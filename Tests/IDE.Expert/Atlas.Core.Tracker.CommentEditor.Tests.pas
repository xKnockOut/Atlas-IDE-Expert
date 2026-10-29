unit Atlas.Core.Tracker.CommentEditor.Tests;

// Tests des Kommentar-Editors (#1278) ohne VCL und ohne Server: Auslöser an
// der Schreibmarke ("@", "#", Projektkürzel), Einsetzen eines Vorschlags,
// Markdown-Kürzel (fett, kursiv, Code-Block), Textbausteine mit
// Platzhaltern, Entwürfe im Speicher und in der Datei, Benutzer je Tracker
// (YouTrack /api/users, GitHub …/assignees) mit Rang und Filter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCommentEditorTests = class
  public
    /// <summary>"@an" am Ende und mitten im Satz; Start und Länge wie SelStart eines Memos.</summary>
    [Test]
    procedure MentionAtCaret;
    /// <summary>Kein Auslöser in E-Mail-Adressen, mitten im Wort, ohne Buchstaben, nach "`" oder "/".</summary>
    [Test]
    procedure NoMentionInMailOrWord;
    /// <summary>GitHub: "#42" liest, "#Speicher" sucht, "ATL-12" gehört nicht zum Tracker.</summary>
    [Test]
    procedure IssueTriggerGitHub;
    /// <summary>YouTrack: "ATL-12", "ATL-Speicher", "ATL-" (zuletzt geöffnet), "#42"; nicht in Pfaden.</summary>
    [Test]
    procedure IssueTriggerYouTrack;
    /// <summary>Vorschlag ersetzt das getippte Wort; am Ende folgt ein Leerzeichen, vorhandene bleiben.</summary>
    [Test]
    procedure ReplaceWord;
    /// <summary>Fett und kursiv an und aus, mit und ohne Auswahl.</summary>
    [Test]
    procedure ToggleBoldAndItalic;
    /// <summary>Code-Block auf eigenen Zeilen mit Sprache pascal; Auswahl bleibt der Code.</summary>
    [Test]
    procedure CodeBlockOnOwnLines;
    [Test]
    procedure InsertReplacesSelection;
    [Test]
    procedure RowsOfUsersAndIssues;
    /// <summary>Platzhalter ohne Groß-/Kleinschreibung; ein leerer Wert lässt den Platzhalter stehen.</summary>
    [Test]
    procedure SnippetPlaceholders;
    /// <summary>JSON hin und zurück, leere Einträge fallen weg, ungültiges JSON ergibt die Vorgaben.</summary>
    [Test]
    procedure SnippetsJson;
    /// <summary>Vorgabe der Einstellung issues.commentSnippets = TAtlasCommentSnippets.Defaults.</summary>
    [Test]
    procedure SnippetDefaultsMatchSetting;
    /// <summary>Je Tracker, Issue und Feld; nur Leerraum löscht; neueste zuerst, höchstens MaxDrafts.</summary>
    [Test]
    procedure DraftsPutGetDelete;
    /// <summary>JSON und Datei hin und zurück (Zeit in UTC); fremde Version ergibt leer.</summary>
    [Test]
    procedure DraftsRoundTrip;
    /// <summary>Rang: Anmeldename vorn, dann Wort des Namens, dann enthalten; Filter und Ranked.</summary>
    [Test]
    procedure UsersRankAndFilter;
    /// <summary>YouTrack: Adresse mit Text und Grenze, gesperrte Benutzer fallen weg, Antwort über Transport.</summary>
    [Test]
    procedure YouTrackUsers;
    /// <summary>GitHub: zuweisbare Benutzer, gefiltert nach dem Text.</summary>
    [Test]
    procedure GitHubUsers;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.CommentEditor;

type
  /// <summary>Transport mit einer festen Antwort; merkt die Adressen.</summary>
  TUsersTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FStatus: Integer;
    FText: string;
  public
    Calls: TArray<string>;
    constructor Create(AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

constructor TUsersTransport.Create(AStatus: Integer; const AText: string);
begin
  inherited Create;
  FStatus := AStatus;
  FText := AText;
end;

function TUsersTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  Calls := Calls + [AUrl];
  AStatus := FStatus;
  AText := FText;
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de/', 'ATL', '');
end;

function TriggerAtEnd(const AText: string; const ATarget: TAtlasTrackerTarget): TAtlasCommentTrigger;
begin
  Result := TAtlasCommentEditing.Trigger(AText, Length(AText), ATarget);
end;

function KindAtEnd(const AText: string; const ATarget: TAtlasTrackerTarget): TAtlasCommentTriggerKind;
begin
  Result := TriggerAtEnd(AText, ATarget).Kind;
end;

function User(const ALogin, AName: string): TAtlasTrackerUser;
begin
  Result := TAtlasTrackerUser.Create(ALogin, AName);
end;

function Logins(const AUsers: TArray<TAtlasTrackerUser>): string;
var
  mUser: TAtlasTrackerUser;
begin
  Result := '';
  for mUser in AUsers do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + mUser.Login;
  end;
end;

{ TAtlasCommentEditorTests }

procedure TAtlasCommentEditorTests.MentionAtCaret;
var
  mTrigger: TAtlasCommentTrigger;
begin
  mTrigger := TriggerAtEnd('Danke @an', GitHubTarget);
  Assert.IsTrue(mTrigger.Kind = TAtlasCommentTriggerKind.Mention);
  Assert.AreEqual('an', mTrigger.Text);
  Assert.AreEqual(6, mTrigger.Start, 'vor dem "@"');
  Assert.AreEqual(3, mTrigger.Length);
  // Mitten im Text: die Schreibmarke direkt hinter dem Wort.
  mTrigger := TAtlasCommentEditing.Trigger('@ber, bitte prüfen', 4, GitHubTarget);
  Assert.IsTrue(mTrigger.Kind = TAtlasCommentTriggerKind.Mention);
  Assert.AreEqual('ber', mTrigger.Text);
  Assert.AreEqual(0, mTrigger.Start);
  // Über Zeilen: CR LF zählen wie im Memo.
  mTrigger := TriggerAtEnd('Hallo'#13#10'@anna.b', GitHubTarget);
  Assert.AreEqual('anna.b', mTrigger.Text);
  Assert.AreEqual(7, mTrigger.Start);
  Assert.IsTrue(mTrigger.SameAs(TriggerAtEnd('@ANNA.B', GitHubTarget)), 'ohne Groß-/Kleinschreibung');
end;

procedure TAtlasCommentEditorTests.NoMentionInMailOrWord;
begin
  Assert.IsTrue(KindAtEnd('mail an anna@firma', GitHubTarget) = TAtlasCommentTriggerKind.None, 'E-Mail');
  Assert.IsTrue(TAtlasCommentEditing.Trigger('@anna', 3, GitHubTarget).Kind = TAtlasCommentTriggerKind.None,
    'mitten im Wort');
  Assert.IsTrue(KindAtEnd('Preis @1', GitHubTarget) = TAtlasCommentTriggerKind.None, 'ohne Buchstaben');
  Assert.IsTrue(KindAtEnd('@', GitHubTarget) = TAtlasCommentTriggerKind.None, 'nur das Zeichen');
  Assert.IsTrue(KindAtEnd('`@Override', GitHubTarget) = TAtlasCommentTriggerKind.None, 'im Code');
  Assert.IsTrue(KindAtEnd('pfad/@scope', GitHubTarget) = TAtlasCommentTriggerKind.None, 'im Pfad');
  Assert.IsTrue(KindAtEnd('@@an', GitHubTarget) = TAtlasCommentTriggerKind.None, 'doppelt');
  Assert.IsTrue(TAtlasCommentEditing.Trigger('', 0, GitHubTarget).Kind = TAtlasCommentTriggerKind.None);
  Assert.IsTrue(TAtlasCommentEditing.Trigger('@an', 9, GitHubTarget).Kind = TAtlasCommentTriggerKind.None,
    'Schreibmarke hinter dem Text');
end;

procedure TAtlasCommentEditorTests.IssueTriggerGitHub;
var
  mTrigger: TAtlasCommentTrigger;
begin
  mTrigger := TriggerAtEnd('siehe #42', GitHubTarget);
  Assert.IsTrue(mTrigger.Kind = TAtlasCommentTriggerKind.Issue);
  Assert.IsTrue(mTrigger.Query.Kind = TAtlasIssueSearchKind.Key);
  Assert.AreEqual('#42', mTrigger.Query.Key);
  Assert.AreEqual(6, mTrigger.Start);
  Assert.AreEqual(3, mTrigger.Length);
  mTrigger := TriggerAtEnd('wie #Speicher', GitHubTarget);
  Assert.IsTrue(mTrigger.Query.Kind = TAtlasIssueSearchKind.Text);
  Assert.AreEqual('Speicher', mTrigger.Query.Text);
  Assert.IsTrue(KindAtEnd('siehe #', GitHubTarget) = TAtlasCommentTriggerKind.None, '"#" allein nicht');
  Assert.IsTrue(KindAtEnd('ATL-12', GitHubTarget) = TAtlasCommentTriggerKind.None, 'kein Kürzel bei GitHub');
  Assert.IsTrue(KindAtEnd('Farbe a#42', GitHubTarget) = TAtlasCommentTriggerKind.None, 'mitten im Wort');
  Assert.IsTrue(KindAtEnd('```#42', GitHubTarget) = TAtlasCommentTriggerKind.None, 'im Code');
end;

procedure TAtlasCommentEditorTests.IssueTriggerYouTrack;
var
  mTrigger: TAtlasCommentTrigger;
begin
  mTrigger := TriggerAtEnd('hängt an ATL-12', YouTrackTarget);
  Assert.IsTrue(mTrigger.Kind = TAtlasCommentTriggerKind.Issue);
  Assert.IsTrue(mTrigger.Query.Kind = TAtlasIssueSearchKind.Key);
  Assert.AreEqual('ATL-12', mTrigger.Query.Key);
  Assert.AreEqual(9, mTrigger.Start, 'ohne "#" beginnt das Wort beim Kürzel');
  Assert.AreEqual(6, mTrigger.Length);
  mTrigger := TriggerAtEnd('atl-Speicher', YouTrackTarget);
  Assert.IsTrue(mTrigger.Query.Kind = TAtlasIssueSearchKind.Text);
  Assert.AreEqual('Speicher', mTrigger.Query.Text);
  Assert.IsTrue(TriggerAtEnd('ATL-', YouTrackTarget).Query.Kind = TAtlasIssueSearchKind.Recent, 'zuletzt geöffnet');
  mTrigger := TriggerAtEnd('#42', YouTrackTarget);
  Assert.AreEqual('ATL-42', mTrigger.Query.Key, 'Nummer im Projekt');
  Assert.IsTrue(KindAtEnd('C:\Daten\ATL-1', YouTrackTarget) = TAtlasCommentTriggerKind.None, 'Pfad');
  Assert.IsTrue(KindAtEnd('ein well-known', YouTrackTarget) = TAtlasCommentTriggerKind.None, 'Bindestrich');
  Assert.IsTrue(KindAtEnd('XYZ-12', YouTrackTarget) = TAtlasCommentTriggerKind.None, 'fremdes Kürzel');
end;

procedure TAtlasCommentEditorTests.ReplaceWord;
var
  mText: string;
  mCaret: Integer;
begin
  mText := TAtlasCommentEditing.Replace('Danke @an', TriggerAtEnd('Danke @an', GitHubTarget), '@anna', mCaret);
  Assert.AreEqual('Danke @anna ', mText, 'am Ende ein Leerzeichen');
  Assert.AreEqual(12, mCaret);
  mText := TAtlasCommentEditing.Replace('@an und', TAtlasCommentEditing.Trigger('@an und', 3, GitHubTarget), '@anna',
    mCaret);
  Assert.AreEqual('@anna und', mText, 'vorhandenes Leerzeichen bleibt allein');
  Assert.AreEqual(6, mCaret, 'hinter dem Leerzeichen');
  mText := TAtlasCommentEditing.Replace('(ATL-1)', TAtlasCommentEditing.Trigger('(ATL-1)', 6, YouTrackTarget),
    'ATL-12', mCaret);
  Assert.AreEqual('(ATL-12)', mText, 'vor Satzzeichen nichts ergänzen');
  Assert.AreEqual(7, mCaret);
end;

procedure TAtlasCommentEditorTests.ToggleBoldAndItalic;
var
  mText: string;
  mStart, mLength: Integer;
begin
  mText := TAtlasCommentEditing.ToggleInline('ab cd', 3, 2, TAtlasCommentEditing.BoldMarker, mStart, mLength);
  Assert.AreEqual('ab **cd**', mText);
  Assert.AreEqual(5, mStart);
  Assert.AreEqual(2, mLength);
  mText := TAtlasCommentEditing.ToggleInline(mText, mStart, mLength, TAtlasCommentEditing.BoldMarker, mStart,
    mLength);
  Assert.AreEqual('ab cd', mText, 'zweites Mal: aus');
  Assert.AreEqual(3, mStart);
  Assert.AreEqual(2, mLength);
  mText := TAtlasCommentEditing.ToggleInline('ab **cd**', 3, 6, TAtlasCommentEditing.BoldMarker, mStart, mLength);
  Assert.AreEqual('ab cd', mText, 'Auswahl samt Zeichen');
  Assert.AreEqual(3, mStart);
  Assert.AreEqual(2, mLength);
  mText := TAtlasCommentEditing.ToggleInline('ab', 2, 0, TAtlasCommentEditing.ItalicMarker, mStart, mLength);
  Assert.AreEqual('ab__', mText, 'ohne Auswahl ein leeres Paar');
  Assert.AreEqual(3, mStart, 'Schreibmarke dazwischen');
  Assert.AreEqual(0, mLength);
end;

procedure TAtlasCommentEditorTests.CodeBlockOnOwnLines;
var
  mText: string;
  mStart, mLength: Integer;
begin
  mText := TAtlasCommentEditing.CodeBlock('x := 1;', 0, 7, mStart, mLength);
  Assert.AreEqual('```pascal'#13#10'x := 1;'#13#10'```', mText);
  Assert.AreEqual(11, mStart);
  Assert.AreEqual(7, mLength);
  mText := TAtlasCommentEditing.CodeBlock('Fehler: x := 1; danach', 8, 7, mStart, mLength);
  Assert.AreEqual('Fehler: '#13#10'```pascal'#13#10'x := 1;'#13#10'```'#13#10' danach', mText,
    'Zaun auf eigenen Zeilen');
  Assert.AreEqual('x := 1;', Copy(mText, mStart + 1, mLength));
  mText := TAtlasCommentEditing.CodeBlock('a'#13#10'b'#13#10, 3, 3, mStart, mLength);
  Assert.AreEqual('a'#13#10'```pascal'#13#10'b'#13#10'```'#13#10, mText, 'Umbruch am Ende hinter den Block');
  mText := TAtlasCommentEditing.CodeBlock('abc', 3, 0, mStart, mLength);
  Assert.AreEqual('abc'#13#10'```pascal'#13#10#13#10'```', mText, 'leerer Block');
  Assert.AreEqual(16, mStart);
  Assert.AreEqual(0, mLength);
end;

procedure TAtlasCommentEditorTests.InsertReplacesSelection;
var
  mText: string;
  mCaret: Integer;
begin
  mText := TAtlasCommentEditing.Insert('Hallo Welt', 6, 4, 'Anna', mCaret);
  Assert.AreEqual('Hallo Anna', mText);
  Assert.AreEqual(10, mCaret);
  mText := TAtlasCommentEditing.Insert('ab', 99, 5, 'c', mCaret);
  Assert.AreEqual('abc', mText, 'Grenzen eingehalten');
  Assert.AreEqual(3, mCaret);
end;

procedure TAtlasCommentEditorTests.RowsOfUsersAndIssues;
var
  mIssue: TAtlasTrackerIssue;
begin
  Assert.AreEqual('@anna · Anna Berger', TAtlasCommentEditing.UserRow(User('anna', 'Anna Berger')));
  Assert.AreEqual('@octocat', TAtlasCommentEditing.UserRow(User('octocat', '')));
  Assert.AreEqual('@anna', TAtlasCommentEditing.MentionText(User(' anna ', 'Anna')));
  mIssue := TAtlasTrackerIssue.Empty;
  mIssue.Key := 'ATL-12';
  mIssue.Title := 'Speicherleck';
  mIssue.State := 'In Arbeit';
  Assert.AreEqual('ATL-12 · Speicherleck · In Arbeit', TAtlasCommentEditing.IssueRow(mIssue));
  mIssue.State := '';
  Assert.AreEqual('ATL-12 · Speicherleck', TAtlasCommentEditing.IssueRow(mIssue));
end;

procedure TAtlasCommentEditorTests.SnippetPlaceholders;
var
  mValues: TAtlasCommentValues;
begin
  mValues := TAtlasCommentValues.Create('ATL-12', 'feature/ATL-12-leck', '4f2c9e1', '1.2.0.0');
  Assert.AreEqual('Behoben in 4f2c9e1 auf feature/ATL-12-leck (ATL-12, 1.2.0.0).',
    TAtlasCommentSnippets.Expand('Behoben in {commit} auf {Branch} ({ISSUE}, {version}).', mValues));
  mValues := TAtlasCommentValues.Create('ATL-12', '', '', '');
  Assert.AreEqual('Behoben in {commit}.', TAtlasCommentSnippets.Expand('Behoben in {commit}.', mValues),
    'unbekannt: Platzhalter bleibt sichtbar');
  Assert.IsTrue(TAtlasCommentSnippets.NeedsVcs('in {Branch}'));
  Assert.IsFalse(TAtlasCommentSnippets.NeedsVcs('Version {version}'));
end;

procedure TAtlasCommentEditorTests.SnippetsJson;
var
  mSnippets: TArray<TAtlasCommentSnippet>;
begin
  Assert.IsTrue(TAtlasCommentSnippets.Parse('[{"name":"A","text":"Erste"},{"name":"","text":"x"},' +
    '{"name":"B","text":"  "},3,{"name":" C ","text":"Zeile 1\nZeile 2"}]', mSnippets));
  Assert.AreEqual(2, Integer(Length(mSnippets)), 'ohne Name oder Text fällt ein Eintrag weg');
  Assert.AreEqual('A', mSnippets[0].Name);
  Assert.AreEqual('C', mSnippets[1].Name, 'Name ohne Leerraum');
  Assert.AreEqual('Zeile 1'#10'Zeile 2', mSnippets[1].Text);
  Assert.IsTrue(TAtlasCommentSnippets.Parse(TAtlasCommentSnippets.ToJson(mSnippets), mSnippets));
  Assert.AreEqual(2, Integer(Length(mSnippets)), 'hin und zurück');
  Assert.AreEqual('Zeile 1'#10'Zeile 2', mSnippets[1].Text);
  Assert.AreEqual(0, Integer(Length(TAtlasCommentSnippets.Read('[]'))), 'leere Liste bleibt leer');
  Assert.AreEqual(Integer(Length(TAtlasCommentSnippets.Defaults)),
    Integer(Length(TAtlasCommentSnippets.Read('kein JSON'))), 'ungültig: Vorgaben');
  Assert.IsFalse(TAtlasCommentSnippets.Parse('{"name":"A"}', mSnippets), 'keine Liste');
  mSnippets := nil;
end;

procedure TAtlasCommentEditorTests.SnippetDefaultsMatchSetting;
var
  mSetting, mDefaults: TArray<TAtlasCommentSnippet>;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasCommentSnippets.Parse(TAtlasPluginSettings.DefaultIssuesCommentSnippets, mSetting));
  mDefaults := TAtlasCommentSnippets.Defaults;
  Assert.AreEqual(Integer(Length(mDefaults)), Integer(Length(mSetting)));
  for mIndex := 0 to High(mDefaults) do
  begin
    Assert.AreEqual(mDefaults[mIndex].Name, mSetting[mIndex].Name);
    Assert.AreEqual(mDefaults[mIndex].Text, mSetting[mIndex].Text);
  end;
  Assert.AreEqual('Behoben in {commit}', mDefaults[1].Name);
  mSetting := nil;
  mDefaults := nil;
end;

procedure TAtlasCommentEditorTests.DraftsPutGetDelete;
var
  mDrafts: TAtlasCommentDrafts;
  mText: string;
  mSaved: TDateTime;
  mIndex: Integer;
begin
  mDrafts := TAtlasCommentDrafts.Create;
  try
    mDrafts.Put('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldPreview, 'Entwurf eins', 1);
    mDrafts.Put('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldEnd, 'Beim Beenden', 2);
    mDrafts.Put('github.com/beispiel/atlas', 'ATL-1', TAtlasCommentDrafts.FieldPreview, 'anderer Tracker', 3);
    Assert.AreEqual(3, mDrafts.Count);
    Assert.IsTrue(mDrafts.Get('YT.firma.de/ATL', 'atl-1', TAtlasCommentDrafts.FieldPreview, mText, mSaved));
    Assert.AreEqual('Entwurf eins', mText, 'ohne Groß-/Kleinschreibung');
    Assert.IsTrue(mDrafts.Get('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldEnd, mText, mSaved));
    Assert.AreEqual('Beim Beenden', mText, 'je Feld');
    mDrafts.Put('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldPreview, 'Entwurf zwei', 4);
    Assert.AreEqual(3, mDrafts.Count, 'ersetzt, nicht doppelt');
    Assert.IsTrue(mDrafts.Get('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldPreview, mText, mSaved));
    Assert.AreEqual('Entwurf zwei', mText);
    mDrafts.Put('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldPreview, '  '#13#10, 5);
    Assert.IsFalse(mDrafts.Get('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldPreview, mText, mSaved),
      'nur Leerraum löscht');
    Assert.IsTrue(mDrafts.Delete('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldEnd));
    Assert.IsFalse(mDrafts.Delete('yt.firma.de/atl', 'ATL-1', TAtlasCommentDrafts.FieldEnd), 'schon weg');
    Assert.AreEqual(1, mDrafts.Count);
    mDrafts.Clear;
    for mIndex := 1 to TAtlasCommentDrafts.MaxDrafts + 5 do
      mDrafts.Put('t', 'ATL-' + IntToStr(mIndex), TAtlasCommentDrafts.FieldPreview, 'x', mIndex);
    Assert.AreEqual(TAtlasCommentDrafts.MaxDrafts, mDrafts.Count, 'höchstens MaxDrafts');
    Assert.IsFalse(mDrafts.Get('t', 'ATL-1', TAtlasCommentDrafts.FieldPreview, mText, mSaved), 'älteste weg');
    Assert.IsTrue(mDrafts.Get('t', 'ATL-105', TAtlasCommentDrafts.FieldPreview, mText, mSaved), 'neueste bleibt');
  finally
    mDrafts.Free;
  end;
end;

procedure TAtlasCommentEditorTests.DraftsRoundTrip;
var
  mDrafts, mRead: TAtlasCommentDrafts;
  mText, mFile: string;
  mSaved, mWhen: TDateTime;
begin
  mWhen := EncodeDateTime(2026, 10, 28, 14, 30, 0, 0);
  mDrafts := TAtlasCommentDrafts.Create;
  mRead := TAtlasCommentDrafts.Create;
  mFile := TPath.Combine(TPath.GetTempPath, 'atlas-drafts-' + TGUID.NewGuid.ToString + '.json');
  try
    mDrafts.Put('yt.firma.de/atl', 'ATL-12', TAtlasCommentDrafts.FieldPreview, 'Zeile 1'#10'**fett** "zitiert"',
      mWhen);
    Assert.IsTrue(mRead.Parse(mDrafts.ToJson));
    Assert.IsTrue(mRead.Get('yt.firma.de/atl', 'ATL-12', TAtlasCommentDrafts.FieldPreview, mText, mSaved));
    Assert.AreEqual('Zeile 1'#10'**fett** "zitiert"', mText);
    Assert.IsTrue(SameDateTime(mWhen, mSaved), 'Zeit unverändert (UTC)');
    Assert.IsFalse(mRead.Parse('{"version":99,"drafts":[]}'), 'fremde Version');
    Assert.AreEqual(0, mRead.Count);
    Assert.IsFalse(mRead.Parse('kein JSON'));
    Assert.IsTrue(mDrafts.SaveToFile(mFile));
    Assert.IsTrue(mRead.LoadFromFile(mFile) = TAtlasDataLoad.Loaded);
    Assert.AreEqual(1, mRead.Count);
    Assert.IsTrue(mRead.LoadFromFile(mFile + '.fehlt') = TAtlasDataLoad.Missing);
    Assert.AreEqual(0, mRead.Count);
  finally
    if TFile.Exists(mFile) then
      TFile.Delete(mFile);
    mRead.Free;
    mDrafts.Free;
  end;
end;

procedure TAtlasCommentEditorTests.UsersRankAndFilter;
var
  mUsers: TArray<TAtlasTrackerUser>;
begin
  mUsers := TArray<TAtlasTrackerUser>.Create(User('bert', 'Bert Anders'), User('anna', 'Anna Berger'),
    User('zoe', 'Zoe Meyer'), User('hans', 'Johannes Klein'), User('', 'Ohne Login'), User('ANNA', 'doppelt'),
    User('andreas', 'Andreas Koch'));
  Assert.AreEqual(0, User('anna', '').Rank('an'));
  Assert.AreEqual(1, User('bert', 'Bert Anders').Rank('an'));
  Assert.AreEqual(2, User('hans', 'Johannes Klein').Rank('an'));
  Assert.AreEqual(3, User('zoe', 'Zoe Meyer').Rank('an'));
  Assert.AreEqual('anna,andreas,bert,hans', Logins(TAtlasTrackerUser.Filter(mUsers, 'an', 8)),
    'Rang, sonst Reihenfolge; ohne leere und doppelte Logins');
  Assert.AreEqual('anna,andreas', Logins(TAtlasTrackerUser.Filter(mUsers, 'AN', 2)), 'höchstens AMax');
  Assert.AreEqual('anna,andreas,bert,hans,zoe', Logins(TAtlasTrackerUser.Ranked(mUsers, 'an', 8)),
    'Ranked behält die übrigen dahinter');
  Assert.AreEqual('bert,anna,zoe,hans,andreas', Logins(TAtlasTrackerUser.Filter(mUsers, '', 8)),
    'leerer Text: alle in Reihenfolge');
  mUsers := nil;
end;

procedure TAtlasCommentEditorTests.YouTrackUsers;
var
  mUsers: TArray<TAtlasTrackerUser>;
  mUrl: string;
  mTransport: TUsersTransport;
  mTransportRef: IAtlasCiTransport;
  mPeople: IAtlasTrackerPeople;
  mError: TAtlasCiFetchError;
begin
  mUrl := TAtlasYouTrackTracker.UsersUrl(YouTrackTarget, 'an na', 8);
  Assert.AreEqual('https://yt.firma.de/api/users?query=an%20na&fields=login%2CfullName%2Cbanned&$top=16', mUrl);
  Assert.AreEqual('', TAtlasYouTrackTracker.UsersUrl(TAtlasTrackerTarget.Create('youtrack', '', 'ATL', ''), 'a', 8),
    'ohne Server');
  Assert.IsTrue(TAtlasYouTrackTracker.ParseUserList('[{"login":"anna","fullName":"Anna Berger"},' +
    '{"login":"alt","fullName":"Alter Account","banned":true},{"fullName":"ohne Login"},' +
    '{"login":"mail","fullName":"Max Mail"}]', mUsers));
  Assert.AreEqual('anna,mail', Logins(mUsers), 'gesperrte und ohne Login fallen weg');
  Assert.AreEqual('Anna Berger', mUsers[0].Name);
  Assert.IsFalse(TAtlasYouTrackTracker.ParseUserList('{"login":"anna"}', mUsers), 'keine Liste');
  mTransport := TUsersTransport.Create(200, '[{"login":"mail","fullName":"Max Mail"},' +
    '{"login":"anna","fullName":"Anna Berger"}]');
  mTransportRef := mTransport;
  Assert.IsTrue(Supports(TAtlasYouTrackTracker.Create as IAtlasTrackerProvider, IAtlasTrackerPeople, mPeople));
  Assert.IsTrue(mPeople.Users(YouTrackTarget, mTransportRef, 'an', 1000, 8, mUsers, mError));
  // YouTrack findet "mail" etwa über die E-Mail-Adresse: bleibt, aber hinter dem Treffer im Namen.
  Assert.AreEqual('anna,mail', Logins(mUsers));
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
  mUsers := nil;
end;

procedure TAtlasCommentEditorTests.GitHubUsers;
var
  mUsers: TArray<TAtlasTrackerUser>;
  mTransport: TUsersTransport;
  mTransportRef: IAtlasCiTransport;
  mPeople: IAtlasTrackerPeople;
  mError: TAtlasCiFetchError;
begin
  Assert.IsTrue(TAtlasGitHubTracker.AssigneesUrl(GitHubTarget).StartsWith('https://api.github.com/repos/'));
  Assert.IsTrue(TAtlasGitHubTracker.AssigneesUrl(GitHubTarget).EndsWith('/assignees?per_page=100'));
  Assert.IsTrue(TAtlasGitHubTracker.ParseUsers('[{"login":"octocat"},{"login":"anna-b"},{"id":3}]', mUsers));
  Assert.AreEqual('octocat,anna-b', Logins(mUsers));
  Assert.AreEqual('', mUsers[0].Name, 'GitHub liefert hier keinen Namen');
  mTransport := TUsersTransport.Create(200, '[{"login":"octocat"},{"login":"anna-b"},{"login":"banana"}]');
  mTransportRef := mTransport;
  Assert.IsTrue(Supports(TAtlasGitHubTracker.Create as IAtlasTrackerProvider, IAtlasTrackerPeople, mPeople));
  Assert.IsTrue(mPeople.Users(GitHubTarget, mTransportRef, 'an', 1000, 8, mUsers, mError));
  Assert.AreEqual('anna-b,banana', Logins(mUsers), 'nur passende, Anfang zuerst');
  Assert.IsTrue(mTransport.Calls[0].EndsWith('/assignees?per_page=100'));
  mUsers := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommentEditorTests);

end.
