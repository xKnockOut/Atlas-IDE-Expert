unit Atlas.IDE.Bookmarks.Composition;

// Modul Lesezeichen (#1455): einzige Unit, die persönliche
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
// Modulklasse, Befehle, Menü und Tasten stehen in Atlas.IDE.Bookmarks.Adapters.Module.

interface

implementation

uses
  System.SysUtils,
  Atlas.UI.Bookmarks.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.Core.Modules.Contract,
  Atlas.Plugin.Editor.Contract,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Bookmarks.Plan,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Notes.Gutter,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.Gutter,
  Atlas.IDE.Bookmarks.QuickColumn,
  Atlas.IDE.Bookmarks.QuickChord,
  Atlas.IDE.Bookmarks.Adapters.SavedPlaces,
  Atlas.IDE.Bookmarks.Composition.Todos,
  Atlas.Plugin.SavedPlaces.Contract,
  Atlas.IDE.Bookmarks.Adapters.Module;

const
  /// <summary>Feld der schnellen Lesezeichen im Atlas-Statusfeld (#1104).</summary>
  cQuickBookmarksExtra = 'quickBookmarks';

var
  GScope: IAtlasModuleScope;
  GNotesStarted: Boolean;
  GBookmarksStarted: Boolean;
  GQuickColumn: TAtlasIdeQuickColumn;

{ Dienste von Base }

procedure QuickStatus(AText: string);
begin
  TAtlasIdeHost.SetStatusExtra(cQuickBookmarksExtra, AText);
end;

{ Start der Teile (aus der Kompositionswurzel hierher gezogen, #1455) }

procedure StartNotes;
begin
  TAtlasIdeNotes.Start(TAtlasIdeHost.Messages());
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
  TAtlasIdeBookmarks.Start(TAtlasIdeHost.Messages(), QuickStatus);
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

function Parts: TArray<IAtlasFeaturePart>;
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
        Result := TAtlasBookmarksPlan.QuickColumnRuns(ALevel, TAtlasIdeSettings.Current.QuickBookmarks);
      end, QuickColumnStarted, StartQuickColumn, StopQuickColumn)];
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasBookmarksEditorSection.ProvideIn(GScope);
  TAtlasBookmarksKeysSection.ProvideIn(GScope);
end;

/// <summary>Was die Modulklasse von der Composition braucht.</summary>
function ModuleHooks: TAtlasBookmarksModuleHooks;
begin
  Result := Default(TAtlasBookmarksModuleHooks);
  Result.AllTodos := AllTodos;
  Result.FilterTodos := FilterTodos;
  Result.BookmarksStarted := BookmarksStarted;
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasBookmarksModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasBookmarksModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasBookmarksModule.Create(ModuleHooks);
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

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasBookmarksModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
