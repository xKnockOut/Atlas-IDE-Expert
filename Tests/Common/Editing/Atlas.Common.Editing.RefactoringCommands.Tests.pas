unit Atlas.Common.Editing.RefactoringCommands.Tests;

// Tests für die Schnellbefehle /fmt und /measure (#300).

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
  Atlas.Common.Editing.SlashCommands;

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

initialization
  TDUnitX.RegisterTestFixture(TRefactoringCommandsTests);

end.
