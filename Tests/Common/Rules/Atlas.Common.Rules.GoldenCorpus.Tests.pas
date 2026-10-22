unit Atlas.Common.Rules.GoldenCorpus.Tests;

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
    procedure PlannedIdsNeedIssue;
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
    [Test]
    procedure MutationsParseAndReportBadLines;
    [Test]
    procedure MutateNeedsUniqueSearchAndUnescapes;
    [Test]
    procedure DetectedNeedsMoreFindingsOfRule;
    [Test]
    procedure HitRatesPerRule;
    [Test]
    procedure ReferenceProjectMutationsAreFound;
    [Test]
    procedure ReferenceRatingsAreValid;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.GoldenCorpus,
  Atlas.Common.Projects.PackageReader,
  System.StrUtils;

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

procedure TGoldenCorpusTests.PlannedIdsNeedIssue;
var
  Ids: TArray<string>;
begin
  Ids := TGoldenCorpus.PlannedWithoutIssue('# Kopf #1'#10'possible-leak  # #56'#10'with-statement  # noch offen'#10 +
    'unreachable-code'#10'format-args # #'#10);
  Assert.AreEqual(3, Integer(Length(Ids)));
  Assert.AreEqual('with-statement', Ids[0]);
  Assert.AreEqual('unreachable-code', Ids[1]);
  Assert.AreEqual('format-args', Ids[2]);
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

/// <summary>Text einer Datei des Referenzprojekts ohne BOM, wie ihn der Server liest.</summary>
function ReadSource(const AFileName: string): string;
var
  Format: TFileFormat;
begin
  Result := TFileEncoding.Decode(TFile.ReadAllBytes(AFileName), Format);
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
    Text := ReadSource(FileName);
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
  Text := ReadSource(TPath.Combine(Folder, 'geplante-regeln.txt'));
  Planned := TGoldenCorpus.PlannedIds(Text);
  // Jede geplante ID gehört zu einem offenen Issue (#94).
  Problems := '';
  for Line in TGoldenCorpus.PlannedWithoutIssue(Text) do
    Problems := Problems + sLineBreak + Line + ' in geplante-regeln.txt nennt kein Issue';
  Texts := nil;
  Markers := 0;
  for FileName in TDirectory.GetFiles(TPath.Combine(Folder, 'Source'), '*.pas') do
  begin
    Text := ReadSource(FileName);
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

procedure TGoldenCorpusTests.MutationsParseAndReportBadLines;
var
  Mutations: TArray<TRuleMutation>;
  Errors: TArray<string>;
begin
  Mutations := TGoldenCorpus.Mutations('# Kommentar'#10#10'self-assignment | A.pas | X := Y; | X := X;'#10 +
    'empty-except | B.pas | a \| b | c'#10'kaputt | A.pas'#10, Errors);
  Assert.AreEqual(2, Integer(Length(Mutations)));
  Assert.AreEqual('self-assignment', Mutations[0].RuleId);
  Assert.AreEqual('A.pas', Mutations[0].FileName);
  Assert.AreEqual('X := Y;', Mutations[0].Search);
  Assert.AreEqual('X := X;', Mutations[0].Replacement);
  Assert.AreEqual(3, Mutations[0].Line);
  // \| trennt nicht.
  Assert.AreEqual('a \| b', Mutations[1].Search);
  Assert.AreEqual(1, Integer(Length(Errors)));
  Assert.IsTrue(Pos('Zeile 5', Errors[0]) > 0, Errors[0]);
end;

procedure TGoldenCorpusTests.MutateNeedsUniqueSearchAndUnescapes;
var
  Mutation: TRuleMutation;
  Mutated: string;
begin
  Mutation := Default(TRuleMutation);
  Mutation.Search := 'A := 1;\nB';
  Mutation.Replacement := 'A := ''\u202E'';\nB';
  Assert.IsTrue(TGoldenCorpus.Mutate('X'#13#10'A := 1;'#13#10'B;', Mutation, Mutated));
  Assert.AreEqual('X'#13#10'A := ''' + Char($202E) + ''';'#13#10'B;', Mutated);
  // Zweimal vorhanden oder fehlend: keine Mutation.
  Mutation.Search := 'A';
  Assert.IsFalse(TGoldenCorpus.Mutate('A A', Mutation, Mutated));
  Assert.IsFalse(TGoldenCorpus.Mutate('B', Mutation, Mutated));
end;

procedure TGoldenCorpusTests.DetectedNeedsMoreFindingsOfRule;
begin
  Assert.IsTrue(TGoldenCorpus.Detected([Finding('a', 1)], [Finding('a', 1), Finding('a', 4)], 'a'));
  Assert.IsFalse(TGoldenCorpus.Detected([Finding('a', 1)], [Finding('a', 1), Finding('b', 4)], 'a'));
  Assert.IsFalse(TGoldenCorpus.Detected(nil, nil, 'a'));
end;

procedure TGoldenCorpusTests.HitRatesPerRule;
var
  Mutations: TArray<TRuleMutation>;
  Rates: TArray<TRuleHitRate>;
begin
  SetLength(Mutations, 3);
  Mutations[0].RuleId := 'b';
  Mutations[1].RuleId := 'a';
  Mutations[2].RuleId := 'b';
  Rates := TGoldenCorpus.HitRates(Mutations, [True, False, False]);
  Assert.AreEqual(2, Integer(Length(Rates)));
  Assert.AreEqual('a', Rates[0].RuleId);
  Assert.AreEqual(0.0, Rates[0].HitRate, 0.001);
  Assert.AreEqual(2, Rates[1].Mutations);
  Assert.AreEqual(0.5, Rates[1].HitRate, 0.001);
  Mutations := nil;
end;

/// <summary>Standardeinstellungen, dazu ADescriptor ausdrücklich eingeschaltet (auch experimentelle und
/// freiwillige Regeln) und jede Konfidenz gemeldet: Die Mutation misst, ob die Regel den Fehler überhaupt
/// erkennt, nicht die Schwelle des Projekts.</summary>
function MutationSettings(const ADescriptor: TRuleDescriptor): TServerSettings;
var
  Setting: TRuleSetting;
begin
  Result := TServerSettings.Default;
  Setting := Default(TRuleSetting);
  Setting.Id := ADescriptor.Id;
  Setting.Severity := ADescriptor.DefaultSeverity;
  Result.Rules := Result.Rules + [Setting];
  Result.MinConfidence := TRuleConfidence.Low;
  Result.MinConfidenceGiven := True;
end;

procedure TGoldenCorpusTests.ReferenceProjectMutationsAreFound;
var
  Folder, FileName, Text, Mutated, Problems, Line: string;
  Rules: TArray<IRule>;
  Rule: IRule;
  Known, Errors: TArray<string>;
  Mutations: TArray<TRuleMutation>;
  Mutation: TRuleMutation;
  Found: TArray<Boolean>;
  Rate: TRuleHitRate;
  Detected: Boolean;
  Settings: TServerSettings;
  RuleIndex: Integer;
  Packages: TArray<TPackageSource>;
  Project: TCheckProject;
begin
  Folder := ReferenceFolder;
  if Folder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  Rules := BuiltinRules;
  // Units der Packages RefRuntime und RefDesign prüfen wie der Linter als Package-Units (#943).
  Packages := nil;
  for FileName in TDirectory.GetFiles(Folder, '*.dpk') do
    Packages := Packages + [TPackageReader.Read(ReadSource(FileName))];
  Known := nil;
  for Rule in Rules do
    Known := Known + [Rule.Descriptor.Id];
  Mutations := TGoldenCorpus.Mutations(ReadSource(TPath.Combine(Folder, 'mutationen.txt')),
    Errors);
  Problems := '';
  for Line in Errors do
    Problems := Problems + sLineBreak + 'mutationen.txt ' + Line;
  Assert.IsTrue(Length(Mutations) > 0, 'Keine Mutationen gefunden');
  Found := nil;
  for Mutation in Mutations do
  begin
    Detected := False;
    FileName := TPath.Combine(TPath.Combine(Folder, 'Source'), Mutation.FileName);
    RuleIndex := IndexText(Mutation.RuleId, Known);
    if RuleIndex < 0 then
      Problems := Problems + sLineBreak + Format('Zeile %d: unbekannte Regel %s', [Mutation.Line, Mutation.RuleId])
    else if not TFile.Exists(FileName) then
      Problems := Problems + sLineBreak + Format('Zeile %d: Datei %s fehlt', [Mutation.Line, Mutation.FileName])
    else
    begin
      Text := ReadSource(FileName);
      if not TGoldenCorpus.Mutate(Text, Mutation, Mutated) then
        Problems := Problems + sLineBreak + Format('Zeile %d: Suchtext nicht genau einmal in %s',
          [Mutation.Line, Mutation.FileName])
      else
      begin
        Settings := MutationSettings(Rules[RuleIndex].Descriptor);
        Project := TFileChecker.PackageOf(Packages, ChangeFileExt(Mutation.FileName, ''));
        Detected := TGoldenCorpus.Detected(TFileChecker.CheckText(Rules, Settings, Mutation.FileName, Text, Project),
          TFileChecker.CheckText(Rules, Settings, Mutation.FileName, Mutated, Project), Mutation.RuleId);
        if not Detected then
          Problems := Problems + sLineBreak + Format('Zeile %d: %s findet die Mutation in %s nicht',
            [Mutation.Line, Mutation.RuleId, Mutation.FileName]);
      end;
    end;
    Found := Found + [Detected];
  end;
  // Trefferquote je Regel ins Protokoll (wie die Laufzeit oben).
  for Rate in TGoldenCorpus.HitRates(Mutations, Found) do
    System.Writeln(Format('  %s: %d von %d gefunden', [Rate.RuleId, Rate.Found, Rate.Mutations]));
  Assert.AreEqual('', Problems, 'Mutationen:' + Problems);
end;

procedure TGoldenCorpusTests.ReferenceRatingsAreValid;
var
  Folder, Problems: string;
  Known: TArray<string>;
  Rule: IRule;
  Rates: TArray<TRuleRate>;
  Rate: TRuleRate;
begin
  Folder := ReferenceFolder;
  if Folder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  Known := nil;
  for Rule in BuiltinRules do
    Known := Known + [Rule.Descriptor.Id];
  // Rates wirft bei ungültiger Bewertung; die Quote ist so aus der Datei reproduzierbar.
  Rates := TGoldenCorpus.Rates(ReadSource(TPath.Combine(Folder, 'bewertungen.csv')));
  Assert.IsTrue(Length(Rates) > 0, 'bewertungen.csv enthält keine Bewertungen');
  Problems := '';
  for Rate in Rates do
  begin
    if IndexText(Rate.RuleId, Known) < 0 then
      Problems := Problems + sLineBreak + 'unbekannte Regel ' + Rate.RuleId;
    System.Writeln(Format('  %s: %d richtig, %d falsch, Fehlalarmquote %.1f %%',
      [Rate.RuleId, Rate.Correct, Rate.Wrong, Rate.FalseAlarmRate * 100], TFormatSettings.Invariant));
  end;
  Assert.AreEqual('', Problems, 'bewertungen.csv:' + Problems);
end;

initialization
  TDUnitX.RegisterTestFixture(TGoldenCorpusTests);

end.
