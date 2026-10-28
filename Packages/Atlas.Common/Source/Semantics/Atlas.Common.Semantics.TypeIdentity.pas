unit Atlas.Common.Semantics.TypeIdentity;

// Gleichheit zweier Typen aus dem Quelltext (#1324). Regeln, die Typen als
// Text verglichen, meldeten Abweichungen in Code, den Delphi übersetzt:
// IUnknown gegen IInterface, Longint gegen Integer, X.ITestResult gegen
// ITestResult, Kommentare und Direktiven im Typtext. Verglichen wird hier
// der Typ, nicht der Text:
//   - Clean: Typtext ohne Kommentare, Direktiven, Leerraum und &-Escape.
//   - BuiltinName: eingebaute Aliase der Unit System auf ihr Ziel
//     (Longint → Integer, Int32 → Integer, LongWord → Cardinal,
//     IUnknown → IInterface, UnicodeString → string, Real → Double …).
//   - Mit Namensauflösung (Compare mit zwei TTypeChainResolver): Jede
//     Namenskette (A.B.C) wird aufgelöst und Aliase "type A = B" bis zum
//     Ziel verfolgt, über Units hinweg; "type A = type B" ist ein eigener
//     Typ und bleibt stehen. Zwei aufgelöste Namen sind gleich, wenn Unit,
//     umgebender Typ und Name gleich sind. Lässt sich ein Name nicht
//     auflösen, zählt nur sein letzter Teil (Classes.TCollection =
//     TCollection), und ein Unterschied an dieser Stelle heißt Unknown.
// Typargumente, Arrays, Mengen und Zeiger werden Teil für Teil verglichen.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Löst die Namenskette ANames eines Typtexts (Kunden.TKunde → ['Kunden', 'TKunde']) dort auf, wo der
  /// Typ steht; False, wenn sie unbekannt ist.</summary>
  TTypeChainResolver = reference to function(const ANames: TArray<string>; out AType: TResolvedSymbol): Boolean;

  /// <summary>Ergebnis von TTypeIdentity.Compare: gleich, sicher verschieden oder offen, weil ein Name an einer
  /// abweichenden Stelle nicht aufzulösen ist.</summary>
  TTypeMatch = (Same, Different, Unknown);

  TTypeIdentity = record
  private type
    /// <summary>Ein Teil eines zerlegten Typtexts: Name (kleingeschrieben, ohne Unit) bzw. Symbol und, wenn der Name
    /// aufgelöst ist, Unit samt umgebendem Typ; Known sagt, ob der Name sicher bekannt ist.</summary>
    TPart = record
      Text: string;
      Origin: string;
      IsName: Boolean;
      Known: Boolean;
    end;
  private
    class function Parts(const AText: string; const AResolve: TTypeChainResolver; AResolver: TNameResolver;
      ADepth: Integer): TArray<TPart>; static;
    class function NamePart(const ANames: TArray<string>; const AResolve: TTypeChainResolver;
      AResolver: TNameResolver; ADepth: Integer): TArray<TPart>; static;
    class function Followed(const AType: TResolvedSymbol; AResolver: TNameResolver; ADepth: Integer;
      out AParts: TArray<TPart>): Boolean; static;
    class function CompareParts(const ALeft, ARight: TArray<TPart>): TTypeMatch; static;
  public
    /// <summary>ATypeText ohne Kommentare, Direktiven, &amp;-Escape und überflüssigen Leerraum:
    /// "System . &amp;string {x}" → "System.string", "array of  Byte" → "array of Byte".</summary>
    class function Clean(const ATypeText: string): string; static;
    /// <summary>Ziel des eingebauten Alias AName der Unit System (Longint → Integer, IUnknown → IInterface …);
    /// sonst AName unverändert.</summary>
    class function BuiltinName(const AName: string): string; static;
    /// <summary>Ist "type A = type B" (eigener Typ) die Deklaration ASignature eines Alias?</summary>
    class function IsDistinctAlias(const ASignature: string): Boolean; static;
    /// <summary>Gleich ohne Namensauflösung: Clean, eingebaute Aliase, ohne Unit-Qualifizierer. Verschiedene
    /// Namen gelten als verschiedene Typen.</summary>
    class function Same(const ALeft, ARight: string): Boolean; overload; static;
    /// <summary>Vergleich mit Namensauflösung: ALeft wird mit AResolveLeft aufgelöst, ARight mit AResolveRight;
    /// AResolver verfolgt Aliase aus anderen Units.</summary>
    class function Compare(const ALeft, ARight: string; const AResolveLeft, AResolveRight: TTypeChainResolver;
      AResolver: TNameResolver): TTypeMatch; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

const
  // Wie weit Aliase verfolgt werden (Schutz vor Zyklen A = B, B = A).
  cMaxDepth = 16;
  // Eingebaute Aliase der Unit System als Paare Alias, Ziel. LongInt und LongWord sind unter Windows dieselben
  // Typen wie Integer und Cardinal.
  cBuiltinAliases: array[0..33] of string = (
    'LongInt', 'Integer',
    'Int32', 'Integer',
    'FixedInt', 'Integer',
    'LongWord', 'Cardinal',
    'UInt32', 'Cardinal',
    'FixedUInt', 'Cardinal',
    'Int8', 'ShortInt',
    'UInt8', 'Byte',
    'Int16', 'SmallInt',
    'UInt16', 'Word',
    'IntPtr', 'NativeInt',
    'UIntPtr', 'NativeUInt',
    'UnicodeString', 'string',
    'IUnknown', 'IInterface',
    'Real', 'Double',
    'Char', 'WideChar',
    'PChar', 'PWideChar');

{ TTypeIdentity }

class function TTypeIdentity.Clean(const ATypeText: string): string;
var
  mToken: TPascalToken;
  mText: string;
begin
  Result := '';
  for mToken in TPascalLexer.Tokenize(ATypeText) do
  begin
    if mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    mText := mToken.Text;
    if mToken.Kind = TPascalTokenKind.Identifier then
      mText := TPascalLexer.PlainName(mText);
    // Zwischen zwei Wörtern bleibt ein Leerzeichen (array of Byte), sonst keins (TList<Integer>).
    if (Result <> '') and (mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword,
      TPascalTokenKind.Number]) and CharInSet(Result[Length(Result)], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Result := Result + ' ';
    Result := Result + mText;
  end;
end;

class function TTypeIdentity.BuiltinName(const AName: string): string;
var
  mIndex: Integer;
begin
  mIndex := 0;
  while mIndex < High(cBuiltinAliases) do
  begin
    if SameText(AName, cBuiltinAliases[mIndex]) then
      Exit(cBuiltinAliases[mIndex + 1]);
    Inc(mIndex, 2);
  end;
  Result := AName;
end;

class function TTypeIdentity.IsDistinctAlias(const ASignature: string): Boolean;
var
  mEquals: Integer;
begin
  mEquals := Pos('=', ASignature);
  Result := (mEquals > 0) and StartsText('type ', Clean(Copy(ASignature, mEquals + 1, MaxInt)) + ' ');
end;

class function TTypeIdentity.Followed(const AType: TResolvedSymbol; AResolver: TNameResolver; ADepth: Integer;
  out AParts: TArray<TPart>): Boolean;
var
  mUnit: TUnitIndex;
  mTarget, mBody: string;
  mResolver: TNameResolver;
begin
  // Nur ein schlichter Alias A = B bzw. A = B<C> wird verfolgt; Zeiger (^B), Mengen, Arrays und A = type B
  // bleiben eigene Typen.
  AParts := nil;
  Result := False;
  if AType.Builtin or (AType.SymbolKind <> TIndexSymbolKind.TypeAlias) or (AType.TypeName = '') or
    (ADepth >= cMaxDepth) or IsDistinctAlias(AType.Signature) or (AResolver = nil) or
    not AResolver.DeclaringUnit(AType, mUnit) then
    Exit;
  mTarget := AType.TypeName;
  if AType.TypeArgs <> '' then
    mTarget := mTarget + '<' + AType.TypeArgs + '>';
  mBody := Clean(Copy(AType.Signature, Pos('=', AType.Signature) + 1, MaxInt));
  if not SameText(mBody, Clean(mTarget)) then
    Exit;
  mResolver := AResolver;
  AParts := Parts(mTarget,
    function(const ANames: TArray<string>; out AResolved: TResolvedSymbol): Boolean
    begin
      Result := mResolver.ResolveTypeTextFrom(mUnit, string.Join('.', ANames), AResolved);
    end, AResolver, ADepth + 1);
  Result := True;
end;

class function TTypeIdentity.NamePart(const ANames: TArray<string>; const AResolve: TTypeChainResolver;
  AResolver: TNameResolver; ADepth: Integer): TArray<TPart>;
var
  mType: TResolvedSymbol;
  mPart: TPart;
begin
  mPart.IsName := True;
  mPart.Origin := '';
  mPart.Known := False;
  if Assigned(AResolve) and AResolve(ANames, mType) and mType.IsType then
  begin
    if Followed(mType, AResolver, ADepth, Result) then
      Exit;
    mPart.Text := LowerCase(BuiltinName(mType.Name));
    mPart.Known := True;
    if not mType.Builtin and not SameText(mType.UnitName, 'System') then
    begin
      mPart.Origin := LowerCase(mType.UnitName);
      if mType.Container <> '' then
        mPart.Origin := mPart.Origin + '.' + LowerCase(mType.Container);
    end;
  end
  else
  begin
    mPart.Text := LowerCase(BuiltinName(ANames[High(ANames)]));
    // Eingebaute Typen sind auch ohne Index bekannt.
    mPart.Known := TNameResolver.IsBuiltinTypeName(ANames[High(ANames)]) or
      not SameText(mPart.Text, ANames[High(ANames)]);
  end;
  Result := [mPart];
end;

class function TTypeIdentity.Parts(const AText: string; const AResolve: TTypeChainResolver; AResolver: TNameResolver;
  ADepth: Integer): TArray<TPart>;
var
  mTokens: TArray<TPascalToken>;
  mNames: TArray<string>;
  mIndex: Integer;
  mPart: TPart;
begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(AText);
  mIndex := 0;
  while mIndex <= High(mTokens) do
  begin
    if mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Inc(mIndex);
      Continue;
    end;
    // Namenskette A.B.C; string ist ein Schlüsselwort, steht aber wie ein Name (System.string).
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) or mTokens[mIndex].IsKeyword('string') then
    begin
      mNames := [TPascalLexer.PlainName(mTokens[mIndex].Text)];
      Inc(mIndex);
      while (mIndex + 1 <= High(mTokens)) and mTokens[mIndex].IsSymbol('.') and
        ((mTokens[mIndex + 1].Kind = TPascalTokenKind.Identifier) or mTokens[mIndex + 1].IsKeyword('string')) do
      begin
        mNames := mNames + [TPascalLexer.PlainName(mTokens[mIndex + 1].Text)];
        Inc(mIndex, 2);
      end;
      Result := Result + NamePart(mNames, AResolve, AResolver, ADepth);
      Continue;
    end;
    mPart.Text := LowerCase(mTokens[mIndex].Text);
    mPart.Origin := '';
    mPart.IsName := False;
    mPart.Known := True;
    Result := Result + [mPart];
    Inc(mIndex);
  end;
end;

class function TTypeIdentity.CompareParts(const ALeft, ARight: TArray<TPart>): TTypeMatch;
var
  mIndex: Integer;
begin
  if Length(ALeft) <> Length(ARight) then
    Exit(TTypeMatch.Different);
  Result := TTypeMatch.Same;
  for mIndex := 0 to High(ALeft) do
  begin
    if ALeft[mIndex].IsName <> ARight[mIndex].IsName then
      Exit(TTypeMatch.Different);
    if ALeft[mIndex].Text <> ARight[mIndex].Text then
    begin
      // Ein unbekannter Name kann ein Alias des anderen sein.
      if ALeft[mIndex].IsName and (not ALeft[mIndex].Known or not ARight[mIndex].Known) then
        Result := TTypeMatch.Unknown
      else
        Exit(TTypeMatch.Different);
    end
    else if (ALeft[mIndex].Origin <> '') and (ARight[mIndex].Origin <> '') and
      (ALeft[mIndex].Origin <> ARight[mIndex].Origin) then
      // Gleicher Name aus verschiedenen Units: Vcl.Graphics.TBitmap ist nicht FMX.Graphics.TBitmap.
      Exit(TTypeMatch.Different);
  end;
end;

class function TTypeIdentity.Same(const ALeft, ARight: string): Boolean;
begin
  Result := CompareParts(Parts(ALeft, nil, nil, 0), Parts(ARight, nil, nil, 0)) = TTypeMatch.Same;
end;

class function TTypeIdentity.Compare(const ALeft, ARight: string; const AResolveLeft,
  AResolveRight: TTypeChainResolver; AResolver: TNameResolver): TTypeMatch;
begin
  // Gleicher Text ohne Kommentare ist immer derselbe Typ; die Auflösung braucht es nur bei Unterschieden.
  if SameText(Clean(ALeft), Clean(ARight)) then
    Exit(TTypeMatch.Same);
  Result := CompareParts(Parts(ALeft, AResolveLeft, AResolver, 0), Parts(ARight, AResolveRight, AResolver, 0));
end;

end.
