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
    BranchFormat = '%(refname:short)%00%(upstream:short)%00%(upstream:remotename)%00%(upstream:remoteref)%00' +
      '%(upstream:track,nobracket)%00%(committerdate:unix)%00%(HEAD)';
    /// <summary>Format für git stash list (#762): Hash, Zeit (Unix), Auswahl, Betreff des Reflogs.</summary>
    StashFormat = '%H%x00%ct%x00%gd%x00%gs';
    /// <summary>Format für git log (#762): Hash, Zeit (Unix), Betreff.</summary>
    LogFormat = '%H%x00%ct%x00%s';
    /// <summary>Format für git log --name-only -z (#755): RS, Hash, Zeit (Unix), Autor, Betreff.</summary>
    IncomingFormat = '%x1e%H%x00%ct%x00%an%x00%s';
    /// <summary>Format für git log --name-status -z (#1269): RS, Hash, Zeit (Unix), Autor, ganze Nachricht.</summary>
    HistoryFormat = '%x1e%H%x00%ct%x00%an%x00%B';
    /// <summary>Format für git for-each-ref (#1269): voller Name, Commit-Zeit (Unix), "*" für HEAD.</summary>
    RefFormat = '%(refname)%00%(committerdate:unix)%00%(HEAD)';
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
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Vcs.Internals.Text;

const
  NullCommit = '0000000000000000000000000000000000000000';

/// <summary>Das N-te durch Leerzeichen getrennte Feld (0-basiert); der Rest ab dem Feld bei ARest.</summary>
function Field(const ALine: string; AIndex: Integer; ARest: Boolean): string;
var
  Index, Count, Start: Integer;
begin
  Count := 0;
  Start := 1;
  for Index := 1 to Length(ALine) do
    if ALine[Index] = ' ' then
    begin
      if Count = AIndex then
        Exit(Copy(ALine, Start, Index - Start));
      Inc(Count);
      Start := Index + 1;
      if (Count = AIndex) and ARest then
        Exit(Copy(ALine, Start, MaxInt));
    end;
  if Count = AIndex then
    Result := Copy(ALine, Start, MaxInt)
  else
    Result := '';
end;

class function TAtlasGitParser.KindOf(const AXY: string): TAtlasVcsChangeKind;
var
  X, Y: Char;
begin
  if Length(AXY) < 2 then
    raise EAtlasVcsParse.CreateFmt('git status: Feld XY "%s" unbekannt', [AXY]);
  X := AXY[1];
  Y := AXY[2];
  if (X = 'A') or (Y = 'A') then
    Result := TAtlasVcsChangeKind.Added
  else if (X = 'D') or (Y = 'D') then
    Result := TAtlasVcsChangeKind.Deleted
  else if (X = 'T') or (Y = 'T') then
    Result := TAtlasVcsChangeKind.TypeChanged
  else if (X = 'R') or (Y = 'R') then
    Result := TAtlasVcsChangeKind.Renamed
  else if (X = 'C') or (Y = 'C') then
    Result := TAtlasVcsChangeKind.Copied
  else
    Result := TAtlasVcsChangeKind.Modified;
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
  AheadText, BehindText: string;
  Number: Integer;
begin
  // "+1 -2"
  AheadText := Field(AValue, 0, False);
  BehindText := Field(AValue, 1, False);
  if (Copy(AheadText, 1, 1) = '+') and TryStrToInt(Copy(AheadText, 2, MaxInt), Number) then
    AHead.Ahead := Number;
  if (Copy(BehindText, 1, 1) = '-') and TryStrToInt(Copy(BehindText, 2, MaxInt), Number) then
    AHead.Behind := Number;
end;

class procedure TAtlasGitParser.ParseStatus(const AText, ARoot: string; out AHead: TAtlasVcsHead;
  out AChanges: TArray<TAtlasVcsChange>);
var
  Entries: TArray<string>;
  Index: Integer;
  Entry, Key, Value, XY: string;
  Change: TAtlasVcsChange;
begin
  AHead := TAtlasVcsHead.Empty;
  AChanges := nil;
  // Mit -z durch NUL getrennt, sonst durch Zeilenumbrüche.
  if Pos(#0, AText) > 0 then
    Entries := AText.Split([#0])
  else
    Entries := AText.Split([#10]);
  Index := 0;
  while Index <= High(Entries) do
  begin
    Entry := Entries[Index];
    Inc(Index);
    Entry := Entry.TrimRight([#13, #10]);
    if Entry = '' then
      Continue;
    case Entry[1] of
      '#':
        begin
          Key := Field(Entry, 1, False);
          Value := Field(Entry, 2, True);
          if Key = 'branch.oid' then
          begin
            if Value <> '(initial)' then
              AHead.Revision := Value;
          end
          else if Key = 'branch.head' then
          begin
            if Value = '(detached)' then
              AHead.Detached := True
            else
              AHead.Branch := Value;
          end
          else if Key = 'branch.upstream' then
            AHead.Upstream := Value
          else if Key = 'branch.ab' then
            ReadAheadBehind(Value, AHead);
        end;
      '1':
        begin
          // 1 XY sub mH mI mW hH hI path
          XY := Field(Entry, 1, False);
          AChanges := AChanges + [MakeChange(ARoot, Field(Entry, 8, True), KindOf(XY), XY)];
        end;
      '2':
        begin
          // 2 XY sub mH mI mW hH hI Xscore path, danach der alte Pfad als eigener Eintrag
          XY := Field(Entry, 1, False);
          Value := Field(Entry, 8, False);
          if Copy(Value, 1, 1) = 'C' then
            Change := MakeChange(ARoot, Field(Entry, 9, True), TAtlasVcsChangeKind.Copied, XY)
          else
            Change := MakeChange(ARoot, Field(Entry, 9, True), TAtlasVcsChangeKind.Renamed, XY);
          if Index <= High(Entries) then
          begin
            Change.OldPath := VcsFullPath(ARoot, Entries[Index]);
            Inc(Index);
          end;
          AChanges := AChanges + [Change];
        end;
      'u':
        begin
          // u XY sub m1 m2 m3 mW h1 h2 h3 path
          XY := Field(Entry, 1, False);
          AChanges := AChanges + [MakeChange(ARoot, Field(Entry, 10, True), TAtlasVcsChangeKind.Conflicted, XY)];
        end;
      '?':
        begin
          Change := MakeChange(ARoot, Copy(Entry, 3, MaxInt), TAtlasVcsChangeKind.Untracked, '.?');
          AChanges := AChanges + [Change];
        end;
      '!':
        ;
    else
      raise EAtlasVcsParse.CreateFmt('git status: unbekannter Eintrag "%s"', [Copy(Entry, 1, 1)]);
    end;
  end;
end;

/// <summary>Zeilen (LF, CR wird entfernt) ohne leere.</summary>
function NonEmptyLines(const AText: string): TArray<string>;
var
  Line: string;
begin
  Result := nil;
  for Line in AText.Split([#10]) do
    if Line.TrimRight([#13]) <> '' then
      Result := Result + [Line.TrimRight([#13])];
end;

/// <summary>Unix-Zeit als UTC; 0 bei ungültigem Text.</summary>
function UnixField(const AText: string): TDateTime;
var
  Seconds: Int64;
begin
  if TryStrToInt64(Trim(AText), Seconds) and (Seconds > 0) then
    Result := VcsUnixToDate(Seconds)
  else
    Result := 0;
end;

procedure ReadTrack(const AText: string; var ABranch: TAtlasVcsBranch);
var
  Part, Text: string;
  Number: Integer;
begin
  // "ahead 3", "behind 2", "ahead 3, behind 2", "gone" oder leer (gleichauf bzw. ohne Upstream).
  Text := Trim(AText);
  if Text = 'gone' then
  begin
    ABranch.Gone := True;
    Exit;
  end;
  if ABranch.Upstream = '' then
    Exit;
  ABranch.Ahead := 0;
  ABranch.Behind := 0;
  for Part in Text.Split([',']) do
  begin
    if Copy(Trim(Part), 1, 6) = 'ahead ' then
    begin
      if TryStrToInt(Trim(Copy(Trim(Part), 7, MaxInt)), Number) then
        ABranch.Ahead := Number
      else
        raise EAtlasVcsParse.CreateFmt('git for-each-ref: Abstand "%s" unbekannt', [Text]);
    end
    else if Copy(Trim(Part), 1, 7) = 'behind ' then
    begin
      if TryStrToInt(Trim(Copy(Trim(Part), 8, MaxInt)), Number) then
        ABranch.Behind := Number
      else
        raise EAtlasVcsParse.CreateFmt('git for-each-ref: Abstand "%s" unbekannt', [Text]);
    end
    else if Trim(Part) <> '' then
      raise EAtlasVcsParse.CreateFmt('git for-each-ref: Abstand "%s" unbekannt', [Text]);
  end;
end;

class function TAtlasGitParser.ParseBranches(const AText: string): TArray<TAtlasVcsBranch>;
var
  Line: string;
  Fields: TArray<string>;
  Branch: TAtlasVcsBranch;
begin
  Result := nil;
  for Line in NonEmptyLines(AText) do
  begin
    Fields := Line.Split([#0]);
    if Length(Fields) < 7 then
      raise EAtlasVcsParse.Create('git for-each-ref: sieben Felder erwartet');
    Branch := Default(TAtlasVcsBranch);
    Branch.Name := Fields[0];
    Branch.Upstream := Fields[1];
    Branch.Remote := Fields[2];
    Branch.RemoteRef := Fields[3];
    Branch.Ahead := -1;
    Branch.Behind := -1;
    ReadTrack(Fields[4], Branch);
    Branch.TipDate := UnixField(Fields[5]);
    Branch.Current := Trim(Fields[6]) = '*';
    if Branch.Name = '' then
      raise EAtlasVcsParse.Create('git for-each-ref: Name fehlt');
    Result := Result + [Branch];
  end;
end;

class function TAtlasGitParser.ParseStashes(const AText: string): TArray<TAtlasVcsStash>;
var
  Line, Subject, Rest: string;
  Fields: TArray<string>;
  Stash: TAtlasVcsStash;
  Colon, Space: Integer;
begin
  Result := nil;
  for Line in NonEmptyLines(AText) do
  begin
    Fields := Line.Split([#0]);
    if Length(Fields) < 4 then
      raise EAtlasVcsParse.Create('git stash list: vier Felder erwartet');
    Stash := Default(TAtlasVcsStash);
    Stash.Hash := Fields[0];
    Stash.Date := UnixField(Fields[1]);
    Stash.Ref := Fields[2];
    // Betreff: "WIP on <branch>: <hash> <Betreff des Commits>" (ohne Namen) oder "On <branch>: <Name>".
    Subject := Fields[3];
    Stash.Message := Subject;
    Colon := Pos(': ', Subject);
    if (Colon > 0) and ((Copy(Subject, 1, 7) = 'WIP on ') or (Copy(Subject, 1, 3) = 'On ')) then
    begin
      if Copy(Subject, 1, 7) = 'WIP on ' then
        Stash.Branch := Copy(Subject, 8, Colon - 8)
      else
        Stash.Branch := Copy(Subject, 4, Colon - 4);
      Rest := Copy(Subject, Colon + 2, MaxInt);
      if Copy(Subject, 1, 7) = 'WIP on ' then
      begin
        // Kurzer Hash vorn entfällt.
        Space := Pos(' ', Rest);
        if Space > 0 then
          Rest := Copy(Rest, Space + 1, MaxInt);
      end;
      Stash.Message := Rest;
    end;
    if Stash.Hash = '' then
      raise EAtlasVcsParse.Create('git stash list: Hash fehlt');
    Result := Result + [Stash];
  end;
end;

class function TAtlasGitParser.ParseLog(const AText: string): TArray<TAtlasVcsCommit>;
var
  Line: string;
  Fields: TArray<string>;
  Commit: TAtlasVcsCommit;
begin
  Result := nil;
  for Line in NonEmptyLines(AText) do
  begin
    Fields := Line.Split([#0]);
    if (Length(Fields) < 2) or (Length(Fields[0]) < 7) then
      raise EAtlasVcsParse.Create('git log: Hash und Zeit erwartet');
    Commit.Hash := Fields[0];
    Commit.Date := UnixField(Fields[1]);
    if Length(Fields) > 2 then
      Commit.Summary := Fields[2]
    else
      Commit.Summary := '';
    Result := Result + [Commit];
  end;
end;

class function TAtlasGitParser.ParseNameStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>;
var
  Entries: TArray<string>;
  Index: Integer;
  Status: string;
  Change: TAtlasVcsChange;
begin
  Result := nil;
  Entries := AText.Split([#0]);
  Index := 0;
  while Index <= High(Entries) do
  begin
    Status := Entries[Index].Trim([#10, #13]);
    Inc(Index);
    if Status = '' then
      Continue;
    if Index > High(Entries) then
      raise EAtlasVcsParse.Create('git diff --name-status: Pfad fehlt');
    Change := Default(TAtlasVcsChange);
    Change.Staged := True;
    Change.Unstaged := False;
    case Status[1] of
      'M':
        Change.Kind := TAtlasVcsChangeKind.Modified;
      'A':
        Change.Kind := TAtlasVcsChangeKind.Added;
      'D':
        Change.Kind := TAtlasVcsChangeKind.Deleted;
      'T':
        Change.Kind := TAtlasVcsChangeKind.TypeChanged;
      'U':
        Change.Kind := TAtlasVcsChangeKind.Conflicted;
      'R', 'C':
        begin
          if Status[1] = 'R' then
            Change.Kind := TAtlasVcsChangeKind.Renamed
          else
            Change.Kind := TAtlasVcsChangeKind.Copied;
          // Erst der alte, dann der neue Pfad.
          Change.OldPath := VcsFullPath(ARoot, Entries[Index]);
          Inc(Index);
          if Index > High(Entries) then
            raise EAtlasVcsParse.Create('git diff --name-status: neuer Pfad fehlt');
        end;
    else
      raise EAtlasVcsParse.CreateFmt('git diff --name-status: Art "%s" unbekannt', [Status]);
    end;
    if Entries[Index] = '' then
      raise EAtlasVcsParse.Create('git diff --name-status: Pfad fehlt');
    Change.Path := VcsFullPath(ARoot, Entries[Index]);
    Inc(Index);
    Result := Result + [Change];
  end;
end;

class function TAtlasGitParser.ParseIncoming(const AText, ARoot: string): TArray<TAtlasVcsIncomingCommit>;
var
  Records, Fields: TArray<string>;
  Item, Path: string;
  Index: Integer;
  Commit: TAtlasVcsIncomingCommit;
begin
  Result := nil;
  Records := AText.Split([#$1E]);
  for Item in Records do
  begin
    // Vor dem ersten Trenner steht nichts; Zeilenenden zwischen den Commits zählen nicht.
    if Item.Trim([#0, #10, #13]) = '' then
      Continue;
    Fields := Item.Split([#0]);
    if (Length(Fields) < 4) or (Length(Fields[0]) < 7) then
      raise EAtlasVcsParse.Create('git log: Hash, Zeit, Autor und Betreff erwartet');
    Commit := Default(TAtlasVcsIncomingCommit);
    Commit.Hash := Fields[0];
    Commit.Date := UnixField(Fields[1]);
    Commit.Author := Fields[2];
    Commit.Summary := Fields[3];
    // Dateien: die erste nach einem Zeilenende, alle je mit NUL abgeschlossen.
    for Index := 4 to High(Fields) do
    begin
      Path := Fields[Index].Trim([#10, #13]);
      if Path <> '' then
        Commit.Files := Commit.Files + [VcsFullPath(ARoot, Path)];
    end;
    Result := Result + [Commit];
  end;
end;

function StatusKind(const AStatus: string): TAtlasVcsChangeKind;
begin
  if AStatus = '' then
    raise EAtlasVcsParse.Create('git log --name-status: Art fehlt');
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

class function TAtlasGitParser.ParseHistory(const AText, ARoot: string): TArray<TAtlasVcsLogEntry>;
var
  mRecords, mFields: TArray<string>;
  mItem, mStatus, mMessage: string;
  mIndex, mBreak: Integer;
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
  mEntries: TList<TAtlasVcsLogEntry>;
  mFiles: TList<TAtlasVcsLogFile>;
begin
  // Liste statt Anhängen ans Array: Die Suche kann viele Commits liefern (Benchmark mit 10 000).
  mEntries := TList<TAtlasVcsLogEntry>.Create;
  mFiles := TList<TAtlasVcsLogFile>.Create;
  try
    mRecords := AText.Split([#$1E]);
    for mItem in mRecords do
    begin
      if mItem.Trim([#0, #10, #13]) = '' then
        Continue;
      mFields := mItem.Split([#0]);
      if (Length(mFields) < 4) or (Length(mFields[0]) < 7) then
        raise EAtlasVcsParse.Create('git log: Hash, Zeit, Autor und Nachricht erwartet');
      mEntry := Default(TAtlasVcsLogEntry);
      mEntry.Revision := mFields[0];
      mEntry.Date := UnixField(mFields[1]);
      mEntry.Author := mFields[2];
      mMessage := StringReplace(mFields[3], #13#10, #10, [rfReplaceAll]).TrimRight([#10, #13, ' ']);
      mEntry.Message := mMessage;
      mBreak := Pos(#10, mMessage);
      if mBreak > 0 then
        mEntry.Summary := Copy(mMessage, 1, mBreak - 1)
      else
        mEntry.Summary := mMessage;
      // Danach Paare aus Art und Pfad; leere Einträge (Ende der Nachricht, Zeilenende davor) zählen nicht.
      mFiles.Clear;
      mIndex := 4;
      while mIndex <= High(mFields) do
      begin
        mStatus := mFields[mIndex].Trim([#10, #13]);
        Inc(mIndex);
        if mStatus = '' then
          Continue;
        if (mIndex > High(mFields)) or (mFields[mIndex] = '') then
          raise EAtlasVcsParse.Create('git log --name-status: Pfad fehlt');
        mFile := Default(TAtlasVcsLogFile);
        mFile.Kind := StatusKind(mStatus);
        mFile.RepositoryPath := mFields[mIndex];
        mFile.Path := VcsFullPath(ARoot, mFields[mIndex]);
        Inc(mIndex);
        mFiles.Add(mFile);
      end;
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
      raise EAtlasVcsParse.Create('git for-each-ref: drei Felder erwartet');
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
        Continue;
      mSlash := Pos('/', mRef.Name);
      if mSlash = 0 then
        Continue;
      mRef.LocalName := Copy(mRef.Name, mSlash + 1, MaxInt);
    end
    else
      Continue;
    if mRef.Name = '' then
      raise EAtlasVcsParse.Create('git for-each-ref: Name fehlt');
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
    raise EAtlasVcsParse.CreateFmt('git rev-list --count: "%s" unbekannt', [Trim(AText)]);
end;

class function TAtlasGitParser.ParseLines(const AText: string): TArray<string>;
var
  Line: string;
begin
  Result := nil;
  for Line in NonEmptyLines(AText) do
    Result := Result + [Trim(Line)];
end;

type
  TCommitInfo = record
    Hash: string;
    Author: string;
    Date: TDateTime;
    Summary: string;
  end;

class function TAtlasGitParser.ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>;
var
  Lines: TArray<string>;
  Commits: TArray<TCommitInfo>;
  CommitIndexOf: TDictionary<string, Integer>;
  Index, CommitIndex, CommitCount, Count, Final: Integer;
  Line, Hash, Key, Value: string;
  Seconds: Int64;
  Item: TAtlasVcsBlameLine;
begin
  Lines := AText.Split([#10]);
  // Höchstens eine Zeile und ein Commit je Kopfzeile: einmal anlegen statt je Zeile zu kopieren, Commits über ihren
  // Hash finden statt die Liste zu durchsuchen (#1109).
  SetLength(Result, Length(Lines));
  SetLength(Commits, Length(Lines));
  Count := 0;
  CommitCount := 0;
  CommitIndexOf := TDictionary<string, Integer>.Create;
  try
    Index := 0;
    while Index <= High(Lines) do
    begin
      Line := Lines[Index].TrimRight([#13]);
      Inc(Index);
      if Line = '' then
        Continue;
      // Kopfzeile: <hash> <ursprüngliche Zeile> <Zeile> [<Anzahl>]
      Hash := Field(Line, 0, False);
      if (Length(Hash) < 40) or not TryStrToInt(Field(Line, 2, False), Final) then
        raise EAtlasVcsParse.Create('git blame: Kopfzeile erwartet');
      if not CommitIndexOf.TryGetValue(Hash, CommitIndex) then
      begin
        CommitIndex := CommitCount;
        Inc(CommitCount);
        CommitIndexOf.Add(Hash, CommitIndex);
        Commits[CommitIndex].Hash := Hash;
        Commits[CommitIndex].Author := '';
        Commits[CommitIndex].Date := 0;
        Commits[CommitIndex].Summary := '';
      end;
      // Angaben zum Commit bis zur Inhaltszeile (beginnt mit Tab).
      while Index <= High(Lines) do
      begin
        Line := Lines[Index].TrimRight([#13]);
        Inc(Index);
        if (Line <> '') and (Line[1] = #9) then
          Break;
        Key := Field(Line, 0, False);
        Value := Field(Line, 1, True);
        if Key = 'author' then
          Commits[CommitIndex].Author := Value
        else if (Key = 'author-time') and TryStrToInt64(Value, Seconds) then
          Commits[CommitIndex].Date := VcsUnixToDate(Seconds)
        else if Key = 'summary' then
          Commits[CommitIndex].Summary := Value;
      end;
      Item.Line := Final;
      if Hash = NullCommit then
      begin
        // Noch nicht übernommen: git nennt "Not Committed Yet" und die Uhrzeit von jetzt.
        Item.Revision := '';
        Item.Author := '';
        Item.Date := 0;
        Item.Summary := '';
      end
      else
      begin
        Item.Revision := Hash;
        Item.Author := Commits[CommitIndex].Author;
        Item.Date := Commits[CommitIndex].Date;
        Item.Summary := Commits[CommitIndex].Summary;
      end;
      Result[Count] := Item;
      Inc(Count);
    end;
  finally
    CommitIndexOf.Free;
  end;
  SetLength(Result, Count);
end;

end.
