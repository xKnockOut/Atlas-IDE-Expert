unit Monitor.Hosting.AssistantsPage;

// Reiter „KI-Assistenten“ (AI assistants) von AtlasMonitor (#2611): oben je laufendem MCP-Prozess eine Zeile mit
// Client, Beginn und Summen, darunter die Tabelle der Werkzeuge, Ressourcen und Prompts aller Sitzungen (Aufrufe,
// Fehler, Dauer, Antwortgröße, letzter fehlgeschlagener Aufruf), rechts die Einzelheiten der gewählten Zeile.
// Auffällige Fehlerquoten stehen rot. Die Einträge liest das Fenster mit dem Reiter „Server“ (TServerStatusFile
// .List); Regeln und Texte stehen in TMonitorAssistants. Mit mcp.statistics aus zählt ein Prozess nicht und
// erscheint nur als Zeile oben.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Text.McpStatistics,
  Atlas.Common.Diagnostics.StatusFile;

type
  TMonitorAssistantPage = class(TComponent)
  private
    FTab: TTabSheet;
    FSummary: TMemo;
    FList: TListView;
    FDetails: TMemo;
    FSessions: TArray<TMcpAssistantSession>;
    FRows: TArray<TMcpAssistantRow>;
    function SelectedRow(out ARow: TMcpAssistantRow): Boolean;
    procedure ListSelectItem(ASender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure ListCustomDrawItem(ASender: TCustomListView; AItem: TListItem; AState: TCustomDrawState;
      var ADefaultDraw: Boolean);
  public
    /// <summary>Legt den Reiter in APages an (noch verborgen, siehe Tab).</summary>
    constructor Create(AOwner: TComponent; APages: TPageControl); reintroduce;
    destructor Destroy; override;
    /// <summary>Sitzungen aus AEntries zeigen (Auswahl bleibt nach Zeilenname); erst mit Fenster.</summary>
    procedure Fill(const AEntries: TArray<TServerStatusEntry>);
    procedure ShowDetails;
    /// <summary>Ohne Fenster scheitert ein sichtbarer Reiter; das Formular zeigt ihn in CreateWnd.</summary>
    property Tab: TTabSheet read FTab;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Common.Monitor.Assistants;

const
  /// <summary>Spalten vor den Zellen aus TMcpCallSummary.Cells: KI-Assistent.</summary>
  cAssistantColumns = 1;
  cSummaryHeight = 72;
  cDetailsWidth = 340;
  cColumnWidth = 90;
  cWideColumnWidth = 200;
  cLastFailedWidth = 320;
  // Rot für auffällige Fehlerquoten als TColor ($00BBGGRR), wie der Zustand „hängt“ im Reiter „Server“.
  cConspicuousColor = $002020D0;

/// <summary>AValue in Pixeln bei 96 dpi, umgerechnet auf die Auflösung des Bildschirms.</summary>
function Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

/// <summary>Schlüssel einer Zeile zum Wiederfinden der Auswahl: pid, Art und Name.</summary>
function RowKey(const ASessions: TArray<TMcpAssistantSession>; const ARow: TMcpAssistantRow): string;
var
  mPid: Cardinal;
begin
  mPid := 0;
  if (ARow.Session >= 0) and (ARow.Session <= High(ASessions)) then
  begin
    mPid := ASessions[ARow.Session].Pid;
  end;
  Result := IntToStr(mPid) + #9 + TMcpStatisticsFormat.KindCode(ARow.Call.Kind) + #9 + ARow.Call.Name;
end;

{ TMonitorAssistantPage }

constructor TMonitorAssistantPage.Create(AOwner: TComponent; APages: TPageControl);
var
  mTitle: string;
  mColumn: TListColumn;
  mSplitter: TSplitter;
  mIndex: Integer;
begin
  inherited Create(AOwner);
  FTab := TTabSheet.Create(Self);
  FTab.Caption := TMonitorAssistants.TabCaption;
  // Ohne Fenster scheitert ein sichtbarer Reiter; das Formular zeigt ihn in CreateWnd.
  FTab.TabVisible := False;
  FTab.PageControl := APages;
  FSummary := TMemo.Create(Self);
  // Höhe vor Align und Parent, sonst kann die VCL die Reihenfolge beim Anlegen vertauschen.
  FSummary.Height := Px(cSummaryHeight);
  FSummary.Align := alTop;
  FSummary.ReadOnly := True;
  FSummary.ScrollBars := ssVertical;
  FSummary.Parent := FTab;
  FDetails := TMemo.Create(Self);
  FDetails.Width := Px(cDetailsWidth);
  FDetails.Align := alRight;
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssVertical;
  FDetails.Parent := FTab;
  mSplitter := TSplitter.Create(Self);
  mSplitter.Align := alRight;
  mSplitter.Parent := FTab;
  FList := TListView.Create(Self);
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnSelectItem := ListSelectItem;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  mIndex := 0;
  for mTitle in TMonitorAssistants.ColumnTitles do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := mTitle;
    mColumn.Width := Px(cColumnWidth);
    // Zahlen rechtsbündig: Aufrufe bis Größte (vor den Zellen der Statistik steht die Spalte KI-Assistent).
    if (mIndex > Ord(TMcpCallColumn.Name) + cAssistantColumns) and
      (mIndex <= Ord(TMcpCallColumn.MaxBytes) + cAssistantColumns) then
    begin
      mColumn.Alignment := taRightJustify;
    end;
    Inc(mIndex);
  end;
  // KI-Assistent und Name sind breiter, der letzte fehlgeschlagene Aufruf am breitesten.
  FList.Columns[0].Width := Px(cWideColumnWidth);
  FList.Columns[1].Width := Px(cWideColumnWidth);
  FList.Columns[FList.Columns.Count - 1].Width := Px(cLastFailedWidth);
  FList.Parent := FTab;
end;

destructor TMonitorAssistantPage.Destroy;
begin
  FSessions := nil;
  FRows := nil;
  inherited;
end;

function TMonitorAssistantPage.SelectedRow(out ARow: TMcpAssistantRow): Boolean;
var
  mIndex: Integer;
begin
  ARow := Default(TMcpAssistantRow);
  mIndex := -1;
  if FList.Selected <> nil then
  begin
    mIndex := FList.Selected.Index;
  end;
  Result := (mIndex >= 0) and (mIndex <= High(FRows));
  if Result then
  begin
    ARow := FRows[mIndex];
  end;
end;

procedure TMonitorAssistantPage.ListSelectItem(ASender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  ShowDetails;
end;

procedure TMonitorAssistantPage.ListCustomDrawItem(ASender: TCustomListView; AItem: TListItem;
  AState: TCustomDrawState; var ADefaultDraw: Boolean);
begin
  ADefaultDraw := True;
  if (AItem.Index >= 0) and (AItem.Index <= High(FRows)) and FRows[AItem.Index].Call.Conspicuous then
  begin
    ASender.Canvas.Font.Color := cConspicuousColor;
  end;
end;

procedure TMonitorAssistantPage.Fill(const AEntries: TArray<TServerStatusEntry>);
var
  mRow: TMcpAssistantRow;
  mItem: TListItem;
  mCells: TArray<string>;
  mIndex: Integer;
  mSelected: string;
begin
  mSelected := '';
  if SelectedRow(mRow) then
  begin
    mSelected := RowKey(FSessions, mRow);
  end;
  FSessions := TMonitorAssistants.Sessions(AEntries);
  FRows := TMcpAssistantSessions.Rows(FSessions);
  FSummary.Lines.Text := string.Join(sLineBreak, TMonitorAssistants.Summary(FSessions));
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRow in FRows do
    begin
      mCells := TMonitorAssistants.Columns(FSessions, mRow);
      mItem := FList.Items.Add;
      mItem.Caption := mCells[0];
      for mIndex := 1 to High(mCells) do
      begin
        mItem.SubItems.Add(mCells[mIndex]);
      end;
      if (mSelected <> '') and (RowKey(FSessions, mRow) = mSelected) then
      begin
        mItem.Selected := True;
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  ShowDetails;
end;

procedure TMonitorAssistantPage.ShowDetails;
var
  mRow: TMcpAssistantRow;
begin
  if SelectedRow(mRow) then
  begin
    FDetails.Lines.Text := string.Join(sLineBreak, TMonitorAssistants.Details(FSessions, mRow));
  end
  else
  begin
    FDetails.Lines.Text := TMonitorAssistants.SelectRow;
  end;
end;

end.
