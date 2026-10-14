program AtlasSetup;

// Installer für Atlas IDE Expert (#495), eigene VCL-Anwendung (ADR 0009).
// Aufruf ohne Parameter: installieren bzw. aktualisieren.
// Aufruf mit /uninstall (aus „Apps und Features“): entfernen.

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Product.Version in '..\Packages\Atlas.IDE.Expert\Source\Core\Product\Atlas.Core.Product.Version.pas',
  Setup.Core.Contract in 'Source\Core\Setup.Core.Contract.pas',
  Setup.Core.Ides in 'Source\Core\Setup.Core.Ides.pas',
  Setup.Core.Installer in 'Source\Core\Setup.Core.Installer.pas',
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

var
  SetupSystem: ISetupSystem;
  MainForm: TSetupMainForm;

begin
  if (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN then
    TSetupTexts.Language := TSetupLanguage.German
  else
    TSetupTexts.Language := TSetupLanguage.English;
  SetupSystem := TSetupWindowsSystem.Create;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Atlas IDE Expert';
  TSetupMainForm.Configure(SetupSystem, SetupPaths(SetupSystem), TAtlasPluginVersion.Version, IsUninstall);
  Application.CreateForm(TSetupMainForm, MainForm);
  Application.Run;
end.
