unit Atlas.Core.Problems.Marks.Tests;

// Unterstreichungen der Probleme (#398, #1967): Zeichenbereich, Spalte,
// Ziel des Ausblendens und belegte Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemMarksTests = class
  public
    [Test]
    procedure CharRangeOnOneLine;
    [Test]
    procedure CharRangeAcrossLines;
    [Test]
    procedure EmptyRangeBecomesOneChar;
    [Test]
    procedure ColumnExpandsTabs;
    [Test]
    procedure HideTargetByRuleOrLine;
    [Test]
    procedure LinesCappedPerProblem;
  end;

implementation

uses
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Problems.Marks;

function Problem(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := AStartLine;
  Result.StartCharacter := AStartCharacter;
  Result.EndLine := AEndLine;
  Result.EndCharacter := AEndCharacter;
end;

{ TAtlasProblemMarksTests }

procedure TAtlasProblemMarksTests.CharRangeOnOneLine;
var
  mFrom, mTill: Integer;
begin
  TAtlasProblemMarks.CharRange(Problem(3, 2, 3, 5), 3, 'abcdefgh', mFrom, mTill);
  Assert.AreEqual(2, mFrom);
  Assert.AreEqual(5, mTill);
  TAtlasProblemMarks.CharRange(Problem(3, 2, 3, 50), 3, 'abcdefgh', mFrom, mTill);
  Assert.AreEqual(8, mTill);
end;

procedure TAtlasProblemMarksTests.CharRangeAcrossLines;
var
  mFrom, mTill: Integer;
begin
  TAtlasProblemMarks.CharRange(Problem(1, 4, 3, 2), 1, 'abcdef', mFrom, mTill);
  Assert.AreEqual(4, mFrom);
  Assert.AreEqual(6, mTill);
  TAtlasProblemMarks.CharRange(Problem(1, 4, 3, 2), 2, 'abcdef', mFrom, mTill);
  Assert.AreEqual(0, mFrom);
  Assert.AreEqual(6, mTill);
  TAtlasProblemMarks.CharRange(Problem(1, 4, 3, 2), 3, 'abcdef', mFrom, mTill);
  Assert.AreEqual(0, mFrom);
  Assert.AreEqual(2, mTill);
end;

procedure TAtlasProblemMarksTests.EmptyRangeBecomesOneChar;
var
  mFrom, mTill: Integer;
begin
  TAtlasProblemMarks.CharRange(Problem(0, 3, 0, 3), 0, 'abcdef', mFrom, mTill);
  Assert.AreEqual(3, mFrom);
  Assert.AreEqual(4, mTill);
  // Am Zeilenende: das letzte Zeichen.
  TAtlasProblemMarks.CharRange(Problem(0, 9, 0, 9), 0, 'abc', mFrom, mTill);
  Assert.AreEqual(2, mFrom);
  Assert.AreEqual(3, mTill);
  TAtlasProblemMarks.CharRange(Problem(0, 0, 0, 0), 0, '', mFrom, mTill);
  Assert.AreEqual(0, mFrom);
  Assert.AreEqual(1, mTill);
end;

procedure TAtlasProblemMarksTests.ColumnExpandsTabs;
begin
  Assert.AreEqual(1, TAtlasProblemMarks.Column('abc', 0, 4));
  Assert.AreEqual(3, TAtlasProblemMarks.Column('abc', 2, 4));
  Assert.AreEqual(5, TAtlasProblemMarks.Column(#9'x', 1, 4));
  Assert.AreEqual(1, TAtlasProblemMarks.Column('abc', -1, 4));
end;

procedure TAtlasProblemMarksTests.HideTargetByRuleOrLine;
var
  mProblem: TAtlasProblem;
  mTarget: TAtlasHideTarget;
begin
  mProblem := Problem(5, 0, 7, 1);
  mProblem.Code := 'empty-except';
  mProblem.Message := 'Leer';
  mTarget := TAtlasProblemMarks.HideTarget('A.pas', mProblem, 6, 'x');
  Assert.AreEqual(5, mTarget.Line);
  Assert.AreEqual('empty-except', mTarget.RuleId);
  Assert.AreEqual('Leer (empty-except)', mTarget.Caption);
  mProblem.Source := TAtlasProblem.cCompilerSource;
  mTarget := TAtlasProblemMarks.HideTarget('A.pas', mProblem, 6, 'x');
  Assert.AreEqual(6, mTarget.Line);
  Assert.AreEqual('', mTarget.RuleId);
  mProblem.Source := '';
  mProblem.Code := '';
  mTarget := TAtlasProblemMarks.HideTarget('A.pas', mProblem, 6, 'x');
  Assert.AreEqual(6, mTarget.Line);
  Assert.AreEqual('Leer', mTarget.Caption);
end;

procedure TAtlasProblemMarksTests.LinesCappedPerProblem;
var
  mLines: TArray<Integer>;
begin
  mLines := TAtlasProblemMarks.Lines([Problem(2, 0, 4, 0), Problem(10, 0, 10, 1)]);
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.AreEqual(2, mLines[0]);
  Assert.AreEqual(4, mLines[2]);
  Assert.AreEqual(10, mLines[3]);
  mLines := TAtlasProblemMarks.Lines([Problem(0, 0, 1000, 0)]);
  Assert.AreEqual(TAtlasProblemMarks.cMaxSpan, Integer(Length(mLines)));
  Assert.AreEqual(0, Integer(Length(TAtlasProblemMarks.Lines(nil))));
  mLines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemMarksTests);

end.
