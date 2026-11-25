unit Rules.Providers.DeadCode.Tests;

// Tests des Anbieters der Regeln für ungenutzten Code (#64) für andere Features: wählt die Regeln aus, meldet ihre
// Treffer mit den Einstellungen und gilt ohne Projekte als vollständig, ohne Datei lesen zu können.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleDeadCodeProviderTests = class
  public
    [Test]
    procedure ListsRuleIds;
    [Test]
    procedure FindsUnusedPrivateMember;
    [Test]
    procedure HonoursSettings;
    [Test]
    procedure WithoutRulesNotAvailable;
    [Test]
    procedure WithoutProjectsCompleteButUnreadable;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Findings.Contract,
  Rules.Builtin,
  Rules.Contract.Api,
  Rules.Providers.DeadCode;

const
  cUnit =
    'unit Haupt;'#10'interface'#10'type'#10'  TDienst = class'#10'  private'#10'    procedure Vergessen;'#10 +
    '  public'#10'    procedure Lauf;'#10'  end;'#10'implementation'#10 +
    'procedure TDienst.Vergessen;'#10'begin'#10'end;'#10 +
    'procedure TDienst.Lauf;'#10'begin'#10'end;'#10'end.';

function Provider: IRuleDeadCode;
begin
  Result := TRuleDeadCodeProvider.Create(BuiltinRules, nil, nil, nil);
end;

function RulesOf(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    Result := Result + mFinding.RuleId + ';';
  end;
end;

{ TRuleDeadCodeProviderTests }

procedure TRuleDeadCodeProviderTests.ListsRuleIds;
var
  mIds: TArray<string>;
begin
  mIds := Provider.RuleIds;
  Assert.AreEqual(4, Integer(Length(mIds)));
  Assert.AreEqual('unused-private-member', mIds[0]);
  Assert.AreEqual('unused-unit', mIds[3]);
end;

procedure TRuleDeadCodeProviderTests.FindsUnusedPrivateMember;
begin
  Assert.AreEqual('unused-private-member;', RulesOf(Provider.Check('C:\P\Haupt.pas', 'Haupt.pas', cUnit,
    TServerSettings.Default)));
end;

procedure TRuleDeadCodeProviderTests.HonoursSettings;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse('{"rules": {"unused-private-member": "off"}}', mIssues);
  Assert.AreEqual('', RulesOf(Provider.Check('C:\P\Haupt.pas', 'Haupt.pas', cUnit, mSettings)));
end;

procedure TRuleDeadCodeProviderTests.WithoutRulesNotAvailable;
var
  mDeadCode: IRuleDeadCode;
begin
  mDeadCode := TRuleDeadCodeProvider.Create(nil, nil, nil, nil);
  Assert.IsFalse(mDeadCode.Available);
  Assert.IsTrue(Provider.Available);
end;

procedure TRuleDeadCodeProviderTests.WithoutProjectsCompleteButUnreadable;
var
  mReason, mText: string;
begin
  Assert.IsTrue(Provider.Complete(mReason));
  Assert.AreEqual('', mReason);
  Assert.IsFalse(Provider.ReadText('C:\P\Haupt.pas', mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleDeadCodeProviderTests);

end.
