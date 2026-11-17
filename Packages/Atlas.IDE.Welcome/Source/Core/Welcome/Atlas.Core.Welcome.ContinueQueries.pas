unit Atlas.Core.Welcome.ContinueQueries;

// Stand der Abfragen im Hintergrund des Bereichs „Weiterarbeiten“ (#755,
// #571), ohne VCL und Open Tools API. Die Abfragen selbst startet die
// IDE-Schicht (Atlas.IDE.Welcome.Continue); hier steht nur, was sie sich
// merkt, je normiertem Schlüssel (Ziel bzw. Projekt):
// - TAtlasContinueHeads: HEAD und verfolgter Branch je Ziel, wann zuletzt
//   gefragt und welche Abfrage gerade läuft (höchstens eine je Ziel innerhalb
//   von cQueryLimitMs).
// - TAtlasContinueIncomingQueries: eingehende Commits zum obersten Eintrag,
//   laufende Abfrage und Zeitpunkt des letzten Ergebnisses.
// Zeiten in Millisekunden (GetTickCount64 der IDE); der Aufrufer reicht sie
// herein. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Welcome.Continue;

type
  TAtlasContinueHeads = class
  private
    FStates: TDictionary<string, TAtlasWorkState>;
    FFresh: TDictionary<string, UInt64>;
    FQuerying: TDictionary<string, UInt64>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Läuft für AKey noch eine Abfrage, die nicht älter als die Grenze ist?</summary>
    function Querying(const AKey: string; ANowMs: UInt64): Boolean;
    /// <summary>Abfrage für AKey begonnen (AStarted = ihr Beginn).</summary>
    procedure Started(const AKey: string; AStarted: UInt64);
    /// <summary>Die Abfrage für AKey kam nicht in Gang; als frisch gefragt merken.</summary>
    procedure NotStarted(const AKey: string; ANowMs: UInt64);
    /// <summary>Ergebnis der Abfrage AStarted für AKey; mit AOk gilt AHead als neuer Stand.</summary>
    procedure Arrived(const AKey: string; AStarted, ANowMs: UInt64; AOk: Boolean; const AHead: TAtlasWorkState);
    /// <summary>Zuletzt bekannter HEAD-Stand von AKey; False ohne.</summary>
    function TryHead(const AKey: string; out AHead: TAtlasWorkState): Boolean;
    /// <summary>Wurde AKey innerhalb von AWindowMs gefragt?</summary>
    function Recent(const AKey: string; ANowMs, AWindowMs: UInt64): Boolean;
  end;

  TAtlasContinueIncomingQueries = class
  private
    FData: TAtlasContinueIncoming;
    FKey: string;
    FFresh: UInt64;
    FStarted: UInt64;
  public
    /// <summary>Läuft eine Abfrage, die nicht älter als die Grenze ist? Eine ältere gilt als vergessen.</summary>
    function Running(ANowMs: UInt64): Boolean;
    /// <summary>Ist eine Abfrage für AKey fällig (AForce: auch mit frischem Ergebnis)?</summary>
    function Due(AForce: Boolean; const AKey: string; ANowMs: UInt64): Boolean;
    /// <summary>Abfrage für AKey begonnen; ein anderer Schlüssel verwirft die alten Commits.</summary>
    procedure Started(const AKey: string; AStarted: UInt64);
    /// <summary>Die Abfrage kam nicht in Gang.</summary>
    procedure NotStarted(ANowMs: UInt64);
    /// <summary>Ergebnis der Abfrage AStarted für AKey bzw. AProject; ohne AOk kein Abschnitt. False, wenn der
    /// oberste Eintrag inzwischen ein anderer ist (nichts geändert).</summary>
    function Arrived(const AKey, AProject: string; AStarted, ANowMs: UInt64; AOk: Boolean;
      const AFound: TAtlasContinueIncoming): Boolean;
    /// <summary>Stand von AKey wurde geschrieben: beim nächsten Anzeigen neu fragen.</summary>
    procedure Outdate(const AKey: string);
    /// <summary>Commits zum obersten Eintrag ATop; leer, wenn sie zu einem anderen gehören.</summary>
    function Current(const ATop: string): TAtlasContinueIncoming;
    /// <summary>Schlüssel der letzten Abfrage.</summary>
    property Key: string read FKey;
  end;

implementation

{ TAtlasContinueHeads }

constructor TAtlasContinueHeads.Create;
begin
  inherited Create;
  FStates := TDictionary<string, TAtlasWorkState>.Create;
  FFresh := TDictionary<string, UInt64>.Create;
  FQuerying := TDictionary<string, UInt64>.Create;
end;

destructor TAtlasContinueHeads.Destroy;
begin
  FQuerying.Free;
  FFresh.Free;
  FStates.Free;
  inherited Destroy;
end;

function TAtlasContinueHeads.Querying(const AKey: string; ANowMs: UInt64): Boolean;
var
  mStarted: UInt64;
begin
  Result := FQuerying.TryGetValue(AKey, mStarted) and
    TAtlasContinueSession.Recent(mStarted, ANowMs, TAtlasWelcomeContinue.cQueryLimitMs);
end;

procedure TAtlasContinueHeads.Started(const AKey: string; AStarted: UInt64);
begin
  FQuerying.AddOrSetValue(AKey, AStarted);
end;

procedure TAtlasContinueHeads.NotStarted(const AKey: string; ANowMs: UInt64);
begin
  FQuerying.Remove(AKey);
  FFresh.AddOrSetValue(AKey, ANowMs);
end;

procedure TAtlasContinueHeads.Arrived(const AKey: string; AStarted, ANowMs: UInt64; AOk: Boolean;
  const AHead: TAtlasWorkState);
var
  mCurrent: UInt64;
begin
  if FQuerying.TryGetValue(AKey, mCurrent) and (mCurrent = AStarted) then
  begin
    FQuerying.Remove(AKey);
  end;
  FFresh.AddOrSetValue(AKey, ANowMs);
  if AOk then
  begin
    FStates.AddOrSetValue(AKey, AHead);
  end;
end;

function TAtlasContinueHeads.TryHead(const AKey: string; out AHead: TAtlasWorkState): Boolean;
begin
  Result := FStates.TryGetValue(AKey, AHead);
end;

function TAtlasContinueHeads.Recent(const AKey: string; ANowMs, AWindowMs: UInt64): Boolean;
var
  mLast: UInt64;
begin
  Result := FFresh.TryGetValue(AKey, mLast) and TAtlasContinueSession.Recent(mLast, ANowMs, AWindowMs);
end;

{ TAtlasContinueIncomingQueries }

function TAtlasContinueIncomingQueries.Running(ANowMs: UInt64): Boolean;
begin
  Result := TAtlasContinueSession.Recent(FStarted, ANowMs, TAtlasWelcomeContinue.cQueryLimitMs);
  if not Result then
  begin
    FStarted := 0;
  end;
end;

function TAtlasContinueIncomingQueries.Due(AForce: Boolean; const AKey: string; ANowMs: UInt64): Boolean;
begin
  Result := TAtlasContinueSession.IncomingDue(AForce, AKey = FKey, FFresh, ANowMs);
end;

procedure TAtlasContinueIncomingQueries.Started(const AKey: string; AStarted: UInt64);
begin
  FStarted := AStarted;
  // Ein anderer oberster Eintrag: alte Commits nicht mehr zeigen.
  if AKey <> FKey then
  begin
    FData := Default(TAtlasContinueIncoming);
  end;
  FKey := AKey;
end;

procedure TAtlasContinueIncomingQueries.NotStarted(ANowMs: UInt64);
begin
  FStarted := 0;
  FFresh := ANowMs;
end;

function TAtlasContinueIncomingQueries.Arrived(const AKey, AProject: string; AStarted, ANowMs: UInt64;
  AOk: Boolean; const AFound: TAtlasContinueIncoming): Boolean;
begin
  if FStarted = AStarted then
  begin
    FStarted := 0;
  end;
  Result := FKey = AKey;
  if not Result then
  begin
    Exit;
  end;
  FFresh := ANowMs;
  FData := AFound;
  if not AOk then
  begin
    // Fehler oder Zeitüberschreitung: kein Abschnitt.
    FData := Default(TAtlasContinueIncoming);
    FData.Project := AProject;
  end;
end;

procedure TAtlasContinueIncomingQueries.Outdate(const AKey: string);
begin
  if FKey = AKey then
  begin
    FFresh := 0;
  end;
end;

function TAtlasContinueIncomingQueries.Current(const ATop: string): TAtlasContinueIncoming;
begin
  Result := Default(TAtlasContinueIncoming);
  if TAtlasContinueSession.IncomingFits(ATop, FKey, FData.Project) then
  begin
    Result := FData;
  end;
end;

end.
