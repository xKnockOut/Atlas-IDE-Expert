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
    property Delay: Cardinal read FDelay;
    /// <summary>Wird bei Ausnahmen einer Aktion aufgerufen; der Thread läuft weiter.</summary>
    property OnError: TProc<Exception> read FOnError write FOnError;
  end;

implementation

const
  WaitForever = Cardinal($FFFFFFFF);

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
  Pending: TPending;
begin
  if FThread = nil then
  begin
    RunAction(AAction);
    Exit;
  end;
  Pending.Due := TThread.GetTickCount64 + FDelay;
  Pending.Action := AAction;
  TMonitor.Enter(FPending);
  try
    FPending.AddOrSetValue(AKey, Pending);
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
  finally
    TMonitor.Exit(FPending);
  end;
end;

function TDebouncer.TakeDue(out AAction: TProc): Boolean;
var
  Pair: TPair<string, TPending>;
  FirstKey: string;
  FirstDue: UInt64;
  Ticks: UInt64;
begin
  // Wartet unter der Sperre, bis eine Aktion fällig ist; False beim Beenden.
  AAction := nil;
  while not FStopping do
  begin
    FirstKey := '';
    FirstDue := High(UInt64);
    for Pair in FPending do
      if Pair.Value.Due < FirstDue then
      begin
        FirstKey := Pair.Key;
        FirstDue := Pair.Value.Due;
      end;
    Ticks := TThread.GetTickCount64;
    if FirstDue = High(UInt64) then
      TMonitor.Wait(FPending, WaitForever)
    else if FirstDue > Ticks then
      TMonitor.Wait(FPending, Cardinal(FirstDue - Ticks))
    else
    begin
      AAction := FPending[FirstKey].Action;
      FPending.Remove(FirstKey);
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TDebouncer.Execute;
var
  Action: TProc;
  Found: Boolean;
begin
  repeat
    TMonitor.Enter(FPending);
    try
      Found := TakeDue(Action);
    finally
      TMonitor.Exit(FPending);
    end;
    if Found then
      RunAction(Action);
  until not Found;
end;

procedure TDebouncer.RunAction(const AAction: TProc);
begin
  try
    AAction();
  except
    on E: Exception do
      if Assigned(FOnError) then
        FOnError(E);
  end;
end;

end.
