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
  cRoutineUnit =
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
  Assert.IsTrue(Run(Format(cRoutineUnit, [ACommand]), 10, mEdits), ACommand);
  Result := Apply(Format(cRoutineUnit, [ACommand]), mEdits);
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

procedure TRefactoringCommandsTests.FmtFormatsRoutine;
var
  mText: string;
begin
  mText := Expand('/fmt');
  Assert.IsTrue(Pos('begin'#10'  Liste := TStringList.Create;'#10'  Liste.Free;'#10'end;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('/fmt', mText), mText);
end;

procedure TRefactoringCommandsTests.FmtOutsideRoutineFails;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := StringReplace(Format(cRoutineUnit, ['']), 'procedure Run;'#10'implementation',
    '/fmt'#10'implementation', []);
  Assert.IsFalse(Run(mText, 4, mEdits));
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(mText, nil))));
end;

procedure TRefactoringCommandsTests.MeasureWrapsAndAddsUses;
var
  mText: string;
begin
  mText := Expand('/measure');
  Assert.IsTrue(Pos('begin'#10'  var SW := TStopwatch.StartNew;'#10'  try'#10 +
    '    Liste  :=TStringList.Create;   '#10'    Liste.Free;'#10'  finally'#10 +
    '    OutputDebugString(PChar(Format(''%s: %d ms'', [''U.Run'', SW.ElapsedMilliseconds])));'#10 +
    '  end;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Pos('System.Diagnostics', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRefactoringCommandsTests.MeasureOutsideRoutineFails;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := StringReplace(Format(cRoutineUnit, ['']), 'procedure Run;'#10'implementation',
    '/measure'#10'implementation', []);
  Assert.IsFalse(Run(mText, 4, mEdits));
end;

const
  cExtractUnit =
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

  cInlineUnit =
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

  cFixUri = 'file:///U.pas';

function RunWith(const AText: string; ALine: Integer; const AHost: ISlashHost; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.Run(AText, ALine, 0, TSlashEnvironment.Create(nil, nil, nil, '', cFixUri,
    AHost), AEdits, AReason);
end;

function Finding(const ARuleId, AMessage: string; ASafe: Boolean): TSlashFinding;
begin
  Result.RuleId := ARuleId;
  Result.Message := AMessage;
  Result.Explanation := ARuleId + ': Erklärung';
  Result.SafeFix := nil;
  if ASafe then
  begin
    Result.SafeFix := [TTextEdit.Create(TTextRange.Create(11, 2, 11, 7), 'Liste')];
  end;
end;

procedure TRefactoringCommandsTests.ExtractMakesValueAndVarParameters;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  // Abnahme: AValue wird nur gelesen (Wertparameter), Total geschrieben und danach gelesen (var).
  Assert.IsTrue(Run(Format(cExtractUnit, ['/extract Verdopple']), 9, mEdits));
  mText := Apply(Format(cExtractUnit, ['/extract Verdopple']), mEdits);
  Assert.IsTrue(Pos('procedure Verdopple(const AValue: Integer; var Total: Integer);', mText) > 0, mText);
  Assert.IsTrue(Pos('  Verdopple(AValue, Total);'#10#10'  Total := Total + 1;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('ExtractedMethod', mText), mText);
  Assert.AreEqual(0, Pos('/extract', mText), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRefactoringCommandsTests.ExtractOutsideRoutineFails;
var
  mEdits: TArray<TRuleEdit>;
  mText, mReason: string;
begin
  mText := StringReplace(Format(cExtractUnit, ['']), 'procedure Run(AValue: Integer);'#10'implementation',
    '/extract Neu'#10'implementation', []);
  Assert.IsFalse(RunWith(mText, 2, nil, mEdits, mReason));
  Assert.IsTrue(Pos('Rumpf einer Routine', mReason) > 0, mReason);
  // Ohne Namen.
  Assert.IsFalse(RunWith(Format(cExtractUnit, ['/extract']), 9, nil, mEdits, mReason));
  Assert.IsTrue(Pos('/extract Name', mReason) > 0, mReason);
end;

procedure TRefactoringCommandsTests.InlineEmbedsCall;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := Format(cInlineUnit, ['/inline', 'Y := Twice(X) + 1;']);
  Assert.IsTrue(Run(mText, 13, mEdits));
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('  X := 5;'#10'  Y := (X * 2) + 1;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRefactoringCommandsTests.InlineEmbedsVariable;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := Format(cInlineUnit, ['/inline', 'Y := X + 1;']);
  Assert.IsTrue(Run(mText, 13, mEdits));
  mText := Apply(mText, mEdits);
  Assert.IsTrue(Pos('begin'#10'  Y := 5 + 1;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRefactoringCommandsTests.InlineOutsideRoutineFails;
var
  mEdits: TArray<TRuleEdit>;
  mText, mReason: string;
begin
  mText := StringReplace(Format(cInlineUnit, ['', '']), 'implementation'#10, 'implementation'#10'/inline'#10, []);
  Assert.IsFalse(RunWith(mText, 3, nil, mEdits, mReason));
  Assert.IsTrue(Pos('Rumpf einer Routine', mReason) > 0, mReason);
end;

procedure TRefactoringCommandsTests.FixAppliesSafeFix;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason: string;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.HasFindings := True;
  mHost.Findings := [Finding('a', 'unsicher', False), Finding('b', 'sicher', True)];
  Assert.IsTrue(RunWith(Format(cRoutineUnit, ['/fix']), 10, mKeep, mEdits, mReason), mReason);
  Assert.AreEqual(2, Integer(Length(mEdits)));
  Assert.AreEqual('Liste', mEdits[0].NewText);
  Assert.AreEqual(11, mHost.RuleLine);
  mHost.Findings := nil;
end;

procedure TRefactoringCommandsTests.FixSkipsUnsafeFix;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason: string;
begin
  // Abnahme: Ein Treffer ohne sichere Korrektur ändert nichts.
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.HasFindings := True;
  mHost.Findings := [Finding('a', 'unsicher', False)];
  Assert.IsFalse(RunWith(Format(cRoutineUnit, ['/fix']), 10, mKeep, mEdits, mReason));
  Assert.AreEqual(NoSafeFixHint, mReason);
  Assert.AreEqual(0, Integer(Length(mEdits)));
  mHost.Findings := nil;
end;

procedure TRefactoringCommandsTests.FixWithoutFindingFails;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason: string;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.HasFindings := True;
  Assert.IsFalse(RunWith(Format(cRoutineUnit, ['/fix']), 10, mKeep, mEdits, mReason));
  Assert.AreEqual(NoFindingBelowHint, mReason);
  // Ohne Editor (Prüfung stehen gebliebener Zeilen) bleibt die Zeile mit Grund.
  Assert.IsFalse(RunWith(Format(cRoutineUnit, ['/fix']), 10, nil, mEdits, mReason));
  Assert.IsTrue(Pos('braucht den Editor', mReason) > 0, mReason);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Format(cRoutineUnit, ['/fix']), nil))));
end;

procedure TRefactoringCommandsTests.ExplainNotifiesFinding;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.HasFindings := True;
  mHost.Findings := [Finding('free-without-try', 'Free ohne try', False)];
  mText := Format(cRoutineUnit, ['/explain']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(11, 0),
    TSlashEnvironment.Create(nil, nil, nil, '', cFixUri, mKeep), mEdits));
  // Nur die Befehlszeile geht.
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(StringReplace(Format(cRoutineUnit, ['']), '  '#10'  Liste  :=', '  Liste  :=', []), Apply(mText, mEdits));
  Assert.AreEqual(1, Integer(Length(mHost.Notes)));
  Assert.AreEqual('Free ohne try'#10'free-without-try: Erklärung', mHost.Notes[0]);
  mHost.Findings := nil;
end;

procedure TRefactoringCommandsTests.ExplainWithoutFindingHints;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mEdits: TArray<TRuleEdit>;
  mReason: string;
begin
  // Abnahme: Ohne Treffer ein Hinweis; die Zeile bleibt.
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.HasFindings := True;
  Assert.IsFalse(RunWith(Format(cRoutineUnit, ['/explain']), 10, mKeep, mEdits, mReason));
  Assert.AreEqual(NoFindingBelowHint, mReason);
  Assert.AreEqual(0, Integer(Length(mHost.Notes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactoringCommandsTests);

end.
