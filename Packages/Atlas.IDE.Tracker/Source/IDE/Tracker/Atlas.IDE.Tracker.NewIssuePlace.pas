unit Atlas.IDE.Tracker.NewIssuePlace;

// Editorseite von „Issue anlegen …“ (#1268, aus Atlas.IDE.Tracker.NewIssue
// gelöst, #1455): liest Datei, Zeile, Methode und Auswahl der aktiven
// Editoransicht und schreibt nach dem Anlegen die Kennung in den Code
// (TODO ergänzen bzw. nach Rückfrage Kommentar anhängen). Geschrieben wird
// nur, wenn Datei und Zeile noch so dastehen wie beim Öffnen des Dialogs.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.NewIssue;

type
  /// <summary>Wohin die Kennung nach dem Anlegen kommt: Datei und Zeile wie beim Öffnen des Dialogs.</summary>
  TAtlasNewIssuePlace = record
    Valid: Boolean;
    FileName: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    /// <summary>Text der Zeile beim Öffnen; hat er sich geändert, schreibt Atlas nichts.</summary>
    LineText: string;
    /// <summary>Kein Ort: Atlas ändert den Code nicht (aus Befunden, aus einem Absturzfall).</summary>
    class function None: TAtlasNewIssuePlace; static;
    /// <summary>Ort und Vorschlag aus der aktiven Editoransicht; False ohne Editor.</summary>
    class function Capture(out APlace: TAtlasNewIssuePlace; out AContext: TAtlasNewIssueContext): Boolean; static;
    /// <summary>AKey an diesen Ort schreiben; ASay meldet die geänderte Zeile.</summary>
    procedure Mark(const AKey: string; const ASay: TProc<string>);
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Editor.MethodToggle,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

/// <summary>Ersetzt Zeile ALine (ab 1) der Ansicht durch ANew; ein Rückgängig-Schritt der IDE.</summary>
function WriteLine(const AView: IOTAEditView; ALine: Integer; const ANew: string): Boolean;
var
  mText: string;
  mFrom, mTill: Integer;
  mWriter: IOTAEditWriter;
begin
  Result := False;
  if (AView = nil) or AView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mFrom := TAtlasEditorBuffer.CharOffset(mText, ALine - 1, 0);
  mTill := TAtlasEditorBuffer.CharOffset(mText, ALine - 1, MaxInt div 2);
  mWriter := AView.Buffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(mText, 1, mFrom)));
  if mTill > mFrom then
  begin
    mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(mText, 1, mTill)));
  end;
  if ANew <> '' then
  begin
    mWriter.Insert(PAnsiChar(UTF8Encode(ANew)));
  end;
  mWriter := nil;
  // Eigener Schreibvorgang: Probleme und Inlay-Hints lesen den Puffer neu.
  TAtlasEditorSnapshots.Invalidate(AView.Buffer.FileName);
  AView.Paint;
  Result := True;
end;

/// <summary>Aktive Ansicht und Zeile, wenn sie noch zu APlace passen.</summary>
function Unchanged(const APlace: TAtlasNewIssuePlace; out AView: IOTAEditView; out ALine: string): Boolean;
begin
  ALine := '';
  AView := nil;
  if APlace.Valid then
  begin
    AView := TAtlasEditorBuffer.ActiveView;
  end;
  Result := (AView <> nil) and SameText(AView.Buffer.FileName, APlace.FileName);
  if Result then
  begin
    ALine := TAtlasEditorBuffer.LineText(AView, APlace.Line);
    Result := ALine = APlace.LineText;
  end;
end;

{ TAtlasNewIssuePlace }

class function TAtlasNewIssuePlace.None: TAtlasNewIssuePlace;
begin
  Result := Default(TAtlasNewIssuePlace);
end;

class function TAtlasNewIssuePlace.Capture(out APlace: TAtlasNewIssuePlace;
  out AContext: TAtlasNewIssueContext): Boolean;
var
  mView: IOTAEditView;
  mText: string;
  mBlock: IOTAEditBlock;
begin
  APlace := None;
  AContext := TAtlasNewIssueContext.Empty;
  mView := TAtlasEditorBuffer.ActiveView;
  Result := mView <> nil;
  if not Result then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  AContext.FileName := mView.Buffer.FileName;
  AContext.Line := mView.CursorPos.Line;
  AContext.Lines := TTextLines.SplitLines(mText);
  AContext.Method := TAtlasMethodToggle.MethodNameAt(mText, AContext.Line);
  mBlock := mView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) then
  begin
    AContext.Selection := mBlock.Text;
    AContext.SelectionLine := mBlock.StartingRow;
  end;
  APlace.Valid := True;
  APlace.FileName := AContext.FileName;
  APlace.Line := AContext.Line;
  if (AContext.Line >= 1) and (AContext.Line <= Length(AContext.Lines)) then
  begin
    APlace.LineText := AContext.Lines[AContext.Line - 1];
  end;
end;

procedure TAtlasNewIssuePlace.Mark(const AKey: string; const ASay: TProc<string>);
var
  mView: IOTAEditView;
  mLine, mNew: string;
  mTodo: TAtlasTodoComment;
begin
  if not Unchanged(Self, mView, mLine) then
  begin
    Exit;
  end;
  if TAtlasNewIssues.TodoAt(mLine, mTodo) then
  begin
    mNew := TAtlasNewIssues.WithKey(mLine, AKey);
    if (mNew <> mLine) and WriteLine(mView, Line, mNew) then
    begin
      ASay(TAtlasStrings.Fmt(TAtlasTextId.NewIssueTodoChanged, [Trim(mNew)]));
    end;
    Exit;
  end;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.NewIssueInsertComment, [TAtlasNewIssues.KeyComment(AKey)]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    WriteLine(mView, Line, TAtlasNewIssues.WithKeyComment(mLine, AKey));
  end;
end;

end.
