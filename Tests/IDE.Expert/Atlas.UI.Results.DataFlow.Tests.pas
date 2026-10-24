unit Atlas.UI.Results.DataFlow.Tests;

// Datenfluss im Ergebnisfenster (#690): Texte der Stellen und Quellen, Baum mit zusammengefassten Fundorten,
// Nachladen beim Aufklappen mit Pfad und Ebene, Tiefengrenze, Sprung per Doppelklick und die Filterleiste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasResultsDataFlowTests = class
  public
    [Test]
    procedure NodeTextShowsKindDetailViaUnsafeAndPlace;
    [Test]
    procedure SourceTextShowsArrowLeafAndDepth;
    [Test]
    procedure TreeGroupsPlacesExpandsLazilyAndJumps;
    [Test]
    procedure DepthLimitAndFilterBar;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Results.DataFlow,
  Atlas.UI.Strings,
  Atlas.UI.Results.Frame;

function Place(ALine: Integer; const AText: string): TAtlasDataFlowPlace;
begin
  Result := Default(TAtlasDataFlowPlace);
  Result.FileName := 'C:\P\Haupt.pas';
  Result.Line := ALine;
  Result.Character := 2;
  Result.LineText := AText;
end;

function Symbol(const AName, AKey: string; ALeaf: TAtlasDataFlowLeaf): TAtlasDataFlowSymbol;
begin
  Result := Default(TAtlasDataFlowSymbol);
  Result.Name := AName;
  Result.FileName := 'C:\P\Daten.pas';
  Result.Line := 10;
  Result.Character := 4;
  Result.Key := AKey;
  Result.Leaf := ALeaf;
end;

function Assignment(const ADetail: string; const APlaces: TArray<TAtlasDataFlowPlace>;
  const ASources: TArray<TAtlasDataFlowSymbol>): TAtlasDataFlowNode;
begin
  Result := Default(TAtlasDataFlowNode);
  Result.Kind := TAtlasDataFlowKind.Assignment;
  Result.Detail := ADetail;
  Result.Places := APlaces;
  Result.Sources := ASources;
end;

function Answer(const ANodes: TArray<TAtlasDataFlowNode>): TAtlasDataFlowResult;
begin
  Result := Default(TAtlasDataFlowResult);
  Result.Found := True;
  Result.Symbol := Symbol('X', 'X', TAtlasDataFlowLeaf.None);
  Result.Nodes := ANodes;
end;

/// <summary>AIndex-te Wurzel des Baums.</summary>
function Root(AFrame: TAtlasResultsFrame; AIndex: Integer): TTreeNode;
begin
  Result := AFrame.Tree.Items.GetFirstNode;
  while (AIndex > 0) and (Result <> nil) do
  begin
    Result := Result.getNextSibling;
    Dec(AIndex);
  end;
end;

function RootCount(AFrame: TAtlasResultsFrame): Integer;
var
  Node: TTreeNode;
begin
  Result := 0;
  Node := AFrame.Tree.Items.GetFirstNode;
  while Node <> nil do
  begin
    Inc(Result);
    Node := Node.getNextSibling;
  end;
end;

{ TAtlasResultsDataFlowTests }

procedure TAtlasResultsDataFlowTests.NodeTextShowsKindDetailViaUnsafeAndPlace;
var
  Node: TAtlasDataFlowNode;
  Text: string;
begin
  Node := Assignment('A + B', [Place(11, 'X := A + B;')], nil);
  Node.Via := 'Summe';
  Node.Unsafe := True;
  Node.UnsafeReason := 'pointer';
  Text := TAtlasResultsFrame.FlowNodeText(Node);
  Assert.StartsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowAssignment) + ': A + B', Text);
  Assert.Contains(Text, TAtlasStrings.Fmt(TAtlasTextId.DataFlowVia, ['Summe']));
  Assert.Contains(Text, TAtlasStrings.Fmt(TAtlasTextId.DataFlowUnsafe,
    [TAtlasStrings.Text(TAtlasTextId.DataFlowUnsafePointer)]));
  Assert.EndsWith('Haupt.pas:12: X := A + B;', Text);
  // Zusammengefasst: Anzahl und Mehrzahl, der Fundort steht darunter.
  Node := Assignment('0', [Place(3, 'X := 0;'), Place(8, 'X := 0;'), Place(9, 'X := 0;')], nil);
  Node.Literal := True;
  Text := TAtlasResultsFrame.FlowNodeText(Node);
  Assert.StartsWith('3 ' + TAtlasStrings.Text(TAtlasTextId.DataFlowAssignments), Text);
  Assert.Contains(Text, TAtlasStrings.Text(TAtlasTextId.DataFlowOriginLiteral));
  Assert.IsFalse(Text.Contains('Haupt.pas'), 'ohne Fundort');
  Assert.AreEqual('Haupt.pas:4: X := 0;', TAtlasResultsFrame.FlowPlaceText(Node.Places[0]));
end;

procedure TAtlasResultsDataFlowTests.SourceTextShowsArrowLeafAndDepth;
var
  Child: TAtlasDataFlowChild;
begin
  Child := Default(TAtlasDataFlowChild);
  Child.Kind := TAtlasDataFlowChildKind.Source;
  Child.Source := Symbol('Summe', 'S', TAtlasDataFlowLeaf.None);
  Assert.AreEqual('← Summe  (Daten.pas:11)', TAtlasResultsFrame.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
  Assert.AreEqual('→ Summe  (Daten.pas:11)', TAtlasResultsFrame.FlowSourceText(Child,
    TAtlasDataFlowDirection.Targets));
  Child.DepthReached := True;
  Assert.EndsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowLeafDepth), TAtlasResultsFrame.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
  Child.DepthReached := False;
  Child.Source.Leaf := TAtlasDataFlowLeaf.Cycle;
  Assert.EndsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowLeafCycle), TAtlasResultsFrame.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
  Child.Source.Leaf := TAtlasDataFlowLeaf.Constant;
  Assert.EndsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowLeafConstant), TAtlasResultsFrame.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
end;

procedure TAtlasResultsDataFlowTests.TreeGroupsPlacesExpandsLazilyAndJumps;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Source: TTreeNode;
  Allow: Boolean;
  AskedKey, OpenedFile: string;
  AskedPath: TArray<string>;
  OpenedLine, Asked: Integer;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Asked := 0;
    Frame.OnFlowExpand :=
      function(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
        const APath: TArray<string>): TAtlasDataFlowResult
      begin
        Inc(Asked);
        AskedKey := ASource.Key;
        AskedPath := APath;
        Result := Answer([Assignment('5', [Place(20, 'Summe := 5;')], nil)]);
      end;
    OpenedLine := -1;
    Frame.OnOpen :=
      procedure(const AFileName: string; ALine, ACharacter: Integer)
      begin
        OpenedFile := AFileName;
        OpenedLine := ALine;
      end;
    Frame.ShowDataFlow('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('0', [Place(3, 'X := 0;'), Place(8, 'X := 0;')], nil),
      Assignment('Summe', [Place(11, 'X := Summe;')], [Symbol('Summe', 'S', TAtlasDataFlowLeaf.None)])]), 6,
      False, False);
    Assert.IsTrue(Frame.ShowsFlow);
    Assert.AreEqual(2, RootCount(Frame));
    // Zusammengefasst: beide Fundorte darunter.
    Assert.AreEqual(2, Integer(Root(Frame, 0).Count));
    Assert.AreEqual('Haupt.pas:9: X := 0;', Root(Frame, 0).Item[1].Text);
    // Quelle mit Platzhalter; geladen wird erst beim Aufklappen.
    Source := Root(Frame, 1).Item[0];
    Assert.AreEqual(1, Integer(Source.Count));
    Assert.AreEqual(0, Asked);
    Allow := True;
    Frame.Tree.OnExpanding(Frame.Tree, Source, Allow);
    Assert.AreEqual(1, Asked);
    Assert.AreEqual('S', AskedKey);
    Assert.AreEqual(2, Integer(Length(AskedPath)));
    Assert.AreEqual('X', AskedPath[0]);
    Assert.AreEqual('S', AskedPath[1]);
    Assert.IsTrue(Allow);
    Assert.AreEqual(1, Integer(Source.Count));
    Assert.Contains(Source.Item[0].Text, 'Summe := 5;');
    // Ein zweites Aufklappen fragt nicht noch einmal.
    Frame.Tree.OnExpanding(Frame.Tree, Source, Allow);
    Assert.AreEqual(1, Asked);
    // Doppelklick springt zum Fundort.
    Frame.Tree.Selected := Source.Item[0];
    Frame.Tree.OnDblClick(Frame.Tree);
    Assert.AreEqual('C:\P\Haupt.pas', OpenedFile);
    Assert.AreEqual(20, OpenedLine);
    Frame.Tree.Selected := Root(Frame, 0).Item[1];
    Frame.Tree.OnDblClick(Frame.Tree);
    Assert.AreEqual(8, OpenedLine);
  finally
    AskedPath := nil;
    Host.Free;
  end;
end;

procedure TAtlasResultsDataFlowTests.DepthLimitAndFilterBar;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Filtered: Integer;
  OnlyProject, ExcludeTests: Boolean;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Filtered := 0;
    OnlyProject := False;
    ExcludeTests := False;
    Frame.OnFlowFilter :=
      procedure(AOnlyProject, AExcludeTests: Boolean)
      begin
        Inc(Filtered);
        OnlyProject := AOnlyProject;
        ExcludeTests := AExcludeTests;
      end;
    // Tiefe 1: Die Quellen der ersten Ebene gehen nicht weiter auf.
    Frame.ShowDataFlow('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('Summe', [Place(11, 'X := Summe;')], [Symbol('Summe', 'S', TAtlasDataFlowLeaf.None)])]),
      1, False, True);
    Assert.AreEqual(0, Integer(Root(Frame, 0).Item[0].Count));
    Assert.EndsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowLeafDepth), Root(Frame, 0).Item[0].Text);
    // Filter wie angefragt, Setzen meldet nichts.
    Assert.IsFalse(Frame.OnlyProjectCheck.Checked);
    Assert.IsTrue(Frame.ExcludeTestsCheck.Checked);
    Assert.AreEqual(0, Filtered);
    Frame.OnlyProjectCheck.Checked := True;
    Assert.AreEqual(1, Filtered);
    Assert.IsTrue(OnlyProject);
    Assert.IsTrue(ExcludeTests);
    // Andere Listen blenden die Filter aus und melden nichts mehr.
    Frame.ShowEntries('Referenzen', nil);
    Assert.IsFalse(Frame.ShowsFlow);
    Frame.ExcludeTestsCheck.Checked := False;
    Assert.AreEqual(1, Filtered);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsDataFlowTests);

end.
