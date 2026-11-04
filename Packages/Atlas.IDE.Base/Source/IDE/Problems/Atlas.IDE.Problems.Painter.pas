unit Atlas.IDE.Problems.Painter;

// Unterstreicht Probleme im Editor (#398): nach dem Zeichnen jeder Zeile
// (PaintLine, plsEndPaint) eine Wellenlinie unter dem Bereich jedes Problems,
// Farbe nach Schweregrad (Fehler, Warnung, Info), Hinweise gepunktet; blasse
// Probleme (Text seither geändert) in abgeschwächter Farbe. Gezeichnet wird
// nur, wenn die Zeile im Editor der Zeile im Speicher entspricht.
// Direkt im DC zwischen SaveDC und RestoreDC (siehe Klammerfarben, #514).
// Ausblenden am Element (#628): Befunde mit Regel bekommen einen
// Unterdrückungskommentar (dann meldet der Server sie nicht mehr), andere
// (Compiler) einen Eintrag in .atlas je Codezeile oder Datei; jede gezeichnete
// Unterstreichung meldet sich mit Regel bei TAtlasIdeElements.
// Fehlertext am Zeilenende (#509, editor.inlineDiagnostics): hinter dem
// letzten Zeichen der Text der schwersten Diagnose, die in der Zeile beginnt,
// gekürzt und mit „(+n)“ für weitere, in ihrer Farbe gedimmt zum Hintergrund
// des Editors. Den Platz hinter dem Zeilenende teilt er mit Inlay-Hints und
// Blockende-Beschriftungen (TAtlasLineTail). In der Cursorzeile erscheint der
// Text erst eine Sekunde nach dem letzten Tastendruck; ein Zeitgeber zeichnet
// danach neu.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store;

type
  TAtlasProblemsPainter = class
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
    FStore: TAtlasProblemStore;
    // Fehlertext am Zeilenende (#509).
    FFont: TFont;
    FFontKey: string;
    FTimer: TTimer;
    FCursorKey: string;
    FCursorText: string;
    FTypedAt: Cardinal;
    /// <summary>Merkt Tastendrücke in der Cursorzeile; True, solange die Pause nicht um ist.</summary>
    function Typing(const AFileName: string; ALine: Integer; const AText: string): Boolean;
    procedure TimerTick(Sender: TObject);
    procedure EnsureFont(const AEditorFont: TFont);
    procedure PaintInline(const Rect: TRect; const Context: INTACodeEditorPaintContext;
      const AProblems: TArray<TAtlasProblem>; const AText: string; ATabWidth: Integer);
    /// <summary>Text der Zeile aus dem Speicher, wenn er dem Editor entspricht und gezeichnet werden soll; ABusy
    /// während der Tipp-Pause in der Cursorzeile.</summary>
    function LineToPaint(const AContext: INTACodeEditorPaintContext; ALine: Integer; out AText: string;
      out ATabWidth: Integer; out ABusy: Boolean): Boolean;
    /// <summary>Wellen, Punkte und Durchstreichungen der Probleme AProblems.</summary>
    procedure PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
      const AProblems: TArray<TAtlasProblem>; const AText: string; ATabWidth: Integer);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
  public
    /// <summary>AStore gehört dem Aufrufer und lebt länger als der Zeichner.</summary>
    constructor Create(AStore: TAtlasProblemStore);
    destructor Destroy; override;
    /// <summary>Oberen Editor neu zeichnen lassen.</summary>
    class procedure Invalidate; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.Math,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Colors,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Problems.InlineHints,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasProblemsPainter.TEvents }

function TAtlasProblemsPainter.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasProblemsPainter.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasProblemsPainter }

constructor TAtlasProblemsPainter.Create(AStore: TAtlasProblemStore);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FStore := AStore;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FFont := TFont.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasInlineDiagnostics.PauseMs;
  FTimer.OnTimer := TimerTick;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasProblemsPainter.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FFont);
  inherited Destroy;
end;

procedure TAtlasProblemsPainter.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Invalidate;
end;

function TAtlasProblemsPainter.Typing(const AFileName: string; ALine: Integer; const AText: string): Boolean;
var
  Key: string;
begin
  Key := AFileName + '|' + IntToStr(ALine);
  // Zeile gewechselt: nur merken. Gleiche Zeile mit anderem Text: getippt.
  if Key <> FCursorKey then
  begin
    FCursorKey := Key;
    FCursorText := AText;
  end
  else if AText <> FCursorText then
  begin
    FCursorText := AText;
    FTypedAt := GetTickCount;
    if FTypedAt = 0 then
    begin
      FTypedAt := 1;
    end;
    // Nach der Pause einmal neu zeichnen.
    FTimer.Enabled := False;
    FTimer.Enabled := True;
  end;
  Result := not TAtlasInlineDiagnostics.PauseOver(FTypedAt, GetTickCount);
end;

procedure TAtlasProblemsPainter.EnsureFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
  begin
    Exit;
  end;
  FFont.Assign(AEditorFont);
  FFont.Style := [fsItalic];
  FFontKey := Key;
end;

class procedure TAtlasProblemsPainter.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

procedure TAtlasProblemsPainter.PaintInline(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AProblems: TArray<TAtlasProblem>; const AText: string; ATabWidth: Integer);
const
  // Deckkraft der Farbe über dem Hintergrund: gedimmt, aber lesbar.
  Strength = 0.7;
var
  Mode: TAtlasInlineDiagnosticsMode;
  Found: TAtlasInlineDiagnostic;
  Caption, Key: string;
  Cell: TRect;
  DC: HDC;
  Saved, X, Top: Integer;
  Sample: COLORREF;
  Front: TAtlasColor;
  Size: TSize;
begin
  Mode := TAtlasIdeSettings.InlineDiagnosticsMode;
  if (Mode = TAtlasInlineDiagnosticsMode.Off) or
    not TAtlasInlineDiagnostics.Pick(AProblems, Context.LogicalLineNum - 1, Mode, Found) then
  begin
    Exit;
  end;
  Caption := TAtlasInlineDiagnostics.Caption(Found);
  // In .atlas ausgeblendet (#628): an dieser Codezeile oder in der Datei.
  if (Caption = '') or TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlineDiagnostics, Context.FileName, AText) then
  begin
    Exit;
  end;
  // Zwei Zeichen hinter dem letzten Zeichen, hinter Inlay-Hints und Beschriftungen derselben Zeile.
  Cell := Context.EditorState.GetCharacterPosPx(ColumnOf(AText, Length(TrimRight(AText)), ATabWidth) + 2,
    Context.EditorLineNum);
  Key := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
  X := TAtlasLineTail.Start(Self, Key, Cell.Left);
  DC := Context.Canvas.Handle;
  // Hintergrund des Editor-Farbschemas am rechten Rand (dort steht nichts), nicht das IDE-Thema.
  Sample := GetPixel(DC, Rect.Right - 2, Rect.Top + 1);
  if Sample = CLR_INVALID then
  begin
    Sample := COLORREF(ColorToRGB(Context.Canvas.Brush.Color));
  end;
  Front := TAtlasColorMath.Mix(ProblemColor(TAtlasIdeStyle.Colors, Found.Problem), TAtlasColor(Sample), Strength);
  EnsureFont(Context.Canvas.Font);
  Saved := SaveDC(DC);
  try
    SelectObject(DC, FFont.Handle);
    SetTextColor(DC, COLORREF(ColorToRGB(TColor(Front))));
    SetBkMode(DC, TRANSPARENT);
    GetTextExtentPoint32W(DC, PChar(Caption), Length(Caption), Size);
    Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Size.cy) div 2);
    TextOutW(DC, X, Top, PChar(Caption), Length(Caption));
  finally
    RestoreDC(DC, Saved);
  end;
  TAtlasLineTail.Finish(Self, Key, X + Size.cx);
  TAtlasIdeElements.Painted(TAtlasDrawnElement.InlineDiagnostics, Context.FileName, Context.LogicalLineNum - 1, AText,
    TRect.Create(X, Top, X + Size.cx, Top + Size.cy), Context.EditView.TopRow, Rect.Height);
end;

/// <summary>Zeichenbereich [AFrom, ATill) des Problems in der Zeile ALine; leer wird ein Zeichen, am Zeilenende
/// das letzte.</summary>
procedure CharRange(const AProblem: TAtlasProblem; ALine: Integer; const AText: string; out AFrom, ATill: Integer);
begin
  AFrom := 0;
  ATill := Length(AText);
  if ALine = AProblem.StartLine then
  begin
    AFrom := AProblem.StartCharacter;
  end;
  if ALine = AProblem.EndLine then
  begin
    ATill := AProblem.EndCharacter;
  end;
  AFrom := EnsureRange(AFrom, 0, Length(AText));
  ATill := EnsureRange(ATill, 0, Length(AText));
  if ATill <= AFrom then
  begin
    if AFrom >= Length(AText) then
    begin
      AFrom := Max(0, Length(AText) - 1);
    end;
    ATill := AFrom + 1;
  end;
end;

/// <summary>Gepunktete Linie (Hinweis).</summary>
procedure DrawDots(ADC: HDC; ALeft, ARight, AY: Integer);
var
  mX: Integer;
begin
  mX := ALeft;
  while mX < ARight do
  begin
    MoveToEx(ADC, mX, AY, nil);
    LineTo(ADC, mX + 2, AY);
    Inc(mX, 4);
  end;
end;

/// <summary>Welle: je 2 Pixel auf und ab.</summary>
procedure DrawWave(ADC: HDC; ALeft, ARight, AY: Integer);
var
  mX: Integer;
  mUp: Boolean;
begin
  mX := ALeft;
  mUp := False;
  MoveToEx(ADC, mX, AY, nil);
  while mX < ARight do
  begin
    Inc(mX, 2);
    mUp := not mUp;
    if mUp then
    begin
      LineTo(ADC, mX, AY - 2);
    end
    else
    begin
      LineTo(ADC, mX, AY);
    end;
  end;
end;

/// <summary>Markierung des Problems zwischen ALeft und ARight in der Zeile ARect.</summary>
procedure DrawMark(ADC: HDC; AColor: TColor; const AProblem: TAtlasProblem; ALeft, ARight: Integer;
  const ARect: TRect);
var
  mPen, mOld: HGDIOBJ;
begin
  mPen := CreatePen(PS_SOLID, 1, ColorToRGB(AColor));
  mOld := SelectObject(ADC, mPen);
  try
    if AProblem.Deprecated then
    begin
      // Veraltetes Symbol (#38): durchgestrichen.
      MoveToEx(ADC, ALeft, ARect.Top + ARect.Height div 2, nil);
      LineTo(ADC, ARight, ARect.Top + ARect.Height div 2);
    end
    else if AProblem.Severity = TAtlasProblemSeverity.Hint then
    begin
      DrawDots(ADC, ALeft, ARight, ARect.Bottom - 2);
    end
    else
    begin
      DrawWave(ADC, ALeft, ARight, ARect.Bottom - 2);
    end;
  finally
    SelectObject(ADC, mOld);
    DeleteObject(mPen);
  end;
end;

/// <summary>Befund mit Regel des Servers: Kommentar über der ersten Zeile; sonst Eintrag für diese Codezeile.
/// </summary>
function HideTargetOf(const AFileName: string; const AProblem: TAtlasProblem; ALine: Integer;
  const AText: string): TAtlasHideTarget;
begin
  if not AProblem.IsCompiler and (AProblem.Code <> '') then
  begin
    Result := TAtlasHideTarget.Finding(AFileName, AProblem.StartLine, AProblem.Code, AText);
  end
  else
  begin
    Result := TAtlasHideTarget.Finding(AFileName, ALine, '', AText);
  end;
  Result.Caption := AProblem.Caption;
end;

function TAtlasProblemsPainter.LineToPaint(const AContext: INTACodeEditorPaintContext; ALine: Integer;
  out AText: string; out ATabWidth: Integer; out ABusy: Boolean): Boolean;
var
  mLineState: INTACodeEditorLineState;
begin
  AText := '';
  ATabWidth := 0;
  ABusy := False;
  mLineState := AContext.LineState;
  Result := (mLineState <> nil) and (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil) and
    FStore.LineText(AContext.FileName, ALine, AText);
  if not Result then
  begin
    Exit;
  end;
  ATabWidth := TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer);
  // Tipp-Pause in der Cursorzeile (#509): vor dem Vergleich, denn beim Tippen weicht der Text kurz ab.
  ABusy := (AContext.EditView.CursorPos.Line = AContext.LogicalLineNum) and
    Typing(AContext.FileName, ALine, mLineState.Text);
  // Nur, wenn die Zeile im Editor der im Speicher entspricht; nicht in .atlas ausgeblendet (#628).
  Result := (TrimRight(TAtlasPairs.DisplayLine(mLineState.Text, ATabWidth)) =
    TrimRight(TAtlasPairs.DisplayLine(AText, ATabWidth))) and
    not TAtlasIdeElements.Hidden(TAtlasDrawnElement.Problems, AContext.FileName, AText);
end;

procedure TAtlasProblemsPainter.PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AProblems: TArray<TAtlasProblem>; const AText: string; ATabWidth: Integer);
var
  mProblem: TAtlasProblem;
  mLine, mFrom, mTill, mLeft, mRight: Integer;
  mColors: TAtlasColors;
  mCode, mFirst, mLast: TRect;
  mDC: HDC;
  mSaved: Integer;
begin
  mLine := AContext.LogicalLineNum - 1;
  mColors := TAtlasIdeStyle.Colors;
  mCode := AContext.LineState.CodeRect;
  mDC := AContext.Canvas.Handle;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mProblem in AProblems do
    begin
      CharRange(mProblem, mLine, AText, mFrom, mTill);
      mFirst := AContext.EditorState.GetCharacterPosPx(ColumnOf(AText, mFrom, ATabWidth), AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(ColumnOf(AText, mTill, ATabWidth), AContext.EditorLineNum);
      mLeft := mFirst.Left;
      mRight := Max(mLast.Left, mLeft + Max(4, mFirst.Width));
      DrawMark(mDC, TColor(ProblemColor(mColors, mProblem)), mProblem, mLeft, mRight, ARect);
      TAtlasIdeElements.Painted(HideTargetOf(AContext.FileName, mProblem, mLine, AText),
        TRect.Create(mLeft, ARect.Top, mRight, ARect.Bottom), AContext.EditView.TopRow, ARect.Height);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasProblemsPainter.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mProblems: TArray<TAtlasProblem>;
  mLine, mTabWidth: Integer;
  mText: string;
  mBusy: Boolean;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  try
    mLine := Context.LogicalLineNum - 1;
    mProblems := FStore.OnLine(Context.FileName, mLine);
    // Einstellung erst hier, ohne Kopie des Einstellungsrecords: die meisten Zeilen haben keine Probleme (P-10).
    if (Length(mProblems) > 0) and TAtlasIdeSettings.ProblemMarksOn and
      LineToPaint(Context, mLine, mText, mTabWidth, mBusy) then
    begin
      PaintMarks(Rect, Context, mProblems, mText, mTabWidth);
      if not mBusy then
      begin
        PaintInline(Rect, Context, mProblems, mText, mTabWidth);
      end;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

end.
