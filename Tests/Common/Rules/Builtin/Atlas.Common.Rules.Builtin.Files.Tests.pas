unit Atlas.Common.Rules.Builtin.Files.Tests;

// Tests der Dateipfad-Regeln:
// path-concat-without-delimiter (#968): Beispiel aus dem Issue mit Korrektur,
// direkte Aufrufe, lokale Variablen, Bezeichner als Name, Ketten, Fälle
// ohne Meldung (ExtractFilePath, Trennzeichen, Endung, Meldungstext, andere
// Werte, var-Parameter), Abschalten und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileRulesTests = class
  public
    [Test]
    procedure PathConcatIssueExample;
    [Test]
    procedure PathConcatDirectCalls;
    [Test]
    procedure PathConcatVariables;
    [Test]
    procedure PathConcatSilentCases;
    [Test]
    procedure PathConcatOptions;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Files,
  Atlas.Tests.RuleAssert;

function Body(const AStatements: string): string;
begin
  Result := 'unit Pfade;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils, System.IOUtils;'#10 +
    'procedure Speichern(const Datei, Name: string);'#10'var'#10'  Ordner, Ziel: string;'#10'begin'#10 + AStatements +
    'end;'#10'end.';
end;

function PathFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TPathConcatWithoutDelimiterRule.Create, ASource);
end;

function PathCount(const ASource: string): Integer;
begin
  Result := Length(PathFindings(ASource));
end;

{ TFileRulesTests }

procedure TFileRulesTests.PathConcatIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := PathFindings(Body('  Ordner := TPath.GetDocumentsPath;'#10'  Ziel := Ordner + ''export.csv'';'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(PathConcatWithoutDelimiterRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Ordner kommt aus GetDocumentsPath und hat keinen abschließenden Backslash; das Ergebnis ist ' +
    '…\Documentsexport.csv.', Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(31, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('TPath.Combine verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'System.IOUtils ist schon eingebunden');
  Assert.AreEqual('TPath.Combine(Ordner, ''export.csv'')', Findings[0].Fixes[0].Edits[0].NewText);
  // Korrigierte Form und naheliegender Negativfall
  Assert.AreEqual(0, PathCount(Body('  Ordner := TPath.GetDocumentsPath;'#10 +
    '  Ziel := TPath.Combine(Ordner, ''export.csv'');'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ordner := ExtractFilePath(Datei);'#10'  Ziel := Ordner + ''export.csv'';'#10)));
end;

procedure TFileRulesTests.PathConcatDirectCalls;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := PathFindings(Body('  Ziel := ExtractFileDir(Datei) + ''alt.bak'';'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('ExtractFileDir liefert keinen abschließenden Backslash; das Ergebnis ist …\Ordneralt.bak.',
    Findings[0].Message);
  Assert.AreEqual('TPath.Combine(ExtractFileDir(Datei), ''alt.bak'')', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(1, PathCount(Body('  Ziel := ExcludeTrailingPathDelimiter(Datei) + ''x.txt'';'#10)));
  Assert.AreEqual(1, PathCount(Body('  Ziel := GetCurrentDir + ''log.txt'';'#10)));
  Assert.AreEqual(1, PathCount(Body('  Ziel := System.SysUtils.GetCurrentDir + ''log.txt'';'#10)));
  Assert.AreEqual(1, PathCount(Body('  Ziel := TDirectory.GetCurrentDirectory + ''log.txt'';'#10)));
  Assert.AreEqual(1, PathCount(Body('  Ziel := TPath.GetDirectoryName(Datei) + ''log.txt'';'#10)));
  // Bezeichner als Name: mittlere Konfidenz
  Findings := PathFindings(Body('  Ziel := ExtractFileDir(Datei) + Name;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('ExtractFileDir liefert keinen abschließenden Backslash; Name wird ohne Trennzeichen angehängt.',
    Findings[0].Message);
  // In einer Kette: Ordner + Name + Endung meldet einmal; Präfix + Ordner + Name ohne Korrektur.
  Findings := PathFindings(Body('  Ziel := ExtractFileDir(Datei) + Name + ''.txt'';'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Findings := PathFindings(Body('  Ziel := ''\\?\'' + ExtractFileDir(Datei) + ''log.txt'';'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TFileRulesTests.PathConcatVariables;
var
  Findings: TArray<TRuleFinding>;
begin
  // Inline-Variable, Ordner wird nur gelesen (ForceDirectories)
  Assert.AreEqual(1, PathCount(Body('  var Basis := TPath.GetHomePath;'#10'  ForceDirectories(Basis);'#10 +
    '  Ziel := Basis + ''Atlas'';'#10)));
  // Ohne System.IOUtils ergänzt die Korrektur die uses.
  Findings := PathFindings('unit Pfade;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'function Ziel(const Datei: string): string;'#10'begin'#10'  Result := ExtractFileDir(Datei) + ''x.txt'';'#10 +
    'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual(',' + sLineBreak + '  System.IOUtils', StringReplace(Findings[0].Fixes[0].Edits[1].NewText, #10,
    sLineBreak, []));
end;

procedure TFileRulesTests.PathConcatSilentCases;
begin
  // Ordner mit Trennzeichen
  Assert.AreEqual(0, PathCount(Body('  Ziel := ExtractFilePath(Datei) + ''x.txt'';'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := IncludeTrailingPathDelimiter(ExtractFileDir(Datei)) + ''x.txt'';'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := TPath.GetTempPath + ''x.txt'';'#10)));
  // Trennzeichen, Endung, Meldungstext
  Assert.AreEqual(0, PathCount(Body('  Ziel := ExtractFileDir(Datei) + PathDelim + Name;'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := ExtractFileDir(Datei) + ''\x.txt'';'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := ExtractFileDir(Datei) + ''.bak'';'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := ExtractFileDir(Datei) + '' fehlt'';'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := ExtractFileDir(Datei) + ExtractFileExt(Datei);'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ziel := ''Ordner: '' + ExtractFileDir(Datei);'#10)));
  // Variable mit anderen oder unbekannten Werten
  Assert.AreEqual(0, PathCount(Body('  Ordner := TPath.GetDocumentsPath;'#10'  if Name <> '''' then'#10 +
    '    Ordner := IncludeTrailingPathDelimiter(Ordner);'#10'  Ziel := Ordner + ''export.csv'';'#10)));
  Assert.AreEqual(0, PathCount(Body('  Ordner := TPath.GetDocumentsPath;'#10'  Anpassen(Ordner);'#10 +
    '  Ziel := Ordner + ''export.csv'';'#10)));
  // Kein lokaler Name (Feld, Parameter)
  Assert.AreEqual(0, PathCount(Body('  Ziel := Datei + ''export.csv'';'#10)));
end;

procedure TFileRulesTests.PathConcatOptions;
var
  Source: string;
begin
  Source := Body('  Ziel := ExtractFileDir(Datei) + ''x.txt'';'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPathConcatWithoutDelimiterRule.Create, Source,
    '{"rules": {"path-concat-without-delimiter": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPathConcatWithoutDelimiterRule.Create, Source,
    '{"rules": {"group:robustness": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPathConcatWithoutDelimiterRule.Create, Source,
    '{"rules": {"path-concat-without-delimiter": {"exclude": ["Source/*.pas"]}}}', 'Source/Pfade.pas'))));
end;

procedure TFileRulesTests.RulesAreRegistered;
var
  Rule: IRule;
  Ids: string;
begin
  Ids := '';
  for Rule in BuiltinRules do
    Ids := Ids + ' ' + Rule.Descriptor.Id;
  Assert.IsTrue(Pos(' ' + PathConcatWithoutDelimiterRuleId, Ids) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TFileRulesTests);

end.
