unit Atlas.Common.Rules.Builtin.Database.Tests;

// Tests der Regel sql-write-without-where (#966): Beispiel aus dem Issue,
// UPDATE, SQL.Add, CommandText, ExecSQL, Konstanten und lokale Werte, Format
// mit dynamischer Tabelle, Formulardatei; still mit WHERE, JOIN, TOP, LIMIT,
// unbekannten Teilen hinter der Tabelle, weitergegebenem Empfänger, Ergänzung
// in anderer Routine und Meldungstexten; Option allowTables, Abschalten,
// Ausnahmen und falscher Optionstyp.
// sql-select-star (#967): Beispiel aus dem Issue, Zerlegung (DISTINCT, TOP,
// FIRST/SKIP, Alias.*, Unterabfrage, EXISTS, COUNT(*), Meldungstexte),
// zusammengesetzte Texte, Korrektur aus den persistenten Feldern der
// Formulardatei, SQL der Formulardatei, Standard aus, Abschalten und Ausnahmen.
// lsp-ignore-file: sql-write-without-where -- die SQL-Texte sind Prüffälle der Regel

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDatabaseRulesTests = class
  public
    [Test]
    procedure SqlWriteIssueExample;
    [Test]
    procedure SqlWriteAnalysis;
    [Test]
    procedure SqlWriteVariants;
    [Test]
    procedure SqlWriteNamedValues;
    [Test]
    procedure SqlWriteSilentCases;
    [Test]
    procedure SqlWriteReceiverChangedElsewhere;
    [Test]
    procedure SqlWriteFormFile;
    [Test]
    procedure SqlWriteOptions;
    [Test]
    procedure SelectStarIssueExample;
    [Test]
    procedure SelectStarAnalysis;
    [Test]
    procedure SelectStarSources;
    [Test]
    procedure SelectStarFixFromPersistentFields;
    [Test]
    procedure SelectStarFormFile;
    [Test]
    procedure SelectStarOptions;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Database,
  Atlas.Tests.RuleAssert;

function Body(const AStatements: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'implementation'#10'procedure Leeren(qry: TFDQuery; Id: Integer);'#10 +
    'var'#10'  S: string;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

function Count(const ASource: string): Integer; overload;
begin
  Result := Length(TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create, ASource));
end;

function Count(const ASource, AConfig: string): Integer; overload;
begin
  Result := Length(TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create, ASource, AConfig));
end;

function FirstMessage(const ASource: string): string;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create, ASource);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Result := Findings[0].Message;
end;

const
  StarOn = '{"rules": {"sql-select-star": "hint"}}';

function StarFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TSqlSelectStarRule.Create, ASource, StarOn);
end;

function StarCount(const ASource: string): Integer;
begin
  Result := Length(StarFindings(ASource));
end;

function StarsIn(const ASql: string): Integer;
begin
  Result := Length(TSqlSelectStarRule.Stars(ASql, False));
end;

{ TDatabaseRulesTests }

procedure TDatabaseRulesTests.SqlWriteIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create,
    Body('  qry.SQL.Text := ''DELETE FROM Warenkorb'';'#10'  qry.ExecSQL;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(SqlWriteWithoutWhereRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('DELETE ohne WHERE löscht alle Zeilen von Warenkorb.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(18, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Korrigierte Form und naheliegender Negativfall
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''DELETE FROM Warenkorb WHERE Kunde = :Kunde'';'#10 +
    '  qry.ExecSQL;'#10)));
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''SELECT * FROM Warenkorb'';'#10'  qry.Open;'#10)));
end;

procedure TDatabaseRulesTests.SqlWriteAnalysis;
var
  Writes: TArray<TSqlWrite>;
begin
  Writes := TSqlWriteWithoutWhereRule.Writes('update Kunden k set Sperre = 1', False);
  Assert.AreEqual(1, Integer(Length(Writes)));
  Assert.AreEqual('UPDATE', Writes[0].Kind);
  Assert.AreEqual('Kunden', Writes[0].Table);
  Assert.AreEqual(1, Writes[0].Offset);
  Writes := TSqlWriteWithoutWhereRule.Writes('DELETE FROM [dbo].[Log]; DELETE FROM Puffer WHERE Alt = 1', False);
  Assert.AreEqual(1, Integer(Length(Writes)));
  Assert.AreEqual('[dbo].[Log]', Writes[0].Table);
  // WHERE in einer Unterabfrage oder einem Kommentar zählt nicht.
  Assert.AreEqual(1, Integer(Length(TSqlWriteWithoutWhereRule.Writes(
    'UPDATE Artikel SET Preis = (SELECT Max(Preis) FROM Liste WHERE Liste.Id = Artikel.Id)', False))));
  Assert.AreEqual(1, Integer(Length(TSqlWriteWithoutWhereRule.Writes('DELETE FROM Log -- WHERE Alt = 1', False))));
  Assert.AreEqual(1, Integer(Length(TSqlWriteWithoutWhereRule.Writes(
    'UPDATE Kunden SET Name = ''x WHERE y''', False))));
  // Einschränkungen ohne WHERE
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes(
    'UPDATE a SET a.X = b.X FROM Artikel a INNER JOIN Neu b ON b.Id = a.Id', False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('DELETE TOP (10) FROM Log', False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('DELETE FROM Log ORDER BY Id LIMIT 10',
    False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes(
    'UPDATE OR INSERT INTO Kunden (Id, Name) VALUES (1, ''A'') MATCHING (Id)', False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('UPDATE STATISTICS Kunden', False))));
  // Unbekannte Teile: als Wert still meldend, hinter der Tabelle unbekannt.
  Assert.AreEqual(1, Integer(Length(TSqlWriteWithoutWhereRule.Writes('UPDATE Kunden SET Name = '#1, False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('DELETE FROM Kunden '#1, False))));
  Writes := TSqlWriteWithoutWhereRule.Writes('DELETE FROM '#1, False);
  Assert.AreEqual(1, Integer(Length(Writes)));
  Assert.AreEqual('', Writes[0].Table);
  // Meldungstexte und Groß-/Kleinschreibung
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('Update fehlgeschlagen', False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('delete from Log', True))));
  Assert.AreEqual(1, Integer(Length(TSqlWriteWithoutWhereRule.Writes('delete from Log', False))));
  Assert.AreEqual(0, Integer(Length(TSqlWriteWithoutWhereRule.Writes('DELETE FROM Log fehlgeschlagen: Fehler',
    True))));
  Assert.IsTrue(TSqlWriteWithoutWhereRule.Allowed('[dbo].[Puffer]', ['puffer']));
  Assert.IsTrue(TSqlWriteWithoutWhereRule.Allowed('dbo.Puffer', ['dbo.Puffer']));
  Assert.IsFalse(TSqlWriteWithoutWhereRule.Allowed('Kunden', ['Puffer']));
end;

procedure TDatabaseRulesTests.SqlWriteVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.AreEqual('UPDATE ohne WHERE ändert alle Zeilen von Kunden.',
    FirstMessage(Body('  qry.SQL.Text := ''UPDATE Kunden SET Gesperrt = 1'';'#10'  qry.ExecSQL;'#10)));
  // SQL.Add: gemeldet am Teil mit dem Schlüsselwort; WHERE in einem späteren Add genügt.
  Findings := TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create, Body('  qry.SQL.Clear;'#10 +
    '  qry.SQL.Add(''DELETE'');'#10'  qry.SQL.Add(''FROM Warenkorb'');'#10'  qry.ExecSQL;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Count(Body('  qry.SQL.Add(''DELETE FROM Warenkorb'');'#10 +
    '  qry.SQL.Add(''WHERE Kunde = :Kunde'');'#10'  qry.ExecSQL;'#10)));
  // Neu gesetzter Text: der alte zählt für sich.
  Assert.AreEqual(1, Count(Body('  qry.SQL.Text := ''DELETE FROM Log'';'#10'  qry.ExecSQL;'#10 +
    '  qry.SQL.Text := ''DELETE FROM Puffer WHERE Id = :Id'';'#10'  qry.ExecSQL;'#10)));
  // Ergänzung über den eigenen Text
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''DELETE FROM Log'';'#10 +
    '  qry.SQL.Text := qry.SQL.Text + '' WHERE Id = '' + IntToStr(Id);'#10'  qry.ExecSQL;'#10)));
  // CommandText und ExecSQL mit SQL
  Assert.AreEqual(1, Count(Body('  Cmd.CommandText := ''delete from Puffer'';'#10'  Cmd.Execute;'#10)));
  Assert.AreEqual(1, Count(Body('  Verbindung.ExecSQL(''DELETE FROM Protokoll'');'#10)));
  Assert.AreEqual(0, Count(Body('  Verbindung.ExecSQL(''DELETE FROM Protokoll WHERE Datum < :D'', [Now - 30]);'#10)));
  // Dynamische Tabelle über Format: mittlere Konfidenz
  Findings := TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create,
    Body('  qry.SQL.Text := Format(''DELETE FROM %s'', [Tabelle]);'#10'  qry.ExecSQL;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('DELETE ohne WHERE löscht alle Zeilen der Tabelle.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := Format(''DELETE FROM %s WHERE Id = %d'', [Tabelle, Id]);'#10)));
  // Wert an der Stelle eines Werts, Teil in Anführungszeichen
  Assert.AreEqual(1, Count(Body('  qry.SQL.Text := ''UPDATE Kunden SET Name = '' + QuotedStr(Name);'#10)));
  // Literal ohne SQL-Eigenschaft: nur in Großbuchstaben
  Assert.AreEqual(1, Count(Body('  Ausfuehren(''DELETE FROM Warenkorb'');'#10)));
  Assert.AreEqual(0, Count(Body('  Ausfuehren(''Delete from Warenkorb'');'#10)));
end;

procedure TDatabaseRulesTests.SqlWriteNamedValues;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  // Konstante: gemeldet an der Verwendung
  Source := 'unit Daten;'#10'interface'#10'implementation'#10'const'#10'  SqlLeeren = ''DELETE FROM Warenkorb'';'#10 +
    'procedure Leeren(qry: TFDQuery);'#10'begin'#10'  qry.SQL.Text := SqlLeeren;'#10'  qry.ExecSQL;'#10'end;'#10'end.';
  Findings := TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  // Konstante mit Ergänzung in SQL.Add
  Assert.AreEqual(0, Count(StringReplace(Source, '  qry.ExecSQL;', '  qry.SQL.Add(''WHERE Kunde = :K'');'#10 +
    '  qry.ExecSQL;', [])));
  // Konstante, die die Unit nicht verwendet: an der Deklaration
  Findings := TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create,
    'unit Daten;'#10'interface'#10'const'#10'  SqlLeeren = ''DELETE FROM Warenkorb'';'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  // Lokaler Wert
  Assert.AreEqual(1, Count(Body('  S := ''DELETE FROM Warenkorb'';'#10'  qry.SQL.Text := S;'#10'  qry.ExecSQL;'#10)));
  Assert.AreEqual(0, Count(Body('  S := ''DELETE FROM Warenkorb'';'#10'  S := S + '' WHERE Kunde = 1'';'#10 +
    '  qry.SQL.Text := S;'#10)));
  Assert.AreEqual(0, Count(Body('  S := ''DELETE FROM Warenkorb'';'#10'  S := Bedingung(S);'#10 +
    '  qry.SQL.Text := S;'#10)));
  Assert.AreEqual(0, Count(Body('  S := ''DELETE FROM Warenkorb'';'#10'  Ergaenzen(S);'#10)));
end;

procedure TDatabaseRulesTests.SqlWriteSilentCases;
begin
  // Unbekannter Teil hinter der Tabelle
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''DELETE FROM Warenkorb '' + Bedingung;'#10)));
  Assert.AreEqual(0, Count(Body('  qry.SQL.Add(''DELETE FROM Warenkorb'');'#10'  qry.SQL.Add(Bedingung);'#10)));
  // Empfänger weitergegeben oder anders verändert
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''DELETE FROM Warenkorb'';'#10'  FilterSetzen(qry.SQL);'#10)));
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''DELETE FROM Warenkorb'';'#10 +
    '  qry.SQL.Insert(1, ''WHERE Id = 1'');'#10)));
  Assert.AreEqual(1, Count(Body('  qry.SQL.BeginUpdate;'#10'  qry.SQL.Text := ''DELETE FROM Warenkorb'';'#10 +
    '  qry.SQL.EndUpdate;'#10)));
  // Meldungstexte
  Assert.AreEqual(0, Count(Body('  ShowMessage(''Update fehlgeschlagen'');'#10 +
    '  raise Exception.Create(''Delete from cart failed'');'#10)));
  // Einschränkung über JOIN
  Assert.AreEqual(0, Count(Body('  qry.SQL.Text := ''DELETE w FROM Warenkorb w INNER JOIN Alt a ON a.Id = w.Id'';'#10)));
end;

procedure TDatabaseRulesTests.SqlWriteReceiverChangedElsewhere;
var
  Source: string;
begin
  Source := 'unit Daten;'#10'interface'#10'implementation'#10'procedure TDaten.Vorbereiten;'#10'begin'#10 +
    '  qryLeeren.SQL.Text := ''DELETE FROM Warenkorb'';'#10'end;'#10'procedure TDaten.Filtern;'#10'begin'#10 +
    '  qryLeeren.SQL.Add(''WHERE Kunde = :Kunde'');'#10'end;'#10'end.';
  Assert.AreEqual(0, Count(Source));
  // Eine andere Routine setzt nur einen eigenen Text: der erste bleibt ein Fund.
  Assert.AreEqual(1, Count(StringReplace(Source, 'qryLeeren.SQL.Add(''WHERE Kunde = :Kunde'')',
    'qryLeeren.SQL.Text := ''SELECT * FROM Warenkorb''', [])));
end;

procedure TDatabaseRulesTests.SqlWriteFormFile;
const
  Source = 'unit Daten;'#10'interface'#10'type'#10'  TdmDaten = class(TDataModule)'#10'    qryLeeren: TFDQuery;'#10 +
    '  end;'#10'implementation'#10'end.';
  Form = 'object dmDaten: TdmDaten'#10'  object qryLeeren: TFDQuery'#10'    SQL.Strings = ('#10 +
    '      ''DELETE FROM Warenkorb'')'#10'  end'#10'  object qryLesen: TFDQuery'#10'    SQL.Strings = ('#10 +
    '      ''SELECT *'''#10'      ''FROM Warenkorb'')'#10'  end'#10'end';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.FormFindings(TSqlWriteWithoutWhereRule.Create, Source, Form);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('DELETE ohne WHERE löscht alle Zeilen von Warenkorb (qryLeeren.SQL in der Formulardatei).',
    Findings[0].Message);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  // Die Unit ergänzt den SQL-Text selbst.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TSqlWriteWithoutWhereRule.Create,
    StringReplace(Source, 'implementation'#10, 'implementation'#10'procedure TdmDaten.Filtern;'#10'begin'#10 +
    '  qryLeeren.SQL.Add(''WHERE Kunde = :Kunde'');'#10'end;'#10, []), Form))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TSqlWriteWithoutWhereRule.Create, Source,
    StringReplace(Form, '''DELETE FROM Warenkorb''', '''DELETE FROM Warenkorb WHERE Kunde = :Kunde''', [])))));
end;

procedure TDatabaseRulesTests.SqlWriteOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Body('  qry.SQL.Text := ''DELETE FROM Puffer'';'#10'  qry.ExecSQL;'#10 +
    '  qry.SQL.Text := ''DELETE FROM dbo.Warenkorb'';'#10'  qry.ExecSQL;'#10);
  Assert.AreEqual(2, Count(Source));
  Assert.AreEqual(1, Count(Source, '{"rules": {"sql-write-without-where": {"allowTables": ["puffer"]}}}'));
  Assert.AreEqual(0, Count(Source, '{"rules": {"sql-write-without-where": {"allowTables": ["Puffer", ' +
    '"Warenkorb"]}}}'));
  Assert.AreEqual(0, Count(Source, '{"rules": {"sql-write-without-where": "off"}}'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSqlWriteWithoutWhereRule.Create, Source,
    '{"rules": {"sql-write-without-where": {"exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
  TConfigurationParser.Parse('{"rules": {"sql-write-without-where": {"allowTables": "Puffer"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"sql-write-without-where": {"allowTables": ["Puffer"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TDatabaseRulesTests.SelectStarIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := StarFindings(Body('  qry.SQL.Text := ''SELECT * FROM Kunden WHERE Ort = :Ort'';'#10'  qry.Open;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(SqlSelectStarRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('SELECT * holt alle Spalten; neue Spalten ändern still die Datenmenge.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(18, Findings[0].Range.StartPos.Character);
  // Ohne Formulardatei kennt die Regel die Spalten nicht: keine Korrektur.
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Korrigierte Form und naheliegender Negativfall
  Assert.AreEqual(0, StarCount(Body('  qry.SQL.Text := ''SELECT Id, Name FROM Kunden WHERE Ort = :Ort'';'#10)));
  Assert.AreEqual(0, StarCount(Body('  qry.SQL.Text := ''SELECT COUNT(*) FROM Kunden'';'#10)));
end;

procedure TDatabaseRulesTests.SelectStarAnalysis;
var
  Stars: TArray<TSqlStar>;
begin
  Stars := TSqlSelectStarRule.Stars('select * from Kunden', False);
  Assert.AreEqual(1, Integer(Length(Stars)));
  Assert.AreEqual(8, Stars[0].Offset);
  Assert.AreEqual('', Stars[0].Qualifier);
  Stars := TSqlSelectStarRule.Stars('SELECT k.Id, a.* FROM Kunden k JOIN Auftrag a ON a.Kunde = k.Id', False);
  Assert.AreEqual(1, Integer(Length(Stars)));
  Assert.AreEqual('a', Stars[0].Qualifier);
  Assert.AreEqual(1, StarsIn('SELECT DISTINCT * FROM Kunden'));
  Assert.AreEqual(1, StarsIn('SELECT TOP 10 * FROM Kunden'));
  Assert.AreEqual(1, StarsIn('SELECT TOP (10) PERCENT WITH TIES * FROM Kunden ORDER BY Umsatz'));
  Assert.AreEqual(1, StarsIn('SELECT FIRST 5 SKIP 10 * FROM Kunden'));
  Assert.AreEqual(1, StarsIn('SELECT FIRST :Anzahl * FROM Kunden'));
  // Unterabfrage zählt, EXISTS nicht
  Assert.AreEqual(1, StarsIn('SELECT Id FROM (SELECT * FROM Kunden) k'));
  Assert.AreEqual(0, StarsIn('SELECT Id FROM Kunden k WHERE NOT EXISTS (SELECT * FROM Sperre s WHERE s.Id = k.Id)'));
  Assert.AreEqual(2, StarsIn('SELECT * FROM A; SELECT * FROM B'));
  // Kein Stern als Spalte
  Assert.AreEqual(0, StarsIn('SELECT COUNT(*), Preis * Menge FROM Posten'));
  Assert.AreEqual(0, StarsIn('SELECT Id FROM Kunden /* SELECT * FROM Alt */'));
  Assert.AreEqual(0, StarsIn('SELECT Name FROM Kunden WHERE Notiz = ''SELECT * FROM X'''));
  // Ohne FROM kein SQL (Meldungstext), im SQL-Text darf ein unbekannter Teil folgen.
  Assert.AreEqual(0, Integer(Length(TSqlSelectStarRule.Stars('SELECT * ist langsam', True))));
  Assert.AreEqual(1, StarsIn('SELECT * '#1' '));
  Assert.AreEqual(0, Integer(Length(TSqlSelectStarRule.Stars('select * from Kunden', True))));
end;

procedure TDatabaseRulesTests.SelectStarSources;
begin
  // SQL.Add, CommandText, Konstante, ExecSQL-Argument, Format
  Assert.AreEqual(1, StarCount(Body('  qry.SQL.Clear;'#10'  qry.SQL.Add(''SELECT *'');'#10 +
    '  qry.SQL.Add(''FROM Kunden'');'#10)));
  Assert.AreEqual(1, StarCount(Body('  cmd.CommandText := ''select * from Kunden'';'#10)));
  Assert.AreEqual(1, StarCount('unit Daten;'#10'interface'#10'implementation'#10'const'#10 +
    '  AlleKunden = ''SELECT * FROM Kunden'';'#10'procedure Laden(qry: TFDQuery);'#10'begin'#10 +
    '  qry.Open(AlleKunden);'#10'end;'#10'end.'));
  Assert.AreEqual(1, StarCount(Body('  qry.SQL.Text := Format(''SELECT * FROM %s'', [Tabelle]);'#10)));
  Assert.AreEqual(1, StarCount(Body('  qry.SQL.Text := ''SELECT * FROM '' + Tabelle;'#10)));
  // Spalten aus einer Variablen und Meldungstexte bleiben still.
  Assert.AreEqual(0, StarCount(Body('  qry.SQL.Text := ''SELECT '' + Spalten + '' FROM Kunden'';'#10)));
  Assert.AreEqual(0, StarCount(Body('  ShowMessage(''Select * from Kunden dauert zu lange'');'#10)));
  // Wird der Text in einer anderen Routine ergänzt, bleibt die Stelle still wie bei sql-write-without-where.
  Assert.AreEqual(0, StarCount(Body('  qry.SQL.Text := ''SELECT * FROM Kunden'';'#10 +
    '  Ergaenzen(qry.SQL);'#10)));
end;

procedure TDatabaseRulesTests.SelectStarFixFromPersistentFields;
const
  Source = 'unit Daten;'#10'interface'#10'type'#10'  TdmDaten = class(TDataModule)'#10'    qryKunden: TFDQuery;'#10 +
    '    procedure Laden;'#10'  end;'#10'implementation'#10'procedure TdmDaten.Laden;'#10'begin'#10 +
    '  qryKunden.SQL.Text := ''SELECT * FROM Kunden WHERE Ort = ''''Bonn'''''';'#10'  qryKunden.Open;'#10'end;'#10 +
    'end.';
  Form = 'object dmDaten: TdmDaten'#10'  object qryKunden: TFDQuery'#10'    object qryKundenId: TIntegerField'#10 +
    '      FieldName = ''Id'''#10'    end'#10'    object qryKundenName: TWideStringField'#10 +
    '      FieldName = ''Name'''#10'      Size = 80'#10'    end'#10'    object qryKundenAnzeige: TStringField'#10 +
    '      FieldKind = fkCalculated'#10'      FieldName = ''Anzeige'''#10'      Calculated = True'#10'    end'#10 +
    '  end'#10'end';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.FormFindings(TSqlSelectStarRule.Create, Source, Form, StarOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('* durch die persistenten Felder ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual('Id, Name', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(10, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(32, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(33, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  // Ohne persistente Felder keine Korrektur
  Findings := TRuleAssert.FormFindings(TSqlSelectStarRule.Create, Source,
    'object dmDaten: TdmDaten'#10'  object qryKunden: TFDQuery'#10'  end'#10'end', StarOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TDatabaseRulesTests.SelectStarFormFile;
const
  Source = 'unit Daten;'#10'interface'#10'type'#10'  TdmDaten = class(TDataModule)'#10'    qryLesen: TFDQuery;'#10 +
    '  end;'#10'implementation'#10'end.';
  Form = 'object dmDaten: TdmDaten'#10'  object qryLesen: TFDQuery'#10'    SQL.Strings = ('#10 +
    '      ''SELECT *'''#10'      ''FROM Warenkorb'')'#10'  end'#10'end';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.FormFindings(TSqlSelectStarRule.Create, Source, Form, StarOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('SELECT * holt alle Spalten (qryLesen.SQL in der Formulardatei); neue Spalten ändern still die ' +
    'Datenmenge.', Findings[0].Message);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  // Standard aus
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TSqlSelectStarRule.Create, Source, Form))));
end;

procedure TDatabaseRulesTests.SelectStarOptions;
var
  Source: string;
  Rule: IRule;
begin
  Source := Body('  qry.SQL.Text := ''SELECT * FROM Kunden'';'#10);
  Rule := TSqlSelectStarRule.Create;
  Assert.IsTrue(Rule.Descriptor.Experimental, 'Standard aus');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSqlSelectStarRule.Create, Source))));
  Assert.AreEqual(1, StarCount(Source));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSqlSelectStarRule.Create, Source,
    '{"rules": {"sql-select-star": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSqlSelectStarRule.Create, Source,
    '{"rules": {"sql-select-star": {"severity": "hint", "exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
end;

procedure TDatabaseRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found, FoundStar: Boolean;
begin
  Found := False;
  FoundStar := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = SqlWriteWithoutWhereRuleId then
      Found := True
    else if Rule.Descriptor.Id = SqlSelectStarRuleId then
      FoundStar := True;
  Assert.IsTrue(Found);
  Assert.IsTrue(FoundStar);
end;

initialization
  TDUnitX.RegisterTestFixture(TDatabaseRulesTests);

end.
