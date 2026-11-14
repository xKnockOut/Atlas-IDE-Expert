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
    procedure DispinterfaceSharesGuidSilent;
    [Test]
    procedure FileHeaderNeedsTemplate;
    [Test]
    procedure FileHeaderReportedWithFix;
    [Test]
    procedure HardcodedStringInStatements;
    [Test]
    procedure HardcodedStringMachineTextSilent;
    [Test]
    procedure GuidLineFormat;
    [Test]
    procedure GuidSyntaxIssueExample;
    [Test]
    procedure GuidSyntaxProblems;
    [Test]
    procedure GuidSyntaxBracesAndConstants;
    [Test]
    procedure GuidSyntaxSilentCases;
    [Test]
    procedure GuidSyntaxOffAndExclude;
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
  cAllConfidences = '{ "minConfidence": "low" }';

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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TEmptyExceptRule.Create, InRoutine('  try'#10'    Save;'#10'  except'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(#10'    raise;', mFindings[0].Fixes[0].Edits[0].NewText);
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  ISaver = interface(IInterface)'#10 +
    '    procedure Save;'#10'  end;'), cAllConfidences);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  // Eingefügt hinter der Klammer der Vorfahren.
  Assert.AreEqual(32, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.IsTrue(mFindings[0].Fixes[0].Edits[0].NewText.StartsWith(#10'    [''{'));
end;

procedure TGeneralRulesTests.InterfaceGuidConfidenceDependsOnQueries;
const
  cTypes = '  ISaver = interface'#10'  end;';
var
  mFindings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TInterfaceGuidRule.Create, InType(cTypes));
  mFindings := TRuleAssert.Findings(TInterfaceGuidRule.Create, InType(cTypes), cAllConfidences);
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  // Ohne Abfrage meldet dcc nichts: kein Code in der Meldung (#1382).
  Assert.AreEqual('Interface ISaver hat keine GUID; Supports, as und QueryInterface brauchen eine',
    mFindings[0].Message);
  mFindings := TRuleAssert.Findings(TInterfaceGuidRule.Create, 'unit U;'#10'interface'#10'type'#10 + cTypes +
    #10'implementation'#10'procedure P(X: IInterface);'#10'var S: ISaver;'#10'begin'#10 +
    '  if Supports(X, ISaver, S) then S := nil;'#10'end;'#10'end.');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  // Mit Abfrage meldet Delphi 13 E2232 (Fall Cm.E2232, #1382).
  Assert.AreEqual('Interface ISaver hat keine GUID; Supports, as und QueryInterface brauchen eine (wie E2232).',
    mFindings[0].Message);
  mFindings := TRuleAssert.Findings(TInterfaceGuidRule.Create, 'unit U;'#10'interface'#10'type'#10 + cTypes +
    #10'implementation'#10'procedure P(X: IInterface);'#10'begin'#10'  (X as ISaver)._AddRef;'#10'end;'#10'end.');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TGeneralRulesTests.InterfaceWithGuidOrForwardSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  ISaver = interface'#10 +
    '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']'#10'  end;'), cAllConfidences))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  ISaver = interface;'#10 +
    '  ILoader = interface'#10'    [SID_Loader]'#10'  end;'), cAllConfidences))));
  // Ein dispinterface ohne GUID übersetzt nicht: Das meldet dispinterface-invalid als Fehler (#1374).
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create, InType('  DSaver = dispinterface'#10 +
    '    procedure Save; dispid 1;'#10'  end;'), cAllConfidences))));
  // Das Schlüsselwort interface des Unit-Abschnitts ist keine Deklaration.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceGuidRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'end.', cAllConfidences))));
end;

procedure TGeneralRulesTests.DuplicateGuidReportedAtBothPlaces;
const
  cGuid = '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDuplicateInterfaceGuidRule.Create, InType('  ILoader = interface'#10 + cGuid +
    #10'  end;'#10'  ISaver = interface'#10 + LowerCase(cGuid) + #10'  end;'));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFindings[1].Range.StartPos.Line);
  Assert.Contains(mFindings[0].Message, 'ISaver');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.IsTrue(mFindings[0].Fixes[0].Edits[0].NewText.StartsWith('''{'));
end;

procedure TGeneralRulesTests.DistinctGuidsSilent;
begin
  TRuleAssert.Silent(TDuplicateInterfaceGuidRule.Create, InType('  ILoader = interface'#10 +
    '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']'#10'  end;'#10'  ISaver = interface'#10 +
    '    [''{0B9E4F21-7C6D-4A3E-8F15-2D9C7B6A4E31}'']'#10'  end;'));
end;

procedure TGeneralRulesTests.DispinterfaceSharesGuidSilent;
const
  cGuid = '    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']';
begin
  // Typbibliotheken (*_TLB.pas) deklarieren interface und dispinterface absichtlich mit derselben GUID.
  TRuleAssert.Silent(TDuplicateInterfaceGuidRule.Create, InType('  ILoader = interface(IDispatch)'#10 + cGuid +
    #10'  end;'#10'  ILoaderDisp = dispinterface'#10 + cGuid + #10'  end;'));
end;

procedure TGeneralRulesTests.FileHeaderNeedsTemplate;
const
  cConfig = '{ "rules": { "file-header": { "severity": "hint" } } }';
begin
  // Standard aus; eingeschaltet ohne Vorlage gibt es nichts zu vergleichen.
  TRuleAssert.Silent(TFileHeaderRule.Create, 'unit U;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFileHeaderRule.Create, 'unit U;', cConfig))));
  Assert.AreEqual('', TFileHeaderRule.Template(''));
  Assert.AreEqual('// Kopf', TFileHeaderRule.Template('{ "template": "// Kopf" }'));
end;

procedure TGeneralRulesTests.FileHeaderReportedWithFix;
const
  cConfig = '{ "rules": { "file-header": { "severity": "hint", "template": "// (c) Beispiel\n// Lizenz: MIT" } } }';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFileHeaderRule.Create, 'unit U;'#13#10'end.', cConfig);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('// (c) Beispiel'#13#10'// Lizenz: MIT'#13#10, mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFileHeaderRule.Create,
    '// (c) Beispiel'#10'// Lizenz: MIT'#10'unit U;', cConfig))));
end;

procedure TGeneralRulesTests.HardcodedStringInStatements;
const
  cConfig = '{ "minConfidence": "low", "rules": { "hardcoded-string": "hint" } }';
var
  mFindings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(THardcodedStringRule.Create, InRoutine('  ShowMessage(''Datei nicht gefunden'');'));
  mFindings := TRuleAssert.Findings(THardcodedStringRule.Create, InRoutine('  ShowMessage(''Datei nicht gefunden'');' +
    #10'  X := ''abc'';'#10'  Y := ''%s: %d'';'), cConfig);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THardcodedStringRule.Create, 'unit U;'#10'interface'#10 +
    'resourcestring'#10'  SFehlt = ''Datei nicht gefunden'';'#10'implementation'#10'end.', cConfig))));
end;

procedure TGeneralRulesTests.HardcodedStringMachineTextSilent;
const
  cConfig = '{ "minConfidence": "low", "rules": { "hardcoded-string": "hint" } }';
  cConfigPick = '{ "minConfidence": "low", "rules": { "hardcoded-string": { "severity": "hint", ' +
    '"ignoreCalls": ["Pick"] } } }';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Protokoll, Prüfungen, Vergleiche, Registry, Masken, Markup und Schriftnamen liest kein Benutzer
  // (Marcos Lauf 06.11.2026).
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THardcodedStringRule.Create, InRoutine(
    '  TAtlasGuard.Log(Format(''Datei nicht gefunden: %s'', [Name]));'#10 +
    '  FLog(''Projekte weggefallen, Prüfung neu'');'#10'  Diagnose(''Starte den Server neu'');'#10 +
    '  Assert(Fertig, ''Liste nicht leer'');'#10'  OutputDebugString(PChar(''Atlas: Protokoll gestört''));'#10 +
    '  if StartsText(''Detailed map of segments'', Zeile) then'#10'    Exit;'#10 +
    '  Farbe := Registry.ReadString(''Background Color New'');'#10 +
    '  Zeit := FormatDateTime(''dd.mm. hh":"nn'', Jetzt);'#10'  B.Append(''<tr class="conflict">'');'#10 +
    '  B.Append(''"summary": {"units": '');'#10'  B.Append(''## Versionen'');'#10 +
    '  Font.Name := ''Segoe UI'';'), cConfig))));
  // Eigene Routinen über ignoreCalls.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THardcodedStringRule.Create, InRoutine(
    '  B.Append(Pick(Englisch, ''## Versions'', ''Die Versionen''));'), cConfig))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THardcodedStringRule.Create, InRoutine(
    '  B.Append(Pick(Englisch, ''## Versions'', ''Die Versionen''));'), cConfigPick))));
  // Text vor einer Maske und ein Text, der mit einem Zitat beginnt, sieht der Benutzer.
  mFindings := TRuleAssert.Findings(THardcodedStringRule.Create, InRoutine(
    '  S := ''Erstellt am '' + FormatDateTime(''dd.mm.yyyy'', Jetzt);'#10 +
    '  raise EFehler.CreateFmt(''"%s" ist keine Formulardatei'', [Name]);'), cConfig);
  Assert.AreEqual(2, Integer(Length(mFindings)));
end;

procedure TGeneralRulesTests.GuidLineFormat;
var
  mLine: string;
begin
  mLine := GuidLine;
  Assert.AreEqual(42, Integer(Length(mLine)));
  Assert.IsTrue(mLine.StartsWith('[''{') and mLine.EndsWith('}'']'), mLine);
  Assert.AreNotEqual(mLine, GuidLine);
end;

procedure TGeneralRulesTests.EmptyFinallyIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  Liste := TStringList.Create;'#10'  try'#10'    Liste.LoadFromFile(Pfad);'#10'  finally'#10 +
    '  end;'#10'  Weiter;');
  mFindings := TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('empty-finally', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Leerer finally-Block; fehlt hier Liste.Free?', mFindings[0].Message);
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('try … finally end entfernen (Rumpf bleibt)', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual(InRoutine('  Liste := TStringList.Create;'#10'  Liste.LoadFromFile(Pfad);'#10'  Weiter;'),
    TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
end;

procedure TGeneralRulesTests.EmptyFinallyFixVariants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Ohne Create davor allgemeine Meldung; fehlendes Semikolon wandert an den Rumpf.
  mSource := InRoutine('  try'#10'    Lesen;'#10#10'    Schreiben'#10'  finally'#10'  end;'#10'  Weiter;');
  mFindings := TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Leerer finally-Block; die Freigabe fehlt oder try … finally ist überflüssig.', mFindings[0].Message);
  Assert.AreEqual(InRoutine('  Lesen;'#10#10'  Schreiben;'#10'  Weiter;'),
    TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
  // Einzige Anweisung eines if mit zwei Anweisungen im Rumpf: begin … end.
  mSource := InRoutine('  if Bereit then'#10'    try'#10'      Lesen;'#10'      Schreiben;'#10'    finally'#10 +
    '    end;');
  mFindings := TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource);
  Assert.AreEqual('try … finally end durch begin … end ersetzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  if Bereit then'#10'    begin'#10'      Lesen;'#10'      Schreiben;'#10'    end;'),
    TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
  // Mit einer Anweisung reicht das Ausrücken.
  mSource := InRoutine('  if Bereit then'#10'    try'#10'      Lesen;'#10'    finally'#10'    end;');
  mFindings := TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource);
  Assert.AreEqual(InRoutine('  if Bereit then'#10'    Lesen;'), TChangeSignature.ApplyEdits(mSource,
    mFindings[0].Fixes[0].Edits));
  // Alles in einer Zeile: Meldung ohne Korrektur.
  mFindings := TRuleAssert.Findings(TEmptyFinallyRule.Create, InRoutine('  try Lesen; finally end;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
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
  mSource: string;
begin
  mSource := InRoutine('  try'#10'    Lesen;'#10'  finally'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource,
    '{"rules": {"empty-finally": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource,
    '{"rules": {"group:style": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyFinallyRule.Create, mSource,
    '{"rules": {"empty-finally": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

function Logger(const AGuid: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  ILogger = interface'#10'    [''' + AGuid + ''']'#10 +
    '    procedure Schreiben;'#10'  end;'#10'implementation'#10'end.';
end;

procedure TGeneralRulesTests.GuidSyntaxIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Logger('{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6}');
  mFindings := TRuleAssert.Findings(TGuidSyntaxInvalidRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('guid-syntax-invalid', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Der letzte Block der GUID hat 11 statt 12 Zeichen (wie E2204).', mFindings[0].Message);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(44, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Neue GUID erzeugen', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreNotEqual(mSource, mFixed);
  TRuleAssert.Silent(TGuidSyntaxInvalidRule.Create, mFixed);
  TRuleAssert.Silent(TGuidSyntaxInvalidRule.Create, Logger('{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C}'));
end;

procedure TGeneralRulesTests.GuidSyntaxProblems;
begin
  Assert.AreEqual('', TGuidSyntaxInvalidRule.Problem('{6a1f3b2c-9d4e-4f5a-8b7c-1d2e3f4a5b6c}'));
  Assert.AreEqual('Der GUID fehlen die geschweiften Klammern',
    TGuidSyntaxInvalidRule.Problem('6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C'));
  Assert.AreEqual('Der GUID fehlt die öffnende geschweifte Klammer',
    TGuidSyntaxInvalidRule.Problem('6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C}'));
  Assert.AreEqual('Der GUID fehlt die schließende geschweifte Klammer',
    TGuidSyntaxInvalidRule.Problem('{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C'));
  Assert.AreEqual('Die GUID hat 4 statt 5 Blöcke',
    TGuidSyntaxInvalidRule.Problem('{6A1F3B2C-9D4E-4F5A-8B7C1D2E3F4A5B6C}'));
  Assert.AreEqual('Der erste Block der GUID hat 7 statt 8 Zeichen',
    TGuidSyntaxInvalidRule.Problem('{6A1F3B2-9D4E-4F5A-8B7C-1D2E3F4A5B6C}'));
  Assert.AreEqual('Der dritte Block der GUID hat 5 statt 4 Zeichen',
    TGuidSyntaxInvalidRule.Problem('{6A1F3B2C-9D4E-4F5AB-8B7C-1D2E3F4A5B6C}'));
  Assert.AreEqual('Die GUID enthält „G“, das ist keine Hexadezimalziffer',
    TGuidSyntaxInvalidRule.Problem('{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6G}'));
  Assert.AreEqual('Der GUID fehlt die schließende geschweifte Klammer', TGuidSyntaxInvalidRule.Problem('{'));
  Assert.AreEqual('Der GUID fehlen die geschweiften Klammern', TGuidSyntaxInvalidRule.Problem(''));
end;

procedure TGeneralRulesTests.GuidSyntaxBracesAndConstants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Nur die Klammern fehlen: sichere Korrektur zuerst; Vorfahr in Klammern; typisierte Konstante.
  mSource := 'unit U;'#10'interface'#10'type'#10'  ILogger = interface(IInterface)'#10 +
    '    [''6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C'']'#10'  end;'#10'const'#10 +
    '  IID_Logger: TGUID = ''{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6X}'';'#10'implementation'#10'end.';
  mFindings := TRuleAssert.Findings(TGuidSyntaxInvalidRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Der GUID fehlen die geschweiften Klammern (wie E2204).', mFindings[0].Message);
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Geschweifte Klammern ergänzen', mFindings[0].Fixes[0].Title);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  Assert.IsTrue(TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits).Contains(
    '[''{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C}'']'));
  Assert.AreEqual('Die GUID enthält „X“, das ist keine Hexadezimalziffer (wie E2204).', mFindings[1].Message);
  Assert.AreEqual(7, mFindings[1].Range.StartPos.Line);
end;

procedure TGeneralRulesTests.GuidSyntaxSilentCases;
begin
  // Gültige GUID, Konstante als GUID, Verkettung, string-Konstante, Attribut mit Text.
  TRuleAssert.Silent(TGuidSyntaxInvalidRule.Create, 'unit U;'#10'interface'#10'const'#10 +
    '  Kennung = ''{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C}'';'#10'  Text: string = ''kein GUID'';'#10 +
    '  Teil: TGUID = ''{6A1F3B2C-9D4E-4F5A-'' + ''8B7C-1D2E3F4A5B6C}'';'#10'type'#10'  IA = interface'#10 +
    '    [Kennung]'#10'  end;'#10'  IB = interface'#10'    [''{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6D}'']'#10 +
    '  end;'#10'  IC = interface;'#10'  [Beschreibung(''kurz'')]'#10'  TKlasse = class'#10'  end;'#10 +
    'implementation'#10'end.');
end;

procedure TGeneralRulesTests.GuidSyntaxOffAndExclude;
var
  mSource: string;
begin
  mSource := Logger('{6A1F3B2C}');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGuidSyntaxInvalidRule.Create, mSource,
    '{"rules": {"guid-syntax-invalid": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGuidSyntaxInvalidRule.Create, mSource,
    '{"rules": {"guid-syntax-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TGeneralRulesTests);

end.
