unit Atlas.Common.Configuration.Internals.Reader.Tests;

// Tests für den Leser von atlas.json und die Abschnittstabellen: Objekte mit
// Wahrheitswerten, festen Werten und eigenen Gliedern, unbekannte Schlüssel
// mit Position, Zahlenbereiche, Aufzählung erlaubter Werte, Schlüssel eines
// Unterobjekts; jeder Schlüssel der obersten Ebene gehört genau einem
// Abschnitt, der liest und schichtet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConfigurationReaderTests = class
  public
    [Test]
    procedure ReadsFlags;
    [Test]
    procedure StoresChoiceAsWrittenInValues;
    [Test]
    procedure ReportsInvalidChoice;
    [Test]
    procedure ReportsUnknownKeyWithPosition;
    [Test]
    procedure ReportsNonObject;
    [Test]
    procedure ChecksIntegerRange;
    [Test]
    procedure JoinsChoicesWithConjunction;
    [Test]
    procedure ListsMemberKeysOfObject;
  end;

  [TestFixture]
  TConfigurationSectionsTests = class
  public
    [Test]
    procedure SectionKeysAreUnique;
    [Test]
    procedure EverySectionReadsAndTakes;
    [Test]
    procedure FileSectionWinsOverEditor;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Configuration.Internals.Reader,
  Atlas.Common.Configuration.Internals.GeneralOptions,
  Atlas.Common.Configuration.Internals.RuleOptions,
  Atlas.Common.Configuration.Internals.McpOptions,
  Atlas.Common.Configuration.Internals.EditorOptions,
  Atlas.Common.Configuration.Internals.RefactoringOptions,
  Atlas.Common.Configuration.Internals.WorkflowOptions,
  Atlas.Common.Configuration.Internals.AnalysisOptions,
  Atlas.Common.Configuration.Internals.ProjectOptions,
  Atlas.Common.Configuration.Internals.SuggestionOptions;

/// <summary>Liest das Objekt unter "x" in AText mit einem Wahrheitswert "on" und einer Auswahl "mode"
/// (ask, always); liefert die Meldungen.</summary>
function ReadSample(const AText: string; out AFlag: Boolean; out AMode: string): TArray<TConfigurationIssue>;
var
  mReader: TConfigurationReader;
  mRoot: TJsonNode;
  mSettings: TServerSettings;
begin
  AFlag := False;
  AMode := 'ask';
  mSettings := TServerSettings.Default;
  mReader := TConfigurationReader.Create(AText);
  mRoot := TJsonTree.Parse(AText);
  try
    mReader.ReadObject(mRoot[0], 'x', [TFlagOption.Create('on', AFlag)],
      [TChoiceOption.Create('mode', ['ask', 'always'], AMode)], [], mSettings);
    Result := mReader.Issues;
  finally
    mRoot.Free;
    mReader.Free;
  end;
end;

function AllSections: TArray<TConfigurationSection>;
begin
  Result := GeneralSections + RuleSections + McpSections + EditorSections + RefactoringSections + WorkflowSections +
    AnalysisSections + ProjectSections + SuggestionSections;
end;

{ TConfigurationReaderTests }

procedure TConfigurationReaderTests.ReadsFlags;
var
  mFlag: Boolean;
  mMode: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mIssues := ReadSample('{"x": {"on": true}}', mFlag, mMode);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsTrue(mFlag);
  mIssues := ReadSample('{"x": {"on": "ja"}}', mFlag, mMode);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mFlag, 'ungültig bleibt der bisherige Wert');
end;

procedure TConfigurationReaderTests.StoresChoiceAsWrittenInValues;
var
  mFlag: Boolean;
  mMode: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mIssues := ReadSample('{"x": {"mode": "ALWAYS"}}', mFlag, mMode);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('always', mMode);
end;

procedure TConfigurationReaderTests.ReportsInvalidChoice;
var
  mFlag: Boolean;
  mMode: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mIssues := ReadSample('{"x": {"mode": "never"}}', mFlag, mMode);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"x.mode" muss "ask" oder "always" sein', mIssues[0].Message);
  Assert.IsTrue(mIssues[0].IsError);
  Assert.AreEqual('ask', mMode);
end;

procedure TConfigurationReaderTests.ReportsUnknownKeyWithPosition;
var
  mFlag: Boolean;
  mMode: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mIssues := ReadSample('{"x": {"on": true, "y": 1}}', mFlag, mMode);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('Unbekannte Einstellung "x.y"', mIssues[0].Message);
  Assert.IsFalse(mIssues[0].IsError, 'unbekannte Schlüssel sind Warnungen');
  Assert.AreEqual(19, mIssues[0].Range.StartPos.Character);
  Assert.AreEqual(22, mIssues[0].Range.EndPos.Character);
  Assert.IsTrue(mFlag);
end;

procedure TConfigurationReaderTests.ReportsNonObject;
var
  mFlag: Boolean;
  mMode: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mIssues := ReadSample('{"x": [1]}', mFlag, mMode);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"x" muss ein Objekt sein', mIssues[0].Message);
end;

procedure TConfigurationReaderTests.ChecksIntegerRange;
var
  mReader: TConfigurationReader;
  mRoot: TJsonNode;
  mValue: Integer;
begin
  mReader := TConfigurationReader.Create('[3, 9, "4"]');
  mRoot := TJsonTree.Parse(mReader.Text);
  try
    mValue := 0;
    Assert.IsTrue(mReader.ExpectInteger(mRoot[0], 1, 5, 'zu groß', mValue));
    Assert.AreEqual(3, mValue);
    Assert.IsFalse(mReader.ExpectInteger(mRoot[1], 1, 5, 'zu groß', mValue));
    Assert.IsFalse(mReader.ExpectInteger(mRoot[2], 1, 5, 'zu groß', mValue), 'Text zählt nicht als Zahl');
    Assert.AreEqual(3, mValue);
    Assert.AreEqual(2, Integer(Length(mReader.Issues)));
  finally
    mRoot.Free;
    mReader.Free;
  end;
end;

procedure TConfigurationReaderTests.JoinsChoicesWithConjunction;
begin
  Assert.AreEqual('"a", "b" und "c"', ChoiceText(['a', 'b', 'c'], 'und'));
  Assert.AreEqual('"a" oder "b"', ChoiceText(['a', 'b'], 'oder'));
  Assert.AreEqual('"a"', ChoiceText(['a'], 'oder'));
end;

procedure TConfigurationReaderTests.ListsMemberKeysOfObject;
begin
  Assert.AreEqual('a|b', string.Join('|', ObjectMemberKeys('{"mcp": {"a": 1, "b": 2}, "c": 3}', 'mcp')));
  Assert.AreEqual(0, Integer(Length(ObjectMemberKeys('{"mcp": [1]}', 'mcp'))));
  Assert.AreEqual(0, Integer(Length(ObjectMemberKeys('{"mcp": ', 'mcp'))), 'ungültiger Text');
end;

{ TConfigurationSectionsTests }

procedure TConfigurationSectionsTests.SectionKeysAreUnique;
var
  mSections: TArray<TConfigurationSection>;
  mIndex, mOther: Integer;
begin
  mSections := AllSections;
  Assert.IsTrue(Length(mSections) > 50);
  for mIndex := 0 to High(mSections) do
  begin
    for mOther := mIndex + 1 to High(mSections) do
    begin
      Assert.AreNotEqual(mSections[mIndex].Section, mSections[mOther].Section);
    end;
  end;
end;

procedure TConfigurationSectionsTests.EverySectionReadsAndTakes;
var
  mSection: TConfigurationSection;
begin
  for mSection in AllSections do
  begin
    if mSection.Section = '$schema' then
    begin
      Assert.IsFalse(Assigned(mSection.Read));
      Continue;
    end;
    Assert.IsTrue(Assigned(mSection.Read), mSection.Section + ' liest');
    Assert.IsTrue(Assigned(mSection.Take), mSection.Section + ' schichtet');
  end;
end;

procedure TConfigurationSectionsTests.FileSectionWinsOverEditor;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TConfigurationParser.ParseLayered('{"format": {"indentSize": 4}, "tests": {"affectedDepth": 3}}',
    '{"format": {"indentSize": 2}}', mIssues);
  Assert.AreEqual(2, mSettings.Formatting.IndentSize, 'atlas.json gilt vor dem Editor');
  Assert.AreEqual(3, mSettings.Tests.AffectedDepth, 'was die Datei nicht setzt, bleibt aus dem Editor');
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

end.
