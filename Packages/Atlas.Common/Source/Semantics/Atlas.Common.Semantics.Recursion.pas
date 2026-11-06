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
    cDefaultDepth = 4;
    cMinDepth = 1;
    cMaxDepth = 16;
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
  cTypeBodies = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.HelperType];

/// <summary>Name ohne generische Parameter: "TFoo&lt;T&gt;.Bar" → "TFoo.Bar".</summary>
function PlainName(const AName: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AName[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if (mDepth <= 0) and (AName[mIndex] <> ' ') then
    begin
      Result := Result + AName[mIndex];
    end;
  end;
end;

/// <summary>Teil vor dem letzten Punkt, '' ohne Punkt.</summary>
function OwnerPart(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := Length(AName) downto 1 do
  begin
    if AName[mIndex] = '.' then
    begin
      Exit(Copy(AName, 1, mIndex - 1));
    end;
  end;
end;

/// <summary>Teil hinter dem letzten Punkt.</summary>
function LastPart(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := AName;
  for mIndex := Length(AName) downto 1 do
  begin
    if AName[mIndex] = '.' then
    begin
      Exit(Copy(AName, mIndex + 1, MaxInt));
    end;
  end;
end;

/// <summary>Namen einer Deklaration mit Komma-Liste ("A, B") einzeln.</summary>
function NamesOf(const ANames: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in ANames.Split([',']) do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + [UpperCase(Trim(mPart))];
    end;
  end;
end;

/// <summary>Qualifizierter Name der Typen um ANode, z. B. "TFoo.TInner".</summary>
function TypeOwner(ANode: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
begin
  Result := '';
  mParent := ANode.Parent;
  while mParent <> nil do
  begin
    if mParent.Kind = TSyntaxKind.TypeDecl then
    begin
      if Result = '' then
      begin
        Result := PlainName(mParent.Name);
      end
      else
      begin
        Result := PlainName(mParent.Name) + '.' + Result;
      end;
    end;
    mParent := mParent.Parent;
  end;
end;

function FirstToken(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mLeft, mRight, mMiddle: Integer;
begin
  mLeft := 0;
  mRight := Length(ATokens);
  while mLeft < mRight do
  begin
    mMiddle := (mLeft + mRight) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      mLeft := mMiddle + 1;
    end
    else
    begin
      mRight := mMiddle;
    end;
  end;
  Result := mLeft;
end;

/// <summary>Bereich des Namens im Kopf (letzter Bezeichner der Punktkette vor der Parameterliste).</summary>
function HeaderNameRange(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TTextRange;
var
  mIndex: Integer;
  mSeen: Boolean;
begin
  Result := TTextRange.Create(AHeader.StartPos, AHeader.StartPos);
  mSeen := False;
  mIndex := FirstToken(ATokens, AHeader.StartOffset);
  while (mIndex < Length(ATokens)) and (ATokens[mIndex].Offset < AHeader.EndOffset) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      Result := TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos);
      mSeen := True;
    end
    else if mSeen and (ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol(':') or
      ATokens[mIndex].IsSymbol(';')) then
    begin
      Break;
    end;
    Inc(mIndex);
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
  mRoutine: TRoutineInfo;
begin
  inherited Create;
  FTree := ATree;
  FRoutines := TObjectList<TRoutineInfo>.Create(True);
  FByKey := TDictionary<string, TRoutineInfo>.Create;
  FProperties := TObjectDictionary<string, TPropertyInfo>.Create([doOwnsValues]);
  FFields := TDictionary<string, string>.Create;
  CollectTypes;
  CollectRoutines;
  for mRoutine in FRoutines do
  begin
    CollectEdges(mRoutine);
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
  Result := (ANode.Kind = AKind) and (ANode.Parent <> nil) and (ANode.Parent.Kind in cTypeBodies);
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
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        AddRoutine(mNode, nil);
        Continue;
      end;
      if mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] + cTypeBodies then
      begin
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack.Push(mNode[mIndex]);
      end;
    end;
  finally
    mStack.Free;
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
  mRoutine: TRoutineInfo;
  mName: string;
begin
  if SameText(AName, 'Result') or SameText(AName, 'Self') then
  begin
    Exit(True);
  end;
  mRoutine := ARoutine;
  while mRoutine <> nil do
  begin
    for mName in mRoutine.Hidden do
    begin
      if mName = UpperCase(AName) then
      begin
        Exit(True);
      end;
    end;
    mRoutine := mRoutine.Parent;
  end;
  Result := False;
end;

function TGraph.LocalRoutine(ARoutine: TRoutineInfo; const AName: string): TRoutineInfo;
var
  mRoutine, mLocal: TRoutineInfo;
begin
  // Die Routine selbst, ihre lokalen Routinen und die der umgebenden.
  mRoutine := ARoutine;
  while mRoutine <> nil do
  begin
    if (mRoutine.Parent <> nil) and SameText(LastPart(mRoutine.Name), AName) then
    begin
      Exit(mRoutine);
    end;
    for mLocal in mRoutine.Locals do
    begin
      if SameText(LastPart(mLocal.Name), AName) then
      begin
        Exit(mLocal);
      end;
    end;
    mRoutine := mRoutine.Parent;
  end;
  Result := nil;
end;

function TGraph.Member(const AOwner, AName: string): TRoutineInfo;
var
  mKey: string;
begin
  mKey := UpperCase(AName);
  if AOwner <> '' then
  begin
    mKey := UpperCase(AOwner) + '.' + mKey;
  end;
  if (AName = '') or not FByKey.TryGetValue(mKey, Result) then
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
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and ((mParent.Kind = TSyntaxKind.CallStatement) or
    ((mParent.Kind = TSyntaxKind.Call) and (mParent.ChildCount > 0) and (mParent[0] = ANode)));
end;

/// <summary>Ist ANode das Ziel einer Zuweisung?</summary>
function IsAssigned(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent.ChildCount > 0) and
    (mParent[0] = ANode);
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
  mStack: TStack<TSyntaxNode>;
  mNode, mBody: TSyntaxNode;
  mDeclaration: TSyntaxNode;
  mIndex: Integer;
begin
  mStack := TStack<TSyntaxNode>.Create;
  try
    for mDeclaration in ARoutine.Nodes do
    begin
      mBody := mDeclaration.FindChild(TSyntaxKind.Block);
      if mBody <> nil then
      begin
        mStack.Push(mBody);
      end;
    end;
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      case mNode.Kind of
        // Nicht verfolgt: Vorfahr, spätere Ausführung, unklare Bindung.
        TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock,
          TSyntaxKind.RoutineDecl:
          Continue;
        TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
          ARoutine.Hidden := ARoutine.Hidden + NamesOf(mNode.Name);
        TSyntaxKind.Identifier:
          Resolve(ARoutine, mNode, mNode.Name, False, TTextRange.Create(mNode.StartPos, mNode.EndPos));
        TSyntaxKind.MemberAccess:
          begin
            // Self.X: Mitglied der eigenen Klasse; andere Empfänger nur durchsuchen.
            if (mNode.ChildCount > 0) and (mNode[0].Kind = TSyntaxKind.Identifier) and SameText(mNode[0].Name, 'Self') then
            begin
              Resolve(ARoutine, mNode, mNode.Name, True, TailRange(mNode, mNode.Name));
              Continue;
            end;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack.Push(mNode[mIndex]);
      end;
    end;
  finally
    mStack.Free;
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
  mGraph: TGraph;
  mRoutine, mStep: TRoutineInfo;
  mEdge: TEdge;
  mPath: TArray<TRoutineInfo>;
  mCall: TRecursiveCall;
  mDepth: Integer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mDepth := AMaxDepth;
  if mDepth < cMinDepth then
  begin
    mDepth := cMinDepth;
  end;
  if mDepth > cMaxDepth then
  begin
    mDepth := cMaxDepth;
  end;
  mGraph := TGraph.Create(ATree);
  try
    for mRoutine in mGraph.Routines do
    begin
      for mEdge in mRoutine.Edges do
      begin
        // Kreis Routine → Ziel → … → Routine aus höchstens Depth Routinen.
        mPath := PathTo(mEdge.Target, mRoutine, mDepth - 1);
        if mPath = nil then
        begin
          Continue;
        end;
        mCall := Default(TRecursiveCall);
        mCall.Range := mEdge.Range;
        mCall.Chain := [StepOf(mRoutine)];
        for mStep in mPath do
        begin
          mCall.Chain := mCall.Chain + [StepOf(mStep)];
        end;
        Result := Result + [mCall];
      end;
    end;
  finally
    mGraph.Free;
  end;
end;

class function TRecursionAnalysis.AccessorTraps(ATree: TSyntaxTree): TArray<TAccessorTrap>;
var
  mGraph: TGraph;
  mRoutine: TRoutineInfo;
  mEdge: TEdge;
  mTrap: TAccessorTrap;
  mProp: TPropertyInfo;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mGraph := TGraph.Create(ATree);
  try
    for mRoutine in mGraph.Routines do
    begin
      for mEdge in mRoutine.Edges do
      begin
        // Zugriff auf eine Property, deren Accessor die Routine selbst ist.
        if (mEdge.PropertyName = '') or (mEdge.Target <> mRoutine) then
        begin
          Continue;
        end;
        mProp := mGraph.PropertyOf(mRoutine.Owner, mEdge.PropertyName);
        if mProp = nil then
        begin
          Continue;
        end;
        mTrap := Default(TAccessorTrap);
        mTrap.Range := mEdge.Range;
        mTrap.PropertyName := mProp.Name;
        mTrap.Accessor := LastPart(mRoutine.Name);
        mTrap.IsSetter := mEdge.Write;
        mTrap.Field := mProp.Field;
        Result := Result + [mTrap];
      end;
    end;
  finally
    mGraph.Free;
  end;
end;

class function TRecursionAnalysis.ChainText(const ACall: TRecursiveCall): string;
var
  mStep: TRecursionStep;
begin
  Result := '';
  for mStep in ACall.Chain do
  begin
    if Result <> '' then
    begin
      Result := Result + ' → ';
    end;
    Result := Result + LastPart(mStep.Name);
  end;
end;

end.
