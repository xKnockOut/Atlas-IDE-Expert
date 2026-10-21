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
  BasisFile = 'C:\P\Basis.pas';
  HauptFile = 'C:\P\Haupt.pas';
  EnkelFile = 'C:\P\Enkel.pas';

  UnitBasis =
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

  UnitHaupt =
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

  UnitEnkel =
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitEnkel, EnkelFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspOverrideMarksTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspOverrideMarksTests.Describe(const AMarks: TArray<TOverrideMark>): string;
var
  Mark: TOverrideMark;
  Target: TOverrideMarkTarget;
begin
  Result := '';
  for Mark in AMarks do
  begin
    Result := Result + IntToStr(Mark.Line);
    for Target in Mark.Overrides do
      Result := Result + Format(' ↑%s@%s:%d', [Target.Name, ExtractFileName(Target.FileName),
        Target.Range.StartPos.Line]);
    for Target in Mark.Overridden do
      Result := Result + Format(' ↓%s@%s:%d', [Target.Name, ExtractFileName(Target.FileName),
        Target.Range.StartPos.Line]);
    Result := Result + '|';
  end;
end;

procedure TLspOverrideMarksTests.MarksOverridesOnDeclarationAndBody;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // TFoo.Zeichne überschreibt TBasis.Zeichne und wird in TEnkel überschrieben (Ziel: Rumpf in Zeile 12).
    Assert.AreEqual('5 ↑TBasis.Zeichne@Basis.pas:4 ↓TEnkel.Zeichne@Enkel.pas:12|' +
      '9 ↑TBasis.Zeichne@Basis.pas:4 ↓TEnkel.Zeichne@Enkel.pas:12|',
      Describe(TLspOverrideMarks.Marks(FResolver, FIndex, Tree, HauptFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspOverrideMarksTests.MarksOverriddenOverAllLevels;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitBasis);
  try
    // Messe überschreibt erst der Enkel, Zeichne beide Stufen; Lies ist nicht virtuell.
    Assert.AreEqual('4 ↓TFoo.Zeichne@Haupt.pas:9 ↓TEnkel.Zeichne@Enkel.pas:12|' +
      '5 ↓TEnkel.Messe@Enkel.pas:9|' +
      '9 ↓TFoo.Zeichne@Haupt.pas:9 ↓TEnkel.Zeichne@Enkel.pas:12|' +
      '12 ↓TEnkel.Messe@Enkel.pas:9|',
      Describe(TLspOverrideMarks.Marks(FResolver, FIndex, Tree, BasisFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspOverrideMarksTests.IgnoresMethodsWithoutOverride;
var
  Tree: TSyntaxTree;
  Mark: TOverrideMark;
begin
  // TFoo.Lies verdeckt TBasis.Lies ohne override: kein Pfeil, obwohl der Vorfahr den Namen kennt.
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    for Mark in TLspOverrideMarks.Marks(FResolver, FIndex, Tree, HauptFile) do
      Assert.IsTrue((Mark.Line <> 6) and (Mark.Line <> 12), 'Lies ohne Marke: ' + IntToStr(Mark.Line));
  finally
    Tree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TLspOverrideMarks.Marks(FResolver, FIndex, nil, HauptFile))));
end;

procedure TLspOverrideMarksTests.WritesJson;
var
  Tree: TSyntaxTree;
  Json: TJSONObject;
  Line, Target: TJSONObject;
begin
  Tree := TPascalParser.Parse(UnitEnkel);
  try
    Json := TLspOverrideMarks.Json(TLspOverrideMarks.Marks(FResolver, FIndex, Tree, EnkelFile));
    try
      Assert.AreEqual(4, TJSONObject(Json).GetValue<TJSONArray>('lines').Count);
      Line := TJSONObject(TJSONObject(Json).GetValue<TJSONArray>('lines').Items[0]);
      Assert.AreEqual(5, Line.GetValue<Integer>('line'));
      Target := TJSONObject(Line.GetValue<TJSONArray>('overrides').Items[0]);
      Assert.AreEqual('TBasis.Messe', Target.GetValue<string>('name'));
      Assert.AreEqual(5, Target.GetValue<Integer>('line'));
      Assert.IsTrue(Target.GetValue<string>('uri').StartsWith('file:'), 'URI');
      Assert.AreEqual(0, Line.GetValue<TJSONArray>('overridden').Count);
    finally
      Json.Free;
    end;
  finally
    Tree.Free;
  end;
end;

end.
