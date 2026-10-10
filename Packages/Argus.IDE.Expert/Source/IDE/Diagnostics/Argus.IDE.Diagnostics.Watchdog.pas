unit Argus.IDE.Diagnostics.Watchdog;

// Einfrier-Wächter (#501): Ein Hintergrund-Thread schickt alle 100 ms eine
// Nachricht an ein Fenster des Hauptthreads und wartet auf die Antwort.
// Bleibt sie über die Schwelle aus, hält er den Hauptthread kurz an, kopiert
// Register und Stapel in einen vorab angelegten Puffer (kein Speicher, keine
// Sperren, solange der Hauptthread steht) und lässt ihn weiterlaufen. Nach
// dem Ende des Hängers wertet der Hauptthread die Kopie aus (Module, Fenster,
// Argus-Aktion) und meldet den Hänger über OnHang.
// Der Wächter arbeitet im Hauptthread nur die Antwort auf die Messnachricht.
// Gemessen wird erst, wenn die Nachrichtenschleife nach dem Laden frei ist;
// das Laden der übrigen Packages beim Start ist kein Hänger (die Startzeit
// meldet OnStartup).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Argus.Core.Diagnostics.Hangs;

type
  TArgusHangProc = reference to procedure(const AHang: TArgusHang);
  TArgusStartupProc = reference to procedure(AMilliseconds: Int64);

  TArgusWatchdog = class
  private const
    WM_ARGUS_PING = WM_APP + $4A1;
    WM_ARGUS_STARTUP = WM_APP + $4A2;
    PeriodMs = 100;
    StackWords = 4096;
  private type
    TWatchThread = class(TThread)
    private
      FOwner: TArgusWatchdog;
      /// <summary>Eigener Rahmen je Bericht: Der Thread arbeitet weiter, während der Hauptthread meldet.</summary>
      procedure Report(const AHang: TArgusHang; const AAddresses: TArray<UInt64>);
    protected
      procedure Execute; override;
    end;
  private
    FWindow: HWND;
    FThread: TWatchThread;
    FWake: TEvent;
    FMainThread: THandle;
    FPong: Integer;
    FStarted: Integer;
    FThresholdMs: Integer;
    FLoadedAt: Int64;
    FOnHang: TArgusHangProc;
    FOnStartup: TArgusStartupProc;
    FThresholdFunc: TFunc<Integer>;
    // Kopie beim Hänger; nur im Wächter-Thread beschrieben, vor dem Anhalten angelegt.
    FStack: array[0..StackWords - 1] of NativeUInt;
    FStackCount: Integer;
    FIP: NativeUInt;
    // GetThreadContext verlangt unter x64 einen auf 16 Byte ausgerichteten TContext.
    FContextBuffer: TBytes;
    procedure WndProc(var AMessage: TMessage);
    procedure Capture;
    function TakeAddresses: TArray<UInt64>;
    class function NowMs: Int64; static;
    class function ForegroundWindowText: string; static;
    class function Modules: TArray<TArgusModuleRange>; static;
  public
    /// <summary>ALoadedAt: NowMs beim Laden des Packages; AThreshold liefert die Schwelle (im Hauptthread gelesen).</summary>
    constructor Create(ALoadedAt: Int64; const AThreshold: TFunc<Integer>);
    destructor Destroy; override;
    /// <summary>Zeitpunkt in ms (monoton) für ALoadedAt.</summary>
    class function Timestamp: Int64; static;
    /// <summary>Im Hauptthread nach dem Ende eines Hängers über der Schwelle.</summary>
    property OnHang: TArgusHangProc read FOnHang write FOnHang;
    /// <summary>Im Hauptthread, sobald die Nachrichtenschleife nach dem Laden frei ist.</summary>
    property OnStartup: TArgusStartupProc read FOnStartup write FOnStartup;
  end;

implementation

uses
  System.Diagnostics,
  Winapi.PsAPI;

function InternalGetWindowText(hWnd: HWND; pString: PWideChar; cchMaxCount: Integer): Integer; stdcall;
  external user32 name 'InternalGetWindowText';

{ TArgusWatchdog.TWatchThread }

procedure TArgusWatchdog.TWatchThread.Execute;
var
  Seq: Integer;
  SentAt, Waited: Int64;
  Captured: Boolean;
  Hang: TArgusHang;
begin
  NameThreadForDebugging('Argus.Watchdog');
  Seq := 0;
  while not Terminated do
  begin
    if TInterlocked.CompareExchange(FOwner.FStarted, 0, 0) = 0 then
    begin
      FOwner.FWake.WaitFor(PeriodMs);
      Continue;
    end;
    Inc(Seq);
    SentAt := NowMs;
    if not PostMessage(FOwner.FWindow, WM_ARGUS_PING, WPARAM(Seq), 0) then
    begin
      FOwner.FWake.WaitFor(PeriodMs);
      Continue;
    end;
    Captured := False;
    Hang := Default(TArgusHang);
    while not Terminated and (TInterlocked.CompareExchange(FOwner.FPong, 0, 0) <> Seq) do
    begin
      FOwner.FWake.WaitFor(25);
      Waited := NowMs - SentAt;
      if not Captured and (Waited >= TInterlocked.CompareExchange(FOwner.FThresholdMs, 0, 0)) then
      begin
        Captured := True;
        Hang.At := Now;
        Hang.Activity := TArgusActivity.Current;
        Hang.Window := ForegroundWindowText;
        FOwner.Capture;
      end;
    end;
    if Terminated then
      Break;
    if Captured then
    begin
      Hang.DurationMs := NowMs - SentAt;
      Report(Hang, FOwner.TakeAddresses);
    end;
    FOwner.FWake.WaitFor(PeriodMs);
  end;
end;

procedure TArgusWatchdog.TWatchThread.Report(const AHang: TArgusHang; const AAddresses: TArray<UInt64>);
var
  Hang: TArgusHang;
  Addresses: TArray<UInt64>;
begin
  Hang := AHang;
  Addresses := AAddresses;
  Queue(
    procedure
    begin
      // Module erst jetzt im Hauptthread: Die Ladersperre ist frei.
      Hang.Frames := TArgusStackScan.Frames(Addresses, TArgusWatchdog.Modules);
      if Assigned(FOwner.FOnHang) then
        FOwner.FOnHang(Hang);
    end);
end;

{ TArgusWatchdog }

constructor TArgusWatchdog.Create(ALoadedAt: Int64; const AThreshold: TFunc<Integer>);
begin
  inherited Create;
  FLoadedAt := ALoadedAt;
  FThresholdFunc := AThreshold;
  FThresholdMs := 500;
  if Assigned(FThresholdFunc) then
    FThresholdMs := FThresholdFunc();
  FWake := TEvent.Create(nil, False, False, '');
  SetLength(FContextBuffer, SizeOf(TContext) + 16);
  FWindow := AllocateHWnd(WndProc);
  // Echter Handle des Hauptthreads (der Konstruktor läuft dort); GetCurrentThread ist nur ein Platzhalter.
  if not DuplicateHandle(GetCurrentProcess, GetCurrentThread, GetCurrentProcess, @FMainThread, 0, False,
    DUPLICATE_SAME_ACCESS) then
    FMainThread := 0;
  PostMessage(FWindow, WM_ARGUS_STARTUP, 0, 0);
  FThread := TWatchThread.Create(True);
  FThread.FOwner := Self;
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

destructor TArgusWatchdog.Destroy;
begin
  // Innerhalb von 1 s beenden: Der Thread wartet höchstens 100 ms am Stück.
  if FThread <> nil then
  begin
    FThread.Terminate;
    FWake.SetEvent;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  if FWindow <> 0 then
    DeallocateHWnd(FWindow);
  if FMainThread <> 0 then
    CloseHandle(FMainThread);
  FWake.Free;
  inherited;
end;

class function TArgusWatchdog.NowMs: Int64;
begin
  Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

class function TArgusWatchdog.Timestamp: Int64;
begin
  Result := NowMs;
end;

procedure TArgusWatchdog.WndProc(var AMessage: TMessage);
begin
  case AMessage.Msg of
    WM_ARGUS_PING:
      begin
        TInterlocked.Exchange(FPong, Integer(AMessage.WParam));
        // Die Schwelle kann sich in den Optionen ändern; hier im Hauptthread lesen.
        if Assigned(FThresholdFunc) then
          TInterlocked.Exchange(FThresholdMs, FThresholdFunc());
      end;
    WM_ARGUS_STARTUP:
      begin
        TInterlocked.Exchange(FStarted, 1);
        if Assigned(FOnStartup) then
          FOnStartup(NowMs - FLoadedAt);
      end;
  else
    AMessage.Result := DefWindowProc(FWindow, AMessage.Msg, AMessage.WParam, AMessage.LParam);
  end;
end;

procedure TArgusWatchdog.Capture;
var
  Context: PContext;
  StackPointer, Limit: NativeUInt;
  Info: TMemoryBasicInformation;
begin
  Context := PContext((NativeUInt(@FContextBuffer[0]) + 15) and not NativeUInt(15));
  FStackCount := 0;
  FIP := 0;
  if FMainThread = 0 then
    Exit;
  // Während der Hauptthread steht: nichts anfordern, nichts sperren, nur kopieren.
  if SuspendThread(FMainThread) = DWORD(-1) then
    Exit;
  try
    FillChar(Context^, SizeOf(TContext), 0);
    Context.ContextFlags := CONTEXT_CONTROL;
    if not GetThreadContext(FMainThread, Context^) then
      Exit;
    {$IFDEF CPUX64}
    StackPointer := Context.Rsp;
    FIP := Context.Rip;
    {$ELSE}
    StackPointer := Context.Esp;
    FIP := Context.Eip;
    {$ENDIF}
    if VirtualQuery(Pointer(StackPointer), Info, SizeOf(Info)) = 0 then
      Exit;
    Limit := NativeUInt(Info.BaseAddress) + Info.RegionSize;
    FStackCount := (Limit - StackPointer) div SizeOf(NativeUInt);
    if FStackCount > StackWords then
      FStackCount := StackWords;
    Move(Pointer(StackPointer)^, FStack[0], FStackCount * SizeOf(NativeUInt));
  finally
    ResumeThread(FMainThread);
  end;
end;

function TArgusWatchdog.TakeAddresses: TArray<UInt64>;
var
  Index: Integer;
begin
  SetLength(Result, FStackCount + 1);
  Result[0] := FIP;
  for Index := 0 to FStackCount - 1 do
    Result[Index + 1] := FStack[Index];
end;

class function TArgusWatchdog.ForegroundWindowText: string;
var
  Window: HWND;
  Buffer: array[0..255] of WideChar;
  Length_: Integer;
begin
  // InternalGetWindowText schickt keine Nachricht an das (hängende) Fenster.
  Result := '';
  Window := GetForegroundWindow;
  if Window = 0 then
    Exit;
  Length_ := InternalGetWindowText(Window, Buffer, Length(Buffer));
  if Length_ > 0 then
    SetString(Result, PWideChar(@Buffer[0]), Length_);
end;

class function TArgusWatchdog.Modules: TArray<TArgusModuleRange>;
var
  Handles: array[0..1023] of HMODULE;
  Needed: DWORD;
  Index: Integer;
  Info: TModuleInfo;
  Name: array[0..MAX_PATH] of Char;
  Range: TArgusModuleRange;
begin
  Result := nil;
  if not EnumProcessModules(GetCurrentProcess, @Handles[0], SizeOf(Handles), Needed) then
    Exit;
  for Index := 0 to Integer(Needed div SizeOf(HMODULE)) - 1 do
    if (Index <= High(Handles)) and GetModuleInformation(GetCurrentProcess, Handles[Index], @Info, SizeOf(Info)) and
      (GetModuleFileName(Handles[Index], Name, Length(Name)) > 0) then
    begin
      Range.Name := ExtractFileName(Name);
      Range.Base := NativeUInt(Info.lpBaseOfDll);
      Range.Size := Info.SizeOfImage;
      Result := Result + [Range];
    end;
end;

end.