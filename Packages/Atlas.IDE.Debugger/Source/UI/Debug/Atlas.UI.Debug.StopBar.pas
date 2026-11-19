unit Atlas.UI.Debug.StopBar;

// Leiste nach einem Halt im Atlas-Stil (#410, #411), gemeinsam für „Beim
// nächsten Ereignis anhalten“ (#856) und „Anhalten bei Datenzugriff“ (#870):
//     Angehalten: btnSpeichern.OnClick → TfrmKunde.btnSpeichernClick
//     UPDATE Kunden SET Name = :Name WHERE ID = :ID        (wahlweise)
//     Weiter beobachten   Nur protokollieren   Beenden
// ohne Fokus; die Verweise sind Klickflächen und melden ihren Index.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.UI.Popup.Window;

type
  TAtlasStopBar = class(TAtlasPopupWindow)
  public const
    cGap = 4;
    /// <summary>Längere Zeilen unter der Überschrift kürzt die Leiste mit „…“.</summary>
    cMaxDetail = 160;
  private
    FHeading: string;
    FDetail: string;
    FLinks: TArray<string>;
    FRects: TArray<TRect>;
    FHot: Integer;
    FOnLink: TProc<Integer>;
    function Layout(ADraw: Boolean): TSize;
    function LinkAt(const APoint: TPoint): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt AHeading, darunter ADetail (leer = keine Zeile) und die Verweise ALinks unter APoint
    /// (Bildschirm).</summary>
    procedure ShowLinks(const AHeading, ADetail: string; const ALinks: TArray<string>; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>ABar zu, wenn es sie gibt und sie offen ist.</summary>
    class procedure Hide(ABar: TAtlasStopBar); static;
    /// <summary>Wie ein Klick auf den Verweis AIndex: Leiste zu, dann OnLink.</summary>
    procedure Choose(AIndex: Integer);
    function LinkRect(AIndex: Integer): TRect;
    /// <summary>ADetail auf eine Zeile gebracht und gekürzt.</summary>
    class function ShortDetail(const ADetail: string): string; static;
    property Heading: string read FHeading;
    property Detail: string read FDetail;
    property OnLink: TProc<Integer> read FOnLink write FOnLink;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard;

const
  cPad = 10;
  cButtonGap = 18;
  cEllipsis = '…';

{ TAtlasStopBar }

constructor TAtlasStopBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  FHot := -1;
end;

class function TAtlasStopBar.ShortDetail(const ADetail: string): string;
begin
  Result := Trim(ADetail.Replace(#13#10, ' ').Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' '));
  if Length(Result) > cMaxDetail then
  begin
    Result := Copy(Result, 1, cMaxDetail - 1) + cEllipsis;
  end;
end;

procedure TAtlasStopBar.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

function TAtlasStopBar.LinkAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRects) do
  begin
    if PtInRect(FRects[mIndex], APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasStopBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  mIndex := -1;
  if Button = mbLeft then
  begin
    mIndex := LinkAt(TPoint.Create(X, Y));
  end;
  if mIndex >= 0 then
  begin
    Choose(mIndex);
  end;
end;

procedure TAtlasStopBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: Integer;
begin
  inherited;
  mHot := LinkAt(TPoint.Create(X, Y));
  Cursor := crDefault;
  if mHot >= 0 then
  begin
    Cursor := crHandPoint;
  end;
  if mHot <> FHot then
  begin
    FHot := mHot;
    Invalidate;
  end;
end;

function TAtlasStopBar.Layout(ADraw: Boolean): TSize;
var
  X, Y, mTextHeight, mWidth, mIndex: Integer;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  X := Scale(cPad);
  Y := Scale(cPad);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, FHeading);
  end;
  mWidth := X + Canvas.TextWidth(FHeading);
  Canvas.Font.Style := [];
  if FDetail <> '' then
  begin
    Y := Y + mTextHeight + Scale(cGap);
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Text);
      Canvas.TextOut(X, Y, FDetail);
    end;
    mWidth := Max(mWidth, X + Canvas.TextWidth(FDetail));
  end;
  Y := Y + mTextHeight + Scale(cGap) * 2;
  SetLength(FRects, Length(FLinks));
  for mIndex := 0 to High(FLinks) do
  begin
    FRects[mIndex] := Rect(X, Y, X + Canvas.TextWidth(FLinks[mIndex]), Y + mTextHeight);
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Accent);
      if FHot = mIndex then
      begin
        Canvas.Font.Style := [fsUnderline];
      end;
      Canvas.TextOut(X, Y, FLinks[mIndex]);
      Canvas.Font.Style := [];
    end;
    mWidth := Max(mWidth, FRects[mIndex].Right);
    X := FRects[mIndex].Right + Scale(cButtonGap);
  end;
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(cPad);
  Result.cy := Y + mTextHeight + Scale(cPad);
end;

procedure TAtlasStopBar.ShowLinks(const AHeading, ADetail: string; const ALinks: TArray<string>;
  const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  FHeading := AHeading;
  FDetail := ShortDetail(ADetail);
  FLinks := Copy(ALinks);
  FHot := -1;
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mLeft := Max(mArea.Left, Min(APoint.X, mArea.Right - mSize.cx));
  mTop := APoint.Y + Scale(cGap);
  if mTop + mSize.cy > mArea.Bottom then
  begin
    mTop := APoint.Y - Scale(cGap) - mSize.cy;
  end;
  mTop := Max(mTop, mArea.Top);
  ShowAt(Rect(mLeft, mTop, mLeft + mSize.cx, mTop + mSize.cy));
  Announce(Trim(FHeading + ' ' + FDetail));
end;

procedure TAtlasStopBar.Dismiss;
begin
  HidePopup;
end;

class procedure TAtlasStopBar.Hide(ABar: TAtlasStopBar);
begin
  if (ABar <> nil) and ABar.IsShown then
  begin
    ABar.Dismiss;
  end;
end;

procedure TAtlasStopBar.Choose(AIndex: Integer);
begin
  Dismiss;
  if Assigned(FOnLink) then
  begin
    FOnLink(AIndex);
  end;
end;

function TAtlasStopBar.LinkRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRects)) then
  begin
    Result := FRects[AIndex];
  end;
end;

end.
