unit Atlas.UI.Generate.Window;

// Fenster des Erzeugen-Menüs (#719) im Stil der Befehlspalette, am Cursor:
// oben der Titel „Erzeugen“, darunter Gruppenköpfe (Zuletzt gewählt,
// Erzeugen, Umschließen, Vorlagen) und Einträge mit Ziffer 1–9, Beschriftung
// und gedimmtem /name rechts (keys.generateMenu.showCommandNames); unten der
// Hinweis bzw. der getippte Filter. Wie die Palette nimmt das Fenster den
// Fokus; Escape oder ein Klick daneben schließt es.
// Tasten in der Liste: Ziffer wählt, Tippen filtert unscharf (#229), Pfeile,
// Bild auf/ab, Pos1/Ende, Enter, Rücktaste, Entf blendet den Eintrag aus
// (OnHide speichert keys.generateMenu.hidden).
// Braucht ein Eintrag ein Argument oder bietet er eine Auswahl (Felder für
// /ctor, Methoden für /override, Interface-Methoden …), folgt ein zweiter
// Schritt: Tippen filtert die Auswahl, bei Mehrfachauswahl schaltet die
// Leertaste (vorab alle gewählt, außer das Argument ist Pflicht), eine
// eigene Eingabe steht als letzte Zeile „„…“ verwenden“ bereit, Escape bzw.
// Rücktaste im leeren Feld führt zurück zur Liste.
// Ausgeführt wird über OnExecute erst nach dem Schließen (TAtlasMainThread).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Generate.Menu,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasGenerateChoicesFunc = reference to function(const AEntry: TAtlasGenerateEntry): TArray<string>;
  TAtlasGenerateExecuteProc = reference to procedure(const AEntry: TAtlasGenerateEntry; const AArgument: string);
  TAtlasGenerateHideProc = reference to procedure(const AEntry: TAtlasGenerateEntry);

  /// <summary>Beschriftungen des Erzeugen-Menüs in der Sprache der Oberfläche.</summary>
  TAtlasGenerateTexts = class
  public
    /// <summary>Beschriftung eines Eintrags: Schnellbefehle mit eigenem Text in der Sprache der Oberfläche, sonst
    /// die Beschriftung des Eintrags (Kurzbeschreibung des Servers, Name der Vorlage, Titel der Code-Aktion).
    /// </summary>
    class function EntryCaption(const AEntry: TAtlasGenerateEntry): string; static;
    class function GroupCaption(AGroup: TAtlasGenerateGroup): string; static;
  end;

  /// <summary>Zweiter Schritt (Argument oder Auswahl): Eintrag, Auswahl mit Häkchen, gefilterte Reihenfolge und die
  /// getippte Eingabe.</summary>
  TAtlasGenerateStep = record
    Active: Boolean;
    Entry: TAtlasGenerateEntry;
    Choices: TArray<string>;
    Checked: TArray<Boolean>;
    /// <summary>Gefilterte Auswahl als Indizes in Choices.</summary>
    Order: TArray<Integer>;
    Text: string;
    /// <summary>Eigene Eingabe als letzte Zeile „„…“ verwenden“: getippt und nicht schon in der Auswahl.</summary>
    function HasFreeTextRow: Boolean;
    function RowCount: Integer;
    /// <summary>Häkchen der Zeile ARow umschalten (nur Mehrfachauswahl); True, wenn sich etwas geändert hat.
    /// </summary>
    function Toggle(ARow: Integer): Boolean;
    /// <summary>Argument für die gewählte Zeile ASelected: eigene Eingabe, die gewählten Einträge oder der Eintrag.
    /// </summary>
    function Argument(ASelected: Integer): string;
  end;

  TAtlasGenerateEvents = record
    Choices: TAtlasGenerateChoicesFunc;
    Execute: TAtlasGenerateExecuteProc;
    Hide: TAtlasGenerateHideProc;
  end;

  TAtlasGenerateWindow = class(TAtlasPopupForm)
  private const
    cVisibleRows = 14;
  private
    FEntries: TArray<TAtlasGenerateEntry>;
    FOptions: TAtlasGenerateOptions;
    FRecent: TAtlasGenerateRecent;
    FPattern: string;
    FRows: TArray<TAtlasGenerateRow>;
    FSelected: Integer;
    FTop: Integer;
    FStep: TAtlasGenerateStep;
    FDone: Boolean;
    FEvents: TAtlasGenerateEvents;
    function RowCount: Integer;
    procedure Rebuild;
    procedure RefilterChoices;
    procedure SelectRow(ARow: Integer);
    procedure Step(ADelta: Integer);
    procedure ChooseRow(ARow: Integer);
    procedure EnterStep(const AEntry: TAtlasGenerateEntry);
    procedure LeaveStep;
    procedure ConfirmStep;
    procedure Finish(const AEntry: TAtlasGenerateEntry; const AArgument: string);
    procedure HideSelected;
    /// <summary>Rücktaste: im Schritt Eingabe kürzen bzw. zurück zur Liste, sonst Filter kürzen (Strg: leeren).
    /// </summary>
    procedure Backspace(AShift: TShiftState);
    procedure UpdateHeight;
    procedure FormDeactivate(Sender: TObject);
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>ARecent gehört weiter dem Aufrufer und darf nil sein.</summary>
    constructor CreateMenu(AOwner: TComponent; const AEntries: TArray<TAtlasGenerateEntry>;
      const AOptions: TAtlasGenerateOptions; ARecent: TAtlasGenerateRecent; const AColors: TAtlasColors);
    /// <summary>Unter dem Caret (Bildschirmkoordinaten), passt es dort nicht hin, darüber.</summary>
    procedure ShowAt(const ACaret: TRect);
    /// <summary>Oben mittig über AArea, wenn kein Caret bekannt ist.</summary>
    procedure ShowOver(const AArea: TRect);
    /// <summary>Mögliche Argumente holen (Server); läuft im Hauptthread, solange das Fenster offen ist.</summary>
    property OnChoices: TAtlasGenerateChoicesFunc read FEvents.Choices write FEvents.Choices;
    /// <summary>Nach dem Schließen; das Fenster gibt sich danach selbst frei.</summary>
    property OnExecute: TAtlasGenerateExecuteProc read FEvents.Execute write FEvents.Execute;
    /// <summary>Entf: Eintrag dauerhaft ausblenden (Einstellung speichern).</summary>
    property OnHide: TAtlasGenerateHideProc read FEvents.Hide write FEvents.Hide;
    /// <summary>Zum Testen: Zeilen der Liste und gewählte Zeile.</summary>
    property Rows: TArray<TAtlasGenerateRow> read FRows;
    property Selected: Integer read FSelected;
    property InStep: Boolean read FStep.Active;
  end;

implementation

uses
  Atlas.Core.Style.Color,
  System.Math,
  Atlas.UI.Generate.Strings,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Completion.Presentation;

type
  TCommandCaption = record
    Name: string;
    Id: TAtlasGenerateTextId;
  end;

const
  // Eigene Beschriftungen der Schnellbefehle; die Kurzbeschreibungen des Servers gibt es nur auf Deutsch.
  cCommandCaptions: array[0..51] of TCommandCaption = (
    (Name: 'ctor'; Id: TAtlasGenerateTextId.GenerateCmdCtor),
    (Name: 'dtor'; Id: TAtlasGenerateTextId.GenerateCmdDtor),
    (Name: 'prop'; Id: TAtlasGenerateTextId.GenerateCmdProp),
    (Name: 'override'; Id: TAtlasGenerateTextId.GenerateCmdOverride),
    (Name: 'implement'; Id: TAtlasGenerateTextId.GenerateCmdImplement),
    (Name: 'equals'; Id: TAtlasGenerateTextId.GenerateCmdEquals),
    (Name: 'impl'; Id: TAtlasGenerateTextId.GenerateCmdImpl),
    (Name: 'field'; Id: TAtlasGenerateTextId.GenerateCmdField),
    (Name: 'encapsulate'; Id: TAtlasGenerateTextId.GenerateCmdEncapsulate),
    (Name: 'clone'; Id: TAtlasGenerateTextId.GenerateCmdClone),
    (Name: 'assign'; Id: TAtlasGenerateTextId.GenerateCmdAssign),
    (Name: 'json'; Id: TAtlasGenerateTextId.GenerateCmdJson),
    (Name: 'msg'; Id: TAtlasGenerateTextId.GenerateCmdMsg),
    (Name: 'notify'; Id: TAtlasGenerateTextId.GenerateCmdNotify),
    (Name: 'changed'; Id: TAtlasGenerateTextId.GenerateCmdChanged),
    (Name: 'loaded'; Id: TAtlasGenerateTextId.GenerateCmdLoaded),
    (Name: 'notification'; Id: TAtlasGenerateTextId.GenerateCmdNotification),
    (Name: 'singleton'; Id: TAtlasGenerateTextId.GenerateCmdSingleton),
    (Name: 'list'; Id: TAtlasGenerateTextId.GenerateCmdList),
    (Name: 'dict'; Id: TAtlasGenerateTextId.GenerateCmdDict),
    (Name: 'dict!'; Id: TAtlasGenerateTextId.GenerateCmdDictBang),
    (Name: 'operator'; Id: TAtlasGenerateTextId.GenerateCmdOperator),
    (Name: 'guid'; Id: TAtlasGenerateTextId.GenerateCmdGuid),
    (Name: 'var'; Id: TAtlasGenerateTextId.GenerateCmdVar),
    (Name: 'const'; Id: TAtlasGenerateTextId.GenerateCmdConst),
    (Name: 'const!'; Id: TAtlasGenerateTextId.GenerateCmdConstBang),
    (Name: 'guard'; Id: TAtlasGenerateTextId.GenerateCmdGuard),
    (Name: 'raise'; Id: TAtlasGenerateTextId.GenerateCmdRaise),
    (Name: 'log'; Id: TAtlasGenerateTextId.GenerateCmdLog),
    (Name: 'sql'; Id: TAtlasGenerateTextId.GenerateCmdSql),
    (Name: 'params'; Id: TAtlasGenerateTextId.GenerateCmdParams),
    (Name: 'record'; Id: TAtlasGenerateTextId.GenerateCmdRecord),
    (Name: 'enum'; Id: TAtlasGenerateTextId.GenerateCmdEnum),
    (Name: 'enum!'; Id: TAtlasGenerateTextId.GenerateCmdEnumBang),
    (Name: 'helper'; Id: TAtlasGenerateTextId.GenerateCmdHelper),
    (Name: 'exception'; Id: TAtlasGenerateTextId.GenerateCmdException),
    (Name: 'thread'; Id: TAtlasGenerateTextId.GenerateCmdThread),
    (Name: 'external'; Id: TAtlasGenerateTextId.GenerateCmdExternal),
    (Name: 'exports'; Id: TAtlasGenerateTextId.GenerateCmdExports),
    (Name: 'todo'; Id: TAtlasGenerateTextId.GenerateCmdTodo),
    (Name: 'try'; Id: TAtlasGenerateTextId.GenerateCmdTry),
    (Name: 'except'; Id: TAtlasGenerateTextId.GenerateCmdExcept),
    (Name: 'lock'; Id: TAtlasGenerateTextId.GenerateCmdLock),
    (Name: 'sync'; Id: TAtlasGenerateTextId.GenerateCmdSync),
    (Name: 'sync!'; Id: TAtlasGenerateTextId.GenerateCmdSyncBang),
    (Name: 'ifdef'; Id: TAtlasGenerateTextId.GenerateCmdIfdef),
    (Name: 'region'; Id: TAtlasGenerateTextId.GenerateCmdRegion),
    (Name: 'measure'; Id: TAtlasGenerateTextId.GenerateCmdMeasure),
    (Name: 'task'; Id: TAtlasGenerateTextId.GenerateCmdTask),
    (Name: 'future'; Id: TAtlasGenerateTextId.GenerateCmdFuture),
    (Name: 'loop'; Id: TAtlasGenerateTextId.GenerateCmdLoop),
    (Name: 'transaction'; Id: TAtlasGenerateTextId.GenerateCmdTransaction));

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>Muster ohne führendes "/" für die Hervorhebung in der Beschriftung.</summary>
function CaptionPattern(const APattern: string): string;
begin
  Result := APattern;
  if Result.StartsWith('/') then
  begin
    Delete(Result, 1, 1);
  end;
end;

{ TAtlasGenerateTexts }

class function TAtlasGenerateTexts.EntryCaption(const AEntry: TAtlasGenerateEntry): string;
var
  mItem: TCommandCaption;
begin
  Result := AEntry.Caption;
  if AEntry.Kind <> TAtlasGenerateKind.Slash then
  begin
    Exit;
  end;
  for mItem in cCommandCaptions do
  begin
    if SameText(mItem.Name, AEntry.Name) then
    begin
      Exit(TAtlasGenerateStrings.Text(mItem.Id));
    end;
  end;
  if Result = '' then
  begin
    Result := AEntry.CommandName;
  end;
end;

class function TAtlasGenerateTexts.GroupCaption(AGroup: TAtlasGenerateGroup): string;
begin
  case AGroup of
    TAtlasGenerateGroup.Recent:
      Result := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateGroupRecent);
    TAtlasGenerateGroup.Surround:
      Result := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateGroupSurround);
    TAtlasGenerateGroup.Templates:
      Result := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateGroupTemplates);
  else
    Result := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateGroupGenerate);
  end;
end;

{ TAtlasGenerateStep }

function TAtlasGenerateStep.HasFreeTextRow: Boolean;
var
  mChoice: string;
begin
  Result := Active and (Trim(Text) <> '');
  if not Result then
  begin
    Exit;
  end;
  for mChoice in Choices do
  begin
    if SameText(mChoice, Trim(Text)) then
    begin
      Exit(False);
    end;
  end;
end;

function TAtlasGenerateStep.RowCount: Integer;
begin
  Result := Length(Order);
  if HasFreeTextRow then
  begin
    Inc(Result);
  end;
end;

function TAtlasGenerateStep.Toggle(ARow: Integer): Boolean;
begin
  Result := Active and Entry.Multi and (ARow >= 0) and (ARow <= High(Order));
  if Result then
  begin
    Checked[Order[ARow]] := not Checked[Order[ARow]];
  end;
end;

function TAtlasGenerateStep.Argument(ASelected: Integer): string;
var
  mIndex: Integer;
  mAnyChecked: Boolean;
begin
  if HasFreeTextRow and (ASelected = RowCount - 1) then
  begin
    Exit(Trim(Text));
  end;
  if Entry.Multi and (Length(Choices) > 0) then
  begin
    mAnyChecked := False;
    for mIndex := 0 to High(Checked) do
    begin
      mAnyChecked := mAnyChecked or Checked[mIndex];
    end;
    if not mAnyChecked then
    begin
      Exit(Trim(Text));
    end;
    Exit(TAtlasGenerateMenu.JoinChoices(Choices, Checked, Entry.Separator,
      Entry.Argument <> TAtlasGenerateArgument.Required));
  end;
  if (ASelected >= 0) and (ASelected <= High(Order)) then
  begin
    Exit(Choices[Order[ASelected]]);
  end;
  Result := Trim(Text);
end;

const
  // Maße in Pixeln bei 96 dpi.
  cWidth = 440;
  cScreenMargin = 40;
  cTopOffset = 60;
  cFrameMargin = 4;
  cRowPadding = 8;
  cTitleGap = 6;
  cListMargin = 4;
  cEdge = 12;
  cTextIndent = 8;
  cNameGap = 12;
  cInputMargin = 6;
  cBadgeWidth = 18;
  cBadgeInset = 4;
  cBadgeRadius = 4;
  cCheckSize = 14;
  cCheckInset = 5;
  cCheckColumn = 22;
  // Zeilen je Schritt des Mausrads.
  cWheelRows = 3;

type
  /// <summary>Höhen und Zeilen des Fensters in der Fensterschrift.</summary>
  TAtlasGenerateMetrics = record
    Window: TAtlasGenerateWindow;
    function RowHeight: Integer;
    function TitleHeight: Integer;
    function FooterHeight: Integer;
    function ListTop: Integer;
    function RowRect(AVisibleRow: Integer): TRect;
  end;

  /// <summary>Zeichnen: Titel, Eingabefeld, Zeilen der Liste bzw. Auswahl, leere Liste und Fußzeile.</summary>
  TAtlasGeneratePainter = record
    Window: TAtlasGenerateWindow;
    Metrics: TAtlasGenerateMetrics;
    function Canvas: TCanvas;
    function Px(AValue: Integer): Integer;
    procedure DrawLabel(const AText: string; ARect: TRect; AColor: TAtlasColor; AFlags: Cardinal);
    procedure DrawHighlighted(const AText, APattern: string; const ARect: TRect);
    procedure Badge(const ABounds: TRect; ADigit: Integer);
    procedure ListRow(AVisibleRow: Integer);
    procedure StepRow(AVisibleRow: Integer);
    /// <summary>Titel; liefert seine Fläche.</summary>
    function Title: TRect;
    procedure Input(const ATitle: TRect);
    procedure Empty;
    procedure Footer;
  end;

{ TAtlasGenerateMetrics }

function TAtlasGenerateMetrics.RowHeight: Integer;
begin
  Window.Canvas.Font := Window.Font;
  Result := Window.Canvas.TextHeight('Wg') + Window.ScaleValue(cRowPadding);
end;

function TAtlasGenerateMetrics.TitleHeight: Integer;
begin
  Result := RowHeight + Window.ScaleValue(cTitleGap);
  // Im zweiten Schritt steht unter dem Titel das Eingabefeld.
  if Window.FStep.Active then
  begin
    Inc(Result, RowHeight + Window.ScaleValue(cTitleGap));
  end;
end;

function TAtlasGenerateMetrics.FooterHeight: Integer;
begin
  Result := RowHeight;
end;

function TAtlasGenerateMetrics.ListTop: Integer;
begin
  Result := TitleHeight;
end;

function TAtlasGenerateMetrics.RowRect(AVisibleRow: Integer): TRect;
begin
  Result := Rect(Window.ScaleValue(cListMargin), ListTop + AVisibleRow * RowHeight,
    Window.ClientWidth - Window.ScaleValue(cListMargin),
    ListTop + (AVisibleRow + 1) * RowHeight);
end;

{ TAtlasGeneratePainter }

function TAtlasGeneratePainter.Canvas: TCanvas;
begin
  Result := Window.Canvas;
end;

function TAtlasGeneratePainter.Px(AValue: Integer): Integer;
begin
  Result := Window.ScaleValue(AValue);
end;

procedure TAtlasGeneratePainter.DrawLabel(const AText: string; ARect: TRect; AColor: TAtlasColor; AFlags: Cardinal);
begin
  Canvas.Font.Color := ToColor(AColor);
  DrawText(Canvas.Handle, PChar(AText), -1, ARect, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or AFlags);
end;

procedure TAtlasGeneratePainter.DrawHighlighted(const AText, APattern: string; const ARect: TRect);
var
  mMarks: TArray<Boolean>;
  mPosition, mIndex, mRun, mX: Integer;
  mPart: TRect;
  mChunk: string;
begin
  SetLength(mMarks, Length(AText) + 1);
  if APattern <> '' then
  begin
    for mPosition in TAtlasItemPresentation.Highlights(APattern, AText) do
    begin
      if (mPosition >= 1) and (mPosition <= Length(AText)) then
      begin
        mMarks[mPosition] := True;
      end;
    end;
  end;
  mX := ARect.Left;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mRun := mIndex;
    while (mRun < Length(AText)) and (mMarks[mRun + 1] = mMarks[mIndex]) do
    begin
      Inc(mRun);
    end;
    mChunk := Copy(AText, mIndex, mRun - mIndex + 1);
    Canvas.Font.Style := [];
    Canvas.Font.Color := ToColor(Window.Colors.Text);
    if mMarks[mIndex] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(Window.Colors.Accent);
    end;
    mPart := Rect(mX, ARect.Top, ARect.Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(mChunk), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Inc(mX, Canvas.TextWidth(mChunk));
    mIndex := mRun + 1;
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasGeneratePainter.Badge(const ABounds: TRect; ADigit: Integer);
var
  mBadge: TRect;
begin
  // Ziffer 1–9 als Badge.
  mBadge := Rect(ABounds.Left, ABounds.Top + Px(cBadgeInset), ABounds.Left + Px(cBadgeWidth),
    ABounds.Bottom - Px(cBadgeInset));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Window.Colors.AccentSoft);
  Canvas.Pen.Color := ToColor(Window.Colors.Line);
  Canvas.RoundRect(mBadge.Left, mBadge.Top, mBadge.Right, mBadge.Bottom, Px(cBadgeRadius), Px(cBadgeRadius));
  Canvas.Brush.Style := bsClear;
  DrawLabel(IntToStr(ADigit), mBadge, Window.Colors.Text, DT_CENTER);
end;

procedure TAtlasGeneratePainter.ListRow(AVisibleRow: Integer);
var
  mRow: TAtlasGenerateRow;
  mEntry: TAtlasGenerateEntry;
  mBounds, mPart: TRect;
  mNameWidth: Integer;
begin
  mRow := Window.FRows[Window.FTop + AVisibleRow];
  mBounds := Metrics.RowRect(AVisibleRow);
  Canvas.Brush.Style := bsClear;
  if mRow.IsHeader then
  begin
    Canvas.Font.Size := Window.Font.Size - 1;
    mPart := mBounds;
    Inc(mPart.Left, Px(cTextIndent));
    DrawLabel(TAtlasGenerateTexts.GroupCaption(mRow.Group), mPart, Window.Colors.Muted, 0);
    Canvas.Font.Size := Window.Font.Size;
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  mEntry := Window.FEntries[mRow.Entry];
  if Window.FTop + AVisibleRow = Window.FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Window.Colors.Selection);
    Canvas.FillRect(mBounds);
    Canvas.Brush.Style := bsClear;
  end;
  InflateRect(mBounds, -Px(cTextIndent), 0);
  if mRow.Digit > 0 then
  begin
    Badge(mBounds, mRow.Digit);
  end;
  Inc(mBounds.Left, Px(cBadgeWidth) + Px(cTextIndent));
  // /name gedimmt rechts.
  mNameWidth := 0;
  if Window.FOptions.ShowCommandNames and (mEntry.CommandName <> '') then
  begin
    mNameWidth := Canvas.TextWidth(mEntry.CommandName);
    mPart := Rect(mBounds.Right - mNameWidth, mBounds.Top, mBounds.Right, mBounds.Bottom);
    DrawLabel(mEntry.CommandName, mPart, Window.Colors.Muted, 0);
    Inc(mNameWidth, Px(cNameGap));
  end;
  DrawHighlighted(TAtlasGenerateTexts.EntryCaption(mEntry), CaptionPattern(Window.FPattern),
    Rect(mBounds.Left, mBounds.Top, mBounds.Right - mNameWidth, mBounds.Bottom));
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasGeneratePainter.StepRow(AVisibleRow: Integer);
var
  mIndex: Integer;
  mBounds, mBox: TRect;
  mStep: TAtlasGenerateStep;
begin
  mStep := Window.FStep;
  mIndex := Window.FTop + AVisibleRow;
  mBounds := Metrics.RowRect(AVisibleRow);
  if mIndex = Window.FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Window.Colors.Selection);
    Canvas.FillRect(mBounds);
  end;
  Canvas.Brush.Style := bsClear;
  InflateRect(mBounds, -Px(cTextIndent), 0);
  if mIndex > High(mStep.Order) then
  begin
    // Eigene Eingabe.
    DrawLabel(TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateFreeText, [Trim(mStep.Text)]), mBounds,
      Window.Colors.Text,
      DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  if mStep.Entry.Multi then
  begin
    mBox := Rect(mBounds.Left, mBounds.Top + Px(cCheckInset), mBounds.Left + Px(cCheckSize),
      mBounds.Bottom - Px(cCheckInset));
    Canvas.Pen.Color := ToColor(Window.Colors.Muted);
    if mStep.Checked[mStep.Order[mIndex]] then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Window.Colors.Accent);
    end;
    Canvas.Rectangle(mBox);
    Canvas.Brush.Style := bsClear;
    Inc(mBounds.Left, Px(cCheckColumn));
  end;
  DrawHighlighted(mStep.Choices[mStep.Order[mIndex]], mStep.Text, mBounds);
  Canvas.Brush.Style := bsSolid;
end;

function TAtlasGeneratePainter.Title: TRect;
begin
  // Titel: „Erzeugen“ bzw. der gewählte Eintrag.
  Result := Rect(Px(cEdge), Px(2), Window.ClientWidth - Px(cEdge), Px(2) + Metrics.RowHeight);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  if Window.FStep.Active then
  begin
    DrawLabel(TAtlasGenerateTexts.EntryCaption(Window.FStep.Entry), Result, Window.Colors.Text, DT_END_ELLIPSIS);
  end
  else
  begin
    DrawLabel(TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateTitle), Result, Window.Colors.Text, 0);
  end;
  Canvas.Font.Style := [];
  if Window.FStep.Active and Window.FOptions.ShowCommandNames then
  begin
    DrawLabel(Window.FStep.Entry.CommandName, Result, Window.Colors.Muted, DT_RIGHT);
  end;
  Canvas.Pen.Color := ToColor(Window.Colors.Line);
  Canvas.MoveTo(0, Result.Bottom + Px(2));
  Canvas.LineTo(Window.ClientWidth, Result.Bottom + Px(2));
end;

procedure TAtlasGeneratePainter.Input(const ATitle: TRect);
var
  mInput: TRect;
begin
  // Eingabefeld mit Akzentrahmen.
  mInput := Rect(Px(cInputMargin), ATitle.Bottom + Px(cInputMargin), Window.ClientWidth - Px(cInputMargin),
    ATitle.Bottom + Px(cInputMargin) + Metrics.RowHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Color := ToColor(Window.Colors.Accent);
  Canvas.Brush.Color := ToColor(Window.Colors.Gutter);
  Canvas.Rectangle(mInput);
  InflateRect(mInput, -Px(cTextIndent), 0);
  Canvas.Brush.Style := bsClear;
  if Window.FStep.Text <> '' then
  begin
    DrawLabel(Window.FStep.Text + '|', mInput, Window.Colors.Text, DT_END_ELLIPSIS);
  end
  else if Window.FStep.Entry.Example <> '' then
  begin
    DrawLabel(TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateExample, [Window.FStep.Entry.Example]), mInput,
      Window.Colors.Muted, DT_END_ELLIPSIS);
  end
  else
  begin
    DrawLabel(TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateArgumentPrompt), mInput, Window.Colors.Muted,
      DT_END_ELLIPSIS);
  end;
end;

procedure TAtlasGeneratePainter.Empty;
var
  mReason: string;
begin
  // Leere Liste: Grund statt Zeilen.
  Canvas.Brush.Style := bsClear;
  if Window.FStep.Active then
  begin
    mReason := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateNoChoices);
  end
  else if (Window.FPattern <> '') and (Length(Window.FEntries) > 0) then
  begin
    mReason := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateNoMatch);
  end
  else
  begin
    mReason := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateEmpty);
  end;
  DrawLabel(mReason, Rect(Px(cEdge), Metrics.ListTop, Window.ClientWidth - Px(cEdge),
    Metrics.ListTop + Metrics.RowHeight), Window.Colors.Muted, 0);
end;

procedure TAtlasGeneratePainter.Footer;
var
  mFooter: TRect;
  mHint: string;
begin
  // Fußzeile: Filter oder Hinweis.
  mFooter := Rect(Px(cEdge), Window.ClientHeight - Metrics.FooterHeight - Px(2), Window.ClientWidth - Px(cEdge),
    Window.ClientHeight - Px(2));
  Canvas.Pen.Color := ToColor(Window.Colors.Line);
  Canvas.MoveTo(0, mFooter.Top);
  Canvas.LineTo(Window.ClientWidth, mFooter.Top);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Size := Window.Font.Size - 1;
  if Window.FStep.Active and Window.FStep.Entry.Multi then
  begin
    mHint := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateStepMultiHint);
  end
  else if Window.FStep.Active then
  begin
    mHint := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateStepHint);
  end
  else if Window.FPattern <> '' then
  begin
    mHint := TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateFilter, [Window.FPattern]);
  end
  else
  begin
    mHint := TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateHint);
  end;
  DrawLabel(mHint, mFooter, Window.Colors.Muted, DT_END_ELLIPSIS);
  Canvas.Font.Size := Window.Font.Size;
end;

{ TAtlasGenerateWindow }

constructor TAtlasGenerateWindow.CreateMenu(AOwner: TComponent; const AEntries: TArray<TAtlasGenerateEntry>;
  const AOptions: TAtlasGenerateOptions; ARecent: TAtlasGenerateRecent; const AColors: TAtlasColors);
begin
  inherited CreatePopup(AOwner, AColors);
  PaintsAll := True;
  FEntries := AEntries;
  FOptions := AOptions;
  FRecent := ARecent;
  // Eine Stufe größer als die Dialogschrift, wie die Befehlspalette.
  Font.Size := Font.Size + 1;
  OnDeactivate := FormDeactivate;
  Rebuild;
end;

procedure TAtlasGenerateWindow.Paint;
var
  mPainter: TAtlasGeneratePainter;
  mTitle: TRect;
  mRow: Integer;
begin
  mPainter.Window := Self;
  mPainter.Metrics.Window := Self;
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  mTitle := mPainter.Title;
  if FStep.Active then
  begin
    mPainter.Input(mTitle);
  end;
  Canvas.Brush.Style := bsSolid;
  for mRow := 0 to Min(cVisibleRows, RowCount - FTop) - 1 do
  begin
    if FStep.Active then
    begin
      mPainter.StepRow(mRow);
    end
    else
    begin
      mPainter.ListRow(mRow);
    end;
  end;
  if RowCount = 0 then
  begin
    mPainter.Empty;
  end;
  mPainter.Footer;
  // Rahmen des Fensters.
  Canvas.Pen.Color := ToColor(Colors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasGenerateWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      if FStep.Active then
      begin
        LeaveStep;
      end
      else
      begin
        FormDeactivate(Self);
      end;
    VK_RETURN:
      if FStep.Active then
      begin
        ConfirmStep;
      end
      else
      begin
        ChooseRow(FSelected);
      end;
    VK_UP:
      Step(-1);
    VK_DOWN:
      Step(1);
    VK_PRIOR:
      Step(-cVisibleRows);
    VK_NEXT:
      Step(cVisibleRows);
    VK_HOME:
      Step(-RowCount);
    VK_END:
      Step(RowCount);
    VK_DELETE:
      HideSelected;
    VK_BACK:
      Backspace(Shift);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TAtlasGenerateWindow.KeyPress(var Key: Char);
var
  mRow: Integer;
begin
  if Key < ' ' then
  begin
    Key := #0;
    Exit;
  end;
  if FStep.Active then
  begin
    // Leertaste schaltet bei Mehrfachauswahl, solange nichts getippt ist.
    if (Key = ' ') and FStep.Entry.Multi and (FStep.Text = '') then
    begin
      if FStep.Toggle(FSelected) then
      begin
        Invalidate;
      end;
    end
    else
    begin
      FStep.Text := FStep.Text + Key;
      RefilterChoices;
    end;
    Key := #0;
    Exit;
  end;
  if CharInSet(Key, ['1'..'9']) then
  begin
    mRow := TAtlasGenerateMenu.RowOfDigit(FRows, Ord(Key) - Ord('0'));
    if mRow >= 0 then
    begin
      ChooseRow(mRow);
    end;
  end
  else if Key <> ' ' then
  begin
    FPattern := FPattern + Key;
    Rebuild;
    UpdateHeight;
  end;
  Key := #0;
end;

procedure TAtlasGenerateWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mMetrics: TAtlasGenerateMetrics;
  mRow: Integer;
begin
  inherited;
  mMetrics.Window := Self;
  if (Y < mMetrics.ListTop) or (Y >= ClientHeight - mMetrics.FooterHeight) then
  begin
    Exit;
  end;
  mRow := FTop + (Y - mMetrics.ListTop) div mMetrics.RowHeight;
  if mRow >= RowCount then
  begin
    Exit;
  end;
  if not FStep.Active then
  begin
    ChooseRow(mRow);
    Exit;
  end;
  SelectRow(mRow);
  if FStep.Entry.Multi and (mRow <= High(FStep.Order)) then
  begin
    if FStep.Toggle(FSelected) then
    begin
      Invalidate;
    end;
  end
  else
  begin
    ConfirmStep;
  end;
end;

function TAtlasGenerateWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FTop := EnsureRange(FTop - Sign(WheelDelta) * cWheelRows, 0, Max(0, RowCount - cVisibleRows));
  Invalidate;
  Result := True;
end;

function TAtlasGenerateWindow.RowCount: Integer;
begin
  if FStep.Active then
  begin
    Result := FStep.RowCount;
  end
  else
  begin
    Result := Length(FRows);
  end;
end;

procedure TAtlasGenerateWindow.Rebuild;
begin
  FRows := TAtlasGenerateMenu.Rows(FEntries, FOptions, FRecent, FPattern);
  FTop := 0;
  FSelected := TAtlasGenerateMenu.FirstEntryRow(FRows);
  Invalidate;
end;

procedure TAtlasGenerateWindow.RefilterChoices;
begin
  FStep.Order := TAtlasGenerateMenu.FilterChoices(FStep.Choices, FStep.Text);
  FTop := 0;
  FSelected := 0;
  if RowCount = 0 then
  begin
    FSelected := -1;
  end;
  UpdateHeight;
  Invalidate;
end;

procedure TAtlasGenerateWindow.SelectRow(ARow: Integer);
begin
  if RowCount = 0 then
  begin
    FSelected := -1;
    Invalidate;
    Exit;
  end;
  FSelected := EnsureRange(ARow, 0, RowCount - 1);
  if FSelected < FTop then
  begin
    FTop := FSelected;
  end
  else if FSelected >= FTop + cVisibleRows then
  begin
    FTop := FSelected - cVisibleRows + 1;
  end;
  // Kopf über dem ersten Eintrag mit zeigen.
  if not FStep.Active and (FTop > 0) and (FTop = FSelected) and FRows[FTop - 1].IsHeader then
  begin
    Dec(FTop);
  end;
  Invalidate;
end;

procedure TAtlasGenerateWindow.Step(ADelta: Integer);
var
  mNext, mIndex: Integer;
begin
  if FStep.Active then
  begin
    SelectRow(FSelected + ADelta);
    Exit;
  end;
  mNext := FSelected;
  // Bild auf/ab: mehrere Schritte über Einträge, Köpfe übersprungen.
  for mIndex := 1 to Abs(ADelta) do
  begin
    mNext := TAtlasGenerateMenu.StepRow(FRows, mNext, Sign(ADelta));
  end;
  if mNext >= 0 then
  begin
    SelectRow(mNext);
  end;
end;

procedure TAtlasGenerateWindow.ChooseRow(ARow: Integer);
begin
  if FStep.Active or (ARow < 0) or (ARow > High(FRows)) or FRows[ARow].IsHeader then
  begin
    Exit;
  end;
  FSelected := ARow;
  if FEntries[FRows[ARow].Entry].NeedsStep then
  begin
    EnterStep(FEntries[FRows[ARow].Entry]);
  end
  else
  begin
    Finish(FEntries[FRows[ARow].Entry], '');
  end;
end;

procedure TAtlasGenerateWindow.EnterStep(const AEntry: TAtlasGenerateEntry);
var
  mChoices: TArray<string>;
  mIndex: Integer;
begin
  mChoices := nil;
  if AEntry.HasChoices and Assigned(FEvents.Choices) then
  begin
    Screen.Cursor := crHourGlass;
    try
      mChoices := FEvents.Choices(AEntry);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  // Ohne Auswahl und ohne Pflicht-Argument gleich ausführen (z. B. /ctor in einer Klasse ohne Felder).
  if AEntry.HasChoices and (Length(mChoices) = 0) and (AEntry.Argument <> TAtlasGenerateArgument.Required) then
  begin
    Finish(AEntry, '');
    Exit;
  end;
  FStep := Default(TAtlasGenerateStep);
  FStep.Active := True;
  FStep.Entry := AEntry;
  FStep.Choices := mChoices;
  SetLength(FStep.Checked, Length(mChoices));
  // Mehrfachauswahl: vorab alles gewählt (alle Felder, alle fehlenden Methoden), außer bei Pflicht-Argumenten.
  for mIndex := 0 to High(FStep.Checked) do
  begin
    FStep.Checked[mIndex] := AEntry.Multi and (AEntry.Argument <> TAtlasGenerateArgument.Required);
  end;
  RefilterChoices;
end;

procedure TAtlasGenerateWindow.LeaveStep;
begin
  FStep := Default(TAtlasGenerateStep);
  Rebuild;
  UpdateHeight;
end;

procedure TAtlasGenerateWindow.ConfirmStep;
var
  mArgument: string;
begin
  mArgument := FStep.Argument(FSelected);
  // Pflicht-Argument fehlt: im Schritt bleiben, die Zeile nennt das Beispiel.
  if (mArgument = '') and (FStep.Entry.Argument = TAtlasGenerateArgument.Required) then
  begin
    MessageBeep(MB_OK);
    Exit;
  end;
  Finish(FStep.Entry, mArgument);
end;

procedure TAtlasGenerateWindow.Finish(const AEntry: TAtlasGenerateEntry; const AArgument: string);
var
  mHandler: TAtlasGenerateExecuteProc;
  mEntry: TAtlasGenerateEntry;
  mArgument: string;
begin
  if FDone then
  begin
    Exit;
  end;
  FDone := True;
  mHandler := FEvents.Execute;
  mEntry := AEntry;
  mArgument := AArgument;
  Close;
  // Erst nach dem Schließen ausführen: Der Editor hat dann wieder den Fokus.
  if Assigned(mHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Generate,
      procedure
      begin
        mHandler(mEntry, mArgument);
      end);
  end;
  Release;
end;

procedure TAtlasGenerateWindow.HideSelected;
var
  mEntry: TAtlasGenerateEntry;
begin
  if FStep.Active or (FSelected < 0) or (FSelected > High(FRows)) or FRows[FSelected].IsHeader then
  begin
    Exit;
  end;
  mEntry := FEntries[FRows[FSelected].Entry];
  FOptions.Hidden := FOptions.Hidden + [mEntry.Id];
  if Assigned(FEvents.Hide) then
  begin
    FEvents.Hide(mEntry);
  end;
  Rebuild;
  UpdateHeight;
end;

procedure TAtlasGenerateWindow.Backspace(AShift: TShiftState);
begin
  if FStep.Active then
  begin
    if FStep.Text = '' then
    begin
      LeaveStep;
    end
    else
    begin
      Delete(FStep.Text, Length(FStep.Text), 1);
      RefilterChoices;
    end;
  end
  else if FPattern <> '' then
  begin
    if ssCtrl in AShift then
    begin
      FPattern := '';
    end
    else
    begin
      Delete(FPattern, Length(FPattern), 1);
    end;
    Rebuild;
    UpdateHeight;
  end;
end;

procedure TAtlasGenerateWindow.UpdateHeight;
var
  mMetrics: TAtlasGenerateMetrics;
  mVisible: Integer;
begin
  mMetrics.Window := Self;
  mVisible := EnsureRange(RowCount, 1, cVisibleRows);
  ClientHeight := mMetrics.TitleHeight + mVisible * mMetrics.RowHeight + mMetrics.FooterHeight +
    ScaleValue(cFrameMargin);
end;

procedure TAtlasGenerateWindow.FormDeactivate(Sender: TObject);
begin
  if not FDone then
  begin
    FDone := True;
    Close;
    Release;
  end;
end;

procedure TAtlasGenerateWindow.ShowAt(const ACaret: TRect);
var
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  Width := ScaleValue(cWidth);
  UpdateHeight;
  mArea := Screen.MonitorFromPoint(ACaret.TopLeft, mdNearest).WorkareaRect;
  mLeft := EnsureRange(ACaret.Left, mArea.Left, Max(mArea.Left, mArea.Right - Width));
  mTop := ACaret.Bottom + ScaleValue(2);
  // Unten kein Platz: über die Zeile.
  if mTop + Height > mArea.Bottom then
  begin
    mTop := Max(mArea.Top, ACaret.Top - Height - ScaleValue(2));
  end;
  SetBounds(mLeft, mTop, Width, Height);
  Show;
  SetFocus;
end;

procedure TAtlasGenerateWindow.ShowOver(const AArea: TRect);
begin
  Width := Min(ScaleValue(cWidth), AArea.Width - ScaleValue(cScreenMargin));
  UpdateHeight;
  SetBounds(AArea.Left + (AArea.Width - Width) div 2, AArea.Top + ScaleValue(cTopOffset), Width, Height);
  Show;
  SetFocus;
end;

end.
