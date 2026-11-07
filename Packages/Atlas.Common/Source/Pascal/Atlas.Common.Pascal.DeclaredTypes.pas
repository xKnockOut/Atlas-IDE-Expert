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
    /// <summary>Rahmen von Walk: Knoten, Klasse, in der er liegt, und nächstes Kind.</summary>
    TFrame = record
      Node: TSyntaxNode;
      OwnerClass: string;
      Next: Integer;
    end;
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
    /// <summary>Legt ANode als Rahmen auf den Stapel von Walk.</summary>
    procedure Enter(AFrames: TList<TFrame>; ANode: TSyntaxNode; const AOwnerClass: string);
    /// <summary>Behandelt das Kind AChild des Knotens ANode in Walk.</summary>
    procedure Visit(AFrames: TList<TFrame>; ANode, AChild: TSyntaxNode; const AOwnerClass: string);
    /// <summary>Felder einer Klasse, eines Records oder Objekts; Sichtbarkeitsabschnitte kommen auf den
    /// Stapel.</summary>
    procedure VisitClassType(AFrames: TList<TFrame>; AType: TSyntaxNode; const AOwnerClass: string);
    procedure VisitVarSection(ANode, ASection: TSyntaxNode);
    /// <summary>Neuer Gültigkeitsbereich für die Routine ARoutine mit ihren Parametern.</summary>
    procedure AddRoutine(ARoutine: TSyntaxNode);
    /// <summary>Typ der zuletzt vor APosition in ARoutine deklarierten Inline-Variable AName; '' ohne.</summary>
    function InlineVarType(const AName: string; const APosition: TTextPosition; ARoutine: TSyntaxNode): string;
    /// <summary>Typ von AKey aus den Deklarationen von ARoutine oder den Feldern ihrer Klasse.</summary>
    function RoutineScopeType(ARoutine: TSyntaxNode; const AKey: string; out AType: string): Boolean;
    function RoutineAt(const APosition: TTextPosition): TSyntaxNode;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string);
    destructor Destroy; override;
    /// <summary>Typ von AName an APosition als Quelltext, z. B. 'Integer' oder 'TArray&lt;Byte&gt;';
    /// '' wenn in der Datei nicht deklariert.</summary>
    function DeclaredType(const AName: string; const APosition: TTextPosition): string;
    /// <summary>Typ des Felds AMember im Typ ATypeName (Klasse, Record oder Objekt aus dieser Datei, auch
    /// verschachtelt; Unit-Präfix zählt nicht); False, wenn der Typ hier kein solches Feld hat.</summary>
    function FieldType(const ATypeName, AMember: string; out AType: string): Boolean;
    /// <summary>Typ der Kette AChain an APosition ("FParts.Menu", "Self.FList"): erstes Glied über
    /// DeclaredType, die weiteren als Felder (FieldType); '' sobald ein Glied unbekannt ist.</summary>
    function ChainType(const AChain: string; const APosition: TTextPosition): string;
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
  begin
    Walk(ATree.Root);
  end;
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
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if mChild.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.ClassOfType, TSyntaxKind.SetType, TSyntaxKind.RecordType, TSyntaxKind.ProcedureType,
      TSyntaxKind.FileType, TSyntaxKind.EnumType, TSyntaxKind.SubrangeType] then
    begin
      Exit(Trim(Copy(FText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset)));
    end;
  end;
end;

procedure TDeclaredTypes.AddNames(AScope: TScope; ANode: TSyntaxNode);
var
  mName, mTypeName: string;
begin
  mTypeName := TypeText(ANode);
  if mTypeName = '' then
  begin
    Exit;
  end;
  for mName in SplitString(ANode.Name, ',') do
  begin
    if Trim(mName) <> '' then
    begin
      AScope.AddOrSetValue(LowerCase(Trim(mName)), mTypeName);
    end;
  end;
end;

procedure TDeclaredTypes.Enter(AFrames: TList<TFrame>; ANode: TSyntaxNode; const AOwnerClass: string);
var
  mEntry: TFrame;
begin
  mEntry.Node := ANode;
  mEntry.OwnerClass := AOwnerClass;
  mEntry.Next := 0;
  AFrames.Add(mEntry);
end;

procedure TDeclaredTypes.VisitClassType(AFrames: TList<TFrame>; AType: TSyntaxNode; const AOwnerClass: string);
var
  mScope: TScope;
  mInner: Integer;
begin
  if not FClassScopes.TryGetValue(LowerCase(AOwnerClass), mScope) then
  begin
    mScope := TScope.Create;
    FClassScopes.Add(LowerCase(AOwnerClass), mScope);
  end;
  for mInner := 0 to AType.ChildCount - 1 do
  begin
    if AType[mInner].Kind = TSyntaxKind.Field then
    begin
      AddNames(mScope, AType[mInner]);
    end;
  end;
  // Sichtbarkeitsabschnitte rückwärts auf den Stapel: Sie kommen in Quelltextreihenfolge dran.
  for mInner := AType.ChildCount - 1 downto 0 do
  begin
    if AType[mInner].Kind = TSyntaxKind.Visibility then
    begin
      Enter(AFrames, AType[mInner], AOwnerClass);
    end;
  end;
end;

procedure TDeclaredTypes.VisitVarSection(ANode, ASection: TSyntaxNode);
var
  mScope: TScope;
  mInner: Integer;
begin
  if (ANode.Kind <> TSyntaxKind.RoutineDecl) or not FRoutineScopes.TryGetValue(ANode, mScope) then
  begin
    mScope := FUnitScope;
  end;
  for mInner := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mInner].Kind = TSyntaxKind.VarDecl then
    begin
      AddNames(mScope, ASection[mInner]);
    end;
  end;
end;

procedure TDeclaredTypes.AddRoutine(ARoutine: TSyntaxNode);
var
  mScope: TScope;
  mHeader, mParams: TSyntaxNode;
  mInner: Integer;
begin
  mScope := TScope.Create;
  FRoutineScopes.Add(ARoutine, mScope);
  FRoutines.Add(ARoutine);
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
  for mInner := 0 to mParams.ChildCount - 1 do
  begin
    if mParams[mInner].Kind = TSyntaxKind.Parameter then
    begin
      AddNames(mScope, mParams[mInner]);
    end;
  end;
end;

procedure TDeclaredTypes.Visit(AFrames: TList<TFrame>; ANode, AChild: TSyntaxNode; const AOwnerClass: string);
var
  mScope: TScope;
begin
  case AChild.Kind of
    TSyntaxKind.TypeDecl:
      Enter(AFrames, AChild, AChild.Name);
    TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType:
      VisitClassType(AFrames, AChild, AOwnerClass);
    TSyntaxKind.Field:
      if FClassScopes.TryGetValue(LowerCase(AOwnerClass), mScope) then
      begin
        AddNames(mScope, AChild);
      end;
    TSyntaxKind.VarSection:
      VisitVarSection(ANode, AChild);
    TSyntaxKind.RoutineDecl:
      begin
        AddRoutine(AChild);
        Enter(AFrames, AChild, '');
      end;
    TSyntaxKind.InlineVar:
      begin
        FInlineVars.Add(AChild);
        Enter(AFrames, AChild, AOwnerClass);
      end;
  else
    Enter(AFrames, AChild, AOwnerClass);
  end;
end;

procedure TDeclaredTypes.Walk(ARoot: TSyntaxNode);
var
  mFrames: TList<TFrame>;
  mFrame: TFrame;
  mTop: Integer;
begin
  // Früher rekursiv je Kind; lange Ausdrucksketten sprengten so den Stapel (Bericht M1). Der Rahmenstapel geht
  // die Kinder in derselben Reihenfolge durch wie die Rekursion: Routinen stehen in FRoutines in
  // Quelltextreihenfolge, wie RoutineAt es braucht.
  mFrames := TList<TFrame>.Create;
  try
    Enter(mFrames, ARoot, '');
    while mFrames.Count > 0 do
    begin
      mTop := mFrames.Count - 1;
      mFrame := mFrames[mTop];
      if mFrame.Next >= mFrame.Node.ChildCount then
      begin
        mFrames.Delete(mTop);
        Continue;
      end;
      Inc(mFrame.Next);
      mFrames[mTop] := mFrame;
      Visit(mFrames, mFrame.Node, mFrame.Node[mFrame.Next - 1], mFrame.OwnerClass);
    end;
  finally
    mFrames.Free;
  end;
end;

function TDeclaredTypes.RoutineAt(const APosition: TTextPosition): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
begin
  // Innerste Routine: die zuletzt begonnene, die APosition enthält.
  Result := nil;
  for mRoutine in FRoutines do
  begin
    if not Before(APosition, mRoutine.StartPos) and Before(APosition, mRoutine.EndPos) then
    begin
      if (Result = nil) or Before(Result.StartPos, mRoutine.StartPos) then
      begin
        Result := mRoutine;
      end;
    end;
  end;
end;

function TDeclaredTypes.InlineVarType(const AName: string; const APosition: TTextPosition;
  ARoutine: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
  mName: string;
begin
  Result := '';
  for mNode in FInlineVars do
  begin
    if not Before(mNode.StartPos, APosition) or (RoutineAt(mNode.StartPos) <> ARoutine) then
    begin
      Continue;
    end;
    for mName in SplitString(mNode.Name, ',') do
    begin
      if SameText(Trim(mName), AName) and (TypeText(mNode) <> '') then
      begin
        Result := TypeText(mNode);
      end;
    end;
  end;
end;

function TDeclaredTypes.RoutineScopeType(ARoutine: TSyntaxNode; const AKey: string; out AType: string): Boolean;
var
  mScope: TScope;
  mClassName: string;
  mDot: Integer;
begin
  AType := '';
  if FRoutineScopes.TryGetValue(ARoutine, mScope) and mScope.TryGetValue(AKey, AType) then
  begin
    Exit(True);
  end;
  // Methode TFoo.Bar: Felder von TFoo.
  mDot := LastDelimiter('.', ARoutine.Name);
  Result := False;
  if mDot > 0 then
  begin
    mClassName := Copy(ARoutine.Name, 1, mDot - 1);
    mClassName := Copy(mClassName, LastDelimiter('.', mClassName) + 1, MaxInt);
    Result := FClassScopes.TryGetValue(LowerCase(mClassName), mScope) and mScope.TryGetValue(AKey, AType);
  end;
end;

function TDeclaredTypes.DeclaredType(const AName: string; const APosition: TTextPosition): string;
var
  mKey: string;
  mRoutine: TSyntaxNode;
begin
  mKey := LowerCase(AName);
  mRoutine := RoutineAt(APosition);
  // Inline-Variablen vor der Position in derselben Routine; die letzte gewinnt.
  Result := InlineVarType(AName, APosition, mRoutine);
  if Result <> '' then
  begin
    Exit;
  end;
  while mRoutine <> nil do
  begin
    if RoutineScopeType(mRoutine, mKey, Result) then
    begin
      Exit;
    end;
    // Verschachtelte Routinen sehen die Deklarationen der umgebenden.
    mRoutine := mRoutine.Parent;
    while (mRoutine <> nil) and (mRoutine.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      mRoutine := mRoutine.Parent;
    end;
  end;
  if not FUnitScope.TryGetValue(mKey, Result) then
  begin
    Result := '';
  end;
end;

function TDeclaredTypes.FieldType(const ATypeName, AMember: string; out AType: string): Boolean;
var
  mScope: TScope;
  mName: string;
begin
  AType := '';
  mName := Copy(ATypeName, LastDelimiter('.', ATypeName) + 1, MaxInt);
  Result := (mName <> '') and FClassScopes.TryGetValue(LowerCase(mName), mScope) and
    mScope.TryGetValue(LowerCase(AMember), AType);
end;

function TDeclaredTypes.ChainType(const AChain: string; const APosition: TTextPosition): string;
var
  mParts: TArray<string>;
  mFirst, mIndex: Integer;
  mMemberType: string;
begin
  Result := '';
  mParts := AChain.Split(['.']);
  if (Length(mParts) = 0) or (Trim(mParts[0]) = '') then
  begin
    Exit;
  end;
  mFirst := 0;
  if SameText(Trim(mParts[0]), 'Self') then
  begin
    // Self.FFeld: Felder der Klasse der Methode an APosition, wie ein Name ohne Self.
    mFirst := 1;
    if Length(mParts) < 2 then
    begin
      Exit;
    end;
  end;
  Result := DeclaredType(Trim(mParts[mFirst]), APosition);
  for mIndex := mFirst + 1 to High(mParts) do
  begin
    // Eigene Variable für das Ergebnis: out leert sie vor dem Lesen des Typnamens.
    if (Result = '') or not FieldType(Result, Trim(mParts[mIndex]), mMemberType) then
    begin
      Exit('');
    end;
    Result := mMemberType;
  end;
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
