unit Atlas.Common.Editing.IfCase;

// if-Kette und case umwandeln (#646).
//   In case umwandeln: auf einer Kette if X = a then … else if X = b then …
//     else …. Jede Bedingung vergleicht denselben Ausdruck ohne Seiteneffekte
//     mit Konstanten: X = a (auch a = X), X in [a, b, c..d], (X >= a) and
//     (X <= b) (auch gespiegelt) und Verknüpfungen mit or. Der Ausdruck muss
//     ordinal sein (Ganzzahl, Zeichen, Aufzählung), die Marken Konstanten
//     (Literale, Konstantenausdrücke oder Namen, die der Aufrufer als Konstante
//     bestätigt). Doppelte oder überlappende Marken (E2030 im case) verhindern
//     die Aktion, ebenso Kommentare in den Bedingungen, die verloren gingen.
//     Der letzte else-Zweig wird zum else des case.
//   In if-Kette umwandeln: auf einem case über einen Ausdruck ohne
//     Seiteneffekte. Eine Marke wird X = a, ein Bereich (X >= a) and (X <= b),
//     mehrere werden X in [a, b] (nur bei Typen, die in eine Menge passen,
//     und Ganzzahlen von 0 bis 255), sonst eine or-Kette.
// begin … end steht nur, wo mehrere Anweisungen stehen (und um ein inneres
// if vor einem else, sonst gehörte das else zum inneren if). Kommentare in den
// Zweigen bleiben an ihrer Anweisung. Typ des Ausdrucks und Bedeutung der
// Namen liefert der Aufrufer (TIfCaseLookup), etwa über TNameResolver; ohne
// sicheren Typ gibt es keine Aktion.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.StatementText;

type
  /// <summary>Art des verglichenen Ausdrucks: unbekannt, nicht ordinal, Ganzzahl, Zeichen (Char, WideChar) oder
  /// ein Typ, der in eine Menge passt (Aufzählung, Boolean, Byte, AnsiChar).</summary>
  TCaseSelectorKind = (Unknown, NotOrdinal, Whole, Character, SetElement);

  /// <summary>Art des Ausdrucks ANode; Unknown, wenn nicht sicher bekannt. ACallable: Der Ausdruck ruft eine
  /// Funktion (auch ohne Klammern) und darf nicht mehrfach ausgewertet werden.</summary>
  TCaseSelectorKindFunc = reference to function(ANode: TSyntaxNode; out ACallable: Boolean): TCaseSelectorKind;
  /// <summary>Ist der Name bzw. die Kette ANode eine echte Konstante (untypisierte Konstante,
  /// Aufzählungswert)?</summary>
  TCaseConstantFunc = reference to function(ANode: TSyntaxNode): Boolean;

  TIfCaseLookup = record
    SelectorKind: TCaseSelectorKindFunc;
    IsConstant: TCaseConstantFunc;
    /// <summary>Typen und Konstanten über AResolver für den Baum ATree der Datei AFileName. Der Aufrufer hält
    /// Resolver und Baum, solange er die Funktionen nutzt (am besten mit PinTree).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TIfCaseLookup; static;
    /// <summary>Art eines aufgelösten Typs: Ganzzahl, Zeichen, Mengentyp, nicht ordinal oder unbekannt.</summary>
    class function KindOfType(const AType: TResolvedSymbol): TCaseSelectorKind; static;
  end;

  TIfCaseConversion = TStatementRewrite;

  TIfCase = class
  public const
    ToCaseTitle = 'In case umwandeln';
    ToIfTitle = 'In if-Kette umwandeln';
    /// <summary>So viele Bedingungen braucht eine Kette mindestens.</summary>
    MinConditions = 2;
  public
    /// <summary>„In case umwandeln“ für die if-Kette, deren Kopf (if … then) APosition enthält.</summary>
    class function ToCase(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TIfCaseLookup; const ALayout: TStatementLayout; out AConversion: TIfCaseConversion): Boolean;
      static;
    /// <summary>„In if-Kette umwandeln“ für das case, dessen Kopf (case … of) APosition enthält.</summary>
    class function ToIf(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TIfCaseLookup; const ALayout: TStatementLayout; out AConversion: TIfCaseConversion): Boolean;
      static;
    /// <summary>Zahl der Bedingungen der umwandelbaren if-Kette ab AIf (Kopf der Kette); 0, wenn sie sich nicht
    /// als case schreiben lässt. Für die Regel prefer-case.</summary>
    class function ConvertibleConditions(const AText: string; ATree: TSyntaxTree; AIf: TSyntaxNode;
      const ALookup: TIfCaseLookup): Integer; static;
    /// <summary>Ist AIf der Kopf einer if-Kette (nicht der else-Zweig eines anderen if)?</summary>
    class function IsChainHead(AIf: TSyntaxNode): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ExpressionText,
  Atlas.Text.Lines;

type
  /// <summary>Eine case-Marke: ein Wert (High = nil) oder ein Bereich Low..High.</summary>
  TCaseLabel = record
    Low: TSyntaxNode;
    High: TSyntaxNode;
  end;

  TChainLink = record
    Condition: TSyntaxNode;
    Branch: TSyntaxNode;
    Labels: TArray<TCaseLabel>;
  end;

  TChainReader = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FLookup: TIfCaseLookup;
    FSelector: TSyntaxNode;
    function MatchSelector(ANode: TSyntaxNode): Boolean;
    function IsConstantLabel(ANode: TSyntaxNode): Boolean;
    function ReadLabels(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
    function ReadRange(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
    function Bound(ANode: TSyntaxNode; out AValue: TSyntaxNode; out ALower: Boolean): Boolean;
  public
    Links: TArray<TChainLink>;
    ElseBranch: TSyntaxNode;
    constructor Create(const AText: string; ATree: TSyntaxTree; const ALookup: TIfCaseLookup);
    function Read(AHead: TSyntaxNode): Boolean;
    property Selector: TSyntaxNode read FSelector;
  end;

function IsChainElse(AIf: TSyntaxNode): Boolean;
begin
  Result := (AIf.Parent <> nil) and (AIf.Parent.Kind = TSyntaxKind.IfStatement) and (AIf.Parent.ChildCount = 3) and
    (AIf.Parent[2] = AIf);
end;

{ TChainReader }

constructor TChainReader.Create(const AText: string; ATree: TSyntaxTree; const ALookup: TIfCaseLookup);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FLookup := ALookup;
end;

function TChainReader.MatchSelector(ANode: TSyntaxNode): Boolean;
begin
  if FSelector = nil then
  begin
    // Der erste Vergleich legt den Ausdruck fest; eine Konstante ist kein Ausdruck für case.
    if IsConstantLabel(ANode) then
    begin
      Exit(False);
    end;
    FSelector := TExpressionText.Strip(ANode);
    Exit(True);
  end;
  Result := TExpressionText.Same(FTree, FSelector, ANode);
end;

function TChainReader.IsConstantLabel(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
  Value: Int64;
begin
  Node := TExpressionText.Strip(ANode);
  case Node.Kind of
    TSyntaxKind.Literal:
      // Zahlen und Zeichen; Strings mit mehr als einem Zeichen und Gleitkomma sind keine case-Marken.
      Result := TOrdinalConstants.Evaluate(TExpressionText.Source(FText, Node), nil, Value);
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      Result := TExpressionText.IsBooleanLiteral(Node) or (Assigned(FLookup.IsConstant) and
        FLookup.IsConstant(Node));
  else
    // Konstantenausdrücke wie Ord('A') + 1.
    Result := TOrdinalConstants.Evaluate(TExpressionText.Source(FText, Node), nil, Value);
  end;
end;

function TChainReader.Bound(ANode: TSyntaxNode; out AValue: TSyntaxNode; out ALower: Boolean): Boolean;
var
  Node: TSyntaxNode;
  Op: string;
begin
  // X >= a (untere Grenze), X <= b (obere), auch gespiegelt: a <= X, b >= X.
  Result := False;
  AValue := nil;
  ALower := False;
  Node := TExpressionText.Strip(ANode);
  if (Node.Kind <> TSyntaxKind.BinaryExpr) or (Node.ChildCount <> 2) then
  begin
    Exit;
  end;
  Op := Node.Name;
  if not MatchStr(Op, ['>=', '<=']) then
  begin
    Exit;
  end;
  if IsConstantLabel(Node[1]) and MatchSelector(Node[0]) then
  begin
    AValue := TExpressionText.Strip(Node[1]);
    ALower := Op = '>=';
    Result := True;
  end
  else if IsConstantLabel(Node[0]) and MatchSelector(Node[1]) then
  begin
    AValue := TExpressionText.Strip(Node[0]);
    ALower := Op = '<=';
    Result := True;
  end;
end;

function TChainReader.ReadRange(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
var
  First, Second: TSyntaxNode;
  FirstLower, SecondLower: Boolean;
  Item: TCaseLabel;
begin
  Result := (ANode.ChildCount = 2) and Bound(ANode[0], First, FirstLower) and Bound(ANode[1], Second, SecondLower) and
    (FirstLower <> SecondLower);
  if not Result then
  begin
    Exit;
  end;
  if FirstLower then
  begin
    Item.Low := First;
    Item.High := Second;
  end
  else
  begin
    Item.Low := Second;
    Item.High := First;
  end;
  ALabels := ALabels + [Item];
end;

function TChainReader.ReadLabels(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
var
  Node, Element: TSyntaxNode;
  Index: Integer;
  Item: TCaseLabel;
begin
  Result := False;
  Node := TExpressionText.Strip(ANode);
  if (Node.Kind <> TSyntaxKind.BinaryExpr) or (Node.ChildCount <> 2) then
  begin
    Exit;
  end;
  if SameText(Node.Name, 'or') then
  begin
    Exit(ReadLabels(Node[0], ALabels) and ReadLabels(Node[1], ALabels));
  end;
  if SameText(Node.Name, 'and') then
  begin
    Exit(ReadRange(Node, ALabels));
  end;
  if Node.Name = '=' then
  begin
    Item.High := nil;
    if IsConstantLabel(Node[1]) and MatchSelector(Node[0]) then
    begin
      Item.Low := TExpressionText.Strip(Node[1]);
    end
    else if IsConstantLabel(Node[0]) and MatchSelector(Node[1]) then
    begin
      Item.Low := TExpressionText.Strip(Node[0]);
    end
    else
    begin
      Exit;
    end;
    ALabels := ALabels + [Item];
    Exit(True);
  end;
  if SameText(Node.Name, 'in') and (TExpressionText.Strip(Node[1]).Kind = TSyntaxKind.SetConstructor) and
    MatchSelector(Node[0]) then
  begin
    Node := TExpressionText.Strip(Node[1]);
    if Node.ChildCount = 0 then
    begin
      Exit;
    end;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      Element := Node[Index];
      if Element.Kind = TSyntaxKind.RangeExpr then
      begin
        if (Element.ChildCount <> 2) or not IsConstantLabel(Element[0]) or not IsConstantLabel(Element[1]) then
        begin
          Exit;
        end;
        Item.Low := TExpressionText.Strip(Element[0]);
        Item.High := TExpressionText.Strip(Element[1]);
      end
      else
      begin
        if not IsConstantLabel(Element) then
        begin
          Exit;
        end;
        Item.Low := TExpressionText.Strip(Element);
        Item.High := nil;
      end;
      ALabels := ALabels + [Item];
    end;
    Exit(True);
  end;
end;

function TChainReader.Read(AHead: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
  Link: TChainLink;
begin
  Result := False;
  Links := nil;
  ElseBranch := nil;
  FSelector := nil;
  Node := AHead;
  while True do
  begin
    if (Node.ChildCount < 2) then
    begin
      Exit;
    end;
    Link.Condition := Node[0];
    Link.Branch := Node[1];
    Link.Labels := nil;
    if not ReadLabels(Link.Condition, Link.Labels) then
    begin
      Exit;
    end;
    Links := Links + [Link];
    if Node.ChildCount < 3 then
    begin
      Break;
    end;
    if Node[2].Kind = TSyntaxKind.IfStatement then
    begin
      Node := Node[2];
    end
    else
    begin
      ElseBranch := Node[2];
      Break;
    end;
  end;
  Result := (Length(Links) >= TIfCase.MinConditions) and (FSelector <> nil);
end;

type
  /// <summary>Wert einer Marke für die Prüfung auf Doppelte: Zahl, wenn auswertbar, sonst der normierte Text.
  /// </summary>
  TLabelKey = record
    Known: Boolean;
    Low, High: Int64;
    Text: string;
  end;

function LabelKey(const AText: string; ATree: TSyntaxTree; const ALabel: TCaseLabel): TLabelKey;
var
  LowValue, HighValue: Int64;
begin
  Result := Default(TLabelKey);
  Result.Text := TExpressionText.Normalized(ATree, ALabel.Low);
  if ALabel.High <> nil then
  begin
    Result.Text := Result.Text + ' .. ' + TExpressionText.Normalized(ATree, ALabel.High);
  end;
  if TOrdinalConstants.Evaluate(TExpressionText.Source(AText, ALabel.Low), nil, LowValue) then
  begin
    HighValue := LowValue;
    if (ALabel.High = nil) or TOrdinalConstants.Evaluate(TExpressionText.Source(AText, ALabel.High), nil,
      HighValue) then
    begin
      Result.Known := True;
      Result.Low := LowValue;
      Result.High := HighValue;
    end;
  end;
end;

/// <summary>Doppelte oder überlappende Marken (im case E2030), auch leere Bereiche (b &lt; a)?</summary>
function HasConflicts(const AText: string; ATree: TSyntaxTree; const ALinks: TArray<TChainLink>): Boolean;
var
  Keys: TArray<TLabelKey>;
  Link: TChainLink;
  Item: TCaseLabel;
  Key: TLabelKey;
  Index, Other: Integer;
begin
  Keys := nil;
  for Link in ALinks do
  begin
    for Item in Link.Labels do
    begin
      Key := LabelKey(AText, ATree, Item);
      if Key.Known and (Key.High < Key.Low) then
      begin
        Exit(True);
      end;
      Keys := Keys + [Key];
    end;
  end;
  for Index := 0 to High(Keys) do
  begin
    for Other := Index + 1 to High(Keys) do
    begin
      if Keys[Index].Known and Keys[Other].Known then
      begin
        if (Keys[Index].Low <= Keys[Other].High) and (Keys[Other].Low <= Keys[Index].High) then
        begin
          Exit(True);
        end;
      end
      else if Keys[Index].Text = Keys[Other].Text then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function SelectorUsable(ANode: TSyntaxNode; const ALookup: TIfCaseLookup; out AKind: TCaseSelectorKind): Boolean;
var
  Callable: Boolean;
begin
  AKind := TCaseSelectorKind.Unknown;
  Result := False;
  if not TExpressionText.IsSideEffectFree(ANode) or not Assigned(ALookup.SelectorKind) then
  begin
    Exit;
  end;
  Callable := False;
  AKind := ALookup.SelectorKind(ANode, Callable);
  Result := not Callable and (AKind in [TCaseSelectorKind.Whole, TCaseSelectorKind.Character,
    TCaseSelectorKind.SetElement]);
end;

/// <summary>Bereiche der Zweige einer if-Kette.</summary>
function ChainSpans(ATree: TSyntaxTree; const ALinks: TArray<TChainLink>; AElse: TSyntaxNode): TArray<TStatementSpan>;
var
  Branches: TArray<TSyntaxNode>;
  Link: TChainLink;
begin
  Branches := nil;
  for Link in ALinks do
  begin
    Branches := Branches + [Link.Branch];
  end;
  if AElse <> nil then
  begin
    Branches := Branches + [AElse];
  end;
  Result := TStatementText.Spans(ATree, Branches);
end;

/// <summary>Kommentar in einer Bedingung oder zwischen den Schlüsselwörtern der Kette, der beim Umschreiben
/// verloren ginge (Kommentare in den Zweigen bleiben).</summary>
function ChainComments(ATree: TSyntaxTree; AHead: TSyntaxNode; const ALinks: TArray<TChainLink>;
  AElse: TSyntaxNode): Boolean;
begin
  Result := TStatementText.Uncovered(ATree, AHead.StartOffset, AHead.EndOffset, ChainSpans(ATree, ALinks, AElse));
end;

function LabelText(const AText: string; const ALabel: TCaseLabel): string;
begin
  Result := TExpressionText.Source(AText, ALabel.Low);
  if ALabel.High <> nil then
  begin
    Result := Result + '..' + TExpressionText.Source(AText, ALabel.High);
  end;
end;

function IndentOfNode(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := TTextLines.IndentOf(AText, ANode.StartPos.Line);
end;

{ TIfCaseLookup }

class function TIfCaseLookup.KindOfType(const AType: TResolvedSymbol): TCaseSelectorKind;
begin
  Result := TCaseSelectorKind.Unknown;
  if not AType.Found then
  begin
    Exit;
  end;
  if AType.Builtin or SameText(AType.UnitName, 'System') then
  begin
    if MatchText(AType.Name, ['Boolean', 'Byte', 'AnsiChar', 'ByteBool']) then
    begin
      Result := TCaseSelectorKind.SetElement;
    end
    else if MatchText(AType.Name, ['Char', 'WideChar']) then
    begin
      Result := TCaseSelectorKind.Character;
    end
    else if MatchText(AType.Name, ['Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'Word', 'LongInt', 'LongWord',
      'Int8', 'Int16', 'Int32', 'Int64', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'NativeInt', 'NativeUInt',
      'FixedInt', 'FixedUInt']) then
    begin
      Result := TCaseSelectorKind.Whole;
    end
    else
    begin
      Result := TCaseSelectorKind.NotOrdinal;
    end;
    Exit;
  end;
  case AType.SymbolKind of
    TIndexSymbolKind.EnumType:
      Result := TCaseSelectorKind.SetElement;
    TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.ObjectType:
      Result := TCaseSelectorKind.NotOrdinal;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

class function TIfCaseLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TIfCaseLookup;
var
  FileName: string;
begin
  FileName := AFileName;
  Result.SelectorKind :=
    function(ANode: TSyntaxNode; out ACallable: Boolean): TCaseSelectorKind
    var
      Symbol, TypeInfo: TResolvedSymbol;
      TypeFound: Boolean;
    begin
      Result := TCaseSelectorKind.Unknown;
      ACallable := False;
      if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
        TSyntaxKind.Call]) or not AResolver.NodeType(ATree, FileName, ANode, Symbol, TypeInfo, TypeFound) then
      begin
        Exit;
      end;
      // Eine Funktion (auch ohne Klammern) liefe in der if-Kette mehrmals.
      ACallable := (ANode.Kind = TSyntaxKind.Call) or (Symbol.SymbolKind in [TIndexSymbolKind.Method,
        TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]);
      if TypeFound then
      begin
        Result := KindOfType(TypeInfo);
      end;
    end;
  Result.IsConstant :=
    function(ANode: TSyntaxNode): Boolean
    var
      Symbol, TypeInfo: TResolvedSymbol;
      TypeFound: Boolean;
    begin
      Result := AResolver.NodeType(ATree, FileName, ANode, Symbol, TypeInfo, TypeFound) and
        ((Symbol.SymbolKind = TIndexSymbolKind.EnumMember) or ((Symbol.SymbolKind = TIndexSymbolKind.Constant) and
        (Symbol.TypeName = ''))) and not Symbol.IsParameter;
    end;
end;

{ TIfCase }

class function TIfCase.IsChainHead(AIf: TSyntaxNode): Boolean;
begin
  Result := (AIf <> nil) and (AIf.Kind = TSyntaxKind.IfStatement) and not IsChainElse(AIf);
end;

class function TIfCase.ConvertibleConditions(const AText: string; ATree: TSyntaxTree; AIf: TSyntaxNode;
  const ALookup: TIfCaseLookup): Integer;
var
  Reader: TChainReader;
  Kind: TCaseSelectorKind;
begin
  Result := 0;
  if not IsChainHead(AIf) then
  begin
    Exit;
  end;
  Reader := TChainReader.Create(AText, ATree, ALookup);
  try
    if Reader.Read(AIf) and SelectorUsable(Reader.Selector, ALookup, Kind) and
      not HasConflicts(AText, ATree, Reader.Links) and
      not ChainComments(ATree, AIf, Reader.Links, Reader.ElseBranch) then
    begin
      Result := Length(Reader.Links);
    end;
  finally
    Reader.Free;
  end;
end;

class function TIfCase.ToCase(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TIfCaseLookup; const ALayout: TStatementLayout; out AConversion: TIfCaseConversion): Boolean;
var
  Head: TSyntaxNode;
  Reader: TChainReader;
  Kind: TCaseSelectorKind;
  Layout, ItemLayout: TStatementLayout;
  Link: TChainLink;
  Labels: TArray<string>;
  Item: TCaseLabel;
  Body, Code, LineBreak, Suffix: string;
  Statements: TArray<TSyntaxNode>;
  EndPos: TTextPosition;
begin
  Result := False;
  AConversion := Default(TIfCaseConversion);
  Head := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  while (Head <> nil) and IsChainElse(Head) do
  begin
    Head := Head.Parent;
  end;
  if Head = nil then
  begin
    Exit;
  end;
  Reader := TChainReader.Create(AText, ATree, ALookup);
  try
    if not Reader.Read(Head) or not SelectorUsable(Reader.Selector, ALookup, Kind) or
      HasConflicts(AText, ATree, Reader.Links) or
      ChainComments(ATree, Head, Reader.Links, Reader.ElseBranch) then
    begin
      Exit;
    end;
    LineBreak := ALayout.LineBreak;
    Layout := TStatementLayout.Create(IndentOfNode(AText, Head), ALayout.IndentUnit, LineBreak);
    ItemLayout := Layout.Deeper;
    Code := 'case ' + TExpressionText.Source(AText, Reader.Selector) + ' of';
    for Link in Reader.Links do
    begin
      Labels := nil;
      for Item in Link.Labels do
      begin
        Labels := Labels + [LabelText(AText, Item)];
      end;
      Statements := TStatementText.Statements(Link.Branch);
      // Mehrere Anweisungen: begin … end eine Stufe unter der Marke.
      if Length(Statements) > 1 then
      begin
        Body := TStatementText.GuardedBranch(AText, ATree, Link.Branch, ItemLayout.Deeper, False);
      end
      else
      begin
        Body := TStatementText.GuardedBranch(AText, ATree, Link.Branch, ItemLayout, False);
      end;
      // Eine einzeilige Anweisung steht hinter der Marke, sonst in den folgenden Zeilen.
      if (Length(Statements) = 1) and (Pos(LineBreak, Trim(Body)) = 0) and (Pos(#0, Body) = 0) then
      begin
        Body := ' ' + Trim(Body);
      end;
      if Statements = nil then
      begin
        Body := ' ;';
      end
      else
      begin
        Body := TStatementText.Finish(Body, ';');
      end;
      Code := Code + LineBreak + ItemLayout.Indent + string.Join(', ', Labels) + ':' + Body;
    end;
    if Reader.ElseBranch <> nil then
    begin
      Statements := TStatementText.Statements(Reader.ElseBranch);
      Code := Code + LineBreak + Layout.Indent + 'else';
      if Statements <> nil then
      begin
        Code := Code + LineBreak + TStatementText.List(AText, ATree, Statements, ItemLayout.Indent, LineBreak);
      end;
    end;
    // Kommentare hinter der letzten Anweisung (… B := 0; // Rest) wandern ins case; die Ersetzung reicht dann
    // bis hinter sie, das Semikolon steht hinter end.
    EndPos := TStatementText.ReplacementEnd(ATree, Head, ChainSpans(ATree, Reader.Links, Reader.ElseBranch), Suffix);
    Code := Code + LineBreak + Layout.Indent + 'end' + Suffix;
    AConversion := TStatementRewrite.Create(ToCaseTitle, TTextEdit.Create(TTextRange.Create(Head.StartPos, EndPos),
      Code));
    Result := True;
  finally
    Reader.Free;
  end;
end;

/// <summary>Bedingung für die Marken eines case-Zweigs.</summary>
function ConditionOf(const AText: string; const ASelector: TExpressionPart; const ALabels: TArray<TSyntaxNode>;
  AKind: TCaseSelectorKind): string;
var
  Parts: TArray<TExpressionPart>;
  Items: TArray<string>;
  LabelNode: TSyntaxNode;
  Part, Joined: TExpressionPart;
  InSet: Boolean;
  Value: Int64;
  Index: Integer;

  function Fits(ANode: TSyntaxNode): Boolean;
  begin
    Result := TOrdinalConstants.Evaluate(TExpressionText.Source(AText, ANode), nil, Value) and (Value >= 0) and
      (Value <= 255);
  end;

begin
  // Mehrere Marken als Menge, wenn der Typ in eine Menge passt bzw. alle Ganzzahlen zwischen 0 und 255 liegen.
  InSet := (Length(ALabels) > 1) and (AKind in [TCaseSelectorKind.SetElement, TCaseSelectorKind.Whole]);
  if InSet and (AKind = TCaseSelectorKind.Whole) then
  begin
    for LabelNode in ALabels do
    begin
      if LabelNode.Kind = TSyntaxKind.RangeExpr then
      begin
        if (LabelNode.ChildCount <> 2) or not Fits(LabelNode[0]) or not Fits(LabelNode[1]) then
        begin
          InSet := False;
        end;
      end
      else if not Fits(LabelNode) then
      begin
        InSet := False;
      end;
    end;
  end;
  if InSet then
  begin
    Items := nil;
    for LabelNode in ALabels do
    begin
      Items := Items + [TExpressionText.Source(AText, LabelNode)];
    end;
    Exit(TExpressionText.Combine('in', ASelector, TExpressionPart.Create('[' + string.Join(', ', Items) + ']',
      PrecedenceOperand)).Text);
  end;
  Parts := nil;
  for LabelNode in ALabels do
  begin
    if (LabelNode.Kind = TSyntaxKind.RangeExpr) and (LabelNode.ChildCount = 2) then
    begin
      Parts := Parts + [TExpressionText.Combine('and',
        TExpressionText.Combine('>=', ASelector, TExpressionText.Part(AText, LabelNode[0])),
        TExpressionText.Combine('<=', ASelector, TExpressionText.Part(AText, LabelNode[1])))];
    end
    else
    begin
      Parts := Parts + [TExpressionText.Combine('=', ASelector, TExpressionText.Part(AText, LabelNode))];
    end;
  end;
  Joined := Parts[0];
  for Index := 1 to High(Parts) do
  begin
    Part := Parts[Index];
    Joined := TExpressionText.Combine('or', Joined, Part);
  end;
  Result := Joined.Text;
end;

/// <summary>Marken eines case-Zweigs (alle Kinder außer der Anweisung).</summary>
function ItemLabels(AItem: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AItem.ChildCount - 1 do
  begin
    if not TRoutineBody.IsStatement(AItem[Index]) then
    begin
      Result := Result + [AItem[Index]];
    end;
  end;
end;

/// <summary>Anweisung eines case-Zweigs; nil bei "a: ;".</summary>
function ItemBranch(AItem: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (AItem.ChildCount > 0) and TRoutineBody.IsStatement(AItem[AItem.ChildCount - 1]) then
  begin
    Result := AItem[AItem.ChildCount - 1];
  end;
end;

class function TIfCase.ToIf(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TIfCaseLookup; const ALayout: TStatementLayout; out AConversion: TIfCaseConversion): Boolean;
var
  CaseNode, Item, Selector: TSyntaxNode;
  Kind: TCaseSelectorKind;
  Layout: TStatementLayout;
  Labels, Branches: TArray<TSyntaxNode>;
  ElseStatements: TArray<TSyntaxNode>;
  Spans: TArray<TStatementSpan>;
  Index, LabelIndex, Count: Integer;
  Code, LineBreak, Suffix: string;
  SelectorPart: TExpressionPart;
  First: Boolean;
  EndPos: TTextPosition;
begin
  Result := False;
  AConversion := Default(TIfCaseConversion);
  CaseNode := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.CaseStatement);
  if CaseNode = nil then
  begin
    Exit;
  end;
  Selector := CaseNode[0];
  if not SelectorUsable(TExpressionText.Strip(Selector), ALookup, Kind) then
  begin
    Exit;
  end;
  Count := 0;
  Branches := nil;
  ElseStatements := nil;
  for Index := 1 to CaseNode.ChildCount - 1 do
  begin
    Item := CaseNode[Index];
    if Item.Kind = TSyntaxKind.CaseItem then
    begin
      if Length(ItemLabels(Item)) = 0 then
      begin
        Exit;
      end;
      Branches := Branches + [ItemBranch(Item)];
      Inc(Count);
    end
    else if Item.Kind = TSyntaxKind.CaseElse then
    begin
      for LabelIndex := 0 to Item.ChildCount - 1 do
      begin
        if TRoutineBody.IsStatement(Item[LabelIndex]) and (Item[LabelIndex].Kind <> TSyntaxKind.EmptyStatement) then
        begin
          ElseStatements := ElseStatements + [Item[LabelIndex]];
        end;
      end;
    end
    else
    begin
      Exit;
    end;
  end;
  // Kommentare zwischen case und of, in den Marken oder hinter else gingen verloren.
  Spans := TStatementText.Spans(ATree, Branches);
  for Index := 0 to High(ElseStatements) do
  begin
    Spans := Spans + [TStatementText.SpanOf(ATree, ElseStatements[Index], Index = High(ElseStatements))];
  end;
  if (Count = 0) or TStatementText.Uncovered(ATree, CaseNode.StartOffset, CaseNode.EndOffset, Spans) then
  begin
    Exit;
  end;
  LineBreak := ALayout.LineBreak;
  Layout := TStatementLayout.Create(TTextLines.IndentOf(AText, CaseNode.StartPos.Line), ALayout.IndentUnit, LineBreak);
  EndPos := TStatementText.ReplacementEnd(ATree, CaseNode, Spans, Suffix);
  SelectorPart := TExpressionText.Part(AText, TExpressionText.Strip(Selector));
  Code := '';
  First := True;
  for Index := 1 to CaseNode.ChildCount - 1 do
  begin
    Item := CaseNode[Index];
    if Item.Kind <> TSyntaxKind.CaseItem then
    begin
      Continue;
    end;
    Labels := ItemLabels(Item);
    if First then
    begin
      Code := 'if ';
    end
    else
    begin
      Code := Code + LineBreak + Layout.Indent + 'else if ';
    end;
    First := False;
    Code := Code + ConditionOf(AText, SelectorPart, Labels, Kind) + ' then';
    Dec(Count);
    // Vor einem weiteren else: ein inneres if braucht begin … end.
    if (Count > 0) or (ElseStatements <> nil) then
    begin
      Code := Code + TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, ItemBranch(Item), Layout, True), '');
    end
    else
    begin
      Code := Code + TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, ItemBranch(Item), Layout, False),
        Suffix);
    end;
  end;
  if ElseStatements <> nil then
  begin
    Code := Code + LineBreak + Layout.Indent + 'else' + TStatementText.Finish(TStatementText.Branch(AText, ATree,
      ElseStatements, Layout, True), Suffix);
  end;
  AConversion := TStatementRewrite.Create(ToIfTitle, TTextEdit.Create(TTextRange.Create(CaseNode.StartPos, EndPos),
    Code));
  Result := True;
end;

end.
