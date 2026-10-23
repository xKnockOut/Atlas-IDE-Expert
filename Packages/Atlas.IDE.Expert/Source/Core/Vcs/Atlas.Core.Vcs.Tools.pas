unit Atlas.Core.Vcs.Tools;

// Findet git und svn auf dem Rechner (#571) und startet sie über
// IAtlasVcsRunner. Gesucht wird in PATH und in den üblichen
// Installationsordnern (Git für Windows, TortoiseSVN mit
// Kommandozeilenwerkzeugen, SlikSVN, CollabNet, VisualSVN); das Ergebnis
// merkt sich Find für die Sitzung. Fehlt das Programm, liefert jeder Aufruf
// Outcome ToolMissing.
// TAtlasVcsCommand bündelt Programm, Arbeitsverzeichnis und Zeitlimit einer
// Umsetzung; die Ausgabe des Programms geht nie ins Protokoll (Pfade).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Vcs.Contract;

type
  TAtlasVcsPathExists = reference to function(const APath: string): Boolean;

  TAtlasVcsTools = class
  private class var
    FLock: TCriticalSection;
    FFound: array[TAtlasVcsKind] of string;
    FSearched: array[TAtlasVcsKind] of Boolean;
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
    /// <summary>git bzw. svn auf diesem Rechner; '' wenn nicht installiert. Merkt sich das Ergebnis.</summary>
    class function Find(AKind: TAtlasVcsKind): string; static;
    /// <summary>Vergessen, was Find gefunden hat (Tests, nach Installation).</summary>
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
    property Executable: string read FExecutable;
    property WorkingDir: string read FWorkingDir;
    property TimeoutMs: Cardinal read FTimeoutMs write FTimeoutMs;
  end;

implementation

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

class function TAtlasVcsTools.Find(AKind: TAtlasVcsKind): string;
var
  ProgramDirs: TArray<string>;
begin
  if AKind = TAtlasVcsKind.None then
    Exit('');
  FLock.Enter;
  try
    if FSearched[AKind] then
      Exit(FFound[AKind]);
  finally
    FLock.Leave;
  end;
  ProgramDirs := [GetEnvironmentVariable('ProgramW6432'), GetEnvironmentVariable('ProgramFiles'),
    GetEnvironmentVariable('ProgramFiles(x86)'), GetEnvironmentVariable('LOCALAPPDATA') + PathDelim + 'Programs'];
  Result := Locate(ProgramName(AKind), GetEnvironmentVariable('PATH'), KnownDirs(AKind, ProgramDirs),
    function(const APath: string): Boolean
    begin
      Result := FileExists(APath);
    end);
  FLock.Enter;
  try
    FFound[AKind] := Result;
    FSearched[AKind] := True;
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasVcsTools.Forget;
var
  Kind: TAtlasVcsKind;
begin
  FLock.Enter;
  try
    for Kind := Low(TAtlasVcsKind) to High(TAtlasVcsKind) do
    begin
      FFound[Kind] := '';
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
    FFound[AKind] := AExecutable;
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

end.
