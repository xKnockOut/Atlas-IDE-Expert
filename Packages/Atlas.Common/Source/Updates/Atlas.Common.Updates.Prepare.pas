unit Atlas.Common.Updates.Prepare;

// Platform-Feature "Updates" (#1519), Root: Befehl prepare von
// AtlasUpdate.exe. Läuft unsichtbar, während die IDE weiterläuft, und ändert
// nichts am Atlas-Ordner:
// 1. Versionsdatei laden; sie muss die angebotene Version nennen.
// 2. Paket der eigenen IDE laden und mit SHA-256 prüfen; gibt es keins, das
//    erste Paket (Server, Daten) und den Quelltext laden und die Packages
//    bauen (ohne Kommandozeilen-Compiler Fehler noCompiler).
// 3. Sicher nach <Staging>\files entpacken und die Signaturen prüfen: Ist
//    AtlasUpdate.exe selbst signiert, müssen alle EXE und BPL des Pakets
//    gültig und vom selben Herausgeber signiert sein (kein Wechsel auf
//    unsignierte Dateien). Unsignierte Releases prüft nur die Prüfsumme.
// 4. Kandidaten für die Auswahl bestimmen und state.json auf ready setzen.
// Jeder Schritt schreibt state.json; ein Fehler setzt failed mit Kennung.

interface

uses
  System.SysUtils,
  Atlas.Text.Updates,
  Atlas.Text.UpdateRun,
  Atlas.Common.Updates.Contract;

type
  TUpdatePreparation = class
  private
    FSystem: TUpdateSystem;
    FArgs: TUpdateArguments;
    FUpdater: string;
    FStage: TUpdateStage;
    procedure SetPhase(APhase: TUpdatePhase; AProgress: Integer);
    procedure WriteStage;
    function LoadManifest: TUpdateManifest;
    procedure Fetch(const AFile: TUpdateFile; const AName: string; AFrom, ATo: Integer; const ATargetDir: string);
    procedure CheckSignatures;
    procedure BuildFromSource(const ASource: TUpdateFile);
    procedure SelectCandidates;
    procedure Prepare;
  public
    /// <summary>AUpdater: Pfad der laufenden AtlasUpdate.exe (Herausgeber für die Signaturprüfung).</summary>
    constructor Create(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments; const AUpdater: string);
    /// <summary>0 bei Erfolg (state.json ready), sonst 1 (failed).</summary>
    function Run: Integer;
    property Stage: TUpdateStage read FStage;
  end;

  TUpdateFolders = class
  public
    class function FilesDir(const AStaging: string): string; static;
    class function PlatformDir(const ARoot, APlatform: string): string; static;
    /// <summary>Übergeordneter Ordner der Staging-Ordner (Updates-Root).</summary>
    class function RootOf(const AStaging: string): string; static;
    /// <summary>Namen der Atlas-Packages (ohne Endung) in ADir.</summary>
    class function PackagesIn(const AFiles: IUpdateFiles; const ADir: string): TArray<string>; static;
    /// <summary>Packages des neuen Aufbaus AFilesDir zur Auswahl für Profil und Atlas-Ordner aus AArgs;
    /// EUpdateError (noPackage) ohne Kern-Package für die IDE.</summary>
    class function Candidates(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments;
      const AFilesDir: string): TArray<TUpdateCandidate>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Updates.Ides,
  Atlas.Common.Updates.Archive,
  Atlas.Common.Updates.SourceBuild,
  Atlas.Common.Updates.KnownPackages,
  Atlas.Common.Updates.Selection;

type
{$SCOPEDENUMS ON}
  TPrepareText = (Loading, Unsigned, Failed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TPrepareText] of TAtlasText = (
    (De: 'Lade %s'; En: 'Downloading %s'),
    (De: 'AtlasUpdate.exe ist nicht signiert: nur die Prüfsumme sichert das Paket.';
    En: 'AtlasUpdate.exe is not signed: only the checksum protects the package.'),
    (De: 'Fehler %s: %s'; En: 'Error %s: %s'));

{ TUpdateFolders }

class function TUpdateFolders.FilesDir(const AStaging: string): string;
begin
  Result := TUpdateLayout.Join(AStaging, TUpdateLayout.cFilesFolder);
end;

class function TUpdateFolders.PlatformDir(const ARoot, APlatform: string): string;
begin
  Result := TUpdateLayout.Join(ARoot, APlatform);
end;

class function TUpdateFolders.RootOf(const AStaging: string): string;
var
  mText: string;
begin
  mText := AStaging;
  while mText.EndsWith('\') do
  begin
    mText := mText.Substring(0, Length(mText) - 1);
  end;
  Result := mText.Substring(0, mText.LastDelimiter('\'));
end;

class function TUpdateFolders.PackagesIn(const AFiles: IUpdateFiles; const ADir: string): TArray<string>;
var
  mList: TList<string>;
  mFile: string;
begin
  mList := TList<string>.Create;
  try
    for mFile in AFiles.FilesIn(ADir) do
    begin
      if (Pos('\', mFile) = 0) and TUpdateKnownPackages.IsAtlasPackage(mFile) then
      begin
        mList.Add(TUpdateVersions.PackageName(mFile));
      end;
    end;
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateFolders.Candidates(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments;
  const AFilesDir: string): TArray<TUpdateCandidate>;
var
  mInput: TUpdateSelectionInput;
  mTarget: TUpdatePackageTarget;
begin
  mTarget := Default(TUpdatePackageTarget);
  mTarget.RegistryKey := AArgs.RegistryKey;
  mTarget.Platform := AArgs.Platform;
  mTarget.PackageDir := PlatformDir(AArgs.Target, AArgs.Platform);
  mTarget.Suffix := TUpdateIdes.PackageSuffix(AArgs.Ide);
  mInput := Default(TUpdateSelectionInput);
  mInput.Staged := PackagesIn(ASystem.Files, PlatformDir(AFilesDir, AArgs.Platform));
  if not ASystem.Files.FileExists(TUpdateLayout.Join(PlatformDir(AFilesDir, AArgs.Platform),
    TUpdateVersions.cBasePackage + mTarget.Suffix + '.bpl')) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cNoPackage, AArgs.Platform);
  end;
  mInput.Registered := TUpdateKnownPackages.Registered(ASystem.Registry, mTarget);
  mInput.Present := PackagesIn(ASystem.Files, mTarget.PackageDir);
  mInput.Declined := TUpdateSelection.ParseLines(ASystem.Files.ReadText(TUpdateLayout.Join(RootOf(AArgs.Staging),
    TUpdateLayout.cDeclinedFile)));
  mInput.NewModules := AArgs.NewModules;
  Result := TUpdateSelection.Candidates(mInput);
end;

{ TUpdatePreparation }

constructor TUpdatePreparation.Create(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments;
  const AUpdater: string);
begin
  inherited Create;
  FSystem := ASystem;
  FArgs := AArgs;
  FUpdater := AUpdater;
  FStage := Default(TUpdateStage);
end;

procedure TUpdatePreparation.WriteStage;
begin
  FSystem.Files.WriteText(TUpdateLayout.Join(FArgs.Staging, TUpdateLayout.cStateFile), FStage.ToJson);
end;

procedure TUpdatePreparation.SetPhase(APhase: TUpdatePhase; AProgress: Integer);
begin
  if (FStage.Phase = APhase) and (FStage.Progress = AProgress) then
  begin
    Exit;
  end;
  FStage.Phase := APhase;
  FStage.Progress := AProgress;
  WriteStage;
end;

function TUpdatePreparation.LoadManifest: TUpdateManifest;
var
  mText, mError: string;
begin
  if not FSystem.Network.Fetch(FArgs.ManifestUrl, mText, mError) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cDownload, mError);
  end;
  if not TUpdateManifests.TryParse(mText, TUpdateChannels.cReleasesUrl, Result) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cManifest, '');
  end;
  if (FArgs.Version <> '') and (Result.Version <> FArgs.Version) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cVersionChanged, Result.Version);
  end;
end;

procedure TUpdatePreparation.Fetch(const AFile: TUpdateFile; const AName: string; AFrom, ATo: Integer;
  const ATargetDir: string);
var
  mZip, mError: string;
begin
  mZip := TUpdateLayout.Join(TUpdateLayout.Join(FArgs.Staging, TUpdateLayout.cDownloadFolder), AName);
  FSystem.Log(cTexts[TPrepareText.Loading].Fmt([AName]));
  if not FSystem.Network.Download(AFile.Url, mZip,
    procedure(APercent: Integer)
    begin
      SetPhase(TUpdatePhase.Downloading, AFrom + (ATo - AFrom) * APercent div 100);
    end, mError) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cDownload, mError);
  end;
  if not SameText(FSystem.Trust.Sha256(mZip), AFile.Sha256) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cHash, AName);
  end;
  TUpdateArchives.ExtractAll(FSystem.Archive, mZip, ATargetDir);
end;

function IsBinary(const AFile: string): Boolean;
begin
  Result := AFile.EndsWith('.exe', True) or AFile.EndsWith('.bpl', True) or AFile.EndsWith('.dll', True);
end;

procedure TUpdatePreparation.CheckSignatures;
var
  mOwn, mSignature: TUpdateSignature;
  mFile, mFilesDir: string;
begin
  SetPhase(TUpdatePhase.Verifying, 0);
  mOwn := FSystem.Trust.Signature(FUpdater);
  if not mOwn.Valid then
  begin
    FSystem.Log(cTexts[TPrepareText.Unsigned].Text);
    Exit;
  end;
  mFilesDir := TUpdateFolders.FilesDir(FArgs.Staging);
  for mFile in FSystem.Files.FilesIn(mFilesDir) do
  begin
    if not IsBinary(mFile) then
    begin
      Continue;
    end;
    mSignature := FSystem.Trust.Signature(TUpdateLayout.Join(mFilesDir, mFile));
    if not mSignature.Valid then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.cUnsigned, mFile);
    end;
    if mSignature.Subject <> mOwn.Subject then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.cSignature, mFile);
    end;
  end;
end;

procedure TUpdatePreparation.BuildFromSource(const ASource: TUpdateFile);
var
  mSourceDir, mReason: string;
  mVersion: TUpdateIdeVersion;
begin
  TUpdateIdes.ByCompilerVersion(FArgs.Ide, mVersion);
  if not FSystem.Builder.CanBuild(mVersion.BdsVersion, FArgs.Platform, mReason) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cNoCompiler, mReason);
  end;
  mSourceDir := TUpdateLayout.Join(FArgs.Staging, TUpdateLayout.cSourceFolder);
  Fetch(ASource, 'source.zip', 50, 80, mSourceDir);
  SetPhase(TUpdatePhase.Building, 0);
  TUpdateSourceBuild.Build(FSystem, mVersion.BdsVersion, FArgs.Platform, mSourceDir);
  TUpdateSourceBuild.Stage(FSystem.Files, mSourceDir, FArgs.Platform, TUpdateFolders.FilesDir(FArgs.Staging));
  SetPhase(TUpdatePhase.Building, 100);
end;

procedure TUpdatePreparation.SelectCandidates;
begin
  FStage.Candidates := TUpdateFolders.Candidates(FSystem, FArgs, TUpdateFolders.FilesDir(FArgs.Staging));
  FStage.AskSelection := TUpdateSelection.MustAsk(FStage.Candidates, FArgs.NewModules);
end;

procedure TUpdatePreparation.Prepare;
var
  mManifest: TUpdateManifest;
  mPackage: TUpdateFile;
  mFilesDir: string;
begin
  SetPhase(TUpdatePhase.Downloading, 0);
  mManifest := LoadManifest;
  FStage.Version := mManifest.Version;
  FStage.Previous := FArgs.Previous;
  FStage.FromSource := not mManifest.PackageFor(FArgs.Ide, mPackage);
  if FStage.FromSource and not (mManifest.Source.IsValid and mManifest.AnyPackage(mPackage)) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cNoPackage, FArgs.Ide);
  end;
  mFilesDir := TUpdateFolders.FilesDir(FArgs.Staging);
  FSystem.Files.DeleteDirectory(mFilesDir);
  FSystem.Files.DeleteDirectory(TUpdateLayout.Join(FArgs.Staging, TUpdateLayout.cSourceFolder));
  Fetch(mPackage, 'package.zip', 0, 50, mFilesDir);
  CheckSignatures;
  if FStage.FromSource then
  begin
    BuildFromSource(mManifest.Source);
  end;
  SelectCandidates;
  if FSystem.Files.FileExists(TUpdateLayout.Join(mFilesDir, TUpdateLayout.cUpdaterExe)) then
  begin
    FStage.Updater := TUpdateLayout.Join(mFilesDir, TUpdateLayout.cUpdaterExe);
  end;
  FSystem.Files.DeleteDirectory(TUpdateLayout.Join(FArgs.Staging, TUpdateLayout.cDownloadFolder));
  SetPhase(TUpdatePhase.Ready, 100);
end;

function TUpdatePreparation.Run: Integer;
begin
  Result := 0;
  try
    Prepare;
  except
    on mError: EUpdateError do
    begin
      FStage.Error := mError.Code;
      FStage.Detail := mError.Detail;
      Result := 1;
    end;
    on mError: Exception do
    begin
      FStage.Error := TUpdateErrors.cUnexpected;
      FStage.Detail := mError.Message;
      Result := 1;
    end;
  end;
  if Result <> 0 then
  begin
    FSystem.Log(cTexts[TPrepareText.Failed].Fmt([FStage.Error, FStage.Detail]));
    FStage.Phase := TUpdatePhase.Failed;
    WriteStage;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Updates.Prepare', cTexts);

end.
