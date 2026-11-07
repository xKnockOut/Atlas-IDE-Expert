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
    procedure Failed(AE: Exception);
  protected
    /// <summary>Zählt E als Fehler der Quelle? Standard: ja.</summary>
    function IsFailure(AE: Exception): Boolean; virtual;
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
  begin
    Result := ClassName;
  end;
end;

function TAtlasAsyncCompletionProvider.IsFailure(AE: Exception): Boolean;
begin
  Result := not (AE is EAbort);
end;

procedure TAtlasAsyncCompletionProvider.Failed(AE: Exception);
begin
  try
    if IsFailure(AE) then
    begin
      TAtlasGuard.ReportProvider(ProviderName, AE);
    end;
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
  mWorker: TThread;
begin
  ReapWorkers;
  mWorker := TThread.CreateAnonymousThread(
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
  mWorker.FreeOnTerminate := False;
  FLock.Enter;
  try
    FWorkers.Add(mWorker);
  finally
    FLock.Leave;
  end;
  mWorker.Start;
end;

procedure TAtlasAsyncCompletionProvider.ReapWorkers;
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    for mIndex := FWorkers.Count - 1 downto 0 do
    begin
      if FWorkers[mIndex].Finished then
      begin
        FWorkers[mIndex].Free;
        FWorkers.Delete(mIndex);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasAsyncCompletionProvider.Shutdown;
var
  mWorkers: TArray<TThread>;
  mWorker: TThread;
begin
  Cancel;
  FLock.Enter;
  try
    mWorkers := FWorkers.ToArray;
    FWorkers.Clear;
  finally
    FLock.Leave;
  end;
  for mWorker in mWorkers do
  begin
    mWorker.WaitFor;
    mWorker.Free;
  end;
end;

procedure TAtlasAsyncCompletionProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

procedure TAtlasAsyncCompletionProvider.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
var
  mGeneration: Integer;
  mContext: TAtlasContext;
  mSink: IAtlasCompletionSink;
  mData: TObject;
  mWorker: TThread;
begin
  mGeneration := TInterlocked.Increment(FGeneration);
  ReapWorkers;
  if not Prepare(AContext, mData) then
  begin
    ASink.Complete;
    Exit;
  end;
  mContext := AContext;
  mSink := ASink;
  mWorker := nil;
  FLock.Enter;
  try
    // Prepare läuft im Zeitlimit-Arbeiter und kann das Zeitlimit überdauern (Code-Review A-13): Ist die Anfrage
    // inzwischen überholt, abgebrochen oder hat Shutdown die Arbeiter eingesammelt, keine Vollanfrage mehr stellen.
    // Unter FLock und mit Start in der Sperre, damit Shutdown keinen danach gestarteten Arbeiter übersieht.
    if IsCurrent(mGeneration) then
    begin
      mWorker := TThread.CreateAnonymousThread(
        procedure
        var
          Items: TAtlasCompletionItems;
          State: TAtlasFetchState;
        begin
          Items := nil;
          State := Default(TAtlasFetchState);
          try
            Items := Fetch(mContext, mData,
              function: Boolean
              begin
                Result := not IsCurrent(mGeneration);
              end,
              procedure(const AItems: TAtlasCompletionItems)
              begin
                if (Length(AItems) > 0) and IsCurrent(mGeneration) then
                begin
                  mSink.AddItems(AItems);
                end;
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
          if IsCurrent(mGeneration) then
          begin
            mSink.AddItems(Items);
            if State.Incomplete then
            begin
              mSink.MarkIncomplete;
            end;
            if State.Syntax.Trust <> TAtlasSyntaxTrust.Sure then
            begin
              mSink.MarkSyntax(State.Syntax);
            end;
            mSink.Complete;
          end;
        end);
      mWorker.FreeOnTerminate := False;
      FWorkers.Add(mWorker);
      mWorker.Start;
    end;
  finally
    FLock.Leave;
  end;
  // Überholt: Die Senken verwerfen veraltete Aufrufe; Composite erwartet je Teil ein Complete.
  if mWorker = nil then
  begin
    ASink.Complete;
  end;
end;

end.
