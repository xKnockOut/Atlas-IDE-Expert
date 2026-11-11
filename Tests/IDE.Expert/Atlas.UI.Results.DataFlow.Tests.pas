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
    /// <summary>Ergebnisfenster mit Baum einmal vorab zeigen: Zwischenspeicher der ersten Benutzung zählen sonst als
    /// Leck im ersten Test.</summary>
    [SetupFixture]
    procedure WarmUp;
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
  Atlas.UI.Results.Strings,
  Atlas.UI.Results.Texts,
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
  Text := TAtlasResultsTexts.FlowNodeText(Node);
  Assert.StartsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowAssignment) + ': A + B', Text);
  Assert.Contains(Text, TAtlasResultsStrings.Fmt(TAtlasResultsTextId.DataFlowVia, ['Summe']));
  Assert.Contains(Text, TAtlasResultsStrings.Fmt(TAtlasResultsTextId.DataFlowUnsafe,
    [TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowUnsafePointer)]));
  Assert.EndsWith('Haupt.pas:12: X := A + B;', Text);
  // Zusammengefasst: Anzahl und Mehrzahl, der Fundort steht darunter.
  Node := Assignment('0', [Place(3, 'X := 0;'), Place(8, 'X := 0;'), Place(9, 'X := 0;')], nil);
  Node.Literal := True;
  Text := TAtlasResultsTexts.FlowNodeText(Node);
  Assert.StartsWith('3 ' + TAtlasStrings.Text(TAtlasTextId.DataFlowAssignments), Text);
  Assert.Contains(Text, TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOriginLiteral));
  Assert.IsFalse(Text.Contains('Haupt.pas'), 'ohne Fundort');
  Assert.AreEqual('Haupt.pas:4: X := 0;', TAtlasResultsTexts.FlowPlaceText(Node.Places[0]));
end;

procedure TAtlasResultsDataFlowTests.SourceTextShowsArrowLeafAndDepth;
var
  Child: TAtlasDataFlowChild;
begin
  Child := Default(TAtlasDataFlowChild);
  Child.Kind := TAtlasDataFlowChildKind.Source;
  Child.Source := Symbol('Summe', 'S', TAtlasDataFlowLeaf.None);
  Assert.AreEqual('← Summe  (Daten.pas:11)', TAtlasResultsTexts.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
  Assert.AreEqual('→ Summe  (Daten.pas:11)', TAtlasResultsTexts.FlowSourceText(Child,
    TAtlasDataFlowDirection.Targets));
  Child.DepthReached := True;
  Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafDepth),
    TAtlasResultsTexts.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
  Child.DepthReached := False;
  Child.Source.Leaf := TAtlasDataFlowLeaf.Cycle;
  Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafCycle),
    TAtlasResultsTexts.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
  Child.Source.Leaf := TAtlasDataFlowLeaf.Constant;
  Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafConstant),
    TAtlasResultsTexts.FlowSourceText(Child,
    TAtlasDataFlowDirection.Sources));
end;

type
  /// <summary>Hält fest, was der Baum nachlädt und wohin er springt.</summary>
  TDataFlowProbe = class
  public
    FAsked: Integer;
    FAskedKey: string;
    FAskedPath: TArray<string>;
    FOpenedFile: string;
    FOpenedLine: Integer;
  end;

/// <summary>Nachladen und Springen des Baums an die Probe hängen.</summary>
procedure WireDataFlow(const ATarget: TAtlasResultsFrame; const AProbe: TDataFlowProbe);
begin
  AProbe.FAsked := 0;
  ATarget.Flow.OnExpand :=
    function(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
      const APath: TArray<string>): TAtlasDataFlowResult
    begin
      Inc(AProbe.FAsked);
      AProbe.FAskedKey := ASource.Key;
      AProbe.FAskedPath := APath;
      Result := Answer([Assignment('5', [Place(20, 'Summe := 5;')], nil)]);
    end;
  AProbe.FOpenedLine := -1;
  ATarget.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      AProbe.FOpenedFile := AFileName;
      AProbe.FOpenedLine := ALine;
    end;
end;

procedure TAtlasResultsDataFlowTests.WarmUp;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Flow.Show('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('0', [Place(3, 'X := 0;')], nil)]), 6, False, False);
  finally
    Host.Free;
  end;
end;

procedure TAtlasResultsDataFlowTests.TreeGroupsPlacesExpandsLazilyAndJumps;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Source: TTreeNode;
  Allow: Boolean;
  mProbe: TDataFlowProbe;
begin
  mProbe := TDataFlowProbe.Create;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    WireDataFlow(Frame, mProbe);
    Frame.Flow.Show('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('0', [Place(3, 'X := 0;'), Place(8, 'X := 0;')], nil),
      Assignment('Summe', [Place(11, 'X := Summe;')], [Symbol('Summe', 'S', TAtlasDataFlowLeaf.None)])]), 6,
      False, False);
    Assert.IsTrue(Frame.Flow.Shows);
    Assert.AreEqual(2, RootCount(Frame));
    // Zusammengefasst: beide Fundorte darunter.
    Assert.AreEqual(2, Integer(Root(Frame, 0).Count));
    Assert.AreEqual('Haupt.pas:9: X := 0;', Root(Frame, 0).Item[1].Text);
    // Quelle mit Platzhalter; geladen wird erst beim Aufklappen.
    Source := Root(Frame, 1).Item[0];
    Assert.AreEqual(1, Integer(Source.Count));
    Assert.AreEqual(0, mProbe.FAsked);
    Allow := True;
    Frame.Tree.OnExpanding(Frame.Tree, Source, Allow);
    Assert.AreEqual(1, mProbe.FAsked);
    Assert.AreEqual('S', mProbe.FAskedKey);
    Assert.AreEqual(2, Integer(Length(mProbe.FAskedPath)));
    Assert.AreEqual('X', mProbe.FAskedPath[0]);
    Assert.AreEqual('S', mProbe.FAskedPath[1]);
    Assert.IsTrue(Allow);
    Assert.AreEqual(1, Integer(Source.Count));
    Assert.Contains(Source.Item[0].Text, 'Summe := 5;');
    // Ein zweites Aufklappen fragt nicht noch einmal.
    Frame.Tree.OnExpanding(Frame.Tree, Source, Allow);
    Assert.AreEqual(1, mProbe.FAsked);
    // Doppelklick springt zum Fundort.
    Frame.Tree.Selected := Source.Item[0];
    Frame.Tree.OnDblClick(Frame.Tree);
    Assert.AreEqual('C:\P\Haupt.pas', mProbe.FOpenedFile);
    Assert.AreEqual(20, mProbe.FOpenedLine);
    Frame.Tree.Selected := Root(Frame, 0).Item[1];
    Frame.Tree.OnDblClick(Frame.Tree);
    Assert.AreEqual(8, mProbe.FOpenedLine);
  finally
    mProbe.FAskedPath := nil;
    Host.Free;
    mProbe.Free;
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
    Frame.Flow.OnFilter :=
      procedure(AOnlyProject, AExcludeTests: Boolean)
      begin
        Inc(Filtered);
        OnlyProject := AOnlyProject;
        ExcludeTests := AExcludeTests;
      end;
    // Tiefe 1: Die Quellen der ersten Ebene gehen nicht weiter auf.
    Frame.Flow.Show('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('Summe', [Place(11, 'X := Summe;')], [Symbol('Summe', 'S', TAtlasDataFlowLeaf.None)])]),
      1, False, True);
    Assert.AreEqual(0, Integer(Root(Frame, 0).Item[0].Count));
    Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafDepth), Root(Frame, 0).Item[0].Text);
    // Filter wie angefragt, Setzen meldet nichts.
    Assert.IsFalse(Frame.Flow.OnlyProjectCheck.Checked);
    Assert.IsTrue(Frame.Flow.ExcludeTestsCheck.Checked);
    Assert.AreEqual(0, Filtered);
    Frame.Flow.OnlyProjectCheck.Checked := True;
    Assert.AreEqual(1, Filtered);
    Assert.IsTrue(OnlyProject);
    Assert.IsTrue(ExcludeTests);
    // Andere Listen blenden die Filter aus und melden nichts mehr.
    Frame.Entries.Show('Referenzen', nil);
    Assert.IsFalse(Frame.Flow.Shows);
    Frame.Flow.ExcludeTestsCheck.Checked := False;
    Assert.AreEqual(1, Filtered);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsDataFlowTests);

end.
