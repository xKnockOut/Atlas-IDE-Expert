unit Atlas.IDE.Debug.VariablesWatches;

// Reiter Überwachung des Fensters „Variablen“ (#853): hält die Liste der
// überwachten Ausdrücke und ihre Ablage je Projekt (TAtlasIdeVariablesStore)
// gleich. Hinzufügen und Entfernen gehen in beide; nach einem Projektwechsel
// kommt die Liste aus der Ablage. Ohne angehaltenes Programm sind neue Zeilen
// nicht verfügbar. Jede Änderung meldet OnChanged; True heißt, es gibt neue
// Zeilen auszuwerten. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Evaluate,
  Atlas.IDE.Debug.VariablesStore;

type
  TAtlasIdeVariablesWatches = class
  private
    FStore: TAtlasIdeVariablesStore;
    FList: TAtlasEvalList;
    FOnChanged: TProc<Boolean>;
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
  end;

implementation

uses
  Atlas.Core.Debug.VariablesFlow;

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
  inherited Destroy;
end;

procedure TAtlasIdeVariablesWatches.Add(const AExpression: string; AStopped: Boolean);
var
  mNode: TAtlasEvalNode;
begin
  if not TAtlasVariablesFlow.CanAddWatch(FList, AExpression) then
  begin
    Exit;
  end;
  mNode := FList.Add(AExpression);
  FStore.Add(mNode.Expression);
  if not AStopped then
  begin
    mNode.State := TAtlasEvalState.Unavailable;
  end;
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
  // Eine laufende Auswertung dieser Zeile findet ihren Knoten nicht mehr und verfällt.
  FList.Delete(mIndex);
  FOnChanged(False);
end;

procedure TAtlasIdeVariablesWatches.Sync(AStopped: Boolean);
var
  mProject: string;
begin
  if not FStore.SwitchProject(mProject) then
  begin
    Exit;
  end;
  FList.Replace(FStore.Items(mProject));
  if not AStopped then
  begin
    FList.Unavailable;
  end;
  FOnChanged(True);
end;

end.
