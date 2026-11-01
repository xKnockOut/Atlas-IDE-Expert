unit Atlas.IDE.Editor.MissingUnit;

// „Unit nicht gefunden“: Suchpfad ergänzen (#550). Der Server bietet die Code-
// Aktionen auf F2613 und F1026 des letzten Compilerlaufs an
// (refactoring.missingUnit); die Projektoptionen ändert das Plugin über die
// Open Tools API, damit die IDE sie gleich kennt (#396):
//   - atlas.addSearchPath: Ordner vorn in DCC_UnitSearchPath der genannten
//     Konfiguration bzw. der Basis; das Projekt gilt danach als geändert.
//   - atlas.addUnitToProject: Datei ins Projekt aufnehmen.
//   - atlas.showInfo: Hinweis im Dialog und in der Meldungsansicht.
// Argumente und neue Liste in Atlas.Core.Editor.MissingUnit. Nur im
// Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasIdeMissingUnit = class
  public const
    SearchPathCommand = 'atlas.addSearchPath';
    AddUnitCommand = 'atlas.addUnitToProject';
    InfoCommand = 'atlas.showInfo';
  public
    /// <summary>atlas.addSearchPath; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure AddSearchPath(const AArgumentsJson: string; const AMessage: TProc<string>); static;
    /// <summary>atlas.addUnitToProject.</summary>
    class procedure AddUnit(const AArgumentsJson: string; const AMessage: TProc<string>); static;
    /// <summary>atlas.showInfo.</summary>
    class procedure ShowInfo(const AArgumentsJson: string; const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Editor.MissingUnit,
  Atlas.IDE.Foundation.Files;

/// <summary>Konfiguration AName des Projekts; '' = Basis. nil, wenn es sie nicht gibt.</summary>
function ConfigurationOf(const AProject: IOTAProject; const AName: string): IOTABuildConfiguration;
var
  Configurations: IOTAProjectOptionsConfigurations;
  Index: Integer;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) then
    Exit;
  if AName = '' then
    Exit(Configurations.BaseConfiguration);
  for Index := 0 to Configurations.ConfigurationCount - 1 do
    if SameText(Configurations.Configurations[Index].Name, AName) then
      Exit(Configurations.Configurations[Index]);
end;

class procedure TAtlasIdeMissingUnit.AddSearchPath(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  Request: TAtlasSearchPathRequest;
  Project: IOTAProject;
  Configuration: IOTABuildConfiguration;
  Label_, Raw: string;
begin
  if not TAtlasSearchPathRequest.TryParse(AArgumentsJson, Request) then
    Exit;
  Project := TAtlasIdeFiles.GroupProject(Request.ProjectFile);
  if Project = nil then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitNoProject, [ExtractFileName(Request.ProjectFile)]));
    Exit;
  end;
  Label_ := Request.Config;
  if Label_ = '' then
    Label_ := TAtlasStrings.Text(TAtlasTextId.MissingUnitAllConfigs);
  Configuration := ConfigurationOf(Project, Request.Config);
  if Configuration = nil then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitConfigNotFound, [Request.Config,
      ExtractFileName(Project.FileName)]));
    Exit;
  end;
  try
    // Mit Geerbtem: Steht der Ordner schon in der Basis, braucht ihn die Konfiguration nicht noch einmal.
    if TAtlasSearchPaths.Contains(Configuration.GetValue(TAtlasSearchPaths.OptionName, True), Request.Folder) then
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitSearchPathPresent, [Request.Folder, Label_,
        ExtractFileName(Project.FileName)]));
      Exit;
    end;
    Raw := Configuration.GetValue(TAtlasSearchPaths.OptionName, False);
    Configuration.SetValue(TAtlasSearchPaths.OptionName,
      TAtlasSearchPaths.WithFolder(Raw, Request.Folder, Request.Config = ''));
    Project.MarkModified;
  except
    on E: Exception do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitSearchPathFailed, [E.Message]));
      Exit;
    end;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitSearchPathDone, [Label_, ExtractFileName(Project.FileName),
    Request.Folder]));
end;

class procedure TAtlasIdeMissingUnit.AddUnit(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  Request: TAtlasAddUnitRequest;
  Project: IOTAProject;
begin
  if not TAtlasAddUnitRequest.TryParse(AArgumentsJson, Request) then
    Exit;
  Project := TAtlasIdeFiles.GroupProject(Request.ProjectFile);
  if Project = nil then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitNoProject, [ExtractFileName(Request.ProjectFile)]));
    Exit;
  end;
  if Project.FindModuleInfo(Request.FileName) <> nil then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitAlreadyInProject, [ExtractFileName(Request.FileName),
      ExtractFileName(Project.FileName)]));
    Exit;
  end;
  try
    Project.AddFile(Request.FileName, True);
  except
    on E: Exception do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitAddFailed, [ExtractFileName(Request.FileName),
        E.Message]));
      Exit;
    end;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.MissingUnitAdded, [ExtractFileName(Request.FileName),
    ExtractFileName(Project.FileName)]));
end;

class procedure TAtlasIdeMissingUnit.ShowInfo(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  Text: string;
begin
  if not TAtlasSearchPaths.TryParseInfo(AArgumentsJson, Text) then
    Exit;
  AMessage(Text);
  // Die Liste der durchsuchten Orte ist zu lang für die Meldungsansicht allein.
  MessageDlg(StringReplace(Text, '; ', sLineBreak, [rfReplaceAll]), mtInformation, [mbOK], 0);
end;

end.
