unit Atlas.IDE.Settings.Transfer;

// Einstellungen exportieren, importieren und zurücksetzen in der IDE (#723):
// Dateidialoge, Sicherung vor dem Import, Projektwerte des aktiven Projekts
// für die Vorschau, Speichern (settings.json, dann Registry über
// TAtlasIdeSettings.Update) und die Befehle der Befehlspalette
// Atlas.SettingsExport, Atlas.SettingsImport, Atlas.SettingsProfile und
// Atlas.SettingsReset (sichtbar mit settings.exportImport). Die Optionsseite
// ruft dieselben Wege mit ihren ungespeicherten Werten auf.
// - Sicherung: %APPDATA%\Atlas\Backups\atlas-settings-JJJJMMTT-HHMMSS.json,
//   alles unverändert (auch Zustände und Rechnerwerte), die zehn neuesten
//   bleiben (settings.backupBeforeImport).
// - Eingebaute Profile kommen aus dem Plugin selbst (ProfileData, gleich den
//   Dateien unter Setup\Profile).

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Transfer;

type
  TAtlasIdeSettingsTransfer = class
  private class var
    FCatalog: TAtlasSettingsCatalog;
  private
    class function State(const ASettings: TAtlasPluginSettings): TAtlasSettingsState; static;
    class function BackupFolder: string; static;
    class procedure ProjectTexts(out AProject, ATeam: string); static;
    class function Save(const AState: TAtlasSettingsState): Boolean; static;
    class procedure Inform(const AText: string); static;
    class function Import(const ACurrent: TAtlasPluginSettings; const AText, AFileName: string;
      out AResult: TAtlasPluginSettings): Boolean; static;
    class function ChooseProfile(out AText, AFileName: string): Boolean; static;
    class function ChooseFile(out AText, AFileName: string): Boolean; static;
  public
    /// <summary>Katalog aus den eingebauten Schemata; lebt bis Release.</summary>
    class function Catalog: TAtlasSettingsCatalog; static;
    /// <summary>Benutzerordner und -name aus der Umgebung für Pfadmakros.</summary>
    class function Macros: TAtlasSettingsEnvironment; static;
    /// <summary>Befehle sichtbar (settings.exportImport).</summary>
    class function Visible: Boolean; static;
    /// <summary>Sichert ACurrent samt settings.json; AFileName = Datei der Sicherung.</summary>
    class function Backup(const ACurrent: TAtlasPluginSettings; out AFileName: string): Boolean; static;
    /// <summary>Export mit Auswahl der Bereiche und Speichern-Dialog.</summary>
    class procedure ExportSettings(const ACurrent: TAtlasPluginSettings); static;
    /// <summary>Import aus Datei oder eingebautem Profil (AProfile) mit Vorschau; gespeichert, wenn True.</summary>
    class function ImportSettings(const ACurrent: TAtlasPluginSettings; AProfile: Boolean;
      out AResult: TAtlasPluginSettings): Boolean; static;
    /// <summary>Alles zurücksetzen mit Rückfrage und Sicherung; gespeichert, wenn True.</summary>
    class function ResetAll(const ACurrent: TAtlasPluginSettings; out AResult: TAtlasPluginSettings): Boolean; static;
    /// <summary>Befehle der Befehlspalette (gespeicherte Werte).</summary>
    class procedure ExportCommand; static;
    class procedure ImportCommand; static;
    class procedure ProfileCommand; static;
    class procedure ResetCommand; static;
    /// <summary>Beim Entladen.</summary>
    class procedure Release; static;
  end;

implementation

uses
  System.IOUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Forms,
  Atlas.Core.Settings.ProfileData,
  Atlas.Core.Projects.Setup,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Transfer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  try
    if FileExists(AFileName) then
    begin
      AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
      Result := True;
    end;
  except
    on Exception do
      Result := False;
  end;
end;

/// <summary>UTF-8 ohne BOM, Zeilenende CRLF.</summary>
procedure WriteText(const AFileName, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, StringReplace(AText, #10, #13#10, [rfReplaceAll]), TEncoding.GetEncoding(65001));
end;

{ TAtlasIdeSettingsTransfer }

class function TAtlasIdeSettingsTransfer.Catalog: TAtlasSettingsCatalog;
begin
  if FCatalog = nil then
    FCatalog := TAtlasSettingsCatalog.CreateDefault;
  Result := FCatalog;
end;

class procedure TAtlasIdeSettingsTransfer.Release;
begin
  FreeAndNil(FCatalog);
end;

class function TAtlasIdeSettingsTransfer.Macros: TAtlasSettingsEnvironment;
begin
  Result :=
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end;
end;

class function TAtlasIdeSettingsTransfer.Visible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.SettingsExportImport;
end;

class function TAtlasIdeSettingsTransfer.State(const ASettings: TAtlasPluginSettings): TAtlasSettingsState;
begin
  Result := TAtlasSettingsState.Create(ASettings, TAtlasIdeSettings.GlobalText);
end;

class function TAtlasIdeSettingsTransfer.BackupFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'Backups');
end;

class procedure TAtlasIdeSettingsTransfer.Inform(const AText: string);
begin
  MessageDlg(AText, TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK], 0);
end;

class procedure TAtlasIdeSettingsTransfer.ProjectTexts(out AProject, ATeam: string);
var
  Project, FileName: string;
begin
  AProject := '';
  ATeam := '';
  Project := TAtlasIdeTeamFile.ActiveProject;
  if Project = '' then
    Exit;
  FileName := TAtlasProjectSetups.ExistingConfig(Project,
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end);
  if FileName <> '' then
    ReadText(FileName, AProject);
  FileName := TAtlasIdeTeamFile.LocateFor(Project);
  if FileName <> '' then
    ReadText(FileName, ATeam);
end;

class function TAtlasIdeSettingsTransfer.Save(const AState: TAtlasSettingsState): Boolean;
begin
  // Erst settings.json (globale Schlüssel), dann Update: das schreibt die Registry und die umgeleiteten Werte
  // in dieselbe Datei.
  Result := TAtlasIdeSettings.SaveGlobalText(AState.GlobalText);
  TAtlasIdeSettings.Update(AState.Plugin);
end;

class function TAtlasIdeSettingsTransfer.Backup(const ACurrent: TAtlasPluginSettings; out AFileName: string): Boolean;
var
  Export_: TAtlasExportResult;
  Old: string;
  Files: TArray<string>;
begin
  AFileName := '';
  Result := False;
  try
    Export_ := TAtlasSettingsTransfer.ExportSettings(Catalog, State(ACurrent), TAtlasExportOptions.ForBackup, Macros());
    AFileName := TPath.Combine(BackupFolder, TAtlasSettingsTransfer.BackupFileName(Now));
    WriteText(AFileName, Export_.Text);
    Result := True;
    // Ältere Sicherungen aufräumen.
    Files := nil;
    for Old in TDirectory.GetFiles(BackupFolder, TAtlasSettingsTransfer.BackupPrefix + '*.json') do
      Files := Files + [ExtractFileName(Old)];
    for Old in TAtlasSettingsTransfer.BackupsToDelete(Files, TAtlasSettingsTransfer.KeepBackups) do
      System.SysUtils.DeleteFile(TPath.Combine(BackupFolder, Old));
  except
    on E: Exception do
      // Scheitert nur das Aufräumen, gilt die Sicherung trotzdem.
      if not Result then
        MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.SettingsTransferFailed, [E.Message]), TMsgDlgType.mtError,
          [TMsgDlgBtn.mbOK], 0);
  end;
end;

class procedure TAtlasIdeSettingsTransfer.ExportSettings(const ACurrent: TAtlasPluginSettings);
var
  Options: TAtlasExportOptions;
  Dialog: TSaveDialog;
  Export_: TAtlasExportResult;
  Message, Keys: string;
  Omission: TAtlasExportOmission;
begin
  Options := TAtlasExportOptions.Create(nil, smOmit);
  if ACurrent.SettingsExportSecrets = 'placeholder' then
    Options.Secrets := smPlaceholder;
  if not TAtlasExportDialog.Execute(Catalog, Options, nil) then
    Exit;
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.FileName := TAtlasSettingsTransfer.FileName;
    Dialog.DefaultExt := 'json';
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsFileFilter);
    Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not Dialog.Execute then
      Exit;
    try
      Export_ := TAtlasSettingsTransfer.ExportSettings(Catalog, State(ACurrent), Options, Macros());
      WriteText(Dialog.FileName, Export_.Text);
    except
      on E: Exception do
      begin
        MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.SettingsTransferFailed, [E.Message]), TMsgDlgType.mtError,
          [TMsgDlgBtn.mbOK], 0);
        Exit;
      end;
    end;
    Message := TAtlasStrings.Fmt(TAtlasTextId.SettingsExportDone, [Export_.Count, Dialog.FileName]);
    if Length(Export_.Omitted) > 0 then
    begin
      Keys := '';
      for Omission in Export_.Omitted do
        Keys := Keys + ', ' + Omission.Key;
      Message := Message + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SettingsExportOmitted, [Copy(Keys, 3, MaxInt)]);
    end;
    if Length(Export_.Placeholders) > 0 then
      Message := Message + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SettingsExportPlaceholders,
        [string.Join(', ', Export_.Placeholders)]);
    Inform(Message);
  finally
    Dialog.Free;
  end;
end;

class function TAtlasIdeSettingsTransfer.ChooseFile(out AText, AFileName: string): Boolean;
var
  Dialog: TOpenDialog;
begin
  AText := '';
  AFileName := '';
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.FileName := TAtlasSettingsTransfer.FileName;
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsFileFilter);
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    Result := Dialog.Execute and ReadText(Dialog.FileName, AText);
    AFileName := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

class function TAtlasIdeSettingsTransfer.ChooseProfile(out AText, AFileName: string): Boolean;
var
  Files, Names, Descriptions: TArray<string>;
  Source: TAtlasSettingsFile;
  Name: string;
  Index: Integer;
begin
  AText := '';
  AFileName := '';
  Files := AtlasProfileFiles;
  Names := nil;
  Descriptions := nil;
  for Name in Files do
  begin
    Source := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson(Name));
    if (TAtlasStrings.Language = TAtlasLanguage.English) and (Source.NameEn <> '') then
    begin
      Names := Names + [Source.NameEn];
      Descriptions := Descriptions + [Source.DescriptionEn];
    end
    else
    begin
      Names := Names + [Source.Name];
      Descriptions := Descriptions + [Source.Description];
    end;
  end;
  // Letzter Eintrag: eigene Datei.
  Names := Names + [TAtlasStrings.Text(TAtlasTextId.SettingsProfileFromFile)];
  Descriptions := Descriptions + [''];
  Result := TAtlasProfileDialog.Choose(Names, Descriptions, Index, nil);
  if not Result then
    Exit;
  if Index > High(Files) then
    Exit(ChooseFile(AText, AFileName));
  AFileName := Files[Index];
  AText := AtlasProfileJson(AFileName);
end;

class function TAtlasIdeSettingsTransfer.Import(const ACurrent: TAtlasPluginSettings; const AText, AFileName: string;
  out AResult: TAtlasPluginSettings): Boolean;
var
  Source: TAtlasSettingsFile;
  Current: TAtlasSettingsState;
  Preview: TAtlasImportPreview;
  ProjectText, TeamText, BackupFile, Message: string;
  Next: TAtlasSettingsState;
  Count: Integer;
begin
  AResult := ACurrent;
  Result := False;
  Source := TAtlasSettingsTransfer.ParseFile(AText);
  if not Source.Valid then
  begin
    MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.SettingsImportInvalidFile, [ExtractFileName(AFileName), Source.Error]),
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;
  Current := State(ACurrent);
  ProjectTexts(ProjectText, TeamText);
  Preview := TAtlasSettingsTransfer.Preview(Catalog, Current, Source, TAtlasSettingsTransfer.ModeOf(Source), nil,
    Macros(), ProjectText, TeamText);
  if not TAtlasImportDialog.Execute(Catalog, AFileName, Preview,
    function(AMode: TAtlasImportMode; const AAreas: TArray<string>): TAtlasImportPreview
    begin
      Result := TAtlasSettingsTransfer.Preview(Catalog, Current, Source, AMode, AAreas, Macros(), ProjectText, TeamText);
    end, nil) then
    Exit;
  Count := Preview.SelectedCount;
  if Count = 0 then
  begin
    Inform(TAtlasStrings.Text(TAtlasTextId.SettingsImportNothing));
    Exit;
  end;
  // Vor jedem Import sichern (settings.backupBeforeImport); ohne Sicherung kein Import.
  BackupFile := '';
  if ACurrent.SettingsBackupBeforeImport and not Backup(ACurrent, BackupFile) then
    Exit;
  Next := TAtlasSettingsTransfer.Apply(Catalog, Current, Preview);
  Save(Next);
  AResult := TAtlasIdeSettings.Stored;
  Result := True;
  Message := TAtlasStrings.Fmt(TAtlasTextId.SettingsImportDone, [Count]);
  if BackupFile <> '' then
    Message := Message + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SettingsBackupDone, [BackupFile]);
  Inform(Message);
end;

class function TAtlasIdeSettingsTransfer.ImportSettings(const ACurrent: TAtlasPluginSettings; AProfile: Boolean;
  out AResult: TAtlasPluginSettings): Boolean;
var
  Text, FileName: string;
  Chosen: Boolean;
begin
  AResult := ACurrent;
  if AProfile then
    Chosen := ChooseProfile(Text, FileName)
  else
    Chosen := ChooseFile(Text, FileName);
  Result := Chosen and Import(ACurrent, Text, FileName, AResult);
end;

class function TAtlasIdeSettingsTransfer.ResetAll(const ACurrent: TAtlasPluginSettings;
  out AResult: TAtlasPluginSettings): Boolean;
var
  BackupFile, Message: string;
begin
  AResult := ACurrent;
  Result := False;
  if MessageDlg(TAtlasStrings.Text(TAtlasTextId.SettingsResetAllConfirm), TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0, TMsgDlgBtn.mbNo) <> mrYes then
    Exit;
  BackupFile := '';
  if ACurrent.SettingsBackupBeforeImport and not Backup(ACurrent, BackupFile) then
    Exit;
  Save(TAtlasSettingsTransfer.ResetAll(Catalog, State(ACurrent)));
  AResult := TAtlasIdeSettings.Stored;
  Result := True;
  Message := TAtlasStrings.Text(TAtlasTextId.SettingsResetAllDone);
  if BackupFile <> '' then
    Message := Message + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SettingsBackupDone, [BackupFile]);
  Inform(Message);
end;

class procedure TAtlasIdeSettingsTransfer.ExportCommand;
begin
  ExportSettings(TAtlasIdeSettings.Stored);
end;

class procedure TAtlasIdeSettingsTransfer.ImportCommand;
var
  Imported: TAtlasPluginSettings;
begin
  ImportSettings(TAtlasIdeSettings.Stored, False, Imported);
end;

class procedure TAtlasIdeSettingsTransfer.ProfileCommand;
var
  Imported: TAtlasPluginSettings;
begin
  ImportSettings(TAtlasIdeSettings.Stored, True, Imported);
end;

class procedure TAtlasIdeSettingsTransfer.ResetCommand;
var
  Reset: TAtlasPluginSettings;
begin
  ResetAll(TAtlasIdeSettings.Stored, Reset);
end;

end.
