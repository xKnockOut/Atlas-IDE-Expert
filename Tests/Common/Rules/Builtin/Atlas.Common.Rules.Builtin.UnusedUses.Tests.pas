unit Atlas.Common.Rules.Builtin.UnusedUses.Tests;

// Tests der Regel unused-uses (#1352): ungenutzter Eintrag mit sicherer
// Korrektur, benutzte Units, initialization, usesKeep, inaktive Zweige,
// Schweigen in Programmen, im Editor (Live) und ohne Index, und die
// Sammelkorrektur mit zwei Einträgen derselben Liste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnusedUsesTests = class
  public
    [Test]
    procedure ReportsUnusedEntryWithSafeFix;
    [Test]
    procedure UsedUnitIsQuiet;
    [Test]
    procedure InitializationKeepsUnit;
    [Test]
    procedure UsesKeepKeepsUnit;
    [Test]
    procedure InactiveBranchIsIgnored;
    [Test]
    procedure ProgramIsQuiet;
    [Test]
    procedure LiveIsQuiet;
    [Test]
    procedure WithoutIndexIsQuiet;
    [Test]
    procedure BulkFixRemovesAllUnusedEntries;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Editing.TextChanges;

const
  cHelper = 'unit Hilfe;'#13#10#13#10'interface'#13#10#13#10'procedure Tu;'#13#10#13#10'implementation'#13#10#13#10 +
    'procedure Tu;'#13#10'begin'#13#10'end;'#13#10#13#10'end.'#13#10;
  cOther = 'unit Andere;'#13#10#13#10'interface'#13#10#13#10'procedure Mach;'#13#10#13#10'implementation'#13#10#13#10 +
    'procedure Mach;'#13#10'begin'#13#10'end;'#13#10#13#10'end.'#13#10;
  cThird = 'unit Dritte;'#13#10#13#10'interface'#13#10#13#10'const'#13#10'  Wert = 1;'#13#10#13#10 +
    'implementation'#13#10#13#10'end.'#13#10;
  cStart = 'unit Start;'#13#10#13#10'interface'#13#10#13#10'implementation'#13#10#13#10'initialization'#13#10 +
    'end.'#13#10;

function Index: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cHelper, 'Hilfe.pas', nil, nil, True));
  Result.AddUnit(TIndexExtractor.ExtractText(cOther, 'Andere.pas', nil, nil, True));
  Result.AddUnit(TIndexExtractor.ExtractText(cStart, 'Start.pas', nil, nil, True));
  Result.AddUnit(TIndexExtractor.ExtractText(cThird, 'Dritte.pas', nil, nil, True));
end;

function UnitText(const AUses: string): string;
begin
  Result := 'unit Bericht;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  ' + AUses + ';'#13#10#13#10 +
    'procedure X;'#13#10#13#10'implementation'#13#10#13#10'procedure X;'#13#10'begin'#13#10'  Mach;'#13#10 +
    'end;'#13#10#13#10'end.'#13#10;
end;

function Project(const AIndex: ISymbolIndex): TCheckProject;
begin
  Result := Default(TCheckProject);
  Result.Services.Index := AIndex;
end;

function Check(const AText: string; const ASettings: TServerSettings; const AIndex: ISymbolIndex;
  const AFileName: string): TArray<TRuleFinding>; overload;
begin
  Result := TFileChecker.CheckText(TArray<IRule>.Create(TUnusedUsesRule.Create), ASettings, AFileName, AText,
    Project(AIndex));
end;

function Check(const AText: string): TArray<TRuleFinding>; overload;
begin
  Result := Check(AText, TServerSettings.Default, Index, 'Bericht.pas');
end;

function Names(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
    if mFinding.RuleId = UnusedUsesRuleId then
      Result := Result + mFinding.Message + ';';
end;

procedure TUnusedUsesTests.ReportsUnusedEntryWithSafeFix;
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
begin
  mText := UnitText('Hilfe, Andere');
  mFindings := Check(mText);
  Assert.AreEqual('Aus Hilfe wird nichts verwendet;', Names(mFindings));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  Assert.AreEqual(UnitText('Andere'), TTextChanges.Apply(mText, mFindings[0].Fixes[0].Edits));
end;

procedure TUnusedUsesTests.UsedUnitIsQuiet;
begin
  Assert.AreEqual('', Names(Check(UnitText('Andere'))));
end;

procedure TUnusedUsesTests.InitializationKeepsUnit;
begin
  Assert.AreEqual('', Names(Check(UnitText('Start, Andere'))));
end;

procedure TUnusedUsesTests.UsesKeepKeepsUnit;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse('{"usesKeep": ["Hilfe"]}', mIssues);
  Assert.AreEqual('', Names(Check(UnitText('Hilfe, Andere'), mSettings, Index, 'Bericht.pas')));
end;

procedure TUnusedUsesTests.InactiveBranchIsIgnored;
begin
  // Der Eintrag im inaktiven Zweig zählt nicht; der aktive bleibt geprüft.
  Assert.AreEqual('', Names(Check(UnitText('Andere{$IFDEF NIE_DEFINIERT}, Hilfe{$ENDIF}'))));
  Assert.AreEqual('Aus Hilfe wird nichts verwendet;',
    Names(Check(UnitText('Andere{$IFNDEF NIE_DEFINIERT}, Hilfe{$ENDIF}'))));
end;

procedure TUnusedUsesTests.ProgramIsQuiet;
const
  cProgram = 'program P;'#13#10#13#10'uses'#13#10'  Hilfe in ''Hilfe.pas'', Andere in ''Andere.pas'';'#13#10#13#10 +
    'begin'#13#10'end.'#13#10;
begin
  // Das uses eines Programms zählt die Units des Projekts auf.
  Assert.AreEqual('', Names(Check(cProgram, TServerSettings.Default, Index, 'P.dpr')));
end;

procedure TUnusedUsesTests.LiveIsQuiet;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mText: string;
begin
  mText := UnitText('Hilfe, Andere');
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'Bericht.pas';
    mContext.UnitName := 'Bericht';
    mContext.Text := mText;
    mContext.Tree := mTree;
    mContext.Index := Index;
    mContext.Live := True;
    Assert.AreEqual('', Names(TRuleEngine.Run(TArray<IRule>.Create(TUnusedUsesRule.Create),
      TServerSettings.Default, mContext)));
    mContext.Live := False;
    Assert.AreEqual('Aus Hilfe wird nichts verwendet;', Names(TRuleEngine.Run(
      TArray<IRule>.Create(TUnusedUsesRule.Create), TServerSettings.Default, mContext)));
    mContext.Index := nil;
  finally
    mTree.Free;
  end;
end;

procedure TUnusedUsesTests.WithoutIndexIsQuiet;
begin
  Assert.AreEqual('', Names(Check(UnitText('Hilfe, Andere'), TServerSettings.Default, nil, 'Bericht.pas')));
end;

procedure TUnusedUsesTests.BulkFixRemovesAllUnusedEntries;
var
  mIndex: ISymbolIndex;
  mResult: TBulkFixFile;
  mSettings: TServerSettings;
begin
  mIndex := Index;
  mSettings := TServerSettings.Default;
  // Hilfe und Dritte stehen nebeneinander: Ihre Korrekturen überlappen am Komma, die zweite folgt im nächsten
  // Durchgang.
  mResult := TBulkFix.Run('Bericht.pas', UnitText('Hilfe, Dritte, Andere, Start'), TBulkFixOptions.Create(
    TArray<string>.Create(UnusedUsesRuleId), mSettings.FixMinConfidence, TRuleCatalog.Shared.Entries),
    TBulkFix.CheckWith(TArray<IRule>.Create(TUnusedUsesRule.Create), mSettings, 'Bericht.pas', Project(mIndex),
    TCheckSource.Default), TBulkFix.SyntaxErrorsWith(TCheckSource.Default));
  Assert.AreEqual(UnitText('Andere, Start'), mResult.NewText);
  Assert.AreEqual(2, mResult.FixCount);
  Assert.AreEqual('', Names(Check(mResult.NewText)));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnusedUsesTests);

end.
