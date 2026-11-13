unit Atlas.UI.Debug.NoSourcePopup;

// Fenster „Kein Quelltext“ (#869), Fensterteil (nur VCL), im Atlas-Stil
// (#410, #411), ohne Fokus:
//     Kein Quelltext: System.SysUtils.FormatFloat
//     Modul rtl290.bpl · Adresse 0040A1B2 · Unit System.SysUtils
//     Debug-DCUs aus: Die Bibliothek von Delphi ist ohne Zeilennummern übersetzt.
//     Debug-DCUs einschalten und neu bauen
//     Zurück zum eigenen Code
//     CPU-Fenster behalten
//     Für diese Unit nicht mehr zeigen
// Die Auswege sind Klickflächen; OnWay bzw. OnIgnore melden den Klick.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Debug.NoSource,
  Atlas.UI.Popup.Window;

type
  TAtlasNoSourceWayEvent = reference to procedure(AWay: TAtlasNoSourceWay);

  TAtlasNoSourcePopup = class(TAtlasPopupWindow)
  public const
    cGap = 4;
    cPad = 10;
    /// <summary>Index der Klickfläche „Für diese Unit nicht mehr zeigen“ hinter den Auswegen.</summary>
    cIgnoreLink = Ord(High(TAtlasNoSourceWay)) + 1;
  private
    FTitle: string;
    FPlace: string;
    FReason: string;
    FWays: TAtlasNoSourceWays;
    FCanIgnore: Boolean;
    FLinks: array[0..cIgnoreLink] of TRect;
    FHot: Integer;
    FOnWay: TAtlasNoSourceWayEvent;
    FOnIgnore: TProc;
    function Layout(ADraw: Boolean): TSize;
    function LinkAt(const APoint: TPoint): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    class function WayText(AWay: TAtlasNoSourceWay): string; static;
    class function ReasonText(AReason: TAtlasNoSourceReason): string; static;
    /// <summary>Zeigt das Fenster mit der rechten oberen Ecke an APoint (Bildschirm).</summary>
    procedure ShowFor(const ATitle, APlace, AReason: string; AWays: TAtlasNoSourceWays; ACanIgnore: Boolean;
      const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Wie ein Klick auf Klickfläche AIndex (Ord des Auswegs bzw. cIgnoreLink).</summary>
    procedure Choose(AIndex: Integer);
    function LinkRect(AIndex: Integer): TRect;
    property Title: string read FTitle;
    property Reason: string read FReason;
    property Ways: TAtlasNoSourceWays read FWays;
    property OnWay: TAtlasNoSourceWayEvent read FOnWay write FOnWay;
    property OnIgnore: TProc read FOnIgnore write FOnIgnore;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Popup.Accessibility;

{ TAtlasNoSourcePopup }

constructor TAtlasNoSourcePopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  FHot := -1;
  SetAccessible(cUiaToolTipControlType, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceTitle, ['']));
end;

class function TAtlasNoSourcePopup.WayText(AWay: TAtlasNoSourceWay): string;
begin
  case AWay of
    TAtlasNoSourceWay.EnableDebugDcus:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceEnableDcus);
    TAtlasNoSourceWay.ReturnToOwnCode:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceReturn);
    TAtlasNoSourceWay.FindSource:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceFind);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceKeepCpu);
  end;
end;

class function TAtlasNoSourcePopup.ReasonText(AReason: TAtlasNoSourceReason): string;
begin
  case AReason of
    TAtlasNoSourceReason.DebugDcusOff:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceDebugDcusOff);
    TAtlasNoSourceReason.NoDebugInfo:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceNoDebugInfo);
    TAtlasNoSourceReason.DcuOnly:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceDcuOnly);
    TAtlasNoSourceReason.NotInSearchPath:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceNotInPath);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceSystem);
  end;
end;

function TAtlasNoSourcePopup.Layout(ADraw: Boolean): TSize;
var
  X, Y, mTextHeight, mWidth: Integer;
  mWay: TAtlasNoSourceWay;

  procedure Line(const AText: string; AColor: TColor; AStyle: TFontStyles);
  begin
    Canvas.Font.Style := AStyle;
    if ADraw then
    begin
      Canvas.Font.Color := AColor;
      Canvas.TextOut(X, Y, AText);
    end;
    mWidth := Max(mWidth, X + Canvas.TextWidth(AText));
    Canvas.Font.Style := [];
    Y := Y + mTextHeight + Scale(cGap);
  end;

  procedure Link(const ACaption: string; AIndex: Integer);
  var
    mStyle: TFontStyles;
  begin
    FLinks[AIndex] := Rect(X, Y, X + Canvas.TextWidth(ACaption), Y + mTextHeight);
    mStyle := [];
    if FHot = AIndex then
    begin
      mStyle := [fsUnderline];
    end;
    Line(ACaption, ToColor(Colors.Accent), mStyle);
  end;

begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  FillChar(FLinks, SizeOf(FLinks), 0);
  X := Scale(cPad);
  Y := Scale(cPad);
  mWidth := 0;
  Line(FTitle, ToColor(Colors.Text), [fsBold]);
  Line(FPlace, ToColor(Colors.Muted), []);
  Line(FReason, ToColor(Colors.Text), []);
  Y := Y + Scale(cGap);
  for mWay := Low(TAtlasNoSourceWay) to High(TAtlasNoSourceWay) do
  begin
    if mWay in FWays then
    begin
      Link(WayText(mWay), Ord(mWay));
    end;
  end;
  if FCanIgnore then
  begin
    Link(TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceIgnore), cIgnoreLink);
  end;
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(cPad);
  Result.cy := Y - Scale(cGap) + Scale(cPad);
end;

procedure TAtlasNoSourcePopup.ShowFor(const ATitle, APlace, AReason: string; AWays: TAtlasNoSourceWays;
  ACanIgnore: Boolean; const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  FTitle := ATitle;
  FPlace := APlace;
  FReason := AReason;
  FWays := AWays;
  FCanIgnore := ACanIgnore;
  FHot := -1;
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mLeft := Max(mArea.Left, Min(APoint.X - mSize.cx, mArea.Right - mSize.cx));
  mTop := Max(mArea.Top, Min(APoint.Y, mArea.Bottom - mSize.cy));
  ShowAt(Rect(mLeft, mTop, mLeft + mSize.cx, mTop + mSize.cy));
  Announce(FTitle + '. ' + FReason);
end;

procedure TAtlasNoSourcePopup.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasNoSourcePopup.Choose(AIndex: Integer);
begin
  Dismiss;
  if AIndex = cIgnoreLink then
  begin
    if Assigned(FOnIgnore) then
    begin
      FOnIgnore();
    end;
  end
  else if (AIndex >= Ord(Low(TAtlasNoSourceWay))) and (AIndex <= Ord(High(TAtlasNoSourceWay))) and
    Assigned(FOnWay) then
  begin
    FOnWay(TAtlasNoSourceWay(AIndex));
  end;
end;

function TAtlasNoSourcePopup.LinkRect(AIndex: Integer): TRect;
begin
  Result := FLinks[AIndex];
end;

function TAtlasNoSourcePopup.LinkAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := Low(FLinks) to High(FLinks) do
  begin
    if not FLinks[mIndex].IsEmpty and PtInRect(FLinks[mIndex], APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasNoSourcePopup.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasNoSourcePopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mIndex := LinkAt(TPoint.Create(X, Y));
  if mIndex >= 0 then
  begin
    Choose(mIndex);
  end;
end;

procedure TAtlasNoSourcePopup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: Integer;
begin
  inherited;
  mHot := LinkAt(TPoint.Create(X, Y));
  if mHot >= 0 then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if mHot <> FHot then
  begin
    FHot := mHot;
    Invalidate;
  end;
end;

end.
