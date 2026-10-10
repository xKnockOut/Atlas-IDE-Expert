unit Argus.Common.Editing.TaskCommands.Tests;

// Tests für die Schnellbefehle /task, /parallel, /future und /atomic (#322).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTaskCommandsTests = class
  public
    [Test]
    procedure TaskWrapsStatements;
    [Test]
    procedure TaskQueuesVclAtEnd;
    [Test]
    procedure TaskOutsideRoutineFails;
    [Test]
    procedure ParallelConvertsLoop;
    [Test]
    procedure ParallelRejectsOuterSum;
    [Test]
    procedure ParallelRejectsBreakAndDownto;
    [Test]
    procedure FutureInline;
    [Test]
    procedure FutureWithoutInlineDeclaresVar;
    [Test]
    procedure AtomicOnField;
    [Test]
    procedure AtomicOnLocalFails;
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

/// <summary>Führt den Befehl in Zeile ALine aus und wendet die Änderungen an; '' wenn er nicht passt.</summary>
function Expand(const AText: string; ALine: Integer;
  const AVersion: string = ''): string;
var
  Edits: TArray<TRuleEdit>;
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  if not TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, Edits, nil,
    AVersion) then
    Exit('');
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(Edits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in Edits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
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

const
  Routine =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'uses System.SysUtils;'#10 +               // 2
    'implementation'#10 +                      // 3
    'procedure P;'#10 +                        // 4
    'var'#10 +                                 // 5
    '  I, Summe: Integer;'#10 +                // 6
    'begin'#10 +                               // 7
    '  %s'#10 +                                // 8 Befehl
    '%s'#10 +                                  // 9.. Anweisungen
    'end;'#10 +
    'end.';

  Fields =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'type'#10 +                                // 2
    '  TZaehler = class'#10 +                  // 3
    '  private'#10 +                           // 4
    '    FAnzahl: Integer;'#10 +               // 5
    '    procedure P;'#10 +                    // 6
    '  end;'#10 +                              // 7
    'implementation'#10 +                      // 8
    'procedure TZaehler.P;'#10 +               // 9
    'var'#10 +                                 // 10
    '  Lokal: Integer;'#10 +                   // 11
    'begin'#10 +                               // 12
    '  /atomic'#10 +                           // 13
    '  %s'#10 +                                // 14
    'end;'#10 +
    'end.';

procedure TTaskCommandsTests.TaskWrapsStatements;
var
  Text: string;
begin
  Text := Expand(Format(Routine, ['/task', '  Rechne;'#10'  Speichere;']), 8);
  Assert.Contains(Text, '  TTask.Run('#10'    procedure'#10'    begin'#10'      Rechne;'#10'      Speichere;'#10 +
    '    end);'#10'end;');
  Assert.Contains(Text, 'System.Threading');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TTaskCommandsTests.TaskQueuesVclAtEnd;
var
  Text: string;
begin
  Text := Expand(Format(Routine, ['/task', '  Rechne;'#10'  ShowMessage(''Fertig'');']), 8);
  Assert.Contains(Text, '      Rechne;'#10'      TThread.Queue(nil,'#10'        procedure'#10'        begin'#10 +
    '          ShowMessage(''Fertig'');'#10'        end);'#10'    end);');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TTaskCommandsTests.TaskOutsideRoutineFails;
begin
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/task'#10'implementation'#10'end.', 2));
  Assert.AreEqual('', Expand(Format(Routine, ['/task', '']), 8));
end;

procedure TTaskCommandsTests.ParallelConvertsLoop;
var
  Text: string;
begin
  Text := Expand(Format(Routine, ['/parallel', '  for I := 0 to High(Liste) do'#10'    Verarbeite(Liste[I]);']), 8);
  Assert.Contains(Text, '  TParallel.For(0, High(Liste),'#10'    procedure(I: Integer)'#10'    begin'#10 +
    '      Verarbeite(Liste[I]);'#10'    end);'#10'end;');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TTaskCommandsTests.ParallelRejectsOuterSum;
begin
  Assert.AreEqual('', Expand(Format(Routine, ['/parallel', '  for I := 0 to 9 do'#10'    Summe := Summe + I;']), 8));
  Assert.AreEqual('', Expand(Format(Routine, ['/parallel', '  for I := 0 to 9 do'#10'    Inc(Summe);']), 8));
  Assert.AreEqual('', Expand(Format(Routine, ['/parallel', '  for I := 0 to 9 do'#10 +
    '    Label1.Caption := IntToStr(I);']), 8));
end;

procedure TTaskCommandsTests.ParallelRejectsBreakAndDownto;
begin
  Assert.AreEqual('', Expand(Format(Routine, ['/parallel', '  for I := 0 to 9 do'#10'  begin'#10 +
    '    if Fertig(I) then'#10'      Break;'#10'  end;']), 8));
  Assert.AreEqual('', Expand(Format(Routine, ['/parallel', '  for I := 9 downto 0 do'#10'    Verarbeite(I);']), 8));
end;

procedure TTaskCommandsTests.FutureInline;
var
  Text: string;
begin
  Text := Expand(Format(Routine, ['/future Wert: Integer', '  Text := Berechne;']), 8);
  Assert.Contains(Text, '  var Wert := TTask.Future<Integer>(');
  Assert.Contains(Text, '    function: Integer');
end;

procedure TTaskCommandsTests.FutureWithoutInlineDeclaresVar;
var
  Text: string;
begin
  Text := Expand(Format(Routine, ['/future Wert: Integer', '  Text := Berechne;']), 8, '19.0');
  Assert.Contains(Text, '  Wert := TTask.Future<Integer>(');
  Assert.Contains(Text, 'Wert: IFuture<Integer>;');
  Assert.DoesNotContain(Text, 'var Wert');
end;

procedure TTaskCommandsTests.AtomicOnField;
begin
  Assert.Contains(Expand(Format(Fields, ['Inc(FAnzahl);']), 13), '  TInterlocked.Increment(FAnzahl);'#10'end;');
  Assert.Contains(Expand(Format(Fields, ['Dec(FAnzahl, 2);']), 13), '  TInterlocked.Add(FAnzahl, -(2));');
  Assert.Contains(Expand(Format(Fields, ['FAnzahl := FAnzahl + N;']), 13), '  TInterlocked.Add(FAnzahl, N);');
  Assert.Contains(Expand(Format(Fields, ['Inc(FAnzahl);']), 13), 'System.SyncObjs');
end;

procedure TTaskCommandsTests.AtomicOnLocalFails;
begin
  Assert.AreEqual('', Expand(Format(Fields, ['Inc(Lokal);']), 13));
  Assert.AreEqual('', Expand(Format(Fields, ['FAnzahl := 0;']), 13));
end;

initialization
  TDUnitX.RegisterTestFixture(TTaskCommandsTests);

end.
