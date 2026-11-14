unit Atlas.Core.Problems.InlineHints.Tests;

// Tests für den Fehlertext am Zeilenende (#509): Auswahl je Zeile, Modus,
// Kürzen, Zähler, Sprung zum nächsten Befund, Tipp-Pause und der gemeinsame
// Platz hinter dem Zeilenende.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasInlineDiagnosticsTests = class
  public
    [Test]
    procedure ModeNamesRoundTrip;
    [Test]
    procedure PicksWorstProblemOfLineAndCountsOthers;
    [Test]
    procedure ErrorsModeShowsNoWarnings;
    [Test]
    procedure CaptionTakesFirstLineAndShortens;
    [Test]
    procedure CaptionOfTestFailureAtAssertIsShort;
    [Test]
    procedure CountsMatchTheList;
    [Test]
    procedure NextWalksThroughFileAndWraps;
    [Test]
    procedure PauseWaitsOneSecond;
    [Test]
    procedure LineTailPlacesPaintersSideBySide;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.LineTail;

function Problem(ALine, ACharacter: Integer; ASeverity: TAtlasProblemSeverity; const AMessage: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := ACharacter;
  Result.EndLine := ALine;
  Result.EndCharacter := ACharacter + 1;
  Result.Severity := ASeverity;
  Result.Message := AMessage;
  Result.Source := 'Atlas';
end;

procedure TAtlasInlineDiagnosticsTests.ModeNamesRoundTrip;
var
  mMode: TAtlasInlineDiagnosticsMode;
begin
  for mMode := Low(TAtlasInlineDiagnosticsMode) to High(TAtlasInlineDiagnosticsMode) do
  begin
    Assert.AreEqual<TAtlasInlineDiagnosticsMode>(mMode,
      TAtlasInlineDiagnostics.ModeOf(TAtlasInlineDiagnostics.ModeName(mMode)));
  end;
  Assert.AreEqual<TAtlasInlineDiagnosticsMode>(TAtlasInlineDiagnosticsMode.ErrorsAndWarnings,
    TAtlasInlineDiagnostics.ModeOf('ERRORSANDWARNINGS'));
  Assert.AreEqual<TAtlasInlineDiagnosticsMode>(TAtlasInlineDiagnosticsMode.Errors,
    TAtlasInlineDiagnostics.ModeOf('unsinn'), 'Vorgabe');
  Assert.IsFalse(TAtlasInlineDiagnostics.Shows(TAtlasInlineDiagnosticsMode.Off, TAtlasProblemSeverity.Error));
end;

procedure TAtlasInlineDiagnosticsTests.PicksWorstProblemOfLineAndCountsOthers;
var
  mProblems: TArray<TAtlasProblem>;
  mInactive, mUsesHint: TAtlasProblem;
  mFound: TAtlasInlineDiagnostic;
begin
  mInactive := Problem(4, 0, TAtlasProblemSeverity.Error, 'inaktiv');
  mInactive.Unnecessary := True;
  mUsesHint := Problem(4, 0, TAtlasProblemSeverity.Error, 'uses');
  mUsesHint.UsesState := TAtlasProblem.cUsesUnused;
  mProblems := [Problem(4, 9, TAtlasProblemSeverity.Warning, 'Warnung'), Problem(4, 7, TAtlasProblemSeverity.Error,
    'Zweiter Fehler'), Problem(4, 2, TAtlasProblemSeverity.Error, 'Erster Fehler'), Problem(5, 0,
    TAtlasProblemSeverity.Error, 'andere Zeile'), mInactive, mUsesHint];
  Assert.IsTrue(TAtlasInlineDiagnostics.Pick(mProblems, 4, TAtlasInlineDiagnosticsMode.All, mFound));
  Assert.AreEqual('Erster Fehler', mFound.Problem.Message, 'schwerster, bei Gleichstand der linke');
  Assert.AreEqual(2, mFound.More, 'zweiter Fehler und Warnung; Abblendungen zählen nicht');
  Assert.AreEqual('Erster Fehler (+2)', TAtlasInlineDiagnostics.Caption(mFound));
  Assert.IsFalse(TAtlasInlineDiagnostics.Pick(mProblems, 3, TAtlasInlineDiagnosticsMode.All, mFound));
end;

procedure TAtlasInlineDiagnosticsTests.ErrorsModeShowsNoWarnings;
var
  mProblems: TArray<TAtlasProblem>;
  mFound: TAtlasInlineDiagnostic;
begin
  mProblems := [Problem(1, 0, TAtlasProblemSeverity.Warning, 'W'), Problem(2, 0, TAtlasProblemSeverity.Hint, 'H'),
    Problem(2, 4, TAtlasProblemSeverity.Error, 'E')];
  Assert.IsFalse(TAtlasInlineDiagnostics.Pick(mProblems, 1, TAtlasInlineDiagnosticsMode.Errors, mFound), 'nur Fehler');
  Assert.IsTrue(TAtlasInlineDiagnostics.Pick(mProblems, 1, TAtlasInlineDiagnosticsMode.ErrorsAndWarnings, mFound));
  Assert.IsTrue(TAtlasInlineDiagnostics.Pick(mProblems, 2, TAtlasInlineDiagnosticsMode.Errors, mFound));
  Assert.AreEqual(0, mFound.More, 'der Hinweis zählt im Modus „nur Fehler“ nicht');
  Assert.IsFalse(TAtlasInlineDiagnostics.Pick(mProblems, 2, TAtlasInlineDiagnosticsMode.Off, mFound), 'aus');
end;

procedure TAtlasInlineDiagnosticsTests.CaptionTakesFirstLineAndShortens;
var
  mFound: TAtlasInlineDiagnostic;
  mText: string;
begin
  mFound := Default(TAtlasInlineDiagnostic);
  mFound.Problem.Message := 'Erste Zeile'#13#10'Zweite Zeile';
  Assert.AreEqual('Erste Zeile', TAtlasInlineDiagnostics.Caption(mFound));
  mFound.Problem.Message := StringOfChar('x', 200);
  mText := TAtlasInlineDiagnostics.Caption(mFound);
  Assert.AreEqual(TAtlasInlineDiagnostics.cMaxChars, Integer(Length(mText)));
  Assert.AreEqual('…', Copy(mText, Length(mText), 1));
end;

procedure TAtlasInlineDiagnosticsTests.CaptionOfTestFailureAtAssertIsShort;
var
  mFound: TAtlasInlineDiagnostic;
begin
  // #1771: Fehlschlag an der Assert-Zeile mit kurzem Text in Details.
  mFound := Default(TAtlasInlineDiagnostic);
  mFound.Problem.Message := 'Test TRechnerTests.Addiert fehlgeschlagen: erwartet 4, erhalten 3';
  mFound.Problem.Source := TAtlasProblemStore.cTestSource;
  mFound.Problem.Details := 'erwartet 4, erhalten 3';
  Assert.IsTrue(TAtlasInlineDiagnostics.IsShortTest(mFound.Problem));
  Assert.AreEqual('erwartet 4, erhalten 3', TAtlasInlineDiagnostics.Caption(mFound));
  mFound.Problem.Details := '';
  Assert.IsFalse(TAtlasInlineDiagnostics.IsShortTest(mFound.Problem), 'ohne kurzen Text die Meldung');
  Assert.AreEqual(mFound.Problem.Message, TAtlasInlineDiagnostics.Caption(mFound));
  mFound.Problem.Source := 'Atlas';
  mFound.Problem.Details := 'Durchsucht: 3 Dateien';
  Assert.IsFalse(TAtlasInlineDiagnostics.IsShortTest(mFound.Problem), 'Details anderer Befunde bleiben im Hover');
end;

procedure TAtlasInlineDiagnosticsTests.CountsMatchTheList;
var
  mCompiler, mInactive: TAtlasProblem;
  mCounts: TAtlasProblemCounts;
begin
  mCompiler := Problem(0, 0, TAtlasProblemSeverity.Error, 'dcc');
  mCompiler.Source := TAtlasProblem.cCompilerSource;
  mInactive := Problem(0, 0, TAtlasProblemSeverity.Hint, 'inaktiv');
  mInactive.Unnecessary := True;
  mCounts := TAtlasInlineDiagnostics.Counts([Problem(0, 0, TAtlasProblemSeverity.Error, 'E'), Problem(1, 0,
    TAtlasProblemSeverity.Warning, 'W'), Problem(2, 0, TAtlasProblemSeverity.Information, 'I'), Problem(3, 0,
    TAtlasProblemSeverity.Hint, 'H'), mCompiler, mInactive]);
  Assert.AreEqual(1, mCounts.Errors);
  Assert.AreEqual(1, mCounts.Warnings);
  Assert.AreEqual(2, mCounts.Hints, 'Info zählt als Hinweis');
  Assert.AreEqual(4, mCounts.Total, 'Compilermeldungen stehen nicht in der Liste');
end;

procedure TAtlasInlineDiagnosticsTests.NextWalksThroughFileAndWraps;
var
  mProblems: TArray<TAtlasProblem>;
  mTarget: TAtlasProblem;
begin
  mProblems := [Problem(9, 1, TAtlasProblemSeverity.Hint, 'C'), Problem(2, 5, TAtlasProblemSeverity.Error, 'A'),
    Problem(4, 0, TAtlasProblemSeverity.Warning, 'B')];
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(mProblems, 0, 0, True, mTarget));
  Assert.AreEqual('A', mTarget.Message);
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(mProblems, 2, 5, True, mTarget), 'ab dem Befund selbst');
  Assert.AreEqual('B', mTarget.Message);
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(mProblems, 9, 1, True, mTarget));
  Assert.AreEqual('A', mTarget.Message, 'am Ende von vorn');
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(mProblems, 4, 0, False, mTarget));
  Assert.AreEqual('A', mTarget.Message);
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(mProblems, 1, 0, False, mTarget));
  Assert.AreEqual('C', mTarget.Message, 'am Anfang von hinten');
  Assert.IsFalse(TAtlasInlineDiagnostics.Next(nil, 0, 0, True, mTarget));
end;

procedure TAtlasInlineDiagnosticsTests.PauseWaitsOneSecond;
begin
  Assert.IsTrue(TAtlasInlineDiagnostics.PauseOver(0, 50), 'nie getippt');
  Assert.IsFalse(TAtlasInlineDiagnostics.PauseOver(1000, 1999));
  Assert.IsTrue(TAtlasInlineDiagnostics.PauseOver(1000, 2000));
  Assert.IsFalse(TAtlasInlineDiagnostics.PauseOver($FFFFFF00, $100000064), 'über die 32-Bit-Grenze hinweg');
  Assert.IsTrue(TAtlasInlineDiagnostics.PauseOver($FFFFFF00, $100000400), 'über die 32-Bit-Grenze hinweg');
end;

procedure TAtlasInlineDiagnosticsTests.LineTailPlacesPaintersSideBySide;
var
  mHints, mErrors: TObject;
  mKey: string;
begin
  mHints := TObject.Create;
  mErrors := TObject.Create;
  try
    TAtlasLineTail.Reset;
    mKey := TAtlasLineTail.KeyOf('U.pas', 3, 3, 40);
    Assert.AreEqual(100, TAtlasLineTail.Start(mHints, mKey, 100));
    TAtlasLineTail.Finish(mHints, mKey, 150);
    Assert.AreEqual(150 + TAtlasLineTail.cGap, TAtlasLineTail.Start(mErrors, mKey, 100), 'hinter den Hinweisen');
    TAtlasLineTail.Finish(mErrors, mKey, 300);
    // Neues Zeichnen derselben Zeile, diesmal zuerst die Fehler.
    Assert.AreEqual(100, TAtlasLineTail.Start(mErrors, mKey, 100));
    TAtlasLineTail.Finish(mErrors, mKey, 200);
    Assert.AreEqual(200 + TAtlasLineTail.cGap, TAtlasLineTail.Start(mHints, mKey, 100));
    // Andere Zeile beginnt am eigenen Rand.
    Assert.AreEqual(60, TAtlasLineTail.Start(mHints, TAtlasLineTail.KeyOf('U.pas', 4, 4, 56), 60));
  finally
    TAtlasLineTail.Reset;
    mHints.Free;
    mErrors.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlineDiagnosticsTests);

end.
