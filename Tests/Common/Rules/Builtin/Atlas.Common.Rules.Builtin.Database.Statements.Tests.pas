unit Atlas.Common.Rules.Builtin.Database.Statements.Tests;

// Tests der SQL-Zerlegung für die Gruppe Datenbank (Atlas.Common.Rules.Builtin.Database.Statements):
// Kommentare und Literale, Großschreibung, unbekannte Teile an Wert- und Klauselstellen, Schema und Alias
// bei UPDATE/DELETE; Sterne nach TOP, FIRST/SKIP, WITH TIES, mit Alias und in EXISTS.
// lsp-ignore-file: sql-write-without-where -- die SQL-Texte sind Prüffälle der Zerlegung

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDatabaseStatementsTests = class
  public
    [Test]
    procedure WritesSkipCommentsAndLiterals;
    [Test]
    procedure WritesRespectStrictCase;
    [Test]
    procedure WritesWithHoles;
    [Test]
    procedure WritesReadSchemaAndAlias;
    [Test]
    procedure StarsAfterLimits;
    [Test]
    procedure StarsWithQualifierAndExists;
  end;

implementation

uses
  Atlas.Common.Rules.Builtin.Database.Statements;

procedure TDatabaseStatementsTests.WritesSkipCommentsAndLiterals;
begin
  Assert.AreEqual(1, Integer(Length(SqlWrites('DELETE FROM Log /* WHERE Alt = 1 */', False))));
  Assert.AreEqual(1, Integer(Length(SqlWrites('DELETE FROM Log /* WHERE offen', False))));
  Assert.AreEqual(0, Integer(Length(SqlWrites('DELETE FROM Log' + #13#10 + '-- Kommentar' + #13#10 +
    'WHERE Alt = 1', False))));
  Assert.AreEqual(1, Integer(Length(SqlWrites('UPDATE Log SET Text = ''WHERE''', False))));
end;

procedure TDatabaseStatementsTests.WritesRespectStrictCase;
begin
  Assert.AreEqual(0, Integer(Length(SqlWrites('Delete from cart failed', True))));
  Assert.AreEqual(0, Integer(Length(SqlWrites('DELETE Log', True))));
  Assert.AreEqual(1, Integer(Length(SqlWrites('DELETE Log', False))));
  Assert.AreEqual(1, Integer(Length(SqlWrites('DELETE FROM Log', True))));
end;

procedure TDatabaseStatementsTests.WritesWithHoles;
var
  mWrites: TArray<TSqlWrite>;
begin
  mWrites := SqlWrites('DELETE FROM ' + cSqlHole, False);
  Assert.AreEqual(1, Integer(Length(mWrites)));
  Assert.AreEqual('', mWrites[0].Table);
  // An einer Wertstelle bleibt die Anweisung eine Meldung, an einer Klauselstelle nicht.
  Assert.AreEqual(1, Integer(Length(SqlWrites('UPDATE Log SET Text = ' + cSqlHole, False))));
  Assert.AreEqual(0, Integer(Length(SqlWrites('UPDATE Log SET Text = 1 ' + cSqlHole, False))));
end;

procedure TDatabaseStatementsTests.WritesReadSchemaAndAlias;
var
  mWrites: TArray<TSqlWrite>;
begin
  mWrites := SqlWrites('update only dbo.Kunden as k set Sperre = 1', False);
  Assert.AreEqual(1, Integer(Length(mWrites)));
  Assert.AreEqual('UPDATE', mWrites[0].Kind);
  Assert.AreEqual('dbo.Kunden', mWrites[0].Table);
  Assert.AreEqual(1, mWrites[0].Offset);
  Assert.AreEqual(0, Integer(Length(SqlWrites('UPDATE OR INSERT INTO Log VALUES (1)', False))));
end;

procedure TDatabaseStatementsTests.StarsAfterLimits;
begin
  Assert.AreEqual(1, Integer(Length(SqlStars('SELECT TOP (10) PERCENT WITH TIES * FROM Log', False))));
  Assert.AreEqual(1, Integer(Length(SqlStars('SELECT FIRST :n SKIP 5 DISTINCT * FROM Log', False))));
  Assert.AreEqual(0, Integer(Length(SqlStars('SELECT COUNT(*) FROM Log', False))));
end;

procedure TDatabaseStatementsTests.StarsWithQualifierAndExists;
var
  mStars: TArray<TSqlStar>;
begin
  mStars := SqlStars('SELECT k.*, a.Id FROM Kunden k JOIN Auftrag a ON a.Kunde = k.Id', False);
  Assert.AreEqual(1, Integer(Length(mStars)));
  Assert.AreEqual('k', mStars[0].Qualifier);
  Assert.AreEqual(10, mStars[0].Offset);
  Assert.AreEqual(0, Integer(Length(SqlStars('SELECT Id FROM Log WHERE EXISTS (SELECT * FROM Alt)', False))));
  Assert.AreEqual(0, Integer(Length(SqlStars('select * fehlt', True))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDatabaseStatementsTests);

end.
