unit Atlas.Common.Semantics.NameResolver.Locals;

// Lokale Namen der Namensauflösung: Parameter, Result, Typparameter aus dem Kopf, lokale var/const/type,
// verschachtelte Routinen und Inline-Variablen vor der Stelle, in den umgebenden Routinen von innen nach außen.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Lookup;

type
  TResolverLocals = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FLookup: TResolverLookup;
    /// <summary>Deklariert ANode (Namensliste "A, B") den Namen AName? Dann AResult als lokaler Name.</summary>
    function NamedLocal(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind; AIsParameter: Boolean;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Ein Eintrag eines Deklarationsteils: Abschnitt, var/const, type oder Routine. AFoundBefore: Eine
    /// Variable oder Konstante davor heißt schon so; AFinal: weitere Einträge zählen nicht mehr.</summary>
    function LookupInChild(AChild: TSyntaxNode; const AName: string; AFoundBefore: Boolean;
      out AFound: TResolvedSymbol; out AFinal: Boolean): Boolean;
    /// <summary>Inline-Variable bzw. for-var-Variable ANode namens AName, wenn die Stelle darin liegt.</summary>
    function InlineDeclaration(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>for var I := ...: das Wort nach "for" ist "var".</summary>
    function IsForVar(ANode: TSyntaxNode): Boolean;
    /// <summary>Parameter, Typparameter oder Result aus dem Kopf von ARoutine.</summary>
    function LookupInHeader(ARoutine: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupParameter(AHeader: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Typparameter aus dem Kopf: die des Typs (TFoo&lt;K, V&gt;.Bar) und die der Methode (Bar&lt;T&gt;).
    /// </summary>
    function LookupTypeParameter(AHeader: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupResult(ARoutine, AHeader: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Deklaration von ARoutine im interface-Teil, wenn ihr Ergebnistyp für den Rumpf gilt (#1369).
    /// </summary>
    function InterfaceRoutine(ARoutine: TSyntaxNode; out ADeclared: TResolvedSymbol): Boolean;
  public
    constructor Create(APlace: TResolverPlace; AUnits: TResolverUnits; ALookup: TResolverLookup);
    /// <summary>Knoten ANode des Baums als lokaler Name AName.</summary>
    function FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
      AIsParameter: Boolean): TResolvedSymbol;
    /// <summary>Lokaler Name AName an der Stelle, innerste Routine zuerst.</summary>
    function LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Deklarationsteil von ANode: Wie dcc gilt bei doppelt deklarierten Variablen die letzte (#1369).
    /// </summary>
    function LookupInDeclarations(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Inline-Variablen in ANode vor der Stelle; verschachtelte Routinen nicht.</summary>
    function LookupInlineVars(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Alle gleichnamigen verschachtelten Routinen neben der lokalen Routine ASymbol (#881), also
    /// ihre Überladungen in derselben umgebenden Routine, ASymbol eingeschlossen.</summary>
    function LocalOverloads(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
    /// <summary>Überladene freie Routinen derselben Unit; bei verschachtelten Routinen die der umgebenden Routine
    /// (#881).</summary>
    function UnitRoutines(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Extractor;

/// <summary>Hat die Deklaration ADeclared dieselben Parametertypen wie die Routine ARoutine des Baums? Dann ist
/// sie dieselbe Routine und keine andere Überladung.</summary>
function SameParamTypes(const ADeclared: TResolvedSymbol; ARoutine: TSyntaxNode): Boolean;
var
  mMinArgs, mMaxArgs, mIndex: Integer;
  mTypes: TArray<string>;
begin
  TIndexExtractor.ParamInfo(ARoutine, mMinArgs, mMaxArgs, mTypes);
  Result := Length(mTypes) = Length(ADeclared.ParamTypes);
  if Result then
  begin
    for mIndex := 0 to High(mTypes) do
    begin
      if not SameText(Trim(mTypes[mIndex]), Trim(ADeclared.ParamTypes[mIndex])) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Hat die Deklaration ANode eine Typangabe ohne Namen (array, set, record, Prozedurtyp …)?</summary>
function HasAnonymousType(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind in [TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.ClassOfType,
      TSyntaxKind.SetType, TSyntaxKind.RecordType, TSyntaxKind.ProcedureType, TSyntaxKind.FileType,
      TSyntaxKind.EnumType, TSyntaxKind.SubrangeType] then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Ausdruck, aus dem der Typ einer Deklaration ohne Typangabe folgt; nil ohne.</summary>
function InitializerOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  // var X := TFoo.Create; const C = 5; for var I := 0 ...: Typ aus dem Ausdruck. Eine Typangabe ohne Namen
  // (const Klassen: array[0..1] of TFooClass = (TFoo, TBar)) hat keinen Typ des Ausdrucks: Das erste Element
  // der Liste ist nicht der Typ der Konstanten (#1326).
  if (ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ConstDecl]) and
    (ANode.ChildCount > 0) and not HasAnonymousType(ANode) then
  begin
    Result := ANode[ANode.ChildCount - 1];
  end
  else if (ANode.Kind = TSyntaxKind.ForStatement) and (ANode.ChildCount > 0) then
  begin
    Result := ANode[0];
  end;
end;

constructor TResolverLocals.Create(APlace: TResolverPlace; AUnits: TResolverUnits; ALookup: TResolverLookup);
begin
  inherited Create;
  FPlace := APlace;
  FUnits := AUnits;
  FLookup := ALookup;
end;

function TResolverLocals.FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
  AIsParameter: Boolean): TResolvedSymbol;
var
  mIndex: Integer;
  mTree: TSyntaxTree;
begin
  mTree := FPlace.Tree;
  Result := TResolvedSymbol.Empty;
  Result.Kind := TResolvedKind.Local;
  Result.Name := AName;
  Result.UnitName := FPlace.Current.UnitName;
  Result.FileName := FPlace.Current.FileName;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.SelectionRange := Result.Range;
  // Auswahl auf den Namen selbst legen; ab dem ersten Token des Knotens, nicht ab Dateianfang: Das
  // kostete je lokalem Namen einen Lauf über alle Tokens davor (Diagnoselog 15.10.2026, große Units).
  for mIndex := mTree.FirstTokenFrom(ANode.StartOffset) to High(mTree.Tokens) do
  begin
    if mTree.Tokens[mIndex].Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (mTree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      (SameText(mTree.Tokens[mIndex].Text, AName) or SameText(mTree.Tokens[mIndex].Text, '&' + AName)) then
    begin
      Result.SelectionRange := TTextRange.Create(mTree.Tokens[mIndex].StartPos, mTree.Tokens[mIndex].EndPos);
      Break;
    end;
  end;
  Result.SymbolKind := AKind;
  Result.TypeName := TIndexExtractor.DeclaredType(ANode);
  if Result.TypeName <> '' then
  begin
    Result.TypeArgs := TIndexExtractor.GenericArgsText(TIndexExtractor.DeclaredTypeNode(ANode));
  end
  else
  begin
    Result.Initializer := InitializerOf(ANode);
  end;
  Result.IsParameter := AIsParameter;
  if AKind in cRoutineKinds then
  begin
    TIndexExtractor.ParamInfo(ANode, Result.MinArgs, Result.MaxArgs, Result.ParamTypes);
  end;
end;

function TResolverLocals.NamedLocal(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
  AIsParameter: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  mName: string;
begin
  for mName in ANode.Name.Split([',']) do
  begin
    if SameText(mName.Trim, AName) then
    begin
      AResult := FromNode(ANode, mName.Trim, AKind, AIsParameter);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverLocals.LookupInChild(AChild: TSyntaxNode; const AName: string; AFoundBefore: Boolean;
  out AFound: TResolvedSymbol; out AFinal: Boolean): Boolean;
begin
  AFinal := False;
  Result := False;
  case AChild.Kind of
    TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
      begin
        Result := LookupInDeclarations(AChild, AName, AFound);
        AFinal := Result and not (AFound.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Constant]);
      end;
    TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
      Result := NamedLocal(AChild, AName, TResolverNodes.DeclarationKind(AChild), False, AFound);
    TSyntaxKind.TypeDecl:
      begin
        Result := not AFoundBefore and SameText(AChild.Name, AName);
        AFinal := Result;
        if Result then
        begin
          AFound := FromNode(AChild, AChild.Name, TIndexSymbolKind.TypeAlias, False);
        end;
      end;
    TSyntaxKind.RoutineDecl:
      begin
        Result := not AFoundBefore and SameText(AChild.Name, AName);
        AFinal := Result;
        if Result then
        begin
          AFound := FromNode(AChild, AChild.Name, TIndexSymbolKind.Routine, False);
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TResolverLocals.LookupInDeclarations(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mIndex: Integer;
  mFound: TResolvedSymbol;
  mFinal: Boolean;
begin
  // Doppelt deklarierte Variablen und Konstanten (E2004): Wie dcc gilt die letzte Deklaration (#1369, Fall
  // Cm.E2004: "mZahl: Integer; mZahl: string" macht "mZahl := 1" zu E2010 'string' und 'Integer').
  Result := False;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if LookupInChild(ANode[mIndex], AName, Result, mFound, mFinal) then
    begin
      AResult := mFound;
      Result := True;
      if mFinal then
      begin
        Exit;
      end;
    end;
  end;
end;

function TResolverLocals.IsForVar(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := FPlace.Tree.FirstTokenFrom(ANode.StartOffset);
  Result := (mIndex < High(FPlace.Tree.Tokens)) and FPlace.Tree.Tokens[mIndex].IsKeyword('for') and
    FPlace.Tree.Tokens[mIndex + 1].IsKeyword('var');
end;

function TResolverLocals.InlineDeclaration(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  if ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
  begin
    Exit(NamedLocal(ANode, AName, TIndexSymbolKind.Variable, False, AResult));
  end;
  // for var I := ... und for var X in ... (#1239): gilt nur in der Schleife.
  Result := (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
    TResolverNodes.Contains(ANode, FPlace.Offset) and SameText(ANode.Name, AName) and IsForVar(ANode);
  if Result then
  begin
    AResult := FromNode(ANode, ANode.Name, TIndexSymbolKind.Variable, False);
  end;
end;

function TResolverLocals.LookupInlineVars(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mChild: TSyntaxNode;
begin
  // Inline-Variablen gelten ab ihrer Deklaration; verschachtelte Routinen nicht durchsuchen. Iterativ mit eigenem
  // Stapel: Der Weg zum Cursor kann durch lange Ausdrucksketten führen.
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    TResolverNodes.PushChildrenBefore(mPending, ANode, FPlace.Offset);
    while not Result and (mPending.Count > 0) do
    begin
      mChild := mPending.Pop;
      Result := InlineDeclaration(mChild, AName, AResult);
      if not Result and not (mChild.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
        TSyntaxKind.RoutineDecl]) and TResolverNodes.Contains(mChild, FPlace.Offset) then
      begin
        TResolverNodes.PushChildrenBefore(mPending, mChild, FPlace.Offset);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TResolverLocals.LookupParameter(AHeader: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mParams: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    if (mParams[mIndex].Kind = TSyntaxKind.Parameter) and
      NamedLocal(mParams[mIndex], AName, TIndexSymbolKind.Variable, True, AResult) then
    begin
      Exit(True);
    end;
  end;
end;

function TResolverLocals.LookupTypeParameter(AHeader: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mGroup, mIndex: Integer;
  mParam: TSyntaxNode;
begin
  for mGroup := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mGroup].Kind <> TSyntaxKind.GenericParams then
    begin
      Continue;
    end;
    for mIndex := 0 to AHeader[mGroup].ChildCount - 1 do
    begin
      mParam := AHeader[mGroup][mIndex];
      if SameText(mParam.Name, AName) then
      begin
        AResult := FromNode(mParam, mParam.Name, TIndexSymbolKind.TypeAlias, False);
        AResult.IsTypeParameter := True;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TResolverLocals.InterfaceRoutine(ARoutine: TSyntaxNode; out ADeclared: TResolvedSymbol): Boolean;
begin
  Result := (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.ImplementationSection) and
    (Pos('.', ARoutine.Name) = 0) and FLookup.LookupInUnit(FPlace.Current, ARoutine.Name, True, False, ADeclared);
  if Result then
  begin
    Result := (ADeclared.SymbolKind = TIndexSymbolKind.Routine) and (ADeclared.TypeName <> '') and
      not ContainsText(ADeclared.Signature, 'overload') and SameParamTypes(ADeclared, ARoutine);
  end;
end;

function TResolverLocals.LookupResult(ARoutine, AHeader: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mDeclared: TResolvedSymbol;
begin
  Result := SameText(AName, 'Result') and (AHeader.FindChild(TSyntaxKind.TypeReference) <> nil);
  if not Result then
  begin
    Exit;
  end;
  AResult := FromNode(AHeader, 'Result', TIndexSymbolKind.Variable, False);
  AResult.SelectionRange := AResult.Range;
  // Weicht der Kopf im implementation-Teil vom interface-Teil ab (E2037), gilt wie bei dcc der
  // Ergebnistyp aus dem interface-Teil (#1369, Fall Cm.E2037).
  if InterfaceRoutine(ARoutine, mDeclared) then
  begin
    AResult.TypeName := mDeclared.TypeName;
    AResult.TypeArgs := mDeclared.TypeArgs;
  end;
end;

function TResolverLocals.LookupInHeader(ARoutine: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mHeader: TSyntaxNode;
begin
  mHeader := TResolverNodes.RoutineHeaderOf(ARoutine);
  Result := (mHeader <> nil) and (LookupParameter(mHeader, AName, AResult) or
    LookupTypeParameter(mHeader, AName, AResult) or LookupResult(ARoutine, mHeader, AName, AResult));
end;

function TResolverLocals.LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in FPlace.EnclosingRoutines do
  begin
    if LookupInlineVars(mRoutine, AName, AResult) or LookupInHeader(mRoutine, AName, AResult) or
      LookupInDeclarations(mRoutine, AName, AResult) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kann ANode die Zeile ALine enthalten? Unbekanntes Ende (0:0) zählt als ja.</summary>
function MayContainLine(ANode: TSyntaxNode; ALine: Integer): Boolean;
var
  mEndKnown: Boolean;
begin
  mEndKnown := (ANode.EndPos.Line > 0) or (ANode.EndPos.Character > 0);
  Result := (ANode.StartPos.Line <= ALine) and (not mEndKnown or (ANode.EndPos.Line >= ALine));
end;

function TResolverLocals.LocalOverloads(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mNode, mParent, mSibling: TSyntaxNode;
  mIndex: Integer;
  mStartPos: TTextPosition;
  mName: string;
begin
  Result := [ASymbol];
  if (ASymbol.Kind <> TResolvedKind.Local) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) or
    (FPlace.Tree = nil) then
  begin
    Exit;
  end;
  mStartPos := ASymbol.Range.StartPos;
  mName := ASymbol.Name;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mNode := FPlace.Tree.Root.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.RoutineDecl) and (AVisited.StartPos = mStartPos) and
        SameText(AVisited.Name, mName) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      // Nur in Knoten, die die Zeile umfassen: Vorher lief jede Auflösung einer lokalen Routine durch den
      // ganzen Baum, quadratisch in der Länge der Unit (verschachtelte Routinen in großen Units).
      if not MayContainLine(AVisited, mStartPos.Line) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
  if (mNode = nil) or (mNode.Parent = nil) then
  begin
    Exit;
  end;
  mParent := mNode.Parent;
  // Überladungen stehen in derselben umgebenden Routine, vor oder hinter ASymbol; in der Reihenfolge der
  // Deklaration, unabhängig davon, welche die Auflösung gewählt hat.
  Result := nil;
  for mIndex := 0 to mParent.ChildCount - 1 do
  begin
    mSibling := mParent[mIndex];
    if mSibling = mNode then
    begin
      TResolvedSymbol.AddDistinct(Result, ASymbol);
    end
    else if (mSibling.Kind = TSyntaxKind.RoutineDecl) and SameText(mSibling.Name, ASymbol.Name) then
    begin
      TResolvedSymbol.AddDistinct(Result, FromNode(mSibling, mSibling.Name, TIndexSymbolKind.Routine, False));
    end;
  end;
end;

function TResolverLocals.UnitRoutines(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mOwner: TUnitIndex;
  mPosition: Integer;
  mSameUnit: Boolean;
begin
  if (ASymbol.Kind = TResolvedKind.Local) and (ASymbol.SymbolKind = TIndexSymbolKind.Routine) then
  begin
    Exit(LocalOverloads(ASymbol));
  end;
  Result := [ASymbol];
  if (ASymbol.Kind <> TResolvedKind.Symbol) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) or
    (ASymbol.Container <> '') or not FUnits.UnitOf(ASymbol, mOwner) then
  begin
    Exit;
  end;
  mSameUnit := FPlace.IsCurrentFile(mOwner.FileName);
  for mPosition in mOwner.SymbolsNamed(ASymbol.Name) do
  begin
    if (mOwner.Symbols[mPosition].Kind = TIndexSymbolKind.Routine) and (mOwner.Symbols[mPosition].Container = '') and
      (mSameUnit or mOwner.Symbols[mPosition].InInterface) then
    begin
      TResolvedSymbol.AddDistinct(Result, TResolvedSymbol.FromIndex(mOwner, mOwner.Symbols[mPosition]));
    end;
  end;
end;

end.
