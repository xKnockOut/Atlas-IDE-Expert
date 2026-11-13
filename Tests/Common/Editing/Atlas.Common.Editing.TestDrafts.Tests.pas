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
  KundenText =
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

  TestUnitText =
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
  Result := TTestDrafts.DraftAt(KundenText, TPascalLexer.Tokenize(KundenText),
    TIndexExtractor.ExtractText(KundenText, 'Kunden.pas', nil), ALine, ADraft);
  ADraft.Fixture := 'TKundeTests';
  ADraft.UnitName := 'Kunden';
end;

/// <summary>Der Rumpf AMethod in einer Testunit parst ohne Fehler.</summary>
function Parses(const AMethod: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse('unit T;'#13#10'interface'#13#10'implementation'#13#10 + AMethod + #13#10'end.');
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
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
  Draft: TTestDraft;
begin
  Assert.IsTrue(DraftAt(19, Draft), 'im Rumpf');
  Assert.AreEqual('TKunde', Draft.ClassName);
  Assert.AreEqual('Berechne', Draft.MethodName);
  Assert.AreEqual('TestBerechne', Draft.TestName);
  Assert.AreEqual('Double', Draft.ResultType);
  Assert.AreEqual(3, Integer(Length(Draft.Parameters)));
  Assert.AreEqual('AName', Draft.Parameters[1].Name);
  Assert.AreEqual('var', Draft.Parameters[1].Modifier);
  Assert.AreEqual('string', Draft.Parameters[1].TypeName);
  Assert.IsFalse(Draft.ClassMethod);
  Assert.IsTrue(Draft.Draft);
  Assert.IsTrue(DraftAt(6, Draft), 'an der Deklaration');
  Assert.AreEqual('Berechne', Draft.MethodName);
  Assert.IsTrue(DraftAt(22, Draft), 'Klassenmethode');
  Assert.IsTrue(Draft.ClassMethod);
  Assert.AreEqual('TKunde', Draft.ResultType);
  Assert.IsTrue(DraftAt(31, Draft), 'Routine');
  Assert.AreEqual('', Draft.ClassName);
  Assert.AreEqual('Summe', Draft.MethodName);
  Assert.AreEqual(2, Integer(Length(Draft.Parameters)));
end;

procedure TTestDraftsTests.DraftAtSkipsConstructorsRecordsAndOtherLines;
var
  Draft: TTestDraft;
begin
  Assert.IsFalse(DraftAt(15, Draft), 'Konstruktor');
  Assert.IsFalse(DraftAt(5, Draft), 'Konstruktor an der Deklaration');
  Assert.IsFalse(DraftAt(27, Draft), 'Methode eines Records');
  Assert.IsFalse(DraftAt(2, Draft), 'type');
end;

procedure TTestDraftsTests.MethodTextCallsSubjectWithLocals;
var
  Draft: TTestDraft;
  Text: string;
begin
  Assert.IsTrue(DraftAt(19, Draft));
  Draft.Subject := 'FSubject';
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(StartsStr('procedure TKundeTests.TestBerechne;'#13#10'var'#13#10 +
    '  Menge: Integer;'#13#10'  Name: string;'#13#10'  Faktor: Double;'#13#10'  Actual: Double;'#13#10'begin', Text),
    Text);
  Assert.IsTrue(ContainsStr(Text, '  Menge := 0;'#13#10'  Name := '''';'#13#10'  Faktor := 0;'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Actual := FSubject.Berechne(Menge, Name, Faktor);'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Assert.AreEqual(0.0, Actual, 1E-9);'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Assert.AreEqual('''', Name);'), 'var-Parameter wird geprüft: ' + Text);
  // Ohne Umlaute im Vergleich: Das FPC-Testprogramm liest Literale mit anderer Codepage.
  Assert.IsTrue(ContainsStr(Text, '  Assert.Fail(''Entwurf f'), Text);
  Assert.IsTrue(ContainsStr(Text, ' TKunde.Berechne: erwartete Werte eintragen und diese Zeile l'), Text);
  Assert.IsTrue(EndsStr('schen'');'#13#10'end;', Text), Text);
  Assert.IsFalse(ContainsStr(Text, 'try'), Text);
end;

procedure TTestDraftsTests.ClassMethodIsCalledViaClass;
var
  Draft: TTestDraft;
  Text: string;
begin
  Assert.IsTrue(DraftAt(22, Draft));
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, '  Actual := TKunde.Neu(Text);'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Assert.AreEqual<TKunde>(Default(TKunde), Actual);'), Text);
  Assert.IsFalse(ContainsStr(Text, 'Subject'), Text);
  Assert.IsTrue(DraftAt(31, Draft));
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(ContainsStr(Text, '  Actual := Summe(A, B);'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Assert.AreEqual(0, Actual);'), Text);
end;

procedure TTestDraftsTests.LocalSubjectIsFreedInFinally;
var
  Draft: TTestDraft;
  Text: string;
begin
  Assert.IsTrue(DraftAt(19, Draft));
  Draft.CreateText := 'TKunde.Create';
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, '  Subject: TKunde;'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Subject := TKunde.Create;'#13#10'  try'#13#10), Text);
  Assert.IsTrue(ContainsStr(Text, '    Actual := Subject.Berechne(Menge, Name, Faktor);'), Text);
  Assert.IsTrue(ContainsStr(Text, '  finally'#13#10'    Subject.Free;'#13#10'  end;'#13#10'end;'), Text);
  Draft.CreateText := '';
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, '  Subject := nil; // '), Text);
end;

procedure TTestDraftsTests.RaisesWithValuesAndFields;
var
  Draft: TTestDraft;
  Field: TTestDraftValue;
  Text: string;
begin
  Assert.IsTrue(DraftAt(19, Draft));
  Draft.Subject := 'FSubject';
  Draft.Draft := False;
  Draft.Kind := TTestDraftKind.Raises;
  Draft.ExceptionClass := 'EConvertError';
  Draft.Comment := 'Aus Debug-Halt, EConvertError';
  Draft.Parameters[0].Value := '12';
  Draft.Parameters[1].Value := '''12,5 kg''';
  Draft.Parameters[2].Todo := True;
  Field := TTestDraftValue.Create('Einheit', 'string', '', '''kg''');
  Draft.Fields := [Field];
  Field := TTestDraftValue.Create('FIntern', 'Integer', '', '3');
  Field.Accessible := False;
  Draft.Fields := Draft.Fields + [Field];
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, 'begin'#13#10'  // Aus Debug-Halt, EConvertError'#13#10), Text);
  Assert.IsTrue(ContainsStr(Text, '  Menge := 12;'#13#10'  Name := ''12,5 kg'';'#13#10 +
    '  Faktor := 0; // TODO: Faktor aufbauen (Double)'), Text);
  Assert.IsTrue(ContainsStr(Text, '  FSubject.Einheit := ''kg'';'), Text);
  Assert.IsTrue(ContainsStr(Text, '  // FIntern = 3 (nicht zug'), Text);
  Assert.IsTrue(ContainsStr(Text, '  Assert.WillRaise('#13#10'    procedure'#13#10'    begin'#13#10 +
    '      FSubject.Berechne(Menge, Name, Faktor);'#13#10'    end, EConvertError);'#13#10'end;'), Text);
  Assert.IsFalse(ContainsStr(Text, 'Actual'), Text);
  Assert.IsFalse(ContainsStr(Text, 'Assert.Fail'), Text);
end;

procedure TTestDraftsTests.BareDraftOnlyFails;
var
  Draft: TTestDraft;
  Text: string;
begin
  Draft := Default(TTestDraft);
  Draft.Fixture := 'TKundeTests';
  Draft.TestName := 'TestPruefe';
  Draft.ClassName := 'TKunde';
  Draft.MethodName := 'Pruefe';
  Draft.Bare := True;
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(StartsStr('procedure TKundeTests.TestPruefe;'#13#10'begin'#13#10'  Assert.Fail(', Text), Text);
  Assert.IsTrue(EndsStr(');'#13#10'end;', Text), Text);
end;

procedure TTestDraftsTests.NonPublicRoutinesAreBare;
const
  Text =
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
  Draft: TTestDraft;
  Index: TUnitIndex;
begin
  Index := TIndexExtractor.ExtractText(Text, 'Intern.pas', nil);
  Assert.IsTrue(TTestDrafts.DraftAt(Text, TPascalLexer.Tokenize(Text), Index, 14, Draft));
  Assert.AreEqual('Pruefe', Draft.MethodName);
  Assert.IsTrue(Draft.Bare, 'private Methode');
  Assert.IsTrue(TTestDrafts.DraftAt(Text, TPascalLexer.Tokenize(Text), Index, 10, Draft));
  Assert.AreEqual('Hilfe', Draft.MethodName);
  Assert.IsTrue(Draft.Bare, 'Routine nur im implementation-Teil');
end;

procedure TTestDraftsTests.AddToTestUnitNumbersAndUsesSubjectField;
var
  Draft: TTestDraft;
  NewText, Name, Reason: string;
begin
  Assert.IsTrue(DraftAt(19, Draft));
  Assert.IsTrue(TTestDrafts.AddToTestUnit(TestUnitText, Draft, False, NewText, Name, Reason), Reason);
  Assert.AreEqual('TestBerechne2', Name);
  Assert.IsTrue(ContainsStr(NewText, '    procedure TestBerechne;'#13#10'    [Test]'#13#10 +
    '    procedure TestBerechne2;'#13#10'  end;'), NewText);
  Assert.IsTrue(ContainsStr(NewText, '  Actual := FKunde.Berechne(Menge, Name, Faktor);'), NewText);
  Assert.IsTrue(ContainsStr(NewText, '  DUnitX.TestFramework,'#13#10'  Kunden;'), NewText);
  Assert.IsTrue(Pos('procedure TKundeTests.TestBerechne2;', NewText) < Pos('initialization', NewText), NewText);
  // Nur wenn er fehlt: TestBerechne gibt es schon, nichts ändert sich.
  Assert.IsTrue(TTestDrafts.AddToTestUnit(TestUnitText, Draft, True, NewText, Name, Reason), Reason);
  Assert.AreEqual(TestUnitText, NewText);
  Assert.AreEqual('TestBerechne', Name);
end;

procedure TTestDraftsTests.AddToTestUnitWithoutFixtureFails;
var
  Draft: TTestDraft;
  NewText, Name, Reason: string;
begin
  Assert.IsTrue(DraftAt(19, Draft));
  Assert.IsFalse(TTestDrafts.AddToTestUnit('unit Leer;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10,
    Draft, False, NewText, Name, Reason));
  Assert.AreNotEqual('', Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDraftsTests);

end.
