unit Atlas.Windows.Monitor.Adapters.System;

// Platform-Feature "Monitor" (#1901), Adapter: was AtlasMonitor vom System braucht. Läuft ein Prozess noch, ist er
// ein AtlasServer (nur solche beendet der Monitor, eine wiederverwendete Prozessnummer bleibt unberührt), Prozess
// beenden, Sprache der Oberfläche von Windows, Autostart über HKCU\...\Run und Ordner bzw. Datei mit dem
// zugeordneten Programm öffnen, ein Programm mit Befehlszeile starten (Editor für einen Befund, #1900).

interface

uses
  System.SysUtils;

type
  TMonitorSystem = record
  public const
    cServerExe = 'AtlasServer.exe';
    cRunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
    cRunValue = 'AtlasMonitor';
  public
    class function IsRunning(APid: Cardinal): Boolean; static;
    /// <summary>True, wenn APid läuft und ein AtlasServer.exe ist.</summary>
    class function IsAtlasServer(APid: Cardinal): Boolean; static;
    /// <summary>Beendet APid hart, aber nur einen AtlasServer; False sonst oder bei fehlendem Recht.</summary>
    class function TerminateServer(APid: Cardinal): Boolean; static;
    /// <summary>Sprache der Oberfläche von Windows als Kennung („de“, „en“).</summary>
    class function UiLanguageCode: string; static;
    /// <summary>Startet AtlasMonitor mit der Anmeldung (Wert im Run-Schlüssel des Benutzers).</summary>
    class function StartsWithWindows: Boolean; static;
    /// <summary>Trägt ACommandLine ein bzw. entfernt den Eintrag; False bei einem Fehler.</summary>
    class function SetStartWithWindows(AEnabled: Boolean; const ACommandLine: string): Boolean; static;
    /// <summary>Öffnet AFileName (Datei oder Ordner) mit dem zugeordneten Programm; False, wenn es fehlt.</summary>
    class function OpenFile(const AFileName: string): Boolean; static;
    /// <summary>Startet ACommandLine (Programm mit Argumenten) sichtbar, ohne zu warten; False, wenn es nicht startet.
    /// </summary>
    class function Launch(const ACommandLine: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Win.Registry,
  Atlas.WinBase.Process,
  Atlas.Windows.Process.Instances;

const
  cProcessQueryLimitedInformation = $1000;
  cLangGerman = $07;
  cMaxPath = 32768;

function QueryFullProcessImageNameW(AProcess: THandle; AFlags: DWORD; AName: PWideChar;
  var ASize: DWORD): BOOL; stdcall; external kernel32 name 'QueryFullProcessImageNameW';

class function TMonitorSystem.IsRunning(APid: Cardinal): Boolean;
begin
  Result := TProcessInstances.Running(APid);
end;

/// <summary>Voller Programmpfad des Prozesses APid; '' ohne Zugriff.</summary>
function ImageOf(APid: Cardinal): string;
var
  mProcess: THandle;
  mSize: DWORD;
begin
  Result := '';
  mProcess := OpenProcess(cProcessQueryLimitedInformation, False, APid);
  if mProcess = 0 then
  begin
    Exit;
  end;
  try
    SetLength(Result, cMaxPath);
    mSize := cMaxPath;
    if QueryFullProcessImageNameW(mProcess, 0, PWideChar(Result), mSize) then
    begin
      SetLength(Result, mSize);
    end
    else
    begin
      Result := '';
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

class function TMonitorSystem.IsAtlasServer(APid: Cardinal): Boolean;
begin
  Result := SameText(ExtractFileName(ImageOf(APid)), cServerExe);
end;

class function TMonitorSystem.TerminateServer(APid: Cardinal): Boolean;
var
  mProcess: THandle;
begin
  Result := False;
  if not IsAtlasServer(APid) then
  begin
    Exit;
  end;
  mProcess := OpenProcess(PROCESS_TERMINATE, False, APid);
  if mProcess = 0 then
  begin
    Exit;
  end;
  try
    Result := TerminateProcess(mProcess, 1);
  finally
    CloseHandle(mProcess);
  end;
end;

class function TMonitorSystem.UiLanguageCode: string;
begin
  Result := 'en';
  if (GetUserDefaultUILanguage and $3FF) = cLangGerman then
  begin
    Result := 'de';
  end;
end;

class function TMonitorSystem.StartsWithWindows: Boolean;
var
  mRegistry: TRegistry;
begin
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    Result := mRegistry.OpenKeyReadOnly(cRunKey) and mRegistry.ValueExists(cRunValue);
  finally
    mRegistry.Free;
  end;
end;

class function TMonitorSystem.SetStartWithWindows(AEnabled: Boolean; const ACommandLine: string): Boolean;
var
  mRegistry: TRegistry;
begin
  mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      mRegistry.RootKey := HKEY_CURRENT_USER;
      Result := mRegistry.OpenKey(cRunKey, True);
      if Result and AEnabled then
      begin
        mRegistry.WriteString(cRunValue, ACommandLine);
      end
      else if Result and mRegistry.ValueExists(cRunValue) then
      begin
        Result := mRegistry.DeleteValue(cRunValue);
      end;
    except
      // Ergebnis False; die Oberfläche meldet den Fehler.
      on ERegistryException do
        Result := False;
    end;
  finally
    mRegistry.Free;
  end;
end;

class function TMonitorSystem.OpenFile(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and (FileExists(AFileName) or DirectoryExists(AFileName)) and
    (ShellExecute(0, 'open', PChar(AFileName), nil, nil, SW_SHOWNORMAL) > 32);
end;

class function TMonitorSystem.Launch(const ACommandLine: string): Boolean;
var
  mLaunch: TAtlasProcessLaunch;
  mInfo: TProcessInformation;
begin
  // Ohne Standard-Handles: Das gestartete Programm erbt nichts.
  mLaunch := Default(TAtlasProcessLaunch);
  mLaunch.CommandLine := ACommandLine;
  Result := (ACommandLine <> '') and TAtlasProcessLauncher.Launch(mLaunch, mInfo);
  if Result then
  begin
    CloseHandle(mInfo.hThread);
    CloseHandle(mInfo.hProcess);
  end;
end;

end.
