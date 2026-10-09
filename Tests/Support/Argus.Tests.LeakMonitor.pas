unit Argus.Tests.LeakMonitor;

// Speicherleck-Überwachung für DUnitX. Misst über GetMemoryManagerState des
// eingebauten Speichermanagers (FastMM-basiert), wie viele Bytes Setup, Test
// und TearDown netto belegt haben. DUnitX wertet einen Test mit Rest als
// Speicherleck; Tests mit gewollten Caches tragen [IgnoreMemoryLeaks].

interface

uses
  DUnitX.TestFramework;

type
  TLeakMonitor = class(TInterfacedObject, IMemoryLeakMonitor)
  private
    FSetUpBefore: Int64;
    FSetUpAllocated: Int64;
    FTestBefore: Int64;
    FTestAllocated: Int64;
    FTearDownBefore: Int64;
    FTearDownAllocated: Int64;
  public
    procedure PreSetup;
    procedure PostSetUp;
    procedure PreTest;
    procedure PostTest;
    procedure PreTearDown;
    procedure PostTearDown;
    function SetUpMemoryAllocated: Int64;
    function TearDownMemoryAllocated: Int64;
    function TestMemoryAllocated: Int64;
  end;

/// <summary>Aktuell belegte Bytes laut Speichermanager.</summary>
function AllocatedBytes: Int64;

/// <summary>Meldet TLeakMonitor als Überwachung bei DUnitX an.</summary>
procedure RegisterLeakMonitor;

implementation

// Delphi 13 liefert DUnitX mit DUnitX.ServiceLocator (TDUnitXServiceLocator)
// statt des früheren DUnitX.IoC (TDUnitXIoC); die Schnittstelle ist gleich.
uses
  DUnitX.ServiceLocator;

function AllocatedBytes: Int64;
var
  State: TMemoryManagerState;
  I: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(State);
  {$WARN SYMBOL_PLATFORM ON}
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(Result, Int64(State.SmallBlockTypeStates[I].AllocatedBlockCount) *
      State.SmallBlockTypeStates[I].UseableBlockSize);
end;

procedure RegisterLeakMonitor;
begin
  TDUnitXServiceLocator.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function: IMemoryLeakMonitor
    begin
      Result := TLeakMonitor.Create;
    end);
end;

{ TLeakMonitor }

procedure TLeakMonitor.PreSetup;
begin
  FSetUpBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostSetUp;
begin
  FSetUpAllocated := AllocatedBytes - FSetUpBefore;
end;

procedure TLeakMonitor.PreTest;
begin
  FTestBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTest;
begin
  FTestAllocated := AllocatedBytes - FTestBefore;
end;

procedure TLeakMonitor.PreTearDown;
begin
  FTearDownBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTearDown;
begin
  FTearDownAllocated := AllocatedBytes - FTearDownBefore;
end;

function TLeakMonitor.SetUpMemoryAllocated: Int64;
begin
  Result := FSetUpAllocated;
end;

function TLeakMonitor.TearDownMemoryAllocated: Int64;
begin
  Result := FTearDownAllocated;
end;

function TLeakMonitor.TestMemoryAllocated: Int64;
begin
  Result := FTestAllocated;
end;

end.
