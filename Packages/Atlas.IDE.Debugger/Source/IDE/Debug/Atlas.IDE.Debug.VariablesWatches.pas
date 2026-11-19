unit Atlas.IDE.Debug.VariablesWatches;

// Reiter Überwachung des Fensters „Variablen“ (#853): hält die Liste der
// überwachten Ausdrücke und ihre Ablage je Projekt (TAtlasIdeVariablesStore)
// gleich. Hinzufügen und Entfernen gehen in beide; nach einem Projektwechsel
// kommt die Liste aus der Ablage. Ohne angehaltenes Programm sind neue Zeilen
// nicht verfügbar. Jede Änderung meldet OnChanged; True heißt, es gibt neue
// Zeilen auszuwerten.
// Bindung an Klasse oder Unit (#2550, debug.variablesWindow.scopedWatches):
// Beim Halt zeigt die Liste nur die Ausdrücke, die dort gelten
// (TAtlasWatchArrange), passende gebundene zuerst; die übrigen stehen nicht in
// der Liste und werden so auch nicht ausgewertet, außer ShowHidden ist an.
// Ohne Halt stehen alle da. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.WatchScopes,
  Atlas.IDE.Debug.VariablesStore;

type
  TAtlasIdeVariablesWatches = class
  private
    FStore: TAtlasIdeVariablesStore;
    FList: TAtlasEvalList;
    FOnChanged: TProc<Boolean>;
    FProject: string;
    FPlace: TAtlasWatchPlace;
    /// <summary>FPlace gehört zu einem Halt; ohne Halt zeigt die Liste alles.</summary>
    FAtStop: Boolean;
    FShowHidden: Boolean;
    FHidden: Integer;
    /// <summary>Stand der Ablage beim letzten Ordnen, für ScopeOf.</summary>
    FWatches: TAtlasScopedWatches;
    /// <summary>Liste nach Ablage, Ort und Einstellung neu ordnen; AStopped: Programm angehalten.</summary>
    procedure Arrange(AStopped: Boolean);
  public
    /// <summary>AList ist die Liste des Reiters und gehört dem Aufrufer; AOnChanged mit True, wenn neue Zeilen
    /// auszuwerten sind.</summary>
    constructor Create(AList: TAtlasEvalList; const AOnChanged: TProc<Boolean>);
    destructor Destroy; override;
    /// <summary>AExpression überwachen, wenn er gültig und noch nicht darin ist; AStopped: Programm angehalten.
    /// </summary>
    procedure Add(const AExpression: string; AStopped: Boolean);
    /// <summary>Zeile ANode nicht mehr überwachen; nichts, wenn sie nicht in der Liste steht.</summary>
    procedure Remove(ANode: TAtlasEvalNode);
    /// <summary>Anderes Projekt als zuletzt: Liste aus der Ablage neu füllen.</summary>
    procedure Sync(AStopped: Boolean);
    /// <summary>Neuer Halt an APlace: Liste ordnen, ohne OnChanged (der Aufrufer wertet danach aus).</summary>
    procedure Stopped(const APlace: TAtlasWatchPlace);
    /// <summary>Kein Halt mehr: alle Ausdrücke zeigen.</summary>
    procedure Ended;
    /// <summary>Zeile ANode an Klasse bzw. Unit des Halts binden oder (Everywhere) lösen; AStopped wie bei Add.
    /// </summary>
    procedure Bind(ANode: TAtlasEvalNode; AKind: TAtlasWatchScopeKind; AStopped: Boolean);
    /// <summary>Lässt sich eine Zeile jetzt an AKind binden (Einstellung an, Halt mit Klasse bzw. Unit)?</summary>
    function CanBind(AKind: TAtlasWatchScopeKind): Boolean;
    /// <summary>Ausgeblendete zeigen oder nicht.</summary>
    procedure SetShowHidden(AValue: Boolean; AStopped: Boolean);
    /// <summary>Bindung der Zeile ANode; Everywhere bei Kindern und Unbekanntem.</summary>
    function ScopeOf(ANode: TAtlasEvalNode): TAtlasWatchScope;
    /// <summary>debug.variablesWindow.scopedWatches an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>So viele Ausdrücke sind beim aktuellen Halt ausgeblendet.</summary>
    property Hidden: Integer read FHidden;
    property ShowHidden: Boolean read FShowHidden;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Debug.VariablesFlow,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeVariablesWatches }

constructor TAtlasIdeVariablesWatches.Create(AList: TAtlasEvalList; const AOnChanged: TProc<Boolean>);
begin
  inherited Create;
  FList := AList;
  FOnChanged := AOnChanged;
  FStore := TAtlasIdeVariablesStore.Create;
end;

destructor TAtlasIdeVariablesWatches.Destroy;
begin
  FreeAndNil(FStore);
  FList := nil;
  FOnChanged := nil;
  FProject := '';
  FPlace := Default(TAtlasWatchPlace);
  FWatches := nil;
  inherited Destroy;
end;

class function TAtlasIdeVariablesWatches.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DebugVariablesScopedWatches;
end;

procedure TAtlasIdeVariablesWatches.Arrange(AStopped: Boolean);
var
  mArrangement: TAtlasWatchArrangement;
begin
  // Ohne Halt alles zeigen: Gebundene lassen sich dann sehen und entfernen.
  FWatches := FStore.Items(FProject);
  mArrangement := TAtlasWatchArrange.Arrange(FWatches, FPlace, Enabled and FAtStop, FShowHidden);
  FHidden := mArrangement.Hidden;
  // Gleiche Ausdrücke behalten Knoten und Wert; neue kommen offen dazu.
  FList.Replace(mArrangement.Expressions);
  if not AStopped then
  begin
    FList.Unavailable;
  end;
end;

procedure TAtlasIdeVariablesWatches.Add(const AExpression: string; AStopped: Boolean);
begin
  if not TAtlasVariablesFlow.CanAddWatch(FList, AExpression) then
  begin
    Exit;
  end;
  FStore.Add(AExpression);
  // Schon in der Ablage, aber hier ausgeblendet: Wer ihn hier eingibt, will ihn hier sehen.
  FStore.SetScope(AExpression, TAtlasWatchScope.Everywhere);
  Arrange(AStopped);
  FOnChanged(True);
end;

procedure TAtlasIdeVariablesWatches.Remove(ANode: TAtlasEvalNode);
var
  mIndex: Integer;
begin
  mIndex := FList.IndexOf(ANode);
  if mIndex < 0 then
  begin
    Exit;
  end;
  FStore.Remove(ANode.Expression);
  FWatches := FStore.Items(FProject);
  // Eine laufende Auswertung dieser Zeile findet ihren Knoten nicht mehr und verfällt.
  FList.Delete(mIndex);
  FOnChanged(False);
end;

procedure TAtlasIdeVariablesWatches.Sync(AStopped: Boolean);
begin
  if not FStore.SwitchProject(FProject) then
  begin
    Exit;
  end;
  Arrange(AStopped);
  FOnChanged(True);
end;

procedure TAtlasIdeVariablesWatches.Stopped(const APlace: TAtlasWatchPlace);
begin
  FPlace := APlace;
  FAtStop := True;
  Arrange(True);
end;

procedure TAtlasIdeVariablesWatches.Ended;
begin
  FPlace := Default(TAtlasWatchPlace);
  FAtStop := False;
  Arrange(False);
end;

procedure TAtlasIdeVariablesWatches.Bind(ANode: TAtlasEvalNode; AKind: TAtlasWatchScopeKind; AStopped: Boolean);
begin
  if (ANode = nil) or (ANode.Parent <> nil) or (FList.IndexOf(ANode) < 0) or
    ((AKind <> TAtlasWatchScopeKind.Everywhere) and not CanBind(AKind)) then
  begin
    Exit;
  end;
  FStore.SetScope(ANode.Expression, FPlace.ScopeOf(AKind));
  Arrange(AStopped);
  FOnChanged(True);
end;

function TAtlasIdeVariablesWatches.CanBind(AKind: TAtlasWatchScopeKind): Boolean;
begin
  Result := Enabled and FAtStop and (FPlace.ScopeOf(AKind).Kind = AKind);
end;

procedure TAtlasIdeVariablesWatches.SetShowHidden(AValue: Boolean; AStopped: Boolean);
begin
  if FShowHidden = AValue then
  begin
    Exit;
  end;
  FShowHidden := AValue;
  Arrange(AStopped);
  FOnChanged(True);
end;

function TAtlasIdeVariablesWatches.ScopeOf(ANode: TAtlasEvalNode): TAtlasWatchScope;
var
  mWatch: TAtlasScopedWatch;
begin
  Result := TAtlasWatchScope.Everywhere;
  if (ANode = nil) or (ANode.Parent <> nil) then
  begin
    Exit;
  end;
  for mWatch in FWatches do
  begin
    if mWatch.Expression = ANode.Expression then
    begin
      Exit(mWatch.Scope);
    end;
  end;
end;

end.
