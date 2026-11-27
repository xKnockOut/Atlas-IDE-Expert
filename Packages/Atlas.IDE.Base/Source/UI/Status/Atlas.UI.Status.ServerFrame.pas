unit Atlas.UI.Status.ServerFrame;

// Inhalt des Fensters „Atlas-Server“ (#1356), reine VCL:
//   Prozess 4711 · Version 1.2.0 · läuft seit 1 h 05 min · bereit · Neustarts …
//   Warteschlange … · Cache-Treffer …
//   Letzter Prüflauf 14:30: 120 Units in 8 s
//   Speicher: je Bereich ein Balken gegen den Maßstab (Budget bzw. darüber
//   der Prozessspeicher), senkrechter Strich beim Budget, darunter „Prozess
//   gesamt“; über dem Budget in Warnfarbe mit dem Hinweis „Verwendungen
//   werden ausgelagert“.
//   Tabellen: langsamste Units (ms), Regeln (ms, Aufrufe), Anfragen (Anzahl,
//   Mittel, Maximum, Fehler). Doppelklick auf eine Unit meldet OnOpenUnit,
//   auf eine Regel OnOpenRule.
//   [Aktualisieren] [Index neu aufbauen] [Diagnosepaket erstellen …]  Stand …
// Zwei Reiter: „Server“ (alles oben) und „KI-Assistenten“ (#2611, TAtlasServerAssistants): je laufendem
// MCP-Prozess eine Zeile mit Client, Beginn und Summen, darunter Werkzeuge, Ressourcen und Prompts aller
// Sitzungen mit Aufrufen, Fehlern, Dauer, Antwortgröße und letztem fehlgeschlagenem Aufruf; auffällige
// Fehlerquoten in Fehlerfarbe. Die Sitzungen liest die IDE-Schicht aus den Statusdateien (TMcpAssistantSessions);
// die Knopfleiste gilt für beide Reiter.
// Die Zahlen kommen als TAtlasServerSnapshot (Core); abgefragt wird nicht
// hier, sondern in der IDE-Schicht. Speicherbalken (TAtlasServerMemoryChart),
// Tabellen (TAtlasServerTables) und Knopfleiste (TAtlasServerButtons) sind
// eigene Steuerelemente; der Frame setzt sie zusammen. Die Listen sind virtuell (OwnerData),
// damit sie auch ohne Fenster gefüllt werden können. Die DFM ist leer, weil
// TCustomFrame.Create für abgeleitete Frames eine Ressource verlangt;
// aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Plugin.Style.Palette,
  Atlas.Text.McpStatistics,
  Atlas.Plugin.Status.Server;

type
  /// <summary>Speicher: je Bereich ein Balken gegen den Maßstab, senkrechter Strich beim Budget, darunter
  /// „Prozess gesamt“.</summary>
  TAtlasServerMemoryChart = class(TPaintBox)
  private
    FSnapshot: TAtlasServerSnapshot;
    FRunning: Boolean;
    FColors: TAtlasColors;
    FLabelWidth: Integer;
    FValueWidth: Integer;
    function Px(AValue: Integer): Integer;
    function RowHeight: Integer;
    function TotalText: string;
    procedure DrawBar(const ABar: TRect; AFraction: Double; AWarnColor: Boolean);
    procedure DrawRow(AIndex: Integer; const ACaption, AValue: string; AFraction: Double; AWarnColor: Boolean);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Display(const ASnapshot: TAtlasServerSnapshot; ARunning: Boolean);
    procedure SetColors(const AColors: TAtlasColors);
  end;

  /// <summary>Tabellen: langsamste Units (ms), Regeln (ms, Aufrufe), Anfragen (Anzahl, Mittel, Maximum, Fehler).
  /// Doppelklick auf eine Unit meldet OnOpenUnit, auf eine Regel OnOpenRule.</summary>
  TAtlasServerTables = class(TPanel)
  private
    FUnits: TListView;
    FRules: TListView;
    FRequests: TListView;
    FSnapshot: TAtlasServerSnapshot;
    FOnOpenUnit: TProc<TAtlasServerSlowUnit>;
    FOnOpenRule: TProc<string>;
    function Px(AValue: Integer): Integer;
    /// <summary>Tabelle mit den Spalten AColumns; AWidths in logischen Pixeln (96 dpi), skaliert über die Liste.
    /// </summary>
    function NewList(const AColumns: array of string; const AWidths: array of Integer): TListView;
    procedure UnitsData(Sender: TObject; Item: TListItem);
    procedure RulesData(Sender: TObject; Item: TListItem);
    procedure RequestsData(Sender: TObject; Item: TListItem);
    procedure UnitsDblClick(Sender: TObject);
    procedure RulesDblClick(Sender: TObject);
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Stand zeigen; AWithWindow False: Die Anzahl der virtuellen Listen braucht ein Fenster, sie setzt
    /// der nächste Aufruf mit Fenster.</summary>
    procedure Display(const ASnapshot: TAtlasServerSnapshot; AWithWindow: Boolean);
    /// <summary>Wie ein Doppelklick auf Zeile AIndex der Units bzw. Regeln (für Tests und Tastatur).</summary>
    procedure OpenUnit(AIndex: Integer);
    procedure OpenRule(AIndex: Integer);
    property Units: TListView read FUnits;
    property Rules: TListView read FRules;
    property Requests: TListView read FRequests;
    property OnOpenUnit: TProc<TAtlasServerSlowUnit> read FOnOpenUnit write FOnOpenUnit;
    property OnOpenRule: TProc<string> read FOnOpenRule write FOnOpenRule;
  end;

  /// <summary>Reiter „KI-Assistenten“ (#2611): oben je Sitzung eine Zeile, darunter die Tabelle aller Sitzungen,
  /// unten der letzte fehlgeschlagene Aufruf der gewählten Zeile ganz. Auffällige Zeilen in Fehlerfarbe.</summary>
  TAtlasServerAssistants = class(TPanel)
  private
    FSummary: TLabel;
    FList: TListView;
    FDetail: TLabel;
    FSessions: TArray<TMcpAssistantSession>;
    FRows: TArray<TMcpAssistantRow>;
    FColors: TAtlasColors;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure UpdateDetail;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Sitzungen zeigen; AWithWindow False: Die Anzahl der virtuellen Liste setzt der nächste Aufruf mit
    /// Fenster.</summary>
    procedure Display(const ASessions: TArray<TMcpAssistantSession>; AWithWindow: Boolean);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Zellen der Zeile AIndex (für Tests); nil bei ungültigem Index.</summary>
    function Cells(AIndex: Integer): TArray<string>;
    /// <summary>Zeile AIndex ist auffällig (Fehlerfarbe).</summary>
    function Conspicuous(AIndex: Integer): Boolean;
    property Summary: TLabel read FSummary;
    property List: TListView read FList;
    property Detail: TLabel read FDetail;
  end;

  /// <summary>[Aktualisieren] [Index neu aufbauen] [Diagnosepaket erstellen …]  Hinweis</summary>
  TAtlasServerButtons = class(TFlowPanel)
  private
    FRefresh: TButton;
    FRebuild: TButton;
    FPackage: TButton;
    FNote: TLabel;
    FOnRefresh: TProc;
    FOnRebuild: TProc;
    FOnPackage: TProc;
    /// <summary>Knopf mit der Breite AWidth in logischen Pixeln (96 dpi).</summary>
    function NewButton(const ACaption: string; AWidth: Integer): TButton;
    procedure ButtonClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    property RefreshButton: TButton read FRefresh;
    property RebuildButton: TButton read FRebuild;
    property PackageButton: TButton read FPackage;
    property Note: TLabel read FNote;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    property OnRebuild: TProc read FOnRebuild write FOnRebuild;
    property OnPackage: TProc read FOnPackage write FOnPackage;
  end;

  TAtlasServerFrame = class(TFrame)
  private
    FPages: TPageControl;
    FServerTab: TTabSheet;
    FAssistantsTab: TTabSheet;
    FAssistants: TAtlasServerAssistants;
    FAssistantSessions: TArray<TMcpAssistantSession>;
    FHeader: TLabel;
    FQueue: TLabel;
    FCheckRun: TLabel;
    FMemory: TAtlasServerMemoryChart;
    FOverBudget: TLabel;
    FTables: TAtlasServerTables;
    FButtons: TAtlasServerButtons;
    FColors: TAtlasColors;
    FSnapshot: TAtlasServerSnapshot;
    FRunning: Boolean;
    FRestarts: Integer;
    /// <summary>Zeile oben unter APrevious (nil = ganz oben).</summary>
    function NewLine(APrevious: TControl): TLabel;
    /// <summary>ALabel als Zeile unter APrevious setzen.</summary>
    function PlaceLine(ALabel: TLabel; APrevious: TControl): TLabel;
    procedure UpdateTexts;
    procedure UpdateServerTexts;
    /// <summary>Reiter in FPages, zunächst verborgen (ohne Fenster scheitert ein sichtbarer Reiter).</summary>
    function NewTab(const ACaption: string): TTabSheet;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Sitzungen der laufenden KI-Assistenten für den Reiter „KI-Assistenten“ zeigen.</summary>
    procedure SetAssistants(const ASessions: TArray<TMcpAssistantSession>);
    /// <summary>Stand zeigen. ARunning False: Server läuft nicht (Snapshot leer); ARestarts aus der IDE-Schicht.
    /// </summary>
    procedure SetSnapshot(const ASnapshot: TAtlasServerSnapshot; ARunning: Boolean; ARestarts: Integer);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Hinweis neben den Knöpfen, z. B. „Stand 14:30:05“.</summary>
    procedure ShowNote(const AText: string);
    property Snapshot: TAtlasServerSnapshot read FSnapshot;
    property Header: TLabel read FHeader;
    property QueueLine: TLabel read FQueue;
    property CheckRunLine: TLabel read FCheckRun;
    property OverBudget: TLabel read FOverBudget;
    property Tables: TAtlasServerTables read FTables;
    property Buttons: TAtlasServerButtons read FButtons;
    property Pages: TPageControl read FPages;
    property AssistantsTab: TTabSheet read FAssistantsTab;
    property Assistants: TAtlasServerAssistants read FAssistants;
  end;

implementation

uses
  Atlas.Plugin.Style.Color,
  Winapi.Windows,
  System.Math,
  Atlas.Text.LogMarks,
  Atlas.UI.Status.Strings,
  Atlas.Vcl.Controls.WrapLabel,
  Atlas.Vcl.Theme.Scaling,
  Atlas.Vcl.Theme.Service;

const
  // Breiten der Spalten Regel, ms und Aufrufe; Breite der Knöpfe der Leiste.
  cRuleWidth = 260;
  cNumberWidth = 80;
  cRefreshWidth = 110;
  cRebuildWidth = 140;
  cPackageWidth = 170;
  /// <summary>Abstand oben des Hinweises in der Leiste bei 96 dpi, mittig zu den Knöpfen.</summary>
  cNoteTop = 7;
  /// <summary>Spalten der Anfragen: Anfrage, Anzahl, Mittel, Maximum, gescheitert; Spalte Unit.</summary>
  cRequestColumnWidths: array[0..4] of Integer = (260, 70, 80, 90, 60);
  cUnitWidth = 260;
  /// <summary>Speicheranzeige bei 96 dpi: Breiten von Name und Wert, Zeilenhöhe, Abstände des Balkens.</summary>
  cChartLabelWidth = 130;
  cChartValueWidth = 150;
  cChartRowHeight = 18;
  cChartBarInset = 4;
  cChartBarGap = 8;
  /// <summary>Tabellen untereinander: Anzahl, kleinste Höhe und Abzug je Tabelle bei 96 dpi.</summary>
  cTableCount = 3;
  cTableMinHeight = 60;
  cTableGap = 6;
  /// <summary>Reiter „KI-Assistenten“ bei 96 dpi: Breite der Spalten KI-Assistent und Name, der Zahlen und des
  /// letzten fehlgeschlagenen Aufrufs.</summary>
  cAssistantWidth = 180;
  cAssistantNumberWidth = 80;
  cAssistantFailedWidth = 300;
  /// <summary>Spalten vor den Zellen aus TMcpCallSummary.Cells: KI-Assistent.</summary>
  cAssistantColumns = 1;

{$R *.dfm}

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>Name eines Speicherbereichs in der Sprache der IDE.</summary>
function PartCaption(APart: TAtlasServerMemoryPart): string;
begin
  case APart of
    TAtlasServerMemoryPart.Symbols:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemorySymbols);
    TAtlasServerMemoryPart.Usages:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryUsages);
    TAtlasServerMemoryPart.LibraryUnits:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryLibrary);
    TAtlasServerMemoryPart.TreeCache:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryTrees);
    TAtlasServerMemoryPart.Documents:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryDocuments);
    TAtlasServerMemoryPart.Packages:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryPackages);
  else
    Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryRest);
  end;
end;

/// <summary>Zustand in der Sprache der IDE.</summary>
function StateCaption(AState: TAtlasServerState): string;
begin
  case AState of
    TAtlasServerState.Loading:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerStateLoading);
    TAtlasServerState.Ready:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerStateReady);
    TAtlasServerState.Checking:
      Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerStateChecking);
  else
    Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerStateUnknown);
  end;
end;

function PercentText(APercent: Integer): string;
begin
  if APercent < 0 then
  begin
    Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowUnknownValue);
  end
  else
  begin
    Result := IntToStr(APercent) + ' %';
  end;
end;

{ TAtlasServerMemoryChart }

constructor TAtlasServerMemoryChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FSnapshot := Default(TAtlasServerSnapshot);
  Height := (Ord(High(TAtlasServerMemoryPart)) + 2) * RowHeight;
end;

procedure TAtlasServerMemoryChart.Paint;
var
  mPart: TAtlasServerMemoryPart;
  mIndex: Integer;
begin
  // Geerbt zuerst: TPaintBox.Paint löst OnPaint aus; das eigene Bild deckt den Rest.
  inherited;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if not FRunning or not FSnapshot.Valid then
  begin
    Exit;
  end;
  FLabelWidth := Px(cChartLabelWidth);
  FValueWidth := Px(cChartValueWidth);
  mIndex := 0;
  for mPart := Low(TAtlasServerMemoryPart) to High(TAtlasServerMemoryPart) do
  begin
    // Über dem Budget fallen die Verwendungen auf: Sie werden ausgelagert.
    DrawRow(mIndex, PartCaption(mPart), TAtlasServerTexts.Megabytes(FSnapshot.Memory[mPart], FormatSettings),
      FSnapshot.Fraction(mPart), FSnapshot.OverBudget and (mPart = TAtlasServerMemoryPart.Usages));
    Inc(mIndex);
  end;
  Canvas.Font.Style := [fsBold];
  DrawRow(mIndex, TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerMemoryTotal), TotalText, FSnapshot.TotalFraction,
    FSnapshot.OverBudget);
  Canvas.Font.Style := [];
end;

function TAtlasServerMemoryChart.Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasServerMemoryChart.RowHeight: Integer;
begin
  Result := Px(cChartRowHeight);
end;

function TAtlasServerMemoryChart.TotalText: string;
begin
  Result := TAtlasServerTexts.Megabytes(FSnapshot.MemoryTotal, FormatSettings) + ' / ';
  if FSnapshot.MemoryBudget > 0 then
  begin
    Result := Result + TAtlasStatusStrings.Fmt(TAtlasStatusTextId.ServerWindowBudget,
      [TAtlasServerTexts.Megabytes(FSnapshot.MemoryBudget, FormatSettings)]);
  end
  else
  begin
    Result := Result + TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowNoBudget);
  end;
end;

procedure TAtlasServerMemoryChart.DrawBar(const ABar: TRect; AFraction: Double; AWarnColor: Boolean);
var
  mFill: TRect;
  mBudgetX: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ABar);
  mFill := ABar;
  mFill.Right := ABar.Left + Round(ABar.Width * AFraction);
  if mFill.Right > mFill.Left then
  begin
    Canvas.Brush.Color := ToColor(FColors.Accent);
    if AWarnColor then
    begin
      Canvas.Brush.Color := ToColor(FColors.Warn);
    end;
    Canvas.FillRect(mFill);
  end;
  // Budget als senkrechter Strich, wenn es kleiner als der Maßstab ist.
  if (FSnapshot.MemoryBudget > 0) and (FSnapshot.Scale > 0) then
  begin
    mBudgetX := ABar.Left + Round(ABar.Width * Min(FSnapshot.MemoryBudget / FSnapshot.Scale, 1));
    Canvas.Pen.Color := ToColor(FColors.Error);
    Canvas.MoveTo(mBudgetX, ABar.Top - Px(2));
    Canvas.LineTo(mBudgetX, ABar.Bottom + Px(2));
  end;
end;

procedure TAtlasServerMemoryChart.DrawRow(AIndex: Integer; const ACaption, AValue: string; AFraction: Double;
  AWarnColor: Boolean);
const
  cTextFlags = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS;
var
  mRow, mCell, mBar: TRect;
begin
  mRow := Rect(0, AIndex * RowHeight, ClientWidth, (AIndex + 1) * RowHeight);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(FColors.Text);
  mCell := Rect(mRow.Left, mRow.Top, mRow.Left + FLabelWidth, mRow.Bottom);
  DrawText(Canvas.Handle, PChar(ACaption), Length(ACaption), mCell, cTextFlags or DT_LEFT);
  mCell := Rect(mRow.Right - FValueWidth, mRow.Top, mRow.Right, mRow.Bottom);
  DrawText(Canvas.Handle, PChar(AValue), Length(AValue), mCell, cTextFlags or DT_RIGHT);
  mBar := Rect(mRow.Left + FLabelWidth, mRow.Top + Px(cChartBarInset), mRow.Right - FValueWidth - Px(cChartBarGap),
    mRow.Bottom - Px(cChartBarInset));
  if mBar.Right > mBar.Left then
  begin
    DrawBar(mBar, AFraction, AWarnColor);
  end;
end;

procedure TAtlasServerMemoryChart.Display(const ASnapshot: TAtlasServerSnapshot; ARunning: Boolean);
begin
  FSnapshot := ASnapshot;
  FRunning := ARunning;
  Invalidate;
end;

procedure TAtlasServerMemoryChart.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

{ TAtlasServerTables }

constructor TAtlasServerTables.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  FSnapshot := Default(TAtlasServerSnapshot);
  FRequests := NewList([TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnRequest),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnCount),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnAverage),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnMax),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnFailed)],
    cRequestColumnWidths);
  FRequests.Align := alClient;
  FRequests.OnData := RequestsData;
  FRules := NewList([TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnRule),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnMs),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnCalls)],
    [cRuleWidth, cNumberWidth, cNumberWidth]);
  FRules.Align := alTop;
  FRules.OnData := RulesData;
  FRules.OnDblClick := RulesDblClick;
  FUnits := NewList([TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnUnit),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerColumnMs)],
    [cUnitWidth, cNumberWidth]);
  FUnits.Align := alTop;
  FUnits.Top := 0;
  FUnits.OnData := UnitsData;
  FUnits.OnDblClick := UnitsDblClick;
end;

procedure TAtlasServerTables.Resize;
begin
  inherited;
  // Drei gleich hohe Tabellen untereinander; die Anfragen nehmen den Rest.
  FUnits.Height := Max(Px(cTableMinHeight), ClientHeight div cTableCount - Px(cTableGap));
  FRules.Height := FUnits.Height;
end;

function TAtlasServerTables.Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasServerTables.NewList(const AColumns: array of string; const AWidths: array of Integer): TListView;
var
  mIndex: Integer;
  mColumn: TListColumn;
begin
  Result := TListView.Create(Self);
  Result.Parent := Self;
  Result.AlignWithMargins := True;
  Result.ViewStyle := vsReport;
  Result.OwnerData := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ReadOnly := True;
  for mIndex := 0 to High(AColumns) do
  begin
    mColumn := Result.Columns.Add;
    mColumn.Caption := AColumns[mIndex];
    mColumn.Width := Result.ScaleValue(AWidths[mIndex]);
    if mIndex > 0 then
    begin
      mColumn.Alignment := taRightJustify;
    end;
  end;
end;

procedure TAtlasServerTables.UnitsData(Sender: TObject; Item: TListItem);
var
  mUnit: TAtlasServerSlowUnit;
begin
  if (Item.Index < 0) or (Item.Index > High(FSnapshot.SlowUnits)) then
  begin
    Exit;
  end;
  mUnit := FSnapshot.SlowUnits[Item.Index];
  Item.Caption := mUnit.Name;
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mUnit.Ms, FormatSettings));
end;

procedure TAtlasServerTables.RulesData(Sender: TObject; Item: TListItem);
var
  mRule: TAtlasServerSlowRule;
begin
  if (Item.Index < 0) or (Item.Index > High(FSnapshot.SlowRules)) then
  begin
    Exit;
  end;
  mRule := FSnapshot.SlowRules[Item.Index];
  Item.Caption := mRule.Id;
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mRule.Ms, FormatSettings));
  Item.SubItems.Add(IntToStr(mRule.Calls));
end;

procedure TAtlasServerTables.RequestsData(Sender: TObject; Item: TListItem);
var
  mRequest: TAtlasServerRequest;
begin
  if (Item.Index < 0) or (Item.Index > High(FSnapshot.Requests)) then
  begin
    Exit;
  end;
  mRequest := FSnapshot.Requests[Item.Index];
  Item.Caption := mRequest.Method;
  Item.SubItems.Add(IntToStr(mRequest.Count));
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mRequest.AverageMs, FormatSettings));
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mRequest.MaxMs, FormatSettings));
  Item.SubItems.Add(IntToStr(mRequest.Failed));
end;

procedure TAtlasServerTables.UnitsDblClick(Sender: TObject);
begin
  if FUnits.Selected <> nil then
  begin
    OpenUnit(FUnits.Selected.Index);
  end;
end;

procedure TAtlasServerTables.RulesDblClick(Sender: TObject);
begin
  if FRules.Selected <> nil then
  begin
    OpenRule(FRules.Selected.Index);
  end;
end;

procedure TAtlasServerTables.Display(const ASnapshot: TAtlasServerSnapshot; AWithWindow: Boolean);
begin
  FSnapshot := ASnapshot;
  if AWithWindow then
  begin
    FUnits.Items.Count := Length(FSnapshot.SlowUnits);
    FRules.Items.Count := Length(FSnapshot.SlowRules);
    FRequests.Items.Count := Length(FSnapshot.Requests);
  end;
  FUnits.Invalidate;
  FRules.Invalidate;
  FRequests.Invalidate;
end;

procedure TAtlasServerTables.OpenUnit(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSnapshot.SlowUnits)) or not Assigned(FOnOpenUnit) then
  begin
    Exit;
  end;
  FOnOpenUnit(FSnapshot.SlowUnits[AIndex]);
end;

procedure TAtlasServerTables.OpenRule(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSnapshot.SlowRules)) or not Assigned(FOnOpenRule) then
  begin
    Exit;
  end;
  FOnOpenRule(FSnapshot.SlowRules[AIndex].Id);
end;

{ TAtlasServerAssistants }

/// <summary>Trennzeichen für Nachkommastellen in der Sprache der IDE.</summary>
function AssistantDecimal: Char;
begin
  Result := TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsDecimal)[1];
end;

/// <summary>Client der Sitzung AIndex mit pid, z. B. „Assistent A (4711)“.</summary>
function AssistantCell(const ASessions: TArray<TMcpAssistantSession>; AIndex: Integer): string;
var
  mSession: TMcpAssistantSession;
begin
  mSession := Default(TMcpAssistantSession);
  if (AIndex >= 0) and (AIndex <= High(ASessions)) then
  begin
    mSession := ASessions[AIndex];
  end;
  Result := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsCell, [
    mSession.ClientOr(TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsUnknown)), mSession.Pid]);
end;

/// <summary>Zeile einer Sitzung über der Tabelle.</summary>
function SessionLine(const ASession: TMcpAssistantSession): string;
begin
  if not ASession.HasStatistics then
  begin
    Exit(TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsNotCounting, [ASession.Pid]));
  end;
  Result := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsSession, [
    ASession.ClientOr(TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsUnknown)), ASession.Pid,
    FormatDateTime('hh":"nn', ASession.Statistics.Started), ASession.Statistics.TotalCalls,
    ASession.Statistics.TotalErrors]);
  if ASession.Statistics.Project <> '' then
  begin
    Result := Result + TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsProject, [
      TLogMarks.Plain(ASession.Statistics.Project)]);
  end;
end;

/// <summary>Zeilen über der Tabelle: je Sitzung eine, dazu die Zahl auffälliger Einträge; ohne Sitzung ein
/// Hinweis.</summary>
function SummaryText(const ASessions: TArray<TMcpAssistantSession>; const ARows: TArray<TMcpAssistantRow>): string;
var
  mSession: TMcpAssistantSession;
  mLines: TArray<string>;
  mConspicuous: Integer;
begin
  if ASessions = nil then
  begin
    Exit(TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsNone));
  end;
  mLines := nil;
  for mSession in ASessions do
  begin
    mLines := mLines + [SessionLine(mSession)];
  end;
  mConspicuous := TMcpAssistantSessions.ConspicuousCount(ARows);
  if mConspicuous > 0 then
  begin
    mLines := mLines + [TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsConspicuous, [
      TMcpCallSummary.cConspicuousPercent, mConspicuous])];
  end;
  Result := string.Join(sLineBreak, mLines);
end;

constructor TAtlasServerAssistants.Create(AOwner: TComponent);
var
  mColumn: TListColumn;
  mIndex: Integer;
  mTitles: TArray<string>;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
  FColors := TAtlasColors.Light;
  FSummary := TAtlasWrapLabel.Create(Self);
  FSummary.Parent := Self;
  FSummary.Align := alTop;
  FSummary.AlignWithMargins := True;
  FSummary.ShowAccelChar := False;
  FDetail := TAtlasWrapLabel.Create(Self);
  FDetail.Parent := Self;
  FDetail.Align := alBottom;
  FDetail.AlignWithMargins := True;
  FDetail.ShowAccelChar := False;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.OnData := ListData;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnSelectItem := ListSelectItem;
  mTitles := TArray<string>.Create(TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnAssistant),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnName),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnCalls),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnErrors),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnMedian),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnLongest),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnResponse),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnLargest),
    TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsColumnLastFailed));
  for mIndex := 0 to High(mTitles) do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := mTitles[mIndex];
    mColumn.Width := FList.ScaleValue(cAssistantNumberWidth);
    // Zahlen rechtsbündig: Aufrufe bis Größte.
    if (mIndex > Ord(TMcpCallColumn.Name) + cAssistantColumns) and
      (mIndex <= Ord(TMcpCallColumn.MaxBytes) + cAssistantColumns) then
    begin
      mColumn.Alignment := taRightJustify;
    end;
  end;
  FList.Columns[0].Width := FList.ScaleValue(cAssistantWidth);
  FList.Columns[Ord(TMcpCallColumn.Name) + cAssistantColumns].Width := FList.ScaleValue(cAssistantWidth);
  FList.Columns[High(mTitles)].Width := FList.ScaleValue(cAssistantFailedWidth);
  FSummary.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsNone);
  FDetail.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsSelect);
end;

destructor TAtlasServerAssistants.Destroy;
begin
  FSessions := nil;
  FRows := nil;
  inherited;
end;

function TAtlasServerAssistants.Cells(AIndex: Integer): TArray<string>;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FRows)) then
  begin
    Exit;
  end;
  Result := TArray<string>.Create(AssistantCell(FSessions, FRows[AIndex].Session)) +
    FRows[AIndex].Call.Cells(AssistantDecimal, TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsNoValue));
end;

function TAtlasServerAssistants.Conspicuous(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FRows)) and FRows[AIndex].Call.Conspicuous;
end;

procedure TAtlasServerAssistants.ListData(Sender: TObject; Item: TListItem);
var
  mCells: TArray<string>;
  mIndex: Integer;
begin
  mCells := Cells(Item.Index);
  if mCells = nil then
  begin
    Exit;
  end;
  Item.Caption := mCells[0];
  for mIndex := 1 to High(mCells) do
  begin
    Item.SubItems.Add(mCells[mIndex]);
  end;
end;

procedure TAtlasServerAssistants.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if Conspicuous(Item.Index) then
  begin
    Sender.Canvas.Font.Color := ToColor(FColors.Error);
  end;
end;

procedure TAtlasServerAssistants.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateDetail;
end;

procedure TAtlasServerAssistants.UpdateDetail;
var
  mIndex: Integer;
  mCall: TMcpCallSummary;
begin
  mIndex := -1;
  if FList.HandleAllocated and (FList.Selected <> nil) then
  begin
    mIndex := FList.Selected.Index;
  end;
  if (mIndex < 0) or (mIndex > High(FRows)) then
  begin
    FDetail.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.AssistantsSelect);
    Exit;
  end;
  mCall := FRows[mIndex].Call;
  if mCall.LastFailed.At = 0 then
  begin
    FDetail.Caption := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsNoFailure, [mCall.Name]);
  end
  else
  begin
    FDetail.Caption := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.AssistantsLastFailed, [mCall.Name,
      mCall.LastFailedText]);
  end;
end;

procedure TAtlasServerAssistants.Display(const ASessions: TArray<TMcpAssistantSession>; AWithWindow: Boolean);
begin
  FSessions := Copy(ASessions);
  FRows := TMcpAssistantSessions.Rows(FSessions);
  FSummary.Caption := SummaryText(FSessions, FRows);
  if AWithWindow then
  begin
    FList.Items.Count := Length(FRows);
  end;
  FList.Invalidate;
  UpdateDetail;
end;

procedure TAtlasServerAssistants.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FList.Invalidate;
end;

{ TAtlasServerButtons }

constructor TAtlasServerButtons.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
  // Fließende Leiste: bei schmalem Fenster brechen Knöpfe und Hinweis in weitere Zeilen um.
  AutoWrap := True;
  AutoSize := True;
  TAtlasControlScaling.SetPadding(Self, 2, 2, 2, 2);
  FRefresh := NewButton(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowRefresh), cRefreshWidth);
  FRebuild := NewButton(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowRebuild), cRebuildWidth);
  FPackage := NewButton(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowPackage), cPackageWidth);
  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.AlignWithMargins := True;
  FNote.AutoSize := True;
  FNote.Margins.Top := FNote.ScaleValue(cNoteTop);
  FNote.ShowAccelChar := False;
  TAtlasUiTheme.UseFontColor(FNote, clGrayText);
  FNote.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowHint);
end;

function TAtlasServerButtons.NewButton(const ACaption: string; AWidth: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.AlignWithMargins := True;
  Result.Width := Result.ScaleValue(AWidth);
  Result.Caption := ACaption;
  Result.OnClick := ButtonClick;
end;

procedure TAtlasServerButtons.ButtonClick(Sender: TObject);
var
  mAction: TProc;
begin
  mAction := nil;
  if Sender = FRefresh then
  begin
    mAction := FOnRefresh;
  end
  else if Sender = FRebuild then
  begin
    mAction := FOnRebuild;
  end
  else if Sender = FPackage then
  begin
    mAction := FOnPackage;
  end;
  if Assigned(mAction) then
  begin
    mAction();
  end;
end;

{ TAtlasServerFrame }

constructor TAtlasServerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FColors := TAtlasColors.Light;
  FSnapshot := Default(TAtlasServerSnapshot);
  FButtons := TAtlasServerButtons.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FServerTab := NewTab(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerTabServer));
  FAssistantsTab := NewTab(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerTabAssistants));
  FAssistants := TAtlasServerAssistants.Create(Self);
  FAssistants.Parent := FAssistantsTab;
  FAssistants.Align := alClient;
  FHeader := NewLine(nil);
  FHeader.EllipsisPosition := epEndEllipsis;
  FHeader.Font.Style := [fsBold];
  FQueue := PlaceLine(TAtlasWrapLabel.Create(Self), FHeader);
  FCheckRun := NewLine(FQueue);
  FMemory := TAtlasServerMemoryChart.Create(Self);
  FMemory.Parent := FServerTab;
  FMemory.Align := alTop;
  FMemory.AlignWithMargins := True;
  FMemory.Top := FCheckRun.Top + FCheckRun.Height + 1;
  FOverBudget := NewLine(FMemory);
  FOverBudget.Font.Style := [fsBold];
  FOverBudget.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowOverBudget);
  FOverBudget.Visible := False;
  FTables := TAtlasServerTables.Create(Self);
  FTables.Parent := FServerTab;
  FTables.Align := alClient;
  UpdateTexts;
end;

destructor TAtlasServerFrame.Destroy;
begin
  FAssistantSessions := nil;
  inherited;
end;

function TAtlasServerFrame.NewTab(const ACaption: string): TTabSheet;
begin
  Result := TTabSheet.Create(Self);
  Result.Caption := ACaption;
  // Ohne Fenster scheitert ein sichtbarer Reiter; CreateWnd zeigt ihn.
  Result.TabVisible := False;
  Result.PageControl := FPages;
end;

procedure TAtlasServerFrame.CreateWnd;
begin
  inherited;
  if (FServerTab <> nil) and not FServerTab.TabVisible then
  begin
    FServerTab.TabVisible := True;
    FAssistantsTab.TabVisible := True;
    FPages.ActivePage := FServerTab;
  end;
  UpdateTexts;
end;

procedure TAtlasServerFrame.SetAssistants(const ASessions: TArray<TMcpAssistantSession>);
begin
  FAssistantSessions := Copy(ASessions);
  // Die Anzahl der virtuellen Liste braucht ein Fenster; ohne Eltern setzt UpdateTexts (CreateWnd) sie nach.
  FAssistants.Display(FAssistantSessions, HandleAllocated or (Parent <> nil));
end;

function TAtlasServerFrame.NewLine(APrevious: TControl): TLabel;
begin
  Result := PlaceLine(TLabel.Create(Self), APrevious);
end;

function TAtlasServerFrame.PlaceLine(ALabel: TLabel; APrevious: TControl): TLabel;
begin
  Result := ALabel;
  Result.Parent := FServerTab;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  // alTop ordnet nach Top: unter die vorige Zeile.
  if APrevious <> nil then
  begin
    Result.Top := APrevious.Top + APrevious.Height + 1;
  end;
end;

procedure TAtlasServerFrame.UpdateTexts;
begin
  FQueue.Caption := '';
  FCheckRun.Caption := '';
  if not FRunning then
  begin
    FHeader.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowNoServer);
  end
  else if not FSnapshot.Valid then
  begin
    FHeader.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowWaiting);
  end
  else if not FSnapshot.Known then
  begin
    FHeader.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowOldServer);
  end
  else
  begin
    UpdateServerTexts;
  end;
  FOverBudget.Visible := FRunning and FSnapshot.OverBudget;
  FOverBudget.Font.Color := ToColor(FColors.Warn);
  // Die Anzahl der virtuellen Listen braucht ein Fenster; ohne Eltern setzt CreateWnd sie nach.
  FTables.Display(FSnapshot, HandleAllocated or (Parent <> nil));
  FAssistants.Display(FAssistantSessions, HandleAllocated or (Parent <> nil));
  FMemory.Display(FSnapshot, FRunning);
end;

procedure TAtlasServerFrame.UpdateServerTexts;
begin
  FHeader.Caption := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.ServerWindowHeader, [FSnapshot.ProcessId,
    FSnapshot.Version,
    TAtlasServerTexts.Duration(FSnapshot.UptimeMs), StateCaption(FSnapshot.State), FRestarts]);
  FQueue.Caption := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.ServerWindowQueue, [FSnapshot.IndexWaiting,
    FSnapshot.IndexRunning, FSnapshot.CheckWaiting, FSnapshot.CheckRunning,
    TAtlasServerTexts.Duration(FSnapshot.OldestWaitMs)]) + sLineBreak +
    TAtlasStatusStrings.Fmt(TAtlasStatusTextId.ServerWindowCacheHits, [PercentText(FSnapshot.IndexHitPercent),
    PercentText(FSnapshot.TreeHitPercent), Max(FSnapshot.Units, 0)]);
  if FSnapshot.CheckActive then
  begin
    FCheckRun.Caption := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.ServerWindowCheckRunning, [FSnapshot.CheckUnits]);
  end
  else if FSnapshot.CheckSerial = 0 then
  begin
    FCheckRun.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowNoCheckRun);
  end
  else
  begin
    FCheckRun.Caption := TAtlasStatusStrings.Fmt(TAtlasStatusTextId.ServerWindowCheckRun,
      [FormatDateTime('hh":"nn', FSnapshot.CheckStarted), FSnapshot.CheckUnits,
      TAtlasServerTexts.Duration(FSnapshot.CheckDurationMs)]);
  end;
end;

procedure TAtlasServerFrame.SetSnapshot(const ASnapshot: TAtlasServerSnapshot; ARunning: Boolean; ARestarts: Integer);
begin
  FRunning := ARunning;
  if ARunning then
  begin
    FSnapshot := ASnapshot;
  end
  else
  begin
    FSnapshot := Default(TAtlasServerSnapshot);
  end;
  FRestarts := ARestarts;
  FButtons.RebuildButton.Enabled := ARunning;
  UpdateTexts;
end;

procedure TAtlasServerFrame.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FOverBudget.Font.Color := ToColor(FColors.Warn);
  FMemory.SetColors(AColors);
  FAssistants.SetColors(AColors);
end;

procedure TAtlasServerFrame.ShowNote(const AText: string);
begin
  FButtons.Note.Caption := AText;
end;

end.
