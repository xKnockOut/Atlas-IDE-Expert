unit Atlas.Common.Editing.ErrorCommands.Tests;

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
    /// <summary>#304: Zeiger (Pointer und P-Typen) bekommen eine Prüfung, Ereignisse nicht.</summary>
    [Test]
    procedure GuardChecksPointers;
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ErrorCommands;

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

function Expand(const AText: string; ALine: Integer): string;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, mEdits), AText);
  Result := Apply(AText, mEdits);
end;

function ProblemOf(const AText: string): string;
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Result := mProblems[0].Message;
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
  cRoutineUnit =
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
  Result := Format(cRoutineUnit, [ACommand]);
end;

procedure TErrorCommandsTests.ParametersFromSignature;
var
  mParameters: TArray<TGuardParameter>;
begin
  mParameters := RoutineParameters('procedure P(const A, B: TFoo; var C: Integer = 0)');
  Assert.AreEqual(3, Integer(Length(mParameters)));
  Assert.AreEqual('B', mParameters[1].Name);
  Assert.AreEqual('TFoo', mParameters[1].TypeName);
  Assert.AreEqual('Integer', mParameters[2].TypeName);
end;

procedure TErrorCommandsTests.GuardChecksOnlyObjects;
var
  mText: string;
begin
  mText := Expand(WithCommand('/guard'), 9);
  Assert.IsTrue(Pos('begin'#10'  if not Assigned(AObj) then'#10'    raise EArgumentNilException.Create(''AObj'');'#10 +
    '  if not Assigned(AListe) then'#10'    raise EArgumentNilException.Create(''AListe'');'#10'  X := 1;', mText) > 0,
    mText);
  Assert.AreEqual(0, Pos('Assigned(S)', mText), mText);
  Assert.AreEqual(0, Pos('Assigned(X)', mText), mText);
  Assert.AreEqual(0, Pos('Assigned(P)', mText), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TErrorCommandsTests.GuardSingleParameter;
var
  mText: string;
begin
  mText := Expand(WithCommand('/guard AListe'), 9);
  Assert.AreEqual(0, Pos('Assigned(AObj)', mText), mText);
  Assert.IsTrue(Pos('Assigned(AListe)', mText) > 0, mText);
  Assert.AreEqual('X ist kein ungeprüfter Objekt-, Interface- oder Zeigerparameter',
    ProblemOf(WithCommand('/guard X')));
end;

procedure TErrorCommandsTests.GuardChecksPointers;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10#10 +
    'procedure Lauf(Data: Pointer; AKnoten: PKnoten; AOnDone: TNotifyEvent; N: Integer);'#10'begin'#10 +
    '  /guard'#10'  N := 1;'#10'end;'#10#10'end.';
var
  mResult_: string;
begin
  mResult_ := Expand(cText, 8);
  Assert.IsTrue(Pos('Assigned(Data)', mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('Assigned(AKnoten)', mResult_) > 0, mResult_);
  Assert.AreEqual(0, Pos('Assigned(AOnDone)', mResult_), mResult_);
  Assert.AreEqual(0, Pos('Assigned(N)', mResult_), mResult_);
end;

procedure TErrorCommandsTests.GuardDoesNotDuplicate;
var
  mText: string;
begin
  mText := StringReplace(WithCommand('/guard'), '  X := 1;', '  if AObj = nil then Exit;'#10 +
    '  Assert(Assigned(AListe));', []);
  Assert.AreEqual('Keine ungeprüften Objekt-, Interface- oder Zeigerparameter', ProblemOf(mText));
end;

procedure TErrorCommandsTests.GuardOutsideRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'/guard'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/guard gilt nur im Rumpf einer Routine', ProblemOf(cText));
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
  cText = 'unit U;'#10'interface'#10'implementation'#10#10'procedure P;'#10'begin'#10'  /raise EImport Datei fehlt'#10 +
    'end;'#10#10'end.';
var
  mResult_: string;
begin
  mResult_ := Expand(cText, 6);
  Assert.IsTrue(Pos('uses'#10'  System.SysUtils;'#10, mResult_) > 0, mResult_);
  Assert.IsTrue(Pos('type'#10'  EImport = class(Exception);'#10#10'procedure P;'#10'begin'#10 +
    '  raise EImport.Create(''Datei fehlt'');'#10'end;', mResult_) > 0, mResult_);
  Assert.IsTrue(Parses(mResult_), mResult_);
end;

procedure TErrorCommandsTests.RaiseOutsideRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'/raise EX Text'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/raise gilt nur im Rumpf einer Routine', ProblemOf(cText));
  Assert.AreEqual('Erwartet wird /raise EKlasse Text', ProblemOf(WithCommand('/raise EX')));
end;

initialization
  TDUnitX.RegisterTestFixture(TErrorCommandsTests);

end.
