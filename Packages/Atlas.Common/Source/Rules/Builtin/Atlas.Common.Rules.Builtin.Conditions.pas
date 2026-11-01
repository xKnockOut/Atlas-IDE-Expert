unit Atlas.Common.Rules.Builtin.Conditions;

// Bedingungen und Schleifen (#909, Gruppe Fehler finden):
//   constant-condition  Bedingung von if, while oder until steht fest (#1041):
//                       True, False, Vergleiche von Zahlen und untypisierte
//                       Konstanten der Datei, auch über and, or, xor und not;
//                       "X or True" ist immer wahr, "X and False" immer falsch.
//                       while True do und repeat … until False sind gewollte
//                       Endlosschleifen und bleiben still (dafür infinite-loop).
//                       Konstanten aus der Option switchConstants, Konstanten in
//                       einem Zweig von {$IF…} und solche aus anderen Units gelten
//                       als unbekannt. Korrektur bei if: toten Zweig entfernen
//                       bzw. die Bedingung entfernen (Zweig bleibt).
//   infinite-loop       while mit immer wahrer bzw. repeat mit immer falscher
//                       Bedingung ohne Ausgang im Rumpf (#1042): kein Break (in
//                       verschachtelten Schleifen zählt es nicht), Exit, raise,
//                       goto, Halt, Abort oder RunError, kein Aufruf einer
//                       Routine der Datei, die eine Ausnahme auslöst bzw. das
//                       Programm beendet, und keine Prüfung von Terminated (dafür
//                       thread-loop-without-terminated). Anonyme Methoden im
//                       Rumpf zählen nicht. Steht die Schleife im try-Teil eines
//                       try … except derselben Routine, endet sie gewollt über
//                       eine Ausnahme (lesen bis EJsonRpcTransportClosed) und
//                       bleibt still. Aktion: Sprung zum Schleifenkopf.
//   loop-condition-unchanged
//                       Keine Variable der while- bzw. until-Bedingung ändert sich
//                       im Rumpf (#1043): typisch das vergessene Inc(I). Gemeldet
//                       nur, wenn jede Variable der Bedingung eine lokale Variable
//                       bzw. ein Wertparameter der Routine ist und mindestens eine
//                       direkt (nicht nur über X.Eigenschaft) vorkommt. Still bei
//                       Aufrufen in der Bedingung, Feldern, globalen Variablen,
//                       var-/out-Parametern, Terminated, with im Rumpf, Ausgängen
//                       (wie infinite-loop), Warteschleifen (Sleep, ProcessMessages
//                       …), Aufrufen lokaler Routinen und Variablen, die eine
//                       anonyme Methode erfasst. Als Änderung gilt: Zuweisung,
//                       Argument eines Aufrufs (var möglich), X.Methode bzw. jeder
//                       Zugriff X.Name im Rumpf, @X und for X; über X[…] nur, wenn
//                       die Bedingung X[…] liest.
//   redundant-jump      Exit als letzte Anweisung einer Routine bzw. anonymen
//                       Methode und Continue als letzte Anweisung eines
//                       Schleifenrumpfs (#1141, Stil): Sie ändern den Ablauf nicht.
//                       Continue zählt auch im letzten Zweig eines if am Ende des
//                       Rumpfs (then nur ohne else; then Continue else … ist ein
//                       Wächter der Kette) und in begin … end. Still: Exit(Wert), Exit in
//                       inneren Blöcken (if, try, case), Sprünge in try … finally
//                       bzw. try … except, Anweisungen mit Marke und Rümpfe mit
//                       bedingten Direktiven. Korrektur „Anweisung entfernen“,
//                       wenn die Anweisung in einem begin … end steht.
//   loop-runs-at-most-once
//                       Jeder Weg durch den Rumpf einer for-, for-in-, while- oder
//                       repeat-Schleife endet mit Exit, Break, raise, Halt, Abort,
//                       RunError, ExitProcess oder dem Aufruf einer Routine der
//                       Datei, die auf jedem Weg eine Ausnahme auslöst (#1131):
//                       Die Schleife läuft höchstens einmal. Ein Weg zählt als
//                       Sprung bei if mit else und beiden Zweigen, case mit else
//                       und allen Zweigen, try … finally mit try- oder
//                       finally-Teil, try … except mit try-Teil und jedem
//                       Behandler. Still bei
//                       Continue dieser Schleife, goto bzw. Marken und bedingten
//                       Direktiven im Rumpf (der Baum enthält alle Zweige); ein
//                       Break innerer Schleifen zählt nicht, TMonitor.Exit(…)
//                       ist kein Sprung. Option allowFirstElement: for-in, in
//                       dem keine Bedingung die Schleifenvariable liest („erstes
//                       Element holen“), bleibt still. Keine Korrektur, die Absicht ist unklar; steht der
//                       Sprung direkt hinter einem if ohne else, fragt die
//                       Meldung, ob er in den if-Zweig gehört.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ConstantConditionRuleId = 'constant-condition';
  InfiniteLoopRuleId = 'infinite-loop';
  LoopConditionUnchangedRuleId = 'loop-condition-unchanged';
  RedundantJumpRuleId = 'redundant-jump';
  LoopRunsAtMostOnceRuleId = 'loop-runs-at-most-once';

type
  TConstantConditionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInfiniteLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopConditionUnchangedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRedundantJumpRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopRunsAtMostOnceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Options;

type
  TTokens = TArray<TPascalToken>;

  TConstantKind = (Unknown, Bool, Int);

  /// <summary>Wert eines Ausdrucks; Shown ist der Teil, der den Wert festlegt (z. B. "… or True").</summary>
  TConstantValue = record
    Kind: TConstantKind;
    Bool: Boolean;
    Int: Int64;
    Shown: string;
    class function Unknown: TConstantValue; static;
    class function OfBool(AValue: Boolean; const AShown: string): TConstantValue; static;
    class function OfInt(AValue: Int64): TConstantValue; static;
  end;

  /// <summary>Wertet Bedingungen aus dem Syntaxbaum aus; Namen über die Namensauflösung.</summary>
  TConditionValues = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FFileName: string;
    FResolver: TNameResolver;
    FPaths: TArray<string>;
    FSwitches: TArray<string>;
    /// <summary>Untypisierte Konstanten der Datei außerhalb von {$IF…}, Schlüssel klein.</summary>
    FConstants: TDictionary<string, Boolean>;
    FDepth: Integer;
    procedure CollectConstants(ANode: TSyntaxNode);
    function FirstToken(AOffset: Integer): Integer;
    function HasDirective(ANode: TSyntaxNode): Boolean;
    function IsPlainConstant(ANode: TSyntaxNode): Boolean;
    function FindConstant(ANode: TSyntaxNode; const AName: string; const APosition: TTextPosition): TSyntaxNode;
    function NameValue(ANode: TSyntaxNode): TConstantValue;
    function Binary(ANode: TSyntaxNode; const ALeft, ARight: TConstantValue): TConstantValue;
    function Unary(ANode: TSyntaxNode; const AInner: TConstantValue): TConstantValue;
  public
    constructor Create(ATree: TSyntaxTree; const AText, AFileName: string; AResolver: TNameResolver;
      const ASwitches: TArray<string>);
    destructor Destroy; override;
    function Evaluate(ANode: TSyntaxNode): TConstantValue;
    /// <summary>Steht in der Bedingung ANode oder direkt davor bzw. dahinter eine Direktive (bedingter Teil)?</summary>
    function Conditional(ANode: TSyntaxNode): Boolean;
  end;

/// <summary>Dateiname für die Namensauflösung: Pfad, sonst relativer Pfad, sonst Unit-Name.</summary>
function RuleFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

{ TConstantValue }

class function TConstantValue.Unknown: TConstantValue;
begin
  Result := Default(TConstantValue);
end;

class function TConstantValue.OfBool(AValue: Boolean; const AShown: string): TConstantValue;
begin
  Result := Default(TConstantValue);
  Result.Kind := TConstantKind.Bool;
  Result.Bool := AValue;
  Result.Shown := AShown;
end;

class function TConstantValue.OfInt(AValue: Int64): TConstantValue;
begin
  Result := Default(TConstantValue);
  Result.Kind := TConstantKind.Int;
  Result.Int := AValue;
end;

function BoolText(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'True';
  end
  else
  begin
    Result := 'False';
  end;
end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

function IsBoolLiteral(ANode: TSyntaxNode; AValue: Boolean): Boolean;
begin
  ANode := Unwrapped(ANode);
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, BoolText(AValue));
end;

{ TConditionValues }

constructor TConditionValues.Create(ATree: TSyntaxTree; const AText, AFileName: string; AResolver: TNameResolver;
  const ASwitches: TArray<string>);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FFileName := AFileName;
  FResolver := AResolver;
  FSwitches := ASwitches;
  FPaths := TConditionalBranches.Paths(ATree.Tokens);
  FConstants := TDictionary<string, Boolean>.Create;
  if ATree.Root <> nil then
  begin
    CollectConstants(ATree.Root);
  end;
end;

destructor TConditionValues.Destroy;
begin
  FConstants.Free;
  inherited;
end;

function TConditionValues.FirstToken(AOffset: Integer): Integer;
var
  Lo, Hi, Middle: Integer;
begin
  Lo := 0;
  Hi := Length(FTree.Tokens);
  while Lo < Hi do
  begin
    Middle := (Lo + Hi) div 2;
    if FTree.Tokens[Middle].Offset < AOffset then
    begin
      Lo := Middle + 1;
    end
    else
    begin
      Hi := Middle;
    end;
  end;
  Result := Lo;
end;

function TConditionValues.HasDirective(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := FirstToken(ANode.StartOffset);
  while (Index <= High(FTree.Tokens)) and (FTree.Tokens[Index].Offset < ANode.EndOffset) do
  begin
    if FTree.Tokens[Index].Kind = TPascalTokenKind.Directive then
    begin
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

function TConditionValues.Conditional(ANode: TSyntaxNode): Boolean;
var
  First, Last, Index: Integer;
begin
  // Vom Schlüsselwort vor der Bedingung (if, while, until) bis zu dem dahinter (then, do, ;).
  First := FirstToken(ANode.StartOffset) - 1;
  while (First > 0) and (FTree.Tokens[First].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(First);
  end;
  Last := FirstToken(ANode.EndOffset);
  while (Last < High(FTree.Tokens)) and
    (FTree.Tokens[Last].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(Last);
  end;
  for Index := First + 1 to Last - 1 do
  begin
    if FTree.Tokens[Index].Kind = TPascalTokenKind.Directive then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TConditionValues.IsPlainConstant(ANode: TSyntaxNode): Boolean;
var
  Index, Values: Integer;
begin
  // Name = Wert; ohne Typ (sonst typisierte Konstante), ohne Direktive, außerhalb von {$IF…}.
  Values := 0;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind <> TSyntaxKind.Directive then
    begin
      Inc(Values);
    end;
  end;
  Result := (Values = 1) and not HasDirective(ANode) and
    (TConditionalBranches.PathAt(FPaths, FirstToken(ANode.StartOffset)) = '');
end;

procedure TConditionValues.CollectConstants(ANode: TSyntaxNode);
var
  Index: Integer;
  Node: TSyntaxNode;
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
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.ConstDecl) and IsPlainConstant(Node) and not MatchText(Node.Name, FSwitches) then
      begin
        FConstants.AddOrSetValue(LowerCase(Node.Name), True);
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

function TConditionValues.FindConstant(ANode: TSyntaxNode; const AName: string;
  const APosition: TTextPosition): TSyntaxNode;
var
  Index: Integer;
  Child: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // ConstDecl mit dem Namen, die APosition enthält. Iterativ (Bericht M1).
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    for Index := ANode.ChildCount - 1 downto 0 do
    begin
      Pending.Push(ANode[Index]);
    end;
    while Pending.Count > 0 do
    begin
      Child := Pending.Pop;
      if (Child.StartPos.Line > APosition.Line) or ((Child.EndPos.Line < APosition.Line)) then
      begin
        Continue;
      end;
      if (Child.Kind = TSyntaxKind.ConstDecl) and SameText(Child.Name, AName) then
      begin
        Exit(Child);
      end;
      for Index := Child.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Child[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TConditionValues.NameValue(ANode: TSyntaxNode): TConstantValue;
var
  Resolved: TResolvedSymbol;
  Declaration: TSyntaxNode;
  Index: Integer;
begin
  Result := TConstantValue.Unknown;
  if SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False') then
  begin
    Exit(TConstantValue.OfBool(SameText(ANode.Name, 'True'), ANode.Name));
  end;
  if not FConstants.ContainsKey(LowerCase(ANode.Name)) or (FDepth >= 8) then
  begin
    Exit;
  end;
  Resolved := FResolver.ResolveChain(FTree, FFileName, [ANode.Name], ANode.StartOffset);
  if not Resolved.Found or (Resolved.SymbolKind <> TIndexSymbolKind.Constant) or
    not ((Resolved.Kind = TResolvedKind.Local) or (Resolved.FileName = '') or
    SameText(Resolved.FileName, FFileName)) then
  begin
    Exit;
  end;
  Declaration := FindConstant(FTree.Root, ANode.Name, Resolved.Range.StartPos);
  if (Declaration = nil) or not IsPlainConstant(Declaration) then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    for Index := Declaration.ChildCount - 1 downto 0 do
    begin
      if Declaration[Index].Kind <> TSyntaxKind.Directive then
      begin
        Result := Evaluate(Declaration[Index]);
        Break;
      end;
    end;
  finally
    Dec(FDepth);
  end;
  if Result.Kind = TConstantKind.Bool then
  begin
    Result.Shown := ANode.Name + ' = ' + BoolText(Result.Bool);
  end;
end;

function TConditionValues.Binary(ANode: TSyntaxNode; const ALeft, ARight: TConstantValue): TConstantValue;
var
  Left, Right: TConstantValue;
  Op: string;
  Compared: Integer;
begin
  Result := TConstantValue.Unknown;
  Op := ANode.Name;
  Left := ALeft;
  Right := ARight;
  if (Op = 'and') or (Op = 'or') then
  begin
    // Ein fester Operand entscheidet allein: X or True, False and X.
    if (Left.Kind = TConstantKind.Bool) and (Left.Bool = (Op = 'or')) then
    begin
      Exit(TConstantValue.OfBool(Left.Bool, Left.Shown + ' ' + Op + ' …'));
    end;
    if (Right.Kind = TConstantKind.Bool) and (Right.Bool = (Op = 'or')) then
    begin
      Exit(TConstantValue.OfBool(Right.Bool, '… ' + Op + ' ' + Right.Shown));
    end;
    if (Left.Kind = TConstantKind.Bool) and (Right.Kind = TConstantKind.Bool) then
    begin
      Exit(TConstantValue.OfBool(Right.Bool, NodeText(FText, ANode)));
    end;
    Exit;
  end;
  if (Left.Kind = TConstantKind.Unknown) or (Left.Kind <> Right.Kind) then
  begin
    Exit;
  end;
  if Left.Kind = TConstantKind.Bool then
  begin
    if Op = 'xor' then
    begin
      Exit(TConstantValue.OfBool(Left.Bool <> Right.Bool, NodeText(FText, ANode)));
    end;
    Compared := Ord(Left.Bool) - Ord(Right.Bool);
  end
  else
  begin
    if Op = '+' then
    begin
      Exit(TConstantValue.OfInt(Left.Int + Right.Int));
    end;
    if Op = '-' then
    begin
      Exit(TConstantValue.OfInt(Left.Int - Right.Int));
    end;
    if Op = '*' then
    begin
      Exit(TConstantValue.OfInt(Left.Int * Right.Int));
    end;
    if ((Op = 'div') or (Op = 'mod')) and (Right.Int <> 0) then
    begin
      if Op = 'div' then
      begin
        Exit(TConstantValue.OfInt(Left.Int div Right.Int));
      end;
      Exit(TConstantValue.OfInt(Left.Int mod Right.Int));
    end;
    if Left.Int < Right.Int then
    begin
      Compared := -1;
    end
    else if Left.Int > Right.Int then
    begin
      Compared := 1;
    end
    else
    begin
      Compared := 0;
    end;
  end;
  if Op = '=' then
  begin
    Result := TConstantValue.OfBool(Compared = 0, '');
  end
  else if Op = '<>' then
  begin
    Result := TConstantValue.OfBool(Compared <> 0, '');
  end
  else if Op = '<' then
  begin
    Result := TConstantValue.OfBool(Compared < 0, '');
  end
  else if Op = '>' then
  begin
    Result := TConstantValue.OfBool(Compared > 0, '');
  end
  else if Op = '<=' then
  begin
    Result := TConstantValue.OfBool(Compared <= 0, '');
  end
  else if Op = '>=' then
  begin
    Result := TConstantValue.OfBool(Compared >= 0, '');
  end;
  if Result.Kind = TConstantKind.Bool then
  begin
    Result.Shown := NodeText(FText, ANode);
  end;
end;

function TConditionValues.Unary(ANode: TSyntaxNode; const AInner: TConstantValue): TConstantValue;
begin
  Result := TConstantValue.Unknown;
  if (ANode.Name = 'not') and (AInner.Kind = TConstantKind.Bool) then
  begin
    Result := TConstantValue.OfBool(not AInner.Bool, 'not ' + AInner.Shown);
  end
  else if (ANode.Name = '-') and (AInner.Kind = TConstantKind.Int) then
  begin
    Result := TConstantValue.OfInt(-AInner.Int);
  end
  else if (ANode.Name = '+') and (AInner.Kind = TConstantKind.Int) then
  begin
    Result := AInner;
  end;
end;

function TConditionValues.Evaluate(ANode: TSyntaxNode): TConstantValue;
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Values: TStack<TConstantValue>;
  Entry: TSyntaxPostOrderEntry;
  Node: TSyntaxNode;
  Value, Left, Right: TConstantValue;
  Number: Int64;
begin
  // Iterativ (Bericht M1): Nachordnung mit Wertestapel; lange Ketten wie 1 - 1 - … - 1 sind tiefe Bäume.
  Pending := TStack<TSyntaxPostOrderEntry>.Create;
  Values := TStack<TConstantValue>.Create;
  try
    Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      Node := Entry.Node;
      if Entry.Done then
      begin
        // Operanden liegen in der Reihenfolge links, rechts auf dem Wertestapel.
        case Node.Kind of
          TSyntaxKind.ParenExpr:
            Value := Values.Pop;
          TSyntaxKind.UnaryExpr:
            Value := Unary(Node, Values.Pop);
        else
          Right := Values.Pop;
          Left := Values.Pop;
          Value := Binary(Node, Left, Right);
        end;
        Values.Push(Value);
        Continue;
      end;
      Value := TConstantValue.Unknown;
      if Node <> nil then
        case Node.Kind of
          TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr:
            if Node.ChildCount = 1 then
            begin
              Pending.Push(TSyntaxPostOrderEntry.Create(Node, True));
              Pending.Push(TSyntaxPostOrderEntry.Create(Node[0], False));
              Continue;
            end;
          TSyntaxKind.Identifier:
            Value := NameValue(Node);
          TSyntaxKind.Literal:
            if TOrdinalConstants.TryNumber(Node.Name, Number) then
            begin
              Value := TConstantValue.OfInt(Number);
            end;
          TSyntaxKind.BinaryExpr:
            if Node.ChildCount = 2 then
            begin
              Pending.Push(TSyntaxPostOrderEntry.Create(Node, True));
              Pending.Push(TSyntaxPostOrderEntry.Create(Node[1], False));
              Pending.Push(TSyntaxPostOrderEntry.Create(Node[0], False));
              Continue;
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      Values.Push(Value);
    end;
    Result := Values.Pop;
  finally
    Values.Free;
    Pending.Free;
  end;
end;

{ TConstantConditionRule }

function TConstantConditionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConstantConditionRuleId, TRuleSeverity.Warning, 'Bedingung ist immer gleich');
end;

/// <summary>Text des Knotens; Folgezeilen um die Spalte des Knotens gegenüber AColumn ausgerückt.</summary>
function Outdented(const AText: string; ANode: TSyntaxNode; AColumn: Integer): string;
var
  Lines: TArray<string>;
  LineBreak: string;
  Index, Shift, Remove: Integer;
begin
  Lines := TTextLines.SplitLines(NodeText(AText, ANode), LineBreak);
  Shift := ANode.StartPos.Character - AColumn;
  if Shift > 0 then
  begin
    for Index := 1 to High(Lines) do
    begin
      Remove := TTextLines.IndentLength(Lines[Index]);
      if Remove > Shift then
      begin
        Remove := Shift;
      end;
      Lines[Index] := Copy(Lines[Index], Remove + 1, MaxInt);
    end;
  end;
  Result := TTextLines.JoinLines(Lines, LineBreak);
end;

/// <summary>Bereich, der eine ganze Anweisung entfernt: mit folgendem Semikolon und, wenn sie allein auf ihren
/// Zeilen steht, mit den Zeilen.</summary>
function StatementRemoval(const AText: string; ANode: TSyntaxNode): TTextRange;
var
  Lines: TLineTable;
  First, Last, Probe: Integer;
begin
  Lines := TLineTable.Build(AText);
  First := ANode.StartOffset;
  Last := ANode.EndOffset;
  Probe := Last;
  while (Probe < Length(AText)) and CharInSet(AText[Probe + 1], [' ', #9]) do
  begin
    Inc(Probe);
  end;
  if (Probe < Length(AText)) and (AText[Probe + 1] = ';') then
  begin
    Last := Probe + 1;
  end;
  Probe := Last;
  while (Probe < Length(AText)) and CharInSet(AText[Probe + 1], [' ', #9]) do
  begin
    Inc(Probe);
  end;
  if ((Probe = Length(AText)) or CharInSet(AText[Probe + 1], [#13, #10])) and
    (Trim(Copy(AText, Lines.LineStart(ANode.StartPos.Line) + 1, First - Lines.LineStart(ANode.StartPos.Line))) = '') then
  begin
    First := Lines.LineStart(ANode.StartPos.Line);
    Last := Lines.LineStart(Lines.PositionAt(Probe).Line + 1);
    if Last <= Probe then
    begin
      Last := Probe;
    end;
  end;
  Result := TTextRange.Create(Lines.PositionAt(First), Lines.PositionAt(Last));
end;

procedure TConstantConditionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Values: TConditionValues;
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;

  procedure ReportIf(ANode: TSyntaxNode; const AValue: TConstantValue);
  var
    Message: string;
    Fixes: TArray<TRuleFix>;
    Branch: TSyntaxNode;
  begin
    if AValue.Bool then
    begin
      Message := Format('Die Bedingung ist immer wahr (%s).', [AValue.Shown]);
    end
    else
    begin
      Message := Format('Die Bedingung ist immer falsch (%s).', [AValue.Shown]);
    end;
    Fixes := nil;
    Branch := nil;
    if AValue.Bool and (ANode.ChildCount >= 2) then
    begin
      Branch := ANode[1];
    end
    else if not AValue.Bool and (ANode.ChildCount >= 3) then
    begin
      Branch := ANode[2];
    end;
    if (Branch <> nil) and (Branch.Kind <> TSyntaxKind.EmptyStatement) then
    begin
      if AValue.Bool then
      begin
        Fixes := [TRuleFix.Create('Bedingung entfernen', [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, Branch, ANode.StartPos.Character))])];
      end
      else
      begin
        Fixes := [TRuleFix.Create('Toten Zweig entfernen', [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, Branch, ANode.StartPos.Character))])];
      end;
    end
    else if not AValue.Bool then
    begin
      Fixes := [TRuleFix.Create('Toten Zweig entfernen', [TRuleEdit.Create(StatementRemoval(AContext.Text, ANode),
        '')])];
    end;
    AReport.Add(NodeRange(ANode[0]), Message, TRuleConfidence.High, Fixes);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Condition: TSyntaxNode;
    Value: TConstantValue;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Condition := nil;
        case Node.Kind of
          TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement:
            if Node.ChildCount > 0 then
            begin
              Condition := Node[0];
            end;
          TSyntaxKind.RepeatStatement:
            if Node.ChildCount > 0 then
            begin
              Condition := Node[Node.ChildCount - 1];
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if (Condition <> nil) and not Values.Conditional(Condition) then
        begin
          Value := Values.Evaluate(Condition);
          // while True do und repeat … until False: gewollte Endlosschleife (infinite-loop prüft den Ausgang).
          if (Value.Kind = TConstantKind.Bool) and
            not ((Node.Kind = TSyntaxKind.WhileStatement) and IsBoolLiteral(Condition, True)) and
            not ((Node.Kind = TSyntaxKind.RepeatStatement) and IsBoolLiteral(Condition, False)) then
          begin
            if Node.Kind = TSyntaxKind.IfStatement then
            begin
              ReportIf(Node, Value);
            end
            else if Value.Bool then
            begin
              AReport.Add(NodeRange(Condition), Format('Die Bedingung ist immer wahr (%s).', [Value.Shown]),
                TRuleConfidence.High);
            end
            else
            begin
              AReport.Add(NodeRange(Condition), Format('Die Bedingung ist immer falsch (%s).', [Value.Shown]),
                TRuleConfidence.High);
            end;
          end;
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := RuleFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  Values := TConditionValues.Create(AContext.Tree, AContext.Text, FileName, Resolver,
    TRuleOptions.Strings(AContext.Options, 'switchConstants', []));
  try
    Visit(AContext.Tree.Root);
  finally
    Values.Free;
    Resolver.UnpinTree;
  end;
end;

{ TInfiniteLoopRule }

const
  // Aufrufe, die die Schleife verlassen: über die Routine, das Programm oder eine Ausnahme.
  LeavingCalls: array[0..4] of string = ('Exit', 'Halt', 'Abort', 'RunError', 'ExitProcess');
  // Aufrufe, die das Programm beenden oder eine Ausnahme auslösen.
  RaisingCalls: array[0..3] of string = ('Halt', 'Abort', 'RunError', 'ExitProcess');

function TInfiniteLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InfiniteLoopRuleId, TRuleSeverity.Error, 'Schleife ohne Ausgang');
end;

/// <summary>Letzter Teil des Namens einer Routine: "TFoo.Bar" → "Bar".</summary>
function ShortName(const AName: string): string;
var
  Dot: Integer;
begin
  Result := AName;
  Dot := Result.LastIndexOf('.');
  if Dot >= 0 then
  begin
    Result := Copy(Result, Dot + 2, MaxInt);
  end;
end;

/// <summary>Name eines Aufrufs (Bezeichner, Kette X.Name, Name(…)); '' sonst.</summary>
function CalledName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
  begin
    ANode := ANode[0];
  end;
  if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    Result := ANode.Name;
  end;
end;

/// <summary>Name eines Sprungs ohne Qualifizierer (Exit, Break, Halt, Exit(X)); '' sonst. TMonitor.Exit(…) ist
/// kein Sprung.</summary>
function JumpName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
  begin
    ANode := ANode[0];
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end;
end;

/// <summary>Löst ANode (ohne anonyme Methoden) eine Ausnahme aus oder beendet das Programm, direkt oder über
/// eine Routine aus ARaising?</summary>
function Raises(ANode: TSyntaxNode; ARaising: TDictionary<string, Boolean>): Boolean;
var
  Index: Integer;
  Name: string;
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
      if Node.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      if Node.Kind = TSyntaxKind.RaiseStatement then
      begin
        Exit(True);
      end;
      if Node.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier] then
      begin
        Name := CalledName(Node);
        if MatchText(Name, RaisingCalls) or ((Name <> '') and ARaising.ContainsKey(LowerCase(Name))) then
        begin
          Exit(True);
        end;
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

/// <summary>Kurznamen (klein) der Routinen der Datei, die eine Ausnahme auslösen oder das Programm beenden.</summary>
function RaisingRoutines(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  Routines: TList<TSyntaxNode>;
  Changed: Boolean;
  Routine: TSyntaxNode;

  procedure Collect(ARoot: TSyntaxNode);
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
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routines.Add(Node);
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

begin
  Result := TDictionary<string, Boolean>.Create;
  Routines := TList<TSyntaxNode>.Create;
  try
    if ATree.Root <> nil then
    begin
      Collect(ATree.Root);
    end;
    // Bis nichts mehr dazukommt: A ruft B, B löst aus.
    repeat
      Changed := False;
      for Routine in Routines do
      begin
        if not Result.ContainsKey(LowerCase(ShortName(Routine.Name))) and (Routine.FindChild(TSyntaxKind.Block) <> nil) and
          Raises(Routine.FindChild(TSyntaxKind.Block), Result) then
        begin
          Result.Add(LowerCase(ShortName(Routine.Name)), True);
          Changed := True;
        end;
      end;
    until not Changed;
  finally
    Routines.Free;
  end;
end;

/// <summary>Hat ANode einen Ausgang aus der Schleife? AInner: ANode liegt in einer inneren Schleife, ein Break
/// verlässt nur diese.</summary>
function HasExit(ANode: TSyntaxNode; AInner: Boolean; ARaising: TDictionary<string, Boolean>): Boolean;
var
  Index: Integer;
  Name: string;
  Inner: Boolean;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
  PendingInner: TStack<Boolean>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  PendingInner := TStack<Boolean>.Create;
  try
    Pending.Push(ANode);
    PendingInner.Push(AInner);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Inner := PendingInner.Pop;
      case Node.Kind of
        TSyntaxKind.AnonymousMethod:
          Continue;
        TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
          Exit(True);
        TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call:
          begin
            Name := CalledName(Node);
            if SameText(Name, 'Terminated') or MatchText(JumpName(Node), LeavingCalls) or
              ((Name <> '') and ARaising.ContainsKey(LowerCase(Name))) then
            begin
              Exit(True);
            end;
            if SameText(JumpName(Node), 'Break') and not Inner then
            begin
              Exit(True);
            end;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Inner := Inner or (Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
        TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
        PendingInner.Push(Inner);
      end;
    end;
  finally
    PendingInner.Free;
    Pending.Free;
  end;
end;

/// <summary>Steht ANode im try-Teil eines try … except derselben Routine?</summary>
function InTryExcept(ANode: TSyntaxNode): Boolean;
var
  Child, Parent: TSyntaxNode;
begin
  Child := ANode;
  Parent := ANode.Parent;
  while (Parent <> nil) and not (Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    if (Parent.Kind = TSyntaxKind.TryStatement) and (Child.Kind <> TSyntaxKind.ExceptBlock) and
      (Child.Kind <> TSyntaxKind.FinallyBlock) and (Parent.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
    begin
      Exit(True);
    end;
    Child := Parent;
    Parent := Parent.Parent;
  end;
  Result := False;
end;

procedure TInfiniteLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Values: TConditionValues;
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  Raising: TDictionary<string, Boolean>;
  FileName: string;

  function Endless(ALoop: TSyntaxNode): Boolean;
  var
    Index, First, Last: Integer;
    Value: TConstantValue;
  begin
    Result := False;
    if ALoop.ChildCount = 0 then
    begin
      Exit;
    end;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      Value := Values.Evaluate(ALoop[0]);
      if (Value.Kind <> TConstantKind.Bool) or not Value.Bool or Values.Conditional(ALoop[0]) then
      begin
        Exit;
      end;
      First := 1;
      Last := ALoop.ChildCount - 1;
    end
    else
    begin
      Value := Values.Evaluate(ALoop[ALoop.ChildCount - 1]);
      if (Value.Kind <> TConstantKind.Bool) or Value.Bool or Values.Conditional(ALoop[ALoop.ChildCount - 1]) then
      begin
        Exit;
      end;
      First := 0;
      Last := ALoop.ChildCount - 2;
    end;
    for Index := First to Last do
    begin
      if HasExit(ALoop[Index], False, Raising) then
      begin
        Exit;
      end;
    end;
    Result := not InTryExcept(ALoop);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Condition: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and Endless(Node) then
        begin
          if Node.Kind = TSyntaxKind.WhileStatement then
          begin
            AReport.Add(TTextRange.Create(Node.StartPos, Node[0].EndPos),
              'Die Schleife hat keinen Ausgang (kein Break, Exit oder raise).', TRuleConfidence.High);
          end
          else
          begin
            Condition := Node[Node.ChildCount - 1];
            AReport.Add(NodeRange(Condition), 'Die Schleife hat keinen Ausgang (kein Break, Exit oder raise).',
              TRuleConfidence.High, [TRuleFix.Jump('Zum Schleifenkopf springen', Node.StartPos)]);
          end;
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := RuleFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  Values := TConditionValues.Create(AContext.Tree, AContext.Text, FileName, Resolver, nil);
  Raising := RaisingRoutines(AContext.Tree);
  try
    Visit(AContext.Tree.Root);
  finally
    Raising.Free;
    Values.Free;
    Resolver.UnpinTree;
  end;
end;

{ TLoopConditionUnchangedRule }

const
  // Warteschleifen: Ein anderer Thread oder eine Nachricht ändert den Zustand.
  WaitingCalls: array[0..8] of string = ('Sleep', 'ProcessMessages', 'WaitFor', 'Yield', 'SpinWait',
    'WaitForSingleObject', 'WaitForMultipleObjects', 'CheckSynchronize', 'HandleMessage');

type
  /// <summary>Variable der Bedingung: Plain = kommt direkt vor (nicht nur X.Name), Indexed = X[…] in der
  /// Bedingung.</summary>
  TLoopVariable = record
    Name: string;
    Plain: Boolean;
    Indexed: Boolean;
  end;

function TLoopConditionUnchangedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LoopConditionUnchangedRuleId, TRuleSeverity.Warning,
    'Schleifenbedingung ändert sich im Rumpf nie');
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Erster Bezeichner einer Kette X.A[…].B^ bzw. (X); nil, wenn die Kette nicht mit einem Bezeichner
/// beginnt. AViaIndex: direkt auf den Bezeichner folgt [ ].</summary>
function ChainRoot(ANode: TSyntaxNode; out AViaIndex: Boolean): TSyntaxNode;
var
  Previous: TSyntaxNode;
begin
  AViaIndex := False;
  Previous := nil;
  Result := ANode;
  while (Result <> nil) and (Result.ChildCount > 0) and ((Result.Kind in [TSyntaxKind.MemberAccess,
    TSyntaxKind.IndexAccess, TSyntaxKind.Call, TSyntaxKind.Dereference]) or
    ((Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1))) do
  begin
    Previous := Result;
    Result := Result[0];
  end;
  if (Result = nil) or (Result.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit(nil);
  end;
  AViaIndex := (Previous <> nil) and (Previous.Kind = TSyntaxKind.IndexAccess);
end;

/// <summary>Enthält der Teilbaum einen Knoten der Art AKind?</summary>
function Contains(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
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
      if Node.Kind = AKind then
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

/// <summary>Kommt im Teilbaum ein Bezeichner aus ANames vor (auch als Aufruf)?</summary>
function Mentions(ANode: TSyntaxNode; const ANames: array of string): Boolean;
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
      if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(Node.Name, ANames) then
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

procedure TLoopConditionUnchangedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  Raising: TDictionary<string, Boolean>;
  FileName: string;

  function Routine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    begin
      Result := Result.Parent;
    end;
  end;

  // Lokale Routinen (Namen) innerhalb von ARoutine.
  function NestedRoutines(ARoutine: TSyntaxNode): TArray<string>;
  var
    Names: TArray<string>;

    procedure Collect(ARoot: TSyntaxNode);
    var
      Index: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        for Index := ARoot.ChildCount - 1 downto 0 do
        begin
          Pending.Push(ARoot[Index]);
        end;
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if Node.Kind = TSyntaxKind.RoutineDecl then
          begin
            Names := Names + [ShortName(Node.Name)];
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

  begin
    Names := nil;
    Collect(ARoutine);
    Result := Names;
  end;

  // Werden Namen aus ANames in einer anonymen Methode von ARoutine erfasst?
  function Captured(ARoot: TSyntaxNode; const ANames: TArray<string>): Boolean;
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
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          if Mentions(Node, ANames) then
          begin
            Exit(True);
          end;
          Continue;
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

  // Parameter-Knoten, dessen Bereich APosition enthält; nil sonst.
  function ParameterAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
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
        if not Before(Node.StartPos, APosition) or not Before(APosition, Node.EndPos) then
        begin
          Continue;
        end;
        if Node.Kind = TSyntaxKind.Parameter then
        begin
          Exit(Node);
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

  // Variablen der Bedingung; False, wenn die Bedingung etwas enthält, das die Regel nicht beurteilt.
  function ConditionVariables(ACondition, ARoutine: TSyntaxNode; out AVariables: TArray<TLoopVariable>): Boolean;
  var
    Failed: Boolean;

    procedure Add(ANode: TSyntaxNode);
    var
      Resolved: TResolvedSymbol;
      Parameter: TSyntaxNode;
      Index: Integer;
      Plain, Indexed: Boolean;
    begin
      if MatchText(ANode.Name, ['True', 'False', 'nil']) then
      begin
        Exit;
      end;
      if SameText(ANode.Name, 'Self') or SameText(ANode.Name, 'Terminated') then
      begin
        Failed := True;
        Exit;
      end;
      Resolved := Resolver.ResolveChain(AContext.Tree, FileName, [ANode.Name], ANode.StartOffset);
      if not Resolved.Found then
      begin
        Failed := True;
        Exit;
      end;
      if Resolved.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember] then
      begin
        Exit;
      end;
      // Nur Variablen und Wertparameter, die in dieser Routine deklariert sind.
      if (Resolved.Kind <> TResolvedKind.Local) or (Resolved.SymbolKind <> TIndexSymbolKind.Variable) or
        not Before(ARoutine.StartPos, Resolved.Range.StartPos) or not Before(Resolved.Range.EndPos, ARoutine.EndPos) then
      begin
        Failed := True;
        Exit;
      end;
      if Resolved.IsParameter then
      begin
        Parameter := ParameterAt(ARoutine, Resolved.SelectionRange.StartPos);
        if (Parameter = nil) or (Parameter.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam,
          TParameterModifier.ConstRefParam]) then
        begin
          Failed := True;
          Exit;
        end;
      end;
      Plain := (ANode.Parent = nil) or not ((ANode.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
        TSyntaxKind.Dereference]) and (ANode.Parent.ChildCount > 0) and (ANode.Parent[0] = ANode));
      Indexed := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.IndexAccess) and (ANode.Parent[0] = ANode);
      for Index := 0 to High(AVariables) do
      begin
        if SameText(AVariables[Index].Name, ANode.Name) then
        begin
          AVariables[Index].Plain := AVariables[Index].Plain or Plain;
          AVariables[Index].Indexed := AVariables[Index].Indexed or Indexed;
          Exit;
        end;
      end;
      SetLength(AVariables, Length(AVariables) + 1);
      AVariables[High(AVariables)].Name := ANode.Name;
      AVariables[High(AVariables)].Plain := Plain;
      AVariables[High(AVariables)].Indexed := Indexed;
    end;

    procedure Walk(ARoot: TSyntaxNode);
    var
      Index: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while (Pending.Count > 0) and not Failed do
        begin
          Node := Pending.Pop;
          if Node.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr,
            TSyntaxKind.Error] then
          begin
            Failed := True;
            Exit;
          end;
          if Node.Kind = TSyntaxKind.Identifier then
          begin
            Add(Node);
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

  begin
    AVariables := nil;
    Failed := False;
    Walk(ACondition);
    Result := not Failed and (AVariables <> nil);
  end;

  // Ändert ANode die Variable AVariable?
  function Changes(ARoot: TSyntaxNode; const AVariable: TLoopVariable): Boolean;
  var
    Index: Integer;
    Node, Root: TSyntaxNode;
    ViaIndex: Boolean;
    Pending: TStack<TSyntaxNode>;

    function IsChange(AExpression: TSyntaxNode): Boolean;
    begin
      Root := ChainRoot(AExpression, ViaIndex);
      Result := (Root <> nil) and SameText(Root.Name, AVariable.Name) and (not ViaIndex or AVariable.Indexed);
    end;

  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.AssignStatement:
            if (Node.ChildCount > 0) and IsChange(Node[0]) then
            begin
              Exit(True);
            end;
          TSyntaxKind.Call:
            for Index := 1 to Node.ChildCount - 1 do
            begin
              if IsChange(Node[Index]) then
              begin
                Exit(True);
              end;
            end;
          TSyntaxKind.MemberAccess, TSyntaxKind.AddressOf:
            // X.Methode, X.Eigenschaft (Getter können ändern), @X.
            if (Node.ChildCount > 0) and IsChange(Node[0]) and not ViaIndex then
            begin
              Exit(True);
            end;
          TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
            if SameText(Node.Name, AVariable.Name) then
            begin
              Exit(True);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
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

  function Message(const AVariables: TArray<TLoopVariable>): string;
  var
    Index: Integer;
  begin
    Result := AVariables[0].Name;
    for Index := 1 to High(AVariables) do
    begin
      if Index = High(AVariables) then
      begin
        Result := Result + ' und ' + AVariables[Index].Name;
      end
      else
      begin
        Result := Result + ', ' + AVariables[Index].Name;
      end;
    end;
    if Length(AVariables) = 1 then
    begin
      Result := Result + ' wird im Rumpf nie verändert; die Schleife endet nicht.';
    end
    else
    begin
      Result := Result + ' werden im Rumpf nie verändert; die Schleife endet nicht.';
    end;
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    Condition, Owner: TSyntaxNode;
    Variables: TArray<TLoopVariable>;
    Variable: TLoopVariable;
    Body: TArray<TSyntaxNode>;
    Index: Integer;
    AnyPlain: Boolean;
    Names: TArray<string>;
  begin
    Owner := Routine(ALoop);
    if (Owner = nil) or (Owner.Kind <> TSyntaxKind.RoutineDecl) or (ALoop.ChildCount < 2) then
    begin
      Exit;
    end;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      Condition := ALoop[0];
      Body := [ALoop[1]];
    end
    else
    begin
      Condition := ALoop[ALoop.ChildCount - 1];
      Body := nil;
      for Index := 0 to ALoop.ChildCount - 2 do
      begin
        Body := Body + [ALoop[Index]];
      end;
    end;
    if not ConditionVariables(Condition, Owner, Variables) then
    begin
      Exit;
    end;
    AnyPlain := False;
    Names := nil;
    for Variable in Variables do
    begin
      AnyPlain := AnyPlain or Variable.Plain;
      Names := Names + [Variable.Name];
    end;
    if not AnyPlain or Captured(Owner, Names) then
    begin
      Exit;
    end;
    for Index := 0 to High(Body) do
    begin
      if HasExit(Body[Index], False, Raising) or Mentions(Body[Index], WaitingCalls) or
        Mentions(Body[Index], NestedRoutines(Owner)) or Contains(Body[Index], TSyntaxKind.WithStatement) then
      begin
        Exit;
      end;
      for Variable in Variables do
      begin
        if Changes(Body[Index], Variable) then
        begin
          Exit;
        end;
      end;
    end;
    AReport.Add(NodeRange(Condition), Message(Variables), TRuleConfidence.Medium);
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
        if Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement] then
        begin
          CheckLoop(Node);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := RuleFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  Raising := RaisingRoutines(AContext.Tree);
  try
    Visit(AContext.Tree.Root);
  finally
    Raising.Free;
    Resolver.UnpinTree;
  end;
end;

{ TRedundantJumpRule }

function TRedundantJumpRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RedundantJumpRuleId, TRuleSeverity.Hint, 'Überflüssiges Exit oder Continue');
end;

/// <summary>Ist AStatement ein bloßes AName; (ohne Argumente, ohne Qualifizierer)?</summary>
function IsBareJump(AStatement: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.CallStatement) and (AStatement.ChildCount = 1) and
    (AStatement[0].Kind = TSyntaxKind.Identifier) and SameText(AStatement[0].Name, AName);
end;

/// <summary>Steht zwischen AStart und AEnd eine bedingte Direktive oder eine andere Direktive?</summary>
function HasDirectiveBetween(const ATokens: TTokens; AStart, AEnd: Integer): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  for mIndex := TSyntaxTree.FirstTokenOf(ATokens, AStart) to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if mToken.Offset < AStart then
    begin
      Continue;
    end;
    if mToken.Offset >= AEnd then
    begin
      Break;
    end;
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letzte Anweisung, mit der AStatement endet: in begin … end die letzte, bei if die des letzten Zweigs
/// (else, ohne else then). Ein then-Zweig mit folgendem else ist ein Wächter der else-if-Kette und zählt nicht.
/// Andere Anweisungen (try, case, with, Schleifen) enden mit sich selbst.</summary>
function LastStatement(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := AStatement;
  // Schleife statt Rekursion (Bericht M1): lange else-if-Ketten wären sonst tiefe Rekursion.
  while (Result <> nil) and (Result.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement]) do
  begin
    if (Result.Kind = TSyntaxKind.IfStatement) and (Result.ChildCount < 2) then
    begin
      Exit(nil);
    end
    else if Result.ChildCount = 0 then
    begin
      Exit(nil);
    end
    else
    begin
      Result := Result[Result.ChildCount - 1];
    end;
  end;
end;

/// <summary>Rumpf einer for-, for-in- oder while-Schleife; bei repeat (die Anweisungen sind direkte Kinder) und
/// bei anderen Knoten nil.</summary>
function LoopBody(ALoop: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ALoop.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement]) and
    (ALoop.ChildCount > 0) then
  begin
    Result := ALoop[ALoop.ChildCount - 1];
  end;
end;

/// <summary>Letzte Anweisung des Rumpfs einer Schleife in ALast: der Rumpf aus LoopBody, bei repeat die Anweisung
/// vor der Bedingung hinter until.</summary>
function LoopLastStatement(ALoop: TSyntaxNode; out ALast: TSyntaxNode): Boolean;
begin
  ALast := LoopBody(ALoop);
  if (ALast = nil) and (ALoop.Kind = TSyntaxKind.RepeatStatement) and (ALoop.ChildCount > 1) then
  begin
    ALast := ALoop[ALoop.ChildCount - 2];
  end;
  Result := ALast <> nil;
end;

procedure TRedundantJumpRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  cExitMessage = 'Exit am Ende der Routine ist überflüssig.';
  cContinueMessage = 'Continue am Ende des Schleifenrumpfs ist überflüssig.';
var
  mTokens: TTokens;
  mPending: TStack<TSyntaxNode>;
  mNode, mBlock, mLast, mStatement: TSyntaxNode;
  mIndex: Integer;

  procedure ReportJump(AStatement: TSyntaxNode; const AMessage: string);
  var
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    // In einer Anweisungsfolge (begin … end, repeat … until); als Zweig eines if bliebe ein leeres then.
    if (AStatement.Parent <> nil) and (AStatement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.RepeatStatement]) then
    begin
      mFixes := [TRuleFix.Create('Anweisung entfernen', [TRuleEdit.Create(StatementRemoval(AContext.Text, AStatement),
        '')])];
    end;
    AReport.Add(TTextRange.Create(AStatement.StartPos, AStatement.EndPos), AMessage, TRuleConfidence.High, mFixes);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'Exit') or ContainsText(AContext.Text, 'Continue')) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
      if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        // Nur die letzte Anweisung des Rumpfs selbst; Exit in inneren Blöcken kann gewollt früh verlassen.
        mBlock := mNode.FindChild(TSyntaxKind.Block);
        if (mBlock <> nil) and (mBlock.ChildCount > 0) and
          IsBareJump(mBlock[mBlock.ChildCount - 1], 'Exit') and
          not HasDirectiveBetween(mTokens, mBlock.StartOffset, mBlock.EndOffset) then
        begin
          ReportJump(mBlock[mBlock.ChildCount - 1], cExitMessage);
        end;
      end
      else if LoopLastStatement(mNode, mLast) and not HasDirectiveBetween(mTokens, mNode.StartOffset, mNode.EndOffset) then
      begin
        mStatement := LastStatement(mLast);
        if (mStatement <> nil) and IsBareJump(mStatement, 'Continue') then
        begin
          ReportJump(mStatement, cContinueMessage);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TLoopRunsAtMostOnceRule }

function TLoopRunsAtMostOnceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LoopRunsAtMostOnceRuleId, TRuleSeverity.Warning, 'Schleife läuft höchstens einmal');
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

procedure TLoopRunsAtMostOnceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRaising: TDictionary<string, Boolean>;
  mAllowFirstElement, mRaisingOnly: Boolean;

  /// <summary>Name des Sprungs, mit dem die Anweisung ANode die Schleife immer verlässt (Exit, Break, raise,
  /// Halt …), '' wenn sie es nicht immer tut. AMixed: verschiedene Sprünge auf verschiedenen Wegen. Mit
  /// FRaisingOnly zählen nur Ausnahmen und Programmende (Rumpf einer Routine: Exit verlässt nur sie).
  /// </summary>
  function Leaves(ANode: TSyntaxNode; out AMixed: Boolean): string;
  var
    mIndex: Integer;
    mName, mOther: string;
    mMixed, mHandlers: Boolean;
    mChild, mPart: TSyntaxNode;

    /// <summary>Kinder von AParent ab AFrom als Anweisungsfolge (ohne on-Behandler): Ein Sprung beendet sie,
    /// was danach steht, ist unerreichbar.</summary>
    function Sequence(AParent: TSyntaxNode; AFrom, ATo: Integer; out ASequenceMixed: Boolean): string;
    var
      mAt: Integer;
    begin
      Result := '';
      ASequenceMixed := False;
      for mAt := AFrom to ATo do
      begin
        if AParent[mAt].Kind <> TSyntaxKind.ExceptionHandler then
        begin
          Result := Leaves(AParent[mAt], ASequenceMixed);
          if Result <> '' then
          begin
            Exit;
          end;
        end;
      end;
    end;

    /// <summary>Verlässt auch AOther die Schleife? Merkt verschiedene Sprünge in AMixed.</summary>
    function Both(const AFirst, AOther: string; AOtherMixed: Boolean): string;
    begin
      Result := '';
      if (AFirst = '') or (AOther = '') then
      begin
        Exit;
      end;
      AMixed := AMixed or AOtherMixed or not SameText(AFirst, AOther);
      Result := AFirst;
    end;

  begin
    Result := '';
    AMixed := False;
    case ANode.Kind of
      TSyntaxKind.RaiseStatement:
        Result := 'raise';
      TSyntaxKind.CallStatement:
        if ANode.ChildCount > 0 then
        begin
          mName := CalledName(ANode[0]);
          if MatchText(JumpName(ANode[0]), RaisingCalls) or ((mName <> '') and
            mRaising.ContainsKey(LowerCase(mName))) or not mRaisingOnly and
            MatchText(JumpName(ANode[0]), ['Exit', 'Break']) then
          begin
            Result := mName;
          end;
        end;
      TSyntaxKind.Block:
        Result := Sequence(ANode, 0, ANode.ChildCount - 1, AMixed);
      TSyntaxKind.WithStatement:
        if ANode.ChildCount > 0 then
        begin
          Result := Leaves(ANode[ANode.ChildCount - 1], AMixed);
        end;
      TSyntaxKind.IfStatement:
        // Nur mit else: Ohne else läuft ein Weg am Sprung vorbei.
        if ANode.ChildCount = 3 then
        begin
          mName := Leaves(ANode[1], AMixed);
          if mName <> '' then
          begin
            Result := Both(mName, Leaves(ANode[2], mMixed), mMixed);
          end;
        end;
      TSyntaxKind.CaseStatement:
        // Jeder Zweig und ein else-Zweig.
        if ANode.FindChild(TSyntaxKind.CaseElse) <> nil then
        begin
          mName := '';
          for mIndex := 1 to ANode.ChildCount - 1 do
          begin
            mChild := ANode[mIndex];
            if (mChild.Kind = TSyntaxKind.CaseItem) and (mChild.ChildCount > 0) then
            begin
              mOther := Leaves(mChild[mChild.ChildCount - 1], mMixed);
            end
            else if mChild.Kind = TSyntaxKind.CaseElse then
            begin
              mOther := Sequence(mChild, 0, mChild.ChildCount - 1, mMixed);
            end
            else
            begin
              mOther := '';
            end;
            if mOther = '' then
            begin
              Exit('');
            end;
            if mName = '' then
            begin
              mName := mOther;
              AMixed := mMixed;
            end
            else
            begin
              mName := Both(mName, mOther, mMixed);
            end;
          end;
          Result := mName;
        end;
      TSyntaxKind.TryStatement:
        if ANode.ChildCount > 0 then
        begin
          // try … finally: der try- oder der finally-Teil; try … except: der try-Teil und jeder Behandler.
          mPart := ANode[ANode.ChildCount - 1];
          mName := Sequence(ANode, 0, ANode.ChildCount - 2, AMixed);
          if mPart.Kind = TSyntaxKind.FinallyBlock then
          begin
            Result := mName;
            if Result = '' then
            begin
              Result := Sequence(mPart, 0, mPart.ChildCount - 1, AMixed);
            end;
            Exit;
          end;
          if (mName = '') or (mPart.Kind <> TSyntaxKind.ExceptBlock) then
          begin
            Exit;
          end;
          mHandlers := False;
          for mIndex := 0 to mPart.ChildCount - 1 do
          begin
            if mPart[mIndex].Kind = TSyntaxKind.ExceptionHandler then
            begin
              mHandlers := True;
              mChild := mPart[mIndex];
              if mChild.ChildCount = 0 then
              begin
                Exit;
              end;
              mName := Both(mName, Leaves(mChild[mChild.ChildCount - 1], mMixed), mMixed);
              if mName = '' then
              begin
                Exit;
              end;
            end;
          end;
          // Anweisungen ohne on bzw. der else-Teil; nur on-Behandler: andere Ausnahmen laufen nach außen.
          if not mHandlers or (mPart[mPart.ChildCount - 1].Kind <> TSyntaxKind.ExceptionHandler) then
          begin
            mName := Both(mName, Sequence(mPart, 0, mPart.ChildCount - 1, mMixed), mMixed);
          end;
          Result := mName;
        end;
    else
      // Übrige Arten: nichts zu tun.
    end;
  end;

  /// <summary>Enthält ANode ein Continue dieser Schleife (nicht in inneren Schleifen und anonymen Methoden),
  /// ein goto oder eine Marke? Dann gibt es einen Weg zum nächsten Durchlauf.</summary>
  function MayContinue(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement] then
        begin
          Exit(True);
        end;
        if (mNode.Kind = TSyntaxKind.AnonymousMethod) or ((mNode <> ANode) and IsLoop(mNode)) then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount > 0) and
          SameText(JumpName(mNode[0]), 'Continue') then
        begin
          Exit(True);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Steht im Bereich von ANode eine bedingte Direktive? Der Baum enthält dann alle Zweige.</summary>
  function HasConditional(ANode: TSyntaxNode): Boolean;
  var
    mToken: TPascalToken;
    mIndex: Integer;
    mText: string;
  begin
    for mIndex := AContext.Tree.FirstTokenFrom(ANode.StartOffset) to High(AContext.Tree.Tokens) do
    begin
      mToken := AContext.Tree.Tokens[mIndex];
      if mToken.Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if (mToken.Offset < ANode.StartOffset) or (mToken.Kind <> TPascalTokenKind.Directive) then
      begin
        Continue;
      end;
      mText := UpperCase(Copy(mToken.Text, 1, 8));
      if StartsStr('{$IF', mText) or StartsStr('{$ELSE', mText) or StartsStr('{$END', mText) or
        StartsStr('(*$IF', mText) or StartsStr('(*$ELSE', mText) or StartsStr('(*$END', mText) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Anweisungen des Rumpfs als Folge (Block, einzelne Anweisung bzw. die Anweisungen von repeat).
  /// </summary>
  function Statements(ALoop: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mIndex: Integer;
    mBody: TSyntaxNode;
  begin
    Result := nil;
    if ALoop.Kind = TSyntaxKind.RepeatStatement then
    begin
      for mIndex := 0 to ALoop.ChildCount - 2 do
      begin
        Result := Result + [ALoop[mIndex]];
      end;
      Exit;
    end;
    mBody := LoopBody(ALoop);
    if mBody = nil then
    begin
      Exit;
    end;
    if mBody.Kind = TSyntaxKind.Block then
    begin
      for mIndex := 0 to mBody.ChildCount - 1 do
      begin
        Result := Result + [mBody[mIndex]];
      end;
    end
    else
    begin
      Result := [mBody];
    end;
  end;

  /// <summary>for-in, das nur das erste Element holt: Keine Bedingung im Rumpf (if, case, Schleife) liest die
  /// Schleifenvariable, der Sprung hängt also nicht vom Element ab.</summary>
  function ReadsFirstElement(ALoop: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mNode, mCondition: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;

    function Mentions(ARoot: TSyntaxNode): Boolean;
    var
      mAt: Integer;
      mInner: TSyntaxNode;
      mStack: TStack<TSyntaxNode>;
    begin
      Result := False;
      mStack := TStack<TSyntaxNode>.Create;
      try
        mStack.Push(ARoot);
        while mStack.Count > 0 do
        begin
          mInner := mStack.Pop;
          if (mInner.Kind = TSyntaxKind.Identifier) and SameText(mInner.Name, ALoop.Name) then
          begin
            Exit(True);
          end;
          for mAt := 0 to mInner.ChildCount - 1 do
          begin
            mStack.Push(mInner[mAt]);
          end;
        end;
      finally
        mStack.Free;
      end;
    end;

  begin
    Result := False;
    if (ALoop.Kind <> TSyntaxKind.ForInStatement) or (ALoop.Name = '') then
    begin
      Exit;
    end;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(LoopBody(ALoop));
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mCondition := nil;
        case mNode.Kind of
          TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.WhileStatement:
            if mNode.ChildCount > 0 then
            begin
              mCondition := mNode[0];
            end;
          TSyntaxKind.RepeatStatement:
            if mNode.ChildCount > 0 then
            begin
              mCondition := mNode[mNode.ChildCount - 1];
            end;
          TSyntaxKind.IfExpr:
            if mNode.ChildCount > 0 then
            begin
              mCondition := mNode[0];
            end;
        else
          // Übrige Arten: nichts zu tun.
        end;
        if (mCondition <> nil) and Mentions(mCondition) then
        begin
          Exit;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
    Result := True;
  end;

  /// <summary>Schlüsselwort der Schleife für den Meldungsbereich.</summary>
  function KeywordRange(ALoop: TSyntaxNode): TTextRange;
  var
    mLength: Integer;
  begin
    mLength := 3;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      mLength := 5;
    end
    else if ALoop.Kind = TSyntaxKind.RepeatStatement then
    begin
      mLength := 6;
    end;
    Result := TTextRange.Create(ALoop.StartPos, TTextPosition.Create(ALoop.StartPos.Line,
      ALoop.StartPos.Character + mLength));
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    mStatements: TArray<TSyntaxNode>;
    mIndex, mJumpAt: Integer;
    mJump, mMessage, mSubject: string;
    mMixed, mOtherMixed: Boolean;
    mBody: TSyntaxNode;
  begin
    mStatements := Statements(ALoop);
    mJump := '';
    mJumpAt := -1;
    mMixed := False;
    for mIndex := 0 to High(mStatements) do
    begin
      mJump := Leaves(mStatements[mIndex], mMixed);
      if mJump <> '' then
      begin
        mJumpAt := mIndex;
        Break;
      end;
    end;
    if mJump = '' then
    begin
      Exit;
    end;
    mBody := LoopBody(ALoop);
    if mBody = nil then
    begin
      mBody := ALoop;
    end;
    if MayContinue(mBody) or HasConditional(ALoop) then
    begin
      Exit;
    end;
    if mAllowFirstElement and ReadsFirstElement(ALoop) then
    begin
      Exit;
    end;
    if mMixed then
    begin
      mJump := 'einem Sprung';
    end;
    case ALoop.Kind of
      TSyntaxKind.ForInStatement:
        begin
          mSubject := '';
          if ALoop.ChildCount > 1 then
          begin
            mSubject := Format(' von %s', [NodeText(AContext.Text, ALoop[ALoop.ChildCount - 2])]);
          end;
          mMessage := Format('Jeder Durchlauf endet mit %s: Die Schleife prüft nur das erste Element%s.',
            [mJump, mSubject]);
        end;
      TSyntaxKind.RepeatStatement:
        mMessage := Format('Jeder Durchlauf endet mit %s: Die Schleife läuft genau einmal.', [mJump]);
    else
      mMessage := Format('Jeder Durchlauf endet mit %s: Die Schleife läuft höchstens einmal.', [mJump]);
    end;
    // Typisch: "if … then X; Exit;" – der Sprung gehört in den if-Zweig.
    if not mMixed and (mJumpAt > 0) and (mStatements[mJumpAt].Kind = TSyntaxKind.CallStatement) and
      (mStatements[mJumpAt - 1].Kind = TSyntaxKind.IfStatement) and (mStatements[mJumpAt - 1].ChildCount = 2) and
      (Leaves(mStatements[mJumpAt - 1][1], mOtherMixed) = '') then
    begin
      mMessage := mMessage + Format(' Gehört %s in den if-Zweig?', [mJump]);
    end;
    AReport.Add(KeywordRange(ALoop), mMessage, TRuleConfidence.High);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if IsLoop(mNode) then
        begin
          CheckLoop(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Routinen der Datei (Kurzname klein), deren Rumpf auf jedem Weg eine Ausnahme auslöst bzw. das
  /// Programm beendet; RaisingRoutines genügt nicht, dort reicht ein raise irgendwo.</summary>
  procedure CollectAlwaysRaising;
  var
    mRoutines: TList<TSyntaxNode>;
    mRoutine, mBlock, mNode: TSyntaxNode;
    mChanged, mMixed: Boolean;
    mIndex: Integer;
    mPending: TStack<TSyntaxNode>;
  begin
    mRoutines := TList<TSyntaxNode>.Create;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutines.Add(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
      mRaisingOnly := True;
      // Bis nichts mehr dazukommt: A ruft B, B löst immer aus.
      repeat
        mChanged := False;
        for mRoutine in mRoutines do
        begin
          mBlock := mRoutine.FindChild(TSyntaxKind.Block);
          if (mBlock <> nil) and not mRaising.ContainsKey(LowerCase(ShortName(mRoutine.Name))) and
            (Leaves(mBlock, mMixed) <> '') then
          begin
            mRaising.Add(LowerCase(ShortName(mRoutine.Name)), True);
            mChanged := True;
          end;
        end;
      until not mChanged;
      mRaisingOnly := False;
    finally
      mPending.Free;
      mRoutines.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mAllowFirstElement := TRuleOptions.Bool(AContext.Options, 'allowFirstElement', False);
  mRaisingOnly := False;
  mRaising := TDictionary<string, Boolean>.Create;
  try
    CollectAlwaysRaising;
    Visit(AContext.Tree.Root);
  finally
    mRaising.Free;
  end;
end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantConditionRule.Create);
  ARegistry.Register(TInfiniteLoopRule.Create);
  ARegistry.Register(TLoopConditionUnchangedRule.Create);
  ARegistry.Register(TRedundantJumpRule.Create);
  ARegistry.Register(TLoopRunsAtMostOnceRule.Create);
end;

end.
