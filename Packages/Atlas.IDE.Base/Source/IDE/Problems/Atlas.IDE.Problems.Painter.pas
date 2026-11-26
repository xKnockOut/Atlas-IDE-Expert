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
// des Editors; ein Testfehlschlag an der Assert-Zeile kurz und grau (#1771).
// Den Platz hinter dem Zeilenende teilt er mit Inlay-Hints und
// Blockende-Beschriftungen (TAtlasLineTail). In der Cursorzeile erscheint der
// Text erst eine Sekunde nach dem letzten Tastendruck; ein Zeitgeber zeichnet
// danach neu.
// Marken folgen ihrer Zeile sofort (#1818, editor.trackLines): Die Zeilen der
// Befunde verfolgt die IDE (TAtlasIdeLineTracker, Kanal Befunde); gezeichnet
// wird in Editorzeile X, was zur Quellzeile gehört, die jetzt dort steht. Eine
// gelöschte Zeile trägt keine Marke mehr. Der nächste Stand des Speichers
// (Tipp-Pause, Serverantwort) meldet die Zeilen neu an, vorsorglich nicht beim
// Zeichnen (eine von drei Vorkehrungen, siehe Atlas.IDE.Foundation.LineTracker):
// Das Anmelden ändert die Zeilentabelle des Editors, und das Zeichnen kommt
// auch mitten aus anderen Vorgängen (WM_PRINTCLIENT beim Hover). Der Zeichner
// merkt sich die Dateien (auch aus weiteren Editorfenstern) und meldet über
// einen eigenen Zeitgeber danach je Datei an; bis dahin gilt jede Zeile als sie
// selbst. Scheitert das Anmelden, bleibt der Stand ohne Verfolgung, bis der
// nächste kommt: Derselbe Fehler wiederholt sich nicht bei jedem Zeichnen.
// Beim Debuggen ausgeblendet (#2962, problems.hideWhileDebugging): Hidden setzt
// der Controller, solange ein Programm im Debugger läuft; dann zeichnet der
// Zeichner nichts, damit Debug-Werte am Zeilenende und unter den Bezeichnern
// frei bleiben.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Plugin.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.LineTracking,
  Atlas.Vcl.Theme.EditorFont;

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
    FFont: TAtlasEditorFont;
    FTimer: TTimer;
    FCursorKey: string;
    FCursorText: string;
    FTypedAt: UInt64;
    // Zeilenverfolgung nach dem Zeichnen anmelden (#1818).
    FFollowTimer: TTimer;
    FFollowFiles: TStringList;
    // Beim Debuggen ausgeblendet (#2962).
    FHidden: Boolean;
    /// <summary>Merkt Tastendrücke in der Cursorzeile; True, solange die Pause nicht um ist.</summary>
    function Typing(const AFileName: string; ALine: Integer; const AText: string): Boolean;
    procedure TimerTick(Sender: TObject);
    /// <summary>Zeilen jeder vorgemerkten Datei verfolgen, die noch offen ist.</summary>
    procedure FollowTick(Sender: TObject);
    /// <summary>Zeilen der Befunde in AFileName verfolgen; nach einem Fehler bis zum nächsten Stand ohne.</summary>
    procedure FollowFile(const AFileName: string);
    procedure PaintInline(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
      const AProblems: TArray<TAtlasProblem>; ALine: Integer; const AText: string; ATabWidth: Integer);
    /// <summary>Text der Zeile aus dem Speicher, wenn er dem Editor entspricht und gezeichnet werden soll; ABusy
    /// während der Tipp-Pause in der Cursorzeile.</summary>
    function LineToPaint(const AContext: INTACodeEditorPaintContext; ALine: Integer; out AText: string;
      out ATabWidth: Integer; out ABusy: Boolean): Boolean;
    /// <summary>Wellen, Punkte und Durchstreichungen der Probleme AProblems.</summary>
    procedure PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
      const AProblems: TArray<TAtlasProblem>; ALine: Integer; const AText: string; ATabWidth: Integer);
    /// <summary>Zuordnung der verfolgten Befundzeilen im Puffer von AContext (#1818); nil ohne Verfolgung oder
    /// solange der Stand noch nicht angemeldet ist (dann merkt sie die Datei für FollowTick vor).</summary>
    function Tracked(const AContext: INTACodeEditorPaintContext): TAtlasTrackedLines;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
  public
    /// <summary>AStore gehört dem Aufrufer und lebt länger als der Zeichner.</summary>
    constructor Create(AStore: TAtlasProblemStore);
    destructor Destroy; override;
    /// <summary>Oberen Editor neu zeichnen lassen.</summary>
    class procedure Invalidate; static;
    /// <summary>Nichts zeichnen (#2962, beim Debuggen); der Aufrufer lässt danach neu zeichnen.</summary>
    property Hidden: Boolean read FHidden write FHidden;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorCover,
  Winapi.Windows,
  System.Math,
  Atlas.Plugin.Style.Color,
  Atlas.Plugin.Style.Palette,
  Atlas.Core.Problems.Colors,
  Atlas.Text.Columns,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.ToolsApi.Theme.Style,
  Atlas.IDE.Foundation.EditorSettings,
  Atlas.IDE.Foundation.Elements,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Problems.Marks,
  Atlas.Core.Editor.Hide,
  Atlas.ToolsApi.Editor.Refresh,
  Atlas.IDE.Foundation.LineTracker;

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
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FStore := AStore;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FFont := TAtlasEditorFont.Create([fsItalic]);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasInlineDiagnostics.cPauseMs;
  FTimer.OnTimer := TimerTick;
  FFollowTimer := TTimer.Create(nil);
  FFollowTimer.Enabled := False;
  FFollowTimer.Interval := 1;
  FFollowTimer.OnTimer := FollowTick;
  FFollowFiles := TStringList.Create;
  FFollowFiles.CaseSensitive := False;
  FFollowFiles.Sorted := True;
  FFollowFiles.Duplicates := dupIgnore;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasProblemsPainter.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FFollowTimer);
  FreeAndNil(FFollowFiles);
  FreeAndNil(FFont);
  inherited Destroy;
end;

function TAtlasProblemsPainter.Typing(const AFileName: string; ALine: Integer; const AText: string): Boolean;
var
  mKey: string;
begin
  mKey := AFileName + '|' + IntToStr(ALine);
  // Zeile gewechselt: nur merken. Gleiche Zeile mit anderem Text: getippt.
  if mKey <> FCursorKey then
  begin
    FCursorKey := mKey;
    FCursorText := AText;
  end
  else if AText <> FCursorText then
  begin
    FCursorText := AText;
    FTypedAt := TAtlasInlineDiagnostics.TypedStamp;
    // Nach der Pause einmal neu zeichnen.
    FTimer.Enabled := False;
    FTimer.Enabled := True;
  end;
  Result := TAtlasInlineDiagnostics.StillTyping(FTypedAt);
end;

procedure TAtlasProblemsPainter.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Invalidate;
end;

procedure TAtlasProblemsPainter.FollowTick(Sender: TObject);
var
  mFiles: TArray<string>;
  mFileName: string;
begin
  FFollowTimer.Enabled := False;
  mFiles := FFollowFiles.ToStringArray;
  FFollowFiles.Clear;
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
  begin
    Exit;
  end;
  for mFileName in mFiles do
  begin
    FollowFile(mFileName);
  end;
end;

procedure TAtlasProblemsPainter.FollowFile(const AFileName: string);
var
  mStore: TAtlasProblemStore;
begin
  mStore := FStore;
  try
    // Auch in einem weiteren Editorfenster; ist die Datei inzwischen geschlossen, geschieht nichts.
    TAtlasIdeLineTracker.FollowFile(AFileName, TAtlasLineTracking.cProblems, mStore.Stamp(AFileName),
      function: TArray<Integer>
      begin
        Result := TAtlasProblemMarks.Lines(mStore.ForFile(AFileName));
      end,
      function: string
      begin
        Result := mStore.TextOf(AFileName);
      end);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
      // Bis zum nächsten Stand ohne Verfolgung (jede Zeile ist sie selbst): Sonst stellte jedes Zeichnen den
      // Zeitgeber neu, und derselbe Fehler schaltete nach drei Versuchen alle Befund-Marken ab.
      TAtlasIdeLineTracker.GiveUp(AFileName, TAtlasLineTracking.cProblems, mStore.Stamp(AFileName));
    end;
  end;
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
  Result := (TrimRight(TTextColumns.DisplayLine(mLineState.Text, ATabWidth)) =
    TrimRight(TTextColumns.DisplayLine(AText, ATabWidth))) and
    not TAtlasIdeElements.Hidden(TAtlasDrawnElement.Problems, AContext.FileName, AText);
end;

procedure TAtlasProblemsPainter.PaintInline(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AProblems: TArray<TAtlasProblem>; ALine: Integer; const AText: string; ATabWidth: Integer);
const
  // Deckkraft der Farbe über dem Hintergrund: gedimmt, aber lesbar.
  cStrength = 0.7;
var
  mMode: TAtlasInlineDiagnosticsMode;
  mFound: TAtlasInlineDiagnostic;
  mCaption, mKey: string;
  mCell: TRect;
  mDC: HDC;
  mSaved, X, mTop: Integer;
  mSample: COLORREF;
  mFront: TAtlasColor;
  mSize: TSize;
begin
  mMode := TAtlasIdeEditorSettings.InlineDiagnosticsMode;
  if (mMode = TAtlasInlineDiagnosticsMode.Off) or
    not TAtlasInlineDiagnostics.Pick(AProblems, ALine, mMode, mFound) then
  begin
    Exit;
  end;
  mCaption := TAtlasInlineDiagnostics.Caption(mFound);
  // In .atlas ausgeblendet (#628): an dieser Codezeile oder in der Datei.
  if (mCaption = '') or TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlineDiagnostics, AContext.FileName, AText) then
  begin
    Exit;
  end;
  // Zwei Zeichen hinter dem letzten Zeichen, hinter Inlay-Hints und Beschriftungen derselben Zeile.
  mCell := AContext.EditorState.GetCharacterPosPx(
    TAtlasProblemMarks.Column(AText, Length(TrimRight(AText)), ATabWidth) + 2,
    AContext.EditorLineNum);
  mKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  X := TAtlasLineTail.Start(Self, mKey, mCell.Left);
  mDC := AContext.Canvas.Handle;
  // Hintergrund des Editor-Farbschemas am rechten Rand (dort steht nichts), nicht das IDE-Thema.
  mSample := GetPixel(mDC, ARect.Right - 2, ARect.Top + 1);
  if mSample = CLR_INVALID then
  begin
    mSample := COLORREF(ColorToRGB(AContext.Canvas.Brush.Color));
  end;
  mFront := ProblemColor(TAtlasIdeStyle.Colors, mFound.Problem);
  if TAtlasInlineDiagnostics.IsShortTest(mFound.Problem) then
  begin
    // „erwartet 4, erhalten 3“ hinter der Assert-Zeile grau wie Inlay-Hinweise (#1771).
    mFront := TAtlasIdeStyle.Colors.Muted;
  end;
  mFront := TAtlasColorMath.Mix(mFront, TAtlasColor(mSample), cStrength);
  FFont.Follow(AContext.Canvas.Font);
  mSaved := SaveDC(mDC);
  try
    SelectObject(mDC, FFont.Font.Handle);
    SetTextColor(mDC, COLORREF(ColorToRGB(TColor(mFront))));
    SetBkMode(mDC, TRANSPARENT);
    GetTextExtentPoint32W(mDC, PChar(mCaption), Length(mCaption), mSize);
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mSize.cy) div 2);
    TextOutW(mDC, X, mTop, PChar(mCaption), Length(mCaption));
  finally
    RestoreDC(mDC, mSaved);
  end;
  TAtlasLineTail.Finish(Self, mKey, X + mSize.cx);
  TAtlasIdeElements.Painted(
    TAtlasIdeElements.Target(TAtlasDrawnElement.InlineDiagnostics, AContext.FileName, AContext.LogicalLineNum - 1,
    AText), TRect.Create(X, mTop, X + mSize.cx, mTop + mSize.cy), AContext.EditView.TopRow, ARect.Height);
end;

const
  /// <summary>Punkte der Hinweislinie: Länge und Abstand in Pixeln.</summary>
  cDotLength = 2;
  cDotStep = 4;
  /// <summary>Mindestbreite einer Markierung in Pixeln.</summary>
  cMinMarkWidth = 4;

/// <summary>Gepunktete Linie (Hinweis).</summary>
procedure DrawDots(ADC: HDC; ALeft, ARight, AY: Integer);
var
  mX: Integer;
begin
  mX := ALeft;
  while mX < ARight do
  begin
    MoveToEx(ADC, mX, AY, nil);
    LineTo(ADC, mX + cDotLength, AY);
    Inc(mX, cDotStep);
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

procedure TAtlasProblemsPainter.PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AProblems: TArray<TAtlasProblem>; ALine: Integer; const AText: string; ATabWidth: Integer);
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
      TAtlasProblemMarks.CharRange(mProblem, ALine, AText, mFrom, mTill);
      mFirst := AContext.EditorState.GetCharacterPosPx(TAtlasProblemMarks.Column(AText, mFrom, ATabWidth),
        AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(TAtlasProblemMarks.Column(AText, mTill, ATabWidth),
        AContext.EditorLineNum);
      mLeft := mFirst.Left;
      mRight := Max(mLast.Left, mLeft + Max(cMinMarkWidth, mFirst.Width));
      DrawMark(mDC, TColor(ProblemColor(mColors, mProblem)), mProblem, mLeft, mRight, ARect);
      TAtlasIdeElements.Painted(TAtlasHideTarget.ForProblem(AContext.FileName, mProblem, mLine, AText),
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
  mLine, mSource, mTabWidth: Integer;
  mText: string;
  mBusy: Boolean;
begin
  // Durch die Sicherung abgeschaltet (#493).
  // Beim Debuggen ausgeblendet (#2962).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) or FHidden or BeforeEvent or (Stage <> plsEndPaint) or
    (Context = nil) then
  begin
    Exit;
  end;
  // Unter dem mitlaufenden Kopf nicht: Er deckt die Zeile ab, und wer nach ihm zeichnet, läge darüber.
  if TAtlasIdeEditorCover.Covers(Rect, Context) then
  begin
    Exit;
  end;
  try
    mLine := Context.LogicalLineNum - 1;
    // Was jetzt in dieser Zeile steht (#1818); weggerückte oder gelöschte Zeilen tragen keine Marke.
    if not TAtlasIdeLineTracker.SourceAt(Tracked(Context), mLine, mSource) then
    begin
      Exit;
    end;
    mProblems := FStore.OnLine(Context.FileName, mSource);
    // Einstellung erst hier, ohne Kopie des Einstellungsrecords: die meisten Zeilen haben keine Probleme.
    if (Length(mProblems) > 0) and TAtlasIdeEditorSettings.ProblemMarksOn and
      LineToPaint(Context, mSource, mText, mTabWidth, mBusy) then
    begin
      PaintMarks(Rect, Context, mProblems, mSource, mText, mTabWidth);
      if not mBusy then
      begin
        PaintInline(Rect, Context, mProblems, mSource, mText, mTabWidth);
      end;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

/// <summary>Zuordnung der verfolgten Befundzeilen zum aktuellen Stand der Datei von AContext; fehlt sie, merkt
/// sich der Zeichner die Datei für FollowTick vor und zeichnet bis dahin jede Zeile als sie selbst.</summary>
function TAtlasProblemsPainter.Tracked(const AContext: INTACodeEditorPaintContext): TAtlasTrackedLines;
var
  mFileName: string;
begin
  Result := nil;
  if not TAtlasIdeEditorSettings.TrackLinesOn then
  begin
    Exit;
  end;
  mFileName := AContext.FileName;
  Result := TAtlasIdeLineTracker.Current(mFileName, TAtlasLineTracking.cProblems, FStore.Stamp(mFileName));
  if Result = nil then
  begin
    // Anmelden ändert die Zeilentabelle des Editors: erst nach dem Zeichnen, für jede vorgemerkte Datei.
    FFollowFiles.Add(mFileName);
    FFollowTimer.Enabled := True;
  end;
end;

class procedure TAtlasProblemsPainter.Invalidate;
begin
  TAtlasIdeEditorRefresh.InvalidateCurrent;
end;

end.
