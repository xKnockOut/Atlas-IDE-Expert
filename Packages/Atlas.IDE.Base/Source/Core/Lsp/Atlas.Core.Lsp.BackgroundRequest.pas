unit Atlas.Core.Lsp.BackgroundRequest;

// Eine Serveranfrage im Hintergrund statt im Hauptthread (2.0-stable: Inlay-Hints, Glühbirne, Überschreibungen
// und Gliederung warteten im Hauptthread bis zum Zeitlimit; bei beschäftigtem Server hing die IDE alle paar Sekunden
// 600 bis 800 ms und keine Antwort kam je an).
// - Start: AWork läuft in einem eigenen Thread, danach ADone im Hauptthread (über TAtlasMainThread). Es läuft
//   höchstens eine Anfrage je Instanz; solange sie läuft, ist Busy wahr, und der Aufrufer fragt nicht erneut.
// - Lebensdauer: ADone läuft nur, solange die Instanz lebt. Der Destruktor wartet die laufende Anfrage ab (sie
//   endet spätestens mit ihrem Zeitlimit oder beim Abbruchsignal des Entladens) und verwirft ein noch eingereihtes
//   ADone.
// - Keine Antwort (ELspClientError: Zeitgrenze, Fehlerantwort, beendete Verbindung) fängt die Anfrage selbst und
//   meldet sie ADone mit AOk = False und der Meldung; der Aufrufer fragt dann später erneut. Andere Ausnahmen
//   meldet die Sicherung für AFeature im Hauptthread; ADone läuft auch dann (AOk = False).
// Start, Busy und der Destruktor nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Diagnostics.Guard;

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
    FWorker: TThread;
    FBusy: Boolean;
    /// <summary>Thread der vorigen, abgeschlossenen Anfrage freigeben.</summary>
    procedure Reap;
  public
    constructor Create(AFeature: TAtlasFeature);
    destructor Destroy; override;
    /// <summary>AWork im Hintergrund, danach ADone im Hauptthread; False, solange noch eine Anfrage läuft.</summary>
    function Start(const AWork: TProc; const ADone: TAtlasRequestDone): Boolean;
    /// <summary>Läuft gerade eine Anfrage?</summary>
    function Busy: Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Client;

type
  TRequestAlive = class(TInterfacedObject, IAtlasRequestAlive)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function Alive: Boolean;
    procedure Kill;
  end;

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
end;

destructor TAtlasBackgroundRequest.Destroy;
begin
  FAlive.Kill;
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  inherited;
end;

procedure TAtlasBackgroundRequest.Reap;
begin
  // Der Abschluss ist schon gelaufen; der Thread steht höchstens noch in seinen letzten Anweisungen.
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FWorker.Free;
    FWorker := nil;
  end;
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

function TAtlasBackgroundRequest.Start(const AWork: TProc; const ADone: TAtlasRequestDone): Boolean;
begin
  Result := not FBusy;
  if not Result then
  begin
    Exit;
  end;
  Reap;
  FBusy := True;
  FWorker := TThread.CreateAnonymousThread(Work(Self, AWork, ADone));
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

end.
