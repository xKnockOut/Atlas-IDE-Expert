unit Atlas.UI.Bookmarks.SettingsSection;

// Abschnitte des Moduls Lesezeichen im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher in den Teilen
// „Editor“ und „Befehle“ von Base).
// - „Editor“: Modulschalter, Notizen an Codezeilen (#545), benannte Lesezeichen (#622) und schnelle Lesezeichen
//   (#1104). Alle Elemente bindet die Seite; die Grenzen der Akkord-Wartezeit setzt TAtlasPluginSettings.Normalize.
// - „Befehle“: Tasten „Lesezeichen setzen…“ (#622) und nächstes/voriges Lesezeichen (#1104).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasBookmarksEditorSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

  TAtlasBookmarksKeysSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

const
  cBookmarksSettingsOwner = 'atlas.bookmarks';

implementation

uses
  Atlas.Core.Settings.Plugin.Store,
  Atlas.UI.Strings,
  Atlas.UI.Bookmarks.Strings;

{ TAtlasBookmarksEditorSection }

function TAtlasBookmarksEditorSection.OwnerId: string;
begin
  Result := cBookmarksSettingsOwner;
end;

function TAtlasBookmarksEditorSection.AreaId: string;
begin
  Result := 'Editor';
end;

procedure TAtlasBookmarksEditorSection.BuildRows;
var
  mScopes: TArray<string>;
  mScope: string;
begin
  ModuleSwitch('bookmarks.enabled');
  Switch('notes.enabled', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsNotes));
  // Benannte Lesezeichen: Funktion und Ablage für das Team; die Taste steht bei den Befehlen.
  Switch('bookmarks.named', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsBookmarksNamed));
  Switch('bookmarks.shared', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsBookmarksShared));
  // Schnelle Lesezeichen: Spalte, Tasten, Akkord-Wartezeit, Sprungbereich, Übernahme der IDE-Lesezeichen.
  Switch('bookmarks.quick', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarks));
  Switch('bookmarks.quick.gutter', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksGutter));
  Switch('bookmarks.quick.gutterClick',
    TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksGutterClick));
  Switch('bookmarks.quick.numberedKeys',
    TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksNumberedKeys));
  Key('bookmarks.quick.key', TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand));
  Number('bookmarks.quick.chordWait', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarkChordWait));
  // Reihenfolge wie AtlasQuickBookmarkScopes.
  mScopes := nil;
  for mScope in AtlasQuickBookmarkScopes do
  begin
    mScopes := mScopes + [mScope];
  end;
  Choice('bookmarks.quick.scope', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksScope),
    [TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksScopeProject),
    TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksScopeFile)], mScopes);
  Switch('bookmarks.quick.importIde', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.SettingsQuickBookmarksImportIde));
end;

{ TAtlasBookmarksKeysSection }

function TAtlasBookmarksKeysSection.OwnerId: string;
begin
  Result := cBookmarksSettingsOwner;
end;

function TAtlasBookmarksKeysSection.AreaId: string;
begin
  Result := 'Befehle';
end;

procedure TAtlasBookmarksKeysSection.BuildRows;
begin
  Key('bookmarks.key', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd));
  // Nächstes/voriges Lesezeichen, ohne Vorgabe.
  Key('keys.nextBookmark', TAtlasStrings.Text(TAtlasTextId.NextBookmarkCommand));
  Key('keys.previousBookmark', TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand));
end;

end.
