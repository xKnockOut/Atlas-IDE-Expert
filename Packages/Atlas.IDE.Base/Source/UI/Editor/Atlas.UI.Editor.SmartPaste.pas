unit Atlas.UI.Editor.SmartPaste;

// Einfügen mit uses-Ergänzung (#515), Fensterteil (nur VCL): kleines, nicht
// modales Fenster an der Einfügestelle.
//   3 Units ergänzen: Data.DB, System.JSON, …
//   › TList:  keine · System.Classes · System.Generics.Collections
//   Übernehmen (Enter) · Verwerfen (Esc)
// Mehrdeutige Bezeichner stehen je in einer Zeile; gewählt ist zuerst
// „keine“. ↑/↓ wechseln die Zeile, ←/→ die Unit (die IDE-Seite leitet die
// Tasten weiter, das Fenster bekommt nie den Fokus), ein Klick wählt direkt.
// Die Überschrift zählt eindeutige und gewählte Units.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Editor.SmartPaste,
  Atlas.UI.Popup.Window;

type
  TAtlasSmartPasteWindow = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand unter der Einfügestelle, logische Pixel.</summary>
    Gap = 4;
  private
    FAnalysis: TAtlasPasteAnalysis;
    FRow: Integer;
    FOptionRects: TArray<TArray<TRect>>;
    FAcceptRect: TRect;
    FCancelRect: TRect;
    FOnAccept: TProc;
    FOnCancel: TProc;
    function Layout(ADraw: Boolean): TSize;
    function Title: string;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt AAnalysis unter APoint (Bildschirm).</summary>
    procedure ShowFor(const AAnalysis: TAtlasPasteAnalysis; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Nächste bzw. vorige Zeile mit Auswahl; False ohne Auswahlzeilen.</summary>
    function MoveRow(ADelta: Integer): Boolean;
    /// <summary>Nächste bzw. vorige Unit der aktuellen Zeile (keine, dann die Units); False ohne
    /// Auswahlzeilen.</summary>
    function MoveChoice(ADelta: Integer): Boolean;
    /// <summary>In Zeile ARow die Unit AOption wählen (-1 = keine).</summary>
    procedure Choose(ARow, AOption: Integer);
    /// <summary>Fläche der Wahl AOption (-1 = keine) in Zeile ARow; leer, wenn es sie nicht gibt.</summary>
    function OptionRect(ARow, AOption: Integer): TRect;
    procedure Accept;
    procedure Cancel;
    function AcceptRect: TRect;
    property Analysis: TAtlasPasteAnalysis read FAnalysis;
    property Row: Integer read FRow;
    property Caption: string read Title;
    property OnAccept: TProc read FOnAccept write FOnAccept;
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
  Separator = '  ·  ';
  Marker = '› ';

{ TAtlasSmartPasteWindow }

constructor TAtlasSmartPasteWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.SmartPaste;
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.SmartPasteName));
end;

function TAtlasSmartPasteWindow.Title: string;
var
  Units: TArray<string>;
begin
  Units := TAtlasSmartPaste.Selected(FAnalysis);
  if Length(Units) = 0 then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SmartPasteNone);
  end
  else if Length(Units) = 1 then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SmartPasteOne, [Units[0]]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SmartPasteTitle, [Length(Units), TAtlasSmartPaste.Named(Units)]);
  end;
end;

function TAtlasSmartPasteWindow.Layout(ADraw: Boolean): TSize;
var
  X, Y, TextHeight, mWidth, Index, Option: Integer;
  mText, Accept, Cancel: string;
  Choice: TAtlasPasteChoice;
  Rects: TArray<TRect>;
begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  X := Scale(Pad);
  Y := Scale(Pad);
  mText := Title;
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, mText);
  end;
  mWidth := X + Canvas.TextWidth(mText);
  Canvas.Font.Style := [];
  SetLength(FOptionRects, Length(FAnalysis.Choices));
  for Index := 0 to High(FAnalysis.Choices) do
  begin
    Choice := FAnalysis.Choices[Index];
    Y := Y + TextHeight + Scale(RowGap);
    X := Scale(Pad);
    mText := Choice.Name + ':  ';
    if Index = FRow then
    begin
      mText := Marker + mText;
    end
    else
    begin
      X := X + Canvas.TextWidth(Marker);
    end;
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(X, Y, mText);
    end;
    Inc(X, Canvas.TextWidth(mText));
    Rects := nil;
    for Option := -1 to High(Choice.Units) do
    begin
      if Option >= 0 then
      begin
        if ADraw then
        begin
          Canvas.Font.Color := ToColor(Colors.Muted);
          Canvas.TextOut(X, Y, Separator);
        end;
        Inc(X, Canvas.TextWidth(Separator));
        mText := Choice.Units[Option];
      end
      else
      begin
        mText := TAtlasStrings.Text(TAtlasTextId.SmartPasteNoUnit);
      end;
      if Option = Choice.Chosen then
      begin
        Canvas.Font.Style := [fsBold];
      end;
      Rects := Rects + [Rect(X, Y, X + Canvas.TextWidth(mText), Y + TextHeight)];
      if ADraw then
      begin
        if Option = Choice.Chosen then
        begin
          Canvas.Font.Color := ToColor(Colors.Accent);
        end
        else
        begin
          Canvas.Font.Color := ToColor(Colors.Text);
        end;
        Canvas.TextOut(X, Y, mText);
      end;
      Inc(X, Canvas.TextWidth(mText));
      Canvas.Font.Style := [];
    end;
    FOptionRects[Index] := Rects;
    mWidth := Max(mWidth, X);
  end;
  // Fußzeile mit den beiden Links.
  Y := Y + TextHeight + Scale(RowGap) * 2;
  X := Scale(Pad);
  Accept := TAtlasStrings.Text(TAtlasTextId.SmartPasteAccept);
  Cancel := TAtlasStrings.Text(TAtlasTextId.SmartPasteCancel);
  FAcceptRect := Rect(X, Y, X + Canvas.TextWidth(Accept), Y + TextHeight);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.TextOut(X, Y, Accept);
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(FAcceptRect.Right, Y, Separator);
  end;
  X := FAcceptRect.Right + Canvas.TextWidth(Separator);
  FCancelRect := Rect(X, Y, X + Canvas.TextWidth(Cancel), Y + TextHeight);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.TextOut(X, Y, Cancel);
  end;
  mWidth := Max(mWidth, FCancelRect.Right);
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(Pad);
  Result.cy := Y + TextHeight + Scale(Pad);
end;

procedure TAtlasSmartPasteWindow.ShowFor(const AAnalysis: TAtlasPasteAnalysis; const APoint: TPoint);
var
  Size: TSize;
  Area: TRect;
  mLeft, mTop: Integer;
begin
  FAnalysis := AAnalysis;
  FRow := 0;
  if Length(FAnalysis.Choices) = 0 then
  begin
    FRow := -1;
  end;
  HandleNeeded;
  Size := Layout(False);
  Area := WorkAreaAt(APoint);
  mLeft := Min(APoint.X, Area.Right - Size.cx);
  mTop := APoint.Y + Scale(Gap);
  if mTop + Size.cy > Area.Bottom then
  begin
    mTop := APoint.Y - Scale(Gap) - Size.cy;
  end;
  ShowAt(Rect(Max(mLeft, Area.Left), Max(mTop, Area.Top), Max(mLeft, Area.Left) + Size.cx,
    Max(mTop, Area.Top) + Size.cy));
  Announce(Title);
end;

procedure TAtlasSmartPasteWindow.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasSmartPasteWindow.Choose(ARow, AOption: Integer);
begin
  if (ARow < 0) or (ARow > High(FAnalysis.Choices)) or (AOption < -1) or
    (AOption > High(FAnalysis.Choices[ARow].Units)) then
  begin
    Exit;
  end;
  FRow := ARow;
  FAnalysis.Choices[ARow].Chosen := AOption;
  if IsShown then
  begin
    // Die Überschrift ändert ihre Länge: neu ausmessen.
    ShowFor(FAnalysis, BoundsRect.TopLeft - Point(0, Scale(Gap)));
    FRow := ARow;
    Invalidate;
  end;
end;

function TAtlasSmartPasteWindow.MoveRow(ADelta: Integer): Boolean;
var
  Count: Integer;
begin
  Count := Length(FAnalysis.Choices);
  Result := Count > 0;
  if not Result then
  begin
    Exit;
  end;
  FRow := ((FRow + ADelta) mod Count + Count) mod Count;
  Invalidate;
end;

function TAtlasSmartPasteWindow.MoveChoice(ADelta: Integer): Boolean;
var
  Count, Option: Integer;
begin
  Result := (FRow >= 0) and (FRow <= High(FAnalysis.Choices));
  if not Result then
  begin
    Exit;
  end;
  // Wahl -1 (keine) bis High(Units), ringsum.
  Count := Length(FAnalysis.Choices[FRow].Units) + 1;
  Option := ((FAnalysis.Choices[FRow].Chosen + 1 + ADelta) mod Count + Count) mod Count - 1;
  Choose(FRow, Option);
end;

function TAtlasSmartPasteWindow.OptionRect(ARow, AOption: Integer): TRect;
begin
  Result := TRect.Empty;
  if (ARow >= 0) and (ARow <= High(FOptionRects)) and (AOption + 1 >= 0) and
    (AOption + 1 <= High(FOptionRects[ARow])) then
  begin
    Result := FOptionRects[ARow][AOption + 1];
  end;
end;

function TAtlasSmartPasteWindow.AcceptRect: TRect;
begin
  Result := FAcceptRect;
end;

procedure TAtlasSmartPasteWindow.Accept;
begin
  Dismiss;
  if Assigned(FOnAccept) then
  begin
    FOnAccept();
  end;
end;

procedure TAtlasSmartPasteWindow.Cancel;
begin
  Dismiss;
  if Assigned(FOnCancel) then
  begin
    FOnCancel();
  end;
end;

procedure TAtlasSmartPasteWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasSmartPasteWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index, Option: Integer;
  Point: TPoint;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  Point := TPoint.Create(X, Y);
  if PtInRect(FAcceptRect, Point) then
  begin
    Accept;
    Exit;
  end;
  if PtInRect(FCancelRect, Point) then
  begin
    Cancel;
    Exit;
  end;
  for Index := 0 to High(FOptionRects) do
  begin
    for Option := 0 to High(FOptionRects[Index]) do
    begin
      if PtInRect(FOptionRects[Index][Option], Point) then
      begin
        Choose(Index, Option - 1);
        Exit;
      end;
    end;
  end;
end;

procedure TAtlasSmartPasteWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Index, Option: Integer;
  Hot: Boolean;
  Point: TPoint;
begin
  inherited;
  Point := TPoint.Create(X, Y);
  Hot := PtInRect(FAcceptRect, Point) or PtInRect(FCancelRect, Point);
  for Index := 0 to High(FOptionRects) do
  begin
    for Option := 0 to High(FOptionRects[Index]) do
    begin
      if PtInRect(FOptionRects[Index][Option], Point) then
      begin
        Hot := True;
      end;
    end;
  end;
  if Hot then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

end.
