unit Atlas.Common.Pascal.DeclaredTypes;

// Deklarierte Typen der Bezeichner einer Datei für typbasierte Regeln und Befehle (#153,
// Stufe 2): Variablen der Unit, Felder der Klassen, Parameter, lokale und
// Inline-Variablen. Ohne Namensauflösung über Units hinweg (#17): Was in der
// Datei nicht deklariert ist, hat den Typ ''. Die Regeln treffen dann keine
// Aussage.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TDeclaredTypes = class
  private type
    TScope = TDictionary<string, string>;
  private
    FText: string;
    FUnitScope: TScope;
    FClassScopes: TObjectDictionary<string, TScope>;
    FRoutineScopes: TObjectDictionary<TSyntaxNode, TScope>;
    FRoutines: TList<TSyntaxNode>;
    FInlineVars: TList<TSyntaxNode>;
    function TypeText(ANode: TSyntaxNode): string;
    procedure AddNames(AScope: TScope; ANode: TSyntaxNode);
    /// <summary>Sammelt die Deklarationen aus dem Baum; iterativ mit eigenem Rahmenstapel (Bericht M1).</summary>
    procedure Walk(ARoot: TSyntaxNode);
    function RoutineAt(const APosition: TTextPosition): TSyntaxNode;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string);
    destructor Destroy; override;
    /// <summary>Typ von AName an APosition als Quelltext, z. B. 'Integer' oder 'TArray&lt;Byte&gt;';
    /// '' wenn in der Datei nicht deklariert.</summary>
    function DeclaredType(const AName: string; const APosition: TTextPosition): string;
    /// <summary>Ganzzahltyp mit höchstens 32 Bit?</summary>
    class function IsInt32(const AType: string): Boolean; static;
    /// <summary>Int64 oder UInt64?</summary>
    class function IsInt64(const AType: string): Boolean; static;
    /// <summary>Gleitkommatyp (Single, Double, Extended, Real, TDateTime …)?</summary>
    class function IsFloat(const AType: string): Boolean; static;
    /// <summary>Zeichentyp (Char, WideChar, AnsiChar)?</summary>
    class function IsChar(const AType: string): Boolean; static;
    /// <summary>Zeiger, String oder dynamisches Array: SizeOf liefert die Größe des Zeigers.</summary>
    class function IsReference(const AType: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

{ TDeclaredTypes }

constructor TDeclaredTypes.Create(ATree: TSyntaxTree; const AText: string);
begin
  inherited Create;
  FText := AText;
  FUnitScope := TScope.Create;
  FClassScopes := TObjectDictionary<string, TScope>.Create([doOwnsValues]);
  FRoutineScopes := TObjectDictionary<TSyntaxNode, TScope>.Create([doOwnsValues]);
  FRoutines := TList<TSyntaxNode>.Create;
  FInlineVars := TList<TSyntaxNode>.Create;
  if (ATree <> nil) and (ATree.Root <> nil) then
    Walk(ATree.Root);
end;

destructor TDeclaredTypes.Destroy;
begin
  FInlineVars.Free;
  FRoutines.Free;
  FRoutineScopes.Free;
  FClassScopes.Free;
  FUnitScope.Free;
  inherited;
end;

function TDeclaredTypes.TypeText(ANode: TSyntaxNode): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.ClassOfType, TSyntaxKind.SetType, TSyntaxKind.RecordType, TSyntaxKind.ProcedureType,
      TSyntaxKind.FileType, TSyntaxKind.EnumType, TSyntaxKind.SubrangeType] then
      Exit(Trim(Copy(FText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset)));
  end;
end;

procedure TDeclaredTypes.AddNames(AScope: TScope; ANode: TSyntaxNode);
var
  Name, TypeName: string;
begin
  TypeName := TypeText(ANode);
  if TypeName = '' then
    Exit;
  for Name in SplitString(ANode.Name, ',') do
    if Trim(Name) <> '' then
      AScope.AddOrSetValue(LowerCase(Trim(Name)), TypeName);
end;

type
  /// <summary>Rahmen von TDeclaredTypes.Walk: Knoten, Klasse, in der er liegt, und nächstes Kind.</summary>
  TDeclaredTypesFrame = record
    Node: TSyntaxNode;
    OwnerClass: string;
    Next: Integer;
  end;

procedure TDeclaredTypes.Walk(ARoot: TSyntaxNode);
var
  Frames: TList<TDeclaredTypesFrame>;
  Frame: TDeclaredTypesFrame;
  Top, Inner: Integer;
  Node, Child, Header, Params: TSyntaxNode;
  OwnerClass: string;
  Scope: TScope;

  procedure Enter(ANode: TSyntaxNode; const AOwnerClass: string);
  var
    Entry: TDeclaredTypesFrame;
  begin
    Entry.Node := ANode;
    Entry.OwnerClass := AOwnerClass;
    Entry.Next := 0;
    Frames.Add(Entry);
  end;

begin
  // Früher rekursiv je Kind; lange Ausdrucksketten sprengten so den Stapel (Bericht M1). Der Rahmenstapel geht
  // die Kinder in derselben Reihenfolge durch wie die Rekursion: Routinen stehen in FRoutines in
  // Quelltextreihenfolge, wie RoutineAt es braucht.
  Frames := TList<TDeclaredTypesFrame>.Create;
  try
    Enter(ARoot, '');
    while Frames.Count > 0 do
    begin
      Top := Frames.Count - 1;
      Frame := Frames[Top];
      if Frame.Next >= Frame.Node.ChildCount then
      begin
        Frames.Delete(Top);
        Continue;
      end;
      Node := Frame.Node;
      OwnerClass := Frame.OwnerClass;
      Child := Node[Frame.Next];
      Inc(Frame.Next);
      Frames[Top] := Frame;
      case Child.Kind of
        TSyntaxKind.TypeDecl:
          Enter(Child, Child.Name);
        TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType:
          begin
            if not FClassScopes.TryGetValue(LowerCase(OwnerClass), Scope) then
            begin
              Scope := TScope.Create;
              FClassScopes.Add(LowerCase(OwnerClass), Scope);
            end;
            for Inner := 0 to Child.ChildCount - 1 do
              if Child[Inner].Kind = TSyntaxKind.Field then
                AddNames(Scope, Child[Inner]);
            // Sichtbarkeitsabschnitte rückwärts auf den Stapel: Sie kommen in Quelltextreihenfolge dran.
            for Inner := Child.ChildCount - 1 downto 0 do
              if Child[Inner].Kind = TSyntaxKind.Visibility then
                Enter(Child[Inner], OwnerClass);
          end;
        TSyntaxKind.Field:
          if FClassScopes.TryGetValue(LowerCase(OwnerClass), Scope) then
            AddNames(Scope, Child);
        TSyntaxKind.VarSection:
          for Inner := 0 to Child.ChildCount - 1 do
            if Child[Inner].Kind = TSyntaxKind.VarDecl then
              if (Node.Kind = TSyntaxKind.RoutineDecl) and FRoutineScopes.TryGetValue(Node, Scope) then
                AddNames(Scope, Child[Inner])
              else
                AddNames(FUnitScope, Child[Inner]);
        TSyntaxKind.RoutineDecl:
          begin
            Scope := TScope.Create;
            FRoutineScopes.Add(Child, Scope);
            FRoutines.Add(Child);
            Header := Child.FindChild(TSyntaxKind.RoutineHeader);
            if Header <> nil then
            begin
              Params := Header.FindChild(TSyntaxKind.Parameters);
              if Params <> nil then
                for Inner := 0 to Params.ChildCount - 1 do
                  if Params[Inner].Kind = TSyntaxKind.Parameter then
                    AddNames(Scope, Params[Inner]);
            end;
            Enter(Child, '');
          end;
        TSyntaxKind.InlineVar:
          begin
            FInlineVars.Add(Child);
            Enter(Child, OwnerClass);
          end;
      else
        Enter(Child, OwnerClass);
      end;
    end;
  finally
    Frames.Free;
  end;
end;

function TDeclaredTypes.RoutineAt(const APosition: TTextPosition): TSyntaxNode;
var
  Routine: TSyntaxNode;
begin
  // Innerste Routine: die zuletzt begonnene, die APosition enthält.
  Result := nil;
  for Routine in FRoutines do
    if not Before(APosition, Routine.StartPos) and Before(APosition, Routine.EndPos) then
      if (Result = nil) or Before(Result.StartPos, Routine.StartPos) then
        Result := Routine;
end;

function TDeclaredTypes.DeclaredType(const AName: string; const APosition: TTextPosition): string;
var
  Key, ClassName, Name: string;
  Routine, Node: TSyntaxNode;
  Scope: TScope;
  Dot: Integer;
begin
  Key := LowerCase(AName);
  Routine := RoutineAt(APosition);
  // Inline-Variablen vor der Position in derselben Routine; die letzte gewinnt.
  Result := '';
  for Node in FInlineVars do
    if Before(Node.StartPos, APosition) and (RoutineAt(Node.StartPos) = Routine) then
      for Name in SplitString(Node.Name, ',') do
        if SameText(Trim(Name), AName) and (TypeText(Node) <> '') then
          Result := TypeText(Node);
  if Result <> '' then
    Exit;
  while Routine <> nil do
  begin
    if FRoutineScopes.TryGetValue(Routine, Scope) and Scope.TryGetValue(Key, Result) then
      Exit;
    // Methode TFoo.Bar: Felder von TFoo.
    Dot := LastDelimiter('.', Routine.Name);
    if Dot > 0 then
    begin
      ClassName := Copy(Routine.Name, 1, Dot - 1);
      if Pos('.', ClassName) > 0 then
        ClassName := Copy(ClassName, LastDelimiter('.', ClassName) + 1, MaxInt);
      if FClassScopes.TryGetValue(LowerCase(ClassName), Scope) and Scope.TryGetValue(Key, Result) then
        Exit;
    end;
    // Verschachtelte Routinen sehen die Deklarationen der umgebenden.
    Node := Routine.Parent;
    while (Node <> nil) and (Node.Kind <> TSyntaxKind.RoutineDecl) do
      Node := Node.Parent;
    Routine := Node;
  end;
  if not FUnitScope.TryGetValue(Key, Result) then
    Result := '';
end;

class function TDeclaredTypes.IsInt32(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Integer', 'Cardinal', 'LongInt', 'LongWord', 'Int32', 'UInt32', 'SmallInt',
    'ShortInt', 'Word', 'Byte', 'Int16', 'UInt16', 'Int8', 'UInt8', 'FixedInt', 'FixedUInt']);
end;

class function TDeclaredTypes.IsInt64(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Int64', 'UInt64']);
end;

class function TDeclaredTypes.IsFloat(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Single', 'Double', 'Extended', 'Real', 'Real48', 'Comp', 'TDateTime', 'TDate',
    'TTime', 'Float32', 'Float64']);
end;

class function TDeclaredTypes.IsChar(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Char', 'WideChar', 'AnsiChar']);
end;

class function TDeclaredTypes.IsReference(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Pointer', 'string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String', 'TBytes', 'PChar', 'PByte']) or StartsText('TArray<', AType) or
    StartsText('array of', AType) or StartsStr('^', AType) or
    ((Length(AType) > 1) and (AType[1] = 'P') and CharInSet(AType[2], ['A'..'Z']));
end;

end.
