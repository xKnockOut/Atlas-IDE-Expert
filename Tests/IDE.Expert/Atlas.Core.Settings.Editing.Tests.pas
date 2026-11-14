unit Atlas.Core.Settings.Editing.Tests;

// Tests der Einstellungen für Bearbeitungsbefehle im Editor.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einstellungen der Bearbeitungsbefehle im Editor.</summary>
  [TestFixture]
  TAtlasEditingSettingsTests = class
  public
    [Test]
    procedure MoveLinesOptions;
    /// <summary>Kommentar beim Enter fortsetzen (#696): Vorgaben, Speichern, Laden, Präfix normalisieren.</summary>
    [Test]
    procedure ContinueCommentsOptions;
    /// <summary>Anweisung vervollständigen (#697): Vorgaben, Speichern, Laden, unbekannte Werte.</summary>
    [Test]
    procedure CompleteStatementOptions;
    /// <summary>#43: Befehl „Formatieren“ mit eigenem Kürzel.</summary>
    [Test]
    procedure FormatCodeOptions;
    [Test]
    procedure ContinuePatternOptions;
    [Test]
    procedure MultiCursorOptions;
    [Test]
    procedure SmartPasteOptions;
    /// <summary>Blockkommentar umschalten (#703): Vorgaben, Auswahlwerte normalisiert, Speichern und Laden.</summary>
    [Test]
    procedure ToggleBlockCommentOptions;
    /// <summary>Neue Zeile ober- oder unterhalb (#700): Vorgaben, Speichern und Laden.</summary>
    [Test]
    procedure NewLineAroundOptions;
    /// <summary>Umschließung entfernen (#657): Vorgaben, Speichern und Laden, Kürzel normalisiert.</summary>
    [Test]
    procedure UnwrapOptions;
    /// <summary>Methodenrümpfe in Deklarationsreihenfolge (#660): Vorgabe, Werte normalisiert, Speichern und
    /// Laden.</summary>
    [Test]
    procedure MethodPlacementOptions;
    /// <summary>Regionen beim Öffnen (#1814): Vorgabe keep, Werte normalisiert, off gespeichert.</summary>
    [Test]
    procedure RegionFoldsOptions;
    [Test]
    procedure SafeDeleteOptions;
    /// <summary>Markierung beim Tippen umschließen (#672): Vorgaben, Speichern und Laden.</summary>
    [Test]
    procedure WrapSelectionOptions;
    /// <summary>Erzeugen-Menü (#719): Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure GenerateMenuOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TestSupport;

procedure TAtlasEditingSettingsTests.GenerateMenuOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.GenerateMenu, 'standardmäßig an');
  Assert.AreEqual($802D, mSettings.GenerateMenuKey, 'Alt+Einfg');
  Assert.AreEqual('generate,surround,templates', mSettings.GenerateMenuGroups);
  Assert.AreEqual('', mSettings.GenerateMenuHidden);
  Assert.IsTrue(mSettings.GenerateMenuRecentFirst);
  Assert.IsTrue(mSettings.GenerateMenuShowCommandNames);
  // Unbekannte Gruppen entfallen, Reihenfolge bleibt; Ausgeblendete ohne Leere und Doppelte.
  mSettings.GenerateMenuGroups := ' Templates; quatsch, generate ';
  mSettings.GenerateMenuHidden := '/json, , /json,tryf';
  mSettings.Normalize;
  Assert.AreEqual('templates,generate', mSettings.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', mSettings.GenerateMenuHidden);
  mSettings.GenerateMenuGroups := 'nichts';
  mSettings.Normalize;
  Assert.AreEqual('generate,surround,templates', mSettings.GenerateMenuGroups, 'ohne bekannte Gruppe: Vorgabe');
  // Speichern und Laden.
  mSettings.GenerateMenu := False;
  mSettings.GenerateMenuKey := 0;
  mSettings.GenerateMenuGroups := 'surround,generate';
  mSettings.GenerateMenuRecentFirst := False;
  mSettings.GenerateMenuShowCommandNames := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.GenerateMenu, 'abschaltbar');
  Assert.AreEqual(0, mLoaded.GenerateMenuKey, '0 = keine Taste');
  Assert.AreEqual('surround,generate', mLoaded.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', mLoaded.GenerateMenuHidden);
  Assert.IsFalse(mLoaded.GenerateMenuRecentFirst);
  Assert.IsFalse(mLoaded.GenerateMenuShowCommandNames);
end;
procedure TAtlasEditingSettingsTests.MoveLinesOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.MoveLines);
  Assert.AreEqual($8026, mSettings.MoveLinesUpKey, 'Alt+↑');
  Assert.AreEqual($8028, mSettings.MoveLinesDownKey, 'Alt+↓');
  Assert.AreEqual($A026, mSettings.DuplicateLinesUpKey, 'Umschalt+Alt+↑');
  Assert.AreEqual($A028, mSettings.DuplicateLinesDownKey, 'Umschalt+Alt+↓');
  mSettings.MoveLines := False;
  mSettings.MoveLinesUpKey := 0;
  mSettings.DuplicateLinesDownKey := $C044;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.MoveLines);
  Assert.AreEqual(0, mLoaded.MoveLinesUpKey);
  Assert.AreEqual($8028, mLoaded.MoveLinesDownKey);
  Assert.AreEqual($C044, mLoaded.DuplicateLinesDownKey);
  mLoaded.DuplicateLinesUpKey := $20000;
  mLoaded.Normalize;
  Assert.AreEqual($FFFF, mLoaded.DuplicateLinesUpKey);
end;
procedure TAtlasEditingSettingsTests.ContinueCommentsOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ContinueComments);
  Assert.IsTrue(mSettings.ContinueCommentsLineComments);
  Assert.IsTrue(mSettings.ContinueCommentsLists);
  Assert.AreEqual('', mSettings.ContinueCommentsBlockPrefix);
  mSettings.ContinueComments := False;
  mSettings.ContinueCommentsLists := False;
  mSettings.ContinueCommentsBlockPrefix := ' * ';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ContinueComments);
  Assert.IsTrue(mLoaded.ContinueCommentsLineComments);
  Assert.IsFalse(mLoaded.ContinueCommentsLists);
  // Leerraum am Rand bleibt.
  Assert.AreEqual(' * ', mLoaded.ContinueCommentsBlockPrefix);
  mLoaded.ContinueCommentsBlockPrefix := ' *'#9'1234567890';
  mLoaded.Normalize;
  Assert.AreEqual(' * 12345', mLoaded.ContinueCommentsBlockPrefix);
  mLoaded.ContinueCommentsBlockPrefix := '   ';
  mLoaded.Normalize;
  Assert.AreEqual('', mLoaded.ContinueCommentsBlockPrefix);
end;
procedure TAtlasEditingSettingsTests.CompleteStatementOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.CompleteStatement);
  Assert.AreEqual($600D, mSettings.CompleteStatementKey, 'Strg+Umschalt+Enter');
  Assert.AreEqual('multiLine', mSettings.CompleteStatementBeginEnd);
  Assert.AreEqual('finally', mSettings.CompleteStatementTryKind);
  Assert.IsTrue(mSettings.CompleteStatementMethodBody);
  mSettings.CompleteStatement := False;
  mSettings.CompleteStatementKey := 0;
  mSettings.CompleteStatementBeginEnd := 'always';
  mSettings.CompleteStatementTryKind := 'ask';
  mSettings.CompleteStatementMethodBody := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.CompleteStatement);
  Assert.AreEqual(0, mLoaded.CompleteStatementKey);
  Assert.AreEqual('always', mLoaded.CompleteStatementBeginEnd);
  Assert.AreEqual('ask', mLoaded.CompleteStatementTryKind);
  Assert.IsFalse(mLoaded.CompleteStatementMethodBody);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschreibung wird angeglichen.
  mLoaded.CompleteStatementBeginEnd := 'MULTILINE';
  mLoaded.CompleteStatementTryKind := 'irgendwas';
  mLoaded.Normalize;
  Assert.AreEqual('multiLine', mLoaded.CompleteStatementBeginEnd);
  Assert.AreEqual('finally', mLoaded.CompleteStatementTryKind);
end;
procedure TAtlasEditingSettingsTests.FormatCodeOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.FormatCode);
  Assert.AreEqual($E04C, mSettings.FormatCodeKey, 'Strg+Umschalt+Alt+L');
  mSettings.FormatCode := False;
  mSettings.FormatCodeKey := $C046;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.FormatCode);
  Assert.AreEqual($C046, mLoaded.FormatCodeKey);
  mLoaded.FormatCodeKey := -5;
  mLoaded.Normalize;
  Assert.AreEqual(0, mLoaded.FormatCodeKey);
end;
procedure TAtlasEditingSettingsTests.MultiCursorOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #589: experimentell, also aus; Klick mit Alt; Kürzel Strg+D, Alt+Umschalt+I, Strg+Alt+↑/↓.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.MultiCursor);
  // #658 ebenso experimentell.
  Assert.IsFalse(mSettings.LinkedEditing);
  Assert.AreEqual('alt', mSettings.MultiCursorModifier);
  Assert.AreEqual($4044, mSettings.MultiCursorNextKey, 'Strg+D');
  Assert.AreEqual($4044, mSettings.MultiCursorSkipKey, 'Strg+K, Strg+D');
  Assert.AreEqual($A049, mSettings.MultiCursorLineEndsKey, 'Alt+Umschalt+I');
  Assert.AreEqual($C026, mSettings.MultiCursorAboveKey, 'Strg+Alt+Hoch');
  Assert.AreEqual($C028, mSettings.MultiCursorBelowKey, 'Strg+Alt+Runter');
  mSettings.MultiCursor := True;
  mSettings.LinkedEditing := True;
  mSettings.MultiCursorModifier := 'ctrl';
  mSettings.MultiCursorNextKey := 0;
  mSettings.MultiCursorSkipKey := $4053;
  mSettings.MultiCursorLineEndsKey := $C049;
  mSettings.MultiCursorAboveKey := $A026;
  mSettings.MultiCursorBelowKey := $A028;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.MultiCursor);
  Assert.IsTrue(mLoaded.LinkedEditing);
  Assert.AreEqual('ctrl', mLoaded.MultiCursorModifier);
  Assert.AreEqual(0, mLoaded.MultiCursorNextKey);
  Assert.AreEqual($4053, mLoaded.MultiCursorSkipKey);
  Assert.AreEqual($C049, mLoaded.MultiCursorLineEndsKey);
  Assert.AreEqual($A026, mLoaded.MultiCursorAboveKey);
  Assert.AreEqual($A028, mLoaded.MultiCursorBelowKey);
  // Unbekannte Taste fällt auf alt zurück; Kürzel bleiben ein Word.
  mLoaded.MultiCursorModifier := 'shift';
  mLoaded.MultiCursorBelowKey := $1FFFF;
  mLoaded.Normalize;
  Assert.AreEqual('alt', mLoaded.MultiCursorModifier);
  Assert.AreEqual($FFFF, mLoaded.MultiCursorBelowKey);
  mLoaded.MultiCursorModifier := 'CTRL';
  mLoaded.Normalize;
  Assert.AreEqual('ctrl', mLoaded.MultiCursorModifier);
end;
procedure TAtlasEditingSettingsTests.SmartPasteOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #515: experimentell, also aus; vier Werte, Unbekanntes fällt auf off zurück.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('off', mSettings.SmartPaste);
  mSettings.SmartPaste := 'indent';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual('indent', mLoaded.SmartPaste);
  mLoaded.SmartPaste := 'BOTH';
  mLoaded.Normalize;
  Assert.AreEqual('both', mLoaded.SmartPaste);
  mLoaded.SmartPaste := 'immer';
  mLoaded.Normalize;
  Assert.AreEqual('off', mLoaded.SmartPaste);
end;
procedure TAtlasEditingSettingsTests.ContinuePatternOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ContinuePattern);
  Assert.AreEqual(2, mSettings.ContinuePatternMinLines);
  mSettings.ContinuePattern := False;
  mSettings.ContinuePatternMinLines := 4;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ContinuePattern);
  Assert.AreEqual(4, mLoaded.ContinuePatternMinLines);
  // Nur 2 bis 5 Zeilen.
  mLoaded.ContinuePatternMinLines := 1;
  mLoaded.Normalize;
  Assert.AreEqual(2, mLoaded.ContinuePatternMinLines);
  mLoaded.ContinuePatternMinLines := 9;
  mLoaded.Normalize;
  Assert.AreEqual(5, mLoaded.ContinuePatternMinLines);
end;
procedure TAtlasEditingSettingsTests.ToggleBlockCommentOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ToggleBlockComment);
  Assert.AreEqual($A041, mSettings.ToggleBlockCommentKey, 'Umschalt+Alt+A');
  Assert.AreEqual('braces', mSettings.ToggleBlockCommentStyle);
  Assert.AreEqual('lineComments', mSettings.ToggleBlockCommentFallback);
  Assert.IsFalse(mSettings.ToggleBlockCommentOwnLines);
  Assert.AreEqual('statement', mSettings.ToggleBlockCommentWithoutSelection);
  mSettings.ToggleBlockComment := False;
  mSettings.ToggleBlockCommentKey := 0;
  mSettings.ToggleBlockCommentStyle := 'parens';
  mSettings.ToggleBlockCommentFallback := 'refuse';
  mSettings.ToggleBlockCommentOwnLines := True;
  mSettings.ToggleBlockCommentWithoutSelection := 'line';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ToggleBlockComment);
  Assert.AreEqual(0, mLoaded.ToggleBlockCommentKey);
  Assert.AreEqual('parens', mLoaded.ToggleBlockCommentStyle);
  Assert.AreEqual('refuse', mLoaded.ToggleBlockCommentFallback);
  Assert.IsTrue(mLoaded.ToggleBlockCommentOwnLines);
  Assert.AreEqual('line', mLoaded.ToggleBlockCommentWithoutSelection);
  // Unbekannte Werte fallen auf die Vorgabe zurück.
  mLoaded.ToggleBlockCommentStyle := 'eckig';
  mLoaded.ToggleBlockCommentFallback := '';
  mLoaded.ToggleBlockCommentWithoutSelection := 'block';
  mLoaded.Normalize;
  Assert.AreEqual('braces', mLoaded.ToggleBlockCommentStyle);
  Assert.AreEqual('lineComments', mLoaded.ToggleBlockCommentFallback);
  Assert.AreEqual('statement', mLoaded.ToggleBlockCommentWithoutSelection);
end;
procedure TAtlasEditingSettingsTests.WrapSelectionOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.WrapSelection);
  Assert.AreEqual('([{''', mSettings.WrapSelectionChars);
  mSettings.WrapSelection := False;
  mSettings.WrapSelectionChars := '(<';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.WrapSelection);
  Assert.AreEqual('(<', mLoaded.WrapSelectionChars);
end;
procedure TAtlasEditingSettingsTests.NewLineAroundOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.NewLineAround);
  Assert.AreEqual($200D, mSettings.NewLineBelowKey, 'Umschalt+Enter');
  Assert.AreEqual($C00D, mSettings.NewLineAboveKey, 'Strg+Alt+Enter');
  Assert.IsTrue(mSettings.NewLineAroundStatementAware);
  mSettings.NewLineAround := False;
  mSettings.NewLineBelowKey := 0;
  mSettings.NewLineAboveKey := $600D;
  mSettings.NewLineAroundStatementAware := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.NewLineAround);
  Assert.AreEqual(0, mLoaded.NewLineBelowKey);
  Assert.AreEqual($600D, mLoaded.NewLineAboveKey);
  Assert.IsFalse(mLoaded.NewLineAroundStatementAware);
  mLoaded.NewLineBelowKey := -5;
  mLoaded.Normalize;
  Assert.AreEqual(0, mLoaded.NewLineBelowKey);
end;
procedure TAtlasEditingSettingsTests.MethodPlacementOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('grouped', mSettings.MethodPlacement, 'Vorgabe gruppiert (#1834)');
  mSettings.MethodPlacement := 'Declaration';
  mSettings.Normalize;
  Assert.AreEqual('declaration', mSettings.MethodPlacement);
  mSettings.MethodPlacement := 'Alphabetical';
  mSettings.Normalize;
  Assert.AreEqual('alphabetical', mSettings.MethodPlacement);
  mSettings.MethodPlacement := 'irgendwie';
  mSettings.Normalize;
  Assert.AreEqual('grouped', mSettings.MethodPlacement, 'Unbekanntes wird zur Vorgabe');
  mSettings.MethodPlacement := 'off';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual('off', mLoaded.MethodPlacement, 'abschaltbar');
end;
procedure TAtlasEditingSettingsTests.RegionFoldsOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('keep', mSettings.RegionFolds);
  mSettings.RegionFolds := 'Collapse';
  mSettings.Normalize;
  Assert.AreEqual('collapse', mSettings.RegionFolds);
  mSettings.RegionFolds := 'irgendwie';
  mSettings.Normalize;
  Assert.AreEqual('keep', mSettings.RegionFolds, 'Unbekanntes wird zur Vorgabe');
  mSettings.RegionFolds := 'off';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual('off', mLoaded.RegionFolds, 'abschaltbar');
end;
procedure TAtlasEditingSettingsTests.UnwrapOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Unwrap);
  Assert.AreEqual($602E, mSettings.UnwrapKey, 'Strg+Umschalt+Entf');
  mSettings.Unwrap := False;
  mSettings.UnwrapKey := $402E;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.Unwrap);
  Assert.AreEqual($402E, mLoaded.UnwrapKey);
  mLoaded.UnwrapKey := $1FFFF;
  mLoaded.Normalize;
  Assert.AreEqual($FFFF, mLoaded.UnwrapKey);
end;
procedure TAtlasEditingSettingsTests.SafeDeleteOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.SafeDelete);
  Assert.AreEqual($802E, mSettings.SafeDeleteKey, 'Alt+Entf');
  mSettings.SafeDelete := False;
  mSettings.SafeDeleteKey := $402E;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.SafeDelete);
  Assert.AreEqual($402E, mLoaded.SafeDeleteKey);
  mLoaded.SafeDeleteKey := -1;
  mLoaded.Normalize;
  Assert.AreEqual(0, mLoaded.SafeDeleteKey);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditingSettingsTests);

end.
