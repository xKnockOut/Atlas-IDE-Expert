unit Atlas.UI.Settings.Page.Tests;

// Tests für die Optionsseite (#227): Die IDE erzeugt sie über die Klasse,
// TCustomFrame.Create braucht dafür die DFM-Ressource.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPageTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure CreatesAndRoundTripsSettings;
    [Test]
    procedure SnippetsPageShowsCatalogAndValidates;
    [Test]
    procedure ShowsAndReenablesTrippedFeatures;
    [Test]
    procedure IndexSectionRoundTripsAndRunsCommands;
    [Test]
    procedure StatusFieldRoundTrips;
    [Test]
    procedure SafeModeRoundTrips;
    [Test]
    procedure UndoSettingsRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.SnippetsPage;

procedure TAtlasSettingsPageTests.WarmUp;
begin
  TAtlasSettingsPage.Create(nil).Free;
end;

procedure TAtlasSettingsPageTests.CreatesAndRoundTripsSettings;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 12;
  Settings.Preview := True;
  Settings.HoverTooltip := False;
  Settings.XmlDocFull := False;
  Settings.XmlDocMaxLines := 7;
  Settings.ListWidth := 333;
  Settings.ActionsKey := 0;
  Settings.ExpandKey := $C057;
  Settings.EditorKeysPriority := True;
  Settings.SlashCommands := False;
  Settings.Snippets := False;
  Settings.ImportIdeTemplates := False;
  Settings.ProviderTimeLimitMs := 400;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.Enabled);
  Assert.AreEqual(12, Saved.VisibleRows);
  Assert.IsTrue(Saved.Preview);
  Assert.IsFalse(Saved.HoverTooltip);
  Assert.IsFalse(Saved.XmlDocFull);
  Assert.AreEqual(7, Saved.XmlDocMaxLines);
  Assert.AreEqual(333, Saved.ListWidth);
  Assert.AreEqual(0, Saved.ActionsKey);
  Assert.AreEqual($C057, Saved.ExpandKey);
  Assert.AreEqual($6057, Saved.ShrinkKey);
  Assert.IsTrue(Saved.EditorKeysPriority);
  Assert.IsFalse(Saved.SlashCommands);
  Assert.IsFalse(Saved.Snippets);
  Assert.IsFalse(Saved.ImportIdeTemplates);
  Assert.AreEqual(400, Saved.ProviderTimeLimitMs);
end;

procedure TAtlasSettingsPageTests.ShowsAndReenablesTrippedFeatures;
var
  Page: TAtlasSettingsPage;
  Index: Integer;
begin
  TAtlasGuard.Fuse.ResetAll;
  try
    for Index := 1 to 3 do
    begin
      TAtlasGuard.ReportProvider('Testquelle', 'Fehler');
      TAtlasGuard.Fuse.Failed(TAtlasFeature.Pairs);
    end;
    Page := TAtlasSettingsPage.Create(nil);
    try
      Page.LoadFrom(TAtlasPluginSettings.Defaults);
      Assert.AreEqual(2, Page.FuseList.Items.Count);
      Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Pairs), Page.FuseList.Items[0]);
      Assert.AreEqual('Testquelle', Page.FuseList.Items[1]);
      Assert.IsTrue(Page.FuseEnableAll.Enabled);
      // Nur die Quelle wieder einschalten.
      Page.FuseList.Selected[1] := True;
      Page.FuseEnableSelected.Click;
      Assert.IsFalse(TAtlasGuard.ProviderDisabled('Testquelle'));
      Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Page.FuseEnableAll.Click;
      Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Assert.AreEqual(1, Page.FuseList.Items.Count, 'nur der Hinweis „keine“');
      Assert.IsFalse(Page.FuseEnableAll.Enabled);
    finally
      Page.Free;
    end;
  finally
    TAtlasGuard.Fuse.ResetAll;
  end;
end;

procedure TAtlasSettingsPageTests.IndexSectionRoundTripsAndRunsCommands;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Confirm: Boolean;
  Cleared: Integer;
begin
  // #492: Verwendungen und Speicherbudget, Kennzahlen, Neuaufbau und Löschen mit Rückfrage.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Confirm := False;
  Cleared := 0;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsFalse(Page.IndexRebuild.Enabled or Page.IndexClear.Enabled, 'ohne Server keine Befehle');
    Page.OnIndexMetrics :=
      function: string
      begin
        Result := 'Units: 3';
      end;
    Page.OnIndexRebuild :=
      function: string
      begin
        Result := 'wird neu aufgebaut';
      end;
    Page.OnIndexClear :=
      function: string
      begin
        Inc(Cleared);
        Result := 'gelöscht';
      end;
    Page.ConfirmClear :=
      function: Boolean
      begin
        Result := Confirm;
      end;
    Page.LoadFrom(Settings);
    Assert.AreEqual('Units: 3', Page.IndexInfo.Caption);
    Assert.IsTrue(Page.IndexRebuild.Enabled and Page.IndexClear.Enabled);
    Page.IndexRebuild.Click;
    Assert.AreEqual('wird neu aufgebaut', Page.IndexInfo.Caption);
    Page.IndexClear.Click;
    Assert.AreEqual(0, Cleared, 'abgelehnt: nichts löschen');
    Confirm := True;
    Page.IndexClear.Click;
    Assert.AreEqual(1, Cleared);
    Assert.AreEqual('gelöscht', Page.IndexInfo.Caption);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.IndexUsages);
  Assert.AreEqual(512, Saved.MemoryBudgetMb);
end;

procedure TAtlasSettingsPageTests.StatusFieldRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #591: Feld an/aus, Kurztext, ausgeblendete Zeilen.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.StatusField := False;
  Settings.StatusFieldSummary := False;
  Settings.StatusFieldHidden := 'atlas.file';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.StatusField.Checked);
    Assert.IsFalse(Page.StatusSummary.Checked);
    Assert.AreEqual('atlas.file', Page.StatusHidden.Text);
    Page.StatusField.Checked := True;
    Page.StatusHidden.Text := ' atlas.file, atlas.index ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StatusField);
    Assert.IsFalse(Saved.StatusFieldSummary);
    Assert.AreEqual('atlas.file, atlas.index', Saved.StatusFieldHidden);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SafeModeRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #722: Rückfrage, ohne Rückfrage nach zwei Abstürzen, Taste, Zeitlimit, gemerkte Stände.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.SafeAskAfterCrash := False;
  Settings.SafeStartupKey := 'ctrl';
  Settings.SafeStartupTimeoutMs := 20000;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.SafeAsk.Checked);
    Assert.IsTrue(Page.SafeAuto.Checked);
    Assert.AreEqual(1, Page.SafeKey.ItemIndex);
    Assert.AreEqual('20000', Page.SafeTimeout.Text);
    Assert.AreEqual('5', Page.SafeHistory.Text);
    Page.SafeAuto.Checked := False;
    Page.SafeKey.ItemIndex := 2;
    Page.SafeHistory.Text := '500';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.SafeAskAfterCrash);
    Assert.IsFalse(Saved.SafeAutoAfterRepeatedCrash);
    Assert.AreEqual('none', Saved.SafeStartupKey);
    Assert.AreEqual(20000, Saved.SafeStartupTimeoutMs);
    // Begrenzt auf die Höchstzahl.
    Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Saved.SafeKeepSettingsHistory);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.UndoSettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #721: Ein/Aus, Tiefe, Sicherung, Größe, Konflikte, neue Dateien und die beiden Tasten.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.UndoMultiFileDepth := 7;
  Settings.UndoMultiFileOnConflict := 'abort';
  Settings.UndoMultiFileNewFiles := 'keep';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.UndoEnabled.Checked);
    Assert.AreEqual('7', Page.UndoDepth.Text);
    Assert.IsTrue(Page.UndoPersist.Checked);
    Assert.AreEqual('50', Page.UndoMaxSize.Text);
    Assert.AreEqual(1, Page.UndoOnConflict.ItemIndex);
    Assert.AreEqual(2, Page.UndoNewFiles.ItemIndex);
    Assert.IsTrue(Page.UndoKey.Text <> '');
    Assert.IsTrue(Page.RedoKey.Text <> '');
    Page.UndoEnabled.Checked := False;
    Page.UndoPersist.Checked := False;
    Page.UndoDepth.Text := '999';
    Page.UndoMaxSize.Text := '0';
    Page.UndoOnConflict.ItemIndex := 0;
    Page.UndoNewFiles.ItemIndex := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.UndoMultiFile);
    Assert.IsFalse(Saved.UndoMultiFilePersist);
    // Begrenzt auf den erlaubten Bereich.
    Assert.AreEqual(TAtlasPluginSettings.MaxUndoDepth, Saved.UndoMultiFileDepth);
    Assert.AreEqual(TAtlasPluginSettings.MinUndoMaxSizeMb, Saved.UndoMultiFileMaxSizeMb);
    Assert.AreEqual('partial', Saved.UndoMultiFileOnConflict);
    Assert.AreEqual('delete', Saved.UndoMultiFileNewFiles);
    Assert.AreEqual(Settings.UndoKey, Saved.UndoKey);
    Assert.AreEqual(Settings.RedoKey, Saved.RedoKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SnippetsPageShowsCatalogAndValidates;
var
  Page: TAtlasSnippetsPage;
  Own: TAtlasSnippet;
begin
  Own := Default(TAtlasSnippet);
  Own.Prefix := 'eigen';
  Own.Body := 'X;';
  Own.Origin := TAtlasSnippetOrigin.User;
  Page := TAtlasSnippetsPage.Create(nil);
  try
    Page.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, [Own]));
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 1, Page.Catalog.Count);
    Assert.AreEqual('', Page.Validate);
    // Zweite eigene mit demselben Kürzel: Meldung nennt das Kürzel.
    Page.Catalog.Update(Page.Catalog.AddNew, Own);
    Assert.IsTrue(Pos('eigen', Page.Validate) > 0);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.