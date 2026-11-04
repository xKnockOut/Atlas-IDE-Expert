unit Atlas.Common.Architecture.SymbolPath.Calls.Tests;

// Tests der Aufrufkanten der Pfadsuche (#1117): Aufrufe aus dem Rumpf,
// Aufrufer über die uses-Liste, ohne Quelltext keine Aufrufe, Abbruch
// ohne Zwischenspeicher.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.SymbolPath.Nodes,
  Atlas.Common.Architecture.SymbolPath.Graph,
  Atlas.Common.Architecture.SymbolPath.Calls;

type
  [TestFixture]
  TSymbolPathCallsTests = class
  private
    FFiles: TDictionary<string, string>;
    FIndex: ISymbolIndex;
    FTable: TSymbolPathNodeTable;
    FGraph: TSymbolPathGraph;
    FCalls: TSymbolPathCalls;
    procedure AddUnit(const AName, AText: string);
    function NodeOf(const AName: string): Integer;
    function Reader: TSymbolPathReadText;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CallsFromBody;
    [Test]
    procedure CallersOfRoutine;
    [Test]
    procedure NoCallsWithoutReader;
    [Test]
    procedure StoppedSearchIsNotCached;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cZielText =
    'unit uZiel;'#10 +
    'interface'#10 +
    'procedure Ziel;'#10 +
    'implementation'#10 +
    'procedure Ziel;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cStartText =
    'unit uStart;'#10 +
    'interface'#10 +
    'uses uZiel;'#10 +
    'procedure Start;'#10 +
    'implementation'#10 +
    'procedure Start;'#10 +
    'begin'#10 +
    '  Ziel;'#10 +
    'end;'#10 +
    'end.';

function FileOf(const AName: string): string;
begin
  Result := 'C:\P\' + AName + '.pas';
end;

procedure TSymbolPathCallsTests.Setup;
begin
  FFiles := TDictionary<string, string>.Create;
  FIndex := TSymbolIndex.Create;
  AddUnit('uZiel', cZielText);
  AddUnit('uStart', cStartText);
  FTable := TSymbolPathNodeTable.Create(FIndex);
  FGraph := TSymbolPathGraph.Create(FTable, nil);
  FGraph.Configure([Low(TSymbolPathEdgeKind)..High(TSymbolPathEdgeKind)], False, nil);
  FCalls := TSymbolPathCalls.Create(FTable, FGraph, Reader(), nil, nil);
end;

procedure TSymbolPathCallsTests.TearDown;
begin
  FCalls.Free;
  FCalls := nil;
  FGraph.Free;
  FGraph := nil;
  FTable.Free;
  FTable := nil;
  FIndex := nil;
  FFiles.Free;
  FFiles := nil;
end;

procedure TSymbolPathCallsTests.AddUnit(const AName, AText: string);
begin
  FFiles.AddOrSetValue(FileOf(AName), AText);
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, FileOf(AName), nil));
end;

function TSymbolPathCallsTests.NodeOf(const AName: string): Integer;
begin
  Result := FTable.Endpoints(AName, nil)[0];
end;

function TSymbolPathCallsTests.Reader: TSymbolPathReadText;
var
  mFiles: TDictionary<string, string>;
begin
  mFiles := FFiles;
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFiles.TryGetValue(AFileName, AText);
    end;
end;

procedure TSymbolPathCallsTests.CallsFromBody;
var
  mEdges: TSymbolPathEdges;
begin
  mEdges := FCalls.CallsOf(NodeOf('Start'));
  Assert.AreEqual(1, Integer(Length(mEdges)));
  Assert.AreEqual(NodeOf('Ziel'), mEdges[0].Target);
  Assert.IsTrue(mEdges[0].Kind = TSymbolPathEdgeKind.Calls);
  // Fundstelle ist der Aufruf im Rumpf.
  Assert.AreEqual(7, mEdges[0].Position.Line);
  Assert.IsTrue(FCalls.Leads(NodeOf('Start'), NodeOf('Ziel')));
  Assert.AreEqual(0, Integer(Length(FCalls.CallsOf(NodeOf('uStart')))));
end;

procedure TSymbolPathCallsTests.CallersOfRoutine;
var
  mCallers: TArray<Integer>;
begin
  // Deklaration und Rumpf von Start sind derselbe Knoten und stehen je einmal da.
  mCallers := FCalls.CallersOf(NodeOf('Ziel'));
  Assert.AreEqual(2, Integer(Length(mCallers)));
  Assert.AreEqual(NodeOf('Start'), mCallers[0]);
  Assert.AreEqual(NodeOf('Start'), mCallers[1]);
end;

procedure TSymbolPathCallsTests.NoCallsWithoutReader;
var
  mCalls: TSymbolPathCalls;
begin
  mCalls := TSymbolPathCalls.Create(FTable, FGraph, nil, nil, nil);
  try
    Assert.AreEqual(0, Integer(Length(mCalls.CallsOf(NodeOf('Start')))));
  finally
    mCalls.Free;
  end;
end;

procedure TSymbolPathCallsTests.StoppedSearchIsNotCached;
var
  mStop: Boolean;
begin
  mStop := True;
  FCalls.Stopped :=
    function: Boolean
    begin
      Result := mStop;
    end;
  Assert.AreEqual(0, Integer(Length(FCalls.CallersOf(NodeOf('Ziel')))));
  // Nach dem Abbruch wird neu gesucht.
  mStop := False;
  Assert.AreEqual(2, Integer(Length(FCalls.CallersOf(NodeOf('Ziel')))));
  FCalls.Stopped := nil;
end;

end.
