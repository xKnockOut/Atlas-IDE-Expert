unit Atlas.UI.Tracker.Notify.Tests;

// Texte der Meldungen zu meinen Issues (#1271): Kennung und was neu ist,
// Zustände von GitHub übersetzt, Sammelmeldung und Fehler mit dem Server.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerNoticeTextTests = class
  public
    /// <summary>Abnahme: „ATL-123: neuer Kommentar von …“, „… dir zugewiesen“, „Zustand → …“.</summary>
    [Test]
    procedure GermanTitles;
    [Test]
    procedure EnglishTitles;
    [Test]
    procedure MoreAndErrors;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Notify,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Notify;

function Notice(const AKey: string): TAtlasTrackerNotice;
begin
  Result := Default(TAtlasTrackerNotice);
  Result.Key := AKey;
  Result.CommentAuthors := nil;
end;

{ TAtlasTrackerNoticeTextTests }

procedure TAtlasTrackerNoticeTextTests.GermanTitles;
var
  mSaved: TAtlasLanguage;
  mNotice: TAtlasTrackerNotice;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mNotice := Notice('ATL-123');
    mNotice.Comments := 1;
    mNotice.CommentAuthors := ['Anna Muster'];
    Assert.AreEqual('ATL-123: neuer Kommentar von Anna Muster', TAtlasTrackerNoticeText.Title(mNotice));
    mNotice.Comments := 3;
    mNotice.CommentAuthors := ['Anna Muster', 'Ben'];
    mNotice.State := 'Fertig';
    Assert.AreEqual('ATL-123: 3 neue Kommentare (Anna Muster, Ben) · Zustand → Fertig',
      TAtlasTrackerNoticeText.Title(mNotice));
    mNotice := Notice('ATL-123');
    mNotice.AssignedToMe := True;
    Assert.AreEqual('ATL-123 dir zugewiesen', TAtlasTrackerNoticeText.Title(mNotice));
    mNotice.Comments := 1;
    mNotice.CommentAuthors := ['Ben'];
    Assert.AreEqual('ATL-123 dir zugewiesen · neuer Kommentar von Ben', TAtlasTrackerNoticeText.Title(mNotice));
    mNotice := Notice('#12');
    mNotice.AssignedTo := 'anna';
    mNotice.State := 'closed';
    Assert.AreEqual('#12: zugewiesen an anna · Zustand → geschlossen', TAtlasTrackerNoticeText.Title(mNotice));
    mNotice := Notice('#7');
    mNotice.Other := True;
    Assert.AreEqual('#7 geändert', TAtlasTrackerNoticeText.Title(mNotice));
    Assert.AreEqual('offen', TAtlasTrackerNoticeText.StateText('open'));
    Assert.AreEqual('In Arbeit', TAtlasTrackerNoticeText.StateText('In Arbeit'), 'YouTrack wie vom Server');
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerNoticeTextTests.EnglishTitles;
var
  mSaved: TAtlasLanguage;
  mNotice: TAtlasTrackerNotice;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    mNotice := Notice('ATL-123');
    mNotice.Comments := 1;
    mNotice.CommentAuthors := ['Anna'];
    Assert.AreEqual('ATL-123: new comment from Anna', TAtlasTrackerNoticeText.Title(mNotice));
    mNotice := Notice('#12');
    mNotice.AssignedToMe := True;
    mNotice.State := 'open';
    Assert.AreEqual('#12 assigned to you · state → open', TAtlasTrackerNoticeText.Title(mNotice));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerNoticeTextTests.MoreAndErrors;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('4 weitere Issues geändert', TAtlasTrackerNoticeText.MoreTitle(4));
    Assert.AreEqual('Issue-Meldungen: Token für https://youtrack.firma.local abgelehnt',
      TAtlasTrackerNoticeText.ErrorTitle(TAtlasCiFetchError.Unauthorized, 'https://youtrack.firma.local'));
    Assert.AreEqual('Issue-Meldungen: https://github.com nicht erreichbar',
      TAtlasTrackerNoticeText.ErrorTitle(TAtlasCiFetchError.Timeout, 'https://github.com'));
    Assert.AreEqual('Issue-Meldungen: https://github.com nicht erreichbar',
      TAtlasTrackerNoticeText.ErrorTitle(TAtlasCiFetchError.Network, 'https://github.com'));
    Assert.AreEqual('Issue-Meldungen: unerwartete Antwort von https://github.com',
      TAtlasTrackerNoticeText.ErrorTitle(TAtlasCiFetchError.Invalid, 'https://github.com'));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerNoticeTextTests);

end.
