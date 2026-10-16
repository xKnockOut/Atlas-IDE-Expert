unit Atlas.Core.Build.ReleaseGuard.Tests;

// Tests für den Release-Build-Wächter (#533) mit gefälschten Projektoptionen,
// ohne IDE: Textform der Prüfungen, Release-Konfigurationen, jede Prüfung,
// Leck-Meldung im Projektquelltext, Versionen, Ausgabeordner und der Ablauf
// über die Compile-Ereignisse (#527) mit build.gate (#529).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasReleaseGuardTests = class
  public
    [Test]
    procedure ChecksTextDefaultsAndParse;
    [Test]
    procedure ReleaseConfigurations;
    /// <summary>Debug-Build, Syntaxprüfung, Clean und Hintergrundprüfung: keine Prüfung.</summary>
    [Test]
    procedure AppliesOnlyToReleaseBuilds;
    [Test]
    procedure CleanReleaseHasNoFindings;
    [Test]
    procedure DebugDefineReported;
    [Test]
    procedure DisabledCheckReportsNothing;
    [Test]
    procedure CompilerOptionsAgainstTargets;
    [Test]
    procedure MissingOptionsUseCompilerDefaults;
    [Test]
    procedure LeakReportOutsideDebugBlock;
    [Test]
    procedure LeakReportGuardedOrHarmless;
    [Test]
    procedure VersionMissingOrUnchanged;
    [Test]
    procedure OutputFolderSameAsDebug;
    [Test]
    procedure PackagesSkipSourceAndOutput;
    /// <summary>build.gate = block: derselbe Build startet nicht; warn und off melden nur.</summary>
    [Test]
    procedure GateBlocksBuild;
    /// <summary>Zweiter Build mit denselben Verstößen binnen 10 s läuft (bewusst übergangen).</summary>
    [Test]
    procedure SecondBuildWithinOverrideRuns;
    [Test]
    procedure RemembersVersionAfterSuccess;
    [Test]
    procedure DebugBuildIsNotRead;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.ReleaseGuard;

const
  DefaultChecks = 'debugDefine,debugInfo=off,stackFrames=off,assertions=off,rangeChecks=off,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder';
  CleanSource = 'program Kasse;'#13#10#13#10'uses'#13#10'  Vcl.Forms;'#13#10#13#10'begin'#13#10 +
    '  Application.Initialize;'#13#10'  Application.Run;'#13#10'end.'#13#10;

function Settings(const AGate, AChecks: string): TAtlasReleaseSettings;
begin
  Result := TAtlasReleaseSettings.Create(True, AGate, 'Release', AChecks);
end;

/// <summary>Optionen eines sauberen Release-Builds.</summary>
function GoodOptions: TAtlasReleaseOptions;
begin
  Result := Default(TAtlasReleaseOptions);
  Result.Project := 'C:\P\Kasse.dproj';
  Result.Configuration := 'Release';
  Result.Platform := 'Win64';
  Result.Defines := ['RELEASE'];
  Result.DebugInformation := '0';
  Result.DebugInfoInExe := 'false';
  Result.StackFrames := 'false';
  Result.Assertions := 'false';
  Result.IncludeVersionInfo := 'true';
  Result.VersionKeys := 'CompanyName=Firma;FileVersion=1.2.0.0;ProductVersion=1.2';
  Result.OutputFolder := '.\$(Platform)\$(Config)';
  Result.HasDebugConfiguration := True;
  Result.DebugOutputFolder := '.\$(Platform)\$(Config)';
  Result.SourceFile := 'C:\P\Kasse.dpr';
  Result.Source := CleanSource;
  Result.LastVersion := '1.1.0.0';
end;

function Issues(const AFindings: TAtlasReleaseFindings): string;
var
  Item: TAtlasReleaseFinding;
begin
  Result := '';
  for Item in AFindings do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + TAtlasReleaseGuard.OptionNames[Item.Issue];
  end;
end;

function Project(const AConfiguration: string; AKind: TAtlasCompileKind): TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := 'C:\P\Kasse.dproj';
  Result.Kind := AKind;
  Result.Configuration := AConfiguration;
  Result.Platform := 'Win64';
end;

procedure TAtlasReleaseGuardTests.ChecksTextDefaultsAndParse;
var
  Checks: TAtlasReleaseChecks;
begin
  Assert.AreEqual(DefaultChecks, TAtlasReleaseChecks.Defaults.ToText);
  Assert.AreEqual(DefaultChecks, TAtlasReleaseChecks.Normalized(''));
  Checks := TAtlasReleaseChecks.Parse(' -Assertions ; rangeChecks=on, unbekannt, -memoryLeaks, debugInfo=true');
  Assert.IsFalse(Checks.Items[TAtlasReleaseCheck.Assertions].Enabled);
  Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.RangeChecks].Enabled);
  Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.RangeChecks].Expected);
  Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.DebugInfo].Expected);
  Assert.IsFalse(Checks.Items[TAtlasReleaseCheck.MemoryLeaks].Enabled);
  Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.VersionInfo].Enabled, 'fehlende Namen mit Vorgabe');
  Assert.AreEqual('debugDefine,debugInfo=on,stackFrames=off,-assertions=off,rangeChecks=on,overflowChecks=off,' +
    '-memoryLeaks,versionInfo,outputFolder', Checks.ToText);
  // Sollwert bleibt auch bei einer abgeschalteten Prüfung erhalten.
  Assert.AreEqual(Checks.ToText, TAtlasReleaseChecks.Normalized(Checks.ToText));
  Assert.IsTrue(TAtlasReleaseGuard.GateOf(' BLOCK ') = TAtlasBuildGate.Block);
  Assert.IsTrue(TAtlasReleaseGuard.GateOf('warn') = TAtlasBuildGate.Warn);
  Assert.IsTrue(TAtlasReleaseGuard.GateOf('irgendwas') = TAtlasBuildGate.Off);
end;

procedure TAtlasReleaseGuardTests.ReleaseConfigurations;
var
  Value: TAtlasReleaseSettings;
begin
  Value := TAtlasReleaseSettings.Create(True, 'off', 'Ship; staging, Ship', DefaultChecks);
  Assert.AreEqual(2, Integer(Length(Value.Configurations)));
  Assert.IsTrue(Value.IsRelease('Release'), 'Release gilt immer');
  Assert.IsTrue(Value.IsRelease('release'));
  Assert.IsTrue(Value.IsRelease('SHIP'));
  Assert.IsTrue(Value.IsRelease('Staging'));
  Assert.IsFalse(Value.IsRelease('Debug'));
  Assert.IsFalse(Value.IsRelease(''));
  Assert.AreEqual('Release, Ship', TAtlasReleaseGuard.NormalizedConfigurations('["Release", "Ship"]'));
  Assert.AreEqual('Release', TAtlasReleaseGuard.NormalizedConfigurations(' Release ,, release'));
end;

procedure TAtlasReleaseGuardTests.AppliesOnlyToReleaseBuilds;
var
  Value: TAtlasReleaseSettings;
  Info: TAtlasCompileProject;
begin
  Value := Settings('off', DefaultChecks);
  Assert.IsTrue(TAtlasReleaseGuard.Applies(Value, Project('Release', TAtlasCompileKind.Build)));
  Assert.IsTrue(TAtlasReleaseGuard.Applies(Value, Project('Release', TAtlasCompileKind.Make)));
  Assert.IsFalse(TAtlasReleaseGuard.Applies(Value, Project('Debug', TAtlasCompileKind.Build)), 'Debug-Build');
  Assert.IsFalse(TAtlasReleaseGuard.Applies(Value, Project('Release', TAtlasCompileKind.Check)), 'Syntaxprüfung');
  Assert.IsFalse(TAtlasReleaseGuard.Applies(Value, Project('Release', TAtlasCompileKind.Clean)), 'Clean');
  Info := Project('Release', TAtlasCompileKind.Make);
  Info.Background := True;
  Assert.IsFalse(TAtlasReleaseGuard.Applies(Value, Info), 'Hintergrundprüfung #548');
  Info.Background := False;
  Info.RequestedBy := 'mcp';
  Assert.IsTrue(TAtlasReleaseGuard.Applies(Value, Info), 'Auftrag #261/#764');
  Value.Enabled := False;
  Assert.IsFalse(TAtlasReleaseGuard.Applies(Value, Project('Release', TAtlasCompileKind.Build)), 'abgeschaltet');
end;

procedure TAtlasReleaseGuardTests.CleanReleaseHasNoFindings;
begin
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('block', DefaultChecks), GoodOptions)));
end;

procedure TAtlasReleaseGuardTests.DebugDefineReported;
var
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
begin
  Options := GoodOptions;
  Options.Defines := ['RELEASE', 'debug', 'USE_LOG'];
  Findings := TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options);
  Assert.AreEqual('DCC_Define', Issues(Findings));
  Assert.AreEqual('DEBUG', Findings[0].Value);
  Assert.AreEqual('release-debug-define', TAtlasReleaseGuard.RuleIds[Findings[0].Check]);
end;

procedure TAtlasReleaseGuardTests.DisabledCheckReportsNothing;
var
  Options: TAtlasReleaseOptions;
begin
  Options := GoodOptions;
  Options.Defines := ['DEBUG'];
  Options.Assertions := 'true';
  Assert.AreEqual('DCC_AssertionsAtRuntime', Issues(TAtlasReleaseGuard.Evaluate(
    Settings('block', '-debugDefine'), Options)));
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('block', '-debugDefine,-assertions'), Options)));
end;

procedure TAtlasReleaseGuardTests.CompilerOptionsAgainstTargets;
var
  Options: TAtlasReleaseOptions;
begin
  Options := GoodOptions;
  Options.DebugInformation := '2';
  Options.DebugInfoInExe := 'true';
  Options.StackFrames := 'true';
  Options.Assertions := 'true';
  Options.RangeChecks := 'true';
  Options.OverflowChecks := 'true';
  Assert.AreEqual('DCC_DebugInformation,DCC_DebugInfoInExe,DCC_GenerateStackFrames,DCC_AssertionsAtRuntime,' +
    'DCC_RangeChecking,DCC_IntegerOverflowCheck', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks),
    Options)));
  // Sollwert an: Bereichs- und Überlaufprüfung erwünscht, Debug-Informationen auch (dann zählt das Linken nicht).
  Assert.AreEqual('DCC_GenerateStackFrames,DCC_AssertionsAtRuntime', Issues(TAtlasReleaseGuard.Evaluate(
    Settings('off', 'debugInfo=on,rangeChecks=on,overflowChecks=on'), Options)));
  Options := GoodOptions;
  Assert.AreEqual('DCC_RangeChecking,DCC_IntegerOverflowCheck', Issues(TAtlasReleaseGuard.Evaluate(
    Settings('off', 'rangeChecks=on,overflowChecks=on'), Options)), 'Soll an, Option aus');
  Options.DebugInformation := '1';
  Assert.AreEqual('DCC_DebugInformation', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks),
    Options)), 'begrenzte Debug-Informationen zählen als an');
end;

procedure TAtlasReleaseGuardTests.MissingOptionsUseCompilerDefaults;
var
  Options: TAtlasReleaseOptions;
begin
  Options := GoodOptions;
  Options.DebugInformation := '';
  Options.DebugInfoInExe := '';
  Options.StackFrames := '';
  Options.Assertions := '';
  // $D+ und $C+ sind Vorgabe des Compilers, $W-, $R-, $Q- ebenso.
  Assert.AreEqual('DCC_DebugInformation,DCC_AssertionsAtRuntime',
    Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options)));
  Assert.IsTrue(TAtlasReleaseGuard.IsOn('True', False));
  Assert.IsFalse(TAtlasReleaseGuard.IsOn('0', True));
  Assert.IsTrue(TAtlasReleaseGuard.IsOn('$(Unbekannt)', True));
end;

procedure TAtlasReleaseGuardTests.LeakReportOutsideDebugBlock;
var
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
begin
  Assert.AreEqual(3, TAtlasReleaseGuard.LeakReportLine(
    'program Kasse;'#13#10'begin'#13#10'  ReportMemoryLeaksOnShutdown := True;'#13#10'end.'));
  // Im Zweig von {$IFNDEF DEBUG} bzw. nach {$ENDIF} gilt es auch im Release.
  Assert.AreEqual(4, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'{$IFNDEF DEBUG}'#10'{ Kommentar'#10'}System.ReportMemoryLeaksOnShutdown:=true;'#10'{$ENDIF}'#10'end.'));
  Assert.AreEqual(5, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'{$IFDEF DEBUG}'#10'  X := 1;'#10'{$ENDIF}'#10'  ReportMemoryLeaksOnShutdown := True;'#10'end.'));
  Assert.AreEqual(4, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'{$IFDEF DEBUG}'#10'{$ELSE}'#10'  ReportMemoryLeaksOnShutdown := True;'#10'{$ENDIF}'#10'end.'));
  Options := GoodOptions;
  Options.Source := 'begin'#13#10'  ReportMemoryLeaksOnShutdown := True;'#13#10'end.';
  Findings := TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options);
  Assert.AreEqual('ReportMemoryLeaksOnShutdown', Issues(Findings));
  Assert.AreEqual('C:\P\Kasse.dpr', Findings[0].FileName);
  Assert.AreEqual(2, Findings[0].Line);
end;

procedure TAtlasReleaseGuardTests.LeakReportGuardedOrHarmless;
begin
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(CleanSource));
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'  {$IFDEF DEBUG}'#10'  ReportMemoryLeaksOnShutdown := True;'#10'  {$ENDIF}'#10'end.'));
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'{$IF Defined(Debug) and (CompilerVersion > 30)}'#10'ReportMemoryLeaksOnShutdown := True;'#10 +
    '{$IFEND}'#10'end.'));
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'{$IFNDEF DEBUG}'#10'{$ELSE}'#10'ReportMemoryLeaksOnShutdown := True;'#10'{$ENDIF}'#10'end.'));
  // Verschachtelt in einem anderen Block innerhalb von DEBUG.
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(
    '{$IFDEF DEBUG}'#10'{$IFDEF WIN64}'#10'ReportMemoryLeaksOnShutdown := True;'#10'{$ENDIF}'#10'{$ENDIF}'));
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(
    'begin'#10'  // ReportMemoryLeaksOnShutdown := True;'#10'  { ReportMemoryLeaksOnShutdown := True }'#10 +
    '  (* ReportMemoryLeaksOnShutdown := True *)'#10'  S := ''ReportMemoryLeaksOnShutdown := True'';'#10 +
    '  ReportMemoryLeaksOnShutdown := DebugHook <> 0;'#10'  ReportMemoryLeaksOnShutdown := False;'#10'end.'));
end;

procedure TAtlasReleaseGuardTests.VersionMissingOrUnchanged;
var
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
begin
  Options := GoodOptions;
  Assert.AreEqual('1.2.0.0', TAtlasReleaseGuard.VersionOf(Options));
  Options.IncludeVersionInfo := 'false';
  Assert.AreEqual('', TAtlasReleaseGuard.VersionOf(Options));
  Assert.AreEqual('VerInfo_IncludeVerInfo', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks),
    Options)), 'fehlende Versionsinformationen');
  Options := GoodOptions;
  Options.LastVersion := '1.2.0.0';
  Findings := TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options);
  Assert.AreEqual('VerInfo_Keys', Issues(Findings), 'gleiche Version wie beim letzten Release-Build');
  Assert.AreEqual('1.2.0.0', Findings[0].Value);
  Options.AutoIncrementVersion := 'true';
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options)),
    'Build-Nummer automatisch erhöht');
  // Ohne FileVersion bzw. mit Makro: Einzelwerte, fehlende mit Vorgabe 1.0.0.0.
  Options := GoodOptions;
  Options.VersionKeys := 'FileVersion=$(MajorVer).$(MinorVer)';
  Options.MinorVersion := '4';
  Options.BuildVersion := '17';
  Assert.AreEqual('1.4.0.17', TAtlasReleaseGuard.VersionOf(Options));
  Options.VersionKeys := 'FileVersion=0.0.0.0';
  Assert.AreEqual('VerInfo_IncludeVerInfo', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks),
    Options)), 'Version 0.0.0.0 gilt als fehlend');
end;

procedure TAtlasReleaseGuardTests.OutputFolderSameAsDebug;
var
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
begin
  Assert.AreEqual('Win64\Release', TAtlasReleaseGuard.ResolveFolder('.\$(platform)\$(CONFIG)\', 'Release', 'Win64'));
  Assert.AreEqual('.', TAtlasReleaseGuard.ResolveFolder(' .\ ', 'Release', 'Win64'));
  Options := GoodOptions;
  Options.OutputFolder := 'Bin\$(Platform)';
  Options.DebugOutputFolder := '.\bin\Win64\';
  Findings := TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options);
  Assert.AreEqual('DCC_ExeOutput', Issues(Findings));
  Assert.AreEqual('Bin\Win64', Findings[0].Value);
  Options.OutputFolder := '';
  Options.DebugOutputFolder := '';
  Assert.AreEqual('DCC_ExeOutput', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options)),
    'beide im Projektordner');
  Options.HasDebugConfiguration := False;
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options)),
    'ohne Konfiguration Debug');
end;

procedure TAtlasReleaseGuardTests.PackagesSkipSourceAndOutput;
var
  Options: TAtlasReleaseOptions;
begin
  Options := GoodOptions;
  Options.IsPackage := True;
  Options.Source := 'package P;'#10'begin ReportMemoryLeaksOnShutdown := True; end.';
  Options.OutputFolder := '';
  Options.DebugOutputFolder := '';
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', DefaultChecks), Options)));
end;

const
  OutcomeNames: array[TAtlasReleaseOutcome] of string = ('passed', 'reported', 'blocked', 'overridden');

type
  TGuardRun = class
  public
    Options: TAtlasReleaseOptions;
    Gate: string;
    Reported: string;
    Remembered: string;
    Reads: Integer;
    Clock: Int64;
    function Make: TAtlasCompileEvents;
  end;

function TGuardRun.Make: TAtlasCompileEvents;
begin
  Result := TAtlasCompileEvents.Create(
    function: Int64
    begin
      Result := Clock;
    end);
  Result.Add(TAtlasReleaseGuardParticipant.Create(
    function: TAtlasReleaseSettings
    begin
      Result := Settings(Gate, DefaultChecks);
    end,
    function(const AProject: TAtlasCompileProject; out AOptions: TAtlasReleaseOptions): Boolean
    begin
      Inc(Reads);
      AOptions := Options;
      Result := True;
    end,
    function(const AOptions: TAtlasReleaseOptions; const AFindings: TAtlasReleaseFindings;
      AOutcome: TAtlasReleaseOutcome): string
    begin
      Reported := Reported + OutcomeNames[AOutcome] + ':' + Issues(AFindings) + ' ';
      Result := Format('%d Verstöße', [Length(AFindings)]);
    end,
    procedure(const AOptions: TAtlasReleaseOptions; const AVersion: string)
    begin
      Remembered := Remembered + AOptions.Configuration + '/' + AOptions.Platform + '=' + AVersion + ' ';
    end,
    function: Int64
    begin
      Result := Clock;
    end));
end;

procedure TAtlasReleaseGuardTests.GateBlocksBuild;
var
  Run: TGuardRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGuardRun.Create;
  try
    Run.Options := GoodOptions;
    Run.Options.Defines := ['DEBUG'];
    Run.Gate := 'block';
    Events := Run.Make;
    try
      Assert.IsTrue(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason),
        'block: der Build startet nicht');
      Assert.AreEqual('Kasse.dproj: 1 Verstöße', Reason);
      Assert.AreEqual('blocked:DCC_Define ', Run.Reported);
      Run.Reported := '';
      Run.Gate := 'warn';
      Run.Clock := 60000;
      Assert.IsFalse(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason));
      Run.Gate := 'off';
      Assert.IsFalse(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason));
      Assert.AreEqual('reported:DCC_Define reported:DCC_Define ', Run.Reported, 'warn und off melden nur');
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasReleaseGuardTests.SecondBuildWithinOverrideRuns;
var
  Run: TGuardRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGuardRun.Create;
  try
    Run.Options := GoodOptions;
    Run.Options.Defines := ['DEBUG'];
    Run.Gate := 'block';
    Run.Clock := 1000;
    Events := Run.Make;
    try
      Assert.IsTrue(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason));
      Run.Clock := 1000 + TAtlasReleaseGuard.OverrideMs;
      Assert.IsFalse(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason),
        'zweiter Build binnen 10 s');
      // Danach gilt wieder block, ebenso nach Ablauf der Frist oder mit anderen Verstößen.
      Assert.IsTrue(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason));
      Run.Clock := Run.Clock + TAtlasReleaseGuard.OverrideMs + 1;
      Assert.IsTrue(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason), 'Frist um');
      Run.Options.Assertions := 'true';
      Assert.IsTrue(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason),
        'andere Verstöße');
      Assert.AreEqual('blocked:DCC_Define overridden:DCC_Define blocked:DCC_Define blocked:DCC_Define ' +
        'blocked:DCC_Define,DCC_AssertionsAtRuntime ', Run.Reported);
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasReleaseGuardTests.RemembersVersionAfterSuccess;
var
  Run: TGuardRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGuardRun.Create;
  try
    Run.Options := GoodOptions;
    Run.Gate := 'block';
    Events := Run.Make;
    try
      Assert.IsFalse(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason));
      Events.ProjectStarted(Project('Release', TAtlasCompileKind.Build));
      Events.ProjectFinished('C:\P\Kasse.dproj', False);
      Assert.AreEqual('', Run.Remembered, 'fehlgeschlagener Build');
      Assert.IsFalse(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, Reason));
      Events.ProjectStarted(Project('Release', TAtlasCompileKind.Build));
      Events.ProjectFinished('C:\P\Kasse.dproj', True);
      Assert.AreEqual('Release/Win64=1.2.0.0 ', Run.Remembered);
      Assert.AreEqual('passed: passed: ', Run.Reported);
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

procedure TAtlasReleaseGuardTests.DebugBuildIsNotRead;
var
  Run: TGuardRun;
  Events: TAtlasCompileEvents;
  Reason: string;
begin
  Run := TGuardRun.Create;
  try
    Run.Options := GoodOptions;
    Run.Options.Defines := ['DEBUG'];
    Run.Gate := 'block';
    Events := Run.Make;
    try
      Assert.IsFalse(Events.BeforeCompile(Project('Debug', TAtlasCompileKind.Build), False, Reason));
      Events.ProjectStarted(Project('Debug', TAtlasCompileKind.Build));
      Events.ProjectFinished('C:\P\Kasse.dproj', True);
      // Hintergrundprüfung (#548): Events.Background gilt schon vor dem Compile.
      Events.Background := True;
      Assert.IsFalse(Events.BeforeCompile(Project('Release', TAtlasCompileKind.Make), False, Reason));
      Events.Background := False;
      Assert.AreEqual(0, Run.Reads, 'keine Optionen gelesen');
      Assert.AreEqual('', Run.Reported);
      Assert.AreEqual('', Run.Remembered);
    finally
      Events.Free;
    end;
  finally
    Run.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReleaseGuardTests);

end.
