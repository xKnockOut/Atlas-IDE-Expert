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
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked);
    Assert.IsTrue(Page.Part<TAtlasSettingsTransferPart>.SettingsMarkModifiedCheck.Checked);
    Assert.IsTrue(CheckOf(Page, 'SettingsBackupBeforeImport').Checked);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice, 'Standard: weglassen');
    Page.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked := False;
    Page.Part<TAtlasSettingsTransferPart>.SettingsMarkModifiedCheck.Checked := False;
    CheckOf(Page, 'SettingsBackupBeforeImport').Checked := False;
    Page.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.SettingsExportImport);
    Assert.IsFalse(Saved.SettingsMarkModified);
    Assert.IsFalse(Saved.SettingsBackupBeforeImport);
    Assert.AreEqual('placeholder', Saved.SettingsExportSecrets);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked);
    Assert.IsFalse(CheckOf(Page, 'SettingsBackupBeforeImport').Checked);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice);
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
    Assert.IsTrue(Page.Part<TAtlasSettingsTransferPart>.TransferBar.Visible, 'Standard: Knöpfe da');
    Assert.IsTrue(Page.Part<TAtlasSettingsTransferPart>.ExportButton.Parent <> nil);
    Settings := TAtlasPluginSettings.Defaults;
    Settings.SettingsExportImport := False;
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.Part<TAtlasSettingsTransferPart>.TransferBar.Visible, 'Schalter aus: keine Knöpfe');
    // Umschalten auf der Seite wirkt sofort.
    Page.Part<TAtlasSettingsTransferPart>.SettingsExportImportCheck.Checked := True;
    Assert.IsTrue(Page.Part<TAtlasSettingsTransferPart>.TransferBar.Visible);
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
    Assert.IsFalse(Page.Marks.IsMarked(CheckOf(Page, 'HoverProblemActions')), 'Standard ohne Punkt');
    Assert.IsFalse(Page.Marks.IsMarked(Page.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice));
    Settings := TAtlasPluginSettings.Defaults;
    Settings.HoverProblemActions := False;
    Settings.SettingsExportSecrets := 'placeholder';
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.Marks.IsMarked(CheckOf(Page, 'HoverProblemActions')), 'geändert: Punkt');
    Assert.IsTrue(string(CheckOf(Page, 'HoverProblemActions').Caption).StartsWith(TAtlasSettingsMarks.cDot));
    Assert.IsTrue(Page.Marks.IsMarked(Page.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice), 'Punkt an der Beschriftung');
    Assert.IsFalse(Page.Marks.IsMarked(CheckOf(Page, 'SettingsBackupBeforeImport')));
    // Ändern auf der Seite setzt den Punkt sofort.
    CheckOf(Page, 'SettingsBackupBeforeImport').Checked := False;
    Assert.IsTrue(Page.Marks.IsMarked(CheckOf(Page, 'SettingsBackupBeforeImport')));
    CheckOf(Page, 'SettingsBackupBeforeImport').Checked := True;
    Assert.IsFalse(Page.Marks.IsMarked(CheckOf(Page, 'SettingsBackupBeforeImport')), 'zurück auf Standard: kein Punkt');
    // settings.markModified aus: keine Punkte, gespeichert wird der Text ohne Punkt.
    Page.Part<TAtlasSettingsTransferPart>.SettingsMarkModifiedCheck.Checked := False;
    Assert.IsFalse(Page.Marks.IsMarked(CheckOf(Page, 'HoverProblemActions')));
    Assert.IsFalse(string(CheckOf(Page, 'HoverProblemActions').Caption).StartsWith(TAtlasSettingsMarks.cDot));
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
    Settings.HoverProblemActions := False;
    Settings.SettingsBackupBeforeImport := False;
    Page.LoadFrom(Settings);
    Page.ResetNames(['HoverProblemActions']);
    Assert.IsTrue(CheckOf(Page, 'HoverProblemActions').Checked, 'Befund-Hover zurück auf Standard');
    Assert.IsFalse(CheckOf(Page, 'SettingsBackupBeforeImport').Checked, 'anderer Wert bleibt');
    Assert.IsFalse(Page.Marks.IsMarked(CheckOf(Page, 'HoverProblemActions')));
    // Erst OK speichert: SaveTo liefert den zurückgesetzten Wert.
    Saved := Settings;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.HoverProblemActions);
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
    Settings.HoverProblemActions := False;
    Settings.SettingsBackupBeforeImport := False;
    Settings.SettingsExportSecrets := 'placeholder';
    Page.LoadFrom(Settings);
    General := SheetOf(CheckOf(Page, 'SettingsBackupBeforeImport'));
    Assert.IsTrue(General <> nil);
    Assert.IsTrue(SheetOf(CheckOf(Page, 'HoverProblemActions')) <> General, 'Befund-Hover auf einem anderen Reiter');
    Page.Pages.ActivePage := General;
    Page.ResetPage;
    Assert.IsTrue(CheckOf(Page, 'SettingsBackupBeforeImport').Checked, 'Reiter zurückgesetzt');
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTransferPart>.SettingsExportSecretsChoice.Choice);
    Assert.IsFalse(CheckOf(Page, 'HoverProblemActions').Checked, 'anderer Reiter bleibt');
    Assert.IsTrue(Page.Marks.IsMarked(CheckOf(Page, 'HoverProblemActions')));
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
    Settings.HoverProblemActions := False;
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'HoverProblemActions').PopupMenu = Page.Marks.Menu, 'Kontextmenü am Feld');
    Assert.AreEqual(1, Integer(Length(Page.Marks.NamesOf(CheckOf(Page, 'HoverProblemActions')))));
    // Wie beim Rechtsklick (ohne das Menü modal zu zeigen).
    Page.Marks.Menu.PopupComponent := CheckOf(Page, 'HoverProblemActions');
    Page.Marks.Menu.OnPopup(Page.Marks.Menu);
    Assert.IsTrue(Page.Marks.Menu.Items[0].Enabled);
    // Erster Eintrag: „Auf Standard zurücksetzen“.
    Item := 0;
    Page.Marks.Menu.Items[Item].Click;
    Assert.IsTrue(CheckOf(Page, 'HoverProblemActions').Checked, 'zurückgesetzt');
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
    Settings.HoverProblemActions := False;
    Page.LoadFrom(Settings);
    Page.Part<TAtlasSettingsTransferPart>.OnExportSettings :=
      procedure(ACurrent: TAtlasPluginSettings)
      begin
        Inc(Exported);
        Assert.IsFalse(ACurrent.HoverProblemActions, 'Werte der Seite');
      end;
    Page.Part<TAtlasSettingsTransferPart>.OnImportSettings :=
      function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean; out AResult: TAtlasPluginSettings): Boolean
      begin
        Inc(Asked);
        Profile := AProfile;
        AResult := ACurrent;
        AResult.HoverProblemActions := True;
        AResult.SettingsBackupBeforeImport := False;
        Result := True;
      end;
    Page.Part<TAtlasSettingsTransferPart>.OnResetAllSettings :=
      function(const ACurrent: TAtlasPluginSettings; out AResult: TAtlasPluginSettings): Boolean
      begin
        AResult := TAtlasPluginSettings.Defaults;
        Result := True;
      end;
    Page.Part<TAtlasSettingsTransferPart>.ExportButton.Click;
    Assert.AreEqual(1, Exported);
    Page.Part<TAtlasSettingsTransferPart>.ImportButton.Click;
    Assert.AreEqual(1, Asked);
    Assert.IsFalse(Profile, 'Import aus Datei');
    Assert.IsTrue(CheckOf(Page, 'HoverProblemActions').Checked, 'Seite zeigt den Import');
    Assert.IsFalse(CheckOf(Page, 'SettingsBackupBeforeImport').Checked);
    Assert.IsTrue(Page.Marks.IsMarked(CheckOf(Page, 'SettingsBackupBeforeImport')));
    Page.Part<TAtlasSettingsTransferPart>.ResetAllButton.Click;
    Assert.IsTrue(CheckOf(Page, 'SettingsBackupBeforeImport').Checked, 'alles zurückgesetzt');
    Assert.IsFalse(Page.Marks.IsMarked(CheckOf(Page, 'SettingsBackupBeforeImport')));
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
      TAtlasSettingsState.Create(TAtlasPluginSettings.Defaults, ''), Source, TAtlasImportOptions.Create(imMerge, nil,
        nil));
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
        begin
          Unknown := Index;
        end;
        if Dialog.List.Items[Index].Caption = 'notes.enabled' then
        begin
          Notes := Index;
        end;
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
      begin
        if Chosen.Items[Index].Key = 'notes.enabled' then
        begin
          Assert.IsFalse(Chosen.Items[Index].Selected, 'abgewählt');
        end;
      end;
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
