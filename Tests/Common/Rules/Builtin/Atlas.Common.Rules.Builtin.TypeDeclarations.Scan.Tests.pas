unit Atlas.Common.Rules.Builtin.TypeDeclarations.Scan.Tests;

// Methodenköpfe und -rümpfe einer Klasse für die Regeln zu Typdeklarationen (Rules.Builtin.TypeDeclarations.Scan):
// einziger Kopf, Überladungen, Rumpf im implementation-Teil.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationScanTests = class
  public
    [Test]
    procedure UniqueHeaderIgnoresOverloads;
    [Test]
    procedure MethodBodyInImplementation;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.TypeDeclarations.Scan;

const
  LB = #13#10;
  cUnit =
    'unit A;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TKunde = class' + LB +
    '    procedure Laden;' + LB +
    '    procedure Zeigen(A: Integer); overload;' + LB +
    '    procedure Zeigen(const S: string); overload;' + LB +
    '  end;' + LB +
    'implementation' + LB +
    'procedure TKunde.Laden;' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure TKunde.Zeigen(A: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure TKunde.Zeigen(const S: string);' + LB +
    'begin' + LB +
    'end;' + LB +
    'end.';

function ClassNode(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  if ANode.Kind = TSyntaxKind.ClassType then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := ClassNode(ANode[mIndex]);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

procedure TDeclarationScanTests.UniqueHeaderIgnoresOverloads;
var
  mTree: TSyntaxTree;
  mClass: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cUnit);
  try
    mClass := ClassNode(mTree.Root);
    Assert.IsNotNull(mClass);
    Assert.IsNotNull(UniqueMethodHeader(mClass, 'laden'));
    Assert.IsNull(UniqueMethodHeader(mClass, 'Zeigen'));
    Assert.IsNull(UniqueMethodHeader(mClass, 'Fehlt'));
  finally
    mTree.Free;
  end;
end;

procedure TDeclarationScanTests.MethodBodyInImplementation;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnit);
  try
    Assert.IsNotNull(MethodBody(mTree, 'TKunde', 'Laden'));
    Assert.IsNull(MethodBody(mTree, 'TKunde', 'Zeigen'), 'zwei Rümpfe');
    Assert.IsNull(MethodBody(mTree, 'TKunde', 'Fehlt'));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationScanTests);

end.
