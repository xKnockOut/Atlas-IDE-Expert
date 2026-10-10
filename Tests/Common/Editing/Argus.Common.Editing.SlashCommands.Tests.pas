unit Argus.Common.Editing.SlashCommands.Tests;

// Tests für den Befehlsrahmen der Schnellbefehle (#293).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSlashCommandsTests = class
  public
    /// <summary>Legt das gemeinsame Register vorab an, sonst zählt es als Leck des ersten Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure SplitsCommandLines;
    [Test]
    procedure UsesRunsThroughRegistry;
    [Test]
    procedure UnknownCommandStaysWithHint;
    [Test]
    procedure CommandInStringOrCommentIsIgnored;
    [Test]
    procedure DisabledCommandIsSkipped;
    [Test]
    procedure MatchingListsCommands;
    [Test]
    procedure RegisterRejectsDuplicates;
    [Test]
    procedure RuleReportsUnknownCommand;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Editing.SlashCommands,
  Argus.Common.Rules.Builtin.SlashCommands,
  Argus.Tests.RuleAssert;

function Source(const ACommandLine: string): string;
begin
  Result := 'unit U;'#10 +          // 0
    'interface'#10 +                // 1
    'implementation'#10 +           // 2
    'uses'#10 +                     // 3
    '  System.SysUtils;'#10 +       // 4
    ACommandLine + #10 +            // 5
    #10 +                           // 6 (Cursor nach Enter)
    'end.';
end;

procedure TSlashCommandsTests.WarmUp;
begin
  Assert.IsNotNull(TSlashCommandRegistry.Shared);
end;

procedure TSlashCommandsTests.SplitsCommandLines;
var
  Name, Arguments: string;
begin
  Assert.IsTrue(TSlashCommandRegistry.Split('  /uses A, B', Name, Arguments));
  Assert.AreEqual('uses', Name);
  Assert.AreEqual('A, B', Arguments);
  Assert.IsTrue(TSlashCommandRegistry.Split('/const! X = 1', Name, Arguments));
  Assert.AreEqual('const!', Name);
  Assert.IsTrue(TSlashCommandRegistry.Split('/guid', Name, Arguments));
  Assert.AreEqual('', Arguments);
  Assert.IsFalse(TSlashCommandRegistry.Split('// Kommentar', Name, Arguments));
  Assert.IsFalse(TSlashCommandRegistry.Split('A / B', Name, Arguments));
  Assert.IsFalse(TSlashCommandRegistry.Split('/ 2', Name, Arguments));
end;

procedure TSlashCommandsTests.UsesRunsThroughRegistry;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Source('/uses System.Classes'), TTextPosition.Create(6, 0),
    nil, nil, Edits));
  Assert.AreEqual(2, Integer(Length(Edits)));
  Assert.IsTrue(Pos('Classes', Edits[0].NewText) > 0, Edits[0].NewText);
  // Die Befehlszeile verschwindet samt Zeilenende.
  Assert.AreEqual(5, Edits[1].Range.StartPos.Line);
  Assert.AreEqual(6, Edits[1].Range.EndPos.Line);
  Assert.AreEqual('', Edits[1].NewText);
end;

procedure TSlashCommandsTests.UnknownCommandStaysWithHint;
var
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Source('/gibtsnicht X'), TTextPosition.Create(6, 0),
    nil, nil, Edits));
  Assert.AreEqual(0, Integer(Length(Edits)));
  Problems := TSlashCommandRegistry.Shared.Problems(Source('  /gibtsnicht X'), nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual(5, Problems[0].Range.StartPos.Line);
  Assert.AreEqual(2, Problems[0].Range.StartPos.Character);
  Assert.AreEqual('Unbekannter Schnellbefehl /gibtsnicht', Problems[0].Message);
  // Falsche Argumente: Grund des Befehls.
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Source('/uses 1A'), nil))));
end;

procedure TSlashCommandsTests.CommandInStringOrCommentIsIgnored;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := 'unit U;'#10'interface'#10'implementation'#10'{'#10'/uses System.Classes'#10#10'}'#10'end.';
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Text, TTextPosition.Create(5, 0), nil, nil, Edits));
  Assert.AreEqual(0, Integer(Length(TSlashCommandRegistry.Shared.Problems(Text, nil))));
  Text := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'asm'#10'/uses System.Classes'#10#10 +
    'end;'#10'end.';
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Text, TTextPosition.Create(6, 0), nil, nil, Edits));
  Text := 'unit U;'#10'interface'#10'implementation'#10'const S = '''''''#10'/gibtsnicht X'#10 +
    ''''''';'#10'end.';
  Assert.AreEqual(0, Integer(Length(TSlashCommandRegistry.Shared.Problems(Text, nil))));
end;

procedure TSlashCommandsTests.DisabledCommandIsSkipped;
var
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Source('/uses System.Classes'), TTextPosition.Create(6, 0),
    nil, ['USES'], Edits));
  Problems := TSlashCommandRegistry.Shared.Problems(Source('/uses System.Classes'), ['uses']);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.IsTrue(Pos('abgeschaltet', Problems[0].Message) > 0, Problems[0].Message);
end;

procedure TSlashCommandsTests.MatchingListsCommands;
begin
  Assert.IsTrue(Length(TSlashCommandRegistry.Shared.Matching('', nil)) >= 1);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Matching('us', nil))));
  Assert.AreEqual('uses', TSlashCommandRegistry.Shared.Matching('us', nil)[0].Name);
  Assert.AreEqual(0, Integer(Length(TSlashCommandRegistry.Shared.Matching('us', ['uses']))));
  Assert.AreEqual(0, Integer(Length(TSlashCommandRegistry.Shared.Matching('xy', nil))));
end;

procedure TSlashCommandsTests.RegisterRejectsDuplicates;
var
  Registry: TSlashCommandRegistry;
  Command: TSlashCommand;
begin
  Registry := TSlashCommandRegistry.Create;
  try
    Command := Default(TSlashCommand);
    Command.Name := 'probe';
    Registry.Register(Command);
    Assert.WillRaise(
      procedure
      begin
        Registry.Register(Command);
      end, EArgumentException);
    Assert.AreEqual(1, Integer(Length(Registry.Commands)));
  finally
    Registry.Free;
  end;
end;

procedure TSlashCommandsTests.RuleReportsUnknownCommand;
begin
  TRuleAssert.Reports(TSlashCommandRule.Create, Source('/gibtsnicht'));
  TRuleAssert.Silent(TSlashCommandRule.Create, Source('// /gibtsnicht'));
end;

initialization
  TDUnitX.RegisterTestFixture(TSlashCommandsTests);

end.
