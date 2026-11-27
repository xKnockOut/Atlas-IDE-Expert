unit Rules.Builtin.Concurrency.ThreadExecute;

// Prüfregel thread-execute-without-except (Teil von Rules.Builtin.Concurrency, dort registriert): Eine
// Ausnahme, die TThread.Execute verlässt, beendet den Thread still; Delphi legt sie nur in FatalException ab.
// IsThreadExecuteGuard teilt die Erkennung mit catch-all-without-raise: Der äußere Handler von Execute fängt dort
// zu Recht, ohne erneut auszulösen.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Rules.Contract,
  Atlas.Common.Semantics.Ancestry,
  Atlas.Common.Documents.Contract;

type
  TThreadExecuteWithoutExceptRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Ist der Ausnahme-Handler AHandler (ExceptionHandler) Teil des äußeren try … except, der den ganzen Rumpf
/// von Execute einer Thread-Klasse umschließt?</summary>
function IsThreadExecuteGuard(const AContext: TRuleContext; AHandler: TSyntaxNode): Boolean;

/// <summary>Bearbeitungen, die den Rumpf ABody einer Methode in try … except legen und eine Ausnahme mit
/// ALogger.Error(ClassName + '.AMethod: ' + E.Message) melden; ergänzt System.SysUtils, wenn es fehlt. False ohne
/// ALogger, bei kurzen Rümpfen und wenn begin oder end nicht allein in ihrer Zeile stehen.</summary>
function TryExceptEdits(const AContext: TRuleContext; ABody: TSyntaxNode; const ALogger, AMethod: string;
  out AEdits: TArray<TTextEdit>): Boolean;

/// <summary>Erbt die Klasse AOwner der Unit (auch eingebettet, TSampler.TWorker) von TThread?</summary>
function IsThreadClassIn(AAncestry: TAncestry; const AOwner: string): Boolean;

type
  /// <summary>Grundlage der Durchsicht einer Unit nach Thread-Klassen: Kontext, Meldungen, Routinen und Vorfahren
  /// aus Unit und Index.</summary>
  TThreadUnitScan = class
  protected
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoutines: TArray<TSyntaxNode>;
    FAncestry: TAncestry;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.RoutineBody,
  Atlas.Common.Pascal.UsesEdits,
  Atlas.Common.Pascal.UsesClauses,
  Rules.Derived,
  Rules.Builtin.Concurrency.Syntax,
  Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Names,
  Atlas.Common.Findings.Contract;

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

/// <summary>Anweisungen vor dem Schutz, die selbst nichts auslösen: der Name des Threads für den Debugger.</summary>
function IsHarmless(AStatement: TSyntaxNode): Boolean;
var
  mCall: TMethodCall;
begin
  Result := TryMethodCall(AStatement, mCall) and SameText(mCall.Method, 'NameThreadForDebugging');
end;

/// <summary>Ruft der Ausdruck ANode etwas auf (Aufruf mit Klammern)? Ein Konstruktor ganz oben (T.Create(…)) zählt
/// mit AAllowCreate nicht.</summary>
function HasCall(ANode: TSyntaxNode; AAllowCreate: Boolean): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in TSyntaxNode.PreOrder(ANode) do
  begin
    if (mNode.Kind = TSyntaxKind.Call) and not (AAllowCreate and (mNode = ANode) and (mNode.ChildCount > 0) and
      (mNode[0].Kind = TSyntaxKind.MemberAccess) and SameText(mNode[0].Name, 'Create')) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Anweisung neben dem Schutz, die praktisch nichts auslöst: Zuweisung ohne Aufruf (L := 0,
/// T.OnProgress := DoProgress), Erzeugen eines Objekts vor seinem try … finally (Inf := TFoo.Create(…)) und ein
/// früher Ausstieg ohne Aufruf in der Bedingung (if FDiscard then Exit).</summary>
function IsQuiet(AStatement: TSyntaxNode): Boolean;
var
  mThen: TSyntaxNode;
begin
  case AStatement.Kind of
    TSyntaxKind.AssignStatement:
      Result := (AStatement.ChildCount = 2) and not HasCall(AStatement[0], False) and
        not HasCall(AStatement[1], True);
    TSyntaxKind.IfStatement:
      begin
        Result := False;
        if (AStatement.ChildCount = 2) and not HasCall(AStatement[0], False) then
        begin
          mThen := AStatement[1];
          if (mThen.Kind = TSyntaxKind.CallStatement) and (mThen.ChildCount = 1) then
          begin
            mThen := mThen[0];
          end;
          Result := (mThen.Kind = TSyntaxKind.Identifier) and SameText(mThen.Name, 'Exit');
        end;
      end;
  else
    Result := False;
  end;
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

// Steht das Wort an APosition allein in seiner Zeile (höchstens ein Semikolon dahinter)?
function OnOwnLine(const ALines: TArray<string>; const APosition: TTextPosition; ALength: Integer): Boolean;
begin
  Result := (APosition.Line <= High(ALines)) and (Trim(Copy(ALines[APosition.Line], 1, APosition.Character)) = '') and
    MatchText(Trim(Copy(ALines[APosition.Line], APosition.Character + ALength + 1, MaxInt)), ['', ';']);
end;

function TryExceptEdits(const AContext: TRuleContext; ABody: TSyntaxNode; const ALogger, AMethod: string;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mLines: TArray<string>;
  mLineBreak, mIndent, mStep, mText: string;
  mLine: Integer;
  mUsesEdit: TTextEdit;
begin
  AEdits := nil;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  Result := (ALogger <> '') and (ABody.EndPos.Line - ABody.StartPos.Line >= 2) and
    OnOwnLine(mLines, ABody.StartPos, Length('begin')) and
    OnOwnLine(mLines, TTextPosition.Create(ABody.EndPos.Line, ABody.EndPos.Character - Length('end')), Length('end'));
  if not Result then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(mLines[ABody.StartPos.Line]);
  mStep := TRoutineBody.IndentUnit(AContext.Formatting);
  mText := mIndent + mStep + 'try' + mLineBreak;
  for mLine := ABody.StartPos.Line + 1 to ABody.EndPos.Line - 1 do
  begin
    if Trim(mLines[mLine]) = '' then
    begin
      mText := mText + mLines[mLine] + mLineBreak;
    end
    else
    begin
      mText := mText + mStep + mLines[mLine] + mLineBreak;
    end;
  end;
  mText := mText + mIndent + mStep + 'except' + mLineBreak +
    mIndent + mStep + mStep + 'on E: Exception do' + mLineBreak +
    mIndent + mStep + mStep + mStep + ALogger + '.Error(ClassName + ''.' + AMethod + ': '' + E.Message);' +
    mLineBreak + mIndent + mStep + 'end;' + mLineBreak;
  AEdits := [TTextEdit.Create(TTextRange.Create(ABody.StartPos.Line + 1, 0, ABody.EndPos.Line, 0), mText)];
  if not TPascalUses.IsUsed(TPascalUses.UsedUnits(AContext.Tree.Tokens), 'System.SysUtils', AContext.Namespaces) and
    TPascalUsesEdits.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, 'System.SysUtils', mLineBreak, mUsesEdit) then
  begin
    AEdits := [mUsesEdit] + AEdits;
  end;
end;

// Korrektur: Rumpf in try … except, Meldung über das Protokoll der Klasse.
function WrapFix(const AContext: TRuleContext; ABody: TSyntaxNode; const ALogger: string): TArray<TRuleFix>;
var
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  if TryExceptEdits(AContext, ABody, ALogger, 'Execute', mEdits) then
  begin
    Result := [TRuleFix.Create(cTexts[TThreadExecuteText.WrapTry].Fmt([ALogger]), mEdits)];
  end;
end;

// Verschachtelte Klassen (TSampler.TWorker) stehen unter ihrem eigenen Namen mit der äußeren Klasse als Container.
function IsThreadClassIn(AAncestry: TAncestry; const AOwner: string): Boolean;
var
  mNested: TSymbolLocation;
  mParent: string;
begin
  if AAncestry.DescendsFrom(AOwner, 'TThread') then
  begin
    Exit(True);
  end;
  Result := (Pos('.', AOwner) > 0) and AAncestry.FindNestedType(ClassPart(AOwner), MethodPart(AOwner), mNested) and
    (Length(mNested.Symbol.Ancestors) > 0);
  if Result then
  begin
    mParent := TTextNames.BareTypeName(mNested.Symbol.Ancestors[0]);
    Result := SameText(mParent, 'TThread') or AAncestry.DescendsFrom(mParent, 'TThread');
  end;
end;

type
  /// <summary>Ein Lauf von TThreadExecuteWithoutExceptRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TThreadExecuteScan = class(TThreadUnitScan)
  private
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
    procedure CheckExecute(ARoutine: TSyntaxNode; const AClass: string);
  public
    /// <summary>Thread-Klassen der Unit (aus der Unit und dem Index).</summary>
    function ThreadClassNames: TArray<string>;
    procedure Run;
  end;

{ TThreadUnitScan }

constructor TThreadUnitScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRoutines := TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
end;

destructor TThreadUnitScan.Destroy;
begin
  FAncestry.Free;
  FRoutines := nil;
  inherited;
end;

{ TThreadExecuteScan }

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
  mFirst, mIndex: Integer;
  mStatement, mCallee: TSyntaxNode;
  mName: string;
  mInherited: Boolean;
begin
  Result := TExecuteGuard.Open;
  // Genau eine Anweisung trägt die Arbeit; die übrigen lösen praktisch nichts aus.
  mFirst := -1;
  for mIndex := 0 to High(AStatements) do
  begin
    if IsHarmless(AStatements[mIndex]) or IsQuiet(AStatements[mIndex]) then
    begin
      Continue;
    end;
    if mFirst >= 0 then
    begin
      Exit;
    end;
    mFirst := mIndex;
  end;
  if mFirst < 0 then
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
    if (MatchText(mOwner, mChain) and not SameText(MethodPart(mRoutine.Name), 'Execute')) or NamesType(mRoutine, AClass) then
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
            MatchText(ShortName(SourceText(FContext.Text, ANode[1])), mReaders) then
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
          TRuleConfidence.High, WrapFix(FContext, mBody, LoggerField(AClass)));
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

function TThreadExecuteScan.ThreadClassNames: TArray<string>;
var
  mRoutine: TSyntaxNode;
  mOwner: string;
begin
  Result := SharedThreadClasses(FContext);
  for mRoutine in FRoutines do
  begin
    mOwner := ClassPart(mRoutine.Name);
    if (mOwner <> '') and SameText(MethodPart(mRoutine.Name), 'Execute') and not MatchText(mOwner, Result) and
      IsThreadClassIn(FAncestry, mOwner) then
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
  mClasses := ThreadClassNames;
  for mRoutine in FRoutines do
  begin
    mOwner := ClassPart(mRoutine.Name);
    if (mOwner <> '') and SameText(MethodPart(mRoutine.Name), 'Execute') and MatchText(mOwner, mClasses) then
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
    Result := MatchText(ClassPart(mNode.Parent.Name), mScan.ThreadClassNames) and
      (mScan.GuardOf(mNode.Parent, ClassPart(mNode.Parent.Name), 0) = TExecuteGuard.Guarded);
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Rules.Builtin.Concurrency.ThreadExecute', cTexts);

end.
