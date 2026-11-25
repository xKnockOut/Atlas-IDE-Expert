unit Atlas.Text.Locked.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextLockedTests = class
  public
    [Test]
    procedure ReadCopiesFieldAndReleasesLock;
    /// <summary>Die erste Sperrung einer gemeinsamen Sperre belegt nichts mehr; bei einem gewöhnlichen Objekt
    /// belegt sie den Monitor-Datensatz (Gegenprobe, dass die Messung greift).</summary>
    [Test]
    procedure SharedLockFirstEnterAllocatesNothing;
    [Test]
    procedure ReadsAndCountsUnderMonitor;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  Atlas.Text.Locked,
  System.Generics.Collections;

function FreeInOtherThread(ALock: TCriticalSection): Boolean;
var
  mFree: Boolean;
  mThread: TThread;
begin
  mFree := False;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      mFree := ALock.TryEnter;
      if mFree then
      begin
        ALock.Leave;
      end;
    end);
  mThread.FreeOnTerminate := False;
  try
    mThread.Start;
    mThread.WaitFor;
  finally
    mThread.Free;
  end;
  Result := mFree;
end;

/// <summary>Belegter Speicher des Prozesses in Byte.</summary>
function HeapInUse: Int64;
{$IFDEF FPC}
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;
{$ELSE}
var
  mState: TMemoryManagerState;
  mIndex: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(mState);
  {$WARN SYMBOL_PLATFORM DEFAULT}
  Result := Int64(mState.TotalAllocatedMediumBlockSize) + Int64(mState.TotalAllocatedLargeBlockSize);
  for mIndex := Low(mState.SmallBlockTypeStates) to High(mState.SmallBlockTypeStates) do
  begin
    Inc(Result, Int64(mState.SmallBlockTypeStates[mIndex].AllocatedBlockCount) *
      mState.SmallBlockTypeStates[mIndex].UseableBlockSize);
  end;
end;
{$ENDIF}

/// <summary>Speicher, den die erste Sperrung eines frischen Objekts belegt (AShared: aus TAtlasSharedLock.New);
/// das Kleinste aus drei Messungen, damit Belegungen anderer Threads nicht mitzählen.</summary>
function FirstEnterBytes(AShared: Boolean): Int64;
var
  mLock: TObject;
  mBefore: Int64;
  mBytes: Int64;
  mTry: Integer;
begin
  Result := High(Int64);
  for mTry := 1 to 3 do
  begin
    if AShared then
    begin
      mLock := TAtlasSharedLock.New;
    end
    else
    begin
      mLock := TObject.Create;
    end;
    try
      mBefore := HeapInUse;
      TMonitor.Enter(mLock);
      TMonitor.Exit(mLock);
      mBytes := HeapInUse - mBefore;
      if mBytes < Result then
      begin
        Result := mBytes;
      end;
    finally
      mLock.Free;
    end;
  end;
end;

{ TTextLockedTests }

procedure TTextLockedTests.ReadCopiesFieldAndReleasesLock;
var
  mLock: TCriticalSection;
  mField: string;
begin
  mLock := TCriticalSection.Create;
  try
    mField := 'Wert';
    Assert.AreEqual('Wert', TTextLocked.Read<string>(mLock, mField));
    Assert.IsTrue(FreeInOtherThread(mLock), 'Sperre nach dem Lesen frei');
  finally
    mLock.Free;
  end;
end;

procedure TTextLockedTests.SharedLockFirstEnterAllocatesNothing;
begin
  Assert.IsTrue(FirstEnterBytes(False) > 0, 'Gewöhnliches Objekt: Monitor-Datensatz beim ersten Sperren');
  Assert.AreEqual<Int64>(0, FirstEnterBytes(True), 'Gemeinsame Sperre: erste Sperrung ohne Belegung');
end;

procedure TTextLockedTests.ReadsAndCountsUnderMonitor;
var
  mLock: TObject;
  mValue: Integer;
  mEntries: TDictionary<string, Integer>;
begin
  mLock := TObject.Create;
  mEntries := TDictionary<string, Integer>.Create;
  try
    mValue := 42;
    Assert.AreEqual(42, TTextLocked.ReadMonitored<Integer>(mLock, mValue));
    mEntries.Add('a', 1);
    mEntries.Add('b', 2);
    Assert.AreEqual(2, TTextLocked.CountMonitored<string, Integer>(mLock, mEntries));
  finally
    mEntries.Free;
    mLock.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextLockedTests);

end.
