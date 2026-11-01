unit Atlas.Core.Build.IdleGate;

// Ruhe nach dem Übersetzen, ohne Open Tools API: Wann darf das Plugin ein
// Dockfenster von sich aus anlegen?
// Baut die IDE eine Gruppe, in der das Plugin-Projekt selbst steht, entlädt
// sie das Plugin und lädt es danach neu, mitten im Gruppen-Build. Legt das
// Plugin dann gleich ein Dockfenster an (Diagnosemodus), stürzt die IDE beim
// nächsten Projekt in coreide ab (Zugriffsverletzung, Lesen von 0). Darum
// gilt: Erst wenn kein Projekt und keine Gruppe übersetzt wird und seit dem
// letzten Compile-Ereignis QuietMs vergangen sind, ist Ruhe. Die Wartezeit
// gilt auch ab dem Anlegen: Nach einem Neuladen mitten im Build kennt das
// Plugin den laufenden Gruppen-Build nicht, das nächste Projekt meldet sich
// aber innerhalb von QuietMs.

interface

type
  TAtlasBuildIdleGate = class
  public const
    QuietMs = 3000;
  private
    FProjects: Integer;
    FGroup: Boolean;
    FLastEvent: UInt64;
    procedure Touch(ANow: UInt64);
  public
    /// <summary>ANow: Zeit in ms (GetTickCount64); ab dann zählt die Ruhezeit.</summary>
    constructor Create(ANow: UInt64);
    procedure ProjectStarted(ANow: UInt64);
    procedure ProjectFinished(ANow: UInt64);
    procedure GroupStarted(ANow: UInt64);
    /// <summary>Ende der Gruppe; ein fehlendes ProjectFinished zählt damit als erledigt.</summary>
    procedure GroupFinished(ANow: UInt64);
    /// <summary>Kein Compile aktiv und seit dem letzten Ereignis mindestens QuietMs vergangen.</summary>
    function Idle(ANow: UInt64): Boolean;
  end;

implementation

{ TAtlasBuildIdleGate }

constructor TAtlasBuildIdleGate.Create(ANow: UInt64);
begin
  inherited Create;
  FLastEvent := ANow;
end;

procedure TAtlasBuildIdleGate.Touch(ANow: UInt64);
begin
  if ANow > FLastEvent then
    FLastEvent := ANow;
end;

procedure TAtlasBuildIdleGate.ProjectStarted(ANow: UInt64);
begin
  Inc(FProjects);
  Touch(ANow);
end;

procedure TAtlasBuildIdleGate.ProjectFinished(ANow: UInt64);
begin
  // Nach dem Neuladen mitten im Build kann ein Ende ohne Anfang kommen.
  if FProjects > 0 then
    Dec(FProjects);
  Touch(ANow);
end;

procedure TAtlasBuildIdleGate.GroupStarted(ANow: UInt64);
begin
  FGroup := True;
  Touch(ANow);
end;

procedure TAtlasBuildIdleGate.GroupFinished(ANow: UInt64);
begin
  FGroup := False;
  FProjects := 0;
  Touch(ANow);
end;

function TAtlasBuildIdleGate.Idle(ANow: UInt64): Boolean;
begin
  Result := not FGroup and (FProjects = 0) and (ANow >= FLastEvent + QuietMs);
end;

end.
