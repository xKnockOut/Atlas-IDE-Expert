unit Atlas.Common.Index.Builder;

// Baut den Symbolindex auf.
//
// - Build: indiziert die Projektdateien. Einträge aus dem Cache gelten
//   weiter, wenn der Zeitstempel gleich ist (Datei wird nicht gelesen) oder
//   der Hash des Inhalts gleich ist (nur der Zeitstempel wird erneuert).
// - Danach werden die referenzierten Units (uses) bedarfsweise über den
//   Resolver gesucht und indiziert, rekursiv, aber nur was wirklich in einer
//   uses-Liste vorkommt. So kommen RTL und VCL nur teilweise in den Index.
// - EnsureUnit indiziert eine einzelne Unit nachträglich.
// - ApplyChanges übernimmt Dateiänderungen von außen (git checkout,
//   andere Werkzeuge): bekannte Units neu einlesen, gelöschte entfernen.
//   Neue Dateien kommen erst in den Index, wenn sie referenziert werden;
//   dafür vergisst der Builder die bisher nicht gefundenen Units.
// - Include-Dateien (#264) werden über IncludePaths gesucht. Units mit
//   Includes übernimmt der Builder aus dem Cache nur, wenn auch alle
//   Include-Dateien denselben Zeitstempel haben (#617); eine geänderte
//   Include-Datei liest alle Units neu ein, die sie einbinden.
// - Aus dem Cache kommen zunächst nur die Köpfe; die Symbole einer Unit
//   dekodiert der Builder erst, wenn er die Unit übernimmt (#617).
// - Läuft im aufrufenden Thread; den Hintergrund-Thread stellt die
//   Komposition bereit.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache;

type
  TIndexBuildResult = record
    Parsed: Integer;
    FromCache: Integer;
    Missing: Integer;
    Cancelled: Boolean;
  end;

  /// <summary>Eine Stufe des Aufbaus ist fertig; APartial ist der Stand bis dahin.</summary>
  TIndexStageDone = reference to procedure(const APartial: TIndexBuildResult);

  TIndexBuilder = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FDefines: TArray<string>;
    FResolveUnit: TUnitFileResolver;
    FCached: TDictionary<string, TIndexCacheEntry>;
    // Von EnsureUnit aus Anfrage-Threads genutzt.
    FFailedUnits: TDictionary<string, Boolean>;
    FFailedLock: TObject;
    FIncludePaths: TArray<string>;
    function IncludeResolver: TIncludeResolver;
    function IncludeStampsOf(const AIncludes: TArray<string>): TArray<Int64>;
    function IncludesUnchanged(const ACached: TUnitIndex): Boolean;
    function IndexFile(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult): Boolean;
    procedure IndexReferenced(var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled);
    function IsCancelled(const ACancelled: TIndexCancelled): Boolean;
    /// <summary>Alle Units aus AFiles, die noch nicht im Index stehen (#648); False bei Abbruch.</summary>
    function IndexAll(const AFiles: TArray<string>; ALibrary: Boolean; const ALabel: string; ADone, ATotal: Integer;
      var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled): Boolean;
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
    destructor Destroy; override;
    /// <summary>Übernimmt einen geladenen Cache als Vergleichsstand.</summary>
    procedure UseCache(const AUnits: TArray<TUnitIndex>); overload;
    /// <summary>Übernimmt die Köpfe eines Caches; Symbole werden erst bei Bedarf dekodiert.</summary>
    procedure UseCache(const AEntries: TArray<TIndexCacheEntry>); overload;
    function Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled): TIndexBuildResult; overload;
    /// <summary>Aufbau in Stufen (#648): AFiles samt über uses erreichbarer Units, dann ASearchFiles (Projekt),
    /// dann ALibraryFiles (Bibliothek). ATurn ordnet die Stufen mehrerer Aufbauten; nil = ohne Warten.
    /// AProjectDone läuft nach der Projektstufe (Projektdateien und über uses erreichbare Units).</summary>
    function Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled; const ATurn: IIndexTurn;
      const AProjectDone: TIndexStageDone = nil): TIndexBuildResult; overload;
    /// <summary>Indiziert die Unit, falls noch nicht vorhanden. False, wenn sie nicht gefunden wird.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Übernimmt Dateiänderungen; liefert die Zahl geänderter Units.</summary>
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    /// <summary>Ungespeicherter Text einer bekannten Unit (Tipp-Pause, #492): nur im Speicher, ohne Cache;
    /// True, wenn der Index sich dadurch geändert hat.</summary>
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Suchpfade für $I nach dem Ordner der Unit (Projekt-Suchpfade, dann Bibliothekspfade).</summary>
    property IncludePaths: TArray<string> read FIncludePaths write FIncludePaths;
  end;

implementation

uses
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Index.Extractor;

{ TIndexBuilder }

constructor TIndexBuilder.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FDefines := ADefines;
  FResolveUnit := AResolveUnit;
  FCached := TDictionary<string, TIndexCacheEntry>.Create;
  FFailedUnits := TDictionary<string, Boolean>.Create;
  FFailedLock := TObject.Create;
end;

destructor TIndexBuilder.Destroy;
begin
  FFailedLock.Free;
  FFailedUnits.Free;
  FCached.Free;
  inherited;
end;

procedure TIndexBuilder.UseCache(const AUnits: TArray<TUnitIndex>);
var
  UnitIndex: TUnitIndex;
begin
  for UnitIndex in AUnits do
    // Kompakt gespeicherte Units fehlen Symbole; sie werden neu eingelesen.
    if not UnitIndex.Compact then
      FCached.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), TIndexCacheEntry.FromUnit(UnitIndex));
end;

procedure TIndexBuilder.UseCache(const AEntries: TArray<TIndexCacheEntry>);
var
  Entry: TIndexCacheEntry;
begin
  for Entry in AEntries do
    if not Entry.Header.Compact then
      FCached.AddOrSetValue(AnsiUpperCase(Entry.Header.FileName), Entry);
end;

function TIndexBuilder.IsCancelled(const ACancelled: TIndexCancelled): Boolean;
begin
  Result := Assigned(ACancelled) and ACancelled();
end;

function TIndexBuilder.IncludeResolver: TIncludeResolver;
var
  FileSystem: IIndexFileSystem;
begin
  FileSystem := FFileSystem;
  Result := TIncludeFiles.Resolver(FIncludePaths,
    function(const AFileName: string): Boolean
    var
      Stamp: Int64;
    begin
      Result := FileSystem.FileStamp(AFileName, Stamp);
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileSystem.ReadText(AFileName, AText);
    end);
end;

function TIndexBuilder.IncludeStampsOf(const AIncludes: TArray<string>): TArray<Int64>;
var
  Index: Integer;
begin
  SetLength(Result, Length(AIncludes));
  for Index := 0 to High(AIncludes) do
    if not FFileSystem.FileStamp(AIncludes[Index], Result[Index]) then
      Result[Index] := -1;
end;

function TIndexBuilder.IncludesUnchanged(const ACached: TUnitIndex): Boolean;
var
  Index: Integer;
  Stamp: Int64;
begin
  if Length(ACached.Includes) = 0 then
    Exit(True);
  // Ältere Einträge ohne Zeitstempel gelten als geändert.
  if Length(ACached.IncludeStamps) <> Length(ACached.Includes) then
    Exit(False);
  for Index := 0 to High(ACached.Includes) do
  begin
    if not FFileSystem.FileStamp(ACached.Includes[Index], Stamp) then
      Exit(False);
    if (ACached.IncludeStamps[Index] < 0) or (Stamp <> ACached.IncludeStamps[Index]) then
      Exit(False);
  end;
  Result := True;
end;

function TIndexBuilder.IndexFile(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult): Boolean;
var
  Stamp: Int64;
  Text, Hash: string;
  Entry: TIndexCacheEntry;
  Cached, UnitIndex: TUnitIndex;
  HasCache: Boolean;
begin
  if not FFileSystem.FileStamp(AFileName, Stamp) then
  begin
    Inc(AResult.Missing);
    Exit(False);
  end;
  HasCache := FCached.TryGetValue(AnsiUpperCase(AFileName), Entry);
  // Mit Includes kann sich das Ergebnis ändern, ohne dass die Unit sich ändert.
  if HasCache and not IncludesUnchanged(Entry.Header) then
    HasCache := False;
  // Zeitstempel oder Inhalt passen: erst jetzt die Symbole dekodieren; ein beschädigter Block
  // zählt wie ein fehlender Cache-Eintrag.
  if HasCache and (Entry.Header.Stamp = Stamp) and TIndexCache.Expand(Entry, Cached) then
  begin
    Cached.Library_ := ALibrary;
    FIndex.AddUnit(Cached);
    Inc(AResult.FromCache);
    Exit(True);
  end;
  if not FFileSystem.ReadText(AFileName, Text) then
  begin
    Inc(AResult.Missing);
    Exit(False);
  end;
  Hash := TIndexCache.HashOf(Text);
  if HasCache and (Entry.Header.Hash = Hash) and TIndexCache.Expand(Entry, Cached) then
  begin
    Cached.Stamp := Stamp;
    Cached.Library_ := ALibrary;
    FIndex.AddUnit(Cached);
    Inc(AResult.FromCache);
    Exit(True);
  end;
  UnitIndex := TIndexExtractor.ExtractText(Text, AFileName, FDefines, IncludeResolver());
  UnitIndex.Stamp := Stamp;
  UnitIndex.Hash := Hash;
  UnitIndex.IncludeStamps := IncludeStampsOf(UnitIndex.Includes);
  UnitIndex.Library_ := ALibrary;
  FIndex.AddUnit(UnitIndex);
  Inc(AResult.Parsed);
  Result := True;
end;

procedure TIndexBuilder.IndexReferenced(var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled);
var
  Pending: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  UnitIndex: TUnitIndex;
  Name, UsedName, FileName: string;
  Existing: TUnitIndex;
begin
  if not Assigned(FResolveUnit) then
    Exit;
  Pending := TQueue<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for UnitIndex in FIndex.Units do
    begin
      Seen.AddOrSetValue(UpperCase(UnitIndex.UnitName), True);
      for Name in UnitIndex.InterfaceUses do
        Pending.Enqueue(Name);
      for Name in UnitIndex.ImplementationUses do
        Pending.Enqueue(Name);
    end;
    while Pending.Count > 0 do
    begin
      if IsCancelled(ACancelled) then
      begin
        AResult.Cancelled := True;
        Exit;
      end;
      Name := Pending.Dequeue;
      if Seen.ContainsKey(UpperCase(Name)) then
        Continue;
      Seen.Add(UpperCase(Name), True);
      if FIndex.FindUnit(Name, Existing) then
        Continue;
      FileName := FResolveUnit(Name);
      if FileName = '' then
        Continue;
      if Assigned(AProgress) then
        AProgress(TIndexProgressKind.Report, Name, -1);
      if IndexFile(FileName, True, AResult) and FIndex.FindFile(FileName, UnitIndex) then
      begin
        // Nur das interface ist von außen sichtbar; dessen uses reichen.
        for UsedName in UnitIndex.InterfaceUses do
          Pending.Enqueue(UsedName);
      end;
    end;
  finally
    Seen.Free;
    Pending.Free;
  end;
end;

function TIndexBuilder.Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled): TIndexBuildResult;
begin
  Result := Build(AFiles, nil, nil, AProgress, ACancelled, nil);
end;

function TIndexBuilder.IndexAll(const AFiles: TArray<string>; ALibrary: Boolean; const ALabel: string;
  ADone, ATotal: Integer; var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled): Boolean;
var
  Index: Integer;
  Existing: TUnitIndex;
begin
  for Index := 0 to High(AFiles) do
  begin
    if IsCancelled(ACancelled) then
      Exit(False);
    // Schon da (anderes Projekt der Gruppe, über uses erreicht): nicht noch einmal lesen.
    if FIndex.FindFile(AFiles[Index], Existing) then
      Continue;
    if Assigned(AProgress) then
      AProgress(TIndexProgressKind.Report, ALabel + ExtractFileName(AFiles[Index]),
        ((ADone + Index) * 100) div ATotal);
    IndexFile(AFiles[Index], ALibrary, AResult);
  end;
  Result := True;
end;

function TIndexBuilder.Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>;
  const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled; const ATurn: IIndexTurn;
  const AProjectDone: TIndexStageDone): TIndexBuildResult;
var
  Index, Total: Integer;

  function Enter(AStage: TIndexStage): Boolean;
  begin
    Result := (ATurn = nil) or ATurn.Enter(AStage, ACancelled);
  end;

  procedure Leave;
  begin
    if ATurn <> nil then
      ATurn.Leave;
  end;

begin
  Result := Default(TIndexBuildResult);
  Total := Length(AFiles) + Length(ASearchFiles) + Length(ALibraryFiles);
  if Total = 0 then
    Total := 1;
  if Assigned(AProgress) then
    AProgress(TIndexProgressKind.Started, 'Symbolindex', 0);
  try
    if not Enter(TIndexStage.Project) then
    begin
      Result.Cancelled := True;
      Exit;
    end;
    try
      for Index := 0 to High(AFiles) do
      begin
        if IsCancelled(ACancelled) then
        begin
          Result.Cancelled := True;
          Exit;
        end;
        if Assigned(AProgress) then
          AProgress(TIndexProgressKind.Report, AFiles[Index], (Index * 100) div Total);
        IndexFile(AFiles[Index], False, Result);
      end;
      IndexReferenced(Result, AProgress, ACancelled);
    finally
      Leave;
    end;
    if Result.Cancelled then
      Exit;
    if Assigned(AProjectDone) then
      AProjectDone(Result);
    if Length(ASearchFiles) > 0 then
    begin
      if not Enter(TIndexStage.SearchPaths) then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      try
        // Units der Suchpfade gehören zum Projekt, auch wenn keine sie einbindet.
        Result.Cancelled := not IndexAll(ASearchFiles, False, 'Suchpfade: ', Length(AFiles), Total, Result,
          AProgress, ACancelled);
      finally
        Leave;
      end;
      if Result.Cancelled then
        Exit;
    end;
    if Length(ALibraryFiles) > 0 then
    begin
      if not Enter(TIndexStage.Library_) then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      try
        Result.Cancelled := not IndexAll(ALibraryFiles, True, 'Bibliothek: ',
          Length(AFiles) + Length(ASearchFiles), Total, Result, AProgress, ACancelled);
      finally
        Leave;
      end;
    end;
  finally
    if Assigned(AProgress) then
      AProgress(TIndexProgressKind.Finished,
        Format('%d Units, %d Symbole', [FIndex.UnitCount, FIndex.SymbolCount]), 100);
  end;
end;

function TIndexBuilder.EnsureUnit(const AUnitName: string): Boolean;
var
  Existing: TUnitIndex;
  FileName: string;
  Ignored: TIndexBuildResult;
  Failed: Boolean;
begin
  if FIndex.FindUnit(AUnitName, Existing) then
    Exit(True);
  if not Assigned(FResolveUnit) then
    Exit(False);
  TMonitor.Enter(FFailedLock);
  try
    Failed := FFailedUnits.ContainsKey(UpperCase(AUnitName));
  finally
    TMonitor.Exit(FFailedLock);
  end;
  if Failed then
    Exit(False);
  FileName := FResolveUnit(AUnitName);
  Ignored := Default(TIndexBuildResult);
  Result := (FileName <> '') and IndexFile(FileName, True, Ignored);
  if not Result then
  begin
    TMonitor.Enter(FFailedLock);
    try
      FFailedUnits.AddOrSetValue(UpperCase(AUnitName), True);
    finally
      TMonitor.Exit(FFailedLock);
    end;
  end;
end;

function TIndexBuilder.ApplyText(const AFileName, AText: string): Boolean;
var
  Existing, UnitIndex: TUnitIndex;
  Hash: string;
begin
  Result := False;
  // Nur Units, die der Index kennt; neue Dateien kommen wie bisher beim Speichern dazu.
  if not FIndex.FindFile(AFileName, Existing) then
    Exit;
  Hash := TIndexCache.HashOf(AText);
  if Hash = Existing.Hash then
    Exit;
  UnitIndex := TIndexExtractor.ExtractText(AText, AFileName, FDefines, IncludeResolver());
  // Zeitstempel bleibt der der Datei: Beim Speichern liest IndexFile sie dann neu von der Platte.
  UnitIndex.Stamp := Existing.Stamp;
  UnitIndex.Hash := Hash;
  UnitIndex.IncludeStamps := IncludeStampsOf(UnitIndex.Includes);
  UnitIndex.Library_ := Existing.Library_;
  FIndex.AddUnit(UnitIndex);
  Result := True;
end;

function TIndexBuilder.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  Change: TFileChange;
  Existing: TUnitIndex;
  Ignored: TIndexBuildResult;
  Known: Boolean;
  UnitIndex: TUnitIndex;
  Dependent: TArray<TUnitIndex>;
  Include: string;
begin
  Result := 0;
  Ignored := Default(TIndexBuildResult);
  for Change in AChanges do
  begin
    // Units, die die Datei per $I einbinden, neu einlesen.
    Dependent := nil;
    for UnitIndex in FIndex.Units do
      for Include in UnitIndex.Includes do
        if SameText(Include, Change.FileName) then
        begin
          Dependent := Dependent + [UnitIndex];
          Break;
        end;
    for UnitIndex in Dependent do
      if IndexFile(UnitIndex.FileName, UnitIndex.Library_, Ignored) then
        Inc(Result);
    Known := FIndex.FindFile(Change.FileName, Existing);
    case Change.Kind of
      TFileChangeKind.Deleted:
        if Known then
        begin
          FIndex.RemoveFile(Change.FileName);
          Inc(Result);
        end;
      TFileChangeKind.Created, TFileChangeKind.Changed:
        if Known then
        begin
          // IndexFile vergleicht mit dem Cache vom Start; ein geänderter
          // Zeitstempel führt zum Neueinlesen, gleicher Inhalt nicht.
          if IndexFile(Change.FileName, Existing.Library_, Ignored) then
            Inc(Result)
          else
          begin
            FIndex.RemoveFile(Change.FileName);
            Inc(Result);
          end;
        end
        else
        begin
          // Eine neue Datei kann eine bisher fehlende Unit sein.
          TMonitor.Enter(FFailedLock);
          try
            FFailedUnits.Clear;
          finally
            TMonitor.Exit(FFailedLock);
          end;
        end;
    end;
  end;
end;

end.
