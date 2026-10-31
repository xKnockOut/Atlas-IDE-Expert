unit Atlas.Common.Editing.RefactoringCommands.Tests;

// Tests für die Schnellbefehle /fmt, /measure, /extract, /inline, /fix und /explain (#300).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRefactoringCommandsTests = class
  public
    [Test]
    procedure FmtFormatsRoutine;
    [Test]
    procedure FmtOutsideRoutineFails;
    [Test]
    procedure MeasureWrapsAndAddsUses;
    [Test]
    procedure MeasureOutsideRoutineFails;
    [Test]
    procedure ExtractMakesValueAndVarParameters;
    [Test]
    procedure ExtractOutsideRoutineFails;
    [Test]
    procedure InlineEmbedsCall;
    [Test]
    procedure InlineEmbedsVariable;
    [Test]
    procedure InlineOutsideRoutineFails;
    [Test]
    procedure FixAppliesSafeFix;
    [Test]
    procedure FixSkipsUnsafeFix;
    [Test]
    procedure FixWithoutFindingFails;
    [Test]
    procedure ExplainNotifiesFinding;
    [Test]
    procedure ExplainWithoutFindingHints;
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
  Atlas.Common.Editing.RefactoringCommands,
  Atlas.Tests.SlashHost;

const
  RoutineUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'uses'#10 +                                     // 2
    '  System.Classes;'#10 +                        // 3
    'procedure Run;'#10 +                           // 4
    'implementation'#10 +                           // 5
    'procedure Run;'#10 +                           // 6
    'var'#10 +                                      // 7
    '  Liste: TStringList;'#10 +                    // 8
    'begin'#10 +                                    // 9
    '  %s'#10 +                                     // 10 Befehl
    '  Liste  :=TStringList.Create;   '#10 +        // 11
    '  Liste.Free;'#10 +                            // 12
    'end;'#10 +                                     // 13
    'end.';

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
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
  Assert.IsTrue(Run(Format(RoutineUnit, [ACommand]), 10, Edits), ACommand);
  Result := Apply(Format(RoutineUnit, [ACommand]), Edits);
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

procedure TRefactoringCommandsTests.FmtFormatsRoutine;
var
  Text: string;
begin
  Text := Expand('/fmt');
  Assert.IsTrue(Pos('begin'#10'  Liste := TStringList.Create;'#10'  Liste.Free;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Pos('/fmt', Text) = 0, Text);
end;

procedure TRefactoringCommandsTests.FmtOutsideRoutineFails;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := StringReplace(Format(RoutineUnit, ['']), 'procedure Run;'#10'implementation',
    '/fmt'#10'implementation', []);
  Assert.IsFalse(Run(Text, 4, Edits));
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Text, nil))));
end;

procedure TRefactoringCommandsTests.MeasureWrapsAndAddsUses;
var
  Text: string;
begin
  Text := Expand('/measure');
  Assert.IsTrue(Pos('begin'#10'  var SW := TStopwatch.StartNew;'#10'  try'#10 +
    '    Liste  :=TStringList.Create;   '#10'    Liste.Free;'#10'  finally'#10 +
    '    OutputDebugString(PChar(Format(''%s: %d ms'', [''U.Run'', SW.ElapsedMilliseconds])));'#10 +
    '  end;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Pos('System.Diagnostics', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRefactoringCommandsTests.MeasureOutsideRoutineFails;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := StringReplace(Format(RoutineUnit, ['']), 'procedure Run;'#10'implementation',
    '/measure'#10'implementation', []);
  Assert.IsFalse(Run(Text, 4, Edits));
end;

const
  ExtractUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'procedure Run(AValue: Integer);'#10 +          // 2
    'implementation'#10 +                           // 3
    'procedure Run(AValue: Integer);'#10 +          // 4
    'var'#10 +                                      // 5
    '  Total, Temp: Integer;'#10 +                  // 6
    'begin'#10 +                                    // 7
    '  Total := 0;'#10 +                            // 8
    '  %s'#10 +                                     // 9 Befehl
    '  Temp := AValue * 2;'#10 +                    // 10
    '  Total := Total + Temp;'#10 +                 // 11
    ''#10 +                                         // 12
    '  Total := Total + 1;'#10 +                    // 13
    'end;'#10 +                                     // 14
    'end.';

  InlineUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'implementation'#10 +                           // 2
    'function Twice(A: Integer): Integer;'#10 +     // 3
    'begin'#10 +                                    // 4
    '  Result := A * 2;'#10 +                       // 5
    'end;'#10 +                                     // 6
    ''#10 +                                         // 7
    'procedure Run;'#10 +                           // 8
    'var'#10 +                                      // 9
    '  X, Y: Integer;'#10 +                         // 10
    'begin'#10 +                                    // 11
    '  X := 5;'#10 +                                // 12
    '  %s'#10 +                                     // 13 Befehl
    '  %s'#10 +                                     // 14
    'end;'#10 +                                     // 15
    'end.';

  FixUri = 'file:///U.pas';

function RunWith(const AText: string; ALine: Integer; const AHost: ISlashHost; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.Run(AText, ALine, 0, nil, nil, nil, '', FixUri, AHost, AEdits, AReason);
end;

function Finding(const ARuleId, AMessage: string; ASafe: Boolean): TSlashFinding;
begin
  Result.RuleId := ARuleId;
  Result.Message := AMessage;
  Result.Explanation := ARuleId + ': Erklärung';
  Result.SafeFix := nil;
  if ASafe then
    Result.SafeFix := [TTextEdit.Create(TTextRange.Create(11, 2, 11, 7), 'Liste')];
end;

procedure TRefactoringCommandsTests.ExtractMakesValueAndVarParameters;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  // Abnahme: AValue wird nur gelesen (Wertparameter), Total geschrieben und danach gelesen (var).
  Assert.IsTrue(Run(Format(ExtractUnit, ['/extract Verdopple']), 9, Edits));
  Text := Apply(Format(ExtractUnit, ['/extract Verdopple']), Edits);
  Assert.IsTrue(Pos('procedure Verdopple(const AValue: Integer; var Total: Integer);', Text) > 0, Text);
  Assert.IsTrue(Pos('  Verdopple(AValue, Total);'#10#10'  Total := Total + 1;', Text) > 0, Text);
  Assert.IsTrue(Pos('ExtractedMethod', Text) = 0, Text);
  Assert.IsTrue(Pos('/extract', Text) = 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRefactoringCommandsTests.ExtractOutsideRoutineFails;
var
  Edits: TArray<TRuleEdit>;
  Text, Reason: string;
begin
  Text := StringReplace(Format(ExtractUnit, ['']), 'procedure Run(AValue: Integer);'#10'implementation',
    '/extract Neu'#10'implementation', []);
  Assert.IsFalse(RunWith(Text, 2, nil, Edits, Reason));
  Assert.IsTrue(Pos('Rumpf einer Routine', Reason) > 0, Reason);
  // Ohne Namen.
  Assert.IsFalse(RunWith(Format(ExtractUnit, ['/extract']), 9, nil, Edits, Reason));
  Assert.IsTrue(Pos('/extract Name', Reason) > 0, Reason);
end;

procedure TRefactoringCommandsTests.InlineEmbedsCall;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := Format(InlineUnit, ['/inline', 'Y := Twice(X) + 1;']);
  Assert.IsTrue(Run(Text, 13, Edits));
  Text := Apply(Text, Edits);
  Assert.IsTrue(Pos('  X := 5;'#10'  Y := (X * 2) + 1;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRefactoringCommandsTests.InlineEmbedsVariable;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := Format(InlineUnit, ['/inline', 'Y := X + 1;']);
  Assert.IsTrue(Run(Text, 13, Edits));
  Text := Apply(Text, Edits);
  Assert.IsTrue(Pos('begin'#10'  Y := 5 + 1;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRefactoringCommandsTests.InlineOutsideRoutineFails;
var
  Edits: TArray<TRuleEdit>;
  Text, Reason: string;
begin
  Text := StringReplace(Format(InlineUnit, ['', '']), 'implementation'#10, 'implementation'#10'/inline'#10, []);
  Assert.IsFalse(RunWith(Text, 3, nil, Edits, Reason));
  Assert.IsTrue(Pos('Rumpf einer Routine', Reason) > 0, Reason);
end;

procedure TRefactoringCommandsTests.FixAppliesSafeFix;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Reason: string;
begin
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.HasFindings := True;
  Host.Findings := [Finding('a', 'unsicher', False), Finding('b', 'sicher', True)];
  Assert.IsTrue(RunWith(Format(RoutineUnit, ['/fix']), 10, Keep, Edits, Reason), Reason);
  Assert.AreEqual(2, Integer(Length(Edits)));
  Assert.AreEqual('Liste', Edits[0].NewText);
  Assert.AreEqual(11, Host.RuleLine);
  Host.Findings := nil;
end;

procedure TRefactoringCommandsTests.FixSkipsUnsafeFix;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Reason: string;
begin
  // Abnahme: Ein Treffer ohne sichere Korrektur ändert nichts.
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.HasFindings := True;
  Host.Findings := [Finding('a', 'unsicher', False)];
  Assert.IsFalse(RunWith(Format(RoutineUnit, ['/fix']), 10, Keep, Edits, Reason));
  Assert.AreEqual(NoSafeFixHint, Reason);
  Assert.AreEqual(0, Integer(Length(Edits)));
  Host.Findings := nil;
end;

procedure TRefactoringCommandsTests.FixWithoutFindingFails;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Reason: string;
begin
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.HasFindings := True;
  Assert.IsFalse(RunWith(Format(RoutineUnit, ['/fix']), 10, Keep, Edits, Reason));
  Assert.AreEqual(NoFindingBelowHint, Reason);
  // Ohne Editor (Prüfung stehen gebliebener Zeilen) bleibt die Zeile mit Grund.
  Assert.IsFalse(RunWith(Format(RoutineUnit, ['/fix']), 10, nil, Edits, Reason));
  Assert.IsTrue(Pos('braucht den Editor', Reason) > 0, Reason);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Format(RoutineUnit, ['/fix']), nil))));
end;

procedure TRefactoringCommandsTests.ExplainNotifiesFinding;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.HasFindings := True;
  Host.Findings := [Finding('free-without-try', 'Free ohne try', False)];
  Text := Format(RoutineUnit, ['/explain']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Text, TTextPosition.Create(11, 0), nil, nil, Edits, nil,
    '', FixUri, Keep));
  // Nur die Befehlszeile geht.
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(StringReplace(Format(RoutineUnit, ['']), '  '#10'  Liste  :=', '  Liste  :=', []), Apply(Text, Edits));
  Assert.AreEqual(1, Integer(Length(Host.Notes)));
  Assert.AreEqual('Free ohne try'#10'free-without-try: Erklärung', Host.Notes[0]);
  Host.Findings := nil;
end;

procedure TRefactoringCommandsTests.ExplainWithoutFindingHints;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Edits: TArray<TRuleEdit>;
  Reason: string;
begin
  // Abnahme: Ohne Treffer ein Hinweis; die Zeile bleibt.
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.HasFindings := True;
  Assert.IsFalse(RunWith(Format(RoutineUnit, ['/explain']), 10, Keep, Edits, Reason));
  Assert.AreEqual(NoFindingBelowHint, Reason);
  Assert.AreEqual(0, Integer(Length(Host.Notes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactoringCommandsTests);

end.
