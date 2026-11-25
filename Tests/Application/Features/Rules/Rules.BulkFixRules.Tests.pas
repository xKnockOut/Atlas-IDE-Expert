unit Rules.BulkFixRules.Tests;

// Tests für die Regelseite der Sammelkorrektur: Regeln mit sicherer Korrektur aus dem Katalog, Regeln je Durchgang
// und das Zusammenspiel von TBulkFix mit den eingebauten Regeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleBulkFixTests = class
  public
    [Test]
    procedure RulesForSubsetAndAll;
    [Test]
    procedure SafeRulesComeFromCatalog;
    [Test]
    procedure SafeFixRulesExist;
    [Test]
    procedure BuiltinRedundantAssignedFree;
    [Test]
    procedure BuiltinDestroyAndResume;
    [Test]
    procedure BuiltinUnusedSuppression;
    [Test]
    procedure BuiltinUnsafeFixStays;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Rules.Contract,
  Rules.Checker,
  Rules.Catalog,
  Rules.Builtin,
  Atlas.Common.Findings.BulkFix,
  Atlas.Common.Checks.Contract,
  Rules.BulkFixRules,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Pascal.Contract;

function Builtin(const AText: string; const ARules: TArray<string>): TBulkFixFile;
var
  mSettings: TServerSettings;
begin
  mSettings := TServerSettings.Default;
  Result := TBulkFix.Run('U.pas', AText, TBulkFixOptions.Create(ARules, mSettings.FixMinConfidence,
    TRuleBulkFix.SafeRulesOf(TRuleCatalog.Shared.Entries)),
    TRuleBulkFix.CheckWith(TRuleBulkFix.RulesFor(BuiltinRules, ARules), mSettings, 'U.pas',
      Default(TCheckProject), TPascalSource.Default), TBulkFix.SyntaxErrorsWith(TPascalSource.Default));
end;

function Remaining(const AText, ARule: string): Integer;
var
  mFinding: TRuleFinding;
begin
  Result := 0;
  for mFinding in TFileChecker.CheckText(BuiltinRules, TServerSettings.Default, 'U.pas', AText) do
  begin
    if SameText(mFinding.RuleId, ARule) then
    begin
      Inc(Result);
    end;
  end;
end;

const
  cUnitHead = 'unit U;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  System.Classes;'#13#10#13#10 +
    'implementation'#13#10#13#10;

{ TRuleBulkFixTests }

procedure TRuleBulkFixTests.RulesForSubsetAndAll;
var
  mAll, mRules: TArray<IRule>;
begin
  mAll := BuiltinRules;
  mRules := TRuleBulkFix.RulesFor(mAll, TArray<string>.Create('redundant-cast'));
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual('redundant-cast', mRules[0].Descriptor.Id);
  Assert.AreEqual(Integer(Length(mAll)), Integer(Length(TRuleBulkFix.RulesFor(mAll, TArray<string>.Create('all')))));
  // syntax entsteht im Checker, unused-suppression in der Engine: dafür alle Regeln.
  Assert.AreEqual(Integer(Length(mAll)), Integer(Length(TRuleBulkFix.RulesFor(mAll,
    TArray<string>.Create('unused-suppression')))));
end;

procedure TRuleBulkFixTests.SafeRulesComeFromCatalog;
var
  mSafe: TArray<string>;
begin
  mSafe := TRuleBulkFix.SafeRulesOf(TRuleCatalog.Shared.Entries);
  Assert.IsTrue(IndexText('redundant-cast', mSafe) >= 0);
  Assert.IsTrue(IndexText('unused-uses', mSafe) >= 0);
  Assert.IsFalse(IndexText('empty-except', mSafe) >= 0);
end;

procedure TRuleBulkFixTests.SafeFixRulesExist;
var
  mEntry: TRuleCatalogEntry;
  mRule: IRule;
  mKnown: Boolean;
begin
  // safeFix nur bei Regeln, die es gibt (eingebaut, im Checker oder in der Engine).
  for mEntry in TRuleCatalog.Shared.Entries do
  begin
    if mEntry.SafeFix then
    begin
      mKnown := MatchText(mEntry.Id, ['syntax', 'unused-suppression', 'unknown-rule-id']);
      for mRule in BuiltinRules do
      begin
        if SameText(mRule.Descriptor.Id, mEntry.Id) then
        begin
          mKnown := True;
        end;
      end;
      Assert.IsTrue(mKnown, mEntry.Id);
    end;
  end;
end;

procedure TRuleBulkFixTests.BuiltinRedundantAssignedFree;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  mText := cUnitHead + 'procedure Weg(AList: TStringList);'#13#10'begin'#13#10'  if Assigned(AList) then'#13#10 +
    '    AList.Free;'#13#10'end;'#13#10#13#10'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('redundant-assigned-free'));
  Assert.AreEqual(1, mResult.FixCount, mResult.NewText);
  Assert.AreEqual(0, Remaining(mResult.NewText, 'redundant-assigned-free'), mResult.NewText);
  Assert.IsTrue(Pos('AList.Free;', mResult.NewText) > 0, mResult.NewText);
  Assert.IsFalse(Pos('Assigned', mResult.NewText) > 0, mResult.NewText);
end;

procedure TRuleBulkFixTests.BuiltinDestroyAndResume;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  mText := cUnitHead + 'procedure Weg(AList: TStringList; AThread: TThread);'#13#10'begin'#13#10 +
    '  AThread.Resume;'#13#10'  AList.Destroy;'#13#10'end;'#13#10#13#10'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('destroy-called-directly', 'thread-resume-suspend'));
  Assert.AreEqual(2, mResult.FixCount, mResult.NewText);
  Assert.IsTrue(Pos('AThread.Start;', mResult.NewText) > 0, mResult.NewText);
  Assert.IsTrue(Pos('AList.Free;', mResult.NewText) > 0, mResult.NewText);
  Assert.AreEqual(0, Remaining(mResult.NewText, 'destroy-called-directly'));
  Assert.AreEqual(0, Remaining(mResult.NewText, 'thread-resume-suspend'));
end;

procedure TRuleBulkFixTests.BuiltinUnusedSuppression;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  mText := cUnitHead + 'procedure Tu;'#13#10'var'#13#10'  X: Integer;'#13#10'begin'#13#10 +
    '  X := 1; // lsp-ignore: empty-except'#13#10'  if X = 1 then'#13#10'    X := 2;'#13#10'end;'#13#10#13#10 +
    'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('unused-suppression'));
  Assert.AreEqual(1, mResult.FixCount, mResult.NewText);
  Assert.IsFalse(Pos('lsp-ignore', mResult.NewText) > 0, mResult.NewText);
  Assert.AreEqual(0, Remaining(mResult.NewText, 'unused-suppression'));
end;

procedure TRuleBulkFixTests.BuiltinUnsafeFixStays;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  // empty-except hat keine sichere Korrektur und steht nicht mit safeFix im Katalog.
  mText := cUnitHead + 'procedure Tu;'#13#10'begin'#13#10'  try'#13#10'    Tu;'#13#10'  except'#13#10'  end;'#13#10 +
    'end;'#13#10#13#10'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('empty-except'));
  Assert.IsFalse(mResult.Changed);
  Assert.AreEqual(0, mResult.FixCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleBulkFixTests);

end.
