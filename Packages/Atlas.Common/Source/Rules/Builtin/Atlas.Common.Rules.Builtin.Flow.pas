unit Atlas.Common.Rules.Builtin.Flow;

// Flussregeln (#269) auf dem Kontrollflussgraphen (#143):
//   result-not-set            Funktion kann enden, ohne Result zu setzen (wie W1035)
//   possibly-uninitialized    lokale Variable wird möglicherweise vor der ersten
//                             Zuweisung gelesen (wie W1036)
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

/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow;

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

  function Visit(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    case ANode.Kind of
      // Lokale Routinen und anonyme Methoden laufen außerhalb dieses Flusses.
      TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
        Exit(False);
      TSyntaxKind.Call:
        for Index := 1 to ANode.ChildCount - 1 do
          if IsName(ANode[Index], AName) then
            Exit(True);
      TSyntaxKind.AddressOf:
        if (ANode.ChildCount > 0) and SameText(RootName(ANode[0]), AName) then
          Exit(True);
      TSyntaxKind.AssignStatement:
        if (ANode.ChildCount > 0) and (ANode[0].Kind <> TSyntaxKind.Identifier) and
          SameText(RootName(ANode[0]), AName) then
          Exit(True);
      TSyntaxKind.WithStatement:
        for Index := 0 to ANode.ChildCount - 2 do
          if SameText(RootName(ANode[Index]), AName) then
            Exit(True);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      if Visit(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

begin
  Result := Visit(ABlock);
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(True);
  if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
    Exit(False);
  for Index := 0 to ANode.ChildCount - 1 do
    if ContainsKind(ANode[Index], AKind) then
      Exit(True);
  Result := False;
end;

/// <summary>Alle RoutineDecl mit Rumpf, auch lokale.</summary>
procedure CollectRoutines(ANode: TSyntaxNode; var ARoutines: TArray<TSyntaxNode>);
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
    ARoutines := ARoutines + [ANode];
  for Index := 0 to ANode.ChildCount - 1 do
    CollectRoutines(ANode[Index], ARoutines);
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
  Name: string;
begin
  if AContext.Tree = nil then
    Exit;
  Routines := nil;
  CollectRoutines(AContext.Tree.Root, Routines);
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
    Graph := TControlFlowGraph.Build(Routine);
    try
      // Alte Schreibweise: Zuweisung an den Funktionsnamen setzt ebenfalls das Ergebnis.
      if (Graph.MayEndWithout('Result') = TFlowAnswer.Yes) and (Graph.MayEndWithout(Name) = TFlowAnswer.Yes) then
        AReport.Add(HeaderNameRange(AContext, Routine),
          Format('"%s" kann enden, ohne Result zu setzen; der Rückgabewert ist dann undefiniert', [Name]),
          TRuleConfidence.High);
    finally
      Graph.Free;
    end;
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
  procedure Visit(ANode: TSyntaxNode);
  var
    Child: Integer;
    Flow: TFlowNode;
  begin
    if Reported or (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      Exit;
    if IsName(ANode, Name) and not ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
      (ANode.Parent.ChildCount > 0) and (ANode.Parent[0] = ANode)) then
    begin
      Flow := FlowNodeOf(ANode);
      if (Flow <> nil) and (Graph.IsReachable(Flow) = TFlowAnswer.Yes) and
        Graph.ReachingDefinitions(Flow, Name).FromEntry then
      begin
        AReport.Add(NodeRange(ANode),
          Format('"%s" wird hier möglicherweise gelesen, bevor ein Wert zugewiesen wurde', [Name]), Confidence);
        Reported := True;
        Exit;
      end;
    end;
    for Child := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Child]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Routines := nil;
  CollectRoutines(AContext.Tree.Root, Routines);
  for Routine in Routines do
  begin
    Block := Routine.FindChild(TSyntaxKind.Block);
    Graph := nil;
    try
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
              Graph := TControlFlowGraph.Build(Routine);
            if not Graph.Complete then
              Break;
            Reported := False;
            Visit(Block);
          end;
        end;
      end;
    finally
      Graph.Free;
    end;
  end;
end;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TResultNotSetRule.Create);
  ARegistry.Register(TPossiblyUninitializedRule.Create);
end;

end.
