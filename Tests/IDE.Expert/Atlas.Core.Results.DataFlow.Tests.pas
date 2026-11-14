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
  mNode: TAtlasDataFlowNode;
  mChildren: TArray<TAtlasDataFlowChild>;
begin
  mNode := Default(TAtlasDataFlowNode);
  mNode.Places := [Place(3), Place(8), Place(12)];
  mNode.Sources := [Source('Summe', TAtlasDataFlowLeaf.None)];
  mChildren := TAtlasDataFlowTree.Children(mNode, 1, 6);
  Assert.AreEqual(4, Integer(Length(mChildren)));
  Assert.AreEqual<TAtlasDataFlowChildKind>(TAtlasDataFlowChildKind.Place, mChildren[0].Kind);
  Assert.AreEqual(12, mChildren[2].Place.Line);
  Assert.AreEqual<TAtlasDataFlowChildKind>(TAtlasDataFlowChildKind.Source, mChildren[3].Kind);
  Assert.IsTrue(mChildren[3].Expandable);
  Assert.AreEqual(3, TAtlasDataFlowTree.FirstPlace(mNode).Line);
end;

procedure TAtlasResultsDataFlowTests.SinglePlaceHasNoPlaceChildren;
var
  mNode: TAtlasDataFlowNode;
begin
  mNode := Default(TAtlasDataFlowNode);
  mNode.Places := [Place(3)];
  Assert.AreEqual(0, Integer(Length(TAtlasDataFlowTree.Children(mNode, 1, 6))));
  Assert.AreEqual(0, TAtlasDataFlowTree.FirstPlace(Default(TAtlasDataFlowNode)).Line);
end;

procedure TAtlasResultsDataFlowTests.LeavesAndDepthLimit;
var
  mNode: TAtlasDataFlowNode;
  mChildren: TArray<TAtlasDataFlowChild>;
begin
  mNode := Default(TAtlasDataFlowNode);
  mNode.Places := [Place(3)];
  mNode.Sources := [Source('A', TAtlasDataFlowLeaf.None), Source('cMax', TAtlasDataFlowLeaf.Constant),
    Source('X', TAtlasDataFlowLeaf.Cycle), Source('IntToStr', TAtlasDataFlowLeaf.Outside)];
  mChildren := TAtlasDataFlowTree.Children(mNode, 5, 6);
  Assert.IsTrue(mChildren[0].Expandable);
  Assert.IsFalse(mChildren[1].Expandable);
  Assert.IsFalse(mChildren[1].DepthReached, 'Konstante ist ein Blatt, keine Grenze');
  Assert.IsFalse(mChildren[2].Expandable);
  Assert.IsFalse(mChildren[3].Expandable);
  // Auf der letzten erlaubten Ebene geht nichts mehr auf.
  mChildren := TAtlasDataFlowTree.Children(mNode, 6, 6);
  Assert.IsFalse(mChildren[0].Expandable);
  Assert.IsTrue(mChildren[0].DepthReached);
  mChildren := TAtlasDataFlowTree.Children(mNode, 1, 1);
  Assert.IsTrue(mChildren[0].DepthReached);
end;

procedure TAtlasResultsDataFlowTests.OriginOfLeafNodes;
var
  mNode: TAtlasDataFlowNode;
begin
  mNode := Default(TAtlasDataFlowNode);
  mNode.Places := [Place(3)];
  mNode.Kind := TAtlasDataFlowKind.Assignment;
  mNode.Literal := True;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Literal, TAtlasDataFlowTree.Origin(mNode));
  mNode.Literal := False;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Open, TAtlasDataFlowTree.Origin(mNode));
  mNode.Via := 'IntToStr';
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Outside, TAtlasDataFlowTree.Origin(mNode));
  mNode.Kind := TAtlasDataFlowKind.Input;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Input, TAtlasDataFlowTree.Origin(mNode));
  mNode.Kind := TAtlasDataFlowKind.Output;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Output, TAtlasDataFlowTree.Origin(mNode));
  mNode.Kind := TAtlasDataFlowKind.Use;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Use, TAtlasDataFlowTree.Origin(mNode));
  mNode.Kind := TAtlasDataFlowKind.Address;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Address, TAtlasDataFlowTree.Origin(mNode));
  mNode.Kind := TAtlasDataFlowKind.Constant;
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.Constant, TAtlasDataFlowTree.Origin(mNode));
  mNode.Sources := [Source('A', TAtlasDataFlowLeaf.None)];
  Assert.AreEqual<TAtlasDataFlowOrigin>(TAtlasDataFlowOrigin.None, TAtlasDataFlowTree.Origin(mNode));
end;

procedure TAtlasResultsDataFlowTests.PathAndDepthRange;
var
  mPath: TArray<string>;
begin
  mPath := TAtlasDataFlowTree.ChildPath(nil, 'a');
  mPath := TAtlasDataFlowTree.ChildPath(mPath, 'b');
  Assert.AreEqual(2, Integer(Length(mPath)));
  Assert.AreEqual('a', mPath[0]);
  Assert.AreEqual('b', mPath[1]);
  Assert.AreEqual(1, TAtlasDataFlowTree.ClampDepth(0));
  Assert.AreEqual(20, TAtlasDataFlowTree.ClampDepth(99));
  Assert.AreEqual(6, TAtlasDataFlowTree.ClampDepth(6));
  mPath := nil;
end;

end.
