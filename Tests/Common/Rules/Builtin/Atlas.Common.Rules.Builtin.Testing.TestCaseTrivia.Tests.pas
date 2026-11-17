unit Atlas.Common.Rules.Builtin.Testing.TestCaseTrivia.Tests;

// Tests des Umfelds der TestCase-Attribute: Kommentare in eigener Zeile, davor und dahinter, über dem ersten und
// hinter dem letzten Fall, bedingte Direktiven um genau einen Fall (auch über dem ersten bzw. unter dem letzten),
// Direktiven, die sich nicht erhalten lassen, und das Zusammensetzen beim Schreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCaseTriviaTests = class
  public
    [Test]
    procedure CommentLinesBelongToTheNextCase;
    [Test]
    procedure CommentAtLineEndBelongsToItsCase;
    [Test]
    procedure CommentsAboveFirstAndBehindLastAreIncluded;
    [Test]
    procedure BlankLineEndsCommentsAboveFirst;
    [Test]
    procedure DirectiveAroundOneCaseIsBound;
    [Test]
    procedure DirectiveAroundFirstAndLastCase;
    [Test]
    procedure DirectiveAroundAllCasesStaysOutside;
    [Test]
    procedure DirectivesThatCannotBeKept;
    [Test]
    procedure InactiveCaseKeepsItsCondition;
    [Test]
    procedure CodeBetweenAttributes;
    [Test]
    procedure WrapAndLineComment;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Builtin.Testing.TestCaseTrivia,
  Atlas.Text.Lines;

/// <summary>Klasse mit den Zeilen ABody vor der Methode Pruefe; ABody beginnt in Zeile 4.</summary>
function ClassText(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  T = class'#10 + ABody + '    procedure Pruefe(A: Integer);'#10 +
    '  end;'#10'implementation'#10'procedure T.Pruefe(A: Integer);'#10'begin'#10'end;'#10'end.';
end;

/// <summary>Sucht die Methode Pruefe unterhalb von ANode.</summary>
function FindHeader(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = TSyntaxKind.RoutineHeader) and SameText(ANode.Name, 'Pruefe') then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindHeader(ANode[mIndex]);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>Umfeld der Attribute vor Pruefe in AText.</summary>
function BindingOf(const AText: string): TTriviaBinding;
var
  mTree: TSyntaxTree;
  mHeader: TSyntaxNode;
  mAttributes: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mHeader := FindHeader(mTree.Root);
    Assert.IsNotNull(mHeader, 'Pruefe');
    mAttributes := nil;
    for mIndex := 0 to mHeader.Parent.ChildCount - 1 do
    begin
      if mHeader.Parent[mIndex] = mHeader then
      begin
        Break;
      end;
      // Wie bei der Tabelle beginnt der Bereich am ersten Fall: [Test] davor gehört nicht dazu.
      if (mHeader.Parent[mIndex].Kind = TSyntaxKind.Attribute) and ((mAttributes <> nil) or
        (Copy(AText, mHeader.Parent[mIndex].StartOffset + 1, 6) <> '[Test]')) then
      begin
        mAttributes := mAttributes + [mHeader.Parent[mIndex]];
      end;
    end;
    Result := TTestCaseTrivia.Bind(AText, TLineTable.Build(AText), mAttributes);
  finally
    mTree.Free;
  end;
end;

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join('|', ALines);
end;

{ TTestCaseTriviaTests }

procedure TTestCaseTriviaTests.CommentLinesBelongToTheNextCase;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    [A]'#10'    // zu B'#10'    { auch zu B }'#10'    [B]'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual(2, Integer(Length(mBinding.Items)));
  Assert.AreEqual('', Joined(mBinding.Items[0].After));
  Assert.AreEqual('', mBinding.Items[0].Trailing);
  Assert.AreEqual('// zu B|{ auch zu B }', Joined(mBinding.Items[1].Leading));
  Assert.AreEqual(4, mBinding.Range.StartPos.Line);
  Assert.AreEqual(7, mBinding.Range.EndPos.Line);
  Assert.IsFalse(mBinding.CodeAfter);
end;

procedure TTestCaseTriviaTests.CommentAtLineEndBelongsToItsCase;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    [A] // zu A'#10'    { vor B } [B] (* hinter B *)'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual('// zu A', mBinding.Items[0].Trailing);
  Assert.AreEqual('{ vor B }', mBinding.Items[1].Prefix);
  Assert.AreEqual('(* hinter B *)', mBinding.Items[1].Trailing);
  Assert.AreEqual(5, mBinding.Range.EndPos.Line);
  Assert.AreEqual(Length('    { vor B } [B] (* hinter B *)'), mBinding.Range.EndPos.Character);
end;

procedure TTestCaseTriviaTests.CommentsAboveFirstAndBehindLastAreIncluded;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    [Test]'#10'    // Kopf'#10'    // zu A'#10'    [A]'#10'    [B] // zu B'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  // Nur A und B gehören zum Bereich; [Test] steht davor.
  Assert.AreEqual(2, Integer(Length(mBinding.Items)));
  Assert.AreEqual('// Kopf|// zu A', Joined(mBinding.Items[0].Leading));
  Assert.AreEqual('// zu B', mBinding.Items[1].Trailing);
  Assert.AreEqual(5, mBinding.Range.StartPos.Line);
  Assert.AreEqual(4, mBinding.Range.StartPos.Character);
end;

procedure TTestCaseTriviaTests.BlankLineEndsCommentsAboveFirst;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    // Abschnitt'#10#10'    [A]'#10'    [B]'#10));
  Assert.AreEqual('', Joined(mBinding.Items[0].Leading));
  Assert.AreEqual(6, mBinding.Range.StartPos.Line);
end;

procedure TTestCaseTriviaTests.DirectiveAroundOneCaseIsBound;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    [A]'#10'    {$IFDEF MSWINDOWS}'#10'    // nur Windows'#10'    [B]'#10 +
    '    {$ENDIF}'#10'    [C]'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual('{$IFDEF MSWINDOWS}|// nur Windows', Joined(mBinding.Items[1].Leading));
  Assert.AreEqual('{$ENDIF}', Joined(mBinding.Items[1].After));
  Assert.AreEqual('', Joined(mBinding.Items[2].Leading));
  // In einer Zeile: davor und dahinter.
  mBinding := BindingOf(ClassText('    [A]'#10'    {$IFDEF MSWINDOWS} [B] {$ENDIF}'#10'    [C]'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual('{$IFDEF MSWINDOWS}', mBinding.Items[1].Prefix);
  Assert.AreEqual('{$ENDIF}', mBinding.Items[1].Trailing);
end;

procedure TTestCaseTriviaTests.DirectiveAroundFirstAndLastCase;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    {$IFDEF MSWINDOWS}'#10'    [A]'#10'    {$ENDIF}'#10'    [B]'#10 +
    '    {$IFNDEF NIE}'#10'    [C]'#10'    {$ENDIF}'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual('{$IFDEF MSWINDOWS}', Joined(mBinding.Items[0].Leading));
  Assert.AreEqual('{$ENDIF}', Joined(mBinding.Items[0].After));
  Assert.AreEqual('{$IFNDEF NIE}', Joined(mBinding.Items[2].Leading));
  Assert.AreEqual('{$ENDIF}', Joined(mBinding.Items[2].After));
  Assert.AreEqual(4, mBinding.Range.StartPos.Line);
  Assert.AreEqual(10, mBinding.Range.EndPos.Line);
end;

procedure TTestCaseTriviaTests.DirectiveAroundAllCasesStaysOutside;
var
  mText: string;
  mBinding: TTriviaBinding;
begin
  mText := ClassText('    {$IFDEF MSWINDOWS}'#10'    // Kopf'#10'    [A]'#10'    [B]'#10);
  mText := StringReplace(mText, '    procedure Pruefe(A: Integer);'#10,
    '    procedure Pruefe(A: Integer);'#10'    {$ENDIF}'#10, []);
  mBinding := BindingOf(mText);
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual('// Kopf', Joined(mBinding.Items[0].Leading));
  Assert.AreEqual(5, mBinding.Range.StartPos.Line);
  Assert.AreEqual(7, mBinding.Range.EndPos.Line);
end;

procedure TTestCaseTriviaTests.DirectivesThatCannotBeKept;
begin
  // Eine Bedingung über zwei Fällen.
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.Directive, BindingOf(ClassText('    [A]'#10 +
    '    {$IFDEF MSWINDOWS}'#10'    [B]'#10'    [C]'#10'    {$ENDIF}'#10'    [D]'#10)).Problem, 'zwei Fälle');
  // {$ELSE} hinter einem Fall.
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.Directive, BindingOf(ClassText('    [A]'#10 +
    '    {$IFDEF MSWINDOWS}'#10'    [B]'#10'    {$ELSE}'#10'    // nichts'#10'    {$ENDIF}'#10'    [C]'#10)).Problem,
    'ELSE');
  // Ein Schalter.
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.Directive, BindingOf(ClassText('    [A]'#10'    {$R+}'#10 +
    '    [B]'#10)).Problem, 'Schalter');
  // Ein {$ENDIF} zwischen den Fällen zu einer Bedingung weit darüber.
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.Directive, BindingOf(ClassText('    {$IFDEF MSWINDOWS}'#10 +
    '    [Test]'#10'    [A]'#10'    {$ENDIF}'#10'    [B]'#10)).Problem, 'Bedingung von weiter oben');
end;

procedure TTestCaseTriviaTests.InactiveCaseKeepsItsCondition;
var
  mBinding: TTriviaBinding;
begin
  mBinding := BindingOf(ClassText('    [A]'#10'    {$IFDEF NIE_DEFINIERT}'#10'    [X]'#10'    {$ENDIF}'#10 +
    '    [B]'#10));
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.None, mBinding.Problem);
  Assert.AreEqual(3, Integer(Length(mBinding.Items)));
  Assert.AreEqual('{$IFDEF NIE_DEFINIERT}', Joined(mBinding.Items[1].Leading));
  Assert.AreEqual('{$ENDIF}', Joined(mBinding.Items[1].After));
end;

procedure TTestCaseTriviaTests.CodeBetweenAttributes;
begin
  Assert.AreEqual<TTriviaProblem>(TTriviaProblem.Code, BindingOf(ClassText('    [A]'#10'    ;'#10'    [B]'#10)).Problem);
end;

procedure TTestCaseTriviaTests.WrapAndLineComment;
var
  mTrivia: TAttributeTrivia;
begin
  mTrivia := Default(TAttributeTrivia);
  Assert.AreEqual('[A]', mTrivia.Wrap('[A]', #10, '  '));
  Assert.IsFalse(mTrivia.EndsWithLineComment);
  mTrivia.Leading := ['{$IFDEF X}', '// a'];
  mTrivia.Prefix := '{ b }';
  mTrivia.Trailing := '// c';
  Assert.AreEqual('{$IFDEF X}'#10'  // a'#10'  { b } [A] // c', mTrivia.Wrap('[A]', #10, '  '));
  Assert.IsTrue(mTrivia.EndsWithLineComment);
  mTrivia.After := ['{$ENDIF}'];
  Assert.AreEqual('{$IFDEF X}'#10'  // a'#10'  { b } [A] // c'#10'  {$ENDIF}', mTrivia.Wrap('[A]', #10, '  '));
  Assert.IsFalse(mTrivia.EndsWithLineComment);
  mTrivia.Leading := nil;
  mTrivia.After := nil;
end;

end.
