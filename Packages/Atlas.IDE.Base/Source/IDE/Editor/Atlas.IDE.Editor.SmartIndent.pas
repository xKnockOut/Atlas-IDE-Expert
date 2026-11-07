unit Atlas.IDE.Editor.SmartIndent;

// Einrückung beim Tippen (#1827) im Editor. Was sich ändert, rechnet der
// Server (atlas.server.smartIndent, Atlas.Common.Editing.SmartIndent); ob die
// Antwort noch passt, Atlas.Core.Editor.SmartIndent; hier bleiben Puffer,
// Schreibmarke und die Anfrage.
// - Den Zeilenumbruch erkennt Atlas.IDE.Editor.EnterWatch, ohne Enter zu
//   binden; dieser Handler läuft nach dem Kommentar fortsetzen (#696) und
//   übernimmt die Zeile nie, damit das Muster fortsetzen (#671) danach läuft.
// - Die Anfrage läuft im Hintergrund (TAtlasBackgroundRequest), die IDE wartet
//   nicht. Hat sich bis zur Antwort etwas geändert, verfällt sie.
// - Atlas schreibt die Änderungen als eigenen Schreiber (CreateUndoableWriter):
//   Strg+Z nimmt nur die Einrückung zurück, der Zeilenumbruch bleibt.
// - Schalter: smartIndent.* in den globalen Einstellungen, ausgewertet vom
//   Server; ist alles aus, antwortet er mit null.
// - ColumnAt fragt für das Einfügen (#1832, editor.smartPaste) die Spalte der
//   Einfügezeile; dort wartet der Hauptthread kurz.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.Core.Editor.SmartIndent;

type
  TAtlasIdeSmartIndent = class
  private class var
    FRequest: TAtlasBackgroundRequest;
    FSessionOf: TFunc<TLspSession>;
    FBusy: TFunc<Boolean>;
  private
    class function Session: TLspSession; static;
    /// <summary>Stand der Zeile ALine (0-basiert) in AView.</summary>
    class function AskedOf(const AView: IOTAEditView; ALine: Integer): TAtlasSmartIndentAsked; static;
    /// <summary>Nach Enter; False: Atlas übernimmt die Zeile nicht.</summary>
    class function Run(const AView: IOTAEditView): Boolean; static;
    class procedure Answered(const AView: IOTAEditView; const AAsked: TAtlasSmartIndentAsked;
      const AAnswer: TAtlasSmartIndentAnswer); static;
  public
    /// <summary>Meldet den Handler nach Enter an. ABusy: Vervollständigung oder Platzhalter offen.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const ABusy: TFunc<Boolean>); static;
    class procedure Uninstall; static;
    /// <summary>Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Spalte einer Anweisung am Anfang der Zeile ALine (0-basiert) von ABuffer mit Text AText; False
    /// ohne Server, ohne Antwort oder bei abgeschaltetem smartIndent.</summary>
    class function ColumnAt(const ABuffer: IOTAEditBuffer; const AText: string; ALine: Integer;
      out AColumn: Integer): Boolean; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Editor.EnterWatch;

const
  cHandlerName = 'SmartIndent';
  /// <summary>Spalte beim Einfügen: kurz, sonst bleibt die bisherige Heuristik.</summary>
  cColumnTimeoutMs = 500;

/// <summary>Schreibt AEdits (aufsteigend, ohne Überlappung) als einen Rückgängig-Schritt in ABuffer mit Text
/// AText.</summary>
procedure WriteEdits(const ABuffer: IOTAEditBuffer; const AText: string; const AEdits: TArray<TLspTextEdit>);
var
  mWriter: IOTAEditWriter;
  mEdit: TLspTextEdit;
begin
  mWriter := ABuffer.CreateUndoableWriter;
  for mEdit in AEdits do
  begin
    mWriter.CopyTo(TAtlasEditorBuffer.ByteOffset(AText, mEdit.StartPos.Line, mEdit.StartPos.Character));
    mWriter.DeleteTo(TAtlasEditorBuffer.ByteOffset(AText, mEdit.EndPos.Line, mEdit.EndPos.Character));
    if mEdit.NewText <> '' then
    begin
      mWriter.Insert(PAnsiChar(UTF8Encode(mEdit.NewText)));
    end;
  end;
  mWriter := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

/// <summary>AEdits nach ihrem Anfang aufsteigend.</summary>
function Sorted(const AEdits: TArray<TLspTextEdit>): TArray<TLspTextEdit>;
var
  mIndex, mOther: Integer;
  mEdit: TLspTextEdit;
begin
  Result := Copy(AEdits);
  for mIndex := 1 to High(Result) do
  begin
    mEdit := Result[mIndex];
    mOther := mIndex - 1;
    while (mOther >= 0) and (TLspTextPosition.Compare(Result[mOther].StartPos, mEdit.StartPos) > 0) do
    begin
      Result[mOther + 1] := Result[mOther];
      Dec(mOther);
    end;
    Result[mOther + 1] := mEdit;
  end;
end;

{ TAtlasIdeSmartIndent }

class procedure TAtlasIdeSmartIndent.Install(const ASessionOf: TFunc<TLspSession>; const ABusy: TFunc<Boolean>);
begin
  FSessionOf := ASessionOf;
  FBusy := ABusy;
  if FRequest = nil then
  begin
    FRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.SmartIndent);
  end;
  TAtlasEnterWatch.Add(cHandlerName,
    function: Boolean
    begin
      Result := Enabled;
    end,
    function(const AView: IOTAEditView): Boolean
    begin
      Result := Run(AView);
    end);
end;

class procedure TAtlasIdeSmartIndent.Uninstall;
begin
  TAtlasEnterWatch.Remove(cHandlerName);
  // Wartet die laufende Anfrage ab und verwirft ihre Antwort.
  FreeAndNil(FRequest);
  FSessionOf := nil;
  FBusy := nil;
end;

class function TAtlasIdeSmartIndent.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled;
end;

class function TAtlasIdeSmartIndent.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class function TAtlasIdeSmartIndent.AskedOf(const AView: IOTAEditView; ALine: Integer): TAtlasSmartIndentAsked;
begin
  Result := TAtlasSmartIndentAsked.Create(AView.Buffer.FileName, ALine, TAtlasEditorBuffer.LineText(AView, ALine + 1),
    TAtlasEditorBuffer.LineText(AView, ALine));
end;

class function TAtlasIdeSmartIndent.Run(const AView: IOTAEditView): Boolean;
var
  mSession: TLspSession;
  mAsked: TAtlasSmartIndentAsked;
  mArguments: string;
  mAnswer: TAtlasSmartIndentAnswer;
  mView: IOTAEditView;
begin
  Result := False;
  mSession := Session;
  if (mSession = nil) or (FRequest = nil) or FRequest.Busy or (Assigned(FBusy) and FBusy()) or
    AView.Buffer.IsReadOnly or not TAtlasSmartIndent.IsSource(AView.Buffer.FileName) then
  begin
    Exit;
  end;
  mAsked := AskedOf(AView, AView.CursorPos.Line - 1);
  if not TAtlasSmartIndent.Applies(mAsked.PreviousText) then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(mAsked.FileName, TAtlasEditorBuffer.Text(AView.Buffer));
  mArguments := TAtlasSmartIndent.Arguments(TLspSession.PathToUri(mAsked.FileName), mAsked.Line,
    TAtlasEditorBuffer.BlockIndent(AView.Buffer), True, False);
  mView := AView;
  mAnswer := Default(TAtlasSmartIndentAnswer);
  FRequest.Start(
    procedure
    var
      mValue: TJSONValue;
    begin
      mValue := mSession.RunCommand(TAtlasSmartIndent.Command, mArguments, TAtlasSmartIndent.TimeoutMs);
      try
        TAtlasSmartIndent.ReadAnswer(mValue, mAnswer);
      finally
        mValue.Free;
      end;
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      if AOk then
      begin
        Answered(mView, mAsked, mAnswer);
      end;
    end);
end;

class procedure TAtlasIdeSmartIndent.Answered(const AView: IOTAEditView; const AAsked: TAtlasSmartIndentAsked;
  const AAnswer: TAtlasSmartIndentAnswer);
var
  mNow: TAtlasSmartIndentAsked;
  mCursor: TOTAEditPos;
  mTabWidth: Integer;
begin
  if (AView = nil) or (AView.Buffer = nil) or (AView <> TAtlasEditorBuffer.ActiveView) or
    (AAnswer.Cursor.Line <> AAsked.Line) then
  begin
    Exit;
  end;
  mNow := AskedOf(AView, AAsked.Line);
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mCursor := AView.CursorPos;
  if not TAtlasSmartIndent.StillValid(AAsked, mNow, mCursor.Line - 1,
    TLspSession.ColumnToIndex(mNow.LineText, mCursor.Col, mTabWidth)) then
  begin
    Exit;
  end;
  if Length(AAnswer.Edits) > 0 then
  begin
    WriteEdits(AView.Buffer, TAtlasEditorBuffer.Text(AView.Buffer), Sorted(AAnswer.Edits));
  end;
  mCursor.Line := AAnswer.Cursor.Line + 1;
  mCursor.Col := TLspSession.IndexToColumn(TAtlasEditorBuffer.LineText(AView, mCursor.Line), AAnswer.Cursor.Character,
    mTabWidth);
  AView.CursorPos := mCursor;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class function TAtlasIdeSmartIndent.ColumnAt(const ABuffer: IOTAEditBuffer; const AText: string; ALine: Integer;
  out AColumn: Integer): Boolean;
var
  mSession: TLspSession;
  mValue: TJSONValue;
begin
  AColumn := 0;
  mSession := Session;
  Result := (mSession <> nil) and Enabled and TAtlasSmartIndent.IsSource(ABuffer.FileName);
  if not Result then
  begin
    Exit;
  end;
  mSession.Sync(ABuffer.FileName, AText);
  try
    mValue := mSession.RunCommand(TAtlasSmartIndent.Command, TAtlasSmartIndent.Arguments(
      TLspSession.PathToUri(ABuffer.FileName), ALine, TAtlasEditorBuffer.BlockIndent(ABuffer), True, True),
      cColumnTimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Beim Einfügen keine Meldung; die bisherige Heuristik gilt.
      TAtlasGuard.Log('smartIndent: ' + TAtlasGuard.MessageText(E.Message));
      Exit(False);
    end;
  end;
  try
    Result := TAtlasSmartIndent.ReadColumn(mValue, AColumn);
  finally
    mValue.Free;
  end;
end;

end.
