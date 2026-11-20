unit Atlas.UI.Tests.ExplorerFrame;

// Inhalt des Fensters „Atlas-Tests“ (#1776), reine VCL:
// - oben (TAtlasTestsExplorerBar) die Wahl des Testprojekts (nur bei
//   mehreren), die Knöpfe „Alle ausführen“, „Ausgewählte ausführen“,
//   „Ausgewählte debuggen“ und „Neu einlesen“, darunter Filter, Suchfeld und
//   Statuszeile,
// - der Baum Testunit → Fixture → Test → Fall mit einem farbigen Punkt je
//   Zeile (grün, rot, gelb, grau, grauer Ring für veraltet), Mehrfachauswahl
//   mit Strg und Umschalt,
// - unter dem Baum der Tastenhinweis, darunter der Teiler und die
//   Einzelheiten zum gewählten Test (Meldung, erwartet, erhalten, Stacktrace)
//   und daneben als Reiter sein Protokoll (#2168), beides in
//   Atlas.UI.Tests.ExplorerDetails.
// Größen: Der Baum nimmt den freien Platz. Die Einzelheiten behalten die
// gezogene Höhe, geben bei kleinem Fenster aber nach, bis der Baum seine
// Mindesthöhe hat (TAtlasTestExplorerLayout); wird das Fenster wieder größer,
// kehren sie zur gezogenen Höhe zurück. Knöpfe und Filter brechen bei
// schmalem Fenster um, die Statuszeile kürzt mit „…“. Bei einem DPI-Wechsel
// werden die Punktbilder neu gezeichnet.
// Unter den Leisten die Testlisten (#2167, Atlas.UI.Tests.ListBar).
// Tasten im Baum: Enter springt zum Test, Strg+R führt die Auswahl aus,
// Strg+D debuggt sie. Die IDE-Schicht (Atlas.IDE.Tests.Explorer) setzt die
// Zeilen und die Ereignisse (SetHandlers). Die DFM ist leer; aufgebaut wird
// im Code, gefüllt erst mit Fenster (CreateWnd).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.ImgList,
  Vcl.Forms,
  Atlas.Core.Tests.Explorer,
  Atlas.UI.Tests.ExplorerDetails,
  Atlas.UI.Tests.ListBar,
  Atlas.UI.Foundation.FillFrame;

type
  /// <summary>Ereignisse des Fensters; nil = keins.</summary>
  TAtlasTestsExplorerHandlers = record
    OnRunAll: TProc;
    OnRunSelected: TProc;
    OnDebugSelected: TProc;
    OnRefresh: TProc;
    /// <summary>Filter oder Suche geändert.</summary>
    OnFilter: TProc;
    /// <summary>Anderes Testprojekt gewählt (Index).</summary>
    OnProject: TProc<Integer>;
    /// <summary>Zum Knoten springen (Index des Modells).</summary>
    OnOpenNode: TProc<Integer>;
    /// <summary>Fokussierter Knoten geändert (-1 ohne).</summary>
    OnSelect: TProc<Integer>;
    /// <summary>Zeile des Stacktraces öffnen (Datei, Zeile 0-basiert).</summary>
    OnOpenLine: TProc<string, Integer>;
  end;

  /// <summary>Obere Leisten des Fensters: Testprojekt, Knöpfe, Filter, Suche und Statuszeile. Die Steuerelemente
  /// gehören dem Frame und liegen auf ihm.</summary>
  TAtlasTestsExplorerBar = class(TComponent)
  private
    FFrame: TCustomFrame;
    FProjectBar: TPanel;
    FProject: TComboBox;
    FRunAll: TButton;
    FRunSelected: TButton;
    FDebugSelected: TButton;
    FRefresh: TButton;
    FFilterChecks: array[TAtlasTestFilter] of TCheckBox;
    FSearch: TEdit;
    FStatus: TLabel;
    FProjects: TArray<string>;
    FProjectIndex: Integer;
    FHandlers: TAtlasTestsExplorerHandlers;
    function Scaled96(AValue: Integer): Integer;
    function NewPanel(ATop, AHeight: Integer): TPanel;
    function NewFlow(ATop: Integer): TFlowPanel;
    function TextWidth(const AText: string): Integer;
    function NewButton(AParent: TWinControl; ALeft: Integer; const ACaption: string): TButton;
    procedure BuildProjectRow;
    function BuildButtonRow(ATop: Integer): Integer;
    function BuildFilterRow(ATop: Integer): Integer;
    procedure ButtonClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure ProjectChange(Sender: TObject);
  public
    /// <summary>Leisten oben auf AFrame anlegen.</summary>
    constructor Create(AFrame: TCustomFrame); reintroduce;
    procedure SetProjects(const ANames: TArray<string>; AIndex: Integer);
    /// <summary>Liste der Testprojekte füllen (braucht ein Fenster).</summary>
    procedure FillProjects;
    procedure SetStatus(const AStatus: string);
    procedure SetBusy(ABusy: Boolean);
    function Filters: TAtlasTestFilters;
    /// <summary>Genau die Filter AFilters ankreuzen (Befehl „Wackelnde Tests zeigen“, #1773); meldet OnFilter
    /// einmal.</summary>
    procedure SetFilters(AFilters: TAtlasTestFilters);
    function SearchText: string;
    property Handlers: TAtlasTestsExplorerHandlers read FHandlers write FHandlers;
    property StatusLabel: TLabel read FStatus;
  end;

  TAtlasTestsExplorerFrame = class(TAtlasFillFrame)
  private
    FBar: TAtlasTestsExplorerBar;
    FListBar: TAtlasTestsListBar;
    FTreeArea: TPanel;
    FTree: TTreeView;
    FDetails: TAtlasTestsExplorerDetails;
    FSplitter: TSplitter;
    FFooter: TLabel;
    FImages: TImageList;
    FRows: TArray<TAtlasTestRow>;
    FHandlers: TAtlasTestsExplorerHandlers;
    /// <summary>Höhe der Einzelheiten, die zuletzt gezogen wurde (Pixel bei CurrentPPI).</summary>
    FWantedDetails: Integer;
    /// <summary>Punktbilder in der Größe ASize (Pixel) zeichnen.</summary>
    procedure BuildImages(ASize: Integer);
    /// <summary>Teiler über den Einzelheiten.</summary>
    procedure BuildSplitter;
    /// <summary>Baum mit dem Tastenhinweis darunter; nimmt den übrigen Platz.</summary>
    procedure BuildTree;
    /// <summary>Höhe der Einzelheiten an den Platz anpassen (TAtlasTestExplorerLayout).</summary>
    procedure FitDetails;
    procedure SplitterMoved(Sender: TObject);
    /// <summary>Baumknoten zu FRows anlegen; Index je Zeile in AItems, der früher fokussierte Knoten in
    /// AFocusItem.</summary>
    procedure AddItems(AFocused: Integer; out AItems: TArray<TTreeNode>; out AFocusItem: TTreeNode);
    /// <summary>Testunits und Fixtures aufklappen, die früher gewählten Knoten wieder wählen.</summary>
    procedure Restore(const AItems: TArray<TTreeNode>; const AWasSelected: TArray<Integer>);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
  protected
    procedure FillControls; override;
    procedure Resize; override;
    procedure ChangeScale(AM, AD: Integer; AIsDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Ereignisse setzen; Default(TAtlasTestsExplorerHandlers) löst alle.</summary>
    procedure SetHandlers(const AHandlers: TAtlasTestsExplorerHandlers);
    /// <summary>Testprojekte (Anzeigenamen) und das gewählte; die Wahl steht nur bei mehreren da.</summary>
    procedure SetProjects(const ANames: TArray<string>; AIndex: Integer);
    /// <summary>Zeilen des Baums und Statuszeile; die Auswahl bleibt, wo die Knoten bleiben.</summary>
    procedure SetRows(const ARows: TArray<TAtlasTestRow>; const AStatus: string);
    /// <summary>Statuszeile allein (Lauf beginnt bzw. endet).</summary>
    procedure SetStatus(const AStatus: string);
    /// <summary>Einzelheiten zum gewählten Test.</summary>
    procedure SetDetails(const ALines: TArray<TAtlasTestStackLine>);
    /// <summary>Protokoll zum gewählten Test (#2168), ACount für den Reiter; AEnabled False = kein Reiter.</summary>
    procedure SetLog(const ALines: TArray<TAtlasTestStackLine>; ACount: Integer; AEnabled: Boolean);
    /// <summary>Knöpfe zum Ausführen sperren, solange ein Lauf im Gange ist.</summary>
    procedure SetBusy(ABusy: Boolean);
    function Filters: TAtlasTestFilters;
    function SearchText: string;
    /// <summary>Knoten (Indizes des Modells) der gewählten Zeilen.</summary>
    function SelectedNodes: TArray<Integer>;
    /// <summary>Knoten der fokussierten Zeile; -1 ohne.</summary>
    function FocusedNode: Integer;
    property Bar: TAtlasTestsExplorerBar read FBar;
    property ListBar: TAtlasTestsListBar read FListBar;
    property Tree: TTreeView read FTree;
    property Details: TAtlasTestsExplorerDetails read FDetails;
  end;

implementation

uses
  Atlas.UI.Tests.Strings,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.Core.Foundation.Calls;

{$R *.dfm}

type
  /// <summary>Zugriff auf die geschützte Schrift des Frames (E2362).</summary>
  TControlAccess = class(TControl);

const
  cBarHeight = 30;
  cGap = 6;
  cLabelWidth = 80;
  cComboWidth = 240;
  cButtonWidth = 140;
  cCheckWidth = 110;
  /// <summary>Kästchen eines Häkchens samt Abstand zum Text, logische Pixel.</summary>
  cCheckBox = 24;

  cSearchWidth = 180;
  cDetailsHeight = 140;
  /// <summary>Mindesthöhen von Baum (etwa vier Zeilen und der Tastenhinweis) und Einzelheiten, logische Pixel.
  /// </summary>
  cMinTreeHeight = 100;
  cMinDetailsHeight = 60;
  cSplitterHeight = 4;
  cDotSize = 16;
  /// <summary>Abstand des Punkts zum Rand: ein Viertel der Bildgröße.</summary>
  cDotInsetDivisor = 4;
  cBasePpi = 96;
  /// <summary>Farben der Punkte in der Reihenfolge von TAtlasTestNodeState.</summary>
  cStateColors: array[TAtlasTestNodeState] of TColor = ($00909090, $004BA02E, $00493AD7, $0009ABDB, $00909090);
  /// <summary>Hintergrund der Punktbilder, wird durchsichtig.</summary>
  cMaskColor = clFuchsia;

{ TAtlasTestsExplorerBar }

constructor TAtlasTestsExplorerBar.Create(AFrame: TCustomFrame);
var
  mStatusBar: TPanel;
  mTop: Integer;
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  FProjectIndex := -1;
  BuildProjectRow;
  mTop := BuildButtonRow(FProjectBar.Top + FProjectBar.Height);
  mTop := BuildFilterRow(mTop);
  mStatusBar := NewPanel(mTop, Scaled96(cBarHeight - cGap));
  // Volle Breite und mit „…“ gekürzt: Bei schmalem Fenster lief die Zahlenzeile sonst unter den Rand.
  FStatus := TLabel.Create(FFrame);
  FStatus.AutoSize := False;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;
  FStatus.ShowHint := True;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(Scaled96(cGap), Scaled96(cGap) div 2, Scaled96(cGap), 0);
  FStatus.Align := alClient;
  FStatus.Parent := mStatusBar;
end;

function TAtlasTestsExplorerBar.Scaled96(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FFrame.CurrentPPI, cBasePpi);
end;

function TAtlasTestsExplorerBar.NewPanel(ATop, AHeight: Integer): TPanel;
begin
  // alTop: Top und Height vor Align und Parent, sonst vertauscht die VCL die Reihenfolge.
  Result := TPanel.Create(FFrame);
  Result.Top := ATop;
  Result.Height := AHeight;
  Result.BevelOuter := bvNone;
  Result.Align := alTop;
  Result.Parent := FFrame;
end;

/// <summary>Fließende Leiste (alTop, wächst mit Umbrüchen): Knöpfe, Filter und Suche brechen bei schmalem Fenster
/// in weitere Zeilen um, statt sich zu überdecken.</summary>
function TAtlasTestsExplorerBar.NewFlow(ATop: Integer): TFlowPanel;
begin
  Result := TFlowPanel.Create(FFrame);
  Result.Top := ATop;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.AutoWrap := True;
  Result.AutoSize := True;
  Result.Align := alTop;
  Result.Parent := FFrame;
end;

/// <summary>Breite von AText in der Schrift des Frames.</summary>
function TAtlasTestsExplorerBar.TextWidth(const AText: string): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font := TControlAccess(FFrame).Font;
    Result := mBitmap.Canvas.TextWidth(AText);
  finally
    mBitmap.Free;
  end;
end;

function TAtlasTestsExplorerBar.NewButton(AParent: TWinControl; ALeft: Integer; const ACaption: string): TButton;
begin
  Result := TButton.Create(FFrame);
  Result.Caption := ACaption;
  Result.AlignWithMargins := True;
  Result.SetBounds(ALeft, Scaled96(cGap) div 2, Scaled96(cButtonWidth), Scaled96(cBarHeight - cGap));
  Result.OnClick := ButtonClick;
  Result.Parent := AParent;
end;

procedure TAtlasTestsExplorerBar.BuildProjectRow;
var
  mLabel: TLabel;
begin
  FProjectBar := NewPanel(0, Scaled96(cBarHeight));
  mLabel := TLabel.Create(FFrame);
  mLabel.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerProject);
  mLabel.SetBounds(Scaled96(cGap), Scaled96(cGap) + Scaled96(cGap) div 2, Scaled96(cLabelWidth),
    Scaled96(cBarHeight - 2 * cGap));
  mLabel.Parent := FProjectBar;
  FProject := TComboBox.Create(FFrame);
  FProject.Style := csDropDownList;
  FProject.SetBounds(mLabel.Left + mLabel.Width, Scaled96(cGap) div 2, Scaled96(cComboWidth),
    Scaled96(cBarHeight - cGap));
  FProject.OnChange := ProjectChange;
  FProject.Parent := FProjectBar;
  // Sichtbar erst bei mehreren Testprojekten (SetProjects).
  FProjectBar.Visible := False;
end;

function TAtlasTestsExplorerBar.BuildButtonRow(ATop: Integer): Integer;
var
  mBar: TFlowPanel;
  mLeft: Integer;
begin
  mBar := NewFlow(ATop);
  mLeft := Scaled96(cGap);
  FRunAll := NewButton(mBar, mLeft, TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerRunAll));
  Inc(mLeft, FRunAll.Width + Scaled96(cGap));
  FRunSelected := NewButton(mBar, mLeft, TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerRunSelected));
  Inc(mLeft, FRunSelected.Width + Scaled96(cGap));
  FDebugSelected := NewButton(mBar, mLeft, TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDebugSelected));
  Inc(mLeft, FDebugSelected.Width + Scaled96(cGap));
  FRefresh := NewButton(mBar, mLeft, TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerRefresh));
  Result := mBar.Top + mBar.Height;
end;

function TAtlasTestsExplorerBar.BuildFilterRow(ATop: Integer): Integer;
const
  cFilterTexts: array[TAtlasTestFilter] of TAtlasTestsTextId = (TAtlasTestsTextId.ExplorerFilterFailed,
    TAtlasTestsTextId.ExplorerFilterNotRun, TAtlasTestsTextId.ExplorerFilterStale,
    TAtlasTestsTextId.ExplorerFilterSlow, TAtlasTestsTextId.ExplorerFilterFlaky);
var
  mBar: TFlowPanel;
  mLeft: Integer;
  mFilter: TAtlasTestFilter;
begin
  mBar := NewFlow(ATop);
  mLeft := Scaled96(cGap);
  for mFilter := Low(TAtlasTestFilter) to High(TAtlasTestFilter) do
  begin
    FFilterChecks[mFilter] := TCheckBox.Create(FFrame);
    FFilterChecks[mFilter].Caption := TAtlasTestsStrings.Text(cFilterTexts[mFilter]);
    // Breite nach dem Text, sonst läuft „Nicht gelaufen“ in den nächsten Filter.
    FFilterChecks[mFilter].AlignWithMargins := True;
    FFilterChecks[mFilter].SetBounds(mLeft, Scaled96(cGap) div 2,
      TextWidth(FFilterChecks[mFilter].Caption) + Scaled96(cCheckBox), Scaled96(cBarHeight - cGap));
    FFilterChecks[mFilter].OnClick := FilterChange;
    FFilterChecks[mFilter].Parent := mBar;
    Inc(mLeft, Scaled96(cCheckWidth));
  end;
  FSearch := TEdit.Create(FFrame);
  FSearch.TextHint := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerSearchHint);
  FSearch.AlignWithMargins := True;
  FSearch.SetBounds(mLeft, Scaled96(cGap) div 2, Scaled96(cSearchWidth), Scaled96(cBarHeight - cGap));
  FSearch.OnChange := FilterChange;
  FSearch.Parent := mBar;
  Result := mBar.Top + mBar.Height;
end;

procedure TAtlasTestsExplorerBar.ButtonClick(Sender: TObject);
begin
  if Sender = FRunAll then
  begin
    TAtlasCalls.Call(FHandlers.OnRunAll);
  end
  else if Sender = FRunSelected then
  begin
    TAtlasCalls.Call(FHandlers.OnRunSelected);
  end
  else if Sender = FDebugSelected then
  begin
    TAtlasCalls.Call(FHandlers.OnDebugSelected);
  end
  else if Sender = FRefresh then
  begin
    TAtlasCalls.Call(FHandlers.OnRefresh);
  end;
end;

procedure TAtlasTestsExplorerBar.FilterChange(Sender: TObject);
begin
  TAtlasCalls.Call(FHandlers.OnFilter);
end;

procedure TAtlasTestsExplorerBar.ProjectChange(Sender: TObject);
begin
  FProjectIndex := FProject.ItemIndex;
  if Assigned(FHandlers.OnProject) then
  begin
    FHandlers.OnProject(FProjectIndex);
  end;
end;

procedure TAtlasTestsExplorerBar.SetProjects(const ANames: TArray<string>; AIndex: Integer);
begin
  FProjects := ANames;
  FProjectIndex := AIndex;
  FProjectBar.Visible := Length(ANames) > 1;
  if FFrame.HandleAllocated then
  begin
    FillProjects;
  end;
end;

procedure TAtlasTestsExplorerBar.FillProjects;
var
  mName: string;
begin
  FProject.HandleNeeded;
  FProject.Items.BeginUpdate;
  try
    FProject.Items.Clear;
    for mName in FProjects do
    begin
      FProject.Items.Add(mName);
    end;
  finally
    FProject.Items.EndUpdate;
  end;
  FProject.ItemIndex := FProjectIndex;
end;

procedure TAtlasTestsExplorerBar.SetStatus(const AStatus: string);
begin
  FStatus.Caption := AStatus;
  FStatus.Hint := AStatus;
end;

procedure TAtlasTestsExplorerBar.SetBusy(ABusy: Boolean);
begin
  FRunAll.Enabled := not ABusy;
  FRunSelected.Enabled := not ABusy;
  FDebugSelected.Enabled := not ABusy;
end;

function TAtlasTestsExplorerBar.Filters: TAtlasTestFilters;
var
  mFilter: TAtlasTestFilter;
begin
  Result := [];
  for mFilter := Low(TAtlasTestFilter) to High(TAtlasTestFilter) do
  begin
    if FFilterChecks[mFilter].Checked then
    begin
      Include(Result, mFilter);
    end;
  end;
end;

procedure TAtlasTestsExplorerBar.SetFilters(AFilters: TAtlasTestFilters);
var
  mFilter: TAtlasTestFilter;
begin
  for mFilter := Low(TAtlasTestFilter) to High(TAtlasTestFilter) do
  begin
    // Ohne OnClick: Jedes Kästchen meldete sonst einzeln.
    FFilterChecks[mFilter].OnClick := nil;
    try
      FFilterChecks[mFilter].Checked := mFilter in AFilters;
    finally
      FFilterChecks[mFilter].OnClick := FilterChange;
    end;
  end;
  TAtlasCalls.Call(FHandlers.OnFilter);
end;

function TAtlasTestsExplorerBar.SearchText: string;
begin
  Result := Trim(FSearch.Text);
end;

{ TAtlasTestsExplorerFrame }

/// <summary>AValue (logische Pixel) in Pixeln bei der DPI von AFrame.</summary>
function FramePixels(AFrame: TCustomFrame; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AFrame.CurrentPPI, cBasePpi);
end;

constructor TAtlasTestsExplorerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildImages(FramePixels(Self, cDotSize));
  FBar := TAtlasTestsExplorerBar.Create(Self);
  FDetails := TAtlasTestsExplorerDetails.Create(Self, cDetailsHeight);
  FWantedDetails := FDetails.Panel.Height;
  BuildSplitter;
  BuildTree;
  FListBar := TAtlasTestsListBar.Create(Self, FTree);
end;

procedure TAtlasTestsExplorerFrame.BuildSplitter;
begin
  FSplitter := TSplitter.Create(Self);
  FSplitter.Height := FramePixels(Self, cSplitterHeight);
  // Erst über die Einzelheiten stellen, dann ausrichten: Die VCL ordnet alBottom nach der Unterkante. Ohne Top
  // lag der Teiler über dem Tastenhinweis und zog dessen Höhe statt der der Einzelheiten (großer leerer Bereich
  // unter dem Hinweis, der Baum schrumpfte).
  FSplitter.Top := FDetails.Panel.Top - FSplitter.Height;
  FSplitter.Align := alBottom;
  FSplitter.MinSize := FramePixels(Self, cMinDetailsHeight);
  FSplitter.AutoSnap := False;
  FSplitter.ResizeStyle := rsUpdate;
  FSplitter.OnMoved := SplitterMoved;
  FSplitter.Parent := Self;
end;

procedure TAtlasTestsExplorerFrame.BuildTree;
var
  mGap: Integer;
begin
  // Baum und Hinweis teilen sich eine Fläche: Der Hinweis gehört zum Baum, und der Teiler hat nur die
  // Einzelheiten als Nachbarn.
  FTreeArea := TPanel.Create(Self);
  FTreeArea.BevelOuter := bvNone;
  FTreeArea.ShowCaption := False;
  FTreeArea.Align := alClient;
  FTreeArea.Parent := Self;
  FFooter := TAtlasWrapLabel.Create(Self);
  FFooter.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerFooter);
  FFooter.AlignWithMargins := True;
  mGap := FramePixels(Self, cGap);
  FFooter.Margins.SetBounds(mGap, mGap div 2, mGap, mGap div 2);
  FFooter.Align := alBottom;
  FFooter.Parent := FTreeArea;
  FTree := TTreeView.Create(Self);
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.MultiSelect := True;
  FTree.MultiSelectStyle := [msControlSelect, msShiftSelect];
  FTree.Images := FImages;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnChange := TreeChange;
  FTree.Parent := FTreeArea;
end;

procedure TAtlasTestsExplorerFrame.Resize;
begin
  inherited Resize;
  FitDetails;
end;

procedure TAtlasTestsExplorerFrame.ChangeScale(AM, AD: Integer; AIsDpiChange: Boolean);
begin
  inherited ChangeScale(AM, AD, AIsDpiChange);
  // Läuft auch beim Laden der DFM, bevor die Steuerelemente bestehen.
  FWantedDetails := MulDiv(FWantedDetails, AM, AD);
  if AIsDpiChange and (FImages <> nil) then
  begin
    BuildImages(MulDiv(FImages.Width, AM, AD));
  end;
end;

procedure TAtlasTestsExplorerFrame.FitDetails;
var
  mHeight: Integer;
begin
  // Resize kommt schon beim Laden der DFM, vor den Steuerelementen.
  if (FDetails = nil) or (FTreeArea = nil) then
  begin
    Exit;
  end;
  mHeight := TAtlasTestExplorerLayout.DetailsHeight(FTreeArea.Height + FDetails.Panel.Height, FWantedDetails,
    FramePixels(Self, cMinTreeHeight), FramePixels(Self, cMinDetailsHeight));
  if mHeight <> FDetails.Panel.Height then
  begin
    FDetails.Panel.Height := mHeight;
  end;
end;

procedure TAtlasTestsExplorerFrame.SplitterMoved(Sender: TObject);
begin
  FWantedDetails := FDetails.Panel.Height;
  FitDetails;
end;

procedure TAtlasTestsExplorerFrame.BuildImages(ASize: Integer);
var
  mState: TAtlasTestNodeState;
  mBitmap: TBitmap;
  mSize, mInset: Integer;
begin
  mSize := ASize;
  mInset := mSize div cDotInsetDivisor;
  if FImages = nil then
  begin
    FImages := TImageList.Create(Self);
  end;
  // Neue Größe leert die Liste; der Baum behält sie über Images.
  FImages.Clear;
  FImages.Width := mSize;
  FImages.Height := mSize;
  for mState := Low(TAtlasTestNodeState) to High(TAtlasTestNodeState) do
  begin
    mBitmap := TBitmap.Create;
    try
      mBitmap.SetSize(mSize, mSize);
      mBitmap.Canvas.Brush.Color := cMaskColor;
      mBitmap.Canvas.FillRect(TRect.Create(0, 0, mSize, mSize));
      mBitmap.Canvas.Brush.Color := cStateColors[mState];
      mBitmap.Canvas.Pen.Color := cStateColors[mState];
      if mState = TAtlasTestNodeState.Stale then
      begin
        // Veraltet: grauer Ring statt grauem Punkt.
        mBitmap.Canvas.Brush.Color := cMaskColor;
      end;
      mBitmap.Canvas.Ellipse(mInset, mInset, mSize - mInset, mSize - mInset);
      FImages.AddMasked(mBitmap, cMaskColor);
    finally
      mBitmap.Free;
    end;
  end;
end;

procedure TAtlasTestsExplorerFrame.FillControls;
var
  mItems: TArray<TTreeNode>;
  mWasSelected: TArray<Integer>;
  mFocused: Integer;
  mFocusItem: TTreeNode;
begin
  FBar.FillProjects;
  FListBar.FillTabs;
  FTree.HandleNeeded;
  // Auswahl und Fokus über die Knoten des Modells behalten.
  mWasSelected := SelectedNodes;
  mFocused := FocusedNode;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    AddItems(mFocused, mItems, mFocusItem);
    Restore(mItems, mWasSelected);
    if mFocusItem <> nil then
    begin
      mFocusItem.Focused := True;
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  FDetails.Fill;
end;

procedure TAtlasTestsExplorerFrame.AddItems(AFocused: Integer; out AItems: TArray<TTreeNode>;
  out AFocusItem: TTreeNode);
var
  mIndex, mParentRow: Integer;
  mItem: TTreeNode;
begin
  AFocusItem := nil;
  SetLength(AItems, Length(FRows));
  for mIndex := 0 to High(FRows) do
  begin
    mParentRow := FRows[mIndex].Parent;
    if (mParentRow >= 0) and (mParentRow < mIndex) then
    begin
      mItem := FTree.Items.AddChildObject(AItems[mParentRow], FRows[mIndex].Text, Pointer(NativeInt(mIndex)));
    end
    else
    begin
      mItem := FTree.Items.AddObject(nil, FRows[mIndex].Text, Pointer(NativeInt(mIndex)));
    end;
    mItem.ImageIndex := Ord(FRows[mIndex].State);
    mItem.SelectedIndex := mItem.ImageIndex;
    AItems[mIndex] := mItem;
    if FRows[mIndex].Node = AFocused then
    begin
      AFocusItem := mItem;
    end;
  end;
end;

procedure TAtlasTestsExplorerFrame.Restore(const AItems: TArray<TTreeNode>; const AWasSelected: TArray<Integer>);
var
  mIndex, mParent, mChosen: Integer;
begin
  for mIndex := 0 to High(FRows) do
  begin
    // Testunits und Fixtures offen, Tests mit Fällen zu.
    mParent := FRows[mIndex].Parent;
    if (mParent < 0) or (FRows[mParent].Parent < 0) then
    begin
      AItems[mIndex].Expand(False);
    end;
    for mChosen in AWasSelected do
    begin
      if FRows[mIndex].Node = mChosen then
      begin
        AItems[mIndex].Selected := True;
      end;
    end;
  end;
end;

procedure TAtlasTestsExplorerFrame.TreeDblClick(Sender: TObject);
var
  mNode: Integer;
begin
  mNode := FocusedNode;
  if (mNode >= 0) and Assigned(FHandlers.OnOpenNode) then
  begin
    FHandlers.OnOpenNode(mNode);
  end;
end;

procedure TAtlasTestsExplorerFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    TreeDblClick(Sender);
  end
  else if (Key = Ord('R')) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    TAtlasCalls.Call(FHandlers.OnRunSelected);
  end
  else if (Key = Ord('D')) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    TAtlasCalls.Call(FHandlers.OnDebugSelected);
  end;
end;

procedure TAtlasTestsExplorerFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if Assigned(FHandlers.OnSelect) then
  begin
    FHandlers.OnSelect(FocusedNode);
  end;
end;

procedure TAtlasTestsExplorerFrame.SetHandlers(const AHandlers: TAtlasTestsExplorerHandlers);
begin
  FHandlers := AHandlers;
  FBar.Handlers := AHandlers;
  FDetails.OnOpenLine := AHandlers.OnOpenLine;
end;

procedure TAtlasTestsExplorerFrame.SetProjects(const ANames: TArray<string>; AIndex: Integer);
begin
  FBar.SetProjects(ANames, AIndex);
end;

procedure TAtlasTestsExplorerFrame.SetRows(const ARows: TArray<TAtlasTestRow>; const AStatus: string);
begin
  FRows := ARows;
  FBar.SetStatus(AStatus);
  Refill;
end;

procedure TAtlasTestsExplorerFrame.SetStatus(const AStatus: string);
begin
  FBar.SetStatus(AStatus);
end;

procedure TAtlasTestsExplorerFrame.SetDetails(const ALines: TArray<TAtlasTestStackLine>);
begin
  FDetails.SetDetails(ALines);
end;

procedure TAtlasTestsExplorerFrame.SetLog(const ALines: TArray<TAtlasTestStackLine>; ACount: Integer;
  AEnabled: Boolean);
begin
  FDetails.SetLog(ALines, ACount, AEnabled);
end;

/// <summary>Zeile in ARows zu ANode (Data = Zeile); -1 ohne.</summary>
function RowOf(ANode: TTreeNode; const ARows: TArray<TAtlasTestRow>): Integer;
begin
  Result := -1;
  if ANode <> nil then
  begin
    Result := Integer(NativeInt(ANode.Data));
  end;
  if (Result < 0) or (Result > High(ARows)) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasTestsExplorerFrame.SetBusy(ABusy: Boolean);
begin
  FBar.SetBusy(ABusy);
  FListBar.SetBusy(ABusy);
end;

function TAtlasTestsExplorerFrame.Filters: TAtlasTestFilters;
begin
  Result := FBar.Filters;
end;

function TAtlasTestsExplorerFrame.SearchText: string;
begin
  Result := FBar.SearchText;
end;

function TAtlasTestsExplorerFrame.SelectedNodes: TArray<Integer>;
var
  mIndex, mRow: Integer;
begin
  Result := nil;
  for mIndex := 0 to Integer(FTree.SelectionCount) - 1 do
  begin
    mRow := RowOf(FTree.Selections[mIndex], FRows);
    if mRow >= 0 then
    begin
      Result := Result + [FRows[mRow].Node];
    end;
  end;
end;

function TAtlasTestsExplorerFrame.FocusedNode: Integer;
var
  mRow: Integer;
begin
  Result := -1;
  mRow := RowOf(FTree.Selected, FRows);
  if mRow >= 0 then
  begin
    Result := FRows[mRow].Node;
  end;
end;

end.
