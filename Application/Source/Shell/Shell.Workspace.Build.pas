unit Shell.Workspace.Build;

// Internals-Rolle Shell: per Befehl gewählte Konfiguration und Plattform eines Arbeitsbereichs (#46), gemerkt
// über Neustarts, und die Symbole aus den Projektoptionen der IDE (#615), auch ungespeichert.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Shell.Workspace.Setup;

type
  /// <summary>Threadsicher.</summary>
  TShellBuildChoice = class
  private
    FName: string;
    FLogger: ILogger;
    FSetup: TShellWorkspaceSetup;
    FLock: TObject;
    // '' = Einstellung.
    FConfig: string;
    FPlatform: string;
    // Nur mit FHasDefines.
    FDefines: TArray<string>;
    FHasDefines: Boolean;
    /// <summary>Gemerkte Konfiguration und Plattform schon übernommen; danach gilt nur noch Select.</summary>
    FRestored: Boolean;
    function TakeRestore(const AConfig, APlatform: string): Boolean;
  public
    constructor Create(const AName: string; const ALogger: ILogger; ASetup: TShellWorkspaceSetup);
    destructor Destroy; override;
    /// <summary>Übernimmt einmal die gemerkte Konfiguration und Plattform von AProjectFile (#46).</summary>
    procedure Restore(const AProjectFile: string);
    /// <summary>True, wenn eine Wahl verworfen wurde, die AProject nicht kennt; dann gelten die Vorgaben.</summary>
    function DropUnknown(const AProject: TProjectInfo): Boolean;
    /// <summary>Wählt AConfig und/oder APlatform ('' = unverändert), wenn AProject sie kennt; mit AHasDefines
    /// ersetzen ADefines die Symbole der .dproj. False mit Grund in AError.</summary>
    function Select(const AProject: TProjectInfo; const AConfig, APlatform: string; const ADefines: TArray<string>;
      AHasDefines: Boolean; out AError: string): Boolean;
    /// <summary>Gewählte Konfiguration und Plattform in AOptions; ungewählte bleiben.</summary>
    procedure ApplyTo(var AOptions: TDprojOptions);
    /// <summary>Symbole aus den Projektoptionen der IDE gelten vor denen der Datei (#615).</summary>
    procedure ApplyDefines(var AProject: TProjectInfo);
    /// <summary>Konfiguration oder Plattform per Befehl gewählt (auch gemerkt).</summary>
    function Chosen: Boolean;
    /// <summary>Getrimmt, groß, ohne Leere und Doppelte.</summary>
    class function NormalizedDefines(const ADefines: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Projects.Selection;

constructor TShellBuildChoice.Create(const AName: string; const ALogger: ILogger; ASetup: TShellWorkspaceSetup);
begin
  inherited Create;
  FName := AName;
  FLogger := ALogger;
  FSetup := ASetup;
  FLock := TObject.Create;
end;

destructor TShellBuildChoice.Destroy;
begin
  FLock.Free;
  FLogger := nil;
  inherited;
end;

class function TShellBuildChoice.NormalizedDefines(const ADefines: TArray<string>): TArray<string>;
var
  mDefine: string;
begin
  Result := nil;
  for mDefine in ADefines do
  begin
    if (Trim(mDefine) <> '') and (IndexText(Trim(mDefine), Result) < 0) then
    begin
      Result := Result + [UpperCase(Trim(mDefine))];
    end;
  end;
end;

function TShellBuildChoice.TakeRestore(const AConfig, APlatform: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := not FRestored;
    FRestored := True;
    if not Result then
    begin
      Exit;
    end;
    if FConfig = '' then
    begin
      FConfig := AConfig;
    end;
    if FPlatform = '' then
    begin
      FPlatform := APlatform;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellBuildChoice.Restore(const AProjectFile: string);
var
  mChoice: TProjectBuildChoice;
begin
  if (FSetup.Selection = nil) or not FSetup.Selection.Build(AProjectFile, mChoice) then
  begin
    TMonitor.Enter(FLock);
    try
      FRestored := True;
    finally
      TMonitor.Exit(FLock);
    end;
    Exit;
  end;
  if TakeRestore(mChoice.Config, mChoice.Platform) then
  begin
    FLogger.Info(Format('%s: gemerkte Wahl übernommen (Konfiguration %s, Plattform %s)',
      [FName, mChoice.Config, mChoice.Platform]));
  end;
end;

function TShellBuildChoice.DropUnknown(const AProject: TProjectInfo): Boolean;
var
  mError: string;
begin
  mError := '';
  TMonitor.Enter(FLock);
  try
    if (FConfig <> '') or (FPlatform <> '') then
    begin
      mError := TDprojReader.CheckTarget(AProject, FConfig, FPlatform);
    end;
    Result := mError <> '';
    if Result then
    begin
      FConfig := '';
      FPlatform := '';
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if not Result then
  begin
    Exit;
  end;
  FLogger.Warning(Format('%s: gewählte Konfiguration oder Plattform gibt es nicht mehr (%s); es gelten die Vorgaben',
    [FName, mError]));
  if FSetup.Selection <> nil then
  begin
    FSetup.Selection.SetBuild(AProject.FileName, '', '');
  end;
end;

function TShellBuildChoice.Select(const AProject: TProjectInfo; const AConfig, APlatform: string;
  const ADefines: TArray<string>; AHasDefines: Boolean; out AError: string): Boolean;
var
  mDefines: TArray<string>;
begin
  mDefines := NormalizedDefines(ADefines);
  AError := TDprojReader.CheckTarget(AProject, AConfig, APlatform);
  Result := AError = '';
  if not Result then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if AConfig <> '' then
    begin
      FConfig := AConfig;
    end;
    if APlatform <> '' then
    begin
      FPlatform := APlatform;
    end;
    if AHasDefines then
    begin
      FDefines := mDefines;
      FHasDefines := True;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if AHasDefines then
  begin
    FLogger.Info(Format('%s: %d Symbole aus den Projektoptionen der IDE', [FName, Length(mDefines)]));
  end;
end;

procedure TShellBuildChoice.ApplyTo(var AOptions: TDprojOptions);
begin
  TMonitor.Enter(FLock);
  try
    if FConfig <> '' then
    begin
      AOptions.Config := FConfig;
    end;
    if FPlatform <> '' then
    begin
      AOptions.Platform := FPlatform;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellBuildChoice.ApplyDefines(var AProject: TProjectInfo);
begin
  TMonitor.Enter(FLock);
  try
    if FHasDefines then
    begin
      AProject.Defines := FDefines;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellBuildChoice.Chosen: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (FConfig <> '') or (FPlatform <> '');
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
