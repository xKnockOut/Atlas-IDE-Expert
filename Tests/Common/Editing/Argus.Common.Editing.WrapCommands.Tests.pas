unit Argus.Common.Editing.WrapCommands.Tests;

// Tests für die Schnellbefehle /try, /lock, /sync, /ifdef und /region (#296).

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
    [Test]
    procedure NothingToWrapFails;
    [Test]
    procedure ResultsParseWithoutErrors;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Editing.SlashCommands;

const
  RoutineUnit =
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
  Result := Format(RoutineUnit, [ACommand]);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Expand(const ACommand: string): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(WithCommand(ACommand), 15, Edits), ACommand);
  Result := Apply(WithCommand(ACommand), Edits);
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TWrapCommandsTests.TryFreesLastCreatedLocal;
var
  Text: string;
begin
  Text := Expand('/try');
  Assert.IsTrue(Pos('begin'#10'  Liste := TStringList.Create;'#10'  try'#10'    Liste.Add(''a'');'#10 +
    '    Liste.Sort;'#10'  finally'#10'    Liste.Free;'#10'  end;'#10'end;', Text) > 0, Text);
end;

procedure TWrapCommandsTests.TryOnResultUsesExcept;
var
  Text: string;
  Edits: TArray<TRuleEdit>;
begin
  Text := StringReplace(WithCommand('/try'), 'Liste := TStringList.Create;', 'Result := TStringList.Create;', []);
  Assert.IsTrue(Run(Text, 15, Edits));
  Text := Apply(Text, Edits);
  Assert.IsTrue(Pos('  except'#10'    Result.Free;'#10'    raise;'#10'  end;'#10'end;', Text) > 0, Text);
end;

procedure TWrapCommandsTests.TryWithoutObjectFails;
var
  Text: string;
  Problems: TArray<TSlashProblem>;
begin
  Text := StringReplace(WithCommand('/try'), 'Liste := TStringList.Create;', 'Liste := nil;', []);
  Problems := TSlashCommandRegistry.Shared.Problems(Text, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual('Vor /try wird kein lokales Objekt erzeugt', Problems[0].Message);
  // Felder gibt die Klasse frei, nicht die Routine.
  Text := StringReplace(WithCommand('/try'), 'Liste := TStringList.Create;', 'FSperre := TCriticalSection.Create;', []);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Text, nil))));
end;

procedure TWrapCommandsTests.TryStopsAtFinally;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  try'#10 +
    '    L := TList.Create;'#10'    /try'#10'    L.Clear;'#10'  finally'#10'    X;'#10'  end;'#10'end;'#10'end.';
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(Text, 7, Edits));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  try'#10 +
    '    L := TList.Create;'#10'    try'#10'      L.Clear;'#10'    finally'#10'      L.Free;'#10'    end;'#10 +
    '  finally'#10'    X;'#10'  end;'#10'end;'#10'end.', Apply(Text, Edits));
end;

procedure TWrapCommandsTests.LockUsesMonitor;
var
  Text: string;
  Edits: TArray<TRuleEdit>;
begin
  Text := StringReplace(WithCommand('/lock'), 'FSperre: TCriticalSection;', 'FAnzahl: Integer;', []);
  Assert.IsTrue(Run(Text, 15, Edits));
  Text := Apply(Text, Edits);
  Assert.IsTrue(Pos('  TMonitor.Enter(Self);'#10'  try'#10'    Liste.Add(''a'');'#10'    Liste.Sort;'#10 +
    '  finally'#10'    TMonitor.Exit(Self);'#10'  end;'#10'end;', Text) > 0, Text);
end;

procedure TWrapCommandsTests.LockUsesCriticalSection;
var
  Text: string;
begin
  Text := Expand('/lock');
  Assert.IsTrue(Pos('  FSperre.Enter;'#10'  try'#10, Text) > 0, Text);
  Assert.IsTrue(Pos('  finally'#10'    FSperre.Leave;'#10'  end;', Text) > 0, Text);
end;

procedure TWrapCommandsTests.SyncQueueAndSynchronize;
var
  Text: string;
begin
  Text := Expand('/sync');
  Assert.IsTrue(Pos('  TThread.Queue(nil,'#10'    procedure'#10'    begin'#10'      Liste.Add(''a'');'#10 +
    '      Liste.Sort;'#10'    end);'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Pos('  TThread.Synchronize(nil,', Expand('/sync!')) > 0);
end;

procedure TWrapCommandsTests.IfdefAndRegion;
var
  Text: string;
begin
  Text := Expand('/ifdef DEBUG');
  Assert.IsTrue(Pos('  {$IFDEF DEBUG}'#10'  Liste.Add(''a'');'#10'  Liste.Sort;'#10'  {$ENDIF}'#10'end;', Text) > 0,
    Text);
  Text := Expand('/region Daten füllen');
  Assert.IsTrue(Pos('  {$REGION ''Daten füllen''}'#10'  Liste.Add(''a'');'#10'  Liste.Sort;'#10'  {$ENDREGION}'#10,
    Text) > 0, Text);
end;

procedure TWrapCommandsTests.ExceptLogsAndReraises;
var
  Text: string;
begin
  Text := Expand('/except');
  Assert.IsTrue(Pos('  try'#10'    Liste.Add(''a'');'#10'    Liste.Sort;'#10'  except'#10'    on E: Exception do'#10 +
    '    begin'#10'      OutputDebugString(PChar(E.ClassName + '': '' + E.Message));'#10'      raise;'#10'    end;'#10 +
    '  end;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TWrapCommandsTests.NothingToWrapFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /sync'#10'end;'#10'end.';
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(Text, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual('Nach /sync stehen keine Anweisungen im Block', Problems[0].Message);
end;

procedure TWrapCommandsTests.ResultsParseWithoutErrors;
const
  Commands: array[0..6] of string = ('/try', '/lock', '/sync', '/sync!', '/ifdef DEBUG', '/region Teil', '/except');
var
  Command, Text: string;
begin
  for Command in Commands do
  begin
    Text := Expand(Command);
    Assert.IsTrue(Parses(Text), Command + ': ' + Text);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWrapCommandsTests);

end.
