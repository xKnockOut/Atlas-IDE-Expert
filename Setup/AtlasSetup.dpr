program AtlasSetup;

// Installer für Atlas IDE Expert (#495), eigene VCL-Anwendung (ADR 0009).
// Aufruf ohne Parameter: installieren bzw. aktualisieren.
// Aufruf mit /uninstall (aus „Apps und Features“): entfernen.
// Aufruf mit /exportSettings, /importSettings oder /resetSettings (#723):
// Einstellungen ohne Fenster übertragen (Setup.Core.SettingsCommand); Ergebnis
// als Exit-Code und, ohne /quiet, als Meldung.

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Text.Product.Version in '..\Packages\Atlas.Text\Source\Product\Atlas.Text.Product.Version.pas',
  Atlas.Core.Product.Version in '..\Packages\Atlas.IDE.Expert\Source\Core\Product\Atlas.Core.Product.Version.pas',
  Atlas.Text.Chars in '..\Packages\Atlas.Text\Source\Chars\Atlas.Text.Chars.pas',
  Atlas.Text.Lines in '..\Packages\Atlas.Text\Source\Lines\Atlas.Text.Lines.pas',
  Atlas.Text.Jsonc in '..\Packages\Atlas.Text\Source\Jsonc\Atlas.Text.Jsonc.pas',
  Atlas.Text.Checkin in '..\Packages\Atlas.Text\Source\Checkin\Atlas.Text.Checkin.pas',
  Atlas.Core.Style.Color in '..\Packages\Atlas.IDE.Expert\Source\Core\Style\Atlas.Core.Style.Color.pas',
  Atlas.Core.Style.Palette in '..\Packages\Atlas.IDE.Expert\Source\Core\Style\Atlas.Core.Style.Palette.pas',
  Atlas.Core.Generate.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Generate\Atlas.Core.Generate.Contract.pas',
  Atlas.Core.Build.Events in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.Events.pas',
  Atlas.Core.Build.OpenBuild in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.OpenBuild.pas',
  Atlas.Core.Build.ReleaseGuard in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.ReleaseGuard.pas',
  Atlas.Core.Lsp.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Lsp\Atlas.Core.Lsp.Contract.pas',
  Atlas.Core.Build.Gate in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.Gate.pas',
  Atlas.Core.Build.Messages in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.Messages.pas',
  Atlas.Core.Build.Verdict in '..\Packages\Atlas.IDE.Expert\Source\Core\Build\Atlas.Core.Build.Verdict.pas',
  Atlas.Core.Notifications.Contract in '..\Packages\Atlas.IDE.Expert\Source\Core\Notifications\Atlas.Core.Notifications.Contract.pas',
  Atlas.Core.Notifications.Sources in '..\Packages\Atlas.IDE.Expert\Source\Core\Notifications\Atlas.Core.Notifications.Sources.pas',
  Atlas.Core.Settings.JsonText in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.JsonText.pas',
  Atlas.Core.Settings.SchemaCheck in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.SchemaCheck.pas',
  Atlas.Core.Settings.SchemaData in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.SchemaData.pas',
  Atlas.Core.Settings.PluginSchemaData in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.PluginSchemaData.pas',
  Atlas.Core.Settings.ProfileData in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.ProfileData.pas',
  Atlas.Core.Settings.OverviewKinds in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.OverviewKinds.pas',
  Atlas.Core.Settings.Plugin in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.Plugin.pas',
  Atlas.Core.Settings.Scopes in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.Scopes.pas',
  Atlas.Core.Settings.History in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.History.pas',
  Atlas.Core.Settings.Catalog in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.Catalog.pas',
  Atlas.Core.Settings.Transfer in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.Transfer.pas',
  Atlas.Core.Settings.ToolbarItems in '..\Packages\Atlas.IDE.Expert\Source\Core\Settings\Atlas.Core.Settings.ToolbarItems.pas',
  Setup.Core.Contract in 'Source\Core\Setup.Core.Contract.pas',
  Setup.Core.Ides in 'Source\Core\Setup.Core.Ides.pas',
  Setup.Core.Installer in 'Source\Core\Setup.Core.Installer.pas',
  Setup.Core.SettingsCommand in 'Source\Core\Setup.Core.SettingsCommand.pas',
  Setup.Core.License in 'Source\Core\Setup.Core.License.pas',
  Setup.Adapters.WindowsSystem in 'Source\Adapters\Setup.Adapters.WindowsSystem.pas',
  Setup.Shell.Texts in 'Source\Shell\Setup.Shell.Texts.pas',
  Setup.Shell.MainForm in 'Source\Shell\Setup.Shell.MainForm.pas';

// Manifest: ohne Administratorrechte (asInvoker, sonst hielte Windows „…Setup.exe“
// für einen Installer und fragte nach Rechten) und mit Windows-Stil der Steuerelemente.
{$R 'AtlasSetup.Manifest.res' 'AtlasSetup.Manifest.rc'}
// Atlas-Symbol (#751) als Programmsymbol; der Deinstallationseintrag zeigt auf diese Exe.
{$R '..\Packages\Atlas.IDE.Expert\Resources\Symbol\Atlas.Icon.res'}

function IsUninstall: Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ParamCount do
    if SameText(ParamStr(Index), '/uninstall') then
      Result := True;
end;

function SetupPaths(const ASystem: ISetupSystem): TSetupPaths;
var
  Local: string;
begin
  Local := GetEnvironmentVariable('LOCALAPPDATA');
  Result.SourceDir := ExtractFileDir(ParamStr(0));
  // Eine frühere Installation bestimmt den Ordner, sonst je Benutzer unter Programs.
  Result.InstallDir := ASystem.ReadString(TSetupInstaller.SetupKey, 'InstallDir');
  if Result.InstallDir = '' then
    Result.InstallDir := IncludeTrailingPathDelimiter(Local) + 'Programs\Atlas';
  Result.RoamingDataDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + 'Atlas';
  Result.LocalDataDir := IncludeTrailingPathDelimiter(Local) + 'Atlas';
end;

function CommandArgs: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 1 to ParamCount do
    Result := Result + [ParamStr(Index)];
end;

/// <summary>Einstellungen über die Kommandozeile (#723); liefert den Exit-Code.</summary>
function RunSettingsCommand(const ASystem: ISetupSystem): Integer;
var
  Request: TSetupSettingsRequest;
  Outcome: TSetupSettingsResult;
  Environment: TAtlasSettingsEnvironment;
  Flags: UINT;
begin
  Request := TSetupSettingsCommand.Parse(CommandArgs);
  // Relative Pfade gelten ab dem aktuellen Ordner; ein Profilname (minimal, alles-an) bleibt, wie er ist.
  if (Request.FileName <> '') and ((Request.Action = TSetupSettingsAction.ExportSettings) or
    (LastDelimiter('.\/:', Request.FileName) > 0)) then
    Request.FileName := ExpandFileName(Request.FileName);
  Environment :=
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end;
  Outcome := TSetupSettingsCommand.Run(ASystem, Request, SetupPaths(ASystem).RoamingDataDir, Environment, Now);
  if not Request.Quiet then
  begin
    Flags := MB_OK or MB_ICONINFORMATION;
    if Outcome.ExitCode <> 0 then
      Flags := MB_OK or MB_ICONWARNING;
    MessageBox(0, PChar(TSetupTexts.SettingsMessage(Outcome)), PChar(TSetupTexts.Get(TSetupTextId.SettingsTitle)),
      Flags);
  end;
  Result := Outcome.ExitCode;
end;

var
  SetupSystem: ISetupSystem;
  MainForm: TSetupMainForm;

begin
  if (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN then
    TSetupTexts.Language := TSetupLanguage.German
  else
    TSetupTexts.Language := TSetupLanguage.English;
  SetupSystem := TSetupWindowsSystem.Create;
  if TSetupSettingsCommand.Requested(CommandArgs) then
  begin
    ExitCode := RunSettingsCommand(SetupSystem);
    Exit;
  end;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Atlas IDE Expert';
  TSetupMainForm.Configure(SetupSystem, SetupPaths(SetupSystem), TAtlasPluginVersion.Version, IsUninstall);
  Application.CreateForm(TSetupMainForm, MainForm);
  Application.Run;
end.
