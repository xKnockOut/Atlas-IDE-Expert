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
    procedure LoadBuilds(ABuilds: TJSONObject);
    procedure LoadProjects(AProjects: TJSONObject);
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
  Atlas.Common.Documents.FileEncoding;

{ TProjectSelection }

constructor TProjectSelection.Create(const AFileName: string);
var
  mData: TBytes;
  mFileFormat: TFileFormat;
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
      mData := TFile.ReadAllBytes(AFileName);
      LoadText(TFileEncoding.Decode(mData, mFileFormat));
    except
      // Nicht lesbar: mit leerer Auswahl weiter, die nächste Wahl schreibt die Datei neu.
      // lsp-ignore: catch-all-without-raise -- Auswahldatei unlesbar heißt keine Auswahl
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

procedure TProjectSelection.LoadBuilds(ABuilds: TJSONObject);
var
  mPair: TJSONPair;
  mItem: TJSONObject;
  mChoice: TProjectBuildChoice;
begin
  for mPair in ABuilds do
  begin
    if not (mPair.JsonValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mPair.JsonValue);
    mChoice := Default(TProjectBuildChoice);
    mChoice.Config := mItem.GetValue<string>('config', '');
    mChoice.Platform := mItem.GetValue<string>('platform', '');
    if (mChoice.Config <> '') or (mChoice.Platform <> '') then
    begin
      FBuilds.AddOrSetValue(AnsiUpperCase(mPair.JsonString.Value), mChoice);
      FBuildKeys.AddOrSetValue(AnsiUpperCase(mPair.JsonString.Value), mPair.JsonString.Value);
    end;
  end;
end;

procedure TProjectSelection.LoadProjects(AProjects: TJSONObject);
var
  mPair: TJSONPair;
begin
  for mPair in AProjects do
  begin
    // TJSONNumber erbt von TJSONString.
    if (mPair.JsonValue is TJSONString) and not (mPair.JsonValue is TJSONNumber) and
      (mPair.JsonValue.Value <> '') then
    begin
      FProjects.AddOrSetValue(AnsiUpperCase(mPair.JsonString.Value), mPair.JsonValue.Value);
      FScopeKeys.AddOrSetValue(AnsiUpperCase(mPair.JsonString.Value), mPair.JsonString.Value);
    end;
  end;
end;

procedure TProjectSelection.LoadText(const AText: string);
var
  mRoot: TJSONValue;
  mBuilds, mProjects: TJSONObject;
begin
  try
    mRoot := TJSONObject.ParseJSONValue(AText);
  except
    // lsp-ignore: catch-all-without-raise -- Auswahldatei unlesbar heißt keine Auswahl
    on Exception do
      mRoot := nil;
  end;
  TMonitor.Enter(FLock);
  try
    FBuilds.Clear;
    FBuildKeys.Clear;
    FProjects.Clear;
    FScopeKeys.Clear;
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    if TJSONObject(mRoot).TryGetValue<TJSONObject>('builds', mBuilds) then
    begin
      LoadBuilds(mBuilds);
    end;
    if TJSONObject(mRoot).TryGetValue<TJSONObject>('projects', mProjects) then
    begin
      LoadProjects(mProjects);
    end;
  finally
    TMonitor.Exit(FLock);
    mRoot.Free;
  end;
end;

function TProjectSelection.ToText: string;
var
  mRoot, mBuilds, mProjects, mItem: TJSONObject;
  mKey: string;
  mKeys: TArray<string>;
  mChoice: TProjectBuildChoice;
begin
  mRoot := TJSONObject.Create;
  try
    mBuilds := TJSONObject.Create;
    mRoot.AddPair('builds', mBuilds);
    mProjects := TJSONObject.Create;
    mRoot.AddPair('projects', mProjects);
    TMonitor.Enter(FLock);
    try
      // Feste Reihenfolge, damit die Datei bei gleicher Auswahl gleich bleibt.
      mKeys := FBuilds.Keys.ToArray;
      TArray.Sort<string>(mKeys);
      for mKey in mKeys do
      begin
        mChoice := FBuilds[mKey];
        mItem := TJSONObject.Create;
        if mChoice.Config <> '' then
        begin
          mItem.AddPair('config', mChoice.Config);
        end;
        if mChoice.Platform <> '' then
        begin
          mItem.AddPair('platform', mChoice.Platform);
        end;
        mBuilds.AddPair(FBuildKeys[mKey], mItem);
      end;
      mKeys := FProjects.Keys.ToArray;
      TArray.Sort<string>(mKeys);
      for mKey in mKeys do
      begin
        mProjects.AddPair(FScopeKeys[mKey], FProjects[mKey]);
      end;
    finally
      TMonitor.Exit(FLock);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

procedure TProjectSelection.Save;
begin
  if FFileName = '' then
  begin
    Exit;
  end;
  try
    TDirectory.CreateDirectory(ExtractFileDir(FFileName));
    TFile.WriteAllText(FFileName, ToText, TEncoding.UTF8);
  except
    // Ohne Schreibrecht gilt die Wahl bis zum Neustart.
    // lsp-ignore: catch-all-without-raise -- Auswahldatei unlesbar heißt keine Auswahl
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
  mChoice: TProjectBuildChoice;
  mKey: string;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  mKey := AnsiUpperCase(AProject);
  TMonitor.Enter(FLock);
  try
    if not FBuilds.TryGetValue(mKey, mChoice) then
    begin
      mChoice := Default(TProjectBuildChoice);
    end;
    if AConfig <> '' then
    begin
      mChoice.Config := AConfig;
    end;
    if APlatform <> '' then
    begin
      mChoice.Platform := APlatform;
    end;
    if (AConfig = '') and (APlatform = '') then
    begin
      FBuilds.Remove(mKey);
      FBuildKeys.Remove(mKey);
    end
    else
    begin
      FBuilds.AddOrSetValue(mKey, mChoice);
      FBuildKeys.AddOrSetValue(mKey, AProject);
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
    begin
      Result := '';
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TProjectSelection.SetProject(const AScope, AProject: string);
var
  mKey: string;
begin
  mKey := AnsiUpperCase(AScope);
  TMonitor.Enter(FLock);
  try
    if AProject = '' then
    begin
      FProjects.Remove(mKey);
      FScopeKeys.Remove(mKey);
    end
    else
    begin
      FProjects.AddOrSetValue(mKey, AProject);
      FScopeKeys.AddOrSetValue(mKey, AScope);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Save;
end;

end.
