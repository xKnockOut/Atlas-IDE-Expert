unit Atlas.Text.Timestamps.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextTimestampTests = class
  public
    [Test]
    procedure ReadsSpaceAndT;
    [Test]
    procedure ReadsFractionAsMilliseconds;
    [Test]
    procedure IgnoresZoneAndSurroundingSpace;
    [Test]
    procedure RejectsWrongShape;
    [Test]
    procedure RejectsSignsAndNonDigits;
    [Test]
    procedure RejectsInvalidParts;
    [Test]
    procedure ParseOrZeroGivesZero;
    [Test]
    procedure ReadsDateOnly;
    [Test]
    procedure ReadsIsoWithZone;
    [Test]
    procedure IsoNeverRaises;
    [Test]
    procedure IsoOrEmptyRoundTrips;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Text.Timestamps;

function Stamp(const AText: string): string;
var
  mStamp: TDateTime;
begin
  Result := '-';
  if TTextTimestamp.TryParse(AText, mStamp) then
  begin
    Result := FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss"."zzz', mStamp);
  end;
end;

{ TTextTimestampTests }

procedure TTextTimestampTests.ReadsSpaceAndT;
begin
  Assert.AreEqual('2026-11-17 10:57:54.000', Stamp('2026-11-17 10:57:54'));
  Assert.AreEqual('2026-11-17 10:57:54.000', Stamp('2026-11-17T10:57:54'));
  Assert.AreEqual('2026-11-17 10:57:54.000', Stamp('2026-11-17t10:57:54'));
  Assert.AreEqual('2026-02-28 23:59:59.000', Stamp('2026-02-28 23:59:59 INFO Start'));
end;

procedure TTextTimestampTests.ReadsFractionAsMilliseconds;
begin
  Assert.AreEqual('2026-10-29 21:24:52.123', Stamp('2026-10-29T21:24:52.123456Z'));
  Assert.AreEqual('2026-10-29 21:24:52.500', Stamp('2026-10-29T21:24:52.5'));
  Assert.AreEqual('2026-10-29 21:24:52.007', Stamp('2026-10-29 21:24:52.007 [Info]'));
  Assert.AreEqual('-', Stamp('2026-10-29 21:24:52.Z'), 'Punkt ohne Ziffer');
end;

procedure TTextTimestampTests.IgnoresZoneAndSurroundingSpace;
begin
  Assert.AreEqual('2026-01-02 03:04:05.000', Stamp('  2026-01-02T03:04:05Z  '));
  Assert.AreEqual('2026-01-02 03:04:05.000', Stamp('2026-01-02T03:04:05+01:00'));
end;

procedure TTextTimestampTests.RejectsWrongShape;
begin
  Assert.AreEqual('-', Stamp(''));
  Assert.AreEqual('-', Stamp('2026-01-02'));
  Assert.AreEqual('-', Stamp('2026-01-02T03:04'));
  Assert.AreEqual('-', Stamp('29.10.2026 21:24:52'));
  Assert.AreEqual('-', Stamp('2026-10-15X09:30:05Z'));
  Assert.AreEqual('-', Stamp('2026/10/15 09:30:05'));
end;

procedure TTextTimestampTests.RejectsSignsAndNonDigits;
begin
  // Ein Vorzeichen darf nicht als Zahl durchgehen: negative Teile lösten mit Bereichsprüfung ERangeError aus.
  Assert.AreEqual('-', Stamp('2026--1-05 10:00:00'));
  Assert.AreEqual('-', Stamp('2026-01--5 10:00:00'));
  Assert.AreEqual('-', Stamp('-026-01-05 10:00:00'));
  Assert.AreEqual('-', Stamp('2026-01-05 -1:00:00'));
  Assert.AreEqual('-', Stamp('2026-01-05 10:+1:00'));
  Assert.AreEqual('-', Stamp('2026-01-05 10:00:-1'));
  Assert.AreEqual('-', Stamp('2026-0a-05 10:00:00'));
  Assert.AreEqual('-', Stamp('2026-01-05 1 :00:00'));
end;

procedure TTextTimestampTests.RejectsInvalidParts;
begin
  Assert.AreEqual('-', Stamp('2026-13-01 10:00:00'));
  Assert.AreEqual('-', Stamp('2026-00-01 10:00:00'));
  Assert.AreEqual('-', Stamp('2026-02-30 10:00:00'));
  Assert.AreEqual('-', Stamp('0000-01-01 10:00:00'));
  Assert.AreEqual('-', Stamp('2026-01-01 24:00:00'));
  Assert.AreEqual('-', Stamp('2026-01-01 10:60:00'));
  Assert.AreEqual('-', Stamp('2026-01-01 10:00:60'));
end;

procedure TTextTimestampTests.ParseOrZeroGivesZero;
begin
  Assert.AreEqual<TDateTime>(0, TTextTimestamp.ParseOrZero('2026--1-05 10:00:00'));
  Assert.AreEqual<TDateTime>(EncodeDateTime(2026, 1, 5, 10, 0, 0, 0),
    TTextTimestamp.ParseOrZero('2026-01-05T10:00:00Z'));
end;

procedure TTextTimestampTests.ReadsDateOnly;
var
  mDate: TDateTime;
begin
  Assert.IsTrue(TTextTimestamp.TryParseDate('2026-11-17', mDate));
  Assert.AreEqual<TDateTime>(EncodeDate(2026, 11, 17), mDate);
  Assert.IsTrue(TTextTimestamp.TryParseDate('2026-11-17T10:00:00', mDate), 'Rest nach dem Datum bleibt unbeachtet');
  Assert.AreEqual<TDateTime>(EncodeDate(2026, 11, 17), mDate);
  Assert.IsFalse(TTextTimestamp.TryParseDate('2026--1-05', mDate));
  Assert.AreEqual<TDateTime>(0, mDate);
  Assert.IsFalse(TTextTimestamp.TryParseDate('2026-02-29', mDate));
  Assert.IsFalse(TTextTimestamp.TryParseDate('2026-1-5', mDate));
end;

procedure TTextTimestampTests.ReadsIsoWithZone;
var
  mStamp: TDateTime;
begin
  Assert.IsTrue(TTextTimestamp.TryParseIso('2026-11-17T10:57:54.123Z', True, mStamp));
  Assert.AreEqual<TDateTime>(EncodeDateTime(2026, 11, 17, 10, 57, 54, 123), mStamp);
  // Zone wird nach UTC umgerechnet.
  Assert.IsTrue(TTextTimestamp.TryParseIso('2026-11-17T11:57:54+01:00', True, mStamp));
  Assert.AreEqual<TDateTime>(EncodeDateTime(2026, 11, 17, 10, 57, 54, 0), mStamp);
  Assert.AreEqual<TDateTime>(EncodeDateTime(2026, 11, 17, 10, 57, 54, 0),
    TTextTimestamp.IsoOrZero('2026-11-17T10:57:54Z', True));
end;

procedure TTextTimestampTests.IsoNeverRaises;
var
  mStamp: TDateTime;
begin
  // Unlesbarer Text, fremde Form und ungültige Teile: False bzw. 0, keine Ausnahme gleich welcher Klasse.
  Assert.IsFalse(TTextTimestamp.TryParseIso('gestern', True, mStamp));
  Assert.AreEqual<TDateTime>(0, mStamp);
  Assert.IsFalse(TTextTimestamp.TryParseIso('', False, mStamp));
  Assert.IsFalse(TTextTimestamp.TryParseIso('17.11.2026 10:00', True, mStamp));
  Assert.IsFalse(TTextTimestamp.TryParseIso('2026-13-01T00:00:00Z', True, mStamp));
  Assert.AreEqual<TDateTime>(0, mStamp);
  Assert.AreEqual<TDateTime>(0, TTextTimestamp.IsoOrZero('gestern', False));
  Assert.AreEqual<TDateTime>(0, TTextTimestamp.IsoOrZero('2026-02-30T10:00:00', False));
end;

procedure TTextTimestampTests.IsoOrEmptyRoundTrips;
var
  mStamp: TDateTime;
begin
  // 0 heißt „kein Zeitpunkt“ und wird zum leeren Text, der wieder 0 ergibt.
  Assert.AreEqual('', TTextTimestamp.IsoOrEmpty(0));
  Assert.AreEqual<TDateTime>(0, TTextTimestamp.IsoOrZero(TTextTimestamp.IsoOrEmpty(0), False));
  mStamp := EncodeDateTime(2026, 11, 19, 1, 2, 3, 456);
  Assert.IsTrue(TTextTimestamp.IsoOrEmpty(mStamp).StartsWith('2026-11-19T01:02:03.456'),
    TTextTimestamp.IsoOrEmpty(mStamp));
  Assert.AreEqual<TDateTime>(mStamp, TTextTimestamp.IsoOrZero(TTextTimestamp.IsoOrEmpty(mStamp), False));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextTimestampTests);

end.
