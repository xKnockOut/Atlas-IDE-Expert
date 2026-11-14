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
  mNode: TTreeNode;
begin
  Result := 0;
  mNode := AFrame.Tree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    Inc(Result);
    mNode := mNode.getNextSibling;
  end;
end;

{ TAtlasResultsDataFlowTests }

procedure TAtlasResultsDataFlowTests.NodeTextShowsKindDetailViaUnsafeAndPlace;
var
  mNode: TAtlasDataFlowNode;
  mText: string;
begin
  mNode := Assignment('A + B', [Place(11, 'X := A + B;')], nil);
  mNode.Via := 'Summe';
  mNode.Unsafe := True;
  mNode.UnsafeReason := 'pointer';
  mText := TAtlasResultsTexts.FlowNodeText(mNode);
  Assert.StartsWith(TAtlasStrings.Text(TAtlasTextId.DataFlowAssignment) + ': A + B', mText);
  Assert.Contains(mText, TAtlasResultsStrings.Fmt(TAtlasResultsTextId.DataFlowVia, ['Summe']));
  Assert.Contains(mText, TAtlasResultsStrings.Fmt(TAtlasResultsTextId.DataFlowUnsafe,
    [TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowUnsafePointer)]));
  Assert.EndsWith('Haupt.pas:12: X := A + B;', mText);
  // Zusammengefasst: Anzahl und Mehrzahl, der Fundort steht darunter.
  mNode := Assignment('0', [Place(3, 'X := 0;'), Place(8, 'X := 0;'), Place(9, 'X := 0;')], nil);
  mNode.Literal := True;
  mText := TAtlasResultsTexts.FlowNodeText(mNode);
  Assert.StartsWith('3 ' + TAtlasStrings.Text(TAtlasTextId.DataFlowAssignments), mText);
  Assert.Contains(mText, TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOriginLiteral));
  Assert.IsFalse(mText.Contains('Haupt.pas'), 'ohne Fundort');
  Assert.AreEqual('Haupt.pas:4: X := 0;', TAtlasResultsTexts.FlowPlaceText(mNode.Places[0]));
end;

procedure TAtlasResultsDataFlowTests.SourceTextShowsArrowLeafAndDepth;
var
  mChild: TAtlasDataFlowChild;
begin
  mChild := Default(TAtlasDataFlowChild);
  mChild.Kind := TAtlasDataFlowChildKind.Source;
  mChild.Source := Symbol('Summe', 'S', TAtlasDataFlowLeaf.None);
  Assert.AreEqual('← Summe  (Daten.pas:11)', TAtlasResultsTexts.FlowSourceText(mChild,
    TAtlasDataFlowDirection.Sources));
  Assert.AreEqual('→ Summe  (Daten.pas:11)', TAtlasResultsTexts.FlowSourceText(mChild,
    TAtlasDataFlowDirection.Targets));
  mChild.DepthReached := True;
  Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafDepth),
    TAtlasResultsTexts.FlowSourceText(mChild,
    TAtlasDataFlowDirection.Sources));
  mChild.DepthReached := False;
  mChild.Source.Leaf := TAtlasDataFlowLeaf.Cycle;
  Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafCycle),
    TAtlasResultsTexts.FlowSourceText(mChild,
    TAtlasDataFlowDirection.Sources));
  mChild.Source.Leaf := TAtlasDataFlowLeaf.Constant;
  Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafConstant),
    TAtlasResultsTexts.FlowSourceText(mChild,
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
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Flow.Show('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('0', [Place(3, 'X := 0;')], nil)]), 6, False, False);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasResultsDataFlowTests.TreeGroupsPlacesExpandsLazilyAndJumps;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mSource: TTreeNode;
  mAllow: Boolean;
  mProbe: TDataFlowProbe;
begin
  mProbe := TDataFlowProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    WireDataFlow(mFrame, mProbe);
    mFrame.Flow.Show('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('0', [Place(3, 'X := 0;'), Place(8, 'X := 0;')], nil),
      Assignment('Summe', [Place(11, 'X := Summe;')], [Symbol('Summe', 'S', TAtlasDataFlowLeaf.None)])]), 6,
      False, False);
    Assert.IsTrue(mFrame.Flow.Shows);
    Assert.AreEqual(2, RootCount(mFrame));
    // Zusammengefasst: beide Fundorte darunter.
    Assert.AreEqual(2, Integer(Root(mFrame, 0).Count));
    Assert.AreEqual('Haupt.pas:9: X := 0;', Root(mFrame, 0).Item[1].Text);
    // Quelle mit Platzhalter; geladen wird erst beim Aufklappen.
    mSource := Root(mFrame, 1).Item[0];
    Assert.AreEqual(1, Integer(mSource.Count));
    Assert.AreEqual(0, mProbe.FAsked);
    mAllow := True;
    mFrame.Tree.OnExpanding(mFrame.Tree, mSource, mAllow);
    Assert.AreEqual(1, mProbe.FAsked);
    Assert.AreEqual('S', mProbe.FAskedKey);
    Assert.AreEqual(2, Integer(Length(mProbe.FAskedPath)));
    Assert.AreEqual('X', mProbe.FAskedPath[0]);
    Assert.AreEqual('S', mProbe.FAskedPath[1]);
    Assert.IsTrue(mAllow);
    Assert.AreEqual(1, Integer(mSource.Count));
    Assert.Contains(mSource.Item[0].Text, 'Summe := 5;');
    // Ein zweites Aufklappen fragt nicht noch einmal.
    mFrame.Tree.OnExpanding(mFrame.Tree, mSource, mAllow);
    Assert.AreEqual(1, mProbe.FAsked);
    // Doppelklick springt zum Fundort.
    mFrame.Tree.Selected := mSource.Item[0];
    mFrame.Tree.OnDblClick(mFrame.Tree);
    Assert.AreEqual('C:\P\Haupt.pas', mProbe.FOpenedFile);
    Assert.AreEqual(20, mProbe.FOpenedLine);
    mFrame.Tree.Selected := Root(mFrame, 0).Item[1];
    mFrame.Tree.OnDblClick(mFrame.Tree);
    Assert.AreEqual(8, mProbe.FOpenedLine);
  finally
    mProbe.FAskedPath := nil;
    mHost.Free;
    mProbe.Free;
  end;
end;

procedure TAtlasResultsDataFlowTests.DepthLimitAndFilterBar;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mFiltered: Integer;
  mOnlyProject, mExcludeTests: Boolean;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFiltered := 0;
    mOnlyProject := False;
    mExcludeTests := False;
    mFrame.Flow.OnFilter :=
      procedure(AOnlyProject, AExcludeTests: Boolean)
      begin
        Inc(mFiltered);
        mOnlyProject := AOnlyProject;
        mExcludeTests := AExcludeTests;
      end;
    // Tiefe 1: Die Quellen der ersten Ebene gehen nicht weiter auf.
    mFrame.Flow.Show('Woher kommt X?', TAtlasDataFlowDirection.Sources,
      Answer([Assignment('Summe', [Place(11, 'X := Summe;')], [Symbol('Summe', 'S', TAtlasDataFlowLeaf.None)])]),
      1, False, True);
    Assert.AreEqual(0, Integer(Root(mFrame, 0).Item[0].Count));
    Assert.EndsWith(TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafDepth), Root(mFrame, 0).Item[0].Text);
    // Filter wie angefragt, Setzen meldet nichts.
    Assert.IsFalse(mFrame.Flow.OnlyProjectCheck.Checked);
    Assert.IsTrue(mFrame.Flow.ExcludeTestsCheck.Checked);
    Assert.AreEqual(0, mFiltered);
    mFrame.Flow.OnlyProjectCheck.Checked := True;
    Assert.AreEqual(1, mFiltered);
    Assert.IsTrue(mOnlyProject);
    Assert.IsTrue(mExcludeTests);
    // Andere Listen blenden die Filter aus und melden nichts mehr.
    mFrame.Entries.Show('Referenzen', nil);
    Assert.IsFalse(mFrame.Flow.Shows);
    mFrame.Flow.ExcludeTestsCheck.Checked := False;
    Assert.AreEqual(1, mFiltered);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsDataFlowTests);

end.
