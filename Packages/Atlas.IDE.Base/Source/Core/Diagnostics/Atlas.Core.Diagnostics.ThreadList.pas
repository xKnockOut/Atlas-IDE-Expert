unit Atlas.Core.Diagnostics.ThreadList;

// Hintergrund-Threads, die bis zum Ende verfolgt werden (#886). Ein Thread mit
// FreeOnTerminate gibt sich nach seinem Ende selbst frei und gibt dabei die
// anonyme Methode frei, deren Klassenzeiger im Code des Plugins liegt. Lief
// das nach dem Entladen (die IDE entlädt Atlas mitten im Gruppen-Build), las
// rtl370.bpl aus nicht mehr geladenem bzw. neu geladenem Speicher. Hier
// gestartete Threads geben sich nicht selbst frei: Start räumt beendete auf,
// StopAll wartet beim Abbau auf alle und gibt sie frei.
// Gewartet wird auf Finished wie in TAtlasShutdown.WaitForThreads: Danach
// läuft im Thread nur noch Code der RTL (Ende des Threads).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TAtlasThreadList = class
  private
    FLock: TCriticalSection;
    FThreads: TList<TThread>;
    /// <summary>Beendete Threads aus der Liste nehmen und freigeben.</summary>
    procedure Prune;
  public
    constructor Create;
    /// <summary>Wartet wie StopAll höchstens TAtlasShutdown.cStopMs.</summary>
    destructor Destroy; override;
    /// <summary>AProc in einem neuen Thread ausführen; der Thread bleibt bis zu seinem Ende in der Liste.</summary>
    function Start(const AProc: TProc): TThread;
    /// <summary>Threads, die noch laufen (beendete zählen bis zum nächsten Start bzw. StopAll mit).</summary>
    function Count: Integer;
    /// <summary>Bis zu AMs auf alle warten und sie freigeben; True, wenn alle beendet waren. Wer dann noch
    /// läuft, geht an TAtlasOverdueThreads.</summary>
    function StopAll(AMs: Cardinal): Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.WorkerSlot;

{ TAtlasThreadList }

constructor TAtlasThreadList.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FThreads := TList<TThread>.Create;
end;

destructor TAtlasThreadList.Destroy;
begin
  StopAll(TAtlasShutdown.cStopMs);
  FThreads.Free;
  FLock.Free;
  inherited;
end;

procedure TAtlasThreadList.Prune;
var
  mDone: TList<TThread>;
  mThread: TThread;
  mIndex: Integer;
begin
  mDone := TList<TThread>.Create;
  try
    FLock.Enter;
    try
      for mIndex := FThreads.Count - 1 downto 0 do
      begin
        if FThreads[mIndex].Finished then
        begin
          mDone.Add(FThreads[mIndex]);
          FThreads.Delete(mIndex);
        end;
      end;
    finally
      FLock.Leave;
    end;
    for mThread in mDone do
    begin
      mThread.Free;
    end;
  finally
    mDone.Free;
  end;
end;

function TAtlasThreadList.Start(const AProc: TProc): TThread;
begin
  Prune;
  Result := TThread.CreateAnonymousThread(AProc);
  Result.FreeOnTerminate := False;
  FLock.Enter;
  try
    FThreads.Add(Result);
  finally
    FLock.Leave;
  end;
  Result.Start;
end;

function TAtlasThreadList.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FThreads.Count;
  finally
    FLock.Leave;
  end;
end;

function TAtlasThreadList.StopAll(AMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
  mThread: TThread;
begin
  FLock.Enter;
  try
    mThreads := FThreads.ToArray;
    FThreads.Clear;
  finally
    FLock.Leave;
  end;
  Result := TAtlasShutdown.WaitForThreads(mThreads, AMs);
  for mThread in mThreads do
  begin
    if mThread.Finished then
    begin
      mThread.Free;
    end
    else
    begin
      // Gibt der Thread nach seinem Ende frei; läuft er beim Entladen noch, bleibt Base im Speicher (T-101).
      TAtlasOverdueThreads.Adopt(mThread, HInstance);
    end;
  end;
end;

end.
