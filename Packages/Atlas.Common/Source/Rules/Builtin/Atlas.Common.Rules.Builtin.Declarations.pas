unit Atlas.Common.Rules.Builtin.Declarations;

// Deklaration und Rumpf passen nicht zusammen (#124):
//   declared-not-implemented   Methode im Typ ohne Rumpf (sonst erst E2065)
//   implemented-not-declared   Rumpf TFoo.Bar ohne Deklaration im Typ
//   signature-mismatch         Rumpf und Deklaration gleichen Namens mit
//                              abweichendem Kopf (#996, wie E2037): Parameter
//                              (Anzahl, Name, Typ, const/var/out), Ergebnistyp,
//                              procedure/function, Aufrufkonvention; ebenso
//                              eine Routine im interface-Teil und ihr Rumpf
//                              (#1380, Cm.E2037), wenn der Name eindeutig ist,
//                              ohne overload und external, und der Rumpf nicht
//                              die Kurzform ohne Parameter und Ergebnis hat
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
//                              bleibt die Regel still (TNameResolver.Queries.
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
  Atlas.Common.Semantics.TypeIdentity,
  Atlas.Common.Rules.Builtin.Declarations.Overloads,
  Atlas.Common.Rules.Builtin.Declarations.Duplicates,
  Atlas.Common.Rules.Builtin.Declarations.TypeSizes,
  Atlas.Common.Rules.Builtin.Declarations.VariantRecords,
  Atlas.Common.Rules.Builtin.Declarations.Defaults;

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

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.Overloads.</summary>
  TOverloadDirectiveMissingRule = Atlas.Common.Rules.Builtin.Declarations.Overloads.TOverloadDirectiveMissingRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.Duplicates.</summary>
  TDuplicateDeclarationRule = Atlas.Common.Rules.Builtin.Declarations.Duplicates.TDuplicateDeclarationRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.TypeSizes.</summary>
  TTypeTooLargeRule = Atlas.Common.Rules.Builtin.Declarations.TypeSizes.TTypeTooLargeRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.VariantRecords.</summary>
  TVariantRecordManagedFieldRule = Atlas.Common.Rules.Builtin.Declarations.VariantRecords.TVariantRecordManagedFieldRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.Defaults.</summary>
  TDefaultParameterRule = Atlas.Common.Rules.Builtin.Declarations.Defaults.TDefaultParameterRule;

const
  FieldAfterMethodRuleId = 'field-after-method';
  DuplicateDeclarationRuleId = Atlas.Common.Rules.Builtin.Declarations.Duplicates.DuplicateDeclarationRuleId;
  OverloadDirectiveMissingRuleId = Atlas.Common.Rules.Builtin.Declarations.Overloads.OverloadDirectiveMissingRuleId;
  DefaultParameterRuleId = Atlas.Common.Rules.Builtin.Declarations.Defaults.DefaultParameterRuleId;

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
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines;

/// <summary>Beginnt die Direktive AText (groß geschrieben) einen {$IF…}-Block?</summary>
function IsIfStart(const AText: string): Boolean;
begin
  Result := StartsStr('{$IF', AText) or StartsStr('(*$IF', AText);
end;

/// <summary>Beendet die Direktive AText (groß geschrieben) einen {$IF…}-Block?</summary>
function IsIfEnd(const AText: string): Boolean;
begin
  Result := StartsStr('{$ENDIF', AText) or StartsStr('{$IFEND', AText) or StartsStr('(*$ENDIF', AText) or
    StartsStr('(*$IFEND', AText);
end;

/// <summary>Markiert die Zeilen AFrom bis ATo.</summary>
procedure MarkLines(var ALines: TArray<Boolean>; AFrom, ATo: Integer);
var
  Line: Integer;
begin
  for Line := AFrom to ATo do
  begin
    ALines[Line] := True;
  end;
end;

/// <summary>Zeilen innerhalb von {$IF…}…{$ENDIF}: Element I gilt für Zeile I.</summary>
function ConditionalLines(const AContext: TRuleContext): TArray<Boolean>;
var
  Token: TPascalToken;
  Text: string;
  Depth, LastLine, StartLine: Integer;
begin
  LastLine := 0;
  for Token in AContext.Tree.Tokens do
  begin
    LastLine := Token.EndPos.Line;
  end;
  SetLength(Result, LastLine + 1);
  Depth := 0;
  StartLine := 0;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Text := UpperCase(Token.Text);
    if IsIfStart(Text) then
    begin
      if Depth = 0 then
      begin
        StartLine := Token.StartPos.Line;
      end;
      Inc(Depth);
    end
    else if (Depth > 0) and IsIfEnd(Text) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        MarkLines(Result, StartLine, Token.EndPos.Line);
      end;
    end;
  end;
  // Nicht geschlossener Block: bis zum Dateiende.
  if Depth > 0 then
  begin
    MarkLines(Result, StartLine, LastLine);
  end;
end;

/// <summary>Bindet die Datei Include-Dateien ein ({$I datei} oder {$INCLUDE datei})?</summary>
function HasIncludes(const AContext: TRuleContext): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(Token.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', Text) or StartsStr('{$I ', Text) then
      begin
        Exit(True);
      end;
    end;
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
  begin
    if (Pair.Declaration.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) or
      (Pair.Body.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Confidence(const AContext: TRuleContext): TRuleConfidence;
begin
  if HasIncludes(AContext) then
  begin
    Result := TRuleConfidence.Medium;
  end
  else
  begin
    Result := TRuleConfidence.High;
  end;
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
  begin
    Exit;
  end;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  Pairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if not Method.Declared or IsConditional(Lines, Method) or InPair(Pairs, Method) then
    begin
      Continue;
    end;
    Fixes := nil;
    if TClassCompletion.MissingBodies(AContext.Tree, AContext.Text, Method.Symbol.SelectionRange.StartPos, Action) then
    begin
      Fixes := [TRuleFix.Create(Action.Title, Action.Edits)];
    end;
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
  begin
    Exit;
  end;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  Pairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if Method.Declared or IsConditional(Lines, Method) or InPair(Pairs, Method) then
    begin
      Continue;
    end;
    Fixes := nil;
    if TClassCompletion.AddDeclaration(AContext.Tree, AContext.Text, Method, Edit) then
    begin
      Fixes := [TRuleFix.Create(Format('Deklaration von %s in %s ergänzen', [Method.Symbol.Name,
        Method.TypeName]), [Edit])];
    end;
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

/// <summary>Steht im Token AIndex ein implements innerhalb der Zeilen von ARange?</summary>
function ImplementsAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ARange: TTextRange): Boolean;
begin
  Result := (ATokens[AIndex].StartPos.Line >= ARange.StartPos.Line) and
    (ATokens[AIndex].EndPos.Line <= ARange.EndPos.Line) and SameText(ATokens[AIndex].Text, 'implements') and
    (ATokens[AIndex].Kind = TPascalTokenKind.Identifier);
end;

/// <summary>Interfaces hinter implements im Token AIndex (implements IFoo, Units.IBar;); AIndex steht danach auf
/// dem Semikolon.</summary>
function DelegatedNames(const ATokens: TArray<TPascalToken>; var AIndex: Integer): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  Inc(AIndex);
  Name := '';
  while (AIndex <= High(ATokens)) and not ATokens[AIndex].IsSymbol(';') do
  begin
    if ATokens[AIndex].IsSymbol(',') then
    begin
      Result := Result + [Name];
      Name := '';
    end
    else if ATokens[AIndex].Kind <> TPascalTokenKind.Comment then
    begin
      Name := Name + ATokens[AIndex].Text;
    end;
    Inc(AIndex);
  end;
  if Name <> '' then
  begin
    Result := Result + [Name];
  end;
end;

class function TInterfaceNotImplementedRule.Delegated(const ATokens: TArray<TPascalToken>;
  const ARange: TTextRange): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if ImplementsAt(ATokens, Index, ARange) then
    begin
      Result := Result + DelegatedNames(ATokens, Index);
    end;
    Inc(Index);
  end;
end;

/// <summary>Methode AName der Klasse ATypeName (ohne Zuordnungen); Name leer, wenn es keine gibt.</summary>
function OwnMethod(const AUnit: TUnitIndex; const ATypeName, AName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.Container, ATypeName) and SameText(Symbol.Name, AName) and
      (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
    begin
      Exit(Symbol);
    end;
  end;
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
        begin
          Found.Add(ANode);
        end;
        Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]);
      end);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

type
  /// <summary>interface-not-implemented für eine Datei: fehlende Interface-Methoden je Klasse und Zuordnungen
  /// (procedure IFoo.Bar = Baz) für Interfaces, die die Klasse nicht nennt.</summary>
  TInterfaceCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<Boolean>;
    FLevel: TRuleConfidence;
    FResolver: TNameResolver;
    FOwnUnit: TUnitIndex;
    FHeaders: TArray<TSyntaxNode>;
    FActions: TClassActionContext;
    function IsCandidate(const AType: TIndexSymbol): Boolean;
    function MissingNames(const AMissing: TArray<TResolvedSymbol>; const ATypeName: string;
      out ADiffers: Boolean): TArray<string>;
    function InterfaceFixes(const AType: TIndexSymbol): TArray<TRuleFix>;
    procedure CheckMissing(const AType: TIndexSymbol; const ATypeName: string);
    function Listed(const AType: TIndexSymbol; const APrefix: string): Boolean;
    procedure CheckResolutions(const AType: TIndexSymbol; const ATypeName: string);
    procedure CheckType(const AType: TIndexSymbol);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; AResolver: TNameResolver;
      const AIndex: ISymbolIndex);
    /// <summary>Prüft alle Klassen der Datei.</summary>
    procedure Run;
  end;

constructor TInterfaceCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  AResolver: TNameResolver; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FResolver := AResolver;
  FLines := ConditionalLines(AContext);
  FLevel := Confidence(AContext);
  FOwnUnit := AResolver.ExtractedUnit(AContext.Tree, AContext.RelativePath);
  FHeaders := ResolutionHeaders(AContext.Tree);
  FActions := TClassActionContext.Default;
  FActions.Index := AIndex;
  FActions.Namespaces := AContext.Namespaces;
  FActions.DelphiVersion := AContext.DelphiVersion;
  FActions.Style := AContext.Formatting;
end;

// Klasse mit Vorfahren außerhalb von {$IF…}-Blöcken?
function TInterfaceCheck.IsCandidate(const AType: TIndexSymbol): Boolean;
var
  Line: Integer;
begin
  Line := AType.SelectionRange.StartPos.Line;
  Result := (AType.Kind = TIndexSymbolKind.ClassType) and (Length(AType.Ancestors) > 0);
  Result := Result and not ((Line <= High(FLines)) and FLines[Line]);
end;

// Namen der fehlenden Methoden (Interface.Methode, sortiert). Gleichnamige Methode der Klasse mit anderer
// Signatur: E2211 an der Methode statt "fehlt", ADiffers.
function TInterfaceCheck.MissingNames(const AMissing: TArray<TResolvedSymbol>; const ATypeName: string;
  out ADiffers: Boolean): TArray<string>;
var
  Member: TResolvedSymbol;
  Own: TIndexSymbol;
  Names: TList<string>;
  Name: string;
begin
  ADiffers := False;
  Names := TList<string>.Create;
  try
    for Member in AMissing do
    begin
      Own := OwnMethod(FOwnUnit, ATypeName, Member.Name);
      Name := BareName(Member.Container) + '.' + Member.Name;
      if Own.Name <> '' then
      begin
        ADiffers := True;
        FReport.Add(Own.SelectionRange, Format('%s weicht von der Deklaration in %s ab (wie E2211).',
          [Own.Name, BareName(Member.Container)]), FLevel);
      end
      else if not Names.Contains(Name) then
      begin
        Names.Add(Name);
      end;
    end;
    Names.Sort;
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

// "Interface implementieren" je Vorfahr, ab dem zweiten als Alternative.
function TInterfaceCheck.InterfaceFixes(const AType: TIndexSymbol): TArray<TRuleFix>;
var
  Ancestor: string;
  Action: TCodeAction;
begin
  Result := nil;
  for Ancestor in AType.Ancestors do
  begin
    if TClassActions.ImplementInterface(FContext.Text, AType.Range.StartPos.Line, Ancestor, FActions, Action) then
    begin
      Result := Result + [Alternative(TRuleFix.Create(Action.Title, Action.Edits), Length(Result) > 0)];
    end;
  end;
end;

procedure TInterfaceCheck.CheckMissing(const AType: TIndexSymbol; const ATypeName: string);
var
  Missing: TArray<TResolvedSymbol>;
  Names: TArray<string>;
  Complete, Differs: Boolean;
  Fixes: TArray<TRuleFix>;
begin
  Missing := FResolver.Queries.MissingInterfaceMembers(FOwnUnit, ATypeName, nil,
    TInterfaceNotImplementedRule.Delegated(FContext.Tree.Tokens, AType.Range), Complete);
  if not Complete or (Length(Missing) = 0) then
  begin
    Exit;
  end;
  Names := MissingNames(Missing, ATypeName, Differs);
  // Bei abweichenden Köpfen fügte die Korrektur eine zweite gleichnamige Methode ein; dann keine.
  Fixes := nil;
  if not Differs then
  begin
    Fixes := InterfaceFixes(AType);
  end;
  if Length(Names) = 1 then
  begin
    FReport.Add(AType.SelectionRange, Format('%s fehlt in %s (wie E2291).', [Names[0], AType.Name]), FLevel, Fixes);
  end
  else if Length(Names) > 1 then
  begin
    FReport.Add(AType.SelectionRange, Format('%s fehlen in %s (wie E2291).', [JoinedList(Names), AType.Name]),
      FLevel, Fixes);
  end;
end;

// Nennt die Klasse AType das Interface APrefix?
function TInterfaceCheck.Listed(const AType: TIndexSymbol; const APrefix: string): Boolean;
var
  Ancestor: string;
begin
  Result := False;
  for Ancestor in AType.Ancestors do
  begin
    Result := Result or SameText(BareName(Ancestor), APrefix);
  end;
end;

// Zuordnung "procedure IFoo.Bar = Baz" für ein Interface, das die Klasse nicht nennt; die Zuordnungen sind keine
// Mitglieder (#849), ihre Stelle steht nur im Baum.
procedure TInterfaceCheck.CheckResolutions(const AType: TIndexSymbol; const ATypeName: string);
var
  Header: TSyntaxNode;
  Prefix: string;
begin
  for Header in FHeaders do
  begin
    if not SameText(Header.EnclosingTypeName, ATypeName) then
    begin
      Continue;
    end;
    Prefix := BareName(Copy(Header.Name, 1, LastDelimiter('.', Header.Name) - 1));
    if not Listed(AType, Prefix) then
    begin
      FReport.Add(TTextRange.Create(Header.StartPos, Header.EndPos),
        Format('%s steht nicht in der Interface-Liste von %s (wie E2265).', [Prefix, AType.Name]), FLevel);
    end;
  end;
end;

procedure TInterfaceCheck.CheckType(const AType: TIndexSymbol);
var
  TypeName: string;
begin
  if not IsCandidate(AType) then
  begin
    Exit;
  end;
  TypeName := AType.Name;
  if AType.Container <> '' then
  begin
    TypeName := AType.Container + '.' + TypeName;
  end;
  CheckMissing(AType, TypeName);
  CheckResolutions(AType, TypeName);
end;

procedure TInterfaceCheck.Run;
var
  TypeSymbol: TIndexSymbol;
begin
  for TypeSymbol in FOwnUnit.Symbols do
  begin
    CheckType(TypeSymbol);
  end;
end;

procedure TInterfaceNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Checker: TInterfaceCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Ohne Projektindex prüft die Regel nur, was die Datei selbst kennt; unbekannte Vorfahren halten sie still.
  Index := AContext.Index;
  if Index = nil then
  begin
    Index := TSymbolIndex.Create;
  end;
  Resolver := TNameResolver.Create(Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      Checker := TInterfaceCheck.Create(AContext, AReport, Resolver, Index);
      try
        Checker.Run;
      finally
        Checker.Free;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
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
  begin
    Result := TTypeMatch.Same;
  end
  else
  begin
    Result := TTypeMatch.Different;
  end;
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
  begin
    FResolver.UnpinTree;
  end;
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
  begin
    if mToken.StartPos = APosition then
    begin
      Exit(mToken.Offset);
    end;
  end;
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

/// <summary>Abweichung der Modifizierer (const, var …) eines Parameters, z. B. "Betrag ohne const".</summary>
function ModifierDifference(const ADecl, ABody: TShapeParameter): string;
begin
  if ABody.Modifier = '' then
  begin
    Result := Format('%s ohne %s', [ABody.Name, ADecl.Modifier]);
  end
  else if ADecl.Modifier = '' then
  begin
    Result := Format('%s mit %s', [ABody.Name, ABody.Modifier]);
  end
  else
  begin
    Result := Format('%s %s statt %s', [ABody.Name, ABody.Modifier, ADecl.Modifier]);
  end;
end;

/// <summary>Abweichung des Typs eines Parameters, z. B. "Datum TDateTime statt TDate".</summary>
function TypeDifference(const ADecl, ABody: TShapeParameter): string;
begin
  if ABody.TypeName = '' then
  begin
    Result := Format('%s ohne Typ statt %s', [ABody.Name, ADecl.TypeName]);
  end
  else if ADecl.TypeName = '' then
  begin
    Result := Format('%s %s statt ohne Typ', [ABody.Name, ABody.TypeName]);
  end
  else
  begin
    Result := Format('%s %s statt %s', [ABody.Name, ABody.TypeName, ADecl.TypeName]);
  end;
end;

/// <summary>Aufrufkonvention von AShape, register ohne Angabe.</summary>
function ConventionOf(const AShape: TSignatureShape): string;
begin
  Result := AShape.Convention;
  if Result = '' then
  begin
    Result := 'register';
  end;
end;

class function TSignatureMismatchRule.Differences(const ADeclaration, ABody: TSignatureShape;
  const AMatch: TSignatureTypeMatch): TArray<string>;

  function Differs(const ADeclType, ABodyType: string): Boolean;
  begin
    if (ADeclType = '') or (ABodyType = '') then
    begin
      Result := (ADeclType <> '') or (ABodyType <> '');
    end
    else
    begin
      Result := AMatch(ADeclType, ABodyType) = TTypeMatch.Different;
    end;
  end;

  // Abweichungen gleich vieler Parameter: Name, Modifizierer, Typ.
  function ParameterDifferences: TArray<string>;
  var
    Index: Integer;
    Decl, Body: TShapeParameter;
  begin
    Result := nil;
    for Index := 0 to High(ABody.Parameters) do
    begin
      Decl := ADeclaration.Parameters[Index];
      Body := ABody.Parameters[Index];
      if not SameText(Decl.Name, Body.Name) then
      begin
        Result := Result + [Format('%s statt %s', [Body.Name, Decl.Name])];
      end;
      if Decl.Modifier <> Body.Modifier then
      begin
        Result := Result + [ModifierDifference(Decl, Body)];
      end;
      if Differs(Decl.TypeName, Body.TypeName) then
      begin
        Result := Result + [TypeDifference(Decl, Body)];
      end;
    end;
  end;

begin
  Result := nil;
  if (ADeclaration.Kind <> '') and (ABody.Kind <> '') and (ADeclaration.Kind <> ABody.Kind) then
  begin
    Result := Result + [Format('%s statt %s', [ABody.Kind, ADeclaration.Kind])];
  end;
  if Length(ADeclaration.Parameters) <> Length(ABody.Parameters) then
  begin
    Result := Result + [Format('%d statt %d Parameter', [Length(ABody.Parameters), Length(ADeclaration.Parameters)])];
  end
  else
  begin
    Result := Result + ParameterDifferences;
  end;
  if (ADeclaration.Kind = ABody.Kind) and Differs(ADeclaration.ResultType, ABody.ResultType) then
  begin
    Result := Result + [Format('Ergebnis %s statt %s', [ABody.ResultType, ADeclaration.ResultType])];
  end;
  // Der Rumpf darf die Konvention weglassen; nur eine abweichende Angabe ist ein Fehler.
  if (ABody.Convention <> '') and (ConventionOf(ABody) <> ConventionOf(ADeclaration)) then
  begin
    Result := Result + [Format('%s statt %s', [ABody.Convention, ConventionOf(ADeclaration)])];
  end;
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
  mCache: IRuleDerivedCache;

  /// <summary>Routinen auf oberster Ebene von ASection namens AName.</summary>
  function Routines(ASection: TSyntaxNode; const AName: string): TArray<TSyntaxNode>;
  var
    mIndex: Integer;
  begin
    Result := nil;
    if ASection <> nil then
    begin
      for mIndex := 0 to ASection.ChildCount - 1 do
      begin
        if (ASection[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ASection[mIndex].Name, AName) then
        begin
          Result := Result + [ASection[mIndex]];
        end;
      end;
    end;
  end;

  function HasDirective(ARoutine: TSyntaxNode; const ADirective: string): Boolean;
  var
    mHeader: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if mHeader <> nil then
    begin
      for mIndex := 0 to mHeader.ChildCount - 1 do
      begin
        if (mHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(mHeader[mIndex].Name, ADirective) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;

  /// <summary>Symbol der Routine ARoutine im Index der Datei.</summary>
  function SymbolOf(const AUnit: TUnitIndex; ARoutine: TSyntaxNode; out ASymbol: TIndexSymbol): Boolean;
  var
    mSymbol: TIndexSymbol;
  begin
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Routine) and (mSymbol.Container = '') and
        SameText(mSymbol.Name, ARoutine.Name) and (mSymbol.Range.StartPos.Line = ARoutine.StartPos.Line) then
      begin
        ASymbol := mSymbol;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Kommt die Routine ADecl des interface-Teils AInterface für ein Paar in Frage: eindeutiger Name
  /// ohne Punkt, ohne overload, external und forward?</summary>
  function IsPairCandidate(AInterface, ADecl: TSyntaxNode): Boolean;
  begin
    Result := (ADecl.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', ADecl.Name) = 0) and
      (Length(Routines(AInterface, ADecl.Name)) = 1);
    Result := Result and not HasDirective(ADecl, 'overload') and not HasDirective(ADecl, 'external') and
      not HasDirective(ADecl, 'forward');
  end;

  /// <summary>Paar aus Deklaration ADecl und Rumpf ABody mit Symbolen und Köpfen; False, wenn eines fehlt oder
  /// der Rumpf die Kurzform ohne Parameter und Ergebnis hat.</summary>
  function PairOf(const AUnit: TUnitIndex; ADecl, ABody: TSyntaxNode; out APair: TSignaturePair): Boolean;
  begin
    APair := Default(TSignaturePair);
    Result := SymbolOf(AUnit, ADecl, APair.Declaration.Symbol) and SymbolOf(AUnit, ABody, APair.Body.Symbol);
    Result := Result and TClassCompletion.Shape(AContext.Tree, AContext.Text, APair.Declaration.Symbol,
      APair.DeclarationShape) and TClassCompletion.Shape(AContext.Tree, AContext.Text, APair.Body.Symbol,
      APair.BodyShape);
    Result := Result and ((APair.BodyShape.Parameters <> nil) or (APair.BodyShape.ResultType <> ''));
    APair.Declaration.Declared := True;
  end;

  /// <summary>Routine im interface-Teil mit ihrem Rumpf (#1380): dcc meldet E2037, wenn der Rumpf anders
  /// aussieht und die Deklaration kein overload hat (Cm.E2037). Nur eindeutige Namen; Rümpfe in der Kurzform
  /// ohne Parameter und Ergebnis übernehmen den Kopf. Mit Include-Dateien kann dort ein weiterer Rumpf stehen.
  /// </summary>
  function RoutinePairs: TArray<TSignaturePair>;
  var
    mInterface, mImplementation, mDecl: TSyntaxNode;
    mBodies: TArray<TSyntaxNode>;
    mIndex: Integer;
    mUnit: TUnitIndex;
    mPair: TSignaturePair;
  begin
    Result := nil;
    if (AContext.Tree.Root = nil) or HasIncludes(AContext) then
    begin
      Exit;
    end;
    mInterface := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
    mImplementation := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    if (mInterface = nil) or (mImplementation = nil) then
    begin
      Exit;
    end;
    mUnit := TRuleDerived.UnitIndex(mCache, AContext);
    for mIndex := 0 to mInterface.ChildCount - 1 do
    begin
      mDecl := mInterface[mIndex];
      if not IsPairCandidate(mInterface, mDecl) then
      begin
        Continue;
      end;
      mBodies := Routines(mImplementation, mDecl.Name);
      if (Length(mBodies) = 1) and (mBodies[0].FindChild(TSyntaxKind.Block) <> nil) and
        PairOf(mUnit, mDecl, mBodies[0], mPair) then
      begin
        Result := Result + [mPair];
      end;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  mCache := TRuleDerived.Open(AContext);
  mTypes := TSignatureTypes.Create(AContext);
  try
    for Pair in TClassCompletion.Pairs(AContext.Tree, AContext.Text) + RoutinePairs do
    begin
      // Bedingte Übersetzung im Kopf ({$IFDEF} in der Parameterliste): Welche Parameter gelten, ist offen (#1324).
      if IsConditional(Lines, Pair.Declaration) or IsConditional(Lines, Pair.Body) or
        Pair.DeclarationShape.Conditional or Pair.BodyShape.Conditional then
      begin
        Continue;
      end;
      Changes := Differences(Pair.DeclarationShape, Pair.BodyShape, mTypes.Matcher(Pair));
      if Changes = nil then
      begin
        Continue;
      end;
      Fixes := nil;
      // refactoring.syncSignatures aus (#100): die Meldung bleibt, die Angleich-Aktionen entfallen.
      if not AContext.NoSignatureSync and TClassCompletion.PairFixes(AContext.Tree, AContext.Text, Pair, Actions) then
      begin
        for Index := 0 to High(Actions) do
        begin
          Fixes := Fixes + [Alternative(TRuleFix.Create(Actions[Index].Title, Actions[Index].Edits), Index > 0)];
        end;
      end;
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
    begin
      Dec(AIndex);
    end;
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
    begin
      Exit;
    end;
    FieldStart := StartLine(Field);
    FieldEnd := ABody[AField].EndPos.Line;
    TargetLine := StartLine(Target);
    if (TargetLine >= FieldStart) or (FieldEnd + 1 >= Length(Lines)) then
    begin
      Exit;
    end;
    Moved := '';
    for Line := FieldStart to FieldEnd do
    begin
      Moved := Moved + Lines[Line] + LineBreak;
    end;
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

  // Ist ABody[AMember] eine Methode oder Property, die immer mit übersetzt wird, wenn das Feld ABody[AField]
  // übersetzt wird?
  function Guards(ABody: TSyntaxNode; AMember, AField: Integer): Boolean;
  begin
    Result := (ABody[AMember].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) and
      TConditionalBranches.Implies(PathOf(ABody[AField]), PathOf(ABody[AMember]));
  end;

  // Gibt es zwischen ABody[AFirst] und dem Feld ABody[AField] eine Methode, die es sicher vor dem Feld gibt?
  function HasGuard(ABody: TSyntaxNode; AFirst, AField: Integer): Boolean;
  var
    Member: Integer;
  begin
    Member := AFirst;
    while (Member < AField) and not Guards(ABody, Member, AField) do
    begin
      Inc(Member);
    end;
    Result := Member < AField;
  end;

  // Meldet das Feld ABody[AField] hinter dem ersten Mitglied ABody[AFirst]; ASamePaths: keine Bedingungen
  // zwischen den Mitgliedern.
  procedure CheckField(ABody: TSyntaxNode; AField, AFirst: Integer; ASamePaths: Boolean);
  var
    Fixes: TArray<TRuleFix>;
  begin
    if not HasGuard(ABody, AFirst, AField) then
    begin
      Exit;
    end;
    Fixes := nil;
    // Verschieben nur ohne Bedingungen dazwischen, sonst landet das Feld in einem anderen Zweig.
    if ASamePaths and (PathOf(ABody[AField]) = PathOf(ABody[AFirst])) then
    begin
      Fixes := MoveFix(ABody, AField, AFirst);
    end;
    if ABody.Kind = TSyntaxKind.RecordType then
    begin
      // In Records verschiebt das Verschieben das Speicherlayout; var zuerst.
      Fixes := [VarFix(ABody, AField)] + Fixes;
    end
    else
    begin
      Fixes := Fixes + [VarFix(ABody, AField)];
    end;
    AReport.Add(TTextRange.Create(ABody[AField].StartPos, ABody[AField].EndPos),
      'Feld nach Methoden im selben Abschnitt (wie E2169).', TRuleConfidence.High, Fixes);
  end;

  procedure CheckBody(ABody: TSyntaxNode);
  var
    Index, First: Integer;
    SamePaths: Boolean;
  begin
    First := -1;
    SamePaths := True;
    for Index := 0 to ABody.ChildCount - 1 do
    begin
      case ABody[Index].Kind of
        // Ein neuer Abschnitt bzw. var erlaubt wieder Felder.
        TSyntaxKind.Visibility, TSyntaxKind.VarSection, TSyntaxKind.TypeSection, TSyntaxKind.ConstSection:
          begin
            First := -1;
            SamePaths := True;
          end;
        TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
          if First < 0 then
          begin
            First := Index;
          end
          else if PathOf(ABody[Index]) <> PathOf(ABody[First]) then
          begin
            SamePaths := False;
          end;
        TSyntaxKind.Field:
          if First >= 0 then
          begin
            CheckField(ABody, Index, First, SamePaths);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
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
        begin
          CheckBody(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Paths := TConditionalBranches.Paths(Tokens);
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
