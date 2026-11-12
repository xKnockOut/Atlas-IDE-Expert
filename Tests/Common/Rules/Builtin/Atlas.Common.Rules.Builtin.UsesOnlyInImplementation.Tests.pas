unit Atlas.Common.Rules.Builtin.UsesOnlyInImplementation.Tests;

// Tests der Regel uses-only-in-implementation (#1136): Treffer mit
// Korrektur, die das implementation-uses anlegt oder ergänzt; Units, deren
// Bezeichner der interface-Teil nennt, ungenutzte Units (meldet unused-uses)
// und Units mit initialization bleiben stumm; ebenso im Editor (Live), ohne
// Index, in Programmen, mit abgeschalteter Regel und unter lsp-ignore.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesOnlyInImplementationTests = class
  public
    [Test]
    procedure ReportsEntryWithMoveFix;
    [Test]
    procedure FixAddsToExistingImplementationUses;
    [Test]
    procedure InterfaceUseIsQuiet;
    [Test]
    procedure UnusedUnitIsLeftToUnusedUses;
    [Test]
    procedure InitializationUnitStays;
    [Test]
    procedure ImplementationEntryIsQuiet;
    [Test]
    procedure LiveAndWithoutIndexAreQuiet;
    [Test]
    procedure ProgramIsQuiet;
    [Test]
    procedure RuleOffAndSuppressionAreQuiet;
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
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Editing.TextChanges;

const
  cOther = 'unit Andere;'#13#10#13#10'interface'#13#10#13#10'procedure Mach;'#13#10#13#10'implementation'#13#10#13#10 +
    'procedure Mach;'#13#10'begin'#13#10'end;'#13#10#13#10'end.'#13#10;
  cTypes = 'unit Typen;'#13#10#13#10'interface'#13#10#13#10'type'#13#10'  TListe = class'#13#10'  end;'#13#10#13#10 +
    'implementation'#13#10#13#10'end.'#13#10;
  cRegistry = 'unit Ablage;'#13#10#13#10'interface'#13#10#13#10'procedure Melde;'#13#10#13#10'implementation'#13#10#13#10 +
    'procedure Melde;'#13#10'begin'#13#10'end;'#13#10#13#10'initialization'#13#10'  Melde;'#13#10#13#10'end.'#13#10;
  cHelper = 'unit Hilfe;'#13#10#13#10'interface'#13#10#13#10'procedure Tu;'#13#10#13#10'implementation'#13#10#13#10 +
    'procedure Tu;'#13#10'begin'#13#10'end;'#13#10#13#10'end.'#13#10;

function Index: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cOther, 'Andere.pas', nil, nil, True));
  Result.AddUnit(TIndexExtractor.ExtractText(cTypes, 'Typen.pas', nil, nil, True));
  Result.AddUnit(TIndexExtractor.ExtractText(cRegistry, 'Ablage.pas', nil, nil, True));
  Result.AddUnit(TIndexExtractor.ExtractText(cHelper, 'Hilfe.pas', nil, nil, True));
end;

/// <summary>Unit Bericht mit AUses im interface-Teil (leer: ohne uses), AImplementationUses im
/// implementation-Teil (leer: ohne uses) und einem Rumpf, der Mach, Melde und Tu aufruft.</summary>
function UnitText(const AUses, AImplementationUses: string): string;
begin
  Result := 'unit Bericht;'#13#10#13#10'interface'#13#10#13#10;
  if AUses <> '' then
  begin
    Result := Result + 'uses'#13#10'  ' + AUses + ';'#13#10#13#10;
  end;
  Result := Result + 'procedure X(AListe: TObject);'#13#10#13#10'implementation'#13#10#13#10;
  if AImplementationUses <> '' then
  begin
    Result := Result + 'uses'#13#10'  ' + AImplementationUses + ';'#13#10#13#10;
  end;
  Result := Result + 'procedure X(AListe: TObject);'#13#10'begin'#13#10'  Mach;'#13#10'  Melde;'#13#10'  Tu;'#13#10 +
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
  Result := TFileChecker.CheckText(TArray<IRule>.Create(TUsesOnlyInImplementationRule.Create), ASettings, AFileName,
    AText, Project(AIndex));
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
  begin
    if mFinding.RuleId = cUsesOnlyInImplementationRuleId then
    begin
      Result := Result + mFinding.Message + ';';
    end;
  end;
end;

function Settings(const AJson: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TUsesOnlyInImplementationTests.ReportsEntryWithMoveFix;
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
begin
  mText := UnitText('Andere', '');
  mFindings := Check(mText);
  Assert.AreEqual('Andere wird nur im implementation-Teil gebraucht;', Names(mFindings));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  // Nicht sicher: Im implementation-uses kann die Unit gleichnamige Bezeichner anderer Units verdecken.
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
  // Das leere interface-uses verschwindet ganz (Leerzeilen bleiben wie bei „uses aufräumen“), das
  // implementation-uses entsteht.
  Assert.AreEqual(StringReplace(UnitText('', 'Andere'), 'interface'#13#10#13#10, 'interface'#13#10#13#10#13#10#13#10,
    []), TTextChanges.Apply(mText, mFindings[0].Fixes[0].Edits));
end;

procedure TUsesOnlyInImplementationTests.FixAddsToExistingImplementationUses;
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
begin
  mText := UnitText('Andere, Typen', 'Hilfe');
  mFindings := Check(mText);
  Assert.AreEqual('Andere wird nur im implementation-Teil gebraucht;', Names(mFindings));
  Assert.AreEqual(UnitText('Typen', 'Hilfe,'#13#10'  Andere'), TTextChanges.Apply(mText, mFindings[0].Fixes[0].Edits));
end;

procedure TUsesOnlyInImplementationTests.InterfaceUseIsQuiet;
begin
  // TListe aus Typen steht im interface-Teil: Typen bleibt im interface-uses.
  Assert.AreEqual('', Names(Check(StringReplace(UnitText('Typen', ''), 'AListe: TObject', 'AListe: TListe',
    [rfReplaceAll]))));
end;

procedure TUsesOnlyInImplementationTests.UnusedUnitIsLeftToUnusedUses;
begin
  // Aus Typen wird nichts verwendet: Das meldet unused-uses, nicht diese Regel.
  Assert.AreEqual('', Names(Check(UnitText('Typen', ''))));
end;

procedure TUsesOnlyInImplementationTests.InitializationUnitStays;
begin
  // Ablage hat initialization: Im implementation-uses liefe sie später.
  Assert.AreEqual('', Names(Check(UnitText('Ablage', ''))));
end;

procedure TUsesOnlyInImplementationTests.ImplementationEntryIsQuiet;
begin
  Assert.AreEqual('', Names(Check(UnitText('', 'Andere, Hilfe'))));
end;

procedure TUsesOnlyInImplementationTests.LiveAndWithoutIndexAreQuiet;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mText: string;
begin
  mText := UnitText('Andere', '');
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'Bericht.pas';
    mContext.UnitName := 'Bericht';
    mContext.Text := mText;
    mContext.Tree := mTree;
    mContext.Index := Index;
    mContext.Live := True;
    // Im Editor zeigt der Server denselben Hinweis (TLspDiagnosticItems.AddUses).
    Assert.AreEqual('', Names(TRuleEngine.Run(TArray<IRule>.Create(TUsesOnlyInImplementationRule.Create),
      TServerSettings.Default, mContext)));
    mContext.Live := False;
    Assert.AreEqual('Andere wird nur im implementation-Teil gebraucht;', Names(TRuleEngine.Run(
      TArray<IRule>.Create(TUsesOnlyInImplementationRule.Create), TServerSettings.Default, mContext)));
    mContext.Index := nil;
  finally
    mTree.Free;
  end;
  Assert.AreEqual('', Names(Check(mText, TServerSettings.Default, nil, 'Bericht.pas')));
end;

procedure TUsesOnlyInImplementationTests.ProgramIsQuiet;
const
  cProgram = 'program P;'#13#10#13#10'uses'#13#10'  Andere in ''Andere.pas'';'#13#10#13#10'begin'#13#10'  Mach;'#13#10 +
    'end.'#13#10;
begin
  Assert.AreEqual('', Names(Check(cProgram, TServerSettings.Default, Index, 'P.dpr')));
end;

procedure TUsesOnlyInImplementationTests.RuleOffAndSuppressionAreQuiet;
begin
  Assert.AreEqual('', Names(Check(UnitText('Andere', ''), Settings(
    '{"rules": {"uses-only-in-implementation": "off"}}'), Index, 'Bericht.pas')));
  Assert.AreEqual('', Names(Check(UnitText('Andere', ''), Settings(
    '{"rules": {"uses-only-in-implementation": {"severity": "hint", "exclude": ["Bericht.pas"]}}}'), Index,
    'Bericht.pas')));
  Assert.AreEqual('', Names(Check(UnitText('// lsp-ignore: uses-only-in-implementation'#13#10'  Andere', ''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesOnlyInImplementationTests);

end.
