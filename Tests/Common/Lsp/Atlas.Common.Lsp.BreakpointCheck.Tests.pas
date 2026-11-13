unit Atlas.Common.Lsp.BreakpointCheck.Tests;

// Tests für die Einordnung von Haltepunktzeilen (#577): Zeilen mit und ohne
// Code, inaktive Zweige, {$D-} aus der Unit und aus dem Projekt, nächste
// Codezeile und JSON.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Lsp.BreakpointCheck;

type
  [TestFixture]
  TLspBreakpointCheckTests = class
  private
    FTree: TSyntaxTree;
    FProcessed: TPreprocessorResult;
    FInput: TCompilerSwitchInput;
    procedure Read(const AText: string; const ADefines: TArray<string>);
    function Verdict(ALine: Integer): TLspBreakpointVerdict;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StatementLinesAreOk;
    [Test]
    procedure BeginAndEndOfRoutineAreOk;
    [Test]
    procedure CommentAndBlankLinesHaveNoCode;
    [Test]
    procedure DeclarationsHaveNoCode;
    [Test]
    procedure ContinuationLineHasNoCode;
    [Test]
    procedure ElseLineHasNoCode;
    [Test]
    procedure UntilLineIsOk;
    [Test]
    procedure NextLineStaysInRoutine;
    [Test]
    procedure BetweenRoutinesNextIsFollowingRoutine;
    [Test]
    procedure InactiveBranchNamesCondition;
    [Test]
    procedure ActiveBranchIsOk;
    [Test]
    procedure LocalDebugInfoOff;
    [Test]
    procedure ProjectDebugInfoOff;
    [Test]
    procedure ReadFilesSkipsInvalid;
    [Test]
    procedure JsonOnlyProblems;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.TreeCache;

const
  Source =
    'unit Kunden;'#10 +                                         // 0
    'interface'#10 +                                            // 1
    'implementation'#10 +                                       // 2
    ''#10 +                                                     // 3
    '// Speichert den Kunden.'#10 +                             // 4
    'procedure Speichere(ANr: Integer);'#10 +                   // 5
    'var'#10 +                                                  // 6
    '  mText: string;'#10 +                                     // 7
    'begin'#10 +                                                // 8
    '  mText := IntToStr(ANr);'#10 +                            // 9
    '  // Kommentar'#10 +                                       // 10
    '  if ANr > 0 then'#10 +                                    // 11
    '    Schreibe(mText,'#10 +                                  // 12
    '      ANr)'#10 +                                           // 13
    '  else'#10 +                                               // 14
    '    Schreibe('''', 0);'#10 +                               // 15
    ''#10 +                                                     // 16
    '  repeat'#10 +                                             // 17
    '    Dec(ANr);'#10 +                                        // 18
    '  until ANr = 0;'#10 +                                     // 19
    'end;'#10 +                                                 // 20
    ''#10 +                                                     // 21
    'procedure Lade;'#10 +                                      // 22
    'begin'#10 +                                                // 23
    '{$IFDEF RELEASE}'#10 +                                     // 24
    '  Schreibe(''r'', 1);'#10 +                                // 25
    '{$ELSE}'#10 +                                              // 26
    '  Schreibe(''d'', 2);'#10 +                                // 27
    '{$ENDIF}'#10 +                                             // 28
    'end;'#10 +                                                 // 29
    ''#10 +                                                     // 30
    'end.'#10;                                                  // 31

{ TLspBreakpointCheckTests }

procedure TLspBreakpointCheckTests.Read(const AText: string; const ADefines: TArray<string>);
var
  mOptions: TPreprocessorOptions;
  mTreeRun: TPreprocessorResult;
begin
  FreeAndNil(FTree);
  mOptions := TPascalPreprocessor.EditorOptions(ADefines);
  FTree := TSyntaxTreeCache.ParseActive(AText, mOptions, nil, mTreeRun);
  // ParseActive spart den Präprozessor bei Texten ohne Bedingung; die Prüfung braucht immer einen vollen Lauf.
  FProcessed := TPascalPreprocessor.Process(AText, mOptions);
  FInput := Default(TCompilerSwitchInput);
  FInput.Defines := ADefines;
end;

function TLspBreakpointCheckTests.Verdict(ALine: Integer): TLspBreakpointVerdict;
var
  mVerdicts: TLspBreakpointVerdicts;
begin
  mVerdicts := TLspBreakpointCheck.Check(FTree, FProcessed, FInput, [ALine]);
  Assert.AreEqual(1, Integer(Length(mVerdicts)));
  Result := mVerdicts[0];
end;

procedure TLspBreakpointCheckTests.TearDown;
begin
  FreeAndNil(FTree);
  FProcessed := Default(TPreprocessorResult);
  FInput := Default(TCompilerSwitchInput);
end;

procedure TLspBreakpointCheckTests.StatementLinesAreOk;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(9).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(11).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(12).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(15).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(18).Reason));
end;

procedure TLspBreakpointCheckTests.BeginAndEndOfRoutineAreOk;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(8).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(20).Reason));
end;

procedure TLspBreakpointCheckTests.CommentAndBlankLinesHaveNoCode;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(10).Reason));
  Assert.AreEqual(11, Verdict(10).NextLine);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(16).Reason));
  Assert.AreEqual(17, Verdict(16).NextLine);
end;

procedure TLspBreakpointCheckTests.DeclarationsHaveNoCode;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(5).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(6).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(7).Reason));
  Assert.AreEqual(8, Verdict(7).NextLine);
end;

procedure TLspBreakpointCheckTests.ContinuationLineHasNoCode;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(13).Reason));
  Assert.AreEqual(15, Verdict(13).NextLine);
end;

procedure TLspBreakpointCheckTests.ElseLineHasNoCode;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(14).Reason));
end;

procedure TLspBreakpointCheckTests.UntilLineIsOk;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(17).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(19).Reason));
end;

procedure TLspBreakpointCheckTests.NextLineStaysInRoutine;
begin
  // Hinter dem letzten Code einer Routine gibt es keinen Vorschlag in der nächsten.
  Read('unit A;'#10'implementation'#10'procedure P;'#10'begin'#10'  X;'#10'  // Ende'#10'end;'#10'end.'#10, []);
  Assert.AreEqual(6, Verdict(5).NextLine);
end;

procedure TLspBreakpointCheckTests.BetweenRoutinesNextIsFollowingRoutine;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoCode), Ord(Verdict(21).Reason));
  Assert.AreEqual(23, Verdict(21).NextLine);
end;

procedure TLspBreakpointCheckTests.InactiveBranchNamesCondition;
var
  mVerdict: TLspBreakpointVerdict;
begin
  Read(Source, ['DEBUG']);
  mVerdict := Verdict(25);
  Assert.AreEqual(Ord(TLspBreakpointReason.Inactive), Ord(mVerdict.Reason));
  Assert.IsTrue(Pos('RELEASE', UpperCase(mVerdict.Detail)) > 0, mVerdict.Detail);
end;

procedure TLspBreakpointCheckTests.ActiveBranchIsOk;
begin
  Read(Source, ['DEBUG']);
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(27).Reason));
  Read(Source, ['RELEASE']);
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(25).Reason));
  Assert.AreEqual(Ord(TLspBreakpointReason.Inactive), Ord(Verdict(27).Reason));
end;

procedure TLspBreakpointCheckTests.LocalDebugInfoOff;
var
  mVerdict: TLspBreakpointVerdict;
begin
  Read('unit A;'#10'{$D-}'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  X;'#10'end;'#10'end.'#10,
    []);
  mVerdict := Verdict(6);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoDebugInfo), Ord(mVerdict.Reason));
  Assert.IsTrue(Pos('D-', mVerdict.Detail) > 0, mVerdict.Detail);
end;

procedure TLspBreakpointCheckTests.ProjectDebugInfoOff;
begin
  // Stand aus der .dproj kommt als Schaltereintrag in den Symbolen.
  Read('unit A;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  X;'#10'end;'#10'end.'#10, ['$D-']);
  Assert.AreEqual(Ord(TLspBreakpointReason.NoDebugInfo), Ord(Verdict(5).Reason));
  Read('unit A;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  X;'#10'end;'#10'end.'#10, ['$D+']);
  Assert.AreEqual(Ord(TLspBreakpointReason.Ok), Ord(Verdict(5).Reason));
end;

procedure TLspBreakpointCheckTests.ReadFilesSkipsInvalid;
var
  mArguments: TJSONArray;
  mFiles: TArray<TLspBreakpointFile>;
begin
  mArguments := TJSONObject.ParseJSONValue(
    '[[{"uri": "file:///a.pas", "lines": [3, 7]}, {"uri": ""}, 5, {"uri": "file:///b.pas", "lines": []}]]')
    as TJSONArray;
  try
    mFiles := TLspBreakpointCheck.ReadFiles(mArguments);
  finally
    mArguments.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('file:///a.pas', mFiles[0].Uri);
  Assert.AreEqual(2, Integer(Length(mFiles[0].Lines)));
  Assert.AreEqual(7, mFiles[0].Lines[1]);
  Assert.AreEqual(0, Integer(Length(mFiles[1].Lines)));
end;

procedure TLspBreakpointCheckTests.JsonOnlyProblems;
var
  mVerdicts: TLspBreakpointVerdicts;
  mFile: TJSONObject;
  mAnswer: TJSONObject;
begin
  Read(Source, ['DEBUG']);
  mVerdicts := TLspBreakpointCheck.Check(FTree, FProcessed, FInput, [9, 10, 25]);
  mFile := TLspBreakpointCheck.FileToJson('file:///k.pas', mVerdicts);
  mAnswer := TLspBreakpointCheck.AnswerToJson([mFile, nil]);
  try
    Assert.AreEqual(
      '{"format":1,"files":[{"uri":"file:///k.pas","items":[{"line":10,"reason":"noCode","nextLine":11},' +
      '{"line":25,"reason":"inactive","detail":"RELEASE"}]}]}', mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  mVerdicts := TLspBreakpointCheck.Check(FTree, FProcessed, FInput, [9]);
  Assert.IsNull(TLspBreakpointCheck.FileToJson('file:///k.pas', mVerdicts));
end;

end.
