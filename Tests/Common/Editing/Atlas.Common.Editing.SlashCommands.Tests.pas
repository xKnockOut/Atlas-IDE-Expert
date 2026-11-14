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
    /// <summary>Gemischte Zeilenenden: Zeilen werden an jedem Umbruch getrennt (TTextLines.SplitLines).</summary>
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
  Atlas.Common.Editing.Contract,
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
  mLines: TArray<string>;
  mIndex: Integer;
begin
  mLines := AContext.Text.Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    if Pos('X := 1', mLines[mIndex]) > 0 then
    begin
      AReport.Add(TTextRange.Create(TTextPosition.Create(mIndex, 2), TTextPosition.Create(mIndex, 8)), 'Probe');
    end;
  end;
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
  mName, mArguments: string;
begin
  Assert.IsTrue(TSlashCommandRegistry.Split('  /uses A, B', mName, mArguments));
  Assert.AreEqual('uses', mName);
  Assert.AreEqual('A, B', mArguments);
  Assert.IsTrue(TSlashCommandRegistry.Split('/const! X = 1', mName, mArguments));
  Assert.AreEqual('const!', mName);
  Assert.IsTrue(TSlashCommandRegistry.Split('/guid', mName, mArguments));
  Assert.AreEqual('', mArguments);
  Assert.IsFalse(TSlashCommandRegistry.Split('// Kommentar', mName, mArguments));
  Assert.IsFalse(TSlashCommandRegistry.Split('A / B', mName, mArguments));
  Assert.IsFalse(TSlashCommandRegistry.Split('/ 2', mName, mArguments));
end;

procedure TSlashCommandsTests.UsesRunsThroughRegistry;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Source('/uses System.Classes'), TTextPosition.Create(6, 0),
    nil, nil, mEdits));
  Assert.AreEqual(2, Integer(Length(mEdits)));
  Assert.IsTrue(Pos('Classes', mEdits[0].NewText) > 0, mEdits[0].NewText);
  // Die Befehlszeile verschwindet samt Zeilenende.
  Assert.AreEqual(5, mEdits[1].Range.StartPos.Line);
  Assert.AreEqual(6, mEdits[1].Range.EndPos.Line);
  Assert.AreEqual('', mEdits[1].NewText);
end;

procedure TSlashCommandsTests.UnknownCommandStaysWithHint;
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Source('/gibtsnicht X'), TTextPosition.Create(6, 0),
    nil, nil, mEdits));
  Assert.AreEqual(0, Integer(Length(mEdits)));
  mProblems := TSlashCommandRegistry.Shared.Problems(Source('  /gibtsnicht X'), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual(5, mProblems[0].Range.StartPos.Line);
  Assert.AreEqual(2, mProblems[0].Range.StartPos.Character);
  Assert.AreEqual('Unbekannter Schnellbefehl /gibtsnicht', mProblems[0].Message);
  // Falsche Argumente: Grund des Befehls.
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Source('/uses 1A'), nil))));
end;

procedure TSlashCommandsTests.MixedLineBreaksKeepLineNumbers;
var
  mProblems: TArray<TSlashProblem>;
begin
  // CRLF-Datei mit einer LF-Zeile davor: der Befehl steht trotzdem in Zeile 3.
  mProblems := TSlashCommandRegistry.Shared.Problems('unit U;'#13#10'interface'#10'implementation'#13#10 +
    '  /gibtsnicht X'#13#10'end.', nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual(3, mProblems[0].Range.StartPos.Line);
end;

procedure TSlashCommandsTests.CommandInStringOrCommentIsIgnored;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := 'unit U;'#10'interface'#10'implementation'#10'{'#10'/uses System.Classes'#10#10'}'#10'end.';
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(5, 0), nil, nil, mEdits));
  Assert.AreEqual(0, Integer(Length(TSlashCommandRegistry.Shared.Problems(mText, nil))));
  mText := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'asm'#10'/uses System.Classes'#10#10 +
    'end;'#10'end.';
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(mText, TTextPosition.Create(6, 0), nil, nil, mEdits));
  mText := 'unit U;'#10'interface'#10'implementation'#10'const S = '''''''#10'/gibtsnicht X'#10 +
    ''''''';'#10'end.';
  Assert.AreEqual(0, Integer(Length(TSlashCommandRegistry.Shared.Problems(mText, nil))));
end;

procedure TSlashCommandsTests.DisabledCommandIsSkipped;
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(Source('/uses System.Classes'), TTextPosition.Create(6, 0),
    nil, ['USES'], mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(Source('/uses System.Classes'), ['uses']);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.IsTrue(Pos('abgeschaltet', mProblems[0].Message) > 0, mProblems[0].Message);
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
  mRegistry: TSlashCommandRegistry;
  mCommand: TSlashCommand;
begin
  mRegistry := TSlashCommandRegistry.Create;
  try
    mCommand := Default(TSlashCommand);
    mCommand.Name := 'probe';
    mRegistry.Register(mCommand);
    Assert.WillRaise(
      procedure
      begin
        mRegistry.Register(mCommand);
      end, EArgumentException);
    Assert.AreEqual(1, Integer(Length(mRegistry.Commands)));
  finally
    mRegistry.Free;
  end;
end;

procedure TSlashCommandsTests.RuleReportsUnknownCommand;
begin
  TRuleAssert.Reports(TSlashCommandRule.Create, Source('/gibtsnicht'));
  TRuleAssert.Silent(TSlashCommandRule.Create, Source('// /gibtsnicht'));
end;

procedure TSlashCommandsTests.RuleReportsIgnoreWithoutHit;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  %s'#10'  %s'#10'end;'#10'end.';

  function HintsOf(const ACommand, ANext: string): TArray<string>;
  var
    mFinding: TRuleFinding;
  begin
    Result := nil;
    for mFinding in TRuleAssert.FindingsOfAll([TSlashCommandRule.Create, TProbeLineRule.Create],
      Format(cText, [ACommand, ANext]), '') do
    begin
      if mFinding.RuleId = 'slash-command' then
      begin
        Result := Result + [mFinding.Message];
      end;
    end;
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
