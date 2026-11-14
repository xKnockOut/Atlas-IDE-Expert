unit Atlas.Common.Editing.TaskCommands.Tests;

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
    procedure TaskQueuesLabelCaption;
    [Test]
    procedure TaskNotesMovedLinesAndReadAfter;
    [Test]
    procedure ParallelConvertsLoop;
    [Test]
    procedure ParallelRejectsOuterSum;
    [Test]
    procedure ParallelRejectsBreakAndDownto;
    [Test]
    procedure ParallelWithoutLoopFails;
    [Test]
    procedure FutureInline;
    [Test]
    procedure FutureWithoutInlineDeclaresVar;
    [Test]
    procedure FutureMovesCursorBehind;
    [Test]
    procedure FutureWrongPlaceFails;
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Tests.SlashHost;

/// <summary>Führt den Befehl in Zeile ALine aus und wendet die Änderungen an; '' wenn er nicht passt.</summary>
function Expand(const AText: string; ALine: Integer;
  const AVersion: string): string; overload;
var
  mEdits: TArray<TRuleEdit>;
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  if not TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0),
    TSlashEnvironment.Create(nil, nil, nil, AVersion, '', nil), mEdits) then
  begin
    Exit('');
  end;
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(mEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in mEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string; overload;
begin
  Result := Expand(AText, ALine, '');
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

const
  cRoutine =
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

  cFields =
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
  mText: string;
begin
  mText := Expand(Format(cRoutine, ['/task', '  Rechne;'#10'  Speichere;']), 8);
  Assert.Contains(mText, '  TTask.Run('#10'    procedure'#10'    begin'#10'      Rechne;'#10'      Speichere;'#10 +
    '    end);'#10'end;');
  Assert.Contains(mText, 'System.Threading');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTaskCommandsTests.TaskQueuesVclAtEnd;
var
  mText: string;
begin
  mText := Expand(Format(cRoutine, ['/task', '  Rechne;'#10'  ShowMessage(''Fertig'');']), 8);
  Assert.Contains(mText, '      Rechne;'#10'      TThread.Queue(nil,'#10'        procedure'#10'        begin'#10 +
    '          ShowMessage(''Fertig'');'#10'        end);'#10'    end);');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTaskCommandsTests.TaskOutsideRoutineFails;
begin
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/task'#10'implementation'#10'end.', 2));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/task', '']), 8));
end;

const
  cFormUnit =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'uses Vcl.StdCtrls, Vcl.Forms;'#10 +        // 2
    'type'#10 +                                // 3
    '  TForm1 = class(TForm)'#10 +             // 4
    '    Label1: TLabel;'#10 +                 // 5
    '    procedure Start;'#10 +                // 6
    '  end;'#10 +                              // 7
    'implementation'#10 +                      // 8
    'procedure TForm1.Start;'#10 +             // 9
    'var'#10 +                                 // 10
    '  Summe: Integer;'#10 +                   // 11
    'begin'#10 +                               // 12
    '  if Bereit then'#10 +                    // 13
    '  begin'#10 +                             // 14
    '    /task'#10 +                           // 15
    '    Summe := Berechne;'#10 +              // 16
    '    Label1.Caption := ''Fertig'';'#10 +   // 17
    '  end;'#10 +                              // 18
    '  Melde(Summe);'#10 +                     // 19
    'end;'#10 +
    'end.';

procedure TTaskCommandsTests.TaskQueuesLabelCaption;
var
  mText: string;
begin
  // Label1 ist ein Feld vom Typ TLabel: die Zuweisung an Caption gehört in den Hauptthread.
  mText := Expand(cFormUnit, 15);
  Assert.Contains(mText, '        Summe := Berechne;'#10'        TThread.Queue(nil,'#10'          procedure'#10 +
    '          begin'#10'            Label1.Caption := ''Fertig'';'#10'          end);'#10'      end);');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTaskCommandsTests.TaskNotesMovedLinesAndReadAfter;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(cFormUnit, TTextPosition.Create(16, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', 'file:///U.pas', mKeep), mEdits));
  Assert.AreEqual(1, Integer(Length(mHost.Notes)));
  // Zeile 18 (1-basiert) wandert in TThread.Queue; Summe wird nach dem Block gelesen (#143).
  Assert.Contains(mHost.Notes[0], 'Zeile 18 fasst VCL-Objekte an');
  Assert.Contains(mHost.Notes[0], 'Summe wird im Task geschrieben und danach gelesen');
  // Ohne VCL-Zeilen und ohne spätere Lesezugriffe gibt es keinen Hinweis.
  mHost.Notes := nil;
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Format(cRoutine, ['/task', '  Rechne;']),
    TTextPosition.Create(9, 0), TSlashEnvironment.Create(nil, nil, nil, '', 'file:///U.pas', mKeep), mEdits));
  Assert.AreEqual(0, Integer(Length(mHost.Notes)));
end;

procedure TTaskCommandsTests.ParallelConvertsLoop;
var
  mText: string;
begin
  mText := Expand(Format(cRoutine, ['/parallel', '  for I := 0 to High(Liste) do'#10'    Verarbeite(Liste[I]);']), 8);
  Assert.Contains(mText, '  TParallel.For(0, High(Liste),'#10'    procedure(I: Integer)'#10'    begin'#10 +
    '      Verarbeite(Liste[I]);'#10'    end);'#10'end;');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TTaskCommandsTests.ParallelRejectsOuterSum;
begin
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  for I := 0 to 9 do'#10'    Summe := Summe + I;']), 8));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  for I := 0 to 9 do'#10'    Inc(Summe);']), 8));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  for I := 0 to 9 do'#10 +
    '    ShowMessage(IntToStr(I));']), 8));
end;

procedure TTaskCommandsTests.ParallelRejectsBreakAndDownto;
begin
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  for I := 0 to 9 do'#10'  begin'#10 +
    '    if Fertig(I) then'#10'      Break;'#10'  end;']), 8));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  for I := 9 downto 0 do'#10'    Verarbeite(I);']), 8));
end;

procedure TTaskCommandsTests.ParallelWithoutLoopFails;
begin
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  Rechne;']), 8));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/parallel', '  while Weiter do'#10'    Rechne;']), 8));
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/parallel'#10'implementation'#10'end.', 2));
end;

procedure TTaskCommandsTests.FutureInline;
var
  mText: string;
begin
  mText := Expand(Format(cRoutine, ['/future Wert: Integer', '  Text := Berechne;']), 8);
  Assert.Contains(mText, '  var Wert := TTask.Future<Integer>(');
  Assert.Contains(mText, '    function: Integer');
end;

procedure TTaskCommandsTests.FutureWithoutInlineDeclaresVar;
var
  mText: string;
begin
  mText := Expand(Format(cRoutine, ['/future Wert: Integer', '  Text := Berechne;']), 8, '19.0');
  Assert.Contains(mText, '  Wert := TTask.Future<Integer>(');
  Assert.Contains(mText, 'Wert: IFuture<Integer>;');
  Assert.DoesNotContain(mText, 'var Wert');
end;

procedure TTaskCommandsTests.FutureMovesCursorBehind;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
  mLines: TArray<string>;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mText := Format(cRoutine, ['/future Wert: Integer', '  Text := Berechne;']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(9, 0),
    TSlashEnvironment.Create(nil, nil, nil, '19.0', 'file:///U.pas', mKeep), mEdits));
  Assert.IsTrue(mHost.HasCursor);
  // Die leere Zeile hinter dem Future, an der Wert.Value gebraucht wird; mit var-Zeile davor (ohne Inline).
  mLines := Expand(mText, 8, '19.0').Split([#10]);
  Assert.AreEqual('    end);', mLines[mHost.Cursor.Line - 1]);
  Assert.AreEqual('  ', mLines[mHost.Cursor.Line]);
  Assert.AreEqual('end;', mLines[mHost.Cursor.Line + 1]);
  Assert.AreEqual(2, mHost.Cursor.Character);
end;

procedure TTaskCommandsTests.FutureWrongPlaceFails;
begin
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/future Wert: Integer'#10'implementation'#10'end.', 2));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/future Wert: Integer', '']), 8));
  Assert.AreEqual('', Expand(Format(cRoutine, ['/future Wert', '  Text := Berechne;']), 8));
end;

procedure TTaskCommandsTests.AtomicOnField;
begin
  Assert.Contains(Expand(Format(cFields, ['Inc(FAnzahl);']), 13), '  TInterlocked.Increment(FAnzahl);'#10'end;');
  Assert.Contains(Expand(Format(cFields, ['Dec(FAnzahl, 2);']), 13), '  TInterlocked.Add(FAnzahl, -(2));');
  Assert.Contains(Expand(Format(cFields, ['FAnzahl := FAnzahl + N;']), 13), '  TInterlocked.Add(FAnzahl, N);');
  Assert.Contains(Expand(Format(cFields, ['Inc(FAnzahl);']), 13), 'System.SyncObjs');
end;

procedure TTaskCommandsTests.AtomicOnLocalFails;
begin
  Assert.AreEqual('', Expand(Format(cFields, ['Inc(Lokal);']), 13));
  Assert.AreEqual('', Expand(Format(cFields, ['FAnzahl := 0;']), 13));
end;

initialization
  TDUnitX.RegisterTestFixture(TTaskCommandsTests);

end.
