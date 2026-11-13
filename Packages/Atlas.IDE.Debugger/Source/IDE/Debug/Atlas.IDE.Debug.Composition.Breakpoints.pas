unit Atlas.IDE.Debug.Composition.Breakpoints;

// Modul Debugger, Teil der Komposition: Anhalten und Haltepunkte. Teile der
// Feature-Tabelle, Befehle, Menüeinträge und Einstellungen für „Beim nächsten
// Ereignis anhalten“ (#856), „Haltepunkte prüfen“ (#577), „Haltepunkt auf
// Methoden“ (#855), Haltepunkt-Sätze (#586), das Haltepunktfenster (#863) und
// „Haltepunkt nur für ein Objekt“ (#857).
// Atlas.IDE.Debug.Composition hängt die Befehle unter die Sicherung des
// Debuggers, ruft Install/Uninstall mit seinen übrigen Befehlen und stellt
// alles über den Scope des Moduls bereit.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Teile für Haltepunkte in ihrer Startreihenfolge.</summary>
function BreakpointParts: TArray<IAtlasFeaturePart>;
/// <summary>Befehle für Haltepunkte, noch ohne Sicherung.</summary>
function BreakpointCommands: TArray<TAtlasModuleCommand>;
/// <summary>Einträge im Atlas-Menü und im Kontextmenü des Editors.</summary>
function BreakpointMenuEntries: TArray<TAtlasMenuEntry>;
/// <summary>Befehle mit eigenem Zustand anlegen bzw. abbauen (mit den übrigen Befehlen des Moduls).</summary>
procedure InstallBreakCommands;
procedure UninstallBreakCommands;
/// <summary>Einstellungen übernehmen.</summary>
procedure ApplyBreakSettings;
/// <summary>IDE-Thema gewechselt: Fenster der Haltepunkte nachziehen.</summary>
procedure BreakpointsThemeChanged;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.EventBreak,
  Atlas.IDE.Debug.BreakpointCheck,
  Atlas.IDE.Debug.MethodBreakpoints,
  Atlas.IDE.Debug.BreakpointSets,
  Atlas.IDE.Debug.BreakpointList,
  Atlas.IDE.Debug.InstanceBreakpoint,
  Atlas.UI.Debug.Strings;

procedure MessageLine(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

function Session: TLspSession;
begin
  Result := TAtlasIdeHost.RunningSession;
end;

function BreakOnNextEventVisible: Boolean;
begin
  Result := TAtlasIdeEventBreak.Enabled;
end;

function BreakpointCheckVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugCheckBreakpoints;
end;

function BreakpointSetsRunning: Boolean;
begin
  Result := TAtlasIdeBreakpointSets.Started;
end;

procedure StartBreakpointSets;
begin
  TAtlasIdeBreakpointSets.Start(MessageLine);
end;

procedure StartBreakpointCheck;
begin
  TAtlasIdeBreakpointCheck.Start(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
end;

/// <summary>Haltepunkte, die nicht greifen werden (#577): Prüfung vor dem Start; aus = Start wie bisher.</summary>
function BreakpointCheckPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugBreakpointCheck',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugCheckBreakpoints;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeBreakpointCheck.Started;
    end, StartBreakpointCheck, TAtlasIdeBreakpointCheck.Release);
end;

function MethodBreakpointsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugMethodBreakpoints;
end;

procedure StartMethodBreakpoints;
begin
  TAtlasIdeMethodBreakpoints.Start(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
end;

/// <summary>Haltepunkte auf Methoden nach Muster (#855): Gruppen laden und beim Start mitwachsen; aus = keine
/// Befehle, kein Zuhörer.</summary>
function MethodBreakpointsPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugMethodBreakpoints',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugMethodBreakpoints;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeMethodBreakpoints.Started;
    end, StartMethodBreakpoints, TAtlasIdeMethodBreakpoints.Release);
end;

function InstanceBreakpointVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugInstanceBreakpoints;
end;

procedure StartInstanceBreakpoints;
begin
  TAtlasIdeInstanceBreakpoint.Start(MessageLine);
end;

/// <summary>Haltepunkt nur für ein Objekt (#857): Frage zu Adressbedingungen vor dem Start; aus = kein Zuhörer.
/// </summary>
function InstanceBreakpointPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugInstanceBreakpoints',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugInstanceBreakpoints;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeInstanceBreakpoint.Started;
    end, StartInstanceBreakpoints, TAtlasIdeInstanceBreakpoint.Release);
end;

/// <summary>Haltepunkt-Sätze (#586): Befehle und Beobachtung des Branchs.</summary>
function BreakpointSetsPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugBreakpointSets',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeBreakpointSets.Started;
    end, StartBreakpointSets, TAtlasIdeBreakpointSets.Release);
end;

function BreakpointsWindowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugBreakpointsWindow;
end;

/// <summary>Haltepunktfenster (#863): Sitzung beobachten, Etiketten laden; aus = kein Fenster.</summary>
function BreakpointsWindowPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugBreakpointsWindow',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugBreakpointsWindow;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugBreakpointList.Started;
    end, TAtlasIdeDebugBreakpointList.Start, TAtlasIdeDebugBreakpointList.Release);
end;

function BreakpointParts: TArray<IAtlasFeaturePart>;
begin
  Result := [BreakpointCheckPart, MethodBreakpointsPart, BreakpointSetsPart, BreakpointsWindowPart,
    InstanceBreakpointPart];
end;

function Command(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

function BreakpointCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Beim nächsten Ereignis anhalten (#856); nur sichtbar, solange debug.breakOnNextEvent an ist.
    Command('Atlas.BreakOnNextEvent', TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakCommand),
      TAtlasIdeEventBreak.Run, BreakOnNextEventVisible),
    // Haltepunkte prüfen (#577); nur sichtbar, solange debug.checkBreakpoints an ist.
    Command('Atlas.CheckBreakpoints', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckCommand),
      TAtlasIdeBreakpointCheck.Run, BreakpointCheckVisible),
    // Haltepunkt auf Methoden (#855); nur sichtbar, solange debug.methodBreakpoints an ist.
    Command('Atlas.MethodBreakpoints', TAtlasDebugStrings.Text(TAtlasDebugTextId.MethodBreakpointsCommand),
      TAtlasIdeMethodBreakpoints.Run, MethodBreakpointsVisible),
    Command('Atlas.MethodBreakpointGroups',
      TAtlasDebugStrings.Text(TAtlasDebugTextId.MethodBreakpointsGroupsCommand), TAtlasIdeMethodBreakpoints.RunGroups,
      MethodBreakpointsVisible),
    // Haltepunkt-Sätze (#586).
    Command('Atlas.BreakpointSetSave', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSaveCommand),
      TAtlasIdeBreakpointSets.SaveSet, BreakpointSetsRunning),
    Command('Atlas.BreakpointSetSwitch', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSwitchCommand),
      TAtlasIdeBreakpointSets.SwitchSet, BreakpointSetsRunning),
    Command('Atlas.BreakpointSetAdd', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetAddCommand),
      TAtlasIdeBreakpointSets.AddSet, BreakpointSetsRunning),
    Command('Atlas.BreakpointSetDelete', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetDeleteCommand),
      TAtlasIdeBreakpointSets.DeleteSet, BreakpointSetsRunning),
    // Haltepunktfenster (#863); nur sichtbar, solange debug.breakpointsWindow an ist.
    Command('Atlas.BreakpointsWindow', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsWindowCommand),
      TAtlasIdeDebugBreakpointList.ShowWindow, BreakpointsWindowVisible),
    // Haltepunkt nur für ein Objekt (#857); nur sichtbar, solange debug.instanceBreakpoints an ist.
    Command('Atlas.BreakpointOnlyForObject', TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceObjectCommand),
      TAtlasIdeInstanceBreakpoint.RestrictToObject, InstanceBreakpointVisible),
    Command('Atlas.BreakpointOnlyIf', TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceFieldCommand),
      TAtlasIdeInstanceBreakpoint.RestrictToField, InstanceBreakpointVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Haltepunkt auf Methoden (#855) auch im Kontextmenü des Editors, Untermenü „Debuggen“, ohne laufende
/// Sitzung: Das Wort am Cursor wird zum Startmuster.</summary>
function MethodBreakpointsContextEntry: TAtlasMenuEntry;
begin
  Result := MenuEntry('Atlas.MethodBreakpoints', TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEditorMenuGroup);
  Result.Group := 'debug';
end;

/// <summary>Ist das Programm angehalten? Nur dann gibt es ein Self.</summary>
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

function BreakpointMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.CheckBreakpoints', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.MethodBreakpoints', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.MethodBreakpointGroups', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointSetSave', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointSetSwitch', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointsWindow', TAtlasMenuPlace.AtlasMenu),
    MethodBreakpointsContextEntry,
    ContextEntry('Atlas.BreakpointOnlyForObject'), ContextEntry('Atlas.BreakpointOnlyIf')];
end;

procedure InstallBreakCommands;
begin
  TAtlasIdeEventBreak.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  TAtlasIdeDebugBreakpointList.Install(MessageLine);
end;

procedure UninstallBreakCommands;
begin
  TAtlasIdeDebugBreakpointList.Uninstall;
  TAtlasIdeEventBreak.Uninstall;
end;

procedure ApplyBreakSettings;
begin
  TAtlasIdeEventBreak.ApplySettings;
  TAtlasIdeDebugBreakpointList.ApplySettings;
end;

procedure BreakpointsThemeChanged;
begin
  TAtlasIdeDebugBreakpointList.ThemeChanged;
end;

end.
