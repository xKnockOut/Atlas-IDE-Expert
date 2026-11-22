unit Atlas.Common.Rules.Providers.DocumentActions.Tests;

// Tests für die Prüfregeln der Code-Aktionen je Dokument: ohne Umfeld nur Syntaxfehler, Treffer aus dem gemeinsamen
// Speicher oder selbst gerechnet, das Warten-Signal bricht den eigenen Lauf nicht ab, Korrekturen in der Zeile und
// Auftrag für KI-Assistenten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleDocumentActionsTests = class
  public
    [Test]
    procedure WithoutContextGivesOnlySyntax;
    [Test]
    procedure CachedFindingsAfterSharedRun;
    [Test]
    procedure WaitSignalKeepsOwnRun;
    [Test]
    procedure FixesInRangeAndPrompt;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Findings.Memo,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.CheckContext,
  Atlas.Common.Rules.Providers.DocumentActions,
  Atlas.Tests.LspRules;

const
  cBroken = 'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'procedure X;' + #10 + 'begin' + #10 +
    '  if True' + #10 + '  X;' + #10 + 'end;' + #10 + 'end.';
  cValid = 'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'end.';
  cUri = 'file:///C:/P/A.pas';

type
  /// <summary>Ein Treffer je Lauf in Zeile 0.</summary>
  TFirstLineRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TFirstLineRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('erste-zeile', TRuleSeverity.Warning, 'Erste Zeile');
end;

procedure TFirstLineRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  AReport.Add(TTextRange.Create(0, 0, 0, 4), 'Treffer');
end;

/// <summary>Aktionen für A.pas mit der Regel erste-zeile und AMemo (nil = ohne Speicher).</summary>
function ActionsWith(const AMemo: IRuleFindingsMemo; const AWaitCancelled: TRuleCancelled): IRuleDocumentActions;
var
  mRule: IRule;
  mContext: TRuleCheckContext;
  mActions: IRuleCodeActions;
begin
  mRule := TFirstLineRule.Create;
  mContext := Default(TRuleCheckContext);
  mContext.Rules := [mRule];
  mContext.Settings := TServerSettings.Default;
  mContext.RelativePath := 'A.pas';
  mContext.FileName := 'C:\P\A.pas';
  mContext.Memo := AMemo;
  mActions := TRuleCodeActionsProvider.Create(TTestLspRules.Fixed(mContext));
  Result := mActions.ForDocument(cUri, AWaitCancelled);
end;

/// <summary>Dokument mit AText (eigener Speicher, Version 1).</summary>
function DocumentOf(const AText: string): ITextDocument;
var
  mStore: IDocumentStore;
begin
  mStore := TDocumentStore.Create;
  Result := mStore.Open(cUri, 'objectpascal', 1, AText);
end;

{ TRuleDocumentActionsTests }

procedure TRuleDocumentActionsTests.WithoutContextGivesOnlySyntax;
var
  mActions: IRuleDocumentActions;
  mDocument: ITextDocument;
  mSyntax, mCached: TArray<TRuleFinding>;
begin
  mActions := (TRuleCodeActionsProvider.Create(nil) as IRuleCodeActions).ForDocument(cUri, nil);
  mDocument := DocumentOf(cBroken);
  mSyntax := mActions.SyntaxFindings(mDocument);
  Assert.AreEqual(1, Integer(Length(mSyntax)));
  Assert.AreEqual('syntax', mSyntax[0].RuleId);
  Assert.AreEqual(0, Integer(Length(mActions.SharedRuleFindings(mDocument))));
  Assert.IsTrue(mActions.CachedRuleFindings(mDocument, mCached));
  Assert.AreEqual(0, Integer(Length(mCached)));
  Assert.IsNull(mActions.Index);
end;

procedure TRuleDocumentActionsTests.CachedFindingsAfterSharedRun;
var
  mMemo: IRuleFindingsMemo;
  mActions: IRuleDocumentActions;
  mDocument: ITextDocument;
  mCached: TArray<TRuleFinding>;
begin
  mMemo := TRuleFindingsMemo.Create;
  mActions := ActionsWith(mMemo, nil);
  mDocument := DocumentOf(cValid);
  Assert.IsFalse(mActions.CachedRuleFindings(mDocument, mCached));
  Assert.AreEqual(1, Integer(Length(mActions.SharedRuleFindings(mDocument))));
  Assert.IsTrue(mActions.CachedRuleFindings(mDocument, mCached));
  Assert.AreEqual(1, Integer(Length(mCached)));
  Assert.AreEqual('erste-zeile', mCached[0].RuleId);
end;

procedure TRuleDocumentActionsTests.WaitSignalKeepsOwnRun;
var
  mMemo: IRuleFindingsMemo;
  mActions: IRuleDocumentActions;
begin
  mMemo := TRuleFindingsMemo.Create;
  mActions := ActionsWith(mMemo,
    function: Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual(1, Integer(Length(mActions.SharedRuleFindings(DocumentOf(cValid)))));
end;

procedure TRuleDocumentActionsTests.FixesInRangeAndPrompt;
var
  mActions: IRuleDocumentActions;
  mDocument: ITextDocument;
  mFindings: TArray<TRuleFinding>;
  mAll: TCodeAction;
begin
  mActions := ActionsWith(nil, nil);
  mDocument := DocumentOf(cValid);
  mFindings := mActions.SharedRuleFindings(mDocument);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(Length(mActions.Fixes(mFindings, mDocument, TTextRange.Create(0, 0, 0, 0), TFormatStyle.Default,
    True)) > 0);
  Assert.AreEqual(0, Integer(Length(mActions.Fixes(mFindings, mDocument, TTextRange.Create(3, 0, 3, 0),
    TFormatStyle.Default, False))));
  Assert.IsFalse(mActions.FixAll(mFindings, mAll));
  Assert.IsTrue(mActions.Prompt(mFindings[0], 'C:\P\A.pas', cValid).Contains('erste-zeile'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleDocumentActionsTests);

end.
