unit Atlas.IDE.Debug.Composition.Run;

// Modul Debugger, Teil der Komposition: Werkzeuge rund um den Lauf des
// Programms: das Ereignisprotokoll (#580), die Logpunkte (#583, mit Taste
// Umschalt+F5 und Schicht in der Rinne), das Fenster „Kein Quelltext“
// (#869), „Neu starten“ (#872, Strg+Umschalt+F2) und Leck- und
// Absturzberichte aus der Zwischenablage (#74). Liefert Teile der
// Feature-Tabelle, Befehle, Menüeinträge, Tasten und das Weiterreichen von
// Einstellungen und Thema; Atlas.IDE.Debug.Composition stellt sie über den
// Scope des Moduls bereit, die Schicht der Rinne stellt ProvideRun bereit.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

/// <summary>Teile in ihrer Startreihenfolge.</summary>
function RunParts: TArray<IAtlasFeaturePart>;
/// <summary>AScope liefert den Scope des Moduls für Antworten des Servers.</summary>
function RunCommands(const AScope: TFunc<IAtlasModuleScope>): TArray<TAtlasModuleCommand>;
function RunMenuEntries: TArray<TAtlasMenuEntry>;
function RunKeys: TArray<TAtlasModuleKey>;
/// <summary>Schicht der Logpunkte in der Rinne (#583) über AScope bereitstellen.</summary>
procedure ProvideRun(const AScope: IAtlasModuleScope);
procedure ApplyRunSettings;
procedure RunThemeChanged;

implementation

uses
  System.Classes,
  Winapi.Windows,
  Vcl.Menus,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Status.Registry,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.EventLog,
  Atlas.IDE.Debug.Logpoints,
  Atlas.IDE.Debug.LogpointGutter,
  Atlas.IDE.Debug.NoSource,
  Atlas.IDE.Debug.Restart,
  Atlas.IDE.Debug.RuntimeReport,
  Atlas.UI.Debug.Strings;

const
  cLogpointCommand = 'Atlas.Logpoint';
  cRestartCommand = 'Atlas.DebugRestart';
  cRuntimeReportCommand = 'Atlas.RuntimeReportPaste';

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

procedure StartEventLog;
begin
  TAtlasIdeDebugEventLog.Start(EventLogServices);
end;

function LogpointsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugLogpoints;
end;

procedure StartNoSource;
begin
  TAtlasIdeDebugNoSource.Start(
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end);
end;

function RestartVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugRestart;
end;

procedure StartRestart;
begin
  TAtlasIdeDebugRestart.Start(
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end);
end;

procedure StartLogpoints;
begin
  TAtlasIdeLogpoints.Start(
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end);
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
      end, StartEventLog, TAtlasIdeDebugEventLog.Release),
    // Logpunkte (#583): Haltepunkte der IDE ohne Anhalten, Text im Ereignisprotokoll.
    TAtlasFeaturePart.When('DebugLogpoints',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and LogpointsVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeLogpoints.Started;
      end, StartLogpoints, TAtlasIdeLogpoints.Release),
    // Fenster „Kein Quelltext“ (#869): Zuhörer der Debug-Sitzung.
    TAtlasFeaturePart.When('DebugNoSource',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugNoSourcePage;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugNoSource.Started;
      end, StartNoSource, TAtlasIdeDebugNoSource.Release),
    // Neu starten (#872): Befehl und Taste; der Zuhörer merkt Haltepunkte und Ende der Sitzung.
    TAtlasFeaturePart.When('DebugRestart',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and RestartVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugRestart.Started;
      end, StartRestart, TAtlasIdeDebugRestart.Release)];
end;

/// <summary>Leck- oder Absturzbericht aus der Zwischenablage (#74).</summary>
function PasteRuntimeReport(const AScope: TFunc<IAtlasModuleScope>): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeRuntimeReport.Paste(AScope());
    end;
end;

function ClearRuntimeReport(const AScope: TFunc<IAtlasModuleScope>): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeRuntimeReport.Clear(AScope());
    end;
end;

function RunCommands(const AScope: TFunc<IAtlasModuleScope>): TArray<TAtlasModuleCommand>;
begin
  Result := [
    RunCommand('Atlas.DebugEventLog', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogCommand),
      TAtlasIdeDebugEventLog.ShowWindow, EventLogVisible),
    RunCommand(cLogpointCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointCommand),
      TAtlasIdeLogpoints.SetAtCursor, LogpointsVisible),
    RunCommand('Atlas.LogpointsDisable', TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointDisableAll),
      TAtlasIdeLogpoints.DisableAll, LogpointsVisible),
    RunCommand('Atlas.LogpointsEnable', TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointEnableAll),
      TAtlasIdeLogpoints.EnableAll, LogpointsVisible),
    RunCommand('Atlas.LogpointsDelete', TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointDeleteAll),
      TAtlasIdeLogpoints.DeleteAll, LogpointsVisible),
    RunCommand(cRestartCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartCommand),
      TAtlasIdeDebugRestart.Execute, RestartVisible),
    // Befehle auf Abruf ohne eigene Oberfläche: keine Einstellung.
    RunCommand(cRuntimeReportCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.RuntimeReportPasteCommand),
      PasteRuntimeReport(AScope), nil),
    RunCommand('Atlas.RuntimeReportClear', TAtlasDebugStrings.Text(TAtlasDebugTextId.RuntimeReportClearCommand),
      ClearRuntimeReport(AScope), nil)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

function RunMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [MenuEntry('Atlas.DebugEventLog', TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cLogpointCommand, TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cLogpointCommand, TAtlasMenuPlace.EditorContext),
    MenuEntry(cRestartCommand, TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cRuntimeReportCommand, TAtlasMenuPlace.AtlasMenu)];
end;

/// <summary>Umschalt+F5 setzt einen Logpunkt, solange debug.logpoints an ist; sonst geht die Taste an die IDE.
/// </summary>
function TryLogpoint: Boolean;
begin
  Result := LogpointsVisible and TAtlasIdeLogpoints.Started;
  if Result then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeLogpoints.SetAtCursor);
  end;
end;

/// <summary>Strg+Umschalt+F2 startet neu, solange debug.restart an ist; sonst geht die Taste an die IDE.</summary>
function TryRestart: Boolean;
begin
  Result := RestartVisible and TAtlasIdeDebugRestart.Started;
  if Result then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugRestart.Execute);
  end;
end;

function RunKey(const AId, ACaption: string; AKey: TShortCut; const AAttempt: TFunc<Boolean>): TAtlasModuleKey;
begin
  Result := Default(TAtlasModuleKey);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Key := AKey;
  Result.Attempt := AAttempt;
end;

function RunKeys: TArray<TAtlasModuleKey>;
begin
  Result := [RunKey(cLogpointCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointCommand),
    ShortCut(VK_F5, [ssShift]), TryLogpoint),
    RunKey(cRestartCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartCommand),
    ShortCut(VK_F2, [ssCtrl, ssShift]), TryRestart)];
end;

procedure ProvideRun(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasGutterLayer, TAtlasIdeLogpointGutter.Create as IAtlasGutterLayer);
end;

procedure ApplyRunSettings;
begin
  // debug.eventLog aus: Fenster zu; debug.eventLogColors: neu zeichnen.
  TAtlasIdeDebugEventLog.ApplySettings;
end;

procedure RunThemeChanged;
begin
  TAtlasIdeDebugEventLog.ThemeChanged;
  TAtlasIdeDebugNoSource.ThemeChanged;
  TAtlasIdeDebugRestart.ThemeChanged;
end;

end.
