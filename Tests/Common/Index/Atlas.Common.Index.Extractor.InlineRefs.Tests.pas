unit Atlas.Common.Index.Extractor.InlineRefs.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexInlineRefsTests = class
  public
    [Test]
    procedure RefsOfSkipsLocalsAndParameters;
    [Test]
    procedure RefsOfBlockedByWith;
    [Test]
    procedure AddWritesDeclarationAndImplementation;
    [Test]
    procedure AddSkipsVirtualMethods;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Extractor.Tokens,
  Atlas.Common.Index.Extractor.InlineRefs;

function Join(const ALines: array of string): string;
begin
  Result := String.Join(#13#10, ALines);
end;

function UnitText(const ABody: array of string): string;
begin
  Result := Join(['unit U;', 'interface', 'function Doppelt(A: Integer): Integer; inline;', 'implementation',
    'uses Werkzeug;']) + #13#10 + Join(ABody) + #13#10 + 'end.';
end;

/// <summary>Symbole von AText ohne InlineRefs, damit Add sie selbst einträgt.</summary>
procedure FillSymbols(ASymbols: TList<TIndexSymbol>; const AText: string);
var
  mSymbol, mCopy: TIndexSymbol;
begin
  for mSymbol in TIndexExtractor.ExtractText(AText, 'U.pas', nil).Symbols do
  begin
    mCopy := mSymbol;
    mCopy.InlineRefs := nil;
    ASymbols.Add(mCopy);
  end;
end;

/// <summary>Verweise des ersten Routinenrumpfs im implementation-Teil von AText.</summary>
function RefsOfFirst(const AText: string): TArray<string>;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
  mSymbols: TList<TIndexSymbol>;
  mRefs: TIndexInlineRefs;
begin
  mTree := TPascalParser.Parse(AText);
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  mSymbols := TList<TIndexSymbol>.Create;
  mRefs := TIndexInlineRefs.Create(mSymbols, mReader);
  try
    FillSymbols(mSymbols, AText);
    Result := mRefs.RefsOf(mTree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(
      TSyntaxKind.RoutineDecl), '', '');
  finally
    mRefs.Free;
    mSymbols.Free;
    mReader.Free;
    mTree.Free;
  end;
end;

function InlineRefsAfterAdd(const AText: string): TArray<TIndexSymbol>;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
  mSymbols: TList<TIndexSymbol>;
  mRefs: TIndexInlineRefs;
begin
  mTree := TPascalParser.Parse(AText);
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  mSymbols := TList<TIndexSymbol>.Create;
  mRefs := TIndexInlineRefs.Create(mSymbols, mReader);
  try
    FillSymbols(mSymbols, AText);
    mRefs.Add(mTree.Root.FindChild(TSyntaxKind.ImplementationSection));
    Result := mSymbols.ToArray;
  finally
    mRefs.Free;
    mSymbols.Free;
    mReader.Free;
    mTree.Free;
  end;
end;

procedure TIndexInlineRefsTests.RefsOfSkipsLocalsAndParameters;
begin
  Assert.AreEqual('Rechne', String.Join(',', RefsOfFirst(UnitText(['function Doppelt(A: Integer): Integer;',
    'begin', '  Result := Rechne(A) * 2;', 'end;']))));
end;

procedure TIndexInlineRefsTests.RefsOfBlockedByWith;
begin
  Assert.AreEqual(0, Integer(Length(RefsOfFirst(UnitText(['function Doppelt(A: Integer): Integer;', 'begin',
    '  with Werte do', '    Result := A;', 'end;'])))));
end;

procedure TIndexInlineRefsTests.AddWritesDeclarationAndImplementation;
var
  mSymbol: TIndexSymbol;
  mCount: Integer;
begin
  mCount := 0;
  for mSymbol in InlineRefsAfterAdd(UnitText(['function Doppelt(A: Integer): Integer;', 'begin',
    '  Result := Rechne(A);', 'end;'])) do
  begin
    if SameText(mSymbol.Name, 'Doppelt') then
    begin
      Assert.AreEqual('Rechne', String.Join(',', mSymbol.InlineRefs));
      Inc(mCount);
    end;
  end;
  Assert.AreEqual(2, mCount);
end;

procedure TIndexInlineRefsTests.AddSkipsVirtualMethods;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in InlineRefsAfterAdd(Join(['unit U;', 'interface', 'type', '  TBasis = class',
    '    function Wert: Integer; virtual; inline;', '  end;', 'implementation', 'function TBasis.Wert: Integer;',
    'begin', '  Result := Rechne;', 'end;', 'end.'])) do
  begin
    Assert.AreEqual(0, Integer(Length(mSymbol.InlineRefs)), mSymbol.Name);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexInlineRefsTests);

end.
