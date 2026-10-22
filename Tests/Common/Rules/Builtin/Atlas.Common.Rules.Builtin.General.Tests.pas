unit Atlas.Common.Rules.Builtin.General.Tests;

// Tests für die allgemeinen Regeln aus #56, Stufe 1: empty-except,
// interface-guid, duplicate-interface-guid, file-header und hardcoded-string;
// empty-finally (#1065).

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
    procedure EmptyFinallyIssueExample;
    [Test]
    procedure EmptyFinallyFixVariants;
    [Test]
    procedure EmptyFinallySilentCases;
    [Test]
    procedure EmptyFinallyOffAndExclude;
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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Tests.RuleAssert;

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
  Assert.AreEqual(42, Integer(Length(Line)));
  Assert.IsTrue(Line.StartsWith('[''{') and Line.EndsWith('}'']'), Line);
  Assert.AreNotEqual(Line, GuidLine);
end;

procedure TGeneralRulesTests.EmptyFinallyIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Liste := TStringList.Create;'#10'  try'#10'    Liste.LoadFromFile(Pfad);'#10'  finally'#10 +
    '  end;'#10'  Weiter;');
  Findings := TRuleAssert.Findings(TEmptyFinallyRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('empty-finally', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Leerer finally-Block; fehlt hier Liste.Free?', Findings[0].Message);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('try … finally end entfernen (Rumpf bleibt)', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual(InRoutine('  Liste := TStringList.Create;'#10'  Liste.LoadFromFile(Pfad);'#10'  Weiter;'),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
end;

procedure TGeneralRulesTests.EmptyFinallyFixVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Ohne Create davor allgemeine Meldung; fehlendes Semikolon wandert an den Rumpf.
  Source := InRoutine('  try'#10'    Lesen;'#10#10'    Schreiben'#10'  finally'#10'  end;'#10'  Weiter;');
  Findings := TRuleAssert.Findings(TEmptyFinallyRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Leerer finally-Block; die Freigabe fehlt oder try … finally ist überflüssig.', Findings[0].Message);
  Assert.AreEqual(InRoutine('  Lesen;'#10#10'  Schreiben;'#10'  Weiter;'),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Einzige Anweisung eines if mit zwei Anweisungen im Rumpf: begin … end.
  Source := InRoutine('  if Bereit then'#10'    try'#10'      Lesen;'#10'      Schreiben;'#10'    finally'#10 +
    '    end;');
  Findings := TRuleAssert.Findings(TEmptyFinallyRule.Create, Source);
  Assert.AreEqual('try … finally end durch begin … end ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  if Bereit then'#10'    begin'#10'      Lesen;'#10'      Schreiben;'#10'    end;'),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Mit einer Anweisung reicht das Ausrücken.
  Source := InRoutine('  if Bereit then'#10'    try'#10'      Lesen;'#10'    finally'#10'    end;');
  Findings := TRuleAssert.Findings(TEmptyFinallyRule.Create, Source);
  Assert.AreEqual(InRoutine('  if Bereit then'#10'    Lesen;'), TChangeSignature.ApplyEdits(Source,
    Findings[0].Fixes[0].Edits));
  // Alles in einer Zeile: Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TEmptyFinallyRule.Create, InRoutine('  try Lesen; finally end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TGeneralRulesTests.EmptyFinallySilentCases;
begin
  TRuleAssert.Silent(TEmptyFinallyRule.Create, InRoutine('  try'#10'    Lesen;'#10'  finally'#10'    Liste.Free;'#10 +
    '  end;'));
  TRuleAssert.Silent(TEmptyFinallyRule.Create, InRoutine('  try'#10'    Lesen;'#10'  finally'#10 +
    '    // Freigabe übernimmt der Besitzer'#10'  end;'));
  TRuleAssert.Silent(TEmptyFinallyRule.Create, InRoutine('  try'#10'    Lesen;'#10'  finally'#10 +
    '    {$IFDEF DEBUG}Protokoll;{$ENDIF}'#10'  end;'));
  TRuleAssert.Silent(TEmptyFinallyRule.Create, InRoutine('  try'#10'    Lesen;'#10'  except'#10'  end;'));
  // Ein inneres leeres finally wird gemeldet, das äußere volle nicht.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, InRoutine('  try'#10 +
    '    try'#10'      Lesen;'#10'    finally'#10'    end;'#10'  finally'#10'    Liste.Free;'#10'  end;')))));
end;

procedure TGeneralRulesTests.EmptyFinallyOffAndExclude;
var
  Source: string;
begin
  Source := InRoutine('  try'#10'    Lesen;'#10'  finally'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, Source,
    '{"rules": {"empty-finally": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, Source,
    '{"rules": {"group:style": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, Source,
    '{"rules": {"empty-finally": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TGeneralRulesTests);

end.
