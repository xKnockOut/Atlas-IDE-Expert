unit Atlas.IDE.Debug.EvaluateStore;

// Verlauf und festgeheftete Ausdrücke des Fensters „Auswerten“ (#784):
//   - Verlauf: die letzten HistoryLimit Ausdrücke je Projekt in
//     %LOCALAPPDATA%\Atlas\debug-evaluate-history.json.
//   - Festgeheftet: PinnedLimit Ausdrücke je Projekt in
//     %LOCALAPPDATA%\Atlas\debug-evaluate-pinned.json.
//   - Projekt: beim Debuggen das gestartete, sonst das aktive.
//   - Beide Dateien werden beim ersten Zugriff gelesen. Ist eine gesperrt,
//     beginnt Atlas leer und überschreibt sie nicht (TAtlasDataFile).
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.DialogCompletion;

type
  TAtlasIdeEvaluateStore = class
  public const
    HistoryLimit = 50;
    PinnedLimit = 100;
    HistoryFileName = 'debug-evaluate-history.json';
    PinnedFileName = 'debug-evaluate-pinned.json';
  private
    FHistory: TAtlasExpressionHistory;
    FPinned: TAtlasExpressionHistory;
    FLoaded: Boolean;
    FHistoryKept: Boolean;
    FPinnedKept: Boolean;
    FProject: string;
    procedure Load;
    procedure SavePinned;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Beim Debuggen das gestartete Projekt, sonst das aktive; '' ohne.</summary>
    class function CurrentProject: string; static;
    /// <summary>Verlauf des aktuellen Projekts, jüngster zuerst.</summary>
    function HistoryItems: TArray<string>;
    /// <summary>Festgeheftete Ausdrücke von AProject, jüngster zuerst.</summary>
    function PinnedItems(const AProject: string): TArray<string>;
    /// <summary>Ist das aktuelle Projekt ein anderes als beim letzten Aufruf? AProject: das aktuelle.</summary>
    function SwitchProject(out AProject: string): Boolean;
    /// <summary>AExpression in den Verlauf des aktuellen Projekts.</summary>
    procedure Remember(const AExpression: string);
    procedure Pin(const AExpression: string);
    procedure Unpin(const AExpression: string);
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Debug.Session;

const
  cHistoryWhat = 'Verlauf des Fensters „Auswerten“';
  cPinnedWhat = 'Festgeheftete Ausdrücke';

function StoreFile(const AName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), AName);
end;

/// <summary>AStore nach AFileName schreiben; AKept: Datei gesperrt, nicht überschreiben.</summary>
procedure SaveStore(AStore: TAtlasExpressionHistory; const AFileName, AWhat: string; AKept: Boolean);
begin
  if AKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(StoreFile(AFileName), AStore.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(AWhat, E);
  end;
end;

{ TAtlasIdeEvaluateStore }

constructor TAtlasIdeEvaluateStore.Create;
begin
  inherited Create;
  FHistory := TAtlasExpressionHistory.Create(HistoryLimit);
  FPinned := TAtlasExpressionHistory.Create(PinnedLimit);
end;

destructor TAtlasIdeEvaluateStore.Destroy;
begin
  FreeAndNil(FPinned);
  FreeAndNil(FHistory);
  FProject := '';
  inherited Destroy;
end;

class function TAtlasIdeEvaluateStore.CurrentProject: string;
var
  mProject: IOTAProject;
begin
  Result := TAtlasIdeDebugSession.LaunchProject;
  if Result <> '' then
  begin
    Exit;
  end;
  mProject := GetActiveProject;
  if mProject <> nil then
  begin
    Result := mProject.FileName;
  end;
end;

procedure TAtlasIdeEvaluateStore.Load;
begin
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert ohne Pfad.
  FHistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile(HistoryFileName), cHistoryWhat,
    function(const AText: string): Boolean
    begin
      Result := FHistory.LoadFromText(AText);
    end));
  FPinnedKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile(PinnedFileName), cPinnedWhat,
    function(const AText: string): Boolean
    begin
      Result := FPinned.LoadFromText(AText);
    end));
end;

procedure TAtlasIdeEvaluateStore.SavePinned;
begin
  SaveStore(FPinned, PinnedFileName, cPinnedWhat, FPinnedKept);
end;

function TAtlasIdeEvaluateStore.HistoryItems: TArray<string>;
begin
  Load;
  Result := FHistory.Items(CurrentProject);
end;

function TAtlasIdeEvaluateStore.PinnedItems(const AProject: string): TArray<string>;
begin
  Load;
  Result := FPinned.Items(AProject);
end;

function TAtlasIdeEvaluateStore.SwitchProject(out AProject: string): Boolean;
begin
  Load;
  AProject := CurrentProject;
  Result := not SameText(AProject, FProject) or (FProject = '');
  FProject := AProject;
end;

procedure TAtlasIdeEvaluateStore.Remember(const AExpression: string);
begin
  Load;
  if FHistory.Add(CurrentProject, AExpression) then
  begin
    SaveStore(FHistory, HistoryFileName, cHistoryWhat, FHistoryKept);
  end;
end;

procedure TAtlasIdeEvaluateStore.Pin(const AExpression: string);
begin
  Load;
  if FPinned.Add(CurrentProject, AExpression) then
  begin
    SavePinned;
  end;
end;

procedure TAtlasIdeEvaluateStore.Unpin(const AExpression: string);
begin
  Load;
  if FPinned.Remove(CurrentProject, AExpression) then
  begin
    SavePinned;
  end;
end;

end.
