unit Atlas.IDE.Welcome.Search;

// Suchfeld der Willkommensseite in der IDE (#760): sammelt die Kandidaten
// und öffnet den gewählten Treffer.
// - Projekte: Favoriten und zuletzt geöffnete Projekte der IDE (Registry
//   <Basis>\Closed Projects, Werte File_0 …), dazu Projekte mit Index-Cache.
// - Dateien: Units dieser Projekte aus dem Index-Cache auf der Platte
//   (%LOCALAPPDATA%\Atlas\Index, #16), ohne Server; der Ordner wird höchstens
//   alle fünf Sekunden neu durchsucht, gelesen werden nur geänderte Caches.
// - Symbole: workspace/symbol (#20/#400) nur, wenn schon eine Sitzung läuft;
//   es wird kein Server gestartet, sonst steht dort ein Hinweis.
// - Befehle: die Atlas-Befehle der Palette (#399, #502).
// Enter auf Datei oder Symbol öffnet zuerst das Projekt (wenn es noch nicht
// offen ist), dann die Datei an der Stelle. Die Taste (welcomePage.search.key,
// Vorgabe Strg+E) setzt den Fokus ins Suchfeld, solange eine
// Willkommensseite mit Suchfeld sichtbar im aktiven Fenster steht; sonst
// bleibt sie der IDE (inkrementelle Suche im Editor).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.AppEvnts,
  Winapi.Windows,
  Winapi.Messages,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Welcome.IndexFiles,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Search;

type
  TAtlasIdeWelcomeSearch = class
  private const
    RefreshMs = 5000;
    SymbolTimeoutMs = 2000;
  private
    FCommands: TFunc<TArray<TAtlasCommand>>;
    FRun: TProc<string>;
    FIndex: TAtlasIndexProjects;
    FRefreshed: UInt64;
    FBoxes: TList<TAtlasWelcomeSearchBox>;
    FWatch: TComponent;
    FEvents: TApplicationEvents;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    function Candidates(const APattern: string; out ASymbolHint: string): TArray<TAtlasWelcomeHit>;
    function ProjectFiles: TArray<string>;
    function ActiveBox: TAtlasWelcomeSearchBox;
  public
    /// <summary>ACommands: Atlas-Befehle der Palette; ARun führt einen davon aus.</summary>
    constructor Create(const ACommands: TFunc<TArray<TAtlasCommand>>; const ARun: TProc<string>);
    destructor Destroy; override;
    /// <summary>Suchfeld anbinden (Abfrage, Öffnen, Farben); mehrfach unschädlich.</summary>
    procedure Attach(ABox: TAtlasWelcomeSearchBox);
    function Query(const APattern: string): TArray<TAtlasWelcomeSearchResult>;
    procedure Open(const AHit: TAtlasWelcomeHit);
    /// <summary>Favoriten und zuletzt geöffnete Projekte der IDE, in dieser Reihenfolge.</summary>
    class function RecentProjects: TArray<string>; static;
    /// <summary>Ablage der Index-Caches: %LOCALAPPDATA%\Atlas (wie TPath.GetCachePath des Servers).</summary>
    class function CacheRoot: string; static;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Win.Registry,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Session,
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Welcome.Registry;

type
  TBoxWatch = class(TComponent)
  private
    FOwner: TAtlasIdeWelcomeSearch;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TBoxWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (FOwner <> nil) and (AComponent is TAtlasWelcomeSearchBox) then
    FOwner.FBoxes.Remove(TAtlasWelcomeSearchBox(AComponent));
end;

{ TAtlasIdeWelcomeSearch }

constructor TAtlasIdeWelcomeSearch.Create(const ACommands: TFunc<TArray<TAtlasCommand>>; const ARun: TProc<string>);
begin
  inherited Create;
  FCommands := ACommands;
  FRun := ARun;
  FIndex := TAtlasIndexProjects.Create(CacheRoot);
  FBoxes := TList<TAtlasWelcomeSearchBox>.Create;
  FWatch := TBoxWatch.Create(nil);
  TBoxWatch(FWatch).FOwner := Self;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnMessage := AppMessage;
end;

destructor TAtlasIdeWelcomeSearch.Destroy;
var
  Box: TAtlasWelcomeSearchBox;
begin
  FEvents.Free;
  for Box in FBoxes do
  begin
    Box.RemoveFreeNotification(FWatch);
    Box.OnQuery := nil;
    Box.OnOpen := nil;
  end;
  TBoxWatch(FWatch).FOwner := nil;
  FWatch.Free;
  FBoxes.Free;
  FIndex.Free;
  inherited;
end;

class function TAtlasIdeWelcomeSearch.CacheRoot: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas');
end;

function ReadProjectValues(ARegistry: TRegistry; const AKey: string): TArray<TPair<string, string>>;
var
  Names: TStringList;
  Name: string;
begin
  Result := nil;
  if not ARegistry.OpenKeyReadOnly('\' + AKey) then
    Exit;
  Names := TStringList.Create;
  try
    ARegistry.GetValueNames(Names);
    for Name in Names do
      if ARegistry.GetDataType(Name) in [rdString, rdExpandString] then
        Result := Result + [TPair<string, string>.Create(Name, ARegistry.ReadString(Name))];
  finally
    Names.Free;
    ARegistry.CloseKey;
  end;
end;

class function TAtlasIdeWelcomeSearch.RecentProjects: TArray<string>;
const
  // Favoriten der Willkommensseite zuerst, dann die Liste „Wieder öffnen“.
  Keys: array[0..2] of string = ('Favorite Projects', 'WelcomePage\Favorites', 'Closed Projects');
var
  Registry: TRegistry;
  Base, Key, Project: string;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  Base := TAtlasIdeRegistryAccess.IdeBaseKey;
  if Base = '' then
    Exit;
  Registry := TRegistry.Create(KEY_READ);
  Seen := TDictionary<string, Boolean>.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    for Key in Keys do
      for Project in TAtlasWelcomeSearch.RecentProjects(ReadProjectValues(Registry, Base + '\' + Key)) do
        if not Seen.ContainsKey(AnsiUpperCase(Project)) then
        begin
          Seen.Add(AnsiUpperCase(Project), True);
          Result := Result + [Project];
        end;
  finally
    Seen.Free;
    Registry.Free;
  end;
end;

function TAtlasIdeWelcomeSearch.ProjectFiles: TArray<string>;
var
  Seen: TDictionary<string, Boolean>;
  Project: string;
  Cached: TAtlasIndexProject;

  procedure Add(const AFileName: string);
  var
    Key: string;
  begin
    // Ein Projekt zählt einmal, egal ob als .dproj oder .dpr bekannt.
    Key := AnsiUpperCase(ChangeFileExt(AFileName, ''));
    if Seen.ContainsKey(Key) then
      Exit;
    Seen.Add(Key, True);
    Result := Result + [AFileName];
  end;

begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Project in RecentProjects do
      if not SameText(ExtractFileExt(Project), '.groupproj') then
        Add(Project);
    for Cached in FIndex.Projects do
      if FileExists(ChangeFileExt(Cached.MainFile, '.dproj')) then
        Add(ChangeFileExt(Cached.MainFile, '.dproj'))
      else
        Add(Cached.MainFile);
  finally
    Seen.Free;
  end;
end;

function TAtlasIdeWelcomeSearch.Candidates(const APattern: string; out ASymbolHint: string): TArray<TAtlasWelcomeHit>;
var
  Settings: TAtlasPluginSettings;
  Project, ProjectName, Detail: string;
  Recent: TArray<string>;
  Files: TArray<TAtlasIndexFile>;
  Entry: TAtlasIndexFile;
  Seen: TDictionary<string, Boolean>;
  Hit: TAtlasWelcomeHit;
  Command: TAtlasCommand;
  Session: TLspSession;
  Symbols: TArray<TAtlasSymbol>;
  Symbol: TAtlasSymbol;
  Now_: UInt64;
begin
  Result := nil;
  ASymbolHint := '';
  Settings := TAtlasIdeSettings.Current;
  Now_ := GetTickCount64;
  if (FRefreshed = 0) or (Now_ - FRefreshed >= RefreshMs) then
  begin
    FIndex.Refresh;
    FRefreshed := Now_;
  end;
  // Projekte: Favoriten und zuletzt geöffnete, Gruppen eingeschlossen.
  Recent := RecentProjects;
  for Project in Recent do
    Result := Result + [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Projects,
      ChangeFileExt(ExtractFileName(Project), ''), ExtractFileDir(Project), Project)];
  // Dateien der Projekte, zuletzt geöffnete zuerst; jede Datei einmal.
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Project in ProjectFiles do
    begin
      ProjectName := ChangeFileExt(ExtractFileName(Project), '');
      Files := FIndex.FilesOf(Project);
      // Projekte nur mit Cache, aber nicht in der Liste der IDE: trotzdem als Projekt anbieten.
      if (Length(Files) > 0) and (IndexText(Project, Recent) < 0) then
        Result := Result + [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Projects, ProjectName,
          ExtractFileDir(Project), Project)];
      for Entry in Files do
      begin
        if not SameText(ExtractFileExt(Entry.FileName), '.pas') or Seen.ContainsKey(AnsiUpperCase(Entry.FileName)) then
          Continue;
        Seen.Add(AnsiUpperCase(Entry.FileName), True);
        Detail := ProjectName;
        if TAtlasWelcomeIndexFiles.FormOf(Entry.FileName) <> '' then
          Detail := Detail + ' · ' + TAtlasStrings.Text(TAtlasTextId.WelcomeSearchForm);
        Hit := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, ExtractFileName(Entry.FileName), Detail,
          Entry.FileName);
        Hit.Project := Project;
        Result := Result + [Hit];
      end;
    end;
  finally
    Seen.Free;
  end;
  // Symbole: nur mit laufender Sitzung; die Willkommensseite startet keinen Server.
  if Settings.WelcomePageSearchSymbols then
  begin
    Session := TAtlasIdeResults.Session;
    if Session = nil then
      ASymbolHint := TAtlasStrings.Text(TAtlasTextId.WelcomeSearchNoServer)
    else if Length(Trim(APattern)) >= 2 then
    begin
      try
        Symbols := Session.WorkspaceSymbols(Trim(APattern), SymbolTimeoutMs);
      except
        // Server beschäftigt oder Zeit abgelaufen: diesmal ohne Symbole.
        on Exception do
          Symbols := nil;
      end;
      for Symbol in Symbols do
      begin
        Detail := ExtractFileName(Symbol.FileName);
        if Symbol.Container <> '' then
          Detail := Symbol.Container + ' · ' + Detail;
        Hit := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Symbols, Symbol.Name, Detail, Symbol.FileName);
        Hit.Line := Symbol.Line;
        Hit.Character := Symbol.Character;
        Hit.Prefiltered := True;
        Result := Result + [Hit];
      end;
    end;
  end;
  // Atlas-Befehle; auch über ihre Kennung auffindbar ("wel" → Atlas.WelcomeApply).
  if Assigned(FCommands) then
    for Command in FCommands() do
    begin
      Hit := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Commands,
        StringReplace(Command.Caption, 'Atlas: ', '', []), Command.ShortCut, Command.Id);
      Hit.Alias := StringReplace(Command.Id, 'Atlas.', '', []);
      Result := Result + [Hit];
    end;
end;

function TAtlasIdeWelcomeSearch.Query(const APattern: string): TArray<TAtlasWelcomeSearchResult>;
var
  Hits: TArray<TAtlasWelcomeHit>;
  Hint: string;
begin
  Result := nil;
  Hits := nil;
  Hint := '';
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Hits := Candidates(APattern, Hint);
    end);
  Result := TAtlasWelcomeSearch.Search(APattern, Hits, Hint);
end;

function ProjectOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

procedure TAtlasIdeWelcomeSearch.Open(const AHit: TAtlasWelcomeHit);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Actions: IOTAActionServices;
    begin
      if not Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Exit;
      case AHit.Group of
        TAtlasWelcomeSearchGroup.Projects:
          Actions.OpenProject(AHit.Target, True);
        TAtlasWelcomeSearchGroup.Commands:
          if Assigned(FRun) then
            FRun(AHit.Target);
      else
        begin
          if (AHit.Project <> '') and FileExists(AHit.Project) and not ProjectOpen(AHit.Project) then
            Actions.OpenProject(AHit.Project, True);
          if AHit.Line >= 0 then
            TAtlasIdeResults.Open(AHit.Target, AHit.Line, AHit.Character)
          else
            Actions.OpenFile(AHit.Target);
        end;
      end;
    end);
end;

procedure TAtlasIdeWelcomeSearch.Attach(ABox: TAtlasWelcomeSearchBox);
begin
  if ABox = nil then
    Exit;
  if FBoxes.IndexOf(ABox) < 0 then
  begin
    FBoxes.Add(ABox);
    ABox.FreeNotification(FWatch);
  end;
  ABox.Colors := TAtlasIdeStyle.Colors;
  ABox.OnQuery :=
    function(const APattern: string): TArray<TAtlasWelcomeSearchResult>
    begin
      Result := Query(APattern);
    end;
  ABox.OnOpen :=
    procedure(const AHit: TAtlasWelcomeHit)
    begin
      Open(AHit);
    end;
end;

function TAtlasIdeWelcomeSearch.ActiveBox: TAtlasWelcomeSearchBox;
var
  Box: TAtlasWelcomeSearchBox;
  Form: TCustomForm;
begin
  Result := nil;
  for Box in FBoxes do
  begin
    if not Box.Showing or not Box.Edit.CanFocus then
      Continue;
    Form := GetParentForm(Box, True);
    if (Form <> nil) and (Form = Screen.ActiveCustomForm) then
      Exit(Box);
  end;
end;

procedure TAtlasIdeWelcomeSearch.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Key: TShortCut;
  Box: TAtlasWelcomeSearchBox;
begin
  if ((Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN)) or (FBoxes.Count = 0) then
    Exit;
  Key := TShortCut(TAtlasIdeSettings.Current.WelcomePageSearchKey);
  if (Key = 0) or not TAtlasIdeSettings.Current.WelcomePageSearch then
    Exit;
  if ShortCut(Word(Msg.wParam), KeyDataToShiftState(Msg.lParam)) <> Key then
    Exit;
  Box := ActiveBox;
  if Box = nil then
    Exit;
  Box.FocusSearch;
  Handled := True;
end;

end.
