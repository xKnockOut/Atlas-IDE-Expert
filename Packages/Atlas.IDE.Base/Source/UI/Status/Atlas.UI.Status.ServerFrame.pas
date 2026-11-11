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
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Server;

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

  /// <summary>[Aktualisieren] [Index neu aufbauen] [Diagnosepaket erstellen …]  Hinweis</summary>
  TAtlasServerButtons = class(TPanel)
  private
    FRefresh: TButton;
    FRebuild: TButton;
    FPackage: TButton;
    FNote: TLabel;
    FOnRefresh: TProc;
    FOnRebuild: TProc;
    FOnPackage: TProc;
    function NewButton(const ACaption: string; ALeft, AWidth: Integer): TButton;
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
    procedure UpdateTexts;
    procedure UpdateServerTexts;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
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
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.UI.Status.Strings;

const
  // Breiten der Spalten Regel, ms und Aufrufe; Lage und Breite der Knöpfe der Leiste.
  cRuleWidth = 260;
  cNumberWidth = 80;
  cRefreshLeft = 4;
  cRefreshWidth = 110;
  cRebuildLeft = 120;
  cRebuildWidth = 140;
  cPackageLeft = 266;
  cPackageWidth = 170;

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

function TAtlasServerMemoryChart.Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasServerMemoryChart.RowHeight: Integer;
begin
  Result := Px(18);
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
  mBar := Rect(mRow.Left + FLabelWidth, mRow.Top + Px(4), mRow.Right - FValueWidth - Px(8), mRow.Bottom - Px(4));
  if mBar.Right > mBar.Left then
  begin
    DrawBar(mBar, AFraction, AWarnColor);
  end;
end;

procedure TAtlasServerMemoryChart.Paint;
var
  mPart: TAtlasServerMemoryPart;
  mIndex: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if not FRunning or not FSnapshot.Valid then
  begin
    Exit;
  end;
  FLabelWidth := Px(130);
  FValueWidth := Px(150);
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
    [260, 70, 80, 90, 60]);
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
    [260, 80]);
  FUnits.Align := alTop;
  FUnits.Top := 0;
  FUnits.OnData := UnitsData;
  FUnits.OnDblClick := UnitsDblClick;
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
    mColumn.Width := AWidths[mIndex];
    if mIndex > 0 then
    begin
      mColumn.Alignment := taRightJustify;
    end;
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

procedure TAtlasServerTables.Resize;
begin
  inherited;
  // Drei gleich hohe Tabellen untereinander; die Anfragen nehmen den Rest.
  FUnits.Height := Max(Px(60), ClientHeight div 3 - Px(6));
  FRules.Height := FUnits.Height;
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

{ TAtlasServerButtons }

constructor TAtlasServerButtons.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  Height := ScaleValue(36);
  FRefresh := NewButton(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowRefresh), cRefreshLeft, cRefreshWidth);
  FRebuild := NewButton(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowRebuild), cRebuildLeft, cRebuildWidth);
  FPackage := NewButton(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowPackage), cPackageLeft, cPackageWidth);
  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Left := FNote.ScaleValue(444);
  FNote.Top := FNote.ScaleValue(11);
  FNote.ShowAccelChar := False;
  FNote.Font.Color := clGrayText;
  FNote.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowHint);
end;

function TAtlasServerButtons.NewButton(const ACaption: string; ALeft, AWidth: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Left := ALeft;
  Result.Top := Result.ScaleValue(6);
  Result.Width := AWidth;
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
  FHeader := NewLine(nil);
  FHeader.EllipsisPosition := epEndEllipsis;
  FHeader.Font.Style := [fsBold];
  FQueue := NewLine(FHeader);
  FQueue.WordWrap := True;
  FCheckRun := NewLine(FQueue);
  FMemory := TAtlasServerMemoryChart.Create(Self);
  FMemory.Parent := Self;
  FMemory.Align := alTop;
  FMemory.AlignWithMargins := True;
  FMemory.Top := FCheckRun.Top + FCheckRun.Height + 1;
  FOverBudget := NewLine(FMemory);
  FOverBudget.Font.Style := [fsBold];
  FOverBudget.Caption := TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowOverBudget);
  FOverBudget.Visible := False;
  FButtons := TAtlasServerButtons.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FTables := TAtlasServerTables.Create(Self);
  FTables.Parent := Self;
  FTables.Align := alClient;
  UpdateTexts;
end;

function TAtlasServerFrame.NewLine(APrevious: TControl): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  // alTop ordnet nach Top: unter die vorige Zeile.
  if APrevious <> nil then
  begin
    Result.Top := APrevious.Top + APrevious.Height + 1;
  end;
end;

procedure TAtlasServerFrame.CreateWnd;
begin
  inherited;
  UpdateTexts;
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
  FMemory.Display(FSnapshot, FRunning);
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
end;

procedure TAtlasServerFrame.ShowNote(const AText: string);
begin
  FButtons.Note.Caption := AText;
end;

end.
