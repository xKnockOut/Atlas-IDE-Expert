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
  /// <summary>Ein Aufruf: Programm, Argumente, Arbeitsordner und Zeitlimit.</summary>
  TAtlasServerToolCall = record
    Exe: string;
    Arguments: string;
    Directory: string;
    TimeoutMs: Cardinal;
    class function Create(const AExe, AArguments, ADirectory: string; ATimeoutMs: Cardinal): TAtlasServerToolCall;
      static;
  end;

  /// <summary>Ergebnis eines Aufrufs: stdout, Exit-Code und, wenn er scheiterte, warum.</summary>
  TAtlasServerToolResult = record
    Output: string;
    ExitCode: Cardinal;
    Error: string;
  end;

  TAtlasServerTool = class
  public const
    /// <summary>Zeitlimit für einen Lauf über das ganze Projekt.</summary>
    cCheckTimeoutMs = 600000;
    cShortTimeoutMs = 60000;
  public
    /// <summary>Startet ACall.Exe mit den Argumenten im Arbeitsordner und wartet höchstens bis zum Zeitlimit.
    /// False, wenn der Prozess nicht startet oder abgebrochen wurde (AResult.Error sagt, warum).</summary>
    class function Run(const ACall: TAtlasServerToolCall; out AResult: TAtlasServerToolResult): Boolean; static;
    /// <summary>Dateiversion aus der Versionsressource ("1.2.3.4"); '' ohne.</summary>
    class function FileVersion(const AFileName: string): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Vcl.Forms,
  Vcl.Controls,
  System.UITypes,
  Atlas.WinBase.Process;

{ TAtlasServerToolCall }

class function TAtlasServerToolCall.Create(const AExe, AArguments, ADirectory: string;
  ATimeoutMs: Cardinal): TAtlasServerToolCall;
begin
  Result.Exe := AExe;
  Result.Arguments := AArguments;
  Result.Directory := ADirectory;
  Result.TimeoutMs := ATimeoutMs;
end;

type
  /// <summary>Handles der Standardkanäle eines Laufs: stdout in die temporäre Datei, stderr nach NUL.</summary>
  TAtlasToolHandles = record
    OutputName: string;
    OutputFile: THandle;
    NulHandle: THandle;
    /// <summary>Legt die temporäre Datei und NUL an (nicht vererbbar, das macht TAtlasProcessLauncher gezielt);
    /// False (AError gesetzt), wenn die Datei nicht angelegt werden kann.</summary>
    function Open(out AError: string): Boolean;
    procedure Close;
  end;

function TAtlasToolHandles.Open(out AError: string): Boolean;
begin
  AError := '';
  OutputName := TPath.GetTempFileName;
  OutputFile := CreateFile(PChar(OutputName), GENERIC_WRITE, FILE_SHARE_READ, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_TEMPORARY, 0);
  Result := OutputFile <> INVALID_HANDLE_VALUE;
  if not Result then
  begin
    AError := SysErrorMessage(GetLastError);
    Exit;
  end;
  NulHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
end;

procedure TAtlasToolHandles.Close;
begin
  CloseHandle(OutputFile);
  if NulHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(NulHandle);
  end;
end;

/// <summary>Startet den Prozess mit AHandles als stdout/stderr und wartet; True mit Exit-Code, wenn er im Zeitlimit
/// endete, sonst wird er beendet.</summary>
function RunProcess(const ACall: TAtlasServerToolCall; const AHandles: TAtlasToolHandles;
  var AResult: TAtlasServerToolResult): Boolean;
var
  mInfo: TProcessInformation;
begin
  Result := False;
  if not TAtlasProcessLauncher.Launch(TAtlasProcessLaunch.Create('', '"' + ACall.Exe + '" ' + ACall.Arguments,
    ACall.Directory, 0, AHandles.OutputFile, AHandles.NulHandle), mInfo) then
  begin
    AResult.Error := SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    if WaitForSingleObject(mInfo.hProcess, ACall.TimeoutMs) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(mInfo.hProcess, 1);
      WaitForSingleObject(mInfo.hProcess, 5000);
      AResult.Error := 'Zeitlimit';
      Exit;
    end;
    GetExitCodeProcess(mInfo.hProcess, AResult.ExitCode);
    Result := True;
  finally
    CloseHandle(mInfo.hThread);
    CloseHandle(mInfo.hProcess);
  end;
end;

{ TAtlasServerTool }

class function TAtlasServerTool.Run(const ACall: TAtlasServerToolCall; out AResult: TAtlasServerToolResult): Boolean;
var
  mHandles: TAtlasToolHandles;
  mOldCursor: TCursor;
begin
  Result := False;
  AResult := Default(TAtlasServerToolResult);
  AResult.ExitCode := High(Cardinal);
  if not FileExists(ACall.Exe) then
  begin
    AResult.Error := ACall.Exe;
    Exit;
  end;
  mHandles := Default(TAtlasToolHandles);
  if not mHandles.Open(AResult.Error) then
  begin
    Exit;
  end;
  mOldCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    Result := RunProcess(ACall, mHandles, AResult);
  finally
    Screen.Cursor := mOldCursor;
    mHandles.Close;
    if Result then
    begin
      AResult.Output := TFile.ReadAllText(mHandles.OutputName, TEncoding.UTF8);
    end;
    TFile.Delete(mHandles.OutputName);
  end;
end;

class function TAtlasServerTool.FileVersion(const AFileName: string): string;
var
  mHandle, mSize, mLength_: Cardinal;
  mBuffer: TBytes;
  mInfo: PVSFixedFileInfo;
begin
  Result := '';
  mSize := GetFileVersionInfoSize(PChar(AFileName), mHandle);
  if mSize = 0 then
  begin
    Exit;
  end;
  SetLength(mBuffer, mSize);
  if not GetFileVersionInfo(PChar(AFileName), 0, mSize, @mBuffer[0]) then
  begin
    Exit;
  end;
  if not VerQueryValue(@mBuffer[0], '\', Pointer(mInfo), mLength_) or (mLength_ = 0) then
  begin
    Exit;
  end;
  Result := Format('%d.%d.%d.%d', [HiWord(mInfo.dwFileVersionMS), LoWord(mInfo.dwFileVersionMS),
    HiWord(mInfo.dwFileVersionLS), LoWord(mInfo.dwFileVersionLS)]);
end;

end.
