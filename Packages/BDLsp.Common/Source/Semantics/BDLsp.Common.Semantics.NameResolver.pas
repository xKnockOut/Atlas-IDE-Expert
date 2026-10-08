unit BDLsp.Common.Semantics.NameResolver;

// Namensauflösung, Grundstufe: ordnet einem Bezeichner im Quelltext seine
// Deklaration zu.
//
// Reihenfolge für den ersten Namen einer Kette A.B.C:
//   1. Lokale Deklarationen der umgebenden Routinen (innen nach außen):
//      Parameter, Result, lokale var/const/type, verschachtelte Routinen,
//      Inline-Variablen vor der Position.
//   2. Bei Methoden (TFoo.Bar) Self und die Mitglieder von TFoo samt
//      Vorfahren.
//   3. Die eigene Unit (im interface-Teil nur deren interface).
//   4. Units aus uses: implementation-uses, dann interface-uses, jeweils
//      von hinten (die letzte Unit gewinnt), zuletzt System.
//   5. Unit-Namen (auch mit Punkten: System.SysUtils.Foo).
// Jeder weitere Name wird im Typ des vorigen gesucht: Mitglieder einer
// Unit, eines Typs oder des deklarierten Typs einer Variablen, eines
// Feldes, einer Property oder des Ergebnisses einer Funktion; Vorfahren
// werden durchlaufen (Klassen ohne Vorfahr erben von TObject).
//
// Nicht in dieser Stufe: Überladungen, Generics, Class Helper, with,
// Typinferenz von Ausdrücken. Was nicht sicher auflösbar ist (z. B.
// Foo(1).Bar), liefert kein Ergebnis statt eines geratenen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract;

type
  TResolvedKind = (None, UnitName, Symbol, Local);

  TResolvedSymbol = record
    Kind: TResolvedKind;
    Name: string;
    /// <summary>Unit der Deklaration (bei Local die eigene Unit).</summary>
    UnitName: string;
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
    SymbolKind: TIndexSymbolKind;
    /// <summary>Umgebender Typ bei Mitgliedern.</summary>
    Container: string;
    /// <summary>Deklarierter Typ (Variablen, Felder, Properties, Parameter, Funktionsergebnis).</summary>
    TypeName: string;
    Ancestors: TArray<string>;
    IsParameter: Boolean;
    function Found: Boolean;
    function IsType: Boolean;
    function QualifiedName: string;
  end;

  TEnsureUnitFunc = reference to function(const AUnitName: string): Boolean;

  TNameResolver = class
  private
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    // Pro Aufruf von Resolve
    FTree: TSyntaxTree;
    FCurrent: TUnitIndex;
    FOffset: Integer;
    FInImplementation: Boolean;
    function FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    function ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
    function FromSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
    function FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
      AIsParameter: Boolean): TResolvedSymbol;
    function LookupInUnit(const AUnit: TUnitIndex; const AName: string; AOnlyInterface, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol): Boolean;
    function LookupGlobal(const AUnit: TUnitIndex; const AName: string; AWithImplementation, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol): Boolean;
    function ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
      AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean;
    function TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    function FindMember(const AType: TResolvedSymbol; const AName: string; ADepth: Integer;
      out AResult: TResolvedSymbol): Boolean;
    function AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
    function EnclosingRoutines: TArray<TSyntaxNode>;
    function LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupInDeclarations(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupInlineVars(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function MethodClass(out AType: TResolvedSymbol): Boolean;
    function ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    function TokenIndexAt(const APosition: TTextPosition): Integer;
  public
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc = nil);
    /// <summary>Löst den Bezeichner an APosition auf.</summary>
    function Resolve(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Löst die Kette ANames (A.B.C) so auf, wie sie an AOffset stünde.</summary>
    function ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean = False): TResolvedSymbol;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace) für uses ohne Präfix.</summary>
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  BDLsp.Common.Index.Extractor;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  MaxDepth = 32;

function NoResult: TResolvedSymbol;
begin
  Result := Default(TResolvedSymbol);
  Result.Kind := TResolvedKind.None;
end;

function Contains(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

{ TResolvedSymbol }

function TResolvedSymbol.Found: Boolean;
begin
  Result := Kind <> TResolvedKind.None;
end;

function TResolvedSymbol.IsType: Boolean;
begin
  Result := (Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (SymbolKind in TypeKinds);
end;

function TResolvedSymbol.QualifiedName: string;
begin
  if Container = '' then
    Result := Name
  else
    Result := Container + '.' + Name;
end;

{ TNameResolver }

constructor TNameResolver.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

function TNameResolver.FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace: string;
begin
  if SameText(AName, FCurrent.UnitName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  if FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  if Assigned(FEnsureUnit) and FEnsureUnit(AName) and FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  // uses SysUtils mit Namespace System → System.SysUtils
  for Namespace in FNamespaces do
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) or
      (Assigned(FEnsureUnit) and FEnsureUnit(Namespace + '.' + AName) and FIndex.FindUnit(Namespace + '.' + AName, AUnit)) then
      Exit(True);
  Result := False;
end;

function TNameResolver.UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if AResolved.Kind = TResolvedKind.Local then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  if SameText(AResolved.FileName, FCurrent.FileName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  Result := FIndex.FindFile(AResolved.FileName, AUnit) or FindUnit(AResolved.UnitName, AUnit);
end;

function TNameResolver.ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
var
  Names: TList<string>;
  Index: Integer;
begin
  // Höchste Priorität zuerst: letzte uses-Einträge gewinnen.
  Names := TList<string>.Create;
  try
    if AWithImplementation then
      for Index := High(AUnit.ImplementationUses) downto 0 do
        Names.Add(AUnit.ImplementationUses[Index]);
    for Index := High(AUnit.InterfaceUses) downto 0 do
      Names.Add(AUnit.InterfaceUses[Index]);
    if not SameText(AUnit.UnitName, 'System') then
      Names.Add('System');
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

function TNameResolver.FromSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
begin
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := ASymbol.Name;
  Result.UnitName := AUnit.UnitName;
  Result.FileName := AUnit.FileName;
  Result.Range := ASymbol.Range;
  Result.SelectionRange := ASymbol.SelectionRange;
  Result.SymbolKind := ASymbol.Kind;
  Result.Container := ASymbol.Container;
  Result.TypeName := ASymbol.TypeName;
  Result.Ancestors := ASymbol.Ancestors;
  Result.IsParameter := False;
end;

function TNameResolver.FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
  AIsParameter: Boolean): TResolvedSymbol;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Local;
  Result.Name := AName;
  Result.UnitName := FCurrent.UnitName;
  Result.FileName := FCurrent.FileName;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.SelectionRange := Result.Range;
  // Auswahl auf den Namen selbst legen.
  for Index := 0 to High(FTree.Tokens) do
  begin
    Token := FTree.Tokens[Index];
    if Token.Offset >= ANode.EndOffset then
      Break;
    if (Token.Offset >= ANode.StartOffset) and (Token.Kind = TPascalTokenKind.Identifier) and
      (SameText(Token.Text, AName) or SameText(Token.Text, '&' + AName)) then
    begin
      Result.SelectionRange := TTextRange.Create(Token.StartPos, Token.EndPos);
      Break;
    end;
  end;
  Result.SymbolKind := AKind;
  Result.TypeName := TIndexExtractor.DeclaredType(ANode);
  Result.IsParameter := AIsParameter;
end;

function TNameResolver.LookupInUnit(const AUnit: TUnitIndex; const AName: string;
  AOnlyInterface, AOnlyTypes: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
  begin
    if not SameText(Symbol.Name, AName) then
      Continue;
    if AOnlyInterface and not Symbol.InInterface then
      Continue;
    if AOnlyTypes and not (Symbol.Kind in TypeKinds) then
      Continue;
    // Unit-Ebene; Enum-Werte sind ohne SCOPEDENUMS auch dort sichtbar.
    if (Symbol.Container <> '') and (Symbol.Kind <> TIndexSymbolKind.EnumMember) then
      Continue;
    AResult := FromSymbol(AUnit, Symbol);
    Exit(True);
  end;
  Result := False;
end;

function TNameResolver.LookupGlobal(const AUnit: TUnitIndex; const AName: string;
  AWithImplementation, AOnlyTypes: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  UnitName: string;
  Used: TUnitIndex;
begin
  if LookupInUnit(AUnit, AName, not AWithImplementation, AOnlyTypes, AResult) then
    Exit(True);
  for UnitName in ScopeUnits(AUnit, AWithImplementation) do
    if FindUnit(UnitName, Used) and LookupInUnit(Used, AName, True, AOnlyTypes, AResult) then
      Exit(True);
  Result := False;
end;

function TNameResolver.ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  Dot: Integer;
  Qualifier: TUnitIndex;
begin
  Result := False;
  if ATypeName = '' then
    Exit;
  // Unit.Typ
  Dot := LastDelimiter('.', ATypeName);
  if Dot > 0 then
  begin
    if FindUnit(Copy(ATypeName, 1, Dot - 1), Qualifier) then
      Exit(LookupInUnit(Qualifier, Copy(ATypeName, Dot + 1, MaxInt), not SameText(Qualifier.FileName, FCurrent.FileName),
        True, AResult));
    Exit;
  end;
  Result := LookupGlobal(AFromUnit, ATypeName, AWithImplementation, True, AResult);
end;

function TNameResolver.TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  Current, Next: TResolvedSymbol;
  FromUnit: TUnitIndex;
  Depth: Integer;
  WithImplementation: Boolean;
begin
  // Typen sind ihr eigener Typ; Aliase werden verfolgt.
  if AResolved.IsType then
    Current := AResolved
  else
  begin
    if AResolved.TypeName = '' then
      Exit(False);
    if not UnitOf(AResolved, FromUnit) then
      Exit(False);
    WithImplementation := (AResolved.Kind = TResolvedKind.Local) or
      (SameText(FromUnit.FileName, FCurrent.FileName) and FInImplementation);
    if not ResolveTypeName(AResolved.TypeName, FromUnit, WithImplementation, Current) then
      Exit(False);
  end;
  Depth := 0;
  while (Current.SymbolKind = TIndexSymbolKind.TypeAlias) and (Current.TypeName <> '') and (Depth < MaxDepth) do
  begin
    // Eigene Variable: der out-Parameter würde Current.TypeName vor dem Aufruf leeren.
    if not UnitOf(Current, FromUnit) or
      not ResolveTypeName(Current.TypeName, FromUnit, SameText(FromUnit.FileName, FCurrent.FileName), Next) then
      Exit(False);
    Current := Next;
    Inc(Depth);
  end;
  AType := Current;
  Result := True;
end;

function TNameResolver.AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
var
  FromUnit: TUnitIndex;
  Name: string;
begin
  Result := False;
  if not UnitOf(AType, FromUnit) then
    Exit;
  if Length(AType.Ancestors) > 0 then
    Name := AType.Ancestors[0]
  else if (AType.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(AType.Name, 'TObject') then
    Name := 'TObject'
  else if (AType.SymbolKind = TIndexSymbolKind.InterfaceType) and not SameText(AType.Name, 'IInterface') then
    Name := 'IInterface'
  else
    Exit;
  Result := ResolveTypeName(Name, FromUnit, SameText(FromUnit.FileName, FCurrent.FileName), AAncestor) and
    not SameText(AAncestor.QualifiedName, AType.QualifiedName);
end;

function TNameResolver.FindMember(const AType: TResolvedSymbol; const AName: string; ADepth: Integer;
  out AResult: TResolvedSymbol): Boolean;
var
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Ancestor: TResolvedSymbol;
  TypeName: string;
begin
  Result := False;
  if (ADepth > MaxDepth) or not UnitOf(AType, OwnerUnit) then
    Exit;
  TypeName := AType.QualifiedName;
  // Erste Fundstelle: die Deklaration im Typ steht vor dem Rumpf in implementation.
  for Symbol in OwnerUnit.Symbols do
    if SameText(Symbol.Container, TypeName) and SameText(Symbol.Name, AName) then
    begin
      AResult := FromSymbol(OwnerUnit, Symbol);
      Exit(True);
    end;
  if AncestorOf(AType, Ancestor) then
    Result := FindMember(Ancestor, AName, ADepth + 1, AResult);
end;

function TNameResolver.EnclosingRoutines: TArray<TSyntaxNode>;
var
  Path: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  // Innerste Routine zuerst.
  Path := TList<TSyntaxNode>.Create;
  try
    Node := FTree.Root;
    repeat
      Descended := False;
      for Index := 0 to Node.ChildCount - 1 do
        if Contains(Node[Index], FOffset) then
        begin
          Node := Node[Index];
          if Node.Kind = TSyntaxKind.RoutineDecl then
            Path.Insert(0, Node);
          Descended := True;
          Break;
        end;
    until not Descended;
    Result := Path.ToArray;
  finally
    Path.Free;
  end;
end;

function TNameResolver.LookupInDeclarations(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
  Kind: TIndexSymbolKind;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        if LookupInDeclarations(Child, AName, AResult) then
          Exit(True);
      TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        for Name in Child.Name.Split([',']) do
          if SameText(Name.Trim, AName) then
          begin
            if Child.Kind = TSyntaxKind.VarDecl then
              Kind := TIndexSymbolKind.Variable
            else
              Kind := TIndexSymbolKind.Constant;
            AResult := FromNode(Child, Name.Trim, Kind, False);
            Exit(True);
          end;
      TSyntaxKind.TypeDecl:
        if SameText(Child.Name, AName) then
        begin
          AResult := FromNode(Child, Child.Name, TIndexSymbolKind.TypeAlias, False);
          Exit(True);
        end;
      TSyntaxKind.RoutineDecl:
        if SameText(Child.Name, AName) then
        begin
          AResult := FromNode(Child, Child.Name, TIndexSymbolKind.Routine, False);
          Exit(True);
        end;
    end;
  end;
  Result := False;
end;

function TNameResolver.LookupInlineVars(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  // Inline-Variablen gelten ab ihrer Deklaration; verschachtelte Routinen nicht durchsuchen.
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.StartOffset > FOffset then
      Break;
    if Child.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      for Name in Child.Name.Split([',']) do
        if SameText(Name.Trim, AName) then
        begin
          AResult := FromNode(Child, Name.Trim, TIndexSymbolKind.Variable, False);
          Exit(True);
        end;
    end
    else if (Child.Kind <> TSyntaxKind.RoutineDecl) and Contains(Child, FOffset) and
      LookupInlineVars(Child, AName, AResult) then
      Exit(True);
  end;
  Result := False;
end;

function TNameResolver.LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  Routine, Header, Params, Param: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  for Routine in EnclosingRoutines do
  begin
    if LookupInlineVars(Routine, AName, AResult) then
      Exit(True);
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
    begin
      Params := Header.FindChild(TSyntaxKind.Parameters);
      if Params <> nil then
        for Index := 0 to Params.ChildCount - 1 do
        begin
          Param := Params[Index];
          if Param.Kind <> TSyntaxKind.Parameter then
            Continue;
          for Name in Param.Name.Split([',']) do
            if SameText(Name.Trim, AName) then
            begin
              AResult := FromNode(Param, Name.Trim, TIndexSymbolKind.Variable, True);
              Exit(True);
            end;
        end;
      if SameText(AName, 'Result') and (Header.FindChild(TSyntaxKind.TypeReference) <> nil) then
      begin
        AResult := FromNode(Header, 'Result', TIndexSymbolKind.Variable, False);
        AResult.SelectionRange := AResult.Range;
        Exit(True);
      end;
    end;
    if LookupInDeclarations(Routine, AName, AResult) then
      Exit(True);
  end;
  Result := False;
end;

function TNameResolver.MethodClass(out AType: TResolvedSymbol): Boolean;
var
  Routines: TArray<TSyntaxNode>;
  Name: string;
  Dot: Integer;
begin
  // Äußerste Routine mit Punkt im Namen: procedure TFoo.Bar
  Routines := EnclosingRoutines;
  Result := False;
  if Length(Routines) = 0 then
    Exit;
  Name := Routines[High(Routines)].Name;
  Dot := LastDelimiter('.', Name);
  if Dot = 0 then
    Exit;
  Result := ResolveTypeName(Copy(Name, 1, Dot - 1), FCurrent, True, AType);
end;

function TNameResolver.ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
var
  ClassType: TResolvedSymbol;
  Count: Integer;
  UnitName: string;
  Found: TUnitIndex;
begin
  AConsumed := 1;
  if LookupLocal(ANames[0], AResult) then
    Exit(True);
  if MethodClass(ClassType) then
  begin
    if SameText(ANames[0], 'Self') then
    begin
      AResult := ClassType;
      Exit(True);
    end;
    if FindMember(ClassType, ANames[0], 0, AResult) then
      Exit(True);
  end;
  // Unit-Namen mit Punkten: längstes Präfix zuerst (System.SysUtils.Foo).
  for Count := Length(ANames) - 1 downto 2 do
  begin
    UnitName := string.Join('.', Copy(ANames, 0, Count));
    if FindUnit(UnitName, Found) then
    begin
      AConsumed := Count;
      AResult := NoResult;
      AResult.Kind := TResolvedKind.UnitName;
      AResult.Name := Found.UnitName;
      AResult.UnitName := Found.UnitName;
      AResult.FileName := Found.FileName;
      Exit(True);
    end;
  end;
  if LookupGlobal(FCurrent, ANames[0], FInImplementation, False, AResult) then
    Exit(True);
  if FindUnit(ANames[0], Found) then
  begin
    AResult := NoResult;
    AResult.Kind := TResolvedKind.UnitName;
    AResult.Name := Found.UnitName;
    AResult.UnitName := Found.UnitName;
    AResult.FileName := Found.FileName;
    Exit(True);
  end;
  Result := False;
end;

function TNameResolver.ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean): TResolvedSymbol;
var
  Section: TSyntaxNode;
  Consumed, Index: Integer;
  Current, TypeInfo, Ancestor: TResolvedSymbol;
  Owner: TUnitIndex;
begin
  Result := NoResult;
  if (ATree = nil) or (Length(ANames) = 0) then
    Exit;
  FTree := ATree;
  FOffset := AOffset;
  FCurrent := TIndexExtractor.Extract(ATree, AFileName);
  Section := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
  // Programme haben keinen interface-Teil: alles ist "implementation".
  FInImplementation := (Section = nil) or not Contains(Section, AOffset);

  if AInherited then
  begin
    // inherited Create: im Vorfahren der Klasse der umgebenden Methode suchen.
    if not MethodClass(Current) or not AncestorOf(Current, Ancestor) or
      not FindMember(Ancestor, ANames[0], 0, Current) then
      Exit;
    Consumed := 1;
  end
  else if not ResolveFirst(ANames, Consumed, Current) then
    Exit;

  for Index := Consumed to High(ANames) do
  begin
    if Current.Kind = TResolvedKind.UnitName then
    begin
      if not FindUnit(Current.UnitName, Owner) or
        not LookupInUnit(Owner, ANames[Index], not SameText(Owner.FileName, FCurrent.FileName), False, Current) then
        Exit;
      Continue;
    end;
    if not TypeOf(Current, TypeInfo) or not FindMember(TypeInfo, ANames[Index], 0, Current) then
      Exit;
  end;
  Result := Current;
end;

function TNameResolver.TokenIndexAt(const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(FTree.Tokens) do
  begin
    Token := FTree.Tokens[Index];
    if ComparePositions(Token.StartPos, APosition) > 0 then
      Break;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (ComparePositions(APosition, Token.EndPos) <= 0) then
      Exit(Index);
  end;
  Result := -1;
end;

function TNameResolver.Resolve(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  Tokens: TArray<TPascalToken>;
  Index, First: Integer;
  Names: TList<string>;
  IsInherited: Boolean;

  function Clean(const AText: string): string;
  begin
    // &Begin → Begin
    if (AText <> '') and (AText[1] = '&') then
      Result := Copy(AText, 2, MaxInt)
    else
      Result := AText;
  end;

begin
  Result := NoResult;
  if ATree = nil then
    Exit;
  FTree := ATree;
  Tokens := ATree.Tokens;
  Index := TokenIndexAt(APosition);
  if Index < 0 then
    Exit;
  Names := TList<string>.Create;
  try
    Names.Add(Clean(Tokens[Index].Text));
    First := Index;
    while (First >= 2) and Tokens[First - 1].IsSymbol('.') and
      (Tokens[First - 2].Kind = TPascalTokenKind.Identifier) do
    begin
      Dec(First, 2);
      Names.Insert(0, Clean(Tokens[First].Text));
    end;
    // Foo(1).Bar, A[0].B: Ergebnis eines Ausdrucks, in dieser Stufe nicht auflösbar.
    if (First >= 2) and Tokens[First - 1].IsSymbol('.') then
      Exit;
    IsInherited := (First >= 1) and Tokens[First - 1].IsKeyword('inherited');
    Result := ResolveChain(ATree, AFileName, Names.ToArray, Tokens[Index].Offset, IsInherited);
  finally
    Names.Free;
  end;
end;

end.
