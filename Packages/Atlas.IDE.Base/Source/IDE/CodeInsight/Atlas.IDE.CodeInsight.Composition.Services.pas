unit Atlas.IDE.CodeInsight.Composition.Services;

// Dienste von Base für die Module (#1455) über TAtlasIdeHost: Sitzungen und Anfragen an den Server, Protokoll und
// Meldungen, Statusfeld, Compile-Ereignisse, Palette, Tastenübersicht, Ausblenden (#628), Snippets und die Knöpfe
// der Zustandskachel (#754). Die Dienste fragen ihre Quellen bei jedem Aufruf neu.

interface

/// <summary>Dienste anmelden; vor den Modulen, sie fragen Sitzung und Protokoll über TAtlasIdeHost.</summary>
procedure InstallHost;
/// <summary>Dienste abmelden; erst nach den Modulen.</summary>
procedure UninstallHost;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Build.Events,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Build,
  Atlas.IDE.CodeInsight.Composition.Tools,
  Atlas.IDE.CodeInsight.Composition.Palette,
  Atlas.IDE.CodeInsight.Composition.Drawing;

/// <summary>„Einstellungen“ der Zustandskachel (#754): Optionsseite „Atlas“ (#227) wie Menü Atlas › Einstellungen.
/// </summary>
procedure OpenAtlasOptions;
var
  mOptions: IOTAEnvironmentOptions140;
  mServices: IOTAServices;
begin
  if Supports(BorlandIDEServices, IOTAServices, mServices) and
    Supports(mServices.GetEnvironmentOptions, IOTAEnvironmentOptions140, mOptions) then
  begin
    mOptions.EditOptions('', 'Atlas');
  end;
end;

/// <summary>„Log-Ordner öffnen“ der Zustandskachel (#754): %LOCALAPPDATA%\Atlas\Logs im Explorer.</summary>
procedure OpenLogFolder;
var
  mFolder: string;
begin
  mFolder := TAtlasRotatingLog.DefaultFolder;
  ForceDirectories(mFolder);
  ShellExecute(0, 'open', PChar(mFolder), nil, nil, SW_SHOWNORMAL);
end;

function IndexedUnits: Integer;
begin
  Result := -1;
  if StatusLines <> nil then
  begin
    Result := StatusLines.Units;
  end;
end;

procedure RestartServer;
begin
  if Manager <> nil then
  begin
    Manager.RestartServer;
  end;
  RequestStatusRefresh;
end;

procedure ShowKeyMap;
begin
  if KeyMap <> nil then
  begin
    KeyMap.ShowAll;
  end;
end;

function FileSnippets: TAtlasSnippetList;
begin
  Result := nil;
  if (Manager <> nil) and (Manager.Completion <> nil) then
  begin
    Result := Manager.Completion.FileSnippets;
  end;
end;

procedure OpenUpdate;
begin
  if Updates <> nil then
  begin
    Updates.OpenUpdate;
  end;
end;

function StatusLinesReady: Boolean;
begin
  Result := StatusLines <> nil;
end;

function CompileEvents: TAtlasCompileEvents;
begin
  Result := nil;
  if Compile <> nil then
  begin
    Result := Compile.Events;
  end;
end;

/// <summary>Zustand des Servers, Palette, Tastenübersicht, Ausblenden, Snippets und die Knöpfe der
/// Zustandskachel.</summary>
procedure InstallShellServices(var AServices: TAtlasHostServices);
begin
  AServices.ServerInfo := ServerInfo;
  AServices.ServerIndexing := ServerIndexing;
  AServices.IndexedUnits := IndexedUnits;
  AServices.RestartServer := RestartServer;
  AServices.PaletteCommands := PaletteCommands;
  AServices.ExecuteCommand :=
    procedure(AId: string)
    begin
      ExecutePaletteCommand(AId);
    end;
  AServices.ShowPalette := ShowPalette;
  AServices.ShowKeyMap := ShowKeyMap;
  AServices.HideSetting := HideSetting;
  AServices.FileSnippets := FileSnippets;
  AServices.OpenOptions := OpenAtlasOptions;
  AServices.OpenLogFolder := OpenLogFolder;
  AServices.OpenUpdate := OpenUpdate;
  AServices.ShowMessages := ShowAtlasMessages;
  // Zustandskachel der Willkommensseite (#754): beobachtet die Zeilen des Statusfelds.
  AServices.StatusLinesReady := StatusLinesReady;
end;

/// <summary>Anfrage der Module, etwa der Abfrage (#1351): abbrechbar, nur an den laufenden Server.</summary>
function RunRequest(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal; const ACancelled: TFunc<Boolean>;
  const ADone: TProc<string>): Boolean;
begin
  Result := (Manager <> nil) and (Manager.RunningSession <> nil);
  if Result then
  begin
    Manager.RunServerRequestAsync(AMethod, AParamsJson, ATimeoutMs, ACancelled, AnswerText(ADone));
  end;
end;

/// <summary>Der eine Hintergrundbefehl des Managers.</summary>
function RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<string>): Boolean;
begin
  Result := (Manager <> nil) and Manager.RunCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
end;

/// <summary>Nebenläufig zu RunCommand (#1455): Fenster, die regelmäßig nachfragen (Unit-Beziehungen, Hotspots),
/// belegen nicht den einen Hintergrundbefehl.</summary>
function RunParallelCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<string>): Boolean;
begin
  Result := (Manager <> nil) and (Manager.RunningSession <> nil);
  if Result then
  begin
    Manager.RunServerCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, AnswerText(ADone));
  end;
end;

procedure InstallHost;
var
  mServices: TAtlasHostServices;
begin
  mServices := Default(TAtlasHostServices);
  mServices.Session := RunningSession;
  mServices.ActiveSession := ActiveSession;
  mServices.Log := LogLines();
  mServices.Warning := Warnings();
  mServices.Report := Reports();
  mServices.RunRequest := RunRequest;
  mServices.RunCommand := RunCommand;
  mServices.RunServerCommand := RunParallelCommand;
  // Felder der Module im Atlas-Statusfeld, etwa Hinweise der schnellen Lesezeichen (#1104).
  mServices.StatusExtra := SetStatusItem;
  mServices.CompileEvents := CompileEvents;
  InstallShellServices(mServices);
  TAtlasIdeHost.Install(mServices);
end;

procedure UninstallHost;
begin
  TAtlasIdeHost.Uninstall;
end;

end.
