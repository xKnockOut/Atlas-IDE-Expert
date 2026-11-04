unit Atlas.Core.Dock.Plan;

// Entscheidungen für Atlas-Dockfenster (#879), ohne VCL und Open Tools API.
// Die IDE gibt andockbare Fenster auch selbst frei (Entladen des Packages,
// Desktop-Wechsel, Beenden) und versteckt sie beim Schließen über das X
// samt Dock-Gastgeber. Ein Fenster gilt darum nur als brauchbar, wenn Form
// UND Frame noch leben; sichtbar ist es nur, wenn auch alle Gastgeber
// (Reiterseite, Dock-Fenster, Hauptfenster) sichtbar sind. Ein Fenster mit
// fester Vorgabe (etwa „Atlas-Architektur“ rechts, #1118) wird nur beim
// allerersten Anlegen dorthin gelegt; danach gilt der Desktop der IDE.

{$SCOPEDENUMS ON}

interface

type
  /// <summary>Was „Fenster zeigen“ tun muss.</summary>
  TAtlasDockStep = (
    /// <summary>Keine andockbaren Fenster (keine INTAServices): nichts tun.</summary>
    Unavailable,
    /// <summary>Kein Fenster vorhanden: neu anlegen.</summary>
    CreateForm,
    /// <summary>Fenster ohne Frame (Frame freigegeben oder nie gemeldet): altes freigeben, neu anlegen.</summary>
    RecreateForm,
    /// <summary>Fenster und Frame leben: nur sichtbar machen (samt Gastgebern).</summary>
    RevealForm);

  TAtlasDockPlan = record
  public
    /// <summary>Schritt beim Zeigen nach dem Zustand von Form und Frame.</summary>
    class function ShowStep(AServices, AFormAlive, AFrameAlive: Boolean): TAtlasDockStep; static;
    /// <summary>Frame nur benutzen, wenn auch die Form noch lebt.</summary>
    class function FrameUsable(AFormAlive, AFrameAlive: Boolean): Boolean; static;
    /// <summary>Wirklich sichtbar: Form sichtbar und jeder Gastgeber bis oben (Reihenfolge innen nach außen).</summary>
    class function Shown(AFormVisible: Boolean; const AHostsVisible: array of Boolean): Boolean; static;
    /// <summary>Neu angelegtes, schwebendes Fenster an seinen Vorgabeplatz andocken: nur einmal (APlaced
    /// merkt sich das) und nur, wenn das Ziel selbst angedockt ist. Ein Fenster, das der Desktop schon
    /// angedockt wiederhergestellt hat, bleibt, wo es ist.</summary>
    class function DockToDefault(ACreated, AFloating, APlaced, ATargetDocked: Boolean): Boolean; static;
  end;

implementation

{ TAtlasDockPlan }

class function TAtlasDockPlan.ShowStep(AServices, AFormAlive, AFrameAlive: Boolean): TAtlasDockStep;
begin
  if AFormAlive and AFrameAlive then
  begin
    Exit(TAtlasDockStep.RevealForm);
  end;
  if not AServices then
  begin
    Exit(TAtlasDockStep.Unavailable);
  end;
  if AFormAlive then
  begin
    Result := TAtlasDockStep.RecreateForm;
  end
  else
  begin
    Result := TAtlasDockStep.CreateForm;
  end;
end;

class function TAtlasDockPlan.FrameUsable(AFormAlive, AFrameAlive: Boolean): Boolean;
begin
  Result := AFormAlive and AFrameAlive;
end;

class function TAtlasDockPlan.Shown(AFormVisible: Boolean; const AHostsVisible: array of Boolean): Boolean;
var
  Visible: Boolean;
begin
  Result := AFormVisible;
  for Visible in AHostsVisible do
  begin
    Result := Result and Visible;
  end;
end;

class function TAtlasDockPlan.DockToDefault(ACreated, AFloating, APlaced, ATargetDocked: Boolean): Boolean;
begin
  Result := ACreated and AFloating and not APlaced and ATargetDocked;
end;

end.
