unit Atlas.Common.Rules.Builtin.SavedQueries.Tests;

// Gespeicherte Abfragen mit failIfAny als Regeln query:<name> (#1351): Befund je
// Treffer der geprüften Datei mit Schweregrad und Meldung aus atlas.json,
// Unterdrückung, Baseline, query.enabled aus und Fehler der Abfrage in
// atlas.json mit Spalte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSavedQueryRuleTests = class
  public
    [Test]
    procedure ReportsHitsOfCheckedFileOnly;
    [Test]
    procedure NeedsFailIfAnyEnabledAndService;
    [Test]
    procedure SuppressionAndBaselineHide;
    [Test]
    procedure RuleSettingTurnsOff;
    [Test]
    procedure ConfigurationIssuesPointAtColumn;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Builtin.SavedQueries,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Service,
  Atlas.Common.Query.Language,
  Atlas.Common.Query.Engine.Tests;

const
  cFile = 'C:\P\Data.Kunden.pas';
  cSettings = '{"queries": [{"name": "rechnen", "query": "methods where name = Rechne", "failIfAny": true, ' +
    '"severity": "error", "message": "{name} mit {params} Parametern"}, ' +
    '{"name": "nur-liste", "query": "classes where methods > 0"}]}';

function Services: ICodeQueries;
begin
  Result := TCodeQueryService.Create(
    function(out ASource: TQuerySource): Boolean
    begin
      ASource := QueryTestSource;
      Result := True;
    end);
end;

function TextOf(const AFileName: string): string;
begin
  if not QueryTestSource.ReadText(AFileName, Result) then
    Result := '';
end;

function Check(const ASettings: TServerSettings; const AText: string; const AQueries: ICodeQueries;
  const AFileName: string): TArray<TRuleFinding>;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ExtractFileName(AFileName);
    mContext.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
    mContext.FileName := AFileName;
    mContext.Text := AText;
    mContext.Tree := mTree;
    mContext.Queries := AQueries;
    Result := TRuleEngine.Run(nil, ASettings, mContext);
  finally
    mTree.Free;
  end;
end;

function SettingsOf(const AJson: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

function QueryFindings(const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  mFinding: TRuleFinding;
begin
  Result := nil;
  for mFinding in AFindings do
    if mFinding.RuleId.StartsWith(TSavedQueryRule.cPrefix) then
      Result := Result + [mFinding];
end;

{ TSavedQueryRuleTests }

procedure TSavedQueryRuleTests.ReportsHitsOfCheckedFileOnly;
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
  mFinding: TRuleFinding;
begin
  mText := TextOf(cFile);
  mFindings := QueryFindings(Check(SettingsOf(cSettings), mText, Services, cFile));
  // Zwei Überladungen von TKunde.Rechne (ein und zwei Parameter).
  Assert.AreEqual(2, Integer(Length(mFindings)));
  for mFinding in mFindings do
  begin
    Assert.AreEqual('query:rechnen', mFinding.RuleId);
    Assert.IsTrue(mFinding.Severity = TRuleSeverity.Error);
    Assert.AreEqual('Rechne', Copy(mText.Split([#10])[mFinding.Range.StartPos.Line],
      mFinding.Range.StartPos.Character + 1, 6));
  end;
  Assert.IsTrue(mFindings[0].Message.StartsWith('Rechne mit '), mFindings[0].Message);
  Assert.IsTrue(mFindings[0].Message.EndsWith(' Parametern'), mFindings[0].Message);
  // Andere Datei: keine Treffer dort.
  Assert.AreEqual(0, Integer(Length(QueryFindings(Check(SettingsOf(cSettings), TextOf('C:\P\Main.pas'), Services,
    'C:\P\Main.pas')))));
end;

procedure TSavedQueryRuleTests.NeedsFailIfAnyEnabledAndService;
var
  mSettings: TServerSettings;
begin
  mSettings := SettingsOf(cSettings);
  Assert.AreEqual(1, Integer(Length(TSavedQueryRule.RulesOf(mSettings))));
  Assert.AreEqual(0, Integer(Length(QueryFindings(Check(mSettings, TextOf(cFile), nil, cFile)))));
  mSettings.QueryEnabled := False;
  Assert.AreEqual(0, Integer(Length(TSavedQueryRule.RulesOf(mSettings))));
  Assert.AreEqual(0, Integer(Length(QueryFindings(Check(mSettings, TextOf(cFile), Services, cFile)))));
end;

procedure TSavedQueryRuleTests.SuppressionAndBaselineHide;
var
  mText, mSuppressed: string;
  mFindings: TArray<TRuleFinding>;
  mSource: TBaselineSource;
  mBaseline: IRuleBaseline;
  mLines: TArray<string>;
begin
  mText := TextOf(cFile);
  mFindings := QueryFindings(Check(SettingsOf(cSettings), mText, Services, cFile));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  // Unterdrückung am Ende der Zeile des ersten Treffers.
  mLines := mText.Split([#10]);
  mLines[mFindings[0].Range.StartPos.Line] := mLines[mFindings[0].Range.StartPos.Line] + ' // lsp-ignore: query:rechnen';
  mSuppressed := string.Join(#10, mLines);
  Assert.AreEqual(1, Integer(Length(QueryFindings(Check(SettingsOf(cSettings), mSuppressed, Services, cFile)))));
  // Baseline aus den Befunden blendet beide aus.
  mSource.Path := 'Data.Kunden.pas';
  mSource.Text := mText;
  mSource.Findings := mFindings;
  mBaseline := TRuleBaseline.FromJson(TRuleBaseline.Build([mSource]));
  Assert.AreEqual(0, Integer(Length(mBaseline.Filter('Data.Kunden.pas', mText, mFindings))));
end;

procedure TSavedQueryRuleTests.RuleSettingTurnsOff;
var
  mSettings: TServerSettings;
begin
  mSettings := SettingsOf('{"rules": {"query:rechnen": "off"}, ' + Copy(cSettings, 2, MaxInt));
  Assert.AreEqual(0, Integer(Length(QueryFindings(Check(mSettings, TextOf(cFile), Services, cFile)))));
  mSettings := SettingsOf('{"rules": {"query:rechnen": "hint"}, ' + Copy(cSettings, 2, MaxInt));
  Assert.IsTrue(QueryFindings(Check(mSettings, TextOf(cFile), Services, cFile))[0].Severity = TRuleSeverity.Hint);
end;

procedure TSavedQueryRuleTests.ConfigurationIssuesPointAtColumn;
const
  cJson = '{"queries": [{"name": "a", "query": "classes where name = X"}, {"name": "b", "query": ' +
    '"  classes where methds > 3"}]}';
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := SettingsOf(cJson);
  mIssues := TQueryParser.ConfigurationIssues(mSettings.Queries);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsTrue(mIssues[0].Message.StartsWith('Abfrage "b", Spalte 15: '), mIssues[0].Message);
  // Stelle in atlas.json: das "m" von methds.
  Assert.AreEqual(Integer(Pos('methds', cJson) - 1), mIssues[0].Range.StartPos.Character);
  Assert.AreEqual(0, mIssues[0].Range.StartPos.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TSavedQueryRuleTests);

end.
