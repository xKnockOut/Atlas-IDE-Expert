unit Atlas.Core.Tracker.BlameLinks;

// Issues in der Zeilenhistorie (#1275), ohne VCL, Open Tools API und Netz.
// - Keys und CaptionSuffix: Kennungen einer Commit-Nachricht (Erkennung wie im
//   Quelltext, Atlas.Core.Tracker.CodeLinks) für die Randanzeige
//   „anna, vor 3 Mon. · ATL-97“. Git-blame liefert nur die erste Zeile, SVN gar
//   keine Nachricht; die ganzen Nachrichten holt die Zeilenhistorie einmal je
//   blame (IAtlasVcsLineHistory.Messages, BlameRevisions).
// - Scope: Bereich für „Issues zu dieser Methode“: innerster Methodenrumpf um
//   die Cursorzeile (TAtlasMethodToggle, TAtlasBookmarks.MethodAt), außerhalb
//   jeder Methode die ganze Unit.
// - RepositoryRange: git log -L und svn log zählen Zeilen im Stand des
//   Repositorys (Git HEAD, SVN BASE); der Puffer kann davon abweichen
//   (ungespeichert, nicht übernommen). Die Zeilen werden über den
//   Zeilenvergleich zugeordnet; neue Zeilen am Rand des Bereichs fallen weg.
// - Group: Commits (neueste zuerst) je Kennung, mit Anzahl und Zeit des
//   neuesten; Issues mit dem neuesten Commit zuerst, bei Gleichstand nach
//   Kennung. Commits ohne Kennung zählen nur.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Tracker.CodeLinks;

type
  /// <summary>Issue mit den Commits, die einen Bereich geändert haben.</summary>
  TAtlasBlameIssue = record
    /// <summary>Erste Fundstelle der Kennung (Key, IssueKey, IssueTarget).</summary>
    Match: TAtlasIssueKeyMatch;
    /// <summary>Indizes in TAtlasBlameIssueList.Commits, neueste zuerst.</summary>
    Commits: TArray<Integer>;
    /// <summary>Zeit des neuesten Commits (UTC).</summary>
    LastDate: TDateTime;
  end;

  TAtlasBlameIssueList = record
    /// <summary>Alle Commits des Bereichs, neueste zuerst.</summary>
    Commits: TArray<TAtlasVcsLineCommit>;
    Issues: TArray<TAtlasBlameIssue>;
    /// <summary>Commits ohne Kennung.</summary>
    Unlinked: Integer;
  end;

  TAtlasBlameLinks = class
  public
    /// <summary>Kennungen in AMessage ohne Doppelte, in der Reihenfolge des Auftretens.</summary>
    class function Keys(const APattern: TAtlasIssueKeyPattern; const AMessage: string): TArray<TAtlasIssueKeyMatch>;
      static;
    /// <summary>" · ATL-97" bzw. " · ATL-97, ATL-98" für die Randanzeige; '' ohne Kennung.</summary>
    class function CaptionSuffix(const AKeys: TArray<TAtlasIssueKeyMatch>): string; static;
    /// <summary>ACommits (neueste zuerst) nach Kennung gruppiert.</summary>
    class function Group(const APattern: TAtlasIssueKeyPattern; const ACommits: TArray<TAtlasVcsLineCommit>):
      TAtlasBlameIssueList; static;
    /// <summary>Bereich für ALine (0-basiert) in AText: innerster Methodenrumpf (True, AName voll qualifiziert)
    /// oder die ganze Unit (False, AName ''). AFirst und ALast 0-basiert.</summary>
    class function Scope(const AText: string; ALine: Integer; out AFirst, ALast: Integer; out AName: string): Boolean;
      static;
    /// <summary>AFirst..ALast (0-basiert in ABuffer) im Stand ARepository, 1-basiert für git und svn; False, wenn
    /// keine Zeile des Bereichs im Repository steht.</summary>
    class function RepositoryRange(const ARepository, ABuffer: TArray<string>; AFirst, ALast: Integer;
      out ARepositoryFirst, ARepositoryLast: Integer): Boolean; static;
    /// <summary>Revisionen aus blame ohne Doppelte und ohne nicht übernommene Zeilen, in Reihenfolge.</summary>
    class function BlameRevisions(const ALines: TArray<TAtlasVcsBlameLine>): TArray<string>; static;
    /// <summary>Kurzform: Git 7 Zeichen, SVN „r123“.</summary>
    class function ShortRevision(AKind: TAtlasVcsKind; const ARevision: string): string; static;
    /// <summary>Erste nicht leere Zeile von AMessage.</summary>
    class function Subject(const AMessage: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Diff,
  Atlas.Core.Editor.LineChanges,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Bookmarks.Store;

{ TAtlasBlameLinks }

class function TAtlasBlameLinks.Keys(const APattern: TAtlasIssueKeyPattern; const AMessage: string):
  TArray<TAtlasIssueKeyMatch>;
begin
  Result := nil;
  if APattern.Active and (AMessage <> '') then
    Result := TAtlasCodeLinks.DistinctKeys(TAtlasCodeLinks.FindKeys(APattern, AMessage));
end;

class function TAtlasBlameLinks.CaptionSuffix(const AKeys: TArray<TAtlasIssueKeyMatch>): string;
var
  mMatch: TAtlasIssueKeyMatch;
begin
  Result := '';
  for mMatch in AKeys do
  begin
    if Result = '' then
      Result := ' · '
    else
      Result := Result + ', ';
    Result := Result + mMatch.Key;
  end;
end;

/// <summary>Kommt A vor B? Neuester Commit zuerst, dann Kennung.</summary>
function Before(const A, B: TAtlasBlameIssue): Boolean;
var
  mCompare: Integer;
begin
  if A.LastDate <> B.LastDate then
    Exit(A.LastDate > B.LastDate);
  mCompare := CompareText(A.Match.Key, B.Match.Key);
  if mCompare <> 0 then
    Exit(mCompare < 0);
  Result := CompareStr(A.Match.Key, B.Match.Key) < 0;
end;

class function TAtlasBlameLinks.Group(const APattern: TAtlasIssueKeyPattern;
  const ACommits: TArray<TAtlasVcsLineCommit>): TAtlasBlameIssueList;
var
  mIndexOf: TDictionary<string, Integer>;
  mCommit, mIssue, mInsert: Integer;
  mMatch: TAtlasIssueKeyMatch;
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mItem: TAtlasBlameIssue;
  mName: string;
begin
  Result.Commits := ACommits;
  Result.Issues := nil;
  Result.Unlinked := 0;
  mIndexOf := TDictionary<string, Integer>.Create;
  try
    for mCommit := 0 to High(ACommits) do
    begin
      mMatches := Keys(APattern, ACommits[mCommit].Message);
      if Length(mMatches) = 0 then
        Inc(Result.Unlinked);
      for mMatch in mMatches do
      begin
        mName := UpperCase(mMatch.Key);
        if not mIndexOf.TryGetValue(mName, mIssue) then
        begin
          mItem := Default(TAtlasBlameIssue);
          mItem.Match := mMatch;
          mIssue := Length(Result.Issues);
          SetLength(Result.Issues, mIssue + 1);
          Result.Issues[mIssue] := mItem;
          mIndexOf.Add(mName, mIssue);
        end;
        SetLength(Result.Issues[mIssue].Commits, Length(Result.Issues[mIssue].Commits) + 1);
        Result.Issues[mIssue].Commits[High(Result.Issues[mIssue].Commits)] := mCommit;
        if ACommits[mCommit].Date > Result.Issues[mIssue].LastDate then
          Result.Issues[mIssue].LastDate := ACommits[mCommit].Date;
      end;
    end;
  finally
    mIndexOf.Free;
  end;
  // Einfügen sortiert: wenige Issues, und die Reihenfolge ist eindeutig.
  for mIssue := 1 to High(Result.Issues) do
  begin
    mItem := Result.Issues[mIssue];
    mInsert := mIssue;
    while (mInsert > 0) and Before(mItem, Result.Issues[mInsert - 1]) do
    begin
      Result.Issues[mInsert] := Result.Issues[mInsert - 1];
      Dec(mInsert);
    end;
    Result.Issues[mInsert] := mItem;
  end;
end;

class function TAtlasBlameLinks.Scope(const AText: string; ALine: Integer; out AFirst, ALast: Integer;
  out AName: string): Boolean;
var
  mPlace: TAtlasMethodPlace;
  mCount, mIndex: Integer;
begin
  Result := TAtlasBookmarks.MethodAt(TAtlasMethodToggle.Places(AText), ALine, mPlace);
  if Result then
  begin
    AFirst := mPlace.FirstLine;
    ALast := mPlace.LastLine;
    AName := mPlace.Name;
    Exit;
  end;
  mCount := 1;
  for mIndex := 1 to Length(AText) do
    if AText[mIndex] = #10 then
      Inc(mCount);
  // Ein Zeilenende am Schluss beginnt keine Zeile mehr.
  if (AText <> '') and (AText[Length(AText)] = #10) then
    Dec(mCount);
  AFirst := 0;
  ALast := mCount - 1;
  AName := '';
end;

class function TAtlasBlameLinks.RepositoryRange(const ARepository, ABuffer: TArray<string>; AFirst, ALast: Integer;
  out ARepositoryFirst, ARepositoryLast: Integer): Boolean;
var
  mHunks: TArray<TTextLineHunk>;
  mLine, mMapped: Integer;
begin
  ARepositoryFirst := 0;
  ARepositoryLast := 0;
  Result := False;
  mHunks := TTextDiff.Hunks(ARepository, ABuffer);
  for mLine := AFirst to ALast do
  begin
    mMapped := TAtlasLineChanges.BlameLine(mHunks, mLine);
    if (mMapped >= 0) and (mMapped < Length(ARepository)) then
    begin
      ARepositoryFirst := mMapped + 1;
      Result := True;
      Break;
    end;
  end;
  if not Result then
    Exit;
  for mLine := ALast downto AFirst do
  begin
    mMapped := TAtlasLineChanges.BlameLine(mHunks, mLine);
    if (mMapped >= 0) and (mMapped < Length(ARepository)) then
    begin
      ARepositoryLast := mMapped + 1;
      Break;
    end;
  end;
end;

class function TAtlasBlameLinks.BlameRevisions(const ALines: TArray<TAtlasVcsBlameLine>): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mLine: TAtlasVcsBlameLine;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mLine in ALines do
      if not mLine.Uncommitted and not mSeen.ContainsKey(mLine.Revision) then
      begin
        mSeen.Add(mLine.Revision, True);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := mLine.Revision;
      end;
  finally
    mSeen.Free;
  end;
end;

class function TAtlasBlameLinks.ShortRevision(AKind: TAtlasVcsKind; const ARevision: string): string;
begin
  case AKind of
    TAtlasVcsKind.Git:
      Result := Copy(ARevision, 1, 7);
    TAtlasVcsKind.Svn:
      Result := 'r' + ARevision;
  else
    Result := ARevision;
  end;
end;

class function TAtlasBlameLinks.Subject(const AMessage: string): string;
var
  mLine: string;
begin
  for mLine in AMessage.Split([#10]) do
    if Trim(mLine) <> '' then
      Exit(Trim(mLine));
  Result := '';
end;

end.
