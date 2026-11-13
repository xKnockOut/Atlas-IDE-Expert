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
// Die Steuerelemente stehen in Parts, der Text der Listen kommt über ListText;
// aufgebaut und gefüllt wird in Routinen dieser Unit, die Ereignisse fängt
// TEvents.

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
  /// <summary>Listen und Bäume des Frames, deren Text TAtlasArchitectureFrame.ListText liefert.</summary>
  TAtlasArchFrameList = (Central, Subsystems, Cycles, CrossLinks, Comparison);

  /// <summary>Sortierung der Tabelle „Zentrale Units“.</summary>
  TAtlasArchSort = record
    Column: TAtlasArchColumn;
    Descending: Boolean;
  end;

  TAtlasArchitectureFrame = class(TFrame)
  public type
    /// <summary>Steuerelemente des Frames (für die IDE-Schicht, Tests und Bildschirmleser).</summary>
    TParts = record
      Top: TFlowPanel;
      Refresh: TButton;
      Save: TButton;
      SaveState: TButton;
      Compare: TButton;
      Scope: TComboBox;
      LibraryUnits: TCheckBox;
      ResolutionCaption: TLabel;
      Resolution: TAtlasResolutionSlider;
      ResolutionInfo: TLabel;
      Filter: TEdit;
      Pages: TPageControl;
      /// <summary>Reiter in Reihenfolge; CreateWnd hängt sie ein (das braucht das Fenster des PageControls).
      /// </summary>
      Sheets: TArray<TTabSheet>;
      MapBar: TPanel;
      Fit: TButton;
      Names: TCheckBox;
      ImplementationUses: TCheckBox;
      MarkCycles: TCheckBox;
      Changes: TCheckBox;
      SubsystemsButton: TButton;
      SubsystemsMenu: TPopupMenu;
      Map: TAtlasArchitectureMap;
      Info: TLabel;
      /// <summary>Zuordnung der gewählten Unit (#1368), links neben der Karte.</summary>
      Assignment: TPaintBox;
      /// <summary>Bereich mit der Erklärung der Zuordnung links neben dem Diagramm (scrollbar).</summary>
      AssignmentBox: TScrollBox;
      AssignmentSplit: TSplitter;
      SubsystemsBar: TPanel;
      ExplainButton: TButton;
      Explanation: TLabel;
      Central: TListView;
      Subsystems: TTreeView;
      Cycles: TTreeView;
      CrossLinks: TListView;
      CompareBar: TPanel;
      CompareInfo: TLabel;
      ClearCompare: TButton;
      Comparison: TTreeView;
      Status: TLabel;
    end;
  private type
    /// <summary>Rückrufe an die IDE-Schicht.</summary>
    THandlers = record
      OnRefresh: TProc;
      OnSave: TProc<string>;
      OnSaveState: TProc<string>;
      OnCompare: TProc<string>;
      OnClearComparison: TProc;
      OnScopeChanged: TProc<string>;
      OnLibraryChanged: TProc<Boolean>;
      OnResolutionChanged: TProc<Double>;
      OnRenameSubsystems: TProc;
      OnOpenUnit: TProc<string>;
      OnOpenLocation: TProc<string, Integer, Integer>;
      OnUnitRelations: TProc<string>;
    end;

    /// <summary>Ereignisse der Steuerelemente; gehört dem Frame.</summary>
    TEvents = class(TComponent)
    private
      FFrame: TAtlasArchitectureFrame;
    public
      constructor Create(AFrame: TAtlasArchitectureFrame); reintroduce;
      procedure RefreshClick(Sender: TObject);
      procedure SaveClick(Sender: TObject);
      procedure SaveStateClick(Sender: TObject);
      procedure CompareClick(Sender: TObject);
      procedure ClearCompareClick(Sender: TObject);
      procedure ScopeChange(Sender: TObject);
      procedure LibraryClick(Sender: TObject);
      procedure FilterChange(Sender: TObject);
      procedure FitClick(Sender: TObject);
      /// <summary>Schalter der Karte; Tag des Kästchens = Ord(TAtlasArchMapFlag).</summary>
      procedure FlagClick(Sender: TObject);
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
      procedure AssignmentPaint(Sender: TObject);
      procedure ExplainClick(Sender: TObject);
    end;

    /// <summary>Gezeigte Daten, Einstellungen und Zeilen der Listen.</summary>
    TState = record
      Model: TAtlasArchitectureModel;
      HasModel: Boolean;
      MessageText: string;
      /// <summary>'projectGroup' oder 'project'; gilt auch ohne Fenster.</summary>
      ScopeValue: string;
      IncludeLibrary: Boolean;
      ShowResolution: Boolean;
      Updating: Boolean;
      Sort: TAtlasArchSort;
      /// <summary>Gezeigte Zeilen der Tabelle „Zentrale Units“ (Nummern der Units).</summary>
      CentralRows: TArray<Integer>;
      /// <summary>uses-Einträge der Bäume und der Querverbindungen; Data eines Knotens = Nummer + 1.</summary>
      Links: TArray<TAtlasArchLink>;
      CrossRows: TArray<Integer>;
      Events: TEvents;
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FState: TState;
    procedure SetScopeValue(const AValue: string);
    procedure SetIncludeLibrary(AValue: Boolean);
    function GetResolutionValue: Double;
    procedure SetResolutionValue(AValue: Double);
    procedure SetShowResolution(AValue: Boolean);
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
    /// <summary>Zeile für Zeile der Text einer Liste bzw. eines Baums (für Tests und Bildschirmleser).</summary>
    function ListText(AList: TAtlasArchFrameList): TArray<string>;
    property Model: TAtlasArchitectureModel read FState.Model;
    property HasModel: Boolean read FState.HasModel;
    property Map: TAtlasArchitectureMap read FParts.Map;
    property Parts: TParts read FParts;
    property ScopeValue: string read FState.ScopeValue write SetScopeValue;
    property IncludeLibrary: Boolean read FState.IncludeLibrary write SetIncludeLibrary;
    /// <summary>Feinheit γ des Reglers (#1366); Setzen meldet nichts.</summary>
    property ResolutionValue: Double read GetResolutionValue write SetResolutionValue;
    /// <summary>Regler „Feinheit“ zeigen (architecture.grouping.showResolutionSlider).</summary>
    property ShowResolution: Boolean read FState.ShowResolution write SetShowResolution;
    property Sort: TAtlasArchSort read FState.Sort;
    property OnRefresh: TProc read FHandlers.OnRefresh write FHandlers.OnRefresh;
    /// <summary>Gewählte Zieldatei (.html oder .md).</summary>
    property OnSave: TProc<string> read FHandlers.OnSave write FHandlers.OnSave;
    /// <summary>Gewählte Zieldatei für den Stand (.json, #1121).</summary>
    property OnSaveState: TProc<string> read FHandlers.OnSaveState write FHandlers.OnSaveState;
    /// <summary>Gewählter gespeicherter Stand (.json), mit dem verglichen werden soll.</summary>
    property OnCompare: TProc<string> read FHandlers.OnCompare write FHandlers.OnCompare;
    /// <summary>Vergleich aufheben (auch den mit architecture.baseline).</summary>
    property OnClearComparison: TProc read FHandlers.OnClearComparison write FHandlers.OnClearComparison;
    property OnScopeChanged: TProc<string> read FHandlers.OnScopeChanged write FHandlers.OnScopeChanged;
    property OnLibraryChanged: TProc<Boolean> read FHandlers.OnLibraryChanged write FHandlers.OnLibraryChanged;
    /// <summary>Regler losgelassen, Doppelklick oder Taste: neue Feinheit (#1366).</summary>
    property OnResolutionChanged: TProc<Double> read FHandlers.OnResolutionChanged
      write FHandlers.OnResolutionChanged;
    /// <summary>„Teilsysteme neu benennen“ im Menü „Teilsysteme ▾“ (#1367): einmal ohne Angleichung rechnen.
    /// </summary>
    property OnRenameSubsystems: TProc read FHandlers.OnRenameSubsystems write FHandlers.OnRenameSubsystems;
    property OnOpenUnit: TProc<string> read FHandlers.OnOpenUnit write FHandlers.OnOpenUnit;
    /// <summary>Absoluter Pfad, Zeile und Spalte ab 1.</summary>
    property OnOpenLocation: TProc<string, Integer, Integer> read FHandlers.OnOpenLocation
      write FHandlers.OnOpenLocation;
    /// <summary>Strg+Doppelklick bzw. Strg+Enter auf eine Unit: Fenster „Unit-Beziehungen“ (#593), absoluter Pfad.
    /// </summary>
    property OnUnitRelations: TProc<string> read FHandlers.OnUnitRelations write FHandlers.OnUnitRelations;
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
  Atlas.UI.Architecture.Texts,
  Atlas.UI.Analysis.Strings;

{$R *.dfm}

const
  cScopeValues: array[0..1] of string = ('projectGroup', 'project');
  /// <summary>Abstand oben der Beschriftungen in der Leiste bei 96 dpi, mittig zu den Feldern.</summary>
  cBarLabelTop = 7;
  /// <summary>Feste Breite des Filterfelds bei 96 dpi; in der fließenden Leiste bricht es um.</summary>
  cFilterWidth = 200;
  /// <summary>Unterer Teil der Index-Generation: Zahl der Änderungen; der obere kennzeichnet nur den Index.
  /// </summary>
  cChangeCountMask = $7FFFFFFF;
  /// <summary>Spalten der Tabelle „Zentrale Units“ in Reihenfolge der Anzeige.</summary>
  cCentralColumns: array[0..5] of TAtlasArchColumn = (TAtlasArchColumn.Name, TAtlasArchColumn.Subsystem,
    TAtlasArchColumn.Direct, TAtlasArchColumn.Total, TAtlasArchColumn.Uses_, TAtlasArchColumn.Role);

type
  TArchFrame = TAtlasArchitectureFrame;
  TArchEvents = TAtlasArchitectureFrame.TEvents;
  TArchTexts = TAtlasArchitectureTexts;

{ Aufbau }

function NewSheet(AFrame: TArchFrame; AText: TAtlasAnalysisTextId): TTabSheet;
begin
  Result := TTabSheet.Create(AFrame);
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (CreateWnd zeigt ihn).
  Result.TabVisible := False;
  Result.PageControl := AFrame.FParts.Pages;
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  AFrame.FParts.Sheets := AFrame.FParts.Sheets + [Result];
end;

function NewList(AFrame: TArchFrame; AParent: TWinControl): TListView;
begin
  Result := TListView.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.RowSelect := True;
  Result.ReadOnly := True;
  Result.HideSelection := False;
  Result.ColumnClick := False;
  Result.OnKeyDown := AFrame.FState.Events.ListKeyDown;
end;

function NewTree(AFrame: TArchFrame; AParent: TWinControl): TTreeView;
begin
  Result := TTreeView.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.HideSelection := False;
  Result.OnDblClick := AFrame.FState.Events.TreeDblClick;
  Result.OnKeyDown := AFrame.FState.Events.TreeKeyDown;
end;

procedure AddColumn(AList: TListView; AText: TAtlasAnalysisTextId; AWidth, APpi: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasAnalysisStrings.Text(AText);
  mColumn.Width := MulDiv(AWidth, APpi, 96);
end;

/// <summary>Links ausgerichtet hinter AAfter (nil: ganz links).</summary>
procedure PlaceLeft(AControl: TControl; AParent: TWinControl; AAfter: TControl);
begin
  AControl.Parent := AParent;
  AControl.AlignWithMargins := True;
  // In einer fließenden Leiste ordnet TFlowPanel nach Erzeugungsreihenfolge an; Align störte dort.
  if AParent is TFlowPanel then
  begin
    Exit;
  end;
  AControl.Align := alLeft;
  if AAfter <> nil then
  begin
    AControl.Left := AAfter.Left + AAfter.Width + 1;
  end;
end;

function NewButton(AFrame: TArchFrame; AParent: TWinControl; AAfter: TControl; AText: TAtlasAnalysisTextId;
  AWidth: Integer; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AFrame);
  PlaceLeft(Result, AParent, AAfter);
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

/// <summary>Schalter der Karte: Tag = Ord(AFlag), Haken nach dem Zustand der Karte.</summary>
function NewFlagCheck(AFrame: TArchFrame; AAfter: TControl; AText: TAtlasAnalysisTextId; AWidth: Integer;
  AFlag: TAtlasArchMapFlag): TCheckBox;
begin
  Result := TCheckBox.Create(AFrame);
  PlaceLeft(Result, AFrame.FParts.MapBar, AAfter);
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  Result.Width := AWidth;
  Result.Tag := Ord(AFlag);
  Result.Checked := AFlag <> TAtlasArchMapFlag.MarkCycles;
  Result.OnClick := AFrame.FState.Events.FlagClick;
end;

function NewLabel(AFrame: TArchFrame; AParent: TWinControl; AAlign: TAlign): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
end;

function NewBar(AFrame: TArchFrame; AParent: TWinControl): TPanel;
begin
  Result := TPanel.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.AutoSize := True;
end;

/// <summary>Obere Leiste, die bei schmalem Fenster in weitere Zeilen umbricht.</summary>
function NewFlowBar(AFrame: TArchFrame; AParent: TWinControl): TFlowPanel;
begin
  Result := TFlowPanel.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.AutoWrap := True;
  Result.AutoSize := True;
end;

/// <summary>Beschriftung einer fließenden Leiste, etwa mittig zu den Knöpfen.</summary>
function NewFlowLabel(AFrame: TArchFrame; AParent: TFlowPanel): TLabel;
begin
  Result := NewLabel(AFrame, AParent, alNone);
  Result.AutoSize := True;
  Result.Margins.Top := AFrame.ScaleValue(cBarLabelTop);
end;

procedure UpdateResolutionInfo(AFrame: TArchFrame; AValue: Double);
var
  mText: string;
begin
  mText := TAtlasArchResolution.Text(AValue, FormatSettings);
  if AFrame.FState.HasModel and TAtlasArchResolution.Same(AFrame.FState.Model.Resolution, AValue) then
  begin
    AFrame.FParts.ResolutionInfo.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureResolutionInfo,
      [mText, AFrame.FState.Model.SubsystemCount]);
  end
  else
  begin
    AFrame.FParts.ResolutionInfo.Caption := TAtlasAnalysisStrings.Fmt(
      TAtlasAnalysisTextId.ArchitectureResolutionValue, [mText]);
  end;
end;

function ResolutionTracking(AFrame: TArchFrame): TProc<Double>;
begin
  Result :=
    procedure(AValue: Double)
    begin
      UpdateResolutionInfo(AFrame, AValue);
    end;
end;

function ResolutionChange(AFrame: TArchFrame): TProc<Double>;
begin
  Result :=
    procedure(AValue: Double)
    begin
      UpdateResolutionInfo(AFrame, AValue);
      if Assigned(AFrame.FHandlers.OnResolutionChanged) then
      begin
        AFrame.FHandlers.OnResolutionChanged(AValue);
      end;
    end;
end;

procedure BuildTop(AFrame: TArchFrame);
var
  mEvents: TArchEvents;
begin
  mEvents := AFrame.FState.Events;
  AFrame.FParts.Top := NewFlowBar(AFrame, AFrame);
  AFrame.FParts.Top.Padding.SetBounds(2, 2, 2, 2);
  AFrame.FParts.Refresh := NewButton(AFrame, AFrame.FParts.Top, nil, TAtlasAnalysisTextId.ArchitectureRefresh, 110,
    mEvents.RefreshClick);
  AFrame.FParts.Save := NewButton(AFrame, AFrame.FParts.Top, AFrame.FParts.Refresh,
    TAtlasAnalysisTextId.ArchitectureSaveReport, 130, mEvents.SaveClick);
  AFrame.FParts.SaveState := NewButton(AFrame, AFrame.FParts.Top, AFrame.FParts.Save,
    TAtlasAnalysisTextId.ArchitectureSaveState, 120, mEvents.SaveStateClick);
  AFrame.FParts.Compare := NewButton(AFrame, AFrame.FParts.Top, AFrame.FParts.SaveState,
    TAtlasAnalysisTextId.ArchitectureCompare, 130, mEvents.CompareClick);
  AFrame.FParts.Scope := TComboBox.Create(AFrame);
  PlaceLeft(AFrame.FParts.Scope, AFrame.FParts.Top, AFrame.FParts.Compare);
  AFrame.FParts.Scope.Style := csDropDownList;
  AFrame.FParts.Scope.Width := AFrame.FParts.Scope.ScaleValue(130);
  AFrame.FParts.Scope.OnChange := mEvents.ScopeChange;
  AFrame.FParts.LibraryUnits := TCheckBox.Create(AFrame);
  PlaceLeft(AFrame.FParts.LibraryUnits, AFrame.FParts.Top, AFrame.FParts.Scope);
  AFrame.FParts.LibraryUnits.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureLibrary);
  AFrame.FParts.LibraryUnits.Width := AFrame.FParts.LibraryUnits.ScaleValue(120);
  AFrame.FParts.LibraryUnits.OnClick := mEvents.LibraryClick;
end;

procedure BuildResolution(AFrame: TArchFrame);
var
  mCaption, mInfo: TLabel;
  mSlider: TAtlasResolutionSlider;
begin
  mCaption := NewFlowLabel(AFrame, AFrame.FParts.Top);
  mCaption.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureResolutionCaption);
  mSlider := TAtlasResolutionSlider.Create(AFrame);
  PlaceLeft(mSlider, AFrame.FParts.Top, mCaption);
  mSlider.Width := mSlider.ScaleValue(140);
  mSlider.Hint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureResolutionHint);
  mSlider.ShowHint := True;
  mSlider.OnTracking := ResolutionTracking(AFrame);
  mSlider.OnChange := ResolutionChange(AFrame);
  mInfo := NewFlowLabel(AFrame, AFrame.FParts.Top);
  AFrame.FParts.ResolutionCaption := mCaption;
  AFrame.FParts.Resolution := mSlider;
  AFrame.FParts.ResolutionInfo := mInfo;
  UpdateResolutionInfo(AFrame, mSlider.Value);
end;

procedure BuildFilterAndStatus(AFrame: TArchFrame);
begin
  AFrame.FParts.Filter := TEdit.Create(AFrame);
  AFrame.FParts.Filter.Parent := AFrame.FParts.Top;
  AFrame.FParts.Filter.AlignWithMargins := True;
  // Feste Breite statt alClient: in der fließenden Leiste bricht das Feld bei Bedarf um.
  AFrame.FParts.Filter.Width := AFrame.ScaleValue(cFilterWidth);
  AFrame.FParts.Filter.TextHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFilterHint);
  AFrame.FParts.Filter.OnChange := AFrame.FState.Events.FilterChange;
  AFrame.FParts.Status := NewLabel(AFrame, AFrame, alBottom);
  AFrame.FParts.Status.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.Status.Caption := '';
  AFrame.FParts.Pages := TPageControl.Create(AFrame);
  AFrame.FParts.Pages.Parent := AFrame;
  AFrame.FParts.Pages.Align := alClient;
  AFrame.FParts.Pages.AlignWithMargins := True;
end;

procedure BuildAssignment(AFrame: TArchFrame; ASheet: TTabSheet);
begin
  // Erklärung der Zuordnung links neben dem Diagramm (scrollbar, Breite über die Ziehleiste); unten verdrängte sie
  // bei vielen Teilsystemen das Diagramm.
  AFrame.FParts.AssignmentBox := TScrollBox.Create(AFrame);
  AFrame.FParts.AssignmentBox.Parent := ASheet;
  AFrame.FParts.AssignmentBox.Align := alLeft;
  AFrame.FParts.AssignmentBox.BorderStyle := bsNone;
  AFrame.FParts.AssignmentBox.VertScrollBar.Tracking := True;
  AFrame.FParts.AssignmentBox.Visible := False;
  AFrame.FParts.AssignmentSplit := TSplitter.Create(AFrame);
  AFrame.FParts.AssignmentSplit.Parent := ASheet;
  AFrame.FParts.AssignmentSplit.Align := alLeft;
  AFrame.FParts.AssignmentSplit.Left := AFrame.FParts.AssignmentBox.Left + AFrame.FParts.AssignmentBox.Width + 1;
  AFrame.FParts.AssignmentSplit.Visible := False;
  AFrame.FParts.Assignment := TPaintBox.Create(AFrame);
  AFrame.FParts.Assignment.Parent := AFrame.FParts.AssignmentBox;
  AFrame.FParts.Assignment.SetBounds(0, 0, 10, 10);
  AFrame.FParts.Assignment.OnPaint := AFrame.FState.Events.AssignmentPaint;
end;

procedure BuildMapBar(AFrame: TArchFrame; ASheet: TTabSheet);
var
  mEvents: TArchEvents;
  mBar: TPanel;
begin
  mEvents := AFrame.FState.Events;
  mBar := NewBar(AFrame, ASheet);
  AFrame.FParts.MapBar := mBar;
  AFrame.FParts.Fit := NewButton(AFrame, mBar, nil, TAtlasAnalysisTextId.ArchitectureFit, 90, mEvents.FitClick);
  AFrame.FParts.Names := NewFlagCheck(AFrame, AFrame.FParts.Fit, TAtlasAnalysisTextId.ArchitectureNames, 120,
    TAtlasArchMapFlag.ShowNames);
  AFrame.FParts.ImplementationUses := NewFlagCheck(AFrame, AFrame.FParts.Names,
    TAtlasAnalysisTextId.ArchitectureImplementation, 140, TAtlasArchMapFlag.ShowImplementation);
  AFrame.FParts.MarkCycles := NewFlagCheck(AFrame, AFrame.FParts.ImplementationUses,
    TAtlasAnalysisTextId.ArchitectureMarkCycles, 130, TAtlasArchMapFlag.MarkCycles);
  AFrame.FParts.Changes := NewFlagCheck(AFrame, AFrame.FParts.MarkCycles, TAtlasAnalysisTextId.ArchitectureShowChanges,
    150, TAtlasArchMapFlag.ShowChanges);
  AFrame.FParts.Changes.Enabled := False;
  AFrame.FParts.SubsystemsButton := NewButton(AFrame, mBar, AFrame.FParts.Changes,
    TAtlasAnalysisTextId.ArchitectureSubsystemsButton, 110, mEvents.SubsystemsClick);
  AFrame.FParts.SubsystemsMenu := TPopupMenu.Create(AFrame);
end;

procedure UpdateInfo(AFrame: TArchFrame); forward;

function MapSelectHandler(AFrame: TArchFrame): TProc<Integer>;
begin
  Result :=
    procedure(AUnit: Integer)
    begin
      UpdateInfo(AFrame);
    end;
end;

function MapOpenHandler(AFrame: TArchFrame): TProc<Integer>;
begin
  Result :=
    procedure(AUnit: Integer)
    begin
      AFrame.OpenUnit(AUnit);
    end;
end;

function PathChangedHandler(AFrame: TArchFrame): TProc;
begin
  Result :=
    procedure
    begin
      UpdateInfo(AFrame);
    end;
end;

procedure BuildOverview(AFrame: TArchFrame);
var
  mSheet: TTabSheet;
begin
  mSheet := NewSheet(AFrame, TAtlasAnalysisTextId.ArchitectureTabOverview);
  AFrame.FParts.Info := NewLabel(AFrame, mSheet, alBottom);
  AFrame.FParts.Info.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.Info.Font.Color := clGrayText;
  AFrame.FParts.Info.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMapHint);
  BuildAssignment(AFrame, mSheet);
  BuildMapBar(AFrame, mSheet);
  AFrame.FParts.Map := TAtlasArchitectureMap.Create(AFrame);
  AFrame.FParts.Map.Parent := mSheet;
  AFrame.FParts.Map.Align := alClient;
  AFrame.FParts.Map.OnSelect := MapSelectHandler(AFrame);
  AFrame.FParts.Map.OnOpen := MapOpenHandler(AFrame);
  AFrame.FParts.Map.State.OnPathChanged := PathChangedHandler(AFrame);
end;

procedure BuildCentral(AFrame: TArchFrame);
var
  mList: TListView;
  mPpi: Integer;
begin
  mList := NewList(AFrame, NewSheet(AFrame, TAtlasAnalysisTextId.ArchitectureTabCentral));
  AFrame.FParts.Central := mList;
  mList.ColumnClick := True;
  mList.OnColumnClick := AFrame.FState.Events.CentralColumnClick;
  mList.OnDblClick := AFrame.FState.Events.CentralDblClick;
  mPpi := AFrame.CurrentPPI;
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColUnit, 220, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColSubsystem, 120, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColDirect, 100, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColTotal, 100, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColUses, 80, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColRole, 100, mPpi);
end;

procedure BuildSubsystems(AFrame: TArchFrame);
var
  mSheet: TTabSheet;
  mButton: TButton;
begin
  mSheet := NewSheet(AFrame, TAtlasAnalysisTextId.ArchitectureTabSubsystems);
  // Fragezeichen mit der Erklärung, wie die Teilsysteme entstehen (#1368); nur mit Zuordnung vom Server.
  AFrame.FParts.SubsystemsBar := NewBar(AFrame, mSheet);
  AFrame.FParts.SubsystemsBar.Visible := False;
  mButton := NewButton(AFrame, AFrame.FParts.SubsystemsBar, nil, TAtlasAnalysisTextId.ArchitectureExplainButton, 28,
    AFrame.FState.Events.ExplainClick);
  mButton.Hint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  mButton.ShowHint := True;
  AFrame.FParts.ExplainButton := mButton;
  AFrame.FParts.Explanation := NewLabel(AFrame, AFrame.FParts.SubsystemsBar, alClient);
  AFrame.FParts.Explanation.WordWrap := True;
  AFrame.FParts.Explanation.Font.Color := clGrayText;
  AFrame.FParts.Explanation.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  AFrame.FParts.Subsystems := NewTree(AFrame, mSheet);
end;

procedure BuildCyclesAndCrossLinks(AFrame: TArchFrame);
var
  mList: TListView;
  mPpi: Integer;
begin
  AFrame.FParts.Cycles := NewTree(AFrame, NewSheet(AFrame, TAtlasAnalysisTextId.ArchitectureTabCycles));
  mList := NewList(AFrame, NewSheet(AFrame, TAtlasAnalysisTextId.ArchitectureTabCrossLinks));
  AFrame.FParts.CrossLinks := mList;
  mList.OnDblClick := AFrame.FState.Events.CrossDblClick;
  mPpi := AFrame.CurrentPPI;
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColFrom, 200, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColTo, 200, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColSubsystem, 180, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColReason, 160, mPpi);
  AddColumn(mList, TAtlasAnalysisTextId.ArchitectureColLocation, 200, mPpi);
end;

procedure BuildComparison(AFrame: TArchFrame);
var
  mSheet: TTabSheet;
  mButton: TButton;
begin
  mSheet := NewSheet(AFrame, TAtlasAnalysisTextId.ArchitectureTabComparison);
  AFrame.FParts.CompareBar := NewBar(AFrame, mSheet);
  mButton := NewButton(AFrame, AFrame.FParts.CompareBar, nil, TAtlasAnalysisTextId.ArchitectureClearComparison, 140,
    AFrame.FState.Events.ClearCompareClick);
  mButton.Align := alRight;
  mButton.Enabled := False;
  AFrame.FParts.ClearCompare := mButton;
  AFrame.FParts.CompareInfo := NewLabel(AFrame, AFrame.FParts.CompareBar, alClient);
  AFrame.FParts.CompareInfo.Layout := tlCenter;
  AFrame.FParts.CompareInfo.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.CompareInfo.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoComparison);
  AFrame.FParts.Comparison := NewTree(AFrame, mSheet);
end;

{ Füllen }

function CanFill(AControl: TWinControl): Boolean;
begin
  Result := AControl.HandleAllocated or (GetParentForm(AControl) <> nil);
end;

procedure FillScope(AFrame: TArchFrame);
var
  mScope: TComboBox;
begin
  mScope := AFrame.FParts.Scope;
  if not CanFill(mScope) then
  begin
    Exit;
  end;
  AFrame.FState.Updating := True;
  try
    mScope.Items.BeginUpdate;
    try
      mScope.Items.Clear;
      mScope.Items.Add(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureScopeGroup));
      mScope.Items.Add(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureScopeProject));
    finally
      mScope.Items.EndUpdate;
    end;
    mScope.ItemIndex := Ord(AFrame.FState.ScopeValue = cScopeValues[1]);
  finally
    AFrame.FState.Updating := False;
  end;
end;

function AddLink(AFrame: TArchFrame; const ALink: TAtlasArchLink): Integer;
begin
  AFrame.FState.Links := AFrame.FState.Links + [ALink];
  Result := Length(AFrame.FState.Links);
end;

function Matches(AFrame: TArchFrame; AUnit: Integer): Boolean;
begin
  Result := AFrame.FState.Model.Matches(AUnit, AFrame.FParts.Filter.Text);
end;

procedure FillCentral(AFrame: TArchFrame);
var
  mShown: TArray<Integer>;
  mMember: Integer;
  mItem: TListItem;
  mData: TAtlasArchUnit;
begin
  if not CanFill(AFrame.FParts.Central) then
  begin
    Exit;
  end;
  mShown := nil;
  for mMember in AFrame.FState.Model.Central do
  begin
    if Matches(AFrame, mMember) then
    begin
      mShown := mShown + [mMember];
    end;
  end;
  AFrame.FState.CentralRows := AFrame.FState.Model.Sorted(mShown, AFrame.FState.Sort.Column,
    AFrame.FState.Sort.Descending);
  AFrame.FParts.Central.Items.BeginUpdate;
  try
    AFrame.FParts.Central.Items.Clear;
    for mMember in AFrame.FState.CentralRows do
    begin
      mData := AFrame.FState.Model.Units[mMember];
      mItem := AFrame.FParts.Central.Items.Add;
      mItem.Caption := mData.Name;
      mItem.SubItems.Add(AFrame.FState.Model.SubsystemName(mData.Subsystem));
      mItem.SubItems.Add(IntToStr(mData.Direct));
      mItem.SubItems.Add(IntToStr(mData.Total));
      mItem.SubItems.Add(IntToStr(mData.Uses_));
      mItem.SubItems.Add(TArchTexts.RoleCaption(mData.Role));
    end;
  finally
    AFrame.FParts.Central.Items.EndUpdate;
  end;
end;

/// <summary>Units des Teilsystems, die der Filter durchlässt.</summary>
function FilteredMembers(AFrame: TArchFrame; ASubsystem: Integer): TArray<Integer>;
var
  mMember: Integer;
begin
  Result := nil;
  for mMember in AFrame.FState.Model.Subsystems[ASubsystem].Units do
  begin
    if Matches(AFrame, mMember) then
    begin
      Result := Result + [mMember];
    end;
  end;
end;

procedure AddSubsystemGroup(AFrame: TArchFrame; ASubsystem: Integer; const AMembers: TArray<Integer>);
var
  mItems: TTreeNodes;
  mGroup: TTreeNode;
  mLine: string;
  mMember: Integer;
  mSubsystem: TAtlasArchSubsystem;
begin
  mItems := AFrame.FParts.Subsystems.Items;
  mSubsystem := AFrame.FState.Model.Subsystems[ASubsystem];
  mLine := TArchTexts.SubsystemCaption(AFrame.FState.Model, ASubsystem);
  if mSubsystem.Parent <> '' then
  begin
    mLine := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemPart, [mLine, mSubsystem.Parent]);
  end;
  mGroup := mItems.Add(nil, mLine);
  mGroup.Data := nil;
  // Regel des Fundaments (#1365) als erste Zeile.
  if mSubsystem.Foundation then
  begin
    mItems.AddChild(mGroup, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationRule)).Data := nil;
  end;
  for mMember in AFrame.FState.Model.Sorted(AMembers, TAtlasArchColumn.Total, True) do
  begin
    // Unit: negative Zahl (−1 − Nummer), uses-Eintrag: positive (Nummer in Links + 1).
    mItems.AddChild(mGroup, TArchTexts.MemberLine(AFrame.FState.Model, mMember)).Data :=
      Pointer(NativeInt(-1 - mMember));
  end;
  // Kleine Teilsysteme aufgeklappt, große zu.
  mGroup.Expanded := Length(AMembers) <= 12;
end;

procedure FillSubsystems(AFrame: TArchFrame);
var
  mIndex: Integer;
  mMembers: TArray<Integer>;
begin
  if not CanFill(AFrame.FParts.Subsystems) then
  begin
    Exit;
  end;
  AFrame.FParts.Subsystems.Items.BeginUpdate;
  try
    AFrame.FParts.Subsystems.Items.Clear;
    // Teile eines nachgeteilten Teilsystems (#1364) beieinander.
    for mIndex in AFrame.FState.Model.LegendOrder do
    begin
      mMembers := FilteredMembers(AFrame, mIndex);
      if Length(mMembers) > 0 then
      begin
        AddSubsystemGroup(AFrame, mIndex, mMembers);
      end;
    end;
  finally
    AFrame.FParts.Subsystems.Items.EndUpdate;
  end;
end;

function CycleShown(AFrame: TArchFrame; const ACycle: TAtlasArchCycle): Boolean;
var
  mMember: Integer;
begin
  Result := False;
  for mMember in ACycle.Units do
  begin
    Result := Result or Matches(AFrame, mMember);
  end;
end;

procedure AddCycle(AFrame: TArchFrame; const ACycle: TAtlasArchCycle);
var
  mItems: TTreeNodes;
  mGroup: TTreeNode;
  mLink: TAtlasArchLink;
begin
  mItems := AFrame.FParts.Cycles.Items;
  mGroup := mItems.Add(nil, TArchTexts.CycleTitle(ACycle) + ': ' + AFrame.FState.Model.CyclePath(ACycle));
  mGroup.Data := nil;
  for mLink in ACycle.Edges do
  begin
    mItems.AddChild(mGroup, TArchTexts.LinkCaption(AFrame.FState.Model, mLink)).Data :=
      Pointer(NativeInt(AddLink(AFrame, mLink)));
  end;
  mGroup.Expanded := True;
end;

procedure FillCycles(AFrame: TArchFrame);
var
  mCycle: TAtlasArchCycle;
begin
  if not CanFill(AFrame.FParts.Cycles) then
  begin
    Exit;
  end;
  AFrame.FParts.Cycles.Items.BeginUpdate;
  try
    AFrame.FParts.Cycles.Items.Clear;
    for mCycle in AFrame.FState.Model.Cycles do
    begin
      if CycleShown(AFrame, mCycle) then
      begin
        AddCycle(AFrame, mCycle);
      end;
    end;
  finally
    AFrame.FParts.Cycles.Items.EndUpdate;
  end;
end;

procedure AddCrossItem(AFrame: TArchFrame; const ALink: TAtlasArchLink);
var
  mItem: TListItem;
  mReason: string;
  mModel: TAtlasArchitectureModel;
begin
  mModel := AFrame.FState.Model;
  if ALink.Reason = 'rare' then
  begin
    mReason := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonRare);
  end
  else
  begin
    mReason := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonAgainst);
  end;
  mItem := AFrame.FParts.CrossLinks.Items.Add;
  mItem.Caption := TArchTexts.UnitCaption(mModel, ALink.Source);
  mItem.SubItems.Add(TArchTexts.UnitCaption(mModel, ALink.Target));
  mItem.SubItems.Add(mModel.SubsystemName(ALink.FromSubsystem) + ' → ' + mModel.SubsystemName(ALink.ToSubsystem));
  mItem.SubItems.Add(Format('%s (%d:%d)', [mReason, ALink.Forward, ALink.Backward]));
  mItem.SubItems.Add(TArchTexts.LocationCaption(ALink));
end;

procedure FillCrossLinks(AFrame: TArchFrame);
var
  mIndex: Integer;
  mLink: TAtlasArchLink;
begin
  if not CanFill(AFrame.FParts.CrossLinks) then
  begin
    Exit;
  end;
  AFrame.FState.CrossRows := nil;
  AFrame.FParts.CrossLinks.Items.BeginUpdate;
  try
    AFrame.FParts.CrossLinks.Items.Clear;
    for mIndex := 0 to High(AFrame.FState.Model.CrossLinks) do
    begin
      mLink := AFrame.FState.Model.CrossLinks[mIndex];
      if Matches(AFrame, mLink.Source) or Matches(AFrame, mLink.Target) then
      begin
        AFrame.FState.CrossRows := AFrame.FState.CrossRows + [mIndex];
        AddCrossItem(AFrame, mLink);
      end;
    end;
  finally
    AFrame.FParts.CrossLinks.Items.EndUpdate;
  end;
end;

/// <summary>Der Filter wirkt wie in den anderen Listen auf die Namen; entfernte Units zählen mit ihrem Namen.
/// </summary>
function ChangeShown(AFrame: TArchFrame; const AChange: TAtlasArchChange): Boolean;
var
  mFilter: string;
begin
  mFilter := LowerCase(Trim(AFrame.FParts.Filter.Text));
  Result := (mFilter = '') or (Pos(mFilter, LowerCase(AChange.Text)) > 0) or Matches(AFrame, AChange.Unit_);
end;

procedure AddChangeSection(AFrame: TArchFrame; const ASection: TAtlasArchChangeSection);
const
  cTitles: array[TAtlasArchChangeKind] of TAtlasAnalysisTextId = (TAtlasAnalysisTextId.ArchitectureChangeNewCycles,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedCycles, TAtlasAnalysisTextId.ArchitectureChangeNewCrossLinks,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedCrossLinks, TAtlasAnalysisTextId.ArchitectureChangeNewEdges,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedEdges, TAtlasAnalysisTextId.ArchitectureChangeMoves,
    TAtlasAnalysisTextId.ArchitectureChangeGrowth, TAtlasAnalysisTextId.ArchitectureChangeNewUnits,
    TAtlasAnalysisTextId.ArchitectureChangeRemovedUnits);
var
  mShown: TArray<TAtlasArchChange>;
  mChange: TAtlasArchChange;
  mGroup: TTreeNode;
  mItems: TTreeNodes;
begin
  mShown := nil;
  for mChange in ASection.Items do
  begin
    if ChangeShown(AFrame, mChange) then
    begin
      mShown := mShown + [mChange];
    end;
  end;
  if Length(mShown) = 0 then
  begin
    Exit;
  end;
  mItems := AFrame.FParts.Comparison.Items;
  mGroup := mItems.Add(nil, TAtlasAnalysisStrings.Fmt(cTitles[ASection.Kind], [Length(mShown)]));
  mGroup.Data := nil;
  for mChange in mShown do
  begin
    // Wie im Baum der Teilsysteme: Unit als −1 − Nummer; entfernte Units haben keine (Data = nil).
    mItems.AddChild(mGroup, TArchTexts.ChangeCaption(ASection.Kind, mChange)).Data :=
      Pointer(NativeInt(-1 - Max(-1, mChange.Unit_)));
  end;
  mGroup.Expanded := Length(mShown) <= 20;
end;

procedure FillComparisonTree(AFrame: TArchFrame);
var
  mComparison: TAtlasArchComparison;
  mSection: TAtlasArchChangeSection;
  mItems: TTreeNodes;
begin
  mComparison := AFrame.FState.Model.Comparison;
  mItems := AFrame.FParts.Comparison.Items;
  mItems.BeginUpdate;
  try
    mItems.Clear;
    if mComparison.Present and (mComparison.Count = 0) then
    begin
      mItems.Add(nil, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoChanges)).Data := nil;
    end
    else if mComparison.Present then
    begin
      for mSection in mComparison.Sections do
      begin
        AddChangeSection(AFrame, mSection);
      end;
    end;
  finally
    mItems.EndUpdate;
  end;
end;

procedure FillComparison(AFrame: TArchFrame);
var
  mComparison: TAtlasArchComparison;
begin
  mComparison := AFrame.FState.Model.Comparison;
  AFrame.FParts.Changes.Enabled := mComparison.Present;
  AFrame.FParts.Map.State.SetFlag(TAtlasArchMapFlag.ShowChanges, AFrame.FParts.Changes.Checked);
  AFrame.FParts.ClearCompare.Enabled := AFrame.FState.HasModel and
    ((mComparison.Baseline <> '') or (mComparison.Error <> ''));
  AFrame.FParts.CompareInfo.Caption := TArchTexts.ComparisonInfo(mComparison);
  AFrame.FParts.CompareInfo.Hint := mComparison.Baseline;
  AFrame.FParts.CompareInfo.ShowHint := mComparison.Baseline <> '';
  if CanFill(AFrame.FParts.Comparison) then
  begin
    FillComparisonTree(AFrame);
  end;
end;

function StatusText(AFrame: TArchFrame): string;
var
  mModel: TAtlasArchitectureModel;
begin
  mModel := AFrame.FState.Model;
  if AFrame.FState.MessageText <> '' then
  begin
    Exit(AFrame.FState.MessageText);
  end;
  if not AFrame.FState.HasModel then
  begin
    Exit('');
  end;
  if Length(mModel.Units) = 0 then
  begin
    Exit(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureEmpty));
  end;
  // Index-Stand: Zahl der Änderungen; der obere Teil der Generation kennzeichnet nur den Index.
  Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatus, [Length(mModel.Units),
    Length(mModel.Subsystems), Length(mModel.Cycles), Length(mModel.CrossLinks),
    Integer(mModel.Generation and cChangeCountMask), mModel.DurationMs]) + TArchTexts.StatusNotes(mModel);
end;

procedure UpdateStatus(AFrame: TArchFrame);
begin
  AFrame.FParts.Status.Caption := StatusText(AFrame);
  AFrame.FParts.Save.Enabled := AFrame.FState.HasModel and (Length(AFrame.FState.Model.Units) > 0);
  AFrame.FParts.SaveState.Enabled := AFrame.FParts.Save.Enabled;
end;

procedure UpdateAssignment(AFrame: TArchFrame);
var
  mBitmap: Vcl.Graphics.TBitmap;
  mSize: TSize;
  mControls: TArchFrame.TParts;
  mState: TAtlasArchitectureMapState;
begin
  mControls := AFrame.FParts;
  mState := mControls.Map.State;
  // Steckbrief (#1368): nur mit gewählter Unit, ohne Weg und mit Zuordnung vom Server.
  if (mState.Path.From >= 0) or (Length(mState.Path.Route) > 0) or
    not TAtlasArchitectureAssignment.Available(AFrame.FState.Model, mState.Selected) then
  begin
    mControls.AssignmentSplit.Visible := False;
    mControls.AssignmentBox.Visible := False;
    Exit;
  end;
  // Messen ohne Fenster: auf einer Bitmap mit derselben Schrift.
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(AFrame.Font);
    mSize := TAtlasArchitectureAssignment.Measure(mBitmap.Canvas, AFrame.FState.Model, mState.Selected,
      AFrame.CurrentPPI);
  finally
    mBitmap.Free;
  end;
  mControls.Assignment.SetBounds(0, 0, mSize.cx + 1, mSize.cy + 1);
  if not mControls.AssignmentBox.Visible then
  begin
    // Breite nach dem Inhalt (Platz für die Bildlaufleiste), höchstens 40 % der Seite; danach gilt die Ziehleiste.
    mControls.AssignmentBox.Width := Min(mSize.cx + GetSystemMetrics(SM_CXVSCROLL) + AFrame.ScaleValue(8),
      Max(AFrame.ScaleValue(120), mControls.AssignmentBox.Parent.Width * 2 div 5));
    mControls.AssignmentBox.Visible := True;
    mControls.AssignmentSplit.Left := mControls.AssignmentBox.Left + mControls.AssignmentBox.Width + 1;
    mControls.AssignmentSplit.Visible := True;
  end;
  mControls.AssignmentBox.VertScrollBar.Position := 0;
  mControls.Assignment.Invalidate;
end;

/// <summary>Zeile unter der Karte: fester Weg (#1117), Weg nach Umschalt+Klick, gewählte Unit oder Hinweis.
/// </summary>
function InfoText(AFrame: TArchFrame): string;
var
  mModel: TAtlasArchitectureModel;
  mPath: TAtlasArchitectureMapPath;
  mItem: TAtlasArchUnit;
begin
  mModel := AFrame.FState.Model;
  mPath := AFrame.FParts.Map.State.Path;
  if Length(mPath.Route) > 0 then
  begin
    Exit(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureRoute, [Length(mPath.Route),
      mModel.RouteText(mPath.Route)]));
  end;
  if (mPath.From >= 0) and mPath.Found then
  begin
    Exit(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitecturePath, [Length(mPath.Edges),
      mModel.PathText(mPath.From, mPath.Edges)]));
  end;
  if mPath.From >= 0 then
  begin
    Exit(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureNoPath,
      [TArchTexts.UnitCaption(mModel, mPath.From), TArchTexts.UnitCaption(mModel, mPath.To_)]));
  end;
  Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMapHint);
  if (AFrame.FParts.Map.State.Selected >= 0) and (AFrame.FParts.Map.State.Selected <= High(mModel.Units)) then
  begin
    mItem := mModel.Units[AFrame.FParts.Map.State.Selected];
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureUnitInfo, [mItem.Name,
      mModel.SubsystemName(mItem.Subsystem), mItem.Direct, mItem.Total, mItem.Uses_]);
  end;
end;

procedure UpdateInfo(AFrame: TArchFrame);
begin
  UpdateAssignment(AFrame);
  AFrame.FParts.Info.Caption := InfoText(AFrame);
end;

/// <summary>Listen und Bäume nach Daten und Filter neu füllen.</summary>
procedure FillLists(AFrame: TArchFrame);
begin
  FillCentral(AFrame);
  FillSubsystems(AFrame);
  AFrame.FState.Links := nil;
  FillCycles(AFrame);
  FillCrossLinks(AFrame);
  FillComparison(AFrame);
end;

procedure FillAll(AFrame: TArchFrame);
begin
  AFrame.FParts.SubsystemsBar.Visible := AFrame.FState.Model.HasAssignment;
  AFrame.FParts.Explanation.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  FillLists(AFrame);
  UpdateStatus(AFrame);
  UpdateInfo(AFrame);
end;

{ Menü „Teilsysteme ▾“ }

function NewMenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  AMenu.Items.Add(Result);
end;

/// <summary>Überschrift der Teile eines nachgeteilten Teilsystems (#1364), nicht wählbar.</summary>
procedure AddFamilyItem(AFrame: TArchFrame; const AFamily: string);
var
  mParts, mIndex: Integer;
begin
  mParts := 0;
  for mIndex := 0 to High(AFrame.FState.Model.Subsystems) do
  begin
    if SameText(AFrame.FState.Model.Subsystems[mIndex].Parent, AFamily) then
    begin
      Inc(mParts);
    end;
  end;
  NewMenuItem(AFrame.FParts.SubsystemsMenu, TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemFamily,
    [AFamily, mParts]), -1, nil).Enabled := False;
end;

/// <summary>Wie die Legende der HTML-Karte: die Teile eines nachgeteilten Teilsystems (#1364) eingerückt unter
/// seinem Namen.</summary>
procedure AddSubsystemItems(AFrame: TArchFrame);
var
  mIndex: Integer;
  mFamily, mParent, mCaption: string;
begin
  mFamily := '';
  for mIndex in AFrame.FState.Model.LegendOrder do
  begin
    mCaption := TArchTexts.SubsystemCaption(AFrame.FState.Model, mIndex);
    mParent := AFrame.FState.Model.Subsystems[mIndex].Parent;
    if (mParent <> '') and not SameText(mParent, mFamily) then
    begin
      AddFamilyItem(AFrame, mParent);
    end;
    if mParent <> '' then
    begin
      mCaption := '      ' + mCaption;
    end;
    mFamily := mParent;
    NewMenuItem(AFrame.FParts.SubsystemsMenu, mCaption, mIndex, AFrame.FState.Events.SubsystemItemClick).Checked :=
      AFrame.FParts.Map.State.SubsystemVisible[mIndex];
  end;
end;

procedure AddMenuCommands(AFrame: TArchFrame);
var
  mMenu: TPopupMenu;
  mEvents: TArchEvents;
begin
  mMenu := AFrame.FParts.SubsystemsMenu;
  mEvents := AFrame.FState.Events;
  mMenu.Items.NewBottomLine;
  // Kanten zum Fundament (#1365) ein- und ausblenden.
  if AFrame.FState.Model.HasFoundation then
  begin
    NewMenuItem(mMenu, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationEdges), -1,
      mEvents.FoundationEdgesClick).Checked := AFrame.FParts.Map.State.Has(TAtlasArchMapFlag.ShowFoundationEdges);
  end;
  NewMenuItem(mMenu, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureShowAll), 0, mEvents.ShowAllClick);
  // Farben und Namen neu vergeben (#1367), nur wenn der Dienst es anbietet.
  if Assigned(AFrame.FHandlers.OnRenameSubsystems) then
  begin
    NewMenuItem(mMenu, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRenameSubsystems), -1,
      mEvents.RenameSubsystemsClick).Hint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRenameHint);
  end;
end;

{ Text der Listen }

function ItemsText(AList: TListView): TArray<string>;
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

function NodesText(ATree: TTreeView): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ATree.Items.Count - 1 do
  begin
    Result := Result + [StringOfChar(' ', 2 * ATree.Items[mIndex].Level) + ATree.Items[mIndex].Text];
  end;
end;

/// <summary>Speicherdialog; True mit gewählter Datei.</summary>
function ChooseTarget(AFilter: TAtlasAnalysisTextId; const AExtension, ATitle: string; out AFileName: string): Boolean;
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TAtlasAnalysisStrings.Text(AFilter);
    mDialog.DefaultExt := AExtension;
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if ATitle <> '' then
    begin
      mDialog.FileName := 'Architektur-' + ATitle + '.' + AExtension;
    end;
    Result := mDialog.Execute;
    AFileName := mDialog.FileName;
  finally
    mDialog.Free;
  end;
end;

function ChooseBaseline(const ACurrent: string; out AFileName: string): Boolean;
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureStateFilter);
    mDialog.DefaultExt := 'json';
    mDialog.Options := mDialog.Options + [ofFileMustExist, ofPathMustExist];
    if ACurrent <> '' then
    begin
      mDialog.FileName := ACurrent;
    end;
    Result := mDialog.Execute;
    AFileName := mDialog.FileName;
  finally
    mDialog.Free;
  end;
end;

procedure CallProc(const AProc: TProc);
begin
  if Assigned(AProc) then
  begin
    AProc();
  end;
end;

{ TAtlasArchitectureFrame.TEvents }

constructor TAtlasArchitectureFrame.TEvents.Create(AFrame: TAtlasArchitectureFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
end;

procedure TAtlasArchitectureFrame.TEvents.RefreshClick(Sender: TObject);
begin
  CallProc(FFrame.FHandlers.OnRefresh);
end;

procedure TAtlasArchitectureFrame.TEvents.SaveClick(Sender: TObject);
var
  mFileName: string;
begin
  if ChooseTarget(TAtlasAnalysisTextId.ArchitectureSaveFilter, 'html', FFrame.FState.Model.Title, mFileName) and
    Assigned(FFrame.FHandlers.OnSave) then
  begin
    FFrame.FHandlers.OnSave(mFileName);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.SaveStateClick(Sender: TObject);
var
  mFileName: string;
begin
  if ChooseTarget(TAtlasAnalysisTextId.ArchitectureStateFilter, 'json', FFrame.FState.Model.Title, mFileName) and
    Assigned(FFrame.FHandlers.OnSaveState) then
  begin
    FFrame.FHandlers.OnSaveState(mFileName);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.CompareClick(Sender: TObject);
var
  mFileName: string;
begin
  if ChooseBaseline(FFrame.FState.Model.Comparison.Baseline, mFileName) and Assigned(FFrame.FHandlers.OnCompare) then
  begin
    FFrame.FHandlers.OnCompare(mFileName);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.ClearCompareClick(Sender: TObject);
begin
  CallProc(FFrame.FHandlers.OnClearComparison);
end;

procedure TAtlasArchitectureFrame.TEvents.ScopeChange(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FFrame.FParts.Scope.ItemIndex;
  if FFrame.FState.Updating or (mIndex < 0) or (mIndex > High(cScopeValues)) then
  begin
    Exit;
  end;
  FFrame.FState.ScopeValue := cScopeValues[mIndex];
  if Assigned(FFrame.FHandlers.OnScopeChanged) then
  begin
    FFrame.FHandlers.OnScopeChanged(FFrame.FState.ScopeValue);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.LibraryClick(Sender: TObject);
begin
  FFrame.FState.IncludeLibrary := FFrame.FParts.LibraryUnits.Checked;
  if not FFrame.FState.Updating and Assigned(FFrame.FHandlers.OnLibraryChanged) then
  begin
    FFrame.FHandlers.OnLibraryChanged(FFrame.FState.IncludeLibrary);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.FilterChange(Sender: TObject);
begin
  FFrame.FParts.Map.State.Filter := FFrame.FParts.Filter.Text;
  FillLists(FFrame);
end;

procedure TAtlasArchitectureFrame.TEvents.FitClick(Sender: TObject);
begin
  FFrame.FParts.Map.FitView;
end;

procedure TAtlasArchitectureFrame.TEvents.FlagClick(Sender: TObject);
var
  mCheck: TCheckBox;
begin
  mCheck := Sender as TCheckBox;
  FFrame.FParts.Map.State.SetFlag(TAtlasArchMapFlag(mCheck.Tag), mCheck.Checked);
end;

procedure TAtlasArchitectureFrame.TEvents.SubsystemsClick(Sender: TObject);
var
  mPoint: TPoint;
  mButton: TButton;
begin
  FFrame.FillSubsystemsMenu;
  mButton := FFrame.FParts.SubsystemsButton;
  mPoint := mButton.ClientToScreen(System.Types.Point(0, mButton.Height));
  FFrame.FParts.SubsystemsMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasArchitectureFrame.TEvents.SubsystemItemClick(Sender: TObject);
var
  mItem: TMenuItem;
  mState: TAtlasArchitectureMapState;
begin
  mItem := Sender as TMenuItem;
  mState := FFrame.FParts.Map.State;
  mState.SubsystemVisible[mItem.Tag] := not mState.SubsystemVisible[mItem.Tag];
  mItem.Checked := mState.SubsystemVisible[mItem.Tag];
  UpdateInfo(FFrame);
end;

procedure TAtlasArchitectureFrame.TEvents.FoundationEdgesClick(Sender: TObject);
var
  mState: TAtlasArchitectureMapState;
begin
  mState := FFrame.FParts.Map.State;
  mState.SetFlag(TAtlasArchMapFlag.ShowFoundationEdges, not mState.Has(TAtlasArchMapFlag.ShowFoundationEdges));
  (Sender as TMenuItem).Checked := mState.Has(TAtlasArchMapFlag.ShowFoundationEdges);
end;

procedure TAtlasArchitectureFrame.TEvents.ShowAllClick(Sender: TObject);
begin
  FFrame.FParts.Map.State.ShowAllSubsystems;
  UpdateInfo(FFrame);
end;

procedure TAtlasArchitectureFrame.TEvents.RenameSubsystemsClick(Sender: TObject);
begin
  CallProc(FFrame.FHandlers.OnRenameSubsystems);
end;

procedure TAtlasArchitectureFrame.TEvents.CentralColumnClick(Sender: TObject; Column: TListColumn);
var
  mNext: TAtlasArchColumn;
begin
  if (Column.Index < 0) or (Column.Index > High(cCentralColumns)) then
  begin
    Exit;
  end;
  mNext := cCentralColumns[Column.Index];
  if mNext = FFrame.FState.Sort.Column then
  begin
    FFrame.FState.Sort.Descending := not FFrame.FState.Sort.Descending;
  end
  else
  begin
    FFrame.FState.Sort.Column := mNext;
    // Zahlen zuerst die größten, Text alphabetisch.
    FFrame.FState.Sort.Descending := mNext in [TAtlasArchColumn.Direct, TAtlasArchColumn.Total, TAtlasArchColumn.Uses_];
  end;
  FillCentral(FFrame);
end;

procedure TAtlasArchitectureFrame.TEvents.CentralDblClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FFrame.FParts.Central.ItemIndex;
  if (mIndex >= 0) and (mIndex <= High(FFrame.FState.CentralRows)) then
  begin
    FFrame.OpenUnit(FFrame.FState.CentralRows[mIndex]);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.CrossDblClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FFrame.FParts.CrossLinks.ItemIndex;
  if (mIndex >= 0) and (mIndex <= High(FFrame.FState.CrossRows)) then
  begin
    FFrame.OpenLink(FFrame.FState.Model.CrossLinks[FFrame.FState.CrossRows[mIndex]]);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.TreeDblClick(Sender: TObject);
var
  mNode: TTreeNode;
  mValue: NativeInt;
begin
  mNode := nil;
  if Sender is TTreeView then
  begin
    mNode := TTreeView(Sender).Selected;
  end;
  if (mNode = nil) or (mNode.Data = nil) then
  begin
    Exit;
  end;
  // Unit: −1 − Nummer, uses-Eintrag: Nummer in Links + 1.
  mValue := NativeInt(mNode.Data);
  if mValue < 0 then
  begin
    FFrame.OpenUnit(-1 - mValue);
  end
  else if mValue <= Length(FFrame.FState.Links) then
  begin
    FFrame.OpenLink(FFrame.FState.Links[mValue - 1]);
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then
  begin
    Exit;
  end;
  if Sender = FFrame.FParts.Central then
  begin
    CentralDblClick(Sender);
  end
  else if Sender = FFrame.FParts.CrossLinks then
  begin
    CrossDblClick(Sender);
  end;
  Key := 0;
end;

procedure TAtlasArchitectureFrame.TEvents.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    TreeDblClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasArchitectureFrame.TEvents.AssignmentPaint(Sender: TObject);
var
  mColors: TAtlasColors;
  mSize: TSize;
  mBox: TPaintBox;
  mSelected, mPpi: Integer;
begin
  mSelected := FFrame.FParts.Map.State.Selected;
  if not TAtlasArchitectureAssignment.Available(FFrame.FState.Model, mSelected) then
  begin
    Exit;
  end;
  mBox := FFrame.FParts.Assignment;
  mPpi := FFrame.CurrentPPI;
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(FFrame).GetSystemColor(clWindow))));
  mBox.Canvas.Font.Assign(FFrame.Font);
  mSize := TAtlasArchitectureAssignment.Measure(mBox.Canvas, FFrame.FState.Model, mSelected, mPpi);
  TAtlasArchitectureAssignment.Draw(mBox.Canvas, Rect(0, 0, Min(mSize.cx, mBox.Width), mSize.cy),
    FFrame.FState.Model, mSelected, mPpi, mColors);
end;

procedure TAtlasArchitectureFrame.TEvents.ExplainClick(Sender: TObject);
var
  mHint: string;
begin
  // Erneut: wieder nur der kurze Hinweis.
  mHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint);
  if FFrame.FParts.Explanation.Caption = mHint then
  begin
    FFrame.FParts.Explanation.Caption := TAtlasArchitectureAssignment.Explanation(FFrame.FState.Model);
  end
  else
  begin
    FFrame.FParts.Explanation.Caption := mHint;
  end;
end;

{ TAtlasArchitectureFrame }

constructor TAtlasArchitectureFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FState.ScopeValue := cScopeValues[0];
  FState.ShowResolution := True;
  FState.Sort.Column := TAtlasArchColumn.Total;
  FState.Sort.Descending := True;
  FState.Events := TEvents.Create(Self);
  BuildTop(Self);
  BuildResolution(Self);
  BuildFilterAndStatus(Self);
  BuildOverview(Self);
  BuildCentral(Self);
  BuildSubsystems(Self);
  BuildCyclesAndCrossLinks(Self);
  BuildComparison(Self);
end;

procedure TAtlasArchitectureFrame.CreateWnd;
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
  // Combo, Listen und Bäume halten ihre Einträge im Fenster: erst jetzt füllen.
  FillScope(Self);
  FillAll(Self);
end;

procedure TAtlasArchitectureFrame.SetScopeValue(const AValue: string);
begin
  FState.ScopeValue := cScopeValues[Ord(AValue = cScopeValues[1])];
  FillScope(Self);
end;

procedure TAtlasArchitectureFrame.SetIncludeLibrary(AValue: Boolean);
begin
  FState.Updating := True;
  try
    FParts.LibraryUnits.Checked := AValue;
    FState.IncludeLibrary := AValue;
  finally
    FState.Updating := False;
  end;
end;

function TAtlasArchitectureFrame.GetResolutionValue: Double;
begin
  Result := FParts.Resolution.Value;
end;

procedure TAtlasArchitectureFrame.SetResolutionValue(AValue: Double);
begin
  FParts.Resolution.Value := AValue;
  UpdateResolutionInfo(Self, FParts.Resolution.Value);
end;

procedure TAtlasArchitectureFrame.SetShowResolution(AValue: Boolean);
begin
  FState.ShowResolution := AValue;
  FParts.ResolutionCaption.Visible := AValue;
  FParts.Resolution.Visible := AValue;
  FParts.ResolutionInfo.Visible := AValue;
end;

procedure TAtlasArchitectureFrame.SetModel(const AModel: TAtlasArchitectureModel);
begin
  FState.Model := AModel;
  FState.HasModel := True;
  FState.MessageText := '';
  FParts.Map.SetModel(FState.Model);
  FParts.Map.State.Filter := FParts.Filter.Text;
  FillAll(Self);
  UpdateResolutionInfo(Self, FParts.Resolution.Value);
end;

procedure TAtlasArchitectureFrame.SetMessage(const AText: string; AKeep: Boolean);
begin
  FState.MessageText := AText;
  if not AKeep then
  begin
    FState.Model := Default(TAtlasArchitectureModel);
    FState.HasModel := False;
    FParts.Map.SetModel(FState.Model);
    FillAll(Self);
    UpdateResolutionInfo(Self, FParts.Resolution.Value);
  end;
  UpdateStatus(Self);
end;

procedure TAtlasArchitectureFrame.ShowCostRanking;
begin
  FState.Sort.Column := TAtlasArchColumn.Total;
  FState.Sort.Descending := True;
  FParts.Pages.ActivePage := FParts.Central.Parent as TTabSheet;
  FillCentral(Self);
end;

procedure TAtlasArchitectureFrame.OpenUnit(AUnit: Integer);
var
  mFileName: string;
begin
  if (AUnit < 0) or (AUnit > High(FState.Model.Units)) or (FState.Model.Units[AUnit].FileName = '') then
  begin
    Exit;
  end;
  mFileName := FState.Model.FullPath(FState.Model.Units[AUnit].FileName);
  if (GetKeyState(VK_CONTROL) < 0) and Assigned(FHandlers.OnUnitRelations) then
  begin
    FHandlers.OnUnitRelations(mFileName);
  end
  else if Assigned(FHandlers.OnOpenUnit) then
  begin
    FHandlers.OnOpenUnit(mFileName);
  end;
end;

procedure TAtlasArchitectureFrame.OpenLink(const ALink: TAtlasArchLink);
begin
  if (ALink.FileName = '') or (ALink.Line <= 0) then
  begin
    OpenUnit(ALink.Source);
  end
  else if Assigned(FHandlers.OnOpenLocation) then
  begin
    FHandlers.OnOpenLocation(FState.Model.FullPath(ALink.FileName), ALink.Line, Max(1, ALink.Character));
  end;
end;

procedure TAtlasArchitectureFrame.FillSubsystemsMenu;
begin
  FParts.SubsystemsMenu.Items.Clear;
  AddSubsystemItems(Self);
  if FParts.SubsystemsMenu.Items.Count > 0 then
  begin
    AddMenuCommands(Self);
  end;
end;

function TAtlasArchitectureFrame.ListText(AList: TAtlasArchFrameList): TArray<string>;
begin
  case AList of
    TAtlasArchFrameList.Central:
      Result := ItemsText(FParts.Central);
    TAtlasArchFrameList.Subsystems:
      Result := NodesText(FParts.Subsystems);
    TAtlasArchFrameList.Cycles:
      Result := NodesText(FParts.Cycles);
    TAtlasArchFrameList.CrossLinks:
      Result := ItemsText(FParts.CrossLinks);
  else
    Result := NodesText(FParts.Comparison);
  end;
end;

end.
