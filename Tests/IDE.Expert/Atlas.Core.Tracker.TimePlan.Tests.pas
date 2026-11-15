unit Atlas.Core.Tracker.TimePlan.Tests;

// Entscheidungen der Zeiterfassung (#1267, #1967) ohne IDE: welche Eingabe zählt, Summe mit ungeschriebenen
// Spannen, Speichern im Takt, Angebot beim Wechsel und nach dem Beenden, Mindestzeit, korrigierte Dauer und
// Kommentar für GitHub.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTimePlanTests = class
  public
    [Test]
    procedure InputCountsOnlyNewInIde;
    [Test]
    procedure InputAtSubtractsAge;
    [Test]
    procedure SavesEveryMinute;
    [Test]
    procedure TotalAddsPendingOfSameIssue;
    [Test]
    procedure OffersOnSwitchBetweenIssues;
    [Test]
    procedure OffersFromOneMinute;
    [Test]
    procedure EndStepBookedOfferOrSkip;
    [Test]
    procedure CurrentIgnoresCase;
    /// <summary>„0“ setzt wie Zurücksetzen auf null; Unlesbares wird abgelehnt.</summary>
    [Test]
    procedure CorrectedMinutesAllowZero;
    [Test]
    procedure CommentWithDescription;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Tracker.TimePlan;

function Issue(const AKey: string): TAtlasTimeIssue;
begin
  Result := TAtlasTimeIssue.Create('youtrack', 'https://firma.youtrack.cloud', 'ATL', AKey);
end;

{ TAtlasTimePlanTests }

procedure TAtlasTimePlanTests.InputCountsOnlyNewInIde;
begin
  Assert.AreEqual(Integer(Ord(TAtlasTimeInput.Ide)), Integer(Ord(TAtlasTimePlan.InputOf(True, 200, 100, True))));
  Assert.AreEqual(Integer(Ord(TAtlasTimeInput.Elsewhere)),
    Integer(Ord(TAtlasTimePlan.InputOf(True, 200, 100, False))), 'IDE nicht vorn');
  Assert.AreEqual(Integer(Ord(TAtlasTimeInput.Same)), Integer(Ord(TAtlasTimePlan.InputOf(True, 100, 100, True))),
    'keine neue Eingabe');
  Assert.AreEqual(Integer(Ord(TAtlasTimeInput.Same)), Integer(Ord(TAtlasTimePlan.InputOf(False, 200, 100, True))),
    'unbekannt');
end;

procedure TAtlasTimePlanTests.InputAtSubtractsAge;
var
  mNow: TDateTime;
begin
  mNow := EncodeDateTime(2026, 11, 15, 10, 0, 0, 0);
  Assert.AreEqual(Int64(30), SecondsBetween(mNow, TAtlasTimePlan.InputAt(mNow, 30000)));
  Assert.AreEqual(Int64(0), MilliSecondsBetween(mNow, TAtlasTimePlan.InputAt(mNow, 0)));
end;

procedure TAtlasTimePlanTests.SavesEveryMinute;
begin
  Assert.IsFalse(TAtlasTimePlan.SavesOnTick(1));
  Assert.IsFalse(TAtlasTimePlan.SavesOnTick(TAtlasTimePlan.cSaveTicks - 1));
  Assert.IsTrue(TAtlasTimePlan.SavesOnTick(TAtlasTimePlan.cSaveTicks));
  Assert.IsTrue(TAtlasTimePlan.SavesOnTick(2 * TAtlasTimePlan.cSaveTicks));
end;

procedure TAtlasTimePlanTests.TotalAddsPendingOfSameIssue;
var
  mStart: TDateTime;
  mPending: TArray<TAtlasTimeSpan>;
begin
  mStart := EncodeDateTime(2026, 11, 15, 9, 0, 0, 0);
  mPending := [TAtlasTimeSpan.Create(Issue('ATL-1'), mStart, IncSecond(mStart, 90)),
    TAtlasTimeSpan.Create(Issue('ATL-2'), mStart, IncSecond(mStart, 600)),
    TAtlasTimeSpan.Create(Issue('atl-1'), mStart, IncSecond(mStart, 10))];
  Assert.AreEqual(Int64(120 + 5 + 90 + 10), TAtlasTimePlan.Total(120, 5, mPending, Issue('ATL-1')));
  Assert.AreEqual(Int64(7), TAtlasTimePlan.Total(7, 0, nil, Issue('ATL-1')), 'nichts ausstehend');
end;

procedure TAtlasTimePlanTests.OffersOnSwitchBetweenIssues;
begin
  Assert.IsTrue(TAtlasTimePlan.OffersOnSwitch(Issue('ATL-1'), Issue('ATL-2')));
  Assert.IsFalse(TAtlasTimePlan.OffersOnSwitch(TAtlasTimeIssue.None, Issue('ATL-2')), 'erstes Issue');
  Assert.IsFalse(TAtlasTimePlan.OffersOnSwitch(Issue('ATL-1'), TAtlasTimeIssue.None), 'kein Issue mehr');
  Assert.IsFalse(TAtlasTimePlan.OffersOnSwitch(Issue('ATL-1'), Issue('ATL-1')), 'dasselbe');
end;

procedure TAtlasTimePlanTests.OffersFromOneMinute;
begin
  Assert.IsFalse(TAtlasTimePlan.Offers(TAtlasTimePlan.cMinOfferSeconds - 1));
  Assert.IsTrue(TAtlasTimePlan.Offers(TAtlasTimePlan.cMinOfferSeconds));
  Assert.IsTrue(TAtlasTimePlan.ReadsCommits('C:\Projekt', 'ATL-1-fix'));
  Assert.IsFalse(TAtlasTimePlan.ReadsCommits('', 'ATL-1-fix'));
  Assert.IsFalse(TAtlasTimePlan.ReadsCommits('C:\Projekt', ''));
end;

procedure TAtlasTimePlanTests.EndStepBookedOfferOrSkip;
begin
  Assert.AreEqual(Integer(Ord(TAtlasTimeEndStep.BookedOnEnd)),
    Integer(Ord(TAtlasTimePlan.EndStep('ATL-1', 'atl-1', True))));
  Assert.AreEqual(Integer(Ord(TAtlasTimeEndStep.BookedOnEnd)),
    Integer(Ord(TAtlasTimePlan.EndStep('ATL-1', 'ATL-1', False))), 'Merker auch ohne Angebot löschen');
  Assert.AreEqual(Integer(Ord(TAtlasTimeEndStep.Offer)), Integer(Ord(TAtlasTimePlan.EndStep('ATL-1', 'ATL-2', True))));
  Assert.AreEqual(Integer(Ord(TAtlasTimeEndStep.Offer)), Integer(Ord(TAtlasTimePlan.EndStep('ATL-1', '', True))));
  Assert.AreEqual(Integer(Ord(TAtlasTimeEndStep.Skip)), Integer(Ord(TAtlasTimePlan.EndStep('ATL-1', '', False))),
    'nicht geplant');
end;

procedure TAtlasTimePlanTests.CurrentIgnoresCase;
begin
  Assert.IsTrue(TAtlasTimePlan.IsCurrent(Issue('ATL-1'), 'atl-1'));
  Assert.IsFalse(TAtlasTimePlan.IsCurrent(Issue('ATL-1'), 'ATL-2'));
  Assert.IsFalse(TAtlasTimePlan.IsCurrent(TAtlasTimeIssue.None, ''));
end;

procedure TAtlasTimePlanTests.CorrectedMinutesAllowZero;
var
  mMinutes: Integer;
begin
  Assert.IsTrue(TAtlasTimePlan.CorrectedMinutes(' 0 ', mMinutes));
  Assert.AreEqual(0, mMinutes);
  Assert.IsTrue(TAtlasTimePlan.CorrectedMinutes('0:00', mMinutes));
  Assert.AreEqual(0, mMinutes);
  Assert.IsTrue(TAtlasTimePlan.CorrectedMinutes('1:25', mMinutes));
  Assert.AreEqual(85, mMinutes);
  Assert.IsFalse(TAtlasTimePlan.CorrectedMinutes('bald', mMinutes));
end;

procedure TAtlasTimePlanTests.CommentWithDescription;
begin
  Assert.AreEqual('Aufwand: 1h', TAtlasTimePlan.BookComment('Aufwand: 1h', ''));
  Assert.AreEqual('Aufwand: 1h'#10#10'Fehler behoben', TAtlasTimePlan.BookComment('Aufwand: 1h', 'Fehler behoben'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimePlanTests);

end.
