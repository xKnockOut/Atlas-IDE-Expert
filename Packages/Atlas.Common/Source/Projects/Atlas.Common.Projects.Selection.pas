unit Atlas.Common.Projects.Selection;

// Gemerkte Projektwahl über Neustarts (#46): je Projekt die per
// atlas.server.selectBuild gewählte Konfiguration und Plattform, je
// Arbeitsbereich (Projektgruppe oder Ordner) das per
// atlas.server.selectProject gewählte Projekt. Abgelegt als JSON je Benutzer
// (die Komposition wählt %LOCALAPPDATA%\Atlas\projektauswahl.json):
//   {"builds": {"C:\P\App.dproj": {"config": "Debug", "platform": "Win64"}},
//    "projects": {"<Arbeitsbereich>": "C:\P\App.dproj"}}
// Schlüssel ohne Groß-/Kleinschreibung. Jede Änderung schreibt die Datei;
// fehlt sie oder ist sie kaputt, beginnt die Auswahl leer. Threadsicher.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TProjectBuildChoice = record
    Config: string;
    Platform: string;
  end;

  TProjectSelection = class
  private
    FFileName: string;
    FLock: TObject;
    FBuilds: TDictionary<string, TProjectBuildChoice>;
    FProjects: TDictionary<string, string>;
    FBuildKeys: TDictionary<string, string>;
    FScopeKeys: TDictionary<string, string>;
    procedure Save;
  public
    /// <summary>AFileName '' = nur im Speicher (Tests, CLI).</summary>
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    /// <summary>Liest den Inhalt einer Datei wie oben; ungültiger Text ergibt eine leere Auswahl.</summary>
    procedure LoadText(const AText: string);
    function ToText: string;
    /// <summary>Gemerkte Konfiguration und Plattform; False ohne.</summary>
    function Build(const AProject: string; out AChoice: TProjectBuildChoice): Boolean;
    /// <summary>Merkt Werte, die nicht leer sind; mit beiden leer wird der Eintrag entfernt.</summary>
    procedure SetBuild(const AProject, AConfig, APlatform: string);
    /// <summary>Gewähltes Projekt des Arbeitsbereichs AScope; '' ohne.</summary>
    function Project(const AScope: string): string;
    /// <summary>AProject '' hebt die Wahl auf.</summary>
    procedure SetProject(const AScope, AProject: string);
    property FileName: string read FFileName;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding;

{ TProjectSelection }

constructor TProjectSelection.Create(const AFileName: string);
var
  Data: TBytes;
  FileFormat: TFileFormat;
begin
  inherited Create;
  FFileName := AFileName;
  FLock := TObject.Create;
  FBuilds := TDictionary<string, TProjectBuildChoice>.Create;
  FProjects := TDictionary<string, string>.Create;
  FBuildKeys := TDictionary<string, string>.Create;
  FScopeKeys := TDictionary<string, string>.Create;
  if (AFileName <> '') and TFile.Exists(AFileName) then
    try
      Data := TFile.ReadAllBytes(AFileName);
      LoadText(TFileEncoding.Decode(Data, FileFormat));
    except
      // Nicht lesbar: mit leerer Auswahl weiter, die nächste Wahl schreibt die Datei neu.
      on Exception do
        LoadText('');
    end;
end;

destructor TProjectSelection.Destroy;
begin
  FScopeKeys.Free;
  FBuildKeys.Free;
  FProjects.Free;
  FBuilds.Free;
  FLock.Free;
  inherited;
end;

procedure TProjectSelection.LoadText(const AText: string);
var
  Root: TJSONValue;
  Builds, Projects, Item: TJSONObject;
  Pair: TJSONPair;
  Choice: TProjectBuildChoice;
begin
  try
    Root := TJSONObject.ParseJSONValue(AText);
  except
    on Exception do
      Root := nil;
  end;
  TMonitor.Enter(FLock);
  try
    FBuilds.Clear;
    FBuildKeys.Clear;
    FProjects.Clear;
    FScopeKeys.Clear;
    if not (Root is TJSONObject) then
      Exit;
    if TJSONObject(Root).TryGetValue<TJSONObject>('builds', Builds) then
      for Pair in Builds do
        if Pair.JsonValue is TJSONObject then
        begin
          Item := TJSONObject(Pair.JsonValue);
          Choice := Default(TProjectBuildChoice);
          Choice.Config := Item.GetValue<string>('config', '');
          Choice.Platform := Item.GetValue<string>('platform', '');
          if (Choice.Config <> '') or (Choice.Platform <> '') then
          begin
            FBuilds.AddOrSetValue(AnsiUpperCase(Pair.JsonString.Value), Choice);
            FBuildKeys.AddOrSetValue(AnsiUpperCase(Pair.JsonString.Value), Pair.JsonString.Value);
          end;
        end;
    if TJSONObject(Root).TryGetValue<TJSONObject>('projects', Projects) then
      for Pair in Projects do
        // TJSONNumber erbt von TJSONString.
        if (Pair.JsonValue is TJSONString) and not (Pair.JsonValue is TJSONNumber) and
          (Pair.JsonValue.Value <> '') then
        begin
          FProjects.AddOrSetValue(AnsiUpperCase(Pair.JsonString.Value), Pair.JsonValue.Value);
          FScopeKeys.AddOrSetValue(AnsiUpperCase(Pair.JsonString.Value), Pair.JsonString.Value);
        end;
  finally
    TMonitor.Exit(FLock);
    Root.Free;
  end;
end;

function TProjectSelection.ToText: string;
var
  Root, Builds, Projects, Item: TJSONObject;
  Key: string;
  Keys: TArray<string>;
  Choice: TProjectBuildChoice;
begin
  Root := TJSONObject.Create;
  try
    Builds := TJSONObject.Create;
    Root.AddPair('builds', Builds);
    Projects := TJSONObject.Create;
    Root.AddPair('projects', Projects);
    TMonitor.Enter(FLock);
    try
      // Feste Reihenfolge, damit die Datei bei gleicher Auswahl gleich bleibt.
      Keys := FBuilds.Keys.ToArray;
      TArray.Sort<string>(Keys);
      for Key in Keys do
      begin
        Choice := FBuilds[Key];
        Item := TJSONObject.Create;
        if Choice.Config <> '' then
          Item.AddPair('config', Choice.Config);
        if Choice.Platform <> '' then
          Item.AddPair('platform', Choice.Platform);
        Builds.AddPair(FBuildKeys[Key], Item);
      end;
      Keys := FProjects.Keys.ToArray;
      TArray.Sort<string>(Keys);
      for Key in Keys do
        Projects.AddPair(FScopeKeys[Key], FProjects[Key]);
    finally
      TMonitor.Exit(FLock);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure TProjectSelection.Save;
begin
  if FFileName = '' then
    Exit;
  try
    TDirectory.CreateDirectory(ExtractFileDir(FFileName));
    TFile.WriteAllText(FFileName, ToText, TEncoding.UTF8);
  except
    // Ohne Schreibrecht gilt die Wahl bis zum Neustart.
    on Exception do
      Exit;
  end;
end;

function TProjectSelection.Build(const AProject: string; out AChoice: TProjectBuildChoice): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FBuilds.TryGetValue(AnsiUpperCase(AProject), AChoice);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TProjectSelection.SetBuild(const AProject, AConfig, APlatform: string);
var
  Choice: TProjectBuildChoice;
  Key: string;
begin
  if AProject = '' then
    Exit;
  Key := AnsiUpperCase(AProject);
  TMonitor.Enter(FLock);
  try
    if not FBuilds.TryGetValue(Key, Choice) then
      Choice := Default(TProjectBuildChoice);
    if AConfig <> '' then
      Choice.Config := AConfig;
    if APlatform <> '' then
      Choice.Platform := APlatform;
    if (AConfig = '') and (APlatform = '') then
    begin
      FBuilds.Remove(Key);
      FBuildKeys.Remove(Key);
    end
    else
    begin
      FBuilds.AddOrSetValue(Key, Choice);
      FBuildKeys.AddOrSetValue(Key, AProject);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Save;
end;

function TProjectSelection.Project(const AScope: string): string;
begin
  TMonitor.Enter(FLock);
  try
    if not FProjects.TryGetValue(AnsiUpperCase(AScope), Result) then
      Result := '';
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TProjectSelection.SetProject(const AScope, AProject: string);
var
  Key: string;
begin
  Key := AnsiUpperCase(AScope);
  TMonitor.Enter(FLock);
  try
    if AProject = '' then
    begin
      FProjects.Remove(Key);
      FScopeKeys.Remove(Key);
    end
    else
    begin
      FProjects.AddOrSetValue(Key, AProject);
      FScopeKeys.AddOrSetValue(Key, AScope);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Save;
end;

end.
