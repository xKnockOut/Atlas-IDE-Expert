unit Atlas.Core.Completion.TestSupport;

// Gemeinsame Hilfen der Vervollständigungs-Tests (Quellen, Zeitgrenzen): eine Senke, die Einträge aus beliebigen
// Threads sammelt.

interface

uses
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract;

type
  /// <summary>Sammelt Einträge aus beliebigen Threads und meldet Complete über ein Ereignis.</summary>
  TCollectingSink = class(TInterfacedObject, IAtlasCompletionSink)
  private
    FLock: TCriticalSection;
    FNames: TList<string>;
    FCompleted: Integer;
    FDone: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddItems(const AItems: TAtlasCompletionItems);
    procedure MarkIncomplete;
    procedure MarkSyntax(const ANotice: TAtlasSyntaxNotice);
    procedure Complete;
    function WaitDone(ATimeoutMs: Cardinal): Boolean;
    function Names: string;
    function Completed: Integer;
  end;

/// <summary>Namen der Einträge in der Reihenfolge AOrder, mit Komma getrennt; Gruppenköpfe als #.</summary>
function OrderNames(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  Atlas.Core.Completion.Ranking;

{ TCollectingSink }

constructor TCollectingSink.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FNames := TList<string>.Create;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TCollectingSink.Destroy;
begin
  FDone.Free;
  FNames.Free;
  FLock.Free;
  inherited;
end;

procedure TCollectingSink.AddItems(const AItems: TAtlasCompletionItems);
var
  mItem: TAtlasCompletionItem;
begin
  FLock.Enter;
  try
    for mItem in AItems do
    begin
      FNames.Add(mItem.Name);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCollectingSink.MarkIncomplete;
begin
end;

procedure TCollectingSink.MarkSyntax(const ANotice: TAtlasSyntaxNotice);
begin
end;

procedure TCollectingSink.Complete;
begin
  TInterlocked.Increment(FCompleted);
  FDone.SetEvent;
end;

function TCollectingSink.WaitDone(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FDone.WaitFor(ATimeoutMs) = wrSignaled;
end;

function TCollectingSink.Names: string;
var
  mList: TArray<string>;
begin
  FLock.Enter;
  try
    mList := FNames.ToArray;
  finally
    FLock.Leave;
  end;
  TArray.Sort<string>(mList);
  Result := string.Join(',', mList);
end;

function TCollectingSink.Completed: Integer;
begin
  Result := TInterlocked.CompareExchange(FCompleted, 0, 0);
end;

function OrderNames(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    if TAtlasRanking.IsHeader(mIndex) then
    begin
      Result := Result + '#';
    end
    else
    begin
      Result := Result + AItems[mIndex].Name;
    end;
  end;
end;

end.
