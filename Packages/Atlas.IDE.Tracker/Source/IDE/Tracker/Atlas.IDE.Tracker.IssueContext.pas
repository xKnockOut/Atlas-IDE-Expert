unit Atlas.IDE.Tracker.IssueContext;

// Gemeinsamer Stand der Teile des Fensters „Atlas-Issue“ (#1264): Anbieter und
// Transport aus den Hooks, Zwischenspeicher, gezeigtes Issue, Generation der
// Abfragen, zuletzt geöffnete Issues (#1270) und die Hintergrundthreads, die
// beim Anhalten abgewartet werden. TAtlasIdeIssuePreview legt ihn an und gibt
// ihn den Teilen (Kurzabfrage, Checklisten, Verknüpfungen, Bilder, Kommentar).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.IssueCache,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  TAtlasIssuePreviewProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Läuft im Hintergrund.</summary>
  TAtlasIssuePreviewTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;

  TAtlasIdeIssueContext = class
  private
    FOwner: TInterfacedObject;
    FProvider: TAtlasIssuePreviewProviderHook;
    FTransport: TAtlasIssuePreviewTransportHook;
    FCache: TAtlasTrackerIssueCache;
    FWorkers: TAtlasWorkerSlot;
    FStarted: Boolean;
    FCurrent: TAtlasIssueHistoryEntry;
    FHasCurrent: Boolean;
    FGeneration: Integer;
    FRecent: TAtlasRecentIssues;
    FRecentFile: string;
  public
    /// <summary>AOwner hält die Teile; Keep liefert ihn für Rückrufe. ACacheFolder: Ordner des Zwischenspeichers
    /// ('' = nur im Speicher).</summary>
    constructor Create(AOwner: TInterfacedObject; const AProvider: TAtlasIssuePreviewProviderHook;
      const ATransport: TAtlasIssuePreviewTransportHook; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Hält den Besitzer am Leben, solange ein Rückruf ihn fängt.</summary>
    function Keep: IInterface;
    /// <summary>Frame, falls das Fenster existiert.</summary>
    function Frame: TAtlasIssueFrame;
    function ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    /// <summary>Es gibt einen Transport-Hook.</summary>
    function CanTransport: Boolean;
    /// <summary>Transport für AProvider und ATarget; nil ohne Hook oder ohne Token.</summary>
    function TransportOf(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
    class function NowUtc: TDateTime; static;
    /// <summary>Ergebnis eines Abrufs fürs Log: "geladen" oder "nicht geladen (Fehlerkennung)".</summary>
    class function LoadState(ASucceeded: Boolean; AError: TAtlasCiFetchError): string; static;
    /// <summary>Angemeldet: alten Zwischenspeicher aufräumen, zuletzt geöffnete laden.</summary>
    procedure Start;
    /// <summary>Abgemeldet: neue Generation, keine Hooks mehr.</summary>
    procedure Stop;
    /// <summary>AEntry ist jetzt das gezeigte Issue; liefert die neue Generation.</summary>
    function Select(const AEntry: TAtlasIssueHistoryEntry): Integer;
    /// <summary>AThread (nicht gestartet) merken und starten; ReleaseThreads gibt ihn frei.</summary>
    procedure Run(AThread: TThread);
    /// <summary>Einen eigenen Thread zum Aufräumen übergeben (nil = nichts).</summary>
    procedure Retire(AThread: TThread);
    /// <summary>Beendete Threads freigeben; AWait: auf alle warten (Anhalten).</summary>
    procedure ReleaseThreads(AWait: Boolean);
    /// <summary>AIssue zuerst unter „zuletzt geöffnet“ und speichern.</summary>
    procedure Remember(const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue);
    function RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
    property Cache: TAtlasTrackerIssueCache read FCache;
    property Started: Boolean read FStarted;
    property Current: TAtlasIssueHistoryEntry read FCurrent;
    property HasCurrent: Boolean read FHasCurrent;
    property Generation: Integer read FGeneration;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Tracker.IssueWindow;

constructor TAtlasIdeIssueContext.Create(AOwner: TInterfacedObject; const AProvider: TAtlasIssuePreviewProviderHook;
  const ATransport: TAtlasIssuePreviewTransportHook; const ACacheFolder: string);
begin
  inherited Create;
  FOwner := AOwner;
  FProvider := AProvider;
  FTransport := ATransport;
  FCache := TAtlasTrackerIssueCache.Create(ACacheFolder);
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
  FRecent := TAtlasRecentIssues.Create;
  if ACacheFolder <> '' then
  begin
    FRecentFile := TPath.Combine(ACacheFolder, 'recent.json');
  end;
end;

destructor TAtlasIdeIssueContext.Destroy;
begin
  FWorkers.Free;
  FRecent.Free;
  FCache.Free;
  inherited;
end;

function TAtlasIdeIssueContext.Keep: IInterface;
begin
  Result := FOwner;
end;

function TAtlasIdeIssueContext.Frame: TAtlasIssueFrame;
begin
  Result := TAtlasIdeIssueWindow.ExistingFrame;
end;

function TAtlasIdeIssueContext.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FProvider) then
  begin
    Result := FProvider(ATarget.Provider);
  end;
end;

function TAtlasIdeIssueContext.CanTransport: Boolean;
begin
  Result := Assigned(FTransport);
end;

function TAtlasIdeIssueContext.TransportOf(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
begin
  Result := nil;
  if Assigned(FTransport) and (AProvider <> nil) then
  begin
    Result := FTransport(AProvider, ATarget);
  end;
end;

class function TAtlasIdeIssueContext.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeIssueContext.LoadState(ASucceeded: Boolean; AError: TAtlasCiFetchError): string;
begin
  Result := 'geladen';
  if not ASucceeded then
  begin
    Result := 'nicht geladen (' + TAtlasCiBuild.ErrorKey(AError) + ')';
  end;
end;

procedure TAtlasIdeIssueContext.Start;
begin
  FStarted := True;
  FCache.Prune(NowUtc);
  // Fehlt, unbrauchbar oder gesperrt: leer anfangen (TAtlasDataFile protokolliert).
  if FRecentFile <> '' then
  begin
    FRecent.LoadFromFile(FRecentFile);
  end;
end;

procedure TAtlasIdeIssueContext.Stop;
begin
  FStarted := False;
  Inc(FGeneration);
  FProvider := nil;
  FTransport := nil;
end;

function TAtlasIdeIssueContext.Select(const AEntry: TAtlasIssueHistoryEntry): Integer;
begin
  FCurrent := AEntry;
  FHasCurrent := True;
  Inc(FGeneration);
  Result := FGeneration;
end;

procedure TAtlasIdeIssueContext.Run(AThread: TThread);
begin
  FWorkers.Start(AThread);
end;

procedure TAtlasIdeIssueContext.Retire(AThread: TThread);
begin
  FWorkers.Keep(AThread);
end;

procedure TAtlasIdeIssueContext.ReleaseThreads(AWait: Boolean);
begin
  FWorkers.Release(AWait);
end;

procedure TAtlasIdeIssueContext.Remember(const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue);
begin
  FRecent.Add(ATarget, AIssue);
  if FRecentFile = '' then
  begin
    Exit;
  end;
  try
    FRecent.SaveToFile(FRecentFile);
  except
    // Die Liste bleibt im Speicher; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(FRecent.Kind, E);
  end;
end;

function TAtlasIdeIssueContext.RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
begin
  Result := FRecent.Items(ATarget);
end;

end.
