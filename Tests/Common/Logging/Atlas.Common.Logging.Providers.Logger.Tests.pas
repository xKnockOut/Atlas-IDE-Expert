unit Atlas.Common.Logging.Providers.Logger.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLoggerTests = class
  public
    [Test]
    procedure DeliversEntryToAllSinks;
    [Test]
    procedure FiltersByMinLevelOfEachSink;
    [Test]
    procedure IgnoresFailingSink;
    [Test]
    procedure EntryTextContainsLevelAndText;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger;

type
  /// <summary>Sammelt Einträge in einer Liste, die dem Test gehört.</summary>
  TCollectingSink = class(TInterfacedObject, ILogSink)
  private
    FEntries: TList<TLogEntry>;
  public
    constructor Create(AEntries: TList<TLogEntry>);
    procedure Write(const AEntry: TLogEntry);
  end;

  TFailingSink = class(TInterfacedObject, ILogSink)
  public
    procedure Write(const AEntry: TLogEntry);
  end;

constructor TCollectingSink.Create(AEntries: TList<TLogEntry>);
begin
  inherited Create;
  FEntries := AEntries;
end;

procedure TCollectingSink.Write(const AEntry: TLogEntry);
begin
  FEntries.Add(AEntry);
end;

procedure TFailingSink.Write(const AEntry: TLogEntry);
begin
  raise EInOutError.Create('Senke defekt');
end;

{ TLoggerTests }

procedure TLoggerTests.DeliversEntryToAllSinks;
var
  mFirst, mSecond: TList<TLogEntry>;
  mLogger: TLogger;
  mLoggerRef: ILogger;
begin
  mFirst := TList<TLogEntry>.Create;
  mSecond := TList<TLogEntry>.Create;
  try
    mLogger := TLogger.Create;
    mLoggerRef := mLogger;
    mLogger.AddSink(TCollectingSink.Create(mFirst), TLogLevel.Debug);
    mLogger.AddSink(TCollectingSink.Create(mSecond), TLogLevel.Debug);

    mLoggerRef.Info('Hallo');

    Assert.AreEqual<NativeInt>(1, mFirst.Count);
    Assert.AreEqual<NativeInt>(1, mSecond.Count);
    Assert.AreEqual('Hallo', mFirst[0].Text);
    Assert.AreEqual<TLogLevel>(TLogLevel.Info, mFirst[0].Level);
    mLoggerRef := nil;
  finally
    mSecond.Free;
    mFirst.Free;
  end;
end;

procedure TLoggerTests.FiltersByMinLevelOfEachSink;
var
  mAll, mErrorsOnly: TList<TLogEntry>;
  mLogger: TLogger;
  mLoggerRef: ILogger;
begin
  mAll := TList<TLogEntry>.Create;
  mErrorsOnly := TList<TLogEntry>.Create;
  try
    mLogger := TLogger.Create;
    mLoggerRef := mLogger;
    mLogger.AddSink(TCollectingSink.Create(mAll), TLogLevel.Debug);
    mLogger.AddSink(TCollectingSink.Create(mErrorsOnly), TLogLevel.Error);

    mLoggerRef.Debug('d');
    mLoggerRef.Info('i');
    mLoggerRef.Warning('w');
    mLoggerRef.Error('e');

    Assert.AreEqual<NativeInt>(4, mAll.Count);
    Assert.AreEqual<NativeInt>(1, mErrorsOnly.Count);
    Assert.AreEqual('e', mErrorsOnly[0].Text);
    mLoggerRef := nil;
  finally
    mErrorsOnly.Free;
    mAll.Free;
  end;
end;

procedure TLoggerTests.IgnoresFailingSink;
var
  mEntries: TList<TLogEntry>;
  mLogger: TLogger;
  mLoggerRef: ILogger;
begin
  mEntries := TList<TLogEntry>.Create;
  try
    mLogger := TLogger.Create;
    mLoggerRef := mLogger;
    mLogger.AddSink(TFailingSink.Create, TLogLevel.Debug);
    mLogger.AddSink(TCollectingSink.Create(mEntries), TLogLevel.Debug);

    Assert.WillNotRaise(
      procedure
      begin
        mLoggerRef.Error('trotzdem');
      end);
    Assert.AreEqual<NativeInt>(1, mEntries.Count);
    mLoggerRef := nil;
  finally
    mEntries.Free;
  end;
end;

procedure TLoggerTests.EntryTextContainsLevelAndText;
var
  mEntry: TLogEntry;
begin
  mEntry := TLogEntry.Create(EncodeDateTime(2026, 10, 7, 19, 50, 1, 234), TLogLevel.Warning, 'Achtung');
  Assert.AreEqual('2026-10-07 19:50:01.234 [WARNING] Achtung', mEntry.ToText);
end;

initialization
  TDUnitX.RegisterTestFixture(TLoggerTests);

end.
