unit Rules.Builtin.Concurrency.QueueRemove.Tests;

// Tests für queue-without-remove: Queue am eigenen Thread ohne RemoveQueuedEvents bei einem Destruktor ohne
// inherited, TThread.Destroy entfernt selbst, Entfernen im Destruktor, in DoTerminate, im Vorfahren und durch den
// Besitzer, Queue(nil, …), Synchronize und die Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TQueueWithoutRemoveRuleTests = class
  public
    [Test]
    procedure IssueExampleReports;
    [Test]
    procedure ThreadDestroyRemoves;
    [Test]
    procedure FixAddsRemoveToDestructor;
    [Test]
    procedure RemovedInDestructorOrDoTerminate;
    [Test]
    procedure RemovedInAncestor;
    [Test]
    procedure RemovedByOwner;
    [Test]
    procedure QueueForms;
    [Test]
    procedure QueueNilAndSynchronizeSilent;
    [Test]
    procedure OwnQueueMethodSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Rules.Builtin.Concurrency.QueueRemove,
  Atlas.Common.Documents.TextChanges,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Findings.Contract;

function WorkerUnit(const AMembers, AMethods: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10 +
    '  TOrderWorker = class(TThread)'#10'  protected'#10'    procedure Execute; override;'#10 + AMembers +
    '  end;'#10'implementation'#10 + AMethods + 'end.';
end;

const
  cDestructorDecl = '  public'#10'    destructor Destroy; override;'#10;
  cQueueExecute = 'procedure TOrderWorker.Execute;'#10'begin'#10 +
    '  Queue(procedure begin FForm.Caption := ''fertig'' end);'#10'end;'#10;
  cDestroy = 'destructor TOrderWorker.Destroy;'#10'begin'#10'  inherited;'#10'end;'#10;
  // Ohne inherited erreicht die Freigabe TThread.Destroy nicht, das RemoveQueuedEvents(Self) aufruft.
  cDestroyAlone = 'destructor TOrderWorker.Destroy;'#10'begin'#10'  FLog.Free;'#10'end;'#10;

{ TQueueWithoutRemoveRuleTests }

procedure TQueueWithoutRemoveRuleTests.IssueExampleReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TQueueWithoutRemoveRule.Create,
    WorkerUnit(cDestructorDecl, cQueueExecute + cDestroyAlone));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('queue-without-remove', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('TOrderWorker reiht mit Queue am eigenen Thread ein, aber niemand entfernt die Einträge mit ' +
    'RemoveQueuedEvents. Was beim Anhalten noch wartet, läuft danach mit freigegebenen Objekten bzw. nach dem ' +
    'Entladen in fremdem Speicher.', mFindings[0].Message);
  Assert.AreEqual(14, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(14, mFindings[0].Range.EndPos.Line);
  Assert.AreEqual(7, mFindings[0].Range.EndPos.Character);
end;

procedure TQueueWithoutRemoveRuleTests.ThreadDestroyRemoves;
begin
  // TThread.Destroy ruft RemoveQueuedEvents(Self): Destruktor mit inherited oder ganz ohne Destruktor.
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit(cDestructorDecl, cQueueExecute + cDestroy));
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit('', cQueueExecute));
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit(cDestructorDecl, cQueueExecute +
    'destructor TOrderWorker.Destroy;'#10'begin'#10'  FLog.Free;'#10'  inherited Destroy;'#10'end;'#10));
end;

procedure TQueueWithoutRemoveRuleTests.FixAddsRemoveToDestructor;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := WorkerUnit(cDestructorDecl, cQueueExecute + cDestroyAlone);
  mFindings := TRuleAssert.Findings(TQueueWithoutRemoveRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('RemoveQueuedEvents(Self) im Destruktor ergänzen', mFindings[0].Fixes[0].Title);
  mFixed := TTextChanges.Apply(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '  RemoveQueuedEvents(Self);');
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, mFixed);
end;

procedure TQueueWithoutRemoveRuleTests.RemovedInDestructorOrDoTerminate;
begin
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit(cDestructorDecl, cQueueExecute +
    'destructor TOrderWorker.Destroy;'#10'begin'#10'  RemoveQueuedEvents(Self);'#10'end;'#10));
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit('    procedure DoTerminate; override;'#10 +
    cDestructorDecl, cQueueExecute + cDestroyAlone + 'procedure TOrderWorker.DoTerminate;'#10'begin'#10 +
    '  TThread.RemoveQueuedEvents(Self);'#10'  inherited;'#10'end;'#10));
end;

procedure TQueueWithoutRemoveRuleTests.RemovedInAncestor;
const
  cSource = 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10 +
    '  TBaseWorker = class(TThread)'#10'  public'#10'    destructor Destroy; override;'#10'  end;'#10 +
    '  TOrderWorker = class(TBaseWorker)'#10'  protected'#10'    procedure Execute; override;'#10'  end;'#10 +
    'implementation'#10'destructor TBaseWorker.Destroy;'#10'begin'#10'  RemoveQueuedEvents(Self);'#10 +
    '  inherited;'#10'end;'#10 + cQueueExecute + 'end.';
begin
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, cSource);
  // Ohne Entfernen und ohne inherited im Vorfahren meldet die Regel die Nachfahrin.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TQueueWithoutRemoveRule.Create,
    StringReplace(cSource, '  RemoveQueuedEvents(Self);'#10'  inherited;'#10, '  FLog.Free;'#10, [])))));
end;

procedure TQueueWithoutRemoveRuleTests.RemovedByOwner;
const
  cOwner = 'type'#10'  TOwner = class'#10'  private'#10'    FWorker: TOrderWorker;'#10'  public'#10 +
    '    procedure Stop;'#10'  end;'#10'procedure TOwner.Stop;'#10'begin'#10'  FWorker.WaitFor;'#10 +
    '  TThread.RemoveQueuedEvents(FWorker);'#10'  FWorker.Free;'#10'end;'#10;
begin
  // Der Besitzer räumt beim Anhalten auf (Problems, Build.Target, Updates.Check).
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit(cDestructorDecl, cOwner + cQueueExecute +
    cDestroyAlone));
end;

procedure TQueueWithoutRemoveRuleTests.QueueForms;
var
  mBody: string;
begin
  for mBody in TArray<string>.Create('  TThread.Queue(Self, Melden);'#10, '  TThread.Queue(CurrentThread, Melden);'#10,
    '  ForceQueue(Melden, 10);'#10, '  Self.Queue(Melden);'#10, '  TThread.ForceQueue(TThread.Current, Melden);'#10) do
  begin
    Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TQueueWithoutRemoveRule.Create,
      WorkerUnit(cDestructorDecl, 'procedure TOrderWorker.Execute;'#10'begin'#10 + mBody + 'end;'#10 +
      cDestroyAlone)))), mBody);
  end;
end;

procedure TQueueWithoutRemoveRuleTests.QueueNilAndSynchronizeSilent;
begin
  // Queue(nil, …) meldet queue-nil-in-package; Synchronize wartet.
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit('', 'procedure TOrderWorker.Execute;'#10'begin'#10 +
    '  TThread.Queue(nil, Melden);'#10'  Synchronize(Melden);'#10'  TThread.Synchronize(Self, Melden);'#10'end;'#10));
  // Queue in einer Klasse, die nicht von TThread erbt.
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, 'unit U;'#10'interface'#10'type'#10'  TListe = class'#10 +
    '    procedure Arbeiten;'#10'  end;'#10'implementation'#10'procedure TListe.Arbeiten;'#10'begin'#10 +
    '  Queue(Melden);'#10'end;'#10'end.');
end;

procedure TQueueWithoutRemoveRuleTests.OwnQueueMethodSilent;
begin
  TRuleAssert.Silent(TQueueWithoutRemoveRule.Create, WorkerUnit('    procedure Queue(const AText: string);'#10,
    'procedure TOrderWorker.Queue(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure TOrderWorker.Execute;'#10'begin'#10'  Queue(''x'');'#10'end;'#10));
end;

procedure TQueueWithoutRemoveRuleTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := WorkerUnit(cDestructorDecl, cQueueExecute + cDestroyAlone);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TQueueWithoutRemoveRule.Create, mSource,
    '{"rules": {"queue-without-remove": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TQueueWithoutRemoveRule.Create, mSource,
    '{"rules": {"queue-without-remove": {"exclude": ["U.pas"]}}}', 'U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TQueueWithoutRemoveRuleTests);

end.
