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
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GenerateMenu, 'standardmäßig an');
  Assert.AreEqual($802D, Settings.GenerateMenuKey, 'Alt+Einfg');
  Assert.AreEqual('generate,surround,templates', Settings.GenerateMenuGroups);
  Assert.AreEqual('', Settings.GenerateMenuHidden);
  Assert.IsTrue(Settings.GenerateMenuRecentFirst);
  Assert.IsTrue(Settings.GenerateMenuShowCommandNames);
  // Unbekannte Gruppen entfallen, Reihenfolge bleibt; Ausgeblendete ohne Leere und Doppelte.
  Settings.GenerateMenuGroups := ' Templates; quatsch, generate ';
  Settings.GenerateMenuHidden := '/json, , /json,tryf';
  Settings.Normalize;
  Assert.AreEqual('templates,generate', Settings.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', Settings.GenerateMenuHidden);
  Settings.GenerateMenuGroups := 'nichts';
  Settings.Normalize;
  Assert.AreEqual('generate,surround,templates', Settings.GenerateMenuGroups, 'ohne bekannte Gruppe: Vorgabe');
  // Speichern und Laden.
  Settings.GenerateMenu := False;
  Settings.GenerateMenuKey := 0;
  Settings.GenerateMenuGroups := 'surround,generate';
  Settings.GenerateMenuRecentFirst := False;
  Settings.GenerateMenuShowCommandNames := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GenerateMenu, 'abschaltbar');
  Assert.AreEqual(0, Loaded.GenerateMenuKey, '0 = keine Taste');
  Assert.AreEqual('surround,generate', Loaded.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', Loaded.GenerateMenuHidden);
  Assert.IsFalse(Loaded.GenerateMenuRecentFirst);
  Assert.IsFalse(Loaded.GenerateMenuShowCommandNames);
end;
procedure TAtlasEditingSettingsTests.MoveLinesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.MoveLines);
  Assert.AreEqual($8026, Settings.MoveLinesUpKey, 'Alt+↑');
  Assert.AreEqual($8028, Settings.MoveLinesDownKey, 'Alt+↓');
  Assert.AreEqual($A026, Settings.DuplicateLinesUpKey, 'Umschalt+Alt+↑');
  Assert.AreEqual($A028, Settings.DuplicateLinesDownKey, 'Umschalt+Alt+↓');
  Settings.MoveLines := False;
  Settings.MoveLinesUpKey := 0;
  Settings.DuplicateLinesDownKey := $C044;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.MoveLines);
  Assert.AreEqual(0, Loaded.MoveLinesUpKey);
  Assert.AreEqual($8028, Loaded.MoveLinesDownKey);
  Assert.AreEqual($C044, Loaded.DuplicateLinesDownKey);
  Loaded.DuplicateLinesUpKey := $20000;
  Loaded.Normalize;
  Assert.AreEqual($FFFF, Loaded.DuplicateLinesUpKey);
end;
procedure TAtlasEditingSettingsTests.ContinueCommentsOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ContinueComments);
  Assert.IsTrue(Settings.ContinueCommentsLineComments);
  Assert.IsTrue(Settings.ContinueCommentsLists);
  Assert.AreEqual('', Settings.ContinueCommentsBlockPrefix);
  Settings.ContinueComments := False;
  Settings.ContinueCommentsLists := False;
  Settings.ContinueCommentsBlockPrefix := ' * ';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ContinueComments);
  Assert.IsTrue(Loaded.ContinueCommentsLineComments);
  Assert.IsFalse(Loaded.ContinueCommentsLists);
  // Leerraum am Rand bleibt.
  Assert.AreEqual(' * ', Loaded.ContinueCommentsBlockPrefix);
  Loaded.ContinueCommentsBlockPrefix := ' *'#9'1234567890';
  Loaded.Normalize;
  Assert.AreEqual(' * 12345', Loaded.ContinueCommentsBlockPrefix);
  Loaded.ContinueCommentsBlockPrefix := '   ';
  Loaded.Normalize;
  Assert.AreEqual('', Loaded.ContinueCommentsBlockPrefix);
end;
procedure TAtlasEditingSettingsTests.CompleteStatementOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CompleteStatement);
  Assert.AreEqual($600D, Settings.CompleteStatementKey, 'Strg+Umschalt+Enter');
  Assert.AreEqual('multiLine', Settings.CompleteStatementBeginEnd);
  Assert.AreEqual('finally', Settings.CompleteStatementTryKind);
  Assert.IsTrue(Settings.CompleteStatementMethodBody);
  Settings.CompleteStatement := False;
  Settings.CompleteStatementKey := 0;
  Settings.CompleteStatementBeginEnd := 'always';
  Settings.CompleteStatementTryKind := 'ask';
  Settings.CompleteStatementMethodBody := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CompleteStatement);
  Assert.AreEqual(0, Loaded.CompleteStatementKey);
  Assert.AreEqual('always', Loaded.CompleteStatementBeginEnd);
  Assert.AreEqual('ask', Loaded.CompleteStatementTryKind);
  Assert.IsFalse(Loaded.CompleteStatementMethodBody);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschreibung wird angeglichen.
  Loaded.CompleteStatementBeginEnd := 'MULTILINE';
  Loaded.CompleteStatementTryKind := 'irgendwas';
  Loaded.Normalize;
  Assert.AreEqual('multiLine', Loaded.CompleteStatementBeginEnd);
  Assert.AreEqual('finally', Loaded.CompleteStatementTryKind);
end;
procedure TAtlasEditingSettingsTests.FormatCodeOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.FormatCode);
  Assert.AreEqual($E04C, Settings.FormatCodeKey, 'Strg+Umschalt+Alt+L');
  Settings.FormatCode := False;
  Settings.FormatCodeKey := $C046;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.FormatCode);
  Assert.AreEqual($C046, Loaded.FormatCodeKey);
  Loaded.FormatCodeKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.FormatCodeKey);
end;
procedure TAtlasEditingSettingsTests.MultiCursorOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #589: experimentell, also aus; Klick mit Alt; Kürzel Strg+D, Alt+Umschalt+I, Strg+Alt+↑/↓.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.MultiCursor);
  // #658 ebenso experimentell.
  Assert.IsFalse(Settings.LinkedEditing);
  Assert.AreEqual('alt', Settings.MultiCursorModifier);
  Assert.AreEqual($4044, Settings.MultiCursorNextKey, 'Strg+D');
  Assert.AreEqual($4044, Settings.MultiCursorSkipKey, 'Strg+K, Strg+D');
  Assert.AreEqual($A049, Settings.MultiCursorLineEndsKey, 'Alt+Umschalt+I');
  Assert.AreEqual($C026, Settings.MultiCursorAboveKey, 'Strg+Alt+Hoch');
  Assert.AreEqual($C028, Settings.MultiCursorBelowKey, 'Strg+Alt+Runter');
  Settings.MultiCursor := True;
  Settings.LinkedEditing := True;
  Settings.MultiCursorModifier := 'ctrl';
  Settings.MultiCursorNextKey := 0;
  Settings.MultiCursorSkipKey := $4053;
  Settings.MultiCursorLineEndsKey := $C049;
  Settings.MultiCursorAboveKey := $A026;
  Settings.MultiCursorBelowKey := $A028;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.MultiCursor);
  Assert.IsTrue(Loaded.LinkedEditing);
  Assert.AreEqual('ctrl', Loaded.MultiCursorModifier);
  Assert.AreEqual(0, Loaded.MultiCursorNextKey);
  Assert.AreEqual($4053, Loaded.MultiCursorSkipKey);
  Assert.AreEqual($C049, Loaded.MultiCursorLineEndsKey);
  Assert.AreEqual($A026, Loaded.MultiCursorAboveKey);
  Assert.AreEqual($A028, Loaded.MultiCursorBelowKey);
  // Unbekannte Taste fällt auf alt zurück; Kürzel bleiben ein Word.
  Loaded.MultiCursorModifier := 'shift';
  Loaded.MultiCursorBelowKey := $1FFFF;
  Loaded.Normalize;
  Assert.AreEqual('alt', Loaded.MultiCursorModifier);
  Assert.AreEqual($FFFF, Loaded.MultiCursorBelowKey);
  Loaded.MultiCursorModifier := 'CTRL';
  Loaded.Normalize;
  Assert.AreEqual('ctrl', Loaded.MultiCursorModifier);
end;
procedure TAtlasEditingSettingsTests.SmartPasteOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #515: experimentell, also aus; vier Werte, Unbekanntes fällt auf off zurück.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('off', Settings.SmartPaste);
  Settings.SmartPaste := 'indent';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('indent', Loaded.SmartPaste);
  Loaded.SmartPaste := 'BOTH';
  Loaded.Normalize;
  Assert.AreEqual('both', Loaded.SmartPaste);
  Loaded.SmartPaste := 'immer';
  Loaded.Normalize;
  Assert.AreEqual('off', Loaded.SmartPaste);
end;
procedure TAtlasEditingSettingsTests.ContinuePatternOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ContinuePattern);
  Assert.AreEqual(2, Settings.ContinuePatternMinLines);
  Settings.ContinuePattern := False;
  Settings.ContinuePatternMinLines := 4;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ContinuePattern);
  Assert.AreEqual(4, Loaded.ContinuePatternMinLines);
  // Nur 2 bis 5 Zeilen.
  Loaded.ContinuePatternMinLines := 1;
  Loaded.Normalize;
  Assert.AreEqual(2, Loaded.ContinuePatternMinLines);
  Loaded.ContinuePatternMinLines := 9;
  Loaded.Normalize;
  Assert.AreEqual(5, Loaded.ContinuePatternMinLines);
end;
procedure TAtlasEditingSettingsTests.ToggleBlockCommentOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ToggleBlockComment);
  Assert.AreEqual($A041, Settings.ToggleBlockCommentKey, 'Umschalt+Alt+A');
  Assert.AreEqual('braces', Settings.ToggleBlockCommentStyle);
  Assert.AreEqual('lineComments', Settings.ToggleBlockCommentFallback);
  Assert.IsFalse(Settings.ToggleBlockCommentOwnLines);
  Assert.AreEqual('statement', Settings.ToggleBlockCommentWithoutSelection);
  Settings.ToggleBlockComment := False;
  Settings.ToggleBlockCommentKey := 0;
  Settings.ToggleBlockCommentStyle := 'parens';
  Settings.ToggleBlockCommentFallback := 'refuse';
  Settings.ToggleBlockCommentOwnLines := True;
  Settings.ToggleBlockCommentWithoutSelection := 'line';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ToggleBlockComment);
  Assert.AreEqual(0, Loaded.ToggleBlockCommentKey);
  Assert.AreEqual('parens', Loaded.ToggleBlockCommentStyle);
  Assert.AreEqual('refuse', Loaded.ToggleBlockCommentFallback);
  Assert.IsTrue(Loaded.ToggleBlockCommentOwnLines);
  Assert.AreEqual('line', Loaded.ToggleBlockCommentWithoutSelection);
  // Unbekannte Werte fallen auf die Vorgabe zurück.
  Loaded.ToggleBlockCommentStyle := 'eckig';
  Loaded.ToggleBlockCommentFallback := '';
  Loaded.ToggleBlockCommentWithoutSelection := 'block';
  Loaded.Normalize;
  Assert.AreEqual('braces', Loaded.ToggleBlockCommentStyle);
  Assert.AreEqual('lineComments', Loaded.ToggleBlockCommentFallback);
  Assert.AreEqual('statement', Loaded.ToggleBlockCommentWithoutSelection);
end;
procedure TAtlasEditingSettingsTests.WrapSelectionOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WrapSelection);
  Assert.AreEqual('([{''', Settings.WrapSelectionChars);
  Settings.WrapSelection := False;
  Settings.WrapSelectionChars := '(<';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WrapSelection);
  Assert.AreEqual('(<', Loaded.WrapSelectionChars);
end;
procedure TAtlasEditingSettingsTests.NewLineAroundOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.NewLineAround);
  Assert.AreEqual($200D, Settings.NewLineBelowKey, 'Umschalt+Enter');
  Assert.AreEqual($C00D, Settings.NewLineAboveKey, 'Strg+Alt+Enter');
  Assert.IsTrue(Settings.NewLineAroundStatementAware);
  Settings.NewLineAround := False;
  Settings.NewLineBelowKey := 0;
  Settings.NewLineAboveKey := $600D;
  Settings.NewLineAroundStatementAware := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.NewLineAround);
  Assert.AreEqual(0, Loaded.NewLineBelowKey);
  Assert.AreEqual($600D, Loaded.NewLineAboveKey);
  Assert.IsFalse(Loaded.NewLineAroundStatementAware);
  Loaded.NewLineBelowKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.NewLineBelowKey);
end;
procedure TAtlasEditingSettingsTests.MethodPlacementOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('grouped', Settings.MethodPlacement, 'Vorgabe gruppiert (#1834)');
  Settings.MethodPlacement := 'Declaration';
  Settings.Normalize;
  Assert.AreEqual('declaration', Settings.MethodPlacement);
  Settings.MethodPlacement := 'Alphabetical';
  Settings.Normalize;
  Assert.AreEqual('alphabetical', Settings.MethodPlacement);
  Settings.MethodPlacement := 'irgendwie';
  Settings.Normalize;
  Assert.AreEqual('grouped', Settings.MethodPlacement, 'Unbekanntes wird zur Vorgabe');
  Settings.MethodPlacement := 'off';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('off', Loaded.MethodPlacement, 'abschaltbar');
end;
procedure TAtlasEditingSettingsTests.RegionFoldsOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('keep', Settings.RegionFolds);
  Settings.RegionFolds := 'Collapse';
  Settings.Normalize;
  Assert.AreEqual('collapse', Settings.RegionFolds);
  Settings.RegionFolds := 'irgendwie';
  Settings.Normalize;
  Assert.AreEqual('keep', Settings.RegionFolds, 'Unbekanntes wird zur Vorgabe');
  Settings.RegionFolds := 'off';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('off', Loaded.RegionFolds, 'abschaltbar');
end;
procedure TAtlasEditingSettingsTests.UnwrapOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Unwrap);
  Assert.AreEqual($602E, Settings.UnwrapKey, 'Strg+Umschalt+Entf');
  Settings.Unwrap := False;
  Settings.UnwrapKey := $402E;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Unwrap);
  Assert.AreEqual($402E, Loaded.UnwrapKey);
  Loaded.UnwrapKey := $1FFFF;
  Loaded.Normalize;
  Assert.AreEqual($FFFF, Loaded.UnwrapKey);
end;
procedure TAtlasEditingSettingsTests.SafeDeleteOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.SafeDelete);
  Assert.AreEqual($802E, Settings.SafeDeleteKey, 'Alt+Entf');
  Settings.SafeDelete := False;
  Settings.SafeDeleteKey := $402E;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.SafeDelete);
  Assert.AreEqual($402E, Loaded.SafeDeleteKey);
  Loaded.SafeDeleteKey := -1;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.SafeDeleteKey);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditingSettingsTests);

end.
