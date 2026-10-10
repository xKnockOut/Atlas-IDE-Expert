unit Argus.Common.Editing.ErrorCommands.Tests;

// Tests für die Schnellbefehle /guard und /raise (#304).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TErrorCommandsTests = class
  public
    [Test]
    procedure ParametersFromSignature;
    [Test]
    procedure GuardChecksOnlyObjects;
    [Test]
    procedure GuardSingleParameter;
    [Test]
    procedure GuardDoesNotDuplicate;
    [Test]
    procedure GuardOutsideRoutineFails;
    [Test]
    procedure RaiseKnownClass;
    [Test]
    procedure RaiseWithPlaceholdersUsesCreateFmt;
    [Test]
    procedure RaiseUnknownClassCreatesIt;
    [Test]
    procedure RaiseOutsideRoutineFails;
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
  Argus.Common.Editing.SlashCommands,
  Argus.Common.Editing.ErrorCommands;

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
  RoutineUnit =
    'unit U;'#10 +                                                          // 0
    'interface'#10 +                                                        // 1
    'implementation'#10 +                                                   // 2
    'uses'#10 +                                                             // 3
    '  System.SysUtils;'#10 +                                               // 4
    #10 +                                                                   // 5
    'procedure Lauf(const S: string; AObj: TObject; var X: Integer;'#10 +   // 6
    '  const AListe: IInterface; P: TPoint);'#10 +                          // 7
    'begin'#10 +                                                            // 8
    '  %s'#10 +                                                             // 9 Befehl
    '  X := 1;'#10 +                                                        // 10
    'end;'#10 +                                                             // 11
    #10 +                                                                   // 12
    'end.';

function WithCommand(const ACommand: string): string;
begin
  Result := Format(RoutineUnit, [ACommand]);
end;

procedure TErrorCommandsTests.ParametersFromSignature;
var
  Parameters: TArray<TGuardParameter>;
begin
  Parameters := RoutineParameters('procedure P(const A, B: TFoo; var C: Integer = 0)');
  Assert.AreEqual(3, Integer(Length(Parameters)));
  Assert.AreEqual('B', Parameters[1].Name);
  Assert.AreEqual('TFoo', Parameters[1].TypeName);
  Assert.AreEqual('Integer', Parameters[2].TypeName);
end;

procedure TErrorCommandsTests.GuardChecksOnlyObjects;
var
  Text: string;
begin
  Text := Expand(WithCommand('/guard'), 9);
  Assert.IsTrue(Pos('begin'#10'  if not Assigned(AObj) then'#10'    raise EArgumentNilException.Create(''AObj'');'#10 +
    '  if not Assigned(AListe) then'#10'    raise EArgumentNilException.Create(''AListe'');'#10'  X := 1;', Text) > 0,
    Text);
  Assert.AreEqual(0, Pos('Assigned(S)', Text), Text);
  Assert.AreEqual(0, Pos('Assigned(X)', Text), Text);
  Assert.AreEqual(0, Pos('Assigned(P)', Text), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TErrorCommandsTests.GuardSingleParameter;
var
  Text: string;
begin
  Text := Expand(WithCommand('/guard AListe'), 9);
  Assert.AreEqual(0, Pos('Assigned(AObj)', Text), Text);
  Assert.IsTrue(Pos('Assigned(AListe)', Text) > 0, Text);
  Assert.AreEqual('X ist kein ungeprüfter Objekt-, Interface- oder Zeigerparameter',
    ProblemOf(WithCommand('/guard X')));
end;

procedure TErrorCommandsTests.GuardDoesNotDuplicate;
var
  Text: string;
begin
  Text := StringReplace(WithCommand('/guard'), '  X := 1;', '  if AObj = nil then Exit;'#10 +
    '  Assert(Assigned(AListe));', []);
  Assert.AreEqual('Keine ungeprüften Objekt-, Interface- oder Zeigerparameter', ProblemOf(Text));
end;

procedure TErrorCommandsTests.GuardOutsideRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'/guard'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/guard gilt nur im Rumpf einer Routine', ProblemOf(Text));
end;

procedure TErrorCommandsTests.RaiseKnownClass;
begin
  Assert.AreEqual(WithCommand('raise EArgumentException.Create(''Kein Wert'');'),
    Expand(WithCommand('/raise EArgumentException Kein Wert'), 9));
end;

procedure TErrorCommandsTests.RaiseWithPlaceholdersUsesCreateFmt;
begin
  Assert.AreEqual(WithCommand('raise EConvertError.CreateFmt(''Wert %d ungültig'', []);'),
    Expand(WithCommand('/raise EConvertError Wert %d ungültig'), 9));
end;

procedure TErrorCommandsTests.RaiseUnknownClassCreatesIt;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10#10'procedure P;'#10'begin'#10'  /raise EImport Datei fehlt'#10 +
    'end;'#10#10'end.';
var
  Result_: string;
begin
  Result_ := Expand(Text, 6);
  Assert.IsTrue(Pos('uses'#10'  System.SysUtils;'#10, Result_) > 0, Result_);
  Assert.IsTrue(Pos('type'#10'  EImport = class(Exception);'#10#10'procedure P;'#10'begin'#10 +
    '  raise EImport.Create(''Datei fehlt'');'#10'end;', Result_) > 0, Result_);
  Assert.IsTrue(Parses(Result_), Result_);
end;

procedure TErrorCommandsTests.RaiseOutsideRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'/raise EX Text'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/raise gilt nur im Rumpf einer Routine', ProblemOf(Text));
  Assert.AreEqual('Erwartet wird /raise EKlasse Text', ProblemOf(WithCommand('/raise EX')));
end;

initialization
  TDUnitX.RegisterTestFixture(TErrorCommandsTests);

end.
