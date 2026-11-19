unit Atlas.IDE.Debug.VariablesStore;

// Überwachungsliste des Fensters „Variablen“ (#853): cLimit Ausdrücke je
// Projekt samt Bindung an Klasse oder Unit (#2550, TAtlasWatchStore) in
// %LOCALAPPDATA%\Atlas\debug-variables-watches.json, gelesen beim ersten
// Zugriff. Ist die Datei gesperrt, beginnt Atlas leer und überschreibt sie
// nicht. Projekt wie im Fenster „Auswerten“: beim Debuggen das gestartete,
// sonst das aktive. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.WatchScopes,
  Atlas.Core.Debug.WatchStore;

type
  TAtlasIdeVariablesStore = class
  public const
    /// <summary>Gebundene Ausdrücke sammeln sich je Klasse an: doppelt so viele wie ohne Bindung (#2550).
    /// </summary>
    cLimit = 200;
    cFileName = 'debug-variables-watches.json';
  private
    FWatches: TAtlasWatchStore;
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
    function Items(const AProject: string): TAtlasScopedWatches;
    /// <summary>Neuer Ausdruck, gilt überall.</summary>
    procedure Add(const AExpression: string);
    procedure Remove(const AExpression: string);
    /// <summary>Bindung eines Ausdrucks ändern (#2550).</summary>
    procedure SetScope(const AExpression: string; const AScope: TAtlasWatchScope);
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.UI.Debug.VariablesStrings;

/// <summary>Was in der Datei steht, für die Meldung, wenn sie sich nicht schreiben lässt.</summary>
function What: string;
begin
  Result := TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesWatchesKind);
end;

{ TAtlasIdeVariablesStore }

constructor TAtlasIdeVariablesStore.Create;
begin
  inherited Create;
  FWatches := TAtlasWatchStore.Create(cLimit);
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
  FWritable := TAtlasIdeEvaluateStore.LoadText(cFileName, What,
    function(const AText: string): Boolean
    begin
      Result := FWatches.LoadFromText(AText);
    end);
end;

procedure TAtlasIdeVariablesStore.Save;
begin
  if FWritable then
  begin
    TAtlasIdeEvaluateStore.SaveText(cFileName, What, FWatches.ToText, FWritable);
  end;
end;

function TAtlasIdeVariablesStore.SwitchProject(out AProject: string): Boolean;
begin
  Load;
  AProject := TAtlasIdeEvaluateStore.CurrentProject;
  Result := not SameText(AProject, FProject) or (FProject = '');
  FProject := AProject;
end;

function TAtlasIdeVariablesStore.Items(const AProject: string): TAtlasScopedWatches;
begin
  Load;
  Result := FWatches.Items(AProject);
end;

procedure TAtlasIdeVariablesStore.Add(const AExpression: string);
begin
  Load;
  if FWatches.Add(TAtlasIdeEvaluateStore.CurrentProject, AExpression, TAtlasWatchScope.Everywhere) then
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

procedure TAtlasIdeVariablesStore.SetScope(const AExpression: string; const AScope: TAtlasWatchScope);
begin
  Load;
  if FWatches.SetScope(TAtlasIdeEvaluateStore.CurrentProject, AExpression, AScope) then
  begin
    Save;
  end;
end;

end.
