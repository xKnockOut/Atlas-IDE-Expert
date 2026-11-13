unit Atlas.Core.Debug.BreakpointList.Tests;

// Tests des Haltepunktfensters ohne IDE (#863): Suche über Datei, Methode,
// Bedingung und Etikett, Filterchips, Gruppierung nach Etikett, Datei und
// Gruppe, Trefferzahlen je Sitzung und die gemerkte Spaltenanordnung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.BreakpointList;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointListTests = class
  private
    FRows: TArray<TAtlasBreakpointRow>;
    procedure Fill;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LocationShowsUnitMethodAndLine;
    [Test]
    procedure SearchFindsFileMethodConditionAndTag;
    [Test]
    procedure SearchWordsMustAllMatch;
    [Test]
    procedure FilterChipsCombine;
    [Test]
    procedure GroupNoneSortsByFileAndLine;
    [Test]
    procedure GroupByTagListsRowInEachTag;
    [Test]
    procedure GroupByFileAndGroup;
    [Test]
    procedure HitsCountPerSessionAndReset;
    [Test]
    procedure HitsMoveWithBreakpoint;
    [Test]
    procedure ColumnsRoundTrip;
    [Test]
    procedure ColumnsParseRepairsText;
    [Test]
    procedure ColumnsMoveTo;
  end;

implementation

uses
  System.SysUtils;

const
  cKunde = 'C:\App\Kunde.pas';
  cImport = 'C:\App\Import.pas';
  cBasis = 'C:\App\Basis\Import.pas';

{ TAtlasBreakpointListTests }

procedure TAtlasBreakpointListTests.TearDown;
begin
  FRows := nil;
end;

procedure TAtlasBreakpointListTests.Fill;
var
  mRow: TAtlasBreakpointRow;
begin
  FRows := nil;
  mRow := TAtlasBreakpointRow.Create(cKunde, 42);
  mRow.Method := 'TKunde.Speichern';
  mRow.Tags := TArray<string>.Create('Bug 4711');
  mRow.Hits := 3;
  FRows := FRows + [mRow];
  mRow := TAtlasBreakpointRow.Create(cImport, 10);
  mRow.Method := 'TImport.Lesen';
  mRow.Condition := 'Zeile > 100';
  mRow.Tags := TArray<string>.Create('Import', 'Bug 4711');
  mRow.Group := 'Lesen';
  FRows := FRows + [mRow];
  mRow := TAtlasBreakpointRow.Create(cKunde, 7);
  mRow.Enabled := False;
  mRow.Tags := TArray<string>.Create('Speicherplatz');
  mRow.NotEffective := True;
  mRow.Reason := 'Optimierung';
  FRows := FRows + [mRow];
  mRow := TAtlasBreakpointRow.Create(cBasis, 5);
  mRow.Method := 'Laden';
  mRow.Group := 'lesen';
  FRows := FRows + [mRow];
end;

procedure TAtlasBreakpointListTests.LocationShowsUnitMethodAndLine;
begin
  Fill;
  Assert.AreEqual('Kunde · TKunde.Speichern · 42', FRows[0].Location);
  Assert.AreEqual('Kunde · 7', FRows[2].Location, 'ohne Methode');
  Assert.AreEqual('Import', FRows[3].UnitName);
  Assert.IsTrue(FRows[1].HasTag('import'));
  Assert.IsFalse(FRows[0].HasTag('Import'));
end;

procedure TAtlasBreakpointListTests.SearchFindsFileMethodConditionAndTag;
var
  mFound: TArray<Integer>;
begin
  Fill;
  mFound := TAtlasBreakpointView.Filter(FRows, 'Speich', []);
  Assert.AreEqual(2, Integer(Length(mFound)), 'Methode Speichern und Etikett Speicherplatz');
  Assert.AreEqual(0, mFound[0]);
  Assert.AreEqual(2, mFound[1]);
  mFound := TAtlasBreakpointView.Filter(FRows, 'zeile >', []);
  Assert.AreEqual(1, Integer(Length(mFound)), 'Bedingung');
  Assert.AreEqual(1, mFound[0]);
  mFound := TAtlasBreakpointView.Filter(FRows, 'IMPORT.pas', []);
  Assert.AreEqual(2, Integer(Length(mFound)), 'Dateiname ohne Groß/klein');
  mFound := TAtlasBreakpointView.Filter(FRows, 'App', []);
  Assert.AreEqual(0, Integer(Length(mFound)), 'Ordner zählt nicht');
  Assert.AreEqual(4, Integer(Length(TAtlasBreakpointView.Filter(FRows, '  ', []))), 'leere Suche');
end;

procedure TAtlasBreakpointListTests.SearchWordsMustAllMatch;
var
  mFound: TArray<Integer>;
begin
  Fill;
  mFound := TAtlasBreakpointView.Filter(FRows, 'bug lesen', []);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, mFound[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasBreakpointView.Filter(FRows, 'bug laden', []))));
end;

procedure TAtlasBreakpointListTests.FilterChipsCombine;
var
  mFound: TArray<Integer>;
begin
  Fill;
  Assert.AreEqual(3, Integer(Length(TAtlasBreakpointView.Filter(FRows, '', [TAtlasBreakpointFilter.Active]))));
  mFound := TAtlasBreakpointView.Filter(FRows, '', [TAtlasBreakpointFilter.WithCondition]);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, mFound[0]);
  mFound := TAtlasBreakpointView.Filter(FRows, '', [TAtlasBreakpointFilter.NeverHit]);
  Assert.AreEqual(3, Integer(Length(mFound)), 'nur Zeile 0 hat gehalten');
  mFound := TAtlasBreakpointView.Filter(FRows, '', [TAtlasBreakpointFilter.NotEffective]);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(2, mFound[0]);
  mFound := TAtlasBreakpointView.Filter(FRows, '', [TAtlasBreakpointFilter.Active,
    TAtlasBreakpointFilter.NeverHit]);
  Assert.AreEqual(2, Integer(Length(mFound)), 'aktiv und nie getroffen');
  mFound := TAtlasBreakpointView.Filter(FRows, 'Kunde', [TAtlasBreakpointFilter.Active]);
  Assert.AreEqual(1, Integer(Length(mFound)), 'Suche und Chip');
  Assert.AreEqual(0, mFound[0]);
end;

procedure TAtlasBreakpointListTests.GroupNoneSortsByFileAndLine;
var
  mGroups: TArray<TAtlasBreakpointGroupEntry>;
begin
  Fill;
  mGroups := TAtlasBreakpointView.Group(FRows, TAtlasBreakpointView.Filter(FRows, '', []),
    TAtlasBreakpointGrouping.None);
  Assert.AreEqual(1, Integer(Length(mGroups)));
  Assert.AreEqual('', mGroups[0].Caption);
  Assert.AreEqual(4, Integer(Length(mGroups[0].Rows)));
  // Import.pas (Basis vor App nach vollem Pfad), dann Kunde.pas 7, 42.
  Assert.AreEqual(3, mGroups[0].Rows[0]);
  Assert.AreEqual(1, mGroups[0].Rows[1]);
  Assert.AreEqual(2, mGroups[0].Rows[2]);
  Assert.AreEqual(0, mGroups[0].Rows[3]);
  mGroups := TAtlasBreakpointView.Group(FRows, nil, TAtlasBreakpointGrouping.None);
  Assert.AreEqual(1, Integer(Length(mGroups)), 'auch ohne Zeilen eine Gruppe');
end;

procedure TAtlasBreakpointListTests.GroupByTagListsRowInEachTag;
var
  mGroups: TArray<TAtlasBreakpointGroupEntry>;
begin
  Fill;
  mGroups := TAtlasBreakpointView.Group(FRows, TAtlasBreakpointView.Filter(FRows, '', []),
    TAtlasBreakpointGrouping.ByTag);
  Assert.AreEqual(4, Integer(Length(mGroups)));
  Assert.AreEqual('Bug 4711', mGroups[0].Caption);
  Assert.AreEqual(2, Integer(Length(mGroups[0].Rows)));
  Assert.AreEqual(1, mGroups[0].Rows[0], 'Import.pas vor Kunde.pas');
  Assert.AreEqual(0, mGroups[0].Rows[1]);
  Assert.AreEqual('Import', mGroups[1].Caption);
  Assert.AreEqual('Speicherplatz', mGroups[2].Caption);
  Assert.AreEqual('', mGroups[3].Caption, 'ohne Etikett zuletzt');
  Assert.AreEqual(1, Integer(Length(mGroups[3].Rows)));
  Assert.AreEqual(3, mGroups[3].Rows[0]);
end;

procedure TAtlasBreakpointListTests.GroupByFileAndGroup;
var
  mGroups: TArray<TAtlasBreakpointGroupEntry>;
  mAll: TArray<Integer>;
begin
  Fill;
  mAll := TAtlasBreakpointView.Filter(FRows, '', []);
  mGroups := TAtlasBreakpointView.Group(FRows, mAll, TAtlasBreakpointGrouping.ByFile);
  Assert.AreEqual(2, Integer(Length(mGroups)), 'gleicher Dateiname in zwei Ordnern: eine Gruppe');
  Assert.AreEqual('Import.pas', mGroups[0].Caption);
  Assert.AreEqual(2, Integer(Length(mGroups[0].Rows)));
  Assert.AreEqual('Kunde.pas', mGroups[1].Caption);
  mGroups := TAtlasBreakpointView.Group(FRows, mAll, TAtlasBreakpointGrouping.ByGroup);
  Assert.AreEqual(2, Integer(Length(mGroups)));
  Assert.AreEqual('Lesen', mGroups[0].Caption, 'Lesen und lesen zusammen, erste Schreibweise');
  Assert.AreEqual(2, Integer(Length(mGroups[0].Rows)));
  Assert.AreEqual('', mGroups[1].Caption);
end;

procedure TAtlasBreakpointListTests.HitsCountPerSessionAndReset;
var
  mHits: TAtlasBreakpointHits;
  mIndex: Integer;
begin
  mHits := TAtlasBreakpointHits.Create;
  try
    Assert.IsFalse(mHits.HasRun);
    mHits.Start;
    Assert.IsTrue(mHits.HasRun);
    for mIndex := 1 to 10 do
    begin
      Assert.AreEqual(mIndex, mHits.Hit(cKunde, 42));
    end;
    Assert.AreEqual(10, mHits.Count('c:/app/KUNDE.pas', 42), 'Pfad ohne Groß/klein und Trenner');
    Assert.AreEqual(0, mHits.Count(cKunde, 43));
    mHits.Reset;
    Assert.AreEqual(0, mHits.Count(cKunde, 42));
    Assert.IsTrue(mHits.HasRun);
    mHits.Hit(cKunde, 42);
    mHits.Start;
    Assert.AreEqual(0, mHits.Count(cKunde, 42), 'neue Sitzung');
  finally
    mHits.Free;
  end;
end;

procedure TAtlasBreakpointListTests.HitsMoveWithBreakpoint;
var
  mHits: TAtlasBreakpointHits;
begin
  mHits := TAtlasBreakpointHits.Create;
  try
    mHits.Start;
    mHits.Hit(cKunde, 42);
    mHits.Hit(cKunde, 42);
    mHits.Move(cKunde, 42, cKunde, 45);
    Assert.AreEqual(0, mHits.Count(cKunde, 42));
    Assert.AreEqual(2, mHits.Count(cKunde, 45));
  finally
    mHits.Free;
  end;
end;

procedure TAtlasBreakpointListTests.ColumnsRoundTrip;
var
  mColumns, mLoaded: TAtlasBreakpointColumns;
begin
  mColumns := TAtlasBreakpointColumns.Default;
  Assert.AreEqual(Integer(Ord(High(TAtlasBreakpointColumn))) + 1, Integer(Length(mColumns.Items)));
  Assert.IsTrue(mColumns.IsVisible(TAtlasBreakpointColumn.SetName));
  mColumns.SetVisible(TAtlasBreakpointColumn.Group, False);
  mColumns.SetWidth(TAtlasBreakpointColumn.Location, 300);
  mColumns.SetWidth(TAtlasBreakpointColumn.Hits, 1);
  mLoaded := TAtlasBreakpointColumns.Parse(mColumns.ToText);
  Assert.AreEqual(mColumns.ToText, mLoaded.ToText);
  Assert.IsFalse(mLoaded.IsVisible(TAtlasBreakpointColumn.Group));
  Assert.AreEqual(300, mLoaded.Items[mLoaded.IndexOf(TAtlasBreakpointColumn.Location)].Width);
  Assert.AreEqual(TAtlasBreakpointColumns.cMinWidth,
    mLoaded.Items[mLoaded.IndexOf(TAtlasBreakpointColumn.Hits)].Width, 'Mindestbreite');
  Assert.IsTrue(mColumns.ToText.Contains('-group:'));
end;

procedure TAtlasBreakpointListTests.ColumnsParseRepairsText;
var
  mColumns: TAtlasBreakpointColumns;
begin
  mColumns := TAtlasBreakpointColumns.Parse('hits:50, unbekannt:20,-LOCATION,hits:80,tags:abc');
  Assert.AreEqual(Integer(Ord(High(TAtlasBreakpointColumn))) + 1, Integer(Length(mColumns.Items)));
  Assert.AreEqual(Ord(TAtlasBreakpointColumn.Hits), Ord(mColumns.Items[0].Column));
  Assert.AreEqual(50, mColumns.Items[0].Width, 'erste Angabe gilt');
  Assert.AreEqual(Ord(TAtlasBreakpointColumn.Location), Ord(mColumns.Items[1].Column));
  Assert.IsFalse(mColumns.Items[1].Visible);
  Assert.AreEqual(TAtlasBreakpointColumns.DefaultWidth(TAtlasBreakpointColumn.Location), mColumns.Items[1].Width);
  Assert.AreEqual(Ord(TAtlasBreakpointColumn.Tags), Ord(mColumns.Items[2].Column));
  Assert.AreEqual(TAtlasBreakpointColumns.DefaultWidth(TAtlasBreakpointColumn.Tags), mColumns.Items[2].Width);
  Assert.AreEqual(Ord(TAtlasBreakpointColumn.Enabled), Ord(mColumns.Items[3].Column), 'fehlende hinten');
  Assert.AreEqual(TAtlasBreakpointColumns.Default.ToText, TAtlasBreakpointColumns.Parse('').ToText);
end;

procedure TAtlasBreakpointListTests.ColumnsMoveTo;
var
  mColumns: TAtlasBreakpointColumns;
begin
  mColumns := TAtlasBreakpointColumns.Default;
  mColumns.MoveTo(TAtlasBreakpointColumn.Hits, 0);
  Assert.AreEqual(0, mColumns.IndexOf(TAtlasBreakpointColumn.Hits));
  Assert.AreEqual(1, mColumns.IndexOf(TAtlasBreakpointColumn.Enabled));
  mColumns.MoveTo(TAtlasBreakpointColumn.Hits, 99);
  Assert.AreEqual(Integer(High(mColumns.Items)), mColumns.IndexOf(TAtlasBreakpointColumn.Hits));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointListTests);

end.
