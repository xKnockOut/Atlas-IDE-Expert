unit Atlas.UI.Settings.Page.Sections.Tests;

// Abschnitte der Module im Optionsdialog (#1455, ADR 0017 Entscheidung 3): Die
// Optionsseite holt sich je Seite einen Abschnitt vom angemeldeten Anbieter,
// baut ihn in den Reiter seines Bereichs (bzw. einen eigenen), lädt und
// speichert gebundene Felder selbst, gibt eigenen Zeilen die Werte über
// IAtlasSettingsValues und schließt den Abschnitt, wenn das Modul geht oder die
// Seite schließt. Ein fehlerhafter Abschnitt verhindert die Seite nicht; ohne
// Modul bleiben seine Werte erhalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSettingsPageSectionsTests = class
  public
    [Test]
    procedure SectionLandsOnSheetOfItsArea;
    [Test]
    procedure UnknownAreaGetsOwnSheet;
    [Test]
    procedure BoundFieldsLoadAndSave;
    [Test]
    procedure OwnRowsGetValues;
    [Test]
    procedure RevokedSectionIsClosed;
    [Test]
    procedure PageCloseClosesSection;
    [Test]
    procedure BrokenSectionDoesNotStopPage;
    [Test]
    procedure BrokenProviderDoesNotStopPage;
    [Test]
    procedure EveryPageGetsOwnSection;
    [Test]
    procedure WindowReadyAndShowReachSection;
    [Test]
    procedure MissingModuleKeepsValues;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.Sections;

type
  TTestSection = class(TInterfacedObject, IAtlasSettingsSection)
  public
    Area: string;
    Broken: Boolean;
    Builds, Loads, Saves, Closes: Integer;
    Switch: TControl;
    Row: TWinControl;
    Edit: TEdit;
    LoadedTracker: string;
    WindowReadies: Integer;
    ShownKey, ShownArgument: string;
    function OwnerId: string;
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    procedure WindowReady;
    function Show(const AKey, AArgument: string): Boolean;
    procedure Close;
  end;

  /// <summary>Anbieter für die Tests: liefert die vorbereiteten Abschnitte der Reihe nach, danach neue.</summary>
  TTestProvider = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    Sections: TArray<IAtlasSettingsSection>;
    Created: Integer;
    Broken: Boolean;
    function CreateSection: IAtlasSettingsSection;
  end;

function TTestSection.OwnerId: string;
begin
  Result := 'test.section';
end;

function TTestSection.AreaId: string;
begin
  Result := Area;
end;

procedure TTestSection.Build(const AHost: IAtlasSettingsSectionHost);
begin
  Inc(Builds);
  AHost.AddTitle('Testabschnitt');
  Switch := AHost.AddSwitch('issues.board.onlyMine', 'Nur meine');
  if Broken then
  begin
    raise EAtlasSettingsKey.Create('kaputt');
  end;
  Row := AHost.AddRow(26, ['issues.tracker']);
  // Eigenes Element des Moduls in der Zeile der Seite; das Modul gibt es in Close frei.
  Edit := TEdit.Create(nil);
  Edit.Parent := Row;
end;

procedure TTestSection.Load(const AValues: IAtlasSettingsValues);
begin
  Inc(Loads);
  LoadedTracker := AValues.ReadString('issues.tracker');
  Edit.Text := LoadedTracker;
end;

procedure TTestSection.Save(const AValues: IAtlasSettingsValues);
begin
  Inc(Saves);
  AValues.WriteString('issues.tracker', Edit.Text);
end;

procedure TTestSection.WindowReady;
begin
  Inc(WindowReadies);
end;

function TTestSection.Show(const AKey, AArgument: string): Boolean;
begin
  Result := AKey = 'issues.tracker';
  if Result then
  begin
    ShownKey := AKey;
    ShownArgument := AArgument;
  end;
end;

function TTestProvider.CreateSection: IAtlasSettingsSection;
var
  mSection: TTestSection;
begin
  if Broken then
  begin
    raise EAtlasSettingsKey.Create('Anbieter kaputt');
  end;
  if Created < Length(Sections) then
  begin
    Result := Sections[Created];
  end
  else
  begin
    mSection := TTestSection.Create;
    mSection.Area := 'issues';
    Result := mSection;
  end;
  Inc(Created);
end;

procedure TTestSection.Close;
begin
  Inc(Closes);
  FreeAndNil(Edit);
end;

function SheetOf(AControl: TControl): TTabSheet;
var
  mParent: TWinControl;
begin
  Result := nil;
  if AControl = nil then
  begin
    Exit;
  end;
  mParent := AControl.Parent;
  while (mParent <> nil) and not (mParent is TTabSheet) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent <> nil then
  begin
    Result := TTabSheet(mParent);
  end;
end;

function Provided(ASection: TTestSection): IAtlasRegistration;
var
  mProvider: TTestProvider;
begin
  mProvider := TTestProvider.Create;
  mProvider.Sections := TArray<IAtlasSettingsSection>.Create(ASection);
  Result := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider, mProvider as IAtlasSettingsSectionProvider);
end;

procedure TSettingsPageSectionsTests.SectionLandsOnSheetOfItsArea;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'issues';
  mRegistration := Provided(mSection);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      Assert.AreEqual(1, mPage.Part<TAtlasSettingsSectionsPart>.Count);
      Assert.AreEqual(1, mSection.Builds);
      // Bereich issues: derselbe Reiter wie die übrigen Einstellungen des Issue-Trackers.
      Assert.AreSame(SheetOf(mPage.ControlOfSetting('IssuesEnabled')), SheetOf(mSection.Row));
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

procedure TSettingsPageSectionsTests.UnknownAreaGetsOwnSheet;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
  mBefore: Integer;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mBefore := mPage.SheetCountForTests;
  finally
    mPage.Free;
  end;
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'test.unbekannt';
  mRegistration := Provided(mSection);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      Assert.AreEqual(mBefore + 1, mPage.SheetCountForTests);
      Assert.IsNotNull(SheetOf(mSection.Row));
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

procedure TSettingsPageSectionsTests.BoundFieldsLoadAndSave;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'test.unbekannt';
  mRegistration := Provided(mSection);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      mSettings := TAtlasPluginSettings.Defaults;
      mSettings.IssuesBoardOnlyMine := False;
      mPage.LoadFrom(mSettings);
      Assert.IsFalse((mSection.Switch as TCheckBox).Checked);
      (mSection.Switch as TCheckBox).Checked := True;
      mSettings := mPage.CurrentSettings;
      Assert.IsTrue(mSettings.IssuesBoardOnlyMine);
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

procedure TSettingsPageSectionsTests.OwnRowsGetValues;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'test.unbekannt';
  mRegistration := Provided(mSection);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      mSettings := TAtlasPluginSettings.Defaults;
      mSettings.IssuesTracker := 'youtrack';
      mPage.LoadFrom(mSettings);
      Assert.AreEqual('youtrack', mSection.LoadedTracker);
      mSection.Edit.Text := 'github';
      mPage.SaveTo(mSettings);
      Assert.AreEqual('github', mSettings.IssuesTracker);
      Assert.IsTrue(mSection.Saves > 0);
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

procedure TSettingsPageSectionsTests.RevokedSectionIsClosed;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mLoads: Integer;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'test.unbekannt';
  mRegistration := Provided(mSection);
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mRegistration.Revoke;
    Assert.AreEqual(1, mSection.Closes);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsSectionsPart>.Count);
    // Danach erreicht nichts mehr den Abschnitt (Regel 3); seine Werte bleiben.
    mLoads := mSection.Loads;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesTracker := 'youtrack';
    mPage.LoadFrom(mSettings);
    mPage.SaveTo(mSettings);
    Assert.AreEqual(mLoads, mSection.Loads);
    Assert.AreEqual('youtrack', mSettings.IssuesTracker);
  finally
    mPage.Free;
  end;
  Assert.AreEqual(1, mSection.Closes);
end;

procedure TSettingsPageSectionsTests.PageCloseClosesSection;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'issues';
  mRegistration := Provided(mSection);
  try
    TAtlasSettingsPage.Create(nil).Free;
    Assert.AreEqual(1, mSection.Closes);
    Assert.IsNull(mSection.Edit);
  finally
    mRegistration.Revoke;
  end;
  // Nach dem Schließen der Seite meldet das Abmelden nichts mehr an den Abschnitt.
  Assert.AreEqual(1, mSection.Closes);
end;

procedure TSettingsPageSectionsTests.BrokenSectionDoesNotStopPage;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'issues';
  mSection.Broken := True;
  mRegistration := Provided(mSection);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      Assert.AreEqual(0, mPage.Part<TAtlasSettingsSectionsPart>.Count);
      Assert.AreEqual(1, mSection.Closes);
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

procedure TSettingsPageSectionsTests.BrokenProviderDoesNotStopPage;
var
  mProvider: TTestProvider;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
begin
  mProvider := TTestProvider.Create;
  mProvider.Broken := True;
  mRegistration := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    mProvider as IAtlasSettingsSectionProvider);
  try
    mPage := TAtlasSettingsPage.Create(nil);
    try
      Assert.AreEqual(0, mPage.Part<TAtlasSettingsSectionsPart>.Count);
      Assert.IsNotNull(mPage.ControlOfSetting('IssuesEnabled'));
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

procedure TSettingsPageSectionsTests.EveryPageGetsOwnSection;
var
  mProvider: TTestProvider;
  mProviderRef: IAtlasSettingsSectionProvider;
  mFirst, mSecond: TTestSection;
  mRefs: TArray<IAtlasSettingsSection>;
  mRegistration: IAtlasRegistration;
  mPage1, mPage2: TAtlasSettingsPage;
begin
  mFirst := TTestSection.Create;
  mFirst.Area := 'issues';
  mSecond := TTestSection.Create;
  mSecond.Area := 'issues';
  mRefs := TArray<IAtlasSettingsSection>.Create(mFirst, mSecond);
  mProvider := TTestProvider.Create;
  mProviderRef := mProvider;
  mProvider.Sections := mRefs;
  mRegistration := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider, mProviderRef);
  try
    mPage1 := TAtlasSettingsPage.Create(nil);
    try
      mPage2 := TAtlasSettingsPage.Create(nil);
      try
        // Zwei offene Seiten teilen nie Steuerelemente: jede hat ihren Abschnitt.
        Assert.AreEqual(2, mProvider.Created);
        Assert.AreEqual(1, mFirst.Builds);
        Assert.AreEqual(1, mSecond.Builds);
        Assert.IsTrue(mFirst.Row <> mSecond.Row);
      finally
        mPage2.Free;
      end;
      Assert.AreEqual(1, mSecond.Closes);
      Assert.AreEqual(0, mFirst.Closes);
    finally
      mPage1.Free;
    end;
    Assert.AreEqual(1, mFirst.Closes);
  finally
    mRegistration.Revoke;
  end;
  mRefs := nil;
end;

procedure TSettingsPageSectionsTests.WindowReadyAndShowReachSection;
var
  mSection: TTestSection;
  mRef: IAtlasSettingsSection;
  mRegistration: IAtlasRegistration;
  mPage: TAtlasSettingsPage;
  mHost: TForm;
begin
  mSection := TTestSection.Create;
  mRef := mSection;
  mSection.Area := 'issues';
  mRegistration := Provided(mSection);
  try
    mHost := TForm.CreateNew(nil);
    try
      mPage := TAtlasSettingsPage.Create(mHost);
      Assert.AreEqual(0, mSection.WindowReadies, 'ohne Fenster noch nicht');
      mPage.Parent := mHost;
      mPage.HandleNeeded;
      Assert.AreEqual(1, mSection.WindowReadies);
      // Registry-Name der Einstellung, der Abschnitt bekommt den Schlüssel.
      Assert.IsTrue(mPage.Part<TAtlasSettingsSectionsPart>.ShowSettingArgument('IssuesTracker', 'youtrack'));
      Assert.AreEqual('issues.tracker', mSection.ShownKey);
      Assert.AreEqual('youtrack', mSection.ShownArgument);
      Assert.IsFalse(mPage.Part<TAtlasSettingsSectionsPart>.ShowSettingArgument('IssuesBoardOnlyMine', 'x'));
      Assert.IsFalse(mPage.Part<TAtlasSettingsSectionsPart>.ShowSettingArgument('GibtEsNicht', 'x'));
    finally
      mHost.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
  mSection.ShownKey := '';
  mSection.ShownArgument := '';
end;

procedure TSettingsPageSectionsTests.MissingModuleKeepsValues;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  // Ohne Abschnitt des Trackers zeigt der Reiter nur den Schalter; Werte des Moduls bleiben, wie sie sind.
  mPage := TAtlasSettingsPage.Create(nil);
  try
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsSectionsPart>.Count);
    Assert.IsNull(mPage.ControlOf('issues.tracker'));
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesTracker := 'youtrack';
    mSettings.IssuesBoardOnlyMine := not mSettings.IssuesBoardOnlyMine;
    mSettings.IssuesConnections := '[{"name":"Firma"}]';
    mPage.LoadFrom(mSettings);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesTracker := 'youtrack';
    mSettings.IssuesBoardOnlyMine := not mSettings.IssuesBoardOnlyMine;
    mSettings.IssuesConnections := '[{"name":"Firma"}]';
    mPage.SaveTo(mSettings);
    Assert.AreEqual('youtrack', mSettings.IssuesTracker);
    Assert.AreEqual(not TAtlasPluginSettings.Defaults.IssuesBoardOnlyMine, mSettings.IssuesBoardOnlyMine);
    Assert.AreEqual('[{"name":"Firma"}]', mSettings.IssuesConnections);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSettingsPageSectionsTests);

end.
