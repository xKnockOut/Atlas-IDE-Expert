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
//   Includes übernimmt der Builder nie ungeprüft aus dem Cache, und eine
//   geänderte Include-Datei liest alle Units neu ein, die sie einbinden.
// - Läuft im aufrufenden Thread; den Hintergrund-Thread stellt die
//   Komposition bereit.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract;

type
  TIndexBuildResult = record
    Parsed: Integer;
    FromCache: Integer;
    Missing: Integer;
    Cancelled: Boolean;
  end;

  TIndexBuilder = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FDefines: TArray<string>;
    FResolveUnit: TUnitFileResolver;
    FCached: TDictionary<string, TUnitIndex>;
    // Von EnsureUnit aus Anfrage-Threads genutzt.
    FFailedUnits: TDictionary<string, Boolean>;
    FFailedLock: TObject;
    FIncludePaths: TArray<string>;
    function IncludeResolver: TIncludeResolver;
    function IndexFile(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult): Boolean;
    procedure IndexReferenced(var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled);
    function IsCancelled(const ACancelled: TIndexCancelled): Boolean;
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
    destructor Destroy; override;
    /// <summary>Übernimmt einen geladenen Cache als Vergleichsstand.</summary>
    procedure UseCache(const AUnits: TArray<TUnitIndex>);
    function Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled): TIndexBuildResult;
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
  Atlas.Common.Index.Cache,
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
  FCached := TDictionary<string, TUnitIndex>.Create;
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
      FCached.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), UnitIndex);
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

function TIndexBuilder.IndexFile(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult): Boolean;
var
  Stamp: Int64;
  Text, Hash: string;
  Cached, UnitIndex: TUnitIndex;
  HasCache: Boolean;
begin
  if not FFileSystem.FileStamp(AFileName, Stamp) then
  begin
    Inc(AResult.Missing);
    Exit(False);
  end;
  HasCache := FCached.TryGetValue(AnsiUpperCase(AFileName), Cached);
  // Mit Includes kann sich das Ergebnis ändern, ohne dass die Unit sich ändert.
  if HasCache and (Length(Cached.Includes) > 0) then
    HasCache := False;
  if HasCache and (Cached.Stamp = Stamp) then
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
  if HasCache and (Cached.Hash = Hash) then
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
var
  Index: Integer;
begin
  Result := Default(TIndexBuildResult);
  if Assigned(AProgress) then
    AProgress(TIndexProgressKind.Started, 'Symbolindex', 0);
  try
    for Index := 0 to High(AFiles) do
    begin
      if IsCancelled(ACancelled) then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      if Assigned(AProgress) then
        AProgress(TIndexProgressKind.Report, AFiles[Index], (Index * 100) div Length(AFiles));
      IndexFile(AFiles[Index], False, Result);
    end;
    IndexReferenced(Result, AProgress, ACancelled);
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
