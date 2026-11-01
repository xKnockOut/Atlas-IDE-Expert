unit Atlas.UI.Settings.Page.Sections.Tests;

// Abschnitte der Module im Optionsdialog (#1455, ADR 0017 Entscheidung 3): Die
// Optionsseite baut angemeldete Abschnitte in den Reiter ihres Bereichs (bzw.
// einen eigenen), lädt und speichert gebundene Felder selbst, gibt eigenen
// Zeilen die Werte über IAtlasSettingsValues und schließt den Abschnitt, wenn
// das Modul geht oder die Seite schließt. Ein fehlerhafter Abschnitt verhindert
// die Seite nicht.

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
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Page;

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
    function OwnerId: string;
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    procedure Close;
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
    raise EAtlasSettingsKey.Create('kaputt');
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
    Exit;
  mParent := AControl.Parent;
  while (mParent <> nil) and not (mParent is TTabSheet) do
    mParent := mParent.Parent;
  if mParent <> nil then
    Result := TTabSheet(mParent);
end;

function Provided(ASection: TTestSection): IAtlasRegistration;
begin
  Result := AtlasModuleRegistry.Provide(IAtlasSettingsSection, ASection as IAtlasSettingsSection);
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
      Assert.AreEqual(1, mPage.SectionCount);
      Assert.AreEqual(1, mSection.Builds);
      // Bereich issues: derselbe Reiter wie die übrigen Einstellungen des Issue-Trackers.
      Assert.AreSame(SheetOf(mPage.ControlOf('IssuesTracker')), SheetOf(mSection.Row));
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
    Assert.AreEqual(0, mPage.SectionCount);
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
      Assert.AreEqual(0, mPage.SectionCount);
      Assert.AreEqual(1, mSection.Closes);
    finally
      mPage.Free;
    end;
  finally
    mRegistration.Revoke;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSettingsPageSectionsTests);

end.
