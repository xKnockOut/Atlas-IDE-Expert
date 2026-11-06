unit Atlas.Common.Rules.Builtin.Ownership.RawMemory;

// Regel aus Atlas.Common.Rules.Builtin.Ownership ausgelagert (Länge der Unit):
//   raw-memory-leak   lokaler Zeiger aus GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, den
//                     die Routine nie freigibt und der sie nicht verlässt (#1047): Jedes Vorkommen wird im
//                     Syntaxbaum nach oben eingeordnet (Belegung, Freigabe, Zugriff, Weitergabe als Ergebnis,
//                     Zuweisung, @P, Add/Insert…, anonyme Methode, lokale Routine). Lesen und Füllen über ein
//                     Argument ist erlaubt; Routinen mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen
//                     gelten als Freigabe. Korrektur: try … finally mit FreeMem, Dispose bzw. StrDispose.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TRawMemoryLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Passende Freigabe zur Belegung AAllocator (GetMem → FreeMem, New → Dispose, StrAlloc →
    /// StrDispose); '' für eine unbekannte Belegung.</summary>
    class function ReleaseFor(const AAllocator: string): string; static;
  end;

/// <summary>Registriert die Regel raw-memory-leak.</summary>
procedure RegisterOwnershipRawMemoryRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Ownership.TryFinally,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TOwnershipRawMemoryText = (Title, InsertTryFinally, NeverReleased);

const
  cTexts: array[TOwnershipRawMemoryText] of TAtlasText = (
    (De: 'GetMem oder New ohne Freigabe'; En: 'GetMem or New without release'),
    (De: 'try … finally %s(%s) end einfügen'; En: 'Insert try … finally %s(%s) end'),
    (De: '%s wird mit %s angelegt, aber nie freigegeben.'; En: '%s is allocated with %s but never released.'));

{$SCOPEDENUMS OFF}

const
  RawMemoryLeakRuleId = 'raw-memory-leak';

{ TRawMemoryLeakRule }

type
  /// <summary>Wie eine lokale Variable an einer Stelle vorkommt (raw-memory-leak, #1047).</summary>
{$SCOPEDENUMS ON}
  TRawMemoryUse = (Use, Alloc, Release, Escape);
{$SCOPEDENUMS OFF}

const
  // Belegungen mit der Variablen als erstem Argument bzw. als Ziel der Zuweisung.
  RawAllocCalls: array[0..2] of string = ('GetMem', 'New', 'ReallocMem');
  RawAllocFunctions: array[0..4] of string = ('AllocMem', 'GetMemory', 'StrAlloc', 'StrNew', 'AnsiStrAlloc');
  RawReleaseCalls: array[0..4] of string = ('FreeMem', 'Dispose', 'StrDispose', 'FreeMemory', 'FreeMemAndNil');
  // Methoden, die den Zeiger übernehmen (in Listen, Felder anderer Objekte).
  RawStorePrefixes: array[0..11] of string = ('Add', 'Insert', 'Push', 'Enqueue', 'Put', 'Store', 'Register',
    'Attach', 'Append', 'Set', 'Assign', 'TryAdd');
  // Teile eines Routinennamens, die auf eine eigene Freigaberoutine schließen lassen.
  RawReleaseWords: array[0..5] of string = ('Free', 'Frei', 'Release', 'Dispose', 'Destroy', 'Dealloc');

function TRawMemoryLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RawMemoryLeakRuleId, TRuleSeverity.Warning,
    cTexts[TOwnershipRawMemoryText.Title].Text);
end;

class function TRawMemoryLeakRule.ReleaseFor(const AAllocator: string): string;
begin
  if MatchText(AAllocator, ['GetMem', 'AllocMem', 'ReallocMem']) then
  begin
    Result := 'FreeMem';
  end
  else if SameText(AAllocator, 'GetMemory') then
  begin
    Result := 'FreeMemory';
  end
  else if SameText(AAllocator, 'New') then
  begin
    Result := 'Dispose';
  end
  else if MatchText(AAllocator, ['StrAlloc', 'StrNew', 'AnsiStrAlloc']) then
  begin
    Result := 'StrDispose';
  end
  else
  begin
    Result := '';
  end;
end;

function StartsWithAny(const AName: string; const APrefixes: array of string): Boolean;
var
  Prefix: string;
begin
  for Prefix in APrefixes do
  begin
    if StartsText(Prefix, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ContainsAny(const AName: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
  begin
    if ContainsText(AName, Word) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Typumwandlung wie PByte(P), PChar(P), Pointer(P): ein Argument, Aufruf über einen Typnamen.
function IsTypeCast(ACall: TSyntaxNode): Boolean;
var
  Name: string;
begin
  Result := False;
  if (ACall.ChildCount <> 2) or (ACall[0].Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  Name := ACall[0].Name;
  Result := MatchText(Name, ['Pointer', 'NativeInt', 'NativeUInt', 'IntPtr', 'UIntPtr', 'PChar', 'PAnsiChar',
    'PWideChar', 'PByte', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'LongInt', 'LongWord']) or
    ((Length(Name) > 1) and CharInSet(Name[1], ['P', 'T']) and CharInSet(Name[2], ['A'..'Z']));
end;

// Art des Vorkommens ANode (Bezeichner der Variablen) vom Knoten aus nach oben bis zur Anweisung.
/// <summary>Belegung an ACall mit der Variablen als erstem Argument; ReallocMem(P, 0) gibt frei.</summary>
function AllocUse(ACall: TSyntaxNode): TRawMemoryUse;
begin
  Result := TRawMemoryUse.Alloc;
  if SameText(ACall.Name, 'ReallocMem') and (ACall.ChildCount = 3) and (ACall[2].Kind = TSyntaxKind.Literal) and
    (ACall[2].Name = '0') then
  begin
    Result := TRawMemoryUse.Release;
  end;
end;

/// <summary>Art des Vorkommens ACurrent als Teil des Aufrufs ACall; False bei einer Typumwandlung (weiter nach
/// oben).</summary>
function UseInCall(ACall, ACurrent: TSyntaxNode; ADirect: Boolean; out AUse: TRawMemoryUse): Boolean;
begin
  Result := True;
  AUse := TRawMemoryUse.Use;
  if ACall[0] = ACurrent then
  begin
    AUse := TRawMemoryUse.Use;
  end
  else if ADirect and (ACall[1] = ACurrent) and MatchText(ACall.Name, RawAllocCalls) then
  begin
    AUse := AllocUse(ACall);
  end
  else if MatchText(ACall.Name, RawReleaseCalls) or ContainsAny(ACall.Name, RawReleaseWords) then
  begin
    AUse := TRawMemoryUse.Release;
  end
  else if SameText(ACall.Name, 'Exit') then
  begin
    AUse := TRawMemoryUse.Escape;
  end
  else if IsTypeCast(ACall) then
  begin
    Result := False;
  end
  else if (ACall[0].Kind = TSyntaxKind.MemberAccess) and StartsWithAny(ACall.Name, RawStorePrefixes) then
  begin
    AUse := TRawMemoryUse.Escape;
  end;
  // Sonst als Argument zum Lesen oder Füllen weitergegeben (Pruefsumme(P, N), Stream.ReadBuffer(P^, N)).
end;

/// <summary>Art des Vorkommens ACurrent in der Zuweisung AAssign.</summary>
function UseInAssign(AAssign, ACurrent: TSyntaxNode; ADirect: Boolean): TRawMemoryUse;
var
  mValue: TSyntaxNode;
begin
  if AAssign[0] <> ACurrent then
  begin
    Exit(TRawMemoryUse.Escape);
  end;
  if not ADirect then
  begin
    Exit(TRawMemoryUse.Use);
  end;
  mValue := nil;
  if AAssign.ChildCount > 1 then
  begin
    mValue := AAssign[1];
  end;
  // Neue Zuweisung (P := Q, P := nil): Herkunft unklar.
  Result := TRawMemoryUse.Escape;
  if (mValue <> nil) and (mValue.Kind = TSyntaxKind.Call) and MatchText(mValue.Name, RawAllocFunctions) then
  begin
    Result := TRawMemoryUse.Alloc;
  end;
end;

// Art des Vorkommens ANode (Bezeichner der Variablen) vom Knoten aus nach oben bis zur Anweisung.
function Classify(ANode: TSyntaxNode): TRawMemoryUse;
var
  mCurrent, mParent: TSyntaxNode;
  mDirect, mDone: Boolean;
begin
  Result := TRawMemoryUse.Use;
  mCurrent := ANode;
  mDirect := True;
  mDone := False;
  while not mDone and (mCurrent.Parent <> nil) do
  begin
    mParent := mCurrent.Parent;
    Result := TRawMemoryUse.Use;
    mDone := True;
    case mParent.Kind of
      // P^, P.Feld, P[I]: Zugriff auf den Speicher.
      TSyntaxKind.Dereference, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess:
        Result := TRawMemoryUse.Use;
      TSyntaxKind.AddressOf, TSyntaxKind.InlineVar, TSyntaxKind.VarDecl, TSyntaxKind.AnonymousMethod:
        Result := TRawMemoryUse.Escape;
      TSyntaxKind.Call:
        mDone := UseInCall(mParent, mCurrent, mDirect, Result);
      TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr:
        mDone := False;
      // Vergleiche lesen nur; P + N rechnet mit dem Zeiger weiter.
      TSyntaxKind.BinaryExpr:
        mDone := not MatchText(mParent.Name, ['+', '-']);
      TSyntaxKind.AssignStatement:
        Result := UseInAssign(mParent, mCurrent, mDirect);
    else
      Result := TRawMemoryUse.Use;
    end;
    mCurrent := mParent;
    mDirect := False;
  end;
end;

// Name der Belegung an der Anweisung des Vorkommens ANode.
function AllocatorOf(ANode: TSyntaxNode): string;
begin
  if ANode.Parent.Kind = TSyntaxKind.Call then
  begin
    Result := ANode.Parent.Name;
  end
  else
  begin
    Result := ANode.Parent[1].Name;
  end;
end;

procedure Occurrences(ANode: TSyntaxNode; const AName: string; var AFound: TArray<TSyntaxNode>);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) and
        not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.MemberAccess) and (Node.Parent[0] <> Node))
        then
      begin
        AFound := AFound + [Node];
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function HasAsm(ANode: TSyntaxNode): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.AsmBlock then
      begin
        Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

// Steht ANode in einer anonymen Methode der Routine (die Variable wird eingefangen)?
function InsideAnonymous(ANode, ARoutine: TSyntaxNode): Boolean;
var
  Current: TSyntaxNode;
begin
  Current := ANode.Parent;
  while (Current <> nil) and (Current <> ARoutine) do
  begin
    if Current.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(True);
    end;
    Current := Current.Parent;
  end;
  Result := False;
end;

// Die Anweisung, die das Vorkommen ANode enthält.
function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.AssignStatement]) do
  begin
    Result := Result.Parent;
  end;
end;

type
  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TRawMemoryScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<string>;
    FLineBreak: string;
    procedure CheckVariable(ARoutine: TSyntaxNode; const AName: string);
    procedure CheckSection(ARoutine, ASection: TSyntaxNode);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TRawMemoryScan }

constructor TRawMemoryScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Erste Belegung der Variablen in ARoutine, wenn kein Vorkommen sie freigibt oder weitergibt (auch nicht
/// in einer anonymen Methode); False sonst oder ohne Belegung.</summary>
function KeptAllocation(ARoutine: TSyntaxNode; const AName: string; out AFirst: TSyntaxNode): Boolean;
var
  mFound: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mUse: TRawMemoryUse;
begin
  mFound := nil;
  Occurrences(ARoutine, AName, mFound);
  AFirst := nil;
  for mNode in mFound do
  begin
    mUse := Classify(mNode);
    if (mUse in [TRawMemoryUse.Release, TRawMemoryUse.Escape]) or InsideAnonymous(mNode, ARoutine) then
    begin
      Exit(False);
    end;
    if (mUse = TRawMemoryUse.Alloc) and (AFirst = nil) then
    begin
      AFirst := mNode;
    end;
  end;
  Result := AFirst <> nil;
end;

function MentionedInLocalRoutine(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mFound: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mFound := nil;
    if ARoutine[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      Occurrences(ARoutine[mIndex], AName, mFound);
    end;
    if mFound <> nil then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Variablen eines var-Abschnitts der Routine prüfen.</summary>
procedure TRawMemoryScan.CheckSection(ARoutine, ASection: TSyntaxNode);
var
  mIndex: Integer;
  mName: string;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind <> TSyntaxKind.VarDecl then
    begin
      Continue;
    end;
    for mName in ASection[mIndex].Name.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        CheckVariable(ARoutine, Trim(mName));
      end;
    end;
  end;
end;

procedure TRawMemoryScan.CheckVariable(ARoutine: TSyntaxNode; const AName: string);
var
  First, Statement: TSyntaxNode;
  Allocator, Release: string;
  Edit: TTextEdit;
  Fixes: TArray<TRuleFix>;
begin
  // Lokale Routinen sehen die Variable ebenfalls: dort könnte sie freigegeben werden.
  if not KeptAllocation(ARoutine, AName, First) or MentionedInLocalRoutine(ARoutine, AName) then
  begin
    Exit;
  end;
  Allocator := AllocatorOf(First);
  Release := TRawMemoryLeakRule.ReleaseFor(Allocator);
  Statement := StatementOf(First);
  Fixes := nil;
  if (Release <> '') and (Statement <> nil) and TTryFinallyWrap.Create(FLines, FLineBreak,
    FContext.Formatting).Wrap(Statement, '', Release + '(' + AName + ');', Edit) then
  begin
    Fixes := [TRuleFix.Create(cTexts[TOwnershipRawMemoryText.InsertTryFinally].Fmt([Release, AName]), [Edit])];
  end;
  FReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
    cTexts[TOwnershipRawMemoryText.NeverReleased].Fmt([AName, Allocator]), TRuleConfidence.Medium,
    Fixes);
end;

procedure TRawMemoryScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mIndex: Integer;
begin
  if HasAsm(ARoutine) then
  begin
    Exit;
  end;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      CheckSection(ARoutine, ARoutine[mIndex]);
    end;
  end;
end;

procedure TRawMemoryScan.Visit(ANode: TSyntaxNode);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        CheckRoutine(Node);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TRawMemoryScan.Run;
var
  Word: string;
  Any: Boolean;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Any := False;
  for Word in RawAllocCalls do
  begin
    Any := Any or ContainsText(FContext.Text, Word);
  end;
  for Word in RawAllocFunctions do
  begin
    Any := Any or ContainsText(FContext.Text, Word);
  end;
  if not Any then
  begin
    Exit;
  end;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  Visit(FContext.Tree.Root);
end;

{ TRawMemoryLeakRule }

procedure TRawMemoryLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mWorker: TRawMemoryScan;
begin
  mWorker := TRawMemoryScan.Create(AContext, AReport);
  try
    mWorker.Run;
  finally
    mWorker.Free;
  end;
end;

procedure RegisterOwnershipRawMemoryRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TRawMemoryLeakRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Ownership.RawMemory', cTexts);

end.
