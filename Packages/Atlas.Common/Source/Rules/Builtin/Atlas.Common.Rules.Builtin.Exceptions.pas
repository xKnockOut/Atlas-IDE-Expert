unit Atlas.Common.Rules.Builtin.Exceptions;

// Exception-Regeln (#277, abgetrennt aus #57):
//   generic-exception-raised    raise Exception.Create(…) statt einer eigenen Klasse
//   catch-all-without-raise     on E: Exception do ohne raise; nur für Bibliothekscode,
//                               deshalb Standard aus und über Profile/Pfadregeln einzuschalten (#146)
//   exception-freed             Exception-Objekt nach raise bzw. im Handler zusätzlich freigegeben
//   exception-in-destructor     raise in einem Destruktor, das kein except im Destruktor abfängt (#927)
//   except-handler-order        on-Handler, der nie erreicht wird, weil ein früherer die Klasse schon fängt (#957)
//   reraise-exception-object    raise E im Handler statt raise; (#958)
//   reraise-outside-handler     raise; ohne Argument außerhalb eines except-Blocks (#985, wie E2145,
//                               Gruppe Compiler vorab). Routinen und anonyme Methoden beginnen neu; in einer
//                               anonymen Methode innerhalb eines except bleibt die Regel still, ebenso in
//                               Routinen, in denen der Parser einen Fehler meldet.
//   inherited-constructor-after-try  try im Konstruktor vor dem geerbten Konstruktor, Self noch nicht
//                               initialisiert (wie H2505, #1027); ergänzt missing-inherited. Zweige von
//                               {$IFDEF}, die sich ausschließen, zählen nicht gegeneinander
// Der leere except-Block bleibt bei empty-except (#56).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TGenericExceptionRaisedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCatchAllWithoutRaiseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionInDestructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptHandlerOrderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorfahr einer bekannten RTL-, VCL- oder FireDAC-Exception; leer, wenn unbekannt.</summary>
    class function KnownParent(const AName: string): string; static;
  end;

  TReraiseExceptionObjectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TReraiseOutsideHandlerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedConstructorAfterTryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Exception-Regeln.</summary>
procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance;

type
  TTokens = TArray<TPascalToken>;

  /// <summary>Exception-Handler "on [Name:] Typ do Anweisung".</summary>
  THandler = record
    OnToken: Integer;
    DoToken: Integer;
    /// <summary>Name der Handler-Variablen; '' bei "on Typ do".</summary>
    Name: string;
    TypeName: string;
    /// <summary>Erstes und letztes Token der Anweisung hinter do.</summary>
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('asm');
end;

/// <summary>Letztes Token der Anweisung ab AFirst: bis zum passenden end bzw. vor ; oder end.</summary>
function StatementEnd(const ATokens: TTokens; AFirst: Integer): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  Index := AFirst;
  Result := AFirst;
  while Index <= High(ATokens) do
  begin
    if OpensBlock(ATokens[Index]) then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsKeyword('end') then
    begin
      if Depth = 0 then
      begin
        Exit;
      end;
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit(Index);
      end;
    end
    else if (Depth = 0) and (ATokens[Index].IsSymbol(';') or ATokens[Index].IsKeyword('else')) then
    begin
      Exit;
    end;
    if not IsTrivia(ATokens[Index]) then
    begin
      Result := Index;
    end;
    Inc(Index);
  end;
end;

/// <summary>Liest ab ANext den Typ eines Handlers (auch qualifiziert: System.SysUtils.Exception) bis zum do;
/// False, wenn dort kein Typ mit do steht.</summary>
function ReadHandlerType(const ATokens: TTokens; ANext: Integer; var AHandler: THandler): Boolean;
begin
  Result := (ANext <= High(ATokens)) and (ATokens[ANext].Kind = TPascalTokenKind.Identifier);
  if not Result then
  begin
    Exit;
  end;
  AHandler.TypeName := ATokens[ANext].Text;
  AHandler.DoToken := NextCode(ATokens, ANext + 1);
  while (AHandler.DoToken < High(ATokens)) and ATokens[AHandler.DoToken].IsSymbol('.') do
  begin
    AHandler.TypeName := ATokens[NextCode(ATokens, AHandler.DoToken + 1)].Text;
    AHandler.DoToken := NextCode(ATokens, NextCode(ATokens, AHandler.DoToken + 1) + 1);
  end;
  Result := (AHandler.DoToken <= High(ATokens)) and ATokens[AHandler.DoToken].IsKeyword('do');
end;

/// <summary>Liest den Handler "on [Name :] Typ do Anweisung" ab dem Token AIndex (on); False, wenn dort keiner
/// steht.</summary>
function ReadHandler(const ATokens: TTokens; AIndex: Integer; out AHandler: THandler): Boolean;
var
  mNext, mColon: Integer;
begin
  AHandler := Default(THandler);
  AHandler.OnToken := AIndex;
  mNext := NextCode(ATokens, AIndex + 1);
  mColon := NextCode(ATokens, mNext + 1);
  Result := mColon <= High(ATokens);
  if Result and ATokens[mColon].IsSymbol(':') then
  begin
    AHandler.Name := ATokens[mNext].Text;
    mNext := NextCode(ATokens, mColon + 1);
  end;
  Result := Result and ReadHandlerType(ATokens, mNext, AHandler);
  if Result then
  begin
    AHandler.First := NextCode(ATokens, AHandler.DoToken + 1);
    Result := AHandler.First <= High(ATokens);
  end;
  if Result then
  begin
    AHandler.Last := StatementEnd(ATokens, AHandler.First);
  end;
end;

function Handlers(const ATokens: TTokens): TArray<THandler>;
var
  mIndex: Integer;
  mHandler: THandler;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    // "on" ist kein reserviertes Wort; im except-Teil folgt Name : Typ do oder Typ do.
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, 'on') and
      ReadHandler(ATokens, mIndex, mHandler) then
    begin
      Result := Result + [mHandler];
    end;
  end;
end;

/// <summary>Gibt Token AIndex den Namen AName frei: AName.Free, AName.Destroy, FreeAndNil(AName)?</summary>
function IsFreeOf(const ATokens: TTokens; AIndex: Integer; const AName: string): Boolean;
var
  Dot, Method, Open, Arg: Integer;
begin
  Result := False;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  if SameText(ATokens[AIndex].Text, AName) then
  begin
    Dot := NextCode(ATokens, AIndex + 1);
    Method := NextCode(ATokens, Dot + 1);
    Result := (Method <= High(ATokens)) and ATokens[Dot].IsSymbol('.') and
      MatchText(ATokens[Method].Text, ['Free', 'Destroy', 'DisposeOf']) and
      ((AIndex = 0) or not ATokens[PreviousCode(ATokens, AIndex)].IsSymbol('.'));
  end
  else if SameText(ATokens[AIndex].Text, 'FreeAndNil') then
  begin
    Open := NextCode(ATokens, AIndex + 1);
    Arg := NextCode(ATokens, Open + 1);
    Result := (Arg < High(ATokens)) and ATokens[Open].IsSymbol('(') and SameText(ATokens[Arg].Text, AName) and
      ATokens[NextCode(ATokens, Arg + 1)].IsSymbol(')');
  end;
end;

{ TGenericExceptionRaisedRule }

function TGenericExceptionRaisedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('generic-exception-raised', TRuleSeverity.Hint,
    'raise Exception statt einer eigenen Exception-Klasse');
end;

procedure TGenericExceptionRaisedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Name, Dot, Ctor: Integer;
  Caught: TArray<THandler>;

  // Die raise-Anweisung, die bei AOffset beginnt; nil, wenn keine.
  function RaiseAt(AOffset: Integer): TSyntaxNode;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mChild: Integer;
  begin
    Result := nil;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while (mPending.Count > 0) and (Result = nil) do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.RaiseStatement) and (mNode.StartOffset = AOffset) then
        begin
          Result := mNode;
        end
        else if (mNode.StartOffset <= AOffset) and (mNode.EndOffset >= AOffset) then
        begin
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Fängt der except-Teil AExcept jede Exception: on Exception, on TObject oder gar kein on?
  function CatchesAll(AExcept: TSyntaxNode): Boolean;
  var
    mHandler: THandler;
    mAnyOn: Boolean;
  begin
    Result := False;
    mAnyOn := False;
    for mHandler in Caught do
    begin
      if (Tokens[mHandler.OnToken].Offset >= AExcept.StartOffset) and
        (Tokens[mHandler.OnToken].Offset < AExcept.EndOffset) then
      begin
        mAnyOn := True;
        Result := Result or MatchText(mHandler.TypeName, ['Exception', 'TObject']);
      end;
    end;
    // except ohne on fängt alles.
    Result := Result or not mAnyOn;
  end;

  // raise direkt im try-Teil, dessen except alles fängt: Die Exception verlässt die Routine nie; oft nur, um einen
  // Stack für das Protokoll zu bekommen (#1109).
  function CaughtRightThere(AOffset: Integer): Boolean;
  var
    mRaise, mExcept: TSyntaxNode;
  begin
    mRaise := RaiseAt(AOffset);
    Result := (mRaise <> nil) and (mRaise.Parent <> nil) and (mRaise.Parent.Kind = TSyntaxKind.TryStatement);
    if Result then
    begin
      mExcept := mRaise.Parent.FindChild(TSyntaxKind.ExceptBlock);
      Result := (mExcept <> nil) and CatchesAll(mExcept);
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not Tokens[Index].IsKeyword('raise') then
    begin
      Continue;
    end;
    Name := NextCode(Tokens, Index + 1);
    // raise SysUtils.Exception.Create bzw. System.SysUtils.Exception.Create
    while (Name + 2 <= High(Tokens)) and MatchText(Tokens[Name].Text, ['System', 'SysUtils']) and
      Tokens[NextCode(Tokens, Name + 1)].IsSymbol('.') do
    begin
      Name := NextCode(Tokens, NextCode(Tokens, Name + 1) + 1);
    end;
    Dot := NextCode(Tokens, Name + 1);
    Ctor := NextCode(Tokens, Dot + 1);
    if (Ctor > High(Tokens)) or not SameText(Tokens[Name].Text, 'Exception') or not Tokens[Dot].IsSymbol('.') or
      not StartsText('Create', Tokens[Ctor].Text) then
    begin
      Continue;
    end;
    if Caught = nil then
    begin
      Caught := Handlers(Tokens);
    end;
    if CaughtRightThere(Tokens[Index].Offset) then
    begin
      Continue;
    end;
    AReport.Add(RangeOf(Tokens, Index, Ctor), 'raise Exception lässt sich nicht gezielt abfangen; eine eigene ' +
      'Klasse (z. B. EKundeNichtGefunden = class(Exception)) oder eine passende der RTL verwenden',
      TRuleConfidence.High);
  end;
end;

{ TCatchAllWithoutRaiseRule }

function TCatchAllWithoutRaiseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('catch-all-without-raise', TRuleSeverity.Warning,
    'on E: Exception do ohne raise', True);
end;

procedure TCatchAllWithoutRaiseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Handler: THandler;
  Index: Integer;
  Raises: Boolean;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Handler in Handlers(Tokens) do
  begin
    if not MatchText(Handler.TypeName, ['Exception', 'TObject']) then
    begin
      Continue;
    end;
    Raises := False;
    for Index := Handler.First to Handler.Last do
    begin
      if Tokens[Index].IsKeyword('raise') then
      begin
        Raises := True;
      end;
    end;
    if not Raises then
    begin
      AReport.Add(RangeOf(Tokens, Handler.OnToken, Handler.DoToken), 'Bibliothekscode fängt jede Exception ab, ' +
        'ohne sie weiterzuwerfen; der Aufrufer erfährt nichts vom Fehler. Gezielt abfangen oder mit raise ' +
        'weiterwerfen', TRuleConfidence.Medium);
    end;
  end;
end;

{ TExceptionFreedRule }

function TExceptionFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-freed', TRuleSeverity.Error,
    'Exception-Objekt nach raise zusätzlich freigegeben');
end;

/// <summary>Erstes und letztes Token der Routine, in der Token AIndex liegt; False ohne.</summary>
function RoutineSpan(ATree: TSyntaxTree; const ATokens: TTokens; AIndex: Integer;
  out AFirst, ALast: Integer): Boolean;
var
  Best: TSyntaxNode;
  Index, Offset: Integer;
begin
  Best := nil;
  Offset := ATokens[AIndex].Offset;
  // Iterativ (Bericht M1); die letzte passende Routine in Baumreihenfolge ist die innerste.
  if ATree.Root <> nil then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.StartOffset <= Offset) and (ANode.EndOffset > Offset) then
        begin
          Best := ANode;
        end;
        Result := True;
      end);
  end;
  Result := Best <> nil;
  if not Result then
  begin
    Exit;
  end;
  AFirst := AIndex;
  ALast := AIndex;
  // Nur die Token von Best, binär angesprungen statt die ganze Datei (#1342).
  Index := TSyntaxTree.FirstTokenOf(ATokens, Best.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < Best.EndOffset) do
  begin
    if Index < AFirst then
    begin
      AFirst := Index;
    end;
    if Index > ALast then
    begin
      ALast := Index;
    end;
    Inc(Index);
  end;
end;

procedure TExceptionFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Done: TArray<Integer>;

  function Reported(AToken: Integer): Boolean;
  var
    Item: Integer;
  begin
    for Item in Done do
    begin
      if Item = AToken then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Im Handler: on E: Exception do … E.Free; die RTL gibt E nach dem Handler selbst frei.
  procedure CheckHandlers;
  var
    mHandler: THandler;
    mIndex: Integer;
  begin
    for mHandler in Handlers(Tokens) do
    begin
      if mHandler.Name = '' then
      begin
        Continue;
      end;
      for mIndex := mHandler.First to mHandler.Last do
      begin
        if IsFreeOf(Tokens, mIndex, mHandler.Name) then
        begin
          Done := Done + [mIndex];
          AReport.Add(RangeOf(Tokens, mIndex, mIndex), Format('%s gehört nach dem Handler der RTL und wird dort ' +
            'freigegeben; eigenes Freigeben führt zur doppelten Freigabe', [mHandler.Name]), TRuleConfidence.High);
        end;
      end;
    end;
  end;

  // Token des Namens X bei "raise X;" bzw. "raise X end" für das Token AIndex; -1 sonst.
  function RaisedName(AIndex: Integer): Integer;
  var
    mStop: Integer;
  begin
    Result := -1;
    if not Tokens[AIndex].IsKeyword('raise') then
    begin
      Exit;
    end;
    Result := NextCode(Tokens, AIndex + 1);
    mStop := NextCode(Tokens, Result + 1);
    if (mStop > High(Tokens)) or (Tokens[Result].Kind <> TPascalTokenKind.Identifier) or
      not (Tokens[mStop].IsSymbol(';') or Tokens[mStop].IsKeyword('end')) then
    begin
      Result := -1;
    end;
  end;

  // raise X; … X.Free in derselben Routine: Nach raise gehört das Objekt der RTL.
  procedure CheckRaised(AIndex, AName: Integer);
  var
    mInner, mFirst, mLast: Integer;
  begin
    if not RoutineSpan(AContext.Tree, Tokens, AIndex, mFirst, mLast) then
    begin
      Exit;
    end;
    for mInner := mFirst to mLast do
    begin
      if IsFreeOf(Tokens, mInner, Tokens[AName].Text) and not Reported(mInner) then
      begin
        Done := Done + [mInner];
        AReport.Add(RangeOf(Tokens, mInner, mInner), Format('%s wird mit raise ausgelöst und gehört dann der ' +
          'RTL; zusätzliches Freigeben führt zur doppelten Freigabe', [Tokens[AName].Text]), TRuleConfidence.High);
        Break;
      end;
    end;
  end;

var
  mIndex, mName: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Done := nil;
  CheckHandlers;
  for mIndex := 0 to High(Tokens) do
  begin
    mName := RaisedName(mIndex);
    if mName >= 0 then
    begin
      CheckRaised(mIndex, mName);
    end;
  end;
end;

{ TExceptionInDestructorRule }

function TExceptionInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-in-destructor', TRuleSeverity.Warning, 'raise im Destruktor');
end;

procedure TExceptionInDestructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  RoutineName: string;
  // Offset des ersten inherited im Destruktor; MaxInt ohne.
  InheritedOffset: Integer;

  function RoutineText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function IsDestructor(ARoutine: TSyntaxNode): Boolean;
  var
    Head: string;
  begin
    Head := RoutineText(ARoutine);
    if StartsText('class', Head) then
    begin
      Head := TrimLeft(Copy(Head, Length('class') + 1, MaxInt));
    end;
    Result := StartsText('destructor', Head) and ((Length(Head) = Length('destructor')) or
      CharInSet(Head[Length('destructor') + 1], [' ', #9, #10, #13]));
  end;

  // Erstes inherited im Destruktor, ohne eingebettete Routinen und anonyme Methoden.
  procedure FindInherited(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.InheritedExpr) and (Node.StartOffset < InheritedOffset) then
        begin
          InheritedOffset := Node.StartOffset;
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

  procedure ReportRaise(ANode: TSyntaxNode);
  var
    mMessage: string;
  begin
    if ANode.StartOffset < InheritedOffset then
    begin
      mMessage := Format('raise im Destruktor: inherited %s läuft nicht mehr, Felder bleiben liegen.',
        [RoutineName]);
    end
    else
    begin
      mMessage := Format('raise im Destruktor: die Ausnahme verlässt %s, der Aufrufer erwartet eine ' +
        'Freigabe ohne Ausnahme.', [RoutineName]);
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
      ANode.StartPos.Character + Length('raise'))), mMessage, TRuleConfidence.High);
  end;

  // Active: eine Ausnahme an dieser Stelle verlässt den Destruktor.
  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode, mChild: TSyntaxNode;
    mActive, mCaught: Boolean;
    mPending: TStack<TSyntaxNode>;
    mPendingActive: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    mPendingActive := TStack<Boolean>.Create;
    try
      mPending.Push(ARoot);
      mPendingActive.Push(True);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mActive := mPendingActive.Pop;
        if (mNode.Kind = TSyntaxKind.RaiseStatement) and mActive then
        begin
          ReportRaise(mNode);
        end;
        if mNode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl, TSyntaxKind.RaiseStatement] then
        begin
          Continue;
        end;
        // Im try-Teil fängt ein eigenes except die Ausnahme ab; except- und finally-Teil nicht.
        mCaught := (mNode.Kind = TSyntaxKind.TryStatement) and (mNode.FindChild(TSyntaxKind.ExceptBlock) <> nil);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mChild := mNode[mIndex];
          mPending.Push(mChild);
          mPendingActive.Push(mActive and (not mCaught or
            (mChild.Kind in [TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock])));
        end;
      end;
    finally
      mPendingActive.Free;
      mPending.Free;
    end;
  end;

  procedure Search(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node, Body: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.RoutineDecl) and IsDestructor(Node) then
        begin
          RoutineName := Node.Name;
          if LastDelimiter('.', RoutineName) > 0 then
          begin
            RoutineName := Copy(RoutineName, LastDelimiter('.', RoutineName) + 1, MaxInt);
          end;
          Body := Node.FindChild(TSyntaxKind.Block);
          if Body <> nil then
          begin
            InheritedOffset := MaxInt;
            FindInherited(Body);
            Visit(Body);
          end;
        end;
        // Auch eingebettete Routinen und Klassen in Routinen.
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    Search(AContext.Tree.Root);
  end;
end;

{ TExceptHandlerOrderRule }

const
  // Vorfahren bekannter RTL-, VCL- und FireDAC-Exceptions (Klasse=Vorfahr), wenn der Index sie nicht kennt.
  KnownExceptionParents: array[0..39] of string = (
    'EAbort=Exception', 'EConvertError=Exception', 'EInOutError=Exception', 'EOSError=Exception',
    'EInvalidCast=Exception', 'EInvalidPointer=EHeapException', 'EOutOfMemory=EHeapException',
    'EHeapException=Exception', 'EExternal=Exception', 'EAccessViolation=EExternal', 'EIntError=EExternal',
    'EDivByZero=EIntError', 'ERangeError=EIntError', 'EIntOverflow=EIntError', 'EMathError=EExternal',
    'EInvalidOp=EMathError', 'EZeroDivide=EMathError', 'EOverflow=EMathError', 'EUnderflow=EMathError',
    'EArgumentException=Exception', 'EArgumentOutOfRangeException=EArgumentException',
    'EArgumentNilException=EArgumentException', 'ENotImplemented=Exception', 'ENotSupportedException=Exception',
    'EListError=Exception', 'EStringListError=EListError', 'EStreamError=Exception',
    'EFileStreamError=EStreamError', 'EFOpenError=EFileStreamError', 'EFCreateError=EFileStreamError',
    'EFilerError=EStreamError', 'EReadError=EFilerError', 'EWriteError=EFilerError',
    'EVariantError=Exception', 'EDatabaseError=Exception', 'EFDException=EDatabaseError',
    'EFDDBEngineException=EFDException', 'EEncodingError=Exception', 'EJSONException=Exception',
    'EComponentError=Exception');

function TExceptHandlerOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('except-handler-order', TRuleSeverity.Warning,
    'Allgemeiner Exception-Handler vor speziellem');
end;

class function TExceptHandlerOrderRule.KnownParent(const AName: string): string;
var
  Entry: string;
begin
  for Entry in KnownExceptionParents do
  begin
    if SameText(Copy(Entry, 1, Pos('=', Entry) - 1), AName) then
    begin
      Exit(Copy(Entry, Pos('=', Entry) + 1, MaxInt));
    end;
  end;
  Result := '';
end;

procedure TExceptHandlerOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Lines: TArray<string>;
  LineBreak: string;

  function TypeOf(AHandler: TSyntaxNode): string;
  var
    Reference: TSyntaxNode;
  begin
    Result := '';
    Reference := AHandler.FindChild(TSyntaxKind.TypeReference);
    if Reference <> nil then
    begin
      Result := Copy(Reference.Name, LastDelimiter('.', Reference.Name) + 1, MaxInt);
    end;
  end;

  // Fängt ein Handler für AGeneral auch ASpecial? Über die Datei, den Index und die Tabelle bekannter Klassen.
  function Covers(const AGeneral, ASpecial: string): Boolean;
  var
    Current, Parent: string;
    Steps: Integer;
  begin
    if SameText(AGeneral, 'TObject') then
    begin
      Exit(True);
    end;
    // Alles, was als Exception ausgelöst wird, erbt in der Praxis von Exception.
    if SameText(AGeneral, 'Exception') and not SameText(ASpecial, 'TObject') then
    begin
      Exit(True);
    end;
    Current := ASpecial;
    for Steps := 1 to 16 do
    begin
      Parent := Ancestry.ParentOf(Current);
      if (Parent = '') or SameText(Parent, 'TObject') then
      begin
        Parent := KnownParent(Current);
      end;
      if Parent = '' then
      begin
        Exit(False);
      end;
      if SameText(Parent, AGeneral) then
      begin
        Exit(True);
      end;
      Current := Parent;
    end;
    Result := False;
  end;

  // Steht der Handler allein auf seinen Zeilen (davor Einrückung, danach höchstens ";")?
  function OwnLines(AHandler: TSyntaxNode): Boolean;
  var
    Rest: string;
  begin
    Rest := Trim(Copy(Lines[AHandler.EndPos.Line], AHandler.EndPos.Character + 1, MaxInt));
    Result := (Trim(Copy(Lines[AHandler.StartPos.Line], 1, AHandler.StartPos.Character)) = '') and
      ((Rest = '') or (Rest = ';')) and (AHandler.EndPos.Line < High(Lines));
  end;

  // Korrektur: den speziellen Handler vor den allgemeinen verschieben.
  function MoveFix(AGeneral, ASpecial: TSyntaxNode): TArray<TRuleFix>;
  var
    Line: Integer;
    Text: string;
  begin
    Result := nil;
    if not OwnLines(AGeneral) or not OwnLines(ASpecial) or (AGeneral.EndPos.Line >= ASpecial.StartPos.Line) then
    begin
      Exit;
    end;
    Text := '';
    for Line := ASpecial.StartPos.Line to ASpecial.EndPos.Line do
    begin
      Text := Text + Lines[Line] + LineBreak;
    end;
    // Der letzte Handler darf ohne Semikolon stehen; vor einem anderen braucht er eines.
    if Trim(Copy(Lines[ASpecial.EndPos.Line], ASpecial.EndPos.Character + 1, MaxInt)) = '' then
    begin
      Text := Copy(Text, 1, Length(Text) - Length(LineBreak)) + ';' + LineBreak;
    end;
    Result := [TRuleFix.Create(Format('on %s vor on %s verschieben', [TypeOf(ASpecial), TypeOf(AGeneral)]), [
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(AGeneral.StartPos.Line, 0),
        TTextPosition.Create(AGeneral.StartPos.Line, 0)), Text),
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ASpecial.StartPos.Line, 0),
        TTextPosition.Create(ASpecial.EndPos.Line + 1, 0)), '')])];
  end;

  // Meldet den Handler AHandlers[AIndex], wenn ein früherer seinen Typ schon fängt.
  procedure CheckHandler(const AHandlers: TArray<TSyntaxNode>; AIndex: Integer);
  var
    mEarlier: Integer;
    mGeneral, mSpecial: string;
    mRange: TTextRange;
    mReference: TSyntaxNode;
  begin
    mSpecial := TypeOf(AHandlers[AIndex]);
    if mSpecial = '' then
    begin
      Exit;
    end;
    for mEarlier := 0 to AIndex - 1 do
    begin
      mGeneral := TypeOf(AHandlers[mEarlier]);
      if mGeneral = '' then
      begin
        Continue;
      end;
      mReference := AHandlers[AIndex].FindChild(TSyntaxKind.TypeReference);
      mRange := TTextRange.Create(mReference.StartPos, mReference.EndPos);
      if SameText(mGeneral, mSpecial) then
      begin
        AReport.Add(mRange, Format('Nie erreicht: %s wird schon in Zeile %d behandelt.',
          [mSpecial, AHandlers[mEarlier].StartPos.Line + 1]));
        Exit;
      end;
      if Covers(mGeneral, mSpecial) then
      begin
        AReport.Add(mRange, Format('Nie erreicht: %s ist ein Nachfahr von %s, das schon in Zeile %d behandelt ' +
          'wird.', [mSpecial, mGeneral, AHandlers[mEarlier].StartPos.Line + 1]),
          MoveFix(AHandlers[mEarlier], AHandlers[AIndex]));
        Exit;
      end;
    end;
  end;

  procedure CheckBlock(ABlock: TSyntaxNode);
  var
    mHandlers: TArray<TSyntaxNode>;
    mIndex: Integer;
  begin
    mHandlers := nil;
    for mIndex := 0 to ABlock.ChildCount - 1 do
    begin
      if ABlock[mIndex].Kind = TSyntaxKind.ExceptionHandler then
      begin
        mHandlers := mHandlers + [ABlock[mIndex]];
      end;
    end;
    for mIndex := 1 to High(mHandlers) do
    begin
      CheckHandler(mHandlers, mIndex);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.ExceptBlock then
        begin
          CheckBlock(Node);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'except') then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

{ TReraiseExceptionObjectRule }

function TReraiseExceptionObjectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('reraise-exception-object', TRuleSeverity.Warning,
    'raise E statt raise im Handler');
end;

procedure TReraiseExceptionObjectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Done: TArray<Integer>;

  // Übernimmt der Handler das Objekt selbst (AcquireExceptionObject) oder weist er der Variablen neu zu?
  function OwnsObject(const AHandler: THandler): Boolean;
  var
    Position: Integer;
  begin
    for Position := AHandler.First to AHandler.Last do
    begin
      if SameText(Tokens[Position].Text, 'AcquireExceptionObject') or
        (SameText(Tokens[Position].Text, AHandler.Name) and
        Tokens[NextCode(Tokens, Position + 1)].IsSymbol(':=')) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Liegt das raise in einer anonymen Methode innerhalb des Handlers?
  function InAnonymousMethod(const AHandler: THandler; ARaise: Integer): Boolean;
  var
    Position: Integer;
  begin
    for Position := AHandler.First to ARaise do
    begin
      if Tokens[Position].IsKeyword('procedure') or Tokens[Position].IsKeyword('function') then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function Reported(AToken: Integer): Boolean;
  var
    Item: Integer;
  begin
    for Item in Done do
    begin
      if Item = AToken then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Meldet "raise E" beim Token AIndex im Handler AHandler.
  procedure CheckRaise(const AHandler: THandler; AIndex: Integer);
  var
    mName, mStop: Integer;
    mFixes: TArray<TRuleFix>;
  begin
    mName := NextCode(Tokens, AIndex + 1);
    mStop := NextCode(Tokens, mName + 1);
    if (mStop > High(Tokens)) or not SameText(Tokens[mName].Text, AHandler.Name) or
      InAnonymousMethod(AHandler, AIndex) then
    begin
      Exit;
    end;
    // raise E; raise E end; raise E else; raise E at Adresse (ohne Korrektur).
    mFixes := nil;
    if Tokens[mStop].IsSymbol(';') or Tokens[mStop].IsKeyword('end') or Tokens[mStop].IsKeyword('else') then
    begin
      mFixes := [TRuleFix.Create(Format('raise %s; durch raise; ersetzen', [AHandler.Name]),
        [TRuleEdit.Create(RangeOf(Tokens, AIndex, mName), 'raise')])];
    end
    else if not SameText(Tokens[mStop].Text, 'at') then
    begin
      Exit;
    end;
    Done := Done + [AIndex];
    AReport.Add(RangeOf(Tokens, AIndex, mName), Format('raise %s löst das Objekt neu aus: Absprungstelle ' +
      '(ExceptAddr) und Aufrufliste zeigen danach auf diesen Handler statt auf den ursprünglichen Fehler; ' +
      'raise; wirft die Exception unverändert weiter.', [AHandler.Name]), TRuleConfidence.High, mFixes);
  end;

var
  mHandler: THandler;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'raise') then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Done := nil;
  for mHandler in Handlers(Tokens) do
  begin
    if (mHandler.Name = '') or OwnsObject(mHandler) then
    begin
      Continue;
    end;
    for mIndex := mHandler.First to mHandler.Last do
    begin
      if Tokens[mIndex].IsKeyword('raise') and not Reported(mIndex) then
      begin
        CheckRaise(mHandler, mIndex);
      end;
    end;
  end;
end;

{ TReraiseOutsideHandlerRule }

function TReraiseOutsideHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('reraise-outside-handler', TRuleSeverity.Error,
    'raise ohne Argument außerhalb eines except-Blocks');
end;

procedure TReraiseOutsideHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  // Hat der Parser im Bereich von AScope einen Fehler gemeldet (nil: irgendwo)?
  function Broken(AScope: TSyntaxNode): Boolean;
  var
    Diagnostic: TSyntaxDiagnostic;
  begin
    for Diagnostic in AContext.Tree.Diagnostics do
    begin
      if (AScope = nil) or ((Diagnostic.StartPos.Line >= AScope.StartPos.Line) and
        (Diagnostic.StartPos.Line <= AScope.EndPos.Line)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Passt Bereich AScope und Zustand an den Knoten ANode an und meldet ein raise ohne Argument außerhalb von
  // except.
  procedure Enter(ANode: TSyntaxNode; var AScope: TSyntaxNode; var AInExcept, AUnknown: Boolean);
  begin
    case ANode.Kind of
      TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection,
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
        begin
          AScope := ANode;
          AInExcept := False;
          AUnknown := False;
        end;
      TSyntaxKind.AnonymousMethod:
        begin
          AScope := ANode;
          AUnknown := AUnknown or AInExcept;
          AInExcept := False;
        end;
      TSyntaxKind.ExceptBlock:
        AInExcept := True;
      TSyntaxKind.RaiseStatement:
        if (ANode.ChildCount = 0) and not AInExcept and not AUnknown and not Broken(AScope) then
        begin
          AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
            ANode.StartPos.Character + Length('raise'))),
            'raise ohne Argument ist nur in einem except-Block erlaubt (wie E2145).', TRuleConfidence.High);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // InExcept: ein except der Routine umschließt die Stelle; Unknown: anonyme Methode in einem except.
  procedure Visit(ARoot: TSyntaxNode);
  const
    InExceptFlag = 1;
    UnknownFlag = 2;
  var
    Index, Flags: Integer;
    Node, Scope: TSyntaxNode;
    InExcept, Unknown: Boolean;
    Pending, PendingScope: TStack<TSyntaxNode>;
    PendingFlags: TStack<Integer>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    PendingScope := TStack<TSyntaxNode>.Create;
    PendingFlags := TStack<Integer>.Create;
    try
      Pending.Push(ARoot);
      PendingScope.Push(nil);
      PendingFlags.Push(0);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Scope := PendingScope.Pop;
        Flags := PendingFlags.Pop;
        InExcept := (Flags and InExceptFlag) <> 0;
        Unknown := (Flags and UnknownFlag) <> 0;
        Enter(Node, Scope, InExcept, Unknown);
        Flags := 0;
        if InExcept then
        begin
          Flags := Flags or InExceptFlag;
        end;
        if Unknown then
        begin
          Flags := Flags or UnknownFlag;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingScope.Push(Scope);
          PendingFlags.Push(Flags);
        end;
      end;
    finally
      PendingFlags.Free;
      PendingScope.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'raise') then
  begin
    Exit;
  end;
  Visit(AContext.Tree.Root);
end;

{ TInheritedConstructorAfterTryRule }

function TInheritedConstructorAfterTryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-constructor-after-try', TRuleSeverity.Hint,
    'Geerbter Konstruktor erst nach try');
end;

/// <summary>Erstes Token ab AOffset (die Tokens sind nach Offset sortiert).</summary>
function TokenAtOffset(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Upper, Middle: Integer;
begin
  Result := 0;
  Upper := Length(ATokens);
  while Result < Upper do
  begin
    Middle := (Result + Upper) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Result := Middle + 1;
    end
    else
    begin
      Upper := Middle;
    end;
  end;
end;

/// <summary>Knoten unter ARoot in Quelltextreihenfolge, ohne Rekursion (#1094). Mit ASkipRoutines ohne
/// eingebettete Routinen und anonyme Methoden.</summary>
function NodesBelow(ARoot: TSyntaxNode; ASkipRoutines: Boolean): TArray<TSyntaxNode>;
var
  Stack: TArray<TSyntaxNode>;
  Count, Index, Found: Integer;
  Node: TSyntaxNode;
begin
  SetLength(Result, 64);
  Found := 0;
  SetLength(Stack, 64);
  Stack[0] := ARoot;
  Count := 1;
  while Count > 0 do
  begin
    Dec(Count);
    Node := Stack[Count];
    if Found = Length(Result) then
    begin
      SetLength(Result, 2 * Found);
    end;
    Result[Found] := Node;
    Inc(Found);
    if Count + Node.ChildCount > Length(Stack) then
    begin
      SetLength(Stack, 2 * (Count + Node.ChildCount));
    end;
    for Index := Node.ChildCount - 1 downto 0 do
    begin
      if not ASkipRoutines or not (Node[Index].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Stack[Count] := Node[Index];
        Inc(Count);
      end;
    end;
  end;
  SetLength(Result, Found);
end;

procedure TInheritedConstructorAfterTryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'try vor dem Aufruf des geerbten Konstruktors; Self ist noch nicht initialisiert (wie H2505).';
var
  Tokens: TTokens;
  Paths, Lines: TArray<string>;
  LineBreak: string;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAtOffset(Tokens, ANode.StartOffset));
  end;

  function IsConstructor(ARoutine: TSyntaxNode): Boolean;
  var
    Head: string;
  begin
    // class constructor ruft kein inherited auf; dort gibt es kein Self.
    Head := TrimLeft(Copy(AContext.Text, ARoutine.StartOffset + 1, Length('constructor') + 1));
    Result := StartsText('constructor', Head) and (Length(Head) > Length('constructor')) and
      CharInSet(Head[Length('constructor') + 1], [' ', #9, #10, #13]);
  end;

  // inherited ohne Namen, mit dem eigenen Namen oder Create…: der geerbte Konstruktor.
  function IsConstructorCall(ANode: TSyntaxNode; const AOwn: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.InheritedExpr) and ((ANode.Name = '') or SameText(ANode.Name, AOwn) or
      StartsText('Create', ANode.Name));
  end;

  // Korrektur, wenn der Aufruf die erste Anweisung des try-Teils ist: vor try ziehen.
  function MoveBeforeTry(ATry, ACall: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    TryToken, Last, Semicolon: Integer;
    Text, Before: string;
    Removal: TTextRange;
  begin
    Result := nil;
    Statement := ACall;
    while (Statement <> nil) and (Statement.Parent <> ATry) do
    begin
      Statement := Statement.Parent;
    end;
    if (Statement = nil) or (ATry.ChildCount = 0) or (ATry[0] <> Statement) or
      (Statement.Kind <> TSyntaxKind.CallStatement) then
    begin
      Exit;
    end;
    TryToken := TokenAtOffset(Tokens, ATry.StartOffset);
    // Kommentare zwischen try und Aufruf gingen mit dem Verschieben verloren.
    if (TryToken + 1 > High(Tokens)) or (Tokens[TryToken + 1].Offset <> Statement.StartOffset) then
    begin
      Exit;
    end;
    Last := PreviousCode(Tokens, TokenAtOffset(Tokens, Statement.EndOffset));
    Semicolon := NextCode(Tokens, Last + 1);
    Removal := TTextRange.Create(Tokens[TryToken].EndPos, Tokens[Last].EndPos);
    if (Semicolon <= High(Tokens)) and Tokens[Semicolon].IsSymbol(';') then
    begin
      Removal.EndPos := Tokens[Semicolon].EndPos;
    end;
    Text := Copy(AContext.Text, Statement.StartOffset + 1, Statement.EndOffset - Statement.StartOffset);
    Before := Trim(Copy(Lines[Tokens[TryToken].StartPos.Line], 1, Tokens[TryToken].StartPos.Character));
    if Before = '' then
    begin
      Text := Text + ';' + LineBreak + TTextLines.IndentOf(Lines[Tokens[TryToken].StartPos.Line]);
    end
    else
    begin
      Text := Text + '; ';
    end;
    Result := [TRuleFix.Create(Format('%s vor try ziehen', [Trim(Copy(AContext.Text, ACall.StartOffset + 1,
      ACall.EndOffset - ACall.StartOffset))]), [TRuleEdit.Create(TTextRange.Create(Tokens[TryToken].StartPos,
      Tokens[TryToken].StartPos), Text), TRuleEdit.Create(Removal, '')], True)];
  end;

  // Eigener Name des Konstruktors ohne Klasse.
  function OwnName(ARoutine: TSyntaxNode): string;
  begin
    Result := ARoutine.Name;
    if LastDelimiter('.', Result) > 0 then
    begin
      Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
    end;
  end;

  // Aufrufe des geerbten Konstruktors und try-Anweisungen im Rumpf ABody, ohne eingebettete Routinen.
  procedure CollectBody(ABody: TSyntaxNode; const AOwn: string; out ACalls, ATrys: TArray<TSyntaxNode>);
  var
    mNode: TSyntaxNode;
  begin
    ACalls := nil;
    ATrys := nil;
    for mNode in NodesBelow(ABody, True) do
    begin
      if IsConstructorCall(mNode, AOwn) then
      begin
        ACalls := ACalls + [mNode];
      end
      else if mNode.Kind = TSyntaxKind.TryStatement then
      begin
        ATrys := ATrys + [mNode];
      end;
    end;
  end;

  // Erster Aufruf des geerbten Konstruktors nach ATry; nil, wenn einer vor ATry steht oder keiner folgt.
  // Zweige von {$IFDEF}, die sich ausschließen, zählen nicht gegeneinander.
  function CallAfter(ATry: TSyntaxNode; const ATryPath: string; const ACalls: TArray<TSyntaxNode>): TSyntaxNode;
  var
    mCall: TSyntaxNode;
  begin
    Result := nil;
    for mCall in ACalls do
    begin
      if TConditionalBranches.Exclusive(ATryPath, PathOf(mCall)) then
      begin
        Continue;
      end;
      if mCall.StartOffset < ATry.StartOffset then
      begin
        Exit(nil);
      end;
      if Result = nil then
      begin
        Result := mCall;
      end;
    end;
  end;

  // Steht schon ein gemeldetes try in einem Zweig, der sich mit ATryPath nicht ausschließt?
  function ReportedBefore(const ATryPath: string; const AReported: TArray<TSyntaxNode>): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    Result := False;
    for mNode in AReported do
    begin
      Result := Result or not TConditionalBranches.Exclusive(ATryPath, PathOf(mNode));
    end;
  end;

  procedure CheckConstructor(ARoutine: TSyntaxNode);
  var
    mBody, mTry, mAfter: TSyntaxNode;
    mTryPath: string;
    mCalls, mTrys, mReported: TArray<TSyntaxNode>;
  begin
    mBody := ARoutine.FindChild(TSyntaxKind.Block);
    if mBody = nil then
    begin
      Exit;
    end;
    CollectBody(mBody, OwnName(ARoutine), mCalls, mTrys);
    mReported := nil;
    for mTry in mTrys do
    begin
      mTryPath := PathOf(mTry);
      mAfter := CallAfter(mTry, mTryPath, mCalls);
      // Gemeldet wird das erste try; ein späteres nur in einem anderen Zweig.
      if (mAfter = nil) or ReportedBefore(mTryPath, mReported) then
      begin
        Continue;
      end;
      mReported := mReported + [mTry];
      AReport.Add(TTextRange.Create(mTry.StartPos, TTextPosition.Create(mTry.StartPos.Line,
        mTry.StartPos.Character + Length('try'))), Message, TRuleConfidence.High, MoveBeforeTry(mTry, mAfter));
    end;
  end;

var
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  for Node in NodesBelow(AContext.Tree.Root, False) do
  begin
    if (Node.Kind = TSyntaxKind.RoutineDecl) and IsConstructor(Node) then
    begin
      CheckConstructor(Node);
    end;
  end;
end;

procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TGenericExceptionRaisedRule.Create);
  ARegistry.Register(TCatchAllWithoutRaiseRule.Create);
  ARegistry.Register(TExceptionFreedRule.Create);
  ARegistry.Register(TExceptionInDestructorRule.Create);
  ARegistry.Register(TExceptHandlerOrderRule.Create);
  ARegistry.Register(TReraiseExceptionObjectRule.Create);
  ARegistry.Register(TReraiseOutsideHandlerRule.Create);
  ARegistry.Register(TInheritedConstructorAfterTryRule.Create);
end;

end.
