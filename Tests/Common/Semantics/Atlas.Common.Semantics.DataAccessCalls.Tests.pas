unit Atlas.Common.Semantics.DataAccessCalls.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.DataAccessCalls;

type
  [TestFixture]
  TSemanticsDataAccessCallsTests = class
  private
    FTree: TSyntaxTree;
    FCalls: TArray<TDataAccessCall>;
    function Describe: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CallsWithAndWithoutParentheses;
    [Test]
    procedure ArgumentsAndRoutine;
    [Test]
    procedure BreakLineIsStatementStart;
    [Test]
    procedure WithoutReceiverAndAssignmentSkipped;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.TreeCache;

const
  cUnit =
    'unit Kunde;'#10 +                                          // 0
    'interface'#10 +                                            // 1
    'implementation'#10 +                                       // 2
    'procedure TfrmKunde.Speichern;'#10 +                       // 3
    'begin'#10 +                                                // 4
    '  qryKunde.ExecSQL;'#10 +                                  // 5
    '  Daten.qryAuftrag.Open();'#10 +                           // 6
    '  if Client.Post(''http://x/api'', Body).StatusCode = 200 then'#10 + // 7
    '    Exit;'#10 +                                            // 8
    '  FConn.ExecSQL('#10 +                                     // 9
    '    ''UPDATE Kunden SET Name = '' + QuotedStr(N));'#10 +   // 10
    '  with qryKunde do Open;'#10 +                             // 11
    '  Open;'#10 +                                              // 12
    '  P := @qryKunde.Open;'#10 +                               // 13
    '  Liste.Sort;'#10 +                                        // 14
    'end;'#10 +                                                 // 15
    'end.'#10;

{ TSemanticsDataAccessCallsTests }

function TSemanticsDataAccessCallsTests.Describe: string;
var
  mCall: TDataAccessCall;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mCall in FCalls do
  begin
    mParts := mParts + [Format('%s@%d:%d/%d', [mCall.Method, mCall.Position.Line, mCall.Position.Character,
      mCall.BreakLine])];
  end;
  Result := string.Join(' ', mParts);
end;

procedure TSemanticsDataAccessCallsTests.Setup;
begin
  FTree := TSyntaxTreeCache.Parse(cUnit, nil);
  FCalls := TDataAccessCalls.Collect(FTree, TArray<string>.Create('open', 'EXECSQL', 'Post', 'Get'));
end;

procedure TSemanticsDataAccessCallsTests.TearDown;
begin
  FCalls := nil;
  FreeAndNil(FTree);
end;

procedure TSemanticsDataAccessCallsTests.CallsWithAndWithoutParentheses;
begin
  // Groß-/Kleinschreibung der Liste egal; with, ohne Empfänger und @X.Open zählen nicht.
  Assert.AreEqual('ExecSQL@5:11/5 Open@6:19/6 Post@7:12/7 ExecSQL@9:8/9', Describe);
end;

procedure TSemanticsDataAccessCallsTests.ArgumentsAndRoutine;
begin
  Assert.AreEqual(4, Integer(Length(FCalls)));
  Assert.AreEqual(0, Integer(Length(FCalls[0].Arguments)));
  Assert.AreEqual(0, Integer(Length(FCalls[1].Arguments)));
  Assert.AreEqual(2, Integer(Length(FCalls[2].Arguments)));
  Assert.AreEqual(1, Integer(Length(FCalls[3].Arguments)));
  Assert.AreEqual('TfrmKunde.Speichern', FCalls[0].Routine);
  Assert.IsTrue(FCalls[0].Receiver.Kind = TSyntaxKind.Identifier);
  Assert.IsTrue(FCalls[1].Receiver.Kind = TSyntaxKind.MemberAccess);
end;

procedure TSemanticsDataAccessCallsTests.BreakLineIsStatementStart;
begin
  // Aufruf in der Bedingung: Halt an der if-Zeile; mehrzeiliger Aufruf: an der ersten Zeile.
  Assert.AreEqual(7, FCalls[2].BreakLine);
  Assert.AreEqual(9, FCalls[3].BreakLine);
  Assert.AreEqual(9, TDataAccessCalls.StatementLine(FCalls[3].Arguments[0]));
end;

procedure TSemanticsDataAccessCallsTests.WithoutReceiverAndAssignmentSkipped;
var
  mCall: TDataAccessCall;
begin
  for mCall in FCalls do
  begin
    Assert.IsTrue(mCall.Position.Line < 11, mCall.Method);
  end;
  Assert.AreEqual(0, Integer(Length(TDataAccessCalls.Collect(nil, TArray<string>.Create('Open')))));
  Assert.AreEqual('', TDataAccessCalls.RoutineOf(FTree.Root));
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticsDataAccessCallsTests);

end.
