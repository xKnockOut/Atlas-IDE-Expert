unit Atlas.Plugin.Lsp.BackgroundRequest;

// Eine Serveranfrage im Hintergrund statt im Hauptthread (2.0-stable: Inlay-Hints, Glühbirne, Überschreibungen
// und Gliederung warteten im Hauptthread bis zum Zeitlimit; bei beschäftigtem Server hing die IDE alle paar Sekunden
// 600 bis 800 ms und keine Antwort kam je an).
// - Start: AWork läuft in einem eigenen Thread, danach ADone im Hauptthread (über TAtlasMainThread). Es läuft
//   höchstens eine Anfrage je Instanz; solange sie läuft, ist Busy wahr, und der Aufrufer fragt nicht erneut.
// - Lebensdauer: ADone läuft nur, solange die Instanz lebt. Der Destruktor wartet die laufende Anfrage ab (sie
//   endet spätestens mit ihrem Zeitlimit oder beim Abbruchsignal des Entladens) und verwirft ein noch eingereihtes
//   ADone.
// - Keine Antwort (ELspClientError: Zeitgrenze, Abbruch, veralteter Stand, begründete Ablehnung, beendete
//   Verbindung) fängt die Anfrage selbst und meldet sie ADone mit AOk = False und der Meldung, ohne Fehlerbericht;
//   der Aufrufer fragt dann später erneut. Eine Fehlerantwort, die auf einen Fehler im Server deutet
//   (ELspResponseError), und alle anderen Ausnahmen meldet die Sicherung für AFeature im Hauptthread; ADone läuft
//   auch dann (AOk = False, bei der Fehlerantwort mit ihrer Meldung).
// Start, Busy und der Destruktor nur im Hauptthread.
// TAtlasBackgroundQueue reiht mehrere Anfragen hintereinander über eine TAtlasBackgroundRequest (etwa Befehle des
// Ergebnisfensters und das Aufklappen ihrer Bäume): Add hängt an, AddLatest ersetzt wartende AddLatest-Aufträge, und
// das Ergebnis eines laufenden verfällt, sobald ein neuerer AddLatest-Auftrag kommt (der jüngste Befehl zählt).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.WorkerSlot;

type
  /// <summary>Abschluss im Hauptthread: AOk, wenn AWork ohne Ausnahme endete; sonst AError mit der Meldung.</summary>
  TAtlasRequestDone = reference to procedure(AOk: Boolean; const AError: string);

  /// <summary>Gilt, solange die Instanz lebt; eingereihte Abschlüsse prüfen es im Hauptthread.</summary>
  IAtlasRequestAlive = interface
    ['{6B8E2D4A-3F1C-4E7B-9A5D-2C8F1E6B4A93}']
    function Alive: Boolean;
    procedure Kill;
  end;

  TAtlasBackgroundRequest = class
  private
    FFeature: TAtlasFeature;
    FAlive: IAtlasRequestAlive;
    FWorkers: TAtlasWorkerSlot;
    FBusy: Boolean;
  public
    constructor Create(AFeature: TAtlasFeature);
    destructor Destroy; override;
    /// <summary>AWork im Hintergrund, danach ADone im Hauptthread; False, solange noch eine Anfrage läuft.</summary>
    function Start(const AWork: TProc; const ADone: TAtlasRequestDone): Boolean;
    /// <summary>Läuft gerade eine Anfrage?</summary>
    function Busy: Boolean;
  end;

  TAtlasBackgroundQueue = class
  private type
    TJob = record
      Work: TProc;
      Done: TAtlasRequestDone;
      /// <summary>Laufende Nummer eines AddLatest-Auftrags; 0 bei Add.</summary>
      Latest: Integer;
    end;
  private
    FRequest: TAtlasBackgroundRequest;
    FJobs: TArray<TJob>;
    FLatest: Integer;
    procedure Next;
    procedure Finished(const AJob: TJob; AOk: Boolean; const AError: string);
  public
    constructor Create(AFeature: TAtlasFeature);
    /// <summary>Wartet die laufende Anfrage ab; wartende und ihr Abschluss verfallen.</summary>
    destructor Destroy; override;
    /// <summary>AWork nach den wartenden im Hintergrund, danach ADone im Hauptthread.</summary>
    procedure Add(const AWork: TProc; const ADone: TAtlasRequestDone);
    /// <summary>Wie Add, ersetzt aber wartende AddLatest-Aufträge; ein laufender bekommt keinen Abschluss mehr.
    /// </summary>
    procedure AddLatest(const AWork: TProc; const ADone: TAtlasRequestDone);
    /// <summary>Wartende Aufträge (ohne den laufenden).</summary>
    function Waiting: Integer;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.MainThread,
  Atlas.Plugin.Lsp.Client;

type
  TRequestAlive = class(TInterfacedObject, IAtlasRequestAlive)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function Alive: Boolean;
    procedure Kill;
  end;

{ TRequestAlive }

constructor TRequestAlive.Create;
begin
  inherited Create;
  FAlive := True;
end;

function TRequestAlive.Alive: Boolean;
begin
  Result := FAlive;
end;

procedure TRequestAlive.Kill;
begin
  FAlive := False;
end;

{ TAtlasBackgroundRequest }

constructor TAtlasBackgroundRequest.Create(AFeature: TAtlasFeature);
begin
  inherited Create;
  FFeature := AFeature;
  FAlive := TRequestAlive.Create;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasBackgroundRequest.Destroy;
begin
  FAlive.Kill;
  if FWorkers <> nil then
  begin
    FWorkers.Stop(TAtlasWorkerSlot.cWaitForever);
  end;
  FreeAndNil(FWorkers);
  inherited;
end;

function TAtlasBackgroundRequest.Busy: Boolean;
begin
  Result := FBusy;
end;

/// <summary>Abschluss im Hauptthread: Busy zurücksetzen und ADone, solange die Instanz lebt.</summary>
function Finish(ARequest: TAtlasBackgroundRequest; const AAlive: IAtlasRequestAlive; const ADone: TAtlasRequestDone;
  const AError: string; AFailure: Exception): TThreadProcedure;
begin
  Result :=
    procedure
    begin
      try
        if not AAlive.Alive then
        begin
          Exit;
        end;
        if AFailure <> nil then
        begin
          TAtlasGuard.Report(ARequest.FFeature, AFailure);
        end;
        ARequest.FBusy := False;
        ADone((AError = '') and (AFailure = nil), AError);
      finally
        AFailure.Free;
      end;
    end;
end;

/// <summary>Arbeit des Threads: AWork, dann den Abschluss einreihen.</summary>
function Work(ARequest: TAtlasBackgroundRequest; const AWork: TProc; const ADone: TAtlasRequestDone): TProc;
var
  mFeature: TAtlasFeature;
  mAlive: IAtlasRequestAlive;
begin
  // Im Hauptthread gelesen; der Thread fasst die Instanz nicht an.
  mFeature := ARequest.FFeature;
  mAlive := ARequest.FAlive;
  Result :=
    procedure
    var
      mError: string;
      mFailure: Exception;
    begin
      mError := '';
      mFailure := nil;
      try
        AWork();
      except
        on E: ELspResponseError do
        begin
          // Ein Fehler im Server: ins Fehlerprotokoll, ADone bekommt trotzdem die Meldung.
          mError := E.Message;
          if mError = '' then
          begin
            mError := E.ClassName;
          end;
          mFailure := Exception(AcquireExceptionObject);
        end;
        on E: ELspClientError do
        begin
          // Leer hieße Erfolg: eine Meldung ohne Text bekommt die Klasse.
          mError := E.Message;
          if mError = '' then
          begin
            mError := E.ClassName;
          end;
        end;
        on EAbort do
        begin
          // Wie TAtlasMainThread: stiller Abbruch, keine Meldung.
          mError := 'EAbort';
        end;
        on Exception do
        begin
          mFailure := Exception(AcquireExceptionObject);
        end;
      end;
      TAtlasMainThread.Queue(mFeature, Finish(ARequest, mAlive, ADone, mError, mFailure));
    end;
end;

{ TAtlasBackgroundQueue }

constructor TAtlasBackgroundQueue.Create(AFeature: TAtlasFeature);
begin
  inherited Create;
  FRequest := TAtlasBackgroundRequest.Create(AFeature);
end;

destructor TAtlasBackgroundQueue.Destroy;
begin
  FJobs := nil;
  FreeAndNil(FRequest);
  inherited;
end;

function TAtlasBackgroundQueue.Waiting: Integer;
begin
  Result := Length(FJobs);
end;

procedure TAtlasBackgroundQueue.Add(const AWork: TProc; const ADone: TAtlasRequestDone);
var
  mJob: TJob;
begin
  mJob.Work := AWork;
  mJob.Done := ADone;
  mJob.Latest := 0;
  FJobs := FJobs + [mJob];
  Next;
end;

procedure TAtlasBackgroundQueue.AddLatest(const AWork: TProc; const ADone: TAtlasRequestDone);
var
  mJob: TJob;
  mIndex: Integer;
begin
  for mIndex := High(FJobs) downto 0 do
  begin
    if FJobs[mIndex].Latest > 0 then
    begin
      Delete(FJobs, mIndex, 1);
    end;
  end;
  Inc(FLatest);
  mJob.Work := AWork;
  mJob.Done := ADone;
  mJob.Latest := FLatest;
  FJobs := FJobs + [mJob];
  Next;
end;

/// <summary>Abschluss eines Auftrags: AQueue.Finished im Hauptthread.</summary>
function JobDone(AQueue: TAtlasBackgroundQueue; const AJob: TAtlasBackgroundQueue.TJob): TAtlasRequestDone;
begin
  Result :=
    procedure(AOk: Boolean; const AError: string)
    begin
      AQueue.Finished(AJob, AOk, AError);
    end;
end;

procedure TAtlasBackgroundQueue.Next;
var
  mJob: TJob;
begin
  if FRequest.Busy or (Length(FJobs) = 0) then
  begin
    Exit;
  end;
  mJob := FJobs[0];
  Delete(FJobs, 0, 1);
  // Der Abschluss läuft nur, solange FRequest lebt; es gehört der Schlange.
  FRequest.Start(mJob.Work, JobDone(Self, mJob));
end;

procedure TAtlasBackgroundQueue.Finished(const AJob: TJob; AOk: Boolean; const AError: string);
begin
  try
    // Ein neuerer AddLatest-Auftrag ersetzt das Ergebnis eines älteren.
    if (AJob.Latest = 0) or (AJob.Latest = FLatest) then
    begin
      AJob.Done(AOk, AError);
    end;
  finally
    Next;
  end;
end;

function TAtlasBackgroundRequest.Start(const AWork: TProc; const ADone: TAtlasRequestDone): Boolean;
begin
  Result := not FBusy;
  if not Result then
  begin
    Exit;
  end;
  // Der Thread der vorigen Anfrage steht höchstens noch in seinen letzten Anweisungen; Start gibt ihn frei,
  // sobald er beendet ist.
  FBusy := True;
  FWorkers.Start(TThread.CreateAnonymousThread(Work(Self, AWork, ADone)));
end;

end.
