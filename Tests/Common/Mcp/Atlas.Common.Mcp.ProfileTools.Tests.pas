unit Atlas.Common.Mcp.ProfileTools.Tests;

// Tests für get_profile (#2057): Argumente, Auswahl des Laufs, Text mit heißester Zeile, Filter nach Unit,
// Vergleich und JSON, Texte in beiden Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpProfileToolsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ArgumentsAndDefaults;
    [Test]
    procedure SelectsRunByNumberOrName;
    [Test]
    procedure TextNamesTopMethodsWithHotLine;
    [Test]
    procedure FiltersByUnit;
    [Test]
    procedure JsonWithComparison;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Mcp.Server,
  Atlas.Text.Profile,
  Atlas.Common.Mcp.ProfileTools;

function Frame(const AUnit, ARoutine: string; ALine: Integer): TAtlasProfileFrame;
begin
  Result := Default(TAtlasProfileFrame);
  Result.Routine := AUnit + '.' + ARoutine;
  Result.UnitName := AUnit;
  Result.FileName := 'C:\Src\' + AUnit + '.pas';
  Result.Line := ALine;
  Result.IsLibrary := TAtlasLibraryUnits.IsLibrary(AUnit);
end;

function MakeRun(const AName: string; AMerge: Integer): TMcpProfileRun;
var
  mBuilder: TAtlasProfileBuilder;
  mIndex: Integer;
begin
  Result := Default(TMcpProfileRun);
  Result.Name := AName;
  Result.Profile.ProgramName := 'C:\Bin\AtlasMonitor.exe';
  Result.Profile.StartedAt := EncodeDateTime(2026, 11, 11, 10, 52, 0, 0);
  Result.Profile.DurationMs := 12400;
  Result.Profile.IntervalMs := 10;
  mBuilder := TAtlasProfileBuilder.Create;
  try
    for mIndex := 1 to AMerge do
    begin
      mBuilder.AddSample([Frame('Tracker.MyIssues', 'TQuery.Merge', 431), Frame('Main', 'Run', 5)]);
    end;
    for mIndex := 1 to 2 do
    begin
      mBuilder.AddSample([Frame('Tracker.Parse', 'TParse.Issue', 77), Frame('Main', 'Run', 6)]);
    end;
    mBuilder.FillProfile(Result.Profile);
  finally
    mBuilder.Free;
  end;
end;

function Runs: TArray<TMcpProfileRun>;
begin
  Result := TArray<TMcpProfileRun>.Create(MakeRun('profile-20261111-105200.json', 6),
    MakeRun('profile-20261110-090000.json', 2));
end;

function Arguments(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

function RequestOf(const AJson: string): TMcpProfileRequest;
var
  mArguments: TJSONObject;
begin
  mArguments := Arguments(AJson);
  try
    Result := TMcpProfileRequest.FromArguments(mArguments);
  finally
    mArguments.Free;
  end;
end;

procedure TMcpProfileToolsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpProfileToolsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpProfileToolsTests.ArgumentsAndDefaults;
var
  mRequest: TMcpProfileRequest;
begin
  mRequest := TMcpProfileRequest.FromArguments(nil);
  Assert.AreEqual(10, mRequest.Top);
  Assert.IsTrue(mRequest.OwnCodeOnly);
  Assert.IsFalse(mRequest.AsJson);
  mRequest := RequestOf('{"top":3,"unit":"Tracker","run":"2","compareWith":"1","format":"json","ownCode":false}');
  Assert.AreEqual(3, mRequest.Top);
  Assert.AreEqual('Tracker', mRequest.UnitFilter);
  Assert.AreEqual('2', mRequest.Run);
  Assert.AreEqual('1', mRequest.CompareWith);
  Assert.IsTrue(mRequest.AsJson);
  Assert.IsFalse(mRequest.OwnCodeOnly);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"top":0}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"format":"xml"}');
    end, EMcpToolError);
  mRequest := Default(TMcpProfileRequest);
end;

procedure TMcpProfileToolsTests.SelectsRunByNumberOrName;
begin
  Assert.AreEqual(0, TMcpProfileTools.SelectRun(Runs, ''));
  Assert.AreEqual(1, TMcpProfileTools.SelectRun(Runs, '2'));
  Assert.AreEqual(1, TMcpProfileTools.SelectRun(Runs, 'profile-20261110-090000'));
  Assert.AreEqual(0, TMcpProfileTools.SelectRun(Runs, 'PROFILE-20261111-105200.json'));
  Assert.WillRaise(
    procedure
    begin
      TMcpProfileTools.SelectRun(Runs, '3');
    end, EMcpToolError);
end;

procedure TMcpProfileToolsTests.TextNamesTopMethodsWithHotLine;
var
  mText: string;
begin
  mText := TMcpProfileTools.Report(Runs, RequestOf('{"top":2}'));
  Assert.IsTrue(mText.StartsWith('Lauf profile-20261111-105200.json · AtlasMonitor.exe · 11.11.2026 10:52 · '),
    mText);
  Assert.IsTrue(mText.Contains('1. Tracker.MyIssues.TQuery.Merge  75.0 % eigen, 75.0 % gesamt'), mText);
  Assert.IsTrue(mText.Contains('   C:\Src\Tracker.MyIssues.pas, heißeste Zeile 431'), mText);
  Assert.IsTrue(mText.Contains('2. Tracker.Parse.TParse.Issue  25.0 % eigen'), mText);
  Assert.IsFalse(mText.Contains('Main.Run'), 'nur top 2');
  Assert.IsTrue(mText.Contains('Läufe (neueste zuerst): profile-20261111-105200.json, profile-20261110-090000.json'),
    mText);
end;

procedure TMcpProfileToolsTests.FiltersByUnit;
var
  mText: string;
begin
  mText := TMcpProfileTools.Report(Runs, RequestOf('{"unit":"parse"}'));
  Assert.IsTrue(mText.Contains('1. Tracker.Parse.TParse.Issue'), mText);
  Assert.IsFalse(mText.Contains('Merge'), mText);
  mText := TMcpProfileTools.Report(Runs, RequestOf('{"unit":"Nirgends"}'));
  Assert.IsTrue(mText.Contains('Keine Methode passt zu unit „Nirgends“.'), mText);
end;

procedure TMcpProfileToolsTests.JsonWithComparison;
var
  mValue: TJSONValue;
  mMethod, mBefore: TJSONValue;
  mText: string;
begin
  mText := TMcpProfileTools.Report(Runs, RequestOf('{"compareWith":"2","format":"json","top":1}'));
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    Assert.IsNotNull(mValue, mText);
    Assert.AreEqual('profile-20261111-105200.json', mValue.GetValue<string>('run.name'));
    Assert.AreEqual(8, mValue.GetValue<Integer>('run.samples'));
    // Arrays über eigene Variablen: Pfade mit [0] kennt die JSON-Schicht unter FPC nicht.
    mMethod := mValue.GetValue<TJSONArray>('methods').Items[0];
    Assert.AreEqual('Tracker.MyIssues.TQuery.Merge', mMethod.GetValue<string>('routine'));
    Assert.AreEqual(431, mMethod.GetValue<Integer>('hotLine'));
    Assert.AreEqual(75.0, mMethod.GetValue<Double>('selfPercent'), 0.001);
    Assert.AreEqual('profile-20261110-090000.json', mValue.GetValue<string>('compare.run.name'));
    mBefore := mValue.GetValue<TJSONArray>('compare.methods').Items[0];
    Assert.AreEqual(50.0, mBefore.GetValue<Double>('selfBefore'), 0.001);
    Assert.AreEqual(2, mValue.GetValue<TJSONArray>('runs').Count);
  finally
    mValue.Free;
  end;
  mText := TMcpProfileTools.Report(Runs, RequestOf('{"compareWith":"2"}'));
  Assert.IsTrue(mText.Contains('Vergleich mit Lauf profile-20261110-090000.json'), mText);
  // Ohne den Pfeil: Die FPC-Aufbereitung schreibt Zeichen außerhalb von cp1252 um.
  Assert.IsTrue(mText.Contains('Tracker.MyIssues.TQuery.Merge  50.0 % '), mText);
  Assert.IsTrue(mText.Contains(' 75.0 % (+25.0)'), mText);
end;

procedure TMcpProfileToolsTests.EnglishTexts;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  mText := TMcpProfileTools.Report(Runs, RequestOf('{"top":1}'));
  Assert.IsTrue(mText.Contains('75.0 % self, 75.0 % total'), mText);
  Assert.IsTrue(mText.Contains('hottest line 431'), mText);
  Assert.IsTrue(TMcpProfileTools.NoRuns('X').Contains('Run with profile'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpProfileToolsTests);

end.
