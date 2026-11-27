unit Atlas.Text.AssistantOrigin.Tests;

// Herkunft eines Auftrags an die IDE (#2616): Auftrag mit und ohne "client"/"session", Bereinigen des Freitexts,
// Anzeige und Vergleich zweier Assistenten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasAssistantOriginTests = class
  public
    [Test]
    procedure RoundTripThroughJson;
    [Test]
    procedure RequestWithoutOriginIsUnknown;
    [Test]
    procedure CleanRemovesControlCharsAndShortens;
    [Test]
    procedure SessionKeepsOnlyLettersAndDigits;
    [Test]
    procedure CaptionNamesClientAndSession;
    [Test]
    procedure SessionDistinguishesSameClient;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.AssistantOrigin;

{ TAtlasAssistantOriginTests }

procedure TAtlasAssistantOriginTests.RoundTripThroughJson;
var
  mObject: TJSONObject;
  mOrigin: TAtlasAssistantOrigin;
begin
  mObject := TJSONObject.Create;
  try
    TAtlasAssistantOrigin.Make('Assistent A', '3f2a').AddTo(mObject);
    Assert.AreEqual('{"client":"Assistent A","session":"3f2a"}', mObject.ToJSON([]));
    mOrigin := TAtlasAssistantOrigin.Read(mObject);
  finally
    mObject.Free;
  end;
  Assert.AreEqual('Assistent A', mOrigin.Client);
  Assert.AreEqual('3f2a', mOrigin.Session);
end;

procedure TAtlasAssistantOriginTests.RequestWithoutOriginIsUnknown;
var
  mObject: TJSONObject;
  mOrigin: TAtlasAssistantOrigin;
begin
  mObject := TJSONObject.ParseJSONValue('{"file":"A.pas"}') as TJSONObject;
  try
    mOrigin := TAtlasAssistantOrigin.Read(mObject);
    Assert.IsFalse(mOrigin.IsKnown);
    // Ohne Herkunft schreibt AddTo nichts.
    mOrigin.AddTo(mObject);
    Assert.AreEqual('{"file":"A.pas"}', mObject.ToJSON([]));
  finally
    mObject.Free;
  end;
  Assert.IsFalse(TAtlasAssistantOrigin.Read(nil).IsKnown);
  Assert.AreEqual('unknown assistant', mOrigin.Caption('unknown assistant'));
  Assert.AreEqual('', mOrigin.Display('unknown assistant'));
end;

procedure TAtlasAssistantOriginTests.CleanRemovesControlCharsAndShortens;
begin
  Assert.AreEqual('Assistent A', TAtlasAssistantOrigin.Clean('  Assistent'#13#10#9' A'#0, 40));
  Assert.AreEqual('Name', TAtlasAssistantOrigin.Clean(#$1B'Name' + Char($85), 40));
  Assert.AreEqual('abcd…', TAtlasAssistantOrigin.Clean('abcdefgh', 5));
  Assert.AreEqual(TAtlasAssistantOrigin.cMaxClient, Length(TAtlasAssistantOrigin.Make(StringOfChar('x', 100),
    '').Client));
end;

procedure TAtlasAssistantOriginTests.SessionKeepsOnlyLettersAndDigits;
begin
  Assert.AreEqual('3f2a', TAtlasAssistantOrigin.CleanSession(' 3f'#10'2a '));
  Assert.AreEqual('abcdefgh', TAtlasAssistantOrigin.CleanSession('abcdefghij'));
  Assert.AreEqual('a-1', TAtlasAssistantOrigin.CleanSession('a-1<>'));
end;

procedure TAtlasAssistantOriginTests.CaptionNamesClientAndSession;
begin
  Assert.AreEqual('Assistent A · 3f2a', TAtlasAssistantOrigin.Make('Assistent A', '3f2a').Caption('?'));
  Assert.AreEqual('Assistent A', TAtlasAssistantOrigin.Make('Assistent A', '').Caption('?'));
  Assert.AreEqual('? · 3f2a', TAtlasAssistantOrigin.Make('', '3f2a').Caption('?'));
  Assert.AreEqual('? · 3f2a', TAtlasAssistantOrigin.Make('', '3f2a').Display('?'));
end;

procedure TAtlasAssistantOriginTests.SessionDistinguishesSameClient;
var
  mFirst, mSecond, mOther: TAtlasAssistantOrigin;
begin
  mFirst := TAtlasAssistantOrigin.Make('Assistent A', '3f2a');
  mSecond := TAtlasAssistantOrigin.Make('Assistent A', 'a91b');
  mOther := TAtlasAssistantOrigin.Make('Assistent B', 'a91b');
  Assert.IsFalse(mFirst.SameAs(mSecond));
  Assert.IsTrue(mSecond.SameAs(mOther));
  Assert.IsTrue(mFirst.SameAs(TAtlasAssistantOrigin.Make('Assistent A', '3F2A')));
  // Ohne Sitzung (älterer Server) zählt der Name.
  Assert.IsTrue(TAtlasAssistantOrigin.Make('A', '').SameAs(TAtlasAssistantOrigin.Make('A', '')));
  Assert.IsFalse(TAtlasAssistantOrigin.Make('A', '').SameAs(TAtlasAssistantOrigin.Make('B', '')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantOriginTests);

end.
