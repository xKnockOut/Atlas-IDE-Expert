unit Shell.Monitor;

// Host-Rolle Shell: Einstieg von AtlasMonitor.exe (#1901), eigenständig neben der IDE. Eine Instanz je Benutzer:
// Ein zweiter Start zeigt das Fenster der ersten und endet. Sprache: --locale, sonst language aus settings.json,
// sonst Windows. Mit --tray (Start mit Windows) und Symbol im Infobereich startet das Programm ohne Fenster.
// Weder AtlasServer noch IDE starten AtlasMonitor; er findet die Server über ihre Statusdateien.

interface

type
  TMonitorShell = class
  public
    /// <summary>Läuft, bis der Benutzer das Programm beendet; liefert den Exit-Code.</summary>
    class function Run: Integer; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Settings,
  Atlas.Windows.Monitor.Adapters.System,
  Shell.Bootstrap,
  Shell.Monitor.MainForm;

const
  cMutexName = 'Local\AtlasMonitor';

/// <summary>Wert des Parameters AName (--name wert oder --name=wert); '' ohne.</summary>
function ParamValue(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to ParamCount do
  begin
    if SameText(ParamStr(mIndex), AName) and (mIndex < ParamCount) then
    begin
      Exit(ParamStr(mIndex + 1));
    end;
    if ParamStr(mIndex).StartsWith(AName + '=', True) then
    begin
      Exit(ParamStr(mIndex).Substring(Length(AName) + 1));
    end;
  end;
end;

/// <summary>Sprache der Texte; eine unlesbare settings.json zählt als leer.</summary>
procedure UseLanguage;
var
  mGlobal: string;
begin
  try
    mGlobal := TShellBootstrap.LoadGlobalSettings(nil);
  except
    // lsp-ignore: catch-all-without-raise -- unlesbare settings.json: Sprache von Windows
    on Exception do
      mGlobal := '';
  end;
  TAtlasLocale.Use(TMonitorSettings.LanguageOf(ParamValue('--locale'), mGlobal, TMonitorSystem.UiLanguageCode));
end;

/// <summary>Zeigt das Fenster einer schon laufenden Instanz.</summary>
procedure ShowRunningInstance;
var
  mWindow: HWND;
begin
  mWindow := FindWindow(PChar(TAtlasMonitorForm.ClassName), nil);
  if mWindow <> 0 then
  begin
    PostMessage(mWindow, TAtlasMonitorForm.ShowMessageId, 0, 0);
  end;
end;

class function TMonitorShell.Run: Integer;
var
  mMutex: THandle;
  mForm: TAtlasMonitorForm;
  mSettings: TMonitorSettings;
begin
  Result := 0;
  mMutex := CreateMutex(nil, False, cMutexName);
  try
    if GetLastError = ERROR_ALREADY_EXISTS then
    begin
      ShowRunningInstance;
      Exit;
    end;
    UseLanguage;
    mSettings := TMonitorSettings.Load(TMonitorSettings.FileIn(GetEnvironmentVariable('APPDATA')));
    Application.Initialize;
    Application.MainFormOnTaskBar := True;
    Application.Title := 'Atlas Monitor';
    // Start mit Windows: nur das Symbol, das Fenster öffnet ein Doppelklick.
    Application.ShowMainForm := not (FindCmdLineSwitch('tray') and mSettings.TrayIcon);
    Application.CreateForm(TAtlasMonitorForm, mForm);
    Application.Run;
  finally
    if mMutex <> 0 then
    begin
      CloseHandle(mMutex);
    end;
  end;
end;

end.
