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
// Die TODO-Liste fragt den Server über TAtlasIdeHost; seine Antwort
// erreicht das Modul nur, solange es angemeldet ist (Regel 3).
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
    ModuleId = 'atlas.bookmarks';
    Switch = 'bookmarks';
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
  System.JSON,
  ToolsAPI,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Results.Model,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Bookmarks.Quick,
  Atlas.Core.Projects.Todos,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Notes.Gutter,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.Gutter,
  Atlas.IDE.Bookmarks.QuickColumn,
  Atlas.IDE.Bookmarks.QuickChord,
  Atlas.IDE.Bookmarks.SavedPlaces,
  Atlas.Core.SavedPlaces.Contract,
  Atlas.UI.Todos.Dialog,
  Atlas.UI.Strings,
  Atlas.UI.Bookmarks.Strings;

const
  /// <summary>Feld der schnellen Lesezeichen im Atlas-Statusfeld (#1104).</summary>
  QuickBookmarksExtra = 'quickBookmarks';
  TodosCommand = 'atlas.server.todos';
  TodosTimeoutMs = 120000;

var
  GScope: IAtlasModuleScope;
  GNotesStarted: Boolean;
  GBookmarksStarted: Boolean;
  GQuickColumn: TAtlasIdeQuickColumn;
  /// <summary>Letzter Filter der TODO-Liste (#68) in dieser Sitzung; Vorgabe für den Filterdialog.</summary>
  GTodoFilter: TAtlasTodoFilter;
  /// <summary>Vorschläge für den Filterdialog aus der letzten Liste.</summary>
  GTodoChoices: TAtlasTodoChoices;

{ Dienste von Base }

procedure MessageLine(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

procedure QuickStatus(AText: string);
begin
  TAtlasIdeHost.SetStatusExtra(QuickBookmarksExtra, AText);
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
    Result := TAtlasIdeSettings.Current.BookmarkKey;
end;

/// <summary>Akkord der schnellen Lesezeichen (#1104); 0, solange sie aus sind oder die Wartezeit 0 ist (dann bleibt
/// Strg+Umschalt+K bei der IDE).</summary>
function QuickBookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.QuickBookmarks and (TAtlasIdeSettings.Current.QuickBookmarkChordWait > 0) then
    Result := TAtlasIdeSettings.Current.QuickBookmarkKey;
end;

function NextBookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.QuickBookmarks then
    Result := TAtlasIdeSettings.Current.NextBookmarkKey;
end;

function PreviousBookmarkKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.QuickBookmarks then
    Result := TAtlasIdeSettings.Current.PreviousBookmarkKey;
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

/// <summary>Argumente für atlas.server.todos im Modus json: [uri, "json", filter].</summary>
function TodoArguments(const AProject: string; const AFilter: TAtlasTodoFilter): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspSession.PathToUri(AProject));
    mArguments.Add('json');
    mArguments.AddElement(TJSONObject.ParseJSONValue(AFilter.ToJson));
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

/// <summary>Antwort des Servers zur TODO-Liste im Ergebnisfenster zeigen (Hauptthread).</summary>
procedure ShowTodos(const AAnswer, AName, ADescribed: string; const AFilter: TAtlasTodoFilter);
var
  mEntries: TArray<TAtlasResultEntry>;
  mChoices: TAtlasTodoChoices;
begin
  if not TAtlasTodoList.Entries(AAnswer, mEntries) then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListFailed));
    Exit;
  end;
  // Vorschläge nur aus der ungefilterten Liste: sonst schrumpfen sie mit jedem Filter.
  if AFilter.IsEmpty and TAtlasTodoList.Choices(AAnswer, mChoices) then
    GTodoChoices := mChoices;
  if (Length(mEntries) = 0) and (ADescribed = '') then
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListEmpty, [AName]))
  else if Length(mEntries) = 0 then
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListNoMatch, [AName, ADescribed]))
  else if ADescribed = '' then
    TAtlasIdeResultsWindow.ShowEntries(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListTitle,
      [AName, Length(mEntries)]), mEntries)
  else
    TAtlasIdeResultsWindow.ShowEntries(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListFilteredTitle,
      [AName, ADescribed, Length(mEntries)]), mEntries);
end;

/// <summary>Rückruf der TODO-Liste; eigene Routine, damit er nur seine Werte festhält.</summary>
function TodosDone(const AName, ADescribed: string; const AFilter: TAtlasTodoFilter): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    begin
      ShowTodos(AAnswer, AName, ADescribed, AFilter);
    end;
end;

/// <summary>TODO-Liste des aktiven Projekts (#68) im Ergebnisfenster: Daten vom Server (startet ihn bei Bedarf) im
/// Hintergrund mit dem Filter AFilter (Filter des Servers), nach Unit gruppiert; Doppelklick springt zum
/// Kommentar.</summary>
procedure ProjectTodos(const AFilter: TAtlasTodoFilter);
var
  mProject: IOTAProject;
  mName, mDescribed: string;
  mFilter: TAtlasTodoFilter;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if (GScope = nil) or not TAtlasIdeSettings.Current.TodoList then
    Exit;
  mProject := GetActiveProject;
  if (mProject = nil) or (mProject.FileName = '') then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListNoProject));
    Exit;
  end;
  mName := ChangeFileExt(ExtractFileName(mProject.FileName), '');
  mFilter := AFilter.Trimmed;
  mDescribed := mFilter.Describe;
  if TAtlasIdeHost.ActiveSession = nil then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListFailed));
    Exit;
  end;
  if not TAtlasIdeHost.RunCommandAsync(GScope, TAtlasFeature.Palette, TodosCommand,
    TodoArguments(mProject.FileName, mFilter), TodosTimeoutMs, TodosDone(mName, mDescribed, mFilter)) then
    // Ein Befehl im Hintergrund läuft schon (etwa die Werte nach einem Build): später noch einmal.
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListBusy));
end;

procedure AllProjectTodos;
begin
  ProjectTodos(Default(TAtlasTodoFilter));
end;

/// <summary>Filterdialog der TODO-Liste (#68) mit dem letzten Filter; „Anzeigen“ fragt mit dem neuen Filter.</summary>
procedure FilterProjectTodos;
var
  mFilter: TAtlasTodoFilter;
begin
  if not TAtlasIdeSettings.Current.TodoList then
    Exit;
  mFilter := GTodoFilter;
  if not TAtlasTodoFilterDialog.Execute(GTodoChoices, mFilter) then
    Exit;
  GTodoFilter := mFilter;
  ProjectTodos(mFilter);
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
    Result := TAtlasKeyPriority.Take;
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
            TAtlasIdeBookmarks.QuickJump(ANumber)
          else
            TAtlasIdeBookmarks.QuickSetNumber(ANumber);
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
  for mNumber := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    mKey := TAtlasQuickBookmarks.KeyFor(Word(ABase), mNumber);
    if mKey = 0 then
      Exit;
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
  Result.Id := ModuleId;
  Result.Name := 'Lesezeichen';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Notizen und benannte Lesezeichen gab es schon im abgesicherten Start (nur lokale Dateien).
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
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
      TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand), TAtlasIdeBookmarks.QuickToggle,
        QuickBookmarksVisible,
      QuickBookmarkKey),
    CommandWithKey(TAtlasFeature.QuickBookmarks, 'Atlas.NextBookmark',
      TAtlasStrings.Text(TAtlasTextId.NextBookmarkCommand),
      TAtlasIdeBookmarks.NextBookmark, QuickBookmarksVisible, NextBookmarkKey),
    CommandWithKey(TAtlasFeature.QuickBookmarks, 'Atlas.PreviousBookmark',
      TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand),
      TAtlasIdeBookmarks.PreviousBookmark, QuickBookmarksVisible, PreviousBookmarkKey),
    // TODO-Liste des Projekts (#68): ohne Filter (alle offenen) und mit Filterdialog; nur sichtbar, solange die
    // Einstellung TodoList an ist.
    Command(TAtlasFeature.Palette, 'Atlas.TodoList',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListCommand), AllProjectTodos,
      TodoListVisible),
    Command(TAtlasFeature.Palette, 'Atlas.TodoListFilter',
      TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterCommand), FilterProjectTodos,
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
    // Spalte der schnellen Lesezeichen hat ihr eigenes Menü.
    MenuEntry('-', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.NoteAdd', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.NoteDelete', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.NoteList', TAtlasMenuPlace.EditorContext),
    MenuEntry('-', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.BookmarkAdd', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.BookmarkGoTo', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.QuickBookmarkToggle', TAtlasMenuPlace.EditorContext)];
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
    Result := Result + [ModuleKey('Atlas.BookmarkAdd', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
      mSettings.BookmarkKey, TAtlasKeyPriority.Shared, Guarded(TAtlasFeature.Bookmarks, TAtlasIdeBookmarks.AddBookmark))];
  // Schnelle Lesezeichen (#1104): aus = alle Tasten gehören wieder der IDE.
  if not mSettings.QuickBookmarks then
    Exit;
  if mSettings.QuickBookmarksNumberedKeys then
    Result := Result + NumberKeys(mSettings.QuickBookmarkSetKey, mSettings.QuickBookmarkSetKeyPriority, False) +
      NumberKeys(mSettings.QuickBookmarkJumpKey, mSettings.QuickBookmarkJumpKeyPriority, True);
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
      TAtlasKeyPriority.Shared, Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.NextBookmark)),
    ModuleKey('Atlas.PreviousBookmark', TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand),
      mSettings.PreviousBookmarkKey, TAtlasKeyPriority.Shared,
      Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.PreviousBookmark))];
end;

procedure TAtlasBookmarksModule.ApplySettings;
begin
  // bookmarks.named und bookmarks.shared (#622).
  TAtlasIdeBookmarks.ApplySettings;
  // bookmarks.quick aus: ein halb gedrückter Akkord gehört wieder der IDE (#1104).
  if not TAtlasIdeSettings.Current.QuickBookmarks then
    TAtlasIdeQuickChord.Release;
end;

procedure TAtlasBookmarksModule.ThemeChanged;
begin
  TAtlasIdeBookmarks.ThemeChanged;
end;

function TAtlasBookmarksModule.Marks(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;
var
  mMarks: TArray<TAtlasBookmark>;
  mMark: TAtlasBookmark;
begin
  // Mit schnellen Lesezeichen (#1104) zeigt die Art „bookmarks“ der Übersichtsleiste die Lesezeichen von Atlas.
  AMarks := nil;
  Result := GBookmarksStarted and TAtlasIdeBookmarks.OverviewMarks(AFileName, mMarks);
  if Result then
    for mMark in mMarks do
      AMarks := AMarks + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, mMark.Line, 1,
        mMark.DisplayName)];
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
    Exit;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasBookmarksModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
    GScope.Provide(IAtlasFeaturePart, mPart);
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
  Result := True;
end;

class procedure TAtlasBookmarksModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
    Exit;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
end;

initialization
  TAtlasBookmarksModule.RegisterModule;

finalization
  TAtlasBookmarksModule.UnregisterModule;

end.
