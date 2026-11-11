unit Shell.Commands.Build;

// Host-Rolle Shell: Fachlogik der Befehle atlas.selectBuild (#46, #615) und
// "Formulare in Text umwandeln" ohne Bezug auf TServerComposition. Die
// Komposition reicht Projekte und Dateien herein; hier stehen Auswertung der
// Argumente, Auswahl der Formulardateien und der Aufbau der Antwort.
// Ohne Windows-Units, damit die Tests auch ohne Windows laufen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Projects.Contract;

type
  /// <summary>Argument von atlas.selectBuild: {"config", "platform", "uri", "defines"}, alle optional.</summary>
  TSelectBuildArgs = record
    Config: string;
    Platform: string;
    Uri: string;
    /// <summary>Ersetzt die Symbole der .dproj, wenn HasDefines (Projektoptionen der IDE, #615).</summary>
    Defines: TArray<string>;
    HasDefines: Boolean;
    /// <summary>Liest das erste Argument; fehlt es oder ist es kein Objekt, bleiben alle Felder leer.</summary>
    class function Parse(const AArguments: TJSONArray): TSelectBuildArgs; static;
    /// <summary>True, wenn Konfiguration, Plattform oder Symbole geändert werden sollen; sonst nur Abfrage.</summary>
    function Changes: Boolean;
  end;

  /// <summary>Argument von atlas.server.selectProject (#46): {"project"} wählt ein Projekt (Pfad der .dproj,
  /// URI oder Name); "" hebt die Wahl auf; ohne "project" nur Abfrage.</summary>
  TSelectProjectArgs = record
    Project: string;
    HasProject: Boolean;
    class function Parse(const AArguments: TJSONArray): TSelectProjectArgs; static;
  end;

  /// <summary>Ein Projekt in der Antwort von atlas.server.selectProject.</summary>
  TProjectChoiceItem = record
    Name: string;
    Project: string;
    Active: Boolean;
    Selected: Boolean;
  end;

  TBuildCommands = class
  public
    /// <summary>Antwort von atlas.server.selectProject: {"selected", "active", "projects": [...]}.</summary>
    class function ProjectChoices(const AItems: TArray<TProjectChoiceItem>): TJSONObject; static;
    /// <summary>Index von ATarget in AItems: gleicher Pfad oder Name (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function FindProject(const AItems: TArray<TProjectChoiceItem>; const ATarget: string): Integer; static;
    /// <summary>Werte als JSON-Liste von Strings.</summary>
    class function StringsToJson(const AValues: TArray<string>): TJSONArray; static;
    /// <summary>Eintrag der Antwort von atlas.selectBuild zu einem Projekt; gewählte Werte vor denen des
    /// Projekts.</summary>
    class function ProjectItem(const AFolder: string; const AProject: TProjectInfo;
      const AArgs: TSelectBuildArgs): TJSONObject; static;
    /// <summary>Formulare für die Umwandlung: mit URI im ersten Argument diese Datei, sonst .dfm und .fmx
    /// neben den Units AProjectSources, die es laut AExists gibt.</summary>
    class function FormFiles(const AArguments: TJSONArray; const AProjectSources: TArray<string>;
      const AExists: TFunc<string, Boolean>): TArray<string>; static;
    /// <summary>Wandelt binäre Formulare in Text um; Fehler je Datei als Warnung in ALogger. Liefert die Zahl
    /// der umgewandelten Dateien, ABackups die der Sicherungskopien (.bak).</summary>
    class function ConvertForms(const AFiles: TArray<string>; const ALogger: ILogger; out ABackups: Integer): Integer;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.BinaryForm,
  Atlas.Text.LogMarks;

{ TSelectBuildArgs }

class function TSelectBuildArgs.Parse(const AArguments: TJSONArray): TSelectBuildArgs;
var
  mOptions: TJSONObject;
  mDefinesValue, mDefine: TJSONValue;
begin
  Result := Default(TSelectBuildArgs);
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONObject) then
  begin
    Exit;
  end;
  mOptions := TJSONObject(AArguments.Items[0]);
  mOptions.TryGetValue<string>('config', Result.Config);
  mOptions.TryGetValue<string>('platform', Result.Platform);
  mOptions.TryGetValue<string>('uri', Result.Uri);
  mDefinesValue := mOptions.GetValue('defines');
  if mDefinesValue is TJSONArray then
  begin
    Result.HasDefines := True;
    for mDefine in TJSONArray(mDefinesValue) do
    begin
      if mDefine is TJSONString then
      begin
        Result.Defines := Result.Defines + [TJSONString(mDefine).Value];
      end;
    end;
  end;
end;

function TSelectBuildArgs.Changes: Boolean;
begin
  Result := (Config <> '') or (Platform <> '') or HasDefines;
end;

{ TSelectProjectArgs }

class function TSelectProjectArgs.Parse(const AArguments: TJSONArray): TSelectProjectArgs;
var
  mValue: TJSONValue;
begin
  Result := Default(TSelectProjectArgs);
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONObject) then
  begin
    Exit;
  end;
  mValue := TJSONObject(AArguments.Items[0]).GetValue('project');
  // TJSONNumber erbt von TJSONString.
  Result.HasProject := (mValue is TJSONString) and not (mValue is TJSONNumber);
  if not Result.HasProject then
  begin
    Exit;
  end;
  Result.Project := Trim(mValue.Value);
  if Result.Project.StartsWith('file:', True) then
  begin
    Result.Project := TDocumentUris.ToPath(Result.Project);
  end;
end;

{ TBuildCommands }

class function TBuildCommands.FindProject(const AItems: TArray<TProjectChoiceItem>; const ATarget: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Project, ATarget) or SameText(AItems[mIndex].Name, ATarget) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TBuildCommands.ProjectChoices(const AItems: TArray<TProjectChoiceItem>): TJSONObject;
var
  mItem: TProjectChoiceItem;
  mEntry: TJSONObject;
  mItems: TJSONArray;
  mSelected, mActive: string;
begin
  mSelected := '';
  mActive := '';
  mItems := TJSONArray.Create;
  for mItem in AItems do
  begin
    mEntry := TJSONObject.Create;
    mEntry.AddPair('name', mItem.Name);
    mEntry.AddPair('project', mItem.Project);
    mEntry.AddPair('active', TJSONBool.Create(mItem.Active));
    mEntry.AddPair('selected', TJSONBool.Create(mItem.Selected));
    mItems.AddElement(mEntry);
    if mItem.Selected and (mSelected = '') then
    begin
      mSelected := mItem.Project;
    end;
    if mItem.Active and (mActive = '') then
    begin
      mActive := mItem.Project;
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('selected', mSelected);
  Result.AddPair('active', mActive);
  Result.AddPair('projects', mItems);
end;


class function TBuildCommands.StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

class function TBuildCommands.ProjectItem(const AFolder: string; const AProject: TProjectInfo;
  const AArgs: TSelectBuildArgs): TJSONObject;
var
  mConfig, mPlatform: string;
begin
  mConfig := AArgs.Config;
  if mConfig = '' then
  begin
    mConfig := AProject.Config;
  end;
  mPlatform := AArgs.Platform;
  if mPlatform = '' then
  begin
    mPlatform := AProject.Platform;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('folder', AFolder);
  Result.AddPair('project', AProject.FileName);
  Result.AddPair('config', mConfig);
  Result.AddPair('platform', mPlatform);
  Result.AddPair('configs', StringsToJson(AProject.Configs));
  Result.AddPair('platforms', StringsToJson(AProject.Platforms));
end;

class function TBuildCommands.FormFiles(const AArguments: TJSONArray; const AProjectSources: TArray<string>;
  const AExists: TFunc<string, Boolean>): TArray<string>;
var
  mFileName, mExtension: string;
begin
  Result := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    // Delphi: Exit mit Array-Literal geht nicht (E2001).
    Result := [TDocumentUris.ToPath(AArguments.Items[0].Value)];
    Exit;
  end;
  for mFileName in AProjectSources do
  begin
    for mExtension in TArray<string>.Create('.dfm', '.fmx') do
    begin
      if AExists(ChangeFileExt(mFileName, mExtension)) then
      begin
        Result := Result + [ChangeFileExt(mFileName, mExtension)];
      end;
    end;
  end;
end;

class function TBuildCommands.ConvertForms(const AFiles: TArray<string>; const ALogger: ILogger;
  out ABackups: Integer): Integer;
var
  mForm, mBackup: string;
begin
  Result := 0;
  ABackups := 0;
  for mForm in AFiles do
    try
      if TDfmBinary.ConvertFile(mForm, mBackup) then
      begin
        Inc(Result);
        if mBackup <> '' then
        begin
          Inc(ABackups);
        end;
      end;
    except
      on E: Exception do
        ALogger.Warning(Format('%s nicht umgewandelt: %s', [TLogMarks.Path(mForm), TLogMarks.Text(E.Message)]));
    end;
end;

end.
