unit Atlas.Common.Architecture.SymbolPath.Graph.Tests;

// Tests der Kanten aus dem Index für die Pfadsuche (#1117): Vorfahr und
// Interface, Umsetzung in Gegenrichtung (erschlossen bei mehreren), Feldtyp,
// Vorgänger nur mit erlaubter Kante, Bibliothek kein Durchgang.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.SymbolPath.Nodes,
  Atlas.Common.Architecture.SymbolPath.Graph;

type
  [TestFixture]
  TSymbolPathGraphTests = class
  private
    FIndex: ISymbolIndex;
    FTable: TSymbolPathNodeTable;
    FGraph: TSymbolPathGraph;
    procedure AddUnit(const AName, AText: string; ALibrary: Boolean);
    function NodeOf(const AName: string): Integer;
    function HasEdge(ASource, ATarget: Integer; AKind: TSymbolPathEdgeKind; out AEdge: TSymbolPathEdge): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ClassEdgesToAncestorAndInterface;
    [Test]
    procedure InterfaceEdgesToImplementers;
    [Test]
    procedure FieldEdgeToType;
    [Test]
    procedure PredecessorsFollowAllowedKinds;
    [Test]
    procedure LibraryIsNoPassage;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cIntfText =
    'unit uIntf;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IRepo = interface'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    '  TBasis = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  cRepoText =
    'unit uRepo;'#10 +
    'interface'#10 +
    'uses uIntf;'#10 +
    'type'#10 +
    '  TRepo = class(TBasis, IRepo)'#10 +
    '    FBasis: TBasis;'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    '  TCache = class(TInterfacedObject, IRepo)'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TRepo.Laden;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TCache.Laden;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cBibText =
    'unit uBib;'#10 +
    'interface'#10 +
    'uses uIntf;'#10 +
    'type'#10 +
    '  TBib = class(TBasis)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

procedure TSymbolPathGraphTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('uIntf', cIntfText, False);
  AddUnit('uRepo', cRepoText, False);
  AddUnit('uBib', cBibText, True);
  FTable := TSymbolPathNodeTable.Create(FIndex);
  FGraph := TSymbolPathGraph.Create(FTable, nil);
  FGraph.Configure([Low(TSymbolPathEdgeKind)..High(TSymbolPathEdgeKind)], False, nil);
end;

procedure TSymbolPathGraphTests.TearDown;
begin
  FGraph.Free;
  FGraph := nil;
  FTable.Free;
  FTable := nil;
  FIndex := nil;
end;

procedure TSymbolPathGraphTests.AddUnit(const AName, AText: string; ALibrary: Boolean);
var
  mData: TUnitIndex;
begin
  mData := TIndexExtractor.ExtractText(AText, 'C:\P\' + AName + '.pas', nil);
  mData.Library_ := ALibrary;
  FIndex.AddUnit(mData);
end;

function TSymbolPathGraphTests.NodeOf(const AName: string): Integer;
begin
  Result := FTable.Endpoints(AName, nil)[0];
end;

function TSymbolPathGraphTests.HasEdge(ASource, ATarget: Integer; AKind: TSymbolPathEdgeKind;
  out AEdge: TSymbolPathEdge): Boolean;
var
  mEdge: TSymbolPathEdge;
begin
  AEdge := Default(TSymbolPathEdge);
  for mEdge in FGraph.ForwardOf(ASource) do
  begin
    if (mEdge.Target = ATarget) and (mEdge.Kind = AKind) then
    begin
      AEdge := mEdge;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSymbolPathGraphTests.ClassEdgesToAncestorAndInterface;
var
  mEdge: TSymbolPathEdge;
begin
  Assert.IsTrue(HasEdge(NodeOf('TRepo'), NodeOf('TBasis'), TSymbolPathEdgeKind.Inherits, mEdge));
  Assert.IsTrue(HasEdge(NodeOf('TRepo'), NodeOf('IRepo'), TSymbolPathEdgeKind.Implements, mEdge));
  Assert.IsFalse(mEdge.Reverse);
  // Methode der Klasse → Interface-Methode, die sie umsetzt.
  Assert.IsTrue(HasEdge(NodeOf('TRepo.Laden'), NodeOf('IRepo.Laden'), TSymbolPathEdgeKind.Implements, mEdge));
  Assert.IsFalse(mEdge.Inferred);
end;

procedure TSymbolPathGraphTests.InterfaceEdgesToImplementers;
var
  mEdge: TSymbolPathEdge;
begin
  Assert.IsTrue(HasEdge(NodeOf('IRepo'), NodeOf('TRepo'), TSymbolPathEdgeKind.Implements, mEdge));
  Assert.IsTrue(mEdge.Reverse);
  // Zwei Umsetzungen: erschlossen (#1119).
  Assert.IsTrue(mEdge.Inferred);
  Assert.IsTrue(HasEdge(NodeOf('IRepo.Laden'), NodeOf('TCache.Laden'), TSymbolPathEdgeKind.Implements, mEdge));
  Assert.IsTrue(mEdge.Reverse);
end;

procedure TSymbolPathGraphTests.FieldEdgeToType;
var
  mEdge: TSymbolPathEdge;
begin
  Assert.IsTrue(HasEdge(NodeOf('TRepo'), NodeOf('TBasis'), TSymbolPathEdgeKind.HasField, mEdge));
  Assert.AreEqual(5, mEdge.Position.Line);
  Assert.IsTrue(HasEdge(NodeOf('TRepo.FBasis'), NodeOf('TBasis'), TSymbolPathEdgeKind.HasField, mEdge));
  Assert.IsTrue(HasEdge(NodeOf('uRepo'), NodeOf('TRepo'), TSymbolPathEdgeKind.Contains, mEdge));
end;

procedure TSymbolPathGraphTests.PredecessorsFollowAllowedKinds;
var
  mPredecessors: TArray<Integer>;
  mNode: Integer;
  mFound: Boolean;
begin
  mPredecessors := FGraph.PredecessorsOf(NodeOf('TBasis'));
  mFound := False;
  for mNode in mPredecessors do
  begin
    mFound := mFound or (mNode = NodeOf('TRepo'));
  end;
  Assert.IsTrue(mFound);
  Assert.IsTrue(FGraph.Leads(NodeOf('TRepo'), NodeOf('TBasis')));
  // Nur noch contains erlaubt: TRepo hat keine Kante mehr nach TBasis.
  FGraph.Configure([TSymbolPathEdgeKind.Contains], False, nil);
  Assert.IsFalse(FGraph.Leads(NodeOf('TRepo'), NodeOf('TBasis')));
end;

procedure TSymbolPathGraphTests.LibraryIsNoPassage;
begin
  Assert.IsFalse(FGraph.Passable(NodeOf('TBib')));
  Assert.IsTrue(FGraph.Passable(NodeOf('TRepo')));
  FGraph.Configure([Low(TSymbolPathEdgeKind)..High(TSymbolPathEdgeKind)], False,
    TArray<Integer>.Create(NodeOf('TBib')));
  Assert.IsTrue(FGraph.Passable(NodeOf('TBib')));
  FGraph.Configure([Low(TSymbolPathEdgeKind)..High(TSymbolPathEdgeKind)], True, nil);
  Assert.IsTrue(FGraph.Passable(NodeOf('TBib')));
end;

end.
