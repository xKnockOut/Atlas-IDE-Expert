unit Atlas.UI.Settings.Page.Editor.Tests;

// Tests der Einstellungsseite: Seiten für Editorbefehle, Leisten und Lesezeichen.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Seiten für Editorbefehle, Leisten und Lesezeichen.</summary>
  [TestFixture]
  TAtlasSettingsPageEditorTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Benannte Lesezeichen (#622): zwei Schalter auf dem Reiter Editor, Taste bei den Befehlen.</summary>
    [Test]
    procedure BookmarksRoundTrip;
    /// <summary>Erzeugen-Menü (#719) auf dem Reiter Befehle.</summary>
    [Test]
    procedure GenerateMenuRoundTrip;
    /// <summary>Blockende-Beschriftung (#620) und Taste „Element ausblenden …“ (#628) laden und speichern.
    /// </summary>
    [Test]
    procedure HideElementRoundTrip;
    [Test]
    procedure MethodToggleRoundTrip;
    [Test]
    procedure MoveLinesRoundTrip;
    [Test]
    procedure ContinueCommentsRoundTrip;
    [Test]
    procedure CompleteStatementRoundTrip;
    [Test]
    procedure FormatCodeRoundTrip;
    [Test]
    procedure ContinuePatternRoundTrip;
    [Test]
    procedure MultiCursorRoundTrip;
    [Test]
    procedure SmartPasteRoundTrip;
    [Test]
    procedure StickyScrollRoundTrip;
    [Test]
    procedure EditorToolbarRoundTrip;
    [Test]
    procedure EditorStatusBarRoundTrip;
    [Test]
    procedure QuickBookmarksRoundTrip;
    /// <summary>#1122: Kontrollkästchen „Aufrufdiagramm“ liest und schreibt callHierarchy.diagram.</summary>
    [Test]
    procedure CallHierarchyDiagramRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Reassigned,
  Atlas.UI.Settings.Page,
  Vcl.Menus,
  Atlas.UI.Settings.Page.TestSupport;

procedure TAtlasSettingsPageEditorTests.WarmUp;
begin
  WarmUpSettingsPage;
end;
/// <summary>Vorgaben und Änderungen: Blockende, Datenfluss, Austrittspunkte, Unterstreichung, Ausdruckstyp.</summary>
procedure EditHideElementMarkers(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(CheckOf(APage, 'BlockEndLabels').Checked, 'standardmäßig an');
  Assert.AreEqual(ShortCutToText($40BE), EditOf(APage, 'HideElementKey').Text, 'Strg+.');
  Assert.AreEqual('25', EditOf(APage, 'BlockEndLabelsMinLines').Text, 'Mindestlänge (#620)');
  Assert.IsTrue(CheckOf(APage, 'DimUnusedUses').Checked, 'uses abblenden standardmäßig an (#621)');
  Assert.IsTrue(CheckOf(APage, 'RecursionMarkers').Checked, 'Rekursionssymbole standardmäßig an (#623)');
  Assert.AreEqual('4', EditOf(APage, 'RecursionMarkersDepth').Text);
  // Datenfluss (#690).
  Assert.IsTrue(CheckOf(APage, 'DataFlow').Checked, 'navigation.dataFlow (#690)');
  Assert.AreEqual('6', EditOf(APage, 'DataFlowMaxDepth').Text);
  Assert.IsFalse(CheckOf(APage, 'DataFlowExcludeTests').Checked);
  CheckOf(APage, 'DataFlow').Checked := False;
  EditOf(APage, 'DataFlowMaxDepth').Text := '9';
  CheckOf(APage, 'DataFlowExcludeTests').Checked := True;
  Assert.IsTrue(CheckOf(APage, 'ExitPoints').Checked, 'Austrittspunkte standardmaessig an (#698)');
  Assert.IsTrue(CheckOf(APage, 'ExitPointsExceptions').Checked);
  Assert.IsTrue(CheckOf(APage, 'ExitPointsLoops').Checked);
  Assert.IsTrue(CheckOf(APage, 'ExitPointsBadge').Checked);
  Assert.IsTrue(CheckOf(APage, 'Reassigned').Checked, 'Unterstreichung standardmaessig an (#712)');
  Assert.IsTrue(APage.ReassignedTargetCheck(TAtlasReassignedTarget.Locals).Checked);
  Assert.IsFalse(APage.ReassignedTargetCheck(TAtlasReassignedTarget.LoopVars).Checked);
  Assert.IsTrue(APage.ReassignedTargetCheck(TAtlasReassignedTarget.ValueParams).Checked);
  Assert.IsFalse(APage.ReassignedTargetCheck(TAtlasReassignedTarget.Fields).Checked);
  Assert.AreEqual(0, APage.ReassignedStyleBox.Choice, 'gepunktet');
  Assert.AreEqual('theme', APage.ReassignedColorEdit.Text);
  Assert.IsTrue(CheckOf(APage, 'ExpressionType').Checked, 'Typ des Ausdrucks standardmaessig an (#689)');
  Assert.IsTrue(CheckOf(APage, 'ExpressionTypeConversions').Checked);
  Assert.IsTrue(CheckOf(APage, 'ExpressionTypeConstValue').Checked);
  Assert.AreEqual(ShortCutToText($6054), EditOf(APage, 'ExpressionTypeKey').Text);
  Assert.AreEqual(0, APage.MethodPlacementBox.Choice, 'Methoden wie die Deklaration (#660)');
end;
/// <summary>Vorgaben und Änderungen: Atlas-Spalte, gleicher Text, Blockkommentar.</summary>
procedure EditHideElementSelection(APage: TAtlasSettingsPage);
begin
  // Atlas-Spalte in der Zeilenleiste (#768).
  Assert.IsTrue(CheckOf(APage, 'GutterColumn').Checked, 'Atlas-Spalte standardmäßig an (#768)');
  Assert.IsTrue(CheckOf(APage, 'GutterColumnProblems').Checked);
  Assert.IsTrue(CheckOf(APage, 'GutterColumnCodeActions').Checked);
  Assert.IsTrue(CheckOf(APage, 'GutterColumnOverrides').Checked);
  CheckOf(APage, 'GutterColumnCodeActions').Checked := False;
  CheckOf(APage, 'GutterColumnOverrides').Checked := False;
  // Gleichen Text hervorheben (#709).
  Assert.IsTrue(CheckOf(APage, 'SelectionMatches').Checked, 'gleichen Text hervorheben standardmäßig an (#709)');
  Assert.AreEqual('3', APage.SelectionMatchesMinLength.Text);
  Assert.IsFalse(CheckOf(APage, 'SelectionMatchesCaseSensitive').Checked);
  Assert.IsFalse(CheckOf(APage, 'SelectionMatchesWholeWord').Checked);
  Assert.IsTrue(CheckOf(APage, 'SelectionMatchesNavigateF3').Checked);
  Assert.AreEqual('1000', APage.SelectionMatchesMaxMatches.Text);
  APage.SelectionMatchesMinLength.Text := '4';
  CheckOf(APage, 'SelectionMatchesWholeWord').Checked := True;
  CheckOf(APage, 'SelectionMatchesNavigateF3').Checked := False;
  APage.SelectionMatchesMaxMatches.Text := '50';
  // Blockkommentar umschalten (#703).
  Assert.IsTrue(CheckOf(APage, 'ToggleBlockComment').Checked, 'Blockkommentar umschalten standardmäßig an (#703)');
  Assert.AreEqual(ShortCutToText($A041), EditOf(APage, 'ToggleBlockCommentKey').Text);
  Assert.AreEqual(0, APage.ToggleBlockCommentStyle.Choice);
  Assert.AreEqual(0, APage.ToggleBlockCommentFallback.Choice);
  Assert.IsFalse(CheckOf(APage, 'ToggleBlockCommentOwnLines').Checked);
  Assert.AreEqual(0, APage.ToggleBlockCommentScope.Choice);
  APage.ToggleBlockCommentStyle.Choice := 1;
  APage.ToggleBlockCommentFallback.Choice := 1;
  CheckOf(APage, 'ToggleBlockCommentOwnLines').Checked := True;
  APage.ToggleBlockCommentScope.Choice := 1;
end;
/// <summary>Vorgaben und Änderungen: Zeilen, Umschließen, Löschen, Fehlertext, Abschalten.</summary>
procedure EditHideElementCommands(APage: TAtlasSettingsPage);
begin
  // Neue Zeile ober- oder unterhalb (#700).
  Assert.IsTrue(CheckOf(APage, 'NewLineAround').Checked, 'Neue Zeile ober-/unterhalb standardmäßig an (#700)');
  Assert.AreEqual(ShortCutToText($200D), EditOf(APage, 'NewLineBelowKey').Text);
  Assert.AreEqual(ShortCutToText($C00D), EditOf(APage, 'NewLineAboveKey').Text);
  Assert.IsTrue(CheckOf(APage, 'NewLineAroundStatementAware').Checked);
  CheckOf(APage, 'NewLineAroundStatementAware').Checked := False;
  // Umschließung entfernen (#657).
  Assert.IsTrue(CheckOf(APage, 'Unwrap').Checked, 'Umschließung entfernen standardmäßig an (#657)');
  Assert.AreEqual(ShortCutToText($602E), EditOf(APage, 'UnwrapKey').Text);
  CheckOf(APage, 'Unwrap').Checked := False;
  // Sicher löschen (#716).
  Assert.IsTrue(CheckOf(APage, 'SafeDelete').Checked, 'Sicher löschen standardmäßig an (#716)');
  Assert.AreEqual(ShortCutToText($802E), EditOf(APage, 'SafeDeleteKey').Text);
  CheckOf(APage, 'SafeDelete').Checked := False;
  // Markierung beim Tippen umschließen (#672).
  Assert.IsTrue(CheckOf(APage, 'WrapSelection').Checked, 'Umschließen standardmäßig an (#672)');
  Assert.AreEqual('([{''', EditOf(APage, 'WrapSelectionChars').Text);
  EditOf(APage, 'WrapSelectionChars').Text := ' ([<';
  // Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).
  Assert.AreEqual(1, APage.InlineDiagnostics.Choice, 'nur Fehler');
  Assert.IsTrue(CheckOf(APage, 'ProblemsStatusCounter').Checked);
  Assert.AreEqual(ShortCutToText($C077), EditOf(APage, 'NextProblemKey').Text);
  CheckOf(APage, 'BlockEndLabels').Checked := False;
  CheckOf(APage, 'DimUnusedUses').Checked := False;
  CheckOf(APage, 'RecursionMarkers').Checked := False;
  EditOf(APage, 'RecursionMarkersDepth').Text := '2';
  CheckOf(APage, 'ExitPoints').Checked := False;
  CheckOf(APage, 'ExitPointsBadge').Checked := False;
  CheckOf(APage, 'Reassigned').Checked := False;
  APage.ReassignedTargetCheck(TAtlasReassignedTarget.ValueParams).Checked := False;
  APage.ReassignedTargetCheck(TAtlasReassignedTarget.VarParams).Checked := True;
  APage.ReassignedStyleBox.Choice := 1;
  APage.ReassignedColorEdit.Text := 'rot';
  CheckOf(APage, 'ExpressionType').Checked := False;
  CheckOf(APage, 'ExpressionTypeConstValue').Checked := False;
  EditOf(APage, 'ExpressionTypeKey').Text := '';
  APage.MethodPlacementBox.Choice := 2;
  APage.InlineDiagnostics.Choice := 2;
  CheckOf(APage, 'ProblemsStatusCounter').Checked := False;
  EditOf(APage, 'PreviousProblemKey').Text := '';
  EditOf(APage, 'BlockEndLabelsMinLines').Text := '30';
  EditOf(APage, 'HideElementKey').Text := '';
end;
/// <summary>Gespeichert: Blockende, Datenfluss, Austrittspunkte, Unterstreichung, Ausdruckstyp, Spalte.</summary>
procedure AssertHideElementSavedMarkers(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.BlockEndLabels, 'abschaltbar');
  Assert.AreEqual(30, ASaved.BlockEndLabelsMinLines);
  Assert.IsFalse(ASaved.DimUnusedUses);
  Assert.IsFalse(ASaved.RecursionMarkers);
  Assert.AreEqual(2, ASaved.RecursionMarkersDepth);
  Assert.IsFalse(ASaved.DataFlow);
  Assert.AreEqual(9, ASaved.DataFlowMaxDepth);
  Assert.IsTrue(ASaved.DataFlowExcludeTests);
  Assert.IsFalse(ASaved.ExitPoints);
  Assert.IsTrue(ASaved.ExitPointsExceptions);
  Assert.IsTrue(ASaved.ExitPointsLoops);
  Assert.IsFalse(ASaved.ExitPointsBadge);
  Assert.IsFalse(ASaved.Reassigned);
  Assert.AreEqual('locals,varParams', ASaved.ReassignedTargets);
  Assert.AreEqual('solid', ASaved.ReassignedStyle);
  Assert.AreEqual('theme', ASaved.ReassignedColor, 'Unlesbares wird theme');
  Assert.IsFalse(ASaved.ExpressionType);
  Assert.IsTrue(ASaved.ExpressionTypeConversions);
  Assert.IsFalse(ASaved.ExpressionTypeConstValue);
  Assert.AreEqual('off', ASaved.MethodPlacement, 'Methodenreihenfolge abschaltbar');
  Assert.AreEqual(0, ASaved.ExpressionTypeKey, 'leer = kein Kuerzel');
  Assert.IsTrue(ASaved.GutterColumn);
  Assert.IsTrue(ASaved.GutterColumnProblems);
  Assert.IsFalse(ASaved.GutterColumnCodeActions);
  Assert.IsFalse(ASaved.GutterColumnOverrides);
end;
/// <summary>Gespeichert: gleicher Text, Blockkommentar, Zeilen, Umschließen, Löschen, Fehlertext.</summary>
procedure AssertHideElementSavedEditing(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsTrue(ASaved.SelectionMatches);
  Assert.AreEqual(4, ASaved.SelectionMatchesMinLength);
  Assert.IsFalse(ASaved.SelectionMatchesCaseSensitive);
  Assert.IsTrue(ASaved.SelectionMatchesWholeWord);
  Assert.IsFalse(ASaved.SelectionMatchesNavigateF3);
  Assert.AreEqual(50, ASaved.SelectionMatchesMaxMatches);
  Assert.IsTrue(ASaved.ToggleBlockComment);
  Assert.AreEqual($A041, ASaved.ToggleBlockCommentKey);
  Assert.AreEqual('parens', ASaved.ToggleBlockCommentStyle);
  Assert.AreEqual('refuse', ASaved.ToggleBlockCommentFallback);
  Assert.IsTrue(ASaved.ToggleBlockCommentOwnLines);
  Assert.AreEqual('line', ASaved.ToggleBlockCommentWithoutSelection);
  Assert.IsTrue(ASaved.NewLineAround);
  Assert.AreEqual($200D, ASaved.NewLineBelowKey);
  Assert.AreEqual($C00D, ASaved.NewLineAboveKey);
  Assert.IsFalse(ASaved.NewLineAroundStatementAware);
  Assert.IsFalse(ASaved.Unwrap);
  Assert.AreEqual($602E, ASaved.UnwrapKey);
  Assert.IsFalse(ASaved.SafeDelete);
  Assert.AreEqual($802E, ASaved.SafeDeleteKey);
  Assert.IsTrue(ASaved.WrapSelection);
  Assert.AreEqual('([<', ASaved.WrapSelectionChars);
  Assert.AreEqual('errorsAndWarnings', ASaved.InlineDiagnostics);
  Assert.IsFalse(ASaved.ProblemsStatusCounter);
  Assert.AreEqual($C077, ASaved.NextProblemKey);
  Assert.AreEqual(0, ASaved.PreviousProblemKey);
  Assert.AreEqual(0, ASaved.HideElementKey, 'leer = keine Taste');
end;
/// <summary>Seite nach erneutem Laden.</summary>
procedure AssertHideElementReloaded(APage: TAtlasSettingsPage);
begin
  Assert.IsFalse(CheckOf(APage, 'BlockEndLabels').Checked);
  Assert.IsFalse(CheckOf(APage, 'DimUnusedUses').Checked);
  Assert.IsFalse(CheckOf(APage, 'RecursionMarkers').Checked);
  Assert.IsFalse(CheckOf(APage, 'ExitPoints').Checked);
  Assert.IsFalse(CheckOf(APage, 'ExitPointsBadge').Checked);
  Assert.IsFalse(CheckOf(APage, 'Reassigned').Checked);
  Assert.IsTrue(APage.ReassignedTargetCheck(TAtlasReassignedTarget.VarParams).Checked);
  Assert.AreEqual(1, APage.ReassignedStyleBox.Choice);
  Assert.IsFalse(CheckOf(APage, 'ExpressionType').Checked);
  Assert.IsFalse(CheckOf(APage, 'ExpressionTypeConstValue').Checked);
  Assert.IsFalse(CheckOf(APage, 'GutterColumnOverrides').Checked);
  Assert.IsTrue(CheckOf(APage, 'SelectionMatchesWholeWord').Checked);
  Assert.AreEqual(1, APage.ToggleBlockCommentScope.Choice);
  Assert.AreEqual(2, APage.InlineDiagnostics.Choice);
  Assert.AreEqual('', EditOf(APage, 'HideElementKey').Text);
end;
procedure TAtlasSettingsPageEditorTests.HideElementRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    EditHideElementMarkers(Page);
    EditHideElementSelection(Page);
    EditHideElementCommands(Page);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    AssertHideElementSavedMarkers(Saved);
    AssertHideElementSavedEditing(Saved);
    Page.LoadFrom(Saved);
    AssertHideElementReloaded(Page);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.GenerateMenuRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'GenerateMenu').Checked, 'standardmäßig an');
    Assert.AreEqual(ShortCutToText($802D), EditOf(Page, 'GenerateMenuKey').Text, 'Alt+Einfg');
    Assert.AreEqual('generate,surround,templates', EditOf(Page, 'GenerateMenuGroups').Text);
    Assert.AreEqual('', EditOf(Page, 'GenerateMenuHidden').Text);
    Assert.IsTrue(CheckOf(Page, 'GenerateMenuRecentFirst').Checked);
    Assert.IsTrue(CheckOf(Page, 'GenerateMenuShowCommandNames').Checked);
    CheckOf(Page, 'GenerateMenu').Checked := False;
    EditOf(Page, 'GenerateMenuKey').Text := '';
    EditOf(Page, 'GenerateMenuGroups').Text := 'templates';
    EditOf(Page, 'GenerateMenuHidden').Text := '/json';
    CheckOf(Page, 'GenerateMenuRecentFirst').Checked := False;
    CheckOf(Page, 'GenerateMenuShowCommandNames').Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.GenerateMenu, 'abschaltbar');
    Assert.AreEqual(0, Saved.GenerateMenuKey, 'leer = keine Taste');
    Assert.AreEqual('templates', Saved.GenerateMenuGroups);
    Assert.AreEqual('/json', Saved.GenerateMenuHidden);
    Assert.IsFalse(Saved.GenerateMenuRecentFirst);
    Assert.IsFalse(Saved.GenerateMenuShowCommandNames);
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'GenerateMenu').Checked);
    Assert.AreEqual('/json', EditOf(Page, 'GenerateMenuHidden').Text);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.BookmarksRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'BookmarksNamed').Checked, 'Lesezeichen standardmäßig an');
    Assert.IsFalse(CheckOf(Page, 'BookmarksShared').Checked, 'standardmäßig lokal');
    Assert.AreEqual(ShortCutToText($C04B), EditOf(Page, 'BookmarkKey').Text, 'Strg+Alt+K');
    CheckOf(Page, 'BookmarksNamed').Checked := False;
    CheckOf(Page, 'BookmarksShared').Checked := True;
    EditOf(Page, 'BookmarkKey').Text := '';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.BookmarksNamed, 'abschaltbar');
    Assert.IsTrue(Saved.BookmarksShared);
    Assert.AreEqual(0, Saved.BookmarkKey, 'leer = keine Taste');
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'BookmarksNamed').Checked);
    Assert.IsTrue(CheckOf(Page, 'BookmarksShared').Checked);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.MoveLinesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #634: Schalter und Tasten; leeres Feld = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'MoveLines').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($8026)), EditOf(Page, 'MoveLinesUpKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($A028)), EditOf(Page, 'DuplicateLinesDownKey').Text);
    CheckOf(Page, 'MoveLines').Checked := False;
    EditOf(Page, 'MoveLinesUpKey').Text := '';
    EditOf(Page, 'DuplicateLinesDownKey').Text := ShortCutToText(TShortCut($C044));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.MoveLines);
    Assert.AreEqual(0, Saved.MoveLinesUpKey);
    Assert.AreEqual($8028, Saved.MoveLinesDownKey);
    Assert.AreEqual($C044, Saved.DuplicateLinesDownKey);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.ContinueCommentsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #696: Schalter und Präfix; Leerraum am Rand des Präfixes bleibt.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'ContinueComments').Checked);
    Assert.IsTrue(CheckOf(Page, 'ContinueCommentsLists').Checked);
    Assert.AreEqual('', Page.ContinueCommentsBlockPrefix.Text);
    CheckOf(Page, 'ContinueComments').Checked := False;
    CheckOf(Page, 'ContinueCommentsLists').Checked := False;
    Page.ContinueCommentsBlockPrefix.Text := ' * ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ContinueComments);
    Assert.IsFalse(Saved.ContinueCommentsLists);
    Assert.IsTrue(Saved.ContinueCommentsLineComments);
    Assert.AreEqual(' * ', Saved.ContinueCommentsBlockPrefix);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.CompleteStatementRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #697: Schalter, Taste und beide Auswahlen.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'CompleteStatement').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($600D)), EditOf(Page, 'CompleteStatementKey').Text);
    Assert.AreEqual(1, Page.CompleteStatementBeginEnd.Choice);
    Assert.AreEqual(0, Page.CompleteStatementTryKind.Choice);
    CheckOf(Page, 'CompleteStatement').Checked := False;
    EditOf(Page, 'CompleteStatementKey').Text := '';
    Page.CompleteStatementBeginEnd.Choice := 2;
    Page.CompleteStatementTryKind.Choice := 2;
    CheckOf(Page, 'CompleteStatementMethodBody').Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CompleteStatement);
    Assert.AreEqual(0, Saved.CompleteStatementKey);
    Assert.AreEqual('never', Saved.CompleteStatementBeginEnd);
    Assert.AreEqual('ask', Saved.CompleteStatementTryKind);
    Assert.IsFalse(Saved.CompleteStatementMethodBody);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.FormatCodeRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #43: Schalter und Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'FormatCode').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($E04C)), EditOf(Page, 'FormatCodeKey').Text);
    CheckOf(Page, 'FormatCode').Checked := False;
    EditOf(Page, 'FormatCodeKey').Text := '';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.FormatCode);
    Assert.AreEqual(0, Saved.FormatCodeKey);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.MultiCursorRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #589: Schalter, Klicktaste und die fünf Kürzel.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(CheckOf(Page, 'MultiCursor').Checked);
    // #658 steht daneben, ebenfalls experimentell und aus.
    Assert.IsFalse(CheckOf(Page, 'LinkedEditing').Checked);
    Assert.AreEqual(0, Page.MultiCursorModifier.Choice);
    Assert.AreEqual(ShortCutToText(TShortCut($4044)), EditOf(Page, 'MultiCursorNextKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($4044)), EditOf(Page, 'MultiCursorSkipKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($A049)), EditOf(Page, 'MultiCursorLineEndsKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($C026)), EditOf(Page, 'MultiCursorAboveKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($C028)), EditOf(Page, 'MultiCursorBelowKey').Text);
    CheckOf(Page, 'MultiCursor').Checked := True;
    CheckOf(Page, 'LinkedEditing').Checked := True;
    Page.MultiCursorModifier.Choice := 1;
    EditOf(Page, 'MultiCursorNextKey').Text := '';
    EditOf(Page, 'MultiCursorSkipKey').Text := ShortCutToText(TShortCut($4053));
    EditOf(Page, 'MultiCursorLineEndsKey').Text := ShortCutToText(TShortCut($C049));
    EditOf(Page, 'MultiCursorAboveKey').Text := ShortCutToText(TShortCut($A026));
    EditOf(Page, 'MultiCursorBelowKey').Text := ShortCutToText(TShortCut($A028));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.MultiCursor);
    Assert.IsTrue(Saved.LinkedEditing);
    Assert.AreEqual('ctrl', Saved.MultiCursorModifier);
    Assert.AreEqual(0, Saved.MultiCursorNextKey);
    Assert.AreEqual($4053, Saved.MultiCursorSkipKey);
    Assert.AreEqual($C049, Saved.MultiCursorLineEndsKey);
    Assert.AreEqual($A026, Saved.MultiCursorAboveKey);
    Assert.AreEqual($A028, Saved.MultiCursorBelowKey);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.SmartPasteRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Index: Integer;
const
  Values: array[0..3] of string = ('off', 'uses', 'indent', 'both');
begin
  // #515: Auswahl mit vier Einträgen, Vorgabe aus.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual(0, Page.SmartPaste.Choice);
    for Index := 0 to High(Values) do
    begin
      Settings.SmartPaste := Values[Index];
      Page.LoadFrom(Settings);
      Assert.AreEqual(Index, Page.SmartPaste.Choice);
      Saved := TAtlasPluginSettings.Defaults;
      Page.SaveTo(Saved);
      Assert.AreEqual(Values[Index], Saved.SmartPaste);
    end;
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.StickyScrollRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #506: Schalter und Höchstzahl der Zeilen.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'StickyScroll').Checked);
    Assert.AreEqual('3', EditOf(Page, 'StickyScrollMaxLines').Text);
    CheckOf(Page, 'StickyScroll').Checked := True;
    EditOf(Page, 'StickyScrollMaxLines').Text := '2';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StickyScroll);
    Assert.AreEqual(2, Saved.StickyScrollMaxLines);
    // Was der Kopf zeigt: je Art ein Schalter.
    Assert.IsTrue(CheckOf(Page, 'StickyScrollTypes').Checked and CheckOf(Page, 'StickyScrollRoutines').Checked);
    Assert.IsFalse(CheckOf(Page, 'StickyScrollTry').Checked);
    CheckOf(Page, 'StickyScrollRoutines').Checked := False;
    CheckOf(Page, 'StickyScrollTry').Checked := True;
    CheckOf(Page, 'StickyScrollWith').Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StickyScrollTypes);
    Assert.IsFalse(Saved.StickyScrollRoutines);
    Assert.IsFalse(Saved.StickyScrollLoops);
    Assert.IsTrue(Saved.StickyScrollTry);
    Assert.IsFalse(Saved.StickyScrollCase);
    Assert.IsTrue(Saved.StickyScrollWith);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.EditorToolbarRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #1101: Position als Auswahl, Belegung als Text (beim Speichern bereinigt), „Leiste anpassen …“ vorhanden.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual(Settings.EditorToolbarItems, Page.EditorToolbarItemsEdit.Text);
    Assert.AreEqual(0, Page.EditorToolbarPositionBox.Choice);
    Assert.IsNotNull(Page.EditorToolbarCustomizeButton);
    Page.EditorToolbarPositionBox.Choice := 2;
    Page.EditorToolbarItemsEdit.Text := ' Atlas.NavBack , | , | ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('inBreadcrumbs', Saved.EditorToolbarPosition);
    Assert.AreEqual('Atlas.NavBack', Saved.EditorToolbarItems);
    Assert.IsTrue(Saved.EditorToolbar);
    Assert.IsTrue(Saved.EditorToolbarReturnButton);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.EditorStatusBarRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #1155: Schalter und Elemente als Text; beim Speichern bereinigt (unbekannte weg, doppelte einmal).
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual('status,findings,liveCheck,method', Page.EditorStatusBarItemsEdit.Text);
    Page.EditorStatusBarItemsEdit.Text := ' method , foo, status, method ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('method,status', Saved.EditorStatusBarItems);
    Assert.IsTrue(Saved.EditorStatusBar);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.CallHierarchyDiagramRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.CallHierarchyDiagram := False;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Assert.IsTrue(Saved.CallHierarchyDiagram);
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CallHierarchyDiagram, 'aus bleibt aus');
    Settings.CallHierarchyDiagram := True;
    Page.LoadFrom(Settings);
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.CallHierarchyDiagram, 'an bleibt an');
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.QuickBookmarksRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #1104: Schalter, Taste, Wartezeit (begrenzt), Sprungbereich als Auswahl, Tasten für nächstes/voriges.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'QuickBookmarks').Checked);
    Assert.IsTrue(CheckOf(Page, 'QuickBookmarksGutter').Checked);
    Assert.AreEqual('800', Page.QuickBookmarkChordWaitEdit.Text);
    Assert.AreEqual(0, Page.QuickBookmarksScopeBox.Choice);
    Assert.AreEqual('', EditOf(Page, 'NextBookmarkKey').Text);
    CheckOf(Page, 'QuickBookmarksGutterClick').Checked := False;
    CheckOf(Page, 'QuickBookmarksNumberedKeys').Checked := False;
    CheckOf(Page, 'QuickBookmarksImportIde').Checked := False;
    Page.QuickBookmarkChordWaitEdit.Text := '99999';
    Page.QuickBookmarksScopeBox.Choice := 1;
    EditOf(Page, 'QuickBookmarkKey').Text := '';
    EditOf(Page, 'NextBookmarkKey').Text := 'F2';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.QuickBookmarks);
    Assert.IsFalse(Saved.QuickBookmarksGutterClick);
    Assert.IsFalse(Saved.QuickBookmarksNumberedKeys);
    Assert.IsFalse(Saved.QuickBookmarksImportIde);
    Assert.AreEqual(TAtlasPluginSettings.MaxQuickChordWait, Saved.QuickBookmarkChordWait);
    Assert.AreEqual('file', Saved.QuickBookmarksScope);
    Assert.AreEqual(0, Saved.QuickBookmarkKey);
    Assert.AreEqual($71, Saved.NextBookmarkKey, 'F2');
    Assert.AreEqual(0, Saved.PreviousBookmarkKey);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.ContinuePatternRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #671: Schalter und Mindestzeilen.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'ContinuePattern').Checked);
    Assert.AreEqual('2', EditOf(Page, 'ContinuePatternMinLines').Text);
    CheckOf(Page, 'ContinuePattern').Checked := False;
    EditOf(Page, 'ContinuePatternMinLines').Text := '3';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ContinuePattern);
    Assert.AreEqual(3, Saved.ContinuePatternMinLines);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.MethodToggleRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #775: Schalter und beide Tasten; leeres Feld = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(CheckOf(Page, 'MethodToggle').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($6026)), EditOf(Page, 'MethodToggleUpKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($6028)), EditOf(Page, 'MethodToggleDownKey').Text);
    CheckOf(Page, 'MethodToggle').Checked := False;
    EditOf(Page, 'MethodToggleUpKey').Text := '';
    EditOf(Page, 'MethodToggleDownKey').Text := ShortCutToText(TShortCut($C044));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.MethodToggle);
    Assert.AreEqual(0, Saved.MethodToggleUpKey);
    Assert.AreEqual($C044, Saved.MethodToggleDownKey);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageEditorTests);

end.
