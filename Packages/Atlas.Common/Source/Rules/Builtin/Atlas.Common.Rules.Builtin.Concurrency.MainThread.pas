unit Atlas.Common.Rules.Builtin.Concurrency.MainThread;

// Nebenläufigkeitsregeln für den Hauptthread (Teil von Atlas.Common.Rules.Builtin.Concurrency, dort registriert):
// processmessages-in-loop, queue-nil-in-package, blocking-call-in-main-thread.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

type
  TProcessMessagesInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TBlockingCallInMainThreadRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Position des Timeouts unter den Argumenten von ACall (ab 0); -1 ohne Timeout.</summary>
    class function TimeoutArgument(const ACall: string): Integer; static;
  end;

  TQueueNilInPackageRule = class(TInterfacedObject, IRule)
  public const
    cDefaultWrapper = 'TAtlasMainThread.Queue';
    cDefaultOkMarker = 'mainthread-ok';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Aufruf, der AWrapper für AMethod (Queue oder ForceQueue) ersetzt: bei ForceQueue wird aus
    /// …Queue …ForceQueue. Enthält AWrapper eine Klammer, steht er so vor den übrigen Argumenten.</summary>
    class function WrapperCall(const AWrapper, AMethod: string): string; static;
  end;


implementation

uses
  System.JSON,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConcurrencyMainThreadText = (ProcessMessagesTitle, ReentryLoop, ReentryHandler, QueueTitle, ReplaceWith,
    ReplaceWithEnd, AfterUnload, ThisPackage, BlockingTitle, InClickHandler, InEventHandler, WaitForSync, Blocks,
    SleepLoop, ProcessMessagesAdvice, BlockingCallAdvice);

const
  cTexts: array[TConcurrencyMainThreadText] of TAtlasText = (
    (De: 'Application.ProcessMessages in Schleifen'; En: 'Application.ProcessMessages in loops'),
    (De: 'ProcessMessages in der Schleife erlaubt Wiedereintritt (zweiter Klick, Formular schließen).';
     En: 'ProcessMessages in the loop allows reentry (second click, closing the form).'),
    (De: 'ProcessMessages im Ereignis-Handler erlaubt Wiedereintritt (zweiter Klick, Formular schließen).';
     En: 'ProcessMessages in the event handler allows reentry (second click, closing the form).'),
    (De: 'TThread.Queue(nil, …) in einem Package'; En: 'TThread.Queue(nil, …) in a package'),
    (De: 'Durch '; En: 'Replace with '),
    (De: '…) ersetzen'; En: '…)'),
    (De: '%s(nil, …) in %s: der Eintrag kann nach dem Entladen des Packages laufen.';
     En: '%s(nil, …) in %s: the entry can run after the package is unloaded.'),
    (De: 'diesem Package'; En: 'this package'),
    (De: 'Blockierender Aufruf im Hauptthread'; En: 'Blocking call in the main thread'),
    (De: 'im Click-Handler'; En: 'in the click handler'),
    (De: 'im Ereignis-Handler '; En: 'in the event handler '),
    (De: 'WaitFor %s blockiert den Hauptthread; ruft %s Synchronize auf, hängt das Programm.';
     En: 'WaitFor %s blocks the main thread; if %s calls Synchronize, the program hangs.'),
    (De: '%s %s blockiert den Hauptthread; die Oberfläche friert ein.';
     En: '%s %s blocks the main thread; the user interface freezes.'),
    (De: 'Warteschleife mit Sleep %s blockiert den Hauptthread; die Oberfläche friert ein.';
     En: 'Waiting loop with Sleep %s blocks the main thread; the user interface freezes.'),
    (De: ' Besser die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren.';
     En: ' Better move the work into a thread or TTask or disable the trigger until the end.'),
    (De: ' Besser die Arbeit mit TTask.Run auslagern und das Ergebnis über TThread.Queue melden.';
     En: ' Better move the work to TTask.Run and report the result via TThread.Queue.'));

{$SCOPEDENUMS OFF}

/// <summary>Methode mit einem Parameter Sender: OnClick, OnTimer und Verwandte.</summary>
function IsEventHandler(ARoutine: TSyntaxNode): Boolean;
var
  mHeader, mParams: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  Result := False;
  if Pos('.', ARoutine.Name) = 0 then
  begin
    Exit;
  end;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    if mParams[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      for mName in SplitString(mParams[mIndex].Name, ',') do
      begin
        if SameText(Trim(mName), 'Sender') then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
end;

{ TProcessMessagesInLoopRule }


function TProcessMessagesInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('processmessages-in-loop', TRuleSeverity.Hint,
    cTexts[TConcurrencyMainThreadText.ProcessMessagesTitle].Text);
end;

procedure TProcessMessagesInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAllowIn: TArray<string>;

  function Allowed(const ARoutineName: string): Boolean;
  var
    mName: string;
  begin
    for mName in mAllowIn do
    begin
      if SameText(mName, ARoutineName) or SameText(mName, MethodPart(ARoutineName)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function IsProcessMessages(ANode: TSyntaxNode): Boolean;
  var
    mCall: TMethodCall;
  begin
    Result := TryMethodCall(ANode, mCall) and SameText(mCall.Method, 'ProcessMessages') and
      (mCall.Receiver <> nil) and SameText(MethodPart(NodeText(AContext.Text, mCall.Receiver)), 'application');
  end;

  // Meldet ProcessMessages an ANode in einer Schleife (ALoops > 0) oder direkt im Ereignis-Handler.
  procedure ReportProcessMessages(ANode: TSyntaxNode; ALoops: Integer; AHandler: Boolean);
  begin
    if ALoops > 0 then
    begin
      AReport.Add(NodeRange(ANode), cTexts[TConcurrencyMainThreadText.ReentryLoop].Text +
        cTexts[TConcurrencyMainThreadText.ProcessMessagesAdvice].Text, TRuleConfidence.Medium);
    end
    else if AHandler then
    begin
      AReport.Add(NodeRange(ANode), cTexts[TConcurrencyMainThreadText.ReentryHandler].Text +
        cTexts[TConcurrencyMainThreadText.ProcessMessagesAdvice].Text, TRuleConfidence.Medium);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode; ALoops: Integer; AHandler, AAllowed: Boolean);
  var
    mPending: TStack<TSyntaxNode>;
    mLoopStack: TStack<Integer>;
    mHandlers, mAlloweds: TStack<Boolean>;
    mNode: TSyntaxNode;
    mIndex, mLoops: Integer;
    mHandler, mIsAllowed: Boolean;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ALoops, AHandler und AAllowed je Knoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mLoopStack := TStack<Integer>.Create;
    mHandlers := TStack<Boolean>.Create;
    mAlloweds := TStack<Boolean>.Create;
    try
      mPending.Push(ANode);
      mLoopStack.Push(ALoops);
      mHandlers.Push(AHandler);
      mAlloweds.Push(AAllowed);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mLoops := mLoopStack.Pop;
        mHandler := mHandlers.Pop;
        mIsAllowed := mAlloweds.Pop;
        // Anonyme Methoden laufen später oder in einem Thread (dort meldet thread-vcl-access).
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mHandler := IsEventHandler(mNode);
          mIsAllowed := Allowed(mNode.Name);
          mLoops := 0;
        end
        else if (mNode.Kind = TSyntaxKind.CallStatement) and not mIsAllowed and IsProcessMessages(mNode) then
        begin
          ReportProcessMessages(mNode, mLoops, mHandler);
          Continue;
        end;
        if mNode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
          TSyntaxKind.RepeatStatement] then
        begin
          Inc(mLoops);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mLoopStack.Push(mLoops);
          mHandlers.Push(mHandler);
          mAlloweds.Push(mIsAllowed);
        end;
      end;
    finally
      mAlloweds.Free;
      mHandlers.Free;
      mLoopStack.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mAllowIn := TRuleOptions.Strings(AContext.Options, 'allowIn', nil);
  Visit(AContext.Tree.Root, 0, False, False);
end;

{ TQueueNilInPackageRule }

function TQueueNilInPackageRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('queue-nil-in-package', TRuleSeverity.Warning,
    cTexts[TConcurrencyMainThreadText.QueueTitle].Text);
end;

class function TQueueNilInPackageRule.WrapperCall(const AWrapper, AMethod: string): string;
var
  mName, mRest: string;
  mParen: Integer;
begin
  mParen := Pos('(', AWrapper);
  if mParen > 0 then
  begin
    mName := TrimRight(Copy(AWrapper, 1, mParen - 1));
    mRest := Copy(AWrapper, mParen, MaxInt);
  end
  else
  begin
    mName := AWrapper;
    mRest := '(';
  end;
  if SameText(AMethod, 'ForceQueue') and EndsText('Queue', mName) and not EndsText('ForceQueue', mName) then
  begin
    mName := Copy(mName, 1, Length(mName) - Length('Queue')) + 'ForceQueue';
  end;
  Result := mName + mRest;
end;

procedure TQueueNilInPackageRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mWrapper, mOkMarker, mWhere: string;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  // Steht in der Zeile ALine ein Kommentar mit der Ausnahme?
  function MarkedOk(ALine: Integer): Boolean;
  var
    mItem: TPascalToken;
  begin
    for mItem in mTokens do
    begin
      if (mItem.Kind = TPascalTokenKind.Comment) and (mItem.StartPos.Line <= ALine) and (mItem.EndPos.Line >= ALine) and
        ContainsText(mItem.Text, mOkMarker) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Anzahl der Argumente ab der öffnenden Klammer AOpen; -1 ohne schließende Klammer.
  function ArgumentCount(AOpen: Integer): Integer;
  var
    mPosition, mDepth: Integer;
  begin
    Result := 1;
    mDepth := 0;
    for mPosition := AOpen to High(mCode) do
    begin
      if Token(mPosition).IsSymbol('(') or Token(mPosition).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          Exit;
        end;
      end
      // Kommas in anonymen Methoden stehen in eigenen Klammern; begin … end zählt nicht.
      else if (mDepth = 1) and Token(mPosition).IsSymbol(',') then
      begin
        Inc(Result);
      end;
    end;
    Result := -1;
  end;

  // Steht an AStart TThread.Queue(nil, bzw. TThread.ForceQueue(nil,?
  function IsQueueNilAt(AStart: Integer): Boolean;
  begin
    Result := (AStart + 5 <= High(mCode)) and SameText(Token(AStart).Text, 'TThread') and
      Token(AStart + 1).IsSymbol('.') and Token(AStart + 3).IsSymbol('(');
    Result := Result and Token(AStart + 4).IsKeyword('nil') and Token(AStart + 5).IsSymbol(',') and
      MatchText(Token(AStart + 2).Text, ['Queue', 'ForceQueue']);
  end;

  procedure CheckAt(AStart: Integer);
  var
    mMethod: string;
    mComma: Integer;
    mRange, mReplace: TTextRange;
    mFixes: TArray<TRuleFix>;
  begin
    // TThread . Queue|ForceQueue ( nil ,
    if not IsQueueNilAt(AStart) or MarkedOk(Token(AStart).StartPos.Line) then
    begin
      Exit;
    end;
    mMethod := Token(AStart + 2).Text;
    mComma := AStart + 5;
    mRange := TTextRange.Create(Token(AStart).StartPos, Token(AStart + 4).EndPos);
    mFixes := nil;
    // Nur mit genau zwei Argumenten: die Verzögerung von ForceQueue kennt der Wrapper nicht.
    if ArgumentCount(AStart + 3) = 2 then
    begin
      mReplace := TTextRange.Create(Token(AStart).StartPos, Token(mComma).EndPos);
      // Steht das nächste Argument in derselben Zeile, fällt der Leerraum davor mit weg.
      if (mComma < High(mCode)) and (Token(mComma + 1).StartPos.Line = Token(mComma).EndPos.Line) then
      begin
        mReplace.EndPos := Token(mComma + 1).StartPos;
      end;
      mFixes := [TRuleFix.Create(cTexts[TConcurrencyMainThreadText.ReplaceWith].Text + WrapperCall(mWrapper, mMethod) +
        cTexts[TConcurrencyMainThreadText.ReplaceWithEnd].Text,
        [TTextEdit.Create(mReplace, WrapperCall(mWrapper, mMethod))])];
    end;
    AReport.Add(mRange, cTexts[TConcurrencyMainThreadText.AfterUnload].Fmt([mMethod, mWhere]), mFixes);
  end;

var
  mKind: TRuleApplicationKind;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Text = '') then
  begin
    Exit;
  end;
  mKind := AContext.Application;
  // Ohne Projekt: die .dpk selbst.
  if mKind = TRuleApplicationKind.Unknown then
  begin
    mKind := TWritelnInGuiAppRule.ApplicationKind('', AContext.Text);
  end;
  if mKind <> TRuleApplicationKind.Package then
  begin
    Exit;
  end;
  mWhere := cTexts[TConcurrencyMainThreadText.ThisPackage].Text;
  if AContext.ProjectName <> '' then
  begin
    mWhere := AContext.ProjectName + '.bpl';
  end;
  mWrapper := TRuleOptions.Text(AContext.Options, 'wrapper', cDefaultWrapper);
  mOkMarker := TRuleOptions.Text(AContext.Options, 'okMarker', cDefaultOkMarker);
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  for mIndex := 0 to High(mCode) do
  begin
    if mTokens[mCode[mIndex]].Kind = TPascalTokenKind.Identifier then
    begin
      CheckAt(mIndex);
    end;
  end;
end;

{ TBlockingCallInMainThreadRule }

const
  cFormBaseClasses: array[0..3] of string = ('TCustomForm', 'TForm', 'TCustomFrame', 'TFrame');
  cWindowsWaitCalls: array[0..2] of string = ('Sleep', 'WaitForSingleObject', 'WaitForMultipleObjects');

function TBlockingCallInMainThreadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('blocking-call-in-main-thread', TRuleSeverity.Warning,
    cTexts[TConcurrencyMainThreadText.BlockingTitle].Text);
end;

class function TBlockingCallInMainThreadRule.TimeoutArgument(const ACall: string): Integer;
begin
  // Position des Timeouts in den Argumenten (ab 0); -1: Aufruf ohne Timeout, blockiert immer.
  if SameText(ACall, 'Sleep') or SameText(ACall, 'WaitFor') or SameText(ACall, 'Wait') then
  begin
    Result := 0;
  end
  else if SameText(ACall, 'WaitForSingleObject') then
  begin
    Result := 1;
  end
  else if SameText(ACall, 'WaitForMultipleObjects') then
  begin
    Result := 3;
  end
  else
  begin
    Result := -1;
  end;
end;

procedure TBlockingCallInMainThreadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCalls: TArray<string>;
  mMaxSleep: Integer;
  mAncestry: TAncestry;
  mThreads: TArray<string>;

  // Methode eines Formulars oder Frames bzw. Ereignis-Handler außerhalb eines Threads.
  function InMainThread(ARoutine: TSyntaxNode): Boolean;
  var
    mOwner, mBase: string;
  begin
    mOwner := ClassPart(ARoutine.Name);
    if (mOwner = '') or InList(mThreads, mOwner) or mAncestry.DescendsFrom(mOwner, 'TThread') then
    begin
      Exit(False);
    end;
    for mBase in cFormBaseClasses do
    begin
      if mAncestry.DescendsFrom(mOwner, mBase) then
      begin
        Exit(True);
      end;
    end;
    Result := IsEventHandler(ARoutine);
  end;

  // Timeout in Millisekunden: Zahl, INFINITE = MaxInt; -1 = unbekannt.
  function Milliseconds(ANode: TSyntaxNode): Integer;
  begin
    if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'INFINITE') then
    begin
      Exit(MaxInt);
    end;
    if (ANode.Kind <> TSyntaxKind.Literal) or not TryStrToInt(ANode.Name, Result) then
    begin
      Result := -1;
    end;
  end;

  function MentionsProcessMessages(ANode: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(mNode.Name, 'ProcessMessages') then
        begin
          Exit(True);
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

  function Where(ARoutine: TSyntaxNode): string;
  var
    mMethod: string;
  begin
    mMethod := MethodPart(ARoutine.Name);
    if EndsText('Click', mMethod) then
    begin
      Result := cTexts[TConcurrencyMainThreadText.InClickHandler].Text;
    end
    else if IsEventHandler(ARoutine) then
    begin
      Result := cTexts[TConcurrencyMainThreadText.InEventHandler].Text + mMethod;
    end
    else
    begin
      Result := 'in ' + mMethod;
    end;
  end;

  // Ist ACallee ein geprüfter blockierender Aufruf? Sleep und die Wait-Funktionen der Windows-API ohne Empfänger
  // (oder Winapi.Windows.…), WaitFor und Wait mit Empfänger.
  function IsBlockingCall(ACallee: TSyntaxNode): Boolean;
  begin
    if InList(cWindowsWaitCalls, ACallee.Name) then
    begin
      Result := (ACallee.Kind <> TSyntaxKind.MemberAccess) or MatchText(SourceText(AContext.Text, ACallee[0]),
        ['Windows', 'Winapi.Windows']);
    end
    else
    begin
      Result := not MatchText(ACallee.Name, ['WaitFor', 'Wait']) or (ACallee.Kind = TSyntaxKind.MemberAccess);
    end;
    Result := Result and InList(mCalls, ACallee.Name);
  end;

  // Timeout des Aufrufs AName mit den Argumenten AArgs (MaxInt ohne Timeout-Argument); False bei Sleep ohne
  // Argument.
  function TimeoutOf(const AName: string; AArgs: TSyntaxNode; out ATimeout: Integer): Boolean;
  var
    mPosition: Integer;
  begin
    mPosition := TimeoutArgument(AName);
    ATimeout := MaxInt;
    Result := True;
    if (mPosition >= 0) and (AArgs <> nil) and (AArgs.ChildCount > mPosition + 1) then
    begin
      ATimeout := Milliseconds(AArgs[mPosition + 1]);
    end
    else
    begin
      Result := not SameText(AName, 'Sleep');
    end;
  end;

  // Meldung für einen langen oder unbegrenzten blockierenden Aufruf; WaitFor auf einem Thread warnt vor Synchronize.
  procedure ReportBlocking(ACallee, AArgs, ARoutine: TSyntaxNode);
  var
    mText, mReceiver: string;
  begin
    mReceiver := '';
    if ACallee.Kind = TSyntaxKind.MemberAccess then
    begin
      mReceiver := VariableName(ACallee[0]);
    end;
    if SameText(ACallee.Name, 'WaitFor') and ((AArgs = nil) or (AArgs.ChildCount = 1)) and (mReceiver <> '') then
    begin
      AReport.Add(NameRange(ACallee), cTexts[TConcurrencyMainThreadText.WaitForSync].Fmt([Where(ARoutine), mReceiver]) +
        cTexts[TConcurrencyMainThreadText.BlockingCallAdvice].Text, TRuleConfidence.Medium);
      Exit;
    end;
    if AArgs <> nil then
    begin
      mText := SourceText(AContext.Text, AArgs);
    end
    else
    begin
      mText := SourceText(AContext.Text, ACallee);
    end;
    AReport.Add(NameRange(ACallee), cTexts[TConcurrencyMainThreadText.Blocks].Fmt(
      [mText, Where(ARoutine)]) + cTexts[TConcurrencyMainThreadText.BlockingCallAdvice].Text, TRuleConfidence.Medium);
  end;

  // ACallee: Identifier oder MemberAccess mit dem Namen; AArgs: Aufruf mit Argumenten oder nil.
  procedure CheckCall(ACallee, AArgs: TSyntaxNode; ARoutine, ALoop: TSyntaxNode);
  var
    mTimeout: Integer;
  begin
    if not IsBlockingCall(ACallee) or not TimeoutOf(ACallee.Name, AArgs, mTimeout) then
    begin
      Exit;
    end;
    if (mTimeout < 0) or (mTimeout >= mMaxSleep) then
    begin
      ReportBlocking(ACallee, AArgs, ARoutine);
    end
    // Kurzes Sleep nur in einer Warteschleife ohne ProcessMessages.
    else if SameText(ACallee.Name, 'Sleep') and (ALoop <> nil) and not MentionsProcessMessages(ALoop) then
    begin
      AReport.Add(NameRange(ACallee), cTexts[TConcurrencyMainThreadText.SleepLoop].Fmt([Where(ARoutine)]) +
        cTexts[TConcurrencyMainThreadText.BlockingCallAdvice].Text, TRuleConfidence.Medium);
    end;
  end;

  // Routine und Schleife für die Kinder von ANode: eine Methode setzt beide neu (eingebettete Routinen gehören zur
  // äußeren Methode), eine Schleife setzt ALoop.
  procedure Enter(ANode: TSyntaxNode; var ARoutine, ALoop: TSyntaxNode);
  begin
    if (ANode.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', ANode.Name) > 0) then
    begin
      ARoutine := nil;
      if InMainThread(ANode) then
      begin
        ARoutine := ANode;
      end;
      ALoop := nil;
    end
    else if ANode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
      TSyntaxKind.ForInStatement] then
    begin
      ALoop := ANode;
    end;
  end;

  // Prüft Aufrufe an ANode in der Hauptthread-Methode ARoutine.
  procedure CheckNode(ANode, ARoutine, ALoop: TSyntaxNode);
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and
      (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    begin
      CheckCall(ANode[0], ANode, ARoutine, ALoop);
    end
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) then
    begin
      CheckCall(ANode[0], nil, ARoutine, ALoop);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode; ARoutine, ALoop: TSyntaxNode);
  var
    mPending, mRoutineStack, mLoopStack: TStack<TSyntaxNode>;
    mNode, mRoutine, mLoop: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ARoutine und ALoop je Knoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mRoutineStack := TStack<TSyntaxNode>.Create;
    mLoopStack := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      mRoutineStack.Push(ARoutine);
      mLoopStack.Push(ALoop);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mRoutine := mRoutineStack.Pop;
        mLoop := mLoopStack.Pop;
        // Anonyme Methoden laufen oft in einem Thread oder später.
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        Enter(mNode, mRoutine, mLoop);
        if mRoutine <> nil then
        begin
          CheckNode(mNode, mRoutine, mLoop);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mRoutineStack.Push(mRoutine);
          mLoopStack.Push(mLoop);
        end;
      end;
    finally
      mLoopStack.Free;
      mRoutineStack.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCalls := TRuleOptions.Strings(AContext.Options, 'calls', ['Sleep', 'WaitFor', 'WaitForSingleObject',
    'WaitForMultipleObjects', 'Wait']);
  mMaxSleep := TRuleOptions.Int(AContext.Options, 'maxSleepMs', 50);
  mThreads := ThreadClasses(AContext.Tree.Root);
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    mAncestry.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.MainThread', cTexts);

end.
