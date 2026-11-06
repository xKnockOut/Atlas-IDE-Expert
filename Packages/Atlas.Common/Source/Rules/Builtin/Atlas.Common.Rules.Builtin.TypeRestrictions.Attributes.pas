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
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeRestrictionsAttributesText = (Title, ArgumentNotConst, CallNotConst, WeakType, VolatileTarget, Duplicate);

const
  cTexts: array[TTypeRestrictionsAttributesText] of TAtlasText = (
    (De: 'Attribut falsch verwendet'; En: 'Attribute used incorrectly'),
    (De: 'Das Argument %s von [%s] ist kein konstanter Ausdruck; Attributargumente müssen Konstanten, ' +
      'TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).';
     En: 'The argument %s of [%s] is not a constant expression; attribute arguments must be constants, TypeInfo ' +
      'expressions or array constructors (like E2448).'),
    (De: 'Der Aufruf %s in [%s] ist kein konstanter Ausdruck; Attributargumente müssen Konstanten, ' +
      'TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).';
     En: 'The call %s in [%s] is not a constant expression; attribute arguments must be constants, TypeInfo ' +
      'expressions or array constructors (like E2448).'),
    (De: '[Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; %s hat den Typ %s (wie E2584).';
     En: '[Weak] is only allowed on class and interface references; %s has the type %s (like E2584).'),
    (De: '[Volatile] gilt nur für Variablen, Parameter und Felder, nicht für Typen, Routinen, Methoden oder ' +
      'Properties (wie E2325).';
     En: '[Volatile] applies only to variables, parameters and fields, not to types, routines, methods or properties ' +
      '(like E2325).'),
    (De: '[%s] steht mehrfach an derselben Deklaration; ein Attribut des Compilers darf je Ziel nur einmal stehen ' +
      '(wie E2326).';
     En: '[%s] occurs several times on the same declaration; a compiler attribute may occur only once per target ' +
      '(like E2326).'));

{$SCOPEDENUMS OFF}

{ TAttributeUsageInvalidRule }

const
  // Attribute des Compilers, die er selbst prüft (System.WeakAttribute …).
  CompilerCheckedAttributes: array[0..3] of string = ('Weak', 'Unsafe', 'Volatile', 'Ref');
  // Typarten, die sicher weder Klasse noch Interface sind (E2584). ProcedureType fehlt: reference to ist ein
  // Interface.
  NonReferenceTypeKinds = [TSyntaxKind.RecordType, TSyntaxKind.EnumType, TSyntaxKind.SetType, TSyntaxKind.ArrayType,
    TSyntaxKind.PointerType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType];
  // Ziele, an denen Volatile nicht stehen darf (Compiler Attributes: keine Typen, Routinen, Methoden).
  // Längste verfolgte Alias-Kette.
  cMaxAliasDepth = 16;
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
type
  /// <summary>Ergebnis eines Schritts entlang einer Alias-Kette: sicher kein Referenztyp, offen bzw. Referenz, oder
  /// dem neuen Namen weiter folgen.</summary>
  TAliasStep = (NoReference, Unknown, Follow);

/// <summary>Ein Schritt von AName entlang der Aliase der Datei; bei Follow steht in AName das Ziel.</summary>
function AliasStep(const ATypes: TFileTypes; var AName: string): TAliasStep;
var
  mIndex: Integer;
begin
  Result := TAliasStep.Unknown;
  if (AName = '') or (Pos('.', AName) > 0) or (Pos('<', AName) > 0) then
  begin
    Exit;
  end;
  if ATypes.DeclaredKind(AName) in NonReferenceTypeKinds then
  begin
    Exit(TAliasStep.NoReference);
  end;
  mIndex := ATypes.IndexOf(AName);
  if mIndex < 0 then
  begin
    // Pointer bleibt außen vor: die Hilfe nennt nur Klassen und Interfaces, der Fall ist nicht abgeglichen.
    if not SameText(AName, 'Pointer') and (MatchText(AName, BuiltinTypeNames) or
      MatchText(AName, BooleanTypeNames)) then
    begin
      Result := TAliasStep.NoReference;
    end;
  end
  else if ATypes.AliasOf[mIndex] <> '' then
  begin
    AName := ATypes.AliasOf[mIndex];
    Result := TAliasStep.Follow;
  end
  else if ATypes.Types[mIndex].Kind = TSyntaxKind.TypeReference then
  begin
    AName := ATypes.Types[mIndex].Name;
    Result := TAliasStep.Follow;
  end;
end;

function CertainlyNoReference(const ATypes: TFileTypes; AType: TSyntaxNode): Boolean;
var
  mName: string;
  mDepth: Integer;
begin
  Result := AType.Kind in NonReferenceTypeKinds;
  if Result or (AType.Kind <> TSyntaxKind.TypeReference) or (AType.FindChild(TSyntaxKind.GenericArgs) <> nil) then
  begin
    Exit;
  end;
  mName := AType.Name;
  for mDepth := 1 to cMaxAliasDepth do
  begin
    case AliasStep(ATypes, mName) of
      TAliasStep.NoReference:
        Exit(True);
      TAliasStep.Unknown:
        Exit(False);
    else
      // Follow: dem Alias weiter folgen.
    end;
  end;
end;

function TAttributeUsageInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AttributeUsageInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeRestrictionsAttributesText.Title].Text);
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

  /// <summary>Ist der var-Abschnitt ASection am Attribut sichtbar? Unit-Ebene oder umgebende Routine.</summary>
  function VarSectionVisible(ASection, AAttribute: TSyntaxNode): Boolean;
  var
    Holder: TSyntaxNode;
  begin
    Result := False;
    if (ASection = nil) or (ASection.Kind <> TSyntaxKind.VarSection) or (ASection.Parent = nil) then
    begin
      Exit;
    end;
    Holder := ASection.Parent;
    if Holder.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Inside(AAttribute, Holder);
    end
    else
    begin
      Result := Holder.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection];
    end;
  end;

  /// <summary>Ist die Deklaration ADecl (VarDecl, Field oder RoutineHeader) am Attribut AAttribute sichtbar und
  /// wird mit ihm übersetzt? Unit-Ebene oder umgebende Routine, vor dem Attribut; Felder nicht.</summary>
  function VisibleAt(ADecl, AAttribute: TSyntaxNode): Boolean;
  begin
    Result := (ADecl.StartOffset < AAttribute.StartOffset) and (ADecl.Kind <> TSyntaxKind.Field);
    if Result and (ADecl.Kind = TSyntaxKind.VarDecl) then
    begin
      Result := VarSectionVisible(ADecl.Parent, AAttribute);
    end;
    Result := Result and TConditionalBranches.Implies(PathOf(AAttribute), PathOf(ADecl));
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

  /// <summary>Meldet ANode, wenn es eine Variable oder der Aufruf einer eigenen Routine ist; True nach einer
  /// Meldung.</summary>
  function ReportNonConstant(ANode, AAttribute: TSyntaxNode; const AAttributeName: string): Boolean;
  var
    Callee: TSyntaxNode;
  begin
    Result := False;
    if ANode.Kind = TSyntaxKind.Identifier then
    begin
      Result := CertainVariable(ANode.Name, AAttribute);
      if Result then
      begin
        AReport.Add(NodeRange(ANode), cTexts[TTypeRestrictionsAttributesText.ArgumentNotConst].Fmt(
          [ANode.Name, AAttributeName]), TRuleConfidence.High, nil);
      end;
      Exit;
    end;
    // Nur Aufrufe eigener Routinen; SizeOf, High, TypeInfo usw. sind konstant, Typumwandlungen auch.
    if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount = 0) then
    begin
      Exit;
    end;
    Callee := ANode[0];
    Result := (Callee.Kind = TSyntaxKind.Identifier) and CertainVariable(Callee.Name, AAttribute);
    if Result then
    begin
      AReport.Add(NodeRange(ANode), cTexts[TTypeRestrictionsAttributesText.CallNotConst].Fmt([Callee.Name,
        AAttributeName]), TRuleConfidence.High, nil);
    end;
  end;

  // Iterativ (Bericht M1).
  procedure CheckArgument(AArgument, AAttribute: TSyntaxNode; const AAttributeName: string; var AReported: Boolean);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(AArgument);
      while (Pending.Count > 0) and not AReported do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Identifier, TSyntaxKind.Call:
            AReported := ReportNonConstant(Node, AAttribute, AAttributeName);
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
    AReport.Add(NodeRange(AItem), cTexts[TTypeRestrictionsAttributesText.WeakType].Fmt([Trim(ATarget.Name),
      OneLine(AContext.Text, TypeNode)]), TRuleConfidence.High,
      nil);
  end;

  /// <summary>Steht das Compiler-Attribut AItemNames[AIndex] schon weiter vorn in derselben Bedingungsvariante?
  /// </summary>
  function IsDuplicate(const AItems: TArray<TSyntaxNode>; const AItemNames: TArray<string>; AIndex: Integer):
    Boolean;
  var
    Other: Integer;
  begin
    Result := False;
    for Other := 0 to AIndex - 1 do
    begin
      if SameText(AItemNames[Other], AItemNames[AIndex]) and
        not TConditionalBranches.Exclusive(PathOf(AItems[Other]), PathOf(AItems[AIndex])) then
      begin
        Exit(True);
      end;
    end;
  end;

  procedure CheckItem(AItem, ATarget: TSyntaxNode; const AName: string);
  begin
    if SameText(AName, 'Volatile') and (ATarget.Kind in VolatileForbiddenTargets) then
    begin
      AReport.Add(NodeRange(AItem), cTexts[TTypeRestrictionsAttributesText.VolatileTarget].Text, TRuleConfidence.High,
        nil);
    end
    else if SameText(AName, 'Weak') then
    begin
      CheckWeakTarget(AItem, ATarget);
    end;
  end;

  procedure CheckTarget(AFirst: TSyntaxNode);
  var
    Items: TArray<TSyntaxNode>;
    ItemNames: TArray<string>;
    Attribute, Target: TSyntaxNode;
    Index: Integer;
  begin
    Target := AttributeTarget(AFirst);
    if Target = nil then
    begin
      Exit;
    end;
    Items := nil;
    for Attribute in AttributeGroup(AFirst) do
    begin
      for Index := 0 to Attribute.ChildCount - 1 do
      begin
        Items := Items + [Attribute[Index]];
      end;
    end;
    SetLength(ItemNames, Length(Items));
    for Index := 0 to High(Items) do
    begin
      ItemNames[Index] := CompilerAttribute(Types, Items[Index]);
    end;
    for Index := 0 to High(Items) do
    begin
      if ItemNames[Index] = '' then
      begin
        Continue;
      end;
      if IsDuplicate(Items, ItemNames, Index) then
      begin
        AReport.Add(NodeRange(Items[Index]), cTexts[TTypeRestrictionsAttributesText.Duplicate].Fmt([ItemNames[Index]]),
          TRuleConfidence.High,
          nil);
      end
      else
      begin
        CheckItem(Items[Index], Target, ItemNames[Index]);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeRestrictions.Attributes', cTexts);

end.
