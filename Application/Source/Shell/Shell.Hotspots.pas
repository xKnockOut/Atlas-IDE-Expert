unit Shell.Hotspots;

// Host-Rolle Shell: Versionsverwaltung für die Hotspots (#1354). Setzt
// IHotspotVcs mit git bzw. svn über IAtlasVcsRunner um (wie die
// Zeilenhistorie im Plugin, Atlas.Core.Vcs.*); die Ausgaben zerlegt
// THotspotHistory.
//
//   Wahl:     nächstliegende Arbeitskopie nach vcs.provider, Programme aus
//             vcs.git.path bzw. vcs.svn.path (#1285, wie --changed).
//   Stand:    git rev-parse HEAD bzw. svn info --show-item revision -r HEAD
//   Verlauf:  git log --numstat … bzw. svn log -v --xml -r HEAD:{Datum}
//   Methode:  IAtlasVcsLineHistory.LineHistory (git log -L bzw. svn log
//             --diff, rückwärts verfolgt), gefiltert auf den Zeitraum
//   Damals:   git rev-list -1 --before=… HEAD und git show <Commit>:<Pfad>
//             bzw. svn cat ^/<Pfad>@{Datum}
//
// Alle Aufrufe ohne Rückfrage (Prozessläufer), mit Zeitlimit; der Server ist
// kein Fenster und darf auch im Hauptthread warten.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Core.Vcs.Contract;

type
  TShellHotspotVcs = class(TInterfacedObject, IHotspotVcs)
  public const
    /// <summary>Höchstens so viele Commits je Methode (git log -L --max-count, SVN durchsuchte Revisionen).</summary>
    MaxLineRevisions = 200;
  private
    FKind: THotspotVcsKind;
    FRoot: string;
    FExecutable: string;
    FRunner: IAtlasVcsRunner;
    FLines: IAtlasVcsLineHistory;
    FTimeoutMs: Cardinal;
    /// <summary>SVN: Pfad der Arbeitskopie im Repository wie "/trunk" ('' bis zur ersten Abfrage).</summary>
    FPrefix: string;
    function Run(const AArguments: TArray<string>; ATimeoutMs: Cardinal; out AText, AError: string): Boolean;
      overload;
    /// <summary>Wie oben mit dem Exit-Code (-1, wenn der Prozess nicht regulär endete) und stderr. stderr nennt
    /// Pfade und gehört weder in AError noch ins Protokoll; nur zum Erkennen fester Fehlerkennungen.</summary>
    function Run(const AArguments: TArray<string>; ATimeoutMs: Cardinal; out AText, AError: string;
      out AExitCode: Integer; out AErrorText: string): Boolean; overload;
    function SvnPrefix(out APrefix, AError: string): Boolean;
  public
    constructor Create(AKind: THotspotVcsKind; const ARoot, AExecutable: string; const ARunner: IAtlasVcsRunner;
      const ALines: IAtlasVcsLineHistory; ATimeoutMs: Cardinal);
    /// <summary>Versionsverwaltung für AFolder nach vcs.* in ASettings; False mit AError ohne Arbeitskopie, bei
    /// vcs.provider = off oder fehlendem Programm.</summary>
    class function Detect(const AFolder: string; const ASettings: TServerSettings; out AVcs: IHotspotVcs;
      out AError: string): Boolean; static;
    function Kind: THotspotVcsKind;
    function Root: string;
    function Head: string;
    function Log(ASince: TDateTime; out ACommits: TArray<THotspotCommit>; out AError: string): Boolean;
    function LineLog(const AFileName: string; AFirstLine, ALastLine: Integer; ASince: TDateTime;
      out ACommits: TArray<THotspotLineCommit>): Boolean;
    function TextAt(const AFileName: string; ADate: TDateTime; out AText: string): THotspotTextState;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Core.Vcs.Detection,
  Atlas.Core.Vcs.Composition,
  Atlas.Common.Hotspots.History,
  Shell.Platform,
  Shell.VcsChanges;

const
  /// <summary>Der Verlauf eines Jahres großer Repositorys braucht mehr als die üblichen Abfragen.</summary>
  cLogTimeoutMs = 300000;

{ TShellHotspotVcs }

constructor TShellHotspotVcs.Create(AKind: THotspotVcsKind; const ARoot, AExecutable: string;
  const ARunner: IAtlasVcsRunner; const ALines: IAtlasVcsLineHistory; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FKind := AKind;
  FRoot := ExcludeTrailingPathDelimiter(ARoot);
  FExecutable := AExecutable;
  FRunner := ARunner;
  FLines := ALines;
  FTimeoutMs := ATimeoutMs;
end;

class function TShellHotspotVcs.Detect(const AFolder: string; const ASettings: TServerSettings;
  out AVcs: IHotspotVcs; out AError: string): Boolean;
var
  mProvider: TAtlasVcsProvider;
  mWorkingCopy: TAtlasVcsWorkingCopy;
  mExecutable: string;
  mKind: THotspotVcsKind;
  mRunner: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mLines: IAtlasVcsLineHistory;
  mTimeoutMs: Cardinal;
begin
  AVcs := nil;
  AError := '';
  mExecutable := '';
  mProvider := AtlasVcsProviderOf(ASettings.VcsProvider);
  if mProvider = TAtlasVcsProvider.Off then
  begin
    AError := 'Versionsverwaltung abgeschaltet (vcs.provider = off)';
    Exit(False);
  end;
  mWorkingCopy := TAtlasVcsDetection.Find(AFolder, mProvider);
  try
    case mWorkingCopy.Kind of
      TAtlasVcsKind.Git:
        begin
          mKind := THotspotVcsKind.Git;
          mExecutable := TVcsChanges.ToolFor(TAtlasVcsKind.Git, ASettings.VcsGitPath);
        end;
      TAtlasVcsKind.Svn:
        begin
          mKind := THotspotVcsKind.Svn;
          mExecutable := TVcsChanges.ToolFor(TAtlasVcsKind.Svn, ASettings.VcsSvnPath);
        end;
    else
      AError := Format('%s liegt weder in einem Git-Repository noch in einer SVN-Arbeitskopie', [AFolder]);
      Exit(False);
    end;
  except
    on E: EVcsChanges do
    begin
      AError := E.Message;
      Exit(False);
    end;
  end;
  if mExecutable = '' then
  begin
    AError := Format('%s ist nicht installiert (vcs.%s.path)', [AtlasVcsKindName(mWorkingCopy.Kind),
      THotspots.KindName(mKind)]);
    Exit(False);
  end;
  mTimeoutMs := 30000;
  if (ASettings.VcsTimeoutSeconds >= 1) and (ASettings.VcsTimeoutSeconds <= 300) then
    mTimeoutMs := Cardinal(ASettings.VcsTimeoutSeconds) * 1000 * 4;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mVcs := TAtlasVersionControl.ForWorkingCopy(mWorkingCopy, mRunner, mExecutable, mTimeoutMs);
  if not Supports(mVcs, IAtlasVcsLineHistory, mLines) then
    mLines := nil;
  AVcs := TShellHotspotVcs.Create(mKind, mWorkingCopy.Root, mExecutable, mRunner, mLines, mTimeoutMs);
  Result := True;
end;

function TShellHotspotVcs.Run(const AArguments: TArray<string>; ATimeoutMs: Cardinal;
  out AText, AError: string): Boolean;
var
  mExitCode: Integer;
  mErrorText: string;
begin
  Result := Run(AArguments, ATimeoutMs, AText, AError, mExitCode, mErrorText);
end;

function TShellHotspotVcs.Run(const AArguments: TArray<string>; ATimeoutMs: Cardinal; out AText, AError: string;
  out AExitCode: Integer; out AErrorText: string): Boolean;
var
  mResult: TAtlasVcsRunResult;
  mArguments: TArray<string>;
begin
  AText := '';
  AError := '';
  if FKind = THotspotVcsKind.Git then
    // Pfade mit Umlauten unverändert (UTF-8), keine Sperren im Repository.
    mArguments := TArray<string>.Create('--no-optional-locks', '-c', 'core.quotepath=off', '-c',
      'i18n.logOutputEncoding=UTF-8') + AArguments
  else
    mArguments := AArguments;
  mResult := FRunner.Run(FExecutable, mArguments, FRoot, ATimeoutMs);
  AExitCode := mResult.ExitCode;
  AErrorText := mResult.ErrorText;
  if mResult.Outcome <> TAtlasVcsOutcome.Ok then
    AExitCode := -1;
  Result := (mResult.Outcome = TAtlasVcsOutcome.Ok) and (mResult.ExitCode = 0);
  if Result then
    AText := TEncoding.UTF8.GetString(mResult.Output)
  else if mResult.Outcome <> TAtlasVcsOutcome.Ok then
    AError := Format('%s: %s', [ExtractFileName(FExecutable), AtlasVcsOutcomeName(mResult.Outcome)])
  else
    AError := Format('%s %s ist fehlgeschlagen (Exit-Code %d)', [ExtractFileName(FExecutable), AArguments[0],
      mResult.ExitCode]);
end;

function TShellHotspotVcs.SvnPrefix(out APrefix, AError: string): Boolean;
var
  mText: string;
begin
  if FPrefix <> '' then
  begin
    APrefix := FPrefix;
    AError := '';
    Exit(True);
  end;
  Result := Run(['info', '--non-interactive', '--show-item', 'relative-url', FRoot], FTimeoutMs, mText, AError);
  APrefix := '';
  if not Result then
    Exit;
  // "^/trunk" → "/trunk"; die Wurzel des Repositorys ist "^/".
  mText := Trim(mText);
  if StartsStr('^', mText) then
    Delete(mText, 1, 1);
  if mText = '' then
    mText := '/';
  FPrefix := mText;
  APrefix := mText;
end;

function TShellHotspotVcs.Kind: THotspotVcsKind;
begin
  Result := FKind;
end;

function TShellHotspotVcs.Root: string;
begin
  Result := FRoot;
end;

function TShellHotspotVcs.Head: string;
var
  mText, mError: string;
begin
  if FKind = THotspotVcsKind.Git then
  begin
    if not Run(['rev-parse', 'HEAD'], FTimeoutMs, mText, mError) then
      mText := '';
  end
  else if not Run(['info', '--non-interactive', '--show-item', 'revision', '-r', 'HEAD', FRoot], FTimeoutMs, mText,
    mError) then
    mText := '';
  Result := Trim(mText);
end;

function TShellHotspotVcs.Log(ASince: TDateTime; out ACommits: TArray<THotspotCommit>; out AError: string): Boolean;
var
  mText, mPrefix: string;
begin
  ACommits := nil;
  if FKind = THotspotVcsKind.Git then
  begin
    Result := Run(THotspotHistory.GitLogArguments(ASince), cLogTimeoutMs, mText, AError);
    if Result then
      ACommits := THotspotHistory.ParseGitLog(mText);
  end
  else
  begin
    Result := SvnPrefix(mPrefix, AError) and Run(THotspotHistory.SvnLogArguments(ASince, FRoot), cLogTimeoutMs, mText,
      AError);
    if Result then
      ACommits := THotspotHistory.ParseSvnLog(mText, mPrefix);
  end;
end;

function TShellHotspotVcs.LineLog(const AFileName: string; AFirstLine, ALastLine: Integer; ASince: TDateTime;
  out ACommits: TArray<THotspotLineCommit>): Boolean;
var
  mCommits: TArray<TAtlasVcsLineCommit>;
  mCommit: TAtlasVcsLineCommit;
  mItem: THotspotLineCommit;
  mMessage: string;
begin
  ACommits := nil;
  Result := (FLines <> nil) and (FLines.LineHistory(AFileName, AFirstLine, ALastLine, MaxLineRevisions,
    mCommits) = TAtlasVcsOutcome.Ok);
  if not Result then
    Exit;
  for mCommit in mCommits do
  begin
    // Neueste zuerst: ab dem ersten älteren Commit liegt alles vor dem Zeitraum.
    if mCommit.Date < ASince then
      Break;
    mItem := Default(THotspotLineCommit);
    mItem.Revision := mCommit.Revision;
    mItem.Author := mCommit.Author;
    mItem.Date := mCommit.Date;
    mMessage := Trim(mCommit.Message);
    if Pos(#10, mMessage) > 0 then
      mMessage := Trim(Copy(mMessage, 1, Pos(#10, mMessage) - 1));
    mItem.Summary := mMessage;
    THotspotHistory.CountPatch(mCommit.Patch, mItem.Added, mItem.Deleted);
    ACommits := ACommits + [mItem];
  end;
end;

function TShellHotspotVcs.TextAt(const AFileName: string; ADate: TDateTime; out AText: string): THotspotTextState;
var
  mRevision, mError, mPrefix, mErrorText: string;
  mExitCode: Integer;
begin
  AText := '';
  if (AFileName = '') or StartsStr('-', AFileName) then
    Exit(THotspotTextState.Unknown);
  Result := THotspotTextState.Unknown;
  if FKind = THotspotVcsKind.Git then
  begin
    // Ohne Commit vor dem Datum reicht der Verlauf nicht so weit (neues oder flach geklontes Repository).
    if not Run(['rev-list', '-1', '--before=' + THotspotHistory.IsoDate(ADate), 'HEAD'], FTimeoutMs, mRevision,
      mError) or (Trim(mRevision) = '') then
      Exit;
    if Run(['show', Trim(mRevision) + ':' + AFileName], FTimeoutMs, AText, mError, mExitCode, mErrorText) then
      Result := THotspotTextState.Found
    else if mExitCode = 128 then
      // fatal: path '…' does not exist in '…'
      Result := THotspotTextState.Missing;
  end
  else if SvnPrefix(mPrefix, mError) then
  begin
    if not EndsStr('/', mPrefix) then
      mPrefix := mPrefix + '/';
    // Peg-Revision am Datum: der Pfad gilt in jenem Stand, auch wenn die Datei heute anders heißt.
    if Run(['cat', '--non-interactive', '^' + mPrefix + AFileName + '@{' + THotspotHistory.IsoDate(ADate) + '}'],
      FTimeoutMs, AText, mError, mExitCode, mErrorText) then
      Result := THotspotTextState.Found
    else if (Pos('E160013', mErrorText) > 0) or (Pos('E195012', mErrorText) > 0) then
      // Pfad nicht gefunden bzw. nicht mit der Peg-Revision verbunden.
      Result := THotspotTextState.Missing;
  end;
  if Result <> THotspotTextState.Found then
    AText := '';
end;

end.
