unit Atlas.IDE.Settings.ServerTool;

// AtlasServer.exe als Werkzeug aufrufen (#227): Die Optionsseite erzeugt und
// löscht die Baseline (--check … --update-baseline), wertet Unterdrückungen
// aus (--suppression-stats) und leert den Index-Cache (--clear-cache), ohne die
// Linter-Logik ins Plugin zu ziehen (Atlas.Common gehört nicht ins Plugin).
// Die Ausgabe geht in eine temporäre Datei statt in eine Pipe: So blockiert
// eine volle Pipe den Prozess nie. Der Aufruf wartet im Hauptthread mit
// Sanduhr bis zum Zeitlimit; danach wird der Prozess beendet.

interface

uses
  System.SysUtils;

type
  TAtlasServerTool = class
  public const
    /// <summary>Zeitlimit für einen Lauf über das ganze Projekt.</summary>
    CheckTimeoutMs = 600000;
    ShortTimeoutMs = 60000;
  public
    /// <summary>Startet AExe mit AArguments im Ordner ADirectory und wartet höchstens ATimeoutMs.
    /// AOutput: stdout; AExitCode: Exit-Code. False, wenn der Prozess nicht startet oder abgebrochen wurde
    /// (AError sagt, warum).</summary>
    class function Run(const AExe, AArguments, ADirectory: string; ATimeoutMs: Cardinal; out AOutput: string;
      out AExitCode: Cardinal; out AError: string): Boolean; static;
    /// <summary>Dateiversion aus der Versionsressource ("1.2.3.4"); '' ohne.</summary>
    class function FileVersion(const AFileName: string): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Vcl.Forms,
  Vcl.Controls,
  System.UITypes;

{ TAtlasServerTool }

class function TAtlasServerTool.Run(const AExe, AArguments, ADirectory: string; ATimeoutMs: Cardinal;
  out AOutput: string; out AExitCode: Cardinal; out AError: string): Boolean;
var
  Security: TSecurityAttributes;
  OutputFile, NulHandle: THandle;
  OutputName, CommandLine: string;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  Wait: Cardinal;
  OldCursor: TCursor;
begin
  Result := False;
  AOutput := '';
  AExitCode := High(Cardinal);
  AError := '';
  if not FileExists(AExe) then
  begin
    AError := AExe;
    Exit;
  end;
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  OutputName := TPath.GetTempFileName;
  OutputFile := CreateFile(PChar(OutputName), GENERIC_WRITE, FILE_SHARE_READ, @Security, CREATE_ALWAYS,
    FILE_ATTRIBUTE_TEMPORARY, 0);
  if OutputFile = INVALID_HANDLE_VALUE then
  begin
    AError := SysErrorMessage(GetLastError);
    Exit;
  end;
  NulHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @Security, OPEN_EXISTING, 0, 0);
  OldCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    Startup := Default(TStartupInfo);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES;
    Startup.hStdInput := 0;
    Startup.hStdOutput := OutputFile;
    Startup.hStdError := NulHandle;
    CommandLine := '"' + AExe + '" ' + AArguments;
    UniqueString(CommandLine);
    if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil, PChar(ADirectory), Startup,
      Info) then
    begin
      AError := SysErrorMessage(GetLastError);
      Exit;
    end;
    try
      Wait := WaitForSingleObject(Info.hProcess, ATimeoutMs);
      if Wait <> WAIT_OBJECT_0 then
      begin
        TerminateProcess(Info.hProcess, 1);
        WaitForSingleObject(Info.hProcess, 5000);
        AError := 'Zeitlimit';
        Exit;
      end;
      GetExitCodeProcess(Info.hProcess, AExitCode);
      Result := True;
    finally
      CloseHandle(Info.hThread);
      CloseHandle(Info.hProcess);
    end;
  finally
    Screen.Cursor := OldCursor;
    CloseHandle(OutputFile);
    if NulHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(NulHandle);
    if Result then
      AOutput := TFile.ReadAllText(OutputName, TEncoding.UTF8);
    TFile.Delete(OutputName);
  end;
end;

class function TAtlasServerTool.FileVersion(const AFileName: string): string;
var
  Handle, Size, Length_: Cardinal;
  Buffer: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(AFileName), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buffer, Size);
  if not GetFileVersionInfo(PChar(AFileName), 0, Size, @Buffer[0]) then
    Exit;
  if not VerQueryValue(@Buffer[0], '\', Pointer(Info), Length_) or (Length_ = 0) then
    Exit;
  Result := Format('%d.%d.%d.%d', [HiWord(Info.dwFileVersionMS), LoWord(Info.dwFileVersionMS),
    HiWord(Info.dwFileVersionLS), LoWord(Info.dwFileVersionLS)]);
end;

end.
