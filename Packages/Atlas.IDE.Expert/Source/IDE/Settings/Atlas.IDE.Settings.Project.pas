unit Atlas.IDE.Settings.Project;

// Server-Einstellungen bearbeiten (#227): atlas.json neben der .dproj des
// aktiven Projekts (Atlas > Projekt-Einstellungen) und die globale Datei
// %APPDATA%\Atlas\settings.json (Tools › Optionen › Atlas › Server). Der Dialog
// zeigt im Projekt, was global gilt. Geschrieben werden nur die geänderten
// Werte (TAtlasJsonText); Kommentare, unbekannte Schlüssel, Reihenfolge,
// Kodierung und Zeilenenden bleiben (TAtlasTextFile, #121). Ohne Änderung
// wird die Datei nicht angefasst. Der Server liest beide Dateien über seinen
// Dateibeobachter neu ein.
// Der laufende Server prüft vor dem Speichern (atlas.server.checkSettings) und
// liefert den Regelkatalog (atlas.server.settingsCatalog); ohne ihn prüft der
// Dialog nur die Syntax. Auswahllisten: installierte Delphi-Versionen aus der
// Registry, Konfigurationen und Plattformen aus der .dproj, Profile.
// Die Schnellschalter (#604) lesen und setzen einzelne Werte über
// ReadProject und WriteValue.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Befehl mit Argumenten (JSON-Array) an den laufenden Server; nil ohne Server. Ergebnis gehört
  /// dem Aufrufer.</summary>
  TAtlasSettingsCommand = reference to function(const ACommand, AArgumentsJson: string): TJSONValue;

  TAtlasProjectSettings = class
  private class var
    FCommand: TAtlasSettingsCommand;
  private
    class procedure ExecuteFile(const AFileName: string; AGlobal: Boolean); static;
  public const
    CheckCommand = 'atlas.server.checkSettings';
    CatalogCommand = 'atlas.server.settingsCatalog';
  public
    /// <summary>atlas.json des aktiven Projekts; '' ohne Projekt.</summary>
    class function SettingsFile: string; static;
    /// <summary>%APPDATA%\Atlas\settings.json; '' ohne APPDATA.</summary>
    class function GlobalFile: string; static;
    /// <summary>.dproj des aktiven Projekts; '' ohne.</summary>
    class function ActiveProject: string; static;
    /// <summary>Dialog für atlas.json des aktiven Projekts zeigen und Änderungen schreiben.</summary>
    class procedure Execute; static;
    /// <summary>Dialog für die globale Datei zeigen und Änderungen schreiben.</summary>
    class procedure ExecuteGlobal; static;
    /// <summary>Inhalt der Datei als Text (ohne BOM); '' wenn es sie nicht gibt.</summary>
    class function ReadText(const AFileName: string; out AHasBom: Boolean): string; static;
    /// <summary>atlas.json des aktiven Projekts als Objekt; nil ohne Projekt, ohne Datei oder bei ungültigem
    /// Inhalt. Der Aufrufer gibt es frei.</summary>
    class function ReadProject: TJSONObject; static;
    /// <summary>Setzt APath in atlas.json des aktiven Projekts auf AJson; Kommentare, Reihenfolge und
    /// Kodierung bleiben. False ohne Projekt.</summary>
    class function WriteValue(const APath, AJson: string): Boolean; static;
    /// <summary>Installierte Delphi-Versionen (Registry-Nummern wie "23.0").</summary>
    class function InstalledVersions: TArray<string>; static;
    /// <summary>Weg zum laufenden Server; setzt die Komposition.</summary>
    class property Command: TAtlasSettingsCommand read FCommand write FCommand;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.Win.Registry,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Choices,
  Atlas.Core.Settings.Validation,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Build.Target,
  Atlas.IDE.Build.Target,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ProjectDialog;

function RunCommand(const ACommand, AArgumentsJson: string): TJSONValue;
begin
  Result := nil;
  if Assigned(TAtlasProjectSettings.Command) then
    Result := TAtlasProjectSettings.Command(ACommand, AArgumentsJson);
end;

/// <summary>Datei lesen; Kodierung und BOM merkt sich AContent. Neue Dateien: UTF-8 ohne BOM.</summary>
function LoadContent(const AFileName: string): TAtlasTextFileContent;
begin
  if (AFileName <> '') and TFile.Exists(AFileName) then
    Result := TAtlasTextFile.Load(AFileName)
  else
  begin
    Result := Default(TAtlasTextFileContent);
    Result.Encoding := TAtlasTextEncoding.Utf8;
  end;
end;

{ TAtlasProjectSettings }

class function TAtlasProjectSettings.ActiveProject: string;
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Project := Modules.GetActiveProject;
  if Project <> nil then
    Result := Project.FileName;
end;

class function TAtlasProjectSettings.SettingsFile: string;
var
  Project: string;
begin
  Result := '';
  Project := ActiveProject;
  if Project <> '' then
    Result := TPath.Combine(ExtractFileDir(Project), TAtlasSettingsFiles.ProjectName);
end;

class function TAtlasProjectSettings.GlobalFile: string;
begin
  Result := TAtlasSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

class function TAtlasProjectSettings.ReadText(const AFileName: string; out AHasBom: Boolean): string;
var
  Content: TAtlasTextFileContent;
begin
  Result := '';
  AHasBom := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  Content := TAtlasTextFile.Load(AFileName);
  AHasBom := Content.Encoding = TAtlasTextEncoding.Utf8Bom;
  Result := Content.Text;
end;

class function TAtlasProjectSettings.ReadProject: TJSONObject;
var
  HasBom: Boolean;
begin
  Result := TAtlasJsonText.Parse(ReadText(SettingsFile, HasBom));
end;

class function TAtlasProjectSettings.WriteValue(const APath, AJson: string): Boolean;
var
  FileName, NewText: string;
  Content: TAtlasTextFileContent;
begin
  FileName := SettingsFile;
  Result := FileName <> '';
  if not Result then
    Exit;
  Content := LoadContent(FileName);
  NewText := TAtlasJsonText.SetValue(Content.Text, APath, AJson);
  if NewText = Content.Text then
    Exit;
  Content.Text := NewText;
  TAtlasTextFile.Save(FileName, Content);
end;

class function TAtlasProjectSettings.InstalledVersions: TArray<string>;
const
  Roots: array[0..1] of HKEY = (HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE);
var
  Registry: TRegistry;
  Keys: TStringList;
  Key: string;
  Root: HKEY;
begin
  Result := nil;
  Keys := TStringList.Create;
  try
    for Root in Roots do
    begin
      Registry := TRegistry.Create(KEY_READ);
      try
        Registry.RootKey := Root;
        if Registry.OpenKeyReadOnly('Software\Embarcadero\BDS') then
        begin
          Keys.Clear;
          Registry.GetKeyNames(Keys);
          for Key in Keys do
            if (Key <> '') and CharInSet(Key[1], ['0'..'9']) then
              Result := Result + [Key];
        end;
      finally
        Registry.Free;
      end;
    end;
  finally
    Keys.Free;
  end;
end;

class procedure TAtlasProjectSettings.Execute;
var
  FileName: string;
begin
  FileName := SettingsFile;
  if FileName = '' then
  begin
    MessageBox(Application.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject)),
      PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle)), MB_ICONINFORMATION or MB_OK);
    Exit;
  end;
  ExecuteFile(FileName, False);
end;

class procedure TAtlasProjectSettings.ExecuteGlobal;
var
  FileName: string;
begin
  FileName := GlobalFile;
  if FileName <> '' then
    ExecuteFile(FileName, True);
end;

class procedure TAtlasProjectSettings.ExecuteFile(const AFileName: string; AGlobal: Boolean);
var
  Content: TAtlasTextFileContent;
  GlobalText, Title, Project, DprojText: string;
  Root: TJSONObject;
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
  Target: TAtlasBuildTarget;
  OpenFile, Accepted: Boolean;
  Actions: IOTAActionServices;
begin
  if AGlobal then
    Title := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsGlobalTitle)
  else
    Title := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle);
  Content := LoadContent(AFileName);
  Root := TAtlasJsonText.Parse(Content.Text);
  try
    if (Root = nil) and (Trim(Content.Text) <> '') then
    begin
      if AGlobal then
        MessageBox(Application.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.GlobalSettingsInvalid)), PChar(Title),
          MB_ICONWARNING or MB_OK)
      else
        MessageBox(Application.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsInvalid)), PChar(Title),
          MB_ICONWARNING or MB_OK);
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenFile(AFileName);
      Exit;
    end;
  finally
    Root.Free;
  end;
  // Im Projekt zeigt der Dialog, was global gilt.
  GlobalText := '';
  if not AGlobal then
    GlobalText := LoadContent(GlobalFile).Text;
  Project := ActiveProject;
  DprojText := '';
  if SameText(ExtractFileExt(Project), '.dproj') and TFile.Exists(Project) then
    DprojText := LoadContent(Project).Text;
  OpenFile := False;
  // Namen und Kategorien der Regeln in der Sprache der Oberfläche (#446).
  if TAtlasStrings.Language = TAtlasLanguage.English then
    Catalog := RunCommand(CatalogCommand, '["en"]')
  else
    Catalog := RunCommand(CatalogCommand, '["de"]');
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), Content.Text, GlobalText,
    AGlobal);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, AFileName);
    try
      Dialog.Catalog := Catalog;
      Dialog.ServerChecks := Catalog <> nil;
      if not AGlobal then
      begin
        Dialog.ProjectHint := ExtractFileName(Project);
        // Die IDE sendet ihre Auswahl laufend an den Server (selectBuild, #46, #615).
        if TAtlasIdeBuildTarget.Read(Target) then
          Dialog.BuildHint := TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsBuildOverride,
            [Target.Config, Target.Platform]);
      end;
      Dialog.OnChoices :=
        function(const APath: string): TArray<TAtlasSettingChoice>
        var
          Profiles: Integer;
        begin
          Result := nil;
          if APath = 'delphiVersion' then
            Result := TAtlasSettingChoices.DelphiVersions(InstalledVersions)
          else if APath = 'config' then
            Result := TAtlasSettingChoices.FromTexts(TAtlasSettingChoices.DprojConfigs(DprojText))
          else if APath = 'platform' then
            Result := TAtlasSettingChoices.FromTexts(TAtlasSettingChoices.DprojPlatforms(DprojText))
          else if (APath = 'project') and (Project <> '') and not AGlobal then
            Result := TAtlasSettingChoices.FromTexts([ExtractRelativePath(IncludeTrailingPathDelimiter(
              ExtractFileDir(AFileName)), Project)])
          else if (APath = 'profile') or (APath = 'testProfile') then
          begin
            Profiles := Model.IndexOf('profiles');
            if Profiles >= 0 then
              Result := TAtlasSettingChoices.FromTexts(TAtlasSettingChoices.Profiles(Model.Effective(Profiles)));
          end;
        end;
      Dialog.OnValidate :=
        function(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>
        var
          Answer: TJSONValue;
          Valid: Boolean;
        begin
          Answer := RunCommand(CheckCommand, '[' + TAtlasJsonText.Quote(AText) + ']');
          try
            AChecked := TAtlasSettingsValidation.FromAnswer(Answer, Result, Valid);
          finally
            Answer.Free;
          end;
          if not AChecked then
            TAtlasSettingsValidation.Syntax(AText, Result);
        end;
      Dialog.OnOpenFile :=
        procedure
        begin
          OpenFile := True;
        end;
      Accepted := Dialog.ShowModal = mrOk;
    finally
      Dialog.Free;
    end;
    if Accepted and Model.Modified then
    begin
      Content.Text := Model.ResultText;
      ForceDirectories(ExtractFileDir(AFileName));
      TAtlasTextFile.Save(AFileName, Content);
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
  if OpenFile and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
  begin
    if not TFile.Exists(AFileName) then
    begin
      ForceDirectories(ExtractFileDir(AFileName));
      TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes('{' + sLineBreak + '}' + sLineBreak));
    end;
    Actions.OpenFile(AFileName);
  end;
end;

end.
