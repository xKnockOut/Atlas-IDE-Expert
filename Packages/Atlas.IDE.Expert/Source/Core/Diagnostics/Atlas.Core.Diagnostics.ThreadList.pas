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
    /// <summary>Wartet wie StopAll höchstens TAtlasShutdown.StopMs.</summary>
    destructor Destroy; override;
    /// <summary>AProc in einem neuen Thread ausführen; der Thread bleibt bis zu seinem Ende in der Liste.</summary>
    function Start(const AProc: TProc): TThread;
    /// <summary>Threads, die noch laufen (beendete zählen bis zum nächsten Start bzw. StopAll mit).</summary>
    function Count: Integer;
    /// <summary>Bis zu AMs auf alle warten und sie freigeben; True, wenn alle beendet waren. Wer dann noch
    /// läuft, gibt sich bei seiner Rückkehr selbst frei (letzter Ausweg, der Aufrufer protokolliert).</summary>
    function StopAll(AMs: Cardinal): Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown;

{ TAtlasThreadList }

constructor TAtlasThreadList.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FThreads := TList<TThread>.Create;
end;

destructor TAtlasThreadList.Destroy;
begin
  StopAll(TAtlasShutdown.StopMs);
  FThreads.Free;
  FLock.Free;
  inherited;
end;

procedure TAtlasThreadList.Prune;
var
  Done: TList<TThread>;
  Thread: TThread;
  Index: Integer;
begin
  Done := TList<TThread>.Create;
  try
    FLock.Enter;
    try
      for Index := FThreads.Count - 1 downto 0 do
        if FThreads[Index].Finished then
        begin
          Done.Add(FThreads[Index]);
          FThreads.Delete(Index);
        end;
    finally
      FLock.Leave;
    end;
    for Thread in Done do
      Thread.Free;
  finally
    Done.Free;
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
  Threads: TArray<TThread>;
  Thread: TThread;
begin
  FLock.Enter;
  try
    Threads := FThreads.ToArray;
    FThreads.Clear;
  finally
    FLock.Leave;
  end;
  Result := TAtlasShutdown.WaitForThreads(Threads, AMs);
  for Thread in Threads do
    if Thread.Finished then
      Thread.Free
    else
      // Wie TAtlasTimeLimit.StopAll: Liest der Thread FreeOnTerminate vor dem Setzen, bleibt höchstens ein Leck.
      Thread.FreeOnTerminate := True;
end;

end.
