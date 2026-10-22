unit Atlas.Common.Rules.Builtin.Concurrency.Tests;

// Tests für die Nebenläufigkeitsregeln (#148) und pair-without-finally (#930).

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
    procedure PairWithoutFinallyIssueExample;
    [Test]
    procedure PairWithoutFinallyVariants;
    [Test]
    procedure PairWithoutFinallySilentCases;
    [Test]
    procedure PairWithoutFinallyOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Concurrency,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  ThreadTypes =
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

function Routine(const ABody: string; const AHeader: string = 'procedure TA.Run;'): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10'begin'#10 + ABody + #10'end;'#10'end.';
end;

function ThreadUnit(const AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10 + ThreadTypes + 'implementation'#10 + AImplementation + #10'end.';
end;

procedure TConcurrencyRulesTests.VclAccessInExecuteReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadVclAccessRule.Create, ThreadUnit(
    'procedure TWorker.Execute;'#10'begin'#10'  Application.Title := ''x'';'#10'  if Done then'#10 +
    '    ShowMessage(''fertig'');'#10'end;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('TThread.Queue(nil, procedure begin Application.Title := ''x'' end)',
    Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
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
  Tree: TSyntaxTree;
  Names: TArray<string>;
begin
  Tree := TPascalParser.Parse('unit U;'#10'interface'#10'type'#10'  TBase = class(TThread) end;'#10 +
    '  TJob = class(TBase) end;'#10'  TOther = class(TObject) end;'#10'implementation'#10'end.');
  try
    Names := ThreadClasses(Tree.Root);
    Assert.AreEqual(2, Integer(Length(Names)));
    Assert.AreEqual('TBase', Names[0]);
    Assert.AreEqual('TJob', Names[1]);
  finally
    Tree.Free;
  end;
end;

procedure TConcurrencyRulesTests.LockWithoutFinallyReportsWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  CS.Enter;'#10'  DoWork;'#10'  CS.Leave;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(10, Findings[0].Range.EndPos.Character);
  Assert.Contains(Findings[0].Message, 'Leave');
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('try' + sLineBreak + '    DoWork;' + sLineBreak + '  finally' + sLineBreak + '    CS.Leave;' +
    sLineBreak + '  end', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(6, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(7, Findings[0].Fixes[0].Edits[0].Range.EndPos.Line);
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

procedure TConcurrencyRulesTests.OwnLockPairFromOptions;
const
  Config = '{ "rules": { "lock-without-finally": { "lockPairs": [["Grab", "Drop"]] } } }';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FPool.Grab;'#10'  DoWork;'#10'  FPool.Drop;'), Config))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FPool.Grab;'#10'  try'#10'    DoWork;'#10'  finally'#10'    FPool.Drop;'#10'  end;'), Config))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FPool.Grab;'#10'  DoWork;')))), 'ohne Option keine Sperre');
end;

procedure TConcurrencyRulesTests.UseAfterFreeOnTerminateReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadUseAfterFreeOnTerminateRule.Create,
    Routine('  T := TWorker.Create(True);'#10'  T.FreeOnTerminate := True;'#10'  T.Start;'#10 +
      '  Log(T.ThreadID);'#10'  T.WaitFor;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
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
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadFreeWithFreeOnTerminateRule.Create,
    Routine('  T.FreeOnTerminate := True;'#10'  T.Start;'#10'  T.Free;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual('', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(7, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(8, Findings[0].Fixes[0].Edits[0].Range.EndPos.Line);
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
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadResumeSuspendRule.Create, Routine('  FWorker.Resume;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('Start', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(10, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(16, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
end;

procedure TConcurrencyRulesTests.SuspendReportsAndResumeWithArgumentsIsSilent;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadResumeSuspendRule.Create, Routine('  FWorker.Suspend;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  TRuleAssert.Silent(TThreadResumeSuspendRule.Create, Routine('  FPlayer.Resume(Position);'));
end;

function Import(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Laden(Tabelle: TDataSet);'#10'var'#10 +
    '  SR: TSearchRec;'#10'  F: TextFile;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TConcurrencyRulesTests.PairWithoutFinallyIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Import('  Screen.Cursor := crHourGlass;'#10'  Tabelle.DisableControls;'#10'  Importieren;'#10 +
    '  Tabelle.EnableControls;'#10'  Screen.Cursor := crDefault;');
  Findings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('EnableControls steht nicht im finally; bei einer Exception bleibt das Grid eingefroren. ' +
    'Gleiches gilt für Screen.Cursor.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('In try/finally einschließen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Import('  Screen.Cursor := crHourGlass;'#10'  Tabelle.DisableControls;'#10'  try'#10 +
    '    Importieren;'#10'  finally'#10'    Tabelle.EnableControls;'#10'    Screen.Cursor := crDefault;'#10 +
    '  end;'), Fixed);
  TRuleAssert.Silent(TPairWithoutFinallyRule.Create, Fixed);
end;

procedure TConcurrencyRulesTests.PairWithoutFinallyVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // FindFirst in der Bedingung, Datei, Speicher.
  Findings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Import('  if FindFirst(''*.txt'', faAnyFile, SR) = 0 then'#10 +
    '  begin'#10'    Verarbeiten(SR);'#10'    FindClose(SR);'#10'  end;'#10'  AssignFile(F, ''a.txt'');'#10'  Reset(F);'#10 +
    '  Readln(F);'#10'  CloseFile(F);'#10'  P := AllocMem(100);'#10'  Fuellen(P);'#10'  FreeMem(P);'));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('FindClose steht nicht im finally; bei einer Exception bleibt das Suchhandle offen.',
    Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('CloseFile steht nicht im finally; bei einer Exception bleibt die Datei offen.', Findings[1].Message);
  Assert.AreEqual('FreeMem steht nicht im finally; bei einer Exception bleibt der Speicher belegt.', Findings[2].Message);
  // BeginUpdate/EndUpdate auf Lines; verschachtelt ohne Korrektur.
  Findings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Import('  Memo.Lines.BeginUpdate;'#10 +
    '  Memo.Lines.Add(''x'');'#10'  Tabelle.DisableControls;'#10'  Memo.Lines.EndUpdate;'#10'  Lesen;'#10 +
    '  Tabelle.EnableControls;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPairWithoutFinallyRule.Create,
    Import('  Tabelle.DisableControls;'#10'  Lesen;'#10'  Tabelle.EnableControls;'),
    '{"rules": {"pair-without-finally": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPairWithoutFinallyRule.Create,
    Import('  Tabelle.DisableControls;'#10'  Lesen;'#10'  Tabelle.EnableControls;'),
    '{"rules": {"pair-without-finally": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TConcurrencyRulesTests.PairWithoutFinallySilentCases;
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

procedure TConcurrencyRulesTests.PairWithoutFinallyOptions;
var
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Findings := TRuleAssert.Findings(TPairWithoutFinallyRule.Create, Import('  Anzeige.Einfrieren;'#10 +
    '  Lesen;'#10'  Anzeige.Auftauen;'), '{"rules": {"pair-without-finally": {"pairs": [{"open": "Einfrieren", ' +
    '"close": "Auftauen"}]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Auftauen steht nicht im finally; bei einer Exception bleibt der Zustand hängen.',
    Findings[0].Message);
  Assert.AreEqual(9, Integer(Length(TPairWithoutFinallyRule.Pairs(''))));
  TConfigurationParser.Parse('{"rules": {"pair-without-finally": {"pairs": [["Einfrieren", "Auftauen"]]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"pairs" muss eine Liste von Objekten mit "open" und "close" sein', Issues[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TConcurrencyRulesTests);

end.
