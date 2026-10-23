unit Atlas.Common.Rules.Builtin.DeadCode;

// Toter Code und zirkuläre Unit-Abhängigkeiten (#64):
//   uses-cycle          Ein uses-Eintrag, über den ein Weg zurück zur eigenen
//                       Unit führt (Gruppe Architektur). Liegt jede Kante im
//                       interface-Teil, ist es ein Fehler wie F2047; Zyklen mit
//                       mindestens einer implementation-Kante sind erlaubt und
//                       erscheinen mit dem Schweregrad der Regel (Option
//                       implementation, Vorgabe an). Die Meldung nennt den
//                       vollständigen kürzesten Pfad, der Befund-Hover jede
//                       Kante mit ihrem Abschnitt. Grundlage ist der
//                       gemeinsame Uses-Graph (#268) über IRuleProjectFiles;
//                       für die eigene Unit gilt der Editor-Stand.
//   unused-declaration  Routine, Typ, Konstante oder globale Variable aus dem
//                       implementation-Teil (bzw. einem Programm), die in der
//                       Unit nirgends vorkommt. Keine Verwendung sind die
//                       eigenen Deklarationen, Vorkommen im eigenen Rumpf
//                       (Rekursion) und bei Typen in der eigenen Deklaration
//                       und den Rümpfen der eigenen Methoden samt Kopf
//                       (TTyp.Name). Ausnahmen aus dem Dienst „gilt als
//                       verwendet“ (exports, Attribute, deadCode.keep*), Namen
//                       aus der Formulardatei; Units mit Include-Dateien
//                       schweigen. Die Deklarationen des interface-Teils
//                       prüft unused-public-member projektweit.
//   unused-unit         Unit einer Anwendung, die keine andere Unit verwendet:
//                       Höchstens Programme nennen sie im uses und verwenden
//                       außerhalb ihres uses keinen ihrer Bezeichner (z. B.
//                       Application.CreateForm(TForm1, Form1)). Units mit
//                       initialization- oder finalization-Teil (Registrierung)
//                       gelten als verwendet, Packages und DLLs haben Nutzer
//                       außerhalb der Gruppe (Option projectKinds).
//
// uses-cycle und unused-unit schweigen ohne Projekte (Linter, Datei ohne
// Projekt), solange Projekte laden oder der Index läuft, und für Units, die der
// Uses-Graph nicht kennt.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UsesCycleRuleId = 'uses-cycle';
  UnusedDeclarationRuleId = 'unused-declaration';
  UnusedUnitRuleId = 'unused-unit';

type
  TUsesCycleRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedUnitRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDeadCodeRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.ConsideredUsed,
  Atlas.Text.Lines;

function CleanName(const AText: string): string;
begin
  if StartsStr('&', AText) then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function SamePosition(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Character = B.Character);
end;

function Inside(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  Range: TTextRange;
begin
  for Range in ARanges do
    if ((APosition.Line > Range.StartPos.Line) or ((APosition.Line = Range.StartPos.Line) and
      (APosition.Character >= Range.StartPos.Character))) and ((APosition.Line < Range.EndPos.Line) or
      ((APosition.Line = Range.EndPos.Line) and (APosition.Character <= Range.EndPos.Character))) then
      Exit(True);
  Result := False;
end;

function HasIncludes(const ATree: TSyntaxTree): Boolean;
var
  Token: TPascalToken;
  Name: string;
begin
  for Token in ATree.Tokens do
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Name := TDirectiveNames.LeadingName(TDirectiveNames.Body(Token.Text));
      if SameText(Name, 'I') or SameText(Name, 'INCLUDE') then
        Exit(True);
    end;
  Result := False;
end;

function IsProgramFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dpr') or SameText(ExtractFileExt(AFileName), '.dpk');
end;

function IsTypeKind(AKind: TIndexSymbolKind): Boolean;
begin
  Result := AKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
end;

/// <summary>Name ohne Typparameter: TListe&lt;T&gt;.Add -> TListe.Add.</summary>
function WithoutTypeParams(const AName: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(AName) do
    if AName[Index] = '<' then
      Inc(Depth)
    else if AName[Index] = '>' then
      Dec(Depth)
    else if Depth = 0 then
      Result := Result + AName[Index];
end;

function ProjectKindKey(AKind: TRuleProjectKind): string;
begin
  case AKind of
    TRuleProjectKind.Application:
      Result := 'application';
    TRuleProjectKind.Package:
      Result := 'package';
    TRuleProjectKind.Library_:
      Result := 'library';
  else
    Result := '';
  end;
end;

/// <summary>Bereich des Unit-Namens im Kopf (unit A.B.C;); leer, wenn die Datei keine Unit ist.</summary>
function UnitNameRange(const ATokens: TArray<TPascalToken>; out ARange: TTextRange): Boolean;
var
  Index, Last: Integer;
begin
  Result := False;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    if not SameText(ATokens[Index].Text, 'unit') then
      Exit;
    Last := Index + 1;
    while (Last + 2 <= High(ATokens)) and ATokens[Last + 1].IsSymbol('.') and
      (ATokens[Last + 2].Kind = TPascalTokenKind.Identifier) do
      Inc(Last, 2);
    if (Last > High(ATokens)) or (ATokens[Index + 1].Kind <> TPascalTokenKind.Identifier) then
      Exit;
    ARange := TTextRange.Create(ATokens[Index + 1].StartPos, ATokens[Last].EndPos);
    Exit(True);
  end;
end;

{ TUsesCycleRule }

function TUsesCycleRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UsesCycleRuleId, TRuleSeverity.Warning, 'Zirkuläre Unit-Referenz über uses');
end;

procedure TUsesCycleRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Reason, OwnName, PathText, Details: string;
  WithImplementation, AllInterface: Boolean;
  Reference: TUsesReference;
  Steps: TArray<TRuleUsesStep>;
  Step: TRuleUsesStep;
  Range: TTextRange;
  Previous: string;

  function SectionText(AInInterface: Boolean): string;
  begin
    if AInInterface then
      Result := 'interface'
    else
      Result := 'implementation';
  end;

begin
  if (AContext.Tree = nil) or (AContext.ProjectFiles = nil) or (AContext.FileName = '') or
    IsProgramFile(AContext.FileName) or not UnitNameRange(AContext.Tree.Tokens, Range) or
    not AContext.ProjectFiles.Complete(Reason) then
    Exit;
  WithImplementation := TRuleOptions.Bool(AContext.Options, 'implementation', True);
  OwnName := TUsesClauses.OwnName(AContext.Tree.Tokens);
  for Reference in TUsesClauses.References(AContext.Tree.Tokens) do
  begin
    if Reference.List <> TUsesListKind.UsesList then
      Continue;
    if Assigned(AContext.Cancelled) and AContext.Cancelled() then
      raise ERuleCheckCancelled.Create(UsesCycleRuleId);
    // Erst nur über interface: ein solcher Zyklus ist ein Compilerfehler und geht vor.
    Steps := nil;
    if Reference.InInterface then
      Steps := AContext.ProjectFiles.UsesPath(Reference.Name, AContext.FileName, True);
    AllInterface := Steps <> nil;
    if (Steps = nil) and WithImplementation then
      Steps := AContext.ProjectFiles.UsesPath(Reference.Name, AContext.FileName, False);
    if Steps = nil then
      Continue;
    PathText := OwnName + ' → ' + Reference.Name;
    // Verkettet statt Format: Der Pfeil bleibt so auch unter FPC ein Zeichen.
    Details := OwnName + ' → ' + Reference.Name + ' (' + SectionText(Reference.InInterface) + ')';
    Previous := Reference.Name;
    for Step in Steps do
    begin
      PathText := PathText + ' → ' + Step.UnitName;
      Details := Details + sLineBreak + Previous + ' → ' + Step.UnitName + ' (' +
        SectionText(Step.InInterface) + ')';
      Previous := Step.UnitName;
    end;
    if AllInterface then
      AReport.AddWithSeverity(Reference.Range, 'Zirkuläre Unit-Referenz über interface-uses (wie F2047): ' +
        PathText, TRuleSeverity.Error, [])
    else
      AReport.AddWithDetails(Reference.Range, 'Zirkuläre Unit-Referenz: ' + PathText + ' (über implementation-uses)',
        Details, TRuleConfidence.High, []);
  end;
end;

{ TUnusedDeclarationRule }

function TUnusedDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnusedDeclarationRuleId, TRuleSeverity.Hint,
    'Deklaration im implementation-Teil wird nie verwendet');
end;

procedure TUnusedDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Local: TUnitIndex;
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Considered: TConsideredUsed;
  // Namen (klein) mit einer Deklaration im interface-Teil: deren Rumpf im implementation-Teil ist kein Kandidat.
  InterfaceNames: TDictionary<string, Boolean>;
  // Name (klein) -> Positionen aller Bezeichner dieses Namens.
  Occurrences: TObjectDictionary<string, TList<TTextPosition>>;

  function KindText(const ASymbol: TIndexSymbol): string;
  begin
    case ASymbol.Kind of
      TIndexSymbolKind.Routine:
        Result := 'Routine';
      TIndexSymbolKind.Constant:
        Result := 'Konstante';
      TIndexSymbolKind.Variable:
        Result := 'Globale Variable';
    else
      Result := 'Typ';
    end;
  end;

  function Candidate(const ASymbol: TIndexSymbol): Boolean;
  begin
    Result := (ASymbol.Container = '') and not ASymbol.InInterface and not ASymbol.Unavailable and
      (ASymbol.FileName = '') and ((ASymbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Constant,
      TIndexSymbolKind.Variable]) or IsTypeKind(ASymbol.Kind)) and
      not InterfaceNames.ContainsKey(LowerCase(ASymbol.Name));
  end;

  /// <summary>Bereiche, deren Vorkommen von ASymbol keine Verwendung sind: eigene Rümpfe (Rekursion), bei Typen
  /// die Deklaration und die Rümpfe der eigenen Methoden samt Kopf.</summary>
  function OwnRanges(const ASymbol: TIndexSymbol): TArray<TTextRange>;
  var
    Node: TSyntaxNode;
  begin
    Result := nil;
    if IsTypeKind(ASymbol.Kind) then
      Result := [ASymbol.Range];
    for Node in TRuleDerived.Routines(Cache, AContext) do
      if ((ASymbol.Kind = TIndexSymbolKind.Routine) and SameText(Node.Name, ASymbol.Name)) or
        (IsTypeKind(ASymbol.Kind) and StartsText(ASymbol.Name + '.', WithoutTypeParams(Node.Name))) then
        Result := Result + [TTextRange.Create(Node.StartPos, Node.EndPos)];
  end;

  /// <summary>Positionen der Deklarationen auf Unit-Ebene mit dem Namen (auch forward und Rümpfe).</summary>
  function Declarations(const AName: string): TArray<TTextPosition>;
  var
    Position: Integer;
  begin
    Result := nil;
    for Position in Local.SymbolsNamed(AName) do
      if Local.Symbols[Position].Container = '' then
        Result := Result + [Local.Symbols[Position].SelectionRange.StartPos];
  end;

  function Used(const ASymbol: TIndexSymbol): Boolean;
  var
    Positions: TList<TTextPosition>;
    Position, Skip: TTextPosition;
    Declared: TArray<TTextPosition>;
    Own: TArray<TTextRange>;
    Excluded: Boolean;
  begin
    if not Occurrences.TryGetValue(LowerCase(ASymbol.Name), Positions) then
      Exit(False);
    Declared := Declarations(ASymbol.Name);
    Own := OwnRanges(ASymbol);
    for Position in Positions do
    begin
      Excluded := Inside(Position, Own);
      for Skip in Declared do
        if SamePosition(Skip, Position) then
          Excluded := True;
      if not Excluded then
        Exit(True);
    end;
    Result := False;
  end;

  /// <summary>[Behalten] verwendet BehaltenAttribute.</summary>
  function UsedAsAttribute(const ASymbol: TIndexSymbol): Boolean;
  var
    Short: string;
    Positions: TList<TTextPosition>;
    Position: TTextPosition;
  begin
    Result := False;
    if (ASymbol.Kind <> TIndexSymbolKind.ClassType) or not EndsText('Attribute', ASymbol.Name) or
      (Length(ASymbol.Name) = Length('Attribute')) then
      Exit;
    Short := Copy(ASymbol.Name, 1, Length(ASymbol.Name) - Length('Attribute'));
    if Occurrences.TryGetValue(LowerCase(Short), Positions) then
      for Position in Positions do
        if not Inside(Position, [ASymbol.Range]) then
          Exit(True);
  end;

  function IgnoreFix(const ASymbol: TIndexSymbol): TRuleFix;
  var
    Line: Integer;
    Indent: string;
  begin
    Line := ASymbol.Range.StartPos.Line;
    Indent := '';
    if Line < Length(Lines) then
      Indent := Copy(Lines[Line], 1, Length(Lines[Line]) - Length(TrimLeft(Lines[Line])));
    Result := TRuleFix.Create('Als bewusst vorhanden markieren (lsp-ignore)',
      [TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Indent + '// lsp-ignore: ' +
      UnusedDeclarationRuleId + LineBreak)]);
    Result.Alternative := True;
  end;

var
  Symbol: TIndexSymbol;
  Token: TPascalToken;
  Name, Key: string;
  List: TList<TTextPosition>;
  Seen: TDictionary<string, Boolean>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or HasIncludes(AContext.Tree) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  if LineBreak = '' then
    LineBreak := sLineBreak;
  InterfaceNames := TDictionary<string, Boolean>.Create;
  Occurrences := TObjectDictionary<string, TList<TTextPosition>>.Create([doOwnsValues]);
  Seen := TDictionary<string, Boolean>.Create;
  // Dienst „gilt als verwendet“ (#1102) mit deadCode.keepAttributes und deadCode.keepPatterns.
  Considered := TConsideredUsed.Create(AContext.Index, Local, Tokens, AContext.KeepAttributes, AContext.KeepPatterns);
  try
    for Symbol in Local.Symbols do
      if (Symbol.Container = '') and Symbol.InInterface then
        InterfaceNames.AddOrSetValue(LowerCase(Symbol.Name), True);
    for Token in Tokens do
      if Token.Kind = TPascalTokenKind.Identifier then
      begin
        Name := LowerCase(CleanName(Token.Text));
        if not Occurrences.TryGetValue(Name, List) then
        begin
          List := TList<TTextPosition>.Create;
          Occurrences.Add(Name, List);
        end;
        List.Add(Token.StartPos);
      end;
    for Symbol in Local.Symbols do
    begin
      if not Candidate(Symbol) then
        Continue;
      // Forward-Deklaration und Rumpf sind ein Kandidat; Überladungen einzeln.
      Key := LowerCase(Symbol.Name + '(' + string.Join(',', Symbol.ParamTypes) + ')');
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      if Used(Symbol) or UsedAsAttribute(Symbol) or (Considered.Reason(Symbol) <> TConsideredUsedReason.None) then
        Continue;
      // Komponenten, Ereignisse und Klassen aus der Formulardatei.
      if (AContext.FormText <> '') and ContainsText(AContext.FormText, Symbol.Name) then
        Continue;
      AReport.Add(Symbol.SelectionRange, Format('%s %s wird nirgends verwendet.', [KindText(Symbol), Symbol.Name]),
        TRuleConfidence.High, [IgnoreFix(Symbol)]);
    end;
  finally
    Considered.Free;
    Seen.Free;
    Occurrences.Free;
    InterfaceNames.Free;
  end;
end;

{ TUnusedUnitRule }

function TUnusedUnitRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnusedUnitRuleId, TRuleSeverity.Hint,
    'Unit wird von keiner anderen Unit verwendet');
end;

procedure TUnusedUnitRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Reason, Programs, OwnName: string;
  ProjectKinds: TArray<string>;
  Projects: TArray<TRuleProject>;
  Project: TRuleProject;
  Users: TArray<TRuleUsesStep>;
  User: TRuleUsesStep;
  Local: TUnitIndex;
  Cache: IRuleDerivedCache;
  Names: TDictionary<string, Boolean>;
  Symbol: TIndexSymbol;
  Range: TTextRange;

  /// <summary>Verwendet das Programm AFile außerhalb seiner uses-Liste einen Bezeichner der Unit? Nicht lesbar
  /// zählt als ja.</summary>
  function ProgramUses(const AFile: string): Boolean;
  var
    Text: string;
    Tree: TSyntaxTree;
    Token: TPascalToken;
    Clauses: TArray<TTextRange>;
    Reference: TUsesReference;
  begin
    if not AContext.ProjectFiles.ReadText(AFile, Text) then
      Exit(True);
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      Clauses := nil;
      for Reference in TUsesClauses.References(Tree.Tokens) do
        Clauses := Clauses + [Reference.Range];
      for Token in Tree.Tokens do
        if (Token.Kind = TPascalTokenKind.Identifier) and Names.ContainsKey(LowerCase(CleanName(Token.Text))) and
          not Inside(Token.StartPos, Clauses) then
          Exit(True);
    finally
      Tree.Free;
    end;
    Result := False;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.ProjectFiles = nil) or
    (AContext.FileName = '') or not SameText(ExtractFileExt(AContext.FileName), '.pas') or
    not UnitNameRange(AContext.Tree.Tokens, Range) then
    Exit;
  ProjectKinds := TRuleOptions.Strings(AContext.Options, 'projectKinds', ['application']);
  Projects := AContext.ProjectFiles.ProjectsOf(AContext.FileName, False);
  if Projects = nil then
    Exit;
  for Project in Projects do
    if IndexText(ProjectKindKey(Project.Kind), ProjectKinds) < 0 then
      Exit;
  if not AContext.ProjectFiles.Complete(Reason) or not AContext.ProjectFiles.UsedBy(AContext.FileName, Users) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  // Registrierungen und andere Seiteneffekte beim Start.
  if Local.HasInitialization then
    Exit;
  Programs := '';
  for User in Users do
  begin
    if not IsProgramFile(User.FileName) then
      Exit;
    if Programs <> '' then
      Programs := Programs + ', ';
    Programs := Programs + ExtractFileName(User.FileName);
  end;
  Names := TDictionary<string, Boolean>.Create;
  try
    for Symbol in Local.Symbols do
      if (Symbol.Container = '') and Symbol.InInterface then
        Names.AddOrSetValue(LowerCase(Symbol.Name), True);
    for User in Users do
      if ProgramUses(User.FileName) then
        Exit;
  finally
    Names.Free;
  end;
  OwnName := TUsesClauses.OwnName(AContext.Tree.Tokens);
  if Programs = '' then
    AReport.Add(Range, Format('Unit %s wird von keiner Unit und keinem Programm verwendet.', [OwnName]),
      TRuleConfidence.Medium)
  else
    AReport.Add(Range, Format('Unit %s wird von keiner anderen Unit verwendet; nur %s nennt sie im uses.',
      [OwnName, Programs]), TRuleConfidence.Medium);
end;

procedure RegisterDeadCodeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUsesCycleRule.Create);
  ARegistry.Register(TUnusedDeclarationRule.Create);
  ARegistry.Register(TUnusedUnitRule.Create);
end;

end.
