unit Atlas.Core.Assistants.DebugGate;

// Debuggen für KI-Assistenten (#1874): Wer darf was, ohne Open Tools API. TAtlasDebugGate führt die Sitzung des
// KI-Assistenten im Eingang des Plugins:
//   - Pause für KI: Solange sie gilt, lehnt der Eingang jeden Auftrag ab; „Fortsetzen“ hebt sie auf.
//   - Eigene Sitzung: Startet der Assistent ein Programm (debug_start), gehört die Sitzung ihm, bis der Debugger
//     endet oder der Benutzer sie mit „Übernehmen“ an sich nimmt. Debuggt der Benutzer selbst, lehnt der Eingang
//     jeden Auftrag ab, außer debug.mcp.attach ist an.
//   - Rechte: Ausdrücke mit Aufrufen nur mit debug.mcp.sideEffects, Zuweisungen (Werte ändern) nur mit
//     debug.mcp.modify; sonst Ablehnung mit Grund, damit der Assistent den Benutzer fragen kann.
//   - Zähler für die Leiste: Schritte (debug_step, debug_continue) und das zuletzt benutzte Werkzeug.
// TAtlasDebugWait entscheidet, wann ein Start, Weiterlaufen oder Schritt beantwortet wird: bei einem neuen Halt, am
// Ende des Programms oder nach waitSeconds. Zeit und Zustand kommen vom Aufrufer.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Core.DebugControl.Types,
  Atlas.Core.Assistants.DebugInbox;

type
  /// <summary>Warum ein Auftrag abgelehnt wird; None = annehmen.</summary>
  TAtlasDebugRefusal = (None, Paused, UserSession, AlreadyRunning, NoProgram, NotStopped, SideEffects, Modify);

  /// <summary>Rechte aus den Einstellungen debug.mcp.sideEffects, debug.mcp.modify und debug.mcp.attach.</summary>
  TAtlasDebugRights = record
    SideEffects: Boolean;
    Modify: Boolean;
    Attach: Boolean;
    class function Make(ASideEffects, AModify, AAttach: Boolean): TAtlasDebugRights; static;
  end;

  /// <summary>Warten auf den nächsten Halt nach Start, Weiterlaufen oder Schritt.</summary>
  TAtlasDebugWait = record
  private
    FStops: Integer;
    FDeadline: UInt64;
    FSeenProgram: Boolean;
  public
    /// <summary>Beginnt zu warten: AStops = Haltezähler jetzt, ANowMs = Tickzähler, AWaitSeconds = Frist.
    /// ALaunch: Das Programm läuft noch nicht; ein Debugger ohne Prozess heißt dann „noch nicht gestartet“.</summary>
    class function Start(AStops: Integer; ANowMs: UInt64; AWaitSeconds: Integer; ALaunch: Boolean): TAtlasDebugWait;
      static;
    /// <summary>Jetzt antworten? Bei einem neuen Halt, am Ende des Programms oder nach der Frist.</summary>
    function Done(APhase: TAtlasDebugControlPhase; AStops: Integer; ANowMs: UInt64): Boolean;
  end;

  TAtlasDebugGate = class
  private
    FPaused: Boolean;
    FOwn: Boolean;
    FEnded: Boolean;
    FSession: string;
    FClient: string;
    FLastTool: string;
    FSteps: Integer;
  public
    /// <summary>Grund, ARequest abzulehnen; None = annehmen. APhase: Zustand des Debuggers jetzt.</summary>
    function Refusal(const ARequest: TAtlasDebugRequest; APhase: TAtlasDebugControlPhase;
      const ARights: TAtlasDebugRights): TAtlasDebugRefusal;
    /// <summary>Ausdruck mit Zuweisung (:= außerhalb von Zeichenketten): Werte ändern.</summary>
    class function Assigns(const AExpression: string): Boolean; static;
    /// <summary>Angenommenen Auftrag vermerken (Client, letztes Werkzeug, Schritte).</summary>
    procedure Note(const ARequest: TAtlasDebugRequest);
    /// <summary>Der Assistent hat ein Programm gestartet; ASession ist die neue Kennung.</summary>
    procedure Launched(const ASession: string);
    /// <summary>Zustand des Debuggers beobachtet: Ohne Prozess endet die eigene Sitzung.</summary>
    procedure Observe(APhase: TAtlasDebugControlPhase);
    /// <summary>Name für "state": none, running, stopped oder terminated (eigene Sitzung beendet).</summary>
    function StateName(APhase: TAtlasDebugControlPhase): string;
    /// <summary>„Pause für KI“ bzw. „Fortsetzen“.</summary>
    procedure SetPaused(AValue: Boolean);
    /// <summary>„Übernehmen“: Die Sitzung bleibt, der Assistent ist getrennt.</summary>
    procedure TakeOver;
    /// <summary>Leiste im Editor zeigen? Mit ABanner (debug.mcp.banner), solange der Assistent eine Sitzung steuert
    /// oder „Pause für KI“ gilt (sonst fände der Benutzer „Fortsetzen“ nicht).</summary>
    function BarShown(ABanner: Boolean): Boolean;
    property Paused: Boolean read FPaused;
    /// <summary>Der Assistent steuert gerade ein von ihm gestartetes Programm.</summary>
    property Own: Boolean read FOwn;
    property Session: string read FSession;
    property Client: string read FClient;
    property LastTool: string read FLastTool;
    property Steps: Integer read FSteps;
  end;

implementation

{ TAtlasDebugRights }

class function TAtlasDebugRights.Make(ASideEffects, AModify, AAttach: Boolean): TAtlasDebugRights;
begin
  Result.SideEffects := ASideEffects;
  Result.Modify := AModify;
  Result.Attach := AAttach;
end;

{ TAtlasDebugWait }

class function TAtlasDebugWait.Start(AStops: Integer; ANowMs: UInt64; AWaitSeconds: Integer;
  ALaunch: Boolean): TAtlasDebugWait;
begin
  Result := Default(TAtlasDebugWait);
  Result.FStops := AStops;
  if AWaitSeconds < 0 then
  begin
    AWaitSeconds := 0;
  end;
  Result.FDeadline := ANowMs + UInt64(AWaitSeconds) * 1000;
  Result.FSeenProgram := not ALaunch;
end;

function TAtlasDebugWait.Done(APhase: TAtlasDebugControlPhase; AStops: Integer; ANowMs: UInt64): Boolean;
begin
  if APhase <> TAtlasDebugControlPhase.None then
  begin
    FSeenProgram := True;
  end;
  Result := (ANowMs >= FDeadline) or ((APhase = TAtlasDebugControlPhase.None) and FSeenProgram) or
    ((APhase = TAtlasDebugControlPhase.Stopped) and (AStops <> FStops));
end;

{ TAtlasDebugGate }

class function TAtlasDebugGate.Assigns(const AExpression: string): Boolean;
var
  mIndex: Integer;
  mQuoted: Boolean;
begin
  mQuoted := False;
  for mIndex := 1 to Length(AExpression) - 1 do
  begin
    if AExpression[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted and (AExpression[mIndex] = ':') and (AExpression[mIndex + 1] = '=') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Grund aus Zustand und Befehl, wenn der Auftrag die Sitzung braucht.</summary>
function PhaseRefusal(ACommand: TAtlasDebugCommand; APhase: TAtlasDebugControlPhase): TAtlasDebugRefusal;
begin
  Result := TAtlasDebugRefusal.None;
  if not (ACommand in [TAtlasDebugCommand.Resume, TAtlasDebugCommand.Step, TAtlasDebugCommand.Evaluate]) then
  begin
    Exit;
  end;
  if APhase = TAtlasDebugControlPhase.None then
  begin
    Result := TAtlasDebugRefusal.NoProgram;
  end
  else if APhase = TAtlasDebugControlPhase.Running then
  begin
    Result := TAtlasDebugRefusal.NotStopped;
  end;
end;

function TAtlasDebugGate.Refusal(const ARequest: TAtlasDebugRequest; APhase: TAtlasDebugControlPhase;
  const ARights: TAtlasDebugRights): TAtlasDebugRefusal;
begin
  if FPaused then
  begin
    Exit(TAtlasDebugRefusal.Paused);
  end;
  // Eine Sitzung, die der Assistent nicht gestartet hat, gehört dem Benutzer.
  if (APhase <> TAtlasDebugControlPhase.None) and not FOwn and not ARights.Attach then
  begin
    Exit(TAtlasDebugRefusal.UserSession);
  end;
  if (ARequest.Command = TAtlasDebugCommand.Start) and (APhase <> TAtlasDebugControlPhase.None) then
  begin
    Exit(TAtlasDebugRefusal.AlreadyRunning);
  end;
  Result := PhaseRefusal(ARequest.Command, APhase);
  if (Result <> TAtlasDebugRefusal.None) or (ARequest.Command <> TAtlasDebugCommand.Evaluate) then
  begin
    Exit;
  end;
  if Assigns(ARequest.Expression) and not ARights.Modify then
  begin
    Result := TAtlasDebugRefusal.Modify;
  end
  else if ARequest.SideEffects and not ARights.SideEffects then
  begin
    Result := TAtlasDebugRefusal.SideEffects;
  end;
end;

procedure TAtlasDebugGate.Note(const ARequest: TAtlasDebugRequest);
begin
  if ARequest.Client <> '' then
  begin
    FClient := ARequest.Client;
  end;
  FLastTool := TAtlasDebugInbox.cCommandNames[ARequest.Command];
  if ARequest.Command in [TAtlasDebugCommand.Resume, TAtlasDebugCommand.Step] then
  begin
    Inc(FSteps);
  end;
end;

procedure TAtlasDebugGate.Launched(const ASession: string);
begin
  FOwn := True;
  FEnded := False;
  FSession := ASession;
  FSteps := 0;
end;

procedure TAtlasDebugGate.Observe(APhase: TAtlasDebugControlPhase);
begin
  if FOwn and (APhase = TAtlasDebugControlPhase.None) then
  begin
    FOwn := False;
    FEnded := True;
  end;
end;

function TAtlasDebugGate.StateName(APhase: TAtlasDebugControlPhase): string;
begin
  if (APhase = TAtlasDebugControlPhase.None) and FEnded then
  begin
    Result := TAtlasDebugInbox.cTerminated;
  end
  else
  begin
    Result := TAtlasDebugInbox.cPhaseNames[APhase];
  end;
end;

procedure TAtlasDebugGate.SetPaused(AValue: Boolean);
begin
  FPaused := AValue;
end;

procedure TAtlasDebugGate.TakeOver;
begin
  FOwn := False;
  FEnded := False;
  FSession := '';
  FSteps := 0;
  FLastTool := '';
end;

function TAtlasDebugGate.BarShown(ABanner: Boolean): Boolean;
begin
  Result := ABanner and (FOwn or FPaused);
end;

end.
