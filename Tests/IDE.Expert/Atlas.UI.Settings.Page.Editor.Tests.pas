unit Atlas.UI.Settings.Page.Editor.Tests;

// Tests der Einstellungsseite: Seiten für Editorbefehle und Leisten.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Seiten für Editorbefehle und Leisten.</summary>
  [TestFixture]
  TAtlasSettingsPageEditorTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
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
    /// <summary>#1122: Kontrollkästchen „Aufrufdiagramm“ liest und schreibt callHierarchy.diagram.</summary>
    [Test]
    procedure CallHierarchyDiagramRoundTrip;
    /// <summary>#1744: Kürzel „Datei jetzt prüfen“ auf der Seite Befehle.</summary>
    [Test]
    procedure CheckFileKeyRoundTrip;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Reassigned,
  Atlas.UI.Settings.Page,
  Vcl.Menus,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Page.Commands,
  Atlas.UI.Settings.Page.EditorCode,
  Atlas.UI.Settings.Page.EditorView;

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
  Assert.IsTrue(APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.Locals).Checked);
  Assert.IsFalse(APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.LoopVars)
    .Checked);
  Assert.IsTrue(APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.ValueParams)
    .Checked);
  Assert.IsFalse(APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.Fields).Checked);
  Assert.AreEqual(0, APage.Part<TAtlasSettingsEditorCodePart>.ReassignedStyleBox.Choice, 'gepunktet');
  Assert.AreEqual('theme', APage.Part<TAtlasSettingsEditorCodePart>.ReassignedColorEdit.Text);
  Assert.IsTrue(CheckOf(APage, 'ExpressionType').Checked, 'Typ des Ausdrucks standardmaessig an (#689)');
  Assert.IsTrue(CheckOf(APage, 'ExpressionTypeConversions').Checked);
  Assert.IsTrue(CheckOf(APage, 'ExpressionTypeConstValue').Checked);
  Assert.AreEqual(ShortCutToText($6054), EditOf(APage, 'ExpressionTypeKey').Text);
  Assert.AreEqual(0, APage.Part<TAtlasSettingsEditorCodePart>.MethodPlacementBox.Choice, 'Methoden wie die Deklaration (#660)');
  Assert.AreEqual(0, APage.Part<TAtlasSettingsEditorCodePart>.RegionFoldsBox.Choice, 'Regionen unveraendert (#1814)');
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
  Assert.AreEqual('3', APage.Part<TAtlasSettingsEditorViewPart>.SelectionMatchesMinLength.Text);
  Assert.IsFalse(CheckOf(APage, 'SelectionMatchesCaseSensitive').Checked);
  Assert.IsFalse(CheckOf(APage, 'SelectionMatchesWholeWord').Checked);
  Assert.IsTrue(CheckOf(APage, 'SelectionMatchesNavigateF3').Checked);
  Assert.AreEqual('1000', APage.Part<TAtlasSettingsEditorViewPart>.SelectionMatchesMaxMatches.Text);
  APage.Part<TAtlasSettingsEditorViewPart>.SelectionMatchesMinLength.Text := '4';
  CheckOf(APage, 'SelectionMatchesWholeWord').Checked := True;
  CheckOf(APage, 'SelectionMatchesNavigateF3').Checked := False;
  APage.Part<TAtlasSettingsEditorViewPart>.SelectionMatchesMaxMatches.Text := '50';
  // Blockkommentar umschalten (#703).
  Assert.IsTrue(CheckOf(APage, 'ToggleBlockComment').Checked, 'Blockkommentar umschalten standardmäßig an (#703)');
  Assert.AreEqual(ShortCutToText($A041), EditOf(APage, 'ToggleBlockCommentKey').Text);
  Assert.AreEqual(0, APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentStyle.Choice);
  Assert.AreEqual(0, APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentFallback.Choice);
  Assert.IsFalse(CheckOf(APage, 'ToggleBlockCommentOwnLines').Checked);
  Assert.AreEqual(0, APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentScope.Choice);
  APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentStyle.Choice := 1;
  APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentFallback.Choice := 1;
  CheckOf(APage, 'ToggleBlockCommentOwnLines').Checked := True;
  APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentScope.Choice := 1;
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
  Assert.AreEqual(1, APage.Part<TAtlasSettingsEditorCodePart>.InlineDiagnostics.Choice, 'nur Fehler');
  Assert.IsTrue(CheckOf(APage, 'ProblemsStatusCounter').Checked);
  Assert.AreEqual(ShortCutToText($C077), EditOf(APage, 'NextProblemKey').Text);
  CheckOf(APage, 'BlockEndLabels').Checked := False;
  CheckOf(APage, 'DimUnusedUses').Checked := False;
  CheckOf(APage, 'RecursionMarkers').Checked := False;
  EditOf(APage, 'RecursionMarkersDepth').Text := '2';
  CheckOf(APage, 'ExitPoints').Checked := False;
  CheckOf(APage, 'ExitPointsBadge').Checked := False;
  CheckOf(APage, 'Reassigned').Checked := False;
  APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.ValueParams).Checked := False;
  APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.VarParams).Checked := True;
  APage.Part<TAtlasSettingsEditorCodePart>.ReassignedStyleBox.Choice := 1;
  APage.Part<TAtlasSettingsEditorCodePart>.ReassignedColorEdit.Text := 'rot';
  CheckOf(APage, 'ExpressionType').Checked := False;
  CheckOf(APage, 'ExpressionTypeConstValue').Checked := False;
  EditOf(APage, 'ExpressionTypeKey').Text := '';
  APage.Part<TAtlasSettingsEditorCodePart>.MethodPlacementBox.Choice := 3;
  APage.Part<TAtlasSettingsEditorCodePart>.RegionFoldsBox.Choice := 1;
  APage.Part<TAtlasSettingsEditorCodePart>.InlineDiagnostics.Choice := 2;
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
  Assert.AreEqual('collapse', ASaved.RegionFolds, 'Regionen beim Oeffnen zuklappen (#1814)');
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
  Assert.IsTrue(APage.Part<TAtlasSettingsEditorCodePart>.ReassignedTargetCheck(TAtlasReassignedTarget.VarParams)
    .Checked);
  Assert.AreEqual(1, APage.Part<TAtlasSettingsEditorCodePart>.ReassignedStyleBox.Choice);
  Assert.IsFalse(CheckOf(APage, 'ExpressionType').Checked);
  Assert.IsFalse(CheckOf(APage, 'ExpressionTypeConstValue').Checked);
  Assert.IsFalse(CheckOf(APage, 'GutterColumnOverrides').Checked);
  Assert.IsTrue(CheckOf(APage, 'SelectionMatchesWholeWord').Checked);
  Assert.AreEqual(1, APage.Part<TAtlasSettingsCommandsPart>.ToggleBlockCommentScope.Choice);
  Assert.AreEqual(2, APage.Part<TAtlasSettingsEditorCodePart>.InlineDiagnostics.Choice);
  Assert.AreEqual('', EditOf(APage, 'HideElementKey').Text);
end;
procedure TAtlasSettingsPageEditorTests.HideElementRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    EditHideElementMarkers(mPage);
    EditHideElementSelection(mPage);
    EditHideElementCommands(mPage);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    AssertHideElementSavedMarkers(mSaved);
    AssertHideElementSavedEditing(mSaved);
    mPage.LoadFrom(mSaved);
    AssertHideElementReloaded(mPage);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.GenerateMenuRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'GenerateMenu').Checked, 'standardmäßig an');
    Assert.AreEqual(ShortCutToText($802D), EditOf(mPage, 'GenerateMenuKey').Text, 'Alt+Einfg');
    Assert.AreEqual('generate,surround,templates', EditOf(mPage, 'GenerateMenuGroups').Text);
    Assert.AreEqual('', EditOf(mPage, 'GenerateMenuHidden').Text);
    Assert.IsTrue(CheckOf(mPage, 'GenerateMenuRecentFirst').Checked);
    Assert.IsTrue(CheckOf(mPage, 'GenerateMenuShowCommandNames').Checked);
    CheckOf(mPage, 'GenerateMenu').Checked := False;
    EditOf(mPage, 'GenerateMenuKey').Text := '';
    EditOf(mPage, 'GenerateMenuGroups').Text := 'templates';
    EditOf(mPage, 'GenerateMenuHidden').Text := '/json';
    CheckOf(mPage, 'GenerateMenuRecentFirst').Checked := False;
    CheckOf(mPage, 'GenerateMenuShowCommandNames').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.GenerateMenu, 'abschaltbar');
    Assert.AreEqual(0, mSaved.GenerateMenuKey, 'leer = keine Taste');
    Assert.AreEqual('templates', mSaved.GenerateMenuGroups);
    Assert.AreEqual('/json', mSaved.GenerateMenuHidden);
    Assert.IsFalse(mSaved.GenerateMenuRecentFirst);
    Assert.IsFalse(mSaved.GenerateMenuShowCommandNames);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'GenerateMenu').Checked);
    Assert.AreEqual('/json', EditOf(mPage, 'GenerateMenuHidden').Text);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.MoveLinesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #634: Schalter und Tasten; leeres Feld = keine Taste.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'MoveLines').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($8026)), EditOf(mPage, 'MoveLinesUpKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($A028)), EditOf(mPage, 'DuplicateLinesDownKey').Text);
    CheckOf(mPage, 'MoveLines').Checked := False;
    EditOf(mPage, 'MoveLinesUpKey').Text := '';
    EditOf(mPage, 'DuplicateLinesDownKey').Text := ShortCutToText(TShortCut($C044));
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.MoveLines);
    Assert.AreEqual(0, mSaved.MoveLinesUpKey);
    Assert.AreEqual($8028, mSaved.MoveLinesDownKey);
    Assert.AreEqual($C044, mSaved.DuplicateLinesDownKey);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.ContinueCommentsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #696: Schalter und Präfix; Leerraum am Rand des Präfixes bleibt.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'ContinueComments').Checked);
    Assert.IsTrue(CheckOf(mPage, 'ContinueCommentsLists').Checked);
    Assert.AreEqual('', mPage.Part<TAtlasSettingsEditorCodePart>.ContinueCommentsBlockPrefix.Text);
    CheckOf(mPage, 'ContinueComments').Checked := False;
    CheckOf(mPage, 'ContinueCommentsLists').Checked := False;
    mPage.Part<TAtlasSettingsEditorCodePart>.ContinueCommentsBlockPrefix.Text := ' * ';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.ContinueComments);
    Assert.IsFalse(mSaved.ContinueCommentsLists);
    Assert.IsTrue(mSaved.ContinueCommentsLineComments);
    Assert.AreEqual(' * ', mSaved.ContinueCommentsBlockPrefix);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.CompleteStatementRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #697: Schalter, Taste und beide Auswahlen.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'CompleteStatement').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($600D)), EditOf(mPage, 'CompleteStatementKey').Text);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsEditorCodePart>.CompleteStatementBeginEnd.Choice);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsEditorCodePart>.CompleteStatementTryKind.Choice);
    CheckOf(mPage, 'CompleteStatement').Checked := False;
    EditOf(mPage, 'CompleteStatementKey').Text := '';
    mPage.Part<TAtlasSettingsEditorCodePart>.CompleteStatementBeginEnd.Choice := 2;
    mPage.Part<TAtlasSettingsEditorCodePart>.CompleteStatementTryKind.Choice := 2;
    CheckOf(mPage, 'CompleteStatementMethodBody').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.CompleteStatement);
    Assert.AreEqual(0, mSaved.CompleteStatementKey);
    Assert.AreEqual('never', mSaved.CompleteStatementBeginEnd);
    Assert.AreEqual('ask', mSaved.CompleteStatementTryKind);
    Assert.IsFalse(mSaved.CompleteStatementMethodBody);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.FormatCodeRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #43: Schalter und Taste.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'FormatCode').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($E04C)), EditOf(mPage, 'FormatCodeKey').Text);
    CheckOf(mPage, 'FormatCode').Checked := False;
    EditOf(mPage, 'FormatCodeKey').Text := '';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.FormatCode);
    Assert.AreEqual(0, mSaved.FormatCodeKey);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.CheckFileKeyRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(ShortCutToText(TShortCut($E050)), EditOf(mPage, 'CheckFileKey').Text, 'Strg+Umschalt+Alt+P');
    EditOf(mPage, 'CheckFileKey').Text := ShortCutToText(TShortCut($C04D));
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual($C04D, mSaved.CheckFileKey, 'Strg+Alt+M');
    EditOf(mPage, 'CheckFileKey').Text := '';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(0, mSaved.CheckFileKey, 'leer = keine Taste');
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.MultiCursorRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #589: Schalter, Klicktaste und die fünf Kürzel.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(CheckOf(mPage, 'MultiCursor').Checked);
    // #658 steht daneben, ebenfalls experimentell und aus.
    Assert.IsFalse(CheckOf(mPage, 'LinkedEditing').Checked);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsEditorCodePart>.MultiCursorModifier.Choice);
    Assert.AreEqual(ShortCutToText(TShortCut($4044)), EditOf(mPage, 'MultiCursorNextKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($4044)), EditOf(mPage, 'MultiCursorSkipKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($A049)), EditOf(mPage, 'MultiCursorLineEndsKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($C026)), EditOf(mPage, 'MultiCursorAboveKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($C028)), EditOf(mPage, 'MultiCursorBelowKey').Text);
    CheckOf(mPage, 'MultiCursor').Checked := True;
    CheckOf(mPage, 'LinkedEditing').Checked := True;
    mPage.Part<TAtlasSettingsEditorCodePart>.MultiCursorModifier.Choice := 1;
    EditOf(mPage, 'MultiCursorNextKey').Text := '';
    EditOf(mPage, 'MultiCursorSkipKey').Text := ShortCutToText(TShortCut($4053));
    EditOf(mPage, 'MultiCursorLineEndsKey').Text := ShortCutToText(TShortCut($C049));
    EditOf(mPage, 'MultiCursorAboveKey').Text := ShortCutToText(TShortCut($A026));
    EditOf(mPage, 'MultiCursorBelowKey').Text := ShortCutToText(TShortCut($A028));
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.MultiCursor);
    Assert.IsTrue(mSaved.LinkedEditing);
    Assert.AreEqual('ctrl', mSaved.MultiCursorModifier);
    Assert.AreEqual(0, mSaved.MultiCursorNextKey);
    Assert.AreEqual($4053, mSaved.MultiCursorSkipKey);
    Assert.AreEqual($C049, mSaved.MultiCursorLineEndsKey);
    Assert.AreEqual($A026, mSaved.MultiCursorAboveKey);
    Assert.AreEqual($A028, mSaved.MultiCursorBelowKey);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.SmartPasteRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mIndex: Integer;
const
  cValues: array[0..3] of string = ('off', 'uses', 'indent', 'both');
begin
  // #515: Auswahl mit vier Einträgen, Vorgabe aus.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsEditorCodePart>.SmartPaste.Choice);
    for mIndex := 0 to High(cValues) do
    begin
      mSettings.SmartPaste := cValues[mIndex];
      mPage.LoadFrom(mSettings);
      Assert.AreEqual(mIndex, mPage.Part<TAtlasSettingsEditorCodePart>.SmartPaste.Choice);
      mSaved := TAtlasPluginSettings.Defaults;
      mPage.SaveTo(mSaved);
      Assert.AreEqual(cValues[mIndex], mSaved.SmartPaste);
    end;
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.StickyScrollRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #506: Schalter und Höchstzahl der Zeilen.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'StickyScroll').Checked);
    Assert.AreEqual('3', EditOf(mPage, 'StickyScrollMaxLines').Text);
    CheckOf(mPage, 'StickyScroll').Checked := True;
    EditOf(mPage, 'StickyScrollMaxLines').Text := '2';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.StickyScroll);
    Assert.AreEqual(2, mSaved.StickyScrollMaxLines);
    // Was der Kopf zeigt: je Art ein Schalter.
    Assert.IsTrue(CheckOf(mPage, 'StickyScrollTypes').Checked and CheckOf(mPage, 'StickyScrollRoutines').Checked);
    Assert.IsFalse(CheckOf(mPage, 'StickyScrollTry').Checked);
    CheckOf(mPage, 'StickyScrollRoutines').Checked := False;
    CheckOf(mPage, 'StickyScrollTry').Checked := True;
    CheckOf(mPage, 'StickyScrollWith').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.StickyScrollTypes);
    Assert.IsFalse(mSaved.StickyScrollRoutines);
    Assert.IsFalse(mSaved.StickyScrollLoops);
    Assert.IsTrue(mSaved.StickyScrollTry);
    Assert.IsFalse(mSaved.StickyScrollCase);
    Assert.IsTrue(mSaved.StickyScrollWith);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.EditorToolbarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #1101: Position als Auswahl, Belegung als Text (beim Speichern bereinigt), „Leiste anpassen …“ vorhanden.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.AreEqual(mSettings.EditorToolbarItems, mPage.Part<TAtlasSettingsEditorViewPart>.EditorToolbarItemsEdit.Text);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsEditorViewPart>.EditorToolbarPositionBox.Choice);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsEditorViewPart>.EditorToolbarCustomizeButton);
    mPage.Part<TAtlasSettingsEditorViewPart>.EditorToolbarPositionBox.Choice := 2;
    mPage.Part<TAtlasSettingsEditorViewPart>.EditorToolbarItemsEdit.Text := ' Atlas.NavBack , | , | ';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('inBreadcrumbs', mSaved.EditorToolbarPosition);
    Assert.AreEqual('Atlas.NavBack', mSaved.EditorToolbarItems);
    Assert.IsTrue(mSaved.EditorToolbar);
    Assert.IsTrue(mSaved.EditorToolbarReturnButton);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.EditorStatusBarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #1155: Schalter und Elemente als Text; beim Speichern bereinigt (unbekannte weg, doppelte einmal).
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.AreEqual('status,findings,liveCheck,method', mPage.Part<TAtlasSettingsEditorViewPart>.EditorStatusBarItemsEdit.Text);
    mPage.Part<TAtlasSettingsEditorViewPart>.EditorStatusBarItemsEdit.Text := ' method , foo, status, method ';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('method,status', mSaved.EditorStatusBarItems);
    Assert.IsTrue(mSaved.EditorStatusBar);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.CallHierarchyDiagramRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.CallHierarchyDiagram := False;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    mSaved := TAtlasPluginSettings.Defaults;
    Assert.IsTrue(mSaved.CallHierarchyDiagram);
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.CallHierarchyDiagram, 'aus bleibt aus');
    mSettings.CallHierarchyDiagram := True;
    mPage.LoadFrom(mSettings);
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.CallHierarchyDiagram, 'an bleibt an');
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.ContinuePatternRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #671: Schalter und Mindestzeilen.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'ContinuePattern').Checked);
    Assert.AreEqual('2', EditOf(mPage, 'ContinuePatternMinLines').Text);
    CheckOf(mPage, 'ContinuePattern').Checked := False;
    EditOf(mPage, 'ContinuePatternMinLines').Text := '3';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.ContinuePattern);
    Assert.AreEqual(3, mSaved.ContinuePatternMinLines);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageEditorTests.MethodToggleRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #775: Schalter und beide Tasten; leeres Feld = keine Taste.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'MethodToggle').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($6026)), EditOf(mPage, 'MethodToggleUpKey').Text);
    Assert.AreEqual(ShortCutToText(TShortCut($6028)), EditOf(mPage, 'MethodToggleDownKey').Text);
    CheckOf(mPage, 'MethodToggle').Checked := False;
    EditOf(mPage, 'MethodToggleUpKey').Text := '';
    EditOf(mPage, 'MethodToggleDownKey').Text := ShortCutToText(TShortCut($C044));
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.MethodToggle);
    Assert.AreEqual(0, mSaved.MethodToggleUpKey);
    Assert.AreEqual($C044, mSaved.MethodToggleDownKey);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageEditorTests);

end.
