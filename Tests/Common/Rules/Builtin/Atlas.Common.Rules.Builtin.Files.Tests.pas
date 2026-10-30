unit Atlas.Common.Rules.Builtin.Files.Tests;

// Tests der Dateipfad-Regeln:
// path-concat-without-delimiter (#968): Beispiel aus dem Issue mit Korrektur,
// direkte Aufrufe, lokale Variablen, Bezeichner als Name, Ketten, Fälle
// ohne Meldung (ExtractFilePath, Trennzeichen, Endung, Meldungstext, andere
// Werte, var-Parameter), Abschalten und Ausnahmen.
// hardcoded-path (#969): Beispiel aus dem Issue, Laufwerk, UNC, Schrägstrich,
// Fälle ohne Meldung (Wurzel, \\?\, relative Pfade, Meldungstexte),
// Test-Units, allowUnits, Abschalten und falscher Optionstyp.
// filename-compare-case (#970): Beispiel aus dem Issue mit Korrektur, <>,
// TPath, FileName-Eigenschaften, ExeName, uses-Ergänzung, Fälle ohne Meldung
// (Leertext, Literal ohne Buchstaben, SameFileName, ExtractFileDir(X) = X),
// Abschalten; plattformabhängiger Vergleich mit SameText in derselben
// Anweisung und Test-Units bleiben still.

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
    procedure HardcodedPathIssueExample;
    [Test]
    procedure HardcodedPathKinds;
    [Test]
    procedure HardcodedPathAllowedUnitsAndTests;
    [Test]
    procedure FilenameCompareIssueExample;
    [Test]
    procedure FilenameCompareVariants;
    [Test]
    procedure FilenameCompareSilentCases;
    [Test]
    procedure FilenameComparePlatformDependent;
    [Test]
    procedure FilenameCompareTestUnits;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
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

function UnitWith(const AStatement: string): string;
begin
  Result := 'unit Protokoll;'#10'interface'#10'implementation'#10'procedure Sichern(Protokoll: TStrings);'#10 +
    'begin'#10 + AStatement + #10'end;'#10'end.';
end;

function HardcodedCount(const ASource, AConfig: string): Integer; overload;
begin
  Result := Length(TRuleAssert.Findings(THardcodedPathRule.Create, ASource, AConfig));
end;

function HardcodedCount(const ASource: string): Integer; overload;
begin
  Result := HardcodedCount(ASource, '');
end;

procedure TFileRulesTests.HardcodedPathIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(THardcodedPathRule.Create,
    UnitWith('  Protokoll.SaveToFile(''C:\Users\marco\Desktop\log.txt'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(HardcodedPathRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Fester Benutzerpfad; auf anderen Rechnern gibt es ihn nicht.', Findings[0].Message);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(23, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Korrigierte Form und naheliegender Negativfall
  Assert.AreEqual(0, HardcodedCount(UnitWith(
    '  Protokoll.SaveToFile(TPath.Combine(TPath.GetDocumentsPath, ''log.txt''));')));
  Assert.AreEqual(0, HardcodedCount(UnitWith('  Protokoll.SaveToFile(''Logs\log.txt'');')));
end;

procedure TFileRulesTests.HardcodedPathKinds;
begin
  Assert.AreEqual(Ord(THardcodedPathKind.Drive), Ord(THardcodedPathRule.PathKind('D:\Daten\Kunden.db')));
  Assert.AreEqual(Ord(THardcodedPathKind.Drive), Ord(THardcodedPathRule.PathKind('c:/Programme/Tool.exe')));
  Assert.AreEqual(Ord(THardcodedPathKind.UserFolder), Ord(THardcodedPathRule.PathKind('C:\users\Public\x.txt')));
  Assert.AreEqual(Ord(THardcodedPathKind.UserFolder),
    Ord(THardcodedPathRule.PathKind('C:\Documents and Settings\marco\x')));
  Assert.AreEqual(Ord(THardcodedPathKind.Drive), Ord(THardcodedPathRule.PathKind('C:\Users')));
  Assert.AreEqual(Ord(THardcodedPathKind.Network), Ord(THardcodedPathRule.PathKind('\\server\Freigabe\x.csv')));
  // Kein fester Pfad
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('C:\')));
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('\\?\')));
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('\\.\COM3')));
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('\\server')));
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('Daten\x.txt')));
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('Pfad: C:\Daten')));
  Assert.AreEqual(Ord(THardcodedPathKind.None), Ord(THardcodedPathRule.PathKind('C:Daten')));
  // Meldungen je Art; Kommentare bleiben still.
  Assert.AreEqual(1, HardcodedCount(UnitWith('  Protokoll.SaveToFile(''D:\Daten\log.txt''); // C:\Alt')));
  Assert.AreEqual('Fester Netzwerkpfad; auf anderen Rechnern und ohne Netzwerk fehlt er womöglich.',
    TRuleAssert.Findings(THardcodedPathRule.Create,
    UnitWith('  Protokoll.SaveToFile(''\\nas\Logs\log.txt'');'))[0].Message);
  Assert.AreEqual('Fester Dateipfad; auf anderen Rechnern fehlt er womöglich.',
    TRuleAssert.Findings(THardcodedPathRule.Create,
    UnitWith('  Protokoll.SaveToFile(''D:\Daten\log.txt'');'))[0].Message);
end;

procedure TFileRulesTests.HardcodedPathAllowedUnitsAndTests;
const
  Constants = 'unit App.Pfade;'#10'interface'#10'const'#10'  Standardordner = ''C:\ProgramData\Atlas'';'#10 +
    'implementation'#10'end.';
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(1, HardcodedCount(Constants));
  Assert.AreEqual(0, HardcodedCount(Constants, '{"rules": {"hardcoded-path": {"allowUnits": ["app.pfade"]}}}'));
  Assert.AreEqual(0, HardcodedCount(Constants, '{"rules": {"hardcoded-path": {"allowUnits": ["App.*"]}}}'));
  Assert.AreEqual(1, HardcodedCount(Constants, '{"rules": {"hardcoded-path": {"allowUnits": ["App.Andere"]}}}'));
  Assert.AreEqual(0, HardcodedCount(Constants, '{"rules": {"hardcoded-path": "off"}}'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THardcodedPathRule.Create, Constants,
    '{"rules": {"hardcoded-path": {"exclude": ["Source/*.pas"]}}}', 'Source/App.Pfade.pas'))));
  // Test-Units bleiben still.
  Assert.AreEqual(0, HardcodedCount('unit Pfade.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10 +
    'implementation'#10'const'#10'  Probe = ''C:\Temp\probe.txt'';'#10'end.'));
  TConfigurationParser.Parse('{"rules": {"hardcoded-path": {"allowUnits": "App.Pfade"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

function CompareUnit(const ACondition: string): string;
begin
  Result := 'unit Dateien;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'procedure Laden(const Datei: string);'#10'begin'#10'  if ' + ACondition + ' then'#10'    Exit;'#10'end;'#10'end.';
end;

function CompareFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TFilenameCompareCaseRule.Create, ASource);
end;

function CompareCount(const ACondition: string): Integer;
begin
  Result := Length(CompareFindings(CompareUnit(ACondition)));
end;

procedure TFileRulesTests.FilenameCompareIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := CompareFindings(CompareUnit('ExtractFileName(Datei) = ''Config.ini'''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(FilenameCompareCaseRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('Dateinamen unterscheiden unter Windows nicht nach Groß-/Kleinschreibung; SameFileName ' +
    'vergleicht richtig.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('SameFileName verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual('SameFileName(ExtractFileName(Datei), ''Config.ini'')', Findings[0].Fixes[0].Edits[0].NewText);
  // Korrigierte Form und naheliegender Negativfall
  Assert.AreEqual(0, CompareCount('SameFileName(ExtractFileName(Datei), ''Config.ini'')'));
  Assert.AreEqual(0, CompareCount('ExtractFileName(Datei) = '''''));
end;

procedure TFileRulesTests.FilenameCompareVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := CompareFindings(CompareUnit('ExtractFileExt(Datei) <> ''.pas'''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('not SameFileName(ExtractFileExt(Datei), ''.pas'')', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(1, CompareCount('TPath.GetFileName(Datei) = Name'));
  Assert.AreEqual(1, CompareCount('OpenDialog.FileName = SaveDialog.FileName'));
  Assert.AreEqual(1, CompareCount('Application.ExeName = Datei'));
  Assert.AreEqual(1, CompareCount('AFileName = FLetzteDatei'));
  Assert.AreEqual(1, CompareCount('(ExpandFileName(Datei)) = ExpandFileName(Alt)'));
  // Ohne System.SysUtils trägt die Korrektur die Unit ein.
  Findings := CompareFindings('unit Dateien;'#10'interface'#10'implementation'#10'uses'#10'  System.Classes;'#10 +
    'function Gleich(Liste: TStrings): Boolean;'#10'begin'#10'  Result := Liste.FileName = ''a.txt'';'#10'end;'#10 +
    'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes[0].Edits)));
end;

procedure TFileRulesTests.FilenameCompareSilentCases;
begin
  Assert.AreEqual(0, CompareCount('ExtractFileExt(Datei) = '''''));
  Assert.AreEqual(0, CompareCount('OpenDialog.FileName <> '''''));
  Assert.AreEqual(0, CompareCount('ExtractFilePath(Datei) = ''\'''));
  Assert.AreEqual(0, CompareCount('ExtractFileDir(Datei) = Datei'));
  Assert.AreEqual(0, CompareCount('Datei = ExtractFileDir(Datei)'));
  Assert.AreEqual(0, CompareCount('SameText(ExtractFileExt(Datei), ''.pas'')'));
  Assert.AreEqual(0, CompareCount('Name = ''Config.ini'''));
  Assert.AreEqual(0, CompareCount('Length(ExtractFileName(Datei)) = 3'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFilenameCompareCaseRule.Create,
    CompareUnit('ExtractFileName(Datei) = ''Config.ini'''), '{"rules": {"filename-compare-case": "off"}}'))));
end;

function StatementUnit(const AStatement: string): string;
begin
  Result := 'unit Dateien;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'function Gleich(const Root, FileName: string): Boolean;'#10'var'#10'  I: Integer;'#10'begin'#10'  Result := False;'#10 +
    AStatement + #10'end;'#10'end.';
end;

function StatementCount(const AStatement: string): Integer;
begin
  Result := Length(CompareFindings(StatementUnit(AStatement)));
end;

procedure TFileRulesTests.FilenameComparePlatformDependent;
begin
  // Atlas.Core.Vcs.Internals.Text: unter Windows SameText, sonst genau.
  Assert.AreEqual(0, StatementCount('  if (Root <> '''') and ((PathDelim = ''\'') and SameText(Root, FileName) or ' +
    '(Root = FileName)) then'#10'    Exit(True);'));
  Assert.AreEqual(0, StatementCount('  Result := ((PathDelim = ''\'') and AnsiSameText(FileName, Root)) or ' +
    '(FileName = Root);'));
  Assert.AreEqual(0, StatementCount('  Result := (PathDelim = ''\'') and (CompareText(Root, FileName) = 0) or ' +
    '(Root = FileName);'));
  Assert.AreEqual(0, StatementCount('  if PathDelim = ''\'' then'#10'    Result := SameFileName(Root, FileName)'#10 +
    '  else'#10'    Result := Root = FileName;'));
  Assert.AreEqual(0, StatementCount('  if PathDelim = ''\'' then'#10'  begin'#10 +
    '    Result := System.SysUtils.SameText((Root), FileName);'#10'  end'#10'  else'#10'  begin'#10 +
    '    Result := Root = FileName;'#10'  end;'));
  // Andere Seiten, andere Anweisung oder eigene Funktion gleichen Namens: weiter melden.
  Assert.AreEqual(1, StatementCount('  Result := SameText(Root, ''x'') or (Root = FileName);'));
  Assert.AreEqual(1, StatementCount('  Result := SameText(Root, FileName);'#10'  Result := Root = FileName;'));
  Assert.AreEqual(1, StatementCount('  for I := 0 to 1 do'#10'    if SameText(Root, FileName) then'#10 +
    '      Exit;'#10'  for I := 0 to 1 do'#10'    Result := Root = FileName;'));
  Assert.AreEqual(1, StatementCount('  Result := Helfer.SameText(Root, FileName) or (Root = FileName);'));
end;

procedure TFileRulesTests.FilenameCompareTestUnits;
const
  Body = 'implementation'#10'function Gibt(const AFileName: string): Boolean;'#10'begin'#10 +
    '  Result := (AFileName = ''A.dfm'') or (AFileName = ''C.fmx'');'#10'end;'#10'end.';
begin
  // Testdoubles vergleichen mit selbst vergebenen Namen.
  Assert.AreEqual(0, Integer(Length(CompareFindings('unit Doubles.Tests;'#10'interface'#10'uses'#10 +
    '  DUnitX.TestFramework;'#10 + Body))));
  Assert.AreEqual(2, Integer(Length(CompareFindings('unit Doubles;'#10'interface'#10'uses'#10 +
    '  System.SysUtils;'#10 + Body))));
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
  Assert.IsTrue(Pos(' ' + HardcodedPathRuleId, Ids) > 0);
  Assert.IsTrue(Pos(' ' + FilenameCompareCaseRuleId, Ids) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TFileRulesTests);

end.
