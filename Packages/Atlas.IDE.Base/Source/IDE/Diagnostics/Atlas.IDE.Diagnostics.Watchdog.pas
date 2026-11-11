unit Atlas.IDE.Diagnostics.Watchdog;

// Einfrier-Wächter (#501): Ein Hintergrund-Thread schickt alle 100 ms eine
// Nachricht an ein Fenster des Hauptthreads und wartet auf die Antwort.
// Bleibt sie über die Schwelle aus, hält er den Hauptthread kurz an, kopiert
// Register und Stapel in einen vorab angelegten Puffer (kein Speicher, keine
// Sperren, solange der Hauptthread steht) und lässt ihn weiterlaufen. Nach
// dem Ende des Hängers wertet der Hauptthread die Kopie aus (Module, Fenster,
// Atlas-Aktion) und meldet den Hänger über OnHang.
// Der Wächter arbeitet im Hauptthread nur die Antwort auf die Messnachricht.
// Gemessen wird erst, wenn die Nachrichtenschleife nach dem Laden frei ist;
// das Laden der übrigen Packages beim Start ist kein Hänger (die Startzeit
// samt Anteilen von Atlas meldet die Composition, Bericht N4). Ebenso das
// Beenden: ohne sichtbares Hauptfenster oder nach Application.Terminate wird
// nichts gemeldet.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.Hangs;

type
  TAtlasHangProc = reference to procedure(const AHang: TAtlasHang);

  TAtlasWatchdog = class
  private const
    cWM_ATLAS_PING = WM_APP + $4A1;
    cWM_ATLAS_STARTUP = WM_APP + $4A2;
    cPeriodMs = 100;
    // 512 KB unter x64: Ruft Atlas eine lange Arbeit der IDE auf, liegt sein Rahmen tief (#1989).
    cStackWords = 65536;
  private type
    TWatchThread = class(TThread)
    private
      FOwner: TAtlasWatchdog;
      /// <summary>Eigener Rahmen je Bericht: Der Thread arbeitet weiter, während der Hauptthread meldet.</summary>
      procedure Report(const AHang: TAtlasHang; const AAddresses: TArray<UInt64>);
      /// <summary>Wartet auf die Antwort zu ASeq; hält dabei einmal den Hänger fest (True).</summary>
      function AwaitPong(ASeq: Integer; ASentAt: Int64; out AHang: TAtlasHang): Boolean;
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
    FOnHang: TAtlasHangProc;
    FThresholdFunc: TFunc<Integer>;
    // Kopie beim Hänger; nur im Wächter-Thread beschrieben, vor dem Anhalten angelegt.
    FStack: array[0..cStackWords - 1] of NativeUInt;
    FStackCount: Integer;
    FIP: NativeUInt;
    // GetThreadContext verlangt unter x64 einen auf 16 Byte ausgerichteten TContext.
    FContextBuffer: TBytes;
    procedure WndProc(var AMessage: TMessage);
    procedure Capture;
    function TakeAddresses: TArray<UInt64>;
    class function NowMs: Int64; static;
    class function ForegroundWindowText: string; static;
  public
    /// <summary>AThreshold liefert die Schwelle (im Hauptthread gelesen).</summary>
    constructor Create(const AThreshold: TFunc<Integer>);
    destructor Destroy; override;
    /// <summary>Zeitpunkt in ms (monoton) für ALoadedAt.</summary>
    class function Timestamp: Int64; static;
    /// <summary>Im Hauptthread nach dem Ende eines Hängers über der Schwelle.</summary>
    property OnHang: TAtlasHangProc read FOnHang write FOnHang;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Diagnostics.StackCapture,
  System.Diagnostics,
  Vcl.Forms;

/// <summary>IDE läuft normal: Hauptfenster sichtbar, nicht im Beenden. Liest nur Felder, aus jedem Thread.</summary>
function Running: Boolean;
begin
  Result := not Application.Terminated and (Application.MainForm <> nil) and Application.MainForm.Visible;
end;

function InternalGetWindowText(AHWnd: HWND; APString: PWideChar; ACchMaxCount: Integer): Integer; stdcall;
  external user32 name 'InternalGetWindowText';

{ TAtlasWatchdog.TWatchThread }

function TAtlasWatchdog.TWatchThread.AwaitPong(ASeq: Integer; ASentAt: Int64; out AHang: TAtlasHang): Boolean;
begin
  Result := False;
  AHang := Default(TAtlasHang);
  while not Terminated and (TInterlocked.CompareExchange(FOwner.FPong, 0, 0) <> ASeq) do
  begin
    FOwner.FWake.WaitFor(25);
    if not Result and (NowMs - ASentAt >= TInterlocked.CompareExchange(FOwner.FThresholdMs, 0, 0)) and Running then
    begin
      Result := True;
      AHang.At := Now;
      AHang.Activity := TAtlasActivity.Running;
      AHang.Window := ForegroundWindowText;
      FOwner.Capture;
    end;
  end;
end;

procedure TAtlasWatchdog.TWatchThread.Execute;
var
  mSeq: Integer;
  mSentAt: Int64;
  mCaptured: Boolean;
  mHang: TAtlasHang;
begin
  try
    NameThreadForDebugging('Atlas.Watchdog');
    mSeq := 0;
    while not Terminated do
    begin
      if TInterlocked.CompareExchange(FOwner.FStarted, 0, 0) = 0 then
      begin
        FOwner.FWake.WaitFor(cPeriodMs);
        Continue;
      end;
      Inc(mSeq);
      mSentAt := NowMs;
      if not PostMessage(FOwner.FWindow, cWM_ATLAS_PING, WPARAM(mSeq), 0) then
      begin
        FOwner.FWake.WaitFor(cPeriodMs);
        Continue;
      end;
      mCaptured := AwaitPong(mSeq, mSentAt, mHang);
      if Terminated then
      begin
        Break;
      end;
      if mCaptured and Running then
      begin
        mHang.DurationMs := NowMs - mSentAt;
        Report(mHang, FOwner.TakeAddresses);
      end;
      FOwner.FWake.WaitFor(cPeriodMs);
    end;
  except
    // Der Wächter selbst darf die IDE nie stören (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Watchdog, E);
  end;
end;

procedure TAtlasWatchdog.TWatchThread.Report(const AHang: TAtlasHang; const AAddresses: TArray<UInt64>);
var
  mHang: TAtlasHang;
  mAddresses: TArray<UInt64>;
begin
  mHang := AHang;
  mAddresses := AAddresses;
  Queue(
    procedure
    var
      mModules: TArray<TAtlasModuleRange>;
    begin
      // Module erst jetzt im Hauptthread: Die Ladersperre ist frei.
      // Rahmen im Atlas-Modul mit Unit, Routine und Zeile, wenn die Map-Datei neben der BPL liegt.
      mModules := TAtlasIdeStackCapture.Modules;
      mHang.Frames := TAtlasIdeStackCapture.Symbolize(TAtlasStackScan.Frames(mAddresses, mModules));
      // Ob Atlas beteiligt ist, entscheidet der ganze Abzug, nicht nur die angezeigten Rahmen.
      mHang.AtlasFrame := TAtlasStackScan.FirstIn(mAddresses, mModules, 'Atlas');
      if mHang.AtlasFrame <> '' then
      begin
        mHang.AtlasFrame := TAtlasIdeStackCapture.Symbolize([mHang.AtlasFrame])[0];
      end;
      if Assigned(FOwner.FOnHang) then
      begin
        FOwner.FOnHang(mHang);
      end;
    end);
end;

{ TAtlasWatchdog }

constructor TAtlasWatchdog.Create(const AThreshold: TFunc<Integer>);
begin
  inherited Create;
  FThresholdFunc := AThreshold;
  FThresholdMs := 500;
  if Assigned(FThresholdFunc) then
  begin
    FThresholdMs := FThresholdFunc();
  end;
  FWake := TEvent.Create(nil, False, False, '');
  SetLength(FContextBuffer, SizeOf(TContext) + 16);
  FWindow := AllocateHWnd(WndProc);
  // Echter Handle des Hauptthreads (der Konstruktor läuft dort); GetCurrentThread ist nur ein Platzhalter.
  if not DuplicateHandle(GetCurrentProcess, GetCurrentThread, GetCurrentProcess, @FMainThread, 0, False,
    DUPLICATE_SAME_ACCESS) then
  begin
    FMainThread := 0;
  end;
  PostMessage(FWindow, cWM_ATLAS_STARTUP, 0, 0);
  FThread := TWatchThread.Create(True);
  FThread.FOwner := Self;
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

destructor TAtlasWatchdog.Destroy;
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
  begin
    DeallocateHWnd(FWindow);
  end;
  if FMainThread <> 0 then
  begin
    CloseHandle(FMainThread);
  end;
  FWake.Free;
  inherited;
end;

class function TAtlasWatchdog.NowMs: Int64;
begin
  Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

class function TAtlasWatchdog.Timestamp: Int64;
begin
  Result := NowMs;
end;

procedure TAtlasWatchdog.WndProc(var AMessage: TMessage);
begin
  try
    case AMessage.Msg of
      cWM_ATLAS_PING:
        begin
          TInterlocked.Exchange(FPong, Integer(AMessage.WParam));
          // Die Schwelle kann sich in den Optionen ändern; hier im Hauptthread lesen.
          if Assigned(FThresholdFunc) then
          begin
            TInterlocked.Exchange(FThresholdMs, FThresholdFunc());
          end;
        end;
      cWM_ATLAS_STARTUP:
        TInterlocked.Exchange(FStarted, 1);
    else
      AMessage.Result := DefWindowProc(FWindow, AMessage.Msg, AMessage.WParam, AMessage.LParam);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Watchdog, E);
  end;
end;

procedure TAtlasWatchdog.Capture;
var
  mContext: PContext;
  mStackPointer, mLimit: NativeUInt;
  mInfo: TMemoryBasicInformation;
begin
  mContext := PContext((NativeUInt(@FContextBuffer[0]) + 15) and not NativeUInt(15));
  FStackCount := 0;
  FIP := 0;
  if FMainThread = 0 then
  begin
    Exit;
  end;
  // Während der Hauptthread steht: nichts anfordern, nichts sperren, nur kopieren.
  if SuspendThread(FMainThread) = DWORD(-1) then
  begin
    Exit;
  end;
  try
    FillChar(mContext^, SizeOf(TContext), 0);
    mContext.ContextFlags := CONTEXT_CONTROL;
    if not GetThreadContext(FMainThread, mContext^) then
    begin
      Exit;
    end;
    {$IFDEF CPUX64}
    mStackPointer := mContext.Rsp;
    FIP := mContext.Rip;
    {$ELSE}
    mStackPointer := mContext.Esp;
    FIP := mContext.Eip;
    {$ENDIF}
    if VirtualQuery(Pointer(mStackPointer), mInfo, SizeOf(mInfo)) = 0 then
    begin
      Exit;
    end;
    mLimit := NativeUInt(mInfo.BaseAddress) + mInfo.RegionSize;
    FStackCount := (mLimit - mStackPointer) div SizeOf(NativeUInt);
    if FStackCount > cStackWords then
    begin
      FStackCount := cStackWords;
    end;
    Move(Pointer(mStackPointer)^, FStack[0], FStackCount * SizeOf(NativeUInt));
  finally
    ResumeThread(FMainThread);
  end;
end;

function TAtlasWatchdog.TakeAddresses: TArray<UInt64>;
var
  mIndex: Integer;
begin
  SetLength(Result, FStackCount + 1);
  Result[0] := FIP;
  for mIndex := 0 to FStackCount - 1 do
  begin
    Result[mIndex + 1] := FStack[mIndex];
  end;
end;

class function TAtlasWatchdog.ForegroundWindowText: string;
var
  mWindow: HWND;
  mBuffer: array[0..255] of WideChar;
  mLength_: Integer;
begin
  // InternalGetWindowText schickt keine Nachricht an das (hängende) Fenster.
  Result := '';
  mWindow := GetForegroundWindow;
  if mWindow = 0 then
  begin
    Exit;
  end;
  mLength_ := InternalGetWindowText(mWindow, mBuffer, Length(mBuffer));
  if mLength_ > 0 then
  begin
    SetString(Result, PWideChar(@mBuffer[0]), mLength_);
  end;
end;

end.