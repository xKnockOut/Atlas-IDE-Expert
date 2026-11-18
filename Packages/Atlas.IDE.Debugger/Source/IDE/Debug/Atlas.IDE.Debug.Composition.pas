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
//   (IAtlasDebugReportSource, Atlas.IDE.Contracts.DebugReport) und den Halt
//   für „Test daraus anlegen …“ (IAtlasDebugStopSource, #1873); beide stellt
//   Atlas.IDE.Debug.Composition.Contracts bereit.
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
  Atlas.IDE.Debug.Composition.Contracts,
  Atlas.IDE.Debug.Composition.Values,
  Atlas.IDE.Debug.Composition.Breakpoints,
  Atlas.IDE.Debug.Composition.Run,
  Atlas.IDE.Debug.Composition.Session,
  Atlas.UI.Debug.Commands.Strings,
  Atlas.UI.Debug.VariablesStrings;

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
  mProvider.HistoryCaption := TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugExpressionHistory);
  Result := mProvider;
end;

procedure ToggleDebugJustMyCode;
begin
  TAtlasIdeDebugOwnCode.ToggleSetting(TAtlasIdeHost.Messages());
end;

/// <summary>Scope des Moduls für Befehle mit Antwort des Servers; nil vor dem Anmelden.</summary>
function CurrentScope: IAtlasModuleScope;
begin
  Result := GScope;
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

/// <summary>Fenster „Auswerten“ (#784) und der Dialog der IDE daneben, Fenster „Variablen“ (#853); nur sichtbar,
/// solange ihre Einstellung an ist.</summary>
function WindowCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    Command('Atlas.DebugEvaluate', TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugEvaluateCommand),
      TAtlasIdeDebugEvaluate.ShowWindow,
      DebugEvaluateVisible),
    Command('Atlas.DebugEvaluateIdeDialog',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugEvaluateIdeDialogCommand),
      TAtlasIdeDebugEvaluate.OpenIdeDialog, DebugEvaluateVisible),
    Command('Atlas.DebugVariables', TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesCommand),
      ShowVariablesWindow, VariablesWindowVisible),
    // Speicherverlauf (#858); nur sichtbar, solange debug.memoryTimeline an ist.
    Command('Atlas.DebugMemory', DebugMemoryCommandText, ShowDebugMemory, DebugMemoryVisible)];
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
    CommandWithKey('Atlas.StepIntoTarget', TAtlasDebugCommandsStrings.StepIntoTargetCommand,
      TAtlasIdeStepInto.Run,
      StepIntoTargetVisible, StepIntoTargetKey),
    // Schrittfilter (#850): Das Fenster schaltet debug.stepFilters selbst, deshalb immer sichtbar.
    Command('Atlas.StepFilters', TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.StepFilterWindowCommand),
      TAtlasIdeDebugStepFilter.ShowWindow,
      nil),
    Command('Atlas.StepIntoAnyway',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.StepFilterStepIntoAnywayCommand),
      TAtlasIdeDebugStepFilter.StepIntoAnyway, StepFilterRunning),
    // Routine an der Schreibmarke in debug.stepFilters.patterns aufnehmen bzw. entfernen (#850); der Aufruf meldet,
    // was danach noch filtert.
    Command('Atlas.StepFilterSkip', TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.StepFilterSkipCommand),
      TAtlasIdeDebugStepFilter.SkipAtCursor, nil),
    Command('Atlas.StepFilterUnskip',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.StepFilterUnskipCommand),
      TAtlasIdeDebugStepFilter.UnskipAtCursor,
      nil),
    // Exception-Verlauf (#517); nur sichtbar, solange debug.exceptionHistory an ist.
    Command('Atlas.DebugExceptions', TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugExceptionsCommand),
      TAtlasIdeDebugExceptions.ShowWindow,
      DebugExceptionsVisible),
    // Nur eigener Code (#578): schaltet debug.justMyCode um, deshalb immer sichtbar.
    Command('Atlas.DebugJustMyCode', TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugJustMyCodeCommand),
      ToggleDebugJustMyCode, nil),
    // Exception-Leiste (#783): Dialog der IDE für die laufende Debug-Sitzung.
    Command('Atlas.DebugExceptionIdeDialog',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugBannerIdeDialogCommand),
      TAtlasIdeDebugExceptionBar.ToggleIdeDialog, DebugExceptionBarVisible),
    // Was wartet worauf? (#587); nur sichtbar, solange debug.deadlocks an ist.
    Command('Atlas.DebugDeadlocks', TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugWaitsCommand),
      RunDebugDeadlocks, DebugDeadlocksVisible),
    // Parallele Aufrufstapel (#837); nur sichtbar, solange debug.parallelStacks an ist.
    Command('Atlas.DebugParallelStacks',
      TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.ParallelStacksCommand),
      ShowDebugParallelStacks, DebugParallelStacksVisible),
    // Atlas-Lecks (#1875); nur sichtbar, solange debug.leakReport an ist.
    Command('Atlas.DebugLeaks', DebugLeaksCommandText, ShowDebugLeaks, DebugLeaksVisible)];
  // Fenster „Auswerten“ (#784) mit dem Dialog der IDE daneben und Fenster „Variablen“ (#853).
  Result := Result + WindowCommands;
  // Threads im Quelltext (#852): markieren, einfrieren, auftauen; Atlas-Aufrufstapel (#843).
  Result := Result + DebugThreadCommands;
  // Werkzeuge rund um den Lauf: Ereignisprotokoll (#580).
  Result := Result + RunCommands(CurrentScope);
  // Anhalten und Haltepunkte (#856, #577) aus Atlas.IDE.Debug.Composition.Breakpoints, unter der Sicherung.
  for mCommand in BreakpointCommands do
  begin
    Result := Result + [Command(mCommand.Id, mCommand.Caption, mCommand.Run, mCommand.Visible)];
  end;
  // Werte ändern (#868) aus Atlas.IDE.Debug.Composition.Values, unter der Sicherung.
  for mCommand in ValueCommands do
  begin
    Result := Result + [CommandWithKey(mCommand.Id, mCommand.Caption, mCommand.Run, mCommand.Visible, mCommand.Key)];
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
  Result.Section := TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugEditorMenuGroup);
  Result.Group := 'debug';
  Result.When := WhileDebugging;
end;

/// <summary>Ist ein Projekt geladen? Ohne Projekt gibt es nichts zu debuggen.</summary>
function WithProject(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.ProjectOpen;
end;

/// <summary>Eintrag im Untermenü ASection des Atlas-Menüs („-“ = Trennlinie); nur mit offenem Projekt.</summary>
function AtlasEntry(const ACommandId: string; ASection: TAtlasDebugCommandsTextId): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.AtlasMenu);
  Result.Section := TAtlasDebugCommandsStrings.Text(ASection);
  Result.When := WithProject;
end;

/// <summary>Einträge AIds („-“ = Trennlinie) im Untermenü ASection des Atlas-Menüs.</summary>
function AtlasEntries(const AIds: array of string; ASection: TAtlasDebugCommandsTextId): TArray<TAtlasMenuEntry>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AIds));
  for mIndex := 0 to High(AIds) do
  begin
    Result[mIndex] := AtlasEntry(AIds[mIndex], ASection);
  end;
end;

/// <summary>Einträge im Atlas-Menü: Untermenü Debuggen (Fenster; Was wartet worauf?; Neu starten und
/// Startverbünde; Profiler; Bericht einfügen und Debug-Zustand festhalten) und Untermenü Haltepunkte, je Gruppe
/// durch Trennlinien getrennt.
/// </summary>
function AtlasMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := AtlasEntries(['Atlas.DebugExceptions', 'Atlas.DebugEvaluate', 'Atlas.DebugVariables',
    'Atlas.DebugCallStack', 'Atlas.DebugParallelStacks', 'Atlas.DebugEventLog', 'Atlas.DebugMemory',
    'Atlas.DebugLeaks', '-', 'Atlas.DebugDeadlocks', '-', 'Atlas.DebugRestart', 'Atlas.LaunchGroups', '-',
    'Atlas.DebugProfile', 'Atlas.DebugProfileRun', 'Atlas.DebugProfileToggle', '-', 'Atlas.RuntimeReportPaste',
    'Atlas.DebugNote'],
    TAtlasDebugCommandsTextId.DebugEditorMenuGroup);
  Result := Result + AtlasEntries(['Atlas.BreakpointsWindow', 'Atlas.CheckBreakpoints', '-', 'Atlas.Logpoint',
    '-', 'Atlas.MethodBreakpoints', 'Atlas.MethodBreakpointGroups', '-', 'Atlas.BreakpointRules', '-',
    'Atlas.BreakpointSetSave', 'Atlas.BreakpointSetSwitch', '-', 'Atlas.BreakpointAnchorsOrphans',
    'Atlas.BreakpointAnchorsUndo'], TAtlasDebugCommandsTextId.MenuGroupBreakpoints);
end;

/// <summary>Fenster des Debuggers unter Ansicht › Atlas › Debuggen; anders als im Atlas-Menü auch ohne Projekt,
/// damit sich das Layout einrichten lässt.</summary>
function ViewMenuEntries: TArray<TAtlasMenuEntry>;
const
  cWindows: array[0..10] of string = ('Atlas.DebugExceptions', 'Atlas.DebugEvaluate', 'Atlas.DebugVariables',
    'Atlas.DebugCallStack', 'Atlas.DebugParallelStacks', 'Atlas.DebugEventLog', 'Atlas.DebugMemory',
    'Atlas.DebugLeaks', 'Atlas.StepFilters', 'Atlas.DebugProfile', 'Atlas.BreakpointsWindow');
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(cWindows));
  for mIndex := 0 to High(cWindows) do
  begin
    Result[mIndex] := MenuEntry(cWindows[mIndex], TAtlasMenuPlace.ViewMenu);
    Result[mIndex].Section := TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DebugEditorMenuGroup);
  end;
end;

function TAtlasDebugModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := AtlasMenuEntries + ViewMenuEntries;
  Result := Result + [
    // Kontextmenü des Editors: gezielt hineinspringen (#836) und Schrittfilter (#850).
    ContextEntry('Atlas.StepIntoTarget'),
    ContextEntry('Atlas.StepFilterSkip'),
    ContextEntry('Atlas.StepFilterUnskip'),
    // Threads im Quelltext (#852): für die Threads an der Zeile des Rechtsklicks in die Rinne.
    ContextEntry('Atlas.DebugThreadFlag'),
    ContextEntry('Atlas.DebugThreadFreeze'),
    ContextEntry('Atlas.DebugThreadThaw'),
    ContextEntry('Atlas.DebugThreadsThawAll')];
  // Ereignisprotokoll, Logpunkte, Neu starten und Laufzeitberichte (#580, #583, #872, #74).
  Result := Result + RunMenuEntries;
  Result := Result + BreakpointMenuEntries;
  // Werte ändern (#868).
  Result := Result + ValueMenuEntries;
end;

function TAtlasDebugModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  // Gezielt hineinspringen (#836): nur im angehaltenen Zustand; sonst geht die Taste an die IDE weiter.
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.StepIntoTarget';
  mKey.Caption := TAtlasDebugCommandsStrings.StepIntoTargetCommand;
  mKey.Key := StepIntoTargetKey;
  mKey.Attempt :=
    function: Boolean
    begin
      Result := TryStepInto;
    end;
  Result := [mKey];
  Result := Result + RunKeys;
  // Bis hier, Haltepunkte überspringen (#851).
  Result := Result + BreakpointKeys;
  // Wert ändern mit F2 (#868).
  Result := Result + ValueKeys;
end;

procedure TAtlasDebugModule.ApplySettings;
begin
  // debug.breakOnNextEvent (#856).
  ApplyBreakSettings;
  // debug.exceptionHistory (#517).
  TAtlasIdeDebugExceptions.ApplySettings;
  // debug.exceptionBanner* (#783).
  TAtlasIdeDebugExceptionBar.ApplySettings;
  // debug.explainUnavailable (#840), debug.completionInDialogs (#538), debug.evaluateWindow.replaceCtrlF7 (#784),
  // debug.memoryTimeline* (#858).
  ApplyValueSettings;
  // debug.stepFilters* (#850): Fenster mit dem gespeicherten Stand, Treffer neuer Muster zählen.
  TAtlasIdeDebugStepFilter.ApplySettings;
  // debug.visualizers aus: abmelden; Arten geändert: neu anmelden (#835).
  TAtlasIdeVisualizers.ApplySettings;
  // debug.displayRules aus: abmelden; an: Regeln beim nächsten Takt neu lesen (#854).
  TAtlasIdeDisplayRules.ApplySettings;
  // debug.eventLog* (#580).
  ApplyRunSettings;
end;

procedure TAtlasDebugModule.ThemeChanged;
begin
  TAtlasIdeDebugExceptions.ThemeChanged;
  TAtlasIdeDebugExceptionBar.ThemeChanged;
  // Fenster „Auswerten“ (#784), „Variablen“ (#853) und „Atlas: Speicher“ (#858).
  ValueThemeChanged;
  TAtlasIdeDebugStepFilter.ThemeChanged;
  RunThemeChanged;
  DebugThreadsThemeChanged;
  BreakpointsThemeChanged;
end;

procedure TAtlasDebugModule.EditorViewActivated;
begin
  // Gezielt hineinspringen (#836): Die Liste gehört zum Ausführungspunkt in der bisherigen Ansicht.
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeStepInto.Dismiss);
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
  Result := Result + [StepFilterPart] + DebugThreadParts(GScope) + DebugLeakParts(GScope) +
    BreakpointParts + RunParts(CurrentScope) + DebugMemoryParts;
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
  // Verträge zwischen Modulen: Debug-Notiz und Exception-Verlauf für „An Issue anhängen …“ (#1276), Halt für
  // „Test daraus anlegen …“ (#1873).
  ProvideDebugContracts(GScope);
  ProvideDebugThreadLayers(GScope);
  // Logpunkte in der Rinne (#583).
  ProvideRun(GScope);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasDebugModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, nil);
end;

initialization
  TAtlasDebugModule.RegisterModule;

finalization
  TAtlasDebugModule.UnregisterModule;

end.
