unit Atlas.UI.Results.Hierarchy;

// Hierarchien im Ergebnisfenster (#400): Aufrufer, Aufrufe, Vorfahren und Nachfahren laden ihre nächste Ebene erst
// beim Aufklappen über OnExpand. Erschlossene Aufrufer (#1119) tragen ≈ und ihren Grund.
// Aufrufhierarchien (#1122) lassen sich als Diagramm zeigen: Umschalter „Diagramm“ in der Titelzeile (nur mit
// DiagramAllowed, also callHierarchy.diagram), darunter eine Leiste mit Richtung (ausgehend oder eingehend, lädt mit
// denselben Wurzeln neu), „Nur Projekt-Units“, „Einpassen“ und „Als HTML speichern …“; die Ansicht selbst ist
// TAtlasCallDiagramView, ihre Ebenen kommen über OnExpand wie im Baum.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Contract,
  Atlas.UI.Results.CallDiagram,
  Atlas.UI.Results.View;

type
  TAtlasHierarchyExpand = reference to function(ADirection: TAtlasHierarchyDirection;
    const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;

  /// <summary>Steuerelemente des Aufrufdiagramms (#1122).</summary>
  TAtlasResultsDiagramControls = record
    Toggle: TCheckBox;
    Bar: TPanel;
    Outgoing: TRadioButton;
    Incoming: TRadioButton;
    ProjectOnly: TCheckBox;
    Fit: TButton;
    Save: TButton;
    Diagram: TAtlasCallDiagramView;
  end;

  TAtlasResultsHierarchyPart = class(TAtlasResultsPart)
  private
    FControls: TAtlasResultsDiagramControls;
    FRoots: TArray<TAtlasHierarchyItem>;
    FDirection: TAtlasHierarchyDirection;
    FDiagramAllowed: Boolean;
    FUpdating: Boolean;
    FTitle: string;
    FOnExpand: TAtlasHierarchyExpand;
    procedure CreateBar;
    procedure CreateDiagram;
    procedure AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
    function Load(ADirection: TAtlasHierarchyDirection;
      const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
    function IsCallHierarchy: Boolean;
    procedure UpdateControls;
    procedure SetDiagramAllowed(AValue: Boolean);
    function GetShowsDiagram: Boolean;
    procedure SetShowsDiagram(AValue: Boolean);
    procedure SetIsProjectFile(const AValue: TFunc<string, Boolean>);
    procedure ToggleClick(Sender: TObject);
    procedure DirectionClick(Sender: TObject);
    procedure ProjectOnlyClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
  protected
    procedure Reset; override;
    function Expand(ANode: TTreeNode; const AData: TAtlasResultsNode; var AAllowExpansion: Boolean): Boolean;
      override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Wurzeln einer Hierarchie; die erste Ebene wird gleich geladen.</summary>
    procedure Show(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>); overload;
    /// <summary>Wie oben; AAsDiagram: Aufrufhierarchie gleich als Diagramm (#1122, nur mit DiagramAllowed).</summary>
    procedure Show(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean); overload;
    /// <summary>Aufrufhierarchie in Richtung ADirection mit denselben Wurzeln neu laden (Baum und Diagramm).</summary>
    procedure SwitchDirection(ADirection: TAtlasHierarchyDirection);
    /// <summary>Diagramm als eigenständige HTML-Datei (#1122) mit dem Titel des Fensters.</summary>
    function DiagramHtml: string;
    /// <summary>Diagramm erlaubt (callHierarchy.diagram, #1122); aus: Umschalter fehlt, nur der Baum.</summary>
    property DiagramAllowed: Boolean read FDiagramAllowed write SetDiagramAllowed;
    /// <summary>Zeigt gerade das Aufrufdiagramm statt des Baums.</summary>
    property ShowsDiagram: Boolean read GetShowsDiagram write SetShowsDiagram;
    /// <summary>Gehört die Datei zu einem Projekt der Gruppe („Nur Projekt-Units“)? nil: alle.</summary>
    property IsProjectFile: TFunc<string, Boolean> write SetIsProjectFile; // lsp-ignore: write-only-property -- reicht nur an das Diagramm weiter
    property Direction: TAtlasHierarchyDirection read FDirection;
    property Controls: TAtlasResultsDiagramControls read FControls;
    property OnExpand: TAtlasHierarchyExpand read FOnExpand write FOnExpand;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.UI.Strings,
  Atlas.UI.Results.Texts;

{ TAtlasResultsHierarchyPart }

constructor TAtlasResultsHierarchyPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Umschalter Liste/Diagramm (#1122), nur bei Aufrufhierarchien.
  FControls.Toggle := TAtlasResultsControls.Check(AView.Host, AView.Header, alRight, 90,
    TAtlasStrings.Text(TAtlasTextId.CallDiagramToggle), ToggleClick);
  FControls.Toggle.Visible := False;
  CreateBar;
  CreateDiagram;
end;

procedure TAtlasResultsHierarchyPart.CreateBar;
var
  mOwner: TComponent;
begin
  // Leiste des Diagramms: Richtung, Filter, Einpassen, HTML.
  mOwner := View.Host;
  FControls.Bar := TAtlasResultsControls.Bar(mOwner, View, 26);
  FControls.Outgoing := TAtlasResultsControls.Radio(mOwner, FControls.Bar, 160,
    TAtlasStrings.Text(TAtlasTextId.CallDiagramOutgoing), DirectionClick);
  FControls.Incoming := TAtlasResultsControls.Radio(mOwner, FControls.Bar, 150,
    TAtlasStrings.Text(TAtlasTextId.CallDiagramIncoming), DirectionClick);
  TAtlasResultsControls.Follow(FControls.Incoming, FControls.Outgoing);
  FControls.ProjectOnly := TAtlasResultsControls.Check(mOwner, FControls.Bar, alLeft, 140,
    TAtlasStrings.Text(TAtlasTextId.CallDiagramProjectOnly), nil);
  TAtlasResultsControls.Follow(FControls.ProjectOnly, FControls.Incoming);
  FControls.ProjectOnly.Checked := True;
  FControls.ProjectOnly.OnClick := ProjectOnlyClick;
  FControls.Save := TAtlasResultsControls.Button(mOwner, FControls.Bar, alRight, 150,
    TAtlasStrings.Text(TAtlasTextId.CallDiagramSaveHtml), SaveClick);
  FControls.Fit := TAtlasResultsControls.Button(mOwner, FControls.Bar, alRight, 90,
    TAtlasStrings.Text(TAtlasTextId.CallDiagramFit), FitClick);
end;

procedure TAtlasResultsHierarchyPart.CreateDiagram;
begin
  FControls.Diagram := TAtlasCallDiagramView.Create(View.Host);
  FControls.Diagram.Parent := View.Host;
  FControls.Diagram.Align := alClient;
  FControls.Diagram.Visible := False;
  FControls.Diagram.Hint := TAtlasStrings.Text(TAtlasTextId.CallDiagramHint);
  FControls.Diagram.OnLoad := Load;
  FControls.Diagram.OnOpen :=
    procedure(const AItem: TAtlasHierarchyItem)
    begin
      if AItem.FileName <> '' then
      begin
        View.Open(TAtlasResultsNode.Place(TAtlasResultsNodeKind.Hierarchy, AItem.FileName, AItem.Line,
          AItem.Character));
      end;
    end;
end;

procedure TAtlasResultsHierarchyPart.Reset;
begin
  // Andere Listen zeigen immer den Baum; der Umschalter behält seinen Stand für die nächste Aufrufhierarchie.
  FRoots := nil;
  UpdateControls;
end;

procedure TAtlasResultsHierarchyPart.AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
var
  mItem: TAtlasHierarchyItem;
  mData: TAtlasResultsNode;
  mNode: TTreeNode;
begin
  for mItem in AItems do
  begin
    mData := TAtlasResultsNode.Place(TAtlasResultsNodeKind.Hierarchy, mItem.FileName, mItem.Line, mItem.Character);
    mData.Item := mItem;
    mData.Hint := mItem.Confidence.Explanation;
    mNode := View.AddNode(AParent, TAtlasResultsTexts.HierarchyText(mItem), mData);
    // Platzhalter, damit sich der Knoten aufklappen lässt; geladen wird erst dann.
    View.AddNode(mNode, '…', TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  end;
end;

function TAtlasResultsHierarchyPart.Load(ADirection: TAtlasHierarchyDirection;
  const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
begin
  Result := nil;
  if Assigned(FOnExpand) then
  begin
    Result := FOnExpand(ADirection, AItem);
  end;
end;

function TAtlasResultsHierarchyPart.Expand(ANode: TTreeNode; const AData: TAtlasResultsNode;
  var AAllowExpansion: Boolean): Boolean;
var
  mData: TAtlasResultsNode;
  mChildren: TArray<TAtlasHierarchyItem>;
begin
  Result := AData.Kind = TAtlasResultsNodeKind.Hierarchy;
  if not Result then
  begin
    Exit;
  end;
  mData := AData;
  mData.Loaded := True;
  View.Store(ANode, mData);
  Screen.Cursor := crHourGlass;
  try
    mChildren := Load(FDirection, mData.Item);
  finally
    Screen.Cursor := crDefault;
  end;
  View.Tree.Items.BeginUpdate;
  try
    ANode.DeleteChildren;
    AddHierarchy(ANode, mChildren);
  finally
    View.Tree.Items.EndUpdate;
  end;
  AAllowExpansion := ANode.HasChildren;
end;

procedure TAtlasResultsHierarchyPart.Show(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>);
begin
  Show(ATitle, ADirection, ARoots, False);
end;

procedure TAtlasResultsHierarchyPart.Show(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean);
begin
  View.Clear(ATitle);
  FDirection := ADirection;
  FRoots := ARoots;
  View.Tree.Items.BeginUpdate;
  try
    AddHierarchy(nil, ARoots);
  finally
    View.Tree.Items.EndUpdate;
  end;
  if View.Tree.Items.Count > 0 then
  begin
    View.Tree.Selected := View.Tree.Items[0];
    View.Tree.Items[0].Expand(False);
  end;
  FTitle := ATitle;
  UpdateControls;
  if AAsDiagram or FControls.Toggle.Checked then
  begin
    SetShowsDiagram(True);
  end;
end;

function TAtlasResultsHierarchyPart.IsCallHierarchy: Boolean;
begin
  Result := (Length(FRoots) > 0) and ((FDirection = TAtlasHierarchyDirection.Incoming) or
    (FDirection = TAtlasHierarchyDirection.Outgoing));
end;

procedure TAtlasResultsHierarchyPart.UpdateControls;
var
  mPossible, mShowing: Boolean;
begin
  mPossible := FDiagramAllowed and IsCallHierarchy;
  FControls.Toggle.Visible := mPossible;
  mShowing := mPossible and FControls.Toggle.Checked;
  FUpdating := True;
  try
    FControls.Outgoing.Checked := FDirection = TAtlasHierarchyDirection.Outgoing;
    FControls.Incoming.Checked := FDirection = TAtlasHierarchyDirection.Incoming;
  finally
    FUpdating := False;
  end;
  FControls.Bar.Visible := mShowing;
  FControls.Diagram.Visible := mShowing;
  View.Tree.Visible := not mShowing;
end;

procedure TAtlasResultsHierarchyPart.SetDiagramAllowed(AValue: Boolean);
begin
  FDiagramAllowed := AValue;
  if not AValue then
  begin
    SetShowsDiagram(False);
  end
  else
  begin
    UpdateControls;
  end;
end;

function TAtlasResultsHierarchyPart.GetShowsDiagram: Boolean;
begin
  Result := FControls.Diagram.Visible;
end;

procedure TAtlasResultsHierarchyPart.SetShowsDiagram(AValue: Boolean);
var
  mShow: Boolean;
begin
  mShow := AValue and FDiagramAllowed and IsCallHierarchy;
  FUpdating := True;
  try
    FControls.Toggle.Checked := mShow;
  finally
    FUpdating := False;
  end;
  // Erst beim Umschalten laden; ein Wechsel zurück zum Baum behält die geladenen Ebenen nicht.
  if mShow then
  begin
    FControls.Diagram.ProjectOnly := FControls.ProjectOnly.Checked;
    FControls.Diagram.ShowRoots(FDirection, FRoots);
  end;
  UpdateControls;
  if mShow and FControls.Diagram.CanFocus and FControls.Diagram.Showing then
  begin
    FControls.Diagram.SetFocus;
  end;
end;

procedure TAtlasResultsHierarchyPart.SetIsProjectFile(const AValue: TFunc<string, Boolean>);
begin
  FControls.Diagram.IsProjectFile := AValue;
end;

procedure TAtlasResultsHierarchyPart.SwitchDirection(ADirection: TAtlasHierarchyDirection);
const
  cTitles: array[TAtlasHierarchyDirection] of TAtlasTextId = (TAtlasTextId.ResultsIncoming,
    TAtlasTextId.ResultsOutgoing, TAtlasTextId.ResultsSupertypes, TAtlasTextId.ResultsSubtypes);
var
  mRoots: TArray<TAtlasHierarchyItem>;
begin
  if (Length(FRoots) = 0) or (ADirection = FDirection) then
  begin
    Exit;
  end;
  mRoots := FRoots;
  Show(TAtlasStrings.Fmt(cTitles[ADirection], [mRoots[0].Name]), ADirection, mRoots, ShowsDiagram);
end;

procedure TAtlasResultsHierarchyPart.ToggleClick(Sender: TObject);
begin
  if not FUpdating then
  begin
    SetShowsDiagram(FControls.Toggle.Checked);
  end;
end;

procedure TAtlasResultsHierarchyPart.DirectionClick(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  if FControls.Outgoing.Checked then
  begin
    SwitchDirection(TAtlasHierarchyDirection.Outgoing);
  end
  else if FControls.Incoming.Checked then
  begin
    SwitchDirection(TAtlasHierarchyDirection.Incoming);
  end;
end;

procedure TAtlasResultsHierarchyPart.ProjectOnlyClick(Sender: TObject);
begin
  FControls.Diagram.ProjectOnly := FControls.ProjectOnly.Checked;
end;

procedure TAtlasResultsHierarchyPart.FitClick(Sender: TObject);
begin
  FControls.Diagram.FitView;
end;

function TAtlasResultsHierarchyPart.DiagramHtml: string;
begin
  Result := FControls.Diagram.Html(FTitle);
end;

procedure TAtlasResultsHierarchyPart.SaveClick(Sender: TObject);
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(View.Host);
  try
    mDialog.Filter := TAtlasStrings.Text(TAtlasTextId.CallDiagramSaveFilter);
    mDialog.DefaultExt := 'html';
    mDialog.FileName := TAtlasStrings.Text(TAtlasTextId.CallDiagramCommand) + '.html';
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    TFile.WriteAllText(mDialog.FileName, DiagramHtml, TEncoding.UTF8);
    View.Title.Caption := FTitle + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.CallDiagramSaved, [mDialog.FileName]);
  finally
    mDialog.Free;
  end;
end;

end.
