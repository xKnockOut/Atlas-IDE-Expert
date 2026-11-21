unit Atlas.Common.Pascal.Signatures;

// Köpfe von Routinen und prozeduralen Typen aus den Token lesen und als Text schreiben: Schlüsselwort, Name,
// Parameter (Modifizierer, Name, Typ, Standardwert), Ergebnistyp, Direktiven; Parameterliste und Kopf als Text,
// Verwendungen eines Namens in einem Tokenbereich, Ende des Rumpfs. Prüfregeln, Namensauflösung und Refactorings
// (Signatur ändern, Überladungen) bauen darauf auf; geändert wird hier nichts.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TSignatureParameter = record
    /// <summary>const, var, out, constref, auch mit Attribut wie "[ref] const"; '' ohne.</summary>
    Modifier: string;
    Name: string;
    /// <summary>'' bei untypisierten Parametern (var Buffer).</summary>
    TypeName: string;
    /// <summary>Standardwert als Quelltext; '' ohne.</summary>
    DefaultValue: string;
    /// <summary>Gruppe in der alten Liste (A, B: Integer ist eine Gruppe); -1 bei neuen Parametern. Nur
    /// Parameter derselben Gruppe werden wieder zusammengefasst.</summary>
    Group: Integer;
    /// <summary>Wie in der Deklaration: "const A: Integer = 0"; AWithDefault False ohne Standardwert.</summary>
    function Text(AWithDefault: Boolean): string;
  end;

  /// <summary>Kopf einer Routine; Token-Indizes in der Tokenliste der Datei, -1 = fehlt.</summary>
  TSignatureHeader = record
    /// <summary>Erstes Token: class bzw. procedure, function, constructor, destructor.</summary>
    StartToken: Integer;
    NameToken: Integer;
    OpenToken: Integer;
    CloseToken: Integer;
    /// <summary>";" hinter Parametern und Ergebnistyp.</summary>
    EndToken: Integer;
    /// <summary>";" hinter der letzten Direktive (= EndToken ohne Direktiven).</summary>
    LastToken: Integer;
    /// <summary>procedure, function, constructor oder destructor in Kleinschreibung.</summary>
    Keyword: string;
    IsClass: Boolean;
    /// <summary>Name wie im Kopf, beim Rumpf mit Typ (TFoo.Bar).</summary>
    QualifiedName: string;
    ResultType: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Direktiven in Kleinschreibung samt Argument ("message wm_paint").</summary>
    Directives: TArray<string>;
    function IsFunction: Boolean;
    function HasDirective(const ADirective: string): Boolean;
    /// <summary>Typen der Parameter in Reihenfolge.</summary>
    function ParamTypes: TArray<string>;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Wie ein Verweis auf die Routine verwendet wird.</summary>
  TSignatureUse = (Call, Pointer_, Accessor);
  {$SCOPEDENUMS OFF}

  TPascalSignatures = class
  public
    /// <summary>Parameter aus dem Text zwischen den Klammern.</summary>
    class function ParseParameters(const AText: string): TArray<TSignatureParameter>; static;
    /// <summary>Kopf zur Routine, deren Name bei ANameToken steht; False, wenn dort keine beginnt.</summary>
    class function ReadHeader(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      out AHeader: TSignatureHeader): Boolean; static;
    /// <summary>Kopf eines prozeduralen Typs (TFooEvent = procedure(...) of object); ANameToken ist der
    /// Typname.</summary>
    class function ReadProcedureType(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      out AHeader: TSignatureHeader): Boolean; static;
    /// <summary>"(A: Integer; const B: string)" bzw. '' ohne Parameter; Parameter, die schon vorher
    /// zusammenstanden (A, B: Integer), bleiben zusammen.</summary>
    class function ParameterList(const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string;
      static;
    /// <summary>Art der Verwendung des Bezeichners ANameToken. AHasRequired: Die alte Signatur hat Parameter
    /// ohne Standardwert (ohne Klammern ist es dann kein Aufruf).</summary>
    class function UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      AHasRequired: Boolean): TSignatureUse;
      static;
    /// <summary>Verwendungen des Namens AName (ohne Punkt davor) in Token AFirst bis ALast.</summary>
    class function Uses_(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const AName: string): TArray<Integer>; static;
    /// <summary>Letztes Token der Routine (";" hinter end), deren Kopf bei AHeader steht; -1 ohne Rumpf.</summary>
    class function BodyEnd(ATree: TSyntaxTree; const AHeader: TSignatureHeader): Integer; static;
    /// <summary>Kopf als Text mit neuer Parameterliste, ohne Direktiven, mit ";".</summary>
    class function HeaderText(const AHeader: TSignatureHeader; const AQualifiedName: string;
      const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string; static;
    /// <summary>Direktiven, die die alte Überladung übernimmt (Aufrufkonvention, static, inline …), je mit
    /// " name;"; virtual nur mit AVirtual.</summary>
    class function OverloadDirectives(const AHeader: TSignatureHeader; AVirtual: Boolean): string; static;
    /// <summary>Steht in ATokens an AIndex das Symbol ASymbol? False außerhalb des Arrays.</summary>
    class function SymbolAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ASymbol: string): Boolean;
      static;
    /// <summary>Passende schließende Klammer zu AOpen ("(" oder "[" oder "&lt;"); -1 ohne.</summary>
    class function ClosingBracket(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer; static;
    /// <summary>Text von Token AFirst bis einschließlich ALast; '' bei leerem Bereich.</summary>
    class function TokensText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
      static;
    /// <summary>Erstes Token hinter den Typargumenten "&lt;…&gt;" ab AIndex; AIndex, wenn dort keine stehen.</summary>
    class function SkipGenerics(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines;

const
  cRoutineWords: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  cModifierWords: array[0..3] of string = ('const', 'var', 'out', 'constref');
  cDirectiveWords: array[0..26] of string = ('overload', 'override', 'virtual', 'dynamic', 'abstract', 'reintroduce',
    'static', 'inline', 'final', 'cdecl', 'stdcall', 'register', 'pascal', 'safecall', 'winapi', 'message',
    'deprecated', 'platform', 'library', 'experimental', 'assembler', 'forward', 'external', 'varargs', 'dispid',
    'unsafe', 'export');
  // Diese Direktiven gehören zur virtuellen Kette bzw. zur Deklaration und gehen nicht auf die alte Überladung über.
  cChainWords: array[0..7] of string = ('overload', 'override', 'virtual', 'dynamic', 'abstract', 'reintroduce',
    'message', 'final');

function IsWord(const AToken: TPascalToken; const AWords: array of string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (IndexText(AToken.Text, AWords) >= 0);
end;

function IsSymbolAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ASymbol: string): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ATokens)) and ATokens[AIndex].IsSymbol(ASymbol);
end;

/// <summary>Passende schließende Klammer zu AOpen ("(" oder "[" oder "&lt;"); -1 ohne.</summary>
function Matching(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  mDepth: Integer;
  mOpening, mClosing: string;
begin
  mOpening := ATokens[AOpen].Text;
  if mOpening = '(' then
  begin
    mClosing := ')';
  end
  else if mOpening = '[' then
  begin
    mClosing := ']';
  end
  else
  begin
    mClosing := '>';
  end;
  mDepth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(mOpening) then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(mClosing) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Text von Token AFirst bis einschließlich ALast.</summary>
function SliceText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
begin
  if (AFirst < 0) or (ALast < AFirst) then
  begin
    Exit('');
  end;
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

/// <summary>Stelle von ADelimiter außerhalb von Klammern und Zeichenketten; 0 ohne.</summary>
function TopLevelPos(const AText: string; ADelimiter: Char): Integer;
var
  mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  mDepth := 0;
  mQuoted := False;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted then
      case AText[mIndex] of
        '(', '[', '<':
          Inc(mDepth);
        ')', ']', '>':
          Dec(mDepth);
      else
        if (AText[mIndex] = ADelimiter) and (mDepth = 0) then
        begin
          Exit(mIndex);
        end;
      end;
  end;
  Result := 0;
end;

{ TSignatureParameter }

function TSignatureParameter.Text(AWithDefault: Boolean): string;
begin
  Result := Name;
  if Modifier <> '' then
  begin
    Result := Modifier + ' ' + Result;
  end;
  if TypeName <> '' then
  begin
    Result := Result + ': ' + TypeName;
  end;
  if AWithDefault and (DefaultValue <> '') then
  begin
    Result := Result + ' = ' + DefaultValue;
  end;
end;

{ TSignatureHeader }

function TSignatureHeader.IsFunction: Boolean;
begin
  Result := Keyword = 'function';
end;

function TSignatureHeader.HasDirective(const ADirective: string): Boolean;
var
  mDirective: string;
begin
  for mDirective in Directives do
  begin
    if SameText(mDirective, ADirective) or StartsText(ADirective + ' ', mDirective) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSignatureHeader.ParamTypes: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(Parameters));
  for mIndex := 0 to High(Parameters) do
  begin
    Result[mIndex] := Parameters[mIndex].TypeName;
  end;
end;

/// <summary>Löst Attribute wie [ref] und einen Modifizierer (const, var …) vom Anfang von ARest; sie gehören zum
/// Modifizierer von AParameter.</summary>
procedure ReadModifiers(var ARest: string; var AParameter: TSignatureParameter);
var
  mSpace: Integer;
  mWord: string;
begin
  while StartsStr('[', ARest) and (Pos(']', ARest) > 0) do
  begin
    AParameter.Modifier := Trim(AParameter.Modifier + ' ' + Copy(ARest, 1, Pos(']', ARest)));
    ARest := Trim(Copy(ARest, Pos(']', ARest) + 1, MaxInt));
  end;
  mSpace := Pos(' ', ARest);
  mWord := Copy(ARest, 1, mSpace - 1);
  if (mSpace > 0) and (IndexText(mWord, cModifierWords) >= 0) then
  begin
    AParameter.Modifier := Trim(AParameter.Modifier + ' ' + LowerCase(mWord));
    ARest := Trim(Copy(ARest, mSpace + 1, MaxInt));
  end;
end;

/// <summary>Löst Standardwert und Typ vom Ende von ARest; liefert die Namen davor ("A, B").</summary>
function ReadTypeAndDefault(const ARest: string; var AParameter: TSignatureParameter): string;
var
  mEquals, mColon: Integer;
begin
  Result := ARest;
  mEquals := TopLevelPos(Result, '=');
  if mEquals > 0 then
  begin
    AParameter.DefaultValue := Trim(Copy(Result, mEquals + 1, MaxInt));
    Result := Trim(Copy(Result, 1, mEquals - 1));
  end;
  mColon := TopLevelPos(Result, ':');
  if mColon > 0 then
  begin
    AParameter.TypeName := Trim(Copy(Result, mColon + 1, MaxInt));
    Result := Copy(Result, 1, mColon - 1);
  end;
end;

{ TPascalSignatures }

class function TPascalSignatures.ParseParameters(const AText: string): TArray<TSignatureParameter>;
var
  mGroup, mRest, mName: string;
  mGroupIndex: Integer;
  mParameter: TSignatureParameter;
begin
  Result := nil;
  mGroupIndex := 0;
  for mGroup in TRoutineSignatures.SplitTopLevel(AText, ';') do
  begin
    mRest := TTextLines.CollapseSpace(mGroup);
    if mRest = '' then
    begin
      Continue;
    end;
    mParameter := Default(TSignatureParameter);
    mParameter.Group := mGroupIndex;
    Inc(mGroupIndex);
    ReadModifiers(mRest, mParameter);
    for mName in TRoutineSignatures.SplitTopLevel(ReadTypeAndDefault(mRest, mParameter), ',') do
    begin
      mParameter.Name := Trim(mName);
      if mParameter.Name <> '' then
      begin
        Result := Result + [mParameter];
      end;
    end;
  end;
end;

/// <summary>Liest die Parameterliste ab ACurrent, falls dort "(" steht, und setzt ACurrent dahinter; False, wenn
/// die Klammer offen bleibt.</summary>
function ReadParameterList(const AText: string; const ATokens: TArray<TPascalToken>; var ACurrent: Integer;
  var AHeader: TSignatureHeader): Boolean;
var
  mClose: Integer;
begin
  Result := True;
  if not IsSymbolAt(ATokens, ACurrent, '(') then
  begin
    Exit;
  end;
  mClose := Matching(ATokens, ACurrent);
  Result := mClose >= 0;
  if not Result then
  begin
    Exit;
  end;
  AHeader.OpenToken := ACurrent;
  AHeader.CloseToken := mClose;
  if mClose > FollowingCode(ATokens, ACurrent) then
  begin
    AHeader.Parameters := TPascalSignatures.ParseParameters(SliceText(AText, ATokens, ACurrent + 1, mClose - 1));
  end;
  ACurrent := FollowingCode(ATokens, mClose);
end;

/// <summary>Liest den Ergebnistyp ab ACurrent, falls dort ":" steht, und setzt ACurrent auf das ";" bzw. "of"
/// dahinter; False, wenn keins folgt.</summary>
function ReadResultType(const AText: string; const ATokens: TArray<TPascalToken>; var ACurrent: Integer;
  var AHeader: TSignatureHeader): Boolean;
var
  mNext: Integer;
begin
  Result := True;
  if not IsSymbolAt(ATokens, ACurrent, ':') then
  begin
    Exit;
  end;
  mNext := ACurrent;
  while (mNext >= 0) and (mNext <= High(ATokens)) and not ATokens[mNext].IsSymbol(';') and
    not ATokens[mNext].IsKeyword('of') do
  begin
    mNext := FollowingCode(ATokens, mNext);
  end;
  Result := mNext >= 0;
  if Result then
  begin
    AHeader.ResultType := TTextLines.CollapseSpace(SliceText(AText, ATokens, FollowingCode(ATokens, ACurrent),
      PreviousCode(ATokens, mNext)));
    ACurrent := mNext;
  end;
end;

/// <summary>Liest die Direktiven hinter dem ";" des Kopfes (AHeader.EndToken), je bis zu ihrem ";".</summary>
procedure ReadDirectives(const AText: string; const ATokens: TArray<TPascalToken>; var AHeader: TSignatureHeader);
var
  mNext, mLast: Integer;
begin
  AHeader.Directives := nil;
  mNext := FollowingCode(ATokens, AHeader.EndToken);
  while (mNext >= 0) and IsWord(ATokens[mNext], cDirectiveWords) do
  begin
    mLast := mNext;
    while (mLast >= 0) and not ATokens[mLast].IsSymbol(';') do
    begin
      mLast := FollowingCode(ATokens, mLast);
    end;
    if mLast < 0 then
    begin
      Break;
    end;
    AHeader.Directives := AHeader.Directives + [LowerCase(TTextLines.CollapseSpace(SliceText(AText, ATokens, mNext,
      PreviousCode(ATokens, mLast))))];
    AHeader.LastToken := mLast;
    mNext := FollowingCode(ATokens, mLast);
  end;
end;

/// <summary>Liest Klammern, Ergebnistyp, ";" und Direktiven ab dem Token hinter dem Namen.</summary>
function ReadTail(const AText: string; const ATokens: TArray<TPascalToken>; AAfterName: Integer;
  var AHeader: TSignatureHeader; ADirectives: Boolean): Boolean;
var
  mCurrent: Integer;
begin
  AHeader.OpenToken := -1;
  AHeader.CloseToken := -1;
  mCurrent := AAfterName;
  Result := ReadParameterList(AText, ATokens, mCurrent, AHeader) and
    ReadResultType(AText, ATokens, mCurrent, AHeader);
  if not Result then
  begin
    Exit;
  end;
  // Prozedurale Typen: "of object" bzw. "reference to" gehören vor das ";".
  while (mCurrent >= 0) and (ATokens[mCurrent].IsKeyword('of') or SameText(ATokens[mCurrent].Text, 'object')) do
  begin
    mCurrent := FollowingCode(ATokens, mCurrent);
  end;
  if IsSymbolAt(ATokens, mCurrent, ';') then
  begin
    AHeader.EndToken := mCurrent;
    AHeader.LastToken := mCurrent;
    if ADirectives then
    begin
      ReadDirectives(AText, ATokens, AHeader);
    end;
  end
  else
  begin
    // Kopf ohne ";" am Ende eines prozeduralen Typs in einer Parameterliste o. Ä.
    Result := not ADirectives;
    if Result then
    begin
      AHeader.EndToken := PreviousCode(ATokens, mCurrent);
      AHeader.LastToken := AHeader.EndToken;
    end;
  end;
end;

/// <summary>Token vor einer generischen Typangabe, deren "&gt;" an AIndex steht (TFoo&lt;T&gt;.Bar).</summary>
function BeforeGenericType(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and not ATokens[Result].IsSymbol('<') do
  begin
    Dec(Result);
  end;
  Result := PreviousCode(ATokens, Result);
end;

/// <summary>Rückwärts vom Namen über "TFoo." bzw. "TAussen.TInnen." bis zum Token davor (dem Schlüsselwort);
/// -1, wenn die Kette kein Bezeichner ist.</summary>
function BeforeQualifier(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Integer;
begin
  Result := PreviousCode(ATokens, ANameToken);
  while IsSymbolAt(ATokens, Result, '.') do
  begin
    Result := PreviousCode(ATokens, Result);
    if (Result >= 0) and ATokens[Result].IsSymbol('>') then
    begin
      Result := BeforeGenericType(ATokens, Result);
    end;
    if (Result < 0) or (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit(-1);
    end;
    Result := PreviousCode(ATokens, Result);
  end;
end;

/// <summary>Ist AIndex das "class" von "class procedure", nicht das von "TFoo = class" oder "packed class" direkt
/// vor der ersten Methode?</summary>
function IsClassMethodPrefix(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  Result := (AIndex >= 0) and ATokens[AIndex].IsKeyword('class');
  if Result then
  begin
    mBefore := PreviousCode(ATokens, AIndex);
    Result := not IsSymbolAt(ATokens, mBefore, '=') and
      not ((mBefore >= 0) and SameText(ATokens[mBefore].Text, 'packed'));
  end;
end;

/// <summary>Token hinter generischen Argumenten bzw. Parametern ab AIndex ("&lt;…&gt;"), sonst AIndex; -1, wenn
/// die spitze Klammer offen bleibt.</summary>
function SkipGenericArguments(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  if IsSymbolAt(ATokens, Result, '<') then
  begin
    Result := Matching(ATokens, Result);
    if Result >= 0 then
    begin
      Result := FollowingCode(ATokens, Result);
    end;
  end;
end;

class function TPascalSignatures.ReadHeader(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; out AHeader: TSignatureHeader): Boolean;
var
  mCurrent, mBefore: Integer;
begin
  AHeader := Default(TSignatureHeader);
  mCurrent := -1;
  if (ANameToken >= 0) and (ANameToken <= High(ATokens)) then
  begin
    mCurrent := BeforeQualifier(ATokens, ANameToken);
  end;
  if (mCurrent < 0) or not IsWord(ATokens[mCurrent], cRoutineWords) then
  begin
    Exit(False);
  end;
  AHeader.NameToken := ANameToken;
  AHeader.Keyword := LowerCase(ATokens[mCurrent].Text);
  AHeader.StartToken := mCurrent;
  mBefore := PreviousCode(ATokens, mCurrent);
  if IsClassMethodPrefix(ATokens, mBefore) then
  begin
    AHeader.IsClass := True;
    AHeader.StartToken := mBefore;
  end;
  AHeader.QualifiedName := StringReplace(TTextLines.CollapseSpace(SliceText(AText, ATokens,
    FollowingCode(ATokens, mCurrent), ANameToken)), ' ', '', [rfReplaceAll]);
  // Generische Methode Bar<T>(...): Bleibt die Klammer offen, scheitert ReadTail am fehlenden ";".
  Result := ReadTail(AText, ATokens, SkipGenericArguments(ATokens, FollowingCode(ATokens, ANameToken)), AHeader, True);
end;

class function TPascalSignatures.ReadProcedureType(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; out AHeader: TSignatureHeader): Boolean;
var
  mCurrent: Integer;
begin
  AHeader := Default(TSignatureHeader);
  Result := False;
  if (ANameToken < 0) or (ANameToken > High(ATokens)) then
  begin
    Exit;
  end;
  // TFooEvent = [reference to] procedure(...)
  mCurrent := FollowingCode(ATokens, ANameToken);
  if not IsSymbolAt(ATokens, mCurrent, '=') then
  begin
    Exit;
  end;
  mCurrent := FollowingCode(ATokens, mCurrent);
  if (mCurrent >= 0) and SameText(ATokens[mCurrent].Text, 'reference') then
  begin
    mCurrent := FollowingCode(ATokens, mCurrent);
    if (mCurrent >= 0) and SameText(ATokens[mCurrent].Text, 'to') then
    begin
      mCurrent := FollowingCode(ATokens, mCurrent);
    end;
  end;
  if (mCurrent < 0) or not IsWord(ATokens[mCurrent], ['procedure', 'function']) then
  begin
    Exit;
  end;
  AHeader.Keyword := LowerCase(ATokens[mCurrent].Text);
  AHeader.StartToken := mCurrent;
  // Der "Name" ist das Schlüsselwort: die Klammern folgen direkt.
  AHeader.NameToken := mCurrent;
  AHeader.QualifiedName := ATokens[ANameToken].Text;
  Result := ReadTail(AText, ATokens, FollowingCode(ATokens, mCurrent), AHeader, False);
end;

/// <summary>Steht der Name von AChanges[AIndex] schon weiter vorn in der Liste?</summary>
class function TPascalSignatures.ParameterList(const AParameters: TArray<TSignatureParameter>;
  AWithDefaults: Boolean): string;
var
  mIndex: Integer;
  mGroup: string;
  mCurrent, mNext: TSignatureParameter;

  function Groupable(const A, B: TSignatureParameter): Boolean;
  begin
    Result := (A.Group >= 0) and (A.Group = B.Group) and SameText(A.Modifier, B.Modifier) and
      (A.TypeName = B.TypeName) and
      ((not AWithDefaults) or ((A.DefaultValue = '') and (B.DefaultValue = '')));
  end;

begin
  Result := '';
  mIndex := 0;
  while mIndex <= High(AParameters) do
  begin
    mCurrent := AParameters[mIndex];
    mGroup := mCurrent.Name;
    while (mIndex < High(AParameters)) and Groupable(mCurrent, AParameters[mIndex + 1]) do
    begin
      Inc(mIndex);
      mNext := AParameters[mIndex];
      mGroup := mGroup + ', ' + mNext.Name;
    end;
    mCurrent.Name := mGroup;
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + mCurrent.Text(AWithDefaults);
    Inc(mIndex);
  end;
  if Result <> '' then
  begin
    Result := '(' + Result + ')';
  end;
end;

class function TPascalSignatures.UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  AHasRequired: Boolean): TSignatureUse;
var
  mBefore: Integer;
begin
  mBefore := PreviousCode(ATokens, ANameToken);
  // Über "Self." bzw. "Liste." hinweg nach vorn schauen.
  while IsSymbolAt(ATokens, mBefore, '.') do
  begin
    mBefore := PreviousCode(ATokens, mBefore);
    if mBefore >= 0 then
    begin
      mBefore := PreviousCode(ATokens, mBefore);
    end;
  end;
  if (mBefore >= 0) and IsWord(ATokens[mBefore], ['read', 'write', 'stored', 'add', 'remove']) then
  begin
    Result := TSignatureUse.Accessor;
  end
  else if IsSymbolAt(ATokens, mBefore, '@') then
  begin
    Result := TSignatureUse.Pointer_;
  end
  else if IsSymbolAt(ATokens, SkipGenericArguments(ATokens, FollowingCode(ATokens, ANameToken)), '(') then
  begin
    Result := TSignatureUse.Call;
  end
  // Ohne Klammern: Aufruf nur, wenn die Routine ohne Argumente aufrufbar ist und nicht zugewiesen wird.
  else if AHasRequired or IsSymbolAt(ATokens, mBefore, ':=') then
  begin
    Result := TSignatureUse.Pointer_;
  end
  else
  begin
    Result := TSignatureUse.Call;
  end;
end;

/// <summary>Klammern eines Aufrufs hinter ANameToken (AOpen -1 ohne Klammern) und die alten Argumente; False, wenn
/// die Klammer offen bleibt.</summary>
class function TPascalSignatures.Uses_(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const AName: string): TArray<Integer>;
var
  mIndex, mBefore: Integer;
  mText: string;
begin
  Result := nil;
  if AFirst < 0 then
  begin
    Exit;
  end;
  for mIndex := AFirst to ALast do
  begin
    if (mIndex > High(ATokens)) or (ATokens[mIndex].Kind <> TPascalTokenKind.Identifier) then
    begin
      Continue;
    end;
    mText := ATokens[mIndex].Text;
    if StartsStr('&', mText) then
    begin
      mText := Copy(mText, 2, MaxInt);
    end;
    if not SameText(mText, AName) then
    begin
      Continue;
    end;
    mBefore := PreviousCode(ATokens, mIndex);
    if IsSymbolAt(ATokens, mBefore, '.') then
    begin
      Continue;
    end;
    Result := Result + [mIndex];
  end;
end;

function FindRoutine(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mRoot: TSyntaxNode;
  mOffset: Integer;
begin
  mRoot := ANode;
  mOffset := AOffset;
  // Search statt Rekursion; unter ANode nur Knoten, die AOffset enthalten.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if ACandidate = mRoot then
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if (ACandidate.StartOffset > mOffset) or (mOffset > ACandidate.EndOffset) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      // Die äußerste Routine, deren Kopf hier steht.
      if ACandidate.Kind = TSyntaxKind.RoutineDecl then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

class function TPascalSignatures.BodyEnd(ATree: TSyntaxTree; const AHeader: TSignatureHeader): Integer;
var
  mNode: TSyntaxNode;
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mHasBegin: Boolean;
begin
  Result := -1;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mNode := FindRoutine(ATree.Root, mTokens[AHeader.NameToken].Offset);
  if mNode = nil then
  begin
    Exit;
  end;
  mHasBegin := False;
  for mIndex := AHeader.LastToken + 1 to High(mTokens) do
  begin
    if mTokens[mIndex].Offset >= mNode.EndOffset then
    begin
      Break;
    end;
    if mTokens[mIndex].IsKeyword('begin') or mTokens[mIndex].IsKeyword('asm') then
    begin
      mHasBegin := True;
    end;
    Result := mIndex;
  end;
  if not mHasBegin then
  begin
    Exit(-1);
  end;
  // Das ";" hinter end gehört dazu.
  mIndex := FollowingCode(mTokens, Result);
  if IsSymbolAt(mTokens, mIndex, ';') then
  begin
    Result := mIndex;
  end;
end;

class function TPascalSignatures.HeaderText(const AHeader: TSignatureHeader; const AQualifiedName: string;
  const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string;
begin
  Result := AHeader.Keyword + ' ' + AQualifiedName + ParameterList(AParameters, AWithDefaults);
  if AHeader.IsClass then
  begin
    Result := 'class ' + Result;
  end;
  if AHeader.ResultType <> '' then
  begin
    Result := Result + ': ' + AHeader.ResultType;
  end;
  Result := Result + ';';
end;

class function TPascalSignatures.OverloadDirectives(const AHeader: TSignatureHeader; AVirtual: Boolean): string;
var
  mDirective, mWord: string;
begin
  Result := ' overload;';
  for mDirective in AHeader.Directives do
  begin
    mWord := mDirective;
    if Pos(' ', mWord) > 0 then
    begin
      mWord := Copy(mWord, 1, Pos(' ', mWord) - 1);
    end;
    if IndexText(mWord, cChainWords) < 0 then
    begin
      Result := Result + ' ' + mDirective + ';';
    end;
  end;
  if AVirtual then
  begin
    Result := Result + ' virtual;';
  end;
end;


{ TPascalSignatures }

class function TPascalSignatures.SymbolAt(const ATokens: TArray<TPascalToken>; AIndex: Integer;
  const ASymbol: string): Boolean;
begin
  Result := IsSymbolAt(ATokens, AIndex, ASymbol);
end;

class function TPascalSignatures.ClosingBracket(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
begin
  Result := Matching(ATokens, AOpen);
end;

class function TPascalSignatures.TokensText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst,
  ALast: Integer): string;
begin
  Result := SliceText(AText, ATokens, AFirst, ALast);
end;

class function TPascalSignatures.SkipGenerics(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := SkipGenericArguments(ATokens, AIndex);
end;

end.
