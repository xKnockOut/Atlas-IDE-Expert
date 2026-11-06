unit Atlas.IDE.Debug.Sources;

// Quelltexte der Rahmen eines Aufrufstapels (#517, #578):
//   - Resolve: Die IDE nennt im Stapel oft nur den Dateinamen. Atlas nimmt
//     einen vorhandenen absoluten Pfad, sonst die gleichnamige Datei aus den
//     Dateien der Projektgruppe; Ergebnisse je Sitzung zwischengespeichert.
//   - OwnCode: Ordner der Projekte der Gruppe und debug.ownCodeFolders.
//   - MarkFrames: Pfad auflösen und Own setzen.
// Clear zu Beginn einer Debug-Sitzung und nach geänderten Einstellungen.
// Nur im Hauptthread verwenden.

interface

uses
  System.Classes,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.OwnCode;

type
  TAtlasIdeDebugSources = class
  private class var
    FCache: TStringList;
    FOwnCode: TAtlasDebugOwnCode;
    FOwnCodeReady: Boolean;
  public
    /// <summary>Vollständiger Pfad zu AFileName; '' wenn die Datei weder vorhanden noch in der Projektgruppe ist.
    /// </summary>
    class function Resolve(const AFileName: string): string; static;
    /// <summary>Ordner des eigenen Codes (#578).</summary>
    class function OwnCode: TAtlasDebugOwnCode; static;
    /// <summary>Dateien der Rahmen auflösen (sofern gefunden) und eigenen Code markieren.</summary>
    class procedure MarkFrames(var AFrames: TAtlasDebugFrames); static;
    class procedure Clear; static;
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  ToolsAPI,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeDebugSources }

class procedure TAtlasIdeDebugSources.Clear;
begin
  if FCache <> nil then
  begin
    FCache.Clear;
  end;
  FOwnCodeReady := False;
  FOwnCode.Folders := nil;
end;

class procedure TAtlasIdeDebugSources.Release;
begin
  FreeAndNil(FCache);
  FOwnCodeReady := False;
  FOwnCode.Folders := nil;
end;

/// <summary>Vorhandene Datei namens AName unter den Dateien von AProject; '' ohne.</summary>
function FindInProject(const AProject: IOTAProject; const AName: string): string;
var
  mFiles: TStringList;
  mIndex: Integer;
begin
  Result := '';
  mFiles := TStringList.Create;
  try
    AProject.GetCompleteFileList(mFiles);
    for mIndex := 0 to mFiles.Count - 1 do
    begin
      if SameText(ExtractFileName(mFiles[mIndex]), AName) and FileExists(mFiles[mIndex]) then
      begin
        Exit(mFiles[mIndex]);
      end;
    end;
  finally
    mFiles.Free;
  end;
end;

/// <summary>Vorhandene Datei namens AName in einem Projekt der Projektgruppe; '' ohne.</summary>
function FindInGroup(const AName: string): string;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mGroup := mModules.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  mIndex := 0;
  while (Result = '') and (mIndex < mGroup.ProjectCount) do
  begin
    Result := FindInProject(mGroup.Projects[mIndex], AName);
    Inc(mIndex);
  end;
end;

class function TAtlasIdeDebugSources.Resolve(const AFileName: string): string;
begin
  Result := '';
  if AFileName = '' then
  begin
    Exit;
  end;
  if TPath.IsPathRooted(AFileName) and FileExists(AFileName) then
  begin
    Exit(AFileName);
  end;
  if FCache = nil then
  begin
    FCache := TStringList.Create;
    FCache.CaseSensitive := False;
  end;
  if FCache.IndexOfName(AFileName) >= 0 then
  begin
    Exit(FCache.Values[AFileName]);
  end;
  Result := FindInGroup(ExtractFileName(AFileName));
  FCache.Values[AFileName] := Result;
end;

class function TAtlasIdeDebugSources.OwnCode: TAtlasDebugOwnCode;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  if not FOwnCodeReady then
  begin
    FOwnCode := TAtlasDebugOwnCode.Create(
      TAtlasDebugOwnCode.ParseFolders(TAtlasIdeSettings.Current.DebugOwnCodeFolders));
    if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    begin
      Group := Modules.MainProjectGroup;
      if Group <> nil then
      begin
        for Index := 0 to Group.ProjectCount - 1 do
        begin
          FOwnCode.AddFolder(ExtractFileDir(Group.Projects[Index].FileName));
        end;
      end;
    end;
    FOwnCodeReady := True;
  end;
  Result := FOwnCode;
end;

class procedure TAtlasIdeDebugSources.MarkFrames(var AFrames: TAtlasDebugFrames);
var
  Index: Integer;
  Path: string;
  Own: TAtlasDebugOwnCode;
begin
  Own := OwnCode;
  for Index := 0 to High(AFrames) do
  begin
    Path := Resolve(AFrames[Index].FileName);
    if Path <> '' then
    begin
      AFrames[Index].FileName := Path;
    end;
    AFrames[Index].Own := Own.IsOwnFile(Path);
  end;
end;

end.
