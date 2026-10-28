unit Atlas.Core.Tracker.IssueCache.Tests;

// Zwischenspeicher der Issue-Vorschau (#1264): Rundreise über JSON (ohne
// signierte Adressen), Ablage je Tracker und Kennung, Ablauf nach
// MaxAgeDays, Aufräumen alter Dateien, Grenze im Speicher (zuletzt benutzt
// bleibt) und reiner Speicherbetrieb ohne Ordner.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerIssueCacheTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure JsonRoundTripDropsSignedQuery;
    [Test]
    procedure FromJsonRejectsBrokenAndOtherVersions;
    [Test]
    procedure FileNamesPerTrackerAndKey;
    [Test]
    procedure DiskEntryExpiresAfterMaxAge;
    [Test]
    procedure PruneDeletesOldFiles;
    [Test]
    procedure MemoryKeepsRecentlyUsed;
    [Test]
    procedure WorksWithoutFolder;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.IssueCache;

const
  cNow = 46323.5;

function Target: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud', 'ATL', '');
end;

function Sample(const AKey: string; AFetched: TDateTime): TAtlasTrackerDetails;
var
  mComment: TAtlasTrackerComment;
  mAttachment: TAtlasTrackerAttachment;
  mLink: TAtlasTrackerLink;
begin
  Result := TAtlasTrackerDetails.Empty;
  Result.Key := AKey;
  Result.Number := 123;
  Result.Title := 'Tracker im Plugin';
  Result.Page := 'https://beispiel.youtrack.cloud/issue/' + AKey;
  Result.State := 'In Progress';
  Result.Priority := 'Major';
  Result.Kind := 'Feature';
  Result.Assignee := 'Marco B.';
  Result.Sprint := 'Sprint 42';
  Result.Labels := TArray<string>.Create('plugin', 'ui');
  Result.Created := cNow - 2;
  Result.Updated := cNow - 1;
  Result.Description := 'Zeile 1'#10'**fett** "Zitat"';
  Result.CommentsLoaded := True;
  mComment := Default(TAtlasTrackerComment);
  mComment.Author := 'kollege';
  mComment.Created := cNow - 0.5;
  mComment.Text := 'Kommentar';
  Result.Comments := [mComment];
  mAttachment := Default(TAtlasTrackerAttachment);
  mAttachment.Name := 'skizze.png';
  mAttachment.Size := 2048;
  mAttachment.Url := 'https://beispiel.youtrack.cloud/api/files/1-2?sign=geheim';
  mAttachment.MimeType := 'image/png';
  Result.Attachments := [mAttachment];
  mLink := Default(TAtlasTrackerLink);
  mLink.Key := 'ATL-100';
  mLink.Title := 'Einstellungen';
  mLink.Relation := 'depends on';
  mLink.Local := True;
  mLink.Kind := TAtlasTrackerLinkKind.DependsOn;
  mLink.StateKnown := True;
  mLink.State := 'In Progress';
  Result.Links := [mLink];
  Result.Fetched := AFetched;
end;

{ TAtlasTrackerIssueCacheTests }

procedure TAtlasTrackerIssueCacheTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasIssueCache-' + TGUID.NewGuid.ToString);
end;

procedure TAtlasTrackerIssueCacheTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TAtlasTrackerIssueCacheTests.JsonRoundTripDropsSignedQuery;
var
  mJson: string;
  mDetails: TAtlasTrackerDetails;
begin
  mJson := TAtlasTrackerIssueCache.ToJson(Sample('ATL-123', cNow));
  Assert.IsFalse(mJson.Contains('geheim'), 'keine Signatur auf der Platte');
  Assert.IsTrue(TAtlasTrackerIssueCache.FromJson(mJson, mDetails));
  Assert.AreEqual('ATL-123', mDetails.Key);
  Assert.AreEqual(Integer(123), mDetails.Number);
  Assert.AreEqual('Marco B.', mDetails.Assignee);
  Assert.AreEqual(Integer(2), Integer(Length(mDetails.Labels)));
  Assert.AreEqual('Zeile 1'#10'**fett** "Zitat"', mDetails.Description);
  Assert.IsTrue(mDetails.CommentsLoaded);
  Assert.AreEqual(Integer(1), Integer(Length(mDetails.Comments)));
  Assert.AreEqual('kollege', mDetails.Comments[0].Author);
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/files/1-2', mDetails.Attachments[0].Url);
  Assert.AreEqual<Int64>(2048, mDetails.Attachments[0].Size);
  Assert.AreEqual('depends on', mDetails.Links[0].Relation);
  Assert.IsTrue(mDetails.Links[0].Local);
  // Art und Zustand der Verknüpfung (#1279).
  Assert.IsTrue(mDetails.Links[0].Kind = TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(mDetails.Links[0].StateKnown);
  Assert.AreEqual('In Progress', mDetails.Links[0].State);
  Assert.IsFalse(mDetails.Links[0].Resolved);
  Assert.IsTrue(mDetails.Links[0].Blocking);
  Assert.IsTrue(SecondsBetween(cNow, mDetails.Fetched) < 1);
  Assert.IsTrue(SecondsBetween(cNow - 2, mDetails.Created) < 1);
end;

procedure TAtlasTrackerIssueCacheTests.FromJsonRejectsBrokenAndOtherVersions;
var
  mDetails: TAtlasTrackerDetails;
begin
  Assert.IsFalse(TAtlasTrackerIssueCache.FromJson('{kaputt', mDetails));
  Assert.IsFalse(TAtlasTrackerIssueCache.FromJson('[]', mDetails));
  Assert.IsFalse(TAtlasTrackerIssueCache.FromJson('{"version": 99, "key": "ATL-1"}', mDetails));
  Assert.IsFalse(TAtlasTrackerIssueCache.FromJson('{"version": 2, "key": ""}', mDetails));
  Assert.IsTrue(TAtlasTrackerIssueCache.FromJson('{"version": 2, "key": "ATL-1"}', mDetails));
  // Version 1 kennt die Art der Verknüpfungen nicht (#1279): gilt als fehlend und wird neu geladen.
  Assert.IsFalse(TAtlasTrackerIssueCache.FromJson('{"version": 1, "key": "ATL-1"}', mDetails));
end;

procedure TAtlasTrackerIssueCacheTests.FileNamesPerTrackerAndKey;
var
  mCache: TAtlasTrackerIssueCache;
  mOther: TAtlasTrackerTarget;
begin
  Assert.AreEqual('ATL-12', TAtlasTrackerIssueCache.SafeName('ATL-12'));
  Assert.AreEqual('753', TAtlasTrackerIssueCache.SafeName('#753'));
  Assert.AreEqual('etcpasswd', TAtlasTrackerIssueCache.SafeName('../etc/passwd'));
  Assert.AreEqual(Integer(8), Integer(Length(TAtlasTrackerIssueCache.TrackerId(Target))));
  mOther := TAtlasTrackerTarget.Create('youtrack', 'https://andere.youtrack.cloud', 'ATL', '');
  Assert.AreNotEqual(TAtlasTrackerIssueCache.TrackerId(Target), TAtlasTrackerIssueCache.TrackerId(mOther));
  mCache := TAtlasTrackerIssueCache.Create(FFolder);
  try
    mCache.Put(Target, Sample('ATL-123', cNow));
    Assert.IsTrue(TFile.Exists(TPath.Combine(TPath.Combine(FFolder, TAtlasTrackerIssueCache.TrackerId(Target)),
      'ATL-123.json')));
  finally
    mCache.Free;
  end;
end;

procedure TAtlasTrackerIssueCacheTests.DiskEntryExpiresAfterMaxAge;
var
  mCache: TAtlasTrackerIssueCache;
  mDetails: TAtlasTrackerDetails;
begin
  mCache := TAtlasTrackerIssueCache.Create(FFolder);
  try
    mCache.Put(Target, Sample('ATL-123', cNow));
  finally
    mCache.Free;
  end;
  // Neue Sitzung: nur von der Platte.
  mCache := TAtlasTrackerIssueCache.Create(FFolder);
  try
    Assert.IsTrue(mCache.Get(Target, 'ATL-123', cNow + TAtlasTrackerIssueCache.MaxAgeDays - 0.1, mDetails));
    Assert.AreEqual('Tracker im Plugin', mDetails.Title);
  finally
    mCache.Free;
  end;
  mCache := TAtlasTrackerIssueCache.Create(FFolder);
  try
    Assert.IsFalse(mCache.Get(Target, 'ATL-123', cNow + TAtlasTrackerIssueCache.MaxAgeDays + 0.1, mDetails));
    Assert.AreEqual('', mDetails.Key);
    Assert.IsFalse(mCache.Get(Target, 'ATL-999', cNow, mDetails), 'unbekannt');
  finally
    mCache.Free;
  end;
end;

procedure TAtlasTrackerIssueCacheTests.PruneDeletesOldFiles;
var
  mCache: TAtlasTrackerIssueCache;
  mFolder: string;
begin
  mCache := TAtlasTrackerIssueCache.Create(FFolder);
  try
    mCache.Put(Target, Sample('ATL-1', cNow - TAtlasTrackerIssueCache.MaxAgeDays - 1));
    mCache.Put(Target, Sample('ATL-2', cNow));
    mFolder := TPath.Combine(FFolder, TAtlasTrackerIssueCache.TrackerId(Target));
    TFile.WriteAllText(TPath.Combine(mFolder, 'kaputt.json'), '{');
    mCache.Prune(cNow);
    Assert.IsFalse(TFile.Exists(TPath.Combine(mFolder, 'ATL-1.json')), 'alt');
    Assert.IsFalse(TFile.Exists(TPath.Combine(mFolder, 'kaputt.json')), 'kaputt');
    Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, 'ATL-2.json')), 'frisch');
    mCache.Prune(cNow + TAtlasTrackerIssueCache.MaxAgeDays + 1);
    Assert.IsFalse(TDirectory.Exists(mFolder), 'leerer Ordner entfällt');
  finally
    mCache.Free;
  end;
end;

procedure TAtlasTrackerIssueCacheTests.MemoryKeepsRecentlyUsed;
var
  mCache: TAtlasTrackerIssueCache;
  mIndex: Integer;
  mDetails: TAtlasTrackerDetails;
begin
  mCache := TAtlasTrackerIssueCache.Create('');
  try
    for mIndex := 1 to TAtlasTrackerIssueCache.MaxMemory do
      mCache.Put(Target, Sample('ATL-' + IntToStr(mIndex), cNow));
    // ATL-1 benutzen: danach fällt ATL-2 als ältestes heraus.
    Assert.IsTrue(mCache.Get(Target, 'ATL-1', cNow, mDetails));
    mCache.Put(Target, Sample('ATL-999', cNow));
    Assert.AreEqual(Integer(TAtlasTrackerIssueCache.MaxMemory), mCache.Count);
    Assert.IsTrue(mCache.Get(Target, 'ATL-1', cNow, mDetails));
    Assert.IsFalse(mCache.Get(Target, 'ATL-2', cNow, mDetails));
    Assert.IsTrue(mCache.Get(Target, 'atl-999', cNow, mDetails), 'Kennung ohne Groß-/Kleinschreibung');
  finally
    mCache.Free;
  end;
end;

procedure TAtlasTrackerIssueCacheTests.WorksWithoutFolder;
var
  mCache: TAtlasTrackerIssueCache;
  mDetails: TAtlasTrackerDetails;
begin
  mCache := TAtlasTrackerIssueCache.Create('');
  try
    mCache.Put(Target, Sample('ATL-5', cNow));
    mCache.Put(Target, Sample('', cNow));
    Assert.AreEqual(Integer(1), mCache.Count, 'ohne Kennung nicht gemerkt');
    Assert.IsTrue(mCache.Get(Target, 'ATL-5', cNow + 30, mDetails), 'im Speicher ohne Ablauf');
    mCache.Prune(cNow);
  finally
    mCache.Free;
  end;
  Assert.IsFalse(TDirectory.Exists(FFolder));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerIssueCacheTests);

end.
