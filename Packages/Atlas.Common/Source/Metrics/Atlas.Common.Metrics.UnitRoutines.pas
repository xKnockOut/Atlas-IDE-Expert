unit Atlas.Common.Metrics.UnitRoutines;

// Freie Routinen, die auf nicht öffentliche Mitglieder einer Klasse derselben Unit zugreifen, für
// metric-class-size. Eine solche Routine ist der Sache nach eine Methode der Klasse, die außerhalb der
// Deklaration steht: Delphi erlaubt einer Routine derselben Unit den Zugriff auf private und protected
// Mitglieder. Ohne sie mitzuzählen, ließe sich jede Klasse unter die Grenze bringen, indem man Methoden als freie
// Routinen mit der Klasse als Parameter schreibt.
//
// Gezählt wird je Klasse jede freie Routine (nicht Methode, nicht lokal) einmal, wenn sie über einen Parameter,
// eine lokale oder Inline-Variable oder eine Variable der Unit mit dieser Klasse als Typ ein Mitglied aus einem
// private- oder protected-Abschnitt anspricht (X.FFeld, X.Methode). Lokale Routinen und anonyme Methoden darin
// gehören zur freien Routine. Ohne Namensauflösung: Der Typ wird am Namen in der Deklaration erkannt, Umwege über
// Typumwandlungen oder with zählen nicht.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Zahl der freien Routinen einer Unit, die auf nicht öffentliche Mitglieder der Klasse zugreifen.
  /// </summary>
  TClassUnitRoutines = record
    /// <summary>Name der Klasse ohne generische Parameter.</summary>
    TypeName: string;
    Count: Integer;
  end;

  TUnitRoutineAccess = class
  public
    /// <summary>Je Klasse in ATree mit mindestens einer solchen Routine ein Eintrag, nach der Reihenfolge der
    /// Klassen im Quelltext.</summary>
    class function Count(ATree: TSyntaxTree): TArray<TClassUnitRoutines>; static;
    /// <summary>Zahl für die Klasse ATypeName aus ACounts; 0 ohne Eintrag.</summary>
    class function CountOf(const ACounts: TArray<TClassUnitRoutines>; const ATypeName: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

type
  /// <summary>Nicht öffentliche Mitglieder einer Klasse (Namen klein geschrieben).</summary>
  TClassPrivates = TDictionary<string, Boolean>;

  /// <summary>Ein Durchlauf über eine Unit.</summary>
  TUnitRoutineScan = class
  private
    FClasses: TObjectDictionary<string, TClassPrivates>;
    FOrder: TList<string>;
    FGlobals: TDictionary<string, string>;
    FCounts: TDictionary<string, Integer>;
    procedure AddClass(ATypeDecl, ABody: TSyntaxNode);
    procedure AddVariables(AOwner: TSyntaxNode; AVariables: TDictionary<string, string>);
    procedure AddTyped(const ANames: string; ATypeNode: TSyntaxNode; AVariables: TDictionary<string, string>);
    procedure ScanRoutine(ARoutine: TSyntaxNode);
    function Accessed(ANode: TSyntaxNode; AVariables: TDictionary<string, string>; out AClass: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Run(ATree: TSyntaxTree): TArray<TClassUnitRoutines>;
  end;

const
  cPublicSections: array[0..2] of string = ('public', 'published', 'automated');

/// <summary>Typname ohne Unit-Präfix und generische Parameter, klein geschrieben.</summary>
function PlainName(const AName: string): string;
var
  mPosition: Integer;
begin
  Result := AName;
  mPosition := Pos('<', Result);
  if mPosition > 0 then
  begin
    Result := Copy(Result, 1, mPosition - 1);
  end;
  mPosition := LastDelimiter('.', Result);
  if mPosition > 0 then
  begin
    Result := Copy(Result, mPosition + 1, MaxInt);
  end;
  Result := LowerCase(Trim(Result));
end;

/// <summary>Namen, die ein Element des Klassenrumpfs deklariert.</summary>
function DeclaredNames(AChild: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  case AChild.Kind of
    TSyntaxKind.Field:
      Result := AChild.Name.Split([',']);
    TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
      Result := TArray<string>.Create(AChild.Name);
    TSyntaxKind.VarSection:
      for mIndex := 0 to AChild.ChildCount - 1 do
      begin
        Result := Result + AChild[mIndex].Name.Split([',']);
      end;
  else
    // Typen und Konstanten im Rumpf sind über den Klassennamen erreichbar, nicht über eine Variable.
  end;
end;

/// <summary>Ist ANode eine freie Routine mit Rumpf auf oberster Ebene (keine Methode, nicht lokal)?</summary>
function IsFreeRoutine(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', ANode.Name) = 0) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]);
end;

{ TUnitRoutineScan }

constructor TUnitRoutineScan.Create;
begin
  inherited Create;
  FClasses := TObjectDictionary<string, TClassPrivates>.Create([doOwnsValues]);
  FOrder := TList<string>.Create;
  FGlobals := TDictionary<string, string>.Create;
  FCounts := TDictionary<string, Integer>.Create;
end;

destructor TUnitRoutineScan.Destroy;
begin
  FCounts.Free;
  FGlobals.Free;
  FOrder.Free;
  FClasses.Free;
  inherited Destroy;
end;

procedure TUnitRoutineScan.AddClass(ATypeDecl, ABody: TSyntaxNode);
var
  mPrivates: TClassPrivates;
  mName, mSection, mMember: string;
  mIndex: Integer;
begin
  mName := PlainName(ATypeDecl.Name);
  if not FClasses.TryGetValue(mName, mPrivates) then
  begin
    mPrivates := TClassPrivates.Create;
    FClasses.Add(mName, mPrivates);
    FOrder.Add(mName);
  end;
  mSection := 'public';
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      mSection := LowerCase(ABody[mIndex].Name);
    end
    else if not MatchText(mSection, cPublicSections) then
    begin
      for mMember in DeclaredNames(ABody[mIndex]) do
      begin
        if Trim(mMember) <> '' then
        begin
          mPrivates.AddOrSetValue(LowerCase(Trim(mMember)), True);
        end;
      end;
    end;
  end;
end;

procedure TUnitRoutineScan.AddTyped(const ANames: string; ATypeNode: TSyntaxNode;
  AVariables: TDictionary<string, string>);
var
  mName, mType: string;
begin
  if (ATypeNode = nil) or (ATypeNode.Kind <> TSyntaxKind.TypeReference) then
  begin
    Exit;
  end;
  mType := PlainName(ATypeNode.Name);
  for mName in ANames.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      AVariables.AddOrSetValue(LowerCase(Trim(mName)), mType);
    end;
  end;
end;

procedure TUnitRoutineScan.AddVariables(AOwner: TSyntaxNode; AVariables: TDictionary<string, string>);
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  for mNode in TSyntaxNode.PreOrder(AOwner) do
  begin
    case mNode.Kind of
      TSyntaxKind.Parameter, TSyntaxKind.InlineVar:
        AddTyped(mNode.Name, mNode.FindChild(TSyntaxKind.TypeReference), AVariables);
      TSyntaxKind.VarSection:
        for mIndex := 0 to mNode.ChildCount - 1 do
        begin
          if mNode[mIndex].Kind = TSyntaxKind.VarDecl then
          begin
            AddTyped(mNode[mIndex].Name, mNode[mIndex].FindChild(TSyntaxKind.TypeReference), AVariables);
          end;
        end;
    else
      // Übrige Knoten deklarieren keine Variable.
    end;
  end;
end;

function TUnitRoutineScan.Accessed(ANode: TSyntaxNode; AVariables: TDictionary<string, string>;
  out AClass: string): Boolean;
var
  mPrivates: TClassPrivates;
begin
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and AVariables.TryGetValue(LowerCase(ANode[0].Name), AClass) and
    FClasses.TryGetValue(AClass, mPrivates) and mPrivates.ContainsKey(LowerCase(ANode.Name));
end;

procedure TUnitRoutineScan.ScanRoutine(ARoutine: TSyntaxNode);
var
  mVariables: TDictionary<string, string>;
  mSeen: TDictionary<string, Boolean>;
  mPair: TPair<string, string>;
  mNode: TSyntaxNode;
  mClass: string;
  mCount: Integer;
begin
  mVariables := TDictionary<string, string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mPair in FGlobals do
    begin
      mVariables.Add(mPair.Key, mPair.Value);
    end;
    AddVariables(ARoutine, mVariables);
    for mNode in TSyntaxNode.PreOrder(ARoutine) do
    begin
      if Accessed(mNode, mVariables, mClass) and not mSeen.ContainsKey(mClass) then
      begin
        mSeen.Add(mClass, True);
        mCount := 0;
        if FCounts.TryGetValue(mClass, mCount) then
        begin
          Inc(mCount);
        end
        else
        begin
          mCount := 1;
        end;
        FCounts.AddOrSetValue(mClass, mCount);
      end;
    end;
  finally
    mSeen.Free;
    mVariables.Free;
  end;
end;

function TUnitRoutineScan.Run(ATree: TSyntaxTree): TArray<TClassUnitRoutines>;
var
  mNode, mBody: TSyntaxNode;
  mRoutines: TList<TSyntaxNode>;
  mName: string;
  mItem: TClassUnitRoutines;
begin
  Result := nil;
  mRoutines := TList<TSyntaxNode>.Create;
  try
    for mNode in TSyntaxNode.PreOrder(ATree.Root) do
    begin
      if mNode.Kind = TSyntaxKind.TypeDecl then
      begin
        mBody := mNode.FindChild(TSyntaxKind.ClassType);
        if mBody = nil then
        begin
          mBody := mNode.FindChild(TSyntaxKind.ObjectType);
        end;
        if mBody <> nil then
        begin
          AddClass(mNode, mBody);
        end;
      end
      else if (mNode.Kind = TSyntaxKind.VarSection) and (mNode.Parent <> nil) and (mNode.Parent.Kind in
        [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) then
      begin
        AddVariables(mNode, FGlobals);
      end
      else if IsFreeRoutine(mNode) then
      begin
        mRoutines.Add(mNode);
      end;
    end;
    if FClasses.Count = 0 then
    begin
      Exit;
    end;
    for mNode in mRoutines do
    begin
      ScanRoutine(mNode);
    end;
  finally
    mRoutines.Free;
  end;
  for mName in FOrder do
  begin
    if FCounts.ContainsKey(mName) then
    begin
      mItem.TypeName := mName;
      mItem.Count := FCounts[mName];
      Result := Result + [mItem];
    end;
  end;
end;

{ TUnitRoutineAccess }

class function TUnitRoutineAccess.Count(ATree: TSyntaxTree): TArray<TClassUnitRoutines>;
var
  mScan: TUnitRoutineScan;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TUnitRoutineScan.Create;
  try
    Result := mScan.Run(ATree);
  finally
    mScan.Free;
  end;
end;

class function TUnitRoutineAccess.CountOf(const ACounts: TArray<TClassUnitRoutines>;
  const ATypeName: string): Integer;
var
  mItem: TClassUnitRoutines;
begin
  Result := 0;
  for mItem in ACounts do
  begin
    if SameText(mItem.TypeName, PlainName(ATypeName)) then
    begin
      Exit(mItem.Count);
    end;
  end;
end;

end.
