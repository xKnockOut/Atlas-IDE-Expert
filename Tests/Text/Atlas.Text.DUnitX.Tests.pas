unit Atlas.Text.DUnitX.Tests;

// Tests der DUnitX-Erkennung im Quelltext (#69, gemeinsamer Baustein mit #154
// und #585): Attributnamen, Fixtures über Attribut und Registrierung, Tests
// über [Test], [TestCase] und published, keine Tests bei [Setup] und
// [Test(False)], Zeilen von Attribut, Deklaration und Rumpf, Befehlszeile;
// für #585 Rumpf bis end (lokale Routinen, Typen), Zeilen der Testfälle,
// Test an einer Zeile, Marken und Namen für --run je Fall.

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
  Assert.IsTrue(TDUnitXSource.AttributeOf('TestFixture') = TDUnitXAttribute.TestFixture);
  Assert.IsTrue(TDUnitXSource.AttributeOf('TestFixtureAttribute') = TDUnitXAttribute.TestFixture);
  Assert.IsTrue(TDUnitXSource.AttributeOf('DUnitX.Attributes.TestFixture') = TDUnitXAttribute.TestFixture);
  Assert.IsTrue(TDUnitXSource.AttributeOf('test') = TDUnitXAttribute.Test);
  Assert.IsTrue(TDUnitXSource.AttributeOf('TestCase') = TDUnitXAttribute.TestCase);
  Assert.IsTrue(TDUnitXSource.AttributeOf('IgnoreAttribute') = TDUnitXAttribute.Ignore);
  Assert.IsTrue(TDUnitXSource.AttributeOf('Category') = TDUnitXAttribute.Category);
  Assert.IsTrue(TDUnitXSource.AttributeOf('SetupFixture') = TDUnitXAttribute.SetupFixture);
  Assert.IsTrue(TDUnitXSource.AttributeOf('TearDown') = TDUnitXAttribute.TearDown);
  Assert.IsTrue(TDUnitXSource.AttributeOf('Weak') = TDUnitXAttribute.None);
  Assert.IsTrue(TDUnitXSource.AttributeOf('Attribute') = TDUnitXAttribute.None, 'nur die Endung');
end;

procedure TDUnitXSourceTests.FindsFixtureTestsAndLines;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.AreEqual('Rechner.Tests', Found.UnitName);
  Assert.AreEqual(1, Integer(Length(Found.Fixtures)));
  Assert.AreEqual('TRechnerTests', Found.Fixtures[0].Name);
  Assert.AreEqual(9, Found.Fixtures[0].Line);
  Assert.AreEqual(8, Found.Fixtures[0].AttributeLine);
  Assert.AreEqual(2, Integer(Length(Found.Fixtures[0].Tests)), 'Addiert und Summe; Setup und Hilfe nicht');
  Assert.AreEqual(2, Found.TestCount);
  Assert.AreEqual('Addiert', Found.Fixtures[0].Tests[0].Method);
  Assert.AreEqual(16, Found.Fixtures[0].Tests[0].Line);
  Assert.AreEqual(15, Found.Fixtures[0].Tests[0].AttributeLine);
  Assert.AreEqual(30, Found.Fixtures[0].Tests[0].BodyLine);
  Assert.AreEqual('Summe', Found.Fixtures[0].Tests[1].Method);
  Assert.AreEqual(17, Found.Fixtures[0].Tests[1].AttributeLine);
  Assert.AreEqual(35, Found.Fixtures[0].Tests[1].BodyLine);
end;

procedure TDUnitXSourceTests.TestCasesAndIgnore;
var
  Found: TDUnitXUnit;
  Test: TDUnitXTest;
begin
  Found := TDUnitXSource.Scan(Sample);
  Test := Found.Fixtures[0].Tests[1];
  Assert.AreEqual(2, Integer(Length(Test.Cases)));
  Assert.AreEqual('Klein', Test.Cases[0]);
  Assert.AreEqual('Gross', Test.Cases[1]);
  Assert.IsFalse(Test.Ignored);
  Found := TDUnitXSource.Scan([
    'unit U;', 'interface', 'type',
    '  [TestFixture]', '  TT = class',
    '  public',
    '    [Test, Ignore(''später'')]',
    '    procedure Spaeter;',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual(1, Found.TestCount);
  Assert.IsTrue(Found.Fixtures[0].Tests[0].Ignored);
  Assert.AreEqual(-1, Found.Fixtures[0].Tests[0].BodyLine, 'ohne Rumpf');
end;

procedure TDUnitXSourceTests.SetupAndDisabledTestsAreNoTests;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(1, Found.TestCount);
  Assert.AreEqual('An', Found.Fixtures[0].Tests[0].Method);
  Assert.AreEqual(10, Found.Fixtures[0].Tests[0].Line);
  Assert.AreEqual(10, Found.Fixtures[0].Tests[0].AttributeLine, 'Attribut in derselben Zeile');
end;

procedure TDUnitXSourceTests.RegisteredClassWithoutAttributeIsFixture;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(1, Integer(Length(Found.Fixtures)));
  Assert.AreEqual(4, Found.Fixtures[0].AttributeLine, 'ohne Attribut die Klassenzeile');
  Assert.AreEqual(10, Found.Fixtures[0].Tests[0].BodyLine);
end;

procedure TDUnitXSourceTests.ClassWithoutFixtureIsIgnored;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(1, Integer(Length(Found.Fixtures)), 'THelfer ist weder markiert noch registriert');
  Assert.AreEqual('TT', Found.Fixtures[0].Name);
  Assert.AreEqual(1, Integer(Length(Found.Fixtures[0].Tests)), 'Methoden innerer Klassen zählen nicht');
  Assert.AreEqual('Aussen', Found.Fixtures[0].Tests[0].Method);
end;

procedure TDUnitXSourceTests.PublishedMethodsAreTests;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(1, Found.TestCount);
  Assert.AreEqual('OhneAttribut', Found.Fixtures[0].Tests[0].Method);
end;

procedure TDUnitXSourceTests.CommentsAndStringsAreSkipped;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(1, Integer(Length(Found.Fixtures)));
  Assert.AreEqual(1, Found.TestCount);
  Assert.AreEqual('A;b', Found.Fixtures[0].Tests[0].Cases[0]);
  Assert.AreEqual(13, Found.Fixtures[0].Tests[0].BodyLine);
end;

procedure TDUnitXSourceTests.FieldAttributeDoesNotMakeTest;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(1, Found.TestCount, '[Test] am Feld gilt nicht für die nächste Methode');
  Assert.AreEqual('Langsam', Found.Fixtures[0].Tests[0].Method);
  Assert.AreEqual(9, Found.Fixtures[0].Tests[0].AttributeLine, 'erstes Attribut');
end;

procedure TDUnitXSourceTests.AtLineFindsFixtureAndTest;
var
  Found: TDUnitXUnit;
  FixtureIndex, TestIndex: Integer;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.IsTrue(Found.AtLine(8, FixtureIndex, TestIndex));
  Assert.AreEqual(0, FixtureIndex);
  Assert.AreEqual(-1, TestIndex);
  Assert.IsTrue(Found.AtLine(16, FixtureIndex, TestIndex));
  Assert.AreEqual(0, TestIndex);
  Assert.IsTrue(Found.AtLine(17, FixtureIndex, TestIndex));
  Assert.AreEqual(1, TestIndex);
  Assert.IsFalse(Found.AtLine(14, FixtureIndex, TestIndex), 'Setup ist kein Test');
  Assert.IsTrue(Found.Find('trechnertests', 'SUMME', FixtureIndex, TestIndex));
  Assert.AreEqual(1, TestIndex);
  Assert.IsTrue(Found.Find('TRechnerTests', '', FixtureIndex, TestIndex));
  Assert.AreEqual(-1, TestIndex);
  Assert.IsFalse(Found.Find('TAndere', 'Addiert', FixtureIndex, TestIndex));
  // Zeile eines Ergebnisses: Methodenkopf, sonst Fixture.
  Assert.AreEqual(35, Found.LineOf('TRechnerTests', 'Summe'));
  Assert.AreEqual(9, Found.LineOf('TRechnerTests', 'Unbekannt'), 'unbekannte Methode: Fixture');
  Assert.AreEqual(9, Found.LineOf('TRechnerTests', ''));
  Assert.AreEqual(-1, Found.LineOf('TAndere', 'Addiert'));
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
  Arguments: TArray<string>;
begin
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Addiert',
    TDUnitXCommandLine.TestName('Rechner.Tests', 'TRechnerTests', 'Addiert'));
  Assert.AreEqual('Rechner.Tests.TRechnerTests', TDUnitXCommandLine.TestName('Rechner.Tests', 'TRechnerTests', ''));
  Arguments := TDUnitXCommandLine.Arguments('C:\Temp\r.xml', nil);
  Assert.AreEqual(2, Integer(Length(Arguments)));
  Assert.AreEqual('--exitbehavior:Continue', Arguments[0]);
  Assert.AreEqual('--xmlfile:C:\Temp\r.xml', Arguments[1]);
  Arguments := TDUnitXCommandLine.Arguments('r.xml', ['A.T.X', '', 'A.T.Y']);
  Assert.AreEqual(3, Integer(Length(Arguments)));
  Assert.AreEqual('--run:A.T.X,A.T.Y', Arguments[2]);
  Arguments := TDUnitXCommandLine.Arguments('r.xml', [StringOfChar('x', TDUnitXCommandLine.MaxRunLength + 1)]);
  Assert.AreEqual(2, Integer(Length(Arguments)), 'zu lang: alle Tests');
end;

procedure TDUnitXSourceTests.BodyRangeSkipsLocalRoutinesAndTypes;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.AreEqual(32, Found.Fixtures[0].Tests[0].BeginLine, 'erste Anweisung');
  Assert.AreEqual(33, Found.Fixtures[0].Tests[0].EndLine);
  Assert.AreEqual(36, Found.Fixtures[0].Tests[1].BeginLine, 'ohne Anweisung: begin');
  Assert.AreEqual(37, Found.Fixtures[0].Tests[1].EndLine);
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(3, Found.TestCount);
  Assert.AreEqual(11, Found.Fixtures[0].Tests[0].BodyLine);
  Assert.AreEqual(22, Found.Fixtures[0].Tests[0].BeginLine, 'nach lokaler Routine und Typen');
  Assert.AreEqual(23, Found.Fixtures[0].Tests[0].EndLine);
  Assert.AreEqual(26, Found.Fixtures[0].Tests[1].BeginLine);
  Assert.AreEqual(32, Found.Fixtures[0].Tests[1].EndLine, 'try und case haben ein eigenes end');
  Assert.AreEqual(-1, Found.Fixtures[0].Tests[2].BeginLine, 'ohne Rumpf');
  Assert.AreEqual(-1, Found.Fixtures[0].Tests[2].EndLine);
end;

procedure TDUnitXSourceTests.CaseLinesAndMarks;
var
  Found: TDUnitXUnit;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.AreEqual(2, Integer(Length(Found.Fixtures[0].Tests[1].CaseLines)));
  Assert.AreEqual(18, Found.Fixtures[0].Tests[1].CaseLines[0]);
  Assert.AreEqual(19, Found.Fixtures[0].Tests[1].CaseLines[1]);
  Assert.IsTrue(Found.CaseHasOwnLine(0, 1, 0));
  Assert.IsTrue(Found.CaseHasOwnLine(0, 1, 1));
  Assert.IsFalse(Found.CaseHasOwnLine(0, 1, 2), 'ungültiger Fall');
  Assert.AreEqual(8, Found.MarkLine(0, -1), 'Fixture: ihr Attribut');
  Assert.AreEqual(15, Found.MarkLine(0, 0), 'Test: sein Attribut');
  Assert.AreEqual(17, Found.MarkLine(0, 1), '[Test] vor den Fällen');
  Assert.AreEqual(-1, Found.MarkLine(1, -1));
  Found := TDUnitXSource.Scan([
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
  Assert.AreEqual(3, Found.TestCount);
  Assert.AreEqual(8, Found.MarkLine(0, 0), 'erster Fall hat die Zeile: Marke des Tests an der Deklaration');
  Assert.IsFalse(Found.CaseHasOwnLine(0, 1, 0), 'zwei Fälle in einer Zeile');
  Assert.AreEqual(9, Found.MarkLine(0, 1), 'Fälle ohne eigene Zeile: Marke am Attribut');
  Assert.IsFalse(Found.CaseHasOwnLine(0, 2, 0), 'Fall in der Zeile der Deklaration');
  Assert.AreEqual(11, Found.MarkLine(0, 2), 'eine Marke für den Test');
end;

procedure TDUnitXSourceTests.TestAtFindsCaseTestFixtureAndBody;
var
  Found: TDUnitXUnit;
  FixtureIndex, TestIndex, CaseIndex: Integer;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.IsTrue(Found.TestAt(8, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(0, FixtureIndex);
  Assert.AreEqual(-1, TestIndex, 'Fixture');
  Assert.IsTrue(Found.TestAt(9, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(-1, TestIndex);
  Assert.IsTrue(Found.TestAt(18, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(1, TestIndex);
  Assert.AreEqual(0, CaseIndex, 'Zeile des Falls Klein');
  Assert.IsTrue(Found.TestAt(19, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(1, CaseIndex);
  Assert.IsTrue(Found.TestAt(17, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(1, TestIndex);
  Assert.AreEqual(-1, CaseIndex, '[Test]: alle Fälle');
  Assert.IsTrue(Found.TestAt(20, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(-1, CaseIndex);
  Assert.IsTrue(Found.TestAt(32, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(0, TestIndex, 'im Rumpf von Addiert');
  Assert.IsTrue(Found.TestAt(30, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(0, TestIndex, 'Methodenkopf');
  Assert.IsTrue(Found.TestAt(37, FixtureIndex, TestIndex, CaseIndex));
  Assert.AreEqual(1, TestIndex, 'end von Summe');
  Assert.IsFalse(Found.TestAt(14, FixtureIndex, TestIndex, CaseIndex), 'Setup ist kein Test');
  Assert.IsFalse(Found.TestAt(27, FixtureIndex, TestIndex, CaseIndex), 'Rumpf von Setup');
  Assert.IsFalse(Found.TestAt(40, FixtureIndex, TestIndex, CaseIndex), 'Rumpf von Hilfe');
  Assert.IsFalse(Found.TestAt(34, FixtureIndex, TestIndex, CaseIndex), 'zwischen den Rümpfen');
  Assert.AreEqual(-1, FixtureIndex);
  Assert.AreEqual(-1, TestIndex);
end;

procedure TDUnitXSourceTests.RunNamesPerCaseAndFixture;
var
  Found: TDUnitXUnit;
  Names: TArray<string>;
begin
  Assert.AreEqual('U.TT.M.Fall', TDUnitXCommandLine.CaseName('U', 'TT', 'M', 'Fall'));
  Assert.AreEqual('U.TT.M(1,2)', TDUnitXCommandLine.CaseName('U', 'TT', 'M', '(1,2)'), 'AutoNameTestCase');
  Assert.AreEqual('U.TT.M', TDUnitXCommandLine.CaseName('U', 'TT', 'M', ''));
  Found := TDUnitXSource.Scan(Sample);
  Names := TDUnitXCommandLine.RunNames(Found, 0, 0, -1);
  Assert.AreEqual(1, Integer(Length(Names)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Addiert', Names[0]);
  // [TestCase]: Unit.Fixture.Methode trifft keinen Fall, darum je Fall ein Name.
  Names := TDUnitXCommandLine.RunNames(Found, 0, 1, -1);
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Klein', Names[0]);
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', Names[1]);
  Names := TDUnitXCommandLine.RunNames(Found, 0, 1, 1);
  Assert.AreEqual(1, Integer(Length(Names)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', Names[0]);
  Names := TDUnitXCommandLine.RunNames(Found, 0, -1, -1);
  Assert.AreEqual(1, Integer(Length(Names)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests', Names[0]);
  Assert.AreEqual(0, Integer(Length(TDUnitXCommandLine.RunNames(Found, 1, -1, -1))), 'ungültige Fixture');
  Assert.AreEqual(0, Integer(Length(TDUnitXCommandLine.RunNames(Found, 0, 5, -1))), 'ungültiger Test');
  Found := TDUnitXSource.Scan([
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
  Names := TDUnitXCommandLine.RunNames(Found, 0, -1, -1);
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('U.TT.Eins', Names[0]);
  Assert.AreEqual('U.TT.Spaeter', Names[1], '[Ignore] mit Fällen: ein Test ohne Fall');
  Names := TDUnitXCommandLine.RunNames(Found, 0, 1, 0);
  Assert.AreEqual(1, Integer(Length(Names)));
  Assert.AreEqual('U.TT.Spaeter', Names[0]);
  Names := TDUnitXCommandLine.RunNames(Found, 1, -1, -1);
  Assert.AreEqual(1, Integer(Length(Names)));
  Assert.AreEqual('U.TTMehr', Names[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXSourceTests);

end.
