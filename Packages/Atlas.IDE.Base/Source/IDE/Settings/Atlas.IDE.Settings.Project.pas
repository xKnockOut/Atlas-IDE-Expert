unit Atlas.IDE.Settings.Project;

// Server-Einstellungen bearbeiten (#227): atlas.json neben der .dproj des
// aktiven Projekts (Atlas > Projekt-Einstellungen) und die globale Datei
// %APPDATA%\Atlas\settings.json (Tools › Optionen › Atlas › Server › „Weitere
// globale Einstellungen“). Jede Einstellung hat genau einen Ort (x-scope): Der
// Projektdialog zeigt nur Projekt-Schlüssel, der globale nur die globalen, die
// nicht schon die Reiter der Optionsseite oder die IDE selbst setzen
// (TAtlasSettingsScopes.IdeManagedPaths). Geschrieben werden nur die geänderten
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
    class procedure ExecuteFile(const AFileName: string; AGlobal: Boolean; const ARuleId: string); static;
  public const
    cCheckCommand = 'atlas.server.checkSettings';
    cCatalogCommand = 'atlas.server.settingsCatalog';
  public
    /// <summary>atlas.json des aktiven Projekts; '' ohne Projekt.</summary>
    class function SettingsFile: string; static;
    /// <summary>%APPDATA%\Atlas\settings.json; '' ohne APPDATA.</summary>
    class function GlobalFile: string; static;
    /// <summary>Dialog für atlas.json des aktiven Projekts zeigen und Änderungen schreiben.</summary>
    class procedure Execute; static;
    /// <summary>Dialog für die globale Datei zeigen und Änderungen schreiben.</summary>
    class procedure ExecuteGlobal; static;
    /// <summary>„Regel einstellen…“ (#909): Dialog des aktiven Projekts, ohne Projekt der globale, im Knoten der
    /// Gruppe der Regel mit markierter Regel.</summary>
    class procedure ShowRule(const ARuleId: string); static;
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
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.Choices,
  Atlas.Core.Settings.Validation,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Build.Target,
  Atlas.IDE.Build.Target,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Files;

/// <summary>Dialogklasse mit Regel-Editor eines laufenden Moduls (Prüfregeln, #1755); sonst die von Base.
/// </summary>
function DialogClass: TAtlasProjectSettingsDialogClass;
var
  mItem: IInterface;
  mProvider: IAtlasSettingsDialogProvider;
begin
  Result := TAtlasProjectSettingsDialog;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasSettingsDialogProvider) do
  begin
    if Supports(mItem, IAtlasSettingsDialogProvider, mProvider) then
    begin
      Exit(mProvider.DialogClass);
    end;
  end;
end;

function RunCommand(const ACommand, AArgumentsJson: string): TJSONValue;
begin
  Result := nil;
  if Assigned(TAtlasProjectSettings.Command) then
  begin
    Result := TAtlasProjectSettings.Command(ACommand, AArgumentsJson);
  end;
end;

/// <summary>Datei lesen; Kodierung und BOM merkt sich AContent. Neue Dateien: UTF-8 ohne BOM.</summary>
function LoadContent(const AFileName: string): TAtlasTextFileContent;
begin
  if (AFileName <> '') and TFile.Exists(AFileName) then
  begin
    Result := TAtlasTextFile.Load(AFileName);
  end
  else
  begin
    Result := Default(TAtlasTextFileContent);
    Result.Encoding := TAtlasTextEncoding.Utf8;
  end;
end;

{ TAtlasProjectSettings }

class function TAtlasProjectSettings.SettingsFile: string;
var
  mProject: string;
begin
  Result := '';
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if mProject <> '' then
  begin
    Result := TPath.Combine(ExtractFileDir(mProject), TAtlasSettingsFiles.cProjectName);
  end;
end;

class function TAtlasProjectSettings.GlobalFile: string;
begin
  Result := TAtlasSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

class function TAtlasProjectSettings.ReadText(const AFileName: string; out AHasBom: Boolean): string;
var
  mContent: TAtlasTextFileContent;
begin
  Result := '';
  AHasBom := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
  begin
    Exit;
  end;
  mContent := TAtlasTextFile.Load(AFileName);
  AHasBom := mContent.Encoding = TAtlasTextEncoding.Utf8Bom;
  Result := mContent.Text;
end;

class function TAtlasProjectSettings.ReadProject: TJSONObject;
var
  mHasBom: Boolean;
begin
  Result := TAtlasJsonText.Parse(ReadText(SettingsFile, mHasBom));
end;

class function TAtlasProjectSettings.WriteValue(const APath, AJson: string): Boolean;
var
  mFileName, mNewText: string;
  mContent: TAtlasTextFileContent;
begin
  mFileName := SettingsFile;
  Result := mFileName <> '';
  if not Result then
  begin
    Exit;
  end;
  mContent := LoadContent(mFileName);
  mNewText := TAtlasJsonText.SetValue(mContent.Text, APath, AJson);
  if mNewText = mContent.Text then
  begin
    Exit;
  end;
  mContent.Text := mNewText;
  TAtlasTextFile.Save(mFileName, mContent);
end;

/// <summary>Versionsnummern unter Software\Embarcadero\BDS des Zweigs ARoot an AVersions anhängen.</summary>
procedure AddInstalledVersions(ARoot: HKEY; var AVersions: TArray<string>);
var
  mRegistry: TRegistry;
  mKeys: TStringList;
  mKey: string;
begin
  mKeys := TStringList.Create;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := ARoot;
    if not mRegistry.OpenKeyReadOnly('Software\Embarcadero\BDS') then
    begin
      Exit;
    end;
    mRegistry.GetKeyNames(mKeys);
    for mKey in mKeys do
    begin
      if (mKey <> '') and CharInSet(mKey[1], ['0'..'9']) then
      begin
        AVersions := AVersions + [mKey];
      end;
    end;
  finally
    mRegistry.Free;
    mKeys.Free;
  end;
end;

class function TAtlasProjectSettings.InstalledVersions: TArray<string>;
begin
  Result := nil;
  AddInstalledVersions(HKEY_CURRENT_USER, Result);
  AddInstalledVersions(HKEY_LOCAL_MACHINE, Result);
end;

class procedure TAtlasProjectSettings.Execute;
var
  mFileName: string;
begin
  mFileName := SettingsFile;
  if mFileName = '' then
  begin
    MessageBox(Application.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject)),
      PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle)), MB_ICONINFORMATION or MB_OK);
    Exit;
  end;
  ExecuteFile(mFileName, False, '');
end;

class procedure TAtlasProjectSettings.ExecuteGlobal;
var
  mFileName: string;
begin
  mFileName := GlobalFile;
  if mFileName <> '' then
  begin
    ExecuteFile(mFileName, True, '');
  end;
end;

class procedure TAtlasProjectSettings.ShowRule(const ARuleId: string);
var
  mFileName: string;
begin
  // Im Projekt, wenn eins aktiv ist: Dort wirkt die Einstellung für diesen Befund; sonst global.
  mFileName := SettingsFile;
  if mFileName <> '' then
  begin
    ExecuteFile(mFileName, False, ARuleId);
  end
  else
  begin
    mFileName := GlobalFile;
    if mFileName <> '' then
    begin
      ExecuteFile(mFileName, True, ARuleId);
    end;
  end;
end;

type
  /// <summary>Ein Lauf des Dialogs über eine Einstellungsdatei: prüfen, zeigen, speichern, auf Wunsch im Editor
  /// öffnen.</summary>
  TAtlasSettingsFileEdit = class
  private
    FFileName: string;
    FGlobal: Boolean;
    FRuleId: string;
    FTitle: string;
    FContent: TAtlasTextFileContent;
    FProject: string;
    FDprojText: string;
    FCheckScope: string;
    FOpenFile: Boolean;
    FModel: TAtlasSettingsModel;
    FCatalog: TJSONValue;
    /// <summary>False (mit Meldung und geöffneter Datei), wenn die Datei Text enthält, der kein JSON-Objekt ist.
    /// </summary>
    function ContentValid: Boolean;
    /// <summary>Felder nach dem Ort der Datei: Im Projekt gibt es keine globale Vorgabe, die es überschreiben
    /// könnte.</summary>
    function Fields: TArray<TAtlasSettingField>;
    /// <summary>Regelkatalog des Servers in der Sprache der Oberfläche (#446); nil ohne Server.</summary>
    function LoadCatalog: TJSONValue;
    function DprojChoices(const APath: string): TArray<TAtlasSettingChoice>;
    function Choices(const APath: string): TArray<TAtlasSettingChoice>;
    function Validate(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>;
    procedure Prepare(ADialog: TAtlasProjectSettingsDialog);
    /// <summary>Dialog zeigen; True nach OK.</summary>
    function ShowDialog: Boolean;
    procedure Save;
    procedure OpenIfAsked;
  public
    constructor Create(const AFileName: string; AGlobal: Boolean; const ARuleId: string);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TAtlasSettingsFileEdit.Create(const AFileName: string; AGlobal: Boolean; const ARuleId: string);
begin
  inherited Create;
  FFileName := AFileName;
  FGlobal := AGlobal;
  FRuleId := ARuleId;
  if AGlobal then
  begin
    FTitle := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProjectSettingsGlobalTitle);
    FCheckScope := ',"global"';
  end
  else
  begin
    FTitle := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle);
    FCheckScope := '';
  end;
  FContent := LoadContent(AFileName);
end;

destructor TAtlasSettingsFileEdit.Destroy;
begin
  FModel.Free;
  FCatalog.Free;
  inherited Destroy;
end;

function TAtlasSettingsFileEdit.ContentValid: Boolean;
var
  mRoot: TJSONObject;
  mMessage: TAtlasTextId;
  mActions: IOTAActionServices;
begin
  mRoot := TAtlasJsonText.Parse(FContent.Text);
  Result := (mRoot <> nil) or (Trim(FContent.Text) = '');
  mRoot.Free;
  if Result then
  begin
    Exit;
  end;
  mMessage := TAtlasTextId.ProjectSettingsInvalid;
  if FGlobal then
  begin
    mMessage := TAtlasTextId.GlobalSettingsInvalid;
  end;
  MessageBox(Application.Handle, PChar(TAtlasStrings.Text(mMessage)), PChar(FTitle), MB_ICONWARNING or MB_OK);
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenFile(FFileName);
  end;
end;

function TAtlasSettingsFileEdit.Fields: TArray<TAtlasSettingField>;
begin
  if FGlobal then
  begin
    Result := TAtlasSettingsSchema.ForScope(TAtlasSettingsSchema.Fields(AtlasSchemaJson), True,
      TAtlasSettingsScopes.IdeManagedPaths);
  end
  else
  begin
    Result := TAtlasSettingsSchema.ForScope(TAtlasSettingsSchema.Fields(AtlasSchemaJson), False, nil);
  end;
end;

function TAtlasSettingsFileEdit.LoadCatalog: TJSONValue;
begin
  if TAtlasStrings.Language = TAtlasLanguage.English then
  begin
    Result := RunCommand(TAtlasProjectSettings.cCatalogCommand, '["en"]');
  end
  else
  begin
    Result := RunCommand(TAtlasProjectSettings.cCatalogCommand, '["de"]');
  end;
end;

function TAtlasSettingsFileEdit.DprojChoices(const APath: string): TArray<TAtlasSettingChoice>;
begin
  Result := nil;
  if APath = 'config' then
  begin
    Result := TAtlasSettingChoices.FromTexts(TAtlasSettingChoices.DprojConfigs(FDprojText));
  end
  else if APath = 'platform' then
  begin
    Result := TAtlasSettingChoices.FromTexts(TAtlasSettingChoices.DprojPlatforms(FDprojText));
  end
  else if (APath = 'project') and (FProject <> '') and not FGlobal then
  begin
    Result := TAtlasSettingChoices.FromTexts([ExtractRelativePath(IncludeTrailingPathDelimiter(
      ExtractFileDir(FFileName)), FProject)]);
  end;
end;

function TAtlasSettingsFileEdit.Choices(const APath: string): TArray<TAtlasSettingChoice>;
var
  mProfiles: Integer;
begin
  Result := nil;
  if APath = 'delphiVersion' then
  begin
    Result := TAtlasSettingChoices.DelphiVersions(TAtlasProjectSettings.InstalledVersions);
  end
  else if APath = 'minDelphiVersion' then
  begin
    Result := TAtlasSettingChoices.DelphiVersions(TAtlasSettingChoices.KnownVersions);
  end
  else if (APath = 'profile') or (APath = 'testProfile') then
  begin
    mProfiles := FModel.IndexOf('profiles');
    if mProfiles >= 0 then
    begin
      Result := TAtlasSettingChoices.FromTexts(TAtlasSettingChoices.Profiles(FModel.Effective(mProfiles)));
    end;
  end
  else
  begin
    Result := DprojChoices(APath);
  end;
end;

function TAtlasSettingsFileEdit.Validate(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>;
var
  mAnswer: TJSONValue;
  mValid: Boolean;
begin
  // Der Server meldet auch Schlüssel am falschen Ort (#227).
  mAnswer := RunCommand(TAtlasProjectSettings.cCheckCommand, '[' + TAtlasJsonText.Quote(AText) + FCheckScope + ']');
  try
    AChecked := TAtlasSettingsValidation.FromAnswer(mAnswer, Result, mValid);
  finally
    mAnswer.Free;
  end;
  if not AChecked then
  begin
    TAtlasSettingsValidation.Syntax(AText, Result);
  end;
end;

procedure TAtlasSettingsFileEdit.Prepare(ADialog: TAtlasProjectSettingsDialog);
var
  mTarget: TAtlasBuildTarget;
begin
  ADialog.Catalog := FCatalog;
  ADialog.ServerChecks := FCatalog <> nil;
  if FRuleId <> '' then
  begin
    ADialog.SelectRule(FRuleId);
  end;
  if FGlobal then
  begin
    Exit;
  end;
  ADialog.ProjectHint := ExtractFileName(FProject);
  // Die IDE sendet ihre Auswahl laufend an den Server (selectBuild, #46, #615).
  if TAtlasIdeBuildTarget.Read(mTarget) then
  begin
    ADialog.BuildHint := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.ProjectSettingsBuildOverride,
      [mTarget.Config, mTarget.Platform]);
  end;
end;

function TAtlasSettingsFileEdit.ShowDialog: Boolean;
var
  mDialog: TAtlasProjectSettingsDialog;
begin
  mDialog := DialogClass.CreateDialog(nil, FModel, FFileName);
  try
    Prepare(mDialog);
    mDialog.OnChoices :=
      function(const APath: string): TArray<TAtlasSettingChoice>
      begin
        Result := Choices(APath);
      end;
    mDialog.OnValidate :=
      function(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>
      begin
        Result := Validate(AText, AChecked);
      end;
    mDialog.OnOpenFile :=
      procedure
      begin
        FOpenFile := True;
      end;
    Result := mDialog.ShowModal = mrOk;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasSettingsFileEdit.Save;
begin
  FContent.Text := FModel.ResultText;
  ForceDirectories(ExtractFileDir(FFileName));
  TAtlasTextFile.Save(FFileName, FContent);
end;

procedure TAtlasSettingsFileEdit.OpenIfAsked;
var
  mActions: IOTAActionServices;
begin
  if not FOpenFile or not Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    Exit;
  end;
  if not TFile.Exists(FFileName) then
  begin
    ForceDirectories(ExtractFileDir(FFileName));
    TFile.WriteAllBytes(FFileName, TEncoding.UTF8.GetBytes('{' + sLineBreak + '}' + sLineBreak));
  end;
  mActions.OpenFile(FFileName);
end;

procedure TAtlasSettingsFileEdit.Run;
begin
  if not ContentValid then
  begin
    Exit;
  end;
  FProject := TAtlasIdeFiles.ActiveProjectFile;
  FDprojText := '';
  if SameText(ExtractFileExt(FProject), '.dproj') and TFile.Exists(FProject) then
  begin
    FDprojText := LoadContent(FProject).Text;
  end;
  FCatalog := LoadCatalog;
  FModel := TAtlasSettingsModel.Create(Fields, FContent.Text, '', FGlobal);
  if ShowDialog and FModel.Modified then
  begin
    Save;
  end;
  OpenIfAsked;
end;

class procedure TAtlasProjectSettings.ExecuteFile(const AFileName: string; AGlobal: Boolean;
  const ARuleId: string);
var
  mEdit: TAtlasSettingsFileEdit;
begin
  mEdit := TAtlasSettingsFileEdit.Create(AFileName, AGlobal, ARuleId);
  try
    mEdit.Run;
  finally
    mEdit.Free;
  end;
end;

end.
