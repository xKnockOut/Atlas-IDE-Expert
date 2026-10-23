unit Atlas.Common.Semantics.Recursion;

// Rekursion innerhalb einer Unit (#623), nur aus dem Syntaxbaum:
// - Aufrufgraph der implementierten Routinen: Bezeichner und Self.X im Rumpf
//   werden aufgelöst zu lokalen Routinen, Methoden derselben Klasse, Getter
//   bzw. Setter einer Property derselben Klasse und freien Routinen der Unit.
//   Parameter, Variablen, Konstanten und Result verdecken gleichnamige
//   Routinen. Ein Prozedurname außerhalb einer Aufrufstelle ist ein
//   Methodenzeiger und kein Aufruf.
// - Nicht verfolgt (Konfidenz #144): inherited, andere Objekte (Other.X),
//   with-Blöcke, anonyme Methoden, @X, Methodenzeiger und Ereignisse sowie
//   virtuelle Methoden anderer Klassen.
// - Calls: jede Aufrufstelle, die auf einem Kreis von höchstens AMaxDepth
//   Routinen liegt, mit der kürzesten Kette von der aufrufenden Routine zurück
//   zu ihr. Überladungen gelten als eine Routine.
// - AccessorTraps: Getter liest bzw. Setter schreibt die eigene Property
//   (Result := Name in GetName); mit dem Feld aus read/write der Property oder
//   F<Name>, wenn die Klasse es hat.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Eine Routine der Kette: Name wie im Kopf (z. B. "TFoo.Speichern") und Bereich des Namens.</summary>
  TRecursionStep = record
    Name: string;
    Range: TTextRange;
  end;

  /// <summary>Aufrufstelle auf einem Kreis.</summary>
  TRecursiveCall = record
    /// <summary>Bereich des aufgerufenen Namens.</summary>
    Range: TTextRange;
    /// <summary>Von der aufrufenden Routine über die aufgerufene zurück zu ihr; bei direkter Rekursion zwei
    /// gleiche Einträge.</summary>
    Chain: TArray<TRecursionStep>;
  end;

  /// <summary>Getter liest bzw. Setter schreibt die eigene Property.</summary>
  TAccessorTrap = record
    Range: TTextRange;
    PropertyName: string;
    Accessor: string;
    IsSetter: Boolean;
    /// <summary>Feld F&lt;PropertyName&gt; der Klasse, sonst ''.</summary>
    Field: string;
  end;

  TRecursionAnalysis = class
  public const
    DefaultDepth = 4;
    MinDepth = 1;
    MaxDepth = 16;
  public
    /// <summary>Aufrufstellen auf Kreisen aus höchstens AMaxDepth Routinen (auf MinDepth..MaxDepth begrenzt).</summary>
    class function Calls(ATree: TSyntaxTree; AMaxDepth: Integer): TArray<TRecursiveCall>; static;
    class function AccessorTraps(ATree: TSyntaxTree): TArray<TAccessorTrap>; static;
    /// <summary>Kette als Text, z. B. "Speichern → Pruefen → Speichern" (ohne Klassennamen).</summary>
    class function ChainText(const ACall: TRecursiveCall): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract;

type
  TRoutineInfo = class;

  TPropertyInfo = class
  public
    Name: string;
    Reader: string;
    Writer: string;
    Field: string;
  end;

  /// <summary>Aufrufstelle im Rumpf: Ziel und Bereich des Namens; Write = Zuweisung an eine Property.</summary>
  TEdge = record
    Target: TRoutineInfo;
    Range: TTextRange;
    PropertyName: string;
    Write: Boolean;
  end;

  TRoutineInfo = class
  public
    Key: string;
    Name: string;
    Owner: string;
    NameRange: TTextRange;
    IsFunction: Boolean;
    Nodes: TArray<TSyntaxNode>;
    Parent: TRoutineInfo;
    Locals: TArray<TRoutineInfo>;
    Hidden: TArray<string>;
    Edges: TArray<TEdge>;
  end;

  TGraph = class
  private
    FTree: TSyntaxTree;
    FRoutines: TObjectList<TRoutineInfo>;
    FByKey: TDictionary<string, TRoutineInfo>;
    FProperties: TObjectDictionary<string, TPropertyInfo>;
    FFields: TDictionary<string, string>;
    procedure CollectTypes;
    procedure CollectRoutines;
    procedure AddRoutine(ANode: TSyntaxNode; AParent: TRoutineInfo);
    procedure CollectEdges(ARoutine: TRoutineInfo);
    function Hides(ARoutine: TRoutineInfo; const AName: string): Boolean;
    function LocalRoutine(ARoutine: TRoutineInfo; const AName: string): TRoutineInfo;
    function Member(const AOwner, AName: string): TRoutineInfo;
    function PropertyOf(const AOwner, AName: string): TPropertyInfo;
    procedure Resolve(ARoutine: TRoutineInfo; ANode: TSyntaxNode; const AName: string; ASelf: Boolean;
      const ARange: TTextRange);
  public
    constructor Create(ATree: TSyntaxTree);
    destructor Destroy; override;
    property Routines: TObjectList<TRoutineInfo> read FRoutines;
  end;

const
  TypeBodies = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.HelperType];

/// <summary>Name ohne generische Parameter: "TFoo&lt;T&gt;.Bar" → "TFoo.Bar".</summary>
function PlainName(const AName: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(AName) do
    if AName[Index] = '<' then
      Inc(Depth)
    else if AName[Index] = '>' then
      Dec(Depth)
    else if (Depth <= 0) and (AName[Index] <> ' ') then
      Result := Result + AName[Index];
end;

/// <summary>Teil vor dem letzten Punkt, '' ohne Punkt.</summary>
function OwnerPart(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := Length(AName) downto 1 do
    if AName[Index] = '.' then
      Exit(Copy(AName, 1, Index - 1));
end;

/// <summary>Teil hinter dem letzten Punkt.</summary>
function LastPart(const AName: string): string;
var
  Index: Integer;
begin
  Result := AName;
  for Index := Length(AName) downto 1 do
    if AName[Index] = '.' then
      Exit(Copy(AName, Index + 1, MaxInt));
end;

/// <summary>Namen einer Deklaration mit Komma-Liste ("A, B") einzeln.</summary>
function NamesOf(const ANames: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in ANames.Split([',']) do
    if Trim(Part) <> '' then
      Result := Result + [UpperCase(Trim(Part))];
end;

/// <summary>Qualifizierter Name der Typen um ANode, z. B. "TFoo.TInner".</summary>
function TypeOwner(ANode: TSyntaxNode): string;
var
  Parent: TSyntaxNode;
begin
  Result := '';
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    if Parent.Kind = TSyntaxKind.TypeDecl then
    begin
      if Result = '' then
        Result := PlainName(Parent.Name)
      else
        Result := PlainName(Parent.Name) + '.' + Result;
    end;
    Parent := Parent.Parent;
  end;
end;

function FirstToken(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Left, Right, Middle: Integer;
begin
  Left := 0;
  Right := Length(ATokens);
  while Left < Right do
  begin
    Middle := (Left + Right) div 2;
    if ATokens[Middle].Offset < AOffset then
      Left := Middle + 1
    else
      Right := Middle;
  end;
  Result := Left;
end;

/// <summary>Bereich des Namens im Kopf (letzter Bezeichner der Punktkette vor der Parameterliste).</summary>
function HeaderNameRange(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TTextRange;
var
  Index: Integer;
  Seen: Boolean;
begin
  Result := TTextRange.Create(AHeader.StartPos, AHeader.StartPos);
  Seen := False;
  Index := FirstToken(ATokens, AHeader.StartOffset);
  while (Index < Length(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) do
  begin
    if ATokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      Result := TTextRange.Create(ATokens[Index].StartPos, ATokens[Index].EndPos);
      Seen := True;
    end
    else if Seen and (ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol(':') or
      ATokens[Index].IsSymbol(';')) then
      Break;
    Inc(Index);
  end;
end;

/// <summary>Bereich des Namens AName am Ende von ANode (Bezeichner oder Self.Name).</summary>
function TailRange(ANode: TSyntaxNode; const AName: string): TTextRange;
begin
  if ANode.EndPos.Line = ANode.StartPos.Line then
    Result := TTextRange.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(AName), ANode.EndPos.Line,
      ANode.EndPos.Character)
  else
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TGraph }

constructor TGraph.Create(ATree: TSyntaxTree);
var
  Routine: TRoutineInfo;
begin
  inherited Create;
  FTree := ATree;
  FRoutines := TObjectList<TRoutineInfo>.Create(True);
  FByKey := TDictionary<string, TRoutineInfo>.Create;
  FProperties := TObjectDictionary<string, TPropertyInfo>.Create([doOwnsValues]);
  FFields := TDictionary<string, string>.Create;
  CollectTypes;
  CollectRoutines;
  for Routine in FRoutines do
    CollectEdges(Routine);
end;

destructor TGraph.Destroy;
begin
  FFields.Free;
  FProperties.Free;
  FByKey.Free;
  FRoutines.Free;
  inherited Destroy;
end;

procedure TGraph.CollectTypes;
var
  Stack: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Info: TPropertyInfo;
  Owner, Name, Text: string;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := FTree.Tokens;
  Stack := TStack<TSyntaxNode>.Create;
  try
    Stack.Push(FTree.Root);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if (Node.Kind = TSyntaxKind.PropertyDecl) and (Node.Parent <> nil) and (Node.Parent.Kind in TypeBodies) then
      begin
        Info := TPropertyInfo.Create;
        Info.Name := Node.Name;
        // read/write stehen nicht im Baum, nur in den Token der Deklaration.
        Index := FirstToken(Tokens, Node.StartOffset);
        while (Index < Length(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) do
        begin
          Text := LowerCase(Tokens[Index].Text);
          if ((Text = 'read') or (Text = 'write')) and (Index + 1 < Length(Tokens)) and
            (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
          begin
            if Text = 'read' then
              Info.Reader := Tokens[Index + 1].Text
            else
              Info.Writer := Tokens[Index + 1].Text;
          end;
          Inc(Index);
        end;
        Name := UpperCase(TypeOwner(Node) + '.' + Node.Name);
        FProperties.AddOrSetValue(Name, Info);
        Continue;
      end;
      if (Node.Kind = TSyntaxKind.Field) and (Node.Parent <> nil) and (Node.Parent.Kind in TypeBodies) then
      begin
        Owner := TypeOwner(Node);
        for Name in Node.Name.Split([',']) do
          if Trim(Name) <> '' then
            FFields.AddOrSetValue(UpperCase(Owner + '.' + Trim(Name)), Trim(Name));
        Continue;
      end;
      if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.RoutineDecl] then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do
        Stack.Push(Node[Index]);
    end;
  finally
    Stack.Free;
  end;
  // Feldvorschlag je Property (#910): das Feld aus read bzw. write der Deklaration,
  // sonst F<Name> derselben Klasse.
  for Name in FProperties.Keys do
    if FFields.TryGetValue(OwnerPart(Name) + '.' + UpperCase(FProperties[Name].Reader), Text) or
      FFields.TryGetValue(OwnerPart(Name) + '.' + UpperCase(FProperties[Name].Writer), Text) or
      FFields.TryGetValue(OwnerPart(Name) + '.F' + LastPart(Name), Text) then
      FProperties[Name].Field := Text;
end;

procedure TGraph.CollectRoutines;
var
  Stack: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Stack := TStack<TSyntaxNode>.Create;
  try
    Stack.Push(FTree.Root);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        AddRoutine(Node, nil);
        Continue;
      end;
      if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] + TypeBodies then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do
        Stack.Push(Node[Index]);
    end;
  finally
    Stack.Free;
  end;
end;

procedure TGraph.AddRoutine(ANode: TSyntaxNode; AParent: TRoutineInfo);
var
  Info: TRoutineInfo;
  Header, Child, Item: TSyntaxNode;
  Name, Key: string;
  Index, ItemIndex: Integer;
begin
  if ANode.FindChild(TSyntaxKind.Block) = nil then
    Exit;
  Name := PlainName(ANode.Name);
  if AParent <> nil then
    Key := AParent.Key + '.' + UpperCase(Name)
  else
    Key := UpperCase(Name);
  if not FByKey.TryGetValue(Key, Info) then
  begin
    Info := TRoutineInfo.Create;
    FRoutines.Add(Info);
    FByKey.Add(Key, Info);
    Info.Key := Key;
    Info.Parent := AParent;
    if AParent <> nil then
    begin
      Info.Name := AParent.Name + '.' + Name;
      Info.Owner := AParent.Owner;
      AParent.Locals := AParent.Locals + [Info];
    end
    else
    begin
      Info.Name := Name;
      Info.Owner := OwnerPart(Name);
    end;
    Header := ANode.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
    begin
      Info.NameRange := HeaderNameRange(FTree.Tokens, Header);
      Info.IsFunction := Header.FindChild(TSyntaxKind.TypeReference) <> nil;
    end
    else
      Info.NameRange := TTextRange.Create(ANode.StartPos, ANode.StartPos);
  end;
  Info.Nodes := Info.Nodes + [ANode];
  // Verdeckende Namen: Parameter, Variablen und Konstanten der Routine.
  Header := ANode.FindChild(TSyntaxKind.RoutineHeader);
  if Header <> nil then
  begin
    Child := Header.FindChild(TSyntaxKind.Parameters);
    if Child <> nil then
      for Index := 0 to Child.ChildCount - 1 do
        if Child[Index].Kind = TSyntaxKind.Parameter then
          Info.Hidden := Info.Hidden + NamesOf(Child[Index].Name);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
      for ItemIndex := 0 to Child.ChildCount - 1 do
      begin
        Item := Child[ItemIndex];
        if Item.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl] then
          Info.Hidden := Info.Hidden + NamesOf(Item.Name);
      end
    else if Child.Kind = TSyntaxKind.RoutineDecl then
      AddRoutine(Child, Info);
  end;
end;

function TGraph.Hides(ARoutine: TRoutineInfo; const AName: string): Boolean;
var
  Routine: TRoutineInfo;
  Name: string;
begin
  if SameText(AName, 'Result') or SameText(AName, 'Self') then
    Exit(True);
  Routine := ARoutine;
  while Routine <> nil do
  begin
    for Name in Routine.Hidden do
      if Name = UpperCase(AName) then
        Exit(True);
    Routine := Routine.Parent;
  end;
  Result := False;
end;

function TGraph.LocalRoutine(ARoutine: TRoutineInfo; const AName: string): TRoutineInfo;
var
  Routine, Local: TRoutineInfo;
begin
  // Die Routine selbst, ihre lokalen Routinen und die der umgebenden.
  Routine := ARoutine;
  while Routine <> nil do
  begin
    if (Routine.Parent <> nil) and SameText(LastPart(Routine.Name), AName) then
      Exit(Routine);
    for Local in Routine.Locals do
      if SameText(LastPart(Local.Name), AName) then
        Exit(Local);
    Routine := Routine.Parent;
  end;
  Result := nil;
end;

function TGraph.Member(const AOwner, AName: string): TRoutineInfo;
var
  Key: string;
begin
  Key := UpperCase(AName);
  if AOwner <> '' then
    Key := UpperCase(AOwner) + '.' + Key;
  if (AName = '') or not FByKey.TryGetValue(Key, Result) then
    Result := nil;
end;

function TGraph.PropertyOf(const AOwner, AName: string): TPropertyInfo;
begin
  if not FProperties.TryGetValue(UpperCase(AOwner + '.' + AName), Result) then
    Result := nil;
end;

/// <summary>Steht ANode an einer Aufrufstelle (Anweisung oder Funktor eines Aufrufs)?</summary>
function AtCallSite(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  Result := (Parent <> nil) and ((Parent.Kind = TSyntaxKind.CallStatement) or
    ((Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount > 0) and (Parent[0] = ANode)));
end;

/// <summary>Ist ANode das Ziel einer Zuweisung?</summary>
function IsAssigned(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  Result := (Parent <> nil) and (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent.ChildCount > 0) and
    (Parent[0] = ANode);
end;

procedure TGraph.Resolve(ARoutine: TRoutineInfo; ANode: TSyntaxNode; const AName: string; ASelf: Boolean;
  const ARange: TTextRange);
var
  Target: TRoutineInfo;
  Prop: TPropertyInfo;
  Edge: TEdge;
  Written: Boolean;
begin
  if (AName = '') or (ANode.Parent = nil) or (ANode.Parent.Kind = TSyntaxKind.AddressOf) then
    Exit;
  Written := IsAssigned(ANode);
  Target := nil;
  Prop := nil;
  if not ASelf then
  begin
    if Hides(ARoutine, AName) then
      Exit;
    Target := LocalRoutine(ARoutine, AName);
  end;
  if (Target = nil) and (ARoutine.Owner <> '') then
  begin
    Prop := PropertyOf(ARoutine.Owner, AName);
    if Prop <> nil then
    begin
      if Written then
        Target := Member(ARoutine.Owner, Prop.Writer)
      else
        Target := Member(ARoutine.Owner, Prop.Reader);
      if Target = nil then
        Exit;
    end
    else
      Target := Member(ARoutine.Owner, AName);
  end;
  if (Target = nil) and not ASelf then
    Target := Member('', AName);
  if Target = nil then
    Exit;
  if Prop = nil then
  begin
    // Zuweisung an den eigenen Namen ist das Funktionsergebnis; ein Prozedurname außerhalb einer Aufrufstelle
    // ein Methodenzeiger.
    if Written then
      Exit;
    if not Target.IsFunction and not AtCallSite(ANode) then
      Exit;
  end;
  Edge := Default(TEdge);
  Edge.Target := Target;
  Edge.Range := ARange;
  Edge.Write := Written;
  if Prop <> nil then
    Edge.PropertyName := Prop.Name;
  ARoutine.Edges := ARoutine.Edges + [Edge];
end;

procedure TGraph.CollectEdges(ARoutine: TRoutineInfo);
var
  Stack: TStack<TSyntaxNode>;
  Node, Body: TSyntaxNode;
  Declaration: TSyntaxNode;
  Index: Integer;
begin
  Stack := TStack<TSyntaxNode>.Create;
  try
    for Declaration in ARoutine.Nodes do
    begin
      Body := Declaration.FindChild(TSyntaxKind.Block);
      if Body <> nil then
        Stack.Push(Body);
    end;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      case Node.Kind of
        // Nicht verfolgt: Vorfahr, spätere Ausführung, unklare Bindung.
        TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock,
          TSyntaxKind.RoutineDecl:
          Continue;
        TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
          ARoutine.Hidden := ARoutine.Hidden + NamesOf(Node.Name);
        TSyntaxKind.Identifier:
          Resolve(ARoutine, Node, Node.Name, False, TTextRange.Create(Node.StartPos, Node.EndPos));
        TSyntaxKind.MemberAccess:
          begin
            // Self.X: Mitglied der eigenen Klasse; andere Empfänger nur durchsuchen.
            if (Node.ChildCount > 0) and (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, 'Self') then
            begin
              Resolve(ARoutine, Node, Node.Name, True, TailRange(Node, Node.Name));
              Continue;
            end;
          end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
        Stack.Push(Node[Index]);
    end;
  finally
    Stack.Free;
  end;
end;

{ TRecursionAnalysis }

function StepOf(ARoutine: TRoutineInfo): TRecursionStep;
begin
  Result.Name := ARoutine.Name;
  Result.Range := ARoutine.NameRange;
end;

/// <summary>Kürzester Weg von AFrom nach ATo mit höchstens AMaxEdges Kanten (Breitensuche); nil ohne.</summary>
function PathTo(AFrom, ATo: TRoutineInfo; AMaxEdges: Integer): TArray<TRoutineInfo>;
var
  Previous: TDictionary<TRoutineInfo, TRoutineInfo>;
  Level, Next: TList<TRoutineInfo>;
  Current, Step: TRoutineInfo;
  Edge: TEdge;
  Depth: Integer;
  Found: Boolean;
begin
  Result := nil;
  if AFrom = ATo then
  begin
    Result := [AFrom];
    Exit;
  end;
  Previous := TDictionary<TRoutineInfo, TRoutineInfo>.Create;
  Level := TList<TRoutineInfo>.Create;
  Next := TList<TRoutineInfo>.Create;
  try
    Previous.Add(AFrom, nil);
    Level.Add(AFrom);
    Found := False;
    Depth := 0;
    while not Found and (Level.Count > 0) and (Depth < AMaxEdges) do
    begin
      Inc(Depth);
      Next.Clear;
      for Current in Level do
      begin
        for Edge in Current.Edges do
          if not Previous.ContainsKey(Edge.Target) then
          begin
            Previous.Add(Edge.Target, Current);
            if Edge.Target = ATo then
            begin
              Found := True;
              Break;
            end;
            Next.Add(Edge.Target);
          end;
        if Found then
          Break;
      end;
      Level.Clear;
      Level.AddRange(Next);
    end;
    if not Found then
      Exit;
    Step := ATo;
    while Step <> nil do
    begin
      Result := [Step] + Result;
      Step := Previous[Step];
    end;
  finally
    Next.Free;
    Level.Free;
    Previous.Free;
  end;
end;

class function TRecursionAnalysis.Calls(ATree: TSyntaxTree; AMaxDepth: Integer): TArray<TRecursiveCall>;
var
  Graph: TGraph;
  Routine, Step: TRoutineInfo;
  Edge: TEdge;
  Path: TArray<TRoutineInfo>;
  Call: TRecursiveCall;
  Depth: Integer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Depth := AMaxDepth;
  if Depth < MinDepth then
    Depth := MinDepth;
  if Depth > MaxDepth then
    Depth := MaxDepth;
  Graph := TGraph.Create(ATree);
  try
    for Routine in Graph.Routines do
      for Edge in Routine.Edges do
      begin
        // Kreis Routine → Ziel → … → Routine aus höchstens Depth Routinen.
        Path := PathTo(Edge.Target, Routine, Depth - 1);
        if Path = nil then
          Continue;
        Call := Default(TRecursiveCall);
        Call.Range := Edge.Range;
        Call.Chain := [StepOf(Routine)];
        for Step in Path do
          Call.Chain := Call.Chain + [StepOf(Step)];
        Result := Result + [Call];
      end;
  finally
    Graph.Free;
  end;
end;

class function TRecursionAnalysis.AccessorTraps(ATree: TSyntaxTree): TArray<TAccessorTrap>;
var
  Graph: TGraph;
  Routine: TRoutineInfo;
  Edge: TEdge;
  Trap: TAccessorTrap;
  Prop: TPropertyInfo;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Graph := TGraph.Create(ATree);
  try
    for Routine in Graph.Routines do
      for Edge in Routine.Edges do
      begin
        // Zugriff auf eine Property, deren Accessor die Routine selbst ist.
        if (Edge.PropertyName = '') or (Edge.Target <> Routine) then
          Continue;
        Prop := Graph.PropertyOf(Routine.Owner, Edge.PropertyName);
        if Prop = nil then
          Continue;
        Trap := Default(TAccessorTrap);
        Trap.Range := Edge.Range;
        Trap.PropertyName := Prop.Name;
        Trap.Accessor := LastPart(Routine.Name);
        Trap.IsSetter := Edge.Write;
        Trap.Field := Prop.Field;
        Result := Result + [Trap];
      end;
  finally
    Graph.Free;
  end;
end;

class function TRecursionAnalysis.ChainText(const ACall: TRecursiveCall): string;
var
  Step: TRecursionStep;
begin
  Result := '';
  for Step in ACall.Chain do
  begin
    if Result <> '' then
      Result := Result + ' → ';
    Result := Result + LastPart(Step.Name);
  end;
end;

end.
