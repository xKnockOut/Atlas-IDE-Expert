unit Atlas.Common.Rules.Builtin.SharedState;

// Ungeschützte Schreibzugriffe auf gemeinsame Variablen aus mehreren Threads (Runde 67):
//   parallel-for-shared-write  Der Rumpf von TParallel.For bzw. ein TTask, der in einer Schleife entsteht, schreibt
//                              eine Variable von außerhalb (Summe := Summe + …, Inc/Dec) oder verändert eine
//                              Sammlung von außerhalb (Liste.Add, Delete, Clear …) ohne Sperre (#1058). Typen aus
//                              "threadSafeTypes" (Vorgabe TThreadList, TThreadedQueue) gelten als threadsicher.
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

procedure RegisterSharedStateRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines;

type
{$SCOPEDENUMS ON}
  TWriteKind = (Assign, Increment, Collection);
  /// <summary>Herkunft eines Namens: unbekannt, Variable oder Parameter der umgebenden Routine, Feld der Klasse
  /// der Methode, globale Variable der Unit.</summary>
  TNameScope = (Unknown, Local, Field, Global);
{$SCOPEDENUMS OFF}

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
    Result := Copy(Result, 1, Pos('<', Result) - 1);
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
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    case ANode[Index].Kind of
      TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl,
      TSyntaxKind.InlineConst:
        for Name in SplitString(ANode[Index].Name, ',') do
          ANames := ANames + [Trim(Name)];
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
        // for var I := …
        if ContainsText(Copy(SourceText(ANode[Index]), 1, 8), ' var ') then
          ANames := ANames + [ANode[Index].Name];
    end;
    if not (ANode[Index].Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]) then
      CollectNames(ANode[Index], ANames);
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
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if Mentions(ANode[Index], AName) then
      Exit(True);
  Result := False;
end;

function TSharedState.HasLock(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(ANode.Name, LockNames) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].Kind <> TSyntaxKind.AnonymousMethod) and HasLock(ANode[Index]) then
      Exit(True);
  Result := False;
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

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Target, Value, Call: TSyntaxNode;
    Amount: string;
  begin
    if ANode.Kind = TSyntaxKind.AssignStatement then
    begin
      Target := ANode[0];
      Value := ANode[ANode.ChildCount - 1];
      // X := X + E, X := E + X, X := X - E
      if (ANode.ChildCount = 2) and Outside(Target) and Mentions(Value, Target.Name) then
      begin
        if (Value.Kind = TSyntaxKind.BinaryExpr) and (Value.ChildCount = 2) and MatchStr(Value.Name, ['+', '-']) and
          (Value[0].Kind = TSyntaxKind.Identifier) and SameText(Value[0].Name, Target.Name) and
          not Mentions(Value[1], Target.Name) then
          Add(TWriteKind.Assign, ANode, Target.Name, Value.Name, SourceText(Value[1]))
        else if (Value.Kind = TSyntaxKind.BinaryExpr) and (Value.ChildCount = 2) and (Value.Name = '+') and
          (Value[1].Kind = TSyntaxKind.Identifier) and SameText(Value[1].Name, Target.Name) and
          not Mentions(Value[0], Target.Name) then
          Add(TWriteKind.Assign, ANode, Target.Name, '+', SourceText(Value[0]))
        else
          Add(TWriteKind.Assign, ANode, Target.Name, '', '');
      end;
    end
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 0) then
    begin
      Call := ANode[0];
      // Inc(X), Inc(X, N), Dec(…)
      if (Call[0].Kind = TSyntaxKind.Identifier) and MatchText(Call[0].Name, ['Inc', 'Dec']) and
        (Call.ChildCount in [2, 3]) and Outside(Call[1]) then
      begin
        Amount := '';
        if Call.ChildCount = 3 then
          Amount := SourceText(Call[2]);
        Add(TWriteKind.Increment, ANode, Call[1].Name, Call[0].Name, Amount);
      end
      // Liste.Add(…)
      else if ACollections and (Call[0].Kind = TSyntaxKind.MemberAccess) and (Call[0].ChildCount = 1) and
        MatchText(Call[0].Name, MutatingMethods) and Outside(Call[0][0]) then
        Add(TWriteKind.Collection, ANode, Call[0][0].Name, Call[0].Name, '');
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      // Verschachtelte anonyme Methoden (Synchronize, Queue) laufen woanders.
      if ANode[Index].Kind <> TSyntaxKind.AnonymousMethod then
        Visit(ANode[Index]);
  end;

var
  Body: TSyntaxNode;
begin
  Result := nil;
  Body := AMethod.FindChild(TSyntaxKind.Block);
  if (Body = nil) or HasLock(Body) then
    Exit;
  Own := OwnNames(AMethod);
  Writes_ := nil;
  Visit(Body);
  Result := Writes_;
end;

function TSharedState.Resolve(ARoutine: TSyntaxNode; const AName: string; out ATypeName: string): TNameScope;
var
  Found: Boolean;
  Owner: string;
  Symbol: TIndexSymbol;

  procedure FindDecl(ANode: TSyntaxNode);
  var
    Index: Integer;
    Child, TypeRef: TSyntaxNode;
    Name: string;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if Found then
        Exit;
      Child := ANode[Index];
      if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter] then
        for Name in SplitString(Child.Name, ',') do
          if SameText(Trim(Name), AName) then
          begin
            Found := True;
            TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
            if TypeRef <> nil then
              ATypeName := TypeRef.Name;
            Exit;
          end;
      // Verschachtelte Routinen und anonyme Methoden deklarieren eigene Namen.
      if not (Child.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]) then
        FindDecl(Child);
    end;
  end;

begin
  Result := TNameScope.Unknown;
  ATypeName := '';
  Found := False;
  if ARoutine <> nil then
  begin
    FindDecl(ARoutine);
    if Found then
      Exit(TNameScope.Local);
  end;
  if not FHasIndex then
  begin
    FLocalIndex := TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext);
    FHasIndex := True;
  end;
  Owner := '';
  if (ARoutine <> nil) and (LastDelimiter('.', ARoutine.Name) > 0) then
    Owner := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
  for Symbol in FLocalIndex.Symbols do
    if SameText(Symbol.Name, AName) then
    begin
      if (Symbol.Kind = TIndexSymbolKind.Field) and (Owner <> '') and SameText(Symbol.Container, Owner) then
        Result := TNameScope.Field
      else if (Symbol.Kind = TIndexSymbolKind.Variable) and (Symbol.Container = '') then
        Result := TNameScope.Global
      else
        Continue;
      ATypeName := Symbol.TypeName;
      Exit;
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
    Exit;
  if (AWrite.Kind = TWriteKind.Increment) and (AWrite.Amount = '') then
  begin
    if SameText(AWrite.Operation, 'Inc') then
      Call := 'TInterlocked.Increment(' + AWrite.Name + ')'
    else
      Call := 'TInterlocked.Decrement(' + AWrite.Name + ')';
  end
  else if (AWrite.Kind = TWriteKind.Increment) or ((AWrite.Kind = TWriteKind.Assign) and (AWrite.Operation <> '')) then
  begin
    if SameText(AWrite.Operation, 'Dec') or (AWrite.Operation = '-') then
      Call := 'TInterlocked.Add(' + AWrite.Name + ', -(' + AWrite.Amount + '))'
    else
      Call := 'TInterlocked.Add(' + AWrite.Name + ', ' + AWrite.Amount + ')';
    // X := X + 1 bzw. X - 1 wie Inc/Dec.
    if (AWrite.Kind = TWriteKind.Assign) and (Trim(AWrite.Amount) = '1') then
    begin
      if AWrite.Operation = '+' then
        Call := 'TInterlocked.Increment(' + AWrite.Name + ')'
      else
        Call := 'TInterlocked.Decrement(' + AWrite.Name + ')';
    end;
  end
  else
    Exit;
  Edits := [TRuleEdit.Create(TTextRange.Create(AWrite.Statement.StartPos, AWrite.Statement.EndPos), Call)];
  LineBreak := TTextLines.LineBreakOf(FContext.Text);
  if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(FContext.Tree.Tokens), 'System.SyncObjs', FContext.Namespaces) and
    TUsesClauses.AddUnit(FContext.Tree.Tokens, AWrite.Statement.StartOffset, 'System.SyncObjs', LineBreak, UsesEdit) then
    Edits := [UsesEdit] + Edits;
  Result := [TRuleFix.Create(Call + ' verwenden', Edits)];
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
    Exit;
  Line := Lines[Statement.StartPos.Line];
  if (Trim(Copy(Line, 1, Statement.StartPos.Character)) <> '') or
    not MatchStr(Trim(Copy(Line, Statement.EndPos.Character + 1, MaxInt)), ['', ';']) then
    Exit;
  Indent := TTextLines.IndentOf(Line);
  // Als Zweig von if, while, for, with oder case braucht die Folge ein begin … end.
  Inner := Indent;
  if (Statement.Parent <> nil) and not (Statement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
    TSyntaxKind.FinallyBlock, TSyntaxKind.RepeatStatement]) then
    Inner := Indent + '  ';
  Text := 'System.TMonitor.Enter(' + AWrite.Name + ');' + LineBreak +
    Inner + 'try' + LineBreak +
    Inner + '  ' + SourceText(Statement) + ';' + LineBreak +
    Inner + 'finally' + LineBreak +
    Inner + '  System.TMonitor.Exit(' + AWrite.Name + ');' + LineBreak +
    Inner + 'end';
  if Inner <> Indent then
    Text := 'begin' + LineBreak + Inner + Text + ';' + LineBreak + Indent + 'end';
  Result := [TRuleFix.Create('Sperre mit TMonitor um ' + AWrite.Name + '.' + AWrite.Operation + ' legen',
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
    Exit;
  Access := ANode[0];
  // TTask.Future<Integer>: MemberAccess mit GenericArgs um den eigentlichen Zugriff.
  if (Access.Kind = TSyntaxKind.MemberAccess) and (Access.ChildCount = 2) and
    (Access[1].Kind = TSyntaxKind.GenericArgs) then
    Access := Access[0];
  if (Access.Kind <> TSyntaxKind.MemberAccess) or (Access.ChildCount = 0) or
    (Access[0].Kind <> TSyntaxKind.Identifier) then
    Exit;
  Method := Access.Name;
  if StartsStr('&', Method) then
    Method := Copy(Method, 2, MaxInt);
  Result := SameText(ShortName(Access[0].Name), AType) and MatchText(Method, AMethods);
end;

/// <summary>Letztes Argument als anonyme Methode, sonst nil.</summary>
function AnonymousArgument(ACall: TSyntaxNode): TSyntaxNode;
begin
  Result := ACall[ACall.ChildCount - 1];
  if Result.Kind <> TSyntaxKind.AnonymousMethod then
    Result := nil;
end;

{ TParallelForSharedWriteRule }

function TParallelForSharedWriteRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('parallel-for-shared-write', TRuleSeverity.Warning,
    'Gemeinsame Variable in TParallel.For geschrieben');
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
        Continue;
      if Write.Kind = TWriteKind.Collection then
      begin
        if (TypeName <> '') and MatchText(ShortName(TypeName), SafeTypes) then
          Continue;
        Message := Format('%s wird parallel ohne Sperre verändert (%s); die Sammlung kann beschädigt werden.',
          [Write.Name, Write.Operation]);
        Fixes := State.LockFix(Write);
      end
      else
      begin
        if MatchStr(Write.Operation, ['+', 'Inc']) then
          Message := Format('%s wird parallel ohne Sperre geschrieben; Additionen gehen verloren.', [Write.Name])
        else
          Message := Format('%s wird parallel ohne Sperre geschrieben; Änderungen gehen verloren.', [Write.Name]);
        Fixes := State.InterlockedFix(Write, TypeName);
      end;
      AReport.Add(TTextRange.Create(Write.Statement.StartPos, Write.Statement.EndPos), Message,
        TRuleConfidence.Medium, Fixes);
    end;
  end;

  procedure Visit(ANode, ARoutine: TSyntaxNode; AInLoop: Boolean);
  var
    Index: Integer;
    Method: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      ARoutine := ANode;
      AInLoop := False;
    end
    else if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
      TSyntaxKind.RepeatStatement] then
      AInLoop := True
    else if ANode.Kind = TSyntaxKind.Call then
    begin
      Method := AnonymousArgument(ANode);
      if (Method <> nil) and (IsCallOf(ANode, 'TParallel', ['For']) or
        (AInLoop and IsCallOf(ANode, 'TTask', ['Run', 'Create', 'Future']))) then
        Report(Method, ARoutine);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], ARoutine, AInLoop and (ANode.Kind <> TSyntaxKind.AnonymousMethod));
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'TParallel') or ContainsText(AContext.Text, 'TTask')) then
    Exit;
  SafeTypes := TRuleOptions.Strings(AContext.Options, 'threadSafeTypes', DefaultThreadSafeTypes);
  State := TSharedState.Create(AContext);
  try
    Visit(AContext.Tree.Root, nil, False);
  finally
    State.Free;
  end;
end;

procedure RegisterSharedStateRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TParallelForSharedWriteRule.Create);
end;

end.
