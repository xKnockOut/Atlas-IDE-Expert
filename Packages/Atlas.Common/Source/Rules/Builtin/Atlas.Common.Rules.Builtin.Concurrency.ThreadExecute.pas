unit Atlas.Common.Rules.Builtin.Concurrency.ThreadExecute;

// Prüfregel thread-execute-without-except (Teil von Atlas.Common.Rules.Builtin.Concurrency, dort registriert): Eine
// Ausnahme, die TThread.Execute verlässt, beendet den Thread still; Delphi legt sie nur in FatalException ab.
// IsThreadExecuteGuard teilt die Erkennung mit catch-all-without-raise: Der äußere Handler von Execute fängt dort
// zu Recht, ohne erneut auszulösen.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

type
  TThreadExecuteWithoutExceptRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Ist der Ausnahme-Handler AHandler (ExceptionHandler) Teil des äußeren try … except, der den ganzen Rumpf
/// von Execute einer Thread-Klasse umschließt?</summary>
function IsThreadExecuteGuard(const AContext: TRuleContext; AHandler: TSyntaxNode): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TThreadExecuteText = (Title, Silent, SilentCall, WrapTry);

  /// <summary>Schutz eines Rumpfs: ganz in try … except, nicht geschützt oder unbekannt (Aufruf einer Routine, deren
  /// Rumpf die Unit nicht kennt).</summary>
  TExecuteGuard = (Guarded, Open, Unknown);

const
  cTexts: array[TThreadExecuteText] of TAtlasText = (
    (De: 'Ausnahme in TThread.Execute beendet den Thread still';
     En: 'Exception in TThread.Execute ends the thread silently'),
    (De: 'Eine Ausnahme in Execute beendet den Thread still (nur FatalException). Ausnahmen abfangen und melden.';
     En: 'An exception in Execute ends the thread silently (only FatalException). Catch and report exceptions.'),
    (De: 'Eine Ausnahme in Execute beendet den Thread still (nur FatalException), wenn %s sie nicht selbst fängt. ' +
      'Ausnahmen abfangen und melden.';
     En: 'An exception in Execute ends the thread silently (only FatalException) unless %s catches it itself. ' +
      'Catch and report exceptions.'),
    (De: 'Rumpf in try … except mit Meldung über %s einschließen';
     En: 'Wrap the body in try … except with a message via %s'));

  /// <summary>Wie tief die Regel Aufrufen folgt, deren Rumpf nur aus einem Aufruf besteht.</summary>
  cMaxCallDepth = 4;

{$SCOPEDENUMS OFF}

{ Erkennung }

/// <summary>Anweisungen von AList ohne leere Anweisungen und ohne den finally- bzw. except-Teil eines try.</summary>
function OwnStatements(AList: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to AList.ChildCount - 1 do
  begin
    mChild := AList[mIndex];
    if not (mChild.Kind in [TSyntaxKind.EmptyStatement, TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock]) then
    begin
      Result := Result + [mChild];
    end;
  end;
end;

/// <summary>Fängt der except-Teil von ATry alle Ausnahmen (except ohne on, on E: Exception, on TObject oder else)?
/// </summary>
function CatchesAll(ATry: TSyntaxNode): Boolean;
var
  mExcept, mChild, mType: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mExcept := ATry.FindChild(TSyntaxKind.ExceptBlock);
  if mExcept = nil then
  begin
    Exit;
  end;
  if mExcept.FindChild(TSyntaxKind.ExceptionHandler) = nil then
  begin
    Exit(True);
  end;
  for mIndex := 0 to mExcept.ChildCount - 1 do
  begin
    mChild := mExcept[mIndex];
    if mChild.Kind <> TSyntaxKind.ExceptionHandler then
    begin
      // Anweisungen neben den Handlern: der else-Teil fängt den Rest.
      Exit(True);
    end;
    mType := mChild.FindChild(TSyntaxKind.TypeReference);
    if (mType <> nil) and MatchText(ShortName(mType.Name), ['Exception', 'TObject']) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Anweisungen vor dem Schutz, die selbst nichts auslösen: der Name des Threads für den Debugger.</summary>
function IsHarmless(AStatement: TSyntaxNode): Boolean;
var
  mCall: TMethodCall;
begin
  Result := TryMethodCall(AStatement, mCall) and SameText(mCall.Method, 'NameThreadForDebugging');
end;

/// <summary>Name der Routine, die die Anweisung AStatement allein aufruft (M, M(…), Self.M(…), inherited bzw.
/// inherited M), sonst ''. Bei inherited ist AInherited gesetzt.</summary>
function CalledName(AStatement: TSyntaxNode; out AInherited: Boolean): string;
var
  mTarget: TSyntaxNode;
begin
  Result := '';
  AInherited := False;
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    mTarget := mTarget[0];
  end;
  case mTarget.Kind of
    TSyntaxKind.Identifier:
      Result := mTarget.Name;
    TSyntaxKind.MemberAccess:
      Result := VariableName(mTarget);
    TSyntaxKind.InheritedExpr:
      begin
        AInherited := True;
        Result := mTarget.Name;
      end;
  end;
end;

/// <summary>Nennt ARoutine im Rumpf oder in den lokalen Deklarationen den Typ AType (Variable, Aufruf, Umwandlung)?
/// </summary>
function NamesType(ARoutine: TSyntaxNode; const AType: string): Boolean;
begin
  Result := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if ANode.Kind = TSyntaxKind.RoutineHeader then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.TypeReference]) and
        SameText(ShortName(ANode.Name), AType) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else
      begin
        Result := TSyntaxSearchStep.Descend;
      end;
    end) <> nil;
end;

type
  /// <summary>Ein Lauf von TThreadExecuteWithoutExceptRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TThreadExecuteScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoutines: TArray<TSyntaxNode>;
    FAncestry: TAncestry;
    FLines: TArray<string>;
    FLineBreak: string;
    /// <summary>Unbekannte Routine, die der zuletzt geprüfte Rumpf aufruft (für die Meldung).</summary>
    FUnknownCall: string;
    function FindRoutine(const AName: string): TSyntaxNode;
    function CalleeOf(const AClass, AName: string; AInherited: Boolean; ANested: TSyntaxNode): TSyntaxNode;
    function GuardOfList(const AStatements: TArray<TSyntaxNode>; const AClass: string; ARoutine: TSyntaxNode;
      ADepth: Integer): TExecuteGuard;
    function GuardOf(ARoutine: TSyntaxNode; const AClass: string; ADepth: Integer): TExecuteGuard;
    function ReadsFatalException(ANode: TSyntaxNode): Boolean;
    function ClassChain(const AClass: string): TArray<string>;
    function EvaluatesFatalException(const AClass: string): Boolean;
    function EvaluatedInOtherUnits(const AClass: string): Boolean;
    function LoggerField(const AClass: string): string;
    function OnOwnLine(const APosition: TTextPosition; ALength: Integer): Boolean;
    function WrapFix(ABody: TSyntaxNode; const ALogger: string): TArray<TRuleFix>;
    procedure CheckExecute(ARoutine: TSyntaxNode; const AClass: string);
    function IsThreadClass(const AOwner: string): Boolean;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    /// <summary>Thread-Klassen der Unit (aus der Unit und dem Index).</summary>
    function ThreadClassNames: TArray<string>;
    procedure Run;
  end;

{ TThreadExecuteScan }

constructor TThreadExecuteScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRoutines := TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
end;

destructor TThreadExecuteScan.Destroy;
begin
  FAncestry.Free;
  FRoutines := nil;
  FLines := nil;
  inherited;
end;

function TThreadExecuteScan.FindRoutine(const AName: string): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in FRoutines do
  begin
    if SameText(mRoutine.Name, AName) then
    begin
      Exit(mRoutine);
    end;
  end;
  Result := nil;
end;

// Die aufgerufene Routine: eingebettet in ANested, Methode der Klasse oder ihrer Vorfahren in der Unit, sonst eine
// freie Routine der Unit; nil, wenn ihr Rumpf nicht in der Unit steht.
function TThreadExecuteScan.CalleeOf(const AClass, AName: string; AInherited: Boolean;
  ANested: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mClass: string;
  mFirst: Boolean;
begin
  if not AInherited then
  begin
    for mIndex := 0 to ANested.ChildCount - 1 do
    begin
      if (ANested[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ANested[mIndex].Name, AName) then
      begin
        Exit(ANested[mIndex]);
      end;
    end;
  end;
  mFirst := True;
  for mClass in ClassChain(AClass) do
  begin
    if not (AInherited and mFirst) then
    begin
      Result := FindRoutine(mClass + '.' + AName);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
    mFirst := False;
  end;
  if AInherited then
  begin
    Exit(nil);
  end;
  Result := FindRoutine(AName);
end;

function TThreadExecuteScan.GuardOfList(const AStatements: TArray<TSyntaxNode>; const AClass: string;
  ARoutine: TSyntaxNode; ADepth: Integer): TExecuteGuard;
var
  mFirst: Integer;
  mStatement, mCallee: TSyntaxNode;
  mName: string;
  mInherited: Boolean;
begin
  Result := TExecuteGuard.Open;
  mFirst := 0;
  while (mFirst < Length(AStatements)) and IsHarmless(AStatements[mFirst]) do
  begin
    Inc(mFirst);
  end;
  if mFirst <> High(AStatements) then
  begin
    Exit;
  end;
  mStatement := AStatements[mFirst];
  if mStatement.Kind = TSyntaxKind.TryStatement then
  begin
    if CatchesAll(mStatement) then
    begin
      Result := TExecuteGuard.Guarded;
    end
    else if mStatement.FindChild(TSyntaxKind.FinallyBlock) <> nil then
    begin
      // try … finally um einen geschützten Teil: Der Schutz liegt innen.
      Result := GuardOfList(OwnStatements(mStatement), AClass, ARoutine, ADepth);
    end;
    Exit;
  end;
  mName := CalledName(mStatement, mInherited);
  if ((mName = '') and not mInherited) or (ADepth >= cMaxCallDepth) then
  begin
    Exit;
  end;
  if mName = '' then
  begin
    mName := MethodPart(ARoutine.Name);
  end;
  mCallee := CalleeOf(AClass, mName, mInherited, ARoutine);
  if mCallee = nil then
  begin
    FUnknownCall := mName;
    Result := TExecuteGuard.Unknown;
  end
  else if mCallee <> ARoutine then
  begin
    Result := GuardOf(mCallee, AClass, ADepth + 1);
  end;
end;

function TThreadExecuteScan.GuardOf(ARoutine: TSyntaxNode; const AClass: string; ADepth: Integer): TExecuteGuard;
var
  mBody: TSyntaxNode;
begin
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    // asm-Rumpf: keine Aussage.
    Exit(TExecuteGuard.Unknown);
  end;
  Result := GuardOfList(OwnStatements(mBody), AClass, ARoutine, ADepth);
end;

function TThreadExecuteScan.ReadsFatalException(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
        SameText(ANode.Name, 'FatalException') then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else
      begin
        Result := TSyntaxSearchStep.Descend;
      end;
    end) <> nil;
end;

/// <summary>AClass und ihre Vorfahren bis vor TThread (soweit bekannt).</summary>
function TThreadExecuteScan.ClassChain(const AClass: string): TArray<string>;
var
  mClass: string;
begin
  Result := nil;
  mClass := AClass;
  while (mClass <> '') and not SameText(mClass, 'TThread') and not SameText(mClass, 'TObject') and
    (Length(Result) < 32) do
  begin
    Result := Result + [mClass];
    mClass := FAncestry.ParentOf(mClass);
  end;
end;

// Wertet die Unit FatalException für AClass aus: DoTerminate (bzw. jede andere Methode außer Execute) der Klasse oder
// eines Vorfahren liest sie, oder eine Routine nennt die Klasse und liest FatalException (OnTerminate-Handler, Code
// nach WaitFor), oder ein OnTerminate-Handler, der sie liest, wird in einer Routine zugewiesen, die die Klasse nennt.
function TThreadExecuteScan.EvaluatesFatalException(const AClass: string): Boolean;
var
  mRoutine: TSyntaxNode;
  mReaders: TArray<string>;
  mChain: TArray<string>;
  mOwner: string;
begin
  mChain := ClassChain(AClass);
  mReaders := nil;
  for mRoutine in FRoutines do
  begin
    if not ReadsFatalException(mRoutine) then
    begin
      Continue;
    end;
    mOwner := ClassPart(mRoutine.Name);
    if (InList(mChain, mOwner) and not SameText(MethodPart(mRoutine.Name), 'Execute')) or NamesType(mRoutine, AClass) then
    begin
      Exit(True);
    end;
    mReaders := mReaders + [MethodPart(mRoutine.Name)];
  end;
  for mRoutine in FRoutines do
  begin
    if NamesType(mRoutine, AClass) and
      (mRoutine.Search(
        function(ANode: TSyntaxNode): TSyntaxSearchStep
        begin
          Result := TSyntaxSearchStep.Descend;
          if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
            (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, 'OnTerminate') and
            InList(mReaders, ShortName(SourceText(FContext.Text, ANode[1]))) then
          begin
            Result := TSyntaxSearchStep.Found;
          end;
        end) <> nil) then
    begin
      Exit(True);
    end;
  end;
  Result := EvaluatedInOtherUnits(AClass);
end;

// Andere Units des Projekts, die die Klasse nennen und FatalException lesen (Verwendungen im Index, nur mit
// index.usages): Dort wertet der Erzeuger die Ausnahme aus.
function TThreadExecuteScan.EvaluatedInOtherUnits(const AClass: string): Boolean;
var
  mUnit: TUnitIndex;
  mUsage: TIndexUsage;
  mClass, mFatal: Boolean;
begin
  Result := False;
  if FContext.Index = nil then
  begin
    Exit;
  end;
  for mUnit in FContext.Index.Units do
  begin
    if mUnit.Library_ or not mUnit.UsagesIndexed or SameText(mUnit.UnitName, FContext.UnitName) then
    begin
      Continue;
    end;
    mClass := False;
    mFatal := False;
    for mUsage in mUnit.Usages do
    begin
      mClass := mClass or SameText(mUsage.Name, AClass);
      mFatal := mFatal or SameText(mUsage.Name, 'FatalException');
    end;
    if mClass and mFatal then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Name eines Felds vom Typ ILogger in AClass oder einem Vorfahren der Unit; '' ohne.</summary>
function TThreadExecuteScan.LoggerField(const AClass: string): string;
var
  mSymbol: TIndexSymbol;
  mClass: string;
begin
  for mClass in ClassChain(AClass) do
  begin
    for mSymbol in TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext).Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, mClass) and
        SameText(ShortName(mSymbol.TypeName), 'ILogger') then
      begin
        Exit(mSymbol.Name);
      end;
    end;
  end;
  Result := '';
end;

// Steht das Wort an APosition allein in seiner Zeile (höchstens ein Semikolon dahinter)?
function TThreadExecuteScan.OnOwnLine(const APosition: TTextPosition; ALength: Integer): Boolean;
begin
  Result := (APosition.Line <= High(FLines)) and (Trim(Copy(FLines[APosition.Line], 1, APosition.Character)) = '') and
    MatchText(Trim(Copy(FLines[APosition.Line], APosition.Character + ALength + 1, MaxInt)), ['', ';']);
end;

// Korrektur: Rumpf in try … except, Meldung über das Protokoll der Klasse.
function TThreadExecuteScan.WrapFix(ABody: TSyntaxNode; const ALogger: string): TArray<TRuleFix>;
var
  mEdits: TArray<TRuleEdit>;
  mIndent, mStep, mText: string;
  mLine: Integer;
  mUsesEdit: TRuleEdit;
begin
  Result := nil;
  if (ALogger = '') or (ABody.EndPos.Line - ABody.StartPos.Line < 2) or
    not OnOwnLine(ABody.StartPos, Length('begin')) or
    not OnOwnLine(TTextPosition.Create(ABody.EndPos.Line, ABody.EndPos.Character - Length('end')), Length('end')) then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(FLines[ABody.StartPos.Line]);
  mStep := TRoutineBody.IndentUnit(FContext.Formatting);
  mText := mIndent + mStep + 'try' + FLineBreak;
  for mLine := ABody.StartPos.Line + 1 to ABody.EndPos.Line - 1 do
  begin
    if Trim(FLines[mLine]) = '' then
    begin
      mText := mText + FLines[mLine] + FLineBreak;
    end
    else
    begin
      mText := mText + mStep + FLines[mLine] + FLineBreak;
    end;
  end;
  mText := mText + mIndent + mStep + 'except' + FLineBreak +
    mIndent + mStep + mStep + 'on E: Exception do' + FLineBreak +
    mIndent + mStep + mStep + mStep + ALogger + '.Error(ClassName + ''.Execute: '' + E.Message);' + FLineBreak +
    mIndent + mStep + 'end;' + FLineBreak;
  mEdits := [TRuleEdit.Create(TTextRange.Create(ABody.StartPos.Line + 1, 0, ABody.EndPos.Line, 0), mText)];
  if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(FContext.Tree.Tokens), 'System.SysUtils', FContext.Namespaces) and
    TUsesClauses.AddUnit(FContext.Tree.Tokens, ABody.StartOffset, 'System.SysUtils', FLineBreak, mUsesEdit) then
  begin
    mEdits := [mUsesEdit] + mEdits;
  end;
  Result := [TRuleFix.Create(cTexts[TThreadExecuteText.WrapTry].Fmt([ALogger]), mEdits)];
end;

procedure TThreadExecuteScan.CheckExecute(ARoutine: TSyntaxNode; const AClass: string);
var
  mBody: TSyntaxNode;
begin
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    Exit;
  end;
  FUnknownCall := '';
  case GuardOf(ARoutine, AClass, 0) of
    TExecuteGuard.Open:
      if not EvaluatesFatalException(AClass) then
      begin
        FReport.Add(HeaderNameRange(FContext, ARoutine), cTexts[TThreadExecuteText.Silent].Text,
          TRuleConfidence.High, WrapFix(mBody, LoggerField(AClass)));
      end;
    TExecuteGuard.Unknown:
      // Ohne Rumpf der aufgerufenen Routine nur ein schwacher Befund.
      if (FUnknownCall <> '') and not EvaluatesFatalException(AClass) then
      begin
        FReport.Add(HeaderNameRange(FContext, ARoutine), cTexts[TThreadExecuteText.SilentCall].Fmt([FUnknownCall]),
          TRuleConfidence.Low);
      end;
  end;
end;

// Verschachtelte Klassen (TSampler.TWorker) stehen unter ihrem eigenen Namen mit der äußeren Klasse als Container.
function TThreadExecuteScan.IsThreadClass(const AOwner: string): Boolean;
var
  mNested: TSymbolLocation;
  mParent: string;
begin
  if FAncestry.DescendsFrom(AOwner, 'TThread') then
  begin
    Exit(True);
  end;
  Result := (Pos('.', AOwner) > 0) and FAncestry.FindNestedType(ClassPart(AOwner), MethodPart(AOwner), mNested) and
    (Length(mNested.Symbol.Ancestors) > 0);
  if Result then
  begin
    mParent := BareName(mNested.Symbol.Ancestors[0]);
    Result := SameText(mParent, 'TThread') or FAncestry.DescendsFrom(mParent, 'TThread');
  end;
end;

function TThreadExecuteScan.ThreadClassNames: TArray<string>;
var
  mRoutine: TSyntaxNode;
  mOwner: string;
begin
  Result := SharedThreadClasses(FContext);
  for mRoutine in FRoutines do
  begin
    mOwner := ClassPart(mRoutine.Name);
    if (mOwner <> '') and SameText(MethodPart(mRoutine.Name), 'Execute') and not InList(Result, mOwner) and
      IsThreadClass(mOwner) then
    begin
      Result := Result + [mOwner];
    end;
  end;
end;

procedure TThreadExecuteScan.Run;
var
  mClasses: TArray<string>;
  mRoutine: TSyntaxNode;
  mOwner: string;
begin
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  mClasses := ThreadClassNames;
  for mRoutine in FRoutines do
  begin
    mOwner := ClassPart(mRoutine.Name);
    if (mOwner <> '') and SameText(MethodPart(mRoutine.Name), 'Execute') and InList(mClasses, mOwner) then
    begin
      CheckExecute(mRoutine, mOwner);
    end;
  end;
end;

{ TThreadExecuteWithoutExceptRule }

function TThreadExecuteWithoutExceptRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-execute-without-except', TRuleSeverity.Warning,
    cTexts[TThreadExecuteText.Title].Text);
end;

procedure TThreadExecuteWithoutExceptRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TThreadExecuteScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Execute') then
  begin
    Exit;
  end;
  mScan := TThreadExecuteScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

// Rumpf (Block) einer Methode Execute?
function IsExecuteBody(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Block) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and SameText(MethodPart(ANode.Parent.Name), 'Execute');
end;

function IsThreadExecuteGuard(const AContext: TRuleContext; AHandler: TSyntaxNode): Boolean;
var
  mTry, mNode: TSyntaxNode;
  mScan: TThreadExecuteScan;
begin
  Result := False;
  if (AHandler = nil) or (AHandler.Parent = nil) or (AHandler.Parent.Parent = nil) then
  begin
    Exit;
  end;
  mTry := AHandler.Parent.Parent;
  mNode := mTry.Parent;
  // try … except direkt im Rumpf, auch innerhalb eines try … finally.
  while (mNode <> nil) and (mNode.Kind = TSyntaxKind.TryStatement) and
    (mNode.FindChild(TSyntaxKind.FinallyBlock) <> nil) do
  begin
    mNode := mNode.Parent;
  end;
  if (mTry.Kind <> TSyntaxKind.TryStatement) or not IsExecuteBody(mNode) or not CatchesAll(mTry) then
  begin
    Exit;
  end;
  mScan := TThreadExecuteScan.Create(AContext, nil);
  try
    Result := InList(mScan.ThreadClassNames, ClassPart(mNode.Parent.Name)) and
      (mScan.GuardOf(mNode.Parent, ClassPart(mNode.Parent.Name), 0) = TExecuteGuard.Guarded);
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.ThreadExecute', cTexts);

end.
