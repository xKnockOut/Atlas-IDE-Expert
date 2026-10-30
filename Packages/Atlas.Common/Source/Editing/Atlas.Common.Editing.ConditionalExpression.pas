unit Atlas.Common.Editing.ConditionalExpression;

// if-Anweisung und Bedingungsausdruck (Delphi 13: X := if C then A else B)
// ineinander umwandeln (#684):
//   In bedingten Ausdruck umwandeln: auf einem if mit else, dessen Zweige je
//     eine Anweisung derselben Form haben: Zuweisung an dasselbe Ziel,
//     Exit(A)/Exit(B) oder derselbe Aufruf mit genau einem anderen Argument
//     (ohne Seiteneffekte). else-if-Ketten werden verschachtelte Ausdrücke,
//     ab drei Bedingungen nicht mehr (dafür gibt es case, #646). Die Typen
//     der Werte müssen sicher bekannt und verträglich sein.
//   In if-Anweisung umwandeln: auf einem Bedingungsausdruck in einer
//     Zuweisung, einem Aufruf (auch Exit) oder einer Inline-Variablen mit
//     Typ. Die Anweisung wird je Zweig wiederholt; verschachtelte Ausdrücke
//     werden else if bzw. ein inneres if in begin … end. Der Rest der
//     Anweisung darf keine Seiteneffekte haben (er liefe sonst nach der
//     Bedingung statt davor).
//   IfThen durch bedingten Ausdruck ersetzen: IfThen aus System.Math bzw.
//     System.StrUtils wertet beide Zweige aus, der Ausdruck nur einen.
// Kommentare im umgeschriebenen Bereich verhindern die Aktion. Typen und die
// Herkunft von IfThen liefert der Aufrufer (TConditionalLookup).

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.StatementText;

type
  /// <summary>Grobe Art eines Werts für die Verträglichkeit der Zweige.</summary>
  TValueKind = (Unknown, Whole, Float, Text, Logical, NilValue, Named);

  TValueType = record
    Kind: TValueKind;
    /// <summary>Typname bei Named.</summary>
    Name: string;
    class function Create(AKind: TValueKind; const AName: string): TValueType; static;
  end;

  /// <summary>Typ des Ausdrucks ANode über die Namensauflösung; Unknown, wenn nicht sicher bekannt.</summary>
  TValueTypeFunc = reference to function(ANode: TSyntaxNode): TValueType;
  /// <summary>Ist der Aufruf ACall das IfThen aus System.Math bzw. System.StrUtils? ADefault: Wert des dritten
  /// Arguments, wenn es fehlt ('0' bzw. '''').</summary>
  TIfThenFunc = reference to function(ACall: TSyntaxNode; out ADefault: string): Boolean;

  TConditionalLookup = record
    ValueType: TValueTypeFunc;
    IfThen: TIfThenFunc;
    /// <summary>Typen und IfThen über AResolver für den Baum ATree der Datei AFileName (Baum festhalten, etwa mit
    /// PinTree, solange die Funktionen gebraucht werden).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TConditionalLookup; static;
    /// <summary>Art eines aufgelösten Typs.</summary>
    class function KindOfType(const AType: TResolvedSymbol): TValueType; static;
  end;

  TConditionalExpression = class
  public const
    ToExpressionTitle = 'In bedingten Ausdruck umwandeln';
    ToStatementTitle = 'In if-Anweisung umwandeln';
    IfThenTitle = 'IfThen durch bedingten Ausdruck ersetzen';
    /// <summary>Höchstens so viele Bedingungen werden zum Ausdruck.</summary>
    MaxConditions = 2;
  public
    /// <summary>„In bedingten Ausdruck umwandeln“ für das if, dessen Kopf APosition enthält.</summary>
    class function ToExpression(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>„In if-Anweisung umwandeln“ für den äußersten Bedingungsausdruck an APosition.</summary>
    class function ToStatement(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; overload; static;
    /// <summary>Dasselbe für den Bedingungsausdruck AExpression.</summary>
    class function ToStatement(const AText: string; ATree: TSyntaxTree; AExpression: TSyntaxNode;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; overload; static;
    /// <summary>„IfThen durch bedingten Ausdruck ersetzen“ für den innersten IfThen-Aufruf an APosition.</summary>
    class function ReplaceIfThen(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>Lassen sich Werte der Typen A und B in einem Bedingungsausdruck verbinden?</summary>
    class function Compatible(const A, B: TValueType): Boolean; static;
    /// <summary>Äußerster Bedingungsausdruck, der ANode enthält (ANode selbst eingeschlossen); nil ohne.</summary>
    class function Outermost(ANode: TSyntaxNode): TSyntaxNode; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ExpressionText,
  Atlas.Text.Lines;

{ TValueType }

class function TValueType.Create(AKind: TValueKind; const AName: string): TValueType;
begin
  Result.Kind := AKind;
  Result.Name := AName;
end;

{ TConditionalLookup }

class function TConditionalLookup.KindOfType(const AType: TResolvedSymbol): TValueType;
begin
  Result := TValueType.Create(TValueKind.Unknown, '');
  if not AType.Found then
    Exit;
  if AType.Builtin or SameText(AType.UnitName, 'System') then
  begin
    if MatchText(AType.Name, ['Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'Word', 'Byte', 'LongInt', 'LongWord',
      'Int8', 'Int16', 'Int32', 'Int64', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'NativeInt', 'NativeUInt',
      'FixedInt', 'FixedUInt']) then
      Exit(TValueType.Create(TValueKind.Whole, ''));
    if MatchText(AType.Name, ['Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp']) then
      Exit(TValueType.Create(TValueKind.Float, ''));
    if MatchText(AType.Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'Char',
      'WideChar', 'AnsiChar', 'RawByteString', 'UTF8String']) then
      Exit(TValueType.Create(TValueKind.Text, ''));
    if SameText(AType.Name, 'Boolean') then
      Exit(TValueType.Create(TValueKind.Logical, ''));
  end;
  Result := TValueType.Create(TValueKind.Named, AType.Name);
end;

class function TConditionalLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TConditionalLookup;
var
  FileName: string;
begin
  FileName := AFileName;
  Result.ValueType :=
    function(ANode: TSyntaxNode): TValueType
    var
      Symbol, TypeInfo: TResolvedSymbol;
      TypeFound: Boolean;
    begin
      Result := TValueType.Create(TValueKind.Unknown, '');
      if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
        TSyntaxKind.Call]) or not AResolver.NodeType(ATree, FileName, ANode, Symbol, TypeInfo, TypeFound) then
        Exit;
      if TypeFound then
        Result := KindOfType(TypeInfo)
      // Ein Aufzählungswert hat den Typ seiner Aufzählung.
      else if (Symbol.SymbolKind = TIndexSymbolKind.EnumMember) and (Symbol.Container <> '') then
        Result := TValueType.Create(TValueKind.Named, Symbol.Container);
    end;
  Result.IfThen :=
    function(ACall: TSyntaxNode; out ADefault: string): Boolean
    var
      Symbol, TypeInfo: TResolvedSymbol;
      TypeFound: Boolean;
    begin
      ADefault := '';
      Result := (ACall.ChildCount > 0) and AResolver.NodeType(ATree, FileName, ACall[0], Symbol, TypeInfo,
        TypeFound) and MatchText(Symbol.UnitName, ['System.Math', 'System.StrUtils', 'Math', 'StrUtils']);
      if Result then
      begin
        if EndsText('StrUtils', Symbol.UnitName) then
          ADefault := ''''''
        else
          ADefault := '0';
      end;
    end;
end;

{ Hilfen }

function ValueKindOf(const AText: string; ANode: TSyntaxNode; const ALookup: TConditionalLookup): TValueType;
var
  Node: TSyntaxNode;
  Source, Op: string;
  Left, Right: TValueType;
begin
  Node := TExpressionText.Strip(ANode);
  Result := TValueType.Create(TValueKind.Unknown, '');
  case Node.Kind of
    TSyntaxKind.Literal:
    begin
      Source := TExpressionText.Source(AText, Node);
      if Source = '' then
        Exit;
      if CharInSet(Source[1], ['''', '#']) then
        Result := TValueType.Create(TValueKind.Text, '')
      else if CharInSet(Source[1], ['$', '%', '&']) then
        Result := TValueType.Create(TValueKind.Whole, '')
      else if CharInSet(Source[1], ['0'..'9']) then
      begin
        if (Pos('.', Source) > 0) or (Pos('e', LowerCase(Source)) > 0) then
          Result := TValueType.Create(TValueKind.Float, '')
        else
          Result := TValueType.Create(TValueKind.Whole, '');
      end
      else if TExpressionText.IsBooleanLiteral(Node) then
        Result := TValueType.Create(TValueKind.Logical, '')
      else if SameText(Source, 'nil') then
        Result := TValueType.Create(TValueKind.NilValue, '');
    end;
    TSyntaxKind.Identifier:
      if TExpressionText.IsBooleanLiteral(Node) then
        Result := TValueType.Create(TValueKind.Logical, '')
      else if SameText(Node.Name, 'nil') then
        Result := TValueType.Create(TValueKind.NilValue, '')
      else if Assigned(ALookup.ValueType) then
        Result := ALookup.ValueType(Node);
    TSyntaxKind.UnaryExpr:
      if SameText(Node.Name, 'not') then
        Result := TValueType.Create(TValueKind.Logical, '')
      else if (Node.ChildCount = 1) and MatchStr(Node.Name, ['-', '+']) then
        Result := ValueKindOf(AText, Node[0], ALookup);
    TSyntaxKind.BinaryExpr:
      if Node.ChildCount = 2 then
      begin
        Op := LowerCase(Node.Name);
        if TExpressionText.OperatorPrecedence(Op) = PrecedenceRelational then
          Exit(TValueType.Create(TValueKind.Logical, ''));
        Left := ValueKindOf(AText, Node[0], ALookup);
        Right := ValueKindOf(AText, Node[1], ALookup);
        if MatchStr(Op, ['and', 'or', 'xor']) and (Left.Kind = TValueKind.Logical) and
          (Right.Kind = TValueKind.Logical) then
          Result := Left
        else if MatchStr(Op, ['div', 'mod', 'shl', 'shr']) and (Left.Kind = TValueKind.Whole) and
          (Right.Kind = TValueKind.Whole) then
          Result := Left
        else if (Op = '/') and (Left.Kind in [TValueKind.Whole, TValueKind.Float]) and
          (Right.Kind in [TValueKind.Whole, TValueKind.Float]) then
          Result := TValueType.Create(TValueKind.Float, '')
        else if MatchStr(Op, ['+', '-', '*']) and (Left.Kind in [TValueKind.Whole, TValueKind.Float]) and
          (Right.Kind in [TValueKind.Whole, TValueKind.Float]) then
        begin
          if (Left.Kind = TValueKind.Float) or (Right.Kind = TValueKind.Float) then
            Result := TValueType.Create(TValueKind.Float, '')
          else
            Result := Left;
        end
        else if (Op = '+') and (Left.Kind = TValueKind.Text) and (Right.Kind = TValueKind.Text) then
          Result := Left;
      end;
    TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Call:
      if Assigned(ALookup.ValueType) then
        Result := ALookup.ValueType(Node);
    TSyntaxKind.IfExpr:
      if Node.ChildCount = 3 then
      begin
        Left := ValueKindOf(AText, Node[1], ALookup);
        Right := ValueKindOf(AText, Node[2], ALookup);
        if TConditionalExpression.Compatible(Left, Right) then
        begin
          if Left.Kind in [TValueKind.Whole, TValueKind.NilValue] then
            Result := Right
          else
            Result := Left;
        end;
      end;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

/// <summary>Teil eines neuen Bedingungsausdrucks: ein Bedingungsausdruck vor then bzw. else in Klammern.</summary>
function Inner(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := TExpressionText.Part(AText, ANode).AtLeast(PrecedenceIfExpr + 1);
end;

/// <summary>Text von AText zwischen den Offsets AStart und AEnd.</summary>
function Slice(const AText: string; AStart, AEnd: Integer): string;
begin
  Result := Copy(AText, AStart + 1, AEnd - AStart);
end;

/// <summary>Anweisung eines Zweigs, wenn er genau eine hat; nil sonst.</summary>
function SoleStatement(ABranch: TSyntaxNode): TSyntaxNode;
var
  Statements: TArray<TSyntaxNode>;
begin
  Result := nil;
  Statements := TStatementText.Statements(ABranch);
  if Length(Statements) = 1 then
    Result := Statements[0];
end;

/// <summary>Aufruf einer Aufrufanweisung (Name mit Argumenten); nil ohne Klammern.</summary>
function CallOf(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (AStatement.Kind = TSyntaxKind.CallStatement) and (AStatement.ChildCount = 1) and
    (AStatement[0].Kind = TSyntaxKind.Call) and (AStatement[0].ChildCount >= 2) then
    Result := AStatement[0];
end;

function IsExit(ACall: TSyntaxNode): Boolean;
begin
  Result := (ACall <> nil) and (ACall[0].Kind = TSyntaxKind.Identifier) and SameText(ACall[0].Name, 'Exit');
end;

{ TConditionalExpression }

class function TConditionalExpression.Compatible(const A, B: TValueType): Boolean;
begin
  if (A.Kind = TValueKind.Unknown) or (B.Kind = TValueKind.Unknown) then
    Exit(False);
  if (A.Kind in [TValueKind.Whole, TValueKind.Float]) and (B.Kind in [TValueKind.Whole, TValueKind.Float]) then
    Exit(True);
  if (A.Kind = TValueKind.NilValue) and (B.Kind in [TValueKind.NilValue, TValueKind.Named]) then
    Exit(True);
  if (B.Kind = TValueKind.NilValue) and (A.Kind = TValueKind.Named) then
    Exit(True);
  Result := (A.Kind = B.Kind) and ((A.Kind <> TValueKind.Named) or SameText(A.Name, B.Name));
end;

class function TConditionalExpression.Outermost(ANode: TSyntaxNode): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  Node := ANode;
  while (Node <> nil) and not TRoutineBody.IsStatement(Node) do
  begin
    if Node.Kind = TSyntaxKind.IfExpr then
      Result := Node;
    // Eine anonyme Methode beginnt einen eigenen Rumpf.
    if Node.Kind = TSyntaxKind.AnonymousMethod then
      Break;
    Node := Node.Parent;
  end;
end;

class function TConditionalExpression.ToExpression(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean;
var
  Head, Node, Statement, First, FirstCall, Call: TSyntaxNode;
  Conditions, Statements, Values: TArray<TSyntaxNode>;
  Index, Differs, Arg: Integer;
  FirstType: TValueType;
  Expression, Code: string;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  Head := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  if Head = nil then
    Exit;
  // Kette lesen: Bedingungen, je eine Anweisung, abschließendes else.
  Conditions := nil;
  Statements := nil;
  Node := Head;
  while True do
  begin
    if Node.ChildCount < 3 then
      Exit;
    Statement := SoleStatement(Node[1]);
    if Statement = nil then
      Exit;
    Conditions := Conditions + [Node[0]];
    Statements := Statements + [Statement];
    if (Node[2].Kind = TSyntaxKind.IfStatement) and (SoleStatement(Node[2]) = Node[2]) then
      Node := Node[2]
    else
    begin
      Statement := SoleStatement(Node[2]);
      if Statement = nil then
        Exit;
      Statements := Statements + [Statement];
      Break;
    end;
  end;
  if (Length(Conditions) > MaxConditions) or TStatementText.HasComment(ATree, Head.StartOffset, Head.EndOffset) then
    Exit;
  // Gleiche Form: Zuweisung an dasselbe Ziel oder derselbe Aufruf mit genau einem anderen Argument.
  First := Statements[0];
  Values := nil;
  Differs := -1;
  if First.Kind = TSyntaxKind.AssignStatement then
  begin
    if First.ChildCount <> 2 then
      Exit;
    for Statement in Statements do
    begin
      if (Statement.Kind <> TSyntaxKind.AssignStatement) or (Statement.ChildCount <> 2) or
        not TExpressionText.Same(AText, ATree, Statement[0], First[0]) then
        Exit;
      Values := Values + [Statement[1]];
    end;
  end
  else
  begin
    FirstCall := CallOf(First);
    if FirstCall = nil then
      Exit;
    for Statement in Statements do
    begin
      Call := CallOf(Statement);
      if (Call = nil) or (Call.ChildCount <> FirstCall.ChildCount) or
        not TExpressionText.Same(AText, ATree, Call[0], FirstCall[0]) then
        Exit;
      for Arg := 1 to Call.ChildCount - 1 do
        if not TExpressionText.Same(AText, ATree, Call[Arg], FirstCall[Arg]) then
        begin
          if (Differs >= 0) and (Differs <> Arg) then
            Exit;
          Differs := Arg;
        end;
    end;
    // Exit(A)/Exit(A) oder Log('a')/Log('a'): nichts zu verbinden.
    if Differs < 0 then
      Exit;
    for Statement in Statements do
    begin
      Call := CallOf(Statement);
      // Nur bei Exit dürfen die Werte Seiteneffekte haben: Bei anderen Aufrufen liefe die Bedingung sonst nach
      // den Argumenten davor statt vor allen.
      if not IsExit(FirstCall) then
        for Arg := 1 to Call.ChildCount - 1 do
          if not TExpressionText.IsSideEffectFree(Call[Arg]) then
            Exit;
      Values := Values + [Call[Differs]];
    end;
  end;
  // Verträgliche Typen.
  FirstType := ValueKindOf(AText, Values[0], ALookup);
  for Index := 1 to High(Values) do
    if not Compatible(FirstType, ValueKindOf(AText, Values[Index], ALookup)) then
      Exit;
  if FirstType.Kind = TValueKind.Unknown then
    Exit;
  Expression := '';
  for Index := 0 to High(Conditions) do
  begin
    if Index > 0 then
      Expression := Expression + ' else ';
    Expression := Expression + 'if ' + Inner(AText, Conditions[Index]) + ' then ' + Inner(AText, Values[Index]);
  end;
  Expression := Expression + ' else ' + TExpressionText.Source(AText, Values[High(Values)]);
  // Die erste Anweisung mit dem Ausdruck an der Stelle ihres Werts.
  Code := Slice(AText, First.StartOffset, Values[0].StartOffset) + Expression +
    Slice(AText, Values[0].EndOffset, First.EndOffset);
  ARewrite := TStatementRewrite.Create(ToExpressionTitle, TTextEdit.Create(TTextRange.Create(Head.StartPos,
    Head.EndPos), Code));
  Result := True;
end;

/// <summary>Hat der Teil von AStatement außerhalb von AExpression Seiteneffekte oder einen weiteren
/// Bedingungsausdruck? Der Aufruf einer Aufrufanweisung selbst (ACall) zählt nicht.</summary>
function RestIsUnsafe(AStatement, AExpression, ACall: TSyntaxNode): Boolean;
begin
  Result := AStatement.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Callee: TSyntaxNode;
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode = AExpression then
        Exit(TSyntaxSearchStep.Skip);
      case ANode.Kind of
        TSyntaxKind.IfExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr, TSyntaxKind.Error:
          Result := TSyntaxSearchStep.Found;
        TSyntaxKind.Call:
          if ANode <> ACall then
          begin
            Callee := nil;
            if ANode.ChildCount > 0 then
              Callee := ANode[0];
            if (Callee = nil) or (Callee.Kind <> TSyntaxKind.Identifier) or
              not TPureRoutines.IsPure(Callee.Name) then
              Result := TSyntaxSearchStep.Found;
          end;
      else
        // Übrige Arten: nichts zu tun.
      end;
    end) <> nil;
end;

type
  /// <summary>Baut die if-Anweisung zu einem Bedingungsausdruck: die Anweisung mit dem Wert an seiner Stelle,
  /// je Zweig.</summary>
  TStatementBuilder = record
    Text: string;
    Prefix: string;
    Suffix: string;
    /// <summary>Mindestvorrang des Werts an seiner Stelle.</summary>
    Context: Integer;
    Layout: TStatementLayout;
    function Statement(AValue: TSyntaxNode): string;
    function Branch(AValue: TSyntaxNode; const ALayout: TStatementLayout): string;
    function Chain(AExpression: TSyntaxNode; const ALayout: TStatementLayout): string;
  end;

function TStatementBuilder.Statement(AValue: TSyntaxNode): string;
begin
  Result := Prefix + TExpressionText.Part(Text, TExpressionText.Strip(AValue)).AtLeast(Context) + Suffix;
end;

function TStatementBuilder.Branch(AValue: TSyntaxNode; const ALayout: TStatementLayout): string;
var
  Value: TSyntaxNode;
  Deeper: TStatementLayout;
begin
  Value := TExpressionText.Strip(AValue);
  Deeper := ALayout.Deeper;
  if Value.Kind = TSyntaxKind.IfExpr then
    // Ein inneres if vor else braucht begin … end.
    Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak + Deeper.Indent +
      Chain(Value, Deeper) + ';' + ALayout.LineBreak + ALayout.Indent + 'end'
  else
    Result := ALayout.LineBreak + Deeper.Indent + Statement(Value);
end;

function TStatementBuilder.Chain(AExpression: TSyntaxNode; const ALayout: TStatementLayout): string;
var
  Node, ElseValue: TSyntaxNode;
begin
  Result := '';
  Node := AExpression;
  // else-if-Ketten in einer Schleife; nur Ausdrücke vor then werden verschachtelt.
  while True do
  begin
    Result := Result + 'if ' + TExpressionText.Source(Text, Node[0]) + ' then' + Branch(Node[1], ALayout);
    ElseValue := TExpressionText.Strip(Node[2]);
    if ElseValue.Kind = TSyntaxKind.IfExpr then
    begin
      Result := Result + ALayout.LineBreak + ALayout.Indent + 'else ';
      Node := ElseValue;
    end
    else
    begin
      Result := Result + ALayout.LineBreak + ALayout.Indent + 'else' + ALayout.LineBreak + ALayout.Deeper.Indent +
        Statement(ElseValue);
      Break;
    end;
  end;
end;

class function TConditionalExpression.ToStatement(const AText: string; ATree: TSyntaxTree;
  AExpression: TSyntaxNode; const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  Expression, Statement, Replaced, Call, Node: TSyntaxNode;
  Builder: TStatementBuilder;
  Declaration: string;
  Index: Integer;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (AExpression = nil) or (AExpression.Kind <> TSyntaxKind.IfExpr) then
    Exit;
  Expression := Outermost(AExpression);
  if (Expression = nil) or (Expression.ChildCount <> 3) then
    Exit;
  Statement := Expression.Parent;
  while (Statement <> nil) and not TRoutineBody.IsStatement(Statement) do
  begin
    if Statement.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    Statement := Statement.Parent;
  end;
  if Statement = nil then
    Exit;
  // Alle Bedingungsausdrücke der Kette brauchen drei Teile.
  Node := Expression.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.IfExpr) and (ACandidate.ChildCount <> 3) then
        Result := TSyntaxSearchStep.Found;
    end);
  if (Node <> nil) or TStatementText.HasComment(ATree, Statement.StartOffset, Statement.EndOffset) then
    Exit;
  // Der Wert ersetzt den Ausdruck samt umschließender Klammern; Klammern setzt der Vorrang.
  Replaced := Expression;
  while (Replaced.Parent <> nil) and (Replaced.Parent.Kind = TSyntaxKind.ParenExpr) and
    (Replaced.Parent.ChildCount = 1) do
    Replaced := Replaced.Parent;
  Call := nil;
  Declaration := '';
  Builder.Text := AText;
  Builder.Context := TExpressionText.ContextPrecedence(Replaced);
  Builder.Layout := TStatementLayout.Create(TTextLines.IndentOf(AText, Statement.StartPos.Line), ALayout.IndentUnit,
    ALayout.LineBreak);
  case Statement.Kind of
    TSyntaxKind.AssignStatement:
      begin
        Builder.Prefix := Slice(AText, Statement.StartOffset, Replaced.StartOffset);
        Builder.Suffix := Slice(AText, Replaced.EndOffset, Statement.EndOffset);
      end;
    TSyntaxKind.CallStatement:
      begin
        Call := CallOf(Statement);
        if Call = nil then
          Exit;
        Builder.Prefix := Slice(AText, Statement.StartOffset, Replaced.StartOffset);
        Builder.Suffix := Slice(AText, Replaced.EndOffset, Statement.EndOffset);
      end;
    TSyntaxKind.InlineVar:
      begin
        // var X: T := if … wird var X: T; und Zuweisungen; ohne Typ kein Angebot.
        if (Statement.ChildCount <> 2) or (Statement[0].Kind <> TSyntaxKind.TypeReference) or
          (Statement[1] <> Replaced) then
          Exit;
        Declaration := 'var ' + Statement.Name + ': ' + TExpressionText.Source(AText, Statement[0]) + ';' +
          ALayout.LineBreak + Builder.Layout.Indent;
        Builder.Prefix := Statement.Name + ' := ';
        Builder.Suffix := '';
      end;
  else
    Exit;
  end;
  if RestIsUnsafe(Statement, Expression, Call) then
    Exit;
  // In einer Aufrufanweisung muss der Ausdruck ein Argument sein oder in einem stecken, nicht im Namen.
  if Call <> nil then
  begin
    Node := Replaced;
    while (Node <> nil) and (Node.Parent <> Call) do
      Node := Node.Parent;
    Index := -1;
    if Node <> nil then
      Index := TStatementText.ChildIndex(Call, Node);
    if Index < 1 then
      Exit;
  end;
  ARewrite := TStatementRewrite.Create(ToStatementTitle, TTextEdit.Create(TTextRange.Create(Statement.StartPos,
    Statement.EndPos), Declaration + Builder.Chain(Expression, Builder.Layout)));
  Result := True;
end;

class function TConditionalExpression.ToStatement(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  Position: TTextPosition;
  Found: TSyntaxNode;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Position := APosition;
  Found := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not TStatementText.Encloses(ANode, Position) then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.IfExpr then
        Result := TSyntaxSearchStep.Found;
    end);
  Result := ToStatement(AText, ATree, Found, ALayout, ARewrite);
end;

class function TConditionalExpression.ReplaceIfThen(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; const ALookup: TConditionalLookup; out ARewrite: TStatementRewrite): Boolean;
var
  Position: TTextPosition;
  Call: TSyntaxNode;
  Fallback, ElseValue, Expression: string;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (ATree = nil) or (ATree.Root = nil) or not Assigned(ALookup.IfThen) then
    Exit;
  Position := APosition;
  Call := nil;
  // Der innerste IfThen-Aufruf an der Stelle.
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := TStatementText.Encloses(ANode, Position);
      if Result and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount in [3, 4]) and
        (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'IfThen') then
        Call := ANode;
    end);
  if (Call = nil) or not ALookup.IfThen(Call, Fallback) or
    TStatementText.HasComment(ATree, Call.StartOffset, Call.EndOffset) then
    Exit;
  if Call.ChildCount = 4 then
    ElseValue := TExpressionText.Source(AText, Call[3])
  else
    ElseValue := Fallback;
  Expression := 'if ' + Inner(AText, Call[1]) + ' then ' + Inner(AText, Call[2]) + ' else ' + ElseValue;
  ARewrite := TStatementRewrite.Create(IfThenTitle, TTextEdit.Create(TTextRange.Create(Call.StartPos, Call.EndPos),
    TExpressionPart.Create(Expression, PrecedenceIfExpr).AtLeast(TExpressionText.ContextPrecedence(Call))));
  Result := True;
end;

end.
