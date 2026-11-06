unit Atlas.Common.Rules.Builtin.Conditions.Values;

// Feste Werte von Bedingungen für die Regeln der Gruppe Bedingungen
// (Atlas.Common.Rules.Builtin.Conditions): True, False, Zahlen, untypisierte
// Konstanten der Datei außerhalb von {$IF…} und Operatoren darauf.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver;

type
{$SCOPEDENUMS ON}
  TConstantKind = (Unknown, Bool, Int);
{$SCOPEDENUMS OFF}

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
    function Combine(ANode: TSyntaxNode; AValues: TStack<TConstantValue>): TConstantValue;
    function LeafValue(ANode: TSyntaxNode): TConstantValue;
  public
    constructor Create(ATree: TSyntaxTree; const AText, AFileName: string; AResolver: TNameResolver;
      const ASwitches: TArray<string>);
    destructor Destroy; override;
    function Evaluate(ANode: TSyntaxNode): TConstantValue;
    /// <summary>Steht in der Bedingung ANode oder direkt davor bzw. dahinter eine Direktive (bedingter Teil)?</summary>
    function Conditional(ANode: TSyntaxNode): Boolean;
  end;

function BoolText(AValue: Boolean): string;
/// <summary>Quelltext des Knotens ANode in AText.</summary>
function NodeText(const AText: string; ANode: TSyntaxNode): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Semantics.OrdinalConstants;

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
  mLo, mHi, mMiddle: Integer;
begin
  mLo := 0;
  mHi := Length(FTree.Tokens);
  while mLo < mHi do
  begin
    mMiddle := (mLo + mHi) div 2;
    if FTree.Tokens[mMiddle].Offset < AOffset then
    begin
      mLo := mMiddle + 1;
    end
    else
    begin
      mHi := mMiddle;
    end;
  end;
  Result := mLo;
end;

function TConditionValues.HasDirective(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := FirstToken(ANode.StartOffset);
  while (mIndex <= High(FTree.Tokens)) and (FTree.Tokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if FTree.Tokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

function TConditionValues.Conditional(ANode: TSyntaxNode): Boolean;
var
  mFirst, mLast, mIndex: Integer;
begin
  // Vom Schlüsselwort vor der Bedingung (if, while, until) bis zu dem dahinter (then, do, ;).
  mFirst := FirstToken(ANode.StartOffset) - 1;
  while (mFirst > 0) and (FTree.Tokens[mFirst].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mFirst);
  end;
  mLast := FirstToken(ANode.EndOffset);
  while (mLast < High(FTree.Tokens)) and
    (FTree.Tokens[mLast].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(mLast);
  end;
  for mIndex := mFirst + 1 to mLast - 1 do
  begin
    if FTree.Tokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TConditionValues.IsPlainConstant(ANode: TSyntaxNode): Boolean;
var
  mIndex, mValues: Integer;
begin
  // Name = Wert; ohne Typ (sonst typisierte Konstante), ohne Direktive, außerhalb von {$IF…}.
  mValues := 0;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind <> TSyntaxKind.Directive then
    begin
      Inc(mValues);
    end;
  end;
  Result := (mValues = 1) and not HasDirective(ANode) and
    (TConditionalBranches.PathAt(FPaths, FirstToken(ANode.StartOffset)) = '');
end;

procedure TConditionValues.CollectConstants(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ANode.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ANode[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.ConstDecl) and IsPlainConstant(mNode) and not MatchText(mNode.Name, FSwitches) then
      begin
        FConstants.AddOrSetValue(LowerCase(mNode.Name), True);
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

function TConditionValues.FindConstant(ANode: TSyntaxNode; const AName: string;
  const APosition: TTextPosition): TSyntaxNode;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // ConstDecl mit dem Namen, die APosition enthält. Iterativ (Bericht M1).
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ANode.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ANode[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mChild := mPending.Pop;
      if (mChild.StartPos.Line > APosition.Line) or ((mChild.EndPos.Line < APosition.Line)) then
      begin
        Continue;
      end;
      if (mChild.Kind = TSyntaxKind.ConstDecl) and SameText(mChild.Name, AName) then
      begin
        Exit(mChild);
      end;
      for mIndex := mChild.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mChild[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TConditionValues.NameValue(ANode: TSyntaxNode): TConstantValue;
var
  mResolved: TResolvedSymbol;
  mDeclaration: TSyntaxNode;
  mIndex: Integer;
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
  mResolved := FResolver.ResolveChain(FTree, FFileName, [ANode.Name], ANode.StartOffset);
  if not mResolved.Found or (mResolved.SymbolKind <> TIndexSymbolKind.Constant) or
    not ((mResolved.Kind = TResolvedKind.Local) or (mResolved.FileName = '') or
    SameText(mResolved.FileName, FFileName)) then
  begin
    Exit;
  end;
  mDeclaration := FindConstant(FTree.Root, ANode.Name, mResolved.Range.StartPos);
  if (mDeclaration = nil) or not IsPlainConstant(mDeclaration) then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    for mIndex := mDeclaration.ChildCount - 1 downto 0 do
    begin
      if mDeclaration[mIndex].Kind <> TSyntaxKind.Directive then
      begin
        Result := Evaluate(mDeclaration[mIndex]);
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

/// <summary>and bzw. or: Ein fester Operand entscheidet allein (X or True, False and X), sonst beide.</summary>
function LogicalValue(const AText: string; ANode: TSyntaxNode; const AOp: string;
  const ALeft, ARight: TConstantValue): TConstantValue;
var
  mDeciding: Boolean;
begin
  mDeciding := AOp = 'or';
  if (ALeft.Kind = TConstantKind.Bool) and (ALeft.Bool = mDeciding) then
  begin
    Result := TConstantValue.OfBool(ALeft.Bool, ALeft.Shown + ' ' + AOp + ' …');
  end
  else if (ARight.Kind = TConstantKind.Bool) and (ARight.Bool = mDeciding) then
  begin
    Result := TConstantValue.OfBool(ARight.Bool, '… ' + AOp + ' ' + ARight.Shown);
  end
  else if (ALeft.Kind = TConstantKind.Bool) and (ARight.Kind = TConstantKind.Bool) then
  begin
    Result := TConstantValue.OfBool(ARight.Bool, NodeText(AText, ANode));
  end
  else
  begin
    Result := TConstantValue.Unknown;
  end;
end;

/// <summary>+, -, *, div und mod zweier Zahlen; False bei anderem Operator oder Division durch 0.</summary>
function IntArithmetic(const AOp: string; const ALeft, ARight: TConstantValue; out AValue: TConstantValue): Boolean;
begin
  Result := True;
  AValue := TConstantValue.Unknown;
  case IndexStr(AOp, ['+', '-', '*']) of
    0:
      AValue := TConstantValue.OfInt(ALeft.Int + ARight.Int);
    1:
      AValue := TConstantValue.OfInt(ALeft.Int - ARight.Int);
    2:
      AValue := TConstantValue.OfInt(ALeft.Int * ARight.Int);
  else
    Result := ((AOp = 'div') or (AOp = 'mod')) and (ARight.Int <> 0);
    if Result and (AOp = 'div') then
    begin
      AValue := TConstantValue.OfInt(ALeft.Int div ARight.Int);
    end
    else if Result then
    begin
      AValue := TConstantValue.OfInt(ALeft.Int mod ARight.Int);
    end;
  end;
end;

/// <summary>Vorzeichen des Vergleichs zweier Werte gleicher Art: -1, 0 oder 1.</summary>
function CompareValues(const ALeft, ARight: TConstantValue): Integer;
begin
  if ALeft.Kind = TConstantKind.Bool then
  begin
    Result := Ord(ALeft.Bool) - Ord(ARight.Bool);
  end
  else if ALeft.Int < ARight.Int then
  begin
    Result := -1;
  end
  else if ALeft.Int > ARight.Int then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Ergebnis des Vergleichsoperators AOp bei Vergleichsergebnis ACompared; unbekannt bei anderem
/// Operator.</summary>
function ComparisonValue(const AOp: string; ACompared: Integer): TConstantValue;
begin
  case IndexStr(AOp, ['=', '<>', '<', '>', '<=', '>=']) of
    0:
      Result := TConstantValue.OfBool(ACompared = 0, '');
    1:
      Result := TConstantValue.OfBool(ACompared <> 0, '');
    2:
      Result := TConstantValue.OfBool(ACompared < 0, '');
    3:
      Result := TConstantValue.OfBool(ACompared > 0, '');
    4:
      Result := TConstantValue.OfBool(ACompared <= 0, '');
    5:
      Result := TConstantValue.OfBool(ACompared >= 0, '');
  else
    Result := TConstantValue.Unknown;
  end;
end;

function TConditionValues.Binary(ANode: TSyntaxNode; const ALeft, ARight: TConstantValue): TConstantValue;
var
  mOp: string;
begin
  mOp := ANode.Name;
  if (mOp = 'and') or (mOp = 'or') then
  begin
    Exit(LogicalValue(FText, ANode, mOp, ALeft, ARight));
  end;
  Result := TConstantValue.Unknown;
  if (ALeft.Kind = TConstantKind.Unknown) or (ALeft.Kind <> ARight.Kind) then
  begin
    Exit;
  end;
  if (ALeft.Kind = TConstantKind.Bool) and (mOp = 'xor') then
  begin
    Exit(TConstantValue.OfBool(ALeft.Bool <> ARight.Bool, NodeText(FText, ANode)));
  end;
  if (ALeft.Kind = TConstantKind.Int) and IntArithmetic(mOp, ALeft, ARight, Result) then
  begin
    Exit;
  end;
  Result := ComparisonValue(mOp, CompareValues(ALeft, ARight));
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

/// <summary>Wert eines Knotens, dessen Operanden schon auf AValues liegen (links, dann rechts).</summary>
function TConditionValues.Combine(ANode: TSyntaxNode; AValues: TStack<TConstantValue>): TConstantValue;
var
  mLeft, mRight: TConstantValue;
begin
  case ANode.Kind of
    TSyntaxKind.ParenExpr:
      Result := AValues.Pop;
    TSyntaxKind.UnaryExpr:
      Result := Unary(ANode, AValues.Pop);
  else
    mRight := AValues.Pop;
    mLeft := AValues.Pop;
    Result := Binary(ANode, mLeft, mRight);
  end;
end;

/// <summary>Klammer, einstelliger oder zweistelliger Ausdruck: Knoten und Operanden auf APending legen.</summary>
function Expand(ANode: TSyntaxNode; APending: TStack<TSyntaxPostOrderEntry>): Boolean;
var
  mIndex: Integer;
begin
  Result := (ANode <> nil) and ((ANode.Kind in [TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr]) and
    (ANode.ChildCount = 1) or (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2));
  if Result then
  begin
    APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
    for mIndex := ANode.ChildCount - 1 downto 0 do
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(ANode[mIndex], False));
    end;
  end;
end;

/// <summary>Wert eines Blatts: Name (True, False, Konstante) oder Zahl; sonst unbekannt.</summary>
function TConditionValues.LeafValue(ANode: TSyntaxNode): TConstantValue;
var
  mNumber: Int64;
begin
  Result := TConstantValue.Unknown;
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := NameValue(ANode);
  end
  else if (ANode.Kind = TSyntaxKind.Literal) and TOrdinalConstants.TryNumber(ANode.Name, mNumber) then
  begin
    Result := TConstantValue.OfInt(mNumber);
  end;
end;

function TConditionValues.Evaluate(ANode: TSyntaxNode): TConstantValue;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mValues: TStack<TConstantValue>;
  mEntry: TSyntaxPostOrderEntry;
begin
  // Iterativ (Bericht M1): Nachordnung mit Wertestapel; lange Ketten wie 1 - 1 - … - 1 sind tiefe Bäume.
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  mValues := TStack<TConstantValue>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if mEntry.Done then
      begin
        mValues.Push(Combine(mEntry.Node, mValues));
      end
      else if not Expand(mEntry.Node, mPending) then
      begin
        mValues.Push(LeafValue(mEntry.Node));
      end;
    end;
    Result := mValues.Pop;
  finally
    mValues.Free;
    mPending.Free;
  end;
end;

end.
