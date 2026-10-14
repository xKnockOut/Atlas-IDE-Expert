unit Atlas.Common.Lsp.IdeProject;

// Projektkontext aus der IDE (#396). In der IDE bestimmt die IDE, welche
// Konfiguration und Plattform ein Projekt hat und welche Suchpfade,
// bedingten Symbole und Unit-Namespaces gelten, auch wenn die Optionen noch
// nicht gespeichert sind. Das IDE-Plugin meldet das je Projekt
// - in initialize unter initializationOptions.projectContexts (vor dem
//   ersten Laden der Projekte) und
// - danach bei jeder Änderung als atlas/projectContext.
// Der Server liest die .dproj weiter selbst (Units, Hauptdatei), nimmt aber
// Konfiguration und Plattform der IDE und ersetzt Symbole, Suchpfade und
// Namespaces durch die der IDE. Die Werte kommen roh aus den Projektoptionen;
// $(Name) löst der Server mit den Variablen der Installation auf, relative
// Pfade gelten ab dem Projektordner. Ohne Plugin (CLI, MCP) bleibt es beim
// Lesen der .dproj (#14).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Projects.Contract;

type
  TIdeProjectContext = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    /// <summary>Version der laufenden IDE, z. B. "23.0" (#47); '' = vom Server gewählt.</summary>
    BdsVersion: string;
    /// <summary>Symbole, Suchpfade und Namespaces gemeldet; sonst gelten die der .dproj.</summary>
    HasOptions: Boolean;
    Defines: TArray<string>;
    SearchPaths: TArray<string>;
    Namespaces: TArray<string>;
    /// <summary>Bibliothekspfade der IDE für die Plattform; leer = aus der Registry der Installation.</summary>
    LibraryPaths: TArray<string>;
    /// <summary>Kontext aus einem JSON-Objekt; Project = '' bei ungültigen Parametern.</summary>
    class function FromJson(const AValue: TJSONValue): TIdeProjectContext; static;
    /// <summary>Vergleichsschlüssel: gleich, wenn sich für den Server nichts ändert.</summary>
    function Key: string;
    /// <summary>Übernimmt Symbole, Suchpfade und Namespaces in AProject ($(Name) mit AVariables,
    /// Pfade ab dem Projektordner, ohne Doppelte).</summary>
    procedure ApplyTo(var AProject: TProjectInfo; const AVariables: TArray<TPair<string, string>>);
    /// <summary>Bibliothekspfade mit aufgelösten Variablen ($(Platform) aus AProject), ohne Doppelte.</summary>
    function ExpandedLibraryPaths(const AProject: TProjectInfo;
      const AVariables: TArray<TPair<string, string>>): TArray<string>;
  end;

  TIdeProjectChangedEvent = reference to procedure(const AContext: TIdeProjectContext);

  TLspIdeProject = class
  public const
    Method = 'atlas/projectContext';
  private
    FLock: TObject;
    FContexts: TDictionary<string, TIdeProjectContext>;
    FOnChanged: TIdeProjectChangedEvent;
    procedure HandleNotification(const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Kontexte aus den Parametern von initialize (initializationOptions.projectContexts).</summary>
    procedure LoadInitialize(const AParams: TJSONValue);
    /// <summary>Merkt sich AContext; True, wenn er neu ist oder sich geändert hat. Threadsicher.</summary>
    function Update(const AContext: TIdeProjectContext): Boolean;
    /// <summary>Gemeldeter Kontext des Projekts AProjectFile; False ohne. Threadsicher.</summary>
    function Find(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean;
    /// <summary>Nach atlas/projectContext mit geändertem Kontext (Thread des Dispatchers).</summary>
    property OnChanged: TIdeProjectChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Projects.Paths;

function StringsOf(AObject: TJSONObject; const AName: string; out AFound: Boolean): TArray<string>;
var
  Items: TJSONArray;
  Item: TJSONValue;
begin
  Result := nil;
  AFound := AObject.TryGetValue<TJSONArray>(AName, Items);
  if not AFound then
    Exit;
  for Item in Items do
    if (Item is TJSONString) and (Trim(Item.Value) <> '') then
      Result := Result + [Trim(Item.Value)];
end;

function WithTarget(const AVariables: TArray<TPair<string, string>>; const AProject: TProjectInfo):
  TArray<TPair<string, string>>;
begin
  Result := AVariables + [TPair<string, string>.Create('Platform', AProject.Platform),
    TPair<string, string>.Create('Config', AProject.Config),
    TPair<string, string>.Create('MSBuildProjectDirectory', TProjectPaths.DirectoryOf(AProject.FileName)),
    TPair<string, string>.Create('MSBuildProjectName', TProjectPaths.BaseName(AProject.FileName))];
end;

function UniquePaths(const ABase: string; const AItems: TArray<string>;
  const AVariables: TArray<TPair<string, string>>): TArray<string>;
var
  Known: TList<string>;
  Item, Path: string;
begin
  Result := nil;
  Known := TList<string>.Create;
  try
    for Item in AItems do
    begin
      Path := TProjectPaths.ExpandVariables(Item, AVariables);
      // Verweis auf den geerbten Wert, den die IDE nicht aufgelöst hat: kein Pfad.
      if Pos('$(', Path) > 0 then
        Continue;
      Path := TProjectPaths.Combine(ABase, Path);
      if Known.Contains(LowerCase(Path)) then
        Continue;
      Known.Add(LowerCase(Path));
      Result := Result + [Path];
    end;
  finally
    Known.Free;
  end;
end;

{ TIdeProjectContext }

class function TIdeProjectContext.FromJson(const AValue: TJSONValue): TIdeProjectContext;
var
  Item: TJSONObject;
  HasDefines, HasPaths, HasNamespaces, Ignored: Boolean;
begin
  Result := Default(TIdeProjectContext);
  if not (AValue is TJSONObject) then
    Exit;
  Item := TJSONObject(AValue);
  Result.Project := Item.GetValue<string>('project', '');
  Result.Configuration := Item.GetValue<string>('configuration', '');
  Result.Platform := Item.GetValue<string>('platform', '');
  Result.BdsVersion := Item.GetValue<string>('bdsVersion', '');
  Result.Defines := StringsOf(Item, 'defines', HasDefines);
  Result.SearchPaths := StringsOf(Item, 'searchPaths', HasPaths);
  Result.Namespaces := StringsOf(Item, 'namespaces', HasNamespaces);
  Result.HasOptions := HasDefines or HasPaths or HasNamespaces;
  Result.LibraryPaths := StringsOf(Item, 'libraryPaths', Ignored);
end;

function TIdeProjectContext.Key: string;
begin
  Result := AnsiUpperCase(Project) + '|' + Configuration + '|' + Platform + '|' + BdsVersion + '|' +
    BoolToStr(HasOptions, True) + '|' + string.Join(';', Defines) + '|' + string.Join(';', SearchPaths) + '|' +
    string.Join(';', Namespaces) + '|' + string.Join(';', LibraryPaths);
end;

procedure TIdeProjectContext.ApplyTo(var AProject: TProjectInfo; const AVariables: TArray<TPair<string, string>>);
var
  Variables: TArray<TPair<string, string>>;
  Define, Upper: string;
  Namespace: string;
begin
  if not HasOptions then
    Exit;
  Variables := WithTarget(AVariables, AProject);
  AProject.Defines := nil;
  for Define in Defines do
  begin
    Upper := UpperCase(Trim(TProjectPaths.ExpandVariables(Define, Variables)));
    // Unaufgelöster Verweis wie $(DCC_Define): kein Symbol.
    if (Upper = '') or (Pos('$(', Upper) > 0) or (IndexStr(Upper, AProject.Defines) >= 0) then
      Continue;
    AProject.Defines := AProject.Defines + [Upper];
  end;
  AProject.SearchPaths := UniquePaths(TProjectPaths.DirectoryOf(AProject.FileName), SearchPaths, Variables);
  AProject.Namespaces := nil;
  for Namespace in Namespaces do
    if (Pos('$(', Namespace) = 0) and (IndexText(Namespace, AProject.Namespaces) < 0) then
      AProject.Namespaces := AProject.Namespaces + [Namespace];
end;

function TIdeProjectContext.ExpandedLibraryPaths(const AProject: TProjectInfo;
  const AVariables: TArray<TPair<string, string>>): TArray<string>;
begin
  Result := UniquePaths('', LibraryPaths, WithTarget(AVariables, AProject));
end;

{ TLspIdeProject }

constructor TLspIdeProject.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FContexts := TDictionary<string, TIdeProjectContext>.Create;
end;

destructor TLspIdeProject.Destroy;
begin
  FContexts.Free;
  FLock.Free;
  inherited;
end;

procedure TLspIdeProject.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(Method, HandleNotification);
end;

procedure TLspIdeProject.LoadInitialize(const AParams: TJSONValue);
var
  Options: TJSONObject;
  Items: TJSONArray;
  Item: TJSONValue;
  Context: TIdeProjectContext;
begin
  if not ((AParams is TJSONObject) and
    TJSONObject(AParams).TryGetValue<TJSONObject>('initializationOptions', Options) and
    Options.TryGetValue<TJSONArray>('projectContexts', Items)) then
    Exit;
  for Item in Items do
  begin
    Context := TIdeProjectContext.FromJson(Item);
    if Context.Project <> '' then
      Update(Context);
  end;
end;

function TLspIdeProject.Update(const AContext: TIdeProjectContext): Boolean;
var
  Known: TIdeProjectContext;
  Key: string;
begin
  Key := AnsiUpperCase(AContext.Project);
  TMonitor.Enter(FLock);
  try
    Result := not FContexts.TryGetValue(Key, Known) or (Known.Key <> AContext.Key);
    if Result then
      FContexts.AddOrSetValue(Key, AContext);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspIdeProject.Find(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FContexts.TryGetValue(AnsiUpperCase(AProjectFile), AContext);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspIdeProject.HandleNotification(const AParams: TJSONValue);
var
  Context: TIdeProjectContext;
begin
  Context := TIdeProjectContext.FromJson(AParams);
  if (Context.Project = '') or not Update(Context) then
    Exit;
  if Assigned(FOnChanged) then
    FOnChanged(Context);
end;

end.
