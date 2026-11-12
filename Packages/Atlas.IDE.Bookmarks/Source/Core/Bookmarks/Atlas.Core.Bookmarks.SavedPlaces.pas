unit Atlas.Core.Bookmarks.SavedPlaces;

// Gemerkte Stellen für andere Module (#1456, Vertrag
// Atlas.Core.SavedPlaces.Contract), Teil ohne VCL und Open Tools API:
// persönliche Notizen (#545) und benannte Lesezeichen (#622) als Einträge mit
// Art, Text, Datei, Zeile und Projekt. Vorher rechnete die Willkommensseite
// das selbst aus den Ablagen dieses Moduls (#755).
// - Notiz: Titel als Text, alle Zeilen in einer als Detail, wenn sie mehrere
//   hat; verwaist gilt als Lost.
// - Lesezeichen: Methode als Detail. Zwei Projekte im selben Ordner lesen
//   dieselbe Lesezeichen-Datei; dasselbe Lesezeichen zählt einmal (beim
//   ersten Projekt).

interface

uses
  Atlas.Core.Notes.Store,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.SavedPlaces.Contract;

type
  TAtlasBookmarksSavedPlaces = class
  public
    /// <summary>Alle Notizen der Notizbücher ABooks in ihrer Reihenfolge.</summary>
    class function FromNotes(const ABooks: TArray<TAtlasNoteBook>): TAtlasSavedPlaces; static;
    /// <summary>Alle Lesezeichen der Listen ALists; dieselbe Datei (Projekte im selben Ordner) zählt einmal.
    /// </summary>
    class function FromBookmarks(const ALists: TArray<TAtlasBookmarkList>): TAtlasSavedPlaces; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Marks.Ids;

function NotePlace(const ABook: TAtlasNoteBook; const ANote: TAtlasNote): TAtlasSavedPlace;
var
  mLines: TArray<string>;
begin
  Result := Default(TAtlasSavedPlace);
  Result.Kind := TAtlasSavedPlaceKind.Note;
  Result.Id := ANote.Id;
  Result.Text := ANote.Title;
  Result.FileName := ANote.FileName;
  Result.Line := ANote.Line;
  Result.Project := ABook.Project;
  Result.Lost := ANote.Orphaned;
  mLines := ANote.Text.Split([#10]);
  if Length(mLines) > 1 then
  begin
    Result.Detail := Trim(string.Join(' ', mLines));
  end;
end;

function MarkPlace(const AList: TAtlasBookmarkList; const AMark: TAtlasBookmark): TAtlasSavedPlace;
begin
  Result := Default(TAtlasSavedPlace);
  Result.Kind := TAtlasSavedPlaceKind.Bookmark;
  Result.Id := AMark.Id;
  Result.Text := AMark.Name;
  Result.FileName := AMark.FileName;
  Result.Line := AMark.Line;
  Result.Project := AList.Project;
  Result.Detail := AMark.Method;
  Result.Lost := AMark.Lost;
end;

/// <summary>Steht dasselbe Lesezeichen (Kennung und Datei) schon in APlaces?</summary>
function Known(const APlaces: TAtlasSavedPlaces; const AMark: TAtlasBookmark): Boolean;
var
  mPlace: TAtlasSavedPlace;
begin
  Result := False;
  for mPlace in APlaces do
  begin
    if SameText(mPlace.Id, AMark.Id) and TAtlasMarkIds.SameFile(mPlace.FileName, AMark.FileName) then
    begin
      Result := True;
    end;
  end;
end;

class function TAtlasBookmarksSavedPlaces.FromNotes(const ABooks: TArray<TAtlasNoteBook>): TAtlasSavedPlaces;
var
  mBook: TAtlasNoteBook;
  mNote: TAtlasNote;
begin
  Result := nil;
  for mBook in ABooks do
  begin
    for mNote in mBook.Notes do
    begin
      Result := Result + [NotePlace(mBook, mNote)];
    end;
  end;
end;

class function TAtlasBookmarksSavedPlaces.FromBookmarks(const ALists: TArray<TAtlasBookmarkList>): TAtlasSavedPlaces;
var
  mList: TAtlasBookmarkList;
  mMark: TAtlasBookmark;
begin
  Result := nil;
  for mList in ALists do
  begin
    for mMark in mList.Bookmarks do
    begin
      if not Known(Result, mMark) then
      begin
        Result := Result + [MarkPlace(mList, mMark)];
      end;
    end;
  end;
end;

end.
