unit Atlas.Common.Mcp.LastTests.Tests;

// Tests für get_last_tests (#2409): Argumente, Auswahl des Laufs (Projekt, neuester, unter dem Arbeitsordner),
// veraltete Units, Text mit Marken (neu rot, wackelig, Leck, veraltet), Grenze max, JSON, kein Lauf, Texte in beiden
// Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpLastTestsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ArgumentsAndDefaults;
    [Test]
    procedure PicksProjectOrNewest;
    [Test]
    procedure StaleUnitsAfterTheRun;
    [Test]
    procedure TextNamesFailuresWithMarks;
    [Test]
    procedure FiltersAndLimit;
    [Test]
    procedure JsonReport;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Mcp.Server,
  Atlas.Text.TestResults,
  Atlas.Text.TestRunFile,
  Atlas.Common.Mcp.LastTests;

function NewCase(const AMethod: string; AOutcome: TTestOutcome; ADurationMs: Int64): TTestRunFileCase;
begin
  Result := Default(TTestRunFileCase);
  Result.Test.FullName := 'Demo.Tests.TRechner.' + AMethod;
  Result.Test.UnitName := 'Demo.Tests';
  Result.Test.Outcome := AOutcome;
  Result.Test.DurationMs := ADurationMs;
end;

function NewRun(const AProject: string; AHour: Word): TTestRunFile;
begin
  Result := Default(TTestRunFile);
  Result.Project := AProject;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.FinishedAtUtc := EncodeDateTime(2026, 11, 16, AHour, 0, 0, 0);
  Result.FinishedAtLocal := Result.FinishedAtUtc;
  Result.DurationMs := 138000;
end;

function Sample: TTestRunFile;
var
  mUnit: TTestRunUnit;
begin
  Result := NewRun('C:\P\Demo.Tests.dproj', 11);
  mUnit.Name := 'Demo.Tests';
  mUnit.FileName := 'C:\P\Demo.Tests.pas';
  Result.Units := [mUnit];
  Result.Cases := [NewCase('Summe', TTestOutcome.Failed, 40), NewCase('Wackel', TTestOutcome.Failed, 900),
    NewCase('Leck', TTestOutcome.Passed, 5), NewCase('Gruen', TTestOutcome.Passed, 1200),
    NewCase('Aus', TTestOutcome.Skipped, 0)];
  Result.Cases[0].Test.Message := 'Expected 1 but got 2';
  Result.Cases[0].Test.Expected := '1';
  Result.Cases[0].Test.Actual := '2';
  Result.Cases[0].Test.HasValues := True;
  Result.Cases[0].FileName := 'C:\P\Demo.Tests.pas';
  Result.Cases[0].Line := 318;
  Result.Cases[0].Change := TTestRunChange.NewFailure;
  Result.Cases[0].Log := ['Trunk-Hilfsprojekt doppelt'];
  Result.Cases[1].Test.Message := 'Zeitüberschreitung' + sLineBreak + 'Stack';
  Result.Cases[1].FlakyFailed := 3;
  Result.Cases[1].FlakyRuns := 10;
  Result.Cases[2].Test.LeakBytes := 72;
  Result.Cases[3].Change := TTestRunChange.Fixed;
end;

function Arguments(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

function RequestOf(const AJson: string): TMcpLastTestsRequest;
var
  mArguments: TJSONObject;
begin
  mArguments := Arguments(AJson);
  try
    Result := TMcpLastTestsRequest.FromArguments(mArguments);
  finally
    mArguments.Free;
  end;
end;

{ TMcpLastTestsTests }

procedure TMcpLastTestsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpLastTestsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpLastTestsTests.ArgumentsAndDefaults;
var
  mRequest: TMcpLastTestsRequest;
begin
  mRequest := TMcpLastTestsRequest.FromArguments(nil);
  Assert.AreEqual(Ord(TMcpLastTestsFilter.Failed), Ord(mRequest.Only));
  Assert.AreEqual(TMcpLastTestsRequest.cDefaultMax, mRequest.Max);
  Assert.IsFalse(mRequest.AsJson);
  mRequest := RequestOf('{"project":"Demo.Tests","only":"FLAKY","max":3,"format":"json"}');
  Assert.AreEqual('Demo.Tests', mRequest.Project);
  Assert.AreEqual(Ord(TMcpLastTestsFilter.Flaky), Ord(mRequest.Only));
  Assert.AreEqual(3, mRequest.Max);
  Assert.IsTrue(mRequest.AsJson);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"only":"rot"}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"max":0}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"format":"xml"}');
    end, EMcpToolError);
  mRequest := Default(TMcpLastTestsRequest);
end;

procedure TMcpLastTestsTests.PicksProjectOrNewest;
var
  mRuns: TArray<TTestRunFile>;
  mReason: string;
begin
  mRuns := [NewRun('C:\P\Demo.Tests.dproj', 9), NewRun('D:\Fremd\Andere.Tests.dproj', 12),
    NewRun('C:\P\Sub\Zweite.Tests.dproj', 10)];
  // Ohne Projekt der neueste unter dem Arbeitsordner, sonst der neueste überhaupt.
  Assert.AreEqual(2, TMcpLastTests.Pick(mRuns, 'C:\P', '', mReason));
  Assert.AreEqual(1, TMcpLastTests.Pick(mRuns, 'E:\Leer', '', mReason));
  Assert.AreEqual(0, TMcpLastTests.Pick(mRuns, 'C:\P', 'Demo.Tests', mReason));
  Assert.AreEqual(0, TMcpLastTests.Pick(mRuns, 'C:\P', 'demo.tests.dproj', mReason));
  Assert.AreEqual(1, TMcpLastTests.Pick(mRuns, 'C:\P', 'D:\Fremd\Andere.Tests.dproj', mReason));
  Assert.AreEqual(-1, TMcpLastTests.Pick(mRuns, 'C:\P', 'Nichts', mReason));
  Assert.IsTrue(mReason.Contains('Nichts'), mReason);
  Assert.IsTrue(mReason.Contains('Zweite.Tests.dproj'), mReason);
  Assert.AreEqual(-1, TMcpLastTests.Pick(nil, 'C:\P', '', mReason));
  mRuns := nil;
  mReason := '';
end;

procedure TMcpLastTestsTests.StaleUnitsAfterTheRun;
var
  mRun: TTestRunFile;
  mUnit: TTestRunUnit;
  mStale: TArray<string>;
begin
  mRun := NewRun('C:\P\Demo.Tests.dproj', 11);
  mUnit.Name := 'Alt.Tests';
  mUnit.FileName := 'C:\P\Alt.Tests.pas';
  mRun.Units := [mUnit];
  mUnit.Name := 'Neu.Tests';
  mUnit.FileName := 'C:\P\Neu.Tests.pas';
  mRun.Units := mRun.Units + [mUnit];
  mUnit.Name := 'Offen.Tests';
  mUnit.FileName := 'C:\P\Offen.Tests.pas';
  mRun.Units := mRun.Units + [mUnit];
  mStale := TMcpLastTests.StaleUnits(mRun,
    function(const AFileName: string): TDateTime
    begin
      if AFileName.Contains('Neu') then
      begin
        Result := EncodeDateTime(2026, 11, 16, 11, 5, 0, 0);
      end
      else
      begin
        Result := EncodeDateTime(2026, 11, 16, 10, 0, 0, 0);
      end;
    end, ['c:\p\offen.tests.pas']);
  Assert.AreEqual(2, Integer(Length(mStale)));
  Assert.AreEqual('Neu.Tests', mStale[0]);
  Assert.AreEqual('Offen.Tests', mStale[1]);
  mStale := nil;
end;

procedure TMcpLastTestsTests.TextNamesFailuresWithMarks;
var
  mText: string;
begin
  mText := TMcpLastTests.Report(Sample, ['Demo.Tests'], TMcpLastTestsRequest.FromArguments(nil));
  Assert.IsTrue(mText.StartsWith('Demo.Tests.dproj · Win64 Debug · 16.11.2026 11:00 · 5 Tests, 2 rot, ' +
    '1 übersprungen'), mText);
  Assert.IsTrue(mText.Contains('1 wackelig, 1 mit Leck, 5 veraltet'), mText);
  Assert.IsTrue(mText.Contains('Wieder grün: TRechner.Gruen'), mText);
  Assert.IsTrue(mText.Contains('✖ TRechner.Summe'), mText);
  Assert.IsTrue(mText.Contains('neu rot'), mText);
  Assert.IsTrue(mText.Contains('Demo.Tests.pas:318'), mText);
  Assert.IsTrue(mText.Contains('Erwartet 1, erhalten 2'), mText);
  Assert.IsTrue(mText.Contains('Protokoll: Trunk-Hilfsprojekt doppelt'), mText);
  Assert.IsTrue(mText.Contains('wackelig (3 von 10 rot)'), mText);
  // Nur die erste Zeile der Meldung.
  Assert.IsTrue(mText.Contains('Zeitüberschreitung'), mText);
  Assert.IsFalse(mText.Contains('Stack'), mText);
  // Bestandene Tests fehlen bei only=failed.
  Assert.IsFalse(mText.Contains('TRechner.Leck'), mText);
end;

procedure TMcpLastTestsTests.FiltersAndLimit;
var
  mText: string;
begin
  mText := TMcpLastTests.Report(Sample, nil, RequestOf('{"only":"leaks"}'));
  Assert.IsTrue(mText.Contains('TRechner.Leck'), mText);
  Assert.IsTrue(mText.Contains('Leck 72 Byte'), mText);
  Assert.IsFalse(mText.Contains('TRechner.Summe  '), mText);
  mText := TMcpLastTests.Report(Sample, nil, RequestOf('{"only":"slow","max":2}'));
  Assert.IsTrue(mText.Contains('Langsamste Tests:'), mText);
  Assert.IsTrue(mText.IndexOf('TRechner.Gruen') < mText.IndexOf('TRechner.Wackel'), mText);
  Assert.IsTrue(mText.Contains('… 2 weitere (max)'), mText);
  mText := TMcpLastTests.Report(Sample, nil, RequestOf('{"only":"stale"}'));
  Assert.IsTrue(mText.Contains('Keine Tests für only=stale.'), mText);
  mText := TMcpLastTests.Report(Sample, nil, RequestOf('{"only":"all"}'));
  Assert.IsTrue(mText.Contains('– TRechner.Aus'), mText);
  Assert.IsTrue(mText.Contains('✔ TRechner.Gruen'), mText);
end;

procedure TMcpLastTestsTests.JsonReport;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mFirst: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TMcpLastTests.Report(Sample, ['Demo.Tests'],
    RequestOf('{"format":"json","max":1}')));
  try
    Assert.IsTrue(mValue is TJSONObject);
    mRoot := TJSONObject(mValue);
    Assert.AreEqual('C:\P\Demo.Tests.dproj', mRoot.GetValue<string>('project'));
    Assert.AreEqual(5, mRoot.GetValue<Integer>('total'));
    Assert.AreEqual(2, mRoot.GetValue<Integer>('failed'));
    Assert.AreEqual(1, mRoot.GetValue<Integer>('flaky'));
    Assert.AreEqual(1, mRoot.GetValue<Integer>('omitted'));
    Assert.AreEqual('failed', mRoot.GetValue<string>('only'));
    mFirst := mRoot.GetValue<TJSONArray>('tests').Items[0] as TJSONObject;
    Assert.AreEqual('Demo.Tests.TRechner.Summe', mFirst.GetValue<string>('name'));
    Assert.AreEqual('newFailure', mFirst.GetValue<string>('change'));
    Assert.AreEqual(318, mFirst.GetValue<Integer>('line'));
    Assert.AreEqual('2', mFirst.GetValue<string>('actual'));
    Assert.IsTrue(mFirst.GetValue<Boolean>('stale'));
  finally
    mValue.Free;
  end;
end;

procedure TMcpLastTestsTests.EnglishTexts;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  mText := TMcpLastTests.Report(Sample, nil, TMcpLastTestsRequest.FromArguments(nil));
  Assert.IsTrue(mText.Contains('5 tests, 2 red, 1 skipped'), mText);
  Assert.IsTrue(mText.Contains('newly red'), mText);
  Assert.IsTrue(mText.Contains('Expected 1, actual 2'), mText);
  Assert.IsTrue(TMcpLastTests.NoRuns('X').Contains('run_tests'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpLastTestsTests);

end.
