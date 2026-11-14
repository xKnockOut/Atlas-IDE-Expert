unit Atlas.UI.Settings.Transfer.Tests;

// Tests für Export, Import und Zurücksetzen auf der Optionsseite (#723): die vier Einstellungen, die
// Knopfleiste, Punkte an geänderten Werten, Zurücksetzen je Schlüssel und Seite, die Anbindung der Knöpfe und
// die Vorschau des Imports.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsTransferUiTests = class
  public
    /// <summary>Erste Benutzung (VCL, Menüs, Warteschlange) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TransferSettingsRoundTrip;
    /// <summary>Mit settings.exportImport aus fehlen die Knöpfe auf der Seite.</summary>
    [Test]
    procedure TransferBarFollowsExportImport;
    /// <summary>Geänderte Werte tragen einen Punkt; mit settings.markModified aus keinen.</summary>
    [Test]
    procedure MarksModifiedValues;
    [Test]
    procedure ResetNamesSetsDefault;
    /// <summary>„Seite zurücksetzen“ betrifft nur den sichtbaren Reiter.</summary>
    [Test]
    procedure ResetPageOnlyActiveSheet;
    /// <summary>Kontextmenü am Feld: „Auf Standard zurücksetzen“.</summary>
    [Test]
    procedure ContextMenuResetsKey;
    /// <summary>Import und „Alles zurücksetzen“ laden das Ergebnis in die Seite.</summary>
    [Test]
    procedure ButtonsCallBackAndReload;
    /// <summary>Vorschau: Liste mit Kästchen, Unbekanntes nicht wählbar, Abwahl kommt im Ergebnis an.</summary>
    [Test]
    procedure ImportDialogShowsPreview;
    [Test]
    procedure ExportDialogOptions;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Transfer,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Transfer,
  Atlas.UI.Settings.Page.Transfer;

function SheetOf(AControl: TControl): TTabSheet;
begin
  Result := nil;
  while (AControl <> nil) and (Result = nil) do
  begin
    if AControl is TTabSheet then
    begin
      Result := TTabSheet(AControl);
    end;
    AControl := AControl.Parent;
  end;
end;

procedure TAtlasSettingsTransferUiTests.WarmUpFirstUse;
begin
  try
    TransferSettingsRoundTrip;
  except
    on Exception do
      ;
  end;
  try
    ResetPageOnlyActiveSheet;
  except
    on Exception do
      ;
  end;
  try
    ImportDialogShowsPreview;
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasSettingsTransferUiTests.TransferSettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(mPage.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked);
    Assert.IsTrue(mPage.Part<TAtlasSettingsTransferPart>.SettingsMarkModifiedCheck.Checked);
    Assert.IsTrue(CheckOf(mPage, 'SettingsBackupBeforeImport').Checked);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice, 'Standard: weglassen');
    mPage.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked := False;
    mPage.Part<TAtlasSettingsTransferPart>.SettingsMarkModifiedCheck.Checked := False;
    CheckOf(mPage, 'SettingsBackupBeforeImport').Checked := False;
    mPage.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.SettingsExportImport);
    Assert.IsFalse(mSaved.SettingsMarkModified);
    Assert.IsFalse(mSaved.SettingsBackupBeforeImport);
    Assert.AreEqual('placeholder', mSaved.SettingsExportSecrets);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(mPage.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked);
    Assert.IsFalse(CheckOf(mPage, 'SettingsBackupBeforeImport').Checked);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.TransferBarFollowsExportImport;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(mPage.Part<TAtlasSettingsTransferPart>.TransferBar.Visible, 'Standard: Knöpfe da');
    Assert.IsNotNull(mPage.Part<TAtlasSettingsTransferPart>.ExportButton.Parent);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.SettingsExportImport := False;
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.Part<TAtlasSettingsTransferPart>.TransferBar.Visible, 'Schalter aus: keine Knöpfe');
    // Umschalten auf der Seite wirkt sofort.
    mPage.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked := True;
    Assert.IsTrue(mPage.Part<TAtlasSettingsTransferPart>.TransferBar.Visible);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.MarksModifiedValues;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(mPage.Marks.IsMarked(CheckOf(mPage, 'HoverProblemActions')), 'Standard ohne Punkt');
    Assert.IsFalse(mPage.Marks.IsMarked(mPage.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice));
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.HoverProblemActions := False;
    mSettings.SettingsExportSecrets := 'placeholder';
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(mPage.Marks.IsMarked(CheckOf(mPage, 'HoverProblemActions')), 'geändert: Punkt');
    Assert.IsTrue(string(CheckOf(mPage, 'HoverProblemActions').Caption).StartsWith(TAtlasSettingsMarks.cDot));
    Assert.IsTrue(mPage.Marks.IsMarked(mPage.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice), 'Punkt an der Beschriftung');
    Assert.IsFalse(mPage.Marks.IsMarked(CheckOf(mPage, 'SettingsBackupBeforeImport')));
    // Ändern auf der Seite setzt den Punkt sofort.
    CheckOf(mPage, 'SettingsBackupBeforeImport').Checked := False;
    Assert.IsTrue(mPage.Marks.IsMarked(CheckOf(mPage, 'SettingsBackupBeforeImport')));
    CheckOf(mPage, 'SettingsBackupBeforeImport').Checked := True;
    Assert.IsFalse(mPage.Marks.IsMarked(CheckOf(mPage, 'SettingsBackupBeforeImport')), 'zurück auf Standard: kein Punkt');
    // settings.markModified aus: keine Punkte, gespeichert wird der Text ohne Punkt.
    mPage.Part<TAtlasSettingsTransferPart>.SettingsMarkModifiedCheck.Checked := False;
    Assert.IsFalse(mPage.Marks.IsMarked(CheckOf(mPage, 'HoverProblemActions')));
    Assert.IsFalse(string(CheckOf(mPage, 'HoverProblemActions').Caption).StartsWith(TAtlasSettingsMarks.cDot));
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ResetNamesSetsDefault;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.HoverProblemActions := False;
    mSettings.SettingsBackupBeforeImport := False;
    mPage.LoadFrom(mSettings);
    mPage.ResetNames(['HoverProblemActions']);
    Assert.IsTrue(CheckOf(mPage, 'HoverProblemActions').Checked, 'Befund-Hover zurück auf Standard');
    Assert.IsFalse(CheckOf(mPage, 'SettingsBackupBeforeImport').Checked, 'anderer Wert bleibt');
    Assert.IsFalse(mPage.Marks.IsMarked(CheckOf(mPage, 'HoverProblemActions')));
    // Erst OK speichert: SaveTo liefert den zurückgesetzten Wert.
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.HoverProblemActions);
    Assert.IsFalse(mSaved.SettingsBackupBeforeImport);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ResetPageOnlyActiveSheet;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mGeneral: TTabSheet;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.HoverProblemActions := False;
    mSettings.SettingsBackupBeforeImport := False;
    mSettings.SettingsExportSecrets := 'placeholder';
    mPage.LoadFrom(mSettings);
    mGeneral := SheetOf(CheckOf(mPage, 'SettingsBackupBeforeImport'));
    Assert.IsNotNull(mGeneral);
    Assert.AreNotSame(mGeneral, SheetOf(CheckOf(mPage, 'HoverProblemActions')), 'Befund-Hover auf einem anderen Reiter');
    mPage.Pages.ActivePage := mGeneral;
    mPage.ResetPage;
    Assert.IsTrue(CheckOf(mPage, 'SettingsBackupBeforeImport').Checked, 'Reiter zurückgesetzt');
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice);
    Assert.IsFalse(CheckOf(mPage, 'HoverProblemActions').Checked, 'anderer Reiter bleibt');
    Assert.IsTrue(mPage.Marks.IsMarked(CheckOf(mPage, 'HoverProblemActions')));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ContextMenuResetsKey;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mItem: Integer;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.HoverProblemActions := False;
    mPage.LoadFrom(mSettings);
    Assert.AreSame(mPage.Marks.Menu, CheckOf(mPage, 'HoverProblemActions').PopupMenu, 'Kontextmenü am Feld');
    Assert.AreEqual(1, Integer(Length(mPage.Marks.NamesOf(CheckOf(mPage, 'HoverProblemActions')))));
    // Wie beim Rechtsklick (ohne das Menü modal zu zeigen).
    mPage.Marks.Menu.PopupComponent := CheckOf(mPage, 'HoverProblemActions');
    mPage.Marks.Menu.OnPopup(mPage.Marks.Menu);
    Assert.IsTrue(mPage.Marks.Menu.Items[0].Enabled);
    // Erster Eintrag: „Auf Standard zurücksetzen“.
    mItem := 0;
    mPage.Marks.Menu.Items[mItem].Click;
    Assert.IsTrue(CheckOf(mPage, 'HoverProblemActions').Checked, 'zurückgesetzt');
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ButtonsCallBackAndReload;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mExported, mAsked: Integer;
  mProfile: Boolean;
begin
  mExported := 0;
  mAsked := 0;
  mProfile := False;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.HoverProblemActions := False;
    mPage.LoadFrom(mSettings);
    mPage.Part<TAtlasSettingsTransferPart>.OnExportSettings :=
      procedure(ACurrent: TAtlasPluginSettings)
      begin
        Inc(mExported);
        Assert.IsFalse(ACurrent.HoverProblemActions, 'Werte der Seite');
      end;
    mPage.Part<TAtlasSettingsTransferPart>.OnImportSettings :=
      function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean; out AResult: TAtlasPluginSettings): Boolean
      begin
        Inc(mAsked);
        mProfile := AProfile;
        AResult := ACurrent;
        AResult.HoverProblemActions := True;
        AResult.SettingsBackupBeforeImport := False;
        Result := True;
      end;
    mPage.Part<TAtlasSettingsTransferPart>.OnResetAllSettings :=
      function(const ACurrent: TAtlasPluginSettings; out AResult: TAtlasPluginSettings): Boolean
      begin
        AResult := TAtlasPluginSettings.Defaults;
        Result := True;
      end;
    mPage.Part<TAtlasSettingsTransferPart>.ExportButton.Click;
    Assert.AreEqual(1, mExported);
    mPage.Part<TAtlasSettingsTransferPart>.ImportButton.Click;
    Assert.AreEqual(1, mAsked);
    Assert.IsFalse(mProfile, 'Import aus Datei');
    Assert.IsTrue(CheckOf(mPage, 'HoverProblemActions').Checked, 'Seite zeigt den Import');
    Assert.IsFalse(CheckOf(mPage, 'SettingsBackupBeforeImport').Checked);
    Assert.IsTrue(mPage.Marks.IsMarked(CheckOf(mPage, 'SettingsBackupBeforeImport')));
    mPage.Part<TAtlasSettingsTransferPart>.ResetAllButton.Click;
    Assert.IsTrue(CheckOf(mPage, 'SettingsBackupBeforeImport').Checked, 'alles zurückgesetzt');
    Assert.IsFalse(mPage.Marks.IsMarked(CheckOf(mPage, 'SettingsBackupBeforeImport')));
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ImportDialogShowsPreview;
var
  mCatalog: TAtlasSettingsCatalog;
  mSource: TAtlasSettingsFile;
  mPreview, mChosen: TAtlasImportPreview;
  mDialog: TAtlasImportDialog;
  mIndex, mUnknown, mNotes: Integer;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    mSource := TAtlasSettingsTransfer.ParseFile('{"format":"atlas-settings","formatVersion":1,"schemaVersion":1,' +
      '"settings":{"notes.enabled":false,"settings.backupBeforeImport":false,"gibt.esNicht":1}}');
    Assert.IsTrue(mSource.Valid, mSource.Error);
    mPreview := TAtlasSettingsTransfer.Preview(mCatalog,
      TAtlasSettingsState.Create(TAtlasPluginSettings.Defaults, ''), mSource, TAtlasImportOptions.Create(imMerge, nil,
        nil));
    mDialog := TAtlasImportDialog.CreateDialog(nil, mCatalog, 'atlas-settings.json', mPreview, nil);
    try
      mDialog.HandleNeeded;
      mDialog.Fill;
      Assert.AreEqual(Integer(Length(mPreview.Items)), mDialog.List.Items.Count);
      mUnknown := -1;
      mNotes := -1;
      for mIndex := 0 to mDialog.List.Items.Count - 1 do
      begin
        if mDialog.List.Items[mIndex].Caption = 'gibt.esNicht' then
        begin
          mUnknown := mIndex;
        end;
        if mDialog.List.Items[mIndex].Caption = 'notes.enabled' then
        begin
          mNotes := mIndex;
        end;
      end;
      Assert.IsTrue(mUnknown >= 0, 'unbekannter Schlüssel gemeldet');
      Assert.IsTrue(mNotes >= 0);
      Assert.IsFalse(mDialog.List.Items[mUnknown].Checked, 'Unbekanntes nicht gewählt');
      Assert.IsTrue(mDialog.List.Items[mNotes].Checked, 'Änderung vorgewählt');
      Assert.IsTrue(mDialog.ApplyButton.Enabled);
      // Abwählen kommt im Ergebnis an.
      mDialog.List.Items[mNotes].Checked := False;
      mChosen := mDialog.Result_;
      for mIndex := 0 to High(mChosen.Items) do
      begin
        if mChosen.Items[mIndex].Key = 'notes.enabled' then
        begin
          Assert.IsFalse(mChosen.Items[mIndex].Selected, 'abgewählt');
        end;
      end;
      Assert.AreEqual(1, mChosen.SelectedCount, 'nur noch settings.backupBeforeImport');
    finally
      mDialog.Free;
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ExportDialogOptions;
var
  mCatalog: TAtlasSettingsCatalog;
  mDialog: TAtlasExportDialog;
  mOptions: TAtlasExportOptions;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    mDialog := TAtlasExportDialog.CreateDialog(nil, mCatalog, smPlaceholder);
    try
      mOptions := mDialog.Options;
      Assert.AreEqual(Integer(Length(mCatalog.Areas)), Integer(Length(mOptions.Areas)), 'alle Bereiche gewählt');
      Assert.AreEqual<TAtlasSecretMode>(smPlaceholder, mOptions.Secrets);
      mDialog.Secrets.ItemIndex := 0;
      Assert.AreEqual<TAtlasSecretMode>(smOmit, mDialog.Options.Secrets);
    finally
      mDialog.Free;
    end;
  finally
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsTransferUiTests);

end.
