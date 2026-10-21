unit Atlas.Common.Editing.SlashCommands.Tests;

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
    /// <summary>Gemischte Zeilenenden: Zeilen werden an jedem Umbruch getrennt (TTextLines.SplitLines, D-03).</summary>
    [Test]
    procedure MixedLineBreaksKeepLineNumbers;
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
    [Test]
    procedure RuleReportsIgnoreWithoutHit;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.MaintenanceCommands,
  Atlas.Common.Rules.Builtin.SlashCommands,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Meldet "probe-line" in jeder Zeile mit "X := 1".</summary>
  TProbeLineRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TProbeLineRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('probe-line', TRuleSeverity.Warning, 'Probe');
end;

procedure TProbeLineRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  Index: Integer;
begin
  Lines := AContext.Text.Split([#10]);
  for Index := 0 to High(Lines) do
    if Pos('X := 1', Lines[Index]) > 0 then
      AReport.Add(TTextRange.Create(TTextPosition.Create(Index, 2), TTextPosition.Create(Index, 8)), 'Probe');
end;

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

procedure TSlashCommandsTests.MixedLineBreaksKeepLineNumbers;
var
  Problems: TArray<TSlashProblem>;
begin
  // CRLF-Datei mit einer LF-Zeile davor: der Befehl steht trotzdem in Zeile 3.
  Problems := TSlashCommandRegistry.Shared.Problems('unit U;'#13#10'interface'#10'implementation'#13#10 +
    '  /gibtsnicht X'#13#10'end.', nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual(3, Problems[0].Range.StartPos.Line);
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

procedure TSlashCommandsTests.RuleReportsIgnoreWithoutHit;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  %s'#10'  %s'#10'end;'#10'end.';

  function HintsOf(const ACommand, ANext: string): TArray<string>;
  var
    Finding: TRuleFinding;
  begin
    Result := nil;
    for Finding in TRuleAssert.FindingsOfAll([TSlashCommandRule.Create, TProbeLineRule.Create],
      Format(Text, [ACommand, ANext]), '') do
      if Finding.RuleId = 'slash-command' then
        Result := Result + [Finding.Message];
  end;

begin
  // #297: Die Regel trifft darunter, also kein Hinweis.
  Assert.AreEqual(0, Integer(Length(HintsOf('/ignore probe-line', 'X := 1;'))));
  Assert.AreEqual(1, Integer(Length(HintsOf('/ignore probe-line', 'Y := 2;'))));
  Assert.AreEqual(Format(IgnoreNoHitHint, ['probe-line']), HintsOf('/ignore Probe-Line Grund', 'Y := 2;')[0]);
  // Nicht gelaufene Regeln und Muster lassen sich nicht beurteilen.
  Assert.AreEqual(0, Integer(Length(HintsOf('/ignore other-rule', 'Y := 2;'))));
  Assert.AreEqual(0, Integer(Length(HintsOf('/ignore probe-*', 'Y := 2;'))));
  Assert.AreEqual(0, Integer(Length(HintsOf('// /ignore probe-line', 'Y := 2;'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TSlashCommandsTests);

end.
