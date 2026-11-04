unit Atlas.Common.Rules.Builtin.Performance.ManagedParams;

// Regel aus Atlas.Common.Rules.Builtin.Performance ausgelagert (Länge der Unit); angemeldet wird sie dort.
// Standardmäßig aus (#975):
//   managed-param-without-const  String-, Interface-, Array- bzw. Record-Parameter (ab
//                             minRecordSize Byte) ohne const, den die Routine sicher nicht
//                             verändert; Übergabe an Aufrufe mit unbekannter Signatur, with,
//                             anonyme Methoden und inherited ohne Namen lassen die Regel
//                             schweigen. Vorgegebene Signaturen (virtual, Interfaces,
//                             published, Ereignisse) bleiben außen vor. Die Korrektur
//                             ergänzt const in Rumpf und Deklaration.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TManagedParamWithoutConstRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ResolvedSignatures,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Performance.DynamicArrays;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

{ TManagedParamWithoutConstRule }

const
  ManagedParamRuleId = 'managed-param-without-const';
  StringTypes: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String', 'ShortString');
  KnownInterfaces: array[0..3] of string = ('IInterface', 'IUnknown', 'IDispatch', 'IInvokable');
  /// <summary>Direktiven, bei denen die Signatur von außen vorgegeben ist (Vorfahr, Nachfahren, Aufrufer).</summary>
  FixedSignatureDirectives: array[0..10] of string = ('virtual', 'dynamic', 'abstract', 'message', 'stdcall',
    'cdecl', 'safecall', 'pascal', 'register', 'external', 'export');

type
  TSyntaxKinds = set of TSyntaxKind;

{$SCOPEDENUMS ON}
  /// <summary>Was eine Wertübergabe kostet.</summary>
  TParamCost = (RefCount, Copy);

  /// <summary>Wie die Routine einen Parameter benutzt.</summary>
  TParamAccess = (Read, Modified, Undecided);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Wertparameter, der für const in Frage kommt.</summary>
  TParamCandidate = record
    Name: string;
    Cost: TParamCost;
    /// <summary>Strings, Records, Arrays: Zuweisungen an Teile ändern den Wert (Interfaces: nur das Objekt).
    /// </summary>
    PartsAreValue: Boolean;
    /// <summary>Feldnamen bei Records der Datei; andere Mitglieder (Methoden, Properties) können ändern.</summary>
    Fields: TArray<string>;
    IsRecord: Boolean;
    /// <summary>Parameterknoten (Gruppe) und Stelle des Namens darin.</summary>
    Group: TSyntaxNode;
    Position: Integer;
  end;

/// <summary>Name ohne Typparameter: TListe&lt;T&gt; wird TListe.</summary>
function WithoutTypeParams(const AName: string): string;
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
    else if Depth = 0 then
    begin
      Result := Result + AName[Index];
    end;
  end;
end;

/// <summary>Quelltext ohne Leerraum, klein geschrieben; für den Vergleich von Parameterlisten.</summary>
function Squeezed(const AText: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] > ' ' then
    begin
      Result := Result + AText[Index];
    end;
  end;
  Result := LowerCase(Result);
end;

function ParamsText(const AText: string; AHeader: TSyntaxNode): string;
var
  Params: TSyntaxNode;
begin
  Result := '';
  Params := AHeader.FindChild(TSyntaxKind.Parameters);
  if Params <> nil then
  begin
    Result := Squeezed(NodeText(AText, Params));
  end;
end;

/// <summary>Knoten der Arten AKinds unter ARoot in Baumreihenfolge; Teilbäume der Arten ASkip werden übergangen.
/// </summary>
function NodesOf(ARoot: TSyntaxNode; const AKinds, ASkip: TSyntaxKinds): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind in AKinds then
      begin
        Found := Found + [ANode];
      end;
      Result := (ANode = ARoot) or not (ANode.Kind in ASkip);
    end);
  Result := Found;
end;

type
  /// <summary>Suche nach dem Kopf der Deklaration zu einem Rumpf.</summary>
  TDeclarationSearch = record
    Name: string;
    /// <summary>Parameterliste des Rumpfs ohne Leerraum; '' ohne.</summary>
    Params: string;
    /// <summary>Köpfe mit dem Namen (Überladungen).</summary>
    Matches: Integer;
    Header: TSyntaxNode;
    Visibility: string;
    ClassNode: TSyntaxNode;
  end;

/// <summary>Methoden namens ASearch.Name in der Klasse AContainer; merkt Abschnitt und passenden Kopf.</summary>
procedure SearchClass(const AText: string; AContainer: TSyntaxNode; var ASearch: TDeclarationSearch);
var
  mIndex: Integer;
  mMember: TSyntaxNode;
  mSection: string;
begin
  mSection := '';
  for mIndex := 0 to AContainer.ChildCount - 1 do
  begin
    mMember := AContainer[mIndex];
    if mMember.Kind = TSyntaxKind.Visibility then
    begin
      mSection := LowerCase(mMember.Name);
    end
    else if (mMember.Kind = TSyntaxKind.RoutineHeader) and SameText(mMember.Name, ASearch.Name) then
    begin
      Inc(ASearch.Matches);
      if (ASearch.Params = '') or (ParamsText(AText, mMember) = ASearch.Params) then
      begin
        ASearch.Header := mMember;
        ASearch.Visibility := mSection;
        ASearch.ClassNode := AContainer;
      end;
    end;
  end;
end;

/// <summary>Methode in der Klasse ATypeName; False, wenn sie fehlt oder die Überladung nicht eindeutig ist.</summary>
function MethodDeclaration(const AText: string; ARoot: TSyntaxNode; const ATypeName: string;
  var ASearch: TDeclarationSearch): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in NodesOf(ARoot, [TSyntaxKind.TypeDecl], [TSyntaxKind.Block, TSyntaxKind.RoutineDecl]) do
  begin
    if SameText(WithoutTypeParams(mNode.Name), ATypeName) and (mNode.ChildCount > 0) then
    begin
      SearchClass(AText, mNode[mNode.ChildCount - 1], ASearch);
    end;
  end;
  // Ohne Parameterliste im Rumpf ist die Überladung nicht eindeutig.
  Result := (ASearch.Header <> nil) and ((ASearch.Params <> '') or (ASearch.Matches = 1));
  if not Result then
  begin
    ASearch.Header := nil;
  end;
end;

/// <summary>Routine ohne Rumpf (interface, forward) außer ARoutine selbst?</summary>
function IsBodilessRoutine(ANode, ARoutine: TSyntaxNode): Boolean;
begin
  Result := (ANode <> ARoutine) and (ANode.FindChild(TSyntaxKind.Block) = nil) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.RoutineHeader);
end;

/// <summary>Routine im interface oder als forward vor AHeader; False, wenn die Überladung nicht eindeutig ist.
/// </summary>
function RoutineDeclaration(const AText: string; ARoot, ARoutine, AHeader: TSyntaxNode;
  var ASearch: TDeclarationSearch): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in NodesOf(ARoot, [TSyntaxKind.RoutineDecl], [TSyntaxKind.Block, TSyntaxKind.RoutineDecl,
    TSyntaxKind.TypeDecl]) do
  begin
    if IsBodilessRoutine(mNode, ARoutine) and SameText(mNode[0].Name, ASearch.Name) and
      (mNode[0].StartOffset < AHeader.StartOffset) then
    begin
      Inc(ASearch.Matches);
      if (ASearch.Params = '') or (ParamsText(AText, mNode[0]) = ASearch.Params) then
      begin
        ASearch.Header := mNode[0];
      end;
    end;
  end;
  Result := (ASearch.Header = nil) or (ASearch.Params <> '') or (ASearch.Matches <= 1);
  if not Result then
  begin
    ASearch.Header := nil;
  end;
end;

/// <summary>Kopf der Deklaration zum Rumpf ARoutine: die Methode in ihrer Klasse bzw. die Routine im interface
/// oder als forward, mit gleicher Parameterliste. nil ohne eigene Deklaration. AFound False, wenn eine Methode
/// ihre Klasse nicht findet (dann ist nichts sicher). AVisibility: Abschnitt in der Klasse ('' = ohne Angabe);
/// AClass: Typknoten der Klasse bzw. nil.</summary>
function DeclarationOf(const AText: string; ARoot, ARoutine: TSyntaxNode; out AFound: Boolean;
  out AVisibility: string; out AClass: TSyntaxNode): TSyntaxNode;
var
  mHeader: TSyntaxNode;
  mTypeName: string;
  mSearch: TDeclarationSearch;
begin
  Result := nil;
  AFound := True;
  AVisibility := '';
  AClass := nil;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (mHeader = nil) or ((ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.RoutineDecl)) then
  begin
    Exit;
  end;
  mSearch := Default(TDeclarationSearch);
  mSearch.Name := mHeader.Name;
  mTypeName := '';
  if Pos('.', mSearch.Name) > 0 then
  begin
    mTypeName := WithoutTypeParams(Copy(mSearch.Name, 1, LastDelimiter('.', mSearch.Name) - 1));
    mSearch.Name := Copy(mSearch.Name, LastDelimiter('.', mSearch.Name) + 1, MaxInt);
  end;
  mSearch.Params := ParamsText(AText, mHeader);
  if mTypeName <> '' then
  begin
    AFound := MethodDeclaration(AText, ARoot, mTypeName, mSearch);
  end
  else
  begin
    AFound := RoutineDeclaration(AText, ARoot, ARoutine, mHeader, mSearch);
  end;
  Result := mSearch.Header;
  AVisibility := mSearch.Visibility;
  AClass := mSearch.ClassNode;
end;

function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  Index: Integer;
begin
  if AHeader <> nil then
  begin
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ANames) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function RecordSize(const AText: string; ARecord: TSyntaxNode; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer; forward;

/// <summary>Größe eines Typs in Byte als Untergrenze (Win64, ohne Ausrichtung); -1 = unbekannt. ARecords: Records
/// der Datei nach Namen (klein); ADepth schützt vor Zyklen.</summary>
function TypeSize(const AText, ATypeName: string; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer;
const
  Sizes: array[0..30] of string = ('Byte=1', 'Boolean=1', 'ByteBool=1', 'AnsiChar=1', 'ShortInt=1', 'Int8=1',
    'UInt8=1', 'Word=2', 'SmallInt=2', 'Char=2', 'WideChar=2', 'WordBool=2', 'Int16=2', 'UInt16=2', 'Integer=4',
    'Cardinal=4', 'LongInt=4', 'LongWord=4', 'Single=4', 'LongBool=4', 'Int32=4', 'UInt32=4', 'Int64=8',
    'UInt64=8', 'Double=8', 'Currency=8', 'TDateTime=8', 'Comp=8', 'Extended=8', 'TDate=8', 'TTime=8');
  Pointers: array[0..7] of string = ('Pointer', 'NativeInt', 'NativeUInt', 'string', 'UnicodeString', 'TObject',
    'PChar', 'IInterface');
var
  Item: string;
  Node: TSyntaxNode;
begin
  Result := -1;
  for Item in Sizes do
  begin
    if SameText(Copy(Item, 1, Pos('=', Item) - 1), ATypeName) then
    begin
      Exit(StrToInt(Copy(Item, Pos('=', Item) + 1, MaxInt)));
    end;
  end;
  if MatchText(ATypeName, Pointers) or StartsText('TArray<', ATypeName) then
  begin
    Exit(8);
  end;
  if (ADepth < 4) and ARecords.TryGetValue(LowerCase(ATypeName), Node) then
  begin
    Result := RecordSize(AText, Node, ARecords, ADepth + 1);
  end;
end;

/// <summary>array[A..B] of T mit Zahlen als Grenzen: ATypeNode wird T, ACount die Anzahl der Elemente.</summary>
function ArrayElement(var ATypeNode: TSyntaxNode; out ACount: Integer): Boolean;
var
  mBounds: TSyntaxNode;
  mLow, mHigh: Integer;
begin
  ACount := 0;
  mBounds := ATypeNode.FindChild(TSyntaxKind.SubrangeType);
  Result := (mBounds <> nil) and (mBounds.ChildCount = 2) and TryStrToInt(mBounds[0].Name, mLow) and
    TryStrToInt(mBounds[1].Name, mHigh) and (ATypeNode[ATypeNode.ChildCount - 1].Kind = TSyntaxKind.TypeReference);
  if Result then
  begin
    ACount := mHigh - mLow + 1;
    ATypeNode := ATypeNode[ATypeNode.ChildCount - 1];
  end;
end;

/// <summary>Größe aller Felder einer Feldgruppe; -1, wenn der Typ unbekannt ist.</summary>
function FieldSize(const AText: string; AField: TSyntaxNode; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer;
var
  mTypeNode: TSyntaxNode;
  mCount, mSize: Integer;
begin
  Result := -1;
  if AField.ChildCount = 0 then
  begin
    Exit;
  end;
  mTypeNode := AField[0];
  mCount := 1;
  if (mTypeNode.Kind = TSyntaxKind.ArrayType) and not ArrayElement(mTypeNode, mCount) then
  begin
    Exit;
  end;
  if mTypeNode.Kind = TSyntaxKind.TypeReference then
  begin
    mSize := TypeSize(AText, Trim(NodeText(AText, mTypeNode)), ARecords, ADepth);
    if mSize >= 0 then
    begin
      Result := mSize * mCount * Length(AField.Name.Split([',']));
    end;
  end;
end;

/// <summary>Summe der Feldgrößen eines Records der Datei; -1, wenn ein Feld unbekannt ist.</summary>
function RecordSize(const AText: string; ARecord: TSyntaxNode; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer;
var
  mIndex, mSize: Integer;
  mField: TSyntaxNode;
begin
  Result := 0;
  for mIndex := 0 to ARecord.ChildCount - 1 do
  begin
    mField := ARecord[mIndex];
    if mField.Kind = TSyntaxKind.VariantPart then
    begin
      Exit(-1);
    end;
    if mField.Kind = TSyntaxKind.Field then
    begin
      mSize := FieldSize(AText, mField, ARecords, ADepth);
      if mSize < 0 then
      begin
        Exit(-1);
      end;
      Inc(Result, mSize);
    end;
  end;
end;

/// <summary>Feldnamen eines Records (Gruppen aufgeteilt).</summary>
function RecordFields(ARecord: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ARecord.ChildCount - 1 do
  begin
    if ARecord[Index].Kind = TSyntaxKind.Field then
    begin
      for Name in ARecord[Index].Name.Split([',']) do
      begin
        Result := Result + [Trim(Name)];
      end;
    end;
  end;
end;

type
  /// <summary>Stelle, an der ein Parameter vorkommt: Bezeichner, äußerster Zugriff (A.B[I]) und dessen Elternknoten.
  /// </summary>
  TParamUse = record
    Node: TSyntaxNode;
    Top: TSyntaxNode;
    Parent: TSyntaxNode;
  end;

/// <summary>Anonyme Methoden fangen den Parameter ein; with-Ausdrücke binden ihn für den Rumpf.</summary>
function CapturedOrBound(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode.Parent;
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if (mNode.Kind = TSyntaxKind.AnonymousMethod) or ((mNode.Kind = TSyntaxKind.WithStatement) and
      (mNode.ChildCount > 1) and (ANode.StartOffset < mNode[mNode.ChildCount - 1].StartOffset)) then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

/// <summary>Bei Records nur Felder; Methoden und Properties können den Wert ändern.</summary>
function IsRecordMember(ANode: TSyntaxNode; const ACandidate: TParamCandidate): Boolean;
begin
  Result := ACandidate.IsRecord and (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and (ANode.Parent[0] = ANode) and
    not MatchText(ANode.Parent.Name, ACandidate.Fields);
end;

/// <summary>Äußerster Zugriff über ANode: A.B, A[I], A^ mit ANode vorn.</summary>
function TopOfChain(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Result.Parent[0] = Result) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Ändert ein Schreiben über die Stelle den Wert (der Parameter selbst oder ein Teil, der zum Wert
/// gehört)?</summary>
function WritesValue(const AUse: TParamUse; const ACandidate: TParamCandidate): Boolean;
begin
  Result := (AUse.Top = AUse.Node) or ACandidate.PartsAreValue;
end;

/// <summary>Methode eines Feldes: Kunde.Adresse.Leeren</summary>
function IsFieldMethodCall(const AUse: TParamUse; const ACandidate: TParamCandidate): Boolean;
begin
  Result := ACandidate.IsRecord and (AUse.Top <> AUse.Node) and ((AUse.Parent.Kind = TSyntaxKind.CallStatement) or
    ((AUse.Parent.Kind = TSyntaxKind.Call) and (AUse.Parent[0] = AUse.Top)));
end;

/// <summary>Argument eines Aufrufs: Übergabeart über ALookup; Undecided mit ACall, wenn sie unbekannt ist.</summary>
function CallArgumentAccess(const AUse: TParamUse; const ACandidate: TParamCandidate;
  const ALookup: TFlowSignatureLookup; out ACall: TSyntaxNode; out AArgument: Integer): TParamAccess;
var
  mIndex: Integer;
  mMode: TFlowArgumentMode;
begin
  ACall := nil;
  AArgument := -1;
  mIndex := 0;
  while (mIndex < AUse.Parent.ChildCount) and (AUse.Parent[mIndex] <> AUse.Top) do
  begin
    Inc(mIndex);
  end;
  mMode := TFlowArgumentMode.Unknown;
  if Assigned(ALookup) then
  begin
    mMode := ALookup(AUse.Parent, mIndex - 1);
  end;
  Result := TParamAccess.Read;
  case mMode of
    TFlowArgumentMode.Value:
      Result := TParamAccess.Read;
    TFlowArgumentMode.Reference, TFlowArgumentMode.Output:
      if WritesValue(AUse, ACandidate) then
      begin
        Result := TParamAccess.Modified;
      end;
  else
    ACall := AUse.Parent;
    AArgument := mIndex - 1;
    // Ein Teil (A[I], Intf.Wert) ändert an einem var-Parameter den Wert nicht, wenn Teile keine Werte sind.
    if WritesValue(AUse, ACandidate) then
    begin
      Result := TParamAccess.Undecided;
    end;
  end;
end;

/// <summary>Wie die Stelle AUse den Parameter benutzt: Zuweisung, Methode eines Feldes, Argument.</summary>
function UseAccess(const AUse: TParamUse; const ACandidate: TParamCandidate; const ALookup: TFlowSignatureLookup;
  out ACall: TSyntaxNode; out AArgument: Integer): TParamAccess;
begin
  ACall := nil;
  AArgument := -1;
  Result := TParamAccess.Read;
  if (AUse.Parent.Kind = TSyntaxKind.AssignStatement) and (AUse.Parent[0] = AUse.Top) then
  begin
    if WritesValue(AUse, ACandidate) then
    begin
      Result := TParamAccess.Modified;
    end;
  end
  else if IsFieldMethodCall(AUse, ACandidate) then
  begin
    Result := TParamAccess.Modified;
  end
  else if (AUse.Parent.Kind = TSyntaxKind.Call) and (AUse.Parent[0] <> AUse.Top) then
  begin
    Result := CallArgumentAccess(AUse, ACandidate, ALookup, ACall, AArgument);
  end;
end;

/// <summary>Wie ANode (Bezeichner des Parameters) den Parameter benutzt. Undecided mit ACall: Argument eines
/// Aufrufs, dessen Signatur ALookup nicht kennt; AArgument ist die Stelle (ab 0).</summary>
function ParamAccess(ANode: TSyntaxNode; const ACandidate: TParamCandidate; const ALookup: TFlowSignatureLookup;
  out ACall: TSyntaxNode; out AArgument: Integer): TParamAccess;
var
  mUse: TParamUse;
begin
  ACall := nil;
  AArgument := -1;
  if CapturedOrBound(ANode) then
  begin
    Exit(TParamAccess.Undecided);
  end;
  if (ANode.Parent.Kind = TSyntaxKind.AddressOf) or IsRecordMember(ANode, ACandidate) then
  begin
    Exit(TParamAccess.Modified);
  end;
  mUse.Node := ANode;
  mUse.Top := TopOfChain(ANode);
  mUse.Parent := mUse.Top.Parent;
  Result := TParamAccess.Read;
  if mUse.Parent <> nil then
  begin
    Result := UseAccess(mUse, ACandidate, ALookup, ACall, AArgument);
  end;
end;

/// <summary>Zeichenketten: Teile gehören zum Wert; ShortString wird kopiert.</summary>
function StringCandidate(const ATypeText: string; var ACandidate: TParamCandidate): Boolean;
begin
  ACandidate.PartsAreValue := True;
  if SameText(ATypeText, 'ShortString') then
  begin
    ACandidate.Cost := TParamCost.Copy;
  end;
  Result := True;
end;

/// <summary>Offenes Array (array of T, nicht array of const): wird kopiert, Teile gehören zum Wert.</summary>
function OpenArrayCandidate(const ATypeText: string; var ACandidate: TParamCandidate): Boolean;
begin
  Result := not SameText(Trim(Copy(ATypeText, 10, MaxInt)), 'const');
  if Result then
  begin
    ACandidate.Cost := TParamCost.Copy;
    ACandidate.PartsAreValue := True;
  end;
end;

/// <summary>Interfaces geben die Signatur vor; published (auch ohne Abschnitt bei Vorfahren) heißt
/// Formular-Ereignis.</summary>
function FixedByClass(AClassNode: TSyntaxNode; const AVisibility: string): Boolean;
begin
  if (AClassNode = nil) or (AClassNode.Kind <> TSyntaxKind.ClassType) then
  begin
    Exit(False);
  end;
  Result := (Length(NodesOf(AClassNode, [TSyntaxKind.TypeReference], [TSyntaxKind.RoutineHeader, TSyntaxKind.Field,
    TSyntaxKind.PropertyDecl])) > 1) or (AVisibility = 'published') or
    ((AVisibility = '') and (AClassNode.FindChild(TSyntaxKind.TypeReference) <> nil));
end;

/// <summary>Bare inherited reicht alle Parameter weiter.</summary>
function PassesAllParams(ARoutine: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in NodesOf(ARoutine, [TSyntaxKind.InheritedExpr], [TSyntaxKind.RoutineHeader]) do
  begin
    if (mNode.Name = '') and (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.CallStatement) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Bezeichner und Deklarationen im Rumpf von ARoutine (ohne den Kopf AHeader).</summary>
procedure CollectUses(ARoutine, AHeader: TSyntaxNode; out AUsages, ADeclared: TArray<TSyntaxNode>);
var
  mIndex: Integer;
begin
  AUsages := nil;
  ADeclared := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex] <> AHeader then
    begin
      AUsages := AUsages + NodesOf(ARoutine[mIndex], [TSyntaxKind.Identifier], []);
      ADeclared := ADeclared + NodesOf(ARoutine[mIndex], [TSyntaxKind.Parameter, TSyntaxKind.VarDecl,
        TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement], []);
    end;
  end;
end;

/// <summary>Gleichnamige Deklarationen darunter verdecken den Parameter; for-Variable heißt verändert.</summary>
function Shadowed(const AName: string; const ADeclared: TArray<TSyntaxNode>): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in ADeclared do
  begin
    if MatchText(AName, mNode.Name.Split([',', ' '])) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>"A wird" bzw. "A, B und C werden".</summary>
function SubjectOf(const AUnchanged: TArray<TParamCandidate>): string;
var
  mNames: TArray<string>;
  mCandidate: TParamCandidate;
begin
  mNames := nil;
  for mCandidate in AUnchanged do
  begin
    mNames := mNames + [mCandidate.Name];
  end;
  if Length(mNames) = 1 then
  begin
    Result := mNames[0] + ' wird';
  end
  else
  begin
    Result := string.Join(', ', Copy(mNames, 0, Length(mNames) - 1)) + ' und ' + mNames[High(mNames)] + ' werden';
  end;
end;

/// <summary>Was const spart: Referenzzählung, Kopie oder beides.</summary>
function CostsOf(const AUnchanged: TArray<TParamCandidate>): string;
var
  mCandidate: TParamCandidate;
  mHasRefCount, mHasCopy: Boolean;
begin
  mHasRefCount := False;
  mHasCopy := False;
  for mCandidate in AUnchanged do
  begin
    mHasRefCount := mHasRefCount or (mCandidate.Cost = TParamCost.RefCount);
    mHasCopy := mHasCopy or (mCandidate.Cost = TParamCost.Copy);
  end;
  if mHasRefCount and mHasCopy then
  begin
    Result := 'entfallen Referenzzählung und Kopie';
  end
  else if mHasRefCount then
  begin
    Result := 'entfällt die Referenzzählung';
  end
  else
  begin
    Result := 'entfällt die Kopie';
  end;
end;

/// <summary>Stellen der Gruppe AGroup, die const bekommen; False, wenn keine.</summary>
function GroupMarks(AGroup: TSyntaxNode; const AUnchanged: TArray<TParamCandidate>;
  out AMarks: TArray<Boolean>): Boolean;
var
  mCandidate: TParamCandidate;
begin
  AMarks := nil;
  SetLength(AMarks, Length(AGroup.Name.Split([','])));
  Result := False;
  for mCandidate in AUnchanged do
  begin
    if mCandidate.Group = AGroup then
    begin
      AMarks[mCandidate.Position] := True;
      Result := True;
    end;
  end;
end;

type
  /// <summary>Rumpf, dessen Parameter const bekommen können, mit Deklaration und Parameterlisten.</summary>
  TParamRoutine = record
    Header: TSyntaxNode;
    Declaration: TSyntaxNode;
    /// <summary>Parameterliste des Rumpfs (bzw. der Deklaration, wenn der Rumpf keine nennt).</summary>
    Params: TSyntaxNode;
    DeclParams: TSyntaxNode;
    IsOverride: Boolean;
  end;

  /// <summary>Prüft eine Datei auf managed-param-without-const.</summary>
  TManagedParamScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FLookup: TFlowSignatureLookup;
    FResolver: TNameResolver;
    /// <summary>Hält den Cache, dem FResolver gehört.</summary>
    FResolverCache: IRuleDerivedCache;
    FRecords: TDictionary<string, TSyntaxNode>;
    FInterfaces: TArray<string>;
    FDynArrays: TArray<string>;
    FExported: TArray<string>;
    FMinRecordSize: Integer;
    FIgnoreOverrides: Boolean;
    FRoot: TSyntaxNode;
    function Range(AStart, AEnd: Integer): TTextRange;
    function ResolvedMode(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;
    function RecordCandidate(const ATypeText: string; var ACandidate: TParamCandidate): Boolean;
    function CandidateOf(AGroup: TSyntaxNode; APosition: Integer; out ACandidate: TParamCandidate): Boolean;
    function UsedAsValue(const AName: string): Boolean;
    function GroupEdit(AGroup: TSyntaxNode; const AConst: TArray<Boolean>): TRuleEdit;
    function FixedSignature(const AInfo: TParamRoutine): Boolean;
    function FixableRoutine(ARoutine: TSyntaxNode; out AInfo: TParamRoutine): Boolean;
    function Candidates(AParams: TSyntaxNode): TArray<TParamCandidate>;
    function UsageAccess(ANode: TSyntaxNode; const ACandidate: TParamCandidate): TParamAccess;
    function CandidateAccess(const ACandidate: TParamCandidate; const AUsages,
      ADeclared: TArray<TSyntaxNode>): TParamAccess;
    function UnchangedParams(ARoutine, AHeader: TSyntaxNode;
      const ACandidates: TArray<TParamCandidate>): TArray<TParamCandidate>;
    function GroupEdits(const AInfo: TParamRoutine; AIndex: Integer; const AMarks: TArray<Boolean>): TArray<TRuleEdit>;
    function ConstEdits(const AInfo: TParamRoutine; const AUnchanged: TArray<TParamCandidate>): TArray<TRuleEdit>;
    procedure ReportParams(const AInfo: TParamRoutine; const AUnchanged: TArray<TParamCandidate>);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
    procedure AddExported(AClause: TSyntaxNode);
    procedure CollectTypes;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TManagedParamScan }

constructor TManagedParamScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TManagedParamScan.Range(AStart, AEnd: Integer): TTextRange;
begin
  Result := TRuleDerived.OffsetRange(FCache, FContext, AStart, AEnd);
end;

/// <summary>Übergabeart über die Namensauflösung (Methoden, Routinen anderer Units, Typumwandlungen).</summary>
function TManagedParamScan.ResolvedMode(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;
begin
  if (FResolver = nil) and (FContext.Index <> nil) then
  begin
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    FResolverCache := TRuleDerived.Open(FContext);
    FResolver := TRuleDerived.Resolver(FResolverCache, FContext);
  end;
  Result := TResolvedSignatures.Mode(FResolver, FContext.Tree, FContext.RelativePath, ACall, AArgument);
end;

/// <summary>Record der Datei ab minRecordSize Byte: wird kopiert, Felder gehören zum Wert.</summary>
function TManagedParamScan.RecordCandidate(const ATypeText: string; var ACandidate: TParamCandidate): Boolean;
var
  mNode: TSyntaxNode;
  mSize: Integer;
begin
  Result := False;
  if FRecords.TryGetValue(LowerCase(ATypeText), mNode) then
  begin
    mSize := RecordSize(FContext.Text, mNode, FRecords, 0);
    Result := (mSize >= 0) and (mSize >= FMinRecordSize);
    if Result then
    begin
      ACandidate.Cost := TParamCost.Copy;
      ACandidate.PartsAreValue := True;
      ACandidate.IsRecord := True;
      ACandidate.Fields := RecordFields(mNode);
    end;
  end;
end;

function TManagedParamScan.CandidateOf(AGroup: TSyntaxNode; APosition: Integer;
  out ACandidate: TParamCandidate): Boolean;
var
  mTypeText: string;
begin
  ACandidate := Default(TParamCandidate);
  if (AGroup.Modifier <> TParameterModifier.None) or (AGroup.ChildCount = 0) then
  begin
    Exit(False);
  end;
  mTypeText := Trim(NodeText(FContext.Text, AGroup[0]));
  ACandidate.Name := Trim(AGroup.Name.Split([','])[APosition]);
  ACandidate.Group := AGroup;
  ACandidate.Position := APosition;
  if MatchText(mTypeText, StringTypes) then
  begin
    Result := StringCandidate(mTypeText, ACandidate);
  end
  else if MatchText(mTypeText, FInterfaces) or MatchText(mTypeText, KnownInterfaces) then
  begin
    Result := True;
  end
  else if StartsText('array of ', mTypeText) then
  begin
    Result := OpenArrayCandidate(mTypeText, ACandidate);
  end
  else if TDynamicArrayTypes.IsDynamic(mTypeText, FDynArrays) then
  begin
    // Elemente eines const-Arrays lassen sich zwar schreiben, das ändert aber den Wert des Aufrufers.
    ACandidate.PartsAreValue := True;
    Result := True;
  end
  else
  begin
    Result := RecordCandidate(mTypeText, ACandidate);
  end;
end;

/// <summary>Routine wird als Wert benutzt (Methodenzeiger, @Routine, Formular, exports).</summary>
function TManagedParamScan.UsedAsValue(const AName: string): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := MatchText(AName, FExported) or
    ((FContext.FormText <> '') and TRegEx.IsMatch(FContext.FormText, '\b' + AName + '\b', [roIgnoreCase]));
  if Result then
  begin
    Exit;
  end;
  for mNode in NodesOf(FRoot, [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess], []) do
  begin
    if SameText(mNode.Name, AName) and (mNode.Parent <> nil) and not ((mNode.Parent.Kind = TSyntaxKind.Call) and
      (mNode.Parent[0] = mNode)) and (mNode.Parent.Kind <> TSyntaxKind.CallStatement) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Text der Gruppe mit const vor den Namen in AConst (Stellen); Gruppen werden bei Bedarf geteilt.
/// </summary>
function TManagedParamScan.GroupEdit(AGroup: TSyntaxNode; const AConst: TArray<Boolean>): TRuleEdit;
var
  mNames: TArray<string>;
  mText, mTypeText, mPart: string;
  mIndex: Integer;
  mAll: Boolean;
begin
  mNames := AGroup.Name.Split([',']);
  mAll := True;
  for mIndex := 0 to High(AConst) do
  begin
    mAll := mAll and AConst[mIndex];
  end;
  if mAll then
  begin
    Exit(TRuleEdit.Create(Range(AGroup.StartOffset, AGroup.StartOffset), 'const '));
  end;
  mText := NodeText(FContext.Text, AGroup);
  mTypeText := Trim(Copy(mText, Pos(':', mText) + 1, MaxInt));
  mText := '';
  for mIndex := 0 to High(mNames) do
  begin
    mPart := Trim(mNames[mIndex]) + ': ' + mTypeText;
    if AConst[mIndex] then
    begin
      mPart := 'const ' + mPart;
    end;
    if mText <> '' then
    begin
      mText := mText + '; ';
    end;
    mText := mText + mPart;
  end;
  Result := TRuleEdit.Create(Range(AGroup.StartOffset, AGroup.EndOffset), mText);
end;

/// <summary>Signatur von außen vorgegeben: Direktiven wie virtual, override bei ignoreOverrides.</summary>
function TManagedParamScan.FixedSignature(const AInfo: TParamRoutine): Boolean;
begin
  Result := HasDirective(AInfo.Header, FixedSignatureDirectives) or
    HasDirective(AInfo.Declaration, FixedSignatureDirectives) or (AInfo.IsOverride and FIgnoreOverrides);
end;

/// <summary>Darf die Regel die Parameter von ARoutine ändern? Kein asm, keine Direktiven im Kopf, Deklaration
/// gefunden, Signatur nicht vorgegeben, nicht als Wert benutzt, kein inherited ohne Namen, Parameterliste
/// vorhanden.</summary>
function TManagedParamScan.FixableRoutine(ARoutine: TSyntaxNode; out AInfo: TParamRoutine): Boolean;
var
  mFound: Boolean;
  mVisibility, mName: string;
  mClassNode: TSyntaxNode;
begin
  AInfo := Default(TParamRoutine);
  AInfo.Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (AInfo.Header = nil) or (NodesOf(ARoutine, [TSyntaxKind.AsmBlock, TSyntaxKind.Error], []) <> nil) or
    ContainsText(NodeText(FContext.Text, AInfo.Header), '{$') then
  begin
    Exit(False);
  end;
  AInfo.Declaration := DeclarationOf(FContext.Text, FRoot, ARoutine, mFound, mVisibility, mClassNode);
  AInfo.IsOverride := HasDirective(AInfo.Header, ['override']) or HasDirective(AInfo.Declaration, ['override']);
  mName := Copy(AInfo.Header.Name, LastDelimiter('.', AInfo.Header.Name) + 1, MaxInt);
  Result := mFound and not FixedSignature(AInfo) and not FixedByClass(mClassNode, mVisibility) and
    not UsedAsValue(mName) and not PassesAllParams(ARoutine);
  if Result then
  begin
    AInfo.Params := AInfo.Header.FindChild(TSyntaxKind.Parameters);
    if AInfo.Declaration <> nil then
    begin
      AInfo.DeclParams := AInfo.Declaration.FindChild(TSyntaxKind.Parameters);
    end;
    if AInfo.Params = nil then
    begin
      AInfo.Params := AInfo.DeclParams;
    end;
    Result := AInfo.Params <> nil;
  end;
end;

/// <summary>Wertparameter der Liste AParams, die für const in Frage kommen.</summary>
function TManagedParamScan.Candidates(AParams: TSyntaxNode): TArray<TParamCandidate>;
var
  mIndex, mPosition: Integer;
  mGroup: TSyntaxNode;
  mCandidate: TParamCandidate;
begin
  Result := nil;
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    mGroup := AParams[mIndex];
    if mGroup.Kind = TSyntaxKind.Parameter then
    begin
      for mPosition := 0 to High(mGroup.Name.Split([','])) do
      begin
        if CandidateOf(mGroup, mPosition, mCandidate) then
        begin
          Result := Result + [mCandidate];
        end;
      end;
    end;
  end;
end;

/// <summary>Zugriff an der Stelle ANode; unbekannte Aufrufe über die Namensauflösung.</summary>
function TManagedParamScan.UsageAccess(ANode: TSyntaxNode; const ACandidate: TParamCandidate): TParamAccess;
var
  mCall: TSyntaxNode;
  mArgument: Integer;
begin
  Result := ParamAccess(ANode, ACandidate, FLookup, mCall, mArgument);
  if (Result = TParamAccess.Undecided) and (mCall <> nil) then
    case ResolvedMode(mCall, mArgument) of
      TFlowArgumentMode.Value:
        Result := TParamAccess.Read;
      TFlowArgumentMode.Reference, TFlowArgumentMode.Output:
        Result := TParamAccess.Modified;
    end;
end;

/// <summary>Zugriff der Routine auf den Parameter über alle Stellen; Read nur, wenn ihn keine ändert.</summary>
function TManagedParamScan.CandidateAccess(const ACandidate: TParamCandidate; const AUsages,
  ADeclared: TArray<TSyntaxNode>): TParamAccess;
var
  mNode: TSyntaxNode;
begin
  if Shadowed(ACandidate.Name, ADeclared) then
  begin
    Exit(TParamAccess.Modified);
  end;
  Result := TParamAccess.Read;
  for mNode in AUsages do
  begin
    if Result <> TParamAccess.Read then
    begin
      Break;
    end;
    if SameText(mNode.Name, ACandidate.Name) then
    begin
      Result := UsageAccess(mNode, ACandidate);
    end;
  end;
end;

/// <summary>Kandidaten, die die Routine sicher nicht verändert.</summary>
function TManagedParamScan.UnchangedParams(ARoutine, AHeader: TSyntaxNode;
  const ACandidates: TArray<TParamCandidate>): TArray<TParamCandidate>;
var
  mUsages, mDeclared: TArray<TSyntaxNode>;
  mCandidate: TParamCandidate;
begin
  Result := nil;
  CollectUses(ARoutine, AHeader, mUsages, mDeclared);
  for mCandidate in ACandidates do
  begin
    if CandidateAccess(mCandidate, mUsages, mDeclared) = TParamAccess.Read then
    begin
      Result := Result + [mCandidate];
    end;
  end;
end;

/// <summary>const in der Gruppe AIndex des Rumpfs und der Deklaration.</summary>
function TManagedParamScan.GroupEdits(const AInfo: TParamRoutine; AIndex: Integer;
  const AMarks: TArray<Boolean>): TArray<TRuleEdit>;
begin
  Result := nil;
  if AInfo.Params <> AInfo.DeclParams then
  begin
    Result := Result + [GroupEdit(AInfo.Params[AIndex], AMarks)];
  end;
  // Gleiche Parameterliste: die Gruppe steht an derselben Stelle.
  if (AInfo.DeclParams <> nil) and (AIndex < AInfo.DeclParams.ChildCount) then
  begin
    Result := Result + [GroupEdit(AInfo.DeclParams[AIndex], AMarks)];
  end;
end;

/// <summary>Änderungen für const an allen unveränderten Parametern.</summary>
function TManagedParamScan.ConstEdits(const AInfo: TParamRoutine;
  const AUnchanged: TArray<TParamCandidate>): TArray<TRuleEdit>;
var
  mIndex: Integer;
  mMarks: TArray<Boolean>;
begin
  Result := nil;
  for mIndex := 0 to AInfo.Params.ChildCount - 1 do
  begin
    if GroupMarks(AInfo.Params[mIndex], AUnchanged, mMarks) then
    begin
      Result := Result + GroupEdits(AInfo, mIndex, mMarks);
    end;
  end;
end;

procedure TManagedParamScan.ReportParams(const AInfo: TParamRoutine; const AUnchanged: TArray<TParamCandidate>);
var
  mEdits: TArray<TRuleEdit>;
  mRange: TTextRange;
  mSubject, mCosts: string;
begin
  mSubject := SubjectOf(AUnchanged);
  mCosts := CostsOf(AUnchanged);
  mRange := Range(AInfo.Params.StartOffset, AInfo.Params.EndOffset);
  mEdits := nil;
  if not AInfo.IsOverride then
  begin
    mEdits := ConstEdits(AInfo, AUnchanged);
  end;
  if mEdits <> nil then
  begin
    FReport.Add(mRange, Format('%s nicht verändert; mit const %s.', [mSubject, mCosts]),
      [TRuleFix.Create('const ergänzen', mEdits)]);
  end
  else
  begin
    FReport.Add(mRange, Format('%s nicht verändert; mit const %s ' +
      '(override: die Signatur des Vorfahren mit ändern).', [mSubject, mCosts]));
  end;
end;

procedure TManagedParamScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mInfo: TParamRoutine;
  mCandidates, mUnchanged: TArray<TParamCandidate>;
begin
  if not FixableRoutine(ARoutine, mInfo) then
  begin
    Exit;
  end;
  mCandidates := Candidates(mInfo.Params);
  if mCandidates = nil then
  begin
    Exit;
  end;
  mUnchanged := UnchangedParams(ARoutine, mInfo.Header, mCandidates);
  if mUnchanged <> nil then
  begin
    ReportParams(mInfo, mUnchanged);
  end;
end;

/// <summary>Namen aus einer exports-Klausel.</summary>
procedure TManagedParamScan.AddExported(AClause: TSyntaxNode);
var
  mName: string;
begin
  for mName in TRegEx.Split(NodeText(FContext.Text, AClause), '[^A-Za-z0-9_]+') do
  begin
    if mName <> '' then
    begin
      FExported := FExported + [mName];
    end;
  end;
end;

/// <summary>Interfaces, Records und exportierte Namen der Datei.</summary>
procedure TManagedParamScan.CollectTypes;
var
  mNode: TSyntaxNode;
begin
  for mNode in NodesOf(FRoot, [TSyntaxKind.TypeDecl, TSyntaxKind.ExportsClause], [TSyntaxKind.Block]) do
  begin
    if mNode.Kind = TSyntaxKind.ExportsClause then
    begin
      AddExported(mNode);
    end
    else if mNode.ChildCount > 0 then
      case mNode[mNode.ChildCount - 1].Kind of
        TSyntaxKind.InterfaceType:
          FInterfaces := FInterfaces + [mNode.Name];
        TSyntaxKind.RecordType:
          FRecords.AddOrSetValue(LowerCase(mNode.Name), mNode[mNode.ChildCount - 1]);
      end;
  end;
end;

procedure TManagedParamScan.Run;
var
  mRoutine: TSyntaxNode;
begin
  FRoot := FContext.Tree.Root;
  FMinRecordSize := TRuleOptions.Int(FContext.Options, 'minRecordSize', 16);
  FIgnoreOverrides := TRuleOptions.Bool(FContext.Options, 'ignoreOverrides', True);
  FCache := TRuleDerived.Open(FContext);
  FLookup := TRuleDerived.FlowSignatures(FCache, FContext);
  FDynArrays := TDynamicArrayTypes.DeclaredIn(FContext.Text, FRoot);
  FRecords := TDictionary<string, TSyntaxNode>.Create;
  try
    CollectTypes;
    for mRoutine in TRuleDerived.Routines(FCache, FContext) do
    begin
      CheckRoutine(mRoutine);
    end;
  finally
    FreeAndNil(FRecords);
  end;
end;

function TManagedParamWithoutConstRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ManagedParamRuleId, TRuleSeverity.Hint,
    'String-, Interface-, Array- oder Record-Parameter ohne const wird nicht verändert', True);
end;

procedure TManagedParamWithoutConstRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TManagedParamScan;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mScan := TManagedParamScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

end.
