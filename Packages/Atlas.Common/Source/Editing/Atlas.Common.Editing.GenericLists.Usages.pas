unit Atlas.Common.Editing.GenericLists.Usages;

// Dritte Stufe der Listenumwandlung (#1105, #1106): alle Verwendungen der Liste in einer Datei sammeln und einordnen.
// Lesezugriffe (L[I], L.Items[I], First, Pop, for … in) brauchen einen Cast, der entfällt; Elemente, die
// hineinkommen, merkt sich die Stufe mit ihrem Typ; Weitergabe, with und Mitglieder ohne Gegenstück verhindern die
// Umwandlung. Mitglieder mit anderem Namen (Push → Enqueue) werden umbenannt, Schleifenvariablen bekommen den Typ T.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.GenericLists.Source,
  Atlas.Common.Editing.GenericLists.State,
  Atlas.Common.Editing.GenericLists.Declarations;

type
  /// <summary>Verwendungen der Liste einsammeln und einordnen.</summary>
  TGenericListUsages = class(TGenericListDeclarations)
  private
    function UseNames(AFileIndex: Integer): TArray<string>;
    function UseVisitor(AFileIndex: Integer; const ANames: TArray<string>): TSyntaxNodeVisit;
    function VisitUse(AFileIndex: Integer; const ANames: TArray<string>; ANode: TSyntaxNode): Boolean;
    function IsCandidate(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
    function IsListMember(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
    function IsAssumed(AFileIndex: Integer; ANode: TSyntaxNode): Boolean;
    function IsOwnMethod(ANode: TSyntaxNode): Boolean;
    function Matches(AFileIndex: Integer; ANode: TSyntaxNode): TGenericListMatch;
    function IsOtherMember(ASource: TGenericListSource; ANode: TSyntaxNode): Boolean;
    procedure FailUse(AUse: TSyntaxNode);
    procedure ClassifyUse(AFileIndex: Integer; AUse: TSyntaxNode);
    procedure ClassifyIndex(AFileIndex: Integer; AUse, AIndex: TSyntaxNode);
    procedure ClassifyForIn(AFileIndex: Integer; AUse, ALoop: TSyntaxNode);
    procedure ClassifyCall(AFileIndex: Integer; AUse, ACall: TSyntaxNode);
    function MemberProblem(AMember: TSyntaxNode): string;
    procedure RewriteMember(ASource: TGenericListSource; AMember, ACall: TSyntaxNode);
    procedure ClassifyMember(AFileIndex: Integer; AMember: TSyntaxNode);
    procedure ClassifyMemberRead(AFileIndex: Integer; AMember, ACall: TSyntaxNode);
    procedure ClassifyRead(AFileIndex: Integer; ARead: TSyntaxNode; const AWhat: string);
    function NoteCastRead(AFileIndex: Integer; ARead, AOuter: TSyntaxNode): Boolean;
    function IsHarmlessRead(ASource: TGenericListSource; AOuter: TSyntaxNode): Boolean;
    function IsPointerTarget(ASource: TGenericListSource; ANode: TSyntaxNode): Boolean;
    procedure ClassifyLoop(AFileIndex: Integer; ALoop: TSyntaxNode);
    function LoopScope(ASource: TGenericListSource; ALoop: TSyntaxNode): TSyntaxNode;
    function LoopVisitor(AFileIndex: Integer; ALoop: TSyntaxNode): TSyntaxNodeVisit;
    function VisitLoop(AFileIndex: Integer; ALoop, ANode: TSyntaxNode): Boolean;
    procedure NoteCast(AFileIndex: Integer; const ATypeText: string; ANode: TSyntaxNode);
    procedure NoteElement(AFileIndex: Integer; AArgument: TSyntaxNode);
    function ElementTypeOf(ASource: TGenericListSource; AArgument: TSyntaxNode): string;
    function ResolvedTypeOf(ASource: TGenericListSource; AValue: TSyntaxNode): string;
  protected
    /// <summary>Verwendungen in der Datei AFileIndex einsammeln: in der eigenen Datei Name und Properties der Liste,
    /// in weiteren Units die ExternalNames.</summary>
    procedure CollectUses(AFileIndex: Integer);
  end;

implementation

uses
  Atlas.Common.Semantics.NameResolver,
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TUsagesText = (TheUseOfInCannot, UnsupportedUseOfIn, IsPassedOnIn, IsInAWithStatement, IsPassedTo2,
    HasNoCounterpartInT, HasNoCounterpartInT2, IsReadWithoutACast, TheLoopVariableInIs, TheLoopVariableIsAlso,
    SomethingIsAssignedToThe);

const
  cTexts: array[TUsagesText] of TAtlasText = (
    (De: 'Die Verwendung von %s in %s (%s) ist nicht auflösbar'; En: 'The use of %s in %s (%s) cannot be resolved'),
    (De: 'Nicht unterstützte Verwendung von %s in %s'; En: 'Unsupported use of %s in %s'),
    (De: '%s wird in %s weitergegeben'; En: '%s is passed on in %s'),
    (De: '%s steht in %s in einer with-Anweisung'; En: '%s is in a with statement in %s'),
    (De: '%s wird in %s an %s übergeben'; En: '%0:s is passed to %2:s in %1:s'),
    (De: '%s hat in %s<T> kein Gegenstück (%s, %s)'; En: '%s has no counterpart in %s<T> (%s, %s)'),
    (De: '%s.%s hat in %s<T> kein Gegenstück (%s)'; En: '%s.%s has no counterpart in %s<T> (%s)'),
    (De: '%s wird in %s ohne Cast gelesen'; En: '%s is read without a cast in %s'),
    (De: 'Die Schleifenvariable %s in %s ist keine lokale Variable';
     En: 'The loop variable %s in %s is not a local variable'),
    (De: 'Die Schleifenvariable %s wird in %s auch anders benutzt';
     En: 'The loop variable %s is also used differently in %s'),
    (De: 'Der Schleifenvariable %s wird in %s etwas zugewiesen';
     En: 'Something is assigned to the loop variable %s in %s'));

{$SCOPEDENUMS OFF}

{ TGenericListUsages }

function TGenericListUsages.UseNames(AFileIndex: Integer): TArray<string>;
begin
  if AFileIndex = 0 then
  begin
    Result := TArray<string>.Create(FTarget.Name) + FProperties;
  end
  else
  begin
    Result := FExternalNames;
  end;
end;

function TGenericListUsages.UseVisitor(AFileIndex: Integer; const ANames: TArray<string>): TSyntaxNodeVisit;
var
  mNames: TArray<string>;
begin
  // Eigene Routine, damit die Methodenreferenz nur Self, den Index und die Namen einfängt.
  mNames := ANames;
  Result :=
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := VisitUse(AFileIndex, mNames, ANode);
    end;
end;

procedure TGenericListUsages.CollectUses(AFileIndex: Integer);
begin
  FFiles[AFileIndex].Tree.Root.Walk(UseVisitor(AFileIndex, UseNames(AFileIndex)));
end;

function TGenericListUsages.IsListMember(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
begin
  // Mitglied der Liste selbst (L.Items, wenn eine Property der Klasse auch Items heißt).
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    TGenericListSyntax.IsPlainName(ANode[0]) and MatchText(ANode[0].Name, ANames) and
    FKind.IsReadOrNeutral(ANode.Name);
end;

function TGenericListUsages.IsCandidate(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
begin
  Result := TGenericListSyntax.IsPlainName(ANode) and MatchText(ANode.Name, ANames) and
    not IsListMember(ANode, ANames);
end;

function TGenericListUsages.VisitUse(AFileIndex: Integer; const ANames: TArray<string>; ANode: TSyntaxNode): Boolean;
var
  mMatch: TGenericListMatch;
begin
  if Failed then
  begin
    Exit(False);
  end;
  if not IsCandidate(ANode, ANames) then
  begin
    Exit(True);
  end;
  mMatch := Matches(AFileIndex, ANode);
  if (mMatch = TGenericListMatch.Unknown) and not IsAssumed(AFileIndex, ANode) then
  begin
    Exit(Fail(cTexts[TUsagesText.TheUseOfInCannot].Fmt([ANode.Name,
      ExtractFileName(FFiles[AFileIndex].FileName), LineOf(ANode)])));
  end;
  // Die Kinder einer Verwendung (Self, A in A.FListe) sind keine weiteren Verwendungen.
  Result := mMatch = TGenericListMatch.No;
  if not Result then
  begin
    ClassifyUse(AFileIndex, ANode);
  end;
end;

function TGenericListUsages.IsOwnMethod(ANode: TSyntaxNode): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  // Bezeichner in einer Methode der eigenen Klasse (TKlasse.Methode), auch in einer lokalen Routine darin.
  mRoutine := TGenericListSyntax.EnclosingRoutine(ANode);
  while mRoutine <> nil do
  begin
    if StartsText(TGenericListSyntax.LastName(FTarget.OwnerType) + '.', mRoutine.Name) then
    begin
      Exit(True);
    end;
    mRoutine := TGenericListSyntax.EnclosingRoutine(mRoutine);
  end;
  Result := False;
end;

function TGenericListUsages.IsAssumed(AFileIndex: Integer; ANode: TSyntaxNode): Boolean;
var
  mIsSelfMember: Boolean;
begin
  // Ohne Index (Linter, Tests) in der eigenen Datei: lokale Variable der Routine bzw. Feld in einer Methode der
  // eigenen Klasse oder über Self.
  if AFileIndex <> 0 then
  begin
    Result := False;
  end
  else if FTarget.IsLocal then
  begin
    Result := (ANode.Kind = TSyntaxKind.Identifier) and FTarget.InScope(ANode);
  end
  else if FTarget.IsField then
  begin
    mIsSelfMember := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      TGenericListSyntax.IsIdentifierNamed(ANode[0], 'Self');
    Result := ((ANode.Kind = TSyntaxKind.Identifier) or mIsSelfMember) and IsOwnMethod(ANode);
  end
  else
  begin
    Result := ANode.Kind = TSyntaxKind.Identifier;
  end;
end;

function TGenericListUsages.IsOtherMember(ASource: TGenericListSource; ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  // X.Name mit bekanntem Typ von X, der nicht die eigene Klasse (oder ein Nachfahre) ist: ein anderes Mitglied.
  if not FTarget.IsField or (ANode.Kind <> TSyntaxKind.MemberAccess) or (ANode.ChildCount <> 1) then
  begin
    Exit(False);
  end;
  if not Resolves(ASource, ANode[0], mSymbol, mType, mTypeFound) or not mTypeFound then
  begin
    Exit(False);
  end;
  Result := not SameText(TGenericListSyntax.LastName(mType.Name), TGenericListSyntax.LastName(FTarget.OwnerType)) and
    FResolver.ResolveChain(ASource.Tree, ASource.FileName, [FTarget.OwnerType], ANode.StartOffset).Found and
    not FResolver.Queries.TypeDescendsFrom(ASource.Tree, ASource.FileName, ANode.StartOffset, mType.Name,
    FTarget.OwnerType);
end;

function TGenericListUsages.Matches(AFileIndex: Integer; ANode: TSyntaxNode): TGenericListMatch;
var
  mSource: TGenericListSource;
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  mSource := FFiles[AFileIndex];
  if Resolves(mSource, ANode, mSymbol, mType, mTypeFound) and mSymbol.Found then
  begin
    Result := TGenericListMatch.No;
    if FTarget.Accepts(mSymbol, AFileIndex, ANode.Name) then
    begin
      Result := TGenericListMatch.Yes;
    end;
  end
  else if IsOtherMember(mSource, ANode) then
  begin
    Result := TGenericListMatch.No;
  end
  else
  begin
    Result := TGenericListMatch.Unknown;
  end;
end;

procedure TGenericListUsages.FailUse(AUse: TSyntaxNode);
begin
  Fail(cTexts[TUsagesText.UnsupportedUseOfIn].Fmt([FTarget.Name, LineOf(AUse)]));
end;

procedure TGenericListUsages.ClassifyUse(AFileIndex: Integer; AUse: TSyntaxNode);
var
  mParent: TSyntaxNode;
begin
  mParent := AUse.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  case mParent.Kind of
    TSyntaxKind.AssignStatement:
      if TGenericListSyntax.IsAssignTarget(AUse) then
      begin
        NoteCreation(AFileIndex, mParent[1]);
      end
      else
      begin
        Fail(cTexts[TUsagesText.IsPassedOnIn].Fmt([FTarget.Name, LineOf(AUse)]));
      end;
    TSyntaxKind.MemberAccess:
      if mParent[0] = AUse then
      begin
        ClassifyMember(AFileIndex, mParent);
      end
      else
      begin
        FailUse(AUse);
      end;
    TSyntaxKind.IndexAccess:
      ClassifyIndex(AFileIndex, AUse, mParent);
    TSyntaxKind.ForInStatement:
      ClassifyForIn(AFileIndex, AUse, mParent);
    TSyntaxKind.Call:
      ClassifyCall(AFileIndex, AUse, mParent);
    TSyntaxKind.BinaryExpr:
      if not TGenericListSyntax.IsNil(TGenericListSyntax.CompareOperand(mParent, AUse)) then
      begin
        FailUse(AUse);
      end;
    TSyntaxKind.WithStatement:
      Fail(cTexts[TUsagesText.IsInAWithStatement].Fmt([FTarget.Name, LineOf(AUse)]));
  else
    Fail(cTexts[TUsagesText.IsPassedOnIn].Fmt([FTarget.Name, LineOf(AUse)]));
  end;
end;

procedure TGenericListUsages.ClassifyIndex(AFileIndex: Integer; AUse, AIndex: TSyntaxNode);
begin
  if (AIndex[0] <> AUse) or not FKind.DefaultItems then
  begin
    FailUse(AUse);
  end
  else if TGenericListSyntax.IsAssignTarget(AIndex) then
  begin
    NoteElement(AFileIndex, AIndex.Parent[1]);
  end
  else
  begin
    ClassifyRead(AFileIndex, AIndex, FTarget.Name);
  end;
end;

procedure TGenericListUsages.ClassifyForIn(AFileIndex: Integer; AUse, ALoop: TSyntaxNode);
var
  mIndex: Integer;
begin
  // Die Sammlung ist das erste Kind, das keine Typangabe der Schleifenvariable ist.
  for mIndex := 0 to ALoop.ChildCount - 1 do
  begin
    if ALoop[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Continue;
    end;
    if ALoop[mIndex] = AUse then
    begin
      ClassifyLoop(AFileIndex, ALoop);
      Exit;
    end;
    Break;
  end;
  FailUse(AUse);
end;

procedure TGenericListUsages.ClassifyCall(AFileIndex: Integer; AUse, ACall: TSyntaxNode);
begin
  if (ACall[0] <> AUse) and (TGenericListSyntax.IsIdentifierNamed(ACall[0], 'FreeAndNil') or
    TGenericListSyntax.IsIdentifierNamed(ACall[0], 'Assigned')) then
  begin
    Exit;
  end;
  Fail(cTexts[TUsagesText.IsPassedTo2].Fmt([FTarget.Name, LineOf(AUse), FFiles[AFileIndex].NodeText(ACall[0])]));
end;

function TGenericListUsages.MemberProblem(AMember: TSyntaxNode): string;
var
  mReason: string;
begin
  Result := '';
  if FKind.UnsupportedReason(AMember.Name, mReason) then
  begin
    Result := cTexts[TUsagesText.HasNoCounterpartInT].Fmt([mReason, FKind.GenericName, FTarget.Name,
      LineOf(AMember)]);
  end
  else if not FKind.IsKnown(AMember.Name) then
  begin
    Result := cTexts[TUsagesText.HasNoCounterpartInT2].Fmt([FTarget.Name, AMember.Name, FKind.GenericName,
      LineOf(AMember)]);
  end;
end;

procedure TGenericListUsages.RewriteMember(ASource: TGenericListSource; AMember, ACall: TSyntaxNode);
var
  mNewName: string;
  mLength: Integer;
begin
  // Umbenennen: der Name ist das letzte Wort des MemberAccess (L.Push → L.Enqueue).
  mLength := Length(AMember.Name);
  if FKind.RenameOf(AMember.Name, mNewName) and (AMember.EndPos.Character >= mLength) then
  begin
    ASource.AddEdit(TTextPosition.Create(AMember.EndPos.Line, AMember.EndPos.Character - mLength), AMember.EndPos,
      mNewName);
  end;
  // Count ist in TOrderedList (Contnrs) eine Funktion, generisch eine Property: Count() ohne Klammern.
  if (ACall <> nil) and (ACall.ChildCount = 1) and SameText(AMember.Name, 'Count') then
  begin
    ASource.AddEdit(AMember.EndPos, ACall.EndPos, '');
  end;
end;

procedure TGenericListUsages.ClassifyMember(AFileIndex: Integer; AMember: TSyntaxNode);
var
  mCall: TSyntaxNode;
  mProblem: string;
  mPosition: Integer;
begin
  mProblem := MemberProblem(AMember);
  if mProblem <> '' then
  begin
    Fail(mProblem);
    Exit;
  end;
  mCall := nil;
  if (AMember.Parent <> nil) and (AMember.Parent.Kind = TSyntaxKind.Call) and (AMember.Parent[0] = AMember) then
  begin
    mCall := AMember.Parent;
  end;
  RewriteMember(FFiles[AFileIndex], AMember, mCall);
  if FKind.ElementArgument(AMember.Name, mPosition) and (mCall <> nil) and (mCall.ChildCount > mPosition + 1) then
  begin
    NoteElement(AFileIndex, mCall[mPosition + 1]);
  end;
  if FKind.IsRead(AMember.Name) then
  begin
    ClassifyMemberRead(AFileIndex, AMember, mCall);
  end;
end;

procedure TGenericListUsages.ClassifyMemberRead(AFileIndex: Integer; AMember, ACall: TSyntaxNode);
var
  mRead, mParent: TSyntaxNode;
begin
  mRead := AMember;
  mParent := AMember.Parent;
  if ACall <> nil then
  begin
    mRead := ACall;
  end
  else if (mParent <> nil) and (mParent.Kind = TSyntaxKind.IndexAccess) and (mParent[0] = AMember) then
  begin
    mRead := mParent;
    // L.Items[I] := X
    if TGenericListSyntax.IsAssignTarget(mRead) then
    begin
      NoteElement(AFileIndex, mRead.Parent[1]);
      Exit;
    end;
  end;
  // Ergebnis verworfen: L.Pop; bzw. L.Extract(X);
  if (mRead.Parent = nil) or (mRead.Parent.Kind <> TSyntaxKind.CallStatement) then
  begin
    ClassifyRead(AFileIndex, mRead, FTarget.Name);
  end;
end;

procedure TGenericListUsages.NoteCast(AFileIndex: Integer; const ATypeText: string; ANode: TSyntaxNode);
var
  mCast: TGenericListCast;
begin
  mCast.FileIndex := AFileIndex;
  mCast.TypeText := ATypeText;
  mCast.Line := ANode.StartPos.Line;
  FCasts := FCasts + [mCast];
end;

function TGenericListUsages.NoteCastRead(AFileIndex: Integer; ARead, AOuter: TSyntaxNode): Boolean;
var
  mSource: TGenericListSource;
  mParent: TSyntaxNode;
  mTypeText: string;
begin
  mSource := FFiles[AFileIndex];
  mParent := AOuter.Parent;
  // T(L[I])
  if TGenericListSyntax.IsSingleArgumentCall(mParent) and (mParent[1] = AOuter) and
    IsTypeCast(mSource, mParent, mTypeText) then
  begin
    NoteCast(AFileIndex, mTypeText, mParent);
    mSource.RemoveCast(mParent, ARead);
    Exit(True);
  end;
  // L[I] as T, auch (L[I] as T).X: dann fallen die Klammern mit weg.
  Result := TGenericListSyntax.IsAsCast(mParent) and (mParent[0] = AOuter);
  if Result then
  begin
    NoteCast(AFileIndex, mSource.NodeText(mParent[1]), mParent);
    mSource.RemoveCast(TGenericListSyntax.Unparen(mParent), ARead);
  end;
end;

function TGenericListUsages.IsPointerTarget(ASource: TGenericListSource; ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := Resolves(ASource, ANode, mSymbol, mType, mTypeFound) and mTypeFound and SameText(mType.Name, 'Pointer');
end;

function TGenericListUsages.IsHarmlessRead(ASource: TGenericListSource; AOuter: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  // Ohne Cast nur, wo der genauere Typ nichts ändert: Vergleich mit nil, Assigned, TObject-Mitglieder an Objekten,
  // Zuweisung an einen Pointer.
  mParent := AOuter.Parent;
  case mParent.Kind of
    TSyntaxKind.BinaryExpr:
      Result := TGenericListSyntax.IsNil(TGenericListSyntax.CompareOperand(mParent, AOuter));
    TSyntaxKind.Call:
      Result := (mParent.ChildCount = 2) and TGenericListSyntax.IsIdentifierNamed(mParent[0], 'Assigned');
    TSyntaxKind.MemberAccess:
      Result := FKind.ClassOnly and TGenericListNames.IsObjectMember(mParent.Name);
    TSyntaxKind.AssignStatement:
      Result := (mParent.ChildCount = 2) and (mParent[1] = AOuter) and IsPointerTarget(ASource, mParent[0]);
  else
    Result := False;
  end;
end;

procedure TGenericListUsages.ClassifyRead(AFileIndex: Integer; ARead: TSyntaxNode; const AWhat: string);
var
  mOuter: TSyntaxNode;
begin
  mOuter := TGenericListSyntax.Unparen(ARead);
  if (mOuter.Parent <> nil) and not NoteCastRead(AFileIndex, ARead, mOuter) and
    not IsHarmlessRead(FFiles[AFileIndex], mOuter) then
  begin
    Fail(cTexts[TUsagesText.IsReadWithoutACast].Fmt([AWhat, LineOf(ARead)]));
  end;
end;

function TGenericListUsages.LoopScope(ASource: TGenericListSource; ALoop: TSyntaxNode): TSyntaxNode;
var
  mTypeRef, mDeclaration: TSyntaxNode;
begin
  // for var V: TPosition in L bzw. for var V in L: die Schleife; for V in L: die Routine mit der Variable V.
  Result := ALoop;
  mTypeRef := ALoop.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef <> nil then
  begin
    ASource.AddEdit(mTypeRef.StartPos, mTypeRef.EndPos, cItemPlaceholder);
    Exit;
  end;
  if TGenericListSyntax.HasInlineVar(ASource.Tree, ALoop) then
  begin
    Exit;
  end;
  Result := TGenericListSyntax.EnclosingRoutine(ALoop);
  mDeclaration := nil;
  if Result <> nil then
  begin
    mDeclaration := TGenericListSyntax.LocalDeclaration(Result, ALoop.Name);
  end;
  if mDeclaration = nil then
  begin
    Fail(cTexts[TUsagesText.TheLoopVariableInIs].Fmt([ALoop.Name, LineOf(ALoop)]));
    Exit(nil);
  end;
  RetypeDeclaration(ASource, mDeclaration, ALoop.Name, cItemPlaceholder, False);
end;

function TGenericListUsages.LoopVisitor(AFileIndex: Integer; ALoop: TSyntaxNode): TSyntaxNodeVisit;
begin
  Result :=
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := VisitLoop(AFileIndex, ALoop, ANode);
    end;
end;

function TGenericListUsages.VisitLoop(AFileIndex: Integer; ALoop, ANode: TSyntaxNode): Boolean;
begin
  if Failed then
  begin
    Exit(False);
  end;
  if (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and (ANode <> ALoop) and
    SameText(ANode.Name, ALoop.Name) then
  begin
    Exit(Fail(cTexts[TUsagesText.TheLoopVariableIsAlso].Fmt([ALoop.Name, LineOf(ANode)])));
  end;
  if TGenericListSyntax.IsIdentifierNamed(ANode, ALoop.Name) then
  begin
    if TGenericListSyntax.IsAssignTarget(TGenericListSyntax.Unparen(ANode)) then
    begin
      Exit(Fail(cTexts[TUsagesText.SomethingIsAssignedToThe].Fmt([ALoop.Name, LineOf(ANode)])));
    end;
    ClassifyRead(AFileIndex, ANode, ALoop.Name);
  end;
  Result := True;
end;

procedure TGenericListUsages.ClassifyLoop(AFileIndex: Integer; ALoop: TSyntaxNode);
var
  mScope: TSyntaxNode;
begin
  // for V in L do: V bekommt den Typ T, Casts auf V entfallen.
  mScope := LoopScope(FFiles[AFileIndex], ALoop);
  if mScope <> nil then
  begin
    mScope.Walk(LoopVisitor(AFileIndex, ALoop));
  end;
end;

function TGenericListUsages.ResolvedTypeOf(ASource: TGenericListSource; AValue: TSyntaxNode): string;
var
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := '';
  if not Resolves(ASource, AValue, mSymbol, mType, mTypeFound) then
  begin
    Exit;
  end;
  if mTypeFound then
  begin
    Result := mType.Name;
  end
  else
  begin
    Result := mSymbol.TypeName;
  end;
end;

function TGenericListUsages.ElementTypeOf(ASource: TGenericListSource; AArgument: TSyntaxNode): string;
var
  mValue, mBase: TSyntaxNode;
  mCastType: string;
begin
  mValue := TGenericListSyntax.Inner(AArgument);
  mBase := mValue;
  if (mBase.Kind = TSyntaxKind.Call) and (mBase.ChildCount > 0) then
  begin
    mBase := mBase[0];
  end;
  if TGenericListSyntax.IsNil(mValue) then
  begin
    Result := 'nil';
  end
  else if IsTypeCast(ASource, mValue, mCastType) then
  begin
    Result := mCastType;
  end
  else if TGenericListSyntax.IsAsCast(mValue) then
  begin
    Result := ASource.NodeText(mValue[1]);
  end
  else if (mBase.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', mBase.Name) and (mBase.ChildCount = 1) and
    TGenericListSyntax.IsPlainName(mBase[0]) then
  begin
    // TKlasse.Create(…): der Typ steht davor. Ist es kein Typ, gilt er beim Prüfen der Elemente als unbekannt.
    Result := ASource.NodeText(mBase[0]);
  end
  else
  begin
    Result := ResolvedTypeOf(ASource, mValue);
  end;
end;

procedure TGenericListUsages.NoteElement(AFileIndex: Integer; AArgument: TSyntaxNode);
var
  mElement: TGenericListElement;
begin
  mElement.FileIndex := AFileIndex;
  mElement.Node := AArgument;
  mElement.TypeName := ElementTypeOf(FFiles[AFileIndex], AArgument);
  FElements := FElements + [mElement];
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.GenericLists.Usages', cTexts);

end.
