unit Shell.Composition.LinterRules.Tests;

// Prüfregeln des Linter-Modus (TShellLinterRules): Beschreibungen samt syntax und gespeicherten Abfragen, alle
// Regeln, die Auswahl für --fix und die Regeln mit sicherer Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellLinterRulesTests = class
  public
    /// <summary>syntax und Sprachstand vorn, gespeicherte Abfragen mit failIfAny nur mit Index.</summary>
    [Test]
    procedure InfosWithSyntaxAndSavedQueries;
    /// <summary>Alle Regeln finden empty-except, die Prüfung für --fix nur mit ihren Regeln.</summary>
    [Test]
    procedure CheckAllAndFixCheck;
    [Test]
    procedure SafeFixRulesFromCatalog;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Scopes,
  Atlas.Common.Checks.Contract,
  Core.Linter.Host,
  Shell.Composition.LinterRules;

const
  cEmptyExcept = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 +
    '  try'#13#10'    P;'#13#10'  except'#13#10'  end;'#13#10'end;'#13#10'end.'#13#10;

function HasRule(const AFindings: TArray<TRuleFinding>; const ARuleId: string): Boolean;
var
  mFinding: TRuleFinding;
begin
  Result := False;
  for mFinding in AFindings do
  begin
    if SameText(mFinding.RuleId, ARuleId) then
    begin
      Result := True;
    end;
  end;
end;

function FindingsOf(const ACheck: TCoreLinterCheckText; const AText: string): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := ACheck(TServerSettings.Default, 'U.pas', AText, Default(TCheckProject), TPascalSource.Default,
    mScopes);
end;

{ TShellLinterRulesTests }

procedure TShellLinterRulesTests.InfosWithSyntaxAndSavedQueries;
var
  mRules: TCoreLinterRules;
  mSettings: TServerSettings;
  mSaved: TSavedQuery;
  mWithout, mWith: TArray<TFindingRuleInfo>;
begin
  mRules := TShellLinterRules.Create;
  mSaved := Default(TSavedQuery);
  mSaved.Name := 'leer';
  mSaved.Query := 'classes where methods = 0';
  mSaved.FailIfAny := True;
  mSettings := TServerSettings.Default;
  mSettings.Queries := TArray<TSavedQuery>.Create(mSaved);
  mWithout := mRules.Infos(mSettings, False);
  Assert.IsTrue(Length(mWithout) > 2);
  Assert.AreEqual('syntax', mWithout[0].Id);
  mWith := mRules.Infos(mSettings, True);
  Assert.AreEqual(Integer(Length(mWithout)) + 1, Integer(Length(mWith)));
  Assert.AreEqual('query:leer', mWith[High(mWith)].Id);
end;

procedure TShellLinterRulesTests.CheckAllAndFixCheck;
var
  mRules: TCoreLinterRules;
begin
  mRules := TShellLinterRules.Create;
  Assert.IsTrue(HasRule(FindingsOf(mRules.CheckAll, cEmptyExcept), 'empty-except'));
  Assert.IsFalse(HasRule(FindingsOf(mRules.FixCheck(TArray<string>.Create('redundant-cast')), cEmptyExcept),
    'empty-except'));
  Assert.IsTrue(HasRule(FindingsOf(mRules.FixCheck(TArray<string>.Create('all')), cEmptyExcept), 'empty-except'));
end;

procedure TShellLinterRulesTests.SafeFixRulesFromCatalog;
var
  mRules: TCoreLinterRules;
  mSafe: TArray<string>;
begin
  mRules := TShellLinterRules.Create;
  mSafe := mRules.SafeFixRules();
  Assert.IsTrue(IndexText('redundant-cast', mSafe) >= 0);
  Assert.IsFalse(IndexText('empty-except', mSafe) >= 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellLinterRulesTests);

end.
