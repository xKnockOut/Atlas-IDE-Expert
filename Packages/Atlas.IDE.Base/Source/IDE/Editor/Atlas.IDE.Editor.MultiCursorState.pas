unit Atlas.IDE.Editor.MultiCursorState;

// Stand der mehreren Einfügemarken (#589) im Editor: Ansicht, Text, Marken
// ([0] = Hauptmarke, also Cursor und Markierung der IDE) und die eigenen
// Schritte für Rückgängig und Wiederholen. Was sich an den Marken ändert,
// rechnet Atlas.Core.Editor.MultiCursor aus; hier geht es in den Puffer (ein
// Schreiber je Schritt, also ein Rückgängig-Schritt). Tasten, Maus, Takt,
// Statusfeld und Zeichnen bleiben in TAtlasIdeMultiCursor, das über AOnFinish
// und AOnRefresh erfährt, wann die Marken enden bzw. neu gezeigt werden.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Editor.MultiCursor;

type
  TAtlasIdeMultiCursorState = class
  private const
    /// <summary>So viele eigene Schritte merkt sich Atlas für Rückgängig und Wiederholen.</summary>
    cStepLimit = 20;
  private type
    /// <summary>Ein eigener Schritt: Text und Marken davor und danach.</summary>
    TStep = record
      Before: string;
      After: string;
      BeforeCarets: TAtlasCarets;
      AfterCarets: TAtlasCarets;
    end;
  private
    FOnFinish: TProc;
    FOnRefresh: TProc;
    // Ansicht, Pufferinhalt nach dem letzten bekannten Stand, Marken ([0] = Hauptmarke).
    FView: IOTAEditView;
    FText: string;
    FLines: TArray<string>;
    FCarets: TAtlasCarets;
    FWriting: Boolean;
    FSteps: TArray<TStep>;
    FStep: Integer;
    /// <summary>Aktive Ansicht, ihr Text und die Marken mit der Hauptmarke aus der IDE; False ohne Ansicht oder
    /// bei schreibgeschütztem Puffer.</summary>
    function Prepare(out AView: IOTAEditView; out AText: string): Boolean;
    procedure Apply(const AView: IOTAEditView; const AText, ANewText: string; const ACarets: TAtlasCarets);
    procedure SetCarets(const AView: IOTAEditView; const AText: string; const ACarets: TAtlasCarets);
    procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string);
    procedure AddStep(const ABefore, AAfter: string; const ABeforeCarets, AAfterCarets: TAtlasCarets);
    procedure SetText(const AText: string);
  public
    /// <summary>AOnFinish beendet die Zusatzmarken (Datei gewechselt), AOnRefresh zeigt sie nach einem Schritt.
    /// </summary>
    constructor Create(const AOnFinish, AOnRefresh: TProc);
    /// <summary>Mehr als eine Marke?</summary>
    function Active: Boolean;
    function Count: Integer;
    /// <summary>Gehört AView zur Datei der Marken?</summary>
    function Shows(const AView: IOTAEditView): Boolean;
    function ShowsFile(const AFileName: string): Boolean;
    /// <summary>Alle Marken und Schritte vergessen.</summary>
    procedure Clear;
    /// <summary>Zeile ALine (0-basiert) im bekannten Stand; '' außerhalb.</summary>
    function LineText(ALine: Integer): string;
    /// <summary>Marken an eine Änderung durch andere anpassen (Rückgängig, Mirror, Shift).</summary>
    procedure Reconcile(const AText: string);
    /// <summary>Hauptmarke aus der IDE übernehmen, wenn sich der Text nicht geändert hat.</summary>
    procedure SyncMain;
    procedure DoEdit(AKind: TAtlasCaretEditKind; const AInsert: string);
    /// <summary>Markierungen an allen Marken umschließen (#672); False, wenn das Zeichen normal getippt wird.
    /// </summary>
    function DoWrap(AOpen: Char): Boolean;
    procedure DoMove(AMove: TAtlasCaretMove; AExtend: Boolean);
    /// <summary>Markierungen in die Zwischenablage; False ohne Markierung (Kopieren bleibt der IDE).</summary>
    function DoCopy: Boolean;
    procedure DoCut;
    procedure DoPaste;
    procedure DoSkip;
    /// <summary>Strg+D: Wort markieren bzw. nächstes Vorkommen hinzufügen; False gibt die Taste an die IDE.</summary>
    function Next: Boolean;
    /// <summary>Marken an die Zeilenenden der Markierung; False ohne Markierung.</summary>
    function LineEnds: Boolean;
    /// <summary>Marke in der Zeile darüber bzw. darunter.</summary>
    function Vertical(AUp: Boolean): Boolean;
    /// <summary>Marke an ALine und AColumn (Spalte des Editors) setzen bzw. entfernen; False, wenn AFileName
    /// nicht die aktive Datei ist.</summary>
    function Toggle(const AFileName: string; ALine, AColumn: Integer): Boolean;
    property View: IOTAEditView read FView;
    property Carets: TAtlasCarets read FCarets;
    /// <summary>Schreibt Atlas gerade selbst in den Puffer?</summary>
    property Writing: Boolean read FWriting;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  Vcl.Clipbrd,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Editor.WrapSelection,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Editor.WrapSelection;

/// <summary>Zeile ALine (0-basiert) aus ALines; '' außerhalb.</summary>
function LineOf(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < Length(ALines)) then
  begin
    Result := ALines[ALine];
  end;
end;

/// <summary>Hauptmarke aus Cursor und Markierung der IDE.</summary>
function ReadMain(const AView: IOTAEditView): TAtlasCaret;
var
  mCursor: TOTAEditPos;
  mBlock: IOTAEditBlock;
  mTabWidth, mLine, mCharacter, mStartLine, mStartCharacter, mEndLine, mEndCharacter: Integer;
  mLineText: string;
begin
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mCursor := AView.CursorPos;
  mLine := Max(0, mCursor.Line - 1);
  mLineText := TAtlasEditorBuffer.LineText(AView, mLine + 1);
  mCharacter := Min(TLspSession.ColumnToIndex(mLineText, mCursor.Col, mTabWidth), Length(mLineText));
  Result := TAtlasCaret.At(mLine, mCharacter);
  mBlock := AView.Block;
  if (mBlock = nil) or not mBlock.IsValid or (mBlock.Size = 0) then
  begin
    Exit;
  end;
  mStartLine := mBlock.StartingRow - 1;
  mStartCharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mStartLine + 1),
    mBlock.StartingColumn, mTabWidth);
  mEndLine := mBlock.EndingRow - 1;
  mEndCharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mEndLine + 1),
    mBlock.EndingColumn, mTabWidth);
  // Der Anker ist das Ende, an dem der Cursor nicht steht.
  if (mLine = mStartLine) and (mCharacter = mStartCharacter) then
  begin
    Result := TAtlasCaret.Range(mEndLine, mEndCharacter, mStartLine, mStartCharacter);
  end
  else
  begin
    Result := TAtlasCaret.Range(mStartLine, mStartCharacter, mEndLine, mEndCharacter);
  end;
end;

/// <summary>Cursor der IDE auf Zeile ALine, Zeichen ACharacter (0-basiert).</summary>
procedure PlaceCursor(const AView: IOTAEditView; const ALines: TArray<string>; ALine, ACharacter: Integer);
var
  mPosition: TOTAEditPos;
begin
  mPosition.Line := ALine + 1;
  mPosition.Col := TLspSession.IndexToColumn(LineOf(ALines, ALine), ACharacter,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.CursorPos := mPosition;
end;

/// <summary>Cursor und Markierung der IDE auf ACaret setzen.</summary>
procedure WriteMain(const AView: IOTAEditView; const ALines: TArray<string>; const ACaret: TAtlasCaret);
begin
  if ACaret.HasSelection then
  begin
    AView.Block.Style := btNonInclusive;
    PlaceCursor(AView, ALines, ACaret.AnchorLine, ACaret.AnchorCharacter);
    AView.Block.BeginBlock;
    PlaceCursor(AView, ALines, ACaret.Line, ACaret.Character);
    AView.Block.EndBlock;
  end
  else
  begin
    AView.Block.Reset;
    PlaceCursor(AView, ALines, ACaret.Line, ACaret.Character);
  end;
  AView.MoveViewToCursor;
end;

/// <summary>Zeile ALine (0-basiert) in den sichtbaren Bereich holen, ohne den Cursor zu bewegen.</summary>
procedure EnsureVisible(const AView: IOTAEditView; ALine: Integer);
var
  mRows: Integer;
begin
  mRows := Max(1, AView.ViewSize.cy);
  if (ALine + 1 >= AView.TopRow) and (ALine + 1 < AView.TopRow + mRows) then
  begin
    Exit;
  end;
  AView.SetTopLeft(Max(1, ALine + 1 - mRows div 2), AView.LeftColumn);
end;

/// <summary>Bereiche der Marken für das Umschließen.</summary>
function RangesOf(const ACarets: TAtlasCarets): TArray<TLspRange>;
var
  mIndex, mStartLine, mStartCharacter, mEndLine, mEndCharacter: Integer;
begin
  SetLength(Result, Length(ACarets));
  for mIndex := 0 to High(ACarets) do
  begin
    ACarets[mIndex].Bounds(mStartLine, mStartCharacter, mEndLine, mEndCharacter);
    Result[mIndex] := TLspRange.Create(mStartLine, mStartCharacter, mEndLine, mEndCharacter);
  end;
end;

/// <summary>Marken aus den Markierungen nach dem Umschließen.</summary>
function CaretsOf(const ASelections: TArray<TLspRange>): TAtlasCarets;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASelections));
  for mIndex := 0 to High(ASelections) do
  begin
    Result[mIndex] := TAtlasCaret.Range(ASelections[mIndex].StartPos.Line, ASelections[mIndex].StartPos.Character,
      ASelections[mIndex].EndPos.Line, ASelections[mIndex].EndPos.Character);
  end;
end;

{ TAtlasIdeMultiCursorState }

constructor TAtlasIdeMultiCursorState.Create(const AOnFinish, AOnRefresh: TProc);
begin
  inherited Create;
  FOnFinish := AOnFinish;
  FOnRefresh := AOnRefresh;
end;

function TAtlasIdeMultiCursorState.Active: Boolean;
begin
  Result := Length(FCarets) > 1;
end;

function TAtlasIdeMultiCursorState.Count: Integer;
begin
  Result := Length(FCarets);
end;

function TAtlasIdeMultiCursorState.ShowsFile(const AFileName: string): Boolean;
begin
  Result := (FView <> nil) and (FView.Buffer <> nil) and SameText(AFileName, FView.Buffer.FileName);
end;

function TAtlasIdeMultiCursorState.Shows(const AView: IOTAEditView): Boolean;
begin
  Result := (AView <> nil) and (AView.Buffer <> nil) and ShowsFile(AView.Buffer.FileName);
end;

function TAtlasIdeMultiCursorState.LineText(ALine: Integer): string;
begin
  Result := LineOf(FLines, ALine);
end;

procedure TAtlasIdeMultiCursorState.Clear;
begin
  FCarets := nil;
  FSteps := nil;
  FStep := 0;
  FView := nil;
  FText := '';
  FLines := nil;
end;

function TAtlasIdeMultiCursorState.Prepare(out AView: IOTAEditView; out AText: string): Boolean;
var
  mMain: TAtlasCaret;
begin
  Result := False;
  AText := '';
  AView := TAtlasEditorBuffer.ActiveView;
  if (AView = nil) or (AView.Buffer = nil) or AView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  if Active and not Shows(AView) then
  begin
    FOnFinish();
  end;
  AText := TAtlasEditorBuffer.Text(AView.Buffer);
  // Eine Änderung, deren Meldung noch aussteht, zuerst nachziehen.
  if Active and (AText <> FText) then
  begin
    Reconcile(AText);
    AText := FText;
  end;
  mMain := ReadMain(AView);
  if Active then
  begin
    FCarets[0] := mMain;
    FCarets := TAtlasMultiCursor.Merge(FCarets);
  end
  else
  begin
    FCarets := [mMain];
    FView := AView;
    SetText(AText);
  end;
  Result := True;
end;

procedure TAtlasIdeMultiCursorState.WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string);
var
  mWriter: IOTAEditWriter;
  mStart, mOldLength: Integer;
  mInsert: string;
begin
  if not TAtlasLineMover.Difference(AText, ANewText, mStart, mOldLength, mInsert) then
  begin
    Exit;
  end;
  FWriting := True;
  try
    // Ein Schreiber: ein Rückgängig-Schritt für alle Marken.
    mWriter := ABuffer.CreateUndoableWriter;
    mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, mStart)));
    mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, mStart + mOldLength)));
    if mInsert <> '' then
    begin
      mWriter.Insert(PAnsiChar(UTF8Encode(mInsert)));
    end;
    mWriter := nil;
  finally
    FWriting := False;
  end;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

procedure TAtlasIdeMultiCursorState.AddStep(const ABefore, AAfter: string; const ABeforeCarets,
  AAfterCarets: TAtlasCarets);
var
  mStep: TStep;
begin
  // Ein neuer Schritt verwirft, was nach dem aktuellen wiederholt werden könnte.
  SetLength(FSteps, FStep);
  mStep.Before := ABefore;
  mStep.After := AAfter;
  mStep.BeforeCarets := Copy(ABeforeCarets);
  mStep.AfterCarets := Copy(AAfterCarets);
  FSteps := FSteps + [mStep];
  if Length(FSteps) > cStepLimit then
  begin
    Delete(FSteps, 0, 1);
  end;
  FStep := Length(FSteps);
end;

procedure TAtlasIdeMultiCursorState.Apply(const AView: IOTAEditView; const AText, ANewText: string;
  const ACarets: TAtlasCarets);
begin
  WriteBuffer(AView.Buffer, AText, ANewText);
  AddStep(AText, ANewText, FCarets, ACarets);
  SetCarets(AView, ANewText, ACarets);
end;

procedure TAtlasIdeMultiCursorState.SetCarets(const AView: IOTAEditView; const AText: string;
  const ACarets: TAtlasCarets);
begin
  FCarets := Copy(ACarets);
  FView := AView;
  SetText(AText);
  if Length(FCarets) > 0 then
  begin
    WriteMain(AView, FLines, FCarets[0]);
  end;
  FOnRefresh();
end;

procedure TAtlasIdeMultiCursorState.SetText(const AText: string);
begin
  FText := AText;
  FLines := TAtlasMultiCursor.Lines(AText);
end;

procedure TAtlasIdeMultiCursorState.SyncMain;
begin
  if not Active or (FView = nil) or (FView.Buffer = nil) then
  begin
    Exit;
  end;
  FCarets[0] := ReadMain(FView);
  FCarets := TAtlasMultiCursor.Merge(FCarets);
end;

procedure TAtlasIdeMultiCursorState.Reconcile(const AText: string);
var
  mMirrored: string;
  mCarets: TAtlasCarets;
begin
  if not Active or (AText = FText) then
  begin
    Exit;
  end;
  // Rückgängig bzw. Wiederholen eines eigenen Schritts: dessen Marken.
  if (FStep > 0) and (AText = FSteps[FStep - 1].Before) then
  begin
    FCarets := Copy(FSteps[FStep - 1].BeforeCarets);
    Dec(FStep);
    SetText(AText);
    Exit;
  end;
  if (FStep < Length(FSteps)) and (AText = FSteps[FStep].After) then
  begin
    FCarets := Copy(FSteps[FStep].AfterCarets);
    Inc(FStep);
    SetText(AText);
    Exit;
  end;
  // Fremde Änderung: an der Hauptmarke an allen Marken ausführen, sonst die Marken verschieben.
  FSteps := nil;
  FStep := 0;
  if TAtlasMultiCursor.Mirror(FText, AText, FCarets, mMirrored, mCarets) then
  begin
    WriteBuffer(FView.Buffer, AText, mMirrored);
    SetText(mMirrored);
    FCarets := mCarets;
    WriteMain(FView, FLines, FCarets[0]);
  end
  else
  begin
    FCarets := TAtlasMultiCursor.Shift(FText, AText, FCarets);
    SetText(AText);
  end;
end;

procedure TAtlasIdeMultiCursorState.DoEdit(AKind: TAtlasCaretEditKind; const AInsert: string);
var
  mView: IOTAEditView;
  mText, mNewText: string;
  mCarets: TAtlasCarets;
begin
  if Prepare(mView, mText) and TAtlasMultiCursor.Edit(mText, FCarets, AKind, AInsert, mNewText, mCarets) then
  begin
    Apply(mView, mText, mNewText, mCarets);
  end;
end;

function TAtlasIdeMultiCursorState.DoWrap(AOpen: Char): Boolean;
var
  mView: IOTAEditView;
  mText: string;
  mWrapped: TAtlasWrapResult;
begin
  Result := TAtlasIdeWrapSelection.Enabled and TAtlasWrapSelection.Accepts(AOpen, TAtlasIdeWrapSelection.Chars) and
    Prepare(mView, mText) and TAtlasWrapSelection.Wrap(TAtlasMultiCursor.Lines(mText), RangesOf(FCarets), AOpen,
    TAtlasIdeWrapSelection.Chars, mWrapped);
  if Result then
  begin
    Apply(mView, mText, string.Join(TAtlasMultiCursor.LineBreakOf(mText), mWrapped.Lines),
      CaretsOf(mWrapped.Selections));
  end;
end;

procedure TAtlasIdeMultiCursorState.DoMove(AMove: TAtlasCaretMove; AExtend: Boolean);
var
  mView: IOTAEditView;
  mText: string;
begin
  if Prepare(mView, mText) then
  begin
    SetCarets(mView, mText, TAtlasMultiCursor.Move(FLines, FCarets, AMove, AExtend,
      TAtlasEditorBuffer.TabWidth(mView.Buffer)));
  end;
end;

function TAtlasIdeMultiCursorState.DoCopy: Boolean;
var
  mView: IOTAEditView;
  mText, mSelected: string;
begin
  Result := False;
  if not Prepare(mView, mText) then
  begin
    Exit;
  end;
  mSelected := TAtlasMultiCursor.SelectedText(mText, FCarets, TAtlasMultiCursor.LineBreakOf(mText));
  // Ohne Markierung bleibt Kopieren der IDE.
  Result := mSelected <> '';
  if Result then
  begin
    Clipboard.AsText := mSelected;
  end;
end;

procedure TAtlasIdeMultiCursorState.DoCut;
begin
  if DoCopy then
  begin
    DoEdit(TAtlasCaretEditKind.Insert, '');
  end;
end;

procedure TAtlasIdeMultiCursorState.DoPaste;
var
  mView: IOTAEditView;
  mText, mNewText, mClip: string;
  mCarets: TAtlasCarets;
begin
  if not Clipboard.HasFormat(CF_UNICODETEXT) and not Clipboard.HasFormat(CF_TEXT) then
  begin
    Exit;
  end;
  mClip := Clipboard.AsText;
  if (mClip <> '') and Prepare(mView, mText) and TAtlasMultiCursor.Paste(mText, FCarets, mClip, mNewText, mCarets) then
  begin
    Apply(mView, mText, mNewText, mCarets);
  end;
end;

procedure TAtlasIdeMultiCursorState.DoSkip;
var
  mView: IOTAEditView;
  mText: string;
  mCarets: TAtlasCarets;
begin
  if not Prepare(mView, mText) or not TAtlasMultiCursor.SkipOccurrence(FLines, FCarets, False, False, mCarets) then
  begin
    Exit;
  end;
  SetCarets(mView, mText, mCarets);
  if Length(mCarets) > 0 then
  begin
    EnsureVisible(mView, mCarets[High(mCarets)].Line);
  end;
end;

function TAtlasIdeMultiCursorState.Next: Boolean;
var
  mView: IOTAEditView;
  mText: string;
  mCarets: TAtlasCarets;
  mWas: Boolean;
begin
  Result := False;
  mWas := Active;
  if not Prepare(mView, mText) then
  begin
    Exit;
  end;
  case TAtlasMultiCursor.NextOccurrence(FLines, FCarets, False, False, mCarets) of
    TAtlasOccurrence.WordSelected:
      begin
        WriteMain(mView, FLines, mCarets[0]);
        FCarets := mCarets;
        mView.Paint;
        Result := True;
      end;
    TAtlasOccurrence.Added:
      begin
        SetCarets(mView, mText, mCarets);
        EnsureVisible(mView, mCarets[High(mCarets)].Line);
        Result := True;
      end;
  else
    // Kein Wort am Cursor: ohne Marken bekommt die IDE die Taste (Quelltext formatieren).
    Result := mWas;
    if not mWas then
    begin
      FCarets := nil;
    end;
  end;
end;

function TAtlasIdeMultiCursorState.LineEnds: Boolean;
var
  mView: IOTAEditView;
  mText: string;
begin
  Result := Prepare(mView, mText) and FCarets[0].HasSelection;
  if Result then
  begin
    SetCarets(mView, mText, TAtlasMultiCursor.LineEnds(FLines, FCarets[0]));
    mView.Paint;
  end;
end;

function TAtlasIdeMultiCursorState.Vertical(AUp: Boolean): Boolean;
var
  mView: IOTAEditView;
  mText: string;
  mCarets: TAtlasCarets;
begin
  Result := Prepare(mView, mText) and TAtlasMultiCursor.AddVertical(FLines, FCarets, AUp,
    TAtlasEditorBuffer.TabWidth(mView.Buffer), mCarets);
  if Result then
  begin
    SetCarets(mView, mText, mCarets);
    EnsureVisible(mView, mCarets[High(mCarets)].Line);
  end;
end;

function TAtlasIdeMultiCursorState.Toggle(const AFileName: string; ALine, AColumn: Integer): Boolean;
var
  mView: IOTAEditView;
  mText, mLineText: string;
  mCharacter: Integer;
begin
  Result := Prepare(mView, mText) and SameText(AFileName, mView.Buffer.FileName);
  if not Result then
  begin
    Exit;
  end;
  mLineText := LineOf(FLines, ALine);
  mCharacter := Min(TLspSession.ColumnToIndex(mLineText, AColumn, TAtlasEditorBuffer.TabWidth(mView.Buffer)),
    Length(mLineText));
  SetCarets(mView, mText, TAtlasMultiCursor.Toggle(FCarets, ALine, mCharacter));
  mView.Paint;
end;

end.
