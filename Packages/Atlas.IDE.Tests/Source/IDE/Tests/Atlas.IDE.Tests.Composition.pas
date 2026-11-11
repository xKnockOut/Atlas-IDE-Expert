unit Atlas.IDE.Tests.Composition;

// Modul Tests (#1455, ADR 0017): einzige Unit, die den Testläufer für DUnitX
// (#69), „Test am Cursor ausführen bzw. debuggen“ (#585), die Code Lens der
// Tests und „Betroffene Tests ausführen“ (#1353) erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.tests“ (Modulschalter tests, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - den Teil Tests der Feature-Tabelle,
// - Befehle (Palette), den Eintrag „Betroffene Tests ausführen“ im
//   Atlas-Menü, „Test ausführen“/„Test debuggen“ im Kontextmenü und „Tests
//   dieser Unit ausführen“ im Kontextmenü der Projektverwaltung (#1817:
//   Testunits der gewählten Units nach Namen in der Projektgruppe, nur solche
//   mit Fixtures; ohne eine meldet das Modul es in der Meldungsansicht),
// - Hörer für Einstellungen und bewertete Builds (Tests nach dem Build),
// - IAtlasTestRunner (Base: Auswirkungsanalyse #1120, Willkommensseite) und
//   IAtlasTestsSource (Atlas.IDE.Contracts.Tests, Willkommensseite); das Ende eines
//   Laufs schreibt das Modul in die Projekt-Zusammenfassung von Base
//   (TAtlasIdeProjectSummaries, #69) und meldet es jedem IAtlasTestsListener.
// Gebaut wird über den Läufer der Builds auf Auftrag der Build-Pipeline
// (IAtlasBuildJobs aus Atlas.IDE.Contracts.BuildPipeline, ohne Modul nicht), die
// Probleme gehen an das Problemfenster von Base; die fehlgeschlagenen Tests des
// letzten Laufs liest das Modul aus den Projektdateien (TAtlasProjectSummaries),
// auch ohne Willkommensseite.
// Diese Haken stehen in Atlas.IDE.Tests.Composition.Hooks.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.IDE.Contracts.Tests;

type
  TAtlasTestsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasBuildVerdictListener, IAtlasTestRunner, IAtlasTestsSource)
  public const
    cModuleId = 'atlas.tests';
    cSwitch = 'tests';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    procedure RunTests(const AFileName: string; const ATests: TArray<string>);
    function RunProject(const ATestProject: string; out AReason: string): Boolean;
    function DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
    function LocateByName(const AProject, AFullName: string; out AFileName: string; out ALine: Integer): Boolean;
    function Busy: Boolean;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Tests.SettingsSection,
  ToolsAPI,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Adapters.ProcessRunner,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.UnitMatch,
  Atlas.Core.Commands.ProjectSelection,
  Atlas.Text.DUnitX,
  Atlas.IDE.Problems.Files,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.CodeInsight.Manager.Paths,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Composition.Hooks,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Lens,
  Atlas.IDE.Tests.Affected,
  Atlas.UI.Strings,
  Atlas.UI.Tests.Strings;

var
  GScope: IAtlasModuleScope;
  GTests: TAtlasIdeTests;
  GDebugger: TAtlasIdeTestDebugger;
  GLens: TAtlasIdeTestsLens;

{ Sichtbarkeit }

function TestsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and (GTests <> nil);
end;

function AffectedTestsVisible: Boolean;
begin
  Result := TAtlasIdeAffectedTests.Enabled and (GTests <> nil);
end;

function TestDebugVisible: Boolean;
begin
  Result := TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) and (GDebugger <> nil);
end;

{ Läufer }

/// <summary>Prozessläufer der Versionsverwaltung für das Testprogramm; eigene Routine, damit die Referenz nichts aus
/// StartTests einfängt.</summary>
function TestsProcess: TAtlasTestsRunnerFactory;
begin
  Result :=
    function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner
    begin
      Result := TAtlasVcsProcessRunner.Create(False, ACancelled);
    end;
end;

procedure RunAtCursor;
begin
  if GDebugger <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GDebugger.RunAtCursor);
  end;
end;

procedure DebugAtCursor;
begin
  if GDebugger <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GDebugger.DebugAtCursor);
  end;
end;

{ Betroffene Tests (#1353) }

procedure AffectedRunTests(const AFileName: string; const ATests: TArray<string>);
begin
  if GTests <> nil then
  begin
    GTests.RunTests(AFileName, ATests);
  end;
end;

procedure AffectedRunAll;
begin
  if GTests <> nil then
  begin
    GTests.RunAll;
  end;
end;

procedure AffectedResolveTarget(const AThen: TAtlasAffectedTargetProc);
var
  mThen: TAtlasAffectedTargetProc;
begin
  if GTests = nil then
  begin
    Exit;
  end;
  mThen := AThen;
  GTests.ResolveProject('',
    procedure(const AProject: IOTAProject)
    begin
      mThen(TAtlasIdeTests.TargetOf(AProject, nil));
    end);
end;

function ServerPath: string;
var
  mArguments: string;
begin
  Result := TAtlasCodeInsightPaths.ServerPath(mArguments);
end;

function AffectedHooks: TAtlasAffectedTestsHooks;
begin
  Result := Default(TAtlasAffectedTestsHooks);
  Result.RunTests := AffectedRunTests;
  Result.RunAll := AffectedRunAll;
  Result.ResolveTarget := AffectedResolveTarget;
  Result.ServerPath := ServerPath;
end;

{ Teil Tests }

procedure StartTests;
begin
  GTests := TAtlasIdeTests.Create(TestsProcess());
  GTests.OnBuild := BuildForTests;
  GTests.OnProblems := ShowProblems;
  GTests.OnFinished := AnnounceTests;
  GTests.OnLastFailed := LastFailed;
  // Einzelner Test ausführen bzw. debuggen (#585), auch aus dem Kontextmenü und der Lens.
  GDebugger := TAtlasIdeTestDebugger.Create(GTests);
  GLens := TAtlasIdeTestsLens.Create(GTests, GDebugger);
  TAtlasIdeAffectedTests.Install(AffectedHooks);
end;

procedure StopTests;
begin
  // tests.run aus (oder Modul aus): pre-commit-Hook entfernen, solange die Haken noch stehen; beim Entladen bleibt
  // er (Einstellung an).
  if not TAtlasIdeAffectedTests.Enabled then
  begin
    TAtlasIdeAffectedTests.ApplySettings;
  end;
  TAtlasIdeAffectedTests.Uninstall;
  // Erst die Lens (sie zeigt auf Läufer und Debugger-Teil), dann der Debugger-Teil (stellt eine laufende Sitzung
  // zurück), dann der Läufer; seine Probleme verschwinden mit ihm.
  FreeAndNil(GLens);
  FreeAndNil(GDebugger);
  try
    FreeAndNil(GTests);
  finally
    if TAtlasProblemsController.Current <> nil then
    begin
      TAtlasProblemsController.Current.ClearTests;
    end;
  end;
end;

function TestsStarted: Boolean;
begin
  Result := GTests <> nil;
end;

{ Befehle }

function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(AFeature, AProc);
    end;
end;

function Command(const AId: string; ACaption: TAtlasTestsTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasTestsStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

procedure RunAll;
begin
  if GTests <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GTests.RunAll);
  end;
end;

procedure RunFailed;
begin
  if GTests <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GTests.RunFailed);
  end;
end;

{ Projektverwaltung (#1817) }

function ProjectUnitTestsVisible: Boolean;
begin
  Result := TAtlasProjectContext.Active and TestsVisible and TAtlasProjectContext.Current.HasUnits;
end;

/// <summary>Testunits (mit Fixtures) der Units AUnits unter AFiles und die vollen Namen ihrer Fixtures.</summary>
function FindUnitTests(const AUnits, AFiles: TArray<string>; out ANames: TArray<string>): TArray<string>;
var
  mUnit, mCandidate: string;
  mNames: TArray<string>;
begin
  Result := nil;
  ANames := nil;
  for mUnit in AUnits do
  begin
    for mCandidate in TAtlasTestUnitMatch.Candidates(mUnit, AFiles) do
    begin
      mNames := TAtlasTestUnitMatch.Names(TDUnitXSource.Scan(TAtlasIdeProblemFiles.DiskLines(mCandidate)));
      if Length(mNames) > 0 then
      begin
        Result := Result + [mCandidate];
        ANames := ANames + mNames;
      end;
    end;
  end;
end;

procedure RunProjectUnitTests;
var
  mSelection: TAtlasProjectSelection;
  mKey: string;
  mTestUnits, mNames: TArray<string>;
begin
  mSelection := TAtlasProjectContext.Current;
  if (GTests = nil) or not mSelection.HasUnits then
  begin
    Exit;
  end;
  mTestUnits := FindUnitTests(mSelection.Units, TAtlasIdeProblemFiles.GroupFiles(mKey), mNames);
  if Length(mTestUnits) = 0 then
  begin
    TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsProjectNoTestUnit,
      [ExtractFileName(mSelection.Units[0])]));
    Exit;
  end;
  // Das Testprojekt bestimmt die erste Testunit; die Namen gelten für alle gefundenen.
  GTests.RunTests(mTestUnits[0], mNames);
end;

{ TAtlasTestsModule }

function TAtlasTestsModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Tests';
  Result.Version := TAtlasVersion.cVersion;
  Result.Handle := HInstance;
  // Der Läufer baut und startet Programme: nur im normalen Start.
  Result.MinLevel := TAtlasSafeLevel.Normal;
  Result.Switch := cSwitch;
end;

procedure TAtlasTestsModule.Start;
begin
  FActive := True;
end;

procedure TAtlasTestsModule.Stop;
begin
  FActive := False;
end;

function TAtlasTestsModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasTestsModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Betroffene Tests (#1353): sichtbar mit tests.affected und tests.run.
    Command('Atlas.RunAffectedTests', TAtlasTestsTextId.TestsAffectedCommand,
      Guarded(TAtlasFeature.Build, TAtlasIdeAffectedTests.Run), AffectedTestsVisible),
    // DUnitX-Tests (#69): sichtbar, solange TestRun an ist und der Läufer läuft.
    Command('Atlas.RunTests', TAtlasTestsTextId.TestsRunCommand, RunAll, TestsVisible),
    Command('Atlas.RunFailedTests', TAtlasTestsTextId.TestsRunFailedCommand, RunFailed, TestsVisible),
    // Einzelner Test am Cursor (#585): ausführen (mit TestRun) und im Debugger (mit TestDebug).
    Command('Atlas.RunTest', TAtlasTestsTextId.TestsRunHereCommand, RunAtCursor, TestsVisible),
    Command('Atlas.DebugTest', TAtlasTestsTextId.TestsDebugCommand, DebugAtCursor, TestDebugVisible),
    // Kontextmenü der Projektverwaltung (#1817); außerhalb unsichtbar.
    Command('Atlas.ProjectRunUnitTests', TAtlasTestsTextId.TestsProjectRunUnit,
      Guarded(TAtlasFeature.Build, RunProjectUnitTests), ProjectUnitTestsVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Eintrag im Untermenü „Tests“ von Atlas im Kontextmenü des Editors.</summary>
function ContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsEditorMenuGroup);
end;

function TAtlasTestsModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.RunAffectedTests', TAtlasMenuPlace.AtlasMenu),
    // Test am Cursor (#585) im Untermenü „Atlas“ des Editors.
    ContextEntry('Atlas.RunTest'),
    ContextEntry('Atlas.DebugTest'),
    MenuEntry('-', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.ProjectRunUnitTests', TAtlasMenuPlace.ProjectContext)];
end;

procedure TAtlasTestsModule.ApplySettings;
begin
  // tests.affectedBeforeCommit (#1353): pre-commit-Hook anlegen bzw. entfernen.
  if GTests <> nil then
  begin
    TAtlasIdeAffectedTests.ApplySettings;
  end;
end;

procedure TAtlasTestsModule.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  // Tests nach dem Build (#69), nach derselben Bewertung wie Zusammenfassung und Benachrichtigung (#530).
  if GTests <> nil then
  begin
    GTests.BuildFinished(AProject, AVerdict.Effective);
  end;
end;

procedure TAtlasTestsModule.RunTests(const AFileName: string; const ATests: TArray<string>);
begin
  if GTests <> nil then
  begin
    GTests.RunTests(AFileName, ATests);
  end
  else
  begin
    TAtlasIdeHost.Warning(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
  end;
end;

function TAtlasTestsModule.RunProject(const ATestProject: string; out AReason: string): Boolean;
begin
  if GTests = nil then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.WelcomeQuickReasonTestsOff);
    Exit(False);
  end;
  Result := GTests.RunProject(ATestProject, AReason);
end;

function TAtlasTestsModule.DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
  if GDebugger <> nil then
  begin
    Result := GDebugger.DebugByName(AProject, AFullName, AReason);
  end;
end;

function TAtlasTestsModule.LocateByName(const AProject, AFullName: string; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  Result := TAtlasIdeTestDebugger.LocateByName(AProject, AFullName, AFileName, ALine);
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasTestsCompilerSection.ProvideIn(GScope);
  TAtlasTestsDebugSection.ProvideIn(GScope);
  TAtlasTestsEditorSection.ProvideIn(GScope);
end;

function TAtlasTestsModule.Busy: Boolean;
begin
  Result := (GTests <> nil) and GTests.Busy;
end;

class function TAtlasTestsModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // DUnitX-Tests (#69): nur im normalen Start und solange TestRun an ist; baut über den Läufer von Base.
  Result := [
    TAtlasFeaturePart.When('Tests',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestRun;
      end, TestsStarted, StartTests, StopTests)];
end;

class function TAtlasTestsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasTestsModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
  begin
    Exit;
  end;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + cModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasTestsModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasBuildVerdictListener, mRef);
  GScope.Provide(IAtlasTestRunner, mRef);
  // Vertrag zwischen Modulen: Karte Tests (#763) und Schnellaktionen (#764) der Willkommensseite.
  GScope.Provide(IAtlasTestsSource, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasTestsModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
  begin
    for mFailure in mRegistry.UnregisterModule(cModuleId) do
    begin
      TAtlasGuard.Log('Modul ' + cModuleId + ' nicht sauber abgemeldet: ' + mFailure);
    end;
  end;
end;

initialization
  TAtlasTestsModule.RegisterModule;

finalization
  TAtlasTestsModule.UnregisterModule;

end.
