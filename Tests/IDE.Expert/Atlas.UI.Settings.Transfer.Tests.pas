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
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Transfer;

function SheetOf(AControl: TControl): TTabSheet;
begin
  Result := nil;
  while (AControl <> nil) and (Result = nil) do
  begin
    if AControl is TTabSheet then
      Result := TTabSheet(AControl);
    AControl := AControl.Parent;
  end;
end;

procedure TAtlasSettingsTransferUiTests.TransferSettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.SettingsExportImportCheck.Checked);
    Assert.IsTrue(Page.SettingsMarkModifiedCheck.Checked);
    Assert.IsTrue(Page.SettingsBackupBeforeImportCheck.Checked);
    Assert.AreEqual(0, Page.SettingsExportSecretsChoice.Choice, 'Standard: weglassen');
    Page.SettingsExportImportCheck.Checked := False;
    Page.SettingsMarkModifiedCheck.Checked := False;
    Page.SettingsBackupBeforeImportCheck.Checked := False;
    Page.SettingsExportSecretsChoice.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.SettingsExportImport);
    Assert.IsFalse(Saved.SettingsMarkModified);
    Assert.IsFalse(Saved.SettingsBackupBeforeImport);
    Assert.AreEqual('placeholder', Saved.SettingsExportSecrets);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.SettingsExportImportCheck.Checked);
    Assert.IsFalse(Page.SettingsBackupBeforeImportCheck.Checked);
    Assert.AreEqual(1, Page.SettingsExportSecretsChoice.Choice);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.TransferBarFollowsExportImport;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.TransferBar.Visible, 'Standard: Knöpfe da');
    Assert.IsTrue(Page.ExportButton.Parent <> nil);
    Settings := TAtlasPluginSettings.Defaults;
    Settings.SettingsExportImport := False;
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.TransferBar.Visible, 'Schalter aus: keine Knöpfe');
    // Umschalten auf der Seite wirkt sofort.
    Page.SettingsExportImportCheck.Checked := True;
    Assert.IsTrue(Page.TransferBar.Visible);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.MarksModifiedValues;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(Page.Marks.IsMarked(Page.NotesCheck), 'Standard ohne Punkt');
    Assert.IsFalse(Page.Marks.IsMarked(Page.SettingsExportSecretsChoice));
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Notes := False;
    Settings.SettingsExportSecrets := 'placeholder';
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.Marks.IsMarked(Page.NotesCheck), 'geändert: Punkt');
    Assert.IsTrue(string(Page.NotesCheck.Caption).StartsWith(TAtlasSettingsMarks.Dot));
    Assert.IsTrue(Page.Marks.IsMarked(Page.SettingsExportSecretsChoice), 'Punkt an der Beschriftung');
    Assert.IsFalse(Page.Marks.IsMarked(Page.SettingsBackupBeforeImportCheck));
    // Ändern auf der Seite setzt den Punkt sofort.
    Page.SettingsBackupBeforeImportCheck.Checked := False;
    Assert.IsTrue(Page.Marks.IsMarked(Page.SettingsBackupBeforeImportCheck));
    Page.SettingsBackupBeforeImportCheck.Checked := True;
    Assert.IsFalse(Page.Marks.IsMarked(Page.SettingsBackupBeforeImportCheck), 'zurück auf Standard: kein Punkt');
    // settings.markModified aus: keine Punkte, gespeichert wird der Text ohne Punkt.
    Page.SettingsMarkModifiedCheck.Checked := False;
    Assert.IsFalse(Page.Marks.IsMarked(Page.NotesCheck));
    Assert.IsFalse(string(Page.NotesCheck.Caption).StartsWith(TAtlasSettingsMarks.Dot));
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ResetNamesSetsDefault;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Notes := False;
    Settings.SettingsBackupBeforeImport := False;
    Page.LoadFrom(Settings);
    Page.ResetNames(['Notes']);
    Assert.IsTrue(Page.NotesCheck.Checked, 'Notizen zurück auf Standard');
    Assert.IsFalse(Page.SettingsBackupBeforeImportCheck.Checked, 'anderer Wert bleibt');
    Assert.IsFalse(Page.Marks.IsMarked(Page.NotesCheck));
    // Erst OK speichert: SaveTo liefert den zurückgesetzten Wert.
    Saved := Settings;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.Notes);
    Assert.IsFalse(Saved.SettingsBackupBeforeImport);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ResetPageOnlyActiveSheet;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  General: TTabSheet;
begin
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Notes := False;
    Settings.SettingsBackupBeforeImport := False;
    Settings.SettingsExportSecrets := 'placeholder';
    Page.LoadFrom(Settings);
    General := SheetOf(Page.SettingsBackupBeforeImportCheck);
    Assert.IsTrue(General <> nil);
    Assert.IsTrue(SheetOf(Page.NotesCheck) <> General, 'Notizen auf einem anderen Reiter');
    Page.Pages.ActivePage := General;
    Page.ResetPage;
    Assert.IsTrue(Page.SettingsBackupBeforeImportCheck.Checked, 'Reiter zurückgesetzt');
    Assert.AreEqual(0, Page.SettingsExportSecretsChoice.Choice);
    Assert.IsFalse(Page.NotesCheck.Checked, 'anderer Reiter bleibt');
    Assert.IsTrue(Page.Marks.IsMarked(Page.NotesCheck));
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ContextMenuResetsKey;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  Item: Integer;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Notes := False;
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.NotesCheck.PopupMenu = Page.Marks.Menu, 'Kontextmenü am Feld');
    Assert.AreEqual(1, Integer(Length(Page.Marks.NamesOf(Page.NotesCheck))));
    // Wie beim Rechtsklick (ohne das Menü modal zu zeigen).
    Page.Marks.Menu.PopupComponent := Page.NotesCheck;
    Page.Marks.Menu.OnPopup(Page.Marks.Menu);
    Assert.IsTrue(Page.Marks.Menu.Items[0].Enabled);
    // Erster Eintrag: „Auf Standard zurücksetzen“.
    Item := 0;
    Page.Marks.Menu.Items[Item].Click;
    Assert.IsTrue(Page.NotesCheck.Checked, 'zurückgesetzt');
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ButtonsCallBackAndReload;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  Exported, Asked: Integer;
  Profile: Boolean;
begin
  Exported := 0;
  Asked := 0;
  Profile := False;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Notes := False;
    Page.LoadFrom(Settings);
    Page.OnExportSettings :=
      procedure(ACurrent: TAtlasPluginSettings)
      begin
        Inc(Exported);
        Assert.IsFalse(ACurrent.Notes, 'Werte der Seite');
      end;
    Page.OnImportSettings :=
      function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean; out AResult: TAtlasPluginSettings): Boolean
      begin
        Inc(Asked);
        Profile := AProfile;
        AResult := ACurrent;
        AResult.Notes := True;
        AResult.SettingsBackupBeforeImport := False;
        Result := True;
      end;
    Page.OnResetAllSettings :=
      function(const ACurrent: TAtlasPluginSettings; out AResult: TAtlasPluginSettings): Boolean
      begin
        AResult := TAtlasPluginSettings.Defaults;
        Result := True;
      end;
    Page.ExportButton.Click;
    Assert.AreEqual(1, Exported);
    Page.ImportButton.Click;
    Assert.AreEqual(1, Asked);
    Assert.IsFalse(Profile, 'Import aus Datei');
    Assert.IsTrue(Page.NotesCheck.Checked, 'Seite zeigt den Import');
    Assert.IsFalse(Page.SettingsBackupBeforeImportCheck.Checked);
    Assert.IsTrue(Page.Marks.IsMarked(Page.SettingsBackupBeforeImportCheck));
    Page.ResetAllButton.Click;
    Assert.IsTrue(Page.SettingsBackupBeforeImportCheck.Checked, 'alles zurückgesetzt');
    Assert.IsFalse(Page.Marks.IsMarked(Page.SettingsBackupBeforeImportCheck));
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ImportDialogShowsPreview;
var
  Catalog: TAtlasSettingsCatalog;
  Source: TAtlasSettingsFile;
  Preview, Chosen: TAtlasImportPreview;
  Dialog: TAtlasImportDialog;
  Index, Unknown, Notes: Integer;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    Source := TAtlasSettingsTransfer.ParseFile('{"format":"atlas-settings","formatVersion":1,"schemaVersion":1,' +
      '"settings":{"notes.enabled":false,"settings.backupBeforeImport":false,"gibt.esNicht":1}}');
    Assert.IsTrue(Source.Valid, Source.Error);
    Preview := TAtlasSettingsTransfer.Preview(Catalog,
      TAtlasSettingsState.Create(TAtlasPluginSettings.Defaults, ''), Source, imMerge, nil,
      nil, '', '');
    Dialog := TAtlasImportDialog.CreateDialog(nil, Catalog, 'atlas-settings.json', Preview, nil);
    try
      Dialog.HandleNeeded;
      Dialog.Fill;
      Assert.AreEqual(Integer(Length(Preview.Items)), Dialog.List.Items.Count);
      Unknown := -1;
      Notes := -1;
      for Index := 0 to Dialog.List.Items.Count - 1 do
      begin
        if Dialog.List.Items[Index].Caption = 'gibt.esNicht' then
          Unknown := Index;
        if Dialog.List.Items[Index].Caption = 'notes.enabled' then
          Notes := Index;
      end;
      Assert.IsTrue(Unknown >= 0, 'unbekannter Schlüssel gemeldet');
      Assert.IsTrue(Notes >= 0);
      Assert.IsFalse(Dialog.List.Items[Unknown].Checked, 'Unbekanntes nicht gewählt');
      Assert.IsTrue(Dialog.List.Items[Notes].Checked, 'Änderung vorgewählt');
      Assert.IsTrue(Dialog.ApplyButton.Enabled);
      // Abwählen kommt im Ergebnis an.
      Dialog.List.Items[Notes].Checked := False;
      Chosen := Dialog.Result_;
      for Index := 0 to High(Chosen.Items) do
        if Chosen.Items[Index].Key = 'notes.enabled' then
          Assert.IsFalse(Chosen.Items[Index].Selected, 'abgewählt');
      Assert.AreEqual(1, Chosen.SelectedCount, 'nur noch settings.backupBeforeImport');
    finally
      Dialog.Free;
    end;
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsTransferUiTests.ExportDialogOptions;
var
  Catalog: TAtlasSettingsCatalog;
  Dialog: TAtlasExportDialog;
  Options: TAtlasExportOptions;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    Dialog := TAtlasExportDialog.CreateDialog(nil, Catalog, smPlaceholder);
    try
      Options := Dialog.Options;
      Assert.AreEqual(Integer(Length(Catalog.Areas)), Integer(Length(Options.Areas)), 'alle Bereiche gewählt');
      Assert.IsTrue(Options.Secrets = smPlaceholder);
      Dialog.Secrets.ItemIndex := 0;
      Assert.IsTrue(Dialog.Options.Secrets = smOmit);
    finally
      Dialog.Free;
    end;
  finally
    Catalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsTransferUiTests);

end.
