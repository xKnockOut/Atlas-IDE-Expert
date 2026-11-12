unit Atlas.WinBase.Process;

// Startet Kindprozesse so, dass sie genau ihre Standard-Handles erben und
// sonst nichts (Code-Review R-101). Einziger Ort mit CreateProcess im
// Produktivcode (forbidden-symbol in atlas.json).
//
// Warum: CreateProcess mit bInheritHandles = True vererbt alle gerade
// vererbbaren Handles des Prozesses, nicht nur die drei aus TStartupInfo. In
// einem Prozess mit vielen Arbeiter-Threads (Plugin: Versionsverwaltung,
// Aufgaben, Serverstart; Server: Compilerlauf) erbt ein gleichzeitig
// gestarteter Prozess sonst das Schreib-Ende einer fremden Pipe, und deren
// Leser sieht sein Dateiende erst, wenn auch dieser Prozess endet.
//
// Wie:
// - STARTUPINFOEX mit PROC_THREAD_ATTRIBUTE_HANDLE_LIST: Vererbt werden nur die
//   Handles der Liste (ohne 0, INVALID_HANDLE_VALUE und Doppelte).
// - Die Aufrufer legen Pipes und Dateien NICHT vererbbar an. Launch macht die
//   Handles der Liste erst unmittelbar vor CreateProcess vererbbar und danach
//   wieder nicht. So erben auch Starter fremden Codes (IDE, andere Plugins), die
//   ohne Liste starten, die Atlas-Pipes höchstens in diesem kurzen Fenster.
// - Ohne Standard-Handles startet der Prozess ganz ohne Vererbung.
// - Eigene Deklarationen für STARTUPINFOEX und die drei Funktionen aus
//   kernel32 (ab Vista): unabhängig davon, was Winapi.Windows der jeweiligen
//   Delphi-Version mitbringt.

interface

uses
  Winapi.Windows;

type
  /// <summary>Was ein Kindprozess bekommt. Leere Texte bedeuten „wie der Elternprozess“: Executable '' = Programm
  /// aus der Befehlszeile, WorkingDir '' = aktueller Ordner, Environment '' = Umgebung des Elternprozesses.</summary>
  TAtlasProcessLaunch = record
    Executable: string;
    /// <summary>Vollständige Befehlszeile, das Programm als erstes Argument.</summary>
    CommandLine: string;
    WorkingDir: string;
    /// <summary>Umgebungsblock: Einträge mit #0 getrennt, am Ende #0#0; Unicode (CREATE_UNICODE_ENVIRONMENT setzt
    /// Launch selbst).</summary>
    Environment: string;
    /// <summary>dwCreationFlags, z. B. CREATE_NO_WINDOW oder CREATE_SUSPENDED.</summary>
    Flags: DWORD;
    /// <summary>STARTF_USESHOWWINDOW mit SW_HIDE.</summary>
    Hidden: Boolean;
    /// <summary>Standard-Handles des Kindes; 0 = keiner. Ist eines gesetzt, gilt STARTF_USESTDHANDLES. Danach sind
    /// diese Handles nicht mehr vererbbar.</summary>
    StdInput: THandle;
    StdOutput: THandle;
    StdError: THandle;
    /// <summary>Befehlszeile und Standard-Handles; alles andere wie der Elternprozess, ohne Fenster.</summary>
    class function Create(const AExecutable, ACommandLine, AWorkingDir: string; AStdInput, AStdOutput,
      AStdError: THandle): TAtlasProcessLaunch; static;
  end;

  TAtlasProcessLauncher = class
  public
    /// <summary>Startet den Prozess; vererbt werden nur die Standard-Handles aus ALaunch. False bei einem Fehler,
    /// GetLastError sagt warum. AInfo enthält dann keine Handles; sonst schließt der Aufrufer hProcess und
    /// hThread.</summary>
    class function Launch(const ALaunch: TAtlasProcessLaunch; out AInfo: TProcessInformation): Boolean; static;
    /// <summary>Die zu vererbenden Handles: StdInput, StdOutput, StdError ohne 0, INVALID_HANDLE_VALUE und
    /// Doppelte (eine Handle-Liste mit doppeltem Eintrag lehnt CreateProcess ab).</summary>
    class function InheritList(const ALaunch: TAtlasProcessLaunch): TArray<THandle>; static;
  end;

implementation

const
  cExtendedStartupInfoPresent = $00080000;
  cCreateUnicodeEnvironment = $00000400;
  // ProcThreadAttributeValue(ProcThreadAttributeHandleList = 2, Thread = False, Input = True, Additive = False)
  cProcThreadAttributeHandleList = $00020002;

type
  /// <summary>STARTUPINFOEXW.</summary>
  TAtlasStartupInfoEx = record
    StartupInfo: TStartupInfo;
    AttributeList: Pointer;
  end;

function InitializeAttributeList(AList: Pointer; ACount, AFlags: DWORD; var ASize: NativeUInt): BOOL; stdcall;
  external kernel32 name 'InitializeProcThreadAttributeList';
function UpdateAttribute(AList: Pointer; AFlags: DWORD; AAttribute: NativeUInt; AValue: Pointer; ASize: NativeUInt;
  APrevious, AReturnSize: Pointer): BOOL; stdcall; external kernel32 name 'UpdateProcThreadAttribute';
procedure DeleteAttributeList(AList: Pointer); stdcall; external kernel32 name 'DeleteProcThreadAttributeList';

/// <summary>PChar von AText, nil für ''; CreateProcess unterscheidet „leer“ und „nicht angegeben“.</summary>
function TextOrNil(const AText: string): PChar;
begin
  Result := nil;
  if AText <> '' then
  begin
    Result := PChar(AText);
  end;
end;

procedure SetInheritable(const AHandles: TArray<THandle>; AInherit: Boolean);
var
  mHandle: THandle;
  mFlag: DWORD;
begin
  mFlag := 0;
  if AInherit then
  begin
    mFlag := HANDLE_FLAG_INHERIT;
  end;
  for mHandle in AHandles do
  begin
    SetHandleInformation(mHandle, HANDLE_FLAG_INHERIT, mFlag);
  end;
end;

{ TAtlasProcessLaunch }

class function TAtlasProcessLaunch.Create(const AExecutable, ACommandLine, AWorkingDir: string; AStdInput,
  AStdOutput, AStdError: THandle): TAtlasProcessLaunch;
begin
  Result := Default(TAtlasProcessLaunch);
  Result.Executable := AExecutable;
  Result.CommandLine := ACommandLine;
  Result.WorkingDir := AWorkingDir;
  Result.Flags := CREATE_NO_WINDOW;
  Result.StdInput := AStdInput;
  Result.StdOutput := AStdOutput;
  Result.StdError := AStdError;
end;

{ TAtlasProcessLauncher }

class function TAtlasProcessLauncher.InheritList(const ALaunch: TAtlasProcessLaunch): TArray<THandle>;
var
  mCandidates: array[0..2] of THandle;
  mHandle, mTaken: THandle;
  mKnown: Boolean;
begin
  Result := nil;
  mCandidates[0] := ALaunch.StdInput;
  mCandidates[1] := ALaunch.StdOutput;
  mCandidates[2] := ALaunch.StdError;
  for mHandle in mCandidates do
  begin
    if (mHandle = 0) or (mHandle = INVALID_HANDLE_VALUE) then
    begin
      Continue;
    end;
    mKnown := False;
    for mTaken in Result do
    begin
      mKnown := mKnown or (mTaken = mHandle);
    end;
    if not mKnown then
    begin
      Result := Result + [mHandle];
    end;
  end;
end;

/// <summary>CreateProcess mit vorbereitetem AStartup; AList leer: ohne Vererbung, sonst mit Handle-Liste.</summary>
function StartWith(const ALaunch: TAtlasProcessLaunch; const AList: TArray<THandle>; var AStartup: TAtlasStartupInfoEx;
  out AInfo: TProcessInformation): Boolean;
var
  mCommandLine: string;
  mFlags, mError: DWORD;
begin
  mCommandLine := ALaunch.CommandLine;
  UniqueString(mCommandLine);
  mFlags := ALaunch.Flags;
  if ALaunch.Environment <> '' then
  begin
    mFlags := mFlags or cCreateUnicodeEnvironment;
  end;
  if Length(AList) = 0 then
  begin
    AStartup.StartupInfo.cb := SizeOf(TStartupInfo);
    Exit(CreateProcess(TextOrNil(ALaunch.Executable), PChar(mCommandLine), nil, nil, False, mFlags,
      TextOrNil(ALaunch.Environment), TextOrNil(ALaunch.WorkingDir), AStartup.StartupInfo, AInfo));
  end;
  AStartup.StartupInfo.cb := SizeOf(TAtlasStartupInfoEx);
  SetInheritable(AList, True);
  try
    Result := CreateProcess(TextOrNil(ALaunch.Executable), PChar(mCommandLine), nil, nil, True,
      mFlags or cExtendedStartupInfoPresent, TextOrNil(ALaunch.Environment), TextOrNil(ALaunch.WorkingDir),
      AStartup.StartupInfo, AInfo);
  finally
    // Der Fehler von CreateProcess bleibt für den Aufrufer erhalten.
    mError := GetLastError;
    SetInheritable(AList, False);
    SetLastError(mError);
  end;
end;

class function TAtlasProcessLauncher.Launch(const ALaunch: TAtlasProcessLaunch;
  out AInfo: TProcessInformation): Boolean;
var
  mStartup: TAtlasStartupInfoEx;
  mList: TArray<THandle>;
  mBuffer: TArray<Byte>;
  mSize: NativeUInt;
  mError: DWORD;
begin
  AInfo := Default(TProcessInformation);
  mStartup := Default(TAtlasStartupInfoEx);
  if ALaunch.Hidden then
  begin
    mStartup.StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
    mStartup.StartupInfo.wShowWindow := SW_HIDE;
  end;
  if (ALaunch.StdInput <> 0) or (ALaunch.StdOutput <> 0) or (ALaunch.StdError <> 0) then
  begin
    mStartup.StartupInfo.dwFlags := mStartup.StartupInfo.dwFlags or STARTF_USESTDHANDLES;
    mStartup.StartupInfo.hStdInput := ALaunch.StdInput;
    mStartup.StartupInfo.hStdOutput := ALaunch.StdOutput;
    mStartup.StartupInfo.hStdError := ALaunch.StdError;
  end;
  mList := InheritList(ALaunch);
  if Length(mList) = 0 then
  begin
    Exit(StartWith(ALaunch, mList, mStartup, AInfo));
  end;
  // Erster Aufruf liefert nur die Größe (und False mit ERROR_INSUFFICIENT_BUFFER).
  mSize := 0;
  InitializeAttributeList(nil, 1, 0, mSize);
  if mSize = 0 then
  begin
    Exit(False);
  end;
  SetLength(mBuffer, mSize);
  mStartup.AttributeList := @mBuffer[0];
  if not InitializeAttributeList(mStartup.AttributeList, 1, 0, mSize) then
  begin
    Exit(False);
  end;
  try
    // Die Liste muss bis nach CreateProcess leben: mList bleibt bis zum Ende dieser Routine.
    Result := False;
    if UpdateAttribute(mStartup.AttributeList, 0, cProcThreadAttributeHandleList, @mList[0],
      NativeUInt(Length(mList)) * SizeOf(THandle), nil, nil) then
    begin
      Result := StartWith(ALaunch, mList, mStartup, AInfo);
    end;
  finally
    mError := GetLastError;
    DeleteAttributeList(mStartup.AttributeList);
    SetLastError(mError);
  end;
end;

end.
