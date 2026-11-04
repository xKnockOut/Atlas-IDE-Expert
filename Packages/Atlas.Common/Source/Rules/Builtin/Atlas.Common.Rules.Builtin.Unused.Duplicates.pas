unit Atlas.Common.Rules.Builtin.Unused.Duplicates;

// duplicate-assignment (#1051), aus Atlas.Common.Rules.Builtin.Unused herausgelöst; angemeldet wird die Regel
// weiter über RegisterUnusedRules. Beschreibung der Regel siehe dort.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

type
  TDuplicateAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ziel als Schlüssel ("Panel.Font.Size", "P^.X", Self. entfällt); '' bei Index, Aufruf und anderem.</summary>
    class function TargetKey(ANode: TSyntaxNode): string; static;
    /// <summary>Gegenstück für den Hinweis (Left zu Top, Height zu Width …); '' ohne.</summary>
    class function Counterpart(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Unused.Shared;

const
  // Gegenstücke für den Hinweis "gemeint ist vermutlich …" (Left/Top vertauscht beim Kopieren).
  CounterpartPairs: array[0..9, 0..1] of string = (('Left', 'Top'), ('Width', 'Height'), ('Right', 'Bottom'),
    ('X', 'Y'), ('Min', 'Max'), ('MinValue', 'MaxValue'), ('ClientWidth', 'ClientHeight'), ('Row', 'Col'),
    ('MinWidth', 'MinHeight'), ('MaxWidth', 'MaxHeight'));
  // Knoten, deren Kinder nacheinander ausgeführte Anweisungen sind.
  StatementLists = [TSyntaxKind.Block, TSyntaxKind.RepeatStatement, TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock,
    TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection];

function TDuplicateAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('duplicate-assignment', TRuleSeverity.Warning,
    'Feld oder Property wird zweimal gesetzt');
end;

// Iterativ (Bericht M1): erst die Kette aus Punkten und ^ hinab, dann den Schlüssel von innen nach außen bauen.
class function TDuplicateAssignmentRule.TargetKey(ANode: TSyntaxNode): string;
var
  Chain: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Base: string;
begin
  Chain := TStack<TSyntaxNode>.Create;
  try
    Node := ANode;
    while (Node.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference]) and (Node.ChildCount = 1) do
    begin
      Chain.Push(Node);
      Node := Node[0];
    end;
    Result := '';
    if Node.Kind = TSyntaxKind.Identifier then
    begin
      Result := Node.Name;
    end;
    while Chain.Count > 0 do
    begin
      Node := Chain.Pop;
      Base := Result;
      Result := '';
      if Node.Kind = TSyntaxKind.MemberAccess then
      begin
        if SameText(Base, 'Self') then
        begin
          Result := Node.Name;
        end
        else if Base <> '' then
        begin
          Result := Base + '.' + Node.Name;
        end;
      end
      else if Base <> '' then
      begin
        Result := Base + '^';
      end;
    end;
  finally
    Chain.Free;
  end;
end;

class function TDuplicateAssignmentRule.Counterpart(const AName: string): string;
var
  Index: Integer;
begin
  for Index := Low(CounterpartPairs) to High(CounterpartPairs) do
  begin
    if SameText(CounterpartPairs[Index, 0], AName) then
    begin
      Exit(CounterpartPairs[Index, 1]);
    end
    else if SameText(CounterpartPairs[Index, 1], AName) then
    begin
      Exit(CounterpartPairs[Index, 0]);
    end;
  end;
  Result := '';
end;

/// <summary>Teile des Schlüssels "Panel.Font.Size" bzw. "P^.X" ohne ^.</summary>
function KeyParts(const AKey: string): TArray<string>;
begin
  Result := StringReplace(AKey, '^', '', [rfReplaceAll]).Split(['.']);
end;

/// <summary>Wurzel des Schlüssels: einfache Bezeichner gehören zu Self (Feld oder Property der eigenen Klasse).
/// </summary>
function KeyRoot(const AKey: string): string;
begin
  if Pos('.', AKey) = 0 then
  begin
    Result := 'Self';
  end
  else
  begin
    Result := KeyParts(AKey)[0];
  end;
end;

/// <summary>Schlüssel des Ziels, wenn ANode eine Zuweisung mit Wert ist; '' sonst.</summary>
function AssignmentKey(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount >= 2) then
  begin
    Result := TDuplicateAssignmentRule.TargetKey(ANode[0]);
  end;
end;

/// <summary>Kommt unter ANode ein Bezeichner aus AParts vor, ein Aufruf oder etwas, das Code ausführt?
/// Dann kann der Ausdruck den ersten Wert lesen.</summary>
// Iterativ (Bericht M1).
function MayRead(ANode: TSyntaxNode; const AParts: TArray<string>): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind in [TSyntaxKind.Call, TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(True);
      end;
      if (Node.Kind = TSyntaxKind.Identifier) and MatchText(Node.Name, AParts) then
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

/// <summary>Namen aus den var-Abschnitten, Parametern und Inline-Variablen der Routine ARoutine.</summary>
function RoutineLocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mSection, mParameters: TSyntaxNode;
  mInlineVars: TArray<TSyntaxNode>;
  mIndex, mInner: Integer;
begin
  Result := nil;
  mInlineVars := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    mParameters := nil;
    case mSection.Kind of
      TSyntaxKind.VarSection:
        mParameters := mSection;
      TSyntaxKind.RoutineHeader:
        mParameters := mSection.FindChild(TSyntaxKind.Parameters);
      TSyntaxKind.Block:
        CollectInlineVars(mSection, mInlineVars);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if mParameters <> nil then
    begin
      for mInner := 0 to mParameters.ChildCount - 1 do
      begin
        Result := Result + SplitNames(mParameters[mInner].Name);
      end;
    end;
  end;
  for mIndex := 0 to High(mInlineVars) do
  begin
    Result := Result + SplitNames(mInlineVars[mIndex].Name);
  end;
end;

/// <summary>Lokale Namen von ARoutine und umschließenden Routinen: Variablen, Parameter, Result, Routinenname.</summary>
function LocalNames(ANode: TSyntaxNode): TArray<string>;
begin
  Result := nil;
  while ANode <> nil do
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result + ['Result', ShortName(ANode.Name)] + RoutineLocalNames(ANode);
    end;
    ANode := ANode.Parent;
  end;
end;

function IsBooleanLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and (SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False'));
end;

/// <summary>False/True im Wechsel stößt oft etwas an (Active, Open).</summary>
function TogglesBoolean(AFirst, ASecond: TSyntaxNode): Boolean;
begin
  Result := IsBooleanLiteral(AFirst[1]) and IsBooleanLiteral(ASecond[1]) and
    not SameText(AFirst[1].Name, ASecond[1].Name);
end;

/// <summary>Setzt eine Zuweisung unter AParent das Ziel ASwapped?</summary>
function AssignsTarget(AParent: TSyntaxNode; const ASwapped: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if (AParent[mIndex].Kind = TSyntaxKind.AssignStatement) and (AParent[mIndex].ChildCount > 0) and
      SameText(TDuplicateAssignmentRule.TargetKey(AParent[mIndex][0]), ASwapped) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zusatz der Meldung: Fehlt das Gegenstück (Left/Top …) in der Folge, eine Vermutung.</summary>
function DuplicateHint(AParent: TSyntaxNode; const AKey, ADisplay, AName: string): string;
var
  mOther: string;
begin
  Result := 'der erste Wert geht ungelesen verloren';
  mOther := TDuplicateAssignmentRule.Counterpart(AName);
  if (mOther <> '') and not AssignsTarget(AParent, Copy(AKey, 1, Length(AKey) - Length(AName)) + mOther) then
  begin
    Result := 'gemeint ist vermutlich ' + Copy(ADisplay, 1, Length(ADisplay) - Length(AName)) + mOther;
  end;
end;

type
  /// <summary>Ein Lauf von duplicate-assignment über eine Datei.</summary>
  TDuplicateAssignmentCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FAllowed: TArray<string>;
    FLocals: TArray<string>;
    FLocalsOwner: TSyntaxNode;
    function PathOf(ANode: TSyntaxNode): string;
    function NodeText(ANode: TSyntaxNode): string;
    function IsAllowed(const AKey: string): Boolean;
    function IsLocal(AParent: TSyntaxNode; const AKey: string): Boolean;
    function FindSecond(AParent: TSyntaxNode; AFirst: Integer; const AKey: string; out AIndex: Integer): Boolean;
    function Reportable(AFirst, ASecond: TSyntaxNode; const AParts: TArray<string>): Boolean;
    procedure CheckFrom(AParent: TSyntaxNode; AFirst: Integer; const AKey: string);
    procedure CheckChild(AParent: TSyntaxNode; AIndex: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Visit(ARoot: TSyntaxNode);
  end;

constructor TDuplicateAssignmentCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FAllowed := TRuleOptions.Strings(AContext.Options, 'allowProperties', ['Visible', 'Enabled']);
end;

function TDuplicateAssignmentCheck.PathOf(ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(FPaths, TRoutineBody.TokenAt(FTokens, ANode.StartOffset));
end;

function TDuplicateAssignmentCheck.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TDuplicateAssignmentCheck.IsAllowed(const AKey: string): Boolean;
var
  mParts: TArray<string>;
  mPattern: string;
begin
  mParts := KeyParts(AKey);
  for mPattern in FAllowed do
  begin
    if MatchesWildcard(mParts[High(mParts)], Trim(mPattern)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist AKey eine lokale Variable? Die deckt unused-assignment ab.</summary>
function TDuplicateAssignmentCheck.IsLocal(AParent: TSyntaxNode; const AKey: string): Boolean;
begin
  if Pos('.', AKey) + Pos('^', AKey) <> 0 then
  begin
    Exit(False);
  end;
  if FLocalsOwner <> AParent then
  begin
    FLocals := LocalNames(AParent);
    FLocalsOwner := AParent;
  end;
  Result := MatchText(AKey, FLocals);
end;

/// <summary>Sucht ab AFirst + 1 die nächste Zuweisung an dasselbe Ziel; dazwischen nur Zuweisungen an andere
/// Objekte, deren Werte nichts aufrufen und das Ziel nicht nennen.</summary>
function TDuplicateAssignmentCheck.FindSecond(AParent: TSyntaxNode; AFirst: Integer; const AKey: string;
  out AIndex: Integer): Boolean;
var
  mParts: TArray<string>;
  mKey: string;
  mIndex: Integer;
begin
  AIndex := -1;
  mParts := KeyParts(AKey);
  for mIndex := AFirst + 1 to AParent.ChildCount - 1 do
  begin
    mKey := AssignmentKey(AParent[mIndex]);
    if SameText(mKey, AKey) then
    begin
      AIndex := mIndex;
      Exit(True);
    end;
    if (mKey = '') or SameText(KeyRoot(mKey), KeyRoot(AKey)) or MayRead(AParent[mIndex][1], mParts) then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Der zweite Wert darf den ersten nicht lesen und nicht nur False/True wechseln. Bei bedingter
/// Übersetzung nur, wenn die zweite Zuweisung immer mit der ersten übersetzt wird.</summary>
function TDuplicateAssignmentCheck.Reportable(AFirst, ASecond: TSyntaxNode; const AParts: TArray<string>): Boolean;
begin
  Result := not MayRead(ASecond[1], AParts) and not TogglesBoolean(AFirst, ASecond) and
    TConditionalBranches.Implies(PathOf(AFirst), PathOf(ASecond));
end;

procedure TDuplicateAssignmentCheck.CheckFrom(AParent: TSyntaxNode; AFirst: Integer; const AKey: string);
var
  mFirst, mSecond: TSyntaxNode;
  mParts: TArray<string>;
  mIndex: Integer;
  mDisplay: string;
begin
  if not FindSecond(AParent, AFirst, AKey, mIndex) then
  begin
    Exit;
  end;
  mFirst := AParent[AFirst];
  mSecond := AParent[mIndex];
  mParts := KeyParts(AKey);
  if not Reportable(mFirst, mSecond, mParts) then
  begin
    Exit;
  end;
  mDisplay := NodeText(mSecond[0]);
  FReport.Add(TTextRange.Create(mSecond[0].StartPos, mSecond[0].EndPos),
    Format('%s wird in Zeile %d schon gesetzt; %s.', [mDisplay, mFirst.StartPos.Line + 1,
    DuplicateHint(AParent, AKey, mDisplay, mParts[High(mParts)])]), TRuleConfidence.High,
    [TRuleFix.Jump('Zur ersten Zuweisung springen', mFirst.StartPos)]);
end;

/// <summary>Nur Anweisungsfolgen; then- und else-Zweig eines if stehen auch nebeneinander.</summary>
procedure TDuplicateAssignmentCheck.CheckChild(AParent: TSyntaxNode; AIndex: Integer);
var
  mKey: string;
begin
  if not (AParent.Kind in StatementLists) then
  begin
    Exit;
  end;
  mKey := AssignmentKey(AParent[AIndex]);
  if (mKey <> '') and not IsAllowed(mKey) and not IsLocal(AParent, mKey) then
  begin
    CheckFrom(AParent, AIndex, mKey);
  end;
end;

// Iterativ (Bericht M1): der Stapel hält Elternknoten und Kindindex, damit jedes Kind wie bisher vor dem
// Abstieg in seine Kinder geprüft wird.
procedure TDuplicateAssignmentCheck.Visit(ARoot: TSyntaxNode);
var
  mPendingParent: TStack<TSyntaxNode>;
  mPendingIndex: TStack<Integer>;
  mParent, mChild: TSyntaxNode;
  mIndex, mChildIndex: Integer;
begin
  mPendingParent := TStack<TSyntaxNode>.Create;
  mPendingIndex := TStack<Integer>.Create;
  try
    for mChildIndex := ARoot.ChildCount - 1 downto 0 do
    begin
      mPendingParent.Push(ARoot);
      mPendingIndex.Push(mChildIndex);
    end;
    while mPendingParent.Count > 0 do
    begin
      mParent := mPendingParent.Pop;
      mIndex := mPendingIndex.Pop;
      mChild := mParent[mIndex];
      CheckChild(mParent, mIndex);
      for mChildIndex := mChild.ChildCount - 1 downto 0 do
      begin
        mPendingParent.Push(mChild);
        mPendingIndex.Push(mChildIndex);
      end;
    end;
  finally
    mPendingIndex.Free;
    mPendingParent.Free;
  end;
end;

procedure TDuplicateAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TDuplicateAssignmentCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos(':=', AContext.Text) = 0) then
  begin
    Exit;
  end;
  mCheck := TDuplicateAssignmentCheck.Create(AContext, AReport);
  try
    mCheck.Visit(AContext.Tree.Root);
  finally
    mCheck.Free;
  end;
end;

end.
