unit Atlas.IDE.Completion.Placeholders;

// Platzhalter-Modus im Editor nach dem Einsetzen einer Code-Vorlage (#51).
// Die IDE kennt keine LSP-Snippets; Atlas führt die Platzhalter selbst
// (Modell: Atlas.Core.Completion.Placeholders).
//   - Der aktuelle Platzhalter ist markiert, Tippen ersetzt die Vorgabe.
//   - Tab springt weiter, Umschalt+Tab zurück, nach dem letzten an die
//     Endposition ($0). Enter beendet und springt an die Endposition, Esc
//     beendet an Ort und Stelle. Die Tasten kommen über den gemeinsamen Hook
//     (Priorität nach Vervollständigung und Parameter-Hint), nur solange der
//     Modus läuft.
//   - Verknüpfte Platzhalter: Nach jeder Änderung im aktuellen Platzhalter
//     gleicht Atlas die übrigen mit derselben Nummer an (gleich danach per
//     ForceQueue, nicht in der Benachrichtigung).
//   - Zeichnen: aktueller Platzhalter durchgezogen umrahmt, verknüpfte
//     gestrichelt, die übrigen gepunktet; hinter der Zeile die Fußzeile
//     „Platzhalter 1 / 3 · Tab weiter · Esc fertig“.
//   - Eine Änderung außerhalb, ein Wechsel der Ansicht oder Esc beendet den Modus.
//   - Ein Undo-Schritt: Endet der Modus regulär (Esc, Enter, Tab nach dem
//     letzten Platzhalter), nimmt Atlas das Einsetzen, alle Eingaben und
//     Angleichungen über IOTAEditBuffer.Undo bis zum Stand vor dem Einsetzen
//     zurück und schreibt das Ergebnis mit einem einzigen Schreiber neu. Ein
//     Strg+Z danach stellt den Stand vor der Vorlage wieder her. Wird der Stand
//     vor dem Einsetzen nicht erreicht (z. B. weil die IDE Schritte
//     zusammengefasst hat), stellt Redo alles wieder her und es bleibt bei
//     mehreren Schritten. Endet der Modus durch eine Änderung außerhalb, bleibt
//     die Undo-Liste unberührt.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Placeholders,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasEditorPlaceholders = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    TKeys = class(TAtlasKeyClient)
    private
      FOwner: TAtlasEditorPlaceholders;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    public
      constructor Create(AOwner: TAtlasEditorPlaceholders);
    end;
  private
    FSession: TAtlasPlaceholderSession;
    FView: IOTAEditView;
    FFileName: string;
    FKeys: TKeys;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FEventsIndex: Integer;
    // Atlas schreibt gerade selbst (verknüpfte Platzhalter): Benachrichtigungen übergehen.
    FApplying: Boolean;
    FMirrorQueued: Boolean;
    // Puffertext vor dem Einsetzen, für den gemeinsamen Undo-Schritt.
    FBefore: string;
    procedure CollapseUndo;
    procedure SelectCurrent;
    /// <summary>Rahmen und Fußzeile neu zeichnen lassen.</summary>
    procedure Invalidate;
    procedure MoveTo(AOffset: Integer);
    procedure Finish(AToEnd: Boolean);
    procedure ApplyMirrors;
    function CursorOffset(const AText: string): Integer;
    function EditPos(const AText: string; AOffset: Integer): TOTAEditPos;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>ABefore: Puffertext vor dem Einsetzen, ADocument: Text danach, AOffset: Anfang der Vorlage
    /// darin. Ohne Platzhalter steht nur der Cursor an der Endposition.</summary>
    procedure Start(const AView: IOTAEditView; const ABefore, ADocument: string; AOffset: Integer;
      const AExpansion: TAtlasSnippetExpansion); overload;
    /// <summary>Wie oben, mit verknüpften Platzhaltern außerhalb der Vorlage (Offsets in ADocument, #473).</summary>
    procedure Start(const AView: IOTAEditView; const ABefore, ADocument: string; AOffset: Integer;
      const AExpansion: TAtlasSnippetExpansion; const ALinked: TArray<TAtlasPlaceholderField>); overload;
    procedure Stop;
    function Active: Boolean;
    /// <summary>Aus EditorViewModified.</summary>
    procedure EditorModified(const AView: IOTAEditView);
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorRefresh;

/// <summary>Zeile ALine (0-basiert) aus AText ohne Zeilenende.</summary>
function LineOf(const AText: string; ALine: Integer): string;
var
  Lines: TArray<string>;
begin
  Lines := AText.Replace(#13, '').Split([#10]);
  if (ALine >= 0) and (ALine <= High(Lines)) then
  begin
    Result := Lines[ALine];
  end
  else
  begin
    Result := '';
  end;
end;

function ByteOffset(const AText: string; AOffset: Integer): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(Copy(AText, 1, AOffset));
end;

{ TAtlasEditorPlaceholders.TEvents }

function TAtlasEditorPlaceholders.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasEditorPlaceholders.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorPlaceholders.TKeys }

constructor TAtlasEditorPlaceholders.TKeys.Create(AOwner: TAtlasEditorPlaceholders);
begin
  // Nach Vervollständigung (0) und Parameter-Hint (10): Tab und Esc gehören zuerst deren Fenstern.
  inherited Create(20);
  FOwner := AOwner;
end;

function TAtlasEditorPlaceholders.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
end;

procedure TAtlasEditorPlaceholders.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.HandleKey(AKey, AShift);
  except
    on E: Exception do
    begin
      FOwner.Stop;
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

{ TAtlasEditorPlaceholders }

constructor TAtlasEditorPlaceholders.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FKeys := TKeys.Create(Self);
  FEventsIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FEventsIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasEditorPlaceholders.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  Stop;
  if (FEventsIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FEventsIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
  end;
  FEventsRef := nil;
  FKeys.Free;
  inherited Destroy;
end;

function TAtlasEditorPlaceholders.Active: Boolean;
begin
  Result := FSession <> nil;
end;

procedure TAtlasEditorPlaceholders.Start(const AView: IOTAEditView; const ABefore, ADocument: string;
  AOffset: Integer; const AExpansion: TAtlasSnippetExpansion);
begin
  Start(AView, ABefore, ADocument, AOffset, AExpansion, nil);
end;

procedure TAtlasEditorPlaceholders.Start(const AView: IOTAEditView; const ABefore, ADocument: string;
  AOffset: Integer; const AExpansion: TAtlasSnippetExpansion; const ALinked: TArray<TAtlasPlaceholderField>);
var
  Field: TAtlasPlaceholderField;
begin
  Stop;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  FView := AView;
  FFileName := AView.Buffer.FileName;
  FBefore := ABefore;
  FSession := TAtlasPlaceholderSession.Create(ADocument, AOffset, AExpansion);
  for Field in ALinked do
  begin
    FSession.Link(Field);
  end;
  if not AExpansion.HasPlaceholders then
  begin
    Finish(True);
    Exit;
  end;
  TAtlasKeyHook.Add(FKeys);
  SelectCurrent;
end;

procedure TAtlasEditorPlaceholders.Stop;
var
  WasActive: Boolean;
begin
  WasActive := Active;
  TAtlasKeyHook.Remove(FKeys);
  FreeAndNil(FSession);
  FView := nil;
  FBefore := '';
  FMirrorQueued := False;
  // Rahmen und Fußzeile verschwinden.
  if WasActive then
  begin
    Invalidate;
  end;
end;

procedure TAtlasEditorPlaceholders.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

function TAtlasEditorPlaceholders.EditPos(const AText: string; AOffset: Integer): TOTAEditPos;
var
  Line, Character: Integer;
begin
  TAtlasPlaceholderSession.Locate(AText, AOffset, Line, Character);
  Result.Line := Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineOf(AText, Line), Character, TAtlasEditorBuffer.TabWidth(FView.Buffer));
end;

function TAtlasEditorPlaceholders.CursorOffset(const AText: string): Integer;
var
  Cursor: TOTAEditPos;
  LineText: string;
begin
  Cursor := FView.CursorPos;
  LineText := TAtlasEditorBuffer.LineText(FView, Cursor.Line);
  Result := TAtlasEditorBuffer.CharOffset(AText, Cursor.Line - 1,
    TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(FView.Buffer)));
end;

procedure TAtlasEditorPlaceholders.MoveTo(AOffset: Integer);
begin
  FView.Block.Reset;
  FView.CursorPos := EditPos(FSession.Text, AOffset);
  FView.MoveViewToCursor;
  FView.Paint;
end;

procedure TAtlasEditorPlaceholders.SelectCurrent;
var
  Field: TAtlasPlaceholderField;
begin
  Field := FSession.Current;
  if Field.Length = 0 then
  begin
    MoveTo(Field.Start);
  end
  else
  begin
    // Wie Auswahl erweitern (#399): Anfang markieren, Cursor ans Ende, Ende markieren. Tippen ersetzt die Vorgabe.
    FView.Block.Style := btNonInclusive;
    FView.CursorPos := EditPos(FSession.Text, Field.Start);
    FView.Block.BeginBlock;
    FView.CursorPos := EditPos(FSession.Text, Field.Stop);
    FView.Block.EndBlock;
    FView.MoveViewToCursor;
    FView.Paint;
  end;
end;

procedure TAtlasEditorPlaceholders.Finish(AToEnd: Boolean);
var
  Cursor: Integer;
begin
  if (FSession <> nil) and (FView <> nil) then
  begin
    Cursor := CursorOffset(FSession.Text);
    CollapseUndo;
    if AToEnd then
    begin
      MoveTo(FSession.FinalOffset);
    end
    else
    begin
      FView.CursorPos := EditPos(FSession.Text, Cursor);
      FView.Paint;
    end;
  end;
  Stop;
end;

procedure TAtlasEditorPlaceholders.CollapseUndo;
const
  // Obergrenze der Undo-Schritte; eine Vorlage braucht selten mehr als ein paar Dutzend.
  MaxSteps = 1000;
var
  Final, Text: string;
  Steps, Index, Prefix, Suffix: Integer;
  Writer: IOTAEditWriter;
begin
  if (FSession = nil) or (FView = nil) or (FView.Buffer = nil) or (FBefore = '') then
  begin
    Exit;
  end;
  Final := TAtlasEditorBuffer.Text(FView.Buffer);
  if Final <> FSession.Text then
  begin
    Exit;
  end;
  FApplying := True;
  try
    Steps := 0;
    Text := Final;
    while (Text <> FBefore) and (Steps < MaxSteps) and FView.Buffer.Undo do
    begin
      Inc(Steps);
      Text := TAtlasEditorBuffer.Text(FView.Buffer);
    end;
    if Text <> FBefore then
    begin
      // Stand vor dem Einsetzen nicht erreicht: alles wiederherstellen.
      for Index := 1 to Steps do
      begin
        if not FView.Buffer.Redo then
        begin
          Break;
        end;
      end;
      Exit;
    end;
    // Gemeinsamer Anfang und gemeinsames Ende; dazwischen ersetzt ein Schreiber.
    Prefix := 0;
    while (Prefix < Length(FBefore)) and (Prefix < Length(Final)) and (FBefore[Prefix + 1] = Final[Prefix + 1]) do
    begin
      Inc(Prefix);
    end;
    Suffix := 0;
    while (Suffix < Length(FBefore) - Prefix) and (Suffix < Length(Final) - Prefix) and
      (FBefore[Length(FBefore) - Suffix] = Final[Length(Final) - Suffix]) do
    begin
      Inc(Suffix);
    end;
    Writer := FView.Buffer.CreateUndoableWriter;
    Writer.CopyTo(ByteOffset(FBefore, Prefix));
    Writer.DeleteTo(ByteOffset(FBefore, Length(FBefore) - Suffix));
    Writer.Insert(PAnsiChar(UTF8Encode(Copy(Final, Prefix + 1, Length(Final) - Prefix - Suffix))));
    Writer := nil;
  finally
    FApplying := False;
  end;
end;

function TAtlasEditorPlaceholders.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := Active and ((AKey = VK_TAB) and ((AShift = []) or (AShift = [ssShift])) or
    ((AKey = VK_ESCAPE) or (AKey = VK_RETURN)) and (AShift = []));
end;

procedure TAtlasEditorPlaceholders.HandleKey(AKey: Word; AShift: TShiftState);
begin
  if not Active then
  begin
    Exit;
  end;
  // Vor dem Springen noch ausstehende Angleichungen schreiben.
  ApplyMirrors;
  if not Active then
  begin
    Exit;
  end;
  case AKey of
    VK_TAB:
      if AShift = [ssShift] then
      begin
        FSession.Previous;
        SelectCurrent;
      end
      else if FSession.Next then
      begin
        SelectCurrent;
      end
      else
      begin
        Finish(True);
      end;
    VK_RETURN:
      Finish(True);
    VK_ESCAPE:
      Finish(False);
  end;
  if Active then
  begin
    Invalidate;
  end;
end;

procedure TAtlasEditorPlaceholders.EditorModified(const AView: IOTAEditView);
begin
  if FApplying or not Active or (AView = nil) or (AView.Buffer = nil) or
    not SameText(AView.Buffer.FileName, FFileName) then
  begin
    Exit;
  end;
  if not FSession.Update(TAtlasEditorBuffer.Text(AView.Buffer)) then
  begin
    Stop;
    Exit;
  end;
  if (Length(FSession.MirrorEdits) > 0) and not FMirrorQueued then
  begin
    FMirrorQueued := True;
    // Nicht im Benachrichtigungsaufruf selbst schreiben, sondern gleich danach.
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion,
      procedure
      begin
        try
          ApplyMirrors;
        except
          on E: Exception do
          begin
            Stop;
            TAtlasGuard.Report(TAtlasFeature.Completion, E);
          end;
        end;
      end);
  end;
end;

procedure TAtlasEditorPlaceholders.ApplyMirrors;
var
  Edits: TAtlasPlaceholderEdits;
  Edit: TAtlasPlaceholderEdit;
  Text: string;
  Writer: IOTAEditWriter;
  Cursor, Shift: Integer;
begin
  FMirrorQueued := False;
  if not Active or (FView = nil) or (FView.Buffer = nil) then
  begin
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(FView.Buffer);
  if not FSession.Update(Text) then
  begin
    Stop;
    Exit;
  end;
  Edits := FSession.MirrorEdits;
  if Length(Edits) = 0 then
  begin
    Exit;
  end;
  Cursor := CursorOffset(Text);
  Shift := 0;
  FApplying := True;
  try
    // Ein Schreiber schreibt nur vorwärts; die Änderungen sind aufsteigend.
    Writer := FView.Buffer.CreateUndoableWriter;
    for Edit in Edits do
    begin
      Writer.CopyTo(ByteOffset(Text, Edit.Start));
      Writer.DeleteTo(ByteOffset(Text, Edit.Stop));
      Writer.Insert(PAnsiChar(UTF8Encode(Edit.Text)));
      if Edit.Stop <= Cursor then
      begin
        Inc(Shift, Length(Edit.Text) - (Edit.Stop - Edit.Start));
      end;
    end;
    Writer := nil;
  finally
    FApplying := False;
  end;
  FSession.Applied(Edits);
  // Der Cursor bleibt an seiner Stelle im Text, auch wenn davor ein verknüpfter Platzhalter wuchs.
  FView.CursorPos := EditPos(FSession.Text, Cursor + Shift);
  FView.Paint;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

/// <summary>Zeichnet PaintLine für AContext: Modus läuft, Ansicht mit Puffer, Datei des Modus.</summary>
function PaintsLine(ASession: TAtlasPlaceholderSession; const AFileName: string;
  const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := (ASession <> nil) and (AContext <> nil) and (AContext.LineState <> nil) and (AContext.EditView <> nil);
  Result := Result and (AContext.EditView.Buffer <> nil) and SameText(AContext.FileName, AFileName);
end;

type
  /// <summary>Rahmen und Fußzeile der Platzhalter in einer Editorzeile (PaintLine).</summary>
  TPlaceholderPaint = record
    Session: TAtlasPlaceholderSession;
    Context: INTACodeEditorPaintContext;
    Area: TRect;
    Colors: TAtlasColors;
    DC: HDC;
    /// <summary>Zeile (0-basiert) und ihr Text im Modell.</summary>
    Line: Integer;
    Text: string;
    TabWidth: Integer;
    /// <summary>Entspricht die Zeile im Editor dem Stand des Modells?</summary>
    function Matches: Boolean;
    /// <summary>Linker Rand des Zeichens ACharacter (0-basiert) der Zeile in Pixeln.</summary>
    function Pixel(ACharacter: Integer): Integer;
    /// <summary>Aktueller Platzhalter durchgezogen, verknüpfte gestrichelt, die übrigen gepunktet.</summary>
    procedure Frame(const AField, ACurrent: TAtlasPlaceholderField);
    procedure Frames;
    /// <summary>Fußzeile hinter der Zeile des aktuellen Platzhalters.</summary>
    procedure Footer;
  end;

{ TPlaceholderPaint }

function TPlaceholderPaint.Matches: Boolean;
begin
  Result := TrimRight(TAtlasPairs.DisplayLine(Context.LineState.Text, TabWidth)) =
    TrimRight(TAtlasPairs.DisplayLine(Text, TabWidth));
end;

function TPlaceholderPaint.Pixel(ACharacter: Integer): Integer;
begin
  Result := Context.EditorState.GetCharacterPosPx(ColumnOf(Text, ACharacter, TabWidth), Context.EditorLineNum).Left;
end;

procedure TPlaceholderPaint.Frame(const AField, ACurrent: TAtlasPlaceholderField);
var
  mStartLine, mStartChar, mEndLine, mEndChar, mLeft, mRight, mPenStyle: Integer;
  mColor: TColor;
  mPen, mOldPen: HGDIOBJ;
begin
  TAtlasPlaceholderSession.Locate(Session.Text, AField.Start, mStartLine, mStartChar);
  TAtlasPlaceholderSession.Locate(Session.Text, AField.Stop, mEndLine, mEndChar);
  if mStartLine <> Line then
  begin
    Exit;
  end;
  if mEndLine <> Line then
  begin
    mEndChar := Length(Text);
  end;
  mLeft := Pixel(mStartChar) - 1;
  mRight := Max(Pixel(mEndChar) + 1, mLeft + 2);
  if (AField.Start = ACurrent.Start) and (AField.Number = ACurrent.Number) then
  begin
    mPenStyle := PS_SOLID;
    mColor := TColor(Colors.Accent);
  end
  else if AField.Number = ACurrent.Number then
  begin
    mPenStyle := PS_DASH;
    mColor := TColor(Colors.Accent);
  end
  else
  begin
    mPenStyle := PS_DOT;
    mColor := TColor(Colors.Muted);
  end;
  mPen := CreatePen(mPenStyle, 1, ColorToRGB(mColor));
  mOldPen := SelectObject(DC, mPen);
  try
    Winapi.Windows.Rectangle(DC, mLeft, Area.Top, mRight, Area.Bottom);
  finally
    SelectObject(DC, mOldPen);
    DeleteObject(mPen);
  end;
end;

procedure TPlaceholderPaint.Frames;
var
  mField, mCurrent: TAtlasPlaceholderField;
  mOldBrush: HGDIOBJ;
begin
  mCurrent := Session.Current;
  mOldBrush := SelectObject(DC, GetStockObject(NULL_BRUSH));
  for mField in Session.Fields do
  begin
    Frame(mField, mCurrent);
  end;
  SelectObject(DC, mOldBrush);
end;

procedure TPlaceholderPaint.Footer;
var
  mStartLine, mStartChar, mLeft: Integer;
  mHint: string;
  mOldFont: TColor;
  mOldBrushStyle: TBrushStyle;
begin
  TAtlasPlaceholderSession.Locate(Session.Text, Session.Current.Start, mStartLine, mStartChar);
  if mStartLine <> Line then
  begin
    Exit;
  end;
  mHint := Format(TAtlasStrings.Text(TAtlasTextId.PlaceholderFooter), [Session.Position, Session.Count]);
  mLeft := Context.EditorState.GetCharacterPosPx(Length(TAtlasPairs.DisplayLine(Text, TabWidth)) + 4,
    Context.EditorLineNum).Left;
  mOldFont := Context.Canvas.Font.Color;
  mOldBrushStyle := Context.Canvas.Brush.Style;
  try
    Context.Canvas.Font.Color := TColor(Colors.Muted);
    Context.Canvas.Brush.Style := bsClear;
    Context.Canvas.TextOut(mLeft, Area.Top, mHint);
  finally
    Context.Canvas.Font.Color := mOldFont;
    Context.Canvas.Brush.Style := mOldBrushStyle;
  end;
end;

procedure TAtlasEditorPlaceholders.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mPaint: TPlaceholderPaint;
  mSaved: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or not PaintsLine(FSession, FFileName, Context) then
  begin
    Exit;
  end;
  try
    mPaint.Session := FSession;
    mPaint.Context := Context;
    mPaint.Area := Rect;
    mPaint.Line := Context.LogicalLineNum - 1;
    mPaint.Text := LineOf(FSession.Text, mPaint.Line);
    mPaint.TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    if not mPaint.Matches then
    begin
      Exit;
    end;
    mPaint.Colors := TAtlasIdeStyle.Colors;
    mPaint.DC := Context.Canvas.Handle;
    mSaved := SaveDC(mPaint.DC);
    try
      mPaint.Frames;
      mPaint.Footer;
    finally
      RestoreDC(mPaint.DC, mSaved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

end.
