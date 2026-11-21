unit Atlas.Common.Updates.Prepare;

// Platform-Feature "Updates" (#1519), Root: Befehl prepare von
// AtlasUpdate.exe. Läuft unsichtbar, während die IDE weiterläuft, und ändert
// nichts am Atlas-Ordner:
// 0. state.json sofort neu schreiben: Ein Stand eines früheren Laufs im
//    selben Ordner gilt ab hier nicht mehr.
// 1. Versionsdatei laden; sie muss die angebotene Version nennen und mit
//    einem der eingebetteten Schlüssel signiert sein (Signaturdatei daneben,
//    Atlas.Common.Updates.ManifestSignature). Eine falsche Signatur bricht ab,
//    eine fehlende nur, solange RequireManifestSignature gilt; sonst Hinweis.
//    Alle Adressen (Versionsdatei, Paket, Quelltext) nur von TUpdateHosts.
// 2. Paket der eigenen IDE laden und mit SHA-256 prüfen; gibt es keins, das
//    erste Paket (Server, Daten) und den Quelltext laden und die Packages
//    bauen (ohne Kommandozeilen-Compiler Fehler noCompiler). Gebaut wird nur
//    nach Bestätigung (--allow-source); sonst endet der Lauf vor dem ersten
//    Download mit sourceConfirm, und das Plugin fragt. Gebaute Packages sind
//    nicht an den Herausgeber gebunden; das Protokoll sagt es.
// 3. Sicher nach <Staging>\files entpacken und die Signaturen prüfen: Ist
//    AtlasUpdate.exe selbst signiert, müssen alle EXE und BPL des Pakets
//    gültig und mit demselben Schlüssel signiert sein (Fingerabdruck, nicht
//    der Name; kein Wechsel auf unsignierte Dateien). Ist der Herausgeber
//    einer Datei nicht lesbar, gilt sie als unsigniert. Unsignierte Releases
//    prüft nur die Prüfsumme.
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
    FRequireManifestSignature: Boolean;
    FManifestKeys: TArray<string>;
    procedure SetPhase(APhase: TUpdatePhase; AProgress: Integer);
    procedure WriteStage;
    procedure CheckManifestSignature(const AManifest: string);
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
    /// <summary>Ohne Signaturdatei abbrechen statt warnen; Vorgabe TUpdateManifestSignature.cRequired.</summary>
    property RequireManifestSignature: Boolean read FRequireManifestSignature write FRequireManifestSignature;
    /// <summary>Öffentliche Schlüssel für die Versionsdatei; Vorgabe TUpdateManifestSignature.Keys.</summary>
    property ManifestKeys: TArray<string> read FManifestKeys write FManifestKeys;
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
  Atlas.Common.Updates.ManifestSignature,
  Atlas.Common.Updates.Selection;

type
{$SCOPEDENUMS ON}
  TPrepareText = (Loading, Unsigned, FromSource, ManifestUnsigned, Failed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TPrepareText] of TAtlasText = (
    (De: 'Lade %s'; En: 'Downloading %s'),
    (De: 'AtlasUpdate.exe ist nicht signiert: nur die Prüfsumme sichert das Paket.';
    En: 'AtlasUpdate.exe is not signed: only the checksum protects the package.'),
    (De: 'Bau aus dem Quelltext: Die gebauten Packages sind nicht an den Herausgeber gebunden; nur die Prüfsumme ' +
    'sichert den Quelltext.';
    En: 'Building from source: the built packages are not bound to the publisher; only the checksum protects the ' +
    'source.'),
    (De: 'Die Versionsdatei ist nicht signiert (%s): Das Update ist nicht an den Herausgeber gebunden.';
    En: 'The version file is not signed (%s): the update is not bound to the publisher.'),
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
  FRequireManifestSignature := TUpdateManifestSignature.cRequired;
  FManifestKeys := TUpdateManifestSignature.Keys;
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

procedure TUpdatePreparation.WriteStage;
begin
  FSystem.Files.WriteText(TUpdateLayout.Join(FArgs.Staging, TUpdateLayout.cStateFile), FStage.ToJson);
end;

procedure TUpdatePreparation.CheckManifestSignature(const AManifest: string);
var
  mSignature, mError: string;
  mFound: Boolean;
  mVerdict: TUpdateManifestVerdict;
begin
  mFound := FSystem.Network.Fetch(TUpdateManifestSignature.SignatureUrl(FArgs.ManifestUrl), mSignature, mError);
  mVerdict := TUpdateManifestSignature.Verdict(FSystem.Trust, AManifest, mFound, mSignature, FManifestKeys);
  if mVerdict = TUpdateManifestVerdict.Forged then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cManifestSignature, '');
  end;
  if mVerdict <> TUpdateManifestVerdict.Missing then
  begin
    Exit;
  end;
  if FRequireManifestSignature then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cManifestUnsigned, mError);
  end;
  FSystem.Log(cTexts[TPrepareText.ManifestUnsigned].Fmt([mError]));
  FStage.Warning := TUpdateErrors.cManifestUnsigned;
end;

/// <summary>EUpdateError (host) für eine Adresse außerhalb der erlaubten Hosts, bevor etwas geladen wird.</summary>
procedure CheckHost(const AUrl: string);
begin
  if not TUpdateHosts.IsTrusted(AUrl) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cHost, TUpdateHosts.HostOf(AUrl));
  end;
end;

function TUpdatePreparation.LoadManifest: TUpdateManifest;
var
  mText, mError: string;
begin
  CheckHost(FArgs.ManifestUrl);
  if not FSystem.Network.Fetch(FArgs.ManifestUrl, mText, mError) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cDownload, mError);
  end;
  // Vor dem Auswerten: Nichts aus einer unechten Versionsdatei (Adressen, Prüfsummen) wird verwendet.
  CheckManifestSignature(mText);
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
  CheckHost(AFile.Url);
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
  // Signiert, aber ohne lesbaren Herausgeber: Vergleichen ginge nur mit leeren Angaben, also abbrechen statt
  // auf die bloße Prüfsumme zurückzufallen.
  if not mOwn.IsComplete then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cSignature, TUpdateLayout.cUpdaterExe);
  end;
  mFilesDir := TUpdateFolders.FilesDir(FArgs.Staging);
  for mFile in FSystem.Files.FilesIn(mFilesDir) do
  begin
    if not IsBinary(mFile) then
    begin
      Continue;
    end;
    mSignature := FSystem.Trust.Signature(TUpdateLayout.Join(mFilesDir, mFile));
    if not mSignature.IsComplete then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.cUnsigned, mFile);
    end;
    if not mSignature.SameSigner(mOwn) then
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
  FSystem.Log(cTexts[TPrepareText.FromSource].Text);
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
  // Unbedingt schreiben: Downloading/0 ist auch der Anfangswert von FStage, SetPhase schriebe dann nichts, und
  // ein fertiger oder gescheiterter Stand eines früheren Laufs bliebe stehen, während files schon gelöscht wird.
  FStage.Phase := TUpdatePhase.Downloading;
  FStage.Progress := 0;
  FStage.Version := FArgs.Version;
  WriteStage;
  mManifest := LoadManifest;
  FStage.Version := mManifest.Version;
  FStage.Previous := FArgs.Previous;
  FStage.FromSource := not mManifest.PackageFor(FArgs.Ide, mPackage);
  if FStage.FromSource and not (mManifest.Source.IsValid and mManifest.AnyPackage(mPackage)) then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cNoPackage, FArgs.Ide);
  end;
  // Den Quelltext-Weg bindet keine Signatur an den Herausgeber: nur nach Bestätigung, und vor jedem Download.
  if FStage.FromSource and not FArgs.AllowSource then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.cSourceConfirm, FArgs.Ide);
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
