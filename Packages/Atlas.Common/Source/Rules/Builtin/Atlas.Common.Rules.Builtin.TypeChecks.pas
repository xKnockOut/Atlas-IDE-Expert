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
//   local-routine-as-callback
//                     Eine lokale (verschachtelte) Routine wird einer Variablen
//                     bzw. einem Parameter eines prozeduralen Typs ohne of object
//                     zugewiesen (wie E2094), oder ihre bzw. die Adresse einer
//                     lokalen Variablen steht in einer typisierten Konstante der
//                     Routine (wie E2278) (#1039). Gemeldet nur, wenn der Zieltyp
//                     sicher ein solcher Typ ist (Methodenzeiger und anonyme
//                     Methoden meldet der Compiler anders). Korrektur: die Routine
//                     als Routine der Unit vor die umgebende Routine verschieben,
//                     wenn sie nichts aus ihr nutzt.
//   hresult-integer-mix
//                     Eine Klasse der Datei implementiert eine Interface-Methode
//                     mit HRESULT-Ergebnis über eine Methode mit Integer-Ergebnis
//                     oder umgekehrt (wie X1008, #1040). Zugeordnet wird über
//                     Name und Parametertypen samt Zuordnungen "IFoo.Bar = Baz";
//                     Interfaces samt ihren Vorfahren kommen aus Datei bzw. Index.
//                     Stehen Varianten in bedingten Zweigen, meldet die Regel nur,
//                     wenn jede Variante abweicht. Korrektur: den Ergebnistyp in
//                     Deklaration und Rumpf an das Interface angleichen.
//   invalid-var-argument
//                     An einen var- oder out-Parameter geht ein String-Element an
//                     einen Zeichen-Parameter (wie E2354), eine Konstante, ein
//                     const-Parameter, eine Property oder ein Funktionsergebnis
//                     (wie E2197), eine Konstante an ein offenes Array (wie
//                     E2192), Slice (wie E2454) oder ein Ausdruck (wie E2036)
//                     (#1037). Nur bei eindeutiger Routine ohne Überladungen und
//                     ohne eingebaute Routinen (Inc, Move ... nehmen mehr an).
//                     Korrektur: über eine lokale Variable übergeben, bei
//                     String-Elementen und Properties mit write mit Rückschreiben.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  DynamicArrayMisuseRuleId = 'dynamic-array-misuse';
  LocalRoutineAsCallbackRuleId = 'local-routine-as-callback';
  HresultIntegerMixRuleId = 'hresult-integer-mix';
  InvalidVarArgumentRuleId = 'invalid-var-argument';

type
  TDynamicArrayMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLocalRoutineAsCallbackRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THresultIntegerMixRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist das eine Ergebnis HRESULT und das andere Integer (bzw. LongInt)?</summary>
    class function Interchanged(const AExpected, AActual: string): Boolean; static;
  end;

  TInvalidVarArgumentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeCheckRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Text.Lines;

const
  // Dynamische Arrays der RTL, auch wenn ihre Unit nicht im Index steht.
  RtlDynamicArrays: array[0..9] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
    'TObjectDynArray', 'TWordDynArray', 'TCardinalDynArray', 'TInt64DynArray', 'TDoubleDynArray',
    'TBooleanDynArray');
  MaxAliasDepth = 16;
  // Prozedurale Typen der RTL ohne of object, auch wenn ihre Unit nicht im Index steht.
  RtlPlainProcedureTypes: array[0..3] of string = ('TListSortCompare', 'TStringListSortCompare',
    'TThreadFunc', 'TFarProc');

type
  /// <summary>Art eines unzulässigen Arguments für einen var- bzw. out-Parameter (invalid-var-argument).</summary>
  TVarArgumentKind = (None, StringElement, ConstantObject, OpenArrayConstant, SliceCall, Expression);

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
      Exit(not ContainsText(Name, ' of object'));
    if (Name = '') or (Pos(' ', Name) > 0) or (Pos('<', Name) > 0) or (Pos('^', Name) > 0) then
      Exit(False);
    if not AResolver.ResolveTypeFrom(FromUnit, Name, Current) then
      Exit(MatchText(Copy(Name, LastDelimiter('.', Name) + 1, MaxInt), RtlPlainProcedureTypes));
    if Current.Builtin or (Current.SymbolKind <> TIndexSymbolKind.TypeAlias) or
      not AResolver.DeclaringUnit(Current, FromUnit) then
      Exit(False);
    Name := DeclaredTypeText(AContext, Current);
  end;
  Result := False;
end;

/// <summary>Parameter der Routine ASymbol in Reihenfolge, je Name ein Eintrag: aus dem Kopf im Index bzw. für
/// lokale Routinen aus dem Baum. False bei Überladungen (auch mit overload im Kopf) oder unbekanntem Kopf.
/// </summary>
function RoutineParams(const AContext: TRuleContext; const ASymbol: TResolvedSymbol;
  out AParams: TArray<TSignatureParameter>): Boolean;
var
  Signature: string;
  Open, Close, Depth, Index: Integer;
  Header, Parameters, Node: TSyntaxNode;
  Name: string;
  Parameter: TSignatureParameter;
begin
  AParams := nil;
  Result := False;
  if (Length(ASymbol.Overloads) > 0) or (Length(ASymbol.VariantParams) > 1) then
    Exit;
  Signature := ASymbol.Signature;
  if Signature <> '' then
  begin
    Open := Pos('(', Signature);
    Close := 0;
    if Open > 0 then
    begin
      Depth := 0;
      for Index := Open to Length(Signature) do
        if Signature[Index] = '(' then
          Inc(Depth)
        else if Signature[Index] = ')' then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Close := Index;
            Break;
          end;
        end;
      // Überladungen aus anderen Units kennt die Namensauflösung nicht immer (Overloads leer); die Direktive
      // im Kopf zeigt sie sicher an.
      if (Close = 0) or MatchText('overload', SplitString(LowerCase(Copy(Signature, Close + 1, MaxInt)), ' ;')) then
        Exit;
      AParams := TChangeSignature.ParseParameters(Copy(Signature, Open + 1, Close - Open - 1));
    end;
    Exit(True);
  end;
  if (ASymbol.Kind <> TResolvedKind.Local) or (AContext.Tree = nil) then
    Exit;
  Header := nil;
  for Node in PreOrder(AContext.Tree.Root) do
    if (Node.Kind = TSyntaxKind.RoutineHeader) and Covers(Node, ASymbol.SelectionRange.StartPos) then
      Header := Node;
  if Header = nil then
    Exit;
  Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
    for Index := 0 to Parameters.ChildCount - 1 do
    begin
      Node := Parameters[Index];
      if Node.Kind <> TSyntaxKind.Parameter then
        Continue;
      for Name in Node.Name.Split([',']) do
      begin
        Parameter := Default(TSignatureParameter);
        Parameter.Name := Trim(Name);
        Parameter.Group := Index;
        Parameter.TypeName := NodeTypeText(AContext.Text, Node);
        case Node.Modifier of
          TParameterModifier.ConstParam:
            Parameter.Modifier := 'const';
          TParameterModifier.VarParam:
            Parameter.Modifier := 'var';
          TParameterModifier.OutParam:
            Parameter.Modifier := 'out';
          TParameterModifier.ConstRefParam:
            Parameter.Modifier := 'constref';
        end;
        AParams := AParams + [Parameter];
      end;
    end;
  Result := True;
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

{ TLocalRoutineAsCallbackRule }

function TLocalRoutineAsCallbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LocalRoutineAsCallbackRuleId, TRuleSeverity.Error,
    'Lokale Routine als Prozedurvariable');
end;

procedure TLocalRoutineAsCallbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName, LineBreak: string;
  Local: TUnitIndex;
  Nodes: TArray<TSyntaxNode>;
  Nested: TList<TSyntaxNode>;
  Names: TStringList;
  Lines: TArray<string>;
  Node, Parent: TSyntaxNode;
  HasConstants: Boolean;

  function OuterRoutine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
      Result := Result.Parent;
  end;

  /// <summary>Verschachtelte Routine, deren Kopf ASymbol deklariert; nil, wenn ASymbol keine ist.</summary>
  function NestedOf(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    Candidate, Header: TSyntaxNode;
  begin
    Result := nil;
    if (ASymbol.Kind <> TResolvedKind.Local) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) then
      Exit;
    for Candidate in Nested do
    begin
      Header := Candidate.FindChild(TSyntaxKind.RoutineHeader);
      if (Header <> nil) and Covers(Header, ASymbol.SelectionRange.StartPos) then
        Exit(Candidate);
    end;
  end;

  /// <summary>Typ des Ziels ATarget einer Zuweisung als Text samt Unit.</summary>
  function TargetType(ATarget: TSyntaxNode; out AText: string; out AUnit: TUnitIndex): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ATarget, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
      SymbolUnit(Resolver, Local, Symbol, AUnit);
    if Result then
      AText := DeclaredTypeText(AContext, Symbol);
  end;

  /// <summary>Typ des Parameters an Stelle AArgument (0 = erstes Argument) des Aufrufs ACall.</summary>
  function ParameterType(ACall: TSyntaxNode; AArgument: Integer; out AText: string; out AUnit: TUnitIndex): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Params: TArray<TSignatureParameter>;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ACall, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) and
      RoutineParams(AContext, Symbol, Params) and (AArgument < Length(Params)) and
      SymbolUnit(Resolver, Local, Symbol, AUnit);
    if Result then
      AText := Params[AArgument].TypeName;
  end;

  /// <summary>Nutzt ARoutine nur eigene Namen und Namen außerhalb der umgebenden Routine (keine Mitglieder
  /// der Klasse ohne Präfix, keine lokalen Namen weiter außen)? Dann darf sie auf Unit-Ebene stehen.</summary>
  function SelfContained(ARoutine: TSyntaxNode): Boolean;
  var
    Inner: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    for Inner in PreOrder(ARoutine) do
    begin
      if (Inner.Kind <> TSyntaxKind.Identifier) or ((Inner.Parent <> nil) and
        (Inner.Parent.Kind = TSyntaxKind.MemberAccess) and (Inner.Parent.ChildCount > 0) and
        (Inner.Parent[0] <> Inner)) then
        Continue;
      if not Resolver.NodeType(AContext.Tree, FileName, Inner, Symbol, TypeInfo, TypeFound) then
      begin
        if TSystemIntrinsics.IsKnown(Inner.Name) then
          Continue;
        Exit(False);
      end;
      if Symbol.Kind = TResolvedKind.Local then
      begin
        if not Covers(ARoutine, Symbol.SelectionRange.StartPos) then
          Exit(False);
      end
      else if (Symbol.Kind = TResolvedKind.Symbol) and (Symbol.Container <> '') and not Symbol.IsType then
        Exit(False);
    end;
    Result := True;
  end;

  /// <summary>Korrektur: ARoutine als Routine der Unit direkt vor die umgebende Routine stellen.</summary>
  function MoveFix(ARoutine: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Outer: TSyntaxNode;
    First, Last, Line: Integer;
    Indent, Text: string;
  begin
    Result := False;
    Outer := OuterRoutine(ARoutine);
    // Nur eine Ebene tief: Bei tieferer Schachtelung bräuchte die mittlere Routine sie weiter.
    if (Outer = nil) or (OuterRoutine(Outer) <> nil) or not SelfContained(ARoutine) then
      Exit;
    First := ARoutine.StartPos.Line;
    Last := ARoutine.EndPos.Line;
    if (Last > High(Lines)) or (Trim(Copy(Lines[First], 1, ARoutine.StartPos.Character)) <> '') or
      (Trim(Copy(Lines[Last], ARoutine.EndPos.Character + 1, MaxInt)) <> '') then
      Exit;
    Indent := TTextLines.IndentOf(Lines[First]);
    Text := '';
    for Line := First to Last do
      if StartsStr(Indent, Lines[Line]) then
        Text := Text + Copy(Lines[Line], Length(Indent) + 1, MaxInt) + LineBreak
      else
        Text := Text + TrimLeft(Lines[Line]) + LineBreak;
    AFix := TRuleFix.Create(Format('%s als Routine der Unit auslagern', [ARoutine.Name]), [
      TTextEdit.Create(TTextRange.Create(Outer.StartPos.Line, 0, Outer.StartPos.Line, 0), Text + LineBreak),
      TTextEdit.Create(TTextRange.Create(First, 0, Last + 1, 0), '')]);
    Result := True;
  end;

  procedure Report(AName: TSyntaxNode; ARoutine: TSyntaxNode; AAssigned: Boolean);
  var
    Kind, Message: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
    Header: TSyntaxNode;
  begin
    Kind := 'Prozedur';
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header <> nil) and StartsText('function', Trim(NodeText(AContext, Header))) then
      Kind := 'Funktion';
    if AAssigned then
      Message := Format('Die lokale %s %s kann keiner Prozedurvariablen zugewiesen werden (wie E2094).',
        [Kind, ARoutine.Name])
    else
      Message := Format('Die lokale %s %s kann nicht als Prozedurvariable übergeben werden (wie E2094).',
        [Kind, ARoutine.Name]);
    Fixes := nil;
    if MoveFix(ARoutine, Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(AName.StartPos, AName.EndPos), Message, TRuleConfidence.High, Fixes);
  end;

  procedure CheckName(AName: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Routine: TSyntaxNode;
    TypeText: string;
    FromUnit: TUnitIndex;
    Argument, Index: Integer;
  begin
    Parent := AName.Parent;
    if (Parent = nil) or not (Parent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call]) or
      (Parent[0] = AName) then
      Exit;
    if not Resolver.NodeType(AContext.Tree, FileName, AName, Symbol, TypeInfo, TypeFound) then
      Exit;
    Routine := NestedOf(Symbol);
    if Routine = nil then
      Exit;
    if Parent.Kind = TSyntaxKind.AssignStatement then
    begin
      if TargetType(Parent[0], TypeText, FromUnit) and IsPlainProcedureType(Resolver, AContext, FromUnit, TypeText)
      then
        Report(AName, Routine, True);
      Exit;
    end;
    Argument := -1;
    for Index := 1 to Parent.ChildCount - 1 do
      if Parent[Index] = AName then
        Argument := Index - 1;
    if (Argument >= 0) and ParameterType(Parent, Argument, TypeText, FromUnit) and
      IsPlainProcedureType(Resolver, AContext, FromUnit, TypeText) then
      Report(AName, Routine, False);
  end;

  /// <summary>@X in einer typisierten Konstante einer Routine mit X lokaler Variable bzw. Parameter
  /// (wie E2278).</summary>
  procedure CheckConstant(AConst: TSyntaxNode);
  var
    Inner, Outer: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Outer := OuterRoutine(AConst);
    if (Outer = nil) or (AConst.FindChild(TSyntaxKind.TypeReference) = nil) and
      (AConst.FindChild(TSyntaxKind.PointerType) = nil) then
      Exit;
    for Inner in PreOrder(AConst) do
      if (Inner.Kind = TSyntaxKind.AddressOf) and (Inner.ChildCount = 1) and
        (Inner[0].Kind = TSyntaxKind.Identifier) and
        Resolver.NodeType(AContext.Tree, FileName, Inner[0], Symbol, TypeInfo, TypeFound) and
        (Symbol.Kind = TResolvedKind.Local) and (Symbol.SymbolKind = TIndexSymbolKind.Variable) and
        Covers(Outer, Symbol.SelectionRange.StartPos) then
        AReport.Add(TTextRange.Create(Inner.StartPos, Inner.EndPos),
          Format('Die Adresse des lokalen Symbols %s ist keine Konstante (wie E2278).', [Inner[0].Name]),
          TRuleConfidence.High);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Nodes := PreOrder(AContext.Tree.Root);
  Nested := TList<TSyntaxNode>.Create;
  Names := TStringList.Create;
  try
    Names.CaseSensitive := False;
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    HasConstants := False;
    for Node in Nodes do
      if (Node.Kind = TSyntaxKind.RoutineDecl) and (OuterRoutine(Node) <> nil) then
      begin
        Nested.Add(Node);
        Names.Add(Node.Name);
      end
      else if Node.Kind = TSyntaxKind.ConstDecl then
        HasConstants := True;
    if (Nested.Count = 0) and not HasConstants then
      Exit;
    FileName := ResolverFileName(AContext);
    Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
    if LineBreak = '' then
      LineBreak := sLineBreak;
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      try
        Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
        for Node in Nodes do
          if (Node.Kind = TSyntaxKind.Identifier) and (Names.IndexOf(Node.Name) >= 0) then
            CheckName(Node)
          else if Node.Kind = TSyntaxKind.ConstDecl then
            CheckConstant(Node);
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    Names.Free;
    Nested.Free;
  end;
end;

{ THresultIntegerMixRule }

function THresultIntegerMixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(HresultIntegerMixRuleId, TRuleSeverity.Warning, 'Integer und HRESULT vertauscht');
end;

class function THresultIntegerMixRule.Interchanged(const AExpected, AActual: string): Boolean;

  function Family(const AType: string): Integer;
  var
    Name: string;
  begin
    Name := Trim(AType);
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
    if SameText(Name, 'HRESULT') then
      Result := 1
    else if SameText(Name, 'Integer') or SameText(Name, 'LongInt') then
      Result := 2
    else
      Result := 0;
  end;

begin
  Result := (Family(AExpected) <> 0) and (Family(AActual) <> 0) and (Family(AExpected) <> Family(AActual));
end;

procedure THresultIntegerMixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName: string;
  Local: TUnitIndex;
  Nodes: TArray<TSyntaxNode>;
  Symbol: TIndexSymbol;

  function Key(const AName: string; const AParamTypes: TArray<string>): string;
  var
    ParamType: string;
  begin
    Result := LowerCase(AName) + '(';
    for ParamType in AParamTypes do
      Result := Result + LowerCase(Resolver.UnqualifyType(NormalizedType(ParamType), Local.UnitName)) + ';';
    Result := Result + ')';
  end;

  function Inside(const ARange, AOuter: TTextRange): Boolean;
  begin
    Result := (ARange.StartPos.Line >= AOuter.StartPos.Line) and (ARange.StartPos.Line <= AOuter.EndPos.Line);
  end;

  /// <summary>Ergebnistyp im Kopf (letzter Typverweis); nil ohne.</summary>
  function ResultNode(AHeader: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to AHeader.ChildCount - 1 do
      if AHeader[Index].Kind = TSyntaxKind.TypeReference then
        Result := AHeader[Index];
  end;

  /// <summary>Korrektur: Ergebnistyp in Deklaration und (einzigem) Rumpf auf AType setzen.</summary>
  function AlignFix(const AClass: string; const AMethod: TIndexSymbol; const AType: string;
    out AFix: TRuleFix): Boolean;
  var
    Node, Declaration, Body, Target: TSyntaxNode;
    Bodies: Integer;
    Edits: TArray<TTextEdit>;
  begin
    Result := False;
    Declaration := nil;
    Body := nil;
    Bodies := 0;
    for Node in Nodes do
      if (Node.Kind = TSyntaxKind.RoutineHeader) and Covers(Node, AMethod.SelectionRange.StartPos) then
        Declaration := Node
      else if (Node.Kind = TSyntaxKind.RoutineDecl) and SameText(Node.Name, AClass + '.' + AMethod.Name) then
      begin
        Inc(Bodies);
        Body := Node.FindChild(TSyntaxKind.RoutineHeader);
      end;
    if (Declaration = nil) or (Bodies > 1) then
      Exit;
    Target := ResultNode(Declaration);
    if Target = nil then
      Exit;
    Edits := [TTextEdit.Create(TTextRange.Create(Target.StartPos, Target.EndPos), AType)];
    if Body <> nil then
    begin
      Target := ResultNode(Body);
      // Ein Rumpf ohne Ergebnistyp (function TExport.Schreiben;) bleibt richtig.
      if (Target <> nil) and (Target.StartPos.Line <> Declaration.StartPos.Line) then
        Edits := Edits + [TTextEdit.Create(TTextRange.Create(Target.StartPos, Target.EndPos), AType)];
    end;
    AFix := TRuleFix.Create(Format('Ergebnistyp %s wie im Interface', [AType]), Edits);
    Result := True;
  end;

  procedure CheckClass(const AClass: TIndexSymbol);
  var
    Methods: TList<TIndexSymbol>;
    Resolutions: TStringList;
    Seen: TStringList;
    Ancestor, Intf, Parent: TResolvedSymbol;
    IntfUnit: TUnitIndex;
    Member, Method, Wanted: TIndexSymbol;
    Name, Target, MethodKey: string;
    Depth: Integer;
    Expected: TArray<TIndexSymbol>;
    Actual: TArray<TIndexSymbol>;
    AllDiffer: Boolean;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Methods := TList<TIndexSymbol>.Create;
    Resolutions := TStringList.Create;
    Seen := TStringList.Create;
    try
      // Methoden im Rumpf der Klasse; "function IExport.Lesen = LesenIntern" als Zuordnung.
      for Member in Local.Symbols do
        if SameText(Member.Container, AClass.Name) and (Member.Kind = TIndexSymbolKind.Method) and
          Inside(Member.SelectionRange, AClass.Range) then
        begin
          if Pos('.', Member.Name) > 0 then
          begin
            Target := Member.Signature;
            if Pos('=', Target) > 0 then
              Resolutions.Values[LowerCase(Member.Name)] := Trim(Copy(Target, Pos('=', Target) + 1, MaxInt));
          end
          else
            Methods.Add(Member);
        end;
      for Name in AClass.Ancestors do
      begin
        if not Resolver.ResolveTypeFrom(Local, Name, Ancestor) or
          (Ancestor.SymbolKind <> TIndexSymbolKind.InterfaceType) then
          Continue;
        Intf := Ancestor;
        for Depth := 0 to MaxAliasDepth do
        begin
          if (Seen.IndexOf(Intf.QualifiedName) >= 0) or not SymbolUnit(Resolver, Local, Intf, IntfUnit) then
            Break;
          Seen.Add(Intf.QualifiedName);
          for Member in IntfUnit.Symbols do
          begin
            if not SameText(Member.Container, Intf.QualifiedName) or (Member.Kind <> TIndexSymbolKind.Method) then
              Continue;
            // Alle Varianten der Interface-Methode (bedingte Zweige) und der Implementierung.
            Expected := nil;
            for Method in IntfUnit.Symbols do
              if SameText(Method.Container, Member.Container) and (Method.Kind = TIndexSymbolKind.Method) and
                (Key(Method.Name, Method.ParamTypes) = Key(Member.Name, Member.ParamTypes)) then
                Expected := Expected + [Method];
            if (Length(Expected) = 0) or (Expected[0].SelectionRange.StartPos.Line <>
              Member.SelectionRange.StartPos.Line) then
              Continue;
            Target := Resolutions.Values[LowerCase(Intf.Name + '.' + Member.Name)];
            if Target = '' then
              Target := Member.Name;
            MethodKey := Key(Target, Member.ParamTypes);
            Actual := nil;
            for Method in Methods do
              if Key(Method.Name, Method.ParamTypes) = MethodKey then
                Actual := Actual + [Method];
            if Length(Actual) = 0 then
              Continue;
            AllDiffer := True;
            for Method in Actual do
              for Wanted in Expected do
                if not Interchanged(Wanted.TypeName, Method.TypeName) then
                  AllDiffer := False;
            if not AllDiffer then
              Continue;
            for Method in Actual do
            begin
              Fixes := nil;
              if (Length(Expected) = 1) and (Length(Actual) = 1) and
                AlignFix(AClass.Name, Method, Member.TypeName, Fix) then
                Fixes := [Fix];
              AReport.Add(Method.SelectionRange, Format('%s.%s liefert %s, die Implementierung %s (wie X1008).',
                [Intf.Name, Member.Name, Member.TypeName, Method.TypeName]), TRuleConfidence.High, Fixes);
            end;
          end;
          if not Resolver.AncestorOf(Intf, Parent) or (Parent.SymbolKind <> TIndexSymbolKind.InterfaceType) then
            Break;
          Intf := Parent;
        end;
      end;
    finally
      Seen.Free;
      Resolutions.Free;
      Methods.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (not ContainsText(AContext.Text, 'HRESULT') and
    not ContainsText(AContext.Text, 'Integer') and not ContainsText(AContext.Text, 'LongInt')) then
    Exit;
  FileName := ResolverFileName(AContext);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
      Nodes := PreOrder(AContext.Tree.Root);
      for Symbol in Local.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Length(Symbol.Ancestors) > 0) then
          CheckClass(Symbol);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

{ TInvalidVarArgumentRule }

function TInvalidVarArgumentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InvalidVarArgumentRuleId, TRuleSeverity.Error,
    'Ungültiges Argument für einen var- oder out-Parameter');
end;

procedure TInvalidVarArgumentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName, LineBreak: string;
  Local: TUnitIndex;
  Lines: TArray<string>;
  Node: TSyntaxNode;
  WriteableConsts: Boolean;

  function ModifierWord(const AModifier: string): string;
  var
    Words: TArray<string>;
  begin
    Words := Trim(AModifier).Split([' ']);
    Result := '';
    if Length(Words) > 0 then
      Result := LowerCase(Words[High(Words)]);
  end;

  function IsStringText(const AType: string): Boolean;
  begin
    Result := MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
      'UTF8String', 'System.string', 'System.UnicodeString', 'System.AnsiString', 'System.WideString']);
  end;

  /// <summary>Typisierte Konstante? Aus dem Kopf im Index ("C: Integer = 2") bzw. dem Baum.</summary>
  function IsTypedConstant(const ASymbol: TResolvedSymbol): Boolean;
  var
    Decl: TSyntaxNode;
    Colon, Equal: Integer;
  begin
    if (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.TypeName <> '') then
      Exit(True);
    if ASymbol.Signature <> '' then
    begin
      Colon := Pos(':', ASymbol.Signature);
      Equal := Pos('=', ASymbol.Signature);
      Exit((Colon > 0) and ((Equal = 0) or (Colon < Equal)));
    end;
    Result := False;
    if (ASymbol.Kind = TResolvedKind.Local) and (AContext.Tree <> nil) then
    begin
      Decl := DeclarationAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
      Result := (Decl <> nil) and (Decl.Kind = TSyntaxKind.ConstDecl) and (NodeTypeText(AContext.Text, Decl) <> '');
    end;
  end;

  /// <summary>Lokaler const- bzw. constref-Parameter?</summary>
  function IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
  var
    Decl: TSyntaxNode;
  begin
    Result := False;
    if (ASymbol.Kind <> TResolvedKind.Local) or not ASymbol.IsParameter then
      Exit;
    Decl := DeclarationAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
    Result := (Decl <> nil) and (Decl.Kind = TSyntaxKind.Parameter) and
      (Decl.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam]);
  end;

  /// <summary>Was ist AArgument für einen var- bzw. out-Parameter vom Typ AParamType? ADescription nennt es in
  /// der Meldung, AWriteBack: Die Korrektur schreibt den Wert zurück.</summary>
  function Classify(AArgument: TSyntaxNode; const AParamType: string; out ADescription: string;
    out AWriteBack: Boolean): TVarArgumentKind;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, OpenArray: Boolean;
  begin
    Result := TVarArgumentKind.None;
    ADescription := NodeText(AContext, AArgument);
    AWriteBack := False;
    OpenArray := StartsText('array of ', AParamType) and not SameText(NormalizedType(AParamType), 'array of const');
    case AArgument.Kind of
      TSyntaxKind.Literal:
        if OpenArray then
          Result := TVarArgumentKind.OpenArrayConstant
        else
        begin
          ADescription := Format('Der Wert %s', [ADescription]);
          Result := TVarArgumentKind.ConstantObject;
        end;
      TSyntaxKind.SetConstructor:
        if OpenArray then
          Result := TVarArgumentKind.OpenArrayConstant
        else
          Result := TVarArgumentKind.Expression;
      TSyntaxKind.UnaryExpr, TSyntaxKind.AddressOf:
        Result := TVarArgumentKind.Expression;
      TSyntaxKind.BinaryExpr:
        // "X as TFoo" ist ein Typumwandlung; der Compiler meldet sie anders.
        if not SameText(AArgument.Name, 'as') then
          Result := TVarArgumentKind.Expression;
      TSyntaxKind.IndexAccess:
        // S[I] mit S vom Typ string an einen Zeichen-Parameter (wie E2354).
        if (AArgument.ChildCount = 2) and MatchText(AParamType, ['Char', 'WideChar', 'AnsiChar']) and
          (AArgument[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          Resolver.NodeType(AContext.Tree, FileName, AArgument[0], Symbol, TypeInfo, TypeFound) and
          (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) and
          IsStringText(DeclaredTypeText(AContext, Symbol)) then
        begin
          AWriteBack := True;
          Result := TVarArgumentKind.StringElement;
        end;
      TSyntaxKind.Call:
        if (AArgument.ChildCount > 0) and (AArgument[0].Kind = TSyntaxKind.Identifier) and
          SameText(AArgument[0].Name, 'Slice') and OpenArray and
          IsIntrinsicCall(Resolver, AContext, FileName, AArgument[0], 'Slice') then
          Result := TVarArgumentKind.SliceCall
        else if (AArgument.ChildCount > 0) and
          Resolver.NodeType(AContext.Tree, FileName, AArgument[0], Symbol, TypeInfo, TypeFound) and
          not Symbol.IsType and (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
          (Symbol.TypeName <> '') then
        begin
          // Aufruf einer Funktion (keine Typumwandlung): ihr Ergebnis ist keine Variable.
          ADescription := Format('Das Ergebnis von %s', [NodeText(AContext, AArgument[0])]);
          Result := TVarArgumentKind.ConstantObject;
        end;
      TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
        if Resolver.NodeType(AContext.Tree, FileName, AArgument, Symbol, TypeInfo, TypeFound) then
          case Symbol.SymbolKind of
            TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember:
              if not IsTypedConstant(Symbol) then
              begin
                if OpenArray then
                  Exit(TVarArgumentKind.OpenArrayConstant);
                ADescription := Format('Die Konstante %s', [ADescription]);
                Result := TVarArgumentKind.ConstantObject;
              end
              else if not WriteableConsts and (Symbol.SymbolKind = TIndexSymbolKind.Constant) then
              begin
                ADescription := Format('Die typisierte Konstante %s', [ADescription]);
                Result := TVarArgumentKind.ConstantObject;
              end;
            TIndexSymbolKind.Property_:
              begin
                ADescription := Format('Die Eigenschaft %s', [ADescription]);
                AWriteBack := ContainsText(' ' + Symbol.Signature.Replace(';', ' ') + ' ', ' write ');
                Result := TVarArgumentKind.ConstantObject;
              end;
            TIndexSymbolKind.Variable:
              if IsConstParameter(Symbol) then
              begin
                ADescription := Format('Der const-Parameter %s', [ADescription]);
                Result := TVarArgumentKind.ConstantObject;
              end;
          end;
    end;
  end;

  /// <summary>Korrektur: das Argument über eine lokale Variable vom Typ des Parameters übergeben, bei
  /// String-Elementen und beschreibbaren Eigenschaften mit Rückschreiben.</summary>
  function LocalVariableFix(ACall, AArgument: TSyntaxNode; const AParamType: string; AOut, AWriteBack: Boolean;
    out AFix: TRuleFix): Boolean;
  var
    Host, Routine: TSyntaxNode;
    TypeSymbol: TResolvedSymbol;
    Name, Argument, Indent, Rest: string;
    Edits: TArray<TTextEdit>;
  begin
    Result := False;
    Host := ACall.Parent;
    if (Host = nil) or not ((Host.Kind = TSyntaxKind.CallStatement) or
      ((Host.Kind = TSyntaxKind.AssignStatement) and (Host.ChildCount = 2) and (Host[1] = ACall))) or
      not TRoutineBody.InList(Host) or (Host.StartPos.Line <> Host.EndPos.Line) or (Host.EndPos.Line > High(Lines)) then
      Exit;
    Routine := TRoutineBody.RoutineAt(AContext.Tree, Host.StartOffset);
    if (Routine = nil) or (AParamType = '') or StartsText('array of', AParamType) or
      not (TNameResolver.IsBuiltinTypeName(AParamType) or Resolver.ResolveTypeFrom(Local, AParamType, TypeSymbol)) then
      Exit;
    Rest := Trim(Copy(Lines[Host.EndPos.Line], Host.EndPos.Character + 1, MaxInt));
    if (Rest <> '') and (Rest <> ';') then
      Exit;
    Name := TRoutineBody.UniqueName(AContext.Tree.Tokens, 'Wert');
    Argument := NodeText(AContext, AArgument);
    Indent := TTextLines.IndentOf(Lines[Host.StartPos.Line]);
    Edits := [TRoutineBody.AddVariable(AContext.Text, Routine, Name, AParamType, AContext.Formatting)];
    if not AOut then
      Edits := Edits + [TRoutineBody.InsertBefore(AContext.Text, Host, Name + ' := ' + Argument + ';')];
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), Name)];
    if AWriteBack then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.EndPos.Line, Length(Lines[Host.EndPos.Line]),
        Host.EndPos.Line, Length(Lines[Host.EndPos.Line])), LineBreak + Indent + Argument + ' := ' + Name + ';')];
    AFix := TRuleFix.Create(Format('Über eine lokale Variable %s übergeben', [Name]), Edits);
    Result := True;
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, WriteBack: Boolean;
    Params: TArray<TSignatureParameter>;
    Index: Integer;
    Modifier, Description, Message: string;
    Argument: TSyntaxNode;
    Kind: TVarArgumentKind;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    if (ACall.ChildCount < 2) or (ACall[0].Kind = TSyntaxKind.InheritedExpr) or
      not Resolver.NodeType(AContext.Tree, FileName, ACall, Symbol, TypeInfo, TypeFound) or Symbol.IsType or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) or
      not RoutineParams(AContext, Symbol, Params) then
      Exit;
    // Passt die Zahl der Argumente nicht zum Kopf, ist es eine andere Routine (bzw. ein anderer Fehler).
    if (Symbol.Signature <> '') and ((ACall.ChildCount - 1 < Symbol.MinArgs) or
      (ACall.ChildCount - 1 > Symbol.MaxArgs)) then
      Exit;
    for Index := 1 to ACall.ChildCount - 1 do
    begin
      if Index > Length(Params) then
        Break;
      Modifier := ModifierWord(Params[Index - 1].Modifier);
      if (Modifier <> 'var') and (Modifier <> 'out') then
        Continue;
      Argument := ACall[Index];
      Kind := Classify(Argument, NormalizedType(Params[Index - 1].TypeName), Description, WriteBack);
      case Kind of
        TVarArgumentKind.StringElement:
          Message := Format('Ein String-Element kann nicht an einen %s-Parameter übergeben werden (wie E2354).',
            [Modifier]);
        TVarArgumentKind.ConstantObject:
          Message := Format('%s ist keine Variable und kann nicht an einen %s-Parameter übergeben werden (wie E2197).',
            [Description, Modifier]);
        TVarArgumentKind.OpenArrayConstant:
          Message := Format('Eine Konstante kann nicht als offenes Array an einen %s-Parameter übergeben werden ' +
            '(wie E2192).', [Modifier]);
        TVarArgumentKind.SliceCall:
          Message := Format('Slice ist für einen %s-Parameter nicht erlaubt; Änderungen kämen nicht im Array an ' +
            '(wie E2454).', [Modifier]);
        TVarArgumentKind.Expression:
          Message := Format('An einen %s-Parameter muss eine Variable übergeben werden, kein Ausdruck (wie E2036).',
            [Modifier]);
      else
        Continue;
      end;
      Fixes := nil;
      if (Kind in [TVarArgumentKind.StringElement, TVarArgumentKind.ConstantObject, TVarArgumentKind.Expression]) and
        LocalVariableFix(ACall, Argument, NormalizedType(Params[Index - 1].TypeName), Modifier = 'out', WriteBack, Fix)
      then
        Fixes := [Fix];
      AReport.Add(TTextRange.Create(Argument.StartPos, Argument.EndPos), Message, TRuleConfidence.High, Fixes);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  // Typisierte Konstanten sind mit {$J+} beschreibbar.
  WriteableConsts := ContainsText(AContext.Text, '{$J+') or ContainsText(AContext.Text, '{$WRITEABLECONST ON') or
    ContainsText(AContext.Text, ',J+');
  FileName := ResolverFileName(AContext);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  if LineBreak = '' then
    LineBreak := sLineBreak;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
      for Node in PreOrder(AContext.Tree.Root) do
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 1) then
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
  ARegistry.Register(TLocalRoutineAsCallbackRule.Create);
  ARegistry.Register(THresultIntegerMixRule.Create);
  ARegistry.Register(TInvalidVarArgumentRule.Create);
end;

end.
