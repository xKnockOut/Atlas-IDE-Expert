unit Atlas.Text.IndexCache.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextIndexCacheTests = class
  public
    [Test]
    procedure ReadVarSevenBitsPerByte;
    [Test]
    procedure ReadPastLimitFails;
    [Test]
    procedure ReadIntSignInLowestBit;
    [Test]
    procedure ReadStringFromTable;
    [Test]
    procedure MagicAndChecksum;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.IndexCache;

function ReaderOf(const ABytes: TBytes): TIndexCacheReader;
begin
  Result.Data := ABytes;
  Result.Position := 0;
  Result.Limit := Length(ABytes);
end;

{ TTextIndexCacheTests }

procedure TTextIndexCacheTests.ReadVarSevenBitsPerByte;
var
  mReader: TIndexCacheReader;
begin
  mReader := ReaderOf(TBytes.Create($05, $AC, $02, $00));
  Assert.AreEqual<UInt64>(5, mReader.ReadVar);
  Assert.AreEqual<UInt64>(300, mReader.ReadVar);
  Assert.AreEqual(0, mReader.ReadCount);
  Assert.AreEqual(4, mReader.Position);
end;

procedure TTextIndexCacheTests.ReadPastLimitFails;
begin
  Assert.WillRaise(
    procedure
    var
      mReader: TIndexCacheReader;
    begin
      mReader := ReaderOf(TBytes.Create($80));
      mReader.ReadVar;
    end, EIndexCacheFormat);
  Assert.WillRaise(
    procedure
    var
      mReader: TIndexCacheReader;
    begin
      // 9 Einträge in 1 Byte gibt es nicht.
      mReader := ReaderOf(TBytes.Create($09));
      mReader.ReadCount;
    end, EIndexCacheFormat);
  Assert.WillRaise(
    procedure
    var
      mReader: TIndexCacheReader;
    begin
      mReader := ReaderOf(TBytes.Create($01, $02));
      mReader.Skip(3);
    end, EIndexCacheFormat);
end;

procedure TTextIndexCacheTests.ReadIntSignInLowestBit;
var
  mReader: TIndexCacheReader;
begin
  mReader := ReaderOf(TBytes.Create($04, $05));
  Assert.AreEqual<Int64>(2, mReader.ReadInt);
  Assert.AreEqual<Int64>(-3, mReader.ReadInt);
end;

procedure TTextIndexCacheTests.ReadStringFromTable;
var
  mReader: TIndexCacheReader;
  mList: TArray<string>;
begin
  mReader := ReaderOf(TBytes.Create($01, $02, $01, $00, $00));
  Assert.AreEqual('b', mReader.ReadString(TArray<string>.Create('a', 'b')));
  mList := mReader.ReadList(TArray<string>.Create('a', 'b'));
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('b', mList[0]);
  Assert.AreEqual('a', mList[1]);
  mReader.Position := 0;
  mReader.SkipList;
  Assert.AreEqual(2, mReader.Position);
  mList := nil;
end;

procedure TTextIndexCacheTests.MagicAndChecksum;
var
  mData: TBytes;
  mReader: TIndexCacheReader;
  mSum: Cardinal;
  mIndex: Integer;
begin
  // FNV-1a von "a".
  Assert.AreEqual<Cardinal>($E40C292C, TIndexCacheReader.Checksum(TBytes.Create(Ord('a')), 0, 1));
  mData := TBytes.Create(Ord('A'), Ord('T'), Ord('L'), Ord('A'), Ord('S'), Ord('I'), Ord('D'), Ord('X'), 0, 0, 0, 0,
    Ord('a'));
  Assert.IsTrue(TIndexCacheReader.HasMagic(mData));
  Assert.IsFalse(TIndexCacheReader.HasMagic(TBytes.Create(Ord('A'), Ord('T'))));
  mSum := TIndexCacheReader.Checksum(mData, 12, Length(mData));
  for mIndex := 0 to 3 do
  begin
    mData[8 + mIndex] := Byte(mSum shr (8 * mIndex));
  end;
  mReader := ReaderOf(mData);
  mReader.Position := 8;
  Assert.IsTrue(mReader.ChecksumMatches);
  Assert.AreEqual(12, mReader.Position);
  mData[12] := Ord('b');
  mReader.Position := 8;
  Assert.IsFalse(mReader.ChecksumMatches);
  mData := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextIndexCacheTests);

end.
