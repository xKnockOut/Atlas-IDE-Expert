unit Atlas.Core.Completion.Composite;

// Führt mehrere Datenquellen der Vervollständigung zusammen (#408). Ein Query
// geht an alle Quellen; ihre Teilmengen werden sofort weitergereicht, Complete
// kommt einmal, wenn alle Quellen fertig sind. Nach Cancel oder einem neuen
// Query gelangt nichts mehr aus dem alten Query an dessen Senke, auch wenn sich
// eine Quelle nicht daran hält.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Completion.Contract;

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
  private
    FLock: TCriticalSection;
    FProviders: TArray<IAtlasCompletionProvider>;
    FCurrent: TQueryState;
    FCurrentRef: IInterface;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AProvider: IAtlasCompletionProvider);
    { IAtlasCompletionProvider }
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
  end;

implementation

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
end;

destructor TAtlasCompletionProviders.Destroy;
begin
  Cancel;
  FLock.Free;
  inherited;
end;

procedure TAtlasCompletionProviders.Add(const AProvider: IAtlasCompletionProvider);
begin
  FLock.Enter;
  try
    FProviders := FProviders + [AProvider];
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasCompletionProviders.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
var
  Providers: TArray<IAtlasCompletionProvider>;
  State: TQueryState;
  StateRef: IInterface;
  Provider: IAtlasCompletionProvider;
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
  for Provider in Providers do
  begin
    // Nicht direkt an den const-Parameter übergeben, sonst zählt niemand die Referenz.
    Part := TPartSink.Create(State);
    Provider.Query(AContext, Part);
  end;
end;

procedure TAtlasCompletionProviders.Cancel;
var
  Providers: TArray<IAtlasCompletionProvider>;
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
  for Provider in Providers do
    Provider.Cancel;
end;

end.
