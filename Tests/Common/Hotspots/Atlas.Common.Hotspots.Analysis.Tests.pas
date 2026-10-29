unit Atlas.Common.Hotspots.Analysis.Tests;

// Tests der Auswertung der Hotspots (#1354): Änderungen je Unit (nur
// Quelldateien, je Commit einmal, Autoren, Zeilen), Normierung und Wert,
// eindeutige Sortierung, Trend mit Toleranz, Änderungskopplung mit
// Ausschlüssen (uses-Kante, .pas/.dfm derselben Unit, große Commits,
// Mindestzahl und Anteil) sowie die Namen aus dem Vertrag.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THotspotAnalysisTests = class
  public
    [Test]
    procedure CountsSourceChangesOncePerCommit;
    [Test]
    procedure LineChangesSumLines;
    [Test]
    procedure ScoreIsNormalizedProduct;
    [Test]
    procedure RankSortsUniquely;
    [Test]
    procedure TrendWithTolerance;
    [Test]
    procedure CouplingFindsPairWithoutUsesEdge;
    [Test]
    procedure CouplingExcludesConnectedFormAndLargeCommits;
    [Test]
    procedure CouplingNeedsRatio;
    [Test]
    procedure ContractNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis;

function UnitOf(const APath: string): THotspotUnit;
begin
  Result.Path := APath;
  Result.UnitName := ChangeFileExt(ExtractFileName(StringReplace(APath, '/', PathDelim, [rfReplaceAll])), '');
  Result.FileName := 'C:\Projekt\' + StringReplace(APath, '/', '\', [rfReplaceAll]);
end;

function CommitOf(const ARevision, AAuthor: string; ADay: Integer; const APaths: TArray<string>): THotspotCommit;
var
  mPath: string;
begin
  Result := Default(THotspotCommit);
  Result.Revision := ARevision;
  Result.Author := AAuthor;
  Result.Date := EncodeDate(2026, 1, 1) + ADay;
  Result.Summary := 'Commit ' + ARevision;
  for mPath in APaths do
    Result.Files := Result.Files + [THotspotFileChange.Make(mPath, '', THotspotChangeKind.Modified, 2, 1)];
end;

function EntryOf(const APath: string; AChanges, AComplexity: Integer): THotspotEntry;
begin
  Result := Default(THotspotEntry);
  Result.Path := APath;
  Result.UnitName := APath;
  Result.Changes.Changes := AChanges;
  Result.Complexity := AComplexity;
end;

function NoEdges: THotspotConnectedFunc;
begin
  Result :=
    function(AFirst, ASecond: Integer): Boolean
    begin
      Result := False;
    end;
end;

function EdgeBetween(AFirst, ASecond: Integer): THotspotConnectedFunc;
begin
  Result :=
    function(ALeft, ARight: Integer): Boolean
    begin
      Result := ((ALeft = AFirst) and (ARight = ASecond)) or ((ALeft = ASecond) and (ARight = AFirst));
    end;
end;

{ THotspotAnalysisTests }

procedure THotspotAnalysisTests.CountsSourceChangesOncePerCommit;
var
  mChanges: TArray<THotspotChanges>;
  mCommits: TArray<THotspotCommit>;
begin
  mCommits := TArray<THotspotCommit>.Create(
    CommitOf('c3', 'anna', 3, TArray<string>.Create('Src/A.pas', 'Src/A.dfm')),
    CommitOf('c2', 'Bernd', 2, TArray<string>.Create('Src/A.pas', 'Src/B.pas')),
    CommitOf('c1', 'Anna', 1, TArray<string>.Create('Src/A.dfm', 'Src/A.pas', 'src/a.pas')));
  mCommits[1].Files := mCommits[1].Files + [THotspotFileChange.Make('Src/B.pas', '', THotspotChangeKind.Deleted,
    0, 5)];
  mChanges := THotspotAnalyzer.UnitChanges(TArray<THotspotUnit>.Create(UnitOf('Src/A.pas'), UnitOf('Src/B.pas'),
    UnitOf('Src/C.pas')), mCommits);
  Assert.AreEqual(3, mChanges[0].Changes, 'je Commit einmal, .dfm zählt nicht');
  Assert.AreEqual(2, Integer(Length(mChanges[0].Authors)), 'anna und Anna sind dieselbe');
  Assert.AreEqual(6, mChanges[0].Added);
  Assert.AreEqual(3, mChanges[0].Deleted);
  Assert.AreEqual(EncodeDate(2026, 1, 1) + 3, mChanges[0].LastChange);
  Assert.AreEqual(3, Integer(Length(mChanges[0].History)));
  Assert.AreEqual('c3', mChanges[0].History[0].Revision, 'neueste zuerst');
  Assert.AreEqual(1, mChanges[1].Changes, 'Löschen zählt nicht');
  Assert.AreEqual(0, mChanges[2].Changes);
end;

procedure THotspotAnalysisTests.LineChangesSumLines;
var
  mCommits: TArray<THotspotLineCommit>;
  mChanges: THotspotChanges;
begin
  SetLength(mCommits, 2);
  mCommits[0] := Default(THotspotLineCommit);
  mCommits[0].Author := 'anna';
  mCommits[0].Added := 3;
  mCommits[0].Deleted := 1;
  mCommits[1] := Default(THotspotLineCommit);
  mCommits[1].Author := 'bernd';
  mCommits[1].Added := 2;
  mCommits[1].Deleted := 2;
  mChanges := THotspotAnalyzer.LineChanges(mCommits);
  Assert.AreEqual(2, mChanges.Changes);
  Assert.AreEqual(5, mChanges.Added);
  Assert.AreEqual(3, mChanges.Deleted);
  mCommits[1].Added := -1;
  mChanges := THotspotAnalyzer.LineChanges(mCommits);
  Assert.AreEqual(-1, mChanges.Added, 'ein unbekannter Wert macht die Summe unbekannt');
end;

procedure THotspotAnalysisTests.ScoreIsNormalizedProduct;
var
  mRanked: TArray<THotspotEntry>;
begin
  mRanked := THotspotAnalyzer.Rank(TArray<THotspotEntry>.Create(EntryOf('A.pas', 10, 50), EntryOf('B.pas', 5, 100),
    EntryOf('C.pas', 0, 500), EntryOf('D.pas', 10, 100)));
  Assert.AreEqual(3, Integer(Length(mRanked)), 'ohne Änderung fällt weg (auch mit hoher Komplexität)');
  Assert.AreEqual('D.pas', mRanked[0].Path);
  Assert.AreEqual(1.0, mRanked[0].Score, 1E-9);
  Assert.AreEqual(0.5, mRanked[1].Score, 1E-9);
  Assert.AreEqual(0.5, mRanked[2].Score, 1E-9);
end;

procedure THotspotAnalysisTests.RankSortsUniquely;
var
  mRanked: TArray<THotspotEntry>;
  mMethod: THotspotEntry;
begin
  // Gleicher Wert: mehr Änderungen zuerst, dann Komplexität, dann Pfad, dann Methode und Zeile.
  mMethod := EntryOf('A.pas', 4, 10);
  mMethod.Method := 'TFoo.B';
  mMethod.Line := 20;
  mRanked := THotspotAnalyzer.Rank(TArray<THotspotEntry>.Create(EntryOf('B.pas', 2, 20), EntryOf('A.pas', 4, 10),
    mMethod, EntryOf('C.pas', 2, 20)));
  Assert.AreEqual('A.pas', mRanked[0].Path);
  Assert.AreEqual('', mRanked[0].Method);
  Assert.AreEqual('TFoo.B', mRanked[1].Method);
  Assert.AreEqual('B.pas', mRanked[2].Path);
  Assert.AreEqual('C.pas', mRanked[3].Path);
end;

procedure THotspotAnalysisTests.TrendWithTolerance;
begin
  Assert.IsTrue(THotspotAnalyzer.TrendOf(10, -2) = THotspotTrend.New);
  Assert.IsTrue(THotspotAnalyzer.TrendOf(10, -1) = THotspotTrend.Unknown);
  Assert.IsTrue(THotspotAnalyzer.TrendOf(10, 10) = THotspotTrend.Steady);
  Assert.IsTrue(THotspotAnalyzer.TrendOf(11, 10) = THotspotTrend.Steady, 'mindestens 1 Toleranz');
  Assert.IsTrue(THotspotAnalyzer.TrendOf(12, 10) = THotspotTrend.Rising);
  Assert.IsTrue(THotspotAnalyzer.TrendOf(8, 10) = THotspotTrend.Falling);
  Assert.IsTrue(THotspotAnalyzer.TrendOf(104, 100) = THotspotTrend.Steady, '5 %');
  Assert.IsTrue(THotspotAnalyzer.TrendOf(106, 100) = THotspotTrend.Rising);
end;

procedure THotspotAnalysisTests.CouplingFindsPairWithoutUsesEdge;
var
  mCommits: TArray<THotspotCommit>;
  mPairs: TArray<THotspotCoupling>;
  mIndex: Integer;
  mExpected: Double;
begin
  // Abnahme: konstruiertes Paar mit 6 gemeinsamen Commits ohne uses-Kante.
  mCommits := nil;
  for mIndex := 1 to 6 do
    mCommits := mCommits + [CommitOf('p' + IntToStr(mIndex), 'anna', mIndex,
      TArray<string>.Create('Src/Kunde.pas', 'Src/Rechnung.pas'))];
  mCommits := mCommits + [CommitOf('x', 'anna', 7, TArray<string>.Create('Src/Kunde.pas'))];
  mPairs := THotspotAnalyzer.Coupling(TArray<THotspotUnit>.Create(UnitOf('Src/Kunde.pas'),
    UnitOf('Src/Rechnung.pas')), mCommits, THotspotOptions.Default, NoEdges);
  Assert.AreEqual(1, Integer(Length(mPairs)));
  Assert.AreEqual('Src/Kunde.pas', mPairs[0].First.Path);
  Assert.AreEqual('Src/Rechnung.pas', mPairs[0].Second.Path);
  Assert.AreEqual(6, mPairs[0].Shared);
  Assert.AreEqual(7, mPairs[0].FirstChanges);
  Assert.AreEqual(6, mPairs[0].SecondChanges);
  // Als Variable: Free Pascal rechnet den konstanten Ausdruck sonst in einfacher Genauigkeit.
  mExpected := 6;
  mExpected := mExpected / 6.5;
  Assert.AreEqual(mExpected, mPairs[0].Ratio, 1E-9);
end;

procedure THotspotAnalysisTests.CouplingExcludesConnectedFormAndLargeCommits;
var
  mCommits: TArray<THotspotCommit>;
  mPairs: TArray<THotspotCoupling>;
  mUnits: TArray<THotspotUnit>;
  mIndex, mFile: Integer;
  mLarge: TArray<string>;
begin
  mUnits := TArray<THotspotUnit>.Create(UnitOf('A.pas'), UnitOf('B.pas'), UnitOf('Form.pas'), UnitOf('C.pas'),
    UnitOf('D.pas'));
  mCommits := nil;
  for mIndex := 1 to 6 do
  begin
    // A und B gekoppelt, aber über uses verbunden; Form.pas und Form.dfm sind dieselbe Unit.
    mCommits := mCommits + [CommitOf('a' + IntToStr(mIndex), 'anna', mIndex,
      TArray<string>.Create('A.pas', 'B.pas', 'Form.pas', 'Form.dfm'))];
    // C und D nur in Commits mit mehr als 50 Dateien.
    mLarge := TArray<string>.Create('C.pas', 'D.pas');
    for mFile := 1 to 50 do
      mLarge := mLarge + ['Daten/' + IntToStr(mFile) + '.txt'];
    mCommits := mCommits + [CommitOf('l' + IntToStr(mIndex), 'anna', mIndex, mLarge)];
  end;
  mPairs := THotspotAnalyzer.Coupling(mUnits, mCommits, THotspotOptions.Default, EdgeBetween(0, 1));
  // Form.pas koppelt mit A und B (je 6 von 6), A–B hat eine Kante; kein Paar Form.pas–Form.dfm, kein C–D.
  Assert.AreEqual(2, Integer(Length(mPairs)));
  Assert.AreEqual('A.pas', mPairs[0].First.Path, 'gleicher Anteil: nach Pfad');
  Assert.AreEqual('Form.pas', mPairs[0].Second.Path);
  Assert.AreEqual('B.pas', mPairs[1].First.Path);
  Assert.AreEqual('Form.pas', mPairs[1].Second.Path);
  Assert.AreEqual(6, mPairs[0].SecondChanges, '.dfm im selben Commit zählt nicht doppelt');
end;

procedure THotspotAnalysisTests.CouplingNeedsRatio;
var
  mCommits: TArray<THotspotCommit>;
  mPairs: TArray<THotspotCoupling>;
  mIndex: Integer;
  mOptions: THotspotOptions;
begin
  mCommits := nil;
  for mIndex := 1 to 5 do
    mCommits := mCommits + [CommitOf('p' + IntToStr(mIndex), 'anna', mIndex, TArray<string>.Create('A.pas', 'B.pas'))];
  for mIndex := 1 to 6 do
    mCommits := mCommits + [CommitOf('a' + IntToStr(mIndex), 'anna', 10 + mIndex, TArray<string>.Create('A.pas'))];
  // 5 gemeinsame von (11 + 5) / 2 = 8: 62 % < 70 %.
  mPairs := THotspotAnalyzer.Coupling(TArray<THotspotUnit>.Create(UnitOf('A.pas'), UnitOf('B.pas')), mCommits,
    THotspotOptions.Default, NoEdges);
  Assert.AreEqual(0, Integer(Length(mPairs)));
  mOptions := THotspotOptions.Default;
  mOptions.MinCouplingRatio := 0.6;
  mPairs := THotspotAnalyzer.Coupling(TArray<THotspotUnit>.Create(UnitOf('A.pas'), UnitOf('B.pas')), mCommits,
    mOptions, NoEdges);
  Assert.AreEqual(1, Integer(Length(mPairs)));
  mOptions.MinSharedCommits := 6;
  mPairs := THotspotAnalyzer.Coupling(TArray<THotspotUnit>.Create(UnitOf('A.pas'), UnitOf('B.pas')), mCommits,
    mOptions, NoEdges);
  Assert.AreEqual(0, Integer(Length(mPairs)), 'hotspots.coupling.minCommits');
end;

procedure THotspotAnalysisTests.ContractNames;
var
  mLevel: THotspotLevel;
  mTrend: THotspotTrend;
begin
  Assert.AreEqual('git', THotspots.KindName(THotspotVcsKind.Git));
  Assert.AreEqual('svn', THotspots.KindName(THotspotVcsKind.Svn));
  for mTrend := Low(THotspotTrend) to High(THotspotTrend) do
    Assert.IsTrue(THotspots.TrendOf(THotspots.TrendKey(mTrend)) = mTrend);
  Assert.AreEqual('method', THotspots.LevelKey(THotspotLevel.Methods));
  Assert.IsTrue(THotspots.TryLevelOf('', mLevel) and (mLevel = THotspotLevel.Units), 'Vorgabe unit');
  Assert.IsTrue(THotspots.TryLevelOf('method', mLevel) and (mLevel = THotspotLevel.Methods));
  Assert.IsFalse(THotspots.TryLevelOf('class', mLevel));
  Assert.AreEqual(12, THotspotOptions.Default.Months);
  Assert.AreEqual(5, THotspotOptions.Default.MinSharedCommits);
  Assert.AreEqual(50, THotspotOptions.Default.MaxCommitFiles);
  Assert.AreEqual('src/a', THotspotAnalyzer.UnitKey('Src\A.dfm'));
  Assert.AreEqual('', THotspotAnalyzer.UnitKey('Src/A.txt'));
end;

initialization
  TDUnitX.RegisterTestFixture(THotspotAnalysisTests);

end.
