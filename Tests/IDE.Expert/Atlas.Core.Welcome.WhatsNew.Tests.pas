unit Atlas.Core.Welcome.WhatsNew.Tests;

// Tests der Karte „Neu in Atlas“ ohne VCL (#756): Lesen von whatsnew.json,
// Versionsvergleich nach SemVer, Zusammenfassen übersprungener Versionen und
// was die Karte je Einstellung welcomePage.whatsNew zeigt.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Core.Welcome.WhatsNew;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWhatsNewTests = class
  public
    [Test]
    procedure ParsesAllFields;
    /// <summary>#1458: titleEn und textEn mit englischer Oberfläche, sonst Deutsch.</summary>
    [Test]
    procedure EnglishFieldsWithFallback;
    [Test]
    procedure SortsNewestFirstAndDropsEmpty;
    [Test]
    procedure InvalidJsonGivesNothing;
    [Test]
    procedure ComparesVersions;
    [Test]
    procedure JumpCollectsSkippedVersions;
    [Test]
    procedure LatestAndUpToIgnoreFutureVersions;
    [Test]
    procedure AfterUpdateShowsOnceAfterSwitch;
    [Test]
    procedure AlwaysKeepsCurrentVersion;
    [Test]
    procedure OffHidesEverything;
    [Test]
    procedure FirstInstallHasNothingUnread;
    [Test]
    procedure ModeNamesRoundTrip;
    [Test]
    procedure AnnouncedItemsJoinTheirVersion;
    [Test]
    procedure ExperimentalItemsComeLast;
  end;

implementation

const
  cSample =
    '{"versions": [' +
    '{"version": "1.1.0", "items": [' +
    '  {"title": "Suchfeld", "text": "Sucht Projekte und Dateien.", "setting": "WelcomePageSearch",' +
    '   "key": "WelcomePageSearchKey", "command": "Atlas.WelcomeStart"},' +
    '  {"title": "Beispiel", "sample": "Beispiele\\Neu.pas", "line": 12}]},' +
    '{"version": "1.2.0", "items": [{"title": "Karte"}]},' +
    '{"version": "1.0.0", "items": [{"title": "Erste"}]}]}';

function Versions: TAtlasWhatsNewVersions;
begin
  Result := TAtlasWhatsNew.Parse(cSample);
end;

function Names(const AVersions: TAtlasWhatsNewVersions): string;
var
  mVersion: TAtlasWhatsNewVersion;
begin
  Result := '';
  for mVersion in AVersions do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mVersion.Version;
  end;
end;

function Titles(const AItems: TArray<TAtlasWhatsNewItem>): string;
var
  mItem: TAtlasWhatsNewItem;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mItem.Title;
  end;
end;

{ TAtlasWhatsNewTests }

procedure TAtlasWhatsNewTests.ExperimentalItemsComeLast;
var
  mParsed: TAtlasWhatsNewVersions;
  mItems: TArray<TAtlasWhatsNewItem>;
begin
  // #834: experimental als Wahrheitswert oder Text; ohne Feld nicht experimentell.
  mParsed := TAtlasWhatsNew.Parse('{"versions": [{"version": "1.1.0", "items": [' +
    '{"title": "Mehrfachcursor", "experimental": true}, {"title": "Suche"},' +
    '{"title": "Live-Umbenennen", "experimental": "true"}, {"title": "Karte", "experimental": false}]}]}');
  Assert.AreEqual(4, Integer(Length(mParsed[0].Items)));
  Assert.IsTrue(mParsed[0].Items[0].Experimental);
  Assert.IsFalse(mParsed[0].Items[1].Experimental);
  Assert.IsTrue(mParsed[0].Items[2].Experimental);
  Assert.IsFalse(mParsed[0].Items[3].Experimental);
  mItems := TAtlasWhatsNew.Ordered(mParsed[0].Items);
  Assert.AreEqual('Suche,Karte,Mehrfachcursor,Live-Umbenennen', Titles(mItems));
  Assert.AreEqual('', Titles(TAtlasWhatsNew.Ordered(nil)));
end;

procedure TAtlasWhatsNewTests.ParsesAllFields;
var
  mParsed: TAtlasWhatsNewVersions;
  mItem: TAtlasWhatsNewItem;
begin
  mParsed := Versions;
  Assert.AreEqual('1.1.0', mParsed[1].Version);
  Assert.AreEqual(2, Integer(Length(mParsed[1].Items)));
  mItem := mParsed[1].Items[0];
  Assert.AreEqual('Suchfeld', mItem.Title);
  Assert.AreEqual('Sucht Projekte und Dateien.', mItem.Text);
  Assert.AreEqual('WelcomePageSearch', mItem.Setting);
  Assert.AreEqual('WelcomePageSearchKey', mItem.Key);
  Assert.AreEqual('Atlas.WelcomeStart', mItem.Command);
  Assert.AreEqual('', mItem.Sample);
  Assert.AreEqual(0, mItem.Line);
  mItem := mParsed[1].Items[1];
  Assert.AreEqual('Beispiele\Neu.pas', mItem.Sample);
  Assert.AreEqual(12, mItem.Line);
  Assert.AreEqual('', mItem.Setting);
end;

procedure TAtlasWhatsNewTests.EnglishFieldsWithFallback;
var
  mParsed: TAtlasWhatsNewVersions;
  mItem: TAtlasWhatsNewItem;
begin
  mParsed := TAtlasWhatsNew.Parse('{"versions": [{"version": "1.2.0", "items": [' +
    '{"title": "Suchfeld", "titleEn": "Search box", "text": "Sucht Dateien.", "textEn": "Finds files."},' +
    '{"title": "Nur deutsch", "text": "Text"}]}]}');
  mItem := mParsed[0].Items[0];
  Assert.AreEqual('Search box', mItem.TitleFor(True));
  Assert.AreEqual('Finds files.', mItem.TextFor(True));
  Assert.AreEqual('Suchfeld', mItem.TitleFor(False));
  Assert.AreEqual('Sucht Dateien.', mItem.TextFor(False));
  mItem := mParsed[0].Items[1];
  Assert.AreEqual('Nur deutsch', mItem.TitleFor(True));
  Assert.AreEqual('Text', mItem.TextFor(True));
end;

procedure TAtlasWhatsNewTests.SortsNewestFirstAndDropsEmpty;
var
  mParsed: TAtlasWhatsNewVersions;
begin
  Assert.AreEqual('1.2.0,1.1.0,1.0.0', Names(Versions));
  // Version ohne Einträge, Eintrag ohne Titel, Version ohne Namen und fremde Werte fallen weg.
  mParsed := TAtlasWhatsNew.Parse('{"versions": [{"version": "2.0.0", "items": []},' +
    '{"version": "1.9.0", "items": [{"text": "ohne Titel"}, 5, {"title": " Mit "}]},' +
    '{"items": [{"title": "ohne Version"}]}, "Text", {"version": "1.8.0"}]}');
  Assert.AreEqual('1.9.0', Names(mParsed));
  Assert.AreEqual(1, Integer(Length(mParsed[0].Items)));
  Assert.AreEqual('Mit', mParsed[0].Items[0].Title);
  // Zeile als Text und negative Zeile.
  mParsed := TAtlasWhatsNew.Parse('{"versions": [{"version": "1.0.0", "items": [{"title": "A", "line": "7"},' +
    '{"title": "B", "line": -3}]}]}');
  Assert.AreEqual(7, mParsed[0].Items[0].Line);
  Assert.AreEqual(0, mParsed[0].Items[1].Line);
end;

procedure TAtlasWhatsNewTests.InvalidJsonGivesNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWhatsNew.Parse(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasWhatsNew.Parse('kein JSON {'))));
  Assert.AreEqual(0, Integer(Length(TAtlasWhatsNew.Parse('[1, 2]'))));
  Assert.AreEqual(0, Integer(Length(TAtlasWhatsNew.Parse('{"versions": 3}'))));
end;

procedure TAtlasWhatsNewTests.ComparesVersions;
begin
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.10.0', '1.9.0') > 0, 'numerisch, nicht als Text');
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0', '1.1.1') < 0);
  Assert.AreEqual(0, TAtlasWhatsNew.CompareVersions('1.1', '1.1.0'));
  Assert.AreEqual(0, TAtlasWhatsNew.CompareVersions('v1.1.0', '1.1.0'));
  Assert.AreEqual(0, TAtlasWhatsNew.CompareVersions('1.1.0+42', '1.1.0'));
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0-beta.2', '1.1.0') < 0, 'Vorabversion vor der Version');
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0-beta.2', '1.0.9') > 0);
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0-beta.10', '1.1.0-beta.2') > 0);
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0-alpha', '1.1.0-beta') < 0);
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0-1', '1.1.0-alpha') < 0, 'Zahl vor Text');
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('1.1.0-beta', '1.1.0-beta.1') < 0, 'kürzer zuerst');
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('', '0.0.1') < 0);
  Assert.IsTrue(TAtlasWhatsNew.CompareVersions('0.0.1', '') > 0);
end;

procedure TAtlasWhatsNewTests.JumpCollectsSkippedVersions;
begin
  // Sprung von 1.0.0 auf 1.2.0: beide Versionen dazwischen, nach Version gruppiert, neueste zuerst.
  Assert.AreEqual('1.2.0,1.1.0', Names(TAtlasWhatsNew.Between(Versions, '1.0.0', '1.2.0')));
  Assert.AreEqual('1.1.0', Names(TAtlasWhatsNew.Between(Versions, '1.0.0', '1.1.0')));
  Assert.AreEqual('', Names(TAtlasWhatsNew.Between(Versions, '1.2.0', '1.2.0')));
  // Zurück auf eine ältere Version: nichts Neues.
  Assert.AreEqual('', Names(TAtlasWhatsNew.Between(Versions, '1.2.0', '1.1.0')));
  // Versionen ohne Einträge zählen nicht; die Karte zeigt dann die nächste darunter.
  Assert.AreEqual('1.2.0', Names(TAtlasWhatsNew.Between(Versions, '1.1.0', '1.3.0')));
end;

procedure TAtlasWhatsNewTests.LatestAndUpToIgnoreFutureVersions;
begin
  Assert.AreEqual('1.1.0', Names(TAtlasWhatsNew.Latest(Versions, '1.1.0')));
  Assert.AreEqual('1.1.0', Names(TAtlasWhatsNew.Latest(Versions, '1.1.5')));
  Assert.AreEqual('', Names(TAtlasWhatsNew.Latest(Versions, '0.9.0')));
  Assert.AreEqual('1.1.0,1.0.0', Names(TAtlasWhatsNew.UpTo(Versions, '1.1.0')));
  Assert.AreEqual('1.2.0,1.1.0,1.0.0', Names(TAtlasWhatsNew.VersionsFor(TAtlasWhatsNewView.All, Versions, '1.0.0',
    '1.2.0')));
  Assert.AreEqual('1.2.0', Names(TAtlasWhatsNew.VersionsFor(TAtlasWhatsNewView.Current, Versions, '1.0.0',
    '1.2.0')));
  Assert.AreEqual('1.2.0,1.1.0', Names(TAtlasWhatsNew.VersionsFor(TAtlasWhatsNewView.Unread, Versions, '1.0.0',
    '1.2.0')));
  Assert.AreEqual('', Names(TAtlasWhatsNew.VersionsFor(TAtlasWhatsNewView.Hidden, Versions, '1.0.0', '1.2.0')));
end;

procedure TAtlasWhatsNewTests.AfterUpdateShowsOnceAfterSwitch;
begin
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.AfterUpdate, Versions, '1.0.0', '1.1.0') =
    TAtlasWhatsNewView.Unread);
  // Nach „Gelesen“ ist 1.1.0 gesehen: nach dem nächsten Start keine Karte.
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.AfterUpdate, Versions, '1.1.0', '1.1.0') =
    TAtlasWhatsNewView.Hidden);
  // Versionswechsel ohne Einträge: keine Karte.
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.AfterUpdate, Versions, '1.2.0', '1.2.1') =
    TAtlasWhatsNewView.Hidden);
end;

procedure TAtlasWhatsNewTests.AlwaysKeepsCurrentVersion;
begin
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.Always, Versions, '1.0.0', '1.2.0') =
    TAtlasWhatsNewView.Unread);
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.Always, Versions, '1.2.0', '1.2.0') =
    TAtlasWhatsNewView.Current);
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.Always, nil, '1.2.0', '1.2.0') =
    TAtlasWhatsNewView.Hidden, 'ohne whatsnew.json keine Karte');
end;

procedure TAtlasWhatsNewTests.OffHidesEverything;
begin
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.Off, Versions, '1.0.0', '1.2.0') =
    TAtlasWhatsNewView.Hidden);
end;

procedure TAtlasWhatsNewTests.FirstInstallHasNothingUnread;
begin
  Assert.IsTrue(TAtlasWhatsNew.ViewFor(TAtlasWhatsNewMode.AfterUpdate, Versions, '', '1.2.0') =
    TAtlasWhatsNewView.Hidden);
  Assert.AreEqual('1.2.0', TAtlasWhatsNew.SeenAfterStart('', '1.2.0'));
  Assert.AreEqual('1.0.0', TAtlasWhatsNew.SeenAfterStart('1.0.0', '1.2.0'), 'bis „Gelesen“ unverändert');
end;

procedure TAtlasWhatsNewTests.ModeNamesRoundTrip;
var
  mMode: TAtlasWhatsNewMode;
begin
  for mMode := Low(TAtlasWhatsNewMode) to High(TAtlasWhatsNewMode) do
  begin
    Assert.IsTrue(TAtlasWhatsNew.ModeOf(TAtlasWhatsNew.ModeName(mMode)) = mMode);
  end;
  Assert.IsTrue(TAtlasWhatsNew.ModeOf('ALWAYS') = TAtlasWhatsNewMode.Always);
  Assert.IsTrue(TAtlasWhatsNew.ModeOf('irgendwas') = TAtlasWhatsNewMode.AfterUpdate);
end;

function Item(const ATitle: string): TAtlasWhatsNewItem;
begin
  Result := Default(TAtlasWhatsNewItem);
  Result.Title := ATitle;
  Result.Text := ATitle + ' – Text';
end;

procedure TAtlasWhatsNewTests.AnnouncedItemsJoinTheirVersion;
var
  mKnown, mJoined: TAtlasWhatsNewVersions;
begin
  // Neue Bereiche nach einem Update (#767) kommen zur laufenden Version, ohne doppelte Titel.
  SetLength(mKnown, 2);
  mKnown[0].Version := '1.3.0';
  mKnown[0].Items := [Item('A')];
  mKnown[1].Version := '1.1.0';
  mKnown[1].Items := [Item('B')];
  mJoined := TAtlasWhatsNew.WithItems(mKnown, '1.3.0', [Item('Neu'), Item('a'), Item('')]);
  Assert.AreEqual(2, Integer(Length(mJoined)));
  Assert.AreEqual(2, Integer(Length(mJoined[0].Items)), 'gleicher Titel und leerer Titel fallen weg');
  Assert.AreEqual('Neu', mJoined[0].Items[1].Title);
  Assert.AreEqual(1, Integer(Length(mKnown[0].Items)), 'Eingabe unverändert');
  // Unbekannte Version: neu angelegt, neueste zuerst.
  mJoined := TAtlasWhatsNew.WithItems(mKnown, '1.2.0', [Item('Neu')]);
  Assert.AreEqual(3, Integer(Length(mJoined)));
  Assert.AreEqual('1.2.0', mJoined[1].Version);
  mJoined := TAtlasWhatsNew.WithItems(mKnown, '2.0.0', [Item('Neu')]);
  Assert.AreEqual('2.0.0', mJoined[0].Version);
  // Nichts Neues: keine leere Version.
  mJoined := TAtlasWhatsNew.WithItems(mKnown, '1.2.0', [Item('')]);
  Assert.AreEqual(2, Integer(Length(mJoined)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWhatsNewTests);

end.
