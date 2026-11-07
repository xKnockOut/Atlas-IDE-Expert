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
  mCurrent: TAtlasBookmarkList;
begin
  Result := nil;
  if TAtlasIdeBookmarks.LoadedList(AFileName, mCurrent) then
  begin
    Result := TAtlasQuickBookmarks.ColumnMarks(mCurrent, AFileName, ALine);
  end;
end;

class function TAtlasIdeQuickBookmarks.NextNumber(const AFileName: string): Integer;
var
  mCurrent: TAtlasBookmarkList;
begin
  Result := 1;
  if TAtlasIdeBookmarks.LoadedList(AFileName, mCurrent) then
  begin
    Result := TAtlasQuickBookmarks.FreeNumber(mCurrent);
  end;
end;

class function TAtlasIdeQuickBookmarks.HasColumnMarks(const AFileName: string): Boolean;
var
  mCurrent: TAtlasBookmarkList;
begin
  Result := TAtlasIdeBookmarks.LoadedList(AFileName, mCurrent) and
    TAtlasQuickBookmarks.HasColumnMarks(mCurrent, AFileName);
end;

class function TAtlasIdeQuickBookmarks.OverviewMarks(const AFileName: string;
  out AMarks: TArray<TAtlasBookmark>): Boolean;
var
  mCurrent: TAtlasBookmarkList;
  mMark: TAtlasBookmark;
begin
  AMarks := nil;
  Result := TAtlasIdeBookmarks.QuickOn(False);
  if not Result then
  begin
    Exit;
  end;
  if TAtlasIdeBookmarks.LoadedList(AFileName, mCurrent) then
  begin
    for mMark in mCurrent.ForFile(AFileName) do
    begin
      if not mMark.Lost then
      begin
        AMarks := AMarks + [mMark];
      end;
    end;
  end;
end;

class function TAtlasIdeQuickBookmarks.QuickTarget(out AFileName, AText: string; out ALine: Integer;
  out AList: TAtlasBookmarkList): Boolean;
var
  mView: IOTAEditView;
  mProject: string;
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
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoEditor));
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  ALine := mView.CursorPos.Line - 1;
  Result := (ALine >= 0) and TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, AText, AList);
end;

class function TAtlasIdeQuickBookmarks.NumberTargets(const AFileName: string): TArray<string>;
var
  mProject: string;
  mCurrent: TAtlasBookmarkList;
  mNumber, mIndex: Integer;
  mMark: TAtlasBookmark;
begin
  SetLength(Result, TAtlasQuickBookmarks.cMaxNumber + 1);
  if not TAtlasIdeBookmarks.Running then
  begin
    Exit;
  end;
  mProject := TAtlasIdeBookmarks.ResolveProject(AFileName);
  if mProject = '' then
  begin
    Exit;
  end;
  mCurrent := TAtlasIdeBookmarks.List(mProject);
  for mNumber := 1 to TAtlasQuickBookmarks.cMaxNumber do
  begin
    mIndex := mCurrent.IndexOfNumber(mNumber);
    if mIndex < 0 then
    begin
      Continue;
    end;
    mMark := mCurrent.Bookmarks[mIndex];
    Result[mNumber] := ExtractFileName(mMark.FileName) + ':' + IntToStr(mMark.Line + 1) + ' ' + mMark.DisplayName;
  end;
end;

class procedure TAtlasIdeQuickBookmarks.QuickToggle;
var
  mFileName, mText: string;
  mLine: Integer;
  mCurrent: TAtlasBookmarkList;
begin
  if not QuickTarget(mFileName, mText, mLine, mCurrent) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(mCurrent, TAtlasQuickBookmarks.Toggle(mCurrent, mFileName, mText, mLine, NowUtc) <>
    TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.QuickSetNumber(ANumber: Integer);
var
  mFileName, mText: string;
  mLine: Integer;
  mCurrent: TAtlasBookmarkList;
begin
  if not QuickTarget(mFileName, mText, mLine, mCurrent) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(mCurrent,
    TAtlasQuickBookmarks.SetNumber(mCurrent, mFileName, mText, mLine, ANumber, NowUtc) <> TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.JumpTo(var AList: TAtlasBookmarkList; const AId: string; ANumber: Integer);
var
  mIndex: Integer;
  mMark: TAtlasBookmark;
begin
  mIndex := AList.IndexOf(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  // Unmittelbar vor dem Sprung wiederfinden: Die Datei kann sich außerhalb geändert haben.
  if TAtlasIdeBookmarks.RelocateFile(AList, AList.Bookmarks[mIndex].FileName) then
  begin
    TAtlasIdeBookmarks.Store(AList);
    TAtlasIdeBookmarks.RefreshWindow(AId);
  end
  else
  begin
    TAtlasIdeBookmarks.Put(AList);
  end;
  mMark := AList.Bookmarks[mIndex];
  if mMark.Lost and (ANumber > 0) then
  begin
    TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkNotFound, [ANumber]));
  end;
  // Der Navigationsverlauf (#504) nimmt den Sprung wie jeden anderen auf (andere Datei oder weiter als einige
  // Zeilen).
  TAtlasIdeResults.Open(mMark.FileName, mMark.Line, 0);
  TAtlasIdeBookmarks.Invalidate;
end;

class procedure TAtlasIdeQuickBookmarks.QuickJump(ANumber: Integer);
var
  mProject, mFileName: string;
  mView: IOTAEditView;
  mCurrent: TAtlasBookmarkList;
  mScope: TAtlasQuickScope;
  mIndex: Integer;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) then
  begin
    Exit;
  end;
  mProject := TAtlasIdeBookmarks.CurrentProject;
  if mProject = '' then
  begin
    TAtlasIdeBookmarks.Say(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksNoProject));
    Exit;
  end;
  mFileName := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mFileName := mView.Buffer.FileName;
  end;
  mScope := TAtlasQuickScope.Project;
  if SameText(TAtlasIdeSettings.Current.QuickBookmarksScope, 'file') then
  begin
    mScope := TAtlasQuickScope.CurrentFile;
  end;
  mCurrent := TAtlasIdeBookmarks.List(mProject);
  case TAtlasQuickBookmarks.Jump(mCurrent, ANumber, mFileName, mScope, mIndex) of
    TAtlasQuickJump.NotAssigned:
      TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkNotAssigned,
        [ANumber]));
    TAtlasQuickJump.OtherFile:
      TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkOtherFile, [ANumber]));
  else
    JumpTo(mCurrent, mCurrent.Bookmarks[mIndex].Id, ANumber);
  end;
end;

class procedure TAtlasIdeQuickBookmarks.Step(AForward: Boolean);
var
  mFileName, mText: string;
  mLine, mTarget: Integer;
  mCurrent: TAtlasBookmarkList;
begin
  if not QuickTarget(mFileName, mText, mLine, mCurrent) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Put(mCurrent);
  if not TAtlasQuickBookmarks.Step(mCurrent, mFileName, mLine, AForward, mTarget) then
  begin
    TAtlasIdeBookmarks.Status(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkNoneInFile));
    Exit;
  end;
  TAtlasIdeResults.Open(mFileName, mTarget, 0);
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
  mProject, mText: string;
  mCurrent: TAtlasBookmarkList;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or not TAtlasIdeSettings.Current.QuickBookmarksGutterClick or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, mText, mCurrent) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(mCurrent, TAtlasQuickBookmarks.Click(mCurrent, AFileName, mText, ALine, NowUtc) <>
    TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.ColumnAssign(const AFileName: string; ALine, ANumber: Integer);
var
  mProject, mText: string;
  mCurrent: TAtlasBookmarkList;
  mMarks: TArray<TAtlasBookmark>;
  mChange: TAtlasQuickChange;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, mText, mCurrent) then
  begin
    Exit;
  end;
  mMarks := TAtlasQuickBookmarks.ColumnMarks(mCurrent, AFileName, ALine);
  if Length(mMarks) > 0 then
  begin
    mChange := TAtlasQuickBookmarks.AssignNumber(mCurrent, mMarks[0].Id, ANumber);
  end
  else
  begin
    mChange := TAtlasQuickBookmarks.SetNumber(mCurrent, AFileName, mText, ALine, ANumber, NowUtc);
  end;
  TAtlasIdeBookmarks.Commit(mCurrent, mChange <> TAtlasQuickChange.None, '');
end;

class procedure TAtlasIdeQuickBookmarks.ColumnName(const AFileName: string; ALine: Integer);
var
  mProject, mText, mName, mId: string;
  mCurrent: TAtlasBookmarkList;
  mMarks: TArray<TAtlasBookmark>;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, mText, mCurrent) then
  begin
    Exit;
  end;
  mMarks := TAtlasQuickBookmarks.ColumnMarks(mCurrent, AFileName, ALine);
  if Length(mMarks) > 0 then
  begin
    mName := mMarks[0].DisplayName;
  end
  else
  begin
    mName := TAtlasBookmarks.SuggestName(AFileName, mText, ALine);
  end;
  if not TAtlasBookmarkDialog.Execute(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.BookmarksDialogTitle,
    [ExtractFileName(AFileName), ALine + 1]), mName) then
  begin
    TAtlasIdeBookmarks.Put(mCurrent);
    Exit;
  end;
  // Umbenennen macht aus dem schnellen ein benanntes Lesezeichen; die Nummer bleibt.
  if Length(mMarks) > 0 then
  begin
    mId := mMarks[0].Id;
    mCurrent.Rename(mId, mName);
  end
  else
  begin
    mId := mCurrent.Add(AFileName, mText, ALine, mName, NowUtc);
  end;
  TAtlasIdeBookmarks.Commit(mCurrent, True, mId);
end;

class procedure TAtlasIdeQuickBookmarks.ColumnRemove(const AFileName: string; ALine: Integer);
var
  mProject, mText: string;
  mCurrent: TAtlasBookmarkList;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, mText, mCurrent) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(mCurrent, TAtlasQuickBookmarks.RemoveAt(mCurrent, AFileName, ALine) > 0, '');
end;

class procedure TAtlasIdeQuickBookmarks.ColumnRemoveFile(const AFileName: string);
var
  mProject, mText: string;
  mCurrent: TAtlasBookmarkList;
begin
  if not TAtlasIdeBookmarks.QuickOn(True) or
    not TAtlasIdeBookmarks.PrepareFile(AFileName, mProject, mText, mCurrent) then
  begin
    Exit;
  end;
  TAtlasIdeBookmarks.Commit(mCurrent, TAtlasQuickBookmarks.RemoveFile(mCurrent, AFileName) > 0, '');
end;

/// <summary>Gesetzte IDE-Lesezeichen 1–9 der Ansicht (Zeile 0-basiert).</summary>
function IdeMarks(const AView: IOTAEditView): TArray<TAtlasIdeBookmarkPos>;
var
  mNumber: Integer;
  mPosition: TOTACharPos;
begin
  Result := nil;
  for mNumber := 1 to TAtlasQuickBookmarks.cMaxNumber do
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
