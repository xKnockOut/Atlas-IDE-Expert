unit Rules.CheckContext.Tests;

// Lauf der Prüfregeln über das Umfeld eines Dokuments (TRuleCheckContext): Felder kommen im Regelumfeld an,
// SharedFindings legt im Memo ab, CachedFindings rechnet nur ohne Memo selbst.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleCheckContextTests = class
  public
    [Test]
    procedure WithoutRulesGivesNothing;
    /// <summary>Unit-Name aus dem relativen Pfad, Dateiname und Live erreichen die Regel.</summary>
    [Test]
    procedure PassesContextToRules;
    [Test]
    procedure SharedFindingsFillMemo;
    [Test]
    procedure SharedFindingsWithoutMemoRuns;
    [Test]
    procedure CachedFindingsWithoutMemoRuns;
    /// <summary>Mit Memo, aber ohne abgelegte Treffer und ohne laufenden Lauf: kein eigener Lauf.</summary>
    [Test]
    procedure CachedFindingsWithEmptyMemoGivesNothing;
    /// <summary>Umfeld vom Anbieter; ohne Anbieter oder bei False die Vorgaben.</summary>
    [Test]
    procedure LookupGivesProviderContext;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Findings.Memo,
  Rules.Contract,
  Rules.CheckContext,
  Atlas.Common.Findings.Contract;

const
  cText = 'unit Haupt;' + #13#10 + 'interface' + #13#10 + 'implementation' + #13#10 + 'end.';

type
  /// <summary>Ein Treffer je Lauf; die Meldung nennt Unit-Name, Dateiname und Live.</summary>
  TEchoRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TEchoRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('echo', TRuleSeverity.Warning, 'Echo');
end;

procedure TEchoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  AReport.Add(TTextRange.Create(0, 0, 0, 4), AContext.UnitName + '|' + AContext.FileName + '|' +
    BoolToStr(AContext.Live, True));
end;

function Context(const AMemo: IRuleFindingsMemo): TRuleCheckContext;
var
  mRule: IRule;
begin
  mRule := TEchoRule.Create;
  Result := Default(TRuleCheckContext);
  Result.Rules := [mRule];
  Result.Settings := TServerSettings.Default;
  Result.RelativePath := 'Quelle/Haupt.pas';
  Result.FileName := 'C:\P\Quelle\Haupt.pas';
  Result.Live := True;
  Result.Memo := AMemo;
end;

{ TRuleCheckContextTests }

procedure TRuleCheckContextTests.WithoutRulesGivesNothing;
var
  mContext: TRuleCheckContext;
  mTree: TSyntaxTree;
begin
  mContext := Context(nil);
  mContext.Rules := nil;
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    Assert.AreEqual(0, Integer(Length(mContext.Findings(cText, mTree))));
  finally
    mTree.Free;
  end;
end;

procedure TRuleCheckContextTests.PassesContextToRules;
var
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mFindings := Context(nil).Findings(cText, mTree);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('echo', mFindings[0].RuleId);
  Assert.AreEqual('Haupt|C:\P\Quelle\Haupt.pas|True', mFindings[0].Message);
end;

procedure TRuleCheckContextTests.SharedFindingsFillMemo;
var
  mMemo: IRuleFindingsMemo;
  mFindings, mStored: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mMemo := TRuleFindingsMemo.Create;
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mFindings := Context(mMemo).SharedFindings(cText, mTree, nil);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mMemo.TryGet('C:\P\Quelle\Haupt.pas', cText, mStored));
  Assert.AreEqual(1, Integer(Length(mStored)));
  Assert.AreEqual('echo', mStored[0].RuleId);
end;

procedure TRuleCheckContextTests.SharedFindingsWithoutMemoRuns;
var
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mFindings := Context(nil).SharedFindings(cText, mTree, nil);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFindings)));
end;

procedure TRuleCheckContextTests.CachedFindingsWithoutMemoRuns;
var
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
  mFound: Boolean;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mFound := Context(nil).CachedFindings(cText, mTree, nil, mFindings);
  finally
    mTree.Free;
  end;
  Assert.IsTrue(mFound);
  Assert.AreEqual(1, Integer(Length(mFindings)));
end;

procedure TRuleCheckContextTests.CachedFindingsWithEmptyMemoGivesNothing;
var
  mMemo: IRuleFindingsMemo;
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
  mFound: Boolean;
begin
  mMemo := TRuleFindingsMemo.Create;
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mFound := Context(mMemo).CachedFindings(cText, mTree, nil, mFindings);
  finally
    mTree.Free;
  end;
  Assert.IsFalse(mFound);
  Assert.AreEqual(0, Integer(Length(mFindings)));
end;

procedure TRuleCheckContextTests.LookupGivesProviderContext;
var
  mContext: TRuleCheckContext;
  mAnswer: Boolean;
  mProvider: TRuleContextProvider;
begin
  mAnswer := True;
  mProvider :=
    function(const AUri: string; out AResult: TRuleCheckContext): Boolean
    begin
      AResult := Default(TRuleCheckContext);
      AResult.RelativePath := AUri;
      Result := mAnswer;
    end;
  Assert.IsTrue(TRuleContexts.Lookup(mProvider, 'A.pas', mContext));
  Assert.AreEqual('A.pas', mContext.RelativePath);
  mAnswer := False;
  Assert.IsFalse(TRuleContexts.Lookup(mProvider, 'A.pas', mContext));
  Assert.AreEqual('', mContext.RelativePath);
  Assert.IsFalse(TRuleContexts.Lookup(nil, 'A.pas', mContext));
  Assert.AreEqual('', mContext.RelativePath);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleCheckContextTests);

end.
