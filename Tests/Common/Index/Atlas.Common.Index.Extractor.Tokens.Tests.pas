unit Atlas.Common.Index.Extractor.Tokens.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexTokenReaderTests = class
  public
    [Test]
    procedure DirectivesOfReadsDeprecatedReason;
    [Test]
    procedure HintsAfterDeclarationCount;
    [Test]
    procedure UnitHintsSkipDottedName;
    [Test]
    procedure ProcedureKindOfObjectAcrossLines;
    [Test]
    procedure ScopedAtFollowsSwitch;
    [Test]
    procedure SignatureOfStringLength;
    [Test]
    procedure ShortenedAddsEllipsis;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor.TypeText,
  Atlas.Common.Index.Extractor.Tokens;

function Join(const ALines: array of string): string;
begin
  Result := String.Join(#13#10, ALines);
end;

function NodeOf(ARoot: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
begin
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = AKind) and SameText(ANode.Name, AName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

procedure TIndexTokenReaderTests.DirectivesOfReadsDeprecatedReason;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
  mReason: string;
  mDirectives: TArray<string>;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface',
    'procedure Laden; overload; deprecated ''Nimm Speichern'';', 'implementation', 'end.']));
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  try
    mDirectives := mReader.DirectivesOf(NodeOf(mTree.Root, TSyntaxKind.RoutineHeader, 'Laden'),
      TIndexSymbolKind.Routine, mReason);
  finally
    mReader.Free;
    mTree.Free;
  end;
  Assert.AreEqual('overload,deprecated', String.Join(',', mDirectives));
  Assert.AreEqual('Nimm Speichern', mReason);
end;

procedure TIndexTokenReaderTests.HintsAfterDeclarationCount;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
  mReason: string;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'const', '  Alt = 1 platform;', 'var',
    '  platform: Integer;', 'implementation', 'end.']));
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  try
    Assert.AreEqual('platform', String.Join(',', mReader.DirectivesOf(NodeOf(mTree.Root, TSyntaxKind.ConstDecl,
      'Alt'), TIndexSymbolKind.Constant, mReason)));
    // Ein Feld namens platform ist kein Hinweis.
    Assert.AreEqual('', String.Join(',', mReader.DirectivesOf(NodeOf(mTree.Root, TSyntaxKind.VarDecl,
      'platform'), TIndexSymbolKind.Variable, mReason)));
  finally
    mReader.Free;
    mTree.Free;
  end;
end;

procedure TIndexTokenReaderTests.UnitHintsSkipDottedName;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
  mUnit: TUnitIndex;
begin
  mTree := TPascalParser.Parse(Join(['unit Atlas.Experimental { Kommentar } deprecated ''alt'' platform;',
    'interface', 'implementation', 'end.']));
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  try
    mUnit := Default(TUnitIndex);
    mReader.UnitHints(mUnit);
  finally
    mReader.Free;
    mTree.Free;
  end;
  Assert.AreEqual('deprecated,platform', String.Join(',', mUnit.Directives));
  Assert.AreEqual('alt', mUnit.DeprecatedText);
end;

procedure TIndexTokenReaderTests.ProcedureKindOfObjectAcrossLines;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'type', '  TEreignis = procedure(A: Integer;',
    '    B: string) of { Methode } object;', '  TRef = reference to procedure;', 'implementation', 'end.']));
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  try
    Assert.AreEqual('of object', mReader.ProcedureKindOf(TIndexTypeText.ProcedureTypeOf(NodeOf(mTree.Root,
      TSyntaxKind.TypeDecl, 'TEreignis'))));
    Assert.AreEqual('reference to', mReader.ProcedureKindOf(TIndexTypeText.ProcedureTypeOf(NodeOf(mTree.Root,
      TSyntaxKind.TypeDecl, 'TRef'))));
    Assert.AreEqual('', mReader.ProcedureKindOf(nil));
  finally
    mReader.Free;
    mTree.Free;
  end;
end;

procedure TIndexTokenReaderTests.ScopedAtFollowsSwitch;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', '{$SCOPEDENUMS ON}', 'type', '  TA = (a1);',
    '{$SCOPEDENUMS OFF}', 'type', '  TB = (b1);', 'implementation', 'end.']));
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  try
    Assert.IsTrue(mReader.ScopedAt(NodeOf(mTree.Root, TSyntaxKind.TypeDecl, 'TA').StartOffset));
    Assert.IsFalse(mReader.ScopedAt(NodeOf(mTree.Root, TSyntaxKind.TypeDecl, 'TB').StartOffset));
  finally
    mReader.Free;
    mTree.Free;
  end;
end;

procedure TIndexTokenReaderTests.SignatureOfStringLength;
var
  mTree: TSyntaxTree;
  mReader: TIndexTokenReader;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'var', '  Kurz: string[8];',
    'function Summe(A, B: Integer): Integer;', 'implementation', 'end.']));
  mReader := TIndexTokenReader.Create(mTree.Tokens);
  try
    Assert.AreEqual('Kurz: string[8]', mReader.SignatureOf(NodeOf(mTree.Root, TSyntaxKind.VarDecl, 'Kurz'),
      TIndexSymbolKind.Variable, 'Kurz', 'string'));
    Assert.AreEqual('function Summe(A, B: Integer): Integer', mReader.SignatureOf(NodeOf(mTree.Root,
      TSyntaxKind.RoutineHeader, 'Summe'), TIndexSymbolKind.Routine, 'Summe', 'Integer'));
  finally
    mReader.Free;
    mTree.Free;
  end;
end;

procedure TIndexTokenReaderTests.ShortenedAddsEllipsis;
begin
  Assert.AreEqual('abc', TIndexTokenReader.Shortened('abc', 3));
  Assert.AreEqual('ab…', TIndexTokenReader.Shortened('abcd', 3));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexTokenReaderTests);

end.
