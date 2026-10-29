unit Atlas.Core.StatusBar.Content.Tests;

// Atlas-Statusleiste (#1155): Zähler der Unit wie im Fenster „Atlas-Prüfung“
// (ohne inaktive Zweige und uses-Hinweise, Compilermeldungen nur auf Wunsch),
// nächster Befund einer Art mit Umlauf, Text der Live-Prüfung und die Methode
// am Cursor mit Zeilen, CC und den Grenzen der Metrikregeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusBarContentTests = class
  public
    [Test]
    procedure CountsLikeProblemsWindow;
    [Test]
    procedure NextOfKindWraps;
    [Test]
    procedure NextOfKindWithoutFinding;
    [Test]
    procedure LiveTexts;
    [Test]
    procedure AgeRounding;
    [Test]
    procedure MethodFromOutlineAndMetrics;
    [Test]
    procedure MethodWithoutMetrics;
    [Test]
    procedure MethodOverLimit;
    [Test]
    procedure NoMethodOutsideRoutines;
    /// <summary>#1232: „ · Projekt 45 %“ nur, solange Units fehlen; abgerundet.</summary>
    [Test]
    procedure ProjectProgressUntilComplete;
    /// <summary>#1247: Lauf der Projektprüfung mit Fortschritt, Pause beim Kompilieren und „fertig“.</summary>
    [Test]
    procedure RunTextShowsProgressPauseAndDone;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.StatusBar.Content;

function Problem(ALine, ACharacter: Integer; ASeverity: TAtlasProblemSeverity;
  const ASource: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := ACharacter;
  Result.EndLine := ALine;
  Result.EndCharacter := ACharacter + 3;
  Result.Severity := ASeverity;
  Result.Source := ASource;
  Result.Message := 'Meldung';
end;

function Sample: TArray<TAtlasProblem>;
var
  Dimmed: TAtlasProblem;
begin
  Dimmed := Problem(3, 0, TAtlasProblemSeverity.Hint, 'Atlas');
  Dimmed.Unnecessary := True;
  Result := [Problem(40, 2, TAtlasProblemSeverity.Warning, 'Atlas'),
    Problem(10, 4, TAtlasProblemSeverity.Error, 'Atlas'), Problem(25, 0, TAtlasProblemSeverity.Warning, 'Atlas'),
    Problem(12, 1, TAtlasProblemSeverity.Information, 'Atlas'), Problem(13, 1, TAtlasProblemSeverity.Hint, 'Atlas'),
    Problem(30, 0, TAtlasProblemSeverity.Error, TAtlasProblem.CompilerSource), Dimmed];
end;

function Texts: TAtlasStatusLiveTexts;
begin
  Result.Live := 'live';
  Result.OnSave := 'beim Speichern';
  Result.Checking := 'prüft …';
  Result.CheckedAgo := 'geprüft vor %s';
  Result.Seconds := '%d s';
  Result.Minutes := '%d min';
  Result.Hours := '%d h';
  Result.Separator := ' · ';
  Result.ProjectProgress := 'Projekt %d %%';
  Result.ProjectDone := 'Projekt fertig';
  Result.ProjectPaused := 'pausiert (Kompilieren)';
end;

function Node(const AName: string; ACategory: TAtlasOutlineCategory; AStart, AEnd, AParent: Integer): TAtlasOutlineNode;
begin
  Result := Default(TAtlasOutlineNode);
  Result.Name := AName;
  Result.Category := ACategory;
  Result.StartLine := AStart;
  Result.EndLine := AEnd;
  Result.NameLine := AStart;
  Result.NameCharacter := 10;
  Result.Parent := AParent;
  Result.Declaration := -1;
  Result.Body := -1;
end;

/// <summary>Klasse TFoo mit Deklaration Bar (Zeile 5), Rumpf TFoo.Bar (20–29) mit lokaler Routine Inner (21–24),
/// Routine Helper (32–35).</summary>
function Outline: TAtlasOutlineNodes;
begin
  Result := [Node('TFoo', TAtlasOutlineCategory.TypeDecl, 3, 7, -1), Node('Bar', TAtlasOutlineCategory.Method, 5, 5, 0),
    Node('TFoo.Bar', TAtlasOutlineCategory.Method, 20, 29, -1), Node('Inner', TAtlasOutlineCategory.Routine, 21, 24, 2),
    Node('Helper', TAtlasOutlineCategory.Routine, 32, 35, -1)];
end;

function Metrics: TAtlasFileMetrics;
var
  Method: TAtlasMethodMetrics;
  Metric: TAtlasMetric;
begin
  Result := Default(TAtlasFileMetrics);
  Result.Enabled := True;
  for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
    Result.Limits[Metric] := MaxInt;
  Result.Limits[TAtlasMetric.MethodLength] := 8;
  Result.Limits[TAtlasMetric.Cyclomatic] := 15;
  Method := Default(TAtlasMethodMetrics);
  Method.Name := 'TFoo.Bar';
  Method.Line := 20;
  Method.Values[TAtlasMetric.MethodLength] := 7;
  Method.Values[TAtlasMetric.Cyclomatic] := 17;
  Result.Methods := [Method];
  Method.Name := 'Helper';
  // Text seit dem Abruf verschoben: über den Namen.
  Method.Line := 31;
  Method.Values[TAtlasMetric.MethodLength] := 4;
  Method.Values[TAtlasMetric.Cyclomatic] := 2;
  Result.Methods := Result.Methods + [Method];
end;

procedure TAtlasStatusBarContentTests.CountsLikeProblemsWindow;
var
  Counts: TAtlasStatusCounts;
begin
  Counts := TAtlasStatusBarContent.CountsOf(Sample, False);
  Assert.AreEqual(1, Counts[TAtlasFindingKind.Error], 'ohne Compilermeldung');
  Assert.AreEqual(2, Counts[TAtlasFindingKind.Warning]);
  Assert.AreEqual(2, Counts[TAtlasFindingKind.Info], 'Hinweise und Informationen, ohne Abblendung');
  Counts := TAtlasStatusBarContent.CountsOf(Sample, True);
  Assert.AreEqual(2, Counts[TAtlasFindingKind.Error], 'mit Compilermeldung');
  Counts := TAtlasStatusBarContent.CountsOf(nil, True);
  Assert.AreEqual(0, Counts[TAtlasFindingKind.Warning]);
end;

procedure TAtlasStatusBarContentTests.NextOfKindWraps;
var
  Target: TAtlasProblem;
begin
  Assert.IsTrue(TAtlasStatusBarContent.NextOf(Sample, TAtlasFindingKind.Warning, False, 0, 0, Target));
  Assert.AreEqual(25, Target.StartLine);
  Assert.IsTrue(TAtlasStatusBarContent.NextOf(Sample, TAtlasFindingKind.Warning, False, 25, 0, Target),
    'nicht der Befund genau am Cursor');
  Assert.AreEqual(40, Target.StartLine);
  Assert.IsTrue(TAtlasStatusBarContent.NextOf(Sample, TAtlasFindingKind.Warning, False, 40, 2, Target));
  Assert.AreEqual(25, Target.StartLine, 'am Ende wieder vom Anfang');
  Assert.IsTrue(TAtlasStatusBarContent.NextOf(Sample, TAtlasFindingKind.Info, False, 12, 1, Target));
  Assert.AreEqual(13, Target.StartLine, 'ohne den abgeblendeten in Zeile 3');
  Assert.IsTrue(TAtlasStatusBarContent.NextOf(Sample, TAtlasFindingKind.Error, True, 11, 0, Target));
  Assert.AreEqual(30, Target.StartLine, 'Compilermeldung nur mit AWithCompiler');
  Assert.IsTrue(TAtlasStatusBarContent.NextOf(Sample, TAtlasFindingKind.Error, False, 11, 0, Target));
  Assert.AreEqual(10, Target.StartLine);
end;

procedure TAtlasStatusBarContentTests.NextOfKindWithoutFinding;
var
  Target: TAtlasProblem;
begin
  Assert.IsFalse(TAtlasStatusBarContent.NextOf(nil, TAtlasFindingKind.Error, True, 0, 0, Target));
  Assert.IsFalse(TAtlasStatusBarContent.NextOf([Problem(1, 0, TAtlasProblemSeverity.Error,
    TAtlasProblem.CompilerSource)], TAtlasFindingKind.Error, False, 0, 0, Target));
end;

procedure TAtlasStatusBarContentTests.LiveTexts;
var
  Now_: TDateTime;
begin
  Now_ := EncodeDateTime(2026, 10, 23, 18, 30, 0, 0);
  Assert.AreEqual('prüft …', TAtlasStatusBarContent.LiveText(True, True, Now_, Now_, Texts));
  Assert.AreEqual('prüft …', TAtlasStatusBarContent.LiveText(False, True, 0, Now_, Texts));
  Assert.AreEqual('beim Speichern', TAtlasStatusBarContent.LiveText(False, False, IncSecond(Now_, -5), Now_, Texts));
  Assert.AreEqual('live', TAtlasStatusBarContent.LiveText(True, False, 0, Now_, Texts), 'noch nicht geprüft');
  Assert.AreEqual('live · geprüft vor 2 s', TAtlasStatusBarContent.LiveText(True, False, IncSecond(Now_, -2), Now_,
    Texts));
  Assert.AreEqual('live · geprüft vor 0 s', TAtlasStatusBarContent.LiveText(True, False, IncSecond(Now_, 30), Now_,
    Texts), 'Uhr zurückgestellt');
end;

procedure TAtlasStatusBarContentTests.AgeRounding;
begin
  Assert.AreEqual('59 s', TAtlasStatusBarContent.AgeText(59, Texts));
  Assert.AreEqual('1 min', TAtlasStatusBarContent.AgeText(60, Texts));
  Assert.AreEqual('59 min', TAtlasStatusBarContent.AgeText(3599, Texts));
  Assert.AreEqual('2 h', TAtlasStatusBarContent.AgeText(7300, Texts));
  Assert.AreEqual('0 s', TAtlasStatusBarContent.AgeText(-4, Texts));
end;

procedure TAtlasStatusBarContentTests.MethodFromOutlineAndMetrics;
var
  Method: TAtlasStatusMethod;
begin
  Method := TAtlasStatusBarContent.MethodAt(Outline, 34, Metrics, True);
  Assert.IsTrue(Method.Found);
  Assert.AreEqual('Helper', Method.Name);
  Assert.AreEqual(32, Method.Line, 'Sprung zum Kopf');
  Assert.AreEqual(10, Method.Character);
  Assert.AreEqual(4, Method.Lines, 'Zeilen wie die Regel');
  Assert.AreEqual(2, Method.Cyclomatic);
  Assert.IsFalse(Method.Over);
  Assert.AreEqual('4 Zeilen · CC 2', TAtlasStatusBarContent.MethodDetail(Method, '%d Zeilen', 'CC %d', ' · '));
  // Deklaration in der Klasse: mit Besitzer, Kennzahlen über den Namen.
  Method := TAtlasStatusBarContent.MethodAt(Outline, 5, Metrics, True);
  Assert.AreEqual('TFoo.Bar', Method.Name);
  Assert.AreEqual(5, Method.Line);
  Assert.AreEqual(17, Method.Cyclomatic);
end;

procedure TAtlasStatusBarContentTests.MethodWithoutMetrics;
var
  Method: TAtlasStatusMethod;
begin
  // In der lokalen Routine: die innerste.
  Method := TAtlasStatusBarContent.MethodAt(Outline, 22, Default(TAtlasFileMetrics), False);
  Assert.AreEqual('Inner', Method.Name);
  Assert.AreEqual(4, Method.Lines, 'aus der Gliederung');
  Assert.AreEqual(-1, Method.Cyclomatic);
  Assert.AreEqual(MaxInt, Method.CyclomaticLimit);
  Assert.IsFalse(Method.Over);
  Assert.AreEqual('4 Zeilen', TAtlasStatusBarContent.MethodDetail(Method, '%d Zeilen', 'CC %d', ' · '));
  Assert.AreEqual('4 Zeilen', TAtlasStatusBarContent.MethodLimits(Method, '%d Zeilen', 'CC %d', '%s (Grenze %d)',
    ' · '));
end;

procedure TAtlasStatusBarContentTests.MethodOverLimit;
var
  Method: TAtlasStatusMethod;
begin
  Method := TAtlasStatusBarContent.MethodAt(Outline, 27, Metrics, True);
  Assert.AreEqual('TFoo.Bar', Method.Name);
  Assert.AreEqual(7, Method.Lines);
  Assert.IsFalse(Method.LinesOver);
  Assert.IsTrue(Method.CyclomaticOver);
  Assert.IsTrue(Method.Over, 'Warnfarbe');
  Assert.AreEqual('7 Zeilen (Grenze 8) · CC 17 (Grenze 15)', TAtlasStatusBarContent.MethodLimits(Method,
    '%d Zeilen', 'CC %d', '%s (Grenze %d)', ' · '));
end;

procedure TAtlasStatusBarContentTests.NoMethodOutsideRoutines;
var
  Method: TAtlasStatusMethod;
begin
  Method := TAtlasStatusBarContent.MethodAt(Outline, 12, Metrics, True);
  Assert.IsFalse(Method.Found);
  Assert.IsFalse(Method.Over);
  Assert.AreEqual('', TAtlasStatusBarContent.MethodDetail(Method, '%d Zeilen', 'CC %d', ' · '));
  Assert.IsFalse(TAtlasStatusBarContent.MethodAt(nil, 0, Metrics, True).Found);
end;

procedure TAtlasStatusBarContentTests.ProjectProgressUntilComplete;
begin
  Assert.AreEqual(' · Projekt 7 %', TAtlasStatusBarContent.ProgressText(2, 27, Texts));
  Assert.AreEqual(' · Projekt 99 %', TAtlasStatusBarContent.ProgressText(899, 900, Texts), 'abgerundet');
  Assert.AreEqual(' · Projekt 0 %', TAtlasStatusBarContent.ProgressText(0, 27, Texts));
  Assert.AreEqual('', TAtlasStatusBarContent.ProgressText(27, 27, Texts), 'fertig');
  Assert.AreEqual('', TAtlasStatusBarContent.ProgressText(0, 0, Texts), 'ohne Projekt');
end;

procedure TAtlasStatusBarContentTests.RunTextShowsProgressPauseAndDone;
begin
  Assert.AreEqual(' · Projekt 44 %', TAtlasStatusBarContent.RunText(True, 40, 90, '', High(UInt64), Texts));
  Assert.AreEqual(' · Projekt 44 % pausiert (Kompilieren)',
    TAtlasStatusBarContent.RunText(True, 40, 90, 'compile', High(UInt64), Texts));
  Assert.AreEqual(' · Projekt 0 %', TAtlasStatusBarContent.RunText(True, 0, 90, 'index', High(UInt64), Texts),
    'Indexaufbau gehört zum Lauf');
  Assert.AreEqual(' · Projekt 100 %', TAtlasStatusBarContent.RunText(True, 95, 90, '', High(UInt64), Texts),
    'höchstens 100 %');
  Assert.AreEqual(' · Projekt fertig', TAtlasStatusBarContent.RunText(False, 90, 90, '', 1000, Texts));
  Assert.AreEqual('', TAtlasStatusBarContent.RunText(False, 90, 90, '', 6000, Texts), 'danach ruhig');
  Assert.AreEqual('', TAtlasStatusBarContent.RunText(False, 90, 90, '', High(UInt64), Texts), 'nie gelaufen');
  Assert.AreEqual('', TAtlasStatusBarContent.RunText(True, 0, 0, '', High(UInt64), Texts), 'ohne Units');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusBarContentTests);

end.
