unit Atlas.Common.Architecture.UsesService;

// Uses-Graph je Symbolindex (#268), für alle Nutzer derselbe: Architektur
// (#1118), Zyklen (#64), Unit-Beziehungen (#593), Kosten einer Änderung
// (#554), Export (#65).
//
// - Der Graph folgt dem Index: Hat sich dessen Generation geändert, gleicht
//   Read ihn vor dem Lesen ab und baut nur die geänderten Units neu ein
//   (inkrementell, #22).
// - Je Optionssatz (Wurzel, Namensräume, Ausschlüsse) ein eigener Graph, die
//   zuletzt benutzten ACapacity Stück bleiben stehen (#3075, Vorgabe einer):
//   Wer zwischen Projekten einer Gruppe wechselt, bekommt seinen Graphen
//   zurück und gleicht ihn nur ab, statt ihn mit allen Units samt Bibliothek
//   neu aufzubauen. SetOptions wählt nur den Satz für Read ohne Optionen;
//   der alte Graph weicht, sobald ein neuer über ACapacity hinaus entsteht.
// - Lesen und Abgleichen laufen unter einer Sperre; ein Leser hält sie nur
//   für seine Abfrage. Abfragen dauern auch bei einigen tausend Units nur
//   Millisekunden. Aus dem Hauptthread der IDE wird nie gelesen: der Server
//   rechnet im Arbeitsthread der Anfrage.
// - TryRead wartet nie: Fehlt der Graph, ist er veraltet oder hält ein anderer
//   die Sperre, baut bzw. gleicht ein eigener Thread im Hintergrund ab und
//   TryRead meldet Pending (veraltet: liest den alten Stand und meldet
//   Stale). Für Anfragen, die beim Tippen kommen (Statusleiste).
// - Derived hält Auswertungen über den ganzen Graphen (Feature-Zyklen) je
//   Schlüssel, bis sich der Graph ändert: Jede Datei einer Prüfung fragt
//   dieselbe Auswertung, gerechnet wird sie einmal.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph;

{$SCOPEDENUMS ON}

type
  TUsesGraphReader = reference to procedure(const AGraph: TUsesGraph);
  TUsesGraphDerive = reference to function(const AGraph: TUsesGraph): IInterface;

  /// <summary>Wie ein Lesen den Graphen vorfand (für das Diagnoselog).</summary>
  TUsesGraphReadKind = (
    /// <summary>Graph stand auf der Generation des Index.</summary>
    Current,
    /// <summary>Inkrementell abgeglichen.</summary>
    Updated,
    /// <summary>Ganz neu aufgebaut.</summary>
    Rebuilt,
    /// <summary>TryRead: älterer Stand gelesen, Abgleich läuft im Hintergrund.</summary>
    Stale,
    /// <summary>TryRead: nichts gelesen, Aufbau läuft im Hintergrund oder die Sperre war belegt.</summary>
    Pending);

  TUsesGraphRead = record
    Kind: TUsesGraphReadKind;
    /// <summary>Generation des Index, auf der der gelesene Graph stand; -1 bei Pending.</summary>
    Generation: Int64;
    /// <summary>Kurzname für das Diagnoselog: current, updated, rebuilt, stale, pending.</summary>
    function KindName: string;
  end;

  TUsesGraphService = class
  public const
    /// <summary>So viele Optionssätze behalten ihren Graphen, wenn der Nutzer je Datei andere Optionen hat
    /// (Projekte einer Gruppe, #3075).</summary>
    cProjectCapacity = 3;
  private type
    TEntry = class
    public
      Options: TUsesGraphOptions;
      Graph: TUsesGraph;
      Generation: Int64;
      /// <summary>Abgeleitete Werte je Schlüssel zur Generation Generation.</summary>
      Derived: TDictionary<string, IInterface>;
      constructor Create(const AOptions: TUsesGraphOptions; AGraph: TUsesGraph; AGeneration: Int64);
      destructor Destroy; override;
    end;
  private
    FIndex: ISymbolIndex;
    FOptions: TUsesGraphOptions;
    FCapacity: Integer;
    /// <summary>Zuletzt benutzter Eintrag vorn.</summary>
    FEntries: TObjectList<TEntry>;
    FLock: TObject;
    FRebuilds: Integer;
    FUpdates: Integer;
    /// <summary>Optionssätze, die der Hintergrund noch aufbauen oder abgleichen soll.</summary>
    FWanted: TList<TUsesGraphOptions>;
    FWorker: TThread;
    FWorkerBusy: Boolean;
    FStopping: Boolean;
    /// <summary>Fehler des letzten Hintergrundlaufs; das nächste TryRead liest dann selbst (der Fehler kommt so
    /// beim Aufrufer an).</summary>
    FWorkerFailed: Boolean;
    FWorkerError: string;
    function IndexOf(const AOptions: TUsesGraphOptions): Integer;
    procedure Touch(AIndex: Integer);
    procedure Add(AEntry: TEntry);
    function Entry(const AOptions: TUsesGraphOptions; out AKind: TUsesGraphReadKind): TEntry;
    function Refresh(AEntry: TEntry): TUsesGraphReadKind;
    function Current(AEntry: TEntry): Boolean;
    procedure Want(const AOptions: TUsesGraphOptions);
    procedure Prepare(const AOptions: TUsesGraphOptions);
    function NextWanted(out AOptions: TUsesGraphOptions): Boolean;
    procedure WorkerFailed(const AError: Exception);
  public
    /// <summary>ACapacity: so viele Optionssätze behalten ihren Graphen (mindestens einer).</summary>
    constructor Create(const AIndex: ISymbolIndex; const AOptions: TUsesGraphOptions;
      ACapacity: Integer = 1);
    destructor Destroy; override;
    /// <summary>Gleiche Optionen (Groß-/Kleinschreibung egal)?</summary>
    class function SameOptions(const A, B: TUsesGraphOptions): Boolean; static;
    /// <summary>Optionen für Read ohne Optionssatz; der Graph der bisherigen bleibt im Zwischenspeicher.</summary>
    procedure SetOptions(const AOptions: TUsesGraphOptions);
    function Options: TUsesGraphOptions;
    /// <summary>Gleicht den Graphen der Optionen von SetOptions mit dem Index ab und ruft AReader unter der
    /// Sperre auf.</summary>
    procedure Read(const AReader: TUsesGraphReader);
    /// <summary>Wie Read mit dem Graphen zu AOptions; ändert die Optionen von SetOptions nicht.</summary>
    function ReadWith(const AOptions: TUsesGraphOptions; const AReader: TUsesGraphReader): TUsesGraphRead;
    /// <summary>Wie ReadWith, wartet aber weder auf Aufbau noch auf Abgleich noch auf die Sperre: Kind Pending
    /// (AReader nicht gerufen) bzw. Stale (älterer Stand); der Hintergrund holt den Graphen nach.</summary>
    function TryRead(const AOptions: TUsesGraphOptions; const AReader: TUsesGraphReader): TUsesGraphRead;
    /// <summary>Wert zu AKey aus dem aktuellen Graphen: ADerive läuft unter der Sperre, je Schlüssel einmal bis
    /// zur nächsten Änderung des Graphen.</summary>
    function Derived(const AKey: string; const ADerive: TUsesGraphDerive): IInterface;
    /// <summary>Generation des Index, auf der der Graph der Optionen von SetOptions zuletzt stand; -1 ohne
    /// Graph.</summary>
    function Generation: Int64;
    /// <summary>Wie oft ein Graph ganz neu aufgebaut bzw. inkrementell abgeglichen wurde (für Tests und das
    /// Diagnoselog).</summary>
    function Rebuilds: Integer;
    function Updates: Integer;
    /// <summary>Optionssätze mit Graph im Zwischenspeicher.</summary>
    function Cached: Integer;
    /// <summary>Fehler des letzten gescheiterten Hintergrundlaufs ("Klasse: Meldung"), '' ohne.</summary>
    function WorkerError: string;
    /// <summary>Wartet, bis der Hintergrund nichts mehr zu tun hat (Tests).</summary>
    procedure WaitIdle;
  end;

implementation

type
  /// <summary>Baut bzw. gleicht im Hintergrund ab, bis nichts mehr gewünscht ist.</summary>
  TUsesGraphWorker = class(TThread)
  private
    FService: TUsesGraphService;
  protected
    procedure Execute; override;
  public
    constructor Create(AService: TUsesGraphService);
  end;

{ TUsesGraphRead }

function TUsesGraphRead.KindName: string;
const
  cNames: array[TUsesGraphReadKind] of string = ('current', 'updated', 'rebuilt', 'stale', 'pending');
begin
  Result := cNames[Kind];
end;

{ TUsesGraphService.TEntry }

constructor TUsesGraphService.TEntry.Create(const AOptions: TUsesGraphOptions; AGraph: TUsesGraph;
  AGeneration: Int64);
begin
  inherited Create;
  Options := AOptions;
  Graph := AGraph;
  Generation := AGeneration;
  Derived := TDictionary<string, IInterface>.Create(4);
end;

destructor TUsesGraphService.TEntry.Destroy;
begin
  Derived.Free;
  Graph.Free;
  inherited;
end;

{ TUsesGraphWorker }

constructor TUsesGraphWorker.Create(AService: TUsesGraphService);
begin
  FService := AService;
  inherited Create(False);
end;

procedure TUsesGraphWorker.Execute;
var
  mOptions: TUsesGraphOptions;
begin
  NameThreadForDebugging('Atlas.UsesGraph');
  try
    while FService.NextWanted(mOptions) do
    begin
      FService.Prepare(mOptions);
    end;
  except
    // Kein stiller Verlust: Der Dienst merkt sich den Fehler, das nächste TryRead liest selbst und bekommt ihn.
    on E: Exception do
      FService.WorkerFailed(E);
  end;
end;

{ TUsesGraphService }

constructor TUsesGraphService.Create(const AIndex: ISymbolIndex; const AOptions: TUsesGraphOptions;
  ACapacity: Integer);
begin
  inherited Create;
  FIndex := AIndex;
  FOptions := AOptions;
  FCapacity := ACapacity;
  if FCapacity < 1 then
  begin
    FCapacity := 1;
  end;
  FLock := TObject.Create;
  FEntries := TObjectList<TEntry>.Create(True);
  FWanted := TList<TUsesGraphOptions>.Create;
end;

destructor TUsesGraphService.Destroy;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopping := True;
    FWanted.Clear;
  finally
    System.TMonitor.Exit(FLock);
  end;
  // Ein laufender Aufbau endet mit seiner aktuellen Unit-Liste; danach nimmt der Thread nichts Neues.
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FWanted.Free;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

class function TUsesGraphService.SameOptions(const A, B: TUsesGraphOptions): Boolean;
begin
  Result := (A.IncludeLibrary = B.IncludeLibrary) and SameText(A.Root, B.Root) and
    SameText(string.Join(#1, A.Exclude), string.Join(#1, B.Exclude)) and
    SameText(string.Join(#1, A.Namespaces), string.Join(#1, B.Namespaces));
end;

function TUsesGraphService.IndexOf(const AOptions: TUsesGraphOptions): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if SameOptions(FEntries[mIndex].Options, AOptions) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TUsesGraphService.Touch(AIndex: Integer);
begin
  if AIndex > 0 then
  begin
    FEntries.Move(AIndex, 0);
  end;
end;

procedure TUsesGraphService.Add(AEntry: TEntry);
begin
  FEntries.Insert(0, AEntry);
  while FEntries.Count > FCapacity do
  begin
    FEntries.Delete(FEntries.Count - 1);
  end;
end;

function TUsesGraphService.Current(AEntry: TEntry): Boolean;
begin
  Result := AEntry.Generation = FIndex.Generation;
end;

function TUsesGraphService.Refresh(AEntry: TEntry): TUsesGraphReadKind;
var
  mCurrent: Int64;
begin
  mCurrent := FIndex.Generation;
  if mCurrent = AEntry.Generation then
  begin
    Exit(TUsesGraphReadKind.Current);
  end;
  AEntry.Graph.Synchronize(FIndex.Units);
  Inc(FUpdates);
  AEntry.Generation := mCurrent;
  AEntry.Derived.Clear;
  Result := TUsesGraphReadKind.Updated;
end;

function TUsesGraphService.Entry(const AOptions: TUsesGraphOptions; out AKind: TUsesGraphReadKind): TEntry;
var
  mIndex: Integer;
  mGeneration: Int64;
begin
  mIndex := IndexOf(AOptions);
  if mIndex >= 0 then
  begin
    Touch(mIndex);
    Result := FEntries[0];
    AKind := Refresh(Result);
    Exit;
  end;
  // Platz vor dem Aufbau schaffen: Zwei große Graphen zugleich braucht es hier nicht.
  while FEntries.Count >= FCapacity do
  begin
    FEntries.Delete(FEntries.Count - 1);
  end;
  mGeneration := FIndex.Generation;
  Result := TEntry.Create(AOptions, TUsesGraph.Create(FIndex.Units, AOptions), mGeneration);
  Inc(FRebuilds);
  Add(Result);
  AKind := TUsesGraphReadKind.Rebuilt;
end;

procedure TUsesGraphService.SetOptions(const AOptions: TUsesGraphOptions);
begin
  System.TMonitor.Enter(FLock);
  try
    FOptions := AOptions;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Options: TUsesGraphOptions;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FOptions;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TUsesGraphService.Read(const AReader: TUsesGraphReader);
var
  mKind: TUsesGraphReadKind;
begin
  System.TMonitor.Enter(FLock);
  try
    AReader(Entry(FOptions, mKind).Graph);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.ReadWith(const AOptions: TUsesGraphOptions;
  const AReader: TUsesGraphReader): TUsesGraphRead;
var
  mEntry: TEntry;
begin
  System.TMonitor.Enter(FLock);
  try
    mEntry := Entry(AOptions, Result.Kind);
    Result.Generation := mEntry.Generation;
    AReader(mEntry.Graph);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.TryRead(const AOptions: TUsesGraphOptions;
  const AReader: TUsesGraphReader): TUsesGraphRead;
var
  mIndex: Integer;
  mEntry: TEntry;
  mFailed: Boolean;
begin
  Result.Kind := TUsesGraphReadKind.Pending;
  Result.Generation := -1;
  if not System.TMonitor.TryEnter(FLock) then
  begin
    // Ein anderer baut oder gleicht gerade ab; nicht dahinter warten.
    Exit;
  end;
  try
    mFailed := FWorkerFailed;
    FWorkerFailed := False;
    mIndex := IndexOf(AOptions);
    if mFailed then
    begin
      // Der Hintergrund scheiterte: selbst lesen, damit der Fehler beim Aufrufer ankommt.
      mEntry := Entry(AOptions, Result.Kind);
    end
    else if mIndex < 0 then
    begin
      Want(AOptions);
      Exit;
    end
    else
    begin
      Touch(mIndex);
      mEntry := FEntries[0];
      Result.Kind := TUsesGraphReadKind.Current;
      if not Current(mEntry) then
      begin
        Want(AOptions);
        Result.Kind := TUsesGraphReadKind.Stale;
      end;
    end;
    Result.Generation := mEntry.Generation;
    AReader(mEntry.Graph);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TUsesGraphService.Want(const AOptions: TUsesGraphOptions);
var
  mOptions: TUsesGraphOptions;
begin
  // Unter der Sperre.
  if FStopping then
  begin
    Exit;
  end;
  for mOptions in FWanted do
  begin
    if SameOptions(mOptions, AOptions) then
    begin
      Exit;
    end;
  end;
  FWanted.Add(AOptions);
  if FWorkerBusy then
  begin
    Exit;
  end;
  if FWorker <> nil then
  begin
    // Fertig (FWorkerBusy ist aus): kehrt sofort zurück.
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FWorkerBusy := True;
  FWorker := TUsesGraphWorker.Create(Self);
end;

function TUsesGraphService.NextWanted(out AOptions: TUsesGraphOptions): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := not FStopping and (FWanted.Count > 0);
    if Result then
    begin
      AOptions := FWanted[0];
      FWanted.Delete(0);
    end
    else
    begin
      FWanted.Clear;
      FWorkerBusy := False;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TUsesGraphService.Prepare(const AOptions: TUsesGraphOptions);
var
  mIndex: Integer;
  mGeneration: Int64;
  mGraph: TUsesGraph;
begin
  System.TMonitor.Enter(FLock);
  try
    mIndex := IndexOf(AOptions);
    if mIndex >= 0 then
    begin
      // Abgleich ändert den Graphen, den Leser sehen: unter der Sperre.
      Refresh(FEntries[mIndex]);
      Exit;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  // Neuer Graph ohne Sperre: Leser anderer Optionssätze warten nicht auf den Aufbau.
  mGeneration := FIndex.Generation;
  mGraph := TUsesGraph.Create(FIndex.Units, AOptions);
  System.TMonitor.Enter(FLock);
  try
    if FStopping or (IndexOf(AOptions) >= 0) then
    begin
      mGraph.Free;
      Exit;
    end;
    Inc(FRebuilds);
    Add(TEntry.Create(AOptions, mGraph, mGeneration));
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TUsesGraphService.WorkerFailed(const AError: Exception);
begin
  System.TMonitor.Enter(FLock);
  try
    FWorkerFailed := True;
    FWorkerError := AError.ClassName + ': ' + AError.Message;
    // Der Thread endet: Was noch gewünscht war, holt das nächste TryRead selbst.
    FWanted.Clear;
    FWorkerBusy := False;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Derived(const AKey: string; const ADerive: TUsesGraphDerive): IInterface;
var
  mEntry: TEntry;
  mKind: TUsesGraphReadKind;
begin
  System.TMonitor.Enter(FLock);
  try
    mEntry := Entry(FOptions, mKind);
    if not mEntry.Derived.TryGetValue(AKey, Result) then
    begin
      Result := ADerive(mEntry.Graph);
      mEntry.Derived.Add(AKey, Result);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Generation: Int64;
var
  mIndex: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := -1;
    mIndex := IndexOf(FOptions);
    if mIndex >= 0 then
    begin
      Result := FEntries[mIndex].Generation;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Rebuilds: Integer;
begin
  Result := FRebuilds;
end;

function TUsesGraphService.Updates: Integer;
begin
  Result := FUpdates;
end;

function TUsesGraphService.WorkerError: string;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FWorkerError;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Cached: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FEntries.Count;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TUsesGraphService.WaitIdle;
var
  mBusy: Boolean;
begin
  repeat
    System.TMonitor.Enter(FLock);
    try
      mBusy := FWorkerBusy;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if mBusy then
    begin
      TThread.Sleep(5);
    end;
  until not mBusy;
end;

end.
