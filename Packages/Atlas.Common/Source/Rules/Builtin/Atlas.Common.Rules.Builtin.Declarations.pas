unit Atlas.Common.Rules.Builtin.Declarations;

// Deklaration und Rumpf passen nicht zusammen (#124):
//   declared-not-implemented   Methode im Typ ohne Rumpf (sonst erst E2065)
//   implemented-not-declared   Rumpf TFoo.Bar ohne Deklaration im Typ
//   signature-mismatch         Rumpf und Deklaration gleichen Namens mit
//                              abweichendem Kopf (#996, wie E2037): Parameter
//                              (Anzahl, Name, Typ, const/var/out), Ergebnistyp,
//                              procedure/function, Aufrufkonvention
//   interface-not-implemented  Klasse nennt ein Interface, dem Methoden fehlen
//   field-after-method         Feld nach Methode oder Property im selben
//                              Abschnitt (#986, wie E2169); Korrektur:
//                              Feld an den Anfang verschieben oder var davor
//   overload-directive-missing Gleichnamige Routinen bzw. Methoden eines
//                              Bereichs ohne overload (#987, wie E2254,
//                              E2267) oder mit gleichen Parametern (E2252,
//                              E2301); Korrektur: overload; anhängen
//   duplicate-declaration      Bezeichner im selben Bereich zweimal deklariert
//                              (#988, wie E2004): Parameter und lokale
//                              Deklarationen, Mitglieder eines Typs, die Unit
//                              über interface und implementation, uses
//                              (#1000, wie E2291), bzw. Zuordnung IFoo.Bar = Baz
//                              für ein nicht genanntes Interface (wie E2265).
//                              Geerbte Methoden, Zuordnungen und implements
//                              zählen; bricht die Kette der Vorfahrklassen ab,
//                              bleibt die Regel still (TNameResolver.
//                              MissingInterfaceMembers mit AComplete)
//   variant-record-managed-field
//                              Verwalteter Typ im varianten Teil eines Records
//                              (#1071): String, dynamisches Array, Interface,
//                              Variant oder Record mit solchen Feldern (wie
//                              E2154), verwalteter Record mit class operator
//                              Initialize/Finalize (wie E2418), Typparameter
//                              ohne Einschränkung (wie E2569); ebenso hinter
//                              file of (wie E2155, E2417). Typen über Datei und
//                              Index (Rules.ManagedTypes), unbekannte bleiben
//                              still. Korrekturen: Feld in den festen Teil vor
//                              case, ShortString, record-Einschränkung
//   type-too-large             Statisches Array oder Record ab 2 GB (#1083, wie
//                              E2100), Instanz eines generischen Typs der Datei
//                              ab 2 GB (wie E2543). Die Größe ist eine untere
//                              Grenze aus den Deklarationen (Grenzen über
//                              Semantics.OrdinalConstants, Konstanten und
//                              Aufzählungen der Datei, Records aus dem Index);
//                              Unbekanntes zählt 0. Gemeldet wird nur der
//                              innerste Typ, der die Grenze überschreitet.
//                              E2419 (1 MB) gilt nur für Delphi für .NET.
//   default-parameter          Parameter mit Vorgabewert (#976, Standard aus);
//                              Korrektur: je weggelassenem Standardparameter
//                              eine Überladung, die mit dem Vorgabewert
//                              weiterreicht
//
// Den Abgleich (auch über Überladungen) liefert TClassCompletion.Unmatched aus
// #42; Paare mit abweichendem Kopf ordnet TClassCompletion.Pairs zu. Sie meldet
// nur signature-mismatch, die beiden anderen Regeln finden fehlende Namen. Abstrakte, externe und forward-Methoden, Interfaces und generische
// Typen erzeugen keinen Treffer. Methoden innerhalb von {$IF…}-Blöcken werden
// übergangen, weil der Syntaxbaum auch inaktive Zweige enthält. Bindet die
// Datei Include-Dateien ein, können dort Rümpfe stehen: dann nur mittlere
// Konfidenz (höchstens Warnung).
//
// Korrekturen: "Rumpf erzeugen" (#42) bzw. "Deklaration ergänzen" im
// private-Abschnitt; bei signature-mismatch "Implementierung an die
// Deklaration angleichen" und als zweite Aktion umgekehrt (#100).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Semantics.TypeIdentity;

type
  /// <summary>Vergleicht den Typ ADeclType der Deklaration mit dem Typ ABodyType des Rumpfs (#1324).</summary>
  TSignatureTypeMatch = reference to function(const ADeclType, ABodyType: string): TTypeMatch;

  TDeclaredNotImplementedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TImplementedNotDeclaredRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceNotImplementedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Interfaces, die eine Property der Klasse mit implements übernimmt (Token im Bereich ARange).</summary>
    class function Delegated(const ATokens: TArray<TPascalToken>; const ARange: TTextRange): TArray<string>; static;
  end;

  TSignatureMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Abweichungen des Rumpfs ABody von der Deklaration ADeclaration, z. B. "Betrag ohne const",
    /// "Datum TDateTime statt TDate"; leer, wenn die Köpfe gleich sind. Typen vergleicht TTypeIdentity.Same.
    /// </summary>
    class function Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>; overload; static;
    /// <summary>Wie oben; Typen vergleicht AMatch (#1324). Nur sicher verschiedene Typen zählen als Abweichung.
    /// </summary>
    class function Differences(const ADeclaration, ABody: TSignatureShape;
      const AMatch: TSignatureTypeMatch): TArray<string>; overload; static;
  end;

  TFieldAfterMethodRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TOverloadDirectiveMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TTypeTooLargeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TVariantRecordManagedFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDefaultParameterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  FieldAfterMethodRuleId = 'field-after-method';
  DuplicateDeclarationRuleId = 'duplicate-declaration';
  OverloadDirectiveMissingRuleId = 'overload-directive-missing';
  DefaultParameterRuleId = 'default-parameter';

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Text.Lines;

/// <summary>Zeilen innerhalb von {$IF…}…{$ENDIF}: Element I gilt für Zeile I.</summary>
function ConditionalLines(const AContext: TRuleContext): TArray<Boolean>;
var
  Token: TPascalToken;
  Text: string;
  Depth, Line, LastLine, StartLine: Integer;
begin
  LastLine := 0;
  for Token in AContext.Tree.Tokens do
    LastLine := Token.EndPos.Line;
  SetLength(Result, LastLine + 1);
  Depth := 0;
  StartLine := 0;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Text := UpperCase(Token.Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) then
    begin
      if Depth = 0 then
        StartLine := Token.StartPos.Line;
      Inc(Depth);
    end
    else if (Depth > 0) and (StartsStr('{$ENDIF', Text) or StartsStr('{$IFEND', Text) or
      StartsStr('(*$ENDIF', Text) or StartsStr('(*$IFEND', Text)) then
    begin
      Dec(Depth);
      if Depth = 0 then
        for Line := StartLine to Token.EndPos.Line do
          Result[Line] := True;
    end;
  end;
  // Nicht geschlossener Block: bis zum Dateiende.
  if Depth > 0 then
    for Line := StartLine to LastLine do
      Result[Line] := True;
end;

/// <summary>Bindet die Datei Include-Dateien ein ({$I datei} oder {$INCLUDE datei})?</summary>
function HasIncludes(const AContext: TRuleContext): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  for Token in AContext.Tree.Tokens do
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(Token.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', Text) or StartsStr('{$I ', Text) then
        Exit(True);
    end;
  Result := False;
end;

function IsConditional(const ALines: TArray<Boolean>; const AMethod: TUnmatchedMethod): Boolean;
var
  Line: Integer;
begin
  Line := AMethod.Symbol.Range.StartPos.Line;
  Result := (Line >= 0) and (Line <= High(ALines)) and ALines[Line];
end;

/// <summary>AFix als gleichrangige Alternative markieren, wenn schon andere Korrekturen vorliegen.</summary>
function Alternative(const AFix: TRuleFix; AIsAlternative: Boolean): TRuleFix;
begin
  Result := AFix;
  Result.Alternative := AIsAlternative;
end;

/// <summary>Gehört AMethod zu einem Paar mit abweichendem Kopf? Das meldet signature-mismatch.</summary>
function InPair(const APairs: TArray<TSignaturePair>; const AMethod: TUnmatchedMethod): Boolean;
var
  Pair: TSignaturePair;
begin
  for Pair in APairs do
    if (Pair.Declaration.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) or
      (Pair.Body.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) then
      Exit(True);
  Result := False;
end;

function Confidence(const AContext: TRuleContext): TRuleConfidence;
begin
  if HasIncludes(AContext) then
    Result := TRuleConfidence.Medium
  else
    Result := TRuleConfidence.High;
end;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenAtOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

/// <summary>Steht vor APosition in ihrer Zeile nur Leerraum?</summary>
function BlankBefore(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
begin
  Result := (APosition.Line < Length(ALines)) and (Trim(Copy(ALines[APosition.Line], 1, APosition.Character)) = '');
end;

/// <summary>Steht hinter APosition in ihrer Zeile nur Leerraum oder ein //-Kommentar?</summary>
function BlankAfter(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
var
  Rest: string;
begin
  Result := False;
  if APosition.Line >= Length(ALines) then
    Exit;
  Rest := Trim(Copy(ALines[APosition.Line], APosition.Character + 1, MaxInt));
  Result := (Rest = '') or Rest.StartsWith('//');
end;

{ TDeclaredNotImplementedRule }

function TDeclaredNotImplementedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('declared-not-implemented', TRuleSeverity.Error,
    'Methode ist deklariert, aber nicht implementiert');
end;

procedure TDeclaredNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Pairs: TArray<TSignaturePair>;
  Method: TUnmatchedMethod;
  Action: TCodeAction;
  Fixes: TArray<TRuleFix>;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  Pairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if not Method.Declared or IsConditional(Lines, Method) or InPair(Pairs, Method) then
      Continue;
    Fixes := nil;
    if TClassCompletion.MissingBodies(AContext.Tree, AContext.Text, Method.Symbol.SelectionRange.StartPos, Action) then
      Fixes := [TRuleFix.Create(Action.Title, Action.Edits)];
    AReport.Add(Method.Symbol.SelectionRange, Format('"%s.%s" ist deklariert, aber nicht implementiert',
      [Method.TypeName, Method.Symbol.Name]), Level, Fixes);
  end;
end;

{ TImplementedNotDeclaredRule }

function TImplementedNotDeclaredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('implemented-not-declared', TRuleSeverity.Error,
    'Methodenrumpf ohne Deklaration im Typ');
end;

procedure TImplementedNotDeclaredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Pairs: TArray<TSignaturePair>;
  Method: TUnmatchedMethod;
  Edit: TRuleEdit;
  Fixes: TArray<TRuleFix>;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  Pairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if Method.Declared or IsConditional(Lines, Method) or InPair(Pairs, Method) then
      Continue;
    Fixes := nil;
    if TClassCompletion.AddDeclaration(AContext.Tree, AContext.Text, Method, Edit) then
      Fixes := [TRuleFix.Create(Format('Deklaration von %s in %s ergänzen', [Method.Symbol.Name,
        Method.TypeName]), [Edit])];
    AReport.Add(Method.Symbol.SelectionRange, Format('"%s.%s" hat keine passende Deklaration in %s',
      [Method.TypeName, Method.Symbol.Name, Method.TypeName]), Level, Fixes);
  end;
end;

{ TInterfaceNotImplementedRule }

function TInterfaceNotImplementedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('interface-not-implemented', TRuleSeverity.Error,
    'Interface-Methode fehlt in der Klasse (wie E2291)');
end;

class function TInterfaceNotImplementedRule.Delegated(const ATokens: TArray<TPascalToken>;
  const ARange: TTextRange): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if (ATokens[Index].StartPos.Line >= ARange.StartPos.Line) and (ATokens[Index].EndPos.Line <= ARange.EndPos.Line) and
      SameText(ATokens[Index].Text, 'implements') and (ATokens[Index].Kind = TPascalTokenKind.Identifier) then
    begin
      // implements IFoo, Units.IBar;
      Inc(Index);
      Name := '';
      while (Index <= High(ATokens)) and not ATokens[Index].IsSymbol(';') do
      begin
        if ATokens[Index].IsSymbol(',') then
        begin
          Result := Result + [Name];
          Name := '';
        end
        else if ATokens[Index].Kind <> TPascalTokenKind.Comment then
          Name := Name + ATokens[Index].Text;
        Inc(Index);
      end;
      if Name <> '' then
        Result := Result + [Name];
    end;
    Inc(Index);
  end;
end;

/// <summary>"A", "A und B", "A, B und C".</summary>
function JoinedList(const AItems: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Index = 0 then
      Result := AItems[Index]
    else if Index = High(AItems) then
      Result := Result + ' und ' + AItems[Index]
    else
      Result := Result + ', ' + AItems[Index];
  end;
end;

function BareName(const AText: string): string;
begin
  Result := Trim(AText);
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

/// <summary>Methode AName der Klasse ATypeName (ohne Zuordnungen); Name leer, wenn es keine gibt.</summary>
function OwnMethod(const AUnit: TUnitIndex; const ATypeName, AName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Container, ATypeName) and SameText(Symbol.Name, AName) and
      (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
      Exit(Symbol);
end;

/// <summary>Köpfe aller Methodenzuordnungen (procedure IFoo.Bar = Baz) in Typrümpfen der Datei; Anweisungen
/// werden nicht durchlaufen.</summary>
function ResolutionHeaders(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  Found: TList<TSyntaxNode>;
begin
  Found := TList<TSyntaxNode>.Create;
  try
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.RoutineHeader) and ANode.IsMethodResolution then
          Found.Add(ANode);
        Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]);
      end);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

procedure TInterfaceNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  OwnUnit: TUnitIndex;
  TypeSymbol: TIndexSymbol;
  Header: TSyntaxNode;
  Headers: TArray<TSyntaxNode>;
  TypeName, Ancestor, Prefix: string;
  Missing: TArray<TResolvedSymbol>;
  Member: TResolvedSymbol;
  Names: TList<string>;
  Complete, Listed, Differs: Boolean;
  Own: TIndexSymbol;
  Actions: TClassActionContext;
  Action: TCodeAction;
  Fixes: TArray<TRuleFix>;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  // Ohne Projektindex prüft die Regel nur, was die Datei selbst kennt; unbekannte Vorfahren halten sie still.
  Index := AContext.Index;
  if Index = nil then
    Index := TSymbolIndex.Create;
  Resolver := TNameResolver.Create(Index, AContext.EnsureUnit, AContext.TreeUnits);
  Names := TList<string>.Create;
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      OwnUnit := Resolver.ExtractedUnit(AContext.Tree, AContext.RelativePath);
      Headers := ResolutionHeaders(AContext.Tree);
      Actions := TClassActionContext.Default;
      Actions.Index := Index;
      Actions.Namespaces := AContext.Namespaces;
      Actions.DelphiVersion := AContext.DelphiVersion;
      Actions.Style := AContext.Formatting;
      for TypeSymbol in OwnUnit.Symbols do
      begin
        if (TypeSymbol.Kind <> TIndexSymbolKind.ClassType) or (Length(TypeSymbol.Ancestors) = 0) or
          ((TypeSymbol.SelectionRange.StartPos.Line <= High(Lines)) and Lines[TypeSymbol.SelectionRange.StartPos.Line]) then
          Continue;
        TypeName := TypeSymbol.Name;
        if TypeSymbol.Container <> '' then
          TypeName := TypeSymbol.Container + '.' + TypeName;
        Missing := Resolver.MissingInterfaceMembers(OwnUnit, TypeName, nil,
          Delegated(AContext.Tree.Tokens, TypeSymbol.Range), Complete);
        if Complete and (Length(Missing) > 0) then
        begin
          Names.Clear;
          Differs := False;
          for Member in Missing do
          begin
            // Gleichnamige Methode der Klasse mit anderer Signatur: E2211 an der Methode statt "fehlt".
            Own := OwnMethod(OwnUnit, TypeName, Member.Name);
            if Own.Name <> '' then
            begin
              Differs := True;
              AReport.Add(Own.SelectionRange, Format('%s weicht von der Deklaration in %s ab (wie E2211).',
                [Own.Name, BareName(Member.Container)]), Level);
            end
            else if not Names.Contains(BareName(Member.Container) + '.' + Member.Name) then
              Names.Add(BareName(Member.Container) + '.' + Member.Name);
          end;
          Names.Sort;
          // Bei abweichenden Köpfen fügte die Korrektur eine zweite gleichnamige Methode ein; dann keine.
          Fixes := nil;
          if not Differs then
            for Ancestor in TypeSymbol.Ancestors do
              if TClassActions.ImplementInterface(AContext.Text, TypeSymbol.Range.StartPos.Line, Ancestor, Actions,
                Action) then
                Fixes := Fixes + [Alternative(TRuleFix.Create(Action.Title, Action.Edits), Length(Fixes) > 0)];
          if Names.Count = 1 then
            AReport.Add(TypeSymbol.SelectionRange, Format('%s fehlt in %s (wie E2291).', [Names[0], TypeSymbol.Name]),
              Level, Fixes)
          else if Names.Count > 1 then
            AReport.Add(TypeSymbol.SelectionRange, Format('%s fehlen in %s (wie E2291).',
              [JoinedList(Names.ToArray), TypeSymbol.Name]), Level, Fixes);
        end;
        // Zuordnung "procedure IFoo.Bar = Baz" für ein Interface, das die Klasse nicht nennt; die Zuordnungen
        // sind keine Mitglieder (#849), ihre Stelle steht nur im Baum.
        for Header in Headers do
        begin
          if not SameText(Header.EnclosingTypeName, TypeName) then
            Continue;
          Prefix := BareName(Copy(Header.Name, 1, LastDelimiter('.', Header.Name) - 1));
          Listed := False;
          for Ancestor in TypeSymbol.Ancestors do
            if SameText(BareName(Ancestor), Prefix) then
              Listed := True;
          if not Listed then
            AReport.Add(TTextRange.Create(Header.StartPos, Header.EndPos),
              Format('%s steht nicht in der Interface-Liste von %s (wie E2265).', [Prefix, TypeSymbol.Name]), Level);
        end;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Names.Free;
    Resolver.Free;
  end;
end;

type
  /// <summary>Typvergleich für signature-mismatch (#1324): löst die Typen eines Paars dort auf, wo sie stehen, die
  /// der Deklaration im Typ, die des Rumpfs im implementation-Teil. Ohne Projektindex zählt der Text.</summary>
  TSignatureTypes = class
  private
    FContext: TRuleContext;
    FResolver: TNameResolver;
    FPinned: Boolean;
    function Resolver: TNameResolver;
    function OffsetOf(const APosition: TTextPosition): Integer;
    function ChainAt(AOffset: Integer): TTypeChainResolver;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Vergleich für die Typen von APair.</summary>
    function Matcher(const APair: TSignaturePair): TSignatureTypeMatch;
  end;

/// <summary>Vergleich ohne Namensauflösung: verschiedene Namen sind verschiedene Typen.</summary>
function TextTypeMatch(const ADeclType, ABodyType: string): TTypeMatch;
begin
  if TTypeIdentity.Same(ADeclType, ABodyType) then
    Result := TTypeMatch.Same
  else
    Result := TTypeMatch.Different;
end;

{ TSignatureTypes }

constructor TSignatureTypes.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
end;

destructor TSignatureTypes.Destroy;
begin
  if FPinned then
    FResolver.UnpinTree;
  FResolver.Free;
  inherited Destroy;
end;

function TSignatureTypes.Resolver: TNameResolver;
begin
  // Erst beim ersten abweichenden Typ: Die meisten Paare unterscheiden sich nicht im Typtext.
  if FResolver = nil then
  begin
    FResolver := TNameResolver.Create(FContext.Index, FContext.EnsureUnit, FContext.TreeUnits);
    FResolver.Namespaces := FContext.Namespaces;
    FResolver.PinTree(FContext.Tree, FContext.RelativePath);
    FPinned := True;
  end;
  Result := FResolver;
end;

function TSignatureTypes.OffsetOf(const APosition: TTextPosition): Integer;
var
  mToken: TPascalToken;
begin
  Result := -1;
  for mToken in FContext.Tree.Tokens do
    if mToken.StartPos = APosition then
      Exit(mToken.Offset);
end;

function TSignatureTypes.ChainAt(AOffset: Integer): TTypeChainResolver;
var
  mSelf: TSignatureTypes;
begin
  mSelf := Self;
  Result :=
    function(const ANames: TArray<string>; out AType: TResolvedSymbol): Boolean
    begin
      AType := mSelf.Resolver.ResolveChain(mSelf.FContext.Tree, mSelf.FContext.RelativePath, ANames, AOffset);
      Result := AType.Found;
    end;
end;

function TSignatureTypes.Matcher(const APair: TSignaturePair): TSignatureTypeMatch;
var
  mSelf: TSignatureTypes;
  mDeclaration, mBody: TTypeChainResolver;
begin
  if FContext.Index = nil then
  begin
    Result := TextTypeMatch;
    Exit;
  end;
  mSelf := Self;
  mDeclaration := ChainAt(OffsetOf(APair.Declaration.Symbol.SelectionRange.StartPos));
  mBody := ChainAt(OffsetOf(APair.Body.Symbol.SelectionRange.StartPos));
  Result :=
    function(const ADeclType, ABodyType: string): TTypeMatch
    begin
      Result := TTypeIdentity.Compare(ADeclType, ABodyType, mDeclaration, mBody, mSelf.Resolver);
    end;
end;

{ TSignatureMismatchRule }

function TSignatureMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('signature-mismatch', TRuleSeverity.Error,
    'Implementierung weicht von der Deklaration ab (wie E2037)');
end;

class function TSignatureMismatchRule.Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>;
var
  mMatch: TSignatureTypeMatch;
begin
  // Typisierte Variable: Delphi wählt die Überladung sonst nicht sicher.
  mMatch := TextTypeMatch;
  Result := Differences(ADeclaration, ABody, mMatch);
end;

class function TSignatureMismatchRule.Differences(const ADeclaration, ABody: TSignatureShape;
  const AMatch: TSignatureTypeMatch): TArray<string>;

  function Differs(const ADeclType, ABodyType: string): Boolean;
  begin
    if (ADeclType = '') or (ABodyType = '') then
      Result := (ADeclType <> '') or (ABodyType <> '')
    else
      Result := AMatch(ADeclType, ABodyType) = TTypeMatch.Different;
  end;

  function ConventionOf(const AShape: TSignatureShape): string;
  begin
    Result := AShape.Convention;
    if Result = '' then
      Result := 'register';
  end;

var
  Index: Integer;
  Decl, Body: TShapeParameter;
begin
  Result := nil;
  if (ADeclaration.Kind <> '') and (ABody.Kind <> '') and (ADeclaration.Kind <> ABody.Kind) then
    Result := Result + [Format('%s statt %s', [ABody.Kind, ADeclaration.Kind])];
  if Length(ADeclaration.Parameters) <> Length(ABody.Parameters) then
    Result := Result + [Format('%d statt %d Parameter', [Length(ABody.Parameters), Length(ADeclaration.Parameters)])]
  else
    for Index := 0 to High(ABody.Parameters) do
    begin
      Decl := ADeclaration.Parameters[Index];
      Body := ABody.Parameters[Index];
      if not SameText(Decl.Name, Body.Name) then
        Result := Result + [Format('%s statt %s', [Body.Name, Decl.Name])];
      if Decl.Modifier <> Body.Modifier then
      begin
        if Body.Modifier = '' then
          Result := Result + [Format('%s ohne %s', [Body.Name, Decl.Modifier])]
        else if Decl.Modifier = '' then
          Result := Result + [Format('%s mit %s', [Body.Name, Body.Modifier])]
        else
          Result := Result + [Format('%s %s statt %s', [Body.Name, Body.Modifier, Decl.Modifier])];
      end;
      if Differs(Decl.TypeName, Body.TypeName) then
      begin
        if Body.TypeName = '' then
          Result := Result + [Format('%s ohne Typ statt %s', [Body.Name, Decl.TypeName])]
        else if Decl.TypeName = '' then
          Result := Result + [Format('%s %s statt ohne Typ', [Body.Name, Body.TypeName])]
        else
          Result := Result + [Format('%s %s statt %s', [Body.Name, Body.TypeName, Decl.TypeName])];
      end;
    end;
  if (ADeclaration.Kind = ABody.Kind) and Differs(ADeclaration.ResultType, ABody.ResultType) then
    Result := Result + [Format('Ergebnis %s statt %s', [ABody.ResultType, ADeclaration.ResultType])];
  // Der Rumpf darf die Konvention weglassen; nur eine abweichende Angabe ist ein Fehler.
  if (ABody.Convention <> '') and (ConventionOf(ABody) <> ConventionOf(ADeclaration)) then
    Result := Result + [Format('%s statt %s', [ABody.Convention, ConventionOf(ADeclaration)])];
end;

procedure TSignatureMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Pair: TSignaturePair;
  Changes: TArray<string>;
  Actions: TArray<TCodeAction>;
  Fixes: TArray<TRuleFix>;
  Index: Integer;
  Level: TRuleConfidence;
  mTypes: TSignatureTypes;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  mTypes := TSignatureTypes.Create(AContext);
  try
    for Pair in TClassCompletion.Pairs(AContext.Tree, AContext.Text) do
    begin
      // Bedingte Übersetzung im Kopf ({$IFDEF} in der Parameterliste): Welche Parameter gelten, ist offen (#1324).
      if IsConditional(Lines, Pair.Declaration) or IsConditional(Lines, Pair.Body) or
        Pair.DeclarationShape.Conditional or Pair.BodyShape.Conditional then
        Continue;
      Changes := Differences(Pair.DeclarationShape, Pair.BodyShape, mTypes.Matcher(Pair));
      if Changes = nil then
        Continue;
      Fixes := nil;
      // refactoring.syncSignatures aus (#100): die Meldung bleibt, die Angleich-Aktionen entfallen.
      if not AContext.NoSignatureSync and TClassCompletion.PairFixes(AContext.Tree, AContext.Text, Pair, Actions) then
        for Index := 0 to High(Actions) do
          Fixes := Fixes + [Alternative(TRuleFix.Create(Actions[Index].Title, Actions[Index].Edits), Index > 0)];
      AReport.Add(Pair.Body.Symbol.SelectionRange, Format('%s weicht von der Deklaration ab: %s (wie E2037).',
        [Pair.Body.Symbol.Name, string.Join(', ', Changes)]), Level, Fixes);
    end;
  finally
    mTypes.Free;
  end;
end;

{ TFieldAfterMethodRule }

function TFieldAfterMethodRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FieldAfterMethodRuleId, TRuleSeverity.Error,
    'Feld nach Methoden im selben Abschnitt');
end;

procedure TFieldAfterMethodRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Paths: TArray<string>;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TokenAtOffset(Tokens, ANode.StartOffset);
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, FirstToken(ANode));
  end;

  function OnlySpaceBefore(const APosition: TTextPosition): Boolean;
  begin
    Result := BlankBefore(Lines, APosition);
  end;

  function OnlyCommentAfter(const APosition: TTextPosition): Boolean;
  begin
    Result := BlankAfter(Lines, APosition);
  end;

  // Erstes Kind des Blocks um ABody[AIndex]: davorstehende Attribute gehören dazu.
  function BlockFirst(ABody: TSyntaxNode; AIndex: Integer): TSyntaxNode;
  begin
    while (AIndex > 0) and (ABody[AIndex - 1].Kind = TSyntaxKind.Attribute) do
      Dec(AIndex);
    Result := ABody[AIndex];
  end;

  // Erste Zeile des Blocks ab ANode samt Kommentarzeilen direkt darüber (XMLDoc).
  function StartLine(ANode: TSyntaxNode): Integer;
  var
    Index: Integer;
  begin
    Result := ANode.StartPos.Line;
    Index := FirstToken(ANode) - 1;
    while (Index >= 0) and (Tokens[Index].Kind = TPascalTokenKind.Comment) and
      (Tokens[Index].EndPos.Line = Result - 1) and OnlySpaceBefore(Tokens[Index].StartPos) do
    begin
      Result := Tokens[Index].StartPos.Line;
      Dec(Index);
    end;
  end;

  // Feld samt Attributen und Kommentaren vor das erste Mitglied des Abschnitts; nil, wenn Zeilen nicht passen.
  function MoveFix(ABody: TSyntaxNode; AField, AMember: Integer): TArray<TRuleFix>;
  var
    Field, Target: TSyntaxNode;
    FieldStart, FieldEnd, TargetLine, Line: Integer;
    Moved: string;
  begin
    Result := nil;
    Field := BlockFirst(ABody, AField);
    Target := BlockFirst(ABody, AMember);
    if not OnlySpaceBefore(Field.StartPos) or not OnlySpaceBefore(Target.StartPos) or
      not OnlyCommentAfter(ABody[AField].EndPos) then
      Exit;
    FieldStart := StartLine(Field);
    FieldEnd := ABody[AField].EndPos.Line;
    TargetLine := StartLine(Target);
    if (TargetLine >= FieldStart) or (FieldEnd + 1 >= Length(Lines)) then
      Exit;
    Moved := '';
    for Line := FieldStart to FieldEnd do
      Moved := Moved + Lines[Line] + LineBreak;
    Result := [TRuleFix.Create('Feld an den Anfang des Abschnitts verschieben', [
      TRuleEdit.Create(TTextRange.Create(TargetLine, 0, TargetLine, 0), Moved),
      TRuleEdit.Create(TTextRange.Create(FieldStart, 0, FieldEnd + 1, 0), '')], True)];
  end;

  function VarFix(ABody: TSyntaxNode; AField: Integer): TRuleFix;
  var
    First: TSyntaxNode;
  begin
    First := BlockFirst(ABody, AField);
    Result := TRuleFix.Create('var davor setzen', [TRuleEdit.Create(TTextRange.Create(First.StartPos,
      First.StartPos), 'var ')], True);
  end;

  procedure CheckBody(ABody: TSyntaxNode);
  var
    Index, Member, First: Integer;
    Fixes: TArray<TRuleFix>;
    SamePaths: Boolean;
  begin
    First := -1;
    SamePaths := True;
    for Index := 0 to ABody.ChildCount - 1 do
      case ABody[Index].Kind of
        // Ein neuer Abschnitt bzw. var erlaubt wieder Felder.
        TSyntaxKind.Visibility, TSyntaxKind.VarSection, TSyntaxKind.TypeSection, TSyntaxKind.ConstSection:
          begin
            First := -1;
            SamePaths := True;
          end;
        TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
          begin
            if First < 0 then
              First := Index
            else if PathOf(ABody[Index]) <> PathOf(ABody[First]) then
              SamePaths := False;
          end;
        TSyntaxKind.Field:
          if First >= 0 then
          begin
            // Nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird.
            Member := First;
            while (Member < Index) and not ((ABody[Member].Kind in [TSyntaxKind.RoutineHeader,
              TSyntaxKind.PropertyDecl]) and TConditionalBranches.Implies(PathOf(ABody[Index]),
              PathOf(ABody[Member]))) do
              Inc(Member);
            if Member >= Index then
              Continue;
            Fixes := nil;
            // Verschieben nur ohne Bedingungen dazwischen, sonst landet das Feld in einem anderen Zweig.
            if SamePaths and (PathOf(ABody[Index]) = PathOf(ABody[First])) then
              Fixes := MoveFix(ABody, Index, First);
            if ABody.Kind = TSyntaxKind.RecordType then
              // In Records verschiebt das Verschieben das Speicherlayout; var zuerst.
              Fixes := [VarFix(ABody, Index)] + Fixes
            else
              Fixes := Fixes + [VarFix(ABody, Index)];
            AReport.Add(TTextRange.Create(ABody[Index].StartPos, ABody[Index].EndPos),
              'Feld nach Methoden im selben Abschnitt (wie E2169).', TRuleConfidence.High, Fixes);
          end;
      end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType] then
          CheckBody(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
end;

{ TOverloadDirectiveMissingRule }

function TOverloadDirectiveMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OverloadDirectiveMissingRuleId, TRuleSeverity.Error,
    'Überladung ohne overload oder mit gleicher Signatur');
end;

type
  /// <summary>Eine Deklaration in einem Gültigkeitsbereich für overload-directive-missing (#987).</summary>
  TOverloadEntry = record
    Header: TSyntaxNode;
    Name: string;
    HasOverload: Boolean;
    /// <summary>Parameterarten und -typen samt Zahl der Typparameter, kleingeschrieben.</summary>
    Parameters: string;
    ResultType: string;
    Path: string;
  end;

procedure TOverloadDirectiveMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TokenAtOffset(Tokens, ANode.StartOffset);
  end;

  function NodeKey(ANode: TSyntaxNode): string;
  var
    Index: Integer;
  begin
    // Quelltext ohne Leerraum und Kommentare, kleingeschrieben.
    Result := '';
    for Index := FirstToken(ANode) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
        Break;
      if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
        Result := Result + LowerCase(Tokens[Index].Text);
    end;
  end;

  // class operator Implicit … darf ohne overload mehrfach stehen.
  function IsOperator(AHeader: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    Index := FirstToken(AHeader);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < AHeader.EndOffset) and
      (Tokens[Index].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier, TPascalTokenKind.Comment]) and
      not SameText(Tokens[Index].Text, AHeader.Name) do
    begin
      if SameText(Tokens[Index].Text, 'operator') then
        Exit(True);
      Inc(Index);
    end;
    Result := False;
  end;

  function EntryOf(AHeader: TSyntaxNode): TOverloadEntry;
  const
    Modifiers: array[TParameterModifier] of string = ('', 'const ', 'var ', 'out ', 'constref ');
  var
    Index, Inner, Count: Integer;
    Child, Parameter, TypeNode: TSyntaxNode;
    TypeText: string;
  begin
    Result := Default(TOverloadEntry);
    Result.Header := AHeader;
    Result.Name := AHeader.Name;
    Result.Path := TConditionalBranches.PathAt(Paths, FirstToken(AHeader));
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      Child := AHeader[Index];
      case Child.Kind of
        TSyntaxKind.Directive:
          // override braucht kein overload: Delphi übernimmt es von der überschriebenen Methode (mORMot2,
          // Graphics32, #1325).
          if SameText(Child.Name, 'overload') or SameText(Child.Name, 'override') then
            Result.HasOverload := True;
        TSyntaxKind.GenericParams:
          Result.Parameters := Result.Parameters + '<' + IntToStr(Child.ChildCount) + '>';
        TSyntaxKind.Parameters:
          for Inner := 0 to Child.ChildCount - 1 do
          begin
            Parameter := Child[Inner];
            if Parameter.Kind <> TSyntaxKind.Parameter then
              Continue;
            // Auch offene Arrays: array of PTypeInfo ist nicht array of TValue (#1325).
            TypeNode := TRoutineSignatures.ParameterType(Parameter);
            TypeText := '?';
            if TypeNode <> nil then
              TypeText := NodeKey(TypeNode);
            // A, B: Integer zählt als zwei Parameter.
            for Count := 1 to Length(Parameter.Name.Split([','])) do
              Result.Parameters := Result.Parameters + Modifiers[Parameter.Modifier] + TypeText + ';';
          end;
        TSyntaxKind.TypeReference:
          Result.ResultType := NodeKey(Child);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  // Wird AEarlier immer mit übersetzt, wenn ALater übersetzt wird?
  function Together(const ALater, AEarlier: TOverloadEntry): Boolean;
  begin
    Result := TConditionalBranches.Implies(ALater.Path, AEarlier.Path);
  end;

  // " overload;" hinter dem ersten Semikolon des Kopfs, also vor den übrigen Direktiven.
  function OverloadEdit(const AEntry: TOverloadEntry; out AEdit: TRuleEdit): Boolean;
  var
    Index, Depth: Integer;
  begin
    Depth := 0;
    for Index := FirstToken(AEntry.Header) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= AEntry.Header.EndOffset then
        Break;
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos, Tokens[Index].EndPos), ' overload;');
        Exit(True);
      end;
    end;
    AEdit := Default(TRuleEdit);
    Result := False;
  end;

  function NameRange(const AEntry: TOverloadEntry): TTextRange;
  var
    Index: Integer;
  begin
    for Index := FirstToken(AEntry.Header) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= AEntry.Header.EndOffset then
        Break;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AEntry.Name) then
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
    end;
    Result := TTextRange.Create(AEntry.Header.StartPos, AEntry.Header.EndPos);
  end;

  procedure CheckGroup(const AEntries: TArray<TOverloadEntry>);
  var
    Later, Earlier: Integer;
    Reported: Boolean;
    Edits: TArray<TRuleEdit>;
    Edit: TRuleEdit;
    Entry: TOverloadEntry;
    Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    Reported := False;
    for Later := 1 to High(AEntries) do
      for Earlier := 0 to Later - 1 do
      begin
        if not Together(AEntries[Later], AEntries[Earlier]) then
          Continue;
        // E2254/E2267 einmal je Name, mit einer Korrektur für alle Deklarationen ohne overload.
        if not Reported and (not AEntries[Later].HasOverload or not AEntries[Earlier].HasOverload) then
        begin
          Reported := True;
          if not AEntries[Later].HasOverload then
            Message := Format('%s ist überladen, aber nicht mit overload markiert (wie E2254).',
              [AEntries[Later].Name])
          else
            Message := Format('%s ist überladen, die frühere Deklaration in Zeile %d trägt kein overload (wie E2267).',
              [AEntries[Later].Name, AEntries[Earlier].Header.StartPos.Line + 1]);
          Edits := nil;
          for Entry in AEntries do
            if not Entry.HasOverload and OverloadEdit(Entry, Edit) then
              Edits := Edits + [Edit];
          Fixes := nil;
          if Edits <> nil then
            Fixes := [TRuleFix.Create('overload; an alle Deklarationen anhängen', Edits, True)];
          AReport.Add(NameRange(AEntries[Later]), Message, TRuleConfidence.High, Fixes);
        end;
        if AEntries[Later].Parameters = AEntries[Earlier].Parameters then
        begin
          if (AEntries[Later].ResultType <> '') and (AEntries[Later].ResultType = AEntries[Earlier].ResultType) then
            Message := Format('%s mit denselben Parametern und demselben Ergebnistyp gibt es schon in Zeile %d ' +
              '(wie E2301).', [AEntries[Later].Name, AEntries[Earlier].Header.StartPos.Line + 1])
          else
            Message := Format('%s mit denselben Parametern gibt es schon in Zeile %d (wie E2252).',
              [AEntries[Later].Name, AEntries[Earlier].Header.StartPos.Line + 1]);
          AReport.Add(NameRange(AEntries[Later]), Message, TRuleConfidence.High);
          Break;
        end;
      end;
  end;

  // Ist AEntry eine Deklaration ohne eigene Implementierung (interface-Teil, forward)?
  function Open(const AEntry: TOverloadEntry): Boolean;
  begin
    Result := not TRoutineSignatures.HasImplementation(AEntry.Header.Parent);
  end;

  // Gehört die Implementierung AEntry zu einer früheren Deklaration ohne Implementierung? Mit gleichen Parametern
  // oder in Kurzform (function Foo;) zur einzigen gleichen Namens (#1325).
  function ImplementsEarlier(const AEntries: TArray<TOverloadEntry>; const AEntry: TOverloadEntry): Boolean;
  var
    mOther: TOverloadEntry;
    mCount: Integer;
  begin
    mCount := 0;
    for mOther in AEntries do
      if SameText(mOther.Name, AEntry.Name) and Open(mOther) then
      begin
        if mOther.Parameters = AEntry.Parameters then
          Exit(True);
        Inc(mCount);
      end;
    Result := (mCount = 1) and TRoutineSignatures.IsShortForm(AEntry.Header);
  end;

  // Deklarationen eines Bereichs nach Namen; eine Implementierung (begin, asm oder external) zu einer früheren
  // Deklaration (interface, forward) zählt nicht. class constructor und class destructor sind keine Überladungen
  // der Instanzmethoden (#1325).
  procedure CheckScope(const AHeaders: TArray<TSyntaxNode>; ABodiesFollow: Boolean);
  var
    Entries, Group: TArray<TOverloadEntry>;
    Entry, Other: TOverloadEntry;
    Index: Integer;
    Done: TArray<string>;
    IsBody: Boolean;
  begin
    Entries := nil;
    for Index := 0 to High(AHeaders) do
    begin
      if (Pos('.', AHeaders[Index].Name) > 0) or (AHeaders[Index].Name = '') or IsOperator(AHeaders[Index]) or
        TRoutineSignatures.IsClassConstructor(Tokens, AHeaders[Index]) then
        Continue;
      Entry := EntryOf(AHeaders[Index]);
      IsBody := ABodiesFollow and (AHeaders[Index].Parent <> nil) and
        TRoutineSignatures.HasImplementation(AHeaders[Index].Parent) and ImplementsEarlier(Entries, Entry);
      if not IsBody then
        Entries := Entries + [Entry];
    end;
    Done := nil;
    for Entry in Entries do
    begin
      if IndexText(Entry.Name, Done) >= 0 then
        Continue;
      Done := Done + [Entry.Name];
      Group := nil;
      for Other in Entries do
        if SameText(Other.Name, Entry.Name) then
          Group := Group + [Other];
      if Length(Group) > 1 then
        CheckGroup(Group);
    end;
  end;

  // Köpfe der Routinen direkt unter ANode (RoutineDecl mit RoutineHeader).
  procedure AddRoutines(ANode: TSyntaxNode; var AHeaders: TArray<TSyntaxNode>);
  var
    Index: Integer;
    Header: TSyntaxNode;
  begin
    if ANode = nil then
      Exit;
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        Header := ANode[Index].FindChild(TSyntaxKind.RoutineHeader);
        if Header <> nil then
          AHeaders := AHeaders + [Header];
      end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Headers: TArray<TSyntaxNode>;
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Headers := nil;
        case Node.Kind of
          TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.HelperType:
            begin
              for Index := 0 to Node.ChildCount - 1 do
                if Node[Index].Kind = TSyntaxKind.RoutineHeader then
                  Headers := Headers + [Node[Index]];
              CheckScope(Headers, False);
            end;
          TSyntaxKind.UnitFile:
            begin
              AddRoutines(Node.FindChild(TSyntaxKind.InterfaceSection), Headers);
              AddRoutines(Node.FindChild(TSyntaxKind.ImplementationSection), Headers);
              CheckScope(Headers, True);
            end;
          TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.RoutineDecl:
            begin
              AddRoutines(Node, Headers);
              CheckScope(Headers, True);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
end;

{ TDuplicateDeclarationRule }

function TDuplicateDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DuplicateDeclarationRuleId, TRuleSeverity.Error, 'Bezeichner doppelt deklariert');
end;

type
  /// <summary>Ein deklarierter Name für duplicate-declaration (#988).</summary>
  TDeclaredName = record
    Name: string;
    /// <summary>Vergleichsschlüssel: Name in Kleinbuchstaben, bei generischen Typen mit Zahl der Typparameter.</summary>
    Key: string;
    /// <summary>Art für die Meldung: Parameter, Variable, Konstante, Typ, Label, Routine, Feld, Methode, Property.</summary>
    Kind: string;
    /// <summary>Deklarationsknoten (VarDecl, Field, TypeDecl …) bzw. LabelSection oder UsedUnit.</summary>
    Node: TSyntaxNode;
    /// <summary>Umgebender Abschnitt (VarSection …) oder nil.</summary>
    Section: TSyntaxNode;
    /// <summary>Position unter den Namen des Knotens (A, B: Integer) und deren Zahl.</summary>
    NameIndex: Integer;
    NameCount: Integer;
    Token: Integer;
    Path: string;
    IsRoutine: Boolean;
  end;

procedure TDuplicateDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Paths: TArray<string>;
  Names: TArray<TDeclaredName>;

  // Erstes Token AName im Knoten ANode; -1 ohne.
  function NameToken(ANode: TSyntaxNode; const AName: string): Integer;
  var
    Index: Integer;
  begin
    for Index := TokenAtOffset(Tokens, ANode.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
        Break;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
        Exit(Index);
    end;
    Result := -1;
  end;

  procedure AddName(ANode, ASection: TSyntaxNode; const AName, AKind: string; AIndex, ACount, AToken: Integer;
    AIsRoutine: Boolean);
  var
    Entry: TDeclaredName;
    Generic: TSyntaxNode;
  begin
    if (AName = '') or (Pos('.', AName) > 0) or (AToken < 0) then
      Exit;
    Entry := Default(TDeclaredName);
    Entry.Name := AName;
    Entry.Key := LowerCase(AName);
    // TList und TList<T> dürfen nebeneinander stehen.
    Generic := nil;
    if ANode.Kind = TSyntaxKind.TypeDecl then
      Generic := ANode.FindChild(TSyntaxKind.GenericParams);
    if Generic <> nil then
      Entry.Key := Entry.Key + '<' + IntToStr(Generic.ChildCount) + '>';
    Entry.Kind := AKind;
    Entry.Node := ANode;
    Entry.Section := ASection;
    Entry.NameIndex := AIndex;
    Entry.NameCount := ACount;
    Entry.Token := AToken;
    Entry.Path := TConditionalBranches.PathAt(Paths, AToken);
    Entry.IsRoutine := AIsRoutine;
    Names := Names + [Entry];
  end;

  // A, B: Integer: je Name ein Eintrag; die Token stehen in der Reihenfolge der Namen.
  procedure AddNames(ANode, ASection: TSyntaxNode; const AKind: string);
  var
    Parts: TArray<string>;
    Index, Token, From: Integer;
  begin
    Parts := ANode.Name.Split([',']);
    From := TokenAtOffset(Tokens, ANode.StartOffset);
    for Index := 0 to High(Parts) do
    begin
      Token := From;
      while (Token <= High(Tokens)) and (Tokens[Token].Offset < ANode.EndOffset) and
        not ((Tokens[Token].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Token].Text, Trim(Parts[Index]))) do
        Inc(Token);
      if (Token > High(Tokens)) or (Tokens[Token].Offset >= ANode.EndOffset) then
        Exit;
      AddName(ANode, ASection, Trim(Parts[Index]), AKind, Index, Length(Parts), Token, False);
      From := Token + 1;
    end;
  end;

  // label L1, L2; über die Token.
  procedure AddLabels(ASection: TSyntaxNode);
  var
    Index, Count, Position: Integer;
  begin
    Count := 0;
    for Index := TokenAtOffset(Tokens, ASection.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ASection.EndOffset then
        Break;
      if Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number] then
        Inc(Count);
    end;
    Position := 0;
    for Index := TokenAtOffset(Tokens, ASection.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ASection.EndOffset then
        Break;
      if Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number] then
      begin
        AddName(ASection, ASection, Tokens[Index].Text, 'Label', Position, Count, Index, False);
        Inc(Position);
      end;
    end;
  end;

  // Ein Deklarationsabschnitt, eine Routine oder Labels.
  procedure AddSection(AChild: TSyntaxNode);
  var
    Inner: Integer;
    Header: TSyntaxNode;
  begin
    case AChild.Kind of
      TSyntaxKind.VarSection:
        for Inner := 0 to AChild.ChildCount - 1 do
          if AChild[Inner].Kind = TSyntaxKind.VarDecl then
            AddNames(AChild[Inner], AChild, 'Variable');
      TSyntaxKind.ConstSection:
        for Inner := 0 to AChild.ChildCount - 1 do
          if AChild[Inner].Kind = TSyntaxKind.ConstDecl then
            AddNames(AChild[Inner], AChild, 'Konstante');
      TSyntaxKind.TypeSection:
        for Inner := 0 to AChild.ChildCount - 1 do
          // Die Vorwärtsdeklaration TFoo = class; und ihre volle Deklaration sind ein Typ.
          if (AChild[Inner].Kind = TSyntaxKind.TypeDecl) and (AChild[Inner].FindChild(TSyntaxKind.ForwardType) = nil) then
            AddName(AChild[Inner], AChild, AChild[Inner].Name, 'Typ', 0, 1, NameToken(AChild[Inner], AChild[Inner].Name),
              False);
      TSyntaxKind.LabelSection:
        AddLabels(AChild);
      TSyntaxKind.RoutineDecl:
        begin
          Header := AChild.FindChild(TSyntaxKind.RoutineHeader);
          if Header <> nil then
            AddName(AChild, nil, Header.Name, 'Routine', 0, 1, NameToken(Header, Header.Name), True);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure AddSections(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
      AddSection(ANode[Index]);
  end;

  procedure AddMembers(ABody: TSyntaxNode);
  var
    Index, Inner: Integer;
    Child: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): Vorordnung, die Namen kommen in derselben Reihenfolge dazu.
    Pending := TStack<TSyntaxNode>.Create;
    try
      for Index := ABody.ChildCount - 1 downto 0 do
        Pending.Push(ABody[Index]);
      while Pending.Count > 0 do
      begin
        Child := Pending.Pop;
        case Child.Kind of
          TSyntaxKind.Field:
            AddNames(Child, nil, 'Feld');
          TSyntaxKind.RoutineHeader:
            AddName(Child, nil, Child.Name, 'Methode', 0, 1, NameToken(Child, Child.Name), True);
          TSyntaxKind.PropertyDecl:
            AddName(Child, nil, Child.Name, 'Property', 0, 1, NameToken(Child, Child.Name), False);
          TSyntaxKind.VarSection:
            for Inner := 0 to Child.ChildCount - 1 do
              if Child[Inner].Kind = TSyntaxKind.VarDecl then
                AddNames(Child[Inner], Child, 'Feld');
          TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
            AddSection(Child);
          // Varianter Teil: Selektorfeld und die Felder der Zweige gehören zum Record.
          TSyntaxKind.VariantPart, TSyntaxKind.CaseItem, TSyntaxKind.Visibility:
            for Inner := Child.ChildCount - 1 downto 0 do
              Pending.Push(Child[Inner]);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Löscht die Zeilen von ANode, wenn er allein auf ihnen steht.
  function LinesEdit(ANode: TSyntaxNode; out AEdit: TRuleEdit): Boolean;
  begin
    Result := BlankBefore(Lines, ANode.StartPos) and BlankAfter(Lines, ANode.EndPos) and
      (ANode.EndPos.Line + 1 < Length(Lines));
    if Result then
      AEdit := TRuleEdit.Create(TTextRange.Create(ANode.StartPos.Line, 0, ANode.EndPos.Line + 1, 0), '');
  end;

  // Name aus einer Liste A, B, C bzw. ganze Deklaration (samt Abschnitt, wenn sie dessen einzige ist).
  function RemovalFix(const AEntry: TDeclaredName; out AFix: TRuleFix): Boolean;
  var
    Edit: TRuleEdit;
    Next, Previous: Integer;
  begin
    Result := False;
    AFix := Default(TRuleFix);
    if AEntry.NameCount > 1 then
    begin
      if AEntry.NameIndex < AEntry.NameCount - 1 then
      begin
        // "B, " bis zum nächsten Namen.
        Next := AEntry.Token + 1;
        while (Next <= High(Tokens)) and not Tokens[Next].IsSymbol(',') do
          Inc(Next);
        Inc(Next);
        while (Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Comment) do
          Inc(Next);
        if Next > High(Tokens) then
          Exit;
        Edit := TRuleEdit.Create(TTextRange.Create(Tokens[AEntry.Token].StartPos, Tokens[Next].StartPos), '');
      end
      else
      begin
        // ", C" ab dem Ende des Namens davor.
        Previous := AEntry.Token - 1;
        while (Previous >= 0) and not Tokens[Previous].IsSymbol(',') do
          Dec(Previous);
        Dec(Previous);
        while (Previous >= 0) and (Tokens[Previous].Kind = TPascalTokenKind.Comment) do
          Dec(Previous);
        if Previous < 0 then
          Exit;
        Edit := TRuleEdit.Create(TTextRange.Create(Tokens[Previous].EndPos, Tokens[AEntry.Token].EndPos), '');
      end;
    end
    else if (AEntry.Section <> nil) and (AEntry.Section.ChildCount = 1) then
    begin
      // Einzige Deklaration: der Abschnitt (var, const, type, label) geht mit.
      if not LinesEdit(AEntry.Section, Edit) then
        Exit;
    end
    else if not LinesEdit(AEntry.Node, Edit) then
      Exit;
    AFix := TRuleFix.Create('Zweite Deklaration entfernen', [Edit]);
    Result := True;
  end;

  procedure CheckNames;
  var
    Later, Earlier: Integer;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    for Later := 1 to High(Names) do
      for Earlier := 0 to Later - 1 do
        if (Names[Earlier].Key = Names[Later].Key) and not (Names[Earlier].IsRoutine and Names[Later].IsRoutine) and
          TConditionalBranches.Implies(Names[Later].Path, Names[Earlier].Path) then
        begin
          Fixes := nil;
          if (Names[Later].Kind <> 'Parameter') and not Names[Later].IsRoutine and
            (Names[Later].Kind <> 'Property') and RemovalFix(Names[Later], Fix) then
            Fixes := [Fix];
          AReport.Add(TTextRange.Create(Tokens[Names[Later].Token].StartPos, Tokens[Names[Later].Token].EndPos),
            Format('%s ist schon als %s deklariert (wie E2004).', [Names[Later].Name, Names[Earlier].Kind]),
            TRuleConfidence.High, Fixes);
          Break;
        end;
  end;

  procedure CheckRoutine(ADecl: TSyntaxNode);
  var
    Header, Parameters: TSyntaxNode;
    Index: Integer;
  begin
    // Nur Rümpfe: Parameter und lokale Deklarationen teilen einen Bereich.
    if ADecl.FindChild(TSyntaxKind.Block) = nil then
      Exit;
    Names := nil;
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
    begin
      Parameters := Header.FindChild(TSyntaxKind.Parameters);
      if Parameters <> nil then
        for Index := 0 to Parameters.ChildCount - 1 do
          if Parameters[Index].Kind = TSyntaxKind.Parameter then
            AddNames(Parameters[Index], nil, 'Parameter');
    end;
    AddSections(ADecl);
    CheckNames;
  end;

  // uses-Einträge der Datei: interface und implementation zusammen.
  procedure CheckUses;
  var
    Clauses: TArray<TSyntaxNode>;
    Clause, Previous, Next: TSyntaxNode;
    Index, Later, Earlier: Integer;
    Entries: TArray<TSyntaxNode>;
    Edit: TRuleEdit;
    Fixes: TArray<TRuleFix>;
    Range: TTextRange;

    procedure Collect(ARoot: TSyntaxNode);
    var
      Inner: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1); Vorordnung, die Klauseln bleiben in Textreihenfolge.
      Pending := TStack<TSyntaxNode>.Create;
      try
        for Inner := ARoot.ChildCount - 1 downto 0 do
          Pending.Push(ARoot[Inner]);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if Node.Kind = TSyntaxKind.UsesClause then
            Clauses := Clauses + [Node]
          else if Node.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
            for Inner := Node.ChildCount - 1 downto 0 do
              Pending.Push(Node[Inner]);
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Clauses := nil;
    Collect(AContext.Tree.Root);
    Entries := nil;
    for Clause in Clauses do
      for Index := 0 to Clause.ChildCount - 1 do
        if Clause[Index].Kind = TSyntaxKind.UsedUnit then
          Entries := Entries + [Clause[Index]];
    for Later := 1 to High(Entries) do
      for Earlier := 0 to Later - 1 do
        if SameText(Entries[Earlier].Name, Entries[Later].Name) and
          TConditionalBranches.Implies(TConditionalBranches.PathAt(Paths, TokenAtOffset(Tokens,
          Entries[Later].StartOffset)), TConditionalBranches.PathAt(Paths, TokenAtOffset(Tokens,
          Entries[Earlier].StartOffset))) then
        begin
          // ", X" bzw. "X, " entfernen; der einzige Eintrag nimmt die ganze uses-Klausel mit.
          Clause := Entries[Later].Parent;
          Previous := nil;
          Next := nil;
          for Index := 0 to Clause.ChildCount - 1 do
            if Clause[Index] = Entries[Later] then
            begin
              if (Index > 0) and (Clause[Index - 1].Kind = TSyntaxKind.UsedUnit) then
                Previous := Clause[Index - 1];
              if (Index < Clause.ChildCount - 1) and (Clause[Index + 1].Kind = TSyntaxKind.UsedUnit) then
                Next := Clause[Index + 1];
            end;
          Fixes := nil;
          if Previous <> nil then
            Fixes := [TRuleFix.Create('Doppelten Eintrag entfernen', [TRuleEdit.Create(TTextRange.Create(
              Previous.EndPos, Entries[Later].EndPos), '')], True)]
          else if Next <> nil then
            Fixes := [TRuleFix.Create('Doppelten Eintrag entfernen', [TRuleEdit.Create(TTextRange.Create(
              Entries[Later].StartPos, Next.StartPos), '')], True)]
          else if LinesEdit(Clause, Edit) then
            Fixes := [TRuleFix.Create('Doppelten Eintrag entfernen', [Edit], True)];
          Range := TTextRange.Create(Entries[Later].StartPos, Entries[Later].EndPos);
          if Entries[Earlier].Parent = Entries[Later].Parent then
            AReport.Add(Range, Format('Unit %s steht schon in uses (wie E2004).', [Entries[Later].Name]),
              TRuleConfidence.High, Fixes)
          else
            AReport.Add(Range, Format('Unit %s steht schon im uses des interface (wie E2004).', [Entries[Later].Name]),
              TRuleConfidence.High, Fixes);
          Break;
        end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.RoutineDecl:
            CheckRoutine(Node);
          TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.HelperType:
            begin
              Names := nil;
              AddMembers(Node);
              CheckNames;
            end;
          TSyntaxKind.UnitFile:
            begin
              Names := nil;
              for Index := 0 to Node.ChildCount - 1 do
                if Node[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
                  AddSections(Node[Index]);
              CheckNames;
            end;
          TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
            begin
              Names := nil;
              AddSections(Node);
              CheckNames;
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
  if TRuleOptions.Bool(AContext.Options, 'checkUses', True) then
    CheckUses;
  Names := nil;
end;

{ TTypeTooLargeRule }

function TTypeTooLargeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('type-too-large', TRuleSeverity.Error, 'Typ überschreitet eine Größengrenze');
end;

const
  // Ab 2 GB meldet Delphi E2100 bzw. E2543.
  TypeSizeLimit = Int64(1) shl 31;
  // Obergrenze der Rechnung, damit Produkte nicht überlaufen.
  TypeSizeCap = Int64(1) shl 50;
  TypeKindsForSize = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
    TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType,
    TSyntaxKind.ClassOfType, TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType,
    TSyntaxKind.SubrangeType, TSyntaxKind.FileType, TSyntaxKind.HelperType];
  // Eingebaute Typen: Größe als untere Grenze; Exakt = auf allen Windows-Plattformen gleich.
  SizeNames: array[0..47] of string = ('Byte', 'ShortInt', 'Boolean', 'ByteBool', 'AnsiChar', 'Int8', 'UInt8',
    'Word', 'SmallInt', 'Char', 'WideChar', 'WordBool', 'Int16', 'UInt16', 'Integer', 'Cardinal', 'LongInt',
    'LongWord', 'Single', 'LongBool', 'FixedInt', 'FixedUInt', 'Int32', 'UInt32', 'Int64', 'UInt64', 'Double',
    'Currency', 'Comp', 'TDateTime', 'TDate', 'TTime', 'Real', 'ShortString', 'TGUID', 'Extended', 'Pointer',
    'PChar', 'PAnsiChar', 'PWideChar', 'string', 'UnicodeString', 'AnsiString', 'WideString', 'NativeInt',
    'NativeUInt', 'Variant', 'OleVariant');
  SizeBytes: array[0..47] of Integer = (1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 256, 16, 8, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 16, 16);
  // Ab diesem Eintrag hängt die Größe von der Plattform ab.
  FirstInexactSize = 35;
  // Elementzahl eingebauter Indextypen.
  CountNames: array[0..11] of string = ('Byte', 'AnsiChar', 'ShortInt', 'Boolean', 'Word', 'Char', 'WideChar',
    'SmallInt', 'Integer', 'Cardinal', 'LongInt', 'LongWord');
  CountValues: array[0..11] of Int64 = (256, 256, 256, 2, 65536, 65536, 65536, 65536, 4294967296, 4294967296,
    4294967296, 4294967296);

type
  /// <summary>Untere Grenze der Größe eines Typs. Exact: genau diese Größe auf allen Windows-Plattformen;
  /// Nested: ein Bestandteil überschreitet die Grenze schon selbst (dort gemeldet).</summary>
  TTypeSize = record
    Bytes: Int64;
    Exact: Boolean;
    Nested: Boolean;
  end;

  /// <summary>Rechnet Typgrößen aus den Deklarationen der Datei und dem Index (#1083).</summary>
  TTypeSizes = class
  private
    FText: string;
    FTokens: TArray<TPascalToken>;
    FIndex: ISymbolIndex;
    FTypes: TDictionary<string, TSyntaxNode>;
    FConstants: TDictionary<string, TSyntaxNode>;
    FEnumValues: TDictionary<string, Int64>;
    FDepth: Integer;
    procedure Collect(ARoot: TSyntaxNode);
    function Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
    function Count(AIndexType: TSyntaxNode; out AExact: Boolean): Int64;
    function CountOfName(const AName: string; out AExact: Boolean): Int64;
    function Multiply(A, B: Int64): Int64;
    function FieldsOf(ARecord: TSyntaxNode; const AParams, AArgs: TArray<string>; var ASize: TTypeSize): Int64;
    function IndexSize(const AName: string): TTypeSize;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
    destructor Destroy; override;
    /// <summary>Typknoten der Deklaration ANode (TypeDecl, Field, VarDecl); nil ohne.</summary>
    class function TypeNodeOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Größe des Typknotens ANode; Typparameter AParams stehen für AArgs.</summary>
    function OfNode(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
    /// <summary>Größe des Typs AName.</summary>
    function OfName(const AName: string; const AParams, AArgs: TArray<string>): TTypeSize;
    /// <summary>Generische Deklaration der Datei zu AName mit ihren Typparametern; nil ohne.</summary>
    function GenericDecl(const AName: string; out AParams: TArray<string>): TSyntaxNode;
  end;

constructor TTypeSizes.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FText := AText;
  FTokens := ATree.Tokens;
  FIndex := AIndex;
  FTypes := TDictionary<string, TSyntaxNode>.Create;
  FConstants := TDictionary<string, TSyntaxNode>.Create;
  FEnumValues := TDictionary<string, Int64>.Create;
  Collect(ATree.Root);
end;

destructor TTypeSizes.Destroy;
begin
  FEnumValues.Free;
  FConstants.Free;
  FTypes.Free;
  inherited;
end;

procedure TTypeSizes.Collect(ARoot: TSyntaxNode);
var
  Stack: TArray<TSyntaxNode>;
  Count, Index, Value: Integer;
  Node: TSyntaxNode;
  Plain: Boolean;
begin
  // Ohne Rekursion (#1094); bei gleichen Namen gilt die erste Deklaration.
  SetLength(Stack, 64);
  Stack[0] := ARoot;
  Count := 1;
  while Count > 0 do
  begin
    Dec(Count);
    Node := Stack[Count];
    if (Node.Kind = TSyntaxKind.TypeDecl) and not FTypes.ContainsKey(LowerCase(Node.Name)) then
      FTypes.Add(LowerCase(Node.Name), Node)
    else if (Node.Kind = TSyntaxKind.ConstDecl) and not FConstants.ContainsKey(LowerCase(Node.Name)) then
      FConstants.Add(LowerCase(Node.Name), Node)
    else if Node.Kind = TSyntaxKind.EnumType then
    begin
      // Werte nur ohne explizite Zuweisung (a = 5) sicher.
      Plain := True;
      for Index := 0 to Node.ChildCount - 1 do
        if Node[Index].Kind <> TSyntaxKind.Identifier then
          Plain := False;
      if Plain then
        for Value := 0 to Node.ChildCount - 1 do
          if not FEnumValues.ContainsKey(LowerCase(Node[Value].Name)) then
            FEnumValues.Add(LowerCase(Node[Value].Name), Value);
    end;
    if Count + Node.ChildCount > Length(Stack) then
      SetLength(Stack, 2 * (Count + Node.ChildCount));
    for Index := Node.ChildCount - 1 downto 0 do
    begin
      Stack[Count] := Node[Index];
      Inc(Count);
    end;
  end;
end;

class function TTypeSizes.TypeNodeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind in TypeKindsForSize then
      Exit(ANode[Index]);
  Result := nil;
end;

function TTypeSizes.Multiply(A, B: Int64): Int64;
begin
  if (A <= 0) or (B <= 0) then
    Exit(0);
  if A > TypeSizeCap div B then
    Exit(TypeSizeCap);
  Result := A * B;
end;

function TTypeSizes.Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
var
  First, Last: Integer;
  Lookup: TOrdinalNameLookup;
begin
  AValue := 0;
  if FDepth > 32 then
    Exit(False);
  First := TokenAtOffset(FTokens, ANode.StartOffset);
  Last := TokenAtOffset(FTokens, ANode.EndOffset) - 1;
  if Last < First then
    Exit(False);
  Lookup :=
    function(const ANames: TArray<string>; ATokenIndex: Integer; out AResult: Int64): Boolean
    var
      Decl: TSyntaxNode;
      Key: string;
    begin
      Result := False;
      AResult := 0;
      if Length(ANames) <> 1 then
        Exit;
      Key := LowerCase(ANames[0]);
      if FEnumValues.TryGetValue(Key, AResult) then
        Exit(True);
      // Nur untypisierte Konstanten sind echte Konstanten in Typgrenzen.
      if not FConstants.TryGetValue(Key, Decl) or (Decl.ChildCount <> 1) or (TypeNodeOf(Decl) <> nil) then
        Exit;
      Inc(FDepth);
      try
        Result := Evaluate(Decl[0], AResult);
      finally
        Dec(FDepth);
      end;
    end;
  Result := TOrdinalConstants.Evaluate(FTokens, First, Last, Lookup, AValue);
end;

function TTypeSizes.CountOfName(const AName: string; out AExact: Boolean): Int64;
var
  Index: Integer;
  Decl, Body: TSyntaxNode;
begin
  AExact := True;
  Index := IndexText(AName, CountNames);
  if Index >= 0 then
    Exit(CountValues[Index]);
  AExact := False;
  Result := 0;
  if (FDepth > 32) or not FTypes.TryGetValue(LowerCase(AName), Decl) then
    Exit;
  Body := TypeNodeOf(Decl);
  if Body = nil then
    Exit;
  Inc(FDepth);
  try
    Result := Count(Body, AExact);
  finally
    Dec(FDepth);
  end;
end;

function TTypeSizes.Count(AIndexType: TSyntaxNode; out AExact: Boolean): Int64;
var
  Low, High: Int64;
  Index: Integer;
begin
  AExact := False;
  Result := 0;
  case AIndexType.Kind of
    TSyntaxKind.SubrangeType:
      if (AIndexType.ChildCount = 2) and Evaluate(AIndexType[0], Low) and Evaluate(AIndexType[1], High) then
      begin
        AExact := True;
        if High >= Low then
          Result := High - Low + 1;
      end;
    TSyntaxKind.TypeReference:
      Result := CountOfName(AIndexType.Name, AExact);
    TSyntaxKind.EnumType:
      begin
        // Mit explizit zugewiesenen Werten (a = 5) mindestens so viele Elemente wie Namen.
        AExact := True;
        for Index := 0 to AIndexType.ChildCount - 1 do
          if AIndexType[Index].Kind = TSyntaxKind.Identifier then
            Inc(Result)
          else
            AExact := False;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TTypeSizes.FieldsOf(ARecord: TSyntaxNode; const AParams, AArgs: TArray<string>;
  var ASize: TTypeSize): Int64;
var
  Index, Inner, Names, Fields: Integer;
  Child, Item: TSyntaxNode;
  Part: TTypeSize;
  Largest, Branch, FieldSize: Int64;
  Uniform: Boolean;
begin
  // Summe der Felder; varianter Teil: Selektor plus größter Zweig.
  Result := 0;
  Fields := 0;
  FieldSize := 0;
  Uniform := True;
  for Index := 0 to ARecord.ChildCount - 1 do
  begin
    Child := ARecord[Index];
    case Child.Kind of
      TSyntaxKind.Field:
        if TypeNodeOf(Child) <> nil then
        begin
          Part := OfNode(TypeNodeOf(Child), AParams, AArgs);
          Names := Length(Child.Name.Split([',']));
          Inc(Fields, Names);
          if (FieldSize <> 0) and (FieldSize <> Part.Bytes) then
            Uniform := False;
          FieldSize := Part.Bytes;
          Result := Result + Multiply(Part.Bytes, Names);
          ASize.Exact := ASize.Exact and Part.Exact;
          ASize.Nested := ASize.Nested or Part.Nested or (Part.Bytes >= TypeSizeLimit);
        end;
      TSyntaxKind.Visibility:
        Result := Result + FieldsOf(Child, AParams, AArgs, ASize);
      TSyntaxKind.VariantPart:
        begin
          // Ein Selektorfeld (case Art: TArt of) belegt Platz, ein bloßer Selektortyp nicht.
          Largest := 0;
          for Inner := 0 to Child.ChildCount - 1 do
          begin
            Item := Child[Inner];
            if Item.Kind = TSyntaxKind.Field then
            begin
              Part := OfNode(TypeNodeOf(Item), AParams, AArgs);
              Result := Result + Part.Bytes;
              Inc(Fields);
            end
            else if Item.Kind = TSyntaxKind.CaseItem then
            begin
              Branch := FieldsOf(Item, AParams, AArgs, ASize);
              if Branch > Largest then
                Largest := Branch;
            end;
          end;
          Result := Result + Largest;
          ASize.Exact := False;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if Result > TypeSizeCap then
      Result := TypeSizeCap;
  end;
  // Mehrere Felder: Ausrichtung kann Lücken einfügen, außer alle sind gleich groß (1, 2, 4 oder 8 Byte).
  if (Fields > 1) and not (Uniform and ((FieldSize = 1) or (FieldSize = 2) or (FieldSize = 4) or
    (FieldSize = 8))) then
    ASize.Exact := False;
end;

function TTypeSizes.IndexSize(const AName: string): TTypeSize;
var
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Part: TTypeSize;
begin
  Result := Default(TTypeSize);
  if (FIndex = nil) or (FDepth > 32) then
    Exit;
  Inc(FDepth);
  try
    for Location in FIndex.FindSymbols(AName) do
    begin
      if Location.Symbol.Container <> '' then
        Continue;
      case Location.Symbol.Kind of
        TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
          Result.Bytes := 4;
        TIndexSymbolKind.EnumType:
          Result.Bytes := 1;
        TIndexSymbolKind.TypeAlias:
          Result := OfName(Location.Symbol.TypeName, nil, nil);
        TIndexSymbolKind.RecordType:
          if FIndex.FindFile(Location.FileName, UnitIndex) then
            for Symbol in UnitIndex.Symbols do
              if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AName) then
              begin
                Part := OfName(Symbol.TypeName, nil, nil);
                Result.Bytes := Result.Bytes + Part.Bytes;
                Result.Nested := Result.Nested or Part.Nested or (Part.Bytes >= TypeSizeLimit);
              end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Result.Exact := False;
      Exit;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TTypeSizes.GenericDecl(const AName: string; out AParams: TArray<string>): TSyntaxNode;
var
  Params: TSyntaxNode;
  Index: Integer;
begin
  AParams := nil;
  if not FTypes.TryGetValue(LowerCase(AName), Result) then
    Exit(nil);
  Params := Result.FindChild(TSyntaxKind.GenericParams);
  if Params = nil then
    Exit(nil);
  for Index := 0 to Params.ChildCount - 1 do
    AParams := AParams + [Params[Index].Name];
end;

function TTypeSizes.OfName(const AName: string; const AParams, AArgs: TArray<string>): TTypeSize;
var
  Index: Integer;
  Decl: TSyntaxNode;
begin
  Result := Default(TTypeSize);
  Index := IndexText(AName, AParams);
  if (Index >= 0) and (Index < Length(AArgs)) then
    Exit(OfName(AArgs[Index], nil, nil));
  Index := IndexText(AName, SizeNames);
  if Index >= 0 then
  begin
    Result.Bytes := SizeBytes[Index];
    Result.Exact := Index < FirstInexactSize;
    Exit;
  end;
  if (FDepth > 32) then
    Exit;
  if FTypes.TryGetValue(LowerCase(AName), Decl) and (Decl.FindChild(TSyntaxKind.GenericParams) = nil) and
    (TypeNodeOf(Decl) <> nil) then
  begin
    Inc(FDepth);
    try
      Result := OfNode(TypeNodeOf(Decl), nil, nil);
    finally
      Dec(FDepth);
    end;
    // Ein benannter Typ über der Grenze wird an seiner Deklaration gemeldet.
    if Result.Bytes >= TypeSizeLimit then
      Result.Nested := True;
    Exit;
  end;
  Result := IndexSize(AName);
end;

function TTypeSizes.OfNode(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
var
  Index, Last: Integer;
  Element: TTypeSize;
  Elements: Int64;
  CountExact: Boolean;
  Decl, Args, ShortLength: TSyntaxNode;
  Params, Values: TArray<string>;
  Value: Int64;
begin
  Result := Default(TTypeSize);
  if (ANode = nil) or (FDepth > 32) then
    Exit;
  Inc(FDepth);
  try
    case ANode.Kind of
      TSyntaxKind.TypeReference:
        begin
          Args := ANode.FindChild(TSyntaxKind.GenericArgs);
          ShortLength := nil;
          for Index := 0 to ANode.ChildCount - 1 do
            if ANode[Index].Kind <> TSyntaxKind.GenericArgs then
              ShortLength := ANode[Index];
          if SameText(ANode.Name, 'string') and (ShortLength <> nil) then
          begin
            // string[N]: ShortString mit N Zeichen und Längenbyte.
            if Evaluate(ShortLength, Value) then
            begin
              Result.Bytes := Value + 1;
              Result.Exact := True;
            end;
          end
          else if Args <> nil then
          begin
            Decl := GenericDecl(ANode.Name, Params);
            if Decl <> nil then
            begin
              Values := nil;
              for Index := 0 to Args.ChildCount - 1 do
                Values := Values + [Trim(Copy(FText, Args[Index].StartOffset + 1,
                  Args[Index].EndOffset - Args[Index].StartOffset))];
              Result := OfNode(TypeNodeOf(Decl), Params, Values);
            end
            else
              // TArray<T>, TList<T> …: Zeiger.
              Result.Bytes := 4;
          end
          else
            Result := OfName(ANode.Name, AParams, AArgs);
        end;
      TSyntaxKind.ArrayType:
        if ANode.ChildCount < 2 then
          // Dynamisches Array: ein Zeiger.
          Result.Bytes := 4
        else
        begin
          Last := ANode.ChildCount - 1;
          Element := OfNode(ANode[Last], AParams, AArgs);
          Result.Bytes := Element.Bytes;
          Result.Exact := Element.Exact;
          Result.Nested := Element.Nested or (Element.Bytes >= TypeSizeLimit);
          for Index := 0 to Last - 1 do
          begin
            Elements := Count(ANode[Index], CountExact);
            Result.Bytes := Multiply(Result.Bytes, Elements);
            Result.Exact := Result.Exact and CountExact;
          end;
        end;
      TSyntaxKind.RecordType, TSyntaxKind.ObjectType:
        begin
          Result.Exact := True;
          Result.Bytes := FieldsOf(ANode, AParams, AArgs, Result);
          if ANode.Kind = TSyntaxKind.ObjectType then
            Result.Exact := False;
        end;
      TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType, TSyntaxKind.PointerType,
      TSyntaxKind.ProcedureType:
        Result.Bytes := 4;
      TSyntaxKind.EnumType, TSyntaxKind.SetType, TSyntaxKind.SubrangeType:
        Result.Bytes := 1;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  finally
    Dec(FDepth);
  end;
end;

procedure TTypeTooLargeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Sizes: TTypeSizes;
  Tokens: TArray<TPascalToken>;

  function SizeText(const ASize: TTypeSize): string;
  var
    Gigabytes: Int64;
    Settings: TFormatSettings;
  begin
    Gigabytes := ASize.Bytes shr 30;
    if ASize.Bytes >= TypeSizeCap then
      Result := 'über 1 PB'
    else if ASize.Bytes and ((Int64(1) shl 30) - 1) = 0 then
      Result := Format('%d GB', [Gigabytes])
    else
    begin
      Settings := TFormatSettings.Invariant;
      Settings.DecimalSeparator := ',';
      Result := FormatFloat('0.#', ASize.Bytes / (Int64(1) shl 30), Settings) + ' GB';
    end;
    if not ASize.Exact and (ASize.Bytes < TypeSizeCap) then
      Result := 'mindestens ' + Result;
  end;

  // Name der Deklaration, zu der der Typknoten gehört; '' bei verschachtelten Typen.
  function OwnerName(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if (ANode.Parent <> nil) and (ANode.Parent.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.Field,
      TSyntaxKind.VarDecl]) and (TTypeSizes.TypeNodeOf(ANode.Parent) = ANode) then
      Result := ANode.Parent.Name.Replace(',', ', ');
  end;

  function NameRange(ANode: TSyntaxNode): TTextRange;
  var
    Index: Integer;
  begin
    // Bei Typdeklarationen der Name, sonst der Typ selbst.
    if ANode.Parent.Kind = TSyntaxKind.TypeDecl then
      for Index := TokenAtOffset(Tokens, ANode.Parent.StartOffset) to High(Tokens) do
        if SameText(Tokens[Index].Text, ANode.Parent.Name) then
          Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  procedure CheckNode(ANode: TSyntaxNode);
  var
    Size: TTypeSize;
    Name, Code: string;
    Params: TArray<string>;
  begin
    Code := 'E2100';
    if ANode.Kind = TSyntaxKind.TypeReference then
    begin
      // Instanz eines generischen Typs der Datei: TFeld<Int64>.
      if (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) or (Sizes.GenericDecl(ANode.Name, Params) = nil) then
        Exit;
      Code := 'E2543';
    end;
    Size := Sizes.OfNode(ANode, nil, nil);
    if (Size.Bytes < TypeSizeLimit) or Size.Nested then
      Exit;
    if Code = 'E2543' then
      Name := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset))
    else
    begin
      Name := OwnerName(ANode);
      if Name = '' then
        Name := 'Der Typ';
    end;
    AReport.Add(NameRange(ANode), Format('%s ist %s groß; erlaubt sind 2 GB (wie %s).', [Name, SizeText(Size),
      Code]), TRuleConfidence.High);
  end;

var
  Stack: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Sizes := TTypeSizes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    // Ohne Rekursion durch den Baum (#1094); Rümpfe generischer Typen erst bei ihrer Instanz.
    SetLength(Stack, 64);
    Stack[0] := AContext.Tree.Root;
    Count := 1;
    while Count > 0 do
    begin
      Dec(Count);
      Node := Stack[Count];
      if (Node.Kind = TSyntaxKind.TypeDecl) and (Node.FindChild(TSyntaxKind.GenericParams) <> nil) then
        Continue;
      if Node.Kind in [TSyntaxKind.ArrayType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
        TSyntaxKind.TypeReference] then
        CheckNode(Node);
      if Count + Node.ChildCount > Length(Stack) then
        SetLength(Stack, 2 * (Count + Node.ChildCount));
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Stack[Count] := Node[Index];
        Inc(Count);
      end;
    end;
  finally
    Sizes.Free;
  end;
end;

{ TVariantRecordManagedFieldRule }

function TVariantRecordManagedFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('variant-record-managed-field', TRuleSeverity.Error,
    'Verwalteter Typ im varianten Teil eines Records');
end;

procedure TVariantRecordManagedFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  TypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.RecordType,
    TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType, TSyntaxKind.SetType,
    TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType, TSyntaxKind.FileType];
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Types: TManagedTypes;

  function IsCode(AIndex: Integer): Boolean;
  begin
    Result := not (Tokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function TypeNode(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in TypeKinds then
        Exit(ANode[Index]);
    Result := nil;
  end;

  // Token des Typparameters AName ohne Einschränkung in der umgebenden generischen Deklaration; -1 sonst.
  // AAlone: einziger Name seiner Gruppe (nur dann lässt sich ": record" anhängen).
  function UnconstrainedParam(ANode: TSyntaxNode; const AName: string; out AAlone: Boolean): Integer;
  var
    Decl, Params: TSyntaxNode;
    Index, Last, Group, Depth: Integer;
    Found, Constrained: Boolean;
  begin
    Result := -1;
    AAlone := False;
    Decl := ANode.Parent;
    while Decl <> nil do
    begin
      Params := nil;
      if Decl.Kind = TSyntaxKind.TypeDecl then
        Params := Decl.FindChild(TSyntaxKind.GenericParams);
      if Params <> nil then
      begin
        // Gruppen durch ; getrennt; Namen vor dem :, Einschränkungen dahinter.
        Index := TokenAtOffset(Tokens, Params.StartOffset) + 1;
        Last := TokenAtOffset(Tokens, Params.EndOffset);
        while Index < Last do
        begin
          Found := False;
          Constrained := False;
          Group := 0;
          Depth := 0;
          Result := -1;
          while Index < Last do
          begin
            if not IsCode(Index) then
            begin
              Inc(Index);
              Continue;
            end;
            if Tokens[Index].IsSymbol('<') then
              Inc(Depth)
            else if Tokens[Index].IsSymbol('>') then
              Dec(Depth)
            else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
              Break
            else if (Depth = 0) and Tokens[Index].IsSymbol(':') then
              Constrained := True
            else if not Constrained and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
            begin
              Inc(Group);
              if SameText(Tokens[Index].Text, AName) then
              begin
                Found := True;
                Result := Index;
              end;
            end;
            Inc(Index);
          end;
          if Found then
          begin
            AAlone := Group = 1;
            if Constrained then
              Result := -1;
            Exit;
          end;
          Inc(Index);
        end;
        Result := -1;
      end;
      Decl := Decl.Parent;
    end;
  end;

  // Feld vor das case des varianten Teils verschieben: einfügen vor case, im Zweig samt Trenner löschen.
  function MoveToFixedPart(AField, APart: TSyntaxNode): TRuleFix;
  var
    Item: TSyntaxNode;
    Text: string;
    Position, Remove: Integer;
    CaseToken, First, Last: Integer;
    Removal: TTextRange;
  begin
    Result := Default(TRuleFix);
    Item := AField.Parent;
    Position := 0;
    while Item[Position] <> AField do
      Inc(Position);
    Text := NodeText(AField);
    if Text.EndsWith(';') then
      Text := TrimRight(Copy(Text, 1, Length(Text) - 1));
    First := TokenAtOffset(Tokens, AField.StartOffset);
    Last := TokenAtOffset(Tokens, AField.EndOffset) - 1;
    if Tokens[Last].IsSymbol(';') and (Position < Item.ChildCount - 1) then
      // Bis vor das nächste Feld.
      Removal := TTextRange.Create(Tokens[First].StartPos, Item[Position + 1].StartPos)
    else if Position > 0 then
    begin
      // Letztes Feld: ab dem ; des vorigen.
      Remove := First - 1;
      while (Remove > 0) and not IsCode(Remove) do
        Dec(Remove);
      if not Tokens[Remove].IsSymbol(';') then
        Exit;
      Removal := TTextRange.Create(Tokens[Remove].StartPos, Tokens[Last].EndPos);
    end
    else
      Removal := TTextRange.Create(Tokens[First].StartPos, Tokens[Last].EndPos);
    CaseToken := TokenAtOffset(Tokens, APart.StartOffset);
    Result := TRuleFix.Create(Format('%s in den festen Teil verschieben', [AField.Name]),
      [TRuleEdit.Create(TTextRange.Create(Tokens[CaseToken].StartPos, Tokens[CaseToken].StartPos),
      Text + ';' + LineBreak + TTextLines.IndentOf(Lines[Tokens[CaseToken].StartPos.Line])),
      TRuleEdit.Create(Removal, '')], False);
  end;

  function ShortStringFix(ATypeNode: TSyntaxNode): TArray<TRuleFix>;
  begin
    Result := nil;
    if MatchText(NodeText(ATypeNode), ['string', 'AnsiString', 'UnicodeString', 'WideString', 'RawByteString',
      'UTF8String']) then
      Result := [TRuleFix.Create('ShortString verwenden (höchstens 255 Zeichen)',
        [TRuleEdit.Create(TTextRange.Create(ATypeNode.StartPos, ATypeNode.EndPos), 'ShortString')], False)];
  end;

  procedure CheckField(AField: TSyntaxNode);
  var
    TypeRef, Part: TSyntaxNode;
    TypeText, Kind: string;
    Param: Integer;
    Alone: Boolean;
    Fixes: TArray<TRuleFix>;
    Moved: TRuleFix;
  begin
    TypeRef := TypeNode(AField);
    if TypeRef = nil then
      Exit;
    TypeText := NodeText(TypeRef);
    Part := AField.Parent.Parent;
    Fixes := nil;
    // Nur der äußerste variante Teil hat einen festen Teil davor.
    if Part.Parent.Kind = TSyntaxKind.RecordType then
    begin
      Moved := MoveToFixedPart(AField, Part);
      if Moved.Title <> '' then
        Fixes := [Moved];
    end;
    Param := UnconstrainedParam(AField, TypeText, Alone);
    if Param >= 0 then
    begin
      if Alone then
        Fixes := Fixes + [TRuleFix.Create(Format('%s: record einschränken', [TypeText]),
          [TRuleEdit.Create(TTextRange.Create(Tokens[Param].EndPos, Tokens[Param].EndPos), ': record')], False)];
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos), Format('Typparameter %s kann ' +
        'Finalisierung brauchen und ist im varianten Teil nicht erlaubt; record-Einschränkung verwenden ' +
        '(wie E2569).', [TypeText]), TRuleConfidence.High, Fixes);
      Exit;
    end;
    Kind := Types.Managed(TypeText, 0);
    if Kind <> '' then
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos), Format('%s braucht Finalisierung und ist ' +
        'im varianten Teil nicht erlaubt (wie E2154).', [TypeText]), TRuleConfidence.High,
        ShortStringFix(TypeRef) + Fixes)
    else if Types.CustomManaged(TypeText, 0) then
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos), Format('%s braucht Initialisierung und ' +
        'ist im varianten Teil nicht erlaubt (wie E2418).', [TypeText]), TRuleConfidence.High, Fixes);
  end;

  procedure CheckFile(AFile: TSyntaxNode);
  var
    TypeRef: TSyntaxNode;
    TypeText: string;
  begin
    TypeRef := TypeNode(AFile);
    if TypeRef = nil then
      Exit;
    TypeText := NodeText(TypeRef);
    if Types.Managed(TypeText, 0) <> '' then
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos), Format('%s braucht Finalisierung und ist ' +
        'in einem Dateityp nicht erlaubt (wie E2155).', [TypeText]), TRuleConfidence.High, ShortStringFix(TypeRef))
    else if Types.CustomManaged(TypeText, 0) then
      AReport.Add(TTextRange.Create(TypeRef.StartPos, TypeRef.EndPos), Format('%s braucht Initialisierung und ' +
        'ist in einem Dateityp nicht erlaubt (wie E2417).', [TypeText]), TRuleConfidence.High, nil);
  end;

var
  Stack: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Types := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    // Ohne Rekursion durch den Baum (#1094).
    SetLength(Stack, 64);
    Stack[0] := AContext.Tree.Root;
    Count := 1;
    while Count > 0 do
    begin
      Dec(Count);
      Node := Stack[Count];
      if (Node.Kind = TSyntaxKind.Field) and (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.CaseItem) and
        (Node.Parent.Parent <> nil) and (Node.Parent.Parent.Kind = TSyntaxKind.VariantPart) then
        CheckField(Node)
      else if Node.Kind = TSyntaxKind.FileType then
        CheckFile(Node);
      if Count + Node.ChildCount > Length(Stack) then
        SetLength(Stack, 2 * (Count + Node.ChildCount));
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Stack[Count] := Node[Index];
        Inc(Count);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TDefaultParameterRule }

function TDefaultParameterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DefaultParameterRuleId, TRuleSeverity.Warning,
    'Standardparameter statt Überladung', True);
end;

type
  TChangeParameters = TArray<Atlas.Common.Editing.ChangeSignature.TSignatureParameter>;

procedure TDefaultParameterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Lines: TArray<string>;
  LineBreak: string;
  Bodies, Calls: TArray<TSyntaxNode>;

  // Bezeichner des Namens im Kopf (beim Rumpf TFoo.Bar der letzte Teil); -1 ohne.
  function NameToken(AHeader: TSyntaxNode): Integer;
  var
    Index: Integer;
    Name: string;
  begin
    Name := BareName(AHeader.Name);
    Result := -1;
    for Index := TokenAtOffset(Tokens, AHeader.StartOffset) to High(Tokens) do
    begin
      if (Tokens[Index].Offset >= AHeader.EndOffset) or Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol(':') or
        Tokens[Index].IsSymbol(';') then
        Break;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, Name) then
        Result := Index;
    end;
  end;

  // Modifizierer und Typen ohne Namen und Standardwerte, kleingeschrieben.
  function ParamKey(const AParameters: TChangeParameters): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := 0 to High(AParameters) do
      Result := Result + LowerCase(AParameters[Index].Modifier + ' ' + AParameters[Index].TypeName) + ';';
  end;

  function IndentAt(AToken: Integer): string;
  begin
    Result := '';
    if Tokens[AToken].StartPos.Line <= High(Lines) then
      Result := TTextLines.IndentOf(Lines[Tokens[AToken].StartPos.Line]);
  end;

  function Conditional(const AHeader: TSignatureHeader): Boolean;
  begin
    Result := TConditionalBranches.PathAt(Paths, AHeader.StartToken) <> '';
  end;

  // Rumpf zur Deklaration: gleicher (qualifizierter) Name und gleiche Parameter, ohne Parameterliste nur eindeutig.
  function BodyOf(const AName: string; const ADecl: TSignatureHeader; out ABody: TSignatureHeader;
    out ABodyNode: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
    Candidate: TSignatureHeader;
    Count: Integer;
  begin
    Result := False;
    Count := 0;
    ABody := Default(TSignatureHeader);
    ABodyNode := nil;
    for Node in Bodies do
      if SameText(StringReplace(Node.Name, ' ', '', [rfReplaceAll]), AName) and
        TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(Node), Candidate) and
        (Candidate.StartToken > ADecl.LastToken) then
        if (Candidate.OpenToken < 0) or (ParamKey(Candidate.Parameters) = ParamKey(ADecl.Parameters)) then
        begin
          Inc(Count);
          ABody := Candidate;
          ABodyNode := Node;
          Result := True;
        end;
    Result := Result and (Count = 1);
  end;

  // Steht der Name irgendwo nicht als Aufruf (Methodenzeiger, @Routine)? Dann wäre er nach der Korrektur mehrdeutig.
  function UsedAsValue(const AName: string): Boolean;
  var
    Node: TSyntaxNode;
  begin
    for Node in Calls do
      if SameText(Node.Name, AName) and (Node.Parent <> nil) and (Node.Parent.Kind <> TSyntaxKind.CallStatement) and
        not ((Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node)) then
        Exit(True);
    Result := False;
  end;

  // " = Wert" hinter den Parametern des Kopfs AHeader entfernen; Zeilenumbrüche der Liste bleiben.
  function DefaultRemovals(AHeader: TSyntaxNode): TArray<TRuleEdit>;
  var
    Params, Param: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
      for Index := 0 to Params.ChildCount - 1 do
      begin
        Param := Params[Index];
        if (Param.Kind = TSyntaxKind.Parameter) and (Param.ChildCount > 1) then
          Result := Result + [TRuleEdit.Create(TTextRange.Create(Param[0].EndPos, Param[Param.ChildCount - 1].EndPos),
            '')];
      end;
  end;

  // Neue Routinen bzw. Köpfe vor ADecl: je eine Überladung ohne die letzten Standardparameter.
  function Fix(const ADecl: TSignatureHeader; ADeclNode: TSyntaxNode; AHasBody: Boolean;
    const ABody: TSignatureHeader; ABodyNode: TSyntaxNode; ADeclIsBody: Boolean; AFirst: Integer): TArray<TRuleEdit>;
  var
    Count, Index: Integer;
    Prefix: TChangeParameters;
    Changes: TArray<TParameterChange>;
    Parameter: Atlas.Common.Editing.ChangeSignature.TSignatureParameter;
    Indent, Declarations, Routines, Name: string;

    function Routine(const AHeader: TSignatureHeader; const AQualified, ADirectives: string): string;
    begin
      Result := TChangeSignature.HeaderText(AHeader, AQualified, Prefix, False) + ADirectives + LineBreak + 'begin' +
        LineBreak + '  ' + TChangeSignature.ForwardCall(AHeader, Prefix, Changes) + LineBreak + 'end;' + LineBreak +
        LineBreak;
    end;

  begin
    Indent := IndentAt(ADecl.StartToken);
    Name := BareName(ADecl.QualifiedName);
    Declarations := '';
    Routines := '';
    for Count := AFirst to High(ADecl.Parameters) do
    begin
      Prefix := Copy(ADecl.Parameters, 0, Count);
      Changes := nil;
      for Index := 0 to High(ADecl.Parameters) do
      begin
        Parameter := ADecl.Parameters[Index];
        if Index < Count then
          Changes := Changes + [TParameterChange.Kept(Index, Parameter.Name)]
        else
          Changes := Changes + [TParameterChange.Added(Parameter.Name, Parameter.TypeName, Parameter.Modifier,
            Parameter.DefaultValue)];
      end;
      if ADeclIsBody then
        Declarations := Declarations + Routine(ADecl, ADecl.QualifiedName,
          TChangeSignature.OverloadDirectives(ADecl, False)) + Indent
      else
      begin
        Declarations := Declarations + TChangeSignature.HeaderText(ADecl, Name, Prefix, False) +
          TChangeSignature.OverloadDirectives(ADecl, False) + LineBreak + Indent;
        if AHasBody then
          Routines := Routines + Routine(ABody, ABody.QualifiedName, '');
      end;
    end;
    Result := [TRuleEdit.Create(TTextRange.Create(Tokens[ADecl.StartToken].StartPos, Tokens[ADecl.StartToken].StartPos),
      Declarations)] + DefaultRemovals(ADeclNode);
    if not ADecl.HasDirective('overload') then
      Result := Result + [TRuleEdit.Create(TTextRange.Create(Tokens[ADecl.EndToken].EndPos,
        Tokens[ADecl.EndToken].EndPos), ' overload;')];
    if AHasBody then
    begin
      Result := Result + [TRuleEdit.Create(TTextRange.Create(Tokens[ABody.StartToken].StartPos,
        Tokens[ABody.StartToken].StartPos), Routines)];
      // Ein im Rumpf wiederholter Standardwert fällt ebenfalls weg.
      Result := Result + DefaultRemovals(ABodyNode);
    end;
  end;

  // Vorfahren, Nachfahren oder Aufrufer von außen geben die Signatur vor.
  function SignatureGiven(const AHeader: TSignatureHeader): Boolean;
  var
    Directive: string;
  begin
    for Directive in AHeader.Directives do
      if MatchText(Directive, ['virtual', 'dynamic', 'abstract', 'override', 'external', 'export']) or
        StartsText('message ', Directive) or StartsText('external ', Directive) then
        Exit(True);
    Result := False;
  end;

  // Meldet die Deklaration AHeader; AScope: andere Köpfe desselben Bereichs, AType: Typ bei Methoden.
  procedure CheckHeader(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>; AType: TSyntaxNode);
  var
    Decl, Body: TSignatureHeader;
    Params, Node, BodyNode: TSyntaxNode;
    First, Index: Integer;
    Names: TArray<string>;
    Message, Qualified: string;
    HasBody, DeclIsBody, CanFix: Boolean;
    Fixes: TArray<TRuleFix>;
  begin
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if (Params = nil) or not TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(AHeader), Decl) then
      Exit;
    First := -1;
    Names := nil;
    for Index := 0 to High(Decl.Parameters) do
      if Decl.Parameters[Index].DefaultValue <> '' then
      begin
        if First < 0 then
          First := Index;
        Names := Names + [Decl.Parameters[Index].Name];
      end;
    if First < 0 then
      Exit;
    if Length(Names) = 1 then
      Message := Format('Standardparameter; eine Überladung ohne %s hält den Vorgabewert in der Bibliothek.',
        [Names[0]])
    else
      Message := Format('Standardparameter; Überladungen ohne %s halten die Vorgabewerte in der Bibliothek.',
        [JoinedList(Names)]);
    // Korrektur nur, wo die neuen Überladungen sicher eindeutig sind und niemand die Signatur vorgibt.
    CanFix := not Conditional(Decl) and not UsedAsValue(BareName(AHeader.Name)) and
      ((AType = nil) or (AType.Kind <> TSyntaxKind.InterfaceType)) and not SignatureGiven(Decl);
    for Node in AScope do
      if (Node <> AHeader) and SameText(BareName(Node.Name), BareName(AHeader.Name)) then
        CanFix := False;
    HasBody := False;
    Body := Default(TSignatureHeader);
    BodyNode := nil;
    DeclIsBody := (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) and
      (AHeader.Parent.FindChild(TSyntaxKind.Block) <> nil);
    if CanFix and not DeclIsBody then
    begin
      Qualified := BareName(AHeader.Name);
      if AType <> nil then
      begin
        // Verschachtelte und generische Typen: Rumpf nicht sicher zuzuordnen.
        if (AType.Parent = nil) or (AType.Parent.Kind <> TSyntaxKind.TypeDecl) or (AType.Parent.Parent = nil) or
          (AType.Parent.Parent.Kind <> TSyntaxKind.TypeSection) or (Pos('<', AType.Parent.Name) > 0) then
          CanFix := False
        else
          Qualified := AType.Parent.Name + '.' + Qualified;
      end;
      HasBody := CanFix and BodyOf(Qualified, Decl, Body, BodyNode);
      CanFix := HasBody and not Conditional(Body);
    end;
    Fixes := nil;
    if CanFix then
      Fixes := [TRuleFix.Create('Überladungen statt Standardparameter',
        Fix(Decl, AHeader, HasBody, Body, BodyNode, DeclIsBody, First))];
    for Index := 0 to Params.ChildCount - 1 do
      if (Params[Index].Kind = TSyntaxKind.Parameter) and (Params[Index].ChildCount > 1) then
      begin
        AReport.Add(TTextRange.Create(Params[Index].StartPos, Params[Params.ChildCount - 1].EndPos), Message,
          TRuleConfidence.High, Fixes);
        Break;
      end;
  end;

  // Köpfe von Routinen direkt unter ANode; Rümpfe zu einer früheren Deklaration zählen nicht.
  procedure CheckRoutines(ANode: TSyntaxNode; var AScope: TArray<TSyntaxNode>);
  var
    Index: Integer;
    Header: TSyntaxNode;
  begin
    if ANode = nil then
      Exit;
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        Header := ANode[Index].FindChild(TSyntaxKind.RoutineHeader);
        if (Header <> nil) and (Pos('.', Header.Name) = 0) then
          AScope := AScope + [Header];
      end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Scope, Declared: TArray<TSyntaxNode>;
    Node, Header, Other: TSyntaxNode;
    Index: Integer;
    IsBody: Boolean;
    Decl, Earlier: TSignatureHeader;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Scope := nil;
        Declared := nil;
        case Node.Kind of
          TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.HelperType:
            begin
              for Index := 0 to Node.ChildCount - 1 do
                if Node[Index].Kind = TSyntaxKind.RoutineHeader then
                  Scope := Scope + [Node[Index]];
              for Header in Scope do
                CheckHeader(Header, Scope, Node);
            end;
          TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.RoutineDecl:
            begin
              if Node.Kind = TSyntaxKind.UnitFile then
              begin
                CheckRoutines(Node.FindChild(TSyntaxKind.InterfaceSection), Scope);
                CheckRoutines(Node.FindChild(TSyntaxKind.ImplementationSection), Scope);
              end
              else
                CheckRoutines(Node, Scope);
              for Header in Scope do
              begin
                // Rumpf zu einer früheren Deklaration (interface, forward) mit gleichen Parametern.
                IsBody := False;
                if (Header.Parent.FindChild(TSyntaxKind.Block) <> nil) and
                  TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(Header), Decl) then
                  for Other in Scope do
                    if (Other <> Header) and (Other.Parent.FindChild(TSyntaxKind.Block) = nil) and
                      SameText(Other.Name, Header.Name) and (Other.StartOffset < Header.StartOffset) and
                      TChangeSignature.ReadHeader(AContext.Text, Tokens, NameToken(Other), Earlier) and
                      ((Decl.OpenToken < 0) or (ParamKey(Decl.Parameters) = ParamKey(Earlier.Parameters))) then
                      IsBody := True;
                if not IsBody then
                  Declared := Declared + [Header];
              end;
              for Header in Declared do
                CheckHeader(Header, Declared, nil);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Bodies := nil;
  Calls := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and (ANode.Parent.FindChild(TSyntaxKind.Block) <> nil) then
        Bodies := Bodies + [ANode]
      else if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
        Calls := Calls + [ANode];
      Result := True;
    end);
  Visit(AContext.Tree.Root);
end;

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeclaredNotImplementedRule.Create);
  ARegistry.Register(TImplementedNotDeclaredRule.Create);
  ARegistry.Register(TSignatureMismatchRule.Create);
  ARegistry.Register(TInterfaceNotImplementedRule.Create);
  ARegistry.Register(TFieldAfterMethodRule.Create);
  ARegistry.Register(TOverloadDirectiveMissingRule.Create);
  ARegistry.Register(TDuplicateDeclarationRule.Create);
  ARegistry.Register(TVariantRecordManagedFieldRule.Create);
  ARegistry.Register(TTypeTooLargeRule.Create);
  ARegistry.Register(TDefaultParameterRule.Create);
end;

end.
