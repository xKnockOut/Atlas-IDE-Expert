unit Atlas.Common.Editing.DatabaseCommands.Tests;

// Tests für die Schnellbefehle /sql, /params, /loop und /transaction (#302):
// je Befehl ein positiver Fall und einer am falschen Ort.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDatabaseCommandsTests = class
  public
    [Test]
    procedure SqlWithTwoParams;
    [Test]
    procedure SqlLongUsesLineBreaks;
    [Test]
    procedure SqlAdoUsesParameters;
    [Test]
    procedure ParamsAddsMissing;
    [Test]
    procedure ParamsReportsExtra;
    [Test]
    procedure LoopWrapsWithNext;
    [Test]
    procedure TransactionWraps;
    [Test]
    procedure TransactionAdo;
    [Test]
    procedure OutsideRoutineFails;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract;

const
  cRoutineUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'implementation'#10 +                           // 2
    'procedure Run;'#10 +                           // 3
    'var'#10 +                                      // 4
    '  Q: TFDQuery;'#10 +                           // 5
    '  Ado: TADOQuery;'#10 +                        // 6
    '  Con: TADOConnection;'#10 +                   // 7
    'begin'#10 +                                    // 8
    '  %s'#10 +                                     // 9 Befehl
    '  Q.ParamByName(''Nr'').Value := 1;'#10 +      // 10
    '  Q.Open;'#10 +                                // 11
    'end;'#10 +                                     // 12
    'end.';

function Run(const ACommand: string; out AEdits: TArray<TRuleEdit>; const AVersion: string): Boolean; overload;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(Format(cRoutineUnit, [ACommand]), TTextPosition.Create(10, 0),
    TSlashEnvironment.Create(nil, nil, nil, AVersion, '', nil), AEdits);
end;

function Run(const ACommand: string; out AEdits: TArray<TRuleEdit>): Boolean; overload;
begin
  Result := Run(ACommand, AEdits, '');
end;

procedure TDatabaseCommandsTests.SqlWithTwoParams;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run('/sql Q select * from Kunde where Nr = :Nr and Ort = :Ort', mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(
    '  Q.SQL.Text := ''select * from Kunde where Nr = :Nr and Ort = :Ort'';'#10 +
    '  Q.ParamByName(''Nr'').Value := ;'#10 +
    '  Q.ParamByName(''Ort'').Value := ;'#10, mEdits[0].NewText);
  Assert.AreEqual(9, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(10, mEdits[0].Range.EndPos.Line);
end;

procedure TDatabaseCommandsTests.SqlLongUsesLineBreaks;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run('/sql Q select Kunde.Nr, Kunde.Name, Kunde.Ort from Kunde where Kunde.Ort = :Ort ' +
    'order by Kunde.Name', mEdits, '22.0'));
  Assert.AreEqual(
    '  Q.SQL.Text :='#10 +
    '    ''select Kunde.Nr, Kunde.Name, Kunde.Ort'' + sLineBreak +'#10 +
    '    ''from Kunde'' + sLineBreak +'#10 +
    '    ''where Kunde.Ort = :Ort'' + sLineBreak +'#10 +
    '    ''order by Kunde.Name'';'#10 +
    '  Q.ParamByName(''Ort'').Value := ;'#10, mEdits[0].NewText);
  Assert.IsTrue(Run('/sql Q select Kunde.Nr, Kunde.Name, Kunde.Ort from Kunde where Kunde.Ort = :Ort ' +
    'order by Kunde.Name', mEdits, '23.0'));
  Assert.StartsWith('  Q.SQL.Text :='#10'    ''''''', mEdits[0].NewText);
end;

procedure TDatabaseCommandsTests.SqlAdoUsesParameters;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run('/sql Ado select * from T where A = :A', mEdits));
  Assert.AreEqual(
    '  Ado.SQL.Text := ''select * from T where A = :A'';'#10 +
    '  Ado.Parameters.ParamByName(''A'').Value := ;'#10, mEdits[0].NewText);
end;

procedure TDatabaseCommandsTests.ParamsAddsMissing;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := Format(cRoutineUnit, ['/params Q']);
  mText := StringReplace(mText, 'begin'#10, 'begin'#10'  Q.SQL.Text := ''select * from T where Nr = :Nr and A = :A'';'#10,
    []);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(11, 0), nil, nil, mEdits));
  Assert.AreEqual('  Q.ParamByName(''A'').Value := ;'#10, mEdits[0].NewText);
end;

procedure TDatabaseCommandsTests.ParamsReportsExtra;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
  mProblems: TArray<TSlashProblem>;
begin
  mText := Format(cRoutineUnit, ['/params Q']);
  mText := StringReplace(mText, 'begin'#10, 'begin'#10'  Q.SQL.Text := ''select * from T'';'#10, []);
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(11, 0), nil, nil, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(mText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.Contains(mProblems[0].Message, 'Nr');
  // Ohne SQL-Text passt /params nicht.
  Assert.IsFalse(Run('/params Q', mEdits));
end;

procedure TDatabaseCommandsTests.LoopWrapsWithNext;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run('/loop Q', mEdits));
  Assert.AreEqual(
    '  Q.DisableControls;'#10 +
    '  try'#10 +
    '    Q.First;'#10 +
    '    while not Q.Eof do'#10 +
    '    begin'#10 +
    '      Q.ParamByName(''Nr'').Value := 1;'#10 +
    '      Q.Open;'#10 +
    '      Q.Next;'#10 +
    '    end;'#10 +
    '  finally'#10 +
    '    Q.EnableControls;'#10 +
    '  end;'#10, mEdits[0].NewText);
end;

procedure TDatabaseCommandsTests.TransactionWraps;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run('/transaction FDCon', mEdits));
  Assert.AreEqual(
    '  FDCon.StartTransaction;'#10 +
    '  try'#10 +
    '    Q.ParamByName(''Nr'').Value := 1;'#10 +
    '    Q.Open;'#10 +
    '    FDCon.Commit;'#10 +
    '  except'#10 +
    '    FDCon.Rollback;'#10 +
    '    raise;'#10 +
    '  end;'#10, mEdits[0].NewText);
end;

procedure TDatabaseCommandsTests.TransactionAdo;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run('/transaction Con', mEdits));
  Assert.StartsWith('  Con.BeginTrans;'#10, mEdits[0].NewText);
  Assert.Contains(mEdits[0].NewText, '    Con.RollbackTrans;'#10);
end;

procedure TDatabaseCommandsTests.OutsideRoutineFails;
const
  cOutside = 'unit U;'#10'interface'#10'implementation'#10'%s'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
  mCommand: string;
begin
  for mCommand in TArray<string>.Create('/sql Q select 1', '/params Q', '/loop Q', '/transaction Con') do
  begin
    Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Format(cOutside, [mCommand]), TTextPosition.Create(4, 0),
      nil, nil, mEdits), mCommand);
  end;
  Assert.IsFalse(Run('/sql Q', mEdits));
end;

initialization
  TDUnitX.RegisterTestFixture(TDatabaseCommandsTests);

end.
