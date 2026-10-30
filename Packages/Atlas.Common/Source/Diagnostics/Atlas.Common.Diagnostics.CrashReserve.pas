unit Atlas.Common.Diagnostics.CrashReserve;

// Vorher reservierter Puffer für Absturzfälle nach einem Stapelüberlauf
// (#1355). Nach EStackOverflow ist der Stapel des abgestürzten Threads bis zur
// Wiederherstellung der Schutzseite (TStackGuard) ungeschützt, und knapper
// Speicher ist oft die Folge desselben Fehlers. Deshalb schreibt der Server
// einen solchen Fall nicht auf dem erschöpften Stapel, sondern
// - in einem Thread, der beim Start mit eigenem Stapel (StackBytes) angelegt
//   wurde und nur darauf wartet, und
// - nachdem er eine beim Start belegte Speicherreserve (ReserveBytes)
//   freigegeben hat; danach wird sie neu belegt.
// Run wartet höchstens TimeoutMs; hängt das Schreiben, kehrt der Aufrufer
// trotzdem zurück (False). Eine Arbeit zur Zeit; weitere warten auf die
// laufende.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  TCrashReserve = class
  public const
    StackBytes = 1024 * 1024;
    ReserveBytes = 4 * 1024 * 1024;
    TimeoutMs = 10000;
  private type
    TWorker = class(TThread)
    private
      FOwner: TCrashReserve;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TCrashReserve);
    end;
  private
    FWorker: TWorker;
    FStart: TEvent;
    FDone: TEvent;
    FLock: TObject;
    FWork: TProc;
    FFailure: string;
    FStopping: Boolean;
    /// <summary>Übergebene und erledigte Arbeiten; weniger erledigte: Die Arbeit eines vergeblich wartenden Run
    /// läuft noch.</summary>
    FPosted: Integer;
    FFinished: Integer;
    FReserve: TBytes;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Führt AWork im reservierten Thread aus und wartet höchstens TimeoutMs. False, wenn die Zeit
    /// ablief oder AWork mit einer Ausnahme endete (AFailure: Klasse und Meldung).</summary>
    function Run(const AWork: TProc; out AFailure: string): Boolean;
  end;

implementation

const
  cForever = Cardinal($FFFFFFFF);

{ TCrashReserve.TWorker }

constructor TCrashReserve.TWorker.Create(AOwner: TCrashReserve);
begin
  inherited Create(True, StackBytes);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TCrashReserve.TWorker.Execute;
var
  mWork: TProc;
begin
  while True do
  begin
    FOwner.FStart.WaitFor(cForever);
    if FOwner.FStopping then
      Exit;
    mWork := FOwner.FWork;
    FOwner.FFailure := '';
    // Erst die Reserve abgeben, damit das Schreiben auch bei knappem Speicher Platz findet.
    FOwner.FReserve := nil;
    try
      if Assigned(mWork) then
        mWork();
    except
      on E: Exception do
        FOwner.FFailure := E.ClassName + ': ' + E.Message;
    end;
    mWork := nil;
    try
      SetLength(FOwner.FReserve, ReserveBytes);
    except
      // Kein Speicher für die neue Reserve: Der nächste Fall schreibt ohne.
      on EOutOfMemory do
        FOwner.FReserve := nil;
    end;
    FOwner.FDone.SetEvent;
    // Erst nach dem Signal: Ein Run nach einem abgelaufenen Warten setzt das alte Signal zurück (Run).
    AtomicIncrement(FOwner.FFinished);
  end;
end;

{ TCrashReserve }

constructor TCrashReserve.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FStart := TEvent.Create(nil, False, False, '');
  FDone := TEvent.Create(nil, False, False, '');
  SetLength(FReserve, ReserveBytes);
  FWorker := TWorker.Create(Self);
  FWorker.Start;
end;

destructor TCrashReserve.Destroy;
begin
  // Wirft der Konstruktor (SetLength der Reserve, Thread anlegen), fehlt der Arbeiter.
  if FWorker <> nil then
  begin
    System.TMonitor.Enter(FLock);
    try
      FStopping := True;
      FStart.SetEvent;
    finally
      System.TMonitor.Exit(FLock);
    end;
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FDone.Free;
  FStart.Free;
  FLock.Free;
  FWork := nil;
  inherited;
end;

function TCrashReserve.Run(const AWork: TProc; out AFailure: string): Boolean;
begin
  AFailure := '';
  System.TMonitor.Enter(FLock);
  try
    if FStopping then
      Exit(False);
    if FFinished < FPosted then
    begin
      AFailure := 'Der vorige Fall wird noch geschrieben';
      Exit(False);
    end;
    FWork := AWork;
    Inc(FPosted);
    FDone.ResetEvent;
    FStart.SetEvent;
    Result := FDone.WaitFor(TimeoutMs) = wrSignaled;
    if Result then
    begin
      AFailure := FFailure;
      Result := AFailure = '';
      FWork := nil;
    end
    else
    begin
      AFailure := Format('Zeitlimit von %d ms beim Schreiben überschritten', [TimeoutMs]);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
