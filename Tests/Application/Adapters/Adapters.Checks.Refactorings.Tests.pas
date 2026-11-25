unit Adapters.Checks.Refactorings.Tests;

// Tests für den Host-Adapter, der den Prüfregeln die Klassen-Aktionen von Editing als Korrektur gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCheckRefactoringsAdapterTests = class
  public
    [Test]
    procedure WithoutClassActionsNoEntry;
    [Test]
    procedure WithoutExtractNoEntry;
    [Test]
    procedure ConstantGoesToEditing;
    [Test]
    procedure MethodWithoutSelfGoesToEditing;
    [Test]
    procedure MethodOrderGoesToEditing;
    [Test]
    procedure ClassCompletionGoesToEditing;
    [Test]
    procedure SlashCommandsGoToEditing;
    [Test]
    procedure OverrideGoesToEditing;
    [Test]
    procedure CreateAccessorGoesToEditing;
    [Test]
    procedure NothingToDoGivesFalse;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.ClassActions.Contract,
  Atlas.Common.Checks.Contract.Refactorings,
  Atlas.Common.Editing.Composition,
  Atlas.Tests.TextEdits,
  Adapters.Checks.Refactorings;

const
  // Zeile 8: Kopf von TKind, Zeile 10: Eigenschaft ohne Feld.
  cSource =
    'unit Klassen;'#13#10 +
    ''#13#10 +
    'interface'#13#10 +
    ''#13#10 +
    'type'#13#10 +
    '  TBasis = class'#13#10 +
    '    procedure Zeichne; virtual;'#13#10 +
    '  end;'#13#10 +
    '  TKind = class(TBasis)'#13#10 +
    '  public'#13#10 +
    '    property Name: string read FName;'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    'implementation'#13#10 +
    ''#13#10 +
    'procedure TBasis.Zeichne;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'end.'#13#10;

  // Zeile 4: Literal 42 ab Spalte 10.
  cCall =
    'unit U;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  Writeln(42);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;

  // Zeile 7: Kopf von THilfe.Doppelt, braucht Self nicht.
  cHelper =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  THilfe = class'#13#10 +
    '    function Doppelt(A: Integer): Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function THilfe.Doppelt(A: Integer): Integer;'#13#10 +
    'begin'#13#10 +
    '  Result := A * 2;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;

  // TFoo deklariert A vor B, die Rümpfe stehen umgekehrt; der Typkommentar ist da.
  cOrder =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    procedure A;'#13#10 +
    '    procedure B;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{ TFoo }'#13#10 +
    'procedure TFoo.B;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'procedure TFoo.A;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;

/// <summary>Alle APIs von Editing, die die Prüfregeln nutzen.</summary>
function Sources: TCheckRefactoringSources;
begin
  Result := Default(TCheckRefactoringSources);
  Result.Classes := TEditingComposition.ClassActions;
  Result.Extract := TEditingComposition.ExtractFixes;
  Result.Methods := TEditingComposition.MethodsWithoutSelf;
  Result.Order := TEditingComposition.MethodOrder;
  Result.Completion := TEditingComposition.ClassCompletion;
  Result.Commands := TEditingComposition.SlashChecks;
end;

function Refactorings: TCheckRefactorings;
begin
  Result := TCheckRefactoringsAdapters.Create(Sources);
end;

{ TCheckRefactoringsAdapterTests }

procedure TCheckRefactoringsAdapterTests.WithoutClassActionsNoEntry;
var
  mSources: TCheckRefactoringSources;
begin
  mSources := Sources;
  mSources.Classes := nil;
  Assert.IsNull(TCheckRefactoringsAdapters.Create(mSources).Classes);
end;

procedure TCheckRefactoringsAdapterTests.WithoutExtractNoEntry;
var
  mSources: TCheckRefactoringSources;
begin
  mSources := Sources;
  mSources.Extract := nil;
  Assert.IsNull(TCheckRefactoringsAdapters.Create(mSources).Extract);
end;

procedure TCheckRefactoringsAdapterTests.ConstantGoesToEditing;
var
  mTree: TSyntaxTree;
  mExtraction: ICheckConstantExtraction;
  mAction: TCodeAction;
begin
  mTree := TSyntaxTreeCache.Parse(cCall);
  try
    mExtraction := Refactorings.Extract.ConstantExtraction(cCall, TSyntaxTreeHandles.Wrap(mTree),
      Default(TPascalNamePrefixes));
    Assert.IsTrue(mExtraction.Run(TTextRange.Create(4, 10, 4, 12), mAction));
    mExtraction := nil;
  finally
    mTree.Free;
  end;
  Assert.IsTrue(Pos('= 42;', TTestEdits.Apply(cCall, mAction.Edits)) > 0);
end;

procedure TCheckRefactoringsAdapterTests.MethodWithoutSelfGoesToEditing;
var
  mTree: TSyntaxTree;
  mScan: TCheckMethodScan;
  mFound: TArray<TCheckMethodWithoutSelf>;
begin
  Assert.IsNull(TCheckRefactoringsAdapters.Create(Default(TCheckRefactoringSources)).Methods);
  mScan := Default(TCheckMethodScan);
  mScan.FileName := 'U.pas';
  mScan.Text := cHelper;
  mScan.WithStatic := True;
  mScan.Style := TFormatStyle.Default;
  mTree := TSyntaxTreeCache.Parse(cHelper);
  try
    mScan.Tree := TSyntaxTreeHandles.Wrap(mTree);
    mFound := Refactorings.Methods.WithoutSelf(mScan);
    mScan.Tree := nil;
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('THilfe', mFound[0].ClassName);
  Assert.AreEqual('Doppelt', mFound[0].Name);
  Assert.AreEqual(7, mFound[0].NamePosition.Line);
  Assert.IsTrue(mFound[0].HasFix);
  Assert.IsTrue(Length(mFound[0].Fix.Edits) > 0);
end;

procedure TCheckRefactoringsAdapterTests.MethodOrderGoesToEditing;
var
  mRequest: TCheckMethodOrderRequest;
  mTree: TSyntaxTree;
  mReview: TCheckMethodOrderReview;
  mText: string;
begin
  Assert.IsNull(TCheckRefactoringsAdapters.Create(Default(TCheckRefactoringSources)).Order);
  mRequest := Default(TCheckMethodOrderRequest);
  mRequest.Placement := 'declaration';
  mRequest.TypeComment := 'brace';
  mTree := TSyntaxTreeCache.Parse(cOrder);
  try
    mReview := Refactorings.Order.Review(cOrder, TSyntaxTreeHandles.Wrap(mTree), mRequest);
  finally
    mTree.Free;
  end;
  Assert.AreEqual('declaration', mReview.Placement);
  Assert.AreEqual(1, Integer(Length(mReview.Types)));
  Assert.AreEqual('TFoo', mReview.Types[0].TypeName);
  Assert.AreEqual(9, mReview.Types[0].NameRange.StartPos.Line, 'Typname im ersten Rumpf');
  Assert.IsTrue(mReview.Types[0].CommentEdits = nil, 'Kommentar steht schon da');
  mText := TTestEdits.Apply(cOrder, mReview.Types[0].OrderEdits);
  Assert.IsTrue(Pos('procedure TFoo.A;'#13#10'begin', mText) < Pos('procedure TFoo.B;'#13#10'begin', mText), mText);
end;

procedure TCheckRefactoringsAdapterTests.ClassCompletionGoesToEditing;
const
  // Foo weicht im Modifizierer ab, Bar fehlt der Rumpf.
  cPair =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    procedure Foo(A: Integer);'#13#10 +
    '    procedure Bar;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Foo(const A: Integer);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  mTree: TSyntaxTree;
  mScan: ICheckClassCompletionScan;
  mPairs: TArray<TCheckSignaturePair>;
  mFixes: TArray<TCodeAction>;
  mMissing: TArray<TCheckUnmatchedMethod>;
  mMethod: TCheckUnmatchedMethod;
  mShape: TCheckSignatureShape;
  mAction: TCodeAction;
begin
  Assert.IsNull(TCheckRefactoringsAdapters.Create(Default(TCheckRefactoringSources)).Completion);
  mTree := TSyntaxTreeCache.Parse(cPair);
  try
    mScan := Refactorings.Completion.Scan(cPair, TSyntaxTreeHandles.Wrap(mTree), TIndexExtractor.Extract(mTree, ''),
      TClassCompletionSettings.Default, TFormatStyle.Default);
    mPairs := mScan.Pairs;
    Assert.AreEqual(1, Integer(Length(mPairs)));
    Assert.AreEqual('const', mPairs[0].BodyShape.Parameters[0].Modifier);
    Assert.IsTrue(mScan.InPair(mPairs[0].Declaration));
    Assert.IsTrue(mScan.Shape(mPairs[0].Body.Symbol, mShape));
    Assert.AreEqual('procedure', mShape.Kind);
    Assert.IsTrue(mScan.PairFixes(mPairs[0], mFixes));
    Assert.Contains(TTestEdits.Apply(cPair, mFixes[0].Edits), 'procedure TFoo.Foo(A: Integer);');
    // Unmatched enthält auch beide Hälften des Paars; ohne Paar bleibt nur Bar.
    mMissing := nil;
    for mMethod in mScan.Unmatched do
    begin
      if not mScan.InPair(mMethod) then
      begin
        mMissing := mMissing + [mMethod];
      end;
    end;
    Assert.AreEqual(1, Integer(Length(mMissing)));
    Assert.AreEqual('Bar', mMissing[0].Symbol.Name);
    Assert.IsTrue(mScan.MissingBodies(mMissing[0].Symbol.SelectionRange.StartPos, mAction));
    mScan := nil;
  finally
    mTree.Free;
  end;
end;

procedure TCheckRefactoringsAdapterTests.OverrideGoesToEditing;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(Refactorings.Classes.OverrideMethod(TClassEditRequest.Create(cSource, 8), 'Zeichne', mAction));
  mText := TTestEdits.Apply(cSource, mAction.Edits);
  Assert.IsTrue(Pos('procedure Zeichne; override;', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TKind.Zeichne;', mText) > 0, mText);
end;

procedure TCheckRefactoringsAdapterTests.CreateAccessorGoesToEditing;
var
  mPlan: TAccessorPlan;
  mAction: TCodeAction;
  mText: string;
begin
  mPlan := Default(TAccessorPlan);
  mPlan.Kind := TAccessorKind.Field;
  mPlan.PropertyName := 'Name';
  mPlan.PropertyType := 'string';
  mPlan.MethodSection := 'private';
  Assert.IsTrue(Refactorings.Classes.CreateAccessor(TClassEditRequest.Create(cSource, 10), mPlan, mAction));
  mText := TTestEdits.Apply(cSource, mAction.Edits);
  Assert.IsTrue(Pos('FName: string;', mText) > 0, mText);
end;

procedure TCheckRefactoringsAdapterTests.SlashCommandsGoToEditing;
var
  mProblems: TArray<TCheckSlashProblem>;
begin
  Assert.IsNull(TCheckRefactoringsAdapters.Create(Default(TCheckRefactoringSources)).Commands);
  mProblems := Refactorings.Commands.Problems('unit U;'#10'implementation'#10'  /gibtsnicht X'#10'end.', nil, '');
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual(2, mProblems[0].Range.StartPos.Line);
  Assert.AreEqual('Unbekannter Schnellbefehl /gibtsnicht', mProblems[0].Message);
  Assert.Contains(Refactorings.Commands.IgnoreWithoutHit('probe-line'), 'probe-line');
end;

procedure TCheckRefactoringsAdapterTests.NothingToDoGivesFalse;
var
  mAction: TCodeAction;
begin
  // Zeile 1 liegt in keiner Klasse.
  Assert.IsFalse(Refactorings.Classes.OverrideMethod(TClassEditRequest.Create(cSource, 1), 'Zeichne', mAction));
  Assert.IsFalse(Refactorings.Classes.ImplementInterface(TClassEditRequest.Create(cSource, 8), 'IUnbekannt',
    mAction));
end;

initialization
  TDUnitX.RegisterTestFixture(TCheckRefactoringsAdapterTests);

end.
