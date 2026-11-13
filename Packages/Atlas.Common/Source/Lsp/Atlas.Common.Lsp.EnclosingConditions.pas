unit Atlas.Common.Lsp.EnclosingConditions;

// Befehl atlas.server.enclosingConditions (#1878): „Warum bin ich hier?“ beim
// Debug-Halt. Die Steueranweisungen, die die Zeile des Halts umgeben, von innen
// nach außen bis zur Routine, höchstens ADepth Stück:
//   if (Zweig then oder else), while, repeat … until, for (Variable, Grenzen),
//   for … in (Variable, Sammlung), case (Selektor und gewählter Zweig) und with
//   (nur als Hinweis).
// Argumente: [uri, line, depth] (Zeile ab 0, depth 1–10, Vorgabe 3).
// Antwort: {"format": 1, "blocks": [{"kind": "if", "line": 12, "character": 2,
//   "branch": "else", "parts": [{"kind": "and", "operator": "and", "text": "A and B",
//   "parent": -1, "call": false, "line": 12, "character": 5}, …]}]}
// line ist die Zeile, an deren Ende das Plugin die Werte zeigt: das Ende der
// Bedingung (bei repeat die until-Zeile, bei for die Zeile mit do).
// parts ist der Baum der Bedingung in Vorordnung (parent -1 = Wurzel):
//   and, or, xor (Glieder gleicher Art zusammengefasst), not, compare
//   (=, <>, <, >, <=, >=, in, is; die beiden Seiten als Kinder der Art value)
//   und value (alles andere, als Ganzes ausgewertet). Klammern fallen weg.
// call: Der Teil enthält einen Aufruf (Funktion, Methode, Property mit
// Getter); das Plugin wertet ihn nur auf Klick aus. Syntaktische Aufrufe mit
// Klammern erkennt die Unit selbst, die übrigen meldet ACallsAt (Namensauflösung
// über Atlas.Common.Lsp.StepTargets, für die Zeile, in der die Bedingung beginnt).
// Bei for stehen in parts die Schleifenvariable und die Endgrenze (bzw. die
// Sammlung), bei case der Selektor, jeweils als value; with nennt seine
// Ausdrücke als value. Eine Anweisung, die in der Zeile des Halts beginnt, zählt
// nicht: Ihr Kopf ist noch nicht ausgewertet.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Teil einer Bedingung; Parent verweist in dasselbe Feld (-1 = Wurzel).</summary>
  TLspConditionPart = record
    /// <summary>and, or, xor, not, compare oder value.</summary>
    Kind: string;
    /// <summary>Operator bei and, or, xor, not und compare; '' bei value.</summary>
    Operator_: string;
    Text: string;
    Parent: Integer;
    Call: Boolean;
    Position: TTextPosition;
  end;

  TLspConditionParts = TArray<TLspConditionPart>;

  TLspEnclosingBlock = record
    /// <summary>if, while, repeat, for, forIn, case oder with.</summary>
    Kind: string;
    /// <summary>Zeile (ab 0), an deren Ende die Werte stehen.</summary>
    Line: Integer;
    /// <summary>Anfang des Schlüsselworts der Anweisung.</summary>
    Start: TTextPosition;
    /// <summary>if: then oder else; case: Marken des gewählten Zweigs oder else; sonst ''.</summary>
    Branch: string;
    /// <summary>for: downto statt to.</summary>
    Descending: Boolean;
    Parts: TLspConditionParts;
  end;

  TLspEnclosingBlocks = TArray<TLspEnclosingBlock>;

  /// <summary>Positionen der Aufrufe, die in der Zeile ALine (ab 0) beginnen bzw. dort ausgelöst werden.</summary>
  TLspCallsAt = reference to function(ALine: Integer): TArray<TTextPosition>;

  TLspEnclosingConditions = class
  public const
    cCommand = 'atlas.server.enclosingConditions';
    cDefaultDepth = 3;
    cMaxDepth = 10;
    cMaxText = 80;
  private
    FTree: TSyntaxTree;
    FText: string;
    FCallsAt: TLspCallsAt;
    FCalls: TArray<TTextPosition>;
    function TextOf(ANode: TSyntaxNode): string;
    function HasCall(ANode: TSyntaxNode): Boolean;
    function NewPart(ANode: TSyntaxNode; const AKind, AOperator: string; AParent: Integer): TLspConditionPart;
    procedure AddValue(var AParts: TLspConditionParts; ANode: TSyntaxNode; AParent: Integer);
    procedure AddChain(var AParts: TLspConditionParts; ANode: TSyntaxNode; const AOperator: string;
      AParent: Integer);
    procedure AddPart(var AParts: TLspConditionParts; ANode: TSyntaxNode; AParent: Integer);
    procedure LoadCalls(ANode: TSyntaxNode);
    function Condition(ANode: TSyntaxNode): TLspConditionParts;
    function Path(ALine: Integer): TArray<TSyntaxNode>;
    function BlockOf(ANode, AThrough, ANext: TSyntaxNode; out ABlock: TLspEnclosingBlock): Boolean;
    function IfBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
    function LoopBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
    function ForBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
    function CaseBlock(ANode, AThrough, ANext: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
    function WithBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
  public
    /// <summary>ACallsAt darf nil sein: Dann zählen nur Aufrufe mit Klammern.</summary>
    constructor Create(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt);
    /// <summary>Die umgebenden Anweisungen der Zeile ALine (ab 0), von innen nach außen, höchstens ADepth.
    /// </summary>
    function Answer(ALine, ADepth: Integer): TLspEnclosingBlocks;
    /// <summary>Der Befehl: Antwort als JSON (format 1).</summary>
    function Execute(ALine, ADepth: Integer): TJSONObject;
    /// <summary>Teile der Bedingung ANode wie in Answer (für die Vorschau kommender Bedingungen, #2169).</summary>
    function ConditionParts(ANode: TSyntaxNode): TLspConditionParts;
    /// <summary>ANode als Teil der Art value an AParts anhängen, Aufrufe aus der Zeile von ANode.</summary>
    procedure AppendValue(var AParts: TLspConditionParts; ANode: TSyntaxNode);
    class function PartToJson(const APart: TLspConditionPart): TJSONObject; static;
    class function ToJson(const ABlocks: TLspEnclosingBlocks): TJSONObject; static;
    /// <summary>ADepth auf 1–MaxDepth begrenzt; 0 und weniger = DefaultDepth.</summary>
    class function ClampDepth(ADepth: Integer): Integer; static;
  end;

implementation

uses
  System.Math;

const
  cCompareOperators: array[0..7] of string = ('=', '<>', '<', '>', '<=', '>=', 'in', 'is');

function IsCompare(const AOperator: string): Boolean;
var
  mOperator: string;
begin
  Result := False;
  for mOperator in cCompareOperators do
  begin
    if SameText(mOperator, AOperator) then
    begin
      Exit(True);
    end;
  end;
end;

function IsLogical(const AOperator: string): Boolean;
begin
  Result := SameText(AOperator, 'and') or SameText(AOperator, 'or') or SameText(AOperator, 'xor');
end;

/// <summary>Klammern (auch mehrfach) überspringen.</summary>
function Unwrap(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result.Children[0];
  end;
end;

function Contains(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  Result := (ANode.StartPos.Line <= ALine) and (ALine <= ANode.EndPos.Line);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function IsBoundary(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod];
end;

function IndexOfChild(ANode, AChild: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode.Children[mIndex] = AChild then
    begin
      Exit(mIndex);
    end;
  end;
end;

{ TLspEnclosingConditions }

constructor TLspEnclosingConditions.Create(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FCallsAt := ACallsAt;
end;

class function TLspEnclosingConditions.ClampDepth(ADepth: Integer): Integer;
begin
  Result := ADepth;
  if Result <= 0 then
  begin
    Result := cDefaultDepth;
  end;
  Result := Min(Result, cMaxDepth);
end;

function TLspEnclosingConditions.TextOf(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode = nil) or (ANode.EndOffset <= ANode.StartOffset) or (ANode.EndOffset > Length(FText)) then
  begin
    Exit;
  end;
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  // Mehrzeilig: in eine Zeile.
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
  while Pos('  ', Result) > 0 do
  begin
    Result := Result.Replace('  ', ' ');
  end;
  if Length(Result) > cMaxText then
  begin
    Result := Copy(Result, 1, cMaxText - 1) + '…';
  end;
end;

function TLspEnclosingConditions.HasCall(ANode: TSyntaxNode): Boolean;
var
  mPosition: TTextPosition;
  mFound: TSyntaxNode;
begin
  // Aufrufe mit Klammern sieht der Baum selbst; anonyme Methoden rufen nichts auf.
  mFound := ANode.Search(
    function(ANext: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANext.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ANext.Kind = TSyntaxKind.Call then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := mFound <> nil;
  if Result then
  begin
    Exit;
  end;
  // Getter und Aufrufe ohne Klammern: aus der Namensauflösung.
  for mPosition in FCalls do
  begin
    if not Before(mPosition, ANode.StartPos) and Before(mPosition, ANode.EndPos) then
    begin
      Exit(True);
    end;
  end;
end;

function TLspEnclosingConditions.NewPart(ANode: TSyntaxNode; const AKind, AOperator: string;
  AParent: Integer): TLspConditionPart;
begin
  Result := Default(TLspConditionPart);
  Result.Kind := AKind;
  Result.Operator_ := AOperator;
  Result.Text := TextOf(ANode);
  Result.Parent := AParent;
  Result.Call := HasCall(ANode);
  Result.Position := ANode.StartPos;
end;

procedure TLspEnclosingConditions.AddValue(var AParts: TLspConditionParts; ANode: TSyntaxNode; AParent: Integer);
begin
  AParts := AParts + [NewPart(ANode, 'value', '', AParent)];
end;

procedure TLspEnclosingConditions.AddChain(var AParts: TLspConditionParts; ANode: TSyntaxNode;
  const AOperator: string; AParent: Integer);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  // A and B and C ist links geschachtelt: Glieder desselben Operators in einen Teil.
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := Unwrap(ANode.Children[mIndex]);
    if (mChild.Kind = TSyntaxKind.BinaryExpr) and SameText(mChild.Name, AOperator) and
      (ANode.Children[mIndex].Kind <> TSyntaxKind.ParenExpr) then
    begin
      AddChain(AParts, mChild, AOperator, AParent);
    end
    else
    begin
      AddPart(AParts, mChild, AParent);
    end;
  end;
end;

procedure TLspEnclosingConditions.AddPart(var AParts: TLspConditionParts; ANode: TSyntaxNode; AParent: Integer);
var
  mSelf: Integer;
  mNode: TSyntaxNode;
begin
  mNode := Unwrap(ANode);
  mSelf := Length(AParts);
  if (mNode.Kind = TSyntaxKind.BinaryExpr) and (mNode.ChildCount = 2) and IsLogical(mNode.Name) then
  begin
    AParts := AParts + [NewPart(mNode, LowerCase(mNode.Name), LowerCase(mNode.Name), AParent)];
    AddChain(AParts, mNode, mNode.Name, mSelf);
  end
  else if (mNode.Kind = TSyntaxKind.UnaryExpr) and SameText(mNode.Name, 'not') and (mNode.ChildCount = 1) then
  begin
    AParts := AParts + [NewPart(mNode, 'not', 'not', AParent)];
    AddPart(AParts, mNode.Children[0], mSelf);
  end
  else if (mNode.Kind = TSyntaxKind.BinaryExpr) and (mNode.ChildCount = 2) and IsCompare(mNode.Name) then
  begin
    AParts := AParts + [NewPart(mNode, 'compare', LowerCase(mNode.Name), AParent)];
    AddValue(AParts, Unwrap(mNode.Children[0]), mSelf);
    AddValue(AParts, Unwrap(mNode.Children[1]), mSelf);
  end
  else
  begin
    AddValue(AParts, mNode, AParent);
  end;
end;

procedure TLspEnclosingConditions.LoadCalls(ANode: TSyntaxNode);
begin
  FCalls := nil;
  if Assigned(FCallsAt) and (ANode <> nil) then
  begin
    FCalls := FCallsAt(ANode.StartPos.Line);
  end;
end;

function TLspEnclosingConditions.Condition(ANode: TSyntaxNode): TLspConditionParts;
begin
  Result := nil;
  LoadCalls(ANode);
  AddPart(Result, ANode, -1);
end;

function TLspEnclosingConditions.Path(ALine: Integer): TArray<TSyntaxNode>;
var
  mNode, mNext: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mNode := FTree.Root;
  while mNode <> nil do
  begin
    Result := Result + [mNode];
    // Reichen mehrere Kinder in die Zeile, gilt das letzte: bei „paNormal: Summe := 0;“ die Anweisung, nicht
    // die Marke.
    mNext := nil;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      if Contains(mNode.Children[mIndex], ALine) then
      begin
        mNext := mNode.Children[mIndex];
        Break;
      end;
    end;
    mNode := mNext;
  end;
end;

function TLspEnclosingConditions.IfBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
var
  mIndex: Integer;
begin
  // Kinder: Bedingung, then-Zweig, else-Zweig.
  mIndex := IndexOfChild(ANode, AThrough);
  Result := (mIndex >= 1) and (ANode.ChildCount >= 2);
  if not Result then
  begin
    Exit;
  end;
  ABlock.Kind := 'if';
  ABlock.Branch := 'then';
  if mIndex = 2 then
  begin
    ABlock.Branch := 'else';
  end;
  ABlock.Line := ANode.Children[0].EndPos.Line;
  ABlock.Parts := Condition(ANode.Children[0]);
end;

function TLspEnclosingConditions.LoopBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
var
  mIndex: Integer;
  mCondition: TSyntaxNode;
begin
  mIndex := IndexOfChild(ANode, AThrough);
  if ANode.Kind = TSyntaxKind.WhileStatement then
  begin
    // Kinder: Bedingung, Rumpf.
    Result := (mIndex = 1) and (ANode.ChildCount = 2);
    ABlock.Kind := 'while';
    mCondition := ANode.Children[0];
  end
  else
  begin
    // repeat: Anweisungen, zuletzt die until-Bedingung.
    Result := (mIndex >= 0) and (mIndex < ANode.ChildCount - 1);
    ABlock.Kind := 'repeat';
    mCondition := ANode.Children[ANode.ChildCount - 1];
  end;
  if Result then
  begin
    ABlock.Line := mCondition.EndPos.Line;
    ABlock.Parts := Condition(mCondition);
  end;
end;

function TLspEnclosingConditions.ForBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
var
  mFirst: Integer;
  mLimit: TSyntaxNode;
  mPart: TLspConditionPart;
begin
  // Kinder: [Typ], Start, Ende, Rumpf bzw. [Typ], Sammlung, Rumpf. Nur der Rumpf zählt.
  Result := (ANode.ChildCount >= 2) and (AThrough = ANode.Children[ANode.ChildCount - 1]);
  if not Result then
  begin
    Exit;
  end;
  mFirst := 0;
  if ANode.Children[0].Kind = TSyntaxKind.TypeReference then
  begin
    mFirst := 1;
  end;
  ABlock.Kind := 'for';
  if ANode.Kind = TSyntaxKind.ForInStatement then
  begin
    ABlock.Kind := 'forIn';
  end;
  ABlock.Descending := ANode.Descending;
  // Endgrenze bzw. Sammlung: das Kind vor dem Rumpf.
  mLimit := ANode.Children[ANode.ChildCount - 2];
  ABlock.Line := mLimit.EndPos.Line;
  LoadCalls(ANode.Children[mFirst]);
  mPart := Default(TLspConditionPart);
  mPart.Kind := 'value';
  mPart.Text := ANode.Name;
  mPart.Parent := -1;
  mPart.Position := ANode.StartPos;
  ABlock.Parts := [mPart];
  AddValue(ABlock.Parts, Unwrap(mLimit), -1);
end;

function TLspEnclosingConditions.CaseBlock(ANode, AThrough, ANext: TSyntaxNode;
  var ABlock: TLspEnclosingBlock): Boolean;
var
  mIndex: Integer;
  mLabels: TArray<string>;
begin
  // Kinder: Selektor, Zweige, [CaseElse]. Im Zweig zählt nur die Anweisung (letztes Kind), nicht die Marken.
  Result := (IndexOfChild(ANode, AThrough) >= 1) and (ANext <> nil);
  if not Result then
  begin
    Exit;
  end;
  if AThrough.Kind = TSyntaxKind.CaseItem then
  begin
    Result := ANext = AThrough.Children[AThrough.ChildCount - 1];
    mLabels := nil;
    for mIndex := 0 to AThrough.ChildCount - 2 do
    begin
      mLabels := mLabels + [TextOf(AThrough.Children[mIndex])];
    end;
    ABlock.Branch := string.Join(', ', mLabels);
  end
  else
  begin
    ABlock.Branch := 'else';
  end;
  ABlock.Kind := 'case';
  ABlock.Line := ANode.Children[0].EndPos.Line;
  ABlock.Parts := Condition(ANode.Children[0]);
  // Der Selektor ist ein Wert, kein boolescher Ausdruck.
  if (Length(ABlock.Parts) > 0) and (ABlock.Parts[0].Kind <> 'value') then
  begin
    ABlock.Parts := nil;
    AddValue(ABlock.Parts, Unwrap(ANode.Children[0]), -1);
  end;
end;

function TLspEnclosingConditions.WithBlock(ANode, AThrough: TSyntaxNode; var ABlock: TLspEnclosingBlock): Boolean;
var
  mIndex: Integer;
begin
  // Kinder: Ausdrücke, zuletzt der Rumpf.
  Result := (ANode.ChildCount >= 2) and (AThrough = ANode.Children[ANode.ChildCount - 1]);
  if not Result then
  begin
    Exit;
  end;
  ABlock.Kind := 'with';
  ABlock.Line := ANode.Children[ANode.ChildCount - 2].EndPos.Line;
  LoadCalls(ANode.Children[0]);
  for mIndex := 0 to ANode.ChildCount - 2 do
  begin
    AddValue(ABlock.Parts, Unwrap(ANode.Children[mIndex]), -1);
  end;
end;

function TLspEnclosingConditions.BlockOf(ANode, AThrough, ANext: TSyntaxNode;
  out ABlock: TLspEnclosingBlock): Boolean;
begin
  ABlock := Default(TLspEnclosingBlock);
  ABlock.Start := ANode.StartPos;
  case ANode.Kind of
    TSyntaxKind.IfStatement:
      Result := IfBlock(ANode, AThrough, ABlock);
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement:
      Result := LoopBlock(ANode, AThrough, ABlock);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      Result := ForBlock(ANode, AThrough, ABlock);
    TSyntaxKind.CaseStatement:
      Result := CaseBlock(ANode, AThrough, ANext, ABlock);
    TSyntaxKind.WithStatement:
      Result := WithBlock(ANode, AThrough, ABlock);
  else
    Result := False;
  end;
end;

function TLspEnclosingConditions.Answer(ALine, ADepth: Integer): TLspEnclosingBlocks;
var
  mPath: TArray<TSyntaxNode>;
  mIndex: Integer;
  mNext: TSyntaxNode;
  mBlock: TLspEnclosingBlock;
begin
  Result := nil;
  ADepth := ClampDepth(ADepth);
  mPath := Path(ALine);
  for mIndex := High(mPath) - 1 downto 0 do
  begin
    if IsBoundary(mPath[mIndex]) or (Length(Result) >= ADepth) then
    begin
      Break;
    end;
    // Beginnt die Anweisung in der Zeile des Halts, ist ihr Kopf noch nicht ausgewertet.
    if mPath[mIndex].StartPos.Line = ALine then
    begin
      Continue;
    end;
    mNext := nil;
    if mIndex + 2 <= High(mPath) then
    begin
      mNext := mPath[mIndex + 2];
    end;
    if BlockOf(mPath[mIndex], mPath[mIndex + 1], mNext, mBlock) then
    begin
      Result := Result + [mBlock];
    end;
  end;
end;

function TLspEnclosingConditions.Execute(ALine, ADepth: Integer): TJSONObject;
begin
  Result := ToJson(Answer(ALine, ADepth));
end;

function TLspEnclosingConditions.ConditionParts(ANode: TSyntaxNode): TLspConditionParts;
begin
  Result := Condition(ANode);
end;

procedure TLspEnclosingConditions.AppendValue(var AParts: TLspConditionParts; ANode: TSyntaxNode);
begin
  LoadCalls(ANode);
  AddValue(AParts, Unwrap(ANode), -1);
end;

class function TLspEnclosingConditions.PartToJson(const APart: TLspConditionPart): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', APart.Kind);
  Result.AddPair('operator', APart.Operator_);
  Result.AddPair('text', APart.Text);
  Result.AddPair('parent', TJSONNumber.Create(APart.Parent));
  Result.AddPair('call', TJSONBool.Create(APart.Call));
  Result.AddPair('line', TJSONNumber.Create(APart.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(APart.Position.Character));
end;

class function TLspEnclosingConditions.ToJson(const ABlocks: TLspEnclosingBlocks): TJSONObject;
var
  mBlocks, mParts: TJSONArray;
  mBlock: TLspEnclosingBlock;
  mPart: TLspConditionPart;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  mBlocks := TJSONArray.Create;
  Result.AddPair('blocks', mBlocks);
  for mBlock in ABlocks do
  begin
    mItem := TJSONObject.Create;
    mBlocks.AddElement(mItem);
    mItem.AddPair('kind', mBlock.Kind);
    mItem.AddPair('line', TJSONNumber.Create(mBlock.Line));
    mItem.AddPair('startLine', TJSONNumber.Create(mBlock.Start.Line));
    mItem.AddPair('character', TJSONNumber.Create(mBlock.Start.Character));
    mItem.AddPair('branch', mBlock.Branch);
    mItem.AddPair('descending', TJSONBool.Create(mBlock.Descending));
    mParts := TJSONArray.Create;
    mItem.AddPair('parts', mParts);
    for mPart in mBlock.Parts do
    begin
      mParts.AddElement(PartToJson(mPart));
    end;
  end;
end;

end.
