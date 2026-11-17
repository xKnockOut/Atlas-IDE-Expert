unit Atlas.IDE.Tracker.PaletteSearchFetch;

// Abfrage der Issue-Suche in der Befehlspalette (#1270) beim Tracker. Die
// Anzeige in der Palette steht in Atlas.IDE.Tracker.PaletteSearch.
// - Entprellt um 300 ms (TAtlasIssueSearchDebounce, Zeitgeber der IDE).
// - Eine Anfrage zur Zeit im Hintergrund; eine neue Eingabe bricht die
//   laufende ab (IAtlasCiCancel), Zeitgrenze 5 s. Die Antwort kommt über
//   TAtlasMainThread zurück und zählt nur, solange keine neuere Eingabe kam.
// - Die letzte Antwort bleibt bis zum nächsten Öffnen: dieselbe Eingabe noch
//   einmal (Rücktaste und neu getippt) braucht kein Netz.
// - Protokoll anonym: Anbieter, Anzahl und Fehlerart, nie Suchtext, Kennung
//   oder Adresse.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.PaletteSearchPlan,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  /// <summary>Antwort auf die aktuelle Anfrage; AAnswer sagt, was damit geschieht.</summary>
  TAtlasIssueSearchAnswered = reference to procedure(const AQuery: TAtlasIssueSearchQuery;
    AAnswer: TAtlasIssueSearchAnswer; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);

  TAtlasIdeIssueSearchFetch = class(TInterfacedObject)
  private type
    /// <summary>Eine Anfrage, wie sie in den Hintergrund geht.</summary>
    TSearchJob = record
      Generation: Integer;
      Query: TAtlasIssueSearchQuery;
      Provider: IAtlasTrackerProvider;
      Target: TAtlasTrackerTarget;
      Transport: IAtlasCiTransport;
    end;
  private
    FTransport: TAtlasIssuePreviewTransportHook;
    FAnswered: TAtlasIssueSearchAnswered;
    FStarted: Boolean;
    FOpen: Boolean;
    FDebounce: TAtlasIssueSearchDebounce;
    FTimer: TTimer;
    FTarget: TAtlasTrackerTarget;
    FProvider: IAtlasTrackerProvider;
    FQuery: TAtlasIssueSearchQuery;
    FLastQuery: TAtlasIssueSearchQuery;
    FLastIssues: TArray<TAtlasTrackerIssue>;
    FHasLast: Boolean;
    FCancel: IAtlasCiCancel;
    FGeneration: Integer;
    FWorkers: TAtlasWorkerSlot;
    procedure TimerTick(Sender: TObject);
    procedure Schedule;
    procedure Request(const AQuery: TAtlasIssueSearchQuery);
    /// <summary>Arbeit des Hintergrundthreads; die Antwort geht über den Hauptthread an Answered, solange AKeep
    /// das Objekt hält.</summary>
    function Worker(const AKeep: IInterface; const AJob: TSearchJob): TProc;
    procedure Answered(AGeneration: Integer; const AQuery: TAtlasIssueSearchQuery; ASucceeded: Boolean;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
    procedure CancelRequest;
    class function NowMs: UInt64; static;
  public
    /// <summary>ATransport: Transport mit dem Token aus dem Anmeldespeicher, ohne Dialog; AAnswered bekommt die
    /// Antworten im Hauptthread.</summary>
    constructor Create(const ATransport: TAtlasIssuePreviewTransportHook; const AAnswered: TAtlasIssueSearchAnswered);
    destructor Destroy; override;
    /// <summary>Palette geöffnet: Tracker AProvider (nil = keiner) bei ATarget; vergisst die letzte Antwort.
    /// </summary>
    procedure Open(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget);
    /// <summary>Wartende und laufende Anfrage verwerfen (jede neue Eingabe).</summary>
    procedure Cancel;
    /// <summary>AQuery nach der Wartezeit abfragen.</summary>
    procedure Search(const AQuery: TAtlasIssueSearchQuery);
    /// <summary>Antwort auf dieselbe Anfrage seit dem Öffnen; False ohne.</summary>
    function Last(const AQuery: TAtlasIssueSearchQuery; out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
    /// <summary>Palette geschlossen: nichts mehr abfragen, keine Antwort mehr melden.</summary>
    procedure Close;
    /// <summary>Abbrechen, kurz auf Anfragen warten, Rückrufe lösen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Tracker seit dem letzten Öffnen; nil ohne.</summary>
    property Provider: IAtlasTrackerProvider read FProvider;
    property Target: TAtlasTrackerTarget read FTarget;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown;

/// <summary>Issue zur Kennung bzw. Suche nach Text; False mit AError.</summary>
function FetchIssues(const AJob: TAtlasIdeIssueSearchFetch.TSearchJob; out AIssues: TArray<TAtlasTrackerIssue>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  AIssues := nil;
  if AJob.Query.Kind <> TAtlasIssueSearchKind.Key then
  begin
    Exit(AJob.Provider.Search(TAtlasTrackerCall.Create(AJob.Target, AJob.Transport,
      TAtlasIssuePaletteSearch.cTimeoutMs), AJob.Query.Text, TAtlasIssuePaletteSearch.cMaxResults, AIssues, AError));
  end;
  Result := AJob.Provider.Lookup(AJob.Target, AJob.Transport, AJob.Query.Key, TAtlasIssuePaletteSearch.cTimeoutMs,
    mIssue, AError);
  if Result then
  begin
    AIssues := [mIssue];
  end;
end;

{ TAtlasIdeIssueSearchFetch }

constructor TAtlasIdeIssueSearchFetch.Create(const ATransport: TAtlasIssuePreviewTransportHook;
  const AAnswered: TAtlasIssueSearchAnswered);
begin
  inherited Create;
  FTransport := ATransport;
  FAnswered := AAnswered;
  FStarted := True;
  FDebounce := TAtlasIssueSearchDebounce.Create(TAtlasIssuePaletteSearch.cDelayMs);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
  FQuery := TAtlasIssueSearchQuery.None;
  FLastQuery := TAtlasIssueSearchQuery.None;
end;

destructor TAtlasIdeIssueSearchFetch.Destroy;
begin
  Stop;
  FWorkers.Free;
  FTimer.Free;
  FDebounce.Free;
  inherited;
end;

class function TAtlasIdeIssueSearchFetch.NowMs: UInt64;
begin
  Result := GetTickCount64;
end;

procedure TAtlasIdeIssueSearchFetch.TimerTick(Sender: TObject);
var
  mText: string;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  if not FStarted or not FOpen then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      if FDebounce.Take(NowMs, mText) then
      begin
        Request(FQuery);
      end
      else
      begin
        Schedule;
      end;
    end);
end;

procedure TAtlasIdeIssueSearchFetch.Schedule;
var
  mWait: Integer;
begin
  if FTimer = nil then
  begin
    Exit;
  end;
  mWait := FDebounce.WaitMs(NowMs);
  FTimer.Enabled := False;
  if mWait < 0 then
  begin
    Exit;
  end;
  if mWait < 1 then
  begin
    mWait := 1;
  end;
  FTimer.Interval := Cardinal(mWait);
  FTimer.Enabled := True;
end;

function TAtlasIdeIssueSearchFetch.Worker(const AKeep: IInterface; const AJob: TSearchJob): TProc;
var
  mJob: TSearchJob;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueSearchFetch;
begin
  // Eigene Routine: Die anonyme Methode hält nur diese Werte.
  mJob := AJob;
  mKeep := AKeep;
  mOwner := Self;
  Result :=
    procedure
    var
      mIssues: TArray<TAtlasTrackerIssue>;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := FetchIssues(mJob, mIssues, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mIssues := nil;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Palettensuche: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Palette,
        procedure
        begin
          if mKeep <> nil then
          begin
            mOwner.Answered(mJob.Generation, mJob.Query, mOk, mIssues, mError);
          end;
        end);
    end;
end;

procedure TAtlasIdeIssueSearchFetch.Request(const AQuery: TAtlasIssueSearchQuery);
var
  mJob: TSearchJob;
begin
  FWorkers.Release(False);
  CancelRequest;
  mJob := Default(TSearchJob);
  mJob.Generation := FGeneration;
  mJob.Query := AQuery;
  mJob.Provider := FProvider;
  mJob.Target := FTarget;
  if (mJob.Provider = nil) or not Assigned(FTransport) then
  begin
    Answered(mJob.Generation, AQuery, False, nil, TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  // Der Transport entsteht hier, damit eine neue Eingabe ihn abbrechen kann; er liest das Token ohne Dialog.
  mJob.Transport := FTransport(mJob.Provider, mJob.Target);
  if mJob.Transport = nil then
  begin
    Answered(mJob.Generation, AQuery, False, nil, TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  if not Supports(mJob.Transport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  FWorkers.Start(TThread.CreateAnonymousThread(Worker(Self, mJob)));
end;

procedure TAtlasIdeIssueSearchFetch.Answered(AGeneration: Integer; const AQuery: TAtlasIssueSearchQuery;
  ASucceeded: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  mName: string;
  mAnswer: TAtlasIssueSearchAnswer;
begin
  FWorkers.Release(False);
  // Neuere Eingabe, abgebrochen oder Palette zu: diese Antwort zählt nicht.
  if not FStarted or (AGeneration <> FGeneration) or not FOpen then
  begin
    Exit;
  end;
  FCancel := nil;
  mName := '';
  if FProvider <> nil then
  begin
    mName := FProvider.Name;
  end;
  TAtlasGuard.Log(TAtlasIssuePaletteSearchPlan.AnswerLog(mName, ASucceeded, Length(AIssues), AError));
  mAnswer := TAtlasIssuePaletteSearchPlan.AnswerOf(ASucceeded, AError);
  if mAnswer = TAtlasIssueSearchAnswer.Show then
  begin
    FLastQuery := AQuery;
    FLastIssues := AIssues;
    FHasLast := True;
  end;
  if Assigned(FAnswered) then
  begin
    FAnswered(AQuery, mAnswer, AIssues, AError);
  end;
end;

procedure TAtlasIdeIssueSearchFetch.CancelRequest;
begin
  // Die Antwort einer abgebrochenen Anfrage zählt nicht mehr (Generation).
  Inc(FGeneration);
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
  FCancel := nil;
end;

procedure TAtlasIdeIssueSearchFetch.Open(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget);
begin
  FOpen := FStarted;
  FProvider := AProvider;
  FTarget := ATarget;
  FQuery := TAtlasIssueSearchQuery.None;
  FHasLast := False;
  FLastIssues := nil;
end;

procedure TAtlasIdeIssueSearchFetch.Cancel;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FDebounce.Clear;
  CancelRequest;
end;

procedure TAtlasIdeIssueSearchFetch.Search(const AQuery: TAtlasIssueSearchQuery);
begin
  FQuery := AQuery;
  FDebounce.Input(TAtlasIssuePaletteSearchPlan.InputKey(AQuery), NowMs);
  Schedule;
end;

function TAtlasIdeIssueSearchFetch.Last(const AQuery: TAtlasIssueSearchQuery;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
begin
  Result := FHasLast and AQuery.SameAs(FLastQuery);
  AIssues := nil;
  if Result then
  begin
    AIssues := FLastIssues;
  end;
end;

procedure TAtlasIdeIssueSearchFetch.Close;
begin
  FOpen := False;
  Cancel;
  FWorkers.Release(False);
end;

procedure TAtlasIdeIssueSearchFetch.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  FOpen := False;
  Inc(FGeneration);
  // Der Zeitgeber gehört dem Hauptthread; die letzte Referenz kann ein Hintergrund-Thread lösen.
  FreeAndNil(FTimer);
  FDebounce.Clear;
  CancelRequest;
  FWorkers.Release(True);
  FProvider := nil;
  FTransport := nil;
  FAnswered := nil;
end;

end.
