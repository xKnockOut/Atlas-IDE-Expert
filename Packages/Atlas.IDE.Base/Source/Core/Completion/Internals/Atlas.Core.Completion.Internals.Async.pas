unit Atlas.Core.Completion.Internals.Async;

// Basis für Datenquellen der Vervollständigung, die im Hintergrund arbeiten
// (#408). Query ruft Prepare im aufrufenden Thread – seit #493 meist ein
// Arbeiter von TAtlasTimeLimit (Composite.QueryOne), nicht der Hauptthread –
// und Fetch in einem eigenen Thread; dessen Ergebnis geht nur an die Senke,
// wenn der Query noch aktuell ist. Mehrere Threads dürfen gleichzeitig laufen,
// damit ein neuer Query nie auf einen langsamen alten warten muss. Beim
// Freigeben wartet die Quelle auf alle Threads (Entladen des Packages, #493).
// Fehler in Fetch und in RunInBackground zählt die Sicherung je Quelle
// (ProviderName, #493); IsFailure nimmt erwartbare Fälle aus (Server weg).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Diagnostics.Guard;

type
  /// <summary>True, sobald der Query abgebrochen oder durch einen neuen ersetzt ist.</summary>
  TAtlasCancelledFunc = reference to function: Boolean;

  /// <summary>Teilergebnis während Fetch (#616): geht sofort an die Senke, solange der Query aktuell ist.</summary>
  TAtlasEmitProc = reference to procedure(const AItems: TAtlasCompletionItems);

  /// <summary>Merker, ob die Quelle noch lebt; eingereihte Aufrufe halten ihn selbst.</summary>
  TAtlasAliveToken = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  TAtlasAsyncCompletionProvider = class(TInterfacedObject, IAtlasCompletionProvider, IAtlasNamedProvider)
  private
    FName: string;
    FToken: TAtlasAliveToken;
    FTokenRef: IInterface;
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    procedure ReapWorkers;
    function IsCurrent(AGeneration: Integer): Boolean;
    procedure Failed(E: Exception);
  protected
    /// <summary>Zählt E als Fehler der Quelle? Standard: ja.</summary>
    function IsFailure(E: Exception): Boolean; virtual;
    /// <summary>Im aufrufenden Thread vor dem Start, meist im Zeitlimit-Arbeiter (#493): weder VCL noch Open Tools
    /// API, kein Serverstart (Code-Review K-03). False = nichts zu tun (Complete sofort).
    /// AData geht unverändert an Fetch (nicht übernommen, muss bis zum Ende von Fetch leben).</summary>
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; virtual;
    /// <summary>Im Hintergrund. Ausnahmen gelten als leeres Ergebnis. AState.Incomplete: Die Liste ist
    /// gekürzt, beim Weitertippen neu fragen (#431); AState.Syntax: Hinweis bei unvollständigem Code (#457).
    /// AEmit liefert Teilergebnisse vorab (#616), auch aus
    /// anderen Threads, aber nur bis Fetch zurückkehrt; das Ergebnis kommt danach dazu.</summary>
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; virtual; abstract;
    /// <summary>Weitere Arbeit im Hintergrund (z. B. Details nachfragen); Shutdown wartet auch darauf.</summary>
    procedure RunInBackground(const AWork: TProc);
    /// <summary>Für Aufrufe per TAtlasMainThread.Queue: nur ausführen, solange Token.Alive gilt.</summary>
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
    { IAtlasNamedProvider }
    function ProviderName: string;
    /// <summary>Name für Sicherung, Meldungen und Einstellungsseite; '' = Klassenname.</summary>
    property Name: string read FName write FName;
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

function TAtlasAsyncCompletionProvider.ProviderName: string;
begin
  Result := FName;
  if Result = '' then
    Result := ClassName;
end;

function TAtlasAsyncCompletionProvider.IsFailure(E: Exception): Boolean;
begin
  Result := not (E is EAbort);
end;

procedure TAtlasAsyncCompletionProvider.Failed(E: Exception);
begin
  try
    if IsFailure(E) then
      TAtlasGuard.ReportProvider(ProviderName, E);
  except
    // Melden darf den Hintergrund-Thread nicht beenden.
  end;
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
        // Hintergrundarbeit darf die IDE nie stören (#493); gezählt je Quelle.
        on E: Exception do
          Failed(E);
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
  Worker := nil;
  FLock.Enter;
  try
    // Prepare läuft im Zeitlimit-Arbeiter und kann das Zeitlimit überdauern (Code-Review A-13): Ist die Anfrage
    // inzwischen überholt, abgebrochen oder hat Shutdown die Arbeiter eingesammelt, keine Vollanfrage mehr stellen.
    // Unter FLock und mit Start in der Sperre, damit Shutdown keinen danach gestarteten Arbeiter übersieht.
    if IsCurrent(Generation) then
    begin
      Worker := TThread.CreateAnonymousThread(
        procedure
        var
          Items: TAtlasCompletionItems;
          State: TAtlasFetchState;
        begin
          Items := nil;
          State := Default(TAtlasFetchState);
          try
            Items := Fetch(Context, Data,
              function: Boolean
              begin
                Result := not IsCurrent(Generation);
              end,
              procedure(const AItems: TAtlasCompletionItems)
              begin
                if (Length(AItems) > 0) and IsCurrent(Generation) then
                  Sink.AddItems(AItems);
              end, State);
          except
            // Server weg, Zeitlimit oder unerwartete Antwort: keine Einträge; Fehler zählt die Sicherung (#493).
            on E: Exception do
            begin
              Items := nil;
              State := Default(TAtlasFetchState);
              Failed(E);
            end;
          end;
          if IsCurrent(Generation) then
          begin
            Sink.AddItems(Items);
            if State.Incomplete then
              Sink.MarkIncomplete;
            if State.Syntax.Trust <> TAtlasSyntaxTrust.Sure then
              Sink.MarkSyntax(State.Syntax);
            Sink.Complete;
          end;
        end);
      Worker.FreeOnTerminate := False;
      FWorkers.Add(Worker);
      Worker.Start;
    end;
  finally
    FLock.Leave;
  end;
  // Überholt: Die Senken verwerfen veraltete Aufrufe; Composite erwartet je Teil ein Complete.
  if Worker = nil then
    ASink.Complete;
end;

end.
