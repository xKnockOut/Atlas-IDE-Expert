unit Atlas.Common.Lsp.CompletionGenerics;

// Typargumente nach "<" eines generischen Typs (#450, ARG-051):
// - SiteAt erkennt an den Tokens vor dem Cursor "TObjectList<", "TDictionary<string, " usw. und zählt die
//   Kommas für den aktiven Typparameter (wie #436). Ob der Name davor wirklich ein generischer Typ ist, klärt
//   die Namensauflösung (Owner); "if A < B" bleibt so ein Vergleich.
// - Params liest die Typparameter samt Constraints aus der Deklaration ("TFoo<K; V: class, constructor>").
// - Apply behält nur Typen, die die Constraints erfüllen: class nur Klassen, record nur Records,
//   Aufzählungen und Grundtypen mit Wertsemantik, constructor nur Klassen mit parameterlosem Konstruktor, ein
//   Typ-Constraint nur Typen, die ihn implementieren bzw. davon abgeleitet sind. Jeder Eintrag trägt den
//   Typparameter, den Constraint, einen Code für die Erklärung (classes, values, constructible,
//   implements:IFoo, descends:TBasis) und die ausgeblendeten Arten (classes, records, interfaces, enums,
//   basic) für Überschrift und Fußzeile im Plugin. Grundtypen kommen dazu, wenn kein Constraint sie
//   ausschließt.

interface

uses
  System.SysUtils,
  System.Math,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  TGenericArgSite = record
    Found: Boolean;
    /// <summary>Position des Typnamens vor "&lt;".</summary>
    OwnerPosition: TTextPosition;
    /// <summary>Aktiver Typparameter, 0-basiert.</summary>
    Parameter: Integer;
  end;

  TGenericParam = record
    Name: string;
    /// <summary>Constraints wie im Quelltext, z. B. ['class', 'constructor'] oder ['IComparable'].</summary>
    Constraints: TArray<string>;
  end;

  /// <summary>Art eines Typarguments für die Constraints.</summary>
  TTypeArgKind = (Unknown, Class_, Record_, Interface_, Enum, Basic);

  TCompletionGenerics = class
  public const
    /// <summary>Grundtypen mit Wertsemantik (record-Constraint).</summary>
    ValueTypes: array[0..18] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
      'Byte', 'Word', 'ShortInt', 'SmallInt', 'Double', 'Single', 'Extended', 'Currency', 'Char', 'AnsiChar',
      'WideChar', 'Boolean', 'TDateTime');
    /// <summary>Weitere Grundtypen ohne Constraint.</summary>
    OtherBasicTypes: array[0..2] of string = ('string', 'Variant', 'Pointer');
  public
    /// <summary>Offenes "&lt;" eines Typnamens vor dem Token ALast (das letzte vor dem angefangenen Namen).
    /// </summary>
    class function SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): TGenericArgSite; static;
    /// <summary>Typparameter aus dem Kopf ab ALine/ACharacter (Name der Deklaration), z. B.
    /// "TFoo&lt;K; V: class&gt; = class"; leer ohne spitze Klammern.</summary>
    class function Params(const ALines: TArray<string>; ALine, ACharacter: Integer): TArray<TGenericParam>; static;
    /// <summary>Erklärungscode zu AConstraints: classes, values, constructible, implements:X, descends:X, ''.
    /// AInterface: der Typ-Constraint ist ein Interface.</summary>
    class function HintCode(const AConstraints: TArray<string>; AInterface: Boolean): string; static;
    /// <summary>Erfüllt ein Typ der Art AKind die Constraints? ASatisfiesType prüft einen Typ-Constraint,
    /// AConstructible den parameterlosen Konstruktor.</summary>
    class function Allowed(AKind: TTypeArgKind; const AConstraints: TArray<string>;
      const ASatisfiesType: TFunc<string, Boolean>; const AConstructible: TFunc<Boolean>): Boolean; static;
    /// <summary>Einträge nach den Constraints filtern und beschriften (siehe oben). AOwner ist der aufgelöste
    /// generische Typ, AParameter der aktive Typparameter.</summary>
    class function Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      const AOwner: TResolvedSymbol; const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Files,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.FuzzyMatch;

const
  MaxAncestorDepth = 32;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Name ohne Typargumente und ohne Unit davor: "Generics.IComparer&lt;T&gt;" → "IComparer".</summary>
function PlainName(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ TCompletionGenerics }

class function TCompletionGenerics.SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): TGenericArgSite;
var
  Index, Depth, Commas, Before: Integer;
  Token: TPascalToken;
begin
  Result := Default(TGenericArgSite);
  Depth := 0;
  Commas := 0;
  Index := ALast;
  if (Index >= 0) and IsTrivia(ATokens[Index]) then
    Index := PreviousIndex(ATokens, Index);
  while Index >= 0 do
  begin
    Token := ATokens[Index];
    if Token.IsSymbol('>') then
      Inc(Depth)
    else if Token.IsSymbol('<') then
    begin
      if Depth = 0 then
      begin
        Before := PreviousIndex(ATokens, Index);
        if (Before >= 0) and (ATokens[Before].Kind = TPascalTokenKind.Identifier) then
        begin
          Result.Found := True;
          Result.OwnerPosition := ATokens[Before].StartPos;
          Result.Parameter := Commas;
        end;
        Exit;
      end;
      Dec(Depth);
    end
    else if Token.IsSymbol(',') then
    begin
      if Depth = 0 then
        Inc(Commas);
    end
    // Nur, was in einer Typargumentliste stehen kann: Namen, Punkte und string.
    else if not ((Token.Kind = TPascalTokenKind.Identifier) or Token.IsSymbol('.') or Token.IsKeyword('string')) then
      Exit;
    Index := PreviousIndex(ATokens, Index);
  end;
end;

class function TCompletionGenerics.Params(const ALines: TArray<string>; ALine,
  ACharacter: Integer): TArray<TGenericParam>;
var
  Text, Inner, Group, NamesText, Name: string;
  Line, Index, Depth, Open, Close, ColonAt: Integer;
  Param: TGenericParam;
  Constraint: string;
begin
  Result := nil;
  // Kopf ab dem Namen bis zur schließenden spitzen Klammer, auch über mehrere Zeilen.
  Text := '';
  for Line := ALine to Min(High(ALines), ALine + 20) do
  begin
    if Line = ALine then
      Text := Text + Copy(ALines[Line], ACharacter + 1, MaxInt)
    else
      Text := Text + ' ' + ALines[Line];
    if Pos('>', Text) > 0 then
      Break;
  end;
  Open := 0;
  for Index := 1 to Length(Text) do
    if Text[Index] = '<' then
    begin
      Open := Index;
      Break;
    end
    else if not CharInSet(Text[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', ' ', #9]) then
      Exit;
  if Open = 0 then
    Exit;
  Depth := 0;
  Close := 0;
  for Index := Open to Length(Text) do
    if Text[Index] = '<' then
      Inc(Depth)
    else if Text[Index] = '>' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close := Index;
        Break;
      end;
    end;
  if Close = 0 then
    Exit;
  Inner := Copy(Text, Open + 1, Close - Open - 1);
  // Gruppen durch ";", darin "K, V: class, constructor".
  for Group in Inner.Split([';']) do
  begin
    ColonAt := Pos(':', Group);
    if ColonAt > 0 then
      NamesText := Copy(Group, 1, ColonAt - 1)
    else
      NamesText := Group;
    for Name in NamesText.Split([',']) do
    begin
      if Trim(Name) = '' then
        Continue;
      Param := Default(TGenericParam);
      Param.Name := Trim(Name);
      if ColonAt > 0 then
        for Constraint in Copy(Group, ColonAt + 1, MaxInt).Split([',']) do
          if Trim(Constraint) <> '' then
            Param.Constraints := Param.Constraints + [Trim(Constraint)];
      Result := Result + [Param];
    end;
  end;
end;

class function TCompletionGenerics.HintCode(const AConstraints: TArray<string>; AInterface: Boolean): string;
var
  Constraint: string;
begin
  Result := '';
  for Constraint in AConstraints do
    if SameText(Constraint, 'constructor') then
      Exit('constructible');
  for Constraint in AConstraints do
    if SameText(Constraint, 'class') then
      Exit('classes')
    else if SameText(Constraint, 'record') then
      Exit('values');
  for Constraint in AConstraints do
  begin
    if AInterface then
      Exit('implements:' + Constraint);
    Exit('descends:' + Constraint);
  end;
end;

class function TCompletionGenerics.Allowed(AKind: TTypeArgKind; const AConstraints: TArray<string>;
  const ASatisfiesType: TFunc<string, Boolean>; const AConstructible: TFunc<Boolean>): Boolean;
var
  Constraint: string;
begin
  Result := True;
  for Constraint in AConstraints do
    if SameText(Constraint, 'class') then
      Result := Result and (AKind = TTypeArgKind.Class_)
    else if SameText(Constraint, 'record') then
      Result := Result and (AKind in [TTypeArgKind.Record_, TTypeArgKind.Enum, TTypeArgKind.Basic])
    else if SameText(Constraint, 'constructor') then
      Result := Result and (AKind = TTypeArgKind.Class_) and AConstructible()
    else
      // Typ-Constraint: Klassen, Interfaces (und Records bei Interfaces nicht) prüft die Namensauflösung.
      Result := Result and (AKind in [TTypeArgKind.Class_, TTypeArgKind.Interface_]) and ASatisfiesType(Constraint);
end;

function KindOfSymbol(const ASymbol: TResolvedSymbol): TTypeArgKind;
begin
  case ASymbol.SymbolKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType:
      Result := TTypeArgKind.Class_;
    TIndexSymbolKind.RecordType:
      Result := TTypeArgKind.Record_;
    TIndexSymbolKind.InterfaceType:
      Result := TTypeArgKind.Interface_;
    TIndexSymbolKind.EnumType:
      Result := TTypeArgKind.Enum;
  else
    Result := TTypeArgKind.Unknown;
  end;
end;

/// <summary>Code der Art für die Fußzeile („ausgeblendet: …“).</summary>
function KindCode(AKind: TTypeArgKind): string;
begin
  case AKind of
    TTypeArgKind.Class_:
      Result := 'classes';
    TTypeArgKind.Record_:
      Result := 'records';
    TTypeArgKind.Interface_:
      Result := 'interfaces';
    TTypeArgKind.Enum:
      Result := 'enums';
    TTypeArgKind.Basic:
      Result := 'basic';
  else
    Result := '';
  end;
end;

/// <summary>AType oder ein Vorfahr heißt AName oder listet es als Interface (auch über Vorfahren des Interfaces).
/// </summary>
function SatisfiesType(AResolver: TNameResolver; const AType: TResolvedSymbol; const AName: string): Boolean;
var
  Current, Next, Listed: TResolvedSymbol;
  FromUnit: TUnitIndex;
  Depth, Inner: Integer;
  Ancestor: string;
begin
  Result := False;
  Current := AType;
  for Depth := 0 to MaxAncestorDepth do
  begin
    if SameText(PlainName(Current.Name), PlainName(AName)) then
      Exit(True);
    for Ancestor in Current.Ancestors do
    begin
      if SameText(PlainName(Ancestor), PlainName(AName)) then
        Exit(True);
      // Interface, das von AName abstammt (IFooEx = interface(IFoo)).
      if AResolver.DeclaringUnit(Current, FromUnit) and AResolver.ResolveTypeFrom(FromUnit, Ancestor, Listed) and
        (Listed.SymbolKind = TIndexSymbolKind.InterfaceType) then
        for Inner := 0 to MaxAncestorDepth do
        begin
          if SameText(PlainName(Listed.Name), PlainName(AName)) then
            Exit(True);
          if not AResolver.AncestorOf(Listed, Next) then
            Break;
          Listed := Next;
        end;
    end;
    if not AResolver.AncestorOf(Current, Next) then
      Exit;
    Current := Next;
  end;
end;

/// <summary>Klasse mit parameterlosem Konstruktor: der nächste deklarierte Create hat eine Variante ohne
/// Parameter; ohne eigenen gilt TObject.Create.</summary>
function Constructible(AResolver: TNameResolver; const AType: TResolvedSymbol): Boolean;
var
  Ctor: TResolvedSymbol;
  Params: string;
begin
  if not AResolver.DeclaredMember(AType, 'Create', Ctor) or (Ctor.MinArgs = 0) then
    Exit(True);
  Result := False;
  for Params in Ctor.VariantParams do
    if Params = '' then
      Exit(True);
end;

class function TCompletionGenerics.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AOwner: TResolvedSymbol; const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Text, Code, Hidden, Name: string;
  Lines: TArray<string>;
  Params: TArray<TGenericParam>;
  Param: TGenericParam;
  Item, Current: TCompletionItem;
  Units: TDictionary<string, TUnitIndex>;
  Names: TDictionary<string, Boolean>;
  HiddenKinds: TList<string>;
  UnitInfo: TUnitIndex;
  Symbol: TIndexSymbol;
  Resolved, ConstraintType: TResolvedSymbol;
  Kind: TTypeArgKind;
  Found, IsInterface: Boolean;
  Kept: TList<TCompletionItem>;
  Resolver: TNameResolver;
  Index: Integer;

  function Admit(AKind: TTypeArgKind; const ASymbol: TResolvedSymbol): Boolean;
  var
    Symbol: TResolvedSymbol;
    Lookup: TNameResolver;
  begin
    // Eigene Kopien: anonyme Methoden fangen keine Variablen der umgebenden Routine aus einer lokalen.
    Symbol := ASymbol;
    Lookup := Resolver;
    Result := Allowed(AKind, Param.Constraints,
      function(AName: string): Boolean
      begin
        Result := SatisfiesType(Lookup, Symbol, AName);
      end,
      function: Boolean
      begin
        Result := Constructible(Lookup, Symbol);
      end);
    if not Result and (KindCode(AKind) <> '') and not HiddenKinds.Contains(KindCode(AKind)) then
      HiddenKinds.Add(KindCode(AKind));
  end;

  procedure Label_(var AItem: TCompletionItem);
  begin
    AItem.TypeParam := Param.Name;
    AItem.Constraint := string.Join(', ', Param.Constraints);
    AItem.ConstraintHint := Code;
  end;

  procedure AddBasic(const AName: string);
  var
    Basic: TCompletionItem;
  begin
    if Names.ContainsKey(UpperCase(AName)) or
      (MatchScore(AName, AContext.Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch) then
      Exit;
    if not Admit(TTypeArgKind.Basic, Default(TResolvedSymbol)) then
      Exit;
    Basic := Default(TCompletionItem);
    Basic.Name := AName;
    Basic.Detail := 'System';
    Basic.Kind := KindStruct;
    Label_(Basic);
    Kept.Add(Basic);
    Names.AddOrSetValue(UpperCase(AName), True);
  end;

begin
  Result := AItems;
  Resolver := ARequest.Resolver;
  Params := nil;
  if SameText(AOwner.FileName, ARequest.FileName) then
    Params := TCompletionGenerics.Params(ARequest.Lines, AOwner.SelectionRange.StartPos.Line,
      AOwner.SelectionRange.StartPos.Character)
  else if Assigned(ARequest.ReadText) and ARequest.ReadText(AOwner.FileName, Text) then
  begin
    // Ein #13 am Zeilenende stört Params nicht.
    Lines := Text.Split([#10]);
    Params := TCompletionGenerics.Params(Lines, AOwner.SelectionRange.StartPos.Line,
      AOwner.SelectionRange.StartPos.Character);
  end;
  // Quelle nicht lesbar: die Namen aus dem Index, ohne Constraints.
  if Length(Params) = 0 then
    for Name in AOwner.TypeParams.Split([',']) do
    begin
      Param := Default(TGenericParam);
      Param.Name := Trim(Name);
      Params := Params + [Param];
    end;
  if (AContext.GenericParam < 0) or (AContext.GenericParam > High(Params)) then
    Exit;
  Param := Params[AContext.GenericParam];
  // Ein Typ-Constraint, der ein Interface ist, heißt „implementieren“, sonst „abgeleitet“.
  IsInterface := False;
  if Length(Param.Constraints) > 0 then
    IsInterface := Resolver.DeclaringUnit(AOwner, UnitInfo) and
      Resolver.ResolveTypeFrom(UnitInfo, Param.Constraints[High(Param.Constraints)], ConstraintType) and
      (ConstraintType.SymbolKind = TIndexSymbolKind.InterfaceType);
  Code := HintCode(Param.Constraints, IsInterface);
  Units := TDictionary<string, TUnitIndex>.Create;
  Names := TDictionary<string, Boolean>.Create;
  HiddenKinds := TList<string>.Create;
  Kept := TList<TCompletionItem>.Create;
  try
    for Item in AItems do
    begin
      // Art aus dem Index, über Datei und Namensposition des Eintrags.
      Found := False;
      Resolved := Default(TResolvedSymbol);
      if Item.SourceFile <> '' then
      begin
        if not Units.TryGetValue(UpperCase(Item.SourceFile), UnitInfo) then
        begin
          // Die eigene Unit aus dem Baum, sie steht vielleicht noch nicht (aktuell) im Index.
          if SameText(Item.SourceFile, ARequest.FileName) and (ARequest.Tree <> nil) then
            UnitInfo := ARequest.UnitIndex
          else if (ARequest.Index = nil) or not TIndexFiles.UnitOf(ARequest.Index, Item.SourceFile, UnitInfo) then
            UnitInfo := Default(TUnitIndex);
          Units.Add(UpperCase(Item.SourceFile), UnitInfo);
        end;
        for Symbol in UnitInfo.Symbols do
          if (Symbol.SelectionRange.StartPos.Line = Item.SourcePosition.Line) and
            (Symbol.SelectionRange.StartPos.Character = Item.SourcePosition.Character) and
            SameText(Symbol.Name, Item.Name) then
          begin
            Resolved := Resolver.SymbolFrom(UnitInfo, Symbol);
            Found := True;
            Break;
          end;
      end;
      if Found then
        Kind := KindOfSymbol(Resolved)
      else if MatchText(Item.Name, ValueTypes) then
        Kind := TTypeArgKind.Basic
      else
        Kind := TTypeArgKind.Unknown;
      // Unbekannte Art (Alias, Typparameter): nur ohne Constraint.
      if (Kind = TTypeArgKind.Unknown) and (Length(Param.Constraints) > 0) then
        Continue;
      if (Kind <> TTypeArgKind.Unknown) and not Admit(Kind, Resolved) then
        Continue;
      Current := Item;
      Label_(Current);
      Kept.Add(Current);
      Names.AddOrSetValue(UpperCase(Item.Name), True);
    end;
    for Name in ValueTypes do
      AddBasic(Name);
    if Length(Param.Constraints) = 0 then
      for Name in OtherBasicTypes do
        AddBasic(Name);
    Hidden := string.Join(',', HiddenKinds.ToArray);
    Result := Kept.ToArray;
    // Ausgeblendete Arten an jedem Eintrag; das Plugin liest sie am ersten.
    for Index := 0 to High(Result) do
      Result[Index].HiddenKinds := Hidden;
  finally
    Kept.Free;
    HiddenKinds.Free;
    Names.Free;
    Units.Free;
  end;
end;

end.
