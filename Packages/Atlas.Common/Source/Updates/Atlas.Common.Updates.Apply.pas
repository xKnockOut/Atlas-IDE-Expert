unit Atlas.Common.Updates.Apply;

// Platform-Feature "Updates" (#1519), Root: Befehle apply und install von
// AtlasUpdate.exe, der eigentliche Tausch.
// 1. Auf das Ende der IDE warten (WaitPid) und auf jeden Prozess, der eine
//    BPL aus dem Atlas-Ordner geladen hat (andere IDE-Instanzen). Nur bis
//    hierhin bricht Strg+C ab, ohne dass sich etwas ändert.
// 2. Dateien tauschen (mit Sicherung): alles aus dem neuen Aufbau außer den
//    BPLs abgewählter Module; in der anderen Plattform nur BPLs, die es dort
//    schon gibt (sie gehören zu einer anderen IDE, deren Profil unberührt
//    bleibt). Abgewählte Module werden gelöscht, solange kein anderes Profil
//    sie lädt.
// 3. Known Packages des Profils anpassen, dann die Prüfsummen der
//    getauschten Dateien vergleichen.
// 4. Bei jedem Fehler Dateien und Registry zurücknehmen (rolledBack); bei
//    Erfolg Abgelehntes merken und das Ergebnis in result.json schreiben.

interface

uses
  System.SysUtils,
  Atlas.Text.UpdateRun,
  Atlas.Common.Updates.Contract,
  Atlas.Common.Updates.KnownPackages,
  Atlas.Common.Updates.FileSwap;

type
  TUpdateApplyInput = record
    /// <summary>Neuer Aufbau des Atlas-Ordners (Staging\files bzw. entpacktes Paket).</summary>
    FilesDir: string;
    /// <summary>Ordner für Sicherung, Protokoll und Ergebnis (Staging bzw. Updates-Root).</summary>
    WorkDir: string;
    /// <summary>Updates-Root für result.json und declined.txt.</summary>
    RootDir: string;
    Version: string;
    Previous: string;
    Candidates: TArray<TUpdateCandidate>;
  end;

  TUpdateInstallation = class
  private
    FSystem: TUpdateSystem;
    FArgs: TUpdateArguments;
    FInput: TUpdateApplyInput;
    FOutcome: TUpdateOutcome;
    FSelected: TArray<string>;
    FSwapping: Boolean;
    FChanges: TArray<TUpdateRegistryChange>;
    function PackageTarget: TUpdatePackageTarget;
    function WaitForIde: Boolean;
    function WantsFile(const APath: string): Boolean;
    procedure CopyFiles(ASwap: TUpdateFileSwap);
    procedure RemoveDeselected(ASwap: TUpdateFileSwap);
    procedure Verify(ASwap: TUpdateFileSwap);
    procedure Swap;
    procedure Finish;
    procedure WriteOutcome;
    procedure Fail(const ACode, ADetail: string);
  public
    constructor Create(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments;
      const AInput: TUpdateApplyInput);
    /// <summary>0 bei installed, sonst 1.</summary>
    function Run: Integer;
    property Outcome: TUpdateOutcome read FOutcome;
  end;

implementation

uses
  Atlas.Text.Updates,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Updates.Ides,
  Atlas.Common.Updates.Selection;

type
{$SCOPEDENUMS ON}
  TApplyText = (Waiting, KeptForProfile, RollingBack, Installing, Outcome);
{$SCOPEDENUMS OFF}

const
  cWaitMs = 1000;
  cTexts: array[TApplyText] of TAtlasText = (
    (De: 'Warte auf das Ende von:%s (Strg+C bricht ab)'; En: 'Waiting for:%s to exit (Ctrl+C cancels)'),
    (De: '%s bleibt: ein anderes Profil lädt es.'; En: '%s stays: another profile loads it.'),
    (De: 'Fehler beim Tausch, nehme alles zurück.'; En: 'Swap failed, rolling everything back.'),
    (De: 'Installiere Atlas %s'; En: 'Installing Atlas %s'),
    (De: 'Ergebnis: %s %s %s'; En: 'Result: %s %s %s'));

{ TUpdateInstallation }

constructor TUpdateInstallation.Create(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments;
  const AInput: TUpdateApplyInput);
begin
  inherited Create;
  FSystem := ASystem;
  FArgs := AArgs;
  FInput := AInput;
  FOutcome := Default(TUpdateOutcome);
  FOutcome.Version := AInput.Version;
  FOutcome.Previous := AInput.Previous;
  FOutcome.LogFile := TUpdateLayout.Join(AInput.WorkDir, TUpdateLayout.cLogFile);
end;

function TUpdateInstallation.PackageTarget: TUpdatePackageTarget;
begin
  Result := Default(TUpdatePackageTarget);
  Result.RegistryKey := FArgs.RegistryKey;
  Result.Platform := FArgs.Platform;
  Result.PackageDir := TUpdateLayout.Join(FArgs.Target, FArgs.Platform);
  Result.Suffix := TUpdateIdes.PackageSuffix(FArgs.Ide);
end;

function ProcessNames(const AProcesses: TArray<TUpdateProcess>): string;
var
  mProcess: TUpdateProcess;
begin
  Result := '';
  for mProcess in AProcesses do
  begin
    Result := Result + Format(' %s (%d)', [mProcess.Name, mProcess.Pid]);
  end;
end;

function IdeProcess(APid: Cardinal): TUpdateProcess;
begin
  Result := Default(TUpdateProcess);
  Result.Pid := APid;
  Result.Name := 'IDE';
end;

function TUpdateInstallation.WaitForIde: Boolean;
var
  mUsing: TArray<TUpdateProcess>;
  mShown: string;
begin
  mShown := '';
  repeat
    if FSystem.Processes.CancelRequested then
    begin
      Exit(False);
    end;
    mUsing := FSystem.Processes.UsingPackages(FArgs.Target);
    if (FArgs.WaitPid <> 0) and FSystem.Processes.IsRunning(FArgs.WaitPid) then
    begin
      mUsing := mUsing + [IdeProcess(FArgs.WaitPid)];
    end;
    if (Length(mUsing) > 0) and (ProcessNames(mUsing) <> mShown) then
    begin
      mShown := ProcessNames(mUsing);
      FSystem.Log(cTexts[TApplyText.Waiting].Fmt([mShown]));
    end;
    if Length(mUsing) > 0 then
    begin
      FSystem.Processes.Sleep(cWaitMs);
    end;
  until Length(mUsing) = 0;
  Result := True;
end;

/// <summary>Plattformordner und Name einer BPL bzw. Map (Pfad Win32\Atlas.IDE.X370.bpl); False sonst.</summary>
function SplitPackage(const APath: string; out APlatform, AName: string): Boolean;
var
  mParts: TArray<string>;
begin
  mParts := APath.Split(['\']);
  Result := (Length(mParts) = 2) and TUpdateIdes.IsPlatform(mParts[0]) and
    mParts[1].StartsWith(TUpdateVersions.cPackagePrefix, True) and
    (mParts[1].EndsWith('.bpl', True) or mParts[1].EndsWith('.map', True));
  APlatform := '';
  AName := '';
  if Result then
  begin
    APlatform := mParts[0];
    AName := TUpdateVersions.PackageName(ChangeFileExt(mParts[1], '.bpl'));
  end;
end;

function TUpdateInstallation.WantsFile(const APath: string): Boolean;
var
  mPlatform, mName: string;
begin
  if not SplitPackage(APath, mPlatform, mName) then
  begin
    Exit(True);
  end;
  if SameText(mPlatform, FArgs.Platform) then
  begin
    Result := TUpdateSelection.Contains(FSelected, mName);
  end
  else
  begin
    Result := FSystem.Files.FileExists(TUpdateLayout.Join(FArgs.Target, APath));
  end;
end;

procedure TUpdateInstallation.CopyFiles(ASwap: TUpdateFileSwap);
var
  mFile: string;
begin
  for mFile in FSystem.Files.FilesIn(FInput.FilesDir) do
  begin
    if WantsFile(mFile) then
    begin
      ASwap.CopyIn(TUpdateLayout.Join(FInput.FilesDir, mFile), mFile);
    end;
  end;
end;

procedure TUpdateInstallation.RemoveDeselected(ASwap: TUpdateFileSwap);
var
  mTarget: TUpdatePackageTarget;
  mCandidate: TUpdateCandidate;
  mFile: string;
begin
  mTarget := PackageTarget;
  for mCandidate in FInput.Candidates do
  begin
    if TUpdateSelection.Contains(FSelected, mCandidate.Name) then
    begin
      Continue;
    end;
    if TUpdateKnownPackages.UsedElsewhere(FSystem.Registry, mTarget.PackageFile(mCandidate.Name),
      FArgs.RegistryKey) then
    begin
      FSystem.Log(cTexts[TApplyText.KeptForProfile].Fmt([mCandidate.Name]));
      Continue;
    end;
    mFile := FArgs.Platform + '\' + mCandidate.Name + mTarget.Suffix;
    ASwap.Remove(mFile + '.bpl');
    ASwap.Remove(mFile + '.map');
  end;
end;

procedure TUpdateInstallation.Verify(ASwap: TUpdateFileSwap);
var
  mStep: TUpdateFileStep;
begin
  for mStep in ASwap.Steps do
  begin
    if not mStep.Deleted and not SameText(FSystem.Trust.Sha256(TUpdateLayout.Join(FArgs.Target, mStep.Path)),
      FSystem.Trust.Sha256(TUpdateLayout.Join(FInput.FilesDir, mStep.Path))) then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.cHash, mStep.Path);
    end;
  end;
end;

procedure TUpdateInstallation.Swap;
var
  mSwap: TUpdateFileSwap;
  mBackup: string;
begin
  mBackup := TUpdateLayout.Join(FInput.WorkDir, TUpdateLayout.cBackupFolder);
  FSystem.Files.DeleteDirectory(mBackup);
  mSwap := TUpdateFileSwap.Create(FSystem.Files, FArgs.Target, mBackup);
  try
    try
      CopyFiles(mSwap);
      RemoveDeselected(mSwap);
      FChanges := TUpdateKnownPackages.Plan(FSystem.Registry, PackageTarget, FSelected);
      TUpdateKnownPackages.Apply(FSystem.Registry, FChanges);
      Verify(mSwap);
    except
      FSystem.Log(cTexts[TApplyText.RollingBack].Text);
      TUpdateKnownPackages.Revert(FSystem.Registry, FChanges);
      mSwap.Rollback(FSystem.Log);
      raise;
    end;
  finally
    mSwap.Free;
  end;
end;

procedure TUpdateInstallation.Finish;
var
  mCandidate: TUpdateCandidate;
  mDeclinedFile: string;
  mOld: TArray<string>;
begin
  for mCandidate in FInput.Candidates do
  begin
    if TUpdateSelection.Contains(FSelected, mCandidate.Name) and not mCandidate.Installed then
    begin
      FOutcome.Added := FOutcome.Added + [mCandidate.Name];
    end;
    if not TUpdateSelection.Contains(FSelected, mCandidate.Name) and mCandidate.Installed then
    begin
      FOutcome.Removed := FOutcome.Removed + [mCandidate.Name];
    end;
  end;
  mDeclinedFile := TUpdateLayout.Join(FInput.RootDir, TUpdateLayout.cDeclinedFile);
  mOld := TUpdateSelection.ParseLines(FSystem.Files.ReadText(mDeclinedFile));
  FSystem.Files.WriteText(mDeclinedFile, TUpdateSelection.JoinLines(TUpdateSelection.Declined(mOld,
    FInput.Candidates, FSelected)));
  TUpdateFileSwap.CleanupOld(FSystem.Files, FArgs.Target, FSystem.Log);
  FOutcome.Kind := TUpdateOutcomeKind.Installed;
end;

procedure TUpdateInstallation.WriteOutcome;
begin
  FSystem.Files.WriteText(TUpdateLayout.Join(FInput.RootDir, TUpdateLayout.cResultFile), FOutcome.ToJson);
end;

procedure TUpdateInstallation.Fail(const ACode, ADetail: string);
begin
  // Vor dem Tausch ist nichts geändert, danach hat Swap alles zurückgenommen.
  if FSwapping then
  begin
    FOutcome.Kind := TUpdateOutcomeKind.RolledBack;
  end
  else
  begin
    FOutcome.Kind := TUpdateOutcomeKind.Failed;
  end;
  FOutcome.Reason := ACode;
  FOutcome.Detail := ADetail;
end;

function TUpdateInstallation.Run: Integer;
begin
  try
    FSelected := TUpdateSelection.Resolve(FInput.Candidates, FArgs.Select);
    if not WaitForIde then
    begin
      FOutcome.Kind := TUpdateOutcomeKind.Cancelled;
      FOutcome.Reason := TUpdateErrors.cCancelled;
    end
    else
    begin
      FSystem.Log(cTexts[TApplyText.Installing].Fmt([FInput.Version]));
      FSwapping := True;
      Swap;
      Finish;
    end;
  except
    on mError: EUpdateError do
    begin
      Fail(mError.Code, mError.Detail);
    end;
    on mError: EInOutError do
    begin
      Fail(TUpdateErrors.cCopyFailed, mError.Message);
    end;
    on mError: Exception do
    begin
      Fail(TUpdateErrors.cUnexpected, mError.Message);
    end;
  end;
  FSystem.Log(cTexts[TApplyText.Outcome].Fmt([TUpdateNames.OutcomeName(FOutcome.Kind), FOutcome.Reason,
    FOutcome.Detail]));
  WriteOutcome;
  Result := Ord(FOutcome.Kind <> TUpdateOutcomeKind.Installed);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Updates.Apply', cTexts);

end.
