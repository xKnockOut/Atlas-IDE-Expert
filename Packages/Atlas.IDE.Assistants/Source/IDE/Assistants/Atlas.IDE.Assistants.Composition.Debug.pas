unit Atlas.IDE.Assistants.Composition.Debug;

// Teil „AssistantDebug“ des Moduls KI-Assistenten (#1874), aus Atlas.IDE.Assistants.Composition gelöst: Eingang
// der MCP-Werkzeuge debug_* und die Leiste „KI-Assistent debuggt“ im Editor (debug.mcp.banner). Ausgeführt wird
// über IAtlasDebugControl des Moduls Debugger, das der Eingang bei jedem Auftrag neu in der Registry sucht
// (Regel 2); Rechte aus debug.mcp.sideEffects, .modify, .attach.

interface

uses
  Atlas.IDE.Assistants.DebugBar;

/// <summary>Eingang und Leiste anlegen; APaused = Pause für KI-Assistenten (#1906) schon an.</summary>
procedure StartDebug(APaused: Boolean);
/// <summary>Zuerst die Leiste, dann den Eingang freigeben.</summary>
procedure StopDebug;
function DebugStarted: Boolean;
/// <summary>Leiste neu zeichnen (Auftrag geändert, debug.mcp.banner).</summary>
procedure DebugChanged;
/// <summary>Pause für KI-Assistenten (#1906) an den Eingang, solange er läuft.</summary>
procedure SetDebugPaused(APaused: Boolean);
/// <summary>Leiste „KI-Assistent debuggt“; nil, solange der Teil nicht läuft.</summary>
function CurrentDebugBar: TAtlasIdeAssistantDebugBar;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Assistants.DebugGate,
  Atlas.IDE.Base.Foundation.DebugControl,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.DebugInbox;

var
  GDebugInbox: TAtlasIdeDebugInbox;
  GDebugBar: TAtlasIdeAssistantDebugBar;

/// <summary>Debugger des Moduls Debugger; nil, solange es fehlt oder nicht läuft.</summary>
function DebugControl: IAtlasDebugControl;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasDebugControl) do
  begin
    if Supports(mItem, IAtlasDebugControl, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Rechte des Assistenten aus den Einstellungen, bei jedem Auftrag neu gelesen.</summary>
function DebugRights: TAtlasDebugRights;
begin
  Result := TAtlasDebugRights.Make(TAtlasIdeSettings.Current.DebugMcpSideEffects,
    TAtlasIdeSettings.Current.DebugMcpModify, TAtlasIdeSettings.Current.DebugMcpAttach);
end;

procedure DebugChanged;
begin
  if GDebugBar <> nil then
  begin
    GDebugBar.Refresh;
  end;
end;

function DebugInbox: TAtlasIdeDebugInbox;
begin
  Result := GDebugInbox;
end;

function DebugBanner: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugMcpBanner;
end;

procedure StartDebug(APaused: Boolean);
begin
  GDebugInbox := TAtlasIdeDebugInbox.Create(DebugControl, DebugRights, DebugChanged,
    procedure(const AMessage: string)
    begin
      TAtlasIdeHost.Warning(AMessage);
    end);
  GDebugBar := TAtlasIdeAssistantDebugBar.Create(DebugInbox, DebugBanner);
  // Die Pause für KI-Assistenten (#1906) gilt auch für Debug-Aufträge.
  if APaused then
  begin
    GDebugInbox.SetPaused(True);
  end;
end;

procedure StopDebug;
begin
  // Zuerst die Leiste: Der Eingang meldet beim Abbau noch eine Änderung.
  FreeAndNil(GDebugBar);
  FreeAndNil(GDebugInbox);
end;

function DebugStarted: Boolean;
begin
  Result := GDebugInbox <> nil;
end;

procedure SetDebugPaused(APaused: Boolean);
begin
  if GDebugInbox <> nil then
  begin
    GDebugInbox.SetPaused(APaused);
  end;
end;

function CurrentDebugBar: TAtlasIdeAssistantDebugBar;
begin
  Result := GDebugBar;
end;

end.
