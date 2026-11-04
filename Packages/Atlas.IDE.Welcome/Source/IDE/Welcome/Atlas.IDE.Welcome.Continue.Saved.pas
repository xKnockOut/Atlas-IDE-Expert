unit Atlas.IDE.Welcome.Continue.Saved;

// Teil „Gemerkt“ (welcomePage.saved) des Bereichs „Weiterarbeiten“ (#755) in
// der IDE: Notizen (#545) und Lesezeichen (#622) der zuletzt geöffneten
// Projekte (bei Projektgruppen auch ihrer Projekte) und angeheftete Favoriten
// (#458); für einen Favoriten die Datei der Unit aus den Index-Caches auf der
// Platte und die Zeile der Deklaration. Abgeteilt aus
// Atlas.IDE.Welcome.Continue (Atlas-Befunde).

interface

uses
  Atlas.Core.Welcome.Saved;

type
  TAtlasIdeContinueSaved = class
  public
    /// <summary>Alle gemerkten Stellen.</summary>
    class function Items: TAtlasSavedItems; static;
    /// <summary>Datei und Zeile (ab 0) der Deklaration des Favoriten AItem; False, wenn die Unit in keinem
    /// Index-Cache steht.</summary>
    class function FindFavorite(const AItem: TAtlasSavedItem; out AFileName: string; out ALine: Integer): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Welcome.IndexFiles,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Welcome.Neighbors,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Continue.Editor;

/// <summary>Projekte der Projektgruppe AGroup; leer, wenn sie nicht lesbar ist.</summary>
function MembersOf(const AGroup: string): TArray<string>;
begin
  Result := nil;
  try
    Result := TAtlasWelcomeSaved.GroupProjects(AGroup, TAtlasTextFile.LoadText(AGroup));
  except
    // Gruppe nicht lesbar: nur ihr eigener Ordner.
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
end;

/// <summary>Zuletzt geöffnete Projekte, bei Projektgruppen dahinter auch deren Projekte (für die Lesezeichen,
/// #622).</summary>
function RecentWithMembers: TArray<string>;
var
  mRecent: TArray<string>;
  mProject: string;
begin
  Result := nil;
  mRecent := nil;
  try
    mRecent := TAtlasIdeWelcomeSearch.RecentProjects;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
  for mProject in mRecent do
  begin
    Result := Result + [mProject];
    if SameText(ExtractFileExt(mProject), '.groupproj') and FileExists(mProject) then
    begin
      Result := Result + MembersOf(mProject);
    end;
  end;
end;

/// <summary>Angeheftete Favoriten (#458) aus einer eigenen Instanz, damit die der Vervollständigung unberührt
/// bleibt.</summary>
function LoadFavorites: TArray<TAtlasFavorite>;
var
  mFavorites: TAtlasFavorites;
begin
  Result := nil;
  mFavorites := TAtlasFavorites.Create;
  try
    try
      if FileExists(TAtlasIdeFavorites.FileName) then
      begin
        mFavorites.LoadFromFile(TAtlasIdeFavorites.FileName);
      end;
      Result := mFavorites.Items;
    except
      on E: Exception do
      begin
        TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
      end;
    end;
  finally
    mFavorites.Free;
  end;
end;

/// <summary>Datei der Unit AUnitName aus den Index-Caches: erst die Projekte, dann die Bibliothek; '' ohne.
/// </summary>
function UnitFile(const AUnitName: string): string;
var
  mRoot, mCache: string;
  mCursor: TCursor;
begin
  Result := '';
  mRoot := TAtlasIdeWelcomeSearch.CacheRoot;
  mCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    for mCache in TAtlasWelcomeIndexFiles.CacheFiles(mRoot) + TAtlasWelcomeIndexFiles.LibraryCacheFiles(mRoot) do
    begin
      Result := TAtlasWelcomeSaved.FindUnit(TAtlasWelcomeIndexFiles.LoadUnits(mCache), AUnitName);
      if (Result <> '') and FileExists(Result) then
      begin
        Break;
      end;
      Result := '';
    end;
  finally
    Screen.Cursor := mCursor;
  end;
end;

{ TAtlasIdeContinueSaved }

class function TAtlasIdeContinueSaved.Items: TAtlasSavedItems;
begin
  // Notizen (#545) und Lesezeichen (#622) vom Modul Lesezeichen (#1456), Favoriten von Base.
  Result := TAtlasWelcomeSaved.Collect(TAtlasWelcomeNeighbors.SavedPlaces(RecentWithMembers), LoadFavorites);
end;

class function TAtlasIdeContinueSaved.FindFavorite(const AItem: TAtlasSavedItem; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  ALine := 0;
  AFileName := UnitFile(AItem.UnitName);
  Result := AFileName <> '';
  if Result then
  begin
    ALine := TAtlasWelcomeSaved.DeclarationLine(TAtlasIdeContinueEditor.FileText(AFileName), AItem.TypeName,
      AItem.Member);
    if ALine < 0 then
    begin
      ALine := 0;
    end;
  end;
end;

end.
