unit Atlas.Common.Rules.Builtin.TypeRestrictions.Attributes;

// Regel aus TypeRestrictions, registriert mit RegisterTypeRestrictionRules:
//   attribute-usage-invalid       Attribute des Compilers am falschen Ziel
//                                 (#1033): [Weak] an Feldern und Variablen,
//                                 deren Typ sicher weder Klasse noch
//                                 Interface ist (E2584), [Volatile] an Typ,
//                                 Routine oder Property (E2325), Weak,
//                                 Unsafe, Volatile oder Ref doppelt am
//                                 selben Ziel (E2326, nicht in sich
//                                 ausschließenden Zweigen); Argument eines
//                                 Attributs, das sicher eine Variable oder
//                                 Routine der Datei ist (E2448). Eigene
//                                 Attribute dürfen mehrfach stehen; ein Typ
//                                 Weak bzw. WeakAttribute in der Datei macht
//                                 die Regel für diesen Namen still.

interface

uses
  Atlas.Common.Rules.Contract;

const
  AttributeUsageInvalidRuleId = 'attribute-usage-invalid';

type
  TAttributeUsageInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

{ TAttributeUsageInvalidRule }

const
  // Attribute des Compilers, die er selbst prüft (System.WeakAttribute …).
  CompilerCheckedAttributes: array[0..3] of string = ('Weak', 'Unsafe', 'Volatile', 'Ref');
  // Typarten, die sicher weder Klasse noch Interface sind (E2584). ProcedureType fehlt: reference to ist ein
  // Interface.
  NonReferenceTypeKinds = [TSyntaxKind.RecordType, TSyntaxKind.EnumType, TSyntaxKind.SetType, TSyntaxKind.ArrayType,
    TSyntaxKind.PointerType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType];
  // Ziele, an denen Volatile nicht stehen darf (Compiler Attributes: keine Typen, Routinen, Methoden).
  VolatileForbiddenTargets = [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
    TSyntaxKind.PropertyDecl];

/// <summary>Knoten des Namens eines Eintrags im Attribut-Knoten ([Name] bzw. [Name(…)]).</summary>
function AttributeNameNode(AItem: TSyntaxNode): TSyntaxNode;
begin
  Result := AItem;
  if (AItem.Kind = TSyntaxKind.Call) and (AItem.ChildCount > 0) then
  begin
    Result := AItem[0];
  end;
end;

/// <summary>Punktkette eines Bezeichners bzw. MemberAccess; '' bei anderen Ausdrücken. Iterativ (Bericht M1):
/// erst die Kette hinab, dann die Namen von innen nach außen anhängen.</summary>
function DottedNameOf(ANode: TSyntaxNode): string;
var
  Chain: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Chain := TStack<TSyntaxNode>.Create;
  try
    Node := ANode;
    while (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount = 1) do
    begin
      Chain.Push(Node);
      Node := Node[0];
    end;
    Result := '';
    if Node.Kind = TSyntaxKind.Identifier then
    begin
      Result := Node.Name;
    end;
    while (Chain.Count > 0) and (Result <> '') do
    begin
      Result := Result + '.' + Chain.Pop.Name;
    end;
  finally
    Chain.Free;
  end;
end;

/// <summary>Name des Compiler-Attributs (Weak, Unsafe, Volatile, Ref) für den Eintrag AItem, '' bei anderen.
/// [WeakAttribute] und [System.Weak] zählen mit; deklariert die Datei einen Typ gleichen Namens, nicht.</summary>
function CompilerAttribute(const ATypes: TFileTypes; AItem: TSyntaxNode): string;
var
  Name, Bare: string;
  Dot: Integer;
begin
  Result := '';
  Name := DottedNameOf(AttributeNameNode(AItem));
  Dot := LastDelimiter('.', Name);
  if (Dot > 0) and not SameText(Copy(Name, 1, Dot - 1), 'System') then
  begin
    Exit;
  end;
  Bare := Copy(Name, Dot + 1, MaxInt);
  if EndsText('Attribute', Bare) and (Length(Bare) > Length('Attribute')) then
  begin
    Bare := Copy(Bare, 1, Length(Bare) - Length('Attribute'));
  end;
  if not MatchText(Bare, CompilerCheckedAttributes) then
  begin
    Exit;
  end;
  if (ATypes.IndexOf(Bare) >= 0) or (ATypes.IndexOf(Bare + 'Attribute') >= 0) then
  begin
    Exit;
  end;
  Result := CompilerCheckedAttributes[IndexText(Bare, CompilerCheckedAttributes)];
end;

/// <summary>Deklaration, zu der der Attribut-Knoten AAttribute gehört: der nächste Geschwisterknoten, der kein
/// Attribut ist, bzw. der Parameter; nil ohne.</summary>
function AttributeTarget(AAttribute: TSyntaxNode): TSyntaxNode;
var
  Parent: TSyntaxNode;
  Index: Integer;
  Found: Boolean;
begin
  Result := nil;
  Parent := AAttribute.Parent;
  if Parent = nil then
  begin
    Exit;
  end;
  if Parent.Kind = TSyntaxKind.Parameter then
  begin
    Exit(Parent);
  end;
  Found := False;
  for Index := 0 to Parent.ChildCount - 1 do
  begin
    if Parent[Index] = AAttribute then
    begin
      Found := True;
    end
    else if Found and (Parent[Index].Kind <> TSyntaxKind.Attribute) then
    begin
      Exit(Parent[Index]);
    end;
  end;
end;

/// <summary>Ist der Typ des Felds bzw. der Variablen (Kind von AType) sicher weder Klasse noch Interface? Eingebaute
/// Werttypen und Records, Aufzählungen, Mengen, Arrays, Zeiger der Datei; Aliase werden verfolgt.</summary>
function CertainlyNoReference(const ATypes: TFileTypes; AType: TSyntaxNode): Boolean;
var
  Name: string;
  Index, Depth: Integer;
begin
  if AType.Kind in NonReferenceTypeKinds then
  begin
    Exit(True);
  end;
  if (AType.Kind <> TSyntaxKind.TypeReference) or (AType.FindChild(TSyntaxKind.GenericArgs) <> nil) then
  begin
    Exit(False);
  end;
  Name := AType.Name;
  for Depth := 1 to 16 do
  begin
    if (Name = '') or (Pos('.', Name) > 0) or (Pos('<', Name) > 0) then
    begin
      Exit(False);
    end;
    if ATypes.DeclaredKind(Name) in NonReferenceTypeKinds then
    begin
      Exit(True);
    end;
    Index := ATypes.IndexOf(Name);
    if Index < 0 then
    begin
      // Pointer bleibt außen vor: die Hilfe nennt nur Klassen und Interfaces, der Fall ist nicht abgeglichen.
      Exit(not SameText(Name, 'Pointer') and (MatchText(Name, BuiltinTypeNames) or
        MatchText(Name, BooleanTypeNames)));
    end;
    if ATypes.AliasOf[Index] <> '' then
    begin
      Name := ATypes.AliasOf[Index];
    end
    else if ATypes.Types[Index].Kind = TSyntaxKind.TypeReference then
    begin
      Name := ATypes.Types[Index].Name;
    end
    else
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

function TAttributeUsageInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AttributeUsageInvalidRuleId, TRuleSeverity.Error, 'Attribut falsch verwendet');
end;

procedure TAttributeUsageInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Paths: TArray<string>;
  Attributes: TList<TSyntaxNode>;
  Names: TDeclarationNames;
  Node: TSyntaxNode;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, ANode.StartOffset));
  end;

  /// <summary>Liegt ANode in ARoot (ARoot selbst eingeschlossen)?</summary>
  function Inside(ANode, ARoot: TSyntaxNode): Boolean;
  begin
    while ANode <> nil do
    begin
      if ANode = ARoot then
      begin
        Exit(True);
      end;
      ANode := ANode.Parent;
    end;
    Result := False;
  end;

  /// <summary>Ist die Deklaration ADecl (VarDecl, Field oder RoutineHeader) am Attribut AAttribute sichtbar und
  /// wird mit ihm übersetzt? Unit-Ebene oder umgebende Routine, vor dem Attribut; Felder nicht.</summary>
  function VisibleAt(ADecl, AAttribute: TSyntaxNode): Boolean;
  var
    Holder: TSyntaxNode;
  begin
    Result := False;
    if (ADecl.StartOffset >= AAttribute.StartOffset) or (ADecl.Kind = TSyntaxKind.Field) then
    begin
      Exit;
    end;
    Holder := ADecl.Parent;
    if ADecl.Kind = TSyntaxKind.VarDecl then
    begin
      if (Holder = nil) or (Holder.Kind <> TSyntaxKind.VarSection) then
      begin
        Exit;
      end;
      Holder := Holder.Parent;
      if Holder = nil then
      begin
        Exit;
      end;
      if Holder.Kind = TSyntaxKind.RoutineDecl then
      begin
        if not Inside(AAttribute, Holder) then
        begin
          Exit;
        end;
      end
      else if not (Holder.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) then
      begin
        Exit;
      end;
    end;
    Result := TConditionalBranches.Implies(PathOf(AAttribute), PathOf(ADecl));
  end;

  /// <summary>Steht AName am Attribut sicher für eine Variable bzw. Routine der Datei?</summary>
  function CertainVariable(const AName: string; AAttribute: TSyntaxNode): Boolean;
  var
    Decls: TList<TSyntaxNode>;
    Decl: TSyntaxNode;
  begin
    Result := False;
    Decls := Names.OnlyVariables(AName);
    if Decls = nil then
    begin
      Exit;
    end;
    for Decl in Decls do
    begin
      if VisibleAt(Decl, AAttribute) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure CheckArgument(AArgument, AAttribute: TSyntaxNode; const AAttributeName: string; var AReported: Boolean);
  var
    Pending: TStack<TSyntaxNode>;
    Node, Callee: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(AArgument);
      while (Pending.Count > 0) and not AReported do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Identifier:
            if CertainVariable(Node.Name, AAttribute) then
            begin
              AReport.Add(NodeRange(Node), Format('Das Argument %s von [%s] ist kein konstanter Ausdruck; ' +
                'Attributargumente müssen Konstanten, TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).',
                [Node.Name, AAttributeName]), TRuleConfidence.High, nil);
              AReported := True;
            end;
          TSyntaxKind.Call:
            begin
              // Nur Aufrufe eigener Routinen; SizeOf, High, TypeInfo usw. sind konstant, Typumwandlungen auch.
              if Node.ChildCount = 0 then
              begin
                Continue;
              end;
              Callee := Node[0];
              if (Callee.Kind = TSyntaxKind.Identifier) and CertainVariable(Callee.Name, AAttribute) then
              begin
                AReport.Add(NodeRange(Node), Format('Der Aufruf %s in [%s] ist kein konstanter Ausdruck; ' +
                  'Attributargumente müssen Konstanten, TypeInfo-Ausdrücke oder Array-Konstruktoren sein ' +
                  '(wie E2448).', [Callee.Name, AAttributeName]), TRuleConfidence.High, nil);
                AReported := True;
              end;
            end;
          TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor,
          TSyntaxKind.IndexAccess, TSyntaxKind.RangeExpr:
            for Index := Node.ChildCount - 1 downto 0 do
            begin
              Pending.Push(Node[Index]);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CheckArguments(AAttribute: TSyntaxNode);
  var
    Index, Argument: Integer;
    Item: TSyntaxNode;
    Reported: Boolean;
  begin
    for Index := 0 to AAttribute.ChildCount - 1 do
    begin
      Item := AAttribute[Index];
      if Item.Kind <> TSyntaxKind.Call then
      begin
        Continue;
      end;
      Reported := False;
      for Argument := 1 to Item.ChildCount - 1 do
      begin
        CheckArgument(Item[Argument], AAttribute, DottedNameOf(Item[0]), Reported);
      end;
    end;
  end;

  /// <summary>Alle Attribut-Knoten vor dem Ziel, zu dem AAttribute gehört (ohne Parameter: nur AAttribute).</summary>
  function AttributeGroup(AAttribute: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Parent: TSyntaxNode;
    Index: Integer;
  begin
    Result := [AAttribute];
    Parent := AAttribute.Parent;
    if (Parent = nil) or (Parent.Kind = TSyntaxKind.Parameter) then
    begin
      Result := nil;
      if Parent <> nil then
      begin
        for Index := 0 to Parent.ChildCount - 1 do
        begin
          if Parent[Index].Kind = TSyntaxKind.Attribute then
          begin
            Result := Result + [Parent[Index]];
          end;
        end;
      end;
      Exit;
    end;
    Index := 0;
    while (Index < Parent.ChildCount) and (Parent[Index] <> AAttribute) do
    begin
      Inc(Index);
    end;
    while (Index + 1 < Parent.ChildCount) and (Parent[Index + 1].Kind = TSyntaxKind.Attribute) do
    begin
      Inc(Index);
      Result := Result + [Parent[Index]];
    end;
  end;

  /// <summary>Ist AAttribute das erste Attribut vor seinem Ziel?</summary>
  function FirstOfGroup(AAttribute: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
    Index: Integer;
  begin
    Parent := AAttribute.Parent;
    if Parent = nil then
    begin
      Exit(False);
    end;
    for Index := 0 to Parent.ChildCount - 1 do
    begin
      if Parent[Index] = AAttribute then
      begin
        Exit((Index = 0) or (Parent[Index - 1].Kind <> TSyntaxKind.Attribute));
      end;
    end;
    Result := False;
  end;

  procedure CheckWeakTarget(AItem, ATarget: TSyntaxNode);
  var
    Child: Integer;
    TypeNode: TSyntaxNode;
  begin
    if not (ATarget.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl]) then
    begin
      Exit;
    end;
    TypeNode := nil;
    for Child := 0 to ATarget.ChildCount - 1 do
    begin
      if ATarget[Child].Kind <> TSyntaxKind.Attribute then
      begin
        TypeNode := ATarget[Child];
        Break;
      end;
    end;
    if (TypeNode = nil) or not CertainlyNoReference(Types, TypeNode) then
    begin
      Exit;
    end;
    AReport.Add(NodeRange(AItem), Format('[Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; %s hat ' +
      'den Typ %s (wie E2584).', [Trim(ATarget.Name), OneLine(AContext.Text, TypeNode)]), TRuleConfidence.High,
      nil);
  end;

  procedure CheckTarget(AFirst: TSyntaxNode);
  var
    Group: TArray<TSyntaxNode>;
    Items: TArray<TSyntaxNode>;
    ItemNames: TArray<string>;
    Attribute, Target, Item: TSyntaxNode;
    Index, Other: Integer;
    Name: string;
    Duplicate: Boolean;
  begin
    Target := AttributeTarget(AFirst);
    if Target = nil then
    begin
      Exit;
    end;
    Group := AttributeGroup(AFirst);
    Items := nil;
    ItemNames := nil;
    for Attribute in Group do
    begin
      for Index := 0 to Attribute.ChildCount - 1 do
      begin
        Items := Items + [Attribute[Index]];
        ItemNames := ItemNames + [CompilerAttribute(Types, Attribute[Index])];
      end;
    end;
    for Index := 0 to High(Items) do
    begin
      Name := ItemNames[Index];
      if Name = '' then
      begin
        Continue;
      end;
      Item := Items[Index];
      Duplicate := False;
      for Other := 0 to Index - 1 do
      begin
        if SameText(ItemNames[Other], Name) and
          not TConditionalBranches.Exclusive(PathOf(Items[Other]), PathOf(Item)) then
        begin
          Duplicate := True;
        end;
      end;
      if Duplicate then
      begin
        AReport.Add(NodeRange(Item), Format('[%s] steht mehrfach an derselben Deklaration; ein Attribut des ' +
          'Compilers darf je Ziel nur einmal stehen (wie E2326).', [Name]), TRuleConfidence.High, nil);
        Continue;
      end;
      if SameText(Name, 'Volatile') and (Target.Kind in VolatileForbiddenTargets) then
      begin
        AReport.Add(NodeRange(Item), '[Volatile] gilt nur für Variablen, Parameter und Felder, nicht für Typen, ' +
          'Routinen, Methoden oder Properties (wie E2325).', TRuleConfidence.High, nil);
      end
      else if SameText(Name, 'Weak') then
      begin
        CheckWeakTarget(Item, Target);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos('[', AContext.Text) = 0) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TFileTypes.Collect(AContext.Tree.Root);
  Paths := TConditionalBranches.Paths(Tokens);
  Names := nil;
  Attributes := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind = TSyntaxKind.Attribute then
        begin
          Attributes.Add(ANode);
        end;
      end);
    if Attributes.Count = 0 then
    begin
      Exit;
    end;
    Names := TDeclarationNames.Create(AContext.Tree.Root);
    for Node in Attributes do
    begin
      CheckArguments(Node);
      if FirstOfGroup(Node) then
      begin
        CheckTarget(Node);
      end;
    end;
  finally
    Names.Free;
    Attributes.Free;
  end;
end;

end.
