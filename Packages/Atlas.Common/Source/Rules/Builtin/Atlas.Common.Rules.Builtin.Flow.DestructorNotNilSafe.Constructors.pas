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
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDestructorConstructorsText = (TheConstructor);

const
  cTexts: array[TDestructorConstructorsText] of TAtlasText = (
    (De: 'der Konstruktor'; En: 'the constructor'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Klassen der RTL, deren Konstruktor ohne Argumente höchstens EOutOfMemory wirft; danach gilt
  /// ohnehin nichts mehr.
  /// Dazu Grafik- und Menüobjekte der VCL, die ihr Handle erst bei Bedarf anlegen.</summary>
  cQuietConstructions: array[0..30] of string = ('TObject', 'TInterfacedObject', 'TPersistent', 'TList',
    'TObjectList', 'TDictionary', 'TObjectDictionary', 'TStringList', 'TQueue', 'TObjectQueue', 'TStack',
    'TObjectStack', 'THashSet', 'TMemoryStream', 'TStringBuilder', 'TCriticalSection', 'TMultiReadExclusiveWriteSynchronizer',
    'TBits', 'TThreadList', 'TInterfaceList', 'TStringStream', 'TBytesStream', 'TFont', 'TBrush', 'TPen', 'TBitmap',
    'TIcon', 'TPicture', 'TPopupMenu', 'TMenuItem', 'TApplicationEvents');
  /// <summary>Standardroutinen, die nicht werfen.</summary>
  cQuietRoutines: array[0..22] of string = ('Assigned', 'Length', 'High', 'Low', 'SizeOf', 'Ord', 'Chr', 'Inc',
    'Dec', 'Include', 'Exclude', 'Default', 'Supports', 'Max', 'Min', 'TypeInfo', 'Trim', 'SameText', 'LowerCase',
    'UpperCase', 'Exit', 'Break', 'Continue');

  /// <summary>Records mit Create, die keine Freigabe brauchen und nie nil sind.</summary>
  cRecordConstructions: array[0..9] of string = ('TStopwatch', 'TTimeSpan', 'TRect', 'TPoint', 'TSize', 'TGUID',
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
  mIndex: Integer;
begin
  Result := True;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result and IsFixedArgument(ACall[mIndex]);
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
  mField: string;
begin
  mField := AField;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
        SameText(FreedPath(ANode[0]), mField) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Kinder, die AssignsAlways für ANode auswertet.</summary>
function AlwaysParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
    case ANode.Kind of
      TSyntaxKind.Block:
        Result := Result + [ANode[mIndex]];
      TSyntaxKind.IfStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse:
        if ANode[mIndex].Kind in cFlowStatementKinds then
        begin
          Result := Result + [ANode[mIndex]];
        end;
      TSyntaxKind.CaseStatement:
        if ANode[mIndex].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
        begin
          Result := Result + [ANode[mIndex]];
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
  mParts: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  if ANode.Kind = TSyntaxKind.AssignStatement then
  begin
    AValues.Push((ANode.ChildCount = 2) and SameText(FreedPath(ANode[0]), AField));
  end
  else if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
    TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
  begin
    APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
    mParts := AlwaysParts(ANode);
    for mIndex := High(mParts) downto 0 do
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(mParts[mIndex], False));
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
  mParts: TArray<TSyntaxNode>;
  mIndex: Integer;
  mAnyTrue, mAllTrue, mHasElse, mValue: Boolean;
begin
  mParts := AlwaysParts(ANode);
  mAnyTrue := False;
  mAllTrue := True;
  mHasElse := False;
  for mIndex := 0 to High(mParts) do
  begin
    mValue := AValues.Pop;
    mAnyTrue := mAnyTrue or mValue;
    mAllTrue := mAllTrue and mValue;
    mHasElse := mHasElse or (mParts[mIndex].Kind = TSyntaxKind.CaseElse);
  end;
  if ANode.Kind = TSyntaxKind.IfStatement then
  begin
    Result := mAllTrue and (Length(mParts) = 2);
  end
  else if ANode.Kind = TSyntaxKind.CaseStatement then
  begin
    Result := mAllTrue and mHasElse;
  end
  else
  begin
    Result := mAnyTrue;
  end;
end;

/// <summary>Weist ANode dem Feld AField auf jedem Weg zu (if mit beiden Zweigen, case mit else, begin … end)?
/// </summary>
function AssignsAlways(ANode: TSyntaxNode; const AField: string): Boolean;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mValues: TStack<Boolean>;
  mEntry: TSyntaxPostOrderEntry;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Nachordnung mit Wertestapel; else-if-Ketten sind tiefe Bäume.
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  mValues := TStack<Boolean>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if mEntry.Done then
      begin
        mValues.Push(CombinedAlways(mEntry.Node, mValues));
      end
      else
      begin
        EnterAlways(mEntry.Node, AField, mPending, mValues);
      end;
    end;
    Result := mValues.Pop;
  finally
    mValues.Free;
    mPending.Free;
  end;
end;

/// <summary>Nimmt eine Klassendeklaration ANode mit ihrem Vorfahren (ohne Angabe TObject) auf.</summary>
procedure AddClassDecl(ANode: TSyntaxNode; var ANames, AAncestors: TArray<string>);
var
  mBody, mAncestor: TSyntaxNode;
begin
  mBody := ANode.FindChild(TSyntaxKind.ClassType);
  if mBody = nil then
  begin
    Exit;
  end;
  mAncestor := mBody.FindChild(TSyntaxKind.TypeReference);
  ANames := ANames + [ANode.Name];
  if mAncestor = nil then
  begin
    AAncestors := AAncestors + ['TObject'];
  end
  else
  begin
    AAncestors := AAncestors + [LastNamePart(mAncestor.Name)];
  end;
end;

/// <summary>Namen aus AList, die auch in AOther stehen.</summary>
function Intersection(const AList, AOther: TArray<string>): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in AList do
  begin
    if MatchText(mName, AOther) then
    begin
      Result := Result + [mName];
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
  Result := MatchText(AName, cQuietConstructions) or MatchText(AName, FQuietLocals);
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
  mCallee: TSyntaxNode;
begin
  mCallee := AValue;
  Result := True;
  if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount > 0) then
  begin
    Result := FixedArguments(mCallee);
    mCallee := mCallee[0];
  end;
  Result := Result and (mCallee.Kind = TSyntaxKind.MemberAccess) and SameText(mCallee.Name, 'Create') and
    (mCallee.ChildCount > 0);
  Result := Result and QuietClass(CreatedClassName(mCallee[0]));
end;

/// <summary>Konstruktoraufruf TKlasse.Create…(…) bzw. TKlasse&lt;T&gt;.Create…; liefert TKlasse.Create….</summary>
function TConstructorScan.CreationCall(AValue: TSyntaxNode; out ACallee: string): Boolean;
var
  mCallee: TSyntaxNode;
begin
  mCallee := AValue;
  if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount > 0) then
  begin
    mCallee := mCallee[0];
  end;
  Result := (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount > 0) and
    StartsText('Create', mCallee.Name);
  Result := Result and not MatchText(RootName(mCallee[0]), cRecordConstructions);
  if Result then
  begin
    ACallee := Trim(Text(mCallee));
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
    ((ACallee.Kind = TSyntaxKind.Identifier) and MatchText(ACallee.Name, cQuietRoutines));
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
  mRaiser: string;
begin
  mRaiser := '';
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Skip lässt den Teilbaum aus, Found liefert den ersten Treffer.
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := RaisingStep(ANode, mRaiser);
    end);
  Result := mRaiser;
end;

/// <summary>Konstruktor Create der Klasse AClass ohne Rumpf oder mit werfendem Aufruf?</summary>
function TConstructorScan.IsRaisingCreate(ARoutine: TSyntaxNode; const AClass: string): Boolean;
var
  mBody: TSyntaxNode;
begin
  Result := SameText(MethodOf(ARoutine), 'Create') and StartsWithWord(FText, ARoutine, 'constructor') and
    SameText(LastNamePart(ClassOf(ARoutine)), AClass);
  if Result then
  begin
    mBody := ARoutine.FindChild(TSyntaxKind.Block);
    Result := (mBody = nil) or (RaisingCall(mBody) <> '');
  end;
end;

function TConstructorScan.IsNewQuiet(const AName, AAncestor: string): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  Result := not MatchText(AName, FQuietLocals) and QuietClass(AAncestor);
  for mRoutine in FRoutines do
  begin
    Result := Result and not IsRaisingCreate(mRoutine, AName);
  end;
end;

/// <summary>Klassen dieser Unit, deren Konstruktor höchstens EOutOfMemory wirft: Vorfahr ruhig (TObject,
/// QuietConstructions oder selbst eine solche Klasse) und kein Konstruktor Create mit werfendem Aufruf. Bis nichts
/// mehr dazukommt, weil eine Klasse auf einer anderen aus der Unit aufbauen kann.</summary>
procedure TConstructorScan.CollectQuietLocals(ARoot: TSyntaxNode);
var
  mNames, mAncestors: TArray<string>;
  mIndex: Integer;
  mChanged: Boolean;
begin
  FQuietLocals := nil;
  mNames := nil;
  mAncestors := nil;
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
        AddClassDecl(ANode, mNames, mAncestors);
      end;
    end);
  repeat
    mChanged := False;
    for mIndex := 0 to High(mNames) do
    begin
      if IsNewQuiet(mNames[mIndex], mAncestors[mIndex]) then
      begin
        FQuietLocals := FQuietLocals + [mNames[mIndex]];
        mChanged := True;
      end;
    end;
  until not mChanged;
end;

procedure TConstructorScan.Start(const AFields: TArray<string>);
begin
  FFields := AFields;
  FRisky := nil;
  FImplications := nil;
end;

function TConstructorScan.RiskOf(const AField: string; out AItem: TNilAtDestroy): Boolean;
var
  mItem: TNilAtDestroy;
begin
  Result := False;
  for mItem in FRisky do
  begin
    if not Result and SameText(mItem.Field, AField) then
    begin
      AItem := mItem;
      Result := True;
    end;
  end;
end;

procedure TConstructorScan.AddRisky(const AField, ARaiser: string; AConditional: Boolean);
var
  mItem: TNilAtDestroy;
begin
  if RiskOf(AField, mItem) then
  begin
    Exit;
  end;
  mItem := Default(TNilAtDestroy);
  mItem.Field := AField;
  mItem.Raiser := ARaiser;
  if not AConditional and (ARaiser = '') then
  begin
    mItem.Raiser := cTexts[TDestructorConstructorsText.TheConstructor].Text;
  end;
  mItem.Conditional := AConditional;
  FRisky := FRisky + [mItem];
end;

/// <summary>AGuard wird erst nach AAlways gesetzt; mit einem anderen Konstruktor gilt nur, was beide vorher setzen.
/// </summary>
procedure TConstructorScan.AddImplication(const AGuard: string; const AAlways: TArray<string>);
var
  mIndex: Integer;
  mItem: TGuardImplication;
begin
  for mIndex := 0 to High(FImplications) do
  begin
    if SameText(FImplications[mIndex].Guard, AGuard) then
    begin
      FImplications[mIndex].Implied := Intersection(FImplications[mIndex].Implied, AAlways);
      Exit;
    end;
  end;
  mItem.Guard := AGuard;
  mItem.Implied := AAlways;
  FImplications := FImplications + [mItem];
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
  mField: string;
begin
  Result := nil;
  if (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) then
  begin
    mField := FreedPath(AStatement[0]);
    if MatchText(mField, FFields) then
    begin
      NoteSeen(mField);
      Result := Result + [mField];
    end;
    Exit;
  end;
  if not (AStatement.Kind in cFlowStatementKinds) then
  begin
    Exit;
  end;
  for mField in FFields do
  begin
    if AssignsField(AStatement, mField) then
    begin
      NoteSeen(mField);
      if AssignsAlways(AStatement, mField) then
      begin
        Result := Result + [mField];
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
  mField: string;
begin
  for mField in FFields do
  begin
    if not MatchText(mField, FDone) and AssignsField(AStatement, mField) then
    begin
      FDone := FDone + [mField];
      NoteCompoundRisk(AStatement, mField);
    end;
  end;
end;

procedure TConstructorScan.ScanStatement(AStatement: TSyntaxNode);
var
  mField, mCallee: string;
begin
  FAlways := FAlways + NoteAssignments(AStatement);
  if CreatesField(AStatement, mField, mCallee) then
  begin
    ScanCreation(AStatement, mField, mCallee);
    Exit;
  end;
  if (AStatement.Kind in cFlowStatementKinds) and (AStatement.Kind <> TSyntaxKind.AssignStatement) then
  begin
    ScanCompound(AStatement);
  end;
  mCallee := RaisingCall(AStatement);
  if mCallee <> '' then
  begin
    FRaiser := mCallee;
  end;
end;

procedure TConstructorScan.Scan(AConstructor: TSyntaxNode);
var
  mBody: TSyntaxNode;
  mIndex: Integer;
begin
  mBody := AConstructor.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    Exit;
  end;
  FRaiser := '';
  FDone := nil;
  FAlways := nil;
  FSeen := nil;
  for mIndex := 0 to mBody.ChildCount - 1 do
  begin
    ScanStatement(mBody[mIndex]);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Constructors', cTexts);

end.
