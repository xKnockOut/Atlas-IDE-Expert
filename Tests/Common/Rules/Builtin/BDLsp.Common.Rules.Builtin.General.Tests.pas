unit BDLsp.Common.Rules.Builtin.General.Tests;

// Tests für die allgemeinen Regeln aus #56, Stufe 1: empty-except,
// interface-guid, duplicate-interface-guid, file-header und hardcoded-string.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGeneralRulesTests = class
  public
    [Test]
    procedure EmptyExceptReportedWithRaiseFix;
    [Test]
    procedure EmptyExceptWithCommentOrStatementSilent;
    [Test]
    procedure InterfaceWithoutGuidReported;
    [Test]
    procedure InterfaceGuidConfidenceDependsOnQueries;
    [Test]
    procedure InterfaceWithGuidOrForwardSilent;
    [Test]
    procedure DuplicateGuidReportedAtBothPlaces;
    [Test]
    procedure DistinctGuidsSilent;
    [Test]
    procedure FileHeaderNeedsTemplate;
    [Test]
    procedure FileHeaderReportedWithFix;
    [Test]
    procedure HardcodedStringInStatements;
    [Test]
    procedure GuidLineFormat;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin.General,
  BDLsp.Tests.RuleAssert;

const
  // Treffer niedriger Konfidenz erscheinen erst mit minConfidence "low".
  AllConfidences = '{ "minConfidence": "low" }';

function InRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

function InType(const ATypes: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + ATypes + #10'implementation'#10'end.';
end;

procedure TGeneralRulesTests.EmptyExceptReportedWithRaiseFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEmptyExceptRule.Create, InRoutine('  try'#10'    Save;'#10'  except'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(#10'    raise;', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Reports(TEmptyExceptRule.Create, InRoutine('  try Save; except end;'));
end;

procedure TGeneralRulesTests.EmptyExceptWithCommentOrStatementSilent;
begin
  TRuleAssert.Silent(TEmptyExceptRule.Create, InRoutine('  try Save; except { absichtlich ignoriert } end;'));
  TRuleAssert.Silent(TEmptyExceptRule.Create, InRoutine('  try Save; except'#10'    // Datei darf fehlen'#10 +
    '  end;'));
  TRuleAssert.Silent(TEmptyExceptRule.Create, InRoutine('  try Save; except raise; end;'));
  TRuleAssert.Silent(TEmptyExceptRule.Create, InRoutine('  try Save; except on E: Exception do Log(E); end;'));
end;

procedure TGeneralRulesTests.InterfaceWithoutGuidReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  ISaver = interface(IInterface)'#10 +
    '    procedure Save;'#10'  end;'), AllConfidences);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  // Eingefügt hinter der Klammer der Vorfahren.
  Assert.AreEqual(32, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.IsTrue(Findings[0].Fixes[0].Edits[0].NewText.StartsWith(#10'    [''{'));
end;

procedure TGeneralRulesTests.InterfaceGuidConfidenceDependsOnQueries;
const
  Types = '  ISaver = interface'#10'  end;';
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TInterfaceGuidRule.Create, InType(Types));
  Findings := TRuleAssert.Findings(TInterfaceGuidRule.Create, InType(Types), AllConfidences);
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Findings := TRuleAssert.Findings(TInterfaceGuidRule.Create, 'unit U;'#10'interface'#10'type'#10 + Types +
    #10'implementation'#10'procedure P(X: IInterface);'#10'var S: ISaver;'#10'begin'#10 +
    '  if Supports(X, ISaver, S) then S := nil;'#10'end;'#10'end.');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Findings := TRuleAssert.Findings(TInterfaceGuidRule.Create, 'unit U;'#10'interface'#10'type'#10 + Types +
    #10'implementation'#10'procedure P(X: IInterface);'#10'begin'#10'  (X as ISaver)._AddRef;'#10'end;'#10'end.');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TGeneralRulesTests.InterfaceWithGuidOrForwardSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  ISaver = interface'#10 +
    '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']'#10'  end;'), AllConfidences))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  ISaver = interface;'#10 +
    '  ILoader = interface'#10'    [SID_Loader]'#10'  end;'), AllConfidences))));
  // Das Schlüsselwort interface des Unit-Abschnitts ist keine Deklaration.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'end.', AllConfidences))));
end;

procedure TGeneralRulesTests.DuplicateGuidReportedAtBothPlaces;
const
  Guid = '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDuplicateInterfaceGuidRule.Create, InType('  ILoader = interface'#10 + Guid +
    #10'  end;'#10'  ISaver = interface'#10 + LowerCase(Guid) + #10'  end;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(7, Findings[1].Range.StartPos.Line);
  Assert.Contains(Findings[0].Message, 'ISaver');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.IsTrue(Findings[0].Fixes[0].Edits[0].NewText.StartsWith('''{'));
end;

procedure TGeneralRulesTests.DistinctGuidsSilent;
begin
  TRuleAssert.Silent(TDuplicateInterfaceGuidRule.Create, InType('  ILoader = interface'#10 +
    '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']'#10'  end;'#10'  ISaver = interface'#10 +
    '    [''{0B9E4F21-7C6D-4A3E-8F15-2D9C7B6A4E31}'']'#10'  end;'));
end;

procedure TGeneralRulesTests.FileHeaderNeedsTemplate;
const
  Config = '{ "rules": { "file-header": { "severity": "hint" } } }';
begin
  // Standard aus; eingeschaltet ohne Vorlage gibt es nichts zu vergleichen.
  TRuleAssert.Silent(TFileHeaderRule.Create, 'unit U;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFileHeaderRule.Create, 'unit U;', Config))));
  Assert.AreEqual('', TFileHeaderRule.Template(''));
  Assert.AreEqual('// Kopf', TFileHeaderRule.Template('{ "template": "// Kopf" }'));
end;

procedure TGeneralRulesTests.FileHeaderReportedWithFix;
const
  Config = '{ "rules": { "file-header": { "severity": "hint", "template": "// (c) Beispiel\n// Lizenz: MIT" } } }';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFileHeaderRule.Create, 'unit U;'#13#10'end.', Config);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('// (c) Beispiel'#13#10'// Lizenz: MIT'#13#10, Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFileHeaderRule.Create,
    '// (c) Beispiel'#10'// Lizenz: MIT'#10'unit U;', Config))));
end;

procedure TGeneralRulesTests.HardcodedStringInStatements;
const
  Config = '{ "minConfidence": "low", "rules": { "hardcoded-string": "hint" } }';
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(THardcodedStringRule.Create, InRoutine('  ShowMessage(''Datei nicht gefunden'');'));
  Findings := TRuleAssert.Findings(THardcodedStringRule.Create, InRoutine('  ShowMessage(''Datei nicht gefunden'');' +
    #10'  X := ''abc'';'#10'  Y := ''%s: %d'';'), Config);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THardcodedStringRule.Create, 'unit U;'#10'interface'#10 +
    'resourcestring'#10'  SFehlt = ''Datei nicht gefunden'';'#10'implementation'#10'end.', Config))));
end;

procedure TGeneralRulesTests.GuidLineFormat;
var
  Line: string;
begin
  Line := GuidLine;
  Assert.AreEqual(42, Length(Line));
  Assert.IsTrue(Line.StartsWith('[''{') and Line.EndsWith('}'']'), Line);
  Assert.AreNotEqual(Line, GuidLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TGeneralRulesTests);

end.
