unit Atlas.Core.Commands.QuickOpen;

// Datei und Symbol schnell öffnen (#503), Teil ohne VCL und Open Tools API:
//   - Eingabe zerlegen: "@Name" Symbole der aktuellen Datei (Gliederung, #9),
//     "#Name" Symbole im Projekt (#20), ":123" Zeile der aktuellen Datei,
//     "Datei:123" die Datei in Zeile 123, sonst Dateisuche.
//   - Dateiliste: Dateien der Projekte (Herkunft Projekt), Ordner der
//     Projektdateien und Suchpfade ohne Unterordner wie beim Compiler
//     (Suchpfad), auf Wunsch die Quellen von RTL/VCL mit Unterordnern
//     (Bibliothek); nur .pas, .dfm, .inc, .dpr, .dpk, .dproj, .rc, ohne Doppelte
//     (die erste Herkunft gewinnt).
//   - TAtlasQuickOpenList baut die Liste im Hintergrund auf und nur neu, wenn
//     sich die Quellen ändern (Projektwechsel, Suchpfad, Schalter).
//   - Rangfolge: Matching der Befehlspalette (#229) auf dem Dateinamen ohne
//     Endung (mit Punkt im Suchtext mit Endung), ersatzweise dem relativen Pfad
//     zu halben Punkten; bei Gleichstand offene Dateien, dann zuletzt geöffnete
//     (jüngste zuerst), dann Projektdateien, dann der Rest; danach .pas vor
//     .dpr/.dpk/.inc/.dfm/.rc/.dproj und der Name.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Commands.Palette;

type
{$SCOPEDENUMS ON}
  TAtlasQuickOpenOrigin = (Project, SearchPath, Library_);
  TAtlasQuickOpenMode = (Files, FileSymbols, ProjectSymbols, Line);
{$SCOPEDENUMS OFF}

  TAtlasQuickOpenQuery = record
    Mode: TAtlasQuickOpenMode;
    /// <summary>Suchtext ohne Präfix und ohne ":Zeile".</summary>
    Text: string;
    /// <summary>Zeile (1-basiert) aus ":123" bzw. "Datei:123"; 0 = keine.</summary>
    Line: Integer;
    class function Parse(const AInput: string): TAtlasQuickOpenQuery; static;
  end;

  TAtlasQuickOpenFile = record
    FileName: string;
    /// <summary>Dateiname mit Endung.</summary>
    Name: string;
    /// <summary>Dateiname ohne Endung.</summary>
    Stem: string;
    /// <summary>Pfad relativ zum Ordner der Projektgruppe; außerhalb absolut.</summary>
    RelativePath: string;
    Origin: TAtlasQuickOpenOrigin;
  end;
  TAtlasQuickOpenFiles = TArray<TAtlasQuickOpenFile>;

  /// <summary>Woraus die Dateiliste entsteht; die IDE-Schicht füllt es mit absoluten Pfaden.</summary>
  TAtlasQuickOpenSources = record
    /// <summary>Ordner der Projektgruppe für relative Pfade.</summary>
    Root: string;
    /// <summary>Dateien der Projekte (Projektdatei, Hauptdatei, eingetragene Units samt Formular).</summary>
    ProjectFiles: TArray<string>;
    /// <summary>Ohne Unterordner: Ordner der Projektdateien und Suchpfade.</summary>
    Folders: TArray<string>;
    /// <summary>Mit Unterordnern: Quellen von RTL/VCL; leer ohne die Einstellung.</summary>
    LibraryFolders: TArray<string>;
    /// <summary>Gleich, wenn die Liste nicht neu aufgebaut werden muss.</summary>
    function Key: string;
  end;

  /// <summary>Dateien eines Ordners (absolute Pfade); ARecursive mit Unterordnern. Läuft im Hintergrund.</summary>
  TAtlasQuickOpenLister = reference to function(const AFolder: string; ARecursive: Boolean): TArray<string>;

  TAtlasQuickOpen = class
  public const
    /// <summary>Höchstzahl der Dateien in der Liste (Schutz vor riesigen Bibliotheksordnern).</summary>
    MaxFiles = 50000;
    /// <summary>Höchstzahl der angezeigten Treffer.</summary>
    MaxResults = 200;
  public
    /// <summary>Gehört AFileName nach seiner Endung in die Liste?</summary>
    class function IsListed(const AFileName: string): Boolean; static;
    /// <summary>Pfad relativ zu ARoot ("\" bleibt); liegt die Datei nicht darunter, der volle Pfad.</summary>
    class function RelativeTo(const AFileName, ARoot: string): string; static;
    /// <summary>Liste aus ASources; AList liest die Ordner.</summary>
    class function Collect(const ASources: TAtlasQuickOpenSources;
      const AList: TAtlasQuickOpenLister): TAtlasQuickOpenFiles; overload; static;
    /// <summary>Wie oben; ACancelled (zwischen den Ordnern gefragt) bricht mit dem bisherigen Stand ab.</summary>
    class function Collect(const ASources: TAtlasQuickOpenSources; const AList: TAtlasQuickOpenLister;
      const ACancelled: TFunc<Boolean>): TAtlasQuickOpenFiles; overload; static;
    /// <summary>Dateien eines Ordners im Dateisystem; '' bei Fehlern (fehlender Ordner, keine Rechte).</summary>
    class function ListFolder(const AFolder: string; ARecursive: Boolean): TArray<string>; static;
    /// <summary>Punkte für AText; -1, wenn die Datei nicht passt. Leerer Text passt immer.</summary>
    class function Score(const AText: string; const AFile: TAtlasQuickOpenFile): Integer; static;
    /// <summary>Indizes der passenden Dateien, beste zuerst, höchstens MaxResults. AOpen: im Editor offene
    /// Dateien; ARecent: zuletzt geöffnete (Schlüssel ist der Dateiname in Kleinschrift; darf nil sein).</summary>
    class function Order(const AFiles: TAtlasQuickOpenFiles; const AText: string; const AOpen: TArray<string>;
      ARecent: TAtlasCommandHistory): TArray<Integer>; static;
    /// <summary>Schlüssel für ARecent.</summary>
    class function RecentKey(const AFileName: string): string; static;
    /// <summary>Symbole nach AText geordnet wie die Befehlspalette; ohne Text in der gegebenen Reihenfolge.</summary>
    class function OrderSymbols(const ANames: TArray<string>; const AText: string): TArray<Integer>; static;
  end;

  /// <summary>Dateiliste, im Hintergrund aufgebaut. Nur aus dem Hauptthread bedienen.</summary>
  TAtlasQuickOpenList = class
  private
    FLock: TObject;
    FFiles: TAtlasQuickOpenFiles;
    FKey: string;
    FGeneration: Integer;
    FStopping: Boolean;
    FThreads: TList<TThread>;
    FLister: TAtlasQuickOpenLister;
    FBuilding: Integer;
    procedure Store(AGeneration: Integer; const AFiles: TAtlasQuickOpenFiles);
    procedure Sweep;
  public
    constructor Create(const ALister: TAtlasQuickOpenLister);
    /// <summary>Wartet auf laufende Aufbauten (sie brechen zwischen zwei Ordnern ab).</summary>
    destructor Destroy; override;
    /// <summary>Startet den Aufbau, wenn sich ASources seit dem letzten Aufruf geändert hat; kehrt sofort
    /// zurück. Bis der neue Stand da ist, liefert Files den alten.</summary>
    procedure Refresh(const ASources: TAtlasQuickOpenSources);
    function Files: TAtlasQuickOpenFiles;
    function Building: Boolean;
    /// <summary>Wartet, bis kein Aufbau mehr läuft; False nach ATimeoutMs (für Tests).</summary>
    function WaitIdle(ATimeoutMs: Cardinal): Boolean;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  System.Diagnostics,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

const
  cListed: array[0..7] of string = ('.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx', '.rc', '.dproj');

function ExtensionRank(const AFileName: string): Integer;
var
  mExtension: string;
  mIndex: Integer;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  for mIndex := 0 to High(cListed) do
  begin
    if cListed[mIndex] = mExtension then
    begin
      Exit(mIndex);
    end;
  end;
  Result := Length(cListed);
end;

{ TAtlasQuickOpenQuery }

class function TAtlasQuickOpenQuery.Parse(const AInput: string): TAtlasQuickOpenQuery;
var
  mInput, mTail: string;
  mColon, mLine: Integer;
begin
  Result := Default(TAtlasQuickOpenQuery);
  mInput := TrimLeft(AInput);
  if mInput = '' then
  begin
    Exit;
  end;
  case mInput[1] of
    '@':
      begin
        Result.Mode := TAtlasQuickOpenMode.FileSymbols;
        Result.Text := Trim(Copy(mInput, 2, MaxInt));
        Exit;
      end;
    '#':
      begin
        Result.Mode := TAtlasQuickOpenMode.ProjectSymbols;
        Result.Text := Trim(Copy(mInput, 2, MaxInt));
        Exit;
      end;
    ':':
      begin
        Result.Mode := TAtlasQuickOpenMode.Line;
        Result.Line := Max(0, StrToIntDef(Trim(Copy(mInput, 2, MaxInt)), 0));
        Exit;
      end;
  end;
  Result.Text := Trim(mInput);
  // "Datei:123": nur Ziffern hinter dem letzten Doppelpunkt (ein Laufwerk "C:\" bleibt Suchtext).
  mColon := LastDelimiter(':', Result.Text);
  if mColon > 1 then
  begin
    mTail := Copy(Result.Text, mColon + 1, MaxInt);
    if (mTail <> '') and TryStrToInt(mTail, mLine) and (mLine > 0) and (Pos('-', mTail) = 0) and
      (Pos('+', mTail) = 0) then
    begin
      Result.Line := mLine;
      Result.Text := TrimRight(Copy(Result.Text, 1, mColon - 1));
    end;
  end;
end;

{ TAtlasQuickOpenSources }

function TAtlasQuickOpenSources.Key: string;
begin
  Result := AnsiUpperCase(Root + '|' + string.Join(';', ProjectFiles) + '|' + string.Join(';', Folders) + '|' +
    string.Join(';', LibraryFolders));
end;

{ TAtlasQuickOpen }

class function TAtlasQuickOpen.IsListed(const AFileName: string): Boolean;
begin
  Result := ExtensionRank(AFileName) < Length(cListed);
end;

class function TAtlasQuickOpen.RelativeTo(const AFileName, ARoot: string): string;
var
  mRoot: string;
begin
  Result := AFileName;
  if ARoot = '' then
  begin
    Exit;
  end;
  // Trenner selbst prüfen statt IncludeTrailingPathDelimiter: Pfade der IDE haben immer "\".
  mRoot := ARoot;
  while (mRoot <> '') and CharInSet(mRoot[Length(mRoot)], ['\', '/']) do
  begin
    Delete(mRoot, Length(mRoot), 1);
  end;
  if (Length(AFileName) > Length(mRoot) + 1) and CharInSet(AFileName[Length(mRoot) + 1], ['\', '/']) and
    SameText(Copy(AFileName, 1, Length(mRoot)), mRoot) then
  begin
    Result := Copy(AFileName, Length(mRoot) + 2, MaxInt);
  end;
end;

class function TAtlasQuickOpen.Collect(const ASources: TAtlasQuickOpenSources;
  const AList: TAtlasQuickOpenLister): TAtlasQuickOpenFiles;
begin
  Result := Collect(ASources, AList, nil);
end;

class function TAtlasQuickOpen.Collect(const ASources: TAtlasQuickOpenSources; const AList: TAtlasQuickOpenLister;
  const ACancelled: TFunc<Boolean>): TAtlasQuickOpenFiles;
var
  mSeen: TDictionary<string, Boolean>;
  mFound: TList<TAtlasQuickOpenFile>;

  procedure Add(const AFileName: string; AOrigin: TAtlasQuickOpenOrigin);
  var
    mEntry: TAtlasQuickOpenFile;
  begin
    if (AFileName = '') or (mFound.Count >= MaxFiles) or not IsListed(AFileName) or
      mSeen.ContainsKey(LowerCase(AFileName)) then
    begin
      Exit;
    end;
    mSeen.Add(LowerCase(AFileName), True);
    mEntry.FileName := AFileName;
    mEntry.Name := ExtractFileName(AFileName);
    mEntry.Stem := ChangeFileExt(mEntry.Name, '');
    mEntry.RelativePath := RelativeTo(AFileName, ASources.Root);
    mEntry.Origin := AOrigin;
    mFound.Add(mEntry);
  end;

  function Cancelled: Boolean;
  begin
    Result := Assigned(ACancelled) and ACancelled();
  end;

  procedure AddFolders(const AFolders: TArray<string>; ARecursive: Boolean; AOrigin: TAtlasQuickOpenOrigin);
  var
    mFolder, mFileName: string;
    mDone: TDictionary<string, Boolean>;
  begin
    mDone := TDictionary<string, Boolean>.Create;
    try
      for mFolder in AFolders do
      begin
        if (mFolder = '') or mDone.ContainsKey(LowerCase(mFolder)) or Cancelled or (mFound.Count >= MaxFiles) then
        begin
          Continue;
        end;
        mDone.Add(LowerCase(mFolder), True);
        for mFileName in AList(mFolder, ARecursive) do
        begin
          Add(mFileName, AOrigin);
        end;
      end;
    finally
      mDone.Free;
    end;
  end;

var
  FileName: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mFound := TList<TAtlasQuickOpenFile>.Create;
  try
    for FileName in ASources.ProjectFiles do
    begin
      Add(FileName, TAtlasQuickOpenOrigin.Project);
    end;
    AddFolders(ASources.Folders, False, TAtlasQuickOpenOrigin.SearchPath);
    AddFolders(ASources.LibraryFolders, True, TAtlasQuickOpenOrigin.Library_);
    Result := mFound.ToArray;
  finally
    mFound.Free;
    mSeen.Free;
  end;
end;

function ListedFile(const APath: string; const ASearchRec: TSearchRec): Boolean;
begin
  Result := TAtlasQuickOpen.IsListed(ASearchRec.Name);
end;

class function TAtlasQuickOpen.ListFolder(const AFolder: string; ARecursive: Boolean): TArray<string>;
begin
  Result := nil;
  try
    if not TDirectory.Exists(AFolder) then
    begin
      Exit;
    end;
    // Nur Delphi-Dateien (#1240): Bibliotheksordner enthalten Tausende anderer Dateien, die sonst erst als Liste
    // entstanden und danach verworfen wurden.
    if ARecursive then
    begin
      Result := TDirectory.GetFiles(AFolder, '*', TSearchOption.soAllDirectories, ListedFile);
    end
    else
    begin
      Result := TDirectory.GetFiles(AFolder, '*', TSearchOption.soTopDirectoryOnly, ListedFile);
    end;
  except
    // Ordner ohne Rechte oder gerade gelöscht: zählt als leer.
    // EInOutError schließt EDirectoryNotFoundException ein.
    on EInOutError do
      Result := nil;
    on EArgumentException do
      Result := nil;
  end;
end;

class function TAtlasQuickOpen.Score(const AText: string; const AFile: TAtlasQuickOpenFile): Integer;
var
  mText: string;
begin
  mText := Trim(AText);
  if mText = '' then
  begin
    Exit(TAtlasCompletionMatcher.ScoreSubsequence);
  end;
  if (Pos('\', mText) > 0) or (Pos('/', mText) > 0) then
  begin
    Exit(TAtlasCompletionMatcher.Score(mText.Replace('/', '\'), AFile.RelativePath));
  end;
  if Pos('.', mText) > 0 then
  begin
    Result := TAtlasCompletionMatcher.Score(mText, AFile.Name);
  end
  else
  begin
    Result := TAtlasCompletionMatcher.Score(mText, AFile.Stem);
  end;
  if Result = TAtlasCompletionMatcher.NoMatch then
  begin
    // Ersatzweise der Pfad: "common lsp" findet Dateien unter Common\Lsp.
    Result := TAtlasCompletionMatcher.Score(mText.Replace(' ', '\'), AFile.RelativePath);
    if Result <> TAtlasCompletionMatcher.NoMatch then
    begin
      Result := Result div 2;
    end;
  end;
end;

class function TAtlasQuickOpen.RecentKey(const AFileName: string): string;
begin
  Result := LowerCase(AFileName);
end;

/// <summary>Stufe der Datei: offen 3, zuletzt geöffnet (ABoost > 0) 2, Projekt 1, Rest 0.</summary>
function TierOf(AOpen: TDictionary<string, Boolean>; const AFile: TAtlasQuickOpenFile; ABoost: Integer): Integer;
begin
  if AOpen.ContainsKey(LowerCase(AFile.FileName)) then
  begin
    Result := 3;
  end
  else if ABoost > 0 then
  begin
    Result := 2;
  end
  else if AFile.Origin = TAtlasQuickOpenOrigin.Project then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Reihenfolge der Treffer: Güte, Stufe, Verlauf, Endung, Name, Pfad.</summary>
function FileComparer(const AFiles: TAtlasQuickOpenFiles; const AScores, ATiers,
  ABoosts: TArray<Integer>): IComparer<Integer>;
begin
  Result := TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := AScores[B] - AScores[A];
      if Result = 0 then
      begin
        Result := ATiers[B] - ATiers[A];
      end;
      if Result = 0 then
      begin
        Result := ABoosts[B] - ABoosts[A];
      end;
      if Result = 0 then
      begin
        Result := ExtensionRank(AFiles[A].Name) - ExtensionRank(AFiles[B].Name);
      end;
      if Result = 0 then
      begin
        Result := CompareText(AFiles[A].Name, AFiles[B].Name);
      end;
      if Result = 0 then
      begin
        Result := CompareText(AFiles[A].FileName, AFiles[B].FileName);
      end;
    end);
end;

class function TAtlasQuickOpen.Order(const AFiles: TAtlasQuickOpenFiles; const AText: string;
  const AOpen: TArray<string>; ARecent: TAtlasCommandHistory): TArray<Integer>;
var
  mScores, mTiers, mBoosts: TArray<Integer>;
  mFound: TList<Integer>;
  mOpen: TDictionary<string, Boolean>;
  mIndex, mPoints: Integer;
  mFileName: string;
  mFiles: TAtlasQuickOpenFiles;
begin
  mFiles := AFiles;
  SetLength(mScores, Length(mFiles));
  SetLength(mTiers, Length(mFiles));
  SetLength(mBoosts, Length(mFiles));
  mFound := TList<Integer>.Create;
  mOpen := TDictionary<string, Boolean>.Create;
  try
    for mFileName in AOpen do
    begin
      mOpen.AddOrSetValue(LowerCase(mFileName), True);
    end;
    for mIndex := 0 to High(mFiles) do
    begin
      mPoints := Score(AText, mFiles[mIndex]);
      if mPoints = TAtlasCompletionMatcher.NoMatch then
      begin
        Continue;
      end;
      mScores[mIndex] := mPoints;
      if ARecent <> nil then
      begin
        mBoosts[mIndex] := ARecent.Boost(RecentKey(mFiles[mIndex].FileName));
      end;
      mTiers[mIndex] := TierOf(mOpen, mFiles[mIndex], mBoosts[mIndex]);
      mFound.Add(mIndex);
    end;
    mFound.Sort(FileComparer(mFiles, mScores, mTiers, mBoosts));
    if mFound.Count > MaxResults then
    begin
      mFound.Count := MaxResults;
    end;
    Result := mFound.ToArray;
  finally
    mOpen.Free;
    mFound.Free;
  end;
end;

class function TAtlasQuickOpen.OrderSymbols(const ANames: TArray<string>; const AText: string): TArray<Integer>;
var
  mScores: TArray<Integer>;
  mFound: TList<Integer>;
  mIndex: Integer;
begin
  SetLength(mScores, Length(ANames));
  mFound := TList<Integer>.Create;
  try
    for mIndex := 0 to High(ANames) do
    begin
      mScores[mIndex] := TAtlasCompletionMatcher.Score(AText, ANames[mIndex]);
      if mScores[mIndex] <> TAtlasCompletionMatcher.NoMatch then
      begin
        mFound.Add(mIndex);
      end;
    end;
    mFound.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := mScores[B] - mScores[A];
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end));
    if mFound.Count > MaxResults then
    begin
      mFound.Count := MaxResults;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

{ TAtlasQuickOpenList }

constructor TAtlasQuickOpenList.Create(const ALister: TAtlasQuickOpenLister);
begin
  inherited Create;
  FLock := TObject.Create;
  FThreads := TList<TThread>.Create;
  FLister := ALister;
end;

destructor TAtlasQuickOpenList.Destroy;
var
  mThread: TThread;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopping := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
  for mThread in FThreads do
  begin
    mThread.WaitFor;
    mThread.Free;
  end;
  FThreads.Free;
  FLock.Free;
  inherited;
end;

procedure TAtlasQuickOpenList.Store(AGeneration: Integer; const AFiles: TAtlasQuickOpenFiles);
begin
  System.TMonitor.Enter(FLock);
  try
    // Nur der jüngste Aufbau zählt; ein überholter verwirft sein Ergebnis.
    if AGeneration = FGeneration then
    begin
      FFiles := AFiles;
    end;
    Dec(FBuilding);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TAtlasQuickOpenList.Sweep;
var
  mIndex: Integer;
begin
  for mIndex := FThreads.Count - 1 downto 0 do
  begin
    if FThreads[mIndex].Finished then
    begin
      FThreads[mIndex].Free;
      FThreads.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasQuickOpenList.Refresh(const ASources: TAtlasQuickOpenSources);
var
  mKey: string;
  mGeneration: Integer;
  mSources: TAtlasQuickOpenSources;
  mLister: TAtlasQuickOpenLister;
  mThread: TThread;
begin
  Sweep;
  mKey := ASources.Key;
  System.TMonitor.Enter(FLock);
  try
    if mKey = FKey then
    begin
      Exit;
    end;
    FKey := mKey;
    Inc(FGeneration);
    mGeneration := FGeneration;
    Inc(FBuilding);
  finally
    System.TMonitor.Exit(FLock);
  end;
  mSources := ASources;
  mLister := FLister;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      Files: TAtlasQuickOpenFiles;
    begin
      Files := nil;
      try
        Files := TAtlasQuickOpen.Collect(mSources, mLister,
          function: Boolean
          begin
            System.TMonitor.Enter(FLock);
            try
              Result := FStopping or (mGeneration <> FGeneration);
            finally
              System.TMonitor.Exit(FLock);
            end;
          end);
      except
        // Ein Fehler beim Lesen der Ordner lässt die bisherige Liste stehen.
        on Exception do
          mGeneration := -1;
      end;
      Store(mGeneration, Files);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
end;

function TAtlasQuickOpenList.Files: TAtlasQuickOpenFiles;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FFiles;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TAtlasQuickOpenList.Building: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FBuilding > 0;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TAtlasQuickOpenList.WaitIdle(ATimeoutMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  while Building do
  begin
    if mWatch.ElapsedMilliseconds >= ATimeoutMs then
    begin
      Exit(False);
    end;
    TThread.Sleep(5);
  end;
  Result := True;
end;

end.
