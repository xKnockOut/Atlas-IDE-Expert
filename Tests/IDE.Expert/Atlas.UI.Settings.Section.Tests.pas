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
    /// <summary>Beitrag zu einem anderen Modul (#1903): nur mit Gastgeber gebaut, steht in dessen Knoten.</summary>
    [Test]
    procedure ContributionNeedsHostAndShowsThere;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.NodeScope,
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

  /// <summary>Vertrag des Gastgebers im Test.</summary>
  ITestHost = interface
    ['{5D1E7A30-2B44-4C8E-9F61-3A7B0C2E9D15}']
  end;

  TTestHost = class(TInterfacedObject, ITestHost)
  end;

  TTestContribution = class(TTestSection, IAtlasSettingsContribution)
  public
    function HostContract: TGUID;
  end;

const
  cNotesCaption = 'Notizen im Test';

/// <summary>Sichtbar samt aller Eltern bis zum Reiter (nicht gewählte Reiter sind selbst unsichtbar).</summary>
function Shown(AControl: TControl; APage: TControl): Boolean;
begin
  Result := True;
  while (AControl <> nil) and (AControl <> APage) and not (AControl is TTabSheet) do
  begin
    Result := Result and AControl.Visible;
    AControl := AControl.Parent;
  end;
end;

function TTestContribution.HostContract: TGUID;
begin
  Result := ITestHost;
end;

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
      Assert.AreSame(CheckOf(mPage, 'BookmarksEnabled'), mSection.ModuleCheck, 'an den Schlüssel gebunden');
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

procedure TAtlasSettingsSectionTests.ContributionNeedsHostAndShowsThere;
var
  mSection: TTestContribution;
  mSectionRef: IAtlasSettingsSection;
  mRegistration, mHost: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
begin
  mSection := TTestContribution.Create;
  mSectionRef := mSection;
  mRegistration := ProvideSection(mSectionRef);
  try
    // Ohne Gastgeber: nicht gebaut.
    mPage := TAtlasSettingsPage.Create(nil);
    mPage.Free;
    Assert.AreEqual(0, mSection.Builds, 'ohne Gastgeber kein Abschnitt');
  finally
    mRegistration.Revoke;
  end;
  mSection := TTestContribution.Create;
  mSectionRef := mSection;
  mRegistration := ProvideSection(mSectionRef);
  // Gastgeber ist Base (Besitzer ''): Der Abschnitt steht im Knoten Base, nicht in dem seines Besitzers.
  mHost := AtlasModuleRegistry.Provide(ITestHost, TTestHost.Create as ITestHost);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      Assert.AreEqual(1, mSection.Builds, 'mit Gastgeber gebaut');
      mPage.ApplyScope(TAtlasSettingsNodeScope.Module('atlas.test', ''));
      Assert.IsFalse(Shown(mSection.NotesCheck, mPage), 'nicht beim Besitzer');
    finally
      mPage.Free;
    end;
    mSection := TTestContribution.Create;
    mSectionRef := mSection;
    mRegistration.Revoke;
    mRegistration := ProvideSection(mSectionRef);
    mPage := TAtlasSettingsPage.Create(nil);
    try
      mPage.ApplyScope(TAtlasSettingsNodeScope.Base);
      Assert.IsTrue(mPage.ScopeHasContent);
      Assert.IsTrue(Shown(mSection.NotesCheck, mPage), 'beim Gastgeber');
    finally
      mPage.Free;
    end;
  finally
    mHost.Revoke;
    mRegistration.Revoke;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsSectionTests);

end.
