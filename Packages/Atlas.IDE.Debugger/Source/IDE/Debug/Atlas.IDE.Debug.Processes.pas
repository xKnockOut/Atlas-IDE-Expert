unit Atlas.IDE.Debug.Processes;

// Erneut anhängen (#2171), Adapter zu Windows: laufende Prozesse eines
// Programms mit Pfad, Startzeit und Befehlszeile.
// - Named: Prozesse mit dem Namen der EXE (Toolhelp), Pfad über
//   QueryFullProcessImageName; Prozesse ohne Zugriff (anderer Benutzer,
//   Dienst ohne Administratorrechte der IDE) haben keinen Pfad.
// - Startzeit (GetProcessTimes) und Befehlszeile (NtQueryInformationProcess,
//   ProcessCommandLineInformation, ab Windows 8.1) nur mit ADetails, für die
//   Auswahl; beim Warten genügt der Pfad.
// - PathOf: Pfad der EXE eines Prozesses.
// Threadsicher (keine gemeinsamen Daten); das Warten fragt aus einem
// Hintergrundthread.

interface

uses
  Atlas.Core.Debug.Reattach;

type
  TAtlasIdeDebugProcesses = record
  public
    /// <summary>Laufende Prozesse mit dem Programmnamen AName ("Kunden.exe"); ADetails liest Startzeit und
    /// Befehlszeile.</summary>
    class function Named(const AName: string; ADetails: Boolean): TAtlasReattachProcesses; static;
    /// <summary>Vollständiger Pfad der EXE von APid; '' ohne Zugriff.</summary>
    class function PathOf(APid: Cardinal): string; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  System.SysUtils;

const
  // Fehlen in Delphis Winapi.Windows.
  cProcessQueryLimitedInformation = $1000;
  cProcessCommandLineInformation = 60;
  cCommandLineBufferBytes = 64 * 1024;

type
  TUnicodeString = record
    Length: Word;
    MaximumLength: Word;
    Buffer: PWideChar;
  end;
  PUnicodeString = ^TUnicodeString;

function QueryFullProcessImageNameW(AProcess: THandle; AFlags: DWORD; AExeName: PWideChar;
  var ASize: DWORD): BOOL; stdcall; external kernel32 name 'QueryFullProcessImageNameW';

function NtQueryInformationProcess(AProcess: THandle; AClass: Integer; AInformation: Pointer; ALength: ULONG;
  AReturned: PULONG): Integer; stdcall; external 'ntdll.dll' name 'NtQueryInformationProcess';

function ImagePath(AProcess: THandle): string;
var
  mBuffer: array[0..MAX_PATH * 2] of WideChar;
  mSize: DWORD;
begin
  Result := '';
  mSize := Length(mBuffer);
  if QueryFullProcessImageNameW(AProcess, 0, @mBuffer[0], mSize) then
  begin
    SetString(Result, PWideChar(@mBuffer[0]), mSize);
  end;
end;

function StartTime(AProcess: THandle): TDateTime;
var
  mCreation, mExit, mKernel, mUser, mLocal: TFileTime;
  mSystem: TSystemTime;
begin
  Result := 0;
  if GetProcessTimes(AProcess, mCreation, mExit, mKernel, mUser) and FileTimeToLocalFileTime(mCreation, mLocal) and
    FileTimeToSystemTime(mLocal, mSystem) then
  begin
    Result := SystemTimeToDateTime(mSystem);
  end;
end;

function CommandLine(AProcess: THandle): string;
var
  mBuffer: TBytes;
  mReturned: ULONG;
  mText: PUnicodeString;
begin
  Result := '';
  SetLength(mBuffer, cCommandLineBufferBytes);
  if NtQueryInformationProcess(AProcess, cProcessCommandLineInformation, @mBuffer[0], Length(mBuffer),
    @mReturned) <> 0 then
  begin
    Exit;
  end;
  mText := PUnicodeString(@mBuffer[0]);
  if (mText.Buffer <> nil) and (mText.Length > 0) then
  begin
    SetString(Result, mText.Buffer, mText.Length div SizeOf(WideChar));
  end;
end;

/// <summary>Pfad und auf Wunsch Startzeit und Befehlszeile in AEntry; ohne Zugriff bleiben sie leer.</summary>
procedure ReadProcess(var AEntry: TAtlasReattachProcess; ADetails: Boolean);
var
  mProcess: THandle;
begin
  mProcess := OpenProcess(cProcessQueryLimitedInformation, False, AEntry.Pid);
  if mProcess = 0 then
  begin
    Exit;
  end;
  try
    AEntry.Path := ImagePath(mProcess);
    if ADetails then
    begin
      AEntry.StartedAt := StartTime(mProcess);
      AEntry.CommandLine := CommandLine(mProcess);
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

class function TAtlasIdeDebugProcesses.Named(const AName: string; ADetails: Boolean): TAtlasReattachProcesses;
var
  mSnapshot: THandle;
  mEntry: TProcessEntry32;
  mProcess: TAtlasReattachProcess;
begin
  Result := nil;
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mEntry := Default(TProcessEntry32);
    mEntry.dwSize := SizeOf(mEntry);
    if not Process32First(mSnapshot, mEntry) then
    begin
      Exit;
    end;
    repeat
      if SameText(string(mEntry.szExeFile), AName) and (mEntry.th32ProcessID <> GetCurrentProcessId) then
      begin
        mProcess := TAtlasReattachProcess.Create(mEntry.th32ProcessID, '', string(mEntry.szExeFile));
        ReadProcess(mProcess, ADetails);
        Result := Result + [mProcess];
      end;
    until not Process32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

class function TAtlasIdeDebugProcesses.PathOf(APid: Cardinal): string;
var
  mProcess: TAtlasReattachProcess;
begin
  mProcess := TAtlasReattachProcess.Create(APid, '', '');
  ReadProcess(mProcess, False);
  Result := mProcess.Path;
end;

end.
