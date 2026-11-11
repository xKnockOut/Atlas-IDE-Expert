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
  Atlas.UI.Bookmarks.Strings,
  Atlas.UI.Notes.Dialog,
  Atlas.UI.Notes.List,
  Atlas.UI.Results.Items,
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
  TAtlasIdeResultsWindow.ReleaseItems(TAtlasNotesList.cOwner);
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

class function TAtlasIdeNotes.ResolveProject(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectOfFile(AFileName);
  if Result = '' then
  begin
    Result := TAtlasIdeFiles.ActiveProjectFile;
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
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasIdeNotes.Track(const AFileName, AText: string): Boolean;
var
  mProject: string;
  mCurrent: TAtlasNoteBook;
begin
  Result := False;
  if (FBooks = nil) or (AFileName = '') then
  begin
    Exit;
  end;
  mProject := ResolveProject(AFileName);
  if mProject = '' then
  begin
    Exit;
  end;
  mCurrent := Book(mProject);
  if Length(mCurrent.ForFile(AFileName)) = 0 then
  begin
    Exit;
  end;
  Result := mCurrent.Relocate(AFileName, TAtlasLineAnchors.Lines(AText));
  if Result then
  begin
    Store(mCurrent);
  end;
end;

class function TAtlasIdeNotes.HasNotes(const AFileName: string): Boolean;
var
  mProject: string;
  mCurrent: TAtlasNoteBook;
begin
  Result := (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), mProject) and
    FBooks.TryGetValue(Key(mProject), mCurrent) and (Length(mCurrent.ForFile(AFileName)) > 0);
end;

class function TAtlasIdeNotes.NotesAt(const AFileName: string; ALine: Integer): TArray<TAtlasNote>;
var
  mProject: string;
  mCurrent: TAtlasNoteBook;
begin
  Result := nil;
  if (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), mProject) and
    FBooks.TryGetValue(Key(mProject), mCurrent) then
  begin
    Result := mCurrent.AtLine(AFileName, ALine);
  end;
end;

class function TAtlasIdeNotes.Target(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
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
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoEditor));
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  // Rechtsklick in die Rinne (#545) gilt vor dem Cursor, solange er frisch ist und zur Datei passt.
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
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
  mFileName, mProject, mText: string;
  mLine, mIndex: Integer;
  mLines: TArray<string>;
  mCurrent: TAtlasNoteBook;
  mChoice: TAtlasNoteChoice;
begin
  if not Target(mFileName, mLine) then
  begin
    Exit;
  end;
  mProject := ResolveProject(mFileName);
  if mProject = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoProject));
    Exit;
  end;
  mLines := CurrentLines(mFileName);
  mCurrent := Book(mProject);
  // Erst neu verankern, damit die Notiz an dieser Zeile gefunden wird.
  mCurrent.Relocate(mFileName, mLines);
  mIndex := mCurrent.IndexAt(mFileName, mLine);
  mText := '';
  if mIndex >= 0 then
  begin
    mText := mCurrent.Notes[mIndex].Text;
  end;
  mChoice := TAtlasNoteDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesDialogTitle,
    [ExtractFileName(mFileName), mLine + 1]), mText, mIndex >= 0);
  case mChoice of
    TAtlasNoteChoice.Save:
      if mIndex >= 0 then
      begin
        mCurrent.SetText(mCurrent.Notes[mIndex].Id, mText, NowUtc);
      end
      else
      begin
        mCurrent.Add(mFileName, mLines, mLine, mText, NowUtc);
      end;
    TAtlasNoteChoice.Delete:
      if mIndex >= 0 then
      begin
        mCurrent.Remove(mCurrent.Notes[mIndex].Id);
      end;
  else
    // Abbrechen: nur die neue Verankerung behalten.
    Put(mCurrent);
    Exit;
  end;
  Store(mCurrent);
  Invalidate;
  RefreshList('');
end;

class procedure TAtlasIdeNotes.DeleteAtLine;
var
  mFileName, mProject: string;
  mLine, mIndex: Integer;
  mCurrent: TAtlasNoteBook;
begin
  if not Target(mFileName, mLine) then
  begin
    Exit;
  end;
  mProject := ResolveProject(mFileName);
  if mProject = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoProject));
    Exit;
  end;
  mCurrent := Book(mProject);
  mCurrent.Relocate(mFileName, CurrentLines(mFileName));
  Put(mCurrent);
  mIndex := mCurrent.IndexAt(mFileName, mLine);
  if mIndex < 0 then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNone));
    Exit;
  end;
  if not Confirm(mCurrent.Notes[mIndex]) then
  begin
    Exit;
  end;
  mCurrent.Remove(mCurrent.Notes[mIndex].Id);
  Store(mCurrent);
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
    Result := TAtlasIdeFiles.ActiveProjectFile;
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
  mProject: string;
  mCurrent: TAtlasNoteBook;
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
  mProject := ListProject;
  if mProject = '' then
  begin
    Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesNoProject));
    Exit;
  end;
  mCurrent := Book(mProject);
  if RelocateBook(mCurrent, mProject) then
  begin
    Store(mCurrent);
  end
  else
  begin
    Put(mCurrent);
  end;
  FListProject := mProject;
  TAtlasIdeResultsWindow.ShowItems(ListOf(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesListTitle,
    [ExtractFileName(mProject), mCurrent.Count, mCurrent.OrphanCount]), mCurrent.Groups, ''));
end;

class procedure TAtlasIdeNotes.RefreshList(const ASelectId: string);
var
  mFrame: TAtlasResultsFrame;
  mCurrent: TAtlasNoteBook;
begin
  mFrame := TAtlasIdeResultsWindow.ExistingFrame;
  // Nur, wenn das Fenster gerade die Notizen zeigt; sonst bleibt seine Liste.
  if (mFrame = nil) or (FListProject = '') or not mFrame.Items.ShowsItemsOf(TAtlasNotesList.cOwner) then
  begin
    Exit;
  end;
  mCurrent := Book(FListProject);
  mFrame.Items.Show(ListOf(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesListTitle,
    [ExtractFileName(FListProject), mCurrent.Count, mCurrent.OrphanCount]), mCurrent.Groups, ASelectId));
end;

class procedure TAtlasIdeNotes.EditNote(const AId: string);
var
  mCurrent: TAtlasNoteBook;
  mIndex: Integer;
  mText: string;
  mNote: TAtlasNote;
begin
  if (FBooks = nil) or (FListProject = '') then
  begin
    Exit;
  end;
  mCurrent := Book(FListProject);
  mIndex := mCurrent.IndexOf(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mNote := mCurrent.Notes[mIndex];
  mText := mNote.Text;
  case TAtlasNoteDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.NotesDialogTitle,
    [ExtractFileName(mNote.FileName), mNote.Line + 1]), mText, True) of
    TAtlasNoteChoice.Save:
      mCurrent.SetText(AId, mText, NowUtc);
    TAtlasNoteChoice.Delete:
      mCurrent.Remove(AId);
  else
    Exit;
  end;
  Store(mCurrent);
  Invalidate;
  RefreshList(AId);
end;

class procedure TAtlasIdeNotes.DeleteNote(const AId: string);
var
  mCurrent: TAtlasNoteBook;
  mIndex: Integer;
begin
  if (FBooks = nil) or (FListProject = '') then
  begin
    Exit;
  end;
  mCurrent := Book(FListProject);
  mIndex := mCurrent.IndexOf(AId);
  if (mIndex < 0) or not Confirm(mCurrent.Notes[mIndex]) then
  begin
    Exit;
  end;
  mCurrent.Remove(AId);
  Store(mCurrent);
  Invalidate;
  RefreshList('');
end;

end.
