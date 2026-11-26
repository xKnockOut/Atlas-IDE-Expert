unit Editing.Providers.ClassCompletion.Tests;

// Tests für IEditingClassCompletion (#42, #124, #996): fehlender Rumpf samt „Rumpf erzeugen“, Rumpf ohne
// Deklaration samt „Deklaration ergänzen“, Paar mit abweichendem Kopf samt Angleichen, ohne Baum keine Zuordnung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingClassCompletionProviderTests = class
  public
    [Test]
    procedure MissingBodyIsCreated;
    [Test]
    procedure MissingDeclarationIsAdded;
    [Test]
    procedure DifferingHeadsArePairedAndAligned;
    [Test]
    procedure NoTreeNoScan;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.TreeHandles,
  Editing.Contract.ClassCompletion,
  Editing.Composition,
  Atlas.Tests.TextEdits,
  Atlas.Common.Semantics.Contract;

const
  // TFoo: A ohne Rumpf, B mit abweichendem Kopf, C nur als Rumpf.
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B(X: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.B(const X: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFoo.C;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

type
  /// <summary>Baum und Zuordnung von cSource für einen Test.</summary>
  TScanFixture = record
    Tree: TSyntaxTree;
    Scan: IEditingClassCompletionScan;
    class function Open: TScanFixture; static;
    procedure Close;
    /// <summary>Methode ohne Gegenstück namens AName.</summary>
    function Unmatched(const AName: string): TUnmatchedMethod;
  end;

class function TScanFixture.Open: TScanFixture;
begin
  Result.Tree := TSyntaxTreeCache.Parse(cSource);
  Result.Scan := TEditingComposition.ClassCompletion.Scan(cSource, TSyntaxTreeHandles.Wrap(Result.Tree),
    TIndexExtractor.Extract(Result.Tree, ''), TClassCompletionSettings.Default, TFormatStyle.Default);
end;

procedure TScanFixture.Close;
begin
  Scan := nil;
  Tree.Free;
  Tree := nil;
end;

function TScanFixture.Unmatched(const AName: string): TUnmatchedMethod;
var
  mMethod: TUnmatchedMethod;
begin
  Result := Default(TUnmatchedMethod);
  for mMethod in Scan.Unmatched do
  begin
    if SameText(mMethod.Symbol.Name, AName) then
    begin
      Exit(mMethod);
    end;
  end;
  Assert.Fail('Keine Methode ohne Gegenstück: ' + AName);
end;

{ TEditingClassCompletionProviderTests }

procedure TEditingClassCompletionProviderTests.MissingBodyIsCreated;
var
  mFixture: TScanFixture;
  mMethod: TUnmatchedMethod;
  mAction: TCodeAction;
begin
  mFixture := TScanFixture.Open;
  try
    mMethod := mFixture.Unmatched('A');
    Assert.IsTrue(mMethod.Declared);
    Assert.IsFalse(mFixture.Scan.InPair(mMethod));
    Assert.IsTrue(mFixture.Scan.MissingBodies(mMethod.Symbol.SelectionRange.StartPos, mAction));
    Assert.Contains(TTestEdits.Apply(cSource, mAction.Edits), 'procedure TFoo.A;');
  finally
    mFixture.Close;
  end;
end;

procedure TEditingClassCompletionProviderTests.MissingDeclarationIsAdded;
var
  mFixture: TScanFixture;
  mMethod: TUnmatchedMethod;
  mEdit: TTextEdit;
begin
  mFixture := TScanFixture.Open;
  try
    mMethod := mFixture.Unmatched('C');
    Assert.IsFalse(mMethod.Declared);
    Assert.IsTrue(mFixture.Scan.AddDeclaration(mMethod, mEdit));
    Assert.Contains(TTestEdits.Apply(cSource, [mEdit]), '    procedure C;');
  finally
    mFixture.Close;
  end;
end;

procedure TEditingClassCompletionProviderTests.DifferingHeadsArePairedAndAligned;
var
  mFixture: TScanFixture;
  mPairs: TArray<TSignaturePair>;
  mFixes: TArray<TCodeAction>;
begin
  mFixture := TScanFixture.Open;
  try
    mPairs := mFixture.Scan.Pairs;
    Assert.AreEqual(1, Integer(Length(mPairs)));
    Assert.AreEqual('B', mPairs[0].Body.Symbol.Name);
    Assert.AreEqual('', mPairs[0].DeclarationShape.Parameters[0].Modifier);
    Assert.AreEqual('const', mPairs[0].BodyShape.Parameters[0].Modifier);
    Assert.IsTrue(mFixture.Scan.InPair(mPairs[0].Body));
    Assert.IsTrue(mFixture.Scan.PairFixes(mPairs[0], mFixes));
    Assert.Contains(TTestEdits.Apply(cSource, mFixes[0].Edits), 'procedure TFoo.B(X: Integer);');
  finally
    mFixture.Close;
  end;
end;

procedure TEditingClassCompletionProviderTests.NoTreeNoScan;
begin
  Assert.IsNull(TEditingComposition.ClassCompletion.Scan(cSource, nil, Default(TUnitIndex),
    TClassCompletionSettings.Default, TFormatStyle.Default));
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingClassCompletionProviderTests);

end.
