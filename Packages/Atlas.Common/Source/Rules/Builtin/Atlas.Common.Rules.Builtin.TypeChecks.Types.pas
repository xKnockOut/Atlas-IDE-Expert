unit Atlas.Common.Rules.Builtin.TypeChecks.Types;

// Gemeinsame Hilfen der Typprüfungen (TypeChecks, TypeChecks.Hresult, TypeChecks.VarArguments, StringConversions):
// deklarierte Typen als Text, dynamische Arrays und prozedurale Typen über Aliase, Parameter einer Routine aus Index
// oder Baum, Knoten in Pre-Order.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature;

/// <summary>Dateiname für die Namensauflösung wie in den übrigen Regeln.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
/// <summary>Quelltext von ANode.</summary>
function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
/// <summary>Typtext ohne Leerzeichen vor spitzen Klammern ("TArray &lt;Integer&gt;" aus dem Index).</summary>
function NormalizedType(const AText: string): string;
/// <summary>Typ der Deklaration ANode (Variable, Parameter, Feld, Typ) als Quelltext; '' ohne.</summary>
function NodeTypeText(const AText: string; ANode: TSyntaxNode): string;
/// <summary>Alle Knoten unter ARoot (samt ARoot) in der Reihenfolge eines rekursiven Laufs, aber über einen
/// eigenen Stapel: Ausdrucksketten können sehr tief sein (Bericht M1).</summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
/// <summary>Liegt APosition im Bereich von ANode?</summary>
function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
/// <summary>Innerste Deklaration (Variable, Parameter, Feld, Typ, Konstante) um APosition; nil ohne.</summary>
function DeclarationAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
/// <summary>Deklarierter Typ von ASymbol als Quelltext ("TArray&lt;Double&gt;", "array of Integer"); bei Aliasen
/// der Typ hinter "=". Aus TypeName, sonst aus dem Kopf des Index, sonst aus der Deklaration im Baum (lokale
/// Namen). '' wenn unbekannt.</summary>
function DeclaredTypeText(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
/// <summary>Steht der Typtext selbst für ein dynamisches Array (array of T, TArray&lt;T&gt;)? array of const
/// ist ein offenes Array.</summary>
function IsDynamicArrayText(const AText: string): Boolean;
/// <summary>Ist der Typtext ATypeName, so wie er in AFromUnit steht, ein dynamisches Array? Aliase werden
/// verfolgt (TWerte = array of Double; TListe = TWerte). False, wenn es nicht sicher feststeht.</summary>
function IsDynamicArrayType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
/// <summary>Ist der Typtext, so wie er in AFromUnit steht, ein prozeduraler Typ ohne of object und ohne
/// reference to (procedure(...), function(...): T bzw. ein Alias darauf)? False, wenn es nicht sicher feststeht.
/// </summary>
function IsPlainProcedureType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
/// <summary>Parameter der Routine ASymbol in Reihenfolge, je Name ein Eintrag: aus dem Kopf im Index bzw. für
/// lokale Routinen aus dem Baum (auch für string-conversion, #1377). False bei Überladungen (auch mit overload im
/// Kopf) oder unbekanntem Kopf.</summary>
function RoutineParams(const AContext: TRuleContext; const ASymbol: TResolvedSymbol;
  out AParams: TArray<TSignatureParameter>): Boolean;
/// <summary>Unit, in der ein aufgelöstes Symbol steht (bei lokalen Namen die geprüfte Datei).</summary>
function SymbolUnit(AResolver: TNameResolver; const ALocal: TUnitIndex; const ASymbol: TResolvedSymbol;
  out AUnit: TUnitIndex): Boolean;
/// <summary>Ist ACallee ein Aufruf der eingebauten Routine AName (nicht überdeckt von einer eigenen
/// Deklaration gleichen Namens)?</summary>
function IsIntrinsicCall(AResolver: TNameResolver; const AContext: TRuleContext; const AFileName: string;
  ACallee: TSyntaxNode; const AName: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

const
  // Dynamische Arrays der RTL, auch wenn ihre Unit nicht im Index steht.
  RtlDynamicArrays: array[0..9] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
    'TObjectDynArray', 'TWordDynArray', 'TCardinalDynArray', 'TInt64DynArray', 'TDoubleDynArray',
    'TBooleanDynArray');
  MaxAliasDepth = 16;
  // Prozedurale Typen der RTL ohne of object, auch wenn ihre Unit nicht im Index steht.
  RtlPlainProcedureTypes: array[0..3] of string = ('TListSortCompare', 'TStringListSortCompare',
    'TThreadFunc', 'TFarProc');

/// <summary>Dateiname für die Namensauflösung wie in den übrigen Regeln.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
begin
  Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Typtext ohne Leerzeichen vor spitzen Klammern ("TArray &lt;Integer&gt;" aus dem Index).</summary>
function NormalizedType(const AText: string): string;
begin
  Result := Trim(AText).Replace(' <', '<').Replace('< ', '<').Replace(' >', '>');
end;

/// <summary>Typ der Deklaration ANode (Variable, Parameter, Feld, Typ) als Quelltext; '' ohne.</summary>
function NodeTypeText(const AText: string; ANode: TSyntaxNode): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType,
      TSyntaxKind.FileType] then
    begin
      Exit(Trim(Copy(AText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset)));
    end;
  end;
end;

/// <summary>Alle Knoten unter ARoot (samt ARoot) in der Reihenfolge eines rekursiven Laufs, aber über einen
/// eigenen Stapel: Ausdrucksketten können sehr tief sein (Bericht M1).</summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  Pending: TStack<TSyntaxNode>;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  Pending := TStack<TSyntaxNode>.Create;
  Nodes := TList<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Nodes.Add(Node);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
    Result := Nodes.ToArray;
  finally
    Nodes.Free;
    Pending.Free;
  end;
end;

/// <summary>Liegt APosition im Bereich von ANode?</summary>
function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((ANode.EndPos.Line > APosition.Line) or
    ((ANode.EndPos.Line = APosition.Line) and (ANode.EndPos.Character >= APosition.Character)));
end;

/// <summary>Innerste Deklaration (Variable, Parameter, Feld, Typ, Konstante) um APosition; nil ohne.</summary>
function DeclarationAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  // Vorwärts in Pre-Order: Der letzte Treffer ist der innerste.
  for Node in PreOrder(ARoot) do
  begin
    if (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field, TSyntaxKind.TypeDecl,
      TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar]) and Covers(Node, APosition) then
    begin
      Result := Node;
    end;
  end;
end;

/// <summary>Typ hinter dem ersten ':' bzw. '=' auf oberster Klammerebene einer Signatur ("Werte: array of Double"
/// bzw. "TWerte = array of Double"), bis vor ';'; '' ohne.</summary>
function TypeAfterSeparator(const ASignature: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(ASignature) do
  begin
    if CharInSet(ASignature[Index], ['(', '[', '<']) then
    begin
      Inc(Depth);
    end
    else if CharInSet(ASignature[Index], [')', ']', '>']) then
    begin
      Dec(Depth);
    end
    else if CharInSet(ASignature[Index], [':', '=']) and (Depth = 0) then
    begin
      Result := Copy(ASignature, Index + 1, MaxInt);
      Break;
    end;
  end;
  if Pos(';', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos(';', Result) - 1);
  end;
  if Result <> '' then
  begin
    Result := NormalizedType(Result);
  end;
end;

/// <summary>Typ der lokalen Deklaration von ASymbol aus dem Baum; '' ohne.</summary>
function LocalDeclaredType(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
var
  Decl: TSyntaxNode;
begin
  Result := '';
  if (ASymbol.Kind <> TResolvedKind.Local) or (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Decl := DeclarationAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
  if Decl <> nil then
  begin
    Result := NormalizedType(NodeTypeText(AContext.Text, Decl));
  end;
end;

function DeclaredTypeText(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
begin
  if ASymbol.TypeName <> '' then
  begin
    Result := ASymbol.TypeName;
    if ASymbol.TypeArgs <> '' then
    begin
      Result := Result + '<' + ASymbol.TypeArgs + '>';
    end;
    Result := NormalizedType(Result);
  end
  else if ASymbol.Signature <> '' then
  begin
    Result := TypeAfterSeparator(ASymbol.Signature);
  end
  else
  begin
    Result := LocalDeclaredType(AContext, ASymbol);
  end;
end;

/// <summary>Steht der Typtext selbst für ein dynamisches Array (array of T, TArray&lt;T&gt;)? array of const
/// ist ein offenes Array.</summary>
function IsDynamicArrayText(const AText: string): Boolean;
var
  Text: string;
begin
  Text := NormalizedType(AText);
  Result := (StartsText('array of ', Text) and not SameText(Text, 'array of const')) or
    StartsText('TArray<', Text) or StartsText('System.TArray<', Text);
end;

/// <summary>Ist der Typtext ATypeName, so wie er in AFromUnit steht, ein dynamisches Array? Aliase werden
/// verfolgt (TWerte = array of Double; TListe = TWerte). False, wenn es nicht sicher feststeht.</summary>
function IsDynamicArrayType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
var
  Name: string;
  Current: TResolvedSymbol;
  FromUnit: TUnitIndex;
  Depth: Integer;
begin
  Name := NormalizedType(ATypeName);
  FromUnit := AFromUnit;
  for Depth := 0 to MaxAliasDepth do
  begin
    if IsDynamicArrayText(Name) then
    begin
      Exit(True);
    end;
    if (Name = '') or (Pos(' ', Name) > 0) or (Pos('<', Name) > 0) or (Pos('^', Name) > 0) then
    begin
      Exit(False);
    end;
    if not AResolver.ResolveTypeFrom(FromUnit, Name, Current) then
    begin
      // Ohne Deklaration im Index: nur die bekannten Arrays der RTL.
      Exit(MatchText(Name, RtlDynamicArrays) or MatchText(Copy(Name, LastDelimiter('.', Name) + 1, MaxInt),
        RtlDynamicArrays));
    end;
    if Current.Builtin or (Current.SymbolKind <> TIndexSymbolKind.TypeAlias) or
      not AResolver.DeclaringUnit(Current, FromUnit) then
    begin
      Exit(False);
    end;
    Name := DeclaredTypeText(AContext, Current);
  end;
  Result := False;
end;

/// <summary>Ist der Typtext, so wie er in AFromUnit steht, ein prozeduraler Typ ohne of object und ohne
/// reference to (procedure(...), function(...): T bzw. ein Alias darauf)? False, wenn es nicht sicher feststeht.
/// </summary>
function IsPlainProcedureType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
var
  Name: string;
  Current: TResolvedSymbol;
  FromUnit: TUnitIndex;
  Depth: Integer;
begin
  Name := NormalizedType(ATypeName);
  FromUnit := AFromUnit;
  for Depth := 0 to MaxAliasDepth do
  begin
    if StartsText('procedure', Name) or StartsText('function', Name) then
    begin
      Exit(not ContainsText(Name, ' of object'));
    end;
    if (Name = '') or (Pos(' ', Name) > 0) or (Pos('<', Name) > 0) or (Pos('^', Name) > 0) then
    begin
      Exit(False);
    end;
    if not AResolver.ResolveTypeFrom(FromUnit, Name, Current) then
    begin
      Exit(MatchText(Copy(Name, LastDelimiter('.', Name) + 1, MaxInt), RtlPlainProcedureTypes));
    end;
    if Current.Builtin or (Current.SymbolKind <> TIndexSymbolKind.TypeAlias) or
      not AResolver.DeclaringUnit(Current, FromUnit) then
    begin
      Exit(False);
    end;
    Name := DeclaredTypeText(AContext, Current);
  end;
  Result := False;
end;

/// <summary>Index der Klammer, die die Klammer an AOpen schließt; 0 ohne.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  Index, Depth: Integer;
begin
  Result := 0;
  Depth := 0;
  for Index := AOpen to Length(AText) do
  begin
    if AText[Index] = '(' then
    begin
      Inc(Depth);
    end
    else if AText[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit(Index);
      end;
    end;
  end;
end;

/// <summary>Parameter aus dem Kopf ASignature des Index; False, wenn die Klammer nicht schließt oder overload im
/// Kopf steht.</summary>
function SignatureParams(const ASignature: string; out AParams: TArray<TSignatureParameter>): Boolean;
var
  Open, Close: Integer;
begin
  AParams := nil;
  Open := Pos('(', ASignature);
  if Open = 0 then
  begin
    Exit(True);
  end;
  Close := ClosingParen(ASignature, Open);
  // Überladungen aus anderen Units kennt die Namensauflösung nicht immer (Overloads leer); die Direktive
  // im Kopf zeigt sie sicher an.
  Result := (Close > 0) and not MatchText('overload', SplitString(LowerCase(Copy(ASignature, Close + 1, MaxInt)),
    ' ;'));
  if Result then
  begin
    AParams := TChangeSignature.ParseParameters(Copy(ASignature, Open + 1, Close - Open - 1));
  end;
end;

/// <summary>Kopf der lokalen Routine, deren Name an APosition steht; nil ohne.</summary>
function HeaderAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  for Node in PreOrder(ARoot) do
  begin
    if (Node.Kind = TSyntaxKind.RoutineHeader) and Covers(Node, APosition) then
    begin
      Result := Node;
    end;
  end;
end;

function ModifierText(AModifier: TParameterModifier): string;
begin
  case AModifier of
    TParameterModifier.ConstParam:
      Result := 'const';
    TParameterModifier.VarParam:
      Result := 'var';
    TParameterModifier.OutParam:
      Result := 'out';
    TParameterModifier.ConstRefParam:
      Result := 'constref';
  else
    Result := '';
  end;
end;

/// <summary>Parameter aus dem Kopf AHeader im Baum, je Name ein Eintrag.</summary>
function HeaderParams(const AText: string; AHeader: TSyntaxNode): TArray<TSignatureParameter>;
var
  Parameters, Node: TSyntaxNode;
  Index: Integer;
  Name: string;
  Parameter: TSignatureParameter;
begin
  Result := nil;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
  begin
    Exit;
  end;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Node := Parameters[Index];
    if Node.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    for Name in Node.Name.Split([',']) do
    begin
      Parameter := Default(TSignatureParameter);
      Parameter.Name := Trim(Name);
      Parameter.Group := Index;
      Parameter.TypeName := NodeTypeText(AText, Node);
      Parameter.Modifier := ModifierText(Node.Modifier);
      Result := Result + [Parameter];
    end;
  end;
end;

function RoutineParams(const AContext: TRuleContext; const ASymbol: TResolvedSymbol;
  out AParams: TArray<TSignatureParameter>): Boolean;
var
  Header: TSyntaxNode;
begin
  AParams := nil;
  Result := False;
  if (Length(ASymbol.Overloads) > 0) or (Length(ASymbol.VariantParams) > 1) then
  begin
    Exit;
  end;
  if ASymbol.Signature <> '' then
  begin
    Exit(SignatureParams(ASymbol.Signature, AParams));
  end;
  if (ASymbol.Kind <> TResolvedKind.Local) or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  Header := HeaderAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
  Result := Header <> nil;
  if Result then
  begin
    AParams := HeaderParams(AContext.Text, Header);
  end;
end;

/// <summary>Unit, in der ein aufgelöstes Symbol steht (bei lokalen Namen die geprüfte Datei).</summary>
function SymbolUnit(AResolver: TNameResolver; const ALocal: TUnitIndex; const ASymbol: TResolvedSymbol;
  out AUnit: TUnitIndex): Boolean;
begin
  if ASymbol.Kind = TResolvedKind.Local then
  begin
    AUnit := ALocal;
    Exit(True);
  end;
  Result := AResolver.DeclaringUnit(ASymbol, AUnit);
end;

/// <summary>Ist ACallee ein Aufruf der eingebauten Routine AName (nicht überdeckt von einer eigenen
/// Deklaration gleichen Namens)?</summary>
function IsIntrinsicCall(AResolver: TNameResolver; const AContext: TRuleContext; const AFileName: string;
  ACallee: TSyntaxNode; const AName: string): Boolean;
var
  Symbol, TypeInfo: TResolvedSymbol;
  TypeFound: Boolean;
begin
  Result := False;
  if (ACallee = nil) or (ACallee.Kind <> TSyntaxKind.Identifier) or not SameText(ACallee.Name, AName) then
  begin
    Exit;
  end;
  if not AResolver.NodeType(AContext.Tree, AFileName, ACallee, Symbol, TypeInfo, TypeFound) then
  begin
    Exit(True);
  end;
  Result := Symbol.Builtin or SameText(Symbol.UnitName, 'System');
end;

end.
