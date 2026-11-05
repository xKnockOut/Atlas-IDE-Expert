unit Atlas.Core.Lsp.BackgroundRequest;

// Eine Serveranfrage im Hintergrund statt im Hauptthread (2.0-stable: Inlay-Hints, Glühbirne, Überschreibungen
// und Gliederung warteten im Hauptthread bis zum Zeitlimit; bei beschäftigtem Server hing die IDE alle paar Sekunden
// 600 bis 800 ms und keine Antwort kam je an).
// - Start: AWork läuft in einem eigenen Thread, danach ADone im Hauptthread (über TAtlasMainThread). Es läuft
//   höchstens eine Anfrage je Instanz; solange sie läuft, ist Busy wahr, und der Aufrufer fragt nicht erneut.
// - Lebensdauer: ADone läuft nur, solange die Instanz lebt. Der Destruktor wartet die laufende Anfrage ab (sie
//   endet spätestens mit ihrem Zeitlimit oder beim Abbruchsignal des Entladens) und verwirft ein noch eingereihtes
//   ADone.
// - Ausnahmen in AWork fängt der Aufrufer selbst; was durchrutscht, meldet die Sicherung für AFeature.
// Start, Busy und der Destruktor nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Diagnostics.Guard;

type
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
    function Start(const AWork: TProc; const ADone: TProc): Boolean;
    /// <summary>Läuft gerade eine Anfrage?</summary>
    function Busy: Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread;

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
function Finish(ARequest: TAtlasBackgroundRequest; const AAlive: IAtlasRequestAlive;
  const ADone: TProc): TThreadProcedure;
begin
  Result :=
    procedure
    begin
      if not AAlive.Alive then
      begin
        Exit;
      end;
      ARequest.FBusy := False;
      ADone();
    end;
end;

/// <summary>Arbeit des Threads: AWork, dann den Abschluss einreihen.</summary>
function Work(AFeature: TAtlasFeature; const AWork: TProc; const AFinish: TThreadProcedure): TProc;
begin
  Result :=
    procedure
    begin
      try
        AWork();
      finally
        TAtlasMainThread.Queue(AFeature, AFinish);
      end;
    end;
end;

function TAtlasBackgroundRequest.Start(const AWork: TProc; const ADone: TProc): Boolean;
begin
  Result := not FBusy;
  if not Result then
  begin
    Exit;
  end;
  Reap;
  FBusy := True;
  FWorker := TThread.CreateAnonymousThread(Work(FFeature, AWork, Finish(Self, FAlive, ADone)));
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

end.
