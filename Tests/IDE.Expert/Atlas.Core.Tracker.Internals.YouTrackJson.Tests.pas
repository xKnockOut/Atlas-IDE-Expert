unit Atlas.Core.Tracker.Internals.YouTrackJson.Tests;

// Einzelwerte aus Antworten der YouTrack-API (TAtlasYouTrackJson): Schalter
// nur bei passendem Typ, Namen von Werten und Listen, Kürzen auf eine
// Zeile, Schlüssel und Kennungen, Zeiten in Millisekunden seit 1970.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasYouTrackJsonTests = class
  public
    [Test]
    procedure ValuesOnlyWithMatchingType;
    [Test]
    procedure ShortenToOneLine;
    [Test]
    procedure ValueTextFromNameOrList;
    [Test]
    procedure KeysAndIds;
    [Test]
    procedure TimeAsUtc;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Core.Tracker.Internals.YouTrackJson,
  Atlas.Text.Json;

function Parsed(const AJson: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AJson);
end;

procedure TAtlasYouTrackJsonTests.ValuesOnlyWithMatchingType;
var
  mObject: TJSONObject;
begin
  mObject := Parsed('{"summary":"Kasse","number":7,"resolved":true,"text":"true","alt":"Ersatz"}') as TJSONObject;
  try
    Assert.AreEqual('Kasse', TJsonRead.Text(mObject, 'summary'));
    Assert.IsTrue(TJsonRead.Flag(mObject, 'resolved'));
    Assert.IsFalse(TJsonRead.Flag(mObject, 'text'), 'Text "true" ist kein Schalter');
    Assert.IsFalse(TJsonRead.Flag(mObject, 'fehlt'));
    Assert.AreEqual('Kasse', TAtlasYouTrackJson.FirstText(mObject, 'summary', 'alt'));
    Assert.AreEqual('Ersatz', TAtlasYouTrackJson.FirstText(mObject, 'fehlt', 'alt'));
    Assert.IsTrue(TAtlasYouTrackJson.IsOneOf('state', ['Priority', 'State']), 'ohne Groß-/Kleinschreibung');
    Assert.IsFalse(TAtlasYouTrackJson.IsOneOf('Type', ['Priority', 'State']));
  finally
    mObject.Free;
  end;
end;

procedure TAtlasYouTrackJsonTests.ShortenToOneLine;
begin
  Assert.AreEqual('a  b', TAtlasYouTrackJson.Shorten('  a'#13#10'b ', 10), 'je Zeichen ein Leerzeichen');
  Assert.AreEqual('abcd…', TAtlasYouTrackJson.Shorten('abcdefgh', 5));
  Assert.AreEqual('abcde', TAtlasYouTrackJson.Shorten('abcde', 5), 'genau an der Grenze');
end;

procedure TAtlasYouTrackJsonTests.ValueTextFromNameOrList;
var
  mValue: TJSONValue;
begin
  mValue := Parsed('[{"name":"Offen"},{"presentation":"2h"},{"fullName":"Erika M","login":"erika"},' +
    '{"login":"max"},{"id":"1"},"roh"]');
  try
    Assert.AreEqual('Offen, 2h, Erika M, max, roh', TAtlasYouTrackJson.ValueText(mValue),
      'leere Einträge fallen weg');
    Assert.AreEqual('', TAtlasYouTrackJson.ValueText(nil));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasYouTrackJsonTests.KeysAndIds;
begin
  Assert.IsTrue(TAtlasYouTrackJson.ValidKey('ATL-12'));
  Assert.IsFalse(TAtlasYouTrackJson.ValidKey(''));
  Assert.IsFalse(TAtlasYouTrackJson.ValidKey('ATL 12'));
  Assert.IsFalse(TAtlasYouTrackJson.ValidKey('1.2'), 'Punkt nur in Kennungen');
  Assert.IsTrue(TAtlasYouTrackJson.ValidId('1-2.3_a'));
  Assert.IsFalse(TAtlasYouTrackJson.ValidId(''));
  Assert.IsFalse(TAtlasYouTrackJson.ValidId('a/b'));
end;

procedure TAtlasYouTrackJsonTests.TimeAsUtc;
var
  mObject: TJSONObject;
  mTime: TDateTime;
begin
  mObject := Parsed('{"created":1700000000250,"none":0,"text":"1700000000250"}') as TJSONObject;
  try
    mTime := TAtlasYouTrackJson.TimeOf(mObject, 'created');
    Assert.AreEqual('2023-11-14 22:13:20.250', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', mTime));
    Assert.AreEqual(Int64(1700000000250), TAtlasYouTrackJson.MsOf(mTime), 'zurück in Millisekunden');
    Assert.AreEqual(Double(0), Double(TAtlasYouTrackJson.TimeOf(mObject, 'none')));
    Assert.AreEqual(Double(0), Double(TAtlasYouTrackJson.TimeOf(mObject, 'text')), 'Text ist keine Zeit');
  finally
    mObject.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasYouTrackJsonTests);

end.
