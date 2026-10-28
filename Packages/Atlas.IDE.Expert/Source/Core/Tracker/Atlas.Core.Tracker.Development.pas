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
  Atlas.Core.Ci.Contract,
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
    MaxCommits = 200;
    MaxBranches = 10;
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
    MaxEntries = 50;
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
  Result.MaxCommits := MaxCommits;
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
    Inc(Result, Length(mGroup.Units));
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
    Dec(mIndex);
  Result := (mIndex >= 1) and (mIndex < APos - 1) and (AText[mIndex] = '/');
end;

class function TAtlasIssueDevelopmentQuery.MentionsKey(const AKey, AText: string): Boolean;
var
  mKey, mText: string;
  mIndex, mStop: Integer;
begin
  Result := False;
  mKey := UpperCase(Trim(AKey));
  if mKey = '' then
    Exit;
  mText := UpperCase(AText);
  mIndex := Pos(mKey, mText);
  while mIndex > 0 do
  begin
    mStop := mIndex + Length(mKey);
    // Davor kein Buchstabe und keine Ziffer ("x#12" und "AATL-1" nicht), außer einem Repository vor "#"
    // ("owner/repo#12"); danach keine Ziffer.
    if ((mIndex = 1) or not IsAlnum(mText[mIndex - 1]) or ((mKey[1] = '#') and AfterRepository(mText, mIndex))) and
      ((mStop > Length(mText)) or not CharInSet(mText[mStop], ['0'..'9'])) then
      Exit(True);
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
  if SameText(ARequest.Provider, TAtlasTrackerTarget.YouTrack) then
    mProject := ARequest.Project;
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
      if MentionsKey(AKey, mEntry.Message) then
        mList.Add(mEntry);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasIssueDevelopmentQuery.BranchesOf(const ARequest: TAtlasIssueDevelopmentRequest;
  const ARefs: TArray<TAtlasVcsRef>): TArray<TAtlasIssueBranch>;
var
  mRef: TAtlasVcsRef;
  mIndex, mFound: Integer;
  mBranch: TAtlasIssueBranch;
  mBase, mCandidate: string;
  mLocal, mRemote: TDictionary<string, Boolean>;
begin
  Result := nil;
  mLocal := TDictionary<string, Boolean>.Create;
  mRemote := TDictionary<string, Boolean>.Create;
  try
    for mRef in ARefs do
      if mRef.Remote then
        mRemote.AddOrSetValue(LowerCase(mRef.Name), True)
      else
        mLocal.AddOrSetValue(LowerCase(mRef.Name), True);
    // Basis: der erste Kandidat, den es gibt, lokal vor origin/<Name>.
    mBase := '';
    for mCandidate in ARequest.Bases do
    begin
      if Trim(mCandidate) = '' then
        Continue;
      if mLocal.ContainsKey(LowerCase(mCandidate)) then
        mBase := mCandidate
      else if mRemote.ContainsKey(LowerCase('origin/' + mCandidate)) then
        mBase := 'origin/' + mCandidate;
      if mBase <> '' then
        Break;
    end;
    for mRef in ARefs do
    begin
      if not BranchMatches(ARequest, mRef.LocalName) then
        Continue;
      mFound := -1;
      for mIndex := 0 to High(Result) do
        if SameText(Result[mIndex].Name, mRef.LocalName) then
          mFound := mIndex;
      if mFound < 0 then
      begin
        if Length(Result) >= TAtlasIssueDevelopmentRequest.MaxBranches then
          Continue;
        mBranch := Default(TAtlasIssueBranch);
        mBranch.Name := mRef.LocalName;
        mBranch.Ahead := -1;
        mBranch.Behind := -1;
        mBranch.Base := mBase;
        Result := Result + [mBranch];
        mFound := High(Result);
      end;
      if mRef.Remote then
      begin
        Result[mFound].Remote := True;
        Result[mFound].RemoteName := mRef.Name;
      end
      else
        Result[mFound].Local := True;
      if mRef.Current then
        Result[mFound].Current := True;
      if mRef.TipDate > Result[mFound].TipDate then
        Result[mFound].TipDate := mRef.TipDate;
    end;
  finally
    mLocal.Free;
    mRemote.Free;
  end;
end;

class function TAtlasIssueDevelopmentQuery.GroupUnits(const ACommits: TArray<TAtlasVcsLogEntry>;
  const AProjects: TArray<TAtlasIssueProject>): TArray<TAtlasIssueUnitGroup>;
var
  mFiles: TDictionary<string, TAtlasIssueUnit>;
  mOrder: TList<string>;
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
  mUnit: TAtlasIssueUnit;
  mKey, mPath: string;
  mGroups: TList<TAtlasIssueUnitGroup>;
  mGroup: TAtlasIssueUnitGroup;
  mProjects: TArray<TAtlasIssueProject>;
  mIndex, mBest, mGroupIndex: Integer;
  mUnits: TList<TAtlasIssueUnit>;
  mByGroup: TArray<TList<TAtlasIssueUnit>>;
  mMembers: TDictionary<string, Integer>;
  mMember, mExt: string;
begin
  Result := nil;
  // Projekte nach Name: Bei gleichem Ordner gewinnt das erste.
  mProjects := Copy(AProjects, 0, Length(AProjects));
  TArray.Sort<TAtlasIssueProject>(mProjects, TComparer<TAtlasIssueProject>.Construct(
    function(const ALeft, ARight: TAtlasIssueProject): Integer
    begin
      Result := CompareText(ALeft.Name, ARight.Name);
      if Result = 0 then
        Result := CompareText(ALeft.FileName, ARight.FileName);
    end));
  mFiles := TDictionary<string, TAtlasIssueUnit>.Create;
  mOrder := TList<string>.Create;
  mGroups := TList<TAtlasIssueUnitGroup>.Create;
  mMembers := TDictionary<string, Integer>.Create;
  try
    // Datei → erstes Projekt (nach Name), das sie enthält.
    for mIndex := 0 to High(mProjects) do
      for mMember in mProjects[mIndex].Files do
        if not mMembers.ContainsKey(LowerCase(mMember)) then
          mMembers.Add(LowerCase(mMember), mIndex);
    // Commits kommen neueste zuerst: Der erste Eintrag einer Datei ist ihr jüngster Stand.
    for mEntry in ACommits do
      for mFile in mEntry.Files do
      begin
        if mFile.Path = '' then
          Continue;
        mKey := LowerCase(mFile.Path);
        if mFiles.TryGetValue(mKey, mUnit) then
        begin
          Inc(mUnit.Commits);
          mFiles[mKey] := mUnit;
          Continue;
        end;
        mUnit := Default(TAtlasIssueUnit);
        mUnit.Path := mFile.Path;
        mUnit.Deleted := mFile.Kind = TAtlasVcsChangeKind.Deleted;
        mUnit.Commits := 1;
        mFiles.Add(mKey, mUnit);
        mOrder.Add(mKey);
      end;
    if mOrder.Count = 0 then
      Exit;
    // Eine Liste je Projekt und eine für „ohne Projekt“ (letzte).
    SetLength(mByGroup, Length(mProjects) + 1);
    for mIndex := 0 to High(mByGroup) do
      mByGroup[mIndex] := TList<TAtlasIssueUnit>.Create;
    try
      for mKey in mOrder do
      begin
        mUnit := mFiles[mKey];
        mPath := mUnit.Path;
        mExt := LowerCase(ExtractFileExt(mPath));
        if not mMembers.TryGetValue(mKey, mBest) and (((mExt <> '.dfm') and (mExt <> '.fmx')) or
          not mMembers.TryGetValue(LowerCase(ChangeFileExt(mPath, '.pas')), mBest)) then
          mBest := -1;
        if mBest < 0 then
          for mIndex := 0 to High(mProjects) do
            if SameOrUnder(mProjects[mIndex].Folder, mPath) and
              ((mBest < 0) or (Length(mProjects[mIndex].Folder) > Length(mProjects[mBest].Folder))) then
              mBest := mIndex;
        if mBest < 0 then
          mBest := Length(mProjects);
        mByGroup[mBest].Add(mUnit);
      end;
      for mGroupIndex := 0 to High(mByGroup) do
      begin
        mUnits := mByGroup[mGroupIndex];
        if mUnits.Count = 0 then
          Continue;
        mUnits.Sort(TComparer<TAtlasIssueUnit>.Construct(
          function(const ALeft, ARight: TAtlasIssueUnit): Integer
          begin
            Result := CompareText(ALeft.Path, ARight.Path);
            if Result = 0 then
              Result := CompareStr(ALeft.Path, ARight.Path);
          end));
        mGroup := Default(TAtlasIssueUnitGroup);
        if mGroupIndex < Length(mProjects) then
        begin
          mGroup.Project := mProjects[mGroupIndex].Name;
          mGroup.ProjectFile := mProjects[mGroupIndex].FileName;
        end;
        mGroup.Units := mUnits.ToArray;
        mGroups.Add(mGroup);
      end;
    finally
      for mIndex := 0 to High(mByGroup) do
        mByGroup[mIndex].Free;
    end;
    Result := mGroups.ToArray;
  finally
    mMembers.Free;
    mGroups.Free;
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
    Exit(TAtlasVcsOutcome.NoWorkingCopy);
  ADevelopment.VcsKind := AVcs.Kind;
  if ARequest.Key = '' then
  begin
    ADevelopment.VcsOutcome := TAtlasVcsOutcome.Failed;
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mMax := ARequest.MaxCommits;
  if mMax < 1 then
    mMax := TAtlasIssueDevelopmentRequest.MaxCommits;
  Result := mHistory.SearchLog(SearchText(ARequest.Key), mMax, mEntries);
  ADevelopment.VcsOutcome := Result;
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  ADevelopment.Truncated := Length(mEntries) >= mMax;
  ADevelopment.Commits := Matching(ARequest.Key, mEntries);
  ADevelopment.Units := GroupUnits(ADevelopment.Commits, ARequest.Projects);
  // Branches gehören dazu, scheitern aber nicht die ganze Abfrage (SVN ohne ^/branches).
  if mHistory.AllBranches(mRefs) <> TAtlasVcsOutcome.Ok then
    Exit;
  ADevelopment.Branches := BranchesOf(ARequest, mRefs);
  for mIndex := 0 to High(ADevelopment.Branches) do
  begin
    if ADevelopment.Branches[mIndex].Base = '' then
      Continue;
    mFrom := ADevelopment.Branches[mIndex].Name;
    if not ADevelopment.Branches[mIndex].Local then
      mFrom := ADevelopment.Branches[mIndex].RemoteName;
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
    if (mIndex > High(mOld)) or (mOld[mIndex] <> mNew[mIndex]) then
      Exit(mIndex + 1);
  // Gleich oder nur hinten gekürzt: die letzte Zeile.
  Result := Length(mNew);
  if Result < 1 then
    Result := 1;
end;

class function TAtlasIssueDevelopmentQuery.OpenTarget(const AEntry: TAtlasVcsLogEntry;
  out AFile: TAtlasVcsLogFile): Boolean;
var
  mFile: TAtlasVcsLogFile;
begin
  for mFile in AEntry.Files do
    if (mFile.Path <> '') and (mFile.Kind <> TAtlasVcsChangeKind.Deleted) and IsPascalFile(mFile.Path) then
    begin
      AFile := mFile;
      Exit(True);
    end;
  for mFile in AEntry.Files do
    if (mFile.Path <> '') and (mFile.Kind <> TAtlasVcsChangeKind.Deleted) then
    begin
      AFile := mFile;
      Exit(True);
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
      Continue;
    if Length(Result) > 0 then
      Result := Result + [''];
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
  while FKeys.Count > MaxEntries do
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
