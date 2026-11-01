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
    MarkAlpha = 70;
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
    procedure PaintMarks(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
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
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FByLine := TDictionary<Integer, TArray<TAtlasFormatMark>>.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeFormatMarks.Destroy;
var
  Services: INTACodeEditorServices;
  Painted: Boolean;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  Painted := FByLine.Count > 0;
  FByLine.Clear;
  FLines := nil;
  FreeAndNil(FByLine);
  if Painted then
    Invalidate;
  inherited;
end;

class procedure TAtlasIdeFormatMarks.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

procedure TAtlasIdeFormatMarks.Show(const AFileName, AText: string; ATabWidth: Integer;
  const AMarks: TArray<TAtlasFormatMark>);
var
  Mark: TAtlasFormatMark;
  Marks: TArray<TAtlasFormatMark>;
  Painted: Boolean;
begin
  Painted := FByLine.Count > 0;
  FByLine.Clear;
  FFileName := AFileName;
  FTabWidth := ATabWidth;
  FLines := nil;
  if Length(AMarks) > 0 then
    FLines := TTextLines.SplitLines(AText);
  for Mark in AMarks do
  begin
    if not FByLine.TryGetValue(Mark.Line, Marks) then
      Marks := nil;
    FByLine.AddOrSetValue(Mark.Line, Marks + [Mark]);
  end;
  if Painted or (FByLine.Count > 0) then
    Invalidate;
end;

procedure TAtlasIdeFormatMarks.Clear;
begin
  FFileName := '';
  FLines := nil;
  if FByLine.Count = 0 then
    Exit;
  FByLine.Clear;
  Invalidate;
end;

procedure TAtlasIdeFormatMarks.PaintMarks(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; const AMarks: TArray<TAtlasFormatMark>; ABack: TAtlasColor);
var
  Mark: TAtlasFormatMark;
  Colors: TAtlasColors;
  First, Last, Code: TRect;
  DC: HDC;
  Saved: Integer;
begin
  Colors := TAtlasColors.ForBackground(ABack);
  DC := Context.Canvas.Handle;
  Code := Context.LineState.CodeRect;
  Saved := SaveDC(DC);
  try
    if Code.Right > Code.Left then
      IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
    for Mark in AMarks do
    begin
      First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Mark.Start, FTabWidth),
        Context.EditorLineNum);
      Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, Mark.Stop, FTabWidth),
        Context.EditorLineNum);
      TAtlasIdeStyle.Blend(DC, TRect.Create(First.Left, Rect.Top, Max(Last.Left, First.Left + 1), Rect.Bottom),
        COLORREF(ColorToRGB(TColor(Colors.Placeholders[Mark.Slot]))), MarkAlpha);
    end;
  finally
    RestoreDC(DC, Saved);
  end;
end;

procedure TAtlasIdeFormatMarks.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Marks: TArray<TAtlasFormatMark>;
  Line: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FByLine.Count = 0) or
    TAtlasGuard.Disabled(TAtlasFeature.Signature) then
    Exit;
  try
    if not SameText(Context.FileName, FFileName) then
      Exit;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line >= Length(FLines)) or not FByLine.TryGetValue(Line, Marks) then
      Exit;
    LineState := Context.LineState;
    // Nur, wenn die Zeile im Editor dem angefragten Stand entspricht.
    if (LineState = nil) or (TrimRight(LineState.Text) <> TrimRight(FLines[Line])) then
      Exit;
    PaintMarks(Rect, Context, FLines[Line], Marks, TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2,
      Rect.Top + 1));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Signature, E);
  end;
end;

end.
