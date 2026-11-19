unit Atlas.Common.History.Service;

// Symbolgeschichte (#2641) für get_symbol_history.
//
// - Stufe 1, Zeilengeschichte: ISymbolHistoryVcs.LineLog über den Bereich des Symbols (git log -L bzw. svn log
//   --diff), je Commit Zeilen, erste Zeile der Nachricht und Issue-Kennungen (TSymbolCommits).
// - Stufe 2, Umbenennen und Verschieben (nur Git): Hat der älteste Commit den Bereich angelegt, sucht der Dienst im
//   Stand davor unter den Dateien desselben Commits eine Routine, die danach in keiner dieser Dateien mehr steht
//   und deren Rumpf dem Rumpf des Symbols gleicht (TSymbolSimilarity). Bei gleichem Kurznamen genügt
//   cSameNameSimilarity, sonst braucht es cRenameSimilarity: Ein ähnlicher, aber fremder Rumpf darf nicht als
//   Vorgänger gelten. Der Treffer macht aus „eingeführt“ ein „umbenannt aus“ bzw. „verschoben aus“, und die Suche
//   geht beim Vorgänger im Stand davor weiter, höchstens cMaxHops Mal.
// - Grenzen: limit (Einträge), Zeitlimit und Abbruch des Clients; die Antwort nennt die erreichte Grenze.
// - Ergebnis je Stand (HEAD) gemerkt, wie get_hotspots; abgebrochene Läufe nicht. Threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Contract;

type
  TSymbolHistoryService = class(TInterfacedObject, ISymbolHistoryService)
  public const
    cDefaultLimit = 20;
    cMaxLimit = 200;
    /// <summary>Höchstens so viele Umbenennungen bzw. Verschiebungen hintereinander.</summary>
    cMaxHops = 10;
    /// <summary>Commits mit mehr Quelltextdateien werden nicht nach Vorgängern durchsucht.</summary>
    cMaxCommitFiles = 60;
    /// <summary>Ähnlichkeit für einen Vorgänger mit gleichem Kurznamen (verschoben).</summary>
    cSameNameSimilarity = 0.8;
    /// <summary>Ähnlichkeit für einen Vorgänger mit anderem Namen (umbenannt).</summary>
    cRenameSimilarity = 0.95;
  private type
    /// <summary>Abschnitt der Suche: Symbol, Datei, Stand und Bereich; bei einem Vorgänger seine Ähnlichkeit.
    /// </summary>
    TSegment = record
      Symbol: string;
      Path: string;
      /// <summary>'' = heutiger Stand.</summary>
      Revision: string;
      FirstLine: Integer;
      LastLine: Integer;
      Similarity: Double;
      /// <summary>Umbenennungen bzw. Verschiebungen bis zu diesem Abschnitt.</summary>
      Hops: Integer;
    end;

    /// <summary>Wonach in den Dateien eines Commits gesucht wird.</summary>
    TCandidateSearch = record
      Vcs: ISymbolHistoryVcs;
      Revision: string;
      Symbol: string;
      Path: string;
      Shape: TArray<string>;
    end;
  private
    FLock: TObject;
    FHead: string;
    FCache: TDictionary<string, TSymbolHistoryResult>;
    function Compute(const AVcs: ISymbolHistoryVcs; const ARequest: TSymbolHistoryRequest): TSymbolHistoryResult;
    /// <summary>Bester Vorgänger in AFile (Text vor dem Commit AOldText), besser als ABest; True, wenn ABest
    /// ersetzt wurde. Path setzt der Aufrufer.</summary>
    class function BestIn(const ASearch: TCandidateSearch; const AFile: THotspotFileChange; const AOldText: string;
      var ABest: TSegment): Boolean; static;
    class function FindPredecessor(const AVcs: ISymbolHistoryVcs; const ARevision, ASymbol, APath: string;
      const AStopped: TFunc<Boolean>; out APredecessor: TSegment): Boolean; static;
    /// <summary>Liest die Zeilengeschichte von ASegment an AResult an; True, wenn der älteste Commit das Symbol
    /// eingeführt hat. Setzt Stop bei Fehler, ohne Commits oder an der Grenze.</summary>
    class function ReadSegment(const AVcs: ISymbolHistoryVcs; const ARequest: TSymbolHistoryRequest;
      const ASegment: TSegment; var AResult: TSymbolHistoryResult): Boolean; static;
    /// <summary>Sucht den Vorgänger des eingeführten Symbols; True mit dem nächsten Abschnitt in ASegment.</summary>
    class function FollowPredecessor(const AVcs: ISymbolHistoryVcs; const ARequest: TSymbolHistoryRequest;
      const AStopped: TFunc<Boolean>; var ASegment: TSegment; var AResult: TSymbolHistoryResult): Boolean; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Geschichte nach ARequest; gemerkt je Stand von AVcs.</summary>
    function Run(const AVcs: ISymbolHistoryVcs; const ARequest: TSymbolHistoryRequest): TSymbolHistoryResult;
    /// <summary>Routine AName in AText (TFoo.Bar, Bar; Typparameter zählen nicht), Zeilen 1-basiert; False ohne.
    /// </summary>
    class function FindRoutine(const AText, AName: string; out AFirstLine, ALastLine: Integer): Boolean; static;
    /// <summary>Gemerkte Ergebnisse (für Tests).</summary>
    function CachedCount: Integer;
  end;

implementation

uses
  System.Math,
  System.Diagnostics,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Hotspots.History,
  Atlas.Common.History.Commits,
  Atlas.Common.History.Similarity;

{ Hilfen }

/// <summary>Name ohne Typparameter in Kleinschreibung: TList&lt;T&gt;.Add → tlist.add.</summary>
function NameKey(const AName: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AName[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      Result := Result + AName[mIndex];
    end;
  end;
  Result := LowerCase(Result);
end;

/// <summary>Letzter Teil des Namens: TFoo.Bar → bar.</summary>
function ShortKey(const AName: string): string;
begin
  Result := NameKey(AName);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

/// <summary>Routinen ohne lokale, nach Anfangszeile: Eine Routine, die vor dem Ende der vorigen äußeren beginnt,
/// ist lokal.</summary>
function OuterRoutines(const AText: string): TArray<TRoutineMetrics>;
var
  mAll: TArray<TRoutineMetrics>;
  mRoutine: TRoutineMetrics;
  mEnd: Integer;
begin
  Result := nil;
  mAll := TMetricsCalculator.ForText(AText);
  TArray.Sort<TRoutineMetrics>(mAll, TComparer<TRoutineMetrics>.Construct(
    function(const ALeft, ARight: TRoutineMetrics): Integer
    begin
      Result := ALeft.Range.StartPos.Line - ARight.Range.StartPos.Line;
      if Result = 0 then
      begin
        Result := ARight.Range.EndPos.Line - ALeft.Range.EndPos.Line;
      end;
    end));
  mEnd := -1;
  for mRoutine in mAll do
  begin
    if mRoutine.Range.StartPos.Line > mEnd then
    begin
      Result := Result + [mRoutine];
      mEnd := mRoutine.Range.EndPos.Line;
    end;
  end;
end;

/// <summary>Zeilen AFirst..ALast (0-basiert) von ALines.</summary>
function LinesText(const ALines: TArray<string>; AFirst, ALast: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := Max(0, AFirst) to Min(ALast, High(ALines)) do
    begin
      mBuilder.Append(ALines[mIndex]).Append(#10);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Neues Ereignis aus einem Commit der Zeilengeschichte.</summary>
function EventOf(const ACommit: TSymbolLineCommit; const ASymbol, APath: string): TSymbolEvent;
begin
  Result := Default(TSymbolEvent);
  Result.Kind := TSymbolEventKind.Changed;
  Result.Revision := ACommit.Revision;
  Result.Author := ACommit.Author;
  Result.Date := ACommit.Date;
  Result.Summary := TSymbolCommits.Summary(ACommit.Message);
  Result.Issues := TSymbolCommits.IssueKeys(ACommit.Message);
  THotspotHistory.CountPatch(ACommit.Patch, Result.Added, Result.Deleted);
  Result.Symbol := ASymbol;
  Result.Path := TSymbolCommits.PatchPath(ACommit.Patch);
  if Result.Path = '' then
  begin
    Result.Path := APath;
  end;
end;

/// <summary>Stoppuhr, Zeitlimit und Abbruch als eine Abfrage.</summary>
function StoppedOf(const AWatch: TStopwatch; ATimeoutMs: Integer; const ACancelled: TFunc<Boolean>): TFunc<Boolean>;
var
  mWatch: TStopwatch;
begin
  mWatch := AWatch;
  Result :=
    function: Boolean
    begin
      Result := (Assigned(ACancelled) and ACancelled()) or ((ATimeoutMs > 0) and
        (mWatch.ElapsedMilliseconds >= ATimeoutMs));
    end;
end;

{ TSymbolHistoryService }

constructor TSymbolHistoryService.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FCache := TDictionary<string, TSymbolHistoryResult>.Create;
  // Monitor-Datensatz gleich anlegen, nicht beim ersten Aufruf (Leckmonitor der Tests).
  System.TMonitor.Enter(FLock);
  System.TMonitor.Exit(FLock);
end;

destructor TSymbolHistoryService.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited Destroy;
end;

class function TSymbolHistoryService.FindRoutine(const AText, AName: string; out AFirstLine,
  ALastLine: Integer): Boolean;
var
  mRoutine: TRoutineMetrics;
  mKey: string;
begin
  AFirstLine := 0;
  ALastLine := 0;
  mKey := NameKey(AName);
  for mRoutine in OuterRoutines(AText) do
  begin
    if NameKey(mRoutine.Name) = mKey then
    begin
      AFirstLine := mRoutine.Range.StartPos.Line + 1;
      ALastLine := mRoutine.Range.EndPos.Line + 1;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Namen der Routinen von AFile im Stand ARevision (nach dem Commit); leer bei gelöschter Datei.</summary>
function NamesAfter(const AVcs: ISymbolHistoryVcs; const ARevision: string;
  const AFile: THotspotFileChange): TDictionary<string, Boolean>;
var
  mText: string;
  mRoutine: TRoutineMetrics;
begin
  Result := TDictionary<string, Boolean>.Create;
  if (AFile.Kind <> THotspotChangeKind.Deleted) and
    (AVcs.TextAt(AFile.Path, ARevision, False, mText) = THotspotTextState.Found) then
  begin
    for mRoutine in OuterRoutines(mText) do
    begin
      Result.AddOrSetValue(NameKey(mRoutine.Name), True);
    end;
  end;
end;

/// <summary>Quelltextdateien von AFiles; nil, wenn es mehr als AMax sind.</summary>
function SourceFiles(const AFiles: TArray<THotspotFileChange>; AMax: Integer): TArray<THotspotFileChange>;
var
  mFile: THotspotFileChange;
begin
  Result := nil;
  for mFile in AFiles do
  begin
    if TMetricsCollector.IsSource(mFile.Path) or TMetricsCollector.IsSource(mFile.OldPath) then
    begin
      Result := Result + [mFile];
    end;
  end;
  if Length(Result) > AMax then
  begin
    Result := nil;
  end;
end;

class function TSymbolHistoryService.BestIn(const ASearch: TCandidateSearch; const AFile: THotspotFileChange;
  const AOldText: string; var ABest: TSegment): Boolean;
var
  mAfter: TDictionary<string, Boolean>;
  mLines: TArray<string>;
  mRoutine: TRoutineMetrics;
  mSimilarity, mNeeded: Double;
begin
  Result := False;
  mLines := TTextLines.SplitLines(AOldText);
  mAfter := NamesAfter(ASearch.Vcs, ASearch.Revision, AFile);
  try
    for mRoutine in OuterRoutines(AOldText) do
    begin
      // Steht die Routine nach dem Commit noch in ihrer Datei, ist sie nicht der Vorgänger; außer es ist das
      // Symbol selbst in seiner Datei (innerhalb der Unit an eine andere Stelle gerückt).
      if mAfter.ContainsKey(NameKey(mRoutine.Name)) and not (SameText(AFile.Path, ASearch.Path) and
        (NameKey(mRoutine.Name) = NameKey(ASearch.Symbol))) then
      begin
        Continue;
      end;
      mNeeded := cRenameSimilarity;
      if ShortKey(mRoutine.Name) = ShortKey(ASearch.Symbol) then
      begin
        mNeeded := cSameNameSimilarity;
      end;
      mSimilarity := TSymbolSimilarity.Compare(ASearch.Shape, TSymbolSimilarity.Shape(LinesText(mLines,
        mRoutine.Range.StartPos.Line, mRoutine.Range.EndPos.Line)));
      if (mSimilarity >= mNeeded) and (mSimilarity > ABest.Similarity) then
      begin
        ABest.Symbol := mRoutine.Name;
        ABest.FirstLine := mRoutine.Range.StartPos.Line + 1;
        ABest.LastLine := mRoutine.Range.EndPos.Line + 1;
        ABest.Similarity := mSimilarity;
        Result := True;
      end;
    end;
  finally
    mAfter.Free;
  end;
end;

class function TSymbolHistoryService.FindPredecessor(const AVcs: ISymbolHistoryVcs; const ARevision, ASymbol,
  APath: string; const AStopped: TFunc<Boolean>; out APredecessor: TSegment): Boolean;
var
  mSearch: TCandidateSearch;
  mFiles: TArray<THotspotFileChange>;
  mFile: THotspotFileChange;
  mText, mOldPath: string;
  mFirst, mLast: Integer;
begin
  APredecessor := Default(TSegment);
  Result := False;
  if not AVcs.CommitFiles(ARevision, mFiles) or
    (AVcs.TextAt(APath, ARevision, False, mText) <> THotspotTextState.Found) or
    not FindRoutine(mText, ASymbol, mFirst, mLast) then
  begin
    Exit;
  end;
  mSearch.Vcs := AVcs;
  mSearch.Revision := ARevision;
  mSearch.Symbol := ASymbol;
  mSearch.Path := APath;
  mSearch.Shape := TSymbolSimilarity.Shape(LinesText(TTextLines.SplitLines(mText), mFirst - 1, mLast - 1));
  if Length(mSearch.Shape) < TSymbolSimilarity.cMinTokens then
  begin
    Exit;
  end;
  for mFile in SourceFiles(mFiles, cMaxCommitFiles) do
  begin
    mOldPath := mFile.Path;
    if mFile.Kind = THotspotChangeKind.Renamed then
    begin
      mOldPath := mFile.OldPath;
    end;
    if not AStopped() and (mFile.Kind <> THotspotChangeKind.Added) and
      (AVcs.TextAt(mOldPath, ARevision, True, mText) = THotspotTextState.Found) and
      BestIn(mSearch, mFile, mText, APredecessor) then
    begin
      APredecessor.Path := mOldPath;
      Result := True;
    end;
  end;
end;

/// <summary>Grenze, an der ein Lauf ohne Fehler stehen bleibt.</summary>
function StopOf(const AStopped: TFunc<Boolean>; const ACancelled: TFunc<Boolean>): TSymbolHistoryStop;
begin
  Result := TSymbolHistoryStop.None;
  if Assigned(ACancelled) and ACancelled() then
  begin
    Result := TSymbolHistoryStop.Cancelled;
  end
  else if AStopped() then
  begin
    Result := TSymbolHistoryStop.TimeLimit;
  end;
end;

/// <summary>Macht aus dem Ereignis „eingeführt“ ein „umbenannt aus“ bzw. „verschoben aus“ (bzw. „geändert“, wenn die
/// Routine nur innerhalb ihrer Unit an eine andere Stelle rückte).</summary>
procedure MarkPredecessor(var AEvent: TSymbolEvent; const ASymbol, APath: string; ASimilarity: Double);
begin
  // Dasselbe Symbol in derselben Datei: nur an eine andere Stelle gerückt, also geändert.
  if SameText(ASymbol, AEvent.Symbol) and SameText(APath, AEvent.Path) then
  begin
    AEvent.Kind := TSymbolEventKind.Changed;
    Exit;
  end;
  AEvent.Kind := TSymbolEventKind.Renamed;
  if not SameText(APath, AEvent.Path) then
  begin
    AEvent.Kind := TSymbolEventKind.Moved;
  end;
  AEvent.FromSymbol := ASymbol;
  AEvent.FromPath := APath;
  AEvent.Similarity := ASimilarity;
end;

class function TSymbolHistoryService.ReadSegment(const AVcs: ISymbolHistoryVcs;
  const ARequest: TSymbolHistoryRequest; const ASegment: TSegment; var AResult: TSymbolHistoryResult): Boolean;
var
  mCommits: TArray<TSymbolLineCommit>;
  mCommit: TSymbolLineCommit;
  mRemaining: Integer;
begin
  Result := False;
  mRemaining := ARequest.Limit - Length(AResult.Events);
  if not AVcs.LineLog(ASegment.Path, ASegment.Revision, ASegment.FirstLine, ASegment.LastLine, mRemaining,
    mCommits) then
  begin
    AResult.Stop := TSymbolHistoryStop.Failed;
  end
  else if Length(mCommits) = 0 then
  begin
    if Length(AResult.Events) = 0 then
    begin
      AResult.Stop := TSymbolHistoryStop.NoHistory;
    end;
  end
  else
  begin
    for mCommit in mCommits do
    begin
      AResult.Events := AResult.Events + [EventOf(mCommit, ASegment.Symbol, ASegment.Path)];
    end;
    Result := TSymbolCommits.IsIntroduction(mCommits[High(mCommits)].Patch);
    if Result then
    begin
      AResult.Events[High(AResult.Events)].Kind := TSymbolEventKind.Introduced;
    end
    else if Length(mCommits) >= mRemaining then
    begin
      // Ohne Einführung endet die Liste an der Grenze oder dort, wo der Verlauf aufhört (flacher Klon, SVN).
      AResult.Stop := TSymbolHistoryStop.Limit;
    end;
  end;
end;

class function TSymbolHistoryService.FollowPredecessor(const AVcs: ISymbolHistoryVcs;
  const ARequest: TSymbolHistoryRequest; const AStopped: TFunc<Boolean>; var ASegment: TSegment;
  var AResult: TSymbolHistoryResult): Boolean;
var
  mLast: Integer;
  mPredecessor: TSegment;
begin
  Result := False;
  mLast := High(AResult.Events);
  if not AResult.FollowedMoves then
  begin
    Exit;
  end;
  if ASegment.Hops >= cMaxHops then
  begin
    AResult.Stop := TSymbolHistoryStop.Hops;
  end
  else if not FindPredecessor(AVcs, AResult.Events[mLast].Revision, ASegment.Symbol, AResult.Events[mLast].Path,
    AStopped, mPredecessor) then
  begin
    AResult.Stop := StopOf(AStopped, ARequest.Cancelled);
  end
  else
  begin
    MarkPredecessor(AResult.Events[mLast], mPredecessor.Symbol, mPredecessor.Path, mPredecessor.Similarity);
    Result := Length(AResult.Events) < ARequest.Limit;
    if not Result then
    begin
      AResult.Stop := TSymbolHistoryStop.Limit;
    end;
    mPredecessor.Hops := ASegment.Hops + 1;
    mPredecessor.Revision := AResult.Events[mLast].Revision + '^';
    ASegment := mPredecessor;
  end;
end;

function TSymbolHistoryService.Compute(const AVcs: ISymbolHistoryVcs;
  const ARequest: TSymbolHistoryRequest): TSymbolHistoryResult;
var
  mStopped: TFunc<Boolean>;
  mSegment: TSegment;
begin
  Result := Default(TSymbolHistoryResult);
  Result.Symbol := ARequest.Symbol;
  Result.Path := ARequest.Path;
  Result.Kind := AVcs.Kind;
  Result.FollowedMoves := ARequest.FollowMoves and ARequest.IsRoutine and (AVcs.Kind = THotspotVcsKind.Git);
  mStopped := StoppedOf(TStopwatch.StartNew, ARequest.TimeoutMs, ARequest.Cancelled);
  mSegment := Default(TSegment);
  mSegment.Symbol := ARequest.Symbol;
  mSegment.Path := ARequest.Path;
  mSegment.FirstLine := ARequest.FirstLine;
  mSegment.LastLine := ARequest.LastLine;
  repeat
    Result.Stop := StopOf(mStopped, ARequest.Cancelled);
  until (Result.Stop <> TSymbolHistoryStop.None) or not ReadSegment(AVcs, ARequest, mSegment, Result) or
    not FollowPredecessor(AVcs, ARequest, mStopped, mSegment, Result);
end;

function TSymbolHistoryService.Run(const AVcs: ISymbolHistoryVcs;
  const ARequest: TSymbolHistoryRequest): TSymbolHistoryResult;
var
  mHead, mKey: string;
begin
  mHead := AVcs.Head;
  mKey := ARequest.Key;
  System.TMonitor.Enter(FLock);
  try
    if FHead <> mHead then
    begin
      FCache.Clear;
      FHead := mHead;
    end;
    if (mHead <> '') and FCache.TryGetValue(mKey, Result) then
    begin
      Result.Cached := True;
      Exit;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := Compute(AVcs, ARequest);
  Result.Head := mHead;
  if (mHead = '') or (Result.Stop in [TSymbolHistoryStop.TimeLimit, TSymbolHistoryStop.Cancelled,
    TSymbolHistoryStop.Failed]) then
  begin
    Exit;
  end;
  System.TMonitor.Enter(FLock);
  try
    if FHead = mHead then
    begin
      FCache.AddOrSetValue(mKey, Result);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TSymbolHistoryService.CachedCount: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FCache.Count;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
