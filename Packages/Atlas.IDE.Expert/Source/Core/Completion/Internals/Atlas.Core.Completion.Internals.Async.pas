unit Atlas.Core.Completion.Internals.Async;

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
  Atlas.Core.Completion.Contract;

type
  /// <summary>True, sobald der Query abgebrochen oder durch einen neuen ersetzt ist.</summary>
  TAtlasCancelledFunc = reference to function: Boolean;

  /// <summary>Merker, ob die Quelle noch lebt; eingereihte Aufrufe halten ihn selbst.</summary>
  TAtlasAliveToken = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  TAtlasAsyncCompletionProvider = class(TInterfacedObject, IAtlasCompletionProvider)
  private
    FToken: TAtlasAliveToken;
    FTokenRef: IInterface;
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    procedure ReapWorkers;
    function IsCurrent(AGeneration: Integer): Boolean;
  protected
    /// <summary>Im aufrufenden Thread vor dem Start; False = nichts zu tun (Complete sofort).
    /// AData geht unverändert an Fetch (nicht übernommen, muss bis zum Ende von Fetch leben).</summary>
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; virtual;
    /// <summary>Im Hintergrund. Ausnahmen gelten als leeres Ergebnis. AIncomplete: Die Liste ist
    /// gekürzt, beim Weitertippen neu fragen (#431).</summary>
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      out AIncomplete: Boolean): TAtlasCompletionItems; virtual; abstract;
    /// <summary>Weitere Arbeit im Hintergrund (z. B. Details nachfragen); Shutdown wartet auch darauf.</summary>
    procedure RunInBackground(const AWork: TProc);
    /// <summary>Für Aufrufe per TThread.Queue: nur ausführen, solange Token.Alive gilt.</summary>
    property Token: TAtlasAliveToken read FToken;
    property TokenRef: IInterface read FTokenRef;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bricht ab und wartet auf alle laufenden Threads.</summary>
    procedure Shutdown;
    { IAtlasCompletionProvider }
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
  end;

implementation

{ TAtlasAsyncCompletionProvider }

constructor TAtlasAsyncCompletionProvider.Create;
begin
  inherited Create;
  FToken := TAtlasAliveToken.Create;
  FToken.Alive := True;
  FTokenRef := FToken;
  FLock := TCriticalSection.Create;
  FWorkers := TList<TThread>.Create;
end;

destructor TAtlasAsyncCompletionProvider.Destroy;
begin
  Shutdown;
  FToken.Alive := False;
  FTokenRef := nil;
  FWorkers.Free;
  FLock.Free;
  inherited;
end;

function TAtlasAsyncCompletionProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
begin
  AData := nil;
  Result := True;
end;

function TAtlasAsyncCompletionProvider.IsCurrent(AGeneration: Integer): Boolean;
begin
  Result := TInterlocked.CompareExchange(FGeneration, 0, 0) = AGeneration;
end;

procedure TAtlasAsyncCompletionProvider.RunInBackground(const AWork: TProc);
var
  Worker: TThread;
begin
  ReapWorkers;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AWork();
      except
        // Hintergrundarbeit darf die IDE nie stören (#493).
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

procedure TAtlasAsyncCompletionProvider.ReapWorkers;
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

procedure TAtlasAsyncCompletionProvider.Shutdown;
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

procedure TAtlasAsyncCompletionProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

procedure TAtlasAsyncCompletionProvider.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
var
  Generation: Integer;
  Context: TAtlasContext;
  Sink: IAtlasCompletionSink;
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
      Items: TAtlasCompletionItems;
      Incomplete: Boolean;
    begin
      Items := nil;
      Incomplete := False;
      try
        Items := Fetch(Context, Data,
          function: Boolean
          begin
            Result := not IsCurrent(Generation);
          end, Incomplete);
      except
        // Server weg, Zeitlimit oder unerwartete Antwort: keine Einträge.
        Items := nil;
      end;
      if IsCurrent(Generation) then
      begin
        Sink.AddItems(Items);
        if Incomplete then
          Sink.MarkIncomplete;
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
