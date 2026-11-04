unit Atlas.UI.Results.Frame;

// Inhalt des Ergebnisfensters (#400), reine VCL: oben eine Titelzeile, darunter
// ein Baum. Fundstellen (Referenzen, Implementierungen) stehen nach Unit
// gruppiert, je Zeile „Zeile: Text“; Hierarchien (Aufrufer, Aufrufe,
// Vorfahren, Nachfahren) laden ihre nächste Ebene erst beim Aufklappen über
// OnExpand. Doppelklick oder Enter springt über OnOpen zur Stelle. Die Liste
// „Atlas-Änderungen“ (#721) zeigt die Sätze des Änderungsprotokolls mit ihren
// Dateien; Doppelklick oder Enter zeigt den Unterschied (OnChangeDiff), das
// Kontextmenü nimmt einen Satz zurück oder stellt ihn wieder her. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code. Die IDE-Schicht bettet den Frame in ein
// andockbares Fenster ein. Vor dem Titel steht das Atlas-Symbol (#751).
// Die Liste der persönlichen Notizen (#545) zeigt je Datei „Zeile: Titel“ und
// verwaiste Notizen in einer Gruppe am Ende; Doppelklick oder Enter springt,
// das Kontextmenü bearbeitet oder löscht die Notiz (Entf löscht ebenfalls).
// Verwendungen mit erschlossenen Treffern (#1119) stehen in zwei Abschnitten,
// „Sicher (n)“ und „Erschlossen (n) · vor dem Umbenennen prüfen“, darin nach
// Unit gruppiert; erschlossene Zeilen tragen ≈ und ihren Grund, der Hinweis
// unter der Maus erklärt ihn. „Nur sichere“ in der Titelzeile blendet die
// erschlossenen aus. Erschlossene Aufrufer der Hierarchie sind ebenso markiert.
// Aufrufhierarchien (#1122) lassen sich als Diagramm zeigen: Umschalter
// „Diagramm“ in der Titelzeile (nur mit DiagramAllowed, also
// callHierarchy.diagram), darunter eine Leiste mit Richtung (ausgehend oder
// eingehend, lädt mit denselben Wurzeln neu), „Nur Projekt-Units“,
// „Einpassen“ und „Als HTML speichern …“; die Ansicht selbst ist
// TAtlasCallDiagramView, ihre Ebenen kommen über OnExpand wie im Baum.
// Ein Weg zwischen Symbolen (#1117) erscheint statt des Baums als gezeichnete
// Kette (TAtlasSymbolPathChain) mit Statuszeile; „In Architekturkarte
// zeigen“ meldet die Units des ersten Wegs über OnShowRoute.
// Die Auswirkungsanalyse (#1120) steht in drei Abschnitten: „Direkt“ (Ebene 1),
// „Indirekt“ als Baum über die verursachende Stelle und „Betroffene Tests“;
// Formularbindungen hängen unter ihrer Stelle, erreichte Grenzen stehen am
// Ende. In der Titelzeile wählt „Tiefe“ 1–5 (OnImpactDepth rechnet neu), und
// „Betroffene Tests ausführen“ gibt die Tests an OnImpactRunTests.
// Datenfluss (#690): je Stelle „Art: Ausdruck · über X   Datei:Zeile: Quelltextzeile“, zusammengefasste
// Stellen mit ihren Fundorten darunter, dann die Quellen bzw. Ziele (← bzw. →), die beim Aufklappen über
// OnFlowExpand die nächste Ebene holen, bis zur Tiefengrenze. Konstanten, Stellen außerhalb des Projekts und
// Zyklen bleiben Blätter. Oben die Filter „Nur Projektcode“ und „Tests ausblenden“ (OnFlowFilter).
// Issues zu einer Methode (#1275): je Issue eine Zeile, die Commits zugeklappt darunter; Klick (oder Enter) auf ein
// Issue meldet OnIssueOpen, Doppelklick (oder Enter) auf einen Commit OnIssueCommit. SetIssueText ersetzt den Text
// eines Issues, sobald Titel und Zustand geladen sind.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Results.DataFlow,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.Core.Undo.Contract,
  Atlas.UI.Results.CallDiagram,
  Atlas.Core.SymbolPath.Model,
  Atlas.UI.SymbolPath.Chain;

type
  TAtlasResultsOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);
  TAtlasHierarchyExpand = reference to function(ADirection: TAtlasHierarchyDirection;
    const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
  /// <summary>Satz (#721) zurücknehmen bzw. wiederherstellen.</summary>
  TAtlasChangeSetAction = reference to procedure(ASetId: Integer);
  /// <summary>Unterschied eines Satzes zeigen; AFileName = '' für alle Dateien.</summary>
  TAtlasChangeDiff = reference to procedure(ASetId: Integer; const AFileName: string);
  /// <summary>Eintrag einer Liste mit Kennung (etwa eine Notiz, #545) bearbeiten bzw. löschen.</summary>
  TAtlasResultsItemAction = reference to procedure(const AItemId: string);

  /// <summary>Eintrag einer Liste mit Kennung: Text, Ort für den Sprung (Line 0-basiert).</summary>
  TAtlasResultsItem = record
    Id: string;
    Caption: string;
    FileName: string;
    Line: Integer;
  end;

  /// <summary>Gruppe einer Liste mit Kennungen (etwa die Notizen einer Datei).</summary>
  TAtlasResultsItemGroup = record
    Caption: string;
    FileName: string;
    Items: TArray<TAtlasResultsItem>;
  end;

  /// <summary>Liste mit Kennungen, die ein Modul zeigt (#1455; zuerst die Notizen, #545). Owner nennt den
  /// Besitzer („notes“); EditCaption bzw. DeleteCaption '' lassen den Eintrag im Kontextmenü weg. Entf löscht,
  /// solange OnDelete gesetzt ist.</summary>
  TAtlasResultsItemList = record
    Owner: string;
    Title: string;
    Groups: TArray<TAtlasResultsItemGroup>;
    /// <summary>Diesen Eintrag wählen; '' = den ersten.</summary>
    SelectId: string;
    EditCaption: string;
    DeleteCaption: string;
    OnEdit: TAtlasResultsItemAction;
    OnDelete: TAtlasResultsItemAction;
  end;
  /// <summary>Units eines Wegs (#1117) auf der Architekturkarte zeigen.</summary>
  TAtlasShowRoute = reference to procedure(const AUnits: TArray<string>);
  /// <summary>Auswirkungsanalyse (#1120) mit anderer Tiefe neu rechnen.</summary>
  TAtlasImpactDepthChange = reference to procedure(ADepth: Integer);
  /// <summary>Betroffene Tests der gezeigten Analyse ausführen.</summary>
  TAtlasImpactRunTests = reference to procedure(const AImpact: TAtlasImpact);
  /// <summary>Nächste Ebene des Datenflusses (#690) unter ASource; APath: Schlüssel der Vorfahren samt ASource.
  /// </summary>
  TAtlasDataFlowExpand = reference to function(ADirection: TAtlasDataFlowDirection;
    const ASource: TAtlasDataFlowSymbol; const APath: TArray<string>): TAtlasDataFlowResult;
  /// <summary>Filter des Datenflusses geändert: die erste Ebene neu holen.</summary>
  TAtlasDataFlowFilter = reference to procedure(AOnlyProject, AExcludeTests: Boolean);
  /// <summary>Issue bzw. Commit (#1275) der Liste AList gewählt; AId wie in TAtlasResultIssue bzw.
  /// TAtlasResultCommit.</summary>
  TAtlasResultsIssueAction = reference to procedure(AList, AId: Integer);

  TAtlasResultsFrame = class(TFrame)
  private type
{$SCOPEDENUMS ON}
    TNodeKind = (Group, Entry, Hierarchy, Placeholder, ChangeSet, ChangeFile, Item, Flow, FlowPlace, FlowSource,
      Issue, Commit);
{$SCOPEDENUMS OFF}
    TNodeData = record
      Kind: TNodeKind;
      FileName: string;
      Line: Integer;
      Character: Integer;
      Item: TAtlasHierarchyItem;
      Loaded: Boolean;
      /// <summary>Kennung des Satzes (#721) und sein Zustand; bei Issue und Commit (#1275) deren Id.</summary>
      SetId: Integer;
      State: TAtlasChangeSetState;
      /// <summary>Kennung des Eintrags einer Liste mit Kennungen (#545, #1455).</summary>
      ItemId: string;
      /// <summary>Hinweis unter der Maus: Erklärung eines erschlossenen Treffers (#1119).</summary>
      Hint: string;
      /// <summary>Datenfluss (#690): Quelle, Pfad bis einschließlich der Quelle und Ebene ihrer Stelle.</summary>
      FlowSource: TAtlasDataFlowSymbol;
      FlowPath: TArray<string>;
      FlowLevel: Integer;
    end;
  private
    FTitle: TLabel;
    FSymbol: TAtlasSymbolImage;
    FTree: TTreeView;
    FData: TList<TNodeData>;
    FDirection: TAtlasHierarchyDirection;
    FOnOpen: TAtlasResultsOpen;
    FOnExpand: TAtlasHierarchyExpand;
    FMenu: TPopupMenu;
    FUndoItem: TMenuItem;
    FRedoItem: TMenuItem;
    FDiffItem: TMenuItem;
    FShowsChanges: Boolean;
    FOnChangeUndo: TAtlasChangeSetAction;
    FOnChangeRedo: TAtlasChangeSetAction;
    FOnChangeDiff: TAtlasChangeDiff;
    FItemEditItem: TMenuItem;
    FItemDeleteItem: TMenuItem;
    /// <summary>Gezeigte Liste mit Kennungen; Owner '' = keine.</summary>
    FItems: TAtlasResultsItemList;
    FOnlySure: TCheckBox;
    FRatedTitle: string;
    FRatedEntries: TArray<TAtlasResultEntry>;
    FSureCaption: string;
    FInferredCaption: string;
    FHintNode: TTreeNode;
    /// <summary>Aufrufdiagramm (#1122).</summary>
    FDiagramToggle: TCheckBox;
    FDiagramBar: TPanel;
    FOutgoing: TRadioButton;
    FIncoming: TRadioButton;
    FProjectOnly: TCheckBox;
    FFitButton: TButton;
    FSaveButton: TButton;
    FDiagram: TAtlasCallDiagramView;
    FRoots: TArray<TAtlasHierarchyItem>;
    FDiagramAllowed: Boolean;
    FUpdatingDiagram: Boolean;
    FHierarchyTitle: string;
    /// <summary>Weg zwischen Symbolen (#1117): Leiste, Statuszeile, Kette in einer Scrollbox.</summary>
    FPathPanel: TPanel;
    FPathStatus: TLabel;
    FPathMap: TButton;
    FPathBox: TScrollBox;
    FPathChain: TAtlasSymbolPathChain;
    FShowsPath: Boolean;
    FOnShowRoute: TAtlasShowRoute;
    FDepthLabel: TLabel;
    FDepth: TComboBox;
    FRunTests: TButton;
    FImpact: TAtlasImpact;
    FShowsImpact: Boolean;
    FOnImpactDepth: TAtlasImpactDepthChange;
    FOnImpactRunTests: TAtlasImpactRunTests;
    FFlowBar: TPanel;
    FOnlyProject: TCheckBox;
    FExcludeTests: TCheckBox;
    FShowsFlow: Boolean;
    FFlowDirection: TAtlasDataFlowDirection;
    FFlowMaxDepth: Integer;
    FSettingFilter: Boolean;
    FOnFlowExpand: TAtlasDataFlowExpand;
    FOnFlowFilter: TAtlasDataFlowFilter;
    FShowsIssues: Boolean;
    FIssueList: Integer;
    FOnIssueOpen: TAtlasResultsIssueAction;
    FOnIssueCommit: TAtlasResultsIssueAction;
    procedure ShowPathPanel(AVisible: Boolean);
    procedure TreeClick(Sender: TObject);
    procedure PathMapClick(Sender: TObject);
    procedure PathBoxResize(Sender: TObject);
    function AddImpactPlace(AParent: TTreeNode; APlace: Integer): TTreeNode;
    procedure AddImpactBranch(AParent: TTreeNode; ACause: Integer);
    procedure AddImpactForms(AParent: TTreeNode; const AForms: TArray<TAtlasImpactForm>);
    procedure DepthChange(Sender: TObject);
    procedure RunTestsClick(Sender: TObject);
    function AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
    function DataOf(ANode: TTreeNode): TNodeData;
    procedure AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
    procedure AddGroups(AParent: TTreeNode; const AGroups: TArray<TAtlasResultGroup>);
    procedure RenderRated;
    procedure OnlySureClick(Sender: TObject);
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Clear(const ATitle: string);
    procedure OpenSelected;
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    function SelectedSet: TNodeData;
    procedure MenuPopup(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure DiffClick(Sender: TObject);
    procedure ItemEditClick(Sender: TObject);
    procedure ItemDeleteClick(Sender: TObject);
    function IsCallHierarchy: Boolean;
    procedure UpdateDiagramControls;
    procedure SetDiagramAllowed(AValue: Boolean);
    function GetShowsDiagram: Boolean;
    procedure SetShowsDiagram(AValue: Boolean);
    procedure SetIsProjectFile(const AValue: TFunc<string, Boolean>);
    procedure DiagramToggleClick(Sender: TObject);
    procedure DirectionClick(Sender: TObject);
    procedure ProjectOnlyClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    function DiagramLoad(ADirection: TAtlasHierarchyDirection;
      const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
    procedure DiagramOpen(const AItem: TAtlasHierarchyItem);
    procedure AddFlowNodes(AParent: TTreeNode; const ANodes: TArray<TAtlasDataFlowNode>; ALevel: Integer;
      const APath: TArray<string>);
    procedure ExpandFlowSource(ANode: TTreeNode; var AllowExpansion: Boolean);
    procedure FlowFilterClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Fundstellen nach Unit gruppiert; alle Gruppen aufgeklappt.</summary>
    procedure ShowEntries(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
    /// <summary>Fundstellen nach Treffersicherheit (#1119): ohne erschlossene wie ShowEntries; sonst zwei Abschnitte
    /// mit ASureCaption bzw. AInferredCaption (Format mit der Anzahl), darin nach Unit gruppiert.</summary>
    procedure ShowRated(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>;
      const ASureCaption, AInferredCaption: string);
    /// <summary>Wurzeln einer Hierarchie; die erste Ebene wird gleich geladen.</summary>
    procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>); overload;
    /// <summary>Wie oben; AAsDiagram: Aufrufhierarchie gleich als Diagramm (#1122, nur mit DiagramAllowed).</summary>
    procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean); overload;
    /// <summary>Aufrufhierarchie in Richtung ADirection mit denselben Wurzeln neu laden (Baum und Diagramm).</summary>
    procedure SwitchDirection(ADirection: TAtlasHierarchyDirection);
    /// <summary>Diagramm als eigenständige HTML-Datei (#1122) mit dem Titel des Fensters.</summary>
    function DiagramHtml: string;
    /// <summary>Liste „Atlas-Änderungen“ (#721): neueste Sätze zuerst, je Satz seine Dateien (zugeklappt).
    /// AKeepSelection: den bisher gewählten Satz wieder wählen (nach Zurücknehmen).</summary>
    procedure ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
      AKeepSelection: Boolean);
    /// <summary>Unterschied, Zurücknehmen und Wiederherstellen für den gewählten Satz
    /// bzw. die gewählte Datei.</summary>
    procedure ShowSelectedDiff;
    procedure UndoSelected;
    procedure RedoSelected;
    /// <summary>Liste mit Kennungen eines Moduls (#1455, etwa die Notizen #545): je Gruppe ein Knoten, alles
    /// aufgeklappt.</summary>
    procedure ShowItems(const AList: TAtlasResultsItemList);
    /// <summary>Zeigt gerade die Liste mit Kennungen von AOwner?</summary>
    function ShowsItemsOf(const AOwner: string): Boolean;
    /// <summary>Aktionen der Liste von AOwner vergessen (Modul stoppt, Regel 3); die Liste bleibt sichtbar, ohne
    /// Bearbeiten und Löschen.</summary>
    procedure ReleaseItems(const AOwner: string);
    /// <summary>Weg zwischen Symbolen (#1117) als Kette; AMapAvailable: Knopf „In Architekturkarte zeigen“
    /// anbieten (Architekturübersicht an und ein Weg gefunden).</summary>
    procedure ShowSymbolPath(const ATitle: string; const AAnswer: TAtlasSymbolPathAnswer; AMapAvailable: Boolean);
    /// <summary>Statt der Kette nur ein Hinweis (Suche läuft, kein Server, Fehler).</summary>
    procedure ShowSymbolPathMessage(const ATitle, AText: string);
    /// <summary>Kennung des gewählten Eintrags einer Liste mit Kennungen; '' ohne.</summary>
    function SelectedItemId: string;
    procedure EditSelectedItem;
    procedure DeleteSelectedItem;
    /// <summary>Text einer Fundstelle: "12: Kunde.Laden;" bzw. mit Vorschau "alt  →  neu"; erschlossen
    /// "≈ 12: S.Speichern;  [über Interface]" (#1119).</summary>
    class function EntryText(const AEntry: TAtlasResultEntry): string; static;
    /// <summary>Kurzer Grund eines erschlossenen Treffers, etwa "über Interface"; '' bei sicheren.</summary>
    class function ReasonText(const AConfidence: TAtlasConfidence): string; static;
    /// <summary>Text eines Hierarchie-Eintrags: "Laden · TKunde  (Kunden.pas:12)".</summary>
    class function HierarchyText(const AItem: TAtlasHierarchyItem): string; static;
    /// <summary>Auswirkungsanalyse (#1120): Abschnitte „Direkt“, „Indirekt“ (Baum über die Ursache),
    /// „Betroffene Tests“, darunter erreichte Grenzen; Tiefe und „Betroffene Tests ausführen“ in der Titelzeile.
    /// </summary>
    procedure ShowImpact(const ATitle: string; const AImpact: TAtlasImpact);
    /// <summary>Text einer betroffenen Stelle: wie HierarchyText, mit Art (Override, Umsetzung …), Zahl der
    /// Verwendungen und Test-Kennzeichen.</summary>
    class function ImpactPlaceText(const APlace: TAtlasImpactPlace): string; static;
    /// <summary>"Formular: OnClick = Button1Click  (Main.dfm:12)".</summary>
    class function ImpactFormText(const AForm: TAtlasImpactForm): string; static;
    /// <summary>Je erreichte Grenze eine Zeile; leer ohne.</summary>
    class function ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>; static;
    /// <summary>Zeigt gerade eine Auswirkungsanalyse (#1120).</summary>
    property ShowsImpact: Boolean read FShowsImpact;
    property Impact: TAtlasImpact read FImpact;
    property DepthBox: TComboBox read FDepth;
    property RunTestsButton: TButton read FRunTests;
    property OnImpactDepth: TAtlasImpactDepthChange read FOnImpactDepth write FOnImpactDepth;
    property OnImpactRunTests: TAtlasImpactRunTests read FOnImpactRunTests write FOnImpactRunTests;
    /// <summary>Datenfluss (#690): erste Ebene; AMaxDepth = navigation.dataFlow.maxDepth, die Filter wie
    /// angefragt.</summary>
    procedure ShowDataFlow(const ATitle: string; ADirection: TAtlasDataFlowDirection;
      const AResult: TAtlasDataFlowResult; AMaxDepth: Integer; AOnlyProject, AExcludeTests: Boolean);
    /// <summary>"Zuweisung" bzw. bei mehreren "3 Zuweisungen".</summary>
    class function FlowKindText(AKind: TAtlasDataFlowKind; ACount: Integer): string; static;
    /// <summary>"Zuweisung: A + B · über Summe  ⚠ unsicher: Zeiger   Haupt.pas:12: X := A + B;"; bei
    /// zusammengefassten Stellen ohne Fundort (der steht darunter).</summary>
    class function FlowNodeText(const ANode: TAtlasDataFlowNode): string; static;
    /// <summary>"Haupt.pas:12: X := A + B;".</summary>
    class function FlowPlaceText(const APlace: TAtlasDataFlowPlace): string; static;
    /// <summary>"← Summe  (Daten.pas:11)" bzw. "→ A …", mit "· Konstante", "· Zyklus", "· Tiefe erreicht".</summary>
    class function FlowSourceText(const AChild: TAtlasDataFlowChild; ADirection: TAtlasDataFlowDirection): string;
      static;
    property Tree: TTreeView read FTree;
    property OnOpen: TAtlasResultsOpen read FOnOpen write FOnOpen;
    property OnExpand: TAtlasHierarchyExpand read FOnExpand write FOnExpand;
    property Menu: TPopupMenu read FMenu;
    property Symbol: TAtlasSymbolImage read FSymbol;
    /// <summary>Zeigt gerade die Liste „Atlas-Änderungen“.</summary>
    property ShowsChanges: Boolean read FShowsChanges;
    property OnChangeUndo: TAtlasChangeSetAction read FOnChangeUndo write FOnChangeUndo;
    property OnChangeRedo: TAtlasChangeSetAction read FOnChangeRedo write FOnChangeRedo;
    property OnChangeDiff: TAtlasChangeDiff read FOnChangeDiff write FOnChangeDiff;
    /// <summary>„Nur sichere“ (#1119); sichtbar, solange erschlossene Treffer da sind.</summary>
    property OnlySure: TCheckBox read FOnlySure;
    /// <summary>Diagramm erlaubt (callHierarchy.diagram, #1122); aus: Umschalter fehlt, nur der Baum.</summary>
    property DiagramAllowed: Boolean read FDiagramAllowed write SetDiagramAllowed;
    /// <summary>Zeigt gerade das Aufrufdiagramm statt des Baums.</summary>
    property ShowsDiagram: Boolean read GetShowsDiagram write SetShowsDiagram;
    /// <summary>Gehört die Datei zu einem Projekt der Gruppe („Nur Projekt-Units“)? nil: alle.</summary>
    property IsProjectFile: TFunc<string, Boolean> write SetIsProjectFile; // lsp-ignore: write-only-property -- reicht nur an das Diagramm weiter
    property Direction: TAtlasHierarchyDirection read FDirection;
    property DiagramToggle: TCheckBox read FDiagramToggle;
    property DiagramBar: TPanel read FDiagramBar;
    property OutgoingButton: TRadioButton read FOutgoing;
    property IncomingButton: TRadioButton read FIncoming;
    property ProjectOnly: TCheckBox read FProjectOnly;
    property Diagram: TAtlasCallDiagramView read FDiagram;
    /// <summary>Zeigt gerade einen Weg zwischen Symbolen (#1117).</summary>
    property ShowsPath: Boolean read FShowsPath;
    property PathChain: TAtlasSymbolPathChain read FPathChain;
    property PathStatus: TLabel read FPathStatus;
    property PathMapButton: TButton read FPathMap;
    property OnShowRoute: TAtlasShowRoute read FOnShowRoute write FOnShowRoute;
    /// <summary>Zeigt gerade einen Datenfluss (#690).</summary>
    property ShowsFlow: Boolean read FShowsFlow;
    property OnlyProjectCheck: TCheckBox read FOnlyProject;
    property ExcludeTestsCheck: TCheckBox read FExcludeTests;
    property OnFlowExpand: TAtlasDataFlowExpand read FOnFlowExpand write FOnFlowExpand;
    property OnFlowFilter: TAtlasDataFlowFilter read FOnFlowFilter write FOnFlowFilter;
    /// <summary>Issues zu einer Methode bzw. Unit (#1275): je Issue eine Zeile, die Commits zugeklappt darunter.
    /// AList kennzeichnet die Liste für OnIssueOpen, OnIssueCommit und SetIssueText.</summary>
    procedure ShowIssues(const ATitle: string; AList: Integer; const AIssues: TArray<TAtlasResultIssue>);
    /// <summary>Text des Issues AId ersetzen, solange die Liste AList gezeigt wird; False sonst.</summary>
    function SetIssueText(AList, AId: Integer; const AText: string): Boolean;
    /// <summary>Gewähltes Issue öffnen bzw. Commit zeigen (Klick, Doppelklick, Enter).</summary>
    procedure OpenSelectedIssue;
    /// <summary>Zeigt gerade Issues zu einer Methode (#1275).</summary>
    property ShowsIssues: Boolean read FShowsIssues;
    property IssueList: Integer read FIssueList;
    property OnIssueOpen: TAtlasResultsIssueAction read FOnIssueOpen write FOnIssueOpen;
    property OnIssueCommit: TAtlasResultsIssueAction read FOnIssueCommit write FOnIssueCommit;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Vcl.Dialogs,
  Atlas.UI.Strings,
  Atlas.UI.Undo.Messages;

{$R *.dfm}

{ TAtlasResultsFrame }

constructor TAtlasResultsFrame.Create(AOwner: TComponent);
var
  Header: TPanel;
begin
  inherited Create(AOwner);
  FData := TList<TNodeData>.Create;
  // Titelzeile: Symbol (#751) und Titel.
  Header := TPanel.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.BevelOuter := bvNone;
  Header.ParentBackground := True;
  Header.Height := 22;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Header;
  FSymbol.LogicalSize := TAtlasSymbol.MenuSize;
  FSymbol.Align := alLeft;
  FSymbol.AlignWithMargins := True;
  // Filter „Nur sichere“ (#1119), rechts in der Titelzeile.
  FOnlySure := TCheckBox.Create(Self);
  FOnlySure.Parent := Header;
  FOnlySure.Align := alRight;
  FOnlySure.AlignWithMargins := True;
  FOnlySure.Caption := TAtlasStrings.Text(TAtlasTextId.ResultsOnlySure);
  FOnlySure.Width := 110;
  FOnlySure.Visible := False;
  FOnlySure.OnClick := OnlySureClick;
  // Umschalter Liste/Diagramm (#1122), nur bei Aufrufhierarchien.
  FDiagramToggle := TCheckBox.Create(Self);
  FDiagramToggle.Parent := Header;
  FDiagramToggle.Align := alRight;
  FDiagramToggle.AlignWithMargins := True;
  FDiagramToggle.Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramToggle);
  FDiagramToggle.Width := 90;
  FDiagramToggle.Visible := False;
  FDiagramToggle.OnClick := DiagramToggleClick;
  // Auswirkungsanalyse (#1120): Tiefe und Testlauf, rechts in der Titelzeile. Die Liste der Tiefen füllt
  // ShowImpact: Ein Kombinationsfeld braucht dafür ein Fenster.
  FRunTests := TButton.Create(Self);
  FRunTests.Parent := Header;
  FRunTests.Align := alRight;
  FRunTests.AlignWithMargins := True;
  FRunTests.Caption := TAtlasStrings.Text(TAtlasTextId.ImpactRunTests);
  FRunTests.Width := 170;
  FRunTests.Visible := False;
  FRunTests.OnClick := RunTestsClick;
  FDepth := TComboBox.Create(Self);
  FDepth.Parent := Header;
  FDepth.Align := alRight;
  FDepth.AlignWithMargins := True;
  FDepth.Style := csDropDownList;
  FDepth.Width := 44;
  FDepth.Visible := False;
  FDepth.OnChange := DepthChange;
  FDepthLabel := TLabel.Create(Self);
  FDepthLabel.Parent := Header;
  FDepthLabel.Align := alRight;
  FDepthLabel.AlignWithMargins := True;
  FDepthLabel.Layout := tlCenter;
  FDepthLabel.Caption := TAtlasStrings.Text(TAtlasTextId.ImpactDepth);
  FDepthLabel.Visible := False;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Header;
  FTitle.Align := alClient;
  FTitle.Layout := tlCenter;
  FTitle.AlignWithMargins := True;
  FTitle.ShowAccelChar := False;
  FTitle.EllipsisPosition := epEndEllipsis;
  // Leiste des Diagramms: Richtung, Filter, Einpassen, HTML.
  FDiagramBar := TPanel.Create(Self);
  FDiagramBar.Parent := Self;
  FDiagramBar.Align := alTop;
  FDiagramBar.Top := Header.Top + Header.Height;
  FDiagramBar.BevelOuter := bvNone;
  FDiagramBar.ParentBackground := True;
  FDiagramBar.Height := 26;
  FDiagramBar.Visible := False;
  FOutgoing := TRadioButton.Create(Self);
  FOutgoing.Parent := FDiagramBar;
  FOutgoing.Align := alLeft;
  FOutgoing.AlignWithMargins := True;
  FOutgoing.Width := 160;
  FOutgoing.Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramOutgoing);
  FOutgoing.OnClick := DirectionClick;
  FIncoming := TRadioButton.Create(Self);
  FIncoming.Parent := FDiagramBar;
  FIncoming.Align := alLeft;
  FIncoming.AlignWithMargins := True;
  FIncoming.Left := FOutgoing.Left + FOutgoing.Width + 1;
  FIncoming.Width := 150;
  FIncoming.Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramIncoming);
  FIncoming.OnClick := DirectionClick;
  FProjectOnly := TCheckBox.Create(Self);
  FProjectOnly.Parent := FDiagramBar;
  FProjectOnly.Align := alLeft;
  FProjectOnly.AlignWithMargins := True;
  FProjectOnly.Left := FIncoming.Left + FIncoming.Width + 1;
  FProjectOnly.Width := 140;
  FProjectOnly.Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramProjectOnly);
  FProjectOnly.Checked := True;
  FProjectOnly.OnClick := ProjectOnlyClick;
  FSaveButton := TButton.Create(Self);
  FSaveButton.Parent := FDiagramBar;
  FSaveButton.Align := alRight;
  FSaveButton.AlignWithMargins := True;
  FSaveButton.Width := 150;
  FSaveButton.Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramSaveHtml);
  FSaveButton.OnClick := SaveClick;
  FFitButton := TButton.Create(Self);
  FFitButton.Parent := FDiagramBar;
  FFitButton.Align := alRight;
  FFitButton.AlignWithMargins := True;
  FFitButton.Width := 90;
  FFitButton.Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramFit);
  FFitButton.OnClick := FitClick;
  FDiagram := TAtlasCallDiagramView.Create(Self);
  FDiagram.Parent := Self;
  FDiagram.Align := alClient;
  FDiagram.Visible := False;
  FDiagram.Hint := TAtlasStrings.Text(TAtlasTextId.CallDiagramHint);
  FDiagram.OnLoad := DiagramLoad;
  FDiagram.OnOpen := DiagramOpen;
  // Filter des Datenflusses (#690); nur sichtbar, solange er gezeigt wird.
  FFlowBar := TPanel.Create(Self);
  FFlowBar.Parent := Self;
  FFlowBar.Align := alTop;
  FFlowBar.Top := Header.Top + Header.Height;
  FFlowBar.BevelOuter := bvNone;
  FFlowBar.ParentBackground := True;
  FFlowBar.Height := 24;
  FFlowBar.Visible := False;
  FOnlyProject := TCheckBox.Create(Self);
  FOnlyProject.Parent := FFlowBar;
  FOnlyProject.Align := alLeft;
  FOnlyProject.AlignWithMargins := True;
  FOnlyProject.Width := 150;
  FOnlyProject.Caption := TAtlasStrings.Text(TAtlasTextId.DataFlowOnlyProject);
  FOnlyProject.OnClick := FlowFilterClick;
  FExcludeTests := TCheckBox.Create(Self);
  FExcludeTests.Parent := FFlowBar;
  FExcludeTests.Align := alLeft;
  FExcludeTests.AlignWithMargins := True;
  FExcludeTests.Left := FOnlyProject.Left + FOnlyProject.Width + 1;
  FExcludeTests.Width := 150;
  FExcludeTests.Caption := TAtlasStrings.Text(TAtlasTextId.DataFlowExcludeTests);
  FExcludeTests.OnClick := FlowFilterClick;
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.ShowLines := False;
  FTree.BorderStyle := bsNone;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnClick := TreeClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnExpanding := TreeExpanding;
  FTree.OnMouseMove := TreeMouseMove;
  FTree.ShowHint := True;
  // Kontextmenü der Liste „Atlas-Änderungen“ (#721); in anderen Listen ohne Einträge.
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FUndoItem := TMenuItem.Create(FMenu);
  FUndoItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionUndo);
  FUndoItem.OnClick := UndoClick;
  FMenu.Items.Add(FUndoItem);
  FRedoItem := TMenuItem.Create(FMenu);
  FRedoItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionRedo);
  FRedoItem.OnClick := RedoClick;
  FMenu.Items.Add(FRedoItem);
  FDiffItem := TMenuItem.Create(FMenu);
  FDiffItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionDiff);
  FDiffItem.OnClick := DiffClick;
  FMenu.Items.Add(FDiffItem);
  // Listen mit Kennungen (#545, #1455): Text setzt die Liste.
  FItemEditItem := TMenuItem.Create(FMenu);
  FItemEditItem.OnClick := ItemEditClick;
  FMenu.Items.Add(FItemEditItem);
  FItemDeleteItem := TMenuItem.Create(FMenu);
  FItemDeleteItem.OnClick := ItemDeleteClick;
  FMenu.Items.Add(FItemDeleteItem);
  FTree.PopupMenu := FMenu;
  // Weg zwischen Symbolen (#1117): anfangs verborgen, ersetzt den Baum.
  FPathPanel := TPanel.Create(Self);
  FPathPanel.Parent := Self;
  FPathPanel.Align := alClient;
  FPathPanel.BevelOuter := bvNone;
  FPathPanel.ShowCaption := False;
  FPathPanel.ParentBackground := True;
  FPathPanel.Visible := False;
  FPathMap := TButton.Create(Self);
  FPathMap.Parent := FPathPanel;
  FPathMap.Align := alTop;
  FPathMap.AlignWithMargins := True;
  FPathMap.Caption := TAtlasStrings.Text(TAtlasTextId.SymbolPathShowMap);
  FPathMap.OnClick := PathMapClick;
  FPathMap.Visible := False;
  FPathStatus := TLabel.Create(Self);
  FPathStatus.Parent := FPathPanel;
  FPathStatus.Align := alTop;
  FPathStatus.AlignWithMargins := True;
  FPathStatus.ShowAccelChar := False;
  FPathStatus.WordWrap := True;
  FPathBox := TScrollBox.Create(Self);
  FPathBox.Parent := FPathPanel;
  FPathBox.Align := alClient;
  FPathBox.BorderStyle := bsNone;
  FPathBox.VertScrollBar.Tracking := True;
  FPathBox.HorzScrollBar.Visible := False;
  FPathBox.OnResize := PathBoxResize;
  FPathChain := TAtlasSymbolPathChain.Create(Self);
  FPathChain.Parent := FPathBox;
  FPathChain.Left := 0;
  FPathChain.Top := 0;
  // Breite erst mit Fenster (PathBoxResize): ClientWidth der ScrollBox braucht ein Handle.
  FPathChain.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      if Assigned(FOnOpen) then
      begin
        FOnOpen(AFileName, ALine, ACharacter);
      end;
    end;
end;

destructor TAtlasResultsFrame.Destroy;
begin
  FData.Free;
  inherited;
end;

class function TAtlasResultsFrame.ReasonText(const AConfidence: TAtlasConfidence): string;
begin
  Result := '';
  if not AConfidence.Inferred then
  begin
    Exit;
  end;
  if AConfidence.Reason = 'interface' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInterface);
  end
  else if AConfidence.Reason = 'virtual' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonVirtual);
  end
  else if AConfidence.Reason = 'ambiguous' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonAmbiguous);
  end
  else if AConfidence.Reason = 'unresolved' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonUnresolved);
  end
  else if AConfidence.Reason = 'inactiveBranch' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInactiveBranch);
  end
  else if AConfidence.Reason = 'text' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonText);
  end
  else
  begin
    // Gründe neuerer Server: wie geliefert.
    Result := AConfidence.Reason;
  end;
end;

class function TAtlasResultsFrame.EntryText(const AEntry: TAtlasResultEntry): string;
begin
  Result := Format('%d: %s', [AEntry.Line + 1, AEntry.Text]);
  if AEntry.Detail <> '' then
  begin
    Result := Result + '  →  ' + AEntry.Detail;
  end;
  if AEntry.Confidence.Inferred then
  begin
    Result := '≈ ' + Result + '  [' + ReasonText(AEntry.Confidence) + ']';
  end;
end;

class function TAtlasResultsFrame.HierarchyText(const AItem: TAtlasHierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Detail <> '' then
  begin
    Result := Result + ' · ' + AItem.Detail;
  end;
  if AItem.FileName <> '' then
  begin
    Result := Result + Format('  (%s:%d)', [ExtractFileName(AItem.FileName), AItem.Line + 1]);
  end;
  if AItem.Confidence.Inferred then
  begin
    Result := '≈ ' + Result + '  [' + ReasonText(AItem.Confidence) + ']';
  end;
end;

class function TAtlasResultsFrame.ImpactPlaceText(const APlace: TAtlasImpactPlace): string;
var
  Edge: string;
begin
  if APlace.Terminal then
  begin
    Result := APlace.Item.Name + ' · ' + TAtlasStrings.Text(TAtlasTextId.ImpactUnitLevel) +
      Format('  (%s:%d)', [ExtractFileName(APlace.Item.FileName), APlace.UseLine + 1]);
  end
  else
  begin
    Result := HierarchyText(APlace.Item);
  end;
  Edge := '';
  if APlace.Edge = 'reference' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeReference);
  end
  else if APlace.Edge = 'override' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeOverride);
  end
  else if APlace.Edge = 'baseMethod' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeBase);
  end
  else if APlace.Edge = 'interfaceMethod' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeInterface);
  end
  else if APlace.Edge = 'implementation' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeImplementation);
  end;
  if Edge <> '' then
  begin
    Result := Result + '  · ' + Edge;
  end;
  if APlace.UseCount > 1 then
  begin
    Result := Result + Format('  ×%d', [APlace.UseCount]);
  end;
  if APlace.Test <> '' then
  begin
    Result := Result + '  · Test';
  end;
end;

class function TAtlasResultsFrame.ImpactFormText(const AForm: TAtlasImpactForm): string;
begin
  Result := Format(TAtlasStrings.Text(TAtlasTextId.ImpactForm), [AForm.Text, ExtractFileName(AForm.FileName),
    AForm.Line + 1]);
end;

class function TAtlasResultsFrame.ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>;
begin
  Result := nil;
  if AImpact.DepthReached then
  begin
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitDepth), [AImpact.Depth,
      AImpact.Unexpanded])];
  end;
  if AImpact.CountReached then
  begin
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitCount), [AImpact.MaxPlaces])];
  end;
  if AImpact.TimeReached then
  begin
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitTime), [AImpact.TimeoutMs])];
  end;
end;

procedure TAtlasResultsFrame.AddImpactForms(AParent: TTreeNode; const AForms: TArray<TAtlasImpactForm>);
var
  Form: TAtlasImpactForm;
  Data: TNodeData;
begin
  for Form in AForms do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Entry;
    Data.FileName := Form.FileName;
    Data.Line := Form.Line;
    Data.Character := Form.Character;
    AddNode(AParent, ImpactFormText(Form), Data);
  end;
end;

function TAtlasResultsFrame.AddImpactPlace(AParent: TTreeNode; APlace: Integer): TTreeNode;
var
  Place: TAtlasImpactPlace;
  Data: TNodeData;
begin
  Place := FImpact.Places[APlace];
  Data := Default(TNodeData);
  Data.Kind := TNodeKind.Entry;
  // Doppelklick springt zur Verwendung der Ursache in der Stelle.
  Data.FileName := Place.Item.FileName;
  Data.Line := Place.UseLine;
  Data.Character := Place.UseCharacter;
  Data.Hint := Place.Item.Confidence.Explanation;
  Result := AddNode(AParent, ImpactPlaceText(Place), Data);
  AddImpactForms(Result, Place.Forms);
end;

procedure TAtlasResultsFrame.AddImpactBranch(AParent: TTreeNode; ACause: Integer);
var
  Child: Integer;
begin
  // Jede Stelle hat genau eine Ursache: Der Baum endet, Zyklen gibt es nicht.
  for Child in FImpact.Children(ACause) do
  begin
    AddImpactBranch(AddImpactPlace(AParent, Child), Child);
  end;
end;

procedure TAtlasResultsFrame.ShowImpact(const ATitle: string; const AImpact: TAtlasImpact);
var
  Data: TNodeData;
  Section, Node: TTreeNode;
  Index, Depth: Integer;
  Test: TAtlasImpactTest;
  Limit: string;
begin
  Clear(ATitle);
  FImpact := AImpact;
  FShowsImpact := True;
  FDepthLabel.Visible := True;
  FDepth.Visible := True;
  FRunTests.Visible := True;
  FRunTests.Enabled := Length(AImpact.Tests) > 0;
  if FDepth.Items.Count = 0 then
  begin
    for Depth := 1 to 5 do
    begin
      FDepth.Items.Add(IntToStr(Depth));
    end;
  end;
  FDepth.OnChange := nil;
  try
    FDepth.ItemIndex := AImpact.Depth - 1;
  finally
    FDepth.OnChange := DepthChange;
  end;
  Data := Default(TNodeData);
  Data.Kind := TNodeKind.Placeholder;
  FTree.Items.BeginUpdate;
  try
    Section := AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactDirect), [AImpact.LevelCount(1)]), Data);
    AddImpactForms(Section, AImpact.SymbolForms);
    for Index := 0 to High(AImpact.Places) do
    begin
      if AImpact.Places[Index].Level = 1 then
      begin
        AddImpactPlace(Section, Index);
      end;
    end;
    Section.Expand(False);
    Section := AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactIndirect), [AImpact.CountFrom(2)]), Data);
    for Index in AImpact.Children(-1) do
    begin
      if Length(AImpact.Children(Index)) > 0 then
      begin
        Node := AddImpactPlace(Section, Index);
        AddImpactBranch(Node, Index);
      end;
    end;
    Section.Expand(AImpact.CountFrom(2) <= 200);
    if Length(AImpact.Tests) = 0 then
    begin
      AddNode(nil, TAtlasStrings.Text(TAtlasTextId.ImpactNoTests), Data);
    end
    else
    begin
      Section := AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactTests), [Length(AImpact.Tests)]), Data);
      for Test in AImpact.Tests do
      begin
        Data.Kind := TNodeKind.Entry;
        Data.FileName := Test.FileName;
        Data.Line := Test.Line;
        Data.Character := 0;
        AddNode(Section, Test.Name + Format('  (%s:%d)', [ExtractFileName(Test.FileName), Test.Line + 1]),
          Data);
      end;
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Placeholder;
      Section.Expand(False);
    end;
    for Limit in ImpactLimitTexts(AImpact) do
    begin
      AddNode(nil, '⚠ ' + Limit, Data);
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

procedure TAtlasResultsFrame.DepthChange(Sender: TObject);
begin
  if FShowsImpact and (FDepth.ItemIndex >= 0) and Assigned(FOnImpactDepth) then
  begin
    FOnImpactDepth(FDepth.ItemIndex + 1);
  end;
end;

procedure TAtlasResultsFrame.RunTestsClick(Sender: TObject);
begin
  if FShowsImpact and (Length(FImpact.Tests) > 0) and Assigned(FOnImpactRunTests) then
  begin
    FOnImpactRunTests(FImpact);
  end;
end;

function TAtlasResultsFrame.AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
begin
  Result := FTree.Items.AddChild(AParent, AText);
  // Index in FData; 0 wäre nil, deshalb um eins verschoben.
  Result.Data := Pointer(NativeInt(FData.Add(AData) + 1));
end;

function TAtlasResultsFrame.DataOf(ANode: TTreeNode): TNodeData;
var
  Index: NativeInt;
begin
  Result := Default(TNodeData);
  Result.Kind := TNodeKind.Placeholder;
  if ANode = nil then
  begin
    Exit;
  end;
  Index := NativeInt(ANode.Data) - 1;
  if (Index >= 0) and (Index < FData.Count) then
  begin
    Result := FData[Integer(Index)];
  end;
end;

procedure TAtlasResultsFrame.ShowPathPanel(AVisible: Boolean);
begin
  FShowsPath := AVisible;
  FPathPanel.Visible := AVisible;
  FTree.Visible := not AVisible;
end;

procedure TAtlasResultsFrame.PathBoxResize(Sender: TObject);
begin
  FPathChain.Width := FPathBox.ClientWidth;
end;

procedure TAtlasResultsFrame.PathMapClick(Sender: TObject);
begin
  if Assigned(FOnShowRoute) and (Length(FPathChain.Answer.Routes) > 0) then
  begin
    FOnShowRoute(FPathChain.Answer.Routes[0].UnitNames);
  end;
end;

procedure TAtlasResultsFrame.ShowSymbolPath(const ATitle: string; const AAnswer: TAtlasSymbolPathAnswer;
  AMapAvailable: Boolean);
begin
  Clear(ATitle);
  ShowPathPanel(True);
  FPathStatus.Caption := TAtlasSymbolPathChain.StatusText(AAnswer);
  FPathMap.Visible := AMapAvailable and (Length(AAnswer.Routes) > 0);
  FPathChain.SetAnswer(AAnswer);
  FPathBox.VertScrollBar.Position := 0;
  // Nur im gezeigten Fenster; SetFocus in einem verborgenen löst eine Ausnahme aus.
  if FPathChain.Showing and FPathChain.CanFocus then
  begin
    FPathChain.SetFocus;
  end;
end;

procedure TAtlasResultsFrame.ShowSymbolPathMessage(const ATitle, AText: string);
begin
  Clear(ATitle);
  ShowPathPanel(True);
  FPathStatus.Caption := AText;
  FPathMap.Visible := False;
  FPathChain.SetAnswer(Default(TAtlasSymbolPathAnswer));
end;

procedure TAtlasResultsFrame.Clear(const ATitle: string);
begin
  // Andere Listen zeigen immer den Baum; der Umschalter behält seinen Stand für die nächste Aufrufhierarchie.
  FRoots := nil;
  ShowPathPanel(False);
  FShowsChanges := False;
  FItems := Default(TAtlasResultsItemList);
  FOnlySure.Visible := False;
  FShowsImpact := False;
  FDepthLabel.Visible := False;
  FDepth.Visible := False;
  FRunTests.Visible := False;
  FHintNode := nil;
  FTree.Hint := '';
  FShowsFlow := False;
  FFlowBar.Visible := False;
  FShowsIssues := False;
  FTitle.Caption := ATitle;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
  finally
    FTree.Items.EndUpdate;
  end;
  FData.Clear;
  UpdateDiagramControls;
end;

procedure TAtlasResultsFrame.AddGroups(AParent: TTreeNode; const AGroups: TArray<TAtlasResultGroup>);
var
  Group: TAtlasResultGroup;
  Entry: TAtlasResultEntry;
  Data: TNodeData;
  GroupNode: TTreeNode;
begin
  for Group in AGroups do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Group;
    Data.FileName := Group.FileName;
    GroupNode := AddNode(AParent, Group.Caption, Data);
    for Entry in Group.Entries do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Entry;
      Data.FileName := Entry.FileName;
      Data.Line := Entry.Line;
      Data.Character := Entry.Character;
      Data.Hint := Entry.Confidence.Explanation;
      AddNode(GroupNode, EntryText(Entry), Data);
    end;
    GroupNode.Expand(False);
  end;
end;

procedure TAtlasResultsFrame.ShowEntries(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
begin
  Clear(ATitle);
  FTree.Items.BeginUpdate;
  try
    AddGroups(nil, AGroups);
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

procedure TAtlasResultsFrame.ShowRated(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>;
  const ASureCaption, AInferredCaption: string);
begin
  FRatedTitle := ATitle;
  FRatedEntries := AEntries;
  FSureCaption := ASureCaption;
  FInferredCaption := AInferredCaption;
  RenderRated;
end;

procedure TAtlasResultsFrame.RenderRated;
var
  Sure, Inferred: TArray<TAtlasResultEntry>;
  Entry: TAtlasResultEntry;
  Data: TNodeData;
  Section: TTreeNode;
begin
  Sure := TAtlasResults.SureOnly(FRatedEntries);
  Inferred := nil;
  for Entry in FRatedEntries do
  begin
    if Entry.Confidence.Inferred then
    begin
      Inferred := Inferred + [Entry];
    end;
  end;
  if Length(Inferred) = 0 then
  begin
    ShowEntries(FRatedTitle, TAtlasResults.Group(FRatedEntries));
    Exit;
  end;
  Clear(FRatedTitle);
  FOnlySure.Visible := True;
  FTree.Items.BeginUpdate;
  try
    if FOnlySure.Checked then
    begin
      AddGroups(nil, TAtlasResults.Group(Sure));
    end
    else
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Placeholder;
      Section := AddNode(nil, Format(FSureCaption, [Length(Sure)]), Data);
      AddGroups(Section, TAtlasResults.Group(Sure));
      Section.Expand(False);
      Section := AddNode(nil, Format(FInferredCaption, [Length(Inferred)]), Data);
      AddGroups(Section, TAtlasResults.Group(Inferred));
      Section.Expand(False);
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

procedure TAtlasResultsFrame.OnlySureClick(Sender: TObject);
begin
  // Clear blendet den Filter aus und RenderRated wieder ein; Checked bleibt.
  if Length(FRatedEntries) > 0 then
  begin
    RenderRated;
  end;
end;

procedure TAtlasResultsFrame.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Node: TTreeNode;
begin
  Node := FTree.GetNodeAt(X, Y);
  if Node = FHintNode then
  begin
    Exit;
  end;
  FHintNode := Node;
  FTree.Hint := DataOf(Node).Hint;
  Application.CancelHint;
end;

procedure TAtlasResultsFrame.AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
var
  Item: TAtlasHierarchyItem;
  Data: TNodeData;
  Node: TTreeNode;
begin
  for Item in AItems do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Hierarchy;
    Data.FileName := Item.FileName;
    Data.Line := Item.Line;
    Data.Character := Item.Character;
    Data.Item := Item;
    Data.Hint := Item.Confidence.Explanation;
    Node := AddNode(AParent, HierarchyText(Item), Data);
    // Platzhalter, damit sich der Knoten aufklappen lässt; geladen wird erst dann.
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Placeholder;
    AddNode(Node, '…', Data);
  end;
end;

procedure TAtlasResultsFrame.ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>);
begin
  ShowHierarchy(ATitle, ADirection, ARoots, False);
end;

procedure TAtlasResultsFrame.ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean);
begin
  Clear(ATitle);
  FDirection := ADirection;
  FRoots := ARoots;
  FTree.Items.BeginUpdate;
  try
    AddHierarchy(nil, ARoots);
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
    FTree.Items[0].Expand(False);
  end;
  FHierarchyTitle := ATitle;
  UpdateDiagramControls;
  if AAsDiagram or FDiagramToggle.Checked then
  begin
    SetShowsDiagram(True);
  end;
end;

function TAtlasResultsFrame.IsCallHierarchy: Boolean;
begin
  Result := (Length(FRoots) > 0) and ((FDirection = TAtlasHierarchyDirection.Incoming) or
    (FDirection = TAtlasHierarchyDirection.Outgoing));
end;

procedure TAtlasResultsFrame.UpdateDiagramControls;
var
  Possible, Showing: Boolean;
begin
  Possible := FDiagramAllowed and IsCallHierarchy;
  FDiagramToggle.Visible := Possible;
  Showing := Possible and FDiagramToggle.Checked;
  FUpdatingDiagram := True;
  try
    FOutgoing.Checked := FDirection = TAtlasHierarchyDirection.Outgoing;
    FIncoming.Checked := FDirection = TAtlasHierarchyDirection.Incoming;
  finally
    FUpdatingDiagram := False;
  end;
  FDiagramBar.Visible := Showing;
  FDiagram.Visible := Showing;
  FTree.Visible := not Showing;
end;

procedure TAtlasResultsFrame.SetDiagramAllowed(AValue: Boolean);
begin
  FDiagramAllowed := AValue;
  if not AValue then
  begin
    SetShowsDiagram(False);
  end
  else
  begin
    UpdateDiagramControls;
  end;
end;

function TAtlasResultsFrame.GetShowsDiagram: Boolean;
begin
  Result := FDiagram.Visible;
end;

procedure TAtlasResultsFrame.SetShowsDiagram(AValue: Boolean);
begin
  AValue := AValue and FDiagramAllowed and IsCallHierarchy;
  FUpdatingDiagram := True;
  try
    FDiagramToggle.Checked := AValue;
  finally
    FUpdatingDiagram := False;
  end;
  // Erst beim Umschalten laden; ein Wechsel zurück zum Baum behält die geladenen Ebenen nicht.
  if AValue then
  begin
    FDiagram.ProjectOnly := FProjectOnly.Checked;
    FDiagram.ShowRoots(FDirection, FRoots);
  end;
  UpdateDiagramControls;
  if AValue and FDiagram.CanFocus and FDiagram.Showing then
  begin
    FDiagram.SetFocus;
  end;
end;

procedure TAtlasResultsFrame.SetIsProjectFile(const AValue: TFunc<string, Boolean>);
begin
  FDiagram.IsProjectFile := AValue;
end;

procedure TAtlasResultsFrame.SwitchDirection(ADirection: TAtlasHierarchyDirection);
const
  Titles: array[TAtlasHierarchyDirection] of TAtlasTextId = (TAtlasTextId.ResultsIncoming,
    TAtlasTextId.ResultsOutgoing, TAtlasTextId.ResultsSupertypes, TAtlasTextId.ResultsSubtypes);
var
  Roots: TArray<TAtlasHierarchyItem>;
  AsDiagram: Boolean;
begin
  if (Length(FRoots) = 0) or (ADirection = FDirection) then
  begin
    Exit;
  end;
  Roots := FRoots;
  AsDiagram := ShowsDiagram;
  ShowHierarchy(TAtlasStrings.Fmt(Titles[ADirection], [Roots[0].Name]), ADirection, Roots, AsDiagram);
end;

procedure TAtlasResultsFrame.DiagramToggleClick(Sender: TObject);
begin
  if not FUpdatingDiagram then
  begin
    SetShowsDiagram(FDiagramToggle.Checked);
  end;
end;

procedure TAtlasResultsFrame.DirectionClick(Sender: TObject);
begin
  if FUpdatingDiagram then
  begin
    Exit;
  end;
  if FOutgoing.Checked then
  begin
    SwitchDirection(TAtlasHierarchyDirection.Outgoing);
  end
  else if FIncoming.Checked then
  begin
    SwitchDirection(TAtlasHierarchyDirection.Incoming);
  end;
end;

procedure TAtlasResultsFrame.ProjectOnlyClick(Sender: TObject);
begin
  FDiagram.ProjectOnly := FProjectOnly.Checked;
end;

procedure TAtlasResultsFrame.FitClick(Sender: TObject);
begin
  FDiagram.FitView;
end;

function TAtlasResultsFrame.DiagramHtml: string;
begin
  Result := FDiagram.Html(FHierarchyTitle);
end;

procedure TAtlasResultsFrame.SaveClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.CallDiagramSaveFilter);
    Dialog.DefaultExt := 'html';
    Dialog.FileName := TAtlasStrings.Text(TAtlasTextId.CallDiagramCommand) + '.html';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not Dialog.Execute then
    begin
      Exit;
    end;
    TFile.WriteAllText(Dialog.FileName, DiagramHtml, TEncoding.UTF8);
    FTitle.Caption := FHierarchyTitle + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.CallDiagramSaved, [Dialog.FileName]);
  finally
    Dialog.Free;
  end;
end;

function TAtlasResultsFrame.DiagramLoad(ADirection: TAtlasHierarchyDirection;
  const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
begin
  Result := nil;
  if Assigned(FOnExpand) then
  begin
    Result := FOnExpand(ADirection, AItem);
  end;
end;

procedure TAtlasResultsFrame.DiagramOpen(const AItem: TAtlasHierarchyItem);
begin
  if Assigned(FOnOpen) and (AItem.FileName <> '') then
  begin
    FOnOpen(AItem.FileName, AItem.Line, AItem.Character);
  end;
end;

procedure TAtlasResultsFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  Index: NativeInt;
  Data: TNodeData;
  Children: TArray<TAtlasHierarchyItem>;
begin
  Data := DataOf(Node);
  if (Data.Kind = TNodeKind.FlowSource) and not Data.Loaded then
  begin
    ExpandFlowSource(Node, AllowExpansion);
    Exit;
  end;
  if (Data.Kind <> TNodeKind.Hierarchy) or Data.Loaded then
  begin
    Exit;
  end;
  Index := NativeInt(Node.Data) - 1;
  Data.Loaded := True;
  FData[Integer(Index)] := Data;
  Children := nil;
  if Assigned(FOnExpand) then
  begin
    Screen.Cursor := crHourGlass;
    try
      Children := FOnExpand(FDirection, Data.Item);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  FTree.Items.BeginUpdate;
  try
    Node.DeleteChildren;
    AddHierarchy(Node, Children);
  finally
    FTree.Items.EndUpdate;
  end;
  AllowExpansion := Node.HasChildren;
end;

procedure TAtlasResultsFrame.ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
  AKeepSelection: Boolean);
var
  ChangeSet: TAtlasChangeSet;
  Change: TAtlasFileChange;
  Data: TNodeData;
  SetNode, Selected: TTreeNode;
  PreviousId: Integer;
begin
  PreviousId := 0;
  if AKeepSelection and FShowsChanges then
  begin
    PreviousId := SelectedSet.SetId;
  end;
  Clear(ATitle);
  FShowsChanges := True;
  Selected := nil;
  FTree.Items.BeginUpdate;
  try
    for ChangeSet in ASets do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.ChangeSet;
      Data.SetId := ChangeSet.Id;
      Data.State := ChangeSet.State;
      SetNode := AddNode(nil, TAtlasUndoMessages.SetCaption(ChangeSet, ANow), Data);
      if ChangeSet.Id = PreviousId then
      begin
        Selected := SetNode;
      end;
      for Change in ChangeSet.Files do
      begin
        Data.Kind := TNodeKind.ChangeFile;
        Data.FileName := Change.FileName;
        AddNode(SetNode, TAtlasUndoMessages.FileCaption(Change), Data);
      end;
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if Selected <> nil then
  begin
    FTree.Selected := Selected;
  end
  else if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

function TAtlasResultsFrame.SelectedSet: TNodeData;
begin
  Result := DataOf(FTree.Selected);
  if not (Result.Kind in [TNodeKind.ChangeSet, TNodeKind.ChangeFile]) then
  begin
    Result := Default(TNodeData);
  end;
end;

procedure TAtlasResultsFrame.MenuPopup(Sender: TObject);
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  FUndoItem.Visible := FShowsChanges;
  FRedoItem.Visible := FShowsChanges;
  FDiffItem.Visible := FShowsChanges;
  FUndoItem.Enabled := (Data.SetId > 0) and (Data.State <> TAtlasChangeSetState.Undone);
  FRedoItem.Enabled := (Data.SetId > 0) and (Data.State <> TAtlasChangeSetState.Applied);
  FDiffItem.Enabled := Data.SetId > 0;
  FItemEditItem.Caption := FItems.EditCaption;
  FItemDeleteItem.Caption := FItems.DeleteCaption;
  FItemEditItem.Visible := (FItems.Owner <> '') and (FItems.EditCaption <> '') and Assigned(FItems.OnEdit);
  FItemDeleteItem.Visible := (FItems.Owner <> '') and (FItems.DeleteCaption <> '') and Assigned(FItems.OnDelete);
  FItemEditItem.Enabled := SelectedItemId <> '';
  FItemDeleteItem.Enabled := SelectedItemId <> '';
end;

procedure TAtlasResultsFrame.ShowItems(const AList: TAtlasResultsItemList);
var
  mGroup: TAtlasResultsItemGroup;
  mItem: TAtlasResultsItem;
  mData: TNodeData;
  mGroupNode, mNode, mSelected: TTreeNode;
begin
  Clear(AList.Title);
  FItems := AList;
  mSelected := nil;
  FTree.Items.BeginUpdate;
  try
    for mGroup in AList.Groups do
    begin
      mData := Default(TNodeData);
      mData.Kind := TNodeKind.Group;
      mData.FileName := mGroup.FileName;
      mGroupNode := AddNode(nil, mGroup.Caption, mData);
      for mItem in mGroup.Items do
      begin
        mData := Default(TNodeData);
        mData.Kind := TNodeKind.Item;
        mData.FileName := mItem.FileName;
        mData.Line := mItem.Line;
        mData.ItemId := mItem.Id;
        mNode := AddNode(mGroupNode, mItem.Caption, mData);
        if (AList.SelectId <> '') and (mItem.Id = AList.SelectId) then
        begin
          mSelected := mNode;
        end;
      end;
      mGroupNode.Expand(False);
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if mSelected <> nil then
  begin
    FTree.Selected := mSelected;
  end
  else if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

function TAtlasResultsFrame.ShowsItemsOf(const AOwner: string): Boolean;
begin
  Result := (AOwner <> '') and SameText(FItems.Owner, AOwner);
end;

procedure TAtlasResultsFrame.ReleaseItems(const AOwner: string);
begin
  if not ShowsItemsOf(AOwner) then
  begin
    Exit;
  end;
  FItems.OnEdit := nil;
  FItems.OnDelete := nil;
end;

function TAtlasResultsFrame.SelectedItemId: string;
begin
  Result := DataOf(FTree.Selected).ItemId;
end;

procedure TAtlasResultsFrame.EditSelectedItem;
var
  mId: string;
begin
  mId := SelectedItemId;
  if (mId <> '') and Assigned(FItems.OnEdit) then
  begin
    FItems.OnEdit(mId);
  end;
end;

procedure TAtlasResultsFrame.DeleteSelectedItem;
var
  mId: string;
begin
  mId := SelectedItemId;
  if (mId <> '') and Assigned(FItems.OnDelete) then
  begin
    FItems.OnDelete(mId);
  end;
end;

procedure TAtlasResultsFrame.ItemEditClick(Sender: TObject);
begin
  EditSelectedItem;
end;

procedure TAtlasResultsFrame.ItemDeleteClick(Sender: TObject);
begin
  DeleteSelectedItem;
end;

procedure TAtlasResultsFrame.ShowSelectedDiff;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeDiff) then
  begin
    FOnChangeDiff(Data.SetId, Data.FileName);
  end;
end;

procedure TAtlasResultsFrame.UndoSelected;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeUndo) then
  begin
    FOnChangeUndo(Data.SetId);
  end;
end;

procedure TAtlasResultsFrame.RedoSelected;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeRedo) then
  begin
    FOnChangeRedo(Data.SetId);
  end;
end;

procedure TAtlasResultsFrame.UndoClick(Sender: TObject);
begin
  UndoSelected;
end;

procedure TAtlasResultsFrame.RedoClick(Sender: TObject);
begin
  RedoSelected;
end;

procedure TAtlasResultsFrame.DiffClick(Sender: TObject);
begin
  ShowSelectedDiff;
end;

class function TAtlasResultsFrame.FlowKindText(AKind: TAtlasDataFlowKind; ACount: Integer): string;
const
  Singular: array[TAtlasDataFlowKind] of TAtlasTextId = (TAtlasTextId.DataFlowAssignment,
    TAtlasTextId.DataFlowVarArgument, TAtlasTextId.DataFlowOutArgument, TAtlasTextId.DataFlowInput,
    TAtlasTextId.DataFlowInitializer, TAtlasTextId.DataFlowLoop, TAtlasTextId.DataFlowCallerArgument,
    TAtlasTextId.DataFlowReturn, TAtlasTextId.DataFlowPropertyWrite, TAtlasTextId.DataFlowPropertyRead,
    TAtlasTextId.DataFlowModify, TAtlasTextId.DataFlowArgument, TAtlasTextId.DataFlowOutput, TAtlasTextId.DataFlowUse,
    TAtlasTextId.DataFlowConstant, TAtlasTextId.DataFlowOutside, TAtlasTextId.DataFlowAddress,
    TAtlasTextId.DataFlowPlace);
  Plural: array[TAtlasDataFlowKind] of TAtlasTextId = (TAtlasTextId.DataFlowAssignments,
    TAtlasTextId.DataFlowVarArguments, TAtlasTextId.DataFlowOutArguments, TAtlasTextId.DataFlowInputs,
    TAtlasTextId.DataFlowInitializers, TAtlasTextId.DataFlowLoops, TAtlasTextId.DataFlowCallerArguments,
    TAtlasTextId.DataFlowReturns, TAtlasTextId.DataFlowPropertyWrites, TAtlasTextId.DataFlowPropertyReads,
    TAtlasTextId.DataFlowModifies, TAtlasTextId.DataFlowArguments, TAtlasTextId.DataFlowOutputs,
    TAtlasTextId.DataFlowUses, TAtlasTextId.DataFlowConstants, TAtlasTextId.DataFlowOutsides,
    TAtlasTextId.DataFlowAddresses, TAtlasTextId.DataFlowPlaces);
begin
  if ACount > 1 then
  begin
    Result := Format('%d %s', [ACount, TAtlasStrings.Text(Plural[AKind])]);
  end
  else
  begin
    Result := TAtlasStrings.Text(Singular[AKind]);
  end;
end;

function UnsafeText(const AReason: string): string;
begin
  if AReason = 'pointer' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.DataFlowUnsafePointer);
  end
  else if AReason = 'address' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.DataFlowUnsafeAddress);
  end
  else if AReason = 'move' then
  begin
    Result := 'Move';
  end
  else if AReason = 'fillchar' then
  begin
    Result := 'FillChar';
  end
  else
  begin
    Result := AReason;
  end;
end;

class function TAtlasResultsFrame.FlowPlaceText(const APlace: TAtlasDataFlowPlace): string;
begin
  Result := Format('%s:%d: %s', [ExtractFileName(APlace.FileName), APlace.Line + 1, APlace.LineText]);
end;

class function TAtlasResultsFrame.FlowNodeText(const ANode: TAtlasDataFlowNode): string;
var
  Origin: TAtlasDataFlowOrigin;
begin
  Result := FlowKindText(ANode.Kind, Length(ANode.Places));
  if ANode.Detail <> '' then
  begin
    Result := Result + ': ' + ANode.Detail;
  end;
  if ANode.Via <> '' then
  begin
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.DataFlowVia, [ANode.Via]);
  end;
  // Herkunft eines Blatts nur, wo die Art sie nicht schon nennt.
  Origin := TAtlasDataFlowTree.Origin(ANode);
  case Origin of
    TAtlasDataFlowOrigin.Literal:
      Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginLiteral);
    TAtlasDataFlowOrigin.Open:
      Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginOpen);
    TAtlasDataFlowOrigin.Outside:
      if ANode.Kind <> TAtlasDataFlowKind.Outside then
      begin
        Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginOutside);
      end;
    TAtlasDataFlowOrigin.Address:
      Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginAddress);
    TAtlasDataFlowOrigin.None, TAtlasDataFlowOrigin.Input, TAtlasDataFlowOrigin.Output, TAtlasDataFlowOrigin.Use,
    TAtlasDataFlowOrigin.Constant: ;
  end;
  if ANode.Unsafe then
  begin
    Result := Result + '  ⚠ ' + TAtlasStrings.Fmt(TAtlasTextId.DataFlowUnsafe, [UnsafeText(ANode.UnsafeReason)]);
  end;
  if Length(ANode.Places) = 1 then
  begin
    Result := Result + '   ' + FlowPlaceText(ANode.Places[0]);
  end;
end;

class function TAtlasResultsFrame.FlowSourceText(const AChild: TAtlasDataFlowChild;
  ADirection: TAtlasDataFlowDirection): string;
begin
  if ADirection = TAtlasDataFlowDirection.Targets then
  begin
    Result := '→ ';
  end
  else
  begin
    Result := '← ';
  end;
  Result := Result + AChild.Source.Name;
  if AChild.Source.FileName <> '' then
  begin
    Result := Result + Format('  (%s:%d)', [ExtractFileName(AChild.Source.FileName), AChild.Source.Line + 1]);
  end;
  case AChild.Source.Leaf of
    TAtlasDataFlowLeaf.Constant:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafConstant);
    TAtlasDataFlowLeaf.Outside:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafOutside);
    TAtlasDataFlowLeaf.Cycle:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafCycle);
  else
    if AChild.DepthReached then
    begin
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafDepth);
    end;
  end;
end;

procedure TAtlasResultsFrame.AddFlowNodes(AParent: TTreeNode; const ANodes: TArray<TAtlasDataFlowNode>;
  ALevel: Integer; const APath: TArray<string>);
var
  Node: TAtlasDataFlowNode;
  Child: TAtlasDataFlowChild;
  Place: TAtlasDataFlowPlace;
  Data: TNodeData;
  FlowNode, SourceNode: TTreeNode;
begin
  for Node in ANodes do
  begin
    Place := TAtlasDataFlowTree.FirstPlace(Node);
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Flow;
    Data.FileName := Place.FileName;
    Data.Line := Place.Line;
    Data.Character := Place.Character;
    FlowNode := AddNode(AParent, FlowNodeText(Node), Data);
    for Child in TAtlasDataFlowTree.Children(Node, ALevel, FFlowMaxDepth) do
    begin
      Data := Default(TNodeData);
      if Child.Kind = TAtlasDataFlowChildKind.Place then
      begin
        Data.Kind := TNodeKind.FlowPlace;
        Data.FileName := Child.Place.FileName;
        Data.Line := Child.Place.Line;
        Data.Character := Child.Place.Character;
        AddNode(FlowNode, FlowPlaceText(Child.Place), Data);
        Continue;
      end;
      Data.Kind := TNodeKind.FlowSource;
      Data.FileName := Child.Source.FileName;
      Data.Line := Child.Source.Line;
      Data.Character := Child.Source.Character;
      Data.FlowSource := Child.Source;
      Data.FlowPath := TAtlasDataFlowTree.ChildPath(APath, Child.Source.Key);
      Data.FlowLevel := ALevel;
      Data.Loaded := not Child.Expandable;
      SourceNode := AddNode(FlowNode, FlowSourceText(Child, FFlowDirection), Data);
      if Child.Expandable then
      begin
        // Platzhalter, damit sich die Quelle aufklappen lässt; geladen wird erst dann.
        Data := Default(TNodeData);
        Data.Kind := TNodeKind.Placeholder;
        AddNode(SourceNode, '…', Data);
      end;
    end;
  end;
end;

procedure TAtlasResultsFrame.ShowDataFlow(const ATitle: string; ADirection: TAtlasDataFlowDirection;
  const AResult: TAtlasDataFlowResult; AMaxDepth: Integer; AOnlyProject, AExcludeTests: Boolean);
begin
  Clear(ATitle);
  FShowsFlow := True;
  FFlowDirection := ADirection;
  FFlowMaxDepth := TAtlasDataFlowTree.ClampDepth(AMaxDepth);
  FSettingFilter := True;
  try
    FOnlyProject.Checked := AOnlyProject;
    FExcludeTests.Checked := AExcludeTests;
  finally
    FSettingFilter := False;
  end;
  FFlowBar.Visible := True;
  FTree.Items.BeginUpdate;
  try
    AddFlowNodes(nil, AResult.Nodes, 1, TArray<string>.Create(AResult.Symbol.Key));
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

procedure TAtlasResultsFrame.ExpandFlowSource(ANode: TTreeNode; var AllowExpansion: Boolean);
var
  Index: NativeInt;
  Data: TNodeData;
  Flow: TAtlasDataFlowResult;
begin
  Data := DataOf(ANode);
  Index := NativeInt(ANode.Data) - 1;
  Data.Loaded := True;
  FData[Integer(Index)] := Data;
  Flow := Default(TAtlasDataFlowResult);
  if Assigned(FOnFlowExpand) then
  begin
    Screen.Cursor := crHourGlass;
    try
      Flow := FOnFlowExpand(FFlowDirection, Data.FlowSource, Data.FlowPath);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  FTree.Items.BeginUpdate;
  try
    ANode.DeleteChildren;
    AddFlowNodes(ANode, Flow.Nodes, Data.FlowLevel + 1, Data.FlowPath);
  finally
    FTree.Items.EndUpdate;
  end;
  AllowExpansion := ANode.HasChildren;
end;

procedure TAtlasResultsFrame.FlowFilterClick(Sender: TObject);
begin
  if FSettingFilter or not FShowsFlow or not Assigned(FOnFlowFilter) then
  begin
    Exit;
  end;
  FOnFlowFilter(FOnlyProject.Checked, FExcludeTests.Checked);
end;

procedure TAtlasResultsFrame.ShowIssues(const ATitle: string; AList: Integer; const AIssues: TArray<TAtlasResultIssue>);
var
  mIssue: TAtlasResultIssue;
  mCommit: TAtlasResultCommit;
  mData: TNodeData;
  mNode: TTreeNode;
begin
  Clear(ATitle);
  FShowsIssues := True;
  FIssueList := AList;
  FTree.Items.BeginUpdate;
  try
    for mIssue in AIssues do
    begin
      mData := Default(TNodeData);
      mData.Kind := TNodeKind.Issue;
      mData.SetId := mIssue.Id;
      mNode := AddNode(nil, mIssue.Text, mData);
      for mCommit in mIssue.Commits do
      begin
        mData := Default(TNodeData);
        mData.Kind := TNodeKind.Commit;
        mData.SetId := mCommit.Id;
        AddNode(mNode, mCommit.Text, mData);
      end;
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
  end;
end;

function TAtlasResultsFrame.SetIssueText(AList, AId: Integer; const AText: string): Boolean;
var
  mNode: TTreeNode;
  mData: TNodeData;
begin
  Result := False;
  if not FShowsIssues or (AList <> FIssueList) then
  begin
    Exit;
  end;
  mNode := FTree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    mData := DataOf(mNode);
    if (mData.Kind = TNodeKind.Issue) and (mData.SetId = AId) then
    begin
      mNode.Text := AText;
      Exit(True);
    end;
    mNode := mNode.getNextSibling;
  end;
end;

procedure TAtlasResultsFrame.OpenSelectedIssue;
var
  mData: TNodeData;
begin
  if not FShowsIssues then
  begin
    Exit;
  end;
  mData := DataOf(FTree.Selected);
  if (mData.Kind = TNodeKind.Issue) and Assigned(FOnIssueOpen) then
  begin
    FOnIssueOpen(FIssueList, mData.SetId);
  end
  else if (mData.Kind = TNodeKind.Commit) and Assigned(FOnIssueCommit) then
  begin
    FOnIssueCommit(FIssueList, mData.SetId);
  end;
end;

procedure TAtlasResultsFrame.TreeClick(Sender: TObject);
var
  mWhere: TPoint;
  mNode: TTreeNode;
begin
  // Klick auf die Zeile eines Issues (nicht auf das Aufklappzeichen) öffnet es (#1275).
  if not FShowsIssues or not FTree.HandleAllocated then
  begin
    Exit;
  end;
  mWhere := FTree.ScreenToClient(Mouse.CursorPos);
  if not (htOnItem in FTree.GetHitTestInfoAt(mWhere.X, mWhere.Y)) then
  begin
    Exit;
  end;
  mNode := FTree.GetNodeAt(mWhere.X, mWhere.Y);
  if (mNode <> nil) and (mNode = FTree.Selected) and (DataOf(mNode).Kind = TNodeKind.Issue) then
  begin
    OpenSelectedIssue;
  end;
end;

procedure TAtlasResultsFrame.OpenSelected;
var
  Data: TNodeData;
begin
  Data := DataOf(FTree.Selected);
  // Issues zu einer Methode (#1275): Issue öffnen, Commit zeigen.
  if Data.Kind in [TNodeKind.Issue, TNodeKind.Commit] then
  begin
    OpenSelectedIssue;
    Exit;
  end;
  // Atlas-Änderungen (#721): Doppelklick zeigt den Unterschied.
  if Data.Kind in [TNodeKind.ChangeSet, TNodeKind.ChangeFile] then
  begin
    ShowSelectedDiff;
    Exit;
  end;
  // Einträge mit Kennung (Notizen #545) springen zu ihrer Zeile, verwaiste Notizen zur zuletzt bekannten.
  if (Data.Kind in [TNodeKind.Entry, TNodeKind.Hierarchy, TNodeKind.Item, TNodeKind.Flow, TNodeKind.FlowPlace,
    TNodeKind.FlowSource]) and (Data.FileName <> '') and
    Assigned(FOnOpen) then
  begin
    FOnOpen(Data.FileName, Data.Line, Data.Character);
  end;
end;

procedure TAtlasResultsFrame.TreeDblClick(Sender: TObject);
begin
  // Ein Issue hat schon der Klick geöffnet; der Doppelklick klappt es nur auf.
  if DataOf(FTree.Selected).Kind = TNodeKind.Issue then
  begin
    Exit;
  end;
  OpenSelected;
end;

procedure TAtlasResultsFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end
  else if (Key = VK_DELETE) and (FItems.Owner <> '') and Assigned(FItems.OnDelete) then
  begin
    DeleteSelectedItem;
    Key := 0;
  end;
end;

end.
