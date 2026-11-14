unit Atlas.Common.Semantics.ControlFlow.Signatures;

// Wie eine Anweisung ihre Argumente übergibt, für den Kontrollfluss (Semantics.ControlFlow): Wert, var, out
// oder unbekannt (#143), und welche Routinen nie normal zurückkehren (Direktive noreturn). Quellen sind die
// Routinenköpfe derselben Datei und eine Tabelle der Standardroutinen; Aufrufe über Objekte (Obj.Methode)
// bleiben ohne Typauflösung unbekannt. Der Graph selbst fragt nur über TFlowSignatureLookup und
// TFlowNoReturnLookup nach; Aufrufer mit Typauflösung (Semantics.ResolvedSignatures) setzen eigene ein.

interface

{$SCOPEDENUMS ON}

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Wie ein Aufruf ein Argument übergibt (#143).</summary>
  TFlowArgumentMode = (Value, Reference, Output, Unknown);

  /// <summary>Übergabeart des Arguments AArgument (0-basiert) im Aufruf ACall (Knoten der Art Call).</summary>
  TFlowSignatureLookup = reference to function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;

  /// <summary>Kehrt die Routine AName (einfacher Aufruf ohne Objekt) nie normal zurück (Direktive noreturn)?
  /// </summary>
  TFlowNoReturnLookup = reference to function(const AName: string): Boolean;

  TFlowSignatures = class
  public
    /// <summary>Übergabeart bei Standardroutinen und Typumwandlungen (SetLength, FillChar, Inc, Str,
    /// Addr, IntToStr, Integer(…)); False bei unbekanntem Namen.</summary>
    class function TryBuiltin(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
      static;
    /// <summary>Routinen aus dem Baum unter ARoot (Überladungen zusammengefasst), dann Standardroutinen,
    /// sonst Unknown; Aufrufe über Objekte sind Unknown. Liest den Baum erst beim ersten Aufruf;
    /// ARoot muss länger leben als die Funktion.</summary>
    class function FromTree(ARoot: TSyntaxNode): TFlowSignatureLookup; static;
    /// <summary>Alle Routinenköpfe unter ARoot als Kurzname (ohne Klassennamen, klein) und ob der Kopf die
    /// Direktive noreturn (ab Delphi 13) trägt; je Kopf ein Eintrag.</summary>
    class function NoReturnVerdicts(ARoot: TSyntaxNode): TArray<TPair<string, Boolean>>; static;
  end;

implementation

uses
  System.SysUtils;

type
  /// <summary>Signaturen der Routinen einer Datei, erst bei Bedarf gelesen.</summary>
  IFlowRoutineTable = interface
    ['{6E1B7C2A-4F3D-4A8B-9C5E-2D7F1A3B8E64}']
    function Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
  end;

  TFlowRoutineTable = class(TInterfacedObject, IFlowRoutineTable)
  private
    FRoot: TSyntaxNode;
    FRoutines: TDictionary<string, TArray<TFlowArgumentMode>>;
    procedure Collect(ANode: TSyntaxNode);
    procedure AddHeader(AHeader: TSyntaxNode);
  public
    constructor Create(ARoot: TSyntaxNode);
    destructor Destroy; override;
    function Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
  end;

{ TFlowSignatures }

type
  TBuiltinSignature = record
    Name: string;
    /// <summary>Je Argument V (Wert), R (var), O (out); das letzte Zeichen gilt für alle weiteren.</summary>
    Modes: string;
  end;

const
  cBuiltinSignatures: array[0..27] of TBuiltinSignature = (
    (Name: 'SetLength'; Modes: 'RV'), (Name: 'FillChar'; Modes: 'RV'), (Name: 'Inc'; Modes: 'RV'),
    (Name: 'Dec'; Modes: 'RV'), (Name: 'Include'; Modes: 'RV'), (Name: 'Exclude'; Modes: 'RV'),
    (Name: 'Insert'; Modes: 'VRV'), (Name: 'Delete'; Modes: 'RV'), (Name: 'Move'; Modes: 'VRV'),
    (Name: 'SetString'; Modes: 'RV'), (Name: 'Initialize'; Modes: 'RV'), (Name: 'Finalize'; Modes: 'RV'),
    (Name: 'FreeAndNil'; Modes: 'R'), (Name: 'GetMem'; Modes: 'RV'), (Name: 'ReallocMem'; Modes: 'RV'),
    (Name: 'New'; Modes: 'RV'), (Name: 'Dispose'; Modes: 'RV'), (Name: 'Addr'; Modes: 'R'),
    (Name: 'AtomicIncrement'; Modes: 'RV'), (Name: 'AtomicDecrement'; Modes: 'RV'),
    (Name: 'AtomicExchange'; Modes: 'RV'), (Name: 'AtomicCmpExchange'; Modes: 'RV'),
    (Name: 'Read'; Modes: 'R'), (Name: 'ReadLn'; Modes: 'R'), (Name: 'Str'; Modes: 'VO'),
    (Name: 'Val'; Modes: 'VO'), (Name: 'SwapEndian'; Modes: 'V'), (Name: 'Exit'; Modes: 'V'));

  /// <summary>Routinen und Typumwandlungen, die alle Argumente als Wert nehmen.</summary>
  cValueRoutines: array[0..63] of string = ('Length', 'High', 'Low', 'SizeOf', 'Assigned', 'Ord', 'Chr', 'Succ',
    'Pred', 'Abs', 'Round', 'Trunc', 'Frac', 'Int', 'Odd', 'Sqr', 'Sqrt', 'Copy', 'Pos', 'Concat', 'IntToStr',
    'StrToInt', 'StrToIntDef', 'FloatToStr', 'Format', 'Trim', 'UpperCase', 'LowerCase', 'SameText',
    'CompareText', 'CompareStr', 'Write', 'WriteLn', 'ShowMessage', 'Assert', 'Halt', 'TypeInfo', 'Default',
    'IntToHex', 'QuotedStr', 'Max', 'Min', 'BoolToStr', 'FreeMem', 'Integer', 'Cardinal', 'Byte', 'Word',
    'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Boolean', 'Char', 'AnsiChar', 'WideChar', 'string',
    'Pointer', 'Double', 'Single', 'Extended', 'Currency', 'LongInt', 'TObject');

class function TFlowSignatures.TryBuiltin(const AName: string; AArgument: Integer;
  out AMode: TFlowArgumentMode): Boolean;
var
  mSignature: TBuiltinSignature;
  mCode: Char;
  mName: string;
begin
  AMode := TFlowArgumentMode.Unknown;
  for mSignature in cBuiltinSignatures do
  begin
    if SameText(mSignature.Name, AName) then
    begin
      if AArgument < Length(mSignature.Modes) then
      begin
        mCode := mSignature.Modes[AArgument + 1];
      end
      else
      begin
        mCode := mSignature.Modes[Length(mSignature.Modes)];
      end;
      case mCode of
        'R':
          AMode := TFlowArgumentMode.Reference;
        'O':
          AMode := TFlowArgumentMode.Output;
      else
        AMode := TFlowArgumentMode.Value;
      end;
      Exit(True);
    end;
  end;
  for mName in cValueRoutines do
  begin
    if SameText(mName, AName) then
    begin
      AMode := TFlowArgumentMode.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TFlowSignatures.FromTree(ARoot: TSyntaxNode): TFlowSignatureLookup;
var
  mTable: IFlowRoutineTable;
begin
  mTable := TFlowRoutineTable.Create(ARoot);
  Result :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    var
      Callee: TSyntaxNode;
    begin
      Result := TFlowArgumentMode.Unknown;
      if (ACall = nil) or (ACall.ChildCount = 0) then
      begin
        Exit;
      end;
      Callee := ACall.Children[0];
      // Obj.Methode(…) oder Foo<T>(…): ohne Typauflösung unbekannt.
      if Callee.Kind <> TSyntaxKind.Identifier then
      begin
        Exit;
      end;
      if not mTable.Find(Callee.Name, AArgument, Result) then
      begin
        TFlowSignatures.TryBuiltin(Callee.Name, AArgument, Result);
      end;
    end;
end;

/// <summary>Kurzname der Routine mit dem Kopf AHeader, ohne Klasse und generische Parameter; '' bei anderen
/// Knoten und namenlosen Köpfen.</summary>
function RoutineShortName(AHeader: TSyntaxNode): string;
begin
  Result := '';
  if AHeader.Kind <> TSyntaxKind.RoutineHeader then
  begin
    Exit;
  end;
  Result := AHeader.Name;
  if (Result = '') and (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
  begin
    Result := AHeader.Parent.Name;
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

/// <summary>Trägt der Kopf AHeader die Direktive noreturn?</summary>
function HasNoReturn(AHeader: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    Result := Result or (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, 'noreturn');
  end;
end;

class function TFlowSignatures.NoReturnVerdicts(ARoot: TSyntaxNode): TArray<TPair<string, Boolean>>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex, mCount: Integer;
  mName: string;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mCount := 0;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mName := RoutineShortName(mNode);
      if mName <> '' then
      begin
        if Length(Result) = mCount then
        begin
          SetLength(Result, 2 * mCount + 8);
        end;
        Result[mCount] := TPair<string, Boolean>.Create(LowerCase(mName), HasNoReturn(mNode));
        Inc(mCount);
      end;
      for mIndex := 0 to mNode.ChildCount - 1 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
  SetLength(Result, mCount);
end;

{ TFlowRoutineTable }

constructor TFlowRoutineTable.Create(ARoot: TSyntaxNode);
begin
  inherited Create;
  FRoot := ARoot;
end;

destructor TFlowRoutineTable.Destroy;
begin
  FRoutines.Free;
  inherited;
end;

/// <summary>Übergabeart je Parameter im Kopf AHeader.</summary>
function ParameterModes(AHeader: TSyntaxNode): TArray<TFlowArgumentMode>;
var
  mParams, mParam: TSyntaxNode;
  mMode: TFlowArgumentMode;
  mIndex, mCount: Integer;
begin
  Result := nil;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    mParam := mParams.Children[mIndex];
    if mParam.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    case mParam.Modifier of
      TParameterModifier.VarParam:
        mMode := TFlowArgumentMode.Reference;
      TParameterModifier.OutParam:
        mMode := TFlowArgumentMode.Output;
    else
      mMode := TFlowArgumentMode.Value;
    end;
    for mCount := 1 to Length(mParam.Name.Split([','])) do
    begin
      Result := Result + [mMode];
    end;
  end;
end;

/// <summary>Überladungen: Wo sich die Übergabeart unterscheidet oder ein Argument fehlt, ist sie unbekannt.</summary>
procedure MergeOverload(const AKnown: TArray<TFlowArgumentMode>; var AModes: TArray<TFlowArgumentMode>);
var
  mIndex: Integer;
begin
  if Length(AKnown) > Length(AModes) then
  begin
    SetLength(AModes, Length(AKnown));
  end;
  for mIndex := 0 to High(AModes) do
  begin
    if (mIndex > High(AKnown)) or (AKnown[mIndex] <> AModes[mIndex]) then
    begin
      AModes[mIndex] := TFlowArgumentMode.Unknown;
    end;
  end;
end;

procedure TFlowRoutineTable.AddHeader(AHeader: TSyntaxNode);
var
  mModes, mKnown: TArray<TFlowArgumentMode>;
  mKey: string;
begin
  mModes := ParameterModes(AHeader);
  mKey := LowerCase(Copy(AHeader.Name, LastDelimiter('.', AHeader.Name) + 1, MaxInt));
  if mKey = '' then
  begin
    Exit;
  end;
  if FRoutines.TryGetValue(mKey, mKnown) then
  begin
    MergeOverload(mKnown, mModes);
  end;
  FRoutines.AddOrSetValue(mKey, mModes);
end;

procedure TFlowRoutineTable.Collect(ANode: TSyntaxNode);
var
  mHeaders: TList<TSyntaxNode>;
  mHeader: TSyntaxNode;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): erst die Köpfe sammeln, dann eintragen.
  mHeaders := TList<TSyntaxNode>.Create;
  try
    ANode.Walk(
      function(AVisited: TSyntaxNode): Boolean
      begin
        if AVisited.Kind = TSyntaxKind.RoutineHeader then
        begin
          mHeaders.Add(AVisited);
        end;
        Result := True;
      end);
    for mHeader in mHeaders do
    begin
      AddHeader(mHeader);
    end;
  finally
    mHeaders.Free;
  end;
end;

function TFlowRoutineTable.Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
var
  mModes: TArray<TFlowArgumentMode>;
begin
  AMode := TFlowArgumentMode.Unknown;
  if FRoutines = nil then
  begin
    FRoutines := TDictionary<string, TArray<TFlowArgumentMode>>.Create;
    if FRoot <> nil then
    begin
      Collect(FRoot);
    end;
  end;
  Result := FRoutines.TryGetValue(LowerCase(AName), mModes);
  // Mehr Argumente als Parameter: andere Überladung oder offenes Array, also unbekannt.
  if Result and (AArgument >= 0) and (AArgument <= High(mModes)) then
  begin
    AMode := mModes[AArgument];
  end;
end;
end.
