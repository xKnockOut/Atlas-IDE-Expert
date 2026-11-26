unit Atlas.Common.Semantics.TypeImports.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeImportsTests = class
  public
    /// <summary>Ein Typ einer anderen Unit, die der Baum nicht einbindet, bringt den uses-Eintrag.</summary>
    [Test]
    procedure ForeignTypeAddsUnit;
    /// <summary>Ist die Unit schon eingebunden, bleibt es ohne Eintrag.</summary>
    [Test]
    procedure UsedUnitAddsNothing;
    /// <summary>Generische, qualifizierte und eingebaute Namen bringen keinen Eintrag.</summary>
    [Test]
    procedure PlainNamesOnly;
    /// <summary>Ohne Index kein Eintrag.</summary>
    [Test]
    procedure NoIndexAddsNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeImports;

const
  cTypen = 'unit Typen;'#10'interface'#10'type'#10'  TKunde = class'#10'  end;'#10'implementation'#10'end.';
  cOhne = 'unit Haupt;'#10'interface'#10'implementation'#10'procedure Laden;'#10'begin'#10'end;'#10'end.';
  cMit = 'unit Haupt;'#10'interface'#10'uses'#10'  Typen;'#10'implementation'#10'procedure Laden;'#10'begin'#10 +
    'end;'#10'end.';

/// <summary>uses-Einträge für ATypeName in ASource mit der Unit Typen im Index (AWithIndex).</summary>
function EditsFor(const ASource, ATypeName: string; AWithIndex: Boolean): TArray<TTextEdit>;
var
  mIndex: ISymbolIndex;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mIndex := nil;
  if AWithIndex then
  begin
    mIndex := TSymbolIndex.Create;
    mIndex.AddUnit(TIndexExtractor.ExtractText(cTypen, 'C:\P\Typen.pas', nil));
  end;
  mTree := TSyntaxTreeCache.Parse(ASource);
  try
    mResolver := TNameResolver.Create(mIndex);
    try
      Result := TTypeImports.Edits(mResolver, mIndex, mTree, 'C:\P\Haupt.pas', ATypeName, #10,
        Pos('begin', ASource) + 5);
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

{ TTypeImportsTests }

procedure TTypeImportsTests.ForeignTypeAddsUnit;
var
  mEdits: TArray<TTextEdit>;
begin
  mEdits := EditsFor(cOhne, 'TKunde', True);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.IsTrue(Pos('Typen', mEdits[0].NewText) > 0, mEdits[0].NewText);
end;

procedure TTypeImportsTests.UsedUnitAddsNothing;
begin
  Assert.AreEqual(0, Integer(Length(EditsFor(cMit, 'TKunde', True))));
end;

procedure TTypeImportsTests.PlainNamesOnly;
begin
  Assert.AreEqual(0, Integer(Length(EditsFor(cOhne, 'TList<TKunde>', True))), 'generisch');
  Assert.AreEqual(0, Integer(Length(EditsFor(cOhne, 'Typen.TKunde', True))), 'qualifiziert');
  Assert.AreEqual(0, Integer(Length(EditsFor(cOhne, 'Integer', True))), 'eingebaut');
end;

procedure TTypeImportsTests.NoIndexAddsNothing;
begin
  Assert.AreEqual(0, Integer(Length(EditsFor(cOhne, 'TKunde', False))));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeImportsTests);

end.
