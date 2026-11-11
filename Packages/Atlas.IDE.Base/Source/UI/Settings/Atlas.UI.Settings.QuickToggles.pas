unit Atlas.UI.Settings.QuickToggles;

// Fenster der Schnellschalter (#604) im Stil der Atlas-Popups (#411), wie das
// Fenster des Statusfelds (#591): oben „Atlas · Schnellschalter“, darunter
// die Schalter nach Seiten gruppiert, je Zeile ein Kästchen, die Beschriftung
// und rechts „Projekt“ (atlas.json setzt den Wert) bzw. „Sitzung“ (gilt nur
// für diese Sitzung). Unten „Alles aus für diese Sitzung“ bzw. „Alles wieder
// an“. Ein Klick oder Leertaste schaltet; das Fenster bleibt offen und zeigt
// danach, was SetItems bekommt. Schalter mit Projektwert schließen vorher das
// Fenster, weil die IDE-Schicht nachfragt, wo die Änderung gelten soll. Esc
// oder ein Klick daneben schließt. Das Fenster kennt keine Einstellung selbst:
// neue Schalter im Katalog erscheinen ohne Änderung hier.
// Gruppen lassen sich ein- und ausklappen: Klick, Leertaste oder Enter auf der
// Überschrift. Eingeklappt zeigt sie die Zahl ihrer Schalter. Der Zustand gilt
// für die IDE-Sitzung (class var), das Fenster öffnet wie zuletzt verlassen.
// Damit das Fenster handlich bleibt: beim ersten Öffnen nur die erste Seite
// offen, Aufklappen schließt die anderen (Akkordeon), höchstens 80 % der
// Arbeitsfläche hoch; darüber Bildlauf mit Mausrad und Pfeiltasten, rechts ein
// schmaler Balken.
// Aufbau: Zeilen und Ein-/Ausklappen in TAtlasQuickToggleRows, Bildlauf in
// TAtlasQuickToggleScroll, Maße und Zeichnen in Hilfsrecords im
// Implementationsteil (TToggleGeometry, TTogglePainter).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.QuickToggles;

type
  TAtlasQuickToggleRow = record
    /// <summary>-1: Überschrift einer Seite; sonst Index in den Schaltern.</summary>
    Item: Integer;
    Text: string;
    /// <summary>Überschrift: Zahl der Schalter der Seite.</summary>
    Count: Integer;
  end;

  /// <summary>Zeilen des Fensters: je Seite eine Überschrift, darunter ihre Schalter; eingeklappte Seiten nur mit
  /// der Überschrift. Welche Seiten eingeklappt sind, gilt für die IDE-Sitzung.</summary>
  TAtlasQuickToggleRows = record
  private
    FItems: TArray<TAtlasQuickToggleItem>;
    FRows: TArray<TAtlasQuickToggleRow>;
    procedure AddPage(const APage: string);
    procedure AddToggle(AIndex: Integer);
  public
    /// <summary>Zeilen aus AItems bilden; beim ersten Mal in der Sitzung ist nur die erste Seite offen.</summary>
    procedure Build(const AItems: TArray<TAtlasQuickToggleItem>);
    /// <summary>Seite APage ein- bzw. ausklappen (Aufklappen schließt die anderen) und die Zeilen neu bilden;
    /// Ergebnis ist die Zeile ihrer Überschrift, -1 ohne.</summary>
    function ToggleGroup(const APage: string): Integer;
    function Count: Integer;
    function Text(ARow: Integer): string;
    /// <summary>Index des Schalters der Zeile; -1 bei einer Überschrift.</summary>
    function Item(ARow: Integer): Integer;
    function Row(ARow: Integer): TAtlasQuickToggleRow;
    /// <summary>ARow ist eine Zeile mit Schalter.</summary>
    function IsToggle(ARow: Integer): Boolean;
    /// <summary>Schalter der Zeile ARow (nur bei IsToggle).</summary>
    function ToggleOf(ARow: Integer): TAtlasQuickToggleItem;
    class function IsCollapsed(const APage: string): Boolean; static;
    /// <summary>Alle Gruppen ausklappen (Tests).</summary>
    class procedure ExpandAll; static;
    /// <summary>Wie beim ersten Öffnen der Sitzung (Tests).</summary>
    class procedure ResetCollapse; static;
  end;

  /// <summary>Bildlauf: erste sichtbare Zeile und Zahl der Zeilen, die ins Fenster passen.</summary>
  TAtlasQuickToggleScroll = record
    First: Integer;
    Visible: Integer;
    /// <summary>First in die Grenzen bei ACount Zeilen bringen.</summary>
    procedure Clamp(ACount: Integer);
    /// <summary>So weit rollen, dass ARow sichtbar ist (-1: nur Grenzen).</summary>
    procedure Reveal(ARow, ACount: Integer);
    /// <summary>Letzte sichtbare Zeile bei ACount Zeilen.</summary>
    function Last(ACount: Integer): Integer;
  end;

  TAtlasQuickToggleWindow = class(TForm)
  private
    FScroll: TAtlasQuickToggleScroll;
    FColors: TAtlasColors;
    FRows: TAtlasQuickToggleRows;
    FAllOff: Boolean;
    FHot: Integer;
    FClosing: Boolean;
    FAllButton: TButton;
    FOnToggle: TProc<TAtlasQuickToggleItem>;
    FOnOpenSetting: TProc<TAtlasQuickToggleItem>;
    /// <summary>Maus über dem Symbol „Einstellung öffnen“ dieser Zeile; -1 ohne.</summary>
    FHotOpen: Integer;
    FOnAllOff: TProc;
    FAnchor: TPoint;
    procedure OpenRow(ARow: Integer);
    procedure Layout;
    procedure MoveHot(ADelta: Integer);
    /// <summary>Unterkante am Anker, aber nie über den oberen Rand der Arbeitsfläche hinaus.</summary>
    procedure PlaceAboveAnchor;
    procedure ToggleRow(ARow: Integer);
    procedure ToggleGroup(const APage: string);
    procedure AllClick(Sender: TObject);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Deactivate; override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateToggles(AOwner: TComponent; const AColors: TAtlasColors);
    /// <summary>Schalter und „Alles aus“ neu setzen (auch bei offenem Fenster).</summary>
    procedure SetItems(const AItems: TArray<TAtlasQuickToggleItem>; AAllOff: Boolean);
    /// <summary>Zeigt das Fenster mit der linken unteren Ecke an AAnchor (Bildschirm).</summary>
    procedure ShowAbove(const AAnchor: TPoint);
    /// <summary>Schließt; das Fenster gibt sich danach selbst frei.</summary>
    procedure Dismiss;
    /// <summary>Zum Testen: Zeile ARow anklicken (Überschriften klappen ein und aus).</summary>
    procedure ClickRow(ARow: Integer);
    /// <summary>Zum Testen: Symbol „Einstellung öffnen“ der Zeile ARow anklicken.</summary>
    procedure ClickOpen(ARow: Integer);
    /// <summary>Zeilen samt Überschriften (Tests).</summary>
    property Rows: TAtlasQuickToggleRows read FRows;
    property AllButton: TButton read FAllButton;
    property HotRow: Integer read FHot;
    /// <summary>Schalter umschalten; bei Projektwerten erst nach dem Schließen.</summary>
    property OnToggle: TProc<TAtlasQuickToggleItem> read FOnToggle write FOnToggle;
    /// <summary>Symbol rechts bzw. Strg+Enter: die Einstellung in Tools › Optionen öffnen (nach dem Schließen).
    /// </summary>
    property OnOpenSetting: TProc<TAtlasQuickToggleItem> read FOnOpenSetting write FOnOpenSetting;
    /// <summary>„Alles aus für diese Sitzung“ bzw. „Alles wieder an“.</summary>
    property OnAllOff: TProc read FOnAllOff write FOnAllOff;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Settings.PageNames,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

var
  /// <summary>Eingeklappte Seiten, für die IDE-Sitzung.</summary>
  GCollapsed: TArray<string>;
  /// <summary>Schon einmal geöffnet: Beim ersten Mal ist nur die erste Seite offen.</summary>
  GCollapseInitialized: Boolean;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>Kennzeichen rechts in der Zeile: „Sitzung“ bzw. „Projekt“; '' ohne.</summary>
function TagText(const AItem: TAtlasQuickToggleItem): string;
begin
  Result := '';
  if AItem.Session then
  begin
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesSession);
  end
  else if AItem.Project then
  begin
    Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesProject);
  end;
end;

/// <summary>Alle Seiten von AItems außer AOpen einklappen.</summary>
procedure CollapseAllBut(const AItems: TArray<TAtlasQuickToggleItem>; const AOpen: string);
var
  mItem: TAtlasQuickToggleItem;
begin
  GCollapsed := nil;
  for mItem in AItems do
  begin
    if not SameText(mItem.Toggle.Page, AOpen) and not TAtlasQuickToggleRows.IsCollapsed(mItem.Toggle.Page) then
    begin
      GCollapsed := GCollapsed + [mItem.Toggle.Page];
    end;
  end;
end;

{ TAtlasQuickToggleRows }

class function TAtlasQuickToggleRows.IsCollapsed(const APage: string): Boolean;
var
  mPage: string;
begin
  for mPage in GCollapsed do
  begin
    if SameText(mPage, APage) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TAtlasQuickToggleRows.ExpandAll;
begin
  GCollapsed := nil;
  GCollapseInitialized := True;
end;

class procedure TAtlasQuickToggleRows.ResetCollapse;
begin
  GCollapsed := nil;
  GCollapseInitialized := False;
end;

procedure TAtlasQuickToggleRows.AddPage(const APage: string);
var
  mRow: TAtlasQuickToggleRow;
begin
  mRow := Default(TAtlasQuickToggleRow);
  mRow.Item := -1;
  mRow.Text := TAtlasSettingsPageNames.Caption(APage, TAtlasStrings.Language = TAtlasLanguage.English);
  FRows := FRows + [mRow];
end;

procedure TAtlasQuickToggleRows.AddToggle(AIndex: Integer);
var
  mRow: TAtlasQuickToggleRow;
begin
  mRow := Default(TAtlasQuickToggleRow);
  mRow.Item := AIndex;
  mRow.Text := FItems[AIndex].Toggle.Caption;
  // Kennzeichen als Text (#834, Barrierefreiheit #447).
  if FItems[AIndex].Toggle.Experimental then
  begin
    mRow.Text := mRow.Text + '  [' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExperimentalTag) + ']';
  end;
  FRows := FRows + [mRow];
end;

procedure TAtlasQuickToggleRows.Build(const AItems: TArray<TAtlasQuickToggleItem>);
var
  mIndex, mHeader: Integer;
  mPage: string;
begin
  FItems := AItems;
  // Erstes Öffnen in der Sitzung: nur die erste Seite offen, sonst wird das Fenster höher als der Bildschirm.
  if not GCollapseInitialized and (FItems <> nil) then
  begin
    GCollapseInitialized := True;
    GCollapsed := nil;
    CollapseAllBut(FItems, FItems[0].Toggle.Page);
  end;
  FRows := nil;
  mPage := #0;
  mHeader := -1;
  for mIndex := 0 to High(FItems) do
  begin
    if not SameText(FItems[mIndex].Toggle.Page, mPage) then
    begin
      mPage := FItems[mIndex].Toggle.Page;
      AddPage(mPage);
      mHeader := High(FRows);
    end;
    Inc(FRows[mHeader].Count);
    // Eingeklappt: nur die Überschrift.
    if not IsCollapsed(mPage) then
    begin
      AddToggle(mIndex);
    end;
  end;
end;

function TAtlasQuickToggleRows.ToggleGroup(const APage: string): Integer;
var
  mIndex: Integer;
begin
  if IsCollapsed(APage) then
  begin
    // Akkordeon: Aufklappen schließt die anderen Seiten, damit das Fenster handlich bleibt.
    CollapseAllBut(FItems, APage);
  end
  else
  begin
    GCollapsed := GCollapsed + [APage];
  end;
  Build(FItems);
  Result := -1;
  for mIndex := 0 to High(FRows) do
  begin
    if (FRows[mIndex].Item < 0) and SameText(FRows[mIndex].Text, APage) then
    begin
      Result := mIndex;
    end;
  end;
end;

function TAtlasQuickToggleRows.Count: Integer;
begin
  Result := Length(FRows);
end;

function TAtlasQuickToggleRows.Text(ARow: Integer): string;
begin
  Result := FRows[ARow].Text;
end;

function TAtlasQuickToggleRows.Item(ARow: Integer): Integer;
begin
  Result := FRows[ARow].Item;
end;

function TAtlasQuickToggleRows.Row(ARow: Integer): TAtlasQuickToggleRow;
begin
  Result := FRows[ARow];
end;

function TAtlasQuickToggleRows.IsToggle(ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(FRows)) and (FRows[ARow].Item >= 0);
end;

function TAtlasQuickToggleRows.ToggleOf(ARow: Integer): TAtlasQuickToggleItem;
begin
  Result := FItems[FRows[ARow].Item];
end;

{ TAtlasQuickToggleScroll }

procedure TAtlasQuickToggleScroll.Clamp(ACount: Integer);
begin
  First := EnsureRange(First, 0, Max(0, ACount - Visible));
end;

procedure TAtlasQuickToggleScroll.Reveal(ARow, ACount: Integer);
begin
  if ARow >= 0 then
  begin
    if ARow < First then
    begin
      First := ARow;
    end
    else if ARow >= First + Visible then
    begin
      First := ARow - Visible + 1;
    end;
  end;
  Clamp(ACount);
end;

function TAtlasQuickToggleScroll.Last(ACount: Integer): Integer;
begin
  Result := Min(ACount - 1, First + Visible - 1);
end;

type
  /// <summary>Maße des Fensters: Zeilenhöhe, Kopf, Knopfleiste, Lage der Zeilen und des Symbols.</summary>
  TToggleGeometry = record
    Window: TAtlasQuickToggleWindow;
    class function Create(AWindow: TAtlasQuickToggleWindow): TToggleGeometry; static;
    function RowHeight: Integer;
    function HeaderHeight: Integer;
    function ButtonsHeight: Integer;
    function RowRect(AIndex: Integer): TRect;
    /// <summary>Sichtbare Zeile unter APoint; -1 ohne.</summary>
    function RowAt(const APoint: TPoint): Integer;
    /// <summary>Symbol „Einstellung öffnen“ rechts in einer Schalterzeile; leer sonst.</summary>
    function OpenRect(ARow: Integer): TRect;
  end;

class function TToggleGeometry.Create(AWindow: TAtlasQuickToggleWindow): TToggleGeometry;
begin
  Result.Window := AWindow;
end;

function TToggleGeometry.RowHeight: Integer;
begin
  Window.Canvas.Font := Window.Font;
  Result := Window.Canvas.TextHeight('Wg') + Window.ScaleValue(8);
end;

function TToggleGeometry.HeaderHeight: Integer;
begin
  Result := RowHeight + Window.ScaleValue(6);
end;

function TToggleGeometry.ButtonsHeight: Integer;
begin
  Result := Window.ScaleValue(40);
end;

function TToggleGeometry.RowRect(AIndex: Integer): TRect;
var
  mOffset: Integer;
begin
  mOffset := AIndex - Window.FScroll.First;
  Result := Rect(Window.ScaleValue(4), HeaderHeight + mOffset * RowHeight, Window.ClientWidth - Window.ScaleValue(4),
    HeaderHeight + (mOffset + 1) * RowHeight);
end;

function TToggleGeometry.RowAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := Window.FScroll.First to Window.FScroll.Last(Window.FRows.Count) do
  begin
    if PtInRect(RowRect(mIndex), APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TToggleGeometry.OpenRect(ARow: Integer): TRect;
var
  mRow: TRect;
  mSize: Integer;
begin
  Result := TRect.Empty;
  if not Window.FRows.IsToggle(ARow) then
  begin
    Exit;
  end;
  mRow := RowRect(ARow);
  mSize := Window.ScaleValue(16);
  // Rechts, mit Abstand zum Bildlaufbalken.
  Result := Rect(mRow.Right - Window.ScaleValue(8) - mSize, (mRow.Top + mRow.Bottom - mSize) div 2,
    mRow.Right - Window.ScaleValue(8), (mRow.Top + mRow.Bottom + mSize) div 2);
end;

type
  /// <summary>Zeichnet das Fenster: Kopf, Überschriften, Schalterzeilen, Bildlaufbalken und Rahmen.</summary>
  TTogglePainter = record
    Window: TAtlasQuickToggleWindow;
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Geometry: TToggleGeometry;
    class function Create(AWindow: TAtlasQuickToggleWindow): TTogglePainter; static;
    procedure Text(const AText: string; ARect: TRect; AFlags: Cardinal);
    procedure Header;
    procedure HotBackground(AIndex: Integer; const ARow: TRect);
    procedure PageRow(AIndex: Integer; const ARow: TRect);
    /// <summary>Kästchen: gefüllt in Akzentfarbe, wenn an; Ergebnis ist sein Rechteck.</summary>
    function CheckBox(const ARow: TRect; AChecked: Boolean): TRect;
    procedure OpenIcon(const ARect: TRect; AHot: Boolean);
    procedure ToggleRow(AIndex: Integer; const ARow: TRect);
    procedure ScrollBar;
    procedure Frame;
    procedure Paint;
  end;

class function TTogglePainter.Create(AWindow: TAtlasQuickToggleWindow): TTogglePainter;
begin
  Result.Window := AWindow;
  Result.Canvas := AWindow.Canvas;
  Result.Colors := AWindow.FColors;
  Result.Geometry := TToggleGeometry.Create(AWindow);
end;

procedure TTogglePainter.Text(const AText: string; ARect: TRect; AFlags: Cardinal);
begin
  DrawText(Canvas.Handle, PChar(AText), -1, ARect, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or AFlags);
end;

procedure TTogglePainter.Header;
var
  mPart: TRect;
begin
  // Kopf: „Atlas · Schnellschalter“, bei „Alles aus“ der Hinweis darauf.
  mPart := Rect(Window.ScaleValue(12), 0, Window.ClientWidth - Window.ScaleValue(8), Geometry.HeaderHeight);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Text);
  Text('Atlas · ' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesTitle), mPart, 0);
  Canvas.Font.Style := [];
  if Window.FAllOff then
  begin
    Canvas.Font.Color := ToColor(Colors.Warn);
    Text(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOffActive), mPart, DT_RIGHT);
  end;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, Geometry.HeaderHeight - Window.ScaleValue(3));
  Canvas.LineTo(Window.ClientWidth, Geometry.HeaderHeight - Window.ScaleValue(3));
end;

procedure TTogglePainter.HotBackground(AIndex: Integer; const ARow: TRect);
begin
  if AIndex = Window.FHot then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.FillRect(ARow);
  end;
  Canvas.Brush.Style := bsClear;
end;

procedure TTogglePainter.PageRow(AIndex: Integer; const ARow: TRect);
var
  mRow: TAtlasQuickToggleRow;
  mText: string;
begin
  // Überschrift der Seite: ▾ ausgeklappt, ▸ eingeklappt mit der Zahl der Schalter.
  mRow := Window.FRows.Row(AIndex);
  HotBackground(AIndex, ARow);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Muted);
  if TAtlasQuickToggleRows.IsCollapsed(mRow.Text) then
  begin
    mText := #$25B8' ' + mRow.Text + ' (' + IntToStr(mRow.Count) + ')';
  end
  else
  begin
    mText := #$25BE' ' + mRow.Text;
  end;
  Text(mText, Rect(ARow.Left + Window.ScaleValue(6), ARow.Top, ARow.Right - Window.ScaleValue(6), ARow.Bottom), 0);
  Canvas.Font.Style := [];
end;

function TTogglePainter.CheckBox(const ARow: TRect; AChecked: Boolean): TRect;
var
  mBox: Integer;
begin
  mBox := Window.ScaleValue(12);
  Result := Rect(ARow.Left + Window.ScaleValue(14), (ARow.Top + ARow.Bottom - mBox) div 2,
    ARow.Left + Window.ScaleValue(14) + mBox, (ARow.Top + ARow.Bottom + mBox) div 2);
  Canvas.Pen.Color := ToColor(Colors.Accent);
  Canvas.Brush.Style := bsClear;
  if AChecked then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Accent);
  end;
  Canvas.Rectangle(Result);
  if AChecked then
  begin
    Canvas.Pen.Color := ToColor(Colors.Surface);
    Canvas.Pen.Width := Max(1, Window.ScaleValue(2));
    Canvas.MoveTo(Result.Left + mBox div 5, Result.Top + mBox div 2);
    Canvas.LineTo(Result.Left + mBox * 2 div 5, Result.Bottom - mBox div 4);
    Canvas.LineTo(Result.Right - mBox div 5, Result.Top + mBox div 4);
    Canvas.Pen.Width := 1;
  end;
  Canvas.Brush.Style := bsClear;
end;

procedure TTogglePainter.OpenIcon(const ARect: TRect; AHot: Boolean);
var
  mInset, mMid, mOne: Integer;
begin
  // Kasten, oben rechts offen, mit Pfeil nach rechts oben: „Einstellung öffnen“.
  Canvas.Pen.Color := ToColor(Colors.Muted);
  if AHot then
  begin
    Canvas.Pen.Color := ToColor(Colors.Accent);
  end;
  Canvas.Pen.Width := Max(1, Window.ScaleValue(1));
  mInset := Window.ScaleValue(3);
  mOne := Window.ScaleValue(1);
  mMid := (ARect.Left + ARect.Right) div 2;
  Canvas.MoveTo(mMid, ARect.Top + mInset);
  Canvas.LineTo(ARect.Left + mInset, ARect.Top + mInset);
  Canvas.LineTo(ARect.Left + mInset, ARect.Bottom - mInset);
  Canvas.LineTo(ARect.Right - mInset, ARect.Bottom - mInset);
  Canvas.LineTo(ARect.Right - mInset, (ARect.Top + ARect.Bottom) div 2);
  // Pfeil.
  Canvas.MoveTo(mMid - mOne, (ARect.Top + ARect.Bottom) div 2 + mOne);
  Canvas.LineTo(ARect.Right - mOne, ARect.Top + mOne);
  Canvas.MoveTo(ARect.Right - mOne - Window.ScaleValue(5), ARect.Top + mOne);
  Canvas.LineTo(ARect.Right - mOne, ARect.Top + mOne);
  Canvas.LineTo(ARect.Right - mOne, ARect.Top + mOne + Window.ScaleValue(5));
  Canvas.Pen.Width := 1;
end;

procedure TTogglePainter.ToggleRow(AIndex: Integer; const ARow: TRect);
var
  mItem: TAtlasQuickToggleItem;
  mCheck, mPart: TRect;
  mTag: string;
begin
  mItem := Window.FRows.ToggleOf(AIndex);
  HotBackground(AIndex, ARow);
  mCheck := CheckBox(ARow, mItem.Checked);
  // Rechts in jeder Zeile das Symbol „Einstellung öffnen“, unter der Maus in Akzentfarbe.
  if Assigned(Window.FOnOpenSetting) then
  begin
    OpenIcon(Geometry.OpenRect(AIndex), AIndex = Window.FHotOpen);
  end;
  mPart := Rect(mCheck.Right + Window.ScaleValue(8), ARow.Top, Geometry.OpenRect(AIndex).Left - Window.ScaleValue(6),
    ARow.Bottom);
  mTag := TagText(mItem);
  if mTag <> '' then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
    Text(mTag, mPart, DT_RIGHT);
    mPart.Right := mPart.Right - Canvas.TextWidth(mTag) - Window.ScaleValue(8);
  end;
  Canvas.Font.Color := ToColor(Colors.Text);
  Text(Window.FRows.Text(AIndex), mPart, DT_END_ELLIPSIS);
end;

procedure TTogglePainter.ScrollBar;
var
  mTrack, mThumb: TRect;
  mCount, mVisible: Integer;
begin
  // Mehr Zeilen als Platz: schmaler Balken rechts zeigt Lage und Anteil.
  mCount := Window.FRows.Count;
  mVisible := Window.FScroll.Visible;
  if mCount <= mVisible then
  begin
    Exit;
  end;
  mTrack := Rect(Window.ClientWidth - Window.ScaleValue(5), Geometry.HeaderHeight,
    Window.ClientWidth - Window.ScaleValue(2), Geometry.HeaderHeight + mVisible * Geometry.RowHeight);
  mThumb := mTrack;
  mThumb.Top := mTrack.Top + MulDiv(mTrack.Height, Window.FScroll.First, mCount);
  mThumb.Bottom := mTrack.Top + MulDiv(mTrack.Height, Window.FScroll.First + mVisible, mCount);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Muted);
  Canvas.FillRect(mThumb);
end;

procedure TTogglePainter.Frame;
begin
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, Window.ClientHeight - Geometry.ButtonsHeight);
  Canvas.LineTo(Window.ClientWidth, Window.ClientHeight - Geometry.ButtonsHeight);
  // Rahmen des Fensters in Akzentfarbe.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(Colors.Accent);
  Canvas.Rectangle(Window.ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

procedure TTogglePainter.Paint;
var
  mIndex: Integer;
  mRow: TRect;
begin
  Canvas.Font := Window.Font;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(Window.ClientRect);
  Header;
  for mIndex := Window.FScroll.First to Window.FScroll.Last(Window.FRows.Count) do
  begin
    mRow := Geometry.RowRect(mIndex);
    if Window.FRows.IsToggle(mIndex) then
    begin
      ToggleRow(mIndex, mRow);
    end
    else
    begin
      PageRow(mIndex, mRow);
    end;
  end;
  ScrollBar;
  Frame;
end;

{ TAtlasQuickToggleWindow }

constructor TAtlasQuickToggleWindow.CreateToggles(AOwner: TComponent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  FHot := -1;
  FHotOpen := -1;
  BorderStyle := bsNone;
  KeyPreview := True;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesTitle);
  FAllButton := TButton.Create(Self);
  FAllButton.Parent := Self;
  FAllButton.OnClick := AllClick;
  FAllButton.TabStop := False;
  SetItems(nil, False);
end;

procedure TAtlasQuickToggleWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TAtlasQuickToggleWindow.OpenRow(ARow: Integer);
var
  mItem: TAtlasQuickToggleItem;
  mHandler: TProc<TAtlasQuickToggleItem>;
begin
  mHandler := FOnOpenSetting;
  if not FRows.IsToggle(ARow) or FClosing or not Assigned(mHandler) then
  begin
    Exit;
  end;
  mItem := FRows.ToggleOf(ARow);
  // Tools › Optionen ist modal: erst schließen, dann öffnen.
  Dismiss;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
    procedure
    begin
      mHandler(mItem);
    end);
end;

procedure TAtlasQuickToggleWindow.ClickOpen(ARow: Integer);
begin
  OpenRow(ARow);
end;

function TAtlasQuickToggleWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  // Drei Zeilen je Raste, wie im Editor.
  if WheelDelta > 0 then
  begin
    Dec(FScroll.First, 3);
  end
  else
  begin
    Inc(FScroll.First, 3);
  end;
  FScroll.Clamp(FRows.Count);
  Invalidate;
  Result := True;
end;

procedure TAtlasQuickToggleWindow.ToggleGroup(const APage: string);
begin
  // Auswahl bleibt auf der Überschrift.
  FHot := FRows.ToggleGroup(APage);
  Layout;
  // Die aufgeklappte Seite steht oben.
  FScroll.First := Max(0, FHot);
  FScroll.Clamp(FRows.Count);
  // Unten bleibt unten: das Fenster wächst bzw. schrumpft nach oben.
  if Visible then
  begin
    PlaceAboveAnchor;
  end;
  Invalidate;
end;

procedure TAtlasQuickToggleWindow.Layout;
var
  mGeometry: TToggleGeometry;
  mWidth, mButtonWidth, mTags, mIndex: Integer;
begin
  mGeometry := TToggleGeometry.Create(Self);
  Canvas.Font := Font;
  mTags := Max(Canvas.TextWidth(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesProject)),
    Canvas.TextWidth(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesSession)));
  mWidth := ScaleValue(280);
  for mIndex := 0 to FRows.Count - 1 do
  begin
    // 64: Kästchen und Ränder, 28: Symbol „Einstellung öffnen“.
    mWidth := Max(mWidth, Canvas.TextWidth(FRows.Text(mIndex)) + mTags + ScaleValue(64 + 28));
  end;
  mWidth := Min(mWidth, ScaleValue(720));
  mButtonWidth := Max(Canvas.TextWidth(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOff)),
    Canvas.TextWidth(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOn))) + ScaleValue(24);
  ClientWidth := Max(mWidth, mButtonWidth + ScaleValue(20));
  // Höchstens 80 % der Arbeitsfläche hoch; der Rest per Mausrad bzw. Pfeiltasten.
  FScroll.Visible := Max(3, (Screen.MonitorFromPoint(FAnchor).WorkareaRect.Height * 4 div 5 -
    mGeometry.HeaderHeight - mGeometry.ButtonsHeight) div mGeometry.RowHeight);
  FScroll.Visible := Min(FScroll.Visible, Max(1, FRows.Count));
  FScroll.Clamp(FRows.Count);
  ClientHeight := mGeometry.HeaderHeight + FScroll.Visible * mGeometry.RowHeight + mGeometry.ButtonsHeight;
  FAllButton.SetBounds(ScaleValue(10), ClientHeight - mGeometry.ButtonsHeight + ScaleValue(8), mButtonWidth,
    ScaleValue(25));
end;

procedure TAtlasQuickToggleWindow.SetItems(const AItems: TArray<TAtlasQuickToggleItem>; AAllOff: Boolean);
begin
  FAllOff := AAllOff;
  FRows.Build(AItems);
  if FHot >= FRows.Count then
  begin
    FHot := -1;
  end;
  if FAllOff then
  begin
    FAllButton.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOn);
  end
  else
  begin
    FAllButton.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOff);
  end;
  Layout;
  if Visible then
  begin
    PlaceAboveAnchor;
  end;
  Invalidate;
end;

procedure TAtlasQuickToggleWindow.PlaceAboveAnchor;
var
  mArea: TRect;
begin
  // Wächst das Fenster (Gruppe aufgeklappt), bleibt die Unterkante am Anker, solange oben Platz ist; sonst stößt
  // es oben an die Arbeitsfläche, statt darüber hinaus zu ragen.
  mArea := Screen.MonitorFromPoint(FAnchor).WorkareaRect;
  SetBounds(EnsureRange(FAnchor.X, mArea.Left, Max(mArea.Left, mArea.Right - Width)),
    Max(mArea.Top, FAnchor.Y - Height), Width, Height);
end;

procedure TAtlasQuickToggleWindow.ShowAbove(const AAnchor: TPoint);
var
  mArea: TRect;
begin
  // Erst der Anker (Monitor und Unterkante), dann das Layout: Die Höchsthöhe richtet sich nach diesem Monitor.
  mArea := Screen.MonitorFromPoint(AAnchor).WorkareaRect;
  FAnchor := Point(AAnchor.X, Min(AAnchor.Y, mArea.Bottom));
  Layout;
  PlaceAboveAnchor;
  Show;
  SetFocus;
end;

procedure TAtlasQuickToggleWindow.Dismiss;
begin
  if FClosing then
  begin
    Exit;
  end;
  FClosing := True;
  Close;
  Release;
end;

procedure TAtlasQuickToggleWindow.Deactivate;
begin
  inherited;
  Dismiss;
end;

procedure TAtlasQuickToggleWindow.AllClick(Sender: TObject);
begin
  if Assigned(FOnAllOff) then
  begin
    FOnAllOff();
  end;
end;

procedure TAtlasQuickToggleWindow.ToggleRow(ARow: Integer);
var
  mItem: TAtlasQuickToggleItem;
  mHandler: TProc<TAtlasQuickToggleItem>;
begin
  if (ARow < 0) or (ARow >= FRows.Count) or FClosing then
  begin
    Exit;
  end;
  // Überschrift: Gruppe ein- bzw. ausklappen.
  if not FRows.IsToggle(ARow) then
  begin
    ToggleGroup(FRows.Text(ARow));
    Exit;
  end;
  mItem := FRows.ToggleOf(ARow);
  mHandler := FOnToggle;
  if not Assigned(mHandler) then
  begin
    Exit;
  end;
  if not mItem.Project or mItem.Session then
  begin
    // Gilt sofort; das Fenster bleibt offen und bekommt den neuen Stand über SetItems.
    mHandler(mItem);
    Exit;
  end;
  // Projektwert: Die IDE-Schicht fragt nach, wo die Änderung gelten soll; das Fenster schließt vorher.
  Dismiss;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
    procedure
    begin
      mHandler(mItem);
    end);
end;

procedure TAtlasQuickToggleWindow.ClickRow(ARow: Integer);
begin
  ToggleRow(ARow);
end;

procedure TAtlasQuickToggleWindow.MoveHot(ADelta: Integer);
var
  mRow, mCount: Integer;
begin
  mCount := FRows.Count;
  if mCount = 0 then
  begin
    Exit;
  end;
  // Überschriften sind Stationen: Leertaste bzw. Enter klappt dort die Gruppe.
  mRow := FHot + ADelta;
  if mRow < 0 then
  begin
    mRow := mCount - 1;
  end;
  if mRow >= mCount then
  begin
    mRow := 0;
  end;
  FHot := mRow;
  FScroll.Reveal(FHot, mCount);
  Invalidate;
end;

procedure TAtlasQuickToggleWindow.CMDialogKey(var Message: TCMDialogKey);
begin
  // Pfeiltasten und Tab bewegen die Auswahl statt des Fokus.
  if (Message.CharCode = VK_UP) or (Message.CharCode = VK_DOWN) or (Message.CharCode = VK_TAB) then
  begin
    if Message.CharCode = VK_UP then
    begin
      MoveHot(-1);
    end
    else
    begin
      MoveHot(1);
    end;
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

procedure TAtlasQuickToggleWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  mKey: Word;
begin
  mKey := Key;
  if (mKey <> VK_ESCAPE) and (mKey <> VK_UP) and (mKey <> VK_DOWN) and (mKey <> VK_SPACE) and (mKey <> VK_RETURN)
  then
  begin
    inherited;
    Exit;
  end;
  Key := 0;
  case mKey of
    VK_ESCAPE:
      Dismiss;
    VK_UP:
      MoveHot(-1);
    VK_DOWN:
      MoveHot(1);
  else
    // Leertaste oder Enter; Strg+Enter: Einstellung öffnen statt schalten.
    if (mKey = VK_RETURN) and (ssCtrl in Shift) then
    begin
      OpenRow(FHot);
    end
    else
    begin
      ToggleRow(FHot);
    end;
  end;
end;

procedure TAtlasQuickToggleWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mGeometry: TToggleGeometry;
  mRow: Integer;
begin
  inherited;
  mGeometry := TToggleGeometry.Create(Self);
  mRow := mGeometry.RowAt(Point(X, Y));
  if mRow >= 0 then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if (mRow >= 0) and (mRow <> FHot) then
  begin
    FHot := mRow;
    Invalidate;
  end;
  // Symbol „Einstellung öffnen“ unter der Maus hervorheben.
  if not PtInRect(mGeometry.OpenRect(mRow), Point(X, Y)) then
  begin
    mRow := -1;
  end;
  if mRow <> FHotOpen then
  begin
    FHotOpen := mRow;
    Invalidate;
  end;
end;

procedure TAtlasQuickToggleWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  Cursor := crDefault;
end;

procedure TAtlasQuickToggleWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mGeometry: TToggleGeometry;
  mRow: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mGeometry := TToggleGeometry.Create(Self);
  mRow := mGeometry.RowAt(Point(X, Y));
  if PtInRect(mGeometry.OpenRect(mRow), Point(X, Y)) then
  begin
    OpenRow(mRow);
  end
  else
  begin
    ToggleRow(mRow);
  end;
end;

procedure TAtlasQuickToggleWindow.Paint;
var
  mPainter: TTogglePainter;
begin
  mPainter := TTogglePainter.Create(Self);
  mPainter.Paint;
end;

end.
