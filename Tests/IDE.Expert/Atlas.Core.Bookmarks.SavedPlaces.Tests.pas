unit Atlas.Core.Bookmarks.SavedPlaces.Tests;

// Tests der gemerkten Stellen für andere Module ohne VCL (#1456, vorher Teil
// des Reiters „Gemerkt“, #755): Notizen (#545) mit Titel, verwaist und den
// Zeilen als Detail, Lesezeichen (#622) mit Methode; zwei Projekte im selben
// Ordner liefern dasselbe Lesezeichen einmal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasBookmarksSavedPlacesTests = class
  public
    [Test]
    procedure NotesWithTitleLostAndDetail;
    [Test]
    procedure BookmarksWithMethodAndProject;
    [Test]
    procedure BookmarksOfSameFolderCountOnce;
  end;

implementation

uses
  Atlas.Core.Notes.Store,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Bookmarks.SavedPlaces,
  Atlas.Core.SavedPlaces.Contract;

function Note(const AId, AFileName, AText: string; ALine: Integer): TAtlasNote;
begin
  Result := Default(TAtlasNote);
  Result.Id := AId;
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Anchor.Line := ALine;
end;

function Mark(const AId, AName, AFileName, AMethod: string; ALine: Integer): TAtlasBookmark;
begin
  Result := Default(TAtlasBookmark);
  Result.Id := AId;
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Method := AMethod;
  Result.Anchor.Line := ALine;
end;

{ TAtlasBookmarksSavedPlacesTests }

procedure TAtlasBookmarksSavedPlacesTests.NotesWithTitleLostAndDetail;
var
  mBook, mOther: TAtlasNoteBook;
  mPlaces: TAtlasSavedPlaces;
begin
  mBook := TAtlasNoteBook.Create('C:\Atlas\Atlas.dproj');
  mBook.Notes := TArray<TAtlasNote>.Create(Note('n1', 'C:\Atlas\Kunde.pas', 'Prüfen, ob leer'#10'mit Eva klären',
    41));
  mBook.Notes[0].Orphaned := True;
  mOther := TAtlasNoteBook.Create('C:\Zeta\Zeta.dproj');
  mOther.Notes := TArray<TAtlasNote>.Create(Note('n2', 'C:\Zeta\Haupt.pas', 'Aufräumen', 4));
  mPlaces := TAtlasBookmarksSavedPlaces.FromNotes(TArray<TAtlasNoteBook>.Create(mBook, mOther));
  Assert.AreEqual(2, Integer(Length(mPlaces)));
  Assert.IsTrue(mPlaces[0].Kind = TAtlasSavedPlaceKind.Note);
  Assert.AreEqual('n1', mPlaces[0].Id);
  Assert.AreEqual('Prüfen, ob leer …', mPlaces[0].Text, 'Titel der Notiz');
  Assert.AreEqual('C:\Atlas\Kunde.pas', mPlaces[0].FileName);
  Assert.AreEqual(41, mPlaces[0].Line, '0-basiert');
  Assert.AreEqual('C:\Atlas\Atlas.dproj', mPlaces[0].Project);
  Assert.IsTrue(mPlaces[0].Lost, 'verwaist');
  Assert.AreEqual('Prüfen, ob leer mit Eva klären', mPlaces[0].Detail, 'alle Zeilen in einer');
  Assert.AreEqual('', mPlaces[1].Detail, 'eine Zeile: kein Detail');
  Assert.IsFalse(mPlaces[1].Lost);
  Assert.AreEqual(0, Integer(Length(TAtlasBookmarksSavedPlaces.FromNotes(nil))));
  mPlaces := nil;
end;

procedure TAtlasBookmarksSavedPlacesTests.BookmarksWithMethodAndProject;
var
  mList: TAtlasBookmarkList;
  mPlaces: TAtlasSavedPlaces;
begin
  mList := TAtlasBookmarkList.Create('C:\Atlas\Atlas.dproj');
  mList.Bookmarks := TArray<TAtlasBookmark>.Create(Mark('b2', 'Speichern', 'C:\Atlas\Kunde.pas',
    'TKunde.Speichern', 80), Mark('b1', 'Einstieg', 'C:\Atlas\Atlas.dpr', '', 9));
  mList.Bookmarks[1].Lost := True;
  mPlaces := TAtlasBookmarksSavedPlaces.FromBookmarks(TArray<TAtlasBookmarkList>.Create(mList));
  Assert.AreEqual(2, Integer(Length(mPlaces)));
  Assert.IsTrue(mPlaces[0].Kind = TAtlasSavedPlaceKind.Bookmark);
  Assert.AreEqual('b2', mPlaces[0].Id);
  Assert.AreEqual('Speichern', mPlaces[0].Text);
  Assert.AreEqual('TKunde.Speichern', mPlaces[0].Detail);
  Assert.AreEqual(80, mPlaces[0].Line);
  Assert.AreEqual('C:\Atlas\Atlas.dproj', mPlaces[0].Project);
  Assert.IsFalse(mPlaces[0].Lost);
  Assert.IsTrue(mPlaces[1].Lost, 'nicht gefunden');
  mPlaces := nil;
end;

procedure TAtlasBookmarksSavedPlacesTests.BookmarksOfSameFolderCountOnce;
var
  mFirst, mSecond: TAtlasBookmarkList;
  mPlaces: TAtlasSavedPlaces;
begin
  // Zwei Projekte im selben Ordner lesen dieselbe Lesezeichen-Datei.
  mFirst := TAtlasBookmarkList.Create('C:\Atlas\Atlas.dproj');
  mFirst.Bookmarks := TArray<TAtlasBookmark>.Create(Mark('b1', 'Einstieg', 'C:\Atlas\Atlas.dpr', '', 9));
  mSecond := TAtlasBookmarkList.Create('C:\Atlas\Werkzeug.dproj');
  mSecond.Bookmarks := TArray<TAtlasBookmark>.Create(Mark('b1', 'Einstieg', 'c:\atlas\ATLAS.dpr', '', 9),
    Mark('b2', 'Werkzeug', 'C:\Atlas\Werkzeug.dpr', '', 1));
  mPlaces := TAtlasBookmarksSavedPlaces.FromBookmarks(TArray<TAtlasBookmarkList>.Create(mFirst, mSecond));
  Assert.AreEqual(2, Integer(Length(mPlaces)));
  Assert.AreEqual('C:\Atlas\Atlas.dproj', mPlaces[0].Project);
  Assert.AreEqual('b2', mPlaces[1].Id);
  mPlaces := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBookmarksSavedPlacesTests);

end.
