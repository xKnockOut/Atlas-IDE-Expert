unit Atlas.Core.BuildPipeline.Gate.Tests;

// Tests für die Prüfung vor dem Kompilieren (#529) ohne IDE: wann geprüft
// wird, welche Units als geändert gelten, welche Treffer zählen, die Modi warn
// und block, bewusstes Übergehen und das Zeitlimit, alles über die
// Compile-Ereignisse (#527) mit gefälschten Units, Prüfer und Uhr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.BuildPipeline')]
  TAtlasBuildGateTests = class
  public
    /// <summary>off, Syntaxprüfung, Clean, Hintergrundprüfung und Aufträge: keine Prüfung.</summary>
    [Test]
    procedure AppliesOnlyToUserMakeAndBuild;
    [Test]
    procedure SettingsClampTimeout;
    /// <summary>Ohne gemerkten Stand zählt die Ausgabedatei, sonst der Stand.</summary>
    [Test]
    procedure ChangedUnitsByStampOrOutputTime;
    /// <summary>Nur Fehler zählen, keine Warnungen, keine Compilermeldungen, keine inaktiven Bereiche.</summary>
    [Test]
    procedure OnlyErrorsCount;
    /// <summary>block mit Syntaxfehler: Der Compile startet nicht, der Treffer wird gemeldet.</summary>
    [Test]
    procedure BlockStopsCompileOnSyntaxError;
    /// <summary>warn: Der Compile startet, der Treffer wird trotzdem gemeldet.</summary>
    [Test]
    procedure WarnReportsAndCompiles;
    /// <summary>Ein Regeltreffer mit Schweregrad Warnung blockiert nie.</summary>
    [Test]
    procedure WarningNeverBlocks;
    /// <summary>Zweiter Compile ohne Änderung binnen 10 s läuft; nach einer Änderung wieder block.</summary>
    [Test]
    procedure SecondCompileWithinOverrideRuns;
    /// <summary>Ein verlangsamter Prüflauf (1 s) hält den Compile höchstens build.gateTimeoutMs auf.</summary>
    [Test]
    procedure SlowCheckStopsAtTimeout;
    /// <summary>Das Zeitlimit wird einmal je Sitzung gemeldet.</summary>
    [Test]
    procedure TimeoutNotifiedOncePerSession;
    /// <summary>Nach einem erfolgreichen Compile prüft der nächste nur noch, was sich seither geändert hat; ein
    /// gescheiterter oder abgebrochener Compile merkt nichts.</summary>
    [Test]
    procedure RemembersStampsOnlyAfterSuccess;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.PipelineSettings,
  Atlas.Core.BuildPipeline.ReleaseGuard,
  Atlas.Core.BuildPipeline.Gate;

const
  cProjectFile = 'C:\P\Kasse.dproj';
  cMainUnit = 'C:\P\Main.pas';
  cDataUnit = 'C:\P\Daten.pas';
  cOutcomeNames: array[TAtlasGateOutcome] of string = ('passed', 'reported', 'blocked', 'overridden', 'timedOut');

function Project(AKind: TAtlasCompileKind): TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := cProjectFile;
  Result.Kind := AKind;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win32';
end;

function UnitOf(const AFileName, AStamp: string; AModifiedAt: TDateTime): TAtlasGateUnit;
begin
  Result.FileName := AFileName;
  Result.Stamp := AStamp;
  Result.ModifiedAt := AModifiedAt;
end;

function Problem(ASeverity: TAtlasProblemSeverity; const ACode, ASource: string; ALine: Integer): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.Severity := ASeverity;
  Result.Code := ACode;
  Result.Source := ASource;
  Result.StartLine := ALine;
  Result.Message := ACode;
end;

type
  TGateRun = class
  public
    Gate: string;
    TimeoutMs: Integer;
    Units: TAtlasGateUnits;
    OutputTime: TDateTime;
    /// <summary>Befunde je Datei (groß geschrieben).</summary>
    Problems: TDictionary<string, TArray<TAtlasProblem>>;
    /// <summary>So lange braucht eine Prüfung (ms), ohne Zeitlimit.</summary>
    CheckMs: Integer;
    Clock: Int64;
    Checked: string;
    Reported: string;
    Notified: Integer;
    constructor Create;
    destructor Destroy; override;
    function Make: TAtlasCompileEvents;
  end;

constructor TGateRun.Create;
begin
  inherited Create;
  Gate := 'block';
  TimeoutMs := 300;
  Problems := TDictionary<string, TArray<TAtlasProblem>>.Create;
end;

destructor TGateRun.Destroy;
begin
  Problems.Free;
  inherited;
end;

function TGateRun.Make: TAtlasCompileEvents;
begin
  Result := TAtlasCompileEvents.Create(
    function: Int64
    begin
      Result := Clock;
    end);
  Result.Add(TAtlasBuildGateParticipant.Create(
    function: TAtlasGateSettings
    begin
      Result := TAtlasGateSettings.Create(Gate, TimeoutMs);
    end,
    function(const AProject: TAtlasCompileProject; out AUnits: TAtlasGateUnits; out AOutputTime: TDateTime): Boolean
    begin
      AUnits := Units;
      AOutputTime := OutputTime;
      Result := True;
    end,
    function(const AFileName: string; ATimeoutMs: Integer; out AProblems: TArray<TAtlasProblem>): Boolean
    begin
      Checked := Checked + ExtractFileName(AFileName) + ' ';
      // Wie der Server mit Zeitlimit: höchstens ATimeoutMs warten.
      if CheckMs > ATimeoutMs then
      begin
        Inc(Clock, ATimeoutMs);
        AProblems := nil;
        Exit(False);
      end;
      Inc(Clock, CheckMs);
      if not Problems.TryGetValue(UpperCase(AFileName), AProblems) then
      begin
        AProblems := nil;
      end;
      Result := True;
    end,
    function(const AProject: TAtlasCompileProject; const AFindings: TAtlasGateFindings; ACheckedUnits: Integer;
      AOutcome: TAtlasGateOutcome; ANotifyTimeout: Boolean): string
    var
      Finding: TAtlasGateFinding;
    begin
      Reported := Reported + cOutcomeNames[AOutcome] + ':';
      for Finding in AFindings do
      begin
        Reported := Reported + ExtractFileName(Finding.FileName) + '/' + Finding.Problem.Code + ',';
      end;
      Reported := Reported + ' ';
      if ANotifyTimeout then
      begin
        Inc(Notified);
      end;
      Result := Format('%d Fehler', [Length(AFindings)]);
    end,
    function: Int64
    begin
      Result := Clock;
    end));
end;

procedure TAtlasBuildGateTests.AppliesOnlyToUserMakeAndBuild;
var
  mSettings: TAtlasGateSettings;
  mInfo: TAtlasCompileProject;
begin
  mSettings := TAtlasGateSettings.Create('warn', 300);
  Assert.IsTrue(TAtlasBuildGateCheck.Applies(mSettings, Project(TAtlasCompileKind.Make)));
  Assert.IsTrue(TAtlasBuildGateCheck.Applies(mSettings, Project(TAtlasCompileKind.Build)));
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(mSettings, Project(TAtlasCompileKind.Check)), 'Syntaxprüfung');
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(mSettings, Project(TAtlasCompileKind.Clean)), 'Clean');
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(mSettings, Project(TAtlasCompileKind.MakeUnit)), 'eine Unit');
  mInfo := Project(TAtlasCompileKind.Make);
  mInfo.Background := True;
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(mSettings, mInfo), 'Hintergrundprüfung #548');
  mInfo := Project(TAtlasCompileKind.Make);
  mInfo.RequestedBy := 'mcp';
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(mSettings, mInfo), 'Auftrag von Claude Code #261');
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(TAtlasGateSettings.Create('off', 300), Project(TAtlasCompileKind.Make)),
    'build.gate = off');
end;

procedure TAtlasBuildGateTests.SettingsClampTimeout;
begin
  Assert.AreEqual(TAtlasBuildPipelineSettings.GateMinTimeoutMs, TAtlasGateSettings.Create('block', 0).TimeoutMs);
  Assert.AreEqual(TAtlasBuildPipelineSettings.GateMaxTimeoutMs, TAtlasGateSettings.Create('block', 999999).TimeoutMs);
  Assert.AreEqual(300, TAtlasGateSettings.Create('block', 300).TimeoutMs);
  Assert.IsTrue(TAtlasGateSettings.Create('BLOCK', 300).Gate = TAtlasBuildGate.Block);
  Assert.IsTrue(TAtlasGateSettings.Create('streng', 300).Gate = TAtlasBuildGate.Off);
end;

procedure TAtlasBuildGateTests.ChangedUnitsByStampOrOutputTime;
var
  mRemembered: TDictionary<string, string>;
  mUnits: TAtlasGateUnits;
  mChanged: TArray<string>;
begin
  mUnits := [UnitOf(cMainUnit, 'd:100', 100), UnitOf(cDataUnit, 'd:50', 50)];
  // Ohne Ausgabedatei: alles geändert.
  mChanged := TAtlasBuildGateCheck.Changed(mUnits, nil, 0);
  Assert.AreEqual(2, Integer(Length(mChanged)));
  // Ausgabedatei von 80: nur Main ist neuer.
  mChanged := TAtlasBuildGateCheck.Changed(mUnits, nil, 80);
  Assert.AreEqual(1, Integer(Length(mChanged)));
  Assert.AreEqual(cMainUnit, mChanged[0]);
  mRemembered := TDictionary<string, string>.Create;
  try
    mRemembered.Add(UpperCase(cMainUnit), 'd:100');
    mRemembered.Add(UpperCase(cDataUnit), 'd:40');
    // Gemerkter Stand gewinnt über die Zeit: Main gleich, Daten anders (auch wenn älter als die Ausgabe).
    mChanged := TAtlasBuildGateCheck.Changed(mUnits, mRemembered, 80);
    Assert.AreEqual(1, Integer(Length(mChanged)));
    Assert.AreEqual(cDataUnit, mChanged[0]);
  finally
    mRemembered.Free;
  end;
end;

procedure TAtlasBuildGateTests.OnlyErrorsCount;
var
  mItem: TAtlasProblem;
begin
  Assert.IsTrue(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 1)));
  Assert.IsTrue(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Error, 'x', TAtlasProblem.ConfirmedSource,
    1)), 'Atlas-Befund, vom Compiler bestätigt');
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Warning, 'x', 'Atlas', 1)));
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Hint, 'x', 'Atlas', 1)));
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Error, 'E2003', 'dcc', 1)),
    'Compilermeldung des vorigen Builds');
  mItem := Problem(TAtlasProblemSeverity.Error, 'x', 'Atlas', 1);
  mItem.Unnecessary := True;
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(mItem), 'inaktiver Bereich');
end;

procedure TAtlasBuildGateTests.BlockStopsCompileOnSyntaxError;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGateRun.Create;
  try
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100), UnitOf(cDataUnit, 'd:50', 50)];
    mRun.OutputTime := 80;
    mRun.Problems.Add(UpperCase(cMainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
    mEvents := mRun.Make;
    try
      Assert.IsTrue(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason), 'block');
      Assert.AreEqual('Kasse.dproj: 1 Fehler', mReason);
      Assert.AreEqual('blocked:Main.pas/syntax, ', mRun.Reported);
      Assert.AreEqual('Main.pas ', mRun.Checked, 'nur die geänderte Unit');
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasBuildGateTests.WarnReportsAndCompiles;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGateRun.Create;
  try
    mRun.Gate := 'warn';
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100)];
    mRun.Problems.Add(UpperCase(cMainUnit), [Problem(TAtlasProblemSeverity.Error, 'empty-except', 'Atlas', 3)]);
    mEvents := mRun.Make;
    try
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Build), False, mReason), 'warn');
      Assert.AreEqual('', mReason);
      Assert.AreEqual('reported:Main.pas/empty-except, ', mRun.Reported);
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasBuildGateTests.WarningNeverBlocks;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGateRun.Create;
  try
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100)];
    mRun.Problems.Add(UpperCase(cMainUnit), [Problem(TAtlasProblemSeverity.Warning, 'empty-except', 'Atlas', 3),
      Problem(TAtlasProblemSeverity.Error, 'E2003', 'dcc', 4)]);
    mEvents := mRun.Make;
    try
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      Assert.AreEqual('', mRun.Reported, 'nichts zu melden');
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasBuildGateTests.SecondCompileWithinOverrideRuns;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGateRun.Create;
  try
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100)];
    mRun.Problems.Add(UpperCase(cMainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
    mEvents := mRun.Make;
    try
      Assert.IsTrue(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      Inc(mRun.Clock, 5000);
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason),
        'zweiter Compile binnen 10 s läuft');
      Assert.AreEqual('blocked:Main.pas/syntax, overridden:Main.pas/syntax, ', mRun.Reported);
      // Danach wieder block; ebenso nach einer Änderung der Unit.
      mRun.Reported := '';
      Inc(mRun.Clock, 1000);
      Assert.IsTrue(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      Inc(mRun.Clock, 1000);
      mRun.Units := [UnitOf(cMainUnit, 'b:2', 100)];
      Assert.IsTrue(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason), 'Unit geändert');
      // Zu spät: nach mehr als 10 s wieder block.
      Inc(mRun.Clock, TAtlasBuildGateCheck.cOverrideMs + 1);
      Assert.IsTrue(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason), 'nach 10 s');
      Assert.AreEqual('blocked:Main.pas/syntax, blocked:Main.pas/syntax, blocked:Main.pas/syntax, ', mRun.Reported);
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasBuildGateTests.SlowCheckStopsAtTimeout;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
  mBefore: Int64;
begin
  mRun := TGateRun.Create;
  try
    mRun.CheckMs := 1000;
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100), UnitOf(cDataUnit, 'b:2', 100)];
    mRun.Problems.Add(UpperCase(cMainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
    mEvents := mRun.Make;
    try
      mBefore := mRun.Clock;
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason),
        'Zeitlimit: der Compile läuft ungehindert');
      Assert.IsTrue(mRun.Clock - mBefore <= 300, Format('höchstens 300 ms, waren %d', [mRun.Clock - mBefore]));
      Assert.AreEqual('Main.pas ', mRun.Checked, 'nach dem Zeitlimit keine weitere Unit');
      Assert.AreEqual('timedOut: ', mRun.Reported);
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasBuildGateTests.TimeoutNotifiedOncePerSession;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGateRun.Create;
  try
    mRun.CheckMs := 1000;
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100)];
    mEvents := mRun.Make;
    try
      mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason);
      mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason);
      mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason);
      Assert.AreEqual(1, mRun.Notified);
      Assert.AreEqual('timedOut: ', mRun.Reported, 'ohne Treffer nur das erste Mal gemeldet');
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasBuildGateTests.RemembersStampsOnlyAfterSuccess;
var
  mRun: TGateRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGateRun.Create;
  try
    mRun.Units := [UnitOf(cMainUnit, 'b:1', 100), UnitOf(cDataUnit, 'd:50', 100)];
    mEvents := mRun.Make;
    try
      // Gescheitert: nichts gemerkt.
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      mEvents.ProjectStarted(Project(TAtlasCompileKind.Make));
      mEvents.ProjectFinished(cProjectFile, False);
      Assert.AreEqual('Main.pas Daten.pas ', mRun.Checked);
      // Erfolgreich: Stände gemerkt, der nächste Compile prüft nur die geänderte Unit.
      mRun.Checked := '';
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      mEvents.ProjectStarted(Project(TAtlasCompileKind.Make));
      mEvents.ProjectFinished(cProjectFile, True);
      Assert.AreEqual('Main.pas Daten.pas ', mRun.Checked);
      mRun.Checked := '';
      mRun.Units := [UnitOf(cMainUnit, 'b:2', 100), UnitOf(cDataUnit, 'd:50', 100)];
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      Assert.AreEqual('Main.pas ', mRun.Checked);
      // Abgebrochen (hier: block): der Stand b:3 gilt nicht als kompiliert.
      mRun.Units := [UnitOf(cMainUnit, 'b:3', 100), UnitOf(cDataUnit, 'd:50', 100)];
      mRun.Problems.Add(UpperCase(cMainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
      Assert.IsTrue(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      mEvents.ProjectFinished(cProjectFile, True);
      mRun.Checked := '';
      mRun.Problems.Clear;
      Assert.IsFalse(mEvents.BeforeCompile(Project(TAtlasCompileKind.Make), False, mReason));
      Assert.AreEqual('Main.pas ', mRun.Checked, 'b:3 weiter geändert gegenüber b:2');
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildGateTests);

end.
