unit Atlas.Common.Lsp.Internals.Debouncer;

// Verzögert Aktionen je Schlüssel: Wird ein Schlüssel vor Ablauf der
// Verzögerung erneut geplant, ersetzt die neue Aktion die alte und die
// Verzögerung beginnt von vorn. So wird beim schnellen Tippen nur der letzte
// Stand ausgewertet. Die Aktionen laufen nacheinander in einem eigenen Thread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TDebouncer = class
  private type
    TPending = record
      Due: UInt64;
      Action: TProc;
    end;
  private
    FDelay: Cardinal;
    FPending: TDictionary<string, TPending>;
    FStopping: Boolean;
    /// <summary>Eine Aktion läuft gerade (unter der Sperre von FPending).</summary>
    FRunning: Boolean;
    FThread: TThread;
    FOnError: TProc<Exception>;
    procedure Execute;
    function TakeDue(out AAction: TProc): Boolean;
    procedure RunAction(const AAction: TProc);
  public
    /// <summary>Bei ADelayMs = 0 laufen Aktionen sofort im aufrufenden Thread (für Tests).</summary>
    constructor Create(ADelayMs: Cardinal);
    /// <summary>Verwirft geplante Aktionen und wartet auf eine laufende.</summary>
    destructor Destroy; override;
    procedure Schedule(const AKey: string; const AAction: TProc);
    /// <summary>Verwirft die geplante Aktion des Schlüssels, eine laufende nicht.</summary>
    procedure Cancel(const AKey: string);
    /// <summary>Wartet, bis nichts mehr geplant ist und keine Aktion läuft (#177: Messung erst in Ruhe).
    /// False, wenn das nicht innerhalb von ATimeoutMs geschieht.</summary>
    function WaitIdle(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Wird bei Ausnahmen einer Aktion aufgerufen; der Thread läuft weiter.</summary>
    property OnError: TProc<Exception> read FOnError write FOnError;
  end;

implementation

const
  cWaitForever = Cardinal($FFFFFFFF);

{ TDebouncer }

constructor TDebouncer.Create(ADelayMs: Cardinal);
begin
  inherited Create;
  FDelay := ADelayMs;
  FPending := TDictionary<string, TPending>.Create;
  if FDelay > 0 then
  begin
    FThread := TThread.CreateAnonymousThread(Execute);
    FThread.FreeOnTerminate := False;
    FThread.Start;
  end;
end;

destructor TDebouncer.Destroy;
begin
  if FThread <> nil then
  begin
    TMonitor.Enter(FPending);
    try
      FStopping := True;
      FPending.Clear;
      TMonitor.PulseAll(FPending);
    finally
      TMonitor.Exit(FPending);
    end;
    FThread.WaitFor;
    FThread.Free;
  end;
  FPending.Free;
  inherited;
end;

procedure TDebouncer.Schedule(const AKey: string; const AAction: TProc);
var
  mPending: TPending;
begin
  if FThread = nil then
  begin
    RunAction(AAction);
    Exit;
  end;
  mPending.Due := TThread.GetTickCount64 + FDelay;
  mPending.Action := AAction;
  TMonitor.Enter(FPending);
  try
    FPending.AddOrSetValue(AKey, mPending);
    TMonitor.PulseAll(FPending);
  finally
    TMonitor.Exit(FPending);
  end;
end;

procedure TDebouncer.Cancel(const AKey: string);
begin
  TMonitor.Enter(FPending);
  try
    FPending.Remove(AKey);
    TMonitor.PulseAll(FPending);
  finally
    TMonitor.Exit(FPending);
  end;
end;

function TDebouncer.WaitIdle(ATimeoutMs: Cardinal): Boolean;
var
  mDeadline, mTicks: UInt64;
begin
  mDeadline := TThread.GetTickCount64 + ATimeoutMs;
  TMonitor.Enter(FPending);
  try
    while (FPending.Count > 0) or FRunning do
    begin
      mTicks := TThread.GetTickCount64;
      if mTicks >= mDeadline then
      begin
        Exit(False);
      end;
      TMonitor.Wait(FPending, Cardinal(mDeadline - mTicks));
    end;
    Result := True;
  finally
    TMonitor.Exit(FPending);
  end;
end;

function TDebouncer.TakeDue(out AAction: TProc): Boolean;
var
  mPair: TPair<string, TPending>;
  mFirstKey: string;
  mFirstDue: UInt64;
  mTicks: UInt64;
begin
  // Wartet unter der Sperre, bis eine Aktion fällig ist; False beim Beenden.
  AAction := nil;
  while not FStopping do
  begin
    mFirstKey := '';
    mFirstDue := High(UInt64);
    for mPair in FPending do
    begin
      if mPair.Value.Due < mFirstDue then
      begin
        mFirstKey := mPair.Key;
        mFirstDue := mPair.Value.Due;
      end;
    end;
    mTicks := TThread.GetTickCount64;
    if mFirstDue = High(UInt64) then
    begin
      TMonitor.Wait(FPending, cWaitForever);
    end
    else if mFirstDue > mTicks then
    begin
      TMonitor.Wait(FPending, Cardinal(mFirstDue - mTicks));
    end
    else
    begin
      AAction := FPending[mFirstKey].Action;
      FPending.Remove(mFirstKey);
      FRunning := True;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TDebouncer.Execute;
var
  mAction: TProc;
  mFound: Boolean;
begin
  repeat
    TMonitor.Enter(FPending);
    try
      mFound := TakeDue(mAction);
    finally
      TMonitor.Exit(FPending);
    end;
    if mFound then
    begin
      RunAction(mAction);
      // Die Aktion samt eingefangener Variablen erst freigeben, dann Ruhe melden.
      mAction := nil;
      TMonitor.Enter(FPending);
      try
        FRunning := False;
        TMonitor.PulseAll(FPending);
      finally
        TMonitor.Exit(FPending);
      end;
    end;
  until not mFound;
end;

procedure TDebouncer.RunAction(const AAction: TProc);
begin
  try
    AAction();
  except
    on E: Exception do
      if Assigned(FOnError) then
      begin
        FOnError(E);
      end;
  end;
end;

end.
