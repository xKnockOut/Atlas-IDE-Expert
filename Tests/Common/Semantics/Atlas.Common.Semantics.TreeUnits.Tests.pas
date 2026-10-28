unit Atlas.Common.Semantics.TreeUnits.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  /// <summary>#1322: Ein Prüflauf wertet den Baum einmal aus, statt bei jeder Typabfrage.</summary>
  [TestFixture]
  TTreeUnitsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ExtractsOncePerFileName;
    [Test]
    procedure MergesOncePerIndex;
    [Test]
    procedure ClearForgetsTree;
    /// <summary>Zwei Resolver mit vielen NodeType-Abfragen: eine Extraktion, dieselben Typen wie ohne.</summary>
    [Test]
    procedure ResolversShareOneExtraction;
    [Test]
    procedure PinTreeTakesSharedExtraction;
    [Test]
    procedure ForeignTreeIsNotServed;
    /// <summary>Die Engine gibt allen Regeln dieselbe Auswertung des Baums und löst sie nach dem Lauf.</summary>
    [Test]
    procedure EngineSharesTreeUnitsWithRules;
    [Test]
    procedure EngineKeepsTreeUnitsOfCaller;
    /// <summary>Eine erzeugte Unit mit 5.000 Zeilen und einer Typabfrage je Ausdruck bleibt linear.</summary>
    [Test]
    [Category('Benchmark')]
    procedure LargeUnitTypeQueriesStayLinear;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TreeUnits;

const
  cFileName = 'C:\P\Haupt.pas';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    '  TFigur = class'#10 +
    '  public'#10 +
    '    FPos: TPunkt;'#10 +
    '    function Mitte: TPunkt;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TFigur.Mitte: TPunkt;'#10 +
    'begin'#10 +
    '  Result := FPos;'#10 +
    'end;'#10 +
    'procedure Verschiebe(AFigur: TFigur);'#10 +
    'var'#10 +
    '  mWert: Integer;'#10 +
    'begin'#10 +
    '  mWert := AFigur.FPos.X + AFigur.Mitte.Y;'#10 +
    '  AFigur.FPos.Y := mWert;'#10 +
    'end;'#10 +
    'end.';

type
  /// <summary>Regel, die für jeden Ausdruck den Typ erfragt, wie Ownership, Casts und TypedExpressions.</summary>
  TTypeQueryRule = class(TInterfacedObject, IRule)
  private
    FId: string;
    FUnits: ITreeUnits;
    FHeld: Boolean;
    FTypes: string;
  public
    constructor Create(const AId: string);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    property Units: ITreeUnits read FUnits;
    property Held: Boolean read FHeld;
    property Types: string read FTypes;
  end;

/// <summary>Typnamen aller Bezeichner und Mitgliedszugriffe in Baumreihenfolge, durch Komma getrennt.</summary>
function QueryAll(AResolver: TNameResolver; ATree: TSyntaxTree): string;
var
  mTypes: string;
begin
  mTypes := '';
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mSymbol, mType: TResolvedSymbol;
      mFound: Boolean;
    begin
      if (ANode.Kind = TSyntaxKind.Identifier) or (ANode.Kind = TSyntaxKind.MemberAccess) then
        if AResolver.NodeType(ATree, cFileName, ANode, mSymbol, mType, mFound) and mFound then
          mTypes := mTypes + mType.Name + ','
        else
          mTypes := mTypes + '?,';
      Result := True;
    end);
  Result := mTypes;
end;

constructor TTypeQueryRule.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
end;

function TTypeQueryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, TRuleSeverity.Warning, 'Testregel');
end;

procedure TTypeQueryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
begin
  FUnits := AContext.TreeUnits;
  FHeld := (FUnits <> nil) and FUnits.Holds(AContext.Tree);
  mResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    FTypes := QueryAll(mResolver, AContext.Tree);
  finally
    mResolver.Free;
  end;
end;

/// <summary>Unit mit ARoutines Routinen zu je sechs Zeilen, jede mit mehreren Mitgliedszugriffen.</summary>
function LargeSource(ARoutines: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('unit Gross;'#10'interface'#10'type'#10'  TPunkt = record'#10'    X, Y: Integer;'#10'  end;'#10);
    mBuilder.Append('  TFigur = class'#10'  public'#10'    FPos: TPunkt;'#10'  end;'#10'implementation'#10);
    for mIndex := 1 to ARoutines do
    begin
      mBuilder.Append('procedure P').Append(mIndex).Append('(AFigur: TFigur);'#10);
      mBuilder.Append('var'#10'  mWert: Integer;'#10'begin'#10);
      mBuilder.Append('  mWert := AFigur.FPos.X + AFigur.FPos.Y;'#10);
      mBuilder.Append('end;'#10);
    end;
    mBuilder.Append('end.');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TTreeUnitsTests }

procedure TTreeUnitsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TTreeUnitsTests.TearDown;
begin
  FIndex := nil;
end;

procedure TTreeUnitsTests.ExtractsOncePerFileName;
var
  mTree: TSyntaxTree;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mFirst, mSecond: TUnitIndex;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mFirst := mUnits.Extracted(cFileName);
    mSecond := mUnits.Extracted('c:\p\HAUPT.pas');
    Assert.AreEqual(1, mObject.Extractions, 'derselbe Name ohne Groß-/Kleinschreibung');
    Assert.AreEqual(Integer(Length(TIndexExtractor.Extract(mTree, cFileName).Symbols)),
      Integer(Length(mFirst.Symbols)));
    Assert.AreEqual(Integer(Length(mFirst.Symbols)), Integer(Length(mSecond.Symbols)));
    mUnits.Extracted('Haupt.pas');
    Assert.AreEqual(2, mObject.Extractions, 'anderer Name: Symbole tragen den Dateinamen');
    Assert.AreEqual('Haupt.pas', mUnits.Extracted('Haupt.pas').FileName);
    mUnits.Clear;
  finally
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.MergesOncePerIndex;
var
  mTree: TSyntaxTree;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mOther: ISymbolIndex;
  mMerged: TUnitIndex;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mMerged := mUnits.Merged(FIndex, cFileName);
    mUnits.Merged(FIndex, cFileName);
    Assert.AreEqual(1, mObject.Merges);
    Assert.AreEqual(1, mObject.Extractions);
    Assert.IsTrue(mMerged.NameTable <> nil, 'Namenstabelle wie bei TNameResolver.TreeUnit');
    mOther := TSymbolIndex.Create;
    mUnits.Merged(mOther, cFileName);
    Assert.AreEqual(2, mObject.Merges, 'anderer Index: neu zusammenführen');
    Assert.AreEqual(1, mObject.Extractions);
    mUnits.Clear;
  finally
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.ClearForgetsTree;
var
  mTree: TSyntaxTree;
  mUnits: ITreeUnits;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mUnits := TTreeUnits.Create(mTree);
    Assert.IsTrue(mUnits.Holds(mTree));
    Assert.IsFalse(mUnits.Holds(nil));
    mUnits.Extracted(cFileName);
    mUnits.Clear;
    Assert.IsFalse(mUnits.Holds(mTree));
    Assert.WillRaise(
      procedure
      begin
        mUnits.Extracted(cFileName);
      end, EInvalidOpException);
  finally
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.ResolversShareOneExtraction;
var
  mTree: TSyntaxTree;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mPlain, mFirst, mSecond: TNameResolver;
  mExpected: string;
begin
  mTree := TPascalParser.Parse(cSource);
  mPlain := nil;
  mFirst := nil;
  mSecond := nil;
  try
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mPlain := TNameResolver.Create(FIndex);
    mFirst := TNameResolver.Create(FIndex, nil, mUnits);
    mSecond := TNameResolver.Create(FIndex, nil, mUnits);
    mExpected := QueryAll(mPlain, mTree);
    Assert.Contains(mExpected, 'TPunkt,');
    Assert.Contains(mExpected, 'Integer,');
    Assert.AreEqual(mExpected, QueryAll(mFirst, mTree));
    Assert.AreEqual(mExpected, QueryAll(mSecond, mTree));
    Assert.AreEqual(1, mObject.Extractions);
    Assert.AreEqual(1, mObject.Merges);
    mUnits.Clear;
  finally
    mSecond.Free;
    mFirst.Free;
    mPlain.Free;
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.PinTreeTakesSharedExtraction;
var
  mTree: TSyntaxTree;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(cSource);
  mResolver := nil;
  try
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mUnits.Merged(FIndex, cFileName);
    mResolver := TNameResolver.Create(FIndex, nil, mUnits);
    mResolver.PinTree(mTree, cFileName);
    try
      Assert.AreEqual(Integer(Length(mUnits.Extracted(cFileName).Symbols)),
        Integer(Length(mResolver.ExtractedUnit(mTree, cFileName).Symbols)));
      QueryAll(mResolver, mTree);
    finally
      mResolver.UnpinTree;
    end;
    Assert.AreEqual(1, mObject.Extractions);
    Assert.AreEqual(1, mObject.Merges);
    mUnits.Clear;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.ForeignTreeIsNotServed;
var
  mTree, mForeign: TSyntaxTree;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mResolver: TNameResolver;
  mPlain: TNameResolver;
begin
  mTree := TPascalParser.Parse(cSource);
  mForeign := TPascalParser.Parse(cSource);
  mResolver := nil;
  mPlain := nil;
  try
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mResolver := TNameResolver.Create(FIndex, nil, mUnits);
    mPlain := TNameResolver.Create(FIndex);
    Assert.AreEqual(QueryAll(mPlain, mForeign), QueryAll(mResolver, mForeign));
    Assert.AreEqual(0, mObject.Extractions, 'ein fremder Baum wird selbst ausgewertet');
    mUnits.Clear;
  finally
    mPlain.Free;
    mResolver.Free;
    mForeign.Free;
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.EngineSharesTreeUnitsWithRules;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mFirst, mSecond: TTypeQueryRule;
  mFirstRule, mSecondRule: IRule;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mFirst := TTypeQueryRule.Create('test-typen-a');
    mFirstRule := mFirst;
    mSecond := TTypeQueryRule.Create('test-typen-b');
    mSecondRule := mSecond;
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Index := FIndex;
    mContext.FileName := cFileName;
    TRuleEngine.Run([mFirstRule, mSecondRule], TServerSettings.Default, mContext);
    Assert.IsTrue(mFirst.Held, 'erste Regel sieht die Auswertung des Baums');
    Assert.IsTrue(mSecond.Held);
    Assert.IsTrue(mFirst.Units = mSecond.Units, 'beide Regeln teilen eine Auswertung');
    Assert.AreEqual(mFirst.Types, mSecond.Types);
    Assert.IsFalse(mFirst.Units.Holds(mTree), 'nach dem Lauf gehört sie zu keinem Baum mehr');
    Assert.IsTrue(mContext.TreeUnits = nil, 'der Kontext des Aufrufers bleibt unverändert');
  finally
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.EngineKeepsTreeUnitsOfCaller;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mRule: TTypeQueryRule;
  mRuleRef: IRule;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mRule := TTypeQueryRule.Create('test-typen');
    mRuleRef := mRule;
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Index := FIndex;
    mContext.TreeUnits := mUnits;
    TRuleEngine.Run([mRuleRef], TServerSettings.Default, mContext);
    TRuleEngine.Run([mRuleRef], TServerSettings.Default, mContext);
    Assert.IsTrue(mRule.Units = mUnits);
    Assert.IsTrue(mUnits.Holds(mTree), 'die Auswertung des Aufrufers löst nur er selbst');
    Assert.AreEqual(1, mObject.Extractions, 'zwei Läufe mit derselben Auswertung');
    mUnits.Clear;
  finally
    mTree.Free;
  end;
end;

procedure TTreeUnitsTests.LargeUnitTypeQueriesStayLinear;
const
  cRoutines = 830;
  cLimitMs = 20000;
var
  mSource: string;
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mObject: TTreeUnits;
  mUnits: ITreeUnits;
  mRule: TTypeQueryRule;
  mRuleRef: IRule;
  mWatch: TStopwatch;
begin
  mSource := LargeSource(cRoutines);
  mTree := TPascalParser.Parse(mSource);
  try
    Assert.IsTrue(mTree.Root.ChildCount > 0);
    mObject := TTreeUnits.Create(mTree);
    mUnits := mObject;
    mRule := TTypeQueryRule.Create('test-typen');
    mRuleRef := mRule;
    mContext := Default(TRuleContext);
    mContext.Text := mSource;
    mContext.Tree := mTree;
    mContext.Index := FIndex;
    mContext.TreeUnits := mUnits;
    mWatch := TStopwatch.StartNew;
    TRuleEngine.Run([mRuleRef], TServerSettings.Default, mContext);
    mWatch.Stop;
    System.Writeln(Format('TreeUnits: %d Routinen, %d ms', [cRoutines, mWatch.ElapsedMilliseconds]));
    Assert.AreEqual(1, mObject.Extractions);
    Assert.Contains(mRule.Types, 'TPunkt,');
    Assert.IsTrue(mWatch.ElapsedMilliseconds < cLimitMs,
      Format('%d ms für %d Typabfragen-Routinen', [mWatch.ElapsedMilliseconds, cRoutines]));
    mUnits.Clear;
  finally
    mTree.Free;
  end;
  mSource := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TTreeUnitsTests);

end.
