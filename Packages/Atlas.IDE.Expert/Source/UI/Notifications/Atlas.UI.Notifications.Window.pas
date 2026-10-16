unit Atlas.UI.Notifications.Window;

// Liste der Benachrichtigungszentrale (#601) im Stil der Atlas-Popups (#411):
// oben Titel, Zahl der ungelesenen und der Filter nach Quelle, darunter die
// Einträge der Zentrale, neueste zuerst (Symbol nach Schwere, Titel mit
// Zähler „3 × …“, Quelle und Uhrzeit, Text, Aktionen als Knöpfe), ungelesene
// hinterlegt. Unten „Alle gelesen“ und „Liste leeren“.
// - Ein Klick auf einen Eintrag markiert ihn als gelesen; ein Klick auf eine
//   Aktion schließt das Fenster und führt sie danach aus (die Zentrale
//   markiert den Eintrag vorher als gelesen).
// - Rechtsklick auf einen Eintrag: „Als gelesen markieren“ und das Verhalten
//   seiner Quelle (einblenden und sammeln, nur sammeln, aus); die Wahl meldet
//   OnModeChange, damit die IDE-Schicht sie speichert.
// - Tastatur: Pfeile wählen, Eingabe führt die erste Aktion aus (ohne Aktion:
//   gelesen), Entf markiert als gelesen, Esc schließt; Tab führt zu Filter
//   und Knöpfen, dort gelten deren Tasten. Mausrad blättert.
// Das Fenster liest nur IAtlasNotificationCenter; neue Quellen brauchen hier
// keine Änderung (ihr Name ist ohne eigenen Text die Kennung der Quelle).
// Es nimmt den Fokus (eigene Knöpfe, Filter, Menü) und schließt mit Esc oder
// einem Klick daneben.

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
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Notifications.Contract;

type
  TAtlasNotificationModeEvent = reference to procedure(const ASource: string; AMode: TAtlasNotificationMode);

  TAtlasNotificationsWindow = class(TForm)
  private
    FColors: TAtlasColors;
    FCenter: IAtlasNotificationCenter;
    FItems: TArray<IAtlasNotification>;
    // Lage der Einträge in der Liste (ohne Blättern) und Gesamthöhe.
    FTops: TArray<Integer>;
    FHeights: TArray<Integer>;
    FContentHeight: Integer;
    FScroll: Integer;
    FSelected: Integer;
    FHotRow: Integer;
    FHotChip: Integer;
    FFilter: string;
    FFilterSources: TArray<string>;
    FFilterBox: TComboBox;
    FAllReadButton: TButton;
    FClearButton: TButton;
    FMenu: TPopupMenu;
    FMenuRow: Integer;
    FMenuOpen: Boolean;
    FClosing: Boolean;
    FUpdating: Boolean;
    FAnchor: TPoint;
    FOnModeChange: TAtlasNotificationModeEvent;
    function LineHeight: Integer;
    function HeaderHeight: Integer;
    function ButtonsHeight: Integer;
    function MaxListHeight: Integer;
    function ListRect: TRect;
    function EntryRect(AIndex: Integer): TRect;
    function ChipRect(ARow, AChip: Integer): TRect;
    function HitTest(const APoint: TPoint; out AChip: Integer): Integer;
    procedure Layout;
    procedure FillFilter;
    procedure ScrollTo(AValue: Integer);
    procedure EnsureVisible(AIndex: Integer);
    procedure DrawEntry(AIndex: Integer);
    procedure DrawSeverity(const ACenter: TPoint; ASeverity: TAtlasNotificationSeverity);
    procedure FormDeactivate(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure AllReadClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    procedure CloseAndRun(const AProc: TProc);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateList(AOwner: TComponent; const AColors: TAtlasColors;
      const ACenter: IAtlasNotificationCenter);
    /// <summary>Name der Quelle in der Sprache der Oberfläche; unbekannte Quellen mit ihrer Kennung.</summary>
    class function SourceCaption(const ASource: string): string; static;
    /// <summary>Farbe des Symbols: Info Akzent, Warnung gelb, Fehler rot.</summary>
    class function SeverityColor(const AColors: TAtlasColors; ASeverity: TAtlasNotificationSeverity): TAtlasColor;
      static;
    /// <summary>Uhrzeit "hh:nn"; an einem anderen Tag als ANow mit Datum "dd.mm. hh:nn".</summary>
    class function TimeText(ATime, ANow: TDateTime): string; static;
    /// <summary>Einträge, Zähler und Filter neu aus der Zentrale lesen (auch bei offenem Fenster).</summary>
    procedure Reload;
    /// <summary>Zeigt das Fenster mit der linken unteren Ecke an AAnchor (Bildschirm, Oberkante des Felds).</summary>
    procedure ShowAbove(const AAnchor: TPoint);
    /// <summary>Schließt ohne Aktion; das Fenster gibt sich danach selbst frei.</summary>
    procedure Dismiss;
    /// <summary>Wie ein Klick auf den Eintrag ARow (gelesen).</summary>
    procedure ClickRow(ARow: Integer);
    /// <summary>Wie ein Klick auf Aktion AAction des Eintrags ARow: schließen, danach ausführen.</summary>
    procedure ClickAction(ARow, AAction: Integer);
    /// <summary>Kontextmenü des Eintrags ARow aufbauen (ohne es zu zeigen).</summary>
    function BuildMenu(ARow: Integer): TPopupMenu;
    /// <summary>Nur Einträge dieser Quelle; '' = alle.</summary>
    procedure SetFilter(const ASource: string);
    function RowCount: Integer;
    function Row(AIndex: Integer): IAtlasNotification;
    property Filter: string read FFilter;
    property Selected: Integer read FSelected;
    /// <summary>Zum Testen: Filter und Knöpfe.</summary>
    property FilterBox: TComboBox read FFilterBox;
    property AllReadButton: TButton read FAllReadButton;
    property ClearButton: TButton read FClearButton;
    /// <summary>Verhalten einer Quelle im Kontextmenü geändert (schon in der Zentrale gesetzt).</summary>
    property OnModeChange: TAtlasNotificationModeEvent read FOnModeChange write FOnModeChange;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Popup.Draw,
  Atlas.UI.Strings;

const
  // Tag der Menüeinträge: gelesen bzw. Verhalten (ModeTag + Ord).
  MarkReadTag = 1;
  ModeTag = 10;

{ TAtlasNotificationsWindow }

constructor TAtlasNotificationsWindow.CreateList(AOwner: TComponent; const AColors: TAtlasColors;
  const ACenter: IAtlasNotificationCenter);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  FCenter := ACenter;
  FSelected := -1;
  FHotRow := -1;
  FHotChip := -1;
  FMenuRow := -1;
  BorderStyle := bsNone;
  KeyPreview := True;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnDeactivate := FormDeactivate;
  FFilterBox := TComboBox.Create(Self);
  FFilterBox.Parent := Self;
  FFilterBox.Style := csDropDownList;
  FFilterBox.OnChange := FilterChange;
  FAllReadButton := TButton.Create(Self);
  FAllReadButton.Parent := Self;
  FAllReadButton.Caption := TAtlasStrings.Text(TAtlasTextId.NotificationsAllRead);
  FAllReadButton.OnClick := AllReadClick;
  FClearButton := TButton.Create(Self);
  FClearButton.Parent := Self;
  FClearButton.Caption := TAtlasStrings.Text(TAtlasTextId.NotificationsClear);
  FClearButton.OnClick := ClearClick;
  FMenu := TPopupMenu.Create(Self);
  Reload;
end;

procedure TAtlasNotificationsWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

class function TAtlasNotificationsWindow.SourceCaption(const ASource: string): string;
begin
  if SameText(ASource, TAtlasNotificationSources.Build) then
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceBuild)
  else if SameText(ASource, TAtlasNotificationSources.Check) then
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceCheck)
  else if SameText(ASource, TAtlasNotificationSources.Reload) then
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceReload)
  else if SameText(ASource, TAtlasNotificationSources.Server) then
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceServer)
  else if SameText(ASource, TAtlasNotificationSources.ShortcutTips) then
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceShortcutTips)
  else
    Result := ASource;
end;

class function TAtlasNotificationsWindow.SeverityColor(const AColors: TAtlasColors;
  ASeverity: TAtlasNotificationSeverity): TAtlasColor;
begin
  case ASeverity of
    TAtlasNotificationSeverity.Warning:
      Result := AColors.Warn;
    TAtlasNotificationSeverity.Error:
      Result := AColors.Error;
  else
    Result := AColors.Accent;
  end;
end;

class function TAtlasNotificationsWindow.TimeText(ATime, ANow: TDateTime): string;
begin
  if IsSameDay(ATime, ANow) then
    Result := FormatDateTime('hh:nn', ATime)
  else
    Result := FormatDateTime('dd.mm. hh:nn', ATime);
end;

function TAtlasNotificationsWindow.LineHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg');
end;

function TAtlasNotificationsWindow.HeaderHeight: Integer;
begin
  Result := Max(LineHeight, FFilterBox.Height) + ScaleValue(12);
end;

function TAtlasNotificationsWindow.ButtonsHeight: Integer;
begin
  Result := ScaleValue(40);
end;

function TAtlasNotificationsWindow.MaxListHeight: Integer;
begin
  Result := ScaleValue(420);
end;

function TAtlasNotificationsWindow.ListRect: TRect;
begin
  Result := Rect(1, HeaderHeight, ClientWidth - 1, ClientHeight - ButtonsHeight);
end;

function TAtlasNotificationsWindow.EntryRect(AIndex: Integer): TRect;
var
  List: TRect;
begin
  List := ListRect;
  Result := Rect(List.Left, List.Top + FTops[AIndex] - FScroll, List.Right,
    List.Top + FTops[AIndex] - FScroll + FHeights[AIndex]);
end;

function TAtlasNotificationsWindow.ChipRect(ARow, AChip: Integer): TRect;
var
  Entry: TRect;
  Index, Left_, Top_, Width_: Integer;
  Actions: TArray<TAtlasNotificationAction>;
begin
  Result := Rect(0, 0, 0, 0);
  if (ARow < 0) or (ARow > High(FItems)) then
    Exit;
  Actions := FItems[ARow].Actions;
  if (AChip < 0) or (AChip > High(Actions)) then
    Exit;
  Canvas.Font := Font;
  Entry := EntryRect(ARow);
  Left_ := Entry.Left + ScaleValue(34);
  Top_ := Entry.Top + ScaleValue(6) + 2 * LineHeight + ScaleValue(6);
  for Index := 0 to AChip do
  begin
    Width_ := Canvas.TextWidth(Actions[Index].Caption) + ScaleValue(TAtlasDraw.ChipPad + 8);
    if Index = AChip then
      Exit(Rect(Left_, Top_, Left_ + Width_, Top_ + LineHeight + ScaleValue(6)));
    Inc(Left_, Width_ + ScaleValue(6));
  end;
end;

function TAtlasNotificationsWindow.HitTest(const APoint: TPoint; out AChip: Integer): Integer;
var
  Index, Chip: Integer;
begin
  AChip := -1;
  Result := -1;
  if not PtInRect(ListRect, APoint) then
    Exit;
  for Index := 0 to High(FItems) do
    if PtInRect(EntryRect(Index), APoint) then
    begin
      Result := Index;
      for Chip := 0 to High(FItems[Index].Actions) do
        if PtInRect(ChipRect(Index, Chip), APoint) then
          AChip := Chip;
      Exit;
    end;
end;

procedure TAtlasNotificationsWindow.Layout;
var
  Index, Top_, Height_, Line, ButtonWidth, ListHeight, Gap: Integer;
begin
  Canvas.Font := Font;
  Line := LineHeight;
  ClientWidth := ScaleValue(440);
  SetLength(FTops, Length(FItems));
  SetLength(FHeights, Length(FItems));
  Top_ := 0;
  for Index := 0 to High(FItems) do
  begin
    // Titel und Text, darunter die Aktionen.
    Height_ := ScaleValue(12) + 2 * Line;
    if Length(FItems[Index].Actions) > 0 then
      Inc(Height_, Line + ScaleValue(12));
    FTops[Index] := Top_;
    FHeights[Index] := Height_;
    Inc(Top_, Height_);
  end;
  FContentHeight := Top_;
  if Length(FItems) = 0 then
    ListHeight := 3 * Line
  else
    ListHeight := Min(FContentHeight, MaxListHeight);
  ClientHeight := HeaderHeight + ListHeight + ButtonsHeight;
  ScrollTo(FScroll);
  Gap := ScaleValue(8);
  FFilterBox.Width := ScaleValue(170);
  FFilterBox.Left := ClientWidth - FFilterBox.Width - Gap;
  FFilterBox.Top := (HeaderHeight - FFilterBox.Height) div 2;
  ButtonWidth := Max(Canvas.TextWidth(FAllReadButton.Caption), Canvas.TextWidth(FClearButton.Caption)) +
    ScaleValue(24);
  Index := ClientHeight - ButtonsHeight + Gap;
  FAllReadButton.SetBounds(ScaleValue(10), Index, ButtonWidth, ScaleValue(25));
  FClearButton.SetBounds(ScaleValue(20) + ButtonWidth, Index, ButtonWidth, ScaleValue(25));
  FAllReadButton.Enabled := (FCenter <> nil) and (FCenter.UnreadCount > 0);
  FClearButton.Enabled := (FCenter <> nil) and (Length(FCenter.Items()) > 0);
end;

procedure TAtlasNotificationsWindow.FillFilter;
var
  Source: string;
  Sources: TArray<string>;
  Index, Found: Integer;
begin
  FUpdating := True;
  try
    Sources := nil;
    if FCenter <> nil then
      Sources := FCenter.Sources;
    // Gewählte Quelle ohne Einträge (z. B. nach „Liste leeren“) bleibt wählbar.
    Found := -1;
    for Index := 0 to High(Sources) do
      if SameText(Sources[Index], FFilter) then
        Found := Index;
    if (FFilter <> '') and (Found < 0) then
      Sources := Sources + [FFilter];
    FFilterSources := [''] + Sources;
    FFilterBox.Items.BeginUpdate;
    try
      FFilterBox.Items.Clear;
      FFilterBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.NotificationsFilterAll));
      for Source in Sources do
        FFilterBox.Items.Add(SourceCaption(Source));
    finally
      FFilterBox.Items.EndUpdate;
    end;
    FFilterBox.ItemIndex := 0;
    for Index := 1 to High(FFilterSources) do
      if SameText(FFilterSources[Index], FFilter) then
        FFilterBox.ItemIndex := Index;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasNotificationsWindow.Reload;
var
  SelectedId: Integer;
  Index: Integer;
begin
  SelectedId := -1;
  if (FSelected >= 0) and (FSelected <= High(FItems)) then
    SelectedId := FItems[FSelected].Id;
  FItems := nil;
  if FCenter <> nil then
    FItems := FCenter.Items(FFilter);
  FSelected := -1;
  for Index := 0 to High(FItems) do
    if FItems[Index].Id = SelectedId then
      FSelected := Index;
  FHotRow := -1;
  FHotChip := -1;
  FillFilter;
  Layout;
  if Visible then
    SetBounds(FAnchor.X, FAnchor.Y - Height, Width, Height);
  Invalidate;
end;

procedure TAtlasNotificationsWindow.SetFilter(const ASource: string);
begin
  FFilter := Trim(ASource);
  FScroll := 0;
  Reload;
end;

function TAtlasNotificationsWindow.RowCount: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasNotificationsWindow.Row(AIndex: Integer): IAtlasNotification;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FItems)) then
    Result := FItems[AIndex];
end;

procedure TAtlasNotificationsWindow.ScrollTo(AValue: Integer);
var
  List: TRect;
begin
  List := ListRect;
  FScroll := EnsureRange(AValue, 0, Max(0, FContentHeight - (List.Bottom - List.Top)));
end;

procedure TAtlasNotificationsWindow.EnsureVisible(AIndex: Integer);
var
  List: TRect;
  Visible_: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FItems)) then
    Exit;
  List := ListRect;
  Visible_ := List.Bottom - List.Top;
  if FTops[AIndex] < FScroll then
    ScrollTo(FTops[AIndex])
  else if FTops[AIndex] + FHeights[AIndex] > FScroll + Visible_ then
    ScrollTo(FTops[AIndex] + FHeights[AIndex] - Visible_);
end;

procedure TAtlasNotificationsWindow.ShowAbove(const AAnchor: TPoint);
var
  Area: TRect;
  Left_, Top_: Integer;
begin
  Layout;
  Area := Screen.MonitorFromPoint(AAnchor).WorkareaRect;
  Left_ := EnsureRange(AAnchor.X, Area.Left, Max(Area.Left, Area.Right - Width));
  Top_ := Max(Area.Top, AAnchor.Y - Height);
  FAnchor := Point(Left_, Top_ + Height);
  SetBounds(Left_, Top_, Width, Height);
  Show;
  // Die Liste hat die Tastatur (Pfeile, Eingabe); Tab führt zu Filter und Knöpfen.
  ActiveControl := nil;
  SetFocus;
end;

procedure TAtlasNotificationsWindow.Dismiss;
begin
  if FClosing then
    Exit;
  FClosing := True;
  Close;
  Release;
end;

procedure TAtlasNotificationsWindow.CloseAndRun(const AProc: TProc);
begin
  if FClosing then
    Exit;
  Dismiss;
  // Erst nach dem Schließen ausführen: Die Aktion springt in den Editor oder öffnet ein Fenster.
  if Assigned(AProc) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.Notifications,
      procedure
      begin
        AProc();
      end);
end;

procedure TAtlasNotificationsWindow.FormDeactivate(Sender: TObject);
begin
  // Das eigene Kontextmenü nimmt den Fokus nicht weg; sicherheitshalber offen lassen.
  if not FMenuOpen then
    Dismiss;
end;

procedure TAtlasNotificationsWindow.FilterChange(Sender: TObject);
begin
  if FUpdating or (FFilterBox.ItemIndex < 0) or (FFilterBox.ItemIndex > High(FFilterSources)) then
    Exit;
  SetFilter(FFilterSources[FFilterBox.ItemIndex]);
end;

procedure TAtlasNotificationsWindow.AllReadClick(Sender: TObject);
begin
  if FCenter = nil then
    Exit;
  FCenter.MarkAllRead;
  Reload;
end;

procedure TAtlasNotificationsWindow.ClearClick(Sender: TObject);
begin
  if FCenter = nil then
    Exit;
  FCenter.Clear;
  FScroll := 0;
  Reload;
end;

procedure TAtlasNotificationsWindow.ClickRow(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FItems)) or (FCenter = nil) then
    Exit;
  FSelected := ARow;
  if not FItems[ARow].Read then
    FCenter.MarkRead(FItems[ARow].Id);
  Reload;
end;

procedure TAtlasNotificationsWindow.ClickAction(ARow, AAction: Integer);
var
  Center: IAtlasNotificationCenter;
  Id: Integer;
begin
  if (ARow < 0) or (ARow > High(FItems)) or (AAction < 0) or (AAction > High(FItems[ARow].Actions)) or
    (FCenter = nil) then
    Exit;
  Center := FCenter;
  Id := FItems[ARow].Id;
  CloseAndRun(
    procedure
    begin
      Center.RunAction(Id, AAction);
    end);
end;

function TAtlasNotificationsWindow.BuildMenu(ARow: Integer): TPopupMenu;
var
  Item: TMenuItem;
  Mode: TAtlasNotificationMode;
  Current: TAtlasNotificationMode;
  Source: string;
const
  ModeTexts: array[TAtlasNotificationMode] of TAtlasTextId = (TAtlasTextId.NotificationsModeShow,
    TAtlasTextId.NotificationsModeCollect, TAtlasTextId.NotificationsModeOff);
begin
  Result := FMenu;
  FMenu.Items.Clear;
  FMenuRow := -1;
  if (ARow < 0) or (ARow > High(FItems)) or (FCenter = nil) then
    Exit;
  FMenuRow := ARow;
  Source := FItems[ARow].Source;
  Item := TMenuItem.Create(FMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.NotificationsMarkRead);
  Item.Tag := MarkReadTag;
  Item.Enabled := not FItems[ARow].Read;
  Item.OnClick := MenuClick;
  FMenu.Items.Add(Item);
  FMenu.Items.Add(NewLine);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := TAtlasStrings.Fmt(TAtlasTextId.NotificationsModeMenu, [SourceCaption(Source)]);
  Item.Enabled := False;
  FMenu.Items.Add(Item);
  Current := FCenter.ModeOf(Source);
  for Mode := Low(TAtlasNotificationMode) to High(TAtlasNotificationMode) do
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := TAtlasStrings.Text(ModeTexts[Mode]);
    Item.Tag := ModeTag + Ord(Mode);
    Item.RadioItem := True;
    Item.GroupIndex := 1;
    Item.Checked := Mode = Current;
    Item.OnClick := MenuClick;
    FMenu.Items.Add(Item);
  end;
end;

procedure TAtlasNotificationsWindow.MenuClick(Sender: TObject);
var
  Tag_: Integer;
  Source: string;
  Mode: TAtlasNotificationMode;
  Handler: TAtlasNotificationModeEvent;
begin
  if (FMenuRow < 0) or (FMenuRow > High(FItems)) or (FCenter = nil) then
    Exit;
  Tag_ := (Sender as TMenuItem).Tag;
  if Tag_ = MarkReadTag then
  begin
    ClickRow(FMenuRow);
    Exit;
  end;
  if (Tag_ < ModeTag) or (Tag_ > ModeTag + Ord(High(TAtlasNotificationMode))) then
    Exit;
  Source := FItems[FMenuRow].Source;
  Mode := TAtlasNotificationMode(Tag_ - ModeTag);
  FCenter.SetMode(Source, Mode);
  Handler := FOnModeChange;
  if Assigned(Handler) then
    Handler(Source, Mode);
  Reload;
end;

procedure TAtlasNotificationsWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  Next: Integer;
begin
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        Dismiss;
        Exit;
      end;
    VK_UP, VK_DOWN:
      if (Length(FItems) > 0) and (ActiveControl = nil) then
      begin
        if Key = VK_UP then
          Next := Max(0, FSelected - 1)
        else
          Next := Min(High(FItems), FSelected + 1);
        Key := 0;
        FSelected := Next;
        EnsureVisible(FSelected);
        Invalidate;
        Exit;
      end;
    VK_RETURN:
      if (FSelected >= 0) and (FSelected <= High(FItems)) and (ActiveControl = nil) then
      begin
        Key := 0;
        if Length(FItems[FSelected].Actions) > 0 then
          ClickAction(FSelected, 0)
        else
          ClickRow(FSelected);
        Exit;
      end;
    VK_DELETE:
      if (FSelected >= 0) and (FSelected <= High(FItems)) and (ActiveControl = nil) then
      begin
        Key := 0;
        ClickRow(FSelected);
        Exit;
      end;
  end;
  inherited;
end;

procedure TAtlasNotificationsWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Row, Chip: Integer;
begin
  inherited;
  Row := HitTest(Point(X, Y), Chip);
  if Chip >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if (Row <> FHotRow) or (Chip <> FHotChip) then
  begin
    FHotRow := Row;
    FHotChip := Chip;
    Invalidate;
  end;
end;

procedure TAtlasNotificationsWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if (FHotRow >= 0) or (FHotChip >= 0) then
  begin
    FHotRow := -1;
    FHotChip := -1;
    Invalidate;
  end;
end;

procedure TAtlasNotificationsWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row, Chip: Integer;
  Screen_: TPoint;
begin
  inherited;
  Row := HitTest(Point(X, Y), Chip);
  if Row < 0 then
    Exit;
  if Button = mbRight then
  begin
    FSelected := Row;
    Invalidate;
    BuildMenu(Row);
    Screen_ := ClientToScreen(Point(X, Y));
    FMenuOpen := True;
    try
      FMenu.Popup(Screen_.X, Screen_.Y);
    finally
      FMenuOpen := False;
    end;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  if Chip >= 0 then
    ClickAction(Row, Chip)
  else
    ClickRow(Row);
end;

function TAtlasNotificationsWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  ScrollTo(FScroll - (WheelDelta div WHEEL_DELTA) * 3 * LineHeight);
  Invalidate;
  Result := True;
end;

procedure TAtlasNotificationsWindow.DrawSeverity(const ACenter: TPoint; ASeverity: TAtlasNotificationSeverity);
var
  Radius: Integer;
  Glyph: string;
  Part: TRect;
begin
  Radius := ScaleValue(8);
  Canvas.Pen.Color := ToColor(SeverityColor(FColors, ASeverity));
  Canvas.Brush.Color := ToColor(SeverityColor(FColors, ASeverity));
  Canvas.Brush.Style := bsSolid;
  Canvas.Ellipse(ACenter.X - Radius, ACenter.Y - Radius, ACenter.X + Radius + 1, ACenter.Y + Radius + 1);
  case ASeverity of
    TAtlasNotificationSeverity.Warning:
      Glyph := '!';
    TAtlasNotificationSeverity.Error:
      Glyph := '×';
  else
    Glyph := 'i';
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Surface);
  Part := Rect(ACenter.X - Radius, ACenter.Y - Radius, ACenter.X + Radius + 1, ACenter.Y + Radius + 1);
  DrawText(Canvas.Handle, PChar(Glyph), -1, Part, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
end;

procedure TAtlasNotificationsWindow.DrawEntry(AIndex: Integer);
var
  Item: IAtlasNotification;
  Entry, Part, Chip: TRect;
  Line, Index: Integer;
  Text, Right: string;
  Actions: TArray<TAtlasNotificationAction>;
begin
  Item := FItems[AIndex];
  Entry := EntryRect(AIndex);
  Line := LineHeight;
  // Ungelesen hinterlegt, mit Balken in der Farbe der Schwere.
  Canvas.Brush.Style := bsSolid;
  if not Item.Read then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.FillRect(Entry);
    Canvas.Brush.Color := ToColor(SeverityColor(FColors, Item.Severity));
    Canvas.FillRect(Rect(Entry.Left, Entry.Top, Entry.Left + ScaleValue(3), Entry.Bottom));
  end;
  if (AIndex = FSelected) or ((AIndex = FHotRow) and (FHotChip < 0)) then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.Rectangle(Entry.Left + ScaleValue(4), Entry.Top + 1, Entry.Right - 1, Entry.Bottom - 1);
  end;
  DrawSeverity(Point(Entry.Left + ScaleValue(18), Entry.Top + ScaleValue(6) + Line div 2), Item.Severity);
  Canvas.Brush.Style := bsClear;
  // Rechts Quelle und Uhrzeit, gedämpft.
  Right := SourceCaption(Item.Source) + ' · ' + TimeText(Item.Time, Now);
  Canvas.Font.Color := ToColor(FColors.Muted);
  Part := Rect(Entry.Left + ScaleValue(34), Entry.Top + ScaleValue(6), Entry.Right - ScaleValue(10),
    Entry.Top + ScaleValue(6) + Line);
  DrawText(Canvas.Handle, PChar(Right), -1, Part, DT_SINGLELINE or DT_RIGHT or DT_NOPREFIX);
  Part.Right := Part.Right - Canvas.TextWidth(Right) - ScaleValue(10);
  // Titel mit Zähler; ungelesen fett.
  if not Item.Read then
    Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  Text := Item.Caption;
  DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  // Text in der zweiten Zeile.
  Part := Rect(Entry.Left + ScaleValue(34), Part.Bottom, Entry.Right - ScaleValue(10), Part.Bottom + Line);
  Canvas.Font.Color := ToColor(FColors.Muted);
  Text := Item.Text;
  DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  // Aktionen als Knöpfe.
  Actions := Item.Actions;
  for Index := 0 to High(Actions) do
  begin
    Chip := ChipRect(AIndex, Index);
    Canvas.Brush.Style := bsSolid;
    if (AIndex = FHotRow) and (Index = FHotChip) then
      Canvas.Brush.Color := ToColor(FColors.AccentSoft)
    else
      Canvas.Brush.Color := ToColor(FColors.Surface);
    Canvas.Pen.Color := ToColor(FColors.Accent);
    Canvas.RoundRect(Chip.Left, Chip.Top, Chip.Right, Chip.Bottom, ScaleValue(2 * TAtlasDraw.ChipRadius),
      ScaleValue(2 * TAtlasDraw.ChipRadius));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(FColors.Accent);
    Text := Actions[Index].Caption;
    DrawText(Canvas.Handle, PChar(Text), -1, Chip, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  end;
end;

procedure TAtlasNotificationsWindow.Paint;
var
  Index, Unread, ThumbHeight, ThumbTop: Integer;
  List, Part: TRect;
  Text: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  List := ListRect;
  // Einträge nur im Listenbereich; Kopf und Fuß übermalen, was hinausragt.
  IntersectClipRect(Canvas.Handle, List.Left, List.Top, List.Right, List.Bottom);
  try
    if Length(FItems) = 0 then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(FColors.Muted);
      Text := TAtlasStrings.Text(TAtlasTextId.NotificationsEmpty);
      Part := List;
      DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
    end;
    for Index := 0 to High(FItems) do
    begin
      Part := EntryRect(Index);
      if (Part.Bottom > List.Top) and (Part.Top < List.Bottom) then
        DrawEntry(Index);
    end;
    // Daumen, wenn die Liste länger ist als der Bereich.
    if FContentHeight > List.Bottom - List.Top then
    begin
      ThumbHeight := Max(ScaleValue(16), MulDiv(List.Bottom - List.Top, List.Bottom - List.Top, FContentHeight));
      ThumbTop := List.Top + MulDiv(FScroll, List.Bottom - List.Top - ThumbHeight,
        Max(1, FContentHeight - (List.Bottom - List.Top)));
      TAtlasDraw.Thumb(Canvas, Rect(List.Right - ScaleValue(5), ThumbTop, List.Right - ScaleValue(1),
        ThumbTop + ThumbHeight), FColors, ScaleValue(2));
    end;
  finally
    SelectClipRgn(Canvas.Handle, 0);
  end;
  // Kopf: Titel und Zahl der ungelesenen.
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  Part := Rect(ScaleValue(12), 0, FFilterBox.Left - ScaleValue(8), HeaderHeight);
  Text := TAtlasStrings.Text(TAtlasTextId.NotificationsCommand);
  DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Part.Left := Part.Left + Canvas.TextWidth(Text) + ScaleValue(8);
  Canvas.Font.Style := [];
  Unread := 0;
  if FCenter <> nil then
    Unread := FCenter.UnreadCount;
  if Unread > 0 then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    Text := TAtlasStrings.Fmt(TAtlasTextId.NotificationsUnread, [Unread]);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, HeaderHeight - 1);
  Canvas.LineTo(ClientWidth, HeaderHeight - 1);
  Canvas.MoveTo(0, ClientHeight - ButtonsHeight);
  Canvas.LineTo(ClientWidth, ClientHeight - ButtonsHeight);
  // Rahmen des Fensters in Akzentfarbe.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

end.
