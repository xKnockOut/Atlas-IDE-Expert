unit Atlas.Common.Architecture.Matching.Tests;

// Tests der gemeinsamen Zuordnung der Teilsysteme (#1367): Überschneidung
// für den Vergleich (#1121), strikte Mehrheit beider Seiten für die
// Angleichung; Gleichstand, Aufteilung, Verschmelzung und Rückfall auf den
// Namen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Architecture.Snapshot;

type
  [TestFixture]
  TSubsystemMatcherTests = class
  public
    [Test]
    procedure MajorityNeedsBothSides;
    [Test]
    procedure TieGoesByName;
    [Test]
    procedure SplitKeepsMajorityPart;
    [Test]
    procedure MergeKeepsLargestOld;
    [Test]
    procedure SameNameOnlyForComparison;
  end;

/// <summary>Fügt ASnapshot das Teilsystem AName mit den Units AUnits hinzu (Tests der Zuordnung).</summary>
procedure AddMatchGroup(var ASnapshot: TArchitectureSnapshot; const AName: string; const AUnits: TArray<string>);

implementation

uses
  Atlas.Common.Architecture.Matching;

procedure AddMatchGroup(var ASnapshot: TArchitectureSnapshot; const AName: string; const AUnits: TArray<string>);
var
  mSubsystem: TSnapshotSubsystem;
  mItem: TSnapshotUnit;
  mName: string;
begin
  mSubsystem := Default(TSnapshotSubsystem);
  mSubsystem.Name := AName;
  mSubsystem.Units := AUnits;
  ASnapshot.Subsystems := ASnapshot.Subsystems + [mSubsystem];
  for mName in AUnits do
  begin
    mItem := Default(TSnapshotUnit);
    mItem.Name := mName;
    mItem.Subsystem := AName;
    ASnapshot.Units := ASnapshot.Units + [mItem];
  end;
end;

/// <summary>Alter Name zum neuen Teilsystem ANewName; '#' ohne Eintrag.</summary>
function OldOf(const AMatches: TArray<TSubsystemMatch>; const ANewName: string): string;
var
  mMatch: TSubsystemMatch;
begin
  for mMatch in AMatches do
    if mMatch.NewName = ANewName then
      Exit(mMatch.OldName);
  Result := '#';
end;

procedure TSubsystemMatcherTests.MajorityNeedsBothSides;
var
  mOld, mNew: TArchitectureSnapshot;
  mMatches: TArray<TSubsystemMatch>;
begin
  mOld := Default(TArchitectureSnapshot);
  mNew := Default(TArchitectureSnapshot);
  // X teilt mit A 3 von 3 bzw. 3 von 4 Units: Mehrheit beider Seiten.
  AddMatchGroup(mOld, 'A', ['a', 'b', 'c', 'd']);
  AddMatchGroup(mNew, 'X', ['a', 'b', 'c']);
  // Y teilt mit B 3 von 7 (neu) bzw. 3 von 3 (alt): keine Mehrheit des neuen.
  AddMatchGroup(mOld, 'B', ['e', 'f', 'g']);
  AddMatchGroup(mNew, 'Y', ['e', 'f', 'g', 'h', 'i', 'j', 'k']);
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Majority);
  Assert.AreEqual(2, Integer(Length(mMatches)));
  Assert.AreEqual('A', OldOf(mMatches, 'X'));
  Assert.AreEqual('', OldOf(mMatches, 'Y'));
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Overlap);
  Assert.AreEqual('A', OldOf(mMatches, 'X'));
  Assert.AreEqual('B', OldOf(mMatches, 'Y'));
  // Genau die Hälfte ist keine strikte Mehrheit.
  mOld := Default(TArchitectureSnapshot);
  mNew := Default(TArchitectureSnapshot);
  AddMatchGroup(mOld, 'A', ['a', 'b', 'c', 'd']);
  AddMatchGroup(mNew, 'X', ['a', 'b', 'x', 'y']);
  Assert.AreEqual('', OldOf(TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Majority), 'X'));
  Assert.AreEqual('A', OldOf(TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Overlap), 'X'));
end;

procedure TSubsystemMatcherTests.TieGoesByName;
var
  mOld, mNew: TArchitectureSnapshot;
  mMatches: TArray<TSubsystemMatch>;
begin
  mOld := Default(TArchitectureSnapshot);
  mNew := Default(TArchitectureSnapshot);
  AddMatchGroup(mOld, 'B', ['c', 'd']);
  AddMatchGroup(mOld, 'A', ['a', 'b']);
  AddMatchGroup(mNew, 'X', ['a', 'b', 'c', 'd']);
  // Gleich große Überschneidung: das alte nach Namen; je altes höchstens ein neues.
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Overlap);
  Assert.AreEqual('A', OldOf(mMatches, 'X'));
  // Bei Gleichstand gewinnt derselbe Name.
  mNew := Default(TArchitectureSnapshot);
  AddMatchGroup(mNew, 'B', ['a', 'b', 'c', 'd']);
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Overlap);
  Assert.AreEqual('B', OldOf(mMatches, 'B'));
  // Mit Mehrheit hat keines der beiden alten mehr als die Hälfte des neuen.
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Majority);
  Assert.AreEqual('', OldOf(mMatches, 'B'));
end;

procedure TSubsystemMatcherTests.SplitKeepsMajorityPart;
var
  mOld, mNew: TArchitectureSnapshot;
  mMatches: TArray<TSubsystemMatch>;
begin
  mOld := Default(TArchitectureSnapshot);
  mNew := Default(TArchitectureSnapshot);
  AddMatchGroup(mOld, 'A', ['a', 'b', 'c', 'd', 'e', 'f']);
  AddMatchGroup(mNew, 'X', ['a', 'b', 'c', 'd']);
  AddMatchGroup(mNew, 'Y', ['e', 'f']);
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Majority);
  Assert.AreEqual('A', OldOf(mMatches, 'X'));
  Assert.AreEqual('', OldOf(mMatches, 'Y'));
end;

procedure TSubsystemMatcherTests.MergeKeepsLargestOld;
var
  mOld, mNew: TArchitectureSnapshot;
  mMatches: TArray<TSubsystemMatch>;
begin
  mOld := Default(TArchitectureSnapshot);
  mNew := Default(TArchitectureSnapshot);
  AddMatchGroup(mOld, 'A', ['a', 'b', 'c']);
  AddMatchGroup(mOld, 'B', ['d', 'e']);
  AddMatchGroup(mNew, 'X', ['a', 'b', 'c', 'd', 'e']);
  mMatches := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Majority);
  Assert.AreEqual(1, Integer(Length(mMatches)));
  Assert.AreEqual('A', OldOf(mMatches, 'X'));
end;

procedure TSubsystemMatcherTests.SameNameOnlyForComparison;
var
  mOld, mNew: TArchitectureSnapshot;
begin
  mOld := Default(TArchitectureSnapshot);
  mNew := Default(TArchitectureSnapshot);
  AddMatchGroup(mOld, 'Kern', ['a']);
  AddMatchGroup(mNew, 'Kern', ['z']);
  Assert.AreEqual('Kern', OldOf(TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Overlap), 'Kern'));
  Assert.AreEqual('', OldOf(TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Majority), 'Kern'));
end;

end.
