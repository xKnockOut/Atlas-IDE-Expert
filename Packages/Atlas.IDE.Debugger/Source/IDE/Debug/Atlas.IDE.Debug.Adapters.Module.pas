unit Atlas.IDE.Debug.Adapters.Module;

// Modulklasse des Debuggers (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Debug.Composition) über den Scope des Moduls bereitstellt: Befehle, Menüeinträge (Atlas-Menü, Ansicht ›
// Atlas › Debuggen, Kontextmenü des Editors) und Tasten von „Gezielt hineinspringen“ (#836), Schrittfilter (#850),
// Exception-Verlauf (#517), Exception-Leiste (#783) und „Nur eigener Code“ (#578), Einstellungen und Thema, die
// Ansicht des Editors und Werte im Tooltip (#835, #854). Was die Teile der Composition beitragen (Werte, Threads,
// Lauf, Haltepunkte, Speicher), reicht sie als TAtlasDebugModuleHooks herein.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  /// <summary>Beiträge der Teile der Composition, die die Modulklasse anhängt.</summary>
  TAtlasDebugModuleHooks = record
    Commands: TFunc<TArray<TAtlasModuleCommand>>;
    MenuEntries: TFunc<TArray<TAtlasMenuEntry>>;
    Keys: TFunc<TArray<TAtlasModuleKey>>;
    ApplySettings: TProc;
    ThemeChanged: TProc;
  end;

  TAtlasDebugModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource, IAtlasKeySource,
    IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasFollowsEditorView, IAtlasHoverValueSource)
  public const
    cModuleId = 'atlas.debugger';
    cSwitch = 'debug';
  private
    FActive: Boolean;
    FHooks: TAtlasDebugModuleHooks;
  public
    constructor Create(const AHooks: TAtlasDebugModuleHooks);
    /// <summary>Befehl unter der Sicherung des Debuggers (#493): eine Ausnahme schaltet nur die
    /// Debugger-Funktionen ab.</summary>
    class function Command(const AId: string; const ACaption: string; const ARun: TProc;
      const AVisible: TFunc<Boolean>): TAtlasModuleCommand; static;
    /// <summary>Wie Command, mit Tastenkürzel zur Anzeige. Eigener Name statt Überladung: anonyme Methoden als
    /// Argument vertragen keine Überladungen.</summary>
    class function CommandWithKey(const AId: string; const ACaption: string; const ARun: TProc;
      const AVisible: TFunc<Boolean>; const AKey: TFunc<Integer>): TAtlasModuleCommand; static;
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
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.OwnCode,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.Visualizers,
  Atlas.IDE.Debug.DisplayRules,
  Atlas.IDE.Debug.StepInto,
  Atlas.IDE.Debug.StepFilter,
  Atlas.UI.Debug.Commands.Strings;

function DebugExceptionBarVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory and TAtlasIdeSettings.Current.DebugExceptionBanner;
end;
function DebugExceptionsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory;
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
procedure ToggleDebugJustMyCode;
begin
  TAtlasIdeDebugOwnCode.ToggleSetting(TAtlasIdeHost.Messages());
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
class function TAtlasDebugModule.Command(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := Guarded(ARun);
  Result.Visible := AVisible;
end;
class function TAtlasDebugModule.CommandWithKey(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>; const AKey: TFunc<Integer>): TAtlasModuleCommand;
begin
  Result := Command(AId, ACaption, ARun, AVisible);
  Result.Key := AKey;
end;

{ TAtlasDebugModule }

constructor TAtlasDebugModule.Create(const AHooks: TAtlasDebugModuleHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasDebugModule.Info: TAtlasModuleInfo;
begin
  // „Gezielt hineinspringen“ und die Befehle des Schrittfilters gab es schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Debugger', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
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
      TAtlasIdeDebugExceptionBar.ToggleIdeDialog, DebugExceptionBarVisible)];
  // Exception-Regeln, Fenster, Threads, Lauf, Haltepunkte und Werte aus den Teilen der Composition.
  Result := Result + FHooks.Commands();
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
/// Startverbünde; Profiler; Bericht einfügen, Debug-Zustand festhalten und Datei offen halten) und Untermenü
/// Haltepunkte, je Gruppe durch Trennlinien getrennt.
/// </summary>
function AtlasMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := AtlasEntries(['Atlas.DebugExceptions', 'Atlas.DebugEvaluate', 'Atlas.DebugVariables',
    'Atlas.DebugCallStack', 'Atlas.DebugParallelStacks', 'Atlas.DebugParallelWatch', 'Atlas.DebugEventLog',
    'Atlas.DebugLogpointValues', 'Atlas.DebugMemory', 'Atlas.DebugLeaks', 'Atlas.DebugObjectMarks', '-',
    'Atlas.DebugDeadlocks', '-', 'Atlas.DebugRestart', 'Atlas.LaunchGroups', 'Atlas.ConsoleOutput',
    'Atlas.ConsoleRunNoDebug', '-', 'Atlas.DebugProfile', 'Atlas.DebugProfileRun', 'Atlas.DebugProfileToggle', '-',
    'Atlas.RuntimeReportPaste', 'Atlas.DebugNote', 'Atlas.DebugKeepOpenedFile'],
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
  cWindows: array[0..14] of string = ('Atlas.DebugExceptions', 'Atlas.DebugEvaluate', 'Atlas.DebugVariables',
    'Atlas.DebugCallStack', 'Atlas.DebugParallelStacks', 'Atlas.DebugParallelWatch', 'Atlas.DebugEventLog',
    'Atlas.DebugLogpointValues', 'Atlas.DebugMemory', 'Atlas.DebugLeaks', 'Atlas.DebugObjectMarks',
    'Atlas.StepFilters', 'Atlas.DebugProfile', 'Atlas.BreakpointsWindow', 'Atlas.ConsoleOutput');
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
  // Ereignisprotokoll, Logpunkte, Neu starten und Laufzeitberichte (#580, #583, #872, #74), Haltepunkte und
  // Werte ändern (#868).
  Result := Result + FHooks.MenuEntries();
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
  // Lauf, bis hier, Haltepunkte überspringen (#851), Wert ändern mit F2 (#868).
  Result := Result + FHooks.Keys();
end;
procedure TAtlasDebugModule.ApplySettings;
begin
  // debug.breakOnNextEvent (#856), debug.explainUnavailable (#840), debug.completionInDialogs (#538),
  // debug.evaluateWindow.replaceCtrlF7 (#784), debug.memoryTimeline* (#858), debug.eventLog* (#580).
  FHooks.ApplySettings();
  // debug.exceptionHistory (#517).
  TAtlasIdeDebugExceptions.ApplySettings;
  // debug.exceptionBanner* (#783).
  TAtlasIdeDebugExceptionBar.ApplySettings;
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
  TAtlasIdeDebugStepFilter.ThemeChanged;
  // Fenster „Auswerten“ (#784), „Variablen“ (#853), „Atlas: Speicher“ (#858) und die übrigen Teile.
  FHooks.ThemeChanged();
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

end.
