unit Atlas.IDE.Tests.Composition;

// Modul Tests (#1455): einzige Unit, die den Testläufer für DUnitX
// (#69), „Test am Cursor ausführen bzw. debuggen“ (#585), die Code Lens der
// Tests und „Betroffene Tests ausführen“ (#1353) erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.tests“ (Modulschalter tests, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - den Teil Tests der Feature-Tabelle,
// - Befehle (Palette), die Einträge „Betroffene Tests ausführen“,
//   „Veraltete Tests ausführen“ (#1770), „Erwartet und erhalten
//   vergleichen“ (#1779) und „Langsamste Tests zeigen“ (#1772) im
//   Atlas-Menü, „TestCase-Tabelle bearbeiten …“ (#1879) in der Palette und im
//   Kontextmenü einer Testunit, „Test ausführen“/„Test debuggen“ im Kontextmenü und „Tests
//   dieser Unit ausführen“ im Kontextmenü der Projektverwaltung (#1817:
//   Testunits der gewählten Units nach Namen in der Projektgruppe, nur solche
//   mit Fixtures; ohne eine meldet das Modul es in der Meldungsansicht) und
//   den Assistenten „DUnitX-Testunit zu Unit …“ in Datei › Neu › Weitere
//   (#1821: Unit der Projektgruppe wählen, die Unit im Editor vorgewählt;
//   angelegt wie „Zur Testunit wechseln“ von Base),
// - Hörer für Einstellungen und bewertete Builds (Tests nach dem Build) und für
//   gespeicherte Dateien (betroffene Tests im Hintergrund, #1775),
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
    IAtlasAppliesSettings, IAtlasBuildVerdictListener, IAtlasTestRunner, IAtlasTestsSource, IAtlasFollowsSaves)
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
    procedure FileSaved(const AFileName: string);
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
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Adapters.ProcessRunner,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.OnSave,
  Atlas.IDE.Tests.Composition.Hooks,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Lens,
  Atlas.IDE.Tests.Stale,
  Atlas.IDE.Tests.Compare,
  Atlas.IDE.Tests.Slowest,
  Atlas.IDE.Tests.CaseTable,
  Atlas.IDE.Tests.Affected,
  Atlas.IDE.Tests.UnitCommands,
  Atlas.UI.Tests.Strings;

var
  GScope: IAtlasModuleScope;
  GOutput: TAtlasIdeTestsOutput;
  GTests: TAtlasIdeTests;
  GOnSave: TAtlasIdeTestsOnSave;
  GDebugger: TAtlasIdeTestDebugger;
  GLens: TAtlasIdeTestsLens;
  GStale: TAtlasIdeStaleTests;
  GCompare: TAtlasIdeTestCompare;
  GSlowest: TAtlasIdeTestSlowest;
  GCaseTable: TAtlasIdeTestCaseTable;

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

function AffectedHooks: TAtlasAffectedTestsHooks;
begin
  Result := Default(TAtlasAffectedTestsHooks);
  Result.RunTests := AffectedRunTests;
  Result.RunAll := AffectedRunAll;
  Result.ResolveTarget := AffectedResolveTarget;
  Result.ServerPath := ServerPath;
end;

{ TestCase-Tabelle (#1879) }

procedure OpenCaseTable(const AFileName: string; ALine: Integer);
begin
  if GCaseTable <> nil then
  begin
    GCaseTable.OpenAt(AFileName, ALine);
  end;
end;

{ Teil Tests }

procedure StartTests;
begin
  GOutput := TAtlasIdeTestsOutput.Create;
  GTests := TAtlasIdeTests.Create(TestsProcess(), GOutput);
  GTests.OnBuild := BuildForTests;
  GTests.OnProblems := ShowProblems;
  GTests.OnFinished := AnnounceTests;
  GTests.OnLastFailed := LastFailed;
  // Veraltete Ergebnisse (#1770): Stand je Test nach jedem Lauf.
  GStale := TAtlasIdeStaleTests.Create(GTests);
  // Erwartet und erhalten vergleichen (#1779): Fehlschläge mit Werten; reicht den Lauf an die Stände weiter.
  GCompare := TAtlasIdeTestCompare.Create(GTests, GStale.Remember);
  // Langsamste Tests (#1772): Ergebnisse des Testprojekts; reicht den Lauf an den Vergleich weiter.
  GSlowest := TAtlasIdeTestSlowest.Create(GTests, GCompare.Remember);
  GTests.OnReported := GSlowest.Remember;
  // Einzelner Test ausführen bzw. debuggen (#585), auch aus dem Kontextmenü und der Lens.
  GDebugger := TAtlasIdeTestDebugger.Create(GTests);
  GLens := TAtlasIdeTestsLens.Create(GTests, GDebugger, GStale.StaleIn);
  // TestCase-Tabelle (#1879): Befehl und Marke „Tabelle“ der Lens.
  GCaseTable := TAtlasIdeTestCaseTable.Create(GScope, GTests, GDebugger);
  GLens.OnTable := OpenCaseTable;
  TAtlasIdeAffectedTests.Install(AffectedHooks);
  // Betroffene Tests beim Speichern (#1775): im Hintergrund über den Läufer.
  GOnSave := TAtlasIdeTestsOnSave.Create(GTests, GOutput);
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
  // Tests beim Speichern (#1775) vor dem Läufer: Uninstall hat ihre offenen Anfragen schon verworfen.
  FreeAndNil(GOnSave);
  // Erst die Lens (sie zeigt auf Läufer und Debugger-Teil), dann der Debugger-Teil (stellt eine laufende Sitzung
  // zurück), dann langsamste Tests (#1772), Vergleich (#1779) und Stände der veralteten Ergebnisse (#1770), dann
  // der Läufer; seine Probleme verschwinden mit ihm.
  FreeAndNil(GLens);
  FreeAndNil(GCaseTable);
  FreeAndNil(GDebugger);
  if GTests <> nil then
  begin
    GTests.OnReported := nil;
  end;
  FreeAndNil(GSlowest);
  FreeAndNil(GCompare);
  FreeAndNil(GStale);
  try
    FreeAndNil(GTests);
    FreeAndNil(GOutput);
  finally
    ClearProblems;
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

{ Veraltete Tests (#1770) }

function StaleTestsVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsStale;
end;

procedure RunStale;
begin
  if GStale <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GStale.Run);
  end;
end;

{ Erwartet und erhalten vergleichen (#1779) }

function CompareVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsCompare;
end;

procedure CompareValues;
begin
  if GCompare <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GCompare.Run);
  end;
end;

{ Langsamste Tests (#1772) }

function SlowestVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsShowDuration;
end;

procedure ShowSlowest;
begin
  if GSlowest <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSlowest.Run);
  end;
end;

{ TestCase-Tabelle (#1879) }

function CaseTableVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeTestCaseTable.Wanted and (GCaseTable <> nil);
end;

procedure EditCaseTable;
begin
  if GCaseTable <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GCaseTable.OpenAtCursor);
  end;
end;

{ Projektverwaltung (#1817) }

function ProjectUnitTestsVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeTestUnitCommands.HasProjectUnits;
end;

procedure RunProjectUnitTests;
begin
  TAtlasIdeTestUnitCommands.RunProjectUnits(GTests);
end;

function Described(const ACommand: TAtlasModuleCommand; ADescription: TAtlasTestsTextId): TAtlasModuleCommand;
begin
  Result := ACommand;
  Result.Description := TAtlasTestsStrings.Text(ADescription);
end;

{ TAtlasTestsModule }

function TAtlasTestsModule.Info: TAtlasModuleInfo;
begin
  // Der Läufer baut und startet Programme: nur im normalen Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Tests', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Normal, cSwitch);
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
    // Veraltete Ergebnisse (#1770): sichtbar mit tests.stale.
    Command('Atlas.RunStaleTests', TAtlasTestsTextId.TestsRunStaleCommand, RunStale, StaleTestsVisible),
    // Erwartet und erhalten eines Fehlschlags (#1779): sichtbar mit tests.compare.
    Command('Atlas.CompareTestValues', TAtlasTestsTextId.TestsCompareCommand, CompareValues, CompareVisible),
    // Langsamste Tests (#1772): sichtbar mit tests.showDuration.
    Command('Atlas.ShowSlowestTests', TAtlasTestsTextId.TestsSlowestCommand, ShowSlowest, SlowestVisible),
    // [TestCase]-Fälle als Tabelle (#1879): sichtbar mit tests.testCaseTable.
    Command('Atlas.EditTestCases', TAtlasTestsTextId.TestsCaseTableCommand, EditCaseTable, CaseTableVisible),
    // Einzelner Test am Cursor (#585): ausführen (mit TestRun) und im Debugger (mit TestDebug).
    Command('Atlas.RunTest', TAtlasTestsTextId.TestsRunHereCommand, RunAtCursor, TestsVisible),
    Command('Atlas.DebugTest', TAtlasTestsTextId.TestsDebugCommand, DebugAtCursor, TestDebugVisible),
    // Kontextmenü der Projektverwaltung (#1817); außerhalb unsichtbar.
    Command('Atlas.ProjectRunUnitTests', TAtlasTestsTextId.TestsProjectRunUnit,
      Guarded(TAtlasFeature.Build, RunProjectUnitTests), ProjectUnitTestsVisible),
    // Assistent in Datei › Neu › Weitere (#1821); auch in der Palette.
    Described(Command('Atlas.NewTestUnitFor', TAtlasTestsTextId.TestsGalleryTestUnit,
      Guarded(TAtlasFeature.Generate, TAtlasIdeTestUnitCommands.NewTestUnitFor), nil),
      TAtlasTestsTextId.TestsGalleryTestUnitHint)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Ist die Datei eine DUnitX-Testunit?</summary>
function InTestUnit(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.TestUnit;
end;

/// <summary>Eintrag im Untermenü „Tests“ von Atlas im Kontextmenü des Editors; nur in einer Testunit.</summary>
function ContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsEditorMenuGroup);
  Result.Group := 'tests';
  Result.When := InTestUnit;
end;

function TAtlasTestsModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.RunAffectedTests', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.RunStaleTests', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.CompareTestValues', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.ShowSlowestTests', TAtlasMenuPlace.AtlasMenu),
    // Test am Cursor (#585) im Untermenü „Atlas“ des Editors.
    ContextEntry('Atlas.RunTest'),
    ContextEntry('Atlas.DebugTest'),
    ContextEntry('Atlas.CompareTestValues'),
    ContextEntry('Atlas.EditTestCases'),
    MenuEntry('-', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.ProjectRunUnitTests', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.NewTestUnitFor', TAtlasMenuPlace.Gallery)];
end;

procedure TAtlasTestsModule.ApplySettings;
begin
  // tests.affectedBeforeCommit (#1353): pre-commit-Hook anlegen bzw. entfernen.
  if GTests <> nil then
  begin
    TAtlasIdeAffectedTests.ApplySettings;
  end;
  // tests.onSave aus (#1775): Warteschlange und Statuszeile weg.
  if GOnSave <> nil then
  begin
    GOnSave.ApplySettings;
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
    TAtlasIdeHost.Warning(TestsOffText);
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

procedure TAtlasTestsModule.FileSaved(const AFileName: string);
begin
  // Betroffene Tests beim Speichern (#1775).
  if GOnSave <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        GOnSave.FileSaved(AFileName);
      end);
  end;
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
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
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
  GScope.Provide(IAtlasFollowsSaves, mRef);
  GScope.Provide(IAtlasTestRunner, mRef);
  // Vertrag zwischen Modulen: Karte Tests (#763) und Schnellaktionen (#764) der Willkommensseite.
  GScope.Provide(IAtlasTestsSource, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasTestsModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, nil);
end;

initialization
  TAtlasTestsModule.RegisterModule;

finalization
  TAtlasTestsModule.UnregisterModule;

end.
