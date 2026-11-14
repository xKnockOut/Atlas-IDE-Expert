unit Atlas.Core.BuildPipeline.ReleaseGuard.Tests;

// Tests für den Release-Build-Wächter (#533) mit gefälschten Projektoptionen,
// ohne IDE: Textform der Prüfungen, Release-Konfigurationen, jede Prüfung,
// Leck-Meldung im Projektquelltext, Versionen, Ausgabeordner und der Ablauf
// über die Compile-Ereignisse (#527) mit build.gate (#529).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.BuildPipeline')]
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
  Atlas.Core.Build.PipelineSettings,
  Atlas.Core.BuildPipeline.ReleaseGuard;

const
  cDefaultChecks = 'debugDefine,debugInfo=off,stackFrames=off,assertions=off,rangeChecks=off,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder';
  cCleanSource = 'program Kasse;'#13#10#13#10'uses'#13#10'  Vcl.Forms;'#13#10#13#10'begin'#13#10 +
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
  Result.Source := cCleanSource;
  Result.LastVersion := '1.1.0.0';
end;

function Issues(const AFindings: TAtlasReleaseFindings): string;
var
  mItem: TAtlasReleaseFinding;
begin
  Result := '';
  for mItem in AFindings do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + TAtlasReleaseGuard.cOptionNames[mItem.Issue];
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
  mChecks: TAtlasReleaseChecks;
begin
  Assert.AreEqual(cDefaultChecks, TAtlasReleaseChecks.Defaults.ToText);
  Assert.AreEqual(cDefaultChecks, TAtlasReleaseChecks.Normalized(''));
  mChecks := TAtlasReleaseChecks.Parse(' -Assertions ; rangeChecks=on, unbekannt, -memoryLeaks, debugInfo=true');
  Assert.IsFalse(mChecks.Items[TAtlasReleaseCheck.Assertions].Enabled);
  Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.RangeChecks].Enabled);
  Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.RangeChecks].Expected);
  Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.DebugInfo].Expected);
  Assert.IsFalse(mChecks.Items[TAtlasReleaseCheck.MemoryLeaks].Enabled);
  Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.VersionInfo].Enabled, 'fehlende Namen mit Vorgabe');
  Assert.AreEqual('debugDefine,debugInfo=on,stackFrames=off,-assertions=off,rangeChecks=on,overflowChecks=off,' +
    '-memoryLeaks,versionInfo,outputFolder', mChecks.ToText);
  // Sollwert bleibt auch bei einer abgeschalteten Prüfung erhalten.
  Assert.AreEqual(mChecks.ToText, TAtlasReleaseChecks.Normalized(mChecks.ToText));
  Assert.AreEqual<TAtlasBuildGate>(TAtlasBuildGate.Block, TAtlasBuildPipelineSettings.GateOf(' BLOCK '));
  Assert.AreEqual<TAtlasBuildGate>(TAtlasBuildGate.Warn, TAtlasBuildPipelineSettings.GateOf('warn'));
  Assert.AreEqual<TAtlasBuildGate>(TAtlasBuildGate.Off, TAtlasBuildPipelineSettings.GateOf('irgendwas'));
end;

procedure TAtlasReleaseGuardTests.ReleaseConfigurations;
var
  mValue: TAtlasReleaseSettings;
begin
  mValue := TAtlasReleaseSettings.Create(True, 'off', 'Ship; staging, Ship', cDefaultChecks);
  Assert.AreEqual(2, Integer(Length(mValue.Configurations)));
  Assert.IsTrue(mValue.IsRelease('Release'), 'Release gilt immer');
  Assert.IsTrue(mValue.IsRelease('release'));
  Assert.IsTrue(mValue.IsRelease('SHIP'));
  Assert.IsTrue(mValue.IsRelease('Staging'));
  Assert.IsFalse(mValue.IsRelease('Debug'));
  Assert.IsFalse(mValue.IsRelease(''));
  Assert.AreEqual('Release, Ship', TAtlasBuildPipelineSettings.NormalizedConfigurations('["Release", "Ship"]'));
  Assert.AreEqual('Release', TAtlasBuildPipelineSettings.NormalizedConfigurations(' Release ,, release'));
end;

procedure TAtlasReleaseGuardTests.AppliesOnlyToReleaseBuilds;
var
  mValue: TAtlasReleaseSettings;
  mInfo: TAtlasCompileProject;
begin
  mValue := Settings('off', cDefaultChecks);
  Assert.IsTrue(TAtlasReleaseGuard.Applies(mValue, Project('Release', TAtlasCompileKind.Build)));
  Assert.IsTrue(TAtlasReleaseGuard.Applies(mValue, Project('Release', TAtlasCompileKind.Make)));
  Assert.IsFalse(TAtlasReleaseGuard.Applies(mValue, Project('Debug', TAtlasCompileKind.Build)), 'Debug-Build');
  Assert.IsFalse(TAtlasReleaseGuard.Applies(mValue, Project('Release', TAtlasCompileKind.Check)), 'Syntaxprüfung');
  Assert.IsFalse(TAtlasReleaseGuard.Applies(mValue, Project('Release', TAtlasCompileKind.Clean)), 'Clean');
  mInfo := Project('Release', TAtlasCompileKind.Make);
  mInfo.Background := True;
  Assert.IsFalse(TAtlasReleaseGuard.Applies(mValue, mInfo), 'Hintergrundprüfung #548');
  mInfo.Background := False;
  mInfo.RequestedBy := 'mcp';
  Assert.IsTrue(TAtlasReleaseGuard.Applies(mValue, mInfo), 'Auftrag #261/#764');
  mValue.Enabled := False;
  Assert.IsFalse(TAtlasReleaseGuard.Applies(mValue, Project('Release', TAtlasCompileKind.Build)), 'abgeschaltet');
end;

procedure TAtlasReleaseGuardTests.CleanReleaseHasNoFindings;
begin
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('block', cDefaultChecks), GoodOptions)));
end;

procedure TAtlasReleaseGuardTests.DebugDefineReported;
var
  mOptions: TAtlasReleaseOptions;
  mFindings: TAtlasReleaseFindings;
begin
  mOptions := GoodOptions;
  mOptions.Defines := ['RELEASE', 'debug', 'USE_LOG'];
  mFindings := TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions);
  Assert.AreEqual('DCC_Define', Issues(mFindings));
  Assert.AreEqual('DEBUG', mFindings[0].Value);
  Assert.AreEqual('release-debug-define', TAtlasReleaseGuard.cRuleIds[mFindings[0].Check]);
end;

procedure TAtlasReleaseGuardTests.DisabledCheckReportsNothing;
var
  mOptions: TAtlasReleaseOptions;
begin
  mOptions := GoodOptions;
  mOptions.Defines := ['DEBUG'];
  mOptions.Assertions := 'true';
  Assert.AreEqual('DCC_AssertionsAtRuntime', Issues(TAtlasReleaseGuard.Evaluate(
    Settings('block', '-debugDefine'), mOptions)));
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('block', '-debugDefine,-assertions'), mOptions)));
end;

procedure TAtlasReleaseGuardTests.CompilerOptionsAgainstTargets;
var
  mOptions: TAtlasReleaseOptions;
begin
  mOptions := GoodOptions;
  mOptions.DebugInformation := '2';
  mOptions.DebugInfoInExe := 'true';
  mOptions.StackFrames := 'true';
  mOptions.Assertions := 'true';
  mOptions.RangeChecks := 'true';
  mOptions.OverflowChecks := 'true';
  Assert.AreEqual('DCC_DebugInformation,DCC_DebugInfoInExe,DCC_GenerateStackFrames,DCC_AssertionsAtRuntime,' +
    'DCC_RangeChecking,DCC_IntegerOverflowCheck', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks),
    mOptions)));
  // Sollwert an: Bereichs- und Überlaufprüfung erwünscht, Debug-Informationen auch (dann zählt das Linken nicht).
  Assert.AreEqual('DCC_GenerateStackFrames,DCC_AssertionsAtRuntime', Issues(TAtlasReleaseGuard.Evaluate(
    Settings('off', 'debugInfo=on,rangeChecks=on,overflowChecks=on'), mOptions)));
  mOptions := GoodOptions;
  Assert.AreEqual('DCC_RangeChecking,DCC_IntegerOverflowCheck', Issues(TAtlasReleaseGuard.Evaluate(
    Settings('off', 'rangeChecks=on,overflowChecks=on'), mOptions)), 'Soll an, Option aus');
  mOptions.DebugInformation := '1';
  Assert.AreEqual('DCC_DebugInformation', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks),
    mOptions)), 'begrenzte Debug-Informationen zählen als an');
end;

procedure TAtlasReleaseGuardTests.MissingOptionsUseCompilerDefaults;
var
  mOptions: TAtlasReleaseOptions;
begin
  mOptions := GoodOptions;
  mOptions.DebugInformation := '';
  mOptions.DebugInfoInExe := '';
  mOptions.StackFrames := '';
  mOptions.Assertions := '';
  // $D+ und $C+ sind Vorgabe des Compilers, $W-, $R-, $Q- ebenso.
  Assert.AreEqual('DCC_DebugInformation,DCC_AssertionsAtRuntime',
    Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions)));
  Assert.IsTrue(TAtlasReleaseGuard.IsOn('True', False));
  Assert.IsFalse(TAtlasReleaseGuard.IsOn('0', True));
  Assert.IsTrue(TAtlasReleaseGuard.IsOn('$(Unbekannt)', True));
end;

procedure TAtlasReleaseGuardTests.LeakReportOutsideDebugBlock;
var
  mOptions: TAtlasReleaseOptions;
  mFindings: TAtlasReleaseFindings;
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
  mOptions := GoodOptions;
  mOptions.Source := 'begin'#13#10'  ReportMemoryLeaksOnShutdown := True;'#13#10'end.';
  mFindings := TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions);
  Assert.AreEqual('ReportMemoryLeaksOnShutdown', Issues(mFindings));
  Assert.AreEqual('C:\P\Kasse.dpr', mFindings[0].FileName);
  Assert.AreEqual(2, mFindings[0].Line);
end;

procedure TAtlasReleaseGuardTests.LeakReportGuardedOrHarmless;
begin
  Assert.AreEqual(0, TAtlasReleaseGuard.LeakReportLine(cCleanSource));
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
  mOptions: TAtlasReleaseOptions;
  mFindings: TAtlasReleaseFindings;
begin
  mOptions := GoodOptions;
  Assert.AreEqual('1.2.0.0', TAtlasReleaseGuard.VersionOf(mOptions));
  mOptions.IncludeVersionInfo := 'false';
  Assert.AreEqual('', TAtlasReleaseGuard.VersionOf(mOptions));
  Assert.AreEqual('VerInfo_IncludeVerInfo', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks),
    mOptions)), 'fehlende Versionsinformationen');
  mOptions := GoodOptions;
  mOptions.LastVersion := '1.2.0.0';
  mFindings := TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions);
  Assert.AreEqual('VerInfo_Keys', Issues(mFindings), 'gleiche Version wie beim letzten Release-Build');
  Assert.AreEqual('1.2.0.0', mFindings[0].Value);
  mOptions.AutoIncrementVersion := 'true';
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions)),
    'Build-Nummer automatisch erhöht');
  // Ohne FileVersion bzw. mit Makro: Einzelwerte, fehlende mit Vorgabe 1.0.0.0.
  mOptions := GoodOptions;
  mOptions.VersionKeys := 'FileVersion=$(MajorVer).$(MinorVer)';
  mOptions.MinorVersion := '4';
  mOptions.BuildVersion := '17';
  Assert.AreEqual('1.4.0.17', TAtlasReleaseGuard.VersionOf(mOptions));
  mOptions.VersionKeys := 'FileVersion=0.0.0.0';
  Assert.AreEqual('VerInfo_IncludeVerInfo', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks),
    mOptions)), 'Version 0.0.0.0 gilt als fehlend');
end;

procedure TAtlasReleaseGuardTests.OutputFolderSameAsDebug;
var
  mOptions: TAtlasReleaseOptions;
  mFindings: TAtlasReleaseFindings;
begin
  Assert.AreEqual('Win64\Release', TAtlasReleaseGuard.ResolveFolder('.\$(platform)\$(CONFIG)\', 'Release', 'Win64'));
  Assert.AreEqual('.', TAtlasReleaseGuard.ResolveFolder(' .\ ', 'Release', 'Win64'));
  mOptions := GoodOptions;
  mOptions.OutputFolder := 'Bin\$(Platform)';
  mOptions.DebugOutputFolder := '.\bin\Win64\';
  mFindings := TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions);
  Assert.AreEqual('DCC_ExeOutput', Issues(mFindings));
  Assert.AreEqual('Bin\Win64', mFindings[0].Value);
  mOptions.OutputFolder := '';
  mOptions.DebugOutputFolder := '';
  Assert.AreEqual('DCC_ExeOutput', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions)),
    'beide im Projektordner');
  mOptions.HasDebugConfiguration := False;
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions)),
    'ohne Konfiguration Debug');
end;

procedure TAtlasReleaseGuardTests.PackagesSkipSourceAndOutput;
var
  mOptions: TAtlasReleaseOptions;
begin
  mOptions := GoodOptions;
  mOptions.IsPackage := True;
  mOptions.Source := 'package P;'#10'begin ReportMemoryLeaksOnShutdown := True; end.';
  mOptions.OutputFolder := '';
  mOptions.DebugOutputFolder := '';
  Assert.AreEqual('', Issues(TAtlasReleaseGuard.Evaluate(Settings('off', cDefaultChecks), mOptions)));
end;

const
  cOutcomeNames: array[TAtlasReleaseOutcome] of string = ('passed', 'reported', 'blocked', 'overridden');

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
      Result := Settings(Gate, cDefaultChecks);
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
      Reported := Reported + cOutcomeNames[AOutcome] + ':' + Issues(AFindings) + ' ';
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
  mRun: TGuardRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGuardRun.Create;
  try
    mRun.Options := GoodOptions;
    mRun.Options.Defines := ['DEBUG'];
    mRun.Gate := 'block';
    mEvents := mRun.Make;
    try
      Assert.IsTrue(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason),
        'block: der Build startet nicht');
      Assert.AreEqual('Kasse.dproj: 1 Verstöße', mReason);
      Assert.AreEqual('blocked:DCC_Define ', mRun.Reported);
      mRun.Reported := '';
      mRun.Gate := 'warn';
      mRun.Clock := 60000;
      Assert.IsFalse(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason));
      mRun.Gate := 'off';
      Assert.IsFalse(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason));
      Assert.AreEqual('reported:DCC_Define reported:DCC_Define ', mRun.Reported, 'warn und off melden nur');
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasReleaseGuardTests.SecondBuildWithinOverrideRuns;
var
  mRun: TGuardRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGuardRun.Create;
  try
    mRun.Options := GoodOptions;
    mRun.Options.Defines := ['DEBUG'];
    mRun.Gate := 'block';
    mRun.Clock := 1000;
    mEvents := mRun.Make;
    try
      Assert.IsTrue(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason));
      mRun.Clock := 1000 + TAtlasReleaseGuard.cOverrideMs;
      Assert.IsFalse(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason),
        'zweiter Build binnen 10 s');
      // Danach gilt wieder block, ebenso nach Ablauf der Frist oder mit anderen Verstößen.
      Assert.IsTrue(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason));
      mRun.Clock := mRun.Clock + TAtlasReleaseGuard.cOverrideMs + 1;
      Assert.IsTrue(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason), 'Frist um');
      mRun.Options.Assertions := 'true';
      Assert.IsTrue(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason),
        'andere Verstöße');
      Assert.AreEqual('blocked:DCC_Define overridden:DCC_Define blocked:DCC_Define blocked:DCC_Define ' +
        'blocked:DCC_Define,DCC_AssertionsAtRuntime ', mRun.Reported);
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasReleaseGuardTests.RemembersVersionAfterSuccess;
var
  mRun: TGuardRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGuardRun.Create;
  try
    mRun.Options := GoodOptions;
    mRun.Gate := 'block';
    mEvents := mRun.Make;
    try
      Assert.IsFalse(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason));
      mEvents.ProjectStarted(Project('Release', TAtlasCompileKind.Build));
      mEvents.ProjectFinished('C:\P\Kasse.dproj', False);
      Assert.AreEqual('', mRun.Remembered, 'fehlgeschlagener Build');
      Assert.IsFalse(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Build), False, mReason));
      mEvents.ProjectStarted(Project('Release', TAtlasCompileKind.Build));
      mEvents.ProjectFinished('C:\P\Kasse.dproj', True);
      Assert.AreEqual('Release/Win64=1.2.0.0 ', mRun.Remembered);
      Assert.AreEqual('passed: passed: ', mRun.Reported);
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

procedure TAtlasReleaseGuardTests.DebugBuildIsNotRead;
var
  mRun: TGuardRun;
  mEvents: TAtlasCompileEvents;
  mReason: string;
begin
  mRun := TGuardRun.Create;
  try
    mRun.Options := GoodOptions;
    mRun.Options.Defines := ['DEBUG'];
    mRun.Gate := 'block';
    mEvents := mRun.Make;
    try
      Assert.IsFalse(mEvents.BeforeCompile(Project('Debug', TAtlasCompileKind.Build), False, mReason));
      mEvents.ProjectStarted(Project('Debug', TAtlasCompileKind.Build));
      mEvents.ProjectFinished('C:\P\Kasse.dproj', True);
      // Hintergrundprüfung (#548): Events.Background gilt schon vor dem Compile.
      mEvents.Background := True;
      Assert.IsFalse(mEvents.BeforeCompile(Project('Release', TAtlasCompileKind.Make), False, mReason));
      mEvents.Background := False;
      Assert.AreEqual(0, mRun.Reads, 'keine Optionen gelesen');
      Assert.AreEqual('', mRun.Reported);
      Assert.AreEqual('', mRun.Remembered);
    finally
      mEvents.Free;
    end;
  finally
    mRun.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReleaseGuardTests);

end.
