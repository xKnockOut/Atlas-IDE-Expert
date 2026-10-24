unit Atlas.Core.Build.Gate.Tests;

// Tests für die Prüfung vor dem Kompilieren (#529) ohne IDE: wann geprüft
// wird, welche Units als geändert gelten, welche Treffer zählen, die Modi warn
// und block, bewusstes Übergehen und das Zeitlimit, alles über die
// Compile-Ereignisse (#527) mit gefälschten Units, Prüfer und Uhr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  Atlas.Core.Build.ReleaseGuard,
  Atlas.Core.Build.Gate;

const
  ProjectFile = 'C:\P\Kasse.dproj';
  MainUnit = 'C:\P\Main.pas';
  DataUnit = 'C:\P\Daten.pas';
  OutcomeNames: array[TAtlasGateOutcome] of string = ('passed', 'reported', 'blocked', 'overridden', 'timedOut');

function Project(AKind: TAtlasCompileKind): TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := ProjectFile;
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
        AProblems := nil;
      Result := True;
    end,
    function(const AProject: TAtlasCompileProject; const AFindings: TAtlasGateFindings; ACheckedUnits: Integer;
      AOutcome: TAtlasGateOutcome; ANotifyTimeout: Boolean): string
    var
      Finding: TAtlasGateFinding;
    begin
      Reported := Reported + OutcomeNames[AOutcome] + ':';
      for Finding in AFindings do
        Reported := Reported + ExtractFileName(Finding.FileName) + '/' + Finding.Problem.Code + ',';
      Reported := Reported + ' ';
      if ANotifyTimeout then
        Inc(Notified);
      Result := Format('%d Fehler', [Length(AFindings)]);
    end,
    function: Int64
    begin
      Result := Clock;
    end));
end;

procedure TAtlasBuildGateTests.AppliesOnlyToUserMakeAndBuild;
var
  Settings: TAtlasGateSettings;
  Info: TAtlasCompileProject;
begin
  Settings := TAtlasGateSettings.Create('warn', 300);
  Assert.IsTrue(TAtlasBuildGateCheck.Applies(Settings, Project(TAtlasCompileKind.Make)));
  Assert.IsTrue(TAtlasBuildGateCheck.Applies(Settings, Project(TAtlasCompileKind.Build)));
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(Settings, Project(TAtlasCompileKind.Check)), 'Syntaxprüfung');
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(Settings, Project(TAtlasCompileKind.Clean)), 'Clean');
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(Settings, Project(TAtlasCompileKind.MakeUnit)), 'eine Unit');
  Info := Project(TAtlasCompileKind.Make);
  Info.Background := True;
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(Settings, Info), 'Hintergrundprüfung #548');
  Info := Project(TAtlasCompileKind.Make);
  Info.RequestedBy := 'mcp';
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(Settings, Info), 'Auftrag von Claude Code #261');
  Assert.IsFalse(TAtlasBuildGateCheck.Applies(TAtlasGateSettings.Create('off', 300), Project(TAtlasCompileKind.Make)),
    'build.gate = off');
end;

procedure TAtlasBuildGateTests.SettingsClampTimeout;
begin
  Assert.AreEqual(TAtlasBuildGateCheck.MinTimeoutMs, TAtlasGateSettings.Create('block', 0).TimeoutMs);
  Assert.AreEqual(TAtlasBuildGateCheck.MaxTimeoutMs, TAtlasGateSettings.Create('block', 999999).TimeoutMs);
  Assert.AreEqual(300, TAtlasGateSettings.Create('block', 300).TimeoutMs);
  Assert.IsTrue(TAtlasGateSettings.Create('BLOCK', 300).Gate = TAtlasBuildGate.Block);
  Assert.IsTrue(TAtlasGateSettings.Create('streng', 300).Gate = TAtlasBuildGate.Off);
end;

procedure TAtlasBuildGateTests.ChangedUnitsByStampOrOutputTime;
var
  Remembered: TDictionary<string, string>;
  Units: TAtlasGateUnits;
  Changed: TArray<string>;
begin
  Units := [UnitOf(MainUnit, 'd:100', 100), UnitOf(DataUnit, 'd:50', 50)];
  // Ohne Ausgabedatei: alles geändert.
  Changed := TAtlasBuildGateCheck.Changed(Units, nil, 0);
  Assert.AreEqual(2, Integer(Length(Changed)));
  // Ausgabedatei von 80: nur Main ist neuer.
  Changed := TAtlasBuildGateCheck.Changed(Units, nil, 80);
  Assert.AreEqual(1, Integer(Length(Changed)));
  Assert.AreEqual(MainUnit, Changed[0]);
  Remembered := TDictionary<string, string>.Create;
  try
    Remembered.Add(UpperCase(MainUnit), 'd:100');
    Remembered.Add(UpperCase(DataUnit), 'd:40');
    // Gemerkter Stand gewinnt über die Zeit: Main gleich, Daten anders (auch wenn älter als die Ausgabe).
    Changed := TAtlasBuildGateCheck.Changed(Units, Remembered, 80);
    Assert.AreEqual(1, Integer(Length(Changed)));
    Assert.AreEqual(DataUnit, Changed[0]);
  finally
    Remembered.Free;
  end;
end;

procedure TAtlasBuildGateTests.OnlyErrorsCount;
var
  Item: TAtlasProblem;
begin
  Assert.IsTrue(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 1)));
  Assert.IsTrue(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Error, 'x', TAtlasProblem.ConfirmedSource,
    1)), 'Atlas-Befund, vom Compiler bestätigt');
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Warning, 'x', 'Atlas', 1)));
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Hint, 'x', 'Atlas', 1)));
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Problem(TAtlasProblemSeverity.Error, 'E2003', 'dcc', 1)),
    'Compilermeldung des vorigen Builds');
  Item := Problem(TAtlasProblemSeverity.Error, 'x', 'Atlas', 1);
  Item.Unnecessary := True;
  Assert.IsFalse(TAtlasBuildGateCheck.Counts(Item), 'inaktiver Bereich');
end;

procedure TAtlasBuildGateTests.BlockStopsCompileOnSyntaxError;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGateRun.Create;
  try
    Run.Units := [UnitOf(MainUnit, 'b:1', 100), UnitOf(DataUnit, 'd:50', 50)];
    Run.OutputTime := 80;
    Run.Problems.Add(UpperCase(MainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
    Events := Run.Make;
    try
      Assert.IsTrue(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason), 'block');
      Assert.AreEqual('Kasse.dproj: 1 Fehler', Reason);
      Assert.AreEqual('blocked:Main.pas/syntax, ', Run.Reported);
      Assert.AreEqual('Main.pas ', Run.Checked, 'nur die geänderte Unit');
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasBuildGateTests.WarnReportsAndCompiles;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGateRun.Create;
  try
    Run.Gate := 'warn';
    Run.Units := [UnitOf(MainUnit, 'b:1', 100)];
    Run.Problems.Add(UpperCase(MainUnit), [Problem(TAtlasProblemSeverity.Error, 'empty-except', 'Atlas', 3)]);
    Events := Run.Make;
    try
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Build), False, Reason), 'warn');
      Assert.AreEqual('', Reason);
      Assert.AreEqual('reported:Main.pas/empty-except, ', Run.Reported);
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasBuildGateTests.WarningNeverBlocks;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGateRun.Create;
  try
    Run.Units := [UnitOf(MainUnit, 'b:1', 100)];
    Run.Problems.Add(UpperCase(MainUnit), [Problem(TAtlasProblemSeverity.Warning, 'empty-except', 'Atlas', 3),
      Problem(TAtlasProblemSeverity.Error, 'E2003', 'dcc', 4)]);
    Events := Run.Make;
    try
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Assert.AreEqual('', Run.Reported, 'nichts zu melden');
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasBuildGateTests.SecondCompileWithinOverrideRuns;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGateRun.Create;
  try
    Run.Units := [UnitOf(MainUnit, 'b:1', 100)];
    Run.Problems.Add(UpperCase(MainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
    Events := Run.Make;
    try
      Assert.IsTrue(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Inc(Run.Clock, 5000);
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason),
        'zweiter Compile binnen 10 s läuft');
      Assert.AreEqual('blocked:Main.pas/syntax, overridden:Main.pas/syntax, ', Run.Reported);
      // Danach wieder block; ebenso nach einer Änderung der Unit.
      Run.Reported := '';
      Inc(Run.Clock, 1000);
      Assert.IsTrue(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Inc(Run.Clock, 1000);
      Run.Units := [UnitOf(MainUnit, 'b:2', 100)];
      Assert.IsTrue(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason), 'Unit geändert');
      // Zu spät: nach mehr als 10 s wieder block.
      Inc(Run.Clock, TAtlasBuildGateCheck.OverrideMs + 1);
      Assert.IsTrue(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason), 'nach 10 s');
      Assert.AreEqual('blocked:Main.pas/syntax, blocked:Main.pas/syntax, blocked:Main.pas/syntax, ', Run.Reported);
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasBuildGateTests.SlowCheckStopsAtTimeout;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
  Before: Int64;
begin
  Run := TGateRun.Create;
  try
    Run.CheckMs := 1000;
    Run.Units := [UnitOf(MainUnit, 'b:1', 100), UnitOf(DataUnit, 'b:2', 100)];
    Run.Problems.Add(UpperCase(MainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
    Events := Run.Make;
    try
      Before := Run.Clock;
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason),
        'Zeitlimit: der Compile läuft ungehindert');
      Assert.IsTrue(Run.Clock - Before <= 300, Format('höchstens 300 ms, waren %d', [Run.Clock - Before]));
      Assert.AreEqual('Main.pas ', Run.Checked, 'nach dem Zeitlimit keine weitere Unit');
      Assert.AreEqual('timedOut: ', Run.Reported);
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasBuildGateTests.TimeoutNotifiedOncePerSession;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGateRun.Create;
  try
    Run.CheckMs := 1000;
    Run.Units := [UnitOf(MainUnit, 'b:1', 100)];
    Events := Run.Make;
    try
      Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason);
      Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason);
      Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason);
      Assert.AreEqual(1, Run.Notified);
      Assert.AreEqual('timedOut: ', Run.Reported, 'ohne Treffer nur das erste Mal gemeldet');
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasBuildGateTests.RemembersStampsOnlyAfterSuccess;
var
  Run: TGateRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGateRun.Create;
  try
    Run.Units := [UnitOf(MainUnit, 'b:1', 100), UnitOf(DataUnit, 'd:50', 100)];
    Events := Run.Make;
    try
      // Gescheitert: nichts gemerkt.
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Events.ProjectStarted(Project(TAtlasCompileKind.Make));
      Events.ProjectFinished(ProjectFile, False);
      Assert.AreEqual('Main.pas Daten.pas ', Run.Checked);
      // Erfolgreich: Stände gemerkt, der nächste Compile prüft nur die geänderte Unit.
      Run.Checked := '';
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Events.ProjectStarted(Project(TAtlasCompileKind.Make));
      Events.ProjectFinished(ProjectFile, True);
      Assert.AreEqual('Main.pas Daten.pas ', Run.Checked);
      Run.Checked := '';
      Run.Units := [UnitOf(MainUnit, 'b:2', 100), UnitOf(DataUnit, 'd:50', 100)];
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Assert.AreEqual('Main.pas ', Run.Checked);
      // Abgebrochen (hier: block): der Stand b:3 gilt nicht als kompiliert.
      Run.Units := [UnitOf(MainUnit, 'b:3', 100), UnitOf(DataUnit, 'd:50', 100)];
      Run.Problems.Add(UpperCase(MainUnit), [Problem(TAtlasProblemSeverity.Error, 'syntax', 'Atlas', 3)]);
      Assert.IsTrue(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Events.ProjectFinished(ProjectFile, True);
      Run.Checked := '';
      Run.Problems.Clear;
      Assert.IsFalse(Events.BeforeCompile(Project(TAtlasCompileKind.Make), False, Reason));
      Assert.AreEqual('Main.pas ', Run.Checked, 'b:3 weiter geändert gegenüber b:2');
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildGateTests);

end.
