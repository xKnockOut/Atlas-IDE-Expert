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
  cMockUnit =
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

  cFixtureUnit =
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

  cRoutineUnit =
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
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Result := '';
  if Length(mProblems) > 0 then
  begin
    Result := mProblems[0].Message;
  end;
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

function InRoutine(const ACommand: string; const AUses: string): string; overload;
begin
  Result := Format(cRoutineUnit, ['', AUses, ACommand]);
end;

function InRoutine(const ACommand: string): string; overload;
begin
  Result := InRoutine(ACommand, '');
end;

procedure TTestCommandsTests.WarmUp;
begin
  SplitValuesKeepsCommasInStrings;
  DumpListsSimpleLocals;
end;

procedure TTestCommandsTests.SplitValuesKeepsCommasInStrings;
var
  mValues: TArray<string>;
begin
  Assert.IsTrue(TTestCommandTexts.SplitValues('''a'', 2, True', mValues));
  Assert.AreEqual('a|2|True', string.Join('|', mValues));
  Assert.IsTrue(TTestCommandTexts.SplitValues('''x, y'', ''it''''s''', mValues));
  Assert.AreEqual('x, y|it''s', string.Join('|', mValues));
  Assert.IsFalse(TTestCommandTexts.SplitValues('''offen, 2', mValues));
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
  mSource, mText: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := Format(cMockUnit, ['/mock IKundenRepo']);
  Assert.IsTrue(Run(mSource, 9, mEdits), Problem(mSource));
  mText := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, 'type'#10'  TKundenRepoMock = class(TInterfacedObject, IKundenRepo)'#10 +
    '  public'#10'    LadenCalls: Integer;'#10'    LadenResult: TKunde;'#10'    SpeichernCalls: Integer;'#10), mText);
  Assert.IsTrue(ContainsStr(mText, '    function Laden(const AId: Integer): TKunde;'#10 +
    '    procedure Speichern(const AKunde: TKunde);'#10'  end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'function TKundenRepoMock.Laden(const AId: Integer): TKunde;'#10'begin'#10 +
    '  Inc(LadenCalls);'#10'  Result := LadenResult;'#10'end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'procedure TKundenRepoMock.Speichern(const AKunde: TKunde);'#10'begin'#10 +
    '  Inc(SpeichernCalls);'#10'end;'), mText);
  Assert.IsTrue(Pos('TKundenRepoMock.Laden', mText) > Pos('implementation', mText), mText);
  Assert.IsFalse(ContainsStr(mText, '/mock'), mText);
  // Kein Interface.
  mSource := Format(cMockUnit, ['/mock TKunde']);
  Assert.IsFalse(Run(mSource, 9, mEdits));
  Assert.IsTrue(ContainsStr(Problem(mSource), 'TKunde'), Problem(mSource));
end;

procedure TTestCommandsTests.MockInsideClassFails;
var
  mSource: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := StringReplace(Format(cMockUnit, ['']), '  TKunde = class'#10, '  TKunde = class'#10'    /mock IKundenRepo'#10,
    []);
  Assert.IsFalse(Run(mSource, 4, mEdits));
  Assert.IsTrue(ContainsStr(Problem(mSource), '/mock'), Problem(mSource));
end;

procedure TTestCommandsTests.MockWithDelphiMocksInRoutine;
var
  mSource, mText: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := InRoutine('/mock IKundenRepo', ', Delphi.Mocks');
  Assert.IsTrue(Run(mSource, 13, mEdits), Problem(mSource));
  mText := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(ContainsStr(mText, '  KundenRepo: TMock<IKundenRepo>;'), mText);
  Assert.IsTrue(ContainsStr(mText, '  KundenRepo := TMock<IKundenRepo>.Create;'), mText);
  // Ohne Delphi.Mocks gehört /mock auf die Unit-Ebene.
  mSource := InRoutine('/mock IKundenRepo');
  Assert.IsFalse(Run(mSource, 13, mEdits));
end;

procedure TTestCommandsTests.TestCaseNumbersAndChecksCount;
var
  mSource, mText: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := Format(cFixtureUnit, ['/testcase ''a, b'', 2, True']);
  Assert.IsTrue(Run(mSource, 10, mEdits), Problem(mSource));
  mText := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(ContainsStr(mText, '    [TestCase(''Fall1'', ''x,1,False'')]'#10 +
    '    [TestCase(''Fall2'', ''a, b;2;True'', '';'')]'#10'    procedure Pruefe('), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTestCommandsTests.TestCaseWithWrongCountFails;
var
  mSource: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := Format(cFixtureUnit, ['/testcase ''a'', 2']);
  Assert.IsFalse(Run(mSource, 10, mEdits));
  Assert.IsTrue(ContainsStr(Problem(mSource), 'Pruefe'), Problem(mSource));
  Assert.IsTrue(ContainsStr(Problem(mSource), '3'), Problem(mSource));
  // Ohne Methode darunter.
  mSource := StringReplace(Format(cFixtureUnit, ['/testcase 1']),
    '    procedure Pruefe(const AName: string; AZahl: Integer; AAn: Boolean);'#10, '', []);
  Assert.IsFalse(Run(mSource, 10, mEdits));
end;

procedure TTestCommandsTests.DumpListsSimpleLocals;
var
  mSource, mText: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := InRoutine('/dump');
  Assert.IsTrue(Run(mSource, 13, mEdits), Problem(mSource));
  mText := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(ContainsStr(mText, '  OutputDebugString(PChar(Format(''Rechne: A=%d, S=%s, Summe=%g, Fertig=%s'', ' +
    '[A, S, Summe, BoolToStr(Fertig, True)])));'), mText);
  Assert.IsTrue(ContainsStr(mText, 'System.SysUtils'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTestCommandsTests.DumpOutsideRoutineFails;
var
  mSource: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := Format(cRoutineUnit, ['/dump', '', '']);
  Assert.IsFalse(Run(mSource, 2, mEdits));
  Assert.IsTrue(ContainsStr(Problem(mSource), '/dump'), Problem(mSource));
end;

procedure TTestCommandsTests.AssertFitsTheType;
var
  mSource, mText: string;
  mEdits: TArray<TTextEdit>;
begin
  // Liste: Klasse aus der RTL ohne Index, über die Liste der Referenztypen nicht erkannt; TStringList kennt die
  // Unit nicht. Darum zuerst ein String.
  mSource := StringReplace(InRoutine('/assert'), '  Liste := TStringList.Create;', '  Fertig := A > 0;', []);
  Assert.IsTrue(Run(mSource, 13, mEdits), Problem(mSource));
  mText := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(ContainsStr(mText, '  Assert(Fertig, ''Fertig ist False'');'), mText);
  mSource := StringReplace(InRoutine('/assert'), '  Liste := TStringList.Create;', '  Summe := A * 2;', []);
  Assert.IsTrue(Run(mSource, 13, mEdits), Problem(mSource));
  mText := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(ContainsStr(mText, '  Assert(Summe >= 0, ''Summe ist negativ'');'), mText);
end;

procedure TTestCommandsTests.AssertInTestUnitUsesDUnitX;
var
  mLine: string;
begin
  Assert.IsTrue(TTestCommandTexts.AssertLine('Kunde', 'TKunde', True, True, mLine));
  Assert.AreEqual('Assert.IsNotNull(Kunde);', mLine);
  Assert.IsTrue(TTestCommandTexts.AssertLine('Name', 'string', False, True, mLine));
  Assert.AreEqual('Assert.AreNotEqual('''', Name);', mLine);
  Assert.IsTrue(TTestCommandTexts.AssertLine('Kunde', 'TKunde', True, False, mLine));
  Assert.AreEqual('Assert(Assigned(Kunde), ''Kunde ist nil'');', mLine);
  Assert.IsFalse(TTestCommandTexts.AssertLine('P', 'TPunkt', False, False, mLine), 'Record');
end;

procedure TTestCommandsTests.AssertWithoutAssignmentFails;
var
  mSource: string;
  mEdits: TArray<TTextEdit>;
begin
  mSource := StringReplace(InRoutine('/assert'), '  Liste := TStringList.Create;', '  Liste.Clear;', []);
  Assert.IsFalse(Run(mSource, 13, mEdits));
  Assert.IsTrue(ContainsStr(Problem(mSource), 'Variable'), Problem(mSource));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandsTests);

end.
