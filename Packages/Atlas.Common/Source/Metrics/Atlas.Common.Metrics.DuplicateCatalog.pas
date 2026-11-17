unit Atlas.Common.Metrics.DuplicateCatalog;

// Rümpfe der Units eines Projekts für die Regel duplicate-routine-body: Die Regel prüft eine Unit, braucht aber die
// Fingerabdrücke aller anderen. Der Katalog merkt sich je Datei die Rümpfe (Prüfsumme und Länge des Textes, wie
// TMetricsCollector) und für die zuletzt angefragte Dateiliste ein Verzeichnis Fingerabdruck → Fassungen.
//
// Die Regel fragt für jede Unit einer Projektgruppe dieselbe Liste an (alle Dateien der Gruppe, die geprüfte Unit
// eingeschlossen); die Reihenfolge zählt nicht. Ein Verzeichnis gilt cFreshMs lang ab dem Ende seines Baus: Ein Lauf
// über viele Units (--check, „Projekt prüfen“) liest die Dateien so nur einmal statt einmal je Unit. Danach liest
// der nächste Aufruf alle Texte neu und parst nur geänderte. Im Editor sieht die Regel Änderungen an anderen Units
// deshalb erst nach höchstens cFreshMs; die geprüfte Unit selbst kommt immer aus ihrem aktuellen Text. Threadsicher.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Metrics.DuplicateBodies;

type
  /// <summary>Fingerabdruck → Fassungen (Pfad absolut, Routine, Zeile) über eine Dateiliste;
  /// unveränderlich.</summary>
  IDuplicateBodyIndex = interface
    ['{4C7B2E19-8D35-4F0A-A6C1-2E9B7D4F5310}']
    /// <summary>Fassungen mit dem Fingerabdruck AHash; nil ohne.</summary>
    function Copies(const AHash: string): TArray<TDuplicateBodyMember>;
    /// <summary>Gelesene Dateien.</summary>
    function FileCount: Integer;
  end;

  TDuplicateBodyCatalog = class
  public const
    /// <summary>So lange gilt ein Verzeichnis, bevor die Dateien neu gelesen werden.</summary>
    cFreshMs = 30000;
  private type
    TEntry = record
      Size: Integer;
      Checksum: Cardinal;
      Bodies: TArray<TRoutineBody>;
    end;
  private class var
    FShared: TDuplicateBodyCatalog;
  private
    FLock: TObject;
    FFiles: TDictionary<string, TEntry>;
    FIndex: IDuplicateBodyIndex;
    FIndexKey: string;
    FIndexStamp: Int64;
    function BodiesOf(const AFileName, AText: string): TArray<TRoutineBody>;
    function Build(const AFiles: TArray<string>; const AReadText: TMetricsReadText): IDuplicateBodyIndex;
    /// <summary>Kurzer Schlüssel einer sortierten Dateiliste: Anzahl, Länge und Prüfsumme der Pfade.</summary>
    class function KeyOf(const AFiles: TArray<string>): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Verzeichnis über AFiles (.pas, .dpr, .dpk; andere fehlen); aus dem Speicher, solange es für
    /// dieselben Dateien (in beliebiger Reihenfolge) jünger als cFreshMs ist.</summary>
    function IndexOf(const AFiles: TArray<string>; const AReadText: TMetricsReadText): IDuplicateBodyIndex;
    /// <summary>Vergisst alles (Tests: Der Leckmonitor zählt gemerkte Dateien sonst dem Test zu).</summary>
    procedure Clear;
    /// <summary>Der Katalog des Prozesses.</summary>
    class function Shared: TDuplicateBodyCatalog; static;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics;

type
  TDuplicateBodyIndex = class(TInterfacedObject, IDuplicateBodyIndex)
  private
    FCopies: TDictionary<string, TArray<TDuplicateBodyMember>>;
    FFileCount: Integer;
  public
    constructor Create(AFileCount: Integer);
    destructor Destroy; override;
    procedure Add(const AFileName: string; const ABody: TRoutineBody);
    function Copies(const AHash: string): TArray<TDuplicateBodyMember>;
    function FileCount: Integer;
  end;

{ TDuplicateBodyIndex }

constructor TDuplicateBodyIndex.Create(AFileCount: Integer);
begin
  inherited Create;
  FFileCount := AFileCount;
  FCopies := TDictionary<string, TArray<TDuplicateBodyMember>>.Create;
end;

destructor TDuplicateBodyIndex.Destroy;
begin
  FCopies.Free;
  inherited Destroy;
end;

procedure TDuplicateBodyIndex.Add(const AFileName: string; const ABody: TRoutineBody);
var
  mMembers: TArray<TDuplicateBodyMember>;
  mMember: TDuplicateBodyMember;
begin
  mMember.Path := AFileName;
  mMember.Routine := ABody.Name;
  mMember.Line := ABody.Line;
  mMembers := nil;
  if not FCopies.TryGetValue(ABody.Hash, mMembers) then
  begin
    mMembers := nil;
  end;
  FCopies.AddOrSetValue(ABody.Hash, mMembers + [mMember]);
end;

function TDuplicateBodyIndex.Copies(const AHash: string): TArray<TDuplicateBodyMember>;
begin
  if not FCopies.TryGetValue(AHash, Result) then
  begin
    Result := nil;
  end;
end;

function TDuplicateBodyIndex.FileCount: Integer;
begin
  Result := FFileCount;
end;

{ TDuplicateBodyCatalog }

constructor TDuplicateBodyCatalog.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FFiles := TDictionary<string, TEntry>.Create;
end;

destructor TDuplicateBodyCatalog.Destroy;
begin
  FIndex := nil;
  FFiles.Free;
  FLock.Free;
  inherited Destroy;
end;

class function TDuplicateBodyCatalog.Shared: TDuplicateBodyCatalog;
begin
  Result := FShared;
end;

procedure TDuplicateBodyCatalog.Clear;
begin
  System.TMonitor.Enter(FLock);
  try
    FFiles.Clear;
    FFiles.TrimExcess;
    FIndex := nil;
    FIndexKey := '';
    FIndexStamp := 0;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TDuplicateBodyCatalog.BodiesOf(const AFileName, AText: string): TArray<TRoutineBody>;
var
  mKey: string;
  mEntry: TEntry;
  mSum: Cardinal;
begin
  mKey := UpperCase(AFileName);
  mSum := TMetricsCollector.Checksum(AText);
  if FFiles.TryGetValue(mKey, mEntry) and (mEntry.Size = Length(AText)) and (mEntry.Checksum = mSum) then
  begin
    Exit(mEntry.Bodies);
  end;
  Result := TDuplicateBodies.ForText(AText);
  mEntry.Size := Length(AText);
  mEntry.Checksum := mSum;
  mEntry.Bodies := Result;
  FFiles.AddOrSetValue(mKey, mEntry);
end;

function TDuplicateBodyCatalog.Build(const AFiles: TArray<string>;
  const AReadText: TMetricsReadText): IDuplicateBodyIndex;
var
  mIndex: TDuplicateBodyIndex;
  mFileName, mText: string;
  mBody: TRoutineBody;
  mCount: Integer;
begin
  mIndex := TDuplicateBodyIndex.Create(0);
  Result := mIndex;
  mCount := 0;
  for mFileName in AFiles do
  begin
    if not TMetricsCollector.IsSource(mFileName) or not Assigned(AReadText) or not AReadText(mFileName, mText) then
    begin
      Continue;
    end;
    Inc(mCount);
    for mBody in BodiesOf(mFileName, mText) do
    begin
      mIndex.Add(mFileName, mBody);
    end;
  end;
  mIndex.FFileCount := mCount;
end;

class function TDuplicateBodyCatalog.KeyOf(const AFiles: TArray<string>): string;
var
  mJoined: string;
begin
  mJoined := UpperCase(string.Join(#1, AFiles));
  Result := Format('%d:%d:%x', [Length(AFiles), Length(mJoined), TMetricsCollector.Checksum(mJoined)]);
end;

function TDuplicateBodyCatalog.IndexOf(const AFiles: TArray<string>;
  const AReadText: TMetricsReadText): IDuplicateBodyIndex;
var
  mFiles: TArray<string>;
  mKey: string;
begin
  // Sortiert: Die Reihenfolge der Anfrage zählt nicht, und das Verzeichnis nennt die Fassungen stets in derselben
  // Folge.
  mFiles := TDuplicateBodies.SortedPaths(AFiles);
  mKey := KeyOf(mFiles);
  System.TMonitor.Enter(FLock);
  try
    if (FIndex <> nil) and (FIndexKey = mKey) and
      ((TStopwatch.GetTimeStamp - FIndexStamp) * 1000 div TStopwatch.Frequency < cFreshMs) then
    begin
      Exit(FIndex);
    end;
    // Unter der Sperre gebaut: Zwei Prüfungen gleichzeitig lesen die Dateien so nicht doppelt. Die Frist beginnt
    // erst nach dem Bau, sonst wäre ein Verzeichnis, dessen Bau länger als cFreshMs dauert, sofort veraltet.
    FIndex := Build(mFiles, AReadText);
    FIndexKey := mKey;
    FIndexStamp := TStopwatch.GetTimeStamp;
    Result := FIndex;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

initialization
  TDuplicateBodyCatalog.FShared := TDuplicateBodyCatalog.Create;

finalization
  FreeAndNil(TDuplicateBodyCatalog.FShared);

end.
