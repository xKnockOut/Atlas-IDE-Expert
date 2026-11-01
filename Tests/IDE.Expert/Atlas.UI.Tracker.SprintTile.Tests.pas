unit Atlas.UI.Tracker.SprintTile.Tests;

// Tests der Sprint-Kachel (#1277) ohne IDE: Texte (Kopf, Zahlen, Vergleich,
// Hinweise, Stand, Tooltip je Tag) auf Deutsch und Englisch, Klickflächen und
// dass Klicks die Quelle erst über die Nachrichtenschleife erreichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerSprintViewTests = class
  public
    /// <summary>„Sprint 12 · 27.10.–07.11. · noch 4 Tage“, „noch 1 Tag“, „beendet“, „beginnt am …“.</summary>
    [Test]
    procedure HeadingWithDaysLeft;
    /// <summary>Zahlen: meine offen/erledigt (ohne Anmeldename „–“), Team übrig in Punkten bzw. Issues.</summary>
    [Test]
    procedure NumbersInPointsOrIssues;
    /// <summary>„erledigt 5 · Vorsprint 4 am selben Tag ▲1“; ohne Vergleich bzw. Vorsprint leer.</summary>
    [Test]
    procedure CompareLine;
    [Test]
    procedure NoticesAndStatus;
    [Test]
    procedure DayHintWithValues;
    [Test]
    procedure EnglishTexts;
    /// <summary>Zahlen filtern „Meine Issues“, Team übrig öffnet das Board, Titel den Browser; ohne Tracker
    /// „zuordnen …“.</summary>
    [Test]
    procedure ClicksReachSource;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.DateUtils,
  Vcl.Forms,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Sprint,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.SprintTile;

type
  /// <summary>Quelle der Kachel für die Tests; merkt sich die Aufrufe.</summary>
  TFakeSprint = class(TInterfacedObject, IAtlasSprintSource)
  public
    FTile: TAtlasSprintTile;
    Calls: TArray<string>;
    function View: TAtlasSprintTile;
    procedure Shown;
    procedure OpenBoard;
    procedure BrowseBoard;
    procedure FilterIssues(ADone: Boolean);
    procedure AssignProject;
  end;

function TFakeSprint.View: TAtlasSprintTile;
begin
  Result := FTile;
end;

procedure TFakeSprint.Shown;
begin
  Calls := Calls + ['shown'];
end;

procedure TFakeSprint.OpenBoard;
begin
  Calls := Calls + ['board'];
end;

procedure TFakeSprint.BrowseBoard;
begin
  Calls := Calls + ['browse'];
end;

procedure TFakeSprint.FilterIssues(ADone: Boolean);
begin
  if ADone then
  begin
    Calls := Calls + ['filter done'];
  end
  else
  begin
    Calls := Calls + ['filter open'];
  end;
end;

procedure TFakeSprint.AssignProject;
begin
  Calls := Calls + ['assign'];
end;

function Day(AUtc: TDateTime): string;
begin
  Result := FormatDateTime('dd.mm.', TTimeZone.Local.ToLocalTime(AUtc));
end;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function Issue(const AKey: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
end;

/// <summary>Laufender Sprint „Sprint 12“ (vor drei Tagen bis in zehn Tagen), 4 Resttage, Punkte.</summary>
function Running: TAtlasSprintTile;
begin
  Result := Default(TAtlasSprintTile);
  Result.Status := TAtlasSprintTileStatus.Ready;
  Result.Burndown := True;
  Result.Compare := True;
  Result.Sprint.Known := True;
  Result.Sprint.Name := 'Sprint 12';
  Result.Sprint.Start := DateOf(NowUtc) - 3;
  Result.Sprint.Finish := DateOf(NowUtc) + 10;
  Result.Sprint.Page := 'https://firma.youtrack.cloud/agiles/108-2/current';
  Result.Sprint.DaysLeft := 4;
  Result.Sprint.DayCount := 2;
  Result.Sprint.Today := 1;
  Result.Sprint.UsesPoints := True;
  Result.Sprint.MineKnown := True;
  Result.Sprint.MineOpen := TArray<TAtlasTrackerIssue>.Create(Issue('ATL-1'), Issue('ATL-2'));
  Result.Sprint.MineDone := TArray<TAtlasTrackerIssue>.Create(Issue('ATL-3'));
  Result.Sprint.Total := 30;
  Result.Sprint.TeamLeft := 21;
  Result.Sprint.Actual := TArray<Double>.Create(30, 21);
  Result.Sprint.Ideal := TArray<Double>.Create(30, 15, 0);
  Result.Sprint.Dates := TArray<TDateTime>.Create(EncodeDate(2026, 10, 27), EncodeDate(2026, 10, 28));
end;

{ TAtlasTrackerSprintViewTests }

procedure TAtlasTrackerSprintViewTests.HeadingWithDaysLeft;
var
  mSaved: TAtlasLanguage;
  mTile: TAtlasSprintTile;
  mRange: string;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mTile := Running;
    // Ende ist exklusiv: als letzten Tag den davor.
    mRange := Day(mTile.Sprint.Start) + '–' + Day(mTile.Sprint.Finish - OneSecond);
    Assert.AreEqual('Sprint 12 · ' + mRange + ' · noch 4 Tage', TAtlasTrackerSprintView.HeadingText(mTile));
    mTile.Sprint.DaysLeft := 1;
    Assert.AreEqual('Sprint 12 · ' + mRange + ' · noch 1 Tag', TAtlasTrackerSprintView.HeadingText(mTile));
    mTile.Sprint.DaysLeft := 0;
    Assert.AreEqual('Sprint 12 · ' + mRange + ' · beendet', TAtlasTrackerSprintView.HeadingText(mTile));
    mTile.Sprint.Start := DateOf(NowUtc) + 2;
    mRange := Day(mTile.Sprint.Start) + '–' + Day(mTile.Sprint.Finish - OneSecond);
    Assert.AreEqual('Sprint 12 · ' + mRange + ' · beginnt am ' + Day(mTile.Sprint.Start),
      TAtlasTrackerSprintView.HeadingText(mTile));
    mTile.Sprint.Known := False;
    Assert.AreEqual('', TAtlasTrackerSprintView.HeadingText(mTile));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerSprintViewTests.NumbersInPointsOrIssues;
var
  mSaved: TAtlasLanguage;
  mTile: TAtlasSprintTile;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mTile := Running;
    Assert.AreEqual('meine offen', TAtlasTrackerSprintView.NumberCaption(0));
    Assert.AreEqual('Team übrig', TAtlasTrackerSprintView.NumberCaption(2));
    Assert.AreEqual('2', TAtlasTrackerSprintView.NumberValue(mTile, 0));
    Assert.AreEqual('1', TAtlasTrackerSprintView.NumberValue(mTile, 1));
    Assert.AreEqual('21 Punkte', TAtlasTrackerSprintView.NumberValue(mTile, 2));
    mTile.Sprint.UsesPoints := False;
    mTile.Sprint.TeamLeft := 3.5;
    Assert.AreEqual('3,5 Issues', TAtlasTrackerSprintView.NumberValue(mTile, 2));
    // Ohne Anmeldename sind die eigenen Zahlen unbekannt.
    mTile.Sprint.MineKnown := False;
    Assert.AreEqual('–', TAtlasTrackerSprintView.NumberValue(mTile, 0));
    Assert.AreEqual('–', TAtlasTrackerSprintView.NumberValue(mTile, 1));
    Assert.AreEqual('12', TAtlasTrackerSprintView.NumberText(12.02));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerSprintViewTests.CompareLine;
var
  mSaved: TAtlasLanguage;
  mTile: TAtlasSprintTile;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mTile := Running;
    Assert.AreEqual('', TAtlasTrackerSprintView.CompareText(mTile), 'ohne Vorsprint');
    mTile.Sprint.HasPrevious := True;
    mTile.Sprint.DoneToday := 5;
    mTile.Sprint.PreviousDone := 4;
    Assert.AreEqual('erledigt 5 · Vorsprint 4 am selben Tag ▲1', TAtlasTrackerSprintView.CompareText(mTile));
    mTile.Sprint.PreviousDone := 7;
    Assert.AreEqual('erledigt 5 · Vorsprint 7 am selben Tag ▼2', TAtlasTrackerSprintView.CompareText(mTile));
    mTile.Sprint.PreviousDone := 5;
    Assert.AreEqual('erledigt 5 · Vorsprint 5 am selben Tag =', TAtlasTrackerSprintView.CompareText(mTile));
    // issues.sprint.compare aus.
    mTile.Compare := False;
    Assert.AreEqual('', TAtlasTrackerSprintView.CompareText(mTile));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerSprintViewTests.NoticesAndStatus;
var
  mSaved: TAtlasLanguage;
  mTile: TAtlasSprintTile;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mTile := Default(TAtlasSprintTile);
    mTile.Status := TAtlasSprintTileStatus.NoTracker;
    Assert.AreEqual('Kein Board für dieses Projekt – zuordnen …', TAtlasTrackerSprintView.NoticeText(mTile));
    mTile.Status := TAtlasSprintTileStatus.NoProject;
    Assert.AreEqual('Kein Projekt geöffnet.', TAtlasTrackerSprintView.NoticeText(mTile));
    mTile.Status := TAtlasSprintTileStatus.Loading;
    Assert.AreEqual('Wird geladen …', TAtlasTrackerSprintView.NoticeText(mTile));
    // Nie geladen und keine Antwort: der Grund statt „lädt“, ohne zweite Zeile.
    mTile.Status := TAtlasSprintTileStatus.Failed;
    mTile.Stale := True;
    mTile.Error := TAtlasCiFetchError.Unauthorized;
    Assert.AreEqual(TAtlasTrackerSprintView.ErrorText(TAtlasCiFetchError.Unauthorized),
      TAtlasTrackerSprintView.NoticeText(mTile));
    Assert.AreEqual('', TAtlasTrackerSprintView.StatusText(mTile));
    // Mit Stand: lädt bzw. „Stand vom … · Grund“.
    mTile := Running;
    Assert.AreEqual('', TAtlasTrackerSprintView.NoticeText(mTile));
    Assert.AreEqual('', TAtlasTrackerSprintView.StatusText(mTile));
    mTile.Loading := True;
    Assert.AreEqual('Wird geladen …', TAtlasTrackerSprintView.StatusText(mTile));
    mTile.Loading := False;
    mTile.Stale := True;
    mTile.Error := TAtlasCiFetchError.Network;
    mTile.Sprint.Fetched := EncodeDateTime(2026, 10, 28, 8, 12, 0, 0);
    Assert.AreEqual('Stand vom ' + FormatDateTime('dd.mm. hh:nn', TTimeZone.Local.ToLocalTime(mTile.Sprint.Fetched),
      FormatSettings) +
      ' · ' + TAtlasTrackerSprintView.ErrorText(TAtlasCiFetchError.Network),
      TAtlasTrackerSprintView.StatusText(mTile));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerSprintViewTests.DayHintWithValues;
var
  mSaved: TAtlasLanguage;
  mTile: TAtlasSprintTile;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mTile := Running;
    Assert.AreEqual('Tag 1 (27.10.): Rest 21 · ideal 15', TAtlasTrackerSprintView.DayHint(mTile, 1));
    // Künftiger Tag: noch kein Ist-Wert.
    Assert.AreEqual('Tag 2 (28.10.): Rest – · ideal 0', TAtlasTrackerSprintView.DayHint(mTile, 2));
    Assert.AreEqual('', TAtlasTrackerSprintView.DayHint(mTile, 3));
    Assert.AreEqual('', TAtlasTrackerSprintView.DayHint(mTile, -1));
    mTile.Sprint.HasPrevious := True;
    mTile.Sprint.Previous := TArray<Double>.Create(30, 18, 0);
    Assert.AreEqual('Tag 1 (27.10.): Rest 21 · ideal 15 · Vorsprint 18', TAtlasTrackerSprintView.DayHint(mTile, 1));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerSprintViewTests.EnglishTexts;
var
  mSaved: TAtlasLanguage;
  mTile: TAtlasSprintTile;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    mTile := Running;
    Assert.EndsWith('4 days left', TAtlasTrackerSprintView.HeadingText(mTile));
    Assert.AreEqual('21 points', TAtlasTrackerSprintView.NumberValue(mTile, 2));
    mTile.Sprint.UsesPoints := False;
    mTile.Sprint.TeamLeft := 3.5;
    Assert.AreEqual('3.5 issues', TAtlasTrackerSprintView.NumberValue(mTile, 2));
    mTile.Sprint.HasPrevious := True;
    mTile.Sprint.DoneToday := 5;
    mTile.Sprint.PreviousDone := 4;
    Assert.AreEqual('done 5 · previous sprint 4 on the same day ▲1', TAtlasTrackerSprintView.CompareText(mTile));
    mTile.Status := TAtlasSprintTileStatus.NoTracker;
    Assert.AreEqual('No board for this project – assign …', TAtlasTrackerSprintView.NoticeText(mTile));
    Assert.AreEqual('Sprint', TAtlasTrackerSprintView.TitleText);
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerSprintViewTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeSprint;
  mSource: IAtlasSprintSource;
  mFrame: TAtlasTrackerSprintView;
  mRect: TRect;
begin
  mFake := TFakeSprint.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFake.FTile := Running;
    mFrame := TAtlasTrackerSprintView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.AreEqual('shown', mFake.Calls[0], 'Anzeigen lädt bei Bedarf');
    // Klickflächen: Kopf, die drei Zahlen, Diagramm.
    Assert.IsTrue(mFrame.HitTest(20, 5) = TAtlasSprintHitKind.Title);
    mRect := mFrame.NumberRect(0, mFrame.ClientWidth);
    Assert.IsTrue(mFrame.HitTest(mRect.Left + 4, mRect.Top + 4) = TAtlasSprintHitKind.MineOpen);
    mRect := mFrame.NumberRect(2, mFrame.ClientWidth);
    Assert.IsTrue(mFrame.HitTest(mRect.Left + 4, mRect.Top + 4) = TAtlasSprintHitKind.TeamLeft);
    mRect := mFrame.ChartRect(mFrame.ClientWidth);
    Assert.IsTrue(mFrame.HitTest(mRect.Left + 10, mRect.Top + 10) = TAtlasSprintHitKind.Chart);
    mFake.Calls := nil;
    mFrame.ClickAt(TAtlasSprintHitKind.MineOpen);
    mFrame.ClickAt(TAtlasSprintHitKind.MineDone);
    mFrame.ClickAt(TAtlasSprintHitKind.TeamLeft);
    mFrame.ClickAt(TAtlasSprintHitKind.Title);
    Assert.AreEqual(Integer(0), Integer(Length(mFake.Calls)), 'nicht im Mausereignis');
    CheckSynchronize;
    Assert.AreEqual(Integer(4), Integer(Length(mFake.Calls)));
    Assert.AreEqual('filter open', mFake.Calls[0]);
    Assert.AreEqual('filter done', mFake.Calls[1]);
    Assert.AreEqual('board', mFake.Calls[2]);
    Assert.AreEqual('browse', mFake.Calls[3]);
    // Ohne Tracker: „zuordnen …“.
    mFake.FTile := Default(TAtlasSprintTile);
    mFake.FTile.Status := TAtlasSprintTileStatus.NoTracker;
    mFake.FTile.CanAssign := True;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.HitTest(20, 10) = TAtlasSprintHitKind.Assign);
    mFake.Calls := nil;
    mFrame.ClickAt(TAtlasSprintHitKind.Assign);
    CheckSynchronize;
    Assert.AreEqual('assign', mFake.Calls[0]);
  finally
    mHost.Free;
    mFake.Calls := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerSprintViewTests);

end.
