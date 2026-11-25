unit Atlas.IDE.Debug.Composition;

// Modul Debugger (#1455): einzige Unit, die die Teile des
// Debuggers erzeugt. Sie meldet in ihrer Initialisierung das Modul
// „atlas.debugger“ (Modulschalter debug, #1454) bei der Registry von Base an
// und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (Visualisierer, eigene Darstellungen,
//   Exception-Verlauf und -Leiste, nur eigener Code, Werte im Editor,
//   „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
//   Debugger-Dialogen, Fenster „Auswerten“, Schrittfilter, „Was wartet worauf?“, Speicherverlauf, Profiler;
//   die Teile für Werte und Ausdrücke stehen in Atlas.IDE.Debug.Composition.Values, die für
//   Exceptions und Threads in Atlas.IDE.Debug.Composition.Session),
// - Befehle (Palette), Einträge im Atlas-Menü und im Kontextmenü des Editors,
//   die Taste von „Gezielt hineinspringen“,
// - Hörer für Einstellungen, Thema und Ansichtswechsel sowie die Werte im
//   Tooltip,
// - für andere Module den Bericht über die Debug-Sitzung
//   (IAtlasDebugReportSource, Atlas.IDE.Base.Foundation.DebugReport) und den Halt
//   für „Test daraus anlegen …“ (IAtlasDebugStopSource, #1873); beide stellt
//   Atlas.IDE.Debug.Composition.Contracts bereit.
// Das erste Teil („DebugCommands“, ab dem abgesicherten Start) installiert
// „Gezielt hineinspringen“, „Beim nächsten Ereignis anhalten“ und die Befehle
// des Schrittfilters; es stoppt als letztes, nimmt sie zurück und hängt F7 ab
// (Trace). Start und Stop des Moduls selbst tun nichts weiter. Abmelden in der Finalisierung, solange Base
// läuft (Regel 5); passt die Vertragsversion von Base nicht, meldet sich das
// Modul nicht an (Regel 7).
// Modulklasse, eigene Befehle, Menü und Tasten stehen in Atlas.IDE.Debug.Adapters.Module.

interface

implementation

uses
  System.SysUtils,
  Atlas.UI.Debug.SettingsSection,
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Base.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Providers.Expression,
  Atlas.Core.Completion.Providers.Server,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.Visualizers,
  Atlas.IDE.Debug.DisplayRules,
  Atlas.IDE.Debug.StepInto,
  Atlas.IDE.Debug.Trace,
  Atlas.IDE.Debug.StepFilter,
  Atlas.IDE.Debug.Composition.Contracts,
  Atlas.IDE.Debug.Composition.Values,
  Atlas.IDE.Debug.Composition.Breakpoints,
  Atlas.IDE.Debug.Composition.Run,
  Atlas.IDE.Debug.Composition.Session,
  Atlas.UI.Debug.Commands.Strings,
  Atlas.UI.Debug.VariablesStrings,
  Atlas.IDE.Debug.Adapters.Module;

var
  GScope: IAtlasModuleScope;
  GCommandsInstalled: Boolean;

{ Dienste von Base }

function Session: TLspSession;
begin
  Result := TAtlasIdeHost.RunningSession;
end;

{ Sichtbarkeit und Bedingungen }

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

{ Start der Teile (aus der Kompositionswurzel hierher gezogen, #1455) }

procedure StartDisplayRules;
begin
  // Nur eine laufende Sitzung; die Regeln warten sonst auf den nächsten Versuch.
  TAtlasIdeDisplayRules.Start(
    function: TLspSession
    begin
      Result := Session;
    end);
end;

function ExpressionProvider(const AHistory: TFunc<TArray<string>>): IAtlasCompletionProvider;
var
  mProvider: TAtlasExpressionCompletionProvider;
begin
  mProvider := TAtlasExpressionCompletionProvider.Create(
    function: TLspSession
    begin
      Result := Session;
    end, AHistory,
    function(AResponse: TJSONValue): TAtlasCompletionItems
    begin
      Result := TAtlasServerCompletionProvider.ItemsFromLsp(AResponse);
    end, TAtlasExpressionCompletionProvider.cDefaultTimeoutMs);
  mProvider.HistoryCaption := TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugExpressionHistory);
  Result := mProvider;
end;

/// <summary>Scope des Moduls für Befehle mit Antwort des Servers; nil vor dem Anmelden.</summary>
function CurrentScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

procedure InstallCommands;
begin
  // Gezielt hineinspringen (#836): Liste der Aufrufe am Ausführungspunkt.
  TAtlasIdeStepInto.Install(
    function: TLspSession
    begin
      Result := Session;
    end, TAtlasIdeHost.Messages());
  // Beim nächsten Ereignis anhalten (#856): Eintrag im Menü Start.
  InstallBreakCommands;
  // Schrittfilter (#850): Fenster und Befehle; den Ablauf startet das Teil DebugStepFilter.
  TAtlasIdeDebugStepFilter.Install(
    function: TLspSession
    begin
      Result := Session;
    end, TAtlasIdeHost.Messages());
  GCommandsInstalled := True;
end;

procedure UninstallCommands;
begin
  GCommandsInstalled := False;
  TAtlasIdeStepInto.Uninstall;
  UninstallBreakCommands;
  TAtlasIdeDebugStepFilter.Uninstall;
  // Nach allen anderen Teilen: Was von F7 übrig ist, hängt der Debugger hier ab (#850).
  TAtlasIdeDebugTrace.Release;
end;

function CommandsInstalled: Boolean;
begin
  Result := GCommandsInstalled;
end;

{ Teile der Feature-Tabelle }

/// <summary>Befehle des Debuggers (schon im abgesicherten Start, stoppen als letztes), Visualisierer und eigene
/// Wertdarstellungen.</summary>
function LeadingParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Zuerst: Befehle des Debuggers, schon im abgesicherten Start; stoppt als letztes Teil.
    TAtlasFeaturePart.AtLevel('DebugCommands', TAtlasSafeLevel.Safe, CommandsInstalled, InstallCommands,
      UninstallCommands),
    // Visualisierer für häufige Typen (#835): nur im normalen Start und solange debug.visualizers an ist.
    TAtlasFeaturePart.When('Visualizers',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugVisualizers;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeVisualizers.Started;
      end, TAtlasIdeVisualizers.Start, TAtlasIdeVisualizers.Stop),
    // Eigene Wertdarstellungen (#854): nur im normalen Start und solange debug.displayRules an ist.
    TAtlasFeaturePart.When('DisplayRules',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugDisplayRules;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDisplayRules.Started;
      end, StartDisplayRules, TAtlasIdeDisplayRules.Stop)]
end;

/// <summary>Schrittfilter (#850): Zuhörer der Debug-Sitzung und Empfänger von F7; aus = F7 wie bisher.</summary>
function StepFilterPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugStepFilter',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugStepFilters;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugStepFilter.Started;
    end, TAtlasIdeDebugStepFilter.Start, TAtlasIdeDebugStepFilter.Release);
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasDebugSettingsSection.ProvideIn(GScope);
end;

/// <summary>Alle Teile in ihrer Startreihenfolge; Werte und Ausdrücke aus Atlas.IDE.Debug.Composition.Values.
/// </summary>
function Parts: TArray<IAtlasFeaturePart>;
begin
  Result := LeadingParts + DebugExceptionParts + DebugValueParts(ExpressionProvider, GScope);
  Result := Result + [StepFilterPart] + DebugThreadParts(GScope) + DebugLeakParts(GScope) +
    BreakpointParts + RunParts(CurrentScope) + DebugMemoryParts;
end;

{ Beiträge der Teile an die Modulklasse }

function DebugEvaluateVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugEvaluateWindow;
end;

/// <summary>Fenster „Auswerten“ (#784) und der Dialog der IDE daneben, Fenster „Variablen“ (#853); nur sichtbar,
/// solange ihre Einstellung an ist.</summary>
function WindowCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    TAtlasDebugModule.Command('Atlas.DebugEvaluate',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugEvaluateCommand),
      TAtlasIdeDebugEvaluate.ShowWindow,
      DebugEvaluateVisible),
    TAtlasDebugModule.Command('Atlas.DebugEvaluateIdeDialog',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugEvaluateIdeDialogCommand),
      TAtlasIdeDebugEvaluate.OpenIdeDialog, DebugEvaluateVisible),
    TAtlasDebugModule.Command('Atlas.DebugVariables',
      TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesCommand),
      ShowVariablesWindow, VariablesWindowVisible),
    // Speicherverlauf (#858); nur sichtbar, solange debug.memoryTimeline an ist.
    TAtlasDebugModule.Command('Atlas.DebugMemory', DebugMemoryCommandText, ShowDebugMemory, DebugMemoryVisible)];
end;

/// <summary>Befehle der Teile: Exception-Regeln, Was wartet worauf?, parallele Stapel und Auswertung, Lecks,
/// Fenster, Threads, Lauf, Haltepunkte und Werte.</summary>
function PartCommands: TArray<TAtlasModuleCommand>;
var
  mCommand: TAtlasModuleCommand;
begin
  Result := [
    // Exception-Regeln nach Klasse, Ort und Meldung (#838, #2549).
    TAtlasDebugModule.Command('Atlas.DebugExceptionRules',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugExceptionRulesCommand),
      ShowDebugExceptionRules, DebugExceptionRulesVisible),
    // Was wartet worauf? (#587); nur sichtbar, solange debug.deadlocks an ist.
    TAtlasDebugModule.Command('Atlas.DebugDeadlocks',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugWaitsCommand),
      RunDebugDeadlocks, DebugDeadlocksVisible),
    // Parallele Aufrufstapel (#837); nur sichtbar, solange debug.parallelStacks an ist.
    TAtlasDebugModule.Command('Atlas.DebugParallelStacks',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.ParallelStacksCommand),
      ShowDebugParallelStacks, DebugParallelStacksVisible),
    // Parallel auswerten (#866); nur sichtbar, solange debug.parallelWatch an ist.
    TAtlasDebugModule.Command('Atlas.DebugParallelWatch', DebugParallelWatchCommandText, ShowDebugParallelWatch,
      DebugParallelWatchVisible),
    // Atlas-Lecks (#1875); nur sichtbar, solange debug.leakReport an ist.
    TAtlasDebugModule.Command('Atlas.DebugLeaks', DebugLeaksCommandText, ShowDebugLeaks, DebugLeaksVisible)];
  // Fenster „Auswerten“ (#784) mit dem Dialog der IDE daneben und Fenster „Variablen“ (#853).
  Result := Result + WindowCommands;
  // Threads im Quelltext (#852): markieren, einfrieren, auftauen; Atlas-Aufrufstapel (#843).
  Result := Result + DebugThreadCommands;
  // Werkzeuge rund um den Lauf: Ereignisprotokoll (#580).
  Result := Result + RunCommands(CurrentScope);
  // Anhalten und Haltepunkte (#856, #577) aus Atlas.IDE.Debug.Composition.Breakpoints, unter der Sicherung.
  for mCommand in BreakpointCommands do
  begin
    Result := Result + [TAtlasDebugModule.Command(mCommand.Id, mCommand.Caption, mCommand.Run, mCommand.Visible)];
  end;
  // Werte ändern (#868) aus Atlas.IDE.Debug.Composition.Values, unter der Sicherung.
  for mCommand in ValueCommands do
  begin
    Result := Result + [TAtlasDebugModule.CommandWithKey(mCommand.Id, mCommand.Caption, mCommand.Run,
      mCommand.Visible, mCommand.Key)];
  end;
end;

/// <summary>Ereignisprotokoll, Logpunkte, Neu starten und Laufzeitberichte (#580, #583, #872, #74), Haltepunkte
/// und Werte ändern (#868).</summary>
function PartMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := RunMenuEntries + BreakpointMenuEntries + ValueMenuEntries;
end;

/// <summary>Tasten des Laufs, bis hier und Haltepunkte überspringen (#851), Wert ändern mit F2 (#868).</summary>
function PartKeys: TArray<TAtlasModuleKey>;
begin
  Result := RunKeys + BreakpointKeys + ValueKeys;
end;

procedure ApplyPartSettings;
begin
  // debug.breakOnNextEvent (#856).
  ApplyBreakSettings;
  // debug.explainUnavailable (#840), debug.completionInDialogs (#538), debug.evaluateWindow.replaceCtrlF7 (#784),
  // debug.memoryTimeline* (#858).
  ApplyValueSettings;
  // debug.eventLog* (#580).
  ApplyRunSettings;
end;

procedure PartThemeChanged;
begin
  // Fenster „Auswerten“ (#784), „Variablen“ (#853) und „Atlas: Speicher“ (#858).
  ValueThemeChanged;
  RunThemeChanged;
  DebugThreadsThemeChanged;
  BreakpointsThemeChanged;
end;

/// <summary>Was die Teile zur Modulklasse beitragen.</summary>
function ModuleHooks: TAtlasDebugModuleHooks;
begin
  Result := Default(TAtlasDebugModuleHooks);
  Result.Commands := PartCommands;
  Result.MenuEntries := PartMenuEntries;
  Result.Keys := PartKeys;
  Result.ApplySettings := ApplyPartSettings;
  Result.ThemeChanged := PartThemeChanged;
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasDebugModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasDebugModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasDebugModule.Create(ModuleHooks);
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  UseDebugAdapters;
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  GScope.Provide(IAtlasFollowsEditorView, mRef);
  GScope.Provide(IAtlasHoverValueSource, mRef);
  // Verträge zwischen Modulen: Debug-Notiz und Exception-Verlauf für „An Issue anhängen …“ (#1276), Halt für
  // „Test daraus anlegen …“ (#1873).
  ProvideDebugContracts(GScope);
  ProvideDebugThreadLayers(GScope);
  // Logpunkte in der Rinne (#583).
  ProvideRun(GScope);
  // Haltepunkte mit Aufrufer in der Rinne (#2548).
  ProvideBreakpoints(GScope);
  ProvideSettingsSections;
  Result := True;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasDebugModule.cModuleId, HInstance, nil);
  ReleaseDebugAdapters;
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
