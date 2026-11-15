unit Atlas.Core.Tracker.DevelopmentPlan;

// Entscheidungen des Reiters „Entwicklung“ (#1269) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.Development)
// ruft nur noch Ansicht, Versionsverwaltung, Tracker und Navigation:
// - Ob ein anderes Issue gewählt ist, welche Basis-Branches verglichen werden und was der Tracker meldet, wenn er
//   nicht abgefragt werden kann oder nicht geantwortet hat.
// - Diff eines Commits: höchstens cMaxDiffFiles Dateien, Anzeigename relativ, beim ersten Lesefehler Schluss.
// - Kurze Revision im Titel und Rückfrage vor dem Wechseln nur mit lokalen Änderungen.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.VersionControl.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zeile zum Tracker, wenn er nicht geantwortet hat: keine, Token, Zeitgrenze, nicht eingerichtet,
  /// ungültige Antwort, Netz.</summary>
  TAtlasIssueDevNote = (None, Token, Timeout, Config, Invalid, Network);
{$SCOPEDENUMS OFF}

  /// <summary>Inhalt von AFile im Commit (ABefore: davor) als Text.</summary>
  TAtlasIssueDevContent = reference to function(const AFile: TAtlasVcsLogFile; ABefore: Boolean;
    out AText: string): TAtlasVcsOutcome;

  TAtlasIssueDevelopmentPlan = class
  public const
    /// <summary>Höchstens so viele Dateien im Diff eines Commits.</summary>
    cMaxDiffFiles = 30;
    /// <summary>Revisionen über so viele Zeichen sind Hashes (Git) und werden gekürzt.</summary>
    cLongRevision = 10;
    /// <summary>Länge der gekürzten Revision.</summary>
    cShortRevision = 7;
  public
    /// <summary>Gilt AKey bei ATarget schon (AHasCurrent: es gibt ein aktuelles Issue AOldKey bei AOld)?</summary>
    class function SameIssue(AHasCurrent: Boolean; const AOld: TAtlasTrackerTarget; const AOldKey: string;
      const ATarget: TAtlasTrackerTarget; const AKey: string): Boolean; static;
    /// <summary>Basis-Branches zum Vergleich: issues.branchBase, sonst main, master.</summary>
    class function Bases(const ABranchBase: string): TArray<string>; static;
    /// <summary>Fehler, wenn der Tracker gar nicht abgefragt werden kann (ohne Anbieter bzw. Token); None sonst.
    /// </summary>
    class function Unreachable(AHasProvider, AHasTransport: Boolean): TAtlasCiFetchError; static;
    /// <summary>Zeile zum Tracker; None, wenn er geantwortet hat bzw. nicht gefragt oder abgebrochen wurde.</summary>
    class function NoteOf(const ADevelopment: TAtlasIssueDevelopment): TAtlasIssueDevNote; static;
    /// <summary>Kurze Revision für den Titel: lange Hashes auf 7 Zeichen, sonst unverändert.</summary>
    class function ShortRevision(const ARevision: string): string; static;
    /// <summary>Vor dem Wechseln fragen (nur mit lokalen Änderungen)?</summary>
    class function AsksSwitch(AChanges: Integer): Boolean; static;
    /// <summary>Anzeigename einer Datei im Diff: Pfad im Repository, sonst in der Arbeitskopie.</summary>
    class function DiffCaption(const AFile: TAtlasVcsLogFile): string; static;
    /// <summary>Diff aller Dateien von AEntry (höchstens cMaxDiffFiles) über AContent; beim ersten Fehler dessen
    /// Ergebnis.</summary>
    class function CommitDiff(const AEntry: TAtlasVcsLogEntry; const AContent: TAtlasIssueDevContent;
      out AFiles: TArray<TAtlasIssueFileDiff>): TAtlasVcsOutcome; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasIssueDevelopmentPlan.SameIssue(AHasCurrent: Boolean; const AOld: TAtlasTrackerTarget;
  const AOldKey: string; const ATarget: TAtlasTrackerTarget; const AKey: string): Boolean;
begin
  Result := AHasCurrent and SameText(AOld.Key, ATarget.Key) and SameText(AOldKey, AKey);
end;

class function TAtlasIssueDevelopmentPlan.Bases(const ABranchBase: string): TArray<string>;
begin
  // SVN vergleicht nicht (Distance = -1); trunk liegt nicht unter ^/branches.
  if Trim(ABranchBase) <> '' then
  begin
    Result := TArray<string>.Create(Trim(ABranchBase));
  end
  else
  begin
    Result := TArray<string>.Create('main', 'master');
  end;
end;

class function TAtlasIssueDevelopmentPlan.Unreachable(AHasProvider, AHasTransport: Boolean): TAtlasCiFetchError;
begin
  Result := TAtlasCiFetchError.None;
  if not AHasProvider then
  begin
    Result := TAtlasCiFetchError.NotConfigured;
  end
  else if not AHasTransport then
  begin
    Result := TAtlasCiFetchError.Unauthorized;
  end;
end;

class function TAtlasIssueDevelopmentPlan.NoteOf(const ADevelopment: TAtlasIssueDevelopment): TAtlasIssueDevNote;
begin
  if ADevelopment.TrackerLoaded or (ADevelopment.TrackerError in [TAtlasCiFetchError.None,
    TAtlasCiFetchError.Cancelled]) then
  begin
    Exit(TAtlasIssueDevNote.None);
  end;
  case ADevelopment.TrackerError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasIssueDevNote.Token;
    TAtlasCiFetchError.Timeout:
      Result := TAtlasIssueDevNote.Timeout;
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasIssueDevNote.Config;
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server, TAtlasCiFetchError.NotFound:
      Result := TAtlasIssueDevNote.Invalid;
  else
    Result := TAtlasIssueDevNote.Network;
  end;
end;

class function TAtlasIssueDevelopmentPlan.ShortRevision(const ARevision: string): string;
begin
  Result := ARevision;
  if Length(Result) > cLongRevision then
  begin
    Result := Copy(Result, 1, cShortRevision);
  end;
end;

class function TAtlasIssueDevelopmentPlan.AsksSwitch(AChanges: Integer): Boolean;
begin
  Result := AChanges > 0;
end;

class function TAtlasIssueDevelopmentPlan.DiffCaption(const AFile: TAtlasVcsLogFile): string;
begin
  Result := AFile.RepositoryPath;
  if Result = '' then
  begin
    Result := AFile.Path;
  end;
end;

class function TAtlasIssueDevelopmentPlan.CommitDiff(const AEntry: TAtlasVcsLogEntry;
  const AContent: TAtlasIssueDevContent; out AFiles: TArray<TAtlasIssueFileDiff>): TAtlasVcsOutcome;
var
  mFile: TAtlasVcsLogFile;
  mCount: Integer;
begin
  AFiles := nil;
  SetLength(AFiles, Length(AEntry.Files));
  mCount := 0;
  Result := TAtlasVcsOutcome.Ok;
  for mFile in AEntry.Files do
  begin
    if mCount >= cMaxDiffFiles then
    begin
      Break;
    end;
    AFiles[mCount] := Default(TAtlasIssueFileDiff);
    AFiles[mCount].Caption := DiffCaption(mFile);
    Result := AContent(mFile, True, AFiles[mCount].Before);
    if Result = TAtlasVcsOutcome.Ok then
    begin
      Result := AContent(mFile, False, AFiles[mCount].After);
    end;
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      Break;
    end;
    Inc(mCount);
  end;
  SetLength(AFiles, mCount);
end;

end.
