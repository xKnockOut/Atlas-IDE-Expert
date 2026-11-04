unit Shell.Update.System;

// Host-Rolle Shell von AtlasUpdate.exe (#1519): setzt das Update-System aus
// den Windows-Adaptern zusammen. Ausgaben gehen nach stderr (stdout bleibt
// frei) und mit Zeitstempel in update.log.

interface

uses
  Atlas.Common.Updates.Contract;

type
  TShellUpdateSystem = class
  public
    /// <summary>Alle Adapter; ALogFile '' = nur Konsole.</summary>
    class function NewSystem(const ALogFile: string): TUpdateSystem; static;
    /// <summary>Text auf die Konsole (stderr) mit Zeilenende.</summary>
    class procedure Say(const AText: string); static;
    /// <summary>%LOCALAPPDATA%\Atlas\Updates.</summary>
    class function UpdatesRoot: string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Windows.Compiler.Adapters.ProcessRunner,
  Atlas.Windows.Updates.Adapters.Registry,
  Atlas.Windows.Updates.Adapters.Files,
  Atlas.Windows.Updates.Adapters.Processes,
  Atlas.Windows.Updates.Adapters.Trust,
  Atlas.Windows.Updates.Adapters.Network,
  Atlas.Windows.Updates.Adapters.Archive,
  Atlas.Windows.Updates.Adapters.Builder;

class procedure TShellUpdateSystem.Say(const AText: string);
begin
  Writeln(ErrOutput, AText);
end;

class function TShellUpdateSystem.UpdatesRoot: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'Atlas\Updates';
end;

function NewLog(const AFiles: IUpdateFiles; const ALogFile: string): TUpdateLog;
begin
  Result :=
    procedure(const AText: string)
    begin
      TShellUpdateSystem.Say(AText);
      if ALogFile <> '' then
      begin
        AFiles.AppendText(ALogFile, DateToISO8601(Now, False) + ' ' + AText + #13#10);
      end;
    end;
end;

class function TShellUpdateSystem.NewSystem(const ALogFile: string): TUpdateSystem;
begin
  Result := Default(TUpdateSystem);
  Result.Registry := TUpdateWindowsRegistry.Create;
  Result.Files := TUpdateWindowsFiles.Create;
  Result.Processes := TUpdateWindowsProcesses.Create;
  Result.Trust := TUpdateWindowsTrust.Create;
  Result.Network := TUpdateWindowsNetwork.Create;
  Result.Archive := TUpdateWindowsArchive.Create;
  Result.Builder := TUpdateWindowsBuilder.Create(Result.Registry, TProcessRunner.Create);
  Result.Log := NewLog(Result.Files, ALogFile);
end;

end.
