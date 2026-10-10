unit Argus.Common.Rules.GoldenCorpus.Tests;

// Tests für den Golden-Korpus und die Quoten (#152), dazu der Abgleich des
// Referenzprojekts mit den eingebauten Regeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGoldenCorpusTests = class
  public
    /// <summary>Prüft das Referenzprojekt einmal vorab; einmalig angelegte Daten der Regeln zählen
    /// sonst als Leck von ReferenceProjectMatchesMarkers.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure MarkersReadExpectedAndNoFinding;
    [Test]
    procedure PlannedIdsSkipComments;
    [Test]
    procedure CompareFindsMissingAndFalseAlarms;
    [Test]
    procedure CompareSkipsPlannedAndRejectsUnknown;
    [Test]
    procedure RatesPerRule;
    [Test]
    procedure RatesRejectInvalidVerdict;
    [Test]
    procedure TimeRulesCoversEveryRule;
    [Test]
    procedure ReferenceProjectMatchesMarkers;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Checker,
  Argus.Common.Rules.Builtin,
  Argus.Common.Rules.GoldenCorpus;

function Finding(const ARuleId: string; ALine: Integer): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(ALine, 2, ALine, 5);
end;

procedure TGoldenCorpusTests.MarkersReadExpectedAndNoFinding;
var
  Markers: TArray<TGoldenMarker>;
begin
  Markers := TGoldenCorpus.Markers('a;'#13#10'b; // ERWARTET: regel-a, regel-b'#13#10'c; // KEIN-TREFFER: regel-a');
  Assert.AreEqual(3, Integer(Length(Markers)));
  Assert.AreEqual(1, Markers[0].Line);
  Assert.AreEqual('regel-a', Markers[0].RuleId);
  Assert.IsTrue(Markers[0].Expected);
  Assert.AreEqual('regel-b', Markers[1].RuleId);
  Assert.AreEqual(2, Markers[2].Line);
  Assert.IsFalse(Markers[2].Expected);
  Assert.AreEqual(0, Integer(Length(TGoldenCorpus.Markers('// Zeilen mit "// ERWARTET: <regel>" markieren'))));
end;

procedure TGoldenCorpusTests.PlannedIdsSkipComments;
var
  Ids: TArray<string>;
begin
  Ids := TGoldenCorpus.PlannedIds('# Kopf'#10#10'empty-except   # #56'#10'  with-statement'#10);
  Assert.AreEqual(2, Integer(Length(Ids)));
  Assert.AreEqual('empty-except', Ids[0]);
  Assert.AreEqual('with-statement', Ids[1]);
end;

procedure TGoldenCorpusTests.CompareFindsMissingAndFalseAlarms;
var
  Markers: TArray<TGoldenMarker>;
  Outcome: TGoldenResult;
begin
  Markers := TGoldenCorpus.Markers('x // ERWARTET: a'#10'y // ERWARTET: b'#10'z // KEIN-TREFFER: a');
  Outcome := TGoldenCorpus.Compare('U.pas', Markers, [Finding('a', 0), Finding('a', 2), Finding('b', 0)],
    ['a', 'b'], nil);
  Assert.IsFalse(Outcome.Passed);
  Assert.AreEqual(1, Integer(Length(Outcome.Missing)));
  Assert.AreEqual('U.pas(2): b erwartet, aber nicht gemeldet', Outcome.Missing[0]);
  Assert.AreEqual(1, Integer(Length(Outcome.FalseAlarms)));
  Assert.AreEqual('U.pas(3): a gemeldet, obwohl KEIN-TREFFER', Outcome.FalseAlarms[0]);
  Assert.IsTrue(TGoldenCorpus.Compare('U.pas', Markers, [Finding('a', 0), Finding('b', 1)], ['a', 'b'],
    nil).Passed);
end;

procedure TGoldenCorpusTests.CompareSkipsPlannedAndRejectsUnknown;
var
  Outcome: TGoldenResult;
begin
  Outcome := TGoldenCorpus.Compare('U.pas', TGoldenCorpus.Markers('x // ERWARTET: geplant'), nil, ['a'],
    ['geplant']);
  Assert.IsTrue(Outcome.Passed);
  Assert.AreEqual(1, Integer(Length(Outcome.Skipped)));
  Outcome := TGoldenCorpus.Compare('U.pas', TGoldenCorpus.Markers('x // KEIN-TREFFER: tippfehler'), nil, ['a'],
    ['geplant']);
  Assert.IsFalse(Outcome.Passed);
  Assert.AreEqual('U.pas(1): tippfehler ist keine bekannte Regel', Outcome.Unknown[0]);
end;

procedure TGoldenCorpusTests.RatesPerRule;
var
  Rates: TArray<TRuleRate>;
begin
  Rates := TGoldenCorpus.Rates('Regel-ID,Datei,Zeile,Bewertung,Datum'#13#10 +
    'unused-local,a.pas,3,richtig,2026-10-08'#13#10 +
    'empty-except,a.pas,9,richtig,2026-10-08'#13#10 +
    'unused-local,b.pas,4,falsch,2026-10-08'#13#10 +
    'unused-local,c.pas,5,richtig,2026-10-08'#13#10);
  Assert.AreEqual(2, Integer(Length(Rates)));
  Assert.AreEqual('empty-except', Rates[0].RuleId);
  Assert.AreEqual(0.0, Rates[0].FalseAlarmRate, 0.0001);
  Assert.AreEqual('unused-local', Rates[1].RuleId);
  Assert.AreEqual(2, Rates[1].Correct);
  Assert.AreEqual(1, Rates[1].Wrong);
  Assert.AreEqual(1 / 3, Rates[1].FalseAlarmRate, 0.0001);
  Assert.AreEqual(0, Integer(Length(TGoldenCorpus.Rates('Regel-ID,Datei,Zeile,Bewertung,Datum'#13#10))));
end;

procedure TGoldenCorpusTests.RatesRejectInvalidVerdict;
begin
  Assert.WillRaise(
    procedure
    begin
      TGoldenCorpus.Rates('Kopf'#10'a,b.pas,1,vielleicht,2026-10-08');
    end, EArgumentException);
end;

procedure TGoldenCorpusTests.TimeRulesCoversEveryRule;
var
  Timings: TArray<TRuleTiming>;
  Rules: TArray<IRule>;
  Index: Integer;
begin
  Rules := BuiltinRules;
  Timings := TGoldenCorpus.TimeRules(Rules, TServerSettings.Default,
    ['unit U;'#10'interface'#10'implementation'#10'end.']);
  Assert.AreEqual(Integer(Length(Rules)), Integer(Length(Timings)));
  for Index := 0 to High(Rules) do
  begin
    Assert.AreEqual(Rules[Index].Descriptor.Id, Timings[Index].RuleId);
    Assert.IsTrue(Timings[Index].Milliseconds >= 0);
  end;
end;

/// <summary>Ordner des Referenzprojekts, gesucht von der Test-EXE aufwärts; '' ohne.</summary>
function ReferenceFolder: string;
var
  Directory: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    Result := TPath.Combine(Directory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
      Exit;
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  Result := '';
end;

procedure TGoldenCorpusTests.WarmUp;
var
  Folder, FileName, Text: string;
  Rules: TArray<IRule>;
  Texts: TArray<string>;
begin
  Folder := ReferenceFolder;
  if Folder = '' then
    Exit;
  Rules := BuiltinRules;
  Texts := nil;
  for FileName in TDirectory.GetFiles(TPath.Combine(Folder, 'Source'), '*.pas') do
  begin
    Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Texts := Texts + [Text];
    TFileChecker.CheckText(Rules, TServerSettings.Default, ExtractFileName(FileName), Text);
  end;
  TGoldenCorpus.TimeRules(Rules, TServerSettings.Default, Texts);
end;

procedure TGoldenCorpusTests.ReferenceProjectMatchesMarkers;
var
  Folder, FileName, Text, Problems, Line: string;
  Rules: TArray<IRule>;
  Rule: IRule;
  Known, Planned, Texts: TArray<string>;
  Outcome: TGoldenResult;
  Timing: TRuleTiming;
  Markers: Integer;
begin
  Folder := ReferenceFolder;
  if Folder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  Rules := BuiltinRules;
  Known := [SyntaxRuleId];
  for Rule in Rules do
    Known := Known + [Rule.Descriptor.Id];
  Planned := TGoldenCorpus.PlannedIds(TFile.ReadAllText(TPath.Combine(Folder, 'geplante-regeln.txt'),
    TEncoding.UTF8));
  Problems := '';
  Texts := nil;
  Markers := 0;
  for FileName in TDirectory.GetFiles(TPath.Combine(Folder, 'Source'), '*.pas') do
  begin
    Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Texts := Texts + [Text];
    Inc(Markers, Length(TGoldenCorpus.Markers(Text)));
    Outcome := TGoldenCorpus.Compare(ExtractFileName(FileName), TGoldenCorpus.Markers(Text),
      TFileChecker.CheckText(Rules, TServerSettings.Default, ExtractFileName(FileName), Text), Known, Planned);
    // Writeln statt CurrentRunner.Log: DUnitX hält Log-Meldungen bis zum Ende des Laufs (Leck-Monitor).
    for Line in Outcome.Skipped do
      System.Writeln('  übersprungen: ', Line);
    for Line in Outcome.Missing + Outcome.FalseAlarms + Outcome.Unknown do
      Problems := Problems + sLineBreak + Line;
  end;
  Assert.IsTrue(Markers > 0, 'Keine Markierungen im Referenzprojekt gefunden');
  // Laufzeit je Regel über den ganzen Korpus, um langsame Regeln zu erkennen.
  for Timing in TGoldenCorpus.TimeRules(Rules, TServerSettings.Default, Texts) do
    System.Writeln(Format('  %s: %.1f ms', [Timing.RuleId, Timing.Milliseconds]));
  Assert.AreEqual('', Problems, 'Golden-Korpus weicht ab:' + Problems);
end;

initialization
  TDUnitX.RegisterTestFixture(TGoldenCorpusTests);

end.
