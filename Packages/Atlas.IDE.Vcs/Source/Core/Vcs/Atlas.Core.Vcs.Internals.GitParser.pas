unit Atlas.Core.Vcs.Internals.GitParser;

// Liest die Ausgaben von git für die Versionsverwaltung (#571):
//   git status --porcelain=v2 --branch -z      Branch, Commit, verfolgter Branch,
//                                              Vorsprung/Rückstand, Änderungen
//   git blame --porcelain                      Zeilenherkunft
// Für nicht gesicherte Arbeit (#762), Felder durch NUL, Einträge durch LF:
//   git for-each-ref --format=<BranchFormat> refs/heads    lokale Branches
//   git stash list --format=<StashFormat>                  Stashes
//   git log --format=<LogFormat> …                         Commits
//   git diff --name-status -z <a> <b>                      geänderte Dateien
//   git remote                                             Remotes
// Für eingehende Commits (#755):
//   git log --format=<IncomingFormat> --name-only -z …     Commits mit Dateien
//   Jeder Commit beginnt mit RS (#$1E), danach Hash, Zeit, Autor und Betreff
//   je mit NUL abgeschlossen, dann LF und die Dateien je mit NUL.
// Für die Issues der Zeilenhistorie (#1275), Felder durch US (#$1F), weil
// Nachrichten Zeilenenden enthalten:
//   git log --format=<LineLogFormat> -L<a>,<b>:<Pfad>   Commits eines Bereichs
//   Jeder Commit beginnt mit RS, danach Hash, Autor, Zeit und ganze Nachricht
//   je mit US abgeschlossen, dann der Unterschied des Bereichs.
//   git log --no-walk=unsorted --format=<MessageFormat> <Commits>
//   Jeder Commit beginnt mit RS, danach Hash, US und die ganze Nachricht.
// Für die Entwicklung zu einem Issue (#1269):
//   git log --all --format=<HistoryFormat> --name-status -z …   Commits mit
//   ganzer Nachricht und Dateien: RS, Hash, Zeit, Autor, Nachricht je mit NUL,
//   dann Paare aus Art und Pfad je mit NUL (vor der ersten Art ein LF).
//   git for-each-ref --format=<RefFormat> refs/heads refs/remotes   Branches
//   git rev-list --left-right --count <Basis>...<Branch>   "Rückstand TAB Vorsprung"
// Mit -z trennt git die Einträge durch NUL und schreibt Pfade unverändert
// (UTF-8, ohne Anführungszeichen); bei Umbenennungen folgt der alte Pfad als
// eigener Eintrag. Pfade sind relativ zur Wurzel, weil git dort läuft.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasGitParser = class
  public
    /// <summary>Ausgabe von "git status --porcelain=v2 --branch -z"; Pfade vollständig unter ARoot.
    /// Ignorierte Dateien ("!") entfallen. Löst EAtlasVcsParse bei unbekannten Einträgen aus.</summary>
    class procedure ParseStatus(const AText, ARoot: string; out AHead: TAtlasVcsHead;
      out AChanges: TArray<TAtlasVcsChange>); static;
    /// <summary>Ausgabe von "git blame --porcelain", eine Zeile je Zeile der Datei in Reihenfolge.</summary>
    class function ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>; static;
    /// <summary>Art der Änderung aus dem XY-Feld eines Eintrags "1".</summary>
    class function KindOf(const AXY: string): TAtlasVcsChangeKind; static;
  public const
    /// <summary>Format für git for-each-ref (#762): Name, Upstream, Remote, Ref auf dem Remote, Abstand
    /// ("ahead 1, behind 2", "gone" oder leer), Commit-Zeit (Unix) und "*" für HEAD.</summary>
    cBranchFormat = '%(refname:short)%00%(upstream:short)%00%(upstream:remotename)%00%(upstream:remoteref)%00' +
      '%(upstream:track,nobracket)%00%(committerdate:unix)%00%(HEAD)';
    /// <summary>Format für git stash list (#762): Hash, Zeit (Unix), Auswahl, Betreff des Reflogs.</summary>
    cStashFormat = '%H%x00%ct%x00%gd%x00%gs';
    /// <summary>Format für git log (#762): Hash, Zeit (Unix), Betreff.</summary>
    cLogFormat = '%H%x00%ct%x00%s';
    /// <summary>Format für git log --name-only -z (#755): RS, Hash, Zeit (Unix), Autor, Betreff.</summary>
    cIncomingFormat = '%x1e%H%x00%ct%x00%an%x00%s';
    /// <summary>Format für git log -L (#1275): RS, Hash, Autor, Zeit (Unix), ganze Nachricht, je mit US
    /// abgeschlossen; danach folgt der Unterschied.</summary>
    cLineLogFormat = '%x1e%H%x1f%an%x1f%ct%x1f%B%x1f';
    /// <summary>Format für die Nachrichten zu Commits (#1275): RS, Hash, US, ganze Nachricht.</summary>
    cMessageFormat = '%x1e%H%x1f%B';
    /// <summary>Format für git log --name-status -z (#1269): RS, Hash, Zeit (Unix), Autor, ganze Nachricht.</summary>
    cHistoryFormat = '%x1e%H%x00%ct%x00%an%x00%B';
    /// <summary>Format für git for-each-ref (#1269): voller Name, Commit-Zeit (Unix), "*" für HEAD.</summary>
    cRefFormat = '%(refname)%00%(committerdate:unix)%00%(HEAD)';
  public
    /// <summary>Ausgabe von git log --name-status -z mit HistoryFormat; Pfade vollständig unter ARoot.</summary>
    class function ParseHistory(const AText, ARoot: string): TArray<TAtlasVcsLogEntry>; static;
    /// <summary>Ausgabe von git for-each-ref mit RefFormat über refs/heads und refs/remotes; "…/HEAD" entfällt.
    /// </summary>
    class function ParseRefs(const AText: string): TArray<TAtlasVcsRef>; static;
    /// <summary>Ausgabe von git rev-list --left-right --count &lt;Basis&gt;...&lt;Branch&gt;.</summary>
    class procedure ParseDistance(const AText: string; out AAhead, ABehind: Integer); static;
    /// <summary>Ausgabe von git for-each-ref mit BranchFormat.</summary>
    class function ParseBranches(const AText: string): TArray<TAtlasVcsBranch>; static;
    /// <summary>Ausgabe von git stash list mit StashFormat.</summary>
    class function ParseStashes(const AText: string): TArray<TAtlasVcsStash>; static;
    /// <summary>Ausgabe von git log mit LogFormat.</summary>
    class function ParseLog(const AText: string): TArray<TAtlasVcsCommit>; static;
    /// <summary>Ausgabe von git diff --name-status -z; Pfade vollständig unter ARoot.</summary>
    class function ParseNameStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>; static;
    /// <summary>Ausgabe von git log --name-only -z mit IncomingFormat; Pfade vollständig unter ARoot.</summary>
    class function ParseIncoming(const AText, ARoot: string): TArray<TAtlasVcsIncomingCommit>; static;
    /// <summary>Ausgabe von git remote: ein Name je Zeile.</summary>
    class function ParseLines(const AText: string): TArray<string>; static;
    /// <summary>Ausgabe von git log -L mit LineLogFormat (#1275): Commits mit ganzer Nachricht und dem Unterschied
    /// des Bereichs.</summary>
    class function ParseLineLog(const AText: string): TArray<TAtlasVcsLineCommit>; static;
    /// <summary>Ausgabe von git log --no-walk mit MessageFormat (#1275).</summary>
    class function ParseMessages(const AText: string): TArray<TAtlasVcsRevisionMessage>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Vcs.Internals.Text;

const
  cNullCommit = '0000000000000000000000000000000000000000';

/// <summary>Das N-te durch Leerzeichen getrennte Feld (0-basiert); der Rest ab dem Feld bei ARest.</summary>
function Field(const ALine: string; AIndex: Integer; ARest: Boolean): string;
var
  mIndex, mCount, mStart: Integer;
begin
  mCount := 0;
  mStart := 1;
  for mIndex := 1 to Length(ALine) do
  begin
    if ALine[mIndex] = ' ' then
    begin
      if mCount = AIndex then
      begin
        Exit(Copy(ALine, mStart, mIndex - mStart));
      end;
      Inc(mCount);
      mStart := mIndex + 1;
      if (mCount = AIndex) and ARest then
      begin
        Exit(Copy(ALine, mStart, MaxInt));
      end;
    end;
  end;
  if mCount = AIndex then
  begin
    Result := Copy(ALine, mStart, MaxInt);
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasGitParser.KindOf(const AXY: string): TAtlasVcsChangeKind;
var
  X, Y: Char;
begin
  if Length(AXY) < 2 then
  begin
    raise EAtlasVcsParse.CreateFmt('git status: Feld XY "%s" unbekannt', [AXY]);
  end;
  X := AXY[1];
  Y := AXY[2];
  if (X = 'A') or (Y = 'A') then
  begin
    Result := TAtlasVcsChangeKind.Added;
  end
  else if (X = 'D') or (Y = 'D') then
  begin
    Result := TAtlasVcsChangeKind.Deleted;
  end
  else if (X = 'T') or (Y = 'T') then
  begin
    Result := TAtlasVcsChangeKind.TypeChanged;
  end
  else if (X = 'R') or (Y = 'R') then
  begin
    Result := TAtlasVcsChangeKind.Renamed;
  end
  else if (X = 'C') or (Y = 'C') then
  begin
    Result := TAtlasVcsChangeKind.Copied;
  end
  else
  begin
    Result := TAtlasVcsChangeKind.Modified;
  end;
end;

function MakeChange(const ARoot, APath: string; AKind: TAtlasVcsChangeKind; const AXY: string): TAtlasVcsChange;
begin
  Result.Path := VcsFullPath(ARoot, APath);
  Result.OldPath := '';
  Result.Kind := AKind;
  Result.Staged := (Length(AXY) >= 1) and (AXY[1] <> '.');
  Result.Unstaged := (Length(AXY) >= 2) and (AXY[2] <> '.');
end;

procedure ReadAheadBehind(const AValue: string; var AHead: TAtlasVcsHead);
var
  mAheadText, mBehindText: string;
  mNumber: Integer;
begin
  // "+1 -2"
  mAheadText := Field(AValue, 0, False);
  mBehindText := Field(AValue, 1, False);
  if (Copy(mAheadText, 1, 1) = '+') and TryStrToInt(Copy(mAheadText, 2, MaxInt), mNumber) then
  begin
    AHead.Ahead := mNumber;
  end;
  if (Copy(mBehindText, 1, 1) = '-') and TryStrToInt(Copy(mBehindText, 2, MaxInt), mNumber) then
  begin
    AHead.Behind := mNumber;
  end;
end;

/// <summary>Kopfzeile "# branch.… Wert" von git status --porcelain=v2 in AHead übernehmen.</summary>
procedure ReadStatusHeader(const AEntry: string; var AHead: TAtlasVcsHead);
var
  mKey, mValue: string;
begin
  mKey := Field(AEntry, 1, False);
  mValue := Field(AEntry, 2, True);
  if (mKey = 'branch.oid') and (mValue <> '(initial)') then
  begin
    AHead.Revision := mValue;
  end
  else if (mKey = 'branch.head') and (mValue = '(detached)') then
  begin
    AHead.Detached := True;
  end
  else if mKey = 'branch.head' then
  begin
    AHead.Branch := mValue;
  end
  else if mKey = 'branch.upstream' then
  begin
    AHead.Upstream := mValue;
  end
  else if mKey = 'branch.ab' then
  begin
    ReadAheadBehind(mValue, AHead);
  end;
end;

/// <summary>Eintrag "2 XY sub mH mI mW hH hI Xscore path"; der alte Pfad folgt als eigener Eintrag bei AIndex, der
/// dann übersprungen wird.</summary>
function ReadMoved(const ARoot, AEntry: string; const AEntries: TArray<string>; var AIndex: Integer):
  TAtlasVcsChange;
var
  mXY: string;
begin
  mXY := Field(AEntry, 1, False);
  if Copy(Field(AEntry, 8, False), 1, 1) = 'C' then
  begin
    Result := MakeChange(ARoot, Field(AEntry, 9, True), TAtlasVcsChangeKind.Copied, mXY);
  end
  else
  begin
    Result := MakeChange(ARoot, Field(AEntry, 9, True), TAtlasVcsChangeKind.Renamed, mXY);
  end;
  if AIndex <= High(AEntries) then
  begin
    Result.OldPath := VcsFullPath(ARoot, AEntries[AIndex]);
    Inc(AIndex);
  end;
end;

class procedure TAtlasGitParser.ParseStatus(const AText, ARoot: string; out AHead: TAtlasVcsHead;
  out AChanges: TArray<TAtlasVcsChange>);
var
  mEntries: TArray<string>;
  mIndex: Integer;
  mEntry: string;
begin
  AHead := TAtlasVcsHead.Empty;
  AChanges := nil;
  // Mit -z durch NUL getrennt, sonst durch Zeilenumbrüche.
  if Pos(#0, AText) > 0 then
  begin
    mEntries := AText.Split([#0]);
  end
  else
  begin
    mEntries := AText.Split([#10]);
  end;
  mIndex := 0;
  while mIndex <= High(mEntries) do
  begin
    mEntry := mEntries[mIndex].TrimRight([#13, #10]);
    Inc(mIndex);
    if mEntry = '' then
    begin
      Continue;
    end;
    case mEntry[1] of
      '#':
        ReadStatusHeader(mEntry, AHead);
      '1':
        // 1 XY sub mH mI mW hH hI path
        AChanges := AChanges + [MakeChange(ARoot, Field(mEntry, 8, True), KindOf(Field(mEntry, 1, False)),
          Field(mEntry, 1, False))];
      '2':
        AChanges := AChanges + [ReadMoved(ARoot, mEntry, mEntries, mIndex)];
      'u':
        // u XY sub m1 m2 m3 mW h1 h2 h3 path
        AChanges := AChanges + [MakeChange(ARoot, Field(mEntry, 10, True), TAtlasVcsChangeKind.Conflicted,
          Field(mEntry, 1, False))];
      '?':
        AChanges := AChanges + [MakeChange(ARoot, Copy(mEntry, 3, MaxInt), TAtlasVcsChangeKind.Untracked, '.?')];
      '!':
        ;
    else
      raise EAtlasVcsParse.CreateFmt('git status: unbekannter Eintrag "%s"', [Copy(mEntry, 1, 1)]);
    end;
  end;
end;

/// <summary>Zeilen (LF, CR wird entfernt) ohne leere.</summary>
function NonEmptyLines(const AText: string): TArray<string>;
var
  mLine: string;
begin
  Result := nil;
  for mLine in AText.Split([#10]) do
  begin
    if mLine.TrimRight([#13]) <> '' then
    begin
      Result := Result + [mLine.TrimRight([#13])];
    end;
  end;
end;

/// <summary>Unix-Zeit als UTC; 0 bei ungültigem Text.</summary>
function UnixField(const AText: string): TDateTime;
var
  mSeconds: Int64;
begin
  if TryStrToInt64(Trim(AText), mSeconds) and (mSeconds > 0) then
  begin
    Result := VcsUnixToDate(mSeconds);
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Ein Teil von "ahead 3, behind 2" (getrimmt); löst EAtlasVcsParse für Unbekanntes aus.</summary>
procedure ReadTrackPart(const APart, AText: string; var ABranch: TAtlasVcsBranch);
var
  mNumber: Integer;
  mKnown: Boolean;
begin
  mKnown := APart = '';
  if Copy(APart, 1, 6) = 'ahead ' then
  begin
    mKnown := TryStrToInt(Trim(Copy(APart, 7, MaxInt)), mNumber);
    ABranch.Ahead := mNumber;
  end
  else if Copy(APart, 1, 7) = 'behind ' then
  begin
    mKnown := TryStrToInt(Trim(Copy(APart, 8, MaxInt)), mNumber);
    ABranch.Behind := mNumber;
  end;
  if not mKnown then
  begin
    raise EAtlasVcsParse.CreateFmt('git for-each-ref: Abstand "%s" unbekannt', [AText]);
  end;
end;

procedure ReadTrack(const AText: string; var ABranch: TAtlasVcsBranch);
var
  mPart, mText: string;
begin
  // "ahead 3", "behind 2", "ahead 3, behind 2", "gone" oder leer (gleichauf bzw. ohne Upstream).
  mText := Trim(AText);
  if mText = 'gone' then
  begin
    ABranch.Gone := True;
    Exit;
  end;
  if ABranch.Upstream = '' then
  begin
    Exit;
  end;
  ABranch.Ahead := 0;
  ABranch.Behind := 0;
  for mPart in mText.Split([',']) do
  begin
    ReadTrackPart(Trim(mPart), mText, ABranch);
  end;
end;

class function TAtlasGitParser.ParseBranches(const AText: string): TArray<TAtlasVcsBranch>;
var
  mLine: string;
  mFields: TArray<string>;
  mBranch: TAtlasVcsBranch;
begin
  Result := nil;
  for mLine in NonEmptyLines(AText) do
  begin
    mFields := mLine.Split([#0]);
    if Length(mFields) < 7 then
    begin
      raise EAtlasVcsParse.Create('git for-each-ref: sieben Felder erwartet');
    end;
    mBranch := Default(TAtlasVcsBranch);
    mBranch.Name := mFields[0];
    mBranch.Upstream := mFields[1];
    mBranch.Remote := mFields[2];
    mBranch.RemoteRef := mFields[3];
    mBranch.Ahead := -1;
    mBranch.Behind := -1;
    ReadTrack(mFields[4], mBranch);
    mBranch.TipDate := UnixField(mFields[5]);
    mBranch.Current := Trim(mFields[6]) = '*';
    if mBranch.Name = '' then
    begin
      raise EAtlasVcsParse.Create('git for-each-ref: Name fehlt');
    end;
    Result := Result + [mBranch];
  end;
end;

/// <summary>Betreff "WIP on &lt;branch&gt;: &lt;hash&gt; &lt;Betreff des Commits&gt;" (ohne Namen) oder
/// "On &lt;branch&gt;: &lt;Name&gt;" in Branch und Nachricht zerlegen; sonst bleibt der Betreff die
/// Nachricht.</summary>
procedure ReadStashSubject(const ASubject: string; var AStash: TAtlasVcsStash);
var
  mRest: string;
  mColon, mSpace: Integer;
  mWip: Boolean;
begin
  AStash.Message := ASubject;
  mColon := Pos(': ', ASubject);
  mWip := Copy(ASubject, 1, 7) = 'WIP on ';
  if (mColon = 0) or not (mWip or (Copy(ASubject, 1, 3) = 'On ')) then
  begin
    Exit;
  end;
  mRest := Copy(ASubject, mColon + 2, MaxInt);
  if mWip then
  begin
    AStash.Branch := Copy(ASubject, 8, mColon - 8);
    // Kurzer Hash vorn entfällt.
    mSpace := Pos(' ', mRest);
    if mSpace > 0 then
    begin
      mRest := Copy(mRest, mSpace + 1, MaxInt);
    end;
  end
  else
  begin
    AStash.Branch := Copy(ASubject, 4, mColon - 4);
  end;
  AStash.Message := mRest;
end;

class function TAtlasGitParser.ParseStashes(const AText: string): TArray<TAtlasVcsStash>;
var
  mLine: string;
  mFields: TArray<string>;
  mStash: TAtlasVcsStash;
begin
  Result := nil;
  for mLine in NonEmptyLines(AText) do
  begin
    mFields := mLine.Split([#0]);
    if Length(mFields) < 4 then
    begin
      raise EAtlasVcsParse.Create('git stash list: vier Felder erwartet');
    end;
    mStash := Default(TAtlasVcsStash);
    mStash.Hash := mFields[0];
    mStash.Date := UnixField(mFields[1]);
    mStash.Ref := mFields[2];
    ReadStashSubject(mFields[3], mStash);
    if mStash.Hash = '' then
    begin
      raise EAtlasVcsParse.Create('git stash list: Hash fehlt');
    end;
    Result := Result + [mStash];
  end;
end;

class function TAtlasGitParser.ParseLog(const AText: string): TArray<TAtlasVcsCommit>;
var
  mLine: string;
  mFields: TArray<string>;
  mCommit: TAtlasVcsCommit;
begin
  Result := nil;
  for mLine in NonEmptyLines(AText) do
  begin
    mFields := mLine.Split([#0]);
    if (Length(mFields) < 2) or (Length(mFields[0]) < 7) then
    begin
      raise EAtlasVcsParse.Create('git log: Hash und Zeit erwartet');
    end;
    mCommit.Hash := mFields[0];
    mCommit.Date := UnixField(mFields[1]);
    if Length(mFields) > 2 then
    begin
      mCommit.Summary := mFields[2];
    end
    else
    begin
      mCommit.Summary := '';
    end;
    Result := Result + [mCommit];
  end;
end;

/// <summary>Art aus dem Kennbuchstaben von git diff --name-status; löst EAtlasVcsParse für unbekannte aus.</summary>
function NameStatusKind(const AStatus: string): TAtlasVcsChangeKind;
begin
  case AStatus[1] of
    'M':
      Result := TAtlasVcsChangeKind.Modified;
    'A':
      Result := TAtlasVcsChangeKind.Added;
    'D':
      Result := TAtlasVcsChangeKind.Deleted;
    'T':
      Result := TAtlasVcsChangeKind.TypeChanged;
    'U':
      Result := TAtlasVcsChangeKind.Conflicted;
    'R':
      Result := TAtlasVcsChangeKind.Renamed;
    'C':
      Result := TAtlasVcsChangeKind.Copied;
  else
    raise EAtlasVcsParse.CreateFmt('git diff --name-status: Art "%s" unbekannt', [AStatus]);
  end;
end;

/// <summary>Pfad bei AIndex (danach weiter); löst EAtlasVcsParse mit AMissing aus, wenn er fehlt.</summary>
function NextPath(const AEntries: TArray<string>; var AIndex: Integer; const AMissing: string): string;
begin
  if (AIndex > High(AEntries)) or (AEntries[AIndex] = '') then
  begin
    raise EAtlasVcsParse.Create(AMissing);
  end;
  Result := AEntries[AIndex];
  Inc(AIndex);
end;

class function TAtlasGitParser.ParseNameStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>;
var
  mEntries: TArray<string>;
  mIndex: Integer;
  mStatus: string;
  mChange: TAtlasVcsChange;
begin
  Result := nil;
  mEntries := AText.Split([#0]);
  mIndex := 0;
  while mIndex <= High(mEntries) do
  begin
    mStatus := mEntries[mIndex].Trim([#10, #13]);
    Inc(mIndex);
    if mStatus = '' then
    begin
      Continue;
    end;
    if mIndex > High(mEntries) then
    begin
      raise EAtlasVcsParse.Create('git diff --name-status: Pfad fehlt');
    end;
    mChange := Default(TAtlasVcsChange);
    mChange.Staged := True;
    mChange.Unstaged := False;
    mChange.Kind := NameStatusKind(mStatus);
    if mChange.Kind in [TAtlasVcsChangeKind.Renamed, TAtlasVcsChangeKind.Copied] then
    begin
      // Erst der alte, dann der neue Pfad.
      mChange.OldPath := VcsFullPath(ARoot, mEntries[mIndex]);
      Inc(mIndex);
      if mIndex > High(mEntries) then
      begin
        raise EAtlasVcsParse.Create('git diff --name-status: neuer Pfad fehlt');
      end;
    end;
    mChange.Path := VcsFullPath(ARoot, NextPath(mEntries, mIndex, 'git diff --name-status: Pfad fehlt'));
    Result := Result + [mChange];
  end;
end;

class function TAtlasGitParser.ParseIncoming(const AText, ARoot: string): TArray<TAtlasVcsIncomingCommit>;
var
  mRecords, mFields: TArray<string>;
  mItem, mPath: string;
  mIndex: Integer;
  mCommit: TAtlasVcsIncomingCommit;
begin
  Result := nil;
  mRecords := AText.Split([#$1E]);
  for mItem in mRecords do
  begin
    // Vor dem ersten Trenner steht nichts; Zeilenenden zwischen den Commits zählen nicht.
    if mItem.Trim([#0, #10, #13]) = '' then
    begin
      Continue;
    end;
    mFields := mItem.Split([#0]);
    if (Length(mFields) < 4) or (Length(mFields[0]) < 7) then
    begin
      raise EAtlasVcsParse.Create('git log: Hash, Zeit, Autor und Betreff erwartet');
    end;
    mCommit := Default(TAtlasVcsIncomingCommit);
    mCommit.Hash := mFields[0];
    mCommit.Date := UnixField(mFields[1]);
    mCommit.Author := mFields[2];
    mCommit.Summary := mFields[3];
    // Dateien: die erste nach einem Zeilenende, alle je mit NUL abgeschlossen.
    for mIndex := 4 to High(mFields) do
    begin
      mPath := mFields[mIndex].Trim([#10, #13]);
      if mPath <> '' then
      begin
        mCommit.Files := mCommit.Files + [VcsFullPath(ARoot, mPath)];
      end;
    end;
    Result := Result + [mCommit];
  end;
end;

function StatusKind(const AStatus: string): TAtlasVcsChangeKind;
begin
  if AStatus = '' then
  begin
    raise EAtlasVcsParse.Create('git log --name-status: Art fehlt');
  end;
  case AStatus[1] of
    'M':
      Result := TAtlasVcsChangeKind.Modified;
    'A':
      Result := TAtlasVcsChangeKind.Added;
    'D':
      Result := TAtlasVcsChangeKind.Deleted;
    'T':
      Result := TAtlasVcsChangeKind.TypeChanged;
    'U':
      Result := TAtlasVcsChangeKind.Conflicted;
  else
    raise EAtlasVcsParse.CreateFmt('git log --name-status: Art "%s" unbekannt', [AStatus]);
  end;
end;

/// <summary>Erste Zeile einer Nachricht.</summary>
function SummaryOf(const AMessage: string): string;
var
  mBreak: Integer;
begin
  mBreak := Pos(#10, AMessage);
  if mBreak > 0 then
  begin
    Result := Copy(AMessage, 1, mBreak - 1);
  end
  else
  begin
    Result := AMessage;
  end;
end;

/// <summary>Paare aus Art und Pfad ab Feld 4; leere Einträge (Ende der Nachricht, Zeilenende davor) zählen nicht.
/// </summary>
procedure ReadHistoryFiles(const AFields: TArray<string>; const ARoot: string; AFiles: TList<TAtlasVcsLogFile>);
var
  mIndex: Integer;
  mStatus: string;
  mFile: TAtlasVcsLogFile;
begin
  AFiles.Clear;
  mIndex := 4;
  while mIndex <= High(AFields) do
  begin
    mStatus := AFields[mIndex].Trim([#10, #13]);
    Inc(mIndex);
    if mStatus = '' then
    begin
      Continue;
    end;
    mFile := Default(TAtlasVcsLogFile);
    mFile.RepositoryPath := NextPath(AFields, mIndex, 'git log --name-status: Pfad fehlt');
    mFile.Kind := StatusKind(mStatus);
    mFile.Path := VcsFullPath(ARoot, mFile.RepositoryPath);
    AFiles.Add(mFile);
  end;
end;

/// <summary>Kopf eines Commits aus git log: Hash, Zeit, Autor und Nachricht.</summary>
function HistoryEntry(const AFields: TArray<string>): TAtlasVcsLogEntry;
begin
  if (Length(AFields) < 4) or (Length(AFields[0]) < 7) then
  begin
    raise EAtlasVcsParse.Create('git log: Hash, Zeit, Autor und Nachricht erwartet');
  end;
  Result := Default(TAtlasVcsLogEntry);
  Result.Revision := AFields[0];
  Result.Date := UnixField(AFields[1]);
  Result.Author := AFields[2];
  Result.Message := StringReplace(AFields[3], #13#10, #10, [rfReplaceAll]).TrimRight([#10, #13, ' ']);
  Result.Summary := SummaryOf(Result.Message);
end;

class function TAtlasGitParser.ParseHistory(const AText, ARoot: string): TArray<TAtlasVcsLogEntry>;
var
  mFields: TArray<string>;
  mItem: string;
  mEntry: TAtlasVcsLogEntry;
  mEntries: TList<TAtlasVcsLogEntry>;
  mFiles: TList<TAtlasVcsLogFile>;
begin
  // Liste statt Anhängen ans Array: Die Suche kann viele Commits liefern (Benchmark mit 10 000).
  mEntries := TList<TAtlasVcsLogEntry>.Create;
  mFiles := TList<TAtlasVcsLogFile>.Create;
  try
    for mItem in AText.Split([#$1E]) do
    begin
      if mItem.Trim([#0, #10, #13]) = '' then
      begin
        Continue;
      end;
      mFields := mItem.Split([#0]);
      mEntry := HistoryEntry(mFields);
      ReadHistoryFiles(mFields, ARoot, mFiles);
      mEntry.Files := mFiles.ToArray;
      mEntries.Add(mEntry);
    end;
    Result := mEntries.ToArray;
  finally
    mFiles.Free;
    mEntries.Free;
  end;
end;

class function TAtlasGitParser.ParseRefs(const AText: string): TArray<TAtlasVcsRef>;
const
  cHeads = 'refs/heads/';
  cRemotes = 'refs/remotes/';
var
  mLine, mName: string;
  mFields: TArray<string>;
  mRef: TAtlasVcsRef;
  mSlash: Integer;
begin
  Result := nil;
  for mLine in NonEmptyLines(AText) do
  begin
    mFields := mLine.Split([#0]);
    if Length(mFields) < 3 then
    begin
      raise EAtlasVcsParse.Create('git for-each-ref: drei Felder erwartet');
    end;
    mName := mFields[0];
    mRef := Default(TAtlasVcsRef);
    if mName.StartsWith(cHeads) then
    begin
      mRef.Name := Copy(mName, Length(cHeads) + 1, MaxInt);
      mRef.LocalName := mRef.Name;
    end
    else if mName.StartsWith(cRemotes) then
    begin
      mRef.Name := Copy(mName, Length(cRemotes) + 1, MaxInt);
      mRef.Remote := True;
      // "origin/HEAD" zeigt nur auf einen anderen Branch.
      if mRef.Name.EndsWith('/HEAD') then
      begin
        Continue;
      end;
      mSlash := Pos('/', mRef.Name);
      if mSlash = 0 then
      begin
        Continue;
      end;
      mRef.LocalName := Copy(mRef.Name, mSlash + 1, MaxInt);
    end
    else
    begin
      Continue;
    end;
    if mRef.Name = '' then
    begin
      raise EAtlasVcsParse.Create('git for-each-ref: Name fehlt');
    end;
    mRef.TipDate := UnixField(mFields[1]);
    mRef.Current := Trim(mFields[2]) = '*';
    Result := Result + [mRef];
  end;
end;

class procedure TAtlasGitParser.ParseDistance(const AText: string; out AAhead, ABehind: Integer);
var
  mParts: TArray<string>;
begin
  // Links steht, was nur in der Basis liegt (Rückstand), rechts, was nur im Branch liegt (Vorsprung).
  mParts := Trim(AText).Split([#9, ' '], TStringSplitOptions.ExcludeEmpty);
  if (Length(mParts) <> 2) or not TryStrToInt(mParts[0], ABehind) or not TryStrToInt(mParts[1], AAhead) then
  begin
    raise EAtlasVcsParse.CreateFmt('git rev-list --count: "%s" unbekannt', [Trim(AText)]);
  end;
end;

class function TAtlasGitParser.ParseLines(const AText: string): TArray<string>;
var
  mLine: string;
begin
  Result := nil;
  for mLine in NonEmptyLines(AText) do
  begin
    Result := Result + [Trim(mLine)];
  end;
end;

/// <summary>Zeilen von AText ohne CR; leere Zeilen am Anfang und am Ende entfallen.</summary>
function TrimmedLines(const AText: string): TArray<string>;
var
  mFirst, mLast, mIndex: Integer;
  mLines: TArray<string>;
begin
  mLines := AText.Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    mLines[mIndex] := mLines[mIndex].TrimRight([#13]);
  end;
  mFirst := 0;
  while (mFirst <= High(mLines)) and (mLines[mFirst] = '') do
  begin
    Inc(mFirst);
  end;
  mLast := High(mLines);
  while (mLast >= mFirst) and (mLines[mLast] = '') do
  begin
    Dec(mLast);
  end;
  Result := Copy(mLines, mFirst, mLast - mFirst + 1);
end;

class function TAtlasGitParser.ParseLineLog(const AText: string): TArray<TAtlasVcsLineCommit>;
var
  mItems, mFields: TArray<string>;
  mItem: string;
  mCommit: TAtlasVcsLineCommit;
  mCount, mStart, mStop, mFound: Integer;
begin
  // Höchstens ein Eintrag je Abschnitt: Länge vorab, am Ende kürzen.
  mItems := AText.Split([#$1E]);
  Result := nil;
  SetLength(Result, Length(mItems));
  mFound := 0;
  for mItem in mItems do
  begin
    if mItem.Trim([#10, #13]) = '' then
    begin
      Continue;
    end;
    // Hash, Autor, Zeit, Nachricht und der Rest (Unterschied); nur vier Trenner zählen.
    SetLength(mFields, 5);
    mStart := 1;
    mCount := 0;
    while mCount < 4 do
    begin
      mStop := Pos(#$1F, mItem, mStart);
      if mStop = 0 then
      begin
        Break;
      end;
      mFields[mCount] := Copy(mItem, mStart, mStop - mStart);
      Inc(mCount);
      mStart := mStop + 1;
    end;
    mFields[4] := Copy(mItem, mStart, MaxInt);
    if (mCount < 4) or (Length(mFields[0]) < 7) then
    begin
      raise EAtlasVcsParse.Create('git log -L: Hash, Autor, Zeit und Nachricht erwartet');
    end;
    mCommit := Default(TAtlasVcsLineCommit);
    mCommit.Revision := mFields[0];
    mCommit.Author := mFields[1];
    mCommit.Date := UnixField(mFields[2]);
    mCommit.Message := TrimRight(mFields[3]);
    mCommit.Patch := TrimmedLines(mFields[4]);
    Result[mFound] := mCommit;
    Inc(mFound);
  end;
  SetLength(Result, mFound);
end;

class function TAtlasGitParser.ParseMessages(const AText: string): TArray<TAtlasVcsRevisionMessage>;
var
  mItems: TArray<string>;
  mItem: string;
  mSplit, mFound: Integer;
  mMessage: TAtlasVcsRevisionMessage;
begin
  // Höchstens ein Eintrag je Abschnitt: Länge vorab, am Ende kürzen.
  mItems := AText.Split([#$1E]);
  Result := nil;
  SetLength(Result, Length(mItems));
  mFound := 0;
  for mItem in mItems do
  begin
    if mItem.Trim([#10, #13]) = '' then
    begin
      Continue;
    end;
    mSplit := Pos(#$1F, mItem);
    if mSplit < 8 then
    begin
      raise EAtlasVcsParse.Create('git log: Hash und Nachricht erwartet');
    end;
    mMessage.Revision := Copy(mItem, 1, mSplit - 1);
    mMessage.Message := TrimRight(Copy(mItem, mSplit + 1, MaxInt));
    Result[mFound] := mMessage;
    Inc(mFound);
  end;
  SetLength(Result, mFound);
end;

type
  TCommitInfo = record
    Hash: string;
    Author: string;
    Date: TDateTime;
    Summary: string;
  end;

  /// <summary>Liest git blame --porcelain Kopfzeile für Kopfzeile.</summary>
  TGitBlameReader = class
  strict private
    FLines: TArray<string>;
    FIndex: Integer;
    FCommits: TArray<TCommitInfo>;
    FCommitCount: Integer;
    FCommitIndexOf: TDictionary<string, Integer>;
    function CommitFor(const AHash: string): Integer;
    procedure ReadCommitInfo(var ACommit: TCommitInfo);
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Höchstzahl der Zeilen (eine je Kopfzeile).</summary>
    function Capacity: Integer;
    /// <summary>Nächste Zeile; False am Ende. Löst EAtlasVcsParse aus, wenn keine Kopfzeile folgt.</summary>
    function Next(out AItem: TAtlasVcsBlameLine): Boolean;
  end;

constructor TGitBlameReader.Create(const AText: string);
begin
  inherited Create;
  FLines := AText.Split([#10]);
  // Höchstens ein Commit je Kopfzeile: einmal anlegen statt je Zeile zu kopieren, Commits über ihren Hash finden statt
  // die Liste zu durchsuchen (#1109).
  SetLength(FCommits, Length(FLines));
  FCommitIndexOf := TDictionary<string, Integer>.Create;
end;

destructor TGitBlameReader.Destroy;
begin
  FreeAndNil(FCommitIndexOf);
  inherited;
end;

function TGitBlameReader.Capacity: Integer;
begin
  Result := Length(FLines);
end;

function TGitBlameReader.CommitFor(const AHash: string): Integer;
begin
  if not FCommitIndexOf.TryGetValue(AHash, Result) then
  begin
    Result := FCommitCount;
    Inc(FCommitCount);
    FCommitIndexOf.Add(AHash, Result);
    FCommits[Result] := Default(TCommitInfo);
    FCommits[Result].Hash := AHash;
  end;
end;

procedure TGitBlameReader.ReadCommitInfo(var ACommit: TCommitInfo);
var
  mLine, mKey, mValue: string;
  mSeconds: Int64;
begin
  // Angaben zum Commit bis zur Inhaltszeile (beginnt mit Tab).
  while FIndex <= High(FLines) do
  begin
    mLine := FLines[FIndex].TrimRight([#13]);
    Inc(FIndex);
    if (mLine <> '') and (mLine[1] = #9) then
    begin
      Break;
    end;
    mKey := Field(mLine, 0, False);
    mValue := Field(mLine, 1, True);
    if mKey = 'author' then
    begin
      ACommit.Author := mValue;
    end
    else if (mKey = 'author-time') and TryStrToInt64(mValue, mSeconds) then
    begin
      ACommit.Date := VcsUnixToDate(mSeconds);
    end
    else if mKey = 'summary' then
    begin
      ACommit.Summary := mValue;
    end;
  end;
end;

function TGitBlameReader.Next(out AItem: TAtlasVcsBlameLine): Boolean;
var
  mLine, mHash: string;
  mCommit, mFinal: Integer;
begin
  AItem := Default(TAtlasVcsBlameLine);
  mLine := '';
  while (mLine = '') and (FIndex <= High(FLines)) do
  begin
    mLine := FLines[FIndex].TrimRight([#13]);
    Inc(FIndex);
  end;
  Result := mLine <> '';
  if not Result then
  begin
    Exit;
  end;
  // Kopfzeile: <hash> <ursprüngliche Zeile> <Zeile> [<Anzahl>]
  mHash := Field(mLine, 0, False);
  if (Length(mHash) < 40) or not TryStrToInt(Field(mLine, 2, False), mFinal) then
  begin
    raise EAtlasVcsParse.Create('git blame: Kopfzeile erwartet');
  end;
  mCommit := CommitFor(mHash);
  ReadCommitInfo(FCommits[mCommit]);
  AItem.Line := mFinal;
  // Noch nicht übernommen: git nennt "Not Committed Yet" und die Uhrzeit von jetzt.
  if mHash <> cNullCommit then
  begin
    AItem.Revision := mHash;
    AItem.Author := FCommits[mCommit].Author;
    AItem.Date := FCommits[mCommit].Date;
    AItem.Summary := FCommits[mCommit].Summary;
  end;
end;

class function TAtlasGitParser.ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>;
var
  mReader: TGitBlameReader;
  mItem: TAtlasVcsBlameLine;
  mCount: Integer;
begin
  mCount := 0;
  mReader := TGitBlameReader.Create(AText);
  try
    // Höchstens eine Zeile je Kopfzeile: einmal anlegen, am Ende kürzen.
    SetLength(Result, mReader.Capacity);
    while mReader.Next(mItem) do
    begin
      Result[mCount] := mItem;
      Inc(mCount);
    end;
  finally
    mReader.Free;
  end;
  SetLength(Result, mCount);
end;

end.
