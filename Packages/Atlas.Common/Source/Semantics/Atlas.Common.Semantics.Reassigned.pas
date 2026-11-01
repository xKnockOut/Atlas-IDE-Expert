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
    DefaultTargets = [TReassignedTarget.Locals, TReassignedTarget.ValueParams];
    TargetNames: array[TReassignedTarget] of string = ('locals', 'loopVars', 'valueParams', 'varParams', 'fields');
    KindNames: array[TReassignedKind] of string = ('local', 'inlineVariable', 'loopVariable', 'valueParameter',
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
  Occurrence: TReassignedOccurrence;
  Line: Integer;
  Known: Boolean;
begin
  Result := nil;
  for Occurrence in Occurrences do
  begin
    if Occurrence.Write in [TReassignedWrite.Write, TReassignedWrite.LoopWrite] then
    begin
      Known := False;
      for Line in Result do
      begin
        if Line = Occurrence.Range.StartPos.Line then
        begin
          Known := True;
        end;
      end;
      if not Known then
      begin
        Result := Result + [Occurrence.Range.StartPos.Line];
      end;
    end;
  end;
end;

function TReassignedSymbol.OccurrenceAt(const APosition: TTextPosition): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Occurrences) do
  begin
    if (Occurrences[Index].Range.StartPos.Line = APosition.Line) and
      (Occurrences[Index].Range.StartPos.Character <= APosition.Character) and
      (APosition.Character <= Occurrences[Index].Range.EndPos.Character) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

{ TReassigned }

class function TReassigned.TryParseTarget(const AName: string; out ATarget: TReassignedTarget): Boolean;
var
  Target: TReassignedTarget;
begin
  for Target := Low(TReassignedTarget) to High(TReassignedTarget) do
  begin
    if SameText(TargetNames[Target], Trim(AName)) then
    begin
      ATarget := Target;
      Exit(True);
    end;
  end;
  ATarget := TReassignedTarget.Locals;
  Result := False;
end;

class function TReassigned.TargetsOf(const ANames: TArray<string>): TReassignedTargets;
var
  Name: string;
  Target: TReassignedTarget;
begin
  Result := [];
  for Name in ANames do
  begin
    if TryParseTarget(Name, Target) then
    begin
      Include(Result, Target);
    end;
  end;
end;

class function TReassigned.WriteOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TReassignedWrite;
var
  Node, Parent: TSyntaxNode;
  Index: Integer;
  Mode: TFlowArgumentMode;
begin
  Result := TReassignedWrite.None;
  Parent := ANode.Parent;
  if Parent = nil then
  begin
    Exit;
  end;
  if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = ANode) then
  begin
    Exit(TReassignedWrite.Write);
  end;
  if Parent.Kind = TSyntaxKind.AddressOf then
  begin
    Exit(TReassignedWrite.MaybeWrite);
  end;
  // Teil eines Ziels oder eines var-Arguments: X.Feld := …, X[I] := …, Inc(X.Zaehler)
  Node := ANode;
  while (Node.Parent <> nil) and (Node.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Node.Parent[0] = Node) do
  begin
    Node := Node.Parent;
  end;
  Parent := Node.Parent;
  if (Parent = nil) or (Parent.Kind <> TSyntaxKind.Call) or (Parent[0] = Node) then
  begin
    if (Node <> ANode) and (Parent <> nil) and (Parent.Kind = TSyntaxKind.AssignStatement) and
      (Parent[0] = Node) then
    begin
      Result := TReassignedWrite.MaybeWrite;
    end;
    Exit;
  end;
  Index := 0;
  while (Index < Parent.ChildCount) and (Parent[Index] <> Node) do
  begin
    Inc(Index);
  end;
  Mode := TFlowArgumentMode.Unknown;
  if Assigned(ALookup) then
  begin
    Mode := ALookup(Parent, Index - 1);
  end;
  if Mode = TFlowArgumentMode.Value then
  begin
    Exit;
  end;
  if (Node = ANode) and (Mode in [TFlowArgumentMode.Reference, TFlowArgumentMode.Output]) then
  begin
    Result := TReassignedWrite.Write;
  end
  else
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
  Routines, Identifiers, SelfMembers, Loops, Types: TList<TSyntaxNode>;
begin
  Routines := FRoutines;
  Identifiers := FIdentifiers;
  SelfMembers := FSelfMembers;
  Loops := FLoops;
  Types := FTypes;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      case ANode.Kind of
        TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
          if TRoutineBody.BodyOf(ANode) <> nil then
          begin
            Routines.Add(ANode);
          end;
        TSyntaxKind.Identifier:
          Identifiers.Add(ANode);
        TSyntaxKind.MemberAccess:
          if (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
            SameText(ANode[0].Name, 'Self') then
          begin
            SelfMembers.Add(ANode);
          end;
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
          Loops.Add(ANode);
        TSyntaxKind.TypeDecl:
          Types.Add(ANode);
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
  Occurrence: TReassignedOccurrence;
begin
  Occurrence.Range := ARange;
  Occurrence.Offset := AOffset;
  Occurrence.Write := AWrite;
  Occurrence.Node := ANode;
  FSymbols[AIndex].Occurrences := FSymbols[AIndex].Occurrences + [Occurrence];
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
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(FTokens, AFrom);
  while (Index <= High(FTokens)) and (FTokens[Index].Offset < ATo) do
  begin
    if (FTokens[Index].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[Index].Text, AName) or SameText(FTokens[Index].Text, '&' + AName)) then
    begin
      Exit(Index);
    end;
    Inc(Index);
  end;
  Result := -1;
end;

function TReassignedRun.IsConstructor(AMethod: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(FTokens, AMethod.StartOffset);
  if (Index <= High(FTokens)) and SameText(FTokens[Index].Text, 'class') then
  begin
    Index := TRoutineBody.NextToken(FTokens, Index);
  end;
  Result := (Index <= High(FTokens)) and SameText(FTokens[Index].Text, 'constructor');
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
  Node: TSyntaxNode;
begin
  Node := ARoutine;
  while (Node <> nil) and (Node.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Node := Node.Parent;
  end;
  Result := '';
  if Node <> nil then
  begin
    Result := Node.Name;
  end;
end;

class function TReassignedRun.ClassOf(const AMethodName: string): string;
var
  Parts: TArray<string>;
begin
  // TFoo.Bar -> TFoo, TAussen.TInnen.Bar -> TInnen.
  Parts := AMethodName.Split(['.']);
  Result := '';
  if Length(Parts) >= 2 then
  begin
    Result := Parts[High(Parts) - 1];
  end;
end;

procedure TReassignedRun.AddLocals(ARoutine: TSyntaxNode);
var
  Locals: TArray<TRoutineLocal>;
  Index, Token, Assign: Integer;
  Symbol: TReassignedSymbol;
  Write: TReassignedWrite;
  Usable: Boolean;
begin
  Locals := TRoutineLocals.Collect(FText, FTree, ARoutine);
  FLocals.AddOrSetValue(ARoutine, Locals);
  for Index := 0 to High(Locals) do
  begin
    Symbol := Default(TReassignedSymbol);
    Symbol.Name := Locals[Index].Name;
    Symbol.Decl := Locals[Index].Decl;
    Symbol.Routine := ARoutine;
    Symbol.RoutineName := NamedRoutineOf(ARoutine);
    Usable := True;
    case Locals[Index].Kind of
      TRoutineLocalKind.Parameter:
        case Locals[Index].Decl.Modifier of
          TParameterModifier.None:
            Symbol.Kind := TReassignedKind.ValueParameter;
          TParameterModifier.VarParam, TParameterModifier.OutParam:
            Symbol.Kind := TReassignedKind.VarParameter;
        else
          Usable := False;
        end;
      TRoutineLocalKind.Variable:
        Symbol.Kind := TReassignedKind.Local;
      TRoutineLocalKind.InlineVariable:
        begin
          Symbol.Kind := TReassignedKind.InlineVariable;
          // Inline-Konstanten führt Collect als Inline-Variable.
          Usable := Locals[Index].Decl.Kind = TSyntaxKind.InlineVar;
        end;
      TRoutineLocalKind.LoopVariable:
        Symbol.Kind := TReassignedKind.LoopVariable;
    else
      Usable := False;
    end;
    if not Usable then
    begin
      Continue;
    end;
    FKeys.Add(IntToStr(ARoutine.StartOffset) + ':' + IntToStr(Index), Add(Symbol));
    Token := NameToken(Symbol.Decl.StartOffset, Symbol.Decl.EndOffset, Symbol.Name);
    if Token < 0 then
    begin
      Continue;
    end;
    Write := TReassignedWrite.None;
    if Symbol.Kind = TReassignedKind.LoopVariable then
    begin
      Write := TReassignedWrite.LoopWrite;
    end
    else if Symbol.Kind = TReassignedKind.InlineVariable then
    begin
      // var X := …, var X: T := …: der Startwert ist die erste Zuweisung.
      Assign := Token;
      while (Assign <= High(FTokens)) and (FTokens[Assign].Offset < Symbol.Decl.EndOffset) and
        not FTokens[Assign].IsSymbol(':=') do
      begin
        Inc(Assign);
      end;
      if (Assign <= High(FTokens)) and (FTokens[Assign].Offset < Symbol.Decl.EndOffset) then
      begin
        Write := TReassignedWrite.Write;
        FSymbols[High(FSymbols)].Initialized := True;
      end;
    end;
    AddOccurrence(High(FSymbols), TTextRange.Create(FTokens[Token].StartPos, FTokens[Token].EndPos),
      FTokens[Token].Offset, Write, nil);
    Count(High(FSymbols), Write, nil);
  end;
end;

procedure TReassignedRun.AddFields(ATypeDecl: TSyntaxNode);
var
  Body, Node: TSyntaxNode;
  Fields: TList<TSyntaxNode>;
  Name, Key: string;
  Symbol: TReassignedSymbol;
  Index, Token: Integer;
begin
  Body := nil;
  for Index := 0 to ATypeDecl.ChildCount - 1 do
  begin
    if ATypeDecl[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType] then
    begin
      Body := ATypeDecl[Index];
    end;
  end;
  if Body = nil then
  begin
    Exit;
  end;
  Fields := TList<TSyntaxNode>.Create;
  try
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // Geschachtelte Typen bringen eigene Felder mit; Methoden und Properties haben keine.
        Result := not (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl,
          TSyntaxKind.PropertyDecl, TSyntaxKind.Field]);
        if ANode.Kind = TSyntaxKind.Field then
        begin
          Fields.Add(ANode);
        end;
      end);
    for Node in Fields do
    begin
      for Name in Node.Name.Split([',']) do
      begin
        Key := LowerCase(ATypeDecl.Name + '.' + Trim(Name));
        if FKeys.ContainsKey(Key) then
        begin
          Continue;
        end;
        Symbol := Default(TReassignedSymbol);
        Symbol.Name := Trim(Name);
        Symbol.Kind := TReassignedKind.Field;
        Symbol.Decl := Node;
        FKeys.Add(Key, Add(Symbol));
        Token := NameToken(Node.StartOffset, Node.EndOffset, Symbol.Name);
        if Token >= 0 then
        begin
          AddOccurrence(High(FSymbols), TTextRange.Create(FTokens[Token].StartPos, FTokens[Token].EndPos),
            FTokens[Token].Offset, TReassignedWrite.None, nil);
        end;
      end;
    end;
  finally
    Fields.Free;
  end;
end;

function TReassignedRun.OwnerOf(ANode: TSyntaxNode; const AName: string; AOffset: Integer): Integer;
var
  Routine, Body: TSyntaxNode;
  Locals: TArray<TRoutineLocal>;
  Offset, Index: Integer;
begin
  Routine := ANode.Parent;
  while Routine <> nil do
  begin
    if FLocals.TryGetValue(Routine, Locals) then
    begin
      Body := TRoutineBody.BodyOf(Routine);
      Offset := AOffset;
      // Aus einer verschachtelten Routine heraus gelten die Namen der äußeren vor ihrem Rumpf.
      if (Offset < Body.StartOffset) or (Offset > Body.EndOffset) then
      begin
        Offset := Body.StartOffset;
      end;
      Index := TRoutineLocals.IndexOf(Locals, AName, Offset);
      if Index >= 0 then
      begin
        if FKeys.TryGetValue(IntToStr(Routine.StartOffset) + ':' + IntToStr(Index), Result) then
        begin
          Exit;
        end;
        Exit(-2);
      end;
    end;
    Routine := Routine.Parent;
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

function TReassignedRun.Run: TArray<TReassignedSymbol>;
var
  Node, Method: TSyntaxNode;
  Index, Token: Integer;
  Write: TReassignedWrite;
  Symbol: TReassignedSymbol;
begin
  Gather;
  for Node in FTypes do
  begin
    AddFields(Node);
  end;
  for Node in FRoutines do
  begin
    AddLocals(Node);
  end;
  for Node in FIdentifiers do
  begin
    Method := nil;
    Index := OwnerOf(Node, Node.Name, Node.StartOffset);
    if Index = -1 then
    begin
      Index := FieldOf(Node, Node.Name, Method);
    end;
    if Index < 0 then
    begin
      Continue;
    end;
    Write := TReassigned.WriteOf(Node, FLookup);
    AddOccurrence(Index, TTextRange.Create(Node.StartPos, Node.EndPos), Node.StartOffset, Write, Node);
    Count(Index, Write, Method);
  end;
  for Node in FSelfMembers do
  begin
    Index := FieldOf(Node, Node.Name, Method);
    if Index < 0 then
    begin
      Continue;
    end;
    Token := NameToken(Node[0].EndOffset, Node.EndOffset + 1, Node.Name);
    if Token < 0 then
    begin
      Continue;
    end;
    Write := TReassigned.WriteOf(Node, FLookup);
    AddOccurrence(Index, TTextRange.Create(FTokens[Token].StartPos, FTokens[Token].EndPos), FTokens[Token].Offset,
      Write, Node);
    Count(Index, Write, Method);
  end;
  // for I := … mit I aus dem var-Abschnitt (for var I deklariert selbst, siehe AddLocals).
  for Node in FLoops do
  begin
    if (Node.Name = '') or TRoutineLocals.IsInlineFor(FTokens, Node) then
    begin
      Continue;
    end;
    Index := OwnerOf(Node, Node.Name, Node.StartOffset);
    if Index < 0 then
    begin
      Continue;
    end;
    Token := NameToken(Node.StartOffset, Node.EndOffset, Node.Name);
    if Token < 0 then
    begin
      Continue;
    end;
    AddOccurrence(Index, TTextRange.Create(FTokens[Token].StartPos, FTokens[Token].EndPos), FTokens[Token].Offset,
      TReassignedWrite.LoopWrite, Node);
    Count(Index, TReassignedWrite.LoopWrite, nil);
    if FSymbols[Index].Kind = TReassignedKind.Local then
    begin
      FSymbols[Index].Kind := TReassignedKind.LoopVariable;
    end;
  end;
  for Index := 0 to High(FSymbols) do
  begin
    Symbol := FSymbols[Index];
    TArray.Sort<TReassignedOccurrence>(Symbol.Occurrences, TComparer<TReassignedOccurrence>.Construct(
      function(const ALeft, ARight: TReassignedOccurrence): Integer
      begin
        Result := ALeft.Offset - ARight.Offset;
        if Result = 0 then
        begin
          Result := Ord(ALeft.Write) - Ord(ARight.Write);
        end;
      end));
    FSymbols[Index].Occurrences := Symbol.Occurrences;
  end;
  Result := FSymbols;
end;

class function TReassigned.Analyze(const AText: string; ATree: TSyntaxTree;
  const ALookup: TFlowSignatureLookup): TArray<TReassignedSymbol>;
var
  Run: TReassignedRun;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Run := TReassignedRun.Create(AText, ATree, ALookup);
  try
    Result := Run.Run;
  finally
    Run.Free;
  end;
end;

class function TReassigned.Filter(const ASymbols: TArray<TReassignedSymbol>;
  ATargets: TReassignedTargets): TArray<TReassignedSymbol>;
var
  Symbol: TReassignedSymbol;
begin
  Result := nil;
  for Symbol in ASymbols do
  begin
    if (Symbol.Target in ATargets) and Symbol.IsReassigned then
    begin
      Result := Result + [Symbol];
    end;
  end;
end;

class function TReassigned.SymbolAt(const ASymbols: TArray<TReassignedSymbol>; const APosition: TTextPosition;
  out ASymbol: TReassignedSymbol): Boolean;
var
  Symbol: TReassignedSymbol;
begin
  for Symbol in ASymbols do
  begin
    if Symbol.OccurrenceAt(APosition) >= 0 then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  end;
  ASymbol := Default(TReassignedSymbol);
  Result := False;
end;

end.
