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
  Atlas.Core.Style.Color,
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
    function ActionCaption(AAction: TAtlasDebugBarAction): string;
    function DetailText: string;
    function ExplanationRows: Integer;
    function ExplanationHas(AAction: TAtlasDebugBarAction): Boolean;
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
    function ActionAt(X, Y: Integer): TAtlasDebugBarAction;
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
  System.Math,
  Vcl.Forms,
  Atlas.UI.Strings;

const
  /// <summary>Knöpfe der dritten Zeile in Reihenfolge.</summary>
  BarButtons: array[0..4] of TAtlasDebugBarAction = (TAtlasDebugBarAction.BreakHere,
    TAtlasDebugBarAction.Continue, TAtlasDebugBarAction.IgnoreClass, TAtlasDebugBarAction.IgnoreLocation,
    TAtlasDebugBarAction.Copy);
  /// <summary>Knöpfe der Erklärung in Reihenfolge.</summary>
  ExplanationButtons: array[0..2] of TAtlasDebugBarAction = (TAtlasDebugBarAction.WhereAssigned,
    TAtlasDebugBarAction.Evaluate, TAtlasDebugBarAction.CopyExplanation);
  /// <summary>Höchstens so viele geprüfte Glieder; der Rest als „… n weitere“.</summary>
  MaxExplanationLines = 6;
  BaseRow = 24;
  Padding = 6;
  Gap = 6;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
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
  Result := MulDiv(ARows * BaseRow + Padding, Max(APPI, 96), 96);
end;

function TAtlasDebugExceptionBar.ShownLines: Integer;
begin
  Result := Min(Length(FExplanation.Lines), MaxExplanationLines);
end;

function TAtlasDebugExceptionBar.ExplanationRows: Integer;
begin
  Result := 0;
  if not FExplanation.Active then
    Exit;
  // Ergebniszeile; fertig auch Glieder, „… n weitere“ und die Knöpfe.
  Result := 1;
  if FExplanation.Busy then
    Exit;
  Inc(Result, ShownLines);
  if Length(FExplanation.Lines) > MaxExplanationLines then
    Inc(Result);
  if (FExplanation.WhereName <> '') or (FExplanation.EvaluateExpression <> '') or (FExplanation.CopyText <> '') then
    Inc(Result);
end;

function TAtlasDebugExceptionBar.ExplanationHas(AAction: TAtlasDebugBarAction): Boolean;
begin
  Result := False;
  if not FExplanation.Active or FExplanation.Busy then
    Exit;
  case AAction of
    TAtlasDebugBarAction.WhereAssigned:
      Result := FExplanation.WhereName <> '';
    TAtlasDebugBarAction.Evaluate:
      Result := FExplanation.EvaluateExpression <> '';
    TAtlasDebugBarAction.CopyExplanation:
      Result := FExplanation.CopyText <> '';
  end;
end;

function TAtlasDebugExceptionBar.Rows: Integer;
begin
  Result := 3 + ExplanationRows;
end;

function TAtlasDebugExceptionBar.RowTop(ARow: Integer): Integer;
begin
  Result := Scale(Padding div 2) + ARow * RowHeight;
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
  Result := Scale(BaseRow);
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

function TAtlasDebugExceptionBar.ActionCaption(AAction: TAtlasDebugBarAction): string;
begin
  case AAction of
    TAtlasDebugBarAction.BreakHere:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugBannerBreak);
    TAtlasDebugBarAction.Continue:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugBannerContinue);
    TAtlasDebugBarAction.IgnoreClass:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugBannerIgnoreClass);
    TAtlasDebugBarAction.IgnoreLocation:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugBannerIgnoreLocation);
    TAtlasDebugBarAction.Copy:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugBannerCopy);
    TAtlasDebugBarAction.WhereAssigned:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DebugAvWhereAssigned, [FExplanation.WhereName]);
    TAtlasDebugBarAction.Evaluate:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugAvEvaluate);
    TAtlasDebugBarAction.CopyExplanation:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugAvCopy);
  else
    Result := '';
  end;
end;

function TAtlasDebugExceptionBar.DetailText: string;
var
  Parts: TArray<string>;
  Place: string;
begin
  Parts := nil;
  if FInfo.ThreadText <> '' then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.DebugBannerThread, [FInfo.ThreadText])];
  if FInfo.Hidden > 0 then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.DebugBannerHidden, [FInfo.Hidden])];
  Place := FInfo.Routine;
  if FInfo.LocationText <> '' then
    if Place <> '' then
      Place := Place + ' (' + FInfo.LocationText + ')'
    else
      Place := FInfo.LocationText;
  if Place <> '' then
    Parts := Parts + [Place];
  Result := string.Join(' · ', Parts);
end;

procedure TAtlasDebugExceptionBar.Layout;
var
  Action: TAtlasDebugBarAction;
  Left, Top, Width_: Integer;
  Place: string;
begin
  if FLaidOut or not HandleAllocated then
    Exit;
  for Action := Low(TAtlasDebugBarAction) to High(TAtlasDebugBarAction) do
    FRects[Action] := TRect.Empty;
  Canvas.Font := Font;
  // Ortszeile: nur der Teil mit Routine und Datei ist anklickbar, und nur mit Datei.
  if FInfo.HasLocation then
  begin
    Place := DetailText;
    Width_ := Min(Canvas.TextWidth(Place), ClientWidth - 2 * Scale(Padding + Gap));
    FRects[TAtlasDebugBarAction.Open] := Rect(Scale(Padding + Gap), Scale(Padding div 2) + RowHeight,
      Scale(Padding + Gap) + Width_, Scale(Padding div 2) + 2 * RowHeight);
  end;
  // Knöpfe der Erklärung in ihrer letzten Zeile (über den Knöpfen der Leiste).
  if FExplanation.Active and not FExplanation.Busy then
  begin
    Top := RowTop(Rows - 2) + Scale(2);
    Left := Scale(Padding + Gap);
    for Action in ExplanationButtons do
    begin
      if not ExplanationHas(Action) then
        Continue;
      Width_ := Canvas.TextWidth(ActionCaption(Action)) + Scale(16);
      FRects[Action] := Rect(Left, Top, Left + Width_, Top + RowHeight - Scale(4));
      Inc(Left, Width_ + Scale(Gap));
    end;
  end;
  Top := RowTop(Rows - 1) + Scale(2);
  Left := Scale(Padding + Gap);
  for Action in BarButtons do
  begin
    if (Action = TAtlasDebugBarAction.IgnoreLocation) and not FInfo.CanIgnoreLocation then
      Continue;
    Width_ := Canvas.TextWidth(ActionCaption(Action)) + Scale(16);
    FRects[Action] := Rect(Left, Top, Left + Width_, Top + RowHeight - Scale(4));
    Inc(Left, Width_ + Scale(Gap));
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

function TAtlasDebugExceptionBar.ActionAt(X, Y: Integer): TAtlasDebugBarAction;
var
  Action: TAtlasDebugBarAction;
begin
  Layout;
  for Action := Succ(TAtlasDebugBarAction.None) to High(TAtlasDebugBarAction) do
    if not FRects[Action].IsEmpty and FRects[Action].Contains(Point(X, Y)) then
      Exit(Action);
  Result := TAtlasDebugBarAction.None;
end;

procedure TAtlasDebugExceptionBar.Trigger(AAction: TAtlasDebugBarAction);
begin
  if AAction = TAtlasDebugBarAction.None then
    Exit;
  // Ohne Ort gibt es weder „Nur an dieser Stelle ignorieren“ noch den Sprung.
  if (AAction = TAtlasDebugBarAction.IgnoreLocation) and not FInfo.CanIgnoreLocation then
    Exit;
  if (AAction = TAtlasDebugBarAction.Open) and not FInfo.HasLocation then
    Exit;
  if (AAction in [TAtlasDebugBarAction.WhereAssigned, TAtlasDebugBarAction.Evaluate,
    TAtlasDebugBarAction.CopyExplanation]) and not ExplanationHas(AAction) then
    Exit;
  if Assigned(FOnAction) then
    FOnAction(AAction);
end;

procedure TAtlasDebugExceptionBar.DrawButton(AAction: TAtlasDebugBarAction);
var
  Area: TRect;
  Text: string;
  Primary: Boolean;
begin
  Area := FRects[AAction];
  if Area.IsEmpty then
    Exit;
  // Fortsetzen ist der Hauptknopf (Akzent), die übrigen wie die Knöpfe der Editorleiste.
  Primary := AAction = TAtlasDebugBarAction.Continue;
  Canvas.Brush.Style := bsSolid;
  if Primary then
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
  Canvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, Scale(6), Scale(6));
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  if Primary then
    Canvas.Font.Color := ToColor(FColors.Accent)
  else
    Canvas.Font.Color := ToColor(FColors.Text);
  Text := ActionCaption(AAction);
  DrawText(Canvas.Handle, PChar(Text), -1, Area, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TAtlasDebugExceptionBar.Paint;
var
  Frame, Line: TRect;
  Text: string;
  Action: TAtlasDebugBarAction;
  Right: Integer;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  // Fläche des Editors außen, die Leiste als Karte mit Akzentrahmen darin.
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  Frame := Rect(Scale(Padding div 2), Scale(1), ClientWidth - Scale(Padding div 2), ClientHeight - Scale(1));
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.RoundRect(Frame.Left, Frame.Top, Frame.Right, Frame.Bottom, Scale(8), Scale(8));
  Canvas.Brush.Style := bsClear;

  // Zeile 1: Klasse und Meldung, rechts der Zähler.
  Canvas.Font := Font;
  Right := Frame.Right - Scale(Gap);
  if FInfo.Count > 1 then
  begin
    Text := TAtlasStrings.Fmt(TAtlasTextId.DebugBannerCount, [FInfo.Count]);
    Canvas.Font.Color := ToColor(FColors.Warn);
    Line := Rect(Frame.Left, Frame.Top, Right, Frame.Top + RowHeight);
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Dec(Right, Canvas.TextWidth(Text) + Scale(Gap));
  end;
  Line := Rect(Frame.Left + Scale(Gap), Frame.Top, Right, Frame.Top + RowHeight);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Error);
  Text := FInfo.ExceptionClass;
  DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Inc(Line.Left, Canvas.TextWidth(Text));
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(FColors.Text);
  if FInfo.Message <> '' then
  begin
    Text := ': ' + FInfo.Message;
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;

  // Zeile 2: Thread, ausgeblendete Ebenen, erste eigene Zeile.
  Line := Rect(Frame.Left + Scale(Gap), Frame.Top + RowHeight, Frame.Right - Scale(Gap), Frame.Top + 2 * RowHeight);
  if FHot = TAtlasDebugBarAction.Open then
  begin
    Canvas.Font.Color := ToColor(FColors.Accent);
    Canvas.Font.Style := [fsUnderline];
  end
  else
    Canvas.Font.Color := ToColor(FColors.Muted);
  Text := DetailText;
  DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Font.Style := [];

  PaintExplanation(Frame);

  // Letzte Zeile: Knöpfe, rechts die Tastenhinweise.
  for Action in BarButtons do
    DrawButton(Action);
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(FColors.Muted);
  Canvas.Brush.Style := bsClear;
  Text := TAtlasStrings.Text(TAtlasTextId.DebugBannerKeys);
  Line := Rect(FRects[TAtlasDebugBarAction.Copy].Right + Scale(Gap), RowTop(Rows - 1), Frame.Right - Scale(Gap),
    Frame.Bottom);
  if Line.Width > Canvas.TextWidth(Text) then
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
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

procedure TAtlasDebugExceptionBar.PaintExplanation(const AFrame: TRect);
var
  Line: TRect;
  Text: string;
  Index, Row, Indent: Integer;
  Action: TAtlasDebugBarAction;
begin
  if not FExplanation.Active then
    Exit;
  // Trennlinie über der Erklärung.
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(AFrame.Left + Scale(Gap), RowTop(2) + Scale(1));
  Canvas.LineTo(AFrame.Right - Scale(Gap), RowTop(2) + Scale(1));
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Line := Rect(AFrame.Left + Scale(Gap), RowTop(2), AFrame.Right - Scale(Gap), RowTop(3));
  if FExplanation.Busy then
    Canvas.Font.Color := ToColor(FColors.Muted)
  else
  begin
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := MarkColor(FColors, FExplanation.HeadlineMark);
    if FExplanation.HeadlineMark = TAtlasDebugBannerMark.Neutral then
      Canvas.Font.Color := ToColor(FColors.Warn);
  end;
  Text := FExplanation.Headline;
  DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Inc(Line.Left, Canvas.TextWidth(Text));
  Canvas.Font.Style := [];
  if (FExplanation.Detail <> '') and not FExplanation.Busy then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    Text := ' ' + #$00B7 + ' ' + FExplanation.Detail;
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  if FExplanation.Busy then
    Exit;
  // Geprüfte Glieder, eingerückt, Zeichen in der Farbe des Zustands.
  Indent := Canvas.TextWidth(TAtlasDebugBannerLine.MarkText(TAtlasDebugBannerMark.Bad)) + Scale(Gap);
  Row := 3;
  for Index := 0 to ShownLines - 1 do
  begin
    Line := Rect(AFrame.Left + Scale(2 * Gap), RowTop(Row), AFrame.Right - Scale(Gap), RowTop(Row + 1));
    Canvas.Font.Color := MarkColor(FColors, FExplanation.Lines[Index].Mark);
    Text := TAtlasDebugBannerLine.MarkText(FExplanation.Lines[Index].Mark);
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Inc(Line.Left, Indent);
    Canvas.Font.Color := ToColor(FColors.Text);
    Text := FExplanation.Lines[Index].Text;
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Inc(Row);
  end;
  if Length(FExplanation.Lines) > MaxExplanationLines then
  begin
    Line := Rect(AFrame.Left + Scale(2 * Gap) + Indent, RowTop(Row), AFrame.Right - Scale(Gap), RowTop(Row + 1));
    Canvas.Font.Color := ToColor(FColors.Muted);
    Text := TAtlasStrings.Fmt(TAtlasTextId.DebugAvMore, [Length(FExplanation.Lines) - MaxExplanationLines]);
    DrawText(Canvas.Handle, PChar(Text), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
  for Action in ExplanationButtons do
    DrawButton(Action);
end;

procedure TAtlasDebugExceptionBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: TAtlasDebugBarAction;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := ActionAt(X, Y);
  if Hot = FHot then
    Exit;
  FHot := Hot;
  if Hot <> TAtlasDebugBarAction.None then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Application.CancelHint;
  if Hot = TAtlasDebugBarAction.Open then
    Hint := TAtlasStrings.Text(TAtlasTextId.DebugBannerOpenHint)
  else
    Hint := FInfo.Message;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FDown := TAtlasDebugBarAction.None;
  if FHot = TAtlasDebugBarAction.None then
    Exit;
  FHot := TAtlasDebugBarAction.None;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FDown := ActionAt(X, Y);
end;

procedure TAtlasDebugExceptionBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Action: TAtlasDebugBarAction;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Action := ActionAt(X, Y);
  if Action = FDown then
    Trigger(Action);
  FDown := TAtlasDebugBarAction.None;
end;

end.
