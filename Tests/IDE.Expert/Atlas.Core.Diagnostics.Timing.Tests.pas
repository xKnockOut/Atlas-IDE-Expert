unit Atlas.Core.Diagnostics.Timing.Tests;

// Diagnosemodus (#479), Teil ohne VCL: Budget aus #409, Rekorder der letzten
// 50 Abfragen, Mittelwert und Maximum, Zeilen des Fensters mit Warnfarbe und
// der kopierte Bericht (keine Quelltexte, Dateinamen nur auf Wunsch, Pfade und
// Benutzername gekürzt). Der ganze Ablauf mit Quellen und Controller steht in
// Atlas.Core.Completion.Controller.Tests (TAtlasCompletionTimingTests).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTimingTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BudgetFollows409;
    [Test]
    procedure OffByDefault;
    [Test]
    procedure KeepsLast50Queries;
    [Test]
    procedure DelayedProviderRowIsWarned;
    [Test]
    procedure StepsKeepLongestAndFirstListOnce;
    [Test]
    procedure StatsMeanAndMaximum;
    [Test]
    procedure RequeryReplacesProviderTime;
    [Test]
    procedure RowsWithoutQueries;
    [Test]
    procedure ReportWithoutSourceAndFileNamesOnRequest;
    [Test]
    procedure ReportShortensPathsInSettings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Timing;

function NewTimings: TAtlasQueryTimings;
begin
  Result := TAtlasQueryTimings.Create;
end;

function FindRow(const ARows: TArray<TAtlasTimingRow>; AKind: TAtlasTimingRowKind; AStep: TAtlasTimingStep;
  const AName: string; out ARow: TAtlasTimingRow): Boolean;
var
  mRow: TAtlasTimingRow;
begin
  for mRow in ARows do
  begin
    if (mRow.Kind = AKind) and ((AKind <> TAtlasTimingRowKind.Step) or (mRow.Step = AStep)) and
      ((AKind <> TAtlasTimingRowKind.Provider) or (mRow.Name = AName)) then
    begin
      ARow := mRow;
      Exit(True);
    end;
  end;
  ARow := Default(TAtlasTimingRow);
  Result := False;
end;

function Input(AFileNames: Boolean): TAtlasTimingReportInput;
begin
  Result := Default(TAtlasTimingReportInput);
  Result.AtlasVersion := '1.4.0';
  Result.IdeVersion := '37.0';
  Result.Platform := 'Win64';
  Result.Settings := '{"ServerPath": "C:\\Users\\marco\\Atlas\\AtlasServer.exe", "DiagnosticMode": 1}';
  Result.Identity := ['marco', 'RECHNER01'];
  Result.FileNames := AFileNames;
  Result.Created := EncodeDate(2026, 10, 15);
end;

{ TAtlasTimingTests }

procedure TAtlasTimingTests.TearDown;
begin
  TAtlasQueryTimings.Enabled := False;
end;

procedure TAtlasTimingTests.BudgetFollows409;
begin
  // Kontext ≤ 8 ms, Filtern und Sortieren ≤ 12 ms, Zeichnen ≤ 10 ms, erste Einträge ≤ 50 ms.
  Assert.AreEqual(8.0, TAtlasTimingBudget.LimitMs(TAtlasTimingStep.Context), 0.001);
  Assert.AreEqual(12.0, TAtlasTimingBudget.LimitMs(TAtlasTimingStep.FilterSort), 0.001);
  Assert.AreEqual(10.0, TAtlasTimingBudget.LimitMs(TAtlasTimingStep.Draw), 0.001);
  Assert.AreEqual(50.0, TAtlasTimingBudget.LimitMs(TAtlasTimingStep.FirstVisible), 0.001);
  Assert.AreEqual(50.0, TAtlasTimingBudget.LimitMs(TAtlasTimingStep.Provider), 0.001);
  Assert.IsFalse(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Context, 8));
  Assert.IsTrue(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Context, 8.1));
  Assert.IsFalse(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.Provider, -1), 'nicht gemessen');
end;

procedure TAtlasTimingTests.OffByDefault;
begin
  // diagnosticMode.enabled ist standardmäßig aus; erst die IDE-Schicht schaltet die Messung ein.
  Assert.IsFalse(TAtlasQueryTimings.Enabled);
  Assert.IsNotNull(TAtlasQueryTimings.Shared);
end;

procedure TAtlasTimingTests.KeepsLast50Queries;
var
  mTimings: TAtlasQueryTimings;
  mQueries: TArray<TAtlasQueryTiming>;
  mIndex: Integer;
begin
  mTimings := NewTimings;
  try
    for mIndex := 1 to 60 do
    begin
      mTimings.BeginQuery(0, 'Bezeichner', '');
    end;
    mQueries := mTimings.Snapshot;
    Assert.AreEqual(TAtlasQueryTimings.cCapacity, Integer(Length(mQueries)));
    Assert.AreEqual(11, mQueries[0].Id, 'die ältesten fallen heraus');
    Assert.AreEqual(60, mQueries[High(mQueries)].Id);
    Assert.AreEqual(60, mTimings.Current);
    Assert.IsTrue(mQueries[0].ContextMs < 0, 'ohne Zeitstempel kein Kontext');
    mTimings.Clear;
    Assert.AreEqual(0, Integer(Length(mTimings.Snapshot)));
    Assert.AreEqual(0, mTimings.Current);
  finally
    mTimings.Free;
  end;
end;

procedure TAtlasTimingTests.DelayedProviderRowIsWarned;
var
  mTimings: TAtlasQueryTimings;
  mId: Integer;
  mQueries: TArray<TAtlasQueryTiming>;
  mRows: TArray<TAtlasTimingRow>;
  mRow: TAtlasTimingRow;
begin
  // Abnahme: Bei einem künstlich verzögerten Provider erscheint dessen Zeit in Warnfarbe.
  mTimings := NewTimings;
  try
    mId := mTimings.BeginQuery(TAtlasQueryTimings.Stamp, 'Member, Strg+Leer', 'Unit1.pas');
    mTimings.ProviderDone(mId, 'Server', 500, 120);
    mTimings.ProviderDone(mId, 'Code-Vorlagen', 1.5, 4);
    mTimings.FilterSorted(2.5, 124, 12);
    mTimings.ListShown;
    mTimings.Drawn(3);
    mQueries := mTimings.Snapshot;
    Assert.AreEqual(1, Integer(Length(mQueries)));
    Assert.AreEqual(500.0, mQueries[0].Value(TAtlasTimingStep.Provider), 0.001, 'langsamste Quelle');
    Assert.IsTrue(mQueries[0].Exceeded);
    mRows := TAtlasTimingRows.Build(mQueries);
    Assert.IsTrue(FindRow(mRows, TAtlasTimingRowKind.Provider, TAtlasTimingStep.Provider, 'Server', mRow));
    Assert.AreEqual(500.0, mRow.Last, 0.001);
    Assert.IsTrue(mRow.LastWarn, 'verzögerte Quelle in Warnfarbe');
    Assert.IsTrue(mRow.MaxWarn);
    Assert.IsTrue(FindRow(mRows, TAtlasTimingRowKind.Provider, TAtlasTimingStep.Provider, 'Code-Vorlagen', mRow));
    Assert.IsFalse(mRow.LastWarn, 'schnelle Quelle normal');
    Assert.IsTrue(FindRow(mRows, TAtlasTimingRowKind.Step, TAtlasTimingStep.FilterSort, '', mRow));
    Assert.IsFalse(mRow.LastWarn);
    Assert.IsTrue(FindRow(mRows, TAtlasTimingRowKind.Entries, TAtlasTimingStep.Context, '', mRow));
    Assert.AreEqual(124.0, mRow.Last, 0.001, 'Anzahl der Einträge');
    // Reihenfolge: Kontext, Quellen, Filtern, Zeichnen, bis zur Liste, Einträge.
    Assert.AreEqual(7, Integer(Length(mRows)));
    Assert.AreEqual<TAtlasTimingStep>(TAtlasTimingStep.Context, mRows[0].Step);
    Assert.AreEqual<TAtlasTimingRowKind>(TAtlasTimingRowKind.Provider, mRows[1].Kind);
    Assert.AreEqual<TAtlasTimingRowKind>(TAtlasTimingRowKind.Entries, mRows[6].Kind);
  finally
    mTimings.Free;
  end;
end;

procedure TAtlasTimingTests.StepsKeepLongestAndFirstListOnce;
var
  mTimings: TAtlasQueryTimings;
  mQuery: TAtlasQueryTiming;
  mFirst: Double;
begin
  mTimings := NewTimings;
  try
    mTimings.BeginQuery(0, 'Bezeichner', '');
    mTimings.FilterSorted(3, 100, 40);
    mTimings.FilterSorted(14, 100, 5);
    mTimings.Drawn(4);
    mTimings.Drawn(2);
    mTimings.ListShown;
    mQuery := mTimings.Snapshot[0];
    mFirst := mQuery.FirstVisibleMs;
    Assert.IsTrue(mFirst >= 0);
    mTimings.ListShown;
    mQuery := mTimings.Snapshot[0];
    Assert.AreEqual(mFirst, mQuery.FirstVisibleMs, 0.0001, 'nur die erste Liste zählt');
    Assert.AreEqual(14.0, mQuery.FilterSortMs, 0.001, 'längster Schritt');
    Assert.AreEqual(2, mQuery.FilterSortSteps);
    Assert.AreEqual(5, mQuery.Shown, 'sichtbar nach dem letzten Filtern');
    Assert.AreEqual(4.0, mQuery.DrawMs, 0.001);
    Assert.AreEqual(2, mQuery.DrawSteps);
    Assert.IsTrue(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.FilterSort, mQuery.FilterSortMs));
  finally
    mTimings.Free;
  end;
end;

procedure TAtlasTimingTests.StatsMeanAndMaximum;
var
  mTimings: TAtlasQueryTimings;
  mId: Integer;
  mStats: TAtlasTimingStats;
  mRows: TArray<TAtlasTimingRow>;
  mRow: TAtlasTimingRow;
begin
  mTimings := NewTimings;
  try
    mId := mTimings.BeginQuery(0, 'Bezeichner', '');
    mTimings.ProviderDone(mId, 'Server', 20, 1);
    mTimings.FilterSorted(2, 10, 10);
    mId := mTimings.BeginQuery(0, 'Bezeichner', '');
    mTimings.ProviderDone(mId, 'Server', 80, 1);
    mTimings.FilterSorted(6, 30, 10);
    mStats := TAtlasTimingStats.From(mTimings.Snapshot);
    Assert.AreEqual(2, mStats.Queries);
    Assert.AreEqual(4.0, mStats.Steps[TAtlasTimingStep.FilterSort].Mean, 0.001);
    Assert.AreEqual(6.0, mStats.Steps[TAtlasTimingStep.FilterSort].Peak, 0.001);
    Assert.AreEqual(50.0, mStats.Provider('Server').Mean, 0.001);
    Assert.AreEqual(80.0, mStats.Provider('Server').Peak, 0.001);
    Assert.AreEqual(20.0, mStats.Entries.Mean, 0.001);
    Assert.AreEqual(-1.0, mStats.Steps[TAtlasTimingStep.Draw].Mean, 0.001, 'nie gezeichnet');
    mRows := TAtlasTimingRows.Build(mTimings.Snapshot);
    Assert.IsTrue(FindRow(mRows, TAtlasTimingRowKind.Provider, TAtlasTimingStep.Provider, 'Server', mRow));
    Assert.IsTrue(mRow.LastWarn);
    Assert.IsFalse(mRow.MeanWarn, 'Mittel genau im Budget');
    Assert.IsTrue(mRow.MaxWarn);
  finally
    mTimings.Free;
  end;
end;

procedure TAtlasTimingTests.RequeryReplacesProviderTime;
var
  mTimings: TAtlasQueryTimings;
  mId: Integer;
  mBefore: TArray<TAtlasQueryTiming>;
  mQuery: TAtlasQueryTiming;
begin
  mTimings := NewTimings;
  try
    mId := mTimings.BeginQuery(0, 'Bezeichner', '');
    mTimings.ProviderDone(mId, 'Server', 90, 10);
    mBefore := mTimings.Snapshot;
    // Gekürzte Liste (#431): Neu fragen ersetzt die Zeit derselben Quelle; alte Momentaufnahmen bleiben.
    mTimings.ProviderDone(mId, 'Server', 30, 12);
    mQuery := mTimings.Snapshot[0];
    Assert.AreEqual(1, Integer(Length(mQuery.Providers)));
    Assert.AreEqual(30.0, mQuery.Providers[0].Ms, 0.001);
    Assert.AreEqual(12, Integer(mQuery.Providers[0].Count));
    Assert.AreEqual(90.0, mBefore[0].Providers[0].Ms, 0.001);
    // Meldungen zu verdrängten oder unbekannten Abfragen gehen verloren, ohne Fehler.
    mTimings.ProviderDone(999, 'Server', 1, 1);
    Assert.AreEqual(1, Integer(Length(mTimings.Snapshot)));
  finally
    mTimings.Free;
  end;
end;

procedure TAtlasTimingTests.RowsWithoutQueries;
var
  mRows: TArray<TAtlasTimingRow>;
  mRow: TAtlasTimingRow;
begin
  mRows := TAtlasTimingRows.Build(nil);
  // Kontext, Filtern, Zeichnen, bis zur Liste, Einträge; ohne Quellen.
  Assert.AreEqual(5, Integer(Length(mRows)));
  for mRow in mRows do
  begin
    Assert.IsTrue(mRow.Last < 0);
    Assert.IsFalse(mRow.LastWarn or mRow.MeanWarn or mRow.MaxWarn);
  end;
  Assert.AreEqual('–', TAtlasTimingRows.Ms(-1));
  Assert.AreEqual('3.2', TAtlasTimingRows.Ms(3.24));
  Assert.AreEqual('12', TAtlasTimingRows.CountText(12));
end;

procedure TAtlasTimingTests.ReportWithoutSourceAndFileNamesOnRequest;
var
  mTimings: TAtlasQueryTimings;
  mId: Integer;
  mReport: string;
begin
  mTimings := NewTimings;
  try
    mId := mTimings.BeginQuery(0, 'Member, automatisch', 'Kundenverwaltung.pas');
    mTimings.ProviderDone(mId, 'Server', 75, 3);
    mTimings.FilterSorted(1, 3, 3);
    mReport := TAtlasTimingReport.Build(mTimings.Snapshot, Input(False));
    Assert.Contains(mReport, 'Atlas: 1.4.0');
    Assert.Contains(mReport, 'IDE: 37.0');
    Assert.Contains(mReport, 'Server 75.0 (!)', 'Überschreitung markiert');
    Assert.Contains(mReport, 'Member, automatisch');
    Assert.Contains(mReport, '"DiagnosticMode": 1', 'Einstellungen');
    Assert.IsFalse(mReport.Contains('Kundenverwaltung'), 'Dateiname nur auf Wunsch');
    mReport := TAtlasTimingReport.Build(mTimings.Snapshot, Input(True));
    Assert.Contains(mReport, 'Kundenverwaltung.pas');
  finally
    mTimings.Free;
  end;
end;

procedure TAtlasTimingTests.ReportShortensPathsInSettings;
var
  mReport: string;
begin
  mReport := TAtlasTimingReport.Build(nil, Input(False));
  Assert.IsFalse(mReport.Contains('marco'), 'Benutzername');
  Assert.IsFalse(mReport.Contains('C:\Users'), 'Pfad');
  Assert.Contains(mReport, 'Noch keine Abfrage gemessen.');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimingTests);

end.
