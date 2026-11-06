unit Atlas.Common.Mcp.DeadCodeTools;

// MCP-Werkzeuge für toten Code und Unit-Abhängigkeiten (#64):
//
// - find_unused_code: die Regeln für ungenutzten Code (unused-private-member,
//   unused-public-member, unused-declaration, unused-unit) für eine Datei oder
//   alle Projektdateien, mit dem Index und den Projekten der Gruppe wie im
//   Editor. Es gelten die Einstellungen aus atlas.json (Schweregrad, off,
//   Optionen, deadCode.keep*). Solange Projekte laden oder der Index läuft,
//   schweigen die projektweiten Regeln; der Bericht sagt das.
// - get_unit_dependencies: direkte uses einer Unit und die Units, die sie
//   verwenden, je mit Abschnitt; auf Wunsch die transitiven Hüllen und die
//   Zyklen durch die Unit mit vollständigem Pfad (wie uses-cycle). Grundlage
//   ist der gemeinsame Uses-Graph (#268) ohne Bibliotheks-Units.
//
// Beide liefern Markdown oder mit format=json die Daten.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Mcp.Contract;

{$SCOPEDENUMS ON}

type
  TMcpUsesDirection = (Uses_, UsedBy, Both);

  TMcpDeadCodeTools = class
  public const
    MaxFindings = 200;
  public
    /// <summary>Die Regeln für ungenutzten Code aus ARules, in der Reihenfolge von ARules.</summary>
    class function DeadCodeRules(const ARules: TArray<IRule>): TArray<IRule>; static;
    /// <summary>find_unused_code: Befunde der Regeln für ungenutzten Code aus AScope.Rules in AFiles. Texte über
    /// AProjectFiles.ReadText, Pfade im Bericht relativ zu AScope.Root.</summary>
    class function FindUnused(const AScope: TMcpRuleScope; const AFiles: TArray<string>; const AIndex: ISymbolIndex;
      const AProjectFiles: IRuleProjectFiles; const ANamespaces: TArray<string>; AJson: Boolean): string; static;
    /// <summary>"uses", "usedBy" oder "both" ('' = both); False bei anderem Text.</summary>
    class function ParseDirection(const AText: string; out ADirection: TMcpUsesDirection): Boolean; static;
    /// <summary>get_unit_dependencies für die Unit AUnit (Name oder absoluter Pfad); EMcpToolError-frei: eine
    /// unbekannte Unit liefert einen Hinweistext.</summary>
    class function UnitDependencies(AGraph: TUsesGraph; const AUnit, ARoot: string; ADirection: TMcpUsesDirection;
      ATransitive, AJson: Boolean): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.Visibility,
  Atlas.Common.Rules.Builtin.PublicMembers,
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDeadCodeToolsText = (NotReadable, NoteUnusedPublicMemberAnd, TheRulesForUnusedCode, FileText,
    AllDependenciesTransitive, ViaImplementationUses, None, UnitIsNotInThe, LineColumnConfidence, FindingsInFiles,
    UsedBy, AllUsersTransitive, InterfaceUsesOnlyCompilerError, MoreFindings, UnusedCode, UsesText, Cycles);

const
  cTexts: array[TDeadCodeToolsText] of TAtlasText = (
    (De: '- %s: nicht lesbar'; En: '- %s: not readable'),
    (De: 'Hinweis: %s; unused-public-member und unused-unit schweigen, bis alle Projekte geladen und indiziert sind.';
     En: 'Note: %s; unused-public-member and unused-unit stay silent until all projects are loaded and indexed.'),
    (De: 'Die Regeln für ungenutzten Code sind nicht verfügbar.'; En: 'The rules for unused code are not available.'),
    (De: 'Datei: '; En: 'File: '),
    (De: 'Alle Abhängigkeiten, transitiv'; En: 'All dependencies, transitive'),
    (De: '- %s (über implementation-uses)'; En: '- %s (via implementation uses)'),
    (De: '- keine'; En: '- none'),
    (De: 'Unit %s steht nicht im Uses-Graphen (nur Units der Projekte, ohne RTL/VCL; Index noch nicht vollständig?).';
     En: 'Unit %s is not in the uses graph (only units of the projects, without RTL/VCL; index not complete yet?).'),
    (De: '- Zeile %d, Spalte %d: %s (%s, Konfidenz %s)'; En: '- Line %d, column %d: %s (%s, confidence %s)'),
    (De: '%d Befunde in %d Dateien (%s).'; En: '%d findings in %d files (%s).'),
    (De: '## Verwendet von (%d)'; En: '## Used by (%d)'),
    (De: 'Alle Nutzer, transitiv'; En: 'All users, transitive'),
    (De: '- %s (nur interface-uses, Compilerfehler wie F2047)';
     En: '- %s (interface uses only, compiler error like F2047)'),
    (De: '… %d weitere Befunde'; En: '… %d more findings'),
    (De: '# Ungenutzter Code'; En: '# Unused code'),
    (De: '## Verwendet (%d)'; En: '## Uses (%d)'),
    (De: '## Zyklen'; En: '## Cycles'));

const
  DeadCodeIds: array[0..3] of string = (UnusedPrivateMemberRuleId, UnusedPublicMemberRuleId,
    UnusedDeclarationRuleId, UnusedUnitRuleId);

// Pfad relativ zu ARoot; beide Trenner gelten, weil Pfade aus dem Index und
// vom Client unter Windows wie unter Linux vorkommen.
function RelativeTo(const ARoot, AFileName: string): string;
var
  Prefix: string;
begin
  Result := AFileName;
  if ARoot = '' then
  begin
    Exit;
  end;
  Prefix := ARoot;
  while (Prefix <> '') and CharInSet(Prefix[Length(Prefix)], ['\', '/']) do
  begin
    Delete(Prefix, Length(Prefix), 1);
  end;
  if (Length(AFileName) > Length(Prefix) + 1) and StartsText(Prefix, AFileName) and
    CharInSet(AFileName[Length(Prefix) + 1], ['\', '/']) then
  begin
    Result := Copy(AFileName, Length(Prefix) + 2, MaxInt);
  end;
end;

function SectionName(ASection: TUsesSection): string;
begin
  if ASection = TUsesSection.Interface_ then
  begin
    Result := 'interface';
  end
  else
  begin
    Result := 'implementation';
  end;
end;

{ TMcpDeadCodeTools }

class function TMcpDeadCodeTools.DeadCodeRules(const ARules: TArray<IRule>): TArray<IRule>;
var
  Rule: IRule;
begin
  Result := nil;
  for Rule in ARules do
  begin
    if IndexText(Rule.Descriptor.Id, DeadCodeIds) >= 0 then
    begin
      Result := Result + [Rule];
    end;
  end;
end;

type
  /// <summary>Sammelt die Befunde von find_unused_code als Markdown-Zeilen und JSON.</summary>
  TUnusedCollector = class
  private
    FScope: TMcpRuleScope;
    FRules: TArray<IRule>;
    FIndex: ISymbolIndex;
    FProjectFiles: IRuleProjectFiles;
    FNamespaces: TArray<string>;
    FLines: TStringList;
    /// <summary>JSON-Bericht; die Befunde stehen unter "findings".</summary>
    FRoot: TJSONObject;
    FCount: Integer;
    FChecked: Integer;
    /// <summary>Alle Projekte geladen und indiziert, beim Start ermittelt; sonst Grund in FReason.</summary>
    FComplete: Boolean;
    FReason: string;
    function ContextOf(const AFileName, AText: string; ATree: TSyntaxTree): TRuleContext;
    procedure AddFinding(const AFileName: string; const AFinding: TRuleFinding; var ACurrent: string);
    procedure AddHeader;
  public
    constructor Create(const AScope: TMcpRuleScope; const AIndex: ISymbolIndex;
      const AProjectFiles: IRuleProjectFiles; const ANamespaces: TArray<string>);
    destructor Destroy; override;
    procedure CheckFile(const AFileName: string);
    function Report(AJson: Boolean): string;
  end;

constructor TUnusedCollector.Create(const AScope: TMcpRuleScope; const AIndex: ISymbolIndex;
  const AProjectFiles: IRuleProjectFiles; const ANamespaces: TArray<string>);
begin
  inherited Create;
  FScope := AScope;
  FRules := TMcpDeadCodeTools.DeadCodeRules(AScope.Rules);
  FIndex := AIndex;
  FProjectFiles := AProjectFiles;
  FNamespaces := ANamespaces;
  FLines := TStringList.Create;
  FRoot := TJSONObject.Create;
  FRoot.AddPair('findings', TJSONArray.Create);
  FComplete := (AProjectFiles = nil) or AProjectFiles.Complete(FReason);
end;

destructor TUnusedCollector.Destroy;
begin
  FRoot.Free;
  FLines.Free;
  inherited;
end;

function TUnusedCollector.ContextOf(const AFileName, AText: string; ATree: TSyntaxTree): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.FileName := AFileName;
  Result.RelativePath := StringReplace(RelativeTo(FScope.Root, AFileName), '\', '/', [rfReplaceAll]);
  Result.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Index := FIndex;
  Result.Namespaces := FNamespaces;
  Result.ProjectFiles := FProjectFiles;
  if SameText(ExtractFileExt(AFileName), '.pas') and not FProjectFiles.ReadText(ChangeFileExt(AFileName, '.dfm'),
    Result.FormText) then
  begin
    FProjectFiles.ReadText(ChangeFileExt(AFileName, '.fmx'), Result.FormText);
  end;
end;

procedure TUnusedCollector.AddFinding(const AFileName: string; const AFinding: TRuleFinding; var ACurrent: string);
var
  mItem: TJSONObject;
begin
  Inc(FCount);
  if FCount > TMcpDeadCodeTools.MaxFindings then
  begin
    Exit;
  end;
  if ACurrent = '' then
  begin
    ACurrent := RelativeTo(FScope.Root, AFileName);
    FLines.Add('');
    FLines.Add('## ' + ACurrent);
  end;
  FLines.Add(cTexts[TDeadCodeToolsText.LineColumnConfidence].Fmt([AFinding.Range.StartPos.Line + 1,
    AFinding.Range.StartPos.Character + 1, AFinding.Message, AFinding.RuleId, ConfidenceText(AFinding.Confidence)]));
  mItem := TJSONObject.Create;
  (FRoot.GetValue('findings') as TJSONArray).AddElement(mItem);
  mItem.AddPair('file', RelativeTo(FScope.Root, AFileName));
  mItem.AddPair('line', TJSONNumber.Create(AFinding.Range.StartPos.Line + 1));
  mItem.AddPair('column', TJSONNumber.Create(AFinding.Range.StartPos.Character + 1));
  mItem.AddPair('rule', AFinding.RuleId);
  mItem.AddPair('message', AFinding.Message);
  mItem.AddPair('confidence', ConfidenceName(AFinding.Confidence));
end;

procedure TUnusedCollector.CheckFile(const AFileName: string);
var
  mText, mCurrent: string;
  mTree: TSyntaxTree;
  mFinding: TRuleFinding;
begin
  if (FProjectFiles = nil) or not FProjectFiles.ReadText(AFileName, mText) then
  begin
    FLines.Add(cTexts[TDeadCodeToolsText.NotReadable].Fmt([RelativeTo(FScope.Root, AFileName)]));
    Exit;
  end;
  Inc(FChecked);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mCurrent := '';
    for mFinding in TRuleEngine.Run(FRules, FScope.Settings, ContextOf(AFileName, mText, mTree)) do
    begin
      AddFinding(AFileName, mFinding, mCurrent);
    end;
  finally
    mTree.Free;
  end;
end;

procedure TUnusedCollector.AddHeader;
begin
  if FCount > TMcpDeadCodeTools.MaxFindings then
  begin
    FLines.Add(cTexts[TDeadCodeToolsText.MoreFindings].Fmt([FCount - TMcpDeadCodeTools.MaxFindings]));
  end;
  if not FComplete then
  begin
    FLines.Insert(0, cTexts[TDeadCodeToolsText.NoteUnusedPublicMemberAnd].Fmt([FReason]));
  end;
  if FRules = nil then
  begin
    FLines.Insert(0, cTexts[TDeadCodeToolsText.TheRulesForUnusedCode].Text);
  end;
  FLines.Insert(0, cTexts[TDeadCodeToolsText.FindingsInFiles].Fmt([FCount, FChecked, string.Join(', ', DeadCodeIds)]));
  FLines.Insert(0, cTexts[TDeadCodeToolsText.UnusedCode].Text);
end;

function TUnusedCollector.Report(AJson: Boolean): string;
begin
  FRoot.AddPair('files', TJSONNumber.Create(FChecked));
  FRoot.AddPair('total', TJSONNumber.Create(FCount));
  if not FComplete then
  begin
    FRoot.AddPair('incomplete', FReason);
  end;
  if AJson then
  begin
    Exit(FRoot.ToJSON);
  end;
  AddHeader;
  Result := TrimRight(FLines.Text);
end;

class function TMcpDeadCodeTools.FindUnused(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
  const AIndex: ISymbolIndex; const AProjectFiles: IRuleProjectFiles; const ANamespaces: TArray<string>;
  AJson: Boolean): string;
var
  mCollector: TUnusedCollector;
  mFileName: string;
begin
  mCollector := TUnusedCollector.Create(AScope, AIndex, AProjectFiles, ANamespaces);
  try
    for mFileName in AFiles do
    begin
      mCollector.CheckFile(mFileName);
    end;
    Result := mCollector.Report(AJson);
  finally
    mCollector.Free;
  end;
end;

class function TMcpDeadCodeTools.ParseDirection(const AText: string; out ADirection: TMcpUsesDirection): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'both') then
  begin
    ADirection := TMcpUsesDirection.Both;
  end
  else if SameText(AText, 'uses') then
  begin
    ADirection := TMcpUsesDirection.Uses_;
  end
  else if SameText(AText, 'usedBy') then
  begin
    ADirection := TMcpUsesDirection.UsedBy;
  end
  else
  begin
    ADirection := TMcpUsesDirection.Both;
    Result := False;
  end;
end;

type
  /// <summary>Bericht von get_unit_dependencies für einen Knoten des Uses-Graphen, als Markdown und JSON.</summary>
  TDependencyReport = class
  private
    FGraph: TUsesGraph;
    FRoot: string;
    FNode: Integer;
    FCurrent: TUsesNode;
    // Zeilen als string statt TStringList: Pfeile und andere Zeichen außerhalb der Codepage bleiben so auf jeder
    // Plattform erhalten.
    FOutput: string;
    FJson: TJSONObject;
    procedure Add(const ALine: string);
    procedure AddNames(const ATitle, AKey: string; const ANodes: TArray<Integer>);
    procedure AddUnit(AList: TJSONArray; const AUnit, ASection: string);
    function CyclePath(const AEdge: TUsesEdge; out AInterfaceOnly: Boolean): TUsesEdges;
    procedure AddCycle(AList: TJSONArray; const APath: TUsesEdges; AInterfaceOnly: Boolean);
  public
    constructor Create(AGraph: TUsesGraph; ANode: Integer; const ARoot: string);
    destructor Destroy; override;
    procedure AddUses(ATransitive: Boolean);
    procedure AddUsedBy(ATransitive: Boolean);
    procedure AddCycles;
    function Text(AJson: Boolean): string;
  end;

constructor TDependencyReport.Create(AGraph: TUsesGraph; ANode: Integer; const ARoot: string);
begin
  inherited Create;
  FGraph := AGraph;
  FNode := ANode;
  FRoot := ARoot;
  FCurrent := AGraph.Node(ANode);
  FJson := TJSONObject.Create;
  FJson.AddPair('unit', FCurrent.UnitName);
  FJson.AddPair('file', RelativeTo(ARoot, FCurrent.FileName));
  Add('# ' + FCurrent.UnitName);
  Add(cTexts[TDeadCodeToolsText.FileText].Text + RelativeTo(ARoot, FCurrent.FileName));
end;

destructor TDependencyReport.Destroy;
begin
  FJson.Free;
  inherited;
end;

procedure TDependencyReport.Add(const ALine: string);
begin
  FOutput := FOutput + ALine + sLineBreak;
end;

procedure TDependencyReport.AddNames(const ATitle, AKey: string; const ANodes: TArray<Integer>);
var
  mNames: TStringList;
  mEntry: Integer;
  mName: string;
  mValues: TJSONArray;
begin
  mNames := TStringList.Create;
  try
    mNames.Sorted := True;
    mNames.Duplicates := dupIgnore;
    for mEntry in ANodes do
    begin
      mNames.Add(FGraph.Node(mEntry).UnitName);
    end;
    mValues := TJSONArray.Create;
    FJson.AddPair(AKey, mValues);
    Add('');
    Add(Format('## %s (%d)', [ATitle, mNames.Count]));
    for mName in mNames do
    begin
      Add('- ' + mName);
      mValues.Add(mName);
    end;
  finally
    mNames.Free;
  end;
end;

procedure TDependencyReport.AddUnit(AList: TJSONArray; const AUnit, ASection: string);
var
  mItem: TJSONObject;
begin
  Add(Format('- %s (%s)', [AUnit, ASection]));
  mItem := TJSONObject.Create;
  AList.AddElement(mItem);
  mItem.AddPair('unit', AUnit);
  mItem.AddPair('section', ASection);
end;

procedure TDependencyReport.AddUses(ATransitive: Boolean);
var
  mList: TJSONArray;
  mEdge: TUsesEdge;
begin
  mList := TJSONArray.Create;
  FJson.AddPair('uses', mList);
  Add('');
  Add(cTexts[TDeadCodeToolsText.UsesText].Fmt([Length(FCurrent.Outgoing)]));
  for mEdge in FCurrent.Outgoing do
  begin
    AddUnit(mList, FGraph.Node(mEdge.Target).UnitName, SectionName(mEdge.Section));
  end;
  if ATransitive then
  begin
    AddNames(cTexts[TDeadCodeToolsText.AllDependenciesTransitive].Text, 'transitiveUses', FGraph.Dependencies(FNode,
      AllUsesSections));
  end;
end;

procedure TDependencyReport.AddUsedBy(ATransitive: Boolean);
var
  mList: TJSONArray;
  mUsers: TStringList;
  mRef: TUsesEdgeRef;
  mEdge: TUsesEdge;
  mText: string;
begin
  mList := TJSONArray.Create;
  FJson.AddPair('usedBy', mList);
  Add('');
  Add(cTexts[TDeadCodeToolsText.UsedBy].Fmt([Length(FCurrent.Incoming)]));
  // Eingehende Kanten stehen in Ladereihenfolge; nach Unit-Namen sortiert ist die Ausgabe stabil.
  mUsers := TStringList.Create;
  try
    for mRef in FCurrent.Incoming do
    begin
      mEdge := FGraph.Node(mRef.Source).Outgoing[mRef.Item];
      mUsers.Add(FGraph.Node(mRef.Source).UnitName + #9 + SectionName(mEdge.Section));
    end;
    mUsers.CaseSensitive := False;
    mUsers.Sort;
    for mText in mUsers do
    begin
      AddUnit(mList, Copy(mText, 1, Pos(#9, mText) - 1), Copy(mText, Pos(#9, mText) + 1, MaxInt));
    end;
  finally
    mUsers.Free;
  end;
  if ATransitive then
  begin
    AddNames(cTexts[TDeadCodeToolsText.AllUsersTransitive].Text, 'transitiveUsedBy', FGraph.Dependents(FNode,
      AllUsesSections));
  end;
end;

function TDependencyReport.CyclePath(const AEdge: TUsesEdge; out AInterfaceOnly: Boolean): TUsesEdges;
begin
  Result := nil;
  AInterfaceOnly := False;
  if AEdge.Section = TUsesSection.Interface_ then
  begin
    Result := FGraph.Path(AEdge.Target, FNode, InterfaceUsesOnly);
    AInterfaceOnly := Result <> nil;
  end;
  if Result = nil then
  begin
    Result := FGraph.Path(AEdge.Target, FNode, AllUsesSections);
  end;
  if Result <> nil then
  begin
    Result := TArray<TUsesEdge>.Create(AEdge) + Result;
  end;
end;

procedure TDependencyReport.AddCycle(AList: TJSONArray; const APath: TUsesEdges; AInterfaceOnly: Boolean);
var
  mItem: TJSONObject;
  mSteps: TJSONArray;
  mBack: TUsesEdge;
begin
  if AInterfaceOnly then
  begin
    Add(cTexts[TDeadCodeToolsText.InterfaceUsesOnlyCompilerError].Fmt([FGraph.Describe(APath)]));
  end
  else
  begin
    Add(cTexts[TDeadCodeToolsText.ViaImplementationUses].Fmt([FGraph.Describe(APath)]));
  end;
  mItem := TJSONObject.Create;
  AList.AddElement(mItem);
  mSteps := TJSONArray.Create;
  mItem.AddPair('path', mSteps);
  mSteps.Add(FCurrent.UnitName);
  for mBack in APath do
  begin
    mSteps.Add(FGraph.Node(mBack.Target).UnitName);
  end;
  mItem.AddPair('interfaceOnly', TJSONBool.Create(AInterfaceOnly));
end;

procedure TDependencyReport.AddCycles;
var
  mList: TJSONArray;
  mSeen: TDictionary<Integer, Boolean>;
  mEdge: TUsesEdge;
  mPath: TUsesEdges;
  mInterfaceOnly: Boolean;
begin
  // Zyklen durch die Unit: je uses-Eintrag der kürzeste Weg zurück, wie die Regel uses-cycle.
  mList := TJSONArray.Create;
  FJson.AddPair('cycles', mList);
  Add('');
  Add(cTexts[TDeadCodeToolsText.Cycles].Text);
  mSeen := TDictionary<Integer, Boolean>.Create;
  try
    for mEdge in FCurrent.Outgoing do
    begin
      if mSeen.ContainsKey(mEdge.Target) then
      begin
        Continue;
      end;
      mSeen.Add(mEdge.Target, True);
      mPath := CyclePath(mEdge, mInterfaceOnly);
      if mPath <> nil then
      begin
        AddCycle(mList, mPath, mInterfaceOnly);
      end;
    end;
  finally
    mSeen.Free;
  end;
  if mList.Count = 0 then
  begin
    Add(cTexts[TDeadCodeToolsText.None].Text);
  end;
end;

function TDependencyReport.Text(AJson: Boolean): string;
begin
  if AJson then
  begin
    Result := FJson.ToJSON;
  end
  else
  begin
    Result := TrimRight(FOutput);
  end;
end;

class function TMcpDeadCodeTools.UnitDependencies(AGraph: TUsesGraph; const AUnit, ARoot: string;
  ADirection: TMcpUsesDirection; ATransitive, AJson: Boolean): string;
var
  mNode: Integer;
  mReport: TDependencyReport;
begin
  mNode := AGraph.IndexOf(AUnit);
  if mNode < 0 then
  begin
    mNode := AGraph.IndexOfFile(AUnit);
  end;
  if (mNode < 0) or not AGraph.Node(mNode).Active then
  begin
    Exit(cTexts[TDeadCodeToolsText.UnitIsNotInThe].Fmt([AUnit]));
  end;
  mReport := TDependencyReport.Create(AGraph, mNode, ARoot);
  try
    if ADirection in [TMcpUsesDirection.Uses_, TMcpUsesDirection.Both] then
    begin
      mReport.AddUses(ATransitive);
    end;
    if ADirection in [TMcpUsesDirection.UsedBy, TMcpUsesDirection.Both] then
    begin
      mReport.AddUsedBy(ATransitive);
    end;
    mReport.AddCycles;
    Result := mReport.Text(AJson);
  finally
    mReport.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.DeadCodeTools', cTexts);

end.
