unit Shell.SymbolHistory;

// Host-Rolle Shell: Versionsverwaltung der Symbolgeschichte (#2641). Setzt ISymbolHistoryVcs mit git bzw. svn um,
// auf derselben Grundlage wie die Hotspots (TShellHotspotVcs: Wahl der Arbeitskopie, Programm, Zeitlimit).
//
//   Zeilen:   git log --format=… --max-count=N --no-ext-diff -L<a>,<b>:<Pfad> <Stand>; SVN nur im heutigen Stand
//             über IAtlasVcsLineHistory.LineHistory (svn log --diff)
//   Commit:   git show --format= --name-status -M <Commit>
//   Text:     git show <Stand>[^]:<Pfad> bzw. svn cat -r BASE <Pfad>
//
// Umbenennen und Verschieben über ältere Stände gibt es nur mit Git.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Contract,
  Shell.Hotspots;

type
  TShellSymbolHistoryVcs = class(TShellHotspotVcs, ISymbolHistoryVcs)
  private
    function GitLineLog(const APath, ARevision: string; AFirstLine, ALastLine, AMaxCount: Integer;
      out ACommits: TArray<TSymbolLineCommit>): Boolean;
    function SvnLineLog(const APath: string; AFirstLine, ALastLine, AMaxCount: Integer;
      out ACommits: TArray<TSymbolLineCommit>): Boolean;
    function FullPath(const APath: string): string;
  public
    function ISymbolHistoryVcs.LineLog = SymbolLineLog;
    function ISymbolHistoryVcs.TextAt = SymbolTextAt;
    function SymbolLineLog(const APath, ARevision: string; AFirstLine, ALastLine, AMaxCount: Integer;
      out ACommits: TArray<TSymbolLineCommit>): Boolean;
    function CommitFiles(const ARevision: string; out AFiles: TArray<THotspotFileChange>): Boolean;
    function SymbolTextAt(const APath, ARevision: string; ABefore: Boolean; out AText: string): THotspotTextState;
    /// <summary>Versionsverwaltung für AFolder nach vcs.* in ASettings; False mit AError wie
    /// TShellHotspotVcs.Detect.</summary>
    class function DetectHistory(const AFolder: string; const ASettings: TServerSettings;
      out AVcs: ISymbolHistoryVcs; out AError: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Common.History.Commits;

/// <summary>Pfad oder Stand, der für git wie eine Option aussähe.</summary>
function LooksLikeOption(const AText: string): Boolean;
begin
  Result := StartsStr('-', AText);
end;

/// <summary>Taugt die Anfrage für git bzw. svn: Pfad und Stand ohne "-" vorn, Bereich und Anzahl ab 1.</summary>
function ValidLineQuery(const APath, ARevision: string; AFirstLine, ALastLine, AMaxCount: Integer): Boolean;
begin
  Result := (APath <> '') and not LooksLikeOption(APath) and not LooksLikeOption(ARevision);
  Result := Result and (AFirstLine >= 1) and (ALastLine >= AFirstLine) and (AMaxCount >= 1);
end;

function LineCommitOf(const ACommit: TAtlasVcsLineCommit): TSymbolLineCommit;
begin
  Result.Revision := ACommit.Revision;
  Result.Author := ACommit.Author;
  Result.Date := ACommit.Date;
  Result.Message := ACommit.Message;
  Result.Patch := Copy(ACommit.Patch);
end;

function LineCommitsOf(const ACommits: TArray<TAtlasVcsLineCommit>): TArray<TSymbolLineCommit>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ACommits));
  for mIndex := 0 to High(ACommits) do
  begin
    Result[mIndex] := LineCommitOf(ACommits[mIndex]);
  end;
end;

{ TShellSymbolHistoryVcs }

class function TShellSymbolHistoryVcs.DetectHistory(const AFolder: string; const ASettings: TServerSettings;
  out AVcs: ISymbolHistoryVcs; out AError: string): Boolean;
var
  mVcs: IHotspotVcs;
begin
  AVcs := nil;
  Result := TShellSymbolHistoryVcs.Detect(AFolder, ASettings, mVcs, AError) and Supports(mVcs, ISymbolHistoryVcs,
    AVcs);
end;

function TShellSymbolHistoryVcs.FullPath(const APath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FRoot) + APath.Replace('/', PathDelim);
end;

function TShellSymbolHistoryVcs.GitLineLog(const APath, ARevision: string; AFirstLine, ALastLine,
  AMaxCount: Integer; out ACommits: TArray<TSymbolLineCommit>): Boolean;
var
  mRevision, mText, mError: string;
begin
  ACommits := nil;
  mRevision := ARevision;
  if mRevision = '' then
  begin
    mRevision := 'HEAD';
  end;
  Result := Run(['log', '--format=' + TSymbolCommits.cLineLogFormat, '--max-count=' + IntToStr(AMaxCount),
    '--no-ext-diff', '-L' + IntToStr(AFirstLine) + ',' + IntToStr(ALastLine) + ':' + APath, mRevision], FTimeoutMs,
    mText, mError);
  if Result then
  begin
    ACommits := TSymbolCommits.ParseLineLog(mText);
  end;
end;

function TShellSymbolHistoryVcs.SvnLineLog(const APath: string; AFirstLine, ALastLine, AMaxCount: Integer;
  out ACommits: TArray<TSymbolLineCommit>): Boolean;
var
  mCommits: TArray<TAtlasVcsLineCommit>;
begin
  ACommits := nil;
  Result := (FLines <> nil) and (FLines.LineHistory(FullPath(APath), AFirstLine, ALastLine, AMaxCount,
    mCommits) = TAtlasVcsOutcome.Ok);
  if Result then
  begin
    ACommits := LineCommitsOf(mCommits);
  end;
end;

function TShellSymbolHistoryVcs.SymbolLineLog(const APath, ARevision: string; AFirstLine, ALastLine,
  AMaxCount: Integer; out ACommits: TArray<TSymbolLineCommit>): Boolean;
begin
  ACommits := nil;
  if not ValidLineQuery(APath, ARevision, AFirstLine, ALastLine, AMaxCount) then
  begin
    Exit(False);
  end;
  if FKind = THotspotVcsKind.Git then
  begin
    Result := GitLineLog(APath, ARevision, AFirstLine, ALastLine, AMaxCount, ACommits);
  end
  else
  begin
    Result := (ARevision = '') and SvnLineLog(APath, AFirstLine, ALastLine, AMaxCount, ACommits);
  end;
end;

function TShellSymbolHistoryVcs.CommitFiles(const ARevision: string; out AFiles: TArray<THotspotFileChange>): Boolean;
var
  mText, mError: string;
begin
  AFiles := nil;
  Result := (FKind = THotspotVcsKind.Git) and (ARevision <> '') and not LooksLikeOption(ARevision) and
    Run(['show', '--format=', '--name-status', '-M', ARevision], FTimeoutMs, mText, mError);
  if Result then
  begin
    AFiles := TSymbolCommits.ParseNameStatus(mText);
  end;
end;

function TShellSymbolHistoryVcs.SymbolTextAt(const APath, ARevision: string; ABefore: Boolean;
  out AText: string): THotspotTextState;
var
  mRevision, mError, mErrorText: string;
  mArguments: TArray<string>;
  mExitCode: Integer;
begin
  AText := '';
  Result := THotspotTextState.Unknown;
  if (APath = '') or LooksLikeOption(APath) or LooksLikeOption(ARevision) then
  begin
    Exit;
  end;
  if FKind = THotspotVcsKind.Git then
  begin
    mRevision := ARevision;
    if mRevision = '' then
    begin
      mRevision := 'HEAD';
    end;
    if ABefore then
    begin
      mRevision := mRevision + '^';
    end;
    mArguments := TArray<string>.Create('show', mRevision + ':' + APath);
  end
  else if (ARevision = '') and not ABefore then
  begin
    mArguments := TArray<string>.Create('cat', '--non-interactive', '-r', 'BASE', FullPath(APath));
  end
  else
  begin
    Exit;
  end;
  if Run(mArguments, FTimeoutMs, AText, mError, mExitCode, mErrorText) then
  begin
    Result := THotspotTextState.Found;
  end
  else
  begin
    AText := '';
    // Git: fatal: path '…' does not exist in '…' (Exit-Code 128); SVN: Pfad nicht unter Versionskontrolle.
    if (mExitCode = 128) or (Pos('E200009', mErrorText) > 0) or (Pos('E155010', mErrorText) > 0) then
    begin
      Result := THotspotTextState.Missing;
    end;
  end;
end;

end.
