unit Atlas.Common.Rules.Builtin.Ownership.RawMemory;

// Regel aus Atlas.Common.Rules.Builtin.Ownership ausgelagert (Länge der Unit):
//   raw-memory-leak   lokaler Zeiger aus GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, den
//                     die Routine nie freigibt und der sie nicht verlässt (#1047): Jedes Vorkommen wird im
//                     Syntaxbaum nach oben eingeordnet (Belegung, Freigabe, Zugriff, Weitergabe als Ergebnis,
//                     Zuweisung, @P, Add/Insert…, anonyme Methode, lokale Routine). Lesen und Füllen über ein
//                     Argument ist erlaubt; Routinen mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen
//                     gelten als Freigabe. Korrektur: try … finally mit FreeMem, Dispose bzw. StrDispose.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TRawMemoryLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Passende Freigabe zur Belegung AAllocator (GetMem → FreeMem, New → Dispose, StrAlloc →
    /// StrDispose); '' für eine unbekannte Belegung.</summary>
    class function ReleaseFor(const AAllocator: string): string; static;
  end;

/// <summary>Registriert die Regel raw-memory-leak.</summary>
procedure RegisterOwnershipRawMemoryRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Ownership.TryFinally;

const
  RawMemoryLeakRuleId = 'raw-memory-leak';

{ TRawMemoryLeakRule }

type
  /// <summary>Wie eine lokale Variable an einer Stelle vorkommt (raw-memory-leak, #1047).</summary>
{$SCOPEDENUMS ON}
  TRawMemoryUse = (Use, Alloc, Release, Escape);
{$SCOPEDENUMS OFF}

const
  // Belegungen mit der Variablen als erstem Argument bzw. als Ziel der Zuweisung.
  RawAllocCalls: array[0..2] of string = ('GetMem', 'New', 'ReallocMem');
  RawAllocFunctions: array[0..4] of string = ('AllocMem', 'GetMemory', 'StrAlloc', 'StrNew', 'AnsiStrAlloc');
  RawReleaseCalls: array[0..4] of string = ('FreeMem', 'Dispose', 'StrDispose', 'FreeMemory', 'FreeMemAndNil');
  // Methoden, die den Zeiger übernehmen (in Listen, Felder anderer Objekte).
  RawStorePrefixes: array[0..11] of string = ('Add', 'Insert', 'Push', 'Enqueue', 'Put', 'Store', 'Register',
    'Attach', 'Append', 'Set', 'Assign', 'TryAdd');
  // Teile eines Routinennamens, die auf eine eigene Freigaberoutine schließen lassen.
  RawReleaseWords: array[0..5] of string = ('Free', 'Frei', 'Release', 'Dispose', 'Destroy', 'Dealloc');

function TRawMemoryLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RawMemoryLeakRuleId, TRuleSeverity.Warning,
    'GetMem oder New ohne Freigabe');
end;

class function TRawMemoryLeakRule.ReleaseFor(const AAllocator: string): string;
begin
  if MatchText(AAllocator, ['GetMem', 'AllocMem', 'ReallocMem']) then
  begin
    Result := 'FreeMem';
  end
  else if SameText(AAllocator, 'GetMemory') then
  begin
    Result := 'FreeMemory';
  end
  else if SameText(AAllocator, 'New') then
  begin
    Result := 'Dispose';
  end
  else if MatchText(AAllocator, ['StrAlloc', 'StrNew', 'AnsiStrAlloc']) then
  begin
    Result := 'StrDispose';
  end
  else
  begin
    Result := '';
  end;
end;

procedure TRawMemoryLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;

  function StartsWithAny(const AName: string; const APrefixes: array of string): Boolean;
  var
    Prefix: string;
  begin
    for Prefix in APrefixes do
    begin
      if StartsText(Prefix, AName) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function ContainsAny(const AName: string; const AWords: array of string): Boolean;
  var
    Word: string;
  begin
    for Word in AWords do
    begin
      if ContainsText(AName, Word) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Typumwandlung wie PByte(P), PChar(P), Pointer(P): ein Argument, Aufruf über einen Typnamen.
  function IsTypeCast(ACall: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    Result := False;
    if (ACall.ChildCount <> 2) or (ACall[0].Kind <> TSyntaxKind.Identifier) then
    begin
      Exit;
    end;
    Name := ACall[0].Name;
    Result := MatchText(Name, ['Pointer', 'NativeInt', 'NativeUInt', 'IntPtr', 'UIntPtr', 'PChar', 'PAnsiChar',
      'PWideChar', 'PByte', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'LongInt', 'LongWord']) or
      ((Length(Name) > 1) and CharInSet(Name[1], ['P', 'T']) and CharInSet(Name[2], ['A'..'Z']));
  end;

  // Art des Vorkommens ANode (Bezeichner der Variablen) vom Knoten aus nach oben bis zur Anweisung.
  function Classify(ANode: TSyntaxNode): TRawMemoryUse;
  var
    Current, Parent, Value: TSyntaxNode;
    Direct: Boolean;
  begin
    Current := ANode;
    Direct := True;
    while Current.Parent <> nil do
    begin
      Parent := Current.Parent;
      case Parent.Kind of
        // P^, P.Feld, P[I]: Zugriff auf den Speicher.
        TSyntaxKind.Dereference, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess:
          Exit(TRawMemoryUse.Use);
        TSyntaxKind.AddressOf, TSyntaxKind.InlineVar, TSyntaxKind.VarDecl, TSyntaxKind.AnonymousMethod:
          Exit(TRawMemoryUse.Escape);
        TSyntaxKind.Call:
          begin
            if Parent[0] = Current then
            begin
              Exit(TRawMemoryUse.Use);
            end;
            if Direct and (Parent[1] = Current) and MatchText(Parent.Name, RawAllocCalls) then
            begin
              // ReallocMem(P, 0) gibt frei.
              if SameText(Parent.Name, 'ReallocMem') and (Parent.ChildCount = 3) and
                (Parent[2].Kind = TSyntaxKind.Literal) and (Parent[2].Name = '0') then
              begin
                Exit(TRawMemoryUse.Release);
              end;
              Exit(TRawMemoryUse.Alloc);
            end;
            if MatchText(Parent.Name, RawReleaseCalls) or ContainsAny(Parent.Name, RawReleaseWords) then
            begin
              Exit(TRawMemoryUse.Release);
            end;
            if SameText(Parent.Name, 'Exit') then
            begin
              Exit(TRawMemoryUse.Escape);
            end;
            if IsTypeCast(Parent) then
            begin
              Current := Parent;
              Direct := False;
              Continue;
            end;
            if (Parent[0].Kind = TSyntaxKind.MemberAccess) and StartsWithAny(Parent.Name, RawStorePrefixes) then
            begin
              Exit(TRawMemoryUse.Escape);
            end;
            // Als Argument zum Lesen oder Füllen weitergegeben (Pruefsumme(P, N), Stream.ReadBuffer(P^, N)).
            Exit(TRawMemoryUse.Use);
          end;
        TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr:
          begin
            Current := Parent;
            Direct := False;
          end;
        TSyntaxKind.BinaryExpr:
          begin
            // Vergleiche lesen nur; P + N rechnet mit dem Zeiger weiter.
            if not MatchText(Parent.Name, ['+', '-']) then
            begin
              Exit(TRawMemoryUse.Use);
            end;
            Current := Parent;
            Direct := False;
          end;
        TSyntaxKind.AssignStatement:
          begin
            if Parent[0] <> Current then
            begin
              Exit(TRawMemoryUse.Escape);
            end;
            if not Direct then
            begin
              Exit(TRawMemoryUse.Use);
            end;
            Value := nil;
            if Parent.ChildCount > 1 then
            begin
              Value := Parent[1];
            end;
            if (Value <> nil) and (Value.Kind = TSyntaxKind.Call) and MatchText(Value.Name, RawAllocFunctions) then
            begin
              Exit(TRawMemoryUse.Alloc);
            end;
            // Neue Zuweisung (P := Q, P := nil): Herkunft unklar.
            Exit(TRawMemoryUse.Escape);
          end;
      else
        Exit(TRawMemoryUse.Use);
      end;
    end;
    Result := TRawMemoryUse.Use;
  end;

  // Name der Belegung an der Anweisung des Vorkommens ANode.
  function AllocatorOf(ANode: TSyntaxNode): string;
  begin
    if ANode.Parent.Kind = TSyntaxKind.Call then
    begin
      Result := ANode.Parent.Name;
    end
    else
    begin
      Result := ANode.Parent[1].Name;
    end;
  end;

  procedure Occurrences(ANode: TSyntaxNode; const AName: string; var AFound: TArray<TSyntaxNode>);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) and
          not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.MemberAccess) and (Node.Parent[0] <> Node))
          then
        begin
          AFound := AFound + [Node];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function HasAsm(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AsmBlock then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Steht ANode in einer anonymen Methode der Routine (die Variable wird eingefangen)?
  function InsideAnonymous(ANode, ARoutine: TSyntaxNode): Boolean;
  var
    Current: TSyntaxNode;
  begin
    Current := ANode.Parent;
    while (Current <> nil) and (Current <> ARoutine) do
    begin
      if Current.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Exit(True);
      end;
      Current := Current.Parent;
    end;
    Result := False;
  end;

  // Die Anweisung, die das Vorkommen ANode enthält.
  function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result <> nil) and not (Result.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement]) do
    begin
      Result := Result.Parent;
    end;
  end;

  procedure CheckVariable(ARoutine: TSyntaxNode; const AName: string);
  var
    Found: TArray<TSyntaxNode>;
    Node, First, Statement: TSyntaxNode;
    Index: Integer;
    Use: TRawMemoryUse;
    Allocator, Release: string;
    Edit: TTextEdit;
    Fixes: TArray<TRuleFix>;
  begin
    Found := nil;
    Occurrences(ARoutine, AName, Found);
    First := nil;
    for Node in Found do
    begin
      Use := Classify(Node);
      if InsideAnonymous(Node, ARoutine) then
      begin
        Use := TRawMemoryUse.Escape;
      end;
      if Use in [TRawMemoryUse.Release, TRawMemoryUse.Escape] then
      begin
        Exit;
      end;
      if (Use = TRawMemoryUse.Alloc) and (First = nil) then
      begin
        First := Node;
      end;
    end;
    // Lokale Routinen sehen die Variable ebenfalls: dort könnte sie freigegeben werden.
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        Found := nil;
        Occurrences(ARoutine[Index], AName, Found);
        if Found <> nil then
        begin
          Exit;
        end;
      end;
    end;
    if First = nil then
    begin
      Exit;
    end;
    Allocator := AllocatorOf(First);
    Release := ReleaseFor(Allocator);
    Statement := StatementOf(First);
    Fixes := nil;
    if (Release <> '') and (Statement <> nil) and TTryFinallyWrap.Create(Lines, LineBreak,
      AContext.Formatting).Wrap(Statement, '', Release + '(' + AName + ');', Edit) then
    begin
      Fixes := [TRuleFix.Create(Format('try … finally %s(%s) end einfügen', [Release, AName]), [Edit])];
    end;
    AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
      Format('%s wird mit %s angelegt, aber nie freigegeben.', [AName, Allocator]), TRuleConfidence.Medium,
      Fixes);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Index, Inner: Integer;
    Section, Decl: TSyntaxNode;
    Name: string;
  begin
    if HasAsm(ARoutine) then
    begin
      Exit;
    end;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Section := ARoutine[Index];
      if Section.Kind <> TSyntaxKind.VarSection then
      begin
        Continue;
      end;
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        Decl := Section[Inner];
        if Decl.Kind <> TSyntaxKind.VarDecl then
        begin
          Continue;
        end;
        for Name in Decl.Name.Split([',']) do
        begin
          if Trim(Name) <> '' then
          begin
            CheckVariable(ARoutine, Trim(Name));
          end;
        end;
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          CheckRoutine(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Word: string;
  Any: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Any := False;
  for Word in RawAllocCalls do
  begin
    Any := Any or ContainsText(AContext.Text, Word);
  end;
  for Word in RawAllocFunctions do
  begin
    Any := Any or ContainsText(AContext.Text, Word);
  end;
  if not Any then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root);
end;

procedure RegisterOwnershipRawMemoryRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TRawMemoryLeakRule.Create);
end;

end.
