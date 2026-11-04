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
    /// <summary>Stand der Treffer: Datei, Suchtext, Optionen, Pufferstand, Markierung (Zeile und Zeichen ab 0,
    /// Ende ausschließlich) und gesuchter Bereich (bei großen Dateien nur der sichtbare).</summary>
    TState = record
      FileName: string;
      Term: string;
      OptionsKey: string;
      Version: Cardinal;
      SelectionLine: Integer;
      SelectionStart: Integer;
      SelectionStop: Integer;
      FirstLine: Integer;
      LastLine: Integer;
      function Same(const AOther: TState): Boolean;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FFont: TFont;
    FFontKey: string;
    FState: TState;
    FVisibleOnly: Boolean;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FMatches: TAtlasSelectionMatchList;
    FByLine: TDictionary<Integer, TArray<TAtlasSelectionMatch>>;
    procedure TimerTick(Sender: TObject);
    procedure Update;
    procedure Locate(const AView: IOTAEditView; var AState: TState);
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
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.PaintedLine;

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
  FState.SelectionLine := -1;
  FByLine := TDictionary<Integer, TArray<TAtlasSelectionMatch>>.Create;
  FFont := TFont.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
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
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  Painted := FState.Term <> '';
  Clear;
  FreeAndNil(FByLine);
  FreeAndNil(FFont);
  if Painted then
  begin
    Invalidate;
  end;
  inherited;
end;

class procedure TAtlasIdeSelectionMatches.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

procedure TAtlasIdeSelectionMatches.Clear;
begin
  FState := Default(TState);
  FState.SelectionLine := -1;
  FLines := nil;
  FMatches := Default(TAtlasSelectionMatchList);
  if FByLine <> nil then
  begin
    FByLine.Clear;
  end;
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
    begin
      Matches := nil;
    end;
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

function TAtlasIdeSelectionMatches.TState.Same(const AOther: TState): Boolean;
begin
  Result := (Term = AOther.Term) and (OptionsKey = AOther.OptionsKey) and (Version = AOther.Version) and
    SameText(FileName, AOther.FileName);
  Result := Result and (SelectionLine = AOther.SelectionLine) and (SelectionStart = AOther.SelectionStart) and
    (SelectionStop = AOther.SelectionStop);
  Result := Result and (FirstLine = AOther.FirstLine) and (LastLine = AOther.LastLine);
end;

/// <summary>Suchtext aus der einzeiligen Markierung im oberen Editor; False ohne (auch, wenn die Funktion aus ist).
/// </summary>
function SelectedTerm(out AView: IOTAEditView; out AOptions: TAtlasSelectionMatchOptions; out ATerm: string): Boolean;
var
  mNavigateF3: Boolean;
  mBlock: IOTAEditBlock;
begin
  ATerm := '';
  AView := nil;
  if TAtlasIdeSettings.SelectionMatchesOn(AOptions, mNavigateF3) and
    not TAtlasGuard.Disabled(TAtlasFeature.SelectionMatches) then
  begin
    AView := TAtlasEditorBuffer.ActiveView;
  end;
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    mBlock := AView.Block;
    if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) and (mBlock.StartingRow = mBlock.EndingRow) then
    begin
      TAtlasSelectionMatches.Term(mBlock.Text, AOptions, ATerm);
    end;
  end;
  Result := ATerm <> '';
end;

/// <summary>Markierung von AView und gesuchter Bereich in FLines.</summary>
procedure TAtlasIdeSelectionMatches.Locate(const AView: IOTAEditView; var AState: TState);
var
  mBlock: IOTAEditBlock;
  mLineText: string;
begin
  mBlock := AView.Block;
  AState.SelectionLine := mBlock.StartingRow - 1;
  mLineText := '';
  if (AState.SelectionLine >= 0) and (AState.SelectionLine < Length(FLines)) then
  begin
    mLineText := FLines[AState.SelectionLine];
  end;
  AState.SelectionStart := TLspSession.ColumnToIndex(mLineText, mBlock.StartingColumn, FTabWidth);
  AState.SelectionStop := TLspSession.ColumnToIndex(mLineText, mBlock.EndingColumn, FTabWidth);
  AState.FirstLine := 0;
  AState.LastLine := High(FLines);
  // Sehr große Dateien: nur der sichtbare Bereich.
  if Length(FLines) > TAtlasSelectionMatches.LargeFileLines then
  begin
    AState.FirstLine := AView.TopRow - 1;
    AState.LastLine := AView.BottomRow - 1;
  end;
end;

procedure TAtlasIdeSelectionMatches.Update;
var
  mOptions: TAtlasSelectionMatchOptions;
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
  mWanted: TState;
begin
  mWanted := Default(TState);
  if not SelectedTerm(mView, mOptions, mWanted.Term) then
  begin
    if FState.Term <> '' then
    begin
      Clear;
      Invalidate;
    end;
    Exit;
  end;
  mSnapshot := TAtlasEditorSnapshots.Get(mView);
  if (mSnapshot.Version <> FState.Version) or not SameText(mSnapshot.FileName, FState.FileName) then
  begin
    FLines := TTextLines.SplitLines(mSnapshot.Text);
    FTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  end;
  mWanted.FileName := mSnapshot.FileName;
  mWanted.OptionsKey := OptionsKey(mOptions);
  mWanted.Version := mSnapshot.Version;
  Locate(mView, mWanted);
  if mWanted.Same(FState) then
  begin
    Exit;
  end;
  FState := mWanted;
  FVisibleOnly := Length(FLines) > TAtlasSelectionMatches.LargeFileLines;
  FMatches := TAtlasSelectionMatches.Find(FLines, mWanted.Term, mOptions, mWanted.FirstLine, mWanted.LastLine);
  BuildIndex;
  Invalidate;
end;

procedure TAtlasIdeSelectionMatches.EnsureFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
  begin
    Exit;
  end;
  FFont.Assign(AEditorFont);
  FFont.Style := [];
  FFontKey := Key;
end;

function TAtlasIdeSelectionMatches.CountText: string;
begin
  if FVisibleOnly then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SelectionMatchesVisible, [FMatches.Count]);
  end
  else if FMatches.Truncated then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SelectionMatchesMore, [FMatches.Count]);
  end
  else if FMatches.Count = 1 then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SelectionMatchesOne);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SelectionMatchesCount, [FMatches.Count]);
  end;
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
    begin
      IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
    end;
    for Match in AMatches do
    begin
      // Die Markierung selbst zeichnet die IDE.
      if TAtlasSelectionMatches.IsSelection(Match, FState.SelectionLine, FState.SelectionStart,
        FState.SelectionStop) then
      begin
        Continue;
      end;
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
  TAtlasIdeElements.Painted(TAtlasDrawnElement.SelectionMatches, Context.FileName, FState.SelectionLine, AText, Mark,
    Context.EditView.TopRow, Rect.Height);
end;

procedure TAtlasIdeSelectionMatches.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mMatches: TArray<TAtlasSelectionMatch>;
  mLine: Integer;
  mBack: TAtlasColor;
begin
  if (FState.Term = '') or TAtlasGuard.Disabled(TAtlasFeature.SelectionMatches) then
  begin
    Exit;
  end;
  try
    if not TAtlasPaintedLine.Resolve(Stage, BeforeEvent, Context, FState.FileName, FLines, mLine) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.SelectionMatches, Context.FileName) then
    begin
      Exit;
    end;
    if not FByLine.TryGetValue(mLine, mMatches) and (mLine <> FState.SelectionLine) then
    begin
      Exit;
    end;
    mBack := TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1);
    if Length(mMatches) > 0 then
    begin
      PaintMatches(Rect, Context, FLines[mLine], mMatches, mBack);
    end;
    if mLine = FState.SelectionLine then
    begin
      PaintCount(Rect, Context, FLines[mLine], mBack);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.SelectionMatches, E);
  end;
end;

end.
