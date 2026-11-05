unit Atlas.Common.Editing.GenericLists.Declarations;

// Zweite Stufe der Listenumwandlung (#1105, #1106): die Deklaration der Liste (Feld, Variable, Inline-Variable)
// einordnen und umschreiben (bei "A, L, B: TList" wird L abgespalten), Properties, die das Feld direkt lesen,
// mitnehmen, und jedes Create der alten Klasse auf den generischen Typ umschreiben.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.GenericLists.Source,
  Atlas.Common.Editing.GenericLists.State;

type
  /// <summary>Deklaration, Properties und Create der Liste.</summary>
  TGenericListDeclarations = class(TGenericListState)
  private
    function CreatedClass(AValue: TSyntaxNode): TSyntaxNode;
    procedure AddCreateArguments(ASource: TGenericListSource; AValue: TSyntaxNode);
    procedure SplitDeclaration(ASource: TGenericListSource; ADeclaration, ATypeRef: TSyntaxNode;
      const AName, ANewType: string; ALegacy: Boolean);
    function PropertyProblem(ASource: TGenericListSource; AMember: TSyntaxNode): string;
    function ReadsTarget(ASource: TGenericListSource; AMember: TSyntaxNode): Boolean;
    procedure ScanProperties(ASource: TGenericListSource; AClass: TSyntaxNode; AInterface: Boolean);
    procedure ScanField(ASource: TGenericListSource);
    procedure ScanVariable(ASource: TGenericListSource);
    procedure ScanInlineVar(ASource: TGenericListSource);
    class function FieldOfProperty(ATree: TSyntaxTree; AProperty: TSyntaxNode; var AName: string): TSyntaxNode;
      static;
  protected
    /// <summary>TList oder Unit.TList, ohne Typargumente.</summary>
    function IsLegacyName(ANode: TSyntaxNode): Boolean;
    /// <summary>L := TList.Create bzw. TObjectList.Create(False); jede andere Zuweisung ist eine Weitergabe.</summary>
    procedure NoteCreation(AFileIndex: Integer; AValue: TSyntaxNode);
    /// <summary>Typ von AName in ADeclaration durch ANewType ersetzen; ALegacy: dort stand der alte Klassenname.</summary>
    procedure RetypeDeclaration(ASource: TGenericListSource; ADeclaration: TSyntaxNode; const AName, ANewType: string;
      ALegacy: Boolean);
    /// <summary>Deklaration FTarget.Declaration in der eigenen Datei einordnen und umschreiben.</summary>
    procedure ScanDeclaration(ASource: TGenericListSource);
  public
    /// <summary>Deklaration (Field, VarDecl, InlineVar, Parameter) an APosition, z. B. an der SelectionRange des
    /// aufgelösten Symbols; AName ist der Name dort. Bei einer Property, die ein Feld derselben Klasse liest
    /// (property Items: TList read FItems), das Feld und sein Name. nil, wenn keine passt.</summary>
    class function DeclarationAt(ATree: TSyntaxTree; const APosition: TTextPosition; var AName: string): TSyntaxNode;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDeclarationsText = (GetsAValueOther, IsCreatedAs2, IsDeclaredTogetherWithOther, ThePropertyInHasA,
    ThePropertyReadsVia, ThePropertyWritesVia, ThePropertyHasIndexParameters, TheClassOfIsNot,
    IsDeclaredTogetherWithOther2, IsAParameterTheSignature, IsNeitherAVariableNor);

const
  cTexts: array[TDeclarationsText] of TAtlasText = (
    (De: '%s bekommt in %s einen anderen Wert als ein neues %s';
     En: '%0:s gets a value other than a new %2:s in %1:s'),
    (De: '%s wird in %s als %s erzeugt'; En: '%0:s is created as %2:s in %1:s'),
    (De: '%s steht in %s mit weiteren Namen in einer Deklaration';
     En: '%s is declared together with other names in %s'),
    (De: 'Die Property %s in %s hat einen anderen Typ'; En: 'The property %s in %s has a different type'),
    (De: 'Die Property %s liest über %s'; En: 'The property %s reads via %s'),
    (De: 'Die Property %s schreibt über %s'; En: 'The property %s writes via %s'),
    (De: 'Die Property %s hat Indexparameter'; En: 'The property %s has index parameters'),
    (De: 'Die Klasse zu %s ist nicht erkennbar'; En: 'The class of %s is not recognizable'),
    (De: '%s steht in %s mit weiteren Namen in einer Inline-Variable';
     En: '%s is declared together with other names in an inline variable in %s'),
    (De: '%s ist ein Parameter; die Signatur der Routine müsste sich ändern';
     En: '%s is a parameter; the signature of the routine would have to change'),
    (De: '%s ist keine Variable und kein Feld'; En: '%s is neither a variable nor a field'));

{$SCOPEDENUMS OFF}

{ TGenericListDeclarations }

function TGenericListDeclarations.IsLegacyName(ANode: TSyntaxNode): Boolean;
begin
  Result := False;
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := SameText(ANode.Name, FKind.LegacyName);
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    TGenericListSyntax.IsPlainName(ANode[0]) then
  begin
    Result := SameText(ANode.Name, FKind.LegacyName);
  end;
end;

function TGenericListDeclarations.CreatedClass(AValue: TSyntaxNode): TSyntaxNode;
var
  mMember: TSyntaxNode;
begin
  // Klasse vor .Create, mit oder ohne Argumentliste; nil, wenn AValue kein X.Create ist.
  Result := nil;
  mMember := AValue;
  if (mMember.Kind = TSyntaxKind.Call) and (mMember.ChildCount > 0) then
  begin
    mMember := mMember[0];
  end;
  if (mMember.Kind = TSyntaxKind.MemberAccess) and SameText(mMember.Name, 'Create') and (mMember.ChildCount = 1) then
  begin
    Result := mMember[0];
  end;
end;

procedure TGenericListDeclarations.AddCreateArguments(ASource: TGenericListSource; AValue: TSyntaxNode);
var
  mBeforeParen: TTextPosition;
begin
  if FKind.CreateArguments = '' then
  begin
    Exit;
  end;
  if AValue.Kind = TSyntaxKind.MemberAccess then
  begin
    ASource.AddEdit(AValue.EndPos, AValue.EndPos, '(' + FKind.CreateArguments + ')');
  end
  else if AValue.ChildCount = 1 then
  begin
    // Create(): Argument vor die schließende Klammer.
    mBeforeParen := TTextPosition.Create(AValue.EndPos.Line, AValue.EndPos.Character - 1);
    ASource.AddEdit(mBeforeParen, mBeforeParen, FKind.CreateArguments);
  end;
end;

procedure TGenericListDeclarations.NoteCreation(AFileIndex: Integer; AValue: TSyntaxNode);
var
  mSource: TGenericListSource;
  mClass: TSyntaxNode;
begin
  mSource := FFiles[AFileIndex];
  if TGenericListSyntax.IsNil(AValue) then
  begin
    Exit;
  end;
  mClass := CreatedClass(AValue);
  if mClass = nil then
  begin
    Fail(cTexts[TDeclarationsText.GetsAValueOther].Fmt([FTarget.Name, LineOf(AValue),
      FKind.LegacyName]));
  end
  else if not IsLegacyName(mClass) then
  begin
    Fail(cTexts[TDeclarationsText.IsCreatedAs2].Fmt([FTarget.Name, LineOf(AValue), mSource.NodeText(mClass)]));
  end
  else
  begin
    FCreated := True;
    mSource.NoteRewritten(mClass);
    // Der Typtext folgt in Finish, wenn T feststeht.
    mSource.AddEdit(mClass.StartPos, mClass.EndPos, cGenericPlaceholder);
    AddCreateArguments(mSource, AValue);
  end;
end;

procedure TGenericListDeclarations.SplitDeclaration(ASource: TGenericListSource; ADeclaration,
  ATypeRef: TSyntaxNode; const AName, ANewType: string; ALegacy: Boolean);
var
  mOthers: TArray<string>;
  mName, mRest, mIndent: string;
begin
  // A, L, B: TList; → A, B: TList; und L: TList<T>; in einer eigenen Zeile.
  mRest := Copy(ASource.Text, ATypeRef.StartOffset + 1, ADeclaration.EndOffset - ATypeRef.StartOffset);
  if not EndsText(';', Trim(mRest)) then
  begin
    Fail(cTexts[TDeclarationsText.IsDeclaredTogetherWithOther].Fmt([AName, LineOf(ADeclaration)]));
    Exit;
  end;
  mOthers := nil;
  for mName in SplitString(ADeclaration.Name, ',') do
  begin
    if not SameText(Trim(mName), AName) then
    begin
      mOthers := mOthers + [Trim(mName)];
    end;
  end;
  mIndent := StringOfChar(' ', ADeclaration.StartPos.Character);
  if ALegacy then
  begin
    ASource.NoteGenericAt(ADeclaration.StartOffset);
  end;
  ASource.AddEdit(ADeclaration.StartPos, ADeclaration.EndPos, string.Join(', ', mOthers) + ': ' + mRest +
    ASource.LineBreak + mIndent + AName + ': ' + ANewType + ';');
end;

procedure TGenericListDeclarations.RetypeDeclaration(ASource: TGenericListSource; ADeclaration: TSyntaxNode;
  const AName, ANewType: string; ALegacy: Boolean);
var
  mTypeRef: TSyntaxNode;
begin
  mTypeRef := ADeclaration.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef = nil then
  begin
    Exit;
  end;
  if Pos(',', ADeclaration.Name) > 0 then
  begin
    SplitDeclaration(ASource, ADeclaration, mTypeRef, AName, ANewType, ALegacy);
    Exit;
  end;
  if ALegacy then
  begin
    ASource.NoteRewritten(mTypeRef);
  end;
  ASource.AddEdit(mTypeRef.StartPos, mTypeRef.EndPos, ANewType);
end;

function TGenericListDeclarations.ReadsTarget(ASource: TGenericListSource; AMember: TSyntaxNode): Boolean;
begin
  Result := (AMember.Kind = TSyntaxKind.PropertyDecl) and
    (SameText(TGenericListSyntax.IdentifierAfter(ASource.Tree, AMember, 'read'), FTarget.Name) or
    SameText(TGenericListSyntax.IdentifierAfter(ASource.Tree, AMember, 'write'), FTarget.Name));
end;

function TGenericListDeclarations.PropertyProblem(ASource: TGenericListSource; AMember: TSyntaxNode): string;
var
  mTypeRef: TSyntaxNode;
  mReadName, mWriteName: string;
begin
  mTypeRef := AMember.FindChild(TSyntaxKind.TypeReference);
  mReadName := TGenericListSyntax.IdentifierAfter(ASource.Tree, AMember, 'read');
  mWriteName := TGenericListSyntax.IdentifierAfter(ASource.Tree, AMember, 'write');
  Result := '';
  if (mTypeRef = nil) or (mTypeRef.ChildCount > 0) or
    not SameText(TGenericListSyntax.LastName(mTypeRef.Name), FKind.LegacyName) then
  begin
    Result := cTexts[TDeclarationsText.ThePropertyInHasA].Fmt([AMember.Name, LineOf(AMember)]);
  end
  else if (mReadName <> '') and not SameText(mReadName, FTarget.Name) then
  begin
    Result := cTexts[TDeclarationsText.ThePropertyReadsVia].Fmt([AMember.Name, mReadName]);
  end
  else if (mWriteName <> '') and not SameText(mWriteName, FTarget.Name) then
  begin
    Result := cTexts[TDeclarationsText.ThePropertyWritesVia].Fmt([AMember.Name, mWriteName]);
  end
  else if (AMember.ChildCount > 1) and (AMember.FindChild(TSyntaxKind.Parameters) <> nil) then
  begin
    Result := cTexts[TDeclarationsText.ThePropertyHasIndexParameters].Fmt([AMember.Name]);
  end;
end;

procedure TGenericListDeclarations.ScanProperties(ASource: TGenericListSource; AClass: TSyntaxNode;
  AInterface: Boolean);
var
  mIndex: Integer;
  mMember, mTypeRef: TSyntaxNode;
  mProblem: string;
begin
  // property Items: TList read FItems: die Property wird mit umgewandelt; ein Getter oder Setter verhindert es.
  for mIndex := 0 to AClass.ChildCount - 1 do
  begin
    mMember := AClass[mIndex];
    if not ReadsTarget(ASource, mMember) then
    begin
      Continue;
    end;
    mProblem := PropertyProblem(ASource, mMember);
    if mProblem <> '' then
    begin
      Fail(mProblem);
      Exit;
    end;
    FProperties := FProperties + [mMember.Name];
    if AInterface and not TGenericListSyntax.IsPrivate(mMember) then
    begin
      FExternalNames := FExternalNames + [mMember.Name];
    end;
    mTypeRef := mMember.FindChild(TSyntaxKind.TypeReference);
    ASource.NoteRewritten(mTypeRef);
    ASource.AddEdit(mTypeRef.StartPos, mTypeRef.EndPos, cGenericPlaceholder);
  end;
end;

procedure TGenericListDeclarations.ScanField(ASource: TGenericListSource);
var
  mDeclaration, mOwner, mTypeDecl: TSyntaxNode;
  mInInterface: Boolean;
begin
  mDeclaration := FTarget.Declaration;
  mOwner := mDeclaration.Parent;
  while (mOwner <> nil) and not (mOwner.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType,
    TSyntaxKind.ObjectType]) do
  begin
    mOwner := mOwner.Parent;
  end;
  mTypeDecl := mOwner;
  while (mTypeDecl <> nil) and (mTypeDecl.Kind <> TSyntaxKind.TypeDecl) do
  begin
    mTypeDecl := mTypeDecl.Parent;
  end;
  if mTypeDecl = nil then
  begin
    Fail(cTexts[TDeclarationsText.TheClassOfIsNot].Fmt([FTarget.Name]));
    Exit;
  end;
  FTarget.IsField := True;
  FTarget.OwnerType := mTypeDecl.Name;
  mInInterface := TGenericListSyntax.InInterface(ASource.Tree, mDeclaration.StartOffset);
  if mInInterface and not TGenericListSyntax.IsPrivate(mDeclaration) then
  begin
    FExternalNames := FExternalNames + [FTarget.Name];
  end;
  RetypeDeclaration(ASource, mDeclaration, FTarget.Name, cGenericPlaceholder, True);
  if not Failed then
  begin
    ScanProperties(ASource, mOwner, mInInterface);
  end;
end;

procedure TGenericListDeclarations.ScanVariable(ASource: TGenericListSource);
var
  mDeclaration: TSyntaxNode;
begin
  mDeclaration := FTarget.Declaration;
  FTarget.Scope := TGenericListSyntax.EnclosingRoutine(mDeclaration);
  FTarget.IsLocal := FTarget.Scope <> nil;
  if not FTarget.IsLocal and TGenericListSyntax.InInterface(ASource.Tree, mDeclaration.StartOffset) then
  begin
    FExternalNames := FExternalNames + [FTarget.Name];
  end;
  RetypeDeclaration(ASource, mDeclaration, FTarget.Name, cGenericPlaceholder, True);
end;

procedure TGenericListDeclarations.ScanInlineVar(ASource: TGenericListSource);
var
  mDeclaration, mValue: TSyntaxNode;
begin
  mDeclaration := FTarget.Declaration;
  FTarget.Scope := TGenericListSyntax.EnclosingRoutine(mDeclaration);
  FTarget.IsLocal := True;
  if Pos(',', mDeclaration.Name) > 0 then
  begin
    Fail(cTexts[TDeclarationsText.IsDeclaredTogetherWithOther2].Fmt([FTarget.Name,
      LineOf(mDeclaration)]));
    Exit;
  end;
  RetypeDeclaration(ASource, mDeclaration, FTarget.Name, cGenericPlaceholder, True);
  // var L := TList.Create: der Wert ist das letzte Kind, wenn es keine Typangabe ist.
  if mDeclaration.ChildCount = 0 then
  begin
    Exit;
  end;
  mValue := mDeclaration[mDeclaration.ChildCount - 1];
  if mValue.Kind <> TSyntaxKind.TypeReference then
  begin
    NoteCreation(0, mValue);
  end;
end;

procedure TGenericListDeclarations.ScanDeclaration(ASource: TGenericListSource);
begin
  case FTarget.Declaration.Kind of
    TSyntaxKind.Field:
      ScanField(ASource);
    TSyntaxKind.VarDecl:
      ScanVariable(ASource);
    TSyntaxKind.InlineVar:
      ScanInlineVar(ASource);
    TSyntaxKind.Parameter:
      Fail(cTexts[TDeclarationsText.IsAParameterTheSignature].Fmt([FTarget.Name]));
  else
    Fail(cTexts[TDeclarationsText.IsNeitherAVariableNor].Fmt([FTarget.Name]));
  end;
end;

class function TGenericListDeclarations.FieldOfProperty(ATree: TSyntaxTree; AProperty: TSyntaxNode;
  var AName: string): TSyntaxNode;
var
  mFieldName: string;
  mIndex: Integer;
  mMember: TSyntaxNode;
begin
  // Property mit read-Feld: umgewandelt wird das Feld, die Property folgt ihm (ScanProperties).
  Result := nil;
  mFieldName := TGenericListSyntax.IdentifierAfter(ATree, AProperty, 'read');
  if (mFieldName = '') or (AProperty.Parent = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to AProperty.Parent.ChildCount - 1 do
  begin
    mMember := AProperty.Parent[mIndex];
    if (mMember.Kind = TSyntaxKind.Field) and MatchText(mFieldName, SplitString(mMember.Name, ', ')) then
    begin
      AName := mFieldName;
      Exit(mMember);
    end;
  end;
end;

class function TGenericListDeclarations.DeclarationAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  var AName: string): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mFound := TGenericListSyntax.DeclarationNodeAt(ATree.Root, APosition);
  // Der Name muss an der Stelle stehen; sonst passt die Position nicht zum Text (veralteter Index).
  if (mFound = nil) or not MatchText(AName, SplitString(mFound.Name, ', ')) then
  begin
    Exit;
  end;
  if mFound.Kind = TSyntaxKind.PropertyDecl then
  begin
    Result := FieldOfProperty(ATree, mFound, AName);
  end
  else
  begin
    Result := mFound;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.GenericLists.Declarations', cTexts);

end.
