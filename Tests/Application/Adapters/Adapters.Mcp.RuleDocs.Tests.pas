unit Adapters.Mcp.RuleDocs.Tests;

// Tests für den Host-Adapter zwischen Mcp und Rules (Regelkatalog zum Nachschlagen): Sprache, Regel und
// Einstellungen gehen unverändert durch, Regeln und Zustand zurück.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpRuleDocsAdapterTests = class
  public
    [Test]
    procedure PassesRules;
    [Test]
    procedure PassesState;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.RuleDocs,
  Atlas.Common.Rules.Contract.Api,
  Adapters.Mcp.RuleDocs;

type
  /// <summary>Merkt die Eingaben und liefert feste Werte.</summary>
  TFakeRuleDocs = class(TInterfacedObject, IRuleDocs)
  public
    Language: string;
    RuleId: string;
    Project: string;
    function Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
    function State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
  end;

function TFakeRuleDocs.Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
begin
  Language := ALanguage;
  SetLength(Result, 1);
  Result[0] := Default(TFindingRuleInfo);
  Result[0].Id := 'fake-rule';
  Result[0].Name := 'Falsche Regel';
end;

function TFakeRuleDocs.State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
begin
  RuleId := ARuleId;
  Project := ASettings.Project;
  Result := Default(TFindingRuleState);
  Result.Severity := TRuleSeverity.Hint;
  Result.Origin := TFindingRuleOrigin.Group;
  Result.Detail := 'group:style';
end;

{ TMcpRuleDocsAdapterTests }

procedure TMcpRuleDocsAdapterTests.PassesRules;
var
  mFake: TFakeRuleDocs;
  mDocs: IRuleDocs;
  mAdapter: IMcpRuleDocs;
  mRules: TArray<TFindingRuleInfo>;
begin
  mFake := TFakeRuleDocs.Create;
  mDocs := mFake;
  mAdapter := TMcpRuleDocsAdapter.Create(mDocs);
  mRules := mAdapter.Rules('de');
  Assert.AreEqual('de', mFake.Language);
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual('fake-rule', mRules[0].Id);
  Assert.AreEqual('Falsche Regel', mRules[0].Name);
end;

procedure TMcpRuleDocsAdapterTests.PassesState;
var
  mFake: TFakeRuleDocs;
  mDocs: IRuleDocs;
  mAdapter: IMcpRuleDocs;
  mSettings: TServerSettings;
  mState: TFindingRuleState;
begin
  mFake := TFakeRuleDocs.Create;
  mDocs := mFake;
  mAdapter := TMcpRuleDocsAdapter.Create(mDocs);
  mSettings := TServerSettings.Default;
  mSettings.Project := 'P.dproj';
  mState := mAdapter.State('fake-rule', mSettings);
  Assert.AreEqual('fake-rule', mFake.RuleId);
  Assert.AreEqual('P.dproj', mFake.Project);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mState.Severity));
  Assert.AreEqual(Ord(TFindingRuleOrigin.Group), Ord(mState.Origin));
  Assert.AreEqual('group:style', mState.Detail);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpRuleDocsAdapterTests);

end.
