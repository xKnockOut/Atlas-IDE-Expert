unit Atlas.Common.Rules.Builtin.Flow.HandleLeak;

// Regel handle-leak aus Atlas.Common.Rules.Builtin.Flow (#269): Ein Windows-Handle aus der Tabelle der Paare
// (CreateFile/CloseHandle, GetDC/ReleaseDC …) wird in einer lokalen Variablen geöffnet, und ein Weg erreicht das
// normale Ende der Routine, ohne es zu schließen oder weiterzugeben. Bei if über die Prüfung des Handles (auch über
// einen Merker, Result := H <> 0; if Result then …, auch Result := CreatePipe(R, W, nil, 0); if Result then …)
// folgt der Weg nur dem Zweig, in dem das Öffnen gelang.
// Korrektur: try … finally Schließen end um die folgenden Anweisungen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  THandleLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Paare "Öffnen|Ort|Schließen" aus der Tabelle und der Option pairs ("Öffnen&gt;Schließen" oder
    /// {"open", "close"}).</summary>
    class function Pairs(const AOptions: string): TArray<string>; static;
  end;

const
  cHandleLeakRuleId = 'handle-leak';

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Rules.Builtin.Flow.HandleLeak.Handles,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowHandleLeakText = (AndWord, NeverClosed, NotAlwaysClosed, Add, WrapTry, Title, VerbOne, VerbMany);

const
  cTexts: array[TFlowHandleLeakText] of TAtlasText = (
    (De: ' und '; En: ' and '),
    (De: '%s %s nie mit %s geschlossen (Handle-Leck).'; En: '%s %s never closed with %s (handle leak).'),
    (De: '%s %s nicht auf jedem Weg mit %s geschlossen (Handle-Leck).';
     En: '%s %s not closed with %s on every path (handle leak).'),
    (De: '%s ergänzen'; En: 'Add %s'),
    (De: 'In try … finally %s einschließen'; En: 'Wrap in try … finally %s'),
    (De: 'Windows-Handle wird nicht geschlossen'; En: 'Windows handle is not closed'),
    (De: 'wird'; En: 'is'),
    (De: 'werden'; En: 'are'));

{$SCOPEDENUMS OFF}

/// <summary>Was ein Knoten selbst auswertet: einfache Anweisungen ganz, bei if, case und Schleifen die Bedingung
/// bzw. der Kopf, with ganz (with H do … gibt das Handle weiter).</summary>
function NodeParts(ANode: TFlowNode): TArray<TSyntaxNode>;
begin
  Result := nil;
  if ANode.Syntax = nil then
  begin
    Exit;
  end;
  if ANode.Syntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.WithStatement] then
  begin
    Result := [ANode.Syntax];
  end
  else if ANode.Kind = TFlowNodeKind.Condition then
  begin
    Result := OwnParts(ANode.Syntax);
  end;
end;

function InRange(AInner, AOuter: TSyntaxNode): Boolean;
begin
  Result := (AInner <> nil) and (AOuter <> nil) and (AInner.StartOffset >= AOuter.StartOffset) and
    (AInner.EndOffset <= AOuter.EndOffset);
end;

/// <summary>Bedingung (erster Ausdruck) und then-Zweig (erste Anweisung) einer if-Anweisung.</summary>
procedure SplitIf(AIf: TSyntaxNode; out ACondition, AThen: TSyntaxNode);
var
  mIndex: Integer;
begin
  ACondition := nil;
  AThen := nil;
  for mIndex := 0 to AIf.ChildCount - 1 do
  begin
    if not (AIf[mIndex].Kind in cFlowStatementKinds) then
    begin
      if ACondition = nil then
      begin
        ACondition := AIf[mIndex];
      end;
    end
    else if AThen = nil then
    begin
      AThen := AIf[mIndex];
    end;
  end;
end;

/// <summary>ANode ist AName := ….</summary>
function IsAssignTo(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, AName);
end;

/// <summary>Zuweisungen AName := … unter ABody (ohne eingebettete Routinen), die hinter AFrom enden und vor ATo;
/// eine Zuweisung, die AFrom umschließt, zählt mit.</summary>
function AssignmentsTo(ABody: TSyntaxNode; const AName: string; AFrom, ATo: Integer): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
  mBody: TSyntaxNode;
  mName: string;
  mFrom, mTill: Integer;
begin
  mFound := nil;
  mBody := ABody;
  mName := AName;
  mFrom := AFrom;
  mTill := ATo;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> mBody) and IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if IsAssignTo(ANode, mName) and (ANode.EndOffset > mFrom) and (ANode.EndOffset < mTill) then
      begin
        mFound := mFound + [ANode];
      end;
    end);
  Result := mFound;
end;

/// <summary>Merker als Bedingung (#1519): Result := H &lt;&gt; INVALID_HANDLE_VALUE; if Result then …. Die
/// Bedingung ist eine Variable (auch not X oder in Klammern), der ABody zwischen dem Öffnen und dem if genau
/// einmal einen Ausdruck zuweist; dann gilt dessen Bedeutung. Das gilt auch für die Zuweisung, die selbst öffnet
/// (Result := OpenProcessToken(…, Token); if not Result then Exit). Spätere Zuweisungen (im then-Zweig) zählen
/// nicht. 0 sonst.</summary>
function FlagSuccess(ABody, AIf, ACondition: TSyntaxNode; const AHandle: TOpenedHandle;
  AOpenCall: TSyntaxNode): Integer;
var
  mNode: TSyntaxNode;
  mSign: Integer;
  mAssignments: TArray<TSyntaxNode>;
begin
  Result := 0;
  mSign := 1;
  mNode := ACondition;
  while (mNode.ChildCount = 1) and ((mNode.Kind = TSyntaxKind.ParenExpr) or
    ((mNode.Kind = TSyntaxKind.UnaryExpr) and SameText(mNode.Name, 'not'))) do
  begin
    if mNode.Kind = TSyntaxKind.UnaryExpr then
    begin
      mSign := -mSign;
    end;
    mNode := mNode[0];
  end;
  if (ABody = nil) or (mNode.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  mAssignments := AssignmentsTo(ABody, mNode.Name, AOpenCall.StartOffset, AIf.StartOffset);
  if Length(mAssignments) = 1 then
  begin
    Result := mSign * OpenSuccess(mAssignments[0][1], AHandle, AOpenCall);
  end;
end;

/// <summary>Variablen und Inline-Variablen der Routine (ohne Parameter und eingebettete Routinen).</summary>
function DeclaredLocals(ARoutine: TSyntaxNode): TArray<string>;
var
  mNames: TArray<string>;
  mRoutine: TSyntaxNode;
begin
  mNames := nil;
  mRoutine := ARoutine;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Name: string;
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> mRoutine) and IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
      begin
        for Name in ANode.Name.Split([',']) do
        begin
          mNames := mNames + [Trim(Name)];
        end;
      end;
    end);
  Result := mNames;
end;

/// <summary>Pfade der Handles, mit und verbunden.</summary>
function HandleNames(const AHandles: TArray<TOpenedHandle>): string;
var
  mHandle: TOpenedHandle;
begin
  Result := '';
  for mHandle in AHandles do
  begin
    if Result <> '' then
    begin
      Result := Result + cTexts[TFlowHandleLeakText.AndWord].Text;
    end;
    Result := Result + mHandle.Path;
  end;
end;

function LeakMessage(const ALeaked: TArray<TOpenedHandle>; ANever: Boolean): string;
var
  mVerb: string;
begin
  mVerb := cTexts[TFlowHandleLeakText.VerbOne].Text;
  if Length(ALeaked) > 1 then
  begin
    mVerb := cTexts[TFlowHandleLeakText.VerbMany].Text;
  end;
  if ANever then
  begin
    Result := cTexts[TFlowHandleLeakText.NeverClosed].Fmt([HandleNames(ALeaked), mVerb,
      ALeaked[0].CloseName]);
  end
  else
  begin
    Result := cTexts[TFlowHandleLeakText.NotAlwaysClosed].Fmt([HandleNames(ALeaked), mVerb,
      ALeaked[0].CloseName]);
  end;
end;

type
  /// <summary>Prüfung einer Unit für handle-leak; hält die Tabelle, die Routine, ihren Graphen und ihre lokalen
  /// Variablen.</summary>
  THandleCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTable: TArray<THandlePair>;
    FRoutine: TSyntaxNode;
    FGraph: TControlFlowGraph;
    FLocals: TArray<string>;
    FLineBreak: string;
    function PairOf(const AName: string; out APair: THandlePair): Boolean;
    function NewHandle(const APair: THandlePair; ACall: TSyntaxNode; const ARoot, APath: string): TOpenedHandle;
    procedure AddArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode; AIndex: Integer;
      const AFields: TArray<string>; var AHandles: TArray<TOpenedHandle>);
    function ArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode): TArray<TOpenedHandle>;
    function Opened(ACall: TSyntaxNode; const ATarget: string; out AHandles: TArray<TOpenedHandle>): Boolean;
    function IfVerdict(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
      out AThen: TSyntaxNode): Integer;
    function Followed(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): TArray<TFlowNode>;
    function StopsHandle(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
    function LeaksFrom(AOpen: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
    function ClosedAnywhere(const AHandle: TOpenedHandle): Boolean;
    function PositionAt(AOffset: Integer): TTextPosition;
    function ClosingLines(const AHandles: TArray<TOpenedHandle>; const AOuter: string): string;
    function AppendFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
      const AOuter: string): TArray<TRuleFix>;
    function IndentedBody(ALineStart: Integer; ALast: TSyntaxNode): string;
    function WrapFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>): TArray<TRuleFix>;
    procedure CollectOpens(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>; var ATargets: TArray<string>);
    procedure NoteTargets(APart: TSyntaxNode; AFirst: Integer; const ACalls: TArray<TSyntaxNode>;
      var ATargets: TArray<string>);
    function LeakedHandles(ANode: TFlowNode; ACall: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
      out ANever: Boolean): TArray<TOpenedHandle>;
    procedure CheckOpen(ANode: TFlowNode; ACall: TSyntaxNode; const ATarget: string);
    procedure CheckNode(ANode: TFlowNode);
    procedure CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ THandleCheck }

constructor THandleCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
end;

function THandleCheck.PairOf(const AName: string; out APair: THandlePair): Boolean;
var
  mPair: THandlePair;
begin
  Result := False;
  for mPair in FTable do
  begin
    if not Result and SameRoutine(AName, mPair.Open) then
    begin
      APair := mPair;
      Result := True;
    end;
  end;
end;

function THandleCheck.NewHandle(const APair: THandlePair; ACall: TSyntaxNode; const ARoot,
  APath: string): TOpenedHandle;
begin
  Result.Path := APath;
  Result.Root := ARoot;
  Result.CloseName := Copy(APair.Close, 1, Pos('(', APair.Close) - 1);
  Result.CloseText := StringReplace(APair.Close, '%h', APath, [rfReplaceAll]);
  if (Pos('%0', Result.CloseText) > 0) and (ACall.ChildCount > 1) then
  begin
    Result.CloseText := StringReplace(Result.CloseText, '%0', Trim(SourceText(FContext.Text, ACall[1])),
      [rfReplaceAll]);
  end;
end;

/// <summary>Handle im out-Argument AIndex (Zählung ab 1 unter den Kindern des Aufrufs); bei Feldern (CreateProcess)
/// je Feld eins.</summary>
procedure THandleCheck.AddArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode; AIndex: Integer;
  const AFields: TArray<string>; var AHandles: TArray<TOpenedHandle>);
var
  mArg, mField: string;
begin
  if (AIndex < 1) or (AIndex >= ACall.ChildCount) then
  begin
    Exit;
  end;
  mArg := HandlePath(ACall[AIndex]);
  if (mArg = '') or (Pos('.', mArg) > 0) or not MatchText(mArg, FLocals) then
  begin
    Exit;
  end;
  if AFields = nil then
  begin
    AHandles := AHandles + [NewHandle(APair, ACall, mArg, mArg)];
  end;
  for mField in AFields do
  begin
    AHandles := AHandles + [NewHandle(APair, ACall, mArg, mArg + '.' + mField)];
  end;
end;

/// <summary>Handles in out-Argumenten: Ort wie '4', '0,1' oder '9:hProcess,hThread'.</summary>
function THandleCheck.ArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode): TArray<TOpenedHandle>;
var
  mWhere, mPart: string;
  mFields: TArray<string>;
begin
  Result := nil;
  mFields := nil;
  mWhere := APair.Where;
  if Pos(':', mWhere) > 0 then
  begin
    mFields := Copy(mWhere, Pos(':', mWhere) + 1, MaxInt).Split([',']);
    mWhere := Copy(mWhere, 1, Pos(':', mWhere) - 1);
  end;
  for mPart in mWhere.Split([',']) do
  begin
    AddArgumentHandles(APair, ACall, StrToIntDef(mPart, -1) + 1, mFields, Result);
  end;
end;

/// <summary>Handles, die ACall öffnet; ATarget ist das Ziel einer Zuweisung ('' ohne).</summary>
function THandleCheck.Opened(ACall: TSyntaxNode; const ATarget: string; out AHandles: TArray<TOpenedHandle>): Boolean;
var
  mPair: THandlePair;
begin
  AHandles := nil;
  if not PairOf(CallName(FContext.Text, ACall), mPair) then
  begin
    Exit(False);
  end;
  if mPair.Where <> 'r' then
  begin
    AHandles := ArgumentHandles(mPair, ACall);
  end
  else if (ATarget <> '') and MatchText(ATarget, FLocals) then
  begin
    AHandles := AHandles + [NewHandle(mPair, ACall, ATarget, ATarget)];
  end;
  Result := AHandles <> nil;
end;

/// <summary>Bedeutet die Bedingung des if ANode, dass das Öffnen gelang (1) oder misslang (-1)? 0 sonst.
/// </summary>
function THandleCheck.IfVerdict(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  out AThen: TSyntaxNode): Integer;
var
  mCondition: TSyntaxNode;
begin
  Result := 0;
  AThen := nil;
  if (ANode.Kind <> TFlowNodeKind.Condition) or (ANode.Syntax.Kind <> TSyntaxKind.IfStatement) then
  begin
    Exit;
  end;
  SplitIf(ANode.Syntax, mCondition, AThen);
  if mCondition <> nil then
  begin
    Result := OpenSuccess(mCondition, AHandle, AOpenCall);
  end;
  if (Result = 0) and (mCondition <> nil) then
  begin
    Result := FlagSuccess(FRoutine.FindChild(TSyntaxKind.Block), ANode.Syntax, mCondition, AHandle, AOpenCall);
  end;
end;

/// <summary>Nachfolger, denen der Weg mit offenem Handle folgt: bei if über die Prüfung des Handles nur der
/// Zweig, in dem das Öffnen gelang.</summary>
function THandleCheck.Followed(ANode: TFlowNode; const AHandle: TOpenedHandle;
  AOpenCall: TSyntaxNode): TArray<TFlowNode>;
var
  mNext: TFlowNode;
  mThenPart: TSyntaxNode;
  mVerdict: Integer;
  mFollows: Boolean;
begin
  Result := nil;
  mVerdict := IfVerdict(ANode, AHandle, AOpenCall, mThenPart);
  for mNext in ANode.Successors do
  begin
    mFollows := not ANode.IsImplicitRaiseEdge(mNext) and (mNext <> FGraph.RaiseExit);
    if mFollows and (mVerdict <> 0) then
    begin
      mFollows := InRange(mNext.Syntax, mThenPart) = (mVerdict > 0);
    end;
    if mFollows then
    begin
      Result := Result + [mNext];
    end;
  end;
end;

/// <summary>Schließt ANode das Handle, gibt es weiter oder weist ihm neu zu (dann wird das alte hier nicht weiter
/// verfolgt)?</summary>
function THandleCheck.StopsHandle(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
var
  mPart, mSyntax: TSyntaxNode;
begin
  Result := False;
  for mPart in NodeParts(ANode) do
  begin
    Result := Result or ClosesHandle(FContext.Text, mPart, AHandle) or
      PassesOn(FContext.Text, mPart, AHandle, AOpenCall, FLocals);
  end;
  mSyntax := ANode.Syntax;
  Result := Result or ((mSyntax <> nil) and (mSyntax.Kind = TSyntaxKind.AssignStatement) and
    (mSyntax.ChildCount = 2) and SameText(HandlePath(mSyntax[0]), AHandle.Path));
end;

/// <summary>Erreicht ein Weg vom Öffnen das normale Ende, ohne das Handle zu schließen oder weiterzugeben?
/// </summary>
function THandleCheck.LeaksFrom(AOpen: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
var
  mVisited: TArray<Boolean>;
  mQueue: TArray<TFlowNode>;
  mHead: Integer;
  mCurrent: TFlowNode;
begin
  Result := False;
  SetLength(mVisited, FGraph.Nodes.Count);
  mQueue := Followed(AOpen, AHandle, AOpenCall);
  mHead := 0;
  while not Result and (mHead < Length(mQueue)) do
  begin
    mCurrent := mQueue[mHead];
    Inc(mHead);
    if mVisited[mCurrent.Index] or (mCurrent = AOpen) then
    begin
      Continue;
    end;
    mVisited[mCurrent.Index] := True;
    Result := mCurrent = FGraph.ExitNode;
    if not Result and not StopsHandle(mCurrent, AHandle, AOpenCall) then
    begin
      mQueue := mQueue + Followed(mCurrent, AHandle, AOpenCall);
    end;
  end;
end;

/// <summary>Schließt die Routine das Handle irgendwo (im Rumpf, ohne eingebettete Routinen)?</summary>
function THandleCheck.ClosedAnywhere(const AHandle: TOpenedHandle): Boolean;
var
  mBody: TSyntaxNode;
begin
  mBody := FRoutine.FindChild(TSyntaxKind.Block);
  Result := (mBody <> nil) and ClosesHandle(FContext.Text, mBody, AHandle);
end;

function THandleCheck.PositionAt(AOffset: Integer): TTextPosition;
var
  mIndex, mLine, mLineStart: Integer;
begin
  mLine := 0;
  mLineStart := 0;
  for mIndex := 1 to AOffset do
  begin
    if FContext.Text[mIndex] = #10 then
    begin
      Inc(mLine);
      mLineStart := mIndex;
    end;
  end;
  Result := TTextPosition.Create(mLine, AOffset - mLineStart);
end;

/// <summary>Schließen in umgekehrter Reihenfolge: zuletzt geöffnet, zuerst geschlossen (PI.hThread vor
/// PI.hProcess).</summary>
function THandleCheck.ClosingLines(const AHandles: TArray<TOpenedHandle>; const AOuter: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := High(AHandles) downto 0 do
  begin
    Result := Result + AOuter + '  ' + AHandles[mIndex].CloseText + ';' + FLineBreak;
  end;
end;

/// <summary>Nichts nach dem Öffnen: nur das Schließen anhängen.</summary>
function THandleCheck.AppendFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
  const AOuter: string): TArray<TRuleFix>;
var
  mIndex: Integer;
  mBody: string;
begin
  mBody := '';
  for mIndex := High(AHandles) downto 0 do
  begin
    mBody := mBody + ';' + FLineBreak + AOuter + AHandles[mIndex].CloseText;
  end;
  Result := [TRuleFix.Create(cTexts[TFlowHandleLeakText.Add].Fmt([AHandles[0].CloseName]),
    [TRuleEdit.Create(TTextRange.Create(AStatement.EndPos, AStatement.EndPos), mBody)])];
end;

/// <summary>Zeilen ab ALineStart bis zum Ende von ALast, zwei Stellen weiter eingerückt.</summary>
function THandleCheck.IndentedBody(ALineStart: Integer; ALast: TSyntaxNode): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in Copy(FContext.Text, ALineStart + 1, ALast.EndOffset - ALineStart).Replace(#13#10, #10).Split([#10]) do
  begin
    if Trim(mLine) = '' then
    begin
      Result := Result + FLineBreak;
    end
    else
    begin
      Result := Result + '  ' + mLine + FLineBreak;
    end;
  end;
  // Die letzte Anweisung endet vor ihrem Semikolon; das alte Semikolon steht danach hinter end.
  if not Result.TrimRight.EndsWith(';') then
  begin
    Result := Result.TrimRight + ';' + FLineBreak;
  end;
end;

/// <summary>Korrektur: die Anweisungen nach dem Öffnen bis zum Ende ihres Blocks in try … finally Schließen end.
/// </summary>
function THandleCheck.WrapFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>): TArray<TRuleFix>;
var
  mBlock, mFirst, mLast: TSyntaxNode;
  mPosition, mLineStart: Integer;
  mOuter, mInner: string;
begin
  Result := nil;
  mBlock := AStatement.Parent;
  if (mBlock = nil) or (mBlock.Kind <> TSyntaxKind.Block) then
  begin
    Exit;
  end;
  mPosition := PositionIn(mBlock, AStatement);
  if (mPosition < 0) or not LineIndent(FContext.Text, AStatement, mOuter) then
  begin
    Exit;
  end;
  if mPosition = mBlock.ChildCount - 1 then
  begin
    Result := AppendFix(AStatement, AHandles, mOuter);
    Exit;
  end;
  mFirst := mBlock[mPosition + 1];
  mLast := mBlock[mBlock.ChildCount - 1];
  if (mFirst.Kind = TSyntaxKind.EmptyStatement) or not LineIndent(FContext.Text, mFirst, mInner) then
  begin
    Exit;
  end;
  mLineStart := mFirst.StartOffset - Length(mInner);
  Result := [TRuleFix.Create(cTexts[TFlowHandleLeakText.WrapTry].Fmt([AHandles[0].CloseName]),
    [TRuleEdit.Create(TTextRange.Create(PositionAt(mLineStart), mLast.EndPos),
    mOuter + 'try' + FLineBreak + IndentedBody(mLineStart, mLast) + mOuter + 'finally' + FLineBreak +
    ClosingLines(AHandles, mOuter) + mOuter + 'end')])];
end;

/// <summary>Aufrufe unter ARoot, die Handles öffnen; ihr Ziel ist zunächst ''.</summary>
procedure THandleCheck.CollectOpens(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>;
  var ATargets: TArray<string>);
var
  mCalls: TArray<TSyntaxNode>;
  mCall: TSyntaxNode;
begin
  mCalls := nil;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Pair: THandlePair;
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.Call) and PairOf(CallName(FContext.Text, ANode), Pair) then
      begin
        mCalls := mCalls + [ANode];
      end;
    end);
  for mCall in mCalls do
  begin
    ACalls := ACalls + [mCall];
    ATargets := ATargets + [''];
  end;
end;

/// <summary>H := CreateFile(…) bzw. var H := CreateFile(…): das Ziel nimmt das Handle auf.</summary>
procedure THandleCheck.NoteTargets(APart: TSyntaxNode; AFirst: Integer; const ACalls: TArray<TSyntaxNode>;
  var ATargets: TArray<string>);
var
  mIndex: Integer;
  mIsAssign: Boolean;
begin
  mIsAssign := (APart.Kind = TSyntaxKind.AssignStatement) and (APart.ChildCount = 2) and
    (APart[0].Kind = TSyntaxKind.Identifier);
  for mIndex := AFirst to High(ACalls) do
  begin
    if mIsAssign and (ACalls[mIndex] = APart[1]) then
    begin
      ATargets[mIndex] := APart[0].Name;
    end
    else if (APart.Kind = TSyntaxKind.InlineVar) and (ACalls[mIndex].Parent = APart) then
    begin
      ATargets[mIndex] := Trim(APart.Name);
    end;
  end;
end;

/// <summary>Handles aus AHandles, die ein Weg vom Öffnen offen lässt; ANever: keins davon wird in der Routine je
/// geschlossen.</summary>
function THandleCheck.LeakedHandles(ANode: TFlowNode; ACall: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
  out ANever: Boolean): TArray<TOpenedHandle>;
var
  mHandle: TOpenedHandle;
begin
  Result := nil;
  ANever := True;
  for mHandle in AHandles do
  begin
    if LeaksFrom(ANode, mHandle, ACall) then
    begin
      Result := Result + [mHandle];
      ANever := ANever and not ClosedAnywhere(mHandle);
    end;
  end;
end;

procedure THandleCheck.CheckOpen(ANode: TFlowNode; ACall: TSyntaxNode; const ATarget: string);
var
  mHandles, mLeaked: TArray<TOpenedHandle>;
  mNever: Boolean;
  mFixes: TArray<TRuleFix>;
  mStatement: TSyntaxNode;
begin
  if not Opened(ACall, ATarget, mHandles) then
  begin
    Exit;
  end;
  mLeaked := LeakedHandles(ANode, ACall, mHandles, mNever);
  if mLeaked = nil then
  begin
    Exit;
  end;
  mFixes := nil;
  mStatement := ANode.Syntax;
  if mNever and (ANode.Kind = TFlowNodeKind.Statement) and (mStatement.StartPos.Line = mStatement.EndPos.Line) then
  begin
    mFixes := WrapFix(mStatement, mLeaked);
  end;
  FReport.Add(NodeRange(ACall), LeakMessage(mLeaked, mNever), TRuleConfidence.Medium, mFixes);
end;

procedure THandleCheck.CheckNode(ANode: TFlowNode);
var
  mCalls: TArray<TSyntaxNode>;
  mTargets: TArray<string>;
  mPart: TSyntaxNode;
  mIndex, mFirst: Integer;
begin
  // with: die Anweisungen darin sind eigene Knoten.
  if (ANode.Syntax = nil) or not (ANode.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) or
    (ANode.Syntax.Kind = TSyntaxKind.WithStatement) then
  begin
    Exit;
  end;
  mCalls := nil;
  mTargets := nil;
  for mPart in NodeParts(ANode) do
  begin
    mFirst := Length(mCalls);
    CollectOpens(mPart, mCalls, mTargets);
    NoteTargets(mPart, mFirst, mCalls, mTargets);
  end;
  for mIndex := 0 to High(mCalls) do
  begin
    CheckOpen(ANode, mCalls[mIndex], mTargets[mIndex]);
  end;
end;

procedure THandleCheck.CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
var
  mNode: TFlowNode;
begin
  FRoutine := ARoutine;
  FLocals := DeclaredLocals(ARoutine);
  if FLocals = nil then
  begin
    Exit;
  end;
  FGraph := TRuleDerived.Graph(ACache, FContext, ARoutine);
  if not FGraph.Complete then
  begin
    Exit;
  end;
  for mNode in FGraph.Nodes do
  begin
    CheckNode(mNode);
  end;
end;

procedure THandleCheck.Run;
var
  mCache: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  FTable := HandleTable(HandlePairs(FContext.Options));
  mCache := TRuleDerived.Open(FContext);
  for mRoutine in TRuleDerived.Routines(mCache, FContext) do
  begin
    CheckRoutine(mCache, mRoutine);
  end;
end;

{ THandleLeakRule }

function THandleLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cHandleLeakRuleId, TRuleSeverity.Warning, cTexts[TFlowHandleLeakText.Title].Text);
end;

class function THandleLeakRule.Pairs(const AOptions: string): TArray<string>;
begin
  Result := HandlePairs(AOptions);
end;

procedure THandleLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: THandleCheck;
begin
  mCheck := THandleCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.HandleLeak', cTexts);

end.
