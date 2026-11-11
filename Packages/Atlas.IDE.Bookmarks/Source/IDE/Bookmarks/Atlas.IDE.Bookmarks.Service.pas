unit Atlas.IDE.Bookmarks.Service;

// Benannte Lesezeichen (#622), IDE-Seite: hält je Projekt die Liste
// (TAtlasBookmarkList) im Speicher, liest und schreibt sie neben der .dproj
// (TAtlasBookmarks: lokal .atlas-bookmarks.json, mit bookmarks.shared
// atlas-bookmarks.json für das Team) und führt die Befehle aus:
// - „Lesezeichen setzen…“ (Strg+Alt+K, Menü Atlas, Kontextmenü, Palette):
//   kleiner Dialog mit Namensvorschlag (Methode und Zeilenbeginn) für die
//   Zeile, die zuletzt per Rechtsklick in der Rinne gewählt wurde
//   (TAtlasIdeGutterMarks.TakeLine), sonst für die Cursorzeile.
// - „Gehe zu Lesezeichen…“: alle Lesezeichen des Projekts in einem Fenster
//   wie die Befehlspalette mit unscharfer Suche über Name sowie Datei und
//   Methode (TAtlasCommandPalette), in der Reihenfolge der Liste.
// - „Lesezeichen-Fenster“: andockbares Seitenfenster (TAtlasIdeBookmarksWindow)
//   mit Filter, Sprung, Umbenennen (F2), Löschen (Entf) und Umsortieren.
// Vor dem Zeigen und vor jedem Sprung werden die Lesezeichen gegen den
// aktuellen Text wiedergefunden (offener Puffer, sonst Platte; fehlende
// Datei = „nicht gefunden“); Track tut das für die Datei im oberen Editor
// nach jeder Tipp-Pause, damit die Lesezeichen Änderungen folgen. Das Projekt
// einer Datei ist das Projekt der Projektgruppe, das sie enthält, sonst das
// aktive Projekt. Mit bookmarks.named aus ruht alles; die nummerierten
// Lesezeichen der IDE bleiben unberührt. Meldungen nur als Zeile in der
// Meldungsansicht.
// Schnelle Lesezeichen (#1104, bookmarks.quick) liegen in derselben Liste
// (Art quick bzw. mit Nummer, TAtlasQuickBookmarks): Strg+Umschalt+K
// (QuickToggle), Strg+Umschalt+1…9 (QuickSetNumber), Strg+1…9 (QuickJump,
// projektweit oder nur in der Datei; Hinweise im Statusfeld), nächstes und
// voriges Lesezeichen (Step), die Befehle der Spalte links der Zeilennummern
// (Column…) und die Übernahme der IDE-Lesezeichen 1–9 beim ersten Öffnen
// einer Datei (ImportIde). Die Schicht der benannten Lesezeichen in der Rinne
// zeigt nur benannte ohne Nummer, solange die Spalte sichtbar ist (NamedAt).
// Fenster und Wiederfinden laufen, solange eine der beiden Arten an ist. Die
// Befehle der schnellen Lesezeichen stehen in Atlas.IDE.Bookmarks.QuickService;
// sie nutzen die öffentlichen Bausteine dieses Dienstes (Liste, Commit, Status).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Bookmarks.Store,
  Atlas.UI.Bookmarks.Frame;

type
  TAtlasIdeBookmarks = class
  private type
    TState = record
      Lists: TDictionary<string, TAtlasBookmarkList>;
      /// <summary>Datei (klein) → Projekt; gefüllt von Track und den Befehlen.</summary>
      ProjectOf: TDictionary<string, string>;
      Message: TProc<string>;
      /// <summary>Statusfeld (#1104); '' entfernt den Hinweis.</summary>
      Status: TProc<string>;
      StatusAt: UInt64;
      /// <summary>Dateien (klein), deren IDE-Lesezeichen in dieser Sitzung geprüft wurden.</summary>
      Imported: TDictionary<string, Boolean>;
      /// <summary>Ablage, aus der die Listen im Speicher stammen (bookmarks.shared).</summary>
      Shared: Boolean;
      /// <summary>Projekt, dessen Lesezeichen das Seitenfenster zeigt.</summary>
      WindowProject: string;
      /// <summary>Die Spalte der schnellen Lesezeichen hat die IDE wirklich gezeichnet (#1281); meldet
      /// TAtlasIdeQuickColumn.</summary>
      ColumnPainted: Boolean;
    end;
  private class var
    FState: TState;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht; AStatus: Hinweis im Statusfeld ('' entfernt ihn).
    /// </summary>
    class procedure Start(const AMessage, AStatus: TProc<string>); static;
    class procedure Release; static;
    /// <summary>Gestartet (Start ohne Release)?</summary>
    class function Running: Boolean; static;
    /// <summary>Einstellungen geändert: Ablage gewechselt (neu lesen), ausgeschaltet (Fenster schließen).</summary>
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Oberer Editor zeigt AFileName mit AText: Projekt merken, dessen Lesezeichen der Datei
    /// wiederfinden (gespeichert, wenn sich etwas ändert). True, wenn sich Lesezeichen geändert haben.</summary>
    class function Track(const AFileName, AText: string): Boolean; static;
    /// <summary>Hat AFileName Lesezeichen (aus dem Speicher, ohne IDE-Aufrufe; erst nach Track bekannt)?</summary>
    class function HasBookmarks(const AFileName: string): Boolean; static;
    /// <summary>Gefundene Lesezeichen an ALine (0-basiert); ohne IDE-Aufrufe, zum Zeichnen.</summary>
    class function BookmarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>; static;
    /// <summary>„Lesezeichen setzen…“.</summary>
    class procedure AddBookmark; static;
    /// <summary>„Gehe zu Lesezeichen…“.</summary>
    class procedure GoToBookmark; static;
    /// <summary>Seitenfenster „Lesezeichen“ zeigen.</summary>
    class procedure ShowWindow; static;
    /// <summary>Zum Lesezeichen AId von AProject springen (nicht gefunden: letzte bekannte Stelle).</summary>
    class procedure OpenBookmark(const AProject, AId: string); static;
    class procedure RenameBookmark(const AProject, AId, AName: string); static;
    class procedure DeleteBookmark(const AProject, AId: string); static;
    class procedure MoveBookmark(const AProject, AId, ABeforeId: string); static;
    /// <summary>Nummer aus dem Fenster (Strg+Umschalt+Zahl in der Liste).</summary>
    class procedure AssignNumber(const AProject, AId: string; ANumber: Integer); static;
    /// <summary>Hinweis im Statusfeld nach einigen Sekunden entfernen; vom Zeitgeber der Spalte.</summary>
    class procedure ExpireStatus; static;
    /// <summary>Spalte der schnellen Lesezeichen gezeichnet bzw. entfernt (#1281): Erst dann zeigt die Rinne
    /// nummerierte benannte Lesezeichen nicht mehr selbst, und erst dann übernimmt ImportIde.</summary>
    class procedure ColumnPainted(APainted: Boolean); static;
    // Bausteine für die schnellen Lesezeichen (Atlas.IDE.Bookmarks.QuickService).
    /// <summary>Zeile in der Meldungsansicht.</summary>
    class procedure Say(const AText: string); static;
    /// <summary>Hinweis im Statusfeld; ohne Statusfeld in die Meldungsansicht.</summary>
    class procedure Status(const AText: string); static;
    /// <summary>Schnelle Lesezeichen an (bookmarks.quick); AReport: sonst Meldung.</summary>
    class function QuickOn(AReport: Boolean): Boolean; static;
    /// <summary>Spalte der schnellen Lesezeichen sichtbar: eingeschaltet (bookmarks.quick und
    /// bookmarks.quick.gutter) und von der IDE gezeichnet (#1281).</summary>
    class function ColumnShown: Boolean; static;
    /// <summary>Projekt, Text und wiedergefundene Liste zu AFileName; False mit Meldung ohne Projekt.</summary>
    class function PrepareFile(const AFileName: string; out AProject, AText: string;
      out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Geänderte Liste speichern, Rinne und Fenster nachziehen; sonst nur merken.</summary>
    class procedure Commit(const AList: TAtlasBookmarkList; AChanged: Boolean; const ASelectId: string); static;
    class function List(const AProject: string): TAtlasBookmarkList; static;
    /// <summary>Liste im Speicher ersetzen, ohne zu speichern.</summary>
    class procedure Put(const AList: TAtlasBookmarkList); static;
    /// <summary>Liste speichern; False mit Meldung.</summary>
    class function Store(const AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Lesezeichen einer Datei wiederfinden; True bei Änderung.</summary>
    class function RelocateFile(var AList: TAtlasBookmarkList; const AFileName: string): Boolean; static;
    class procedure RefreshWindow(const ASelectId: string); static;
    /// <summary>Rinne neu zeichnen.</summary>
    class procedure Invalidate; static;
    class function ResolveProject(const AFileName: string): string; static;
    /// <summary>Projekt der Datei im oberen Editor, sonst das aktive Projekt.</summary>
    class function CurrentProject: string; static;
    /// <summary>Liste im Speicher zur Datei AFileName (ohne IDE-Aufrufe; erst nach Track bekannt).</summary>
    class function LoadedList(const AFileName: string; out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>IDE-Lesezeichen von AFileName in dieser Sitzung noch nicht übernommen: jetzt als übernommen
    /// merken und True.</summary>
    class function TakeImport(const AFileName: string): Boolean; static;
  end;

implementation

uses
  Atlas.IDE.Foundation.EditorBuffer,
  System.Classes,
  System.Types,
  System.DateUtils,
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Bookmarks.Quick,
  Atlas.UI.Bookmarks.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Bookmarks.Dialog,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Bookmarks.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Host;

const
  /// <summary>So lange steht ein Hinweis der schnellen Lesezeichen im Statusfeld.</summary>
  cStatusMs = 4000;

function Key(const APath: string): string;
begin
  Result := LowerCase(Trim(APath)).Replace('/', '\');
end;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function Enabled(AReport: Boolean): Boolean;
begin
  Result := (TAtlasIdeBookmarks.FState.Lists <> nil) and TAtlasIdeSettings.Current.BookmarksNamed;
  if not Result and AReport and (TAtlasIdeBookmarks.FState.Lists <> nil) then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksDisabled));
  end;
end;

function Available(AReport: Boolean): Boolean;
begin
  Result := (TAtlasIdeBookmarks.FState.Lists <> nil) and (TAtlasIdeSettings.Current.BookmarksNamed or
    TAtlasIdeSettings.Current.QuickBookmarks);
  if not Result and AReport and (TAtlasIdeBookmarks.FState.Lists <> nil) then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksDisabled));
  end;
end;

procedure CheckStorage;
begin
  // Ablage umgeschaltet: Listen aus der jeweils gültigen Datei neu lesen.
  if (TAtlasIdeBookmarks.FState.Lists <> nil) and
    (TAtlasIdeBookmarks.FState.Shared <> TAtlasIdeSettings.Current.BookmarksShared) then
  begin
    TAtlasIdeBookmarks.FState.Lists.Clear;
    TAtlasIdeBookmarks.FState.Shared := TAtlasIdeSettings.Current.BookmarksShared;
  end;
end;

function RelocateAll(var AList: TAtlasBookmarkList): Boolean;
var
  mFileName: string;
begin
  Result := False;
  for mFileName in AList.Files do
  begin
    Result := TAtlasIdeBookmarks.RelocateFile(AList, mFileName) or Result;
  end;
end;

function Target(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  Result := False;
  if not Enabled(True) then
  begin
    Exit;
  end;
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoEditor));
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  // Rechtsklick in die Rinne gilt vor dem Cursor, solange er frisch ist und zur Datei passt.
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
  end;
  Result := ALine >= 0;
end;

function PlaceText(const AProject: string): string;
var
  mCurrent: TAtlasBookmarkList;
begin
  if AProject = '' then
  begin
    Exit(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoProjectList));
  end;
  // Fußzeile: „Lesezeichen in Projekt.dproj: 5, davon 1 nicht gefunden · Lokal in …“.
  mCurrent := TAtlasIdeBookmarks.List(AProject);
  Result := TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.BookmarksListTitle,
    [ExtractFileName(AProject), mCurrent.Count, mCurrent.LostCount]) + ' · ';
  if TAtlasIdeBookmarks.FState.Shared then
  begin
    Result := Result + TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksStoredShared);
  end
  else
  begin
    Result := Result + TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksStoredLocal);
  end;
end;

procedure WireFrame(AFrame: TAtlasBookmarksFrame);
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.OnOpen :=
    procedure(AId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.OpenBookmark(TAtlasIdeBookmarks.FState.WindowProject, AId);
        end);
    end;
  AFrame.OnRename :=
    procedure(AId, AName: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.RenameBookmark(TAtlasIdeBookmarks.FState.WindowProject, AId, AName);
        end);
    end;
  AFrame.OnDelete :=
    procedure(AId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.DeleteBookmark(TAtlasIdeBookmarks.FState.WindowProject, AId);
        end);
    end;
  AFrame.OnNumber :=
    procedure(AId: string; ANumber: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.AssignNumber(TAtlasIdeBookmarks.FState.WindowProject, AId, ANumber);
        end);
    end;
  AFrame.OnMove :=
    procedure(AId, ABeforeId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.MoveBookmark(TAtlasIdeBookmarks.FState.WindowProject, AId, ABeforeId);
        end);
    end;
end;

{ TAtlasIdeBookmarks }

class function TAtlasIdeBookmarks.Running: Boolean;
begin
  Result := FState.Lists <> nil;
end;

class function TAtlasIdeBookmarks.LoadedList(const AFileName: string; out AList: TAtlasBookmarkList): Boolean;
var
  mProject: string;
begin
  Result := (FState.ProjectOf <> nil) and FState.ProjectOf.TryGetValue(Key(AFileName), mProject) and
    FState.Lists.TryGetValue(Key(mProject), AList);
end;

class function TAtlasIdeBookmarks.TakeImport(const AFileName: string): Boolean;
begin
  Result := (FState.Imported <> nil) and not FState.Imported.ContainsKey(Key(AFileName));
  if Result then
  begin
    FState.Imported.Add(Key(AFileName), True);
  end;
end;

class procedure TAtlasIdeBookmarks.Start(const AMessage, AStatus: TProc<string>);
begin
  // Mehrfach aufgerufen (nach jeder Einstellungsänderung): vorhandene Listen bleiben, ApplySettings wechselt
  // bei Bedarf die Ablage.
  FState.Message := AMessage;
  FState.Status := AStatus;
  if FState.Imported = nil then
  begin
    FState.Imported := TDictionary<string, Boolean>.Create;
  end;
  if FState.Lists = nil then
  begin
    FState.Lists := TDictionary<string, TAtlasBookmarkList>.Create;
    FState.Shared := TAtlasIdeSettings.Current.BookmarksShared;
  end;
  if FState.ProjectOf = nil then
  begin
    FState.ProjectOf := TDictionary<string, string>.Create;
  end;
  TAtlasIdeBookmarksWindow.OnFrame :=
    procedure(AFrame: TAtlasBookmarksFrame)
    begin
      WireFrame(AFrame);
      RefreshWindow('');
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeBookmarksWindow.Prepare;
end;

class procedure TAtlasIdeBookmarks.Release;
begin
  TAtlasIdeBookmarksWindow.Release;
  if Assigned(FState.Status) and (FState.StatusAt <> 0) then
  begin
    FState.Status('');
  end;
  FState.Message := nil;
  FState.Status := nil;
  FState.StatusAt := 0;
  FreeAndNil(FState.Lists);
  FreeAndNil(FState.ProjectOf);
  FreeAndNil(FState.Imported);
  FState.WindowProject := '';
  FState.ColumnPainted := False;
end;

class procedure TAtlasIdeBookmarks.Say(const AText: string);
begin
  if Assigned(FState.Message) then
  begin
    FState.Message(AText);
  end;
end;

class procedure TAtlasIdeBookmarks.Status(const AText: string);
begin
  // Ohne Statusfeld (Statusleiste aus) in die Meldungsansicht.
  if not Assigned(FState.Status) then
  begin
    Say(AText);
    Exit;
  end;
  FState.Status(AText);
  FState.StatusAt := TThread.GetTickCount64;
end;

class procedure TAtlasIdeBookmarks.ExpireStatus;
begin
  if (FState.StatusAt = 0) or (TThread.GetTickCount64 - FState.StatusAt < cStatusMs) then
  begin
    Exit;
  end;
  FState.StatusAt := 0;
  if Assigned(FState.Status) then
  begin
    FState.Status('');
  end;
end;

class function TAtlasIdeBookmarks.QuickOn(AReport: Boolean): Boolean;
begin
  Result := (FState.Lists <> nil) and TAtlasIdeSettings.Current.QuickBookmarks;
  if not Result and AReport and (FState.Lists <> nil) then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkDisabled));
  end;
end;

class function TAtlasIdeBookmarks.ColumnShown: Boolean;
begin
  // Nicht allein die Einstellung: Fehlt die Spalte, blieben Marker sonst ganz unsichtbar (#1281).
  Result := FState.ColumnPainted and TAtlasIdeSettings.Current.QuickBookmarks and
    TAtlasIdeSettings.Current.QuickBookmarksGutter;
end;

class procedure TAtlasIdeBookmarks.ColumnPainted(APainted: Boolean);
begin
  if FState.ColumnPainted = APainted then
  begin
    Exit;
  end;
  FState.ColumnPainted := APainted;
  // Die Schicht der benannten Lesezeichen zeigt nummerierte nun selbst bzw. überlässt sie der Spalte.
  Invalidate;
end;

class function TAtlasIdeBookmarks.ResolveProject(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectOfFile(AFileName);
  if Result = '' then
  begin
    Result := TAtlasIdeFiles.ActiveProjectFile;
  end;
  if (Result <> '') and (FState.ProjectOf <> nil) then
  begin
    FState.ProjectOf.AddOrSetValue(Key(AFileName), Result);
  end;
end;

class function TAtlasIdeBookmarks.CurrentProject: string;
var
  mView: IOTAEditView;
begin
  Result := '';
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and (mView.Buffer.FileName <> '') then
  begin
    Result := ResolveProject(mView.Buffer.FileName);
  end;
  if Result = '' then
  begin
    Result := TAtlasIdeFiles.ActiveProjectFile;
  end;
end;

class function TAtlasIdeBookmarks.List(const AProject: string): TAtlasBookmarkList;
begin
  CheckStorage;
  if (FState.Lists <> nil) and FState.Lists.TryGetValue(Key(AProject), Result) then
  begin
    Exit;
  end;
  // Ohne Datei oder bei ungültigem Inhalt: leere Liste zu diesem Projekt.
  TAtlasBookmarks.Load(AProject, FState.Shared, Result);
  if FState.Lists <> nil then
  begin
    FState.Lists.AddOrSetValue(Key(AProject), Result);
  end;
end;

class procedure TAtlasIdeBookmarks.Put(const AList: TAtlasBookmarkList);
begin
  if FState.Lists <> nil then
  begin
    FState.Lists.AddOrSetValue(Key(AList.Project), AList);
  end;
end;

class function TAtlasIdeBookmarks.Store(const AList: TAtlasBookmarkList): Boolean;
begin
  Put(AList);
  Result := TAtlasBookmarks.Save(AList, FState.Shared);
  if not Result then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksSaveFailed));
  end;
end;

class function TAtlasIdeBookmarks.RelocateFile(var AList: TAtlasBookmarkList; const AFileName: string): Boolean;
var
  mText: string;
begin
  mText := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  // Leer heißt: Datei fehlt (oder ist leer); ihre Lesezeichen sind dann nicht zu finden.
  if mText = '' then
  begin
    Result := AList.LoseFile(AFileName);
  end
  else
  begin
    Result := AList.Relocate(AFileName, mText);
  end;
  if FState.ProjectOf <> nil then
  begin
    FState.ProjectOf.AddOrSetValue(Key(AFileName), AList.Project);
  end;
end;

class procedure TAtlasIdeBookmarks.Invalidate;
begin
  TAtlasIdeGutterMarks.Invalidate;
end;

class function TAtlasIdeBookmarks.Track(const AFileName, AText: string): Boolean;
var
  mProject: string;
  mCurrent: TAtlasBookmarkList;
begin
  Result := False;
  if not Available(False) or (AFileName = '') then
  begin
    Exit;
  end;
  mProject := ResolveProject(AFileName);
  if mProject = '' then
  begin
    Exit;
  end;
  // Das Seitenfenster folgt dem Projekt der Datei vorn.
  if TAtlasIdeBookmarksWindow.Visible and (Key(mProject) <> Key(FState.WindowProject)) then
  begin
    FState.WindowProject := mProject;
    RefreshWindow('');
  end;
  mCurrent := List(mProject);
  if Length(mCurrent.ForFile(AFileName)) = 0 then
  begin
    Exit;
  end;
  Result := mCurrent.Relocate(AFileName, AText);
  if not Result then
  begin
    Exit;
  end;
  Store(mCurrent);
  RefreshWindow('');
end;

class function TAtlasIdeBookmarks.HasBookmarks(const AFileName: string): Boolean;
var
  mCurrent: TAtlasBookmarkList;
begin
  Result := LoadedList(AFileName, mCurrent) and (Length(mCurrent.ForFile(AFileName)) > 0);
end;

class function TAtlasIdeBookmarks.BookmarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
var
  mCurrent: TAtlasBookmarkList;
  mMark: TAtlasBookmark;
begin
  Result := nil;
  if not LoadedList(AFileName, mCurrent) then
  begin
    Exit;
  end;
  // Schnelle Lesezeichen gehören in ihre Spalte, nummerierte benannte ebenfalls, solange sie sichtbar ist.
  for mMark in mCurrent.AtLine(AFileName, ALine) do
  begin
    if (mMark.Kind = TAtlasBookmarkKind.Named) and not (ColumnShown and (mMark.Number > 0)) then
    begin
      Result := Result + [mMark];
    end;
  end;
end;

class procedure TAtlasIdeBookmarks.AddBookmark;
var
  mFileName, mProject, mText, mName, mId: string;
  mLine: Integer;
  mCurrent: TAtlasBookmarkList;
begin
  if not Target(mFileName, mLine) then
  begin
    Exit;
  end;
  mProject := ResolveProject(mFileName);
  if mProject = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoProject));
    Exit;
  end;
  mText := TAtlasIdeWorkspaceEdit.CurrentText(mFileName);
  mCurrent := List(mProject);
  // Erst wiederfinden, damit die übrigen Lesezeichen der Datei zum Text passen.
  mCurrent.Relocate(mFileName, mText);
  mName := TAtlasBookmarks.SuggestName(mFileName, mText, mLine);
  if not TAtlasBookmarkDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.BookmarksDialogTitle,
    [ExtractFileName(mFileName), mLine + 1]), mName) then
  begin
    // Abbrechen: nur das Wiederfinden behalten.
    Put(mCurrent);
    Exit;
  end;
  mId := mCurrent.Add(mFileName, mText, mLine, mName, NowUtc);
  Store(mCurrent);
  Invalidate;
  if TAtlasIdeBookmarksWindow.Visible then
  begin
    FState.WindowProject := mProject;
  end;
  RefreshWindow(mId);
end;

/// <summary>Je Lesezeichen ein Eintrag der Palette: Name als Beschriftung, Ort (Datei, Zeile, Methode) als Pfad;
/// die Suche findet beides.</summary>
function BookmarkCommands(const AList: TAtlasBookmarkList): TArray<TAtlasCommand>;
var
  mCommand: TAtlasCommand;
  mMark: TAtlasBookmark;
begin
  Result := nil;
  for mMark in AList.Bookmarks do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := mMark.Id;
    mCommand.Caption := mMark.DisplayName;
    if mMark.Number > 0 then
    begin
      mCommand.Caption := IntToStr(mMark.Number) + ' · ' + mCommand.Caption;
    end;
    mCommand.Path := TAtlasBookmarks.Location(mMark);
    if mMark.Lost then
    begin
      mCommand.ShortCut := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksLost);
    end;
    mCommand.Description := mMark.Preview;
    Result := Result + [mCommand];
  end;
end;

/// <summary>Palette über die Lesezeichen von AProject; Auswahl springt hin.</summary>
procedure ShowPalette(const AProject: string; const AList: TAtlasBookmarkList);
var
  mProject: string;
  mWindow: TAtlasPaletteWindow;
begin
  mProject := AProject;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, BookmarkCommands(AList), nil, TAtlasIdeStyle.Colors);
  mWindow.KeepOrder := True;
  mWindow.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      mId: string;
    begin
      mId := ACommand.Id;
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.OpenBookmark(mProject, mId);
        end);
    end;
  mWindow.ShowOver(TAtlasIdeHost.PopupArea);
end;

class procedure TAtlasIdeBookmarks.GoToBookmark;
var
  mProject: string;
  mCurrent: TAtlasBookmarkList;
begin
  if not Available(True) then
  begin
    Exit;
  end;
  mProject := CurrentProject;
  if mProject = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoProject));
    Exit;
  end;
  mCurrent := List(mProject);
  if RelocateAll(mCurrent) then
  begin
    Store(mCurrent);
  end
  else
  begin
    Put(mCurrent);
  end;
  if mCurrent.Count = 0 then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNone));
    Exit;
  end;
  ShowPalette(mProject, mCurrent);
end;

class procedure TAtlasIdeBookmarks.RefreshWindow(const ASelectId: string);
var
  mFrame: TAtlasBookmarksFrame;
  mCurrent: TAtlasBookmarkList;
  mView: IOTAEditView;
begin
  mFrame := TAtlasIdeBookmarksWindow.ExistingFrame;
  if (mFrame = nil) or (FState.Lists = nil) then
  begin
    Exit;
  end;
  // „nur diese Datei“ bezieht sich auf die Datei im oberen Editor.
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mFrame.SetCurrentFile(mView.Buffer.FileName);
  end;
  if FState.WindowProject = '' then
  begin
    mCurrent := TAtlasBookmarkList.Create('');
  end
  else
  begin
    mCurrent := List(FState.WindowProject);
  end;
  mFrame.SetBookmarks(mCurrent, PlaceText(FState.WindowProject), ASelectId);
end;

class procedure TAtlasIdeBookmarks.ShowWindow;
var
  mCurrent: TAtlasBookmarkList;
  mFrame: TAtlasBookmarksFrame;
begin
  if not Available(True) then
  begin
    Exit;
  end;
  FState.WindowProject := CurrentProject;
  if FState.WindowProject <> '' then
  begin
    mCurrent := List(FState.WindowProject);
    if RelocateAll(mCurrent) then
    begin
      Store(mCurrent);
    end
    else
    begin
      Put(mCurrent);
    end;
  end;
  mFrame := TAtlasIdeBookmarksWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  RefreshWindow('');
  if mFrame.Filter.CanFocus then
  begin
    mFrame.Filter.SetFocus;
  end;
end;

class procedure TAtlasIdeBookmarks.OpenBookmark(const AProject, AId: string);
var
  mCurrent: TAtlasBookmarkList;
  mIndex: Integer;
  mMark: TAtlasBookmark;
begin
  if not Available(True) or (AProject = '') then
  begin
    Exit;
  end;
  mCurrent := List(AProject);
  mIndex := mCurrent.IndexOf(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  // Unmittelbar vor dem Sprung wiederfinden: Die Datei kann sich außerhalb geändert haben.
  if RelocateFile(mCurrent, mCurrent.Bookmarks[mIndex].FileName) then
  begin
    Store(mCurrent);
    RefreshWindow(AId);
  end
  else
  begin
    Put(mCurrent);
  end;
  mMark := mCurrent.Bookmarks[mIndex];
  if mMark.Lost then
  begin
    Say(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.BookmarksLostJump, [mMark.DisplayName]));
  end;
  TAtlasIdeResults.Open(mMark.FileName, mMark.Line, 0);
  Invalidate;
end;

class procedure TAtlasIdeBookmarks.RenameBookmark(const AProject, AId, AName: string);
var
  mCurrent: TAtlasBookmarkList;
begin
  if not Available(True) or (AProject = '') then
  begin
    Exit;
  end;
  mCurrent := List(AProject);
  if not mCurrent.Rename(AId, AName) then
  begin
    Exit;
  end;
  Store(mCurrent);
  RefreshWindow(AId);
end;

class procedure TAtlasIdeBookmarks.DeleteBookmark(const AProject, AId: string);
var
  mCurrent: TAtlasBookmarkList;
  mIndex: Integer;
begin
  if not Available(True) or (AProject = '') then
  begin
    Exit;
  end;
  mCurrent := List(AProject);
  mIndex := mCurrent.IndexOf(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  if MessageDlg(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.BookmarksDeleteConfirm,
    [mCurrent.Bookmarks[mIndex].DisplayName]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  mCurrent.Remove(AId);
  Store(mCurrent);
  Invalidate;
  RefreshWindow('');
end;

class procedure TAtlasIdeBookmarks.MoveBookmark(const AProject, AId, ABeforeId: string);
var
  mCurrent: TAtlasBookmarkList;
begin
  if not Available(True) or (AProject = '') then
  begin
    Exit;
  end;
  mCurrent := List(AProject);
  if not mCurrent.MoveBefore(AId, ABeforeId) then
  begin
    Exit;
  end;
  Store(mCurrent);
  RefreshWindow(AId);
end;

class procedure TAtlasIdeBookmarks.ApplySettings;
begin
  if FState.Lists = nil then
  begin
    Exit;
  end;
  if not Available(False) then
  begin
    // Beide Arten aus: Fenster zu, die Rinne zeichnet nichts mehr (Wanted der Schicht).
    TAtlasIdeBookmarksWindow.Hide;
    Invalidate;
    Exit;
  end;
  // Spalte ein- oder ausgeschaltet: Die Schicht der benannten Lesezeichen zeigt nummerierte wieder bzw. nicht.
  Invalidate;
  if not QuickOn(False) and (FState.StatusAt <> 0) then
  begin
    FState.StatusAt := 0;
    if Assigned(FState.Status) then
    begin
      FState.Status('');
    end;
  end;
  if FState.Shared <> TAtlasIdeSettings.Current.BookmarksShared then
  begin
    CheckStorage;
    FState.ProjectOf.Clear;
    Invalidate;
    RefreshWindow('');
  end;
end;

class function TAtlasIdeBookmarks.PrepareFile(const AFileName: string; out AProject, AText: string;
  out AList: TAtlasBookmarkList): Boolean;
begin
  AText := '';
  AList := TAtlasBookmarkList.Create('');
  AProject := ResolveProject(AFileName);
  if AProject = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoProject));
    Exit(False);
  end;
  AText := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  AList := List(AProject);
  // Erst wiederfinden, damit die Marker der Datei zum Text passen.
  AList.Relocate(AFileName, AText);
  Result := True;
end;

class procedure TAtlasIdeBookmarks.Commit(const AList: TAtlasBookmarkList; AChanged: Boolean;
  const ASelectId: string);
begin
  if not AChanged then
  begin
    Put(AList);
    Exit;
  end;
  Store(AList);
  Invalidate;
  RefreshWindow(ASelectId);
end;

class procedure TAtlasIdeBookmarks.AssignNumber(const AProject, AId: string; ANumber: Integer);
var
  mCurrent: TAtlasBookmarkList;
begin
  if not QuickOn(True) or (AProject = '') then
  begin
    Exit;
  end;
  mCurrent := List(AProject);
  Commit(mCurrent, TAtlasQuickBookmarks.AssignNumber(mCurrent, AId, ANumber) <> TAtlasQuickChange.None, AId);
end;

class procedure TAtlasIdeBookmarks.ThemeChanged;
begin
  TAtlasIdeBookmarksWindow.ApplyTheme;
end;

end.
