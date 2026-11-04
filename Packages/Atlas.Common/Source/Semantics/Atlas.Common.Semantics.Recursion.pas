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
    /// <summary>Property ANode mit read und write aus den Token der Deklaration eintragen.</summary>
    procedure AddProperty(ANode: TSyntaxNode);
    /// <summary>Die Felder der Deklaration ANode eintragen.</summary>
    procedure AddFields(ANode: TSyntaxNode);
    /// <summary>Feldvorschlag je Property (#910).</summary>
    procedure LinkPropertyFields;
    /// <summary>Eintrag der Routine ANode (lokal in AParent), beim ersten Mal angelegt.</summary>
    function RoutineInfoFor(ANode: TSyntaxNode; AParent: TRoutineInfo): TRoutineInfo;
    /// <summary>Mitglied AName der Klasse AOwner; bei einer Property deren read bzw. write (AProp).</summary>
    function OwnerTarget(const AOwner, AName: string; AWritten: Boolean; out AProp: TPropertyInfo): TRoutineInfo;
    /// <summary>Routine hinter AName in ARoutine; nil ohne oder bei einem verdeckenden Namen.</summary>
    function FindTarget(ARoutine: TRoutineInfo; const AName: string; ASelf, AWritten: Boolean;
      out AProp: TPropertyInfo): TRoutineInfo;
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
  begin
    if AName[Index] = '<' then
    begin
      Inc(Depth);
    end
    else if AName[Index] = '>' then
    begin
      Dec(Depth);
    end
    else if (Depth <= 0) and (AName[Index] <> ' ') then
    begin
      Result := Result + AName[Index];
    end;
  end;
end;

/// <summary>Teil vor dem letzten Punkt, '' ohne Punkt.</summary>
function OwnerPart(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := Length(AName) downto 1 do
  begin
    if AName[Index] = '.' then
    begin
      Exit(Copy(AName, 1, Index - 1));
    end;
  end;
end;

/// <summary>Teil hinter dem letzten Punkt.</summary>
function LastPart(const AName: string): string;
var
  Index: Integer;
begin
  Result := AName;
  for Index := Length(AName) downto 1 do
  begin
    if AName[Index] = '.' then
    begin
      Exit(Copy(AName, Index + 1, MaxInt));
    end;
  end;
end;

/// <summary>Namen einer Deklaration mit Komma-Liste ("A, B") einzeln.</summary>
function NamesOf(const ANames: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in ANames.Split([',']) do
  begin
    if Trim(Part) <> '' then
    begin
      Result := Result + [UpperCase(Trim(Part))];
    end;
  end;
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
      begin
        Result := PlainName(Parent.Name);
      end
      else
      begin
        Result := PlainName(Parent.Name) + '.' + Result;
      end;
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
    begin
      Left := Middle + 1;
    end
    else
    begin
      Right := Middle;
    end;
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
    begin
      Break;
    end;
    Inc(Index);
  end;
end;

/// <summary>Bereich des Namens AName am Ende von ANode (Bezeichner oder Self.Name).</summary>
function TailRange(ANode: TSyntaxNode; const AName: string): TTextRange;
begin
  if ANode.EndPos.Line = ANode.StartPos.Line then
  begin
    Result := TTextRange.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(AName), ANode.EndPos.Line,
      ANode.EndPos.Character);
  end
  else
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;
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
  begin
    CollectEdges(Routine);
  end;
end;

destructor TGraph.Destroy;
begin
  FFields.Free;
  FProperties.Free;
  FByKey.Free;
  FRoutines.Free;
  inherited Destroy;
end;

/// <summary>Bezeichner hinter read bzw. write in den Token AFirst bis vor AEnd.</summary>
procedure ReadAccessors(const ATokens: TArray<TPascalToken>; AFirst, AEnd: Integer; AInfo: TPropertyInfo);
var
  mIndex: Integer;
  mText: string;
begin
  mIndex := AFirst;
  while (mIndex + 1 < Length(ATokens)) and (ATokens[mIndex].Offset < AEnd) do
  begin
    mText := LowerCase(ATokens[mIndex].Text);
    if ATokens[mIndex + 1].Kind = TPascalTokenKind.Identifier then
    begin
      if mText = 'read' then
      begin
        AInfo.Reader := ATokens[mIndex + 1].Text;
      end
      else if mText = 'write' then
      begin
        AInfo.Writer := ATokens[mIndex + 1].Text;
      end;
    end;
    Inc(mIndex);
  end;
end;

procedure TGraph.AddProperty(ANode: TSyntaxNode);
var
  mInfo: TPropertyInfo;
begin
  mInfo := TPropertyInfo.Create;
  mInfo.Name := ANode.Name;
  // read/write stehen nicht im Baum, nur in den Token der Deklaration.
  ReadAccessors(FTree.Tokens, FirstToken(FTree.Tokens, ANode.StartOffset), ANode.EndOffset, mInfo);
  FProperties.AddOrSetValue(UpperCase(TypeOwner(ANode) + '.' + ANode.Name), mInfo);
end;

procedure TGraph.AddFields(ANode: TSyntaxNode);
var
  mOwner, mName: string;
begin
  mOwner := TypeOwner(ANode);
  for mName in ANode.Name.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      FFields.AddOrSetValue(UpperCase(mOwner + '.' + Trim(mName)), Trim(mName));
    end;
  end;
end;

procedure TGraph.LinkPropertyFields;
var
  mName, mField: string;
begin
  // Das Feld aus read bzw. write der Deklaration, sonst F<Name> derselben Klasse.
  for mName in FProperties.Keys do
  begin
    if FFields.TryGetValue(OwnerPart(mName) + '.' + UpperCase(FProperties[mName].Reader), mField) or
      FFields.TryGetValue(OwnerPart(mName) + '.' + UpperCase(FProperties[mName].Writer), mField) or
      FFields.TryGetValue(OwnerPart(mName) + '.F' + LastPart(mName), mField) then
    begin
      FProperties[mName].Field := mField;
    end;
  end;
end;

/// <summary>ANode ist eine Deklaration der Art AKind in einem Klassen-, Record- oder Helper-Rumpf.</summary>
function IsTypeMember(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
begin
  Result := (ANode.Kind = AKind) and (ANode.Parent <> nil) and (ANode.Parent.Kind in TypeBodies);
end;

procedure TGraph.CollectTypes;
var
  mStack: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(FTree.Root);
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if IsTypeMember(mNode, TSyntaxKind.PropertyDecl) then
      begin
        AddProperty(mNode);
      end
      else if IsTypeMember(mNode, TSyntaxKind.Field) then
      begin
        AddFields(mNode);
      end
      else if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.RoutineDecl]) then
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mStack.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mStack.Free;
  end;
  LinkPropertyFields;
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
      begin
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Stack.Push(Node[Index]);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

function TGraph.RoutineInfoFor(ANode: TSyntaxNode; AParent: TRoutineInfo): TRoutineInfo;
var
  mHeader: TSyntaxNode;
  mName, mKey: string;
begin
  mName := PlainName(ANode.Name);
  mKey := UpperCase(mName);
  if AParent <> nil then
  begin
    mKey := AParent.Key + '.' + mKey;
  end;
  if FByKey.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := TRoutineInfo.Create;
  FRoutines.Add(Result);
  FByKey.Add(mKey, Result);
  Result.Key := mKey;
  Result.Parent := AParent;
  Result.Name := mName;
  Result.Owner := OwnerPart(mName);
  if AParent <> nil then
  begin
    Result.Name := AParent.Name + '.' + mName;
    Result.Owner := AParent.Owner;
    AParent.Locals := AParent.Locals + [Result];
  end;
  Result.NameRange := TTextRange.Create(ANode.StartPos, ANode.StartPos);
  mHeader := ANode.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    Result.NameRange := HeaderNameRange(FTree.Tokens, mHeader);
    Result.IsFunction := mHeader.FindChild(TSyntaxKind.TypeReference) <> nil;
  end;
end;

/// <summary>Namen der Parameter im Kopf der Routine ANode.</summary>
function ParameterNames(ANode: TSyntaxNode): TArray<string>;
var
  mHeader, mParameters: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mHeader := ANode.FindChild(TSyntaxKind.RoutineHeader);
  mParameters := nil;
  if mHeader <> nil then
  begin
    mParameters := mHeader.FindChild(TSyntaxKind.Parameters);
  end;
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    if mParameters[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      Result := Result + NamesOf(mParameters[mIndex].Name);
    end;
  end;
end;

/// <summary>Namen der Variablen und Konstanten aus dem Abschnitt ASection.</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl] then
    begin
      Result := Result + NamesOf(ASection[mIndex].Name);
    end;
  end;
end;

procedure TGraph.AddRoutine(ANode: TSyntaxNode; AParent: TRoutineInfo);
var
  mInfo: TRoutineInfo;
  mChild: TSyntaxNode;
  mIndex: Integer;
begin
  if ANode.FindChild(TSyntaxKind.Block) = nil then
  begin
    Exit;
  end;
  mInfo := RoutineInfoFor(ANode, AParent);
  mInfo.Nodes := mInfo.Nodes + [ANode];
  // Verdeckende Namen: Parameter, Variablen und Konstanten der Routine.
  mInfo.Hidden := mInfo.Hidden + ParameterNames(ANode);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if mChild.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
    begin
      mInfo.Hidden := mInfo.Hidden + SectionNames(mChild);
    end
    else if mChild.Kind = TSyntaxKind.RoutineDecl then
    begin
      AddRoutine(mChild, mInfo);
    end;
  end;
end;

function TGraph.Hides(ARoutine: TRoutineInfo; const AName: string): Boolean;
var
  Routine: TRoutineInfo;
  Name: string;
begin
  if SameText(AName, 'Result') or SameText(AName, 'Self') then
  begin
    Exit(True);
  end;
  Routine := ARoutine;
  while Routine <> nil do
  begin
    for Name in Routine.Hidden do
    begin
      if Name = UpperCase(AName) then
      begin
        Exit(True);
      end;
    end;
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
    begin
      Exit(Routine);
    end;
    for Local in Routine.Locals do
    begin
      if SameText(LastPart(Local.Name), AName) then
      begin
        Exit(Local);
      end;
    end;
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
  begin
    Key := UpperCase(AOwner) + '.' + Key;
  end;
  if (AName = '') or not FByKey.TryGetValue(Key, Result) then
  begin
    Result := nil;
  end;
end;

function TGraph.PropertyOf(const AOwner, AName: string): TPropertyInfo;
begin
  if not FProperties.TryGetValue(UpperCase(AOwner + '.' + AName), Result) then
  begin
    Result := nil;
  end;
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

function TGraph.OwnerTarget(const AOwner, AName: string; AWritten: Boolean;
  out AProp: TPropertyInfo): TRoutineInfo;
begin
  AProp := PropertyOf(AOwner, AName);
  if AProp = nil then
  begin
    Result := Member(AOwner, AName);
  end
  else if AWritten then
  begin
    Result := Member(AOwner, AProp.Writer);
  end
  else
  begin
    Result := Member(AOwner, AProp.Reader);
  end;
end;

function TGraph.FindTarget(ARoutine: TRoutineInfo; const AName: string; ASelf, AWritten: Boolean;
  out AProp: TPropertyInfo): TRoutineInfo;
begin
  AProp := nil;
  Result := nil;
  if not ASelf then
  begin
    if Hides(ARoutine, AName) then
    begin
      Exit;
    end;
    Result := LocalRoutine(ARoutine, AName);
  end;
  if (Result = nil) and (ARoutine.Owner <> '') then
  begin
    Result := OwnerTarget(ARoutine.Owner, AName, AWritten, AProp);
  end;
  // Eine Property ohne passendes read bzw. write führt nirgends hin.
  if (Result = nil) and (AProp = nil) and not ASelf then
  begin
    Result := Member('', AName);
  end;
end;

/// <summary>Führt der Name ANode zu ATarget? Ohne Property: Zuweisung an den eigenen Namen ist das
/// Funktionsergebnis, ein Prozedurname außerhalb einer Aufrufstelle ein Methodenzeiger.</summary>
function IsEdge(ATarget: TRoutineInfo; AProp: TPropertyInfo; AWritten: Boolean; ANode: TSyntaxNode): Boolean;
begin
  Result := (AProp <> nil) or (not AWritten and (ATarget.IsFunction or AtCallSite(ANode)));
end;

procedure TGraph.Resolve(ARoutine: TRoutineInfo; ANode: TSyntaxNode; const AName: string; ASelf: Boolean;
  const ARange: TTextRange);
var
  mTarget: TRoutineInfo;
  mProp: TPropertyInfo;
  mEdge: TEdge;
  mWritten: Boolean;
begin
  if (AName = '') or (ANode.Parent = nil) or (ANode.Parent.Kind = TSyntaxKind.AddressOf) then
  begin
    Exit;
  end;
  mWritten := IsAssigned(ANode);
  mTarget := FindTarget(ARoutine, AName, ASelf, mWritten, mProp);
  if (mTarget = nil) or not IsEdge(mTarget, mProp, mWritten, ANode) then
  begin
    Exit;
  end;
  mEdge := Default(TEdge);
  mEdge.Target := mTarget;
  mEdge.Range := ARange;
  mEdge.Write := mWritten;
  if mProp <> nil then
  begin
    mEdge.PropertyName := mProp.Name;
  end;
  ARoutine.Edges := ARoutine.Edges + [mEdge];
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
      begin
        Stack.Push(Body);
      end;
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
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Stack.Push(Node[Index]);
      end;
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

/// <summary>Noch nicht erreichte Ziele der Kanten von ACurrent in APrevious und ANext; True, wenn ATo dabei ist.
/// </summary>
function ExpandEdges(ACurrent, ATo: TRoutineInfo; APrevious: TDictionary<TRoutineInfo, TRoutineInfo>;
  ANext: TList<TRoutineInfo>): Boolean;
var
  mEdge: TEdge;
begin
  for mEdge in ACurrent.Edges do
  begin
    if APrevious.ContainsKey(mEdge.Target) then
    begin
      Continue;
    end;
    APrevious.Add(mEdge.Target, ACurrent);
    if mEdge.Target = ATo then
    begin
      Exit(True);
    end;
    ANext.Add(mEdge.Target);
  end;
  Result := False;
end;

/// <summary>Eine Stufe der Breitensuche: ALevel wird zur nächsten Stufe; True, wenn ATo erreicht ist.</summary>
function ExpandLevel(ALevel: TList<TRoutineInfo>; ATo: TRoutineInfo;
  APrevious: TDictionary<TRoutineInfo, TRoutineInfo>): Boolean;
var
  mNext: TList<TRoutineInfo>;
  mCurrent: TRoutineInfo;
begin
  Result := False;
  mNext := TList<TRoutineInfo>.Create;
  try
    for mCurrent in ALevel do
    begin
      if ExpandEdges(mCurrent, ATo, APrevious, mNext) then
      begin
        Result := True;
        Break;
      end;
    end;
    ALevel.Clear;
    ALevel.AddRange(mNext);
  finally
    mNext.Free;
  end;
end;

/// <summary>Weg zu ATo über die Vorgänger APrevious.</summary>
function PathBack(ATo: TRoutineInfo; APrevious: TDictionary<TRoutineInfo, TRoutineInfo>): TArray<TRoutineInfo>;
var
  mStep, mBefore: TRoutineInfo;
begin
  Result := nil;
  mStep := ATo;
  while mStep <> nil do
  begin
    Result := TArray<TRoutineInfo>.Create(mStep) + Result;
    if not APrevious.TryGetValue(mStep, mBefore) then
    begin
      mBefore := nil;
    end;
    mStep := mBefore;
  end;
end;

/// <summary>Kürzester Weg von AFrom nach ATo mit höchstens AMaxEdges Kanten (Breitensuche); nil ohne.</summary>
function PathTo(AFrom, ATo: TRoutineInfo; AMaxEdges: Integer): TArray<TRoutineInfo>;
var
  mPrevious: TDictionary<TRoutineInfo, TRoutineInfo>;
  mLevel: TList<TRoutineInfo>;
  mDepth: Integer;
  mFound: Boolean;
begin
  Result := nil;
  if AFrom = ATo then
  begin
    Result := TArray<TRoutineInfo>.Create(AFrom);
    Exit;
  end;
  mPrevious := TDictionary<TRoutineInfo, TRoutineInfo>.Create;
  mLevel := TList<TRoutineInfo>.Create;
  try
    mPrevious.Add(AFrom, nil);
    mLevel.Add(AFrom);
    mFound := False;
    mDepth := 0;
    while not mFound and (mLevel.Count > 0) and (mDepth < AMaxEdges) do
    begin
      Inc(mDepth);
      mFound := ExpandLevel(mLevel, ATo, mPrevious);
    end;
    if mFound then
    begin
      Result := PathBack(ATo, mPrevious);
    end;
  finally
    mLevel.Free;
    mPrevious.Free;
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
  begin
    Exit;
  end;
  Depth := AMaxDepth;
  if Depth < MinDepth then
  begin
    Depth := MinDepth;
  end;
  if Depth > MaxDepth then
  begin
    Depth := MaxDepth;
  end;
  Graph := TGraph.Create(ATree);
  try
    for Routine in Graph.Routines do
    begin
      for Edge in Routine.Edges do
      begin
        // Kreis Routine → Ziel → … → Routine aus höchstens Depth Routinen.
        Path := PathTo(Edge.Target, Routine, Depth - 1);
        if Path = nil then
        begin
          Continue;
        end;
        Call := Default(TRecursiveCall);
        Call.Range := Edge.Range;
        Call.Chain := [StepOf(Routine)];
        for Step in Path do
        begin
          Call.Chain := Call.Chain + [StepOf(Step)];
        end;
        Result := Result + [Call];
      end;
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
  begin
    Exit;
  end;
  Graph := TGraph.Create(ATree);
  try
    for Routine in Graph.Routines do
    begin
      for Edge in Routine.Edges do
      begin
        // Zugriff auf eine Property, deren Accessor die Routine selbst ist.
        if (Edge.PropertyName = '') or (Edge.Target <> Routine) then
        begin
          Continue;
        end;
        Prop := Graph.PropertyOf(Routine.Owner, Edge.PropertyName);
        if Prop = nil then
        begin
          Continue;
        end;
        Trap := Default(TAccessorTrap);
        Trap.Range := Edge.Range;
        Trap.PropertyName := Prop.Name;
        Trap.Accessor := LastPart(Routine.Name);
        Trap.IsSetter := Edge.Write;
        Trap.Field := Prop.Field;
        Result := Result + [Trap];
      end;
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
    begin
      Result := Result + ' → ';
    end;
    Result := Result + LastPart(Step.Name);
  end;
end;

end.
