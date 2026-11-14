unit Atlas.Common.Editing.TestDrafts.Tests;

// Tests für den Entwurf eines Testfalls (#1226): Methode an der Zeile finden,
// Kopf lesen, Platzhalter je Typ, Aufruf über Objekt, Klasse oder lokales
// Objekt, WillRaise mit Werten (#1873) und Eintragen in eine Testunit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDraftsTests = class
  public
    [Test]
    procedure PlaceholdersPerType;
    [Test]
    procedure LocalNameAvoidsReservedWordsAndTakenNames;
    [Test]
    procedure DraftAtReadsMethodFromBodyAndDeclaration;
    [Test]
    procedure DraftAtSkipsConstructorsRecordsAndOtherLines;
    [Test]
    procedure MethodTextCallsSubjectWithLocals;
    [Test]
    procedure ClassMethodIsCalledViaClass;
    [Test]
    procedure LocalSubjectIsFreedInFinally;
    [Test]
    procedure RaisesWithValuesAndFields;
    [Test]
    procedure BareDraftOnlyFails;
    [Test]
    procedure NonPublicRoutinesAreBare;
    [Test]
    procedure AddToTestUnitNumbersAndUsesSubjectField;
    [Test]
    procedure AddToTestUnitWithoutFixtureFails;
    [Test]
    procedure ParameterizedWithTestCases;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.TestDrafts;

const
  cKundenText =
    'unit Kunden;'#13#10 +                                                              // 0
    'interface'#13#10 +                                                                 // 1
    'type'#13#10 +                                                                      // 2
    '  TKunde = class'#13#10 +                                                          // 3
    '  public'#13#10 +                                                                  // 4
    '    constructor Create;'#13#10 +                                                   // 5
    '    function Berechne(const AMenge: Integer; var AName: string; AFaktor: Double): Double;'#13#10 + // 6
    '    class function Neu(const AText: string): TKunde;'#13#10 +                      // 7
    '  end;'#13#10 +                                                                    // 8
    '  TPunkt = record'#13#10 +                                                         // 9
    '    function Laenge: Double;'#13#10 +                                              // 10
    '  end;'#13#10 +                                                                    // 11
    'function Summe(A, B: Integer): Integer;'#13#10 +                                  // 12
    'implementation'#13#10 +                                                            // 13
    'constructor TKunde.Create;'#13#10 +                                                // 14
    'begin'#13#10 +                                                                     // 15
    'end;'#13#10 +                                                                      // 16
    'function TKunde.Berechne(const AMenge: Integer; var AName: string; AFaktor: Double): Double;'#13#10 + // 17
    'begin'#13#10 +                                                                     // 18
    '  Result := AMenge * AFaktor;'#13#10 +                                             // 19
    'end;'#13#10 +                                                                      // 20
    'class function TKunde.Neu(const AText: string): TKunde;'#13#10 +                   // 21
    'begin'#13#10 +                                                                     // 22
    '  Result := TKunde.Create;'#13#10 +                                                // 23
    'end;'#13#10 +                                                                      // 24
    'function TPunkt.Laenge: Double;'#13#10 +                                           // 25
    'begin'#13#10 +                                                                     // 26
    '  Result := 0;'#13#10 +                                                            // 27
    'end;'#13#10 +                                                                      // 28
    'function Summe(A, B: Integer): Integer;'#13#10 +                                  // 29
    'begin'#13#10 +                                                                     // 30
    '  Result := A + B;'#13#10 +                                                        // 31
    'end;'#13#10 +                                                                      // 32
    'end.'#13#10;

  cTestUnitText =
    'unit Kunden.Tests;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'type'#13#10 +
    '  [TestFixture]'#13#10 +
    '  TKundeTests = class'#13#10 +
    '  private'#13#10 +
    '    FKunde: TKunde;'#13#10 +
    '  public'#13#10 +
    '    [Test]'#13#10 +
    '    procedure TestBerechne;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TKundeTests.TestBerechne;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'initialization'#13#10 +
    '  TDUnitX.RegisterTestFixture(TKundeTests);'#13#10 +
    'end.'#13#10;

function DraftAt(ALine: Integer; out ADraft: TTestDraft): Boolean;
begin
  Result := TTestDrafts.DraftAt(cKundenText, TPascalLexer.Tokenize(cKundenText),
    TIndexExtractor.ExtractText(cKundenText, 'Kunden.pas', nil), ALine, ADraft);
  ADraft.Fixture := 'TKundeTests';
  ADraft.UnitName := 'Kunden';
end;

/// <summary>Der Rumpf AMethod in einer Testunit parst ohne Fehler.</summary>
function Parses(const AMethod: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse('unit T;'#13#10'interface'#13#10'implementation'#13#10 + AMethod + #13#10'end.');
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TTestDraftsTests.PlaceholdersPerType;
begin
  Assert.AreEqual('0', TTestDrafts.Placeholder('Integer'));
  Assert.AreEqual('0', TTestDrafts.Placeholder('Double'));
  Assert.AreEqual('''''', TTestDrafts.Placeholder('string'));
  Assert.AreEqual('#0', TTestDrafts.Placeholder('Char'));
  Assert.AreEqual('False', TTestDrafts.Placeholder('Boolean'));
  Assert.AreEqual('nil', TTestDrafts.Placeholder('IKundenRepo'));
  Assert.AreEqual('nil', TTestDrafts.Placeholder('TArray<Integer>'));
  Assert.AreEqual('Default(TKunde)', TTestDrafts.Placeholder('TKunde'));
end;

procedure TTestDraftsTests.LocalNameAvoidsReservedWordsAndTakenNames;
begin
  Assert.AreEqual('Menge', TTestDrafts.LocalName('AMenge', nil));
  Assert.AreEqual('AType', TTestDrafts.LocalName('AType', nil), 'type ist reserviert');
  Assert.AreEqual('Wert', TTestDrafts.LocalName('Wert', nil));
  Assert.AreEqual('AActual', TTestDrafts.LocalName('AActual', ['Actual']));
  Assert.AreEqual('Actual2', TTestDrafts.LocalName('Actual', ['Actual']));
  Assert.AreEqual('Alpha', TTestDrafts.LocalName('Alpha', nil), 'A ohne Großbuchstaben danach bleibt');
end;

procedure TTestDraftsTests.DraftAtReadsMethodFromBodyAndDeclaration;
var
  mDraft: TTestDraft;
begin
  Assert.IsTrue(DraftAt(19, mDraft), 'im Rumpf');
  Assert.AreEqual('TKunde', mDraft.ClassName);
  Assert.AreEqual('Berechne', mDraft.MethodName);
  Assert.AreEqual('TestBerechne', mDraft.TestName);
  Assert.AreEqual('Double', mDraft.ResultType);
  Assert.AreEqual(3, Integer(Length(mDraft.Parameters)));
  Assert.AreEqual('AName', mDraft.Parameters[1].Name);
  Assert.AreEqual('var', mDraft.Parameters[1].Modifier);
  Assert.AreEqual('string', mDraft.Parameters[1].TypeName);
  Assert.IsFalse(mDraft.ClassMethod);
  Assert.IsTrue(mDraft.Draft);
  Assert.IsTrue(DraftAt(6, mDraft), 'an der Deklaration');
  Assert.AreEqual('Berechne', mDraft.MethodName);
  Assert.IsTrue(DraftAt(22, mDraft), 'Klassenmethode');
  Assert.IsTrue(mDraft.ClassMethod);
  Assert.AreEqual('TKunde', mDraft.ResultType);
  Assert.IsTrue(DraftAt(31, mDraft), 'Routine');
  Assert.AreEqual('', mDraft.ClassName);
  Assert.AreEqual('Summe', mDraft.MethodName);
  Assert.AreEqual(2, Integer(Length(mDraft.Parameters)));
end;

procedure TTestDraftsTests.DraftAtSkipsConstructorsRecordsAndOtherLines;
var
  mDraft: TTestDraft;
begin
  Assert.IsFalse(DraftAt(15, mDraft), 'Konstruktor');
  Assert.IsFalse(DraftAt(5, mDraft), 'Konstruktor an der Deklaration');
  Assert.IsFalse(DraftAt(27, mDraft), 'Methode eines Records');
  Assert.IsFalse(DraftAt(2, mDraft), 'type');
end;

procedure TTestDraftsTests.MethodTextCallsSubjectWithLocals;
var
  mDraft: TTestDraft;
  mText: string;
begin
  Assert.IsTrue(DraftAt(19, mDraft));
  mDraft.Subject := 'FSubject';
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(StartsStr('procedure TKundeTests.TestBerechne;'#13#10'var'#13#10 +
    '  Menge: Integer;'#13#10'  Name: string;'#13#10'  Faktor: Double;'#13#10'  Actual: Double;'#13#10'begin', mText),
    mText);
  Assert.IsTrue(ContainsStr(mText, '  Menge := 0;'#13#10'  Name := '''';'#13#10'  Faktor := 0;'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Actual := FSubject.Berechne(Menge, Name, Faktor);'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Assert.AreEqual(0.0, Actual, 1E-9);'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Assert.AreEqual('''', Name);'), 'var-Parameter wird geprüft: ' + mText);
  // Ohne Umlaute im Vergleich: Das FPC-Testprogramm liest Literale mit anderer Codepage.
  Assert.IsTrue(ContainsStr(mText, '  Assert.Fail(''Entwurf f'), mText);
  Assert.IsTrue(ContainsStr(mText, ' TKunde.Berechne: erwartete Werte eintragen und diese Zeile l'), mText);
  Assert.IsTrue(EndsStr('schen'');'#13#10'end;', mText), mText);
  Assert.IsFalse(ContainsStr(mText, 'try'), mText);
end;

procedure TTestDraftsTests.ClassMethodIsCalledViaClass;
var
  mDraft: TTestDraft;
  mText: string;
begin
  Assert.IsTrue(DraftAt(22, mDraft));
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '  Actual := TKunde.Neu(Text);'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Assert.AreEqual<TKunde>(Default(TKunde), Actual);'), mText);
  Assert.IsFalse(ContainsStr(mText, 'Subject'), mText);
  Assert.IsTrue(DraftAt(31, mDraft));
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(ContainsStr(mText, '  Actual := Summe(A, B);'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Assert.AreEqual(0, Actual);'), mText);
end;

procedure TTestDraftsTests.LocalSubjectIsFreedInFinally;
var
  mDraft: TTestDraft;
  mText: string;
begin
  Assert.IsTrue(DraftAt(19, mDraft));
  mDraft.CreateText := 'TKunde.Create';
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '  Subject: TKunde;'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Subject := TKunde.Create;'#13#10'  try'#13#10), mText);
  Assert.IsTrue(ContainsStr(mText, '    Actual := Subject.Berechne(Menge, Name, Faktor);'), mText);
  Assert.IsTrue(ContainsStr(mText, '  finally'#13#10'    Subject.Free;'#13#10'  end;'#13#10'end;'), mText);
  mDraft.CreateText := '';
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '  Subject := nil; // '), mText);
end;

procedure TTestDraftsTests.RaisesWithValuesAndFields;
var
  mDraft: TTestDraft;
  mField: TTestDraftValue;
  mText: string;
begin
  Assert.IsTrue(DraftAt(19, mDraft));
  mDraft.Subject := 'FSubject';
  mDraft.Draft := False;
  mDraft.Kind := TTestDraftKind.Raises;
  mDraft.ExceptionClass := 'EConvertError';
  mDraft.Comment := 'Aus Debug-Halt, EConvertError';
  mDraft.Parameters[0].Value := '12';
  mDraft.Parameters[1].Value := '''12,5 kg''';
  mDraft.Parameters[2].Todo := True;
  mField := TTestDraftValue.Create('Einheit', 'string', '', '''kg''');
  mDraft.Fields := [mField];
  mField := TTestDraftValue.Create('FIntern', 'Integer', '', '3');
  mField.Accessible := False;
  mDraft.Fields := mDraft.Fields + [mField];
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, 'begin'#13#10'  // Aus Debug-Halt, EConvertError'#13#10), mText);
  Assert.IsTrue(ContainsStr(mText, '  Menge := 12;'#13#10'  Name := ''12,5 kg'';'#13#10 +
    '  Faktor := 0; // TODO: Faktor aufbauen (Double)'), mText);
  Assert.IsTrue(ContainsStr(mText, '  FSubject.Einheit := ''kg'';'), mText);
  Assert.IsTrue(ContainsStr(mText, '  // FIntern = 3 (nicht zug'), mText);
  Assert.IsTrue(ContainsStr(mText, '  Assert.WillRaise('#13#10'    procedure'#13#10'    begin'#13#10 +
    '      FSubject.Berechne(Menge, Name, Faktor);'#13#10'    end, EConvertError);'#13#10'end;'), mText);
  Assert.IsFalse(ContainsStr(mText, 'Actual'), mText);
  Assert.IsFalse(ContainsStr(mText, 'Assert.Fail'), mText);
end;

procedure TTestDraftsTests.BareDraftOnlyFails;
var
  mDraft: TTestDraft;
  mText: string;
begin
  mDraft := Default(TTestDraft);
  mDraft.Fixture := 'TKundeTests';
  mDraft.TestName := 'TestPruefe';
  mDraft.ClassName := 'TKunde';
  mDraft.MethodName := 'Pruefe';
  mDraft.Bare := True;
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(StartsStr('procedure TKundeTests.TestPruefe;'#13#10'begin'#13#10'  Assert.Fail(', mText), mText);
  Assert.IsTrue(EndsStr(');'#13#10'end;', mText), mText);
end;

procedure TTestDraftsTests.NonPublicRoutinesAreBare;
const
  cText =
    'unit Intern;'#13#10 +                    // 0
    'interface'#13#10 +                       // 1
    'type'#13#10 +                            // 2
    '  TKunde = class'#13#10 +                // 3
    '  private'#13#10 +                       // 4
    '    function Pruefe: Boolean;'#13#10 +   // 5
    '  end;'#13#10 +                          // 6
    'implementation'#13#10 +                  // 7
    'function Hilfe(A: Integer): Integer;'#13#10 + // 8
    'begin'#13#10 +                           // 9
    '  Result := A;'#13#10 +                  // 10
    'end;'#13#10 +                            // 11
    'function TKunde.Pruefe: Boolean;'#13#10 + // 12
    'begin'#13#10 +                           // 13
    '  Result := True;'#13#10 +               // 14
    'end;'#13#10 +                            // 15
    'end.'#13#10;
var
  mDraft: TTestDraft;
  mIndex: TUnitIndex;
begin
  mIndex := TIndexExtractor.ExtractText(cText, 'Intern.pas', nil);
  Assert.IsTrue(TTestDrafts.DraftAt(cText, TPascalLexer.Tokenize(cText), mIndex, 14, mDraft));
  Assert.AreEqual('Pruefe', mDraft.MethodName);
  Assert.IsTrue(mDraft.Bare, 'private Methode');
  Assert.IsTrue(TTestDrafts.DraftAt(cText, TPascalLexer.Tokenize(cText), mIndex, 10, mDraft));
  Assert.AreEqual('Hilfe', mDraft.MethodName);
  Assert.IsTrue(mDraft.Bare, 'Routine nur im implementation-Teil');
end;

procedure TTestDraftsTests.AddToTestUnitNumbersAndUsesSubjectField;
var
  mDraft: TTestDraft;
  mNewText, mName, mReason: string;
begin
  Assert.IsTrue(DraftAt(19, mDraft));
  Assert.IsTrue(TTestDrafts.AddToTestUnit(cTestUnitText, mDraft, False, mNewText, mName, mReason), mReason);
  Assert.AreEqual('TestBerechne2', mName);
  Assert.IsTrue(ContainsStr(mNewText, '    procedure TestBerechne;'#13#10'    [Test]'#13#10 +
    '    procedure TestBerechne2;'#13#10'  end;'), mNewText);
  Assert.IsTrue(ContainsStr(mNewText, '  Actual := FKunde.Berechne(Menge, Name, Faktor);'), mNewText);
  Assert.IsTrue(ContainsStr(mNewText, '  DUnitX.TestFramework,'#13#10'  Kunden;'), mNewText);
  Assert.IsTrue(Pos('procedure TKundeTests.TestBerechne2;', mNewText) < Pos('initialization', mNewText), mNewText);
  // Nur wenn er fehlt: TestBerechne gibt es schon, nichts ändert sich.
  Assert.IsTrue(TTestDrafts.AddToTestUnit(cTestUnitText, mDraft, True, mNewText, mName, mReason), mReason);
  Assert.AreEqual(cTestUnitText, mNewText);
  Assert.AreEqual('TestBerechne', mName);
end;

procedure TTestDraftsTests.AddToTestUnitWithoutFixtureFails;
var
  mDraft: TTestDraft;
  mNewText, mName, mReason: string;
begin
  Assert.IsTrue(DraftAt(19, mDraft));
  Assert.IsFalse(TTestDrafts.AddToTestUnit('unit Leer;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10,
    mDraft, False, mNewText, mName, mReason));
  Assert.AreNotEqual('', mReason);
end;

procedure TTestDraftsTests.ParameterizedWithTestCases;
var
  mDraft: TTestDraft;
  mText, mNewText, mName, mReason: string;
begin
  // Grenzfälle (#2173): Werte als Parameter, Prüfung gegen AExpected, Attribute über der Deklaration.
  Assert.IsTrue(DraftAt(31, mDraft));
  mDraft.Parameterized := True;
  mDraft.TestName := 'TestSummeGrenzen';
  mDraft.Attributes := ['[TestCase(''Eins'', ''1,2,3'')]', '[TestCase(''Null'', ''0,0,0'')]'];
  Assert.AreEqual('(const A: Integer; const B: Integer; const AExpected: Integer)',
    TTestDrafts.ParameterList(mDraft));
  mText := TTestDrafts.MethodText(mDraft, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.AreEqual('procedure TKundeTests.TestSummeGrenzen(const A: Integer; const B: Integer; ' +
    'const AExpected: Integer);'#13#10'var'#13#10'  Actual: Integer;'#13#10'begin'#13#10 +
    '  Actual := Summe(A, B);'#13#10'  Assert.AreEqual(AExpected, Actual);'#13#10'end;', mText);
  Assert.IsTrue(TTestDrafts.AddToTestUnit(cTestUnitText, mDraft, False, mNewText, mName, mReason), mReason);
  Assert.IsTrue(ContainsStr(mNewText, '    procedure TestBerechne;'#13#10'    [TestCase(''Eins'', ''1,2,3'')]'#13#10 +
    '    [TestCase(''Null'', ''0,0,0'')]'#13#10'    procedure TestSummeGrenzen(const A: Integer; ' +
    'const B: Integer; const AExpected: Integer);'#13#10'  end;'), mNewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDraftsTests);

end.
