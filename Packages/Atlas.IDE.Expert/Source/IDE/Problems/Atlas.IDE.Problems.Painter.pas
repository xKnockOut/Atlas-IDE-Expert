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
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasProblemsPainter.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
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
      FTypedAt := 1;
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
    Exit;
  FFont.Assign(AEditorFont);
  FFont.Style := [fsItalic];
  FFontKey := Key;
end;

class procedure TAtlasProblemsPainter.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
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
    Exit;
  Caption := TAtlasInlineDiagnostics.Caption(Found);
  // In .atlas ausgeblendet (#628): an dieser Codezeile oder in der Datei.
  if (Caption = '') or TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlineDiagnostics, Context.FileName, AText) then
    Exit;
  // Zwei Zeichen hinter dem letzten Zeichen, hinter Inlay-Hints und Beschriftungen derselben Zeile.
  Cell := Context.EditorState.GetCharacterPosPx(ColumnOf(AText, Length(TrimRight(AText)), ATabWidth) + 2,
    Context.EditorLineNum);
  Key := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
  X := TAtlasLineTail.Start(Self, Key, Cell.Left);
  DC := Context.Canvas.Handle;
  // Hintergrund des Editor-Farbschemas am rechten Rand (dort steht nichts), nicht das IDE-Thema.
  Sample := GetPixel(DC, Rect.Right - 2, Rect.Top + 1);
  if Sample = CLR_INVALID then
    Sample := COLORREF(ColorToRGB(Context.Canvas.Brush.Color));
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

procedure TAtlasProblemsPainter.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Problems: TArray<TAtlasProblem>;
  Problem: TAtlasProblem;
  LineState: INTACodeEditorLineState;
  Line, TabWidth, From, Till, Left, Right, X, Y, Cell: Integer;
  Text, Stored: string;
  Colors: TAtlasColors;
  Code, First, Last: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
  Up, Busy: Boolean;
  Target: TAtlasHideTarget;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Line := Context.LogicalLineNum - 1;
    Problems := FStore.OnLine(Context.FileName, Line);
    if Length(Problems) = 0 then
      Exit;
    // Erst hier, ohne Kopie des Einstellungsrecords: die meisten Zeilen haben keine Probleme (P-10).
    if not TAtlasIdeSettings.ProblemMarksOn then
      Exit;
    LineState := Context.LineState;
    if (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) or
      not FStore.LineText(Context.FileName, Line, Stored) then
      Exit;
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    Text := Stored;
    // Tipp-Pause in der Cursorzeile (#509): vor dem Vergleich, denn beim Tippen weicht der Text kurz ab.
    Busy := (Context.EditView.CursorPos.Line = Context.LogicalLineNum) and
      Typing(Context.FileName, Line, LineState.Text);
    // Nur, wenn die Zeile im Editor der im Speicher entspricht.
    if TrimRight(TAtlasPairs.DisplayLine(LineState.Text, TabWidth)) <>
      TrimRight(TAtlasPairs.DisplayLine(Text, TabWidth)) then
      Exit;
    // In .atlas ausgeblendet (#628): diese Codezeile oder die ganze Datei.
    if TAtlasIdeElements.Hidden(TAtlasDrawnElement.Problems, Context.FileName, Text) then
      Exit;
    Colors := TAtlasIdeStyle.Colors;
    Code := LineState.CodeRect;
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      for Problem in Problems do
      begin
        if Line = Problem.StartLine then
          From := Problem.StartCharacter
        else
          From := 0;
        if Line = Problem.EndLine then
          Till := Problem.EndCharacter
        else
          Till := Length(Text);
        From := EnsureRange(From, 0, Length(Text));
        Till := EnsureRange(Till, 0, Length(Text));
        // Leerer Bereich: ein Zeichen, am Zeilenende das letzte.
        if Till <= From then
        begin
          if From >= Length(Text) then
            From := Max(0, Length(Text) - 1);
          Till := From + 1;
        end;
        First := Context.EditorState.GetCharacterPosPx(ColumnOf(Text, From, TabWidth), Context.EditorLineNum);
        Last := Context.EditorState.GetCharacterPosPx(ColumnOf(Text, Till, TabWidth), Context.EditorLineNum);
        Cell := Max(4, First.Width);
        Left := First.Left;
        Right := Max(Last.Left, Left + Cell);
        Y := Rect.Bottom - 2;
        Pen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(ProblemColor(Colors, Problem))));
        Old := SelectObject(DC, Pen);
        try
          if Problem.Deprecated then
          begin
            // Veraltetes Symbol (#38): durchgestrichen.
            MoveToEx(DC, Left, Rect.Top + Rect.Height div 2, nil);
            LineTo(DC, Right, Rect.Top + Rect.Height div 2);
          end
          else if Problem.Severity = TAtlasProblemSeverity.Hint then
          begin
            // Hinweis: gepunktet.
            X := Left;
            while X < Right do
            begin
              MoveToEx(DC, X, Y, nil);
              LineTo(DC, X + 2, Y);
              Inc(X, 4);
            end;
          end
          else
          begin
            // Welle: je 2 Pixel auf und ab.
            X := Left;
            Up := False;
            MoveToEx(DC, X, Y, nil);
            while X < Right do
            begin
              Inc(X, 2);
              Up := not Up;
              if Up then
                LineTo(DC, X, Y - 2)
              else
                LineTo(DC, X, Y);
            end;
          end;
        finally
          SelectObject(DC, Old);
          DeleteObject(Pen);
        end;
        // Befund mit Regel des Servers: Kommentar über der ersten Zeile; sonst Eintrag für diese Codezeile.
        if not Problem.IsCompiler and (Problem.Code <> '') then
          Target := TAtlasHideTarget.Finding(Context.FileName, Problem.StartLine, Problem.Code, Text)
        else
          Target := TAtlasHideTarget.Finding(Context.FileName, Line, '', Text);
        Target.Caption := Problem.Caption;
        TAtlasIdeElements.Painted(Target, TRect.Create(Left, Rect.Top, Right, Rect.Bottom), Context.EditView.TopRow,
          Rect.Height);
      end;
    finally
      RestoreDC(DC, Saved);
    end;
    if not Busy then
      PaintInline(Rect, Context, Problems, Text, TabWidth);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

end.
