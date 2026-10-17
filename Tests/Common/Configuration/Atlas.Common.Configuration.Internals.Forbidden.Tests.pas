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
  Issues: TArray<TConfigurationIssue>;
begin
  Result := TForbiddenEntries.Strip(AText, Issues);
end;

function Stripped(const AText: string; out ACount: Integer): string; overload;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Result := TForbiddenEntries.Strip(AText, Issues);
  ACount := Length(Issues);
end;

{ TForbiddenEntriesTests }

procedure TForbiddenEntriesTests.KeepsTextWithoutFindings;
const
  Text = '{'#10'  "project": "Haupt.dproj",'#10'  "lsp": { "trace": "off" }'#10'}';
var
  Count: Integer;
begin
  Assert.AreEqual(Text, Stripped(Text, Count), 'Unverändert bis aufs Zeichen');
  Assert.AreEqual(0, Count);
end;

procedure TForbiddenEntriesTests.RemovesCredentialKeysOnEveryLevel;
var
  Count: Integer;
begin
  Assert.AreEqual('{"a": 1}', Stripped('{"a": 1, "token": "geheim"}', Count));
  Assert.AreEqual(1, Count);
  Assert.AreEqual('{"ci": {"url": "https://ci.example"}}',
    Stripped('{"ci": {"url": "https://ci.example", "password": "x"}}', Count));
  Assert.AreEqual(1, Count);
end;

procedure TForbiddenEntriesTests.RemovesUrlWithCredentials;
var
  Count: Integer;
begin
  Assert.AreEqual('{"n": 2}', Stripped('{"url": "https://user:pw@ci.example/job", "n": 2}', Count));
  Assert.AreEqual(1, Count);
  Assert.AreEqual('{"ci": {"hooks": ["https://ci.example/a"]}}',
    Stripped('{"ci": {"hooks": ["https://ci.example/a", "https://x:y@ci.example/b"]}}', Count));
  Assert.AreEqual(1, Count);
end;

procedure TForbiddenEntriesTests.RemovesAbsolutePathsInPathSettings;
var
  Count: Integer;
begin
  Assert.AreEqual('{}', Stripped('{"project": "C:\\Projekte\\Haupt.dproj"}', Count));
  Assert.AreEqual(1, Count);
  Assert.AreEqual('{"exclude": ["Generated\\**"]}', Stripped('{"exclude": ["Generated\\**", "D:\\Fremd\\**"]}',
    Count));
  Assert.AreEqual(1, Count);
  Assert.AreEqual('{"testUnits": {}}', Stripped('{"testUnits": {"folder": "\\\\server\\share\\Tests"}}', Count));
  Assert.AreEqual(1, Count);
  Assert.AreEqual('{"overrides": [{"files": []}]}', Stripped('{"overrides": [{"files": ["C:\\a.pas"]}]}', Count));
  Assert.AreEqual(1, Count);
end;

procedure TForbiddenEntriesTests.KeepsRelativePathsAndGlobs;
const
  Text = '{"project": "..\\Haupt.dproj", "exclude": ["/Generated/**"], "index": {"exclude": ["Lib\\*"]}}';
var
  Count: Integer;
begin
  Assert.AreEqual(Text, Stripped(Text, Count));
  Assert.AreEqual(0, Count);
end;

procedure TForbiddenEntriesTests.AbsolutePathOutsidePathSettingStays;
const
  Text = '{"compiler": {"dcc": "C:\\Delphi\\bin\\dcc64.exe"}}';
begin
  Assert.AreEqual(Text, Stripped(Text));
end;

procedure TForbiddenEntriesTests.ReportsWarningWithPosition;
var
  Issues: TArray<TConfigurationIssue>;
begin
  TForbiddenEntries.Strip('{'#10'  "n": 1,'#10'  "token": "x"'#10'}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsFalse(Issues[0].IsError, 'Warnung, kein Fehler');
  Assert.AreEqual(2, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(2, Issues[0].Range.StartPos.Character);
  Assert.AreEqual(9, Issues[0].Range.EndPos.Character, 'Ganzer Schlüssel samt Anführungszeichen');
  Assert.IsTrue(Pos('"token"', Issues[0].Message) > 0, Issues[0].Message);
  Issues := nil;
end;

procedure TForbiddenEntriesTests.InvalidOrEmptyTextStays;
var
  Count: Integer;
begin
  Assert.AreEqual('', Stripped('', Count));
  Assert.AreEqual(0, Count);
  Assert.AreEqual('{"token": ', Stripped('{"token": ', Count), 'Syntaxfehler meldet der Parser');
  Assert.AreEqual(0, Count);
  Assert.AreEqual('["C:\\x"]', Stripped('["C:\\x"]', Count), 'Nur Objekte werden gefiltert');
  Assert.AreEqual(0, Count);
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
