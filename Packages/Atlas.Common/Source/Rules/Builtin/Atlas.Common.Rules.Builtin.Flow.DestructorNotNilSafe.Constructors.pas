unit Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Constructors;

// Konstruktoren für destructor-not-nil-safe (Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe, #269): Welche
// Felder können beim Destruktor nach einer Exception im Konstruktor noch nil sein, und welche Felder setzt jeder
// Konstruktor erst nach anderen (dann schützt die Abfrage des späteren auch die früheren)?

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Feld, das beim Destruktor nach einer Exception im Konstruktor noch nil sein kann.</summary>
  TNilAtDestroy = record
    Field: string;
    /// <summary>Aufruf vor dem Anlegen, der werfen kann (TFileStream.Create); '' bei bedingtem Anlegen.</summary>
    Raiser: string;
    /// <summary>Wird das Feld im Konstruktor nur bedingt angelegt?</summary>
    Conditional: Boolean;
  end;

  /// <summary>Feld Guard, das jeder Konstruktor erst nach den Feldern Implied setzt: Ist Guard nicht nil, sind
  /// es Implied auch (if FThread &lt;&gt; nil then FStop.SetEvent).</summary>
  TGuardImplication = record
    Guard: string;
    Implied: TArray<string>;
  end;

  /// <summary>Untersucht die Konstruktoren einer Klasse; die ruhigen Klassen der Unit stehen ab Create fest.
  /// </summary>
  TConstructorScan = class
  strict private
    FText: string;
    FRoutines: TArray<TSyntaxNode>;
    FOnlyAfterRaising: Boolean;
    FQuietLocals: TArray<string>;
    FFields: TArray<string>;
    FRisky: TArray<TNilAtDestroy>;
    FImplications: TArray<TGuardImplication>;
    FRaiser: string;
    FDone: TArray<string>;
    FAlways: TArray<string>;
    FSeen: TArray<string>;
    function Text(ANode: TSyntaxNode): string;
    function QuietClass(const AName: string): Boolean;
    function CreatedClassName(ANode: TSyntaxNode): string;
    function QuietCreation(AValue: TSyntaxNode): Boolean;
    function CreationCall(AValue: TSyntaxNode; out ACallee: string): Boolean;
    function CreatesField(AStatement: TSyntaxNode; out AField, ACallee: string): Boolean;
    function IsQuietCall(ACall, ACallee: TSyntaxNode): Boolean;
    function CallStep(ACall, ACallee: TSyntaxNode; var ARaiser: string): TSyntaxSearchStep;
    function RaisingStep(ANode: TSyntaxNode; var ARaiser: string): TSyntaxSearchStep;
    function IsRaisingCreate(ARoutine: TSyntaxNode; const AClass: string): Boolean;
    function IsNewQuiet(const AName, AAncestor: string): Boolean;
    procedure CollectQuietLocals(ARoot: TSyntaxNode);
    procedure AddRisky(const AField, ARaiser: string; AConditional: Boolean);
    procedure AddImplication(const AGuard: string; const AAlways: TArray<string>);
    procedure NoteSeen(const AField: string);
    function NoteAssignments(AStatement: TSyntaxNode): TArray<string>;
    procedure ScanCreation(AStatement: TSyntaxNode; const AField, ACallee: string);
    procedure NoteCompoundRisk(AStatement: TSyntaxNode; const AField: string);
    procedure ScanCompound(AStatement: TSyntaxNode);
    procedure ScanStatement(AStatement: TSyntaxNode);
  public
    constructor Create(const AText: string; ARoot: TSyntaxNode; const ARoutines: TArray<TSyntaxNode>;
      AOnlyAfterRaising: Boolean);
    /// <summary>Erster Aufruf unter ARoot, der werfen kann (ohne inherited); '' ohne.</summary>
    function RaisingCall(ARoot: TSyntaxNode): string;
    /// <summary>Beginnt eine Klasse mit den Feldern AFields; vergisst die Ergebnisse der vorigen.</summary>
    procedure Start(const AFields: TArray<string>);
    /// <summary>Felder, die nach einer Exception in AConstructor beim Destruktor noch nil sein können.</summary>
    procedure Scan(AConstructor: TSyntaxNode);
    function RiskOf(const AField: string; out AItem: TNilAtDestroy): Boolean;
    property Risky: TArray<TNilAtDestroy> read FRisky;
    property Implications: TArray<TGuardImplication> read FImplications;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Builtin.Flow.Shared;

const
  /// <summary>Klassen der RTL, deren Konstruktor ohne Argumente höchstens EOutOfMemory wirft; danach gilt
  /// ohnehin nichts mehr.
  /// Dazu Grafik- und Menüobjekte der VCL, die ihr Handle erst bei Bedarf anlegen.</summary>
  QuietConstructions: array[0..30] of string = ('TObject', 'TInterfacedObject', 'TPersistent', 'TList',
    'TObjectList', 'TDictionary', 'TObjectDictionary', 'TStringList', 'TQueue', 'TObjectQueue', 'TStack',
    'TObjectStack', 'THashSet', 'TMemoryStream', 'TStringBuilder', 'TCriticalSection', 'TMultiReadExclusiveWriteSynchronizer',
    'TBits', 'TThreadList', 'TInterfaceList', 'TStringStream', 'TBytesStream', 'TFont', 'TBrush', 'TPen', 'TBitmap',
    'TIcon', 'TPicture', 'TPopupMenu', 'TMenuItem', 'TApplicationEvents');
  /// <summary>Standardroutinen, die nicht werfen.</summary>
  QuietRoutines: array[0..22] of string = ('Assigned', 'Length', 'High', 'Low', 'SizeOf', 'Ord', 'Chr', 'Inc',
    'Dec', 'Include', 'Exclude', 'Default', 'Supports', 'Max', 'Min', 'TypeInfo', 'Trim', 'SameText', 'LowerCase',
    'UpperCase', 'Exit', 'Break', 'Continue');

  /// <summary>Records mit Create, die keine Freigabe brauchen und nie nil sind.</summary>
  RecordConstructions: array[0..9] of string = ('TStopwatch', 'TTimeSpan', 'TRect', 'TPoint', 'TSize', 'TGUID',
    'TFormatSettings', 'TValue', 'TRegEx', 'TRttiContext');

function LastNamePart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Festes Argument wie True, nil oder ein Literal.</summary>
function IsFixedArgument(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) or ((ANode.Kind = TSyntaxKind.Identifier) and
    MatchText(ANode.Name, ['True', 'False', 'nil']));
end;

function FixedArguments(ACall: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := True;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result and IsFixedArgument(ACall[Index]);
  end;
end;

/// <summary>Aufruf ohne Klammern als Anweisung: Laden; bzw. FLog.Oeffnen;</summary>
function IsBareCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and
    (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]);
end;

/// <summary>TKlasse.Create ohne Klammern ist ebenfalls ein Aufruf.</summary>
function IsBareCreate(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', ANode.Name);
  Result := Result and ((ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.Call));
end;

/// <summary>Weist eine Anweisung unter ARoot dem Feld AField zu?</summary>
function AssignsField(ARoot: TSyntaxNode; const AField: string): Boolean;
var
  Field: string;
begin
  Field := AField;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
        SameText(FreedPath(ANode[0]), Field) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Kinder, die AssignsAlways für ANode auswertet.</summary>
function AlwaysParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    case ANode.Kind of
      TSyntaxKind.Block:
        Result := Result + [ANode[Index]];
      TSyntaxKind.IfStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse:
        if ANode[Index].Kind in FlowStatementKinds then
        begin
          Result := Result + [ANode[Index]];
        end;
      TSyntaxKind.CaseStatement:
        if ANode[Index].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
        begin
          Result := Result + [ANode[Index]];
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
end;


/// <summary>Besuch von ANode in AssignsAlways: Zuweisungen und andere Anweisungen geben ihren Wert sofort,
/// zusammengesetzte Anweisungen legen ihre Teile und sich selbst zum Zusammenfassen ab.</summary>
procedure EnterAlways(ANode: TSyntaxNode; const AField: string; APending: TStack<TSyntaxPostOrderEntry>;
  AValues: TStack<Boolean>);
var
  Parts: TArray<TSyntaxNode>;
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.AssignStatement then
  begin
    AValues.Push((ANode.ChildCount = 2) and SameText(FreedPath(ANode[0]), AField));
  end
  else if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
    TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
  begin
    APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
    Parts := AlwaysParts(ANode);
    for Index := High(Parts) downto 0 do
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(Parts[Index], False));
    end;
  end
  else
  begin
    AValues.Push(False);
  end;
end;

/// <summary>Fasst die Werte der Teile von ANode zusammen; sie liegen oben auf AValues.</summary>
function CombinedAlways(ANode: TSyntaxNode; AValues: TStack<Boolean>): Boolean;
var
  Parts: TArray<TSyntaxNode>;
  Index: Integer;
  AnyTrue, AllTrue, HasElse, Value: Boolean;
begin
  Parts := AlwaysParts(ANode);
  AnyTrue := False;
  AllTrue := True;
  HasElse := False;
  for Index := 0 to High(Parts) do
  begin
    Value := AValues.Pop;
    AnyTrue := AnyTrue or Value;
    AllTrue := AllTrue and Value;
    HasElse := HasElse or (Parts[Index].Kind = TSyntaxKind.CaseElse);
  end;
  if ANode.Kind = TSyntaxKind.IfStatement then
  begin
    Result := AllTrue and (Length(Parts) = 2);
  end
  else if ANode.Kind = TSyntaxKind.CaseStatement then
  begin
    Result := AllTrue and HasElse;
  end
  else
  begin
    Result := AnyTrue;
  end;
end;

/// <summary>Weist ANode dem Feld AField auf jedem Weg zu (if mit beiden Zweigen, case mit else, begin … end)?
/// </summary>
function AssignsAlways(ANode: TSyntaxNode; const AField: string): Boolean;
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Values: TStack<Boolean>;
  Entry: TSyntaxPostOrderEntry;
begin
  // Iterativ (Bericht M1): Nachordnung mit Wertestapel; else-if-Ketten sind tiefe Bäume.
  Pending := TStack<TSyntaxPostOrderEntry>.Create;
  Values := TStack<Boolean>.Create;
  try
    Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      if Entry.Done then
      begin
        Values.Push(CombinedAlways(Entry.Node, Values));
      end
      else
      begin
        EnterAlways(Entry.Node, AField, Pending, Values);
      end;
    end;
    Result := Values.Pop;
  finally
    Values.Free;
    Pending.Free;
  end;
end;

/// <summary>Nimmt eine Klassendeklaration ANode mit ihrem Vorfahren (ohne Angabe TObject) auf.</summary>
procedure AddClassDecl(ANode: TSyntaxNode; var ANames, AAncestors: TArray<string>);
var
  Body, Ancestor: TSyntaxNode;
begin
  Body := ANode.FindChild(TSyntaxKind.ClassType);
  if Body = nil then
  begin
    Exit;
  end;
  Ancestor := Body.FindChild(TSyntaxKind.TypeReference);
  ANames := ANames + [ANode.Name];
  if Ancestor = nil then
  begin
    AAncestors := AAncestors + ['TObject'];
  end
  else
  begin
    AAncestors := AAncestors + [LastNamePart(Ancestor.Name)];
  end;
end;

/// <summary>Namen aus AList, die auch in AOther stehen.</summary>
function Intersection(const AList, AOther: TArray<string>): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in AList do
  begin
    if MatchText(Name, AOther) then
    begin
      Result := Result + [Name];
    end;
  end;
end;

{ TConstructorScan }

constructor TConstructorScan.Create(const AText: string; ARoot: TSyntaxNode; const ARoutines: TArray<TSyntaxNode>;
  AOnlyAfterRaising: Boolean);
begin
  inherited Create;
  FText := AText;
  FRoutines := ARoutines;
  FOnlyAfterRaising := AOnlyAfterRaising;
  CollectQuietLocals(ARoot);
end;

function TConstructorScan.Text(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FText, ANode);
end;

function TConstructorScan.QuietClass(const AName: string): Boolean;
begin
  Result := MatchText(AName, QuietConstructions) or MatchText(AName, FQuietLocals);
end;

/// <summary>Name der angelegten Klasse ohne Typparameter; bei verschachtelten Klassen (TOwner.TEvents) der letzte
/// Namensteil.</summary>
function TConstructorScan.CreatedClassName(ANode: TSyntaxNode): string;
begin
  Result := Trim(Text(ANode));
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := LastNamePart(Result);
end;

/// <summary>Wirft der Konstruktoraufruf höchstens EOutOfMemory (TStringList.Create, TDictionary&lt;K, V&gt;.Create)?
/// Nur mit festen Argumenten wie TObjectList&lt;T&gt;.Create(True).</summary>
function TConstructorScan.QuietCreation(AValue: TSyntaxNode): Boolean;
var
  Callee: TSyntaxNode;
begin
  Callee := AValue;
  Result := True;
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount > 0) then
  begin
    Result := FixedArguments(Callee);
    Callee := Callee[0];
  end;
  Result := Result and (Callee.Kind = TSyntaxKind.MemberAccess) and SameText(Callee.Name, 'Create') and
    (Callee.ChildCount > 0);
  Result := Result and QuietClass(CreatedClassName(Callee[0]));
end;

/// <summary>Konstruktoraufruf TKlasse.Create…(…) bzw. TKlasse&lt;T&gt;.Create…; liefert TKlasse.Create….</summary>
function TConstructorScan.CreationCall(AValue: TSyntaxNode; out ACallee: string): Boolean;
var
  Callee: TSyntaxNode;
begin
  Callee := AValue;
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount > 0) then
  begin
    Callee := Callee[0];
  end;
  Result := (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount > 0) and
    StartsText('Create', Callee.Name);
  Result := Result and not MatchText(RootName(Callee[0]), RecordConstructions);
  if Result then
  begin
    ACallee := Trim(Text(Callee));
  end;
end;

/// <summary>Weist AStatement einem Feld mit TKlasse.Create zu? Liefert Feld und Aufruf.</summary>
function TConstructorScan.CreatesField(AStatement: TSyntaxNode; out AField, ACallee: string): Boolean;
begin
  Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2);
  if Result then
  begin
    AField := FreedPath(AStatement[0]);
    Result := (AField <> '') and MatchText(AField, FFields) and CreationCall(AStatement[1], ACallee);
  end;
end;

function TConstructorScan.IsQuietCall(ACall, ACallee: TSyntaxNode): Boolean;
begin
  Result := (ACallee.Kind = TSyntaxKind.InheritedExpr) or QuietCreation(ACall) or
    ((ACallee.Kind = TSyntaxKind.Identifier) and MatchText(ACallee.Name, QuietRoutines));
end;

/// <summary>Ruhiger Aufruf: Teilbaum auslassen; sonst ist ACallee der Treffer.</summary>
function TConstructorScan.CallStep(ACall, ACallee: TSyntaxNode; var ARaiser: string): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Skip;
  if not IsQuietCall(ACall, ACallee) then
  begin
    ARaiser := Trim(Text(ACallee));
    Result := TSyntaxSearchStep.Found;
  end;
end;

function TConstructorScan.RaisingStep(ANode: TSyntaxNode; var ARaiser: string): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if IsRoutineBody(ANode) or (ANode.Kind = TSyntaxKind.InheritedExpr) then
  begin
    Result := TSyntaxSearchStep.Skip;
  end
  else if ANode.Kind = TSyntaxKind.RaiseStatement then
  begin
    ARaiser := 'raise';
    Result := TSyntaxSearchStep.Found;
  end
  else if IsBareCall(ANode) then
  begin
    Result := CallStep(ANode[0], ANode[0], ARaiser);
  end
  else if IsBareCreate(ANode) then
  begin
    Result := CallStep(ANode, ANode, ARaiser);
  end
  else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
  begin
    Result := CallStep(ANode, ANode[0], ARaiser);
  end;
end;

function TConstructorScan.RaisingCall(ARoot: TSyntaxNode): string;
var
  Raiser: string;
begin
  Raiser := '';
  // Iterativ (Bericht M1): Skip lässt den Teilbaum aus, Found liefert den ersten Treffer.
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := RaisingStep(ANode, Raiser);
    end);
  Result := Raiser;
end;

/// <summary>Konstruktor Create der Klasse AClass ohne Rumpf oder mit werfendem Aufruf?</summary>
function TConstructorScan.IsRaisingCreate(ARoutine: TSyntaxNode; const AClass: string): Boolean;
var
  Body: TSyntaxNode;
begin
  Result := SameText(MethodOf(ARoutine), 'Create') and StartsWithWord(FText, ARoutine, 'constructor') and
    SameText(LastNamePart(ClassOf(ARoutine)), AClass);
  if Result then
  begin
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    Result := (Body = nil) or (RaisingCall(Body) <> '');
  end;
end;

function TConstructorScan.IsNewQuiet(const AName, AAncestor: string): Boolean;
var
  Routine: TSyntaxNode;
begin
  Result := not MatchText(AName, FQuietLocals) and QuietClass(AAncestor);
  for Routine in FRoutines do
  begin
    Result := Result and not IsRaisingCreate(Routine, AName);
  end;
end;

/// <summary>Klassen dieser Unit, deren Konstruktor höchstens EOutOfMemory wirft: Vorfahr ruhig (TObject,
/// QuietConstructions oder selbst eine solche Klasse) und kein Konstruktor Create mit werfendem Aufruf. Bis nichts
/// mehr dazukommt, weil eine Klasse auf einer anderen aus der Unit aufbauen kann.</summary>
procedure TConstructorScan.CollectQuietLocals(ARoot: TSyntaxNode);
var
  Names, Ancestors: TArray<string>;
  Index: Integer;
  Changed: Boolean;
begin
  FQuietLocals := nil;
  Names := nil;
  Ancestors := nil;
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ANode.Kind = TSyntaxKind.TypeDecl then
      begin
        AddClassDecl(ANode, Names, Ancestors);
      end;
    end);
  repeat
    Changed := False;
    for Index := 0 to High(Names) do
    begin
      if IsNewQuiet(Names[Index], Ancestors[Index]) then
      begin
        FQuietLocals := FQuietLocals + [Names[Index]];
        Changed := True;
      end;
    end;
  until not Changed;
end;

procedure TConstructorScan.Start(const AFields: TArray<string>);
begin
  FFields := AFields;
  FRisky := nil;
  FImplications := nil;
end;

function TConstructorScan.RiskOf(const AField: string; out AItem: TNilAtDestroy): Boolean;
var
  Item: TNilAtDestroy;
begin
  Result := False;
  for Item in FRisky do
  begin
    if not Result and SameText(Item.Field, AField) then
    begin
      AItem := Item;
      Result := True;
    end;
  end;
end;

procedure TConstructorScan.AddRisky(const AField, ARaiser: string; AConditional: Boolean);
var
  Item: TNilAtDestroy;
begin
  if RiskOf(AField, Item) then
  begin
    Exit;
  end;
  Item := Default(TNilAtDestroy);
  Item.Field := AField;
  Item.Raiser := ARaiser;
  if not AConditional and (ARaiser = '') then
  begin
    Item.Raiser := 'der Konstruktor';
  end;
  Item.Conditional := AConditional;
  FRisky := FRisky + [Item];
end;

/// <summary>AGuard wird erst nach AAlways gesetzt; mit einem anderen Konstruktor gilt nur, was beide vorher setzen.
/// </summary>
procedure TConstructorScan.AddImplication(const AGuard: string; const AAlways: TArray<string>);
var
  Index: Integer;
  Item: TGuardImplication;
begin
  for Index := 0 to High(FImplications) do
  begin
    if SameText(FImplications[Index].Guard, AGuard) then
    begin
      FImplications[Index].Implied := Intersection(FImplications[Index].Implied, AAlways);
      Exit;
    end;
  end;
  Item.Guard := AGuard;
  Item.Implied := AAlways;
  FImplications := FImplications + [Item];
end;

procedure TConstructorScan.NoteSeen(const AField: string);
begin
  if not MatchText(AField, FSeen) then
  begin
    AddImplication(AField, FAlways);
  end;
  FSeen := FSeen + [AField];
end;

/// <summary>Reihenfolge der Zuweisungen: Wer ein Feld zuweist, hat die Felder davor auf jedem Weg schon gesetzt.
/// Liefert die Felder, die AStatement auf jedem Weg setzt.</summary>
function TConstructorScan.NoteAssignments(AStatement: TSyntaxNode): TArray<string>;
var
  Field: string;
begin
  Result := nil;
  if (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) then
  begin
    Field := FreedPath(AStatement[0]);
    if MatchText(Field, FFields) then
    begin
      NoteSeen(Field);
      Result := Result + [Field];
    end;
    Exit;
  end;
  if not (AStatement.Kind in FlowStatementKinds) then
  begin
    Exit;
  end;
  for Field in FFields do
  begin
    if AssignsField(AStatement, Field) then
    begin
      NoteSeen(Field);
      if AssignsAlways(AStatement, Field) then
      begin
        Result := Result + [Field];
      end;
    end;
  end;
end;

procedure TConstructorScan.ScanCreation(AStatement: TSyntaxNode; const AField, ACallee: string);
begin
  if not MatchText(AField, FDone) then
  begin
    FDone := FDone + [AField];
    if FRaiser <> '' then
    begin
      AddRisky(AField, FRaiser, False);
    end
    else if not FOnlyAfterRaising then
    begin
      AddRisky(AField, ACallee, False);
    end;
  end;
  if not QuietCreation(AStatement[1]) then
  begin
    FRaiser := ACallee;
  end;
end;

procedure TConstructorScan.NoteCompoundRisk(AStatement: TSyntaxNode; const AField: string);
begin
  if not AssignsAlways(AStatement, AField) then
  begin
    AddRisky(AField, '', True);
  end
  else if FRaiser <> '' then
  begin
    AddRisky(AField, FRaiser, False);
  end
  else if not FOnlyAfterRaising then
  begin
    AddRisky(AField, RaisingCall(AStatement), False);
  end;
end;

/// <summary>In if, case, try, Schleife oder with angelegt: auf jedem Weg wie eine einfache Zuweisung, sonst
/// bedingt.</summary>
procedure TConstructorScan.ScanCompound(AStatement: TSyntaxNode);
var
  Field: string;
begin
  for Field in FFields do
  begin
    if not MatchText(Field, FDone) and AssignsField(AStatement, Field) then
    begin
      FDone := FDone + [Field];
      NoteCompoundRisk(AStatement, Field);
    end;
  end;
end;

procedure TConstructorScan.ScanStatement(AStatement: TSyntaxNode);
var
  Field, Callee: string;
begin
  FAlways := FAlways + NoteAssignments(AStatement);
  if CreatesField(AStatement, Field, Callee) then
  begin
    ScanCreation(AStatement, Field, Callee);
    Exit;
  end;
  if (AStatement.Kind in FlowStatementKinds) and (AStatement.Kind <> TSyntaxKind.AssignStatement) then
  begin
    ScanCompound(AStatement);
  end;
  Callee := RaisingCall(AStatement);
  if Callee <> '' then
  begin
    FRaiser := Callee;
  end;
end;

procedure TConstructorScan.Scan(AConstructor: TSyntaxNode);
var
  Body: TSyntaxNode;
  Index: Integer;
begin
  Body := AConstructor.FindChild(TSyntaxKind.Block);
  if Body = nil then
  begin
    Exit;
  end;
  FRaiser := '';
  FDone := nil;
  FAlways := nil;
  FSeen := nil;
  for Index := 0 to Body.ChildCount - 1 do
  begin
    ScanStatement(Body[Index]);
  end;
end;

end.
