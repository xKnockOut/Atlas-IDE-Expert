unit Atlas.Core.Tracker.Development;

// Reiter „Entwicklung“ der Issue-Vorschau (#1269), ohne VCL und Open Tools
// API: Was zu einem Issue in der Versionsverwaltung liegt, gesammelt über
// IAtlasVcsHistory (#571), dazu der Teil des Trackers (Pull Requests mit
// CI-Ampel bzw. VCS-Änderungen, TAtlasTrackerDevelopment).
// - Branches: Branches, deren Name die Kennung trägt, wie „Beginnen“ sie
//   anlegt (#765, TAtlasTrackerNaming.KeyOfBranch); lokal und entfernt
//   gleichen Namens sind eine Zeile. Vorsprung und Rückstand gegenüber der
//   Basis (issues.branchBase, sonst main bzw. master; lokal vor origin/…);
//   SVN kennt das nicht (-1).
// - Commits: Suche nach der Kennung in den Nachrichten über alle Branches
//   (git log --all --grep, svn log --search); danach zählt nur, was die
//   Kennung als eigenes Stück trägt („#12“ nicht in „#123“, „ATL-1“ nicht in
//   „ATL-10“).
// - Geänderte Units: Vereinigung der Dateien aller Commits, je Datei der
//   jüngste Stand (gelöscht oder nicht), gruppiert nach Projekt: Eine Datei
//   gehört zum Projekt, das sie enthält (Module der Projektgruppe; .dfm/.fmx
//   über die .pas gleichen Namens), sonst zum Projekt mit dem tiefsten
//   Ordner, unter dem sie liegt; bei mehreren das erste nach Name. Was
//   übrig bleibt, steht in der Gruppe ohne Projekt (Name '', zuletzt).
// - Diff und Sprung: Zeilen je Datei (TAtlasTextDiff) und die erste geänderte
//   Zeile; die „erste geänderte Unit“ eines Commits ist die erste Pascal-Datei
//   (.pas, .dpr, .dpk, .inc), sonst die erste Datei, die noch existiert.
// - Zwischenspeicher je Tracker und Kennung im Speicher (zuletzt benutzte
//   MaxEntries); „Aktualisieren“ fragt neu.
// Kein Netz und kein Prozess hier außer über die übergebene Versionsverwaltung;
// Collect nur aus einem Hintergrund-Thread aufrufen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Vcs.Contract;

type
  /// <summary>Branch zum Issue; lokal und entfernt gleichen Namens zusammen.</summary>
  TAtlasIssueBranch = record
    /// <summary>Name ohne Remote, zum Wechseln ("feature/753-x"; SVN: Name unter ^/branches).</summary>
    Name: string;
    /// <summary>Entfernter Name ("origin/feature/753-x"); '' ohne. SVN: wie Name.</summary>
    RemoteName: string;
    Local: Boolean;
    Remote: Boolean;
    /// <summary>Die Arbeitskopie steht auf diesem Branch.</summary>
    Current: Boolean;
    /// <summary>Basis des Vergleichs ("main", "origin/main"); '' ohne.</summary>
    Base: string;
    /// <summary>Commits vor bzw. hinter der Basis; -1 unbekannt (SVN, keine Basis).</summary>
    Ahead: Integer;
    Behind: Integer;
    /// <summary>Letzter Commit (UTC); 0 unbekannt.</summary>
    TipDate: TDateTime;
  end;

  /// <summary>Geänderte Datei in der Vereinigung aller Commits.</summary>
  TAtlasIssueUnit = record
    /// <summary>Vollständiger Pfad in der Arbeitskopie.</summary>
    Path: string;
    /// <summary>Der jüngste Commit hat die Datei gelöscht.</summary>
    Deleted: Boolean;
    /// <summary>In so vielen Commits geändert.</summary>
    Commits: Integer;
  end;

  /// <summary>Dateien eines Projekts.</summary>
  TAtlasIssueUnitGroup = record
    /// <summary>Anzeigename des Projekts; '' = keinem Projekt zugeordnet.</summary>
    Project: string;
    /// <summary>Projektdatei (.dproj); '' ohne.</summary>
    ProjectFile: string;
    /// <summary>Nach Pfad sortiert.</summary>
    Units: TArray<TAtlasIssueUnit>;
  end;

  /// <summary>Projekt der Projektgruppe für die Zuordnung der Dateien.</summary>
  TAtlasIssueProject = record
    Name: string;
    FileName: string;
    /// <summary>Ordner der Projektdatei ohne Trenner am Ende.</summary>
    Folder: string;
    /// <summary>Dateien des Projekts (Module), vollständige Pfade.</summary>
    Files: TArray<string>;
    class function Create(const AFileName: string; const AFiles: TArray<string>): TAtlasIssueProject; static;
  end;

  /// <summary>Was gesucht wird.</summary>
  TAtlasIssueDevelopmentRequest = record
  public const
    /// <summary>Höchstens so viele Commits bzw. Branches.</summary>
    cDefaultMaxCommits = 200;
    cMaxBranches = 10;
  public
    /// <summary>Anbieter des Trackers ("github", "youtrack").</summary>
    Provider: string;
    /// <summary>Projekt im Tracker (YouTrack-Kürzel, GitHub "owner/repo"); für die Kennung im Branch-Namen.</summary>
    Project: string;
    /// <summary>Kennung wie im Tracker ("#753", "ATL-123").</summary>
    Key: string;
    /// <summary>Basis-Branches in der Reihenfolge des Versuchs; leer = ohne Vergleich.</summary>
    Bases: TArray<string>;
    Projects: TArray<TAtlasIssueProject>;
    MaxCommits: Integer;
    class function Create(const AProvider, AProject, AKey: string; const ABases: TArray<string>;
      const AProjects: TArray<TAtlasIssueProject>): TAtlasIssueDevelopmentRequest; static;
  end;

  /// <summary>Alles für den Reiter „Entwicklung“.</summary>
  TAtlasIssueDevelopment = record
    Key: string;
    VcsKind: TAtlasVcsKind;
    /// <summary>Ergebnis der Suche in der Versionsverwaltung (Ok, NoWorkingCopy, Disabled, ToolMissing …).</summary>
    VcsOutcome: TAtlasVcsOutcome;
    Branches: TArray<TAtlasIssueBranch>;
    /// <summary>Commits mit der Kennung, neueste zuerst.</summary>
    Commits: TArray<TAtlasVcsLogEntry>;
    /// <summary>Die Suche stieß an MaxCommits: Es kann ältere geben.</summary>
    Truncated: Boolean;
    Units: TArray<TAtlasIssueUnitGroup>;
    /// <summary>Teil des Trackers; TrackerLoaded False, wenn nicht abgefragt bzw. gescheitert (TrackerError).</summary>
    Tracker: TAtlasTrackerDevelopment;
    TrackerLoaded: Boolean;
    TrackerError: TAtlasCiFetchError;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    Fetched: TDateTime;
    class function Empty: TAtlasIssueDevelopment; static;
    /// <summary>Anzahl der Dateien über alle Gruppen.</summary>
    function UnitCount: Integer;
  end;

  /// <summary>Datei mit Inhalt vor und nach einem Commit, für den Diff.</summary>
  TAtlasIssueFileDiff = record
    /// <summary>Anzeigename (relativer Pfad).</summary>
    Caption: string;
    Before: string;
    After: string;
  end;

  TAtlasIssueDevelopmentQuery = class
  public
    /// <summary>Text für die grobe Suche in der Versionsverwaltung: die Kennung wie im Tracker.</summary>
    class function SearchText(const AKey: string): string; static;
    /// <summary>AText trägt AKey als eigenes Stück: kein Buchstabe und keine Ziffer davor, keine Ziffer danach; ohne
    /// Groß-/Kleinschreibung.</summary>
    class function MentionsKey(const AKey, AText: string): Boolean; static;
    /// <summary>Der Branch-Name trägt die Kennung (wie „Beginnen“ ihn anlegt).</summary>
    class function BranchMatches(const ARequest: TAtlasIssueDevelopmentRequest; const ABranch: string): Boolean;
      static;
    /// <summary>Branches, Commits und geänderte Units über AVcs (IAtlasVcsHistory); Tracker bleibt leer. Liefert
    /// das Ergebnis der Commit-Suche; ohne IAtlasVcsHistory NoWorkingCopy.</summary>
    class function Collect(const AVcs: IAtlasVersionControl; const ARequest: TAtlasIssueDevelopmentRequest;
      out ADevelopment: TAtlasIssueDevelopment): TAtlasVcsOutcome; static;
    /// <summary>Nur die Commits aus AEntries, die die Kennung tragen, in derselben Reihenfolge.</summary>
    class function Matching(const AKey: string; const AEntries: TArray<TAtlasVcsLogEntry>): TArray<TAtlasVcsLogEntry>;
      static;
    /// <summary>Branches aus ARefs mit der Kennung, lokal und entfernt zusammen, höchstens MaxBranches; die Basis
    /// (lokal vor origin/…) nach ARequest.Bases. Abstand noch -1.</summary>
    class function BranchesOf(const ARequest: TAtlasIssueDevelopmentRequest; const ARefs: TArray<TAtlasVcsRef>):
      TArray<TAtlasIssueBranch>; static;
    /// <summary>Vereinigung der Dateien, gruppiert nach Projekt (siehe Kopf der Unit).</summary>
    class function GroupUnits(const ACommits: TArray<TAtlasVcsLogEntry>;
      const AProjects: TArray<TAtlasIssueProject>): TArray<TAtlasIssueUnitGroup>; static;
    /// <summary>Erste Zeile (1-basiert) in ANew, die sich von AOld unterscheidet; 1, wenn gleich; die letzte
    /// Zeile, wenn nur hinten etwas wegfiel.</summary>
    class function FirstChangedLine(const AOld, ANew: string): Integer; static;
    /// <summary>Datei zum Öffnen bei Doppelklick: die erste Pascal-Datei, sonst die erste, die nicht gelöscht wurde
    /// und in der Arbeitskopie liegt; False ohne.</summary>
    class function OpenTarget(const AEntry: TAtlasVcsLogEntry; out AFile: TAtlasVcsLogFile): Boolean; static;
    /// <summary>Zeilen des Diffs: je Datei "=== Name ===" und die geänderten Zeilen; Dateien ohne Unterschied
    /// entfallen.</summary>
    class function DiffLines(const AFiles: TArray<TAtlasIssueFileDiff>): TArray<string>; static;
  end;

  /// <summary>Letzter Stand je Tracker und Kennung im Speicher, zuletzt benutzte zuerst.</summary>
  TAtlasIssueDevelopmentCache = class
  public const
    cMaxEntries = 50;
  private
    FKeys: TList<string>;
    FItems: TDictionary<string, TAtlasIssueDevelopment>;
    class function KeyOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const ATarget: TAtlasTrackerTarget; const ADevelopment: TAtlasIssueDevelopment);
    function Get(const ATarget: TAtlasTrackerTarget; const AKey: string;
      out ADevelopment: TAtlasIssueDevelopment): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

implementation

uses
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Core.Files.TextDiff,
  Atlas.Core.Tracker.Naming;

function IsAlnum(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['0'..'9', 'A'..'Z', 'a'..'z']);
end;

function IsPascalFile(const APath: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(APath));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.inc');
end;

function SameOrUnder(const AFolder, APath: string): Boolean;
var
  mFolder: string;
begin
  mFolder := IncludeTrailingPathDelimiter(AFolder);
  Result := (AFolder <> '') and SameText(Copy(APath, 1, Length(mFolder)), mFolder);
end;

{ TAtlasIssueProject }

class function TAtlasIssueProject.Create(const AFileName: string; const AFiles: TArray<string>): TAtlasIssueProject;
begin
  Result.FileName := AFileName;
  Result.Files := AFiles;
  Result.Name := ChangeFileExt(ExtractFileName(AFileName), '');
  Result.Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(AFileName));
end;

{ TAtlasIssueDevelopmentRequest }

class function TAtlasIssueDevelopmentRequest.Create(const AProvider, AProject, AKey: string;
  const ABases: TArray<string>; const AProjects: TArray<TAtlasIssueProject>): TAtlasIssueDevelopmentRequest;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Project := Trim(AProject);
  Result.Key := Trim(AKey);
  Result.Bases := ABases;
  Result.Projects := AProjects;
  Result.MaxCommits := cDefaultMaxCommits;
end;

{ TAtlasIssueDevelopment }

class function TAtlasIssueDevelopment.Empty: TAtlasIssueDevelopment;
begin
  Result := Default(TAtlasIssueDevelopment);
  Result.Branches := nil;
  Result.Commits := nil;
  Result.Units := nil;
  Result.Tracker := TAtlasTrackerDevelopment.Empty;
  Result.VcsOutcome := TAtlasVcsOutcome.NoWorkingCopy;
end;

function TAtlasIssueDevelopment.UnitCount: Integer;
var
  mGroup: TAtlasIssueUnitGroup;
begin
  Result := 0;
  for mGroup in Units do
  begin
    Inc(Result, Length(mGroup.Units));
  end;
end;

{ TAtlasIssueDevelopmentQuery }

class function TAtlasIssueDevelopmentQuery.SearchText(const AKey: string): string;
begin
  Result := Trim(AKey);
end;

/// <summary>Vor APos steht ein Repository wie "owner/repo" (GitHub-Verweis "owner/repo#12").</summary>
function AfterRepository(const AText: string; APos: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := APos - 1;
  while (mIndex >= 1) and (IsAlnum(AText[mIndex]) or CharInSet(AText[mIndex], ['.', '_', '-'])) do
  begin
    Dec(mIndex);
  end;
  Result := (mIndex >= 1) and (mIndex < APos - 1) and (AText[mIndex] = '/');
end;

/// <summary>Vor AIndex kein Buchstabe und keine Ziffer ("x#12" und "AATL-1" nicht), außer einem Repository vor
/// "#" ("owner/repo#12").</summary>
function FreeBefore(const AText, AKey: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex = 1) or not IsAlnum(AText[AIndex - 1]) or ((AKey[1] = '#') and AfterRepository(AText, AIndex));
end;

/// <summary>An AStop steht keine Ziffer mehr.</summary>
function FreeAfter(const AText: string; AStop: Integer): Boolean;
begin
  Result := (AStop > Length(AText)) or not CharInSet(AText[AStop], ['0'..'9']);
end;

class function TAtlasIssueDevelopmentQuery.MentionsKey(const AKey, AText: string): Boolean;
var
  mKey, mText: string;
  mIndex: Integer;
begin
  Result := False;
  mKey := UpperCase(Trim(AKey));
  if mKey = '' then
  begin
    Exit;
  end;
  mText := UpperCase(AText);
  mIndex := Pos(mKey, mText);
  while mIndex > 0 do
  begin
    if FreeBefore(mText, mKey, mIndex) and FreeAfter(mText, mIndex + Length(mKey)) then
    begin
      Exit(True);
    end;
    mIndex := Pos(mKey, mText, mIndex + 1);
  end;
end;

class function TAtlasIssueDevelopmentQuery.BranchMatches(const ARequest: TAtlasIssueDevelopmentRequest;
  const ABranch: string): Boolean;
var
  mProject: string;
begin
  // GitHub: das Projekt ist "owner/repo" und spielt für die Nummer keine Rolle.
  mProject := '';
  if SameText(ARequest.Provider, TAtlasTrackerTarget.cYouTrack) then
  begin
    mProject := ARequest.Project;
  end;
  Result := (ARequest.Key <> '') and
    SameText(TAtlasTrackerNaming.KeyOfBranch(ARequest.Provider, mProject, ABranch), ARequest.Key);
end;

class function TAtlasIssueDevelopmentQuery.Matching(const AKey: string;
  const AEntries: TArray<TAtlasVcsLogEntry>): TArray<TAtlasVcsLogEntry>;
var
  mEntry: TAtlasVcsLogEntry;
  mList: TList<TAtlasVcsLogEntry>;
begin
  mList := TList<TAtlasVcsLogEntry>.Create;
  try
    for mEntry in AEntries do
    begin
      if MentionsKey(AKey, mEntry.Message) then
      begin
        mList.Add(mEntry);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Ein Ref mit dem Namen AName (lokal bzw. entfernt) ist da.</summary>
function HasRef(const ARefs: TArray<TAtlasVcsRef>; const AName: string; ARemote: Boolean): Boolean;
var
  mRef: TAtlasVcsRef;
begin
  Result := False;
  for mRef in ARefs do
  begin
    if (mRef.Remote = ARemote) and SameText(mRef.Name, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Basis: der erste Kandidat, den es gibt, lokal vor origin/&lt;Name&gt;; '' ohne.</summary>
function BaseOf(const ABases: TArray<string>; const ARefs: TArray<TAtlasVcsRef>): string;
var
  mCandidate: string;
begin
  Result := '';
  for mCandidate in ABases do
  begin
    if Trim(mCandidate) = '' then
    begin
      Continue;
    end;
    if HasRef(ARefs, mCandidate, False) then
    begin
      Exit(mCandidate);
    end;
    if HasRef(ARefs, 'origin/' + mCandidate, True) then
    begin
      Exit('origin/' + mCandidate);
    end;
  end;
end;

/// <summary>Stelle des Branches ALocalName in ABranches; neu angelegt mit ABase, -1 wenn die Liste voll ist.
/// </summary>
function BranchIndex(var ABranches: TArray<TAtlasIssueBranch>; const ALocalName, ABase: string): Integer;
var
  mIndex: Integer;
  mBranch: TAtlasIssueBranch;
begin
  for mIndex := 0 to High(ABranches) do
  begin
    if SameText(ABranches[mIndex].Name, ALocalName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
  if Length(ABranches) < TAtlasIssueDevelopmentRequest.cMaxBranches then
  begin
    mBranch := Default(TAtlasIssueBranch);
    mBranch.Name := ALocalName;
    mBranch.Ahead := -1;
    mBranch.Behind := -1;
    mBranch.Base := ABase;
    ABranches := ABranches + [mBranch];
    Result := High(ABranches);
  end;
end;

/// <summary>ARef in den Branch übernehmen: lokal bzw. entfernt, aktuell, jüngster Commit.</summary>
procedure MergeRef(var ABranch: TAtlasIssueBranch; const ARef: TAtlasVcsRef);
begin
  if ARef.Remote then
  begin
    ABranch.Remote := True;
    ABranch.RemoteName := ARef.Name;
  end
  else
  begin
    ABranch.Local := True;
  end;
  ABranch.Current := ABranch.Current or ARef.Current;
  if ARef.TipDate > ABranch.TipDate then
  begin
    ABranch.TipDate := ARef.TipDate;
  end;
end;

class function TAtlasIssueDevelopmentQuery.BranchesOf(const ARequest: TAtlasIssueDevelopmentRequest;
  const ARefs: TArray<TAtlasVcsRef>): TArray<TAtlasIssueBranch>;
var
  mRef: TAtlasVcsRef;
  mFound: Integer;
  mBase: string;
begin
  Result := nil;
  mBase := BaseOf(ARequest.Bases, ARefs);
  for mRef in ARefs do
  begin
    if not BranchMatches(ARequest, mRef.LocalName) then
    begin
      Continue;
    end;
    mFound := BranchIndex(Result, mRef.LocalName, mBase);
    if mFound >= 0 then
    begin
      MergeRef(Result[mFound], mRef);
    end;
  end;
end;

/// <summary>Projekte nach Name: Bei gleichem Ordner gewinnt das erste.</summary>
function SortedProjects(const AProjects: TArray<TAtlasIssueProject>): TArray<TAtlasIssueProject>;
begin
  Result := Copy(AProjects, 0, Length(AProjects));
  TArray.Sort<TAtlasIssueProject>(Result, TComparer<TAtlasIssueProject>.Construct(
    function(const ALeft, ARight: TAtlasIssueProject): Integer
    begin
      Result := CompareText(ALeft.Name, ARight.Name);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.FileName, ARight.FileName);
      end;
    end));
end;

/// <summary>Datei (klein geschrieben) → erstes Projekt in AProjects, das sie enthält.</summary>
procedure AddMembers(AMembers: TDictionary<string, Integer>; const AProjects: TArray<TAtlasIssueProject>);
var
  mIndex: Integer;
  mMember: string;
begin
  for mIndex := 0 to High(AProjects) do
  begin
    for mMember in AProjects[mIndex].Files do
    begin
      if not AMembers.ContainsKey(LowerCase(mMember)) then
      begin
        AMembers.Add(LowerCase(mMember), mIndex);
      end;
    end;
  end;
end;

/// <summary>Geänderte Dateien aller Commits in AFiles, die Schlüssel in der Reihenfolge des ersten Auftretens in
/// AOrder. Commits kommen neueste zuerst: Der erste Eintrag einer Datei ist ihr jüngster Stand.</summary>
procedure CollectUnits(const ACommits: TArray<TAtlasVcsLogEntry>; AFiles: TDictionary<string, TAtlasIssueUnit>;
  AOrder: TList<string>);
var
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
  mUnit: TAtlasIssueUnit;
  mKey: string;
begin
  for mEntry in ACommits do
  begin
    for mFile in mEntry.Files do
    begin
      mKey := LowerCase(mFile.Path);
      if mFile.Path = '' then
      begin
        Continue;
      end;
      if AFiles.TryGetValue(mKey, mUnit) then
      begin
        Inc(mUnit.Commits);
        AFiles[mKey] := mUnit;
        Continue;
      end;
      mUnit := Default(TAtlasIssueUnit);
      mUnit.Path := mFile.Path;
      mUnit.Deleted := mFile.Kind = TAtlasVcsChangeKind.Deleted;
      mUnit.Commits := 1;
      AFiles.Add(mKey, mUnit);
      AOrder.Add(mKey);
    end;
  end;
end;

/// <summary>Projekt einer Datei: über die Liste des Projekts (Formular über seine .pas), sonst das tiefste
/// Projekt, unter dessen Ordner sie liegt; Length(AProjects) = ohne Projekt.</summary>
function ProjectOf(AMembers: TDictionary<string, Integer>; const AProjects: TArray<TAtlasIssueProject>;
  const AKey, APath: string): Integer;
var
  mExt: string;
  mIndex: Integer;
begin
  if AMembers.TryGetValue(AKey, Result) then
  begin
    Exit;
  end;
  mExt := LowerCase(ExtractFileExt(APath));
  if ((mExt = '.dfm') or (mExt = '.fmx')) and AMembers.TryGetValue(LowerCase(ChangeFileExt(APath, '.pas')),
    Result) then
  begin
    Exit;
  end;
  Result := -1;
  for mIndex := 0 to High(AProjects) do
  begin
    if SameOrUnder(AProjects[mIndex].Folder, APath) and
      ((Result < 0) or (Length(AProjects[mIndex].Folder) > Length(AProjects[Result].Folder))) then
    begin
      Result := mIndex;
    end;
  end;
  if Result < 0 then
  begin
    Result := Length(AProjects);
  end;
end;

function UnitOrder: IComparer<TAtlasIssueUnit>;
begin
  Result := TComparer<TAtlasIssueUnit>.Construct(
    function(const ALeft, ARight: TAtlasIssueUnit): Integer
    begin
      Result := CompareText(ALeft.Path, ARight.Path);
      if Result = 0 then
      begin
        Result := CompareStr(ALeft.Path, ARight.Path);
      end;
    end);
end;

/// <summary>Gruppen aus den Listen je Projekt (die letzte ist „ohne Projekt“); leere entfallen.</summary>
function GroupsOf(const AByGroup: TArray<TList<TAtlasIssueUnit>>;
  const AProjects: TArray<TAtlasIssueProject>): TArray<TAtlasIssueUnitGroup>;
var
  mGroupIndex: Integer;
  mGroup: TAtlasIssueUnitGroup;
begin
  Result := nil;
  for mGroupIndex := 0 to High(AByGroup) do
  begin
    if AByGroup[mGroupIndex].Count = 0 then
    begin
      Continue;
    end;
    AByGroup[mGroupIndex].Sort(UnitOrder());
    mGroup := Default(TAtlasIssueUnitGroup);
    if mGroupIndex < Length(AProjects) then
    begin
      mGroup.Project := AProjects[mGroupIndex].Name;
      mGroup.ProjectFile := AProjects[mGroupIndex].FileName;
    end;
    mGroup.Units := AByGroup[mGroupIndex].ToArray;
    Result := Result + [mGroup];
  end;
end;

/// <summary>Dateien aus AOrder je Projekt gruppieren.</summary>
function GroupByProject(AFiles: TDictionary<string, TAtlasIssueUnit>; AOrder: TList<string>;
  AMembers: TDictionary<string, Integer>; const AProjects: TArray<TAtlasIssueProject>):
  TArray<TAtlasIssueUnitGroup>;
var
  mByGroup: TArray<TList<TAtlasIssueUnit>>;
  mIndex: Integer;
  mKey: string;
  mUnit: TAtlasIssueUnit;
begin
  // Eine Liste je Projekt und eine für „ohne Projekt“ (letzte).
  SetLength(mByGroup, Length(AProjects) + 1);
  for mIndex := 0 to High(mByGroup) do
  begin
    mByGroup[mIndex] := TList<TAtlasIssueUnit>.Create;
  end;
  try
    for mKey in AOrder do
    begin
      if AFiles.TryGetValue(mKey, mUnit) then
      begin
        mByGroup[ProjectOf(AMembers, AProjects, mKey, mUnit.Path)].Add(mUnit);
      end;
    end;
    Result := GroupsOf(mByGroup, AProjects);
  finally
    for mIndex := 0 to High(mByGroup) do
    begin
      mByGroup[mIndex].Free;
    end;
  end;
end;

class function TAtlasIssueDevelopmentQuery.GroupUnits(const ACommits: TArray<TAtlasVcsLogEntry>;
  const AProjects: TArray<TAtlasIssueProject>): TArray<TAtlasIssueUnitGroup>;
var
  mFiles: TDictionary<string, TAtlasIssueUnit>;
  mOrder: TList<string>;
  mProjects: TArray<TAtlasIssueProject>;
  mMembers: TDictionary<string, Integer>;
begin
  Result := nil;
  mProjects := SortedProjects(AProjects);
  mFiles := TDictionary<string, TAtlasIssueUnit>.Create;
  mOrder := TList<string>.Create;
  mMembers := TDictionary<string, Integer>.Create;
  try
    AddMembers(mMembers, mProjects);
    CollectUnits(ACommits, mFiles, mOrder);
    if mOrder.Count > 0 then
    begin
      Result := GroupByProject(mFiles, mOrder, mMembers, mProjects);
    end;
  finally
    mMembers.Free;
    mOrder.Free;
    mFiles.Free;
  end;
end;

class function TAtlasIssueDevelopmentQuery.Collect(const AVcs: IAtlasVersionControl;
  const ARequest: TAtlasIssueDevelopmentRequest; out ADevelopment: TAtlasIssueDevelopment): TAtlasVcsOutcome;
var
  mHistory: IAtlasVcsHistory;
  mEntries: TArray<TAtlasVcsLogEntry>;
  mRefs: TArray<TAtlasVcsRef>;
  mIndex, mAhead, mBehind, mMax: Integer;
  mFrom: string;
begin
  ADevelopment := TAtlasIssueDevelopment.Empty;
  ADevelopment.Key := ARequest.Key;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsHistory, mHistory) then
  begin
    Exit(TAtlasVcsOutcome.NoWorkingCopy);
  end;
  ADevelopment.VcsKind := AVcs.Kind;
  if ARequest.Key = '' then
  begin
    ADevelopment.VcsOutcome := TAtlasVcsOutcome.Failed;
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mMax := ARequest.MaxCommits;
  if mMax < 1 then
  begin
    mMax := TAtlasIssueDevelopmentRequest.cDefaultMaxCommits;
  end;
  Result := mHistory.SearchLog(SearchText(ARequest.Key), mMax, mEntries);
  ADevelopment.VcsOutcome := Result;
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  ADevelopment.Truncated := Length(mEntries) >= mMax;
  ADevelopment.Commits := Matching(ARequest.Key, mEntries);
  ADevelopment.Units := GroupUnits(ADevelopment.Commits, ARequest.Projects);
  // Branches gehören dazu, scheitern aber nicht die ganze Abfrage (SVN ohne ^/branches).
  if mHistory.AllBranches(mRefs) <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  ADevelopment.Branches := BranchesOf(ARequest, mRefs);
  for mIndex := 0 to High(ADevelopment.Branches) do
  begin
    if ADevelopment.Branches[mIndex].Base = '' then
    begin
      Continue;
    end;
    mFrom := ADevelopment.Branches[mIndex].Name;
    if not ADevelopment.Branches[mIndex].Local then
    begin
      mFrom := ADevelopment.Branches[mIndex].RemoteName;
    end;
    if mHistory.Distance(mFrom, ADevelopment.Branches[mIndex].Base, mAhead, mBehind) = TAtlasVcsOutcome.Ok then
    begin
      ADevelopment.Branches[mIndex].Ahead := mAhead;
      ADevelopment.Branches[mIndex].Behind := mBehind;
    end;
  end;
end;

class function TAtlasIssueDevelopmentQuery.FirstChangedLine(const AOld, ANew: string): Integer;
var
  mOld, mNew: TArray<string>;
  mIndex: Integer;
begin
  mOld := TTextLines.SplitLines(AOld);
  mNew := TTextLines.SplitLines(ANew);
  for mIndex := 0 to High(mNew) do
  begin
    if (mIndex > High(mOld)) or (mOld[mIndex] <> mNew[mIndex]) then
    begin
      Exit(mIndex + 1);
    end;
  end;
  // Gleich oder nur hinten gekürzt: die letzte Zeile.
  Result := Length(mNew);
  if Result < 1 then
  begin
    Result := 1;
  end;
end;

class function TAtlasIssueDevelopmentQuery.OpenTarget(const AEntry: TAtlasVcsLogEntry;
  out AFile: TAtlasVcsLogFile): Boolean;
var
  mFile: TAtlasVcsLogFile;
begin
  for mFile in AEntry.Files do
  begin
    if (mFile.Path <> '') and (mFile.Kind <> TAtlasVcsChangeKind.Deleted) and IsPascalFile(mFile.Path) then
    begin
      AFile := mFile;
      Exit(True);
    end;
  end;
  for mFile in AEntry.Files do
  begin
    if (mFile.Path <> '') and (mFile.Kind <> TAtlasVcsChangeKind.Deleted) then
    begin
      AFile := mFile;
      Exit(True);
    end;
  end;
  AFile := Default(TAtlasVcsLogFile);
  Result := False;
end;

class function TAtlasIssueDevelopmentQuery.DiffLines(const AFiles: TArray<TAtlasIssueFileDiff>): TArray<string>;
var
  mFile: TAtlasIssueFileDiff;
  mLines: TArray<string>;
begin
  Result := nil;
  for mFile in AFiles do
  begin
    mLines := TAtlasTextDiff.Lines(mFile.Before, mFile.After);
    if Length(mLines) = 0 then
    begin
      Continue;
    end;
    if Length(Result) > 0 then
    begin
      Result := Result + [''];
    end;
    Result := Result + ['=== ' + mFile.Caption + ' ==='] + mLines;
  end;
end;

{ TAtlasIssueDevelopmentCache }

constructor TAtlasIssueDevelopmentCache.Create;
begin
  inherited Create;
  FKeys := TList<string>.Create;
  FItems := TDictionary<string, TAtlasIssueDevelopment>.Create;
end;

destructor TAtlasIssueDevelopmentCache.Destroy;
begin
  FItems.Free;
  FKeys.Free;
  inherited;
end;

class function TAtlasIssueDevelopmentCache.KeyOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := ATarget.Key + '|' + UpperCase(Trim(AKey));
end;

procedure TAtlasIssueDevelopmentCache.Put(const ATarget: TAtlasTrackerTarget;
  const ADevelopment: TAtlasIssueDevelopment);
var
  mKey: string;
begin
  mKey := KeyOf(ATarget, ADevelopment.Key);
  FKeys.Remove(mKey);
  FKeys.Insert(0, mKey);
  FItems.AddOrSetValue(mKey, ADevelopment);
  while FKeys.Count > cMaxEntries do
  begin
    FItems.Remove(FKeys[FKeys.Count - 1]);
    FKeys.Delete(FKeys.Count - 1);
  end;
end;

function TAtlasIssueDevelopmentCache.Get(const ATarget: TAtlasTrackerTarget; const AKey: string;
  out ADevelopment: TAtlasIssueDevelopment): Boolean;
var
  mKey: string;
begin
  mKey := KeyOf(ATarget, AKey);
  Result := FItems.TryGetValue(mKey, ADevelopment);
  if not Result then
  begin
    ADevelopment := TAtlasIssueDevelopment.Empty;
    Exit;
  end;
  FKeys.Remove(mKey);
  FKeys.Insert(0, mKey);
end;

procedure TAtlasIssueDevelopmentCache.Clear;
begin
  FKeys.Clear;
  FItems.Clear;
end;

function TAtlasIssueDevelopmentCache.Count: Integer;
begin
  Result := FKeys.Count;
end;

end.
