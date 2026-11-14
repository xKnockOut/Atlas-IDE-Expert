unit Atlas.Common.Architecture.SymbolPath.Nodes.Tests;

// Tests der Knoten und Kanten der Pfadsuche (#1117): Typnamen in Typangaben,
// uses-Treffer, eine Routine als ein Knoten, Endpunkte, Sortierung der Kanten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.SymbolPath.Nodes;

type
  [TestFixture]
  TSymbolPathNodesTests = class
  private
    FIndex: ISymbolIndex;
    FTable: TSymbolPathNodeTable;
    procedure AddUnit(const AName, AText: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TypeNamesSkipTypeWords;
    [Test]
    procedure UsesMatchesNamespace;
    [Test]
    procedure RoutineBodyIsDeclarationNode;
    [Test]
    procedure EndpointsFindUnitAndQualifiedSymbol;
    [Test]
    procedure TargetsOfTypeIncludeMembers;
    [Test]
    procedure EdgeListSortsAndDropsDuplicates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cKundeText =
    'unit uKunde;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '    FName: string;'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    'procedure Hilfe;'#10 +
    'implementation'#10 +
    'procedure TKunde.Laden;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Hilfe;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

procedure TSymbolPathNodesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('uKunde', cKundeText);
  FTable := TSymbolPathNodeTable.Create(FIndex);
end;

procedure TSymbolPathNodesTests.TearDown;
begin
  FTable.Free;
  FTable := nil;
  FIndex := nil;
end;

procedure TSymbolPathNodesTests.AddUnit(const AName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, 'C:\P\' + AName + '.pas', nil));
end;

procedure TSymbolPathNodesTests.TypeNamesSkipTypeWords;
var
  mNames: TArray<string>;
begin
  mNames := TSymbolPathNames.TypeNamesIn('array of TList<&TKunde.>');
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('TList', mNames[0]);
  Assert.AreEqual('TKunde', mNames[1]);
  Assert.AreEqual(0, Integer(Length(TSymbolPathNames.TypeNamesIn('reference to procedure'))));
  Assert.AreEqual('Bar', TSymbolPathNames.LastSegment('Foo.Bar'));
end;

procedure TSymbolPathNodesTests.UsesMatchesNamespace;
begin
  Assert.IsTrue(TSymbolPathNames.UsesMatches('SysUtils', 'System.SysUtils'));
  Assert.IsTrue(TSymbolPathNames.UsesMatches('system.sysutils', 'System.SysUtils'));
  Assert.IsFalse(TSymbolPathNames.UsesMatches('Utils', 'System.SysUtils'));
end;

procedure TSymbolPathNodesTests.RoutineBodyIsDeclarationNode;
var
  mNodes: TArray<Integer>;
begin
  // Deklaration in der Klasse und Rumpf im implementation-Teil sind ein Knoten.
  mNodes := FTable.Endpoints('TKunde.Laden', nil);
  Assert.AreEqual(1, Integer(Length(mNodes)));
  Assert.AreEqual(5, FTable.Node(mNodes[0]).Position.Line);
  // Ebenso eine freie Routine mit Deklaration im interface.
  mNodes := FTable.Endpoints('Hilfe', nil);
  Assert.AreEqual(1, Integer(Length(mNodes)));
  Assert.AreEqual(7, FTable.Node(mNodes[0]).Position.Line);
end;

procedure TSymbolPathNodesTests.EndpointsFindUnitAndQualifiedSymbol;
var
  mNodes: TArray<Integer>;
begin
  mNodes := FTable.Endpoints('uKunde', nil);
  Assert.AreEqual(1, Integer(Length(mNodes)));
  Assert.IsTrue(FTable.Node(mNodes[0]).IsUnit);
  Assert.AreEqual(FTable.UnitNode('ukunde'), mNodes[0]);
  mNodes := FTable.Endpoints('uKunde.TKunde', nil);
  Assert.AreEqual(1, Integer(Length(mNodes)));
  Assert.AreEqual('TKunde', FTable.Node(mNodes[0]).Caption);
  Assert.AreEqual(0, Integer(Length(FTable.Endpoints('TFehlt', nil))));
end;

procedure TSymbolPathNodesTests.TargetsOfTypeIncludeMembers;
var
  mType: Integer;
  mTargets: TArray<Integer>;
  mField: Integer;
begin
  mType := FTable.Endpoints('TKunde', nil)[0];
  mTargets := FTable.Targets(mType);
  Assert.AreEqual(mType, mTargets[0]);
  // Typ, Feld, Methode; der Rumpf der Methode ist derselbe Knoten wie ihre Deklaration.
  Assert.AreEqual(4, Integer(Length(mTargets)));
  Assert.AreEqual(mTargets[2], mTargets[3]);
  mField := FTable.Endpoints('TKunde.FName', nil)[0];
  Assert.AreEqual('TKunde.FName: string', FTable.Node(mField).Caption);
  Assert.AreEqual(mType, FTable.ContainerNode(FTable.NodeUnit(mField), FTable.Node(mField).Symbol));
  Assert.AreEqual(FTable.Endpoints('TKunde.Laden', nil)[0], FTable.MemberNamed(mType, 'laden'));
end;

procedure TSymbolPathNodesTests.EdgeListSortsAndDropsDuplicates;
var
  mList: TSymbolPathEdgeList;
  mEdges: TSymbolPathEdges;
  mType, mField: Integer;
begin
  mType := FTable.Endpoints('TKunde', nil)[0];
  mField := FTable.Endpoints('TKunde.FName', nil)[0];
  mList := TSymbolPathEdgeList.Create(FTable);
  try
    mList.Add(mField, TSymbolPathEdgeKind.Contains, False, 'a.pas', TTextPosition.Create(1, 0));
    mList.Add(mType, TSymbolPathEdgeKind.Inherits, False, 'a.pas', TTextPosition.Create(2, 0));
    mList.Add(mField, TSymbolPathEdgeKind.Contains, False, 'a.pas', TTextPosition.Create(3, 0));
    mList.AddReverse(mType, True);
    mEdges := mList.ToArray;
  finally
    mList.Free;
  end;
  // Rang der Kantenart zuerst; gleiche Kanten nur einmal (die mit der früheren Fundstelle).
  Assert.AreEqual(3, Integer(Length(mEdges)));
  Assert.AreEqual<TSymbolPathEdgeKind>(TSymbolPathEdgeKind.Inherits, mEdges[0].Kind);
  Assert.AreEqual<TSymbolPathEdgeKind>(TSymbolPathEdgeKind.Implements, mEdges[1].Kind);
  Assert.IsTrue(mEdges[1].Reverse);
  Assert.IsTrue(mEdges[1].Inferred);
  Assert.AreEqual<TSymbolPathEdgeKind>(TSymbolPathEdgeKind.Contains, mEdges[2].Kind);
  Assert.AreEqual(1, mEdges[2].Position.Line);
end;

end.
