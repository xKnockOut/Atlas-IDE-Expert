unit Atlas.UI.Debug.ExceptionBar;

// Exception-Leiste beim Debuggen (#783), Darstellung: drei Zeilen oben im
// Editor, im Atlas-Stil (#410, #411: Akzentrahmen, runde Ecken, Farben nach
// IDE-Thema über SetColors).
//   1. Klasse (fett, Fehlerfarbe) und Meldung; rechts „n× an dieser Stelle“.
//   2. Thread, „n Ebenen ausgeblendet“ und die erste eigene Zeile (Routine,
//      Unit:Zeile; Klick springt hin, OnAction Open).
//   3. Knöpfe Anhalten, Fortsetzen, Klasse ignorieren, Nur an dieser Stelle
//      ignorieren (nur mit TAtlasDebugBannerInfo.CanIgnoreLocation), Meldung
//      kopieren; rechts die Tastenhinweise als Fußzeile.
// Erklärung einer Zugriffsverletzung (#865, SetExplanation): zwischen Zeile 2
// und den Knöpfen eine Zeile mit dem Ergebnis („Auftrag.Kunde ist nil“ und
// Feld bzw. Versatz), darunter die geprüften Glieder mit ✓/✗ (höchstens
// MaxExplanationLines, dann „… n weitere“) und eine Zeile mit den Knöpfen
// „Wo wird X zugewiesen?“, „Ausdruck auswerten“, „Erklärung kopieren“. Die
// Höhe wächst mit den Zeilen. Während Atlas prüft, steht nur die Ergebniszeile
// („Atlas prüft …“) da.
// Gezeichnet wird alles selbst (kein Fokus, keine Fenster für Knöpfe), damit
// der Editor die Tasten behält; die Tasten F8, F9 und Esc fängt die IDE-Schicht.
// Ausgelöst wird beim Loslassen auf demselben Knopf. Was ein Knopf tut,
// entscheidet der Aufrufer (Atlas.IDE.Debug.ExceptionBar).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.ExceptionBanner;

type
  {$SCOPEDENUMS ON}
  TAtlasDebugBarAction = (None, BreakHere, Continue, IgnoreClass, IgnoreLocation, Copy, Open, WhereAssigned, Evaluate,
    CopyExplanation);
  {$SCOPEDENUMS OFF}

  TAtlasDebugBarActionEvent = reference to procedure(AAction: TAtlasDebugBarAction);

  TAtlasDebugExceptionBar = class(TCustomControl)
  private
    FInfo: TAtlasDebugBannerInfo;
    FExplanation: TAtlasDebugBannerExplanation;
    FColors: TAtlasColors;
    FRects: array[TAtlasDebugBarAction] of TRect;
    FHot: TAtlasDebugBarAction;
    FDown: TAtlasDebugBarAction;
    FLaidOut: Boolean;
    FOnAction: TAtlasDebugBarActionEvent;
    function Scale(AValue: Integer): Integer;
    function RowHeight: Integer;
    function DetailText: string;
    function ExplanationRows: Integer;
    function ShownLines: Integer;
    function RowTop(ARow: Integer): Integer;
    procedure ApplyHeight;
    procedure Layout;
    procedure PaintExplanation(const AFrame: TRect);
    procedure DrawButton(AAction: TAtlasDebugBarAction);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetInfo(const AInfo: TAtlasDebugBannerInfo);
    /// <summary>Erklärung zeigen bzw. mit Active = False entfernen; die Höhe passt sich an.</summary>
    procedure SetExplanation(const AExplanation: TAtlasDebugBannerExplanation);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Höhe der Leiste bei APPI (drei Zeilen, 78 px bei 96 DPI).</summary>
    class function BarHeight(APPI: Integer): Integer; overload; static;
    /// <summary>Höhe bei APPI mit ARows Zeilen.</summary>
    class function BarHeight(APPI, ARows: Integer): Integer; overload; static;
    /// <summary>Zeilen der Leiste: drei, mit Erklärung mehr.</summary>
    function Rows: Integer;
    /// <summary>Knopf bzw. Ortszeile unter dem Punkt (Client); None = nichts.</summary>
    function ActionAt(AX, AY: Integer): TAtlasDebugBarAction;
    /// <summary>Fläche eines Knopfs (Client); leer, wenn er fehlt.</summary>
    function ActionRect(AAction: TAtlasDebugBarAction): TRect;
    /// <summary>Wie ein Klick (Tasten, Tests): meldet OnAction, wenn es den Knopf gibt.</summary>
    procedure Trigger(AAction: TAtlasDebugBarAction);
    /// <summary>Zeile 2 als Text (für Tests und Tooltip).</summary>
    property Detail: string read DetailText;
    property Info: TAtlasDebugBannerInfo read FInfo;
    property Explanation: TAtlasDebugBannerExplanation read FExplanation;
    property OnAction: TAtlasDebugBarActionEvent read FOnAction write FOnAction;
  end;

implementation

uses
  Atlas.Core.Style.Color,
  System.Math,
  Vcl.Forms,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Knöpfe der dritten Zeile in Reihenfolge.</summary>
  cBarButtons: array[0..4] of TAtlasDebugBarAction = (TAtlasDebugBarAction.BreakHere,
    TAtlasDebugBarAction.Continue, TAtlasDebugBarAction.IgnoreClass, TAtlasDebugBarAction.IgnoreLocation,
    TAtlasDebugBarAction.Copy);
  /// <summary>Knöpfe der Erklärung in Reihenfolge.</summary>
  cExplanationButtons: array[0..2] of TAtlasDebugBarAction = (TAtlasDebugBarAction.WhereAssigned,
    TAtlasDebugBarAction.Evaluate, TAtlasDebugBarAction.CopyExplanation);
  /// <summary>Höchstens so viele geprüfte Glieder; der Rest als „… n weitere“.</summary>
  cMaxExplanationLines = 6;
  cBaseRow = 24;
  cBarPadding = 6;
  cGap = 6;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>AText einzeilig, senkrecht mittig in ARect; AFlags: Ausrichtung, ggf. DT_END_ELLIPSIS.</summary>
procedure TextIn(ACanvas: TCanvas; const AText: string; ARect: TRect; AFlags: Cardinal);
begin
  DrawText(ACanvas.Handle, PChar(AText), -1, ARect, AFlags or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

/// <summary>Gibt es den Knopf AAction der Erklärung AExplanation?</summary>
function ExplanationHas(const AExplanation: TAtlasDebugBannerExplanation;
  AAction: TAtlasDebugBarAction): Boolean;
begin
  Result := False;
  if not AExplanation.Active or AExplanation.Busy then
  begin
    Exit;
  end;
  case AAction of
    TAtlasDebugBarAction.WhereAssigned:
      Result := AExplanation.WhereName <> '';
    TAtlasDebugBarAction.Evaluate:
      Result := AExplanation.EvaluateExpression <> '';
    TAtlasDebugBarAction.CopyExplanation:
      Result := AExplanation.CopyText <> '';
    TAtlasDebugBarAction.None, TAtlasDebugBarAction.BreakHere, TAtlasDebugBarAction.Continue,
    TAtlasDebugBarAction.IgnoreClass, TAtlasDebugBarAction.IgnoreLocation, TAtlasDebugBarAction.Copy,
    TAtlasDebugBarAction.Open: ;
  end;
end;

/// <summary>Beschriftung des Knopfs AAction; AWhereName für „Wo wird X zugewiesen?“.</summary>
function ActionCaption(AAction: TAtlasDebugBarAction; const AWhereName: string): string;
begin
  case AAction of
    TAtlasDebugBarAction.BreakHere:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerBreak);
    TAtlasDebugBarAction.Continue:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerContinue);
    TAtlasDebugBarAction.IgnoreClass:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerIgnoreClass);
    TAtlasDebugBarAction.IgnoreLocation:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerIgnoreLocation);
    TAtlasDebugBarAction.Copy:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerCopy);
    TAtlasDebugBarAction.WhereAssigned:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvWhereAssigned, [AWhereName]);
    TAtlasDebugBarAction.Evaluate:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvEvaluate);
    TAtlasDebugBarAction.CopyExplanation:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvCopy);
  else
    Result := '';
  end;
end;

{ TAtlasDebugExceptionBar }

constructor TAtlasDebugExceptionBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  ShowHint := True;
  FColors := TAtlasColors.Light;
  FHot := TAtlasDebugBarAction.None;
  FDown := TAtlasDebugBarAction.None;
  Height := BarHeight(96);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

class function TAtlasDebugExceptionBar.BarHeight(APPI: Integer): Integer;
begin
  Result := BarHeight(APPI, 3);
end;

class function TAtlasDebugExceptionBar.BarHeight(APPI, ARows: Integer): Integer;
begin
  Result := MulDiv(ARows * cBaseRow + cBarPadding, Max(APPI, 96), 96);
end;

function TAtlasDebugExceptionBar.ShownLines: Integer;
begin
  Result := Min(Length(FExplanation.Lines), cMaxExplanationLines);
end;

function TAtlasDebugExceptionBar.ExplanationRows: Integer;
begin
  Result := 0;
  if not FExplanation.Active then
  begin
    Exit;
  end;
  // Ergebniszeile; fertig auch Glieder, „… n weitere“ und die Knöpfe.
  Result := 1;
  if FExplanation.Busy then
  begin
    Exit;
  end;
  Inc(Result, ShownLines);
  if Length(FExplanation.Lines) > cMaxExplanationLines then
  begin
    Inc(Result);
  end;
  if (FExplanation.WhereName <> '') or (FExplanation.EvaluateExpression <> '') or (FExplanation.CopyText <> '') then
  begin
    Inc(Result);
  end;
end;

function TAtlasDebugExceptionBar.Rows: Integer;
begin
  Result := 3 + ExplanationRows;
end;

function TAtlasDebugExceptionBar.RowTop(ARow: Integer): Integer;
begin
  Result := Scale(cBarPadding div 2) + ARow * RowHeight;
end;

procedure TAtlasDebugExceptionBar.ApplyHeight;
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  Height := BarHeight(CurrentPPI, Rows);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

procedure TAtlasDebugExceptionBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  inherited ChangeScale(M, D, isDpiChange);
  ApplyHeight;
  FLaidOut := False;
end;

function TAtlasDebugExceptionBar.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

function TAtlasDebugExceptionBar.RowHeight: Integer;
begin
  Result := Scale(cBaseRow);
end;

procedure TAtlasDebugExceptionBar.SetInfo(const AInfo: TAtlasDebugBannerInfo);
begin
  FInfo := AInfo;
  FLaidOut := False;
  Hint := FInfo.Message;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.SetExplanation(const AExplanation: TAtlasDebugBannerExplanation);
begin
  FExplanation := AExplanation;
  ApplyHeight;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

function TAtlasDebugExceptionBar.DetailText: string;
var
  mParts: TArray<string>;
  mPlace: string;
begin
  mParts := nil;
  if FInfo.ThreadText <> '' then
  begin
    mParts := mParts + [TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugBannerThread, [FInfo.ThreadText])];
  end;
  if FInfo.Hidden > 0 then
  begin
    mParts := mParts + [TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugBannerHidden, [FInfo.Hidden])];
  end;
  mPlace := FInfo.Routine;
  if FInfo.LocationText <> '' then
  begin
    if mPlace <> '' then
    begin
      mPlace := mPlace + ' (' + FInfo.LocationText + ')';
    end
    else
    begin
      mPlace := FInfo.LocationText;
    end;
  end;
  if mPlace <> '' then
  begin
    mParts := mParts + [mPlace];
  end;
  Result := string.Join(' · ', mParts);
end;

procedure TAtlasDebugExceptionBar.Layout;
var
  mAction: TAtlasDebugBarAction;
  mLeft, mTop, mWidth_: Integer;
  mPlace: string;
begin
  if FLaidOut or not HandleAllocated then
  begin
    Exit;
  end;
  for mAction := Low(TAtlasDebugBarAction) to High(TAtlasDebugBarAction) do
  begin
    FRects[mAction] := TRect.Empty;
  end;
  Canvas.Font := Font;
  // Ortszeile: nur der Teil mit Routine und Datei ist anklickbar, und nur mit Datei.
  if FInfo.HasLocation then
  begin
    mPlace := DetailText;
    mWidth_ := Min(Canvas.TextWidth(mPlace), ClientWidth - 2 * Scale(cBarPadding + cGap));
    FRects[TAtlasDebugBarAction.Open] := Rect(Scale(cBarPadding + cGap), Scale(cBarPadding div 2) + RowHeight,
      Scale(cBarPadding + cGap) + mWidth_, Scale(cBarPadding div 2) + 2 * RowHeight);
  end;
  // Knöpfe der Erklärung in ihrer letzten Zeile (über den Knöpfen der Leiste).
  if FExplanation.Active and not FExplanation.Busy then
  begin
    mTop := RowTop(Rows - 2) + Scale(2);
    mLeft := Scale(cBarPadding + cGap);
    for mAction in cExplanationButtons do
    begin
      if not ExplanationHas(FExplanation, mAction) then
      begin
        Continue;
      end;
      mWidth_ := Canvas.TextWidth(ActionCaption(mAction, FExplanation.WhereName)) + Scale(16);
      FRects[mAction] := Rect(mLeft, mTop, mLeft + mWidth_, mTop + RowHeight - Scale(4));
      Inc(mLeft, mWidth_ + Scale(cGap));
    end;
  end;
  mTop := RowTop(Rows - 1) + Scale(2);
  mLeft := Scale(cBarPadding + cGap);
  for mAction in cBarButtons do
  begin
    if (mAction = TAtlasDebugBarAction.IgnoreLocation) and not FInfo.CanIgnoreLocation then
    begin
      Continue;
    end;
    mWidth_ := Canvas.TextWidth(ActionCaption(mAction, FExplanation.WhereName)) + Scale(16);
    FRects[mAction] := Rect(mLeft, mTop, mLeft + mWidth_, mTop + RowHeight - Scale(4));
    Inc(mLeft, mWidth_ + Scale(cGap));
  end;
  FLaidOut := True;
end;

procedure TAtlasDebugExceptionBar.Resize;
begin
  inherited Resize;
  FLaidOut := False;
end;

procedure TAtlasDebugExceptionBar.CMFontChanged(var Message: TMessage);
begin
  inherited;
  FLaidOut := False;
  Invalidate;
end;

function TAtlasDebugExceptionBar.ActionRect(AAction: TAtlasDebugBarAction): TRect;
begin
  Layout;
  Result := FRects[AAction];
end;

function TAtlasDebugExceptionBar.ActionAt(AX, AY: Integer): TAtlasDebugBarAction;
var
  mAction: TAtlasDebugBarAction;
begin
  Layout;
  for mAction := Succ(TAtlasDebugBarAction.None) to High(TAtlasDebugBarAction) do
  begin
    if not FRects[mAction].IsEmpty and FRects[mAction].Contains(Point(AX, AY)) then
    begin
      Exit(mAction);
    end;
  end;
  Result := TAtlasDebugBarAction.None;
end;

procedure TAtlasDebugExceptionBar.Trigger(AAction: TAtlasDebugBarAction);
begin
  if AAction = TAtlasDebugBarAction.None then
  begin
    Exit;
  end;
  // Ohne Ort gibt es weder „Nur an dieser Stelle ignorieren“ noch den Sprung.
  if (AAction = TAtlasDebugBarAction.IgnoreLocation) and not FInfo.CanIgnoreLocation then
  begin
    Exit;
  end;
  if (AAction = TAtlasDebugBarAction.Open) and not FInfo.HasLocation then
  begin
    Exit;
  end;
  if (AAction in [TAtlasDebugBarAction.WhereAssigned, TAtlasDebugBarAction.Evaluate,
    TAtlasDebugBarAction.CopyExplanation]) and not ExplanationHas(FExplanation, AAction) then
  begin
    Exit;
  end;
  if Assigned(FOnAction) then
  begin
    FOnAction(AAction);
  end;
end;

procedure TAtlasDebugExceptionBar.DrawButton(AAction: TAtlasDebugBarAction);
var
  mArea: TRect;
  mText: string;
  mPrimary: Boolean;
begin
  mArea := FRects[AAction];
  if mArea.IsEmpty then
  begin
    Exit;
  end;
  // Fortsetzen ist der Hauptknopf (Akzent), die übrigen wie die Knöpfe der Editorleiste.
  mPrimary := AAction = TAtlasDebugBarAction.Continue;
  Canvas.Brush.Style := bsSolid;
  if mPrimary then
  begin
    Canvas.Brush.Color := ToColor(FColors.AccentSoft);
    Canvas.Pen.Color := ToColor(FColors.Accent);
  end
  else if FHot = AAction then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.Pen.Color := ToColor(FColors.Line);
  end
  else
  begin
    Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.Pen.Color := ToColor(FColors.Line);
  end;
  Canvas.RoundRect(mArea.Left, mArea.Top, mArea.Right, mArea.Bottom, Scale(6), Scale(6));
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  if mPrimary then
  begin
    Canvas.Font.Color := ToColor(FColors.Accent);
  end
  else
  begin
    Canvas.Font.Color := ToColor(FColors.Text);
  end;
  mText := ActionCaption(AAction, FExplanation.WhereName);
  DrawText(Canvas.Handle, PChar(mText), -1, mArea, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

/// <summary>Zeile 1 der Leiste ABar in AFrame: Klasse und Meldung, rechts der Zähler.</summary>
procedure PaintTitle(ABar: TAtlasDebugExceptionBar; const AFrame: TRect);
var
  mLine: TRect;
  mText: string;
  mRight: Integer;
begin
  ABar.Canvas.Font := ABar.Font;
  mRight := AFrame.Right - ABar.Scale(cGap);
  if ABar.FInfo.Count > 1 then
  begin
    mText := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugBannerCount, [ABar.FInfo.Count]);
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Warn);
    TextIn(ABar.Canvas, mText, Rect(AFrame.Left, AFrame.Top, mRight, AFrame.Top + ABar.RowHeight), DT_RIGHT);
    Dec(mRight, ABar.Canvas.TextWidth(mText) + ABar.Scale(cGap));
  end;
  mLine := Rect(AFrame.Left + ABar.Scale(cGap), AFrame.Top, mRight, AFrame.Top + ABar.RowHeight);
  ABar.Canvas.Font.Style := [fsBold];
  ABar.Canvas.Font.Color := ToColor(ABar.FColors.Error);
  mText := ABar.FInfo.ExceptionClass;
  TextIn(ABar.Canvas, mText, mLine, DT_LEFT);
  Inc(mLine.Left, ABar.Canvas.TextWidth(mText));
  ABar.Canvas.Font.Style := [];
  ABar.Canvas.Font.Color := ToColor(ABar.FColors.Text);
  if ABar.FInfo.Message <> '' then
  begin
    TextIn(ABar.Canvas, ': ' + ABar.FInfo.Message, mLine, DT_LEFT or DT_END_ELLIPSIS);
  end;
end;

/// <summary>Zeile 2 der Leiste ABar in AFrame: Thread, ausgeblendete Ebenen, erste eigene Zeile.</summary>
procedure PaintDetail(ABar: TAtlasDebugExceptionBar; const AFrame: TRect);
begin
  if ABar.FHot = TAtlasDebugBarAction.Open then
  begin
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Accent);
    ABar.Canvas.Font.Style := [fsUnderline];
  end
  else
  begin
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Muted);
  end;
  TextIn(ABar.Canvas, ABar.DetailText, Rect(AFrame.Left + ABar.Scale(cGap), AFrame.Top + ABar.RowHeight,
    AFrame.Right - ABar.Scale(cGap), AFrame.Top + 2 * ABar.RowHeight), DT_LEFT or DT_END_ELLIPSIS);
  ABar.Canvas.Font.Style := [];
end;

/// <summary>Letzte Zeile der Leiste ABar: rechts neben den Knöpfen die Tastenhinweise, wenn Platz ist.</summary>
procedure PaintKeys(ABar: TAtlasDebugExceptionBar; const AFrame: TRect);
var
  mLine: TRect;
  mText: string;
begin
  ABar.Canvas.Font := ABar.Font;
  ABar.Canvas.Font.Color := ToColor(ABar.FColors.Muted);
  ABar.Canvas.Brush.Style := bsClear;
  mText := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerKeys);
  mLine := Rect(ABar.FRects[TAtlasDebugBarAction.Copy].Right + ABar.Scale(cGap), ABar.RowTop(ABar.Rows - 1),
    AFrame.Right - ABar.Scale(cGap), AFrame.Bottom);
  if mLine.Width > ABar.Canvas.TextWidth(mText) then
  begin
    TextIn(ABar.Canvas, mText, mLine, DT_RIGHT);
  end;
end;

procedure TAtlasDebugExceptionBar.Paint;
var
  mFrame: TRect;
  mAction: TAtlasDebugBarAction;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  // Fläche des Editors außen, die Leiste als Karte mit Akzentrahmen darin.
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  mFrame := Rect(Scale(cBarPadding div 2), Scale(1), ClientWidth - Scale(cBarPadding div 2), ClientHeight - Scale(1));
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.RoundRect(mFrame.Left, mFrame.Top, mFrame.Right, mFrame.Bottom, Scale(8), Scale(8));
  Canvas.Brush.Style := bsClear;
  PaintTitle(Self, mFrame);
  PaintDetail(Self, mFrame);
  PaintExplanation(mFrame);
  // Letzte Zeile: Knöpfe, rechts die Tastenhinweise.
  for mAction in cBarButtons do
  begin
    DrawButton(mAction);
  end;
  PaintKeys(Self, mFrame);
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

/// <summary>Ergebniszeile der Erklärung der Leiste ABar in AFrame, daneben der Zusatz.</summary>
procedure PaintVerdict(ABar: TAtlasDebugExceptionBar; const AFrame: TRect);
var
  mLine: TRect;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  mExplanation := ABar.FExplanation;
  mLine := Rect(AFrame.Left + ABar.Scale(cGap), ABar.RowTop(2), AFrame.Right - ABar.Scale(cGap), ABar.RowTop(3));
  if mExplanation.Busy then
  begin
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Muted);
  end
  else
  begin
    ABar.Canvas.Font.Style := [fsBold];
    ABar.Canvas.Font.Color := MarkColor(ABar.FColors, mExplanation.HeadlineMark);
    if mExplanation.HeadlineMark = TAtlasDebugBannerMark.Neutral then
    begin
      ABar.Canvas.Font.Color := ToColor(ABar.FColors.Warn);
    end;
  end;
  TextIn(ABar.Canvas, mExplanation.Headline, mLine, DT_LEFT or DT_END_ELLIPSIS);
  Inc(mLine.Left, ABar.Canvas.TextWidth(mExplanation.Headline));
  ABar.Canvas.Font.Style := [];
  if (mExplanation.Detail <> '') and not mExplanation.Busy then
  begin
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Muted);
    TextIn(ABar.Canvas, ' ' + #$00B7 + ' ' + mExplanation.Detail, mLine, DT_LEFT or DT_END_ELLIPSIS);
  end;
end;

/// <summary>Geprüfte Glieder der Erklärung von ABar, eingerückt, Zeichen in der Farbe des Zustands; darunter
/// „… n weitere“.</summary>
procedure PaintChecks(ABar: TAtlasDebugExceptionBar; const AFrame: TRect);
var
  mLine: TRect;
  mIndex, mRow, mIndent: Integer;
  mLines: TArray<TAtlasDebugBannerLine>;
begin
  mLines := ABar.FExplanation.Lines;
  mIndent := ABar.Canvas.TextWidth(TAtlasDebugBannerLine.MarkText(TAtlasDebugBannerMark.Bad)) + ABar.Scale(cGap);
  mRow := 3;
  for mIndex := 0 to ABar.ShownLines - 1 do
  begin
    mLine := Rect(AFrame.Left + ABar.Scale(2 * cGap), ABar.RowTop(mRow), AFrame.Right - ABar.Scale(cGap),
      ABar.RowTop(mRow + 1));
    ABar.Canvas.Font.Color := MarkColor(ABar.FColors, mLines[mIndex].Mark);
    TextIn(ABar.Canvas, TAtlasDebugBannerLine.MarkText(mLines[mIndex].Mark), mLine, DT_LEFT);
    Inc(mLine.Left, mIndent);
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Text);
    TextIn(ABar.Canvas, mLines[mIndex].Text, mLine, DT_LEFT or DT_END_ELLIPSIS);
    Inc(mRow);
  end;
  if Length(mLines) > cMaxExplanationLines then
  begin
    ABar.Canvas.Font.Color := ToColor(ABar.FColors.Muted);
    TextIn(ABar.Canvas, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvMore, [Length(mLines) - cMaxExplanationLines]),
      Rect(AFrame.Left + ABar.Scale(2 * cGap) + mIndent, ABar.RowTop(mRow), AFrame.Right - ABar.Scale(cGap),
      ABar.RowTop(mRow + 1)), DT_LEFT);
  end;
end;

procedure TAtlasDebugExceptionBar.PaintExplanation(const AFrame: TRect);
var
  mAction: TAtlasDebugBarAction;
begin
  if not FExplanation.Active then
  begin
    Exit;
  end;
  // Trennlinie über der Erklärung.
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(AFrame.Left + Scale(cGap), RowTop(2) + Scale(1));
  Canvas.LineTo(AFrame.Right - Scale(cGap), RowTop(2) + Scale(1));
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  PaintVerdict(Self, AFrame);
  if FExplanation.Busy then
  begin
    Exit;
  end;
  PaintChecks(Self, AFrame);
  for mAction in cExplanationButtons do
  begin
    DrawButton(mAction);
  end;
end;

procedure TAtlasDebugExceptionBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: TAtlasDebugBarAction;
begin
  inherited MouseMove(Shift, X, Y);
  mHot := ActionAt(X, Y);
  if mHot = FHot then
  begin
    Exit;
  end;
  FHot := mHot;
  if mHot <> TAtlasDebugBarAction.None then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  Application.CancelHint;
  if mHot = TAtlasDebugBarAction.Open then
  begin
    Hint := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerOpenHint);
  end
  else
  begin
    Hint := FInfo.Message;
  end;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FDown := TAtlasDebugBarAction.None;
  if FHot = TAtlasDebugBarAction.None then
  begin
    Exit;
  end;
  FHot := TAtlasDebugBarAction.None;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDown := ActionAt(X, Y);
  end;
end;

procedure TAtlasDebugExceptionBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mAction: TAtlasDebugBarAction;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mAction := ActionAt(X, Y);
  if mAction = FDown then
  begin
    Trigger(mAction);
  end;
  FDown := TAtlasDebugBarAction.None;
end;

end.
