unit Atlas.Core.Projects.VcsQueries;

// Buchführung der Abfragen der Versionsverwaltung für die Projekt-Zusammenfassungen (#571, #1967), ohne Open
// Tools API. Atlas.IDE.Projects.Summaries startet die Abfrage im Hintergrund und meldet ihr Ende; hier fällt:
// - Je Projekt läuft höchstens eine Abfrage. Eine, die nicht binnen TAtlasProjectRecording.cVcsQueryLimitMs
//   zurückkommt, gilt als beendet („wird abgefragt …“ endet).
// - Am Ende beendet nur die eigene Abfrage ihren Eintrag, nicht eine neuere, die nach Ablauf des Zeitlimits
//   begann.
// - Frisch ist ein Projekt cVcsRefreshMs lang nach der letzten beendeten (oder nicht gestarteten) Abfrage;
//   QueryIfStale fragt erst danach wieder.
// - Das Ergebnis einer gelungenen Abfrage gilt bis zum Ende der Sitzung vor dem gespeicherten Stand.
// Schlüssel ist der vereinheitlichte Pfad (TAtlasProjectSummaries.NormalizedPath). Zeiten in Millisekunden eines
// fortlaufenden Zählers; der Aufrufer nennt die aktuelle Zeit (ANow).

interface

uses
  System.Generics.Collections,
  Atlas.Core.Projects.Summary;

type
  TAtlasProjectVcsQueries = class
  private
    /// <summary>Laufende Abfragen: Schlüssel → Start.</summary>
    FQuerying: TDictionary<string, UInt64>;
    /// <summary>Letzte beendete Abfrage: Schlüssel → Ende.</summary>
    FFresh: TDictionary<string, UInt64>;
    /// <summary>Ergebnis der letzten gelungenen Abfrage.</summary>
    FLive: TDictionary<string, TAtlasProjectVcs>;
    function RunningKey(const AKey: string; ANow: UInt64): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Schlüssel zu AProject.</summary>
    class function KeyOf(const AProject: string): string; static;
    /// <summary>Neue Abfrage für AProject beginnen: False, solange schon eine läuft. AKey und AStarted gehören an
    /// Finish bzw. NotStarted.</summary>
    function TryStart(const AProject: string; ANow: UInt64; out AKey: string; out AStarted: UInt64): Boolean;
    /// <summary>Abfrage, die bei AStarted begann, ist fertig; AOk mit AState gilt als neuer Stand.</summary>
    procedure Finish(const AKey: string; AStarted, ANow: UInt64; AOk: Boolean; const AState: TAtlasProjectVcs);
    /// <summary>Abfrage startete nicht (Versionsverwaltung nicht bereit): kein „wird abgefragt …“ und nicht bei
    /// jedem Zeichnen neu versuchen.</summary>
    procedure NotStarted(const AKey: string; ANow: UInt64);
    /// <summary>Für AProject läuft eine Abfrage.</summary>
    function Querying(const AProject: string; ANow: UInt64): Boolean;
    /// <summary>AProject wurde noch nie oder vor mindestens cVcsRefreshMs zuletzt abgefragt.</summary>
    function IsStale(const AProject: string; ANow: UInt64): Boolean;
    /// <summary>AProject gilt sofort als veraltet (der Benutzer hat gerade geholt).</summary>
    procedure Forget(const AProject: string);
    /// <summary>Stand der letzten gelungenen Abfrage in dieser Sitzung; False ohne.</summary>
    function Live(const AProject: string; out AVcs: TAtlasProjectVcs): Boolean;
  end;

implementation

uses
  Atlas.Core.Projects.Recording;

{ TAtlasProjectVcsQueries }

constructor TAtlasProjectVcsQueries.Create;
begin
  inherited Create;
  FQuerying := TDictionary<string, UInt64>.Create;
  FFresh := TDictionary<string, UInt64>.Create;
  FLive := TDictionary<string, TAtlasProjectVcs>.Create;
end;

destructor TAtlasProjectVcsQueries.Destroy;
begin
  FLive.Free;
  FFresh.Free;
  FQuerying.Free;
  inherited Destroy;
end;

class function TAtlasProjectVcsQueries.KeyOf(const AProject: string): string;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(AProject);
end;

function TAtlasProjectVcsQueries.RunningKey(const AKey: string; ANow: UInt64): Boolean;
var
  mStarted: UInt64;
begin
  Result := FQuerying.TryGetValue(AKey, mStarted) and TAtlasProjectRecording.QueryRunning(mStarted, ANow);
  if not Result then
  begin
    FQuerying.Remove(AKey);
  end;
end;

function TAtlasProjectVcsQueries.TryStart(const AProject: string; ANow: UInt64; out AKey: string;
  out AStarted: UInt64): Boolean;
begin
  AKey := KeyOf(AProject);
  AStarted := ANow;
  Result := not RunningKey(AKey, ANow);
  if Result then
  begin
    FQuerying.AddOrSetValue(AKey, AStarted);
  end;
end;

procedure TAtlasProjectVcsQueries.Finish(const AKey: string; AStarted, ANow: UInt64; AOk: Boolean;
  const AState: TAtlasProjectVcs);
var
  mCurrent: UInt64;
begin
  if FQuerying.TryGetValue(AKey, mCurrent) and (mCurrent = AStarted) then
  begin
    FQuerying.Remove(AKey);
  end;
  FFresh.AddOrSetValue(AKey, ANow);
  if AOk then
  begin
    FLive.AddOrSetValue(AKey, AState);
  end;
end;

procedure TAtlasProjectVcsQueries.NotStarted(const AKey: string; ANow: UInt64);
begin
  FQuerying.Remove(AKey);
  FFresh.AddOrSetValue(AKey, ANow);
end;

function TAtlasProjectVcsQueries.Querying(const AProject: string; ANow: UInt64): Boolean;
begin
  Result := RunningKey(KeyOf(AProject), ANow);
end;

function TAtlasProjectVcsQueries.IsStale(const AProject: string; ANow: UInt64): Boolean;
var
  mLast: UInt64;
begin
  Result := not FFresh.TryGetValue(KeyOf(AProject), mLast) or (ANow - mLast >= TAtlasProjectRecording.cVcsRefreshMs);
end;

procedure TAtlasProjectVcsQueries.Forget(const AProject: string);
begin
  FFresh.Remove(KeyOf(AProject));
end;

function TAtlasProjectVcsQueries.Live(const AProject: string; out AVcs: TAtlasProjectVcs): Boolean;
var
  mVcs: TAtlasProjectVcs;
begin
  // Eigene Variable: Delphis TryGetValue setzt den out-Wert auch ohne Schlüssel auf Default.
  AVcs := TAtlasProjectVcs.Empty;
  Result := FLive.TryGetValue(KeyOf(AProject), mVcs);
  if Result then
  begin
    AVcs := mVcs;
  end;
end;

end.
