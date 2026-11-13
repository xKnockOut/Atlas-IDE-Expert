unit Atlas.Common.Lsp.UpcomingConditions;

// Befehl atlas.server.upcomingConditions (#2169): Bedingungen vorausschauen.
// Ab der Zeile des Halts bis ALines Zeilen voraus die Anweisungen derselben
// Anweisungsliste (Geschwister der Anweisung am Halt): if, while und case.
// Eine Bedingung zählt nur, wenn sie sich aus dem jetzigen Zustand ergibt:
//   - keine Zuweisung an einen ihrer Namen dazwischen (auch Argumente von
//     Aufrufen, var/out, Inc/Dec, Laufvariablen),
//   - kein Aufruf dazwischen, wenn sie Namen außerhalb der lokalen Variablen
//     und Parameter liest (Felder, globale Variablen),
//   - kein Sprung dazwischen (Exit, raise, goto, Break oder Continue der Liste).
// Nach einer Anweisung mit Exit, raise oder goto ist Schluss; repeat und for
// werden nicht vorhergesagt, ihre Wirkungen zählen aber für die folgenden.
// Argumente: [uri, line, lines] (Zeile ab 0, lines 1–200, Vorgabe 20).
// Antwort: {"format": 1, "blocks": [{"kind": "if", "line": 12, "startLine": 12,
//   "character": 2, "parts": [...wie enclosingConditions...],
//   "branches": [{"name": "then", "from": 13, "to": 13, "labels": []}, ...]}]}
// branches: if then/else, while body, case item (labels: [[low, high], ...] als
// Indizes in parts, high -1 ohne Bereich) und else. Bei case ist parts[0] der
// Selektor, die Marken folgen als value.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.EnclosingConditions;

type
  TLspUpcomingBranch = record
    /// <summary>then, else, body oder item.</summary>
    Name: string;
    FromLine: Integer;
    ToLine: Integer;
    /// <summary>Nur bei item: je Marke Index in Parts für Anfang und Ende (-1 ohne Bereich).</summary>
    Labels: TArray<TArray<Integer>>;
  end;

  TLspUpcomingBlock = record
    /// <summary>if, while oder case.</summary>
    Kind: string;
    /// <summary>Zeile (ab 0), an deren Ende die Vorhersage steht: Ende der Bedingung bzw. des Selektors.</summary>
    Line: Integer;
    Start: TTextPosition;
    Parts: TLspConditionParts;
    Branches: TArray<TLspUpcomingBranch>;
  end;

  TLspUpcomingBlocks = TArray<TLspUpcomingBlock>;

  /// <summary>Was die Anweisungen zwischen Halt und Bedingung tun können.</summary>
  TLspUpcomingEffects = record
    /// <summary>Kleingeschriebene Namen, die sich ändern können.</summary>
    Changed: TArray<string>;
    Called: Boolean;
    /// <summary>Exit, raise oder goto: danach keine Vorhersage mehr.</summary>
    Leaves: Boolean;
    procedure Add(ANode: TSyntaxNode);
    function Touches(const ANames: TArray<string>): Boolean;
  end;

  TLspUpcomingConditions = class
  public const
    cCommand = 'atlas.server.upcomingConditions';
    cDefaultLines = 20;
    cMaxLines = 200;
  private
    FTree: TSyntaxTree;
    FText: string;
    FParts: TLspEnclosingConditions;
    FLocals: TArray<string>;
    function StatementAt(ALine: Integer; out AList: TSyntaxNode; out AIndex: Integer): Boolean;
    procedure LoadLocals(ANode: TSyntaxNode);
    function Predictable(ACondition: TSyntaxNode; const AEffects: TLspUpcomingEffects): Boolean;
    function BlockOf(ANode: TSyntaxNode; out ABlock: TLspUpcomingBlock): Boolean;
    procedure CaseBranches(ANode: TSyntaxNode; var ABlock: TLspUpcomingBlock);
    class function Branch(const AName: string; ANode: TSyntaxNode): TLspUpcomingBranch; static;
    class function LastIndex(AList: TSyntaxNode): Integer; static;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt);
    destructor Destroy; override;
    /// <summary>Vorhersagbare Bedingungen ab Zeile ALine (ab 0) bis ALines Zeilen voraus.</summary>
    function Answer(ALine, ALines: Integer): TLspUpcomingBlocks;
    function Execute(ALine, ALines: Integer): TJSONObject;
    class function ToJson(const ABlocks: TLspUpcomingBlocks): TJSONObject; static;
    /// <summary>ALines auf 1–MaxLines begrenzt; 0 und weniger = DefaultLines.</summary>
    class function ClampLines(ALines: Integer): Integer; static;
    /// <summary>Kleingeschriebene Namen aller Bezeichner unter ANode.</summary>
    class function NamesIn(ANode: TSyntaxNode): TArray<string>; static;
  end;

implementation

uses
  System.Math,
  Atlas.Common.Editing.RoutineLocals;

const
  cListKinds = [TSyntaxKind.Block, TSyntaxKind.RepeatStatement, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock, TSyntaxKind.CaseElse];
  cStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement, TSyntaxKind.AsmBlock];
  cLoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];

function Contains(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  Result := (ANode.StartPos.Line <= ALine) and (ALine <= ANode.EndPos.Line);
end;

function IsJump(ANode: TSyntaxNode; const ANames: array of string): Boolean;
var
  mName: string;
begin
  Result := False;
  if ANode.Kind <> TSyntaxKind.CallStatement then
  begin
    Exit;
  end;
  for mName in ANames do
  begin
    if SameText(ANode.Name, mName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Break oder Continue, das nicht in einer Schleife unter ANode steht, verlässt die Liste.</summary>
function LeavesList(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Search(
    function(ANext: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANext <> ANode) and ((ANext.Kind in cLoopKinds) or (ANext.Kind = TSyntaxKind.AnonymousMethod)) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if IsJump(ANext, ['Break', 'Continue']) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

{ TLspUpcomingEffects }

procedure TLspUpcomingEffects.Add(ANode: TSyntaxNode);
var
  mEffects: ^TLspUpcomingEffects;
begin
  mEffects := @Self;
  ANode.Walk(
    function(ANext: TSyntaxNode): Boolean
    begin
      // Anonyme Methoden laufen hier nicht.
      Result := ANext.Kind <> TSyntaxKind.AnonymousMethod;
      if not Result then
      begin
        Exit;
      end;
      if (ANext.Kind = TSyntaxKind.AssignStatement) and (ANext.ChildCount > 0) then
      begin
        mEffects.Changed := mEffects.Changed + TLspUpcomingConditions.NamesIn(ANext.Children[0]);
      end
      else if ANext.Kind = TSyntaxKind.Call then
      begin
        // Argumente können var oder out sein.
        mEffects.Called := True;
        mEffects.Changed := mEffects.Changed + TLspUpcomingConditions.NamesIn(ANext);
      end
      else if IsJump(ANext, ['Exit', 'Halt']) or (ANext.Kind in [TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement])
        then
      begin
        mEffects.Leaves := True;
      end
      else if ANext.Kind = TSyntaxKind.CallStatement then
      begin
        mEffects.Called := True;
      end
      else if ANext.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
      begin
        mEffects.Changed := mEffects.Changed + [LowerCase(ANext.Name)];
      end;
    end);
  Leaves := Leaves or LeavesList(ANode);
end;

function TLspUpcomingEffects.Touches(const ANames: TArray<string>): Boolean;
var
  mName, mChanged: string;
begin
  Result := False;
  for mName in ANames do
  begin
    for mChanged in Changed do
    begin
      if mName = mChanged then
      begin
        Exit(True);
      end;
    end;
  end;
end;

{ TLspUpcomingConditions }

constructor TLspUpcomingConditions.Create(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FParts := TLspEnclosingConditions.Create(ATree, AText, ACallsAt);
end;

destructor TLspUpcomingConditions.Destroy;
begin
  FParts.Free;
  FLocals := nil;
  inherited Destroy;
end;

class function TLspUpcomingConditions.ClampLines(ALines: Integer): Integer;
begin
  Result := ALines;
  if Result <= 0 then
  begin
    Result := cDefaultLines;
  end;
  Result := Min(Result, cMaxLines);
end;

class function TLspUpcomingConditions.NamesIn(ANode: TSyntaxNode): TArray<string>;
var
  mNames: TArray<string>;
begin
  mNames := nil;
  ANode.Walk(
    function(ANext: TSyntaxNode): Boolean
    begin
      Result := ANext.Kind <> TSyntaxKind.AnonymousMethod;
      if Result and (ANext.Kind = TSyntaxKind.Identifier) then
      begin
        mNames := mNames + [LowerCase(ANext.Name)];
      end;
    end);
  Result := mNames;
end;

class function TLspUpcomingConditions.LastIndex(AList: TSyntaxNode): Integer;
begin
  // repeat: das letzte Kind ist die until-Bedingung, keine Anweisung.
  Result := AList.ChildCount - 1;
  if AList.Kind = TSyntaxKind.RepeatStatement then
  begin
    Dec(Result);
  end;
end;

function TLspUpcomingConditions.StatementAt(ALine: Integer; out AList: TSyntaxNode; out AIndex: Integer): Boolean;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
  mDescend: Boolean;
begin
  // Die tiefste Anweisung in einer Anweisungsliste, die die Zeile enthält.
  AList := nil;
  AIndex := -1;
  mNode := FTree.Root;
  mDescend := mNode <> nil;
  while mDescend do
  begin
    mDescend := False;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      if Contains(mNode.Children[mIndex], ALine) then
      begin
        if (mNode.Kind in cListKinds) and (mIndex <= LastIndex(mNode)) then
        begin
          AList := mNode;
          AIndex := mIndex;
        end;
        mNode := mNode.Children[mIndex];
        mDescend := True;
        Break;
      end;
    end;
  end;
  Result := AList <> nil;
end;

procedure TLspUpcomingConditions.LoadLocals(ANode: TSyntaxNode);
var
  mRoutine: TSyntaxNode;
  mLocal: TRoutineLocal;
begin
  FLocals := ['result', 'self'];
  mRoutine := ANode;
  while (mRoutine <> nil) and not (mRoutine.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    mRoutine := mRoutine.Parent;
  end;
  if mRoutine = nil then
  begin
    Exit;
  end;
  for mLocal in TRoutineLocals.Collect(FText, FTree, mRoutine) do
  begin
    FLocals := FLocals + [LowerCase(mLocal.Name)];
  end;
end;

function TLspUpcomingConditions.Predictable(ACondition: TSyntaxNode; const AEffects: TLspUpcomingEffects): Boolean;
var
  mName, mLocal: string;
  mIsLocal: Boolean;
begin
  Result := not AEffects.Touches(NamesIn(ACondition));
  if not Result or not AEffects.Called then
  begin
    Exit;
  end;
  // Ein Aufruf kann Felder und globale Variablen ändern, lokale nur über Argumente (oben).
  for mName in NamesIn(ACondition) do
  begin
    mIsLocal := False;
    for mLocal in FLocals do
    begin
      mIsLocal := mIsLocal or (mLocal = mName);
    end;
    if not mIsLocal then
    begin
      Exit(False);
    end;
  end;
end;

class function TLspUpcomingConditions.Branch(const AName: string; ANode: TSyntaxNode): TLspUpcomingBranch;
begin
  Result := Default(TLspUpcomingBranch);
  Result.Name := AName;
  Result.FromLine := ANode.StartPos.Line;
  Result.ToLine := ANode.EndPos.Line;
end;

procedure TLspUpcomingConditions.CaseBranches(ANode: TSyntaxNode; var ABlock: TLspUpcomingBlock);
var
  mIndex, mLabel: Integer;
  mItem, mMark: TSyntaxNode;
  mBranch: TLspUpcomingBranch;
  mLow, mHigh, mLastLabel: Integer;
begin
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mItem := ANode.Children[mIndex];
    if mItem.Kind = TSyntaxKind.CaseElse then
    begin
      ABlock.Branches := ABlock.Branches + [Branch('else', mItem)];
      Continue;
    end;
    // Kinder: Marken, zuletzt die Anweisung; bei leerer Anweisung („smManual: ;“) nur Marken.
    mLastLabel := mItem.ChildCount - 1;
    mBranch := Branch('item', mItem);
    if mItem.Children[mLastLabel].Kind in cStatementKinds then
    begin
      mBranch := Branch('item', mItem.Children[mLastLabel]);
      Dec(mLastLabel);
    end;
    for mLabel := 0 to mLastLabel do
    begin
      mMark := mItem.Children[mLabel];
      mLow := Length(ABlock.Parts);
      mHigh := -1;
      if (mMark.Kind = TSyntaxKind.RangeExpr) and (mMark.ChildCount = 2) then
      begin
        FParts.AppendValue(ABlock.Parts, mMark.Children[0]);
        mHigh := Length(ABlock.Parts);
        FParts.AppendValue(ABlock.Parts, mMark.Children[1]);
      end
      else
      begin
        FParts.AppendValue(ABlock.Parts, mMark);
      end;
      mBranch.Labels := mBranch.Labels + [TArray<Integer>.Create(mLow, mHigh)];
    end;
    ABlock.Branches := ABlock.Branches + [mBranch];
  end;
end;

function TLspUpcomingConditions.BlockOf(ANode: TSyntaxNode; out ABlock: TLspUpcomingBlock): Boolean;
begin
  ABlock := Default(TLspUpcomingBlock);
  ABlock.Start := ANode.StartPos;
  Result := (ANode.ChildCount >= 2) and (ANode.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.CaseStatement]);
  if not Result then
  begin
    Exit;
  end;
  ABlock.Line := ANode.Children[0].EndPos.Line;
  case ANode.Kind of
    TSyntaxKind.IfStatement:
      begin
        ABlock.Kind := 'if';
        ABlock.Parts := FParts.ConditionParts(ANode.Children[0]);
        ABlock.Branches := [Branch('then', ANode.Children[1])];
        if ANode.ChildCount > 2 then
        begin
          ABlock.Branches := ABlock.Branches + [Branch('else', ANode.Children[2])];
        end;
      end;
    TSyntaxKind.WhileStatement:
      begin
        ABlock.Kind := 'while';
        ABlock.Parts := FParts.ConditionParts(ANode.Children[0]);
        ABlock.Branches := [Branch('body', ANode.Children[1])];
      end;
  else
    ABlock.Kind := 'case';
    FParts.AppendValue(ABlock.Parts, ANode.Children[0]);
    CaseBranches(ANode, ABlock);
  end;
end;

function TLspUpcomingConditions.Answer(ALine, ALines: Integer): TLspUpcomingBlocks;
var
  mList, mStatement: TSyntaxNode;
  mIndex, mLast: Integer;
  mEffects: TLspUpcomingEffects;
  mBlock: TLspUpcomingBlock;
begin
  Result := nil;
  if not StatementAt(ALine, mList, mIndex) then
  begin
    Exit;
  end;
  LoadLocals(mList);
  mEffects := Default(TLspUpcomingEffects);
  mLast := ALine + ClampLines(ALines);
  // Beginnt die Anweisung am Halt schon vorher, läuft sie gerade: nur ihre Wirkung zählt.
  if mList.Children[mIndex].StartPos.Line < ALine then
  begin
    mEffects.Add(mList.Children[mIndex]);
    Inc(mIndex);
  end;
  while not mEffects.Leaves and (mIndex <= LastIndex(mList)) do
  begin
    mStatement := mList.Children[mIndex];
    if mStatement.StartPos.Line > mLast then
    begin
      Break;
    end;
    if BlockOf(mStatement, mBlock) and Predictable(mStatement.Children[0], mEffects) then
    begin
      Result := Result + [mBlock];
    end;
    mEffects.Add(mStatement);
    Inc(mIndex);
  end;
end;

function TLspUpcomingConditions.Execute(ALine, ALines: Integer): TJSONObject;
begin
  Result := ToJson(Answer(ALine, ALines));
end;

function BranchToJson(const ABranch: TLspUpcomingBranch): TJSONObject;
var
  mLabels, mPair: TJSONArray;
  mLabel: TArray<Integer>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ABranch.Name);
  Result.AddPair('from', TJSONNumber.Create(ABranch.FromLine));
  Result.AddPair('to', TJSONNumber.Create(ABranch.ToLine));
  mLabels := TJSONArray.Create;
  Result.AddPair('labels', mLabels);
  for mLabel in ABranch.Labels do
  begin
    mPair := TJSONArray.Create;
    mPair.Add(mLabel[0]);
    mPair.Add(mLabel[1]);
    mLabels.AddElement(mPair);
  end;
end;

class function TLspUpcomingConditions.ToJson(const ABlocks: TLspUpcomingBlocks): TJSONObject;
var
  mBlocks, mParts, mBranches: TJSONArray;
  mBlock: TLspUpcomingBlock;
  mPart: TLspConditionPart;
  mBranch: TLspUpcomingBranch;
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
    mParts := TJSONArray.Create;
    mItem.AddPair('parts', mParts);
    for mPart in mBlock.Parts do
    begin
      mParts.AddElement(TLspEnclosingConditions.PartToJson(mPart));
    end;
    mBranches := TJSONArray.Create;
    mItem.AddPair('branches', mBranches);
    for mBranch in mBlock.Branches do
    begin
      mBranches.AddElement(BranchToJson(mBranch));
    end;
  end;
end;

end.
