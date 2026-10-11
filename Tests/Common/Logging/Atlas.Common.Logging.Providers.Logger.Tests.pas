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
  First, Second: TList<TLogEntry>;
  Logger: TLogger;
  LoggerRef: ILogger;
begin
  First := TList<TLogEntry>.Create;
  Second := TList<TLogEntry>.Create;
  try
    Logger := TLogger.Create;
    LoggerRef := Logger;
    Logger.AddSink(TCollectingSink.Create(First), TLogLevel.Debug);
    Logger.AddSink(TCollectingSink.Create(Second), TLogLevel.Debug);

    LoggerRef.Info('Hallo');

    Assert.AreEqual<NativeInt>(1, First.Count);
    Assert.AreEqual<NativeInt>(1, Second.Count);
    Assert.AreEqual('Hallo', First[0].Text);
    Assert.IsTrue(First[0].Level = TLogLevel.Info);
    LoggerRef := nil;
  finally
    Second.Free;
    First.Free;
  end;
end;

procedure TLoggerTests.FiltersByMinLevelOfEachSink;
var
  All, ErrorsOnly: TList<TLogEntry>;
  Logger: TLogger;
  LoggerRef: ILogger;
begin
  All := TList<TLogEntry>.Create;
  ErrorsOnly := TList<TLogEntry>.Create;
  try
    Logger := TLogger.Create;
    LoggerRef := Logger;
    Logger.AddSink(TCollectingSink.Create(All), TLogLevel.Debug);
    Logger.AddSink(TCollectingSink.Create(ErrorsOnly), TLogLevel.Error);

    LoggerRef.Debug('d');
    LoggerRef.Info('i');
    LoggerRef.Warning('w');
    LoggerRef.Error('e');

    Assert.AreEqual<NativeInt>(4, All.Count);
    Assert.AreEqual<NativeInt>(1, ErrorsOnly.Count);
    Assert.AreEqual('e', ErrorsOnly[0].Text);
    LoggerRef := nil;
  finally
    ErrorsOnly.Free;
    All.Free;
  end;
end;

procedure TLoggerTests.IgnoresFailingSink;
var
  Entries: TList<TLogEntry>;
  Logger: TLogger;
  LoggerRef: ILogger;
begin
  Entries := TList<TLogEntry>.Create;
  try
    Logger := TLogger.Create;
    LoggerRef := Logger;
    Logger.AddSink(TFailingSink.Create, TLogLevel.Debug);
    Logger.AddSink(TCollectingSink.Create(Entries), TLogLevel.Debug);

    Assert.WillNotRaise(
      procedure
      begin
        LoggerRef.Error('trotzdem');
      end);
    Assert.AreEqual<NativeInt>(1, Entries.Count);
    LoggerRef := nil;
  finally
    Entries.Free;
  end;
end;

procedure TLoggerTests.EntryTextContainsLevelAndText;
var
  Entry: TLogEntry;
begin
  Entry := TLogEntry.Create(EncodeDateTime(2026, 10, 7, 19, 50, 1, 234), TLogLevel.Warning, 'Achtung');
  Assert.AreEqual('2026-10-07 19:50:01.234 [WARNING] Achtung', Entry.ToText);
end;

initialization
  TDUnitX.RegisterTestFixture(TLoggerTests);

end.
