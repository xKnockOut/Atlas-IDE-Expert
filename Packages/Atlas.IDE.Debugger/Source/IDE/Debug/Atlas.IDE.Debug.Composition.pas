unit Atlas.IDE.Debug.Composition;

// Modul Debugger (#1455): einzige Unit, die die Teile des
// Debuggers erzeugt. Sie meldet in ihrer Initialisierung das Modul
// „atlas.debugger“ (Modulschalter debug, #1454) bei der Registry von Base an
// und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (Visualisierer, eigene Darstellungen,
//   Exception-Verlauf und -Leiste, nur eigener Code, Werte im Editor,
//   „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
//   Debugger-Dialogen, Fenster „Auswerten“, Schrittfilter, „Was wartet worauf?“; die Teile
//   für Werte und Ausdrücke stehen in Atlas.IDE.Debug.Composition.Values, die für
//   Exceptions und Threads in Atlas.IDE.Debug.Composition.Session),
// - Befehle (Palette), Einträge im Atlas-Menü und im Kontextmenü des Editors,
//   die Taste von „Gezielt hineinspringen“,
// - Hörer für Einstellungen, Thema und Ansichtswechsel sowie die Werte im
//   Tooltip,
// - für andere Module den Bericht über die Debug-Sitzung
//   (IAtlasDebugReportSource, Atlas.IDE.Contracts.DebugReport).
// Das erste Teil („DebugCommands“, ab dem abgesicherten Start) installiert
// „Gezielt hineinspringen“, „Beim nächsten Ereignis anhalten“ und die Befehle
// des Schrittfilters; es stoppt als letztes, nimmt sie zurück und hängt F7 ab
// (Trace). Start und Stop des Moduls selbst tun nichts weiter. Abmelden in der Finalisierung, solange Base
// läuft (Regel 5); passt die Vertragsversion von Base nicht, meldet sich das
// Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasDebugModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource, IAtlasKeySource,
    IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasFollowsEditorView, IAtlasHoverValueSource)
  public const
    cModuleId = 'atlas.debugger';
    cSwitch = 'debug';
  private
    FActive: Boolean;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
    procedure EditorViewActivated;
    function HoverValue(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Debug.SettingsSection,
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Providers.Expression,
  Atlas.Core.Completion.Providers.Server,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.OwnCode,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.Visualizers,
  Atlas.IDE.Debug.DisplayRules,
  Atlas.IDE.Debug.StepInto,
  Atlas.IDE.Debug.Trace,
  Atlas.IDE.Debug.StepFilter,
  Atlas.IDE.Debug.Report,
  Atlas.IDE.Contracts.DebugReport,
  Atlas.IDE.Debug.Composition.Values,
  Atlas.IDE.Debug.Composition.Breakpoints,
  Atlas.IDE.Debug.Composition.Session,
  Atlas.UI.Debug.Strings;

var
  GScope: IAtlasModuleScope;
  GCommandsInstalled: Boolean;

{ Dienste von Base }

function Session: TLspSession;
begin
  Result := TAtlasIdeHost.RunningSession;
end;

procedure MessageLine(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

{ Sichtbarkeit und Bedingungen }

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

function DebugExceptionBarVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory and TAtlasIdeSettings.Current.DebugExceptionBanner;
end;

function DebugExceptionsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory;
end;

function DebugEvaluateVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugEvaluateWindow;
end;

function StepIntoTargetVisible: Boolean;
begin
  Result := TAtlasIdeStepInto.Enabled;
end;

function StepFilterRunning: Boolean;
begin
  Result := TAtlasIdeDebugStepFilter.Started;
end;

/// <summary>Taste von „Gezielt hineinspringen“ (#836); 0, solange debug.stepIntoTarget aus ist.</summary>
function StepIntoTargetKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.DebugStepIntoTarget then
  begin
    Result := TAtlasIdeSettings.Current.DebugStepIntoTargetKey;
  end;
end;

/// <summary>Taste von „Gezielt hineinspringen“ unter der Sicherung des Debuggers (#493): nur im angehaltenen
/// Zustand; sonst (und nach einem Fehler) geht die Taste an die IDE.</summary>
function TryStepInto: Boolean;
var
  mDone: Boolean;
begin
  mDone := False;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      mDone := TAtlasIdeStepInto.TryRun;
    end);
  Result := mDone;
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
  mProvider.HistoryCaption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExpressionHistory);
  Result := mProvider;
end;

procedure ToggleDebugJustMyCode;
begin
  TAtlasIdeDebugOwnCode.ToggleSetting(MessageLine);
end;

/// <summary>Befehl abgesichert ausführen (#493): eine Ausnahme schaltet nur die Debugger-Funktionen ab.</summary>
function Guarded(const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, AProc);
    end;
end;

function Command(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := Guarded(ARun);
  Result.Visible := AVisible;
end;

/// <summary>Wie Command, mit Tastenkürzel zur Anzeige. Eigener Name statt Überladung: anonyme Methoden als
/// Argument vertragen keine Überladungen.</summary>
function CommandWithKey(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>; const AKey: TFunc<Integer>): TAtlasModuleCommand;
begin
  Result := Command(AId, ACaption, ARun, AVisible);
  Result.Key := AKey;
end;

{ TAtlasDebugModule }

function TAtlasDebugModule.Info: TAtlasModuleInfo;
begin
  // „Gezielt hineinspringen“ und die Befehle des Schrittfilters gab es schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Debugger', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;

procedure InstallCommands;
begin
  // Gezielt hineinspringen (#836): Liste der Aufrufe am Ausführungspunkt.
  TAtlasIdeStepInto.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  // Beim nächsten Ereignis anhalten (#856): Eintrag im Menü Start.
  InstallBreakCommands;
  // Schrittfilter (#850): Fenster und Befehle; den Ablauf startet das Teil DebugStepFilter.
  TAtlasIdeDebugStepFilter.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
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

procedure TAtlasDebugModule.Start;
begin
  FActive := True;
end;

procedure TAtlasDebugModule.Stop;
begin
  FActive := False;
end;

function TAtlasDebugModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasDebugModule.Commands: TArray<TAtlasModuleCommand>;
var
  mCommand: TAtlasModuleCommand;
begin
  Result := [
    // Gezielt hineinspringen (#836); nur sichtbar, solange debug.stepIntoTarget an ist.
    CommandWithKey('Atlas.StepIntoTarget', TAtlasDebugStrings.StepIntoTargetCommand,
      TAtlasIdeStepInto.Run,
      StepIntoTargetVisible, StepIntoTargetKey),
    // Schrittfilter (#850): Das Fenster schaltet debug.stepFilters selbst, deshalb immer sichtbar.
    Command('Atlas.StepFilters', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterWindowCommand),
      TAtlasIdeDebugStepFilter.ShowWindow,
      nil),
    Command('Atlas.StepIntoAnyway', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterStepIntoAnywayCommand),
      TAtlasIdeDebugStepFilter.StepIntoAnyway, StepFilterRunning),
    // Routine an der Schreibmarke in debug.stepFilters.patterns aufnehmen bzw. entfernen (#850); der Aufruf meldet,
    // was danach noch filtert.
    Command('Atlas.StepFilterSkip', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterSkipCommand),
      TAtlasIdeDebugStepFilter.SkipAtCursor, nil),
    Command('Atlas.StepFilterUnskip', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterUnskipCommand),
      TAtlasIdeDebugStepFilter.UnskipAtCursor,
      nil),
    // Exception-Verlauf (#517); nur sichtbar, solange debug.exceptionHistory an ist.
    Command('Atlas.DebugExceptions', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsCommand),
      TAtlasIdeDebugExceptions.ShowWindow,
      DebugExceptionsVisible),
    // Fenster „Auswerten“ (#784) und der Dialog der IDE daneben.
    Command('Atlas.DebugEvaluate', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateCommand),
      TAtlasIdeDebugEvaluate.ShowWindow,
      DebugEvaluateVisible),
    Command('Atlas.DebugEvaluateIdeDialog', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateIdeDialogCommand),
      TAtlasIdeDebugEvaluate.OpenIdeDialog, DebugEvaluateVisible),
    // Nur eigener Code (#578): schaltet debug.justMyCode um, deshalb immer sichtbar.
    Command('Atlas.DebugJustMyCode', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugJustMyCodeCommand),
      ToggleDebugJustMyCode, nil),
    // Exception-Leiste (#783): Dialog der IDE für die laufende Debug-Sitzung.
    Command('Atlas.DebugExceptionIdeDialog', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerIdeDialogCommand),
      TAtlasIdeDebugExceptionBar.ToggleIdeDialog, DebugExceptionBarVisible),
    // Was wartet worauf? (#587); nur sichtbar, solange debug.deadlocks an ist.
    Command('Atlas.DebugDeadlocks', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugWaitsCommand),
      RunDebugDeadlocks, DebugDeadlocksVisible),
    // Parallele Aufrufstapel (#837); nur sichtbar, solange debug.parallelStacks an ist.
    Command('Atlas.DebugParallelStacks', TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksCommand),
      ShowDebugParallelStacks, DebugParallelStacksVisible)];
  // Anhalten und Haltepunkte (#856, #577) aus Atlas.IDE.Debug.Composition.Breakpoints, unter der Sicherung.
  for mCommand in BreakpointCommands do
  begin
    Result := Result + [Command(mCommand.Id, mCommand.Caption, mCommand.Run, mCommand.Visible)];
  end;
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Läuft eine Debug-Sitzung?</summary>
function WhileDebugging(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.Debugging;
end;

/// <summary>Eintrag im Untermenü „Debuggen“ von Atlas im Kontextmenü des Editors; nur während einer Debug-Sitzung.
/// </summary>
function ContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEditorMenuGroup);
  Result.Group := 'debug';
  Result.When := WhileDebugging;
end;

function TAtlasDebugModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.DebugExceptions', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.DebugEvaluate', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.DebugDeadlocks', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.DebugParallelStacks', TAtlasMenuPlace.AtlasMenu),
    // Kontextmenü des Editors: gezielt hineinspringen (#836) und Schrittfilter (#850).
    ContextEntry('Atlas.StepIntoTarget'),
    ContextEntry('Atlas.StepFilterSkip'),
    ContextEntry('Atlas.StepFilterUnskip')];
  Result := Result + BreakpointMenuEntries;
end;

function TAtlasDebugModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  // Gezielt hineinspringen (#836): nur im angehaltenen Zustand; sonst geht die Taste an die IDE weiter.
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.StepIntoTarget';
  mKey.Caption := TAtlasDebugStrings.StepIntoTargetCommand;
  mKey.Key := StepIntoTargetKey;
  mKey.Attempt :=
    function: Boolean
    begin
      Result := TryStepInto;
    end;
  Result := [mKey];
end;

procedure TAtlasDebugModule.EditorViewActivated;
begin
  // Gezielt hineinspringen (#836): Die Liste gehört zum Ausführungspunkt in der bisherigen Ansicht.
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeStepInto.Dismiss);
end;

procedure TAtlasDebugModule.ApplySettings;
begin
  // debug.breakOnNextEvent (#856).
  ApplyBreakSettings;
  // debug.exceptionHistory (#517).
  TAtlasIdeDebugExceptions.ApplySettings;
  // debug.exceptionBanner* (#783).
  TAtlasIdeDebugExceptionBar.ApplySettings;
  // debug.explainUnavailable (#840), debug.completionInDialogs (#538), debug.evaluateWindow.replaceCtrlF7 (#784).
  ApplyValueSettings;
  // debug.stepFilters* (#850): Fenster mit dem gespeicherten Stand, Treffer neuer Muster zählen.
  TAtlasIdeDebugStepFilter.ApplySettings;
  // debug.visualizers aus: abmelden; Arten geändert: neu anmelden (#835).
  TAtlasIdeVisualizers.ApplySettings;
  // debug.displayRules aus: abmelden; an: Regeln beim nächsten Takt neu lesen (#854).
  TAtlasIdeDisplayRules.ApplySettings;
end;

procedure TAtlasDebugModule.ThemeChanged;
begin
  TAtlasIdeDebugExceptions.ThemeChanged;
  TAtlasIdeDebugExceptionBar.ThemeChanged;
  TAtlasIdeDebugEvaluate.ThemeChanged;
  TAtlasIdeDebugStepFilter.ThemeChanged;
  DebugThreadsThemeChanged;
end;

function TAtlasDebugModule.HoverValue(const AExpression: string; const ATypeChain: TArray<string>;
  const AText: string): string;
begin
  // Eigene Regel des Typs vor den Visualisierern für Bibliothekstypen (#835, #854); beide liefern '', solange ihr
  // Teil nicht läuft.
  Result := TAtlasIdeDisplayRules.HoverText(AExpression, ATypeChain);
  if Result = '' then
  begin
    Result := TAtlasIdeVisualizers.HoverText(AExpression, ATypeChain, AText);
  end;
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
  Result := Result + [StepFilterPart] + DebugThreadParts + BreakpointParts;
end;

class function TAtlasDebugModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasDebugModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasDebugModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
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
  // Vertrag zwischen Modulen: Debug-Notiz und Exception-Verlauf für „An Issue anhängen …“ (#1276).
  GScope.Provide(IAtlasDebugReportSource, TAtlasIdeDebugReport.Create as IAtlasDebugReportSource);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasDebugModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, nil);
end;

initialization
  TAtlasDebugModule.RegisterModule;

finalization
  TAtlasDebugModule.UnregisterModule;

end.
