unit Atlas.Common.Lsp.Hover.Parts.Tests;

// Tests der Teile des Hovers einzeln: Inhalt und Darstellungen (Hover.Info) und das Sammeln an einer Stelle
// (Hover.Lookup). Das Verhalten von textDocument/hover prüft Atlas.Common.Lsp.Hover.Tests.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  THoverPartsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InfoFoundOnlyWithDeclaration;
    [Test]
    procedure InfoRendersDeclarationInEveryForm;
    [Test]
    procedure LookupFindsLocalDeclaration;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Hover.Info,
  Atlas.Common.Lsp.Hover.Lookup;

const
  cFile = 'C:\P\Teile.pas';
  cUnit =
    'unit Teile;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure Probe;'#10 +
    'var'#10 +
    '  Anzahl: Integer;'#10 +
    'begin'#10 +
    '  Anzahl := 1;'#10 +
    'end;'#10 +
    'end.';

function ReadNothing(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

{ THoverPartsTests }

procedure THoverPartsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnit, cFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure THoverPartsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure THoverPartsTests.InfoFoundOnlyWithDeclaration;
var
  mInfo: THoverInfo;
begin
  mInfo := Default(THoverInfo);
  Assert.IsFalse(mInfo.Found);
  mInfo.Declaration := 'Anzahl: Integer;';
  Assert.IsTrue(mInfo.Found);
end;

procedure THoverPartsTests.InfoRendersDeclarationInEveryForm;
var
  mInfo: THoverInfo;
  mJson: TJSONObject;
begin
  mInfo := Default(THoverInfo);
  mInfo.Declaration := 'Anzahl: Integer;';
  Assert.IsTrue(Pos('Anzahl: Integer;', mInfo.ToMarkdown) > 0, mInfo.ToMarkdown);
  Assert.IsTrue(Pos('Anzahl: Integer;', mInfo.ToPlainText) > 0, mInfo.ToPlainText);
  mJson := mInfo.ToAtlasJson;
  try
    Assert.AreEqual('Anzahl: Integer;', mJson.GetValue<string>('declaration'));
  finally
    mJson.Free;
  end;
end;

procedure THoverPartsTests.LookupFindsLocalDeclaration;
var
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
begin
  mTree := TSyntaxTreeCache.Parse(cUnit);
  try
    mInfo := TLspHoverLookup.InfoAt(THoverSource.Create(FResolver, FIndex, ReadNothing), mTree, cUnit, cFile,
      TTextPosition.Create(7, 3), '');
  finally
    mTree.Free;
  end;
  Assert.IsTrue(mInfo.Found);
  Assert.AreEqual('Anzahl: Integer;', mInfo.Declaration);
end;

initialization
  TDUnitX.RegisterTestFixture(THoverPartsTests);

end.
