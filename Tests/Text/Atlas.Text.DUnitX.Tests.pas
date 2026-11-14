unit Atlas.Text.DUnitX.Tests;

// Tests der DUnitX-Erkennung im Quelltext (#69, gemeinsamer Baustein mit #154
// und #585): Attributnamen, Fixtures über Attribut und Registrierung, Tests
// über [Test], [TestCase] und published, keine Tests bei [Setup] und
// [Test(False)], Zeilen von Attribut, Deklaration und Rumpf, Befehlszeile;
// für #585 Rumpf bis end (lokale Routinen, Typen), Zeilen der Testfälle,
// Test an einer Zeile, Marken und Namen für --run je Fall; für #1770 die
// Prüfsumme ohne Kommentare und Leerraum und die Units der uses-Klauseln;
// für #2167 die Kategorien an Fixture und Test und Optionen in den Argumenten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXSourceTests = class
  public
    [Test]
    procedure AttributeNamesWithSuffixAndQualified;
    [Test]
    procedure FindsFixtureTestsAndLines;
    [Test]
    procedure TestCasesAndIgnore;
    [Test]
    procedure SetupAndDisabledTestsAreNoTests;
    [Test]
    procedure RegisteredClassWithoutAttributeIsFixture;
    [Test]
    procedure ClassWithoutFixtureIsIgnored;
    [Test]
    procedure PublishedMethodsAreTests;
    [Test]
    procedure CommentsAndStringsAreSkipped;
    [Test]
    procedure FieldAttributeDoesNotMakeTest;
    [Test]
    procedure AtLineFindsFixtureAndTest;
    [Test]
    procedure DetectsDUnitXProgram;
    [Test]
    procedure CommandLineWithAndWithoutFilter;
    [Test]
    procedure BodyRangeSkipsLocalRoutinesAndTypes;
    [Test]
    procedure CaseLinesAndMarks;
    [Test]
    procedure TestAtFindsCaseTestFixtureAndBody;
    [Test]
    procedure RunNamesPerCaseAndFixture;
    [Test]
    procedure FingerprintIgnoresWhitespaceAndComments;
    [Test]
    procedure FingerprintSeesCodeStringsAndDirectives;
    [Test]
    procedure UsedUnitsOfBothClauses;
    [Test]
    procedure CategoriesOfFixtureAndTest;
    [Test]
    procedure OptionsGoBesideRun;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DUnitX;

function Sample: TArray<string>;
begin
  Result := [
    'unit Rechner.Tests;',                                      // 0
    '',                                                         // 1
    'interface',                                                // 2
    '',                                                         // 3
    'uses',                                                     // 4
    '  DUnitX.TestFramework;',                                  // 5
    '',                                                         // 6
    'type',                                                     // 7
    '  [TestFixture]',                                          // 8
    '  TRechnerTests = class',                                  // 9
    '  private',                                                // 10
    '    FWert: Integer;',                                      // 11
    '  public',                                                 // 12
    '    [Setup]',                                              // 13
    '    procedure Setup;',                                     // 14
    '    [Test]',                                               // 15
    '    procedure Addiert;',                                   // 16
    '    [Test]',                                               // 17
    '    [TestCase(''Klein'', ''1,2,3'')]',                     // 18
    '    [TestCase(''Gross'', ''10,20,30'')]',                  // 19
    '    procedure Summe(A, B, C: Integer);',                   // 20
    '    procedure Hilfe;',                                     // 21
    '  end;',                                                   // 22
    '',                                                         // 23
    'implementation',                                           // 24
    '',                                                         // 25
    'procedure TRechnerTests.Setup;',                           // 26
    'begin',                                                    // 27
    'end;',                                                     // 28
    '',                                                         // 29
    'procedure TRechnerTests.Addiert;',                         // 30
    'begin',                                                    // 31
    '  Assert.AreEqual(3, 1 + 2);',                             // 32
    'end;',                                                     // 33
    '',                                                         // 34
    'procedure TRechnerTests.Summe(A, B, C: Integer);',         // 35
    'begin',                                                    // 36
    'end;',                                                     // 37
    '',                                                         // 38
    'procedure TRechnerTests.Hilfe;',                           // 39
    'begin',                                                    // 40
    'end;',                                                     // 41
    '',                                                         // 42
    'end.'];                                                    // 43
end;

{ TDUnitXSourceTests }

procedure TDUnitXSourceTests.AttributeNamesWithSuffixAndQualified;
begin
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.TestFixture, TDUnitXSource.AttributeOf('TestFixture'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.TestFixture, TDUnitXSource.AttributeOf('TestFixtureAttribute'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.TestFixture,
    TDUnitXSource.AttributeOf('DUnitX.Attributes.TestFixture'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.Test, TDUnitXSource.AttributeOf('test'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.TestCase, TDUnitXSource.AttributeOf('TestCase'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.Ignore, TDUnitXSource.AttributeOf('IgnoreAttribute'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.Category, TDUnitXSource.AttributeOf('Category'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.SetupFixture, TDUnitXSource.AttributeOf('SetupFixture'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.TearDown, TDUnitXSource.AttributeOf('TearDown'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.None, TDUnitXSource.AttributeOf('Weak'));
  Assert.AreEqual<TDUnitXAttribute>(TDUnitXAttribute.None, TDUnitXSource.AttributeOf('Attribute'), 'nur die Endung');
end;

procedure TDUnitXSourceTests.FindsFixtureTestsAndLines;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.AreEqual('Rechner.Tests', mFound.UnitName);
  Assert.AreEqual(1, Integer(Length(mFound.Fixtures)));
  Assert.AreEqual('TRechnerTests', mFound.Fixtures[0].Name);
  Assert.AreEqual(9, mFound.Fixtures[0].Line);
  Assert.AreEqual(8, mFound.Fixtures[0].AttributeLine);
  Assert.AreEqual(2, Integer(Length(mFound.Fixtures[0].Tests)), 'Addiert und Summe; Setup und Hilfe nicht');
  Assert.AreEqual(2, mFound.TestCount);
  Assert.AreEqual('Addiert', mFound.Fixtures[0].Tests[0].Method);
  Assert.AreEqual(16, mFound.Fixtures[0].Tests[0].Line);
  Assert.AreEqual(15, mFound.Fixtures[0].Tests[0].AttributeLine);
  Assert.AreEqual(30, mFound.Fixtures[0].Tests[0].BodyLine);
  Assert.AreEqual('Summe', mFound.Fixtures[0].Tests[1].Method);
  Assert.AreEqual(17, mFound.Fixtures[0].Tests[1].AttributeLine);
  Assert.AreEqual(35, mFound.Fixtures[0].Tests[1].BodyLine);
end;

procedure TDUnitXSourceTests.TestCasesAndIgnore;
var
  mFound: TDUnitXUnit;
  mTest: TDUnitXTest;
begin
  mFound := TDUnitXSource.Scan(Sample);
  mTest := mFound.Fixtures[0].Tests[1];
  Assert.AreEqual(2, Integer(Length(mTest.Cases)));
  Assert.AreEqual('Klein', mTest.Cases[0]);
  Assert.AreEqual('Gross', mTest.Cases[1]);
  Assert.IsFalse(mTest.Ignored);
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]', '  TT = class',
    '  public',
    '    [Test, Ignore(''später'')]',
    '    procedure Spaeter;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(1, mFound.TestCount);
  Assert.IsTrue(mFound.Fixtures[0].Tests[0].Ignored);
  Assert.AreEqual(-1, mFound.Fixtures[0].Tests[0].BodyLine, 'ohne Rumpf');
end;

procedure TDUnitXSourceTests.SetupAndDisabledTestsAreNoTests;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]', '  TT = class',
    '  public',
    '    [SetupFixture] procedure Vorher;',
    '    [TearDownFixture] procedure Nachher;',
    '    [TearDown] procedure Danach;',
    '    [Test(False)] procedure Aus;',
    '    [Test(True)] procedure An;',
    '    [Test] class procedure Klasse;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(1, mFound.TestCount);
  Assert.AreEqual('An', mFound.Fixtures[0].Tests[0].Method);
  Assert.AreEqual(10, mFound.Fixtures[0].Tests[0].Line);
  Assert.AreEqual(10, mFound.Fixtures[0].Tests[0].AttributeLine, 'Attribut in derselben Zeile');
end;

procedure TDUnitXSourceTests.RegisteredClassWithoutAttributeIsFixture;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'uses DUnitX.TestFramework;', 'type',
    '  TOhneAttribut = class(TObject)',
    '  public',
    '    [Test]',
    '    procedure Eins;',
    '  end;',
    'implementation',
    'procedure TOhneAttribut.Eins; begin end;',
    'initialization',
    '  TDUnitX.RegisterTestFixture(TOhneAttribut);',
    'end.']);
  Assert.AreEqual(1, Integer(Length(mFound.Fixtures)));
  Assert.AreEqual(4, mFound.Fixtures[0].AttributeLine, 'ohne Attribut die Klassenzeile');
  Assert.AreEqual(10, mFound.Fixtures[0].Tests[0].BodyLine);
end;

procedure TDUnitXSourceTests.ClassWithoutFixtureIsIgnored;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  TVorwaerts = class;',
    '  TKlasse = class of TObject;',
    '  THelfer = class',
    '  public',
    '    [Test] procedure KeineFixture;',
    '  end;',
    '  [TestFixture]',
    '  TT = class',
    '  public',
    '    type TInnen = class',
    '      [Test] procedure Innen;',
    '    end;',
    '    [Test] procedure Aussen;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(1, Integer(Length(mFound.Fixtures)), 'THelfer ist weder markiert noch registriert');
  Assert.AreEqual('TT', mFound.Fixtures[0].Name);
  Assert.AreEqual(1, Integer(Length(mFound.Fixtures[0].Tests)), 'Methoden innerer Klassen zählen nicht');
  Assert.AreEqual('Aussen', mFound.Fixtures[0].Tests[0].Method);
end;

procedure TDUnitXSourceTests.PublishedMethodsAreTests;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]',
    '  TT = class',
    '  published',
    '    procedure OhneAttribut;',
    '    [Setup] procedure Vorbereiten;',
    '  public',
    '    procedure KeinTest;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(1, mFound.TestCount);
  Assert.AreEqual('OhneAttribut', mFound.Fixtures[0].Tests[0].Method);
end;

procedure TDUnitXSourceTests.CommentsAndStringsAreSkipped;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  // [TestFixture] TFalsch = class',
    '  { [TestFixture]',
    '    TAuchFalsch = class }',
    '  [TestFixture] (* Kommentar *)',
    '  TT = class',
    '  public',
    '    [TestCase(''A;b'', ''x]y'')]',
    '    procedure Fall(const S: string);',
    '  end;',
    'implementation',
    'procedure TT.Fall(const S: string);',
    'begin',
    '  Writeln(''procedure TT.Fall'');',
    'end;',
    'end.']);
  Assert.AreEqual(1, Integer(Length(mFound.Fixtures)));
  Assert.AreEqual(1, mFound.TestCount);
  Assert.AreEqual('A;b', mFound.Fixtures[0].Tests[0].Cases[0]);
  Assert.AreEqual(13, mFound.Fixtures[0].Tests[0].BodyLine);
end;

procedure TDUnitXSourceTests.FieldAttributeDoesNotMakeTest;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]',
    '  TT = class',
    '  public',
    '    [Test]',
    '    FFeld: Integer;',
    '    procedure Methode;',
    '    [Category(''Langsam'')]',
    '    [Test] procedure Langsam;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(1, mFound.TestCount, '[Test] am Feld gilt nicht für die nächste Methode');
  Assert.AreEqual('Langsam', mFound.Fixtures[0].Tests[0].Method);
  Assert.AreEqual(9, mFound.Fixtures[0].Tests[0].AttributeLine, 'erstes Attribut');
end;

procedure TDUnitXSourceTests.AtLineFindsFixtureAndTest;
var
  mFound: TDUnitXUnit;
  mFixtureIndex, mTestIndex: Integer;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.IsTrue(mFound.AtLine(8, mFixtureIndex, mTestIndex));
  Assert.AreEqual(0, mFixtureIndex);
  Assert.AreEqual(-1, mTestIndex);
  Assert.IsTrue(mFound.AtLine(16, mFixtureIndex, mTestIndex));
  Assert.AreEqual(0, mTestIndex);
  Assert.IsTrue(mFound.AtLine(17, mFixtureIndex, mTestIndex));
  Assert.AreEqual(1, mTestIndex);
  Assert.IsFalse(mFound.AtLine(14, mFixtureIndex, mTestIndex), 'Setup ist kein Test');
  Assert.IsTrue(mFound.Find('trechnertests', 'SUMME', mFixtureIndex, mTestIndex));
  Assert.AreEqual(1, mTestIndex);
  Assert.IsTrue(mFound.Find('TRechnerTests', '', mFixtureIndex, mTestIndex));
  Assert.AreEqual(-1, mTestIndex);
  Assert.IsFalse(mFound.Find('TAndere', 'Addiert', mFixtureIndex, mTestIndex));
  // Zeile eines Ergebnisses: Methodenkopf, sonst Fixture.
  Assert.AreEqual(35, mFound.LineOf('TRechnerTests', 'Summe'));
  Assert.AreEqual(9, mFound.LineOf('TRechnerTests', 'Unbekannt'), 'unbekannte Methode: Fixture');
  Assert.AreEqual(9, mFound.LineOf('TRechnerTests', ''));
  Assert.AreEqual(-1, mFound.LineOf('TAndere', 'Addiert'));
end;

procedure TDUnitXSourceTests.DetectsDUnitXProgram;
begin
  Assert.IsTrue(TDUnitXSource.UsesDUnitX([
    'program Rechner.Tests;', '{$APPTYPE CONSOLE}', 'uses', '  System.SysUtils,',
    '  DUnitX.TestFramework,', '  Rechner.Tests in ''Rechner.Tests.pas'';', 'begin', 'end.']));
  Assert.IsTrue(TDUnitXSource.UsesDUnitX(['program P;', 'uses DUnitX.TestFramework in ''x.pas'';', 'end.']));
  Assert.IsFalse(TDUnitXSource.UsesDUnitX(['program App;', 'uses Vcl.Forms; // DUnitX.TestFramework,', 'end.']));
  Assert.IsFalse(TDUnitXSource.UsesDUnitX(['program App;', 'uses DUnitX.TestFrameworkExtra;', 'end.']));
end;

procedure TDUnitXSourceTests.CommandLineWithAndWithoutFilter;
var
  mArguments: TArray<string>;
begin
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Addiert',
    TDUnitXCommandLine.TestName('Rechner.Tests', 'TRechnerTests', 'Addiert'));
  Assert.AreEqual('Rechner.Tests.TRechnerTests', TDUnitXCommandLine.TestName('Rechner.Tests', 'TRechnerTests', ''));
  mArguments := TDUnitXCommandLine.Arguments('C:\Temp\r.xml', nil);
  Assert.AreEqual(2, Integer(Length(mArguments)));
  Assert.AreEqual('--exitbehavior:Continue', mArguments[0]);
  Assert.AreEqual('--xmlfile:C:\Temp\r.xml', mArguments[1]);
  mArguments := TDUnitXCommandLine.Arguments('r.xml', ['A.T.X', '', 'A.T.Y']);
  Assert.AreEqual(3, Integer(Length(mArguments)));
  Assert.AreEqual('--run:A.T.X,A.T.Y', mArguments[2]);
  mArguments := TDUnitXCommandLine.Arguments('r.xml', [StringOfChar('x', TDUnitXCommandLine.cMaxRunLength + 1)]);
  Assert.AreEqual(2, Integer(Length(mArguments)), 'zu lang: alle Tests');
end;

procedure TDUnitXSourceTests.BodyRangeSkipsLocalRoutinesAndTypes;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.AreEqual(32, mFound.Fixtures[0].Tests[0].BeginLine, 'erste Anweisung');
  Assert.AreEqual(33, mFound.Fixtures[0].Tests[0].EndLine);
  Assert.AreEqual(36, mFound.Fixtures[0].Tests[1].BeginLine, 'ohne Anweisung: begin');
  Assert.AreEqual(37, mFound.Fixtures[0].Tests[1].EndLine);
  mFound := TDUnitXSource.Scan([
    'unit U;',                                                  // 0
    'interface',                                                // 1
    'type',                                                     // 2
    '  [TestFixture]',                                          // 3
    '  TT = class',                                             // 4
    '  public',                                                 // 5
    '    [Test] procedure Lokal;',                              // 6
    '    [Test] procedure Verschachtelt;',                      // 7
    '    [Test] procedure OhneRumpf;',                          // 8
    '  end;',                                                   // 9
    'implementation',                                           // 10
    'procedure TT.Lokal;',                                      // 11
    'type',                                                     // 12
    '  TPaar = record A, B: Integer; end;',                     // 13
    '  TRueckruf = procedure(X: Integer) of object;',           // 14
    'var',                                                      // 15
    '  P: TPaar;',                                              // 16
    '  function Hilfe: Integer;',                               // 17
    '  begin',                                                  // 18
    '    Result := 1;',                                         // 19
    '  end;',                                                   // 20
    'begin',                                                    // 21
    '  P.A := Hilfe;',                                          // 22
    'end;',                                                     // 23
    'procedure TT.Verschachtelt;',                              // 24
    'begin',                                                    // 25
    '  try',                                                    // 26
    '    case 1 of',                                            // 27
    '      1: begin end;',                                      // 28
    '    end;',                                                 // 29
    '  finally',                                                // 30
    '  end;',                                                   // 31
    'end;',                                                     // 32
    'end.']);                                                   // 33
  Assert.AreEqual(3, mFound.TestCount);
  Assert.AreEqual(11, mFound.Fixtures[0].Tests[0].BodyLine);
  Assert.AreEqual(22, mFound.Fixtures[0].Tests[0].BeginLine, 'nach lokaler Routine und Typen');
  Assert.AreEqual(23, mFound.Fixtures[0].Tests[0].EndLine);
  Assert.AreEqual(26, mFound.Fixtures[0].Tests[1].BeginLine);
  Assert.AreEqual(32, mFound.Fixtures[0].Tests[1].EndLine, 'try und case haben ein eigenes end');
  Assert.AreEqual(-1, mFound.Fixtures[0].Tests[2].BeginLine, 'ohne Rumpf');
  Assert.AreEqual(-1, mFound.Fixtures[0].Tests[2].EndLine);
end;

procedure TDUnitXSourceTests.CaseLinesAndMarks;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.AreEqual(2, Integer(Length(mFound.Fixtures[0].Tests[1].CaseLines)));
  Assert.AreEqual(18, mFound.Fixtures[0].Tests[1].CaseLines[0]);
  Assert.AreEqual(19, mFound.Fixtures[0].Tests[1].CaseLines[1]);
  Assert.IsTrue(mFound.CaseHasOwnLine(0, 1, 0));
  Assert.IsTrue(mFound.CaseHasOwnLine(0, 1, 1));
  Assert.IsFalse(mFound.CaseHasOwnLine(0, 1, 2), 'ungültiger Fall');
  Assert.AreEqual(8, mFound.MarkLine(0, -1), 'Fixture: ihr Attribut');
  Assert.AreEqual(15, mFound.MarkLine(0, 0), 'Test: sein Attribut');
  Assert.AreEqual(17, mFound.MarkLine(0, 1), '[Test] vor den Fällen');
  Assert.AreEqual(-1, mFound.MarkLine(1, -1));
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]', '  TT = class',
    '  public',
    '    [TestCase(''A'', ''1'')]',                             // 6
    '    [TestCase(''B'', ''2'')]',                             // 7
    '    procedure EigeneZeilen(X: Integer);',                  // 8
    '    [TestCase(''C'', ''1''), TestCase(''D'', ''2'')]',     // 9
    '    procedure EineZeile(X: Integer);',                     // 10
    '    [TestCase(''E'', ''1'')] procedure MitKopf(X: Integer);', // 11
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(3, mFound.TestCount);
  Assert.AreEqual(8, mFound.MarkLine(0, 0), 'erster Fall hat die Zeile: Marke des Tests an der Deklaration');
  Assert.IsFalse(mFound.CaseHasOwnLine(0, 1, 0), 'zwei Fälle in einer Zeile');
  Assert.AreEqual(9, mFound.MarkLine(0, 1), 'Fälle ohne eigene Zeile: Marke am Attribut');
  Assert.IsFalse(mFound.CaseHasOwnLine(0, 2, 0), 'Fall in der Zeile der Deklaration');
  Assert.AreEqual(11, mFound.MarkLine(0, 2), 'eine Marke für den Test');
end;

procedure TDUnitXSourceTests.TestAtFindsCaseTestFixtureAndBody;
var
  mFound: TDUnitXUnit;
  mFixtureIndex, mTestIndex, mCaseIndex: Integer;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.IsTrue(mFound.TestAt(8, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(0, mFixtureIndex);
  Assert.AreEqual(-1, mTestIndex, 'Fixture');
  Assert.IsTrue(mFound.TestAt(9, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(-1, mTestIndex);
  Assert.IsTrue(mFound.TestAt(18, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(1, mTestIndex);
  Assert.AreEqual(0, mCaseIndex, 'Zeile des Falls Klein');
  Assert.IsTrue(mFound.TestAt(19, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(1, mCaseIndex);
  Assert.IsTrue(mFound.TestAt(17, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(1, mTestIndex);
  Assert.AreEqual(-1, mCaseIndex, '[Test]: alle Fälle');
  Assert.IsTrue(mFound.TestAt(20, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(-1, mCaseIndex);
  Assert.IsTrue(mFound.TestAt(32, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(0, mTestIndex, 'im Rumpf von Addiert');
  Assert.IsTrue(mFound.TestAt(30, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(0, mTestIndex, 'Methodenkopf');
  Assert.IsTrue(mFound.TestAt(37, mFixtureIndex, mTestIndex, mCaseIndex));
  Assert.AreEqual(1, mTestIndex, 'end von Summe');
  Assert.IsFalse(mFound.TestAt(14, mFixtureIndex, mTestIndex, mCaseIndex), 'Setup ist kein Test');
  Assert.IsFalse(mFound.TestAt(27, mFixtureIndex, mTestIndex, mCaseIndex), 'Rumpf von Setup');
  Assert.IsFalse(mFound.TestAt(40, mFixtureIndex, mTestIndex, mCaseIndex), 'Rumpf von Hilfe');
  Assert.IsFalse(mFound.TestAt(34, mFixtureIndex, mTestIndex, mCaseIndex), 'zwischen den Rümpfen');
  Assert.AreEqual(-1, mFixtureIndex);
  Assert.AreEqual(-1, mTestIndex);
end;

procedure TDUnitXSourceTests.RunNamesPerCaseAndFixture;
var
  mFound: TDUnitXUnit;
  mNames: TArray<string>;
begin
  Assert.AreEqual('U.TT.M.Fall', TDUnitXCommandLine.CaseName('U', 'TT', 'M', 'Fall'));
  Assert.AreEqual('U.TT.M(1,2)', TDUnitXCommandLine.CaseName('U', 'TT', 'M', '(1,2)'), 'AutoNameTestCase');
  Assert.AreEqual('U.TT.M', TDUnitXCommandLine.CaseName('U', 'TT', 'M', ''));
  mFound := TDUnitXSource.Scan(Sample);
  mNames := TDUnitXCommandLine.RunNames(mFound, 0, 0, -1);
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Addiert', mNames[0]);
  // [TestCase]: Unit.Fixture.Methode trifft keinen Fall, darum je Fall ein Name.
  mNames := TDUnitXCommandLine.RunNames(mFound, 0, 1, -1);
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Klein', mNames[0]);
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mNames[1]);
  mNames := TDUnitXCommandLine.RunNames(mFound, 0, 1, 1);
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mNames[0]);
  mNames := TDUnitXCommandLine.RunNames(mFound, 0, -1, -1);
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests', mNames[0]);
  Assert.AreEqual(0, Integer(Length(TDUnitXCommandLine.RunNames(mFound, 1, -1, -1))), 'ungültige Fixture');
  Assert.AreEqual(0, Integer(Length(TDUnitXCommandLine.RunNames(mFound, 0, 5, -1))), 'ungültiger Test');
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]', '  TT = class',
    '  public',
    '    [Test] procedure Eins;',
    '    [TestCase(''A'', ''1'')]',
    '    [Ignore(''später'')]',
    '    procedure Spaeter(X: Integer);',
    '  end;',
    '  [TestFixture]', '  TTMehr = class',
    '  public',
    '    [Test] procedure Zwei;',
    '  end;',
    'implementation', 'end.']);
  // TT ist der Anfang von TTMehr: U.TT liefe beide; also die Tests von TT einzeln.
  mNames := TDUnitXCommandLine.RunNames(mFound, 0, -1, -1);
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('U.TT.Eins', mNames[0]);
  Assert.AreEqual('U.TT.Spaeter', mNames[1], '[Ignore] mit Fällen: ein Test ohne Fall');
  mNames := TDUnitXCommandLine.RunNames(mFound, 0, 1, 0);
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual('U.TT.Spaeter', mNames[0]);
  mNames := TDUnitXCommandLine.RunNames(mFound, 1, -1, -1);
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual('U.TTMehr', mNames[0]);
end;

procedure TDUnitXSourceTests.FingerprintIgnoresWhitespaceAndComments;
var
  mBase: string;
begin
  mBase := TDUnitXSource.Fingerprint(['begin', '  Assert.AreEqual(4, Summe(2, 2));', 'end;'], 0, 2);
  Assert.AreNotEqual('', mBase);
  Assert.AreEqual(mBase, TDUnitXSource.Fingerprint(['begin Assert.AreEqual( 4,Summe(2,2) ) ;', 'end;'], 0, 1),
    'nur Leerraum und Zeilenumbrüche');
  Assert.AreEqual(mBase, TDUnitXSource.Fingerprint(['begin', '  // Prüft die Summe', '  { alt }',
    '  Assert.AreEqual(4, Summe(2, 2)); (* mehrzeilig', '  noch Kommentar *)', 'end;'], 0, 5), 'Kommentare');
  Assert.AreEqual(mBase, TDUnitXSource.Fingerprint(['unit X;', 'begin', 'Assert.AreEqual(4, Summe(2, 2));',
    'end;', 'end.'], 1, 3), 'nur die Zeilen des Bereichs');
  Assert.AreEqual('', TDUnitXSource.Fingerprint(['begin'], -1, 0), 'ungültiger Bereich');
  Assert.AreEqual('', TDUnitXSource.Fingerprint(['begin'], 2, 3), 'hinter dem Ende');
end;

procedure TDUnitXSourceTests.FingerprintSeesCodeStringsAndDirectives;
var
  mBase: string;
begin
  mBase := TDUnitXSource.Fingerprint(['begin', '  X := ''a b'';', 'end;'], 0, 2);
  Assert.AreNotEqual(mBase, TDUnitXSource.Fingerprint(['begin', '  X := ''ab'';', 'end;'], 0, 2),
    'Leerraum in Zeichenketten zählt');
  Assert.AreNotEqual(mBase, TDUnitXSource.Fingerprint(['begin', '  X := ''a b'';', '  Y := 1;', 'end;'], 0, 3),
    'neue Anweisung');
  Assert.AreNotEqual(TDUnitXSource.Fingerprint(['if A or B then'], 0, 0),
    TDUnitXSource.Fingerprint(['if AorB then'], 0, 0), 'Leerraum zwischen Wörtern trennt');
  Assert.AreNotEqual(TDUnitXSource.Fingerprint(['{$IFDEF X}', 'Y;', '{$ENDIF}'], 0, 2),
    TDUnitXSource.Fingerprint(['{$IFNDEF X}', 'Y;', '{$ENDIF}'], 0, 2), 'Direktiven zählen');
  Assert.AreEqual(TDUnitXSource.Fingerprint(['X := ''it''''s'';'], 0, 0),
    TDUnitXSource.Fingerprint(['X  :=  ''it''''s'' ;'], 0, 0), 'verdoppeltes Anführungszeichen');
  Assert.AreNotEqual(TDUnitXSource.Fingerprint(['X := ''{a}'';'], 0, 0),
    TDUnitXSource.Fingerprint(['X := ''{b}'';'], 0, 0), 'Klammern in Zeichenketten sind kein Kommentar');
end;

procedure TDUnitXSourceTests.UsedUnitsOfBothClauses;
var
  mUnits: TArray<string>;
begin
  mUnits := TDUnitXSource.UsedUnits(['unit Rechner.Tests;', 'interface', 'uses',
    '  DUnitX.TestFramework, // Kommentar', '  Rechner in ''..\Src\Rechner.pas'';', 'implementation',
    'uses System.SysUtils, { Liste } &Type.Helfer;', 'end.']);
  Assert.AreEqual(4, Integer(Length(mUnits)));
  Assert.AreEqual('DUnitX.TestFramework', mUnits[0]);
  Assert.AreEqual('Rechner', mUnits[1]);
  Assert.AreEqual('System.SysUtils', mUnits[2]);
  Assert.AreEqual('Type.Helfer', mUnits[3]);
  Assert.AreEqual(0, Integer(Length(TDUnitXSource.UsedUnits(['unit X;', 'interface', 'implementation', 'end.']))));
end;

procedure TDUnitXSourceTests.CategoriesOfFixtureAndTest;
var
  mFound: TDUnitXUnit;
begin
  mFound := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]',
    '  [Category(''Modul, Langsam'')]',
    '  TT = class',
    '  public',
    '    [Test]',
    '    [Category(''Benchmark'')]',
    '    [Category(''Benchmark,,Netz'')]',
    '    procedure Messen;',
    '    [Test]',
    '    [Category(cKonstante)]',
    '    procedure Ohne;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(2, Integer(Length(mFound.Fixtures[0].Categories)));
  Assert.AreEqual('Modul', mFound.Fixtures[0].Categories[0]);
  Assert.AreEqual('Langsam', mFound.Fixtures[0].Categories[1], 'getrimmt');
  Assert.AreEqual(2, mFound.TestCount);
  Assert.AreEqual(2, Integer(Length(mFound.Fixtures[0].Tests[0].Categories)), 'ohne doppelte und leere');
  Assert.AreEqual('Benchmark', mFound.Fixtures[0].Tests[0].Categories[0]);
  Assert.AreEqual('Netz', mFound.Fixtures[0].Tests[0].Categories[1]);
  Assert.AreEqual(0, Integer(Length(mFound.Fixtures[0].Tests[1].Categories)), 'Konstante: nicht erkannt');
end;

procedure TDUnitXSourceTests.OptionsGoBesideRun;
var
  mArguments: TArray<string>;
begin
  mArguments := TDUnitXCommandLine.Arguments('r.xml', ['--exclude:Benchmark', 'A.T']);
  Assert.AreEqual(4, Integer(Length(mArguments)));
  Assert.AreEqual('--exclude:Benchmark', mArguments[2]);
  Assert.AreEqual('--run:A.T', mArguments[3]);
  mArguments := TDUnitXCommandLine.Arguments('r.xml', ['--include:Netz']);
  Assert.AreEqual(3, Integer(Length(mArguments)), 'nur Option: alle Tests der Kategorie, kein --run');
  Assert.AreEqual('--include:Netz', mArguments[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXSourceTests);

end.
