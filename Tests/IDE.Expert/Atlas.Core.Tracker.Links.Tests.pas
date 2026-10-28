unit Atlas.Core.Tracker.Links.Tests;

// Abhängigkeiten und Unteraufgaben (#1279): Art der YouTrack-Links aus Name,
// Beschriftungen und Richtung (englisch und deutsch, vertauschte
// Beschriftungen), Gruppen des Baums in fester Reihenfolge, Fortschritt der
// Unteraufgaben, Entscheidung „blockiert“ (Warnung beim Beginnen, Schloss im
// Board, Symbol der Zeile) und Abhängigkeiten aus dem Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerLinksTests = class
  public
    [Test]
    procedure YouTrackKindEnglish;
    [Test]
    procedure YouTrackKindGerman;
    /// <summary>Eigener Typ mit „depends on“ auf der Seite der Quelle: Richtung umgedreht.</summary>
    [Test]
    procedure YouTrackKindReversedLabels;
    [Test]
    procedure YouTrackKindUnknown;
    [Test]
    procedure KindKeyRoundTrip;
    [Test]
    procedure GroupsInOrder;
    [Test]
    procedure ProgressOfSubtasks;
    [Test]
    procedure BlockedDecision;
    [Test]
    procedure MarkOfRows;
    [Test]
    procedure TextDependenciesInline;
    [Test]
    procedure TextDependenciesLeading;
    [Test]
    procedure TextDependenciesLimits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Links;

function Link(const AKey: string; AKind: TAtlasTrackerLinkKind; AKnown, AResolved: Boolean): TAtlasTrackerLink;
begin
  Result := Default(TAtlasTrackerLink);
  Result.Key := AKey;
  Result.Kind := AKind;
  Result.StateKnown := AKnown;
  Result.Resolved := AResolved;
end;

function Kind(const AName, ASource, ATarget, ADirection: string): TAtlasTrackerLinkKind;
begin
  Result := TAtlasTrackerLinks.YouTrackKind(AName, ASource, ATarget, ADirection, False);
end;

{ TAtlasTrackerLinksTests }

procedure TAtlasTrackerLinksTests.YouTrackKindEnglish;
begin
  Assert.IsTrue(Kind('Depend', 'is required for', 'depends on', 'INWARD') = TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(Kind('Depend', 'is required for', 'depends on', 'OUTWARD') = TAtlasTrackerLinkKind.Blocks);
  Assert.IsTrue(Kind('depend', 'is required for', 'depends on', 'inward') = TAtlasTrackerLinkKind.DependsOn,
    'Groß-/Kleinschreibung egal');
  Assert.IsTrue(Kind('Depend', 'is required for', 'depends on', 'BOTH') = TAtlasTrackerLinkKind.Relates,
    'ohne Richtung keine Abhängigkeit');
  Assert.IsTrue(Kind('Subtask', 'parent for', 'subtask of', 'OUTWARD') = TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(Kind('Subtask', 'parent for', 'subtask of', 'INWARD') = TAtlasTrackerLinkKind.Parent);
  Assert.IsTrue(Kind('Duplicate', 'is duplicated by', 'duplicates', 'INWARD') = TAtlasTrackerLinkKind.Duplicates);
  Assert.IsTrue(Kind('Duplicate', 'is duplicated by', 'duplicates', 'OUTWARD') =
    TAtlasTrackerLinkKind.DuplicatedBy);
  Assert.IsTrue(Kind('Relates', 'relates to', 'relates to', 'BOTH') = TAtlasTrackerLinkKind.Relates);
  // Unbekannter Name: an den Beschriftungen erkannt.
  Assert.IsTrue(Kind('Requirement', 'is required for', 'depends on', 'INWARD') = TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(Kind('Blocker', 'blocks', 'is blocked by', 'OUTWARD') = TAtlasTrackerLinkKind.Blocks);
end;

procedure TAtlasTrackerLinksTests.YouTrackKindGerman;
begin
  Assert.IsTrue(Kind('Abhängigkeit', 'ist erforderlich für', 'hängt ab von', 'INWARD') =
    TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(Kind('Voraussetzung', 'ist erforderlich für', 'hängt ab von', 'OUTWARD') =
    TAtlasTrackerLinkKind.Blocks, 'an den Beschriftungen');
  Assert.IsTrue(Kind('Unteraufgabe', 'übergeordnet zu', 'Unteraufgabe von', 'OUTWARD') =
    TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(Kind('Teil', 'übergeordnet zu', 'Unteraufgabe von', 'INWARD') = TAtlasTrackerLinkKind.Parent);
  Assert.IsTrue(Kind('Duplikat', 'wird dupliziert durch', 'dupliziert', 'INWARD') =
    TAtlasTrackerLinkKind.Duplicates);
  Assert.IsTrue(Kind('Bezieht sich auf', '', '', 'BOTH') = TAtlasTrackerLinkKind.Relates);
  Assert.IsTrue(Kind('Eigen', 'bezieht sich auf', 'bezieht sich auf', 'BOTH') = TAtlasTrackerLinkKind.Relates);
end;

procedure TAtlasTrackerLinksTests.YouTrackKindReversedLabels;
begin
  Assert.IsTrue(Kind('Eigene Abhängigkeit', 'hängt ab von', 'ist erforderlich für', 'OUTWARD') =
    TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(Kind('Eigene Abhängigkeit', 'hängt ab von', 'ist erforderlich für', 'INWARD') =
    TAtlasTrackerLinkKind.Blocks);
  // Bekannter Name, aber vertauschte Beschriftungen (wie im Fixture der Vorschau).
  Assert.IsTrue(Kind('Depend', 'depends on', 'is required for', 'OUTWARD') = TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(Kind('Subtask', 'subtask of', 'parent for', 'OUTWARD') = TAtlasTrackerLinkKind.Parent);
  Assert.IsTrue(Kind('Duplicate', 'duplicates', 'is duplicated by', 'OUTWARD') = TAtlasTrackerLinkKind.Duplicates);
end;

procedure TAtlasTrackerLinksTests.YouTrackKindUnknown;
begin
  Assert.IsTrue(Kind('Kunde', 'meldet', 'gemeldet von', 'OUTWARD') = TAtlasTrackerLinkKind.Other);
  Assert.IsTrue(Kind('', '', '', '') = TAtlasTrackerLinkKind.Other);
  // Eltern-Kind-Typ mit eigenem Namen.
  Assert.IsTrue(TAtlasTrackerLinks.YouTrackKind('Epic', 'enthält', 'gehört zu', 'OUTWARD', True) =
    TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(TAtlasTrackerLinks.YouTrackKind('Epic', 'enthält', 'gehört zu', 'INWARD', True) =
    TAtlasTrackerLinkKind.Parent);
end;

procedure TAtlasTrackerLinksTests.KindKeyRoundTrip;
var
  mKind: TAtlasTrackerLinkKind;
begin
  for mKind := Low(TAtlasTrackerLinkKind) to High(TAtlasTrackerLinkKind) do
    Assert.IsTrue(TAtlasTrackerLink.KindOf(TAtlasTrackerLink.KindKey(mKind)) = mKind, TAtlasTrackerLink.KindKey(mKind));
  Assert.AreEqual('dependsOn', TAtlasTrackerLink.KindKey(TAtlasTrackerLinkKind.DependsOn));
  Assert.AreEqual('', TAtlasTrackerLink.KindKey(TAtlasTrackerLinkKind.Other));
  Assert.IsTrue(TAtlasTrackerLink.KindOf('unbekannt') = TAtlasTrackerLinkKind.Other);
end;

procedure TAtlasTrackerLinksTests.GroupsInOrder;
var
  mGroups: TArray<TAtlasTrackerLinkGroup>;
begin
  mGroups := TAtlasTrackerLinks.Groups(TArray<TAtlasTrackerLink>.Create(
    Link('#9', TAtlasTrackerLinkKind.Mentioned, True, False),
    Link('#3', TAtlasTrackerLinkKind.Subtask, True, True),
    Link('#1', TAtlasTrackerLinkKind.DependsOn, True, False),
    Link('#4', TAtlasTrackerLinkKind.Subtask, False, False),
    Link('#5', TAtlasTrackerLinkKind.Duplicates, True, False),
    Link('#2', TAtlasTrackerLinkKind.Blocks, True, False)));
  Assert.AreEqual(Integer(5), Integer(Length(mGroups)), 'leere Gruppen entfallen');
  Assert.IsTrue(mGroups[0].Kind = TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(mGroups[1].Kind = TAtlasTrackerLinkKind.Blocks);
  Assert.IsTrue(mGroups[2].Kind = TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(mGroups[3].Kind = TAtlasTrackerLinkKind.Duplicates);
  Assert.IsTrue(mGroups[4].Kind = TAtlasTrackerLinkKind.Mentioned);
  Assert.AreEqual('#3', mGroups[2].Links[0].Key, 'Reihenfolge des Trackers');
  Assert.AreEqual('#4', mGroups[2].Links[1].Key);
  Assert.AreEqual(1, mGroups[2].Done);
  Assert.AreEqual(2, mGroups[2].Total);
  Assert.IsFalse(mGroups[0].Collapsed);
  Assert.IsFalse(mGroups[2].Collapsed);
  Assert.IsTrue(mGroups[3].Collapsed, 'Duplikate eingeklappt');
  Assert.IsTrue(mGroups[4].Collapsed, 'Erwähnungen eingeklappt');
  Assert.IsTrue(TAtlasTrackerLinks.Collapsed(TAtlasTrackerLinkKind.Relates));
  Assert.IsFalse(TAtlasTrackerLinks.Collapsed(TAtlasTrackerLinkKind.Parent));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.Groups(nil))));
end;

procedure TAtlasTrackerLinksTests.ProgressOfSubtasks;
var
  mDone, mTotal: Integer;
begin
  Assert.IsTrue(TAtlasTrackerLinks.Progress(TArray<TAtlasTrackerLink>.Create(
    Link('#1', TAtlasTrackerLinkKind.Subtask, True, True),
    Link('#2', TAtlasTrackerLinkKind.Subtask, True, False),
    Link('#3', TAtlasTrackerLinkKind.Subtask, True, True),
    Link('#4', TAtlasTrackerLinkKind.DependsOn, True, True)), mDone, mTotal));
  Assert.AreEqual(2, mDone);
  Assert.AreEqual(3, mTotal);
  Assert.AreEqual('2/3', TAtlasTrackerLinks.ProgressText(mDone, mTotal));
  // Unbekannter Zustand zählt nicht als erledigt.
  Assert.IsTrue(TAtlasTrackerLinks.Progress(TArray<TAtlasTrackerLink>.Create(
    Link('#1', TAtlasTrackerLinkKind.Subtask, False, True)), mDone, mTotal));
  Assert.AreEqual('0/1', TAtlasTrackerLinks.ProgressText(mDone, mTotal));
  Assert.IsFalse(TAtlasTrackerLinks.Progress(TArray<TAtlasTrackerLink>.Create(
    Link('#1', TAtlasTrackerLinkKind.Parent, True, True)), mDone, mTotal), 'ohne Unteraufgaben');
  Assert.AreEqual(0, mTotal);
end;

procedure TAtlasTrackerLinksTests.BlockedDecision;
var
  mDetails: TAtlasTrackerDetails;
  mBlockers: TArray<TAtlasTrackerLink>;
begin
  mDetails := TAtlasTrackerDetails.Empty;
  mDetails.Links := TArray<TAtlasTrackerLink>.Create(
    Link('ATL-128', TAtlasTrackerLinkKind.DependsOn, True, True),
    Link('ATL-129', TAtlasTrackerLinkKind.DependsOn, True, False),
    Link('ATL-127', TAtlasTrackerLinkKind.DependsOn, False, False),
    Link('ATL-140', TAtlasTrackerLinkKind.Blocks, True, False),
    Link('ATL-131', TAtlasTrackerLinkKind.Subtask, True, False));
  mBlockers := TAtlasTrackerLinks.WarnOnStart(True, mDetails);
  Assert.AreEqual(Integer(1), Integer(Length(mBlockers)), 'nur offene, bekannte „hängt ab von“');
  Assert.AreEqual('ATL-129', mBlockers[0].Key);
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.WarnOnStart(False, mDetails))),
    'issues.warnBlocked aus');
  Assert.IsTrue(TAtlasTrackerLinks.Locked(mDetails));
  Assert.IsTrue(mDetails.Links[1].Blocking);
  Assert.IsFalse(mDetails.Links[2].Blocking, 'unbekannter Zustand warnt nicht');
  Assert.IsFalse(mDetails.Links[3].Blocking, '„blockiert“ hält das gezeigte Issue nicht auf');
  mDetails.Links[1].Resolved := True;
  Assert.IsFalse(TAtlasTrackerLinks.Locked(mDetails), 'alle erledigt');
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.WarnOnStart(True, mDetails))));
  mDetails.Links := nil;
end;

procedure TAtlasTrackerLinksTests.MarkOfRows;
begin
  Assert.IsTrue(TAtlasTrackerLinks.Mark(Link('#1', TAtlasTrackerLinkKind.DependsOn, True, False)) =
    TAtlasTrackerLinkMark.Blocking);
  Assert.IsTrue(TAtlasTrackerLinks.Mark(Link('#1', TAtlasTrackerLinkKind.Subtask, True, False)) =
    TAtlasTrackerLinkMark.Open);
  Assert.IsTrue(TAtlasTrackerLinks.Mark(Link('#1', TAtlasTrackerLinkKind.DependsOn, True, True)) =
    TAtlasTrackerLinkMark.Done);
  Assert.IsTrue(TAtlasTrackerLinks.Mark(Link('#1', TAtlasTrackerLinkKind.DependsOn, False, False)) =
    TAtlasTrackerLinkMark.Unknown);
end;

procedure TAtlasTrackerLinksTests.TextDependenciesInline;
var
  mNumbers: TArray<Integer>;
begin
  mNumbers := TAtlasTrackerLinks.TextDependencies('Die Arbeit depends on #12 and #13.'#13#10 +
    'Außerdem hängt das ab von nichts, aber hängt ab von #14; blocked by #15, #12.');
  Assert.AreEqual(Integer(4), Integer(Length(mNumbers)), 'ohne Doppelte');
  Assert.AreEqual(12, mNumbers[0]);
  Assert.AreEqual(13, mNumbers[1]);
  // Je Zeile in der Reihenfolge der Wendungen: erst „blocked by“, dann „hängt ab von“.
  Assert.AreEqual(15, mNumbers[2]);
  Assert.AreEqual(14, mNumbers[3]);
  mNumbers := TAtlasTrackerLinks.TextDependencies('Is Blocked By #7 und #8');
  Assert.AreEqual(Integer(2), Integer(Length(mNumbers)), 'Groß-/Kleinschreibung egal');
  Assert.AreEqual(8, mNumbers[1]);
  // Nur als eigenes Wort und nur echte Nummern.
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.TextDependencies('xdepends on #3'))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.TextDependencies('depends on #12a'))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.TextDependencies('depends on #12-fix'))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.TextDependencies('depends on #0'))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.TextDependencies('depends on the API #3'))),
    'Nummer muss direkt folgen');
end;

procedure TAtlasTrackerLinksTests.TextDependenciesLeading;
var
  mNumbers: TArray<Integer>;
begin
  mNumbers := TAtlasTrackerLinks.TextDependencies('## Abhängigkeiten'#10'- **Benötigt:** #765, #1264'#10 +
    '- Wird benötigt von: #227'#10'> Requires: #9'#10'Text, der Benötigt: #5 nicht am Anfang hat');
  Assert.AreEqual(Integer(3), Integer(Length(mNumbers)));
  Assert.AreEqual(765, mNumbers[0]);
  Assert.AreEqual(1264, mNumbers[1]);
  Assert.AreEqual(9, mNumbers[2], 'ohne „Wird benötigt von“ (Gegenrichtung) und ohne Text mitten in der Zeile');
end;

procedure TAtlasTrackerLinksTests.TextDependenciesLimits;
var
  mText: string;
  mIndex: Integer;
begin
  mText := 'Benötigt:';
  for mIndex := 1 to 15 do
    mText := mText + ' #' + IntToStr(mIndex) + ',';
  Assert.AreEqual(Integer(TAtlasTrackerLinks.MaxTextDependencies),
    Integer(Length(TAtlasTrackerLinks.TextDependencies(mText))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerLinks.TextDependencies(''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerLinksTests);

end.
