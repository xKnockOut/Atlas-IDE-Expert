unit Atlas.UI.EditorToolbar.Bar;

// Atlas-Editorleiste (#1101), Darstellung: eine Zeile mit 16-px-Symbolen über
// dem Editor (bzw. rechts in der Brotkrumenzeile, Inline). Die Höhe hängt nur
// von der DPI ab, nie vom Inhalt.
// - SetButtons setzt die Knöpfe (Befehl, Symbol, Zustand), SetReturn den
//   Rücksprung-Knopf „↩ 214“; er steht hinter den angehefteten
//   Abschnittssymbolen und wandert wie sie nie in den Überlauf.
// - Passt nicht alles in die Breite, verteilt TAtlasToolbarLayout die hinteren
//   Knöpfe auf das Menü »; rechts außen steht immer das Zahnrad.
// - Zustände: hervorgehoben (aktueller Abschnitt, Akzentfarbe), gesperrt
//   (gedämpft, Tooltip nennt den Grund), Punkt (Befunde).
// - Klick meldet OnCommand mit der Befehlskennung, der Rücksprung OnReturn;
//   Zahnrad, Rechtsklick und „Leiste anpassen …“ im Überlauf melden
//   OnCustomize. Ausgelöst wird beim Loslassen über dem Knopf; nur wer auf
//   einem anderen Knopf gedrückt hat, bricht ab. Das Verlassen der Leiste
//   zwischen Drücken und Loslassen bricht nicht ab: In der IDE kommt es bei
//   jedem Klick (Mausfang, die IDE holt den Fokus in den Editor), früher lief
//   dadurch jeder Klick ins Leere.
// - Die Leiste lässt sich von außen nicht sperren (SetEnabled): Die IDE setzt
//   Enabled bei Steuerelementen im Editor-Panel auf False (Protokoll der
//   Brotkrumen: „Fenster ist gesperrt“), danach kam kein Klick mehr an. Die
//   Knöpfe sperrt die Leiste selbst; ein Klick auf einen gesperrten Knopf
//   steht samt Grund im Protokoll.
// - Tooltip je Knopf: Name und Taste.
// - PreferredWidth: Breite ohne Überlauf (Inline: so breit, wie nötig).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.EditorToolbar.Layout;

type
  TAtlasToolbarButton = record
    /// <summary>Befehlskennung; '|' = Trennstrich.</summary>
    Id: string;
    /// <summary>Name des Befehls (Text neben dem Symbol, Menü, erster Buchstabe ohne eigenes Symbol).</summary>
    Caption: string;
    /// <summary>Tooltip: Name und Taste bzw. Grund, warum gesperrt.</summary>
    Hint: string;
    Icon: TAtlasToolbarIcon;
    Enabled: Boolean;
    /// <summary>Hervorgehoben (aktueller Abschnitt).</summary>
    Pressed: Boolean;
    /// <summary>Punkt oben rechts (Befunde).</summary>
    Dot: Boolean;
    /// <summary>Wandert nie in den Überlauf.</summary>
    Pinned: Boolean;
    function IsSeparator: Boolean;
    function SameAs(const AOther: TAtlasToolbarButton): Boolean;
    class function Create(const AId, ACaption, AHint: string; AIcon: TAtlasToolbarIcon): TAtlasToolbarButton; static;
    class function Separator: TAtlasToolbarButton; static;
  end;

  TAtlasToolbarCommandEvent = reference to procedure(const AId: string);

  TAtlasEditorToolbar = class(TCustomControl)
  private const
    /// <summary>Teile ohne Index in FButtons.</summary>
    PartNone = -1;
    PartReturn = -2;
    PartMore = -3;
    PartGear = -4;
  private
    FButtons: TArray<TAtlasToolbarButton>;
    FReturnShown: Boolean;
    FReturnText: string;
    FReturnHint: string;
    FLabels: Boolean;
    FInline: Boolean;
    FColors: TAtlasColors;
    FRects: TArray<TRect>;
    FReturnRect: TRect;
    FMoreRect: TRect;
    FGearRect: TRect;
    FOverflow: TArray<Integer>;
    FLaidOut: Boolean;
    FHot: Integer;
    FDown: Integer;
    FMoreHint: string;
    FGearHint: string;
    FCustomizeCaption: string;
    FMenu: TPopupMenu;
    /// <summary>Kennungen der Menüeinträge: Die Knöpfe können sich ändern, während das Menü offen ist.</summary>
    FMenuIds: TArray<string>;
    FOnCommand: TAtlasToolbarCommandEvent;
    FOnReturn: TProc;
    FOnCustomize: TProc;
    function Scale(AValue: Integer): Integer;
    function IconSize: Integer;
    function ButtonWidth(const AButton: TAtlasToolbarButton): Integer;
    function ReturnWidth: Integer;
    function SeparatorWidth: Integer;
    /// <summary>Einträge in Reihenfolge der Leiste: Index in FButtons, PartReturn für den Rücksprung.</summary>
    function Entries: TArray<Integer>;
    procedure Layout;
    function PartAt(X, Y: Integer): Integer;
    function PartRect(APart: Integer): TRect;
    function PartHint(APart: Integer): string;
    function PartEnabled(APart: Integer): Boolean;
    procedure DrawButton(const ARect: TRect; AIcon: TAtlasToolbarIcon; const ACaption: string; AEnabled, APressed,
      AHot, ADot: Boolean; const AText: string);
    procedure ShowMenu(const APoint: TPoint; AOverflow: Boolean);
    procedure MenuCommandClick(Sender: TObject);
    procedure MenuCustomizeClick(Sender: TObject);
    procedure Fire(APart: Integer);
    procedure SetLabels(AValue: Boolean);
    procedure SetInline(AValue: Boolean);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    procedure SetEnabled(Value: Boolean); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Knöpfe setzen; gleiche Knöpfe zeichnen nicht neu.</summary>
    procedure SetButtons(const AButtons: TArray<TAtlasToolbarButton>);
    /// <summary>Rücksprung zeigen (AShown) mit Text (Zeilennummer) und Tooltip.</summary>
    procedure SetReturn(AShown: Boolean; const AText, AHint: string);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Höhe der Leiste bei APPI (eine Zeile, 24 px bei 96 DPI).</summary>
    class function BarHeight(APPI: Integer): Integer; static;
    /// <summary>Breite, mit der alles ohne Überlauf passt (samt Zahnrad).</summary>
    function PreferredWidth: Integer;
    /// <summary>Fläche des Knopfs mit Kennung AId (Client); leer, wenn er nicht in der Leiste steht.</summary>
    function ButtonRect(const AId: string): TRect;
    /// <summary>Kennungen im Überlaufmenü in Reihenfolge ('|' = Trennstrich).</summary>
    function OverflowIds: TArray<string>;
    /// <summary>Steht der Rücksprung-Knopf in der Leiste?</summary>
    function ReturnRect: TRect;
    function MoreRect: TRect;
    function GearRect: TRect;
    /// <summary>Tooltip über dem Punkt (Client); '' = keiner.</summary>
    function HintAt(X, Y: Integer): string;
    /// <summary>Klick wie mit der Maus (für Tests): Knopf, Rücksprung, », Zahnrad unter dem Punkt.</summary>
    procedure ClickAt(X, Y: Integer);
    property Buttons: TArray<TAtlasToolbarButton> read FButtons;
    property ReturnShown: Boolean read FReturnShown;
    property Labels: Boolean read FLabels write SetLabels;
    /// <summary>In der Brotkrumenzeile: ohne eigene Fläche unten, Trennlinie links.</summary>
    property InlineMode: Boolean read FInline write SetInline;
    property MoreHint: string read FMoreHint write FMoreHint;
    property GearHint: string read FGearHint write FGearHint;
    property CustomizeCaption: string read FCustomizeCaption write FCustomizeCaption;
    property OnCommand: TAtlasToolbarCommandEvent read FOnCommand write FOnCommand;
    property OnReturn: TProc read FOnReturn write FOnReturn;
    property OnCustomize: TProc read FOnCustomize write FOnCustomize;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.EditorToolbar.Glyphs;

const
  /// <summary>Höhe bei 96 DPI.</summary>
  BaseHeight = 24;
  BaseButton = 24;
  BaseSeparator = 9;
  Margin = 4;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasToolbarButton }

class function TAtlasToolbarButton.Create(const AId, ACaption, AHint: string;
  AIcon: TAtlasToolbarIcon): TAtlasToolbarButton;
begin
  Result := Default(TAtlasToolbarButton);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Icon := AIcon;
  Result.Enabled := True;
end;

class function TAtlasToolbarButton.Separator: TAtlasToolbarButton;
begin
  Result := Default(TAtlasToolbarButton);
  Result.Id := TAtlasToolbarItems.Separator;
end;

function TAtlasToolbarButton.IsSeparator: Boolean;
begin
  Result := TAtlasToolbarItems.IsSeparator(Id);
end;

function TAtlasToolbarButton.SameAs(const AOther: TAtlasToolbarButton): Boolean;
begin
  Result := (Id = AOther.Id) and (Caption = AOther.Caption) and (Hint = AOther.Hint) and (Icon = AOther.Icon) and
    (Enabled = AOther.Enabled) and (Pressed = AOther.Pressed) and (Dot = AOther.Dot) and (Pinned = AOther.Pinned);
end;

{ TAtlasEditorToolbar }

constructor TAtlasEditorToolbar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  ShowHint := True;
  FColors := TAtlasColors.Light;
  FHot := PartNone;
  FDown := PartNone;
  FMoreHint := '»';
  FGearHint := '';
  FCustomizeCaption := '';
  Height := BarHeight(96);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

destructor TAtlasEditorToolbar.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasEditorToolbar.BarHeight(APPI: Integer): Integer;
begin
  Result := MulDiv(BaseHeight, Max(APPI, 96), 96);
end;

procedure TAtlasEditorToolbar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  inherited ChangeScale(M, D, isDpiChange);
  if not FInline then
  begin
    Height := BarHeight(CurrentPPI);
    Constraints.MinHeight := Height;
    Constraints.MaxHeight := Height;
  end;
  FLaidOut := False;
end;

function TAtlasEditorToolbar.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

function TAtlasEditorToolbar.IconSize: Integer;
begin
  Result := Scale(16);
end;

procedure TAtlasEditorToolbar.SetButtons(const AButtons: TArray<TAtlasToolbarButton>);
var
  Index: Integer;
  Same: Boolean;
begin
  Same := Length(AButtons) = Length(FButtons);
  Index := 0;
  while Same and (Index <= High(AButtons)) do
  begin
    Same := AButtons[Index].SameAs(FButtons[Index]);
    Inc(Index);
  end;
  if Same then
    Exit;
  FButtons := AButtons;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetReturn(AShown: Boolean; const AText, AHint: string);
begin
  if (AShown = FReturnShown) and (AText = FReturnText) and (AHint = FReturnHint) then
    Exit;
  FReturnShown := AShown;
  FReturnText := AText;
  FReturnHint := AHint;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetLabels(AValue: Boolean);
begin
  if AValue = FLabels then
    Exit;
  FLabels := AValue;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetInline(AValue: Boolean);
begin
  if AValue = FInline then
    Exit;
  FInline := AValue;
  // In der Brotkrumenzeile bestimmt deren Höhe die Höhe (alRight).
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  if not FInline then
  begin
    Height := BarHeight(CurrentPPI);
    Constraints.MinHeight := Height;
    Constraints.MaxHeight := Height;
  end;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.Resize;
begin
  inherited Resize;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.CMFontChanged(var Message: TMessage);
begin
  inherited;
  FLaidOut := False;
  Invalidate;
end;

function TAtlasEditorToolbar.SeparatorWidth: Integer;
begin
  Result := Scale(BaseSeparator);
end;

function TAtlasEditorToolbar.ButtonWidth(const AButton: TAtlasToolbarButton): Integer;
begin
  if AButton.IsSeparator then
    Exit(SeparatorWidth);
  Result := Scale(BaseButton);
  if FLabels and (AButton.Caption <> '') then
  begin
    Canvas.Font := Font;
    Inc(Result, Canvas.TextWidth(AButton.Caption) + Scale(6));
  end;
end;

function TAtlasEditorToolbar.ReturnWidth: Integer;
begin
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Result := Scale(4) + IconSize + Scale(4) + Canvas.TextWidth(FReturnText) + Scale(6);
  Canvas.Font := Font;
end;

function TAtlasEditorToolbar.Entries: TArray<Integer>;
var
  Index: Integer;
  Placed: Boolean;
begin
  Result := nil;
  Placed := not FReturnShown;
  for Index := 0 to High(FButtons) do
  begin
    // Rücksprung hinter den angehefteten Abschnittssymbolen am Anfang.
    if not Placed and not FButtons[Index].Pinned then
    begin
      Result := Result + [PartReturn];
      Placed := True;
    end;
    Result := Result + [Index];
  end;
  if not Placed then
    Result := Result + [PartReturn];
end;

procedure TAtlasEditorToolbar.Layout;
var
  Order: TArray<Integer>;
  Slots: TArray<TAtlasToolbarSlot>;
  Fit: TAtlasToolbarFit;
  Index, Left_, Top_, Bottom_, Available, Width_, Part: Integer;
  Overflow: Integer;
begin
  if FLaidOut or not HandleAllocated then
    Exit;
  FLaidOut := True;
  Order := Entries;
  SetLength(Slots, Length(Order));
  for Index := 0 to High(Order) do
    if Order[Index] = PartReturn then
      Slots[Index] := TAtlasToolbarSlot.Create(ReturnWidth, False, True)
    else
      Slots[Index] := TAtlasToolbarSlot.Create(ButtonWidth(FButtons[Order[Index]]),
        FButtons[Order[Index]].IsSeparator, FButtons[Order[Index]].Pinned);
  Width_ := Scale(BaseButton);
  Available := ClientWidth - 2 * Scale(Margin) - Width_;
  Fit := TAtlasToolbarLayout.Fit(Slots, Available, Width_);
  SetLength(FRects, Length(FButtons));
  for Index := 0 to High(FRects) do
    FRects[Index] := TRect.Empty;
  FReturnRect := TRect.Empty;
  Top_ := Scale(1);
  Bottom_ := ClientHeight - Scale(1);
  Left_ := Scale(Margin);
  for Index := 0 to High(Order) do
  begin
    if not Fit.Visible[Index] then
      Continue;
    Part := Order[Index];
    if Part = PartReturn then
      FReturnRect := Rect(Left_, Top_, Left_ + Slots[Index].Width, Bottom_)
    else
      FRects[Part] := Rect(Left_, Top_, Left_ + Slots[Index].Width, Bottom_);
    Inc(Left_, Slots[Index].Width);
  end;
  FOverflow := nil;
  for Overflow in Fit.Overflow do
    if Order[Overflow] >= 0 then
      FOverflow := FOverflow + [Order[Overflow]];
  if Fit.More then
  begin
    FMoreRect := Rect(Left_, Top_, Left_ + Width_, Bottom_);
    Inc(Left_, Width_);
  end
  else
    FMoreRect := TRect.Empty;
  // Zahnrad rechts außen.
  FGearRect := Rect(Max(Left_, ClientWidth - Scale(Margin) - Width_), Top_, Max(Left_, ClientWidth - Scale(Margin) -
    Width_) + Width_, Bottom_);
end;

function TAtlasEditorToolbar.PreferredWidth: Integer;
var
  Order: TArray<Integer>;
  Slots: TArray<TAtlasToolbarSlot>;
  Index: Integer;
begin
  Order := Entries;
  SetLength(Slots, Length(Order));
  for Index := 0 to High(Order) do
    if Order[Index] = PartReturn then
      Slots[Index] := TAtlasToolbarSlot.Create(ReturnWidth, False, True)
    else
      Slots[Index] := TAtlasToolbarSlot.Create(ButtonWidth(FButtons[Order[Index]]),
        FButtons[Order[Index]].IsSeparator, FButtons[Order[Index]].Pinned);
  Result := TAtlasToolbarLayout.FullWidth(Slots) + 2 * Scale(Margin) + Scale(BaseButton);
  if FInline then
    Inc(Result, Scale(Margin));
end;

function TAtlasEditorToolbar.PartRect(APart: Integer): TRect;
begin
  Layout;
  case APart of
    PartReturn:
      Result := FReturnRect;
    PartMore:
      Result := FMoreRect;
    PartGear:
      Result := FGearRect;
  else
    if (APart >= 0) and (APart <= High(FRects)) then
      Result := FRects[APart]
    else
      Result := TRect.Empty;
  end;
end;

function TAtlasEditorToolbar.ButtonRect(const AId: string): TRect;
var
  Index: Integer;
begin
  for Index := 0 to High(FButtons) do
    if SameText(FButtons[Index].Id, AId) then
      Exit(PartRect(Index));
  Result := TRect.Empty;
end;

function TAtlasEditorToolbar.ReturnRect: TRect;
begin
  Result := PartRect(PartReturn);
end;

function TAtlasEditorToolbar.MoreRect: TRect;
begin
  Result := PartRect(PartMore);
end;

function TAtlasEditorToolbar.GearRect: TRect;
begin
  Result := PartRect(PartGear);
end;

function TAtlasEditorToolbar.OverflowIds: TArray<string>;
var
  Index: Integer;
begin
  Layout;
  Result := nil;
  for Index in FOverflow do
    Result := Result + [FButtons[Index].Id];
end;

function TAtlasEditorToolbar.PartAt(X, Y: Integer): Integer;
var
  Index: Integer;
  Point_: TPoint;
begin
  Layout;
  Point_ := Point(X, Y);
  if FReturnRect.Contains(Point_) then
    Exit(PartReturn);
  if FMoreRect.Contains(Point_) then
    Exit(PartMore);
  if FGearRect.Contains(Point_) then
    Exit(PartGear);
  for Index := 0 to High(FRects) do
    if not FButtons[Index].IsSeparator and FRects[Index].Contains(Point_) then
      Exit(Index);
  Result := PartNone;
end;

function TAtlasEditorToolbar.PartHint(APart: Integer): string;
begin
  case APart of
    PartNone:
      Result := '';
    PartReturn:
      Result := FReturnHint;
    PartMore:
      Result := FMoreHint;
    PartGear:
      Result := FGearHint;
  else
    Result := FButtons[APart].Hint;
    if Result = '' then
      Result := FButtons[APart].Caption;
  end;
end;

function TAtlasEditorToolbar.PartEnabled(APart: Integer): Boolean;
begin
  Result := (APart < 0) or FButtons[APart].Enabled;
end;

function TAtlasEditorToolbar.HintAt(X, Y: Integer): string;
begin
  Result := PartHint(PartAt(X, Y));
end;

procedure TAtlasEditorToolbar.DrawButton(const ARect: TRect; AIcon: TAtlasToolbarIcon; const ACaption: string;
  AEnabled, APressed, AHot, ADot: Boolean; const AText: string);
var
  Back, Fore: TColor;
  Icon, Part: TRect;
  Radius, DotSize: Integer;
begin
  Back := ToColor(FColors.Gutter);
  Fore := ToColor(FColors.Text);
  Radius := Scale(4);
  Canvas.Brush.Style := bsSolid;
  if APressed then
  begin
    Back := ToColor(FColors.AccentSoft);
    Fore := ToColor(FColors.Accent);
    Canvas.Brush.Color := Back;
    Canvas.Pen.Color := ToColor(FColors.Accent);
    Canvas.RoundRect(ARect.Left + Scale(1), ARect.Top + Scale(1), ARect.Right - Scale(1), ARect.Bottom - Scale(1),
      Radius, Radius);
  end
  else if AHot and AEnabled then
  begin
    Back := ToColor(FColors.Selection);
    Canvas.Brush.Color := Back;
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.RoundRect(ARect.Left + Scale(1), ARect.Top + Scale(1), ARect.Right - Scale(1), ARect.Bottom - Scale(1),
      Radius, Radius);
  end;
  if not AEnabled then
    Fore := ToColor(FColors.Muted);
  Icon := Rect(ARect.Left + Scale(4), ARect.Top + (ARect.Height - IconSize) div 2, ARect.Left + Scale(4) + IconSize,
    ARect.Top + (ARect.Height - IconSize) div 2 + IconSize);
  Canvas.Font := Font;
  TAtlasGlyphPainter.Draw(Canvas, AIcon, Icon, Fore, Back, ACaption);
  if AText <> '' then
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := Fore;
    Canvas.Brush.Style := bsClear;
    Part := Rect(Icon.Right + Scale(4), ARect.Top, ARect.Right - Scale(2), ARect.Bottom);
    DrawText(Canvas.Handle, PChar(AText), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  if ADot then
  begin
    DotSize := Scale(6);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Warn);
    Canvas.Pen.Color := ToColor(FColors.Warn);
    Canvas.Ellipse(ARect.Right - Scale(3) - DotSize, ARect.Top + Scale(2), ARect.Right - Scale(3),
      ARect.Top + Scale(2) + DotSize);
  end;
end;

procedure TAtlasEditorToolbar.Paint;
var
  Index, Middle: Integer;
  Button: TAtlasToolbarButton;
  Area: TRect;
  mText: string;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := ToColor(FColors.Line);
  // Untere Linie wie die Brotkrumenleiste, Inline dazu ein Trennstrich links.
  Canvas.MoveTo(0, ClientHeight - 1);
  Canvas.LineTo(ClientWidth, ClientHeight - 1);
  if FInline then
  begin
    Canvas.MoveTo(0, Scale(4));
    Canvas.LineTo(0, ClientHeight - Scale(4));
  end;
  for Index := 0 to High(FButtons) do
  begin
    Area := FRects[Index];
    if Area.IsEmpty then
      Continue;
    Button := FButtons[Index];
    if Button.IsSeparator then
    begin
      Middle := (Area.Left + Area.Right) div 2;
      Canvas.Pen.Color := ToColor(FColors.Line);
      Canvas.MoveTo(Middle, Area.Top + Scale(4));
      Canvas.LineTo(Middle, Area.Bottom - Scale(4));
      Continue;
    end;
    mText := '';
    if FLabels then
      mText := Button.Caption;
    DrawButton(Area, Button.Icon, Button.Caption, Button.Enabled, Button.Pressed, FHot = Index, Button.Dot, mText);
  end;
  if not FReturnRect.IsEmpty then
  begin
    // Rücksprung: Akzentfarbe, Zeilennummer fett daneben.
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.AccentSoft);
    Canvas.Pen.Color := ToColor(FColors.Accent);
    Canvas.RoundRect(FReturnRect.Left + Scale(1), FReturnRect.Top + Scale(1), FReturnRect.Right - Scale(1),
      FReturnRect.Bottom - Scale(1), Scale(4), Scale(4));
    TAtlasGlyphPainter.Draw(Canvas, TAtlasToolbarIcon.Return, Rect(FReturnRect.Left + Scale(4), FReturnRect.Top +
      (FReturnRect.Height - IconSize) div 2, FReturnRect.Left + Scale(4) + IconSize, FReturnRect.Top +
      (FReturnRect.Height - IconSize) div 2 + IconSize), ToColor(FColors.Accent), ToColor(FColors.AccentSoft), '');
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(FColors.Accent);
    Canvas.Brush.Style := bsClear;
    Area := Rect(FReturnRect.Left + Scale(8) + IconSize, FReturnRect.Top, FReturnRect.Right - Scale(2),
      FReturnRect.Bottom);
    DrawText(Canvas.Handle, PChar(FReturnText), -1, Area, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Font := Font;
  end;
  if not FMoreRect.IsEmpty then
    DrawButton(FMoreRect, TAtlasToolbarIcon.More, '', True, False, FHot = PartMore, False, '');
  DrawButton(FGearRect, TAtlasToolbarIcon.Gear, '', True, False, FHot = PartGear, False, '');
end;

procedure TAtlasEditorToolbar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := PartAt(X, Y);
  if Hot = FHot then
    Exit;
  FHot := Hot;
  if (Hot <> PartNone) and PartEnabled(Hot) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Application.CancelHint;
  Hint := PartHint(Hot);
  Invalidate;
end;

procedure TAtlasEditorToolbar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  // FDown bleibt: Das Verlassen kommt in der IDE zwischen Drücken und Loslassen jedes Klicks (siehe oben).
  if FHot = PartNone then
    Exit;
  FHot := PartNone;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetEnabled(Value: Boolean);
begin
  // Immer bedienbar (siehe oben); gesperrt werden nur einzelne Knöpfe.
  inherited SetEnabled(True);
end;

procedure TAtlasEditorToolbar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FDown := PartAt(X, Y);
end;

procedure TAtlasEditorToolbar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Part: TPoint;
  Released: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbRight then
  begin
    // Rechtsklick: „Leiste anpassen …“.
    Part := ClientToScreen(Point(X, Y));
    ShowMenu(Part, False);
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  // Erst beim Loslassen, wie in der Brotkrumenleiste: Die IDE holt beim Drücken den Fokus in den Editor. Ein
  // Drücken muss die Leiste dafür nicht gesehen haben; nur ein Drücken auf einem anderen Knopf bricht ab.
  Released := PartAt(X, Y);
  if (Released <> PartNone) and ((FDown = PartNone) or (FDown = Released)) then
    Fire(Released);
  FDown := PartNone;
end;

procedure TAtlasEditorToolbar.ClickAt(X, Y: Integer);
begin
  Fire(PartAt(X, Y));
end;

procedure TAtlasEditorToolbar.Fire(APart: Integer);
var
  Area: TRect;
begin
  case APart of
    PartNone:
      ;
    PartReturn:
      if Assigned(FOnReturn) then
        FOnReturn();
    PartMore:
      begin
        Area := FMoreRect;
        ShowMenu(ClientToScreen(Point(Area.Left, Area.Bottom)), True);
      end;
    PartGear:
      if Assigned(FOnCustomize) then
        FOnCustomize();
  else
    if not FButtons[APart].Enabled then
      TAtlasGuard.Log(Format('Editorleiste: Klick auf gesperrten Knopf %s (%s)', [FButtons[APart].Id,
        PartHint(APart)]))
    else if Assigned(FOnCommand) then
      FOnCommand(FButtons[APart].Id);
  end;
end;

procedure TAtlasEditorToolbar.ShowMenu(const APoint: TPoint; AOverflow: Boolean);
var
  Item: TMenuItem;
  Index: Integer;
begin
  Layout;
  FreeAndNil(FMenu);
  FMenuIds := nil;
  FMenu := TPopupMenu.Create(nil);
  if AOverflow then
  begin
    for Index in FOverflow do
    begin
      if FButtons[Index].IsSeparator then
      begin
        FMenu.Items.Add(NewLine);
        Continue;
      end;
      Item := TMenuItem.Create(FMenu);
      Item.Caption := StringReplace(FButtons[Index].Caption, '&', '&&', [rfReplaceAll]);
      Item.Hint := FButtons[Index].Hint;
      Item.Enabled := FButtons[Index].Enabled;
      Item.Checked := FButtons[Index].Pressed;
      Item.Tag := Length(FMenuIds);
      FMenuIds := FMenuIds + [FButtons[Index].Id];
      Item.OnClick := MenuCommandClick;
      FMenu.Items.Add(Item);
    end;
    if FMenu.Items.Count > 0 then
      FMenu.Items.Add(NewLine);
  end;
  Item := TMenuItem.Create(FMenu);
  Item.Caption := StringReplace(FCustomizeCaption, '&', '&&', [rfReplaceAll]);
  Item.OnClick := MenuCustomizeClick;
  FMenu.Items.Add(Item);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasEditorToolbar.MenuCommandClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (Index >= 0) and (Index <= High(FMenuIds)) and Assigned(FOnCommand) then
    FOnCommand(FMenuIds[Index]);
end;

procedure TAtlasEditorToolbar.MenuCustomizeClick(Sender: TObject);
begin
  if Assigned(FOnCustomize) then
    FOnCustomize();
end;

end.
