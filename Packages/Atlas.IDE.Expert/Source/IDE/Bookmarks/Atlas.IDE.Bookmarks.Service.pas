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
// Fenster und Wiederfinden laufen, solange eine der beiden Arten an ist.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Bookmarks.Store,
  Atlas.UI.Bookmarks.Frame;

type
  TAtlasIdeBookmarks = class
  private class var
    FLists: TDictionary<string, TAtlasBookmarkList>;
    /// <summary>Datei (klein) → Projekt; gefüllt von Track und den Befehlen.</summary>
    FProjectOf: TDictionary<string, string>;
    FMessage: TProc<string>;
    /// <summary>Statusfeld (#1104); '' entfernt den Hinweis.</summary>
    FStatus: TProc<string>;
    FStatusAt: UInt64;
    /// <summary>Dateien (klein), deren IDE-Lesezeichen in dieser Sitzung geprüft wurden.</summary>
    FImported: TDictionary<string, Boolean>;
    /// <summary>Ablage, aus der die Listen im Speicher stammen (bookmarks.shared).</summary>
    FShared: Boolean;
    /// <summary>Projekt, dessen Lesezeichen das Seitenfenster zeigt.</summary>
    FWindowProject: string;
  private
    class function Key(const APath: string): string; static;
    class procedure Say(const AText: string); static;
    class function NowUtc: TDateTime; static;
    class procedure Status(const AText: string); static;
    /// <summary>Benannte Lesezeichen an (bookmarks.named).</summary>
    class function Enabled(AReport: Boolean): Boolean; static;
    /// <summary>Schnelle Lesezeichen an (bookmarks.quick).</summary>
    class function QuickOn(AReport: Boolean): Boolean; static;
    /// <summary>Eine der beiden Arten an: Fenster, Wiederfinden, Sprung.</summary>
    class function Available(AReport: Boolean): Boolean; static;
    /// <summary>Spalte der schnellen Lesezeichen sichtbar (bookmarks.quick und bookmarks.quick.gutter).</summary>
    class function ColumnShown: Boolean; static;
    /// <summary>Projekt, Text und wiedergefundene Liste zu AFileName; False mit Meldung ohne Projekt.</summary>
    class function PrepareFile(const AFileName: string; out AProject, AText: string;
      out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Datei und Zeile (0-basiert) der Schreibmarke für die schnellen Lesezeichen samt Liste.</summary>
    class function QuickTarget(out AFileName, AText: string; out ALine: Integer;
      out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Geänderte Liste speichern, Rinne und Fenster nachziehen; sonst nur merken.</summary>
    class procedure Commit(const AList: TAtlasBookmarkList; AChanged: Boolean; const ASelectId: string); static;
    /// <summary>Zum Lesezeichen AId springen; ANumber > 0: Hinweis „Lesezeichen N nicht gefunden“.</summary>
    class procedure JumpTo(var AList: TAtlasBookmarkList; const AId: string; ANumber: Integer); static;
    class procedure Step(AForward: Boolean); static;
    class function ActiveProject: string; static;
    class function ResolveProject(const AFileName: string): string; static;
    /// <summary>Projekt der Datei im oberen Editor, sonst das aktive Projekt.</summary>
    class function CurrentProject: string; static;
    class procedure CheckStorage; static;
    class function List(const AProject: string): TAtlasBookmarkList; static;
    class procedure Put(const AList: TAtlasBookmarkList); static;
    class function Store(const AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Alle Lesezeichen der Liste gegen den aktuellen Text wiederfinden; True bei Änderung.</summary>
    class function RelocateAll(var AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Lesezeichen einer Datei wiederfinden; True bei Änderung.</summary>
    class function RelocateFile(var AList: TAtlasBookmarkList; const AFileName: string): Boolean; static;
    /// <summary>Datei und Zeile (0-basiert) für „Lesezeichen setzen…“; False mit Meldung.</summary>
    class function Target(out AFileName: string; out ALine: Integer): Boolean; static;
    class function PlaceText(const AProject: string): string; static;
    class procedure WireFrame(AFrame: TAtlasBookmarksFrame); static;
    class procedure RefreshWindow(const ASelectId: string); static;
    class procedure Invalidate; static;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht; AStatus: Hinweis im Statusfeld ('' entfernt ihn).
    /// </summary>
    class procedure Start(const AMessage, AStatus: TProc<string>); static;
    class procedure Release; static;
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
    /// <summary>Hinweis im Statusfeld nach einigen Sekunden entfernen; vom Zeitgeber der Spalte.</summary>
    class procedure ExpireStatus; static;
    /// <summary>Marker der Spalte an ALine (0-basiert), gefunden; ohne IDE-Aufrufe, zum Zeichnen.</summary>
    class function ColumnMarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>; static;
    /// <summary>Datei hat Marker für die Spalte (aus dem Speicher; erst nach Track bekannt).</summary>
    class function HasColumnMarks(const AFileName: string): Boolean; static;
    /// <summary>Gefundene Lesezeichen von AFileName für die Übersichtsleiste (#519); False, wenn die schnellen
    /// Lesezeichen aus sind (dann zeigt sie die IDE-Lesezeichen).</summary>
    class function OverviewMarks(const AFileName: string; out AMarks: TArray<TAtlasBookmark>): Boolean; static;
    /// <summary>Für „Nummer vergeben ›“: Index 1–9 der Ort der Nummer („Datei.pas:12 Name“), '' = frei.
    /// </summary>
    class function NumberTargets(const AFileName: string): TArray<string>; static;
    /// <summary>Strg+Umschalt+K: unnummeriertes Lesezeichen an der Cursorzeile setzen bzw. entfernen.</summary>
    class procedure QuickToggle; static;
    /// <summary>Strg+Umschalt+ANumber an der Cursorzeile.</summary>
    class procedure QuickSetNumber(ANumber: Integer); static;
    /// <summary>Strg+ANumber: Sprung nach bookmarks.quick.scope.</summary>
    class procedure QuickJump(ANumber: Integer); static;
    /// <summary>Nächstes bzw. voriges Lesezeichen der Datei, reihum.</summary>
    class procedure NextBookmark; static;
    class procedure PreviousBookmark; static;
    /// <summary>Linksklick in die Spalte an ALine (0-basiert).</summary>
    class procedure ColumnClick(const AFileName: string; ALine: Integer); static;
    /// <summary>„Nummer vergeben › N“: am ersten Marker der Zeile bzw. neu an der Zeile.</summary>
    class procedure ColumnAssign(const AFileName: string; ALine, ANumber: Integer); static;
    /// <summary>„Namen geben …“: macht den ersten Marker der Zeile zu einem benannten Lesezeichen (#622).</summary>
    class procedure ColumnName(const AFileName: string; ALine: Integer); static;
    class procedure ColumnRemove(const AFileName: string; ALine: Integer); static;
    class procedure ColumnRemoveFile(const AFileName: string); static;
    /// <summary>Nummer aus dem Fenster (Strg+Umschalt+Zahl in der Liste).</summary>
    class procedure AssignNumber(const AProject, AId: string; ANumber: Integer); static;
    /// <summary>IDE-Lesezeichen 1–9 von AFileName einmal je Sitzung übernehmen und dort entfernen
    /// (bookmarks.quick.importIde); AFileName muss die Datei im oberen Editor sein.</summary>
    class procedure ImportIde(const AFileName: string); static;
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
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Bookmarks.Dialog,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Bookmarks.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files;

const
  /// <summary>So lange steht ein Hinweis der schnellen Lesezeichen im Statusfeld.</summary>
  StatusMs = 4000;

{ TAtlasIdeBookmarks }

class procedure TAtlasIdeBookmarks.Start(const AMessage, AStatus: TProc<string>);
begin
  // Mehrfach aufgerufen (nach jeder Einstellungsänderung): vorhandene Listen bleiben, ApplySettings wechselt
  // bei Bedarf die Ablage.
  FMessage := AMessage;
  FStatus := AStatus;
  if FImported = nil then
    FImported := TDictionary<string, Boolean>.Create;
  if FLists = nil then
  begin
    FLists := TDictionary<string, TAtlasBookmarkList>.Create;
    FShared := TAtlasIdeSettings.Current.BookmarksShared;
  end;
  if FProjectOf = nil then
    FProjectOf := TDictionary<string, string>.Create;
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
  if Assigned(FStatus) and (FStatusAt <> 0) then
    FStatus('');
  FMessage := nil;
  FStatus := nil;
  FStatusAt := 0;
  FreeAndNil(FLists);
  FreeAndNil(FProjectOf);
  FreeAndNil(FImported);
  FWindowProject := '';
end;

class function TAtlasIdeBookmarks.Key(const APath: string): string;
begin
  Result := LowerCase(Trim(APath)).Replace('/', '\');
end;

class procedure TAtlasIdeBookmarks.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class procedure TAtlasIdeBookmarks.Status(const AText: string);
begin
  // Ohne Statusfeld (Statusleiste aus) in die Meldungsansicht.
  if not Assigned(FStatus) then
  begin
    Say(AText);
    Exit;
  end;
  FStatus(AText);
  FStatusAt := TThread.GetTickCount64;
end;

class procedure TAtlasIdeBookmarks.ExpireStatus;
begin
  if (FStatusAt = 0) or (TThread.GetTickCount64 - FStatusAt < StatusMs) then
    Exit;
  FStatusAt := 0;
  if Assigned(FStatus) then
    FStatus('');
end;

class function TAtlasIdeBookmarks.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeBookmarks.Enabled(AReport: Boolean): Boolean;
begin
  Result := (FLists <> nil) and TAtlasIdeSettings.Current.BookmarksNamed;
  if not Result and AReport and (FLists <> nil) then
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksDisabled));
end;

class function TAtlasIdeBookmarks.QuickOn(AReport: Boolean): Boolean;
begin
  Result := (FLists <> nil) and TAtlasIdeSettings.Current.QuickBookmarks;
  if not Result and AReport and (FLists <> nil) then
    Say(TAtlasStrings.Text(TAtlasTextId.QuickBookmarkDisabled));
end;

class function TAtlasIdeBookmarks.Available(AReport: Boolean): Boolean;
begin
  Result := (FLists <> nil) and (TAtlasIdeSettings.Current.BookmarksNamed or TAtlasIdeSettings.Current.QuickBookmarks);
  if not Result and AReport and (FLists <> nil) then
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksDisabled));
end;

class function TAtlasIdeBookmarks.ColumnShown: Boolean;
begin
  Result := TAtlasIdeSettings.Current.QuickBookmarks and TAtlasIdeSettings.Current.QuickBookmarksGutter;
end;

class function TAtlasIdeBookmarks.ActiveProject: string;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Project := Services.GetActiveProject;
  if Project <> nil then
    Result := Project.FileName;
end;

class function TAtlasIdeBookmarks.ResolveProject(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectOfFile(AFileName);
  if Result = '' then
    Result := ActiveProject;
  if (Result <> '') and (FProjectOf <> nil) then
    FProjectOf.AddOrSetValue(Key(AFileName), Result);
end;

class function TAtlasIdeBookmarks.CurrentProject: string;
var
  View: IOTAEditView;
begin
  Result := '';
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) and (View.Buffer.FileName <> '') then
    Result := ResolveProject(View.Buffer.FileName);
  if Result = '' then
    Result := ActiveProject;
end;

class procedure TAtlasIdeBookmarks.CheckStorage;
begin
  // Ablage umgeschaltet: Listen aus der jeweils gültigen Datei neu lesen.
  if (FLists <> nil) and (FShared <> TAtlasIdeSettings.Current.BookmarksShared) then
  begin
    FLists.Clear;
    FShared := TAtlasIdeSettings.Current.BookmarksShared;
  end;
end;

class function TAtlasIdeBookmarks.List(const AProject: string): TAtlasBookmarkList;
begin
  CheckStorage;
  if (FLists <> nil) and FLists.TryGetValue(Key(AProject), Result) then
    Exit;
  // Ohne Datei oder bei ungültigem Inhalt: leere Liste zu diesem Projekt.
  TAtlasBookmarks.Load(AProject, FShared, Result);
  if FLists <> nil then
    FLists.AddOrSetValue(Key(AProject), Result);
end;

class procedure TAtlasIdeBookmarks.Put(const AList: TAtlasBookmarkList);
begin
  if FLists <> nil then
    FLists.AddOrSetValue(Key(AList.Project), AList);
end;

class function TAtlasIdeBookmarks.Store(const AList: TAtlasBookmarkList): Boolean;
begin
  Put(AList);
  Result := TAtlasBookmarks.Save(AList, FShared);
  if not Result then
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksSaveFailed));
end;

class function TAtlasIdeBookmarks.RelocateFile(var AList: TAtlasBookmarkList; const AFileName: string): Boolean;
var
  Text: string;
begin
  Text := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  // Leer heißt: Datei fehlt (oder ist leer); ihre Lesezeichen sind dann nicht zu finden.
  if Text = '' then
    Result := AList.LoseFile(AFileName)
  else
    Result := AList.Relocate(AFileName, Text);
  if FProjectOf <> nil then
    FProjectOf.AddOrSetValue(Key(AFileName), AList.Project);
end;

class function TAtlasIdeBookmarks.RelocateAll(var AList: TAtlasBookmarkList): Boolean;
var
  FileName: string;
begin
  Result := False;
  for FileName in AList.Files do
    Result := RelocateFile(AList, FileName) or Result;
end;

class procedure TAtlasIdeBookmarks.Invalidate;
begin
  TAtlasIdeGutterMarks.Invalidate;
end;

class function TAtlasIdeBookmarks.Track(const AFileName, AText: string): Boolean;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := False;
  if not Available(False) or (AFileName = '') then
    Exit;
  Project := ResolveProject(AFileName);
  if Project = '' then
    Exit;
  // Das Seitenfenster folgt dem Projekt der Datei vorn.
  if TAtlasIdeBookmarksWindow.Visible and (Key(Project) <> Key(FWindowProject)) then
  begin
    FWindowProject := Project;
    RefreshWindow('');
  end;
  Current := List(Project);
  if Length(Current.ForFile(AFileName)) = 0 then
    Exit;
  Result := Current.Relocate(AFileName, AText);
  if not Result then
    Exit;
  Store(Current);
  RefreshWindow('');
end;

class function TAtlasIdeBookmarks.HasBookmarks(const AFileName: string): Boolean;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current) and (Length(Current.ForFile(AFileName)) > 0);
end;

class function TAtlasIdeBookmarks.BookmarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
var
  Project: string;
  Current: TAtlasBookmarkList;
  Mark: TAtlasBookmark;
begin
  Result := nil;
  if not ((FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current)) then
    Exit;
  // Schnelle Lesezeichen gehören in ihre Spalte, nummerierte benannte ebenfalls, solange sie sichtbar ist.
  for Mark in Current.AtLine(AFileName, ALine) do
    if (Mark.Kind = TAtlasBookmarkKind.Named) and not (ColumnShown and (Mark.Number > 0)) then
      Result := Result + [Mark];
end;

class function TAtlasIdeBookmarks.ColumnMarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := nil;
  if (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current) then
    Result := TAtlasQuickBookmarks.ColumnMarks(Current, AFileName, ALine);
end;

class function TAtlasIdeBookmarks.HasColumnMarks(const AFileName: string): Boolean;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current) and TAtlasQuickBookmarks.HasColumnMarks(Current, AFileName);
end;

class function TAtlasIdeBookmarks.OverviewMarks(const AFileName: string; out AMarks: TArray<TAtlasBookmark>): Boolean;
var
  Project: string;
  Current: TAtlasBookmarkList;
  Mark: TAtlasBookmark;
begin
  AMarks := nil;
  Result := QuickOn(False);
  if not Result then
    Exit;
  if (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current) then
    for Mark in Current.ForFile(AFileName) do
      if not Mark.Lost then
        AMarks := AMarks + [Mark];
end;

class function TAtlasIdeBookmarks.Target(out AFileName: string; out ALine: Integer): Boolean;
var
  View: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  Result := False;
  if not Enabled(True) then
    Exit;
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoEditor));
    Exit;
  end;
  AFileName := View.Buffer.FileName;
  // Rechtsklick in die Rinne gilt vor dem Cursor, solange er frisch ist und zur Datei passt.
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
    ALine := View.CursorPos.Line - 1;
  Result := ALine >= 0;
end;

class procedure TAtlasIdeBookmarks.AddBookmark;
var
  FileName, Project, Text, Name, Id: string;
  Line: Integer;
  Current: TAtlasBookmarkList;
begin
  if not Target(FileName, Line) then
    Exit;
  Project := ResolveProject(FileName);
  if Project = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProject));
    Exit;
  end;
  Text := TAtlasIdeWorkspaceEdit.CurrentText(FileName);
  Current := List(Project);
  // Erst wiederfinden, damit die übrigen Lesezeichen der Datei zum Text passen.
  Current.Relocate(FileName, Text);
  Name := TAtlasBookmarks.SuggestName(FileName, Text, Line);
  if not TAtlasBookmarkDialog.Execute(TAtlasStrings.Fmt(TAtlasTextId.BookmarksDialogTitle,
    [ExtractFileName(FileName), Line + 1]), Name) then
  begin
    // Abbrechen: nur das Wiederfinden behalten.
    Put(Current);
    Exit;
  end;
  Id := Current.Add(FileName, Text, Line, Name, NowUtc);
  Store(Current);
  Invalidate;
  if TAtlasIdeBookmarksWindow.Visible then
    FWindowProject := Project;
  RefreshWindow(Id);
end;

class procedure TAtlasIdeBookmarks.GoToBookmark;
var
  Project: string;
  Current: TAtlasBookmarkList;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Mark: TAtlasBookmark;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  if not Available(True) then
    Exit;
  Project := CurrentProject;
  if Project = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProject));
    Exit;
  end;
  Current := List(Project);
  if RelocateAll(Current) then
    Store(Current)
  else
    Put(Current);
  if Current.Count = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNone));
    Exit;
  end;
  // Name als Beschriftung, Ort (Datei, Zeile, Methode) als Pfad: Die Suche findet beides.
  Commands := nil;
  for Mark in Current.Bookmarks do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := Mark.Id;
    Command.Caption := Mark.DisplayName;
    if Mark.Number > 0 then
      Command.Caption := IntToStr(Mark.Number) + ' · ' + Command.Caption;
    Command.Path := TAtlasBookmarks.Location(Mark);
    if Mark.Lost then
      Command.ShortCut := TAtlasStrings.Text(TAtlasTextId.BookmarksLost);
    Command.Description := Mark.Preview;
    Commands := Commands + [Command];
  end;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Id: string;
    begin
      Id := ACommand.Id;
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          OpenBookmark(Project, Id);
        end);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

class function TAtlasIdeBookmarks.PlaceText(const AProject: string): string;
var
  Current: TAtlasBookmarkList;
begin
  if AProject = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProjectList));
  // Fußzeile: „Lesezeichen in Projekt.dproj: 5, davon 1 nicht gefunden · Lokal in …“.
  Current := List(AProject);
  Result := TAtlasStrings.Fmt(TAtlasTextId.BookmarksListTitle,
    [ExtractFileName(AProject), Current.Count, Current.LostCount]) + ' · ';
  if FShared then
    Result := Result + TAtlasStrings.Text(TAtlasTextId.BookmarksStoredShared)
  else
    Result := Result + TAtlasStrings.Text(TAtlasTextId.BookmarksStoredLocal);
end;

class procedure TAtlasIdeBookmarks.WireFrame(AFrame: TAtlasBookmarksFrame);
begin
  if AFrame = nil then
    Exit;
  AFrame.OnOpen :=
    procedure(AId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          OpenBookmark(FWindowProject, AId);
        end);
    end;
  AFrame.OnRename :=
    procedure(AId, AName: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          RenameBookmark(FWindowProject, AId, AName);
        end);
    end;
  AFrame.OnDelete :=
    procedure(AId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          DeleteBookmark(FWindowProject, AId);
        end);
    end;
  AFrame.OnNumber :=
    procedure(AId: string; ANumber: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
        procedure
        begin
          AssignNumber(FWindowProject, AId, ANumber);
        end);
    end;
  AFrame.OnMove :=
    procedure(AId, ABeforeId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          MoveBookmark(FWindowProject, AId, ABeforeId);
        end);
    end;
end;

class procedure TAtlasIdeBookmarks.RefreshWindow(const ASelectId: string);
var
  Frame: TAtlasBookmarksFrame;
  Current: TAtlasBookmarkList;
  View: IOTAEditView;
begin
  Frame := TAtlasIdeBookmarksWindow.ExistingFrame;
  if (Frame = nil) or (FLists = nil) then
    Exit;
  // „nur diese Datei“ bezieht sich auf die Datei im oberen Editor.
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) then
    Frame.SetCurrentFile(View.Buffer.FileName);
  if FWindowProject = '' then
    Current := TAtlasBookmarkList.Create('')
  else
    Current := List(FWindowProject);
  Frame.SetBookmarks(Current, PlaceText(FWindowProject), ASelectId);
end;

class procedure TAtlasIdeBookmarks.ShowWindow;
var
  Current: TAtlasBookmarkList;
  Frame: TAtlasBookmarksFrame;
begin
  if not Available(True) then
    Exit;
  FWindowProject := CurrentProject;
  if FWindowProject <> '' then
  begin
    Current := List(FWindowProject);
    if RelocateAll(Current) then
      Store(Current)
    else
      Put(Current);
  end;
  Frame := TAtlasIdeBookmarksWindow.Show;
  if Frame = nil then
    Exit;
  RefreshWindow('');
  if Frame.Filter.CanFocus then
    Frame.Filter.SetFocus;
end;

class procedure TAtlasIdeBookmarks.OpenBookmark(const AProject, AId: string);
var
  Current: TAtlasBookmarkList;
  Index: Integer;
  Mark: TAtlasBookmark;
begin
  if not Available(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  Index := Current.IndexOf(AId);
  if Index < 0 then
    Exit;
  // Unmittelbar vor dem Sprung wiederfinden: Die Datei kann sich außerhalb geändert haben.
  if RelocateFile(Current, Current.Bookmarks[Index].FileName) then
  begin
    Store(Current);
    RefreshWindow(AId);
  end
  else
    Put(Current);
  Mark := Current.Bookmarks[Index];
  if Mark.Lost then
    Say(TAtlasStrings.Fmt(TAtlasTextId.BookmarksLostJump, [Mark.DisplayName]));
  TAtlasIdeResults.Open(Mark.FileName, Mark.Line, 0);
  Invalidate;
end;

class procedure TAtlasIdeBookmarks.RenameBookmark(const AProject, AId, AName: string);
var
  Current: TAtlasBookmarkList;
begin
  if not Available(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  if not Current.Rename(AId, AName) then
    Exit;
  Store(Current);
  RefreshWindow(AId);
end;

class procedure TAtlasIdeBookmarks.DeleteBookmark(const AProject, AId: string);
var
  Current: TAtlasBookmarkList;
  Index: Integer;
begin
  if not Available(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  Index := Current.IndexOf(AId);
  if Index < 0 then
    Exit;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.BookmarksDeleteConfirm, [Current.Bookmarks[Index].DisplayName]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  Current.Remove(AId);
  Store(Current);
  Invalidate;
  RefreshWindow('');
end;

class procedure TAtlasIdeBookmarks.MoveBookmark(const AProject, AId, ABeforeId: string);
var
  Current: TAtlasBookmarkList;
begin
  if not Available(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  if not Current.MoveBefore(AId, ABeforeId) then
    Exit;
  Store(Current);
  RefreshWindow(AId);
end;

class procedure TAtlasIdeBookmarks.ApplySettings;
begin
  if FLists = nil then
    Exit;
  if not Available(False) then
  begin
    // Beide Arten aus: Fenster zu, die Rinne zeichnet nichts mehr (Wanted der Schicht).
    TAtlasIdeBookmarksWindow.Hide;
    Invalidate;
    Exit;
  end;
  // Spalte ein- oder ausgeschaltet: Die Schicht der benannten Lesezeichen zeigt nummerierte wieder bzw. nicht.
  Invalidate;
  if not QuickOn(False) and (FStatusAt <> 0) then
  begin
    FStatusAt := 0;
    if Assigned(FStatus) then
      FStatus('');
  end;
  if FShared <> TAtlasIdeSettings.Current.BookmarksShared then
  begin
    CheckStorage;
    FProjectOf.Clear;
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
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProject));
    Exit(False);
  end;
  AText := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  AList := List(AProject);
  // Erst wiederfinden, damit die Marker der Datei zum Text passen.
  AList.Relocate(AFileName, AText);
  Result := True;
end;

class function TAtlasIdeBookmarks.QuickTarget(out AFileName, AText: string; out ALine: Integer;
  out AList: TAtlasBookmarkList): Boolean;
var
  View: IOTAEditView;
  Project: string;
begin
  AFileName := '';
  AText := '';
  ALine := -1;
  AList := TAtlasBookmarkList.Create('');
  Result := False;
  if not QuickOn(True) then
    Exit;
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoEditor));
    Exit;
  end;
  AFileName := View.Buffer.FileName;
  ALine := View.CursorPos.Line - 1;
  Result := (ALine >= 0) and PrepareFile(AFileName, Project, AText, AList);
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

class function TAtlasIdeBookmarks.NumberTargets(const AFileName: string): TArray<string>;
var
  Project: string;
  Current: TAtlasBookmarkList;
  Number, Index: Integer;
  Mark: TAtlasBookmark;
begin
  SetLength(Result, TAtlasQuickBookmarks.MaxNumber + 1);
  if FLists = nil then
    Exit;
  Project := ResolveProject(AFileName);
  if Project = '' then
    Exit;
  Current := List(Project);
  for Number := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    Index := Current.IndexOfNumber(Number);
    if Index < 0 then
      Continue;
    Mark := Current.Bookmarks[Index];
    Result[Number] := ExtractFileName(Mark.FileName) + ':' + IntToStr(Mark.Line + 1) + ' ' + Mark.DisplayName;
  end;
end;

class procedure TAtlasIdeBookmarks.QuickToggle;
var
  FileName, Text: string;
  Line: Integer;
  Current: TAtlasBookmarkList;
begin
  if not QuickTarget(FileName, Text, Line, Current) then
    Exit;
  Commit(Current, TAtlasQuickBookmarks.Toggle(Current, FileName, Text, Line, NowUtc) <> TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeBookmarks.QuickSetNumber(ANumber: Integer);
var
  FileName, Text: string;
  Line: Integer;
  Current: TAtlasBookmarkList;
begin
  if not QuickTarget(FileName, Text, Line, Current) then
    Exit;
  Commit(Current, TAtlasQuickBookmarks.SetNumber(Current, FileName, Text, Line, ANumber, NowUtc) <>
    TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeBookmarks.JumpTo(var AList: TAtlasBookmarkList; const AId: string; ANumber: Integer);
var
  Index: Integer;
  Mark: TAtlasBookmark;
begin
  Index := AList.IndexOf(AId);
  if Index < 0 then
    Exit;
  // Unmittelbar vor dem Sprung wiederfinden: Die Datei kann sich außerhalb geändert haben.
  if RelocateFile(AList, AList.Bookmarks[Index].FileName) then
  begin
    Store(AList);
    RefreshWindow(AId);
  end
  else
    Put(AList);
  Mark := AList.Bookmarks[Index];
  if Mark.Lost and (ANumber > 0) then
    Status(TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkNotFound, [ANumber]));
  // Der Navigationsverlauf (#504) nimmt den Sprung wie jeden anderen auf (andere Datei oder weiter als einige
  // Zeilen).
  TAtlasIdeResults.Open(Mark.FileName, Mark.Line, 0);
  Invalidate;
end;

class procedure TAtlasIdeBookmarks.QuickJump(ANumber: Integer);
var
  Project, FileName: string;
  View: IOTAEditView;
  Current: TAtlasBookmarkList;
  Scope: TAtlasQuickScope;
  Index: Integer;
begin
  if not QuickOn(True) then
    Exit;
  Project := CurrentProject;
  if Project = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProject));
    Exit;
  end;
  FileName := '';
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) then
    FileName := View.Buffer.FileName;
  Scope := TAtlasQuickScope.Project;
  if SameText(TAtlasIdeSettings.Current.QuickBookmarksScope, 'file') then
    Scope := TAtlasQuickScope.CurrentFile;
  Current := List(Project);
  case TAtlasQuickBookmarks.Jump(Current, ANumber, FileName, Scope, Index) of
    TAtlasQuickJump.NotAssigned:
      Status(TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkNotAssigned, [ANumber]));
    TAtlasQuickJump.OtherFile:
      Status(TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkOtherFile, [ANumber]));
  else
    JumpTo(Current, Current.Bookmarks[Index].Id, ANumber);
  end;
end;

class procedure TAtlasIdeBookmarks.Step(AForward: Boolean);
var
  FileName, Text: string;
  Line, Target: Integer;
  Current: TAtlasBookmarkList;
begin
  if not QuickTarget(FileName, Text, Line, Current) then
    Exit;
  Put(Current);
  if not TAtlasQuickBookmarks.Step(Current, FileName, Line, AForward, Target) then
  begin
    Status(TAtlasStrings.Text(TAtlasTextId.QuickBookmarkNoneInFile));
    Exit;
  end;
  TAtlasIdeResults.Open(FileName, Target, 0);
end;

class procedure TAtlasIdeBookmarks.NextBookmark;
begin
  Step(True);
end;

class procedure TAtlasIdeBookmarks.PreviousBookmark;
begin
  Step(False);
end;

class procedure TAtlasIdeBookmarks.ColumnClick(const AFileName: string; ALine: Integer);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if not QuickOn(True) or not TAtlasIdeSettings.Current.QuickBookmarksGutterClick or
    not PrepareFile(AFileName, Project, Text, Current) then
    Exit;
  Commit(Current, TAtlasQuickBookmarks.Click(Current, AFileName, Text, ALine, NowUtc) <> TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeBookmarks.ColumnAssign(const AFileName: string; ALine, ANumber: Integer);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
  Marks: TArray<TAtlasBookmark>;
  Change: TAtlasQuickChange;
begin
  if not QuickOn(True) or not PrepareFile(AFileName, Project, Text, Current) then
    Exit;
  Marks := TAtlasQuickBookmarks.ColumnMarks(Current, AFileName, ALine);
  if Length(Marks) > 0 then
    Change := TAtlasQuickBookmarks.AssignNumber(Current, Marks[0].Id, ANumber)
  else
    Change := TAtlasQuickBookmarks.SetNumber(Current, AFileName, Text, ALine, ANumber, NowUtc);
  Commit(Current, Change <> TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeBookmarks.ColumnName(const AFileName: string; ALine: Integer);
var
  Project, Text, Name, Id: string;
  Current: TAtlasBookmarkList;
  Marks: TArray<TAtlasBookmark>;
begin
  if not QuickOn(True) or not PrepareFile(AFileName, Project, Text, Current) then
    Exit;
  Marks := TAtlasQuickBookmarks.ColumnMarks(Current, AFileName, ALine);
  if Length(Marks) > 0 then
    Name := Marks[0].DisplayName
  else
    Name := TAtlasBookmarks.SuggestName(AFileName, Text, ALine);
  if not TAtlasBookmarkDialog.Execute(TAtlasStrings.Fmt(TAtlasTextId.BookmarksDialogTitle,
    [ExtractFileName(AFileName), ALine + 1]), Name) then
  begin
    Put(Current);
    Exit;
  end;
  // Umbenennen macht aus dem schnellen ein benanntes Lesezeichen; die Nummer bleibt.
  if Length(Marks) > 0 then
  begin
    Id := Marks[0].Id;
    Current.Rename(Id, Name);
  end
  else
    Id := Current.Add(AFileName, Text, ALine, Name, NowUtc);
  Commit(Current, True, Id);
end;

class procedure TAtlasIdeBookmarks.ColumnRemove(const AFileName: string; ALine: Integer);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if not QuickOn(True) or not PrepareFile(AFileName, Project, Text, Current) then
    Exit;
  Commit(Current, TAtlasQuickBookmarks.RemoveAt(Current, AFileName, ALine) > 0, '');
end;

class procedure TAtlasIdeBookmarks.ColumnRemoveFile(const AFileName: string);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if not QuickOn(True) or not PrepareFile(AFileName, Project, Text, Current) then
    Exit;
  Commit(Current, TAtlasQuickBookmarks.RemoveFile(Current, AFileName) > 0, '');
end;

class procedure TAtlasIdeBookmarks.AssignNumber(const AProject, AId: string; ANumber: Integer);
var
  Current: TAtlasBookmarkList;
begin
  if not QuickOn(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  Commit(Current, TAtlasQuickBookmarks.AssignNumber(Current, AId, ANumber) <> TAtlasQuickChange.None, AId);
end;

class procedure TAtlasIdeBookmarks.ImportIde(const AFileName: string);
var
  View: IOTAEditView;
  Marks: TArray<TAtlasIdeBookmarkPos>;
  Taken: TArray<Integer>;
  Number, Top, Left: Integer;
  Position: TOTACharPos;
  Saved, Place: TOTAEditPos;
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if (FImported = nil) or not QuickOn(False) or not TAtlasIdeSettings.Current.QuickBookmarksImportIde or
    (AFileName = '') or FImported.ContainsKey(Key(AFileName)) then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, AFileName) then
    Exit;
  // Einmal je Datei und Sitzung: Später gesetzte IDE-Lesezeichen (etwa mit Strg+Umschalt+0) bleiben bei der IDE.
  FImported.Add(Key(AFileName), True);
  Marks := nil;
  for Number := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    Position := View.BookmarkPos[Number];
    if Position.Line > 0 then
      Marks := Marks + [TAtlasIdeBookmarkPos.Create(Number, Position.Line - 1)];
  end;
  if (Length(Marks) = 0) or not PrepareFile(AFileName, Project, Text, Current) then
    Exit;
  Taken := TAtlasQuickBookmarks.Import(Current, AFileName, Text, Marks, NowUtc);
  if Length(Taken) = 0 then
  begin
    Put(Current);
    Exit;
  end;
  if not Store(Current) then
    Exit;
  // In der IDE entfernen, damit kein doppeltes Symbol bleibt: BookmarkToggle wirkt an der Schreibmarke, also
  // kurz an die Zeile des Lesezeichens und zurück, ohne dass die Ansicht springt.
  Saved := View.CursorPos;
  Top := View.TopRow;
  Left := View.LeftColumn;
  for Number in Taken do
  begin
    Position := View.BookmarkPos[Number];
    if Position.Line <= 0 then
      Continue;
    Place.Line := Position.Line;
    Place.Col := Position.CharIndex + 1;
    View.CursorPos := Place;
    View.BookmarkToggle(Number);
  end;
  View.CursorPos := Saved;
  View.SetTopLeft(Top, Left);
  View.Paint;
  Say(TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkImported, [Length(Taken), ExtractFileName(AFileName)]));
  Invalidate;
  RefreshWindow('');
end;

class procedure TAtlasIdeBookmarks.ThemeChanged;
begin
  TAtlasIdeBookmarksWindow.ApplyTheme;
end;

end.
