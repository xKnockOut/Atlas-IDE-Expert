unit Atlas.Core.Debug.ReattachFlow;

// Entscheidungen von „Erneut anhängen“ (#2171) außerhalb der Prozesswahl, ohne IDE prüfbar (#1967): wann nach dem Ende
// das Warten angeboten wird, ob ein Treffer des Wartens noch zählt, wann ein Wechsel der Projektgruppe das Warten
// beendet bzw. den Menüeintrag erneuert, welches Programm zuletzt gemerkt ist und welches der Dateidialog vorschlägt.
// Atlas.IDE.Debug.Reattach fragt IDE, Windows und Debugger.

interface

type
  TAtlasReattachFlow = class
  public
    /// <summary>Nach dem Ende einer angehängten Sitzung (APath) „Warten auf Neustart“ anbieten?</summary>
    class function OffersWait(const APath: string; AWaiting: Boolean): Boolean; static;
    /// <summary>Zählt ein Treffer aus dem Warten AGeneration noch (kein abgebrochenes oder ersetztes Warten)?</summary>
    class function Counts(AGeneration, ACurrent: Integer; AWaiting: Boolean): Boolean; static;
    /// <summary>Projektgruppe gewechselt oder geschlossen, während auf AWaitGroup gewartet wird?</summary>
    class function GroupLeft(AWaiting: Boolean; const AGroup, AWaitGroup: string): Boolean; static;
    /// <summary>Nennt der Menüeintrag noch das Programm einer anderen Gruppe?</summary>
    class function MenuStale(const AGroup, AMenuGroup: string): Boolean; static;
    /// <summary>Zuletzt gemerktes Programm (erster Eintrag); '' ohne.</summary>
    class function LastOf(const AItems: TArray<string>): string; static;
    /// <summary>Vorschlag im Dateidialog: das zuletzt gemerkte Programm, sonst das Ziel des aktiven Projekts.
    /// </summary>
    class function DefaultExe(const ALast, AProjectTarget: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasReattachFlow }

class function TAtlasReattachFlow.OffersWait(const APath: string; AWaiting: Boolean): Boolean;
begin
  Result := (APath <> '') and not AWaiting;
end;

class function TAtlasReattachFlow.Counts(AGeneration, ACurrent: Integer; AWaiting: Boolean): Boolean;
begin
  Result := (AGeneration = ACurrent) and AWaiting;
end;

class function TAtlasReattachFlow.GroupLeft(AWaiting: Boolean; const AGroup, AWaitGroup: string): Boolean;
begin
  Result := AWaiting and not SameText(AGroup, AWaitGroup);
end;

class function TAtlasReattachFlow.MenuStale(const AGroup, AMenuGroup: string): Boolean;
begin
  Result := not SameText(AGroup, AMenuGroup);
end;

class function TAtlasReattachFlow.LastOf(const AItems: TArray<string>): string;
begin
  Result := '';
  if AItems <> nil then
  begin
    Result := AItems[0];
  end;
end;

class function TAtlasReattachFlow.DefaultExe(const ALast, AProjectTarget: string): string;
begin
  Result := ALast;
  if Result = '' then
  begin
    Result := AProjectTarget;
  end;
end;

end.
