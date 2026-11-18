unit Atlas.Core.Editor.Overview.Tests;

// Übersichtsleiste (#519): Arten aus der Einstellung, Lage proportional zur
// Zeile (Zeile 900 von 1000 unten), Mindesthöhe und Zusammenfassen,
// Zeichenreihenfolge, Treffer beim Klick, Suche nach dem markierten Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOverviewTests = class
  public
    [Test]
    procedure KindsFromSetting;
    [Test]
    procedure PositionIsProportional;
    [Test]
    procedure LayoutMergesAndOrders;
    [Test]
    procedure HitPrefersImportantMarks;
    [Test]
    procedure FilterByKinds;
    [Test]
    procedure SearchOccurrences;
    [Test]
    procedure SameMarks;
    [Test]
    procedure ProblemsBySeverityWithoutUsesAndInactive;
    [Test]
    procedure ChangesWithTextOfTheirKind;
    [Test]
    procedure IndexesOfKindByLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Editor.LineChanges,
  Atlas.Core.Editor.Overview;

{ TAtlasOverviewTests }

procedure TAtlasOverviewTests.KindsFromSetting;
begin
  Assert.AreEqual('diagnostics,search,changes,breakpoints,bookmarks,cursor',
    TAtlasOverview.KindsText(TAtlasOverview.cAllKinds));
  Assert.AreEqual<TAtlasOverviewKinds>([TAtlasOverviewKind.Changes, TAtlasOverviewKind.Cursor],
    TAtlasOverview.Kinds('Changes, cursor'));
  Assert.AreEqual('search,cursor', TAtlasOverview.Normalize('cursor;gibtsnicht,search,search'));
  Assert.AreEqual('', TAtlasOverview.Normalize(''));
end;

procedure TAtlasOverviewTests.PositionIsProportional;
var
  mBars: TAtlasOverviewBars;
  mMarks: TAtlasOverviewMarks;
begin
  // Fehler in Zeile 900 einer Datei mit 1000 Zeilen: unten im Streifen (Akzeptanzkriterium).
  mBars := TAtlasOverview.Layout([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 899, 1)], 1000, 500, 3);
  Assert.AreEqual(1, Integer(Length(mBars)));
  Assert.AreEqual(449, mBars[0].Top);
  Assert.AreEqual(452, mBars[0].Bottom, 'Mindesthöhe');
  Assert.AreEqual(Ord(TAtlasOverviewLane.Right), Ord(mBars[0].Lane));
  Assert.AreEqual(900, TAtlasOverview.LineAt(450, 1000, 500));
  Assert.AreEqual(898, TAtlasOverview.LineAt(449, 1000, 500));
  Assert.AreEqual(0, TAtlasOverview.LineAt(-5, 1000, 500));
  Assert.AreEqual(999, TAtlasOverview.LineAt(9999, 1000, 500));
  // Letzte Zeile bleibt im Streifen.
  mBars := TAtlasOverview.Layout([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 999, 1)], 1000, 500, 3);
  Assert.AreEqual(500, mBars[0].Bottom);
  Assert.AreEqual(497, mBars[0].Top);
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Layout(nil, 1000, 500, 3))));
  mMarks := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1)];
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Layout(mMarks, 0, 500, 3))), 'leere Datei');
end;

procedure TAtlasOverviewTests.LayoutMergesAndOrders;
var
  mBars: TAtlasOverviewBars;
begin
  mBars := TAtlasOverview.Layout([
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 10, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 11, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 10, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, 50, 20),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 30, 1)], 100, 100, 2);
  Assert.AreEqual(4, Integer(Length(mBars)), 'zwei Treffer auf benachbarten Pixeln: ein Balken');
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Cursor), Ord(mBars[0].Kind), 'Cursor zuunterst');
  Assert.AreEqual(Ord(TAtlasOverviewLane.Full), Ord(mBars[0].Lane));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Added), Ord(mBars[1].Kind));
  Assert.AreEqual(50, mBars[1].Top);
  Assert.AreEqual(70, mBars[1].Bottom, 'Block über 20 Zeilen');
  Assert.AreEqual(Ord(TAtlasOverviewLane.Left), Ord(mBars[1].Lane));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Search), Ord(mBars[2].Kind));
  Assert.AreEqual(10, mBars[2].Top);
  Assert.AreEqual(13, mBars[2].Bottom);
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Error), Ord(mBars[3].Kind), 'Fehler zuoberst');
end;

procedure TAtlasOverviewTests.HitPrefersImportantMarks;
var
  mMarks: TAtlasOverviewMarks;
  mBars: TAtlasOverviewBars;
  mMark: Integer;
begin
  mMarks := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 10, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Warning, 11, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 40, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 70, 1)];
  mBars := TAtlasOverview.Layout(mMarks, 100, 100, 2);
  Assert.IsTrue(TAtlasOverview.Hit(mBars, 11, 2, mMark));
  Assert.AreEqual(1, mMark, 'Warnung vor Treffer');
  Assert.IsTrue(TAtlasOverview.Hit(mBars, 43, 2, mMark));
  Assert.AreEqual(2, mMark, 'mit Toleranz');
  Assert.IsFalse(TAtlasOverview.Hit(mBars, 25, 2, mMark));
  Assert.AreEqual(-1, mMark);
  Assert.IsFalse(TAtlasOverview.Hit(mBars, 70, 2, mMark), 'Cursor ist kein Ziel');
end;

procedure TAtlasOverviewTests.FilterByKinds;
var
  mMarks: TAtlasOverviewMarks;
begin
  mMarks := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Deleted, 2, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Breakpoint, 3, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, 4, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 5, 1)];
  Assert.AreEqual(5, Integer(Length(TAtlasOverview.Filter(mMarks, TAtlasOverview.cAllKinds))));
  mMarks := TAtlasOverview.Filter(mMarks, [TAtlasOverviewKind.Changes, TAtlasOverviewKind.Bookmarks]);
  Assert.AreEqual(2, Integer(Length(mMarks)));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Deleted), Ord(mMarks[0].Kind));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Bookmark), Ord(mMarks[1].Kind));
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Filter(mMarks, []))));
end;

procedure TAtlasOverviewTests.SearchOccurrences;
var
  mTerm: string;
  mLines: TArray<Integer>;
begin
  Assert.IsTrue(TAtlasOverview.SearchTerm('ShowMessage', mTerm));
  Assert.AreEqual('ShowMessage', mTerm);
  Assert.IsFalse(TAtlasOverview.SearchTerm('', mTerm));
  Assert.IsFalse(TAtlasOverview.SearchTerm('   ', mTerm));
  Assert.IsFalse(TAtlasOverview.SearchTerm('a'#13#10'b', mTerm), 'mehrzeilig');
  Assert.IsFalse(TAtlasOverview.SearchTerm(StringOfChar('x', TAtlasOverview.cMaxTermLength + 1), mTerm));
  mLines := TAtlasOverview.Occurrences(['begin', '  showmessage(''a'');', 'end;', '  ShowMessage(X);'], 'ShowMessage');
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual(1, mLines[0], 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual(3, mLines[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Occurrences(['a'], ''))));
end;

procedure TAtlasOverviewTests.SameMarks;
var
  A, B: TAtlasOverviewMarks;
begin
  A := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1, 'E2003')];
  B := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1, 'E2003')];
  Assert.IsTrue(TAtlasOverview.Same(A, B));
  B[0].Text := 'anders';
  Assert.IsFalse(TAtlasOverview.Same(A, B));
  Assert.IsFalse(TAtlasOverview.Same(A, nil));
  Assert.IsTrue(TAtlasOverview.Same(nil, nil));
end;

function Problem(ASeverity: TAtlasProblemSeverity; AStart, AEnd: Integer): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.Severity := ASeverity;
  Result.StartLine := AStart;
  Result.EndLine := AEnd;
  Result.Message := 'm' + IntToStr(AStart);
end;

procedure TAtlasOverviewTests.ProblemsBySeverityWithoutUsesAndInactive;
var
  mProblems: TArray<TAtlasProblem>;
  mMarks: TAtlasOverviewMarks;
begin
  mProblems := TArray<TAtlasProblem>.Create(Problem(TAtlasProblemSeverity.Error, 4, 6),
    Problem(TAtlasProblemSeverity.Warning, 8, 2), Problem(TAtlasProblemSeverity.Hint, 9, 9),
    Problem(TAtlasProblemSeverity.Warning, 1, 1), Problem(TAtlasProblemSeverity.Warning, 2, 2));
  mProblems[3].Unnecessary := True;
  mProblems[4].UsesUnit := 'System.Math';
  mMarks := TAtlasOverview.ProblemMarks(mProblems);
  Assert.AreEqual(3, Integer(Length(mMarks)), 'ohne inaktive Zweige und uses-Einträge');
  Assert.IsTrue(mMarks[0].Kind = TAtlasOverviewMarkKind.Error);
  Assert.AreEqual(3, mMarks[0].Count, 'über alle Zeilen des Befunds');
  Assert.AreEqual('m4', mMarks[0].Text);
  Assert.IsTrue(mMarks[1].Kind = TAtlasOverviewMarkKind.Warning);
  Assert.AreEqual(1, mMarks[1].Count, 'mindestens eine Zeile');
  Assert.IsTrue(mMarks[2].Kind = TAtlasOverviewMarkKind.Info);
end;

procedure TAtlasOverviewTests.ChangesWithTextOfTheirKind;
var
  mChange: TAtlasLineChange;
  mMark: TAtlasOverviewMark;
begin
  mChange := Default(TAtlasLineChange);
  mChange.Kind := TAtlasLineChangeKind.Modified;
  mChange.Line := 5;
  mChange.Count := 2;
  mMark := TAtlasOverview.ChangeMark(mChange, 20, 'neu', 'anders', 'weg');
  Assert.IsTrue(mMark.Kind = TAtlasOverviewMarkKind.Modified);
  Assert.AreEqual(2, mMark.Count);
  Assert.AreEqual('anders', mMark.Text);
  mChange.Kind := TAtlasLineChangeKind.Deleted;
  mChange.Line := 20;
  mChange.Count := 0;
  mMark := TAtlasOverview.ChangeMark(mChange, 20, 'neu', 'anders', 'weg');
  Assert.IsTrue(mMark.Kind = TAtlasOverviewMarkKind.Deleted);
  Assert.AreEqual(19, mMark.Line, 'am Ende auf die letzte Zeile');
  Assert.AreEqual(1, mMark.Count);
  mChange.Kind := TAtlasLineChangeKind.Added;
  Assert.AreEqual('neu', TAtlasOverview.ChangeMark(mChange, 30, 'neu', 'anders', 'weg').Text);
end;

procedure TAtlasOverviewTests.IndexesOfKindByLine;
var
  mMarks: TAtlasOverviewMarks;
  mIndexes: TArray<Integer>;
begin
  mMarks := TAtlasOverviewMarks.Create(
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 9, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 1, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 3, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 3, 2));
  mIndexes := TAtlasOverviewMark.IndexesOfKind(mMarks, TAtlasOverviewMarkKind.Error);
  Assert.AreEqual(3, Integer(Length(mIndexes)));
  Assert.AreEqual(2, mIndexes[0]);
  Assert.AreEqual(3, mIndexes[1]);
  Assert.AreEqual(0, mIndexes[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasOverviewMark.IndexesOfKind(mMarks, TAtlasOverviewMarkKind.Cursor))));
  mMarks := nil;
  mIndexes := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOverviewTests);

end.
