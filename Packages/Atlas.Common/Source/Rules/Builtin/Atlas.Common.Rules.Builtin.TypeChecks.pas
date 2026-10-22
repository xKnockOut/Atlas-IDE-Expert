unit Atlas.Common.Rules.Builtin.TypeChecks;

// Compilerfehler aus Typen von Ausdrücken schon beim Tippen (Gruppe „Compiler
// vorab“, #1024). Gemeldet wird nur, was die Namensauflösung sicher findet:
//   dynamic-array-misuse
//                     New (wie E2255) oder Dispose (wie E2256) auf einem
//                     dynamischen Array, SetLength ohne Länge (wie E2246), New
//                     mit Länge auf einem Typ, der kein dynamisches Array ist
//                     (wie E2307), und New(TArrayTyp) ohne Länge (wie E2308)
//                     (#1038). Korrekturen: Dispose(A) wird A := nil, New(A)
//                     wird SetLength(A, 1).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  DynamicArrayMisuseRuleId = 'dynamic-array-misuse';

type
  TDynamicArrayMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeCheckRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

const
  // Dynamische Arrays der RTL, auch wenn ihre Unit nicht im Index steht.
  RtlDynamicArrays: array[0..9] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
    'TObjectDynArray', 'TWordDynArray', 'TCardinalDynArray', 'TInt64DynArray', 'TDoubleDynArray',
    'TBooleanDynArray');
  MaxAliasDepth = 16;

/// <summary>Dateiname für die Namensauflösung wie in den übrigen Regeln.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
    Result := AContext.RelativePath;
  if Result = '' then
    Result := AContext.UnitName + '.pas';
end;

function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
begin
  Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Typtext ohne Leerzeichen vor spitzen Klammern ("TArray <Integer>" aus dem Index).</summary>
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
      Exit(Trim(Copy(AText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset)));
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
    Exit;
  Pending := TStack<TSyntaxNode>.Create;
  Nodes := TList<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Nodes.Add(Node);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
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
    if (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field, TSyntaxKind.TypeDecl,
      TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar]) and Covers(Node, APosition) then
      Result := Node;
end;

/// <summary>Deklarierter Typ von ASymbol als Quelltext ("TArray<Double>", "array of Integer"); bei Aliasen
/// der Typ hinter "=". Aus TypeName, sonst aus dem Kopf des Index, sonst aus der Deklaration im Baum (lokale
/// Namen). '' wenn unbekannt.</summary>
function DeclaredTypeText(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
var
  Signature: string;
  Index, Depth: Integer;
  Decl: TSyntaxNode;
begin
  if ASymbol.TypeName <> '' then
  begin
    Result := ASymbol.TypeName;
    if ASymbol.TypeArgs <> '' then
      Result := Result + '<' + ASymbol.TypeArgs + '>';
    Exit(NormalizedType(Result));
  end;
  Result := '';
  Signature := ASymbol.Signature;
  if Signature <> '' then
  begin
    // "Werte: array of Double" bzw. "TWerte = array of Double": der Teil hinter ':' bzw. '=' auf oberster Ebene.
    Depth := 0;
    for Index := 1 to Length(Signature) do
      case Signature[Index] of
        '(', '[', '<':
          Inc(Depth);
        ')', ']', '>':
          Dec(Depth);
        ':', '=':
          if Depth = 0 then
          begin
            Result := Copy(Signature, Index + 1, MaxInt);
            if Pos(';', Result) > 0 then
              Result := Copy(Result, 1, Pos(';', Result) - 1);
            Exit(NormalizedType(Result));
          end;
      end;
    Exit;
  end;
  if (ASymbol.Kind = TResolvedKind.Local) and (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    Decl := DeclarationAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
    if Decl <> nil then
      Result := NormalizedType(NodeTypeText(AContext.Text, Decl));
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
      Exit(True);
    if (Name = '') or (Pos(' ', Name) > 0) or (Pos('<', Name) > 0) or (Pos('^', Name) > 0) then
      Exit(False);
    if not AResolver.ResolveTypeFrom(FromUnit, Name, Current) then
      // Ohne Deklaration im Index: nur die bekannten Arrays der RTL.
      Exit(MatchText(Name, RtlDynamicArrays) or MatchText(Copy(Name, LastDelimiter('.', Name) + 1, MaxInt),
        RtlDynamicArrays));
    if Current.Builtin or (Current.SymbolKind <> TIndexSymbolKind.TypeAlias) or
      not AResolver.DeclaringUnit(Current, FromUnit) then
      Exit(False);
    Name := DeclaredTypeText(AContext, Current);
  end;
  Result := False;
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
    Exit;
  if not AResolver.NodeType(AContext.Tree, AFileName, ACallee, Symbol, TypeInfo, TypeFound) then
    Exit(True);
  Result := Symbol.Builtin or SameText(Symbol.UnitName, 'System');
end;

{ TDynamicArrayMisuseRule }

function TDynamicArrayMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DynamicArrayMisuseRuleId, TRuleSeverity.Error,
    'New, Dispose oder SetLength falsch für dynamische Arrays');
end;

procedure TDynamicArrayMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName: string;
  Local: TUnitIndex;
  Node: TSyntaxNode;

  /// <summary>Variable, Feld oder Parameter mit dynamischem Array als Typ? Offene Array-Parameter (array of
  /// T als Parametertyp) sind keine dynamischen Arrays.</summary>
  function IsArrayVariable(ANode: TSyntaxNode): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    FromUnit: TUnitIndex;
    TypeText: string;
  begin
    Result := False;
    if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
      Exit;
    TypeText := DeclaredTypeText(AContext, Symbol);
    if (Symbol.IsParameter and StartsText('array of', TypeText)) or
      not SymbolUnit(Resolver, Local, Symbol, FromUnit) then
      Exit;
    Result := IsDynamicArrayType(Resolver, AContext, FromUnit, TypeText);
  end;

  /// <summary>Ist ANode ein Typbezeichner? ADynamic: ein dynamisches Array; AOther: sicher keins (Klasse,
  /// Record, Aufzählung, Interface oder eingebauter Wert-Typ).</summary>
  function TypeIdentifier(ANode: TSyntaxNode; out ADynamic, AOther: Boolean): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    FromUnit: TUnitIndex;
  begin
    ADynamic := False;
    AOther := False;
    Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) and Symbol.IsType;
    if not Result then
      Exit;
    if Symbol.Builtin then
    begin
      AOther := not MatchText(Symbol.Name, ['Pointer', 'PChar', 'PWideChar', 'PAnsiChar']);
      Exit;
    end;
    if Symbol.SymbolKind = TIndexSymbolKind.TypeAlias then
    begin
      ADynamic := SymbolUnit(Resolver, Local, Symbol, FromUnit) and
        IsDynamicArrayType(Resolver, AContext, FromUnit, Symbol.Name);
      Exit;
    end;
    AOther := Symbol.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.EnumType, TIndexSymbolKind.InterfaceType];
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    Callee, Target: TSyntaxNode;
    ArgCount: Integer;
    Dynamic, Other: Boolean;
    TargetText: string;
    Fixes: TArray<TRuleFix>;
    InStatement: Boolean;
  begin
    if ACall.ChildCount < 2 then
      Exit;
    Callee := ACall[0];
    Target := ACall[1];
    ArgCount := ACall.ChildCount - 1;
    TargetText := NodeText(AContext, Target);
    InStatement := (ACall.Parent <> nil) and (ACall.Parent.Kind = TSyntaxKind.CallStatement) and
      (ACall.Parent.ChildCount = 1);
    if IsIntrinsicCall(Resolver, AContext, FileName, Callee, 'Dispose') then
    begin
      if (ArgCount = 1) and IsArrayVariable(Target) then
      begin
        Fixes := nil;
        if InStatement then
          Fixes := [TRuleFix.Create(Format('%s := nil', [TargetText]), [TTextEdit.Create(TTextRange.Create(
            ACall.StartPos, ACall.EndPos), TargetText + ' := nil')])];
        AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
          'Dispose ist für dynamische Arrays nicht erlaubt und nicht nötig (wie E2256).', TRuleConfidence.High,
          Fixes);
      end;
    end
    else if IsIntrinsicCall(Resolver, AContext, FileName, Callee, 'SetLength') then
    begin
      if (ArgCount = 1) and IsArrayVariable(Target) then
        AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
          Format('SetLength braucht für das dynamische Array %s mindestens eine Länge (wie E2246).', [TargetText]),
          TRuleConfidence.High);
    end
    else if IsIntrinsicCall(Resolver, AContext, FileName, Callee, 'New') then
    begin
      if TypeIdentifier(Target, Dynamic, Other) then
      begin
        if (ArgCount = 1) and Dynamic then
          AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
            Format('New für das dynamische Array %s braucht mindestens eine Länge (wie E2308).', [TargetText]),
            TRuleConfidence.High)
        else if (ArgCount > 1) and Other then
          AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
            Format('New mit Länge erwartet den Typ eines dynamischen Arrays; %s ist keiner (wie E2307).',
            [TargetText]), TRuleConfidence.High);
      end
      else if (ArgCount = 1) and IsArrayVariable(Target) then
      begin
        Fixes := nil;
        if InStatement then
          Fixes := [TRuleFix.Create(Format('SetLength(%s, 1)', [TargetText]), [TTextEdit.Create(
            TTextRange.Create(ACall.StartPos, ACall.EndPos), Format('SetLength(%s, 1)', [TargetText]))])];
        AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
          'New ist für dynamische Arrays nicht erlaubt; die Länge setzt SetLength (wie E2255).',
          TRuleConfidence.High, Fixes);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  // Vorfilter: ohne New, Dispose oder SetLength im Text keine Namensauflösung.
  if not ContainsText(AContext.Text, 'New') and not ContainsText(AContext.Text, 'Dispose') and
    not ContainsText(AContext.Text, 'SetLength') then
    Exit;
  FileName := ResolverFileName(AContext);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
      for Node in PreOrder(AContext.Tree.Root) do
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and
          MatchText(Node[0].Name, ['New', 'Dispose', 'SetLength']) then
          CheckCall(Node);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterTypeCheckRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDynamicArrayMisuseRule.Create);
end;

end.
