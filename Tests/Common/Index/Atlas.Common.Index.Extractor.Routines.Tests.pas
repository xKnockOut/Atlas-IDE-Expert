unit Atlas.Common.Index.Extractor.Routines.Tests;

// Tests der Zuordnung einer Implementierung zu ihren Symbolen im Index (Atlas.Common.Index.Extractor.Routines):
// Deklaration über Name, Typ und Parametertypen, mehrdeutige Überladungen, Ändern beider Symbole.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexRoutineSymbolsTests = class
  public
    [Test]
    procedure FindsDeclarationOfOverload;
    [Test]
    procedure OverloadWithoutParameterListIsAmbiguous;
    [Test]
    procedure ChangeReachesDeclarationAndImplementation;
    [Test]
    procedure SplitNameSeparatesType;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Extractor.Routines;

const
  cText = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure Bar(A: Integer); overload;'#10 +
    '    procedure Bar(const S: string); overload;'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.Bar(A: Integer);'#10'begin'#10'end;'#10'procedure TFoo.Bar(const S: string);'#10'begin'#10 +
    'end;'#10'end.';
  cShortText = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure Bar(A: Integer); overload;'#10 +
    '    procedure Bar(const S: string); overload;'#10'  end;'#10'implementation'#10'procedure TFoo.Bar;'#10 +
    'begin'#10'end;'#10'end.';

/// <summary>Führt AAction mit den Symbolen von AText und der Implementierung Nummer AImplementation (ab 0) aus.
/// </summary>
procedure WithRoutines(const AText: string; AImplementation: Integer;
  const AAction: TProc<TIndexRoutineSymbols, TSyntaxNode>);
var
  mTree: TSyntaxTree;
  mSymbols: TList<TIndexSymbol>;
  mRoutines: TIndexRoutineSymbols;
  mSection: TSyntaxNode;
  mIndex, mFound: Integer;
begin
  mSymbols := nil;
  mRoutines := nil;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mSymbols := TList<TIndexSymbol>.Create;
    mRoutines := TIndexRoutineSymbols.Create(mSymbols);
    mSymbols.AddRange(TIndexExtractor.ExtractText(AText, 'U.pas', nil).Symbols);
    mSection := mTree.Root.FindChild(TSyntaxKind.ImplementationSection);
    mFound := -1;
    for mIndex := 0 to mSection.ChildCount - 1 do
    begin
      if mSection[mIndex].Kind = TSyntaxKind.RoutineDecl then
      begin
        Inc(mFound);
        if mFound = AImplementation then
        begin
          AAction(mRoutines, mSection[mIndex]);
        end;
      end;
    end;
  finally
    mRoutines.Free;
    mSymbols.Free;
    mTree.Free;
  end;
end;

procedure TIndexRoutineSymbolsTests.FindsDeclarationOfOverload;
var
  mSignature: string;
begin
  mSignature := '';
  WithRoutines(cText, 1,
    procedure(ARoutines: TIndexRoutineSymbols; ANode: TSyntaxNode)
    var
      mFound: Integer;
    begin
      mFound := ARoutines.FindDeclaration(ANode, 'Bar', 'TFoo');
      Assert.IsTrue(mFound >= 0);
      mSignature := ARoutines.Symbols[mFound].Signature;
    end);
  Assert.Contains(mSignature, 'const S: string');
end;

procedure TIndexRoutineSymbolsTests.OverloadWithoutParameterListIsAmbiguous;
var
  mFound: Integer;
begin
  mFound := 0;
  WithRoutines(cShortText, 0,
    procedure(ARoutines: TIndexRoutineSymbols; ANode: TSyntaxNode)
    begin
      mFound := ARoutines.FindDeclaration(ANode, 'Bar', 'TFoo');
    end);
  Assert.AreEqual(-2, mFound);
end;

procedure TIndexRoutineSymbolsTests.ChangeReachesDeclarationAndImplementation;
var
  mMarked: Integer;
begin
  mMarked := 0;
  WithRoutines(cText, 0,
    procedure(ARoutines: TIndexRoutineSymbols; ANode: TSyntaxNode)
    var
      mSymbol: TIndexSymbol;
    begin
      ARoutines.Change(ANode, 'Bar', 'TFoo', ARoutines.FindDeclaration(ANode, 'Bar', 'TFoo'),
        procedure(var ASymbol: TIndexSymbol)
        begin
          ASymbol.ParamOwnership := 'b';
        end);
      for mSymbol in ARoutines.Symbols do
      begin
        if mSymbol.ParamOwnership = 'b' then
        begin
          Inc(mMarked);
          Assert.Contains(mSymbol.Signature, 'A: Integer');
        end;
      end;
    end);
  Assert.AreEqual(2, mMarked);
end;

procedure TIndexRoutineSymbolsTests.SplitNameSeparatesType;
var
  mContainer, mName: string;
begin
  TIndexRoutineSymbols.SplitName('TFoo.TInnen.Bar', mContainer, mName);
  Assert.AreEqual('TFoo.TInnen', mContainer);
  Assert.AreEqual('Bar', mName);
  TIndexRoutineSymbols.SplitName('Frei', mContainer, mName);
  Assert.AreEqual('', mContainer);
  Assert.AreEqual('Frei', mName);
end;

end.
