unit Argus.Common.Semantics.UnresolvedNames.Tests;

// Tests für nicht auflösbare Bezeichner (#178, MCP check_code).

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

type
  [TestFixture]
  TUnresolvedNamesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Names(const AText: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReportsUnknownName;
    [Test]
    procedure KnowsLocalsUsesAndIntrinsics;
    [Test]
    procedure SkipsWithAndExceptionVariables;
    [Test]
    procedure NeedsSystemUnit;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Semantics.UnresolvedNames;

const
  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  Integer = -2147483648..2147483647;'#10 +
    '  TObject = class'#10 +
    '  end;'#10 +
    '  Exception = class(TObject)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'procedure Melde(A: Integer);'#10 +
    'implementation'#10 +
    'procedure Melde(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

procedure TUnresolvedNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSystem, 'C:\Lib\System.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TUnresolvedNamesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TUnresolvedNamesTests.Names(const AText: string): string;
var
  Tree: TSyntaxTree;
  Name: TUnresolvedName;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Name in TUnresolvedNames.Find(FResolver, Tree, 'C:\P\Haupt.pas') do
      Result := Result + Name.Name + Format('@%d:%d;', [Name.Range.StartPos.Line, Name.Range.StartPos.Character]);
  finally
    Tree.Free;
  end;
end;

procedure TUnresolvedNamesTests.ReportsUnknownName;
begin
  Assert.AreEqual('Unbekannt@5:2;', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Unbekannt(1);'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsLocalsUsesAndIntrinsics;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Basis;'#10 +
    'function P(A: Integer): Integer;'#10 +
    'var'#10 +
    '  B: Integer;'#10 +
    'begin'#10 +
    '  B := A;'#10 +
    '  Inc(B);'#10 +
    '  Melde(Length(''x'') + B);'#10 +
    '  Result := B;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.SkipsWithAndExceptionVariables;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(O: TObject);'#10 +
    'begin'#10 +
    '  with O do'#10 +
    '    Feld := 1;'#10 +
    '  try'#10 +
    '  except'#10 +
    '    on E: Exception do'#10 +
    '      raise E;'#10 +
    '  end;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.NeedsSystemUnit;
var
  Empty: ISymbolIndex;
begin
  Assert.IsTrue(TUnresolvedNames.Available(FIndex));
  Empty := TSymbolIndex.Create;
  Assert.IsFalse(TUnresolvedNames.Available(Empty));
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('writeln'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnresolvedNamesTests);

end.
