unit Atlas.IDE.Debug.VariablesStore;

// Überwachungsliste des Fensters „Variablen“ (#853): cLimit Ausdrücke je
// Projekt in %LOCALAPPDATA%\Atlas\debug-variables-watches.json, gelesen beim
// ersten Zugriff. Ist die Datei gesperrt, beginnt Atlas leer und überschreibt
// sie nicht. Projekt wie im Fenster „Auswerten“: beim Debuggen das
// gestartete, sonst das aktive. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.DialogCompletion;

type
  TAtlasIdeVariablesStore = class
  public const
    cLimit = 100;
    cFileName = 'debug-variables-watches.json';
  private
    FWatches: TAtlasExpressionHistory;
    FLoaded: Boolean;
    FWritable: Boolean;
    FProject: string;
    procedure Load;
    procedure Save;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ist das aktuelle Projekt ein anderes als beim letzten Aufruf? AProject: das aktuelle.</summary>
    function SwitchProject(out AProject: string): Boolean;
    /// <summary>Überwachte Ausdrücke von AProject in der Reihenfolge, in der sie dazukamen.</summary>
    function Items(const AProject: string): TArray<string>;
    procedure Add(const AExpression: string);
    procedure Remove(const AExpression: string);
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.UI.Debug.Strings;

/// <summary>Was in der Datei steht, für die Meldung, wenn sie sich nicht schreiben lässt.</summary>
function What: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.VariablesWatchesKind);
end;

{ TAtlasIdeVariablesStore }

constructor TAtlasIdeVariablesStore.Create;
begin
  inherited Create;
  FWatches := TAtlasExpressionHistory.Create(cLimit);
end;

destructor TAtlasIdeVariablesStore.Destroy;
begin
  FreeAndNil(FWatches);
  FProject := '';
  inherited Destroy;
end;

procedure TAtlasIdeVariablesStore.Load;
begin
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  FWritable := TAtlasIdeEvaluateStore.LoadFile(FWatches, cFileName, What);
end;

procedure TAtlasIdeVariablesStore.Save;
begin
  TAtlasIdeEvaluateStore.SaveFile(FWatches, cFileName, What, FWritable);
end;

function TAtlasIdeVariablesStore.SwitchProject(out AProject: string): Boolean;
begin
  Load;
  AProject := TAtlasIdeEvaluateStore.CurrentProject;
  Result := not SameText(AProject, FProject) or (FProject = '');
  FProject := AProject;
end;

function TAtlasIdeVariablesStore.Items(const AProject: string): TArray<string>;
var
  mNewest: TArray<string>;
  mIndex: Integer;
begin
  Load;
  // Die Liste führt den jüngsten zuerst; das Fenster zeigt sie in der Reihenfolge des Hinzufügens.
  mNewest := FWatches.Items(AProject);
  SetLength(Result, Length(mNewest));
  for mIndex := 0 to High(mNewest) do
  begin
    Result[High(mNewest) - mIndex] := mNewest[mIndex];
  end;
end;

procedure TAtlasIdeVariablesStore.Add(const AExpression: string);
begin
  Load;
  if FWatches.Add(TAtlasIdeEvaluateStore.CurrentProject, AExpression) then
  begin
    Save;
  end;
end;

procedure TAtlasIdeVariablesStore.Remove(const AExpression: string);
begin
  Load;
  if FWatches.Remove(TAtlasIdeEvaluateStore.CurrentProject, AExpression) then
  begin
    Save;
  end;
end;

end.
