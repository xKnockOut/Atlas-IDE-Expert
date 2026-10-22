unit Atlas.Common.Rules.Builtin.Flow;

// Flussregeln (#269) auf dem Kontrollflussgraphen (#143):
//   result-not-set            Funktion kann enden, ohne Result zu setzen (wie W1035)
//   possibly-uninitialized    lokale Variable wird möglicherweise vor der ersten
//                             Zuweisung gelesen (wie W1036)
//   unreachable-code          Anweisung nach Exit, raise, Abort, goto … wird nie
//                             ausgeführt (#94); gemeldet wird nur die erste
//                             Anweisung eines unerreichbaren Abschnitts
//   use-after-free            nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X)
//                             oder Dispose(X) wird X ohne neue Zuweisung wieder
//                             benutzt (#915): X.Methode, X.Feld, X[…], X^, with X,
//                             nach Free auch Assigned(X) und ein zweites Free.
//                             Vom Freigabeknoten aus folgt die Regel dem Graphen;
//                             eine Zuweisung an X, die Übergabe von X an eine
//                             Routine, @X und nach FreeAndNil eine Abfrage auf nil
//                             (Assigned(X), X <> nil) beenden den Weg. Konfidenz
//                             hoch, wenn Freigabe und Zugriff im selben Block
//                             nacheinander stehen, sonst mittel. Die Aktion
//                             springt zur Freigabe.
//   deref-before-nil-check    X wird benutzt (X.Feld, X.Methode, X[…], X^) und
//                             erst danach mit Assigned(X), X <> nil oder X = nil
//                             geprüft (#916). Still, wenn vor dem Zugriff schon
//                             geprüft wurde, wenn X dazwischen neu gesetzt oder
//                             übergeben wird und bei Feldern und globalen
//                             Variablen nach jedem Aufruf dazwischen (er kann
//                             sie ändern). Steht die Prüfung als if ohne else
//                             direkt nach dem Zugriff im selben Block, zieht die
//                             Korrektur sie vor den Zugriff.
//   field-free-without-nil    FFeld.Free in einer Methode außerhalb des
//                             Destruktors, und ein Weg zum Ende der Methode
//                             setzt das Feld nicht neu (#917). Neu setzt eine
//                             Zuweisung oder der Aufruf einer Methode derselben
//                             Klasse, die das Feld zuweist. Felder sind die der
//                             Klassendeklaration in der Unit. Ausgenommen sind
//                             die Methoden aus ignoreMethods (Vorgabe Destroy,
//                             BeforeDestruction); Korrektur FreeAndNil(FFeld).
//   destructor-not-nil-safe   Der Destruktor (oder eine Methode, die nur er
//                             aufruft) benutzt ein Feld (FFeld.Clear), das ein
//                             Konstruktor erst nach Code anlegt, der eine
//                             Exception werfen kann, oder nur bedingt (#1087).
//                             Wirft der Konstruktor, ruft Delphi den Destruktor
//                             mit dem noch leeren Feld auf. Free, FreeAndNil,
//                             DisposeOf und Zugriffe nach Assigned(FFeld) bzw.
//                             FFeld <> nil sind sicher; BeforeDestruction läuft
//                             auf diesem Weg nicht. Mit onlyAfterRaisingCode
//                             aus zählt jedes im Konstruktor angelegte Feld.
//                             Korrektur: if Assigned(FFeld) then davor.
//   handle-leak               Ein Windows-Handle aus CreateFile, CreateEvent,
//                             OpenProcess, CreateProcess (hProcess, hThread),
//                             FindFirstFile, RegOpenKeyEx, LoadLibrary, GetDC,
//                             GDI-Objekten … in einer lokalen Variablen wird
//                             auf einem Weg zum Ende der Routine nicht mit dem
//                             passenden Gegenstück geschlossen (#1088). Die
//                             Paare stehen in BuiltinHandlePairs, eigene über
//                             die Option pairs. Zurückgeben, Speichern und
//                             Übergabe an unbekannte Routinen gelten als
//                             Weitergabe; Zweige, in denen das Öffnen laut
//                             if-Prüfung misslang, und Ausnahmewege
//                             (pair-without-finally) zählen nicht. Korrektur:
//                             die Anweisungen danach in try … finally mit dem
//                             Schließen einschließen.
//   out-param-read            out-Parameter wird gelesen, bevor die Routine ihn
//                             setzt (#924); bei verwalteten Typen hat ihn der
//                             Aufrufer schon geleert. Korrektur out -> var in
//                             Implementierung und Deklaration.
//
// Was der Graph nicht sieht, macht die Variable "unbekannt" und erzeugt keinen
// Treffer: Übergabe als Argument (var/out-Parameter, SetLength, FillChar,
// TryGetValue …), @X, Zuweisung an ein Feld oder Element (Result.Feld := …,
// Result[I] := …), with X do, inherited in Funktionen und die alte Zuweisung
// an den Funktionsnamen. Ist der Graph unvollständig (asm, Syntaxfehler),
// gibt es ebenfalls keinen Treffer.
//
// possibly-uninitialized prüft nur Variablen, die Delphi nicht selbst
// vorbelegt: einfache Typen (Konfidenz hoch) und T…-Typen wie Klassen und
// Records (Konfidenz mittel). string, Variant, Interfaces und dynamische
// Arrays sind verwaltet und werden übergangen.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TResultNotSetRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPossiblyUninitializedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnreachableCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUseAfterFreeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDerefBeforeNilCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFieldFreeWithoutNilRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option ignoreMethods.</summary>
    class function DefaultIgnoreMethods: TArray<string>; static;
  end;

  TDestructorNotNilSafeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THandleLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Paare "Öffnen|Ort|Schließen" aus der Tabelle und der Option pairs ("Öffnen>Schließen" oder
    /// {"open", "close"}).</summary>
    class function Pairs(const AOptions: string): TArray<string>; static;
  end;

  TOutParamReadRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  OutParamReadRuleId = 'out-param-read';
  UseAfterFreeRuleId = 'use-after-free';
  DerefBeforeNilCheckRuleId = 'deref-before-nil-check';
  FieldFreeWithoutNilRuleId = 'field-free-without-nil';
  DestructorNotNilSafeRuleId = 'destructor-not-nil-safe';
  HandleLeakRuleId = 'handle-leak';

/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived;

const
  SimpleTypes: array[0..23] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'ByteBool', 'WordBool', 'LongBool',
    'Char', 'AnsiChar', 'WideChar', 'Double', 'Single', 'Extended', 'Currency', 'Pointer');
  ManagedTypes: array[0..7] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant', 'TArray');

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Bezeichner, an dem eine Kette wie Result.Feld oder Result[I] hängt.</summary>
function RootName(ANode: TSyntaxNode): string;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
    ANode := ANode[0];
  if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
    Result := ANode.Name
  else
    Result := '';
end;

function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  Result := ABlock.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Index: Integer;
    begin
      Result := TSyntaxSearchStep.Descend;
      case ANode.Kind of
        // Lokale Routinen und anonyme Methoden laufen außerhalb dieses Flusses.
        TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
          Result := TSyntaxSearchStep.Skip;
        TSyntaxKind.Call:
          for Index := 1 to ANode.ChildCount - 1 do
            if IsName(ANode[Index], Name) then
              Result := TSyntaxSearchStep.Found;
        TSyntaxKind.AddressOf:
          if (ANode.ChildCount > 0) and SameText(RootName(ANode[0]), Name) then
            Result := TSyntaxSearchStep.Found;
        TSyntaxKind.AssignStatement:
          if (ANode.ChildCount > 0) and (ANode[0].Kind <> TSyntaxKind.Identifier) and
            SameText(RootName(ANode[0]), Name) then
            Result := TSyntaxSearchStep.Found;
        TSyntaxKind.WithStatement:
          for Index := 0 to ANode.ChildCount - 2 do
            if SameText(RootName(ANode[Index]), Name) then
              Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = Kind then
        Exit(TSyntaxSearchStep.Found);
      if AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Bereich des Routinennamens im Kopf; sonst der Kopf.</summary>
function HeaderNameRange(const AContext: TRuleContext; ARoutine: TSyntaxNode): TTextRange;
var
  Header: TSyntaxNode;
  Token: TPascalToken;
  Index: Integer;
  Name: string;
begin
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Header := ARoutine;
  Name := ShortName(ARoutine.Name);
  for Index := 0 to High(AContext.Tree.Tokens) do
  begin
    Token := AContext.Tree.Tokens[Index];
    if Token.Offset >= Header.EndOffset then
      Break;
    if (Token.Offset >= Header.StartOffset) and SameText(Token.Text, Name) then
      Exit(TTextRange.Create(Token.StartPos, Token.EndPos));
  end;
  Result := NodeRange(Header);
end;

{ TResultNotSetRule }

function TResultNotSetRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('result-not-set', TRuleSeverity.Warning,
    'Funktion kann enden, ohne Result zu setzen');
end;

procedure TResultNotSetRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Block: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Name: string;
begin
  if AContext.Tree = nil then
    Exit;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    // Nur Funktionen: der Kopf trägt einen Ergebnistyp.
    if (Header = nil) or (Header.FindChild(TSyntaxKind.TypeReference) = nil) then
      Continue;
    Block := Routine.FindChild(TSyntaxKind.Block);
    Name := ShortName(Routine.Name);
    if HasOpaqueUse(Block, 'Result') or HasOpaqueUse(Block, Name) or ContainsKind(Block, TSyntaxKind.InheritedExpr) then
      Continue;
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    // Alte Schreibweise: Zuweisung an den Funktionsnamen setzt ebenfalls das Ergebnis.
    if (Graph.MayEndWithout('Result') = TFlowAnswer.Yes) and (Graph.MayEndWithout(Name) = TFlowAnswer.Yes) then
      AReport.Add(HeaderNameRange(AContext, Routine),
        Format('"%s" kann enden, ohne Result zu setzen; der Rückgabewert ist dann undefiniert', [Name]),
        TRuleConfidence.High);
  end;
end;

{ TPossiblyUninitializedRule }

function TPossiblyUninitializedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('possibly-uninitialized', TRuleSeverity.Warning,
    'Variable wird möglicherweise vor der ersten Zuweisung gelesen');
end;

procedure TPossiblyUninitializedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Block, Section, Decl, TypeNode: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Index, Inner: Integer;
  Name, TypeName: string;
  Confidence: TRuleConfidence;
  Reported: Boolean;

  function FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
  begin
    Result := nil;
    while (ANode <> nil) and (Result = nil) do
    begin
      Result := Graph.NodeOf(ANode);
      ANode := ANode.Parent;
    end;
  end;

  // Erster Lesezugriff auf Name, der ohne vorherige Zuweisung erreichbar ist.
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
    Flow: TFlowNode;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1); die Kinder rückwärts darauf, damit der erste Treffer derselbe bleibt.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while not Reported and (Pending.Count > 0) do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          Continue;
        if IsName(Node, Name) and not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.AssignStatement) and
          (Node.Parent.ChildCount > 0) and (Node.Parent[0] = Node)) then
        begin
          Flow := FlowNodeOf(Node);
          if (Flow <> nil) and (Graph.IsReachable(Flow) = TFlowAnswer.Yes) and
            Graph.ReachingDefinitions(Flow, Name).FromEntry then
          begin
            AReport.Add(NodeRange(Node),
              Format('"%s" wird hier möglicherweise gelesen, bevor ein Wert zugewiesen wurde', [Name]), Confidence);
            Reported := True;
            Continue;
          end;
        end;
        for Child := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Child]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Block := Routine.FindChild(TSyntaxKind.Block);
    Graph := nil;
    for Index := 0 to Routine.ChildCount - 1 do
    begin
      Section := Routine[Index];
      if Section.Kind <> TSyntaxKind.VarSection then
        Continue;
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        Decl := Section[Inner];
        TypeNode := Decl.FindChild(TSyntaxKind.TypeReference);
        // var X: Integer = 0 ist vorbelegt; nur einfache Deklarationen mit Typverweis.
        if (Decl.Kind <> TSyntaxKind.VarDecl) or (TypeNode = nil) or (Decl.ChildCount <> 1) or
          (TypeNode.FindChild(TSyntaxKind.GenericArgs) <> nil) then
          Continue;
        TypeName := TypeNode.Name;
        if MatchText(TypeName, SimpleTypes) then
          Confidence := TRuleConfidence.High
        else if StartsText('T', TypeName) and (Length(TypeName) > 1) and not MatchText(TypeName, ManagedTypes) then
          Confidence := TRuleConfidence.Medium
        else
          Continue;
        for Name in Decl.Name.Split([',']) do
        begin
          if HasOpaqueUse(Block, Name.Trim) then
            Continue;
          if Graph = nil then
            Graph := TRuleDerived.Graph(Cache, AContext, Routine);
          if not Graph.Complete then
            Break;
          Reported := False;
          Visit(Block);
        end;
      end;
    end;
  end;
end;

{ TUnreachableCodeRule }

function TUnreachableCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unreachable-code', TRuleSeverity.Warning, 'Anweisung wird nie ausgeführt');
end;

/// <summary>Bereich der ersten Zeile von ANode; mehrzeilige Anweisungen werden nicht ganz markiert.</summary>
function FirstLineRange(const AContext: TRuleContext; ANode: TSyntaxNode): TTextRange;
var
  Token: TPascalToken;
  Last: TTextPosition;
begin
  Last := ANode.EndPos;
  if Last.Line <> ANode.StartPos.Line then
  begin
    Last := ANode.StartPos;
    for Token in AContext.Tree.Tokens do
    begin
      if Token.Offset >= ANode.EndOffset then
        Break;
      if (Token.Offset >= ANode.StartOffset) and (Token.StartPos.Line = ANode.StartPos.Line) and
        (Token.Kind <> TPascalTokenKind.Comment) then
        Last := Token.EndPos;
    end;
  end;
  Result := TTextRange.Create(ANode.StartPos, Last);
end;

procedure TUnreachableCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Dead: TArray<TSyntaxNode>;
  Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Unreachable: TArray<TFlowNode>;
  Node: TFlowNode;

  function IsDead(ANode: TSyntaxNode): Boolean;
  var
    Item: TSyntaxNode;
  begin
    for Item in Dead do
      if Item = ANode then
        Exit(True);
    Result := False;
  end;

  // Liegt eine unerreichbare Anweisung in ANode (oder ist es ANode selbst)? Iterativ (Bericht M1): von den
  // unerreichbaren Anweisungen aufwärts statt rekursiv durch ANode.
  function HasDead(ANode: TSyntaxNode): Boolean;
  var
    Item, Current: TSyntaxNode;
  begin
    for Item in Dead do
    begin
      Current := Item;
      while Current <> nil do
      begin
        if Current = ANode then
          Exit(True);
        Current := Current.Parent;
      end;
    end;
    Result := False;
  end;

  // Erste Anweisung eines unerreichbaren Abschnitts: nicht in einer anderen
  // unerreichbaren Anweisung enthalten, und davor steht (auf der ersten Ebene,
  // die einen Vorgänger hat) erreichbarer Code.
  function StartsDeadRun(AStatement: TSyntaxNode): Boolean;
  var
    Current, Parent: TSyntaxNode;
    Index: Integer;
  begin
    Current := AStatement.Parent;
    while (Current <> nil) and (Current <> Routine) do
    begin
      if IsDead(Current) then
        Exit(False);
      Current := Current.Parent;
    end;
    Current := AStatement;
    while (Current <> Routine) and (Current.Parent <> nil) do
    begin
      Parent := Current.Parent;
      for Index := 1 to Parent.ChildCount - 1 do
        if Parent[Index] = Current then
          Exit(not HasDead(Parent[Index - 1]));
      Current := Parent;
    end;
    Result := True;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    Unreachable := Graph.UnreachableStatements;
    Dead := nil;
    for Node in Unreachable do
      if Node.Syntax <> nil then
        Dead := Dead + [Node.Syntax];
    for Node in Unreachable do
      if (Node.Syntax <> nil) and StartsDeadRun(Node.Syntax) then
        AReport.Add(FirstLineRange(AContext, Node.Syntax), 'Diese Anweisung wird nie ausgeführt',
          TRuleConfidence.High);
  end;
end;

const
  /// <summary>Anweisungen und ihre Teile; ein Knoten des Graphen wertet sie nicht selbst aus.</summary>
  FlowStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem,
    TSyntaxKind.CaseElse, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock,
    TSyntaxKind.ExceptionHandler, TSyntaxKind.FinallyBlock, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];

{ TUseAfterFreeRule }

function TUseAfterFreeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UseAfterFreeRuleId, TRuleSeverity.Error, 'Objekt nach Free weiter benutzt');
end;

/// <summary>Name einer Variablen oder eines Feldes (X oder Self.X); sonst ''.</summary>
function FreedPath(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and IsName(ANode[0], 'Self') then
    Result := ANode.Name;
  if SameText(Result, 'Self') or SameText(Result, 'inherited') then
    Result := '';
end;

/// <summary>Gibt die Anweisung AStatement X frei? AToNil bei FreeAndNil.</summary>
function FreedBy(AStatement: TSyntaxNode; out APath: string; out AToNil: Boolean): Boolean;
var
  Callee, Target: TSyntaxNode;
begin
  Result := False;
  APath := '';
  AToNil := False;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
    Exit;
  Callee := AStatement[0];
  Target := nil;
  // X.Free; bzw. X.Free();
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 1) then
    Callee := Callee[0];
  if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and
    MatchText(Callee.Name, ['Free', 'Destroy', 'DisposeOf']) then
    Target := Callee[0]
  else if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 2) and (Callee[0].Kind = TSyntaxKind.Identifier) and
    MatchText(Callee[0].Name, ['FreeAndNil', 'Dispose']) then
  begin
    Target := Callee[1];
    AToNil := SameText(Callee[0].Name, 'FreeAndNil');
  end;
  APath := FreedPath(Target);
  Result := APath <> '';
end;

procedure TUseAfterFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Node: TFlowNode;
  Reported: TArray<Integer>;
  Path: string;
  ToNil: Boolean;

  function AlreadyReported(AOffset: Integer): Boolean;
  var
    Offset: Integer;
  begin
    for Offset in Reported do
      if Offset = AOffset then
        Exit(True);
    Result := False;
  end;

  // Zugriffe auf APath im eigenen Teil der Anweisung bzw. Bedingung ASyntax; AStops: der Weg endet hier.
  procedure Inspect(ASyntax: TSyntaxNode; const APath: string; AToNil: Boolean; var AUses: TArray<TSyntaxNode>;
    var AStops, AGuarded: Boolean);

    procedure Visit(ARoot: TSyntaxNode);
    var
      Index, First: Integer;
      E, Callee: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          E := Pending.Pop;
          if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
            Continue;
          // Ab diesem Kind weiter absteigen; nach einem Zugriff X.… nicht mehr in X selbst.
          First := 0;
          case E.Kind of
            TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference:
              if (E.ChildCount > 0) and SameText(FreedPath(E[0]), APath) then
              begin
                // Nach FreeAndNil ist ein weiteres Free harmlos.
                if not (AToNil and (E.Kind = TSyntaxKind.MemberAccess) and SameText(E.Name, 'Free')) then
                  AUses := AUses + [E[0]];
                First := 1;
              end;
            TSyntaxKind.Call:
              begin
                Callee := nil;
                if E.ChildCount > 0 then
                  Callee := E[0];
                for Index := 1 to E.ChildCount - 1 do
                  if SameText(FreedPath(E[Index]), APath) then
                  begin
                    if (Callee <> nil) and (Callee.Kind = TSyntaxKind.Identifier) and
                      MatchText(Callee.Name, ['Assigned', 'FreeAndNil']) and not AToNil then
                      // Nach Free: Assigned(X) ist immer True, FreeAndNil(X) gibt doppelt frei.
                      AUses := AUses + [E[Index]]
                    else if (Callee <> nil) and (Callee.Kind = TSyntaxKind.Identifier) and
                      SameText(Callee.Name, 'Assigned') then
                      AGuarded := True
                    else
                      // Übergabe: die Routine kann X neu setzen oder nur vergleichen (List.Remove(X)).
                      AStops := True;
                  end;
              end;
            TSyntaxKind.AddressOf:
              if (E.ChildCount > 0) and SameText(FreedPath(E[0]), APath) then
              begin
                AStops := True;
                Continue;
              end;
            TSyntaxKind.BinaryExpr:
              // X = nil, X <> nil: eine Abfrage, die den Weg trennt.
              for Index := 0 to E.ChildCount - 1 do
                if SameText(FreedPath(E[Index]), APath) then
                  AGuarded := True;
          end;
          for Index := E.ChildCount - 1 downto First do
            Pending.Push(E[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

  var
    Index: Integer;
    Child: TSyntaxNode;
    AllChildren: Boolean;
  begin
    AllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
      TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
    for Index := 0 to ASyntax.ChildCount - 1 do
    begin
      Child := ASyntax[Index];
      if not AllChildren and (Child.Kind in FlowStatementKinds) then
        Continue;
      if (Index = 0) and (ASyntax.Kind = TSyntaxKind.AssignStatement) and SameText(FreedPath(Child), APath) then
      begin
        AStops := True;
        Continue;
      end;
      if (ASyntax.Kind = TSyntaxKind.WithStatement) and SameText(FreedPath(Child), APath) then
      begin
        AUses := AUses + [Child];
        Continue;
      end;
      Visit(Child);
    end;
  end;

  procedure Follow(AFree: TFlowNode; const APath: string; AToNil: Boolean);
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current, Next: TFlowNode;
    Accesses: TArray<TSyntaxNode>;
    Access: TSyntaxNode;
    Stops, Guarded: Boolean;
    Confidence: TRuleConfidence;
    FreeLine: Integer;
    Message: string;
  begin
    SetLength(Visited, Graph.Nodes.Count);
    // Wege nur über eine mögliche Ausnahme (die Anweisung wirkt dann nicht) bleiben aus: lieber zu wenig.
    Queue := nil;
    for Next in AFree.Successors do
      if not AFree.IsImplicitRaiseEdge(Next) then
        Queue := Queue + [Next];
    FreeLine := AFree.Syntax.StartPos.Line;
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] then
        Continue;
      Visited[Current.Index] := True;
      // for und for … in weisen der Schleifenvariablen in jedem Durchlauf neu zu.
      Stops := SameText(Current.Defines, APath) or ((Current.Kind = TFlowNodeKind.Condition) and
        (Current.Syntax.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
        SameText(Current.Syntax.Name, APath));
      Guarded := False;
      Accesses := nil;
      if (Current.Syntax <> nil) and not Stops then
        Inspect(Current.Syntax, APath, AToNil, Accesses, Stops, Guarded);
      if Guarded and AToNil then
        Continue;
      for Access in Accesses do
      begin
        if AlreadyReported(Access.StartOffset) then
          Continue;
        Reported := Reported + [Access.StartOffset];
        // Im selben Block nacheinander: der Zugriff folgt sicher auf die Freigabe.
        Confidence := TRuleConfidence.Medium;
        if (Current.Syntax.Parent = AFree.Syntax.Parent) and (Current.Syntax.StartOffset > AFree.Syntax.StartOffset)
          then
          Confidence := TRuleConfidence.High;
        if AToNil then
          Message := Format('%s wurde in Zeile %d mit FreeAndNil freigegeben und ist hier nil.',
            [APath, FreeLine + 1])
        else
          Message := Format('%s wurde in Zeile %d freigegeben und wird hier wieder gelesen.', [APath, FreeLine + 1]);
        AReport.Add(NodeRange(Access), Message, Confidence,
          [TRuleFix.Jump(Format('Zur Freigabe in Zeile %d springen', [FreeLine + 1]), AFree.Syntax.StartPos)]);
      end;
      if Stops or Guarded then
        Continue;
      for Next in Current.Successors do
        if not Visited[Next.Index] and not Current.IsImplicitRaiseEdge(Next) then
          Queue := Queue + [Next];
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Reported := nil;
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    for Node in Graph.Nodes do
      if (Node.Kind = TFlowNodeKind.Statement) and FreedBy(Node.Syntax, Path, ToNil) then
        Follow(Node, Path, ToNil);
  end;
end;

{ TDerefBeforeNilCheckRule }

function TDerefBeforeNilCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DerefBeforeNilCheckRuleId, TRuleSeverity.Warning,
    'Erst benutzt, dann auf nil geprüft');
end;

/// <summary>Ausdrücke, die ein Knoten des Graphen selbst auswertet: bei einfachen Anweisungen alle Kinder,
/// bei if, while, for, case und with nur die Bedingung bzw. den Kopf.</summary>
function OwnParts(ASyntax: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
  AllChildren: Boolean;
begin
  Result := nil;
  if ASyntax = nil then
    Exit;
  AllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
  for Index := 0 to ASyntax.ChildCount - 1 do
    if AllChildren or not (ASyntax[Index].Kind in FlowStatementKinds) then
      Result := Result + [ASyntax[Index]];
end;

/// <summary>Enthält E Assigned(APath), APath = nil oder APath <> nil?</summary>
function ContainsNilCheck(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  Index: Integer;
  E: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      E := Pending.Pop;
      if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        Continue;
      if (E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and IsName(E[0], 'Assigned') and
        SameText(FreedPath(E[1]), APath) then
        Exit(True);
      if (E.Kind = TSyntaxKind.BinaryExpr) and MatchText(E.Name, ['=', '<>']) and (E.ChildCount = 2) and
        ((SameText(FreedPath(E[0]), APath) and (E[1].Kind = TSyntaxKind.Literal) and SameText(E[1].Name, 'nil')) or
        (SameText(FreedPath(E[1]), APath) and (E[0].Kind = TSyntaxKind.Literal) and SameText(E[0].Name, 'nil'))) then
        Exit(True);
      for Index := E.ChildCount - 1 downto 0 do
        Pending.Push(E[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Wurzeln der Zugriffe X.… und X^ in E, in Textreihenfolge. X[…] zählt nicht: bei dynamischen
/// Arrays ist X <> nil die übliche Abfrage auf leer.</summary>
procedure CollectDerefs(ARoot: TSyntaxNode; var AList: TArray<TSyntaxNode>);
var
  Index: Integer;
  E: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      E := Pending.Pop;
      if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        Continue;
      if (E.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference]) and (E.ChildCount > 0) and
        (FreedPath(E[0]) <> '') then
        AList := AList + [E[0]];
      for Index := E.ChildCount - 1 downto 0 do
        Pending.Push(E[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Weist der Knoten APath sicher einen Wert zu (Zuweisung, Schleifenvariable)?</summary>
function AssignsPath(ANode: TFlowNode; const APath: string): Boolean;
var
  S: TSyntaxNode;
begin
  S := ANode.Syntax;
  Result := SameText(ANode.Defines, APath);
  if Result or (S = nil) then
    Exit;
  if (ANode.Kind = TFlowNodeKind.Condition) and (S.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
    SameText(S.Name, APath) then
    Exit(True);
  Result := (S.Kind = TSyntaxKind.AssignStatement) and (S.ChildCount > 0) and SameText(FreedPath(S[0]), APath);
end;

/// <summary>Kann der Knoten APath ändern? Zuweisung, Schleifenvariable, Übergabe als Argument, @X; bei
/// Feldern und globalen Variablen (ALocal = False) jeder Aufruf.</summary>
function ChangesPath(ANode: TFlowNode; const APath: string; ALocal: Boolean): Boolean;

  function Visit(ARoot: TSyntaxNode): Boolean;
  var
    Index: Integer;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
          Continue;
        if (E.Kind = TSyntaxKind.Call) and (E.ChildCount > 0) and not IsName(E[0], 'Assigned') then
        begin
          if not ALocal then
            Exit(True);
          for Index := 1 to E.ChildCount - 1 do
            if SameText(FreedPath(E[Index]), APath) then
              Exit(True);
        end;
        if (E.Kind = TSyntaxKind.AddressOf) and (E.ChildCount > 0) and SameText(FreedPath(E[0]), APath) then
          Exit(True);
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  S, Part: TSyntaxNode;
begin
  S := ANode.Syntax;
  Result := AssignsPath(ANode, APath);
  if Result or (S = nil) then
    Exit;
  // X.Methode ohne Klammern ist ein Aufruf.
  if not ALocal and (S.Kind = TSyntaxKind.CallStatement) then
    Exit(True);
  for Part in OwnParts(S) do
    if Visit(Part) then
      Exit(True);
end;

function NodeHasNilCheck(ANode: TFlowNode; const APath: string): Boolean;
var
  Part: TSyntaxNode;
begin
  Result := False;
  for Part in OwnParts(ANode.Syntax) do
    if ContainsNilCheck(Part, APath) then
      Exit(True);
end;

/// <summary>Weist eine Anweisung unter ANode APath zu?</summary>
function SubtreeAssigns(ANode: TSyntaxNode; const APath: string): Boolean;
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
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) and
        SameText(FreedPath(Node[0]), APath) then
        Exit(True);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Parameter, lokale Variablen und Inline-Variablen der Routine (ohne lokale Routinen).</summary>
function LocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
  E: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoutine);
    while Pending.Count > 0 do
    begin
      E := Pending.Pop;
      if (E <> ARoutine) and (E.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
        Continue;
      if E.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
        for Name in E.Name.Split([',']) do
          Result := Result + [Trim(Name)];
      for Index := E.ChildCount - 1 downto 0 do
        Pending.Push(E[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

procedure TDerefBeforeNilCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Node, CheckNode: TFlowNode;
  Locals, Checked, Done: TArray<string>;
  Derefs: TArray<TSyntaxNode>;
  Deref, Part: TSyntaxNode;
  Path, Key: string;
  LineBreak: string;

  function Contains(const AList: TArray<string>; const AName: string): Boolean;
  var
    Item: string;
  begin
    for Item in AList do
      if SameText(Item, AName) then
        Exit(True);
    Result := False;
  end;

  // Pfade, die die Routine irgendwo auf nil prüft; nur diese lohnen die Suche.
  procedure CollectChecked(ARoot: TSyntaxNode);
  var
    Index: Integer;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if (E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and IsName(E[0], 'Assigned') and
          (FreedPath(E[1]) <> '') and not Contains(Checked, FreedPath(E[1])) then
          Checked := Checked + [FreedPath(E[1])];
        if (E.Kind = TSyntaxKind.BinaryExpr) and (E.ChildCount = 2) then
          for Index := 0 to 1 do
            if (FreedPath(E[Index]) <> '') and (E[1 - Index].Kind = TSyntaxKind.Literal) and
              SameText(E[1 - Index].Name, 'nil') and not Contains(Checked, FreedPath(E[Index])) then
              Checked := Checked + [FreedPath(E[Index])];
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Wird APath auf einem Weg zu ANode schon geprüft (ohne Zuweisung dazwischen)? Rückwärts beenden nur sichere
  // Zuweisungen den Weg: lieber eine Prüfung zu viel finden.
  function CheckedBefore(ANode: TFlowNode; const APath: string): Boolean;
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current, Prev: TFlowNode;
  begin
    Result := False;
    SetLength(Visited, Graph.Nodes.Count);
    Queue := ANode.Predecessors.ToArray;
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] then
        Continue;
      Visited[Current.Index] := True;
      if (Current.Syntax <> nil) and NodeHasNilCheck(Current, APath) then
        Exit(True);
      if AssignsPath(Current, APath) then
        Continue;
      for Prev in Current.Predecessors do
        if not Visited[Prev.Index] then
          Queue := Queue + [Prev];
    end;
  end;

  // Erste Prüfung von APath nach ANode ohne Änderung dazwischen; nil ohne.
  function CheckAfter(ANode: TFlowNode; const APath: string; ALocal: Boolean): TFlowNode;
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current, Next: TFlowNode;
  begin
    Result := nil;
    SetLength(Visited, Graph.Nodes.Count);
    Queue := nil;
    for Next in ANode.Successors do
      if not ANode.IsImplicitRaiseEdge(Next) then
        Queue := Queue + [Next];
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] or (Current = ANode) then
        Continue;
      Visited[Current.Index] := True;
      if (Current.Syntax <> nil) and NodeHasNilCheck(Current, APath) then
        Exit(Current);
      if ChangesPath(Current, APath, ALocal) then
        Continue;
      for Next in Current.Successors do
        if not Visited[Next.Index] and not Current.IsImplicitRaiseEdge(Next) then
          Queue := Queue + [Next];
    end;
  end;

  function Source(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Einrückung vor ANode; False, wenn davor in der Zeile noch Code steht.
  function Indent(ANode: TSyntaxNode; out AIndent: string): Boolean;
  var
    Start: Integer;
  begin
    Start := ANode.StartOffset;
    while (Start > 0) and CharInSet(AContext.Text[Start], [' ', #9]) do
      Dec(Start);
    AIndent := Copy(AContext.Text, Start + 1, ANode.StartOffset - Start);
    Result := (Start = 0) or CharInSet(AContext.Text[Start], [#10, #13]);
  end;

  // Zeilen von AText mit AIndent davor; führende und folgende Leerzeilen fallen weg.
  function Reindented(const AText, AIndent: string): string;
  var
    Line: string;
    Lines: TArray<string>;
    Index: Integer;
  begin
    Result := '';
    Lines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    for Index := 0 to High(Lines) do
    begin
      Line := Lines[Index];
      if Trim(Line) = '' then
        Continue;
      Result := Result + AIndent + Line + LineBreak;
    end;
  end;

  // Prüfung als if ohne else direkt nach dem Zugriff im selben Block: if … then begin Zugriff; Rumpf end.
  function MoveCheckFix(AAccess: TFlowNode; ACheck: TFlowNode; out AFix: TRuleFix): Boolean;
  var
    Access, IfNode, Parent, Body, Condition: TSyntaxNode;
    Position, Index: Integer;
    Outer, Inner, Text, BodyText: string;
  begin
    Result := False;
    Access := AAccess.Syntax;
    IfNode := ACheck.Syntax;
    if (AAccess.Kind <> TFlowNodeKind.Statement) or (ACheck.Kind <> TFlowNodeKind.Condition) or
      (IfNode.Kind <> TSyntaxKind.IfStatement) or (Access.Parent = nil) or (Access.Parent <> IfNode.Parent) then
      Exit;
    Parent := Access.Parent;
    Position := -1;
    for Index := 0 to Parent.ChildCount - 1 do
      if Parent[Index] = Access then
        Position := Index;
    if (Position < 0) or (Position + 1 >= Parent.ChildCount) or (Parent[Position + 1] <> IfNode) then
      Exit;
    // if Bedingung then Rumpf, ohne else.
    Condition := nil;
    Body := nil;
    for Index := 0 to IfNode.ChildCount - 1 do
      if IfNode[Index].Kind in FlowStatementKinds then
      begin
        if Body <> nil then
          Exit;
        Body := IfNode[Index];
      end
      else if Condition = nil then
        Condition := IfNode[Index];
    if (Condition = nil) or (Body = nil) then
      Exit;
    if not Indent(Access, Outer) then
      Exit;
    Inner := Outer + '  ';
    if Body.Kind = TSyntaxKind.Block then
    begin
      BodyText := Source(Body);
      // begin … end abschneiden; die Zeilen behalten ihre Einrückung.
      BodyText := Copy(BodyText, 6, Length(BodyText) - 8);
      BodyText := Reindented(BodyText, '');
    end
    else
      BodyText := Inner + Trim(Source(Body)) + ';' + LineBreak;
    Text := 'if ' + Trim(Source(Condition)) + ' then' + LineBreak + Outer + 'begin' + LineBreak +
      Inner + Trim(Source(Access)) + ';' + LineBreak + BodyText + Outer + 'end';
    AFix := TRuleFix.Create('Prüfung vor den Zugriff ziehen',
      [TRuleEdit.Create(TTextRange.Create(Access.StartPos, IfNode.EndPos), Text)]);
    Result := True;
  end;

var
  Fix: TRuleFix;
  Fixes: TArray<TRuleFix>;
  IsLocal: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
    LineBreak := #13#10;
  Cache := TRuleDerived.Open(AContext);
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    Checked := nil;
    CollectChecked(Routine);
    if Checked = nil then
      Continue;
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    Locals := LocalNames(Routine);
    Done := nil;
    for Node in Graph.Nodes do
    begin
      if (Node.Syntax = nil) or not (Node.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) then
        Continue;
      Derefs := nil;
      for Part in OwnParts(Node.Syntax) do
        CollectDerefs(Part, Derefs);
      for Deref in Derefs do
      begin
        Path := FreedPath(Deref);
        if not Contains(Checked, Path) or NodeHasNilCheck(Node, Path) then
          Continue;
        IsLocal := Contains(Locals, Path);
        // X := X.Next: die spätere Prüfung gilt dem neuen Wert. Ebenso Supports(Y, IX, X) and X.Foo: die
        // Übergabe im selben Ausdruck setzt X erst.
        if ChangesPath(Node, Path, True) then
          Continue;
        CheckNode := CheckAfter(Node, Path, IsLocal);
        // Eine Prüfung weiter oben, die erst der nächste Schleifendurchlauf erreicht, schützt den Zugriff.
        if (CheckNode = nil) or (CheckNode.Syntax.StartOffset < Node.Syntax.StartOffset) then
          Continue;
        // Nur wenn jeder Weg zur Prüfung durch den Zugriff führt; sonst gilt sie den anderen Wegen
        // (X := TX.Create; X.Init; … if X <> nil nach einem Zweig ohne Create).
        if Graph.Dominates(Node, CheckNode) <> TFlowAnswer.Yes then
          Continue;
        // while X <> nil do … X := X.Parent: die Bedingung gilt den späteren Durchläufen.
        if (CheckNode.Syntax.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and
          SubtreeAssigns(CheckNode.Syntax, Path) then
          Continue;
        Key := LowerCase(Path) + '@' + IntToStr(CheckNode.Index);
        if Contains(Done, Key) or CheckedBefore(Node, Path) then
          Continue;
        Done := Done + [Key];
        Fixes := nil;
        if MoveCheckFix(Node, CheckNode, Fix) then
          Fixes := [Fix];
        AReport.Add(NodeRange(Deref), Format('%s wird hier benutzt, aber erst in Zeile %d auf nil geprüft.',
          [Path, CheckNode.Syntax.StartPos.Line + 1]), TRuleConfidence.Medium, Fixes);
      end;
    end;
  end;
end;

{ TFieldFreeWithoutNilRule }

function TFieldFreeWithoutNilRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FieldFreeWithoutNilRuleId, TRuleSeverity.Warning,
    'Feld freigegeben, Verweis bleibt stehen');
end;

class function TFieldFreeWithoutNilRule.DefaultIgnoreMethods: TArray<string>;
begin
  Result := ['Destroy', 'BeforeDestruction'];
end;

/// <summary>Deklaration der Klasse AClassName (letzter Namensteil) unter ARoot; nil ohne.</summary>
function FindClassType(ARoot: TSyntaxNode; const AClassName: string): TSyntaxNode;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AClassName) then
      begin
        // Ohne class-Teil (z. B. Vorwärtsdeklaration eines anderen Typs) weitersuchen.
        Result := Node.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
          Exit;
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
        if not (Node[Index].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.ImplementationSection]) then
          Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Felder der Klassendeklaration AClass (ohne verschachtelte Typen).</summary>
function ClassFields(AClass: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
  E: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  if AClass = nil then
    Exit;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(AClass);
    while Pending.Count > 0 do
    begin
      E := Pending.Pop;
      if E.Kind = TSyntaxKind.Field then
        for Name in E.Name.Split([',']) do
          Result := Result + [Trim(Name)];
      for Index := E.ChildCount - 1 downto 0 do
        if E[Index].Kind <> TSyntaxKind.TypeSection then
          Pending.Push(E[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Methoden der Klassendeklaration AClass mit [TearDown] oder [TearDownFixture] (DUnitX).</summary>
function TearDownMethods(AClass: TSyntaxNode): TArray<string>;

  procedure Visit(E: TSyntaxNode);
  var
    Index: Integer;
    Pending: Boolean;
  begin
    Pending := False;
    for Index := 0 to E.ChildCount - 1 do
      if E[Index].Kind = TSyntaxKind.Attribute then
        Pending := Pending or MatchText(E[Index].Name, ['TearDown', 'TearDownFixture'])
      else
      begin
        if Pending and (E[Index].Name <> '') then
          Result := Result + [E[Index].Name];
        Pending := False;
        if E[Index].Kind = TSyntaxKind.Visibility then
          Visit(E[Index]);
      end;
  end;

begin
  Result := nil;
  if AClass <> nil then
    Visit(AClass);
end;

procedure TFieldFreeWithoutNilRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Routines: TArray<TSyntaxNode>;
  Routine, Target, Callee: TSyntaxNode;
  Graph: TControlFlowGraph;
  Node: TFlowNode;
  Ignore, Fields, Locals, TearDowns: TArray<string>;
  QualifiedClass, ClassName, Path: string;
  Dot: Integer;

  function Contains(const AList: TArray<string>; const AName: string): Boolean;
  var
    Item: string;
  begin
    for Item in AList do
      if SameText(Item, AName) then
        Exit(True);
    Result := False;
  end;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function MethodOf(ARoutine: TSyntaxNode): string;
  begin
    Result := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
  end;

  // Destruktor, Methode aus ignoreMethods oder mit [TearDown].
  function Releasing(ARoutine: TSyntaxNode): Boolean;
  begin
    Result := MatchText(MethodOf(ARoutine), Ignore) or StartsText('destructor', Trim(Text(ARoutine))) or
      Contains(TearDowns, MethodOf(ARoutine));
  end;

  // Ruft ARoutine die Methode AName auf (AName; AName(…); Self.AName)?
  function Calls(ARoutine: TSyntaxNode; const AName: string): Boolean;

    function Visit(ARoot: TSyntaxNode): Boolean;
    var
      Index: Integer;
      E: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Result := False;
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          E := Pending.Pop;
          if ((E.Kind = TSyntaxKind.CallStatement) and (E.ChildCount > 0) and SameText(FreedPath(E[0]), AName)) or
            ((E.Kind = TSyntaxKind.Call) and (E.ChildCount > 0) and SameText(FreedPath(E[0]), AName)) then
            Exit(True);
          for Index := E.ChildCount - 1 downto 0 do
            Pending.Push(E[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Result := Visit(ARoutine);
  end;

  // Wird die Methode nur aus freigebenden Methoden der Klasse aufgerufen (FreeFeatures aus Destroy)?
  function OnlyCalledWhileReleasing(ARoutine: TSyntaxNode): Boolean;
  var
    Other: TSyntaxNode;
    Callers: Integer;
  begin
    Callers := 0;
    for Other in Routines do
      if (Other <> ARoutine) and Calls(Other, MethodOf(ARoutine)) then
      begin
        if not StartsText(QualifiedClass + '.', Other.Name) or not Releasing(Other) then
          Exit(False);
        Inc(Callers);
      end;
    Result := Callers > 0;
  end;

  // Methode derselben Klasse, die APath zuweist.
  function AssignerMethod(const AName, APath: string): Boolean;
  var
    Other: TSyntaxNode;
  begin
    for Other in Routines do
      if SameText(Other.Name, QualifiedClass + '.' + AName) and SubtreeAssigns(Other, APath) then
        Exit(True);
    Result := False;
  end;

  // Ruft der Knoten eine Methode der Klasse auf, die APath neu setzt (Laden; Self.Laden; Laden(…))?
  function CallsAssigner(ANode: TFlowNode; const APath: string): Boolean;

    function Visit(ARoot: TSyntaxNode): Boolean;
    var
      Index: Integer;
      Name: string;
      E: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Result := False;
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          E := Pending.Pop;
          Name := '';
          if (E.Kind = TSyntaxKind.Call) and (E.ChildCount > 0) then
            Name := FreedPath(E[0]);
          if (Name <> '') and AssignerMethod(Name, APath) then
            Exit(True);
          for Index := E.ChildCount - 1 downto 0 do
            Pending.Push(E[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

  var
    Part: TSyntaxNode;
  begin
    Result := False;
    if ANode.Syntax = nil then
      Exit;
    // Aufruf ohne Klammern: "Laden;" bzw. "Self.Laden;".
    if (ANode.Syntax.Kind = TSyntaxKind.CallStatement) and (ANode.Syntax.ChildCount > 0) and
      (FreedPath(ANode.Syntax[0]) <> '') and AssignerMethod(FreedPath(ANode.Syntax[0]), APath) then
      Exit(True);
    for Part in OwnParts(ANode.Syntax) do
      if Visit(Part) then
        Exit(True);
  end;

  // Erreicht ein Weg vom Free das normale Ende der Methode, ohne das Feld neu zu setzen?
  function ReachesEnd(AFree: TFlowNode; const APath: string): Boolean;
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current, Next: TFlowNode;
  begin
    Result := False;
    SetLength(Visited, Graph.Nodes.Count);
    Queue := nil;
    for Next in AFree.Successors do
      if not AFree.IsImplicitRaiseEdge(Next) then
        Queue := Queue + [Next];
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] or (Current = AFree) then
        Continue;
      Visited[Current.Index] := True;
      if Current = Graph.ExitNode then
        Exit(True);
      if AssignsPath(Current, APath) or CallsAssigner(Current, APath) then
        Continue;
      for Next in Current.Successors do
        if not Visited[Next.Index] and not Current.IsImplicitRaiseEdge(Next) then
          Queue := Queue + [Next];
    end;
  end;

  // X.Free bzw. X.Free(); liefert X.
  function FreeTarget(AStatement: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
      Exit;
    Callee := AStatement[0];
    if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 1) then
      Callee := Callee[0];
    if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and SameText(Callee.Name, 'Free') then
      Result := Callee[0];
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Ignore := TRuleOptions.Strings(AContext.Options, 'ignoreMethods', DefaultIgnoreMethods);
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Dot := LastDelimiter('.', Routine.Name);
    if Dot = 0 then
      Continue;
    QualifiedClass := Copy(Routine.Name, 1, Dot - 1);
    ClassName := Copy(QualifiedClass, LastDelimiter('.', QualifiedClass) + 1, MaxInt);
    // TStapel<T>.Ablegen: die Deklaration heißt TStapel.
    if Pos('<', ClassName) > 0 then
      ClassName := Copy(ClassName, 1, Pos('<', ClassName) - 1);
    Fields := ClassFields(FindClassType(AContext.Tree.Root, ClassName));
    if Fields = nil then
      Continue;
    TearDowns := TearDownMethods(FindClassType(AContext.Tree.Root, ClassName));
    if Releasing(Routine) or OnlyCalledWhileReleasing(Routine) then
      Continue;
    Locals := LocalNames(Routine);
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    for Node in Graph.Nodes do
    begin
      if Node.Kind <> TFlowNodeKind.Statement then
        Continue;
      Target := FreeTarget(Node.Syntax);
      Path := FreedPath(Target);
      if (Path = '') or Contains(Locals, Path) or not Contains(Fields, Path) or not ReachesEnd(Node, Path) then
        Continue;
      AReport.Add(NodeRange(Node.Syntax), Format('%s bleibt nach Free gesetzt; ein späterer Zugriff trifft ' +
        'freigegebenen Speicher.', [Path]), TRuleConfidence.Medium,
        [TRuleFix.Create(Format('FreeAndNil(%s)', [Text(Target)]),
        [TRuleEdit.Create(NodeRange(Node.Syntax), Format('FreeAndNil(%s)', [Text(Target)]))])]);
    end;
  end;
end;

{ TDestructorNotNilSafeRule }

function TDestructorNotNilSafeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DestructorNotNilSafeRuleId, TRuleSeverity.Warning,
    'Destruktor benutzt ein Feld, das nach einer Exception im Konstruktor nil ist');
end;

const
  /// <summary>Klassen der RTL, deren Konstruktor ohne Argumente höchstens EOutOfMemory wirft; danach gilt
  /// ohnehin nichts mehr.</summary>
  QuietConstructions: array[0..21] of string = ('TObject', 'TInterfacedObject', 'TPersistent', 'TList',
    'TObjectList', 'TDictionary', 'TObjectDictionary', 'TStringList', 'TQueue', 'TObjectQueue', 'TStack',
    'TObjectStack', 'THashSet', 'TMemoryStream', 'TStringBuilder', 'TCriticalSection', 'TMultiReadExclusiveWriteSynchronizer',
    'TBits', 'TThreadList', 'TInterfaceList', 'TStringStream', 'TBytesStream');
  /// <summary>Standardroutinen, die nicht werfen.</summary>
  QuietRoutines: array[0..22] of string = ('Assigned', 'Length', 'High', 'Low', 'SizeOf', 'Ord', 'Chr', 'Inc',
    'Dec', 'Include', 'Exclude', 'Default', 'Supports', 'Max', 'Min', 'TypeInfo', 'Trim', 'SameText', 'LowerCase',
    'UpperCase', 'Exit', 'Break', 'Continue');

type
  /// <summary>Feld, das beim Destruktor nach einer Exception im Konstruktor noch nil sein kann.</summary>
  TNilAtDestroy = record
    Field: string;
    /// <summary>Aufruf vor dem Anlegen, der werfen kann (TFileStream.Create); '' bei bedingtem Anlegen.</summary>
    Raiser: string;
    /// <summary>Wird das Feld im Konstruktor nur bedingt angelegt?</summary>
    Conditional: Boolean;
  end;

procedure TDestructorNotNilSafeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Fields: TArray<string>;
  Risky: TArray<TNilAtDestroy>;
  PrivateMethods: TArray<string>;
  OnlyAfterRaising: Boolean;
  QualifiedClass, LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function Contains(const AList: TArray<string>; const AName: string): Boolean;
  var
    Item: string;
  begin
    for Item in AList do
      if SameText(Item, AName) then
        Exit(True);
    Result := False;
  end;

  function MethodOf(ARoutine: TSyntaxNode): string;
  begin
    Result := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
  end;

  // Methoden in private- und strict-private-Abschnitten der Klassendeklaration.
  function PrivateOf(AClass: TSyntaxNode): TArray<string>;
  var
    Index: Integer;
    IsPrivate: Boolean;
  begin
    Result := nil;
    if AClass = nil then
      Exit;
    IsPrivate := False;
    for Index := 0 to AClass.ChildCount - 1 do
      if AClass[Index].Kind = TSyntaxKind.Visibility then
        IsPrivate := MatchText(AClass[Index].Name, ['private', 'strict private'])
      else if IsPrivate and (AClass[Index].Kind = TSyntaxKind.RoutineHeader) and (AClass[Index].Name <> '') then
        Result := Result + [AClass[Index].Name];
  end;

  function ClassOf(ARoutine: TSyntaxNode): string;
  begin
    Result := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
  end;

  // constructor bzw. destructor, ohne class constructor und class destructor.
  function StartsWithWord(ARoutine: TSyntaxNode; const AWord: string): Boolean;
  var
    Head: string;
  begin
    Head := TrimLeft(Text(ARoutine));
    Result := StartsText(AWord, Head) and (Length(Head) > Length(AWord)) and
      CharInSet(Head[Length(AWord) + 1], [' ', #9, #10, #13]);
  end;

  // Konstruktoraufruf TKlasse.Create…(…) bzw. TKlasse<T>.Create…; liefert TKlasse.Create….
  function CreationCall(AValue: TSyntaxNode; out ACallee: string): Boolean;
  var
    Callee: TSyntaxNode;
  begin
    Result := False;
    Callee := AValue;
    if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount > 0) then
      Callee := Callee[0];
    if (Callee.Kind <> TSyntaxKind.MemberAccess) or (Callee.ChildCount = 0) or not StartsText('Create', Callee.Name) then
      Exit;
    // Records mit Create (TStopwatch.Create) brauchen keine Freigabe und sind nie nil.
    if MatchText(RootName(Callee[0]), ['TStopwatch', 'TTimeSpan', 'TRect', 'TPoint', 'TSize', 'TGUID',
      'TFormatSettings', 'TValue', 'TRegEx', 'TRttiContext']) then
      Exit;
    ACallee := Trim(Text(Callee));
    Result := True;
  end;

  // Wirft der Konstruktoraufruf höchstens EOutOfMemory (TStringList.Create, TDictionary<K, V>.Create)?
  function QuietCreation(AValue: TSyntaxNode): Boolean;
  var
    Callee: TSyntaxNode;
    Name: string;
    Index: Integer;
  begin
    Callee := AValue;
    if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount > 0) then
    begin
      // Nur feste Argumente wie TObjectList<T>.Create(True).
      for Index := 1 to Callee.ChildCount - 1 do
        if (Callee[Index].Kind <> TSyntaxKind.Literal) and not ((Callee[Index].Kind = TSyntaxKind.Identifier) and
          MatchText(Callee[Index].Name, ['True', 'False', 'nil'])) then
          Exit(False);
      Callee := Callee[0];
    end;
    Result := (Callee.Kind = TSyntaxKind.MemberAccess) and SameText(Callee.Name, 'Create') and (Callee.ChildCount > 0);
    if not Result then
      Exit;
    Name := Trim(Text(Callee[0]));
    if Pos('<', Name) > 0 then
      Name := Copy(Name, 1, Pos('<', Name) - 1);
    Result := MatchText(Name, QuietConstructions);
  end;

  // Weist AStatement einem Feld mit TKlasse.Create zu? Liefert Feld und Aufruf.
  function CreatesField(AStatement: TSyntaxNode; out AField, ACallee: string): Boolean;
  begin
    Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2);
    if not Result then
      Exit;
    AField := FreedPath(AStatement[0]);
    Result := (AField <> '') and Contains(Fields, AField) and CreationCall(AStatement[1], ACallee);
  end;

  // Erster Aufruf in ANode, der werfen kann (ohne inherited); '' ohne. AStatement: ANode ist eine Anweisung.
  function RaisingCall(ARoot: TSyntaxNode): string;
  var
    Index: Integer;
    Node, Callee: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): Continue lässt den Teilbaum aus, Exit liefert den ersten Treffer.
    Result := '';
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl, TSyntaxKind.InheritedExpr] then
          Continue;
        if Node.Kind = TSyntaxKind.RaiseStatement then
          Exit('raise');
        // Aufruf ohne Klammern als Anweisung: Laden; bzw. FLog.Oeffnen;
        if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) and
          (Node[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
        begin
          if (Node[0].Kind = TSyntaxKind.Identifier) and MatchText(Node[0].Name, QuietRoutines) then
            Continue;
          if QuietCreation(Node[0]) then
            Continue;
          Exit(Trim(Text(Node[0])));
        end;
        // TKlasse.Create ohne Klammern ist ebenfalls ein Aufruf.
        if (Node.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', Node.Name) and
          ((Node.Parent = nil) or (Node.Parent.Kind <> TSyntaxKind.Call)) then
        begin
          if QuietCreation(Node) then
            Continue;
          Exit(Trim(Text(Node)));
        end;
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) then
        begin
          Callee := Node[0];
          if (Callee.Kind = TSyntaxKind.InheritedExpr) or QuietCreation(Node) or
            ((Callee.Kind = TSyntaxKind.Identifier) and MatchText(Callee.Name, QuietRoutines)) then
            Continue;
          Exit(Trim(Text(Callee)));
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Weist eine Anweisung unter ANode dem Feld AField zu?
  function AssignsField(ARoot: TSyntaxNode; const AField: string): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
          Continue;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          SameText(FreedPath(Node[0]), AField) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Kinder, die AssignsAlways für ANode auswertet.
  function AlwaysParts(ANode: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 0 to ANode.ChildCount - 1 do
      case ANode.Kind of
        TSyntaxKind.Block:
          Result := Result + [ANode[Index]];
        TSyntaxKind.IfStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse:
          if ANode[Index].Kind in FlowStatementKinds then
            Result := Result + [ANode[Index]];
        TSyntaxKind.CaseStatement:
          if ANode[Index].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
            Result := Result + [ANode[Index]];
      end;
  end;

  // Weist ANode dem Feld AField auf jedem Weg zu (if mit beiden Zweigen, case mit else, begin … end)?
  function AssignsAlways(ANode: TSyntaxNode; const AField: string): Boolean;
  var
    Pending: TStack<TSyntaxPostOrderEntry>;
    Values: TStack<Boolean>;
    Entry: TSyntaxPostOrderEntry;
    Node: TSyntaxNode;
    Parts: TArray<TSyntaxNode>;
    Index: Integer;
    AnyTrue, AllTrue, HasElse, Value: Boolean;
  begin
    // Iterativ (Bericht M1): Nachordnung mit Wertestapel; else-if-Ketten sind tiefe Bäume.
    Pending := TStack<TSyntaxPostOrderEntry>.Create;
    Values := TStack<Boolean>.Create;
    try
      Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
      while Pending.Count > 0 do
      begin
        Entry := Pending.Pop;
        Node := Entry.Node;
        if not Entry.Done then
        begin
          if Node.Kind = TSyntaxKind.AssignStatement then
            Values.Push((Node.ChildCount = 2) and SameText(FreedPath(Node[0]), AField))
          else if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
            TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
          begin
            Pending.Push(TSyntaxPostOrderEntry.Create(Node, True));
            Parts := AlwaysParts(Node);
            for Index := High(Parts) downto 0 do
              Pending.Push(TSyntaxPostOrderEntry.Create(Parts[Index], False));
          end
          else
            Values.Push(False);
          Continue;
        end;
        // Die Werte der Teile liegen oben auf dem Wertestapel.
        Parts := AlwaysParts(Node);
        AnyTrue := False;
        AllTrue := True;
        HasElse := False;
        for Index := 0 to High(Parts) do
        begin
          Value := Values.Pop;
          AnyTrue := AnyTrue or Value;
          AllTrue := AllTrue and Value;
          HasElse := HasElse or (Parts[Index].Kind = TSyntaxKind.CaseElse);
        end;
        case Node.Kind of
          TSyntaxKind.IfStatement:
            Values.Push(AllTrue and (Length(Parts) = 2));
          TSyntaxKind.CaseStatement:
            Values.Push(AllTrue and HasElse);
        else
          Values.Push(AnyTrue);
        end;
      end;
      Result := Values.Pop;
    finally
      Values.Free;
      Pending.Free;
    end;
  end;

  procedure AddRisky(const AField, ARaiser: string; AConditional: Boolean);
  var
    Item: TNilAtDestroy;
  begin
    for Item in Risky do
      if SameText(Item.Field, AField) then
        Exit;
    Item.Field := AField;
    Item.Raiser := ARaiser;
    if not AConditional and (ARaiser = '') then
      Item.Raiser := 'der Konstruktor';
    Item.Conditional := AConditional;
    Risky := Risky + [Item];
  end;

  // Felder, die nach einer Exception in AConstructor beim Destruktor noch nil sein können.
  procedure ScanConstructor(AConstructor: TSyntaxNode);
  var
    Body, Statement: TSyntaxNode;
    Index: Integer;
    Raiser, Field, Callee, Created: string;
    Done: TArray<string>;
  begin
    Body := AConstructor.FindChild(TSyntaxKind.Block);
    if Body = nil then
      Exit;
    Raiser := '';
    Done := nil;
    for Index := 0 to Body.ChildCount - 1 do
    begin
      Statement := Body[Index];
      if CreatesField(Statement, Field, Callee) then
      begin
        if not Contains(Done, Field) then
        begin
          Done := Done + [Field];
          if Raiser <> '' then
            AddRisky(Field, Raiser, False)
          else if not OnlyAfterRaising then
            AddRisky(Field, Callee, False);
        end;
        if not QuietCreation(Statement[1]) then
          Raiser := Callee;
        Continue;
      end;
      // In if, case, try, Schleife oder with angelegt: auf jedem Weg wie eine einfache Zuweisung, sonst bedingt.
      if (Statement.Kind in FlowStatementKinds) and (Statement.Kind <> TSyntaxKind.AssignStatement) then
        for Created in Fields do
          if not Contains(Done, Created) and AssignsField(Statement, Created) then
          begin
            Done := Done + [Created];
            if not AssignsAlways(Statement, Created) then
              AddRisky(Created, '', True)
            else if Raiser <> '' then
              AddRisky(Created, Raiser, False)
            else if not OnlyAfterRaising then
              AddRisky(Created, RaisingCall(Statement), False);
          end;
      Callee := RaisingCall(Statement);
      if Callee <> '' then
        Raiser := Callee;
    end;
  end;

  function RiskOf(const AField: string; out AItem: TNilAtDestroy): Boolean;
  var
    Item: TNilAtDestroy;
  begin
    for Item in Risky do
      if SameText(Item.Field, AField) then
      begin
        AItem := Item;
        Exit(True);
      end;
    Result := False;
  end;

  // Ruft ARoutine die Methode AName der eigenen Klasse auf (AName; AName(…); Self.AName)?
  function Calls(ARoutine: TSyntaxNode; const AName: string): Boolean;

    function Visit(ARoot: TSyntaxNode): Boolean;
    var
      Index: Integer;
      E: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Result := False;
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          E := Pending.Pop;
          if (E.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call]) and (E.ChildCount > 0) and
            SameText(FreedPath(E[0]), AName) then
            Exit(True);
          for Index := E.ChildCount - 1 downto 0 do
            Pending.Push(E[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Result := Visit(ARoutine);
  end;

  // Private Methode der Klasse, die nur aus dem Destruktor aufgerufen wird (FreeAll aus Destroy); öffentliche
  // Methoden rufen auch andere Units.
  function OnlyCalledFromDestructor(ARoutine: TSyntaxNode): Boolean;
  var
    Other: TSyntaxNode;
    Callers: Integer;
  begin
    if not Contains(PrivateMethods, MethodOf(ARoutine)) then
      Exit(False);
    Callers := 0;
    for Other in Routines do
      if (Other <> ARoutine) and Calls(Other, MethodOf(ARoutine)) then
      begin
        if not SameText(ClassOf(Other), QualifiedClass) or not StartsWithWord(Other, 'destructor') then
          Exit(False);
        Inc(Callers);
      end;
    Result := Callers > 0;
  end;

  // Einrückung vor ANode; False, wenn davor in der Zeile noch Code steht.
  function Indent(ANode: TSyntaxNode; out AIndent: string): Boolean;
  var
    Start: Integer;
  begin
    Start := ANode.StartOffset;
    while (Start > 0) and CharInSet(AContext.Text[Start], [' ', #9]) do
      Dec(Start);
    AIndent := Copy(AContext.Text, Start + 1, ANode.StartOffset - Start);
    Result := (Start = 0) or CharInSet(AContext.Text[Start], [#10, #13]);
  end;

  // Korrektur: "if Assigned(FFeld) then" vor eine Anweisung, die allein in einer Anweisungsliste steht.
  function GuardFix(AStatement: TSyntaxNode; const AField: string): TArray<TRuleFix>;
  var
    Outer: string;
  begin
    Result := nil;
    if (AStatement.Parent = nil) or (AStatement.Parent.Kind <> TSyntaxKind.Block) or
      (AStatement.StartPos.Line <> AStatement.EndPos.Line) or not Indent(AStatement, Outer) then
      Exit;
    Result := [TRuleFix.Create(Format('In if Assigned(%s) then einschließen', [AField]),
      [TRuleEdit.Create(NodeRange(AStatement), Format('if Assigned(%s) then', [AField]) + LineBreak + Outer + '  ' +
      Trim(Text(AStatement)))])];
  end;

  procedure CheckBody(ARoutine: TSyntaxNode);
  var
    Checked, Reported: TArray<string>;

    // Assigned(X), X <> nil, X = nil in E sammeln: danach gilt X als geprüft.
    procedure CollectChecks(ARoot: TSyntaxNode);
    var
      Index: Integer;
      E: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          E := Pending.Pop;
          if (E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and IsName(E[0], 'Assigned') and
            (FreedPath(E[1]) <> '') then
            Checked := Checked + [FreedPath(E[1])];
          if (E.Kind = TSyntaxKind.BinaryExpr) and (E.ChildCount = 2) then
            for Index := 0 to 1 do
              if (FreedPath(E[Index]) <> '') and (E[1 - Index].Kind = TSyntaxKind.Literal) and
                SameText(E[1 - Index].Name, 'nil') then
                Checked := Checked + [FreedPath(E[Index])];
          for Index := E.ChildCount - 1 downto 0 do
            Pending.Push(E[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

    // Zugriffe FFeld.X (außer Free und DisposeOf), FFeld[…] und FFeld^ in E, in Textreihenfolge.
    procedure Visit(ARoot: TSyntaxNode);
    var
      Index: Integer;
      E, Statement: TSyntaxNode;
      Field, Access: string;
      Item: TNilAtDestroy;
      Message: string;
      Pending, PendingStatement: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1): Vorordnung wie die Rekursion, Checked wächst in derselben Reihenfolge.
      Pending := TStack<TSyntaxNode>.Create;
      PendingStatement := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        PendingStatement.Push(ARoot);
        while Pending.Count > 0 do
        begin
          E := Pending.Pop;
          Statement := PendingStatement.Pop;
          if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
            Continue;
          if E.Kind in FlowStatementKinds + [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement] then
            Statement := E;
          // if Assigned(FFeld) then …, while FFeld <> nil do …: die Bedingung schützt alles danach.
          if E.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
            TSyntaxKind.CaseStatement] then
            for Index := 0 to E.ChildCount - 1 do
              if not (E[Index].Kind in FlowStatementKinds) then
                CollectChecks(E[Index]);
          // Neu zugewiesen im Destruktor: der Wert stammt nicht mehr aus dem Konstruktor.
          if (E.Kind = TSyntaxKind.AssignStatement) and (E.ChildCount = 2) and (FreedPath(E[0]) <> '') then
            Checked := Checked + [FreedPath(E[0])];
          if (E.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
            (E.ChildCount > 0) then
          begin
            Field := FreedPath(E[0]);
            if (Field <> '') and not ((E.Kind = TSyntaxKind.MemberAccess) and
              MatchText(E.Name, ['Free', 'DisposeOf'])) and not Contains(Checked, Field) and
              not Contains(Reported, Field + '@' + IntToStr(Statement.StartOffset)) and RiskOf(Field, Item) then
            begin
              // Je Anweisung und Feld ein Befund, damit jede Korrektur ihre Anweisung schützt.
              Reported := Reported + [Field + '@' + IntToStr(Statement.StartOffset)];
              Access := Trim(Text(E));
              if Item.Conditional then
                Message := Format('%s wird im Konstruktor nur bedingt angelegt und kann beim Destruktor nil sein; ' +
                  '%s stürzt dann ab.', [Field, Access])
              else
                Message := Format('Wirft %s, ist %s beim Destruktor noch nil; %s stürzt ab und verdeckt die ' +
                  'eigentliche Exception.', [Item.Raiser, Field, Access]);
              AReport.Add(NodeRange(E), Message, TRuleConfidence.High, GuardFix(Statement, Field));
            end;
          end;
          for Index := E.ChildCount - 1 downto 0 do
          begin
            Pending.Push(E[Index]);
            PendingStatement.Push(Statement);
          end;
        end;
      finally
        PendingStatement.Free;
        Pending.Free;
      end;
    end;

  var
    Body: TSyntaxNode;
  begin
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    if Body = nil then
      Exit;
    Checked := nil;
    Reported := nil;
    Visit(Body);
  end;

var
  Routine, Other: TSyntaxNode;
  ClassName: string;
  Classes: TArray<string>;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'destructor') then
    Exit;
  OnlyAfterRaising := TRuleOptions.Bool(AContext.Options, 'onlyAfterRaisingCode', True);
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
    LineBreak := #13#10;
  Routines := TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext);
  Classes := nil;
  for Routine in Routines do
  begin
    QualifiedClass := ClassOf(Routine);
    if (QualifiedClass = '') or Contains(Classes, QualifiedClass) or not StartsWithWord(Routine, 'destructor') then
      Continue;
    Classes := Classes + [QualifiedClass];
    ClassName := Copy(QualifiedClass, LastDelimiter('.', QualifiedClass) + 1, MaxInt);
    if Pos('<', ClassName) > 0 then
      ClassName := Copy(ClassName, 1, Pos('<', ClassName) - 1);
    Fields := ClassFields(FindClassType(AContext.Tree.Root, ClassName));
    if Fields = nil then
      Continue;
    PrivateMethods := PrivateOf(FindClassType(AContext.Tree.Root, ClassName));
    Risky := nil;
    for Other in Routines do
      if SameText(ClassOf(Other), QualifiedClass) and StartsWithWord(Other, 'constructor') then
        ScanConstructor(Other);
    if Risky = nil then
      Continue;
    // Destruktoren und Methoden, die nur sie aufrufen; BeforeDestruction läuft nach einer Exception im
    // Konstruktor nicht.
    for Other in Routines do
      if SameText(ClassOf(Other), QualifiedClass) and (StartsWithWord(Other, 'destructor') or
        (not StartsWithWord(Other, 'constructor') and OnlyCalledFromDestructor(Other))) then
        CheckBody(Other);
  end;
end;

{ THandleLeakRule }

const
  /// <summary>Öffnen|Ort|Schließen: Ort r = Ergebnis, Zahlen = out-Argumente (ab 0), Zahl:Feld,Feld = Felder
  /// eines Record-Arguments (CreateProcess). Im Schließen steht %h für das Handle, %0 für das erste Argument
  /// des Öffnens. Namen mit A/W am Ende gelten mit.</summary>
  BuiltinHandlePairs: array[0..64] of string = (
    'CreateFile|r|CloseHandle(%h)', 'CreateEvent|r|CloseHandle(%h)', 'CreateEventEx|r|CloseHandle(%h)',
    'CreateMutex|r|CloseHandle(%h)', 'CreateSemaphore|r|CloseHandle(%h)', 'CreateWaitableTimer|r|CloseHandle(%h)',
    'CreateThread|r|CloseHandle(%h)', 'CreateRemoteThread|r|CloseHandle(%h)', 'OpenProcess|r|CloseHandle(%h)',
    'OpenThread|r|CloseHandle(%h)', 'OpenEvent|r|CloseHandle(%h)', 'OpenMutex|r|CloseHandle(%h)',
    'OpenSemaphore|r|CloseHandle(%h)', 'CreateFileMapping|r|CloseHandle(%h)', 'OpenFileMapping|r|CloseHandle(%h)',
    'CreateNamedPipe|r|CloseHandle(%h)', 'CreateMailslot|r|CloseHandle(%h)',
    'CreateToolhelp32Snapshot|r|CloseHandle(%h)', 'CreateJobObject|r|CloseHandle(%h)',
    'OpenProcessToken|2|CloseHandle(%h)', 'OpenThreadToken|3|CloseHandle(%h)', 'DuplicateToken|2|CloseHandle(%h)',
    'CreatePipe|0,1|CloseHandle(%h)', 'CreateProcess|9:hProcess,hThread|CloseHandle(%h)',
    'CreateProcessAsUser|10:hProcess,hThread|CloseHandle(%h)', 'FindFirstFile|r|FindClose(%h)',
    'FindFirstFileEx|r|FindClose(%h)', 'FindFirstChangeNotification|r|FindCloseChangeNotification(%h)',
    'LoadLibrary|r|FreeLibrary(%h)', 'LoadLibraryEx|r|FreeLibrary(%h)', 'GetDC|r|ReleaseDC(%0, %h)',
    'GetWindowDC|r|ReleaseDC(%0, %h)', 'GetDCEx|r|ReleaseDC(%0, %h)', 'CreateCompatibleDC|r|DeleteDC(%h)',
    'CreateDC|r|DeleteDC(%h)', 'CreateIC|r|DeleteDC(%h)', 'CreatePen|r|DeleteObject(%h)',
    'CreatePenIndirect|r|DeleteObject(%h)', 'ExtCreatePen|r|DeleteObject(%h)', 'CreateFont|r|DeleteObject(%h)',
    'CreateFontIndirect|r|DeleteObject(%h)', 'CreateSolidBrush|r|DeleteObject(%h)',
    'CreateHatchBrush|r|DeleteObject(%h)', 'CreatePatternBrush|r|DeleteObject(%h)',
    'CreateBrushIndirect|r|DeleteObject(%h)', 'CreateBitmap|r|DeleteObject(%h)',
    'CreateCompatibleBitmap|r|DeleteObject(%h)', 'CreateDIBitmap|r|DeleteObject(%h)',
    'CreateDIBSection|r|DeleteObject(%h)', 'CreateRectRgn|r|DeleteObject(%h)',
    'CreateRectRgnIndirect|r|DeleteObject(%h)', 'CreateRoundRectRgn|r|DeleteObject(%h)',
    'CreateEllipticRgn|r|DeleteObject(%h)', 'CreatePolygonRgn|r|DeleteObject(%h)',
    'CreatePalette|r|DeleteObject(%h)', 'CreateIcon|r|DestroyIcon(%h)', 'CreateIconIndirect|r|DestroyIcon(%h)',
    'CopyIcon|r|DestroyIcon(%h)', 'ExtractIcon|r|DestroyIcon(%h)', 'OpenSCManager|r|CloseServiceHandle(%h)',
    'OpenService|r|CloseServiceHandle(%h)', 'CreateService|r|CloseServiceHandle(%h)',
    'RegOpenKeyEx|4|RegCloseKey(%h)', 'RegCreateKeyEx|7|RegCloseKey(%h)', 'MapViewOfFile|r|UnmapViewOfFile(%h)');
  /// <summary>Routinen, die ein Handle nur benutzen und es nicht übernehmen; jede andere Übergabe zählt als
  /// Weitergabe.</summary>
  HandleUsers: array[0..75] of string = ('WaitForSingleObject', 'WaitForSingleObjectEx', 'WaitForInputIdle',
    'MsgWaitForMultipleObjects', 'SignalObjectAndWait', 'ReadFile', 'WriteFile', 'ReadFileEx', 'WriteFileEx',
    'GetFileSize', 'GetFileSizeEx', 'SetFilePointer', 'SetFilePointerEx', 'SetEndOfFile', 'FlushFileBuffers',
    'GetFileTime', 'SetFileTime', 'GetFileType', 'GetFileInformationByHandle', 'LockFile', 'UnlockFile',
    'LockFileEx', 'UnlockFileEx', 'DeviceIoControl', 'GetOverlappedResult', 'SetEvent', 'ResetEvent', 'PulseEvent',
    'ReleaseMutex', 'ReleaseSemaphore', 'SetWaitableTimer', 'CancelWaitableTimer', 'TerminateProcess',
    'TerminateThread', 'GetExitCodeProcess', 'GetExitCodeThread', 'ResumeThread', 'SuspendThread',
    'SetThreadPriority', 'GetProcessTimes', 'GetProcessId', 'GetThreadId', 'QueryFullProcessImageName',
    'GetModuleFileNameEx', 'GetTokenInformation', 'AdjustTokenPrivileges', 'FindNextFile',
    'FindNextChangeNotification', 'Process32First', 'Process32Next', 'Module32First', 'Module32Next',
    'Thread32First', 'Thread32Next', 'PeekNamedPipe', 'ConnectNamedPipe', 'DisconnectNamedPipe', 'GetProcAddress',
    'RegQueryValueEx', 'RegSetValueEx', 'RegEnumKeyEx', 'RegEnumValue', 'RegDeleteValue', 'RegQueryInfoKey',
    'RegDeleteKey', 'SelectObject', 'GetObject', 'GetDeviceCaps', 'BitBlt', 'StretchBlt', 'TextOut', 'DrawText',
    'FillRect', 'FrameRect', 'FillRgn', 'PatBlt');

type
  /// <summary>Paar aus Tabelle oder Option.</summary>
  THandlePair = record
    Open: string;
    /// <summary>'r' für das Ergebnis, sonst Argumente wie '4', '0,1' oder '9:hProcess,hThread'.</summary>
    Where: string;
    Close: string;
  end;

  /// <summary>Ein geöffnetes Handle: Pfad (H, PI.hProcess) und Schließen.</summary>
  TOpenedHandle = record
    Path: string;
    /// <summary>Wurzel des Pfads (PI bei PI.hProcess); Weitergabe der Wurzel gibt auch das Handle weiter.</summary>
    Root: string;
    CloseName: string;
    CloseText: string;
  end;

function THandleLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(HandleLeakRuleId, TRuleSeverity.Warning, 'Windows-Handle wird nicht geschlossen');
end;

class function THandleLeakRule.Pairs(const AOptions: string): TArray<string>;
var
  Value, List, Item: TJSONValue;
  Open, Close: string;
begin
  Result := nil;
  for Open in BuiltinHandlePairs do
    Result := Result + [Open];
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    List := TJSONObject(Value).GetValue('pairs');
    if not (List is TJSONArray) then
      Exit;
    for Item in TJSONArray(List) do
    begin
      Open := '';
      Close := '';
      // "MeinOeffnen>MeinSchliessen" bzw. {"open": "MeinOeffnen", "close": "MeinSchliessen"}.
      if (Item is TJSONString) and (Pos('>', Item.Value) > 1) then
      begin
        Open := Trim(Copy(Item.Value, 1, Pos('>', Item.Value) - 1));
        Close := Trim(Copy(Item.Value, Pos('>', Item.Value) + 1, MaxInt));
      end
      else if Item is TJSONObject then
      begin
        if not TJSONObject(Item).TryGetValue<string>('open', Open) or
          not TJSONObject(Item).TryGetValue<string>('close', Close) then
          Continue;
        Open := Trim(Open);
        Close := Trim(Close);
      end;
      if (Open <> '') and (Close <> '') and IsValidIdent(Open, True) and IsValidIdent(Close, True) then
        Result := Result + [Open + '|r|' + Close + '(%h)'];
    end;
  finally
    Value.Free;
  end;
end;

procedure THandleLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Table: TArray<THandlePair>;
  Cache: IRuleDerivedCache;
  Graph: TControlFlowGraph;
  Locals: TArray<string>;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function Contains(const AList: TArray<string>; const AName: string): Boolean;
  var
    Item: string;
  begin
    for Item in AList do
      if SameText(Item, AName) then
        Exit(True);
    Result := False;
  end;

  // Name einer aufgerufenen Routine ohne Unit-Präfix (Winapi.Windows.CloseHandle).
  function CallName(ACall: TSyntaxNode): string;
  var
    Callee: TSyntaxNode;
  begin
    Result := '';
    if (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount = 0) then
      Exit;
    Callee := ACall[0];
    if Callee.Kind = TSyntaxKind.Identifier then
      Result := Callee.Name
    else if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and
      MatchText(Trim(Text(Callee[0])), ['Windows', 'Winapi.Windows', 'ShellAPI', 'Winapi.ShellAPI', 'TlHelp32',
      'Winapi.TlHelp32', 'WinSvc', 'Winapi.WinSvc']) then
      Result := Callee.Name;
  end;

  // Gleicher Name, auch mit A/W-Endung (CreateFileW).
  function SameRoutine(const AName, ATableName: string): Boolean;
  begin
    Result := SameText(AName, ATableName) or ((Length(AName) = Length(ATableName) + 1) and
      StartsText(ATableName, AName) and CharInSet(AName[Length(AName)], ['A', 'W']));
  end;

  function PairOf(const AName: string; out APair: THandlePair): Boolean;
  var
    Pair: THandlePair;
  begin
    for Pair in Table do
      if SameRoutine(AName, Pair.Open) then
      begin
        APair := Pair;
        Exit(True);
      end;
    Result := False;
  end;

  // Pfad eines Ausdrucks: H, PI.hProcess; sonst ''.
  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode.Kind = TSyntaxKind.Identifier then
      Result := ANode.Name
    else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) then
      Result := ANode[0].Name + '.' + ANode.Name;
  end;

  function CloseText(const APair: THandlePair; ACall: TSyntaxNode; const APath: string): string;
  begin
    Result := StringReplace(APair.Close, '%h', APath, [rfReplaceAll]);
    if (Pos('%0', Result) > 0) and (ACall.ChildCount > 1) then
      Result := StringReplace(Result, '%0', Trim(Text(ACall[1])), [rfReplaceAll]);
  end;

  // Handles, die ACall öffnet; ATarget ist das Ziel einer Zuweisung (nil ohne).
  function Opened(ACall: TSyntaxNode; const ATarget: string; out AHandles: TArray<TOpenedHandle>): Boolean;
  var
    Pair: THandlePair;
    Handle: TOpenedHandle;
    Part, Arg, Field: string;
    Parts, Fields: TArray<string>;
    Index: Integer;
  begin
    AHandles := nil;
    if not PairOf(CallName(ACall), Pair) then
      Exit(False);
    Handle.CloseName := Copy(Pair.Close, 1, Pos('(', Pair.Close) - 1);
    if Pair.Where = 'r' then
    begin
      if (ATarget <> '') and Contains(Locals, ATarget) then
      begin
        Handle.Path := ATarget;
        Handle.Root := ATarget;
        Handle.CloseText := CloseText(Pair, ACall, Handle.Path);
        AHandles := [Handle];
      end;
    end
    else
    begin
      Fields := nil;
      Part := Pair.Where;
      if Pos(':', Part) > 0 then
      begin
        Fields := Copy(Part, Pos(':', Part) + 1, MaxInt).Split([',']);
        Part := Copy(Part, 1, Pos(':', Part) - 1);
      end;
      Parts := Part.Split([',']);
      for Part in Parts do
      begin
        Index := StrToIntDef(Part, -1) + 1;
        if (Index < 1) or (Index >= ACall.ChildCount) then
          Continue;
        Arg := PathOf(ACall[Index]);
        if (Arg = '') or (Pos('.', Arg) > 0) or not Contains(Locals, Arg) then
          Continue;
        Handle.Root := Arg;
        if Fields = nil then
        begin
          Handle.Path := Arg;
          Handle.CloseText := CloseText(Pair, ACall, Handle.Path);
          AHandles := AHandles + [Handle];
        end
        else
          for Field in Fields do
          begin
            Handle.Path := Arg + '.' + Field;
            Handle.CloseText := CloseText(Pair, ACall, Handle.Path);
            AHandles := AHandles + [Handle];
          end;
      end;
    end;
    Result := AHandles <> nil;
  end;

  // Was ein Knoten selbst auswertet: einfache Anweisungen ganz, bei if, case und Schleifen die Bedingung bzw.
  // der Kopf, with ganz (with H do … gibt das Handle weiter).
  function Parts(ANode: TFlowNode): TArray<TSyntaxNode>;
  begin
    Result := nil;
    if ANode.Syntax = nil then
      Exit;
    if ANode.Syntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
      TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.WithStatement] then
      Result := [ANode.Syntax]
    else if ANode.Kind = TFlowNodeKind.Condition then
      Result := OwnParts(ANode.Syntax);
  end;

  // Schließt E das Handle (CloseHandle(PI.hProcess), ReleaseDC(Wnd, DC))?
  function Closes(ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  var
    Index: Integer;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
          Continue;
        if (E.Kind = TSyntaxKind.Call) and SameRoutine(CallName(E), AHandle.CloseName) then
          for Index := 1 to E.ChildCount - 1 do
            if SameText(PathOf(E[Index]), AHandle.Path) then
              Exit(True);
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Kommt das Handle (oder seine Wurzel) in E vor?
  function Mentions(ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  var
    Index: Integer;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if (E.Kind = TSyntaxKind.Identifier) and SameText(E.Name, AHandle.Root) and
          ((E.Parent = nil) or (E.Parent.Kind <> TSyntaxKind.MemberAccess) or (E.Parent[0] <> E) or
          SameText(PathOf(E.Parent), AHandle.Path) or (Pos('.', AHandle.Path) = 0)) then
          Exit(True);
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Ist E das Handle selbst, seine Wurzel (PI) oder eine Typumwandlung davon (THandle(H), (H))?
  function IsHandleValue(E: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  begin
    // Iterativ (Bericht M1): an Klammern und Typumwandlungen entlang nach innen.
    Result := False;
    while True do
    begin
      if SameText(PathOf(E), AHandle.Path) or ((E.Kind = TSyntaxKind.Identifier) and SameText(E.Name, AHandle.Root)) then
        Exit(True);
      if (E.Kind = TSyntaxKind.ParenExpr) and (E.ChildCount = 1) then
        E := E[0]
      else if (E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and (E[0].Kind = TSyntaxKind.Identifier) and
        MatchText(E[0].Name, ['THandle', 'HWND', 'HMODULE', 'HKEY', 'HDC', 'HGDIOBJ', 'Integer', 'Cardinal',
        'NativeInt', 'NativeUInt', 'Pointer', 'UIntPtr', 'IntPtr']) then
        E := E[1]
      else
        Exit;
    end;
  end;

  // Gibt E das Handle weiter: Zuweisung an ein anderes Ziel, Exit(H), Übergabe an eine unbekannte Routine,
  // with, anonyme Methode?
  function PassesOn(ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Name: string;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind = TSyntaxKind.AnonymousMethod then
        begin
          if Mentions(E, AHandle) then
            Exit(True);
          Continue;
        end;
        if E.Kind = TSyntaxKind.RoutineDecl then
          Continue;
        if (E.Kind = TSyntaxKind.AssignStatement) and (E.ChildCount = 2) and IsHandleValue(E[1], AHandle) then
          Exit(True);
        // @Funktion := GetProcAddress(Modul, …) in eine Variable außerhalb der Routine: Das Modul muss geladen
        // bleiben, solange jemand den Zeiger aufrufen kann.
        if (E.Kind = TSyntaxKind.AssignStatement) and (E.ChildCount = 2) and (E[1].Kind = TSyntaxKind.Call) and
          SameRoutine(CallName(E[1]), 'GetProcAddress') and Mentions(E[1], AHandle) and
          not Contains(Locals, RootName(E[0])) then
          Exit(True);
        if (E.Kind = TSyntaxKind.InlineVar) and (E.ChildCount > 0) and IsHandleValue(E[E.ChildCount - 1], AHandle) then
          Exit(True);
        if (E.Kind = TSyntaxKind.WithStatement) and Mentions(E, AHandle) then
          Exit(True);
        if (E.Kind = TSyntaxKind.Call) and (E <> AOpenCall) then
        begin
          Name := CallName(E);
          if SameText(Name, 'Exit') or not (MatchText(Name, HandleUsers) or SameRoutine(Name, AHandle.CloseName) or
            MatchText(Name, ['Win32Check', 'CheckOSError', 'Assigned', 'Ord', 'Integer', 'Cardinal', 'NativeInt',
            'NativeUInt', 'THandle', 'IntToStr', 'IntToHex', 'Format'])) then
            for Index := 1 to E.ChildCount - 1 do
              if Mentions(E[Index], AHandle) then
                Exit(True);
        end;
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function IsFailureValue(E: TSyntaxNode): Boolean;
  begin
    Result := ((E.Kind = TSyntaxKind.Literal) and MatchText(E.Name, ['0', 'nil'])) or
      ((E.Kind = TSyntaxKind.Identifier) and MatchText(E.Name, ['INVALID_HANDLE_VALUE', 'nil'])) or
      ((E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and (E[1].Kind = TSyntaxKind.Literal) and
      (E[1].Name = '0'));
  end;

  // Bedeutet "E ist wahr", dass das Öffnen gelang (1), misslang (-1), oder ist es unklar (0)?
  // Wert eines Vergleichs mit dem Handle (H <> 0, RegOpenKeyEx(…) = ERROR_SUCCESS); 0 sonst.
  function ComparisonSuccess(E: TSyntaxNode; AOpenCall: TSyntaxNode; const AHandle: TOpenedHandle): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    if not MatchText(E.Name, ['=', '<>']) then
      Exit;
    for Index := 0 to 1 do
      if (SameText(PathOf(E[Index]), AHandle.Path) or (E[Index] = AOpenCall)) then
      begin
        // RegOpenKeyEx(…) = ERROR_SUCCESS
        if (E[1 - Index].Kind = TSyntaxKind.Identifier) and SameText(E[1 - Index].Name, 'ERROR_SUCCESS') then
        begin
          if E.Name = '=' then
            Exit(1);
          Exit(-1);
        end;
        if IsFailureValue(E[1 - Index]) then
        begin
          if E.Name = '=' then
            Exit(-1);
          Exit(1);
        end;
      end;
  end;

  function Success(ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Integer;
  var
    Pending: TStack<TSyntaxPostOrderEntry>;
    Values: TStack<Integer>;
    Entry: TSyntaxPostOrderEntry;
    E: TSyntaxNode;
    Value, Left, Right: Integer;
  begin
    // Iterativ (Bericht M1): Nachordnung mit Wertestapel; lange and/or-Ketten sind tiefe Bäume. Die Auswertung
    // hat keine Nebenwirkungen, daher darf sie ohne Kurzschluss beide Operanden berechnen.
    Pending := TStack<TSyntaxPostOrderEntry>.Create;
    Values := TStack<Integer>.Create;
    try
      Pending.Push(TSyntaxPostOrderEntry.Create(ARoot, False));
      while Pending.Count > 0 do
      begin
        Entry := Pending.Pop;
        E := Entry.Node;
        if Entry.Done then
        begin
          if E.Kind = TSyntaxKind.ParenExpr then
            Value := Values.Pop
          else if E.Kind = TSyntaxKind.UnaryExpr then
            Value := -Values.Pop
          else
          begin
            Right := Values.Pop;
            Left := Values.Pop;
            Value := 0;
            if SameText(E.Name, 'and') and ((Left > 0) or (Right > 0)) then
              Value := 1
            else if SameText(E.Name, 'or') and ((Left < 0) or (Right < 0)) then
              Value := -1;
          end;
          Values.Push(Value);
          Continue;
        end;
        Value := 0;
        if E.Kind = TSyntaxKind.ParenExpr then
        begin
          if E.ChildCount = 1 then
          begin
            Pending.Push(TSyntaxPostOrderEntry.Create(E, True));
            Pending.Push(TSyntaxPostOrderEntry.Create(E[0], False));
            Continue;
          end;
        end
        else if (E.Kind = TSyntaxKind.UnaryExpr) and SameText(E.Name, 'not') and (E.ChildCount = 1) then
        begin
          Pending.Push(TSyntaxPostOrderEntry.Create(E, True));
          Pending.Push(TSyntaxPostOrderEntry.Create(E[0], False));
          Continue;
        end
        // if CreateProcess(…) then, Win32Check(…)
        else if E = AOpenCall then
          Value := 1
        else if (E.Kind = TSyntaxKind.BinaryExpr) and (E.ChildCount = 2) then
        begin
          Value := ComparisonSuccess(E, AOpenCall, AHandle);
          if (Value = 0) and (SameText(E.Name, 'and') or SameText(E.Name, 'or')) then
          begin
            Pending.Push(TSyntaxPostOrderEntry.Create(E, True));
            Pending.Push(TSyntaxPostOrderEntry.Create(E[1], False));
            Pending.Push(TSyntaxPostOrderEntry.Create(E[0], False));
            Continue;
          end;
        end;
        Values.Push(Value);
      end;
      Result := Values.Pop;
    finally
      Values.Free;
      Pending.Free;
    end;
  end;

  function InRange(AInner, AOuter: TSyntaxNode): Boolean;
  begin
    Result := (AInner <> nil) and (AOuter <> nil) and (AInner.StartOffset >= AOuter.StartOffset) and
      (AInner.EndOffset <= AOuter.EndOffset);
  end;

  // Nachfolger, denen der Weg mit offenem Handle folgt: bei if über die Prüfung des Handles nur der Zweig, in
  // dem das Öffnen gelang.
  function Followed(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): TArray<TFlowNode>;
  var
    Next: TFlowNode;
    Condition, ThenPart: TSyntaxNode;
    Index, Verdict: Integer;
    IsThen: Boolean;
  begin
    Result := nil;
    Verdict := 0;
    ThenPart := nil;
    if (ANode.Kind = TFlowNodeKind.Condition) and (ANode.Syntax.Kind = TSyntaxKind.IfStatement) then
    begin
      Condition := nil;
      for Index := 0 to ANode.Syntax.ChildCount - 1 do
        if not (ANode.Syntax[Index].Kind in FlowStatementKinds) then
        begin
          if Condition = nil then
            Condition := ANode.Syntax[Index];
        end
        else if ThenPart = nil then
          ThenPart := ANode.Syntax[Index];
      if Condition <> nil then
        Verdict := Success(Condition, AHandle, AOpenCall);
    end;
    for Next in ANode.Successors do
    begin
      if ANode.IsImplicitRaiseEdge(Next) or (Next = Graph.RaiseExit) then
        Continue;
      if Verdict <> 0 then
      begin
        IsThen := (Next.Syntax <> nil) and InRange(Next.Syntax, ThenPart);
        if IsThen <> (Verdict > 0) then
          Continue;
      end;
      Result := Result + [Next];
    end;
  end;

  // Erreicht ein Weg vom Öffnen das normale Ende, ohne das Handle zu schließen oder weiterzugeben?
  function LeaksFrom(AOpen: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current: TFlowNode;
    Part: TSyntaxNode;
    Stop: Boolean;
  begin
    Result := False;
    SetLength(Visited, Graph.Nodes.Count);
    Queue := Followed(AOpen, AHandle, AOpenCall);
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] or (Current = AOpen) then
        Continue;
      Visited[Current.Index] := True;
      if Current = Graph.ExitNode then
        Exit(True);
      Stop := False;
      if Current.Syntax <> nil then
        for Part in Parts(Current) do
          if Closes(Part, AHandle) or PassesOn(Part, AHandle, AOpenCall) then
            Stop := True;
      // Neue Zuweisung an das Handle: das alte wird hier nicht weiter verfolgt.
      if not Stop and (Current.Syntax <> nil) and (Current.Syntax.Kind = TSyntaxKind.AssignStatement) and
        (Current.Syntax.ChildCount = 2) and SameText(PathOf(Current.Syntax[0]), AHandle.Path) then
        Stop := True;
      if Stop then
        Continue;
      Queue := Queue + Followed(Current, AHandle, AOpenCall);
    end;
  end;

  // Schließt die Routine das Handle irgendwo (im Rumpf, ohne eingebettete Routinen)?
  function ClosedAnywhere(ARoutine: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  var
    Body: TSyntaxNode;
  begin
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    Result := (Body <> nil) and Closes(Body, AHandle);
  end;

  // Einrückung vor ANode; False, wenn davor in der Zeile noch Code steht.
  function Indent(ANode: TSyntaxNode; out AIndent: string; out ALineStart: Integer): Boolean;
  var
    Start: Integer;
  begin
    Start := ANode.StartOffset;
    while (Start > 0) and CharInSet(AContext.Text[Start], [' ', #9]) do
      Dec(Start);
    AIndent := Copy(AContext.Text, Start + 1, ANode.StartOffset - Start);
    ALineStart := Start;
    Result := (Start = 0) or CharInSet(AContext.Text[Start], [#10, #13]);
  end;

  function PositionAt(AOffset: Integer): TTextPosition;
  var
    Index, Line, LineStart: Integer;
  begin
    Line := 0;
    LineStart := 0;
    for Index := 1 to AOffset do
      if AContext.Text[Index] = #10 then
      begin
        Inc(Line);
        LineStart := Index;
      end;
    Result := TTextPosition.Create(Line, AOffset - LineStart);
  end;

  // Korrektur: die Anweisungen nach dem Öffnen bis zum Ende ihres Blocks in try … finally Schließen end.
  function WrapFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>): TArray<TRuleFix>;
  var
    Block, First, Last: TSyntaxNode;
    Position, Index, LineStart: Integer;
    Outer, Body, Closing, Line: string;
    Lines: TArray<string>;
  begin
    Result := nil;
    Block := AStatement.Parent;
    if (Block = nil) or (Block.Kind <> TSyntaxKind.Block) then
      Exit;
    Position := -1;
    for Index := 0 to Block.ChildCount - 1 do
      if Block[Index] = AStatement then
        Position := Index;
    if Position < 0 then
      Exit;
    Closing := '';
    // Umgekehrte Reihenfolge: zuletzt geöffnet, zuerst geschlossen (PI.hThread vor PI.hProcess).
    for Index := High(AHandles) downto 0 do
      Closing := Closing + '%s  ' + AHandles[Index].CloseText + ';' + LineBreak;
    if not Indent(AStatement, Outer, LineStart) then
      Exit;
    Closing := StringReplace(Closing, '%s', Outer, [rfReplaceAll]);
    if Position = Block.ChildCount - 1 then
    begin
      // Nichts danach: nur das Schließen anhängen.
      Body := '';
      for Index := High(AHandles) downto 0 do
        Body := Body + ';' + LineBreak + Outer + AHandles[Index].CloseText;
      Result := [TRuleFix.Create(Format('%s ergänzen', [AHandles[0].CloseName]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.EndPos, AStatement.EndPos), Body)])];
      Exit;
    end;
    First := Block[Position + 1];
    Last := Block[Block.ChildCount - 1];
    if (First.Kind = TSyntaxKind.EmptyStatement) or not Indent(First, Body, LineStart) then
      Exit;
    Body := '';
    Lines := Copy(AContext.Text, LineStart + 1, Last.EndOffset - LineStart).Replace(#13#10, #10).Split([#10]);
    for Line in Lines do
      if Trim(Line) = '' then
        Body := Body + LineBreak
      else
        Body := Body + '  ' + Line + LineBreak;
    // Die letzte Anweisung endet vor ihrem Semikolon; das alte Semikolon steht danach hinter end.
    if not Body.TrimRight.EndsWith(';') then
      Body := Body.TrimRight + ';' + LineBreak;
    Result := [TRuleFix.Create(Format('In try … finally %s einschließen', [AHandles[0].CloseName]),
      [TRuleEdit.Create(TTextRange.Create(PositionAt(LineStart), Last.EndPos),
      Outer + 'try' + LineBreak + Body + Outer + 'finally' + LineBreak + Closing + Outer + 'end')])];
  end;

  function CollectLocals(ARoutine: TSyntaxNode): TArray<string>;
  var
    Index: Integer;
    Name: string;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoutine);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if (E <> ARoutine) and (E.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
          Continue;
        if E.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
          for Name in E.Name.Split([',']) do
            Result := Result + [Trim(Name)];
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Aufrufe in E, die Handles öffnen; ATarget ist das Ziel der Zuweisung.
  procedure CollectOpens(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>; var ATargets: TArray<string>);
  var
    Index: Integer;
    Pair: THandlePair;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
          Continue;
        if (E.Kind = TSyntaxKind.Call) and PairOf(CallName(E), Pair) then
        begin
          ACalls := ACalls + [E];
          ATargets := ATargets + [''];
        end;
        for Index := E.ChildCount - 1 downto 0 do
          Pending.Push(E[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Routine, Part, Statement: TSyntaxNode;
  Node: TFlowNode;
  Calls: TArray<TSyntaxNode>;
  Targets: TArray<string>;
  Handles, Leaked: TArray<TOpenedHandle>;
  Handle: TOpenedHandle;
  Index, First: Integer;
  Pair: string;
  Names, Message, Verb: string;
  Never: Boolean;
  Item: THandlePair;
  Fixes: TArray<TRuleFix>;
begin
  if AContext.Tree = nil then
    Exit;
  Table := nil;
  for Pair in Pairs(AContext.Options) do
  begin
    Item.Open := Copy(Pair, 1, Pos('|', Pair) - 1);
    Item.Where := Copy(Pair, Pos('|', Pair) + 1, MaxInt);
    Item.Close := Copy(Item.Where, Pos('|', Item.Where) + 1, MaxInt);
    Item.Where := Copy(Item.Where, 1, Pos('|', Item.Where) - 1);
    Table := Table + [Item];
  end;
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
    LineBreak := #13#10;
  Cache := TRuleDerived.Open(AContext);
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    Locals := CollectLocals(Routine);
    if Locals = nil then
      Continue;
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    for Node in Graph.Nodes do
    begin
      if (Node.Syntax = nil) or not (Node.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) then
        Continue;
      Calls := nil;
      Targets := nil;
      // with: die Anweisungen darin sind eigene Knoten.
      if Node.Syntax.Kind = TSyntaxKind.WithStatement then
        Continue;
      for Part in Parts(Node) do
      begin
        First := Length(Calls);
        CollectOpens(Part, Calls, Targets);
        // H := CreateFile(…) bzw. var H := CreateFile(…): das Ziel nimmt das Handle auf.
        for Index := First to High(Calls) do
          if (Part.Kind = TSyntaxKind.AssignStatement) and (Part.ChildCount = 2) and (Calls[Index] = Part[1]) and
            (Part[0].Kind = TSyntaxKind.Identifier) then
            Targets[Index] := Part[0].Name
          else if (Part.Kind = TSyntaxKind.InlineVar) and (Calls[Index].Parent = Part) then
            Targets[Index] := Trim(Part.Name);
      end;
      for Index := 0 to High(Calls) do
      begin
        if not Opened(Calls[Index], Targets[Index], Handles) then
          Continue;
        Leaked := nil;
        Never := True;
        for Handle in Handles do
          if LeaksFrom(Node, Handle, Calls[Index]) then
          begin
            Leaked := Leaked + [Handle];
            Never := Never and not ClosedAnywhere(Routine, Handle);
          end;
        if Leaked = nil then
          Continue;
        Names := '';
        for Handle in Leaked do
        begin
          if Names <> '' then
            Names := Names + ' und ';
          Names := Names + Handle.Path;
        end;
        Verb := 'wird';
        if Length(Leaked) > 1 then
          Verb := 'werden';
        if Never then
          Message := Format('%s %s nie mit %s geschlossen (Handle-Leck).', [Names, Verb, Leaked[0].CloseName])
        else
          Message := Format('%s %s nicht auf jedem Weg mit %s geschlossen (Handle-Leck).',
            [Names, Verb, Leaked[0].CloseName]);
        Fixes := nil;
        Statement := Node.Syntax;
        if Never and (Node.Kind = TFlowNodeKind.Statement) and (Statement.StartPos.Line = Statement.EndPos.Line) then
          Fixes := WrapFix(Statement, Leaked);
        AReport.Add(NodeRange(Calls[Index]), Message, TRuleConfidence.Medium, Fixes);
      end;
    end;
  end;
end;

{ TOutParamReadRule }

function TOutParamReadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OutParamReadRuleId, TRuleSeverity.Warning,
    'out-Parameter gelesen, bevor er gesetzt ist');
end;

/// <summary>Verwaltete Typen leert der Aufrufer vor dem Aufruf mit out.</summary>
function IsManagedParamType(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ManagedTypes) or MatchText(ATypeName, ['IInterface', 'IUnknown', 'TBytes']) or
    StartsText('TArray<', ATypeName) or StartsText('array of', ATypeName) or
    ((Length(ATypeName) > 1) and (ATypeName[1] = 'I') and CharInSet(ATypeName[2], ['A'..'Z']));
end;

/// <summary>Wird ein Teil von AName (AName.Feld, AName[I]) als Argument übergeben? Ein out-Argument
/// setzt ihn dann, ohne dass der Graph es sieht.</summary>
function PassesPart(ANode: TSyntaxNode; const AName: string): Boolean;
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
      if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Continue;
      if Node.Kind = TSyntaxKind.Call then
        for Index := 1 to Node.ChildCount - 1 do
          if (Node[Index].Kind <> TSyntaxKind.Identifier) and SameText(RootName(Node[Index]), AName) then
            Exit(True);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

procedure TOutParamReadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Block, Params, Param: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Index: Integer;
  Name, TypeName: string;
  Reported: Boolean;

  function FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
  begin
    Result := nil;
    while (ANode <> nil) and (Result = nil) do
    begin
      Result := Graph.NodeOf(ANode);
      ANode := ANode.Parent;
    end;
  end;

  function ShortOf(const AName: string): string;
  begin
    Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
  end;

  function Collapsed(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode <> nil then
      Result := LowerCase(StringReplace(StringReplace(StringReplace(Copy(AContext.Text, ANode.StartOffset + 1,
        ANode.EndOffset - ANode.StartOffset), ' ', '', [rfReplaceAll]), #13, '', [rfReplaceAll]), #10, '',
        [rfReplaceAll]));
  end;

  // Das Token "out" vor dem Parameter mit den Namen ANames in AParams.
  function OutToken(AParams: TSyntaxNode; const ANames: string; out AToken: TPascalToken): Boolean;
  var
    Inner: Integer;
    Token: TPascalToken;
  begin
    Result := False;
    for Inner := 0 to AParams.ChildCount - 1 do
      if (AParams[Inner].Kind = TSyntaxKind.Parameter) and SameText(AParams[Inner].Name, ANames) and
        (AParams[Inner].Modifier = TParameterModifier.OutParam) then
        for Token in AContext.Tree.Tokens do
        begin
          if Token.Offset >= AParams[Inner].EndOffset then
            Break;
          if (Token.Offset >= AParams[Inner].StartOffset) and SameText(Token.Text, 'out') then
          begin
            AToken := Token;
            Exit(True);
          end;
        end;
  end;

  // out -> var in der Implementierung und in jeder Deklaration mit gleicher Parameterliste.
  function Fix(const ANames: string): TArray<TRuleFix>;
  var
    Edits: TArray<TRuleEdit>;
    Token: TPascalToken;
    Key: string;
    Short: string;
    ClassPart: string;

    // Owner: Klasse, in deren Deklaration der Knoten steht ('' außerhalb).
    procedure Declarations(ARoot: TSyntaxNode);
    var
      Child: Integer;
      Node, Other: TSyntaxNode;
      Found: TPascalToken;
      Owner: string;
      Pending: TStack<TSyntaxNode>;
      PendingOwner: TStack<string>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      PendingOwner := TStack<string>.Create;
      try
        Pending.Push(ARoot);
        PendingOwner.Push('');
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          Owner := PendingOwner.Pop;
          if Node.Kind = TSyntaxKind.TypeDecl then
            Owner := Node.Name;
          if (Node.Kind = TSyntaxKind.RoutineHeader) and (Node <> Header) and SameText(ShortOf(Node.Name), Short) and
            SameText(Owner, ClassPart) then
          begin
            Other := Node.FindChild(TSyntaxKind.Parameters);
            if (Other <> nil) and (Collapsed(Other) = Key) and OutToken(Other, ANames, Found) then
              Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Found.StartPos, Found.EndPos), 'var')];
          end;
          // Rümpfe anderer Routinen enthalten keine Deklarationen dieser Routine.
          if Node.Kind = TSyntaxKind.Block then
            Continue;
          for Child := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Child]);
            PendingOwner.Push(Owner);
          end;
        end;
      finally
        PendingOwner.Free;
        Pending.Free;
      end;
    end;

  begin
    Result := nil;
    Edits := nil;
    Key := Collapsed(Params);
    Short := ShortOf(Routine.Name);
    ClassPart := Copy(Routine.Name, 1, Length(Routine.Name) - Length(Short) - 1);
    if Pos('<', ClassPart) > 0 then
      ClassPart := Copy(ClassPart, 1, Pos('<', ClassPart) - 1);
    // Deklarationen stehen vor der Implementierung; die Änderungen bleiben nach Stelle sortiert.
    Declarations(AContext.Tree.Root);
    if OutToken(Params, ANames, Token) then
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Token.StartPos, Token.EndPos), 'var')];
    if Edits <> nil then
      Result := [TRuleFix.Create('out durch var ersetzen', Edits)];
  end;

  procedure Visit(ARoot: TSyntaxNode; const ANames: string);
  var
    Child: Integer;
    Node: TSyntaxNode;
    Flow: TFlowNode;
    Detail: string;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while (Pending.Count > 0) and not Reported do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          Continue;
        if IsName(Node, Name) and not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.AssignStatement) and
          (Node.Parent.ChildCount > 0) and (Node.Parent[0] = Node)) then
        begin
          Flow := FlowNodeOf(Node);
          if (Flow <> nil) and (Graph.IsReachable(Flow) = TFlowAnswer.Yes) and
            Graph.ReachingDefinitions(Flow, Name).FromEntry then
          begin
            if IsManagedParamType(TypeName) then
              Detail := Format('bei %s ist er hier immer leer.', [TypeName])
            else
              Detail := 'sein Wert ist hier undefiniert.';
            AReport.Add(NodeRange(Node), Format('out-Parameter %s wird gelesen, bevor er gesetzt ist; %s',
              [Name, Detail]), TRuleConfidence.High, Fix(ANames));
            Reported := True;
            Exit;
          end;
        end;
        for Child := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Child]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Block := Routine.FindChild(TSyntaxKind.Block);
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    if (Block = nil) or (Header = nil) then
      Continue;
    Params := Header.FindChild(TSyntaxKind.Parameters);
    if Params = nil then
      Continue;
    Graph := nil;
    for Index := 0 to Params.ChildCount - 1 do
    begin
      Param := Params[Index];
      if (Param.Kind <> TSyntaxKind.Parameter) or (Param.Modifier <> TParameterModifier.OutParam) then
        Continue;
      TypeName := '';
      if Param.FindChild(TSyntaxKind.TypeReference) <> nil then
        TypeName := Param.FindChild(TSyntaxKind.TypeReference).Name;
      for Name in Param.Name.Split([',']) do
      begin
        if HasOpaqueUse(Block, Name.Trim) or PassesPart(Block, Name.Trim) then
          Continue;
        if Graph = nil then
          Graph := TRuleDerived.Graph(Cache, AContext, Routine);
        if not Graph.Complete then
          Break;
        Reported := False;
        Visit(Block, Param.Name);
      end;
    end;
  end;
end;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TResultNotSetRule.Create);
  ARegistry.Register(TPossiblyUninitializedRule.Create);
  ARegistry.Register(TUnreachableCodeRule.Create);
  ARegistry.Register(TUseAfterFreeRule.Create);
  ARegistry.Register(TDerefBeforeNilCheckRule.Create);
  ARegistry.Register(TFieldFreeWithoutNilRule.Create);
  ARegistry.Register(TDestructorNotNilSafeRule.Create);
  ARegistry.Register(THandleLeakRule.Create);
  ARegistry.Register(TOutParamReadRule.Create);
end;

end.
