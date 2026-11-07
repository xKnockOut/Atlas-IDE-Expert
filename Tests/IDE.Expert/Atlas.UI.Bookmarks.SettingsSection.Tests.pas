unit Atlas.UI.Bookmarks.SettingsSection.Tests;

// Abschnitte des Moduls Lesezeichen (#1456) auf den Seiten „Editor“ und „Befehle“: Notizen (#545), benannte
// (#622) und schnelle Lesezeichen (#1104); Laden und Speichern über die Seite (vorher in den Tests der Seite von
// Base).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TBookmarksSettingsSectionTests = class
  private
    FRegistrations: TArray<IAtlasRegistration>;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Notizen und benannte Lesezeichen: zwei Schalter auf dem Reiter Editor, Taste bei den Befehlen.
    /// </summary>
    [Test]
    procedure BookmarksRoundTrip;
    /// <summary>Schalter, Taste, Wartezeit (begrenzt), Sprungbereich als Auswahl, Tasten für nächstes/voriges.
    /// </summary>
    [Test]
    procedure QuickBookmarksRoundTrip;
  end;

implementation

uses
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Bookmarks.SettingsSection;

procedure TBookmarksSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TBookmarksSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasBookmarksEditorSection, TAtlasBookmarksKeysSection]);
end;

procedure TBookmarksSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TBookmarksSettingsSectionTests.BookmarksRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'BookmarksEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'Notes').Checked, 'Notizen standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'BookmarksNamed').Checked, 'Lesezeichen standardmäßig an');
    Assert.IsFalse(CheckOf(mPage, 'BookmarksShared').Checked, 'standardmäßig lokal');
    Assert.AreEqual(ShortCutToText($C04B), EditOf(mPage, 'BookmarkKey').Text, 'Strg+Alt+K');
    CheckOf(mPage, 'Notes').Checked := False;
    CheckOf(mPage, 'BookmarksNamed').Checked := False;
    CheckOf(mPage, 'BookmarksShared').Checked := True;
    EditOf(mPage, 'BookmarkKey').Text := '';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.Notes, 'Notizen abschaltbar');
    Assert.IsFalse(mSaved.BookmarksNamed, 'abschaltbar');
    Assert.IsTrue(mSaved.BookmarksShared);
    Assert.AreEqual(0, mSaved.BookmarkKey, 'leer = keine Taste');
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'Notes').Checked);
    Assert.IsFalse(CheckOf(mPage, 'BookmarksNamed').Checked);
    Assert.IsTrue(CheckOf(mPage, 'BookmarksShared').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TBookmarksSettingsSectionTests.QuickBookmarksRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'QuickBookmarks').Checked);
    Assert.IsTrue(CheckOf(mPage, 'QuickBookmarksGutter').Checked);
    Assert.AreEqual('800', EditOf(mPage, 'QuickBookmarkChordWait').Text);
    Assert.AreEqual(0, ChoiceOf(mPage, 'QuickBookmarksScope').Choice);
    Assert.AreEqual('', EditOf(mPage, 'NextBookmarkKey').Text);
    CheckOf(mPage, 'QuickBookmarksGutterClick').Checked := False;
    CheckOf(mPage, 'QuickBookmarksNumberedKeys').Checked := False;
    CheckOf(mPage, 'QuickBookmarksImportIde').Checked := False;
    EditOf(mPage, 'QuickBookmarkChordWait').Text := '99999';
    ChoiceOf(mPage, 'QuickBookmarksScope').Choice := 1;
    EditOf(mPage, 'QuickBookmarkKey').Text := '';
    EditOf(mPage, 'NextBookmarkKey').Text := 'F2';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.QuickBookmarks);
    Assert.IsFalse(mSaved.QuickBookmarksGutterClick);
    Assert.IsFalse(mSaved.QuickBookmarksNumberedKeys);
    Assert.IsFalse(mSaved.QuickBookmarksImportIde);
    Assert.AreEqual(TAtlasPluginSettings.cMaxQuickChordWait, mSaved.QuickBookmarkChordWait, 'begrenzt');
    Assert.AreEqual('file', mSaved.QuickBookmarksScope);
    Assert.AreEqual(0, mSaved.QuickBookmarkKey);
    Assert.AreEqual($71, mSaved.NextBookmarkKey, 'F2');
    Assert.AreEqual(0, mSaved.PreviousBookmarkKey);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(1, ChoiceOf(mPage, 'QuickBookmarksScope').Choice);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBookmarksSettingsSectionTests);

end.
