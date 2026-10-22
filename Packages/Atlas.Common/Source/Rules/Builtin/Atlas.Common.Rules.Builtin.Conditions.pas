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

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ConstantConditionRuleId = 'constant-condition';
  InfiniteLoopRuleId = 'infinite-loop';
  LoopConditionUnchangedRuleId = 'loop-condition-unchanged';

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

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);

implementation

uses
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
    function Binary(ANode: TSyntaxNode): TConstantValue;
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
    Result := AContext.RelativePath;
  if Result = '' then
    Result := AContext.UnitName + '.pas';
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
    Result := 'True'
  else
    Result := 'False';
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
    Result := Result[0];
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
    CollectConstants(ATree.Root);
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
      Lo := Middle + 1
    else
      Hi := Middle;
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
      Exit(True);
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
    Dec(First);
  Last := FirstToken(ANode.EndOffset);
  while (Last < High(FTree.Tokens)) and
    (FTree.Tokens[Last].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Last);
  for Index := First + 1 to Last - 1 do
    if FTree.Tokens[Index].Kind = TPascalTokenKind.Directive then
      Exit(True);
  Result := False;
end;

function TConditionValues.IsPlainConstant(ANode: TSyntaxNode): Boolean;
var
  Index, Values: Integer;
begin
  // Name = Wert; ohne Typ (sonst typisierte Konstante), ohne Direktive, außerhalb von {$IF…}.
  Values := 0;
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind <> TSyntaxKind.Directive then
      Inc(Values);
  Result := (Values = 1) and not HasDirective(ANode) and
    (TConditionalBranches.PathAt(FPaths, FirstToken(ANode.StartOffset)) = '');
end;

procedure TConditionValues.CollectConstants(ANode: TSyntaxNode);
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[Index].Kind = TSyntaxKind.ConstDecl) and IsPlainConstant(ANode[Index]) and
      not MatchText(ANode[Index].Name, FSwitches) then
      FConstants.AddOrSetValue(LowerCase(ANode[Index].Name), True);
    CollectConstants(ANode[Index]);
  end;
end;

function TConditionValues.FindConstant(ANode: TSyntaxNode; const AName: string;
  const APosition: TTextPosition): TSyntaxNode;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  // ConstDecl mit dem Namen, die APosition enthält.
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if (Child.StartPos.Line > APosition.Line) or ((Child.EndPos.Line < APosition.Line)) then
      Continue;
    if (Child.Kind = TSyntaxKind.ConstDecl) and SameText(Child.Name, AName) then
      Exit(Child);
    Result := FindConstant(Child, AName, APosition);
    if Result <> nil then
      Exit;
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
    Exit(TConstantValue.OfBool(SameText(ANode.Name, 'True'), ANode.Name));
  if not FConstants.ContainsKey(LowerCase(ANode.Name)) or (FDepth >= 8) then
    Exit;
  Resolved := FResolver.ResolveChain(FTree, FFileName, [ANode.Name], ANode.StartOffset);
  if not Resolved.Found or (Resolved.SymbolKind <> TIndexSymbolKind.Constant) or
    not ((Resolved.Kind = TResolvedKind.Local) or (Resolved.FileName = '') or
    SameText(Resolved.FileName, FFileName)) then
    Exit;
  Declaration := FindConstant(FTree.Root, ANode.Name, Resolved.Range.StartPos);
  if (Declaration = nil) or not IsPlainConstant(Declaration) then
    Exit;
  Inc(FDepth);
  try
    for Index := Declaration.ChildCount - 1 downto 0 do
      if Declaration[Index].Kind <> TSyntaxKind.Directive then
      begin
        Result := Evaluate(Declaration[Index]);
        Break;
      end;
  finally
    Dec(FDepth);
  end;
  if Result.Kind = TConstantKind.Bool then
    Result.Shown := ANode.Name + ' = ' + BoolText(Result.Bool);
end;

function TConditionValues.Binary(ANode: TSyntaxNode): TConstantValue;
var
  Left, Right: TConstantValue;
  Op: string;
  Compared: Integer;
begin
  Result := TConstantValue.Unknown;
  if ANode.ChildCount <> 2 then
    Exit;
  Op := ANode.Name;
  Left := Evaluate(ANode[0]);
  Right := Evaluate(ANode[1]);
  if (Op = 'and') or (Op = 'or') then
  begin
    // Ein fester Operand entscheidet allein: X or True, False and X.
    if (Left.Kind = TConstantKind.Bool) and (Left.Bool = (Op = 'or')) then
      Exit(TConstantValue.OfBool(Left.Bool, Left.Shown + ' ' + Op + ' …'));
    if (Right.Kind = TConstantKind.Bool) and (Right.Bool = (Op = 'or')) then
      Exit(TConstantValue.OfBool(Right.Bool, '… ' + Op + ' ' + Right.Shown));
    if (Left.Kind = TConstantKind.Bool) and (Right.Kind = TConstantKind.Bool) then
      Exit(TConstantValue.OfBool(Right.Bool, NodeText(FText, ANode)));
    Exit;
  end;
  if (Left.Kind = TConstantKind.Unknown) or (Left.Kind <> Right.Kind) then
    Exit;
  if Left.Kind = TConstantKind.Bool then
  begin
    if Op = 'xor' then
      Exit(TConstantValue.OfBool(Left.Bool <> Right.Bool, NodeText(FText, ANode)));
    Compared := Ord(Left.Bool) - Ord(Right.Bool);
  end
  else
  begin
    if Op = '+' then
      Exit(TConstantValue.OfInt(Left.Int + Right.Int));
    if Op = '-' then
      Exit(TConstantValue.OfInt(Left.Int - Right.Int));
    if Op = '*' then
      Exit(TConstantValue.OfInt(Left.Int * Right.Int));
    if ((Op = 'div') or (Op = 'mod')) and (Right.Int <> 0) then
    begin
      if Op = 'div' then
        Exit(TConstantValue.OfInt(Left.Int div Right.Int));
      Exit(TConstantValue.OfInt(Left.Int mod Right.Int));
    end;
    if Left.Int < Right.Int then
      Compared := -1
    else if Left.Int > Right.Int then
      Compared := 1
    else
      Compared := 0;
  end;
  if Op = '=' then
    Result := TConstantValue.OfBool(Compared = 0, '')
  else if Op = '<>' then
    Result := TConstantValue.OfBool(Compared <> 0, '')
  else if Op = '<' then
    Result := TConstantValue.OfBool(Compared < 0, '')
  else if Op = '>' then
    Result := TConstantValue.OfBool(Compared > 0, '')
  else if Op = '<=' then
    Result := TConstantValue.OfBool(Compared <= 0, '')
  else if Op = '>=' then
    Result := TConstantValue.OfBool(Compared >= 0, '');
  if Result.Kind = TConstantKind.Bool then
    Result.Shown := NodeText(FText, ANode);
end;

function TConditionValues.Evaluate(ANode: TSyntaxNode): TConstantValue;
var
  Inner: TConstantValue;
  Number: Int64;
begin
  Result := TConstantValue.Unknown;
  if ANode = nil then
    Exit;
  case ANode.Kind of
    TSyntaxKind.ParenExpr:
      if ANode.ChildCount = 1 then
        Result := Evaluate(ANode[0]);
    TSyntaxKind.Identifier:
      Result := NameValue(ANode);
    TSyntaxKind.Literal:
      if TOrdinalConstants.TryNumber(ANode.Name, Number) then
        Result := TConstantValue.OfInt(Number);
    TSyntaxKind.UnaryExpr:
      if ANode.ChildCount = 1 then
      begin
        Inner := Evaluate(ANode[0]);
        if (ANode.Name = 'not') and (Inner.Kind = TConstantKind.Bool) then
          Result := TConstantValue.OfBool(not Inner.Bool, 'not ' + Inner.Shown)
        else if (ANode.Name = '-') and (Inner.Kind = TConstantKind.Int) then
          Result := TConstantValue.OfInt(-Inner.Int)
        else if (ANode.Name = '+') and (Inner.Kind = TConstantKind.Int) then
          Result := Inner;
      end;
    TSyntaxKind.BinaryExpr:
      Result := Binary(ANode);
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
    for Index := 1 to High(Lines) do
    begin
      Remove := TTextLines.IndentLength(Lines[Index]);
      if Remove > Shift then
        Remove := Shift;
      Lines[Index] := Copy(Lines[Index], Remove + 1, MaxInt);
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
    Inc(Probe);
  if (Probe < Length(AText)) and (AText[Probe + 1] = ';') then
    Last := Probe + 1;
  Probe := Last;
  while (Probe < Length(AText)) and CharInSet(AText[Probe + 1], [' ', #9]) do
    Inc(Probe);
  if ((Probe = Length(AText)) or CharInSet(AText[Probe + 1], [#13, #10])) and
    (Trim(Copy(AText, Lines.LineStart(ANode.StartPos.Line) + 1, First - Lines.LineStart(ANode.StartPos.Line))) = '') then
  begin
    First := Lines.LineStart(ANode.StartPos.Line);
    Last := Lines.LineStart(Lines.PositionAt(Probe).Line + 1);
    if Last <= Probe then
      Last := Probe;
  end;
  Result := TTextRange.Create(Lines.PositionAt(First), Lines.PositionAt(Last));
end;

procedure TConstantConditionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Values: TConditionValues;
  Resolver: TNameResolver;
  FileName: string;

  procedure ReportIf(ANode: TSyntaxNode; const AValue: TConstantValue);
  var
    Message: string;
    Fixes: TArray<TRuleFix>;
    Branch: TSyntaxNode;
  begin
    if AValue.Bool then
      Message := Format('Die Bedingung ist immer wahr (%s).', [AValue.Shown])
    else
      Message := Format('Die Bedingung ist immer falsch (%s).', [AValue.Shown]);
    Fixes := nil;
    Branch := nil;
    if AValue.Bool and (ANode.ChildCount >= 2) then
      Branch := ANode[1]
    else if not AValue.Bool and (ANode.ChildCount >= 3) then
      Branch := ANode[2];
    if (Branch <> nil) and (Branch.Kind <> TSyntaxKind.EmptyStatement) then
    begin
      if AValue.Bool then
        Fixes := [TRuleFix.Create('Bedingung entfernen', [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, Branch, ANode.StartPos.Character))])]
      else
        Fixes := [TRuleFix.Create('Toten Zweig entfernen', [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, Branch, ANode.StartPos.Character))])];
    end
    else if not AValue.Bool then
      Fixes := [TRuleFix.Create('Toten Zweig entfernen', [TRuleEdit.Create(StatementRemoval(AContext.Text, ANode),
        '')])];
    AReport.Add(NodeRange(ANode[0]), Message, TRuleConfidence.High, Fixes);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Condition: TSyntaxNode;
    Value: TConstantValue;
  begin
    Condition := nil;
    case ANode.Kind of
      TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement:
        if ANode.ChildCount > 0 then
          Condition := ANode[0];
      TSyntaxKind.RepeatStatement:
        if ANode.ChildCount > 0 then
          Condition := ANode[ANode.ChildCount - 1];
    end;
    if (Condition <> nil) and not Values.Conditional(Condition) then
    begin
      Value := Values.Evaluate(Condition);
      // while True do und repeat … until False: gewollte Endlosschleife (infinite-loop prüft den Ausgang).
      if (Value.Kind = TConstantKind.Bool) and
        not ((ANode.Kind = TSyntaxKind.WhileStatement) and IsBoolLiteral(Condition, True)) and
        not ((ANode.Kind = TSyntaxKind.RepeatStatement) and IsBoolLiteral(Condition, False)) then
      begin
        if ANode.Kind = TSyntaxKind.IfStatement then
          ReportIf(ANode, Value)
        else if Value.Bool then
          AReport.Add(NodeRange(Condition), Format('Die Bedingung ist immer wahr (%s).', [Value.Shown]),
            TRuleConfidence.High)
        else
          AReport.Add(NodeRange(Condition), Format('Die Bedingung ist immer falsch (%s).', [Value.Shown]),
            TRuleConfidence.High);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := RuleFileName(AContext);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    Values := TConditionValues.Create(AContext.Tree, AContext.Text, FileName, Resolver,
      TRuleOptions.Strings(AContext.Options, 'switchConstants', []));
    try
      Visit(AContext.Tree.Root);
    finally
      Values.Free;
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
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
    Result := Copy(Result, Dot + 2, MaxInt);
end;

/// <summary>Name eines Aufrufs (Bezeichner, Kette X.Name, Name(…)); '' sonst.</summary>
function CalledName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
    ANode := ANode[0];
  if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
    Result := ANode.Name;
end;

/// <summary>Löst ANode (ohne anonyme Methoden) eine Ausnahme aus oder beendet das Programm, direkt oder über
/// eine Routine aus ARaising?</summary>
function Raises(ANode: TSyntaxNode; ARaising: TDictionary<string, Boolean>): Boolean;
var
  Index: Integer;
  Name: string;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit(False);
  if ANode.Kind = TSyntaxKind.RaiseStatement then
    Exit(True);
  if ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier] then
  begin
    Name := CalledName(ANode);
    if MatchText(Name, RaisingCalls) or ((Name <> '') and ARaising.ContainsKey(LowerCase(Name))) then
      Exit(True);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    if Raises(ANode[Index], ARaising) then
      Exit(True);
  Result := False;
end;

/// <summary>Kurznamen (klein) der Routinen der Datei, die eine Ausnahme auslösen oder das Programm beenden.</summary>
function RaisingRoutines(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  Routines: TList<TSyntaxNode>;
  Changed: Boolean;
  Routine: TSyntaxNode;

  procedure Collect(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
      Routines.Add(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Collect(ANode[Index]);
  end;

begin
  Result := TDictionary<string, Boolean>.Create;
  Routines := TList<TSyntaxNode>.Create;
  try
    if ATree.Root <> nil then
      Collect(ATree.Root);
    // Bis nichts mehr dazukommt: A ruft B, B löst aus.
    repeat
      Changed := False;
      for Routine in Routines do
        if not Result.ContainsKey(LowerCase(ShortName(Routine.Name))) and (Routine.FindChild(TSyntaxKind.Block) <> nil) and
          Raises(Routine.FindChild(TSyntaxKind.Block), Result) then
        begin
          Result.Add(LowerCase(ShortName(Routine.Name)), True);
          Changed := True;
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
begin
  case ANode.Kind of
    TSyntaxKind.AnonymousMethod:
      Exit(False);
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
      Exit(True);
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call:
      begin
        Name := CalledName(ANode);
        if SameText(Name, 'Terminated') or MatchText(Name, LeavingCalls) or
          ((Name <> '') and ARaising.ContainsKey(LowerCase(Name))) then
          Exit(True);
        if SameText(Name, 'Break') and not AInner then
          Exit(True);
      end;
  end;
  Inner := AInner or (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]);
  for Index := 0 to ANode.ChildCount - 1 do
    if HasExit(ANode[Index], Inner, ARaising) then
      Exit(True);
  Result := False;
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
      Exit(True);
    Child := Parent;
    Parent := Parent.Parent;
  end;
  Result := False;
end;

procedure TInfiniteLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Values: TConditionValues;
  Resolver: TNameResolver;
  Raising: TDictionary<string, Boolean>;
  FileName: string;

  function Endless(ALoop: TSyntaxNode): Boolean;
  var
    Index, First, Last: Integer;
    Value: TConstantValue;
  begin
    Result := False;
    if ALoop.ChildCount = 0 then
      Exit;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      Value := Values.Evaluate(ALoop[0]);
      if (Value.Kind <> TConstantKind.Bool) or not Value.Bool or Values.Conditional(ALoop[0]) then
        Exit;
      First := 1;
      Last := ALoop.ChildCount - 1;
    end
    else
    begin
      Value := Values.Evaluate(ALoop[ALoop.ChildCount - 1]);
      if (Value.Kind <> TConstantKind.Bool) or Value.Bool or Values.Conditional(ALoop[ALoop.ChildCount - 1]) then
        Exit;
      First := 0;
      Last := ALoop.ChildCount - 2;
    end;
    for Index := First to Last do
      if HasExit(ALoop[Index], False, Raising) then
        Exit;
    Result := not InTryExcept(ALoop);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Condition: TSyntaxNode;
  begin
    if (ANode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and Endless(ANode) then
    begin
      if ANode.Kind = TSyntaxKind.WhileStatement then
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode[0].EndPos),
          'Die Schleife hat keinen Ausgang (kein Break, Exit oder raise).', TRuleConfidence.High)
      else
      begin
        Condition := ANode[ANode.ChildCount - 1];
        AReport.Add(NodeRange(Condition), 'Die Schleife hat keinen Ausgang (kein Break, Exit oder raise).',
          TRuleConfidence.High, [TRuleFix.Jump('Zum Schleifenkopf springen', ANode.StartPos)]);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := RuleFileName(AContext);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
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
  finally
    Resolver.Free;
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
    Exit(nil);
  AViaIndex := (Previous <> nil) and (Previous.Kind = TSyntaxKind.IndexAccess);
end;

/// <summary>Enthält der Teilbaum einen Knoten der Art AKind?</summary>
function Contains(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if Contains(ANode[Index], AKind) then
      Exit(True);
  Result := False;
end;

/// <summary>Kommt im Teilbaum ein Bezeichner aus ANames vor (auch als Aufruf)?</summary>
function Mentions(ANode: TSyntaxNode; const ANames: array of string): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(ANode.Name, ANames) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if Mentions(ANode[Index], ANames) then
      Exit(True);
  Result := False;
end;

procedure TLoopConditionUnchangedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  Raising: TDictionary<string, Boolean>;
  FileName: string;

  function Routine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
      Result := Result.Parent;
  end;

  // Lokale Routinen (Namen) innerhalb von ARoutine.
  function NestedRoutines(ARoutine: TSyntaxNode): TArray<string>;
  var
    Names: TArray<string>;

    procedure Collect(ANode: TSyntaxNode);
    var
      Index: Integer;
    begin
      for Index := 0 to ANode.ChildCount - 1 do
      begin
        if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
          Names := Names + [ShortName(ANode[Index].Name)];
        Collect(ANode[Index]);
      end;
    end;

  begin
    Names := nil;
    Collect(ARoutine);
    Result := Names;
  end;

  // Werden Namen aus ANames in einer anonymen Methode von ARoutine erfasst?
  function Captured(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.AnonymousMethod then
      Exit(Mentions(ANode, ANames));
    for Index := 0 to ANode.ChildCount - 1 do
      if Captured(ANode[Index], ANames) then
        Exit(True);
    Result := False;
  end;

  // Parameter-Knoten, dessen Bereich APosition enthält; nil sonst.
  function ParameterAt(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    if not Before(ANode.StartPos, APosition) or not Before(APosition, ANode.EndPos) then
      Exit;
    if ANode.Kind = TSyntaxKind.Parameter then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Result := ParameterAt(ANode[Index], APosition);
      if Result <> nil then
        Exit;
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
        Exit;
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
        Exit;
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
        if SameText(AVariables[Index].Name, ANode.Name) then
        begin
          AVariables[Index].Plain := AVariables[Index].Plain or Plain;
          AVariables[Index].Indexed := AVariables[Index].Indexed or Indexed;
          Exit;
        end;
      SetLength(AVariables, Length(AVariables) + 1);
      AVariables[High(AVariables)].Name := ANode.Name;
      AVariables[High(AVariables)].Plain := Plain;
      AVariables[High(AVariables)].Indexed := Indexed;
    end;

    procedure Walk(ANode: TSyntaxNode);
    var
      Index: Integer;
    begin
      if Failed then
        Exit;
      if ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr,
        TSyntaxKind.Error] then
      begin
        Failed := True;
        Exit;
      end;
      if ANode.Kind = TSyntaxKind.Identifier then
        Add(ANode);
      for Index := 0 to ANode.ChildCount - 1 do
        Walk(ANode[Index]);
    end;

  begin
    AVariables := nil;
    Failed := False;
    Walk(ACondition);
    Result := not Failed and (AVariables <> nil);
  end;

  // Ändert ANode die Variable AVariable?
  function Changes(ANode: TSyntaxNode; const AVariable: TLoopVariable): Boolean;
  var
    Index: Integer;
    Root: TSyntaxNode;
    ViaIndex: Boolean;

    function IsChange(AExpression: TSyntaxNode): Boolean;
    begin
      Root := ChainRoot(AExpression, ViaIndex);
      Result := (Root <> nil) and SameText(Root.Name, AVariable.Name) and (not ViaIndex or AVariable.Indexed);
    end;

  begin
    case ANode.Kind of
      TSyntaxKind.AssignStatement:
        if (ANode.ChildCount > 0) and IsChange(ANode[0]) then
          Exit(True);
      TSyntaxKind.Call:
        for Index := 1 to ANode.ChildCount - 1 do
          if IsChange(ANode[Index]) then
            Exit(True);
      TSyntaxKind.MemberAccess, TSyntaxKind.AddressOf:
        // X.Methode, X.Eigenschaft (Getter können ändern), @X.
        if (ANode.ChildCount > 0) and IsChange(ANode[0]) and not ViaIndex then
          Exit(True);
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
        if SameText(ANode.Name, AVariable.Name) then
          Exit(True);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      if Changes(ANode[Index], AVariable) then
        Exit(True);
    Result := False;
  end;

  function Message(const AVariables: TArray<TLoopVariable>): string;
  var
    Index: Integer;
  begin
    Result := AVariables[0].Name;
    for Index := 1 to High(AVariables) do
      if Index = High(AVariables) then
        Result := Result + ' und ' + AVariables[Index].Name
      else
        Result := Result + ', ' + AVariables[Index].Name;
    if Length(AVariables) = 1 then
      Result := Result + ' wird im Rumpf nie verändert; die Schleife endet nicht.'
    else
      Result := Result + ' werden im Rumpf nie verändert; die Schleife endet nicht.';
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
      Exit;
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
        Body := Body + [ALoop[Index]];
    end;
    if not ConditionVariables(Condition, Owner, Variables) then
      Exit;
    AnyPlain := False;
    Names := nil;
    for Variable in Variables do
    begin
      AnyPlain := AnyPlain or Variable.Plain;
      Names := Names + [Variable.Name];
    end;
    if not AnyPlain or Captured(Owner, Names) then
      Exit;
    for Index := 0 to High(Body) do
    begin
      if HasExit(Body[Index], False, Raising) or Mentions(Body[Index], WaitingCalls) or
        Mentions(Body[Index], NestedRoutines(Owner)) or Contains(Body[Index], TSyntaxKind.WithStatement) then
        Exit;
      for Variable in Variables do
        if Changes(Body[Index], Variable) then
          Exit;
    end;
    AReport.Add(NodeRange(Condition), Message(Variables), TRuleConfidence.Medium);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement] then
      CheckLoop(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  FileName := RuleFileName(AContext);
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    Raising := RaisingRoutines(AContext.Tree);
    try
      Visit(AContext.Tree.Root);
    finally
      Raising.Free;
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantConditionRule.Create);
  ARegistry.Register(TInfiniteLoopRule.Create);
  ARegistry.Register(TLoopConditionUnchangedRule.Create);
end;

end.
