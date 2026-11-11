unit Atlas.IDE.Editor.HideTeamFile;

// Einträge "hidden" der Teamdatei .atlas für „Ausblenden“ (#628), aus
// Atlas.IDE.Editor.Hide gelöst: Ort der Datei, Eintrag hinzufügen und
// zurücknehmen. Eine neue Datei entsteht wie bei „Projektdatei öffnen“
// (UTF-8 ohne BOM, mit Gerüst).
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Settings.HiddenPlaces;

type
  TAtlasIdeHideTeamFile = class
  public
    /// <summary>Ordner der .atlas des aktiven Projekts (vorhandene Datei, sonst neben der .dproj); AFileName ist
    /// der Pfad der Datei. Ohne Projekt beide leer.</summary>
    class function Folder(out AFileName: string): string; static;
    /// <summary>Trägt APlace ein; AFileName ist die geschriebene Datei. False mit Begründung in ADetail, wenn die
    /// Teamdatei aus ist, kein Projekt offen ist, APlace schon drinsteht oder das Schreiben scheitert.</summary>
    class function Add(const APlace: TAtlasHiddenPlace; out AFileName, ADetail: string): Boolean; static;
    /// <summary>Nimmt APlace aus AFileName wieder heraus; False, wenn die Datei fehlt.</summary>
    class function Remove(const AFileName: string; const APlace: TAtlasHiddenPlace): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Files.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.TeamFile,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.Files;

/// <summary>Inhalt von AFileName oder eine leere Datei in UTF-8 ohne BOM.</summary>
function LoadOrNew(const AFileName: string): TAtlasTextFileContent;
begin
  if FileExists(AFileName) then
  begin
    Result := TAtlasTextFile.Load(AFileName);
  end
  else
  begin
    Result := Default(TAtlasTextFileContent);
    Result.Encoding := TAtlasTextEncoding.Utf8;
  end;
end;

/// <summary>Schreibt APlace in AFileName; False mit Begründung in ADetail, wenn es schon drinsteht oder das
/// Schreiben scheitert.</summary>
function WritePlace(const AFileName: string; const APlace: TAtlasHiddenPlace; out ADetail: string): Boolean;
var
  mContent: TAtlasTextFileContent;
  mUpdated: string;
begin
  Result := False;
  ADetail := '';
  try
    mContent := LoadOrNew(AFileName);
    mUpdated := TAtlasHiddenPlaces.AddTo(mContent.Text, TAtlasTeamFile.Skeleton, APlace);
    if mUpdated = mContent.Text then
    begin
      ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedAlready);
      Exit;
    end;
    mContent.Text := mUpdated;
    TAtlasTextFile.Save(AFileName, mContent);
    Result := True;
  except
    on E: Exception do
    begin
      ADetail := TAtlasStrings.Fmt(TAtlasTextId.HideFailed, [E.Message]);
    end;
  end;
end;

{ TAtlasIdeHideTeamFile }

class function TAtlasIdeHideTeamFile.Folder(out AFileName: string): string;
var
  mTeam: TAtlasTeamSettings;
  mProject: string;
begin
  // Vorhandene .atlas des aktiven Projekts, sonst neben der .dproj (wie „Projektdatei öffnen“).
  mTeam := TAtlasIdeTeamFile.Current;
  if mTeam.FileName <> '' then
  begin
    AFileName := mTeam.FileName;
    Exit(mTeam.Folder);
  end;
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    AFileName := '';
    Exit('');
  end;
  Result := ExtractFileDir(mProject);
  AFileName := TPath.Combine(Result, TAtlasTeamFile.cFileName);
end;

class function TAtlasIdeHideTeamFile.Add(const APlace: TAtlasHiddenPlace; out AFileName, ADetail: string): Boolean;
begin
  Result := False;
  AFileName := '';
  if not (TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.TeamFile) then
  begin
    ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedTeamFileOff);
    Exit;
  end;
  Folder(AFileName);
  if AFileName = '' then
  begin
    ADetail := TAtlasStrings.Text(TAtlasTextId.HideRefusedNoProject);
    Exit;
  end;
  Result := WritePlace(AFileName, APlace, ADetail);
  if Result then
  begin
    TAtlasIdeTeamFile.Refresh;
  end;
end;

class function TAtlasIdeHideTeamFile.Remove(const AFileName: string; const APlace: TAtlasHiddenPlace): Boolean;
var
  mContent: TAtlasTextFileContent;
  mUpdated: string;
begin
  Result := FileExists(AFileName);
  if not Result then
  begin
    Exit;
  end;
  mContent := TAtlasTextFile.Load(AFileName);
  mUpdated := TAtlasHiddenPlaces.RemoveFrom(mContent.Text, APlace);
  if mUpdated <> mContent.Text then
  begin
    mContent.Text := mUpdated;
    TAtlasTextFile.Save(AFileName, mContent);
  end;
  TAtlasIdeTeamFile.Refresh;
end;

end.
