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
  Atlas.Core.Style.Signal,
  Atlas.Core.Notifications.Contract;

type
  TAtlasNotificationModeEvent = reference to procedure(const ASource: string; AMode: TAtlasNotificationMode);

  /// <summary>Texte und Farben der Einträge, auch für die Einstellungen.</summary>
  TAtlasNotificationTexts = record
    /// <summary>Name der Quelle in der Sprache der Oberfläche; unbekannte Quellen mit ihrer Kennung.</summary>
    class function SourceCaption(const ASource: string): string; static;
    /// <summary>Signalfarben von Symbol und Balken: Info blau, Warnung gelb, Fehler rot; dieselben kräftigen
    /// Farben wie Plakette und Zähler der Atlas-Statusleiste (#1255), nicht die Textfarben.</summary>
    class function SeveritySignal(const AColors: TAtlasColors; ASeverity: TAtlasNotificationSeverity): TAtlasSignal;
      static;
    /// <summary>Uhrzeit "hh:nn"; an einem anderen Tag als ANow mit Datum "dd.mm. hh:nn".</summary>
    class function TimeText(ATime, ANow: TDateTime): string; static;
  end;

  TAtlasNotificationsWindow = class(TForm)
  private type
    /// <summary>Einträge, ihre Lage in der Liste (ohne Blättern), Auswahl und Eintrag unter der Maus.</summary>
    TRows = record
      Items: TArray<IAtlasNotification>;
      Tops: TArray<Integer>;
      Heights: TArray<Integer>;
      ContentHeight: Integer;
      Scroll: Integer;
      Selected: Integer;
      HotRow: Integer;
      HotChip: Integer;
      function Valid(AIndex: Integer): Boolean;
      /// <summary>Lage je Eintrag: Titel und Text (je ALine hoch) plus APad, mit Aktionen eine Zeile mehr.</summary>
      procedure Measure(ALine, APad: Integer);
      /// <summary>Blättern auf AValue, begrenzt auf einen Bereich der Höhe AVisible.</summary>
      procedure ScrollTo(AValue, AVisible: Integer);
      procedure EnsureVisible(AIndex, AVisible: Integer);
      /// <summary>Kennung des gewählten Eintrags; -1 ohne Auswahl.</summary>
      function SelectedId: Integer;
      /// <summary>Wählt den Eintrag mit der Kennung AId; -1, wenn es ihn nicht gibt.</summary>
      procedure SelectId(AId: Integer);
    end;

    /// <summary>Steuerelemente des Fensters.</summary>
    TParts = record
      FilterBox: TComboBox;
      AllReadButton: TButton;
      ClearButton: TButton;
      Menu: TPopupMenu;
    end;

    /// <summary>Filter nach Quelle: gewählte Quelle und Quellen der Auswahlliste ('' = alle).</summary>
    TFilter = record
      Source: string;
      Sources: TArray<string>;
      /// <summary>Die Auswahlliste wird gerade gefüllt; ihr OnChange zählt nicht.</summary>
      Updating: Boolean;
    end;

    TState = record
      /// <summary>Eintrag des Kontextmenüs; -1 ohne.</summary>
      MenuRow: Integer;
      MenuOpen: Boolean;
      Closing: Boolean;
      /// <summary>Linke untere Ecke beim Zeigen (Bildschirm).</summary>
      Anchor: TPoint;
    end;
  private
    FColors: TAtlasColors;
    FCenter: IAtlasNotificationCenter;
    FRows: TRows;
    FParts: TParts;
    FFilter: TFilter;
    FState: TState;
    FOnModeChange: TAtlasNotificationModeEvent;
    /// <summary>Höhe und Lage aller Einträge, Größe des Fensters.</summary>
    procedure Layout;
    /// <summary>Filter oben rechts, Knöpfe unten.</summary>
    procedure PlaceControls;
    procedure FillFilter;
    /// <summary>Pfeile, Eingabe und Entf in der Liste; False, wenn die Taste nicht der Liste gilt.</summary>
    function ListKey(AKey: Word): Boolean;
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
    /// <summary>Angezeigte Einträge, neueste zuerst.</summary>
    property Rows: TArray<IAtlasNotification> read FRows.Items;
    property Filter: string read FFilter.Source;
    property Selected: Integer read FRows.Selected;
    /// <summary>Zum Testen: Filter und Knöpfe.</summary>
    property FilterBox: TComboBox read FParts.FilterBox;
    property AllReadButton: TButton read FParts.AllReadButton;
    property ClearButton: TButton read FParts.ClearButton;
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
  cMarkReadTag = 1;
  cModeTag = 10;
  /// <summary>Höhe des Fußes mit den Knöpfen und größte Höhe der Liste, logische Pixel.</summary>
  cButtonsHeight = 40;
  cMaxListHeight = 420;

type
  /// <summary>Maße des Fensters: Zeilenhöhe, Kopf, Bereich der Liste, Einträge und ihre Aktionen.</summary>
  TNotificationsGeometry = record
    Window: TAtlasNotificationsWindow;
    Line: Integer;
    Header: Integer;
    List: TRect;
    class function Create(AWindow: TAtlasNotificationsWindow): TNotificationsGeometry; static;
    function VisibleHeight: Integer;
    function EntryRect(AIndex: Integer): TRect;
    function ChipRect(ARow, AChip: Integer): TRect;
    /// <summary>Eintrag unter APoint (-1 ohne), AChip die Aktion darunter (-1 ohne).</summary>
    function HitTest(const APoint: TPoint; out AChip: Integer): Integer;
  end;

  /// <summary>Zeichnet das Fenster: Einträge, Kopf, Trennlinien und Rahmen.</summary>
  TNotificationsPainter = record
    Window: TAtlasNotificationsWindow;
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Geometry: TNotificationsGeometry;
    class function Create(AWindow: TAtlasNotificationsWindow): TNotificationsPainter; static;
    function Scale(AValue: Integer): Integer;
    procedure DrawSeverity(const ACenter: TPoint; ASeverity: TAtlasNotificationSeverity);
    /// <summary>Hintergrund (ungelesen, Auswahl) und Symbol der Schwere.</summary>
    procedure DrawEntryBack(AIndex: Integer; const AEntry: TRect);
    procedure DrawEntryTexts(const AItem: IAtlasNotification; const AEntry: TRect);
    procedure DrawChips(AIndex: Integer);
    procedure DrawEntry(AIndex: Integer);
    procedure DrawThumb;
    /// <summary>Einträge im Listenbereich; Kopf und Fuß übermalen, was hinausragt.</summary>
    procedure DrawList;
    procedure DrawHeader;
    procedure Paint;
  end;

{ TAtlasNotificationTexts }

class function TAtlasNotificationTexts.SourceCaption(const ASource: string): string;
begin
  if SameText(ASource, TAtlasNotificationSources.Build) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceBuild);
  end
  else if SameText(ASource, TAtlasNotificationSources.Check) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceCheck);
  end
  else if SameText(ASource, TAtlasNotificationSources.Reload) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceReload);
  end
  else if SameText(ASource, TAtlasNotificationSources.Server) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceServer);
  end
  else if SameText(ASource, TAtlasNotificationSources.ShortcutTips) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceShortcutTips);
  end
  else if SameText(ASource, TAtlasNotificationSources.BuildServer) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceBuildServer);
  end
  else if SameText(ASource, TAtlasNotificationSources.OpenBuild) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceOpenBuild);
  end
  else if SameText(ASource, TAtlasNotificationSources.Hidden) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceHidden);
  end
  else if SameText(ASource, TAtlasNotificationSources.UnitRename) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UnitRenameTitle);
  end
  else if SameText(ASource, TAtlasNotificationSources.Minimap) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MinimapNoticeTitle);
  end
  else if SameText(ASource, TAtlasNotificationSources.NewIssue) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NewIssueCreatedTitle);
  end
  else if SameText(ASource, TAtlasNotificationSources.Issues) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceIssues);
  end
  else if SameText(ASource, TAtlasNotificationSources.RuleChecks) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.NotificationsSourceRuleChecks);
  end
  else
  begin
    Result := ASource;
  end;
end;

class function TAtlasNotificationTexts.SeveritySignal(const AColors: TAtlasColors;
  ASeverity: TAtlasNotificationSeverity): TAtlasSignal;
begin
  case ASeverity of
    TAtlasNotificationSeverity.Warning:
      Result := AColors.Signals.Get(TAtlasSignalKind.Warn);
    TAtlasNotificationSeverity.Error:
      Result := AColors.Signals.Get(TAtlasSignalKind.Error);
  else
    Result := AColors.Signals.Get(TAtlasSignalKind.Info);
  end;
end;

class function TAtlasNotificationTexts.TimeText(ATime, ANow: TDateTime): string;
begin
  if IsSameDay(ATime, ANow) then
  begin
    Result := FormatDateTime('hh":"nn', ATime);
  end
  else
  begin
    Result := FormatDateTime('dd.mm. hh":"nn', ATime);
  end;
end;

{ TAtlasNotificationsWindow.TRows }

function TAtlasNotificationsWindow.TRows.Valid(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(Items));
end;

procedure TAtlasNotificationsWindow.TRows.Measure(ALine, APad: Integer);
var
  mIndex, mTop, mHeight: Integer;
begin
  SetLength(Tops, Length(Items));
  SetLength(Heights, Length(Items));
  mTop := 0;
  for mIndex := 0 to High(Items) do
  begin
    // Titel und Text, darunter die Aktionen.
    mHeight := APad + 2 * ALine;
    if Length(Items[mIndex].Actions) > 0 then
    begin
      Inc(mHeight, ALine + APad);
    end;
    Tops[mIndex] := mTop;
    Heights[mIndex] := mHeight;
    Inc(mTop, mHeight);
  end;
  ContentHeight := mTop;
end;

procedure TAtlasNotificationsWindow.TRows.ScrollTo(AValue, AVisible: Integer);
begin
  Scroll := EnsureRange(AValue, 0, Max(0, ContentHeight - AVisible));
end;

procedure TAtlasNotificationsWindow.TRows.EnsureVisible(AIndex, AVisible: Integer);
begin
  if not Valid(AIndex) then
  begin
    Exit;
  end;
  if Tops[AIndex] < Scroll then
  begin
    ScrollTo(Tops[AIndex], AVisible);
  end
  else if Tops[AIndex] + Heights[AIndex] > Scroll + AVisible then
  begin
    ScrollTo(Tops[AIndex] + Heights[AIndex] - AVisible, AVisible);
  end;
end;

function TAtlasNotificationsWindow.TRows.SelectedId: Integer;
begin
  Result := -1;
  if Valid(Selected) then
  begin
    Result := Items[Selected].Id;
  end;
end;

procedure TAtlasNotificationsWindow.TRows.SelectId(AId: Integer);
var
  mIndex: Integer;
begin
  Selected := -1;
  for mIndex := 0 to High(Items) do
  begin
    if Items[mIndex].Id = AId then
    begin
      Selected := mIndex;
    end;
  end;
end;

{ TNotificationsGeometry }

class function TNotificationsGeometry.Create(AWindow: TAtlasNotificationsWindow): TNotificationsGeometry;
begin
  Result.Window := AWindow;
  AWindow.Canvas.Font := AWindow.Font;
  Result.Line := AWindow.Canvas.TextHeight('Wg');
  Result.Header := Max(Result.Line, AWindow.FParts.FilterBox.Height) + AWindow.ScaleValue(12);
  Result.List := Rect(1, Result.Header, AWindow.ClientWidth - 1,
    AWindow.ClientHeight - AWindow.ScaleValue(cButtonsHeight));
end;

function TNotificationsGeometry.VisibleHeight: Integer;
begin
  Result := List.Bottom - List.Top;
end;

function TNotificationsGeometry.EntryRect(AIndex: Integer): TRect;
var
  mTop: Integer;
begin
  mTop := List.Top + Window.FRows.Tops[AIndex] - Window.FRows.Scroll;
  Result := Rect(List.Left, mTop, List.Right, mTop + Window.FRows.Heights[AIndex]);
end;

function TNotificationsGeometry.ChipRect(ARow, AChip: Integer): TRect;
var
  mEntry: TRect;
  mIndex, mLeft, mTop, mWidth: Integer;
  mActions: TArray<TAtlasNotificationAction>;
begin
  Result := Rect(0, 0, 0, 0);
  if not Window.FRows.Valid(ARow) then
  begin
    Exit;
  end;
  mActions := Window.FRows.Items[ARow].Actions;
  if (AChip < 0) or (AChip > High(mActions)) then
  begin
    Exit;
  end;
  Window.Canvas.Font := Window.Font;
  mEntry := EntryRect(ARow);
  mLeft := mEntry.Left + Window.ScaleValue(34);
  mTop := mEntry.Top + Window.ScaleValue(6) + 2 * Line + Window.ScaleValue(6);
  for mIndex := 0 to AChip do
  begin
    mWidth := Window.Canvas.TextWidth(mActions[mIndex].Caption) + Window.ScaleValue(TAtlasDraw.ChipPad + 8);
    if mIndex = AChip then
    begin
      Exit(Rect(mLeft, mTop, mLeft + mWidth, mTop + Line + Window.ScaleValue(6)));
    end;
    Inc(mLeft, mWidth + Window.ScaleValue(6));
  end;
end;

function TNotificationsGeometry.HitTest(const APoint: TPoint; out AChip: Integer): Integer;
var
  mIndex, mChip: Integer;
begin
  AChip := -1;
  Result := -1;
  if not PtInRect(List, APoint) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Window.FRows.Items) do
  begin
    if PtInRect(EntryRect(mIndex), APoint) then
    begin
      Result := mIndex;
      for mChip := 0 to High(Window.FRows.Items[mIndex].Actions) do
      begin
        if PtInRect(ChipRect(mIndex, mChip), APoint) then
        begin
          AChip := mChip;
        end;
      end;
      Exit;
    end;
  end;
end;

{ TNotificationsPainter }

class function TNotificationsPainter.Create(AWindow: TAtlasNotificationsWindow): TNotificationsPainter;
begin
  Result.Window := AWindow;
  Result.Canvas := AWindow.Canvas;
  Result.Colors := AWindow.FColors;
  Result.Geometry := TNotificationsGeometry.Create(AWindow);
end;

function TNotificationsPainter.Scale(AValue: Integer): Integer;
begin
  Result := Window.ScaleValue(AValue);
end;

procedure TNotificationsPainter.DrawSeverity(const ACenter: TPoint; ASeverity: TAtlasNotificationSeverity);
var
  mRadius: Integer;
  mGlyph: string;
  mPart: TRect;
  mSignal: TAtlasSignal;
begin
  mRadius := Scale(8);
  mSignal := TAtlasNotificationTexts.SeveritySignal(Colors, ASeverity);
  Canvas.Pen.Color := ToColor(mSignal.Ring);
  Canvas.Brush.Color := ToColor(mSignal.Fill);
  Canvas.Brush.Style := bsSolid;
  Canvas.Ellipse(ACenter.X - mRadius, ACenter.Y - mRadius, ACenter.X + mRadius + 1, ACenter.Y + mRadius + 1);
  case ASeverity of
    TAtlasNotificationSeverity.Warning:
      mGlyph := '!';
    TAtlasNotificationSeverity.Error:
      mGlyph := '×';
  else
    mGlyph := 'i';
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(mSignal.Mark);
  mPart := Rect(ACenter.X - mRadius, ACenter.Y - mRadius, ACenter.X + mRadius + 1, ACenter.Y + mRadius + 1);
  DrawText(Canvas.Handle, PChar(mGlyph), -1, mPart, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
end;

procedure TNotificationsPainter.DrawEntryBack(AIndex: Integer; const AEntry: TRect);
var
  mItem: IAtlasNotification;
begin
  mItem := Window.FRows.Items[AIndex];
  // Ungelesen hinterlegt, mit Balken in der Farbe der Schwere.
  Canvas.Brush.Style := bsSolid;
  if not mItem.Read then
  begin
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.FillRect(AEntry);
    Canvas.Brush.Color := ToColor(TAtlasNotificationTexts.SeveritySignal(Colors, mItem.Severity).Solid);
    Canvas.FillRect(Rect(AEntry.Left, AEntry.Top, AEntry.Left + Scale(3), AEntry.Bottom));
  end;
  if (AIndex = Window.FRows.Selected) or ((AIndex = Window.FRows.HotRow) and (Window.FRows.HotChip < 0)) then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := ToColor(Colors.Line);
    Canvas.Rectangle(AEntry.Left + Scale(4), AEntry.Top + 1, AEntry.Right - 1, AEntry.Bottom - 1);
  end;
  DrawSeverity(Point(AEntry.Left + Scale(18), AEntry.Top + Scale(6) + Geometry.Line div 2), mItem.Severity);
end;

procedure TNotificationsPainter.DrawEntryTexts(const AItem: IAtlasNotification; const AEntry: TRect);
var
  mPart: TRect;
  mText, mRight: string;
begin
  Canvas.Brush.Style := bsClear;
  // Rechts Quelle und Uhrzeit, gedämpft.
  mRight := TAtlasNotificationTexts.SourceCaption(AItem.Source) + ' · ' +
    TAtlasNotificationTexts.TimeText(AItem.Time, Now);
  Canvas.Font.Color := ToColor(Colors.Muted);
  mPart := Rect(AEntry.Left + Scale(34), AEntry.Top + Scale(6), AEntry.Right - Scale(10),
    AEntry.Top + Scale(6) + Geometry.Line);
  DrawText(Canvas.Handle, PChar(mRight), -1, mPart, DT_SINGLELINE or DT_RIGHT or DT_NOPREFIX);
  mPart.Right := mPart.Right - Canvas.TextWidth(mRight) - Scale(10);
  // Titel mit Zähler; ungelesen fett.
  if not AItem.Read then
  begin
    Canvas.Font.Style := [fsBold];
  end;
  Canvas.Font.Color := ToColor(Colors.Text);
  mText := AItem.Caption;
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  // Text in der zweiten Zeile.
  mPart := Rect(AEntry.Left + Scale(34), mPart.Bottom, AEntry.Right - Scale(10), mPart.Bottom + Geometry.Line);
  Canvas.Font.Color := ToColor(Colors.Muted);
  mText := AItem.Text;
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TNotificationsPainter.DrawChips(AIndex: Integer);
var
  mActions: TArray<TAtlasNotificationAction>;
  mChip: TRect;
  mIndex: Integer;
  mText: string;
begin
  // Aktionen als Knöpfe.
  mActions := Window.FRows.Items[AIndex].Actions;
  for mIndex := 0 to High(mActions) do
  begin
    mChip := Geometry.ChipRect(AIndex, mIndex);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Surface);
    if (AIndex = Window.FRows.HotRow) and (mIndex = Window.FRows.HotChip) then
    begin
      Canvas.Brush.Color := ToColor(Colors.AccentSoft);
    end;
    Canvas.Pen.Color := ToColor(Colors.Accent);
    Canvas.RoundRect(mChip.Left, mChip.Top, mChip.Right, mChip.Bottom, Scale(2 * TAtlasDraw.ChipRadius),
      Scale(2 * TAtlasDraw.ChipRadius));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(Colors.Accent);
    mText := mActions[mIndex].Caption;
    DrawText(Canvas.Handle, PChar(mText), -1, mChip, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  end;
end;

procedure TNotificationsPainter.DrawEntry(AIndex: Integer);
var
  mEntry: TRect;
begin
  mEntry := Geometry.EntryRect(AIndex);
  DrawEntryBack(AIndex, mEntry);
  DrawEntryTexts(Window.FRows.Items[AIndex], mEntry);
  DrawChips(AIndex);
end;

procedure TNotificationsPainter.DrawThumb;
var
  mList: TRect;
  mVisible, mThumbHeight, mThumbTop: Integer;
begin
  // Daumen, wenn die Liste länger ist als der Bereich.
  mList := Geometry.List;
  mVisible := Geometry.VisibleHeight;
  if Window.FRows.ContentHeight <= mVisible then
  begin
    Exit;
  end;
  mThumbHeight := Max(Scale(16), MulDiv(mVisible, mVisible, Window.FRows.ContentHeight));
  mThumbTop := mList.Top + MulDiv(Window.FRows.Scroll, mVisible - mThumbHeight,
    Max(1, Window.FRows.ContentHeight - mVisible));
  TAtlasDraw.Thumb(Canvas, Rect(mList.Right - Scale(5), mThumbTop, mList.Right - Scale(1),
    mThumbTop + mThumbHeight), Colors, Scale(2));
end;

procedure TNotificationsPainter.DrawList;
var
  mIndex: Integer;
  mList, mPart: TRect;
  mText: string;
begin
  mList := Geometry.List;
  IntersectClipRect(Canvas.Handle, mList.Left, mList.Top, mList.Right, mList.Bottom);
  try
    if Length(Window.FRows.Items) = 0 then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(Colors.Muted);
      mText := TAtlasStrings.Text(TAtlasTextId.NotificationsEmpty);
      mPart := mList;
      DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
    end;
    for mIndex := 0 to High(Window.FRows.Items) do
    begin
      mPart := Geometry.EntryRect(mIndex);
      if (mPart.Bottom > mList.Top) and (mPart.Top < mList.Bottom) then
      begin
        DrawEntry(mIndex);
      end;
    end;
    DrawThumb;
  finally
    SelectClipRgn(Canvas.Handle, 0);
  end;
end;

procedure TNotificationsPainter.DrawHeader;
var
  mPart: TRect;
  mText: string;
  mUnread: Integer;
begin
  // Kopf: Titel und Zahl der ungelesenen.
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Text);
  mPart := Rect(Scale(12), 0, Window.FParts.FilterBox.Left - Scale(8), Geometry.Header);
  mText := TAtlasStrings.Text(TAtlasTextId.NotificationsCommand);
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  mPart.Left := mPart.Left + Canvas.TextWidth(mText) + Scale(8);
  Canvas.Font.Style := [];
  mUnread := 0;
  if Window.FCenter <> nil then
  begin
    mUnread := Window.FCenter.UnreadCount;
  end;
  if mUnread > 0 then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
    mText := TAtlasStrings.Fmt(TAtlasTextId.NotificationsUnread, [mUnread]);
    DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
end;

procedure TNotificationsPainter.Paint;
var
  mFoot: Integer;
begin
  Canvas.Font := Window.Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(Window.ClientRect);
  DrawList;
  DrawHeader;
  mFoot := Window.ClientHeight - Scale(cButtonsHeight);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, Geometry.Header - 1);
  Canvas.LineTo(Window.ClientWidth, Geometry.Header - 1);
  Canvas.MoveTo(0, mFoot);
  Canvas.LineTo(Window.ClientWidth, mFoot);
  // Rahmen des Fensters in Akzentfarbe.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(Colors.Accent);
  Canvas.Rectangle(Window.ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

{ TAtlasNotificationsWindow }

constructor TAtlasNotificationsWindow.CreateList(AOwner: TComponent; const AColors: TAtlasColors;
  const ACenter: IAtlasNotificationCenter);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  FCenter := ACenter;
  FRows.Selected := -1;
  FRows.HotRow := -1;
  FRows.HotChip := -1;
  FState.MenuRow := -1;
  BorderStyle := bsNone;
  KeyPreview := True;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnDeactivate := FormDeactivate;
  FParts.FilterBox := TComboBox.Create(Self);
  FParts.FilterBox.Parent := Self;
  FParts.FilterBox.Style := csDropDownList;
  FParts.FilterBox.OnChange := FilterChange;
  FParts.AllReadButton := TButton.Create(Self);
  FParts.AllReadButton.Parent := Self;
  FParts.AllReadButton.Caption := TAtlasStrings.Text(TAtlasTextId.NotificationsAllRead);
  FParts.AllReadButton.OnClick := AllReadClick;
  FParts.ClearButton := TButton.Create(Self);
  FParts.ClearButton.Parent := Self;
  FParts.ClearButton.Caption := TAtlasStrings.Text(TAtlasTextId.NotificationsClear);
  FParts.ClearButton.OnClick := ClearClick;
  FParts.Menu := TPopupMenu.Create(Self);
  Reload;
end;

procedure TAtlasNotificationsWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TAtlasNotificationsWindow.Layout;
var
  mGeometry: TNotificationsGeometry;
  mListHeight: Integer;
begin
  mGeometry := TNotificationsGeometry.Create(Self);
  ClientWidth := ScaleValue(440);
  FRows.Measure(mGeometry.Line, ScaleValue(12));
  if Length(FRows.Items) = 0 then
  begin
    mListHeight := 3 * mGeometry.Line;
  end
  else
  begin
    mListHeight := Min(FRows.ContentHeight, ScaleValue(cMaxListHeight));
  end;
  ClientHeight := mGeometry.Header + mListHeight + ScaleValue(cButtonsHeight);
  FRows.ScrollTo(FRows.Scroll, TNotificationsGeometry.Create(Self).VisibleHeight);
  PlaceControls;
end;

procedure TAtlasNotificationsWindow.PlaceControls;
var
  mGap, mButtonWidth, mTop, mHeader: Integer;
begin
  mGap := ScaleValue(8);
  mHeader := TNotificationsGeometry.Create(Self).Header;
  FParts.FilterBox.Width := ScaleValue(170);
  FParts.FilterBox.Left := ClientWidth - FParts.FilterBox.Width - mGap;
  FParts.FilterBox.Top := (mHeader - FParts.FilterBox.Height) div 2;
  Canvas.Font := Font;
  mButtonWidth := Max(Canvas.TextWidth(FParts.AllReadButton.Caption),
    Canvas.TextWidth(FParts.ClearButton.Caption)) + ScaleValue(24);
  mTop := ClientHeight - ScaleValue(cButtonsHeight) + mGap;
  FParts.AllReadButton.SetBounds(ScaleValue(10), mTop, mButtonWidth, ScaleValue(25));
  FParts.ClearButton.SetBounds(ScaleValue(20) + mButtonWidth, mTop, mButtonWidth, ScaleValue(25));
  FParts.AllReadButton.Enabled := (FCenter <> nil) and (FCenter.UnreadCount > 0);
  FParts.ClearButton.Enabled := (FCenter <> nil) and (Length(FCenter.Items()) > 0);
end;

procedure TAtlasNotificationsWindow.FillFilter;
var
  mSource: string;
  mSources: TArray<string>;
  mIndex, mFound: Integer;
begin
  FFilter.Updating := True;
  try
    mSources := nil;
    if FCenter <> nil then
    begin
      mSources := FCenter.Sources;
    end;
    // Gewählte Quelle ohne Einträge (z. B. nach „Liste leeren“) bleibt wählbar.
    mFound := -1;
    for mIndex := 0 to High(mSources) do
    begin
      if SameText(mSources[mIndex], FFilter.Source) then
      begin
        mFound := mIndex;
      end;
    end;
    if (FFilter.Source <> '') and (mFound < 0) then
    begin
      mSources := mSources + [FFilter.Source];
    end;
    FFilter.Sources := [''] + mSources;
    FParts.FilterBox.Items.BeginUpdate;
    try
      FParts.FilterBox.Items.Clear;
      FParts.FilterBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.NotificationsFilterAll));
      for mSource in mSources do
      begin
        FParts.FilterBox.Items.Add(TAtlasNotificationTexts.SourceCaption(mSource));
      end;
    finally
      FParts.FilterBox.Items.EndUpdate;
    end;
    FParts.FilterBox.ItemIndex := 0;
    for mIndex := 1 to High(FFilter.Sources) do
    begin
      if SameText(FFilter.Sources[mIndex], FFilter.Source) then
      begin
        FParts.FilterBox.ItemIndex := mIndex;
      end;
    end;
  finally
    FFilter.Updating := False;
  end;
end;

procedure TAtlasNotificationsWindow.Reload;
var
  mSelectedId: Integer;
begin
  mSelectedId := FRows.SelectedId;
  FRows.Items := nil;
  if FCenter <> nil then
  begin
    FRows.Items := FCenter.Items(FFilter.Source);
  end;
  FRows.SelectId(mSelectedId);
  FRows.HotRow := -1;
  FRows.HotChip := -1;
  FillFilter;
  Layout;
  if Visible then
  begin
    SetBounds(FState.Anchor.X, FState.Anchor.Y - Height, Width, Height);
  end;
  Invalidate;
end;

procedure TAtlasNotificationsWindow.SetFilter(const ASource: string);
begin
  FFilter.Source := Trim(ASource);
  FRows.Scroll := 0;
  Reload;
end;

procedure TAtlasNotificationsWindow.ShowAbove(const AAnchor: TPoint);
var
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  Layout;
  mArea := Screen.MonitorFromPoint(AAnchor).WorkareaRect;
  mLeft := EnsureRange(AAnchor.X, mArea.Left, Max(mArea.Left, mArea.Right - Width));
  mTop := Max(mArea.Top, AAnchor.Y - Height);
  FState.Anchor := Point(mLeft, mTop + Height);
  SetBounds(mLeft, mTop, Width, Height);
  Show;
  // Die Liste hat die Tastatur (Pfeile, Eingabe); Tab führt zu Filter und Knöpfen.
  ActiveControl := nil;
  SetFocus;
end;

procedure TAtlasNotificationsWindow.Dismiss;
begin
  if FState.Closing then
  begin
    Exit;
  end;
  FState.Closing := True;
  Close;
  Release;
end;

procedure TAtlasNotificationsWindow.CloseAndRun(const AProc: TProc);
begin
  if FState.Closing then
  begin
    Exit;
  end;
  Dismiss;
  // Erst nach dem Schließen ausführen: Die Aktion springt in den Editor oder öffnet ein Fenster.
  if Assigned(AProc) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Notifications,
      procedure
      begin
        AProc();
      end);
  end;
end;

procedure TAtlasNotificationsWindow.FormDeactivate(Sender: TObject);
begin
  // Das eigene Kontextmenü nimmt den Fokus nicht weg; sicherheitshalber offen lassen.
  if not FState.MenuOpen then
  begin
    Dismiss;
  end;
end;

procedure TAtlasNotificationsWindow.FilterChange(Sender: TObject);
begin
  if FFilter.Updating or (FParts.FilterBox.ItemIndex < 0) or
    (FParts.FilterBox.ItemIndex > High(FFilter.Sources)) then
  begin
    Exit;
  end;
  SetFilter(FFilter.Sources[FParts.FilterBox.ItemIndex]);
end;

procedure TAtlasNotificationsWindow.AllReadClick(Sender: TObject);
begin
  if FCenter = nil then
  begin
    Exit;
  end;
  FCenter.MarkAllRead;
  Reload;
end;

procedure TAtlasNotificationsWindow.ClearClick(Sender: TObject);
begin
  if FCenter = nil then
  begin
    Exit;
  end;
  FCenter.Clear;
  FRows.Scroll := 0;
  Reload;
end;

procedure TAtlasNotificationsWindow.ClickRow(ARow: Integer);
begin
  if not FRows.Valid(ARow) or (FCenter = nil) then
  begin
    Exit;
  end;
  FRows.Selected := ARow;
  if not FRows.Items[ARow].Read then
  begin
    FCenter.MarkRead(FRows.Items[ARow].Id);
  end;
  Reload;
end;

procedure TAtlasNotificationsWindow.ClickAction(ARow, AAction: Integer);
var
  mCenter: IAtlasNotificationCenter;
  mId: Integer;
begin
  if not FRows.Valid(ARow) or (FCenter = nil) then
  begin
    Exit;
  end;
  if (AAction < 0) or (AAction > High(FRows.Items[ARow].Actions)) then
  begin
    Exit;
  end;
  mCenter := FCenter;
  mId := FRows.Items[ARow].Id;
  CloseAndRun(
    procedure
    begin
      mCenter.RunAction(mId, AAction);
    end);
end;

function TAtlasNotificationsWindow.BuildMenu(ARow: Integer): TPopupMenu;
var
  mItem: TMenuItem;
  mMode: TAtlasNotificationMode;
  mCurrent: TAtlasNotificationMode;
  mSource: string;
const
  cModeTexts: array[TAtlasNotificationMode] of TAtlasTextId = (TAtlasTextId.NotificationsModeShow,
    TAtlasTextId.NotificationsModeCollect, TAtlasTextId.NotificationsModeOff);
begin
  Result := FParts.Menu;
  FParts.Menu.Items.Clear;
  FState.MenuRow := -1;
  if not FRows.Valid(ARow) or (FCenter = nil) then
  begin
    Exit;
  end;
  FState.MenuRow := ARow;
  mSource := FRows.Items[ARow].Source;
  mItem := TMenuItem.Create(FParts.Menu);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.NotificationsMarkRead);
  mItem.Tag := cMarkReadTag;
  mItem.Enabled := not FRows.Items[ARow].Read;
  mItem.OnClick := MenuClick;
  FParts.Menu.Items.Add(mItem);
  FParts.Menu.Items.Add(NewLine);
  mItem := TMenuItem.Create(FParts.Menu);
  mItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.NotificationsModeMenu,
    [TAtlasNotificationTexts.SourceCaption(mSource)]);
  mItem.Enabled := False;
  FParts.Menu.Items.Add(mItem);
  mCurrent := FCenter.ModeOf(mSource);
  for mMode := Low(TAtlasNotificationMode) to High(TAtlasNotificationMode) do
  begin
    mItem := TMenuItem.Create(FParts.Menu);
    mItem.Caption := TAtlasStrings.Text(cModeTexts[mMode]);
    mItem.Tag := cModeTag + Ord(mMode);
    mItem.RadioItem := True;
    mItem.GroupIndex := 1;
    mItem.Checked := mMode = mCurrent;
    mItem.OnClick := MenuClick;
    FParts.Menu.Items.Add(mItem);
  end;
end;

procedure TAtlasNotificationsWindow.MenuClick(Sender: TObject);
var
  mTag: Integer;
  mSource: string;
  mMode: TAtlasNotificationMode;
  mHandler: TAtlasNotificationModeEvent;
begin
  if not FRows.Valid(FState.MenuRow) or (FCenter = nil) then
  begin
    Exit;
  end;
  mTag := (Sender as TMenuItem).Tag;
  if mTag = cMarkReadTag then
  begin
    ClickRow(FState.MenuRow);
    Exit;
  end;
  if (mTag < cModeTag) or (mTag > cModeTag + Ord(High(TAtlasNotificationMode))) then
  begin
    Exit;
  end;
  mSource := FRows.Items[FState.MenuRow].Source;
  mMode := TAtlasNotificationMode(mTag - cModeTag);
  FCenter.SetMode(mSource, mMode);
  mHandler := FOnModeChange;
  if Assigned(mHandler) then
  begin
    mHandler(mSource, mMode);
  end;
  Reload;
end;

function TAtlasNotificationsWindow.ListKey(AKey: Word): Boolean;
begin
  // Nur ohne Fokus auf Filter oder Knöpfen; dort gelten deren Tasten.
  Result := (ActiveControl = nil) and (Length(FRows.Items) > 0);
  if not Result then
  begin
    Exit;
  end;
  case AKey of
    VK_UP:
      FRows.Selected := Max(0, FRows.Selected - 1);
    VK_DOWN:
      FRows.Selected := Min(High(FRows.Items), FRows.Selected + 1);
    VK_RETURN, VK_DELETE:
      begin
        Result := FRows.Valid(FRows.Selected);
        // Eingabe führt die erste Aktion aus (ohne Aktion: gelesen), Entf markiert als gelesen.
        if Result and (AKey = VK_RETURN) and (Length(FRows.Items[FRows.Selected].Actions) > 0) then
        begin
          ClickAction(FRows.Selected, 0);
        end
        else if Result then
        begin
          ClickRow(FRows.Selected);
        end;
        Exit;
      end;
  else
    Exit(False);
  end;
  FRows.EnsureVisible(FRows.Selected, TNotificationsGeometry.Create(Self).VisibleHeight);
  Invalidate;
end;

procedure TAtlasNotificationsWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Dismiss;
    Exit;
  end;
  if ListKey(Key) then
  begin
    Key := 0;
    Exit;
  end;
  inherited;
end;

procedure TAtlasNotificationsWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mRow, mChip: Integer;
begin
  inherited;
  mRow := TNotificationsGeometry.Create(Self).HitTest(Point(X, Y), mChip);
  if mChip >= 0 then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if (mRow <> FRows.HotRow) or (mChip <> FRows.HotChip) then
  begin
    FRows.HotRow := mRow;
    FRows.HotChip := mChip;
    Invalidate;
  end;
end;

procedure TAtlasNotificationsWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if (FRows.HotRow >= 0) or (FRows.HotChip >= 0) then
  begin
    FRows.HotRow := -1;
    FRows.HotChip := -1;
    Invalidate;
  end;
end;

procedure TAtlasNotificationsWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mRow, mChip: Integer;
  mScreen: TPoint;
begin
  inherited;
  mRow := TNotificationsGeometry.Create(Self).HitTest(Point(X, Y), mChip);
  if mRow < 0 then
  begin
    Exit;
  end;
  if Button = mbRight then
  begin
    FRows.Selected := mRow;
    Invalidate;
    BuildMenu(mRow);
    mScreen := ClientToScreen(Point(X, Y));
    FState.MenuOpen := True;
    try
      FParts.Menu.Popup(mScreen.X, mScreen.Y);
    finally
      FState.MenuOpen := False;
    end;
    Exit;
  end;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  if mChip >= 0 then
  begin
    ClickAction(mRow, mChip);
  end
  else
  begin
    ClickRow(mRow);
  end;
end;

function TAtlasNotificationsWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mGeometry: TNotificationsGeometry;
begin
  mGeometry := TNotificationsGeometry.Create(Self);
  FRows.ScrollTo(FRows.Scroll - (WheelDelta div WHEEL_DELTA) * 3 * mGeometry.Line, mGeometry.VisibleHeight);
  Invalidate;
  Result := True;
end;

procedure TAtlasNotificationsWindow.Paint;
begin
  TNotificationsPainter.Create(Self).Paint;
end;

end.
