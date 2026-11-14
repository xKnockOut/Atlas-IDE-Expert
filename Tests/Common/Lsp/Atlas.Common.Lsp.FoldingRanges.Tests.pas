unit Atlas.Common.Lsp.FoldingRanges.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFoldingRangesTests = class
  public
    [Test]
    procedure FoldsClassesRoutinesAndBlocks;
    [Test]
    procedure FoldsUsesClauseAsImports;
    [Test]
    procedure FoldsRegions;
    [Test]
    procedure FoldsCommentBlocks;
    [Test]
    procedure IgnoresSingleLineConstructs;
    [Test]
    procedure KeepsOneRangePerStartLine;
    [Test]
    procedure WritesLspJson;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.FoldingRanges;

function Lines(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

// Bereiche als Text, z. B. "0-3,2-3:imports".
function Describe(const AText: string): string;
var
  mTree: TSyntaxTree;
  mRange: TFoldingRange;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mRange in TLspFoldingRanges.Collect(mTree) do
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + Format('%d-%d', [mRange.StartLine, mRange.EndLine]);
      if mRange.Kind <> '' then
      begin
        Result := Result + ':' + mRange.Kind;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

{ TLspFoldingRangesTests }

procedure TLspFoldingRangesTests.FoldsClassesRoutinesAndBlocks;
begin
  Assert.AreEqual('1-5,2-5,3-5,6-10,7-10,8-10',
    Describe(Lines([
      'unit U;',                     // 0
      'interface',                   // 1
      'type',                        // 2
      '  TFoo = class',              // 3
      '    procedure A;',            // 4
      '  end;',                      // 5
      'implementation',              // 6
      'procedure TFoo.A;',           // 7
      'begin',                       // 8
      '  X;',                        // 9
      'end;',                        // 10
      'end.'])));                    // 11
end;

procedure TLspFoldingRangesTests.FoldsUsesClauseAsImports;
begin
  Assert.AreEqual('1-3:imports',
    Describe(Lines(['program P;', 'uses', '  A,', '  B;', 'begin end.'])));
end;

procedure TLspFoldingRangesTests.FoldsRegions;
begin
  Assert.AreEqual('1-5:region,2-4:region',
    Describe(Lines(['program P;', '{$REGION ''Außen''}', '{$region}', 'const A = 1;', '{$ENDREGION}',
      '{$EndRegion}', 'begin end.'])));
end;

procedure TLspFoldingRangesTests.FoldsCommentBlocks;
begin
  Assert.AreEqual('1-2:comment,4-5:comment',
    Describe(Lines(['program P;', '// eins', '// zwei', 'var X: Integer; // hinten', '{ Block', '  Ende }',
      '// allein', 'begin end.'])));
end;

procedure TLspFoldingRangesTests.IgnoresSingleLineConstructs;
begin
  Assert.AreEqual('', Describe('program P; uses A, B; begin if X then begin Y end; end.'));
end;

procedure TLspFoldingRangesTests.KeepsOneRangePerStartLine;
begin
  // TypeDecl und Klassentyp beginnen in derselben Zeile; der größere Bereich bleibt.
  Assert.AreEqual('1-3', Describe(Lines(['program P;', 'type TFoo = class', '  X: Integer;', 'end;', 'begin end.'])));
end;

procedure TLspFoldingRangesTests.WritesLspJson;
var
  mJson: TJSONArray;
begin
  mJson := TLspFoldingRanges.ToJson([TFoldingRange.Create(1, 3, 'imports'), TFoldingRange.Create(4, 9, '')]);
  try
    Assert.AreEqual('[{"startLine":1,"endLine":3,"kind":"imports"},{"startLine":4,"endLine":9}]', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFoldingRangesTests);

end.
