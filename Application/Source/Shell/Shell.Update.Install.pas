unit Shell.Update.Install;

// Host-Rolle Shell von AtlasUpdate.exe (#1519), Befehl install: Erstinstallation
// aus dem entpackten Release-Paket im Dialog auf der Konsole.
// 1. IDE und Profil wählen (alle installierten Delphi-Versionen, eigene
//    Profile aus bds -r, klassische oder 64-Bit-IDE).
// 2. Zielordner wählen; vorgeschlagen ist %LOCALAPPDATA%\Programs\Atlas,
//    weil dort keine Adminrechte nötig sind.
// 3. Hat das Paket keine BPLs für die gewählte IDE (Delphi 12), wird die
//    eigene Version aus dem Quelltext gebaut wie beim Update.
// 4. Module wählen, dann tauschen wie apply (mit Rückfall).
// Was schon als Argument kommt (--ide, --platform, --registry-key, --target,
// --select), wird nicht erfragt.

interface

uses
  Atlas.Text.UpdateRun;

type
  TShellUpdateInstall = class
  public
    class function Run(const AArgs: TUpdateArguments): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Updates,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Product.Version,
  Atlas.Common.Updates.Contract,
  Atlas.Common.Updates.Ides,
  Atlas.Common.Updates.Prepare,
  Atlas.Common.Updates.Apply,
  Atlas.Common.Updates.Selection,
  Shell.Update.System;

type
{$SCOPEDENUMS ON}
  TInstallText = (Welcome, NotUnpacked, NoIde, ChooseIde, Ide32, Ide64, Target, Building, Modules, AllModules,
    Module, CloseIde, NotWritable, Installed, Failed, PressEnter);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TInstallText] of TAtlasText = (
    (De: 'Atlas %s installieren'; En: 'Install Atlas %s'),
    (De: 'Bitte das Release-Paket ganz entpacken und AtlasUpdate.exe aus diesem Ordner starten.';
    En: 'Please unpack the whole release package and run AtlasUpdate.exe from that folder.'),
    (De: 'Keine unterstützte Delphi-Version gefunden (Delphi 12 oder 13).';
    En: 'No supported Delphi version found (Delphi 12 or 13).'),
    (De: 'Nummer der IDE: '; En: 'Number of the IDE: '),
    (De: 'klassische IDE'; En: 'classic IDE'),
    (De: '64-Bit-IDE'; En: '64-bit IDE'),
    (De: 'Zielordner [%s]: '; En: 'Target folder [%s]: '),
    (De: 'Das Paket enthält keine Packages für diese IDE; sie werden aus dem Quelltext gebaut.';
    En: 'The package has no packages for this IDE; they are built from source.'),
    (De: 'Module:'; En: 'Modules:'),
    (De: 'Alle Module installieren? [J/n] '; En: 'Install all modules? [Y/n] '),
    (De: '  %s installieren? [J/n] '; En: '  Install %s? [Y/n] '),
    (De: 'Bitte Delphi schließen und dann die Eingabetaste drücken.'; En: 'Please close Delphi, then press Enter.'),
    (De: 'In %s darf AtlasUpdate nicht schreiben. Bitte einen Ordner im Benutzerprofil wählen.';
    En: 'AtlasUpdate may not write to %s. Please choose a folder in your user profile.'),
    (De: 'Atlas %s ist installiert. Beim nächsten Start lädt Delphi die Packages.';
    En: 'Atlas %s is installed. Delphi loads the packages on its next start.'),
    (De: 'Installation nicht abgeschlossen (%s %s); nichts wurde geändert.';
    En: 'Installation not completed (%s %s); nothing was changed.'),
    (De: 'Eingabetaste schließt das Fenster.'; En: 'Press Enter to close this window.'));

function Ask(const APrompt: string): string;
begin
  Write(ErrOutput, APrompt);
  Readln(Result);
  Result := Result.Trim;
end;

function Agrees(const APrompt: string): Boolean;
var
  mAnswer: string;
begin
  mAnswer := LowerCase(Ask(APrompt));
  Result := (mAnswer = '') or (mAnswer = 'j') or (mAnswer = 'y') or (mAnswer = 'ja') or (mAnswer = 'yes');
end;

function PlatformCaption(const APlatform: string): string;
begin
  if SameText(APlatform, TUpdateIdes.cWin64) then
  begin
    Result := cTexts[TInstallText.Ide64].Text;
  end
  else
  begin
    Result := cTexts[TInstallText.Ide32].Text;
  end;
end;

/// <summary>IDE aus den Argumenten oder im Dialog; False ohne passende IDE.</summary>
function ChooseIde(const ASystem: TUpdateSystem; var AArgs: TUpdateArguments): Boolean;
var
  mChoices: TArray<TUpdateIdeChoice>;
  mIndex, mNumber: Integer;
begin
  if (AArgs.Ide <> '') and (AArgs.Platform <> '') and (AArgs.RegistryKey <> '') then
  begin
    Exit(True);
  end;
  mChoices := TUpdateIdes.Choices(ASystem.Registry, ASystem.Files);
  if Length(mChoices) = 0 then
  begin
    TShellUpdateSystem.Say(cTexts[TInstallText.NoIde].Text);
    Exit(False);
  end;
  for mIndex := 0 to High(mChoices) do
  begin
    TShellUpdateSystem.Say(Format('  %d) %s, %s', [mIndex + 1, mChoices[mIndex].Caption,
      PlatformCaption(mChoices[mIndex].Platform)]));
  end;
  mNumber := 1;
  if Length(mChoices) > 1 then
  begin
    mNumber := StrToIntDef(Ask(cTexts[TInstallText.ChooseIde].Text), 0);
  end;
  Result := (mNumber >= 1) and (mNumber <= Length(mChoices));
  if Result then
  begin
    AArgs.Ide := mChoices[mNumber - 1].CompilerVersion;
    AArgs.Platform := mChoices[mNumber - 1].Platform;
    AArgs.RegistryKey := mChoices[mNumber - 1].Profile.RegistryKey;
  end;
end;

function ChooseTarget(const ATarget: string): string;
var
  mDefault: string;
begin
  if ATarget <> '' then
  begin
    Exit(ATarget);
  end;
  mDefault := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'Programs\Atlas';
  Result := Ask(cTexts[TInstallText.Target].Fmt([mDefault]));
  if Result = '' then
  begin
    Result := mDefault;
  end;
end;

function ChooseModules(const ACandidates: TArray<TUpdateCandidate>): TArray<string>;
var
  mCandidate: TUpdateCandidate;
begin
  Result := nil;
  TShellUpdateSystem.Say(cTexts[TInstallText.Modules].Text);
  for mCandidate in ACandidates do
  begin
    TShellUpdateSystem.Say('  ' + mCandidate.Name);
  end;
  // Alle heißt alle, auch früher abgewählte Module im Zielordner.
  if Agrees(cTexts[TInstallText.AllModules].Text) then
  begin
    for mCandidate in ACandidates do
    begin
      Result := Result + [mCandidate.Name];
    end;
    Exit;
  end;
  for mCandidate in ACandidates do
  begin
    if mCandidate.Required or Agrees(cTexts[TInstallText.Module].Fmt([mCandidate.Name])) then
    begin
      Result := Result + [mCandidate.Name];
    end;
  end;
end;

/// <summary>Ordner mit dem neuen Aufbau: das entpackte Paket oder, ohne BPLs für die IDE, der gebaute Stand im
/// Staging-Ordner; '' bei Fehler.</summary>
function FilesFor(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments): string;
var
  mArgs: TUpdateArguments;
  mPreparation: TUpdatePreparation;
begin
  Result := ExtractFileDir(ParamStr(0));
  if ASystem.Files.FileExists(TUpdateLayout.Join(TUpdateLayout.Join(Result, AArgs.Platform),
    TUpdateVersions.BasePackage + TUpdateIdes.PackageSuffix(AArgs.Ide) + '.bpl')) then
  begin
    Exit;
  end;
  TShellUpdateSystem.Say(cTexts[TInstallText.Building].Text);
  mArgs := AArgs;
  mArgs.Command := 'prepare';
  mArgs.Version := TProductVersion.cVersion;
  if mArgs.ManifestUrl = '' then
  begin
    // Die eigene Version steht nur in der Versionsdatei ihres Kanals.
    mArgs.ManifestUrl := TUpdateChannels.UrlOf(Pos('-', mArgs.Version) > 0);
  end;
  mPreparation := TUpdatePreparation.Create(ASystem, mArgs, ParamStr(0));
  try
    Result := '';
    if mPreparation.Run = 0 then
    begin
      Result := TUpdateFolders.FilesDir(AArgs.Staging);
    end;
  finally
    mPreparation.Free;
  end;
end;

function Swap(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments; const AFilesDir: string;
  const ACandidates: TArray<TUpdateCandidate>): Integer;
var
  mInput: TUpdateApplyInput;
  mInstallation: TUpdateInstallation;
begin
  mInput := Default(TUpdateApplyInput);
  mInput.FilesDir := AFilesDir;
  mInput.WorkDir := AArgs.Staging;
  mInput.RootDir := TShellUpdateSystem.UpdatesRoot;
  mInput.Version := TProductVersion.cVersion;
  mInput.Candidates := ACandidates;
  mInstallation := TUpdateInstallation.Create(ASystem, AArgs, mInput);
  try
    Result := mInstallation.Run;
    if Result = 0 then
    begin
      TShellUpdateSystem.Say(cTexts[TInstallText.Installed].Fmt([TProductVersion.cVersion]));
    end
    else
    begin
      TShellUpdateSystem.Say(cTexts[TInstallText.Failed].Fmt([mInstallation.Outcome.Reason,
        mInstallation.Outcome.Detail]));
    end;
  finally
    mInstallation.Free;
  end;
end;

function Install(const ASystem: TUpdateSystem; var AArgs: TUpdateArguments): Integer;
var
  mFilesDir: string;
  mCandidates: TArray<TUpdateCandidate>;
begin
  if not ASystem.Files.FileExists(TUpdateLayout.Join(ExtractFileDir(ParamStr(0)), TUpdateLayout.ServerExe)) then
  begin
    TShellUpdateSystem.Say(cTexts[TInstallText.NotUnpacked].Text);
    Exit(1);
  end;
  if not ChooseIde(ASystem, AArgs) then
  begin
    Exit(1);
  end;
  AArgs.Target := ChooseTarget(AArgs.Target);
  if not ASystem.Files.CanWrite(AArgs.Target) then
  begin
    TShellUpdateSystem.Say(cTexts[TInstallText.NotWritable].Fmt([AArgs.Target]));
    Exit(1);
  end;
  mFilesDir := FilesFor(ASystem, AArgs);
  if mFilesDir = '' then
  begin
    Exit(1);
  end;
  mCandidates := TUpdateFolders.Candidates(ASystem, AArgs, mFilesDir);
  if Length(AArgs.Select) = 0 then
  begin
    AArgs.Select := ChooseModules(mCandidates);
  end;
  Ask(cTexts[TInstallText.CloseIde].Text);
  Result := Swap(ASystem, AArgs, mFilesDir, mCandidates);
end;

class function TShellUpdateInstall.Run(const AArgs: TUpdateArguments): Integer;
var
  mArgs: TUpdateArguments;
  mSystem: TUpdateSystem;
begin
  mArgs := AArgs;
  mArgs.Command := 'install';
  mArgs.Staging := TUpdateLayout.Join(TShellUpdateSystem.UpdatesRoot, 'install');
  mArgs.NewModules := TUpdateNewModules.Install;
  mSystem := TShellUpdateSystem.NewSystem(TUpdateLayout.Join(mArgs.Staging, TUpdateLayout.LogFile));
  TShellUpdateSystem.Say(cTexts[TInstallText.Welcome].Fmt([TProductVersion.cVersion]));
  try
    Result := Install(mSystem, mArgs);
  except
    on mError: EUpdateError do
    begin
      TShellUpdateSystem.Say(cTexts[TInstallText.Failed].Fmt([mError.Code, mError.Detail]));
      Result := 1;
    end;
  end;
  Ask(cTexts[TInstallText.PressEnter].Text);
end;

initialization
  TAtlasTextTables.Add('Shell.Update.Install', cTexts);

end.
