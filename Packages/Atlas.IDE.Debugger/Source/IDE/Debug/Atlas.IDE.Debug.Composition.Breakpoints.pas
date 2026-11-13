unit Atlas.IDE.Debug.Composition.Breakpoints;

// Modul Debugger, Teil der Komposition: Anhalten und Haltepunkte. Teile der
// Feature-Tabelle, Befehle, Menüeinträge und Einstellungen für „Beim nächsten
// Ereignis anhalten“ (#856), „Haltepunkte prüfen“ (#577), Haltepunkt-Sätze
// (#586), „Bis hier ausführen“ (#851), das Haltepunktfenster (#863), „Haltepunkt nur für ein Objekt“
// (#857), Haltepunkte, die mit dem Code wandern (#841), Haltepunkt-Regeln (#864) und „Anhalten, wenn sich ein
// Feld ändert“ (#584).
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
/// <summary>Tastenkürzel: „Bis hier, Haltepunkte überspringen“ (#851).</summary>
function BreakpointKeys: TArray<TAtlasModuleKey>;
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
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.EventBreak,
  Atlas.IDE.Debug.BreakpointCheck,
  Atlas.IDE.Debug.BreakpointSets,
  Atlas.IDE.Debug.RunTo,
  Atlas.IDE.Debug.RunToColumn,
  Atlas.IDE.Debug.BreakpointList,
  Atlas.IDE.Debug.InstanceBreakpoint,
  Atlas.IDE.Debug.BreakpointAnchors,
  Atlas.IDE.Debug.BreakpointRules,
  Atlas.IDE.Debug.DataBreakpoint,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Strg+F4: nur im angehaltenen Zustand, sonst schließt die IDE wie gewohnt die Datei.</summary>
  cRunToSkipKey = $4073;

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

function RunToVisible: Boolean;
begin
  Result := TAtlasIdeRunTo.Enabled;
end;

procedure StartRunTo;
begin
  TAtlasIdeRunTo.Start(MessageLine);
  TAtlasIdeRunToColumn.Install;
end;

procedure ReleaseRunTo;
begin
  TAtlasIdeRunToColumn.Uninstall;
  TAtlasIdeRunTo.Release;
end;

function BreakpointAnchorsVisible: Boolean;
begin
  Result := TAtlasIdeBreakpointAnchors.Enabled;
end;

procedure StartBreakpointAnchors;
begin
  TAtlasIdeBreakpointAnchors.Start(MessageLine);
end;

function BreakpointRulesVisible: Boolean;
begin
  Result := TAtlasIdeBreakpointRules.Enabled;
end;

procedure StartBreakpointRules;
begin
  TAtlasIdeBreakpointRules.Start(MessageLine);
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

function DataBreakpointVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugDataBreakpoints;
end;

procedure StartDataBreakpoints;
begin
  TAtlasIdeDataBreakpoint.Start(MessageLine);
end;

/// <summary>Anhalten, wenn sich ein Feld ändert (#584): Datenhaltepunkte beobachten und am Ende der Sitzung
/// entfernen; aus = kein Zuhörer.</summary>
function DataBreakpointPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugDataBreakpoints',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugDataBreakpoints;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDataBreakpoint.Started;
    end, StartDataBreakpoints, TAtlasIdeDataBreakpoint.Release);
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

/// <summary>Bis hier ausführen (#851): Spalte im Rand, Befehle und Zurücksetzen nach dem Halt.</summary>
function RunToPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugRunTo',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugRunToClick;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeRunTo.Started;
    end, StartRunTo, ReleaseRunTo);
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

/// <summary>Haltepunkte wandern mit dem Code (#841): Anker und Nachziehen nach Änderungen von außen.</summary>
function BreakpointAnchorsPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugBreakpointAnchors',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugBreakpointAnchors;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeBreakpointAnchors.Started;
    end, StartBreakpointAnchors, TAtlasIdeBreakpointAnchors.Release);
end;

/// <summary>Abhängige Haltepunkte und Trefferbedingungen (#864): Befehl und Zuhörer der Sitzung.</summary>
function BreakpointRulesPart: IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugBreakpointRules',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugBreakpointRules;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeBreakpointRules.Started;
    end, StartBreakpointRules, TAtlasIdeBreakpointRules.Release);
end;

function BreakpointParts: TArray<IAtlasFeaturePart>;
begin
  Result := [BreakpointCheckPart, BreakpointSetsPart, RunToPart, BreakpointsWindowPart, InstanceBreakpointPart,
    BreakpointAnchorsPart, BreakpointRulesPart, DataBreakpointPart];
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
    // Haltepunkt-Sätze (#586).
    Command('Atlas.BreakpointSetSave', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSaveCommand),
      TAtlasIdeBreakpointSets.SaveSet, BreakpointSetsRunning),
    Command('Atlas.BreakpointSetSwitch', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSwitchCommand),
      TAtlasIdeBreakpointSets.SwitchSet, BreakpointSetsRunning),
    Command('Atlas.BreakpointSetAdd', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetAddCommand),
      TAtlasIdeBreakpointSets.AddSet, BreakpointSetsRunning),
    Command('Atlas.BreakpointSetDelete', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetDeleteCommand),
      TAtlasIdeBreakpointSets.DeleteSet, BreakpointSetsRunning),
    // Bis hier ausführen (#851); nur sichtbar, solange debug.runToClick an ist.
    Command('Atlas.RunToHere', TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToHereCommand), TAtlasIdeRunTo.RunHere,
      RunToVisible),
    Command('Atlas.RunToHereSkip', TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToSkipCommand),
      TAtlasIdeRunTo.RunHereSkip, RunToVisible),
    Command('Atlas.OnceBreakpoint', TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToOnceCommand),
      TAtlasIdeRunTo.SetOnce, RunToVisible),
    // Haltepunktfenster (#863); nur sichtbar, solange debug.breakpointsWindow an ist.
    Command('Atlas.BreakpointsWindow', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsWindowCommand),
      TAtlasIdeDebugBreakpointList.ShowWindow, BreakpointsWindowVisible),
    // Haltepunkt nur für ein Objekt (#857); nur sichtbar, solange debug.instanceBreakpoints an ist.
    Command('Atlas.BreakpointOnlyForObject', TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceObjectCommand),
      TAtlasIdeInstanceBreakpoint.RestrictToObject, InstanceBreakpointVisible),
    Command('Atlas.BreakpointOnlyIf', TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceFieldCommand),
      TAtlasIdeInstanceBreakpoint.RestrictToField, InstanceBreakpointVisible),
    // Haltepunkte wandern mit dem Code (#841); nur sichtbar, solange debug.breakpointAnchors an ist.
    Command('Atlas.BreakpointAnchorsUndo', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsUndoCommand),
      TAtlasIdeBreakpointAnchors.Undo, BreakpointAnchorsVisible),
    Command('Atlas.BreakpointAnchorsOrphans',
      TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsOrphansCommand),
      TAtlasIdeBreakpointAnchors.ShowOrphans, BreakpointAnchorsVisible),
    // Haltepunkt-Regeln (#864); nur sichtbar, solange debug.breakpointRules an ist.
    Command('Atlas.BreakpointRules', TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesCommand),
      TAtlasIdeBreakpointRules.Edit, BreakpointRulesVisible),
    // Anhalten, wenn sich ein Feld ändert (#584); der Text nennt den Ausdruck unter der Schreibmarke.
    Command('Atlas.BreakOnFieldChange', TAtlasIdeDataBreakpoint.CommandCaption, TAtlasIdeDataBreakpoint.WatchAtCursor,
      DataBreakpointVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Läuft eine Debug-Sitzung? Für „nur für ein Objekt“ (#857) muss das Programm angehalten sein.</summary>
function WhileDebugging(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.Debugging;
end;

/// <summary>Eintrag im Untermenü „Debuggen“ von Atlas im Kontextmenü des Editors; AWhen nil = immer.</summary>
function ContextEntry(const ACommandId: string; const AWhen: TAtlasMenuWhen): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEditorMenuGroup);
  Result.Group := 'debug';
  Result.When := AWhen;
end;

function BreakpointMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.CheckBreakpoints', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointSetSave', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointSetSwitch', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointsWindow', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointAnchorsOrphans', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointAnchorsUndo', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.BreakpointRules', TAtlasMenuPlace.AtlasMenu),
    // Bis hier ausführen (#851): die ersten beiden nur in einer Debug-Sitzung, der einmalige Haltepunkt immer.
    ContextEntry('Atlas.RunToHere', WhileDebugging),
    ContextEntry('Atlas.RunToHereSkip', WhileDebugging),
    ContextEntry('Atlas.OnceBreakpoint', nil),
    ContextEntry('Atlas.BreakpointOnlyForObject', WhileDebugging),
    ContextEntry('Atlas.BreakpointOnlyIf', WhileDebugging),
    ContextEntry('Atlas.BreakpointRules', nil),
    ContextEntry('Atlas.BreakOnFieldChange', WhileDebugging)];
end;

/// <summary>„Bis hier, Haltepunkte überspringen“ unter der Sicherung des Debuggers: nur im angehaltenen Zustand;
/// sonst (und nach einem Fehler) geht die Taste an die IDE.</summary>
function TryRunHereSkip: Boolean;
var
  mDone: Boolean;
begin
  mDone := False;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      mDone := TAtlasIdeRunTo.TryRunHereSkip;
    end);
  Result := mDone;
end;

function BreakpointKeys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  if not TAtlasIdeSettings.Current.DebugRunToClick then
  begin
    Exit;
  end;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.RunToHereSkip';
  mKey.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToSkipCommand);
  mKey.Key := cRunToSkipKey;
  mKey.Attempt :=
    function: Boolean
    begin
      Result := TryRunHereSkip;
    end;
  Result := [mKey];
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
