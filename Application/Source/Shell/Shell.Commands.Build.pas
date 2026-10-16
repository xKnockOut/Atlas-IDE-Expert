unit Shell.Commands.Build;

// Host-Rolle Shell: Fachlogik der Befehle atlas.selectBuild (#46, #615) und
// "Formulare in Text umwandeln" ohne Bezug auf TServerComposition (S-02). Die
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

  TBuildCommands = class
  public
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
  Atlas.Common.Dfm.BinaryForm;

{ TSelectBuildArgs }

class function TSelectBuildArgs.Parse(const AArguments: TJSONArray): TSelectBuildArgs;
var
  Options: TJSONObject;
  DefinesValue, Define: TJSONValue;
begin
  Result := Default(TSelectBuildArgs);
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONObject) then
    Exit;
  Options := TJSONObject(AArguments.Items[0]);
  Options.TryGetValue<string>('config', Result.Config);
  Options.TryGetValue<string>('platform', Result.Platform);
  Options.TryGetValue<string>('uri', Result.Uri);
  DefinesValue := Options.GetValue('defines');
  if DefinesValue is TJSONArray then
  begin
    Result.HasDefines := True;
    for Define in TJSONArray(DefinesValue) do
      if Define is TJSONString then
        Result.Defines := Result.Defines + [TJSONString(Define).Value];
  end;
end;

function TSelectBuildArgs.Changes: Boolean;
begin
  Result := (Config <> '') or (Platform <> '') or HasDefines;
end;

{ TBuildCommands }

class function TBuildCommands.StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
end;

class function TBuildCommands.ProjectItem(const AFolder: string; const AProject: TProjectInfo;
  const AArgs: TSelectBuildArgs): TJSONObject;
var
  Config, Platform: string;
begin
  Config := AArgs.Config;
  if Config = '' then
    Config := AProject.Config;
  Platform := AArgs.Platform;
  if Platform = '' then
    Platform := AProject.Platform;
  Result := TJSONObject.Create;
  Result.AddPair('folder', AFolder);
  Result.AddPair('project', AProject.FileName);
  Result.AddPair('config', Config);
  Result.AddPair('platform', Platform);
  Result.AddPair('configs', StringsToJson(AProject.Configs));
  Result.AddPair('platforms', StringsToJson(AProject.Platforms));
end;

class function TBuildCommands.FormFiles(const AArguments: TJSONArray; const AProjectSources: TArray<string>;
  const AExists: TFunc<string, Boolean>): TArray<string>;
var
  FileName, Extension: string;
begin
  Result := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    // Delphi: Exit mit Array-Literal geht nicht (E2001).
    Result := [TDocumentUris.ToPath(AArguments.Items[0].Value)];
    Exit;
  end;
  for FileName in AProjectSources do
    for Extension in TArray<string>.Create('.dfm', '.fmx') do
      if AExists(ChangeFileExt(FileName, Extension)) then
        Result := Result + [ChangeFileExt(FileName, Extension)];
end;

class function TBuildCommands.ConvertForms(const AFiles: TArray<string>; const ALogger: ILogger;
  out ABackups: Integer): Integer;
var
  Form, Backup: string;
begin
  Result := 0;
  ABackups := 0;
  for Form in AFiles do
    try
      if TDfmBinary.ConvertFile(Form, Backup) then
      begin
        Inc(Result);
        if Backup <> '' then
          Inc(ABackups);
      end;
    except
      on E: Exception do
        ALogger.Warning(Format('%s nicht umgewandelt: %s', [Form, E.Message]));
    end;
end;

end.
