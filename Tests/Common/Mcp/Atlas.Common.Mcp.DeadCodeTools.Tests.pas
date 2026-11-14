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
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.DeadCodeTools;

const
  cRoot = 'C:\P';
  cAppFile = 'C:\P\App.dpr';
  cMainFile = 'C:\P\Haupt.pas';
  cOrphanFile = 'C:\P\Waise.pas';

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
  mTexts: TDictionary<string, string>;
  mPair: TPair<string, string>;
  mIncomplete: Boolean;
  mProject: TRuleProject;
begin
  mIncomplete := AIncomplete;
  mTexts := TDictionary<string, string>.Create;
  mTexts.Add(UpperCase(cAppFile), 'program App;'#10'uses'#10'  Haupt, Waise;'#10'begin'#10'  Start;'#10'end.');
  mTexts.Add(UpperCase(cMainFile), MainText);
  mTexts.Add(UpperCase(cOrphanFile), 'unit Waise;'#10'interface'#10'implementation'#10'uses'#10'  Haupt;'#10'end.');
  Result.Texts := mTexts;
  Result.Index := TSymbolIndex.Create;
  for mPair in mTexts do
  begin
    if mPair.Key = UpperCase(cAppFile) then
    begin
      Result.Index.AddUnit(TIndexExtractor.ExtractText(mPair.Value, cAppFile, nil, nil, True));
    end
    else if mPair.Key = UpperCase(cMainFile) then
    begin
      Result.Index.AddUnit(TIndexExtractor.ExtractText(mPair.Value, cMainFile, nil, nil, True));
    end
    else
    begin
      Result.Index.AddUnit(TIndexExtractor.ExtractText(mPair.Value, cOrphanFile, nil, nil, True));
    end;
  end;
  Result.Sources := [cAppFile, cMainFile, cOrphanFile];
  mProject := Default(TRuleProject);
  mProject.FileName := 'C:\P\App.dproj';
  mProject.Kind := TRuleProjectKind.Application;
  mProject.Sources := Result.Sources;
  Result.Files := TRuleProjectFiles.Create([mProject], Result.Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mTexts.TryGetValue(UpperCase(AFileName), AText);
    end,
    function(out AReason: string): Boolean
    begin
      Result := not mIncomplete;
      if mIncomplete then
      begin
        AReason := 'Index wird aufgebaut';
      end;
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
  mData: TFixture;
  mText: string;
begin
  mData := Fixture(False);
  try
    mText := TMcpDeadCodeTools.FindUnused(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, cRoot),
      [cMainFile, cOrphanFile], mData.Index, mData.Files, nil, False);
    Assert.AreEqual(
      '# Ungenutzter Code'#13#10 +
      '2 Befunde in 2 Dateien (unused-private-member, unused-public-member, unused-declaration, unused-unit).'#13#10 +
      #13#10 +
      '## Haupt.pas'#13#10 +
      '- Zeile 8, Spalte 15: Private Methode Vergessen wird nie verwendet (wie H2219). (unused-private-member, ' +
      'Konfidenz hoch)'#13#10 +
      '- Zeile 14, Spalte 11: Routine Hilfe wird nirgends verwendet. (unused-declaration, Konfidenz hoch)',
      StringReplace(mText, sLineBreak, #13#10, [rfReplaceAll]));
  finally
    Release(mData);
  end;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedAsJson;
var
  mData: TFixture;
  mJson: TJSONValue;
  mItems: TJSONArray;
begin
  mData := Fixture(False);
  try
    mJson := TJSONObject.ParseJSONValue(TMcpDeadCodeTools.FindUnused(TMcpRuleScope.Create(BuiltinRules,
      TServerSettings.Default, cRoot), mData.Sources, mData.Index, mData.Files, nil, True));
    try
      Assert.AreEqual(3, (mJson as TJSONObject).GetValue<Integer>('files'));
      Assert.AreEqual(2, (mJson as TJSONObject).GetValue<Integer>('total'));
      mItems := (mJson as TJSONObject).GetValue<TJSONArray>('findings');
      Assert.AreEqual('unused-private-member', mItems.Items[0].GetValue<string>('rule'));
      Assert.AreEqual('Haupt.pas', mItems.Items[0].GetValue<string>('file'));
      Assert.AreEqual(8, mItems.Items[0].GetValue<Integer>('line'));
      Assert.AreEqual('high', mItems.Items[1].GetValue<string>('confidence'));
    finally
      mJson.Free;
    end;
  finally
    Release(mData);
  end;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedWhileIndexing;
var
  mData: TFixture;
  mText: string;
begin
  mData := Fixture(True);
  try
    mText := TMcpDeadCodeTools.FindUnused(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, cRoot),
      [cMainFile],
      mData.Index, mData.Files, nil, False);
    Assert.IsTrue(Pos('Hinweis: Index wird aufgebaut; unused-public-member und unused-unit schweigen', mText) > 0, mText);
    // Regeln innerhalb der Unit melden trotzdem.
    Assert.IsTrue(Pos('Routine Hilfe wird nirgends verwendet.', mText) > 0, mText);
  finally
    Release(mData);
  end;
end;

procedure TMcpDeadCodeToolsTests.FindUnusedHonoursSettings;
var
  mData: TFixture;
  mIssues: TArray<TConfigurationIssue>;
  mText: string;
begin
  mData := Fixture(False);
  try
    mText := TMcpDeadCodeTools.FindUnused(TMcpRuleScope.Create(BuiltinRules, TConfigurationParser.Parse(
      '{"rules": {"unused-private-member": "off"}, "deadCode": {"keepPatterns": ["Hilfe"]}}', mIssues), cRoot),
      [cMainFile], mData.Index, mData.Files, nil, False);
    Assert.IsTrue(Pos('0 Befunde in 1 Dateien', mText) > 0, mText);
    mIssues := nil;
  finally
    Release(mData);
  end;
end;

/// <summary>Uses-Graph über den Index der Fixture.</summary>
function GraphOf(const AData: TFixture): TUsesGraph;
begin
  Result := TUsesGraph.Create(AData.Index.Units, TUsesGraphOptions.Default);
end;

procedure TMcpDeadCodeToolsTests.UnitDependenciesWithCycle;
var
  mData: TFixture;
  mGraph: TUsesGraph;
begin
  mData := Fixture(False);
  mGraph := GraphOf(mData);
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
      StringReplace(TMcpDeadCodeTools.UnitDependencies(mGraph, 'Waise', cRoot, TMcpUsesDirection.Both, False, False),
      sLineBreak, #13#10, [rfReplaceAll]));
  finally
    mGraph.Free;
    Release(mData);
  end;
end;

procedure TMcpDeadCodeToolsTests.UnitDependenciesDirectionsAndJson;
var
  mData: TFixture;
  mGraph: TUsesGraph;
  mText: string;
  mJson: TJSONValue;
begin
  mData := Fixture(False);
  mGraph := GraphOf(mData);
  try
    mText := TMcpDeadCodeTools.UnitDependencies(mGraph, 'Haupt', cRoot, TMcpUsesDirection.UsedBy, True, False);
    Assert.IsTrue(Pos('## Verwendet von (2)', mText) > 0, mText);
    Assert.IsFalse(Pos('## Verwendet (', mText) > 0, mText);
    Assert.IsTrue(Pos('## Alle Nutzer, transitiv (2)', mText) > 0, mText);
    // Pfad statt Name, als JSON.
    mJson := TJSONObject.ParseJSONValue(TMcpDeadCodeTools.UnitDependencies(mGraph, cMainFile, cRoot,
      TMcpUsesDirection.Uses_, True, True));
    try
      Assert.AreEqual('Haupt', (mJson as TJSONObject).GetValue<string>('unit'));
      Assert.AreEqual('Waise', (mJson as TJSONObject).GetValue<TJSONArray>('uses').Items[0].GetValue<string>('unit'));
      Assert.AreEqual('interface', (mJson as TJSONObject).GetValue<TJSONArray>('uses').Items[0].GetValue<string>(
        'section'));
      Assert.AreEqual(1, (mJson as TJSONObject).GetValue<TJSONArray>('transitiveUses').Count);
      Assert.AreEqual(3, (mJson as TJSONObject).GetValue<TJSONArray>('cycles').Items[0].GetValue<TJSONArray>(
        'path').Count);
      Assert.IsFalse((mJson as TJSONObject).GetValue<TJSONArray>('cycles').Items[0].GetValue<Boolean>(
        'interfaceOnly'));
    finally
      mJson.Free;
    end;
  finally
    mGraph.Free;
    Release(mData);
  end;
end;

procedure TMcpDeadCodeToolsTests.UnknownUnitAndDirections;
var
  mData: TFixture;
  mGraph: TUsesGraph;
  mDirection: TMcpUsesDirection;
begin
  mData := Fixture(False);
  mGraph := GraphOf(mData);
  try
    Assert.IsTrue(Pos('Unit Vcl.Forms steht nicht im Uses-Graphen', TMcpDeadCodeTools.UnitDependencies(mGraph,
      'Vcl.Forms', cRoot, TMcpUsesDirection.Both, False, False)) > 0);
    Assert.IsTrue(TMcpDeadCodeTools.ParseDirection('', mDirection));
    Assert.AreEqual<TMcpUsesDirection>(TMcpUsesDirection.Both, mDirection);
    Assert.IsTrue(TMcpDeadCodeTools.ParseDirection('usedBy', mDirection));
    Assert.AreEqual<TMcpUsesDirection>(TMcpUsesDirection.UsedBy, mDirection);
    Assert.IsTrue(TMcpDeadCodeTools.ParseDirection('uses', mDirection));
    Assert.AreEqual<TMcpUsesDirection>(TMcpUsesDirection.Uses_, mDirection);
    Assert.IsFalse(TMcpDeadCodeTools.ParseDirection('rauf', mDirection));
  finally
    mGraph.Free;
    Release(mData);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpDeadCodeToolsTests);

end.
