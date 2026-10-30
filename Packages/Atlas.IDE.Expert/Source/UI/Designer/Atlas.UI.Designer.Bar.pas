unit Atlas.UI.Designer.Bar;

// Designer-Leiste (#1442), Darstellung: eine Zeile mit 16-px-Symbolen über dem
// Formular-Designer an Stelle von Brotkrumen und Editorleiste, im Stil der
// Editorleiste (#1101). Die Knöpfe setzt der Aufrufer (SetButtons):
// Komponenten suchen, Nichtvisuelle (Strg+H der IDE), Elternelement,
// Tab-Reihenfolge, Ausrichten.
// - Gedrückt (Pressed): Akzentfläche wie der aktuelle Abschnitt der
//   Editorleiste (Nichtvisuelle ausgeblendet, Tab-Reihenfolge an).
// - Knopf mit Menü (Menu): rechts ein kleiner Pfeil. Ein Klick auf den Pfeil
//   meldet OnMenu mit dem Bildschirmpunkt unter dem Knopf, ein Klick auf das
//   Symbol OnCommand (Ausrichten wiederholt den letzten Befehl).
// - Tooltip je Knopf: Name und Taste.
// Höhe, Farben, Hervorhebung, Klick beim Loslassen, Kontextmenü (geht nie an
// den Editor) und OnDisabled kommen vom Vorfahr TAtlasEditorBar (#1248).
// Reine VCL; was die Knöpfe tun, entscheidet Atlas.IDE.Designer.Bar.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Editor.Bar;

type
  TAtlasDesignerButton = record
    Id: string;
    Icon: TAtlasToolbarIcon;
    /// <summary>Tooltip: Name und Taste.</summary>
    Hint: string;
    Enabled: Boolean;
    Pressed: Boolean;
    /// <summary>Mit Pfeil für ein Menü.</summary>
    Menu: Boolean;
    /// <summary>Trennstrich davor.</summary>
    GapBefore: Boolean;
    class function Create(const AId: string; AIcon: TAtlasToolbarIcon; const AHint: string): TAtlasDesignerButton;
      static;
    function SameAs(const AOther: TAtlasDesignerButton): Boolean;
  end;

  TAtlasDesignerBar = class(TAtlasEditorBar)
  private
    FButtons: TArray<TAtlasDesignerButton>;
    FRects: TArray<TRect>;
    FArrows: TArray<TRect>;
    FOnCommand: TProc<string>;
    FOnMenu: TProc<string, TPoint>;
    procedure Layout;
    function IconSize: Integer;
    /// <summary>Teil APart: Knopf 2·i, sein Pfeil 2·i + 1.</summary>
    function ButtonOf(APart: Integer): Integer;
    procedure DrawButton(AIndex: Integer);
  protected
    class function BaseHeight: Integer; override;
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    function PartEnabled(APart: Integer): Boolean; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Knöpfe setzen; gleiche Knöpfe zeichnen nicht neu.</summary>
    procedure SetButtons(const AButtons: TArray<TAtlasDesignerButton>);
    /// <summary>Fläche des Knopfs AId (Client, ohne Pfeil); leer ohne ihn.</summary>
    function ButtonRect(const AId: string): TRect;
    /// <summary>Fläche des Pfeils am Knopf AId; leer ohne Menü.</summary>
    function ArrowRect(const AId: string): TRect;
    /// <summary>Tooltip über dem Punkt (Client); '' = keiner.</summary>
    function HintAt(X, Y: Integer): string;
    /// <summary>Klick wie mit der linken Maustaste (Tests).</summary>
    procedure ClickAt(X, Y: Integer);
    property Buttons: TArray<TAtlasDesignerButton> read FButtons;
    /// <summary>Klick auf einen Knopf (Kennung).</summary>
    property OnCommand: TProc<string> read FOnCommand write FOnCommand;
    /// <summary>Klick auf den Pfeil: Menü des Knopfs an diesem Bildschirmpunkt.</summary>
    property OnMenu: TProc<string, TPoint> read FOnMenu write FOnMenu;
  end;

implementation

uses
  Atlas.UI.EditorToolbar.Glyphs;

{ TAtlasDesignerButton }

class function TAtlasDesignerButton.Create(const AId: string; AIcon: TAtlasToolbarIcon;
  const AHint: string): TAtlasDesignerButton;
begin
  Result := Default(TAtlasDesignerButton);
  Result.Id := AId;
  Result.Icon := AIcon;
  Result.Hint := AHint;
  Result.Enabled := True;
end;

function TAtlasDesignerButton.SameAs(const AOther: TAtlasDesignerButton): Boolean;
begin
  Result := (Id = AOther.Id) and (Icon = AOther.Icon) and (Hint = AOther.Hint) and (Enabled = AOther.Enabled) and
    (Pressed = AOther.Pressed) and (Menu = AOther.Menu) and (GapBefore = AOther.GapBefore);
end;

{ TAtlasDesignerBar }

class function TAtlasDesignerBar.BaseHeight: Integer;
begin
  Result := 24;
end;

function TAtlasDesignerBar.IconSize: Integer;
begin
  Result := Scale(16);
end;

procedure TAtlasDesignerBar.ApplyColors(const AColors: TAtlasColors);
begin
  SetColors(AColors);
end;

procedure TAtlasDesignerBar.SetButtons(const AButtons: TArray<TAtlasDesignerButton>);
var
  mIndex: Integer;
  mSame: Boolean;
begin
  mSame := Length(AButtons) = Length(FButtons);
  if mSame then
    for mIndex := 0 to High(AButtons) do
      if not AButtons[mIndex].SameAs(FButtons[mIndex]) then
      begin
        mSame := False;
        Break;
      end;
  if mSame then
    Exit;
  FButtons := Copy(AButtons);
  Layout;
  SetHot(PartNone);
  Invalidate;
end;

procedure TAtlasDesignerBar.Layout;
var
  mIndex, mX, mSize, mArrow: Integer;
begin
  SetLength(FRects, Length(FButtons));
  SetLength(FArrows, Length(FButtons));
  mSize := ClientHeight;
  if not HandleAllocated then
    mSize := Height;
  mSize := mSize - Scale(2);
  mArrow := Scale(10);
  mX := Scale(4);
  for mIndex := 0 to High(FButtons) do
  begin
    if FButtons[mIndex].GapBefore then
      Inc(mX, Scale(9));
    FRects[mIndex] := Rect(mX, Scale(1), mX + IconSize + Scale(8), Scale(1) + mSize);
    mX := FRects[mIndex].Right;
    if FButtons[mIndex].Menu then
    begin
      FArrows[mIndex] := Rect(mX, Scale(1), mX + mArrow, Scale(1) + mSize);
      mX := FArrows[mIndex].Right;
    end
    else
      FArrows[mIndex] := TRect.Empty;
    Inc(mX, Scale(2));
  end;
end;

function TAtlasDesignerBar.ButtonOf(APart: Integer): Integer;
begin
  Result := -1;
  if (APart >= 0) and (APart div 2 <= High(FButtons)) then
    Result := APart div 2;
end;

function TAtlasDesignerBar.PartAt(X, Y: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FButtons) do
  begin
    if FRects[mIndex].Contains(Point(X, Y)) then
      Exit(2 * mIndex);
    if FButtons[mIndex].Menu and FArrows[mIndex].Contains(Point(X, Y)) then
      Exit(2 * mIndex + 1);
  end;
  Result := PartNone;
end;

function TAtlasDesignerBar.PartHint(APart: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := ButtonOf(APart);
  if mIndex >= 0 then
    Result := FButtons[mIndex].Hint;
end;

function TAtlasDesignerBar.PartEnabled(APart: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := ButtonOf(APart);
  Result := (mIndex >= 0) and FButtons[mIndex].Enabled;
end;

procedure TAtlasDesignerBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mId: string;
begin
  mIndex := ButtonOf(APart);
  if (mIndex < 0) or not FButtons[mIndex].Enabled then
    Exit;
  // Kennung vorher merken: Der Aufrufer setzt im Ereignis oft neue Knöpfe.
  mId := FButtons[mIndex].Id;
  if Odd(APart) then
  begin
    if Assigned(FOnMenu) then
      FOnMenu(mId, ClientToScreen(Point(FRects[mIndex].Left, FRects[mIndex].Bottom)));
  end
  else if Assigned(FOnCommand) then
    FOnCommand(mId);
end;

procedure TAtlasDesignerBar.DrawButton(AIndex: Integer);
var
  mButton: TAtlasDesignerButton;
  mArea, mIcon: TRect;
  mBack, mFore: TColor;
  mRadius, mMid, mHalf: Integer;
  mHot: Boolean;
begin
  mButton := FButtons[AIndex];
  mArea := FRects[AIndex];
  if mButton.Menu then
    mArea.Right := FArrows[AIndex].Right;
  mHot := (Hot = 2 * AIndex) or (Hot = 2 * AIndex + 1);
  mBack := TColor(Colors.Gutter);
  mFore := TColor(Colors.Text);
  mRadius := Scale(4);
  Canvas.Brush.Style := bsSolid;
  if mButton.Pressed then
  begin
    mBack := TColor(Colors.AccentSoft);
    mFore := TColor(Colors.Accent);
    Canvas.Brush.Color := mBack;
    Canvas.Pen.Color := TColor(Colors.Accent);
    Canvas.RoundRect(mArea.Left + Scale(1), mArea.Top + Scale(1), mArea.Right - Scale(1), mArea.Bottom - Scale(1),
      mRadius, mRadius);
  end
  else if mHot and mButton.Enabled then
  begin
    mBack := TColor(Colors.Selection);
    Canvas.Brush.Color := mBack;
    Canvas.Pen.Color := TColor(Colors.Line);
    Canvas.RoundRect(mArea.Left + Scale(1), mArea.Top + Scale(1), mArea.Right - Scale(1), mArea.Bottom - Scale(1),
      mRadius, mRadius);
  end;
  if not mButton.Enabled then
    mFore := TColor(Colors.Muted);
  mIcon := FRects[AIndex];
  mIcon := Rect(mIcon.Left + Scale(4), mIcon.Top + (mIcon.Height - IconSize) div 2, mIcon.Left + Scale(4) + IconSize,
    mIcon.Top + (mIcon.Height - IconSize) div 2 + IconSize);
  TAtlasGlyphPainter.Draw(Canvas, mButton.Icon, mIcon, mFore, mBack, mButton.Id);
  if mButton.Menu then
  begin
    // Kleines Dreieck nach unten.
    mMid := (FArrows[AIndex].Left + FArrows[AIndex].Right) div 2;
    mHalf := Scale(3);
    Canvas.Brush.Color := mFore;
    Canvas.Pen.Color := mFore;
    Canvas.Polygon([Point(mMid - mHalf, FArrows[AIndex].CenterPoint.Y - Scale(1)),
      Point(mMid + mHalf, FArrows[AIndex].CenterPoint.Y - Scale(1)),
      Point(mMid, FArrows[AIndex].CenterPoint.Y + Scale(2))]);
  end;
end;

procedure TAtlasDesignerBar.Paint;
var
  mIndex, mX: Integer;
begin
  Layout;
  PaintChrome(False);
  for mIndex := 0 to High(FButtons) do
  begin
    if FButtons[mIndex].GapBefore then
    begin
      mX := FRects[mIndex].Left - Scale(5);
      Canvas.Pen.Color := TColor(Colors.Line);
      Canvas.MoveTo(mX, Scale(5));
      Canvas.LineTo(mX, ClientHeight - Scale(5));
    end;
    DrawButton(mIndex);
  end;
end;

procedure TAtlasDesignerBar.Resize;
begin
  inherited Resize;
  Layout;
end;

procedure TAtlasDesignerBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  Layout;
end;

function TAtlasDesignerBar.ButtonRect(const AId: string): TRect;
var
  mIndex: Integer;
begin
  Layout;
  for mIndex := 0 to High(FButtons) do
    if SameText(FButtons[mIndex].Id, AId) then
      Exit(FRects[mIndex]);
  Result := TRect.Empty;
end;

function TAtlasDesignerBar.ArrowRect(const AId: string): TRect;
var
  mIndex: Integer;
begin
  Layout;
  for mIndex := 0 to High(FButtons) do
    if SameText(FButtons[mIndex].Id, AId) then
      Exit(FArrows[mIndex]);
  Result := TRect.Empty;
end;

function TAtlasDesignerBar.HintAt(X, Y: Integer): string;
begin
  Layout;
  Result := PartHint(PartAt(X, Y));
end;

procedure TAtlasDesignerBar.ClickAt(X, Y: Integer);
begin
  Layout;
  PartClicked(PartAt(X, Y), [], X, Y);
end;

end.
