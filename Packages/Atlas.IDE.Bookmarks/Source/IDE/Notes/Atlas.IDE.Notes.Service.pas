unit Atlas.IDE.Notes.Service;

// Persönliche Notizen an Codezeilen (#545), IDE-Seite: hält je Projekt ein
// Notizbuch (TAtlasNoteBook) im Speicher, liest und schreibt es unter
// %LOCALAPPDATA%\Atlas\Notes\<Schlüssel>.json (TAtlasNotes, nie im Projekt-
// oder Repository-Ordner) und führt die Befehle aus:
// - „Notiz an dieser Zeile…“: Dialog für die Zeile, die zuletzt per Rechtsklick
//   in der Rinne gewählt wurde (TAtlasIdeGutterMarks.TakeLine: höchstens eine
//   Minute alt, gleiche Datei), sonst für die Cursorzeile. Gibt es dort schon eine Notiz, wird sie
//   bearbeitet.
// - „Notiz an dieser Zeile löschen“ mit Rückfrage.
// - „Notizen des Projekts“: verankert alle Notizen gegen den aktuellen Text
//   (offener Puffer, sonst Platte; fehlende Datei = verwaist), speichert und
//   zeigt die Liste im Ergebnisfenster (#400). Bearbeiten und Löschen dort
//   gehen an EditNote und DeleteNote.
// Das Projekt einer Datei ist das Projekt der Projektgruppe, das sie enthält,
// sonst das aktive Projekt. Meldungen nur als Zeile in der Meldungsansicht.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Notes.Store;

type
  TAtlasIdeNotes = class
  private class var
    FBooks: TDictionary<string, TAtlasNoteBook>;
    /// <summary>Datei (klein) → Projekt; gefüllt von Track und den Befehlen.</summary>
    FProjectOf: TDictionary<string, string>;
    FFolder: string;
    FMessage: TProc<string>;
    /// <summary>Projekt der zuletzt gezeigten Liste.</summary>
    FListProject: string;
  private
    class function Key(const APath: string): string; static;
    class procedure Say(const AText: string); static;
    class function NowUtc: TDateTime; static;
    class function ResolveProject(const AFileName: string): string; static;
    class function ActiveProject: string; static;
    class function Book(const AProject: string): TAtlasNoteBook; static;
    class procedure Put(const ABook: TAtlasNoteBook); static;
    class function Store(const ABook: TAtlasNoteBook): Boolean; static;
    /// <summary>Datei und Zeile (0-basiert) für die Befehle; False mit Meldung.</summary>
    class function Target(out AFileName: string; out ALine: Integer): Boolean; static;
    class function CurrentLines(const AFileName: string): TArray<string>; static;
    class function Confirm(const ANote: TAtlasNote): Boolean; static;
    class procedure RefreshList(const ASelectId: string); static;
    class procedure Invalidate; static;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    /// <summary>Ordner der Notizbücher; Vorgabe TAtlasNotes.DefaultFolder.</summary>
    class property Folder: string read FFolder write FFolder;
    /// <summary>Oberer Editor zeigt AFileName mit AText: Projekt merken und dessen Notizen der Datei neu
    /// verankern (gespeichert, wenn sich etwas ändert). True, wenn sich Notizen bewegt haben.</summary>
    class function Track(const AFileName, AText: string): Boolean; static;
    /// <summary>Hat AFileName Notizen (aus dem Speicher, ohne IDE-Aufrufe; erst nach Track bekannt)?</summary>
    class function HasNotes(const AFileName: string): Boolean; static;
    /// <summary>Nicht verwaiste Notizen an ALine (0-basiert); ohne IDE-Aufrufe, zum Zeichnen.</summary>
    class function NotesAt(const AFileName: string; ALine: Integer): TArray<TAtlasNote>; static;
    /// <summary>Notiz an der Zeile anlegen oder bearbeiten (Dialog).</summary>
    class procedure AddOrEdit; static;
    /// <summary>Notiz an der Zeile löschen (mit Rückfrage).</summary>
    class procedure DeleteAtLine; static;
    /// <summary>Liste aller Notizen des Projekts im Ergebnisfenster.</summary>
    class procedure ShowList; static;
    /// <summary>Notiz der Liste bearbeiten bzw. löschen.</summary>
    class procedure EditNote(const AId: string); static;
    class procedure DeleteNote(const AId: string); static;
  end;

implementation

uses
  Atlas.IDE.Foundation.EditorBuffer,
  System.Classes,
  System.DateUtils,
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Bookmarks.Strings,
  Atlas.UI.Notes.Dialog,
  Atlas.UI.Notes.List,
  Atlas.UI.Results.Frame,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.EditorRefresh;

/// <summary>Liste der Notizen für das Ergebnisfenster mit Bearbeiten und Löschen.</summary>
function ListOf(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>;
  const ASelectId: string): TAtlasResultsItemList;
begin
  Result := TAtlasNotesList.Build(ATitle, AGroups, ASelectId,
    procedure(const ANoteId: string)
    begin
      TAtlasIdeNotes.EditNote(ANoteId);
    end,
    procedure(const ANoteId: string)
    begin
      TAtlasIdeNotes.DeleteNote(ANoteId);
    end);
end;

{ TAtlasIdeNotes }

class procedure TAtlasIdeNotes.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FFolder = '' then
  begin
    FFolder := TAtlasNotes.DefaultFolder;
  end;
  if FBooks = nil then
  begin
    FBooks := TDictionary<string, TAtlasNoteBook>.Create;
  end;
  if FProjectOf = nil then
  begin
    FProjectOf := TDictionary<string, string>.Create;
  end;
end;

class procedure TAtlasIdeNotes.Release;
begin
  // Die Liste im Ergebnisfenster darf das Modul danach nicht mehr erreichen (Regel 3).
  TAtlasIdeResultsWindow.ReleaseItems(TAtlasNotesList.Owner);
  FMessage := nil;
  FreeAndNil(FBooks);
  FreeAndNil(FProjectOf);
  FListProject := '';
end;

class function TAtlasIdeNotes.Key(const APath: string): string;
begin
  Result := LowerCase(Trim(APath)).Replace('/', '\');
end;

class procedure TAtlasIdeNotes.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeNotes.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeNotes.ActiveProject: string;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
  begin
    Exit;
  end;
  Project := Services.GetActiveProject;
  if Project <> nil then
  begin
    Result := Project.FileName;
  end;
end;

class function TAtlasIdeNotes.ResolveProject(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectOfFile(AFileName);
  if Result = '' then
  begin
    Result := ActiveProject;
  end;
  if (Result <> '') and (FProjectOf <> nil) then
  begin
    FProjectOf.AddOrSetValue(Key(AFileName), Result);
  end;
end;

class function TAtlasIdeNotes.Book(const AProject: string): TAtlasNoteBook;
begin
  if (FBooks <> nil) and FBooks.TryGetValue(Key(AProject), Result) then
  begin
    Exit;
  end;
  // Ohne Datei oder bei ungültigem Inhalt: leeres Buch zu diesem Projekt.
  TAtlasNotes.Load(FFolder, AProject, Result);
  if FBooks <> nil then
  begin
    FBooks.AddOrSetValue(Key(AProject), Result);
  end;
end;

class procedure TAtlasIdeNotes.Put(const ABook: TAtlasNoteBook);
begin
  if FBooks <> nil then
  begin
    FBooks.AddOrSetValue(Key(ABook.Project), ABook);
  end;
end;

class function TAtlasIdeNotes.Store(const ABook: TAtlasNoteBook): Boolean;
begin
  Put(ABook);
  Result := (FFolder <> '') and TAtlasNotes.Save(FFolder, ABook);
  if not Result then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesSaveFailed));
  end;
end;

class function TAtlasIdeNotes.CurrentLines(const AFileName: string): TArray<string>;
begin
  Result := TAtlasLineAnchors.Lines(TAtlasIdeWorkspaceEdit.CurrentText(AFileName));
end;

class procedure TAtlasIdeNotes.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

class function TAtlasIdeNotes.Track(const AFileName, AText: string): Boolean;
var
  Project: string;
  Current: TAtlasNoteBook;
begin
  Result := False;
  if (FBooks = nil) or (AFileName = '') then
  begin
    Exit;
  end;
  Project := ResolveProject(AFileName);
  if Project = '' then
  begin
    Exit;
  end;
  Current := Book(Project);
  if Length(Current.ForFile(AFileName)) = 0 then
  begin
    Exit;
  end;
  Result := Current.Relocate(AFileName, TAtlasLineAnchors.Lines(AText));
  if Result then
  begin
    Store(Current);
  end;
end;

class function TAtlasIdeNotes.HasNotes(const AFileName: string): Boolean;
var
  Project: string;
  Current: TAtlasNoteBook;
begin
  Result := (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FBooks.TryGetValue(Key(Project), Current) and (Length(Current.ForFile(AFileName)) > 0);
end;

class function TAtlasIdeNotes.NotesAt(const AFileName: string; ALine: Integer): TArray<TAtlasNote>;
var
  Project: string;
  Current: TAtlasNoteBook;
begin
  Result := nil;
  if (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FBooks.TryGetValue(Key(Project), Current) then
  begin
    Result := Current.AtLine(AFileName, ALine);
  end;
end;

class function TAtlasIdeNotes.Target(out AFileName: string; out ALine: Integer): Boolean;
var
  View: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  Result := False;
  if FBooks = nil then
  begin
    Exit;
  end;
  if not TAtlasIdeSettings.Current.Notes then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDisabled));
    Exit;
  end;
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoEditor));
    Exit;
  end;
  AFileName := View.Buffer.FileName;
  // Rechtsklick in die Rinne (#545) gilt vor dem Cursor, solange er frisch ist und zur Datei passt.
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := View.CursorPos.Line - 1;
  end;
  Result := ALine >= 0;
end;

class function TAtlasIdeNotes.Confirm(const ANote: TAtlasNote): Boolean;
begin
  Result := MessageDlg(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesDeleteConfirm, [ANote.Title]),
    mtConfirmation,
    [mbYes, mbNo], 0) = mrYes;
end;

class procedure TAtlasIdeNotes.AddOrEdit;
var
  FileName, Project, Text: string;
  Line, Index: Integer;
  Lines: TArray<string>;
  Current: TAtlasNoteBook;
  Choice: TAtlasNoteChoice;
begin
  if not Target(FileName, Line) then
  begin
    Exit;
  end;
  Project := ResolveProject(FileName);
  if Project = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoProject));
    Exit;
  end;
  Lines := CurrentLines(FileName);
  Current := Book(Project);
  // Erst neu verankern, damit die Notiz an dieser Zeile gefunden wird.
  Current.Relocate(FileName, Lines);
  Index := Current.IndexAt(FileName, Line);
  Text := '';
  if Index >= 0 then
  begin
    Text := Current.Notes[Index].Text;
  end;
  Choice := TAtlasNoteDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesDialogTitle,
    [ExtractFileName(FileName), Line + 1]), Text, Index >= 0);
  case Choice of
    TAtlasNoteChoice.Save:
      if Index >= 0 then
      begin
        Current.SetText(Current.Notes[Index].Id, Text, NowUtc);
      end
      else
      begin
        Current.Add(FileName, Lines, Line, Text, NowUtc);
      end;
    TAtlasNoteChoice.Delete:
      if Index >= 0 then
      begin
        Current.Remove(Current.Notes[Index].Id);
      end;
  else
    // Abbrechen: nur die neue Verankerung behalten.
    Put(Current);
    Exit;
  end;
  Store(Current);
  Invalidate;
  RefreshList('');
end;

class procedure TAtlasIdeNotes.DeleteAtLine;
var
  FileName, Project: string;
  Line, Index: Integer;
  Current: TAtlasNoteBook;
begin
  if not Target(FileName, Line) then
  begin
    Exit;
  end;
  Project := ResolveProject(FileName);
  if Project = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoProject));
    Exit;
  end;
  Current := Book(Project);
  Current.Relocate(FileName, CurrentLines(FileName));
  Put(Current);
  Index := Current.IndexAt(FileName, Line);
  if Index < 0 then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNone));
    Exit;
  end;
  if not Confirm(Current.Notes[Index]) then
  begin
    Exit;
  end;
  Current.Remove(Current.Notes[Index].Id);
  Store(Current);
  Invalidate;
  RefreshList('');
end;

// Projekt der Liste: das der Datei im Editor, sonst das aktive. Auch aus Palette und Menü, wenn der Fokus nicht
// im Editor liegt.
function ListProject: string;
var
  mView: IOTAEditView;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and (mView.Buffer.FileName <> '') then
  begin
    Result := TAtlasIdeNotes.ResolveProject(mView.Buffer.FileName);
  end;
  if Result = '' then
  begin
    Result := TAtlasIdeNotes.ActiveProject;
  end;
end;

// Notizen aller Dateien des Notizbuchs an den aktuellen Text anpassen; True, wenn sich etwas geändert hat.
function RelocateBook(var ABook: TAtlasNoteBook; const AProject: string): Boolean;
var
  mFileName, mText: string;
begin
  Result := False;
  for mFileName in ABook.Files do
  begin
    mText := TAtlasIdeWorkspaceEdit.CurrentText(mFileName);
    // Leer heißt: Datei fehlt (oder ist leer); ihre Notizen sind dann nicht zuordenbar.
    if mText = '' then
    begin
      Result := ABook.OrphanFile(mFileName) or Result;
    end
    else
    begin
      Result := ABook.Relocate(mFileName, TAtlasLineAnchors.Lines(mText)) or Result;
    end;
    if TAtlasIdeNotes.FProjectOf <> nil then
    begin
      TAtlasIdeNotes.FProjectOf.AddOrSetValue(TAtlasIdeNotes.Key(mFileName), AProject);
    end;
  end;
end;

class procedure TAtlasIdeNotes.ShowList;
var
  Project: string;
  Current: TAtlasNoteBook;
begin
  if FBooks = nil then
  begin
    Exit;
  end;
  if not TAtlasIdeSettings.Current.Notes then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDisabled));
    Exit;
  end;
  Project := ListProject;
  if Project = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoProject));
    Exit;
  end;
  Current := Book(Project);
  if RelocateBook(Current, Project) then
  begin
    Store(Current);
  end
  else
  begin
    Put(Current);
  end;
  FListProject := Project;
  TAtlasIdeResultsWindow.ShowItems(ListOf(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesListTitle,
    [ExtractFileName(Project), Current.Count, Current.OrphanCount]), Current.Groups, ''));
end;

class procedure TAtlasIdeNotes.RefreshList(const ASelectId: string);
var
  Frame: TAtlasResultsFrame;
  Current: TAtlasNoteBook;
begin
  Frame := TAtlasIdeResultsWindow.ExistingFrame;
  // Nur, wenn das Fenster gerade die Notizen zeigt; sonst bleibt seine Liste.
  if (Frame = nil) or (FListProject = '') or not Frame.ShowsItemsOf(TAtlasNotesList.Owner) then
  begin
    Exit;
  end;
  Current := Book(FListProject);
  Frame.ShowItems(ListOf(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesListTitle,
    [ExtractFileName(FListProject), Current.Count, Current.OrphanCount]), Current.Groups, ASelectId));
end;

class procedure TAtlasIdeNotes.EditNote(const AId: string);
var
  Current: TAtlasNoteBook;
  Index: Integer;
  Text: string;
  Note: TAtlasNote;
begin
  if (FBooks = nil) or (FListProject = '') then
  begin
    Exit;
  end;
  Current := Book(FListProject);
  Index := Current.IndexOf(AId);
  if Index < 0 then
  begin
    Exit;
  end;
  Note := Current.Notes[Index];
  Text := Note.Text;
  case TAtlasNoteDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesDialogTitle,
    [ExtractFileName(Note.FileName), Note.Line + 1]), Text, True) of
    TAtlasNoteChoice.Save:
      Current.SetText(AId, Text, NowUtc);
    TAtlasNoteChoice.Delete:
      Current.Remove(AId);
  else
    Exit;
  end;
  Store(Current);
  Invalidate;
  RefreshList(AId);
end;

class procedure TAtlasIdeNotes.DeleteNote(const AId: string);
var
  Current: TAtlasNoteBook;
  Index: Integer;
begin
  if (FBooks = nil) or (FListProject = '') then
  begin
    Exit;
  end;
  Current := Book(FListProject);
  Index := Current.IndexOf(AId);
  if (Index < 0) or not Confirm(Current.Notes[Index]) then
  begin
    Exit;
  end;
  Current.Remove(AId);
  Store(Current);
  Invalidate;
  RefreshList('');
end;

end.
