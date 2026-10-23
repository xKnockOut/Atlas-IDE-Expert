unit Setup.Core.SettingsCommand;

// Einstellungen über die Kommandozeile des Installers (#723, #495):
//   AtlasSetup.exe /exportSettings <Datei> [/areas:editor,build] [/secrets:placeholder]
//   AtlasSetup.exe /importSettings <Datei|Profil> [/replace|/merge] [/areas:…]
//   AtlasSetup.exe /resetSettings [/areas:…]
// jeweils mit /quiet ohne Meldungsfenster. Gleicher Kern wie die Optionsseite
// (Atlas.Core.Settings.Transfer): nur geänderte Werte, keine Zugangsdaten und
// Benutzerpfade, Projekt- und Teamwerte bleiben unberührt. Vor Import und
// Zurücksetzen kommt eine Sicherung nach %APPDATA%\Atlas\Backups
// (settings.backupBeforeImport). Profile: minimal, atlas-standard, alles-an,
// alles-an-experimentell (#834).
// Gelesen und geschrieben wird nur über ISetupSystem (Registry
// HKCU\Software\Atlas\IdePlugin und settings.json), darum mit einer Attrappe
// testbar. Eine laufende IDE übernimmt die Werte erst beim nächsten Start.

interface

uses
  System.SysUtils,
  Setup.Core.Contract,
  Atlas.Core.Settings.Transfer;

type
{$SCOPEDENUMS ON}
  TSetupSettingsAction = (None, ExportSettings, ImportSettings, ResetSettings);
  TSetupSettingsOutcome = (Done, Nothing, Usage, FileMissing, FileInvalid, Failed);
{$SCOPEDENUMS OFF}

  TSetupSettingsRequest = record
    Action: TSetupSettingsAction;
    /// <summary>Exportziel bzw. Importquelle; beim Import auch ein Profilname.</summary>
    FileName: string;
    /// <summary>Bereiche (/areas:); leer = alle bzw. die der Datei.</summary>
    Areas: TArray<string>;
    /// <summary>/replace bzw. /merge; ohne beides gilt der Modus der Datei.</summary>
    Replace: Boolean;
    Merge: Boolean;
    /// <summary>/secrets:placeholder statt der Einstellung settings.exportSecrets.</summary>
    Secrets: string;
    Quiet: Boolean;
    /// <summary>Unbekannter oder unvollständiger Schalter.</summary>
    Error: string;
  end;

  TSetupSettingsResult = record
    Action: TSetupSettingsAction;
    Outcome: TSetupSettingsOutcome;
    /// <summary>Geschriebene bzw. übernommene Werte.</summary>
    Count: Integer;
    FileName: string;
    BackupFile: string;
    /// <summary>Weggelassene (Export) bzw. übersprungene Schlüssel (Import).</summary>
    Skipped: TArray<string>;
    /// <summary>Fehlertext oder unbekannter Schalter.</summary>
    Detail: string;
    /// <summary>0 = erledigt oder nichts zu tun, 1 = Aufruf falsch, 2 = Datei fehlt oder ungültig,
    /// 3 = Schreiben gescheitert.</summary>
    function ExitCode: Integer;
  end;

  TSetupSettingsCommand = class
  public const
    PluginKey = 'Software\Atlas\IdePlugin';
    GlobalName = 'settings.json';
    BackupFolder = 'Backups';
  public
    /// <summary>Einer der drei Befehle steht in AArgs (ohne Programmnamen).</summary>
    class function Requested(const AArgs: TArray<string>): Boolean; static;
    class function Parse(const AArgs: TArray<string>): TSetupSettingsRequest; static;
    /// <summary>Führt ARequest aus. ARoamingDataDir = %APPDATA%\Atlas; AEnvironment liefert die Benutzerordner
    /// (APPDATA, LOCALAPPDATA, USERPROFILE, USERNAME), damit kein Benutzerpfad in die Datei kommt.</summary>
    class function Run(const ASystem: ISetupSystem; const ARequest: TSetupSettingsRequest;
      const ARoamingDataDir: string; const AEnvironment: TAtlasSettingsEnvironment;
      ANow: TDateTime): TSetupSettingsResult; static;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.ProfileData;

type
  /// <summary>Registry-Werte des Plugins über ISetupSystem.</summary>
  TSetupPluginStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FSystem: ISetupSystem;
    FNames: TArray<string>;
    function Exists(const AName: string): Boolean;
  public
    constructor Create(const ASystem: ISetupSystem);
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TSetupPluginStore }

constructor TSetupPluginStore.Create(const ASystem: ISetupSystem);
begin
  inherited Create;
  FSystem := ASystem;
  FNames := FSystem.ValueNames(TSetupSettingsCommand.PluginKey);
end;

function TSetupPluginStore.Exists(const AName: string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in FNames do
    if SameText(Name, AName) then
      Exit(True);
end;

function TSetupPluginStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  Result := FSystem.ReadInteger(TSetupSettingsCommand.PluginKey, AName, ADefault);
end;

procedure TSetupPluginStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FSystem.WriteInteger(TSetupSettingsCommand.PluginKey, AName, AValue);
end;

function TSetupPluginStore.ReadString(const AName, ADefault: string): string;
begin
  Result := ADefault;
  if Exists(AName) then
    Result := FSystem.ReadString(TSetupSettingsCommand.PluginKey, AName);
end;

procedure TSetupPluginStore.WriteString(const AName, AValue: string);
begin
  FSystem.WriteString(TSetupSettingsCommand.PluginKey, AName, AValue);
end;

{ TSetupSettingsResult }

function TSetupSettingsResult.ExitCode: Integer;
begin
  case Outcome of
    TSetupSettingsOutcome.Usage:
      Result := 1;
    TSetupSettingsOutcome.FileMissing, TSetupSettingsOutcome.FileInvalid:
      Result := 2;
    TSetupSettingsOutcome.Failed:
      Result := 3;
  else
    Result := 0;
  end;
end;

{ Hilfen }

function Join(const ADir, AName: string): string;
begin
  Result := ADir;
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
  Result := Result + AName;
end;

function SplitList(const AText: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in AText.Split([',', ';']) do
    if Part.Trim <> '' then
      Result := Result + [Part.Trim];
end;

function ActionOf(const AArg: string): TSetupSettingsAction;
begin
  Result := TSetupSettingsAction.None;
  if SameText(AArg, '/exportSettings') then
    Result := TSetupSettingsAction.ExportSettings
  else if SameText(AArg, '/importSettings') then
    Result := TSetupSettingsAction.ImportSettings
  else if SameText(AArg, '/resetSettings') then
    Result := TSetupSettingsAction.ResetSettings;
end;

function GlobalFile(const ARoamingDataDir: string): string;
begin
  Result := Join(ARoamingDataDir, TSetupSettingsCommand.GlobalName);
end;

function LoadState(const ASystem: ISetupSystem; const ARoamingDataDir: string): TAtlasSettingsState;
var
  Text: string;
  Store: IAtlasSettingsStore;
  Plugin: TAtlasPluginSettings;
begin
  Text := ASystem.ReadText(GlobalFile(ARoamingDataDir));
  Store := TAtlasRoutedSettingsStore.Create(TSetupPluginStore.Create(ASystem), Text);
  Plugin := TAtlasPluginSettings.Defaults;
  Plugin.Load(Store);
  Result := TAtlasSettingsState.Create(Plugin, Text);
end;

/// <summary>Wie TAtlasIdeSettings: erst settings.json mit den globalen Werten, darüber die umgeleiteten
/// Plugin-Werte, der Rest in die Registry.</summary>
procedure SaveState(const ASystem: ISetupSystem; const ARoamingDataDir, AOldText: string;
  const AState: TAtlasSettingsState);
var
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
  Plugin: TAtlasPluginSettings;
begin
  Plugin := AState.Plugin;
  Plugin.Normalize;
  Routed := TAtlasRoutedSettingsStore.Create(TSetupPluginStore.Create(ASystem), AState.GlobalText);
  Store := Routed;
  Plugin.Save(Store);
  if Routed.Text <> AOldText then
    ASystem.WriteText(GlobalFile(ARoamingDataDir), Routed.Text);
end;

function WithCrLf(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #10, #13#10, [rfReplaceAll]);
end;

/// <summary>Sicherung vor Import und Zurücksetzen; die zehn neuesten bleiben.</summary>
function Backup(const ASystem: ISetupSystem; ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
  const ARoamingDataDir: string; const AEnvironment: TAtlasSettingsEnvironment; ANow: TDateTime): string;
var
  Folder, Name: string;
  Exported: TAtlasExportResult;
begin
  Folder := Join(ARoamingDataDir, TSetupSettingsCommand.BackupFolder);
  Exported := TAtlasSettingsTransfer.ExportSettings(ACatalog, AState, TAtlasExportOptions.ForBackup, AEnvironment);
  Result := Join(Folder, TAtlasSettingsTransfer.BackupFileName(ANow));
  ASystem.WriteText(Result, WithCrLf(Exported.Text));
  for Name in TAtlasSettingsTransfer.BackupsToDelete(ASystem.FilesIn(Folder), TAtlasSettingsTransfer.KeepBackups) do
    ASystem.DeleteFile(Join(Folder, Name));
end;

/// <summary>Profilname ohne Pfad und Endung (minimal, atlas-standard, alles-an, alles-an-experimentell) → Inhalt; sonst ''.</summary>
function ProfileText(const AName: string): string;
var
  FileName: string;
begin
  Result := '';
  if (AName = '') or (Pos('\', AName) > 0) or (Pos('/', AName) > 0) or (Pos('.', AName) > 0) then
    Exit;
  for FileName in AtlasProfileFiles do
    if SameText(FileName, AName + '.json') then
      Exit(AtlasProfileJson(FileName));
end;

{ TSetupSettingsCommand }

class function TSetupSettingsCommand.Requested(const AArgs: TArray<string>): Boolean;
var
  Arg: string;
begin
  Result := False;
  for Arg in AArgs do
    if ActionOf(Arg) <> TSetupSettingsAction.None then
      Exit(True);
end;

class function TSetupSettingsCommand.Parse(const AArgs: TArray<string>): TSetupSettingsRequest;
var
  Index: Integer;
  Arg, Lower: string;
  Action: TSetupSettingsAction;
begin
  Result := Default(TSetupSettingsRequest);
  Index := 0;
  while Index <= High(AArgs) do
  begin
    Arg := AArgs[Index];
    Lower := LowerCase(Arg);
    Action := ActionOf(Arg);
    if Action <> TSetupSettingsAction.None then
    begin
      if Result.Action <> TSetupSettingsAction.None then
        Result.Error := Arg
      else
        Result.Action := Action;
      // Export und Import erwarten die Datei als nächstes Argument.
      if Action <> TSetupSettingsAction.ResetSettings then
      begin
        if (Index < High(AArgs)) and not AArgs[Index + 1].StartsWith('/') then
        begin
          Inc(Index);
          Result.FileName := AArgs[Index];
        end
        else if Result.Error = '' then
          Result.Error := Arg;
      end;
    end
    else if Lower.StartsWith('/areas:') then
      Result.Areas := SplitList(Arg.Substring(Length('/areas:')))
    else if Lower.StartsWith('/secrets:') then
    begin
      Result.Secrets := LowerCase(Arg.Substring(Length('/secrets:')));
      if (Result.Secrets <> 'omit') and (Result.Secrets <> 'placeholder') and (Result.Error = '') then
        Result.Error := Arg;
    end
    else if Lower = '/replace' then
      Result.Replace := True
    else if Lower = '/merge' then
      Result.Merge := True
    else if Lower = '/quiet' then
      Result.Quiet := True
    else if Result.Error = '' then
      Result.Error := Arg;
    Inc(Index);
  end;
  if Result.Replace and Result.Merge and (Result.Error = '') then
    Result.Error := '/replace /merge';
end;

class function TSetupSettingsCommand.Run(const ASystem: ISetupSystem; const ARequest: TSetupSettingsRequest;
  const ARoamingDataDir: string; const AEnvironment: TAtlasSettingsEnvironment;
  ANow: TDateTime): TSetupSettingsResult;
var
  Catalog: TAtlasSettingsCatalog;
  State, Next: TAtlasSettingsState;
  Area, Text: string;
  Options: TAtlasExportOptions;
  Exported: TAtlasExportResult;
  Omission: TAtlasExportOmission;
  Source: TAtlasSettingsFile;
  Mode: TAtlasImportMode;
  Preview: TAtlasImportPreview;
  Item: TAtlasImportItem;
begin
  Result := Default(TSetupSettingsResult);
  Result.Action := ARequest.Action;
  Result.FileName := ARequest.FileName;
  if (ARequest.Action = TSetupSettingsAction.None) or (ARequest.Error <> '') then
  begin
    Result.Outcome := TSetupSettingsOutcome.Usage;
    Result.Detail := ARequest.Error;
    Exit;
  end;
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    for Area in ARequest.Areas do
      if not Catalog.HasArea(Area) then
      begin
        Result.Outcome := TSetupSettingsOutcome.Usage;
        Result.Detail := '/areas:' + Area;
        Exit;
      end;
    try
      State := LoadState(ASystem, ARoamingDataDir);
      case ARequest.Action of
        TSetupSettingsAction.ExportSettings:
          begin
            Options := TAtlasExportOptions.Create(ARequest.Areas, smOmit);
            if (ARequest.Secrets = 'placeholder') or
              ((ARequest.Secrets = '') and (State.Plugin.SettingsExportSecrets = 'placeholder')) then
              Options.Secrets := smPlaceholder;
            Exported := TAtlasSettingsTransfer.ExportSettings(Catalog, State, Options, AEnvironment);
            ASystem.WriteText(ARequest.FileName, WithCrLf(Exported.Text));
            Result.Count := Exported.Count;
            for Omission in Exported.Omitted do
              Result.Skipped := Result.Skipped + [Omission.Key];
            Result.Outcome := TSetupSettingsOutcome.Done;
          end;
        TSetupSettingsAction.ImportSettings:
          begin
            Text := ProfileText(ARequest.FileName);
            if Text = '' then
            begin
              if not ASystem.FileExists(ARequest.FileName) then
              begin
                Result.Outcome := TSetupSettingsOutcome.FileMissing;
                Exit;
              end;
              Text := ASystem.ReadText(ARequest.FileName);
            end;
            Source := TAtlasSettingsTransfer.ParseFile(Text);
            if not Source.Valid then
            begin
              Result.Outcome := TSetupSettingsOutcome.FileInvalid;
              Result.Detail := Source.Error;
              Exit;
            end;
            Mode := TAtlasSettingsTransfer.ModeOf(Source);
            if ARequest.Replace then
              Mode := imReplace;
            if ARequest.Merge then
              Mode := imMerge;
            // Ohne IDE kein aktives Projekt: Projekt- und Teamwerte bleiben ohnehin unberührt.
            Preview := TAtlasSettingsTransfer.Preview(Catalog, State, Source, Mode, ARequest.Areas, AEnvironment, '', '');
            for Item in Preview.Items do
              if Item.Status in [isUnknown, isInvalid, isSecret] then
                Result.Skipped := Result.Skipped + [Item.SourceKey];
            Result.Count := Preview.SelectedCount;
            if Result.Count = 0 then
            begin
              Result.Outcome := TSetupSettingsOutcome.Nothing;
              Exit;
            end;
            if State.Plugin.SettingsBackupBeforeImport then
              Result.BackupFile := Backup(ASystem, Catalog, State, ARoamingDataDir, AEnvironment, ANow);
            Next := TAtlasSettingsTransfer.Apply(Catalog, State, Preview);
            SaveState(ASystem, ARoamingDataDir, State.GlobalText, Next);
            Result.Outcome := TSetupSettingsOutcome.Done;
          end;
        TSetupSettingsAction.ResetSettings:
          begin
            if Length(ARequest.Areas) = 0 then
              Next := TAtlasSettingsTransfer.ResetAll(Catalog, State)
            else
              Next := TAtlasSettingsTransfer.ResetAreas(Catalog, State, ARequest.Areas);
            Result.Count := Length(TAtlasSettingsTransfer.ModifiedKeys(Catalog, State)) -
              Length(TAtlasSettingsTransfer.ModifiedKeys(Catalog, Next));
            if Result.Count = 0 then
            begin
              Result.Outcome := TSetupSettingsOutcome.Nothing;
              Exit;
            end;
            if State.Plugin.SettingsBackupBeforeImport then
              Result.BackupFile := Backup(ASystem, Catalog, State, ARoamingDataDir, AEnvironment, ANow);
            SaveState(ASystem, ARoamingDataDir, State.GlobalText, Next);
            Result.Outcome := TSetupSettingsOutcome.Done;
          end;
        TSetupSettingsAction.None: ;
      end;
    except
      on E: Exception do
      begin
        Result.Outcome := TSetupSettingsOutcome.Failed;
        Result.Detail := E.Message;
      end;
    end;
  finally
    Catalog.Free;
  end;
end;

end.
