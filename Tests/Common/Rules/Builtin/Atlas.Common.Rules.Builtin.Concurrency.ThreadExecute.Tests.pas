unit Atlas.Common.Rules.Builtin.Concurrency.ThreadExecute.Tests;

// Tests für thread-execute-without-except und die Ausnahme in catch-all-without-raise.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TThreadExecuteRuleTests = class
  public
    [Test]
    procedure IssueExampleReports;
    [Test]
    procedure FixWithLoggerWrapsBody;
    [Test]
    procedure GuardedCallIsSilent;
    [Test]
    procedure UnknownCallReportsLow;
    [Test]
    procedure FatalExceptionEvaluatedIsSilent;
    [Test]
    procedure OwnThreadAncestor;
    [Test]
    procedure GuardVariants;
    [Test]
    procedure CatchAllSilentInExecuteGuard;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Rules.Builtin.Exceptions,
  Atlas.Common.Rules.Builtin.Concurrency.ThreadExecute,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  cCatchAllOn = '{ "rules": { "catch-all-without-raise": "warning" } }';

function WorkerUnit(const AFields, AMethods: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10'type'#10 +
    '  TIndexWorker = class(TThread)'#10'  private'#10 + AFields + '  protected'#10 +
    '    procedure Execute; override;'#10'  end;'#10'implementation'#10 + AMethods + 'end.';
end;

function WorkerExecute(const ABody: string): string;
begin
  Result := WorkerUnit('', 'procedure TIndexWorker.Execute;'#10'begin'#10 + ABody + 'end;'#10);
end;

procedure TThreadExecuteRuleTests.IssueExampleReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create,
    WorkerExecute('  while not Terminated do'#10'    ProcessNext;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('thread-execute-without-except', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Eine Ausnahme in Execute beendet den Thread still (nur FatalException). Ausnahmen abfangen und ' +
    'melden.', mFindings[0].Message);
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(23, mFindings[0].Range.StartPos.Character);
  // Ohne Protokoll keine Korrektur, damit kein leerer Handler entsteht.
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TThreadExecuteRuleTests.FixWithLoggerWrapsBody;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := WorkerUnit('    FLogger: ILogger;'#10, 'procedure TIndexWorker.Execute;'#10'begin'#10 +
    '  while not Terminated do'#10'    ProcessNext;'#10'end;'#10);
  mFindings := TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Rumpf in try … except mit Meldung über FLogger einschließen', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(WorkerUnit('    FLogger: ILogger;'#10, 'procedure TIndexWorker.Execute;'#10'begin'#10'  try'#10 +
    '    while not Terminated do'#10'      ProcessNext;'#10'  except'#10'    on E: Exception do'#10 +
    '      FLogger.Error(ClassName + ''.Execute: '' + E.Message);'#10'  end;'#10'end;'#10), mFixed);
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, mFixed);
  TRuleAssert.Silent(TEmptyExceptRule.Create, mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create, mFixed, cCatchAllOn))));
  // Fehlt System.SysUtils, ergänzt die Korrektur es.
  mSource := StringReplace(mSource, 'System.SysUtils, ', '', []);
  mFindings := TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create, mSource);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, 'implementation'#10#10'uses'#10'  System.SysUtils;');
end;

procedure TThreadExecuteRuleTests.GuardedCallIsSilent;
begin
  // Execute ruft nur eine Routine, die selbst ganz in try … except steht, auch mit Methodenreferenz als Argument.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', 'procedure RunGuarded(const AWork: TProc);'#10 +
    'begin'#10'  try'#10'    AWork;'#10'  except'#10'    on E: Exception do'#10'      Log(E.Message);'#10'  end;'#10 +
    'end;'#10'procedure TIndexWorker.Execute;'#10'begin'#10'  RunGuarded(ProcessAll);'#10'end;'#10));
  // Auch über eine eigene Methode und eine eingebettete Routine.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', 'procedure TIndexWorker.Execute;'#10 +
    '  procedure Inner;'#10'  begin'#10'    try'#10'      Work;'#10'    except'#10'      Log;'#10'    end;'#10 +
    '  end;'#10'begin'#10'  Inner;'#10'end;'#10));
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', 'procedure TIndexWorker.Execute;'#10 +
    'begin'#10'  Self.Guarded;'#10'end;'#10'procedure TIndexWorker.Guarded;'#10'begin'#10'  try'#10'    Work;'#10 +
    '  except'#10'    on E: Exception do Log(E.Message);'#10'  end;'#10'end;'#10));
  // Die gerufene Routine schützt sich nicht: gemeldet.
  TRuleAssert.Reports(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', 'procedure RunAll;'#10'begin'#10 +
    '  Work;'#10'  Done;'#10'end;'#10'procedure TIndexWorker.Execute;'#10'begin'#10'  RunAll;'#10'end;'#10), 1);
end;

procedure TThreadExecuteRuleTests.UnknownCallReportsLow;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Ohne Rumpf der Routine (andere Unit) nur ein schwacher Befund, der sie nennt; unter der Vorgabe minConfidence
  // medium still.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerExecute('  RunGuarded(ProcessAll);'#10));
  mFindings := TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create,
    WorkerExecute('  RunGuarded(ProcessAll);'#10), '{"minConfidence": "low"}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.Contains(mFindings[0].Message, 'wenn RunGuarded sie nicht selbst fängt');
end;

procedure TThreadExecuteRuleTests.FatalExceptionEvaluatedIsSilent;
const
  cBody = 'procedure TIndexWorker.Execute;'#10'begin'#10'  Prepare;'#10'  ProcessNext;'#10'end;'#10;
begin
  // DoTerminate liest FatalException.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', cBody +
    'procedure TIndexWorker.DoTerminate;'#10'begin'#10'  if FatalException <> nil then'#10'    Log;'#10 +
    '  inherited;'#10'end;'#10));
  // Code nach WaitFor liest FatalException.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', cBody + 'procedure Run;'#10 +
    'var'#10'  mWorker: TIndexWorker;'#10'begin'#10'  mWorker := TIndexWorker.Create(False);'#10 +
    '  mWorker.WaitFor;'#10'  if mWorker.FatalException <> nil then'#10'    Log;'#10'  mWorker.Free;'#10'end;'#10));
  // OnTerminate-Handler, der FatalException liest, zugewiesen beim Erzeugen.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', cBody +
    'procedure TOwner.WorkerDone(Sender: TObject);'#10'begin'#10'  if TThread(Sender).FatalException <> nil then'#10 +
    '    Log;'#10'end;'#10'procedure TOwner.Start;'#10'begin'#10'  FWorker := TIndexWorker.Create(True);'#10 +
    '  FWorker.OnTerminate := WorkerDone;'#10'  FWorker.Start;'#10'end;'#10));
  // FatalException nur für eine andere Klasse: gemeldet.
  TRuleAssert.Reports(TThreadExecuteWithoutExceptRule.Create, WorkerUnit('', cBody +
    'procedure TOwner.WorkerDone(Sender: TObject);'#10'begin'#10'  if TThread(Sender).FatalException <> nil then'#10 +
    '    Log;'#10'end;'#10), 1);
end;

procedure TThreadExecuteRuleTests.OwnThreadAncestor;
const
  cUnit = 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10'type'#10 +
    '  TWorker = class(TThread)'#10'  protected'#10'    procedure DoWork; virtual; abstract;'#10 +
    '    procedure Execute; override;'#10'  end;'#10'  TImport = class(TWorker)'#10'  protected'#10 +
    '    procedure DoWork; override;'#10'  end;'#10'  TExport = class(TWorker)'#10'  protected'#10 +
    '    procedure Execute; override;'#10'  end;'#10'implementation'#10'procedure TWorker.Execute;'#10'begin'#10 +
    '  try'#10'    DoWork;'#10'  except'#10'    on E: Exception do'#10'      Log(E.Message);'#10'  end;'#10 +
    'end;'#10'procedure TImport.DoWork;'#10'begin'#10'  Import;'#10'end;'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Nachfahren eines geschützten Vorfahren, die nur DoWork überschreiben oder inherited rufen, bleiben still.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, cUnit + 'procedure TExport.Execute;'#10'begin'#10 +
    '  inherited;'#10'end;'#10'end.');
  // Ein Nachfahr, der Execute ungeschützt überschreibt, wird gemeldet.
  mFindings := TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create, cUnit + 'procedure TExport.Execute;'#10 +
    'begin'#10'  Prepare;'#10'  Export;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(32, mFindings[0].Range.StartPos.Line);
end;

procedure TThreadExecuteRuleTests.GuardVariants;
begin
  // try … finally um try … except, NameThreadForDebugging davor, except ohne on, else-Teil.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerExecute('  NameThreadForDebugging(''Index'');'#10 +
    '  try'#10'    try'#10'      Work;'#10'    except'#10'      Log;'#10'    end;'#10'  finally'#10'    Done;'#10 +
    '  end;'#10));
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, WorkerExecute('  try'#10'    Work;'#10'  except'#10 +
    '    on E: EAbort do'#10'      Exit;'#10'  else'#10'    Log;'#10'  end;'#10));
  // Nur EAbort gefangen, Anweisung nach dem try, try … finally ohne Schutz: gemeldet.
  TRuleAssert.Reports(TThreadExecuteWithoutExceptRule.Create, WorkerExecute('  try'#10'    Work;'#10'  except'#10 +
    '    on E: EAbort do'#10'      Exit;'#10'  end;'#10), 1);
  TRuleAssert.Reports(TThreadExecuteWithoutExceptRule.Create, WorkerExecute('  try'#10'    Work;'#10'  except'#10 +
    '    Log;'#10'  end;'#10'  Done;'#10), 1);
  TRuleAssert.Reports(TThreadExecuteWithoutExceptRule.Create, WorkerExecute('  try'#10'    Work;'#10'    Step;'#10 +
    '  finally'#10'    Done;'#10'  end;'#10), 1);
  // Execute einer Klasse ohne Thread-Vorfahren bleibt still.
  TRuleAssert.Silent(TThreadExecuteWithoutExceptRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TCommand = class'#10'    procedure Execute;'#10'  end;'#10'implementation'#10'procedure TCommand.Execute;'#10 +
    'begin'#10'  Work;'#10'end;'#10'end.');
end;

procedure TThreadExecuteRuleTests.CatchAllSilentInExecuteGuard;
var
  mSource: string;
begin
  mSource := WorkerExecute('  try'#10'    Work;'#10'  except'#10'    on E: Exception do'#10'      Log(E.Message);'#10 +
    '  end;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create, mSource, cCatchAllOn))));
  // Ein innerer Handler in Execute und Handler anderer Methoden bleiben gemeldet.
  mSource := WorkerExecute('  Prepare;'#10'  try'#10'    Work;'#10'  except'#10'    on E: Exception do'#10 +
    '      Log(E.Message);'#10'  end;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create, mSource, cCatchAllOn))));
  mSource := WorkerUnit('', 'procedure TIndexWorker.Execute;'#10'begin'#10'  Work;'#10'end;'#10 +
    'procedure TIndexWorker.Work;'#10'begin'#10'  try'#10'    Step;'#10'  except'#10'    on E: Exception do'#10 +
    '      Log(E.Message);'#10'  end;'#10'end;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create, mSource, cCatchAllOn))));
end;

procedure TThreadExecuteRuleTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := WorkerExecute('  Prepare;'#10'  Work;'#10);
  TRuleAssert.Reports(TThreadExecuteWithoutExceptRule.Create, mSource);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create, mSource,
    '{"rules": {"thread-execute-without-except": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadExecuteWithoutExceptRule.Create, mSource,
    '{"rules": {"thread-execute-without-except": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TThreadExecuteRuleTests);

end.
