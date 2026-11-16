unit Atlas.Common.Metrics.DuplicateBaseline.Tests;

// Tests der Baseline wortgleicher Rümpfe: Lesen und Schreiben, neue Gruppen, weitere Kopien bekannter Gruppen und
// tote Einträge.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDuplicateBaselineTests = class
  public
    [Test]
    procedure RoundTripsOneGroupPerLine;
    [Test]
    procedure EmptyBaselineIsValidJson;
    [Test]
    procedure UnknownGroupIsNew;
    [Test]
    procedure FurtherCopyOfKnownGroupIsNew;
    [Test]
    procedure KnownGroupIsClean;
    [Test]
    procedure RemovedCopiesAreStale;
    [Test]
    procedure BrokenJsonRaises;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Metrics.DuplicateBodies,
  Atlas.Common.Metrics.DuplicateBaseline;

function Member(const APath, ARoutine: string): TDuplicateBodyMember;
begin
  Result.Path := APath;
  Result.Routine := ARoutine;
  Result.Line := 1;
end;

function Group(const AHash: string; const AMembers: array of TDuplicateBodyMember): TDuplicateBodyGroup;
var
  mIndex: Integer;
begin
  Result.Hash := AHash;
  Result.BodyLines := 8;
  Result.Members := nil;
  SetLength(Result.Members, Length(AMembers));
  for mIndex := 0 to High(AMembers) do
  begin
    Result.Members[mIndex] := AMembers[mIndex];
  end;
end;

function Known: TDuplicateBaseline;
begin
  Result := TDuplicateBaseline.FromGroups([Group('bb', [Member('B.pas', 'TB.Show'), Member('A.pas', 'TA.Show')]),
    Group('aa', [Member('C.pas', 'Tick'), Member('D.pas', 'Tick')])], 6);
end;

{ TDuplicateBaselineTests }

procedure TDuplicateBaselineTests.RoundTripsOneGroupPerLine;
var
  mJson: string;
  mRead: TDuplicateBaseline;
begin
  mJson := Known.ToJson;
  Assert.AreEqual('{'#10'  "minLines": 6,'#10'  "groups": ['#10 +
    '    {"hash": "aa", "lines": 8, "members": ["C.pas:Tick", "D.pas:Tick"]},'#10 +
    '    {"hash": "bb", "lines": 8, "members": ["A.pas:TA.Show", "B.pas:TB.Show"]}'#10'  ]'#10'}'#10, mJson);
  mRead := TDuplicateBaseline.Parse(mJson);
  Assert.AreEqual(6, mRead.MinLines);
  Assert.AreEqual(2, Integer(Length(mRead.Groups)));
  Assert.AreEqual('bb', mRead.Groups[1].Hash);
  Assert.AreEqual('A.pas:TA.Show', mRead.Groups[1].Members[0]);
  Assert.AreEqual(4, mRead.MemberCount);
end;

procedure TDuplicateBaselineTests.EmptyBaselineIsValidJson;
var
  mEmpty: TDuplicateBaseline;
begin
  mEmpty := TDuplicateBaseline.FromGroups(nil, 8);
  Assert.AreEqual('{'#10'  "minLines": 8,'#10'  "groups": []'#10'}'#10, mEmpty.ToJson);
  Assert.AreEqual(0, Integer(Length(TDuplicateBaseline.Parse(mEmpty.ToJson).Groups)));
end;

procedure TDuplicateBaselineTests.UnknownGroupIsNew;
var
  mResult: TDuplicateComparison;
begin
  mResult := Known.Compare([Group('aa', [Member('C.pas', 'Tick'), Member('D.pas', 'Tick')]),
    Group('bb', [Member('A.pas', 'TA.Show'), Member('B.pas', 'TB.Show')]),
    Group('cc', [Member('E.pas', 'Pending'), Member('F.pas', 'Pending')])]);
  Assert.IsFalse(mResult.Clean);
  Assert.AreEqual(1, Integer(Length(mResult.NewCopies)));
  Assert.IsTrue(mResult.NewCopies[0].NewGroup);
  Assert.AreEqual(2, Integer(Length(mResult.NewCopies[0].NewMembers)));
  Assert.AreEqual(2, mResult.KnownGroups);
  Assert.AreEqual(0, Integer(Length(mResult.Stale)));
end;

procedure TDuplicateBaselineTests.FurtherCopyOfKnownGroupIsNew;
var
  mResult: TDuplicateComparison;
begin
  mResult := Known.Compare([Group('aa', [Member('C.pas', 'Tick'), Member('D.pas', 'Tick')]),
    Group('bb', [Member('A.pas', 'TA.Show'), Member('B.pas', 'TB.Show'), Member('G.pas', 'TG.Show')])]);
  Assert.AreEqual(1, Integer(Length(mResult.NewCopies)));
  Assert.IsFalse(mResult.NewCopies[0].NewGroup);
  Assert.AreEqual(1, Integer(Length(mResult.NewCopies[0].NewMembers)));
  Assert.AreEqual('G.pas:TG.Show', mResult.NewCopies[0].NewMembers[0]);
end;

procedure TDuplicateBaselineTests.KnownGroupIsClean;
var
  mResult: TDuplicateComparison;
begin
  // Pfade ohne Groß-/Kleinschreibung: Windows und Linux schreiben denselben Ordner verschieden.
  mResult := Known.Compare([Group('aa', [Member('c.pas', 'Tick'), Member('D.pas', 'Tick')]),
    Group('bb', [Member('A.pas', 'TA.Show'), Member('B.pas', 'TB.Show')])]);
  Assert.IsTrue(mResult.Clean);
  Assert.AreEqual(2, mResult.KnownGroups);
end;

procedure TDuplicateBaselineTests.RemovedCopiesAreStale;
var
  mResult: TDuplicateComparison;
begin
  mResult := TDuplicateBaseline.FromGroups([Group('bb', [Member('A.pas', 'TA.Show'), Member('B.pas', 'TB.Show'),
    Member('C.pas', 'TC.Show')]), Group('aa', [Member('C.pas', 'Tick'), Member('D.pas', 'Tick')])], 6).Compare(
    [Group('bb', [Member('A.pas', 'TA.Show'), Member('B.pas', 'TB.Show')])]);
  Assert.IsFalse(mResult.Clean);
  Assert.AreEqual(0, Integer(Length(mResult.NewCopies)));
  Assert.AreEqual(2, Integer(Length(mResult.Stale)));
  Assert.AreEqual('aa', mResult.Stale[0].Hash);
  Assert.AreEqual(2, Integer(Length(mResult.Stale[0].Members)), 'Gruppe ganz verschwunden');
  Assert.AreEqual('bb', mResult.Stale[1].Hash);
  Assert.AreEqual('C.pas:TC.Show', mResult.Stale[1].Members[0], 'eine Kopie entfernt');
end;

procedure TDuplicateBaselineTests.BrokenJsonRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TDuplicateBaseline.Parse('{"minLines": 6}');
    end, EDuplicateBaseline);
  Assert.WillRaise(
    procedure
    begin
      TDuplicateBaseline.Parse('[1]');
    end, EDuplicateBaseline);
  Assert.WillRaise(
    procedure
    begin
      TDuplicateBaseline.Parse('{"groups": [{"hash": "aa"}]}');
    end, EDuplicateBaseline);
end;

end.
