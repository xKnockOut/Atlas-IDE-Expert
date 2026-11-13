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
  private type
    /// <summary>Steuerelemente des Frames.</summary>
    TParts = record
      Top: TFlowPanel;
      Refresh: TButton;
      Save: TButton;
      Level: TComboBox;
      Filter: TEdit;
      Chart: TAtlasHotspotChartView;
      Splitter: TSplitter;
      Pages: TPageControl;
      /// <summary>Reiter in Reihenfolge; CreateWnd hängt sie ein (das braucht das Fenster des PageControls).
      /// </summary>
      Sheets: TArray<TTabSheet>;
      HotspotSheet: TTabSheet;
      CouplingSheet: TTabSheet;
      HistorySheet: TTabSheet;
      Hotspots: TListView;
      Coupling: TListView;
      HistoryInfo: TLabel;
      History: TListView;
      Status: TLabel;
      Menu: TPopupMenu;
      MenuOpen: TMenuItem;
      MenuHistory: TMenuItem;
      MenuImpact: TMenuItem;
    end;

    /// <summary>Rückrufe an die IDE-Schicht.</summary>
    THandlers = record
      OnRefresh: TProc;
      OnSave: TProc<string>;
      OnLevelChanged: TProc<string>;
      OnOpen: TProc<string, Integer>;
      OnImpact: TProc<string, Integer, string>;
    end;

    /// <summary>Gezeigte Daten und Auswahl.</summary>
    TState = record
      Model: TAtlasHotspotModel;
      HasModel: Boolean;
      MessageText: string;
      /// <summary>'unit' oder 'method'; gilt auch ohne Fenster.</summary>
      LevelValue: string;
      Updating: Boolean;
      /// <summary>Gezeigte Zeilen der Rangliste (Nummern in Entries).</summary>
      Rows: TArray<Integer>;
      Pairs: TArray<Integer>;
      /// <summary>Gewählte Zeile (Nummer in Entries), -1 = keine.</summary>
      Selected: Integer;
      /// <summary>Zeile, deren Verlauf der Reiter zeigt, -1 = keine.</summary>
      HistoryEntry: Integer;
    end;

    /// <summary>Ereignisse der Steuerelemente; gehört dem Frame.</summary>
    TEvents = class(TComponent)
    private
      FFrame: TAtlasHotspotsFrame;
    public
      constructor Create(AFrame: TAtlasHotspotsFrame); reintroduce;
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
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FState: TState;
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
    property Model: TAtlasHotspotModel read FState.Model;
    property HasModel: Boolean read FState.HasModel;
    property Chart: TAtlasHotspotChartView read FParts.Chart;
    property Pages: TPageControl read FParts.Pages;
    property RefreshButton: TButton read FParts.Refresh;
    property SaveButton: TButton read FParts.Save;
    property Filter: TEdit read FParts.Filter;
    property HotspotList: TListView read FParts.Hotspots;
    property HistoryInfo: TLabel read FParts.HistoryInfo;
    property StatusLabel: TLabel read FParts.Status;
    property Menu: TPopupMenu read FParts.Menu;
    property Selected: Integer read FState.Selected;
    /// <summary>'unit' oder 'method'.</summary>
    property LevelValue: string read FState.LevelValue write SetLevelValue;
    property OnRefresh: TProc read FHandlers.OnRefresh write FHandlers.OnRefresh;
    /// <summary>Gewählte Zieldatei (.html, .md oder .json).</summary>
    property OnSave: TProc<string> read FHandlers.OnSave write FHandlers.OnSave;
    /// <summary>Ebene im Fenster gewechselt ('unit' oder 'method').</summary>
    property OnLevelChanged: TProc<string> read FHandlers.OnLevelChanged write FHandlers.OnLevelChanged;
    /// <summary>Vollständiger Pfad und Zeile ab 1 (1 = Anfang der Unit).</summary>
    property OnOpen: TProc<string, Integer> read FHandlers.OnOpen write FHandlers.OnOpen;
    /// <summary>Vollständiger Pfad, Zeile ab 1 und Methode (TFoo.Bar; '' auf Unit-Ebene).</summary>
    property OnImpact: TProc<string, Integer, string> read FHandlers.OnImpact write FHandlers.OnImpact;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Dialogs,
  Atlas.UI.Analysis.Strings;

{$R *.dfm}

const
  cLevelValues: array[0..1] of string = ('unit', 'method');

type
  THotspotsFrame = TAtlasHotspotsFrame;

function Entries(AFrame: THotspotsFrame): TArray<TAtlasHotspotEntry>;
begin
  Result := AFrame.FState.Model.Entries;
end;

function ValidEntry(AFrame: THotspotsFrame; AEntry: Integer): Boolean;
begin
  Result := (AEntry >= 0) and (AEntry < Length(Entries(AFrame)));
end;

function NewSheet(AFrame: THotspotsFrame; AText: TAtlasAnalysisTextId): TTabSheet;
begin
  Result := TTabSheet.Create(AFrame);
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (CreateWnd zeigt ihn).
  Result.TabVisible := False;
  Result.PageControl := AFrame.FParts.Pages;
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  AFrame.FParts.Sheets := AFrame.FParts.Sheets + [Result];
end;

function NewList(AFrame: THotspotsFrame; AParent: TWinControl; AEvents: THotspotsFrame.TEvents): TListView;
begin
  Result := TListView.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.RowSelect := True;
  Result.ReadOnly := True;
  Result.HideSelection := False;
  Result.ColumnClick := False;
  Result.OnKeyDown := AEvents.ListKeyDown;
end;

procedure AddColumn(AList: TListView; AText: TAtlasAnalysisTextId; AWidth, APpi: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasAnalysisStrings.Text(AText);
  mColumn.Width := MulDiv(AWidth, APpi, 96);
end;

procedure FillHotspotColumns(AFrame: THotspotsFrame);
var
  mList: TListView;
  mPpi: Integer;
begin
  mList := AFrame.FParts.Hotspots;
  mPpi := AFrame.CurrentPPI;
  mList.Columns.BeginUpdate;
  try
    mList.Columns.Clear;
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColRank, 36, mPpi);
    if AFrame.FState.LevelValue = cLevelValues[1] then
    begin
      AddColumn(mList, TAtlasAnalysisTextId.HotspotsColMethod, 220, mPpi);
    end
    else
    begin
      AddColumn(mList, TAtlasAnalysisTextId.HotspotsColUnit, 220, mPpi);
    end;
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColScore, 60, mPpi);
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColChanges, 80, mPpi);
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColAuthors, 60, mPpi);
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColComplexity, 85, mPpi);
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColLines, 60, mPpi);
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColTrend, 70, mPpi);
    AddColumn(mList, TAtlasAnalysisTextId.HotspotsColLast, 90, mPpi);
  finally
    mList.Columns.EndUpdate;
  end;
end;

function CanFill(AControl: TWinControl): Boolean;
begin
  Result := AControl.HandleAllocated or (GetParentForm(AControl) <> nil);
end;

procedure FillLevel(AFrame: THotspotsFrame);
var
  mLevel: TComboBox;
begin
  mLevel := AFrame.FParts.Level;
  if not CanFill(mLevel) then
  begin
    Exit;
  end;
  AFrame.FState.Updating := True;
  try
    mLevel.Items.BeginUpdate;
    try
      mLevel.Items.Clear;
      mLevel.Items.Add(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsLevelUnits));
      mLevel.Items.Add(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsLevelMethods));
    finally
      mLevel.Items.EndUpdate;
    end;
    if AFrame.FState.LevelValue = cLevelValues[1] then
    begin
      mLevel.ItemIndex := 1;
    end
    else
    begin
      mLevel.ItemIndex := 0;
    end;
  finally
    AFrame.FState.Updating := False;
  end;
end;

function TrendCaption(const ATrend: string): string;
begin
  if ATrend = 'rising' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsTrendRising);
  end
  else if ATrend = 'steady' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsTrendSteady);
  end
  else if ATrend = 'falling' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsTrendFalling);
  end
  else if ATrend = 'new' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsTrendNew);
  end
  else
  begin
    Result := '';
  end;
end;

procedure AddHotspotItem(AList: TListView; const AEntry: TAtlasHotspotEntry; ARank: Integer; ASelected: Boolean);
var
  mItem: TListItem;
begin
  mItem := AList.Items.Add;
  // Rang in der ganzen Liste, nicht in der gefilterten.
  mItem.Caption := IntToStr(ARank);
  mItem.SubItems.Add(AEntry.Caption);
  mItem.SubItems.Add(FormatFloat('0.00', AEntry.Score, FormatSettings));
  mItem.SubItems.Add(IntToStr(AEntry.Changes));
  mItem.SubItems.Add(IntToStr(AEntry.Authors));
  mItem.SubItems.Add(IntToStr(AEntry.Complexity));
  mItem.SubItems.Add(IntToStr(AEntry.Lines));
  mItem.SubItems.Add(TrendCaption(AEntry.Trend));
  mItem.SubItems.Add(Copy(AEntry.LastChange, 1, 10));
  if ASelected then
  begin
    mItem.Selected := True;
  end;
end;

procedure FillHotspots(AFrame: THotspotsFrame);
var
  mIndex: Integer;
  mAll: TArray<TAtlasHotspotEntry>;
  mRows: TArray<Integer>;
  mList: TListView;
begin
  mList := AFrame.FParts.Hotspots;
  if not CanFill(mList) then
  begin
    Exit;
  end;
  mAll := Entries(AFrame);
  mRows := AFrame.FState.Rows;
  AFrame.FState.Updating := True;
  mList.Items.BeginUpdate;
  try
    mList.Items.Clear;
    for mIndex := 0 to High(mRows) do
    begin
      AddHotspotItem(mList, mAll[mRows[mIndex]], mRows[mIndex] + 1, mRows[mIndex] = AFrame.FState.Selected);
    end;
  finally
    mList.Items.EndUpdate;
    AFrame.FState.Updating := False;
  end;
end;

procedure FillCoupling(AFrame: THotspotsFrame);
var
  mIndex: Integer;
  mItem: TListItem;
  mPair: TAtlasHotspotPair;
  mList: TListView;
begin
  mList := AFrame.FParts.Coupling;
  if not CanFill(mList) then
  begin
    Exit;
  end;
  mList.Items.BeginUpdate;
  try
    mList.Items.Clear;
    for mIndex in AFrame.FState.Pairs do
    begin
      mPair := AFrame.FState.Model.Coupling[mIndex];
      mItem := mList.Items.Add;
      mItem.Caption := mPair.FirstUnit;
      mItem.SubItems.Add(mPair.SecondUnit);
      mItem.SubItems.Add(IntToStr(mPair.Shared));
      mItem.SubItems.Add(IntToStr(Round(mPair.Ratio * 100)) + ' %');
    end;
  finally
    mList.Items.EndUpdate;
  end;
end;

procedure AddCommitItem(AList: TListView; const ACommit: TAtlasHotspotCommit; const AVcs: string);
var
  mItem: TListItem;
begin
  mItem := AList.Items.Add;
  mItem.Caption := ACommit.ShortRevision(AVcs);
  mItem.SubItems.Add(Copy(ACommit.Date, 1, 10));
  mItem.SubItems.Add(ACommit.Author);
  mItem.SubItems.Add(ACommit.Summary);
  if ACommit.Added < 0 then
  begin
    mItem.SubItems.Add('');
  end
  else
  begin
    mItem.SubItems.Add('+' + IntToStr(ACommit.Added) + ' −' + IntToStr(ACommit.Deleted));
  end;
end;

procedure FillHistory(AFrame: THotspotsFrame);
var
  mEntry: TAtlasHotspotEntry;
  mCommit: TAtlasHotspotCommit;
  mList: TListView;
begin
  if not ValidEntry(AFrame, AFrame.FState.HistoryEntry) then
  begin
    AFrame.FState.HistoryEntry := -1;
    AFrame.FParts.HistoryInfo.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsHistoryNone);
  end
  else
  begin
    mEntry := Entries(AFrame)[AFrame.FState.HistoryEntry];
    AFrame.FParts.HistoryInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.HotspotsHistoryOf,
      [mEntry.Caption, mEntry.Changes]);
  end;
  mList := AFrame.FParts.History;
  if not CanFill(mList) then
  begin
    Exit;
  end;
  mList.Items.BeginUpdate;
  try
    mList.Items.Clear;
    if AFrame.FState.HistoryEntry >= 0 then
    begin
      for mCommit in Entries(AFrame)[AFrame.FState.HistoryEntry].History do
      begin
        AddCommitItem(mList, mCommit, AFrame.FState.Model.Vcs);
      end;
    end;
  finally
    mList.Items.EndUpdate;
  end;
end;

function StatusText(const AState: THotspotsFrame.TState): string;
var
  mRange: string;
begin
  if AState.MessageText <> '' then
  begin
    Exit(AState.MessageText);
  end;
  Result := '';
  if not AState.HasModel then
  begin
    Exit;
  end;
  mRange := 'Git';
  if SameText(AState.Model.Vcs, 'svn') then
  begin
    mRange := 'SVN';
  end;
  mRange := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.HotspotsRange,
    [mRange, AState.Model.Months, Copy(AState.Model.Since, 1, 10), AState.Model.Commits]);
  Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.HotspotsStatus, [mRange, Length(AState.Model.Units),
    Length(AState.Model.Methods), Length(AState.Model.Coupling)]);
end;

procedure UpdateStatus(AFrame: THotspotsFrame);
begin
  AFrame.FParts.Status.Caption := StatusText(AFrame.FState);
end;

procedure FillAll(AFrame: THotspotsFrame);
var
  mChart: TAtlasHotspotChartView;
begin
  AFrame.FState.Rows := AFrame.FState.Model.Filter(AFrame.FParts.Filter.Text);
  AFrame.FState.Pairs := AFrame.FState.Model.FilterCoupling(AFrame.FParts.Filter.Text);
  mChart := AFrame.FParts.Chart;
  if AFrame.FState.HasModel and (Length(Entries(AFrame)) = 0) then
  begin
    mChart.EmptyText := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsNoEntries);
  end
  else
  begin
    mChart.EmptyText := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsChartHint);
  end;
  mChart.SetEntries(Entries(AFrame), AFrame.FState.Rows);
  mChart.SelectEntry(AFrame.FState.Selected);
  FillHotspots(AFrame);
  FillCoupling(AFrame);
  FillHistory(AFrame);
  UpdateStatus(AFrame);
end;

procedure SelectRow(AFrame: THotspotsFrame; AEntry: Integer);
var
  mIndex: Integer;
  mList: TListView;
begin
  mList := AFrame.FParts.Hotspots;
  if not CanFill(mList) then
  begin
    Exit;
  end;
  AFrame.FState.Updating := True;
  try
    for mIndex := 0 to High(AFrame.FState.Rows) do
    begin
      if (AFrame.FState.Rows[mIndex] = AEntry) and (mIndex < mList.Items.Count) then
      begin
        mList.Items[mIndex].Selected := True;
        mList.Items[mIndex].MakeVisible(False);
        Exit;
      end;
    end;
    mList.Selected := nil;
  finally
    AFrame.FState.Updating := False;
  end;
end;

/// <summary>Neu berechnen, Bericht speichern, Ebene und Filter.</summary>
procedure BuildTop(AFrame: THotspotsFrame; AEvents: THotspotsFrame.TEvents);
var
  mTop: TFlowPanel;
begin
  // Fließende Leiste: bei schmalem Fenster brechen die Bedienelemente in weitere Zeilen um.
  mTop := TFlowPanel.Create(AFrame);
  mTop.Parent := AFrame;
  mTop.Align := alTop;
  mTop.BevelOuter := bvNone;
  mTop.ShowCaption := False;
  mTop.AutoWrap := True;
  mTop.AutoSize := True;
  mTop.Padding.SetBounds(2, 2, 2, 2);
  AFrame.FParts.Top := mTop;
  AFrame.FParts.Refresh := TButton.Create(AFrame);
  AFrame.FParts.Refresh.Parent := mTop;
  AFrame.FParts.Refresh.AlignWithMargins := True;
  AFrame.FParts.Refresh.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsRefresh);
  AFrame.FParts.Refresh.Width := AFrame.FParts.Refresh.ScaleValue(110);
  AFrame.FParts.Refresh.OnClick := AEvents.RefreshClick;
  AFrame.FParts.Save := TButton.Create(AFrame);
  AFrame.FParts.Save.Parent := mTop;
  AFrame.FParts.Save.AlignWithMargins := True;
  AFrame.FParts.Save.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsSaveReport);
  AFrame.FParts.Save.Width := AFrame.FParts.Save.ScaleValue(130);
  AFrame.FParts.Save.OnClick := AEvents.SaveClick;
  AFrame.FParts.Level := TComboBox.Create(AFrame);
  AFrame.FParts.Level.Parent := mTop;
  AFrame.FParts.Level.AlignWithMargins := True;
  AFrame.FParts.Level.Style := csDropDownList;
  AFrame.FParts.Level.Width := AFrame.FParts.Level.ScaleValue(110);
  AFrame.FParts.Level.OnChange := AEvents.LevelChange;
  AFrame.FParts.Filter := TEdit.Create(AFrame);
  AFrame.FParts.Filter.Parent := mTop;
  AFrame.FParts.Filter.AlignWithMargins := True;
  // Feste Breite statt alClient, damit das Feld in der fließenden Leiste umbrechen kann.
  AFrame.FParts.Filter.Width := AFrame.FParts.Filter.ScaleValue(200);
  AFrame.FParts.Filter.TextHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsFilterHint);
  AFrame.FParts.Filter.OnChange := AEvents.FilterChange;
end;

function NewMenuItem(AMenu: TPopupMenu; AText: TAtlasAnalysisTextId; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  Result.OnClick := AOnClick;
  AMenu.Items.Add(Result);
end;

/// <summary>Statuszeile und Kontextmenü.</summary>
procedure BuildStatusAndMenu(AFrame: THotspotsFrame; AEvents: THotspotsFrame.TEvents);
var
  mMenu: TPopupMenu;
begin
  AFrame.FParts.Status := TLabel.Create(AFrame);
  AFrame.FParts.Status.Parent := AFrame;
  AFrame.FParts.Status.Align := alBottom;
  AFrame.FParts.Status.AlignWithMargins := True;
  AFrame.FParts.Status.ShowAccelChar := False;
  AFrame.FParts.Status.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.Status.Caption := '';
  mMenu := TPopupMenu.Create(AFrame);
  mMenu.OnPopup := AEvents.MenuPopup;
  AFrame.FParts.Menu := mMenu;
  AFrame.FParts.MenuOpen := NewMenuItem(mMenu, TAtlasAnalysisTextId.HotspotsMenuOpen, AEvents.MenuOpenClick);
  AFrame.FParts.MenuOpen.Default := True;
  AFrame.FParts.MenuHistory := NewMenuItem(mMenu, TAtlasAnalysisTextId.HotspotsMenuHistory,
    AEvents.MenuHistoryClick);
  AFrame.FParts.MenuImpact := NewMenuItem(mMenu, TAtlasAnalysisTextId.HotspotsMenuImpact, AEvents.MenuImpactClick);
end;

function ChartSelectHandler(AFrame: THotspotsFrame): TProc<Integer>;
begin
  Result :=
    procedure(AEntry: Integer)
    begin
      AFrame.Select(AEntry);
    end;
end;

function ChartOpenHandler(AFrame: THotspotsFrame): TProc<Integer>;
begin
  Result :=
    procedure(AEntry: Integer)
    begin
      AFrame.OpenEntry(AEntry);
    end;
end;

/// <summary>Blasendiagramm, Teiler und das PageControl der Reiter.</summary>
procedure BuildChart(AFrame: THotspotsFrame);
var
  mChart: TAtlasHotspotChartView;
begin
  mChart := TAtlasHotspotChartView.Create(AFrame);
  mChart.Parent := AFrame;
  mChart.Align := alTop;
  mChart.AlignWithMargins := True;
  mChart.Height := MulDiv(220, AFrame.CurrentPPI, 96);
  mChart.EmptyText := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsChartHint);
  mChart.PopupMenu := AFrame.FParts.Menu;
  mChart.OnSelect := ChartSelectHandler(AFrame);
  mChart.OnOpen := ChartOpenHandler(AFrame);
  AFrame.FParts.Chart := mChart;
  AFrame.FParts.Splitter := TSplitter.Create(AFrame);
  AFrame.FParts.Splitter.Parent := AFrame;
  AFrame.FParts.Splitter.Align := alTop;
  AFrame.FParts.Splitter.Top := mChart.Top + mChart.Height + 1;
  AFrame.FParts.Splitter.MinSize := MulDiv(80, AFrame.CurrentPPI, 96);
  AFrame.FParts.Pages := TPageControl.Create(AFrame);
  AFrame.FParts.Pages.Parent := AFrame;
  AFrame.FParts.Pages.Align := alClient;
  AFrame.FParts.Pages.AlignWithMargins := True;
end;

/// <summary>Reiter Hotspots, Änderungskopplung und Verlauf.</summary>
procedure BuildSheets(AFrame: THotspotsFrame; AEvents: THotspotsFrame.TEvents);
var
  mPpi: Integer;
begin
  mPpi := AFrame.CurrentPPI;
  AFrame.FParts.HotspotSheet := NewSheet(AFrame, TAtlasAnalysisTextId.HotspotsTabHotspots);
  AFrame.FParts.Hotspots := NewList(AFrame, AFrame.FParts.HotspotSheet, AEvents);
  AFrame.FParts.Hotspots.PopupMenu := AFrame.FParts.Menu;
  AFrame.FParts.Hotspots.OnSelectItem := AEvents.HotspotsSelect;
  AFrame.FParts.Hotspots.OnDblClick := AEvents.HotspotsDblClick;
  AFrame.FParts.CouplingSheet := NewSheet(AFrame, TAtlasAnalysisTextId.HotspotsTabCoupling);
  AFrame.FParts.Coupling := NewList(AFrame, AFrame.FParts.CouplingSheet, AEvents);
  AFrame.FParts.Coupling.OnDblClick := AEvents.CouplingDblClick;
  AddColumn(AFrame.FParts.Coupling, TAtlasAnalysisTextId.HotspotsColFirst, 200, mPpi);
  AddColumn(AFrame.FParts.Coupling, TAtlasAnalysisTextId.HotspotsColSecond, 200, mPpi);
  AddColumn(AFrame.FParts.Coupling, TAtlasAnalysisTextId.HotspotsColShared, 80, mPpi);
  AddColumn(AFrame.FParts.Coupling, TAtlasAnalysisTextId.HotspotsColRatio, 70, mPpi);
  AFrame.FParts.HistorySheet := NewSheet(AFrame, TAtlasAnalysisTextId.HotspotsTabHistory);
  AFrame.FParts.HistoryInfo := TLabel.Create(AFrame);
  AFrame.FParts.HistoryInfo.Parent := AFrame.FParts.HistorySheet;
  AFrame.FParts.HistoryInfo.Align := alTop;
  AFrame.FParts.HistoryInfo.AlignWithMargins := True;
  AFrame.FParts.HistoryInfo.ShowAccelChar := False;
  AFrame.FParts.HistoryInfo.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.HistoryInfo.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsHistoryNone);
  AFrame.FParts.History := NewList(AFrame, AFrame.FParts.HistorySheet, AEvents);
  AddColumn(AFrame.FParts.History, TAtlasAnalysisTextId.HotspotsColRevision, 80, mPpi);
  AddColumn(AFrame.FParts.History, TAtlasAnalysisTextId.HotspotsColDate, 90, mPpi);
  AddColumn(AFrame.FParts.History, TAtlasAnalysisTextId.HotspotsColAuthor, 120, mPpi);
  AddColumn(AFrame.FParts.History, TAtlasAnalysisTextId.HotspotsColSummary, 300, mPpi);
  AddColumn(AFrame.FParts.History, TAtlasAnalysisTextId.HotspotsColLines, 70, mPpi);
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
    begin
      mLine := mLine + #9 + AList.Items[mIndex].SubItems[mColumn];
    end;
    Result := Result + [mLine];
  end;
end;

{ TAtlasHotspotsFrame.TEvents }

constructor TAtlasHotspotsFrame.TEvents.Create(AFrame: TAtlasHotspotsFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
end;

procedure TAtlasHotspotsFrame.TEvents.RefreshClick(Sender: TObject);
begin
  if Assigned(FFrame.FHandlers.OnRefresh) then
  begin
    FFrame.FHandlers.OnRefresh();
  end;
end;

procedure TAtlasHotspotsFrame.TEvents.SaveClick(Sender: TObject);
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsSaveFilter);
    mDialog.DefaultExt := 'html';
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if FFrame.FState.Model.Title <> '' then
    begin
      mDialog.FileName := 'Hotspots-' + FFrame.FState.Model.Title + '.html';
    end;
    if mDialog.Execute and Assigned(FFrame.FHandlers.OnSave) then
    begin
      FFrame.FHandlers.OnSave(mDialog.FileName);
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasHotspotsFrame.TEvents.LevelChange(Sender: TObject);
begin
  if FFrame.FState.Updating or (FFrame.FParts.Level.ItemIndex < 0) then
  begin
    Exit;
  end;
  FFrame.LevelValue := cLevelValues[EnsureRange(FFrame.FParts.Level.ItemIndex, 0, High(cLevelValues))];
  if Assigned(FFrame.FHandlers.OnLevelChanged) then
  begin
    FFrame.FHandlers.OnLevelChanged(FFrame.FState.LevelValue);
  end;
end;

procedure TAtlasHotspotsFrame.TEvents.FilterChange(Sender: TObject);
begin
  FillAll(FFrame);
  FFrame.Select(FFrame.FState.Selected);
end;

procedure TAtlasHotspotsFrame.TEvents.HotspotsSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFrame.FState.Updating or not Selected or (Item = nil) or (Item.Index > High(FFrame.FState.Rows)) then
  begin
    Exit;
  end;
  FFrame.FState.Selected := FFrame.FState.Rows[Item.Index];
  FFrame.FParts.Chart.SelectEntry(FFrame.FState.Selected);
end;

procedure TAtlasHotspotsFrame.TEvents.HotspotsDblClick(Sender: TObject);
begin
  FFrame.OpenEntry(FFrame.FState.Selected);
end;

procedure TAtlasHotspotsFrame.TEvents.CouplingDblClick(Sender: TObject);
var
  mPair: TAtlasHotspotPair;
  mList: TListView;
begin
  mList := FFrame.FParts.Coupling;
  if (mList.Selected = nil) or (mList.Selected.Index > High(FFrame.FState.Pairs))
    or not Assigned(FFrame.FHandlers.OnOpen) then
  begin
    Exit;
  end;
  mPair := FFrame.FState.Model.Coupling[FFrame.FState.Pairs[mList.Selected.Index]];
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    FFrame.FHandlers.OnOpen(mPair.SecondFile, 1);
  end
  else
  begin
    FFrame.FHandlers.OnOpen(mPair.FirstFile, 1);
  end;
end;

procedure TAtlasHotspotsFrame.TEvents.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then
  begin
    Exit;
  end;
  if Sender = FFrame.FParts.Hotspots then
  begin
    HotspotsDblClick(Sender);
  end
  else if Sender = FFrame.FParts.Coupling then
  begin
    CouplingDblClick(Sender);
  end;
  Key := 0;
end;

procedure TAtlasHotspotsFrame.TEvents.MenuPopup(Sender: TObject);
var
  mHas: Boolean;
begin
  mHas := ValidEntry(FFrame, FFrame.FState.Selected);
  FFrame.FParts.MenuOpen.Enabled := mHas;
  FFrame.FParts.MenuHistory.Enabled := mHas;
  FFrame.FParts.MenuImpact.Enabled := mHas and Assigned(FFrame.FHandlers.OnImpact);
end;

procedure TAtlasHotspotsFrame.TEvents.MenuOpenClick(Sender: TObject);
begin
  FFrame.OpenEntry(FFrame.FState.Selected);
end;

procedure TAtlasHotspotsFrame.TEvents.MenuHistoryClick(Sender: TObject);
begin
  FFrame.ShowHistory(FFrame.FState.Selected);
end;

procedure TAtlasHotspotsFrame.TEvents.MenuImpactClick(Sender: TObject);
begin
  FFrame.ShowImpact(FFrame.FState.Selected);
end;

{ TAtlasHotspotsFrame }

constructor TAtlasHotspotsFrame.Create(AOwner: TComponent);
var
  mEvents: TEvents;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FState.LevelValue := cLevelValues[0];
  FState.Selected := -1;
  FState.HistoryEntry := -1;
  mEvents := TEvents.Create(Self);
  BuildTop(Self, mEvents);
  BuildStatusAndMenu(Self, mEvents);
  BuildChart(Self);
  BuildSheets(Self, mEvents);
  FillHotspotColumns(Self);
end;

procedure TAtlasHotspotsFrame.CreateWnd;
var
  mSheet: TTabSheet;
begin
  inherited CreateWnd;
  for mSheet in FParts.Sheets do
  begin
    mSheet.TabVisible := True;
  end;
  if (FParts.Pages.ActivePage = nil) and (Length(FParts.Sheets) > 0) then
  begin
    FParts.Pages.ActivePage := FParts.Sheets[0];
  end;
  // Combo und Listen halten ihre Einträge im Fenster: erst jetzt füllen.
  FillLevel(Self);
  FillAll(Self);
end;

/// <summary>Erste (höchstbewertete) Zeile der Unit AUnitName; -1 ohne.</summary>
function FirstOfUnit(AFrame: THotspotsFrame; const AUnitName: string): Integer;
var
  mIndex: Integer;
  mAll: TArray<TAtlasHotspotEntry>;
begin
  mAll := Entries(AFrame);
  for mIndex := 0 to High(mAll) do
  begin
    if SameText(mAll[mIndex].UnitName, AUnitName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasHotspotsFrame.SetLevelValue(const AValue: string);
var
  mValue: string;
  mSelected: string;
begin
  mValue := cLevelValues[0];
  if AValue = cLevelValues[1] then
  begin
    mValue := cLevelValues[1];
  end;
  if mValue = FState.LevelValue then
  begin
    FillLevel(Self);
    Exit;
  end;
  // Die Auswahl bleibt über die Unit erhalten, wenn es sie auf der anderen Ebene gibt.
  mSelected := '';
  if ValidEntry(Self, FState.Selected) then
  begin
    mSelected := Entries(Self)[FState.Selected].UnitName;
  end;
  FState.LevelValue := mValue;
  FState.Model.Level := mValue;
  FState.Selected := -1;
  FState.HistoryEntry := -1;
  FillLevel(Self);
  FillHotspotColumns(Self);
  FillAll(Self);
  if (mSelected <> '') and (FirstOfUnit(Self, mSelected) >= 0) then
  begin
    Select(FirstOfUnit(Self, mSelected));
  end;
end;

procedure TAtlasHotspotsFrame.SetModel(const AModel: TAtlasHotspotModel);
var
  mCaption: string;
  mIndex: Integer;
  mAll: TArray<TAtlasHotspotEntry>;
begin
  mCaption := '';
  if ValidEntry(Self, FState.Selected) then
  begin
    mCaption := Entries(Self)[FState.Selected].Caption + #1 + Entries(Self)[FState.Selected].Path;
  end;
  FState.Model := AModel;
  FState.Model.Level := FState.LevelValue;
  FState.HasModel := True;
  FState.MessageText := '';
  FState.Selected := -1;
  FState.HistoryEntry := -1;
  FillAll(Self);
  if mCaption = '' then
  begin
    Exit;
  end;
  mAll := Entries(Self);
  for mIndex in FState.Model.Filter('') do
  begin
    if mAll[mIndex].Caption + #1 + mAll[mIndex].Path = mCaption then
    begin
      Select(mIndex);
      Break;
    end;
  end;
end;

procedure TAtlasHotspotsFrame.SetMessage(const AText: string; AKeep: Boolean);
begin
  FState.MessageText := AText;
  if not AKeep then
  begin
    FState.Model := Default(TAtlasHotspotModel);
    FState.Model.Level := FState.LevelValue;
    FState.HasModel := False;
    FState.Selected := -1;
    FState.HistoryEntry := -1;
    FillAll(Self);
  end;
  UpdateStatus(Self);
end;

procedure TAtlasHotspotsFrame.Select(AEntry: Integer);
begin
  if not ValidEntry(Self, AEntry) then
  begin
    AEntry := -1;
  end;
  FState.Selected := AEntry;
  FParts.Chart.SelectEntry(AEntry);
  SelectRow(Self, AEntry);
end;

procedure TAtlasHotspotsFrame.OpenEntry(AEntry: Integer);
var
  mEntry: TAtlasHotspotEntry;
begin
  if not ValidEntry(Self, AEntry) or not Assigned(FHandlers.OnOpen) then
  begin
    Exit;
  end;
  mEntry := Entries(Self)[AEntry];
  FHandlers.OnOpen(mEntry.FileName, Max(1, mEntry.Line));
end;

procedure TAtlasHotspotsFrame.ShowHistory(AEntry: Integer);
begin
  if not ValidEntry(Self, AEntry) then
  begin
    Exit;
  end;
  Select(AEntry);
  FState.HistoryEntry := AEntry;
  FillHistory(Self);
  FParts.Pages.ActivePage := FParts.HistorySheet;
  OpenEntry(AEntry);
end;

procedure TAtlasHotspotsFrame.ShowImpact(AEntry: Integer);
var
  mEntry: TAtlasHotspotEntry;
begin
  if not ValidEntry(Self, AEntry) or not Assigned(FHandlers.OnImpact) then
  begin
    Exit;
  end;
  mEntry := Entries(Self)[AEntry];
  FHandlers.OnImpact(mEntry.FileName, Max(1, mEntry.Line), mEntry.Method);
end;

function TAtlasHotspotsFrame.HotspotText: TArray<string>;
begin
  Result := ListText(FParts.Hotspots);
end;

function TAtlasHotspotsFrame.CouplingText: TArray<string>;
begin
  Result := ListText(FParts.Coupling);
end;

function TAtlasHotspotsFrame.HistoryText: TArray<string>;
begin
  Result := ListText(FParts.History);
end;

end.
