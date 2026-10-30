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
// hier, sondern in der IDE-Schicht. Die Listen sind virtuell (OwnerData),
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
  TAtlasServerFrame = class(TFrame)
  private
    FHeader: TLabel;
    FQueue: TLabel;
    FCheckRun: TLabel;
    FMemory: TPaintBox;
    FOverBudget: TLabel;
    FTables: TPanel;
    FUnits: TListView;
    FRules: TListView;
    FRequests: TListView;
    FBottom: TPanel;
    FRefresh: TButton;
    FRebuild: TButton;
    FPackage: TButton;
    FNote: TLabel;
    FColors: TAtlasColors;
    FSnapshot: TAtlasServerSnapshot;
    FRunning: Boolean;
    FRestarts: Integer;
    FOnRefresh: TProc;
    FOnRebuild: TProc;
    FOnPackage: TProc;
    FOnOpenUnit: TProc<TAtlasServerSlowUnit>;
    FOnOpenRule: TProc<string>;
    function Scale(AValue: Integer): Integer;
    function RowHeight: Integer;
    function NewList(const AColumns: array of string; const AWidths: array of Integer): TListView;
    function NewButton(const ACaption: string; ALeft, AWidth: Integer; AClick: TNotifyEvent): TButton;
    procedure MemoryPaint(Sender: TObject);
    procedure TablesResize(Sender: TObject);
    procedure UnitsData(Sender: TObject; Item: TListItem);
    procedure RulesData(Sender: TObject; Item: TListItem);
    procedure RequestsData(Sender: TObject; Item: TListItem);
    procedure UnitsDblClick(Sender: TObject);
    procedure RulesDblClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure RebuildClick(Sender: TObject);
    procedure PackageClick(Sender: TObject);
    procedure UpdateTexts;
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
    /// <summary>Wie ein Doppelklick auf Zeile AIndex der Units bzw. Regeln (für Tests und Tastatur).</summary>
    procedure OpenUnit(AIndex: Integer);
    procedure OpenRule(AIndex: Integer);
    /// <summary>Name eines Speicherbereichs in der Sprache der IDE.</summary>
    class function PartCaption(APart: TAtlasServerMemoryPart): string; static;
    /// <summary>Zustand in der Sprache der IDE.</summary>
    class function StateCaption(AState: TAtlasServerState): string; static;
    property Snapshot: TAtlasServerSnapshot read FSnapshot;
    property Header: TLabel read FHeader;
    property QueueLine: TLabel read FQueue;
    property CheckRunLine: TLabel read FCheckRun;
    property OverBudget: TLabel read FOverBudget;
    property Units: TListView read FUnits;
    property Rules: TListView read FRules;
    property Requests: TListView read FRequests;
    property RefreshButton: TButton read FRefresh;
    property RebuildButton: TButton read FRebuild;
    property PackageButton: TButton read FPackage;
    property Note: TLabel read FNote;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    property OnRebuild: TProc read FOnRebuild write FOnRebuild;
    property OnPackage: TProc read FOnPackage write FOnPackage;
    property OnOpenUnit: TProc<TAtlasServerSlowUnit> read FOnOpenUnit write FOnOpenUnit;
    property OnOpenRule: TProc<string> read FOnOpenRule write FOnOpenRule;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.UI.Strings;

{$R *.dfm}

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasServerFrame }

constructor TAtlasServerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FColors := TAtlasColors.Light;
  FSnapshot := Default(TAtlasServerSnapshot);
  FHeader := TLabel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.AlignWithMargins := True;
  FHeader.ShowAccelChar := False;
  FHeader.EllipsisPosition := epEndEllipsis;
  FHeader.Font.Style := [fsBold];
  FQueue := TLabel.Create(Self);
  FQueue.Parent := Self;
  FQueue.Align := alTop;
  FQueue.AlignWithMargins := True;
  FQueue.ShowAccelChar := False;
  FQueue.WordWrap := True;
  FQueue.Top := FHeader.Top + FHeader.Height + 1;
  FCheckRun := TLabel.Create(Self);
  FCheckRun.Parent := Self;
  FCheckRun.Align := alTop;
  FCheckRun.AlignWithMargins := True;
  FCheckRun.ShowAccelChar := False;
  FCheckRun.Top := FQueue.Top + FQueue.Height + 1;
  FMemory := TPaintBox.Create(Self);
  FMemory.Parent := Self;
  FMemory.Align := alTop;
  FMemory.AlignWithMargins := True;
  FMemory.Top := FCheckRun.Top + FCheckRun.Height + 1;
  FMemory.Height := (Ord(High(TAtlasServerMemoryPart)) + 2) * RowHeight;
  FMemory.OnPaint := MemoryPaint;
  FOverBudget := TLabel.Create(Self);
  FOverBudget.Parent := Self;
  FOverBudget.Align := alTop;
  FOverBudget.AlignWithMargins := True;
  FOverBudget.ShowAccelChar := False;
  FOverBudget.Font.Style := [fsBold];
  FOverBudget.Top := FMemory.Top + FMemory.Height + 1;
  FOverBudget.Caption := TAtlasStrings.Text(TAtlasTextId.ServerWindowOverBudget);
  FOverBudget.Visible := False;
  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.BevelOuter := bvNone;
  FBottom.ParentBackground := True;
  FBottom.Height := 36;
  FRefresh := NewButton(TAtlasStrings.Text(TAtlasTextId.ServerWindowRefresh), 4, 110, RefreshClick);
  FRebuild := NewButton(TAtlasStrings.Text(TAtlasTextId.ServerWindowRebuild), 120, 140, RebuildClick);
  FPackage := NewButton(TAtlasStrings.Text(TAtlasTextId.ServerWindowPackage), 266, 170, PackageClick);
  FNote := TLabel.Create(Self);
  FNote.Parent := FBottom;
  FNote.Left := 444;
  FNote.Top := 11;
  FNote.ShowAccelChar := False;
  FNote.Font.Color := clGrayText;
  FNote.Caption := TAtlasStrings.Text(TAtlasTextId.ServerWindowHint);
  FTables := TPanel.Create(Self);
  FTables.Parent := Self;
  FTables.Align := alClient;
  FTables.BevelOuter := bvNone;
  FTables.ParentBackground := True;
  FTables.OnResize := TablesResize;
  FRequests := NewList([TAtlasStrings.Text(TAtlasTextId.ServerColumnRequest),
    TAtlasStrings.Text(TAtlasTextId.ServerColumnCount), TAtlasStrings.Text(TAtlasTextId.ServerColumnAverage),
    TAtlasStrings.Text(TAtlasTextId.ServerColumnMax), TAtlasStrings.Text(TAtlasTextId.ServerColumnFailed)],
    [260, 70, 80, 90, 60]);
  FRequests.Align := alClient;
  FRequests.OnData := RequestsData;
  FRules := NewList([TAtlasStrings.Text(TAtlasTextId.ServerColumnRule), TAtlasStrings.Text(TAtlasTextId.ServerColumnMs),
    TAtlasStrings.Text(TAtlasTextId.ServerColumnCalls)], [260, 80, 80]);
  FRules.Align := alTop;
  FRules.OnData := RulesData;
  FRules.OnDblClick := RulesDblClick;
  FUnits := NewList([TAtlasStrings.Text(TAtlasTextId.ServerColumnUnit), TAtlasStrings.Text(TAtlasTextId.ServerColumnMs)],
    [260, 80]);
  FUnits.Align := alTop;
  FUnits.Top := 0;
  FUnits.OnData := UnitsData;
  FUnits.OnDblClick := UnitsDblClick;
  UpdateTexts;
end;

procedure TAtlasServerFrame.CreateWnd;
begin
  inherited;
  UpdateTexts;
end;

function TAtlasServerFrame.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasServerFrame.RowHeight: Integer;
begin
  Result := Scale(18);
end;

function TAtlasServerFrame.NewList(const AColumns: array of string; const AWidths: array of Integer): TListView;
var
  mIndex: Integer;
  mColumn: TListColumn;
begin
  Result := TListView.Create(Self);
  Result.Parent := FTables;
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
      mColumn.Alignment := taRightJustify;
  end;
end;

function TAtlasServerFrame.NewButton(const ACaption: string; ALeft, AWidth: Integer; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FBottom;
  Result.Left := ALeft;
  Result.Top := 6;
  Result.Width := AWidth;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

class function TAtlasServerFrame.PartCaption(APart: TAtlasServerMemoryPart): string;
begin
  case APart of
    TAtlasServerMemoryPart.Symbols:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerMemorySymbols);
    TAtlasServerMemoryPart.Usages:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerMemoryUsages);
    TAtlasServerMemoryPart.LibraryUnits:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerMemoryLibrary);
    TAtlasServerMemoryPart.TreeCache:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerMemoryTrees);
    TAtlasServerMemoryPart.Documents:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerMemoryDocuments);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.ServerMemoryRest);
  end;
end;

class function TAtlasServerFrame.StateCaption(AState: TAtlasServerState): string;
begin
  case AState of
    TAtlasServerState.Loading:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerStateLoading);
    TAtlasServerState.Ready:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerStateReady);
    TAtlasServerState.Checking:
      Result := TAtlasStrings.Text(TAtlasTextId.ServerStateChecking);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.ServerStateUnknown);
  end;
end;

function PercentText(APercent: Integer): string;
begin
  if APercent < 0 then
    Result := TAtlasStrings.Text(TAtlasTextId.ServerWindowUnknownValue)
  else
    Result := IntToStr(APercent) + ' %';
end;

procedure TAtlasServerFrame.UpdateTexts;
begin
  FQueue.Caption := '';
  FCheckRun.Caption := '';
  if not FRunning then
    FHeader.Caption := TAtlasStrings.Text(TAtlasTextId.ServerWindowNoServer)
  else if not FSnapshot.Valid then
    FHeader.Caption := TAtlasStrings.Text(TAtlasTextId.ServerWindowWaiting)
  else if not FSnapshot.Known then
    FHeader.Caption := TAtlasStrings.Text(TAtlasTextId.ServerWindowOldServer)
  else
  begin
    FHeader.Caption := TAtlasStrings.Fmt(TAtlasTextId.ServerWindowHeader, [FSnapshot.ProcessId, FSnapshot.Version,
      TAtlasServerTexts.Duration(FSnapshot.UptimeMs), StateCaption(FSnapshot.State), FRestarts]);
    FQueue.Caption := TAtlasStrings.Fmt(TAtlasTextId.ServerWindowQueue, [FSnapshot.IndexWaiting,
      FSnapshot.IndexRunning, FSnapshot.CheckWaiting, FSnapshot.CheckRunning,
      TAtlasServerTexts.Duration(FSnapshot.OldestWaitMs)]) + sLineBreak +
      TAtlasStrings.Fmt(TAtlasTextId.ServerWindowCacheHits, [PercentText(FSnapshot.IndexHitPercent),
      PercentText(FSnapshot.TreeHitPercent), Max(FSnapshot.Units, 0)]);
    if FSnapshot.CheckActive then
      FCheckRun.Caption := TAtlasStrings.Fmt(TAtlasTextId.ServerWindowCheckRunning, [FSnapshot.CheckUnits])
    else if FSnapshot.CheckSerial = 0 then
      FCheckRun.Caption := TAtlasStrings.Text(TAtlasTextId.ServerWindowNoCheckRun)
    else
      FCheckRun.Caption := TAtlasStrings.Fmt(TAtlasTextId.ServerWindowCheckRun,
        [FormatDateTime('hh":"nn', FSnapshot.CheckStarted), FSnapshot.CheckUnits,
        TAtlasServerTexts.Duration(FSnapshot.CheckDurationMs)]);
  end;
  FOverBudget.Visible := FRunning and FSnapshot.OverBudget;
  FOverBudget.Font.Color := ToColor(FColors.Warn);
  // Die Anzahl der virtuellen Listen braucht ein Fenster; ohne Eltern setzt CreateWnd sie nach.
  if HandleAllocated or (Parent <> nil) then
  begin
    FUnits.Items.Count := Length(FSnapshot.SlowUnits);
    FRules.Items.Count := Length(FSnapshot.SlowRules);
    FRequests.Items.Count := Length(FSnapshot.Requests);
  end;
  FUnits.Invalidate;
  FRules.Invalidate;
  FRequests.Invalidate;
  FMemory.Invalidate;
end;

procedure TAtlasServerFrame.SetSnapshot(const ASnapshot: TAtlasServerSnapshot; ARunning: Boolean; ARestarts: Integer);
begin
  FRunning := ARunning;
  if ARunning then
    FSnapshot := ASnapshot
  else
    FSnapshot := Default(TAtlasServerSnapshot);
  FRestarts := ARestarts;
  FRebuild.Enabled := ARunning;
  UpdateTexts;
end;

procedure TAtlasServerFrame.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FOverBudget.Font.Color := ToColor(FColors.Warn);
  FMemory.Invalidate;
end;

procedure TAtlasServerFrame.ShowNote(const AText: string);
begin
  FNote.Caption := AText;
end;

procedure TAtlasServerFrame.TablesResize(Sender: TObject);
begin
  // Drei gleich hohe Tabellen untereinander; die Anfragen nehmen den Rest.
  FUnits.Height := Max(Scale(60), FTables.ClientHeight div 3 - Scale(6));
  FRules.Height := FUnits.Height;
end;

procedure TAtlasServerFrame.UnitsData(Sender: TObject; Item: TListItem);
var
  mUnit: TAtlasServerSlowUnit;
begin
  if (Item.Index < 0) or (Item.Index > High(FSnapshot.SlowUnits)) then
    Exit;
  mUnit := FSnapshot.SlowUnits[Item.Index];
  Item.Caption := mUnit.Name;
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mUnit.Ms, FormatSettings));
end;

procedure TAtlasServerFrame.RulesData(Sender: TObject; Item: TListItem);
var
  mRule: TAtlasServerSlowRule;
begin
  if (Item.Index < 0) or (Item.Index > High(FSnapshot.SlowRules)) then
    Exit;
  mRule := FSnapshot.SlowRules[Item.Index];
  Item.Caption := mRule.Id;
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mRule.Ms, FormatSettings));
  Item.SubItems.Add(IntToStr(mRule.Calls));
end;

procedure TAtlasServerFrame.RequestsData(Sender: TObject; Item: TListItem);
var
  mRequest: TAtlasServerRequest;
begin
  if (Item.Index < 0) or (Item.Index > High(FSnapshot.Requests)) then
    Exit;
  mRequest := FSnapshot.Requests[Item.Index];
  Item.Caption := mRequest.Method;
  Item.SubItems.Add(IntToStr(mRequest.Count));
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mRequest.AverageMs, FormatSettings));
  Item.SubItems.Add(TAtlasServerTexts.Milliseconds(mRequest.MaxMs, FormatSettings));
  Item.SubItems.Add(IntToStr(mRequest.Failed));
end;

procedure TAtlasServerFrame.OpenUnit(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSnapshot.SlowUnits)) or not Assigned(FOnOpenUnit) then
    Exit;
  FOnOpenUnit(FSnapshot.SlowUnits[AIndex]);
end;

procedure TAtlasServerFrame.OpenRule(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSnapshot.SlowRules)) or not Assigned(FOnOpenRule) then
    Exit;
  FOnOpenRule(FSnapshot.SlowRules[AIndex].Id);
end;

procedure TAtlasServerFrame.UnitsDblClick(Sender: TObject);
begin
  if FUnits.Selected <> nil then
    OpenUnit(FUnits.Selected.Index);
end;

procedure TAtlasServerFrame.RulesDblClick(Sender: TObject);
begin
  if FRules.Selected <> nil then
    OpenRule(FRules.Selected.Index);
end;

procedure TAtlasServerFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TAtlasServerFrame.RebuildClick(Sender: TObject);
begin
  if Assigned(FOnRebuild) then
    FOnRebuild();
end;

procedure TAtlasServerFrame.PackageClick(Sender: TObject);
begin
  if Assigned(FOnPackage) then
    FOnPackage();
end;

procedure TAtlasServerFrame.MemoryPaint(Sender: TObject);
const
  cTextFlags = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS;
var
  mCanvas: TCanvas;
  mBounds, mRow, mBar, mFill: TRect;
  mLabelWidth, mValueWidth, mIndex, mBudgetX: Integer;
  mPart: TAtlasServerMemoryPart;
  mFraction: Double;
  mText: string;
  mWarn: Boolean;

  procedure DrawRow(const ACaption, AValue: string; AFraction: Double; AWarnColor: Boolean);
  var
    mCell: TRect;
  begin
    mRow := Rect(mBounds.Left, mBounds.Top + mIndex * RowHeight, mBounds.Right,
      mBounds.Top + (mIndex + 1) * RowHeight);
    mCanvas.Brush.Style := bsClear;
    mCanvas.Font.Color := ToColor(FColors.Text);
    mCell := Rect(mRow.Left, mRow.Top, mRow.Left + mLabelWidth, mRow.Bottom);
    DrawText(mCanvas.Handle, PChar(ACaption), Length(ACaption), mCell, cTextFlags or DT_LEFT);
    mCell := Rect(mRow.Right - mValueWidth, mRow.Top, mRow.Right, mRow.Bottom);
    DrawText(mCanvas.Handle, PChar(AValue), Length(AValue), mCell, cTextFlags or DT_RIGHT);
    mBar := Rect(mRow.Left + mLabelWidth, mRow.Top + Scale(4), mRow.Right - mValueWidth - Scale(8),
      mRow.Bottom - Scale(4));
    if mBar.Right <= mBar.Left then
      Exit;
    mCanvas.Brush.Style := bsSolid;
    mCanvas.Brush.Color := ToColor(FColors.Gutter);
    mCanvas.FillRect(mBar);
    mFill := mBar;
    mFill.Right := mBar.Left + Round(mBar.Width * AFraction);
    if mFill.Right > mFill.Left then
    begin
      if AWarnColor then
        mCanvas.Brush.Color := ToColor(FColors.Warn)
      else
        mCanvas.Brush.Color := ToColor(FColors.Accent);
      mCanvas.FillRect(mFill);
    end;
    // Budget als senkrechter Strich, wenn es kleiner als der Maßstab ist.
    if (FSnapshot.MemoryBudget > 0) and (FSnapshot.Scale > 0) then
    begin
      mBudgetX := mBar.Left + Round(mBar.Width * Min(FSnapshot.MemoryBudget / FSnapshot.Scale, 1));
      mCanvas.Pen.Color := ToColor(FColors.Error);
      mCanvas.MoveTo(mBudgetX, mBar.Top - Scale(2));
      mCanvas.LineTo(mBudgetX, mBar.Bottom + Scale(2));
    end;
  end;

begin
  mCanvas := FMemory.Canvas;
  mBounds := FMemory.ClientRect;
  mCanvas.Font := Font;
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Brush.Color := ToColor(FColors.Surface);
  mCanvas.FillRect(mBounds);
  if not FRunning or not FSnapshot.Valid then
    Exit;
  mLabelWidth := Scale(130);
  mValueWidth := Scale(150);
  mIndex := 0;
  for mPart := Low(TAtlasServerMemoryPart) to High(TAtlasServerMemoryPart) do
  begin
    mFraction := FSnapshot.Fraction(mPart);
    // Über dem Budget fallen die Verwendungen auf: Sie werden ausgelagert.
    mWarn := FSnapshot.OverBudget and (mPart = TAtlasServerMemoryPart.Usages);
    DrawRow(PartCaption(mPart), TAtlasServerTexts.Megabytes(FSnapshot.Memory[mPart], FormatSettings), mFraction,
      mWarn);
    Inc(mIndex);
  end;
  if FSnapshot.MemoryBudget > 0 then
    mText := TAtlasServerTexts.Megabytes(FSnapshot.MemoryTotal, FormatSettings) + ' / ' +
      TAtlasStrings.Fmt(TAtlasTextId.ServerWindowBudget, [TAtlasServerTexts.Megabytes(FSnapshot.MemoryBudget,
      FormatSettings)])
  else
    mText := TAtlasServerTexts.Megabytes(FSnapshot.MemoryTotal, FormatSettings) + ' / ' +
      TAtlasStrings.Text(TAtlasTextId.ServerWindowNoBudget);
  mCanvas.Font.Style := [fsBold];
  DrawRow(TAtlasStrings.Text(TAtlasTextId.ServerMemoryTotal), mText, FSnapshot.TotalFraction, FSnapshot.OverBudget);
  mCanvas.Font.Style := [];
end;

end.
