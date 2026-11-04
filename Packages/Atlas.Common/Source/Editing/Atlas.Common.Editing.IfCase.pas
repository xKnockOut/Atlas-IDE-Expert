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
    /// <summary>X = a bzw. a = X.</summary>
    function ReadEqual(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
    /// <summary>Elemente der Menge in X in [a, b..c].</summary>
    function ReadSet(ASet: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
    /// <summary>Marke aus einem Mengenelement: Konstante oder Bereich aus Konstanten.</summary>
    function ElementLabel(AElement: TSyntaxNode; out AItem: TCaseLabel): Boolean;
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

function TChainReader.ReadEqual(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
var
  mItem: TCaseLabel;
begin
  mItem := Default(TCaseLabel);
  if IsConstantLabel(ANode[1]) and MatchSelector(ANode[0]) then
  begin
    mItem.Low := TExpressionText.Strip(ANode[1]);
  end
  else if IsConstantLabel(ANode[0]) and MatchSelector(ANode[1]) then
  begin
    mItem.Low := TExpressionText.Strip(ANode[0]);
  end
  else
  begin
    Exit(False);
  end;
  ALabels := ALabels + [mItem];
  Result := True;
end;

function TChainReader.ElementLabel(AElement: TSyntaxNode; out AItem: TCaseLabel): Boolean;
begin
  AItem := Default(TCaseLabel);
  if AElement.Kind = TSyntaxKind.RangeExpr then
  begin
    Result := (AElement.ChildCount = 2) and IsConstantLabel(AElement[0]) and IsConstantLabel(AElement[1]);
    if Result then
    begin
      AItem.Low := TExpressionText.Strip(AElement[0]);
      AItem.High := TExpressionText.Strip(AElement[1]);
    end;
  end
  else
  begin
    Result := IsConstantLabel(AElement);
    AItem.Low := TExpressionText.Strip(AElement);
  end;
end;

function TChainReader.ReadSet(ASet: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
var
  mIndex: Integer;
  mItem: TCaseLabel;
begin
  Result := ASet.ChildCount > 0;
  for mIndex := 0 to ASet.ChildCount - 1 do
  begin
    if not ElementLabel(ASet[mIndex], mItem) then
    begin
      Exit(False);
    end;
    ALabels := ALabels + [mItem];
  end;
end;

function TChainReader.ReadLabels(ANode: TSyntaxNode; var ALabels: TArray<TCaseLabel>): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  mNode := TExpressionText.Strip(ANode);
  if (mNode.Kind <> TSyntaxKind.BinaryExpr) or (mNode.ChildCount <> 2) then
  begin
    Exit;
  end;
  if SameText(mNode.Name, 'or') then
  begin
    Result := ReadLabels(mNode[0], ALabels) and ReadLabels(mNode[1], ALabels);
  end
  else if SameText(mNode.Name, 'and') then
  begin
    Result := ReadRange(mNode, ALabels);
  end
  else if mNode.Name = '=' then
  begin
    Result := ReadEqual(mNode, ALabels);
  end
  else if SameText(mNode.Name, 'in') and (TExpressionText.Strip(mNode[1]).Kind = TSyntaxKind.SetConstructor) and
    MatchSelector(mNode[0]) then
  begin
    Result := ReadSet(TExpressionText.Strip(mNode[1]), ALabels);
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

/// <summary>Schlüssel aller Marken in AKeys; False bei einem leeren Bereich (b &lt; a).</summary>
function CollectKeys(const AText: string; ATree: TSyntaxTree; const ALinks: TArray<TChainLink>;
  out AKeys: TArray<TLabelKey>): Boolean;
var
  mLink: TChainLink;
  mItem: TCaseLabel;
  mKey: TLabelKey;
begin
  AKeys := nil;
  for mLink in ALinks do
  begin
    for mItem in mLink.Labels do
    begin
      mKey := LabelKey(AText, ATree, mItem);
      if mKey.Known and (mKey.High < mKey.Low) then
      begin
        Exit(False);
      end;
      AKeys := AKeys + [mKey];
    end;
  end;
  Result := True;
end;

/// <summary>Überschneiden sich die Marken A und B (Werte bzw. gleicher Text)?</summary>
function Overlap(const A, B: TLabelKey): Boolean;
begin
  if A.Known and B.Known then
  begin
    Result := (A.Low <= B.High) and (B.Low <= A.High);
  end
  else
  begin
    Result := A.Text = B.Text;
  end;
end;

/// <summary>Doppelte oder überlappende Marken (im case E2030), auch leere Bereiche (b &lt; a)?</summary>
function HasConflicts(const AText: string; ATree: TSyntaxTree; const ALinks: TArray<TChainLink>): Boolean;
var
  mKeys: TArray<TLabelKey>;
  mIndex, mOther: Integer;
begin
  if not CollectKeys(AText, ATree, ALinks, mKeys) then
  begin
    Exit(True);
  end;
  for mIndex := 0 to High(mKeys) do
  begin
    for mOther := mIndex + 1 to High(mKeys) do
    begin
      if Overlap(mKeys[mIndex], mKeys[mOther]) then
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

/// <summary>Kopf der if-Kette, deren if … then APosition enthält; nil ohne.</summary>
function ChainHeadAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
begin
  Result := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  while (Result <> nil) and IsChainElse(Result) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>case-Zweig zum Glied ALink: Marken, dahinter die Anweisung (einzeilig in derselben Zeile).</summary>
function LinkCode(const AText: string; ATree: TSyntaxTree; const ALink: TChainLink;
  const AItemLayout: TStatementLayout): string;
var
  mLabels: TArray<string>;
  mItem: TCaseLabel;
  mStatements: TArray<TSyntaxNode>;
  mBody: string;
begin
  mLabels := nil;
  for mItem in ALink.Labels do
  begin
    mLabels := mLabels + [LabelText(AText, mItem)];
  end;
  mStatements := TStatementText.Statements(ALink.Branch);
  // Mehrere Anweisungen: begin … end eine Stufe unter der Marke.
  if Length(mStatements) > 1 then
  begin
    mBody := TStatementText.GuardedBranch(AText, ATree, ALink.Branch, AItemLayout.Deeper, False);
  end
  else
  begin
    mBody := TStatementText.GuardedBranch(AText, ATree, ALink.Branch, AItemLayout, False);
  end;
  // Eine einzeilige Anweisung steht hinter der Marke, sonst in den folgenden Zeilen.
  if (Length(mStatements) = 1) and (Pos(AItemLayout.LineBreak, Trim(mBody)) = 0) and (Pos(#0, mBody) = 0) then
  begin
    mBody := ' ' + Trim(mBody);
  end;
  if mStatements = nil then
  begin
    mBody := ' ;';
  end
  else
  begin
    mBody := TStatementText.Finish(mBody, ';');
  end;
  Result := AItemLayout.LineBreak + AItemLayout.Indent + string.Join(', ', mLabels) + ':' + mBody;
end;

/// <summary>case bis vor sein end: Kopf, ein Zweig je Glied und der else-Zweig.</summary>
function CaseCode(const AText: string; ATree: TSyntaxTree; AReader: TChainReader;
  const ALayout: TStatementLayout): string;
var
  mLink: TChainLink;
  mStatements: TArray<TSyntaxNode>;
begin
  Result := 'case ' + TExpressionText.Source(AText, AReader.Selector) + ' of';
  for mLink in AReader.Links do
  begin
    Result := Result + LinkCode(AText, ATree, mLink, ALayout.Deeper);
  end;
  if AReader.ElseBranch = nil then
  begin
    Exit;
  end;
  mStatements := TStatementText.Statements(AReader.ElseBranch);
  Result := Result + ALayout.LineBreak + ALayout.Indent + 'else';
  if mStatements <> nil then
  begin
    Result := Result + ALayout.LineBreak + TStatementText.List(AText, ATree, mStatements, ALayout.Deeper.Indent,
      ALayout.LineBreak);
  end;
end;

class function TIfCase.ToCase(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TIfCaseLookup; const ALayout: TStatementLayout; out AConversion: TIfCaseConversion): Boolean;
var
  mHead: TSyntaxNode;
  mReader: TChainReader;
  mKind: TCaseSelectorKind;
  mLayout: TStatementLayout;
  mCode, mSuffix: string;
  mEndPos: TTextPosition;
begin
  Result := False;
  AConversion := Default(TIfCaseConversion);
  mHead := ChainHeadAt(ATree, APosition);
  if mHead = nil then
  begin
    Exit;
  end;
  mReader := TChainReader.Create(AText, ATree, ALookup);
  try
    if not mReader.Read(mHead) or not SelectorUsable(mReader.Selector, ALookup, mKind) or
      HasConflicts(AText, ATree, mReader.Links) or
      ChainComments(ATree, mHead, mReader.Links, mReader.ElseBranch) then
    begin
      Exit;
    end;
    mLayout := TStatementLayout.Create(IndentOfNode(AText, mHead), ALayout.IndentUnit, ALayout.LineBreak);
    mCode := CaseCode(AText, ATree, mReader, mLayout);
    // Kommentare hinter der letzten Anweisung (… B := 0; // Rest) wandern ins case; die Ersetzung reicht dann
    // bis hinter sie, das Semikolon steht hinter end.
    mEndPos := TStatementText.ReplacementEnd(ATree, mHead, ChainSpans(ATree, mReader.Links, mReader.ElseBranch),
      mSuffix);
    mCode := mCode + mLayout.LineBreak + mLayout.Indent + 'end' + mSuffix;
    AConversion := TStatementRewrite.Create(ToCaseTitle, TTextEdit.Create(TTextRange.Create(mHead.StartPos,
      mEndPos), mCode));
    Result := True;
  finally
    mReader.Free;
  end;
end;

/// <summary>Liegt der Wert der Konstanten ANode zwischen 0 und 255?</summary>
function FitsByte(const AText: string; ANode: TSyntaxNode): Boolean;
var
  mValue: Int64;
begin
  Result := TOrdinalConstants.Evaluate(TExpressionText.Source(AText, ANode), nil, mValue) and (mValue >= 0) and
    (mValue <= 255);
end;

/// <summary>Passen die Marken ALabels einer Ganzzahl in eine Menge (alle zwischen 0 und 255)?</summary>
function LabelsFitByte(const AText: string; const ALabels: TArray<TSyntaxNode>): Boolean;
var
  mLabel: TSyntaxNode;
begin
  for mLabel in ALabels do
  begin
    if mLabel.Kind <> TSyntaxKind.RangeExpr then
    begin
      Result := FitsByte(AText, mLabel);
    end
    else
    begin
      Result := (mLabel.ChildCount = 2) and FitsByte(AText, mLabel[0]) and FitsByte(AText, mLabel[1]);
    end;
    if not Result then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Bedingung X in [a, b..c].</summary>
function SetCondition(const AText: string; const ASelector: TExpressionPart;
  const ALabels: TArray<TSyntaxNode>): string;
var
  mItems: TArray<string>;
  mLabel: TSyntaxNode;
begin
  mItems := nil;
  for mLabel in ALabels do
  begin
    mItems := mItems + [TExpressionText.Source(AText, mLabel)];
  end;
  Result := TExpressionText.Combine('in', ASelector, TExpressionPart.Create('[' + string.Join(', ', mItems) + ']',
    PrecedenceOperand)).Text;
end;

/// <summary>Vergleich mit einer Marke: X = a bzw. (X >= a) and (X &lt;= b).</summary>
function LabelCondition(const AText: string; const ASelector: TExpressionPart; ALabel: TSyntaxNode):
  TExpressionPart;
begin
  if (ALabel.Kind = TSyntaxKind.RangeExpr) and (ALabel.ChildCount = 2) then
  begin
    Result := TExpressionText.Combine('and',
      TExpressionText.Combine('>=', ASelector, TExpressionText.Part(AText, ALabel[0])),
      TExpressionText.Combine('<=', ASelector, TExpressionText.Part(AText, ALabel[1])));
  end
  else
  begin
    Result := TExpressionText.Combine('=', ASelector, TExpressionText.Part(AText, ALabel));
  end;
end;

/// <summary>Bedingung für die Marken eines case-Zweigs.</summary>
function ConditionOf(const AText: string; const ASelector: TExpressionPart; const ALabels: TArray<TSyntaxNode>;
  AKind: TCaseSelectorKind): string;
var
  mJoined: TExpressionPart;
  mIndex: Integer;
begin
  // Mehrere Marken als Menge, wenn der Typ in eine Menge passt bzw. alle Ganzzahlen zwischen 0 und 255 liegen.
  if (Length(ALabels) > 1) and ((AKind = TCaseSelectorKind.SetElement) or ((AKind = TCaseSelectorKind.Whole) and
    LabelsFitByte(AText, ALabels))) then
  begin
    Exit(SetCondition(AText, ASelector, ALabels));
  end;
  mJoined := LabelCondition(AText, ASelector, ALabels[0]);
  for mIndex := 1 to High(ALabels) do
  begin
    mJoined := TExpressionText.Combine('or', mJoined, LabelCondition(AText, ASelector, ALabels[mIndex]));
  end;
  Result := mJoined.Text;
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

/// <summary>Anweisungen des else-Zweigs AElse eines case ohne leere Anweisungen.</summary>
function ElseStatementsOf(AElse: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AElse.ChildCount - 1 do
  begin
    if TRoutineBody.IsStatement(AElse[mIndex]) and (AElse[mIndex].Kind <> TSyntaxKind.EmptyStatement) then
    begin
      Result := Result + [AElse[mIndex]];
    end;
  end;
end;

/// <summary>Zweige (je Marke ihre Anweisung) und else-Anweisungen des case ACase; False bei einem Zweig ohne Marke
/// oder einem unbekannten Teil.</summary>
function CaseParts(ACase: TSyntaxNode; out ABranches, AElse: TArray<TSyntaxNode>): Boolean;
var
  mIndex: Integer;
  mItem: TSyntaxNode;
begin
  ABranches := nil;
  AElse := nil;
  for mIndex := 1 to ACase.ChildCount - 1 do
  begin
    mItem := ACase[mIndex];
    if (mItem.Kind = TSyntaxKind.CaseItem) and (Length(ItemLabels(mItem)) > 0) then
    begin
      ABranches := ABranches + [ItemBranch(mItem)];
    end
    else if mItem.Kind = TSyntaxKind.CaseElse then
    begin
      AElse := AElse + ElseStatementsOf(mItem);
    end
    else
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Bereiche der Zweige und der else-Anweisungen samt ihrer Kommentare.</summary>
function CaseSpans(ATree: TSyntaxTree; const ABranches, AElse: TArray<TSyntaxNode>): TArray<TStatementSpan>;
var
  mIndex: Integer;
begin
  Result := TStatementText.Spans(ATree, ABranches);
  for mIndex := 0 to High(AElse) do
  begin
    Result := Result + [TStatementText.SpanOf(ATree, AElse[mIndex], mIndex = High(AElse))];
  end;
end;

type
  /// <summary>Schreibt ein case als if-Kette.</summary>
  TIfChainWriter = record
    Text: string;
    Tree: TSyntaxTree;
    Selector: TExpressionPart;
    Kind: TCaseSelectorKind;
    Layout: TStatementLayout;
    /// <summary>Was hinter der letzten Anweisung steht (Semikolon, Kommentar).</summary>
    Suffix: string;
    /// <summary>Anweisung des Zweigs AItem; vor einem weiteren else (AGuard) braucht ein inneres if begin … end.
    /// </summary>
    function ItemCode(AItem: TSyntaxNode; AGuard: Boolean): string;
    /// <summary>if-Kette zu den Zweigen von ACase (ACount Stück) und den else-Anweisungen AElse.</summary>
    function Code(ACase: TSyntaxNode; ACount: Integer; const AElse: TArray<TSyntaxNode>): string;
  end;

function TIfChainWriter.ItemCode(AItem: TSyntaxNode; AGuard: Boolean): string;
begin
  if AGuard then
  begin
    Result := TStatementText.Finish(TStatementText.GuardedBranch(Text, Tree, ItemBranch(AItem), Layout, True), '');
  end
  else
  begin
    Result := TStatementText.Finish(TStatementText.GuardedBranch(Text, Tree, ItemBranch(AItem), Layout, False),
      Suffix);
  end;
end;

function TIfChainWriter.Code(ACase: TSyntaxNode; ACount: Integer; const AElse: TArray<TSyntaxNode>): string;
var
  mIndex, mLeft: Integer;
  mItem: TSyntaxNode;
begin
  Result := '';
  mLeft := ACount;
  for mIndex := 1 to ACase.ChildCount - 1 do
  begin
    mItem := ACase[mIndex];
    if mItem.Kind <> TSyntaxKind.CaseItem then
    begin
      Continue;
    end;
    if Result = '' then
    begin
      Result := 'if ';
    end
    else
    begin
      Result := Result + Layout.LineBreak + Layout.Indent + 'else if ';
    end;
    Result := Result + ConditionOf(Text, Selector, ItemLabels(mItem), Kind) + ' then';
    Dec(mLeft);
    Result := Result + ItemCode(mItem, (mLeft > 0) or (AElse <> nil));
  end;
  if AElse <> nil then
  begin
    Result := Result + Layout.LineBreak + Layout.Indent + 'else' + TStatementText.Finish(TStatementText.Branch(Text,
      Tree, AElse, Layout, True), Suffix);
  end;
end;

class function TIfCase.ToIf(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TIfCaseLookup; const ALayout: TStatementLayout; out AConversion: TIfCaseConversion): Boolean;
var
  mCase: TSyntaxNode;
  mWriter: TIfChainWriter;
  mBranches, mElse: TArray<TSyntaxNode>;
  mSpans: TArray<TStatementSpan>;
  mEndPos: TTextPosition;
begin
  Result := False;
  AConversion := Default(TIfCaseConversion);
  mWriter := Default(TIfChainWriter);
  mCase := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.CaseStatement);
  if (mCase = nil) or not SelectorUsable(TExpressionText.Strip(mCase[0]), ALookup, mWriter.Kind) or
    not CaseParts(mCase, mBranches, mElse) then
  begin
    Exit;
  end;
  // Kommentare zwischen case und of, in den Marken oder hinter else gingen verloren.
  mSpans := CaseSpans(ATree, mBranches, mElse);
  if (mBranches = nil) or TStatementText.Uncovered(ATree, mCase.StartOffset, mCase.EndOffset, mSpans) then
  begin
    Exit;
  end;
  mWriter.Text := AText;
  mWriter.Tree := ATree;
  mWriter.Layout := TStatementLayout.Create(TTextLines.IndentOf(AText, mCase.StartPos.Line), ALayout.IndentUnit,
    ALayout.LineBreak);
  mWriter.Selector := TExpressionText.Part(AText, TExpressionText.Strip(mCase[0]));
  mEndPos := TStatementText.ReplacementEnd(ATree, mCase, mSpans, mWriter.Suffix);
  AConversion := TStatementRewrite.Create(ToIfTitle, TTextEdit.Create(TTextRange.Create(mCase.StartPos, mEndPos),
    mWriter.Code(mCase, Length(mBranches), mElse)));
  Result := True;
end;

end.
