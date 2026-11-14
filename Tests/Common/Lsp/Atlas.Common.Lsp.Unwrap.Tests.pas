unit Atlas.Common.Lsp.Unwrap.Tests;

// Tests für den Befehl atlas.server.unwrap (#657): Form der Antwort,
// Einrückung aus dem Formatierstil oder dem Argument und with ohne
// Namensauflösung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspUnwrapTests = class
  public
    [Test]
    procedure AnswerShape;
    [Test]
    procedure IndentFromStyleOrArgument;
    [Test]
    procedure WithWithoutResolver;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.Refactorings,
  Atlas.Common.Lsp.Unwrap;

const
  cSource = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 +
    '  if A then'#13#10'    for I := 1 to 2 do'#13#10'      X(I);'#13#10'  with O do'#13#10'    Y;'#13#10 +
    'end;'#13#10'end.'#13#10;

function Run(const APosition: TTextPosition; AStyleIndent, AIndent: Integer): TJSONObject;
var
  mTree: TSyntaxTree;
  mContext: TRefactoringContext;
begin
  mContext := Default(TRefactoringContext);
  mContext.Style.IndentSize := AStyleIndent;
  mTree := TPascalParser.Parse(cSource);
  try
    Result := TLspUnwrap.Execute(nil, mTree, cSource, APosition, mContext, AIndent);
  finally
    mTree.Free;
  end;
end;

function Candidate(AAnswer: TJSONObject; AIndex: Integer): TJSONObject;
begin
  Result := (AAnswer.GetValue('candidates') as TJSONArray).Items[AIndex] as TJSONObject;
end;

function FirstEditText(ACandidate: TJSONObject): string;
var
  mVariant0: TJSONObject;
begin
  mVariant0 := (ACandidate.GetValue('variants') as TJSONArray).Items[0] as TJSONObject;
  Result := ((mVariant0.GetValue('edits') as TJSONArray).Items[0] as TJSONObject).GetValue('newText').Value;
end;

procedure TLspUnwrapTests.AnswerShape;
var
  mAnswer, mItem, mVariant0: TJSONObject;
begin
  mAnswer := Run(TTextPosition.Create(7, 6), 2, 0);
  try
    Assert.AreEqual(2, (mAnswer.GetValue('candidates') as TJSONArray).Count);
    mItem := Candidate(mAnswer, 0);
    Assert.AreEqual('forDo', mItem.GetValue('kind').Value);
    Assert.AreEqual('loopVariable', mItem.GetValue('note').Value);
    Assert.AreEqual('I', mItem.GetValue('noteText').Value);
    Assert.AreEqual(6, ((mItem.GetValue('range') as TJSONObject).GetValue('start') as TJSONObject).GetValue<Integer>(
      'line'));
    mVariant0 := (mItem.GetValue('variants') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('body', mVariant0.GetValue('kind').Value);
    Assert.AreEqual(0, mVariant0.GetValue<Integer>('branch'));
    Assert.AreEqual(1, (mVariant0.GetValue('keep') as TJSONArray).Count);
    Assert.AreEqual(1, (mVariant0.GetValue('remove') as TJSONArray).Count);
    Assert.AreEqual('ifThen', Candidate(mAnswer, 1).GetValue('kind').Value);
    Assert.AreEqual('', Candidate(mAnswer, 1).GetValue('note').Value);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspUnwrapTests.IndentFromStyleOrArgument;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Run(TTextPosition.Create(7, 6), 4, 0);
  try
    Assert.AreEqual('      X(I);'#13#10, FirstEditText(Candidate(mAnswer, 0)));
  finally
    mAnswer.Free;
  end;
  mAnswer := Run(TTextPosition.Create(7, 6), 4, 3);
  try
    Assert.AreEqual('     X(I);'#13#10, FirstEditText(Candidate(mAnswer, 0)));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspUnwrapTests.WithWithoutResolver;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Run(TTextPosition.Create(9, 4), 2, 0);
  try
    Assert.AreEqual('withDo', Candidate(mAnswer, 0).GetValue('kind').Value);
    Assert.AreEqual('withUnresolved', Candidate(mAnswer, 0).GetValue('note').Value);
    Assert.AreEqual(0, (Candidate(mAnswer, 0).GetValue('variants') as TJSONArray).Count);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUnwrapTests);

end.
