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
  Source = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 +
    '  if A then'#13#10'    for I := 1 to 2 do'#13#10'      X(I);'#13#10'  with O do'#13#10'    Y;'#13#10 +
    'end;'#13#10'end.'#13#10;

function Run(const APosition: TTextPosition; AStyleIndent, AIndent: Integer): TJSONObject;
var
  Tree: TSyntaxTree;
  Context: TRefactoringContext;
begin
  Context := Default(TRefactoringContext);
  Context.Style.IndentSize := AStyleIndent;
  Tree := TPascalParser.Parse(Source);
  try
    Result := TLspUnwrap.Execute(nil, Tree, Source, APosition, Context, AIndent);
  finally
    Tree.Free;
  end;
end;

function Candidate(AAnswer: TJSONObject; AIndex: Integer): TJSONObject;
begin
  Result := (AAnswer.GetValue('candidates') as TJSONArray).Items[AIndex] as TJSONObject;
end;

function FirstEditText(ACandidate: TJSONObject): string;
var
  Variant0: TJSONObject;
begin
  Variant0 := (ACandidate.GetValue('variants') as TJSONArray).Items[0] as TJSONObject;
  Result := ((Variant0.GetValue('edits') as TJSONArray).Items[0] as TJSONObject).GetValue('newText').Value;
end;

procedure TLspUnwrapTests.AnswerShape;
var
  Answer, Item, Variant0: TJSONObject;
begin
  Answer := Run(TTextPosition.Create(7, 6), 2, 0);
  try
    Assert.AreEqual(2, (Answer.GetValue('candidates') as TJSONArray).Count);
    Item := Candidate(Answer, 0);
    Assert.AreEqual('forDo', Item.GetValue('kind').Value);
    Assert.AreEqual('loopVariable', Item.GetValue('note').Value);
    Assert.AreEqual('I', Item.GetValue('noteText').Value);
    Assert.AreEqual(6, ((Item.GetValue('range') as TJSONObject).GetValue('start') as TJSONObject).GetValue<Integer>(
      'line'));
    Variant0 := (Item.GetValue('variants') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('body', Variant0.GetValue('kind').Value);
    Assert.AreEqual(0, Variant0.GetValue<Integer>('branch'));
    Assert.AreEqual(1, (Variant0.GetValue('keep') as TJSONArray).Count);
    Assert.AreEqual(1, (Variant0.GetValue('remove') as TJSONArray).Count);
    Assert.AreEqual('ifThen', Candidate(Answer, 1).GetValue('kind').Value);
    Assert.AreEqual('', Candidate(Answer, 1).GetValue('note').Value);
  finally
    Answer.Free;
  end;
end;

procedure TLspUnwrapTests.IndentFromStyleOrArgument;
var
  Answer: TJSONObject;
begin
  Answer := Run(TTextPosition.Create(7, 6), 4, 0);
  try
    Assert.AreEqual('      X(I);'#13#10, FirstEditText(Candidate(Answer, 0)));
  finally
    Answer.Free;
  end;
  Answer := Run(TTextPosition.Create(7, 6), 4, 3);
  try
    Assert.AreEqual('     X(I);'#13#10, FirstEditText(Candidate(Answer, 0)));
  finally
    Answer.Free;
  end;
end;

procedure TLspUnwrapTests.WithWithoutResolver;
var
  Answer: TJSONObject;
begin
  Answer := Run(TTextPosition.Create(9, 4), 2, 0);
  try
    Assert.AreEqual('withDo', Candidate(Answer, 0).GetValue('kind').Value);
    Assert.AreEqual('withUnresolved', Candidate(Answer, 0).GetValue('note').Value);
    Assert.AreEqual(0, (Candidate(Answer, 0).GetValue('variants') as TJSONArray).Count);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUnwrapTests);

end.
