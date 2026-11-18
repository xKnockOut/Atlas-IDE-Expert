unit Atlas.UI.Debug.ExceptionBarPainter;

// Zeichnet die Exception-Leiste (#783, #865) im Atlas-Stil (#410, #411): die
// Leiste als Karte mit Akzentrahmen und runden Ecken auf der Fläche des
// Editors, darin
//   1. Klasse (fett, Fehlerfarbe) und Meldung; rechts „n× an dieser Stelle“.
//   2. Thread, „n Ebenen ausgeblendet“ und die erste eigene Zeile; unter der
//      Maus unterstrichen in der Akzentfarbe.
//   (Erklärung: Trennlinie, Ergebniszeile, geprüfte Glieder mit ✓/✗ in der
//   Farbe ihres Zustands, „… n weitere“, Knöpfe der Erklärung.)
//   3. Knöpfe, „Fortsetzen“ als Hauptknopf im Akzent, rechts die
//      Tastenhinweise, wenn Platz ist.
// Wo was liegt, sagt TAtlasDebugBarLayout; Texte und Farben kommen von hier.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.Core.Debug.ExceptionBarLayout;

type
  /// <summary>Ein Zeichenvorgang der Leiste: für ein Paint anlegen, zeichnen, freigeben.</summary>
  TAtlasDebugBarPainter = class
  private
    FCanvas: TCanvas;
    FFont: TFont;
    FLayout: TAtlasDebugBarLayout;
    FColors: TAtlasColors;
    FHot: TAtlasDebugBarAction;
    procedure PaintTitle(const AFrame: TRect);
    procedure PaintDetail(const AFrame: TRect);
    procedure PaintExplanation(const AFrame: TRect);
    procedure PaintVerdict(const AFrame: TRect);
    procedure PaintChecks(const AFrame: TRect);
    procedure PaintKeys(const AFrame: TRect);
    procedure DrawButton(AAction: TAtlasDebugBarAction);
  public
    /// <summary>ACanvas und AFont gehören der Leiste; AHot: Knopf bzw. Ortszeile unter der Maus.</summary>
    constructor Create(ACanvas: TCanvas; AFont: TFont; ALayout: TAtlasDebugBarLayout; const AColors: TAtlasColors;
      AHot: TAtlasDebugBarAction);
    /// <summary>Ganze Leiste in AClient; das Layout ist angeordnet.</summary>
    procedure Paint(const AClient: TRect);
    /// <summary>Beschriftung des Knopfs AAction; AWhereName für „Wo wird X zugewiesen?“.</summary>
    class function Caption(AAction: TAtlasDebugBarAction; const AWhereName: string): string; static;
    /// <summary>Zeile 2: Thread, ausgeblendete Ebenen, erste eigene Zeile.</summary>
    class function DetailText(const AInfo: TAtlasDebugBannerInfo): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.UITypes,
  Atlas.Core.Style.Color,
  Atlas.UI.Debug.AccessViolation.Strings,
  Atlas.UI.Debug.Exceptions.Strings;

const
  /// <summary>Rundung der Karte und der Knöpfe bei 96 dpi.</summary>
  cCardRound = 8;
  cButtonRound = 6;
  /// <summary>Zeilen vor der Erklärung (Titel, Ort); die Ergebniszeile ist Zeile 2, die Glieder folgen.</summary>
  cVerdictRow = 2;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>AText einzeilig, senkrecht mittig in ARect; AFlags: Ausrichtung, ggf. DT_END_ELLIPSIS.</summary>
procedure TextIn(ACanvas: TCanvas; const AText: string; ARect: TRect; AFlags: Cardinal);
begin
  DrawText(ACanvas.Handle, PChar(AText), -1, ARect, AFlags or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

function MarkColor(const AColors: TAtlasColors; AMark: TAtlasDebugBannerMark): TColor;
begin
  case AMark of
    TAtlasDebugBannerMark.Ok:
      Result := ToColor(AColors.Add);
    TAtlasDebugBannerMark.Bad:
      Result := ToColor(AColors.Error);
  else
    Result := ToColor(AColors.Muted);
  end;
end;

{ TAtlasDebugBarPainter }

constructor TAtlasDebugBarPainter.Create(ACanvas: TCanvas; AFont: TFont; ALayout: TAtlasDebugBarLayout;
  const AColors: TAtlasColors; AHot: TAtlasDebugBarAction);
begin
  inherited Create;
  FCanvas := ACanvas;
  FFont := AFont;
  FLayout := ALayout;
  FColors := AColors;
  FHot := AHot;
end;

class function TAtlasDebugBarPainter.Caption(AAction: TAtlasDebugBarAction; const AWhereName: string): string;
begin
  case AAction of
    TAtlasDebugBarAction.BreakHere:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerBreak);
    TAtlasDebugBarAction.Continue:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerContinue);
    TAtlasDebugBarAction.IgnoreClass:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerIgnoreClass);
    TAtlasDebugBarAction.IgnoreLocation:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerIgnoreLocation);
    TAtlasDebugBarAction.Copy:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerCopy);
    TAtlasDebugBarAction.WhereAssigned:
      Result := TAtlasAccessViolationStrings.Fmt(TAtlasAccessViolationTextId.DebugAvWhereAssigned, [AWhereName]);
    TAtlasDebugBarAction.Evaluate:
      Result := TAtlasAccessViolationStrings.Text(TAtlasAccessViolationTextId.DebugAvEvaluate);
    TAtlasDebugBarAction.CopyExplanation:
      Result := TAtlasAccessViolationStrings.Text(TAtlasAccessViolationTextId.DebugAvCopy);
    TAtlasDebugBarAction.CreateTest:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerCreateTest);
    TAtlasDebugBarAction.MessageRule:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerMessageRule);
  else
    Result := '';
  end;
end;

class function TAtlasDebugBarPainter.DetailText(const AInfo: TAtlasDebugBannerInfo): string;
var
  mParts: TArray<string>;
  mPlace: string;
begin
  mParts := nil;
  if AInfo.ThreadText <> '' then
  begin
    mParts := mParts + [TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugBannerThread, [AInfo.ThreadText])];
  end;
  if AInfo.Hidden > 0 then
  begin
    mParts := mParts + [TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugBannerHidden, [AInfo.Hidden])];
  end;
  mPlace := AInfo.Routine;
  if AInfo.LocationText <> '' then
  begin
    if mPlace <> '' then
    begin
      mPlace := mPlace + ' (' + AInfo.LocationText + ')';
    end
    else
    begin
      mPlace := AInfo.LocationText;
    end;
  end;
  if mPlace <> '' then
  begin
    mParts := mParts + [mPlace];
  end;
  Result := string.Join(' · ', mParts);
end;

procedure TAtlasDebugBarPainter.Paint(const AClient: TRect);
var
  mFrame: TRect;
  mAction: TAtlasDebugBarAction;
begin
  FCanvas.Brush.Style := bsSolid;
  // Fläche des Editors außen, die Leiste als Karte mit Akzentrahmen darin.
  FCanvas.Brush.Color := ToColor(FColors.Gutter);
  FCanvas.FillRect(AClient);
  mFrame := Rect(FLayout.Scale(TAtlasDebugBarLayout.cBarPadding div 2), FLayout.Scale(1),
    AClient.Right - FLayout.Scale(TAtlasDebugBarLayout.cBarPadding div 2), AClient.Bottom - FLayout.Scale(1));
  FCanvas.Brush.Color := ToColor(FColors.Surface);
  FCanvas.Pen.Color := ToColor(FColors.Accent);
  FCanvas.RoundRect(mFrame.Left, mFrame.Top, mFrame.Right, mFrame.Bottom, FLayout.Scale(cCardRound),
    FLayout.Scale(cCardRound));
  FCanvas.Brush.Style := bsClear;
  PaintTitle(mFrame);
  PaintDetail(mFrame);
  PaintExplanation(mFrame);
  // Letzte Zeile: Knöpfe, rechts die Tastenhinweise.
  for mAction in cDebugBarButtons do
  begin
    DrawButton(mAction);
  end;
  PaintKeys(mFrame);
end;

/// <summary>Zeile 1: Klasse und Meldung, rechts der Zähler.</summary>
procedure TAtlasDebugBarPainter.PaintTitle(const AFrame: TRect);
var
  mLine: TRect;
  mText: string;
  mRight, mGap, mRow: Integer;
begin
  FCanvas.Font := FFont;
  mGap := FLayout.Scale(TAtlasDebugBarLayout.cGap);
  mRow := FLayout.RowHeight;
  mRight := AFrame.Right - mGap;
  if FLayout.Info.Count > 1 then
  begin
    mText := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugBannerCount, [FLayout.Info.Count]);
    FCanvas.Font.Color := ToColor(FColors.Warn);
    TextIn(FCanvas, mText, Rect(AFrame.Left, AFrame.Top, mRight, AFrame.Top + mRow), DT_RIGHT);
    Dec(mRight, FCanvas.TextWidth(mText) + mGap);
  end;
  mLine := Rect(AFrame.Left + mGap, AFrame.Top, mRight, AFrame.Top + mRow);
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := ToColor(FColors.Error);
  mText := FLayout.Info.ExceptionClass;
  TextIn(FCanvas, mText, mLine, DT_LEFT);
  Inc(mLine.Left, FCanvas.TextWidth(mText));
  FCanvas.Font.Style := [];
  FCanvas.Font.Color := ToColor(FColors.Text);
  if FLayout.Info.Message <> '' then
  begin
    TextIn(FCanvas, ': ' + FLayout.Info.Message, mLine, DT_LEFT or DT_END_ELLIPSIS);
  end;
end;

/// <summary>Zeile 2: Thread, ausgeblendete Ebenen, erste eigene Zeile.</summary>
procedure TAtlasDebugBarPainter.PaintDetail(const AFrame: TRect);
var
  mGap, mRow: Integer;
begin
  if FHot = TAtlasDebugBarAction.Open then
  begin
    FCanvas.Font.Color := ToColor(FColors.Accent);
    FCanvas.Font.Style := [fsUnderline];
  end
  else
  begin
    FCanvas.Font.Color := ToColor(FColors.Muted);
  end;
  mGap := FLayout.Scale(TAtlasDebugBarLayout.cGap);
  mRow := FLayout.RowHeight;
  TextIn(FCanvas, DetailText(FLayout.Info), Rect(AFrame.Left + mGap, AFrame.Top + mRow, AFrame.Right - mGap,
    AFrame.Top + 2 * mRow), DT_LEFT or DT_END_ELLIPSIS);
  FCanvas.Font.Style := [];
end;

procedure TAtlasDebugBarPainter.PaintExplanation(const AFrame: TRect);
var
  mAction: TAtlasDebugBarAction;
  mGap, mLineTop: Integer;
begin
  if not FLayout.Explanation.Active then
  begin
    Exit;
  end;
  // Trennlinie über der Erklärung.
  mGap := FLayout.Scale(TAtlasDebugBarLayout.cGap);
  mLineTop := FLayout.RowTop(cVerdictRow) + FLayout.Scale(1);
  FCanvas.Pen.Color := ToColor(FColors.Line);
  FCanvas.MoveTo(AFrame.Left + mGap, mLineTop);
  FCanvas.LineTo(AFrame.Right - mGap, mLineTop);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font := FFont;
  PaintVerdict(AFrame);
  if FLayout.Explanation.Busy then
  begin
    Exit;
  end;
  PaintChecks(AFrame);
  for mAction in cDebugExplanationButtons do
  begin
    DrawButton(mAction);
  end;
end;

/// <summary>Ergebniszeile der Erklärung, daneben der Zusatz.</summary>
procedure TAtlasDebugBarPainter.PaintVerdict(const AFrame: TRect);
var
  mLine: TRect;
  mExplanation: TAtlasDebugBannerExplanation;
  mGap: Integer;
begin
  mExplanation := FLayout.Explanation;
  mGap := FLayout.Scale(TAtlasDebugBarLayout.cGap);
  mLine := Rect(AFrame.Left + mGap, FLayout.RowTop(cVerdictRow), AFrame.Right - mGap,
    FLayout.RowTop(cVerdictRow + 1));
  if mExplanation.Busy then
  begin
    FCanvas.Font.Color := ToColor(FColors.Muted);
  end
  else
  begin
    FCanvas.Font.Style := [fsBold];
    FCanvas.Font.Color := MarkColor(FColors, mExplanation.HeadlineMark);
    if mExplanation.HeadlineMark = TAtlasDebugBannerMark.Neutral then
    begin
      FCanvas.Font.Color := ToColor(FColors.Warn);
    end;
  end;
  TextIn(FCanvas, mExplanation.Headline, mLine, DT_LEFT or DT_END_ELLIPSIS);
  Inc(mLine.Left, FCanvas.TextWidth(mExplanation.Headline));
  FCanvas.Font.Style := [];
  if (mExplanation.Detail <> '') and not mExplanation.Busy then
  begin
    FCanvas.Font.Color := ToColor(FColors.Muted);
    TextIn(FCanvas, ' ' + #$00B7 + ' ' + mExplanation.Detail, mLine, DT_LEFT or DT_END_ELLIPSIS);
  end;
end;

/// <summary>Geprüfte Glieder der Erklärung, eingerückt, Zeichen in der Farbe des Zustands; darunter
/// „… n weitere“.</summary>
procedure TAtlasDebugBarPainter.PaintChecks(const AFrame: TRect);
var
  mLine: TRect;
  mIndex, mRow, mIndent, mGap: Integer;
  mLines: TArray<TAtlasDebugBannerLine>;
begin
  mLines := FLayout.Explanation.Lines;
  mGap := FLayout.Scale(TAtlasDebugBarLayout.cGap);
  mIndent := FCanvas.TextWidth(TAtlasDebugBannerLine.MarkText(TAtlasDebugBannerMark.Bad)) + mGap;
  mRow := cVerdictRow + 1;
  for mIndex := 0 to FLayout.ShownLines - 1 do
  begin
    mLine := Rect(AFrame.Left + 2 * mGap, FLayout.RowTop(mRow), AFrame.Right - mGap, FLayout.RowTop(mRow + 1));
    FCanvas.Font.Color := MarkColor(FColors, mLines[mIndex].Mark);
    TextIn(FCanvas, TAtlasDebugBannerLine.MarkText(mLines[mIndex].Mark), mLine, DT_LEFT);
    Inc(mLine.Left, mIndent);
    FCanvas.Font.Color := ToColor(FColors.Text);
    TextIn(FCanvas, mLines[mIndex].Text, mLine, DT_LEFT or DT_END_ELLIPSIS);
    Inc(mRow);
  end;
  if Length(mLines) > TAtlasDebugBarLayout.cMaxExplanationLines then
  begin
    FCanvas.Font.Color := ToColor(FColors.Muted);
    TextIn(FCanvas, TAtlasAccessViolationStrings.Fmt(TAtlasAccessViolationTextId.DebugAvMore,
      [Length(mLines) - TAtlasDebugBarLayout.cMaxExplanationLines]),
      Rect(AFrame.Left + 2 * mGap + mIndent, FLayout.RowTop(mRow), AFrame.Right - mGap, FLayout.RowTop(mRow + 1)),
      DT_LEFT);
  end;
end;

/// <summary>Letzte Zeile: rechts neben den Knöpfen die Tastenhinweise, wenn Platz ist.</summary>
procedure TAtlasDebugBarPainter.PaintKeys(const AFrame: TRect);
var
  mLine: TRect;
  mText: string;
  mGap: Integer;
begin
  FCanvas.Font := FFont;
  FCanvas.Font.Color := ToColor(FColors.Muted);
  FCanvas.Brush.Style := bsClear;
  mGap := FLayout.Scale(TAtlasDebugBarLayout.cGap);
  mText := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerKeys);
  mLine := Rect(FLayout.LastButtonRight + mGap, FLayout.RowTop(FLayout.Rows - 1), AFrame.Right - mGap,
    AFrame.Bottom);
  if mLine.Width > FCanvas.TextWidth(mText) then
  begin
    TextIn(FCanvas, mText, mLine, DT_RIGHT);
  end;
end;

procedure TAtlasDebugBarPainter.DrawButton(AAction: TAtlasDebugBarAction);
var
  mArea: TRect;
  mText: string;
  mPrimary: Boolean;
begin
  mArea := FLayout.ActionRect(AAction);
  if mArea.IsEmpty then
  begin
    Exit;
  end;
  // Fortsetzen ist der Hauptknopf (Akzent), die übrigen wie die Knöpfe der Editorleiste.
  mPrimary := AAction = TAtlasDebugBarAction.Continue;
  FCanvas.Brush.Style := bsSolid;
  if mPrimary then
  begin
    FCanvas.Brush.Color := ToColor(FColors.AccentSoft);
    FCanvas.Pen.Color := ToColor(FColors.Accent);
  end
  else if FHot = AAction then
  begin
    FCanvas.Brush.Color := ToColor(FColors.Selection);
    FCanvas.Pen.Color := ToColor(FColors.Line);
  end
  else
  begin
    FCanvas.Brush.Color := ToColor(FColors.Gutter);
    FCanvas.Pen.Color := ToColor(FColors.Line);
  end;
  FCanvas.RoundRect(mArea.Left, mArea.Top, mArea.Right, mArea.Bottom, FLayout.Scale(cButtonRound),
    FLayout.Scale(cButtonRound));
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font := FFont;
  if mPrimary then
  begin
    FCanvas.Font.Color := ToColor(FColors.Accent);
  end
  else
  begin
    FCanvas.Font.Color := ToColor(FColors.Text);
  end;
  mText := Caption(AAction, FLayout.Explanation.WhereName);
  DrawText(FCanvas.Handle, PChar(mText), -1, mArea, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

end.
