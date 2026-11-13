unit Atlas.IDE.Debug.Composition.Run;

// Modul Debugger, Teil der Komposition: Werkzeuge rund um den Lauf des
// Programms: das Ereignisprotokoll (#580), die Logpunkte (#583, mit Taste
// Umschalt+F5 und Schicht in der Rinne), das Fenster „Kein Quelltext“
// (#869), „Neu starten“ (#872, Strg+Umschalt+F2), „Erneut anhängen“ (#2171,
// Menü Start, Taste debug.reattach.key), Leck- und Absturzberichte aus der
// Zwischenablage (#74) und die Startverbünde (#867, F9 und Strg+F2 mit
// aktivem Verbund). Liefert Teile der
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
  Atlas.IDE.Debug.Reattach,
  Atlas.IDE.Debug.RuntimeReport,
  Atlas.IDE.Debug.LaunchGroups,
  Atlas.UI.Debug.Strings;

const
  cLogpointCommand = 'Atlas.Logpoint';
  cRestartCommand = 'Atlas.DebugRestart';
  cReattachCommand = 'Atlas.Reattach';
  cRuntimeReportCommand = 'Atlas.RuntimeReportPaste';
  cLaunchGroupsCommand = 'Atlas.LaunchGroups';
  cLaunchRunCommand = 'Atlas.LaunchGroupRun';
  cLaunchStopCommand = 'Atlas.LaunchGroupStop';

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

function ReattachVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugReattach;
end;

procedure StartReattach;
begin
  TAtlasIdeDebugReattach.Start(
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end, TAtlasStatusRegistry.Default);
end;

function LaunchGroupsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugLaunchGroups;
end;

procedure StartLaunchGroups;
begin
  TAtlasIdeLaunchGroups.Start(
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end, TAtlasStatusRegistry.Default);
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
      end, StartRestart, TAtlasIdeDebugRestart.Release),
    // Erneut anhängen (#2171): Zuhörer merkt angehängte Programme, Einträge im Menü Start, Warten im Hintergrund.
    TAtlasFeaturePart.When('DebugReattach',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and ReattachVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugReattach.Started;
      end, StartReattach, TAtlasIdeDebugReattach.Release),
    // Startverbünde (#867): mehrere Projekte nacheinander starten, Statusfeld und Leiste des Laufs.
    TAtlasFeaturePart.When('DebugLaunchGroups',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and LaunchGroupsVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeLaunchGroups.Started;
      end, StartLaunchGroups, TAtlasIdeLaunchGroups.Release)];
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
    RunCommand(cReattachCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachCommandPlain),
      TAtlasIdeDebugReattach.Execute, ReattachVisible),
    RunCommand('Atlas.ReattachWhenStarted', TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachWaitCommand),
      TAtlasIdeDebugReattach.WaitForStart, ReattachVisible),
    // Befehle auf Abruf ohne eigene Oberfläche: keine Einstellung.
    RunCommand(cRuntimeReportCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.RuntimeReportPasteCommand),
      PasteRuntimeReport(AScope), nil),
    RunCommand('Atlas.RuntimeReportClear', TAtlasDebugStrings.Text(TAtlasDebugTextId.RuntimeReportClearCommand),
      ClearRuntimeReport(AScope), nil),
    RunCommand(cLaunchGroupsCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchCommandWindow),
      TAtlasIdeLaunchGroups.ShowWindow, LaunchGroupsVisible),
    RunCommand(cLaunchRunCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchCommandRun),
      TAtlasIdeLaunchGroups.RunActive, LaunchGroupsVisible),
    RunCommand(cLaunchStopCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchCommandStop),
      TAtlasIdeLaunchGroups.StopAll, LaunchGroupsVisible)];
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
    MenuEntry(cRuntimeReportCommand, TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cLaunchGroupsCommand, TAtlasMenuPlace.AtlasMenu)];
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

/// <summary>Taste von „Erneut anhängen“ (#2171); 0, solange debug.reattach aus ist.</summary>
function ReattachKey: TShortCut;
begin
  Result := 0;
  if ReattachVisible then
  begin
    Result := TShortCut(TAtlasIdeSettings.Current.DebugReattachKey);
  end;
end;

/// <summary>Taste von „Erneut anhängen“; ohne laufenden Teil geht sie an die IDE.</summary>
function TryReattach: Boolean;
begin
  Result := ReattachVisible and TAtlasIdeDebugReattach.Started;
  if Result then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugReattach.Execute);
  end;
end;

/// <summary>Taste eines Startverbunds (#867); 0, solange debug.launchGroups aus ist.</summary>
function LaunchKey(AKey: Word; AShift: TShiftState): TShortCut;
begin
  Result := 0;
  if LaunchGroupsVisible then
  begin
    Result := ShortCut(AKey, AShift);
  end;
end;

/// <summary>F9 startet den aktiven Verbund, solange keine Sitzung läuft; sonst geht die Taste an die IDE.</summary>
function TryLaunchRun: Boolean;
begin
  Result := TAtlasIdeLaunchGroups.TryRun;
end;

/// <summary>Strg+F2 beendet alle Programme des Verbunds; ohne laufenden Verbund geht die Taste an die IDE.</summary>
function TryLaunchStop: Boolean;
begin
  Result := TAtlasIdeLaunchGroups.TryStop;
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
    ShortCut(VK_F2, [ssCtrl, ssShift]), TryRestart),
    RunKey(cReattachCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachCommandPlain), ReattachKey,
    TryReattach),
    RunKey(cLaunchRunCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchCommandRun), LaunchKey(VK_F9, []),
    TryLaunchRun),
    RunKey(cLaunchStopCommand, TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchCommandStop),
    LaunchKey(VK_F2, [ssCtrl]), TryLaunchStop)];
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
  TAtlasIdeLaunchGroups.ThemeChanged;
end;

end.
