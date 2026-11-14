unit Atlas.Common.Configuration.Internals.Forbidden.Tests;

// Tests für die Sperre von Zugangsdaten und absoluten Pfaden in atlas.json
// (#486, #415): Schlüssel mit Zugangsdaten auf jeder Ebene, Adressen mit
// Zugangsdaten, absolute Pfade nur in den Pfad-Einstellungen, erlaubte
// relative Pfade und Glob-Muster, Warnungen mit Position, Text ohne Fund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForbiddenEntriesTests = class
  public
    [Test]
    procedure KeepsTextWithoutFindings;
    [Test]
    procedure RemovesCredentialKeysOnEveryLevel;
    [Test]
    procedure RemovesUrlWithCredentials;
    [Test]
    procedure RemovesAbsolutePathsInPathSettings;
    [Test]
    procedure KeepsRelativePathsAndGlobs;
    [Test]
    procedure AbsolutePathOutsidePathSettingStays;
    [Test]
    procedure ReportsWarningWithPosition;
    [Test]
    procedure InvalidOrEmptyTextStays;
    [Test]
    procedure KnowsPathSettings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.Forbidden;

function Stripped(const AText: string): string; overload;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TForbiddenEntries.Strip(AText, mIssues);
end;

function Stripped(const AText: string; out ACount: Integer): string; overload;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TForbiddenEntries.Strip(AText, mIssues);
  ACount := Length(mIssues);
end;

{ TForbiddenEntriesTests }

procedure TForbiddenEntriesTests.KeepsTextWithoutFindings;
const
  cText = '{'#10'  "project": "Haupt.dproj",'#10'  "lsp": { "trace": "off" }'#10'}';
var
  mCount: Integer;
begin
  Assert.AreEqual(cText, Stripped(cText, mCount), 'Unverändert bis aufs Zeichen');
  Assert.AreEqual(0, mCount);
end;

procedure TForbiddenEntriesTests.RemovesCredentialKeysOnEveryLevel;
var
  mCount: Integer;
begin
  Assert.AreEqual('{"a": 1}', Stripped('{"a": 1, "token": "geheim"}', mCount));
  Assert.AreEqual(1, mCount);
  Assert.AreEqual('{"ci": {"url": "https://ci.example"}}',
    Stripped('{"ci": {"url": "https://ci.example", "password": "x"}}', mCount));
  Assert.AreEqual(1, mCount);
end;

procedure TForbiddenEntriesTests.RemovesUrlWithCredentials;
var
  mCount: Integer;
begin
  Assert.AreEqual('{"n": 2}', Stripped('{"url": "https://user:pw@ci.example/job", "n": 2}', mCount));
  Assert.AreEqual(1, mCount);
  Assert.AreEqual('{"ci": {"hooks": ["https://ci.example/a"]}}',
    Stripped('{"ci": {"hooks": ["https://ci.example/a", "https://x:y@ci.example/b"]}}', mCount));
  Assert.AreEqual(1, mCount);
end;

procedure TForbiddenEntriesTests.RemovesAbsolutePathsInPathSettings;
var
  mCount: Integer;
begin
  Assert.AreEqual('{}', Stripped('{"project": "C:\\Projekte\\Haupt.dproj"}', mCount));
  Assert.AreEqual(1, mCount);
  Assert.AreEqual('{"exclude": ["Generated\\**"]}', Stripped('{"exclude": ["Generated\\**", "D:\\Fremd\\**"]}',
    mCount));
  Assert.AreEqual(1, mCount);
  Assert.AreEqual('{"testUnits": {}}', Stripped('{"testUnits": {"folder": "\\\\server\\share\\Tests"}}', mCount));
  Assert.AreEqual(1, mCount);
  Assert.AreEqual('{"overrides": [{"files": []}]}', Stripped('{"overrides": [{"files": ["C:\\a.pas"]}]}', mCount));
  Assert.AreEqual(1, mCount);
end;

procedure TForbiddenEntriesTests.KeepsRelativePathsAndGlobs;
const
  cText = '{"project": "..\\Haupt.dproj", "exclude": ["/Generated/**"], "index": {"exclude": ["Lib\\*"]}}';
var
  mCount: Integer;
begin
  Assert.AreEqual(cText, Stripped(cText, mCount));
  Assert.AreEqual(0, mCount);
end;

procedure TForbiddenEntriesTests.AbsolutePathOutsidePathSettingStays;
const
  cText = '{"compiler": {"dcc": "C:\\Delphi\\bin\\dcc64.exe"}}';
begin
  Assert.AreEqual(cText, Stripped(cText));
end;

procedure TForbiddenEntriesTests.ReportsWarningWithPosition;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  TForbiddenEntries.Strip('{'#10'  "n": 1,'#10'  "token": "x"'#10'}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError, 'Warnung, kein Fehler');
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Character);
  Assert.AreEqual(9, mIssues[0].Range.EndPos.Character, 'Ganzer Schlüssel samt Anführungszeichen');
  Assert.IsTrue(Pos('"token"', mIssues[0].Message) > 0, mIssues[0].Message);
  mIssues := nil;
end;

procedure TForbiddenEntriesTests.InvalidOrEmptyTextStays;
var
  mCount: Integer;
begin
  Assert.AreEqual('', Stripped('', mCount));
  Assert.AreEqual(0, mCount);
  Assert.AreEqual('{"token": ', Stripped('{"token": ', mCount), 'Syntaxfehler meldet der Parser');
  Assert.AreEqual(0, mCount);
  Assert.AreEqual('["C:\\x"]', Stripped('["C:\\x"]', mCount), 'Nur Objekte werden gefiltert');
  Assert.AreEqual(0, mCount);
end;

procedure TForbiddenEntriesTests.KnowsPathSettings;
begin
  Assert.IsTrue(TForbiddenEntries.IsPathSetting('project'));
  Assert.IsTrue(TForbiddenEntries.IsPathSetting('testUnits.folder'));
  Assert.IsTrue(TForbiddenEntries.IsPathSetting('testUnits.project'));
  Assert.IsTrue(TForbiddenEntries.IsPathSetting('exclude[]'));
  Assert.IsTrue(TForbiddenEntries.IsPathSetting('index.exclude[]'));
  Assert.IsTrue(TForbiddenEntries.IsPathSetting('overrides[].files[]'));
  Assert.IsFalse(TForbiddenEntries.IsPathSetting('exclude'), 'Nur die Einträge, nicht die Liste');
  Assert.IsFalse(TForbiddenEntries.IsPathSetting('compiler.dcc'));
end;

initialization
  TDUnitX.RegisterTestFixture(TForbiddenEntriesTests);

end.
