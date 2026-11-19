unit Atlas.Core.Tracker.BoardPlan;

// Entscheidungen des Fensters „Atlas-Board“ (#1272) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.Board)
// ruft nur noch Fenster, Dialog und Hintergrundarbeiter:
// - Was nach dem Laden erscheint: frischer Stand (bei GitHub ohne Recht auf Projekte mit Hinweis), der letzte Stand
//   aus dem Zwischenspeicher, nur ein Hinweis oder nichts (abgebrochen), und welcher Grund genannt wird.
// - Karten aus einem anderen Repository (GitHub „owner/repo#12“) öffnen nur im Browser; Beginnen, Prüfen und
//   Zuweisen gehen nur mit eigener Kennung.
// - Ob gezogen werden darf (ohne Verbindung gesperrt, Workflow von YouTrack) und ob die Fehlermeldung die
//   erlaubten Übergänge nennt. Nach der Rückfrage findet Relocate Karte und Spalte über Kennung und Namen im
//   dann gezeigten Stand wieder.
// - Stand des Ladens (TAtlasBoardLoadRun): Jedes Laden beginnt mit einer neuen Generation und ohne
//   Ladezustand; nur die Antwort der jüngsten Generation zählt und beendet ihn.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
{$SCOPEDENUMS ON}
  /// <summary>Was das Fenster nach dem Laden zeigt: frischen Stand (FreshDenied: ohne Recht auf Projekte, mit
  /// Hinweis), den letzten Stand mit Grund, nur den Grund als Hinweis oder nichts (abgebrochen).</summary>
  TAtlasBoardLoadView = (Fresh, FreshDenied, Cached, Notice, Silent);
  /// <summary>Grund, den das Fenster bei einem Ladefehler nennt.</summary>
  TAtlasBoardReason = (Token, NoBoard, Timeout, NoTracker, Invalid, Network);
  /// <summary>Prüfung vor dem Ziehen: erlaubt; ohne Verbindung oder Schreibweg gesperrt; ohne Meldung
  /// abgelehnt; vom Workflow abgelehnt ohne bzw. mit erlaubten Übergängen.</summary>
  TAtlasBoardMoveCheck = (Allowed, Locked, Refused, NoTransition, NotAllowed);
  /// <summary>Klick auf eine Karte: nichts, Vorschau oder Seite im Browser.</summary>
  TAtlasBoardCardOpen = (None, Preview, Browse);
{$SCOPEDENUMS OFF}

  /// <summary>Laden im Fenster „Atlas-Board“: Generation des jüngsten Ladens und ob eine Abfrage läuft. Nur im
  /// Hauptthread.</summary>
  TAtlasBoardLoadRun = record
  private
    FGeneration: Integer;
    FLoading: Boolean;
  public
    /// <summary>Neues Laden: Ältere Antworten zählen nicht mehr, und es lädt erst nach Started (ohne Tracker
    /// gar nicht). Ergebnis: die neue Generation.</summary>
    function Next: Integer;
    /// <summary>Die Abfrage der jüngsten Generation läuft.</summary>
    procedure Started;
    /// <summary>Antwort des Ladens AGeneration: True, wenn sie zählt; dann endet der Ladezustand.</summary>
    function Answered(AGeneration: Integer): Boolean;
    property Generation: Integer read FGeneration;
    property Loading: Boolean read FLoading;
  end;

  TAtlasBoardPlan = class
  public
    /// <summary>Kennung aus einem anderen Repository (GitHub „owner/repo#12“).</summary>
    class function Foreign(const AKey: string): Boolean; static;
    /// <summary>Beginnen, Prüfen und Zuweisen: nur mit eigener Kennung.</summary>
    class function Actionable(const AKey: string): Boolean; static;
    /// <summary>Klick auf die Karte AKey; AHasPreview: Vorschau angebunden.</summary>
    class function CardOpen(const AKey: string; AHasPreview: Boolean): TAtlasBoardCardOpen; static;
    /// <summary>Seite im Browser: die Seite des Anbieters (AProviderPage, nur bei eigener Kennung), sonst die aus
    /// der Antwort.</summary>
    class function BrowsePage(const AKey, ACardPage, AProviderPage: string): string; static;
    /// <summary>Anzeige nach dem Laden; AHasCache: letzter Stand im Zwischenspeicher (nur ohne Erfolg gefragt).
    /// </summary>
    class function LoadView(ASucceeded, AProjectsDenied, AHasCache: Boolean;
      AError: TAtlasCiFetchError): TAtlasBoardLoadView; static;
    /// <summary>Grund zu AError.</summary>
    class function ReasonOf(AError: TAtlasCiFetchError): TAtlasBoardReason; static;
    /// <summary>Anderer Tracker (Projektwechsel): Auswahl von Board und Sprint und der Stand gelten nicht mehr.
    /// </summary>
    class function TargetChanged(const AOld, ANew: TAtlasTrackerTarget): Boolean; static;
    /// <summary>Darf ACard nach AColumn gezogen werden?</summary>
    class function MoveCheck(AOnline, ACanWrite: Boolean; const ASnapshot: TAtlasBoardSnapshot;
      ACard, AColumn: Integer): TAtlasBoardMoveCheck; static;
    /// <summary>Nennt die Meldung zum gescheiterten Verschieben die erlaubten Übergänge (abgelehnt unter einer
    /// Zustandsmaschine)?</summary>
    class function ShowsTransitions(const ACard: TAtlasBoardCard; const AResult: TAtlasTrackerWriteResult): Boolean;
      static;
    /// <summary>Neu laden bei Aktualisieren: nur gestartet, an, sichtbar und ohne laufendes Laden oder Verschieben.
    /// </summary>
    class function Refreshes(AStarted, AActive, AVisible, ALoading, AMoving: Boolean): Boolean; static;
    /// <summary>Karte AKey und Spalte AColumnName (ohne Groß-/Kleinschreibung) in ASnapshot; False, wenn eine
    /// fehlt (inzwischen neu geladen).</summary>
    class function Relocate(const ASnapshot: TAtlasBoardSnapshot; const AKey, AColumnName: string;
      out ACard, AColumn: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasBoardPlan.Foreign(const AKey: string): Boolean;
begin
  Result := Pos('/', AKey) > 0;
end;

class function TAtlasBoardPlan.Actionable(const AKey: string): Boolean;
begin
  Result := (AKey <> '') and not Foreign(AKey);
end;

class function TAtlasBoardPlan.CardOpen(const AKey: string; AHasPreview: Boolean): TAtlasBoardCardOpen;
begin
  Result := TAtlasBoardCardOpen.None;
  if AKey = '' then
  begin
    Exit;
  end;
  Result := TAtlasBoardCardOpen.Browse;
  if AHasPreview and not Foreign(AKey) then
  begin
    Result := TAtlasBoardCardOpen.Preview;
  end;
end;

class function TAtlasBoardPlan.BrowsePage(const AKey, ACardPage, AProviderPage: string): string;
begin
  Result := ACardPage;
  if not Foreign(AKey) and (AProviderPage <> '') then
  begin
    Result := AProviderPage;
  end;
end;

class function TAtlasBoardPlan.LoadView(ASucceeded, AProjectsDenied, AHasCache: Boolean;
  AError: TAtlasCiFetchError): TAtlasBoardLoadView;
begin
  if ASucceeded then
  begin
    Result := TAtlasBoardLoadView.Fresh;
    if AProjectsDenied then
    begin
      Result := TAtlasBoardLoadView.FreshDenied;
    end;
  end
  else if AHasCache and (AError <> TAtlasCiFetchError.NotFound) then
  begin
    Result := TAtlasBoardLoadView.Cached;
  end
  else if AError <> TAtlasCiFetchError.Cancelled then
  begin
    Result := TAtlasBoardLoadView.Notice;
  end
  else
  begin
    Result := TAtlasBoardLoadView.Silent;
  end;
end;

class function TAtlasBoardPlan.ReasonOf(AError: TAtlasCiFetchError): TAtlasBoardReason;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasBoardReason.Token;
    TAtlasCiFetchError.NotFound:
      Result := TAtlasBoardReason.NoBoard;
    TAtlasCiFetchError.Timeout:
      Result := TAtlasBoardReason.Timeout;
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasBoardReason.NoTracker;
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasBoardReason.Invalid;
  else
    Result := TAtlasBoardReason.Network;
  end;
end;

class function TAtlasBoardPlan.TargetChanged(const AOld, ANew: TAtlasTrackerTarget): Boolean;
begin
  Result := not SameText(ANew.Key, AOld.Key);
end;

class function TAtlasBoardPlan.MoveCheck(AOnline, ACanWrite: Boolean; const ASnapshot: TAtlasBoardSnapshot;
  ACard, AColumn: Integer): TAtlasBoardMoveCheck;
begin
  if not AOnline or not ACanWrite then
  begin
    Result := TAtlasBoardMoveCheck.Locked;
  end
  else if TAtlasBoardTransitions.Allowed(ASnapshot, ACard, AColumn) then
  begin
    Result := TAtlasBoardMoveCheck.Allowed;
  end
  else if not TAtlasTrackerBoard.CanMove(ASnapshot, ACard, AColumn) then
  begin
    Result := TAtlasBoardMoveCheck.Refused;
  end
  else if TAtlasBoardTransitions.Names(ASnapshot.Cards[ACard]) = '' then
  begin
    Result := TAtlasBoardMoveCheck.NoTransition;
  end
  else
  begin
    Result := TAtlasBoardMoveCheck.NotAllowed;
  end;
end;

class function TAtlasBoardPlan.ShowsTransitions(const ACard: TAtlasBoardCard;
  const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Result := (AResult.Error = TAtlasCiFetchError.Invalid) and ACard.Workflow.StateMachine and
    (TAtlasBoardTransitions.Names(ACard) <> '');
end;

class function TAtlasBoardPlan.Refreshes(AStarted, AActive, AVisible, ALoading, AMoving: Boolean): Boolean;
begin
  Result := AStarted and AActive and AVisible and not ALoading and not AMoving;
end;

class function TAtlasBoardPlan.Relocate(const ASnapshot: TAtlasBoardSnapshot; const AKey, AColumnName: string;
  out ACard, AColumn: Integer): Boolean;
var
  mIndex: Integer;
begin
  ACard := ASnapshot.CardIndex(AKey);
  AColumn := -1;
  for mIndex := 0 to High(ASnapshot.Columns) do
  begin
    if SameText(ASnapshot.Columns[mIndex].Name, AColumnName) then
    begin
      AColumn := mIndex;
      Break;
    end;
  end;
  Result := (ACard >= 0) and (AColumn >= 0);
end;

{ TAtlasBoardLoadRun }

function TAtlasBoardLoadRun.Next: Integer;
begin
  Inc(FGeneration);
  FLoading := False;
  Result := FGeneration;
end;

procedure TAtlasBoardLoadRun.Started;
begin
  FLoading := True;
end;

function TAtlasBoardLoadRun.Answered(AGeneration: Integer): Boolean;
begin
  Result := AGeneration = FGeneration;
  if Result then
  begin
    FLoading := False;
  end;
end;

end.
