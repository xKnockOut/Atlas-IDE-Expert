unit Atlas.Common.Rules.CallOwnership.Tests;

// Tests der Besitzabfrage für Prüfregeln (Atlas.Common.Rules.CallOwnership): Antwort aus dem Index des
// Regelkontexts, ohne Index unklar, und Freigabe ohne einen einzigen Aufruf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleCallOwnershipTests = class
  public
    [Test]
    procedure AnswersFromTheIndex;
    [Test]
    procedure WithoutIndexUnknown;
    [Test]
    procedure FreeWithoutQuery;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.ParamOwnership,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.CallOwnership,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.CallOwnership,
  Atlas.Tests.SymbolIndex;

const
  cHelfer = 'unit Helfer;'#10'interface'#10'uses System.Classes;'#10 +
    'procedure Fuellen(Teile: TStrings);'#10'procedure Weg(A: TObject);'#10'implementation'#10 +
    'procedure Fuellen(Teile: TStrings);'#10'begin'#10'  Teile.Add(''a'');'#10'end;'#10 +
    'procedure Weg(A: TObject);'#10'begin'#10'  A.Free;'#10'end;'#10'end.';
  cNutzer = 'unit Nutzer;'#10'interface'#10'implementation'#10'uses System.Classes, Helfer;'#10'procedure Lauf;'#10 +
    'var'#10'  X: TStringList;'#10'begin'#10'  Fuellen(X);'#10'  Weg(X);'#10'end;'#10'end.';

function CallNamed(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
begin
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Call) and SameText(ANode.Name, AName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Assert.IsNotNull(Result, AName);
end;

/// <summary>Marken der Aufrufe Fuellen und Weg (Argument 0), durch ";" getrennt.</summary>
function Marks(const AIndex: ISymbolIndex): string;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mCalls: TRuleCallOwnership;
begin
  mTree := TSyntaxTreeCache.Parse(cNutzer);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cNutzer;
    mContext.Tree := mTree;
    mContext.FileName := 'Nutzer.pas';
    mContext.Index := AIndex;
    mCalls := TRuleCallOwnership.Create(mContext);
    try
      Result := TParamOwnership.cEffectMarks[mCalls.EffectOf(CallNamed(mTree, 'Fuellen'), 0).Effect] + ';' +
        TParamOwnership.cEffectMarks[mCalls.EffectOf(CallNamed(mTree, 'Weg'), 0).Effect];
    finally
      mCalls.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TRuleCallOwnershipTests.AnswersFromTheIndex;
begin
  Assert.AreEqual('b;f', Marks(TTestIndex.Build([cHelfer, 'Helfer.pas'])));
end;

procedure TRuleCallOwnershipTests.WithoutIndexUnknown;
begin
  Assert.AreEqual('?;?', Marks(nil));
end;

procedure TRuleCallOwnershipTests.FreeWithoutQuery;
var
  mContext: TRuleContext;
  mCalls: TRuleCallOwnership;
begin
  // Ohne Aufruf von EffectOf wird keine Namensauflösung geholt; Destroy darf trotzdem nichts lösen.
  mContext := Default(TRuleContext);
  mCalls := TRuleCallOwnership.Create(mContext);
  mCalls.Free;
  Assert.AreEqual('', mContext.Text);
end;

end.
