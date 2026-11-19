unit Atlas.Core.Debug.DataBreakPatterns.Tests;

// Tests für den Musterabgleich von „Anhalten bei Datenzugriff“ (#870): SQL mit *, HTTP mit Methoden, Zeichenketten
// aus der Auswertung des Debuggers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDataPatternsTests = class
  public
    [Test]
    procedure SqlPatternMatchesWholeText;
    [Test]
    procedure SqlPatternCaseAndWhitespace;
    [Test]
    procedure EmptyPatternMatchesAll;
    [Test]
    procedure HttpPatternWithMethods;
    [Test]
    procedure HttpPatternWithoutMethods;
    [Test]
    procedure HttpMethodNames;
    [Test]
    procedure DebuggerStrings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.DataBreakPatterns;

{ TAtlasDataPatternsTests }

procedure TAtlasDataPatternsTests.SqlPatternMatchesWholeText;
begin
  Assert.IsTrue(TAtlasDataPatterns.Like('UPDATE Kunden*', 'UPDATE Kunden SET Name = :Name WHERE ID = :ID', False));
  Assert.IsFalse(TAtlasDataPatterns.Like('UPDATE Kunden*', 'SELECT * FROM Kunden', False));
  Assert.IsTrue(TAtlasDataPatterns.Like('*FROM Kunden*', 'SELECT * FROM Kunden WHERE ID = 1', False));
  Assert.IsFalse(TAtlasDataPatterns.Like('*FROM Kunden', 'SELECT * FROM Kunden WHERE ID = 1', False));
  Assert.IsTrue(TAtlasDataPatterns.Like('SELECT ** FROM *', 'SELECT * FROM Auftrag', False));
  Assert.IsTrue(TAtlasDataPatterns.Like('*a*b*', 'xaybz', False));
  Assert.IsFalse(TAtlasDataPatterns.Like('*a*b', 'xaybz', False));
end;

procedure TAtlasDataPatternsTests.SqlPatternCaseAndWhitespace;
begin
  Assert.IsTrue(TAtlasDataPatterns.Like('update kunden*', 'UPDATE Kunden SET Größe = 1 WHERE ID = 2', True));
  Assert.IsFalse(TAtlasDataPatterns.Like('update kunden*', 'UPDATE Kunden SET Größe = 1 WHERE ID = 2', False));
  Assert.IsTrue(TAtlasDataPatterns.Like('UPDATE Kunden SET*', '  UPDATE'#13#10'  Kunden'#9'SET X = 1 WHERE ID = 2 ',
    False));
  Assert.AreEqual('A B C', TAtlasDataPatterns.Squeeze(#13#10' A  B'#10#10'C '));
end;

procedure TAtlasDataPatternsTests.EmptyPatternMatchesAll;
begin
  Assert.IsTrue(TAtlasDataPatterns.Like('', 'DELETE FROM Kunden WHERE ID = 3', True));
  Assert.IsTrue(TAtlasDataPatterns.Like('   ', '', True));
  Assert.IsTrue(TAtlasDataPatterns.Like('*', '', True));
  Assert.IsFalse(TAtlasDataPatterns.Like('A', '', True));
end;

procedure TAtlasDataPatternsTests.HttpPatternWithMethods;
var
  mPattern: TAtlasHttpPattern;
begin
  mPattern := TAtlasDataPatterns.ParseHttp('POST */api/auftrag*');
  Assert.AreEqual(1, Integer(Length(mPattern.Methods)));
  Assert.AreEqual('POST', mPattern.Methods[0]);
  Assert.AreEqual('*/api/auftrag*', mPattern.Url);
  Assert.IsTrue(TAtlasDataPatterns.HttpMatches(mPattern, 'post', 'https://x.de/api/auftrag/12', True));
  Assert.IsFalse(TAtlasDataPatterns.HttpMatches(mPattern, 'GET', 'https://x.de/api/auftrag/12', True));
  Assert.IsFalse(TAtlasDataPatterns.HttpMatches(mPattern, 'POST', 'https://x.de/api/kunde', True));
  mPattern := TAtlasDataPatterns.ParseHttp('get,Put  *');
  Assert.AreEqual('GET,PUT', string.Join(',', mPattern.Methods));
  Assert.IsTrue(TAtlasDataPatterns.HttpMatches(mPattern, 'PUT', 'http://a', True));
  Assert.IsFalse(TAtlasDataPatterns.HttpMatches(mPattern, 'DELETE', 'http://a', True));
  mPattern := TAtlasDataPatterns.ParseHttp('DELETE');
  Assert.AreEqual('', mPattern.Url);
  Assert.IsTrue(TAtlasDataPatterns.HttpMatches(mPattern, 'DELETE', 'http://a', True));
end;

procedure TAtlasDataPatternsTests.HttpPatternWithoutMethods;
var
  mPattern: TAtlasHttpPattern;
begin
  mPattern := TAtlasDataPatterns.ParseHttp('*/api/*');
  Assert.AreEqual(0, Integer(Length(mPattern.Methods)));
  Assert.AreEqual('*/api/*', mPattern.Url);
  Assert.IsTrue(TAtlasDataPatterns.HttpMatches(mPattern, 'GET', 'http://x/api/a', False));
  // Kein Methodenwort vorn: alles ist URL.
  mPattern := TAtlasDataPatterns.ParseHttp('POSTEN *');
  Assert.AreEqual('POSTEN *', mPattern.Url);
end;

procedure TAtlasDataPatternsTests.HttpMethodNames;
begin
  Assert.AreEqual('GET', TAtlasDataPatterns.HttpMethodOf('Get'));
  Assert.AreEqual('POST', TAtlasDataPatterns.HttpMethodOf('rmPOST'));
  Assert.AreEqual('DELETE', TAtlasDataPatterns.HttpMethodOf(' rmDELETE '));
  Assert.AreEqual('', TAtlasDataPatterns.HttpMethodOf('Execute'));
  Assert.AreEqual('', TAtlasDataPatterns.HttpMethodOf('rm'));
end;

procedure TAtlasDataPatternsTests.DebuggerStrings;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasDataPatterns.DebuggerString('''It''''s''', mText));
  Assert.AreEqual('It''s', mText);
  Assert.IsTrue(TAtlasDataPatterns.DebuggerString('''SELECT *''#13#10''FROM X''', mText));
  Assert.AreEqual('SELECT *'#13#10'FROM X', mText);
  Assert.IsTrue(TAtlasDataPatterns.DebuggerString('#$D#$A''A''', mText));
  Assert.AreEqual(#13#10'A', mText);
  Assert.IsTrue(TAtlasDataPatterns.DebuggerString('''''', mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasDataPatterns.DebuggerString('42', mText));
  Assert.IsFalse(TAtlasDataPatterns.DebuggerString('''offen', mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasDataPatterns.DebuggerString('#x', mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataPatternsTests);

end.
