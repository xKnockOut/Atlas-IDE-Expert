unit Atlas.Common.Editing.AnonymousMethods.Shared.Tests;

// Tests für die gemeinsamen Teile der Umwandlungen zwischen anonymer Methode und Methode
// (Atlas.Common.Editing.AnonymousMethods.Shared): Eingabe, Lookup ohne Baum, Syntaxhilfen; dazu
// TAnonymousEmbedding aus Atlas.Common.Editing.AnonymousMethods.Embed direkt mit Grund bei Ablehnung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAnonymousSharedTests = class
  public
    [Test]
    procedure InputCreateSetsDefaults;
    [Test]
    procedure LookupFromTreeWithoutTreeIsEmpty;
    [Test]
    procedure TopRoutineOfFindsOutermostRoutine;
    [Test]
    procedure InsideStopsAtGivenNode;
    [Test]
    procedure HasInheritedLooksOnlyInRange;
    [Test]
    procedure IsArgumentExcludesCallee;
    [Test]
    procedure UnreadParametersNeedsNonEmptyList;
    [Test]
    procedure EmbeddingEmbedsPrivateMethod;
    [Test]
    procedure EmbeddingRefusesPublicMethod;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.AnonymousMethods.Shared,
  Atlas.Common.Editing.AnonymousMethods.Embed;

function Join(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

/// <summary>Erster Knoten der Art AKind mit dem Namen AName; nil ohne.</summary>
function NodeNamed(ATree: TSyntaxTree; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mFound: TSyntaxNode;
  mKind: TSyntaxKind;
  mName: string;
begin
  mFound := nil;
  mKind := AKind;
  mName := AName;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (mFound = nil) and (ANode.Kind = mKind) and SameText(ANode.Name, mName) then
      begin
        mFound := ANode;
      end;
      Result := mFound = nil;
    end);
  Result := mFound;
end;

/// <summary>Unit mit TFoo: Run übergibt Tick an ForEach; Tick steht im Abschnitt AVisibility.</summary>
function EmbedUnit(const AVisibility: string): string;
begin
  Result := Join(['unit U;', '', 'interface', '', 'type', '  TFoo = class', '  ' + AVisibility,
    '    procedure Run;', '    procedure Tick(const AItem: Integer);', '  end;', '', 'implementation', '',
    'procedure TFoo.Run;', 'begin', '  FList.ForEach(Tick);', 'end;', '', 'procedure TFoo.Tick(const AItem: Integer);',
    'begin', '  Writeln(AItem);', 'end;', '', 'end.']);
end;

/// <summary>Eingabe an der Implementierung von Tick mit Zieltyp reference to.</summary>
function EmbedInput(const AText: string; ATree: TSyntaxTree): TAnonymousInput;
var
  mLookup: TAnonymousLookup;
begin
  mLookup := TAnonymousLookup.FromTree(ATree);
  mLookup.TargetType :=
    function(AValue: TSyntaxNode): TProcTypeKind
    begin
      Result := TProcTypeKind.Reference;
    end;
  Result := TAnonymousInput.Create(AText, ATree,
    TLineTable.Build(AText).PositionAt(Pos('TFoo.Tick', AText) - 1), mLookup);
end;

function RunEmbedding(const AInput: TAnonymousInput; out AAction: TCodeAction; out AReason: string): Boolean;
var
  mEmbedding: TAnonymousEmbedding;
begin
  mEmbedding := TAnonymousEmbedding.Create(AInput);
  try
    Result := mEmbedding.Run(AAction, AReason);
  finally
    mEmbedding.Free;
  end;
end;

procedure TAnonymousSharedTests.InputCreateSetsDefaults;
var
  mInput: TAnonymousInput;
begin
  mInput := TAnonymousInput.Create('X', nil, TTextPosition.Create(1, 2), Default(TAnonymousLookup));
  Assert.AreEqual('X', mInput.Text);
  Assert.IsNull(mInput.Tree);
  Assert.AreEqual(1, mInput.Position.Line);
  Assert.AreEqual(2, mInput.Position.Character);
  Assert.AreEqual<TDeferredCapture>(TDeferredCapture.Forward, mInput.Capture);
end;

procedure TAnonymousSharedTests.LookupFromTreeWithoutTreeIsEmpty;
var
  mLookup: TAnonymousLookup;
begin
  mLookup := TAnonymousLookup.FromTree(nil);
  Assert.IsFalse(Assigned(mLookup.Flow));
  Assert.IsFalse(Assigned(mLookup.TargetType));
end;

procedure TAnonymousSharedTests.TopRoutineOfFindsOutermostRoutine;
var
  mText: string;
  mTree: TSyntaxTree;
  mOuter, mNode: TSyntaxNode;
begin
  mText := Join(['unit U;', 'interface', 'implementation', 'procedure Outer;', '  procedure Inner;', '  begin',
    '    Marke;', '  end;', 'begin', '  Inner;', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    mOuter := NodeNamed(mTree, TSyntaxKind.RoutineDecl, 'Outer');
    mNode := NodeNamed(mTree, TSyntaxKind.Identifier, 'Marke');
    Assert.IsNotNull(mNode);
    Assert.AreSame(mOuter, TAnonymousSyntax.TopRoutineOf(mNode));
    Assert.IsNull(TAnonymousSyntax.TopRoutineOf(mTree.Root));
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousSharedTests.InsideStopsAtGivenNode;
var
  mText: string;
  mTree: TSyntaxTree;
  mNode, mWith: TSyntaxNode;
begin
  mText := Join(['unit U;', 'interface', 'implementation', 'procedure P;', 'begin', '  with Q do', '  begin',
    '    Marke;', '  end;', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    mNode := NodeNamed(mTree, TSyntaxKind.Identifier, 'Marke');
    mWith := mNode.Parent;
    while mWith.Kind <> TSyntaxKind.WithStatement do
    begin
      mWith := mWith.Parent;
    end;
    Assert.IsTrue(TAnonymousSyntax.Inside(mNode, nil, TSyntaxKind.WithStatement));
    Assert.IsFalse(TAnonymousSyntax.Inside(mNode, mWith, TSyntaxKind.WithStatement), 'bis ausschließlich with');
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousSharedTests.HasInheritedLooksOnlyInRange;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := Join(['unit U;', 'interface', 'implementation', 'procedure TFoo.A;', 'begin', '  inherited;', 'end;',
    'procedure TFoo.B;', 'begin', '  X;', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TAnonymousSyntax.HasInherited(mTree.Tokens, NodeNamed(mTree, TSyntaxKind.RoutineDecl, 'TFoo.A')));
    Assert.IsFalse(TAnonymousSyntax.HasInherited(mTree.Tokens, NodeNamed(mTree, TSyntaxKind.RoutineDecl, 'TFoo.B')));
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousSharedTests.IsArgumentExcludesCallee;
var
  mText: string;
  mTree: TSyntaxTree;
  mArgument, mCall: TSyntaxNode;
begin
  mText := Join(['unit U;', 'interface', 'implementation', 'procedure P;', 'begin', '  Rufe(Wert);', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    mArgument := NodeNamed(mTree, TSyntaxKind.Identifier, 'Wert');
    mCall := mArgument.Parent;
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Call, mCall.Kind);
    Assert.IsTrue(TAnonymousSyntax.IsArgument(mArgument, mCall));
    Assert.IsFalse(TAnonymousSyntax.IsArgument(mCall[0], mCall), 'der Aufgerufene');
    Assert.IsFalse(TAnonymousSyntax.IsArgument(mArgument, nil));
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousSharedTests.UnreadParametersNeedsNonEmptyList;
var
  mText: string;
  mTree: TSyntaxTree;
  mWith, mWithout: TSyntaxNode;
begin
  mText := Join(['unit U;', 'interface', 'implementation', 'procedure Mit(A: Integer);', 'begin', 'end;',
    'procedure Ohne;', 'begin', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    mWith := TRoutineParts.HeaderOf(NodeNamed(mTree, TSyntaxKind.RoutineDecl, 'Mit'));
    mWithout := TRoutineParts.HeaderOf(NodeNamed(mTree, TSyntaxKind.RoutineDecl, 'Ohne'));
    Assert.IsTrue(TAnonymousSyntax.UnreadParameters(nil, mWith));
    Assert.IsFalse(TAnonymousSyntax.UnreadParameters(TRoutineParts.ParameterTexts(mText, mWith), mWith));
    Assert.IsFalse(TAnonymousSyntax.UnreadParameters(nil, mWithout));
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousSharedTests.EmbeddingEmbedsPrivateMethod;
var
  mText, mReason: string;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  mText := EmbedUnit('private');
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(RunEmbedding(EmbedInput(mText, mTree), mAction, mReason), mReason);
    Assert.AreEqual(EmbedTitle, mAction.Title);
    Assert.AreEqual(3, Integer(Length(mAction.Edits)));
    Assert.IsTrue(Pos('procedure(const AItem: Integer)', mAction.Edits[2].NewText) > 0, mAction.Edits[2].NewText);
  finally
    mTree.Free;
  end;
end;

procedure TAnonymousSharedTests.EmbeddingRefusesPublicMethod;
var
  mText, mReason: string;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  mText := EmbedUnit('public');
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsFalse(RunEmbedding(EmbedInput(mText, mTree), mAction, mReason));
    Assert.AreEqual('nicht privat', mReason);
    Assert.AreEqual(0, Integer(Length(mAction.Edits)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnonymousSharedTests);

end.
