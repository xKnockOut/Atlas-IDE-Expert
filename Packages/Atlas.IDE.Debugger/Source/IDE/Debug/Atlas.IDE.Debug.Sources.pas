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
    FCache.Clear;
  FOwnCodeReady := False;
  FOwnCode.Folders := nil;
end;

class procedure TAtlasIdeDebugSources.Release;
begin
  FreeAndNil(FCache);
  FOwnCodeReady := False;
  FOwnCode.Folders := nil;
end;

class function TAtlasIdeDebugSources.Resolve(const AFileName: string): string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  ProjectIndex, FileIndex: Integer;
  Name, Candidate: string;
  Files: TStringList;
begin
  Result := '';
  if AFileName = '' then
    Exit;
  if TPath.IsPathRooted(AFileName) and FileExists(AFileName) then
    Exit(AFileName);
  if FCache = nil then
  begin
    FCache := TStringList.Create;
    FCache.CaseSensitive := False;
  end;
  if FCache.IndexOfName(AFileName) >= 0 then
    Exit(FCache.Values[AFileName]);
  Name := ExtractFileName(AFileName);
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Group := Modules.MainProjectGroup;
    Files := TStringList.Create;
    try
      if Group <> nil then
        for ProjectIndex := 0 to Group.ProjectCount - 1 do
        begin
          Files.Clear;
          Group.Projects[ProjectIndex].GetCompleteFileList(Files);
          for FileIndex := 0 to Files.Count - 1 do
          begin
            Candidate := Files[FileIndex];
            if SameText(ExtractFileName(Candidate), Name) and FileExists(Candidate) then
            begin
              Result := Candidate;
              Break;
            end;
          end;
          if Result <> '' then
            Break;
        end;
    finally
      Files.Free;
    end;
  end;
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
        for Index := 0 to Group.ProjectCount - 1 do
          FOwnCode.AddFolder(ExtractFileDir(Group.Projects[Index].FileName));
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
      AFrames[Index].FileName := Path;
    AFrames[Index].Own := Own.IsOwnFile(Path);
  end;
end;

end.
