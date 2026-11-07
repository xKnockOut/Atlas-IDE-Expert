unit Atlas.IDE.Completion.Preview;

// Vorschau des gewählten Eintrags im Editor (#434): Der noch fehlende Teil
// steht kursiv und gedämpft hinter dem Cursor. Ebenso der Vorschlag von
// „Muster fortsetzen“ (#671, Element PatternPreview, nur in der Cursorzeile). Nur gezeichnet über die
// Zeichenereignisse der Code-Editor-API (ToolsAPI.Editor, PaintLine nach dem
// Zeichnen der Zeile); Datei und Undo-Liste bleiben unberührt. Beim Wechsel
// des Texts wird nur die betroffene Zeile neu gezeichnet. Die gezeichnete
// Vorschau meldet sich bei TAtlasIdeElements (#628, nur „überall
// ausblenden“: Einstellung Preview).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.Elements;

type
  TAtlasEditorPreview = class
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
    FElement: TAtlasDrawnElement;
    FFollowCursor: Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Gehört die Vorschau in die Zeile, die AContext zeichnet?</summary>
    function ShowsIn(const AContext: INTACodeEditorPaintContext): Boolean;
    procedure InvalidateLine(ALine: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AText hinter der Editorspalte AColumn (1-basiert) in Zeile ALine von AFileName zeigen.</summary>
    procedure Show(const AFileName: string; ALine, AColumn: Integer; const AText: string);
    procedure Clear;
    /// <summary>Unter diesem Element meldet sich die gezeichnete Vorschau; Vorgabe CompletionPreview.</summary>
    property Element: TAtlasDrawnElement read FElement write FElement;
    /// <summary>Nur zeichnen, solange der Cursor der Ansicht in der Zeile steht.</summary>
    property FollowCursor: Boolean read FFollowCursor write FFollowCursor;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasEditorPreview.TEvents }

function TAtlasEditorPreview.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasEditorPreview.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorPreview }

constructor TAtlasEditorPreview.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FElement := TAtlasDrawnElement.CompletionPreview;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasEditorPreview.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  Clear;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasEditorPreview.InvalidateLine(ALine: Integer);
var
  mServices: INTACodeEditorServices;
begin
  if (ALine > 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTopLine(mServices, ALine);
  end;
end;

procedure TAtlasEditorPreview.Show(const AFileName: string; ALine, AColumn: Integer; const AText: string);
begin
  if (AText = FText) and (ALine = FLine) and (AColumn = FColumn) and SameText(AFileName, FFileName) then
  begin
    Exit;
  end;
  if FLine <> ALine then
  begin
    InvalidateLine(FLine);
  end;
  FFileName := AFileName;
  FLine := ALine;
  FColumn := AColumn;
  FText := AText;
  InvalidateLine(FLine);
end;

procedure TAtlasEditorPreview.Clear;
begin
  if FText = '' then
  begin
    Exit;
  end;
  FText := '';
  InvalidateLine(FLine);
  FLine := 0;
end;

function TAtlasEditorPreview.ShowsIn(const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := (FText <> '') and (AContext <> nil) and (AContext.LogicalLineNum = FLine) and
    SameText(AContext.FileName, FFileName);
  // Nur in der Cursorzeile (FollowCursor): Der Cursor der Ansicht muss in der Zeile stehen.
  if Result and FFollowCursor then
  begin
    Result := (AContext.EditView <> nil) and (AContext.EditView.CursorPos.Line = FLine);
  end;
end;

procedure TAtlasEditorPreview.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mCell: TRect;
  mCanvas: TCanvas;
  mItalic: TFont;
  mDC: HDC;
  mSaved, mTop, mTopRow: Integer;
  mSize: TSize;
begin
  try
    if BeforeEvent or (Stage <> plsEndPaint) or not ShowsIn(Context) then
    begin
      Exit;
    end;
    mCell := Context.EditorState.GetCharacterPosPx(FColumn, Context.EditorLineNum);
    mCanvas := Context.Canvas;
    mTop := Rect.Top + (Rect.Height - mCanvas.TextHeight('Wg')) div 2;
    // Eigene kursive Schrift und gesicherter DC-Zustand: Schrift, Textfarbe und
    // Hintergrundmodus der IDE bleiben unverändert (sonst färbt die Vorschaufarbe
    // später gezeichnete Läufe ein).
    mItalic := TFont.Create;
    try
      mItalic.Assign(mCanvas.Font);
      mItalic.Style := [fsItalic];
      mDC := mCanvas.Handle;
      mSaved := SaveDC(mDC);
      try
        SelectObject(mDC, mItalic.Handle);
        SetBkMode(mDC, TRANSPARENT);
        SetTextColor(mDC, ColorToRGB(TColor(TAtlasIdeStyle.Colors.Muted)));
        Winapi.Windows.TextOut(mDC, mCell.Left, mTop, PChar(FText), Length(FText));
        GetTextExtentPoint32W(mDC, PChar(FText), Length(FText), mSize);
      finally
        RestoreDC(mDC, mSaved);
      end;
      mTopRow := 0;
      if Context.EditView <> nil then
      begin
        mTopRow := Context.EditView.TopRow;
      end;
      TAtlasIdeElements.Painted(TAtlasIdeElements.Target(FElement, Context.FileName, FLine - 1, ''),
        TRect.Create(mCell.Left, Rect.Top, mCell.Left + mSize.cx, Rect.Bottom), mTopRow, Rect.Height);
    finally
      mItalic.Free;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FText := '';
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

end.
