unit Atlas.Common.Lsp.OverrideMarks.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.OverrideMarks;

type
  [TestFixture]
  TLspOverrideMarksTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AMarks: TArray<TOverrideMark>): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MarksOverridesOnDeclarationAndBody;
    [Test]
    procedure MarksOverriddenOverAllLevels;
    [Test]
    procedure IgnoresMethodsWithoutOverride;
    [Test]
    procedure WritesJson;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cBasisFile = 'C:\P\Basis.pas';
  cHauptFile = 'C:\P\Haupt.pas';
  cEnkelFile = 'C:\P\Enkel.pas';

  cUnitBasis =
    'unit Basis;'#10 +                         // 0
    'interface'#10 +                           // 1
    'type'#10 +                                // 2
    '  TBasis = class'#10 +                    // 3
    '    procedure Zeichne; virtual;'#10 +     // 4
    '    procedure Messe; virtual;'#10 +       // 5
    '    procedure Lies;'#10 +                 // 6
    '  end;'#10 +                              // 7
    'implementation'#10 +                      // 8
    'procedure TBasis.Zeichne;'#10 +           // 9
    'begin'#10 +                               // 10
    'end;'#10 +                                // 11
    'procedure TBasis.Messe;'#10 +             // 12
    'begin'#10 +                               // 13
    'end;'#10 +                                // 14
    'procedure TBasis.Lies;'#10 +              // 15
    'begin'#10 +                               // 16
    'end;'#10 +                                // 17
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +                         // 0
    'interface'#10 +                           // 1
    'uses Basis;'#10 +                         // 2
    'type'#10 +                                // 3
    '  TFoo = class(TBasis)'#10 +              // 4
    '    procedure Zeichne; override;'#10 +    // 5
    '    procedure Lies;'#10 +                 // 6
    '  end;'#10 +                              // 7
    'implementation'#10 +                      // 8
    'procedure TFoo.Zeichne;'#10 +             // 9
    'begin'#10 +                               // 10
    'end;'#10 +                                // 11
    'procedure TFoo.Lies;'#10 +                // 12
    'begin'#10 +                               // 13
    'end;'#10 +                                // 14
    'end.';

  cUnitEnkel =
    'unit Enkel;'#10 +                         // 0
    'interface'#10 +                           // 1
    'uses Haupt;'#10 +                         // 2
    'type'#10 +                                // 3
    '  TEnkel = class(TFoo)'#10 +              // 4
    '    procedure Messe; override;'#10 +      // 5
    '    procedure Zeichne; override;'#10 +    // 6
    '  end;'#10 +                              // 7
    'implementation'#10 +                      // 8
    'procedure TEnkel.Messe;'#10 +             // 9
    'begin'#10 +                               // 10
    'end;'#10 +                                // 11
    'procedure TEnkel.Zeichne;'#10 +           // 12
    'begin'#10 +                               // 13
    'end;'#10 +                                // 14
    'end.';

{ TLspOverrideMarksTests }

procedure TLspOverrideMarksTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitEnkel, cEnkelFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspOverrideMarksTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspOverrideMarksTests.Describe(const AMarks: TArray<TOverrideMark>): string;
var
  mMark: TOverrideMark;
  mTarget: TOverrideMarkTarget;
begin
  Result := '';
  for mMark in AMarks do
  begin
    Result := Result + IntToStr(mMark.Line);
    for mTarget in mMark.Overrides do
    begin
      Result := Result + Format(' ↑%s@%s:%d', [mTarget.Name, ExtractFileName(mTarget.FileName),
        mTarget.Range.StartPos.Line]);
    end;
    for mTarget in mMark.Overridden do
    begin
      Result := Result + Format(' ↓%s@%s:%d', [mTarget.Name, ExtractFileName(mTarget.FileName),
        mTarget.Range.StartPos.Line]);
    end;
    Result := Result + '|';
  end;
end;

procedure TLspOverrideMarksTests.MarksOverridesOnDeclarationAndBody;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    // TFoo.Zeichne überschreibt TBasis.Zeichne und wird in TEnkel überschrieben (Ziel: Rumpf in Zeile 12).
    Assert.AreEqual('5 ↑TBasis.Zeichne@Basis.pas:4 ↓TEnkel.Zeichne@Enkel.pas:12|' +
      '9 ↑TBasis.Zeichne@Basis.pas:4 ↓TEnkel.Zeichne@Enkel.pas:12|',
      Describe(TLspOverrideMarks.Marks(FResolver, FIndex, mTree, cHauptFile)));
  finally
    mTree.Free;
  end;
end;

procedure TLspOverrideMarksTests.MarksOverriddenOverAllLevels;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitBasis);
  try
    // Messe überschreibt erst der Enkel, Zeichne beide Stufen; Lies ist nicht virtuell.
    Assert.AreEqual('4 ↓TFoo.Zeichne@Haupt.pas:9 ↓TEnkel.Zeichne@Enkel.pas:12|' +
      '5 ↓TEnkel.Messe@Enkel.pas:9|' +
      '9 ↓TFoo.Zeichne@Haupt.pas:9 ↓TEnkel.Zeichne@Enkel.pas:12|' +
      '12 ↓TEnkel.Messe@Enkel.pas:9|',
      Describe(TLspOverrideMarks.Marks(FResolver, FIndex, mTree, cBasisFile)));
  finally
    mTree.Free;
  end;
end;

procedure TLspOverrideMarksTests.IgnoresMethodsWithoutOverride;
var
  mTree: TSyntaxTree;
  mMark: TOverrideMark;
begin
  // TFoo.Lies verdeckt TBasis.Lies ohne override: kein Pfeil, obwohl der Vorfahr den Namen kennt.
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    for mMark in TLspOverrideMarks.Marks(FResolver, FIndex, mTree, cHauptFile) do
    begin
      Assert.IsTrue((mMark.Line <> 6) and (mMark.Line <> 12), 'Lies ohne Marke: ' + IntToStr(mMark.Line));
    end;
  finally
    mTree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TLspOverrideMarks.Marks(FResolver, FIndex, nil, cHauptFile))));
end;

procedure TLspOverrideMarksTests.WritesJson;
var
  mTree: TSyntaxTree;
  mJson: TJSONObject;
  mLine, mTarget: TJSONObject;
begin
  mTree := TPascalParser.Parse(cUnitEnkel);
  try
    mJson := TLspOverrideMarks.Json(TLspOverrideMarks.Marks(FResolver, FIndex, mTree, cEnkelFile));
    try
      Assert.AreEqual(4, TJSONObject(mJson).GetValue<TJSONArray>('lines').Count);
      mLine := TJSONObject(TJSONObject(mJson).GetValue<TJSONArray>('lines').Items[0]);
      Assert.AreEqual(5, mLine.GetValue<Integer>('line'));
      mTarget := TJSONObject(mLine.GetValue<TJSONArray>('overrides').Items[0]);
      Assert.AreEqual('TBasis.Messe', mTarget.GetValue<string>('name'));
      Assert.AreEqual(5, mTarget.GetValue<Integer>('line'));
      Assert.IsTrue(mTarget.GetValue<string>('uri').StartsWith('file:'), 'URI');
      Assert.AreEqual(0, mLine.GetValue<TJSONArray>('overridden').Count);
    finally
      mJson.Free;
    end;
  finally
    mTree.Free;
  end;
end;

end.
