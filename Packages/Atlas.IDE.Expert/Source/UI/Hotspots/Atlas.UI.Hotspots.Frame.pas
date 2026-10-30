unit Atlas.UI.Hotspots.Frame;

// Inhalt des Seitenfensters „Atlas-Hotspots“ (#1354), reine VCL: oben
// „Neu berechnen“, „Bericht speichern …“ (HTML, Markdown oder JSON), die
// Ebene (Units, Methoden) und ein Filter nach Unit- oder Methodennamen;
// darunter das Blasendiagramm (TAtlasHotspotChartView), ein Teiler und drei
// Reiter:
// - Hotspots: Rangliste mit Unit bzw. Methode, Wert, Änderungen, Autoren,
//   Komplexität, Zeilen, Trend und letzter Änderung,
// - Änderungskopplung: Paare ohne uses-Kante, die oft zusammen geändert
//   werden (gemeinsame Commits, Anteil),
// - Verlauf: Commits der gewählten Zeile im Zeitraum (Revision, Datum, Autor,
//   Betreff, Zeilen).
// Unten die Statuszeile (Stand der Versionsverwaltung bzw. ein Hinweis, etwa
// „Keine Versionsverwaltung“ statt einer leeren Liste).
// Klick in Diagramm oder Liste wählt die Zeile in beiden; Doppelklick oder
// Enter springt zur Methode bzw. Unit (OnOpen, Zeile ab 1). Kontextmenü:
// „Springen“, „Verlauf zeigen“ (Reiter Verlauf und Sprung, dort zeigt die
// Zeilenhistorie des Editors den Rest) und „Auswirkungen anzeigen“ (OnImpact,
// #1120). Doppelklick auf ein Kopplungspaar öffnet die erste Unit,
// Strg+Doppelklick die zweite. Die DFM ist leer, weil TCustomFrame.Create für
// abgeleitete Frames eine Ressource verlangt; aufgebaut wird im Code. Listen
// und Auswahl der Ebene brauchen ein Fenster: gefüllt wird erst mit Fenster
// (CreateWnd).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Hotspots.Model,
  Atlas.UI.Hotspots.Chart;

type
  TAtlasHotspotsFrame = class(TFrame)
  private
    FTop: TPanel;
    FRefresh: TButton;
    FSave: TButton;
    FLevel: TComboBox;
    FFilter: TEdit;
    FChart: TAtlasHotspotChartView;
    FSplitter: TSplitter;
    FPages: TPageControl;
    /// <summary>Reiter in Reihenfolge; CreateWnd hängt sie ein (das braucht das Fenster des PageControls).</summary>
    FSheets: TArray<TTabSheet>;
    FHotspotSheet: TTabSheet;
    FCouplingSheet: TTabSheet;
    FHistorySheet: TTabSheet;
    FHotspots: TListView;
    FCoupling: TListView;
    FHistoryInfo: TLabel;
    FHistory: TListView;
    FStatus: TLabel;
    FMenu: TPopupMenu;
    FMenuOpen: TMenuItem;
    FMenuHistory: TMenuItem;
    FMenuImpact: TMenuItem;
    FModel: TAtlasHotspotModel;
    FHasModel: Boolean;
    FMessageText: string;
    /// <summary>'unit' oder 'method'; gilt auch ohne Fenster.</summary>
    FLevelValue: string;
    FUpdating: Boolean;
    /// <summary>Gezeigte Zeilen der Rangliste (Nummern in Entries).</summary>
    FRows: TArray<Integer>;
    FPairs: TArray<Integer>;
    /// <summary>Gewählte Zeile (Nummer in Entries), -1 = keine.</summary>
    FSelected: Integer;
    /// <summary>Zeile, deren Verlauf der Reiter zeigt, -1 = keine.</summary>
    FHistoryEntry: Integer;
    FOnRefresh: TProc;
    FOnSave: TProc<string>;
    FOnLevelChanged: TProc<string>;
    FOnOpen: TProc<string, Integer>;
    FOnImpact: TProc<string, Integer, string>;
    function NewSheet(const ACaption: string): TTabSheet;
    function NewList(AParent: TWinControl): TListView;
    function AddColumn(AList: TListView; const ACaption: string; AWidth: Integer): TListColumn;
    function CanFill(AControl: TWinControl): Boolean;
    function TrendCaption(const ATrend: string): string;
    function Entries: TArray<TAtlasHotspotEntry>;
    procedure FillLevel;
    procedure FillAll;
    procedure FillHotspots;
    procedure FillCoupling;
    procedure FillHistory;
    procedure FillHotspotColumns;
    procedure UpdateStatus;
    procedure SelectRow(AEntry: Integer);
    procedure RefreshClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure LevelChange(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure HotspotsSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure HotspotsDblClick(Sender: TObject);
    procedure CouplingDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuPopup(Sender: TObject);
    procedure MenuOpenClick(Sender: TObject);
    procedure MenuHistoryClick(Sender: TObject);
    procedure MenuImpactClick(Sender: TObject);
    procedure ChartSelect(AEntry: Integer);
    procedure SetLevelValue(const AValue: string);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Neue Daten zeigen; Ebene, Filter und Reiter bleiben, die Auswahl nach Name.</summary>
    procedure SetModel(const AModel: TAtlasHotspotModel);
    /// <summary>Statt der Daten ein Hinweis in der Statuszeile (kein Projekt, kein Server, keine
    /// Versionsverwaltung, Rechnen läuft); AKeep: bisherige Daten stehen lassen.</summary>
    procedure SetMessage(const AText: string; AKeep: Boolean);
    /// <summary>Zeile wählen (Nummer in Entries) und in Diagramm und Liste zeigen.</summary>
    procedure Select(AEntry: Integer);
    /// <summary>Zur Zeile springen (OnOpen).</summary>
    procedure OpenEntry(AEntry: Integer);
    /// <summary>Verlauf der Zeile im Reiter „Verlauf“ zeigen und hinspringen.</summary>
    procedure ShowHistory(AEntry: Integer);
    /// <summary>„Auswirkungen anzeigen“ für die Zeile (OnImpact).</summary>
    procedure ShowImpact(AEntry: Integer);
    /// <summary>Zeile für Zeile der Text einer Liste (für Tests und Bildschirmleser).</summary>
    function HotspotText: TArray<string>;
    function CouplingText: TArray<string>;
    function HistoryText: TArray<string>;
    property Model: TAtlasHotspotModel read FModel;
    property HasModel: Boolean read FHasModel;
    property Chart: TAtlasHotspotChartView read FChart;
    property Pages: TPageControl read FPages;
    property RefreshButton: TButton read FRefresh;
    property SaveButton: TButton read FSave;
    property LevelCombo: TComboBox read FLevel;
    property Filter: TEdit read FFilter;
    property HotspotList: TListView read FHotspots;
    property CouplingList: TListView read FCoupling;
    property HistoryList: TListView read FHistory;
    property HistoryInfo: TLabel read FHistoryInfo;
    property StatusLabel: TLabel read FStatus;
    property Menu: TPopupMenu read FMenu;
    property Selected: Integer read FSelected;
    /// <summary>'unit' oder 'method'.</summary>
    property LevelValue: string read FLevelValue write SetLevelValue;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    /// <summary>Gewählte Zieldatei (.html, .md oder .json).</summary>
    property OnSave: TProc<string> read FOnSave write FOnSave;
    /// <summary>Ebene im Fenster gewechselt ('unit' oder 'method').</summary>
    property OnLevelChanged: TProc<string> read FOnLevelChanged write FOnLevelChanged;
    /// <summary>Vollständiger Pfad und Zeile ab 1 (1 = Anfang der Unit).</summary>
    property OnOpen: TProc<string, Integer> read FOnOpen write FOnOpen;
    /// <summary>Vollständiger Pfad, Zeile ab 1 und Methode (TFoo.Bar; '' auf Unit-Ebene).</summary>
    property OnImpact: TProc<string, Integer, string> read FOnImpact write FOnImpact;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Dialogs,
  Atlas.UI.Strings;

{$R *.dfm}

const
  cLevelValues: array[0..1] of string = ('unit', 'method');

{ TAtlasHotspotsFrame }

constructor TAtlasHotspotsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FLevelValue := cLevelValues[0];
  FSelected := -1;
  FHistoryEntry := -1;

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.ShowCaption := False;
  FTop.AutoSize := True;
  FTop.Padding.SetBounds(2, 2, 2, 2);

  FRefresh := TButton.Create(Self);
  FRefresh.Parent := FTop;
  FRefresh.Align := alLeft;
  FRefresh.AlignWithMargins := True;
  FRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsRefresh);
  FRefresh.Width := 110;
  FRefresh.OnClick := RefreshClick;

  FSave := TButton.Create(Self);
  FSave.Parent := FTop;
  FSave.Align := alLeft;
  FSave.AlignWithMargins := True;
  FSave.Left := FRefresh.Left + FRefresh.Width + 1;
  FSave.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsSaveReport);
  FSave.Width := 130;
  FSave.OnClick := SaveClick;

  FLevel := TComboBox.Create(Self);
  FLevel.Parent := FTop;
  FLevel.Align := alLeft;
  FLevel.AlignWithMargins := True;
  FLevel.Left := FSave.Left + FSave.Width + 1;
  FLevel.Style := csDropDownList;
  FLevel.Width := 110;
  FLevel.OnChange := LevelChange;

  FFilter := TEdit.Create(Self);
  FFilter.Parent := FTop;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasStrings.Text(TAtlasTextId.HotspotsFilterHint);
  FFilter.OnChange := FilterChange;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;
  FStatus.Caption := '';

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FMenuOpen := TMenuItem.Create(FMenu);
  FMenuOpen.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsMenuOpen);
  FMenuOpen.Default := True;
  FMenuOpen.OnClick := MenuOpenClick;
  FMenu.Items.Add(FMenuOpen);
  FMenuHistory := TMenuItem.Create(FMenu);
  FMenuHistory.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsMenuHistory);
  FMenuHistory.OnClick := MenuHistoryClick;
  FMenu.Items.Add(FMenuHistory);
  FMenuImpact := TMenuItem.Create(FMenu);
  FMenuImpact.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsMenuImpact);
  FMenuImpact.OnClick := MenuImpactClick;
  FMenu.Items.Add(FMenuImpact);

  FChart := TAtlasHotspotChartView.Create(Self);
  FChart.Parent := Self;
  FChart.Align := alTop;
  FChart.AlignWithMargins := True;
  FChart.Height := MulDiv(220, CurrentPPI, 96);
  FChart.EmptyText := TAtlasStrings.Text(TAtlasTextId.HotspotsChartHint);
  FChart.PopupMenu := FMenu;
  FChart.OnSelect :=
    procedure(AEntry: Integer)
    begin
      ChartSelect(AEntry);
    end;
  FChart.OnOpen :=
    procedure(AEntry: Integer)
    begin
      OpenEntry(AEntry);
    end;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alTop;
  FSplitter.Top := FChart.Top + FChart.Height + 1;
  FSplitter.MinSize := MulDiv(80, CurrentPPI, 96);

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;

  FHotspotSheet := NewSheet(TAtlasStrings.Text(TAtlasTextId.HotspotsTabHotspots));
  FHotspots := NewList(FHotspotSheet);
  FHotspots.PopupMenu := FMenu;
  FHotspots.OnSelectItem := HotspotsSelect;
  FHotspots.OnDblClick := HotspotsDblClick;

  FCouplingSheet := NewSheet(TAtlasStrings.Text(TAtlasTextId.HotspotsTabCoupling));
  FCoupling := NewList(FCouplingSheet);
  FCoupling.OnDblClick := CouplingDblClick;
  AddColumn(FCoupling, TAtlasStrings.Text(TAtlasTextId.HotspotsColFirst), 200);
  AddColumn(FCoupling, TAtlasStrings.Text(TAtlasTextId.HotspotsColSecond), 200);
  AddColumn(FCoupling, TAtlasStrings.Text(TAtlasTextId.HotspotsColShared), 80);
  AddColumn(FCoupling, TAtlasStrings.Text(TAtlasTextId.HotspotsColRatio), 70);

  FHistorySheet := NewSheet(TAtlasStrings.Text(TAtlasTextId.HotspotsTabHistory));
  FHistoryInfo := TLabel.Create(Self);
  FHistoryInfo.Parent := FHistorySheet;
  FHistoryInfo.Align := alTop;
  FHistoryInfo.AlignWithMargins := True;
  FHistoryInfo.ShowAccelChar := False;
  FHistoryInfo.EllipsisPosition := epEndEllipsis;
  FHistoryInfo.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsHistoryNone);
  FHistory := NewList(FHistorySheet);
  AddColumn(FHistory, TAtlasStrings.Text(TAtlasTextId.HotspotsColRevision), 80);
  AddColumn(FHistory, TAtlasStrings.Text(TAtlasTextId.HotspotsColDate), 90);
  AddColumn(FHistory, TAtlasStrings.Text(TAtlasTextId.HotspotsColAuthor), 120);
  AddColumn(FHistory, TAtlasStrings.Text(TAtlasTextId.HotspotsColSummary), 300);
  AddColumn(FHistory, TAtlasStrings.Text(TAtlasTextId.HotspotsColLines), 70);
  FillHotspotColumns;
end;

function TAtlasHotspotsFrame.NewSheet(const ACaption: string): TTabSheet;
begin
  Result := TTabSheet.Create(Self);
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (CreateWnd zeigt ihn).
  Result.TabVisible := False;
  Result.PageControl := FPages;
  Result.Caption := ACaption;
  FSheets := FSheets + [Result];
end;

function TAtlasHotspotsFrame.NewList(AParent: TWinControl): TListView;
begin
  Result := TListView.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.RowSelect := True;
  Result.ReadOnly := True;
  Result.HideSelection := False;
  Result.ColumnClick := False;
  Result.OnKeyDown := ListKeyDown;
end;

function TAtlasHotspotsFrame.AddColumn(AList: TListView; const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := AList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

procedure TAtlasHotspotsFrame.FillHotspotColumns;
begin
  FHotspots.Columns.BeginUpdate;
  try
    FHotspots.Columns.Clear;
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColRank), 36);
    if FLevelValue = cLevelValues[1] then
      AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColMethod), 220)
    else
      AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColUnit), 220);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColScore), 60);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColChanges), 80);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColAuthors), 60);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColComplexity), 85);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColLines), 60);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColTrend), 70);
    AddColumn(FHotspots, TAtlasStrings.Text(TAtlasTextId.HotspotsColLast), 90);
  finally
    FHotspots.Columns.EndUpdate;
  end;
end;

procedure TAtlasHotspotsFrame.CreateWnd;
var
  mSheet: TTabSheet;
begin
  inherited CreateWnd;
  for mSheet in FSheets do
    mSheet.TabVisible := True;
  if (FPages.ActivePage = nil) and (Length(FSheets) > 0) then
    FPages.ActivePage := FSheets[0];
  // Combo und Listen halten ihre Einträge im Fenster: erst jetzt füllen.
  FillLevel;
  FillAll;
end;

function TAtlasHotspotsFrame.CanFill(AControl: TWinControl): Boolean;
begin
  Result := AControl.HandleAllocated or (GetParentForm(AControl) <> nil);
end;

procedure TAtlasHotspotsFrame.FillLevel;
begin
  if not CanFill(FLevel) then
    Exit;
  FUpdating := True;
  try
    FLevel.Items.BeginUpdate;
    try
      FLevel.Items.Clear;
      FLevel.Items.Add(TAtlasStrings.Text(TAtlasTextId.HotspotsLevelUnits));
      FLevel.Items.Add(TAtlasStrings.Text(TAtlasTextId.HotspotsLevelMethods));
    finally
      FLevel.Items.EndUpdate;
    end;
    if FLevelValue = cLevelValues[1] then
      FLevel.ItemIndex := 1
    else
      FLevel.ItemIndex := 0;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasHotspotsFrame.SetLevelValue(const AValue: string);
var
  mValue: string;
  mSelected: string;
  mIndex: Integer;
begin
  if AValue = cLevelValues[1] then
    mValue := cLevelValues[1]
  else
    mValue := cLevelValues[0];
  if mValue = FLevelValue then
  begin
    FillLevel;
    Exit;
  end;
  // Die Auswahl bleibt über die Unit erhalten, wenn es sie auf der anderen Ebene gibt.
  mSelected := '';
  if (FSelected >= 0) and (FSelected < Length(Entries)) then
    mSelected := Entries[FSelected].UnitName;
  FLevelValue := mValue;
  FModel.Level := mValue;
  FSelected := -1;
  FHistoryEntry := -1;
  FillLevel;
  FillHotspotColumns;
  FillAll;
  if mSelected = '' then
    Exit;
  // Erste (höchstbewertete) Zeile derselben Unit.
  for mIndex := 0 to High(Entries) do
    if SameText(Entries[mIndex].UnitName, mSelected) then
    begin
      Select(mIndex);
      Break;
    end;
end;

function TAtlasHotspotsFrame.Entries: TArray<TAtlasHotspotEntry>;
begin
  Result := FModel.Entries;
end;

procedure TAtlasHotspotsFrame.SetModel(const AModel: TAtlasHotspotModel);
var
  mCaption: string;
  mFound: TArray<Integer>;
  mIndex: Integer;
begin
  mCaption := '';
  if (FSelected >= 0) and (FSelected < Length(Entries)) then
    mCaption := Entries[FSelected].Caption + #1 + Entries[FSelected].Path;
  FModel := AModel;
  FModel.Level := FLevelValue;
  FHasModel := True;
  FMessageText := '';
  FSelected := -1;
  FHistoryEntry := -1;
  FillAll;
  if mCaption = '' then
    Exit;
  mFound := FModel.Filter('');
  for mIndex in mFound do
    if Entries[mIndex].Caption + #1 + Entries[mIndex].Path = mCaption then
    begin
      Select(mIndex);
      Break;
    end;
end;

procedure TAtlasHotspotsFrame.SetMessage(const AText: string; AKeep: Boolean);
begin
  FMessageText := AText;
  if not AKeep then
  begin
    FModel := Default(TAtlasHotspotModel);
    FModel.Level := FLevelValue;
    FHasModel := False;
    FSelected := -1;
    FHistoryEntry := -1;
    FillAll;
  end;
  UpdateStatus;
end;

function TAtlasHotspotsFrame.TrendCaption(const ATrend: string): string;
begin
  if ATrend = 'rising' then
    Result := TAtlasStrings.Text(TAtlasTextId.HotspotsTrendRising)
  else if ATrend = 'steady' then
    Result := TAtlasStrings.Text(TAtlasTextId.HotspotsTrendSteady)
  else if ATrend = 'falling' then
    Result := TAtlasStrings.Text(TAtlasTextId.HotspotsTrendFalling)
  else if ATrend = 'new' then
    Result := TAtlasStrings.Text(TAtlasTextId.HotspotsTrendNew)
  else
    Result := '';
end;

procedure TAtlasHotspotsFrame.FillAll;
begin
  FRows := FModel.Filter(FFilter.Text);
  FPairs := FModel.FilterCoupling(FFilter.Text);
  if FHasModel and (Length(Entries) = 0) then
    FChart.EmptyText := TAtlasStrings.Text(TAtlasTextId.HotspotsNoEntries)
  else
    FChart.EmptyText := TAtlasStrings.Text(TAtlasTextId.HotspotsChartHint);
  FChart.SetEntries(Entries, FRows);
  FChart.SelectEntry(FSelected);
  FillHotspots;
  FillCoupling;
  FillHistory;
  UpdateStatus;
end;

procedure TAtlasHotspotsFrame.FillHotspots;
var
  mIndex: Integer;
  mItem: TListItem;
  mEntry: TAtlasHotspotEntry;
  mAll: TArray<TAtlasHotspotEntry>;
begin
  if not CanFill(FHotspots) then
    Exit;
  mAll := Entries;
  FUpdating := True;
  FHotspots.Items.BeginUpdate;
  try
    FHotspots.Items.Clear;
    for mIndex := 0 to High(FRows) do
    begin
      mEntry := mAll[FRows[mIndex]];
      mItem := FHotspots.Items.Add;
      // Rang in der ganzen Liste, nicht in der gefilterten.
      mItem.Caption := IntToStr(FRows[mIndex] + 1);
      mItem.SubItems.Add(mEntry.Caption);
      mItem.SubItems.Add(FormatFloat('0.00', mEntry.Score));
      mItem.SubItems.Add(IntToStr(mEntry.Changes));
      mItem.SubItems.Add(IntToStr(mEntry.Authors));
      mItem.SubItems.Add(IntToStr(mEntry.Complexity));
      mItem.SubItems.Add(IntToStr(mEntry.Lines));
      mItem.SubItems.Add(TrendCaption(mEntry.Trend));
      mItem.SubItems.Add(Copy(mEntry.LastChange, 1, 10));
      if FRows[mIndex] = FSelected then
        mItem.Selected := True;
    end;
  finally
    FHotspots.Items.EndUpdate;
    FUpdating := False;
  end;
end;

procedure TAtlasHotspotsFrame.FillCoupling;
var
  mIndex: Integer;
  mItem: TListItem;
  mPair: TAtlasHotspotPair;
begin
  if not CanFill(FCoupling) then
    Exit;
  FCoupling.Items.BeginUpdate;
  try
    FCoupling.Items.Clear;
    for mIndex in FPairs do
    begin
      mPair := FModel.Coupling[mIndex];
      mItem := FCoupling.Items.Add;
      mItem.Caption := mPair.FirstUnit;
      mItem.SubItems.Add(mPair.SecondUnit);
      mItem.SubItems.Add(IntToStr(mPair.Shared));
      mItem.SubItems.Add(IntToStr(Round(mPair.Ratio * 100)) + ' %');
    end;
  finally
    FCoupling.Items.EndUpdate;
  end;
end;

procedure TAtlasHotspotsFrame.FillHistory;
var
  mItem: TListItem;
  mEntry: TAtlasHotspotEntry;
  mCommit: TAtlasHotspotCommit;
begin
  if (FHistoryEntry < 0) or (FHistoryEntry >= Length(Entries)) then
  begin
    FHistoryEntry := -1;
    FHistoryInfo.Caption := TAtlasStrings.Text(TAtlasTextId.HotspotsHistoryNone);
  end
  else
  begin
    mEntry := Entries[FHistoryEntry];
    FHistoryInfo.Caption := TAtlasStrings.Fmt(TAtlasTextId.HotspotsHistoryOf, [mEntry.Caption, mEntry.Changes]);
  end;
  if not CanFill(FHistory) then
    Exit;
  FHistory.Items.BeginUpdate;
  try
    FHistory.Items.Clear;
    if FHistoryEntry < 0 then
      Exit;
    for mCommit in Entries[FHistoryEntry].History do
    begin
      mItem := FHistory.Items.Add;
      mItem.Caption := mCommit.ShortRevision(FModel.Vcs);
      mItem.SubItems.Add(Copy(mCommit.Date, 1, 10));
      mItem.SubItems.Add(mCommit.Author);
      mItem.SubItems.Add(mCommit.Summary);
      if mCommit.Added < 0 then
        mItem.SubItems.Add('')
      else
        mItem.SubItems.Add('+' + IntToStr(mCommit.Added) + ' −' + IntToStr(mCommit.Deleted));
    end;
  finally
    FHistory.Items.EndUpdate;
  end;
end;

procedure TAtlasHotspotsFrame.UpdateStatus;
var
  mRange: string;
begin
  if FMessageText <> '' then
    FStatus.Caption := FMessageText
  else if FHasModel then
  begin
    if SameText(FModel.Vcs, 'svn') then
      mRange := 'SVN'
    else
      mRange := 'Git';
    mRange := TAtlasStrings.Fmt(TAtlasTextId.HotspotsRange, [mRange, FModel.Months, Copy(FModel.Since, 1, 10),
      FModel.Commits]);
    FStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.HotspotsStatus, [mRange, Length(FModel.Units),
      Length(FModel.Methods), Length(FModel.Coupling)]);
  end
  else
    FStatus.Caption := '';
end;

procedure TAtlasHotspotsFrame.SelectRow(AEntry: Integer);
var
  mIndex: Integer;
begin
  if not CanFill(FHotspots) then
    Exit;
  FUpdating := True;
  try
    for mIndex := 0 to High(FRows) do
      if (FRows[mIndex] = AEntry) and (mIndex < FHotspots.Items.Count) then
      begin
        FHotspots.Items[mIndex].Selected := True;
        FHotspots.Items[mIndex].MakeVisible(False);
        Exit;
      end;
    FHotspots.Selected := nil;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasHotspotsFrame.Select(AEntry: Integer);
begin
  if (AEntry < 0) or (AEntry >= Length(Entries)) then
    AEntry := -1;
  FSelected := AEntry;
  FChart.SelectEntry(AEntry);
  SelectRow(AEntry);
end;

procedure TAtlasHotspotsFrame.ChartSelect(AEntry: Integer);
begin
  Select(AEntry);
end;

procedure TAtlasHotspotsFrame.OpenEntry(AEntry: Integer);
var
  mEntry: TAtlasHotspotEntry;
begin
  if (AEntry < 0) or (AEntry >= Length(Entries)) or not Assigned(FOnOpen) then
    Exit;
  mEntry := Entries[AEntry];
  FOnOpen(mEntry.FileName, Max(1, mEntry.Line));
end;

procedure TAtlasHotspotsFrame.ShowHistory(AEntry: Integer);
begin
  if (AEntry < 0) or (AEntry >= Length(Entries)) then
    Exit;
  Select(AEntry);
  FHistoryEntry := AEntry;
  FillHistory;
  FPages.ActivePage := FHistorySheet;
  OpenEntry(AEntry);
end;

procedure TAtlasHotspotsFrame.ShowImpact(AEntry: Integer);
var
  mEntry: TAtlasHotspotEntry;
begin
  if (AEntry < 0) or (AEntry >= Length(Entries)) or not Assigned(FOnImpact) then
    Exit;
  mEntry := Entries[AEntry];
  FOnImpact(mEntry.FileName, Max(1, mEntry.Line), mEntry.Method);
end;

procedure TAtlasHotspotsFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TAtlasHotspotsFrame.SaveClick(Sender: TObject);
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TAtlasStrings.Text(TAtlasTextId.HotspotsSaveFilter);
    mDialog.DefaultExt := 'html';
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if FModel.Title <> '' then
      mDialog.FileName := 'Hotspots-' + FModel.Title + '.html';
    if mDialog.Execute and Assigned(FOnSave) then
      FOnSave(mDialog.FileName);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasHotspotsFrame.LevelChange(Sender: TObject);
begin
  if FUpdating or (FLevel.ItemIndex < 0) then
    Exit;
  LevelValue := cLevelValues[EnsureRange(FLevel.ItemIndex, 0, High(cLevelValues))];
  if Assigned(FOnLevelChanged) then
    FOnLevelChanged(FLevelValue);
end;

procedure TAtlasHotspotsFrame.FilterChange(Sender: TObject);
begin
  FillAll;
  Select(FSelected);
end;

procedure TAtlasHotspotsFrame.HotspotsSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FUpdating or not Selected or (Item = nil) or (Item.Index > High(FRows)) then
    Exit;
  FSelected := FRows[Item.Index];
  FChart.SelectEntry(FSelected);
end;

procedure TAtlasHotspotsFrame.HotspotsDblClick(Sender: TObject);
begin
  OpenEntry(FSelected);
end;

procedure TAtlasHotspotsFrame.CouplingDblClick(Sender: TObject);
var
  mPair: TAtlasHotspotPair;
begin
  if (FCoupling.Selected = nil) or (FCoupling.Selected.Index > High(FPairs)) or not Assigned(FOnOpen) then
    Exit;
  mPair := FModel.Coupling[FPairs[FCoupling.Selected.Index]];
  if GetKeyState(VK_CONTROL) < 0 then
    FOnOpen(mPair.SecondFile, 1)
  else
    FOnOpen(mPair.FirstFile, 1);
end;

procedure TAtlasHotspotsFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then
    Exit;
  if Sender = FHotspots then
    HotspotsDblClick(Sender)
  else if Sender = FCoupling then
    CouplingDblClick(Sender);
  Key := 0;
end;

procedure TAtlasHotspotsFrame.MenuPopup(Sender: TObject);
var
  mHas: Boolean;
begin
  mHas := (FSelected >= 0) and (FSelected < Length(Entries));
  FMenuOpen.Enabled := mHas;
  FMenuHistory.Enabled := mHas;
  FMenuImpact.Enabled := mHas and Assigned(FOnImpact);
end;

procedure TAtlasHotspotsFrame.MenuOpenClick(Sender: TObject);
begin
  OpenEntry(FSelected);
end;

procedure TAtlasHotspotsFrame.MenuHistoryClick(Sender: TObject);
begin
  ShowHistory(FSelected);
end;

procedure TAtlasHotspotsFrame.MenuImpactClick(Sender: TObject);
begin
  ShowImpact(FSelected);
end;

function ListText(AList: TListView): TArray<string>;
var
  mIndex, mColumn: Integer;
  mLine: string;
begin
  Result := nil;
  for mIndex := 0 to AList.Items.Count - 1 do
  begin
    mLine := AList.Items[mIndex].Caption;
    for mColumn := 0 to AList.Items[mIndex].SubItems.Count - 1 do
      mLine := mLine + #9 + AList.Items[mIndex].SubItems[mColumn];
    Result := Result + [mLine];
  end;
end;

function TAtlasHotspotsFrame.HotspotText: TArray<string>;
begin
  Result := ListText(FHotspots);
end;

function TAtlasHotspotsFrame.CouplingText: TArray<string>;
begin
  Result := ListText(FCoupling);
end;

function TAtlasHotspotsFrame.HistoryText: TArray<string>;
begin
  Result := ListText(FHistory);
end;

end.
