unit Atlas.IDE.Bookmarks.QuickService;

// Schnelle Lesezeichen (#1104), IDE-Seite: die Befehle Strg+Umschalt+K
// (QuickToggle), Strg+Umschalt+1…9 (QuickSetNumber), Strg+1…9 (QuickJump,
// projektweit oder nur in der Datei; Hinweise im Statusfeld), nächstes und
// voriges Lesezeichen, die Befehle der Spalte links der Zeilennummern
// (Column…) und die Übernahme der IDE-Lesezeichen 1–9 beim ersten Öffnen
// einer Datei (ImportIde). Aus Atlas.IDE.Bookmarks.Service gelöst; Listen,
// Ablage, Seitenfenster und Meldungen bleiben dort (TAtlasIdeBookmarks).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Bookmarks.Store;

type
  TAtlasIdeQuickBookmarks = class
  private
    /// <summary>Datei und Zeile (0-basiert) der Schreibmarke für die schnellen Lesezeichen samt Liste.</summary>
    class function QuickTarget(out AFileName, AText: string; out ALine: Integer;
      out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Zum Lesezeichen AId springen; ANumber > 0: Hinweis „Lesezeichen N nicht gefunden“.</summary>
    class procedure JumpTo(var AList: TAtlasBookmarkList; const AId: string; ANumber: Integer); static;
    class procedure Step(AForward: Boolean); static;
  public
    /// <summary>Marker der Spalte an ALine (0-basiert), gefunden; ohne IDE-Aufrufe, zum Zeichnen.</summary>
    class function ColumnMarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>; static;
    /// <summary>Datei hat Marker für die Spalte (aus dem Speicher; erst nach Track bekannt).</summary>
    class function HasColumnMarks(const AFileName: string): Boolean; static;
    /// <summary>Nummer, die ein Klick in die Spalte jetzt vergäbe (1–9, 0 = alle belegt).</summary>
    class function NextNumber(const AFileName: string): Integer; static;
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
    /// <summary>IDE-Lesezeichen 1–9 von AFileName einmal je Sitzung übernehmen und dort entfernen
    /// (bookmarks.quick.importIde); AFileName muss die Datei im oberen Editor sein.</summary>
    class procedure ImportIde(const AFileName: string); static;
  end;

implementation

uses
  System.DateUtils,
  ToolsAPI,
  Atlas.Core.Bookmarks.Quick,
  Atlas.UI.Bookmarks.Strings,
  Atlas.UI.Bookmarks.Dialog,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Bookmarks.Service;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

{ TAtlasIdeQuickBookmarks }

class function TAtlasIdeQuickBookmarks.ColumnMarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
var
  Current: TAtlasBookmarkList;
begin
  Result := nil;
  if TAtlasIdeBookmarks.LoadedList(AFileName, Current) then
  begin
    Result := TAtlasQuickBookmarks.ColumnMarks(Current, AFileName, ALine);
  end;
end;

class function TAtlasIdeQuickBookmarks.NextNumber(const AFileName: string): Integer;
var
  Current: TAtlasBookmarkList;
begin
  Result := 1;
  if TAtlasIdeBookmarks.LoadedList(AFileName, Current) then
  begin
    Result := TAtlasQuickBookmarks.FreeNumber(Current);
  end;
end;

class function TAtlasIdeQuickBookmarks.HasColumnMarks(const AFileName: string): Boolean;
var
  Current: TAtlasBookmarkList;
begin
  Result := TAtlasIdeBookmarks.LoadedList(AFileName, Current) and
    TAtlasQuickBookmarks.HasColumnMarks(Current, AFileName);
end;

class function TAtlasIdeQuickBookmarks.OverviewMarks(const AFileName: string;
  out AMarks: TArray<TAtlasBookmark>): Boolean;
var
  Current: TAtlasBookmarkList;
  Mark: TAtlasBookmark;
begin
  AMarks := nil;
  Result := TAtlasIdeBookmarks.QuickOn(False);
  if not Result then
  begin
    Exit;
  end;
  if TAtlasIdeBookmarks.LoadedList(AFileName, Current) then
  begin
    for Mark in Current.ForFile(AFileName) do
    begin
      if not Mark.Lost then
      begin
        AMarks := AMarks + [Mark];
      end;
    end;
  end;
end;

class function TAtlasIdeQuickBookmarks.QuickTarget(out AFileName, AText: string; out ALine: Integer;
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
  if not TAtlasIdeBookmarks.QuickOn(True) then
  begin
    Exit;
  end;
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoEditor));
    Exit;
  end;
  AFileName := View.Buffer.FileName;
  ALine := View.CursorPos.Line - 1;
  Result := (ALine >= 0) and TAtlasIdeBookmarks.PrepareFile(AFileName, Project, AText, AList);
end;

class function TAtlasIdeQuickBookmarks.NumberTargets(const AFileName: string): TArray<string>;
var
  Project: string;
  Current: TAtlasBookmarkList;
  Number, Index: Integer;
  Mark: TAtlasBookmark;
begin
  SetLength(Result, TAtlasQuickBookmarks.MaxNumber + 1);
  if not TAtlasIdeBookmarks.Running then
  begin
    Exit;
  end;
  Project := TAtlasIdeBookmarks.ResolveProject(AFileName);
  if Project = '' then
  begin
    Exit;
  end;
  Current := TAtlasIdeBookmarks.List(Project);
  for Number := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    Index := Current.IndexOfNumber(Number);
    if Index < 0 then
    begin
      Continue;
    end;
    Mark := Current.Bookmarks[Index];
    Result[Number] := ExtractFileName(Mark.FileName) + ':' + IntToStr(Mark.Line + 1) + ' ' + Mark.DisplayName;
  end;
end;

class procedure TAtlasIdeQuickBookmarks.QuickToggle;
var
  FileName, Text: string;
  Line: Integer;
  Current: TAtlasBookmarkList;
begin
  if not QuickTarget(FileName, Text, Line, Current) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(Current, TAtlasQuickBookmarks.Toggle(Current, FileName, Text, Line, NowUtc) <>
    TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.QuickSetNumber(ANumber: Integer);
var
  FileName, Text: string;
  Line: Integer;
  Current: TAtlasBookmarkList;
begin
  if not QuickTarget(FileName, Text, Line, Current) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(Current, TAtlasQuickBookmarks.SetNumber(Current, FileName, Text, Line, ANumber, NowUtc) <>
    TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.JumpTo(var AList: TAtlasBookmarkList; const AId: string; ANumber: Integer);
var
  Index: Integer;
  Mark: TAtlasBookmark;
begin
  Index := AList.IndexOf(AId);
  if Index < 0 then
  begin
    Exit;
  end;
  // Unmittelbar vor dem Sprung wiederfinden: Die Datei kann sich außerhalb geändert haben.
  if TAtlasIdeBookmarks.RelocateFile(AList, AList.Bookmarks[Index].FileName) then
  begin
    TAtlasIdeBookmarks.Store(AList);
    TAtlasIdeBookmarks.RefreshWindow(AId);
  end
  else
  begin
    TAtlasIdeBookmarks.Put(AList);
  end;
  Mark := AList.Bookmarks[Index];
  if Mark.Lost and (ANumber > 0) then
  begin
    TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkNotFound, [ANumber]));
  end;
  // Der Navigationsverlauf (#504) nimmt den Sprung wie jeden anderen auf (andere Datei oder weiter als einige
  // Zeilen).
  TAtlasIdeResults.Open(Mark.FileName, Mark.Line, 0);
  TAtlasIdeBookmarks.Invalidate;
end;

class procedure TAtlasIdeQuickBookmarks.QuickJump(ANumber: Integer);
var
  Project, FileName: string;
  View: IOTAEditView;
  Current: TAtlasBookmarkList;
  Scope: TAtlasQuickScope;
  Index: Integer;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) then
  begin
    Exit;
  end;
  Project := TAtlasIdeBookmarks.CurrentProject;
  if Project = '' then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoProject));
    Exit;
  end;
  FileName := '';
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) then
  begin
    FileName := View.Buffer.FileName;
  end;
  Scope := TAtlasQuickScope.Project;
  if SameText(TAtlasIdeSettings.Current.QuickBookmarksScope, 'file') then
  begin
    Scope := TAtlasQuickScope.CurrentFile;
  end;
  Current := TAtlasIdeBookmarks.List(Project);
  case TAtlasQuickBookmarks.Jump(Current, ANumber, FileName, Scope, Index) of
    TAtlasQuickJump.NotAssigned:
      TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkNotAssigned,
        [ANumber]));
    TAtlasQuickJump.OtherFile:
      TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkOtherFile, [ANumber]));
  else
    JumpTo(Current, Current.Bookmarks[Index].Id, ANumber);
  end;
end;

class procedure TAtlasIdeQuickBookmarks.Step(AForward: Boolean);
var
  FileName, Text: string;
  Line, Target: Integer;
  Current: TAtlasBookmarkList;
begin
  if not QuickTarget(FileName, Text, Line, Current) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Put(Current);
  if not TAtlasQuickBookmarks.Step(Current, FileName, Line, AForward, Target) then
  begin
    TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkNoneInFile));
    Exit;
  end;
  TAtlasIdeResults.Open(FileName, Target, 0);
end;

class procedure TAtlasIdeQuickBookmarks.NextBookmark;
begin
  Step(True);
end;

class procedure TAtlasIdeQuickBookmarks.PreviousBookmark;
begin
  Step(False);
end;

class procedure TAtlasIdeQuickBookmarks.ColumnClick(const AFileName: string; ALine: Integer);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or not TAtlasIdeSettings.Current.QuickBookmarksGutterClick or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, Project, Text, Current) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(Current, TAtlasQuickBookmarks.Click(Current, AFileName, Text, ALine, NowUtc) <>
    TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.ColumnAssign(const AFileName: string; ALine, ANumber: Integer);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
  Marks: TArray<TAtlasBookmark>;
  Change: TAtlasQuickChange;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, Project, Text, Current) then
  begin
    Exit;
  end;
  Marks := TAtlasQuickBookmarks.ColumnMarks(Current, AFileName, ALine);
  if Length(Marks) > 0 then
  begin
    Change := TAtlasQuickBookmarks.AssignNumber(Current, Marks[0].Id, ANumber);
  end
  else
  begin
    Change := TAtlasQuickBookmarks.SetNumber(Current, AFileName, Text, ALine, ANumber, NowUtc);
  end;
  TAtlasIdeBookmarks.Commit(Current, Change <> TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.ColumnName(const AFileName: string; ALine: Integer);
var
  Project, Text, Name, Id: string;
  Current: TAtlasBookmarkList;
  Marks: TArray<TAtlasBookmark>;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, Project, Text, Current) then
  begin
    Exit;
  end;
  Marks := TAtlasQuickBookmarks.ColumnMarks(Current, AFileName, ALine);
  if Length(Marks) > 0 then
  begin
    Name := Marks[0].DisplayName;
  end
  else
  begin
    Name := TAtlasBookmarks.SuggestName(AFileName, Text, ALine);
  end;
  if not TAtlasBookmarkDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.BookmarksDialogTitle,
    [ExtractFileName(AFileName), ALine + 1]), Name) then
  begin
    TAtlasIdeBookmarks.Put(Current);
    Exit;
  end;
  // Umbenennen macht aus dem schnellen ein benanntes Lesezeichen; die Nummer bleibt.
  if Length(Marks) > 0 then
  begin
    Id := Marks[0].Id;
    Current.Rename(Id, Name);
  end
  else
  begin
    Id := Current.Add(AFileName, Text, ALine, Name, NowUtc);
  end;
  TAtlasIdeBookmarks.Commit(Current, True, Id);
end;

class procedure TAtlasIdeQuickBookmarks.ColumnRemove(const AFileName: string; ALine: Integer);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, Project, Text, Current) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(Current, TAtlasQuickBookmarks.RemoveAt(Current, AFileName, ALine) > 0, '');
end;

class procedure TAtlasIdeQuickBookmarks.ColumnRemoveFile(const AFileName: string);
var
  Project, Text: string;
  Current: TAtlasBookmarkList;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, Project, Text, Current) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(Current, TAtlasQuickBookmarks.RemoveFile(Current, AFileName) > 0, '');
end;

/// <summary>Gesetzte IDE-Lesezeichen 1–9 der Ansicht (Zeile 0-basiert).</summary>
function IdeMarks(const AView: IOTAEditView): TArray<TAtlasIdeBookmarkPos>;
var
  mNumber: Integer;
  mPosition: TOTACharPos;
begin
  Result := nil;
  for mNumber := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    mPosition := AView.BookmarkPos[mNumber];
    if mPosition.Line > 0 then
    begin
      Result := Result + [TAtlasIdeBookmarkPos.Create(mNumber, mPosition.Line - 1)];
    end;
  end;
end;

/// <summary>Übernommene IDE-Lesezeichen in der IDE entfernen, damit kein doppeltes Symbol bleibt: BookmarkToggle
/// wirkt an der Schreibmarke, also kurz an die Zeile des Lesezeichens und zurück, ohne dass die Ansicht springt.
/// </summary>
procedure RemoveIdeMarks(const AView: IOTAEditView; const ANumbers: TArray<Integer>);
var
  mNumber, mTop, mLeft: Integer;
  mPosition: TOTACharPos;
  mSaved, mPlace: TOTAEditPos;
begin
  mSaved := AView.CursorPos;
  mTop := AView.TopRow;
  mLeft := AView.LeftColumn;
  for mNumber in ANumbers do
  begin
    mPosition := AView.BookmarkPos[mNumber];
    if mPosition.Line <= 0 then
    begin
      Continue;
    end;
    mPlace.Line := mPosition.Line;
    mPlace.Col := mPosition.CharIndex + 1;
    AView.CursorPos := mPlace;
    AView.BookmarkToggle(mNumber);
  end;
  AView.CursorPos := mSaved;
  AView.SetTopLeft(mTop, mLeft);
  AView.Paint;
end;

class procedure TAtlasIdeQuickBookmarks.ImportIde(const AFileName: string);
var
  mView: IOTAEditView;
  mMarks: TArray<TAtlasIdeBookmarkPos>;
  mTaken: TArray<Integer>;
  mProject, mText: string;
  mCurrent: TAtlasBookmarkList;
begin
  // Nur, wenn die Spalte wirklich zeichnet: Die IDE-Lesezeichen werden dort entfernt, ohne Spalte wären die
  // übernommenen nirgends mehr zu sehen (#1281).
  if not TAtlasIdeBookmarks.QuickOn(False) or not TAtlasIdeSettings.Current.QuickBookmarksImportIde or
    not TAtlasIdeBookmarks.ColumnShown or (AFileName = '') then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  // Einmal je Datei und Sitzung: Später gesetzte IDE-Lesezeichen (etwa mit Strg+Umschalt+0) bleiben bei der IDE.
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) or
    not TAtlasIdeBookmarks.TakeImport(AFileName) then
  begin
    Exit;
  end;
  mMarks := IdeMarks(mView);
  if (Length(mMarks) = 0) or not TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, mText, mCurrent) then
  begin
    Exit;
  end;
  mTaken := TAtlasQuickBookmarks.Import(mCurrent, AFileName, mText, mMarks, NowUtc);
  if Length(mTaken) = 0 then
  begin
    TAtlasIdeBookmarks.Put(mCurrent);
  end
  else if TAtlasIdeBookmarks.Store(mCurrent) then
  begin
    RemoveIdeMarks(mView, mTaken);
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkImported,
      [Length(mTaken), ExtractFileName(AFileName)]));
    TAtlasIdeBookmarks.Invalidate;
    TAtlasIdeBookmarks.RefreshWindow('');
  end;
end;

end.
