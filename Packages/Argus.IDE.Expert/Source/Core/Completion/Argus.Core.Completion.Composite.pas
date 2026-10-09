unit Argus.Core.Completion.Composite;

// Führt mehrere Datenquellen der Vervollständigung zusammen (#408). Ein Query
// geht an alle Quellen; ihre Teilmengen werden sofort weitergereicht, Complete
// kommt einmal, wenn alle Quellen fertig sind. Nach Cancel oder einem neuen
// Query gelangt nichts mehr aus dem alten Query an dessen Senke, auch wenn sich
// eine Quelle nicht daran hält.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Argus.Core.Completion.Contract;

type
  TArgusCompletionProviders = class(TInterfacedObject, IArgusCompletionProvider)
  private type
    /// <summary>Gemeinsamer Zustand eines Query; lebt, solange eine Teilsenke ihn hält.</summary>
    TQueryState = class(TInterfacedObject)
    private
      FLock: TCriticalSection;
      FSink: IArgusCompletionSink;
      FRemaining: Integer;
    public
      constructor Create(const ASink: IArgusCompletionSink; ACount: Integer);
      destructor Destroy; override;
      procedure Add(const AItems: TArgusCompletionItems);
      procedure Incomplete;
      procedure PartDone;
      procedure Cancel;
    end;

    /// <summary>Senke je Quelle; zählt deren Complete nur einmal.</summary>
    TPartSink = class(TInterfacedObject, IArgusCompletionSink)
    private
      FState: TQueryState;
      FStateRef: IInterface;
      FDone: Integer;
    public
      constructor Create(AState: TQueryState);
      procedure AddItems(const AItems: TArgusCompletionItems);
      procedure MarkIncomplete;
      procedure Complete;
    end;
  private
    FLock: TCriticalSection;
    FProviders: TArray<IArgusCompletionProvider>;
    FCurrent: TQueryState;
    FCurrentRef: IInterface;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AProvider: IArgusCompletionProvider);
    { IArgusCompletionProvider }
    procedure Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
    procedure Cancel;
  end;

implementation

{ TArgusCompletionProviders.TQueryState }

constructor TArgusCompletionProviders.TQueryState.Create(const ASink: IArgusCompletionSink; ACount: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSink := ASink;
  FRemaining := ACount;
end;

destructor TArgusCompletionProviders.TQueryState.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TArgusCompletionProviders.TQueryState.Add(const AItems: TArgusCompletionItems);
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

procedure TArgusCompletionProviders.TQueryState.Incomplete;
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

procedure TArgusCompletionProviders.TQueryState.PartDone;
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

procedure TArgusCompletionProviders.TQueryState.Cancel;
begin
  FLock.Enter;
  try
    FSink := nil;
  finally
    FLock.Leave;
  end;
end;

{ TArgusCompletionProviders.TPartSink }

constructor TArgusCompletionProviders.TPartSink.Create(AState: TQueryState);
begin
  inherited Create;
  FState := AState;
  FStateRef := AState;
end;

procedure TArgusCompletionProviders.TPartSink.AddItems(const AItems: TArgusCompletionItems);
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
    FState.Add(AItems);
end;

procedure TArgusCompletionProviders.TPartSink.MarkIncomplete;
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
    FState.Incomplete;
end;

procedure TArgusCompletionProviders.TPartSink.Complete;
begin
  if TInterlocked.Exchange(FDone, 1) = 0 then
    FState.PartDone;
end;

{ TArgusCompletionProviders }

constructor TArgusCompletionProviders.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TArgusCompletionProviders.Destroy;
begin
  Cancel;
  FLock.Free;
  inherited;
end;

procedure TArgusCompletionProviders.Add(const AProvider: IArgusCompletionProvider);
begin
  FLock.Enter;
  try
    FProviders := FProviders + [AProvider];
  finally
    FLock.Leave;
  end;
end;

procedure TArgusCompletionProviders.Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
var
  Providers: TArray<IArgusCompletionProvider>;
  State: TQueryState;
  StateRef: IInterface;
  Provider: IArgusCompletionProvider;
  Part: IArgusCompletionSink;
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
  for Provider in Providers do
  begin
    // Nicht direkt an den const-Parameter übergeben, sonst zählt niemand die Referenz.
    Part := TPartSink.Create(State);
    Provider.Query(AContext, Part);
  end;
end;

procedure TArgusCompletionProviders.Cancel;
var
  Providers: TArray<IArgusCompletionProvider>;
  Provider: IArgusCompletionProvider;
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
  for Provider in Providers do
    Provider.Cancel;
end;

end.
