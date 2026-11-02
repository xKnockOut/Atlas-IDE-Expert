unit Atlas.IDE.Editor.SelectionMatches;

// Gleichen Text wie die Markierung hervorheben (#709) im Editor. Was zählt und
// wo die Treffer liegen, rechnet Atlas.Core.Editor.SelectionMatches aus; hier
// bleiben Zeitgeber und Zeichnen.
// - Ein Zeitgeber (100 ms) liest die Markierung der Ansicht vorn. Zählt sie
//   (einzeilig, Mindestlänge, nicht nur Leerraum), sucht er die Treffer im
//   Stand des Puffers (TAtlasEditorSnapshots, liest nur bei Änderungen neu),
//   bei Dateien ab TAtlasSelectionMatches.LargeFileLines Zeilen nur im
//   sichtbaren Bereich. Neu gezeichnet wird nur bei geänderten Treffern.
// - PaintLine (plsEndPaint) überzieht jeden Treffer außer der Markierung
//   selbst halb durchsichtig mit der Akzentfarbe; hinter dem Ende der
//   markierten Zeile steht die Anzahl („3 Treffer“, „mehr als 1000 Treffer“,
//   bei großen Dateien „… im sichtbaren Bereich“). Den Platz hinter dem
//   Zeilenende teilt die Marke mit den anderen Zeichnern (TAtlasLineTail).
// - Übersichtsleiste (#519) und F3 (Atlas.IDE.Commands.Editor) lesen dieselben
//   Optionen selbst.
// - highlight.selectionMatches aus oder Atlas aus: keine Hervorhebung. Je
//   Datei oder überall ausblenden über das Element SelectionMatches (#628) an
//   der Anzahl.
// Gesichert über TAtlasFeature.SelectionMatches (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Style.Color,
  Atlas.Core.Editor.SelectionMatches;

type
  TAtlasIdeSelectionMatches = class
  private const
    TickMs = 100;
    /// <summary>Deckkraft der Treffer über dem Text (0–255).</summary>
    MatchAlpha = 60;
    /// <summary>Anteil der Akzentfarbe am Hintergrund der Anzahl.</summary>
    MarkStrength = 0.16;
    /// <summary>Innenabstand der Anzahl links und rechts in Pixeln.</summary>
    MarkPadding = 4;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FFont: TFont;
    FFontKey: string;
    // Stand der Treffer: Datei, Suchtext, Optionen, Pufferstand und (bei großen Dateien) sichtbarer Bereich.
    FFileName: string;
    FTerm: string;
    FOptionsKey: string;
    FVersion: Cardinal;
    FFirstLine: Integer;
    FLastLine: Integer;
    FVisibleOnly: Boolean;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FMatches: TAtlasSelectionMatchList;
    FByLine: TDictionary<Integer, TArray<TAtlasSelectionMatch>>;
    // Markierung: Zeile und Zeichen ab 0, Ende ausschließlich.
    FSelectionLine: Integer;
    FSelectionStart: Integer;
    FSelectionStop: Integer;
    procedure TimerTick(Sender: TObject);
    procedure Update;
    procedure Clear;
    procedure BuildIndex;
    procedure EnsureFont(const AEditorFont: TFont);
    function CountText: string;
    procedure PaintMatches(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
      const AMatches: TArray<TAtlasSelectionMatch>; ABack: TAtlasColor);
    procedure PaintCount(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
      ABack: TAtlasColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Editor.Elements,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

function OptionsKey(const AOptions: TAtlasSelectionMatchOptions): string;
begin
  Result := Format('%d|%d|%d|%d', [AOptions.MinLength, Ord(AOptions.CaseSensitive), Ord(AOptions.WholeWord),
    AOptions.MaxMatches]);
end;

{ TAtlasIdeSelectionMatches.TEvents }

function TAtlasIdeSelectionMatches.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeSelectionMatches.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeSelectionMatches }

constructor TAtlasIdeSelectionMatches.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FSelectionLine := -1;
  FByLine := TDictionary<Integer, TArray<TAtlasSelectionMatch>>.Create;
  FFont := TFont.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeSelectionMatches.Destroy;
var
  Services: INTACodeEditorServices;
  Painted: Boolean;
begin
  FreeAndNil(FTimer);
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  Painted := FTerm <> '';
  Clear;
  FreeAndNil(FByLine);
  FreeAndNil(FFont);
  if Painted then
    Invalidate;
  inherited;
end;

class procedure TAtlasIdeSelectionMatches.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

procedure TAtlasIdeSelectionMatches.Clear;
begin
  FFileName := '';
  FTerm := '';
  FOptionsKey := '';
  FVersion := 0;
  FLines := nil;
  FMatches := Default(TAtlasSelectionMatchList);
  if FByLine <> nil then
    FByLine.Clear;
  FSelectionLine := -1;
  FVisibleOnly := False;
end;

procedure TAtlasIdeSelectionMatches.BuildIndex;
var
  Match: TAtlasSelectionMatch;
  Matches: TArray<TAtlasSelectionMatch>;
begin
  FByLine.Clear;
  for Match in FMatches.Matches do
  begin
    if not FByLine.TryGetValue(Match.Line, Matches) then
      Matches := nil;
    FByLine.AddOrSetValue(Match.Line, Matches + [Match]);
  end;
end;

procedure TAtlasIdeSelectionMatches.TimerTick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.SelectionMatches, E);
  end;
end;

procedure TAtlasIdeSelectionMatches.Update;
var
  Options: TAtlasSelectionMatchOptions;
  NavigateF3, VisibleOnly: Boolean;
  View: IOTAEditView;
  Block: IOTAEditBlock;
  Snapshot: TAtlasEditorSnapshot;
  Term, Key, LineText: string;
  Row, First, Last, Start, Stop: Integer;
begin
  View := nil;
  Term := '';
  if TAtlasIdeSettings.SelectionMatchesOn(Options, NavigateF3) and
    not TAtlasGuard.Disabled(TAtlasFeature.SelectionMatches) then
    View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) then
  begin
    Block := View.Block;
    if (Block <> nil) and Block.IsValid and (Block.Size > 0) and (Block.StartingRow = Block.EndingRow) then
      TAtlasSelectionMatches.Term(Block.Text, Options, Term);
  end;
  if Term = '' then
  begin
    if FTerm <> '' then
    begin
      Clear;
      Invalidate;
    end;
    Exit;
  end;
  Snapshot := TAtlasEditorSnapshots.Get(View);
  Key := OptionsKey(Options);
  if (Snapshot.Version <> FVersion) or not SameText(Snapshot.FileName, FFileName) then
  begin
    FLines := TTextLines.SplitLines(Snapshot.Text);
    FTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  end;
  Row := Block.StartingRow - 1;
  LineText := '';
  if (Row >= 0) and (Row < Length(FLines)) then
    LineText := FLines[Row];
  Start := TLspSession.ColumnToIndex(LineText, Block.StartingColumn, FTabWidth);
  Stop := TLspSession.ColumnToIndex(LineText, Block.EndingColumn, FTabWidth);
  // Sehr große Dateien: nur der sichtbare Bereich.
  VisibleOnly := Length(FLines) > TAtlasSelectionMatches.LargeFileLines;
  First := 0;
  Last := High(FLines);
  if VisibleOnly then
  begin
    First := View.TopRow - 1;
    Last := View.BottomRow - 1;
  end;
  if (Term = FTerm) and (Key = FOptionsKey) and (Snapshot.Version = FVersion) and
    SameText(Snapshot.FileName, FFileName) and (Row = FSelectionLine) and (Start = FSelectionStart) and
    (Stop = FSelectionStop) and (First = FFirstLine) and (Last = FLastLine) then
    Exit;
  FFileName := Snapshot.FileName;
  FTerm := Term;
  FOptionsKey := Key;
  FVersion := Snapshot.Version;
  FSelectionLine := Row;
  FSelectionStart := Start;
  FSelectionStop := Stop;
  FFirstLine := First;
  FLastLine := Last;
  FVisibleOnly := VisibleOnly;
  FMatches := TAtlasSelectionMatches.Find(FLines, Term, Options, First, Last);
  BuildIndex;
  Invalidate;
end;

procedure TAtlasIdeSelectionMatches.EnsureFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
    Exit;
  FFont.Assign(AEditorFont);
  FFont.Style := [];
  FFontKey := Key;
end;

function TAtlasIdeSelectionMatches.CountText: string;
begin
  if FVisibleOnly then
    Result := TAtlasStrings.Fmt(TAtlasTextId.SelectionMatchesVisible, [FMatches.Count])
  else if FMatches.Truncated then
    Result := TAtlasStrings.Fmt(TAtlasTextId.SelectionMatchesMore, [FMatches.Count])
  else if FMatches.Count = 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.SelectionMatchesOne)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.SelectionMatchesCount, [FMatches.Count]);
end;

procedure TAtlasIdeSelectionMatches.PaintMatches(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; const AMatches: TArray<TAtlasSelectionMatch>; ABack: TAtlasColor);
var
  Match: TAtlasSelectionMatch;
  First, Last, Code: TRect;
  Color: COLORREF;
  DC: HDC;
  Saved: Integer;
begin
  Color := COLORREF(ColorToRGB(TColor(TAtlasColors.ForBackground(ABack).Accent)));
  DC := Context.Canvas.Handle;
  Code := Context.LineState.CodeRect;
  Saved := SaveDC(DC);
  try
    if Code.Right > Code.Left then
      IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
    for Match in AMatches do
    begin
      // Die Markierung selbst zeichnet die IDE.
      if TAtlasSelectionMatches.IsSelection(Match, FSelectionLine, FSelectionStart, FSelectionStop) then
        Continue;
      First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Match.Character, FTabWidth),
        Context.EditorLineNum);
      Last := Context.EditorState.GetCharacterPosPx(
        TLspSession.IndexToColumn(AText, Match.Character + Match.Length, FTabWidth), Context.EditorLineNum);
      TAtlasIdeStyle.Blend(DC, TRect.Create(First.Left, Rect.Top, Max(Last.Left, First.Left + 1), Rect.Bottom), Color,
        MatchAlpha);
    end;
  finally
    RestoreDC(DC, Saved);
  end;
end;

procedure TAtlasIdeSelectionMatches.PaintCount(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; ABack: TAtlasColor);
var
  Caption, Key: string;
  Cell, Mark: TRect;
  Colors: TAtlasColors;
  DC: HDC;
  Saved, X, Top: Integer;
  Size: TSize;
  Brush: HBRUSH;
begin
  Caption := CountText;
  Cell := Context.EditorState.GetCharacterPosPx(
    TLspSession.IndexToColumn(AText, Length(TrimRight(AText)), FTabWidth) + 2, Context.EditorLineNum);
  Key := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
  X := TAtlasLineTail.Start(Self, Key, Cell.Left);
  Colors := TAtlasColors.ForBackground(ABack);
  EnsureFont(Context.Canvas.Font);
  DC := Context.Canvas.Handle;
  Saved := SaveDC(DC);
  Brush := CreateSolidBrush(COLORREF(ColorToRGB(TColor(TAtlasColorMath.Mix(Colors.Accent, ABack, MarkStrength)))));
  try
    SelectObject(DC, FFont.Handle);
    GetTextExtentPoint32W(DC, PChar(Caption), Length(Caption), Size);
    Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Size.cy) div 2);
    Mark := TRect.Create(X, Rect.Top + 1, X + Size.cx + 2 * MarkPadding, Rect.Bottom - 1);
    FillRect(DC, Mark, Brush);
    SetTextColor(DC, COLORREF(ColorToRGB(TColor(Colors.Accent))));
    SetBkMode(DC, TRANSPARENT);
    TextOutW(DC, X + MarkPadding, Top, PChar(Caption), Length(Caption));
  finally
    DeleteObject(Brush);
    RestoreDC(DC, Saved);
  end;
  TAtlasLineTail.Finish(Self, Key, Mark.Right);
  TAtlasIdeElements.Painted(TAtlasDrawnElement.SelectionMatches, Context.FileName, FSelectionLine, AText, Mark,
    Context.EditView.TopRow, Rect.Height);
end;

procedure TAtlasIdeSelectionMatches.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Matches: TArray<TAtlasSelectionMatch>;
  Text: string;
  Line: Integer;
  Back: TAtlasColor;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FTerm = '') or
    TAtlasGuard.Disabled(TAtlasFeature.SelectionMatches) then
    Exit;
  try
    if not SameText(Context.FileName, FFileName) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.SelectionMatches, Context.FileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line >= Length(FLines)) then
      Exit;
    Text := FLines[Line];
    // Nur, wenn die Zeile im Editor dem gesuchten Stand entspricht (sonst kommt gleich ein neuer Takt).
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    if not FByLine.TryGetValue(Line, Matches) and (Line <> FSelectionLine) then
      Exit;
    Back := TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1);
    if Length(Matches) > 0 then
      PaintMatches(Rect, Context, Text, Matches, Back);
    if Line = FSelectionLine then
      PaintCount(Rect, Context, Text, Back);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.SelectionMatches, E);
  end;
end;

end.
