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
    /// <summary>Wie oben mit Symbolindex über alle Units und RTL-Stubs (#1112): ERWARTET-INDEX zählt mit.
    /// </summary>
    [Test]
    procedure ReferenceProjectWithIndexMatchesMarkers;
    [Test]
    procedure IndexMarkersOnlyWithIndex;
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
    /// <summary>Alle Mutationen mit englischen Texten (#1458): Meldungen, Korrekturtitel und Regeltitel ohne
    /// deutsche Wörter, außer solchen aus dem geprüften Quelltext.</summary>
    [Test]
    procedure EnglishTextsWithoutGerman;
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
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Rules.GoldenCorpus,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RtlStubs,
  Atlas.Common.Localization.Texts,
  System.StrUtils;

function Finding(const ARuleId: string; ALine: Integer): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(ALine, 2, ALine, 5);
end;

procedure TGoldenCorpusTests.MarkersReadExpectedAndNoFinding;
var
  mMarkers: TArray<TGoldenMarker>;
begin
  mMarkers := TGoldenCorpus.Markers('a;'#13#10'b; // ERWARTET: regel-a, regel-b'#13#10'c; // KEIN-TREFFER: regel-a');
  Assert.AreEqual(3, Integer(Length(mMarkers)));
  Assert.AreEqual(1, mMarkers[0].Line);
  Assert.AreEqual('regel-a', mMarkers[0].RuleId);
  Assert.IsTrue(mMarkers[0].Expected);
  Assert.AreEqual('regel-b', mMarkers[1].RuleId);
  Assert.AreEqual(2, mMarkers[2].Line);
  Assert.IsFalse(mMarkers[2].Expected);
  Assert.AreEqual(0, Integer(Length(TGoldenCorpus.Markers('// Zeilen mit "// ERWARTET: <regel>" markieren'))));
end;

procedure TGoldenCorpusTests.PlannedIdsSkipComments;
var
  mIds: TArray<string>;
begin
  mIds := TGoldenCorpus.PlannedIds('# Kopf'#10#10'empty-except   # #56'#10'  with-statement'#10);
  Assert.AreEqual(2, Integer(Length(mIds)));
  Assert.AreEqual('empty-except', mIds[0]);
  Assert.AreEqual('with-statement', mIds[1]);
end;

procedure TGoldenCorpusTests.PlannedIdsNeedIssue;
var
  mIds: TArray<string>;
begin
  mIds := TGoldenCorpus.PlannedWithoutIssue('# Kopf #1'#10'possible-leak  # #56'#10'with-statement  # noch offen'#10 +
    'unreachable-code'#10'format-args # #'#10);
  Assert.AreEqual(3, Integer(Length(mIds)));
  Assert.AreEqual('with-statement', mIds[0]);
  Assert.AreEqual('unreachable-code', mIds[1]);
  Assert.AreEqual('format-args', mIds[2]);
end;

procedure TGoldenCorpusTests.CompareFindsMissingAndFalseAlarms;
var
  mMarkers: TArray<TGoldenMarker>;
  mOutcome: TGoldenResult;
begin
  mMarkers := TGoldenCorpus.Markers('x // ERWARTET: a'#10'y // ERWARTET: b'#10'z // KEIN-TREFFER: a');
  mOutcome := TGoldenCorpus.Compare('U.pas', mMarkers, [Finding('a', 0), Finding('a', 2), Finding('b', 0)],
    ['a', 'b'], nil);
  Assert.IsFalse(mOutcome.Passed);
  Assert.AreEqual(1, Integer(Length(mOutcome.Missing)));
  Assert.AreEqual('U.pas(2): b erwartet, aber nicht gemeldet', mOutcome.Missing[0]);
  Assert.AreEqual(1, Integer(Length(mOutcome.FalseAlarms)));
  Assert.AreEqual('U.pas(3): a gemeldet, obwohl KEIN-TREFFER', mOutcome.FalseAlarms[0]);
  Assert.IsTrue(TGoldenCorpus.Compare('U.pas', mMarkers, [Finding('a', 0), Finding('b', 1)], ['a', 'b'],
    nil).Passed);
end;

procedure TGoldenCorpusTests.CompareSkipsPlannedAndRejectsUnknown;
var
  mOutcome: TGoldenResult;
begin
  mOutcome := TGoldenCorpus.Compare('U.pas', TGoldenCorpus.Markers('x // ERWARTET: geplant'), nil, ['a'],
    ['geplant']);
  Assert.IsTrue(mOutcome.Passed);
  Assert.AreEqual(1, Integer(Length(mOutcome.Skipped)));
  mOutcome := TGoldenCorpus.Compare('U.pas', TGoldenCorpus.Markers('x // KEIN-TREFFER: tippfehler'), nil, ['a'],
    ['geplant']);
  Assert.IsFalse(mOutcome.Passed);
  Assert.AreEqual('U.pas(1): tippfehler ist keine bekannte Regel', mOutcome.Unknown[0]);
end;

procedure TGoldenCorpusTests.RatesPerRule;
var
  mRates: TArray<TRuleRate>;
begin
  mRates := TGoldenCorpus.Rates('Regel-ID,Datei,Zeile,Bewertung,Datum'#13#10 +
    'unused-local,a.pas,3,richtig,2026-10-08'#13#10 +
    'empty-except,a.pas,9,richtig,2026-10-08'#13#10 +
    'unused-local,b.pas,4,falsch,2026-10-08'#13#10 +
    'unused-local,c.pas,5,richtig,2026-10-08'#13#10);
  Assert.AreEqual(2, Integer(Length(mRates)));
  Assert.AreEqual('empty-except', mRates[0].RuleId);
  Assert.AreEqual(0.0, mRates[0].FalseAlarmRate, 0.0001);
  Assert.AreEqual('unused-local', mRates[1].RuleId);
  Assert.AreEqual(2, mRates[1].Correct);
  Assert.AreEqual(1, mRates[1].Wrong);
  Assert.AreEqual(1 / 3, mRates[1].FalseAlarmRate, 0.0001);
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
  mTimings: TArray<TRuleTiming>;
  mRules: TArray<IRule>;
  mIndex: Integer;
begin
  mRules := BuiltinRules;
  mTimings := TGoldenCorpus.TimeRules(mRules, TServerSettings.Default,
    ['unit U;'#10'interface'#10'implementation'#10'end.']);
  Assert.AreEqual(Integer(Length(mRules)), Integer(Length(mTimings)));
  for mIndex := 0 to High(mRules) do
  begin
    Assert.AreEqual(mRules[mIndex].Descriptor.Id, mTimings[mIndex].RuleId);
    Assert.IsTrue(mTimings[mIndex].Milliseconds >= 0);
  end;
end;

/// <summary>Ordner des Referenzprojekts, gesucht von der Test-EXE aufwärts; '' ohne.</summary>
function ReferenceFolder: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
    begin
      Exit;
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

/// <summary>Text einer Datei des Referenzprojekts ohne BOM, wie ihn der Server liest.</summary>
function ReadSource(const AFileName: string): string;
var
  mFormat: TFileFormat;
begin
  Result := TFileEncoding.Decode(TFile.ReadAllBytes(AFileName), mFormat);
end;

procedure TGoldenCorpusTests.WarmUp;
var
  mFolder, mFileName, mText: string;
  mRules: TArray<IRule>;
  mTexts: TArray<string>;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Exit;
  end;
  mRules := BuiltinRules;
  mTexts := nil;
  for mFileName in TDirectory.GetFiles(TPath.Combine(mFolder, 'Source'), '*.pas') do
  begin
    mText := ReadSource(mFileName);
    mTexts := mTexts + [mText];
    TFileChecker.CheckText(mRules, TServerSettings.Default, ExtractFileName(mFileName), mText);
  end;
  TGoldenCorpus.TimeRules(mRules, TServerSettings.Default, mTexts);
end;

/// <summary>IDs der Syntaxprüfung und aller Regeln aus ARules.</summary>
function KnownIds(const ARules: TArray<IRule>): TArray<string>;
var
  mRule: IRule;
begin
  Result := [cSyntaxRuleId];
  for mRule in ARules do
  begin
    Result := Result + [mRule.Descriptor.Id];
  end;
end;

/// <summary>Geplante IDs aus APlannedText ohne Issue (#94), je eine Zeile.</summary>
function PlannedProblems(const APlannedText: string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in TGoldenCorpus.PlannedWithoutIssue(APlannedText) do
  begin
    Result := Result + sLineBreak + mLine + ' in geplante-regeln.txt nennt kein Issue';
  end;
end;

/// <summary>Vergleicht jede Unit unter ASourceFolder mit ihren Markierungen und liefert die Abweichungen;
/// ATexts sind die gelesenen Texte, AMarkers zählt die Markierungen.</summary>
function CompareSources(const ASourceFolder: string; const ARules: TArray<IRule>; const AKnown,
  APlanned: TArray<string>; out ATexts: TArray<string>; out AMarkers: Integer): string;
var
  mFileName, mText, mLine: string;
  mOutcome: TGoldenResult;
begin
  Result := '';
  ATexts := nil;
  AMarkers := 0;
  for mFileName in TDirectory.GetFiles(ASourceFolder, '*.pas') do
  begin
    mText := ReadSource(mFileName);
    ATexts := ATexts + [mText];
    Inc(AMarkers, Length(TGoldenCorpus.Markers(mText)));
    mOutcome := TGoldenCorpus.Compare(ExtractFileName(mFileName), TGoldenCorpus.Markers(mText),
      TFileChecker.CheckText(ARules, TServerSettings.Default, ExtractFileName(mFileName), mText), AKnown, APlanned);
    // Writeln statt CurrentRunner.Log: DUnitX hält Log-Meldungen bis zum Ende des Laufs (Leck-Monitor).
    for mLine in mOutcome.Skipped do
    begin
      System.Writeln('  übersprungen: ', mLine);
    end;
    for mLine in mOutcome.Missing + mOutcome.FalseAlarms + mOutcome.Unknown do
    begin
      Result := Result + sLineBreak + mLine;
    end;
  end;
end;

procedure TGoldenCorpusTests.ReferenceProjectMatchesMarkers;
var
  mFolder, mText, mProblems: string;
  mRules: TArray<IRule>;
  mTexts: TArray<string>;
  mTiming: TRuleTiming;
  mMarkers: Integer;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  mRules := BuiltinRules;
  mText := ReadSource(TPath.Combine(mFolder, 'geplante-regeln.txt'));
  mProblems := PlannedProblems(mText);
  mProblems := mProblems + CompareSources(TPath.Combine(mFolder, 'Source'), mRules, KnownIds(mRules),
    TGoldenCorpus.PlannedIds(mText), mTexts, mMarkers);
  Assert.IsTrue(mMarkers > 0, 'Keine Markierungen im Referenzprojekt gefunden');
  // Laufzeit je Regel über den ganzen Korpus, um langsame Regeln zu erkennen.
  for mTiming in TGoldenCorpus.TimeRules(mRules, TServerSettings.Default, mTexts) do
  begin
    System.Writeln(Format('  %s: %.1f ms', [mTiming.RuleId, mTiming.Milliseconds]));
  end;
  Assert.AreEqual('', mProblems, 'Golden-Korpus weicht ab:' + mProblems);
end;

procedure TGoldenCorpusTests.IndexMarkersOnlyWithIndex;
const
  cText = 'a; // ERWARTET-INDEX: regel-a'#13#10'b; // ERWARTET: regel-b';
var
  mMarkers: TArray<TGoldenMarker>;
begin
  mMarkers := TGoldenCorpus.Markers(cText);
  Assert.AreEqual(1, Integer(Length(mMarkers)));
  Assert.AreEqual('regel-b', mMarkers[0].RuleId);
  mMarkers := TGoldenCorpus.Markers(cText, True);
  Assert.AreEqual(2, Integer(Length(mMarkers)));
  Assert.AreEqual(0, mMarkers[0].Line);
  Assert.AreEqual('regel-a', mMarkers[0].RuleId);
  Assert.IsTrue(mMarkers[0].Expected);
  Assert.AreEqual('regel-b', mMarkers[1].RuleId);
  mMarkers := nil;
end;

type
  /// <summary>Was der Lauf mit Index braucht: Regeln, bekannte und geplante IDs, Einstellungen und das Projekt
  /// mit dem Symbolindex.</summary>
  TIndexRun = record
    Rules: TArray<IRule>;
    Known: TArray<string>;
    Planned: TArray<string>;
    Settings: TServerSettings;
    Project: TCheckProject;
  end;

/// <summary>Ob AText AMarker auch ohne Index (ERWARTET) erwartet.</summary>
function HasPlainMarker(const AText: string; const AMarker: TGoldenMarker): Boolean;
var
  mPlain: TGoldenMarker;
begin
  Result := False;
  for mPlain in TGoldenCorpus.Markers(AText) do
  begin
    if (mPlain.Line = AMarker.Line) and SameText(mPlain.RuleId, AMarker.RuleId) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Schaltet ARuleId in ASettings ein, wenn die Einstellungen sie noch nicht nennen.</summary>
procedure EnableRule(var ASettings: TServerSettings; const ARuleId: string);
var
  mSetting: TRuleSetting;
begin
  for mSetting in ASettings.Rules do
  begin
    if SameText(mSetting.Id, ARuleId) then
    begin
      Exit;
    end;
  end;
  mSetting := Default(TRuleSetting);
  mSetting.Id := ARuleId;
  mSetting.Severity := TRuleSeverity.Information;
  ASettings.Rules := ASettings.Rules + [mSetting];
end;

/// <summary>Standardeinstellungen mit allen Regeln, die nur mit Index treffen (ERWARTET-INDEX). Sie sind teils
/// experimentell (legacy-stack-queue) und liefen mit den Standardeinstellungen nie: ausdrücklich einschalten, wie
/// es ein Projekt in atlas.json täte.</summary>
function IndexOnlySettings(const ATexts: TArray<string>): TServerSettings;
var
  mText: string;
  mMarker: TGoldenMarker;
begin
  Result := TServerSettings.Default;
  for mText in ATexts do
  begin
    for mMarker in TGoldenCorpus.Markers(mText, True) do
    begin
      if mMarker.Expected and not HasPlainMarker(mText, mMarker) then
      begin
        EnableRule(Result, mMarker.RuleId);
      end;
    end;
  end;
end;

/// <summary>Symbolindex mit RTL-Stubs über alle Units unter ASourceFolder; AFiles und ATexts sind die Units.
/// </summary>
function ReferenceIndex(const ASourceFolder: string; out AFiles, ATexts: TArray<string>): ISymbolIndex;
var
  mFileName: string;
begin
  Result := TSymbolIndex.Create;
  TRtlStubs.AddTo(Result);
  AFiles := nil;
  ATexts := nil;
  for mFileName in TDirectory.GetFiles(ASourceFolder, '*.pas') do
  begin
    AFiles := AFiles + [mFileName];
    ATexts := ATexts + [ReadSource(mFileName)];
    Result.AddUnit(TIndexExtractor.ExtractText(ATexts[High(ATexts)], mFileName, nil));
  end;
end;

/// <summary>Vergleicht jede Unit mit ihren Markierungen samt ERWARTET-INDEX und liefert die Abweichungen.
/// </summary>
function CompareWithIndex(const ARun: TIndexRun; const AFiles, ATexts: TArray<string>): string;
var
  mIndex: Integer;
  mOutcome: TGoldenResult;
  mScopes: TFindingScopes;
  mLine: string;
begin
  Result := '';
  for mIndex := 0 to High(AFiles) do
  begin
    mOutcome := TGoldenCorpus.Compare(ExtractFileName(AFiles[mIndex]),
      TGoldenCorpus.Markers(ATexts[mIndex], True), TFileChecker.CheckText(ARun.Rules, ARun.Settings,
      ExtractFileName(AFiles[mIndex]), ATexts[mIndex],
      TCheckOrigin.Make(ARun.Project, TCheckSource.Default), mScopes), ARun.Known,
      ARun.Planned);
    for mLine in mOutcome.Missing + mOutcome.FalseAlarms + mOutcome.Unknown do
    begin
      Result := Result + sLineBreak + mLine;
    end;
  end;
end;

procedure TGoldenCorpusTests.ReferenceProjectWithIndexMatchesMarkers;
var
  mFolder, mProblems: string;
  mFiles, mTexts: TArray<string>;
  mRun: TIndexRun;
begin
  // Wie TShellWorkspaceGroup.RuleProject: Die Regeln bekommen den Index über TCheckProject.Services. Ohne
  // Dateinamen wie der Lauf ohne Index, damit nur der Index den Unterschied macht.
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  mRun := Default(TIndexRun);
  mRun.Rules := BuiltinRules;
  mRun.Known := KnownIds(mRun.Rules);
  mRun.Planned := TGoldenCorpus.PlannedIds(ReadSource(TPath.Combine(mFolder, 'geplante-regeln.txt')));
  mRun.Project.Services.Index := ReferenceIndex(TPath.Combine(mFolder, 'Source'), mFiles, mTexts);
  mRun.Settings := IndexOnlySettings(mTexts);
  mProblems := CompareWithIndex(mRun, mFiles, mTexts);
  mFiles := nil;
  mTexts := nil;
  mRun := Default(TIndexRun);
  Assert.AreEqual('', mProblems, 'Golden-Korpus mit Index weicht ab:' + mProblems);
end;

procedure TGoldenCorpusTests.MutationsParseAndReportBadLines;
var
  mMutations: TArray<TRuleMutation>;
  mErrors: TArray<string>;
begin
  mMutations := TGoldenCorpus.Mutations('# Kommentar'#10#10'self-assignment | A.pas | X := Y; | X := X;'#10 +
    'empty-except | B.pas | a \| b | c'#10'kaputt | A.pas'#10, mErrors);
  Assert.AreEqual(2, Integer(Length(mMutations)));
  Assert.AreEqual('self-assignment', mMutations[0].RuleId);
  Assert.AreEqual('A.pas', mMutations[0].FileName);
  Assert.AreEqual('X := Y;', mMutations[0].Search);
  Assert.AreEqual('X := X;', mMutations[0].Replacement);
  Assert.AreEqual(3, mMutations[0].Line);
  // \| trennt nicht.
  Assert.AreEqual('a \| b', mMutations[1].Search);
  Assert.AreEqual(1, Integer(Length(mErrors)));
  Assert.IsTrue(Pos('Zeile 5', mErrors[0]) > 0, mErrors[0]);
end;

procedure TGoldenCorpusTests.MutateNeedsUniqueSearchAndUnescapes;
var
  mMutation: TRuleMutation;
  mMutated: string;
begin
  mMutation := Default(TRuleMutation);
  mMutation.Search := 'A := 1;\nB';
  mMutation.Replacement := 'A := ''\u202E'';\nB';
  Assert.IsTrue(TGoldenCorpus.Mutate('X'#13#10'A := 1;'#13#10'B;', mMutation, mMutated));
  Assert.AreEqual('X'#13#10'A := ''' + Char($202E) + ''';'#13#10'B;', mMutated);
  // Zweimal vorhanden oder fehlend: keine Mutation.
  mMutation.Search := 'A';
  Assert.IsFalse(TGoldenCorpus.Mutate('A A', mMutation, mMutated));
  Assert.IsFalse(TGoldenCorpus.Mutate('B', mMutation, mMutated));
end;

procedure TGoldenCorpusTests.DetectedNeedsMoreFindingsOfRule;
begin
  Assert.IsTrue(TGoldenCorpus.Detected([Finding('a', 1)], [Finding('a', 1), Finding('a', 4)], 'a'));
  Assert.IsFalse(TGoldenCorpus.Detected([Finding('a', 1)], [Finding('a', 1), Finding('b', 4)], 'a'));
  Assert.IsFalse(TGoldenCorpus.Detected(nil, nil, 'a'));
end;

procedure TGoldenCorpusTests.HitRatesPerRule;
var
  mMutations: TArray<TRuleMutation>;
  mRates: TArray<TRuleHitRate>;
begin
  SetLength(mMutations, 3);
  mMutations[0].RuleId := 'b';
  mMutations[1].RuleId := 'a';
  mMutations[2].RuleId := 'b';
  mRates := TGoldenCorpus.HitRates(mMutations, [True, False, False]);
  Assert.AreEqual(2, Integer(Length(mRates)));
  Assert.AreEqual('a', mRates[0].RuleId);
  Assert.AreEqual(0.0, mRates[0].HitRate, 0.001);
  Assert.AreEqual(2, mRates[1].Mutations);
  Assert.AreEqual(0.5, mRates[1].HitRate, 0.001);
  mMutations := nil;
end;

/// <summary>Standardeinstellungen, dazu ADescriptor ausdrücklich eingeschaltet (auch experimentelle und
/// freiwillige Regeln) und jede Konfidenz gemeldet: Die Mutation misst, ob die Regel den Fehler überhaupt
/// erkennt, nicht die Schwelle des Projekts.</summary>
function MutationSettings(const ADescriptor: TRuleDescriptor): TServerSettings;
var
  mSetting: TRuleSetting;
  mEntry: TRuleCatalogEntry;
  mOther: string;
begin
  Result := TServerSettings.Default;
  mSetting := Default(TRuleSetting);
  mSetting.Id := ADescriptor.Id;
  mSetting.Severity := ADescriptor.DefaultSeverity;
  Result.Rules := Result.Rules + [mSetting];
  // Gegenregeln (#1025) aus: Solange eine an ist, läuft die Regel nicht (redundant-begin-end neben
  // missing-begin-end).
  if TRuleCatalog.Shared.TryFind(ADescriptor.Id, mEntry) then
  begin
    for mOther in mEntry.OverriddenBy do
    begin
      mSetting := Default(TRuleSetting);
      mSetting.Id := mOther;
      mSetting.Severity := TRuleSeverity.Off;
      Result.Rules := Result.Rules + [mSetting];
    end;
  end;
  Result.MinConfidence := TRuleConfidence.Low;
  Result.MinConfidenceGiven := True;
end;

type
  /// <summary>Was die Mutationen brauchen: Ordner des Referenzprojekts, Regeln, ihre Beschreibungen samt
  /// Syntaxprüfung (#1022) und deren IDs, Packages (#943) und Programme (#956).</summary>
  TMutationRun = record
    Folder: string;
    Rules: TArray<IRule>;
    Descriptors: TArray<TRuleDescriptor>;
    Known: TArray<string>;
    Packages: TArray<TPackageSource>;
    Programs: TArray<string>;
  end;

function MutationRun(const AFolder: string): TMutationRun;
var
  mFileName: string;
  mRule: IRule;
  mDescriptor: TRuleDescriptor;
begin
  Result := Default(TMutationRun);
  Result.Folder := AFolder;
  Result.Rules := BuiltinRules;
  // Units der Packages RefRuntime und RefDesign prüfen wie der Linter als Package-Units (#943).
  for mFileName in TDirectory.GetFiles(AFolder, '*.dpk') do
  begin
    Result.Packages := Result.Packages + [TPackageReader.Read(ReadSource(mFileName))];
  end;
  for mFileName in TDirectory.GetFiles(AFolder, '*.dpr') do
  begin
    Result.Programs := Result.Programs + [ReadSource(mFileName)];
  end;
  // Syntaxfehler (#1022) sind keine IRule, prüft aber TFileChecker.CheckText mit.
  for mRule in Result.Rules do
  begin
    Result.Descriptors := Result.Descriptors + [mRule.Descriptor];
  end;
  Result.Descriptors := Result.Descriptors + [TFileChecker.SyntaxDescriptor];
  for mDescriptor in Result.Descriptors do
  begin
    Result.Known := Result.Known + [mDescriptor.Id];
  end;
end;

/// <summary>Projekt für die Unit AUnitFile (Datei AFileName) wie im Linter.</summary>
function MutationProject(const ARun: TMutationRun; const AUnitFile, AFileName: string): TCheckProject;
begin
  Result := TFileChecker.PackageOf(ARun.Packages, ChangeFileExt(AUnitFile, ''));
  // Units eines Programms: CreateForm-Reihenfolge seiner .dpr wie im Linter (#956).
  if Result.Name = '' then
  begin
    Result.AutoCreateForms := TFormAccessBeforeCreateRule.FormsOfProgram(ARun.Programs,
      ChangeFileExt(AUnitFile, ''));
  end;
  // Formulardatei neben der Unit wie im Linter (#1054).
  Result.FileName := AFileName;
end;

/// <summary>Wendet AMutation an und prüft, ob ihre Regel sie findet; liefert den Fehler oder ''.</summary>
function CheckMutation(const ARun: TMutationRun; const AMutation: TRuleMutation; out ADetected: Boolean): string;
var
  mFileName, mText, mMutated: string;
  mRuleIndex: Integer;
  mSettings: TServerSettings;
  mProject: TCheckProject;
begin
  ADetected := False;
  mFileName := TPath.Combine(TPath.Combine(ARun.Folder, 'Source'), AMutation.FileName);
  mRuleIndex := IndexText(AMutation.RuleId, ARun.Known);
  if mRuleIndex < 0 then
  begin
    Exit(Format('Zeile %d: unbekannte Regel %s', [AMutation.Line, AMutation.RuleId]));
  end;
  if not TFile.Exists(mFileName) then
  begin
    Exit(Format('Zeile %d: Datei %s fehlt', [AMutation.Line, AMutation.FileName]));
  end;
  mText := ReadSource(mFileName);
  if not TGoldenCorpus.Mutate(mText, AMutation, mMutated) then
  begin
    Exit(Format('Zeile %d: Suchtext nicht genau einmal in %s', [AMutation.Line, AMutation.FileName]));
  end;
  mSettings := MutationSettings(ARun.Descriptors[mRuleIndex]);
  mProject := MutationProject(ARun, AMutation.FileName, mFileName);
  ADetected := TGoldenCorpus.Detected(TFileChecker.CheckText(ARun.Rules, mSettings, AMutation.FileName, mText,
    mProject), TFileChecker.CheckText(ARun.Rules, mSettings, AMutation.FileName, mMutated, mProject),
    AMutation.RuleId);
  Result := '';
  if not ADetected then
  begin
    Result := Format('Zeile %d: %s findet die Mutation in %s nicht', [AMutation.Line, AMutation.RuleId,
      AMutation.FileName]);
  end;
end;

procedure TGoldenCorpusTests.ReferenceProjectMutationsAreFound;
var
  mFolder, mProblems, mProblem, mLine: string;
  mRun: TMutationRun;
  mErrors: TArray<string>;
  mMutations: TArray<TRuleMutation>;
  mMutation: TRuleMutation;
  mFound: TArray<Boolean>;
  mRate: TRuleHitRate;
  mDetected: Boolean;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  mRun := MutationRun(mFolder);
  mMutations := TGoldenCorpus.Mutations(ReadSource(TPath.Combine(mFolder, 'mutationen.txt')), mErrors);
  mProblems := '';
  for mLine in mErrors do
  begin
    mProblems := mProblems + sLineBreak + 'mutationen.txt ' + mLine;
  end;
  Assert.IsTrue(Length(mMutations) > 0, 'Keine Mutationen gefunden');
  mFound := nil;
  for mMutation in mMutations do
  begin
    mProblem := CheckMutation(mRun, mMutation, mDetected);
    if mProblem <> '' then
    begin
      mProblems := mProblems + sLineBreak + mProblem;
    end;
    mFound := mFound + [mDetected];
  end;
  // Trefferquote je Regel ins Protokoll (wie die Laufzeit oben).
  for mRate in TGoldenCorpus.HitRates(mMutations, mFound) do
  begin
    System.Writeln(Format('  %s: %d von %d gefunden', [mRate.RuleId, mRate.Found, mRate.Mutations]));
  end;
  Assert.AreEqual('', mProblems, 'Mutationen:' + mProblems);
end;

procedure TGoldenCorpusTests.ReferenceRatingsAreValid;
var
  mFolder, mProblems: string;
  mKnown: TArray<string>;
  mRule: IRule;
  mRates: TArray<TRuleRate>;
  mRate: TRuleRate;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  mKnown := nil;
  for mRule in BuiltinRules do
  begin
    mKnown := mKnown + [mRule.Descriptor.Id];
  end;
  // Rates wirft bei ungültiger Bewertung; die Quote ist so aus der Datei reproduzierbar.
  mRates := TGoldenCorpus.Rates(ReadSource(TPath.Combine(mFolder, 'bewertungen.csv')));
  Assert.IsTrue(Length(mRates) > 0, 'bewertungen.csv enthält keine Bewertungen');
  mProblems := '';
  for mRate in mRates do
  begin
    if IndexText(mRate.RuleId, mKnown) < 0 then
    begin
      mProblems := mProblems + sLineBreak + 'unbekannte Regel ' + mRate.RuleId;
    end;
    System.Writeln(Format('  %s: %d richtig, %d falsch, Fehlalarmquote %.1f %%',
      [mRate.RuleId, mRate.Correct, mRate.Wrong, mRate.FalseAlarmRate * 100], TFormatSettings.Invariant));
  end;
  Assert.AreEqual('', mProblems, 'bewertungen.csv:' + mProblems);
end;

const
  // Häufige deutsche Wörter der Meldungen; Umlaute und ß zählen immer.
  cGermanWords: array[0..33] of string = ('und', 'oder', 'nicht', 'der', 'die', 'das', 'den', 'dem', 'des', 'ist',
    'sind', 'wird', 'werden', 'mit', 'ohne', 'kein', 'keine', 'keinen', 'eine', 'einen', 'einer', 'ein', 'wie',
    'auf', 'aus', 'nach', 'zum', 'zur', 'beim', 'vom', 'statt', 'fehlt', 'ersetzen', 'entfernen');
  // Texte, die nicht aus den Regeln kommen, sondern aus Parser bzw. Editing (#1458 Gruppe B): Regel-ID und Art.
  // Einträge entfernen, sobald die Units dort umgestellt sind.
  cOtherGroups: array[0..2] of string = ('syntax ', 'declared-not-implemented Korrektur',
    'constant-initializer-mismatch Korrektur');

/// <summary>Erstes deutsche Wort in AText, das nicht im geprüften Quelltext ASource steht; '' ohne.</summary>
function GermanWord(const AText, ASource: string): string;
var
  mWord: string;
  mStart, mPos: Integer;
begin
  Result := '';
  mPos := 1;
  while mPos <= Length(AText) do
  begin
    while (mPos <= Length(AText)) and not CharInSet(AText[mPos], ['A'..'Z', 'a'..'z', '_']) and
      (Ord(AText[mPos]) < 128) do
    begin
      Inc(mPos);
    end;
    mStart := mPos;
    while (mPos <= Length(AText)) and (CharInSet(AText[mPos], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or
      (Ord(AText[mPos]) >= 128)) do
    begin
      Inc(mPos);
    end;
    mWord := Copy(AText, mStart, mPos - mStart);
    // Ganz in Großbuchstaben (DES, SQL) sind Abkürzungen, keine Wörter.
    if (mWord <> '') and (mWord <> UpperCase(mWord)) and (MatchText(mWord, cGermanWords) or
      (mWord.IndexOfAny(['ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß']) >= 0)) and not ContainsText(ASource, mWord) then
    begin
      Exit(mWord);
    end;
    Inc(mPos);
  end;
end;

/// <summary>Ob AKey ("Regel Art") mit einem Eintrag aus cOtherGroups beginnt.</summary>
function StartsWithAny(const AKey: string): Boolean;
var
  mPrefix: string;
begin
  Result := False;
  for mPrefix in cOtherGroups do
  begin
    if StartsText(mPrefix, AKey) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Meldet AText, wenn es ein deutsches Wort enthält, einmal je Regel und Text.</summary>
procedure AddGerman(var AProblems: string; const ARuleId, AKind, AText, ASource: string);
var
  mWord, mLine: string;
begin
  mWord := GermanWord(AText, ASource);
  mLine := Format('%s %s: %s [%s]', [ARuleId, AKind, AText, mWord]);
  if (mWord <> '') and (Pos(mLine, AProblems) = 0) and not StartsWithAny(ARuleId + ' ' + AKind) then
  begin
    AProblems := AProblems + sLineBreak + mLine;
  end;
end;

/// <summary>Englische Texte der Befunde von AMutation; liefert die deutschen Stellen.</summary>
function EnglishMutationProblems(const ARun: TMutationRun; const AMutation: TRuleMutation): string;
var
  mFileName, mText, mMutated: string;
  mRuleIndex: Integer;
  mFinding: TRuleFinding;
  mFix: TRuleFix;
begin
  Result := '';
  mFileName := TPath.Combine(TPath.Combine(ARun.Folder, 'Source'), AMutation.FileName);
  mRuleIndex := IndexText(AMutation.RuleId, ARun.Known);
  if (mRuleIndex < 0) or not TFile.Exists(mFileName) then
  begin
    Exit;
  end;
  mText := ReadSource(mFileName);
  if not TGoldenCorpus.Mutate(mText, AMutation, mMutated) then
  begin
    Exit;
  end;
  for mFinding in TFileChecker.CheckText(ARun.Rules, MutationSettings(ARun.Descriptors[mRuleIndex]),
    AMutation.FileName, mMutated, MutationProject(ARun, AMutation.FileName, mFileName)) do
  begin
    AddGerman(Result, mFinding.RuleId, 'Meldung', mFinding.Message, mMutated);
    for mFix in mFinding.Fixes do
    begin
      AddGerman(Result, mFinding.RuleId, 'Korrektur', mFix.Title, mMutated);
    end;
  end;
end;

procedure TGoldenCorpusTests.EnglishTextsWithoutGerman;
var
  mFolder, mProblems: string;
  mRun: TMutationRun;
  mErrors: TArray<string>;
  mMutation: TRuleMutation;
  mDescriptor: TRuleDescriptor;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  mProblems := '';
  TAtlasLocale.Use(TTextLanguage.English);
  try
    mRun := MutationRun(mFolder);
    for mDescriptor in mRun.Descriptors do
    begin
      AddGerman(mProblems, mDescriptor.Id, 'Titel', mDescriptor.Description, '');
    end;
    for mMutation in TGoldenCorpus.Mutations(ReadSource(TPath.Combine(mFolder, 'mutationen.txt')), mErrors) do
    begin
      mProblems := mProblems + EnglishMutationProblems(mRun, mMutation);
    end;
  finally
    TAtlasLocale.Use(TTextLanguage.German);
  end;
  mRun := Default(TMutationRun);
  mErrors := nil;
  Assert.AreEqual('', mProblems, 'Deutsche Texte im englischen Lauf:' + mProblems);
end;

initialization
  TDUnitX.RegisterTestFixture(TGoldenCorpusTests);

end.
