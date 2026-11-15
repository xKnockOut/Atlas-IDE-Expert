unit Atlas.Common.Semantics.FreeRoutineMembers;

// Mitglied einer Klasse ohne Objekt in einer freien Routine (#2309, wie E2003): Eine Routine ohne Klasse vor dem
// Namen hat kein Self; "List.OnSelectItem := ListSelectItem;" in "procedure CreateList(AFrame: TFrame)" meint
// "AFrame.ListSelectItem". Delphi meldet E2003 (nicht deklarierter Bezeichner).
// Gesucht wird der erste Name einer Kette in den Anweisungen freier Routinen (auch lokaler Routinen darin), der
// - ein Mitglied (Methode, Feld, Property) einer Klasse, eines Records oder object-Typs dieser Datei benennt,
// - nicht auf Unit-Ebene dieser Datei deklariert ist (Typ, Konstante, Variable, Routine),
// - nicht lokal ist (Parameter, Variablen, Inline-Variablen, Ausnahmevariablen, lokale Routinen) und
// - sich auch über den Index nicht auflösen lässt (Unit aus uses, System).
// Ist der Index unvollständig (System oder eine Unit aus uses fehlt, etwa ohne RTL in Cloud und CI), könnte eine
// fehlende Unit eine gleichnamige freie Routine deklarieren (Trim, Format). Dann zählt nur eine Methode, die als
// Wert steht (rechts einer Zuweisung oder als Argument): Eine freie Routine gleichen Namens dort ist selten.
// with-Blöcke, Assembler, anonyme Methoden, Intrinsics und Init/Done in New(P, Init)/Dispose(P, Done) bleiben
// außen vor. Hat die Routine einen Parameter vom Typ der Klasse, nennt der Eintrag ihn (AFrame.ListSelectItem).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver;

type
  TFreeRoutineMember = record
    Name: string;
    Range: TTextRange;
    /// <summary>Typ, zu dem das Mitglied gehört.</summary>
    Owner: string;
    /// <summary>Name der freien Routine.</summary>
    Routine: string;
    /// <summary>Parameter der Routine vom Typ Owner; '' ohne.</summary>
    Parameter: string;
  end;

  TFreeRoutineMembers = class
  public
    /// <summary>Mitglieder ohne Objekt in den freien Routinen von ATree; ohne ACompleteIndex nur Methoden, die als
    /// Wert stehen.</summary>
    class function Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      ACompleteIndex: Boolean): TArray<TFreeRoutineMember>; static;
  end;

implementation

uses
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.UnresolvedNames;

type
  /// <summary>Was die Suche aus der Datei braucht: Mitglieder je Name und Namen auf Unit-Ebene.</summary>
  TFileNames = class
  private
    FMembers: TDictionary<string, string>;
    FMethods: TDictionary<string, Boolean>;
    FUnitNames: TDictionary<string, Boolean>;
    procedure AddMembers(AType: TSyntaxNode; const AOwner: string);
    procedure AddNames(const ANames: string; ATarget: TDictionary<string, Boolean>);
  public
    constructor Create(ATree: TSyntaxTree);
    destructor Destroy; override;
    /// <summary>Typ des Mitglieds AName; False, wenn keiner der Typen der Datei es hat oder die Datei AName auf
    /// Unit-Ebene deklariert.</summary>
    function MemberOwner(const AName: string; out AOwner: string): Boolean;
    /// <summary>Ist AName eine Methode eines Typs der Datei?</summary>
    function IsMethod(const AName: string): Boolean;
  end;

/// <summary>Ist ANode der Kopf eines Typs mit Mitgliedern?</summary>
function HasMembers(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.HelperType];
end;

/// <summary>Freie Routine (kein Punkt im Namen) mit Rumpf, die in keiner Methode liegt.</summary>
function IsFreeRoutine(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.Name <> '') and (Pos('.', ANode.Name) = 0) and
    (ANode.FindChild(TSyntaxKind.Block) <> nil);
  mParent := ANode.Parent;
  while Result and (mParent <> nil) do
  begin
    Result := not HasMembers(mParent) and ((mParent.Kind <> TSyntaxKind.RoutineDecl) or
      (Pos('.', mParent.Name) = 0)) and (mParent.Kind <> TSyntaxKind.AnonymousMethod);
    mParent := mParent.Parent;
  end;
end;

constructor TFileNames.Create(ATree: TSyntaxTree);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  inherited Create;
  FMembers := TDictionary<string, string>.Create;
  FMethods := TDictionary<string, Boolean>.Create;
  FUnitNames := TDictionary<string, Boolean>.Create;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ATree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if HasMembers(mNode) and (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.TypeDecl) then
      begin
        AddMembers(mNode, mNode.Parent.Name);
      end;
      // Deklarationen auf Unit-Ebene (nicht in Routinen und nicht in Typen).
      // Routinen und Typen selbst durchläuft die Schleife nicht.
      if mNode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.RoutineDecl,
        TSyntaxKind.RoutineHeader] then
      begin
        AddNames(mNode.Name, FUnitNames);
      end;
      if (mNode.Kind = TSyntaxKind.RoutineDecl) or HasMembers(mNode) then
      begin
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

destructor TFileNames.Destroy;
begin
  FUnitNames.Free;
  FMethods.Free;
  FMembers.Free;
  inherited;
end;

procedure TFileNames.AddNames(const ANames: string; ATarget: TDictionary<string, Boolean>);
var
  mName: string;
begin
  for mName in ANames.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      ATarget.AddOrSetValue(UpperCase(Trim(mName)), True);
    end;
  end;
end;

procedure TFileNames.AddMembers(AType: TSyntaxNode; const AOwner: string);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AType);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.Field, TSyntaxKind.PropertyDecl] then
      begin
        for mName in mNode.Name.Split([',']) do
        begin
          if (Trim(mName) <> '') and not FMembers.ContainsKey(UpperCase(Trim(mName))) then
          begin
            FMembers.Add(UpperCase(Trim(mName)), AOwner);
          end;
          if mNode.Kind = TSyntaxKind.RoutineHeader then
          begin
            FMethods.AddOrSetValue(UpperCase(Trim(mName)), True);
          end;
        end;
        Continue;
      end;
      // Verschachtelte Typen bringen ihre Mitglieder selbst mit (über ihre TypeDecl).
      if (mNode <> AType) and HasMembers(mNode) then
      begin
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TFileNames.MemberOwner(const AName: string; out AOwner: string): Boolean;
begin
  Result := FMembers.TryGetValue(UpperCase(AName), AOwner) and not FUnitNames.ContainsKey(UpperCase(AName));
end;

function TFileNames.IsMethod(const AName: string): Boolean;
begin
  Result := FMethods.ContainsKey(UpperCase(AName));
end;

/// <summary>Steht ANode als Wert: ganze rechte Seite einer Zuweisung oder ganzes Argument eines Aufrufs?</summary>
function IsValue(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (((mParent.Kind = TSyntaxKind.AssignStatement) and (mParent.ChildCount = 2) and
    (mParent[1] = ANode)) or ((mParent.Kind = TSyntaxKind.Call) and (mParent.ChildCount > 0) and
    (mParent[0] <> ANode)));
end;

/// <summary>Steht ANode hinter dem Zeiger in New(P, Init) bzw. Dispose(P, Done)? Dort meint der Name den
/// Konstruktor bzw. Destruktor des Objekttyps von P, nicht ein Mitglied von Self.</summary>
function IsAllocationMember(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (mParent.Kind = TSyntaxKind.Call) and (mParent.ChildCount > 2) and
    (mParent[0].Kind = TSyntaxKind.Identifier) and (SameText(mParent[0].Name, 'New') or
    SameText(mParent[0].Name, 'Dispose')) and (mParent[0] <> ANode) and (mParent[1] <> ANode);
end;

/// <summary>Name des Parameters von ARoutine, dessen Typ AOwner heißt; '' ohne.</summary>
function OwnerParameter(ARoutine: TSyntaxNode; const AOwner: string): string;
var
  mHeader, mParams, mParam, mType: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mParams := nil;
  if mHeader <> nil then
  begin
    mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  end;
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    mParam := mParams[mIndex];
    mType := mParam.FindChild(TSyntaxKind.TypeReference);
    if (mType <> nil) and SameText(mType.Name, AOwner) and (Pos(',', mParam.Name) = 0) then
    begin
      Exit(mParam.Name);
    end;
  end;
end;

/// <summary>Lokale Namen, die die Namensauflösung nicht sicher kennt: Inline-Variablen, Ausnahmevariablen,
/// lokale Routinen.</summary>
procedure CollectLocal(ARoutine: TSyntaxNode; ANames: TDictionary<string, Boolean>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoutine);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ExceptionHandler,
        TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.Parameter]) or
        ((mNode.Kind = TSyntaxKind.RoutineDecl) and (mNode <> ARoutine)) then
      begin
        for mName in mNode.Name.Split([',']) do
        begin
          ANames.AddOrSetValue(UpperCase(Trim(mName)), True);
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

class function TFreeRoutineMembers.Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  ACompleteIndex: Boolean): TArray<TFreeRoutineMember>;
var
  mFile: TFileNames;
  mLocal: TDictionary<string, Boolean>;

  procedure CheckIdentifier(ARoutine, ANode: TSyntaxNode);
  var
    mItem: TFreeRoutineMember;
  begin
    mItem := Default(TFreeRoutineMember);
    if mLocal.ContainsKey(UpperCase(ANode.Name)) or TUnresolvedNames.IsIntrinsic(ANode.Name) or
      TResolverText.IsBuiltinTypeName(ANode.Name) or IsAllocationMember(ANode) or
      not mFile.MemberOwner(ANode.Name, mItem.Owner) then
    begin
      Exit;
    end;
    if not ACompleteIndex and not (mFile.IsMethod(ANode.Name) and IsValue(ANode)) then
    begin
      Exit;
    end;
    if AResolver.ResolveChain(ATree, AFileName, [ANode.Name], ANode.StartOffset).Found then
    begin
      Exit;
    end;
    mItem.Name := ANode.Name;
    mItem.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
    mItem.Routine := ARoutine.Name;
    mItem.Parameter := OwnerParameter(ARoutine, mItem.Owner);
    Result := Result + [mItem];
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode, mOuter: TSyntaxNode;
    mIndex: Integer;
  begin
    mLocal.Clear;
    // Lokale Namen umschließender freier Routinen sind auch sichtbar.
    mOuter := ARoutine;
    while mOuter <> nil do
    begin
      if mOuter.Kind = TSyntaxKind.RoutineDecl then
      begin
        CollectLocal(mOuter, mLocal);
      end;
      mOuter := mOuter.Parent;
    end;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoutine.FindChild(TSyntaxKind.Block));
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock, TSyntaxKind.AnonymousMethod,
          TSyntaxKind.Error] then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.Identifier) and (mNode.Name <> '') then
        begin
          CheckIdentifier(ARoutine, mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if IsFreeRoutine(mNode) then
        begin
          CheckRoutine(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mFile := TFileNames.Create(ATree);
  mLocal := TDictionary<string, Boolean>.Create;
  try
    AResolver.PinTree(ATree, AFileName);
    try
      Visit(ATree.Root);
    finally
      AResolver.UnpinTree;
    end;
  finally
    mLocal.Free;
    mFile.Free;
  end;
end;

end.
