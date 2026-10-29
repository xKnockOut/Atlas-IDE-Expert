unit Atlas.UI.Debug.StepInto;

// Gezielt hineinspringen (#836), Fensterteil (nur VCL): Liste der Aufrufe an
// der Ausführungszeile im Atlas-Stil (#410, #411).
//   Gezielt hineinspringen
//   › 1  TKunde.GetName  Getter   Kunden.pas:27
//     2  Format                   ohne Quelltext
//     3  Pruefe                   Haupt.pas:51
//     4  Speichere                Haupt.pas:12
//   ↑/↓ und Enter oder 1–9 wählen  ·  Esc schließt
// Nicht wählbare Einträge (ohne Quelltext, Bibliothek ohne Debug-DCUs) stehen
// gedämpft mit Grund da. Die IDE-Seite leitet die Tasten weiter, das Fenster
// bekommt nie den Fokus; ein Klick auf einen Eintrag wählt ihn.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Debug.StepInto,
  Atlas.UI.Popup.Window;

type
  TAtlasStepIntoIndexEvent = reference to procedure(AIndex: Integer);

  TAtlasStepIntoWindow = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand unter der Zeile, logische Pixel.</summary>
    Gap = 4;
  private
    FRows: TArray<TAtlasStepRow>;
    FRow: Integer;
    FRowRects: TArray<TRect>;
    FOnAccept: TAtlasStepIntoIndexEvent;
    FOnCancel: TProc;
    function Layout(ADraw: Boolean): TSize;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>„Getter“, „Konstruktor“ … bzw. '' bei einem einfachen Aufruf.</summary>
    class function KindText(const ARow: TAtlasStepRow): string; static;
    /// <summary>Grund, warum ein Eintrag nicht wählbar ist; '' wenn er es ist.</summary>
    class function ReasonText(const ARow: TAtlasStepRow): string; static;
    /// <summary>„1  TKunde.GetName  Getter“ ohne Ort.</summary>
    class function RowCaption(const ARows: TArray<TAtlasStepRow>; AIndex: Integer): string; static;
    /// <summary>Zeigt ARows unter APoint (Bildschirm) und wählt den ersten wählbaren Eintrag.</summary>
    procedure ShowFor(const ARows: TArray<TAtlasStepRow>; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Nächster bzw. voriger wählbarer Eintrag; False ohne solche.</summary>
    function MoveRow(ADelta: Integer): Boolean;
    /// <summary>Ziffer 1–9: Eintrag wählen und übernehmen; False, wenn er nicht wählbar ist.</summary>
    function AcceptDigit(ADigit: Integer): Boolean;
    procedure Select(AIndex: Integer);
    function RowRect(AIndex: Integer): TRect;
    /// <summary>Gewählten Eintrag übernehmen (OnAccept); ohne Wahl nichts.</summary>
    procedure Accept;
    procedure Cancel;
    property Rows: TArray<TAtlasStepRow> read FRows;
    property Row: Integer read FRow;
    property OnAccept: TAtlasStepIntoIndexEvent read FOnAccept write FOnAccept;
    property OnCancel: TProc read FOnCancel write FOnCancel;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Accessibility;

const
  Pad = 10;
  RowGap = 4;
  ColumnGap = 16;
  Marker = '› ';

{ TAtlasStepIntoWindow }

constructor TAtlasStepIntoWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  FRow := -1;
  SetAccessible(UiaListControlType, TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
end;

class function TAtlasStepIntoWindow.KindText(const ARow: TAtlasStepRow): string;
begin
  case ARow.Kind of
    TAtlasStepKind.Getter:
      Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetGetter);
    TAtlasStepKind.Setter:
      Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetSetter);
    TAtlasStepKind.Constructor_:
      Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetConstructor);
    TAtlasStepKind.Inherited_:
      Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetInherited);
  else
    Result := '';
  end;
  if ARow.Candidate then
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCandidate);
  end;
end;

class function TAtlasStepIntoWindow.ReasonText(const ARow: TAtlasStepRow): string;
begin
  case ARow.Unavailable of
    TAtlasStepUnavailable.NoSource:
      Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetNoSource);
    TAtlasStepUnavailable.Library_:
      Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetLibrary);
  else
    Result := '';
  end;
end;

class function TAtlasStepIntoWindow.RowCaption(const ARows: TArray<TAtlasStepRow>; AIndex: Integer): string;
var
  Kind: string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(ARows)) then
    Exit;
  Result := ARows[AIndex].Caption;
  if AIndex < TAtlasStepInto.MaxDigit then
    Result := IntToStr(AIndex + 1) + '  ' + Result
  else
    Result := '   ' + Result;
  Kind := KindText(ARows[AIndex]);
  if Kind <> '' then
    Result := Result + '  (' + Kind + ')';
end;

function TAtlasStepIntoWindow.Layout(ADraw: Boolean): TSize;
var
  X, Y, TextHeight, Width, Index, NameWidth, RightX: Integer;
  Text, Right: string;
  Top: Integer;
begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  if ADraw then
    Canvas.Brush.Style := bsClear;
  X := Scale(Pad);
  Y := Scale(Pad);
  Text := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, Text);
  end;
  Width := X + Canvas.TextWidth(Text);
  Canvas.Font.Style := [];
  // Spalte für den Ort: hinter dem breitesten Namen.
  NameWidth := 0;
  for Index := 0 to High(FRows) do
    NameWidth := Max(NameWidth, Canvas.TextWidth(Marker + RowCaption(FRows, Index)));
  RightX := Scale(Pad) + NameWidth + Scale(ColumnGap);
  SetLength(FRowRects, Length(FRows));
  for Index := 0 to High(FRows) do
  begin
    Y := Y + TextHeight + Scale(RowGap);
    Top := Y;
    X := Scale(Pad);
    Text := RowCaption(FRows, Index);
    if Index = FRow then
      Text := Marker + Text
    else
      X := X + Canvas.TextWidth(Marker);
    if ADraw then
    begin
      if Index = FRow then
        Canvas.Font.Color := ToColor(Colors.Accent)
      else if FRows[Index].Available then
        Canvas.Font.Color := ToColor(Colors.Text)
      else
        Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(X, Y, Text);
    end;
    // Rechts: Datei:Zeile, bei nicht wählbaren der Grund.
    Right := ReasonText(FRows[Index]);
    if Right = '' then
      Right := FRows[Index].Location
    else if FRows[Index].Location <> '' then
      Right := Right + '  ·  ' + FRows[Index].Location;
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(RightX, Y, Right);
    end;
    Width := Max(Width, RightX + Canvas.TextWidth(Right));
    FRowRects[Index] := Rect(Scale(Pad), Top, RightX + Canvas.TextWidth(Right), Y + TextHeight);
  end;
  // Fußzeile mit den Tasten.
  Y := Y + TextHeight + Scale(RowGap) * 2;
  Text := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetFooter);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(Scale(Pad), Y, Text);
  end;
  Width := Max(Width, Scale(Pad) + Canvas.TextWidth(Text));
  if ADraw then
    Canvas.Brush.Style := bsSolid;
  Result.cx := Width + Scale(Pad);
  Result.cy := Y + TextHeight + Scale(Pad);
end;

procedure TAtlasStepIntoWindow.ShowFor(const ARows: TArray<TAtlasStepRow>; const APoint: TPoint);
var
  Size: TSize;
  Area: TRect;
  Left, Top: Integer;
begin
  FRows := ARows;
  FRow := TAtlasStepInto.NextAvailable(FRows, 0, 1);
  HandleNeeded;
  Size := Layout(False);
  Area := WorkAreaAt(APoint);
  Left := Min(APoint.X, Area.Right - Size.cx);
  Top := APoint.Y + Scale(Gap);
  if Top + Size.cy > Area.Bottom then
    Top := APoint.Y - Scale(Gap) - Size.cy;
  ShowAt(Rect(Max(Left, Area.Left), Max(Top, Area.Top), Max(Left, Area.Left) + Size.cx,
    Max(Top, Area.Top) + Size.cy));
  Announce(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
  if FRow >= 0 then
    Announce(RowCaption(FRows, FRow));
end;

procedure TAtlasStepIntoWindow.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasStepIntoWindow.Select(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or not FRows[AIndex].Available or (AIndex = FRow) then
    Exit;
  FRow := AIndex;
  Invalidate;
  Announce(RowCaption(FRows, FRow));
end;

function TAtlasStepIntoWindow.MoveRow(ADelta: Integer): Boolean;
var
  Next: Integer;
begin
  Next := TAtlasStepInto.NextAvailable(FRows, FRow + ADelta, ADelta);
  Result := Next >= 0;
  if Result then
    Select(Next);
end;

function TAtlasStepIntoWindow.AcceptDigit(ADigit: Integer): Boolean;
var
  Index: Integer;
begin
  Index := TAtlasStepInto.DigitRow(FRows, ADigit);
  Result := Index >= 0;
  if not Result then
    Exit;
  Select(Index);
  Accept;
end;

function TAtlasStepIntoWindow.RowRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRowRects)) then
    Result := FRowRects[AIndex];
end;

procedure TAtlasStepIntoWindow.Accept;
var
  Chosen: Integer;
begin
  Chosen := FRow;
  if (Chosen < 0) or (Chosen > High(FRows)) or not FRows[Chosen].Available then
    Exit;
  Dismiss;
  if Assigned(FOnAccept) then
    FOnAccept(Chosen);
end;

procedure TAtlasStepIntoWindow.Cancel;
begin
  Dismiss;
  if Assigned(FOnCancel) then
    FOnCancel();
end;

procedure TAtlasStepIntoWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasStepIntoWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Point: TPoint;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Point := TPoint.Create(X, Y);
  for Index := 0 to High(FRowRects) do
    if PtInRect(FRowRects[Index], Point) and FRows[Index].Available then
    begin
      Select(Index);
      Accept;
      Exit;
    end;
end;

procedure TAtlasStepIntoWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Hot: Boolean;
  Point: TPoint;
begin
  inherited;
  Point := TPoint.Create(X, Y);
  Hot := False;
  for Index := 0 to High(FRowRects) do
    if PtInRect(FRowRects[Index], Point) and FRows[Index].Available then
    begin
      Hot := True;
      Select(Index);
    end;
  if Hot then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

end.
