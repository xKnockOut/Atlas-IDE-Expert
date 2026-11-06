unit Atlas.Common.Rules.Builtin.Recursion;

// Property-Falle (#623, #910):
//   setter-recursion   Setter schreibt bzw. Getter liest die eigene Property
//                      (Name := Value in SetName) und ruft sich damit endlos
//                      selbst auf. Fehler mit hoher Konfidenz; bis #910 hieß
//                      die Regel recursive-property-accessor (TRuleIdAliases).
// Die Analyse liefert TRecursionAnalysis.AccessorTraps. Die Korrektur setzt
// das Feld ein: aus read/write der Property, sonst F<Name>, wenn die Klasse
// es hat. Geerbte Properties und Accessoren in anderen Units sieht die
// Analyse nicht.
//
// Rekursion ohne Abbruch (#1044):
//   unconditional-recursion  Eine Routine ruft sich auf jedem Pfad selbst auf,
//                      bevor sie zurückkehren kann (Stapelüberlauf). Die direkten
//                      Selbstaufrufe liefert TRecursionAnalysis.Calls (Tiefe 1);
//                      Getter und Setter der eigenen Property bleiben bei
//                      setter-recursion. Ein Pfad ohne Aufruf ist: Zweig von if
//                      ohne else bzw. case ohne else, Rumpf von while und for,
//                      rechter Teil von and/or, Zweige von if-Ausdrücken, anonyme
//                      Methoden. Exit, raise, goto, Halt, Abort (bzw. Break und
//                      Continue in einer Schleife) vor dem Aufruf beenden den Pfad.
//                      Überladene Routinen bleiben still (Aufruf einer anderen
//                      Überladung).

interface

uses
  Atlas.Common.Semantics.Recursion,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  SetterRecursionRuleId = 'setter-recursion';
  UnconditionalRecursionRuleId = 'unconditional-recursion';

type
  TSetterRecursionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Meldungstext eines Treffers.</summary>
    class function Message(const ATrap: TAccessorTrap): string; static;
  end;

  TUnconditionalRecursionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterRecursionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRecursionText = (AccessorTitle, SetterRecursion, GetterRecursion, UseField, Title, NoTerminationExample,
    NoTermination);

const
  cTexts: array[TRecursionText] of TAtlasText = (
    (De: 'Setter oder Getter ruft sich selbst auf (Endlosrekursion)';
     En: 'Setter or getter calls itself (endless recursion)'),
    (De: 'Zuweisung an die Property %s im eigenen Setter: Endlosrekursion.';
     En: 'Assignment to the property %s in its own setter: endless recursion.'),
    (De: 'Lesen der Property %s im eigenen Getter: Endlosrekursion.';
     En: 'Reading the property %s in its own getter: endless recursion.'),
    (De: 'Feld %s verwenden'; En: 'Use field %s'),
    (De: 'Rekursion ohne Abbruch'; En: 'Recursion without termination'),
    (De: '%s ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch (z. B. %s).';
     En: '%s calls itself on every path; the termination is missing (e.g. %s).'),
    (De: '%s ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch.';
     En: '%s calls itself on every path; the termination is missing.'));

{$SCOPEDENUMS OFF}

{ TSetterRecursionRule }

function TSetterRecursionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SetterRecursionRuleId, TRuleSeverity.Error,
    cTexts[TRecursionText.AccessorTitle].Text);
end;

class function TSetterRecursionRule.Message(const ATrap: TAccessorTrap): string;
begin
  if ATrap.IsSetter then
  begin
    Result := cTexts[TRecursionText.SetterRecursion].Fmt([ATrap.PropertyName]);
  end
  else
  begin
    Result := cTexts[TRecursionText.GetterRecursion].Fmt([ATrap.PropertyName]);
  end;
end;

procedure TSetterRecursionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Trap: TAccessorTrap;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for Trap in TRecursionAnalysis.AccessorTraps(AContext.Tree) do
  begin
    if Trap.Field <> '' then
    begin
      AReport.Add(Trap.Range, Message(Trap), [TRuleFix.Create(cTexts[TRecursionText.UseField].Fmt([Trap.Field]),
        [TRuleEdit.Create(Trap.Range, Trap.Field)])]);
    end
    else
    begin
      AReport.Add(Trap.Range, Message(Trap));
    end;
  end;
end;

{ TUnconditionalRecursionRule }

const
  // Aufrufe, die die Routine verlassen.
  LeavingCalls: array[0..4] of string = ('Exit', 'Halt', 'Abort', 'RunError', 'ExitProcess');
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];

function TUnconditionalRecursionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnconditionalRecursionRuleId, TRuleSeverity.Error,
    cTexts[TRecursionText.Title].Text);
end;

/// <summary>Liegt A nicht hinter B?</summary>
function NotAfter(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Liegt A vor B?</summary>
function Earlier(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function Inside(const APosition: TTextPosition; ANode: TSyntaxNode): Boolean;
begin
  Result := NotAfter(ANode.StartPos, APosition) and Earlier(APosition, ANode.EndPos);
end;

/// <summary>Legt die Kinder von ANode so auf APending, dass das erste zuerst wieder herunterkommt.</summary>
procedure PushChildren(ANode: TSyntaxNode; APending: TStack<TSyntaxNode>);
var
  mIndex: Integer;
begin
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(ANode[mIndex]);
  end;
end;

/// <summary>Legt nur das erste Kind von ANode auf APending (falls vorhanden).</summary>
procedure PushFirst(ANode: TSyntaxNode; APending: TStack<TSyntaxNode>);
begin
  if ANode.ChildCount > 0 then
  begin
    APending.Push(ANode[0]);
  end;
end;

/// <summary>Selbstaufrufe einer Routine und die Prüfung, ob jeder Pfad einen davon ausführt.</summary>
type
  TSelfCalls = class
  private
    FSites: TArray<TTextPosition>;
    function SiteIn(const AFrom, ATo: TTextPosition): Boolean;
    function Leaves(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
    /// <summary>Prüft einen Ausdrucksknoten und legt die auf jedem Weg ausgewerteten Kinder auf APending.</summary>
    function CallsAt(ANode: TSyntaxNode; APending: TStack<TSyntaxNode>): Boolean;
    /// <summary>Wertet einer der Ausdrücke ANode[0..ChildCount-2] (Kopf von for bzw. with) einen Selbstaufruf aus?</summary>
    function InHead(ANode: TSyntaxNode): Boolean;
    /// <summary>Ein Durchlauf von Always für den Knoten ANode; ANext: als Nächstes zu prüfender Knoten oder nil.</summary>
    function Step(ANode: TSyntaxNode; ALoop: Boolean; out ANext: TSyntaxNode): Boolean;
    function IfAlways(ANode: TSyntaxNode; ALoop: Boolean; out ANext: TSyntaxNode): Boolean;
    function CaseAlways(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
    /// <summary>Führt ein case-Zweig (bzw. der else-Teil) auf jedem Pfad einen Selbstaufruf aus?</summary>
    function CasePartAlways(APart: TSyntaxNode; ALoop: Boolean): Boolean;
    function RepeatAlways(ANode: TSyntaxNode): Boolean;
    function WithAlways(ANode: TSyntaxNode; out ANext: TSyntaxNode): Boolean;
    function TryAlways(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
  public
    constructor Create(const ASites: TArray<TTextPosition>);
    /// <summary>Wertet ein Ausdruck auf jedem Weg einen Selbstaufruf aus?</summary>
    function InExpression(ANode: TSyntaxNode): Boolean;
    /// <summary>Führt die Anweisung ANode auf jedem Pfad einen Selbstaufruf aus, bevor sie endet oder die
    /// Routine verlässt? ALoop: ANode steht im Rumpf einer Schleife (Break und Continue verlassen ihn).</summary>
    function Always(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
    /// <summary>Wie Always für die Anweisungen AFirst..ALast von AParent nacheinander.</summary>
    function AlwaysList(AParent: TSyntaxNode; AFirst, ALast: Integer; ALoop: Boolean): Boolean;
  end;

constructor TSelfCalls.Create(const ASites: TArray<TTextPosition>);
begin
  inherited Create;
  FSites := ASites;
end;

function TSelfCalls.SiteIn(const AFrom, ATo: TTextPosition): Boolean;
var
  mSite: TTextPosition;
begin
  for mSite in FSites do
  begin
    if NotAfter(AFrom, mSite) and Earlier(mSite, ATo) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSelfCalls.CallsAt(ANode: TSyntaxNode; APending: TStack<TSyntaxNode>): Boolean;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.AnonymousMethod:
      // Rumpf läuft nicht auf jedem Weg.
      ;
    TSyntaxKind.Identifier:
      Result := SiteIn(ANode.StartPos, ANode.EndPos);
    TSyntaxKind.MemberAccess:
      begin
        // Self.Name: der Name hinter dem Empfänger.
        Result := (ANode.ChildCount > 0) and SiteIn(ANode[0].EndPos, ANode.EndPos);
        PushChildren(ANode, APending);
      end;
    TSyntaxKind.BinaryExpr:
      // Kurzschluss: rechts von and/or nicht auf jedem Weg.
      if (ANode.Name = 'and') or (ANode.Name = 'or') then
      begin
        PushFirst(ANode, APending);
      end
      else
      begin
        PushChildren(ANode, APending);
      end;
    TSyntaxKind.IfExpr:
      PushFirst(ANode, APending);
  else
    PushChildren(ANode, APending);
  end;
end;

function TSelfCalls.InExpression(ANode: TSyntaxNode): Boolean;
var
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while (mPending.Count > 0) and not Result do
    begin
      Result := CallsAt(mPending.Pop, mPending);
    end;
  finally
    mPending.Free;
  end;
end;

function TSelfCalls.Leaves(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Loops: TStack<Boolean>;
  Node: TSyntaxNode;
  Loop, ChildLoop: Boolean;
  Index: Integer;
  Name: string;
begin
  // Iterativ (Bericht M1); Loops führt ALoop je Knoten mit.
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  Loops := TStack<Boolean>.Create;
  try
    Pending.Push(ANode);
    Loops.Push(ALoop);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Loop := Loops.Pop;
      case Node.Kind of
        TSyntaxKind.AnonymousMethod:
          Continue;
        TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
          Exit(True);
        TSyntaxKind.Identifier, TSyntaxKind.Call:
          begin
            Name := Node.Name;
            if MatchText(Name, LeavingCalls) or (Loop and MatchText(Name, ['Break', 'Continue'])) then
            begin
              Exit(True);
            end;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      ChildLoop := Loop and not (Node.Kind in LoopKinds);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
        Loops.Push(ChildLoop);
      end;
    end;
  finally
    Loops.Free;
    Pending.Free;
  end;
end;

function TSelfCalls.AlwaysList(AParent: TSyntaxNode; AFirst, ALast: Integer; ALoop: Boolean): Boolean;
var
  Index: Integer;
begin
  for Index := AFirst to ALast do
  begin
    if Always(AParent[Index], ALoop) then
    begin
      Exit(True);
    end;
    if Leaves(AParent[Index], ALoop) then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

function TSelfCalls.InHead(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ANode.ChildCount - 2 do
  begin
    if InExpression(ANode[mIndex]) then
    begin
      Exit(True);
    end;
  end;
end;

function TSelfCalls.IfAlways(ANode: TSyntaxNode; ALoop: Boolean; out ANext: TSyntaxNode): Boolean;
begin
  // else-Zweig als nächster Durchlauf statt rekursiv.
  ANext := nil;
  Result := (ANode.ChildCount > 0) and InExpression(ANode[0]);
  if not Result and (ANode.ChildCount = 3) and Always(ANode[1], ALoop) then
  begin
    ANext := ANode[2];
  end;
end;

function TSelfCalls.CasePartAlways(APart: TSyntaxNode; ALoop: Boolean): Boolean;
begin
  if APart.Kind = TSyntaxKind.CaseElse then
  begin
    Result := AlwaysList(APart, 0, APart.ChildCount - 1, ALoop);
  end
  else
  begin
    Result := (APart.ChildCount > 0) and Always(APart[APart.ChildCount - 1], ALoop);
  end;
end;

function TSelfCalls.CaseAlways(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
var
  mIndex: Integer;
begin
  if ANode.ChildCount = 0 then
  begin
    Exit(False);
  end;
  if InExpression(ANode[0]) then
  begin
    Exit(True);
  end;
  // Ohne else gibt es einen Pfad ohne Zweig; sonst muss jeder Zweig aufrufen.
  Result := ANode.FindChild(TSyntaxKind.CaseElse) <> nil;
  mIndex := 1;
  while Result and (mIndex < ANode.ChildCount) do
  begin
    Result := CasePartAlways(ANode[mIndex], ALoop);
    Inc(mIndex);
  end;
end;

function TSelfCalls.RepeatAlways(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.ChildCount > 0) and (AlwaysList(ANode, 0, ANode.ChildCount - 2, True) or
    (not Leaves(ANode, True) and InExpression(ANode[ANode.ChildCount - 1])));
end;

function TSelfCalls.WithAlways(ANode: TSyntaxNode; out ANext: TSyntaxNode): Boolean;
begin
  // Rumpf als nächster Durchlauf statt rekursiv.
  ANext := nil;
  Result := InHead(ANode);
  if not Result and (ANode.ChildCount > 0) then
  begin
    ANext := ANode[ANode.ChildCount - 1];
  end;
end;

function TSelfCalls.TryAlways(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
var
  mIndex: Integer;
begin
  // try-Teil nacheinander; bei try … finally zählt auch der finally-Teil.
  mIndex := 0;
  while (mIndex < ANode.ChildCount) and not (ANode[mIndex].Kind in [TSyntaxKind.ExceptBlock,
    TSyntaxKind.FinallyBlock]) do
  begin
    Inc(mIndex);
  end;
  Result := AlwaysList(ANode, 0, mIndex - 1, ALoop) or ((mIndex < ANode.ChildCount) and
    (ANode[mIndex].Kind = TSyntaxKind.FinallyBlock) and Always(ANode[mIndex], ALoop));
end;

function TSelfCalls.Step(ANode: TSyntaxNode; ALoop: Boolean; out ANext: TSyntaxNode): Boolean;
begin
  Result := False;
  ANext := nil;
  case ANode.Kind of
    TSyntaxKind.Block, TSyntaxKind.LabeledStatement, TSyntaxKind.FinallyBlock:
      Result := AlwaysList(ANode, 0, ANode.ChildCount - 1, ALoop);
    TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst:
      Result := InExpression(ANode);
    TSyntaxKind.IfStatement:
      Result := IfAlways(ANode, ALoop, ANext);
    TSyntaxKind.CaseStatement:
      Result := CaseAlways(ANode, ALoop);
    TSyntaxKind.WhileStatement:
      Result := (ANode.ChildCount > 0) and InExpression(ANode[0]);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      Result := InHead(ANode);
    TSyntaxKind.RepeatStatement:
      Result := RepeatAlways(ANode);
    TSyntaxKind.WithStatement:
      Result := WithAlways(ANode, ANext);
    TSyntaxKind.TryStatement:
      Result := TryAlways(ANode, ALoop);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

// Lange else-if-Ketten und with-Rümpfe laufen iterativ über Node (Bericht M1); Ausdrücke prüfen die iterativen
// InExpression und Leaves. Rekursiv bleibt nur der Abstieg in then-Zweige, Blöcke und case-Zweige: diese
// Schachtelung baut der Parser selbst rekursiv auf (ParseStatement), sie ist durch dessen größere Rahmen begrenzt.
function TSelfCalls.Always(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
var
  mNode, mNext: TSyntaxNode;
begin
  Result := False;
  mNode := ANode;
  while mNode <> nil do
  begin
    Result := Step(mNode, ALoop, mNext);
    mNode := mNext;
  end;
end;

/// <summary>Hinweis auf den fehlenden Abbruch am ersten Parameter, z. B. "K = nil".</summary>
function StopHint(ARoutine: TSyntaxNode): string;
var
  Header, Parameters, Parameter, TypeNode: TSyntaxNode;
  Name, TypeName: string;
begin
  Result := '';
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
  begin
    Exit;
  end;
  Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if (Parameters = nil) or (Parameters.ChildCount = 0) then
  begin
    Exit;
  end;
  Parameter := Parameters[0];
  Name := Parameter.Name.Split([','])[0];
  TypeNode := Parameter.FindChild(TSyntaxKind.TypeReference);
  if TypeNode <> nil then
  begin
    TypeName := TypeNode.Name;
  end
  else
  begin
    TypeName := '';
  end;
  if MatchText(TypeName, ['Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'SmallInt', 'ShortInt', 'LongInt', 'LongWord']) then
  begin
    Result := Name + ' <= 0';
  end
  else if MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString']) then
  begin
    Result := Name + ' = ''''';
  end
  else if SameText(TypeName, 'TArray') or StartsText('TArray<', TypeName) or
    (Parameter.FindChild(TSyntaxKind.ArrayType) <> nil) then
  begin
    Result := 'Length(' + Name + ') = 0';
  end
  else if (Length(TypeName) > 1) and CharInSet(TypeName[1], ['T', 'P', 'I']) and
    CharInSet(TypeName[2], ['A'..'Z']) then
  begin
    Result := Name + ' = nil';
  end;
end;

/// <summary>Teil nach dem letzten Punkt eines qualifizierten Namens.</summary>
function ShortName(const AName: string): string;
begin
  Result := Copy(AName, AName.LastIndexOf('.') + 2, MaxInt);
end;

/// <summary>Innerste implementierte Routine unter ARoot, die APosition enthält.</summary>
function RoutineAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  mIndex: Integer;
  mNode, mNext: TSyntaxNode;
begin
  // Iterativ (Bericht M1): je Ebene in das erste Kind, das APosition enthält.
  Result := nil;
  mNode := ARoot;
  while mNode <> nil do
  begin
    mNext := nil;
    mIndex := 0;
    while (mNext = nil) and (mIndex < mNode.ChildCount) do
    begin
      if Inside(APosition, mNode[mIndex]) then
      begin
        mNext := mNode[mIndex];
      end;
      Inc(mIndex);
    end;
    if (mNext <> nil) and (mNext.Kind = TSyntaxKind.RoutineDecl) and (mNext.FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Result := mNext;
    end;
    mNode := mNext;
  end;
end;

/// <summary>Trägt die Routinendeklaration bzw. der Kopf ADecl die Direktive overload?</summary>
function HasOverloadDirective(ADecl: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mHeader := ADecl;
  if ADecl.Kind = TSyntaxKind.RoutineDecl then
  begin
    mHeader := ADecl.FindChild(TSyntaxKind.RoutineHeader);
  end;
  if mHeader = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    if (mHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(mHeader[mIndex].Name, 'overload') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Ein Lauf von unconditional-recursion über eine Datei.</summary>
type
  TRecursionScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoot: TSyntaxNode;
    FCalls: TArray<TRecursiveCall>;
    FTraps: TArray<TAccessorTrap>;
    // Kurznamen (klein) mit overload-Direktive oder mehreren Rümpfen gleichen Namens.
    FOverloaded: TArray<string>;
    // Bereits gemeldete Routinen (Name klein).
    FReported: TArray<string>;
    FBodies: TArray<string>;
    procedure CollectOverloads;
    procedure CollectRoutine(ADecl: TSyntaxNode);
    function IsTrap(const APosition: TTextPosition): Boolean;
    /// <summary>Alle Selbstaufrufe von ARoutine, ohne Property-Zugriffe (setter-recursion).</summary>
    function SitesOf(ARoutine: TSyntaxNode): TArray<TTextPosition>;
    function AlwaysRecurses(ARoutine: TSyntaxNode; const ASites: TArray<TTextPosition>): Boolean;
    procedure CheckCall(const ACall: TRecursiveCall);
    procedure ReportCall(const ACall: TRecursiveCall; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TRecursionScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRoot := AContext.Tree.Root;
end;

procedure TRecursionScan.CollectRoutine(ADecl: TSyntaxNode);
var
  mKey: string;
begin
  mKey := ShortName(LowerCase(ADecl.Name));
  if HasOverloadDirective(ADecl) then
  begin
    FOverloaded := FOverloaded + [mKey];
  end;
  if (ADecl.Kind = TSyntaxKind.RoutineDecl) and (ADecl.FindChild(TSyntaxKind.Block) <> nil) then
  begin
    if IndexStr(LowerCase(ADecl.Name), FBodies) >= 0 then
    begin
      FOverloaded := FOverloaded + [mKey];
    end;
    FBodies := FBodies + [LowerCase(ADecl.Name)];
  end;
end;

procedure TRecursionScan.CollectOverloads;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (Vorordnung).
  FBodies := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    PushChildren(FRoot, mPending);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
      begin
        CollectRoutine(mNode);
      end;
      PushChildren(mNode, mPending);
    end;
  finally
    mPending.Free;
  end;
  FBodies := nil;
end;

function TRecursionScan.IsTrap(const APosition: TTextPosition): Boolean;
var
  mTrap: TAccessorTrap;
begin
  for mTrap in FTraps do
  begin
    if mTrap.Range.StartPos = APosition then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TRecursionScan.SitesOf(ARoutine: TSyntaxNode): TArray<TTextPosition>;
var
  mCall: TRecursiveCall;
begin
  Result := nil;
  for mCall in FCalls do
  begin
    if (RoutineAt(FRoot, mCall.Range.StartPos) = ARoutine) and not IsTrap(mCall.Range.StartPos) then
    begin
      Result := Result + [mCall.Range.StartPos];
    end;
  end;
end;

function TRecursionScan.AlwaysRecurses(ARoutine: TSyntaxNode; const ASites: TArray<TTextPosition>): Boolean;
var
  mAnalysis: TSelfCalls;
begin
  mAnalysis := TSelfCalls.Create(ASites);
  try
    Result := mAnalysis.Always(ARoutine.FindChild(TSyntaxKind.Block), False);
  finally
    mAnalysis.Free;
  end;
end;

procedure TRecursionScan.ReportCall(const ACall: TRecursiveCall; ARoutine: TSyntaxNode);
var
  mName, mHint: string;
begin
  mName := ShortName(ACall.Chain[0].Name);
  mHint := StopHint(ARoutine);
  if mHint <> '' then
  begin
    FReport.Add(ACall.Chain[0].Range, cTexts[TRecursionText.NoTerminationExample].Fmt([mName, mHint]),
      TRuleConfidence.High);
  end
  else
  begin
    FReport.Add(ACall.Chain[0].Range, cTexts[TRecursionText.NoTermination].Fmt([mName]), TRuleConfidence.High);
  end;
end;

procedure TRecursionScan.CheckCall(const ACall: TRecursiveCall);
var
  mRoutine: TSyntaxNode;
  mKey: string;
  mSites: TArray<TTextPosition>;
begin
  mRoutine := RoutineAt(FRoot, ACall.Range.StartPos);
  if mRoutine = nil then
  begin
    Exit;
  end;
  mKey := LowerCase(mRoutine.Name);
  if (IndexStr(mKey, FReported) >= 0) or (IndexStr(ShortName(mKey), FOverloaded) >= 0) then
  begin
    Exit;
  end;
  FReported := FReported + [mKey];
  mSites := SitesOf(mRoutine);
  if (mSites <> nil) and AlwaysRecurses(mRoutine, mSites) then
  begin
    ReportCall(ACall, mRoutine);
  end;
end;

procedure TRecursionScan.Run;
var
  mCall: TRecursiveCall;
begin
  FCalls := TRecursionAnalysis.Calls(FContext.Tree, 1);
  if FCalls = nil then
  begin
    Exit;
  end;
  FTraps := TRecursionAnalysis.AccessorTraps(FContext.Tree);
  CollectOverloads;
  for mCall in FCalls do
  begin
    CheckCall(mCall);
  end;
end;

procedure TUnconditionalRecursionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TRecursionScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TRecursionScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterRecursionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSetterRecursionRule.Create);
  ARegistry.Register(TUnconditionalRecursionRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Recursion', cTexts);

end.
