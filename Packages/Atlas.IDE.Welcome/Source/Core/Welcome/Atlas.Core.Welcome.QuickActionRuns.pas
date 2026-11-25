unit Atlas.Core.Welcome.QuickActionRuns;

// Stand der Schnellaktionen je Projekt in dieser Sitzung (#764), ohne VCL und
// Open Tools API: letzter Stand je Projekt (läuft seit, Ergebnis, Grund),
// laufende Testläufe (Testprojekt → Projekt der Zeile) und gestartete
// Projektaufgaben (#900). Die Schlüssel bildet die Funktion des Konstruktors
// (in der IDE der normierte Pfad); Testläufe merken sich die Zeile, wie sie
// übergeben wurde. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Welcome.QuickActions;

type
  /// <summary>Schlüssel zu einem Projektpfad.</summary>
  TAtlasQuickActionKeyOf = reference to function(const AProject: string): string;

  TAtlasQuickActionRuns = class
  private
    FKeyOf: TAtlasQuickActionKeyOf;
    /// <summary>Schlüssel des Projekts → Stand der letzten Schnellaktion.</summary>
    FStates: TDictionary<string, TAtlasQuickActionState>;
    /// <summary>Schlüssel des Testprojekts → Projekt der Zeile, deren Tests laufen.</summary>
    FTests: TDictionary<string, string>;
    /// <summary>Schlüssel des Projekts → Name der gestarteten Projektaufgabe.</summary>
    FTasks: TDictionary<string, string>;
  public
    constructor Create(const AKeyOf: TAtlasQuickActionKeyOf);
    destructor Destroy; override;
    /// <summary>Stand von AProject; ohne Aktion Idle.</summary>
    function State(const AProject: string): TAtlasQuickActionState;
    procedure SetState(const AProject: string; const AState: TAtlasQuickActionState);
    /// <summary>Aktion AAction von AProject endet mit APhase und ADetail (Zeitpunkt des Starts bleibt).</summary>
    procedure Finish(const AProject: string; AAction: TAtlasQuickAction; APhase: TAtlasQuickActionPhase;
      const ADetail: string);
    /// <summary>Läuft auf einem anderen Projekt als AProject eine Aktion, die die IDE braucht?</summary>
    function OtherUsesIde(const AProject: string): Boolean;
    /// <summary>Tests von ATestProject laufen für die Zeile ARow.</summary>
    procedure TestsStarted(const ATestProject, ARow: string);
    /// <summary>Der Testlauf von ATestProject kam nicht in Gang: vergessen.</summary>
    procedure TestsDropped(const ATestProject: string);
    /// <summary>Wartet ein Testlauf von ATestProject auf sein Ergebnis?</summary>
    function TestsPending(const ATestProject: string): Boolean; overload;
    /// <summary>Wartet irgendein Testlauf auf sein Ergebnis?</summary>
    function TestsPending: Boolean; overload;
    /// <summary>Ergebnis des Testlaufs von ATestProject in seine Zeile; False, wenn kein Lauf dazu wartet.
    /// </summary>
    function TestsFinished(const ATestProject: string; APassed, AFailed: Integer): Boolean;
    /// <summary>Testläufe, die ohne Ergebnis endeten (Zeile läuft nicht mehr oder die Schonzeit AGraceMs ist um),
    /// vergessen; liefert die Zeilen, die noch als laufend stehen.</summary>
    function EndTests(ANowMs, AGraceMs: UInt64): TArray<string>;
    /// <summary>Projektaufgabe AName von AProject gestartet.</summary>
    procedure TaskStarted(const AProject, AName: string);
    /// <summary>Die Projektaufgabe von AProject kam nicht in Gang: vergessen.</summary>
    procedure TaskDropped(const AProject: string);
    /// <summary>Projektaufgabe AName von AProject ist fertig; False, wenn die Schnellaktion sie nicht gestartet
    /// hat.</summary>
    function TaskFinished(const AProject, AName: string): Boolean;
  end;

implementation

{ TAtlasQuickActionRuns }

constructor TAtlasQuickActionRuns.Create(const AKeyOf: TAtlasQuickActionKeyOf);
begin
  inherited Create;
  FKeyOf := AKeyOf;
  FStates := TDictionary<string, TAtlasQuickActionState>.Create;
  FTests := TDictionary<string, string>.Create;
  FTasks := TDictionary<string, string>.Create;
end;

destructor TAtlasQuickActionRuns.Destroy;
begin
  FTasks.Free;
  FTests.Free;
  FStates.Free;
  FKeyOf := nil;
  inherited Destroy;
end;

function TAtlasQuickActionRuns.State(const AProject: string): TAtlasQuickActionState;
begin
  if not FStates.TryGetValue(FKeyOf(AProject), Result) then
  begin
    Result := TAtlasQuickActionState.Idle;
  end;
end;

procedure TAtlasQuickActionRuns.SetState(const AProject: string; const AState: TAtlasQuickActionState);
begin
  FStates.AddOrSetValue(FKeyOf(AProject), AState);
end;

procedure TAtlasQuickActionRuns.Finish(const AProject: string; AAction: TAtlasQuickAction;
  APhase: TAtlasQuickActionPhase; const ADetail: string);
var
  mValue: TAtlasQuickActionState;
begin
  mValue := State(AProject);
  mValue.Action := AAction;
  mValue.Phase := APhase;
  mValue.Detail := ADetail;
  SetState(AProject, mValue);
end;

function TAtlasQuickActionRuns.OtherUsesIde(const AProject: string): Boolean;
begin
  Result := TAtlasQuickActionSteps.OtherUsesIde(FStates, FKeyOf(AProject));
end;

procedure TAtlasQuickActionRuns.TestsStarted(const ATestProject, ARow: string);
begin
  FTests.AddOrSetValue(FKeyOf(ATestProject), ARow);
end;

procedure TAtlasQuickActionRuns.TestsDropped(const ATestProject: string);
begin
  FTests.Remove(FKeyOf(ATestProject));
end;

function TAtlasQuickActionRuns.TestsPending(const ATestProject: string): Boolean;
begin
  Result := FTests.ContainsKey(FKeyOf(ATestProject));
end;

function TAtlasQuickActionRuns.TestsPending: Boolean;
begin
  Result := FTests.Count > 0;
end;

function TAtlasQuickActionRuns.TestsFinished(const ATestProject: string; APassed, AFailed: Integer): Boolean;
var
  mRow: string;
begin
  Result := FTests.TryGetValue(FKeyOf(ATestProject), mRow);
  if Result then
  begin
    FTests.Remove(FKeyOf(ATestProject));
    SetState(mRow, State(mRow).AfterTests(APassed, AFailed));
  end;
end;

function TAtlasQuickActionRuns.EndTests(ANowMs, AGraceMs: UInt64): TArray<string>;
var
  mPair: TPair<string, string>;
  mEnded: TArray<string>;
  mKey: string;
begin
  Result := nil;
  mEnded := nil;
  for mPair in FTests do
  begin
    if State(mPair.Value).TestEnded(ANowMs, AGraceMs) then
    begin
      mEnded := mEnded + [mPair.Key];
    end;
  end;
  for mKey in mEnded do
  begin
    if State(FTests[mKey]).Running then
    begin
      Result := Result + [FTests[mKey]];
    end;
    FTests.Remove(mKey);
  end;
end;

procedure TAtlasQuickActionRuns.TaskStarted(const AProject, AName: string);
begin
  FTasks.AddOrSetValue(FKeyOf(AProject), AName);
end;

procedure TAtlasQuickActionRuns.TaskDropped(const AProject: string);
begin
  FTasks.Remove(FKeyOf(AProject));
end;

function TAtlasQuickActionRuns.TaskFinished(const AProject, AName: string): Boolean;
var
  mName: string;
begin
  Result := FTasks.TryGetValue(FKeyOf(AProject), mName) and SameText(mName, AName);
  if Result then
  begin
    FTasks.Remove(FKeyOf(AProject));
  end;
end;

end.
