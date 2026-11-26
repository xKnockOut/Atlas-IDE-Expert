unit Atlas.Common.Semantics.ExpectedTypes.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TExpectedTypesTests = class
  private
    FIndex: ISymbolIndex;
    /// <summary>Erwarteter Typ an "|" in ALine im Rumpf von Rechne; mit AFull samt Typargumenten.</summary>
    function TypeAt(const ALine: string; AFull: Boolean = False): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Im Aufruf der Typ des aktiven Parameters.</summary>
    [Test]
    procedure ParameterOfOpenCall;
    /// <summary>Rechts einer Zuweisung der Typ der linken Seite, bei Result der Rückgabetyp.</summary>
    [Test]
    procedure AssignmentTargetAndResult;
    /// <summary>Im Vergleich der Typ der Kette links (#448).</summary>
    [Test]
    procedure ComparisonChain;
    /// <summary>FullAt behält die Typargumente der linken Seite (#468).</summary>
    [Test]
    procedure FullKeepsTypeArguments;
    /// <summary>Ohne Aufruf, Zuweisung oder Vergleich leer.</summary>
    [Test]
    procedure NothingElsewhere;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpectedTypes;

const
  cFileName = 'C:\P\Haupt.pas';

/// <summary>Unit mit ALine im Rumpf von Rechne.</summary>
function SourceWith(const ALine: string): string;
begin
  Result := 'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TModus = (mLesen, mSchreiben);'#10 +
    '  TBox<T> = class'#10 +
    '  end;'#10 +
    '  TDatei = class'#10 +
    '  public'#10 +
    '    Modus: TModus;'#10 +
    '  end;'#10 +
    'procedure Setze(A: Integer; B: TModus);'#10 +
    'function Rechne(D: TDatei): Double;'#10 +
    'implementation'#10 +
    'procedure Setze(A: Integer; B: TModus);'#10 +
    'begin'#10 +
    'end;'#10 +
    'function Rechne(D: TDatei): Double;'#10 +
    'var'#10 +
    '  Text: string;'#10 +
    '  Box: TBox<string>;'#10 +
    'begin'#10 +
    '  ' + ALine + #10 +
    'end;'#10 +
    'end.';
end;

{ TExpectedTypesTests }

procedure TExpectedTypesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TExpectedTypesTests.TearDown;
begin
  FIndex := nil;
end;

function TExpectedTypesTests.TypeAt(const ALine: string; AFull: Boolean): string;
const
  cBodyLine = 21;
var
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mPosition: TTextPosition;
begin
  mText := SourceWith(StringReplace(ALine, '|', '', []));
  FIndex.AddUnit(TIndexExtractor.ExtractText(mText, cFileName, nil));
  mPosition := TTextPosition.Create(cBodyLine, 2 + Pos('|', ALine) - 1);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mResolver := TNameResolver.Create(FIndex);
    try
      if AFull then
      begin
        Result := TExpectedTypes.FullAt(mResolver, mTree, cFileName, mPosition);
      end
      else
      begin
        Result := TExpectedTypes.At(mResolver, mTree, cFileName, mPosition);
      end;
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TExpectedTypesTests.ParameterOfOpenCall;
begin
  Assert.AreEqual('Integer', TypeAt('Setze(|'));
  Assert.AreEqual('TModus', TypeAt('Setze(1, |'));
end;

procedure TExpectedTypesTests.AssignmentTargetAndResult;
begin
  Assert.AreEqual('string', TypeAt('Text := |'));
  Assert.AreEqual('TModus', TypeAt('D.Modus := |'));
  Assert.AreEqual('Double', TypeAt('Result := |'));
end;

procedure TExpectedTypesTests.ComparisonChain;
begin
  Assert.AreEqual('TModus', TypeAt('if D.Modus = |'));
end;

procedure TExpectedTypesTests.FullKeepsTypeArguments;
begin
  Assert.AreEqual('TBox', TypeAt('Box := |'));
  Assert.AreEqual('TBox<string>', TypeAt('Box := |', True));
end;

procedure TExpectedTypesTests.NothingElsewhere;
begin
  Assert.AreEqual('', TypeAt('|'));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpectedTypesTests);

end.
