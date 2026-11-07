unit Atlas.IDE.Signature.FormatMarks;

// Farbige Platzhalter im Editor (#451): Solange der Parameter-Hint einer Formatroutine offen ist, bekommen jeder
// Platzhalter im Formatstring und sein Argument in der Liste [...] dieselbe Farbe (Palette Placeholders). Welche
// Stellen welche Farbe bekommen, rechnet TAtlasSignatureFormats.Marks aus; hier bleibt das Zeichnen.
// - Show übernimmt die Stellen mit dem Text, auf den sie sich beziehen; Clear nimmt sie weg (Hint zu).
// - PaintLine (plsEndPaint) überzieht die Stellen halb durchsichtig, aber nur in Zeilen, die im Editor noch dem
//   angefragten Stand entsprechen. Nach einer Änderung bleibt die Zeile ungefärbt, bis die neue Antwort da ist.
// - completion.formatPlaceholders aus: Der Editor ruft Show nicht auf.
// Gesichert über TAtlasFeature.Signature (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Style.Color,
  Atlas.Core.Signature.Format;

type
  TAtlasIdeFormatMarks = class
  private const
    /// <summary>Deckkraft der Farbe über dem Text (0–255).</summary>
    cMarkAlpha = 70;
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
    FFileName: string;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FByLine: TDictionary<Integer, TArray<TAtlasFormatMark>>;
    procedure PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
      const AMarks: TArray<TAtlasFormatMark>; ABack: TAtlasColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Färbt AMarks in AFileName; AText ist der Stand des Puffers, zu dem sie gehören.</summary>
    procedure Show(const AFileName, AText: string; ATabWidth: Integer; const AMarks: TArray<TAtlasFormatMark>);
    procedure Clear;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasIdeFormatMarks.TEvents }

function TAtlasIdeFormatMarks.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeFormatMarks.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeFormatMarks }

constructor TAtlasIdeFormatMarks.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FByLine := TDictionary<Integer, TArray<TAtlasFormatMark>>.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeFormatMarks.Destroy;
var
  mServices: INTACodeEditorServices;
  mPainted: Boolean;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  mPainted := FByLine.Count > 0;
  FByLine.Clear;
  FLines := nil;
  FreeAndNil(FByLine);
  if mPainted then
  begin
    Invalidate;
  end;
  inherited;
end;

class procedure TAtlasIdeFormatMarks.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure TAtlasIdeFormatMarks.Show(const AFileName, AText: string; ATabWidth: Integer;
  const AMarks: TArray<TAtlasFormatMark>);
var
  mMark: TAtlasFormatMark;
  mMarks: TArray<TAtlasFormatMark>;
  mPainted: Boolean;
begin
  mPainted := FByLine.Count > 0;
  FByLine.Clear;
  FFileName := AFileName;
  FTabWidth := ATabWidth;
  FLines := nil;
  if Length(AMarks) > 0 then
  begin
    FLines := TTextLines.SplitLines(AText);
  end;
  for mMark in AMarks do
  begin
    if not FByLine.TryGetValue(mMark.Line, mMarks) then
    begin
      mMarks := nil;
    end;
    FByLine.AddOrSetValue(mMark.Line, mMarks + [mMark]);
  end;
  if mPainted or (FByLine.Count > 0) then
  begin
    Invalidate;
  end;
end;

procedure TAtlasIdeFormatMarks.Clear;
begin
  FFileName := '';
  FLines := nil;
  if FByLine.Count = 0 then
  begin
    Exit;
  end;
  FByLine.Clear;
  Invalidate;
end;

procedure TAtlasIdeFormatMarks.PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AText: string; const AMarks: TArray<TAtlasFormatMark>; ABack: TAtlasColor);
var
  mMark: TAtlasFormatMark;
  mColors: TAtlasColors;
  mFirst, mLast, mCode: TRect;
  mDC: HDC;
  mSaved: Integer;
begin
  mColors := TAtlasColors.ForBackground(ABack);
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mMark in AMarks do
    begin
      mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mMark.Start, FTabWidth),
        AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mMark.Stop, FTabWidth),
        AContext.EditorLineNum);
      TAtlasIdeStyle.Blend(mDC, TRect.Create(mFirst.Left, ARect.Top, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom),
        COLORREF(ColorToRGB(TColor(mColors.Placeholders[mMark.Slot]))), cMarkAlpha);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasIdeFormatMarks.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLineState: INTACodeEditorLineState;
  mMarks: TArray<TAtlasFormatMark>;
  mLine: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FByLine.Count = 0) or
    TAtlasGuard.Disabled(TAtlasFeature.Signature) then
  begin
    Exit;
  end;
  try
    if not SameText(Context.FileName, FFileName) then
    begin
      Exit;
    end;
    mLine := Context.LogicalLineNum - 1;
    if (mLine < 0) or (mLine >= Length(FLines)) or not FByLine.TryGetValue(mLine, mMarks) then
    begin
      Exit;
    end;
    mLineState := Context.LineState;
    // Nur, wenn die Zeile im Editor dem angefragten Stand entspricht.
    if (mLineState = nil) or (TrimRight(mLineState.Text) <> TrimRight(FLines[mLine])) then
    begin
      Exit;
    end;
    PaintMarks(Rect, Context, FLines[mLine], mMarks, TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2,
      Rect.Top + 1));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Signature, E);
  end;
end;

end.
