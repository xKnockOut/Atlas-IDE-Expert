unit Atlas.Core.Completion.Composite;

// Führt mehrere Datenquellen der Vervollständigung zusammen (#408). Ein Query
// geht an alle Quellen; ihre Teilmengen werden sofort weitergereicht, Complete
// kommt einmal, wenn alle Quellen fertig sind. Nach Cancel oder einem neuen
// Query gelangt nichts mehr aus dem alten Query an dessen Senke, auch wenn sich
// eine Quelle nicht daran hält.
// Absturzsicherheit (#493): Jede Quelle läuft mit Zeitlimit (TAtlasTimeLimit,
// Standard 200 ms) und über die Sicherung je Quelle. Wirft eine Quelle, hängt
// sie oder ist sie abgeschaltet, gilt ihr Teil als fertig; die übrigen Quellen
// liefern weiter. Nach 3 Fehlern in 5 Minuten fällt nur diese Quelle aus.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.TimeLimit;

type
  TAtlasCompletionProviders = class(TInterfacedObject, IAtlasCompletionProvider)
  private type
    /// <summary>Gemeinsamer Zustand eines Query; lebt, solange eine Teilsenke ihn hält.</summary>
    TQueryState = class(TInterfacedObject)
    private
      FLock: TCriticalSection;
      FSink: IAtlasCompletionSink;
      FRemaining: Integer;
    public
      constructor Create(const ASink: IAtlasCompletionSink; ACount: Integer);
      destructor Destroy; override;
      procedure Add(const AItems: TAtlasCompletionItems);
      procedure Incomplete;
      procedure PartDone;
      procedure Cancel;
    end;

    /// <summary>Senke je Quelle; zählt deren Complete nur einmal.</summary>
    TPartSink = class(TInterfacedObject, IAtlasCompletionSink)
    private
      FState: TQueryState;
      FStateRef: IInterface;
      FDone: Integer;
    public
      constructor Create(AState: TQueryState);
      procedure AddItems(const AItems: TAtlasCompletionItems);
      procedure MarkIncomplete;
      procedure Complete;
    end;
    TEntry = record
      Provider: IAtlasCompletionProvider;
      Name: string;
    end;
  private
    FLock: TCriticalSection;
    FProviders: TArray<TEntry>;
    FCurrent: TQueryState;
    FCurrentRef: IInterface;
    FTimeLimitMs: Integer;
    procedure QueryOne(const AEntry: TEntry; const AContext: TAtlasContext; const APart: IAtlasCompletionSink);
  public
    /// <summary>Name einer Quelle ohne IAtlasNamedProvider.</summary>
    const DefaultName = 'Vervollständigung';
    constructor Create;
    destructor Destroy; override;
    /// <summary>Quelle anmelden; ihr Name (IAtlasNamedProvider) gilt für die Sicherung je Quelle.</summary>
    procedure Add(const AProvider: IAtlasCompletionProvider);
    /// <summary>Zeitlimit je Quelle im aufrufenden Thread; -1 (Standard) = TAtlasTimeLimit.LimitMs.</summary>
    property TimeLimitMs: Integer read FTimeLimitMs write FTimeLimitMs;
    { IAtlasCompletionProvider }
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
  end;

implementation

function TimeLimitOf(ALimitMs: Integer): Integer;
begin
  Result := ALimitMs;
  if Result < 0 then
    Result := TAtlasTimeLimit.LimitMs;
end;

{ TAtlasCompletionProviders.TQueryState }

constructor TAtlasCompletionProviders.TQueryState.Create(const ASink: IAtlasCompletionSink; ACount: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSink := ASink;
  FRemaining := ACount;
end;

destructor TAtlasCompletionProviders.TQueryState.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TAtlasCompletionProviders.TQueryState.Add(const AItems: TAtlasCompletionItems);
begin
  if Length(AItems) = 0 then
    Exit;
  FLock.Enter;
  try
    if FSink <> nil then
      FSink.AddItems(AItems);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasCompletionProviders.TQueryState.Incomplete;
begin
  // Ist eine Quelle gekürzt, ist es die ganze Liste.
  FLock.Enter;
  try
    if FSink <> nil then
      FSink.MarkIncomplete;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasCompletionProviders.TQueryState.PartDone;
begin
  FLock.Enter;
  try
    Dec(FRemaining);
    if (FRemaining = 0) and (FSink <> nil) then
    begin
      FSink.Complete;
      FSink := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasCompletionProviders.TQueryState.Cancel;
begin
  FLock.Enter;
  try
    FSink := nil;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasCompletionProviders.TPartSink }

constructor TAtlasCompletionProviders.TPartSink.Create(AState: TQueryState);
begin
  inherited Create;
  FState := AState;
  FStateRef := AState;
end;

procedure TAtlasCompletionProviders.TPartSink.AddItems(const AItems: TAtlasCompletionItems);
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
    FState.Add(AItems);
end;

procedure TAtlasCompletionProviders.TPartSink.MarkIncomplete;
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
    FState.Incomplete;
end;

procedure TAtlasCompletionProviders.TPartSink.Complete;
begin
  if TInterlocked.Exchange(FDone, 1) = 0 then
    FState.PartDone;
end;

{ TAtlasCompletionProviders }

constructor TAtlasCompletionProviders.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FTimeLimitMs := -1;
end;

destructor TAtlasCompletionProviders.Destroy;
begin
  Cancel;
  FLock.Free;
  inherited;
end;

procedure TAtlasCompletionProviders.Add(const AProvider: IAtlasCompletionProvider);
var
  Entry: TEntry;
  Named: IAtlasNamedProvider;
begin
  Entry.Provider := AProvider;
  Entry.Name := DefaultName;
  if Supports(AProvider, IAtlasNamedProvider, Named) and (Named.ProviderName <> '') then
    Entry.Name := Named.ProviderName;
  FLock.Enter;
  try
    FProviders := FProviders + [Entry];
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasCompletionProviders.QueryOne(const AEntry: TEntry; const AContext: TAtlasContext;
  const APart: IAtlasCompletionSink);
var
  Provider: IAtlasCompletionProvider;
  Part: IAtlasCompletionSink;
  Context: TAtlasContext;
  Error: string;
begin
  if TAtlasGuard.ProviderDisabled(AEntry.Name) then
  begin
    APart.Complete;
    Exit;
  end;
  Provider := AEntry.Provider;
  Part := APart;
  Context := AContext;
  case TAtlasTimeLimit.Run(
    procedure
    begin
      Provider.Query(Context, Part);
    end, Error, FTimeLimitMs) of
    TAtlasTimedOutcome.Done:
      ;
    TAtlasTimedOutcome.Failed:
      begin
        Part.Complete;
        TAtlasGuard.ReportProvider(AEntry.Name, Error);
      end;
  else
    begin
      // Hängt: abbrechen, nicht länger warten; was später noch kommt, verwirft die Teilsenke.
      Part.Complete;
      try
        Provider.Cancel;
      except
        on E: Exception do
          TAtlasGuard.ReportProvider(AEntry.Name, E);
      end;
      TAtlasGuard.ReportProvider(AEntry.Name, Format('Zeitlimit von %d ms überschritten',
        [TimeLimitOf(FTimeLimitMs)]));
    end;
  end;
end;

procedure TAtlasCompletionProviders.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
var
  Providers: TArray<TEntry>;
  State: TQueryState;
  StateRef: IInterface;
  Entry: TEntry;
  Part: IAtlasCompletionSink;
begin
  Cancel;
  FLock.Enter;
  try
    Providers := FProviders;
    State := TQueryState.Create(ASink, Length(Providers));
    StateRef := State;
    FCurrent := State;
    FCurrentRef := StateRef;
  finally
    FLock.Leave;
  end;
  if Length(Providers) = 0 then
  begin
    ASink.Complete;
    Exit;
  end;
  for Entry in Providers do
  begin
    // Nicht direkt an den const-Parameter übergeben, sonst zählt niemand die Referenz.
    Part := TPartSink.Create(State);
    QueryOne(Entry, AContext, Part);
  end;
end;

procedure TAtlasCompletionProviders.Cancel;
var
  Providers: TArray<TEntry>;
  Entry: TEntry;
  Provider: IAtlasCompletionProvider;
begin
  FLock.Enter;
  try
    Providers := FProviders;
    if FCurrent <> nil then
      FCurrent.Cancel;
    FCurrent := nil;
    // Teilsenken, die noch laufen, halten den Zustand selbst am Leben.
    FCurrentRef := nil;
  finally
    FLock.Leave;
  end;
  for Entry in Providers do
  begin
    Provider := Entry.Provider;
    TAtlasGuard.RunProvider(Entry.Name,
      procedure
      begin
        Provider.Cancel;
      end);
  end;
end;

end.
