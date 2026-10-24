unit Atlas.Common.Rules.TypedScope.Tests;

// Tests des gemeinsamen Rahmens der Regeln mit Ausdruckstypen (#1129): Text
// ohne Zeilenumbrüche, sicherer Typ einer Variablen, unsichere Deklaration im
// bedingten Zweig, Ausdruck ohne Klammern.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypedScopeTests = class
  public
    [Test]
    procedure TextCollapsesWhitespace;
    [Test]
    procedure SureTypeOfVariable;
    [Test]
    procedure ConditionalDeclarationIsNotSure;
    [Test]
    procedure UnwrappedDropsParens;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.TypedScope;

const
  cSource = 'unit Werte;'#10'interface'#10'implementation'#10'procedure Pruefen;'#10'var'#10 +
    '  mZahl: Integer;'#10'{$IFDEF TEXT}'#10'  mWert: string;'#10'{$ELSE}'#10'  mWert: Integer;'#10'{$ENDIF}'#10 +
    'begin'#10'  mZahl := (mZahl'#10'    + 1);'#10'  mZahl := ((mWert));'#10'end;'#10'end.';

/// <summary>Der (ASkip+1)-te Knoten der Art AKind ab ANode in Vorordnung, dessen Name ANamed ist ('' = jeder);
/// nil ohne.</summary>
function Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const ANamed: string; ASkip: Integer): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mSkip, mIndex: Integer;
begin
  Result := nil;
  mSkip := ASkip;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = AKind) and ((ANamed = '') or SameText(mNode.Name, ANamed)) then
      begin
        if mSkip = 0 then
          Exit(mNode);
        Dec(mSkip);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

function Context(ATree: TSyntaxTree): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.Text := cSource;
  Result.Tree := ATree;
  Result.UnitName := 'Werte';
  Result.FileName := 'C:\Projekt\Werte.pas';
end;

{ TTypedScopeTests }

procedure TTypedScopeTests.TextCollapsesWhitespace;
var
  mTree: TSyntaxTree;
  mScope: TTypedScope;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mScope := TTypedScope.Create(Context(mTree));
    try
      Assert.AreEqual('mZahl + 1', mScope.Text(Unwrapped(Find(mTree.Root, TSyntaxKind.ParenExpr, '', 0))));
    finally
      mScope.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TTypedScopeTests.SureTypeOfVariable;
var
  mTree: TSyntaxTree;
  mScope: TTypedScope;
  mSymbol, mType: TResolvedSymbol;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mScope := TTypedScope.Create(Context(mTree));
    try
      Assert.IsTrue(mScope.SureType(Find(mTree.Root, TSyntaxKind.Identifier, 'mZahl', 0), mSymbol, mType));
      Assert.AreEqual('mZahl', mSymbol.Name);
      Assert.AreEqual('Integer', mType.Name);
    finally
      mScope.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TTypedScopeTests.ConditionalDeclarationIsNotSure;
var
  mTree: TSyntaxTree;
  mScope: TTypedScope;
  mSymbol, mType: TResolvedSymbol;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mScope := TTypedScope.Create(Context(mTree));
    try
      // mWert ist je nach TEXT string oder Integer.
      Assert.IsFalse(mScope.SureType(Find(mTree.Root, TSyntaxKind.Identifier, 'mWert', 0), mSymbol, mType));
    finally
      mScope.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TTypedScopeTests.UnwrappedDropsParens;
var
  mTree: TSyntaxTree;
  mParen: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    // ((mWert)): die äußere Klammer ist der zweite ParenExpr.
    mParen := Find(mTree.Root, TSyntaxKind.ParenExpr, '', 1);
    Assert.IsNotNull(mParen);
    Assert.AreEqual(Ord(TSyntaxKind.Identifier), Ord(Unwrapped(mParen).Kind));
    Assert.AreEqual('mWert', Unwrapped(mParen).Name);
    Assert.IsNull(Unwrapped(nil));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypedScopeTests);

end.
