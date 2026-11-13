unit Atlas.Common.Editing.TestCommands.Tests;

// Tests für die Schnellbefehle /mock, /testcase, /dump und /assert (#305): je Befehl
// ein Fall, der passt, und einer am falschen Ort bzw. mit falschen Werten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommandsTests = class
  public
    /// <summary>Führt einen Befehl vorab aus; einmalig angelegte Daten zählen sonst als Leck des ersten Tests.
    /// </summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure SplitValuesKeepsCommasInStrings;
    [Test]
    procedure TestCaseAttributeSwitchesSeparator;
    [Test]
    procedure MockImplementsTheWholeInterface;
    [Test]
    procedure MockInsideClassFails;
    [Test]
    procedure MockWithDelphiMocksInRoutine;
    [Test]
    procedure TestCaseNumbersAndChecksCount;
    [Test]
    procedure TestCaseWithWrongCountFails;
    [Test]
    procedure DumpListsSimpleLocals;
    [Test]
    procedure DumpOutsideRoutineFails;
    [Test]
    procedure AssertFitsTheType;
    [Test]
    procedure AssertInTestUnitUsesDUnitX;
    [Test]
    procedure AssertWithoutAssignmentFails;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.TestCommands;

const
  MockUnit =
    'unit Repos;'#10 +                                           // 0
    'interface'#10 +                                             // 1
    'type'#10 +                                                  // 2
    '  TKunde = class'#10 +                                      // 3
    '  end;'#10 +                                                // 4
    '  IKundenRepo = interface'#10 +                             // 5
    '    function Laden(const AId: Integer): TKunde;'#10 +       // 6
    '    procedure Speichern(const AKunde: TKunde);'#10 +        // 7
    '  end;'#10 +                                                // 8
    '%s'#10 +                                                    // 9 Befehl
    'implementation'#10 +                                        // 10
    #10 +                                                        // 11
    'end.';

  FixtureUnit =
    'unit Kunden.Tests;'#10 +                                    // 0
    'interface'#10 +                                             // 1
    'uses'#10 +                                                  // 2
    '  DUnitX.TestFramework;'#10 +                               // 3
    'type'#10 +                                                  // 4
    '  [TestFixture]'#10 +                                       // 5
    '  TKundeTests = class'#10 +                                 // 6
    '  public'#10 +                                              // 7
    '    [Test]'#10 +                                            // 8
    '    [TestCase(''Fall1'', ''x,1,False'')]'#10 +               // 9
    '    %s'#10 +                                                // 10 Befehl
    '    procedure Pruefe(const AName: string; AZahl: Integer; AAn: Boolean);'#10 + // 11
    '  end;'#10 +                                                // 12
    'implementation'#10 +                                        // 13
    'procedure TKundeTests.Pruefe(const AName: string; AZahl: Integer; AAn: Boolean);'#10 + // 14
    'begin'#10 +                                                 // 15
    'end;'#10 +                                                  // 16
    'end.';

  RoutineUnit =
    'unit Rechnen;'#10 +                                         // 0
    'interface'#10 +                                             // 1
    '%s'#10 +                                                    // 2 Befehl auf Unit-Ebene
    'implementation'#10 +                                        // 3
    'uses'#10 +                                                  // 4
    '  System.Classes%s;'#10 +                                   // 5
    'procedure Rechne(A: Integer; const S: string; L: TStringList);'#10 + // 6
    'var'#10 +                                                   // 7
    '  Summe: Double;'#10 +                                      // 8
    '  Fertig: Boolean;'#10 +                                    // 9
    '  Liste: TStringList;'#10 +                                 // 10
    'begin'#10 +                                                 // 11
    '  Liste := TStringList.Create;'#10 +                        // 12
    '  %s'#10 +                                                  // 13 Befehl in der Routine
    'end;'#10 +                                                  // 14
    'end.';

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TTextEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
end;

function Problem(const AText: string): string;
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Result := '';
  if Length(Problems) > 0 then
  begin
    Result := Problems[0].Message;
  end;
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

function InRoutine(const ACommand: string; const AUses: string = ''): string;
begin
  Result := Format(RoutineUnit, ['', AUses, ACommand]);
end;

procedure TTestCommandsTests.WarmUp;
begin
  SplitValuesKeepsCommasInStrings;
  DumpListsSimpleLocals;
end;

procedure TTestCommandsTests.SplitValuesKeepsCommasInStrings;
var
  Values: TArray<string>;
begin
  Assert.IsTrue(TTestCommandTexts.SplitValues('''a'', 2, True', Values));
  Assert.AreEqual('a|2|True', string.Join('|', Values));
  Assert.IsTrue(TTestCommandTexts.SplitValues('''x, y'', ''it''''s''', Values));
  Assert.AreEqual('x, y|it''s', string.Join('|', Values));
  Assert.IsFalse(TTestCommandTexts.SplitValues('''offen, 2', Values));
end;

procedure TTestCommandsTests.TestCaseAttributeSwitchesSeparator;
begin
  Assert.AreEqual('[TestCase(''Fall1'', ''a,2,True'')]', TTestCommandTexts.TestCaseAttribute('Fall1',
    TArray<string>.Create('a', '2', 'True')));
  Assert.AreEqual('[TestCase(''Fall2'', ''x, y;it''''s'', '';'')]', TTestCommandTexts.TestCaseAttribute('Fall2',
    TArray<string>.Create('x, y', 'it''s')));
end;

procedure TTestCommandsTests.MockImplementsTheWholeInterface;
var
  Source, Text: string;
  Edits: TArray<TTextEdit>;
begin
  Source := Format(MockUnit, ['/mock IKundenRepo']);
  Assert.IsTrue(Run(Source, 9, Edits), Problem(Source));
  Text := TTextChanges.Apply(Source, Edits);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, 'type'#10'  TKundenRepoMock = class(TInterfacedObject, IKundenRepo)'#10 +
    '  public'#10'    LadenCalls: Integer;'#10'    LadenResult: TKunde;'#10'    SpeichernCalls: Integer;'#10), Text);
  Assert.IsTrue(ContainsStr(Text, '    function Laden(const AId: Integer): TKunde;'#10 +
    '    procedure Speichern(const AKunde: TKunde);'#10'  end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'function TKundenRepoMock.Laden(const AId: Integer): TKunde;'#10'begin'#10 +
    '  Inc(LadenCalls);'#10'  Result := LadenResult;'#10'end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'procedure TKundenRepoMock.Speichern(const AKunde: TKunde);'#10'begin'#10 +
    '  Inc(SpeichernCalls);'#10'end;'), Text);
  Assert.IsTrue(Pos('TKundenRepoMock.Laden', Text) > Pos('implementation', Text), Text);
  Assert.IsFalse(ContainsStr(Text, '/mock'), Text);
  // Kein Interface.
  Source := Format(MockUnit, ['/mock TKunde']);
  Assert.IsFalse(Run(Source, 9, Edits));
  Assert.IsTrue(ContainsStr(Problem(Source), 'TKunde'), Problem(Source));
end;

procedure TTestCommandsTests.MockInsideClassFails;
var
  Source: string;
  Edits: TArray<TTextEdit>;
begin
  Source := StringReplace(Format(MockUnit, ['']), '  TKunde = class'#10, '  TKunde = class'#10'    /mock IKundenRepo'#10,
    []);
  Assert.IsFalse(Run(Source, 4, Edits));
  Assert.IsTrue(ContainsStr(Problem(Source), '/mock'), Problem(Source));
end;

procedure TTestCommandsTests.MockWithDelphiMocksInRoutine;
var
  Source, Text: string;
  Edits: TArray<TTextEdit>;
begin
  Source := InRoutine('/mock IKundenRepo', ', Delphi.Mocks');
  Assert.IsTrue(Run(Source, 13, Edits), Problem(Source));
  Text := TTextChanges.Apply(Source, Edits);
  Assert.IsTrue(ContainsStr(Text, '  KundenRepo: TMock<IKundenRepo>;'), Text);
  Assert.IsTrue(ContainsStr(Text, '  KundenRepo := TMock<IKundenRepo>.Create;'), Text);
  // Ohne Delphi.Mocks gehört /mock auf die Unit-Ebene.
  Source := InRoutine('/mock IKundenRepo');
  Assert.IsFalse(Run(Source, 13, Edits));
end;

procedure TTestCommandsTests.TestCaseNumbersAndChecksCount;
var
  Source, Text: string;
  Edits: TArray<TTextEdit>;
begin
  Source := Format(FixtureUnit, ['/testcase ''a, b'', 2, True']);
  Assert.IsTrue(Run(Source, 10, Edits), Problem(Source));
  Text := TTextChanges.Apply(Source, Edits);
  Assert.IsTrue(ContainsStr(Text, '    [TestCase(''Fall1'', ''x,1,False'')]'#10 +
    '    [TestCase(''Fall2'', ''a, b;2;True'', '';'')]'#10'    procedure Pruefe('), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TTestCommandsTests.TestCaseWithWrongCountFails;
var
  Source: string;
  Edits: TArray<TTextEdit>;
begin
  Source := Format(FixtureUnit, ['/testcase ''a'', 2']);
  Assert.IsFalse(Run(Source, 10, Edits));
  Assert.IsTrue(ContainsStr(Problem(Source), 'Pruefe'), Problem(Source));
  Assert.IsTrue(ContainsStr(Problem(Source), '3'), Problem(Source));
  // Ohne Methode darunter.
  Source := StringReplace(Format(FixtureUnit, ['/testcase 1']),
    '    procedure Pruefe(const AName: string; AZahl: Integer; AAn: Boolean);'#10, '', []);
  Assert.IsFalse(Run(Source, 10, Edits));
end;

procedure TTestCommandsTests.DumpListsSimpleLocals;
var
  Source, Text: string;
  Edits: TArray<TTextEdit>;
begin
  Source := InRoutine('/dump');
  Assert.IsTrue(Run(Source, 13, Edits), Problem(Source));
  Text := TTextChanges.Apply(Source, Edits);
  Assert.IsTrue(ContainsStr(Text, '  OutputDebugString(PChar(Format(''Rechne: A=%d, S=%s, Summe=%g, Fertig=%s'', ' +
    '[A, S, Summe, BoolToStr(Fertig, True)])));'), Text);
  Assert.IsTrue(ContainsStr(Text, 'System.SysUtils'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TTestCommandsTests.DumpOutsideRoutineFails;
var
  Source: string;
  Edits: TArray<TTextEdit>;
begin
  Source := Format(RoutineUnit, ['/dump', '', '']);
  Assert.IsFalse(Run(Source, 2, Edits));
  Assert.IsTrue(ContainsStr(Problem(Source), '/dump'), Problem(Source));
end;

procedure TTestCommandsTests.AssertFitsTheType;
var
  Source, Text: string;
  Edits: TArray<TTextEdit>;
begin
  // Liste: Klasse aus der RTL ohne Index, über die Liste der Referenztypen nicht erkannt; TStringList kennt die
  // Unit nicht. Darum zuerst ein String.
  Source := StringReplace(InRoutine('/assert'), '  Liste := TStringList.Create;', '  Fertig := A > 0;', []);
  Assert.IsTrue(Run(Source, 13, Edits), Problem(Source));
  Text := TTextChanges.Apply(Source, Edits);
  Assert.IsTrue(ContainsStr(Text, '  Assert(Fertig, ''Fertig ist False'');'), Text);
  Source := StringReplace(InRoutine('/assert'), '  Liste := TStringList.Create;', '  Summe := A * 2;', []);
  Assert.IsTrue(Run(Source, 13, Edits), Problem(Source));
  Text := TTextChanges.Apply(Source, Edits);
  Assert.IsTrue(ContainsStr(Text, '  Assert(Summe >= 0, ''Summe ist negativ'');'), Text);
end;

procedure TTestCommandsTests.AssertInTestUnitUsesDUnitX;
var
  Line: string;
begin
  Assert.IsTrue(TTestCommandTexts.AssertLine('Kunde', 'TKunde', True, True, Line));
  Assert.AreEqual('Assert.IsNotNull(Kunde);', Line);
  Assert.IsTrue(TTestCommandTexts.AssertLine('Name', 'string', False, True, Line));
  Assert.AreEqual('Assert.AreNotEqual('''', Name);', Line);
  Assert.IsTrue(TTestCommandTexts.AssertLine('Kunde', 'TKunde', True, False, Line));
  Assert.AreEqual('Assert(Assigned(Kunde), ''Kunde ist nil'');', Line);
  Assert.IsFalse(TTestCommandTexts.AssertLine('P', 'TPunkt', False, False, Line), 'Record');
end;

procedure TTestCommandsTests.AssertWithoutAssignmentFails;
var
  Source: string;
  Edits: TArray<TTextEdit>;
begin
  Source := StringReplace(InRoutine('/assert'), '  Liste := TStringList.Create;', '  Liste.Clear;', []);
  Assert.IsFalse(Run(Source, 13, Edits));
  Assert.IsTrue(ContainsStr(Problem(Source), 'Variable'), Problem(Source));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandsTests);

end.
