unit Atlas.Common.Rules.Builtin.SharedState;

// Ungeschützte Schreibzugriffe auf gemeinsame Variablen aus mehreren Threads (Runde 67):
//   parallel-for-shared-write  Der Rumpf von TParallel.For bzw. ein TTask, der in einer Schleife entsteht, schreibt
//                              eine Variable von außerhalb (Summe := Summe + …, Inc/Dec) oder verändert eine
//                              Sammlung von außerhalb (Liste.Add, Delete, Clear …) ohne Sperre (#1058). Typen aus
//                              "threadSafeTypes" (Vorgabe TThreadList, TThreadedQueue) gelten als threadsicher.
//   thread-unsafe-increment    Inc, Dec, X := X + 1 bzw. X := X - 1 auf einer globalen Variablen in TThread.Execute,
//                              auf einem Feld oder einer globalen Variablen im Rumpf von TTask.Run/Create/Future
//                              außerhalb von Schleifen und von TThread.CreateAnonymousThread (#1059).
//
// Von außerhalb heißt: kein Parameter, keine lokale Variable und keine Inline-Variable der anonymen Methode
// selbst. Gemeldet wird nur, wenn der Name sicher aufgelöst ist (Variable oder Parameter der umgebenden Routine,
// Feld ihrer Klasse, globale Variable der Unit). Still bleiben Rümpfe mit Sperren (TMonitor, Enter, Acquire,
// Lock, LockList, BeginWrite, TInterlocked), Zugriffe über Index (Werte[I] := …) und verschachtelte anonyme
// Methoden (Synchronize, Queue).
// Korrekturen: TInterlocked.Add/Increment/Decrement für Variablen vom Typ Integer, Int64 bzw. Cardinal (mit
// System.SyncObjs in den uses), System.TMonitor.Enter/Exit in try … finally um den Sammlungsaufruf.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TParallelForSharedWriteRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option threadSafeTypes.</summary>
    class function DefaultThreadSafeTypes: TArray<string>; static;
  end;

  TThreadUnsafeIncrementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterSharedStateRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Builtin.Concurrency,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TSharedStateText = (ParallelTitle, ParallelCollection, ParallelAdd, ParallelWrite, CounterTitle, IncNotAtomic,
    DecNotAtomic, LockFix, NotAtomic, CounterUp, CounterDown, UseCall);

const
  cTexts: array[TSharedStateText] of TAtlasText = (
    (De: 'Gemeinsame Variable in TParallel.For geschrieben'; En: 'Shared variable written in TParallel.For'),
    (De: '%s wird parallel ohne Sperre verändert (%s); die Sammlung kann beschädigt werden.';
     En: '%s is modified in parallel without a lock (%s); the collection can be damaged.'),
    (De: '%s wird parallel ohne Sperre geschrieben; Additionen gehen verloren.';
     En: '%s is written in parallel without a lock; additions get lost.'),
    (De: '%s wird parallel ohne Sperre geschrieben; Änderungen gehen verloren.';
     En: '%s is written in parallel without a lock; changes get lost.'),
    (De: 'Zähler im Thread ohne TInterlocked'; En: 'Counter in a thread without TInterlocked'),
    (De: 'Inc ist nicht atomar'; En: 'Inc is not atomic'),
    (De: 'Dec ist nicht atomar'; En: 'Dec is not atomic'),
    (De: 'Sperre mit TMonitor um %s.%s legen'; En: 'Put a TMonitor lock around %s.%s'),
    (De: '%s ist nicht atomar'; En: '%s is not atomic'),
    (De: '%s wird aus mehreren Threads ohne Sperre erhöht; %s.';
     En: '%s is incremented from several threads without a lock; %s.'),
    (De: '%s wird aus mehreren Threads ohne Sperre verringert; %s.';
     En: '%s is decremented from several threads without a lock; %s.'),
    (De: '%s verwenden'; En: 'Use %s'));

{$SCOPEDENUMS OFF}

type
{$SCOPEDENUMS ON}
  TWriteKind = (Assign, Increment, Collection);
  /// <summary>Herkunft eines Namens: unbekannt, Variable oder Parameter der umgebenden Routine, Feld der Klasse
  /// der Methode, globale Variable der Unit.</summary>
  TNameScope = (Unknown, Local, Field, Global);
{$SCOPEDENUMS OFF}
  TNameScopes = set of TNameScope;

  /// <summary>Ein ungeschützter Schreibzugriff auf AName.</summary>
  TSharedWrite = record
    Kind: TWriteKind;
    Statement: TSyntaxNode;
    Name: string;
    /// <summary>Inc, Dec, + oder -; bei Sammlungen der Methodenname.</summary>
    Operation: string;
    /// <summary>Betrag als Quelltext ('' bei Inc/Dec ohne zweites Argument).</summary>
    Amount: string;
  end;

  /// <summary>Gemeinsame Suche beider Regeln.</summary>
  TSharedState = class
  private
    FContext: TRuleContext;
    FLocalIndex: TUnitIndex;
    FHasIndex: Boolean;
    function SourceText(ANode: TSyntaxNode): string;
    procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
    function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
    function HasLock(ANode: TSyntaxNode): Boolean;
    function DeclaresName(ADecl: TSyntaxNode; const AName: string; var ATypeName: string): Boolean;
    function FindLocalDecl(ARoutine: TSyntaxNode; const AName: string; var ATypeName: string): Boolean;
    function SymbolScope(const ASymbol: TIndexSymbol; const AOwner: string): TNameScope;
  public
    constructor Create(const AContext: TRuleContext);
    /// <summary>Namen, die AMethod (RoutineDecl oder AnonymousMethod) selbst deklariert.</summary>
    function OwnNames(AMethod: TSyntaxNode): TArray<string>;
    /// <summary>Ungeschützte Schreibzugriffe im Rumpf von AMethod auf Namen außerhalb; leer, wenn der Rumpf
    /// sperrt. ACollections: auch Sammlungsaufrufe.</summary>
    function Writes(AMethod: TSyntaxNode; ACollections: Boolean): TArray<TSharedWrite>;
    /// <summary>Herkunft und Typ von AName aus der umgebenden Routine ARoutine, der Klasse der Methode oder der
    /// Unit; ATypeName '' wenn unbekannt.</summary>
    function Resolve(ARoutine: TSyntaxNode; const AName: string; out ATypeName: string): TNameScope;
    /// <summary>Korrektur mit TInterlocked für AWrite, wenn der Typ passt; sonst leer.</summary>
    function InterlockedFix(const AWrite: TSharedWrite; const ATypeName: string): TArray<TRuleFix>;
    /// <summary>Korrektur: System.TMonitor um den Sammlungsaufruf, wenn er allein in seiner Zeile steht; als
    /// Zweig einer Anweisung in begin … end.</summary>
    function LockFix(const AWrite: TSharedWrite): TArray<TRuleFix>;
    property Context: TRuleContext read FContext;
  end;

const
  MutatingMethods: array[0..12] of string = ('Add', 'AddObject', 'AddPair', 'AddOrSetValue', 'AddRange', 'Append',
    'Insert', 'Delete', 'Remove', 'Clear', 'Push', 'Enqueue', 'Exchange');
  LockNames: array[0..6] of string = ('TMonitor', 'Enter', 'Acquire', 'Lock', 'LockList', 'BeginWrite',
    'TInterlocked');

function ShortName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ TSharedState }

constructor TSharedState.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
end;

function TSharedState.SourceText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

procedure TSharedState.CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Index: Integer;
  Name: string;
  Child: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    for Index := ANode.ChildCount - 1 downto 0 do
    begin
      Pending.Push(ANode[Index]);
    end;
    while Pending.Count > 0 do
    begin
      Child := Pending.Pop;
      case Child.Kind of
        TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl,
        TSyntaxKind.InlineConst:
          for Name in SplitString(Child.Name, ',') do
          begin
            ANames := ANames + [Trim(Name)];
          end;
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
          // for var I := …
          if ContainsText(Copy(SourceText(Child), 1, 8), ' var ') then
          begin
            ANames := ANames + [Child.Name];
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      if not (Child.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]) then
      begin
        for Index := Child.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Child[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TSharedState.OwnNames(AMethod: TSyntaxNode): TArray<string>;
begin
  Result := ['Result'];
  CollectNames(AMethod, Result);
end;

function TSharedState.Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) then
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

function TSharedState.HasLock(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(Node.Name, LockNames) then
      begin
        Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        if Node[Index].Kind <> TSyntaxKind.AnonymousMethod then
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TSharedState.Writes(AMethod: TSyntaxNode; ACollections: Boolean): TArray<TSharedWrite>;
var
  Own: TArray<string>;
  Writes_: TArray<TSharedWrite>;

  function Outside(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Identifier) and (Pos('.', ANode.Name) = 0) and
      not MatchText(ANode.Name, Own);
  end;

  procedure Add(AKind: TWriteKind; AStatement: TSyntaxNode; const AName, AOperation, AAmount: string);
  var
    Write: TSharedWrite;
  begin
    Write.Kind := AKind;
    Write.Statement := AStatement;
    Write.Name := AName;
    Write.Operation := AOperation;
    Write.Amount := AAmount;
    Writes_ := Writes_ + [Write];
  end;

  /// <summary>AValue ist X op E mit X = AName an Stelle ASelf und E ohne AName.</summary>
  function IsSelfOperation(AValue: TSyntaxNode; const AName: string; ASelf: Integer): Boolean;
  begin
    Result := (AValue.Kind = TSyntaxKind.BinaryExpr) and (AValue.ChildCount = 2);
    if Result then
    begin
      Result := (AValue[ASelf].Kind = TSyntaxKind.Identifier) and SameText(AValue[ASelf].Name, AName) and
        not Mentions(AValue[1 - ASelf], AName);
    end;
  end;

  procedure VisitAssign(ANode: TSyntaxNode);
  var
    mTarget, mValue: TSyntaxNode;
  begin
    mTarget := ANode[0];
    mValue := ANode[ANode.ChildCount - 1];
    // X := X + E, X := E + X, X := X - E
    if (ANode.ChildCount <> 2) or not Outside(mTarget) or not Mentions(mValue, mTarget.Name) then
    begin
      Exit;
    end;
    if IsSelfOperation(mValue, mTarget.Name, 0) and MatchStr(mValue.Name, ['+', '-']) then
    begin
      Add(TWriteKind.Assign, ANode, mTarget.Name, mValue.Name, SourceText(mValue[1]));
    end
    else if IsSelfOperation(mValue, mTarget.Name, 1) and (mValue.Name = '+') then
    begin
      Add(TWriteKind.Assign, ANode, mTarget.Name, '+', SourceText(mValue[0]));
    end
    else
    begin
      Add(TWriteKind.Assign, ANode, mTarget.Name, '', '');
    end;
  end;

  function IsIncrement(ACall: TSyntaxNode): Boolean;
  begin
    Result := (ACall[0].Kind = TSyntaxKind.Identifier) and MatchText(ACall[0].Name, ['Inc', 'Dec']) and
      (ACall.ChildCount in [2, 3]);
    Result := Result and Outside(ACall[1]);
  end;

  function IsCollectionCall(ACall: TSyntaxNode): Boolean;
  begin
    Result := ACollections and (ACall[0].Kind = TSyntaxKind.MemberAccess) and (ACall[0].ChildCount = 1);
    Result := Result and MatchText(ACall[0].Name, MutatingMethods) and Outside(ACall[0][0]);
  end;

  procedure VisitCall(ANode: TSyntaxNode);
  var
    mCall: TSyntaxNode;
    mAmount: string;
  begin
    mCall := ANode[0];
    // Inc(X), Inc(X, N), Dec(…)
    if IsIncrement(mCall) then
    begin
      mAmount := '';
      if mCall.ChildCount = 3 then
      begin
        mAmount := SourceText(mCall[2]);
      end;
      Add(TWriteKind.Increment, ANode, mCall[1].Name, mCall[0].Name, mAmount);
    end
    // Liste.Add(…)
    else if IsCollectionCall(mCall) then
    begin
      Add(TWriteKind.Collection, ANode, mCall[0][0].Name, mCall[0].Name, '');
    end;
  end;

  procedure VisitNode(ANode: TSyntaxNode);
  begin
    if ANode.Kind = TSyntaxKind.AssignStatement then
    begin
      VisitAssign(ANode);
    end
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 0) then
    begin
      VisitCall(ANode);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        VisitNode(Node);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          // Verschachtelte anonyme Methoden (Synchronize, Queue) laufen woanders.
          if Node[Index].Kind <> TSyntaxKind.AnonymousMethod then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Body: TSyntaxNode;
begin
  Result := nil;
  Body := AMethod.FindChild(TSyntaxKind.Block);
  if (Body = nil) or HasLock(Body) then
  begin
    Exit;
  end;
  Own := OwnNames(AMethod);
  Writes_ := nil;
  Visit(Body);
  Result := Writes_;
end;

function TSharedState.DeclaresName(ADecl: TSyntaxNode; const AName: string; var ATypeName: string): Boolean;
var
  mName: string;
  mTypeRef: TSyntaxNode;
begin
  Result := False;
  for mName in SplitString(ADecl.Name, ',') do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Result := True;
      mTypeRef := ADecl.FindChild(TSyntaxKind.TypeReference);
      if mTypeRef <> nil then
      begin
        ATypeName := mTypeRef.Name;
      end;
      Break;
    end;
  end;
end;

function TSharedState.FindLocalDecl(ARoutine: TSyntaxNode; const AName: string; var ATypeName: string): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  Result := False;
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ARoutine.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ARoutine[mIndex]);
    end;
    while (mPending.Count > 0) and not Result do
    begin
      mChild := mPending.Pop;
      if mChild.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter] then
      begin
        Result := DeclaresName(mChild, AName, ATypeName);
      end;
      // Verschachtelte Routinen und anonyme Methoden deklarieren eigene Namen.
      if not (mChild.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]) then
      begin
        for mIndex := mChild.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mChild[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TSharedState.SymbolScope(const ASymbol: TIndexSymbol; const AOwner: string): TNameScope;
begin
  Result := TNameScope.Unknown;
  if (ASymbol.Kind = TIndexSymbolKind.Field) and (AOwner <> '') and SameText(ASymbol.Container, AOwner) then
  begin
    Result := TNameScope.Field;
  end
  else if (ASymbol.Kind = TIndexSymbolKind.Variable) and (ASymbol.Container = '') then
  begin
    Result := TNameScope.Global;
  end;
end;

function TSharedState.Resolve(ARoutine: TSyntaxNode; const AName: string; out ATypeName: string): TNameScope;
var
  mOwner: string;
  mSymbol: TIndexSymbol;
begin
  Result := TNameScope.Unknown;
  ATypeName := '';
  if (ARoutine <> nil) and FindLocalDecl(ARoutine, AName, ATypeName) then
  begin
    Exit(TNameScope.Local);
  end;
  if not FHasIndex then
  begin
    FLocalIndex := TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext);
    FHasIndex := True;
  end;
  mOwner := '';
  if (ARoutine <> nil) and (LastDelimiter('.', ARoutine.Name) > 0) then
  begin
    mOwner := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
  end;
  for mSymbol in FLocalIndex.Symbols do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      Result := SymbolScope(mSymbol, mOwner);
      if Result <> TNameScope.Unknown then
      begin
        ATypeName := mSymbol.TypeName;
        Break;
      end;
    end;
  end;
end;

function InterlockedStep(const AWrite: TSharedWrite; AUp: Boolean): string;
begin
  if AUp then
  begin
    Result := 'TInterlocked.Increment(' + AWrite.Name + ')';
  end
  else
  begin
    Result := 'TInterlocked.Decrement(' + AWrite.Name + ')';
  end;
end;

/// <summary>Aufruf von TInterlocked für AWrite; '' wenn AWrite keine Addition ist.</summary>
function InterlockedCall(const AWrite: TSharedWrite): string;
var
  mDown: Boolean;
begin
  Result := '';
  mDown := SameText(AWrite.Operation, 'Dec') or (AWrite.Operation = '-');
  if (AWrite.Kind = TWriteKind.Increment) and (AWrite.Amount = '') then
  begin
    Result := InterlockedStep(AWrite, not mDown);
  end
  // X := X + 1 bzw. X - 1 wie Inc/Dec.
  else if (AWrite.Kind = TWriteKind.Assign) and (AWrite.Operation <> '') and (Trim(AWrite.Amount) = '1') then
  begin
    Result := InterlockedStep(AWrite, AWrite.Operation = '+');
  end
  else if (AWrite.Kind = TWriteKind.Increment) or ((AWrite.Kind = TWriteKind.Assign) and (AWrite.Operation <> '')) then
  begin
    if mDown then
    begin
      Result := 'TInterlocked.Add(' + AWrite.Name + ', -(' + AWrite.Amount + '))';
    end
    else
    begin
      Result := 'TInterlocked.Add(' + AWrite.Name + ', ' + AWrite.Amount + ')';
    end;
  end;
end;

function TSharedState.InterlockedFix(const AWrite: TSharedWrite; const ATypeName: string): TArray<TRuleFix>;
var
  Call, LineBreak: string;
  Edits: TArray<TRuleEdit>;
  UsesEdit: TRuleEdit;
begin
  Result := nil;
  if not MatchText(ShortName(ATypeName), ['Integer', 'Int64', 'Cardinal', 'LongInt', 'UInt64']) then
  begin
    Exit;
  end;
  Call := InterlockedCall(AWrite);
  if Call = '' then
  begin
    Exit;
  end;
  Edits := [TRuleEdit.Create(TTextRange.Create(AWrite.Statement.StartPos, AWrite.Statement.EndPos), Call)];
  LineBreak := TTextLines.LineBreakOf(FContext.Text);
  if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(FContext.Tree.Tokens), 'System.SyncObjs', FContext.Namespaces) and
    TUsesClauses.AddUnit(FContext.Tree.Tokens, AWrite.Statement.StartOffset, 'System.SyncObjs', LineBreak, UsesEdit) then
  begin
    Edits := [UsesEdit] + Edits;
  end;
  Result := [TRuleFix.Create(cTexts[TSharedStateText.UseCall].Fmt([Call]), Edits)];
end;

function TSharedState.LockFix(const AWrite: TSharedWrite): TArray<TRuleFix>;
var
  Lines: TArray<string>;
  LineBreak, Line, Indent, Inner, Text: string;
  Statement: TSyntaxNode;
begin
  Result := nil;
  Statement := AWrite.Statement;
  Lines := TTextLines.SplitLines(FContext.Text, LineBreak);
  if (Statement.StartPos.Line <> Statement.EndPos.Line) or (Statement.StartPos.Line > High(Lines)) then
  begin
    Exit;
  end;
  Line := Lines[Statement.StartPos.Line];
  if (Trim(Copy(Line, 1, Statement.StartPos.Character)) <> '') or
    not MatchStr(Trim(Copy(Line, Statement.EndPos.Character + 1, MaxInt)), ['', ';']) then
  begin
    Exit;
  end;
  Indent := TTextLines.IndentOf(Line);
  // Als Zweig von if, while, for, with oder case braucht die Folge ein begin … end.
  Inner := Indent;
  if (Statement.Parent <> nil) and not (Statement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
    TSyntaxKind.FinallyBlock, TSyntaxKind.RepeatStatement]) then
  begin
    Inner := Indent + '  ';
  end;
  Text := 'System.TMonitor.Enter(' + AWrite.Name + ');' + LineBreak +
    Inner + 'try' + LineBreak +
    Inner + '  ' + SourceText(Statement) + ';' + LineBreak +
    Inner + 'finally' + LineBreak +
    Inner + '  System.TMonitor.Exit(' + AWrite.Name + ');' + LineBreak +
    Inner + 'end';
  if Inner <> Indent then
  begin
    Text := 'begin' + LineBreak + Inner + Text + ';' + LineBreak + Indent + 'end';
  end;
  Result := [TRuleFix.Create(cTexts[TSharedStateText.LockFix].Fmt([AWrite.Name, AWrite.Operation]),
    [TRuleEdit.Create(TTextRange.Create(Statement.StartPos, Statement.EndPos), Text)])];
end;

/// <summary>Ist ANode ein Aufruf AType.AMethod(…) (auch AType.&amp;AMethod und AType.AMethod&lt;T&gt;)?</summary>
function IsCallOf(ANode: TSyntaxNode; const AType: string; const AMethods: array of string): Boolean;
var
  Method: string;
  Access: TSyntaxNode;
begin
  Result := False;
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount < 2) then
  begin
    Exit;
  end;
  Access := ANode[0];
  // TTask.Future<Integer>: MemberAccess mit GenericArgs um den eigentlichen Zugriff.
  if (Access.Kind = TSyntaxKind.MemberAccess) and (Access.ChildCount = 2) and
    (Access[1].Kind = TSyntaxKind.GenericArgs) then
  begin
    Access := Access[0];
  end;
  if (Access.Kind <> TSyntaxKind.MemberAccess) or (Access.ChildCount = 0) or
    (Access[0].Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  Method := Access.Name;
  if StartsStr('&', Method) then
  begin
    Method := Copy(Method, 2, MaxInt);
  end;
  Result := SameText(ShortName(Access[0].Name), AType) and MatchText(Method, AMethods);
end;

/// <summary>Letztes Argument als anonyme Methode, sonst nil.</summary>
function AnonymousArgument(ACall: TSyntaxNode): TSyntaxNode;
begin
  Result := ACall[ACall.ChildCount - 1];
  if Result.Kind <> TSyntaxKind.AnonymousMethod then
  begin
    Result := nil;
  end;
end;

{ TParallelForSharedWriteRule }

function TParallelForSharedWriteRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('parallel-for-shared-write', TRuleSeverity.Warning,
    cTexts[TSharedStateText.ParallelTitle].Text);
end;

class function TParallelForSharedWriteRule.DefaultThreadSafeTypes: TArray<string>;
begin
  Result := ['TThreadList', 'TThreadedQueue'];
end;

procedure TParallelForSharedWriteRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  State: TSharedState;
  SafeTypes: TArray<string>;

  procedure Report(AMethod, ARoutine: TSyntaxNode);
  var
    Write: TSharedWrite;
    TypeName, Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    for Write in State.Writes(AMethod, True) do
    begin
      // Nur Namen, deren Herkunft sicher ist: Variable der umgebenden Routine, Feld oder globale Variable.
      if State.Resolve(ARoutine, Write.Name, TypeName) = TNameScope.Unknown then
      begin
        Continue;
      end;
      if Write.Kind = TWriteKind.Collection then
      begin
        if (TypeName <> '') and MatchText(ShortName(TypeName), SafeTypes) then
        begin
          Continue;
        end;
        Message := cTexts[TSharedStateText.ParallelCollection].Fmt([Write.Name, Write.Operation]);
        Fixes := State.LockFix(Write);
      end
      else
      begin
        if MatchStr(Write.Operation, ['+', 'Inc']) then
        begin
          Message := cTexts[TSharedStateText.ParallelAdd].Fmt([Write.Name]);
        end
        else
        begin
          Message := cTexts[TSharedStateText.ParallelWrite].Fmt([Write.Name]);
        end;
        Fixes := State.InterlockedFix(Write, TypeName);
      end;
      AReport.Add(TTextRange.Create(Write.Statement.StartPos, Write.Statement.EndPos), Message,
        TRuleConfidence.Medium, Fixes);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Routine, Method: TSyntaxNode;
    InLoop: Boolean;
    Pending, Routines: TStack<TSyntaxNode>;
    InLoops: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel die umgebende Routine und ob er in einer Schleife liegt.
    Pending := TStack<TSyntaxNode>.Create;
    Routines := TStack<TSyntaxNode>.Create;
    InLoops := TStack<Boolean>.Create;
    try
      Pending.Push(ARoot);
      Routines.Push(nil);
      InLoops.Push(False);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := Routines.Pop;
        InLoop := InLoops.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routine := Node;
          InLoop := False;
        end
        else if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
          TSyntaxKind.RepeatStatement] then
        begin
          InLoop := True;
        end
        else if Node.Kind = TSyntaxKind.Call then
        begin
          Method := AnonymousArgument(Node);
          if (Method <> nil) and (IsCallOf(Node, 'TParallel', ['For']) or
            (InLoop and IsCallOf(Node, 'TTask', ['Run', 'Create', 'Future']))) then
          begin
            Report(Method, Routine);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          Routines.Push(Routine);
          InLoops.Push(InLoop and (Node.Kind <> TSyntaxKind.AnonymousMethod));
        end;
      end;
    finally
      InLoops.Free;
      Routines.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'TParallel') or ContainsText(AContext.Text, 'TTask')) then
  begin
    Exit;
  end;
  SafeTypes := TRuleOptions.Strings(AContext.Options, 'threadSafeTypes', DefaultThreadSafeTypes);
  State := TSharedState.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    State.Free;
  end;
end;

{ TThreadUnsafeIncrementRule }

function TThreadUnsafeIncrementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-unsafe-increment', TRuleSeverity.Warning,
    cTexts[TSharedStateText.CounterTitle].Text);
end;

/// <summary>Kann AText einen Zähler enthalten (Inc, Dec, + 1, - 1)? Schneller Vorfilter.</summary>
function MayCount(const AText: string): Boolean;
begin
  Result := ContainsText(AText, 'Inc') or ContainsText(AText, 'Dec');
  Result := Result or ContainsText(AText, '+ 1') or ContainsText(AText, '- 1');
end;

procedure TThreadUnsafeIncrementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  State: TSharedState;
  Ancestry: TAncestry;
  Classes: TArray<string>;

  /// <summary>Erbt AOwner von TThread (über Klassen der Unit oder über den Index)?</summary>
  function IsThreadClass(const AOwner: string): Boolean;
  begin
    Result := MatchText(AOwner, Classes);
    if not Result and (AContext.Index <> nil) then
    begin
      if Ancestry = nil then
      begin
        Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
      end;
      Result := Ancestry.DescendsFrom(AOwner, 'TThread');
    end;
  end;

  procedure Report(AMethod, ARoutine: TSyntaxNode; AScopes: TNameScopes);
  var
    Write: TSharedWrite;
    What, TypeName: string;
    Verb: TSharedStateText;
  begin
    for Write in State.Writes(AMethod, False) do
    begin
      if not (State.Resolve(ARoutine, Write.Name, TypeName) in AScopes) then
      begin
        Continue;
      end;
      // Nur Zähler: Inc/Dec und X := X ± 1.
      if (Write.Kind = TWriteKind.Assign) and not ((Write.Operation <> '') and (Trim(Write.Amount) = '1')) then
      begin
        Continue;
      end;
      Verb := TSharedStateText.CounterUp;
      if MatchText(Write.Operation, ['Dec', '-']) then
      begin
        Verb := TSharedStateText.CounterDown;
      end;
      What := cTexts[TSharedStateText.IncNotAtomic].Text;
      if SameText(Write.Operation, 'Dec') then
      begin
        What := cTexts[TSharedStateText.DecNotAtomic].Text;
      end
      else if Write.Kind = TWriteKind.Assign then
      begin
        What := cTexts[TSharedStateText.NotAtomic].Fmt([Write.Name + ' := ' + Write.Name + ' ' + Write.Operation +
          ' 1']);
      end;
      AReport.Add(TTextRange.Create(Write.Statement.StartPos, Write.Statement.EndPos),
        cTexts[Verb].Fmt([Write.Name, What]), TRuleConfidence.Medium,
        State.InterlockedFix(Write, TypeName));
    end;
  end;

  procedure VisitRoutine(ANode: TSyntaxNode);
  var
    mDot: Integer;
  begin
    // TArbeiter.Execute einer Thread-Klasse.
    mDot := LastDelimiter('.', ANode.Name);
    if (mDot > 0) and SameText(Copy(ANode.Name, mDot + 1, MaxInt), 'Execute') and
      IsThreadClass(Copy(ANode.Name, 1, mDot - 1)) then
    begin
      // Eigene Felder schreibt nur der Thread selbst; geteilt sind globale Variablen.
      Report(ANode, ANode, [TNameScope.Global]);
    end;
  end;

  procedure VisitCall(ANode, ARoutine: TSyntaxNode; AInLoop: Boolean);
  var
    mMethod: TSyntaxNode;
  begin
    mMethod := AnonymousArgument(ANode);
    if mMethod = nil then
    begin
      Exit;
    end;
    // TTask in Schleifen und TParallel.For meldet parallel-for-shared-write.
    if (not AInLoop and IsCallOf(ANode, 'TTask', ['Run', 'Create', 'Future'])) or
      IsCallOf(ANode, 'TThread', ['CreateAnonymousThread']) then
    begin
      // Eingefangene lokale Variablen schreibt nur dieser eine Thread neben dem Aufrufer; Felder und globale
      // Variablen teilen sich alle Aufrufe.
      Report(mMethod, ARoutine, [TNameScope.Field, TNameScope.Global]);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Routine: TSyntaxNode;
    InLoop: Boolean;
    Pending, Routines: TStack<TSyntaxNode>;
    InLoops: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel die umgebende Routine und ob er in einer Schleife liegt.
    Pending := TStack<TSyntaxNode>.Create;
    Routines := TStack<TSyntaxNode>.Create;
    InLoops := TStack<Boolean>.Create;
    try
      Pending.Push(ARoot);
      Routines.Push(nil);
      InLoops.Push(False);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := Routines.Pop;
        InLoop := InLoops.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routine := Node;
          InLoop := False;
          VisitRoutine(Node);
        end
        else if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
          TSyntaxKind.RepeatStatement] then
        begin
          InLoop := True;
        end
        else if Node.Kind = TSyntaxKind.Call then
        begin
          VisitCall(Node, Routine, InLoop);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          Routines.Push(Routine);
          InLoops.Push(InLoop and (Node.Kind <> TSyntaxKind.AnonymousMethod));
        end;
      end;
    finally
      InLoops.Free;
      Routines.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not MayCount(AContext.Text) then
  begin
    Exit;
  end;
  Classes := ThreadClasses(AContext.Tree.Root);
  Ancestry := nil;
  State := TSharedState.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    State.Free;
    Ancestry.Free;
  end;
end;

procedure RegisterSharedStateRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TParallelForSharedWriteRule.Create);
  ARegistry.Register(TThreadUnsafeIncrementRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.SharedState', cTexts);

end.
