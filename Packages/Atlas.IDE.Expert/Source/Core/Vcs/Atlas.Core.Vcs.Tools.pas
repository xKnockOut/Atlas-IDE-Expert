unit Atlas.Core.Vcs.Tools;

// Findet git und svn auf dem Rechner (#571) und startet sie über
// IAtlasVcsRunner. Gesucht wird in PATH und in den üblichen
// Installationsordnern (Git für Windows, TortoiseSVN mit
// Kommandozeilenwerkzeugen, SlikSVN, CollabNet, VisualSVN); das Ergebnis
// merkt sich Find für die Sitzung. Fehlt das Programm, liefert jeder Aufruf
// Outcome ToolMissing.
// Ein eigener Pfad aus vcs.git.path bzw. vcs.svn.path (#1285, Configure) gilt
// vor PATH und den bekannten Ordnern; fehlt die Datei dort, gilt das Programm
// als fehlend, ohne ersatzweise woanders zu suchen (Source ConfiguredMissing).
// Where nennt außer dem Pfad auch den Fundort für die Optionsseite.
// TAtlasVcsCommand bündelt Programm, Arbeitsverzeichnis und Zeitlimit einer
// Umsetzung; die Ausgabe des Programms geht nie ins Protokoll (Pfade).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Vcs.Contract;

type
  TAtlasVcsPathExists = reference to function(const APath: string): Boolean;

{$SCOPEDENUMS ON}
  /// <summary>Fundort von git bzw. svn (#1285). None: nicht gefunden. Configured: eigener Pfad aus den
  /// Einstellungen. Path: aus PATH. KnownDir: aus einem üblichen Installationsordner. ConfiguredMissing: eigener
  /// Pfad gesetzt, die Datei fehlt dort.</summary>
  TAtlasVcsToolSource = (None, Configured, Path, KnownDir, ConfiguredMissing);
{$SCOPEDENUMS OFF}

  /// <summary>Gefundenes Programm mit Fundort (#1285).</summary>
  TAtlasVcsToolLocation = record
    /// <summary>Vollständiger Pfad; '' wenn nicht gefunden.</summary>
    Executable: string;
    Source: TAtlasVcsToolSource;
    /// <summary>Eigener Pfad aus den Einstellungen, wie eingetragen; '' ohne.</summary>
    Configured: string;
    class function Empty: TAtlasVcsToolLocation; static;
  end;

  TAtlasVcsTools = class
  private class var
    FLock: TCriticalSection;
    FFound: array[TAtlasVcsKind] of TAtlasVcsToolLocation;
    FSearched: array[TAtlasVcsKind] of Boolean;
    FConfigured: array[TAtlasVcsKind] of string;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Programmname ohne Endung: "git" bzw. "svn"; '' für None.</summary>
    class function ProgramName(AKind: TAtlasVcsKind): string; static;
    /// <summary>Ordner, in denen das Programm außerhalb von PATH üblicherweise liegt, unter AProgramDirs
    /// (z. B. %ProgramFiles%).</summary>
    class function KnownDirs(AKind: TAtlasVcsKind; const AProgramDirs: TArray<string>): TArray<string>; static;
    /// <summary>Erster Treffer für AName (mit .exe unter Windows) in APath (durch ";" bzw. ":" getrennt), dann
    /// in AExtraDirs; '' ohne Treffer.</summary>
    class function Locate(const AName, APath: string; const AExtraDirs: TArray<string>;
      const AExists: TAtlasVcsPathExists): string; static;
    /// <summary>Fundort für AName (#1285): ein gesetzter eigener Pfad AConfigured gilt allein (fehlt die Datei,
    /// Source ConfiguredMissing ohne Suche anderswo); sonst erster Treffer in APath, dann in AExtraDirs.</summary>
    class function Resolve(const AName, AConfigured, APath: string; const AExtraDirs: TArray<string>;
      const AExists: TAtlasVcsPathExists): TAtlasVcsToolLocation; static;
    /// <summary>Eigener Pfad aus vcs.git.path bzw. vcs.svn.path ('' = automatisch suchen). Ändert er sich, vergisst
    /// Find das gemerkte Ergebnis dieser Art; so gilt ein neuer Pfad ohne Neustart.</summary>
    class procedure Configure(AKind: TAtlasVcsKind; const APath: string); static;
    /// <summary>Gesetzter eigener Pfad; '' ohne.</summary>
    class function Configured(AKind: TAtlasVcsKind): string; static;
    /// <summary>Fundort für den eigenen Pfad AConfigured ('' = automatisch suchen) auf diesem Rechner, ohne sich
    /// etwas zu merken (Optionsseite, noch nicht gespeicherter Pfad).</summary>
    class function Probe(AKind: TAtlasVcsKind; const AConfigured: string): TAtlasVcsToolLocation; static;
    /// <summary>git bzw. svn auf diesem Rechner mit Fundort. Merkt sich das Ergebnis.</summary>
    class function Where(AKind: TAtlasVcsKind): TAtlasVcsToolLocation; static;
    /// <summary>git bzw. svn auf diesem Rechner; '' wenn nicht installiert. Merkt sich das Ergebnis.</summary>
    class function Find(AKind: TAtlasVcsKind): string; static;
    /// <summary>Vergessen, was Find gefunden hat (Tests, nach Installation); eigene Pfade bleiben.</summary>
    class procedure Forget; static;
    /// <summary>Für Tests: Ergebnis von Find vorgeben ('' = nicht installiert).</summary>
    class procedure Preset(AKind: TAtlasVcsKind; const AExecutable: string); static;
  end;

  /// <summary>Ein Programm (git oder svn) mit Arbeitsverzeichnis und Zeitlimit.</summary>
  TAtlasVcsCommand = class
  private
    FRunner: IAtlasVcsRunner;
    FExecutable: string;
    FWorkingDir: string;
    FTimeoutMs: Cardinal;
  public
    /// <summary>Vorgabe für das Zeitlimit eines Aufrufs.</summary>
    const DefaultTimeoutMs = 15000;
    constructor Create(const ARunner: IAtlasVcsRunner; const AExecutable, AWorkingDir: string;
      ATimeoutMs: Cardinal);
    /// <summary>Startet das Programm; Outcome Failed bei Exit-Code ungleich 0, ToolMissing ohne Programm.</summary>
    function Run(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
    /// <summary>Wie Run für einen Aufruf, der mit dem Server spricht (fetch, pull, push, svn update): LoginNeeded,
    /// wenn die Anmeldung fehlt (#1287; AKind wählt die Fehlerkennungen von git bzw. svn).</summary>
    function RunRemote(AKind: TAtlasVcsKind; const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
    property Executable: string read FExecutable;
    property WorkingDir: string read FWorkingDir;
    property TimeoutMs: Cardinal read FTimeoutMs write FTimeoutMs;
  end;

implementation

uses
  Atlas.Core.Vcs.ServerAccess;

{ TAtlasVcsToolLocation }

class function TAtlasVcsToolLocation.Empty: TAtlasVcsToolLocation;
begin
  Result.Executable := '';
  Result.Source := TAtlasVcsToolSource.None;
  Result.Configured := '';
end;

{ TAtlasVcsTools }

class constructor TAtlasVcsTools.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TAtlasVcsTools.Destroy;
begin
  FreeAndNil(FLock);
end;

class function TAtlasVcsTools.ProgramName(AKind: TAtlasVcsKind): string;
begin
  case AKind of
    TAtlasVcsKind.Git:
      Result := 'git';
    TAtlasVcsKind.Svn:
      Result := 'svn';
  else
    Result := '';
  end;
end;

class function TAtlasVcsTools.KnownDirs(AKind: TAtlasVcsKind; const AProgramDirs: TArray<string>): TArray<string>;
var
  Dir: string;
begin
  Result := nil;
  for Dir in AProgramDirs do
  begin
    if Trim(Dir) = '' then
      Continue;
    case AKind of
      TAtlasVcsKind.Git:
        Result := Result + [
          IncludeTrailingPathDelimiter(Dir) + 'Git' + PathDelim + 'cmd',
          IncludeTrailingPathDelimiter(Dir) + 'Git' + PathDelim + 'bin'];
      TAtlasVcsKind.Svn:
        Result := Result + [
          IncludeTrailingPathDelimiter(Dir) + 'TortoiseSVN' + PathDelim + 'bin',
          IncludeTrailingPathDelimiter(Dir) + 'SlikSvn' + PathDelim + 'bin',
          IncludeTrailingPathDelimiter(Dir) + 'CollabNet' + PathDelim + 'Subversion Client',
          IncludeTrailingPathDelimiter(Dir) + 'VisualSVN Server' + PathDelim + 'bin'];
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

class function TAtlasVcsTools.Locate(const AName, APath: string; const AExtraDirs: TArray<string>;
  const AExists: TAtlasVcsPathExists): string;
var
  FileName, Dir, Candidate: string;
begin
  FileName := AName;
  if PathDelim = '\' then
    FileName := FileName + '.exe';
  for Dir in APath.Split([PathSep]) + AExtraDirs do
  begin
    Candidate := Trim(Dir).Trim(['"']);
    if Candidate = '' then
      Continue;
    Candidate := IncludeTrailingPathDelimiter(Candidate) + FileName;
    if AExists(Candidate) then
      Exit(Candidate);
  end;
  Result := '';
end;

class function TAtlasVcsTools.Resolve(const AName, AConfigured, APath: string; const AExtraDirs: TArray<string>;
  const AExists: TAtlasVcsPathExists): TAtlasVcsToolLocation;
var
  mConfigured: string;
begin
  Result := TAtlasVcsToolLocation.Empty;
  mConfigured := Trim(AConfigured).Trim(['"']);
  Result.Configured := mConfigured;
  if mConfigured <> '' then
  begin
    // Ein eigener Pfad gilt allein: Wer ihn setzt, will genau dieses Programm (Ursache sichtbar, kein Ersatz).
    if AExists(mConfigured) then
    begin
      Result.Executable := mConfigured;
      Result.Source := TAtlasVcsToolSource.Configured;
    end
    else
      Result.Source := TAtlasVcsToolSource.ConfiguredMissing;
    Exit;
  end;
  Result.Executable := Locate(AName, APath, nil, AExists);
  if Result.Executable <> '' then
  begin
    Result.Source := TAtlasVcsToolSource.Path;
    Exit;
  end;
  Result.Executable := Locate(AName, '', AExtraDirs, AExists);
  if Result.Executable <> '' then
    Result.Source := TAtlasVcsToolSource.KnownDir;
end;

class procedure TAtlasVcsTools.Configure(AKind: TAtlasVcsKind; const APath: string);
var
  mPath: string;
begin
  if AKind = TAtlasVcsKind.None then
    Exit;
  mPath := Trim(APath);
  FLock.Enter;
  try
    if FConfigured[AKind] = mPath then
      Exit;
    FConfigured[AKind] := mPath;
    FFound[AKind] := TAtlasVcsToolLocation.Empty;
    FSearched[AKind] := False;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasVcsTools.Configured(AKind: TAtlasVcsKind): string;
begin
  FLock.Enter;
  try
    Result := FConfigured[AKind];
  finally
    FLock.Leave;
  end;
end;

class function TAtlasVcsTools.Probe(AKind: TAtlasVcsKind; const AConfigured: string): TAtlasVcsToolLocation;
var
  mProgramDirs: TArray<string>;
begin
  if AKind = TAtlasVcsKind.None then
    Exit(TAtlasVcsToolLocation.Empty);
  mProgramDirs := [GetEnvironmentVariable('ProgramW6432'), GetEnvironmentVariable('ProgramFiles'),
    GetEnvironmentVariable('ProgramFiles(x86)'), GetEnvironmentVariable('LOCALAPPDATA') + PathDelim + 'Programs'];
  Result := Resolve(ProgramName(AKind), AConfigured, GetEnvironmentVariable('PATH'), KnownDirs(AKind, mProgramDirs),
    function(const APath: string): Boolean
    begin
      Result := FileExists(APath);
    end);
end;

class function TAtlasVcsTools.Where(AKind: TAtlasVcsKind): TAtlasVcsToolLocation;
var
  mConfigured: string;
begin
  if AKind = TAtlasVcsKind.None then
    Exit(TAtlasVcsToolLocation.Empty);
  FLock.Enter;
  try
    if FSearched[AKind] then
      Exit(FFound[AKind]);
    mConfigured := FConfigured[AKind];
  finally
    FLock.Leave;
  end;
  Result := Probe(AKind, mConfigured);
  FLock.Enter;
  try
    // Wurde der Pfad inzwischen geändert, gilt das Ergebnis nicht mehr als gemerkt.
    if FConfigured[AKind] = mConfigured then
    begin
      FFound[AKind] := Result;
      FSearched[AKind] := True;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasVcsTools.Find(AKind: TAtlasVcsKind): string;
begin
  Result := Where(AKind).Executable;
end;

class procedure TAtlasVcsTools.Forget;
var
  Kind: TAtlasVcsKind;
begin
  FLock.Enter;
  try
    for Kind := Low(TAtlasVcsKind) to High(TAtlasVcsKind) do
    begin
      FFound[Kind] := TAtlasVcsToolLocation.Empty;
      FSearched[Kind] := False;
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasVcsTools.Preset(AKind: TAtlasVcsKind; const AExecutable: string);
begin
  FLock.Enter;
  try
    FFound[AKind] := TAtlasVcsToolLocation.Empty;
    FFound[AKind].Executable := AExecutable;
    if AExecutable <> '' then
      FFound[AKind].Source := TAtlasVcsToolSource.Path;
    FSearched[AKind] := True;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasVcsCommand }

constructor TAtlasVcsCommand.Create(const ARunner: IAtlasVcsRunner; const AExecutable, AWorkingDir: string;
  ATimeoutMs: Cardinal);
begin
  inherited Create;
  FRunner := ARunner;
  FExecutable := AExecutable;
  FWorkingDir := AWorkingDir;
  FTimeoutMs := ATimeoutMs;
end;

function TAtlasVcsCommand.Run(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
var
  Answer: TAtlasVcsRunResult;
begin
  AOutput := nil;
  if (FExecutable = '') or (FRunner = nil) then
    Exit(TAtlasVcsOutcome.ToolMissing);
  Answer := FRunner.Run(FExecutable, AArguments, FWorkingDir, FTimeoutMs);
  Result := Answer.Outcome;
  if (Result = TAtlasVcsOutcome.Ok) and (Answer.ExitCode <> 0) then
    Result := TAtlasVcsOutcome.Failed;
  if Result = TAtlasVcsOutcome.Ok then
    AOutput := Answer.Output;
end;

function TAtlasVcsCommand.RunRemote(AKind: TAtlasVcsKind; const AArguments: TArray<string>;
  out AOutput: TBytes): TAtlasVcsOutcome;
var
  Answer: TAtlasVcsRunResult;
begin
  AOutput := nil;
  if (FExecutable = '') or (FRunner = nil) then
    Exit(TAtlasVcsOutcome.ToolMissing);
  Answer := FRunner.Run(FExecutable, AArguments, FWorkingDir, FTimeoutMs);
  Result := TAtlasVcsServerAccess.OutcomeOf(AKind, Answer);
  if Result = TAtlasVcsOutcome.Ok then
    AOutput := Answer.Output;
end;

end.
