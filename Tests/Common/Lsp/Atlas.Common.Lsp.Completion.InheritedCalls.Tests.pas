unit Atlas.Common.Lsp.Completion.InheritedCalls.Tests;

// Tests für die vollständigen inherited-Aufrufe (#482) vor den Namen der Vorfahrmethoden.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  [TestFixture]
  TCompletionInheritedCallsTests = class
  private
    FIndex: ISymbolIndex;
    function CallsAt(const AFind, AReplace: string; out ACandidates: TArray<TResolvedSymbol>):
      TArray<TCompletionItem>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Gleiche Überladung zuerst, mit Semikolon; abstrakte fallen weg und stehen in der Fußzeile.</summary>
    [Test]
    procedure ConstructorCallsComeFirst;
    /// <summary>In einer Funktion mit "Result := " davor.</summary>
    [Test]
    procedure FunctionCallAssignsResult;
    /// <summary>Außerhalb einer Methode keine Aufrufe.</summary>
    [Test]
    procedure NothingOutsideMethod;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Completion.InheritedCalls;

const
  cBasisFile = 'C:\P\Basis.pas';
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TComponent = class'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); virtual;'#10 +
    '  end;'#10 +
    '  TBaseView = class(TComponent)'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); virtual;'#10 +
    '    function FormatZeile(const AText: string; ALevel: Integer): string; virtual;'#10 +
    '    procedure Zeichnen; virtual; abstract;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TLogView = class(TBaseView)'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    function FormatZeile(const AText: string; ALevel: Integer): string; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TLogView.Create(AOwner: TComponent);'#10 +
    'begin'#10 +
    '  { Create }'#10 +
    'end;'#10 +
    'function TLogView.FormatZeile(const AText: string; ALevel: Integer): string;'#10 +
    'begin'#10 +
    '  { Format }'#10 +
    'end;'#10 +
    '{ Draussen }'#10 +
    'end.';

/// <summary>Position hinter AMarker in AText.</summary>
function PositionAfter(const AText, AMarker: string): TTextPosition;
var
  mLines: TArray<string>;
  mLine: Integer;
begin
  Result := TTextPosition.Create(0, 0);
  mLines := AText.Split([#10]);
  for mLine := 0 to High(mLines) do
  begin
    if Pos(AMarker, mLines[mLine]) > 0 then
    begin
      Result := TTextPosition.Create(mLine, Pos(AMarker, mLines[mLine]) - 1 + Length(AMarker));
    end;
  end;
end;

function Names(const ACandidates: TArray<TResolvedSymbol>): string;
var
  mCandidate: TResolvedSymbol;
begin
  Result := '';
  for mCandidate in ACandidates do
  begin
    Result := Trim(Result + ' ' + mCandidate.Name);
  end;
end;

procedure TCompletionInheritedCallsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
end;

procedure TCompletionInheritedCallsTests.TearDown;
begin
  FIndex := nil;
end;

function TCompletionInheritedCallsTests.CallsAt(const AFind, AReplace: string;
  out ACandidates: TArray<TResolvedSymbol>): TArray<TCompletionItem>;
var
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mRequest: TCompletionRequest;
  mContext: TCompletionContext;
  mCollector: TCompletionCollector;
  mIncomplete: Boolean;
begin
  mText := StringReplace(cUnitHaupt, AFind, AReplace, []);
  mTree := TPascalParser.Parse(mText);
  mResolver := TNameResolver.Create(FIndex);
  mRequest := TCompletionRequest.Create(mText, cHauptFile, PositionAfter(mText, AReplace));
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := mResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mContext := TCompletionContexts.Analyze(mTree, mRequest.Position);
    ACandidates := mResolver.Candidates.InheritedCandidates(mTree, cHauptFile, mContext.Offset);
    mCollector := TCompletionCollector.Create(mRequest, mContext, '', nil);
    try
      TCompletionInheritedCalls.Add(mRequest, mContext, mCollector, ACandidates);
      Result := mCollector.Finish(mIncomplete);
    finally
      mCollector.Free;
    end;
  finally
    mRequest.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TCompletionInheritedCallsTests.ConstructorCallsComeFirst;
var
  mItems: TArray<TCompletionItem>;
  mCandidates: TArray<TResolvedSymbol>;
begin
  mItems := CallsAt('  { Create }', '  inherited ', mCandidates);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Create(AOwner)', mItems[0].Name);
  Assert.AreEqual('same', mItems[0].InheritedMatch);
  Assert.AreEqual('Create(AOwner);', mItems[0].TextEdit.NewText);
  Assert.AreEqual('CreateNew(AOwner, Dummy)', mItems[1].Name);
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', mItems[0].InheritedAbstract));
  // Create und CreateNew stehen schon oben, Zeichnen ist abstrakt.
  Assert.IsFalse(Pos('Zeichnen', Names(mCandidates)) > 0, Names(mCandidates));
  Assert.IsFalse(Pos('CreateNew', Names(mCandidates)) > 0, Names(mCandidates));
end;

procedure TCompletionInheritedCallsTests.FunctionCallAssignsResult;
var
  mItems: TArray<TCompletionItem>;
  mCandidates: TArray<TResolvedSymbol>;
begin
  mItems := CallsAt('  { Format }', '  inherited Form', mCandidates);
  Assert.IsTrue(Length(mItems) >= 1);
  Assert.AreEqual('FormatZeile(AText, ALevel)', mItems[0].Name);
  Assert.AreEqual('Result := inherited FormatZeile(AText, ALevel);', mItems[0].TextEdit.NewText);
  Assert.AreEqual(2, mItems[0].TextEdit.Range.StartPos.Character);
end;

procedure TCompletionInheritedCallsTests.NothingOutsideMethod;
var
  mItems: TArray<TCompletionItem>;
  mCandidates: TArray<TResolvedSymbol>;
begin
  mItems := CallsAt('{ Draussen }', 'inherited ', mCandidates);
  Assert.AreEqual(0, Integer(Length(mItems)));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionInheritedCallsTests);

end.
