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
    DefaultWrapper = 'TAtlasMainThread.Queue';
    DefaultOkMarker = 'mainthread-ok';
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
  Atlas.Text.Lines,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Pascal.DeclaredTypes,
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
  Header, Params: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  Result := False;
  if Pos('.', ARoutine.Name) = 0 then
  begin
    Exit;
  end;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
  begin
    Exit;
  end;
  Params := Header.FindChild(TSyntaxKind.Parameters);
  if Params = nil then
  begin
    Exit;
  end;
  for Index := 0 to Params.ChildCount - 1 do
  begin
    if Params[Index].Kind = TSyntaxKind.Parameter then
    begin
      for Name in SplitString(Params[Index].Name, ',') do
      begin
        if SameText(Trim(Name), 'Sender') then
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
  AllowIn: TArray<string>;

  function Allowed(const ARoutineName: string): Boolean;
  var
    Name: string;
  begin
    for Name in AllowIn do
    begin
      if SameText(Name, ARoutineName) or SameText(Name, MethodPart(ARoutineName)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function IsProcessMessages(ANode: TSyntaxNode): Boolean;
  var
    Call: TMethodCall;
  begin
    Result := TryMethodCall(ANode, Call) and SameText(Call.Method, 'ProcessMessages') and
      (Call.Receiver <> nil) and SameText(MethodPart(NodeText(AContext.Text, Call.Receiver)), 'application');
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
    Pending: TStack<TSyntaxNode>;
    LoopStack: TStack<Integer>;
    Handlers, Alloweds: TStack<Boolean>;
    Node: TSyntaxNode;
    Index, Loops: Integer;
    Handler, IsAllowed: Boolean;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ALoops, AHandler und AAllowed je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    LoopStack := TStack<Integer>.Create;
    Handlers := TStack<Boolean>.Create;
    Alloweds := TStack<Boolean>.Create;
    try
      Pending.Push(ANode);
      LoopStack.Push(ALoops);
      Handlers.Push(AHandler);
      Alloweds.Push(AAllowed);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Loops := LoopStack.Pop;
        Handler := Handlers.Pop;
        IsAllowed := Alloweds.Pop;
        // Anonyme Methoden laufen später oder in einem Thread (dort meldet thread-vcl-access).
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Handler := IsEventHandler(Node);
          IsAllowed := Allowed(Node.Name);
          Loops := 0;
        end
        else if (Node.Kind = TSyntaxKind.CallStatement) and not IsAllowed and IsProcessMessages(Node) then
        begin
          ReportProcessMessages(Node, Loops, Handler);
          Continue;
        end;
        if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
          TSyntaxKind.RepeatStatement] then
        begin
          Inc(Loops);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          LoopStack.Push(Loops);
          Handlers.Push(Handler);
          Alloweds.Push(IsAllowed);
        end;
      end;
    finally
      Alloweds.Free;
      Handlers.Free;
      LoopStack.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  AllowIn := TRuleOptions.Strings(AContext.Options, 'allowIn', nil);
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
  Name, Rest: string;
  Paren: Integer;
begin
  Paren := Pos('(', AWrapper);
  if Paren > 0 then
  begin
    Name := TrimRight(Copy(AWrapper, 1, Paren - 1));
    Rest := Copy(AWrapper, Paren, MaxInt);
  end
  else
  begin
    Name := AWrapper;
    Rest := '(';
  end;
  if SameText(AMethod, 'ForceQueue') and EndsText('Queue', Name) and not EndsText('ForceQueue', Name) then
  begin
    Name := Copy(Name, 1, Length(Name) - Length('Queue')) + 'ForceQueue';
  end;
  Result := Name + Rest;
end;

procedure TQueueNilInPackageRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Wrapper, OkMarker, Where: string;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  // Steht in der Zeile ALine ein Kommentar mit der Ausnahme?
  function MarkedOk(ALine: Integer): Boolean;
  var
    Item: TPascalToken;
  begin
    for Item in Tokens do
    begin
      if (Item.Kind = TPascalTokenKind.Comment) and (Item.StartPos.Line <= ALine) and (Item.EndPos.Line >= ALine) and
        ContainsText(Item.Text, OkMarker) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Anzahl der Argumente ab der öffnenden Klammer AOpen; -1 ohne schließende Klammer.
  function ArgumentCount(AOpen: Integer): Integer;
  var
    Position, Depth: Integer;
  begin
    Result := 1;
    Depth := 0;
    for Position := AOpen to High(Code) do
    begin
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Exit;
        end;
      end
      // Kommas in anonymen Methoden stehen in eigenen Klammern; begin … end zählt nicht.
      else if (Depth = 1) and Token(Position).IsSymbol(',') then
      begin
        Inc(Result);
      end;
    end;
    Result := -1;
  end;

  // Steht an AStart TThread.Queue(nil, bzw. TThread.ForceQueue(nil,?
  function IsQueueNilAt(AStart: Integer): Boolean;
  begin
    Result := (AStart + 5 <= High(Code)) and SameText(Token(AStart).Text, 'TThread') and
      Token(AStart + 1).IsSymbol('.') and Token(AStart + 3).IsSymbol('(');
    Result := Result and Token(AStart + 4).IsKeyword('nil') and Token(AStart + 5).IsSymbol(',') and
      MatchText(Token(AStart + 2).Text, ['Queue', 'ForceQueue']);
  end;

  procedure CheckAt(AStart: Integer);
  var
    Method: string;
    Comma: Integer;
    Range, Replace: TTextRange;
    Fixes: TArray<TRuleFix>;
  begin
    // TThread . Queue|ForceQueue ( nil ,
    if not IsQueueNilAt(AStart) or MarkedOk(Token(AStart).StartPos.Line) then
    begin
      Exit;
    end;
    Method := Token(AStart + 2).Text;
    Comma := AStart + 5;
    Range := TTextRange.Create(Token(AStart).StartPos, Token(AStart + 4).EndPos);
    Fixes := nil;
    // Nur mit genau zwei Argumenten: die Verzögerung von ForceQueue kennt der Wrapper nicht.
    if ArgumentCount(AStart + 3) = 2 then
    begin
      Replace := TTextRange.Create(Token(AStart).StartPos, Token(Comma).EndPos);
      // Steht das nächste Argument in derselben Zeile, fällt der Leerraum davor mit weg.
      if (Comma < High(Code)) and (Token(Comma + 1).StartPos.Line = Token(Comma).EndPos.Line) then
      begin
        Replace.EndPos := Token(Comma + 1).StartPos;
      end;
      Fixes := [TRuleFix.Create(cTexts[TConcurrencyMainThreadText.ReplaceWith].Text + WrapperCall(Wrapper, Method) +
        cTexts[TConcurrencyMainThreadText.ReplaceWithEnd].Text,
        [TTextEdit.Create(Replace, WrapperCall(Wrapper, Method))])];
    end;
    AReport.Add(Range, cTexts[TConcurrencyMainThreadText.AfterUnload].Fmt([Method, Where]), Fixes);
  end;

var
  Kind: TRuleApplicationKind;
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Text = '') then
  begin
    Exit;
  end;
  Kind := AContext.Application;
  // Ohne Projekt: die .dpk selbst.
  if Kind = TRuleApplicationKind.Unknown then
  begin
    Kind := TWritelnInGuiAppRule.ApplicationKind('', AContext.Text);
  end;
  if Kind <> TRuleApplicationKind.Package then
  begin
    Exit;
  end;
  Where := cTexts[TConcurrencyMainThreadText.ThisPackage].Text;
  if AContext.ProjectName <> '' then
  begin
    Where := AContext.ProjectName + '.bpl';
  end;
  Wrapper := TRuleOptions.Text(AContext.Options, 'wrapper', DefaultWrapper);
  OkMarker := TRuleOptions.Text(AContext.Options, 'okMarker', DefaultOkMarker);
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Code := Code + [Index];
    end;
  end;
  for Index := 0 to High(Code) do
  begin
    if Tokens[Code[Index]].Kind = TPascalTokenKind.Identifier then
    begin
      CheckAt(Index);
    end;
  end;
end;

{ TBlockingCallInMainThreadRule }

const
  FormBaseClasses: array[0..3] of string = ('TCustomForm', 'TForm', 'TCustomFrame', 'TFrame');
  WindowsWaitCalls: array[0..2] of string = ('Sleep', 'WaitForSingleObject', 'WaitForMultipleObjects');

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
  Calls: TArray<string>;
  MaxSleep: Integer;
  Ancestry: TAncestry;
  Threads: TArray<string>;

  // Methode eines Formulars oder Frames bzw. Ereignis-Handler außerhalb eines Threads.
  function InMainThread(ARoutine: TSyntaxNode): Boolean;
  var
    Owner, Base: string;
  begin
    Owner := ClassPart(ARoutine.Name);
    if (Owner = '') or InList(Threads, Owner) or Ancestry.DescendsFrom(Owner, 'TThread') then
    begin
      Exit(False);
    end;
    for Base in FormBaseClasses do
    begin
      if Ancestry.DescendsFrom(Owner, Base) then
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
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(Node.Name, 'ProcessMessages') then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function Where(ARoutine: TSyntaxNode): string;
  var
    Method: string;
  begin
    Method := MethodPart(ARoutine.Name);
    if EndsText('Click', Method) then
    begin
      Result := cTexts[TConcurrencyMainThreadText.InClickHandler].Text;
    end
    else if IsEventHandler(ARoutine) then
    begin
      Result := cTexts[TConcurrencyMainThreadText.InEventHandler].Text + Method;
    end
    else
    begin
      Result := 'in ' + Method;
    end;
  end;

  // Ist ACallee ein geprüfter blockierender Aufruf? Sleep und die Wait-Funktionen der Windows-API ohne Empfänger
  // (oder Winapi.Windows.…), WaitFor und Wait mit Empfänger.
  function IsBlockingCall(ACallee: TSyntaxNode): Boolean;
  begin
    if InList(WindowsWaitCalls, ACallee.Name) then
    begin
      Result := (ACallee.Kind <> TSyntaxKind.MemberAccess) or MatchText(SourceText(AContext.Text, ACallee[0]),
        ['Windows', 'Winapi.Windows']);
    end
    else
    begin
      Result := not MatchText(ACallee.Name, ['WaitFor', 'Wait']) or (ACallee.Kind = TSyntaxKind.MemberAccess);
    end;
    Result := Result and InList(Calls, ACallee.Name);
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
    if (mTimeout < 0) or (mTimeout >= MaxSleep) then
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
    Pending, RoutineStack, LoopStack: TStack<TSyntaxNode>;
    Node, Routine, Loop: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ARoutine und ALoop je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    RoutineStack := TStack<TSyntaxNode>.Create;
    LoopStack := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      RoutineStack.Push(ARoutine);
      LoopStack.Push(ALoop);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := RoutineStack.Pop;
        Loop := LoopStack.Pop;
        // Anonyme Methoden laufen oft in einem Thread oder später.
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        Enter(Node, Routine, Loop);
        if Routine <> nil then
        begin
          CheckNode(Node, Routine, Loop);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          RoutineStack.Push(Routine);
          LoopStack.Push(Loop);
        end;
      end;
    finally
      LoopStack.Free;
      RoutineStack.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Calls := TRuleOptions.Strings(AContext.Options, 'calls', ['Sleep', 'WaitFor', 'WaitForSingleObject',
    'WaitForMultipleObjects', 'Wait']);
  MaxSleep := TRuleOptions.Int(AContext.Options, 'maxSleepMs', 50);
  Threads := ThreadClasses(AContext.Tree.Root);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    Ancestry.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.MainThread', cTexts);

end.
