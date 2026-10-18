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
  Row: TAtlasTimingRow;
begin
  for Row in ARows do
    if (Row.Kind = AKind) and ((AKind <> TAtlasTimingRowKind.Step) or (Row.Step = AStep)) and
      ((AKind <> TAtlasTimingRowKind.Provider) or (Row.Name = AName)) then
    begin
      ARow := Row;
      Exit(True);
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
  Timings: TAtlasQueryTimings;
  Queries: TArray<TAtlasQueryTiming>;
  Index: Integer;
begin
  Timings := NewTimings;
  try
    for Index := 1 to 60 do
      Timings.BeginQuery(0, 'Bezeichner', '');
    Queries := Timings.Snapshot;
    Assert.AreEqual(TAtlasQueryTimings.Capacity, Integer(Length(Queries)));
    Assert.AreEqual(11, Queries[0].Id, 'die ältesten fallen heraus');
    Assert.AreEqual(60, Queries[High(Queries)].Id);
    Assert.AreEqual(60, Timings.Current);
    Assert.IsTrue(Queries[0].ContextMs < 0, 'ohne Zeitstempel kein Kontext');
    Timings.Clear;
    Assert.AreEqual(0, Integer(Length(Timings.Snapshot)));
    Assert.AreEqual(0, Timings.Current);
  finally
    Timings.Free;
  end;
end;

procedure TAtlasTimingTests.DelayedProviderRowIsWarned;
var
  Timings: TAtlasQueryTimings;
  Id: Integer;
  Queries: TArray<TAtlasQueryTiming>;
  Rows: TArray<TAtlasTimingRow>;
  Row: TAtlasTimingRow;
begin
  // Abnahme: Bei einem künstlich verzögerten Provider erscheint dessen Zeit in Warnfarbe.
  Timings := NewTimings;
  try
    Id := Timings.BeginQuery(TAtlasQueryTimings.Stamp, 'Member, Strg+Leer', 'Unit1.pas');
    Timings.ProviderDone(Id, 'Server', 500, 120);
    Timings.ProviderDone(Id, 'Code-Vorlagen', 1.5, 4);
    Timings.FilterSorted(2.5, 124, 12);
    Timings.ListShown;
    Timings.Drawn(3);
    Queries := Timings.Snapshot;
    Assert.AreEqual(1, Integer(Length(Queries)));
    Assert.AreEqual(500.0, Queries[0].Value(TAtlasTimingStep.Provider), 0.001, 'langsamste Quelle');
    Assert.IsTrue(Queries[0].Exceeded);
    Rows := TAtlasTimingRows.Build(Queries);
    Assert.IsTrue(FindRow(Rows, TAtlasTimingRowKind.Provider, TAtlasTimingStep.Provider, 'Server', Row));
    Assert.AreEqual(500.0, Row.Last, 0.001);
    Assert.IsTrue(Row.LastWarn, 'verzögerte Quelle in Warnfarbe');
    Assert.IsTrue(Row.MaxWarn);
    Assert.IsTrue(FindRow(Rows, TAtlasTimingRowKind.Provider, TAtlasTimingStep.Provider, 'Code-Vorlagen', Row));
    Assert.IsFalse(Row.LastWarn, 'schnelle Quelle normal');
    Assert.IsTrue(FindRow(Rows, TAtlasTimingRowKind.Step, TAtlasTimingStep.FilterSort, '', Row));
    Assert.IsFalse(Row.LastWarn);
    Assert.IsTrue(FindRow(Rows, TAtlasTimingRowKind.Entries, TAtlasTimingStep.Context, '', Row));
    Assert.AreEqual(124.0, Row.Last, 0.001, 'Anzahl der Einträge');
    // Reihenfolge: Kontext, Quellen, Filtern, Zeichnen, bis zur Liste, Einträge.
    Assert.AreEqual(7, Integer(Length(Rows)));
    Assert.IsTrue(Rows[0].Step = TAtlasTimingStep.Context);
    Assert.IsTrue(Rows[1].Kind = TAtlasTimingRowKind.Provider);
    Assert.IsTrue(Rows[6].Kind = TAtlasTimingRowKind.Entries);
  finally
    Timings.Free;
  end;
end;

procedure TAtlasTimingTests.StepsKeepLongestAndFirstListOnce;
var
  Timings: TAtlasQueryTimings;
  Query: TAtlasQueryTiming;
  First: Double;
begin
  Timings := NewTimings;
  try
    Timings.BeginQuery(0, 'Bezeichner', '');
    Timings.FilterSorted(3, 100, 40);
    Timings.FilterSorted(14, 100, 5);
    Timings.Drawn(4);
    Timings.Drawn(2);
    Timings.ListShown;
    Query := Timings.Snapshot[0];
    First := Query.FirstVisibleMs;
    Assert.IsTrue(First >= 0);
    Timings.ListShown;
    Query := Timings.Snapshot[0];
    Assert.AreEqual(First, Query.FirstVisibleMs, 0.0001, 'nur die erste Liste zählt');
    Assert.AreEqual(14.0, Query.FilterSortMs, 0.001, 'längster Schritt');
    Assert.AreEqual(2, Query.FilterSortSteps);
    Assert.AreEqual(5, Query.Shown, 'sichtbar nach dem letzten Filtern');
    Assert.AreEqual(4.0, Query.DrawMs, 0.001);
    Assert.AreEqual(2, Query.DrawSteps);
    Assert.IsTrue(TAtlasTimingBudget.Exceeded(TAtlasTimingStep.FilterSort, Query.FilterSortMs));
  finally
    Timings.Free;
  end;
end;

procedure TAtlasTimingTests.StatsMeanAndMaximum;
var
  Timings: TAtlasQueryTimings;
  Id: Integer;
  Stats: TAtlasTimingStats;
  Rows: TArray<TAtlasTimingRow>;
  Row: TAtlasTimingRow;
begin
  Timings := NewTimings;
  try
    Id := Timings.BeginQuery(0, 'Bezeichner', '');
    Timings.ProviderDone(Id, 'Server', 20, 1);
    Timings.FilterSorted(2, 10, 10);
    Id := Timings.BeginQuery(0, 'Bezeichner', '');
    Timings.ProviderDone(Id, 'Server', 80, 1);
    Timings.FilterSorted(6, 30, 10);
    Stats := TAtlasTimingStats.From(Timings.Snapshot);
    Assert.AreEqual(2, Stats.Queries);
    Assert.AreEqual(4.0, Stats.Steps[TAtlasTimingStep.FilterSort].Mean, 0.001);
    Assert.AreEqual(6.0, Stats.Steps[TAtlasTimingStep.FilterSort].Peak, 0.001);
    Assert.AreEqual(50.0, Stats.Provider('Server').Mean, 0.001);
    Assert.AreEqual(80.0, Stats.Provider('Server').Peak, 0.001);
    Assert.AreEqual(20.0, Stats.Entries.Mean, 0.001);
    Assert.AreEqual(-1.0, Stats.Steps[TAtlasTimingStep.Draw].Mean, 0.001, 'nie gezeichnet');
    Rows := TAtlasTimingRows.Build(Timings.Snapshot);
    Assert.IsTrue(FindRow(Rows, TAtlasTimingRowKind.Provider, TAtlasTimingStep.Provider, 'Server', Row));
    Assert.IsTrue(Row.LastWarn);
    Assert.IsFalse(Row.MeanWarn, 'Mittel genau im Budget');
    Assert.IsTrue(Row.MaxWarn);
  finally
    Timings.Free;
  end;
end;

procedure TAtlasTimingTests.RequeryReplacesProviderTime;
var
  Timings: TAtlasQueryTimings;
  Id: Integer;
  Before: TArray<TAtlasQueryTiming>;
  Query: TAtlasQueryTiming;
begin
  Timings := NewTimings;
  try
    Id := Timings.BeginQuery(0, 'Bezeichner', '');
    Timings.ProviderDone(Id, 'Server', 90, 10);
    Before := Timings.Snapshot;
    // Gekürzte Liste (#431): Neu fragen ersetzt die Zeit derselben Quelle; alte Momentaufnahmen bleiben.
    Timings.ProviderDone(Id, 'Server', 30, 12);
    Query := Timings.Snapshot[0];
    Assert.AreEqual(1, Integer(Length(Query.Providers)));
    Assert.AreEqual(30.0, Query.Providers[0].Ms, 0.001);
    Assert.AreEqual(12, Integer(Query.Providers[0].Count));
    Assert.AreEqual(90.0, Before[0].Providers[0].Ms, 0.001);
    // Meldungen zu verdrängten oder unbekannten Abfragen gehen verloren, ohne Fehler.
    Timings.ProviderDone(999, 'Server', 1, 1);
    Assert.AreEqual(1, Integer(Length(Timings.Snapshot)));
  finally
    Timings.Free;
  end;
end;

procedure TAtlasTimingTests.RowsWithoutQueries;
var
  Rows: TArray<TAtlasTimingRow>;
  Row: TAtlasTimingRow;
begin
  Rows := TAtlasTimingRows.Build(nil);
  // Kontext, Filtern, Zeichnen, bis zur Liste, Einträge; ohne Quellen.
  Assert.AreEqual(5, Integer(Length(Rows)));
  for Row in Rows do
  begin
    Assert.IsTrue(Row.Last < 0);
    Assert.IsFalse(Row.LastWarn or Row.MeanWarn or Row.MaxWarn);
  end;
  Assert.AreEqual('–', TAtlasTimingRows.Ms(-1));
  Assert.AreEqual('3.2', TAtlasTimingRows.Ms(3.24));
  Assert.AreEqual('12', TAtlasTimingRows.CountText(12));
end;

procedure TAtlasTimingTests.ReportWithoutSourceAndFileNamesOnRequest;
var
  Timings: TAtlasQueryTimings;
  Id: Integer;
  Report: string;
begin
  Timings := NewTimings;
  try
    Id := Timings.BeginQuery(0, 'Member, automatisch', 'Kundenverwaltung.pas');
    Timings.ProviderDone(Id, 'Server', 75, 3);
    Timings.FilterSorted(1, 3, 3);
    Report := TAtlasTimingReport.Build(Timings.Snapshot, Input(False));
    Assert.Contains(Report, 'Atlas: 1.4.0');
    Assert.Contains(Report, 'IDE: 37.0');
    Assert.Contains(Report, 'Server 75.0 (!)', 'Überschreitung markiert');
    Assert.Contains(Report, 'Member, automatisch');
    Assert.Contains(Report, '"DiagnosticMode": 1', 'Einstellungen');
    Assert.IsFalse(Report.Contains('Kundenverwaltung'), 'Dateiname nur auf Wunsch');
    Report := TAtlasTimingReport.Build(Timings.Snapshot, Input(True));
    Assert.Contains(Report, 'Kundenverwaltung.pas');
  finally
    Timings.Free;
  end;
end;

procedure TAtlasTimingTests.ReportShortensPathsInSettings;
var
  Report: string;
begin
  Report := TAtlasTimingReport.Build(nil, Input(False));
  Assert.IsFalse(Report.Contains('marco'), 'Benutzername');
  Assert.IsFalse(Report.Contains('C:\Users'), 'Pfad');
  Assert.Contains(Report, 'Noch keine Abfrage gemessen.');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimingTests);

end.
