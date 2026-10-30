unit Atlas.Common.Hotspots.Service;

// Hotspots je Projekt (#1354) für Fenster, Bericht, Kommandozeile und
// get_hotspots: ein Dienst, dieselben Zahlen.
//
// - Umfang wie die Architekturübersicht (#1118): Units des Index, deren Datei
//   in ARequest.Files steht (leer = alle), nie Bibliotheks-Units, nie
//   Packages (.dpk), Ausschlüsse aus architecture.exclude; nur Dateien unter
//   der Wurzel der Arbeitskopie. Der Uses-Graph derselben Units liefert die
//   Kanten für die Änderungskopplung.
// - Verlauf: ein Aufruf von IHotspotVcs.Log je Zeitraum und Stand (HEAD),
//   Pfade auf den heutigen Namen (FollowRenames). Gilt bis zum nächsten
//   Commit; ohne bekannten Stand wird jedes Mal neu gelesen.
// - Komplexität nur für Units mit Änderungen (die übrigen haben den Wert 0),
//   über TMetricsCollector (unveränderter Text kommt aus seinem Speicher).
// - Trend für die obersten THotspotOptions.TrendCandidates Units: Text im
//   Stand vor TrendMonths Monaten (unter dem damaligen Namen) über
//   IHotspotVcs.TextAt.
// - Methodenebene: Kandidaten sind die Routinen (ohne lokale) der Units mit
//   Änderungen, vorsortiert nach Änderungen der Unit × Komplexität der
//   Routine; nur die obersten MethodCandidates lesen ihren Verlauf über
//   IHotspotVcs.LineLog (git log -L bzw. svn log --diff). Ergebnisse je
//   Stand gemerkt.
// - Ergebnis gilt, solange Stand, Index-Generation und Anfrage gleich
//   bleiben. Rechnen läuft unter einer Sperre im Arbeitsthread des Aufrufers,
//   nie im Hauptthread der IDE.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis;

type
  EHotspots = class(Exception);

  THotspotRequest = record
    Title: string;
    /// <summary>Projektordner; Ausschlüsse gelten relativ dazu.</summary>
    Root: string;
    Level: THotspotLevel;
    Options: THotspotOptions;
    Exclude: TArray<string>;
    Namespaces: TArray<string>;
    /// <summary>Dateien im Umfang; leer = alle Projekt-Units des Index.</summary>
    Files: TArray<string>;
    /// <summary>Werte aus hotspots.* und architecture.exclude.</summary>
    class function FromSettings(const ASettings: TServerSettings): THotspotRequest; static;
    /// <summary>Text, der die Anfrage eindeutig beschreibt (Schlüssel des Zwischenspeichers).</summary>
    function Key: string;
  end;

  /// <summary>Stand einer Datei vor dem Trend-Abstand.</summary>
  THotspotPastText = record
    State: THotspotTextState;
    Routines: TArray<TRoutineMetrics>;
  end;

  THotspotService = class
  private
    FIndex: ISymbolIndex;
    FReadText: TMetricsReadText;
    FMetrics: TMetricsCollector;
    FLock: TObject;
    FHistoryKey: string;
    FHistory: TArray<THotspotCommit>;
    FSince: TDateTime;
    FResultKey: string;
    FResult: THotspotResult;
    FHasResult: Boolean;
    /// <summary>Verlauf je Methode und Stand (Schlüssel: Stand, Datei, Zeilen).</summary>
    FLineLogs: TDictionary<string, TArray<THotspotLineCommit>>;
    /// <summary>Routinen im Stand vor dem Trend-Abstand je Datei (gilt für FHistoryKey).</summary>
    FPast: TDictionary<string, THotspotPastText>;
    FComputations: Integer;
    FHistoryReads: Integer;
    FLineLogReads: Integer;
    function History(const AVcs: IHotspotVcs; AMonths: Integer; ANow: TDateTime; out AKey: string):
      TArray<THotspotCommit>;
    function ScopeUnits(const ARequest: THotspotRequest; const AVcsRoot: string;
      AEdges: TDictionary<Int64, Boolean>): TArray<THotspotUnit>;
    function PathAt(const APath: string; ADate: TDateTime): string;
    function PastRoutines(const AVcs: IHotspotVcs; const APath: string; ADate: TDateTime;
      out ARoutines: TArray<TRoutineMetrics>): THotspotTextState;
    procedure ApplyTrends(const AVcs: IHotspotVcs; var AEntries: TArray<THotspotEntry>; ACount: Integer;
      ADate: TDateTime);
    function MethodEntries(const AVcs: IHotspotVcs; const ARequest: THotspotRequest;
      const AUnits: TArray<THotspotEntry>; const ARoutines: TDictionary<string, TArray<TRoutineMetrics>>):
      TArray<THotspotEntry>;
    function Compute(const ARequest: THotspotRequest; const AVcs: IHotspotVcs; ANow: TDateTime;
      AGeneration: Int64): THotspotResult;
  public
    /// <summary>AReadText liest Quelltexte (geöffnetes Dokument oder Platte).</summary>
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TMetricsReadText);
    destructor Destroy; override;
    /// <summary>Hotspots zur Anfrage; EHotspots, wenn git bzw. svn scheitert.</summary>
    function Analyze(const ARequest: THotspotRequest; const AVcs: IHotspotVcs): THotspotResult; overload;
    /// <summary>Wie oben mit festem „jetzt“ (UTC, Tests).</summary>
    function Analyze(const ARequest: THotspotRequest; const AVcs: IHotspotVcs; ANow: TDateTime): THotspotResult;
      overload;
    /// <summary>Wie oft wirklich gerechnet, der Verlauf gelesen bzw. ein Methodenverlauf gelesen wurde (Tests).
    /// </summary>
    function Computations: Integer;
    function HistoryReads: Integer;
    function LineLogReads: Integer;
  end;

  /// <summary>Kognitive Komplexität einer Unit: Summe über alle Routinen (lokale zählen für sich).</summary>
function HotspotComplexity(const ARoutines: TArray<TRoutineMetrics>): Integer;

implementation

uses
  System.Math,
  System.DateUtils,
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Hotspots.History;

function HotspotComplexity(const ARoutines: TArray<TRoutineMetrics>): Integer;
var
  mRoutine: TRoutineMetrics;
begin
  Result := 0;
  for mRoutine in ARoutines do
    Inc(Result, mRoutine.Values[TMetricKind.Cognitive]);
end;

function LineCount(const AText: string): Integer;
var
  mChar: Char;
begin
  if AText = '' then
    Exit(0);
  Result := 1;
  for mChar in AText do
    if mChar = #10 then
      Inc(Result);
end;

/// <summary>Pfad relativ zu ARoot mit "/"; False außerhalb.</summary>
function RelativePath(const ARoot, AFileName: string; out ARelative: string): Boolean;
var
  mRoot, mFile: string;
begin
  mFile := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
    mRoot := mRoot + '/';
  Result := (mRoot <> '') and StartsText(mRoot, mFile) and (Length(mFile) > Length(mRoot));
  if Result then
    ARelative := Copy(mFile, Length(mRoot) + 1, MaxInt)
  else
    ARelative := '';
end;

/// <summary>Schlüssel einer ungerichteten Kante zwischen zwei Units (Index in der Unit-Liste).</summary>
function EdgeKey(AFirst, ASecond: Integer; ACount: Int64): Int64;
begin
  Result := Min(AFirst, ASecond) * ACount + Max(AFirst, ASecond);
end;

/// <summary>Abfrage der Kanten als Methodenreferenz; in eigener Routine, damit sie nur AEdges und ACount einfängt.
/// </summary>
function ConnectedOf(AEdges: TDictionary<Int64, Boolean>; ACount: Int64): THotspotConnectedFunc;
begin
  Result :=
    function(AFirst, ASecond: Integer): Boolean
    begin
      Result := AEdges.ContainsKey(EdgeKey(AFirst, ASecond, ACount));
    end;
end;

/// <summary>Routinen ohne lokale Routinen (Bereich liegt in einer anderen).</summary>
function TopLevel(const ARoutines: TArray<TRoutineMetrics>): TArray<TRoutineMetrics>;
var
  mIndex, mOuter: Integer;
  mNested: Boolean;
begin
  Result := nil;
  for mIndex := 0 to High(ARoutines) do
  begin
    mNested := False;
    for mOuter := 0 to High(ARoutines) do
      if (mOuter <> mIndex) and (ARoutines[mOuter].Range.StartPos.Line <= ARoutines[mIndex].Range.StartPos.Line) and
        (ARoutines[mOuter].Range.EndPos.Line >= ARoutines[mIndex].Range.EndPos.Line) and
        ((ARoutines[mOuter].Range.StartPos.Line < ARoutines[mIndex].Range.StartPos.Line) or
        (ARoutines[mOuter].Range.EndPos.Line > ARoutines[mIndex].Range.EndPos.Line)) then
      begin
        mNested := True;
        Break;
      end;
    if not mNested then
      Result := Result + [ARoutines[mIndex]];
  end;
end;

{ THotspotRequest }

class function THotspotRequest.FromSettings(const ASettings: TServerSettings): THotspotRequest;
begin
  Result := Default(THotspotRequest);
  Result.Level := THotspotLevel.Units;
  Result.Options := THotspotOptions.Default;
  Result.Options.Months := ASettings.HotspotsMonths;
  Result.Options.MinSharedCommits := ASettings.HotspotsCouplingMinCommits;
  Result.Exclude := ASettings.ArchitectureExclude;
end;

function THotspotRequest.Key: string;
var
  mFiles: TArray<string>;
  mIndex: Integer;
begin
  // Klein vor dem Sortieren: Reihenfolge und Schreibweise der Dateien ändern den Schlüssel nicht.
  mFiles := Copy(Files);
  for mIndex := 0 to High(mFiles) do
    mFiles[mIndex] := LowerCase(mFiles[mIndex]);
  TArray.Sort<string>(mFiles);
  Result := Title + #1 + Root + #1 + IntToStr(Ord(Level)) + #1 + IntToStr(Options.Months) + #1 +
    IntToStr(Options.MinSharedCommits) + #1 + FloatToStr(Options.MinCouplingRatio) + #1 +
    IntToStr(Options.MaxCommitFiles) + #1 + IntToStr(Options.MethodCandidates) + #1 +
    IntToStr(Options.TrendCandidates) + #1 + IntToStr(Options.TrendMonths) + #1 + string.Join(#2, Exclude) + #1 +
    string.Join(#2, Namespaces) + #1 + string.Join(#2, mFiles);
end;

{ THotspotService }

constructor THotspotService.Create(const AIndex: ISymbolIndex; const AReadText: TMetricsReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FMetrics := TMetricsCollector.Create;
  FLock := TObject.Create;
  FLineLogs := TDictionary<string, TArray<THotspotLineCommit>>.Create;
  FPast := TDictionary<string, THotspotPastText>.Create;
end;

destructor THotspotService.Destroy;
begin
  FPast.Free;
  FLineLogs.Free;
  FLock.Free;
  FMetrics.Free;
  inherited Destroy;
end;

function THotspotService.History(const AVcs: IHotspotVcs; AMonths: Integer; ANow: TDateTime;
  out AKey: string): TArray<THotspotCommit>;
var
  mHead, mError: string;
  mCommits: TArray<THotspotCommit>;
  mSince: TDateTime;
begin
  mHead := AVcs.Head;
  mSince := THotspotHistory.Since(ANow, AMonths);
  // Ohne bekannten Stand nie aus dem Speicher; mit Stand gilt der Verlauf bis zum nächsten Commit (der Zeitraum
  // verschiebt sich innerhalb eines Tages nicht merklich).
  AKey := THotspots.KindName(AVcs.Kind) + #1 + AVcs.Root + #1 + mHead + #1 + IntToStr(AMonths) + #1 +
    FormatDateTime('yyyymmdd', mSince);
  if (mHead <> '') and (AKey = FHistoryKey) then
    Exit(FHistory);
  if not AVcs.Log(mSince, mCommits, mError) then
    raise EHotspots.Create(mError);
  Inc(FHistoryReads);
  Result := THotspotHistory.FollowRenames(mCommits);
  if mHead = '' then
    AKey := AKey + #1 + IntToStr(FHistoryReads);
  if FHistoryKey <> AKey then
  begin
    // Neuer Stand: gemerkte Methodenverläufe und alte Texte gehören zum alten.
    FLineLogs.Clear;
    FPast.Clear;
  end;
  FHistoryKey := AKey;
  FHistory := Result;
  FSince := mSince;
end;

function THotspotService.ScopeUnits(const ARequest: THotspotRequest; const AVcsRoot: string;
  AEdges: TDictionary<Int64, Boolean>): TArray<THotspotUnit>;
var
  mUnits, mSelected: TArray<TUnitIndex>;
  mItem: TUnitIndex;
  mInScope: TDictionary<string, Boolean>;
  mFileName, mRelative: string;
  mOptions: TUsesGraphOptions;
  mGraph: TUsesGraph;
  mNode, mIndex, mTarget: Integer;
  mNodeToUnit: TDictionary<Integer, Integer>;
  mList: TList<THotspotUnit>;
  mUnit: THotspotUnit;
  mCount: Int64;
begin
  mUnits := FIndex.Units;
  mInScope := TDictionary<string, Boolean>.Create;
  try
    for mFileName in ARequest.Files do
      mInScope.AddOrSetValue(LowerCase(mFileName), True);
    mSelected := nil;
    for mItem in mUnits do
    begin
      if mItem.Library_ or SameText(ExtractFileExt(mItem.FileName), '.dpk') then
        Continue;
      if (mInScope.Count > 0) and not mInScope.ContainsKey(LowerCase(mItem.FileName)) then
        Continue;
      mSelected := mSelected + [mItem];
    end;
  finally
    mInScope.Free;
  end;
  mOptions := TUsesGraphOptions.Default;
  mOptions.IncludeLibrary := False;
  mOptions.Exclude := ARequest.Exclude;
  mOptions.Root := ARequest.Root;
  mOptions.Namespaces := ARequest.Namespaces;
  mGraph := TUsesGraph.Create(mSelected, mOptions);
  mNodeToUnit := TDictionary<Integer, Integer>.Create;
  mList := TList<THotspotUnit>.Create;
  try
    for mNode in mGraph.SortedNodes do
    begin
      if not RelativePath(AVcsRoot, mGraph.Node(mNode).FileName, mRelative) then
        Continue;
      mUnit.UnitName := mGraph.Node(mNode).UnitName;
      mUnit.FileName := mGraph.Node(mNode).FileName;
      mUnit.Path := mRelative;
      mNodeToUnit.Add(mNode, mList.Count);
      mList.Add(mUnit);
    end;
    mCount := mList.Count;
    for mNode in mGraph.SortedNodes do
      if mNodeToUnit.TryGetValue(mNode, mIndex) then
        for mTarget in mGraph.DirectDependencies(mNode, AllUsesSections) do
          if mNodeToUnit.ContainsKey(mTarget) then
            AEdges.AddOrSetValue(EdgeKey(mIndex, mNodeToUnit[mTarget], mCount), True);
    Result := mList.ToArray;
  finally
    mList.Free;
    mNodeToUnit.Free;
    mGraph.Free;
  end;
end;

function THotspotService.PathAt(const APath: string; ADate: TDateTime): string;
var
  mCommit: THotspotCommit;
  mFile: THotspotFileChange;
begin
  // FHistory: neueste zuerst, Pfade heutig; OldPath ist der Name vor dem jeweiligen Commit.
  Result := APath;
  for mCommit in FHistory do
  begin
    if mCommit.Date <= ADate then
      Break;
    for mFile in mCommit.Files do
      if (mFile.Kind = THotspotChangeKind.Renamed) and (mFile.OldPath <> '') and SameText(mFile.Path, APath) then
        Result := mFile.OldPath;
  end;
end;

function THotspotService.PastRoutines(const AVcs: IHotspotVcs; const APath: string; ADate: TDateTime;
  out ARoutines: TArray<TRoutineMetrics>): THotspotTextState;
var
  mKey, mText: string;
  mPast: THotspotPastText;
begin
  mKey := LowerCase(APath);
  if not FPast.TryGetValue(mKey, mPast) then
  begin
    mPast.State := AVcs.TextAt(PathAt(APath, ADate), ADate, mText);
    mPast.Routines := nil;
    if mPast.State = THotspotTextState.Found then
      mPast.Routines := TMetricsCalculator.ForText(mText);
    FPast.Add(mKey, mPast);
  end;
  ARoutines := mPast.Routines;
  Result := mPast.State;
end;

procedure THotspotService.ApplyTrends(const AVcs: IHotspotVcs; var AEntries: TArray<THotspotEntry>; ACount: Integer;
  ADate: TDateTime);
var
  mIndex, mPast: Integer;
  mRoutines: TArray<TRoutineMetrics>;
  mRoutine: TRoutineMetrics;
  mFound: Boolean;
  mState: THotspotTextState;
begin
  for mIndex := 0 to Min(ACount, Length(AEntries)) - 1 do
  begin
    mState := PastRoutines(AVcs, AEntries[mIndex].Path, ADate, mRoutines);
    if mState = THotspotTextState.Missing then
      mPast := -2
    else if mState = THotspotTextState.Unknown then
      mPast := -1
    else if AEntries[mIndex].Method = '' then
      mPast := HotspotComplexity(mRoutines)
    else
    begin
      mFound := False;
      mPast := -2;
      for mRoutine in mRoutines do
        if SameText(mRoutine.Name, AEntries[mIndex].Method) then
        begin
          mPast := mRoutine.Values[TMetricKind.Cognitive];
          mFound := True;
          Break;
        end;
      if not mFound then
        mPast := -2;
    end;
    AEntries[mIndex].Trend := THotspotAnalyzer.TrendOf(AEntries[mIndex].Complexity, mPast);
    AEntries[mIndex].PastComplexity := Max(mPast, -1);
  end;
end;

type
  TMethodCandidate = record
    Entry: THotspotEntry;
    Weight: Double;
  end;

function THotspotService.MethodEntries(const AVcs: IHotspotVcs; const ARequest: THotspotRequest;
  const AUnits: TArray<THotspotEntry>;
  const ARoutines: TDictionary<string, TArray<TRoutineMetrics>>): TArray<THotspotEntry>;
var
  mCandidates: TList<TMethodCandidate>;
  mCandidate: TMethodCandidate;
  mUnit: THotspotEntry;
  mRoutine: TRoutineMetrics;
  mRoutines: TArray<TRoutineMetrics>;
  mMaxChanges, mIndex: Integer;
  mEntries: TArray<THotspotEntry>;
  mCommits: TArray<THotspotLineCommit>;
  mKey: string;
begin
  mMaxChanges := 1;
  for mUnit in AUnits do
    mMaxChanges := Max(mMaxChanges, mUnit.Changes.Changes);
  mCandidates := TList<TMethodCandidate>.Create;
  try
    for mUnit in AUnits do
    begin
      if not ARoutines.TryGetValue(LowerCase(mUnit.Path), mRoutines) then
        Continue;
      for mRoutine in TopLevel(mRoutines) do
      begin
        if mRoutine.Values[TMetricKind.Cognitive] <= 0 then
          Continue;
        mCandidate.Entry := Default(THotspotEntry);
        mCandidate.Entry.UnitName := mUnit.UnitName;
        mCandidate.Entry.Path := mUnit.Path;
        mCandidate.Entry.FileName := mUnit.FileName;
        mCandidate.Entry.Method := mRoutine.Name;
        mCandidate.Entry.Line := mRoutine.Range.StartPos.Line + 1;
        mCandidate.Entry.EndLine := mRoutine.Range.EndPos.Line + 1;
        mCandidate.Entry.Complexity := mRoutine.Values[TMetricKind.Cognitive];
        mCandidate.Entry.Lines := mCandidate.Entry.EndLine - mCandidate.Entry.Line + 1;
        mCandidate.Entry.PastComplexity := -1;
        mCandidate.Weight := (mUnit.Changes.Changes / mMaxChanges) * mCandidate.Entry.Complexity;
        mCandidates.Add(mCandidate);
      end;
    end;
    mCandidates.Sort(TComparer<TMethodCandidate>.Construct(
      function(const ALeft, ARight: TMethodCandidate): Integer
      begin
        Result := CompareValue(ARight.Weight, ALeft.Weight);
        if Result = 0 then
          Result := CompareText(ALeft.Entry.Path, ARight.Entry.Path);
        if Result = 0 then
          Result := ALeft.Entry.Line - ARight.Entry.Line;
      end));
    mEntries := nil;
    for mIndex := 0 to Min(ARequest.Options.MethodCandidates, mCandidates.Count) - 1 do
    begin
      mCandidate := mCandidates[mIndex];
      mKey := LowerCase(mCandidate.Entry.Path) + #1 + IntToStr(mCandidate.Entry.Line) + #1 +
        IntToStr(mCandidate.Entry.EndLine);
      if not FLineLogs.TryGetValue(mKey, mCommits) then
      begin
        Inc(FLineLogReads);
        if not AVcs.LineLog(mCandidate.Entry.FileName, mCandidate.Entry.Line, mCandidate.Entry.EndLine, FSince,
          mCommits) then
          mCommits := nil;
        FLineLogs.AddOrSetValue(mKey, mCommits);
      end;
      mCandidate.Entry.Changes := THotspotAnalyzer.LineChanges(mCommits);
      mEntries := mEntries + [mCandidate.Entry];
    end;
  finally
    mCandidates.Free;
  end;
  Result := THotspotAnalyzer.Rank(mEntries);
end;

function THotspotService.Compute(const ARequest: THotspotRequest; const AVcs: IHotspotVcs; ANow: TDateTime;
  AGeneration: Int64): THotspotResult;
var
  mUnits: TArray<THotspotUnit>;
  mEdges: TDictionary<Int64, Boolean>;
  mChanges: TArray<THotspotChanges>;
  mEntries: TArray<THotspotEntry>;
  mEntry: THotspotEntry;
  mRoutines: TArray<TRoutineMetrics>;
  mAllRoutines: TDictionary<string, TArray<TRoutineMetrics>>;
  mIndex: Integer;
  mText: string;
  mTrendDate: TDateTime;
begin
  Result := Default(THotspotResult);
  Result.Title := ARequest.Title;
  Result.Root := AVcs.Root;
  Result.Kind := AVcs.Kind;
  Result.Head := AVcs.Head;
  Result.Months := ARequest.Options.Months;
  Result.Since := FSince;
  Result.Commits := Length(FHistory);
  Result.Level := ARequest.Level;
  Result.Generation := AGeneration;
  mEdges := TDictionary<Int64, Boolean>.Create;
  mAllRoutines := TDictionary<string, TArray<TRoutineMetrics>>.Create;
  try
    mUnits := ScopeUnits(ARequest, AVcs.Root, mEdges);
    mChanges := THotspotAnalyzer.UnitChanges(mUnits, FHistory);
    mEntries := nil;
    for mIndex := 0 to High(mUnits) do
    begin
      if mChanges[mIndex].Changes = 0 then
        Continue;
      if not (Assigned(FReadText) and FReadText(mUnits[mIndex].FileName, mText)) then
        Continue;
      mRoutines := FMetrics.FileRoutines(mUnits[mIndex].FileName, mText);
      mAllRoutines.AddOrSetValue(LowerCase(mUnits[mIndex].Path), mRoutines);
      mEntry := Default(THotspotEntry);
      mEntry.UnitName := mUnits[mIndex].UnitName;
      mEntry.Path := mUnits[mIndex].Path;
      mEntry.FileName := mUnits[mIndex].FileName;
      mEntry.Line := 1;
      mEntry.Changes := mChanges[mIndex];
      mEntry.Complexity := HotspotComplexity(mRoutines);
      mEntry.Lines := LineCount(mText);
      mEntry.EndLine := mEntry.Lines;
      mEntry.PastComplexity := -1;
      mEntries := mEntries + [mEntry];
    end;
    Result.Units := THotspotAnalyzer.Rank(mEntries);
    mTrendDate := IncMonth(ANow, -ARequest.Options.TrendMonths);
    ApplyTrends(AVcs, Result.Units, ARequest.Options.TrendCandidates, mTrendDate);
    Result.Coupling := THotspotAnalyzer.Coupling(mUnits, FHistory, ARequest.Options,
      ConnectedOf(mEdges, Length(mUnits)));
    if ARequest.Level = THotspotLevel.Methods then
    begin
      Result.Methods := MethodEntries(AVcs, ARequest, Result.Units, mAllRoutines);
      ApplyTrends(AVcs, Result.Methods, ARequest.Options.TrendCandidates, mTrendDate);
    end;
  finally
    mAllRoutines.Free;
    mEdges.Free;
  end;
end;

function THotspotService.Analyze(const ARequest: THotspotRequest; const AVcs: IHotspotVcs): THotspotResult;
begin
  Result := Analyze(ARequest, AVcs, UnixToDateTime(DateTimeToUnix(Now, False), True));
end;

function THotspotService.Analyze(const ARequest: THotspotRequest; const AVcs: IHotspotVcs;
  ANow: TDateTime): THotspotResult;
var
  mHistoryKey, mKey: string;
  mGeneration: Int64;
begin
  if AVcs = nil then
    raise EHotspots.Create('Keine Versionsverwaltung');
  System.TMonitor.Enter(FLock);
  try
    History(AVcs, Max(1, ARequest.Options.Months), ANow, mHistoryKey);
    mGeneration := FIndex.Generation;
    mKey := mHistoryKey + #1 + IntToStr(mGeneration) + #1 + ARequest.Key;
    if not FHasResult or (FResultKey <> mKey) then
    begin
      FResult := Compute(ARequest, AVcs, ANow, mGeneration);
      FResultKey := mKey;
      FHasResult := True;
      Inc(FComputations);
    end;
    Result := FResult;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function THotspotService.Computations: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FComputations;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function THotspotService.HistoryReads: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FHistoryReads;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function THotspotService.LineLogReads: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FLineLogReads;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
