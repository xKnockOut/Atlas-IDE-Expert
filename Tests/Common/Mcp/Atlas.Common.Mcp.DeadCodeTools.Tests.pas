unit Atlas.Common.Mcp.DeadCodeTools.Tests;

// Tests der MCP-Werkzeuge find_unused_code und get_unit_dependencies (#64):
// Bericht als Markdown und JSON, Hinweis bei laufendem Index, abgeschaltete
// Regeln, Richtungen, transitive Hüllen, Zyklen mit Pfad und unbekannte Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpDeadCodeToolsTests = class
  public
    [Test]
    procedure FindUnusedReportsAllRules;
    [Test]
    procedure FindUnusedAsJson;
    [Test]
    procedure FindUnusedWhileIndexing;
    [Test]
    procedure FindUnusedHonoursSettings;
    [Test]
    procedure UnitDependenciesWithCycle;
    [Test]
    procedure UnitDependenciesDirectionsAndJson;
    [Test]
    procedure UnknownUnitAndDirections;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Mcp.DeadCodeTools;

const
  Root = 'C:\P';
  AppFile = 'C:\P\App.dpr';
  MainFile = 'C:\P\Haupt.pas';
  OrphanFile = 'C:\P\Waise.pas';

type
  TFixture = record
    Texts: TDictionary<string, string>;
    Index: ISymbolIndex;
    Files: IRuleProjectFiles;
    Sources: TArray<string>;
  end;

function MainText: string;
begin
  Result :=
    'unit Haupt;'#10'interface'#10'uses'#10'  Waise;'#10'type'#10 +
    '  TDienst = class'#10'  private'#10'    procedure Vergessen;'#10'  public'#10'    procedure Lauf;'#10'  end;'#10 +
    'procedure Start;'#10'implementation'#10 +
    'procedure Hilfe;'#10'begin'#10'end;'#10 +
    'procedure TDienst.Vergessen;'#10'begin'#10'end;'#10 +
    'procedure TDienst.Lauf;'#10'begin'#10'end;'#10 +
    'procedure Start;'#10'begin'#10'  TDienst.Create.Lauf;'#10'end;'#10'end.';
end;

/// <summary>App nutzt Haupt und Waise; Waise nutzt Haupt im implementation-Teil (Zyklus).</summary>
function Fixture(AIncomplete: Boolean): TFixture;
var
  Texts: TDictionary<string, string>;
  Pair: TPair<string, string>;
  Incomplete: Boolean;
  Project: TRuleProject;
begin
  Incomplete := AIncomplete;
  Texts := TDictionary<string, string>.Create;
  Texts.Add(UpperCase(AppFile), 'program App;'#10'uses'#10'  Haupt, Waise;'#10'begin'#10'  Start;'#10'end.');
  Texts.Add(UpperCase(MainFile), MainText);
  Texts.Add(UpperCase(OrphanFile), 'unit Waise;'#10'interface'#10'implementation'#10'uses'#10'  Haupt;'#10'end.');
  Result.Texts := Texts;
  Result.Index := TSymbolIndex.Create;
  for Pair in Texts do
    if Pair.Key = UpperCase(AppFile) then
      Result.Index.AddUnit(TIndexExtractor.ExtractText(Pair.Value, AppFile, nil, nil, True))
    else if Pair.Key = UpperCase(MainFile) then
      Result.Index.AddUnit(TIndexExtractor.ExtractText(Pair.Value, MainFile, nil, nil, True))
    else
      Result.Index.AddUnit(TIndexExtractor.ExtractText(Pair.Value, OrphanFile, nil, nil, True));
  Result.Sources := [AppFile, MainFile, OrphanFile];
  Project := Default(TRuleProject);
  Project.FileName := 'C:\P\App.dproj';
  Project.Kind := TRuleProjectKind.Application;
  Project.Sources := Result.Sources;
  Result.Files := TRuleProjectFiles.Create([Project], Result.Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Texts.TryGetValue(UpperCase(AFileName), AText);
    end,
    function(out AReason: string): Boolean
    begin
      Result := not Incomplete;
      if Incomplete then
        AReason := 'Index wird aufgebaut';
    end);
end;

procedure Release(var AFixture: TFixture);
begin
  AFixture.Files := nil;
  AFixture.Index := nil;
  AFixture.Texts.Free;
  AFixture.Sources := nil;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedReportsAllRules;
var
  Data: TFixture;
  Text: string;
begin
  Data := Fixture(False);
  try
    Text := TMcpDeadCodeTools.FindUnused(BuiltinRules, TServerSettings.Default, Root, [MainFile, OrphanFile],
      Data.Index, Data.Files, nil, False);
    Assert.AreEqual(
      '# Ungenutzter Code'#13#10 +
      '2 Befunde in 2 Dateien (unused-private-member, unused-public-member, unused-declaration, unused-unit).'#13#10 +
      #13#10 +
      '## Haupt.pas'#13#10 +
      '- Zeile 8, Spalte 15: Private Methode Vergessen wird nie verwendet (wie H2219). (unused-private-member, ' +
      'Konfidenz hoch)'#13#10 +
      '- Zeile 14, Spalte 11: Routine Hilfe wird nirgends verwendet. (unused-declaration, Konfidenz hoch)',
      StringReplace(Text, sLineBreak, #13#10, [rfReplaceAll]));
  finally
    Release(Data);
  end;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedAsJson;
var
  Data: TFixture;
  Json: TJSONValue;
  Items: TJSONArray;
begin
  Data := Fixture(False);
  try
    Json := TJSONObject.ParseJSONValue(TMcpDeadCodeTools.FindUnused(BuiltinRules, TServerSettings.Default, Root,
      Data.Sources, Data.Index, Data.Files, nil, True));
    try
      Assert.AreEqual(3, (Json as TJSONObject).GetValue<Integer>('files'));
      Assert.AreEqual(2, (Json as TJSONObject).GetValue<Integer>('total'));
      Items := (Json as TJSONObject).GetValue<TJSONArray>('findings');
      Assert.AreEqual('unused-private-member', Items.Items[0].GetValue<string>('rule'));
      Assert.AreEqual('Haupt.pas', Items.Items[0].GetValue<string>('file'));
      Assert.AreEqual(8, Items.Items[0].GetValue<Integer>('line'));
      Assert.AreEqual('high', Items.Items[1].GetValue<string>('confidence'));
    finally
      Json.Free;
    end;
  finally
    Release(Data);
  end;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedWhileIndexing;
var
  Data: TFixture;
  Text: string;
begin
  Data := Fixture(True);
  try
    Text := TMcpDeadCodeTools.FindUnused(BuiltinRules, TServerSettings.Default, Root, [MainFile], Data.Index,
      Data.Files, nil, False);
    Assert.IsTrue(Pos('Hinweis: Index wird aufgebaut; unused-public-member und unused-unit schweigen', Text) > 0, Text);
    // Regeln innerhalb der Unit melden trotzdem.
    Assert.IsTrue(Pos('Routine Hilfe wird nirgends verwendet.', Text) > 0, Text);
  finally
    Release(Data);
  end;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedHonoursSettings;
var
  Data: TFixture;
  Issues: TArray<TConfigurationIssue>;
  Text: string;
begin
  Data := Fixture(False);
  try
    Text := TMcpDeadCodeTools.FindUnused(BuiltinRules, TConfigurationParser.Parse(
      '{"rules": {"unused-private-member": "off"}, "deadCode": {"keepPatterns": ["Hilfe"]}}', Issues), Root,
      [MainFile], Data.Index, Data.Files, nil, False);
    Assert.IsTrue(Pos('0 Befunde in 1 Dateien', Text) > 0, Text);
    Issues := nil;
  finally
    Release(Data);
  end;
end;

/// <summary>Uses-Graph über den Index der Fixture.</summary>
function GraphOf(const AData: TFixture): TUsesGraph;
begin
  Result := TUsesGraph.Create(AData.Index.Units, TUsesGraphOptions.Default);
end;

procedure TMcpDeadCodeToolsTests.UnitDependenciesWithCycle;
var
  Data: TFixture;
  Graph: TUsesGraph;
begin
  Data := Fixture(False);
  Graph := GraphOf(Data);
  try
    Assert.AreEqual(
      '# Waise'#13#10 +
      'Datei: Waise.pas'#13#10 +
      #13#10 +
      '## Verwendet (1)'#13#10 +
      '- Haupt (implementation)'#13#10 +
      #13#10 +
      '## Verwendet von (2)'#13#10 +
      '- App (implementation)'#13#10 +
      '- Haupt (interface)'#13#10 +
      #13#10 +
      '## Zyklen'#13#10 +
      '- Waise → Haupt → Waise (über implementation-uses)',
      StringReplace(TMcpDeadCodeTools.UnitDependencies(Graph, 'Waise', Root, TMcpUsesDirection.Both, False, False),
      sLineBreak, #13#10, [rfReplaceAll]));
  finally
    Graph.Free;
    Release(Data);
  end;
end;

procedure TMcpDeadCodeToolsTests.UnitDependenciesDirectionsAndJson;
var
  Data: TFixture;
  Graph: TUsesGraph;
  Text: string;
  Json: TJSONValue;
begin
  Data := Fixture(False);
  Graph := GraphOf(Data);
  try
    Text := TMcpDeadCodeTools.UnitDependencies(Graph, 'Haupt', Root, TMcpUsesDirection.UsedBy, True, False);
    Assert.IsTrue(Pos('## Verwendet von (2)', Text) > 0, Text);
    Assert.IsFalse(Pos('## Verwendet (', Text) > 0, Text);
    Assert.IsTrue(Pos('## Alle Nutzer, transitiv (2)', Text) > 0, Text);
    // Pfad statt Name, als JSON.
    Json := TJSONObject.ParseJSONValue(TMcpDeadCodeTools.UnitDependencies(Graph, MainFile, Root,
      TMcpUsesDirection.Uses_, True, True));
    try
      Assert.AreEqual('Haupt', (Json as TJSONObject).GetValue<string>('unit'));
      Assert.AreEqual('Waise', (Json as TJSONObject).GetValue<TJSONArray>('uses').Items[0].GetValue<string>('unit'));
      Assert.AreEqual('interface', (Json as TJSONObject).GetValue<TJSONArray>('uses').Items[0].GetValue<string>(
        'section'));
      Assert.AreEqual(1, (Json as TJSONObject).GetValue<TJSONArray>('transitiveUses').Count);
      Assert.AreEqual(3, (Json as TJSONObject).GetValue<TJSONArray>('cycles').Items[0].GetValue<TJSONArray>(
        'path').Count);
      Assert.IsFalse((Json as TJSONObject).GetValue<TJSONArray>('cycles').Items[0].GetValue<Boolean>(
        'interfaceOnly'));
    finally
      Json.Free;
    end;
  finally
    Graph.Free;
    Release(Data);
  end;
end;

procedure TMcpDeadCodeToolsTests.UnknownUnitAndDirections;
var
  Data: TFixture;
  Graph: TUsesGraph;
  Direction: TMcpUsesDirection;
begin
  Data := Fixture(False);
  Graph := GraphOf(Data);
  try
    Assert.IsTrue(Pos('Unit Vcl.Forms steht nicht im Uses-Graphen', TMcpDeadCodeTools.UnitDependencies(Graph,
      'Vcl.Forms', Root, TMcpUsesDirection.Both, False, False)) > 0);
    Assert.IsTrue(TMcpDeadCodeTools.ParseDirection('', Direction));
    Assert.AreEqual<TMcpUsesDirection>(TMcpUsesDirection.Both, Direction);
    Assert.IsTrue(TMcpDeadCodeTools.ParseDirection('usedBy', Direction));
    Assert.AreEqual<TMcpUsesDirection>(TMcpUsesDirection.UsedBy, Direction);
    Assert.IsTrue(TMcpDeadCodeTools.ParseDirection('uses', Direction));
    Assert.AreEqual<TMcpUsesDirection>(TMcpUsesDirection.Uses_, Direction);
    Assert.IsFalse(TMcpDeadCodeTools.ParseDirection('rauf', Direction));
  finally
    Graph.Free;
    Release(Data);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpDeadCodeToolsTests);

end.
