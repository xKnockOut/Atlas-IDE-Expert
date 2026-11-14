unit Atlas.Core.Results.DataFlow.Tests;

// Datenfluss (#690) im Ergebnisfenster: Kinder einer Stelle, Tiefengrenze, Blätter und Pfad.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasResultsDataFlowTests = class
  public
    [Test]
    procedure GroupedPlacesBeforeSources;
    [Test]
    procedure SinglePlaceHasNoPlaceChildren;
    [Test]
    procedure LeavesAndDepthLimit;
    [Test]
    procedure OriginOfLeafNodes;
    [Test]
    procedure PathAndDepthRange;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Results.DataFlow;

function Place(ALine: Integer): TAtlasDataFlowPlace;
begin
  Result := Default(TAtlasDataFlowPlace);
  Result.FileName := 'C:\P\Haupt.pas';
  Result.Line := ALine;
end;

function Source(const AName: string; ALeaf: TAtlasDataFlowLeaf): TAtlasDataFlowSymbol;
begin
  Result := Default(TAtlasDataFlowSymbol);
  Result.Name := AName;
  Result.Key := AName;
  Result.Leaf := ALeaf;
end;

{ TAtlasResultsDataFlowTests }

procedure TAtlasResultsDataFlowTests.GroupedPlacesBeforeSources;
var
  Node: TAtlasDataFlowNode;
  Children: TArray<TAtlasDataFlowChild>;
begin
  Node := Default(TAtlasDataFlowNode);
  Node.Places := [Place(3), Place(8), Place(12)];
  Node.Sources := [Source('Summe', TAtlasDataFlowLeaf.None)];
  Children := TAtlasDataFlowTree.Children(Node, 1, 6);
  Assert.AreEqual(4, Integer(Length(Children)));
  Assert.AreEqual<TAtlasDataFlowChildKind>(TAtlasDataFlowChildKind.Place, Children[0].Kind);
  Assert.AreEqual(12, Children[2].Place.Line);
  Assert.AreEqual<TAtlasDataFlowChildKind>(TAtlasDataFlowChildKind.Source, Children[3].Kind);
  Assert.IsTrue(Children[3].Expandable);
  Assert.AreEqual(3, TAtlasDataFlowTree.FirstPlace(Node).Line);
end;

procedure TAtlasResultsDataFlowTests.SinglePlaceHasNoPlaceChildren;
var
  Node: TAtlasDataFlowNode;
begin
  Node := Default(TAtlasDataFlowNode);
  Node.Places := [Place(3)];
  Assert.AreEqual(0, Integer(Length(TAtlasDataFlowTree.Children(Node, 1, 6))));
  Assert.AreEqual(0, TAtlasDataFlowTree.FirstPlace(Default(TAtlasDataFlowNode)).Line);
end;

procedure TAtlasResultsDataFlowTests.LeavesAndDepthLimit;
var
  Node: TAtlasDataFlowNode;
  Children: TArray<TAtlasDataFlowChild>;
begin
  Node := Default(TAtlasDataFlowNode);
  Node.Places := [Place(3)];
  Node.Sources := [Source('A', TAtlasDataFlowLeaf.None), Source('cMax', TAtlasDataFlowLeaf.Constant),
    Source('X', TAtlasDataFlowLeaf.Cycle), Source('IntToStr', TAtlasDataFlowLeaf.Outside)];
  Children := TAtlasDataFlowTree.Children(Node, 5, 6);
  Assert.IsTrue(Children[0].Expandable);
  Assert.IsFalse(Children[1].Expandable);
  Assert.IsFalse(Children[1].DepthReached, 'Konstante ist ein Blatt, keine Grenze');
  Assert.IsFalse(Children[2].Expandable);
  Assert.IsFalse(Children[3].Expandable);
  // Auf der letzten erlaubten Ebene geht nichts mehr auf.
  Children := TAtlasDataFlowTree.Children(Node, 6, 6);
  Assert.IsFalse(Children[0].Expandable);
  Assert.IsTrue(Children[0].DepthReached);
  Children := TAtlasDataFlowTree.Children(Node, 1, 1);
  Assert.IsTrue(Children[0].DepthReached);
end;

procedure TAtlasResultsDataFlowTests.OriginOfLeafNodes;
var
  Node: TAtlasDataFlowNode;
begin
  Node := Default(TAtlasDataFlowNode);
  Node.Places := [Place(3)];
  Node.Kind := TAtlasDataFlowKind.Assignment;
  Node.Literal := True;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Literal, TAtlasDataFlowTree.Origin(Node));
  Node.Literal := False;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Open, TAtlasDataFlowTree.Origin(Node));
  Node.Via := 'IntToStr';
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Outside, TAtlasDataFlowTree.Origin(Node));
  Node.Kind := TAtlasDataFlowKind.Input;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Input, TAtlasDataFlowTree.Origin(Node));
  Node.Kind := TAtlasDataFlowKind.Output;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Output, TAtlasDataFlowTree.Origin(Node));
  Node.Kind := TAtlasDataFlowKind.Use;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Use, TAtlasDataFlowTree.Origin(Node));
  Node.Kind := TAtlasDataFlowKind.Address;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Address, TAtlasDataFlowTree.Origin(Node));
  Node.Kind := TAtlasDataFlowKind.Constant;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Constant, TAtlasDataFlowTree.Origin(Node));
  Node.Sources := [Source('A', TAtlasDataFlowLeaf.None)];
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.None, TAtlasDataFlowTree.Origin(Node));
end;

procedure TAtlasResultsDataFlowTests.PathAndDepthRange;
var
  Path: TArray<string>;
begin
  Path := TAtlasDataFlowTree.ChildPath(nil, 'a');
  Path := TAtlasDataFlowTree.ChildPath(Path, 'b');
  Assert.AreEqual(2, Integer(Length(Path)));
  Assert.AreEqual('a', Path[0]);
  Assert.AreEqual('b', Path[1]);
  Assert.AreEqual(1, TAtlasDataFlowTree.ClampDepth(0));
  Assert.AreEqual(20, TAtlasDataFlowTree.ClampDepth(99));
  Assert.AreEqual(6, TAtlasDataFlowTree.ClampDepth(6));
  Path := nil;
end;

end.
