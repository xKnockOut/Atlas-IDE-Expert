unit Argus.Common.Editing.MaintenanceCommands.Tests;

// Tests für die Schnellbefehle /sortuses, /ignore, /todo, /doc und /log (#297).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMaintenanceCommandsTests = class
  public
    [Test]
    procedure SortUsesSortsAndRemovesLine;
    [Test]
    procedure IgnoreWritesSuppression;
    [Test]
    procedure IgnoreWithoutLineBelowFails;
    [Test]
    procedure TodoUsesIdeFormat;
    [Test]
    procedure TodoWithoutTextFails;
    [Test]
    procedure DocForFunction;
    [Test]
    procedure DocForMultiLineProcedure;
    [Test]
    procedure DocWithoutRoutineFails;
    [Test]
    procedure LogNamesUnitAndRoutine;
    [Test]
    procedure LogOutsideRoutineFails;
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

function Expand(const AText: string; ALine: Integer): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, Edits), AText);
  Result := Apply(AText, Edits);
end;

function ProblemOf(const AText: string): string;
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Result := Problems[0].Message;
end;

const
  Routine =
    'unit Daten;'#10'interface'#10'implementation'#10'procedure TFoo.Laden;'#10'begin'#10'  %s'#10 +
    '  X := 1;'#10'end;'#10'end.';

procedure TMaintenanceCommandsTests.SortUsesSortsAndRemovesLine;
const
  Text = 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10'implementation'#10 +
    '/sortuses'#10#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.Classes,'#10'  System.SysUtils;'#10 +
    'implementation'#10#10'end.', Expand(Text, 5));
end;

procedure TMaintenanceCommandsTests.IgnoreWritesSuppression;
begin
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: magic-number -- Absicht']),
    Expand(Format(Routine, ['/ignore Magic-Number Absicht']), 5));
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: magic-number']),
    Expand(Format(Routine, ['/ignore magic-number']), 5));
end;

procedure TMaintenanceCommandsTests.IgnoreWithoutLineBelowFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'/ignore magic-number'#10#10'end.';
begin
  Assert.AreEqual('Unter /ignore steht keine Zeile, die unterdrückt werden kann', ProblemOf(Text));
  Assert.AreEqual('Erwartet wird /ignore regel [Begründung]', ProblemOf(Format(Routine, ['/ignore ä'])));
end;

procedure TMaintenanceCommandsTests.TodoUsesIdeFormat;
begin
  Assert.AreEqual(Format(Routine, ['// TODO : Fehlerfall prüfen']),
    Expand(Format(Routine, ['/todo Fehlerfall prüfen']), 5));
end;

procedure TMaintenanceCommandsTests.TodoWithoutTextFails;
begin
  Assert.AreEqual('Erwartet wird /todo Text', ProblemOf(Format(Routine, ['/todo'])));
end;

procedure TMaintenanceCommandsTests.DocForFunction;
const
  Text = 'unit U;'#10'interface'#10'/doc'#10'function Summe(const A, B: Integer): Integer;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'/// <summary></summary>'#10'/// <param name="A"></param>'#10 +
    '/// <param name="B"></param>'#10'/// <returns></returns>'#10 +
    'function Summe(const A, B: Integer): Integer;'#10'implementation'#10'end.', Expand(Text, 2));
end;

procedure TMaintenanceCommandsTests.DocForMultiLineProcedure;
const
  Text = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    /doc'#10'    procedure Lauf(X: Integer;'#10 +
    '      var Y: string);'#10'  end;'#10'implementation'#10'end.';
var
  Result_: string;
begin
  Result_ := Expand(Text, 4);
  Assert.IsTrue(Pos('    /// <summary></summary>'#10'    /// <param name="X"></param>'#10 +
    '    /// <param name="Y"></param>'#10'    procedure Lauf(', Result_) > 0, Result_);
  Assert.AreEqual(0, Pos('returns', Result_));
end;

procedure TMaintenanceCommandsTests.DocWithoutRoutineFails;
begin
  Assert.AreEqual('/doc gilt nur über einer Routine', ProblemOf(Format(Routine, ['/doc'])));
end;

procedure TMaintenanceCommandsTests.LogNamesUnitAndRoutine;
begin
  Assert.AreEqual(Format(Routine, ['OutputDebugString(PChar(''Daten.TFoo.Laden''));']),
    Expand(Format(Routine, ['/log']), 5));
  Assert.AreEqual(Format(Routine, ['OutputDebugString(PChar(''Daten.TFoo.Laden: Start''));']),
    Expand(Format(Routine, ['/log Start']), 5));
end;

procedure TMaintenanceCommandsTests.LogOutsideRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'/log'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/log gilt nur im Rumpf einer Routine', ProblemOf(Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TMaintenanceCommandsTests);

end.
