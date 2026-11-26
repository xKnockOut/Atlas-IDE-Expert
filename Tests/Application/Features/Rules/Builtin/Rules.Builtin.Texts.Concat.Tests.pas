unit Rules.Builtin.Texts.Concat.Tests;

// Tests der Regel text-concat-without-space (#3042): Beispiel aus dem Issue mit Korrektur, Nähte (Satzzeichen,
// Ziffern, Ketten, Klammern, SQL), Fälle ohne Meldung (Leerzeichen, Trenner dazwischen, Bezeichner, Unit-Namen,
// Pfade, URLs, Format-Platzhalter, maschinelle Umbrüche), Option wrapLength, Stufe 2 mit Ausdrücken an der Naht
// (Option expressions, niedrige Konfidenz), Abschalten und Anmeldung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextConcatRuleTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure ReportedSeams;
    [Test]
    procedure SilentSeams;
    [Test]
    procedure WrappedLongTexts;
    [Test]
    procedure ExpressionsOffByDefault;
    [Test]
    procedure ExpressionsAtSeam;
    [Test]
    procedure SeamHelpers;
    [Test]
    procedure SwitchedOff;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Rules.Contract,
  Rules.Builtin,
  Rules.Builtin.Texts.Concat,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Findings.Contract;

const
  cExpressions = '{"minConfidence": "low", "rules": {"text-concat-without-space": {"expressions": true}}}';

/// <summary>Unit mit einer Routine, deren erste Anweisung in Zeile 7 (ab 0) steht.</summary>
function Body(const AStatements: string): string;
begin
  Result := 'unit Texte;'#10'interface'#10'implementation'#10'procedure Zeigen(const Name: string; N: Integer);'#10 +
    'var'#10'  S: string;'#10'begin'#10 + AStatements + #10'end;'#10'end.';
end;

function Found(const AStatements, AConfig: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TTextConcatWithoutSpaceRule.Create, Body(AStatements), AConfig);
end;

function Count(const AStatements: string): Integer; overload;
begin
  Result := Length(Found(AStatements, ''));
end;

function Count(const AStatements, AConfig: string): Integer; overload;
begin
  Result := Length(Found(AStatements, AConfig));
end;

{ TTextConcatRuleTests }

procedure TTextConcatRuleTests.IssueExample;
var
  mFindings: TArray<TRuleFinding>;
  mEdit: TTextEdit;
begin
  mFindings := Found('  S := ''Bli Bla Blubb'' + ''Bla Bla Bla'';', '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cTextConcatWithoutSpaceRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Text ohne Leerzeichen zusammengesetzt: ''Blubb'' + ''Bla'' ergibt ''BlubbBla''.',
    mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(38, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Leerzeichen am Ende des Textes einfügen', mFindings[0].Fixes[0].Title);
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
  mEdit := mFindings[0].Fixes[0].Edits[0];
  Assert.AreEqual(' ', mEdit.NewText);
  // Vor dem schließenden Hochkomma von 'Bli Bla Blubb' (Spalte 7 bis 22).
  Assert.AreEqual(7, mEdit.Range.StartPos.Line);
  Assert.AreEqual(21, mEdit.Range.StartPos.Character);
  Assert.AreEqual(21, mEdit.Range.EndPos.Character);
  // Korrigierte Form
  Assert.AreEqual(0, Count('  S := ''Bli Bla Blubb '' + ''Bla Bla Bla'';'));
end;

procedure TTextConcatRuleTests.ReportedSeams;
begin
  Assert.AreEqual(1, Count('  S := ''Fehler:'' + ''Datei fehlt'';'), 'Doppelpunkt vor Großbuchstaben');
  Assert.AreEqual(1, Count('  S := ''Seite eins,'' + ''Seite zwei'';'), 'Komma vor Großbuchstaben');
  Assert.AreEqual(1, Count('  S := ''Fertig!'' + ''Weiter geht es'';'), 'Ausrufezeichen');
  Assert.AreEqual(1, Count('  S := ''Anzahl 3'' + ''4 Teile'';'), 'Ziffern');
  Assert.AreEqual(1, Count('  S := ''Eins zwei'' + ''drei'' + '' vier'';'), 'nur die erste Naht der Kette');
  Assert.AreEqual(1, Count('  S := (''Hallo du'') + ''Welt'';'), 'Klammern');
  Assert.AreEqual(1, Count('  S := ''Hallo du'' + (''Welt'' + '' da'');'), 'Klammer rechts');
  Assert.AreEqual(1, Count('  S := ''SELECT a FROM t'' + ''WHERE x = 1'';'), 'SQL ist nicht ausgenommen');
  Assert.AreEqual(1, Count('  S := ''Die Datei wurde'' +'#10'    ''gelöscht'';'), 'Umbruch über Zeilen');
  Assert.AreEqual(1, Count('  ShowMessage(''Bli Bla Blubb'' + ''Bla'');'), 'Argument');
  Assert.AreEqual(2, Count('  S := ''Eins zwei'' + ''Drei vier'' + ''Fünf'';'), 'zwei Nähte');
end;

procedure TTextConcatRuleTests.SilentSeams;
begin
  Assert.AreEqual(0, Count('  S := ''Bli Bla'' + '' Blubb'';'), 'Leerzeichen rechts');
  Assert.AreEqual(0, Count('  S := ''Zeile eins'' + sLineBreak + ''Zeile zwei'';'), 'sLineBreak');
  Assert.AreEqual(0, Count('  S := ''Zeile eins'' + #13#10 + ''Zeile zwei'';'), '#13#10');
  Assert.AreEqual(0, Count('  S := ''Zeile eins''#13#10 + ''Zeile zwei'';'), '#13#10 im Literal');
  Assert.AreEqual(0, Count('  S := ''Zeile eins'' + '' '' + ''Zeile zwei'';'), 'Leerzeichen dazwischen');
  Assert.AreEqual(0, Count('  S := ''Wert ist,'' + ''aber klein'';'), 'Komma vor Kleinbuchstaben');
  Assert.AreEqual(0, Count('  S := ''Atlas'' + ''Server'';'), 'Bezeichner ohne Leerzeichen');
  Assert.AreEqual(0, Count('  S := ''Donaudampf'' + ''schifffahrt'';'), 'ein Wort');
  Assert.AreEqual(0, Count('  S := ''Unit System.'' + ''SysUtils fehlt'';'), 'Unit-Name mit Punkt');
  Assert.AreEqual(0, Count('  S := ''Datei C:\Daten'' + ''Export fehlt'';'), 'Pfad');
  Assert.AreEqual(0, Count('  S := ''Siehe https://x.de/a'' + ''b bitte'';'), 'URL');
  Assert.AreEqual(0, Count('  S := ''Name ist Kunde_'' + ''Nummer hier'';'), 'Bezeichner mit _');
  Assert.AreEqual(0, Count('  S := ''<b>Fett'' + ''Text</b> hier'';'), 'Markup');
  Assert.AreEqual(0, Count('  S := ''Fehler (%s).%s'' + ''Für diese Verbindung'';'), 'Format-Platzhalter');
  Assert.AreEqual(0, Count('  S := ''Wert %0:d'' + ''Teile da'';'), 'Platzhalter mit Index');
  Assert.AreEqual(0, Count('  S := ''1'' + ''2'';'), 'Zahlen');
  Assert.AreEqual(0, Count('  N := 1 + 2;'), 'kein Text');
end;

procedure TTextConcatRuleTests.WrappedLongTexts;
var
  mLong: string;
begin
  // 130 Zeichen: maschinell umbrochen, mitten im Wort.
  mLong := StringOfChar(Char('a'), 60) + ' ' + StringOfChar(Char('b'), 69);
  Assert.AreEqual(0, Count('  S := ''' + mLong + ''' + ''weiter geht es'';'));
  Assert.AreEqual(1, Count('  S := ''' + mLong + ''' + ''weiter geht es'';',
    '{"rules": {"text-concat-without-space": {"wrapLength": 200}}}'));
  Assert.AreEqual(1, Count('  S := ''' + mLong + ''' + ''weiter geht es'';',
    '{"rules": {"text-concat-without-space": {"wrapLength": 0}}}'), '0 schaltet die Ausnahme ab');
  mLong := '';
end;

procedure TTextConcatRuleTests.ExpressionsOffByDefault;
begin
  Assert.AreEqual(0, Count('  S := ''Fehler beim Laden von'' + Name;', '{"minConfidence": "low"}'));
  Assert.AreEqual(0, Count('  S := Name + ''wurde gelöscht'';', '{"minConfidence": "low"}'));
end;

procedure TTextConcatRuleTests.ExpressionsAtSeam;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Found('  S := ''Fehler beim Laden von'' + Name;', cExpressions);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Kein Leerzeichen zwischen ''von'' und Name.', mFindings[0].Message);
  Assert.AreEqual('Leerzeichen am Ende des Textes einfügen', mFindings[0].Fixes[0].Title);
  // Ausdruck links: Leerzeichen an den Anfang des rechten Literals.
  mFindings := Found('  S := Name + ''wurde gelöscht'';', cExpressions);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kein Leerzeichen zwischen Name und ''wurde''.', mFindings[0].Message);
  Assert.AreEqual('Leerzeichen am Anfang des Textes einfügen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(15, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(1, Count('  S := ''Datei'' + Name + ''wurde gelöscht'';', cExpressions),
    'nur die Naht rechts: ''Datei'' allein sieht nicht nach Text aus');
  Assert.AreEqual(1, Count('  S := ''Anzahl der Teile'' + IntToStr(N);', cExpressions));
  Assert.AreEqual(0, Count('  S := ''Die Datei '' + Name + '' fehlt'';', cExpressions), 'Leerzeichen');
  Assert.AreEqual(0, Count('  S := ''T'' + Name;', cExpressions), 'Präfix ohne Text');
  Assert.AreEqual(0, Count('  S := ''Zeile eins'' + sLineBreak;', cExpressions), 'Trenner');
  Assert.AreEqual(0, Count('  S := ''Wert ist'' + QuotedStr(Name);', cExpressions), 'Rahmen');
  Assert.AreEqual(0, Count('  S := ''Ordner ist C:\Daten'' + Name;', cExpressions), 'Pfad');
  Assert.AreEqual(0, Count('  S := ''Wert ist %s'' + Name;', cExpressions), 'Platzhalter');
  mFindings := nil;
end;

procedure TTextConcatRuleTests.SeamHelpers;
begin
  Assert.IsTrue(TTextConcatWithoutSpaceRule.MissingSpace('Blubb', 'Bla'));
  Assert.IsTrue(TTextConcatWithoutSpaceRule.MissingSpace('Fehler:', 'Datei'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('Fehler:', 'datei'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('Satz.', 'Neu'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('Blubb ', 'Bla'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('Blubb', ' Bla'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('Wert %s', 'Bla'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('', 'Bla'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.MissingSpace('Bla', ''));
  Assert.IsTrue(TTextConcatWithoutSpaceRule.SeamIsTechnical('Ordner C:\Daten', 'Export'));
  Assert.IsTrue(TTextConcatWithoutSpaceRule.SeamIsTechnical('Mail an a', '@b.de'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.SeamIsTechnical('Ordner C:\Daten ist', 'Export'));
  Assert.IsFalse(TTextConcatWithoutSpaceRule.SeamIsTechnical('Bli Bla Blubb', 'Bla'));
end;

procedure TTextConcatRuleTests.SwitchedOff;
const
  cStatement = '  S := ''Bli Bla Blubb'' + ''Bla Bla Bla'';';
begin
  Assert.AreEqual(0, Count(cStatement, '{"rules": {"text-concat-without-space": "off"}}'));
  Assert.AreEqual(0, Count(cStatement, '{"rules": {"group:find-bugs": "off"}}'));
end;

procedure TTextConcatRuleTests.RuleIsRegistered;
var
  mRule: IRule;
  mIds: string;
begin
  mIds := '';
  for mRule in BuiltinRules do
  begin
    mIds := mIds + ' ' + mRule.Descriptor.Id + ' ';
  end;
  Assert.IsTrue(Pos(' ' + cTextConcatWithoutSpaceRuleId + ' ', mIds) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextConcatRuleTests);

end.
