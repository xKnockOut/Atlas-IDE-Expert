unit Atlas.UI.Results.Impact;

// Auswirkungsanalyse (#1120) im Ergebnisfenster, in drei Abschnitten: „Direkt“ (Ebene 1), „Indirekt“ als Baum über
// die verursachende Stelle und „Betroffene Tests“; Formularbindungen hängen unter ihrer Stelle, erreichte Grenzen
// stehen am Ende. In der Titelzeile wählt „Tiefe“ 1–5 (OnDepth rechnet neu), und „Betroffene Tests ausführen“ gibt
// die Tests an OnRunTests.

interface

uses
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Lsp.Contract,
  Atlas.UI.Results.View;

type
  /// <summary>Auswirkungsanalyse (#1120) mit anderer Tiefe neu rechnen.</summary>
  TAtlasImpactDepthChange = reference to procedure(ADepth: Integer);
  /// <summary>Betroffene Tests der gezeigten Analyse ausführen.</summary>
  TAtlasImpactRunTests = reference to procedure(const AImpact: TAtlasImpact);

  TAtlasResultsImpactPart = class(TAtlasResultsPart)
  private type
    TParts = record
      DepthLabel: TLabel;
      Depth: TComboBox;
      RunTests: TButton;
    end;
    THandlers = record
      OnDepth: TAtlasImpactDepthChange;
      OnRunTests: TAtlasImpactRunTests;
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FImpact: TAtlasImpact;
    FShows: Boolean;
    function AddPlace(AParent: TTreeNode; APlace: Integer): TTreeNode;
    procedure AddBranch(AParent: TTreeNode; ACause: Integer);
    procedure AddForms(AParent: TTreeNode; const AForms: TArray<TAtlasImpactForm>);
    procedure AddDirect;
    procedure AddIndirect;
    procedure AddTests;
    procedure AddLimits;
    procedure ShowDepth;
    procedure DepthChange(Sender: TObject);
    procedure RunTestsClick(Sender: TObject);
  protected
    procedure Reset; override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Abschnitte „Direkt“, „Indirekt“ (Baum über die Ursache), „Betroffene Tests“, darunter erreichte
    /// Grenzen; Tiefe und „Betroffene Tests ausführen“ in der Titelzeile.</summary>
    procedure Show(const ATitle: string; const AImpact: TAtlasImpact);
    /// <summary>Zeigt gerade eine Auswirkungsanalyse.</summary>
    property Shows: Boolean read FShows;
    property Impact: TAtlasImpact read FImpact;
    property DepthBox: TComboBox read FParts.Depth;
    property RunTestsButton: TButton read FParts.RunTests;
    property OnDepth: TAtlasImpactDepthChange read FHandlers.OnDepth write FHandlers.OnDepth;
    property OnRunTests: TAtlasImpactRunTests read FHandlers.OnRunTests write FHandlers.OnRunTests;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.UI.Results.Texts;

const
  /// <summary>Ab so vielen indirekten Stellen bleibt der Abschnitt zugeklappt.</summary>
  cExpandIndirect = 200;
  cMaxDepth = 5;

{ TAtlasResultsImpactPart }

constructor TAtlasResultsImpactPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Tiefe und Testlauf, rechts in der Titelzeile. Die Liste der Tiefen füllt Show: Ein Kombinationsfeld braucht
  // dafür ein Fenster.
  FParts.RunTests := TAtlasResultsControls.Button(AView.Host, AView.Header, alRight, 170,
    TAtlasStrings.Text(TAtlasTextId.ImpactRunTests), RunTestsClick);
  FParts.RunTests.Visible := False;
  FParts.Depth := TComboBox.Create(AView.Host);
  FParts.Depth.Parent := AView.Header;
  FParts.Depth.Align := alRight;
  FParts.Depth.AlignWithMargins := True;
  FParts.Depth.Style := csDropDownList;
  FParts.Depth.Width := 44;
  FParts.Depth.Visible := False;
  FParts.Depth.OnChange := DepthChange;
  FParts.DepthLabel := TLabel.Create(AView.Host);
  FParts.DepthLabel.Parent := AView.Header;
  FParts.DepthLabel.Align := alRight;
  FParts.DepthLabel.AlignWithMargins := True;
  FParts.DepthLabel.Layout := tlCenter;
  FParts.DepthLabel.Caption := TAtlasStrings.Text(TAtlasTextId.ImpactDepth);
  FParts.DepthLabel.Visible := False;
end;

procedure TAtlasResultsImpactPart.Reset;
begin
  FShows := False;
  FParts.DepthLabel.Visible := False;
  FParts.Depth.Visible := False;
  FParts.RunTests.Visible := False;
end;

procedure TAtlasResultsImpactPart.AddForms(AParent: TTreeNode; const AForms: TArray<TAtlasImpactForm>);
var
  mForm: TAtlasImpactForm;
begin
  for mForm in AForms do
  begin
    View.AddNode(AParent, TAtlasResultsTexts.ImpactFormText(mForm),
      TAtlasResultsNode.Place(TAtlasResultsNodeKind.Entry, mForm.FileName, mForm.Line, mForm.Character));
  end;
end;

function TAtlasResultsImpactPart.AddPlace(AParent: TTreeNode; APlace: Integer): TTreeNode;
var
  mPlace: TAtlasImpactPlace;
  mData: TAtlasResultsNode;
begin
  mPlace := FImpact.Places[APlace];
  // Doppelklick springt zur Verwendung der Ursache in der Stelle.
  mData := TAtlasResultsNode.Place(TAtlasResultsNodeKind.Entry, mPlace.Item.FileName, mPlace.UseLine,
    mPlace.UseCharacter);
  mData.Hint := mPlace.Item.Confidence.Explanation;
  Result := View.AddNode(AParent, TAtlasResultsTexts.ImpactPlaceText(mPlace), mData);
  AddForms(Result, mPlace.Forms);
end;

procedure TAtlasResultsImpactPart.AddBranch(AParent: TTreeNode; ACause: Integer);
var
  mChild: Integer;
begin
  // Jede Stelle hat genau eine Ursache: Der Baum endet, Zyklen gibt es nicht.
  for mChild in FImpact.Children(ACause) do
  begin
    AddBranch(AddPlace(AParent, mChild), mChild);
  end;
end;

procedure TAtlasResultsImpactPart.AddDirect;
var
  mSection: TTreeNode;
  mIndex: Integer;
begin
  mSection := View.AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactDirect), [FImpact.LevelCount(1)]),
    TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  AddForms(mSection, FImpact.SymbolForms);
  for mIndex := 0 to High(FImpact.Places) do
  begin
    if FImpact.Places[mIndex].Level = 1 then
    begin
      AddPlace(mSection, mIndex);
    end;
  end;
  mSection.Expand(False);
end;

procedure TAtlasResultsImpactPart.AddIndirect;
var
  mSection: TTreeNode;
  mIndex: Integer;
begin
  mSection := View.AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactIndirect), [FImpact.CountFrom(2)]),
    TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  for mIndex in FImpact.Children(-1) do
  begin
    if Length(FImpact.Children(mIndex)) > 0 then
    begin
      AddBranch(AddPlace(mSection, mIndex), mIndex);
    end;
  end;
  mSection.Expand(FImpact.CountFrom(2) <= cExpandIndirect);
end;

procedure TAtlasResultsImpactPart.AddTests;
var
  mSection: TTreeNode;
  mTest: TAtlasImpactTest;
begin
  if Length(FImpact.Tests) = 0 then
  begin
    View.AddNode(nil, TAtlasStrings.Text(TAtlasTextId.ImpactNoTests),
      TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
    Exit;
  end;
  mSection := View.AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactTests), [Length(FImpact.Tests)]),
    TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  for mTest in FImpact.Tests do
  begin
    View.AddNode(mSection, mTest.Name + Format('  (%s:%d)', [ExtractFileName(mTest.FileName), mTest.Line + 1]),
      TAtlasResultsNode.Place(TAtlasResultsNodeKind.Entry, mTest.FileName, mTest.Line, 0));
  end;
  mSection.Expand(False);
end;

procedure TAtlasResultsImpactPart.AddLimits;
var
  mLimit: string;
begin
  for mLimit in TAtlasResultsTexts.ImpactLimitTexts(FImpact) do
  begin
    View.AddNode(nil, '⚠ ' + mLimit, TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  end;
end;

procedure TAtlasResultsImpactPart.ShowDepth;
var
  mDepth: Integer;
begin
  FParts.DepthLabel.Visible := True;
  FParts.Depth.Visible := True;
  FParts.RunTests.Visible := True;
  FParts.RunTests.Enabled := Length(FImpact.Tests) > 0;
  if FParts.Depth.Items.Count = 0 then
  begin
    for mDepth := 1 to cMaxDepth do
    begin
      FParts.Depth.Items.Add(IntToStr(mDepth));
    end;
  end;
  FParts.Depth.OnChange := nil;
  try
    FParts.Depth.ItemIndex := FImpact.Depth - 1;
  finally
    FParts.Depth.OnChange := DepthChange;
  end;
end;

procedure TAtlasResultsImpactPart.Show(const ATitle: string; const AImpact: TAtlasImpact);
begin
  View.Clear(ATitle);
  FImpact := AImpact;
  FShows := True;
  ShowDepth;
  View.Tree.Items.BeginUpdate;
  try
    AddDirect;
    AddIndirect;
    AddTests;
    AddLimits;
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(nil);
end;

procedure TAtlasResultsImpactPart.DepthChange(Sender: TObject);
begin
  if FShows and (FParts.Depth.ItemIndex >= 0) and Assigned(FHandlers.OnDepth) then
  begin
    FHandlers.OnDepth(FParts.Depth.ItemIndex + 1);
  end;
end;

procedure TAtlasResultsImpactPart.RunTestsClick(Sender: TObject);
begin
  if FShows and (Length(FImpact.Tests) > 0) and Assigned(FHandlers.OnRunTests) then
  begin
    FHandlers.OnRunTests(FImpact);
  end;
end;

end.
