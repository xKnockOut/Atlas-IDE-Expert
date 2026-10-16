unit Atlas.Text.DUnitX.Tests;

// Tests der DUnitX-Erkennung im Quelltext (#69, gemeinsamer Baustein mit #154
// und #585): Attributnamen, Fixtures über Attribut und Registrierung, Tests
// über [Test], [TestCase] und published, keine Tests bei [Setup] und
// [Test(False)], Zeilen von Attribut, Deklaration und Rumpf, Befehlszeile.

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
  Assert.AreEqual(1, Length(Found.Fixtures));
  Assert.AreEqual('TRechnerTests', Found.Fixtures[0].Name);
  Assert.AreEqual(9, Found.Fixtures[0].Line);
  Assert.AreEqual(8, Found.Fixtures[0].AttributeLine);
  Assert.AreEqual(2, Length(Found.Fixtures[0].Tests), 'Addiert und Summe; Setup und Hilfe nicht');
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
  Assert.AreEqual(2, Length(Test.Cases));
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
  Assert.AreEqual(1, Length(Found.Fixtures));
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
  Assert.AreEqual(1, Length(Found.Fixtures), 'THelfer ist weder markiert noch registriert');
  Assert.AreEqual('TT', Found.Fixtures[0].Name);
  Assert.AreEqual(1, Length(Found.Fixtures[0].Tests), 'Methoden innerer Klassen zählen nicht');
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
  Assert.AreEqual(1, Length(Found.Fixtures));
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
  Assert.AreEqual(2, Length(Arguments));
  Assert.AreEqual('--exitbehavior:Continue', Arguments[0]);
  Assert.AreEqual('--xmlfile:C:\Temp\r.xml', Arguments[1]);
  Arguments := TDUnitXCommandLine.Arguments('r.xml', ['A.T.X', '', 'A.T.Y']);
  Assert.AreEqual(3, Length(Arguments));
  Assert.AreEqual('--run:A.T.X,A.T.Y', Arguments[2]);
  Arguments := TDUnitXCommandLine.Arguments('r.xml', [StringOfChar('x', TDUnitXCommandLine.MaxRunLength + 1)]);
  Assert.AreEqual(2, Length(Arguments), 'zu lang: alle Tests');
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXSourceTests);

end.
