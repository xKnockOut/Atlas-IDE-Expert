unit Atlas.Common.Rules.Builtin.Concurrency.Tests;

// Tests für die Nebenläufigkeitsregeln (#148), pair-without-finally (#930) und processmessages-in-loop (#931).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConcurrencyRulesTests = class
  public
    [Test]
    procedure VclAccessInExecuteReports;
    [Test]
    procedure VclAccessInsideSynchronizeIsSilent;
    [Test]
    procedure VclAccessInAnonymousThreadReports;
    [Test]
    procedure VclAccessOutsideThreadIsSilent;
    [Test]
    procedure ThreadClassesFollowIntermediateClasses;
    [Test]
    procedure LockWithoutFinallyReportsWithFix;
    [Test]
    procedure LockFollowedByTryFinallyIsSilent;
    [Test]
    procedure LockInsideTryWithFinallyIsSilent;
    [Test]
    procedure MonitorAndCriticalSectionNeedSameObject;
    [Test]
    procedure OwnLockPairFromOptions;
    [Test]
    procedure LockLookalikesAndWrappersAreSilent;
    [Test]
    procedure UseAfterFreeOnTerminateReports;
    [Test]
    procedure UseWithoutFreeOnTerminateIsSilent;
    [Test]
    procedure ReassignedThreadIsSilent;
    [Test]
    procedure FreeWithFreeOnTerminateReportsWithFix;
    [Test]
    procedure FreeWithoutFreeOnTerminateIsSilent;
    [Test]
    procedure SynchronizeInThreadDestructorReports;
    [Test]
    procedure SynchronizeInCalledMethodReports;
    [Test]
    procedure SynchronizeInFormDestructorIsSilent;
    [Test]
    procedure ResumeReportsWithFix;
    [Test]
    procedure SuspendReportsAndResumeWithArgumentsIsSilent;
    [Test]
    procedure ResumeOnOwnNonThreadClassIsSilent;
  end;

  /// <summary>Regeln zu Paaren ohne finally, ProcessMessages, Queue(nil), blockierenden Aufrufen, Threadschleifen und
  /// Tasks.</summary>
  [TestFixture]
  TConcurrencyPatternRulesTests = class
  public
    [Test]
    procedure PairWithoutFinallyIssueExample;
    [Test]
    procedure PairWithoutFinallyVariants;
    [Test]
    procedure PairWithoutFinallySilentCases;
    [Test]
    procedure PairWithoutFinallyOptions;
    [Test]
    procedure ProcessMessagesInLoopIssueExample;
    [Test]
    procedure ProcessMessagesInEventHandler;
    [Test]
    procedure ProcessMessagesSilentCases;
    [Test]
    procedure ProcessMessagesOptions;
    [Test]
    procedure QueueNilIssueExample;
    [Test]
    procedure QueueNilFixAndVariants;
    [Test]
    procedure QueueNilSilentCases;
    [Test]
    procedure QueueNilOptions;
    [Test]
    procedure QueueNilWrapperCall;
    [Test]
    procedure BlockingCallIssueExample;
    [Test]
    procedure BlockingCallVariants;
    [Test]
    procedure BlockingCallSilentCases;
    [Test]
    procedure BlockingCallOptions;
    [Test]
    procedure ThreadLoopIssueExample;
    [Test]
    procedure ThreadLoopVariants;
    [Test]
    procedure ThreadLoopSilentCases;
    [Test]
    procedure ThreadLoopOffAndExclude;
    [Test]
    procedure AnonymousThreadIssueExample;
    [Test]
    procedure AnonymousThreadVariables;
    [Test]
    procedure AnonymousThreadSilentCases;
    [Test]
    procedure AnonymousThreadOffAndExclude;
    [Test]
    procedure TaskExceptionIssueExample;
    [Test]
    procedure TaskExceptionVariants;
    [Test]
    procedure TaskExceptionSilentCases;
    [Test]
    procedure TaskExceptionOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Concurrency,
  Atlas.Common.Rules.Builtin.Concurrency.Threads,
  Atlas.Common.Rules.Builtin.Concurrency.MainThread,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  cThreadTypes =
    'type'#10 +
    '  TWorker = class(TThread)'#10 +
    '  protected'#10 +
    '    procedure Execute; override;'#10 +
    '  public'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    '  TMainForm = class(TForm)'#10 +
    '  public'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10;

function Routine(const ABody: string; const AHeader: string): string; overload;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10'begin'#10 + ABody + #10'end;'#10'end.';
end;

function Routine(const ABody: string): string; overload;
begin
  Result := Routine(ABody, 'procedure TA.Run;');
end;

function ThreadUnit(const AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10 + cThreadTypes + 'implementation'#10 + AImplementation + #10'end.';
end;

procedure TConcurrencyRulesTests.VclAccessInExecuteReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TThreadVclAccessRule.Create, ThreadUnit(
    'procedure TWorker.Execute;'#10'begin'#10'  Application.Title := ''x'';'#10'  if Done then'#10 +
    '    ShowMessage(''fertig'');'#10'end;'));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('TThread.Queue(nil, procedure begin Application.Title := ''x'' end)',
    mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(0, Integer(Length(mFindings[1].Fixes)));
end;

procedure TConcurrencyRulesTests.VclAccessInsideSynchronizeIsSilent;
begin
  TRuleAssert.Silent(TThreadVclAccessRule.Create, ThreadUnit(
    'procedure TWorker.Execute;'#10'begin'#10 +
    '  Synchronize(procedure begin Application.Title := ''x''; end);'#10 +
    '  TThread.Queue(nil, procedure begin Screen.Cursor := crDefault; end);'#10'end;'));
end;

procedure TConcurrencyRulesTests.VclAccessInAnonymousThreadReports;
begin
  TRuleAssert.Reports(TThreadVclAccessRule.Create, Routine(
    '  TThread.CreateAnonymousThread(procedure begin ShowMessage(''x''); end).Start;'#10 +
    '  TTask.Run(procedure begin Application.ProcessMessages; end);'), 2);
end;

procedure TConcurrencyRulesTests.VclAccessOutsideThreadIsSilent;
begin
  TRuleAssert.Silent(TThreadVclAccessRule.Create, ThreadUnit(
    'procedure TMainForm.Execute;'#10'begin'#10'  Application.Title := ''x'';'#10'end;'));
end;

procedure TConcurrencyRulesTests.ThreadClassesFollowIntermediateClasses;
var
  mTree: TSyntaxTree;
  mNames: TArray<string>;
begin
  mTree := TPascalParser.Parse('unit U;'#10'interface'#10'type'#10'  TBase = class(TThread) end;'#10 +
    '  TJob = class(TBase) end;'#10'  TOther = class(TObject) end;'#10'implementation'#10'end.');
  try
    mNames := ThreadClasses(mTree.Root);
    Assert.AreEqual(2, Integer(Length(mNames)));
    Assert.AreEqual('TBase', mNames[0]);
    Assert.AreEqual('TJob', mNames[1]);
  finally
    mTree.Free;
  end;
end;

procedure TConcurrencyRulesTests.LockWithoutFinallyReportsWithFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  CS.Enter;'#10'  DoWork;'#10'  CS.Leave;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(10, mFindings[0].Range.EndPos.Character);
  Assert.Contains(mFindings[0].Message, 'Leave');
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('try' + sLineBreak + '    DoWork;' + sLineBreak + '  finally' + sLineBreak + '    CS.Leave;' +
    sLineBreak + '  end', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(6, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Line);
end;

procedure TConcurrencyRulesTests.LockFollowedByTryFinallyIsSilent;
begin
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  CS.Enter;'#10'  try'#10'    DoWork;'#10'  finally'#10'    CS.Leave;'#10'  end;'));
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  FSync.BeginWrite;'#10'  try'#10'    DoWork;'#10'  finally'#10'    FSync.EndWrite;'#10'  end;'));
  // Freigabe eines anderen Objekts zählt nicht.
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create,
    Routine('  CS.Enter;'#10'  try'#10'    DoWork;'#10'  finally'#10'    FOther.Leave;'#10'  end;'));
end;

procedure TConcurrencyRulesTests.LockInsideTryWithFinallyIsSilent;
begin
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  try'#10'    FMutex.Acquire;'#10'    DoWork;'#10'  finally'#10'    FMutex.Release;'#10'  end;'));
end;

procedure TConcurrencyRulesTests.MonitorAndCriticalSectionNeedSameObject;
begin
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  TMonitor.Enter(FList);'#10'  try'#10'    DoWork;'#10'  finally'#10'    TMonitor.Exit(FList);'#10'  end;'));
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create,
    Routine('  TMonitor.Enter(FList);'#10'  try'#10'    DoWork;'#10'  finally'#10'    TMonitor.Exit(FOther);'#10'  end;'));
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  EnterCriticalSection(FCS);'#10'  try'#10'    DoWork;'#10'  finally'#10'    LeaveCriticalSection(FCS);'#10 +
    '  end;'));
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create, Routine('  EnterCriticalSection(FCS);'#10'  DoWork;'));
end;

procedure TConcurrencyRulesTests.LockLookalikesAndWrappersAreSilent;
begin
  // Lokale Routine Enter ist keine Sperre (Rahmenstapel wie in DeclaredTypes).
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create, Routine(
    '  Enter(ARoot);'#10'  DoWork;',
    'procedure TA.Run;'#10'  procedure Enter(ANode: TObject);'#10'  begin'#10'  end;'));
  // Eigene Methode Acquire(Id) ohne Empfänger.
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure TA.Acquire(AId: Integer);'#10'begin'#10'end;'#10 +
    'procedure TA.Run;'#10'begin'#10'  Acquire(Id);'#10'  DoWork;'#10'end;'#10'end.');
  // Hülle, die nur sperrt: der Aufrufer wird geprüft.
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create, Routine('  TMonitor.Enter(FLock);',
    'class procedure TSharedWrites.Enter;'));
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create, Routine('  TSharedWrites.Enter;'#10'  DoWork;'));
  // Monitor vorab anlegen: Freigabe direkt danach.
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create, Routine('  TMonitor.Enter(FLock);'#10'  TMonitor.Exit(FLock);'));
  // Freigabe mit eigenen Parametern in einem Ausdruck im finally.
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create, Routine(
    '  Guard.Enter;'#10'  try'#10'    DoWork;'#10'  finally'#10'    if Guard.Leave(Clear, Keys) then'#10'      Reset;'#10 +
    '  end;'));
  // Ein fremdes Programm-Enter ohne Empfänger bleibt eine Sperre.
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create, Routine('  EnterCriticalSection(FCS);'#10'  DoWork;'));
end;

procedure TConcurrencyRulesTests.OwnLockPairFromOptions;
const
  cConfig = '{ "rules": { "lock-without-finally": { "lockPairs": [["Grab", "Drop"]] } } }';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FPool.Grab;'#10'  DoWork;'#10'  FPool.Drop;'), cConfig))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FPool.Grab;'#10'  try'#10'    DoWork;'#10'  finally'#10'    FPool.Drop;'#10'  end;'), cConfig))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FPool.Grab;'#10'  DoWork;')))), 'ohne Option keine Sperre');
end;

procedure TConcurrencyRulesTests.UseAfterFreeOnTerminateReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TThreadUseAfterFreeOnTerminateRule.Create,
    Routine('  T := TWorker.Create(True);'#10'  T.FreeOnTerminate := True;'#10'  T.Start;'#10 +
      '  Log(T.ThreadID);'#10'  T.WaitFor;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
end;

procedure TConcurrencyRulesTests.UseWithoutFreeOnTerminateIsSilent;
begin
  TRuleAssert.Silent(TThreadUseAfterFreeOnTerminateRule.Create,
    Routine('  T := TWorker.Create(True);'#10'  T.Start;'#10'  T.WaitFor;'#10'  T.Free;'));
end;

procedure TConcurrencyRulesTests.ReassignedThreadIsSilent;
begin
  TRuleAssert.Silent(TThreadUseAfterFreeOnTerminateRule.Create,
    Routine('  T.FreeOnTerminate := True;'#10'  T.Start;'#10'  T := TWorker.Create(True);'#10'  T.Start;'));
end;

procedure TConcurrencyRulesTests.FreeWithFreeOnTerminateReportsWithFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TThreadFreeWithFreeOnTerminateRule.Create,
    Routine('  T.FreeOnTerminate := True;'#10'  T.Start;'#10'  T.Free;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual('', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(7, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(8, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Line);
  // Die Nutzungsregel meldet Free nicht doppelt.
  TRuleAssert.Silent(TThreadUseAfterFreeOnTerminateRule.Create,
    Routine('  T.FreeOnTerminate := True;'#10'  T.Start;'#10'  T.Free;'));
end;

procedure TConcurrencyRulesTests.FreeWithoutFreeOnTerminateIsSilent;
begin
  TRuleAssert.Silent(TThreadFreeWithFreeOnTerminateRule.Create,
    Routine('  T.Start;'#10'  T.WaitFor;'#10'  T.Free;'));
end;

procedure TConcurrencyRulesTests.SynchronizeInThreadDestructorReports;
begin
  TRuleAssert.Reports(TSynchronizeInDestructorRule.Create, ThreadUnit(
    'destructor TWorker.Destroy;'#10'begin'#10'  Synchronize(Notify);'#10'  inherited;'#10'end;'));
end;

procedure TConcurrencyRulesTests.SynchronizeInCalledMethodReports;
begin
  TRuleAssert.Reports(TSynchronizeInDestructorRule.Create, ThreadUnit(
    'procedure TWorker.Cleanup;'#10'begin'#10'  TThread.Synchronize(nil, Notify);'#10'end;'#10 +
    'destructor TWorker.Destroy;'#10'begin'#10'  Cleanup;'#10'  inherited;'#10'end;'));
end;

procedure TConcurrencyRulesTests.SynchronizeInFormDestructorIsSilent;
begin
  TRuleAssert.Silent(TSynchronizeInDestructorRule.Create, ThreadUnit(
    'destructor TMainForm.Destroy;'#10'begin'#10'  TThread.Synchronize(nil, Notify);'#10'  inherited;'#10'end;'));
end;

procedure TConcurrencyRulesTests.ResumeReportsWithFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TThreadResumeSuspendRule.Create, Routine('  FWorker.Resume;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual('Start', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(10, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(16, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Character);
end;

procedure TConcurrencyRulesTests.SuspendReportsAndResumeWithArgumentsIsSilent;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TThreadResumeSuspendRule.Create, Routine('  FWorker.Suspend;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  TRuleAssert.Silent(TThreadResumeSuspendRule.Create, Routine('  FPlayer.Resume(Position);'));
end;

procedure TConcurrencyRulesTests.ResumeOnOwnNonThreadClassIsSilent;
const
  cTypes = 'type'#10'  TClock = class'#10'    procedure Pause;'#10'    procedure Resume;'#10'  end;'#10 +
    '  TWorker = class(TThread)'#10'  end;'#10'  TA = class'#10'    FClock: TClock;'#10'    FWorker: TWorker;'#10 +
    '    procedure Run;'#10'  end;'#10;
begin
  // Eigene Klasse mit Pause/Resume (wie TAtlasTimeClock): Vorfahrenkette bis TObject ohne TThread.
  TRuleAssert.Silent(TThreadResumeSuspendRule.Create, 'unit U;'#10'interface'#10 + cTypes + 'implementation'#10 +
    'procedure TA.Run;'#10'begin'#10'  FClock.Resume;'#10'  FClock.Suspend;'#10'end;'#10'end.');
  // Thread-Nachfahre derselben Datei: weiter gemeldet, auch wenn TThread selbst nicht im Index steht.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TThreadResumeSuspendRule.Create, 'unit U;'#10'interface'#10 +
    cTypes + 'implementation'#10'procedure TA.Run;'#10'begin'#10'  FWorker.Resume;'#10'end;'#10'end.'))));
end;

function Import(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Laden(Tabelle: TDataSet);'#10'var'#10 +
    '  SR: TSearchRec;'#10'  F: TextFile;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TConcurrencyPatternRulesTests.PairWithoutFinallyIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Import('  Screen.Cursor := crHourGlass;'#10'  Tabelle.DisableControls;'#10'  Importieren;'#10 +
    '  Tabelle.EnableControls;'#10'  Screen.Cursor := crDefault;');
  mFindings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('EnableControls steht nicht im finally; bei einer Exception bleibt das Grid eingefroren. ' +
    'Gleiches gilt für Screen.Cursor.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('In try/finally einschließen', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Import('  Screen.Cursor := crHourGlass;'#10'  Tabelle.DisableControls;'#10'  try'#10 +
    '    Importieren;'#10'  finally'#10'    Tabelle.EnableControls;'#10'    Screen.Cursor := crDefault;'#10 +
    '  end;'), mFixed);
  TRuleAssert.Silent(TPairWithoutFinallyRule.Create, mFixed);
end;

procedure TConcurrencyPatternRulesTests.PairWithoutFinallyVariants;
var
  mFindings: TArray<TRuleFinding>;
begin
  // FindFirst in der Bedingung, Datei, Speicher.
  mFindings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Import('  if FindFirst(''*.txt'', faAnyFile, SR) = 0 then'#10 +
    '  begin'#10'    Verarbeiten(SR);'#10'    FindClose(SR);'#10'  end;'#10'  AssignFile(F, ''a.txt'');'#10'  Reset(F);'#10 +
    '  Readln(F);'#10'  CloseFile(F);'#10'  P := AllocMem(100);'#10'  Fuellen(P);'#10'  FreeMem(P);'));
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual('FindClose steht nicht im finally; bei einer Exception bleibt das Suchhandle offen.',
    mFindings[0].Message);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('CloseFile steht nicht im finally; bei einer Exception bleibt die Datei offen.', mFindings[1].Message);
  Assert.AreEqual('FreeMem steht nicht im finally; bei einer Exception bleibt der Speicher belegt.', mFindings[2].Message);
  // BeginUpdate/EndUpdate auf Lines; verschachtelt ohne Korrektur.
  mFindings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Import('  Memo.Lines.BeginUpdate;'#10 +
    '  Memo.Lines.Add(''x'');'#10'  Tabelle.DisableControls;'#10'  Memo.Lines.EndUpdate;'#10'  Lesen;'#10 +
    '  Tabelle.EnableControls;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPairWithoutFinallyRule.Create,
    Import('  Tabelle.DisableControls;'#10'  Lesen;'#10'  Tabelle.EnableControls;'),
    '{"rules": {"pair-without-finally": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPairWithoutFinallyRule.Create,
    Import('  Tabelle.DisableControls;'#10'  Lesen;'#10'  Tabelle.EnableControls;'),
    '{"rules": {"pair-without-finally": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TConcurrencyPatternRulesTests.PairWithoutFinallySilentCases;
begin
  // Mit try/finally, direkt hintereinander, anderer Empfänger, Schließen in einer anderen Routine.
  TRuleAssert.Silent(TPairWithoutFinallyRule.Create, Import('  Tabelle.DisableControls;'#10'  try'#10 +
    '    Lesen;'#10'  finally'#10'    Tabelle.EnableControls;'#10'  end;'#10'  Liste.BeginUpdate;'#10 +
    '  Liste.EndUpdate;'#10'  A.BeginUpdate;'#10'  Lesen;'#10'  B.EndUpdate;'#10'  Tabelle.DisableControls;'));
  TRuleAssert.Silent(TPairWithoutFinallyRule.Create, Import('  if FindFirst(''*.txt'', faAnyFile, SR) = 0 then'#10 +
    '  try'#10'    Verarbeiten(SR);'#10'  finally'#10'    FindClose(SR);'#10'  end;'#10 +
    '  Alt := Screen.Cursor;'#10'  Screen.Cursor := crHourGlass;'#10'  try'#10'    Lesen;'#10'  finally'#10 +
    '    Screen.Cursor := Alt;'#10'  end;'));
end;

procedure TConcurrencyPatternRulesTests.PairWithoutFinallyOptions;
var
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  mFindings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Import('  Anzeige.Einfrieren;'#10 +
    '  Lesen;'#10'  Anzeige.Auftauen;'), '{"rules": {"pair-without-finally": {"pairs": [{"open": "Einfrieren", ' +
    '"close": "Auftauen"}]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Auftauen steht nicht im finally; bei einer Exception bleibt der Zustand hängen.',
    mFindings[0].Message);
  Assert.AreEqual(9, Integer(Length(TPairWithoutFinallyRule.Pairs(''))));
  TConfigurationParser.Parse('{"rules": {"pair-without-finally": {"pairs": [["Einfrieren", "Auftauen"]]}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"pairs" muss eine Liste von Objekten mit "open" und "close" sein', mIssues[0].Message);
end;

const
  cProcessMessagesAdvice = ' Besser die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum ' +
    'Ende sperren.';

procedure TConcurrencyPatternRulesTests.ProcessMessagesInLoopIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, Routine('  while not Fertig do'#10'  begin'#10 +
    '    Schritt;'#10'    Application.ProcessMessages;'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('ProcessMessages in der Schleife erlaubt Wiedereintritt (zweiter Klick, Formular schließen).' +
    cProcessMessagesAdvice, mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // for, repeat und Vcl.Forms.Application.
  TRuleAssert.Reports(TProcessMessagesInLoopRule.Create, Routine('  for I := 0 to 9 do'#10 +
    '    Vcl.Forms.Application.ProcessMessages;'#10'  repeat'#10'    if Abbruch then'#10 +
    '      Application.ProcessMessages;'#10'  until Fertig;'), 2);
end;

procedure TConcurrencyPatternRulesTests.ProcessMessagesInEventHandler;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, Routine('  Status.Caption := ''Lade …'';'#10 +
    '  Application.ProcessMessages;'#10'  Laden;', 'procedure TForm1.LadenClick(Sender: TObject);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('ProcessMessages im Ereignis-Handler erlaubt Wiedereintritt (zweiter Klick, Formular schließen).' +
    cProcessMessagesAdvice, mFindings[0].Message);
end;

procedure TConcurrencyPatternRulesTests.ProcessMessagesSilentCases;
begin
  // Außerhalb von Schleife und Handler, im Thread (anonyme Methode), fremdes ProcessMessages,
  // Schleife ohne ProcessMessages.
  TRuleAssert.Silent(TProcessMessagesInLoopRule.Create, Routine('  Application.ProcessMessages;'#10 +
    '  TTask.Run(procedure begin while True do Application.ProcessMessages; end);'#10 +
    '  while not Fertig do'#10'    Warteschlange.ProcessMessages;'#10'  for I := 0 to 9 do'#10'    Schritt;'));
  // Korrigierte Form: Arbeit im Thread, Knopf gesperrt.
  TRuleAssert.Silent(TProcessMessagesInLoopRule.Create, Routine('  LadenButton.Enabled := False;'#10 +
    '  TTask.Run(procedure begin while not Fertig do Schritt; end);',
    'procedure TForm1.LadenClick(Sender: TObject);'));
end;

procedure TConcurrencyPatternRulesTests.ProcessMessagesOptions;
var
  mSource: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := Routine('  while not Fertig do'#10'    Application.ProcessMessages;', 'procedure TForm1.Warten;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, mSource,
    '{"rules": {"processmessages-in-loop": {"allowIn": ["Warten"]}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, mSource,
    '{"rules": {"processmessages-in-loop": {"allowIn": ["TForm1.Warten"]}}}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, mSource,
    '{"rules": {"processmessages-in-loop": {"allowIn": ["TForm2.Warten"]}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, mSource,
    '{"rules": {"processmessages-in-loop": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TProcessMessagesInLoopRule.Create, mSource,
    '{"rules": {"processmessages-in-loop": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"processmessages-in-loop": {"allowIn": "Warten"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

const
  cQueueExample =
    '  TThread.Queue(nil,'#10 +
    '    procedure'#10 +
    '    begin'#10 +
    '      FPanel.Aktualisieren;'#10 +
    '    end);';

/// <summary>Quelltext nach den Korrekturen des ersten Treffers.</summary>
function Fixed(const ASource: string; const AFinding: TRuleFinding): string;
var
  mLines: TArray<string>;
  mOffsets: TArray<Integer>;
  mIndex: Integer;
  mEdit: TTextEdit;
begin
  mLines := ASource.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  Result := ASource;
  for mIndex := High(AFinding.Fixes[0].Edits) downto 0 do
  begin
    mEdit := AFinding.Fixes[0].Edits[mIndex];
    Result := Copy(Result, 1, mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character) + mEdit.NewText +
      Copy(Result, mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character + 1, MaxInt);
  end;
end;

procedure TConcurrencyPatternRulesTests.QueueNilIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mSource := Routine(cQueueExample);
  mFindings := TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create, mSource, 'Atlas.IDE.Expert', '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('queue-nil-in-package', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Queue(nil, …) in Atlas.IDE.Expert.bpl: der Eintrag kann nach dem Entladen des Packages laufen.',
    mFindings[0].Message);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(19, mFindings[0].Range.EndPos.Character);
  // Korrigierte Form wie im Issue; sie parst fehlerfrei und wird nicht mehr gemeldet.
  Assert.AreEqual(Routine('  TAtlasMainThread.Queue('#10'    procedure'#10'    begin'#10 +
    '      FPanel.Aktualisieren;'#10'    end);'), Fixed(mSource, mFindings[0]));
  mTree := TPascalParser.Parse(Fixed(mSource, mFindings[0]));
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create,
    Fixed(mSource, mFindings[0]), 'Atlas.IDE.Expert', '', 'U.pas'))));
end;

procedure TConcurrencyPatternRulesTests.QueueNilFixAndVariants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // ForceQueue und Argument in derselben Zeile.
  mSource := Routine('  TThread.ForceQueue(nil, Aktualisieren);');
  mFindings := TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create, mSource, 'P', '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('ForceQueue(nil, …) in P.bpl: der Eintrag kann nach dem Entladen des Packages laufen.',
    mFindings[0].Message);
  Assert.AreEqual(Routine('  TAtlasMainThread.ForceQueue(Aktualisieren);'), Fixed(mSource, mFindings[0]));
  // ForceQueue mit Verzögerung: Meldung ohne Korrektur.
  mFindings := TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create,
    Routine('  TThread.ForceQueue(nil, Aktualisieren, 100);'), 'P', '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Mehrere Argumente in der anonymen Methode zählen nicht mit.
  mFindings := TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create,
    Routine('  TThread.Queue(nil, procedure begin Zeigen(1, [2, 3]); end);'), 'P', '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  // Ohne Projektname: die .dpk selbst.
  mFindings := TRuleAssert.Findings(TQueueNilInPackageRule.Create,
    'package P;'#10'requires rtl;'#10'begin'#10'  TThread.Queue(nil, Start);'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Queue(nil, …) in diesem Package: der Eintrag kann nach dem Entladen des Packages laufen.',
    mFindings[0].Message);
end;

procedure TConcurrencyPatternRulesTests.QueueNilSilentCases;
begin
  // Kein Package: Programm oder unbekannt.
  TRuleAssert.Silent(TQueueNilInPackageRule.Create, Routine(cQueueExample));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TQueueNilInPackageRule.Create,
    Routine(cQueueExample), TRuleApplicationKind.Gui))));
  // Mit Besitzer, über den Wrapper, im Kommentar oder String.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create,
    Routine('  TThread.Queue(Self, Aktualisieren);'#10'  TAtlasMainThread.Queue(Aktualisieren);'#10 +
    '  // TThread.Queue(nil, Aktualisieren);'#10'  S := ''TThread.Queue(nil, X)'';'), 'P', '', 'U.pas'))));
  // Ausnahme per Kommentar.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create,
    Routine('  TThread.Queue(nil, Aktualisieren); // mainthread-ok'), 'P', '', 'U.pas'))));
end;

procedure TConcurrencyPatternRulesTests.QueueNilOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := Routine('  TThread.Queue(nil, Aktualisieren); // ui-ok');
  mFindings := TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create, mSource, 'P',
    '{"rules": {"queue-nil-in-package": {"wrapper": "Haupt.Einreihen"}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Routine('  Haupt.Einreihen(Aktualisieren); // ui-ok'), Fixed(mSource, mFindings[0]));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create, mSource, 'P',
    '{"rules": {"queue-nil-in-package": {"okMarker": "ui-ok"}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create, mSource, 'P',
    '{"rules": {"queue-nil-in-package": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TQueueNilInPackageRule.Create, mSource, 'P',
    '{"rules": {"queue-nil-in-package": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"queue-nil-in-package": {"wrapper": 1, "okMarker": true}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;

procedure TConcurrencyPatternRulesTests.QueueNilWrapperCall;
begin
  Assert.AreEqual('TAtlasMainThread.Queue(', TQueueNilInPackageRule.WrapperCall('TAtlasMainThread.Queue', 'Queue'));
  Assert.AreEqual('TAtlasMainThread.ForceQueue(',
    TQueueNilInPackageRule.WrapperCall('TAtlasMainThread.Queue', 'ForceQueue'));
  Assert.AreEqual('TAtlasMainThread.Queue(TAtlasFeature.Hover, ',
    TQueueNilInPackageRule.WrapperCall('TAtlasMainThread.Queue(TAtlasFeature.Hover, ', 'queue'));
  Assert.AreEqual('Post(', TQueueNilInPackageRule.WrapperCall('Post', 'ForceQueue'));
end;

const
  cBlockingCallAdvice = ' Besser die Arbeit mit TTask.Run auslagern und das Ergebnis über TThread.Queue melden.';

function FormUnit(const AMethods: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'type'#10'  TfrmHaupt = class(TForm)'#10 +
    '    procedure btnExportClick(Sender: TObject);'#10'  end;'#10'implementation'#10 + AMethods + 'end.';
end;

function FormMethod(const AHeader, ABody: string): string;
begin
  Result := FormUnit(AHeader + #10'begin'#10 + ABody + 'end;'#10);
end;

procedure TConcurrencyPatternRulesTests.BlockingCallIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, FormMethod(
    'procedure TfrmHaupt.btnExportClick(Sender: TObject);', '  FExport.Start;'#10'  FExport.WaitFor;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('blocking-call-in-main-thread', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('WaitFor im Click-Handler blockiert den Hauptthread; ruft FExport Synchronize auf, hängt das ' +
    'Programm.' + cBlockingCallAdvice, mFindings[0].Message);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(17, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Korrigierte Form: Arbeit in TTask.Run, Rückmeldung über TThread.Queue.
  TRuleAssert.Silent(TBlockingCallInMainThreadRule.Create, FormMethod(
    'procedure TfrmHaupt.btnExportClick(Sender: TObject);', '  btnExport.Enabled := False;'#10 +
    '  TTask.Run(procedure begin FExport.Ausfuehren; FExport.WaitFor; TThread.Queue(nil, procedure begin ' +
    'btnExport.Enabled := True; end); end);'#10));
end;

procedure TConcurrencyPatternRulesTests.BlockingCallVariants;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, FormMethod('procedure TfrmHaupt.Laden;',
    '  Sleep(500);'#10'  if WaitForSingleObject(H, INFINITE) = WAIT_OBJECT_0 then'#10'    FEreignis.WaitFor(5000);'#10 +
    '  FAufgabe.Wait;'#10'  Winapi.Windows.Sleep(Pause);'#10'  while not Fertig do'#10'    Sleep(10);'#10));
  Assert.AreEqual(6, Integer(Length(mFindings)));
  Assert.AreEqual('Sleep(500) in Laden blockiert den Hauptthread; die Oberfläche friert ein.' + cBlockingCallAdvice,
    mFindings[0].Message);
  Assert.AreEqual('FEreignis.WaitFor(5000) in Laden blockiert den Hauptthread; die Oberfläche friert ein.' +
    cBlockingCallAdvice, mFindings[2].Message);
  Assert.AreEqual('Warteschleife mit Sleep in Laden blockiert den Hauptthread; die Oberfläche friert ein.' +
    cBlockingCallAdvice, mFindings[5].Message);
  // Ereignis-Handler einer anderen Klasse, Frame, eingebettete Routine.
  mFindings := TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TfraListe = class(TFrame)'#10'  end;'#10'implementation'#10 +
    'procedure TVerwaltung.TimerTimer(Sender: TObject);'#10'begin'#10'  Sleep(100);'#10'end;'#10 +
    'procedure TfraListe.Fuellen;'#10'  procedure Warten;'#10'  begin'#10'    Sleep(1000);'#10'  end;'#10 +
    'begin'#10'  Warten;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Sleep(100) im Ereignis-Handler TimerTimer blockiert den Hauptthread; die Oberfläche friert ein.' +
    cBlockingCallAdvice, mFindings[0].Message);
  Assert.AreEqual(1, TBlockingCallInMainThreadRule.TimeoutArgument('WaitForSingleObject'));
  Assert.AreEqual(3, TBlockingCallInMainThreadRule.TimeoutArgument('WaitForMultipleObjects'));
  Assert.AreEqual(-1, TBlockingCallInMainThreadRule.TimeoutArgument('Pause'));
end;

procedure TConcurrencyPatternRulesTests.BlockingCallSilentCases;
begin
  // Kurze Wartezeiten, Warteschleife mit ProcessMessages, anonyme Methode, fremde Sleep- und Wait-Methoden.
  TRuleAssert.Silent(TBlockingCallInMainThreadRule.Create, FormMethod('procedure TfrmHaupt.Laden;',
    '  Sleep(10);'#10'  Sleep(0);'#10'  WaitForSingleObject(H, 0);'#10'  while not Fertig do'#10'  begin'#10 +
    '    Application.ProcessMessages;'#10'    Sleep(10);'#10'  end;'#10 +
    '  TTask.Run(procedure begin Sleep(1000); end);'#10'  FUhr.Sleep(1000);'#10'  Wait(1000);'#10));
  // Thread-Klasse, Klasse ohne Formular und ohne Sender, Routine außerhalb einer Klasse.
  TRuleAssert.Silent(TBlockingCallInMainThreadRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TExport = class(TThread)'#10'  end;'#10'implementation'#10'procedure TExport.Execute;'#10'begin'#10 +
    '  Sleep(1000);'#10'  FEreignis.WaitFor;'#10'end;'#10'procedure TExport.Fertig(Sender: TObject);'#10'begin'#10 +
    '  Sleep(1000);'#10'end;'#10'procedure TDienst.Laufen;'#10'begin'#10'  Sleep(1000);'#10'end;'#10 +
    'procedure Warten;'#10'begin'#10'  Sleep(1000);'#10'end;'#10'end.');
end;

procedure TConcurrencyPatternRulesTests.BlockingCallOptions;
var
  mSource: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := FormMethod('procedure TfrmHaupt.Laden;', '  Sleep(500);'#10'  Sleep(10);'#10'  Pause(100);'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mSource, '', 'U.pas'))));
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mSource,
    '{"rules": {"blocking-call-in-main-thread": {"maxSleepMs": 5}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mSource,
    '{"rules": {"blocking-call-in-main-thread": {"maxSleepMs": 1000}}}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mSource,
    '{"rules": {"blocking-call-in-main-thread": {"calls": ["Pause"]}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mSource,
    '{"rules": {"blocking-call-in-main-thread": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mSource,
    '{"rules": {"blocking-call-in-main-thread": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"blocking-call-in-main-thread": {"maxSleepMs": "x", "calls": 1}}}',
    mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;

function Poller(const AMethods: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TPoller = class(TThread)'#10'  protected'#10 +
    '    procedure Execute; override;'#10'  end;'#10'implementation'#10 + AMethods + 'end.';
end;

function PollerExecute(const ABody: string): string;
begin
  Result := Poller('procedure TPoller.Execute;'#10'begin'#10 + ABody + 'end;'#10);
end;

procedure TConcurrencyPatternRulesTests.ThreadLoopIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := PollerExecute('  while True do'#10'  begin'#10'    Abfragen;'#10'    Sleep(1000);'#10'  end;'#10);
  mFindings := TRuleAssert.Findings(TThreadLoopWithoutTerminatedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('thread-loop-without-terminated', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Die Schleife prüft Terminated nicht; der Thread lässt sich nicht beenden.', mFindings[0].Message);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(7, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual('Terminated in die Schleifenbedingung aufnehmen', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(PollerExecute('  while not Terminated do'#10'  begin'#10'    Abfragen;'#10'    Sleep(1000);'#10 +
    '  end;'#10), mFixed);
  TRuleAssert.Silent(TThreadLoopWithoutTerminatedRule.Create, mFixed);
end;

procedure TConcurrencyPatternRulesTests.ThreadLoopVariants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Warteschleife mit Bedingung, repeat … until False und mit Bedingung.
  mSource := PollerExecute('  while not FFertig do'#10'    FEreignis.WaitFor(500);'#10'  repeat'#10 +
    '    Abfragen;'#10'  until False;'#10'  repeat'#10'    Sleep(10);'#10'  until FFertig or FAbbruch;'#10);
  mFindings := TRuleAssert.Findings(TThreadLoopWithoutTerminatedRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual(PollerExecute('  while not FFertig and not Terminated do'#10'    FEreignis.WaitFor(500);'#10 +
    '  repeat'#10'    Abfragen;'#10'  until False;'#10'  repeat'#10'    Sleep(10);'#10'  until FFertig or FAbbruch;'#10),
    TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
  Assert.AreEqual(PollerExecute('  while not FFertig do'#10'    FEreignis.WaitFor(500);'#10'  repeat'#10 +
    '    Abfragen;'#10'  until Terminated;'#10'  repeat'#10'    Sleep(10);'#10'  until FFertig or FAbbruch;'#10),
    TChangeSignature.ApplyEdits(mSource, mFindings[1].Fixes[0].Edits));
  Assert.AreEqual(PollerExecute('  while not FFertig do'#10'    FEreignis.WaitFor(500);'#10'  repeat'#10 +
    '    Abfragen;'#10'  until False;'#10'  repeat'#10'    Sleep(10);'#10'  until (FFertig or FAbbruch) or Terminated;'#10),
    TChangeSignature.ApplyEdits(mSource, mFindings[2].Fixes[0].Edits));
  // Methode, die nur aus Execute kommt (auch über eine zweite), eingebettete Routine.
  mFindings := TRuleAssert.Findings(TThreadLoopWithoutTerminatedRule.Create, Poller(
    'procedure TPoller.Execute;'#10'  procedure Warten;'#10'  begin'#10'    while True do Sleep(1);'#10'  end;'#10 +
    'begin'#10'  Starten;'#10'  Warten;'#10'end;'#10'procedure TPoller.Starten;'#10'begin'#10'  Schleife;'#10 +
    'end;'#10'procedure TPoller.Schleife;'#10'begin'#10'  while True do Abfragen;'#10'end;'#10));
  Assert.AreEqual(2, Integer(Length(mFindings)));
end;

procedure TConcurrencyPatternRulesTests.ThreadLoopSilentCases;
begin
  // Terminated in Bedingung oder Rumpf, CheckTerminated, begrenzte Schleifen, for, anonyme Methode.
  TRuleAssert.Silent(TThreadLoopWithoutTerminatedRule.Create, PollerExecute(
    '  while not Terminated do Sleep(10);'#10'  while True do'#10'  begin'#10'    if Terminated then Exit;'#10 +
    '    Sleep(10);'#10'  end;'#10'  repeat Sleep(10) until CheckTerminated;'#10 +
    '  while I < Liste.Count do Inc(I);'#10'  for I := 0 to 9 do Sleep(10);'#10 +
    '  TTask.Run(procedure begin while True do Sleep(10); end);'#10));
  // Methode, die auch von außerhalb kommt; Klasse mit TerminatedSet; Klasse ohne Thread; Execute fremder Klasse.
  TRuleAssert.Silent(TThreadLoopWithoutTerminatedRule.Create, Poller('procedure TPoller.Execute;'#10'begin'#10 +
    '  Schleife;'#10'end;'#10'procedure TPoller.Schleife;'#10'begin'#10'  while True do Sleep(1);'#10'end;'#10 +
    'procedure Fremd(P: TPoller);'#10'begin'#10'  P.Schleife;'#10'end;'#10));
  TRuleAssert.Silent(TThreadLoopWithoutTerminatedRule.Create, Poller('procedure TPoller.TerminatedSet;'#10 +
    'begin'#10'  FEreignis.SetEvent;'#10'end;'#10'procedure TPoller.Execute;'#10'begin'#10 +
    '  while True do FEreignis.WaitFor;'#10'end;'#10));
  TRuleAssert.Silent(TThreadLoopWithoutTerminatedRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TDienst.Execute;'#10'begin'#10'  while True do Sleep(1);'#10'end;'#10'end.');
end;

procedure TConcurrencyPatternRulesTests.ThreadLoopOffAndExclude;
var
  mSource: string;
begin
  mSource := PollerExecute('  while True do Sleep(1);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadLoopWithoutTerminatedRule.Create, mSource,
    '{"rules": {"thread-loop-without-terminated": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadLoopWithoutTerminatedRule.Create, mSource,
    '{"rules": {"thread-loop-without-terminated": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TConcurrencyPatternRulesTests.AnonymousThreadIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine('  TThread.CreateAnonymousThread('#10'    procedure'#10'    begin'#10'      Synchronisieren;'#10 +
    '    end);');
  mFindings := TRuleAssert.Findings(TAnonymousThreadNotStartedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('anonymous-thread-not-started', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Der anonyme Thread wird nie gestartet und nie freigegeben.', mFindings[0].Message);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('.Start anhängen', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine('  TThread.CreateAnonymousThread('#10'    procedure'#10'    begin'#10 +
    '      Synchronisieren;'#10'    end).Start;'), mFixed);
  TRuleAssert.Silent(TAnonymousThreadNotStartedRule.Create, mFixed);
end;

procedure TConcurrencyPatternRulesTests.AnonymousThreadVariables;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Lokale Variable mit gesetzten Eigenschaften: Start nach der letzten Anweisung, die sie erwähnt.
  mSource := Routine('  T := System.Classes.TThread.CreateAnonymousThread(Arbeit);'#10'  T.FreeOnTerminate := False;'#10 +
    '  Weiter;', 'procedure TA.Run;'#10'var'#10'  T: TThread;');
  mFindings := TRuleAssert.Findings(TAnonymousThreadNotStartedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('T.Start ergänzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Routine('  T := System.Classes.TThread.CreateAnonymousThread(Arbeit);'#10 +
    '  T.FreeOnTerminate := False;'#10'  T.Start;'#10'  Weiter;', 'procedure TA.Run;'#10'var'#10'  T: TThread;'),
    TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
  // Inline-Variable.
  mFindings := TRuleAssert.Findings(TAnonymousThreadNotStartedRule.Create, Routine(
    '  var Aufgabe := TThread.CreateAnonymousThread(Arbeit);'#10'  Weiter;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Routine('  var Aufgabe := TThread.CreateAnonymousThread(Arbeit);'#10'  Aufgabe.Start;'#10 +
    '  Weiter;'), TChangeSignature.ApplyEdits(Routine('  var Aufgabe := TThread.CreateAnonymousThread(Arbeit);'#10 +
    '  Weiter;'), mFindings[0].Fixes[0].Edits));
end;

procedure TConcurrencyPatternRulesTests.AnonymousThreadSilentCases;
begin
  // Gestartet, später gestartet, Resume, weitergegeben, Ergebnis, Feld, fremde Fabrik.
  TRuleAssert.Silent(TAnonymousThreadNotStartedRule.Create, Routine(
    '  TThread.CreateAnonymousThread(Arbeit).Start;'#10'  T := TThread.CreateAnonymousThread(Arbeit);'#10 +
    '  T.FreeOnTerminate := False;'#10'  T.Start;'#10'  U := TThread.CreateAnonymousThread(Arbeit);'#10 +
    '  U.Resume;'#10'  V := TThread.CreateAnonymousThread(Arbeit);'#10'  FListe.Add(V);'#10 +
    '  Result := TThread.CreateAnonymousThread(Arbeit);'#10'  FThread := TThread.CreateAnonymousThread(Arbeit);'#10 +
    '  Fabrik.CreateAnonymousThread(Arbeit);', 'function TA.Run: TThread;'#10'var'#10'  T, U, V: TThread;'));
end;

procedure TConcurrencyPatternRulesTests.AnonymousThreadOffAndExclude;
var
  mSource: string;
begin
  mSource := Routine('  TThread.CreateAnonymousThread(Arbeit);');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAnonymousThreadNotStartedRule.Create, mSource,
    '{"rules": {"anonymous-thread-not-started": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAnonymousThreadNotStartedRule.Create, mSource,
    '{"rules": {"anonymous-thread-not-started": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

function TaskUnit(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils, System.Threading;'#10 +
    'procedure TA.Run;'#10'var'#10'  A: ITask;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TConcurrencyPatternRulesTests.TaskExceptionIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mSource := TaskUnit('  TTask.Run('#10'    procedure'#10'    begin'#10'      Importieren(Datei);'#10'    end);'#10);
  mFindings := TRuleAssert.Findings(TTaskExceptionUnobservedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('task-exception-unobserved', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Der Task wird nie abgefragt und fängt keine Exceptions; Fehler in Importieren gehen verloren.',
    mFindings[0].Message);
  Assert.AreEqual(9, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('Rumpf in try … except mit Meldung über TThread.Queue einschließen', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(TaskUnit('  TTask.Run('#10'    procedure'#10'    begin'#10'      try'#10 +
    '        Importieren(Datei);'#10'      except'#10'        on E: Exception do'#10'        begin'#10 +
    '          var Fehler := E.Message;'#10'          TThread.Queue(nil,'#10'            procedure'#10 +
    '            begin'#10'              ShowMessage(Fehler);'#10'            end);'#10'        end;'#10 +
    '      end;'#10'    end);'#10), 'System.Threading;', 'System.Threading,'#10'  Vcl.Dialogs;', []), mFixed);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  TRuleAssert.Silent(TTaskExceptionUnobservedRule.Create, mFixed);
end;

procedure TConcurrencyPatternRulesTests.TaskExceptionVariants;
var
  mFindings: TArray<TRuleFinding>;
begin
  // TTask.Create(…).Start, Variable ohne Abfrage, Create in Variable mit Start, Rumpf in einer Zeile (ohne Korrektur).
  mFindings := TRuleAssert.Findings(TTaskExceptionUnobservedRule.Create, TaskUnit(
    '  TTask.Create(procedure begin Laden; end).Start;'#10'  A := TTask.Run(procedure begin Laden; end);'#10 +
    '  var B := TTask.Create(procedure begin end);'#10'  B.Start;'#10) );
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Der Task wird nie abgefragt und fängt keine Exceptions; Fehler im Task gehen verloren.',
    mFindings[2].Message);
end;

procedure TConcurrencyPatternRulesTests.TaskExceptionSilentCases;
begin
  // try … except im Rumpf, abgefragtes Ergebnis, Variable weitergegeben, Methodenzeiger, nie gestartetes Create.
  TRuleAssert.Silent(TTaskExceptionUnobservedRule.Create, TaskUnit(
    '  TTask.Run(procedure begin try Laden; except on E: Exception do Melden(E.Message); end; end);'#10 +
    '  TTask.Run(procedure begin Laden; end).Wait;'#10'  A := TTask.Run(procedure begin Laden; end);'#10 +
    '  A.Wait;'#10'  FAufgabe := TTask.Run(procedure begin Laden; end);'#10'  TTask.Run(Laden);'#10 +
    '  var C := TTask.Create(procedure begin Laden; end);'#10'  Result := TTask.Run(procedure begin end);'#10));
end;

procedure TConcurrencyPatternRulesTests.TaskExceptionOffAndExclude;
var
  mSource: string;
begin
  mSource := TaskUnit('  TTask.Run(procedure begin Laden; end);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTaskExceptionUnobservedRule.Create, mSource,
    '{"rules": {"task-exception-unobserved": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTaskExceptionUnobservedRule.Create, mSource,
    '{"rules": {"task-exception-unobserved": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TConcurrencyRulesTests);
  TDUnitX.RegisterTestFixture(TConcurrencyPatternRulesTests);

end.
