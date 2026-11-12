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
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.Transfer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.Files;

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
  begin
    FCatalog := TAtlasSettingsCatalog.CreateDefault;
  end;
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
  mProject, mFileName: string;
begin
  AProject := '';
  ATeam := '';
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    Exit;
  end;
  mFileName := TAtlasProjectSetups.ExistingConfig(mProject,
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end);
  if mFileName <> '' then
  begin
    ReadText(mFileName, AProject);
  end;
  mFileName := TAtlasIdeTeamFile.LocateFor(mProject);
  if mFileName <> '' then
  begin
    ReadText(mFileName, ATeam);
  end;
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
  mExport_: TAtlasExportResult;
  mOld: string;
  mFiles: TArray<string>;
begin
  AFileName := '';
  Result := False;
  try
    mExport_ := TAtlasSettingsTransfer.ExportSettings(Catalog, State(ACurrent), TAtlasExportOptions.ForBackup,
      Macros());
    AFileName := TPath.Combine(BackupFolder, TAtlasSettingsTransfer.BackupFileName(Now));
    WriteText(AFileName, mExport_.Text);
    Result := True;
    // Ältere Sicherungen aufräumen.
    mFiles := nil;
    for mOld in TDirectory.GetFiles(BackupFolder, TAtlasSettingsTransfer.cBackupPrefix + '*.json') do
    begin
      mFiles := mFiles + [ExtractFileName(mOld)];
    end;
    for mOld in TAtlasSettingsTransfer.BackupsToDelete(mFiles, TAtlasSettingsTransfer.cKeepBackups) do
    begin
      System.SysUtils.DeleteFile(TPath.Combine(BackupFolder, mOld));
    end;
  except
    on E: Exception do
      // Scheitert nur das Aufräumen, gilt die Sicherung trotzdem.
      if not Result then
      begin
        MessageDlg(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTransferFailed, [E.Message]),
          TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
      end;
  end;
end;

class procedure TAtlasIdeSettingsTransfer.ExportSettings(const ACurrent: TAtlasPluginSettings);
var
  mOptions: TAtlasExportOptions;
  mDialog: TSaveDialog;
  mExport_: TAtlasExportResult;
  mMessage: string;
  mKeys: TArray<string>;
  mOmission: TAtlasExportOmission;
begin
  mOptions := TAtlasExportOptions.Create(nil, smOmit);
  if ACurrent.SettingsExportSecrets = 'placeholder' then
  begin
    mOptions.Secrets := smPlaceholder;
  end;
  if not TAtlasExportDialog.Execute(Catalog, mOptions, nil) then
  begin
    Exit;
  end;
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.FileName := TAtlasSettingsTransfer.cFileName;
    mDialog.DefaultExt := 'json';
    mDialog.Filter := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFileFilter);
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    try
      mExport_ := TAtlasSettingsTransfer.ExportSettings(Catalog, State(ACurrent), mOptions, Macros());
      WriteText(mDialog.FileName, mExport_.Text);
    except
      on E: Exception do
      begin
        MessageDlg(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTransferFailed, [E.Message]),
          TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
        Exit;
      end;
    end;
    mMessage := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsExportDone, [mExport_.Count, mDialog.FileName]);
    if Length(mExport_.Omitted) > 0 then
    begin
      mKeys := nil;
      for mOmission in mExport_.Omitted do
      begin
        mKeys := mKeys + [mOmission.Key];
      end;
      mMessage := mMessage + sLineBreak + TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsExportOmitted,
        [string.Join(', ', mKeys)]);
    end;
    if Length(mExport_.Placeholders) > 0 then
    begin
      mMessage := mMessage + sLineBreak + TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsExportPlaceholders,
        [string.Join(', ', mExport_.Placeholders)]);
    end;
    Inform(mMessage);
  finally
    mDialog.Free;
  end;
end;

class function TAtlasIdeSettingsTransfer.ChooseFile(out AText, AFileName: string): Boolean;
var
  mDialog: TOpenDialog;
begin
  AText := '';
  AFileName := '';
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.FileName := TAtlasSettingsTransfer.cFileName;
    mDialog.Filter := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFileFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    Result := mDialog.Execute and ReadText(mDialog.FileName, AText);
    AFileName := mDialog.FileName;
  finally
    mDialog.Free;
  end;
end;

class function TAtlasIdeSettingsTransfer.ChooseProfile(out AText, AFileName: string): Boolean;
var
  mFiles, mNames, mDescriptions: TArray<string>;
  mSource: TAtlasSettingsFile;
  mName: string;
  mIndex: Integer;
begin
  AText := '';
  AFileName := '';
  mFiles := AtlasProfileFiles;
  mNames := nil;
  mDescriptions := nil;
  for mName in mFiles do
  begin
    mSource := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson(mName));
    if (TAtlasStrings.Language = TAtlasLanguage.English) and (mSource.NameEn <> '') then
    begin
      mNames := mNames + [mSource.NameEn];
      mDescriptions := mDescriptions + [mSource.DescriptionEn];
    end
    else
    begin
      mNames := mNames + [mSource.Name];
      mDescriptions := mDescriptions + [mSource.Description];
    end;
  end;
  // Letzter Eintrag: eigene Datei.
  mNames := mNames + [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProfileFromFile)];
  mDescriptions := mDescriptions + [''];
  Result := TAtlasProfileDialog.Choose(mNames, mDescriptions, mIndex, nil);
  if not Result then
  begin
    Exit;
  end;
  if mIndex > High(mFiles) then
  begin
    Exit(ChooseFile(AText, AFileName));
  end;
  AFileName := mFiles[mIndex];
  AText := AtlasProfileJson(AFileName);
end;

class function TAtlasIdeSettingsTransfer.Import(const ACurrent: TAtlasPluginSettings; const AText, AFileName: string;
  out AResult: TAtlasPluginSettings): Boolean;
var
  mSource: TAtlasSettingsFile;
  mCurrent: TAtlasSettingsState;
  mPreview: TAtlasImportPreview;
  mProjectText, mTeamText, mBackupFile, mMessage: string;
  mNext: TAtlasSettingsState;
  mCount: Integer;
begin
  AResult := ACurrent;
  Result := False;
  mSource := TAtlasSettingsTransfer.ParseFile(AText);
  if not mSource.Valid then
  begin
    MessageDlg(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsImportInvalidFile, [ExtractFileName(AFileName),
      mSource.Error]),
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;
  mCurrent := State(ACurrent);
  ProjectTexts(mProjectText, mTeamText);
  mPreview := TAtlasSettingsTransfer.Preview(Catalog, mCurrent, mSource,
    TAtlasImportOptions.Create(TAtlasSettingsTransfer.ModeOf(mSource), nil, Macros(), mProjectText, mTeamText));
  if not TAtlasImportDialog.Execute(Catalog, AFileName, mPreview,
    function(AMode: TAtlasImportMode; const AAreas: TArray<string>): TAtlasImportPreview
    begin
      Result := TAtlasSettingsTransfer.Preview(Catalog, mCurrent, mSource, TAtlasImportOptions.Create(AMode, AAreas,
        Macros(), mProjectText, mTeamText));
    end, nil) then
  begin
    Exit;
  end;
  mCount := mPreview.SelectedCount;
  if mCount = 0 then
  begin
    Inform(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsImportNothing));
    Exit;
  end;
  // Vor jedem Import sichern (settings.backupBeforeImport); ohne Sicherung kein Import.
  mBackupFile := '';
  if ACurrent.SettingsBackupBeforeImport and not Backup(ACurrent, mBackupFile) then
  begin
    Exit;
  end;
  mNext := TAtlasSettingsTransfer.Apply(Catalog, mCurrent, mPreview);
  Save(mNext);
  AResult := TAtlasIdeSettings.Stored;
  Result := True;
  mMessage := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsImportDone, [mCount]);
  if mBackupFile <> '' then
  begin
    mMessage := mMessage + sLineBreak + TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsBackupDone,
      [mBackupFile]);
  end;
  Inform(mMessage);
end;

class function TAtlasIdeSettingsTransfer.ImportSettings(const ACurrent: TAtlasPluginSettings; AProfile: Boolean;
  out AResult: TAtlasPluginSettings): Boolean;
var
  mText, mFileName: string;
  mChosen: Boolean;
begin
  AResult := ACurrent;
  if AProfile then
  begin
    mChosen := ChooseProfile(mText, mFileName);
  end
  else
  begin
    mChosen := ChooseFile(mText, mFileName);
  end;
  Result := mChosen and Import(ACurrent, mText, mFileName, AResult);
end;

class function TAtlasIdeSettingsTransfer.ResetAll(const ACurrent: TAtlasPluginSettings;
  out AResult: TAtlasPluginSettings): Boolean;
var
  mBackupFile, mMessage: string;
begin
  AResult := ACurrent;
  Result := False;
  if MessageDlg(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsResetAllConfirm), TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0, TMsgDlgBtn.mbNo) <> mrYes then
  begin
    Exit;
  end;
  mBackupFile := '';
  if ACurrent.SettingsBackupBeforeImport and not Backup(ACurrent, mBackupFile) then
  begin
    Exit;
  end;
  Save(TAtlasSettingsTransfer.ResetAll(Catalog, State(ACurrent)));
  AResult := TAtlasIdeSettings.Stored;
  Result := True;
  mMessage := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsResetAllDone);
  if mBackupFile <> '' then
  begin
    mMessage := mMessage + sLineBreak + TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsBackupDone,
      [mBackupFile]);
  end;
  Inform(mMessage);
end;

class procedure TAtlasIdeSettingsTransfer.ExportCommand;
begin
  ExportSettings(TAtlasIdeSettings.Stored);
end;

class procedure TAtlasIdeSettingsTransfer.ImportCommand;
var
  mImported: TAtlasPluginSettings;
begin
  ImportSettings(TAtlasIdeSettings.Stored, False, mImported);
end;

class procedure TAtlasIdeSettingsTransfer.ProfileCommand;
var
  mImported: TAtlasPluginSettings;
begin
  ImportSettings(TAtlasIdeSettings.Stored, True, mImported);
end;

class procedure TAtlasIdeSettingsTransfer.ResetCommand;
var
  mReset: TAtlasPluginSettings;
begin
  ResetAll(TAtlasIdeSettings.Stored, mReset);
end;

end.
