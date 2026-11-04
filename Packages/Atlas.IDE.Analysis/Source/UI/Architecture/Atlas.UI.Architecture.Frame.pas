unit Atlas.UI.Architecture.Frame;

// Inhalt des Seitenfensters „Atlas-Architektur“ (#1118), reine VCL: oben
// „Neu berechnen“, „Bericht speichern …“, „Stand speichern …“ und
// „Vergleichen mit …“ (#1121, Datei .json), Umfang (Projektgruppe, Projekt),
// „Bibliotheks-Units“, der Regler „Feinheit“ (#1366, TAtlasResolutionSlider,
// daneben „γ = 1,0 · 6 Teilsysteme“; OnResolutionChanged beim Loslassen,
// ShowResolution blendet ihn aus) und ein Filter nach Unit-Namen; darunter
// sechs Reiter:
// - Übersicht: „Einpassen“, „Namen“, „implementation-uses“, „Zyklen
//   markieren“, „Änderungen zum Stand“ (nur mit Vergleich) und „Teilsysteme ▾“
//   (ein- und ausblenden), die Karte (TAtlasArchitectureMap), darunter Angaben
//   zur gewählten Unit bzw. der Weg nach Umschalt+Klick; mit
//   architecture.explainAssignment (#1368) dazu die Zuordnung der gewählten
//   Unit als Tabelle (Steckbrief) und als Hinweis über der Karte,
// - Zentrale Units: Tabelle, Klick auf eine Spalte sortiert (nochmals:
//   umgekehrt); ShowCostRanking zeigt sie nach „gesamt abhängig“ absteigend,
//   also die Units, deren interface-Änderung am meisten neu übersetzt
//   (#554),
// - Teilsysteme: Baum mit Zusammenhalt und Units, Ausreißer mit Grund und
//   knapp zugeordnete Units (#1368); das Fragezeichen darüber erklärt, wie
//   die Teilsysteme entstehen,
// - Zyklen: je Zyklus der Weg und die uses-Einträge mit Fundstelle,
// - Querverbindungen: seltene Kanten und Kanten gegen die Hauptrichtung,
// - Vergleich (#1121): gegen welchen Stand, „Vergleich aufheben“ und je
//   Abschnitt (neue Zyklen, Querverbindungen, Kanten zwischen Teilsystemen,
//   Wechsel, Wachstum, Units) die Einträge; ohne Vergleich ein Hinweis, bei
//   unlesbarem Stand die Meldung.
// Unten die Statuszeile (Zahlen, Index-Stand, Rechendauer und Ausschlüsse,
// „Teilsysteme an Stand vom … angeglichen“ (#1367) bzw. ein Hinweis). Das Menü
// „Teilsysteme ▾“ bietet mit OnRenameSubsystems „Teilsysteme neu benennen“.
// Doppelklick oder Enter öffnet die Unit (OnOpenUnit) bzw. springt zum
// uses-Eintrag (OnOpenLocation, Zeile und Spalte ab 1); Strg+Doppelklick auf
// eine Unit zeigt sie im Fenster „Unit-Beziehungen“ (OnUnitRelations, #593).
// Der Filter wirkt auf
// Karte und alle Listen. Die IDE-Schicht bettet den Frame in ein andockbares
// Fenster ein, fragt den Server und ruft SetModel bzw. SetMessage. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code. Listen, Bäume und die Auswahl des Umfangs
// brauchen ein Fenster: gefüllt wird erst mit Fenster (CreateWnd).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Architecture.MapState,
  Atlas.Core.Architecture.Model,
  Atlas.UI.Architecture.Map,
  Atlas.UI.Architecture.Slider;

type
  TAtlasArchitectureFrame = class(TFrame)
  private
    FTop: TPanel;
    FRefresh: TButton;
    FSave: TButton;
    FSaveState: TButton;
    FCompare: TButton;
    FScope: TComboBox;
    FLibrary: TCheckBox;
    FResolutionCaption: TLabel;
    FResolution: TAtlasResolutionSlider;
    FResolutionInfo: TLabel;
    FFilter: TEdit;
    FPages: TPageControl;
    /// <summary>Reiter in Reihenfolge; CreateWnd hängt sie ein (das braucht das Fenster des PageControls).</summary>
    FSheets: TArray<TTabSheet>;
    FMapBar: TPanel;
    FFit: TButton;
    FNames: TCheckBox;
    FImplementation: TCheckBox;
    FMarkCycles: TCheckBox;
    FChanges: TCheckBox;
    FSubsystemsButton: TButton;
    FSubsystemsMenu: TPopupMenu;
    FMap: TAtlasArchitectureMap;
    FInfo: TLabel;
    /// <summary>Zuordnung der gewählten Unit (#1368), unter der Karte.</summary>
    FAssignment: TPaintBox;
    FAssignmentBox: TScrollBox;
    FAssignmentSplit: TSplitter;
    FSubsystemsBar: TPanel;
    FExplainButton: TButton;
    FExplanation: TLabel;
    FCentral: TListView;
    FSubsystems: TTreeView;
    FCycles: TTreeView;
    FCrossLinks: TListView;
    FCompareBar: TPanel;
    FCompareInfo: TLabel;
    FClearCompare: TButton;
    FComparison: TTreeView;
    FStatus: TLabel;
    FModel: TAtlasArchitectureModel;
    FHasModel: Boolean;
    FMessageText: string;
    /// <summary>'projectGroup' oder 'project'; gilt auch ohne Fenster.</summary>
    FScopeValue: string;
    FUpdating: Boolean;
    FSortColumn: TAtlasArchColumn;
    FSortDescending: Boolean;
    /// <summary>Gezeigte Zeilen der Tabelle „Zentrale Units“ (Nummern der Units).</summary>
    FCentralRows: TArray<Integer>;
    /// <summary>uses-Einträge der Bäume und der Querverbindungen; Data eines Knotens = Nummer + 1.</summary>
    FLinks: TArray<TAtlasArchLink>;
    FCrossRows: TArray<Integer>;
    FOnRefresh: TProc;
    FOnSave: TProc<string>;
    FOnSaveState: TProc<string>;
    FOnCompare: TProc<string>;
    FOnClearComparison: TProc;
    FOnScopeChanged: TProc<string>;
    FOnLibraryChanged: TProc<Boolean>;
    FOnResolutionChanged: TProc<Double>;
    FOnRenameSubsystems: TProc;
    FOnOpenUnit: TProc<string>;
    FOnOpenLocation: TProc<string, Integer, Integer>;
    FOnUnitRelations: TProc<string>;
    function NewSheet(const ACaption: string): TTabSheet;
    function NewList(AParent: TWinControl): TListView;
    function NewTree(AParent: TWinControl): TTreeView;
    function AddColumn(AList: TListView; const ACaption: string; AWidth: Integer): TListColumn;
    function CanFill(AControl: TWinControl): Boolean;
    function UnitCaption(AUnit: Integer): string;
    function RoleCaption(const ARole: string): string;
    function LinkCaption(const ALink: TAtlasArchLink): string;
    function LocationCaption(const ALink: TAtlasArchLink): string;
    function AddLink(const ALink: TAtlasArchLink): Integer;
    procedure FillScope;
    procedure FillAll;
    procedure FillCentral;
    procedure FillSubsystems;
    procedure FillCycles;
    procedure FillCrossLinks;
    procedure FillComparison;
    function ChangeCaption(AKind: TAtlasArchChangeKind; const AChange: TAtlasArchChange): string;
    procedure UpdateStatus;
    procedure UpdateInfo;
    procedure UpdateAssignment;
    procedure AssignmentPaint(Sender: TObject);
    procedure ExplainClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveStateClick(Sender: TObject);
    procedure CompareClick(Sender: TObject);
    procedure ClearCompareClick(Sender: TObject);
    procedure ChangesClick(Sender: TObject);
    procedure ScopeChange(Sender: TObject);
    procedure LibraryClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure NamesClick(Sender: TObject);
    procedure ImplementationClick(Sender: TObject);
    procedure MarkCyclesClick(Sender: TObject);
    procedure SubsystemsClick(Sender: TObject);
    procedure SubsystemItemClick(Sender: TObject);
    procedure FoundationEdgesClick(Sender: TObject);
    procedure ShowAllClick(Sender: TObject);
    procedure RenameSubsystemsClick(Sender: TObject);
    procedure CentralColumnClick(Sender: TObject; Column: TListColumn);
    procedure CentralDblClick(Sender: TObject);
    procedure CrossDblClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MapSelect;
    procedure MapOpen(AUnit: Integer);
    procedure SetScopeValue(const AValue: string);
    function GetIncludeLibrary: Boolean;
    procedure SetIncludeLibrary(AValue: Boolean);
    function GetResolutionValue: Double;
    procedure SetResolutionValue(AValue: Double);
    function GetShowResolution: Boolean;
    procedure SetShowResolution(AValue: Boolean);
    /// <summary>„γ = 1,0 · 6 Teilsysteme“; die Zahl nur, wenn die Karte mit diesem Wert gerechnet ist.</summary>
    procedure UpdateResolutionInfo(AValue: Double);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Neue Daten zeigen; Filter, Sortierung, Reiter und Auswahl bleiben.</summary>
    procedure SetModel(const AModel: TAtlasArchitectureModel);
    /// <summary>Statt der Daten ein Hinweis in der Statuszeile (kein Projekt, kein Server, Rechnen läuft);
    /// AKeep: bisherige Daten stehen lassen (z. B. während neu gerechnet wird).</summary>
    procedure SetMessage(const AText: string; AKeep: Boolean);
    /// <summary>Reiter „Zentrale Units“ nach „gesamt abhängig“ absteigend (#554, teuerste Units).</summary>
    procedure ShowCostRanking;
    /// <summary>Unit öffnen (OnOpenUnit mit absolutem Pfad).</summary>
    procedure OpenUnit(AUnit: Integer);
    /// <summary>uses-Eintrag öffnen (OnOpenLocation), ohne Fundstelle die Unit, in der er steht.</summary>
    procedure OpenLink(const ALink: TAtlasArchLink);
    /// <summary>Menü „Teilsysteme ▾“ neu aufbauen: je Teilsystem ein Haken, dazu „Alle einblenden“ und mit
    /// OnRenameSubsystems „Teilsysteme neu benennen“ (#1367).</summary>
    procedure FillSubsystemsMenu;
    /// <summary>Zeile eines Teilsystems in Menü und Reiter: Name, Units, Zusammenhalt (Fundament ohne, #1365).
    /// </summary>
    function SubsystemCaption(ASubsystem: Integer): string;
    /// <summary>Zeile für Zeile der Text einer Liste bzw. eines Baums (für Tests und Bildschirmleser).</summary>
    function CentralText: TArray<string>;
    function SubsystemText: TArray<string>;
    function CycleText: TArray<string>;
    function CrossLinkText: TArray<string>;
    function ComparisonText: TArray<string>;
    property Model: TAtlasArchitectureModel read FModel;
    property HasModel: Boolean read FHasModel;
    property Map: TAtlasArchitectureMap read FMap;
    property Pages: TPageControl read FPages;
    property RefreshButton: TButton read FRefresh;
    property SaveButton: TButton read FSave;
    property SaveStateButton: TButton read FSaveState;
    property CompareButton: TButton read FCompare;
    property ClearCompareButton: TButton read FClearCompare;
    property ChangesCheck: TCheckBox read FChanges;
    property ComparisonTree: TTreeView read FComparison;
    property ComparisonInfo: TLabel read FCompareInfo;
    property LibraryCheck: TCheckBox read FLibrary;
    property Filter: TEdit read FFilter;
    property CentralList: TListView read FCentral;
    property SubsystemTree: TTreeView read FSubsystems;
    property CycleTree: TTreeView read FCycles;
    property CrossLinkList: TListView read FCrossLinks;
    property StatusLabel: TLabel read FStatus;
    property InfoLabel: TLabel read FInfo;
    /// <summary>Bereich mit der Erklärung der Zuordnung links neben dem Diagramm (scrollbar).</summary>
    property AssignmentBox: TScrollBox read FAssignmentBox;
    property ExplainButton: TButton read FExplainButton;
    property ExplanationLabel: TLabel read FExplanation;
    property FitButton: TButton read FFit;
    property NamesCheck: TCheckBox read FNames;
    property ImplementationCheck: TCheckBox read FImplementation;
    property MarkCyclesCheck: TCheckBox read FMarkCycles;
    property SubsystemsMenu: TPopupMenu read FSubsystemsMenu;
    property ScopeValue: string read FScopeValue write SetScopeValue;
    property IncludeLibrary: Boolean read GetIncludeLibrary write SetIncludeLibrary;
    /// <summary>Feinheit γ des Reglers (#1366); Setzen meldet nichts.</summary>
    property ResolutionValue: Double read GetResolutionValue write SetResolutionValue;
    /// <summary>Regler „Feinheit“ zeigen (architecture.grouping.showResolutionSlider).</summary>
    property ShowResolution: Boolean read GetShowResolution write SetShowResolution;
    property ResolutionSlider: TAtlasResolutionSlider read FResolution;
    property ResolutionInfo: TLabel read FResolutionInfo;
    property SortColumn: TAtlasArchColumn read FSortColumn;
    property SortDescending: Boolean read FSortDescending;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    /// <summary>Gewählte Zieldatei (.html oder .md).</summary>
    property OnSave: TProc<string> read FOnSave write FOnSave;
    /// <summary>Gewählte Zieldatei für den Stand (.json, #1121).</summary>
    property OnSaveState: TProc<string> read FOnSaveState write FOnSaveState;
    /// <summary>Gewählter gespeicherter Stand (.json), mit dem verglichen werden soll.</summary>
    property OnCompare: TProc<string> read FOnCompare write FOnCompare;
    /// <summary>Vergleich aufheben (auch den mit architecture.baseline).</summary>
    property OnClearComparison: TProc read FOnClearComparison write FOnClearComparison;
    property OnScopeChanged: TProc<string> read FOnScopeChanged write FOnScopeChanged;
    property OnLibraryChanged: TProc<Boolean> read FOnLibraryChanged write FOnLibraryChanged;
    /// <summary>Regler losgelassen, Doppelklick oder Taste: neue Feinheit (#1366).</summary>
    property OnResolutionChanged: TProc<Double> read FOnResolutionChanged write FOnResolutionChanged;
    /// <summary>„Teilsysteme neu benennen“ im Menü „Teilsysteme ▾“ (#1367): einmal ohne Angleichung rechnen.
    /// </summary>
    property OnRenameSubsystems: TProc read FOnRenameSubsystems write FOnRenameSubsystems;
    property OnOpenUnit: TProc<string> read FOnOpenUnit write FOnOpenUnit;
    /// <summary>Absoluter Pfad, Zeile und Spalte ab 1.</summary>
    property OnOpenLocation: TProc<string, Integer, Integer> read FOnOpenLocation write FOnOpenLocation;
    /// <summary>Strg+Doppelklick bzw. Strg+Enter auf eine Unit: Fenster „Unit-Beziehungen“ (#593), absoluter Pfad.
    /// </summary>
    property OnUnitRelations: TProc<string> read FOnUnitRelations write FOnUnitRelations;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.Types,
  Vcl.Dialogs,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Architecture.Assignment,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings;

{$R *.dfm}

const
  ScopeValues: array[0..1] of string = ('projectGroup', 'project');
  /// <summary>Spalten der Tabelle „Zentrale Units“ in Reihenfolge der Anzeige.</summary>
  CentralColumns: array[0..5] of TAtlasArchColumn = (TAtlasArchColumn.Name, TAtlasArchColumn.Subsystem,
    TAtlasArchColumn.Direct, TAtlasArchColumn.Total, TAtlasArchColumn.Uses_, TAtlasArchColumn.Role);

{ TAtlasArchitectureFrame }

constructor TAtlasArchitectureFrame.Create(AOwner: TComponent);
var
  Sheet: TTabSheet;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FScopeValue := ScopeValues[0];
  FSortColumn := TAtlasArchColumn.Total;
  FSortDescending := True;

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
  FRefresh.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRefresh);
  FRefresh.Width := 110;
  FRefresh.OnClick := RefreshClick;

  FSave := TButton.Create(Self);
  FSave.Parent := FTop;
  FSave.Align := alLeft;
  FSave.AlignWithMargins := True;
  FSave.Left := FRefresh.Left + FRefresh.Width + 1;
  FSave.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureSaveReport);
  FSave.Width := 130;
  FSave.OnClick := SaveClick;

  FSaveState := TButton.Create(Self);
  FSaveState.Parent := FTop;
  FSaveState.Align := alLeft;
  FSaveState.AlignWithMargins := True;
  FSaveState.Left := FSave.Left + FSave.Width + 1;
  FSaveState.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureSaveState);
  FSaveState.Width := 120;
  FSaveState.OnClick := SaveStateClick;

  FCompare := TButton.Create(Self);
  FCompare.Parent := FTop;
  FCompare.Align := alLeft;
  FCompare.AlignWithMargins := True;
  FCompare.Left := FSaveState.Left + FSaveState.Width + 1;
  FCompare.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCompare);
  FCompare.Width := 130;
  FCompare.OnClick := CompareClick;

  FScope := TComboBox.Create(Self);
  FScope.Parent := FTop;
  FScope.Align := alLeft;
  FScope.AlignWithMargins := True;
  FScope.Left := FCompare.Left + FCompare.Width + 1;
  FScope.Style := csDropDownList;
  FScope.Width := 130;
  FScope.OnChange := ScopeChange;

  FLibrary := TCheckBox.Create(Self);
  FLibrary.Parent := FTop;
  FLibrary.Align := alLeft;
  FLibrary.AlignWithMargins := True;
  FLibrary.Left := FScope.Left + FScope.Width + 1;
  FLibrary.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureLibrary);
  FLibrary.Width := 120;
  FLibrary.OnClick := LibraryClick;

  FResolutionCaption := TLabel.Create(Self);
  FResolutionCaption.Parent := FTop;
  FResolutionCaption.Align := alLeft;
  FResolutionCaption.AlignWithMargins := True;
  FResolutionCaption.Left := FLibrary.Left + FLibrary.Width + 1;
  FResolutionCaption.Layout := tlCenter;
  FResolutionCaption.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureResolutionCaption);
  FResolutionCaption.ShowAccelChar := False;

  FResolution := TAtlasResolutionSlider.Create(Self);
  FResolution.Parent := FTop;
  FResolution.Align := alLeft;
  FResolution.AlignWithMargins := True;
  FResolution.Left := FResolutionCaption.Left + FResolutionCaption.Width + 1;
  FResolution.Width := 140;
  FResolution.Hint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureResolutionHint);
  FResolution.ShowHint := True;
  FResolution.OnTracking :=
    procedure(AValue: Double)
    begin
      UpdateResolutionInfo(AValue);
    end;
  FResolution.OnChange :=
    procedure(AValue: Double)
    begin
      UpdateResolutionInfo(AValue);
      if Assigned(FOnResolutionChanged) then
      begin
        FOnResolutionChanged(AValue);
      end;
    end;

  FResolutionInfo := TLabel.Create(Self);
  FResolutionInfo.Parent := FTop;
  FResolutionInfo.Align := alLeft;
  FResolutionInfo.AlignWithMargins := True;
  FResolutionInfo.Left := FResolution.Left + FResolution.Width + 1;
  FResolutionInfo.Layout := tlCenter;
  FResolutionInfo.ShowAccelChar := False;
  UpdateResolutionInfo(FResolution.Value);

  FFilter := TEdit.Create(Self);
  FFilter.Parent := FTop;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFilterHint);
  FFilter.OnChange := FilterChange;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;
  FStatus.Caption := '';

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;

  Sheet := NewSheet(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureTabOverview));
  FInfo := TLabel.Create(Self);
  FInfo.Parent := Sheet;
  FInfo.Align := alBottom;
  FInfo.AlignWithMargins := True;
  FInfo.ShowAccelChar := False;
  FInfo.EllipsisPosition := epEndEllipsis;
  FInfo.Font.Color := clGrayText;
  FInfo.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMapHint);
  // Erklärung der Zuordnung links neben dem Diagramm (scrollbar, Breite über die Ziehleiste); unten verdrängte sie
  // bei vielen Teilsystemen das Diagramm.
  FAssignmentBox := TScrollBox.Create(Self);
  FAssignmentBox.Parent := Sheet;
  FAssignmentBox.Align := alLeft;
  FAssignmentBox.BorderStyle := bsNone;
  FAssignmentBox.VertScrollBar.Tracking := True;
  FAssignmentBox.Visible := False;
  FAssignmentSplit := TSplitter.Create(Self);
  FAssignmentSplit.Parent := Sheet;
  FAssignmentSplit.Align := alLeft;
  FAssignmentSplit.Left := FAssignmentBox.Left + FAssignmentBox.Width + 1;
  FAssignmentSplit.Visible := False;
  FAssignment := TPaintBox.Create(Self);
  FAssignment.Parent := FAssignmentBox;
  FAssignment.SetBounds(0, 0, 10, 10);
  FAssignment.OnPaint := AssignmentPaint;
  FMapBar := TPanel.Create(Self);
  FMapBar.Parent := Sheet;
  FMapBar.Align := alTop;
  FMapBar.BevelOuter := bvNone;
  FMapBar.ShowCaption := False;
  FMapBar.AutoSize := True;
  FFit := TButton.Create(Self);
  FFit.Parent := FMapBar;
  FFit.Align := alLeft;
  FFit.AlignWithMargins := True;
  FFit.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFit);
  FFit.Width := 90;
  FFit.OnClick := FitClick;
  FNames := TCheckBox.Create(Self);
  FNames.Parent := FMapBar;
  FNames.Align := alLeft;
  FNames.AlignWithMargins := True;
  FNames.Left := FFit.Left + FFit.Width + 1;
  FNames.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNames);
  FNames.Width := 120;
  FNames.Checked := True;
  FNames.OnClick := NamesClick;
  FImplementation := TCheckBox.Create(Self);
  FImplementation.Parent := FMapBar;
  FImplementation.Align := alLeft;
  FImplementation.AlignWithMargins := True;
  FImplementation.Left := FNames.Left + FNames.Width + 1;
  FImplementation.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureImplementation);
  FImplementation.Width := 140;
  FImplementation.Checked := True;
  FImplementation.OnClick := ImplementationClick;
  FMarkCycles := TCheckBox.Create(Self);
  FMarkCycles.Parent := FMapBar;
  FMarkCycles.Align := alLeft;
  FMarkCycles.AlignWithMargins := True;
  FMarkCycles.Left := FImplementation.Left + FImplementation.Width + 1;
  FMarkCycles.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMarkCycles);
  FMarkCycles.Width := 130;
  FMarkCycles.OnClick := MarkCyclesClick;
  FChanges := TCheckBox.Create(Self);
  FChanges.Parent := FMapBar;
  FChanges.Align := alLeft;
  FChanges.AlignWithMargins := True;
  FChanges.Left := FMarkCycles.Left + FMarkCycles.Width + 1;
  FChanges.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureShowChanges);
  FChanges.Width := 150;
  FChanges.Checked := True;
  FChanges.Enabled := False;
  FChanges.OnClick := ChangesClick;
  FSubsystemsButton := TButton.Create(Self);
  FSubsystemsButton.Parent := FMapBar;
  FSubsystemsButton.Align := alLeft;
  FSubsystemsButton.AlignWithMargins := True;
  FSubsystemsButton.Left := FChanges.Left + FChanges.Width + 1;
  FSubsystemsButton.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureSubsystemsButton);
  FSubsystemsButton.Width := 110;
  FSubsystemsButton.OnClick := SubsystemsClick;
  FSubsystemsMenu := TPopupMenu.Create(Self);
  FMap := TAtlasArchitectureMap.Create(Self);
  FMap.Parent := Sheet;
  FMap.Align := alClient;
  FMap.OnSelect :=
    procedure(AUnit: Integer)
    begin
      MapSelect;
    end;
  FMap.OnOpen :=
    procedure(AUnit: Integer)
    begin
      MapOpen(AUnit);
    end;
  FMap.State.OnPathChanged :=
    procedure
    begin
      UpdateInfo;
    end;

  Sheet := NewSheet(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureTabCentral));
  FCentral := NewList(Sheet);
  FCentral.ColumnClick := True;
  FCentral.OnColumnClick := CentralColumnClick;
  FCentral.OnDblClick := CentralDblClick;
  AddColumn(FCentral, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColUnit), 220);
  AddColumn(FCentral, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColSubsystem), 120);
  AddColumn(FCentral, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColDirect), 100);
  AddColumn(FCentral, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColTotal), 100);
  AddColumn(FCentral, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColUses), 80);
  AddColumn(FCentral, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColRole), 100);

  Sheet := NewSheet(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureTabSubsystems));
  // Fragezeichen mit der Erklärung, wie die Teilsysteme entstehen (#1368); nur mit Zuordnung vom Server.
  FSubsystemsBar := TPanel.Create(Self);
  FSubsystemsBar.Parent := Sheet;
  FSubsystemsBar.Align := alTop;
  FSubsystemsBar.BevelOuter := bvNone;
  FSubsystemsBar.ShowCaption := False;
  FSubsystemsBar.AutoSize := True;
  FSubsystemsBar.Visible := False;
  FExplainButton := TButton.Create(Self);
  FExplainButton.Parent := FSubsystemsBar;
  FExplainButton.Align := alLeft;
  FExplainButton.AlignWithMargins := True;
  FExplainButton.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainButton);
  FExplainButton.Hint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  FExplainButton.ShowHint := True;
  FExplainButton.Width := 28;
  FExplainButton.OnClick := ExplainClick;
  FExplanation := TLabel.Create(Self);
  FExplanation.Parent := FSubsystemsBar;
  FExplanation.Align := alClient;
  FExplanation.AlignWithMargins := True;
  FExplanation.ShowAccelChar := False;
  FExplanation.WordWrap := True;
  FExplanation.Font.Color := clGrayText;
  FExplanation.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  FSubsystems := NewTree(Sheet);

  Sheet := NewSheet(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureTabCycles));
  FCycles := NewTree(Sheet);

  Sheet := NewSheet(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureTabCrossLinks));
  FCrossLinks := NewList(Sheet);
  FCrossLinks.OnDblClick := CrossDblClick;
  AddColumn(FCrossLinks, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColFrom), 200);
  AddColumn(FCrossLinks, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColTo), 200);
  AddColumn(FCrossLinks, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColSubsystem), 180);
  AddColumn(FCrossLinks, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColReason), 160);
  AddColumn(FCrossLinks, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureColLocation), 200);

  Sheet := NewSheet(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureTabComparison));
  FCompareBar := TPanel.Create(Self);
  FCompareBar.Parent := Sheet;
  FCompareBar.Align := alTop;
  FCompareBar.BevelOuter := bvNone;
  FCompareBar.ShowCaption := False;
  FCompareBar.AutoSize := True;
  FClearCompare := TButton.Create(Self);
  FClearCompare.Parent := FCompareBar;
  FClearCompare.Align := alRight;
  FClearCompare.AlignWithMargins := True;
  FClearCompare.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureClearComparison);
  FClearCompare.Width := 140;
  FClearCompare.Enabled := False;
  FClearCompare.OnClick := ClearCompareClick;
  FCompareInfo := TLabel.Create(Self);
  FCompareInfo.Parent := FCompareBar;
  FCompareInfo.Align := alClient;
  FCompareInfo.AlignWithMargins := True;
  FCompareInfo.Layout := tlCenter;
  FCompareInfo.ShowAccelChar := False;
  FCompareInfo.EllipsisPosition := epEndEllipsis;
  FCompareInfo.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoComparison);
  FComparison := NewTree(Sheet);
end;

function TAtlasArchitectureFrame.NewSheet(const ACaption: string): TTabSheet;
begin
  Result := TTabSheet.Create(Self);
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (CreateWnd zeigt ihn).
  Result.TabVisible := False;
  Result.PageControl := FPages;
  Result.Caption := ACaption;
  FSheets := FSheets + [Result];
end;

function TAtlasArchitectureFrame.NewList(AParent: TWinControl): TListView;
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

function TAtlasArchitectureFrame.NewTree(AParent: TWinControl): TTreeView;
begin
  Result := TTreeView.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.HideSelection := False;
  Result.OnDblClick := TreeDblClick;
  Result.OnKeyDown := TreeKeyDown;
end;

function TAtlasArchitectureFrame.AddColumn(AList: TListView; const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := AList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

procedure TAtlasArchitectureFrame.CreateWnd;
var
  Sheet: TTabSheet;
begin
  inherited CreateWnd;
  for Sheet in FSheets do
  begin
    Sheet.TabVisible := True;
  end;
  if (FPages.ActivePage = nil) and (Length(FSheets) > 0) then
  begin
    FPages.ActivePage := FSheets[0];
  end;
  // Combo, Listen und Bäume halten ihre Einträge im Fenster: erst jetzt füllen.
  FillScope;
  FillAll;
end;

function TAtlasArchitectureFrame.CanFill(AControl: TWinControl): Boolean;
begin
  Result := AControl.HandleAllocated or (GetParentForm(AControl) <> nil);
end;

procedure TAtlasArchitectureFrame.FillScope;
begin
  if not CanFill(FScope) then
  begin
    Exit;
  end;
  FUpdating := True;
  try
    FScope.Items.BeginUpdate;
    try
      FScope.Items.Clear;
      FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.ArchitectureScopeGroup));
      FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.ArchitectureScopeProject));
    finally
      FScope.Items.EndUpdate;
    end;
    if FScopeValue = ScopeValues[1] then
    begin
      FScope.ItemIndex := 1;
    end
    else
    begin
      FScope.ItemIndex := 0;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasArchitectureFrame.SetScopeValue(const AValue: string);
begin
  if AValue = ScopeValues[1] then
  begin
    FScopeValue := ScopeValues[1];
  end
  else
  begin
    FScopeValue := ScopeValues[0];
  end;
  FillScope;
end;

function TAtlasArchitectureFrame.GetIncludeLibrary: Boolean;
begin
  Result := FLibrary.Checked;
end;

procedure TAtlasArchitectureFrame.SetIncludeLibrary(AValue: Boolean);
begin
  FUpdating := True;
  try
    FLibrary.Checked := AValue;
  finally
    FUpdating := False;
  end;
end;

function TAtlasArchitectureFrame.GetResolutionValue: Double;
begin
  Result := FResolution.Value;
end;

procedure TAtlasArchitectureFrame.SetResolutionValue(AValue: Double);
begin
  FResolution.Value := AValue;
  UpdateResolutionInfo(FResolution.Value);
end;

function TAtlasArchitectureFrame.GetShowResolution: Boolean;
begin
  Result := FResolution.Visible;
end;

procedure TAtlasArchitectureFrame.SetShowResolution(AValue: Boolean);
begin
  FResolutionCaption.Visible := AValue;
  FResolution.Visible := AValue;
  FResolutionInfo.Visible := AValue;
end;

procedure TAtlasArchitectureFrame.UpdateResolutionInfo(AValue: Double);
var
  mText: string;
begin
  mText := TAtlasArchResolution.Text(AValue, FormatSettings);
  if FHasModel and TAtlasArchResolution.Same(FModel.Resolution, AValue) then
  begin
    FResolutionInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureResolutionInfo, [mText,
      FModel.SubsystemCount]);
  end
  else
  begin
    FResolutionInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureResolutionValue, [mText]);
  end;
end;

procedure TAtlasArchitectureFrame.SetModel(const AModel: TAtlasArchitectureModel);
begin
  FModel := AModel;
  FHasModel := True;
  FMessageText := '';
  FMap.SetModel(FModel);
  FMap.State.Filter := FFilter.Text;
  FillAll;
  UpdateResolutionInfo(FResolution.Value);
end;

procedure TAtlasArchitectureFrame.SetMessage(const AText: string; AKeep: Boolean);
begin
  FMessageText := AText;
  if not AKeep then
  begin
    FModel := Default(TAtlasArchitectureModel);
    FHasModel := False;
    FMap.SetModel(FModel);
    FillAll;
    UpdateResolutionInfo(FResolution.Value);
  end;
  UpdateStatus;
end;

function TAtlasArchitectureFrame.UnitCaption(AUnit: Integer): string;
begin
  if (AUnit >= 0) and (AUnit <= High(FModel.Units)) then
  begin
    Result := FModel.Units[AUnit].Name;
  end
  else
  begin
    Result := '';
  end;
end;

function TAtlasArchitectureFrame.RoleCaption(const ARole: string): string;
begin
  if ARole = 'foundation' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRoleFoundation);
  end
  else if ARole = 'hub' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRoleHub);
  end
  else
  begin
    Result := '';
  end;
end;

function TAtlasArchitectureFrame.LocationCaption(const ALink: TAtlasArchLink): string;
begin
  if (ALink.FileName = '') or (ALink.Line <= 0) then
  begin
    Exit('');
  end;
  Result := Format('%s:%d', [ALink.FileName, ALink.Line]);
end;

function TAtlasArchitectureFrame.LinkCaption(const ALink: TAtlasArchLink): string;
var
  Section, Location: string;
begin
  if ALink.Interface_ then
  begin
    Section := 'interface';
  end
  else
  begin
    Section := 'implementation';
  end;
  Location := LocationCaption(ALink);
  if Location <> '' then
  begin
    Section := Section + ', ' + Location;
  end;
  Result := Format('%s → %s (%s)', [UnitCaption(ALink.Source), UnitCaption(ALink.Target), Section]);
end;

function TAtlasArchitectureFrame.AddLink(const ALink: TAtlasArchLink): Integer;
begin
  FLinks := FLinks + [ALink];
  Result := Length(FLinks);
end;

procedure TAtlasArchitectureFrame.FillAll;
begin
  FLinks := nil;
  FSubsystemsBar.Visible := FModel.HasAssignment;
  FExplanation.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  FillCentral;
  FillSubsystems;
  FillCycles;
  FillCrossLinks;
  FillComparison;
  UpdateStatus;
  UpdateInfo;
end;

procedure TAtlasArchitectureFrame.FillCentral;
var
  Shown: TArray<Integer>;
  Member, Index: Integer;
  Item: TListItem;
  Data: TAtlasArchUnit;
begin
  if not CanFill(FCentral) then
  begin
    Exit;
  end;
  Shown := nil;
  for Member in FModel.Central do
  begin
    if FModel.Matches(Member, FFilter.Text) then
    begin
      Shown := Shown + [Member];
    end;
  end;
  FCentralRows := FModel.Sorted(Shown, FSortColumn, FSortDescending);
  FCentral.Items.BeginUpdate;
  try
    FCentral.Items.Clear;
    for Index := 0 to High(FCentralRows) do
    begin
      Data := FModel.Units[FCentralRows[Index]];
      Item := FCentral.Items.Add;
      Item.Caption := Data.Name;
      Item.SubItems.Add(FModel.SubsystemName(Data.Subsystem));
      Item.SubItems.Add(IntToStr(Data.Direct));
      Item.SubItems.Add(IntToStr(Data.Total));
      Item.SubItems.Add(IntToStr(Data.Uses_));
      Item.SubItems.Add(RoleCaption(Data.Role));
    end;
  finally
    FCentral.Items.EndUpdate;
  end;
end;

procedure TAtlasArchitectureFrame.FillSubsystems;
var
  Index, Member, Outlier: Integer;
  Subsystem: TAtlasArchSubsystem;
  Group, Node: TTreeNode;
  Line: string;
  Members: TArray<Integer>;
begin
  if not CanFill(FSubsystems) then
  begin
    Exit;
  end;
  FSubsystems.Items.BeginUpdate;
  try
    FSubsystems.Items.Clear;
    // Teile eines nachgeteilten Teilsystems (#1364) beieinander.
    for Index in FModel.LegendOrder do
    begin
      Subsystem := FModel.Subsystems[Index];
      Members := nil;
      for Member in Subsystem.Units do
      begin
        if FModel.Matches(Member, FFilter.Text) then
        begin
          Members := Members + [Member];
        end;
      end;
      if Length(Members) = 0 then
      begin
        Continue;
      end;
      Line := SubsystemCaption(Index);
      if Subsystem.Parent <> '' then
      begin
        Line := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemPart, [Line, Subsystem.Parent]);
      end;
      Group := FSubsystems.Items.Add(nil, Line);
      Group.Data := nil;
      // Regel des Fundaments (#1365) als erste Zeile.
      if Subsystem.Foundation then
      begin
        FSubsystems.Items.AddChild(Group,
          TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationRule)).Data := nil;
      end;
      for Member in FModel.Sorted(Members, TAtlasArchColumn.Total, True) do
      begin
        Line := FModel.Units[Member].Name;
        Outlier := FModel.OutlierOf(Member);
        if (Outlier >= 0) and (FModel.Outliers[Outlier].Reason = 'namespace') then
        begin
            Line := Line + ' — ' + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureOutlierNamespace,
            [FModel.SubsystemName(FModel.Outliers[Outlier].Suggested)]);
        end
        else if Outlier >= 0 then
        begin
            Line := Line + ' — ' + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureOutlierEdges,
            [FModel.SubsystemName(FModel.Outliers[Outlier].Suggested)]);
        end;
        // Knapp zugeordnet (#1368).
        if TAtlasArchitectureAssignment.CloseMark(FModel, Member) <> '' then
        begin
          Line := Line + ' — ' + TAtlasArchitectureAssignment.CloseMark(FModel, Member);
        end;
        Node := FSubsystems.Items.AddChild(Group, Line);
        // Unit: negative Zahl (−1 − Nummer), uses-Eintrag: positive (Nummer in FLinks + 1).
        Node.Data := Pointer(NativeInt(-1 - Member));
      end;
      // Kleine Teilsysteme aufgeklappt, große zu.
      Group.Expanded := Length(Members) <= 12;
    end;
  finally
    FSubsystems.Items.EndUpdate;
  end;
end;

procedure TAtlasArchitectureFrame.FillCycles;
var
  Cycle: TAtlasArchCycle;
  Link: TAtlasArchLink;
  Group, Node: TTreeNode;
  Line: string;
  Member: Integer;
  Hit: Boolean;
begin
  if not CanFill(FCycles) then
  begin
    Exit;
  end;
  FCycles.Items.BeginUpdate;
  try
    FCycles.Items.Clear;
    for Cycle in FModel.Cycles do
    begin
      Hit := False;
      for Member in Cycle.Units do
      begin
        Hit := Hit or FModel.Matches(Member, FFilter.Text);
      end;
      if not Hit then
      begin
        Continue;
      end;
      if Cycle.InterfaceOnly then
      begin
        Line := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleInterface);
      end
      else
      begin
        Line := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleImplementation);
      end;
      Group := FCycles.Items.Add(nil, Line + ': ' + FModel.CyclePath(Cycle));
      Group.Data := nil;
      for Link in Cycle.Edges do
      begin
        Node := FCycles.Items.AddChild(Group, LinkCaption(Link));
        Node.Data := Pointer(NativeInt(AddLink(Link)));
      end;
      Group.Expanded := True;
    end;
  finally
    FCycles.Items.EndUpdate;
  end;
end;

procedure TAtlasArchitectureFrame.FillCrossLinks;
var
  Index: Integer;
  Link: TAtlasArchLink;
  Item: TListItem;
  Reason: string;
begin
  if not CanFill(FCrossLinks) then
  begin
    Exit;
  end;
  FCrossRows := nil;
  FCrossLinks.Items.BeginUpdate;
  try
    FCrossLinks.Items.Clear;
    for Index := 0 to High(FModel.CrossLinks) do
    begin
      Link := FModel.CrossLinks[Index];
      if not (FModel.Matches(Link.Source, FFilter.Text) or FModel.Matches(Link.Target, FFilter.Text)) then
      begin
        Continue;
      end;
      FCrossRows := FCrossRows + [Index];
      if Link.Reason = 'rare' then
      begin
        Reason := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonRare);
      end
      else
      begin
        Reason := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonAgainst);
      end;
      Item := FCrossLinks.Items.Add;
      Item.Caption := UnitCaption(Link.Source);
      Item.SubItems.Add(UnitCaption(Link.Target));
      Item.SubItems.Add(FModel.SubsystemName(Link.FromSubsystem) + ' → ' + FModel.SubsystemName(Link.ToSubsystem));
      Item.SubItems.Add(Format('%s (%d:%d)', [Reason, Link.Forward, Link.Backward]));
      Item.SubItems.Add(LocationCaption(Link));
    end;
  finally
    FCrossLinks.Items.EndUpdate;
  end;
end;

function TAtlasArchitectureFrame.ChangeCaption(AKind: TAtlasArchChangeKind; const AChange: TAtlasArchChange): string;
var
  Detail: string;
begin
  Result := AChange.Text;
  case AKind of
    TAtlasArchChangeKind.NewCycles, TAtlasArchChangeKind.RemovedCycles:
      if AChange.Section = 'interface' then
      begin
        Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleInterface) + ': ' + Result;
      end
      else
      begin
        Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleImplementation) + ': ' + Result;
      end;
    TAtlasArchChangeKind.Growth:
      Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureGrowthLine,
        [AChange.Text, AChange.From, AChange.To_]);
    TAtlasArchChangeKind.Moves:
      Result := Result + ' (' + AChange.From + ' → ' + AChange.To_ + ')';
    TAtlasArchChangeKind.NewCrossLinks, TAtlasArchChangeKind.RemovedCrossLinks, TAtlasArchChangeKind.NewEdges,
    TAtlasArchChangeKind.RemovedEdges:
      begin
        Detail := AChange.From + ' → ' + AChange.To_;
        if AChange.Section <> '' then
        begin
          Detail := Detail + ', ' + AChange.Section;
        end;
        if AChange.Reason = 'rare' then
        begin
          Detail := Detail + ', ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonRare);
        end
        else if AChange.Reason <> '' then
        begin
          Detail := Detail + ', ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonAgainst);
        end;
        Result := Result + ' (' + Detail + ')';
      end;
    TAtlasArchChangeKind.NewUnits, TAtlasArchChangeKind.RemovedUnits: ;
  end;
end;

procedure TAtlasArchitectureFrame.FillComparison;
const
  Titles: array[TAtlasArchChangeKind] of TAtlasAnalysisTextId = (TAtlasAnalysisTextId.ArchitectureChangeNewCycles,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedCycles, TAtlasAnalysisTextId.ArchitectureChangeNewCrossLinks,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedCrossLinks, TAtlasAnalysisTextId.ArchitectureChangeNewEdges,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedEdges, TAtlasAnalysisTextId.ArchitectureChangeMoves,
    TAtlasAnalysisTextId.ArchitectureChangeGrowth, TAtlasAnalysisTextId.ArchitectureChangeNewUnits,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedUnits);
var
  Comparison: TAtlasArchComparison;
  Section: TAtlasArchChangeSection;
  Change: TAtlasArchChange;
  Shown: TArray<TAtlasArchChange>;
  Group, Node: TTreeNode;
  Info: string;
begin
  Comparison := FModel.Comparison;
  FChanges.Enabled := Comparison.Present;
  FMap.State.SetFlag(TAtlasArchMapFlag.ShowChanges, FChanges.Checked);
  FClearCompare.Enabled := FHasModel and ((Comparison.Baseline <> '') or (Comparison.Error <> ''));
  if Comparison.Error <> '' then
  begin
    Info := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonError, [Comparison.Error]);
  end
  else if Comparison.Present then
  begin
    Info := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonInfo,
      [ExtractFileName(Comparison.Baseline),
      Comparison.BaselineTitle, Comparison.BaselineUnits, Comparison.BaselineEdges, Comparison.Count]);
    if Length(Comparison.Failed) > 0 then
    begin
      Info := Info + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonFailed,
        [string.Join(', ', Comparison.Failed)]);
    end;
    // Verschiedene Feinheit (#1366): Teilsystemwechsel können allein daher kommen.
    if Comparison.ResolutionDiffers then
    begin
      Info := Info + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonResolution,
        [TAtlasArchResolution.Text(Comparison.BaselineResolution, FormatSettings),
        TAtlasArchResolution.Text(Comparison.Resolution, FormatSettings)]);
    end;
  end
  else
  begin
    Info := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoComparison);
  end;
  FCompareInfo.Caption := Info;
  FCompareInfo.Hint := Comparison.Baseline;
  FCompareInfo.ShowHint := Comparison.Baseline <> '';
  if not CanFill(FComparison) then
  begin
    Exit;
  end;
  FComparison.Items.BeginUpdate;
  try
    FComparison.Items.Clear;
    if not Comparison.Present then
    begin
      Exit;
    end;
    if Comparison.Count = 0 then
    begin
      FComparison.Items.Add(nil, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoChanges)).Data := nil;
      Exit;
    end;
    for Section in Comparison.Sections do
    begin
      // Der Filter wirkt wie in den anderen Listen auf die Namen; entfernte Units zählen mit ihrem Namen.
      Shown := nil;
      for Change in Section.Items do
      begin
        if (Trim(FFilter.Text) = '') or (Pos(LowerCase(Trim(FFilter.Text)), LowerCase(Change.Text)) > 0) or
          FModel.Matches(Change.Unit_, FFilter.Text) then
        begin
          Shown := Shown + [Change];
        end;
      end;
      if Length(Shown) = 0 then
      begin
        Continue;
      end;
      Group := FComparison.Items.Add(nil, TAtlasAnalysisStrings.Fmt(Titles[Section.Kind], [Length(Shown)]));
      Group.Data := nil;
      for Change in Shown do
      begin
        Node := FComparison.Items.AddChild(Group, ChangeCaption(Section.Kind, Change));
        // Wie im Baum der Teilsysteme: Unit als −1 − Nummer; entfernte Units haben keine.
        if Change.Unit_ >= 0 then
        begin
          Node.Data := Pointer(NativeInt(-1 - Change.Unit_));
        end
        else
        begin
          Node.Data := nil;
        end;
      end;
      Group.Expanded := Length(Shown) <= 20;
    end;
  finally
    FComparison.Items.EndUpdate;
  end;
end;

procedure TAtlasArchitectureFrame.UpdateStatus;
begin
  if FMessageText <> '' then
  begin
    FStatus.Caption := FMessageText;
  end
  else if not FHasModel then
  begin
    FStatus.Caption := '';
  end
  else if Length(FModel.Units) = 0 then
  begin
    FStatus.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureEmpty);
  end
  else
  begin
    // Index-Stand: Zahl der Änderungen; der obere Teil der Generation kennzeichnet nur den Index.
    FStatus.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatus, [Length(FModel.Units),
      Length(FModel.Subsystems), Length(FModel.Cycles), Length(FModel.CrossLinks),
      Integer(FModel.Generation and $7FFFFFFF), FModel.DurationMs]);
    if Length(FModel.Excludes) > 0 then
    begin
      FStatus.Caption := FStatus.Caption + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusExcludes,
        [string.Join(', ', FModel.Excludes)]);
    end;
    // Angleichung an einen vorigen Stand (#1367).
    if FModel.AlignedSource = 'baseline' then
    begin
      FStatus.Caption := FStatus.Caption + TAtlasAnalysisStrings.Fmt(
        TAtlasAnalysisTextId.ArchitectureStatusAlignedBaseline,
        [FModel.AlignedText]);
    end
    else if FModel.AlignedSource <> '' then
    begin
      FStatus.Caption := FStatus.Caption + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusAlignedLast,
        [FModel.AlignedText]);
    end;
    if FModel.Comparison.Present then
    begin
      FStatus.Caption := FStatus.Caption + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusComparison,
        [FModel.Comparison.Count]);
    end
    else if FModel.Comparison.Error <> '' then
    begin
      FStatus.Caption := FStatus.Caption + ' · ' + TAtlasAnalysisStrings.Fmt(
        TAtlasAnalysisTextId.ArchitectureComparisonError,
        [FModel.Comparison.Error]);
    end;
  end;
  FSave.Enabled := FHasModel and (Length(FModel.Units) > 0);
  FSaveState.Enabled := FSave.Enabled;
end;

procedure TAtlasArchitectureFrame.UpdateInfo;
var
  Item: TAtlasArchUnit;
begin
  UpdateAssignment;
  if Length(FMap.State.Path.Route) > 0 then
  begin
    // Fester Weg aus „Weg zwischen Symbolen“ (#1117).
    FInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureRoute, [Length(FMap.State.Path.Route),
      FModel.RouteText(FMap.State.Path.Route)]);
    Exit;
  end;
  if FMap.State.Path.From >= 0 then
  begin
    if FMap.State.Path.Found then
    begin
      FInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitecturePath, [Length(FMap.State.Path.Edges),
        FModel.PathText(FMap.State.Path.From, FMap.State.Path.Edges)]);
    end
    else
    begin
      FInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureNoPath, 
        [UnitCaption(FMap.State.Path.From), UnitCaption(FMap.State.Path.To_)]);
    end;
    Exit;
  end;
  if (FMap.State.Selected < 0) or (FMap.State.Selected > High(FModel.Units)) then
  begin
    FInfo.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMapHint);
    Exit;
  end;
  Item := FModel.Units[FMap.State.Selected];
  FInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureUnitInfo, [Item.Name,
    FModel.SubsystemName(Item.Subsystem), Item.Direct, Item.Total, Item.Uses_]);
end;

procedure TAtlasArchitectureFrame.UpdateAssignment;
var
  mBitmap: Vcl.Graphics.TBitmap;
  mSize: TSize;
begin
  // Steckbrief (#1368): nur mit gewählter Unit, ohne Weg und mit Zuordnung vom Server.
  if (FMap.State.Path.From >= 0) or (Length(FMap.State.Path.Route) > 0) or
    not TAtlasArchitectureAssignment.Available(FModel, FMap.State.Selected) then
  begin
    FAssignmentSplit.Visible := False;
    FAssignmentBox.Visible := False;
    Exit;
  end;
  // Messen ohne Fenster: auf einer Bitmap mit derselben Schrift.
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(Font);
    mSize := TAtlasArchitectureAssignment.Measure(mBitmap.Canvas, FModel, FMap.State.Selected, CurrentPPI);
  finally
    mBitmap.Free;
  end;
  FAssignment.SetBounds(0, 0, mSize.cx + 1, mSize.cy + 1);
  if not FAssignmentBox.Visible then
  begin
    // Breite nach dem Inhalt (Platz für die Bildlaufleiste), höchstens 40 % der Seite; danach gilt die Ziehleiste.
    FAssignmentBox.Width := Min(mSize.cx + GetSystemMetrics(SM_CXVSCROLL) + ScaleValue(8),
      Max(ScaleValue(120), FAssignmentBox.Parent.Width * 2 div 5));
    FAssignmentBox.Visible := True;
    FAssignmentSplit.Left := FAssignmentBox.Left + FAssignmentBox.Width + 1;
    FAssignmentSplit.Visible := True;
  end;
  FAssignmentBox.VertScrollBar.Position := 0;
  FAssignment.Invalidate;
end;

procedure TAtlasArchitectureFrame.AssignmentPaint(Sender: TObject);
var
  mColors: TAtlasColors;
  mSize: TSize;
begin
  if not TAtlasArchitectureAssignment.Available(FModel, FMap.State.Selected) then
  begin
    Exit;
  end;
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  FAssignment.Canvas.Font.Assign(Font);
  mSize := TAtlasArchitectureAssignment.Measure(FAssignment.Canvas, FModel, FMap.State.Selected, CurrentPPI);
  TAtlasArchitectureAssignment.Draw(FAssignment.Canvas, Rect(0, 0, Min(mSize.cx, FAssignment.Width), mSize.cy),
    FModel, FMap.State.Selected, CurrentPPI, mColors);
end;

procedure TAtlasArchitectureFrame.ExplainClick(Sender: TObject);
begin
  // Erneut: wieder nur der kurze Hinweis.
  if FExplanation.Caption = TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint) then
  begin
    FExplanation.Caption := TAtlasArchitectureAssignment.Explanation(FModel);
  end
  else
  begin
    FExplanation.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  end;
end;

procedure TAtlasArchitectureFrame.OpenUnit(AUnit: Integer);
var
  FileName: string;
begin
  if (AUnit < 0) or (AUnit > High(FModel.Units)) or (FModel.Units[AUnit].FileName = '') then
  begin
    Exit;
  end;
  FileName := FModel.FullPath(FModel.Units[AUnit].FileName);
  if (GetKeyState(VK_CONTROL) < 0) and Assigned(FOnUnitRelations) then
  begin
    FOnUnitRelations(FileName);
  end
  else if Assigned(FOnOpenUnit) then
  begin
    FOnOpenUnit(FileName);
  end;
end;

procedure TAtlasArchitectureFrame.OpenLink(const ALink: TAtlasArchLink);
begin
  if (ALink.FileName = '') or (ALink.Line <= 0) then
  begin
    OpenUnit(ALink.Source);
    Exit;
  end;
  if Assigned(FOnOpenLocation) then
  begin
    FOnOpenLocation(FModel.FullPath(ALink.FileName), ALink.Line, Max(1, ALink.Character));
  end;
end;

procedure TAtlasArchitectureFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
  begin
    FOnRefresh();
  end;
end;

procedure TAtlasArchitectureFrame.SaveClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Filter := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureSaveFilter);
    Dialog.DefaultExt := 'html';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if FModel.Title <> '' then
    begin
      Dialog.FileName := 'Architektur-' + FModel.Title + '.html';
    end;
    if Dialog.Execute and Assigned(FOnSave) then
    begin
      FOnSave(Dialog.FileName);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasArchitectureFrame.SaveStateClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Filter := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureStateFilter);
    Dialog.DefaultExt := 'json';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if FModel.Title <> '' then
    begin
      Dialog.FileName := 'Architektur-' + FModel.Title + '.json';
    end;
    if Dialog.Execute and Assigned(FOnSaveState) then
    begin
      FOnSaveState(Dialog.FileName);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasArchitectureFrame.CompareClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Filter := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureStateFilter);
    Dialog.DefaultExt := 'json';
    Dialog.Options := Dialog.Options + [ofFileMustExist, ofPathMustExist];
    if FModel.Comparison.Baseline <> '' then
    begin
      Dialog.FileName := FModel.Comparison.Baseline;
    end;
    if Dialog.Execute and Assigned(FOnCompare) then
    begin
      FOnCompare(Dialog.FileName);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasArchitectureFrame.ClearCompareClick(Sender: TObject);
begin
  if Assigned(FOnClearComparison) then
  begin
    FOnClearComparison();
  end;
end;

procedure TAtlasArchitectureFrame.ChangesClick(Sender: TObject);
begin
  FMap.State.SetFlag(TAtlasArchMapFlag.ShowChanges, FChanges.Checked);
end;

procedure TAtlasArchitectureFrame.ScopeChange(Sender: TObject);
begin
  if FUpdating or (FScope.ItemIndex < 0) or (FScope.ItemIndex > High(ScopeValues)) then
  begin
    Exit;
  end;
  FScopeValue := ScopeValues[FScope.ItemIndex];
  if Assigned(FOnScopeChanged) then
  begin
    FOnScopeChanged(FScopeValue);
  end;
end;

procedure TAtlasArchitectureFrame.LibraryClick(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  if Assigned(FOnLibraryChanged) then
  begin
    FOnLibraryChanged(FLibrary.Checked);
  end;
end;

procedure TAtlasArchitectureFrame.FilterChange(Sender: TObject);
begin
  FMap.State.Filter := FFilter.Text;
  FillCentral;
  FillSubsystems;
  FLinks := nil;
  FillCycles;
  FillCrossLinks;
  FillComparison;
end;

procedure TAtlasArchitectureFrame.FitClick(Sender: TObject);
begin
  FMap.FitView;
end;

procedure TAtlasArchitectureFrame.NamesClick(Sender: TObject);
begin
  FMap.State.SetFlag(TAtlasArchMapFlag.ShowNames, FNames.Checked);
end;

procedure TAtlasArchitectureFrame.ImplementationClick(Sender: TObject);
begin
  FMap.State.SetFlag(TAtlasArchMapFlag.ShowImplementation, FImplementation.Checked);
end;

procedure TAtlasArchitectureFrame.MarkCyclesClick(Sender: TObject);
begin
  FMap.State.SetFlag(TAtlasArchMapFlag.MarkCycles, FMarkCycles.Checked);
end;

procedure TAtlasArchitectureFrame.FillSubsystemsMenu;
var
  Index, mOther, mParts: Integer;
  Item: TMenuItem;
  mFamily, mCaption: string;
begin
  FSubsystemsMenu.Items.Clear;
  // Wie die Legende der HTML-Karte: die Teile eines nachgeteilten Teilsystems (#1364) eingerückt unter seinem
  // Namen.
  mFamily := '';
  for Index in FModel.LegendOrder do
  begin
    mCaption := SubsystemCaption(Index);
    if FModel.Subsystems[Index].Parent = '' then
    begin
      mFamily := '';
    end
    else
    begin
      if not SameText(FModel.Subsystems[Index].Parent, mFamily) then
      begin
        mFamily := FModel.Subsystems[Index].Parent;
        mParts := 0;
        for mOther := 0 to High(FModel.Subsystems) do
        begin
          if SameText(FModel.Subsystems[mOther].Parent, mFamily) then
          begin
            Inc(mParts);
          end;
        end;
        Item := TMenuItem.Create(FSubsystemsMenu);
        Item.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemFamily, [mFamily, mParts]);
        Item.Enabled := False;
        Item.Tag := -1;
        FSubsystemsMenu.Items.Add(Item);
      end;
      mCaption := '      ' + mCaption;
    end;
    Item := TMenuItem.Create(FSubsystemsMenu);
    Item.Caption := mCaption;
    Item.Tag := Index;
    Item.Checked := FMap.State.SubsystemVisible[Index];
    Item.OnClick := SubsystemItemClick;
    FSubsystemsMenu.Items.Add(Item);
  end;
  if FSubsystemsMenu.Items.Count = 0 then
  begin
    Exit;
  end;
  FSubsystemsMenu.Items.NewBottomLine;
  // Kanten zum Fundament (#1365) ein- und ausblenden.
  if FModel.HasFoundation then
  begin
    Item := TMenuItem.Create(FSubsystemsMenu);
    Item.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationEdges);
    Item.Checked := FMap.State.Has(TAtlasArchMapFlag.ShowFoundationEdges);
    Item.Tag := -1;
    Item.OnClick := FoundationEdgesClick;
    FSubsystemsMenu.Items.Add(Item);
  end;
  Item := TMenuItem.Create(FSubsystemsMenu);
  Item.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureShowAll);
  Item.OnClick := ShowAllClick;
  FSubsystemsMenu.Items.Add(Item);
  // Farben und Namen neu vergeben (#1367), nur wenn der Dienst es anbietet.
  if Assigned(FOnRenameSubsystems) then
  begin
    Item := TMenuItem.Create(FSubsystemsMenu);
    Item.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRenameSubsystems);
    Item.Hint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRenameHint);
    Item.Tag := -1;
    Item.OnClick := RenameSubsystemsClick;
    FSubsystemsMenu.Items.Add(Item);
  end;
end;

procedure TAtlasArchitectureFrame.RenameSubsystemsClick(Sender: TObject);
begin
  if Assigned(FOnRenameSubsystems) then
  begin
    FOnRenameSubsystems();
  end;
end;

procedure TAtlasArchitectureFrame.SubsystemsClick(Sender: TObject);
var
  Point: TPoint;
begin
  FillSubsystemsMenu;
  Point := FSubsystemsButton.ClientToScreen(System.Types.Point(0, FSubsystemsButton.Height));
  FSubsystemsMenu.Popup(Point.X, Point.Y);
end;

procedure TAtlasArchitectureFrame.FoundationEdgesClick(Sender: TObject);
var
  mItem: TMenuItem;
begin
  mItem := Sender as TMenuItem;
  FMap.State.SetFlag(TAtlasArchMapFlag.ShowFoundationEdges, not FMap.State.Has(TAtlasArchMapFlag.ShowFoundationEdges));
  mItem.Checked := FMap.State.Has(TAtlasArchMapFlag.ShowFoundationEdges);
end;

function TAtlasArchitectureFrame.SubsystemCaption(ASubsystem: Integer): string;
begin
  if FModel.Subsystems[ASubsystem].Foundation then
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureFoundationLine,
      [FModel.Subsystems[ASubsystem].Name,
      Length(FModel.Subsystems[ASubsystem].Units)]);
  end
  else
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemLine,
      [FModel.Subsystems[ASubsystem].Name,
      Length(FModel.Subsystems[ASubsystem].Units), Round(FModel.Subsystems[ASubsystem].Cohesion * 100)]);
  end;
end;

procedure TAtlasArchitectureFrame.SubsystemItemClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  Item := Sender as TMenuItem;
  FMap.State.SubsystemVisible[Item.Tag] := not FMap.State.SubsystemVisible[Item.Tag];
  Item.Checked := FMap.State.SubsystemVisible[Item.Tag];
  UpdateInfo;
end;

procedure TAtlasArchitectureFrame.ShowAllClick(Sender: TObject);
begin
  FMap.State.ShowAllSubsystems;
  UpdateInfo;
end;

procedure TAtlasArchitectureFrame.ShowCostRanking;
begin
  FSortColumn := TAtlasArchColumn.Total;
  FSortDescending := True;
  FPages.ActivePage := FCentral.Parent as TTabSheet;
  FillCentral;
end;

procedure TAtlasArchitectureFrame.CentralColumnClick(Sender: TObject; Column: TListColumn);
var
  Next: TAtlasArchColumn;
begin
  if (Column.Index < 0) or (Column.Index > High(CentralColumns)) then
  begin
    Exit;
  end;
  Next := CentralColumns[Column.Index];
  if Next = FSortColumn then
  begin
    FSortDescending := not FSortDescending;
  end
  else
  begin
    FSortColumn := Next;
    // Zahlen zuerst die größten, Text alphabetisch.
    FSortDescending := Next in [TAtlasArchColumn.Direct, TAtlasArchColumn.Total, TAtlasArchColumn.Uses_];
  end;
  FillCentral;
end;

procedure TAtlasArchitectureFrame.CentralDblClick(Sender: TObject);
begin
  if (FCentral.ItemIndex >= 0) and (FCentral.ItemIndex <= High(FCentralRows)) then
  begin
    OpenUnit(FCentralRows[FCentral.ItemIndex]);
  end;
end;

procedure TAtlasArchitectureFrame.CrossDblClick(Sender: TObject);
begin
  if (FCrossLinks.ItemIndex >= 0) and (FCrossLinks.ItemIndex <= High(FCrossRows)) then
  begin
    OpenLink(FModel.CrossLinks[FCrossRows[FCrossLinks.ItemIndex]]);
  end;
end;

procedure TAtlasArchitectureFrame.TreeDblClick(Sender: TObject);
var
  Node: TTreeNode;
  Value: NativeInt;
begin
  if not (Sender is TTreeView) then
  begin
    Exit;
  end;
  Node := TTreeView(Sender).Selected;
  if (Node = nil) or (Node.Data = nil) then
  begin
    Exit;
  end;
  Value := NativeInt(Node.Data);
  if Value < 0 then
  begin
    OpenUnit(-1 - Value);
  end
  else if Value <= Length(FLinks) then
  begin
    OpenLink(FLinks[Value - 1]);
  end;
end;

procedure TAtlasArchitectureFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then
  begin
    Exit;
  end;
  if Sender = FCentral then
  begin
    CentralDblClick(Sender);
  end
  else if Sender = FCrossLinks then
  begin
    CrossDblClick(Sender);
  end;
  Key := 0;
end;

procedure TAtlasArchitectureFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then
  begin
    Exit;
  end;
  TreeDblClick(Sender);
  Key := 0;
end;

procedure TAtlasArchitectureFrame.MapSelect;
begin
  UpdateInfo;
end;

procedure TAtlasArchitectureFrame.MapOpen(AUnit: Integer);
begin
  OpenUnit(AUnit);
end;

function TAtlasArchitectureFrame.CentralText: TArray<string>;
var
  Index, Column: Integer;
  Line: string;
begin
  Result := nil;
  for Index := 0 to FCentral.Items.Count - 1 do
  begin
    Line := FCentral.Items[Index].Caption;
    for Column := 0 to FCentral.Items[Index].SubItems.Count - 1 do
    begin
      Line := Line + #9 + FCentral.Items[Index].SubItems[Column];
    end;
    Result := Result + [Line];
  end;
end;

function TAtlasArchitectureFrame.SubsystemText: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to FSubsystems.Items.Count - 1 do
  begin
    Result := Result + [StringOfChar(' ', 2 * FSubsystems.Items[Index].Level) + FSubsystems.Items[Index].Text];
  end;
end;

function TAtlasArchitectureFrame.CycleText: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to FCycles.Items.Count - 1 do
  begin
    Result := Result + [StringOfChar(' ', 2 * FCycles.Items[Index].Level) + FCycles.Items[Index].Text];
  end;
end;

function TAtlasArchitectureFrame.ComparisonText: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to FComparison.Items.Count - 1 do
  begin
    Result := Result + [StringOfChar(' ', 2 * FComparison.Items[Index].Level) + FComparison.Items[Index].Text];
  end;
end;

function TAtlasArchitectureFrame.CrossLinkText: TArray<string>;
var
  Index, Column: Integer;
  Line: string;
begin
  Result := nil;
  for Index := 0 to FCrossLinks.Items.Count - 1 do
  begin
    Line := FCrossLinks.Items[Index].Caption;
    for Column := 0 to FCrossLinks.Items[Index].SubItems.Count - 1 do
    begin
      Line := Line + #9 + FCrossLinks.Items[Index].SubItems[Column];
    end;
    Result := Result + [Line];
  end;
end;

end.
