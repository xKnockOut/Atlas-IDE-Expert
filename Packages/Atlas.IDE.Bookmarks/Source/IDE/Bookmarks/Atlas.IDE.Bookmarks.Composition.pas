unit Atlas.IDE.Bookmarks.Composition;

// Modul Lesezeichen (#1455, ADR 0017): einzige Unit, die persönliche
// Notizen (#545), benannte (#622) und schnelle Lesezeichen (#1104) sowie
// die TODO-Liste des Projekts (#68) erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.bookmarks“ (Modulschalter bookmarks,
// #1454) bei der Registry von Base an und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (Notes, Bookmarks, QuickBookmarks),
// - Befehle (Palette), Einträge im Atlas-Menü (Untermenü „Notizen und
//   Lesezeichen“) und im Kontextmenü des Editors, die Tasten der
//   Lesezeichen (Strg+Alt+K, Strg+Umschalt+1…9, Strg+1…9, Strg+Umschalt+K
//   als Akkord, nächstes/voriges),
// - die Schichten der Rinne (IAtlasGutterLayer) und die eigenen Lesezeichen
//   der Übersichtsleiste (IAtlasOverviewBookmarks),
// - Hörer für Einstellungen und Thema.
// Die TODO-Liste (Atlas.IDE.Bookmarks.Composition.Todos) fragt den Server
// über TAtlasIdeHost; seine Antwort erreicht das Modul nur, solange es
// angemeldet ist (Regel 3).
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Editor.Overview;

type
  TAtlasBookmarksModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasOverviewBookmarks)
  public const
    cModuleId = 'atlas.bookmarks';
    cSwitch = 'bookmarks';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
    function Marks(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Bookmarks.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Bookmarks.Quick,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Notes.Gutter,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.QuickService,
  Atlas.IDE.Bookmarks.Gutter,
  Atlas.IDE.Bookmarks.QuickColumn,
  Atlas.IDE.Bookmarks.QuickChord,
  Atlas.IDE.Bookmarks.SavedPlaces,
  Atlas.IDE.Bookmarks.Composition.Todos,
  Atlas.Core.SavedPlaces.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Bookmarks.Strings;

const
  /// <summary>Feld der schnellen Lesezeichen im Atlas-Statusfeld (#1104).</summary>
  cQuickBookmarksExtra = 'quickBookmarks';

var
  GScope: IAtlasModuleScope;
  GNotesStarted: Boolean;
  GBookmarksStarted: Boolean;
  GQuickColumn: TAtlasIdeQuickColumn;

{ Dienste von Base }

procedure MessageLine(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

procedure QuickStatus(AText: string);
begin
  TAtlasIdeHost.SetStatusExtra(cQuickBookmarksExtra, AText);
end;

{ Sichtbarkeit und Bedingungen }

function NotesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Notes;
end;

function BookmarksNamedVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed;
end;

function QuickBookmarksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.QuickBookmarks;
end;

function BookmarksWindowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed or TAtlasIdeSettings.Current.QuickBookmarks;
end;

function TodoListVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TodoList;
end;

/// <summary>Taste von „Lesezeichen setzen…“ (#622); 0, solange bookmarks.named aus ist.</summary>
function BookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.BookmarksNamed then
  begin
    Result := TAtlasIdeSettings.Current.BookmarkKey;
  end;
end;

/// <summary>Akkord der schnellen Lesezeichen (#1104); 0, solange sie aus sind oder die Wartezeit 0 ist (dann bleibt
/// Strg+Umschalt+K bei der IDE).</summary>
function QuickBookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.QuickBookmarks and (TAtlasIdeSettings.Current.QuickBookmarkChordWait > 0) then
  begin
    Result := TAtlasIdeSettings.Current.QuickBookmarkKey;
  end;
end;

function NextBookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.QuickBookmarks then
  begin
    Result := TAtlasIdeSettings.Current.NextBookmarkKey;
  end;
end;

function PreviousBookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.QuickBookmarks then
  begin
    Result := TAtlasIdeSettings.Current.PreviousBookmarkKey;
  end;
end;

{ Start der Teile (aus der Kompositionswurzel hierher gezogen, #1455) }

procedure StartNotes;
begin
  TAtlasIdeNotes.Start(MessageLine);
  GNotesStarted := True;
end;

procedure StopNotes;
begin
  GNotesStarted := False;
  TAtlasIdeNotes.Release;
end;

function NotesStarted: Boolean;
begin
  Result := GNotesStarted;
end;

procedure StartBookmarks;
begin
  // Hinweise der schnellen Lesezeichen (#1104) im Statusfeld.
  TAtlasIdeBookmarks.Start(MessageLine, QuickStatus);
  GBookmarksStarted := True;
end;

procedure StopBookmarks;
begin
  GBookmarksStarted := False;
  TAtlasIdeBookmarks.Release;
  QuickStatus('');
end;

function BookmarksStarted: Boolean;
begin
  Result := GBookmarksStarted;
end;

procedure StartQuickColumn;
begin
  GQuickColumn := TAtlasIdeQuickColumn.Create;
end;

procedure StopQuickColumn;
begin
  TAtlasIdeQuickChord.Release;
  FreeAndNil(GQuickColumn);
end;

function QuickColumnStarted: Boolean;
begin
  Result := GQuickColumn <> nil;
end;

{ TODO-Liste des Projekts (#68) }

procedure AllTodos;
begin
  AllProjectTodos(GScope);
end;

procedure FilterTodos;
begin
  FilterProjectTodos(GScope);
end;

{ Befehle }

/// <summary>Befehl abgesichert ausführen (#493): eine Ausnahme schaltet nur AFeature ab.</summary>
function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(AFeature, AProc);
    end;
end;

function Command(AFeature: TAtlasFeature; const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := Guarded(AFeature, ARun);
  Result.Visible := AVisible;
end;

/// <summary>Wie Command, mit Tastenkürzel zur Anzeige. Eigener Name statt Überladung: anonyme Methoden als
/// Argument vertragen keine Überladungen.</summary>
function CommandWithKey(AFeature: TAtlasFeature; const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>; const AKey: TFunc<Integer>): TAtlasModuleCommand;
begin
  Result := Command(AFeature, AId, ACaption, ARun, AVisible);
  Result.Key := AKey;
end;

{ Tasten }

function ModuleKey(const AId: string; const ACaption: string; AKey: Integer; APriority: TAtlasKeyPriority;
  const ARun: TProc): TAtlasModuleKey;
begin
  Result := Default(TAtlasModuleKey);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Key := AKey;
  Result.Priority := APriority;
  Result.Run := ARun;
end;

function PriorityOf(ATake: Boolean): TAtlasKeyPriority;
begin
  Result := TAtlasKeyPriority.Yield;
  if ATake then
  begin
    Result := TAtlasKeyPriority.Take;
  end;
end;

/// <summary>Befehl für Nummer ANumber: eigene Funktion, damit jede anonyme Methode ihre Nummer behält.</summary>
function NumberProc(ANumber: Integer; AJump: Boolean): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
        procedure
        begin
          if AJump then
          begin
            TAtlasIdeQuickBookmarks.QuickJump(ANumber);
          end
          else
          begin
            TAtlasIdeQuickBookmarks.QuickSetNumber(ANumber);
          end;
        end);
    end;
end;

/// <summary>Strg+Umschalt+1…9 bzw. Strg+1…9 aus der Grundtaste ABase (#1104); Ids
/// Atlas.QuickBookmarkSet1…9 bzw. Atlas.QuickBookmarkJump1…9.</summary>
function NumberKeys(ABase: Integer; ATake, AJump: Boolean): TArray<TAtlasModuleKey>;
var
  mNumber: Integer;
  mKey: Word;
  mId, mWhat: string;
begin
  Result := nil;
  for mNumber := 1 to TAtlasQuickBookmarks.cMaxNumber do
  begin
    mKey := TAtlasQuickBookmarks.KeyFor(Word(ABase), mNumber);
    if mKey = 0 then
    begin
      Exit;
    end;
    if AJump then
    begin
      mId := 'Atlas.QuickBookmarkJump' + IntToStr(mNumber);
      mWhat := TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkJumpN, [mNumber]);
    end
    else
    begin
      mId := 'Atlas.QuickBookmarkSet' + IntToStr(mNumber);
      mWhat := TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkSetN, [mNumber]);
    end;
    Result := Result + [ModuleKey(mId, mWhat, mKey, PriorityOf(ATake), NumberProc(mNumber, AJump))];
  end;
end;

function QuickChordPressed: Boolean;
begin
  Result := TAtlasIdeQuickChord.Pressed;
end;

{ TAtlasBookmarksModule }

function TAtlasBookmarksModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Lesezeichen';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Notizen und benannte Lesezeichen gab es schon im abgesicherten Start (nur lokale Dateien).
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
end;

procedure TAtlasBookmarksModule.Start;
begin
  FActive := True;
end;

procedure TAtlasBookmarksModule.Stop;
begin
  FActive := False;
end;

function TAtlasBookmarksModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasBookmarksModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Persönliche Notizen (#545); nur sichtbar, solange notes.enabled an ist. Nach Rechtsklick in die Rinne für
    // die angeklickte Zeile, sonst für den Cursor.
    Command(TAtlasFeature.Notes, 'Atlas.NoteAdd', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesMenuAdd),
      TAtlasIdeNotes.AddOrEdit,
      NotesVisible),
    Command(TAtlasFeature.Notes, 'Atlas.NoteDelete',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesMenuDelete), TAtlasIdeNotes.DeleteAtLine,
      NotesVisible),
    Command(TAtlasFeature.Notes, 'Atlas.NoteList', TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesMenuList),
      TAtlasIdeNotes.ShowList,
      NotesVisible),
    // Benannte Lesezeichen (#622); nur sichtbar, solange bookmarks.named an ist, das Fenster auch mit
    // bookmarks.quick.
    CommandWithKey(TAtlasFeature.Bookmarks, 'Atlas.BookmarkAdd', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
      TAtlasIdeBookmarks.AddBookmark, BookmarksNamedVisible, BookmarkKey),
    Command(TAtlasFeature.Bookmarks, 'Atlas.BookmarkGoTo',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksMenuGoTo),
      TAtlasIdeBookmarks.GoToBookmark, BookmarksNamedVisible),
    Command(TAtlasFeature.Bookmarks, 'Atlas.BookmarkWindow',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksMenuWindow),
      TAtlasIdeBookmarks.ShowWindow, BookmarksWindowVisible),
    // Schnelle Lesezeichen (#1104); nur sichtbar, solange bookmarks.quick an ist.
    CommandWithKey(TAtlasFeature.QuickBookmarks, 'Atlas.QuickBookmarkToggle',
      TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand), TAtlasIdeQuickBookmarks.QuickToggle,
        QuickBookmarksVisible,
      QuickBookmarkKey),
    CommandWithKey(TAtlasFeature.QuickBookmarks, 'Atlas.NextBookmark',
      TAtlasStrings.Text(TAtlasTextId.NextBookmarkCommand),
      TAtlasIdeQuickBookmarks.NextBookmark, QuickBookmarksVisible, NextBookmarkKey),
    CommandWithKey(TAtlasFeature.QuickBookmarks, 'Atlas.PreviousBookmark',
      TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand),
      TAtlasIdeQuickBookmarks.PreviousBookmark, QuickBookmarksVisible, PreviousBookmarkKey),
    // TODO-Liste des Projekts (#68): ohne Filter (alle offenen) und mit Filterdialog; nur sichtbar, solange die
    // Einstellung TodoList an ist.
    Command(TAtlasFeature.Palette, 'Atlas.TodoList',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListCommand), AllTodos,
      TodoListVisible),
    Command(TAtlasFeature.Palette, 'Atlas.TodoListFilter',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterCommand), FilterTodos,
      TodoListVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Eintrag im Untermenü „Notizen und Lesezeichen“ des Atlas-Menüs.</summary>
function NotesMenuEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.AtlasMenu);
  Result.Section := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.MenuGroupNotes);
end;

/// <summary>Eintrag im gleichnamigen Untermenü von Atlas im Kontextmenü des Editors.</summary>
function NotesContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := NotesMenuEntry(ACommandId);
  Result.Place := TAtlasMenuPlace.EditorContext;
end;

function TAtlasBookmarksModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    // Atlas-Menü: Notizen (#545), Trennlinie, benannte (#622) und schnelle Lesezeichen (#1104).
    NotesMenuEntry('Atlas.NoteAdd'),
    NotesMenuEntry('Atlas.NoteDelete'),
    NotesMenuEntry('Atlas.NoteList'),
    NotesMenuEntry('-'),
    NotesMenuEntry('Atlas.BookmarkAdd'),
    NotesMenuEntry('Atlas.BookmarkGoTo'),
    NotesMenuEntry('Atlas.BookmarkWindow'),
    NotesMenuEntry('Atlas.QuickBookmarkToggle'),
    NotesMenuEntry('Atlas.NextBookmark'),
    NotesMenuEntry('Atlas.PreviousBookmark'),
    // Kontextmenü des Editors: nach Rechtsklick in die Rinne für die angeklickte Zeile, sonst für den Cursor; die
    // Spalte der schnellen Lesezeichen hat ihr eigenes Menü. Eigenes Untermenü, sonst wird das Kontextmenü höher
    // als der Bildschirm.
    NotesContextEntry('Atlas.NoteAdd'),
    NotesContextEntry('Atlas.NoteDelete'),
    NotesContextEntry('Atlas.NoteList'),
    NotesContextEntry('-'),
    NotesContextEntry('Atlas.BookmarkAdd'),
    NotesContextEntry('Atlas.BookmarkGoTo'),
    NotesContextEntry('Atlas.QuickBookmarkToggle')];
end;

function TAtlasBookmarksModule.Keys: TArray<TAtlasModuleKey>;
var
  mSettings: TAtlasPluginSettings;
  mChord: TAtlasModuleKey;
begin
  Result := nil;
  mSettings := TAtlasIdeSettings.Current;
  // Benannte Lesezeichen (#622): aus = keine Taste, die IDE-Lesezeichen bleiben unberührt.
  if mSettings.BookmarksNamed then
  begin
    Result := Result + [ModuleKey('Atlas.BookmarkAdd', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
      mSettings.BookmarkKey, TAtlasKeyPriority.Shared,
      Guarded(TAtlasFeature.Bookmarks, TAtlasIdeBookmarks.AddBookmark))];
  end;
  // Schnelle Lesezeichen (#1104): aus = alle Tasten gehören wieder der IDE.
  if not mSettings.QuickBookmarks then
  begin
    Exit;
  end;
  if mSettings.QuickBookmarksNumberedKeys then
  begin
    Result := Result + NumberKeys(mSettings.QuickBookmarkSetKey, mSettings.QuickBookmarkSetKeyPriority, False) +
      NumberKeys(mSettings.QuickBookmarkJumpKey, mSettings.QuickBookmarkJumpKeyPriority, True);
  end;
  // Wartezeit 0: Strg+Umschalt+K bleibt bei der IDE. Erster Teil neben den Faltungsakkorden der IDE, mit Rückfall
  // an die IDE für den selbst weitergereichten Akkord (TAtlasIdeQuickChord).
  if mSettings.QuickBookmarkChordWait > 0 then
  begin
    mChord := ModuleKey('Atlas.QuickBookmarkToggle', TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand),
      mSettings.QuickBookmarkKey, PriorityOf(mSettings.QuickBookmarkKeyPriority), nil);
    mChord.Attempt :=
      function: Boolean
      begin
        Result := QuickChordPressed;
      end;
    Result := Result + [mChord];
  end;
  Result := Result + [
    ModuleKey('Atlas.NextBookmark', TAtlasStrings.Text(TAtlasTextId.NextBookmarkCommand), mSettings.NextBookmarkKey,
      TAtlasKeyPriority.Shared, Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeQuickBookmarks.NextBookmark)),
    ModuleKey('Atlas.PreviousBookmark', TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand),
      mSettings.PreviousBookmarkKey, TAtlasKeyPriority.Shared,
      Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeQuickBookmarks.PreviousBookmark))];
end;

procedure TAtlasBookmarksModule.ApplySettings;
begin
  // bookmarks.named und bookmarks.shared (#622).
  TAtlasIdeBookmarks.ApplySettings;
  // bookmarks.quick aus: ein halb gedrückter Akkord gehört wieder der IDE (#1104).
  if not TAtlasIdeSettings.Current.QuickBookmarks then
  begin
    TAtlasIdeQuickChord.Release;
  end;
end;

procedure TAtlasBookmarksModule.ThemeChanged;
begin
  TAtlasIdeBookmarks.ThemeChanged;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasBookmarksEditorSection.ProvideIn(GScope);
  TAtlasBookmarksKeysSection.ProvideIn(GScope);
end;

function TAtlasBookmarksModule.Marks(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;
var
  mMarks: TArray<TAtlasBookmark>;
  mMark: TAtlasBookmark;
begin
  // Mit schnellen Lesezeichen (#1104) zeigt die Art „bookmarks“ der Übersichtsleiste die Lesezeichen von Atlas.
  AMarks := nil;
  Result := GBookmarksStarted and TAtlasIdeQuickBookmarks.OverviewMarks(AFileName, mMarks);
  if Result then
  begin
    for mMark in mMarks do
    begin
      AMarks := AMarks + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, mMark.Line, 1,
        mMark.DisplayName)];
    end;
  end;
end;

class function TAtlasBookmarksModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Persönliche Notizen (#545): Befehle auch abgesichert (nur lokale Dateien).
    TAtlasFeaturePart.AtLevel('Notes', TAtlasSafeLevel.Safe, NotesStarted, StartNotes, StopNotes),
    // Benannte Lesezeichen (#622): Befehle auch abgesichert; die Rinne teilt sich die Zeichenschicht mit den
    // Notizen, jede Schicht folgt ihrer Einstellung.
    TAtlasFeaturePart.AtLevel('Bookmarks', TAtlasSafeLevel.Safe, BookmarksStarted, StartBookmarks, StopBookmarks),
    // Schnelle Lesezeichen (#1104): Spalte links der Zeilennummern, Wiederfinden und Übernahme der IDE-Lesezeichen;
    // nach den Lesezeichen (#622), deren Listen sie liest.
    TAtlasFeaturePart.When('QuickBookmarks',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
          TAtlasIdeSettings.Current.QuickBookmarks);
      end, QuickColumnStarted, StartQuickColumn, StopQuickColumn)];
end;

class function TAtlasBookmarksModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasBookmarksModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
  begin
    Exit;
  end;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + cModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasBookmarksModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  GScope.Provide(IAtlasOverviewBookmarks, mRef);
  // Reiter „Gemerkt“ der Willkommensseite (#755) über den Vertrag (#1456).
  GScope.Provide(IAtlasSavedPlacesSource, TAtlasIdeSavedPlaces.Create as IAtlasSavedPlacesSource);
  // Schichten der Rinne (#545, #622): vor den Rekursionssymbolen von Base.
  GScope.Provide(IAtlasGutterLayer, TAtlasIdeNotesGutter.Create as IAtlasGutterLayer);
  GScope.Provide(IAtlasGutterLayer, TAtlasIdeBookmarksGutter.Create as IAtlasGutterLayer);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasBookmarksModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
  begin
    for mFailure in mRegistry.UnregisterModule(cModuleId) do
    begin
      TAtlasGuard.Log('Modul ' + cModuleId + ' nicht sauber abgemeldet: ' + mFailure);
    end;
  end;
end;

initialization
  TAtlasBookmarksModule.RegisterModule;

finalization
  TAtlasBookmarksModule.UnregisterModule;

end.
