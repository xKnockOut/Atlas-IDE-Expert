unit Argus.Core.Completion.Internals.Async;

// Basis für Datenquellen der Vervollständigung, die im Hintergrund arbeiten
// (#408). Query ruft Prepare im aufrufenden Thread (dem Hauptthread der IDE)
// und Fetch in einem eigenen Thread; dessen Ergebnis geht nur an die Senke,
// wenn der Query noch aktuell ist. Mehrere Threads dürfen gleichzeitig laufen,
// damit ein neuer Query nie auf einen langsamen alten warten muss. Beim
// Freigeben wartet die Quelle auf alle Threads (Entladen des Packages, #493).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Argus.Core.Completion.Contract;

type
  /// <summary>True, sobald der Query abgebrochen oder durch einen neuen ersetzt ist.</summary>
  TArgusCancelledFunc = reference to function: Boolean;

  TArgusAsyncCompletionProvider = class(TInterfacedObject, IArgusCompletionProvider)
  private
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    procedure ReapWorkers;
    function IsCurrent(AGeneration: Integer): Boolean;
  protected
    /// <summary>Im aufrufenden Thread vor dem Start; False = nichts zu tun (Complete sofort).
    /// AData geht unverändert an Fetch (nicht übernommen, muss bis zum Ende von Fetch leben).</summary>
    function Prepare(const AContext: TArgusContext; out AData: TObject): Boolean; virtual;
    /// <summary>Im Hintergrund. Ausnahmen gelten als leeres Ergebnis.</summary>
    function Fetch(const AContext: TArgusContext; AData: TObject;
      const ACancelled: TArgusCancelledFunc): TArgusCompletionItems; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bricht ab und wartet auf alle laufenden Threads.</summary>
    procedure Shutdown;
    { IArgusCompletionProvider }
    procedure Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
    procedure Cancel;
  end;

implementation

{ TArgusAsyncCompletionProvider }

constructor TArgusAsyncCompletionProvider.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWorkers := TList<TThread>.Create;
end;

destructor TArgusAsyncCompletionProvider.Destroy;
begin
  Shutdown;
  FWorkers.Free;
  FLock.Free;
  inherited;
end;

function TArgusAsyncCompletionProvider.Prepare(const AContext: TArgusContext; out AData: TObject): Boolean;
begin
  AData := nil;
  Result := True;
end;

function TArgusAsyncCompletionProvider.IsCurrent(AGeneration: Integer): Boolean;
begin
  Result := TInterlocked.CompareExchange(FGeneration, 0, 0) = AGeneration;
end;

procedure TArgusAsyncCompletionProvider.ReapWorkers;
var
  Index: Integer;
begin
  FLock.Enter;
  try
    for Index := FWorkers.Count - 1 downto 0 do
      if FWorkers[Index].Finished then
      begin
        FWorkers[Index].Free;
        FWorkers.Delete(Index);
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TArgusAsyncCompletionProvider.Shutdown;
var
  Workers: TArray<TThread>;
  Worker: TThread;
begin
  Cancel;
  FLock.Enter;
  try
    Workers := FWorkers.ToArray;
    FWorkers.Clear;
  finally
    FLock.Leave;
  end;
  for Worker in Workers do
  begin
    Worker.WaitFor;
    Worker.Free;
  end;
end;

procedure TArgusAsyncCompletionProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

procedure TArgusAsyncCompletionProvider.Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
var
  Generation: Integer;
  Context: TArgusContext;
  Sink: IArgusCompletionSink;
  Data: TObject;
  Worker: TThread;
begin
  Generation := TInterlocked.Increment(FGeneration);
  ReapWorkers;
  if not Prepare(AContext, Data) then
  begin
    ASink.Complete;
    Exit;
  end;
  Context := AContext;
  Sink := ASink;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Items: TArgusCompletionItems;
    begin
      Items := nil;
      try
        Items := Fetch(Context, Data,
          function: Boolean
          begin
            Result := not IsCurrent(Generation);
          end);
      except
        // Server weg, Zeitlimit oder unerwartete Antwort: keine Einträge.
        Items := nil;
      end;
      if IsCurrent(Generation) then
      begin
        Sink.AddItems(Items);
        Sink.Complete;
      end;
    end);
  Worker.FreeOnTerminate := False;
  FLock.Enter;
  try
    FWorkers.Add(Worker);
  finally
    FLock.Leave;
  end;
  Worker.Start;
end;

end.
