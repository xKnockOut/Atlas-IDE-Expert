unit Atlas.Common.Editing.WrapCommands.Tests;

// Tests für die Schnellbefehle /try, /lock, /sync, /ifdef, /region und /case (#296).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWrapCommandsTests = class
  public
    [Test]
    procedure TryFreesLastCreatedLocal;
    [Test]
    procedure TryOnResultUsesExcept;
    /// <summary>#293/#43: Einrückung nach dem Formatstil der Datei (vier Leerzeichen, Tabulator).</summary>
    [Test]
    procedure TryFollowsFormatStyle;
    [Test]
    procedure TryWithoutObjectFails;
    [Test]
    procedure TryStopsAtFinally;
    [Test]
    procedure LockUsesMonitor;
    [Test]
    procedure LockUsesCriticalSection;
    [Test]
    procedure SyncQueueAndSynchronize;
    [Test]
    procedure IfdefAndRegion;
    [Test]
    procedure ExceptLogsAndReraises;
    /// <summary>#304: /except außerhalb einer Routine und ohne Anweisungen darunter bleibt stehen.</summary>
    [Test]
    procedure ExceptWrongPlaceFails;
    [Test]
    procedure NothingToWrapFails;
    [Test]
    procedure ResultsParseWithoutErrors;
    [Test]
    procedure CaseAddsMissingValues;
    [Test]
    procedure CaseWithoutBranchesAndElse;
    [Test]
    procedure CaseKeepsScopedLabels;
    /// <summary>Markierung im Erzeugen-Menü (#719): /case ergänzt auch dann den case darunter.</summary>
    [Test]
    procedure CaseWithSelection;
    [Test]
    procedure CaseAllPresentFails;
    [Test]
    procedure CaseWrongPlaceFails;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SlashMenu;

const
  cCaseUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TArt = (aKreis, aLinie, aRechteck);'#10 +    // 3
    '  TFoo = class'#10 +                           // 4
    '  private'#10 +                                // 5
    '    FArt: TArt;'#10 +                          // 6
    '    procedure Run;'#10 +                       // 7
    '  end;'#10 +                                   // 8
    'implementation'#10 +                           // 9
    #10 +                                           // 10
    'procedure TFoo.Run;'#10 +                      // 11
    'begin'#10 +                                    // 12
    '  /case'#10 +                                  // 13 Befehl
    '  case FArt of'#10 +                           // 14
    '%s' +                                          // Zweige
    '  end;'#10 +
    'end;'#10 +
    #10 +
    'end.';

  cRoutineUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TFoo = class'#10 +                           // 3
    '  private'#10 +                                // 4
    '    FSperre: TCriticalSection;'#10 +           // 5
    '    procedure Run;'#10 +                       // 6
    '  end;'#10 +                                   // 7
    'implementation'#10 +                           // 8
    #10 +                                           // 9
    'procedure TFoo.Run;'#10 +                      // 10
    'var'#10 +                                      // 11
    '  Liste: TStringList;'#10 +                    // 12
    'begin'#10 +                                    // 13
    '  Liste := TStringList.Create;'#10 +           // 14
    '  %s'#10 +                                     // 15 Befehl
    '  Liste.Add(''a'');'#10 +                      // 16
    '  Liste.Sort;'#10 +                            // 17
    'end;'#10 +                                     // 18
    #10 +                                           // 19
    'end.';

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
end;

function WithCommand(const ACommand: string): string;
begin
  Result := Format(cRoutineUnit, [ACommand]);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Expand(const ACommand: string): string;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(WithCommand(ACommand), 15, mEdits), ACommand);
  Result := Apply(WithCommand(ACommand), mEdits);
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TWrapCommandsTests.TryFreesLastCreatedLocal;
var
  mText: string;
begin
  mText := Expand('/try');
  Assert.IsTrue(Pos('begin'#10'  Liste := TStringList.Create;'#10'  try'#10'    Liste.Add(''a'');'#10 +
    '    Liste.Sort;'#10'  finally'#10'    Liste.Free;'#10'  end;'#10'end;', mText) > 0, mText);
end;

procedure TWrapCommandsTests.TryOnResultUsesExcept;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
begin
  mText := StringReplace(WithCommand('/try'), 'Liste := TStringList.Create;', 'Result := TStringList.Create;', []);
  Assert.IsTrue(Run(mText, 15, mEdits));
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('  except'#10'    Result.Free;'#10'    raise;'#10'  end;'#10'end;', mText) > 0, mText);
end;

procedure TWrapCommandsTests.TryFollowsFormatStyle;
var
  mText, mWide: string;
  mStyle: TFormatStyle;
  mEdits: TArray<TRuleEdit>;
begin
  // Datei mit vier Leerzeichen je Ebene.
  mWide := StringReplace(WithCommand('/try'), #10'  ', #10'    ', [rfReplaceAll]);
  mStyle := TFormatStyle.Default;
  mStyle.IndentSize := 4;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mWide, TTextPosition.Create(16, 0),
    TSlashEnvironment.Create(nil, nil).WithStyle(mStyle), mEdits));
  mText := Apply(mWide, mEdits);
  Assert.IsTrue(Pos('begin'#10'    Liste := TStringList.Create;'#10'    try'#10'        Liste.Add(''a'');'#10 +
    '        Liste.Sort;'#10'    finally'#10'        Liste.Free;'#10'    end;'#10'end;', mText) > 0, mText);
  // Tabulatoren.
  mWide := StringReplace(WithCommand('/try'), #10'  ', #10#9, [rfReplaceAll]);
  mStyle.UseTabs := True;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mWide, TTextPosition.Create(16, 0),
    TSlashEnvironment.Create(nil, nil).WithStyle(mStyle), mEdits));
  mText := Apply(mWide, mEdits);
  Assert.IsTrue(Pos('begin'#10#9'Liste := TStringList.Create;'#10#9'try'#10#9#9'Liste.Add(''a'');'#10 +
    #9#9'Liste.Sort;'#10#9'finally'#10#9#9'Liste.Free;'#10#9'end;'#10'end;', mText) > 0, mText);
  // Vorgabestil (zwei Leerzeichen): Reindent ändert nichts.
  Assert.IsTrue(Run(WithCommand('/try'), 15, mEdits));
  Assert.AreEqual(Apply(WithCommand('/try'), mEdits), Apply(WithCommand('/try'),
    TSlashCommandRegistry.Reindent(WithCommand('/try'), mEdits, TFormatStyle.Default)));
end;

procedure TWrapCommandsTests.TryWithoutObjectFails;
var
  mText: string;
  mProblems: TArray<TSlashProblem>;
begin
  mText := StringReplace(WithCommand('/try'), 'Liste := TStringList.Create;', 'Liste := nil;', []);
  mProblems := TSlashCommandRegistry.Shared.Problems(mText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('Vor /try wird kein lokales Objekt erzeugt', mProblems[0].Message);
  // Felder gibt die Klasse frei, nicht die Routine.
  mText := StringReplace(WithCommand('/try'), 'Liste := TStringList.Create;', 'FSperre := TCriticalSection.Create;', []);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(mText, nil))));
end;

procedure TWrapCommandsTests.TryStopsAtFinally;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  try'#10 +
    '    L := TList.Create;'#10'    /try'#10'    L.Clear;'#10'  finally'#10'    X;'#10'  end;'#10'end;'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(cText, 7, mEdits));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  try'#10 +
    '    L := TList.Create;'#10'    try'#10'      L.Clear;'#10'    finally'#10'      L.Free;'#10'    end;'#10 +
    '  finally'#10'    X;'#10'  end;'#10'end;'#10'end.', Apply(cText, mEdits));
end;

procedure TWrapCommandsTests.LockUsesMonitor;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
begin
  mText := StringReplace(WithCommand('/lock'), 'FSperre: TCriticalSection;', 'FAnzahl: Integer;', []);
  Assert.IsTrue(Run(mText, 15, mEdits));
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('  TMonitor.Enter(Self);'#10'  try'#10'    Liste.Add(''a'');'#10'    Liste.Sort;'#10 +
    '  finally'#10'    TMonitor.Exit(Self);'#10'  end;'#10'end;', mText) > 0, mText);
end;

procedure TWrapCommandsTests.LockUsesCriticalSection;
var
  mText: string;
begin
  mText := Expand('/lock');
  Assert.IsTrue(Pos('  FSperre.Enter;'#10'  try'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('  finally'#10'    FSperre.Leave;'#10'  end;', mText) > 0, mText);
end;

procedure TWrapCommandsTests.SyncQueueAndSynchronize;
var
  mText: string;
begin
  mText := Expand('/sync');
  Assert.IsTrue(Pos('  TThread.Queue(nil,'#10'    procedure'#10'    begin'#10'      Liste.Add(''a'');'#10 +
    '      Liste.Sort;'#10'    end);'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Pos('  TThread.Synchronize(nil,', Expand('/sync!')) > 0);
end;

procedure TWrapCommandsTests.IfdefAndRegion;
var
  mText: string;
begin
  mText := Expand('/ifdef DEBUG');
  Assert.IsTrue(Pos('  {$IFDEF DEBUG}'#10'  Liste.Add(''a'');'#10'  Liste.Sort;'#10'  {$ENDIF}'#10'end;', mText) > 0,
    mText);
  mText := Expand('/region Daten füllen');
  Assert.IsTrue(Pos('  {$REGION ''Daten füllen''}'#10'  Liste.Add(''a'');'#10'  Liste.Sort;'#10'  {$ENDREGION}'#10,
    mText) > 0, mText);
end;

procedure TWrapCommandsTests.ExceptLogsAndReraises;
var
  mText: string;
begin
  mText := Expand('/except');
  Assert.IsTrue(Pos('  try'#10'    Liste.Add(''a'');'#10'    Liste.Sort;'#10'  except'#10'    on E: Exception do'#10 +
    '    begin'#10'      OutputDebugString(PChar(E.ClassName + '': '' + E.Message));'#10'      raise;'#10'    end;'#10 +
    '  end;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TWrapCommandsTests.ExceptWrongPlaceFails;
const
  cOutsideText = 'unit U;'#10'interface'#10'/except'#10#10'implementation'#10'end.';
  cEmptyText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /except'#10'end;'#10'end.';
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(cOutsideText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/except gilt nur im Rumpf einer Routine', mProblems[0].Message);
  mProblems := TSlashCommandRegistry.Shared.Problems(cEmptyText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('Nach /except stehen keine Anweisungen im Block', mProblems[0].Message);
end;

procedure TWrapCommandsTests.NothingToWrapFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /sync'#10'end;'#10'end.';
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(cText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('Nach /sync stehen keine Anweisungen im Block', mProblems[0].Message);
end;

procedure TWrapCommandsTests.ResultsParseWithoutErrors;
const
  cCommands: array[0..6] of string = ('/try', '/lock', '/sync', '/sync!', '/ifdef DEBUG', '/region Teil', '/except');
var
  mCommand, mText: string;
begin
  for mCommand in cCommands do
  begin
    mText := Expand(mCommand);
    Assert.IsTrue(Parses(mText), mCommand + ': ' + mText);
  end;
end;

function ExpandCase(const ABranches: string): string;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := Format(cCaseUnit, [ABranches]);
  Assert.IsTrue(Run(mText, 13, mEdits), mText);
  Result := Apply(mText, mEdits);
end;

procedure TWrapCommandsTests.CaseAddsMissingValues;
var
  mText: string;
begin
  mText := ExpandCase('    aKreis: Run;'#10);
  Assert.IsTrue(Pos('begin'#10'  case FArt of'#10'    aKreis: Run;'#10'    aLinie: ;'#10'    aRechteck: ;'#10 +
    '  end;'#10'end;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('/case', mText), mText);
  Assert.IsTrue(Parses(mText), mText);
  // Letzter Zweig ohne ";" vor end: das ";" kommt dazu.
  mText := ExpandCase('    aKreis: Run'#10);
  Assert.IsTrue(Pos('    aKreis: Run;'#10'    aLinie: ;'#10'    aRechteck: ;'#10'  end;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TWrapCommandsTests.CaseWithoutBranchesAndElse;
var
  mText: string;
begin
  mText := ExpandCase('');
  Assert.IsTrue(Pos('  case FArt of'#10'    aKreis: ;'#10'    aLinie: ;'#10'    aRechteck: ;'#10'  end;', mText) > 0,
    mText);
  // Fehlende Werte kommen vor den else-Teil.
  mText := ExpandCase('    aLinie: Run;'#10'  else'#10'    Run;'#10);
  Assert.IsTrue(Pos('    aLinie: Run;'#10'    aKreis: ;'#10'    aRechteck: ;'#10'  else'#10'    Run;'#10'  end;',
    mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TWrapCommandsTests.CaseKeepsScopedLabels;
var
  mEdits: TArray<TRuleEdit>;
  mReason: string;
  mText: string;
begin
  mText := ExpandCase('    TArt.aKreis, TArt.aLinie: Run;'#10);
  Assert.IsTrue(Pos('    TArt.aKreis, TArt.aLinie: Run;'#10'    TArt.aRechteck: ;'#10'  end;', mText) > 0, mText);
  // {$SCOPEDENUMS ON} an der Deklaration: Werte nur mit Typpräfix.
  mText := StringReplace(Format(cCaseUnit, ['']), '  TArt = (', '  {$SCOPEDENUMS ON}'#10'  TArt = (', []);
  mText := StringReplace(mText, '/case', '', []);
  Assert.IsTrue(TSlashMenu.Run(TSlashCommandRegistry.Shared, mText, TSlashSpot.Create(14, 2, -1),
    TSlashMenuCall.Create('case', '', TSlashEnvironment.Create(nil, nil)), mEdits, mReason), mReason);
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('    TArt.aKreis: ;'#10'    TArt.aLinie: ;'#10'    TArt.aRechteck: ;', mText) > 0, mText);
end;

procedure TWrapCommandsTests.CaseWithSelection;
var
  mEdits: TArray<TRuleEdit>;
  mReason: string;
  mText: string;
begin
  // Markierung über dem case (Zeilen 13 bis 15): die gedachte Befehlszeile steht davor.
  mText := StringReplace(Format(cCaseUnit, ['    aKreis: Run;'#10]), '  /case'#10, '', []);
  Assert.IsTrue(TSlashMenu.Run(TSlashCommandRegistry.Shared, mText, TSlashSpot.Create(13, 0, 15),
    TSlashMenuCall.Create('case', '', TSlashEnvironment.Create(nil, nil)), mEdits, mReason), mReason);
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('    aKreis: Run;'#10'    aLinie: ;'#10'    aRechteck: ;'#10'  end;', mText) > 0, mText);
end;

procedure TWrapCommandsTests.CaseAllPresentFails;
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cCaseUnit, ['    aKreis..aRechteck: Run;'#10]), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('Der case behandelt schon alle Werte von TArt', mProblems[0].Message);
end;

procedure TWrapCommandsTests.CaseWrongPlaceFails;
var
  mProblems: TArray<TSlashProblem>;
  mText: string;
begin
  // Kein case darunter.
  mText := StringReplace(Format(cCaseUnit, ['    aKreis: Run;'#10]), '  case FArt of', '  if True then', []);
  mProblems := TSlashCommandRegistry.Shared.Problems(mText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/case erwartet darunter eine case-Anweisung über einer Aufzählung', mProblems[0].Message);
  // Außerhalb einer Routine.
  mProblems := TSlashCommandRegistry.Shared.Problems('unit U;'#10'interface'#10'/case'#10'implementation'#10'end.', nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/case gilt nur im Rumpf einer Routine', mProblems[0].Message);
  // Auswahl ist keine Aufzählung.
  mText := StringReplace(Format(cCaseUnit, ['    1: Run;'#10]), '    FArt: TArt;', '    FArt: Integer;', []);
  mProblems := TSlashCommandRegistry.Shared.Problems(mText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('Der Typ von FArt ist keine bekannte Aufzählung', mProblems[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TWrapCommandsTests);

end.
