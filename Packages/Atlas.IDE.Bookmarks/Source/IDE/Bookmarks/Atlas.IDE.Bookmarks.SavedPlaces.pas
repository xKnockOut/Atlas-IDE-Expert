unit Atlas.IDE.Bookmarks.SavedPlaces;

// Gemerkte Stellen des Moduls für andere Module (#1456, Vertrag
// IAtlasSavedPlacesSource): liest die Notizbücher im Ordner der Notizen
// (#545) und die Lesezeichen neben den Projekten (#622, Ablage im Projekt
// oder privat nach bookmarks.shared) und springt zu einem Lesezeichen, wenn
// benannte Lesezeichen eingeschaltet sind. Der Reiter „Gemerkt“ der
// Willkommensseite (#755) holt die Einträge hierüber, statt die Ablagen des
// Moduls selbst zu lesen.

interface

uses
  Atlas.Core.SavedPlaces.Contract;

type
  TAtlasIdeSavedPlaces = class(TInterfacedObject, IAtlasSavedPlacesSource)
  public
    function Places(const AProjects: TArray<string>): TAtlasSavedPlaces;
    function OpenBookmark(const AProject, AId: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Notes.Store,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Bookmarks.SavedPlaces,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Bookmarks.Service;

function LoadNotes: TArray<TAtlasNoteBook>;
begin
  Result := nil;
  try
    Result := TAtlasNotes.LoadAll(TAtlasNotes.DefaultFolder);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Notes, E);
    end;
  end;
end;

/// <summary>Liste von AProject in AList, wenn sie Lesezeichen hat; Fehler beim Lesen lassen sie aus.</summary>
function LoadList(const AProject: string; AShared: Boolean; out AList: TAtlasBookmarkList): Boolean;
begin
  Result := False;
  try
    Result := FileExists(AProject) and TAtlasBookmarks.Load(AProject, AShared, AList) and (AList.Count > 0);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Bookmarks, E);
    end;
  end;
end;

function LoadLists(const AProjects: TArray<string>): TArray<TAtlasBookmarkList>;
var
  mSeen: TDictionary<string, Boolean>;
  mProject, mKey: string;
  mShared: Boolean;
  mList: TAtlasBookmarkList;
begin
  Result := nil;
  mShared := TAtlasIdeSettings.Current.BookmarksShared;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mProject in AProjects do
    begin
      mKey := TAtlasProjectSummaries.NormalizedPath(mProject);
      if not SameText(ExtractFileExt(mProject), '.groupproj') and not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        if LoadList(mProject, mShared, mList) then
        begin
          Result := Result + [mList];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function TAtlasIdeSavedPlaces.Places(const AProjects: TArray<string>): TAtlasSavedPlaces;
begin
  Result := TAtlasBookmarksSavedPlaces.FromNotes(LoadNotes) +
    TAtlasBookmarksSavedPlaces.FromBookmarks(LoadLists(AProjects));
end;

function TAtlasIdeSavedPlaces.OpenBookmark(const AProject, AId: string): Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed;
  if Result then
  begin
    TAtlasIdeBookmarks.OpenBookmark(AProject, AId);
  end;
end;

end.
