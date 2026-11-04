unit Atlas.IDE.Debug.AccessViolationUnderline;

// Unterstreichung des schuldigen Glieds einer Zugriffsverletzung (#865) im Editor:
//   - Show merkt Datei, Zeile, Spalten und den abgeglichenen Text der Zeile; gezeichnet wird nur, wenn die Zeile
//     im Editor noch diesem Text entspricht.
//   - Fehlerfarbe zum Hintergrund, doppelt so dick wie eine Wellenlinie der Diagnosen.
//   - Der Notifier der Editorereignisse ist vom Erzeugen bis zur Freigabe angemeldet (#493).
// Nur im Hauptthread verwenden.

interface

uses
  System.Types,
  ToolsAPI.Editor;

type
  TAtlasIdeAvUnderline = class
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
    FActive: Boolean;
    FFileName: string;
    FLine: Integer;
    FStart: Integer;
    FEnd: Integer;
    FStored: string;
    /// <summary>Linke Kanten der ersten und der letzten Spalte; False, wenn die Zeile nicht passt.</summary>
    function Span(const AContext: INTACodeEditorPaintContext; out AFirst, ALast: Integer): Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>In AFileName Zeile ALine (0-basiert, Text AStored) von Zeichen AStart bis AEnd unterstreichen.
    /// </summary>
    procedure Show(const AFileName: string; ALine, AStart, AEnd: Integer; const AStored: string);
    /// <summary>Unterstreichung entfernen; False, wenn keine stand.</summary>
    function Clear: Boolean;
    /// <summary>Den obersten Editor neu zeichnen.</summary>
    class procedure Invalidate; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Winapi.Windows,
  Vcl.Graphics,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

/// <summary>Strich von AFirst bis ALast am unteren Rand von ARect in Fehlerfarbe zum Hintergrund.</summary>
procedure DrawUnderline(const AContext: INTACodeEditorPaintContext; const ARect: TRect; AFirst, ALast: Integer);
var
  mDC: HDC;
  mSample: COLORREF;
  mThickness, mY, mSaved: Integer;
  mPen: HPEN;
begin
  mDC := AContext.Canvas.Handle;
  mSample := GetPixel(mDC, AFirst, ARect.Top + 1);
  if mSample = CLR_INVALID then
  begin
    mSample := COLORREF(ColorToRGB(AContext.Canvas.Brush.Color));
  end;
  // Fehlerfarbe zum Hintergrund, doppelt so dick wie eine Wellenlinie der Diagnosen.
  mThickness := Max(2, (ARect.Bottom - ARect.Top) div 8);
  mY := ARect.Bottom - mThickness;
  // Reines GDI zwischen SaveDC und RestoreDC; der Stift erst nach RestoreDC löschen (dann nicht mehr gewählt).
  mPen := CreatePen(PS_SOLID, mThickness,
    COLORREF(ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(mSample)).Error))));
  mSaved := SaveDC(mDC);
  try
    SelectObject(mDC, mPen);
    MoveToEx(mDC, AFirst, mY, nil);
    LineTo(mDC, ALast, mY);
  finally
    RestoreDC(mDC, mSaved);
    DeleteObject(mPen);
  end;
end;

{ TAtlasIdeAvUnderline.TEvents }

function TAtlasIdeAvUnderline.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeAvUnderline.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeAvUnderline }

constructor TAtlasIdeAvUnderline.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeAvUnderline.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
  end;
  FEventsRef := nil;
  FStored := '';
  FFileName := '';
  inherited Destroy;
end;

class procedure TAtlasIdeAvUnderline.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure TAtlasIdeAvUnderline.Show(const AFileName: string; ALine, AStart, AEnd: Integer; const AStored: string);
begin
  FFileName := AFileName;
  FLine := ALine;
  FStart := AStart;
  FEnd := AEnd;
  FStored := AStored;
  FActive := True;
  Invalidate;
end;

function TAtlasIdeAvUnderline.Clear: Boolean;
begin
  Result := FActive;
  FActive := False;
  FStored := '';
end;

function TAtlasIdeAvUnderline.Span(const AContext: INTACodeEditorPaintContext; out AFirst, ALast: Integer): Boolean;
var
  mLineState: INTACodeEditorLineState;
  mTabWidth: Integer;
begin
  AFirst := 0;
  ALast := 0;
  mLineState := AContext.LineState;
  Result := (AContext.LogicalLineNum - 1 = FLine) and SameText(AContext.FileName, FFileName) and
    (mLineState <> nil) and (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil);
  if not Result then
  begin
    Exit;
  end;
  mTabWidth := TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer);
  // Nur, wenn die Zeile im Editor der abgeglichenen entspricht.
  Result := TrimRight(TAtlasPairs.DisplayLine(mLineState.Text, mTabWidth)) =
    TrimRight(TAtlasPairs.DisplayLine(FStored, mTabWidth));
  if Result then
  begin
    AFirst := AContext.EditorState.GetCharacterPosPx(ColumnOf(FStored, FStart, mTabWidth),
      AContext.EditorLineNum).Left;
    ALast := AContext.EditorState.GetCharacterPosPx(ColumnOf(FStored, FEnd, mTabWidth),
      AContext.EditorLineNum).Left;
    Result := ALast > AFirst;
  end;
end;

procedure TAtlasIdeAvUnderline.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mFirst, mLast: Integer;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or
    not FActive then
  begin
    Exit;
  end;
  try
    if Span(Context, mFirst, mLast) then
    begin
      DrawUnderline(Context, Rect, mFirst, mLast);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

end.
