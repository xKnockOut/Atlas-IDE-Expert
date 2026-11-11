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
// - Gesperrt wird die Leiste nur von außen: Etwas setzt Enabled bei
//   Steuerelementen im Editor-Panel auf False (Protokoll der Brotkrumen:
//   „Fenster ist gesperrt“), danach kommt kein Klick mehr an. OnDisabled
//   meldet das im Moment des Sperrens, die IDE-Schicht protokolliert den
//   Aufrufer. Die Knöpfe sperrt die Leiste selbst; ein Klick auf einen
//   gesperrten Knopf steht samt Grund im Protokoll.
// - Tooltip je Knopf: Name und Taste.
// - Höhe, Farben, Hervorhebung, Klick beim Loslassen, Kontextmenü (geht nie
//   an den Editor) und OnDisabled kommen vom Vorfahr TAtlasEditorBar (#1248).
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
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.EditorToolbar.Layout,
  Atlas.UI.Editor.Bar;

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

  /// <summary>Lage der Teile nach dem Layout (Client): je Knopf, Rücksprung, », Zahnrad und die Knöpfe im
  /// Überlauf. Leere Flächen stehen nicht in der Leiste.</summary>
  TAtlasToolbarPlaces = record
  public const
    /// <summary>Teile ohne Index in den Knöpfen (PartNone vom Vorfahr ist -1).</summary>
    cPartReturn = -2;
    cPartMore = -3;
    cPartGear = -4;
  public
    Ids: TArray<string>;
    Separators: TArray<Boolean>;
    Rects: TArray<TRect>;
    Return: TRect;
    More: TRect;
    Gear: TRect;
    /// <summary>Indizes der Knöpfe im Überlaufmenü in Reihenfolge.</summary>
    Overflow: TArray<Integer>;
    class function Create(const AButtons: TArray<TAtlasToolbarButton>): TAtlasToolbarPlaces; static;
    /// <summary>Verteilt die Einträge AOrder (Index oder PartReturn) mit Breiten ASlots nach AFit in ABand; AWidth
    /// ist die Breite von » und Zahnrad, das rechts außen steht.</summary>
    procedure Arrange(const AOrder: TArray<Integer>; const ASlots: TArray<TAtlasToolbarSlot>;
      const AFit: TAtlasToolbarFit; const ABand: TRect; AWidth: Integer);
    /// <summary>Fläche des Knopfs mit Kennung AId; leer, wenn er nicht in der Leiste steht.</summary>
    function ButtonRect(const AId: string): TRect;
    /// <summary>Kennungen im Überlaufmenü in Reihenfolge ('|' = Trennstrich).</summary>
    function OverflowIds: TArray<string>;
    /// <summary>Teil unter APoint; -1 (PartNone) ohne. Trennstriche sind keine Teile.</summary>
    function PartAt(const APoint: TPoint): Integer;
  end;

  /// <summary>Rücksprung-Knopf: gezeigt, Text (Zeilennummer) und Tooltip.</summary>
  TAtlasToolbarReturn = record
    Shown: Boolean;
    Text: string;
    Hint: string;
  end;

  /// <summary>Texte der Leiste: Tooltips von » und Zahnrad, Menüeintrag „Leiste anpassen …“.</summary>
  TAtlasToolbarTexts = record
    More: string;
    Gear: string;
    Customize: string;
  end;

  TAtlasToolbarEvents = record
    Command: TAtlasToolbarCommandEvent;
    Return: TProc;
    Customize: TProc;
  end;

  TAtlasEditorToolbar = class(TAtlasEditorBar)
  private
    FButtons: TArray<TAtlasToolbarButton>;
    FReturn: TAtlasToolbarReturn;
    FLabels: Boolean;
    FInline: Boolean;
    FPlaces: TAtlasToolbarPlaces;
    FLaidOut: Boolean;
    FTexts: TAtlasToolbarTexts;
    FMenu: TPopupMenu;
    FEvents: TAtlasToolbarEvents;
    procedure Layout;
    procedure ShowMenu(const APoint: TPoint; AOverflow: Boolean);
    procedure Fire(APart: Integer);
    procedure SetLabels(AValue: Boolean);
    procedure SetInline(AValue: Boolean);
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    class function BaseHeight: Integer; override;
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    function PartEnabled(APart: Integer): Boolean; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    /// <summary>Rechtsklick: „Leiste anpassen …“.</summary>
    procedure ContextMenu(const APoint: TPoint; APart: Integer); override;
    function KeyboardMenuPoint: TPoint; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Knöpfe setzen; gleiche Knöpfe zeichnen nicht neu.</summary>
    procedure SetButtons(const AButtons: TArray<TAtlasToolbarButton>);
    /// <summary>Rücksprung zeigen (AShown) mit Text (Zeilennummer) und Tooltip.</summary>
    procedure SetReturn(AShown: Boolean; const AText, AHint: string);
    /// <summary>Breite, mit der alles ohne Überlauf passt (samt Zahnrad).</summary>
    function PreferredWidth: Integer;
    /// <summary>Lage der Teile nach dem Layout (Client).</summary>
    function Places: TAtlasToolbarPlaces;
    /// <summary>Tooltip über dem Punkt (Client); '' = keiner.</summary>
    function HintAt(AX, AY: Integer): string;
    /// <summary>Klick wie mit der Maus (für Tests): Knopf, Rücksprung, », Zahnrad unter dem Punkt.</summary>
    procedure ClickAt(AX, AY: Integer);
    property Labels: Boolean read FLabels write SetLabels;
    /// <summary>In der Brotkrumenzeile: ohne eigene Fläche unten, Trennlinie links.</summary>
    property InlineMode: Boolean read FInline write SetInline;
    property MoreHint: string read FTexts.More write FTexts.More;
    property GearHint: string read FTexts.Gear write FTexts.Gear;
    property CustomizeCaption: string read FTexts.Customize write FTexts.Customize;
    property OnCommand: TAtlasToolbarCommandEvent read FEvents.Command write FEvents.Command;
    property OnReturn: TProc read FEvents.Return write FEvents.Return;
    property OnCustomize: TProc read FEvents.Customize write FEvents.Customize;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.EditorToolbar.Glyphs;

const
  cBaseButton = 24;
  cBaseSeparator = 9;
  cMargin = 4;
  cPartReturn = TAtlasToolbarPlaces.cPartReturn;
  cPartMore = TAtlasToolbarPlaces.cPartMore;
  cPartGear = TAtlasToolbarPlaces.cPartGear;

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
  Result.Id := TAtlasToolbarItems.cSeparator;
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

{ TAtlasToolbarPlaces }

class function TAtlasToolbarPlaces.Create(const AButtons: TArray<TAtlasToolbarButton>): TAtlasToolbarPlaces;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasToolbarPlaces);
  SetLength(Result.Ids, Length(AButtons));
  SetLength(Result.Separators, Length(AButtons));
  SetLength(Result.Rects, Length(AButtons));
  for mIndex := 0 to High(AButtons) do
  begin
    Result.Ids[mIndex] := AButtons[mIndex].Id;
    Result.Separators[mIndex] := AButtons[mIndex].IsSeparator;
    Result.Rects[mIndex] := TRect.Empty;
  end;
  Result.Return := TRect.Empty;
  Result.More := TRect.Empty;
  Result.Gear := TRect.Empty;
end;

procedure TAtlasToolbarPlaces.Arrange(const AOrder: TArray<Integer>; const ASlots: TArray<TAtlasToolbarSlot>;
  const AFit: TAtlasToolbarFit; const ABand: TRect; AWidth: Integer);
var
  mIndex, mLeft: Integer;
begin
  mLeft := ABand.Left;
  for mIndex := 0 to High(AOrder) do
  begin
    if not AFit.Visible[mIndex] then
    begin
      Continue;
    end;
    if AOrder[mIndex] = cPartReturn then
    begin
      Return := Rect(mLeft, ABand.Top, mLeft + ASlots[mIndex].Width, ABand.Bottom);
    end
    else
    begin
      Rects[AOrder[mIndex]] := Rect(mLeft, ABand.Top, mLeft + ASlots[mIndex].Width, ABand.Bottom);
    end;
    Inc(mLeft, ASlots[mIndex].Width);
  end;
  Overflow := nil;
  for mIndex in AFit.Overflow do
  begin
    if AOrder[mIndex] >= 0 then
    begin
      Overflow := Overflow + [AOrder[mIndex]];
    end;
  end;
  if AFit.More then
  begin
    More := Rect(mLeft, ABand.Top, mLeft + AWidth, ABand.Bottom);
    Inc(mLeft, AWidth);
  end;
  // Zahnrad rechts außen.
  mLeft := Max(mLeft, ABand.Right - AWidth);
  Gear := Rect(mLeft, ABand.Top, mLeft + AWidth, ABand.Bottom);
end;

function TAtlasToolbarPlaces.ButtonRect(const AId: string): TRect;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Ids) do
  begin
    if SameText(Ids[mIndex], AId) then
    begin
      Exit(Rects[mIndex]);
    end;
  end;
  Result := TRect.Empty;
end;

function TAtlasToolbarPlaces.OverflowIds: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex in Overflow do
  begin
    Result := Result + [Ids[mIndex]];
  end;
end;

function TAtlasToolbarPlaces.PartAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  if Return.Contains(APoint) then
  begin
    Exit(cPartReturn);
  end;
  if More.Contains(APoint) then
  begin
    Exit(cPartMore);
  end;
  if Gear.Contains(APoint) then
  begin
    Exit(cPartGear);
  end;
  for mIndex := 0 to High(Rects) do
  begin
    if not Separators[mIndex] and Rects[mIndex].Contains(APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := TAtlasEditorBar.cPartNone;
end;

type
  /// <summary>Breiten der Leiste: Knöpfe, Rücksprung und die Einträge in Reihenfolge.</summary>
  TAtlasToolbarMeasure = record
    Bar: TAtlasEditorToolbar;
    function IconSize: Integer;
    function ButtonWidth(const AButton: TAtlasToolbarButton): Integer;
    function ReturnWidth: Integer;
    /// <summary>Einträge in Reihenfolge der Leiste: Index der Knöpfe, PartReturn für den Rücksprung.</summary>
    function Entries: TArray<Integer>;
    function Slots(const AOrder: TArray<Integer>): TArray<TAtlasToolbarSlot>;
  end;

  /// <summary>Zeichnen der Knöpfe, Trennstriche und des Rücksprungs.</summary>
  TAtlasToolbarPainter = record
    Bar: TAtlasEditorToolbar;
    procedure Button(const ARect: TRect; const AButton: TAtlasToolbarButton; AHot: Boolean; const AText: string);
    procedure Separator(const ARect: TRect);
    procedure Return(const ARect: TRect; const AText: string);
  end;

  /// <summary>Menü der Leiste: Überlauf und „Leiste anpassen …“. Die Kennungen stehen im Menü, weil sich die
  /// Knöpfe ändern können, während es offen ist.</summary>
  TAtlasToolbarMenu = class(TPopupMenu)
  private
    FBar: TAtlasEditorToolbar;
    FIds: TArray<string>;
    procedure CommandClick(Sender: TObject);
    procedure CustomizeClick(Sender: TObject);
  public
    constructor CreateFor(ABar: TAtlasEditorToolbar);
    procedure AddButton(const AButton: TAtlasToolbarButton);
    procedure AddCustomize(const ACaption: string);
  end;

{ TAtlasToolbarMeasure }

function TAtlasToolbarMeasure.IconSize: Integer;
begin
  Result := Bar.Scale(16);
end;

function TAtlasToolbarMeasure.ButtonWidth(const AButton: TAtlasToolbarButton): Integer;
begin
  if AButton.IsSeparator then
  begin
    Exit(Bar.Scale(cBaseSeparator));
  end;
  Result := Bar.Scale(cBaseButton);
  if Bar.FLabels and (AButton.Caption <> '') then
  begin
    Bar.Canvas.Font := Bar.Font;
    Inc(Result, Bar.Canvas.TextWidth(AButton.Caption) + Bar.Scale(6));
  end;
end;

function TAtlasToolbarMeasure.ReturnWidth: Integer;
begin
  Bar.Canvas.Font := Bar.Font;
  Bar.Canvas.Font.Style := [fsBold];
  Result := Bar.Scale(4) + IconSize + Bar.Scale(4) + Bar.Canvas.TextWidth(Bar.FReturn.Text) + Bar.Scale(6);
  Bar.Canvas.Font := Bar.Font;
end;

function TAtlasToolbarMeasure.Entries: TArray<Integer>;
var
  mIndex: Integer;
  mPlaced: Boolean;
begin
  Result := nil;
  mPlaced := not Bar.FReturn.Shown;
  for mIndex := 0 to High(Bar.FButtons) do
  begin
    // Rücksprung hinter den angehefteten Abschnittssymbolen am Anfang.
    if not mPlaced and not Bar.FButtons[mIndex].Pinned then
    begin
      Result := Result + [cPartReturn];
      mPlaced := True;
    end;
    Result := Result + [mIndex];
  end;
  if not mPlaced then
  begin
    Result := Result + [cPartReturn];
  end;
end;

function TAtlasToolbarMeasure.Slots(const AOrder: TArray<Integer>): TArray<TAtlasToolbarSlot>;
var
  mIndex: Integer;
  mButton: TAtlasToolbarButton;
begin
  SetLength(Result, Length(AOrder));
  for mIndex := 0 to High(AOrder) do
  begin
    if AOrder[mIndex] = cPartReturn then
    begin
      Result[mIndex] := TAtlasToolbarSlot.Create(ReturnWidth, False, True);
    end
    else
    begin
      mButton := Bar.FButtons[AOrder[mIndex]];
      Result[mIndex] := TAtlasToolbarSlot.Create(ButtonWidth(mButton), mButton.IsSeparator, mButton.Pinned);
    end;
  end;
end;

{ TAtlasToolbarPainter }

procedure TAtlasToolbarPainter.Button(const ARect: TRect; const AButton: TAtlasToolbarButton; AHot: Boolean;
  const AText: string);
var
  mBack, mFore: TColor;
  mIcon, mPart: TRect;
  mIconSize, mDotSize: Integer;
begin
  mBack := ToColor(Bar.Colors.Gutter);
  mFore := ToColor(Bar.Colors.Text);
  Bar.Canvas.Brush.Style := bsSolid;
  if AButton.Pressed then
  begin
    mBack := ToColor(Bar.Colors.AccentSoft);
    mFore := ToColor(Bar.Colors.Accent);
    Bar.Canvas.Pen.Color := ToColor(Bar.Colors.Accent);
  end
  else if AHot and AButton.Enabled then
  begin
    mBack := ToColor(Bar.Colors.Selection);
    Bar.Canvas.Pen.Color := ToColor(Bar.Colors.Line);
  end;
  if AButton.Pressed or (AHot and AButton.Enabled) then
  begin
    Bar.Canvas.Brush.Color := mBack;
    Bar.Canvas.RoundRect(ARect.Left + Bar.Scale(1), ARect.Top + Bar.Scale(1), ARect.Right - Bar.Scale(1),
      ARect.Bottom - Bar.Scale(1), Bar.Scale(4), Bar.Scale(4));
  end;
  if not AButton.Enabled then
  begin
    mFore := ToColor(Bar.Colors.Muted);
  end;
  mIconSize := Bar.Scale(16);
  mIcon := Rect(ARect.Left + Bar.Scale(4), ARect.Top + (ARect.Height - mIconSize) div 2,
    ARect.Left + Bar.Scale(4) + mIconSize, ARect.Top + (ARect.Height - mIconSize) div 2 + mIconSize);
  Bar.Canvas.Font := Bar.Font;
  TAtlasGlyphPainter.Draw(Bar.Canvas, AButton.Icon, mIcon, mFore, mBack, AButton.Caption);
  if AText <> '' then
  begin
    Bar.Canvas.Font := Bar.Font;
    Bar.Canvas.Font.Color := mFore;
    Bar.Canvas.Brush.Style := bsClear;
    mPart := Rect(mIcon.Right + Bar.Scale(4), ARect.Top, ARect.Right - Bar.Scale(2), ARect.Bottom);
    DrawText(Bar.Canvas.Handle, PChar(AText), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  if AButton.Dot then
  begin
    mDotSize := Bar.Scale(6);
    Bar.Canvas.Brush.Style := bsSolid;
    Bar.Canvas.Brush.Color := ToColor(Bar.Colors.Warn);
    Bar.Canvas.Pen.Color := ToColor(Bar.Colors.Warn);
    Bar.Canvas.Ellipse(ARect.Right - Bar.Scale(3) - mDotSize, ARect.Top + Bar.Scale(2), ARect.Right - Bar.Scale(3),
      ARect.Top + Bar.Scale(2) + mDotSize);
  end;
end;

procedure TAtlasToolbarPainter.Separator(const ARect: TRect);
var
  mMiddle: Integer;
begin
  mMiddle := (ARect.Left + ARect.Right) div 2;
  Bar.Canvas.Pen.Color := ToColor(Bar.Colors.Line);
  Bar.Canvas.MoveTo(mMiddle, ARect.Top + Bar.Scale(4));
  Bar.Canvas.LineTo(mMiddle, ARect.Bottom - Bar.Scale(4));
end;

procedure TAtlasToolbarPainter.Return(const ARect: TRect; const AText: string);
var
  mIconSize: Integer;
  mArea: TRect;
begin
  // Rücksprung: Akzentfarbe, Zeilennummer fett daneben.
  mIconSize := Bar.Scale(16);
  Bar.Canvas.Brush.Style := bsSolid;
  Bar.Canvas.Brush.Color := ToColor(Bar.Colors.AccentSoft);
  Bar.Canvas.Pen.Color := ToColor(Bar.Colors.Accent);
  Bar.Canvas.RoundRect(ARect.Left + Bar.Scale(1), ARect.Top + Bar.Scale(1), ARect.Right - Bar.Scale(1),
    ARect.Bottom - Bar.Scale(1), Bar.Scale(4), Bar.Scale(4));
  TAtlasGlyphPainter.Draw(Bar.Canvas, TAtlasToolbarIcon.Return, Rect(ARect.Left + Bar.Scale(4),
    ARect.Top + (ARect.Height - mIconSize) div 2, ARect.Left + Bar.Scale(4) + mIconSize,
    ARect.Top + (ARect.Height - mIconSize) div 2 + mIconSize), ToColor(Bar.Colors.Accent),
    ToColor(Bar.Colors.AccentSoft), '');
  Bar.Canvas.Font := Bar.Font;
  Bar.Canvas.Font.Style := [fsBold];
  Bar.Canvas.Font.Color := ToColor(Bar.Colors.Accent);
  Bar.Canvas.Brush.Style := bsClear;
  mArea := Rect(ARect.Left + Bar.Scale(8) + mIconSize, ARect.Top, ARect.Right - Bar.Scale(2), ARect.Bottom);
  DrawText(Bar.Canvas.Handle, PChar(AText), -1, mArea, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Bar.Canvas.Font := Bar.Font;
end;

{ TAtlasToolbarMenu }

constructor TAtlasToolbarMenu.CreateFor(ABar: TAtlasEditorToolbar);
begin
  inherited Create(ABar);
  FBar := ABar;
end;

procedure TAtlasToolbarMenu.AddButton(const AButton: TAtlasToolbarButton);
var
  mItem: TMenuItem;
begin
  if AButton.IsSeparator then
  begin
    Items.Add(NewLine);
    Exit;
  end;
  mItem := TMenuItem.Create(Self);
  mItem.Caption := StringReplace(AButton.Caption, '&', '&&', [rfReplaceAll]);
  mItem.Hint := AButton.Hint;
  mItem.Enabled := AButton.Enabled;
  mItem.Checked := AButton.Pressed;
  mItem.Tag := Length(FIds);
  FIds := FIds + [AButton.Id];
  mItem.OnClick := CommandClick;
  Items.Add(mItem);
end;

procedure TAtlasToolbarMenu.AddCustomize(const ACaption: string);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(Self);
  mItem.Caption := StringReplace(ACaption, '&', '&&', [rfReplaceAll]);
  mItem.OnClick := CustomizeClick;
  Items.Add(mItem);
end;

procedure TAtlasToolbarMenu.CommandClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FIds)) and Assigned(FBar.FEvents.Command) then
  begin
    FBar.FEvents.Command(FIds[mIndex]);
  end;
end;

procedure TAtlasToolbarMenu.CustomizeClick(Sender: TObject);
begin
  if Assigned(FBar.FEvents.Customize) then
  begin
    FBar.FEvents.Customize();
  end;
end;

{ TAtlasEditorToolbar }

constructor TAtlasEditorToolbar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTexts.More := '»';
  FTexts.Gear := '';
  FTexts.Customize := '';
  FPlaces := TAtlasToolbarPlaces.Create(nil);
end;

class function TAtlasEditorToolbar.BaseHeight: Integer;
begin
  Result := 24;
end;

procedure TAtlasEditorToolbar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  FLaidOut := False;
end;

procedure TAtlasEditorToolbar.SetButtons(const AButtons: TArray<TAtlasToolbarButton>);
var
  mIndex: Integer;
  mSame: Boolean;
begin
  mSame := Length(AButtons) = Length(FButtons);
  mIndex := 0;
  while mSame and (mIndex <= High(AButtons)) do
  begin
    mSame := AButtons[mIndex].SameAs(FButtons[mIndex]);
    Inc(mIndex);
  end;
  if mSame then
  begin
    Exit;
  end;
  FButtons := AButtons;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetReturn(AShown: Boolean; const AText, AHint: string);
begin
  if (AShown = FReturn.Shown) and (AText = FReturn.Text) and (AHint = FReturn.Hint) then
  begin
    Exit;
  end;
  FReturn.Shown := AShown;
  FReturn.Text := AText;
  FReturn.Hint := AHint;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetLabels(AValue: Boolean);
begin
  if AValue = FLabels then
  begin
    Exit;
  end;
  FLabels := AValue;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorToolbar.SetInline(AValue: Boolean);
begin
  if AValue = FInline then
  begin
    Exit;
  end;
  FInline := AValue;
  // In der Brotkrumenzeile bestimmt deren Höhe die Höhe (alRight).
  FixedHeight := not FInline;
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

procedure TAtlasEditorToolbar.Layout;
var
  mMeasure: TAtlasToolbarMeasure;
  mOrder: TArray<Integer>;
  mSlots: TArray<TAtlasToolbarSlot>;
  mWidth: Integer;
begin
  if FLaidOut or not HandleAllocated then
  begin
    Exit;
  end;
  FLaidOut := True;
  mMeasure.Bar := Self;
  mOrder := mMeasure.Entries;
  mSlots := mMeasure.Slots(mOrder);
  mWidth := Scale(cBaseButton);
  FPlaces := TAtlasToolbarPlaces.Create(FButtons);
  FPlaces.Arrange(mOrder, mSlots, TAtlasToolbarLayout.Fit(mSlots, ClientWidth - 2 * Scale(cMargin) - mWidth, mWidth),
    Rect(Scale(cMargin), Scale(1), ClientWidth - Scale(cMargin), ClientHeight - Scale(1)), mWidth);
end;

function TAtlasEditorToolbar.PreferredWidth: Integer;
var
  mMeasure: TAtlasToolbarMeasure;
begin
  mMeasure.Bar := Self;
  Result := TAtlasToolbarLayout.FullWidth(mMeasure.Slots(mMeasure.Entries)) + 2 * Scale(cMargin) + Scale(cBaseButton);
  if FInline then
  begin
    Inc(Result, Scale(cMargin));
  end;
end;

function TAtlasEditorToolbar.Places: TAtlasToolbarPlaces;
begin
  Layout;
  Result := FPlaces;
end;

function TAtlasEditorToolbar.PartAt(X, Y: Integer): Integer;
begin
  Layout;
  Result := FPlaces.PartAt(Point(X, Y));
end;

function TAtlasEditorToolbar.PartHint(APart: Integer): string;
begin
  case APart of
    cPartNone:
      Result := '';
    cPartReturn:
      Result := FReturn.Hint;
    cPartMore:
      Result := FTexts.More;
    cPartGear:
      Result := FTexts.Gear;
  else
    Result := FButtons[APart].Hint;
    if Result = '' then
    begin
      Result := FButtons[APart].Caption;
    end;
  end;
end;

function TAtlasEditorToolbar.PartEnabled(APart: Integer): Boolean;
begin
  Result := (APart < 0) or FButtons[APart].Enabled;
end;

function TAtlasEditorToolbar.HintAt(AX, AY: Integer): string;
begin
  Result := PartHint(PartAt(AX, AY));
end;

procedure TAtlasEditorToolbar.Paint;
var
  mIndex: Integer;
  mPainter: TAtlasToolbarPainter;
begin
  Layout;
  mPainter.Bar := Self;
  // Untere Linie wie die Brotkrumenleiste, Inline dazu ein Trennstrich links.
  PaintChrome(False);
  if FInline then
  begin
    Canvas.MoveTo(0, Scale(4));
    Canvas.LineTo(0, ClientHeight - Scale(4));
  end;
  for mIndex := 0 to High(FPlaces.Rects) do
  begin
    if FPlaces.Rects[mIndex].IsEmpty then
    begin
      Continue;
    end;
    if FButtons[mIndex].IsSeparator then
    begin
      mPainter.Separator(FPlaces.Rects[mIndex]);
    end
    else if FLabels then
    begin
      mPainter.Button(FPlaces.Rects[mIndex], FButtons[mIndex], Hot = mIndex, FButtons[mIndex].Caption);
    end
    else
    begin
      mPainter.Button(FPlaces.Rects[mIndex], FButtons[mIndex], Hot = mIndex, '');
    end;
  end;
  if not FPlaces.Return.IsEmpty then
  begin
    mPainter.Return(FPlaces.Return, FReturn.Text);
  end;
  if not FPlaces.More.IsEmpty then
  begin
    mPainter.Button(FPlaces.More, TAtlasToolbarButton.Create('', '', '', TAtlasToolbarIcon.More), Hot = cPartMore, '');
  end;
  mPainter.Button(FPlaces.Gear, TAtlasToolbarButton.Create('', '', '', TAtlasToolbarIcon.Gear), Hot = cPartGear, '');
end;

procedure TAtlasEditorToolbar.ClickAt(AX, AY: Integer);
begin
  Fire(PartAt(AX, AY));
end;

procedure TAtlasEditorToolbar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
begin
  Fire(APart);
end;

procedure TAtlasEditorToolbar.ContextMenu(const APoint: TPoint; APart: Integer);
begin
  ShowMenu(ClientToScreen(APoint), False);
end;

function TAtlasEditorToolbar.KeyboardMenuPoint: TPoint;
begin
  Layout;
  Result := Point(FPlaces.Gear.Left, FPlaces.Gear.Bottom);
end;

procedure TAtlasEditorToolbar.Fire(APart: Integer);
begin
  case APart of
    cPartNone:
      ;
    cPartReturn:
      if Assigned(FEvents.Return) then
      begin
        FEvents.Return();
      end;
    cPartMore:
      ShowMenu(ClientToScreen(Point(FPlaces.More.Left, FPlaces.More.Bottom)), True);
    cPartGear:
      if Assigned(FEvents.Customize) then
      begin
        FEvents.Customize();
      end;
  else
    if not FButtons[APart].Enabled then
    begin
      TAtlasGuard.Log(Format('Editorleiste: Klick auf gesperrten Knopf %s (%s)', [FButtons[APart].Id,
        PartHint(APart)]));
    end
    else if Assigned(FEvents.Command) then
    begin
      FEvents.Command(FButtons[APart].Id);
    end;
  end;
end;

procedure TAtlasEditorToolbar.ShowMenu(const APoint: TPoint; AOverflow: Boolean);
var
  mMenu: TAtlasToolbarMenu;
  mIndex: Integer;
begin
  Layout;
  FreeAndNil(FMenu);
  mMenu := TAtlasToolbarMenu.CreateFor(Self);
  FMenu := mMenu;
  if AOverflow then
  begin
    for mIndex in FPlaces.Overflow do
    begin
      mMenu.AddButton(FButtons[mIndex]);
    end;
    if mMenu.Items.Count > 0 then
    begin
      mMenu.Items.Add(NewLine);
    end;
  end;
  mMenu.AddCustomize(FTexts.Customize);
  mMenu.Popup(APoint.X, APoint.Y);
end;

end.
