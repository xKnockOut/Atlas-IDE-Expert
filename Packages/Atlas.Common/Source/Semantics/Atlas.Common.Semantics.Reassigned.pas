unit Atlas.Common.Semantics.Reassigned;

// Neu zugewiesene Variablen (#712): Welche lokalen Namen, Parameter und Felder
// ändern ihren Wert im Lauf der Routine bzw. des Objekts? Grundlage für die
// Unterstreichung im IDE-Plugin (atlas.server.reassigned), den Modifier
// "reassigned" der semantischen Hervorhebung, den Hover und den Vorschlag
// "als Konstante deklarieren".
//
// Schreibende Stellen (sicher): Ziel einer Zuweisung (:=), Argument an einen
// var- oder out-Parameter (Inc/Dec, Include/Exclude, Read/ReadLn und alle
// Routinen, deren Signatur ALookup kennt), der Startwert einer
// Inline-Variablen (var X := …). Die Steuervariable einer for-Schleife zählt
// gesondert (LoopWrites). Möglich, aber nicht sicher (MaybeWrites): Adresse
// (@X), Teilzuweisung (X.Feld := …, X[I] := …) und Argument an eine Routine
// mit unbekannter Signatur. Sie zählen nicht als Zuweisung, verhindern aber
// den Vorschlag "Konstante".
//
// Neu zugewiesen ist
//   - eine lokale Variable oder Inline-Variable mit mehr als einer
//     schreibenden Stelle,
//   - ein Schleifenzähler (for I := …, for var X in …) immer,
//   - ein Wertparameter bzw. var-/out-Parameter, sobald der Rumpf ihn
//     beschreibt (const-Parameter können das nicht),
//   - ein Feld, das nur in einer Methode geschrieben wird und nicht im
//     Konstruktor (Felder aus Klassen und Records derselben Datei; Zugriff
//     über den Namen oder Self.Name).
// Welche Arten gezeigt werden, entscheiden die Ziele (TReassignedTarget).
// Namen gehören der innersten Routine, die sie deklariert, auch aus
// verschachtelten Routinen und anonymen Methoden heraus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow;

type
{$SCOPEDENUMS ON}
  TReassignedKind = (Local, InlineVariable, LoopVariable, ValueParameter, VarParameter, Field);
  /// <summary>Einstellung highlight.reassigned.targets: welche Arten markiert werden.</summary>
  TReassignedTarget = (Locals, LoopVars, ValueParams, VarParams, Fields);
  /// <summary>Art einer Stelle: liest nur, schreibt sicher, steuert eine for-Schleife, schreibt womöglich.</summary>
  TReassignedWrite = (None, Write, LoopWrite, MaybeWrite);
{$SCOPEDENUMS OFF}
  TReassignedTargets = set of TReassignedTarget;

  TReassignedOccurrence = record
    Range: TTextRange;
    Offset: Integer;
    Write: TReassignedWrite;
    /// <summary>Bezeichner bzw. Self.Name (MemberAccess); nil an der Deklaration.</summary>
    Node: TSyntaxNode;
  end;

  TReassignedSymbol = record
    Name: string;
    Kind: TReassignedKind;
    /// <summary>Sichere Schreibstellen ohne Schleifensteuerung, mit dem Startwert einer Inline-Variablen.</summary>
    Writes: Integer;
    LoopWrites: Integer;
    MaybeWrites: Integer;
    /// <summary>Inline-Variable mit Startwert (var X := …).</summary>
    Initialized: Boolean;
    /// <summary>Deklarierende Routine (RoutineDecl oder AnonymousMethod); bei Feldern die schreibende Methode.
    /// </summary>
    Routine: TSyntaxNode;
    /// <summary>Name der umgebenden benannten Routine; bei Feldern der schreibenden Methode.</summary>
    RoutineName: string;
    /// <summary>Knoten der Deklaration (Parameter, VarDecl, InlineVar, ForStatement, Field).</summary>
    Decl: TSyntaxNode;
    /// <summary>Alle Stellen in Textreihenfolge, die Deklaration eingeschlossen.</summary>
    Occurrences: TArray<TReassignedOccurrence>;
    /// <summary>Felder: Zahl der Methoden mit sicheren Schreibstellen.</summary>
    WriterCount: Integer;
    /// <summary>Felder: Ein Konstruktor schreibt.</summary>
    InConstructor: Boolean;
    function Target: TReassignedTarget;
    /// <summary>Ändert sich der Wert (ohne Blick auf die Ziele)?</summary>
    function IsReassigned: Boolean;
    /// <summary>Genau einmal sicher geschrieben, nie womöglich: Kandidat für const.</summary>
    function IsConstCandidate: Boolean;
    /// <summary>Alle schreibenden Stellen (sicher und Schleife).</summary>
    function WriteCount: Integer;
    /// <summary>Zeilen der sicheren Schreibstellen (ab 0), ohne Doppelte.</summary>
    function WriteLines: TArray<Integer>;
    /// <summary>Stelle, die APosition enthält (Ende eingeschlossen); -1 ohne.</summary>
    function OccurrenceAt(const APosition: TTextPosition): Integer;
  end;

  TReassigned = class
  public const
    cDefaultTargets = [TReassignedTarget.Locals, TReassignedTarget.ValueParams];
    cTargetNames: array[TReassignedTarget] of string = ('locals', 'loopVars', 'valueParams', 'varParams', 'fields');
    cKindNames: array[TReassignedKind] of string = ('local', 'inlineVariable', 'loopVariable', 'valueParameter',
      'varParameter', 'field');
  public
    /// <summary>Art der Stelle ANode (Bezeichner oder Self.Name); ALookup nennt die Übergabeart von Argumenten.
    /// </summary>
    class function WriteOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TReassignedWrite; static;
    /// <summary>Alle Namen der Datei mit ihren Stellen; ALookup nil = TFlowSignatures.FromTree.</summary>
    class function Analyze(const AText: string; ATree: TSyntaxTree;
      const ALookup: TFlowSignatureLookup): TArray<TReassignedSymbol>; static;
    /// <summary>Die neu zugewiesenen Namen, deren Art in ATargets steht.</summary>
    class function Filter(const ASymbols: TArray<TReassignedSymbol>;
      ATargets: TReassignedTargets): TArray<TReassignedSymbol>; static;
    /// <summary>Name an APosition (Deklaration oder Verwendung); False ohne.</summary>
    class function SymbolAt(const ASymbols: TArray<TReassignedSymbol>; const APosition: TTextPosition;
      out ASymbol: TReassignedSymbol): Boolean; static;
    class function TryParseTarget(const AName: string; out ATarget: TReassignedTarget): Boolean; static;
    /// <summary>Ziele aus Namen; unbekannte zählen nicht.</summary>
    class function TargetsOf(const ANames: TArray<string>): TReassignedTargets; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

{ TReassignedSymbol }

function TReassignedSymbol.Target: TReassignedTarget;
begin
  case Kind of
    TReassignedKind.LoopVariable:
      Result := TReassignedTarget.LoopVars;
    TReassignedKind.ValueParameter:
      Result := TReassignedTarget.ValueParams;
    TReassignedKind.VarParameter:
      Result := TReassignedTarget.VarParams;
    TReassignedKind.Field:
      Result := TReassignedTarget.Fields;
  else
    Result := TReassignedTarget.Locals;
  end;
end;

function TReassignedSymbol.WriteCount: Integer;
begin
  Result := Writes + LoopWrites;
end;

function TReassignedSymbol.IsReassigned: Boolean;
begin
  case Kind of
    TReassignedKind.Local, TReassignedKind.InlineVariable:
      Result := Writes > 1;
    TReassignedKind.Field:
      Result := (Writes > 0) and (WriterCount = 1) and not InConstructor;
  else
    Result := WriteCount > 0;
  end;
end;

function TReassignedSymbol.IsConstCandidate: Boolean;
begin
  Result := (Kind in [TReassignedKind.Local, TReassignedKind.InlineVariable]) and (Writes = 1) and
    (LoopWrites = 0) and (MaybeWrites = 0);
end;

function TReassignedSymbol.WriteLines: TArray<Integer>;
var
  mOccurrence: TReassignedOccurrence;
  mLine: Integer;
  mKnown: Boolean;
begin
  Result := nil;
  for mOccurrence in Occurrences do
  begin
    if mOccurrence.Write in [TReassignedWrite.Write, TReassignedWrite.LoopWrite] then
    begin
      mKnown := False;
      for mLine in Result do
      begin
        if mLine = mOccurrence.Range.StartPos.Line then
        begin
          mKnown := True;
        end;
      end;
      if not mKnown then
      begin
        Result := Result + [mOccurrence.Range.StartPos.Line];
      end;
    end;
  end;
end;

function TReassignedSymbol.OccurrenceAt(const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Occurrences) do
  begin
    if (Occurrences[mIndex].Range.StartPos.Line = APosition.Line) and
      (Occurrences[mIndex].Range.StartPos.Character <= APosition.Character) and
      (APosition.Character <= Occurrences[mIndex].Range.EndPos.Character) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TReassigned }

class function TReassigned.TryParseTarget(const AName: string; out ATarget: TReassignedTarget): Boolean;
var
  mTarget: TReassignedTarget;
begin
  for mTarget := Low(TReassignedTarget) to High(TReassignedTarget) do
  begin
    if SameText(cTargetNames[mTarget], Trim(AName)) then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
  ATarget := TReassignedTarget.Locals;
  Result := False;
end;

class function TReassigned.TargetsOf(const ANames: TArray<string>): TReassignedTargets;
var
  mName: string;
  mTarget: TReassignedTarget;
begin
  Result := [];
  for mName in ANames do
  begin
    if TryParseTarget(mName, mTarget) then
    begin
      Include(Result, mTarget);
    end;
  end;
end;

/// <summary>Schreibt das Elternteil von ANode direkt (Ziel einer Zuweisung, @X)? AWrite trägt die Art.</summary>
function DirectWrite(ANode: TSyntaxNode; out AWrite: TReassignedWrite): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  AWrite := TReassignedWrite.None;
  if (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent[0] = ANode) then
  begin
    AWrite := TReassignedWrite.Write;
  end
  else if mParent.Kind = TSyntaxKind.AddressOf then
  begin
    AWrite := TReassignedWrite.MaybeWrite;
  end;
  Result := AWrite <> TReassignedWrite.None;
end;

/// <summary>Äußerster Zugriff, der mit ANode beginnt: X.Feld, X[I], X^.</summary>
function AccessRoot(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Result.Parent[0] = Result) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Der Zugriff AAccess auf ANode als Argument des Aufrufs ACall: nach der Übergabeart.</summary>
function ArgumentWrite(ANode, AAccess, ACall: TSyntaxNode; const ALookup: TFlowSignatureLookup): TReassignedWrite;
var
  mIndex: Integer;
  mMode: TFlowArgumentMode;
begin
  mIndex := 0;
  while (mIndex < ACall.ChildCount) and (ACall[mIndex] <> AAccess) do
  begin
    Inc(mIndex);
  end;
  mMode := TFlowArgumentMode.Unknown;
  if Assigned(ALookup) then
  begin
    mMode := ALookup(ACall, mIndex - 1);
  end;
  if mMode = TFlowArgumentMode.Value then
  begin
    Result := TReassignedWrite.None;
  end
  else if (AAccess = ANode) and (mMode in [TFlowArgumentMode.Reference, TFlowArgumentMode.Output]) then
  begin
    Result := TReassignedWrite.Write;
  end
  else
  begin
    Result := TReassignedWrite.MaybeWrite;
  end;
end;

class function TReassigned.WriteOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TReassignedWrite;
var
  mAccess, mParent: TSyntaxNode;
begin
  Result := TReassignedWrite.None;
  if (ANode.Parent = nil) or DirectWrite(ANode, Result) then
  begin
    Exit;
  end;
  // Teil eines Ziels oder eines var-Arguments: X.Feld := …, X[I] := …, Inc(X.Zaehler)
  mAccess := AccessRoot(ANode);
  mParent := mAccess.Parent;
  if (mParent <> nil) and (mParent.Kind = TSyntaxKind.Call) and (mParent[0] <> mAccess) then
  begin
    Result := ArgumentWrite(ANode, mAccess, mParent, ALookup);
  end
  else if (mAccess <> ANode) and (mParent <> nil) and (mParent.Kind = TSyntaxKind.AssignStatement) and
    (mParent[0] = mAccess) then
  begin
    Result := TReassignedWrite.MaybeWrite;
  end;
end;

type
  /// <summary>Lauf über eine Datei; hält die Zwischenstände von Analyze.</summary>
  TReassignedRun = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FTokens: TArray<TPascalToken>;
    FLookup: TFlowSignatureLookup;
    FSymbols: TArray<TReassignedSymbol>;
    FRoutines: TList<TSyntaxNode>;
    FIdentifiers: TList<TSyntaxNode>;
    FSelfMembers: TList<TSyntaxNode>;
    FLoops: TList<TSyntaxNode>;
    FTypes: TList<TSyntaxNode>;
    FLocals: TDictionary<TSyntaxNode, TArray<TRoutineLocal>>;
    // Routine (Offset) und Index des lokalen Namens bzw. Klasse.Feld (klein) zum Eintrag in FSymbols.
    FKeys: TDictionary<string, Integer>;
    procedure Gather;
    procedure AddLocals(ARoutine: TSyntaxNode);
    /// <summary>Eintrag für den lokalen Namen ALocal mit Index AIndex der Routine ARoutine.</summary>
    procedure AddLocal(ARoutine: TSyntaxNode; AIndex: Integer; const ALocal: TRoutineLocal);
    /// <summary>Schreibzugriff der Deklaration von ASymbol am Namen AToken (Schleife, var X := …).</summary>
    function DeclarationWrite(const ASymbol: TReassignedSymbol; AToken: Integer): TReassignedWrite;
    procedure AddIdentifierUse(ANode: TSyntaxNode);
    procedure AddSelfMemberUse(ANode: TSyntaxNode);
    /// <summary>for I := … mit I aus dem var-Abschnitt (for var I deklariert selbst, siehe AddLocals).</summary>
    procedure AddLoopUse(ANode: TSyntaxNode);
    procedure AddFields(ATypeDecl: TSyntaxNode);
    function Add(const ASymbol: TReassignedSymbol): Integer;
    procedure AddOccurrence(AIndex: Integer; const ARange: TTextRange; AOffset: Integer; AWrite: TReassignedWrite;
      ANode: TSyntaxNode);
    procedure Count(AIndex: Integer; AWrite: TReassignedWrite; AMethod: TSyntaxNode);
    /// <summary>Eintrag des lokalen Namens AName, der an ANode gilt; -1 ohne, -2 bei einem Namen ohne Eintrag
    /// (Konstante, const-Parameter), der ein Feld verdeckt.</summary>
    function OwnerOf(ANode: TSyntaxNode; const AName: string; AOffset: Integer): Integer;
    /// <summary>Eintrag des Felds AName der Klasse der Methode, in der ANode steht; -1 ohne.</summary>
    function FieldOf(ANode: TSyntaxNode; const AName: string; out AMethod: TSyntaxNode): Integer;
    function NameToken(AFrom, ATo: Integer; const AName: string): Integer;
    function IsConstructor(AMethod: TSyntaxNode): Boolean;
    class function MethodOf(ANode: TSyntaxNode): TSyntaxNode; static;
    class function NamedRoutineOf(ARoutine: TSyntaxNode): string; static;
    class function ClassOf(const AMethodName: string): string; static;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const ALookup: TFlowSignatureLookup);
    destructor Destroy; override;
    function Run: TArray<TReassignedSymbol>;
  end;

constructor TReassignedRun.Create(const AText: string; ATree: TSyntaxTree; const ALookup: TFlowSignatureLookup);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FTokens := ATree.Tokens;
  FLookup := ALookup;
  if not Assigned(FLookup) then
  begin
    FLookup := TFlowSignatures.FromTree(ATree.Root);
  end;
  FRoutines := TList<TSyntaxNode>.Create;
  FIdentifiers := TList<TSyntaxNode>.Create;
  FSelfMembers := TList<TSyntaxNode>.Create;
  FLoops := TList<TSyntaxNode>.Create;
  FTypes := TList<TSyntaxNode>.Create;
  FLocals := TDictionary<TSyntaxNode, TArray<TRoutineLocal>>.Create;
  FKeys := TDictionary<string, Integer>.Create;
end;

destructor TReassignedRun.Destroy;
begin
  FKeys.Free;
  FLocals.Free;
  FTypes.Free;
  FLoops.Free;
  FSelfMembers.Free;
  FIdentifiers.Free;
  FRoutines.Free;
  inherited;
end;

procedure TReassignedRun.Gather;
var
  mRoutines, mIdentifiers, mSelfMembers, mLoops, mTypes: TList<TSyntaxNode>;
begin
  mRoutines := FRoutines;
  mIdentifiers := FIdentifiers;
  mSelfMembers := FSelfMembers;
  mLoops := FLoops;
  mTypes := FTypes;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      case ANode.Kind of
        TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
          if TRoutineBody.BodyOf(ANode) <> nil then
          begin
            mRoutines.Add(ANode);
          end;
        TSyntaxKind.Identifier:
          mIdentifiers.Add(ANode);
        TSyntaxKind.MemberAccess:
          if (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
            SameText(ANode[0].Name, 'Self') then
          begin
            mSelfMembers.Add(ANode);
          end;
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
          mLoops.Add(ANode);
        TSyntaxKind.TypeDecl:
          mTypes.Add(ANode);
      else
        // Übrige Arten: nichts zu tun.
      end;
    end);
end;

function TReassignedRun.Add(const ASymbol: TReassignedSymbol): Integer;
begin
  Result := Length(FSymbols);
  FSymbols := FSymbols + [ASymbol];
end;

procedure TReassignedRun.AddOccurrence(AIndex: Integer; const ARange: TTextRange; AOffset: Integer;
  AWrite: TReassignedWrite; ANode: TSyntaxNode);
var
  mOccurrence: TReassignedOccurrence;
begin
  mOccurrence.Range := ARange;
  mOccurrence.Offset := AOffset;
  mOccurrence.Write := AWrite;
  mOccurrence.Node := ANode;
  FSymbols[AIndex].Occurrences := FSymbols[AIndex].Occurrences + [mOccurrence];
end;

procedure TReassignedRun.Count(AIndex: Integer; AWrite: TReassignedWrite; AMethod: TSyntaxNode);
begin
  case AWrite of
    TReassignedWrite.Write:
      Inc(FSymbols[AIndex].Writes);
    TReassignedWrite.LoopWrite:
      Inc(FSymbols[AIndex].LoopWrites);
    TReassignedWrite.MaybeWrite:
      Inc(FSymbols[AIndex].MaybeWrites);
    TReassignedWrite.None: ;
  end;
  if (FSymbols[AIndex].Kind <> TReassignedKind.Field) or
    not (AWrite in [TReassignedWrite.Write, TReassignedWrite.LoopWrite]) or (AMethod = nil) then
  begin
    Exit;
  end;
  if FSymbols[AIndex].Routine = nil then
  begin
    FSymbols[AIndex].Routine := AMethod;
    FSymbols[AIndex].RoutineName := AMethod.Name;
    FSymbols[AIndex].WriterCount := 1;
  end
  else if FSymbols[AIndex].Routine <> AMethod then
  begin
    Inc(FSymbols[AIndex].WriterCount);
  end;
  if IsConstructor(AMethod) then
  begin
    FSymbols[AIndex].InConstructor := True;
  end;
end;

function TReassignedRun.NameToken(AFrom, ATo: Integer; const AName: string): Integer;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(FTokens, AFrom);
  while (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < ATo) do
  begin
    if (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[mIndex].Text, AName) or SameText(FTokens[mIndex].Text, '&' + AName)) then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex);
  end;
  Result := -1;
end;

function TReassignedRun.IsConstructor(AMethod: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(FTokens, AMethod.StartOffset);
  if (mIndex <= High(FTokens)) and SameText(FTokens[mIndex].Text, 'class') then
  begin
    mIndex := TRoutineBody.NextToken(FTokens, mIndex);
  end;
  Result := (mIndex <= High(FTokens)) and SameText(FTokens[mIndex].Text, 'constructor');
end;

class function TReassignedRun.MethodOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and ((Result.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', Result.Name) = 0)) do
  begin
    Result := Result.Parent;
  end;
end;

class function TReassignedRun.NamedRoutineOf(ARoutine: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  mNode := ARoutine;
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    mNode := mNode.Parent;
  end;
  Result := '';
  if mNode <> nil then
  begin
    Result := mNode.Name;
  end;
end;

class function TReassignedRun.ClassOf(const AMethodName: string): string;
var
  mParts: TArray<string>;
begin
  // TFoo.Bar -> TFoo, TAussen.TInnen.Bar -> TInnen.
  mParts := AMethodName.Split(['.']);
  Result := '';
  if Length(mParts) >= 2 then
  begin
    Result := mParts[High(mParts) - 1];
  end;
end;

/// <summary>Art des Eintrags für ALocal; False für Namen ohne Eintrag (const-Parameter, Inline-Konstanten).</summary>
function LocalKindOf(const ALocal: TRoutineLocal; out AKind: TReassignedKind): Boolean;
begin
  Result := True;
  AKind := TReassignedKind.Local;
  case ALocal.Kind of
    TRoutineLocalKind.Parameter:
      case ALocal.Decl.Modifier of
        TParameterModifier.None:
          AKind := TReassignedKind.ValueParameter;
        TParameterModifier.VarParam, TParameterModifier.OutParam:
          AKind := TReassignedKind.VarParameter;
      else
        Result := False;
      end;
    TRoutineLocalKind.Variable:
      AKind := TReassignedKind.Local;
    TRoutineLocalKind.InlineVariable:
      begin
        AKind := TReassignedKind.InlineVariable;
        // Inline-Konstanten führt Collect als Inline-Variable.
        Result := ALocal.Decl.Kind = TSyntaxKind.InlineVar;
      end;
    TRoutineLocalKind.LoopVariable:
      AKind := TReassignedKind.LoopVariable;
  else
    Result := False;
  end;
end;

function TReassignedRun.DeclarationWrite(const ASymbol: TReassignedSymbol; AToken: Integer): TReassignedWrite;
var
  mAssign: Integer;
begin
  Result := TReassignedWrite.None;
  if ASymbol.Kind = TReassignedKind.LoopVariable then
  begin
    Result := TReassignedWrite.LoopWrite;
  end
  else if ASymbol.Kind = TReassignedKind.InlineVariable then
  begin
    // var X := …, var X: T := …: der Startwert ist die erste Zuweisung.
    mAssign := AToken;
    while (mAssign <= High(FTokens)) and (FTokens[mAssign].Offset < ASymbol.Decl.EndOffset) and
      not FTokens[mAssign].IsSymbol(':=') do
    begin
      Inc(mAssign);
    end;
    if (mAssign <= High(FTokens)) and (FTokens[mAssign].Offset < ASymbol.Decl.EndOffset) then
    begin
      Result := TReassignedWrite.Write;
    end;
  end;
end;

procedure TReassignedRun.AddLocal(ARoutine: TSyntaxNode; AIndex: Integer; const ALocal: TRoutineLocal);
var
  mSymbol: TReassignedSymbol;
  mToken: Integer;
  mWrite: TReassignedWrite;
begin
  mSymbol := Default(TReassignedSymbol);
  if not LocalKindOf(ALocal, mSymbol.Kind) then
  begin
    Exit;
  end;
  mSymbol.Name := ALocal.Name;
  mSymbol.Decl := ALocal.Decl;
  mSymbol.Routine := ARoutine;
  mSymbol.RoutineName := NamedRoutineOf(ARoutine);
  FKeys.Add(IntToStr(ARoutine.StartOffset) + ':' + IntToStr(AIndex), Add(mSymbol));
  mToken := NameToken(mSymbol.Decl.StartOffset, mSymbol.Decl.EndOffset, mSymbol.Name);
  if mToken < 0 then
  begin
    Exit;
  end;
  mWrite := DeclarationWrite(mSymbol, mToken);
  if (mSymbol.Kind = TReassignedKind.InlineVariable) and (mWrite = TReassignedWrite.Write) then
  begin
    FSymbols[High(FSymbols)].Initialized := True;
  end;
  AddOccurrence(High(FSymbols), TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos),
    FTokens[mToken].Offset, mWrite, nil);
  Count(High(FSymbols), mWrite, nil);
end;

procedure TReassignedRun.AddLocals(ARoutine: TSyntaxNode);
var
  mLocals: TArray<TRoutineLocal>;
  mIndex: Integer;
begin
  mLocals := TRoutineLocals.Collect(FText, FTree, ARoutine);
  FLocals.AddOrSetValue(ARoutine, mLocals);
  for mIndex := 0 to High(mLocals) do
  begin
    AddLocal(ARoutine, mIndex, mLocals[mIndex]);
  end;
end;

procedure TReassignedRun.AddFields(ATypeDecl: TSyntaxNode);
var
  mBody, mNode: TSyntaxNode;
  mFields: TList<TSyntaxNode>;
  mName, mKey: string;
  mSymbol: TReassignedSymbol;
  mIndex, mToken: Integer;
begin
  mBody := nil;
  for mIndex := 0 to ATypeDecl.ChildCount - 1 do
  begin
    if ATypeDecl[mIndex].Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType] then
    begin
      mBody := ATypeDecl[mIndex];
    end;
  end;
  if mBody = nil then
  begin
    Exit;
  end;
  mFields := TList<TSyntaxNode>.Create;
  try
    mBody.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // Geschachtelte Typen bringen eigene Felder mit; Methoden und Properties haben keine.
        Result := not (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl,
          TSyntaxKind.PropertyDecl, TSyntaxKind.Field]);
        if ANode.Kind = TSyntaxKind.Field then
        begin
          mFields.Add(ANode);
        end;
      end);
    for mNode in mFields do
    begin
      for mName in mNode.Name.Split([',']) do
      begin
        mKey := LowerCase(ATypeDecl.Name + '.' + Trim(mName));
        if FKeys.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mSymbol := Default(TReassignedSymbol);
        mSymbol.Name := Trim(mName);
        mSymbol.Kind := TReassignedKind.Field;
        mSymbol.Decl := mNode;
        FKeys.Add(mKey, Add(mSymbol));
        mToken := NameToken(mNode.StartOffset, mNode.EndOffset, mSymbol.Name);
        if mToken >= 0 then
        begin
          AddOccurrence(High(FSymbols), TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos),
            FTokens[mToken].Offset, TReassignedWrite.None, nil);
        end;
      end;
    end;
  finally
    mFields.Free;
  end;
end;

function TReassignedRun.OwnerOf(ANode: TSyntaxNode; const AName: string; AOffset: Integer): Integer;
var
  mRoutine, mBody: TSyntaxNode;
  mLocals: TArray<TRoutineLocal>;
  mOffset, mIndex: Integer;
begin
  mRoutine := ANode.Parent;
  while mRoutine <> nil do
  begin
    if FLocals.TryGetValue(mRoutine, mLocals) then
    begin
      mBody := TRoutineBody.BodyOf(mRoutine);
      mOffset := AOffset;
      // Aus einer verschachtelten Routine heraus gelten die Namen der äußeren vor ihrem Rumpf.
      if (mOffset < mBody.StartOffset) or (mOffset > mBody.EndOffset) then
      begin
        mOffset := mBody.StartOffset;
      end;
      mIndex := TRoutineLocals.IndexOf(mLocals, AName, mOffset);
      if mIndex >= 0 then
      begin
        if FKeys.TryGetValue(IntToStr(mRoutine.StartOffset) + ':' + IntToStr(mIndex), Result) then
        begin
          Exit;
        end;
        Exit(-2);
      end;
    end;
    mRoutine := mRoutine.Parent;
  end;
  Result := -1;
end;

function TReassignedRun.FieldOf(ANode: TSyntaxNode; const AName: string; out AMethod: TSyntaxNode): Integer;
begin
  Result := -1;
  AMethod := MethodOf(ANode);
  if (AMethod = nil) or not FKeys.TryGetValue(LowerCase(ClassOf(AMethod.Name) + '.' + AName), Result) or
    (FSymbols[Result].Kind <> TReassignedKind.Field) then
  begin
    Result := -1;
  end;
end;

procedure TReassignedRun.AddIdentifierUse(ANode: TSyntaxNode);
var
  mMethod: TSyntaxNode;
  mIndex: Integer;
  mWrite: TReassignedWrite;
begin
  mMethod := nil;
  mIndex := OwnerOf(ANode, ANode.Name, ANode.StartOffset);
  if mIndex = -1 then
  begin
    mIndex := FieldOf(ANode, ANode.Name, mMethod);
  end;
  if mIndex >= 0 then
  begin
    mWrite := TReassigned.WriteOf(ANode, FLookup);
    AddOccurrence(mIndex, TTextRange.Create(ANode.StartPos, ANode.EndPos), ANode.StartOffset, mWrite, ANode);
    Count(mIndex, mWrite, mMethod);
  end;
end;

procedure TReassignedRun.AddSelfMemberUse(ANode: TSyntaxNode);
var
  mMethod: TSyntaxNode;
  mIndex, mToken: Integer;
  mWrite: TReassignedWrite;
begin
  mIndex := FieldOf(ANode, ANode.Name, mMethod);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mToken := NameToken(ANode[0].EndOffset, ANode.EndOffset + 1, ANode.Name);
  if mToken < 0 then
  begin
    Exit;
  end;
  mWrite := TReassigned.WriteOf(ANode, FLookup);
  AddOccurrence(mIndex, TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos), FTokens[mToken].Offset,
    mWrite, ANode);
  Count(mIndex, mWrite, mMethod);
end;

procedure TReassignedRun.AddLoopUse(ANode: TSyntaxNode);
var
  mIndex, mToken: Integer;
begin
  if (ANode.Name = '') or TRoutineLocals.IsInlineFor(FTokens, ANode) then
  begin
    Exit;
  end;
  mIndex := OwnerOf(ANode, ANode.Name, ANode.StartOffset);
  mToken := -1;
  if mIndex >= 0 then
  begin
    mToken := NameToken(ANode.StartOffset, ANode.EndOffset, ANode.Name);
  end;
  if mToken < 0 then
  begin
    Exit;
  end;
  AddOccurrence(mIndex, TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos), FTokens[mToken].Offset,
    TReassignedWrite.LoopWrite, ANode);
  Count(mIndex, TReassignedWrite.LoopWrite, nil);
  if FSymbols[mIndex].Kind = TReassignedKind.Local then
  begin
    FSymbols[mIndex].Kind := TReassignedKind.LoopVariable;
  end;
end;

/// <summary>Vorkommen nach Offset, bei Gleichstand nach Art.</summary>
function OccurrenceComparer: IComparer<TReassignedOccurrence>;
begin
  Result := TComparer<TReassignedOccurrence>.Construct(
    function(const ALeft, ARight: TReassignedOccurrence): Integer
    begin
      Result := ALeft.Offset - ARight.Offset;
      if Result = 0 then
      begin
        Result := Ord(ALeft.Write) - Ord(ARight.Write);
      end;
    end);
end;

function TReassignedRun.Run: TArray<TReassignedSymbol>;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
  mOccurrences: TArray<TReassignedOccurrence>;
begin
  Gather;
  for mNode in FTypes do
  begin
    AddFields(mNode);
  end;
  for mNode in FRoutines do
  begin
    AddLocals(mNode);
  end;
  for mNode in FIdentifiers do
  begin
    AddIdentifierUse(mNode);
  end;
  for mNode in FSelfMembers do
  begin
    AddSelfMemberUse(mNode);
  end;
  for mNode in FLoops do
  begin
    AddLoopUse(mNode);
  end;
  for mIndex := 0 to High(FSymbols) do
  begin
    mOccurrences := FSymbols[mIndex].Occurrences;
    TArray.Sort<TReassignedOccurrence>(mOccurrences, OccurrenceComparer);
    FSymbols[mIndex].Occurrences := mOccurrences;
  end;
  Result := FSymbols;
end;

class function TReassigned.Analyze(const AText: string; ATree: TSyntaxTree;
  const ALookup: TFlowSignatureLookup): TArray<TReassignedSymbol>;
var
  mRun: TReassignedRun;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mRun := TReassignedRun.Create(AText, ATree, ALookup);
  try
    Result := mRun.Run;
  finally
    mRun.Free;
  end;
end;

class function TReassigned.Filter(const ASymbols: TArray<TReassignedSymbol>;
  ATargets: TReassignedTargets): TArray<TReassignedSymbol>;
var
  mSymbol: TReassignedSymbol;
begin
  Result := nil;
  for mSymbol in ASymbols do
  begin
    if (mSymbol.Target in ATargets) and mSymbol.IsReassigned then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

class function TReassigned.SymbolAt(const ASymbols: TArray<TReassignedSymbol>; const APosition: TTextPosition;
  out ASymbol: TReassignedSymbol): Boolean;
var
  mSymbol: TReassignedSymbol;
begin
  for mSymbol in ASymbols do
  begin
    if mSymbol.OccurrenceAt(APosition) >= 0 then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  ASymbol := Default(TReassignedSymbol);
  Result := False;
end;

end.
