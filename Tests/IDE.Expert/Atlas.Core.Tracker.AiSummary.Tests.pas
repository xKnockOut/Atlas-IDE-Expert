unit Atlas.Core.Tracker.AiSummary.Tests;

// Tests der Issue-Zusammenfassung mit KI (#2462) ohne Netz und Oberfläche:
// Aufbau der Eingabe (Felder, Verknüpfungen, Kürzen langer Verläufe), Lesen der
// Antwort (Codeblock, Fragen als Text oder Objekt, Unit-Namen), Prüfung der
// Units gegen die Dateien des Projekts, Kommentartext, Knopf ab einer Zahl von
// Kommentaren, Zwischenspeicher mit „veraltet“ und gespeichertem Stand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueSummaryTests = class
  public
    [Test]
    procedure InputHasFieldsDescriptionCommentsAndLinks;
    [Test]
    procedure LongHistoryKeepsFirstAndNewestComments;
    [Test]
    procedure InstructionsNameLanguageAndFormat;
    [Test]
    procedure ParseReadsFencedJson;
    [Test]
    procedure ParseWithoutStatusFails;
    [Test]
    procedure UnitsOnlyWhenTheProjectHasThem;
    [Test]
    procedure CommentHasAllSections;
    [Test]
    procedure ButtonFromMinimumComments;
    [Test]
    procedure CacheIsStaleAfterChange;
    [Test]
    procedure CacheSurvivesJson;
    [Test]
    procedure CacheDropsOldestEntries;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.AiSummary;

function CommentOf(const AAuthor, AText: string; ADay: Integer): TAtlasTrackerComment;
begin
  Result := Default(TAtlasTrackerComment);
  Result.Author := AAuthor;
  Result.Text := AText;
  Result.Created := EncodeDate(2026, 11, ADay);
end;

function DetailsOf(ACommentCount, ACommentLength: Integer): TAtlasTrackerDetails;
var
  mIndex: Integer;
begin
  Result := TAtlasTrackerDetails.Empty;
  Result.Key := 'ATL-7';
  Result.Title := 'Absturz beim Speichern';
  Result.State := 'In Arbeit';
  Result.Assignee := 'M. Muster';
  Result.Labels := ['bug', 'ui'];
  Result.Description := 'Beim Speichern stürzt die IDE ab.';
  SetLength(Result.Comments, ACommentCount);
  for mIndex := 0 to ACommentCount - 1 do
  begin
    Result.Comments[mIndex] := CommentOf('Autor' + IntToStr(mIndex),
      'Kommentar' + IntToStr(mIndex) + ' ' + StringOfChar('x', ACommentLength), 1 + mIndex mod 28);
  end;
end;

procedure TAtlasIssueSummaryTests.InputHasFieldsDescriptionCommentsAndLinks;
var
  mDetails: TAtlasTrackerDetails;
  mLink: TAtlasTrackerLink;
  mInput: string;
begin
  mDetails := DetailsOf(2, 5);
  mLink := Default(TAtlasTrackerLink);
  mLink.Key := 'ATL-3';
  mLink.Title := 'Speichern langsam';
  mLink.Relation := 'relates to';
  mLink.StateKnown := True;
  mLink.State := 'Offen';
  mDetails.Links := [mLink];
  mInput := TAtlasIssueSummaries.Input(mDetails, TAtlasIssueSummaries.cMaxInput);
  Assert.IsTrue(mInput.StartsWith('Issue ATL-7: Absturz beim Speichern'), 'Kopf');
  Assert.IsTrue(mInput.Contains('State: In Arbeit; Assignee: M. Muster; Labels: bug, ui'), 'Felder');
  Assert.IsTrue(mInput.Contains('Beim Speichern stürzt die IDE ab.'), 'Beschreibung');
  Assert.IsTrue(mInput.Contains('Comments (2, oldest first):'), 'Kommentare gezählt');
  Assert.IsTrue(mInput.Contains('--- Autor0, 2026-11-01'), 'Autor und Datum');
  Assert.IsTrue(mInput.Contains('- ATL-3 Speichern langsam (relates to) [Offen]'), 'Verknüpfung');
  Assert.IsFalse(mInput.Contains('omitted'), 'nichts ausgelassen');
end;

procedure TAtlasIssueSummaryTests.LongHistoryKeepsFirstAndNewestComments;
var
  mInput: string;
begin
  mInput := TAtlasIssueSummaries.Input(DetailsOf(40, 1000), 12000);
  Assert.IsTrue(Length(mInput) < 13000, 'Länge begrenzt: ' + IntToStr(Length(mInput)));
  Assert.IsTrue(mInput.Contains('Kommentar0 '), 'erster Kommentar bleibt');
  Assert.IsTrue(mInput.Contains('Kommentar39 '), 'neuester Kommentar bleibt');
  Assert.IsFalse(mInput.Contains('Kommentar1 '), 'früher Kommentar fällt weg');
  Assert.IsTrue(mInput.Contains('comments omitted]'), 'Hinweis auf ausgelassene');
  Assert.IsTrue(mInput.IndexOf('Kommentar0 ') < mInput.IndexOf('omitted'), 'Reihenfolge bleibt');
  mInput := TAtlasIssueSummaries.Input(DetailsOf(1, 10000), TAtlasIssueSummaries.cMaxInput);
  Assert.IsTrue(mInput.Contains(' […]'), 'langer Kommentar gekürzt');
end;

procedure TAtlasIssueSummaryTests.InstructionsNameLanguageAndFormat;
var
  mText: string;
begin
  mText := TAtlasIssueSummaries.Instructions('German');
  Assert.IsTrue(mText.Contains('in German'), 'Sprache');
  Assert.IsTrue(mText.Contains('"openQuestions"'), 'Format');
  Assert.IsTrue(mText.Contains('Do not invent'), 'nichts erfinden');
end;

procedure TAtlasIssueSummaryTests.ParseReadsFencedJson;
var
  mSummary: TAtlasIssueSummary;
begin
  Assert.IsTrue(TAtlasIssueSummaries.TryParse('Hier:' + sLineBreak + '```json' + sLineBreak +
    '{"status": " Fix liegt im PR. ", "openQuestions": [{"question": "Welche Version?", "who": "Anna"}, ' +
    '"Nur Win64?", {"who": "Leer"}], "nextStep": "PR prüfen", ' +
    '"units": ["Atlas.Core.Save.pas", "Atlas.UI.Main", "kein Name!", 3]}' + sLineBreak + '```', mSummary));
  Assert.AreEqual('Fix liegt im PR.', mSummary.Status);
  Assert.AreEqual(2, Integer(Length(mSummary.Questions)), 'Fragen ohne Text fallen weg');
  Assert.AreEqual('Welche Version?', mSummary.Questions[0].Question);
  Assert.AreEqual('Anna', mSummary.Questions[0].Who);
  Assert.AreEqual('Nur Win64?', mSummary.Questions[1].Question);
  Assert.AreEqual('', mSummary.Questions[1].Who);
  Assert.AreEqual('PR prüfen', mSummary.NextStep);
  Assert.AreEqual(2, Integer(Length(mSummary.Units)), 'nur Unit-Namen');
  Assert.AreEqual('Atlas.Core.Save', mSummary.Units[0], 'ohne Endung');
  Assert.AreEqual('Atlas.UI.Main', mSummary.Units[1]);
end;

procedure TAtlasIssueSummaryTests.ParseWithoutStatusFails;
var
  mSummary: TAtlasIssueSummary;
begin
  Assert.IsFalse(TAtlasIssueSummaries.TryParse('Das Issue ist fast fertig.', mSummary), 'kein JSON');
  Assert.IsFalse(TAtlasIssueSummaries.TryParse('{"nextStep": "x"}', mSummary), 'ohne Stand');
  Assert.IsFalse(TAtlasIssueSummaries.TryParse('{"status": ', mSummary), 'abgebrochen');
end;

procedure TAtlasIssueSummaryTests.UnitsOnlyWhenTheProjectHasThem;
var
  mUnits: TArray<TAtlasIssueSummaryUnit>;
begin
  mUnits := TAtlasIssueSummaries.KnownUnits(
    TArray<string>.Create('atlas.core.save', 'Erfunden.Unit', 'Atlas.Core.Save', 'Atlas.UI.Main'),
    TArray<string>.Create('C:\Src\Atlas.Core.Save.pas', 'C:\Src\Atlas.UI.Main.dfm', 'src/Atlas.UI.Main.pas',
    'C:\Src\Erfunden.Unit.inc'));
  Assert.AreEqual(2, Integer(Length(mUnits)), 'nur vorhandene, ohne Doppelte');
  Assert.AreEqual('Atlas.Core.Save', mUnits[0].Name, 'Name wie die Datei');
  Assert.AreEqual('C:\Src\Atlas.Core.Save.pas', mUnits[0].Path);
  Assert.AreEqual('src/Atlas.UI.Main.pas', mUnits[1].Path, 'nur .pas');
end;

procedure TAtlasIssueSummaryTests.CommentHasAllSections;
var
  mSummary: TAtlasIssueSummary;
  mHeads: TAtlasIssueSummaryHeads;
  mQuestion: TAtlasIssueSummaryQuestion;
  mText: string;
begin
  mSummary := Default(TAtlasIssueSummary);
  mSummary.Status := 'Fix liegt im PR.';
  mQuestion := Default(TAtlasIssueSummaryQuestion);
  mQuestion.Question := 'Welche Version?';
  mQuestion.Who := 'Anna';
  mSummary.Questions := [mQuestion];
  mSummary.NextStep := 'PR prüfen';
  mSummary.Units := ['Atlas.Core.Save'];
  mHeads := Default(TAtlasIssueSummaryHeads);
  mHeads.Title := 'Zusammenfassung';
  mHeads.Status := 'Stand:';
  mHeads.Questions := 'Offene Fragen:';
  mHeads.NextStep := 'Nächster Schritt:';
  mHeads.Units := 'Units:';
  mHeads.Footer := 'Mit KI zusammengefasst';
  mText := TAtlasIssueSummaries.AsComment(mSummary, mHeads);
  Assert.IsTrue(mText.StartsWith('**Zusammenfassung**'), 'Titel');
  Assert.IsTrue(mText.Contains('**Stand:** Fix liegt im PR.'), 'Stand');
  Assert.IsTrue(mText.Contains('- Welche Version? (Anna)'), 'Frage mit wem');
  Assert.IsTrue(mText.Contains('**Nächster Schritt:** PR prüfen'), 'nächster Schritt');
  Assert.IsTrue(mText.Contains('`Atlas.Core.Save`'), 'Units');
  Assert.IsTrue(mText.Contains('_Mit KI zusammengefasst_'), 'Fußzeile');
end;

procedure TAtlasIssueSummaryTests.ButtonFromMinimumComments;
begin
  Assert.IsTrue(TAtlasIssueSummaries.ShowButton(0, 0), '0 = immer');
  Assert.IsFalse(TAtlasIssueSummaries.ShowButton(4, 5), 'zu wenige');
  Assert.IsTrue(TAtlasIssueSummaries.ShowButton(5, 5), 'genug');
end;

procedure TAtlasIssueSummaryTests.CacheIsStaleAfterChange;
var
  mCache: TAtlasIssueSummaryCache;
  mDetails: TAtlasTrackerDetails;
  mSummary: TAtlasIssueSummary;
  mStale: Boolean;
  mId, mStamp: string;
begin
  mCache := TAtlasIssueSummaryCache.Create;
  try
    mDetails := DetailsOf(3, 5);
    mDetails.Updated := EncodeDateTime(2026, 11, 18, 10, 0, 0, 0);
    mId := TAtlasIssueSummaryCache.KeyOf(TAtlasTrackerTarget.Create('youtrack', 'https://x.youtrack.cloud', 'ATL',
      ''), 'ATL-7');
    mStamp := TAtlasIssueSummaries.StampOf(mDetails);
    Assert.IsFalse(mCache.Find(mId, mStamp, mSummary, mStale), 'leer');
    mSummary.Status := 'Stand';
    mCache.Put(mId, mStamp, mSummary);
    Assert.IsTrue(mCache.Changed, 'geändert');
    Assert.IsTrue(mCache.Find(mId, mStamp, mSummary, mStale), 'gefunden');
    Assert.IsFalse(mStale, 'gleicher Stand');
    mDetails.Comments := mDetails.Comments + [CommentOf('Neu', 'Noch was', 20)];
    Assert.IsTrue(mCache.Find(mId, TAtlasIssueSummaries.StampOf(mDetails), mSummary, mStale), 'noch da');
    Assert.IsTrue(mStale, 'neuer Kommentar: veraltet');
    Assert.AreEqual('Stand', mSummary.Status, 'alter Inhalt bleibt sichtbar');
  finally
    mCache.Free;
  end;
end;

procedure TAtlasIssueSummaryTests.CacheSurvivesJson;
var
  mCache, mLoaded: TAtlasIssueSummaryCache;
  mSummary: TAtlasIssueSummary;
  mQuestion: TAtlasIssueSummaryQuestion;
  mStale: Boolean;
begin
  mCache := TAtlasIssueSummaryCache.Create;
  mLoaded := TAtlasIssueSummaryCache.Create;
  try
    mSummary := Default(TAtlasIssueSummary);
    mSummary.Status := 'Stand äöü';
    mQuestion := Default(TAtlasIssueSummaryQuestion);
    mQuestion.Question := 'Wer?';
    mQuestion.Who := 'Anna';
    mSummary.Questions := [mQuestion];
    mSummary.NextStep := 'Weiter';
    mSummary.Units := ['A.B'];
    mCache.Put('gh|#1', 's1', mSummary);
    mCache.Acknowledge('GitHub|Owner/Repo');
    Assert.IsTrue(mLoaded.LoadJson(mCache.ToJson), 'gelesen');
    Assert.IsFalse(mLoaded.Changed, 'frisch geladen');
    Assert.IsTrue(mLoaded.Find('gh|#1', 's1', mSummary, mStale), 'Eintrag');
    Assert.AreEqual('Stand äöü', mSummary.Status);
    Assert.AreEqual('Anna', mSummary.Questions[0].Who);
    Assert.AreEqual('Weiter', mSummary.NextStep);
    Assert.AreEqual('A.B', mSummary.Units[0]);
    Assert.IsTrue(mLoaded.Acknowledged('github|owner/repo'), 'Hinweis bestätigt');
    Assert.IsFalse(mLoaded.Acknowledged('youtrack|x'), 'andere Verbindung nicht');
    Assert.IsFalse(mLoaded.LoadJson('kein json'), 'ungültig');
    Assert.IsFalse(mLoaded.Find('gh|#1', 's1', mSummary, mStale), 'ungültig = leer');
  finally
    mLoaded.Free;
    mCache.Free;
  end;
end;

procedure TAtlasIssueSummaryTests.CacheDropsOldestEntries;
var
  mCache: TAtlasIssueSummaryCache;
  mSummary: TAtlasIssueSummary;
  mStale: Boolean;
  mIndex: Integer;
begin
  mCache := TAtlasIssueSummaryCache.Create;
  try
    mSummary := Default(TAtlasIssueSummary);
    mSummary.Status := 'x';
    for mIndex := 0 to TAtlasIssueSummaryCache.cMaxEntries do
    begin
      mCache.Put('id' + IntToStr(mIndex), 's', mSummary);
    end;
    Assert.IsFalse(mCache.Find('id0', 's', mSummary, mStale), 'ältester fällt heraus');
    Assert.IsTrue(mCache.Find('id1', 's', mSummary, mStale), 'zweiter bleibt');
  finally
    mCache.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueSummaryTests);

end.
