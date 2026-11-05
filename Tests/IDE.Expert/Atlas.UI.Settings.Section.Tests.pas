unit Atlas.UI.Settings.Section.Tests;

// Grundklasse der Abschnitte der Module (#1456): Fabrik je Seite, einmal bauen, nach Close nichts mehr, Schalter
// des Moduls mit der Beschriftung aus dem Katalog.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsSectionTests = class
  public
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Die Fabrik liefert je Aufruf einen neuen Abschnitt der Klasse.</summary>
    [Test]
    procedure FactoryCreatesNewSection;
    /// <summary>Ein Abschnitt baut seine Zeilen einmal; nach Close baut er nicht mehr.</summary>
    [Test]
    procedure BuildsOnceAndNotAfterClose;
    /// <summary>Der Schalter des Moduls heißt wie im Katalog, ein Schalter mit eigener Beschriftung wie übergeben.
    /// </summary>
    [Test]
    procedure ModuleSwitchUsesCatalogCaption;
  end;

implementation

uses
  Vcl.StdCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport;

type
  TTestSection = class(TAtlasSettingsSection)
  private
    FBuilds: Integer;
    FModule: TCheckBox;
    FNotes: TCheckBox;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Close; override;
    property Builds: Integer read FBuilds;
    property ModuleCheck: TCheckBox read FModule;
    property NotesCheck: TCheckBox read FNotes;
  end;

const
  cNotesCaption = 'Notizen im Test';

function TTestSection.OwnerId: string;
begin
  Result := 'atlas.test';
end;

function TTestSection.AreaId: string;
begin
  Result := 'Editor';
end;

procedure TTestSection.BuildRows;
begin
  Inc(FBuilds);
  FModule := ModuleSwitch('bookmarks.enabled');
  FNotes := Switch('notes.enabled', cNotesCaption);
end;

procedure TTestSection.Close;
begin
  FModule := nil;
  FNotes := nil;
  inherited Close;
end;

procedure TAtlasSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TAtlasSettingsSectionTests.FactoryCreatesNewSection;
var
  mProvider: IAtlasSettingsSectionProvider;
  mFirst, mSecond: IAtlasSettingsSection;
begin
  mProvider := TAtlasSettingsSectionFactory.Create(TTestSection);
  mFirst := mProvider.CreateSection;
  mSecond := mProvider.CreateSection;
  Assert.IsTrue(mFirst <> mSecond, 'je Seite ein neuer Abschnitt');
  Assert.AreEqual('Editor', mFirst.AreaId);
end;

procedure TAtlasSettingsSectionTests.BuildsOnceAndNotAfterClose;
var
  mSection: TTestSection;
  mSectionRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
begin
  mSection := TTestSection.Create;
  mSectionRef := mSection;
  mRegistration := ProvideSection(mSectionRef);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      Assert.AreEqual(1, mSection.Builds);
      Assert.IsFalse(mSection.Closed);
      mSectionRef.Build(nil);
      Assert.AreEqual(1, mSection.Builds, 'nur einmal');
    finally
      mPage.Free;
    end;
    Assert.IsTrue(mSection.Closed, 'die Seite schließt den Abschnitt');
    Assert.IsNull(mSection.NotesCheck);
    // Eine weitere Seite bekommt denselben, geschlossenen Abschnitt: Er baut nicht mehr.
    mPage := TAtlasSettingsPage.Create(nil);
    mPage.Free;
    Assert.AreEqual(1, mSection.Builds, 'nach Close nichts mehr');
  finally
    mRegistration.Revoke;
  end;
end;

procedure TAtlasSettingsSectionTests.ModuleSwitchUsesCatalogCaption;
var
  mSection: TTestSection;
  mSectionRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
  mIndex: Integer;
  mExpected: string;
begin
  mSection := TTestSection.Create;
  mSectionRef := mSection;
  mRegistration := ProvideSection(mSectionRef);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      mPage.LoadFrom(TAtlasPluginSettings.Defaults);
      mIndex := mPage.Catalog.IndexOfName('BookmarksEnabled');
      Assert.IsTrue(mIndex >= 0);
      Assert.IsTrue(mSection.ModuleCheck = CheckOf(mPage, 'BookmarksEnabled'), 'an den Schlüssel gebunden');
      mExpected := mPage.Catalog[mIndex].Caption;
      if TAtlasStrings.Language = TAtlasLanguage.English then
      begin
        mExpected := mPage.Catalog[mIndex].CaptionEn;
      end;
      Assert.AreEqual(mExpected, string(mSection.ModuleCheck.Caption));
      Assert.AreEqual(cNotesCaption, string(mSection.NotesCheck.Caption));
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsSectionTests);

end.
