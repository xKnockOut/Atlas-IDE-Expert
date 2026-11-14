unit Atlas.Common.Editing.GenericLists.Parts.Tests;

// Tests für die Teile der Listenumwandlung (#1105, #1106): Listenarten (Atlas.Common.Editing.GenericLists.Kinds),
// Abfragen am Syntaxbaum (.Syntax), Edits je Datei (.Source), uses-Listen (.UsesEdits), Zielprüfung (.State),
// Elementprüfung (.Elements) und DeclarationAt (.Declarations). Die Verwendungen
// (Atlas.Common.Editing.GenericLists.Usages) prüfen die Umwandlungstests in Atlas.Common.Editing.GenericLists.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGenericListPartsTests = class
  public
    [Test]
    procedure KindsFindAndMembers;
    [Test]
    procedure NamesLists;
    [Test]
    procedure SyntaxNames;
    [Test]
    procedure SyntaxTreeQueries;
    [Test]
    procedure DeclarationAtFollowsProperty;
    [Test]
    procedure SourceFinalizeSortsAndDropsDuplicates;
    [Test]
    procedure SourceFinalizeRejectsOverlap;
    [Test]
    procedure SourceLegacyUnitStillUsed;
    [Test]
    procedure UsesEditsAddGenericUnit;
    [Test]
    procedure TargetAccepts;
    [Test]
    procedure ElementCheck;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Editing.GenericLists.Source,
  Atlas.Common.Editing.GenericLists.UsesEdits,
  Atlas.Common.Editing.GenericLists.State,
  Atlas.Common.Editing.GenericLists.Elements,
  Atlas.Common.Editing.GenericLists.Declarations;

const
  cUnitText = 'unit Haupt;'#10'interface'#10'uses Classes, Contnrs;'#10'type'#10'  TListe = class'#10 +
    '  private'#10'    FListe: TObjectList;'#10'  public'#10'    property Liste: TObjectList read FListe;'#10 +
    '  end;'#10'implementation'#10'procedure Lauf;'#10'begin'#10'  for var E in X do'#10'    ;'#10'end;'#10'end.';

function FindKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  if ANode.Kind = AKind then
  begin
    Exit(ANode);
  end;
  Result := nil;
  mIndex := 0;
  while (Result = nil) and (mIndex < ANode.ChildCount) do
  begin
    Result := FindKind(ANode[mIndex], AKind);
    Inc(mIndex);
  end;
end;

function Edit(ALine, AStart, AEnd: Integer; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ALine, AStart), TTextPosition.Create(ALine, AEnd)),
    AText);
end;

{ TGenericListPartsTests }

procedure TGenericListPartsTests.KindsFindAndMembers;
var
  mKind: TLegacyListKind;
  mPosition: Integer;
  mText: string;
begin
  Assert.IsTrue(TLegacyListKind.Find('tobjectqueue', mKind));
  Assert.AreEqual('TObjectQueue', mKind.GenericName);
  Assert.AreEqual('False', mKind.CreateArguments);
  Assert.IsTrue(mKind.RenameOf('Pop', mText));
  Assert.AreEqual('Extract', mText);
  Assert.IsFalse(TLegacyListKind.Find('TStringList', mKind));
  Assert.AreEqual('', mKind.LegacyName);
  mKind := TLegacyListKind.PointerList;
  Assert.IsTrue(mKind.ElementArgument('Insert', mPosition));
  Assert.AreEqual(1, mPosition);
  Assert.IsTrue(mKind.IsKnown('Count'));
  Assert.IsTrue(mKind.IsReadOrNeutral('First'));
  Assert.IsFalse(mKind.IsKnown('Sort'));
  Assert.IsTrue(mKind.UnsupportedReason('Sort', mText));
  Assert.AreEqual('Sort mit TListSortCompare', mText);
  Assert.AreEqual('TList<TPosition>', mKind.GenericText('TPosition'));
  Assert.IsTrue(TLegacyListKind.Queue.IsLegacyUnit('System.Contnrs'));
  Assert.IsFalse(mKind.IsLegacyUnit('Contnrs'));
end;

procedure TGenericListPartsTests.NamesLists;
var
  mValue: string;
begin
  Assert.IsTrue(TGenericListNames.IsObjectMember('free'));
  Assert.IsFalse(TGenericListNames.IsObjectMember('Add'));
  Assert.IsTrue(TGenericListNames.IsScalarType('Pointer'));
  Assert.IsFalse(TGenericListNames.IsScalarType('TPosition'));
  Assert.IsTrue(TGenericListNames.IsContnrsType('TBucketList'));
  Assert.IsTrue(TGenericListNames.ValueOf('add', ['Count', 'Add=0'], mValue));
  Assert.AreEqual('0', mValue);
  Assert.IsTrue(TGenericListNames.ValueOf('Count', ['Count', 'Add=0'], mValue));
  Assert.AreEqual('', mValue);
  Assert.IsFalse(TGenericListNames.ValueOf('Clear', ['Count', 'Add=0'], mValue));
end;

procedure TGenericListPartsTests.SyntaxNames;
begin
  Assert.AreEqual('TPosition', TGenericListSyntax.LastName(' Daten.TPosition '));
  Assert.AreEqual('TPosition', TGenericListSyntax.LastName('TPosition'));
  Assert.IsTrue(TGenericListSyntax.ContainsName('FA, FListe,FB', 'fliste'));
  Assert.IsFalse(TGenericListSyntax.ContainsName('FA, FListe', 'Liste'));
  Assert.IsTrue(TGenericListSyntax.NotAfter(TTextPosition.Create(1, 4), TTextPosition.Create(1, 4)));
  Assert.IsFalse(TGenericListSyntax.NotAfter(TTextPosition.Create(2, 0), TTextPosition.Create(1, 9)));
end;

procedure TGenericListPartsTests.SyntaxTreeQueries;
var
  mTree: TSyntaxTree;
  mField, mProperty, mLoop: TSyntaxNode;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitText);
  try
    mField := FindKind(mTree.Root, TSyntaxKind.Field);
    mProperty := FindKind(mTree.Root, TSyntaxKind.PropertyDecl);
    mLoop := FindKind(mTree.Root, TSyntaxKind.ForInStatement);
    Assert.IsNotNull(mField);
    Assert.IsTrue(TGenericListSyntax.IsPrivate(mField));
    Assert.AreEqual('public', TGenericListSyntax.VisibilityOf(mProperty));
    Assert.IsTrue(TGenericListSyntax.InInterface(mTree, mField.StartOffset));
    Assert.IsFalse(TGenericListSyntax.InInterface(mTree, mLoop.StartOffset));
    Assert.AreEqual('FListe', TGenericListSyntax.IdentifierAfter(mTree, mProperty, 'read'));
    Assert.AreEqual('', TGenericListSyntax.IdentifierAfter(mTree, mProperty, 'write'));
    Assert.IsTrue(TGenericListSyntax.HasInlineVar(mTree, mLoop));
    Assert.IsNotNull(TGenericListSyntax.EnclosingRoutine(mLoop));
    Assert.IsNull(TGenericListSyntax.EnclosingRoutine(mField));
    Assert.AreSame(mField, TGenericListSyntax.DeclarationNodeAt(mTree.Root, mField.StartPos));
  finally
    mTree.Free;
  end;
end;

procedure TGenericListPartsTests.DeclarationAtFollowsProperty;
var
  mTree: TSyntaxTree;
  mProperty: TSyntaxNode;
  mName: string;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitText);
  try
    mProperty := FindKind(mTree.Root, TSyntaxKind.PropertyDecl);
    mName := 'Liste';
    Assert.AreSame(FindKind(mTree.Root, TSyntaxKind.Field),
      TGenericListDeclarations.DeclarationAt(mTree, mProperty.StartPos, mName));
    Assert.AreEqual('FListe', mName);
    // Name passt nicht zur Stelle (veralteter Index): keine Deklaration.
    mName := 'Andere';
    Assert.IsNull(TGenericListDeclarations.DeclarationAt(mTree, mProperty.StartPos, mName));
  finally
    mTree.Free;
  end;
end;

procedure TGenericListPartsTests.SourceFinalizeSortsAndDropsDuplicates;
var
  mSource: TGenericListSource;
  mReason: string;
begin
  mSource := TGenericListSource.Create(TSyntaxTreeCache.Parse(cUnitText), True, cUnitText, 'Haupt.pas');
  try
    mSource.AddTextEdit(Edit(6, 12, 23, cGenericPlaceholder));
    mSource.AddTextEdit(Edit(2, 0, 0, '// ' + cItemPlaceholder));
    mSource.AddTextEdit(Edit(6, 12, 23, cGenericPlaceholder));
    Assert.IsTrue(mSource.Finalize('TObjectList<TPosition>', 'TPosition', mReason), mReason);
    Assert.AreEqual(2, Integer(Length(mSource.Edits)));
    Assert.AreEqual('// TPosition', mSource.Edits[0].NewText);
    Assert.AreEqual('TObjectList<TPosition>', mSource.Edits[1].NewText);
  finally
    mSource.Free;
  end;
end;

procedure TGenericListPartsTests.SourceFinalizeRejectsOverlap;
var
  mSource: TGenericListSource;
  mReason: string;
begin
  mSource := TGenericListSource.Create(TSyntaxTreeCache.Parse(cUnitText), True, cUnitText, 'C:\P\Haupt.pas');
  try
    mSource.AddTextEdit(Edit(6, 4, 20, 'A'));
    mSource.AddTextEdit(Edit(6, 10, 23, 'B'));
    Assert.IsFalse(mSource.Finalize('', '', mReason));
    Assert.AreEqual('Die Änderungen in Haupt.pas überschneiden sich', mReason);
  finally
    mSource.Free;
  end;
end;

procedure TGenericListPartsTests.SourceLegacyUnitStillUsed;
const
  cText = 'unit Haupt;'#10'interface'#10'uses Contnrs;'#10'var'#10'  A: TObjectList;'#10'  B: TStack<Integer>;'#10 +
    'implementation'#10'end.';
var
  mSource: TGenericListSource;
  mDeclaration: TSyntaxNode;
begin
  mSource := TGenericListSource.Create(TSyntaxTreeCache.Parse(cText), True, cText, 'Haupt.pas');
  try
    Assert.IsTrue(mSource.LegacyUnitStillUsed);
    Assert.IsTrue(mSource.MentionsIdentifier('tstack'));
    mDeclaration := FindKind(mSource.Tree.Root, TSyntaxKind.VarDecl);
    mSource.NoteRewritten(mDeclaration.FindChild(TSyntaxKind.TypeReference));
    // TObjectList wird umgeschrieben, TStack<Integer> stammt schon aus System.Generics.Collections.
    Assert.IsFalse(mSource.LegacyUnitStillUsed);
    Assert.AreEqual(1, Integer(Length(mSource.GenericAt)));
  finally
    mSource.Free;
  end;
end;

procedure TGenericListPartsTests.UsesEditsAddGenericUnit;
const
  cText = 'unit Haupt;'#10'interface'#10'uses Classes, Contnrs;'#10'var'#10'  A: TObjectList;'#10 +
    'implementation'#10'end.';
var
  mSource: TGenericListSource;
  mDeclaration: TSyntaxNode;
  mReason: string;
begin
  mSource := TGenericListSource.Create(TSyntaxTreeCache.Parse(cText), True, cText, 'Haupt.pas');
  try
    mDeclaration := FindKind(mSource.Tree.Root, TSyntaxKind.VarDecl);
    mSource.NoteRewritten(mDeclaration.FindChild(TSyntaxKind.TypeReference));
    Assert.IsTrue(TGenericListUses.AddEdits(mSource, TLegacyListKind.ObjectList, nil, mReason), mReason);
    // Contnrs entfällt, System.Generics.Collections kommt an seine Stelle.
    Assert.AreEqual(1, Integer(Length(mSource.Edits)));
    Assert.AreEqual('Classes, System.Generics.Collections', mSource.Edits[0].NewText);
  finally
    mSource.Free;
  end;
end;

procedure TGenericListPartsTests.TargetAccepts;
var
  mTarget: TGenericListTarget;
  mSymbol: TResolvedSymbol;
begin
  mTarget := Default(TGenericListTarget);
  mTarget.Name := 'FListe';
  mTarget.OwnerType := 'TListe';
  mTarget.UnitName := 'Haupt';
  mTarget.IsField := True;
  mSymbol := Default(TResolvedSymbol);
  mSymbol.SymbolKind := TIndexSymbolKind.Field;
  mSymbol.Container := 'Haupt.TListe';
  mSymbol.UnitName := 'Andere';
  Assert.IsTrue(mTarget.Accepts(mSymbol, 0, 'FListe'));
  // In einer weiteren Unit muss das Feld aus der Unit der Liste stammen.
  Assert.IsFalse(mTarget.Accepts(mSymbol, 1, 'FListe'));
  // Unter dem Namen einer Property wird nur eine Property angenommen.
  Assert.IsFalse(mTarget.Accepts(mSymbol, 0, 'Liste'));
  mTarget.IsField := False;
  mTarget.IsLocal := True;
  mTarget.DeclarationLine := 5;
  mSymbol.Kind := TResolvedKind.Local;
  mSymbol.Range := TTextRange.Create(TTextPosition.Create(5, 2), TTextPosition.Create(5, 20));
  Assert.IsTrue(mTarget.Accepts(mSymbol, 0, 'FListe'));
  mTarget.DeclarationLine := 7;
  Assert.IsFalse(mTarget.Accepts(mSymbol, 0, 'FListe'));
end;

procedure TGenericListPartsTests.ElementCheck;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mCheck: TGenericListElementCheck;
  mElement: TGenericListElement;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitText);
  mResolver := TNameResolver.Create(nil);
  try
    mCheck := TGenericListElementCheck.Create(mResolver, nil, 'FListe', 'Daten.TPosition');
    mElement := Default(TGenericListElement);
    mElement.Node := FindKind(mTree.Root, TSyntaxKind.Field);
    mElement.TypeName := 'nil';
    Assert.AreEqual<TGenericListElementFit>(TGenericListElementFit.Fits, mCheck.Check(mElement));
    mElement.TypeName := 'TPosition';
    Assert.AreEqual<TGenericListElementFit>(TGenericListElementFit.Fits, mCheck.Check(mElement));
    mElement.TypeName := '';
    Assert.AreEqual<TGenericListElementFit>(TGenericListElementFit.Unknown, mCheck.Check(mElement));
    mElement.TypeName := 'Integer';
    Assert.AreEqual<TGenericListElementFit>(TGenericListElementFit.Wrong, mCheck.Check(mElement));
    Assert.AreEqual('FListe nimmt in Zeile 7 Werte vom Typ Integer auf', mCheck.Problem);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGenericListPartsTests);

end.
