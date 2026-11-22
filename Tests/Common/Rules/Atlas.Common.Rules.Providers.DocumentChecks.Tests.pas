unit Atlas.Common.Rules.Providers.DocumentChecks.Tests;

// Tests für die Prüfregeln der Diagnose je Dokument: ohne Umfeld Vorgaben und keine Regeln, Syntaxfehler nach den
// Einstellungen, Treffer ohne die Baseline, Schalter für auffällige uses nach den Regeln, Abbruch reicht durch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleDocumentChecksTests = class
  public
    [Test]
    procedure WithoutContextUsesDefaults;
    [Test]
    procedure SyntaxFollowsSettings;
    [Test]
    procedure RuleFindingsWithoutBaseline;
    [Test]
    procedure UsesSwitchesFollowRules;
    [Test]
    procedure CancelledReachesRules;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.CheckContext,
  Atlas.Common.Rules.Providers.DocumentChecks;

const
  cBroken = 'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'procedure X;' + #10 + 'begin' + #10 +
    '  if True' + #10 + '  X;' + #10 + 'end;' + #10 + 'end.';
  cValid = 'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'end.';

type
  /// <summary>Ein Treffer je Lauf in Zeile 0.</summary>
  TOneRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TOneRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('eins', TRuleSeverity.Warning, 'Eins');
end;

procedure TOneRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  AReport.Add(TTextRange.Create(0, 0, 0, 4), 'Treffer');
end;

/// <summary>Umfeld für A.pas mit den Einstellungen AConfig ('' = Vorgaben) und der Regel eins.</summary>
function ContextWith(const AConfig: string): TRuleCheckContext;
var
  mRule: IRule;
  mIssues: TArray<TConfigurationIssue>;
begin
  mRule := TOneRule.Create;
  Result := Default(TRuleCheckContext);
  Result.Rules := [mRule];
  if AConfig = '' then
  begin
    Result.Settings := TServerSettings.Default;
  end
  else
  begin
    Result.Settings := TConfigurationParser.Parse(AConfig, mIssues);
  end;
  Result.RelativePath := 'A.pas';
  Result.FileName := 'C:\P\A.pas';
end;

function Provider(const AContext: TRuleCheckContext): TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AResult: TRuleCheckContext): Boolean
    begin
      AResult := AContext;
      Result := True;
    end;
end;

function CheckOf(const AContext: TRuleCheckContext; const ACancelled: TRuleCancelled): IRuleDocumentCheck;
var
  mChecks: IRuleDocumentChecks;
begin
  mChecks := TRuleDocumentChecks.Create(Provider(AContext));
  Result := mChecks.ForDocument('file:///C:/P/A.pas', ACancelled);
end;

/// <summary>Dokument mit AText (eigener Speicher, Version 1).</summary>
function DocumentOf(const AText: string): ITextDocument;
var
  mStore: IDocumentStore;
begin
  mStore := TDocumentStore.Create;
  Result := mStore.Open('file:///C:/P/A.pas', 'objectpascal', 1, AText);
end;

function FindingsOf(const ACheck: IRuleDocumentCheck; const AText: string): TArray<TRuleFinding>;
begin
  Result := ACheck.RuleFindings(DocumentOf(AText), nil);
end;

function SyntaxOf(const ACheck: IRuleDocumentCheck; const AText: string): TArray<TRuleFinding>;
begin
  Result := ACheck.SyntaxFindings(DocumentOf(AText), nil);
end;

{ TRuleDocumentChecksTests }

procedure TRuleDocumentChecksTests.WithoutContextUsesDefaults;
var
  mChecks: IRuleDocumentChecks;
  mCheck: IRuleDocumentCheck;
  mSyntax: TArray<TRuleFinding>;
begin
  mChecks := TRuleDocumentChecks.Create(nil);
  mCheck := mChecks.ForDocument('file:///C:/P/A.pas', nil);
  mSyntax := SyntaxOf(mCheck, cBroken);
  Assert.AreEqual(1, Integer(Length(mSyntax)));
  Assert.AreEqual('syntax', mSyntax[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mSyntax[0].Severity));
  Assert.AreEqual(0, Integer(Length(FindingsOf(mCheck, cValid))));
  Assert.IsTrue(mCheck.UnusedUsesShown);
  Assert.IsTrue(mCheck.OnlyImplementationShown);
end;

procedure TRuleDocumentChecksTests.SyntaxFollowsSettings;
begin
  Assert.AreEqual(0, Integer(Length(SyntaxOf(CheckOf(ContextWith('{ "rules": { "syntax": "off" } }'), nil),
    cBroken))));
end;

procedure TRuleDocumentChecksTests.RuleFindingsWithoutBaseline;
var
  mContext: TRuleCheckContext;
  mSource: TBaselineSource;
begin
  mContext := ContextWith('');
  Assert.AreEqual(1, Integer(Length(FindingsOf(CheckOf(mContext, nil), cValid))));
  mSource.Path := mContext.RelativePath;
  mSource.Text := cValid;
  mSource.Findings := FindingsOf(CheckOf(mContext, nil), cValid);
  mContext.Baseline := TRuleBaseline.FromJson(TRuleBaseline.Build([mSource]));
  Assert.AreEqual(0, Integer(Length(FindingsOf(CheckOf(mContext, nil), cValid))));
end;

procedure TRuleDocumentChecksTests.UsesSwitchesFollowRules;
var
  mCheck: IRuleDocumentCheck;
begin
  mCheck := CheckOf(ContextWith('{ "rules": { "unused-uses": "off" } }'), nil);
  Assert.IsFalse(mCheck.UnusedUsesShown);
  Assert.IsTrue(mCheck.OnlyImplementationShown);
  mCheck := CheckOf(ContextWith('{ "rules": { "uses-only-in-implementation": "off" } }'), nil);
  Assert.IsTrue(mCheck.UnusedUsesShown);
  Assert.IsFalse(mCheck.OnlyImplementationShown);
end;

procedure TRuleDocumentChecksTests.CancelledReachesRules;
var
  mCancelled: TRuleCancelled;
  mRaised: Boolean;
begin
  mCancelled :=
    function: Boolean
    begin
      Result := True;
    end;
  mRaised := False;
  try
    FindingsOf(CheckOf(ContextWith(''), mCancelled), cValid);
  except
    on ERuleCheckCancelled do
    begin
      mRaised := True;
    end;
  end;
  Assert.IsTrue(mRaised);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleDocumentChecksTests);

end.
