unit Atlas.Core.Updates.Install;

// Update installieren (#1519, Variante A „beim Beenden installieren“), ohne
// IDE und ohne Prozesse:
// - updates.install: ask bietet ein gefundenes Update an, auto bereitet es
//   ohne Frage vor (nicht bei einer neuen Hauptversion), off meldet es nur
//   wie bisher (#495).
// - Vorbereitet wird unsichtbar mit „AtlasUpdate.exe prepare“ in
//   %LOCALAPPDATA%\Atlas\Updates\<Version> (Stand in state.json), eingespielt
//   beim Schließen der IDE mit „apply“ in einer sichtbaren Konsole; das
//   Ergebnis (result.json) meldet das Plugin beim nächsten Start.
// - Nicht über das Plugin: Installation über GetIt (GetIt verwaltet die
//   Dateien), ohne AtlasUpdate.exe neben AtlasServer.exe und außerhalb eines
//   Release-Ordners (<Ziel>\Win32 bzw. \Win64, etwa beim Bauen aus dem
//   Repository). Dann bleibt es beim Hinweis mit Link (#495).
// - Kanal: updates.channel = prerelease oder eine installierte
//   Vorabversion fragt die Versionsdatei der Vorabversionen, sonst die der
//   stabilen Versionen.

interface

uses
  System.SysUtils,
  Atlas.Text.UpdateRun;

type
{$SCOPEDENUMS ON}
  TAtlasUpdateInstallMode = (Off, Ask, Auto);
  /// <summary>Warum das Plugin ein Update nicht selbst installiert.</summary>
  TAtlasUpdateBlock = (None, GetIt, NoUpdater, NoReleaseFolder);
{$SCOPEDENUMS OFF}

  /// <summary>Was das Plugin über sich und die IDE weiß.</summary>
  TAtlasUpdateEnvironment = record
    /// <summary>Ordner der geladenen Base-BPL.</summary>
    PluginDir: string;
    /// <summary>Win32 oder Win64 (Bitbreite der IDE).</summary>
    Platform: string;
    /// <summary>CompilerVersion der IDE, z. B. „37.0“.</summary>
    Ide: string;
    /// <summary>Registry-Basis der IDE unter HKCU (auch eigene Profile mit bds -r).</summary>
    RegistryKey: string;
    /// <summary>Installierte Atlas-Version.</summary>
    Installed: string;
    /// <summary>AtlasUpdate.exe liegt im Atlas-Ordner.</summary>
    UpdaterExists: Boolean;
  end;

  TAtlasUpdateInstall = class
  public const
    PrereleaseChannel = 'prerelease';
    /// <summary>Fehlercode des Plugins: AtlasUpdate.exe ließ sich nicht starten.</summary>
    StartFailed = 'start';
  public
    /// <summary>Wert von updates.install; unbekannt = ask.</summary>
    class function ModeOf(const AText: string): TAtlasUpdateInstallMode; static;
    /// <summary>Adresse der Versionsdatei nach updates.channel und installierter Version.</summary>
    class function ChannelUrl(const AChannel, AInstalled: string): string; static;
    /// <summary>ALocalAppData\Atlas\Updates.</summary>
    class function UpdatesRoot(const ALocalAppData: string): string; static;
    class function StagingDir(const ARoot, AVersion: string): string; static;
    /// <summary>Atlas-Ordner: eine Ebene über dem Ordner der BPL.</summary>
    class function TargetOf(const APluginDir: string): string; static;
    class function UpdaterOf(const APluginDir: string): string; static;
    class function Blocked(const AEnvironment: TAtlasUpdateEnvironment): TAtlasUpdateBlock; static;
    /// <summary>Andere Hauptversion als die installierte (Änderungen lesen, nie ohne Frage).</summary>
    class function IsMajorJump(const AInstalled, AVersion: string): Boolean; static;
    /// <summary>Ohne Frage vorbereiten: auto und keine neue Hauptversion.</summary>
    class function PrepareWithoutAsking(AMode: TAtlasUpdateInstallMode; const AInstalled,
      AVersion: string): Boolean; static;
    /// <summary>Aufruf „prepare“ für AVersion aus der Versionsdatei AManifestUrl.</summary>
    class function PrepareArgs(const AEnvironment: TAtlasUpdateEnvironment; const ARoot, AVersion, AManifestUrl,
      ANewModules: string): TUpdateArguments; static;
    /// <summary>Aufruf „apply“ mit den gewählten Packages; AWaitPid = Prozess der IDE.</summary>
    class function ApplyArgs(const AEnvironment: TAtlasUpdateEnvironment; const ARoot: string;
      const AStage: TUpdateStage; AWaitPid: Cardinal): TUpdateArguments; static;
    /// <summary>Stand eines laufenden oder fertigen „prepare“: fertig, wenn bereit oder gescheitert.</summary>
    class function IsFinished(const AStage: TUpdateStage): Boolean; static;
    /// <summary>Gewählte Packages nach der Auswahl (Mockup 6) übernehmen; Pflicht-Packages bleiben gewählt,
    /// unbekannte Namen fallen weg. Danach fragt das Plugin nicht mehr.</summary>
    class function Choose(const AStage: TUpdateStage; const AChosen: TArray<string>): TUpdateStage; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Updates;

const
  cModeNames: array[TAtlasUpdateInstallMode] of string = ('off', 'ask', 'auto');

{ TAtlasUpdateInstall }

class function TAtlasUpdateInstall.ModeOf(const AText: string): TAtlasUpdateInstallMode;
var
  mIndex: Integer;
begin
  mIndex := IndexText(AText, cModeNames);
  Result := TAtlasUpdateInstallMode.Ask;
  if mIndex >= 0 then
  begin
    Result := TAtlasUpdateInstallMode(mIndex);
  end;
end;

class function TAtlasUpdateInstall.ChannelUrl(const AChannel, AInstalled: string): string;
begin
  // Wer eine Vorabversion fährt, erfährt auch von der nächsten (stabil kommt ebenfalls in diesen Kanal).
  Result := TUpdateChannels.UrlOf(SameText(AChannel, PrereleaseChannel) or (Pos('-', AInstalled) > 0));
end;

class function TAtlasUpdateInstall.UpdatesRoot(const ALocalAppData: string): string;
begin
  Result := TUpdateLayout.Join(TUpdateLayout.Join(ALocalAppData, 'Atlas'), 'Updates');
end;

class function TAtlasUpdateInstall.StagingDir(const ARoot, AVersion: string): string;
begin
  Result := TUpdateLayout.Join(ARoot, AVersion);
end;

class function TAtlasUpdateInstall.TargetOf(const APluginDir: string): string;
begin
  Result := ExtractFileDir(ExcludeTrailingPathDelimiter(APluginDir));
end;

class function TAtlasUpdateInstall.UpdaterOf(const APluginDir: string): string;
begin
  Result := TUpdateLayout.Join(TargetOf(APluginDir), TUpdateLayout.UpdaterExe);
end;

class function TAtlasUpdateInstall.Blocked(const AEnvironment: TAtlasUpdateEnvironment): TAtlasUpdateBlock;
begin
  Result := TAtlasUpdateBlock.None;
  if ContainsText(AEnvironment.PluginDir, '\CatalogRepository\') then
  begin
    Result := TAtlasUpdateBlock.GetIt;
  end
  else if not SameText(ExtractFileName(ExcludeTrailingPathDelimiter(AEnvironment.PluginDir)),
    AEnvironment.Platform) then
  begin
    Result := TAtlasUpdateBlock.NoReleaseFolder;
  end
  else if not AEnvironment.UpdaterExists then
  begin
    Result := TAtlasUpdateBlock.NoUpdater;
  end;
end;

class function TAtlasUpdateInstall.IsMajorJump(const AInstalled, AVersion: string): Boolean;
begin
  Result := TUpdateVersions.Major(AInstalled) <> TUpdateVersions.Major(AVersion);
end;

class function TAtlasUpdateInstall.PrepareWithoutAsking(AMode: TAtlasUpdateInstallMode; const AInstalled,
  AVersion: string): Boolean;
begin
  Result := (AMode = TAtlasUpdateInstallMode.Auto) and not IsMajorJump(AInstalled, AVersion);
end;

class function TAtlasUpdateInstall.PrepareArgs(const AEnvironment: TAtlasUpdateEnvironment; const ARoot, AVersion,
  AManifestUrl, ANewModules: string): TUpdateArguments;
begin
  Result := Default(TUpdateArguments);
  Result.Command := 'prepare';
  Result.ManifestUrl := AManifestUrl;
  Result.Version := AVersion;
  Result.Previous := AEnvironment.Installed;
  Result.Ide := AEnvironment.Ide;
  Result.Platform := AEnvironment.Platform;
  Result.RegistryKey := AEnvironment.RegistryKey;
  Result.Target := TargetOf(AEnvironment.PluginDir);
  Result.Staging := StagingDir(ARoot, AVersion);
  Result.NewModules := TUpdateNames.ParseNewModules(ANewModules);
end;

class function TAtlasUpdateInstall.ApplyArgs(const AEnvironment: TAtlasUpdateEnvironment; const ARoot: string;
  const AStage: TUpdateStage; AWaitPid: Cardinal): TUpdateArguments;
begin
  Result := Default(TUpdateArguments);
  Result.Command := 'apply';
  Result.Version := AStage.Version;
  Result.Previous := AEnvironment.Installed;
  Result.Ide := AEnvironment.Ide;
  Result.Platform := AEnvironment.Platform;
  Result.RegistryKey := AEnvironment.RegistryKey;
  Result.Target := TargetOf(AEnvironment.PluginDir);
  Result.Staging := StagingDir(ARoot, AStage.Version);
  Result.Select := AStage.SelectedNames;
  Result.WaitPid := AWaitPid;
end;

class function TAtlasUpdateInstall.IsFinished(const AStage: TUpdateStage): Boolean;
begin
  Result := AStage.Phase in [TUpdatePhase.Ready, TUpdatePhase.Failed];
end;

class function TAtlasUpdateInstall.Choose(const AStage: TUpdateStage; const AChosen: TArray<string>): TUpdateStage;
var
  mIndex: Integer;
begin
  Result := AStage;
  Result.Candidates := Copy(AStage.Candidates);
  for mIndex := 0 to High(Result.Candidates) do
  begin
    Result.Candidates[mIndex].Selected := Result.Candidates[mIndex].Required or
      MatchText(Result.Candidates[mIndex].Name, AChosen);
  end;
  Result.AskSelection := False;
end;

end.
