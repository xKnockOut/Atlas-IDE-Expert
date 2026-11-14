unit Atlas.Common.Lsp.DataFlow.Parts.Tests;

// Tests der Teile des Datenflusses einzeln (Typen, Hilfen am Baum, Dateien des Laufs, Klassenkette
// Base → Sources → Targets). Das Verhalten von atlas/dataFlow prüft Atlas.Common.Lsp.DataFlow.Tests.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TDataFlowPartsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SymbolKeyAndParamSymbol;
    [Test]
    procedure CallSiteNamesCallee;
    [Test]
    procedure SyntaxTextHelpers;
    [Test]
    procedure RoutineNameAfterTypePrefix;
    [Test]
    procedure FilesKnowProjectLinesAndTests;
    [Test]
    procedure RunClimbsChainInBothDirections;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.DataFlow.Types,
  Atlas.Common.Lsp.DataFlow.Syntax,
  Atlas.Common.Lsp.DataFlow.Files,
  Atlas.Common.Lsp.DataFlow.Base,
  Atlas.Common.Lsp.DataFlow.Sources,
  Atlas.Common.Lsp.DataFlow.Targets;

const
  cFile = 'C:\P\Teile.pas';
  cTestFile = 'C:\P\Probe.pas';
  cUnit =
    'unit Teile;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(A: Integer);'#10 +
    'var'#10 +
    '  X, Y: Integer;'#10 +
    'begin'#10 +
    '    X := A;'#10 +
    '  Y := X;'#10 +
    'end;'#10 +
    'end.';
  cTestUnit =
    'unit Probe;'#10 +
    'interface'#10 +
    'uses DUnitX.TestFramework;'#10 +
    'implementation'#10 +
    'end.';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cFile) then
  begin
    AText := cUnit;
  end
  else if SameText(AFileName, cTestFile) then
  begin
    AText := cTestUnit;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Position des ersten Vorkommens von AMarker in cUnit.</summary>
function PositionOf(const AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  mIndex := Pos(AMarker, cUnit);
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if cUnit[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function NewRequest(ATree: TSyntaxTree; const AFiles: TArray<string>): TDataFlowRequest;
begin
  Result := Default(TDataFlowRequest);
  Result.Tree := ATree;
  Result.FileName := cFile;
  Result.Files := AFiles;
  Result.ReadText := ReadText;
end;

{ TDataFlowPartsTests }

procedure TDataFlowPartsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnit, cFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TDataFlowPartsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure TDataFlowPartsTests.SymbolKeyAndParamSymbol;
var
  mParam: TDataFlowParam;
  mSymbol: TDataFlowSymbol;
begin
  mParam := Default(TDataFlowParam);
  mParam.Name := 'AWert';
  mParam.FileName := 'c:\p\a.pas';
  mParam.Position := TTextPosition.Create(3, 4);
  mSymbol := mParam.Symbol;
  Assert.AreEqual('AWert', mSymbol.Name);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Variable, mSymbol.SymbolKind);
  Assert.AreEqual<TDataFlowLeaf>(TDataFlowLeaf.None, mSymbol.Leaf);
  Assert.AreEqual('C:\P\A.PAS|3:4', mSymbol.Key);
end;

procedure TDataFlowPartsTests.CallSiteNamesCallee;
var
  mTree: TSyntaxTree;
  mCall: TSyntaxNode;
  mSite: TDataFlowCallSite;
  mSpot: TDataFlowSpot;
begin
  mTree := TSyntaxTreeCache.Parse('unit U; implementation procedure P; begin System.Inc(N, 2); end; end.');
  try
    mCall := TDataFlowSyntax.NodeAt(mTree.Root, TTextPosition.Create(0, 50));
    while (mCall <> nil) and (mCall.Kind <> TSyntaxKind.Call) do
    begin
      mCall := mCall.Parent;
    end;
    Assert.IsNotNull(mCall);
    mSite := TDataFlowCallSite.Create(mTree, cFile, mCall, 0, TTextPosition.Create(0, 50), 'pointer');
    Assert.AreEqual('inc', mSite.Callee);
    Assert.AreEqual('Inc', mSite.Via);
    mSpot := mSite.Spot(TDataFlowKind.Modify);
    Assert.AreEqual<TDataFlowKind>(TDataFlowKind.Modify, mSpot.Kind);
    Assert.AreEqual(cFile, mSpot.FileName);
    Assert.AreEqual(50, mSpot.Position.Character);
  finally
    mTree.Free;
  end;
end;

procedure TDataFlowPartsTests.SyntaxTextHelpers;
var
  mLong: string;
begin
  Assert.AreEqual('Bar', TDataFlowSyntax.ShortName('TFoo.Bar'));
  Assert.AreEqual('Type', TDataFlowSyntax.CleanName('&Type'));
  Assert.AreEqual('A + B', TDataFlowSyntax.SingleLine('  A +'#13#10#9'  B  '));
  mLong := StringOfChar('x', 200);
  Assert.AreEqual(120, Integer(Length(TDataFlowSyntax.SingleLine(mLong))));
  Assert.IsTrue(TDataFlowSyntax.IsFormFile('C:\P\Haupt.DFM'));
  Assert.IsTrue(TDataFlowSyntax.IsFormFile('Haupt.fmx'));
  Assert.IsFalse(TDataFlowSyntax.IsFormFile('Haupt.pas'));
end;

procedure TDataFlowPartsTests.RoutineNameAfterTypePrefix;
var
  mTree: TSyntaxTree;
  mHeader, mStatement, mInner: TSyntaxNode;
  mPosition: TTextPosition;
  mReason: string;
begin
  mTree := TSyntaxTreeCache.Parse(cUnit);
  try
    mInner := TDataFlowSyntax.NodeAt(mTree.Root, PositionOf('X := A'));
    mHeader := TDataFlowSyntax.RoutineWithBody(mInner).FindChild(TSyntaxKind.RoutineHeader);
    Assert.IsTrue(TDataFlowSyntax.RoutineNamePosition(mTree, mHeader, 'Bar', mPosition));
    Assert.AreEqual(PositionOf('Bar').Character, mPosition.Character);
    Assert.IsFalse(TDataFlowSyntax.InRoutineHeader(mInner));
    mReason := '';
    Assert.IsTrue(TDataFlowSyntax.WrittenTarget(mInner, mStatement, mReason));
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.AssignStatement, mStatement.Kind);
    Assert.AreEqual('', mReason);
  finally
    mTree.Free;
  end;
end;

procedure TDataFlowPartsTests.FilesKnowProjectLinesAndTests;
var
  mTree: TSyntaxTree;
  mFiles: TDataFlowFiles;
begin
  mTree := TSyntaxTreeCache.Parse(cUnit);
  try
    mFiles := TDataFlowFiles.Create(NewRequest(mTree, TArray<string>.Create(cFile)));
    try
      Assert.AreSame(mTree, mFiles.TreeOf(cFile), 'Eigener Baum statt neu geparst');
      Assert.IsTrue(mFiles.InProject(cFile));
      Assert.IsFalse(mFiles.InProject(cTestFile), 'Lesbar, aber nicht im Projekt');
      Assert.AreEqual('X := A;', mFiles.LineText(cFile, 7));
      Assert.AreEqual('X := A;', mFiles.Place(cFile, TTextPosition.Create(7, 4)).LineText);
      Assert.IsTrue(mFiles.IsTestFile(cTestFile));
      Assert.IsFalse(mFiles.IsTestFile(cFile));
      Assert.IsNull(mFiles.TreeOf('C:\P\Fehlt.pas'));
    finally
      mFiles.Free;
    end;
    mFiles := TDataFlowFiles.Create(NewRequest(mTree, nil));
    try
      Assert.IsTrue(mFiles.InProject(cTestFile), 'Ohne Projekt zählt jede lesbare Datei');
      Assert.IsFalse(mFiles.InProject('C:\P\Fehlt.pas'));
    finally
      mFiles.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TDataFlowPartsTests.RunClimbsChainInBothDirections;
var
  mRequest: TDataFlowRequest;
  mRun: TDataFlowRun;
  mResult: TDataFlowResult;
begin
  Assert.IsTrue(TDataFlowRun.InheritsFrom(TDataFlowSources));
  Assert.IsTrue(TDataFlowSources.InheritsFrom(TDataFlowBase));
  mRequest := NewRequest(TSyntaxTreeCache.Parse(cUnit), TArray<string>.Create(cFile));
  try
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Position := PositionOf('Y := X');
    mRun := TDataFlowRun.Create(mRequest);
    try
      mResult := mRun.Run(mRequest);
    finally
      mRun.Free;
    end;
    Assert.IsTrue(mResult.Found);
    Assert.AreEqual(1, Integer(Length(mResult.Nodes)));
    Assert.AreEqual<TDataFlowKind>(TDataFlowKind.Assignment, mResult.Nodes[0].Kind);
    Assert.AreEqual('X', mResult.Nodes[0].Detail);
    Assert.AreEqual('X', mResult.Nodes[0].Sources[0].Name);
    mRequest.Position := PositionOf('X := A');
    mRequest.Direction := TDataFlowDirection.Targets;
    mRun := TDataFlowRun.Create(mRequest);
    try
      mResult := mRun.Run(mRequest);
    finally
      mRun.Free;
    end;
    Assert.AreEqual(1, Integer(Length(mResult.Nodes)));
    Assert.AreEqual<TDataFlowKind>(TDataFlowKind.Assignment, mResult.Nodes[0].Kind);
    Assert.AreEqual('Y := X', mResult.Nodes[0].Detail);
    Assert.AreEqual('Y', mResult.Nodes[0].Sources[0].Name);
  finally
    mRequest.Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDataFlowPartsTests);

end.
