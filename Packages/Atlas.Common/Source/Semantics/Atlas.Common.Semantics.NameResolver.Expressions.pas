unit Atlas.Common.Semantics.NameResolver.Expressions;

// Ausdrücke der Namensauflösung: der erste Name einer Kette (lokal, Mitglied der Methodenklasse, Unit, global,
// with-Mitglied), Werte von Ausdrücken (Aufruf, Index, Typumwandlung, Literal) und die Auswahl passender
// Überladungen nach Zahl und Typ der Argumente.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Lookup,
  Atlas.Common.Semantics.NameResolver.Typing,
  Atlas.Common.Semantics.NameResolver.Members,
  Atlas.Common.Semantics.NameResolver.Locals;

type
  /// <summary>Die Teile der Namensauflösung, auf denen Ausdrücke, Ketten, Kandidaten und Abfragen aufbauen.
  /// </summary>
  TResolverParts = record
    Place: TResolverPlace;
    Units: TResolverUnits;
    Lookup: TResolverLookup;
    Typing: TResolverTyping;
    Members: TResolverMembers;
    Locals: TResolverLocals;
  end;

  TResolverExpressions = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FLookup: TResolverLookup;
    FTyping: TResolverTyping;
    FMembers: TResolverMembers;
    FLocals: TResolverLocals;
    function ClassMember(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function UnitPrefix(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    function GlobalName(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function Overloads(const AName: string; AConsumed: Integer; const AFirst: TResolvedSymbol): TArray<TResolvedSymbol>;
    function IdentifierCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    function AccessCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    function UnitMemberCandidates(const AOwner: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    function TypeMemberCandidates(const AOwner, AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    function NodeSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function FirstCandidate(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function MemberSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function GenericMemberSymbol(ANode, AArgs: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function CallSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function IndexSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function ElementSymbol(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
    function DeclaredBase(const ACandidate: TResolvedSymbol; const AParam: string; out ABase: TResolvedSymbol): Boolean;
    function ParamFits(const ACandidate: TResolvedSymbol; AArg: Integer; const AArgType: string;
      out ASame: Boolean): Boolean;
    function CandidateScore(const ACandidate: TResolvedSymbol; AArgCount: Integer;
      const AArgTypes: TArray<string>): Integer;
  public
    constructor Create(const AParts: TResolverParts);
    /// <summary>Erster Name einer Kette an der Stelle; AConsumed: wie viele Namen er verbraucht (Unit-Namen mit
    /// Punkten).</summary>
    function ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Wie ResolveFirst, mit with-Mitgliedern zuerst und allen Überladungen einer Routine.</summary>
    function ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
      out AResults: TArray<TResolvedSymbol>): Boolean;
    /// <summary>Mögliche Symbole des Ausdrucks ANode (alle Überladungen eines Namens).</summary>
    function ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    /// <summary>Symbol, für das der Ausdruck ANode steht; bei Werten das Symbol, dessen Typ der Wert hat.</summary>
    function ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Typnamen der Argumente von ANode ab dem Kind AFirst; '' = unbekannt.</summary>
    function ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
    /// <summary>Überladungen, die zu AArgCount Argumenten der Typen AArgTypes passen; die mit den meisten genau
    /// passenden Typen. AArgCount &lt; 0: alle.</summary>
    function SelectOverloads(const ACandidates: TArray<TResolvedSymbol>; AArgCount: Integer;
      const AArgTypes: TArray<string>): TArray<TResolvedSymbol>;
    /// <summary>Mitglieder AName der umgebenden with-Ausdrücke; AStop: ein Ausdruck hat einen unbekannten Typ.
    /// </summary>
    function LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean): Boolean;
    /// <summary>Wie LookupWith, dazu die with-Anweisung und der Platz ihres Ausdrucks.</summary>
    function LookupWithOwner(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean;
      out AWith: TSyntaxNode; out AElement: Integer): Boolean;
    /// <summary>Typ des Ausdrucks AIndex der with-Anweisung AWith, an seiner eigenen Stelle aufgelöst.</summary>
    function WithElementType(AWith: TSyntaxNode; AIndex: Integer; out AType: TResolvedSymbol): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor;

/// <summary>Setzt bei allen Konstruktoren in AList den erzeugten Typ AType.</summary>
procedure MarkConstructed(var AList: TArray<TResolvedSymbol>; const AType: TResolvedSymbol);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].SymbolKind = TIndexSymbolKind.Constructor_ then
    begin
      AList[mIndex].Constructed := [AType];
    end;
  end;
end;

/// <summary>Typ eines Literals: Text, Gleitkomma oder Ganzzahl.</summary>
function LiteralSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mText: string;
begin
  mText := ANode.Name;
  Result := mText <> '';
  if not Result then
  begin
    Exit;
  end;
  if CharInSet(mText[1], ['''', '#']) then
  begin
    AResult := TResolvedSymbol.BuiltinOf('string');
  end
  else if not CharInSet(mText[1], ['0'..'9', '$', '%']) then
  begin
    Result := False;
  end
  else if (mText[1] <> '$') and ((Pos('.', mText) > 0) or (Pos('E', UpperCase(mText)) > 0)) then
  begin
    AResult := TResolvedSymbol.BuiltinOf('Double');
  end
  else
  begin
    AResult := TResolvedSymbol.BuiltinOf('Integer');
  end;
end;

/// <summary>Einträge aus AFitting, deren Wertung in AScores die beste ist.</summary>
function BestScored(const AFitting: TArray<TResolvedSymbol>; const AScores: TArray<Integer>): TArray<TResolvedSymbol>;
var
  mBest, mIndex: Integer;
begin
  mBest := MaxIntValue(AScores);
  Result := nil;
  for mIndex := 0 to High(AFitting) do
  begin
    if AScores[mIndex] = mBest then
    begin
      Result := Result + [AFitting[mIndex]];
    end;
  end;
end;

constructor TResolverExpressions.Create(const AParts: TResolverParts);
begin
  inherited Create;
  FPlace := AParts.Place;
  FUnits := AParts.Units;
  FLookup := AParts.Lookup;
  FTyping := AParts.Typing;
  FMembers := AParts.Members;
  FLocals := AParts.Locals;
end;

function TResolverExpressions.ClassMember(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  mClasses: TArray<TResolvedSymbol>;
  mClass: TResolvedSymbol;
begin
  mClasses := FTyping.MethodClasses;
  if Length(mClasses) = 0 then
  begin
    Exit(False);
  end;
  if SameText(AName, 'Self') then
  begin
    AResult := mClasses[0];
    Exit(True);
  end;
  // Innerster Typ zuerst, dann die äußeren (verschachtelte Typen sehen deren Mitglieder).
  for mClass in mClasses do
  begin
    if FMembers.FindMember(mClass, AName, AResult) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverExpressions.UnitPrefix(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
var
  mCount: Integer;
  mFound: TUnitIndex;
begin
  // Unit-Namen mit Punkten: längstes Präfix zuerst (System.SysUtils.Foo). Der
  // ganze Ausdruck zählt mit, sonst bleibt "Vcl.Werkzeug" in uses unaufgelöst.
  AConsumed := 1;
  for mCount := Length(ANames) downto 2 do
  begin
    if FUnits.FindQualifierUnit(string.Join('.', Copy(ANames, 0, mCount)), mFound) then
    begin
      AConsumed := mCount;
      AResult := TResolvedSymbol.OfUnit(mFound);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverExpressions.GlobalName(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  mFound: TUnitIndex;
begin
  Result := FLookup.LookupGlobal(FPlace.Current, AName, FPlace.InImplementation, False, AResult);
  if not Result and FUnits.FindQualifierUnit(AName, mFound) then
  begin
    AResult := TResolvedSymbol.OfUnit(mFound);
    Result := True;
  end;
end;

function TResolverExpressions.ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
begin
  AConsumed := 1;
  Result := FLocals.LookupLocal(ANames[0], AResult) or ClassMember(ANames[0], AResult) or
    UnitPrefix(ANames, AConsumed, AResult) or GlobalName(ANames[0], AResult);
end;

function TResolverExpressions.Overloads(const AName: string; AConsumed: Integer;
  const AFirst: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mClass: TResolvedSymbol;
begin
  // Überladungen: Mitglieder der eigenen Klasse oder freie Routinen derselben Unit.
  // Verschachtelte Routinen (#881): ihre Überladungen in der umgebenden Routine.
  Result := nil;
  if (AConsumed = 1) and (AFirst.Kind = TResolvedKind.Local) and (AFirst.SymbolKind = TIndexSymbolKind.Routine) then
  begin
    Result := FLocals.LocalOverloads(AFirst);
  end
  else if (AConsumed = 1) and (AFirst.Kind = TResolvedKind.Symbol) and (AFirst.SymbolKind in cRoutineKinds) then
  begin
    if (AFirst.Container <> '') and FTyping.CurrentClass(mClass) then
    begin
      Result := FMembers.FindMembers(mClass, AName);
    end;
    if Length(Result) = 0 then
    begin
      Result := FLocals.UnitRoutines(AFirst);
    end;
  end
  else
  begin
    Result := [AFirst];
  end;
end;

function TResolverExpressions.ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
  out AResults: TArray<TResolvedSymbol>): Boolean;
var
  mFirst: TResolvedSymbol;
  mStop: Boolean;
begin
  AConsumed := 1;
  AResults := nil;
  if LookupWith(ANames[0], AResults, mStop) then
  begin
    Exit(True);
  end;
  if mStop or not ResolveFirst(ANames, AConsumed, mFirst) then
  begin
    Exit(False);
  end;
  AResults := Overloads(ANames[0], AConsumed, mFirst);
  Result := True;
end;

function TResolverExpressions.IdentifierCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  mConsumed, mSavedOffset: Integer;
begin
  mSavedOffset := FPlace.Offset;
  FPlace.Offset := ANode.StartOffset;
  try
    if not ResolveFirstAll([ANode.Name], mConsumed, Result) then
    begin
      Result := nil;
    end;
  finally
    FPlace.Offset := mSavedOffset;
  end;
end;

function TResolverExpressions.UnitMemberCandidates(const AOwner: TResolvedSymbol;
  const AName: string): TArray<TResolvedSymbol>;
var
  mOwnerUnit: TUnitIndex;
  mSingle: TResolvedSymbol;
begin
  Result := nil;
  if FUnits.FindUnit(AOwner.UnitName, mOwnerUnit) and
    FLookup.LookupInUnit(mOwnerUnit, AName, not FPlace.IsCurrentFile(mOwnerUnit.FileName), False, mSingle) then
  begin
    Result := FLocals.UnitRoutines(mSingle);
  end;
end;

function TResolverExpressions.TypeMemberCandidates(const AOwner, AType: TResolvedSymbol;
  const AName: string): TArray<TResolvedSymbol>;
var
  mTarget: TResolvedSymbol;
begin
  // Wert einer Klassenreferenz (FError: ExceptClass): Mitglieder der Zielklasse, FError.Create ist
  // Exception.Create und liefert ein Exception. Die Referenz selbst hat im Index keine Vorfahren, ohne
  // diesen Schritt fände FindMembers nur TObject.Create.
  if not AOwner.IsType and FTyping.ClassRefTargetOf(AType, mTarget) then
  begin
    Result := FMembers.FindMembers(mTarget, AName);
    MarkConstructed(Result, mTarget);
    Exit;
  end;
  Result := FMembers.FindMembers(AType, AName);
  // TKunde.Create liefert TKunde, auch wenn Create aus TObject stammt.
  if AOwner.IsType then
  begin
    MarkConstructed(Result, AType);
  end;
end;

function TResolverExpressions.AccessCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  mOwner, mType: TResolvedSymbol;
begin
  Result := nil;
  if not ExprSymbol(ANode[0], mOwner) then
  begin
    Exit;
  end;
  if mOwner.Kind = TResolvedKind.UnitName then
  begin
    Result := UnitMemberCandidates(mOwner, ANode.Name);
  end
  else if FTyping.TypeOf(mOwner, mType) then
  begin
    Result := TypeMemberCandidates(mOwner, mType, ANode.Name);
  end;
end;

function TResolverExpressions.ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  mSingle: TResolvedSymbol;
begin
  Result := nil;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := IdentifierCandidates(ANode);
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) and
    (ANode.ChildCount > 0) then
  begin
    Result := AccessCandidates(ANode);
  end
  else if ExprSymbol(ANode, mSingle) then
  begin
    Result := [mSingle];
  end;
end;

function TResolverExpressions.FirstCandidate(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
begin
  mCandidates := ExprCandidates(ANode);
  Result := Length(mCandidates) > 0;
  if Result then
  begin
    AResult := mCandidates[0];
  end;
end;

function TResolverExpressions.GenericMemberSymbol(ANode, AArgs: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mArguments: TArray<string>;
  mIndex: Integer;
begin
  // Foo<Integer>: Typargumente an die Typparameter der Methode binden. Nur eine generische Überladung
  // passt; eine gleichnamige ohne Typparameter wäre falsch (TJSONObject.GetValue(Name): TJSONValue
  // neben TJSONValue.GetValue<T>). Ohne generischen Kandidaten bleibt der Ausdruck unbekannt.
  mCandidates := ExprCandidates(ANode[0]);
  mIndex := 0;
  while (mIndex <= High(mCandidates)) and (mCandidates[mIndex].TypeParams = '') do
  begin
    Inc(mIndex);
  end;
  if mIndex > High(mCandidates) then
  begin
    Exit(False);
  end;
  AResult := mCandidates[mIndex];
  mArguments := nil;
  for mIndex := 0 to AArgs.ChildCount - 1 do
  begin
    mArguments := mArguments + [FLookup.QualifyType(TIndexExtractor.TypeText(AArgs[mIndex]), FPlace.Current,
      FPlace.InImplementation)];
  end;
  AResult.Bindings := AResult.Bindings + TResolverText.Bind(AResult.TypeParams, mArguments);
  Result := True;
end;

function TResolverExpressions.MemberSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mArgs: TSyntaxNode;
begin
  mArgs := ANode.FindChild(TSyntaxKind.GenericArgs);
  if (mArgs <> nil) and (ANode.ChildCount > 0) and (ANode[0] <> mArgs) then
  begin
    Result := GenericMemberSymbol(ANode, mArgs, AResult);
  end
  else
  begin
    Result := FirstCandidate(ANode, AResult);
  end;
end;

function TResolverExpressions.CallSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
begin
  Result := False;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mCandidates := ExprCandidates(ANode[0]);
  if Length(mCandidates) = 0 then
  begin
    Exit;
  end;
  // TFoo(X) ist eine Typumwandlung.
  if not mCandidates[0].IsType then
  begin
    mCandidates := SelectOverloads(mCandidates, ANode.ChildCount - 1, ArgTypes(ANode, 1));
  end;
  AResult := mCandidates[0];
  Result := True;
end;

function TResolverExpressions.ElementSymbol(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
var
  mText: string;
  mFromUnit: TUnitIndex;
begin
  // TArray<T>[i]: das Element.
  Result := False;
  if SameText(AType.Name, 'TArray') and (Length(AType.Bindings) > 0) then
  begin
    mText := AType.Bindings[0];
    mText := Copy(mText, Pos('=', mText) + 1, MaxInt);
    Result := FUnits.UnitOf(AType, mFromUnit) and FLookup.ResolveTypeText(mText, mFromUnit, True, AResult);
  end;
end;

function TResolverExpressions.IndexSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mBase, mType: TResolvedSymbol;
begin
  if (ANode.ChildCount = 0) or not ExprSymbol(ANode[0], mBase) then
  begin
    Exit(False);
  end;
  // Liste.Items[i]: die indizierte Property selbst. Bei Lines[i][j] ist Base schon der Wert von Lines[i]
  // (ein string), nicht die Property (#1369, SynEdit).
  if (mBase.SymbolKind = TIndexSymbolKind.Property_) and (mBase.MaxArgs > 0) and
    (ANode[0].Kind <> TSyntaxKind.IndexAccess) then
  begin
    AResult := mBase;
    Exit(True);
  end;
  if not FTyping.TypeOf(mBase, mType) then
  begin
    Exit(False);
  end;
  Result := FMembers.DefaultProperty(mType, AResult);
  if not Result and mType.Builtin and TResolverText.IsStringName(mType.Name) then
  begin
    AResult := TResolvedSymbol.BuiltinOf('Char');
    Result := True;
  end;
  Result := Result or ElementSymbol(mType, AResult);
end;

function TResolverExpressions.NodeSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := FirstCandidate(ANode, AResult);
    TSyntaxKind.MemberAccess:
      Result := MemberSymbol(ANode, AResult);
    TSyntaxKind.Call:
      Result := CallSymbol(ANode, AResult);
    TSyntaxKind.IndexAccess:
      Result := IndexSymbol(ANode, AResult);
    TSyntaxKind.ParenExpr:
      Result := (ANode.ChildCount > 0) and ExprSymbol(ANode[0], AResult);
    TSyntaxKind.BinaryExpr:
      // (X as TBar): der Zieltyp.
      Result := SameText(ANode.Name, 'as') and (ANode.ChildCount = 2) and ExprSymbol(ANode[1], AResult) and
        AResult.IsType;
    TSyntaxKind.IfExpr:
      Result := (ANode.ChildCount >= 2) and ExprSymbol(ANode[1], AResult);
    TSyntaxKind.Literal:
      Result := LiteralSymbol(ANode, AResult);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TResolverExpressions.ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
begin
  Result := False;
  if (ANode = nil) or (FPlace.InferDepth > cMaxInferDepth * 4) then
  begin
    Exit;
  end;
  FPlace.InferDepth := FPlace.InferDepth + 1;
  try
    Result := NodeSymbol(ANode, AResult);
  finally
    FPlace.InferDepth := FPlace.InferDepth - 1;
  end;
end;

function TResolverExpressions.ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
var
  mIndex: Integer;
  mArg: TSyntaxNode;
  mValue, mType: TResolvedSymbol;
  mText: string;
begin
  Result := nil;
  for mIndex := AFirst to ANode.ChildCount - 1 do
  begin
    mArg := ANode[mIndex];
    if mArg.Kind = TSyntaxKind.GenericArgs then
    begin
      Continue;
    end;
    mText := '';
    if mArg.Kind = TSyntaxKind.SetConstructor then
    begin
      mText := '[]';
    end
    else if ExprSymbol(mArg, mValue) and FTyping.TypeOf(mValue, mType) then
    begin
      mText := mType.Name;
    end;
    Result := Result + [mText];
  end;
end;

function TResolverExpressions.DeclaredBase(const ACandidate: TResolvedSymbol; const AParam: string;
  out ABase: TResolvedSymbol): Boolean;
var
  mOwner: TUnitIndex;
  mDeclared: TResolvedSymbol;
begin
  Result := FUnits.UnitOf(ACandidate, mOwner) and FLookup.ResolveTypeText(AParam, mOwner, True, mDeclared) and
    FTyping.TypeOf(mDeclared, ABase) and not SameText(ABase.Name, AParam);
end;

function TResolverExpressions.ParamFits(const ACandidate: TResolvedSymbol; AArg: Integer; const AArgType: string;
  out ASame: Boolean): Boolean;
var
  mParam: string;
  mBase: TResolvedSymbol;
begin
  mParam := ACandidate.ParamTypes[AArg];
  Result := TResolverText.ArgumentFits(mParam, AArgType);
  ASame := Result and (AArgType <> '') and TResolverText.SameFamily(mParam, AArgType);
  if Result or TResolverText.IsBuiltinName(mParam) or not DeclaredBase(ACandidate, mParam, mBase) then
  begin
    Exit;
  end;
  Result := TResolverText.ArgumentFits(mBase.Name, AArgType);
  ASame := Result and TResolverText.SameFamily(mBase.Name, AArgType);
end;

function TResolverExpressions.CandidateScore(const ACandidate: TResolvedSymbol; AArgCount: Integer;
  const AArgTypes: TArray<string>): Integer;
var
  mArg: Integer;
  mSame: Boolean;
begin
  if (ACandidate.SymbolKind in cRoutineKinds) and
    ((AArgCount < ACandidate.MinArgs) or (AArgCount > ACandidate.MaxArgs)) then
  begin
    Exit(-1);
  end;
  Result := 0;
  for mArg := 0 to Min(Min(AArgCount, Length(ACandidate.ParamTypes)), Length(AArgTypes)) - 1 do
  begin
    if not ParamFits(ACandidate, mArg, AArgTypes[mArg], mSame) then
    begin
      Exit(-1);
    end;
    if mSame then
    begin
      Inc(Result);
    end;
  end;
end;

function TResolverExpressions.SelectOverloads(const ACandidates: TArray<TResolvedSymbol>; AArgCount: Integer;
  const AArgTypes: TArray<string>): TArray<TResolvedSymbol>;
var
  mCandidate: TResolvedSymbol;
  mFitting: TArray<TResolvedSymbol>;
  mScores: TArray<Integer>;
  mScore: Integer;
begin
  if (AArgCount < 0) or (Length(ACandidates) <= 1) then
  begin
    Exit(ACandidates);
  end;
  mFitting := nil;
  mScores := nil;
  for mCandidate in ACandidates do
  begin
    mScore := CandidateScore(mCandidate, AArgCount, AArgTypes);
    if mScore >= 0 then
    begin
      mFitting := mFitting + [mCandidate];
      mScores := mScores + [mScore];
    end;
  end;
  // Passt keine, lieber alle zeigen als eine falsche.
  if Length(mFitting) = 0 then
  begin
    Exit(ACandidates);
  end;
  Result := BestScored(mFitting, mScores);
end;

function TResolverExpressions.LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean): Boolean;
var
  mWith: TSyntaxNode;
  mElement: Integer;
begin
  Result := LookupWithOwner(AName, AResults, AStop, mWith, mElement);
end;

function TResolverExpressions.LookupWithOwner(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean; out AWith: TSyntaxNode; out AElement: Integer): Boolean;
var
  mWith: TSyntaxNode;
  mIndex: Integer;
  mType: TResolvedSymbol;
begin
  Result := False;
  AStop := False;
  AResults := nil;
  AWith := nil;
  AElement := -1;
  for mWith in FPlace.EnclosingWiths do
  begin
    for mIndex := mWith.ChildCount - 2 downto 0 do
    begin
      // Unbekannter Typ: der Name könnte ein Mitglied sein, also lieber nichts liefern.
      AStop := not WithElementType(mWith, mIndex, mType);
      if AStop then
      begin
        Exit;
      end;
      AResults := FMembers.FindMembers(mType, AName);
      if Length(AResults) > 0 then
      begin
        AWith := mWith;
        AElement := mIndex;
        Exit(True);
      end;
    end;
  end;
end;

function TResolverExpressions.WithElementType(AWith: TSyntaxNode; AIndex: Integer;
  out AType: TResolvedSymbol): Boolean;
var
  mValue: TResolvedSymbol;
  mSavedOffset: Integer;
begin
  // Den Ausdruck an seiner eigenen Stelle auflösen, außerhalb des with-Rumpfs.
  mSavedOffset := FPlace.Offset;
  FPlace.Offset := AWith[AIndex].StartOffset;
  try
    Result := ExprSymbol(AWith[AIndex], mValue) and FTyping.TypeOf(mValue, AType);
  finally
    FPlace.Offset := mSavedOffset;
  end;
end;

end.
