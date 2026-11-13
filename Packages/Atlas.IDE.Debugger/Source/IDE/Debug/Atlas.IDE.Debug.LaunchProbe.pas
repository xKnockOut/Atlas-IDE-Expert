unit Atlas.IDE.Debug.LaunchProbe;

// Startverbünde (#867), Adapter zu Windows:
// - TAtlasIdeLaunchProbe: Hintergrundthread, der alle cIntervalMs prüft, ob
//   localhost:Port Verbindungen annimmt bzw. ob der Prozess ein sichtbares
//   Hauptfenster hat (EnumWindows nach Prozess-ID). Die Ergebnisse liest der
//   Hauptthread aus PortOpen und WindowFound (nur gesetzt, nie zurück).
// - TAtlasIdeLaunchProcesses: Programm ohne Debugger starten (CreateProcess
//   mit Arbeitsordner und Umgebung) und Prozesse beenden.
// Free wartet auf das Ende des Threads; der Besitzer gibt ihn frei, bevor das
// Modul geht.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Settings.TeamFile;

type
  TAtlasIdeLaunchProbe = class(TThread)
  public const
    cIntervalMs = 250;
    cConnectMs = 200;
  private
    FPort: Integer;
    FPid: Cardinal;
    FWake: TEvent;
    FPortOpen: Integer;
    FWindowFound: Integer;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    /// <summary>Prüft APort (0 = nicht) und das Hauptfenster von APid (0 = nicht).</summary>
    constructor Create(APort: Integer; APid: Cardinal);
    destructor Destroy; override;
    function PortOpen: Boolean;
    function WindowFound: Boolean;
    /// <summary>Kennung des Prozesses nachtragen (beim Start mit Debugger erst später bekannt).</summary>
    procedure SetPid(APid: Cardinal);
  end;

  TAtlasIdeLaunchProcesses = record
  public
    /// <summary>Startet AExe ohne Debugger; 0 bei Fehler. AVariables ergänzen bzw. ersetzen die geerbte
    /// Umgebung.</summary>
    class function Start(const AExe, AArgs, AWorkingDir: string;
      const AVariables: TArray<TAtlasTeamVariable>): Cardinal; static;
    /// <summary>Umgebungsblock (Name=Wert#0…#0#0): geerbte Umgebung mit AVariables; '' ohne Variablen.</summary>
    class function EnvironmentBlock(const AVariables: TArray<TAtlasTeamVariable>): string; static;
    /// <summary>Beendet APid hart (TerminateProcess); False ohne Zugriff.</summary>
    class function Kill(APid: Cardinal): Boolean; static;
    /// <summary>Läuft APid noch?</summary>
    class function Running(APid: Cardinal): Boolean; static;
    class function PortAccepts(APort, ATimeoutMs: Integer): Boolean; static;
    class function HasMainWindow(APid: Cardinal): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Winsock2;

const
  cProcessTerminate = $0001;
  cProcessQueryLimitedInformation = $1000;
  cWinsockVersion = $0202;
  cLocalhost = '127.0.0.1';

{ TAtlasIdeLaunchProbe }

constructor TAtlasIdeLaunchProbe.Create(APort: Integer; APid: Cardinal);
begin
  FPort := APort;
  FPid := APid;
  FWake := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasIdeLaunchProbe.Destroy;
begin
  Terminate;
  inherited Destroy;
  FWake.Free;
end;

procedure TAtlasIdeLaunchProbe.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TAtlasIdeLaunchProbe.SetPid(APid: Cardinal);
begin
  TInterlocked.Exchange(Integer(FPid), Integer(APid));
end;

function TAtlasIdeLaunchProbe.PortOpen: Boolean;
begin
  Result := TInterlocked.CompareExchange(FPortOpen, 0, 0) <> 0;
end;

function TAtlasIdeLaunchProbe.WindowFound: Boolean;
begin
  Result := TInterlocked.CompareExchange(FWindowFound, 0, 0) <> 0;
end;

procedure TAtlasIdeLaunchProbe.Execute;
var
  mPid: Cardinal;
begin
  while not Terminated do
  begin
    if (FPort > 0) and (FPortOpen = 0) and TAtlasIdeLaunchProcesses.PortAccepts(FPort, cConnectMs) then
    begin
      TInterlocked.Exchange(FPortOpen, 1);
    end;
    mPid := Cardinal(TInterlocked.CompareExchange(Integer(FPid), 0, 0));
    if (mPid <> 0) and (FWindowFound = 0) and TAtlasIdeLaunchProcesses.HasMainWindow(mPid) then
    begin
      TInterlocked.Exchange(FWindowFound, 1);
    end;
    if FWake.WaitFor(cIntervalMs) = wrSignaled then
    begin
      Exit;
    end;
  end;
end;

{ TAtlasIdeLaunchProcesses }

class function TAtlasIdeLaunchProcesses.EnvironmentBlock(const AVariables: TArray<TAtlasTeamVariable>): string;
var
  mStrings: PChar;
  mEntry: PChar;
  mList: TStringList;
  mBuilder: TStringBuilder;
  mVariable: TAtlasTeamVariable;
  mIndex: Integer;
begin
  Result := '';
  if AVariables = nil then
  begin
    Exit;
  end;
  mList := TStringList.Create;
  try
    mList.CaseSensitive := False;
    mStrings := GetEnvironmentStrings;
    try
      mEntry := mStrings;
      while mEntry^ <> #0 do
      begin
        mList.Add(mEntry);
        Inc(mEntry, StrLen(mEntry) + 1);
      end;
    finally
      FreeEnvironmentStrings(mStrings);
    end;
    for mVariable in AVariables do
    begin
      mIndex := mList.IndexOfName(mVariable.Name);
      if mIndex >= 0 then
      begin
        mList.Delete(mIndex);
      end;
      mList.Add(mVariable.Name + '=' + mVariable.Value);
    end;
    mBuilder := TStringBuilder.Create;
    try
      for mIndex := 0 to mList.Count - 1 do
      begin
        mBuilder.Append(mList[mIndex]).Append(#0);
      end;
      mBuilder.Append(#0);
      Result := mBuilder.ToString;
    finally
      mBuilder.Free;
    end;
  finally
    mList.Free;
  end;
end;

class function TAtlasIdeLaunchProcesses.Start(const AExe, AArgs, AWorkingDir: string;
  const AVariables: TArray<TAtlasTeamVariable>): Cardinal;
var
  mStartup: TStartupInfo;
  mInfo: TProcessInformation;
  mCommand, mDir, mEnvironment: string;
  mBlock: Pointer;
begin
  Result := 0;
  mStartup := Default(TStartupInfo);
  mStartup.cb := SizeOf(mStartup);
  mCommand := '"' + AExe + '"';
  if AArgs <> '' then
  begin
    mCommand := mCommand + ' ' + AArgs;
  end;
  UniqueString(mCommand);
  mDir := AWorkingDir;
  if mDir = '' then
  begin
    mDir := ExtractFileDir(AExe);
  end;
  mEnvironment := EnvironmentBlock(AVariables);
  mBlock := nil;
  if mEnvironment <> '' then
  begin
    mBlock := PChar(mEnvironment);
  end;
  if not CreateProcess(nil, PChar(mCommand), nil, nil, False, CREATE_UNICODE_ENVIRONMENT, mBlock, PChar(mDir),
    mStartup, mInfo) then
  begin
    Exit;
  end;
  CloseHandle(mInfo.hThread);
  CloseHandle(mInfo.hProcess);
  Result := mInfo.dwProcessId;
end;

class function TAtlasIdeLaunchProcesses.Kill(APid: Cardinal): Boolean;
var
  mProcess: THandle;
begin
  mProcess := OpenProcess(cProcessTerminate, False, APid);
  Result := mProcess <> 0;
  if not Result then
  begin
    Exit;
  end;
  try
    Result := TerminateProcess(mProcess, 1);
  finally
    CloseHandle(mProcess);
  end;
end;

class function TAtlasIdeLaunchProcesses.Running(APid: Cardinal): Boolean;
var
  mProcess: THandle;
  mCode: DWORD;
begin
  mProcess := OpenProcess(cProcessQueryLimitedInformation, False, APid);
  Result := mProcess <> 0;
  if not Result then
  begin
    Exit;
  end;
  try
    Result := GetExitCodeProcess(mProcess, mCode) and (mCode = STILL_ACTIVE);
  finally
    CloseHandle(mProcess);
  end;
end;

class function TAtlasIdeLaunchProcesses.PortAccepts(APort, ATimeoutMs: Integer): Boolean;
var
  mData: TWSAData;
  mSocket: TSocket;
  mAddress: TSockAddrIn;
  mMode: u_long;
  mWrite: TFdSet;
  mTime: TTimeVal;
begin
  Result := False;
  if WSAStartup(cWinsockVersion, mData) <> 0 then
  begin
    Exit;
  end;
  try
    mSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if mSocket = INVALID_SOCKET then
    begin
      Exit;
    end;
    try
      mMode := 1;
      ioctlsocket(mSocket, Integer(FIONBIO), mMode);
      mAddress := Default(TSockAddrIn);
      mAddress.sin_family := AF_INET;
      mAddress.sin_port := htons(APort);
      mAddress.sin_addr.S_addr := inet_addr(PAnsiChar(AnsiString(cLocalhost)));
      connect(mSocket, PSockAddr(@mAddress)^, SizeOf(mAddress));
      FD_ZERO(mWrite);
      _FD_SET(mSocket, mWrite);
      mTime.tv_sec := 0;
      mTime.tv_usec := ATimeoutMs * 1000;
      Result := select(0, nil, @mWrite, nil, @mTime) > 0;
    finally
      closesocket(mSocket);
    end;
  finally
    WSACleanup;
  end;
end;

type
  TWindowSearch = record
    Pid: Cardinal;
    Found: Boolean;
  end;
  PWindowSearch = ^TWindowSearch;

function FindWindowOf(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  mSearch: PWindowSearch;
  mPid: DWORD;
begin
  mSearch := PWindowSearch(AParam);
  GetWindowThreadProcessId(AWindow, @mPid);
  if (mPid = mSearch.Pid) and IsWindowVisible(AWindow) and (GetWindow(AWindow, GW_OWNER) = 0) then
  begin
    mSearch.Found := True;
    Exit(False);
  end;
  Result := True;
end;

class function TAtlasIdeLaunchProcesses.HasMainWindow(APid: Cardinal): Boolean;
var
  mSearch: TWindowSearch;
begin
  mSearch.Pid := APid;
  mSearch.Found := False;
  EnumWindows(@FindWindowOf, LPARAM(@mSearch));
  Result := mSearch.Found;
end;

end.
