unit Argus.IDE.Completion.Preview;

// Vorschau des gewählten Eintrags im Editor (#434): Der noch fehlende Teil
// steht kursiv und gedämpft hinter dem Cursor. Nur gezeichnet über die
// Zeichenereignisse der Code-Editor-API (ToolsAPI.Editor, PaintLine nach dem
// Zeichnen der Zeile); Datei und Undo-Liste bleiben unberührt. Beim Wechsel
// des Texts wird nur die betroffene Zeile neu gezeichnet.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor;

type
  TArgusEditorPreview = class
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
    /// <summary>1-basiert wie in der IDE.</summary>
    FLine: Integer;
    FColumn: Integer;
    FText: string;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure InvalidateLine(ALine: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AText hinter der Editorspalte AColumn (1-basiert) in Zeile ALine von AFileName zeigen.</summary>
    procedure Show(const AFileName: string; ALine, AColumn: Integer; const AText: string);
    procedure Clear;
  end;

implementation

uses
  Argus.IDE.Editor.Style;

{ TArgusEditorPreview.TEvents }

function TArgusEditorPreview.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TArgusEditorPreview.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TArgusEditorPreview }

constructor TArgusEditorPreview.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TArgusEditorPreview.Destroy;
var
  Services: INTACodeEditorServices;
begin
  Clear;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TArgusEditorPreview.InvalidateLine(ALine: Integer);
var
  Services: INTACodeEditorServices;
begin
  if (ALine > 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditorLogicalLine(ALine);
end;

procedure TArgusEditorPreview.Show(const AFileName: string; ALine, AColumn: Integer; const AText: string);
begin
  if (AText = FText) and (ALine = FLine) and (AColumn = FColumn) and SameText(AFileName, FFileName) then
    Exit;
  if FLine <> ALine then
    InvalidateLine(FLine);
  FFileName := AFileName;
  FLine := ALine;
  FColumn := AColumn;
  FText := AText;
  InvalidateLine(FLine);
end;

procedure TArgusEditorPreview.Clear;
begin
  if FText = '' then
    Exit;
  FText := '';
  InvalidateLine(FLine);
  FLine := 0;
end;

procedure TArgusEditorPreview.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Cell: TRect;
  Canvas: TCanvas;
  Style: TFontStyles;
  Color: TColor;
begin
  try
    if BeforeEvent or (Stage <> plsEndPaint) or (FText = '') or (Context = nil) or
      (Context.LogicalLineNum <> FLine) or not SameText(Context.FileName, FFileName) then
      Exit;
    Cell := Context.EditorState.GetCharacterPosPx(FColumn, Context.EditorLineNum);
    Canvas := Context.Canvas;
    Style := Canvas.Font.Style;
    Color := Canvas.Font.Color;
    try
      Canvas.Font.Style := [fsItalic];
      Canvas.Font.Color := TColor(TArgusIdeStyle.Colors.Muted);
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(Cell.Left, Rect.Top + (Rect.Height - Canvas.TextHeight('Wg')) div 2, FText);
    finally
      Canvas.Font.Style := Style;
      Canvas.Font.Color := Color;
      Canvas.Brush.Style := bsSolid;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on Exception do
      FText := '';
  end;
end;

end.
