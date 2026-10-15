unit Atlas.Core.Vcs.Internals.GitParser;

// Liest die Ausgaben von git für die Versionsverwaltung (#571):
//   git status --porcelain=v2 --branch -z      Branch, Commit, verfolgter Branch,
//                                              Vorsprung/Rückstand, Änderungen
//   git blame --porcelain                      Zeilenherkunft
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
  end;

implementation

uses
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
  Index, CommitIndex, Final, Search: Integer;
  Line, Hash, Key, Value: string;
  Seconds: Int64;
  Item: TAtlasVcsBlameLine;
begin
  Result := nil;
  Commits := nil;
  Lines := AText.Split([#10]);
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
    CommitIndex := -1;
    for Search := 0 to High(Commits) do
      if Commits[Search].Hash = Hash then
        CommitIndex := Search;
    if CommitIndex < 0 then
    begin
      SetLength(Commits, Length(Commits) + 1);
      CommitIndex := High(Commits);
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
    Result := Result + [Item];
  end;
end;

end.
