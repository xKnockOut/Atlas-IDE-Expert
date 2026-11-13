unit Atlas.IDE.Debug.Composition.Run;

// Modul Debugger, Teil der Komposition: Werkzeuge rund um den Lauf des
// Programms: Start der Exception-Leiste (#783, mit dem Feld in der
// Statusleiste) und das Ereignisprotokoll (#580). Liefert Teile der
// Feature-Tabelle, Befehle, Menüeinträge und das Weiterreichen von
// Einstellungen und Thema; Atlas.IDE.Debug.Composition stellt sie über den
// Scope des Moduls bereit.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Exception-Leiste starten (#783); Teil DebugExceptionBar der Komposition.</summary>
procedure StartDebugExceptionBar;
/// <summary>Teile in ihrer Startreihenfolge.</summary>
function RunParts: TArray<IAtlasFeaturePart>;
function RunCommands: TArray<TAtlasModuleCommand>;
function RunMenuEntries: TArray<TAtlasMenuEntry>;
procedure ApplyRunSettings;
procedure RunThemeChanged;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Status.Registry,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.EventLog,
  Atlas.UI.Debug.Strings;

{ Dienste von Base }

function EventLogServices: TAtlasEventLogServices;
begin
  Result := Default(TAtlasEventLogServices);
  Result.Message :=
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end;
  Result.Log :=
    procedure(AText: string)
    begin
      TAtlasIdeHost.Log(AText);
    end;
  // Fragt den Server nur, wenn er ohnehin läuft.
  Result.Session :=
    function: TLspSession
    begin
      Result := TAtlasIdeHost.RunningSession;
    end;
end;

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

function EventLogVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugEventLog;
end;

procedure StartDebugExceptionBar;
begin
  TAtlasIdeDebugExceptionBar.Start(
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end, TAtlasStatusRegistry.Default);
end;

procedure StartEventLog;
begin
  TAtlasIdeDebugEventLog.Start(EventLogServices);
end;

/// <summary>Befehl abgesichert ausführen (#493): eine Ausnahme schaltet nur die Debugger-Funktionen ab.</summary>
function RunCommand(const AId, ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, ARun);
    end;
  Result.Visible := AVisible;
end;

function RunParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Ereignisprotokoll (#580): Zuhörer der Debug-Sitzung, Mitlesen erst mit einer Sitzung.
    TAtlasFeaturePart.When('DebugEventLog',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and EventLogVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugEventLog.Started;
      end, StartEventLog, TAtlasIdeDebugEventLog.Release)];
end;

function RunCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    RunCommand('Atlas.DebugEventLog', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogCommand),
      TAtlasIdeDebugEventLog.ShowWindow, EventLogVisible)];
end;

function RunMenuEntries: TArray<TAtlasMenuEntry>;
var
  mEntry: TAtlasMenuEntry;
begin
  mEntry := Default(TAtlasMenuEntry);
  mEntry.CommandId := 'Atlas.DebugEventLog';
  mEntry.Place := TAtlasMenuPlace.AtlasMenu;
  Result := [mEntry];
end;

procedure ApplyRunSettings;
begin
  // debug.eventLog aus: Fenster zu; debug.eventLogColors: neu zeichnen.
  TAtlasIdeDebugEventLog.ApplySettings;
end;

procedure RunThemeChanged;
begin
  TAtlasIdeDebugEventLog.ThemeChanged;
end;

end.
