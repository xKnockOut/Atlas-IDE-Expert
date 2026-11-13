unit Atlas.IDE.Debug.Composition.Breakpoints;

// Modul Debugger, Teil der Komposition: Anhalten und Haltepunkte. Teile der
// Feature-Tabelle, Befehle, Menüeinträge und Einstellungen für „Beim nächsten
// Ereignis anhalten“ (#856) und „Haltepunkte prüfen“ (#577).
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

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.EventBreak,
  Atlas.IDE.Debug.BreakpointCheck,
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

function BreakpointParts: TArray<IAtlasFeaturePart>;
begin
  Result := [BreakpointCheckPart];
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
      TAtlasIdeBreakpointCheck.Run, BreakpointCheckVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

function BreakpointMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [MenuEntry('Atlas.CheckBreakpoints', TAtlasMenuPlace.AtlasMenu)];
end;

procedure InstallBreakCommands;
begin
  TAtlasIdeEventBreak.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
end;

procedure UninstallBreakCommands;
begin
  TAtlasIdeEventBreak.Uninstall;
end;

procedure ApplyBreakSettings;
begin
  TAtlasIdeEventBreak.ApplySettings;
end;

end.
