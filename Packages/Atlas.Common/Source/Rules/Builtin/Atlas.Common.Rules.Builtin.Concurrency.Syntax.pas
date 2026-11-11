unit Atlas.Common.Rules.Builtin.Concurrency.Syntax;

// Gemeinsame Bausteine der Nebenläufigkeitsregeln (Atlas.Common.Rules.Builtin.Concurrency und ihre Teil-Units):
// Methodenaufrufe als Anweisung, Quelltext und Bereiche von Knoten, Anweisungslisten, Thread-Klassen der Unit,
// eingebaute Sperrpaare und VCL-Namen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Aufruf X.M, X.M(…) oder M(…) als Anweisung.</summary>
  TMethodCall = record
    Method: string;
    /// <summary>Ausdruck vor dem Punkt, nil bei M(…).</summary>
    Receiver: TSyntaxNode;
    /// <summary>Knoten mit dem Methodennamen (MemberAccess oder Identifier).</summary>
    Member: TSyntaxNode;
    /// <summary>Aufruf mit Argumenten, sonst nil.</summary>
    Call: TSyntaxNode;
  end;

const
  cBuiltinLockPairs: array[0..5, 0..1] of string = (('Enter', 'Leave'), ('Enter', 'Exit'), ('Acquire', 'Release'),
    ('BeginRead', 'EndRead'), ('BeginWrite', 'EndWrite'), ('EnterCriticalSection', 'LeaveCriticalSection'));
  cVclGlobals: array[0..1] of string = ('Application', 'Screen');
  cVclDialogs: array[0..4] of string = ('ShowMessage', 'ShowMessageFmt', 'ShowMessagePos', 'MessageDlg',
    'InputBox');

function InList(const AItems: array of string; const AText: string): Boolean;

function SourceText(const AText: string; ANode: TSyntaxNode): string;

function NodeText(const AText: string; ANode: TSyntaxNode): string;

function TryMethodCall(AStatement: TSyntaxNode; out ACall: TMethodCall): Boolean;

/// <summary>Bereich des Namens am Ende von ANode (MemberAccess oder Identifier).</summary>
function NameRange(ANode: TSyntaxNode): TTextRange;

function NodeRange(ANode: TSyntaxNode): TTextRange;

/// <summary>Bezeichner der Variablen in X oder Self.X, sonst ''.</summary>
function VariableName(ANode: TSyntaxNode): string;

function IsStatementList(ANode: TSyntaxNode): Boolean;

/// <summary>Anweisungslisten in ARoot in Baumreihenfolge. Iterativ gesammelt, damit die Regeln sie
/// ohne eigene Rekursion prüfen.</summary>
function StatementLists(ARoot: TSyntaxNode): TArray<TSyntaxNode>;

/// <summary>True, wenn ANode oder ein Nachfahre den Bezeichner AName benutzt.</summary>
function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;

/// <summary>Klassenteil eines Routinennamens: "TA" in "TA.Destroy", sonst ''.</summary>
function ClassPart(const ARoutineName: string): string;

function MethodPart(const ARoutineName: string): string;

/// <summary>Klassen der Unit, die direkt oder über Klassen der Unit von TThread erben.</summary>
function ThreadClasses(ARoot: TSyntaxNode): TArray<string>;

/// <summary>ThreadClasses der geprüften Datei, je Lauf einmal berechnet.</summary>
function SharedThreadClasses(const AContext: TRuleContext): TArray<string>;

/// <summary>Bereich einer ganzen Anweisung samt Semikolon und Zeilenende, wenn sie allein in ihrer Zeile
/// steht.</summary>
function StatementRemoval(const AText: string; AStatement: TSyntaxNode): TTextRange;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Derived;

function InList(const AItems: array of string; const AText: string): Boolean;
var
  mItem: string;
begin
  for mItem in AItems do
  begin
    if SameText(mItem, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function SourceText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := LowerCase(SourceText(AText, ANode));
end;

function TryMethodCall(AStatement: TSyntaxNode; out ACall: TMethodCall): Boolean;
var
  mTarget: TSyntaxNode;
begin
  Result := False;
  ACall := Default(TMethodCall);
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    ACall.Call := mTarget;
    mTarget := mTarget[0];
  end;
  if (mTarget.Kind = TSyntaxKind.MemberAccess) and (mTarget.ChildCount > 0) then
  begin
    ACall.Receiver := mTarget[0];
  end
  else if (mTarget.Kind <> TSyntaxKind.Identifier) or (ACall.Call = nil) then
  begin
    Exit;
  end;
  ACall.Method := mTarget.Name;
  ACall.Member := mTarget;
  Result := True;
end;

function NameRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(ANode.Name),
    ANode.EndPos.Line, ANode.EndPos.Character);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function VariableName(ANode: TSyntaxNode): string;
begin
  if ANode = nil then
  begin
    Result := '';
  end
  else if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    Result := ANode.Name;
  end
  else
  begin
    Result := '';
  end;
end;

function IsStatementList(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection];
end;

function StatementLists(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mFound: TList<TSyntaxNode>;
begin
  mFound := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if IsStatementList(ANode) then
        begin
          mFound.Add(ANode);
        end;
        Result := True;
      end);
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.Identifier) and SameText(AVisited.Name, mName) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function ClassPart(const ARoutineName: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', ARoutineName);
  if mDot > 0 then
  begin
    Result := Copy(ARoutineName, 1, mDot - 1);
  end
  else
  begin
    Result := '';
  end;
end;

function MethodPart(const ARoutineName: string): string;
begin
  Result := Copy(ARoutineName, LastDelimiter('.', ARoutineName) + 1, MaxInt);
end;

function ThreadClasses(ARoot: TSyntaxNode): TArray<string>;
var
  mNames, mParents: TArray<string>;
  mIndex: Integer;
  mChanged: Boolean;
begin
  Result := nil;
  mNames := nil;
  mParents := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Der Lauf geht auch durch lange Ausdrucksketten.
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      ClassNode, Ancestor: TSyntaxNode;
    begin
      Result := ANode.Kind <> TSyntaxKind.TypeDecl;
      if Result then
      begin
        Exit;
      end;
      ClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if ClassNode = nil then
      begin
        Exit;
      end;
      Ancestor := ClassNode.FindChild(TSyntaxKind.TypeReference);
      if Ancestor = nil then
      begin
        Exit;
      end;
      mNames := mNames + [ANode.Name];
      mParents := mParents + [Ancestor.Name];
    end);
  // Fixpunkt über Zwischenklassen der Unit.
  repeat
    mChanged := False;
    for mIndex := 0 to High(mNames) do
    begin
      if not InList(Result, mNames[mIndex]) and
        (SameText(mParents[mIndex], 'TThread') or SameText(mParents[mIndex], 'System.Classes.TThread') or
        InList(Result, mParents[mIndex])) then
      begin
        Result := Result + [mNames[mIndex]];
        mChanged := True;
      end;
    end;
  until not mChanged;
end;

function SharedThreadClasses(const AContext: TRuleContext): TArray<string>;
var
  mCache: IRuleDerivedCache;
  mRoot: TSyntaxNode;
begin
  mCache := TRuleDerived.Open(AContext);
  mRoot := AContext.Tree.Root;
  Result := TRuleDerived.Get<TRuleDerivedValue<TArray<string>>>(mCache, 'concurrency.threadClasses',
    function: TRuleDerivedValue<TArray<string>>
    begin
      Result := TRuleDerivedValue<TArray<string>>.Create(ThreadClasses(mRoot));
    end).Value;
end;

function StatementRemoval(const AText: string; AStatement: TSyntaxNode): TTextRange;
var
  mIndex: Integer;
  mAlone: Boolean;
begin
  mAlone := True;
  mIndex := AStatement.StartOffset;
  while (mIndex > 0) and (AText[mIndex] <> #10) do
  begin
    if not CharInSet(AText[mIndex], [' ', #9]) then
    begin
      mAlone := False;
    end;
    Dec(mIndex);
  end;
  mIndex := AStatement.EndOffset + 1;
  if (mIndex <= Length(AText)) and (AText[mIndex] = ';') then
  begin
    Inc(mIndex);
  end;
  while (mIndex <= Length(AText)) and not CharInSet(AText[mIndex], [#10, #13]) do
  begin
    if not CharInSet(AText[mIndex], [' ', #9]) then
    begin
      mAlone := False;
    end;
    Inc(mIndex);
  end;
  if mAlone then
  begin
    Result := TTextRange.Create(AStatement.StartPos.Line, 0, AStatement.EndPos.Line + 1, 0);
  end
  else
  begin
    Result := NodeRange(AStatement);
  end;
end;

end.
