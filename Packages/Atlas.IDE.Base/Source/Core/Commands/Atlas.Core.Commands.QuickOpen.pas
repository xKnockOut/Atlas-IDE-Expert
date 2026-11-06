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
  Listed: array[0..7] of string = ('.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx', '.rc', '.dproj');

function ExtensionRank(const AFileName: string): Integer;
var
  Extension: string;
  Index: Integer;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  for Index := 0 to High(Listed) do
  begin
    if Listed[Index] = Extension then
    begin
      Exit(Index);
    end;
  end;
  Result := Length(Listed);
end;

{ TAtlasQuickOpenQuery }

class function TAtlasQuickOpenQuery.Parse(const AInput: string): TAtlasQuickOpenQuery;
var
  Input, Tail: string;
  Colon, Line: Integer;
begin
  Result := Default(TAtlasQuickOpenQuery);
  Input := TrimLeft(AInput);
  if Input = '' then
  begin
    Exit;
  end;
  case Input[1] of
    '@':
      begin
        Result.Mode := TAtlasQuickOpenMode.FileSymbols;
        Result.Text := Trim(Copy(Input, 2, MaxInt));
        Exit;
      end;
    '#':
      begin
        Result.Mode := TAtlasQuickOpenMode.ProjectSymbols;
        Result.Text := Trim(Copy(Input, 2, MaxInt));
        Exit;
      end;
    ':':
      begin
        Result.Mode := TAtlasQuickOpenMode.Line;
        Result.Line := Max(0, StrToIntDef(Trim(Copy(Input, 2, MaxInt)), 0));
        Exit;
      end;
  end;
  Result.Text := Trim(Input);
  // "Datei:123": nur Ziffern hinter dem letzten Doppelpunkt (ein Laufwerk "C:\" bleibt Suchtext).
  Colon := LastDelimiter(':', Result.Text);
  if Colon > 1 then
  begin
    Tail := Copy(Result.Text, Colon + 1, MaxInt);
    if (Tail <> '') and TryStrToInt(Tail, Line) and (Line > 0) and (Pos('-', Tail) = 0) and (Pos('+', Tail) = 0) then
    begin
      Result.Line := Line;
      Result.Text := TrimRight(Copy(Result.Text, 1, Colon - 1));
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
  Result := ExtensionRank(AFileName) < Length(Listed);
end;

class function TAtlasQuickOpen.RelativeTo(const AFileName, ARoot: string): string;
var
  Root: string;
begin
  Result := AFileName;
  if ARoot = '' then
  begin
    Exit;
  end;
  // Trenner selbst prüfen statt IncludeTrailingPathDelimiter: Pfade der IDE haben immer "\".
  Root := ARoot;
  while (Root <> '') and CharInSet(Root[Length(Root)], ['\', '/']) do
  begin
    Delete(Root, Length(Root), 1);
  end;
  if (Length(AFileName) > Length(Root) + 1) and CharInSet(AFileName[Length(Root) + 1], ['\', '/']) and
    SameText(Copy(AFileName, 1, Length(Root)), Root) then
  begin
    Result := Copy(AFileName, Length(Root) + 2, MaxInt);
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
  Seen: TDictionary<string, Boolean>;
  Found: TList<TAtlasQuickOpenFile>;

  procedure Add(const AFileName: string; AOrigin: TAtlasQuickOpenOrigin);
  var
    Entry: TAtlasQuickOpenFile;
  begin
    if (AFileName = '') or (Found.Count >= MaxFiles) or not IsListed(AFileName) or
      Seen.ContainsKey(LowerCase(AFileName)) then
    begin
      Exit;
    end;
    Seen.Add(LowerCase(AFileName), True);
    Entry.FileName := AFileName;
    Entry.Name := ExtractFileName(AFileName);
    Entry.Stem := ChangeFileExt(Entry.Name, '');
    Entry.RelativePath := RelativeTo(AFileName, ASources.Root);
    Entry.Origin := AOrigin;
    Found.Add(Entry);
  end;

  function Cancelled: Boolean;
  begin
    Result := Assigned(ACancelled) and ACancelled();
  end;

  procedure AddFolders(const AFolders: TArray<string>; ARecursive: Boolean; AOrigin: TAtlasQuickOpenOrigin);
  var
    Folder, FileName: string;
    Done: TDictionary<string, Boolean>;
  begin
    Done := TDictionary<string, Boolean>.Create;
    try
      for Folder in AFolders do
      begin
        if (Folder = '') or Done.ContainsKey(LowerCase(Folder)) or Cancelled or (Found.Count >= MaxFiles) then
        begin
          Continue;
        end;
        Done.Add(LowerCase(Folder), True);
        for FileName in AList(Folder, ARecursive) do
        begin
          Add(FileName, AOrigin);
        end;
      end;
    finally
      Done.Free;
    end;
  end;

var
  FileName: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  Found := TList<TAtlasQuickOpenFile>.Create;
  try
    for FileName in ASources.ProjectFiles do
    begin
      Add(FileName, TAtlasQuickOpenOrigin.Project);
    end;
    AddFolders(ASources.Folders, False, TAtlasQuickOpenOrigin.SearchPath);
    AddFolders(ASources.LibraryFolders, True, TAtlasQuickOpenOrigin.Library_);
    Result := Found.ToArray;
  finally
    Found.Free;
    Seen.Free;
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
  Text: string;
begin
  Text := Trim(AText);
  if Text = '' then
  begin
    Exit(TAtlasCompletionMatcher.ScoreSubsequence);
  end;
  if (Pos('\', Text) > 0) or (Pos('/', Text) > 0) then
  begin
    Exit(TAtlasCompletionMatcher.Score(Text.Replace('/', '\'), AFile.RelativePath));
  end;
  if Pos('.', Text) > 0 then
  begin
    Result := TAtlasCompletionMatcher.Score(Text, AFile.Name);
  end
  else
  begin
    Result := TAtlasCompletionMatcher.Score(Text, AFile.Stem);
  end;
  if Result = TAtlasCompletionMatcher.NoMatch then
  begin
    // Ersatzweise der Pfad: "common lsp" findet Dateien unter Common\Lsp.
    Result := TAtlasCompletionMatcher.Score(Text.Replace(' ', '\'), AFile.RelativePath);
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
  Scores, Tiers, Boosts: TArray<Integer>;
  Found: TList<Integer>;
  Open: TDictionary<string, Boolean>;
  Index, Points: Integer;
  FileName: string;
  Files: TAtlasQuickOpenFiles;
begin
  Files := AFiles;
  SetLength(Scores, Length(Files));
  SetLength(Tiers, Length(Files));
  SetLength(Boosts, Length(Files));
  Found := TList<Integer>.Create;
  Open := TDictionary<string, Boolean>.Create;
  try
    for FileName in AOpen do
    begin
      Open.AddOrSetValue(LowerCase(FileName), True);
    end;
    for Index := 0 to High(Files) do
    begin
      Points := Score(AText, Files[Index]);
      if Points = TAtlasCompletionMatcher.NoMatch then
      begin
        Continue;
      end;
      Scores[Index] := Points;
      if ARecent <> nil then
      begin
        Boosts[Index] := ARecent.Boost(RecentKey(Files[Index].FileName));
      end;
      Tiers[Index] := TierOf(Open, Files[Index], Boosts[Index]);
      Found.Add(Index);
    end;
    Found.Sort(FileComparer(Files, Scores, Tiers, Boosts));
    if Found.Count > MaxResults then
    begin
      Found.Count := MaxResults;
    end;
    Result := Found.ToArray;
  finally
    Open.Free;
    Found.Free;
  end;
end;

class function TAtlasQuickOpen.OrderSymbols(const ANames: TArray<string>; const AText: string): TArray<Integer>;
var
  Scores: TArray<Integer>;
  Found: TList<Integer>;
  Index: Integer;
begin
  SetLength(Scores, Length(ANames));
  Found := TList<Integer>.Create;
  try
    for Index := 0 to High(ANames) do
    begin
      Scores[Index] := TAtlasCompletionMatcher.Score(AText, ANames[Index]);
      if Scores[Index] <> TAtlasCompletionMatcher.NoMatch then
      begin
        Found.Add(Index);
      end;
    end;
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Scores[B] - Scores[A];
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end));
    if Found.Count > MaxResults then
    begin
      Found.Count := MaxResults;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
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
  Thread: TThread;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopping := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
  for Thread in FThreads do
  begin
    Thread.WaitFor;
    Thread.Free;
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
  Index: Integer;
begin
  for Index := FThreads.Count - 1 downto 0 do
  begin
    if FThreads[Index].Finished then
    begin
      FThreads[Index].Free;
      FThreads.Delete(Index);
    end;
  end;
end;

procedure TAtlasQuickOpenList.Refresh(const ASources: TAtlasQuickOpenSources);
var
  Key: string;
  Generation: Integer;
  Sources: TAtlasQuickOpenSources;
  Lister: TAtlasQuickOpenLister;
  Thread: TThread;
begin
  Sweep;
  Key := ASources.Key;
  System.TMonitor.Enter(FLock);
  try
    if Key = FKey then
    begin
      Exit;
    end;
    FKey := Key;
    Inc(FGeneration);
    Generation := FGeneration;
    Inc(FBuilding);
  finally
    System.TMonitor.Exit(FLock);
  end;
  Sources := ASources;
  Lister := FLister;
  Thread := TThread.CreateAnonymousThread(
    procedure
    var
      Files: TAtlasQuickOpenFiles;
    begin
      Files := nil;
      try
        Files := TAtlasQuickOpen.Collect(Sources, Lister,
          function: Boolean
          begin
            System.TMonitor.Enter(FLock);
            try
              Result := FStopping or (Generation <> FGeneration);
            finally
              System.TMonitor.Exit(FLock);
            end;
          end);
      except
        // Ein Fehler beim Lesen der Ordner lässt die bisherige Liste stehen.
        on Exception do
          Generation := -1;
      end;
      Store(Generation, Files);
    end);
  Thread.FreeOnTerminate := False;
  FThreads.Add(Thread);
  Thread.Start;
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
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  while Building do
  begin
    if Watch.ElapsedMilliseconds >= ATimeoutMs then
    begin
      Exit(False);
    end;
    TThread.Sleep(5);
  end;
  Result := True;
end;

end.
