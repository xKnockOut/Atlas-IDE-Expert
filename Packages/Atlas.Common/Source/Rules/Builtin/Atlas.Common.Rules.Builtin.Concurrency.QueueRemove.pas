unit Atlas.Common.Rules.Builtin.Concurrency.QueueRemove;

// Prüfregel queue-without-remove (Teil von Atlas.Common.Rules.Builtin.Concurrency, dort registriert): Eine
// Thread-Klasse reiht mit Queue am eigenen Thread in den Hauptthread ein (Queue(…), TThread.Queue(Self, …),
// TThread.Queue(CurrentThread, …), ebenso ForceQueue), aber niemand entfernt die Einträge mit RemoveQueuedEvents.
// Was beim Anhalten noch wartet, läuft danach mit freigegebenen Objekten bzw. nach dem Entladen des Packages in
// fremdem Speicher. Gegenstück zu queue-nil-in-package, das Queue(nil, …) meldet.
//
// Als Entfernen gilt RemoveQueuedEvents in einer Methode der Klasse oder eines Vorfahren der Unit, ein Aufruf mit
// einem anderen Argument als Self bzw. nil an anderer Stelle der Unit (der Besitzer räumt beim Anhalten auf) und
// eine andere Unit des Projekts, die Klasse und RemoveQueuedEvents nennt (Index mit Verwendungen).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TQueueWithoutRemoveRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.FreeFields,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Rules.Builtin.Concurrency.ThreadExecute,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TQueueRemoveText = (Title, NeverRemoved, AddToDestructor);

const
  cTexts: array[TQueueRemoveText] of TAtlasText = (
    (De: 'Thread reiht ein, entfernt die Einträge aber nie'; En: 'Thread queues but never removes the entries'),
    (De: '%0:s reiht mit %1:s am eigenen Thread ein, aber niemand entfernt die Einträge mit RemoveQueuedEvents. ' +
      'Was beim Anhalten noch wartet, läuft danach mit freigegebenen Objekten bzw. nach dem Entladen in fremdem ' +
      'Speicher.';
     En: '%0:s queues with %1:s on its own thread, but nobody removes the entries with RemoveQueuedEvents. ' +
      'Whatever is still waiting when it stops runs afterwards with freed objects or, after unloading, in foreign ' +
      'memory.'),
    (De: 'RemoveQueuedEvents(Self) im Destruktor ergänzen'; En: 'Add RemoveQueuedEvents(Self) to the destructor'));

{$SCOPEDENUMS OFF}

const
  cRemove = 'RemoveQueuedEvents';
  /// <summary>Höchstzahl der Klassen einer Vorfahrenkette (Schutz vor Zyklen).</summary>
  cMaxChain = 32;
  /// <summary>Erste Argumente von TThread.Queue, die den eigenen Thread meinen.</summary>
  cOwnThread: array[0..3] of string = ('Self', 'CurrentThread', 'TThread.Current', 'TThread.CurrentThread');

type
  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TQueueRemoveScan = class(TThreadUnitScan)
  private
    function TargetText(ACall: TSyntaxNode): string;
    function IsOwnQueue(ACall: TSyntaxNode; ADeclaresQueue: Boolean): Boolean;
    function FirstQueue(ARoutine: TSyntaxNode; ADeclaresQueue: Boolean): TSyntaxNode;
    function RemoveCalls(ARoutine: TSyntaxNode): TArray<TSyntaxNode>;
    function ClassChain(const AClass: string; out AForeign: Boolean): TArray<string>;
    function RemovedInUnit(const AChain: TArray<string>): Boolean;
    function RemovedInOtherUnits(const AClass: string): Boolean;
    function DeclaresQueue(const AClass: string): Boolean;
    function DestructorFix(const AClass: string): TArray<TRuleFix>;
    procedure CheckClass(const AClass: string);
  public
    procedure Run;
  end;

{ TQueueRemoveScan }

// Quelltext des Aufrufziels ohne Leerraum: Queue, TThread.Queue, Self.ForceQueue.
function TQueueRemoveScan.TargetText(ACall: TSyntaxNode): string;
begin
  Result := '';
  if (ACall.ChildCount > 0) and (ACall[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
  begin
    Result := StringReplace(SourceText(FContext.Text, ACall[0]), ' ', '', [rfReplaceAll]);
  end;
end;

// Queue(…)/ForceQueue(…) der Klasse selbst oder TThread.Queue(Self|CurrentThread, …).
function TQueueRemoveScan.IsOwnQueue(ACall: TSyntaxNode; ADeclaresQueue: Boolean): Boolean;
var
  mTarget, mFirst: string;
begin
  mTarget := TargetText(ACall);
  if MatchText(mTarget, ['Queue', 'ForceQueue', 'Self.Queue', 'Self.ForceQueue']) then
  begin
    // Eine eigene Methode Queue der Klasse ist kein TThread.Queue.
    Exit(not ADeclaresQueue);
  end;
  Result := MatchText(mTarget, ['TThread.Queue', 'TThread.ForceQueue']) and (ACall.ChildCount > 2);
  if Result then
  begin
    mFirst := StringReplace(SourceText(FContext.Text, ACall[1]), ' ', '', [rfReplaceAll]);
    Result := MatchText(mFirst, cOwnThread);
  end;
end;

function TQueueRemoveScan.FirstQueue(ARoutine: TSyntaxNode; ADeclaresQueue: Boolean): TSyntaxNode;
begin
  Result := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Call) and IsOwnQueue(ANode, ADeclaresQueue) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

// Aufrufe von RemoveQueuedEvents (auch TThread.RemoveQueuedEvents) in ARoutine.
function TQueueRemoveScan.RemoveCalls(ARoutine: TSyntaxNode): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.Call) and SameText(ShortName(TargetText(ANode)), cRemove) then
      begin
        mFound := mFound + [ANode];
      end;
    end);
  Result := mFound;
end;

// AClass und ihre Vorfahren bis vor TThread; AForeign, wenn ein eigener Vorfahr nicht in der Unit steht (sein
// Destruktor ist unbekannt).
function TQueueRemoveScan.ClassChain(const AClass: string; out AForeign: Boolean): TArray<string>;
var
  mClass: string;
  mType: TSymbolLocation;
begin
  Result := nil;
  AForeign := False;
  mClass := AClass;
  while (mClass <> '') and not SameText(mClass, 'TThread') and (Length(Result) < cMaxChain) do
  begin
    Result := Result + [mClass];
    if (Length(Result) > 1) and not (FAncestry.FindClass(mClass, mType) and (mType.FileName = '')) then
    begin
      AForeign := True;
    end;
    mClass := FAncestry.ParentOf(mClass);
  end;
end;

// Entfernt die Unit die Einträge: in einer Methode der Kette oder mit einem fremden Argument anderswo?
function TQueueRemoveScan.RemovedInUnit(const AChain: TArray<string>): Boolean;
var
  mRoutine, mCall: TSyntaxNode;
  mInChain: Boolean;
  mArgument: string;
begin
  for mRoutine in FRoutines do
  begin
    mInChain := MatchText(ClassPart(mRoutine.Name), AChain);
    for mCall in RemoveCalls(mRoutine) do
    begin
      if mInChain then
      begin
        Exit(True);
      end;
      mArgument := '';
      if mCall.ChildCount > 1 then
      begin
        mArgument := Trim(SourceText(FContext.Text, mCall[1]));
      end;
      if (mArgument <> '') and not MatchText(mArgument, ['Self', 'nil']) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

// Andere Units des Projekts, die die Klasse nennen und RemoveQueuedEvents aufrufen (nur mit index.usages).
function TQueueRemoveScan.RemovedInOtherUnits(const AClass: string): Boolean;
var
  mUnit: TUnitIndex;
  mUsage: TIndexUsage;
  mClass, mRemove: Boolean;
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
    mRemove := False;
    for mUsage in mUnit.Usages do
    begin
      mClass := mClass or SameText(mUsage.Name, AClass);
      mRemove := mRemove or SameText(mUsage.Name, cRemove);
    end;
    if mClass and mRemove then
    begin
      Exit(True);
    end;
  end;
end;

// Deklariert die Klasse selbst eine Methode Queue oder ForceQueue?
function TQueueRemoveScan.DeclaresQueue(const AClass: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Method) and SameText(mSymbol.Container, ShortName(AClass)) and
      MatchText(mSymbol.Name, ['Queue', 'ForceQueue']) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TQueueRemoveScan.DestructorFix(const AClass: string): TArray<TRuleFix>;
var
  mDecl: TSyntaxNode;
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  // Eingebettete Klassen: den Rumpf TAußen.TInnen.Destroy findet die Korrektur nicht sicher.
  if Pos('.', AClass) > 0 then
  begin
    Exit;
  end;
  mDecl := FindClassType(FContext.Tree.Root, AClass);
  if (mDecl <> nil) and (mDecl.Parent <> nil) and TFreeFields.DestructorEdits(FContext.Tree, FContext.Text, AClass,
    mDecl.Parent.StartPos.Line, [cRemove + '(Self);'], mEdits) then
  begin
    Result := [TRuleFix.Create(cTexts[TQueueRemoveText.AddToDestructor].Text, mEdits)];
  end;
end;

procedure TQueueRemoveScan.CheckClass(const AClass: string);
var
  mRoutine, mQueue: TSyntaxNode;
  mChain: TArray<string>;
  mForeign, mDeclares: Boolean;
  mConfidence: TRuleConfidence;
begin
  mDeclares := DeclaresQueue(AClass);
  mQueue := nil;
  for mRoutine in FRoutines do
  begin
    if SameText(ClassPart(mRoutine.Name), AClass) then
    begin
      mQueue := FirstQueue(mRoutine, mDeclares);
      if mQueue <> nil then
      begin
        Break;
      end;
    end;
  end;
  if mQueue = nil then
  begin
    Exit;
  end;
  mChain := ClassChain(AClass, mForeign);
  if RemovedInUnit(mChain) or RemovedInOtherUnits(ShortName(AClass)) then
  begin
    Exit;
  end;
  mConfidence := TRuleConfidence.High;
  if mForeign then
  begin
    // Ein Vorfahr aus einer anderen Unit kann die Einträge in seinem Destruktor entfernen.
    mConfidence := TRuleConfidence.Low;
  end;
  FReport.Add(NodeRange(mQueue[0]), cTexts[TQueueRemoveText.NeverRemoved].Fmt([ShortName(AClass),
    TargetText(mQueue)]), mConfidence, DestructorFix(AClass));
end;

procedure TQueueRemoveScan.Run;
var
  mRoutine: TSyntaxNode;
  mOwner: string;
  mDone: TArray<string>;
begin
  mDone := nil;
  for mRoutine in FRoutines do
  begin
    mOwner := ClassPart(mRoutine.Name);
    if (mOwner <> '') and not MatchText(mOwner, mDone) then
    begin
      mDone := mDone + [mOwner];
      if MatchText(mOwner, SharedThreadClasses(FContext)) or IsThreadClassIn(FAncestry, mOwner) then
      begin
        CheckClass(mOwner);
      end;
    end;
  end;
end;

{ TQueueWithoutRemoveRule }

function TQueueWithoutRemoveRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('queue-without-remove', TRuleSeverity.Warning, cTexts[TQueueRemoveText.Title].Text);
end;

procedure TQueueWithoutRemoveRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TQueueRemoveScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Queue') then
  begin
    Exit;
  end;
  mScan := TQueueRemoveScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.QueueRemove', cTexts);

end.
