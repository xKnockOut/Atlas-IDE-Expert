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
    /// <summary>Commits des Zeilenbereichs von AEntry, gemerkt in FLineLogs.</summary>
    function LineCommits(const AVcs: IHotspotVcs; const AEntry: THotspotEntry): TArray<THotspotLineCommit>;
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
  begin
    Inc(Result, mRoutine.Values[TMetricKind.Cognitive]);
  end;
end;

function LineCount(const AText: string): Integer;
var
  mChar: Char;
begin
  if AText = '' then
  begin
    Exit(0);
  end;
  Result := 1;
  for mChar in AText do
  begin
    if mChar = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Pfad relativ zu ARoot mit "/"; False außerhalb.</summary>
function RelativePath(const ARoot, AFileName: string; out ARelative: string): Boolean;
var
  mRoot, mFile: string;
begin
  mFile := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  Result := (mRoot <> '') and StartsText(mRoot, mFile) and (Length(mFile) > Length(mRoot));
  if Result then
  begin
    ARelative := Copy(mFile, Length(mRoot) + 1, MaxInt);
  end
  else
  begin
    ARelative := '';
  end;
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
    begin
      if (mOuter <> mIndex) and (ARoutines[mOuter].Range.StartPos.Line <= ARoutines[mIndex].Range.StartPos.Line) and
        (ARoutines[mOuter].Range.EndPos.Line >= ARoutines[mIndex].Range.EndPos.Line) and
        ((ARoutines[mOuter].Range.StartPos.Line < ARoutines[mIndex].Range.StartPos.Line) or
        (ARoutines[mOuter].Range.EndPos.Line > ARoutines[mIndex].Range.EndPos.Line)) then
      begin
        mNested := True;
        Break;
      end;
    end;
    if not mNested then
    begin
      Result := Result + [ARoutines[mIndex]];
    end;
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
  begin
    mFiles[mIndex] := LowerCase(mFiles[mIndex]);
  end;
  TArray.Sort<string>(mFiles);
  Result := Title + #1 + Root + #1 + IntToStr(Ord(Level)) + #1 + IntToStr(Options.Months) + #1 +
    IntToStr(Options.MinSharedCommits) + #1 + FloatToStr(Options.MinCouplingRatio, TFormatSettings.Invariant) + #1 +
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
  begin
    Exit(FHistory);
  end;
  if not AVcs.Log(mSince, mCommits, mError) then
  begin
    raise EHotspots.Create(mError);
  end;
  Inc(FHistoryReads);
  Result := THotspotHistory.FollowRenames(mCommits);
  if mHead = '' then
  begin
    AKey := AKey + #1 + IntToStr(FHistoryReads);
  end;
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

/// <summary>Projekt-Units aus AUnits ohne Bibliotheken und Packages; mit AFiles nur diese Dateien.</summary>
function SelectUnits(const AUnits: TArray<TUnitIndex>; const AFiles: TArray<string>): TArray<TUnitIndex>;
var
  mInScope: TDictionary<string, Boolean>;
  mFileName: string;
  mItem: TUnitIndex;
begin
  Result := nil;
  mInScope := TDictionary<string, Boolean>.Create;
  try
    for mFileName in AFiles do
    begin
      mInScope.AddOrSetValue(LowerCase(mFileName), True);
    end;
    for mItem in AUnits do
    begin
      if not mItem.Library_ and not SameText(ExtractFileExt(mItem.FileName), '.dpk') and
        ((mInScope.Count = 0) or mInScope.ContainsKey(LowerCase(mItem.FileName))) then
      begin
        Result := Result + [mItem];
      end;
    end;
  finally
    mInScope.Free;
  end;
end;

function GraphOptions(const ARequest: THotspotRequest): TUsesGraphOptions;
begin
  Result := TUsesGraphOptions.Default;
  Result.IncludeLibrary := False;
  Result.Exclude := ARequest.Exclude;
  Result.Root := ARequest.Root;
  Result.Namespaces := ARequest.Namespaces;
end;

/// <summary>Units des Graphen unter AVcsRoot in AList; ANodeToUnit ordnet Knoten ihrem Index darin zu.</summary>
procedure CollectGraphUnits(AGraph: TUsesGraph; const AVcsRoot: string; ANodeToUnit: TDictionary<Integer, Integer>;
  AList: TList<THotspotUnit>);
var
  mNode: Integer;
  mRelative: string;
  mUnit: THotspotUnit;
begin
  for mNode in AGraph.SortedNodes do
  begin
    if RelativePath(AVcsRoot, AGraph.Node(mNode).FileName, mRelative) then
    begin
      mUnit.UnitName := AGraph.Node(mNode).UnitName;
      mUnit.FileName := AGraph.Node(mNode).FileName;
      mUnit.Path := mRelative;
      ANodeToUnit.Add(mNode, AList.Count);
      AList.Add(mUnit);
    end;
  end;
end;

/// <summary>uses-Kanten zwischen den Units aus ANodeToUnit als EdgeKey in AEdges.</summary>
procedure CollectEdges(AGraph: TUsesGraph; ANodeToUnit: TDictionary<Integer, Integer>;
  AEdges: TDictionary<Int64, Boolean>);
var
  mNode, mIndex, mTarget, mTargetIndex: Integer;
begin
  for mNode in AGraph.SortedNodes do
  begin
    if not ANodeToUnit.TryGetValue(mNode, mIndex) then
    begin
      Continue;
    end;
    for mTarget in AGraph.DirectDependencies(mNode, AllUsesSections) do
    begin
      if ANodeToUnit.TryGetValue(mTarget, mTargetIndex) then
      begin
        AEdges.AddOrSetValue(EdgeKey(mIndex, mTargetIndex, ANodeToUnit.Count), True);
      end;
    end;
  end;
end;

function THotspotService.ScopeUnits(const ARequest: THotspotRequest; const AVcsRoot: string;
  AEdges: TDictionary<Int64, Boolean>): TArray<THotspotUnit>;
var
  mGraph: TUsesGraph;
  mNodeToUnit: TDictionary<Integer, Integer>;
  mList: TList<THotspotUnit>;
begin
  mGraph := TUsesGraph.Create(SelectUnits(FIndex.Units, ARequest.Files), GraphOptions(ARequest));
  mNodeToUnit := TDictionary<Integer, Integer>.Create;
  mList := TList<THotspotUnit>.Create;
  try
    CollectGraphUnits(mGraph, AVcsRoot, mNodeToUnit, mList);
    CollectEdges(mGraph, mNodeToUnit, AEdges);
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
    begin
      Break;
    end;
    for mFile in mCommit.Files do
    begin
      if (mFile.Kind = THotspotChangeKind.Renamed) and (mFile.OldPath <> '') and SameText(mFile.Path, APath) then
      begin
        Result := mFile.OldPath;
      end;
    end;
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
    begin
      mPast.Routines := TMetricsCalculator.ForText(mText);
    end;
    FPast.Add(mKey, mPast);
  end;
  ARoutines := mPast.Routines;
  Result := mPast.State;
end;

/// <summary>Kognitive Komplexität der Methode AMethod in ARoutines; -2, wenn es sie nicht gab.</summary>
function MethodComplexity(const ARoutines: TArray<TRoutineMetrics>; const AMethod: string): Integer;
var
  mRoutine: TRoutineMetrics;
begin
  for mRoutine in ARoutines do
  begin
    if SameText(mRoutine.Name, AMethod) then
    begin
      Exit(mRoutine.Values[TMetricKind.Cognitive]);
    end;
  end;
  Result := -2;
end;

/// <summary>Komplexität damals für THotspotAnalyzer.TrendOf: -2 gab es nicht, -1 unbekannt.</summary>
function PastComplexity(AState: THotspotTextState; const ARoutines: TArray<TRoutineMetrics>;
  const AMethod: string): Integer;
begin
  if AState = THotspotTextState.Missing then
  begin
    Result := -2;
  end
  else if AState = THotspotTextState.Unknown then
  begin
    Result := -1;
  end
  else if AMethod = '' then
  begin
    Result := HotspotComplexity(ARoutines);
  end
  else
  begin
    Result := MethodComplexity(ARoutines, AMethod);
  end;
end;

procedure THotspotService.ApplyTrends(const AVcs: IHotspotVcs; var AEntries: TArray<THotspotEntry>; ACount: Integer;
  ADate: TDateTime);
var
  mIndex, mPast: Integer;
  mRoutines: TArray<TRoutineMetrics>;
  mState: THotspotTextState;
begin
  for mIndex := 0 to Min(ACount, Length(AEntries)) - 1 do
  begin
    mState := PastRoutines(AVcs, AEntries[mIndex].Path, ADate, mRoutines);
    mPast := PastComplexity(mState, mRoutines, AEntries[mIndex].Method);
    AEntries[mIndex].Trend := THotspotAnalyzer.TrendOf(AEntries[mIndex].Complexity, mPast);
    AEntries[mIndex].PastComplexity := Max(mPast, -1);
  end;
end;

type
  TMethodCandidate = record
    Entry: THotspotEntry;
    Weight: Double;
  end;

/// <summary>Größte Zahl Änderungen der Units, mindestens 1.</summary>
function MaxUnitChanges(const AUnits: TArray<THotspotEntry>): Integer;
var
  mUnit: THotspotEntry;
begin
  Result := 1;
  for mUnit in AUnits do
  begin
    Result := Max(Result, mUnit.Changes.Changes);
  end;
end;

/// <summary>Kandidat für die Methode ARoutine aus AUnit; Gewicht = Anteil der Änderungen × Komplexität.</summary>
function MethodCandidate(const AUnit: THotspotEntry; const ARoutine: TRoutineMetrics;
  AMaxChanges: Integer): TMethodCandidate;
begin
  Result.Entry := Default(THotspotEntry);
  Result.Entry.UnitName := AUnit.UnitName;
  Result.Entry.Path := AUnit.Path;
  Result.Entry.FileName := AUnit.FileName;
  Result.Entry.Method := ARoutine.Name;
  Result.Entry.Line := ARoutine.Range.StartPos.Line + 1;
  Result.Entry.EndLine := ARoutine.Range.EndPos.Line + 1;
  Result.Entry.Complexity := ARoutine.Values[TMetricKind.Cognitive];
  Result.Entry.Lines := Result.Entry.EndLine - Result.Entry.Line + 1;
  Result.Entry.PastComplexity := -1;
  Result.Weight := (AUnit.Changes.Changes / AMaxChanges) * Result.Entry.Complexity;
end;

/// <summary>Kandidaten aller Methoden mit Komplexität über 0 aus den Units in ARoutines.</summary>
procedure CollectCandidates(ACandidates: TList<TMethodCandidate>; const AUnits: TArray<THotspotEntry>;
  const ARoutines: TDictionary<string, TArray<TRoutineMetrics>>);
var
  mMaxChanges: Integer;
  mUnit: THotspotEntry;
  mRoutines: TArray<TRoutineMetrics>;
  mRoutine: TRoutineMetrics;
begin
  mMaxChanges := MaxUnitChanges(AUnits);
  for mUnit in AUnits do
  begin
    if not ARoutines.TryGetValue(LowerCase(mUnit.Path), mRoutines) then
    begin
      Continue;
    end;
    for mRoutine in TopLevel(mRoutines) do
    begin
      if mRoutine.Values[TMetricKind.Cognitive] > 0 then
      begin
        ACandidates.Add(MethodCandidate(mUnit, mRoutine, mMaxChanges));
      end;
    end;
  end;
end;

/// <summary>Schwerste zuerst, dann nach Pfad und Zeile.</summary>
function CompareCandidates(const ALeft, ARight: TMethodCandidate): Integer;
begin
  Result := CompareValue(ARight.Weight, ALeft.Weight);
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Entry.Path, ARight.Entry.Path);
  end;
  if Result = 0 then
  begin
    Result := ALeft.Entry.Line - ARight.Entry.Line;
  end;
end;

function THotspotService.LineCommits(const AVcs: IHotspotVcs; const AEntry: THotspotEntry):
  TArray<THotspotLineCommit>;
var
  mKey: string;
begin
  mKey := LowerCase(AEntry.Path) + #1 + IntToStr(AEntry.Line) + #1 + IntToStr(AEntry.EndLine);
  if FLineLogs.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Inc(FLineLogReads);
  if not AVcs.LineLog(AEntry.FileName, AEntry.Line, AEntry.EndLine, FSince, Result) then
  begin
    Result := nil;
  end;
  FLineLogs.AddOrSetValue(mKey, Result);
end;

function THotspotService.MethodEntries(const AVcs: IHotspotVcs; const ARequest: THotspotRequest;
  const AUnits: TArray<THotspotEntry>;
  const ARoutines: TDictionary<string, TArray<TRoutineMetrics>>): TArray<THotspotEntry>;
var
  mCandidates: TList<TMethodCandidate>;
  mEntry: THotspotEntry;
  mIndex: Integer;
  mEntries: TArray<THotspotEntry>;
begin
  mEntries := nil;
  mCandidates := TList<TMethodCandidate>.Create;
  try
    CollectCandidates(mCandidates, AUnits, ARoutines);
    mCandidates.Sort(TComparer<TMethodCandidate>.Construct(
      function(const ALeft, ARight: TMethodCandidate): Integer
      begin
        Result := CompareCandidates(ALeft, ARight);
      end));
    for mIndex := 0 to Min(ARequest.Options.MethodCandidates, mCandidates.Count) - 1 do
    begin
      mEntry := mCandidates[mIndex].Entry;
      mEntry.Changes := THotspotAnalyzer.LineChanges(LineCommits(AVcs, mEntry));
      mEntries := mEntries + [mEntry];
    end;
  finally
    mCandidates.Free;
  end;
  Result := THotspotAnalyzer.Rank(mEntries);
end;

/// <summary>Kopf des Ergebnisses ohne Einträge.</summary>
function NewResult(const ARequest: THotspotRequest; const AVcs: IHotspotVcs; ASince: TDateTime; ACommits: Integer;
  AGeneration: Int64): THotspotResult;
begin
  Result := Default(THotspotResult);
  Result.Title := ARequest.Title;
  Result.Root := AVcs.Root;
  Result.Kind := AVcs.Kind;
  Result.Head := AVcs.Head;
  Result.Months := ARequest.Options.Months;
  Result.Since := ASince;
  Result.Commits := ACommits;
  Result.Level := ARequest.Level;
  Result.Generation := AGeneration;
end;

/// <summary>Eintrag der Rangliste für die Unit AUnit mit Text AText.</summary>
function UnitEntry(const AUnit: THotspotUnit; const AChanges: THotspotChanges;
  const ARoutines: TArray<TRoutineMetrics>; const AText: string): THotspotEntry;
begin
  Result := Default(THotspotEntry);
  Result.UnitName := AUnit.UnitName;
  Result.Path := AUnit.Path;
  Result.FileName := AUnit.FileName;
  Result.Line := 1;
  Result.Changes := AChanges;
  Result.Complexity := HotspotComplexity(ARoutines);
  Result.Lines := LineCount(AText);
  Result.EndLine := Result.Lines;
  Result.PastComplexity := -1;
end;

function THotspotService.Compute(const ARequest: THotspotRequest; const AVcs: IHotspotVcs; ANow: TDateTime;
  AGeneration: Int64): THotspotResult;
var
  mUnits: TArray<THotspotUnit>;
  mEdges: TDictionary<Int64, Boolean>;
  mChanges: TArray<THotspotChanges>;
  mEntries: TArray<THotspotEntry>;
  mRoutines: TArray<TRoutineMetrics>;
  mAllRoutines: TDictionary<string, TArray<TRoutineMetrics>>;
  mIndex: Integer;
  mText: string;
  mTrendDate: TDateTime;
begin
  Result := NewResult(ARequest, AVcs, FSince, Length(FHistory), AGeneration);
  mEdges := TDictionary<Int64, Boolean>.Create;
  mAllRoutines := TDictionary<string, TArray<TRoutineMetrics>>.Create;
  try
    mUnits := ScopeUnits(ARequest, AVcs.Root, mEdges);
    mChanges := THotspotAnalyzer.UnitChanges(mUnits, FHistory);
    mEntries := nil;
    for mIndex := 0 to High(mUnits) do
    begin
      if (mChanges[mIndex].Changes = 0) or not (Assigned(FReadText) and FReadText(mUnits[mIndex].FileName, mText)) then
      begin
        Continue;
      end;
      mRoutines := FMetrics.FileRoutines(mUnits[mIndex].FileName, mText);
      mAllRoutines.AddOrSetValue(LowerCase(mUnits[mIndex].Path), mRoutines);
      mEntries := mEntries + [UnitEntry(mUnits[mIndex], mChanges[mIndex], mRoutines, mText)];
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
  begin
    raise EHotspots.Create('Keine Versionsverwaltung');
  end;
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
