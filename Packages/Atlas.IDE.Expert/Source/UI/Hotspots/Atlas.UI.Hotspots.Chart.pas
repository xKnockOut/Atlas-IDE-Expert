unit Atlas.UI.Hotspots.Chart;

// Blasendiagramm des Fensters „Atlas-Hotspots“ (#1354), reine VCL: x =
// Änderungen im Zeitraum, y = kognitive Komplexität, Größe nach Zeilen, Farbe
// nach Wert (grün → rot wie im HTML-Bericht). Lage und Treffer rechnet
// TAtlasHotspotChart im Kern (getestet). Der Mauszeiger über einer Blase
// zeigt Name und Zahlen als Hinweis, Klick wählt die Zeile (OnSelect),
// Doppelklick oder Enter springt (OnOpen), Rechtsklick wählt und öffnet das
// Kontextmenü (PopupMenu des Frames). Farben der Fläche aus dem IDE-Thema.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Hotspots.Model;

type
  TAtlasHotspotChartView = class(TCustomControl)
  private
    FEntries: TArray<TAtlasHotspotEntry>;
    FShown: TArray<Integer>;
    FBubbles: TArray<TAtlasHotspotBubble>;
    FSelected: Integer;
    FHover: Integer;
    FEmptyText: string;
    FOnSelect: TProc<Integer>;
    FOnOpen: TProc<Integer>;
    function Scale: Double;
    procedure Relayout;
    procedure SelectAt(X, Y: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeilen AEntries, gezeigt werden die Nummern AShown (Reihenfolge der Rangliste).</summary>
    procedure SetEntries(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>);
    /// <summary>Zeile wählen (-1 = keine), ohne OnSelect.</summary>
    procedure SelectEntry(AEntry: Integer);
    /// <summary>Hinweis der Blase (Name und Zahlen).</summary>
    function BubbleText(AEntry: Integer): string;
    property Bubbles: TArray<TAtlasHotspotBubble> read FBubbles;
    property Selected: Integer read FSelected;
    /// <summary>Text mitten in der Fläche, solange keine Blase da ist.</summary>
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnSelect: TProc<Integer> read FOnSelect write FOnSelect;
    property OnOpen: TProc<Integer> read FOnOpen write FOnOpen;
    property PopupMenu;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings;

const
  /// <summary>Teilstriche je Achse.</summary>
  cTicks = 4;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasHotspotChartView }

constructor TAtlasHotspotChartView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  ShowHint := True;
  FSelected := -1;
  FHover := -1;
  Width := 400;
  Height := 220;
end;

function TAtlasHotspotChartView.Scale: Double;
begin
  Result := CurrentPPI / 96;
end;

procedure TAtlasHotspotChartView.Relayout;
begin
  FBubbles := TAtlasHotspotChart.Layout(FEntries, FShown, ClientWidth, ClientHeight, Scale);
end;

procedure TAtlasHotspotChartView.SetEntries(const AEntries: TArray<TAtlasHotspotEntry>;
  const AShown: TArray<Integer>);
begin
  FEntries := AEntries;
  FShown := AShown;
  FHover := -1;
  if (FSelected < 0) or (FSelected > High(FEntries)) then
    FSelected := -1;
  Hint := '';
  Relayout;
  Invalidate;
end;

procedure TAtlasHotspotChartView.SelectEntry(AEntry: Integer);
begin
  if (AEntry < 0) or (AEntry > High(FEntries)) then
    AEntry := -1;
  if AEntry = FSelected then
    Exit;
  FSelected := AEntry;
  Invalidate;
end;

function TAtlasHotspotChartView.BubbleText(AEntry: Integer): string;
var
  mEntry: TAtlasHotspotEntry;
begin
  Result := '';
  if (AEntry < 0) or (AEntry > High(FEntries)) then
    Exit;
  mEntry := FEntries[AEntry];
  Result := TAtlasStrings.Fmt(TAtlasTextId.HotspotsBubbleHint, [mEntry.Caption, mEntry.Changes, mEntry.Complexity,
    mEntry.Lines, FormatFloat('0.00', mEntry.Score)]);
end;

procedure TAtlasHotspotChartView.Resize;
begin
  inherited Resize;
  Relayout;
  Invalidate;
end;

procedure TAtlasHotspotChartView.Paint;
var
  mColors: TAtlasColors;
  mLeft, mBottom, mTop, mRight, mTick, mX, mY, mMaxChanges, mMaxComplexity: Integer;
  mBubble: TAtlasHotspotBubble;
  mCaption: string;
  mSize: TSize;
begin
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(mColors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(mColors.Muted);
  if Length(FBubbles) = 0 then
  begin
    mSize := Canvas.TextExtent(FEmptyText);
    Canvas.TextOut((ClientWidth - mSize.cx) div 2, (ClientHeight - mSize.cy) div 2, FEmptyText);
    Exit;
  end;
  mLeft := Round(TAtlasHotspotChart.MarginLeft * Scale);
  mBottom := ClientHeight - Round(TAtlasHotspotChart.MarginBottom * Scale);
  mTop := Round(TAtlasHotspotChart.MarginTop * Scale);
  mRight := ClientWidth - Round(TAtlasHotspotChart.MarginRight * Scale);
  TAtlasHotspotChart.Extent(FEntries, FShown, mMaxChanges, mMaxComplexity);
  // Achsen mit Teilstrichen und Beschriftung.
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := ToColor(mColors.Line);
  Canvas.MoveTo(mLeft, mTop);
  Canvas.LineTo(mLeft, mBottom);
  Canvas.LineTo(mRight, mBottom);
  Canvas.Brush.Style := bsClear;
  for mTick := 0 to cTicks do
  begin
    mX := mLeft + (mRight - mLeft) * mTick div cTicks;
    mCaption := IntToStr(Round(mMaxChanges * mTick / cTicks));
    mSize := Canvas.TextExtent(mCaption);
    Canvas.TextOut(mX - mSize.cx div 2, mBottom + 2, mCaption);
    mY := mBottom - (mBottom - mTop) * mTick div cTicks;
    mCaption := IntToStr(Round(mMaxComplexity * mTick / cTicks));
    mSize := Canvas.TextExtent(mCaption);
    Canvas.TextOut(mLeft - mSize.cx - 4, mY - mSize.cy div 2, mCaption);
  end;
  mCaption := TAtlasStrings.Text(TAtlasTextId.HotspotsColChanges);
  mSize := Canvas.TextExtent(mCaption);
  Canvas.TextOut(mRight - mSize.cx, mBottom - mSize.cy - 2, mCaption);
  Canvas.TextOut(mLeft + 4, mTop, TAtlasStrings.Text(TAtlasTextId.HotspotsColComplexity));
  // Blasen: größte zuerst, damit kleine sichtbar bleiben; gewählte und überfahrene mit Rahmen.
  Canvas.Brush.Style := bsSolid;
  for mBubble in FBubbles do
  begin
    Canvas.Brush.Color := ToColor(TAtlasColorMath.Mix(TAtlasColor(TAtlasHotspotChart.ScoreColor(
      FEntries[mBubble.Entry].Score)), mColors.Surface, 0.75));
    if (mBubble.Entry = FSelected) or (mBubble.Entry = FHover) then
    begin
      Canvas.Pen.Color := ToColor(mColors.Accent);
      Canvas.Pen.Width := Max(2, Round(2 * Scale));
    end
    else
    begin
      Canvas.Pen.Color := ToColor(mColors.Surface);
      Canvas.Pen.Width := 1;
    end;
    Canvas.Ellipse(mBubble.X - mBubble.Radius, mBubble.Y - mBubble.Radius, mBubble.X + mBubble.Radius + 1,
      mBubble.Y + mBubble.Radius + 1);
  end;
  Canvas.Pen.Width := 1;
  // Name der gewählten Blase daneben.
  for mBubble in FBubbles do
    if mBubble.Entry = FSelected then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(mColors.Text);
      Canvas.TextOut(mBubble.X + mBubble.Radius + 3, mBubble.Y - Canvas.TextHeight('Ag') div 2,
        FEntries[mBubble.Entry].Caption);
    end;
end;

procedure TAtlasHotspotChartView.SelectAt(X, Y: Integer);
var
  mHit: Integer;
begin
  mHit := TAtlasHotspotChart.HitTest(FBubbles, X, Y);
  SelectEntry(mHit);
  if Assigned(FOnSelect) then
    FOnSelect(mHit);
end;

procedure TAtlasHotspotChartView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus and Showing then
    SetFocus;
  // Rechtsklick wählt die Blase, bevor das Kontextmenü aufgeht.
  if Button in [mbLeft, mbRight] then
    SelectAt(X, Y);
end;

procedure TAtlasHotspotChartView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHit: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  mHit := TAtlasHotspotChart.HitTest(FBubbles, X, Y);
  if mHit = FHover then
    Exit;
  FHover := mHit;
  Hint := BubbleText(mHit);
  Application.CancelHint;
  Invalidate;
end;

procedure TAtlasHotspotChartView.DblClick;
begin
  inherited DblClick;
  if (FSelected >= 0) and Assigned(FOnOpen) then
    FOnOpen(FSelected);
end;

procedure TAtlasHotspotChartView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key = VK_RETURN) and (FSelected >= 0) and Assigned(FOnOpen) then
  begin
    FOnOpen(FSelected);
    Key := 0;
  end;
end;

end.
