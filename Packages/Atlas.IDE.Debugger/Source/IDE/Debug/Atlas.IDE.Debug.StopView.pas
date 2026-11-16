unit Atlas.IDE.Debug.StopView;

// Gemeinsame Basis der Debugger-Anzeigen, die auf die Debug-Sitzung hören (Werte im Editor, „Warum bin ich hier?“,
// Variablen, Auswerten, Pins, Baum im Hover):
//   - Zuhörer: Listen meldet die Anzeige bei TAtlasIdeDebugSession an; Start, Halt, Fortsetzen und Ende gehen an
//     die virtuellen Methoden SessionStarted, SessionStopped, SessionResumed und SessionEnded. Vor dem Abbau
//     (BeforeDestruction) meldet die Basis den Zuhörer ab und trennt ihn von der Anzeige; ein Ereignis, das danach
//     noch ankommt, erreicht sie nicht mehr.
//   - Takt (optional, CreateTimer): ein TTimer, dessen Ereignis unter der Sicherung des Features Debugger läuft;
//     ist das Feature aus oder wirft ein Schritt, hält der Takt an. Den Schritt bestimmt Advance, von Haus aus
//     TAtlasStopProgress.Next: Ausführungspunkt lesen (ReadLocation, dann Ask), ein Stück auswerten
//     (EvaluateSlice) oder anhalten.
// Nur im Hauptthread verwenden.

interface

uses
  Vcl.ExtCtrls,
  Atlas.Core.Debug.StopProgress,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeDebugStopView = class abstract
  private type
    TListener = class(TAtlasIdeDebugListener)
    private
      FView: TAtlasIdeDebugStopView;
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
  private
    FListener: TListener;
    FListenerRef: IAtlasIdeDebugListener;
    procedure Tick(Sender: TObject);
    procedure Unlisten;
  protected
    /// <summary>Takt der Anzeige; nil ohne CreateTimer. Gibt die Basis frei.</summary>
    FTimer: TTimer;
    /// <summary>Ablauf des jüngsten Halts.</summary>
    FProgress: TAtlasStopProgress;
    /// <summary>Takt mit AIntervalMs anlegen, zunächst aus.</summary>
    procedure CreateTimer(AIntervalMs: Cardinal);
    procedure SessionStarted; virtual;
    procedure SessionStopped; virtual;
    procedure SessionResumed; virtual;
    procedure SessionEnded; virtual;
    /// <summary>Ein Takt; von Haus aus nach FProgress.Next.</summary>
    procedure Advance; virtual;
    /// <summary>Besteht der Halt aus FProgress noch?</summary>
    function StillAtStop: Boolean; virtual;
    /// <summary>Ausführungspunkt lesen; False: später noch einmal bzw. aufgegeben (FProgress.Phase).</summary>
    function ReadLocation: Boolean; virtual;
    /// <summary>Ausführungspunkt gelesen: weiter mit dem Halt (Server fragen bzw. auswerten).</summary>
    procedure Ask; virtual;
    /// <summary>Ein Stück auswerten (Phase Evaluate).</summary>
    procedure EvaluateSlice; virtual;
  public
    destructor Destroy; override;
    procedure BeforeDestruction; override;
    /// <summary>Bei der Debug-Sitzung anmelden (einmal; weitere Aufrufe tun nichts).</summary>
    procedure Listen;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard;

{ TAtlasIdeDebugStopView.TListener }

procedure TAtlasIdeDebugStopView.TListener.DebugStarted;
begin
  if FView <> nil then
  begin
    FView.SessionStarted;
  end;
end;

procedure TAtlasIdeDebugStopView.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FView <> nil then
  begin
    FView.SessionStopped;
  end;
end;

procedure TAtlasIdeDebugStopView.TListener.DebugResumed;
begin
  if FView <> nil then
  begin
    FView.SessionResumed;
  end;
end;

procedure TAtlasIdeDebugStopView.TListener.DebugEnded;
begin
  if FView <> nil then
  begin
    FView.SessionEnded;
  end;
end;

{ TAtlasIdeDebugStopView }

destructor TAtlasIdeDebugStopView.Destroy;
begin
  FreeAndNil(FTimer);
  inherited Destroy;
end;

procedure TAtlasIdeDebugStopView.BeforeDestruction;
begin
  // Vor den Destruktoren der Anzeigen: kein Ereignis und kein Takt erreicht eine halb abgebaute Anzeige.
  Unlisten;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.OnTimer := nil;
  end;
  inherited BeforeDestruction;
end;

procedure TAtlasIdeDebugStopView.Listen;
begin
  if FListener <> nil then
  begin
    Exit;
  end;
  FListener := TListener.Create;
  FListener.FView := Self;
  FListenerRef := FListener;
  TAtlasIdeDebugSession.AddListener(FListenerRef);
end;

procedure TAtlasIdeDebugStopView.Unlisten;
begin
  if FListener = nil then
  begin
    Exit;
  end;
  FListener.FView := nil;
  FListener := nil;
  TAtlasIdeDebugSession.RemoveListener(FListenerRef);
  FListenerRef := nil;
end;

procedure TAtlasIdeDebugStopView.CreateTimer(AIntervalMs: Cardinal);
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
  end;
  FTimer.Enabled := False;
  FTimer.Interval := AIntervalMs;
  FTimer.OnTimer := Tick;
end;

procedure TAtlasIdeDebugStopView.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    Advance;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

procedure TAtlasIdeDebugStopView.Advance;
begin
  case FProgress.Next(StillAtStop) of
    TAtlasStopTick.Locate:
      begin
        FTimer.Enabled := False;
        if ReadLocation then
        begin
          Ask;
        end;
      end;
    TAtlasStopTick.Evaluate:
      EvaluateSlice;
  else
    FTimer.Enabled := False;
  end;
end;

function TAtlasIdeDebugStopView.StillAtStop: Boolean;
begin
  Result := FProgress.StillAt(TAtlasIdeDebugSession.StopCount, TAtlasIdeDebugSession.StoppedThread <> nil);
end;

function TAtlasIdeDebugStopView.ReadLocation: Boolean;
begin
  Result := False;
end;

procedure TAtlasIdeDebugStopView.Ask;
begin
end;

procedure TAtlasIdeDebugStopView.EvaluateSlice;
begin
end;

procedure TAtlasIdeDebugStopView.SessionStarted;
begin
end;

procedure TAtlasIdeDebugStopView.SessionStopped;
begin
end;

procedure TAtlasIdeDebugStopView.SessionResumed;
begin
end;

procedure TAtlasIdeDebugStopView.SessionEnded;
begin
end;

end.
