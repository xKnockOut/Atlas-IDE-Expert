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
    cSearchPathCommand = 'atlas.addSearchPath';
    cAddUnitCommand = 'atlas.addUnitToProject';
    cInfoCommand = 'atlas.showInfo';
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
  Atlas.UI.Editor.Strings,
  Atlas.Core.Editor.MissingUnit,
  Atlas.IDE.Foundation.Files;

/// <summary>Konfiguration AName des Projekts; '' = Basis. nil, wenn es sie nicht gibt.</summary>
function ConfigurationOf(const AProject: IOTAProject; const AName: string): IOTABuildConfiguration;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mConfigurations) then
  begin
    Exit;
  end;
  if AName = '' then
  begin
    Exit(mConfigurations.BaseConfiguration);
  end;
  for mIndex := 0 to mConfigurations.ConfigurationCount - 1 do
  begin
    if SameText(mConfigurations.Configurations[mIndex].Name, AName) then
    begin
      Exit(mConfigurations.Configurations[mIndex]);
    end;
  end;
end;

/// <summary>Trägt den Ordner von ARequest in AConfiguration ein; False mit Meldung, wenn er schon (auch geerbt)
/// drinsteht oder die IDE ablehnt. ALabel: Name der Konfiguration für die Meldung.</summary>
function WriteSearchPath(const AProject: IOTAProject; const AConfiguration: IOTABuildConfiguration;
  const ARequest: TAtlasSearchPathRequest; const ALabel: string; const AMessage: TProc<string>): Boolean;
var
  mRaw: string;
begin
  Result := False;
  try
    // Mit Geerbtem: Steht der Ordner schon in der Basis, braucht ihn die Konfiguration nicht noch einmal.
    if TAtlasSearchPaths.Contains(AConfiguration.GetValue(TAtlasSearchPaths.cOptionName, True), ARequest.Folder) then
    begin
      AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitSearchPathPresent, [ARequest.Folder, ALabel,
        ExtractFileName(AProject.FileName)]));
      Exit;
    end;
    mRaw := AConfiguration.GetValue(TAtlasSearchPaths.cOptionName, False);
    AConfiguration.SetValue(TAtlasSearchPaths.cOptionName,
      TAtlasSearchPaths.WithFolder(mRaw, ARequest.Folder, ARequest.Config = ''));
    AProject.MarkModified;
    Result := True;
  except
    on E: Exception do
    begin
      AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitSearchPathFailed, [E.Message]));
    end;
  end;
end;

class procedure TAtlasIdeMissingUnit.AddSearchPath(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  mRequest: TAtlasSearchPathRequest;
  mProject: IOTAProject;
  mConfiguration: IOTABuildConfiguration;
  mLabel_: string;
begin
  if not TAtlasSearchPathRequest.TryParse(AArgumentsJson, mRequest) then
  begin
    Exit;
  end;
  mProject := TAtlasIdeFiles.GroupProject(mRequest.ProjectFile);
  if mProject = nil then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitNoProject, [ExtractFileName(mRequest.ProjectFile)]));
    Exit;
  end;
  mLabel_ := mRequest.Config;
  if mLabel_ = '' then
  begin
    mLabel_ := TAtlasEditorStrings.Text(TAtlasEditorTextId.MissingUnitAllConfigs);
  end;
  mConfiguration := ConfigurationOf(mProject, mRequest.Config);
  if mConfiguration = nil then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitConfigNotFound, [mRequest.Config,
      ExtractFileName(mProject.FileName)]));
    Exit;
  end;
  if WriteSearchPath(mProject, mConfiguration, mRequest, mLabel_, AMessage) then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitSearchPathDone, [mLabel_,
      ExtractFileName(mProject.FileName),
      mRequest.Folder]));
  end;
end;

class procedure TAtlasIdeMissingUnit.AddUnit(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  mRequest: TAtlasAddUnitRequest;
  mProject: IOTAProject;
begin
  if not TAtlasAddUnitRequest.TryParse(AArgumentsJson, mRequest) then
  begin
    Exit;
  end;
  mProject := TAtlasIdeFiles.GroupProject(mRequest.ProjectFile);
  if mProject = nil then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitNoProject, [ExtractFileName(mRequest.ProjectFile)]));
    Exit;
  end;
  if mProject.FindModuleInfo(mRequest.FileName) <> nil then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitAlreadyInProject,
      [ExtractFileName(mRequest.FileName),
      ExtractFileName(mProject.FileName)]));
    Exit;
  end;
  try
    mProject.AddFile(mRequest.FileName, True);
  except
    on E: Exception do
    begin
      AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitAddFailed, [ExtractFileName(mRequest.FileName),
        E.Message]));
      Exit;
    end;
  end;
  AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.MissingUnitAdded, [ExtractFileName(mRequest.FileName),
    ExtractFileName(mProject.FileName)]));
end;

class procedure TAtlasIdeMissingUnit.ShowInfo(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  mText: string;
begin
  if not TAtlasSearchPaths.TryParseInfo(AArgumentsJson, mText) then
  begin
    Exit;
  end;
  AMessage(mText);
  // Die Liste der durchsuchten Orte ist zu lang für die Meldungsansicht allein.
  MessageDlg(StringReplace(mText, '; ', sLineBreak, [rfReplaceAll]), mtInformation, [mbOK], 0);
end;

end.
