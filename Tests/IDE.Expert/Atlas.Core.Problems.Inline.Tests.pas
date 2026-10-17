unit Atlas.Core.Problems.Inline.Tests;

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
  Atlas.Core.Problems.Inline,
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
  Mode: TAtlasInlineDiagnosticsMode;
begin
  for Mode := Low(TAtlasInlineDiagnosticsMode) to High(TAtlasInlineDiagnosticsMode) do
    Assert.IsTrue(TAtlasInlineDiagnostics.ModeOf(TAtlasInlineDiagnostics.ModeName(Mode)) = Mode);
  Assert.IsTrue(TAtlasInlineDiagnostics.ModeOf('ERRORSANDWARNINGS') = TAtlasInlineDiagnosticsMode.ErrorsAndWarnings);
  Assert.IsTrue(TAtlasInlineDiagnostics.ModeOf('unsinn') = TAtlasInlineDiagnosticsMode.Errors, 'Vorgabe');
  Assert.IsFalse(TAtlasInlineDiagnostics.Shows(TAtlasInlineDiagnosticsMode.Off, TAtlasProblemSeverity.Error));
end;

procedure TAtlasInlineDiagnosticsTests.PicksWorstProblemOfLineAndCountsOthers;
var
  Problems: TArray<TAtlasProblem>;
  Inactive, UsesHint: TAtlasProblem;
  Found: TAtlasInlineDiagnostic;
begin
  Inactive := Problem(4, 0, TAtlasProblemSeverity.Error, 'inaktiv');
  Inactive.Unnecessary := True;
  UsesHint := Problem(4, 0, TAtlasProblemSeverity.Error, 'uses');
  UsesHint.UsesState := TAtlasProblem.UsesUnused;
  Problems := [Problem(4, 9, TAtlasProblemSeverity.Warning, 'Warnung'), Problem(4, 7, TAtlasProblemSeverity.Error,
    'Zweiter Fehler'), Problem(4, 2, TAtlasProblemSeverity.Error, 'Erster Fehler'), Problem(5, 0,
    TAtlasProblemSeverity.Error, 'andere Zeile'), Inactive, UsesHint];
  Assert.IsTrue(TAtlasInlineDiagnostics.Pick(Problems, 4, TAtlasInlineDiagnosticsMode.All, Found));
  Assert.AreEqual('Erster Fehler', Found.Problem.Message, 'schwerster, bei Gleichstand der linke');
  Assert.AreEqual(2, Found.More, 'zweiter Fehler und Warnung; Abblendungen zählen nicht');
  Assert.AreEqual('Erster Fehler (+2)', TAtlasInlineDiagnostics.Caption(Found));
  Assert.IsFalse(TAtlasInlineDiagnostics.Pick(Problems, 3, TAtlasInlineDiagnosticsMode.All, Found));
end;

procedure TAtlasInlineDiagnosticsTests.ErrorsModeShowsNoWarnings;
var
  Problems: TArray<TAtlasProblem>;
  Found: TAtlasInlineDiagnostic;
begin
  Problems := [Problem(1, 0, TAtlasProblemSeverity.Warning, 'W'), Problem(2, 0, TAtlasProblemSeverity.Hint, 'H'),
    Problem(2, 4, TAtlasProblemSeverity.Error, 'E')];
  Assert.IsFalse(TAtlasInlineDiagnostics.Pick(Problems, 1, TAtlasInlineDiagnosticsMode.Errors, Found), 'nur Fehler');
  Assert.IsTrue(TAtlasInlineDiagnostics.Pick(Problems, 1, TAtlasInlineDiagnosticsMode.ErrorsAndWarnings, Found));
  Assert.IsTrue(TAtlasInlineDiagnostics.Pick(Problems, 2, TAtlasInlineDiagnosticsMode.Errors, Found));
  Assert.AreEqual(0, Found.More, 'der Hinweis zählt im Modus „nur Fehler“ nicht');
  Assert.IsFalse(TAtlasInlineDiagnostics.Pick(Problems, 2, TAtlasInlineDiagnosticsMode.Off, Found), 'aus');
end;

procedure TAtlasInlineDiagnosticsTests.CaptionTakesFirstLineAndShortens;
var
  Found: TAtlasInlineDiagnostic;
  Text: string;
begin
  Found := Default(TAtlasInlineDiagnostic);
  Found.Problem.Message := 'Erste Zeile'#13#10'Zweite Zeile';
  Assert.AreEqual('Erste Zeile', TAtlasInlineDiagnostics.Caption(Found));
  Found.Problem.Message := StringOfChar('x', 200);
  Text := TAtlasInlineDiagnostics.Caption(Found);
  Assert.AreEqual(TAtlasInlineDiagnostics.MaxChars, Integer(Length(Text)));
  Assert.AreEqual('…', Copy(Text, Length(Text), 1));
end;

procedure TAtlasInlineDiagnosticsTests.CountsMatchTheList;
var
  Compiler, Inactive: TAtlasProblem;
  Counts: TAtlasProblemCounts;
begin
  Compiler := Problem(0, 0, TAtlasProblemSeverity.Error, 'dcc');
  Compiler.Source := TAtlasProblem.CompilerSource;
  Inactive := Problem(0, 0, TAtlasProblemSeverity.Hint, 'inaktiv');
  Inactive.Unnecessary := True;
  Counts := TAtlasInlineDiagnostics.Counts([Problem(0, 0, TAtlasProblemSeverity.Error, 'E'), Problem(1, 0,
    TAtlasProblemSeverity.Warning, 'W'), Problem(2, 0, TAtlasProblemSeverity.Information, 'I'), Problem(3, 0,
    TAtlasProblemSeverity.Hint, 'H'), Compiler, Inactive]);
  Assert.AreEqual(1, Counts.Errors);
  Assert.AreEqual(1, Counts.Warnings);
  Assert.AreEqual(2, Counts.Hints, 'Info zählt als Hinweis');
  Assert.AreEqual(4, Counts.Total, 'Compilermeldungen stehen nicht in der Liste');
end;

procedure TAtlasInlineDiagnosticsTests.NextWalksThroughFileAndWraps;
var
  Problems: TArray<TAtlasProblem>;
  Target: TAtlasProblem;
begin
  Problems := [Problem(9, 1, TAtlasProblemSeverity.Hint, 'C'), Problem(2, 5, TAtlasProblemSeverity.Error, 'A'),
    Problem(4, 0, TAtlasProblemSeverity.Warning, 'B')];
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(Problems, 0, 0, True, Target));
  Assert.AreEqual('A', Target.Message);
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(Problems, 2, 5, True, Target), 'ab dem Befund selbst');
  Assert.AreEqual('B', Target.Message);
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(Problems, 9, 1, True, Target));
  Assert.AreEqual('A', Target.Message, 'am Ende von vorn');
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(Problems, 4, 0, False, Target));
  Assert.AreEqual('A', Target.Message);
  Assert.IsTrue(TAtlasInlineDiagnostics.Next(Problems, 1, 0, False, Target));
  Assert.AreEqual('C', Target.Message, 'am Anfang von hinten');
  Assert.IsFalse(TAtlasInlineDiagnostics.Next(nil, 0, 0, True, Target));
end;

procedure TAtlasInlineDiagnosticsTests.PauseWaitsOneSecond;
begin
  Assert.IsTrue(TAtlasInlineDiagnostics.PauseOver(0, 50), 'nie getippt');
  Assert.IsFalse(TAtlasInlineDiagnostics.PauseOver(1000, 1999));
  Assert.IsTrue(TAtlasInlineDiagnostics.PauseOver(1000, 2000));
  Assert.IsFalse(TAtlasInlineDiagnostics.PauseOver($FFFFFF00, 100), 'Überlauf von GetTickCount');
end;

procedure TAtlasInlineDiagnosticsTests.LineTailPlacesPaintersSideBySide;
var
  Hints, Errors: TObject;
  Key: string;
begin
  Hints := TObject.Create;
  Errors := TObject.Create;
  try
    TAtlasLineTail.Reset;
    Key := TAtlasLineTail.KeyOf('U.pas', 3, 3, 40);
    Assert.AreEqual(100, TAtlasLineTail.Start(Hints, Key, 100));
    TAtlasLineTail.Finish(Hints, Key, 150);
    Assert.AreEqual(150 + TAtlasLineTail.Gap, TAtlasLineTail.Start(Errors, Key, 100), 'hinter den Hinweisen');
    TAtlasLineTail.Finish(Errors, Key, 300);
    // Neues Zeichnen derselben Zeile, diesmal zuerst die Fehler.
    Assert.AreEqual(100, TAtlasLineTail.Start(Errors, Key, 100));
    TAtlasLineTail.Finish(Errors, Key, 200);
    Assert.AreEqual(200 + TAtlasLineTail.Gap, TAtlasLineTail.Start(Hints, Key, 100));
    // Andere Zeile beginnt am eigenen Rand.
    Assert.AreEqual(60, TAtlasLineTail.Start(Hints, TAtlasLineTail.KeyOf('U.pas', 4, 4, 56), 60));
  finally
    TAtlasLineTail.Reset;
    Hints.Free;
    Errors.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlineDiagnosticsTests);

end.
