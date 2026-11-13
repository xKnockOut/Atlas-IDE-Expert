unit Atlas.Common.Rules.Builtin.Performance.SetLengthInLoop;

// setlength-in-loop (#974, standardmäßig an): SetLength(A, Length(A) + 1) in einer Schleife kopiert das
// dynamische Array bei jedem Durchlauf; gemeldet wird nur, wenn A sicher ein dynamisches Array ist (Typ in der
// Datei bzw. bekannter RTL-Typ, nie Strings). Bei einer for-Schleife ist die Anzahl bekannt; dann setzt die
// Korrektur die Länge vor der Schleife, wenn A eine lokale Variable ist, die vorher nicht benutzt wird, und A in
// der Schleife nur über A[High(A)] bzw. A[Length(A) - 1] beschrieben wird. Angemeldet wird die Regel mit den
// übrigen Performance-Regeln (Atlas.Common.Rules.Builtin.Performance).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TSetLengthInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Builtin.Performance.StringResets,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Performance.DynamicArrays,
  Atlas.Common.Rules.Builtin.Performance.ManagedParams,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TSetLengthText = (SetLengthBefore, SetLengthKnown, SetLengthUnknown, GrowTitle);

const
  cTexts: array[TSetLengthText] of TAtlasText = (
    (De: 'Länge von %s vor der Schleife setzen'; En: 'Set the length of %s before the loop'),
    (De: 'SetLength in der Schleife kopiert %s bei jedem Durchlauf; die Anzahl %s ist vorher bekannt.';
     En: 'SetLength in the loop copies %s on every iteration; the count %s is known beforehand.'),
    (De: 'SetLength in der Schleife kopiert %s bei jedem Durchlauf; die Länge vor der Schleife setzen oder die Werte ' +
      'in einer TList<T> sammeln.';
     En: 'SetLength in the loop copies %s on every iteration; set the length before the loop or collect the values ' +
      'in a TList<T>.'),
    (De: 'Dynamisches Array wächst in einer Schleife um je ein Element';
     En: 'Dynamic array grows by one element per loop iteration'));

{$SCOPEDENUMS OFF}

{ TSetLengthInLoopRule }

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Ist ANode der Aufruf AName(X) mit genau einem Argument, dessen Text ATarget ist?</summary>
function IsCallOf(const AText: string; ANode: TSyntaxNode; const AName, ATarget: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    SameText(ANode.Name, AName) and SameText(NodeText(AText, ANode[1]), ATarget);
end;

/// <summary>Ganzzahliges Literal ab 1?</summary>
function IsPositiveLiteral(ANode: TSyntaxNode): Boolean;
var
  mValue: Integer;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and TryStrToInt(ANode.Name, mValue) and (mValue >= 1);
end;

/// <summary>Vergrößert ALength die Länge von ATarget um einen festen Schritt: Length(A) + n, n + Length(A),
/// Succ(Length(A)) oder High(A) + n mit n ab 2?</summary>
function IsGrowth(const AText: string; ALength: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := False;
  if (ALength.Kind = TSyntaxKind.Call) and SameText(ALength.Name, 'Succ') and (ALength.ChildCount = 2) then
  begin
    Exit(IsCallOf(AText, ALength[1], 'Length', ATarget));
  end;
  if (ALength.Kind <> TSyntaxKind.BinaryExpr) or (ALength.Name <> '+') or (ALength.ChildCount <> 2) then
  begin
    Exit;
  end;
  if IsCallOf(AText, ALength[0], 'Length', ATarget) then
  begin
    Result := IsPositiveLiteral(ALength[1]);
  end
  else if IsCallOf(AText, ALength[1], 'Length', ATarget) then
  begin
    Result := IsPositiveLiteral(ALength[0]);
  end
  else if IsCallOf(AText, ALength[0], 'High', ATarget) then
  begin
    Result := IsPositiveLiteral(ALength[1]) and (ALength[1].Name <> '1');
  end;
end;

/// <summary>Letztes Element von ATarget als Index: High(A) bzw. Length(A) - 1?</summary>
function IsLastIndex(const AText: string; AIndex: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := IsCallOf(AText, AIndex, 'High', ATarget) or
    ((AIndex.Kind = TSyntaxKind.BinaryExpr) and (AIndex.Name = '-') and (AIndex.ChildCount = 2) and
    IsCallOf(AText, AIndex[0], 'Length', ATarget) and (AIndex[1].Kind = TSyntaxKind.Literal) and
    (AIndex[1].Name = '1'));
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

/// <summary>Innerste Schleife um ANode innerhalb derselben Routine; nil ohne.</summary>
function EnclosingLoop(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not IsLoop(Result) do
  begin
    if Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

/// <summary>Rumpf der Schleife; bei repeat nil (mehrere Anweisungen).</summary>
function LoopBody(ALoop: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ALoop.Kind <> TSyntaxKind.RepeatStatement) and (ALoop.ChildCount > 0) then
  begin
    Result := ALoop[ALoop.ChildCount - 1];
  end;
end;

/// <summary>Steht AStatement direkt im Rumpf von ALoop, wird es also bei jedem Durchlauf ausgeführt?</summary>
function RunsEveryIteration(ALoop, AStatement: TSyntaxNode): Boolean;
var
  mBody: TSyntaxNode;
begin
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    Exit(AStatement.Parent = ALoop);
  end;
  mBody := LoopBody(ALoop);
  Result := (mBody = AStatement) or ((mBody <> nil) and (mBody.Kind = TSyntaxKind.Block) and
    (AStatement.Parent = mBody));
end;

/// <summary>Ergebnistyp der Funktion um ANode als Quelltext; '' ohne.</summary>
function ResultType(const AText: string; ANode: TSyntaxNode): string;
var
  mRoutine, mHeader: TSyntaxNode;
begin
  Result := '';
  mRoutine := ANode.Parent;
  while (mRoutine <> nil) and (mRoutine.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if mRoutine.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit;
    end;
    mRoutine := mRoutine.Parent;
  end;
  if mRoutine = nil then
  begin
    Exit;
  end;
  mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (mHeader <> nil) and (mHeader.ChildCount > 0) and
    (mHeader[mHeader.ChildCount - 1].Kind <> TSyntaxKind.Parameters) then
  begin
    mHeader := mHeader.FindChild(TSyntaxKind.TypeReference);
    if mHeader <> nil then
    begin
      Result := NodeText(AText, mHeader);
    end;
  end;
end;

/// <summary>Anzahl der Durchläufe einer for-Schleife als Quelltext; '' wenn sie nicht sicher zu bestimmen ist.
/// ALoopIndex: Ausdruck für den Index des I-ten Elements (I bzw. I - Start).</summary>
function ForCount(const AText: string; ALoop: TSyntaxNode; out ALoopIndex: string): string;
var
  mFirst, mLast: TSyntaxNode;
  mLowText, mHighText: string;
begin
  Result := '';
  ALoopIndex := '';
  if (ALoop.Kind <> TSyntaxKind.ForStatement) or (ALoop.ChildCount < 3) then
  begin
    Exit;
  end;
  mFirst := ALoop[ALoop.ChildCount - 3];
  mLast := ALoop[ALoop.ChildCount - 2];
  if ContainsText(Copy(AText, mFirst.EndOffset + 1, mLast.StartOffset - mFirst.EndOffset), 'downto') then
  begin
    Exit;
  end;
  mLowText := Trim(NodeText(AText, mFirst));
  mHighText := Trim(NodeText(AText, mLast));
  if mLowText = '0' then
  begin
    ALoopIndex := ALoop.Name;
    if (mLast.Kind = TSyntaxKind.BinaryExpr) and (mLast.Name = '-') and (mLast.ChildCount = 2) and
      (mLast[1].Kind = TSyntaxKind.Literal) and (mLast[1].Name = '1') then
    begin
      Result := Trim(NodeText(AText, mLast[0]));
    end
    else
    begin
      Result := mHighText + ' + 1';
    end;
  end
  else if mLowText = '1' then
  begin
    Result := mHighText;
    ALoopIndex := ALoop.Name + ' - 1';
  end
  else
  begin
    Result := Format('%s - %s + 1', [mHighText, mLowText]);
    ALoopIndex := Format('%s - %s', [ALoop.Name, mLowText]);
  end;
end;

/// <summary>Routine um ANode; nil ohne oder in einer anonymen Methode.</summary>
function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if Result.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

/// <summary>Deklariert der var-Abschnitt ASection den Namen AName?</summary>
function SectionDeclares(ASection: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    for mName in SplitString(ASection[mIndex].Name, ',') do
    begin
      if SameText(Trim(mName), AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Ist AName eine lokale Variable der Routine ARoutine?</summary>
function DeclaresLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if (ARoutine[mIndex].Kind = TSyntaxKind.VarSection) and SectionDeclares(ARoutine[mIndex], AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kommt AName in ABody vor der Stelle AOffset vor?</summary>
function UsedBefore(ABody: TSyntaxNode; AOffset: Integer; const AName: string): Boolean;
var
  mUsed: Boolean;
  mName: string;
begin
  mUsed := False;
  mName := AName;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not mUsed;
      if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.EndOffset <= AOffset) and SameText(ANode.Name, mName) then
      begin
        mUsed := True;
      end;
    end);
  Result := mUsed;
end;

/// <summary>A[High(A)] bzw. A[Length(A) - 1] für A = ATarget?</summary>
function IsLastElement(const AText: string; ANode: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, ATarget) and
    IsLastIndex(AText, ANode[1], ATarget);
end;

/// <summary>Andere Verwendung von ATarget oder ein Sprung (Break, Continue, Exit, goto), der das Array
/// verkürzt?</summary>
function SpoilsCount(ANode: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := ((ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, ATarget)) or
    ((ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.CallStatement]) and
    MatchText(ANode.Name, ['Break', 'Continue', 'Exit'])) or (ANode.Kind = TSyntaxKind.GotoStatement);
end;

/// <summary>Einzige Anweisung im Block ABody außer AStatement; nil, wenn es nicht genau eine gibt.</summary>
function SoleOther(ABody, AStatement: TSyntaxNode): TSyntaxNode;
var
  mIndex, mRemaining: Integer;
begin
  Result := nil;
  mRemaining := 0;
  if ABody.Kind = TSyntaxKind.Block then
  begin
    for mIndex := 0 to ABody.ChildCount - 1 do
    begin
      if ABody[mIndex] <> AStatement then
      begin
        Inc(mRemaining);
        Result := ABody[mIndex];
      end;
    end;
  end;
  if mRemaining <> 1 then
  begin
    Result := nil;
  end;
end;

/// <summary>Alle SetLength(A, …)-Anweisungen der Datei.</summary>
function SetLengthCalls(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mCalls: TArray<TSyntaxNode>;
begin
  mCalls := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
        (ANode[0].Kind = TSyntaxKind.Call) and SameText(ANode[0].Name, 'SetLength') and (ANode[0].ChildCount = 3) then
      begin
        mCalls := mCalls + [ANode];
      end;
    end);
  Result := mCalls;
end;

type
  /// <summary>Prüft eine Datei auf setlength-in-loop.</summary>
  TSetLengthScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTypes: TDeclaredTypes;
    FArrayTypes: TArray<string>;
    /// <summary>Array der gerade geprüften Anweisung, Anzahl der Durchläufe und Index des I-ten Elements.</summary>
    FTarget: string;
    FCount: string;
    FLoopIndex: string;
    function Range(AStart, AEnd: Integer): TTextRange;
    function LineStart(AOffset: Integer): Integer;
    function Indent(AOffset: Integer): string;
    function SkipBlanks(AOffset: Integer): Integer;
    function WholeLines(AStatement: TSyntaxNode; out AStart, AEnd: Integer): Boolean;
    function FreshLocal(ALoop: TSyntaxNode): Boolean;
    function Rewrite(AFrom, ATo: Integer; const AReplaced: TArray<TSyntaxNode>; const ANew: string): string;
    function OnOwnLine(AOffset: Integer): Boolean;
    function LastIndexUses(ABody, AStatement: TSyntaxNode; out AReplaced: TArray<TSyntaxNode>): Boolean;
    function StatementEdits(AStart, AStop: Integer; const AReplaced: TArray<TSyntaxNode>): TArray<TRuleEdit>;
    function CountFix(ALoop, AStatement: TSyntaxNode): TArray<TRuleFix>;
    function TargetType(AStatement, ATargetNode: TSyntaxNode): string;
    procedure ReportCall(ALoop, AStatement: TSyntaxNode);
    procedure CheckCall(AStatement: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TSetLengthScan }

constructor TSetLengthScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TSetLengthScan.Range(AStart, AEnd: Integer): TTextRange;
begin
  Result := TRuleDerived.OffsetRange(FCache, FContext, AStart, AEnd);
end;

function TSetLengthScan.LineStart(AOffset: Integer): Integer;
begin
  Result := AOffset;
  while (Result > 0) and not CharInSet(FContext.Text[Result], [#10, #13]) do
  begin
    Dec(Result);
  end;
end;

function TSetLengthScan.Indent(AOffset: Integer): string;
var
  mStart, mIndex: Integer;
begin
  mStart := LineStart(AOffset);
  mIndex := mStart;
  while (mIndex < AOffset) and CharInSet(FContext.Text[mIndex + 1], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(FContext.Text, mStart + 1, mIndex - mStart);
end;

/// <summary>Stelle nach Leerzeichen und Tabs ab AOffset.</summary>
function TSetLengthScan.SkipBlanks(AOffset: Integer): Integer;
begin
  Result := AOffset;
  while (Result < Length(FContext.Text)) and CharInSet(FContext.Text[Result + 1], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Bereich der ganzen Zeile(n) von AStatement samt folgendem ; und Zeilenende; False, wenn mehr in der
/// Zeile steht.</summary>
function TSetLengthScan.WholeLines(AStatement: TSyntaxNode; out AStart, AEnd: Integer): Boolean;
begin
  AStart := LineStart(AStatement.StartOffset);
  Result := Trim(Copy(FContext.Text, AStart + 1, AStatement.StartOffset - AStart)) = '';
  AEnd := SkipBlanks(AStatement.EndOffset);
  if (AEnd < Length(FContext.Text)) and (FContext.Text[AEnd + 1] = ';') then
  begin
    Inc(AEnd);
  end;
  AEnd := SkipBlanks(AEnd);
  if (AEnd < Length(FContext.Text)) and (FContext.Text[AEnd + 1] = #13) then
  begin
    Inc(AEnd);
  end;
  if (AEnd < Length(FContext.Text)) and (FContext.Text[AEnd + 1] = #10) then
  begin
    Inc(AEnd);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Lokale Variable FTarget der Routine um ALoop, die vor der Schleife nicht vorkommt?</summary>
function TSetLengthScan.FreshLocal(ALoop: TSyntaxNode): Boolean;
var
  mRoutine, mBody: TSyntaxNode;
begin
  mRoutine := EnclosingRoutine(ALoop);
  if (mRoutine = nil) or not DeclaresLocal(mRoutine, FTarget) then
  begin
    Exit(False);
  end;
  mBody := mRoutine.FindChild(TSyntaxKind.Block);
  Result := (mBody <> nil) and not UsedBefore(mBody, ALoop.StartOffset, FTarget);
end;

/// <summary>Text von AFrom bis ATo mit den Ersetzungen in AEdits (Offsets) darin.</summary>
function TSetLengthScan.Rewrite(AFrom, ATo: Integer; const AReplaced: TArray<TSyntaxNode>; const ANew: string): string;
var
  mIndex: Integer;
begin
  Result := Copy(FContext.Text, AFrom + 1, ATo - AFrom);
  for mIndex := High(AReplaced) downto 0 do
  begin
    if (AReplaced[mIndex].StartOffset >= AFrom) and (AReplaced[mIndex].EndOffset <= ATo) then
    begin
      Result := Copy(Result, 1, AReplaced[mIndex].StartOffset - AFrom) + ANew +
        Copy(Result, AReplaced[mIndex].EndOffset - AFrom + 1, MaxInt);
    end;
  end;
end;

function TSetLengthScan.OnOwnLine(AOffset: Integer): Boolean;
begin
  Result := Trim(Copy(FContext.Text, LineStart(AOffset) + 1, AOffset - LineStart(AOffset))) = '';
end;

/// <summary>Jede andere Stelle mit FTarget im Rumpf muss A[High(A)] bzw. A[Length(A) - 1] sein; Sprünge verkürzen
/// das Array. AReplaced: die Indexausdrücke dieser Stellen.</summary>
function TSetLengthScan.LastIndexUses(ABody, AStatement: TSyntaxNode; out AReplaced: TArray<TSyntaxNode>): Boolean;
var
  mSafe: Boolean;
  mReplaced: TArray<TSyntaxNode>;
  mText, mTarget: string;
begin
  mSafe := True;
  mReplaced := nil;
  mText := FContext.Text;
  mTarget := FTarget;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mSafe and (ANode <> AStatement);
      if not Result then
      begin
        Exit;
      end;
      if IsLastElement(mText, ANode, mTarget) then
      begin
        mReplaced := mReplaced + [ANode[1]];
        Exit(False);
      end;
      if SpoilsCount(ANode, mTarget) then
      begin
        mSafe := False;
      end;
    end);
  AReplaced := mReplaced;
  Result := mSafe and (mReplaced <> nil);
end;

/// <summary>SetLength-Zeilen AStart bis AStop entfernen, die Indexausdrücke durch FLoopIndex ersetzen.</summary>
function TSetLengthScan.StatementEdits(AStart, AStop: Integer; const AReplaced: TArray<TSyntaxNode>): TArray<TRuleEdit>;
var
  mIndex: Integer;
begin
  Result := [TRuleEdit.Create(Range(AStart, AStop), '')];
  for mIndex := 0 to High(AReplaced) do
  begin
    Result := Result + [TRuleEdit.Create(Range(AReplaced[mIndex].StartOffset, AReplaced[mIndex].EndOffset),
      FLoopIndex)];
  end;
end;

/// <summary>Korrektur: Länge vor der Schleife setzen, SetLength entfernen, A[High(A)] durch A[I] ersetzen.
/// Bleibt im begin … end nur eine Anweisung, entfällt der Block.</summary>
function TSetLengthScan.CountFix(ALoop, AStatement: TSyntaxNode): TArray<TRuleFix>;
var
  mBody, mOther: TSyntaxNode;
  mEdits: TArray<TRuleEdit>;
  mReplaced: TArray<TSyntaxNode>;
  mStart, mStop: Integer;
begin
  Result := nil;
  mBody := LoopBody(ALoop);
  if (FLoopIndex = '') or (mBody = nil) or not FreshLocal(ALoop) or not WholeLines(AStatement, mStart, mStop) or
    not LastIndexUses(mBody, AStatement, mReplaced) then
  begin
    Exit;
  end;
  mEdits := [TRuleEdit.Create(Range(LineStart(ALoop.StartOffset), LineStart(ALoop.StartOffset)),
    Indent(ALoop.StartOffset) + Format('SetLength(%s, %s);', [FTarget, FCount]) +
    TTextLines.LineBreakOf(FContext.Text))];
  mOther := SoleOther(mBody, AStatement);
  if (mOther <> nil) and OnOwnLine(mBody.StartOffset) and OnOwnLine(mBody.EndOffset - 3) and
    OnOwnLine(mOther.StartOffset) and (mOther.StartOffset > AStatement.StartOffset) then
  begin
    // Die Anweisung steht schon zwei Zeichen tiefer als begin, also dort, wo sie ohne Block hingehört.
    mEdits := mEdits + [TRuleEdit.Create(Range(LineStart(mBody.StartOffset), mBody.EndOffset),
      Rewrite(LineStart(mOther.StartOffset), mOther.EndOffset, mReplaced, FLoopIndex))];
  end
  else
  begin
    mEdits := mEdits + StatementEdits(mStart, mStop, mReplaced);
  end;
  Result := [TRuleFix.Create(cTexts[TSetLengthText.SetLengthBefore].Fmt([FTarget]), mEdits)];
end;

/// <summary>Deklarierter Typ des Arrays bzw. Ergebnistyp bei Result.</summary>
function TSetLengthScan.TargetType(AStatement, ATargetNode: TSyntaxNode): string;
begin
  Result := FTypes.DeclaredType(FTarget, ATargetNode.StartPos);
  if (Result = '') and SameText(FTarget, 'Result') then
  begin
    Result := ResultType(FContext.Text, AStatement);
  end;
end;

procedure TSetLengthScan.ReportCall(ALoop, AStatement: TSyntaxNode);
begin
  if FCount <> '' then
  begin
    FReport.Add(Range(AStatement.StartOffset, AStatement.EndOffset),
      cTexts[TSetLengthText.SetLengthKnown].Fmt([FTarget, FCount]), CountFix(ALoop, AStatement));
  end
  else
  begin
    FReport.Add(Range(AStatement.StartOffset, AStatement.EndOffset), cTexts[TSetLengthText.SetLengthUnknown].Fmt(
      [FTarget]));
  end;
end;

procedure TSetLengthScan.CheckCall(AStatement: TSyntaxNode);
var
  mCall, mLoop: TSyntaxNode;
begin
  mCall := AStatement[0];
  if mCall[1].Kind <> TSyntaxKind.Identifier then
  begin
    Exit;
  end;
  FTarget := mCall[1].Name;
  mLoop := EnclosingLoop(AStatement);
  if (mLoop = nil) or not IsGrowth(FContext.Text, mCall[2], FTarget) or
    not TDynamicArrayTypes.IsDynamic(TargetType(AStatement, mCall[1]), FArrayTypes) then
  begin
    Exit;
  end;
  FCount := '';
  FLoopIndex := '';
  if RunsEveryIteration(mLoop, AStatement) then
  begin
    FCount := ForCount(FContext.Text, mLoop, FLoopIndex);
  end;
  ReportCall(mLoop, AStatement);
end;

procedure TSetLengthScan.Run;
var
  mCalls: TArray<TSyntaxNode>;
  mStatement: TSyntaxNode;
begin
  mCalls := SetLengthCalls(FContext.Tree.Root);
  if mCalls = nil then
  begin
    Exit;
  end;
  FCache := TRuleDerived.Open(FContext);
  FArrayTypes := TDynamicArrayTypes.DeclaredIn(FContext.Text, FContext.Tree.Root);
  FTypes := TDeclaredTypes.Create(FContext.Tree, FContext.Text);
  try
    for mStatement in mCalls do
    begin
      CheckCall(mStatement);
    end;
  finally
    FreeAndNil(FTypes);
  end;
end;

function TSetLengthInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('setlength-in-loop', TRuleSeverity.Hint,
    cTexts[TSetLengthText.GrowTitle].Text);
end;

procedure TSetLengthInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TSetLengthScan;
begin
  // Vorfilter: ohne SetLength keine Arbeit.
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'SetLength') then
  begin
    Exit;
  end;
  mScan := TSetLengthScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Performance.SetLengthInLoop', cTexts);

end.
