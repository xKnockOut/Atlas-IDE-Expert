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
    /// <summary>Zeile der Wahl AIndex bei AY; merkt die Flächen der Units und liefert das rechte Ende.</summary>
    function LayoutChoice(ADraw: Boolean; AIndex, AY, ATextHeight: Integer): Integer;
    /// <summary>Fußzeile „Übernehmen · Verwerfen“ bei AY; merkt beide Flächen und liefert das rechte Ende.</summary>
    function LayoutFooter(ADraw: Boolean; AY, ATextHeight: Integer): Integer;
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

/// <summary>Schreibt AText bei AX, AY in AColor (nur wenn ADraw) und rückt AX um seine Breite weiter.</summary>
procedure PutText(ACanvas: TCanvas; ADraw: Boolean; var AX: Integer; AY: Integer; const AText: string;
  AColor: TColor);
begin
  if ADraw then
  begin
    ACanvas.Font.Color := AColor;
    ACanvas.TextOut(AX, AY, AText);
  end;
  Inc(AX, ACanvas.TextWidth(AText));
end;

function TAtlasSmartPasteWindow.Layout(ADraw: Boolean): TSize;
var
  mX, mY, mTextHeight, mWidth, mIndex: Integer;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  mX := Scale(Pad);
  mY := Scale(Pad);
  Canvas.Font.Style := [fsBold];
  PutText(Canvas, ADraw, mX, mY, Title, ToColor(Colors.Text));
  mWidth := mX;
  Canvas.Font.Style := [];
  SetLength(FOptionRects, Length(FAnalysis.Choices));
  for mIndex := 0 to High(FAnalysis.Choices) do
  begin
    mY := mY + mTextHeight + Scale(RowGap);
    mWidth := Max(mWidth, LayoutChoice(ADraw, mIndex, mY, mTextHeight));
  end;
  // Fußzeile mit den beiden Links.
  mY := mY + mTextHeight + Scale(RowGap) * 2;
  mWidth := Max(mWidth, LayoutFooter(ADraw, mY, mTextHeight));
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(Pad);
  Result.cy := mY + mTextHeight + Scale(Pad);
end;

function TAtlasSmartPasteWindow.LayoutChoice(ADraw: Boolean; AIndex, AY, ATextHeight: Integer): Integer;
var
  mChoice: TAtlasPasteChoice;
  mText: string;
  mOption: Integer;
  mRects: TArray<TRect>;
begin
  mChoice := FAnalysis.Choices[AIndex];
  Result := Scale(Pad);
  mText := mChoice.Name + ':  ';
  if AIndex = FRow then
  begin
    mText := Marker + mText;
  end
  else
  begin
    Result := Result + Canvas.TextWidth(Marker);
  end;
  PutText(Canvas, ADraw, Result, AY, mText, ToColor(Colors.Muted));
  mRects := nil;
  for mOption := -1 to High(mChoice.Units) do
  begin
    mText := TAtlasStrings.Text(TAtlasTextId.SmartPasteNoUnit);
    if mOption >= 0 then
    begin
      PutText(Canvas, ADraw, Result, AY, Separator, ToColor(Colors.Muted));
      mText := mChoice.Units[mOption];
    end;
    if mOption = mChoice.Chosen then
    begin
      Canvas.Font.Style := [fsBold];
    end;
    mRects := mRects + [Rect(Result, AY, Result + Canvas.TextWidth(mText), AY + ATextHeight)];
    if mOption = mChoice.Chosen then
    begin
      PutText(Canvas, ADraw, Result, AY, mText, ToColor(Colors.Accent));
    end
    else
    begin
      PutText(Canvas, ADraw, Result, AY, mText, ToColor(Colors.Text));
    end;
    Canvas.Font.Style := [];
  end;
  FOptionRects[AIndex] := mRects;
end;

function TAtlasSmartPasteWindow.LayoutFooter(ADraw: Boolean; AY, ATextHeight: Integer): Integer;
var
  mAccept, mCancel: string;
begin
  mAccept := TAtlasStrings.Text(TAtlasTextId.SmartPasteAccept);
  mCancel := TAtlasStrings.Text(TAtlasTextId.SmartPasteCancel);
  Result := Scale(Pad);
  FAcceptRect := Rect(Result, AY, Result + Canvas.TextWidth(mAccept), AY + ATextHeight);
  PutText(Canvas, ADraw, Result, AY, mAccept, ToColor(Colors.Accent));
  PutText(Canvas, ADraw, Result, AY, Separator, ToColor(Colors.Muted));
  FCancelRect := Rect(Result, AY, Result + Canvas.TextWidth(mCancel), AY + ATextHeight);
  PutText(Canvas, ADraw, Result, AY, mCancel, ToColor(Colors.Accent));
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
