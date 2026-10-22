unit Atlas.Common.Semantics.UnresolvedNames;

// Bezeichner, die sich nicht auflösen lassen (#178), für das MCP-Werkzeug
// check_code. Bewusst vorsichtig, weil die Namensauflösung nur die
// Grundstufe kennt:
// - geprüft wird nur der erste Name einer Kette (A in A.B.C) in
//   Anweisungen, nicht in Deklarationen;
// - with-Blöcke, asm und anonyme Methoden werden übersprungen;
// - Compiler-Intrinsics (Length, Inc, Exit, …) gelten als bekannt;
// - ohne Unit System im Index wird gar nichts gemeldet, weil dann jeder
//   RTL-Name fehlen würde.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TUnresolvedName = record
    Name: string;
    Range: TTextRange;
  end;

  TUnresolvedNames = class
  public const
    MaxNames = 100;
  public
    /// <summary>True, wenn der Index die Unit System kennt und die Prüfung damit aussagekräftig ist.</summary>
    class function Available(const AIndex: ISymbolIndex): Boolean; static;
    /// <summary>Nicht auflösbare Namen in ATree, höchstens MaxNames.</summary>
    class function Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TArray<TUnresolvedName>; static;
    /// <summary>Vom Compiler eingebaute Routinen und Konstanten ohne Deklaration in System.pas.</summary>
    class function IsIntrinsic(const AName: string): Boolean; static;
  end;

implementation

const
  Intrinsics: array[0..62] of string = (
    'Abs', 'Addr', 'Assert', 'Assigned', 'AtomicCmpExchange', 'AtomicDecrement', 'AtomicExchange',
    'AtomicIncrement', 'Break', 'Chr', 'Concat', 'Continue', 'Copy', 'Dec', 'Default',
    'Delete', 'Dispose', 'Exclude', 'Exit', 'False', 'FillChar', 'Finalize', 'GetTypeKind', 'Halt', 'HasWeakRef',
    'Hi', 'High', 'Inc', 'Include', 'Initialize', 'Insert', 'IsConstValue', 'IsManagedType', 'Length', 'Lo', 'Low',
    'Move', 'New', 'nil', 'Odd', 'Ord', 'Pred', 'Ptr', 'Read', 'ReadLn', 'Result', 'Round', 'Self', 'SetLength',
    'SetString', 'SizeOf', 'Slice', 'Str', 'Succ', 'Swap', 'True', 'Trunc', 'TypeInfo', 'Write', 'WriteLn',
    // Konstanten aus System.pas, die im Index fehlen können (Ursache nicht geprüft, #647).
    'MaxInt', 'MaxLongint',
    // Aus SysInit, das der Compiler immer einbindet.
    'HInstance');

class function TUnresolvedNames.IsIntrinsic(const AName: string): Boolean;
var
  Name: string;
begin
  for Name in Intrinsics do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

class function TUnresolvedNames.Available(const AIndex: ISymbolIndex): Boolean;
var
  SystemUnit: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindUnit('System', SystemUnit);
end;

type
  /// <summary>Eintrag in TUnresolvedNames.Find: Knoten und ob er in Anweisungen liegt.</summary>
  TUnresolvedEntry = record
    Node: TSyntaxNode;
    InStatements: Boolean;
  end;

function UnresolvedEntry(ANode: TSyntaxNode; AInStatements: Boolean): TUnresolvedEntry;
begin
  Result.Node := ANode;
  Result.InStatements := AInStatements;
end;

class function TUnresolvedNames.Find(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TArray<TUnresolvedName>;
var
  // Nachschlagen statt Liste: bei vielen Inline-Variablen sonst ein Lauf je Bezeichner (Diagnoselog 15.10.2026).
  Declared: TDictionary<string, Boolean>;

  function IsDeclared(const AName: string): Boolean;
  begin
    Result := Declared.ContainsKey(UpperCase(AName));
  end;

  // Namen, die die Grundstufe nicht sicher als lokal kennt: Ausnahmevariablen und Inline-Variablen.
  procedure CollectDeclared(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.ExceptionHandler, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
          TSyntaxKind.LabeledStatement, TSyntaxKind.GotoStatement]) and (Node.Name <> '') then
          Declared.AddOrSetValue(UpperCase(Node.Name), True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TUnresolvedEntry>;
    Entry: TUnresolvedEntry;
    Node: TSyntaxNode;
    InStatements: Boolean;
    Index: Integer;
    Resolved: TResolvedSymbol;
    Item: TUnresolvedName;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1); die Kinder rückwärts darauf, damit Reihenfolge und Grenze
    // MaxNames dieselben bleiben wie in der früheren Rekursion.
    Pending := TStack<TUnresolvedEntry>.Create;
    try
      Pending.Push(UnresolvedEntry(ARoot, False));
      while (Pending.Count > 0) and (Length(Result) < MaxNames) do
      begin
        Entry := Pending.Pop;
        Node := Entry.Node;
        InStatements := Entry.InStatements;
        if Node.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock, TSyntaxKind.AnonymousMethod,
          TSyntaxKind.Error] then
          Continue;
        // Anweisungen stehen in Blöcken von Routinen und in initialization/finalization.
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection] then
          InStatements := True
        else if Node.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection,
          TSyntaxKind.RoutineHeader, TSyntaxKind.Parameters, TSyntaxKind.GenericArgs] then
          InStatements := False;
        // Typumwandlungen und Typhelfer (Integer(X), string.Join) sowie der Anfang eines Unit-Namens
        // (Winapi in Winapi.Windows.TextOut) sind keine fehlenden Bezeichner (#647).
        if InStatements and (Node.Kind = TSyntaxKind.Identifier) and (Node.Name <> '') and
          not IsIntrinsic(Node.Name) and not IsDeclared(Node.Name) and
          not TNameResolver.IsBuiltinTypeName(Node.Name) then
        begin
          // IsUnitPrefix erst danach: ResolveChain legt die Unit und den Abschnitt fest.
          Resolved := AResolver.ResolveChain(ATree, AFileName, [Node.Name], Node.StartOffset);
          if not Resolved.Found and not AResolver.IsUnitPrefix(Node.Name) and not AResolver.HasUnknownAncestor then
          begin
            Item.Name := Node.Name;
            Item.Range := TTextRange.Create(Node.StartPos, Node.EndPos);
            Result := Result + [Item];
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(UnresolvedEntry(Node[Index], InStatements));
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Declared := TDictionary<string, Boolean>.Create;
  try
    CollectDeclared(ATree.Root);
    AResolver.PinTree(ATree, AFileName);
    try
      Visit(ATree.Root);
    finally
      AResolver.UnpinTree;
    end;
  finally
    Declared.Free;
  end;
end;

end.
