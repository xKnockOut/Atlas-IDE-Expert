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
// Vorgabe Strg+E) setzt den Fokus ins Suchfeld, solange der Fokus in der
// Form des Suchfelds liegt: im Fenster „Atlas-Start“ (#1114) bzw. im
// Editorfenster, das gerade die Willkommensseite der IDE zeigt (#761); sonst
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
    /// <summary>Nur die zuletzt geöffneten Projekte und Projektgruppen der IDE (Closed Projects), neueste zuerst
    /// (Bereich „Projekte“, #592).</summary>
    class function ClosedProjects: TArray<string>; static;
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
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
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
  begin
    FOwner.FBoxes.Remove(TAtlasWelcomeSearchBox(AComponent));
  end;
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
  begin
    Exit;
  end;
  Names := TStringList.Create;
  try
    ARegistry.GetValueNames(Names);
    for Name in Names do
    begin
      if ARegistry.GetDataType(Name) in [rdString, rdExpandString] then
      begin
        Result := Result + [TPair<string, string>.Create(Name, ARegistry.ReadString(Name))];
      end;
    end;
  finally
    Names.Free;
    ARegistry.CloseKey;
  end;
end;

/// <summary>Projekte aus den Registry-Schlüsseln AKeys unter der Basis der IDE, jedes einmal.</summary>
function ProjectsIn(const AKeys: array of string): TArray<string>;
var
  Registry: TRegistry;
  Base, Key, Project: string;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  Base := TAtlasIdeRegistryAccess.IdeBaseKey;
  if Base = '' then
  begin
    Exit;
  end;
  Registry := TRegistry.Create(KEY_READ);
  Seen := TDictionary<string, Boolean>.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    for Key in AKeys do
    begin
      for Project in TAtlasWelcomeSearch.RecentProjects(ReadProjectValues(Registry, Base + '\' + Key)) do
      begin
        if not Seen.ContainsKey(AnsiUpperCase(Project)) then
        begin
          Seen.Add(AnsiUpperCase(Project), True);
          Result := Result + [Project];
        end;
      end;
    end;
  finally
    Seen.Free;
    Registry.Free;
  end;
end;

class function TAtlasIdeWelcomeSearch.RecentProjects: TArray<string>;
begin
  // Favoriten der Willkommensseite zuerst, dann die Liste „Wieder öffnen“.
  Result := ProjectsIn(['Favorite Projects', 'WelcomePage\Favorites', 'Closed Projects']);
end;

class function TAtlasIdeWelcomeSearch.ClosedProjects: TArray<string>;
begin
  Result := ProjectsIn(['Closed Projects']);
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
    begin
      Exit;
    end;
    Seen.Add(Key, True);
    Result := Result + [AFileName];
  end;

begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Project in RecentProjects do
    begin
      if not SameText(ExtractFileExt(Project), '.groupproj') then
      begin
        Add(Project);
      end;
    end;
    for Cached in FIndex.Projects do
    begin
      if FileExists(ChangeFileExt(Cached.MainFile, '.dproj')) then
      begin
        Add(ChangeFileExt(Cached.MainFile, '.dproj'));
      end
      else
      begin
        Add(Cached.MainFile);
      end;
    end;
  finally
    Seen.Free;
  end;
end;

function ProjectHits(const AProjects: TArray<string>): TArray<TAtlasWelcomeHit>;
var
  mProject: string;
begin
  Result := nil;
  for mProject in AProjects do
  begin
    Result := Result + [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Projects,
      ChangeFileExt(ExtractFileName(mProject), ''), ExtractFileDir(mProject), mProject)];
  end;
end;

function FileHit(const AProject, AFileName: string): TAtlasWelcomeHit;
var
  mDetail: string;
begin
  mDetail := ChangeFileExt(ExtractFileName(AProject), '');
  if TAtlasWelcomeIndexFiles.FormOf(AFileName) <> '' then
  begin
    mDetail := mDetail + ' · ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchForm);
  end;
  Result := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, ExtractFileName(AFileName), mDetail, AFileName);
  Result.Project := AProject;
end;

/// <summary>Treffer eines Projekts aus seinem Cache: das Projekt selbst, wenn die IDE es nicht kennt, und seine
/// .pas-Dateien, die ASeen noch nicht hat.</summary>
function IndexHits(const AProject: string; const AFiles: TArray<TAtlasIndexFile>; const ARecent: TArray<string>;
  ASeen: TDictionary<string, Boolean>): TArray<TAtlasWelcomeHit>;
var
  mEntry: TAtlasIndexFile;
begin
  Result := nil;
  // Projekte nur mit Cache, aber nicht in der Liste der IDE: trotzdem als Projekt anbieten.
  if (Length(AFiles) > 0) and (IndexText(AProject, ARecent) < 0) then
  begin
    Result := ProjectHits(TArray<string>.Create(AProject));
  end;
  for mEntry in AFiles do
  begin
    if SameText(ExtractFileExt(mEntry.FileName), '.pas') and not ASeen.ContainsKey(AnsiUpperCase(mEntry.FileName)) then
    begin
      ASeen.Add(AnsiUpperCase(mEntry.FileName), True);
      Result := Result + [FileHit(AProject, mEntry.FileName)];
    end;
  end;
end;

function SymbolHit(const ASymbol: TAtlasSymbol): TAtlasWelcomeHit;
var
  mDetail: string;
begin
  mDetail := ExtractFileName(ASymbol.FileName);
  if ASymbol.Container <> '' then
  begin
    mDetail := ASymbol.Container + ' · ' + mDetail;
  end;
  Result := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Symbols, ASymbol.Name, mDetail, ASymbol.FileName);
  Result.Line := ASymbol.Line;
  Result.Character := ASymbol.Character;
  Result.Prefiltered := True;
end;

/// <summary>Symbole: nur mit laufender Sitzung; die Willkommensseite startet keinen Server.</summary>
function SymbolHits(const APattern: string; ATimeoutMs: Integer; out AHint: string): TArray<TAtlasWelcomeHit>;
var
  mSession: TLspSession;
  mSymbols: TArray<TAtlasSymbol>;
  mSymbol: TAtlasSymbol;
begin
  Result := nil;
  AHint := '';
  mSession := TAtlasIdeResults.Session;
  if mSession = nil then
  begin
    AHint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchNoServer);
    Exit;
  end;
  if Length(Trim(APattern)) < 2 then
  begin
    Exit;
  end;
  try
    mSymbols := mSession.WorkspaceSymbols(Trim(APattern), ATimeoutMs);
  except
    // Server beschäftigt oder Zeit abgelaufen: diesmal ohne Symbole.
    on Exception do
      mSymbols := nil;
  end;
  for mSymbol in mSymbols do
  begin
    Result := Result + [SymbolHit(mSymbol)];
  end;
end;

/// <summary>Atlas-Befehle; auch über ihre Kennung auffindbar ("wel" → Atlas.WelcomeStart).</summary>
function CommandHits(const ACommands: TArray<TAtlasCommand>): TArray<TAtlasWelcomeHit>;
var
  mCommand: TAtlasCommand;
  mHit: TAtlasWelcomeHit;
begin
  Result := nil;
  for mCommand in ACommands do
  begin
    mHit := TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Commands,
      StringReplace(mCommand.Caption, 'Atlas: ', '', []), mCommand.ShortCut, mCommand.Id);
    mHit.Alias := StringReplace(mCommand.Id, 'Atlas.', '', []);
    Result := Result + [mHit];
  end;
end;

function TAtlasIdeWelcomeSearch.Candidates(const APattern: string; out ASymbolHint: string): TArray<TAtlasWelcomeHit>;
var
  mProject: string;
  mRecent: TArray<string>;
  mSeen: TDictionary<string, Boolean>;
  mNow: UInt64;
begin
  ASymbolHint := '';
  mNow := GetTickCount64;
  if (FRefreshed = 0) or (mNow - FRefreshed >= RefreshMs) then
  begin
    FIndex.Refresh;
    FRefreshed := mNow;
  end;
  // Projekte: Favoriten und zuletzt geöffnete, Gruppen eingeschlossen.
  mRecent := RecentProjects;
  Result := ProjectHits(mRecent);
  // Dateien der Projekte, zuletzt geöffnete zuerst; jede Datei einmal.
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mProject in ProjectFiles do
    begin
      Result := Result + IndexHits(mProject, FIndex.FilesOf(mProject), mRecent, mSeen);
    end;
  finally
    mSeen.Free;
  end;
  if TAtlasIdeSettings.Current.WelcomePageSearchSymbols then
  begin
    Result := Result + SymbolHits(APattern, SymbolTimeoutMs, ASymbolHint);
  end;
  if Assigned(FCommands) then
  begin
    Result := Result + CommandHits(FCommands());
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
      begin
        Exit;
      end;
      case AHit.Group of
        TAtlasWelcomeSearchGroup.Projects:
          Actions.OpenProject(AHit.Target, True);
        TAtlasWelcomeSearchGroup.Commands:
          if Assigned(FRun) then
          begin
            FRun(AHit.Target);
          end;
      else
        begin
          if (AHit.Project <> '') and FileExists(AHit.Project) and not ProjectOpen(AHit.Project) then
          begin
            Actions.OpenProject(AHit.Project, True);
          end;
          if AHit.Line >= 0 then
          begin
            TAtlasIdeResults.Open(AHit.Target, AHit.Line, AHit.Character);
          end
          else
          begin
            TAtlasIdeNavigation.ShowFile(AHit.Target);
          end;
        end;
      end;
    end);
end;

procedure TAtlasIdeWelcomeSearch.Attach(ABox: TAtlasWelcomeSearchBox);
begin
  if ABox = nil then
  begin
    Exit;
  end;
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
    begin
      Continue;
    end;
    // Innerste Form, nicht die oberste: Angedockt ist die oberste Form von
    // „Atlas-Start“ das Hauptfenster der IDE; die Taste gehört Atlas daher
    // nur, wenn der Fokus im Fenster selbst liegt, sonst bliebe Strg+E im
    // Editor nicht die inkrementelle Suche der IDE. Auf der Willkommensseite
    // der IDE ist es das Editorfenster; Showing gilt dort nur, solange die
    // Willkommensseite der sichtbare Reiter ist.
    Form := GetParentForm(Box, False);
    if Form = nil then
    begin
      Continue;
    end;
    if (Form = Screen.ActiveCustomForm) or
      ((Screen.ActiveControl <> nil) and Form.ContainsControl(Screen.ActiveControl)) then
    begin
      Exit(Box);
    end;
  end;
end;

procedure TAtlasIdeWelcomeSearch.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Key: TShortCut;
  Box: TAtlasWelcomeSearchBox;
begin
  if ((Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN)) or (FBoxes.Count = 0) then
  begin
    Exit;
  end;
  Key := TShortCut(TAtlasIdeSettings.Current.WelcomePageSearchKey);
  if (Key = 0) or not TAtlasIdeSettings.Current.WelcomePageSearch then
  begin
    Exit;
  end;
  if ShortCut(Word(Msg.wParam), KeyDataToShiftState(Msg.lParam)) <> Key then
  begin
    Exit;
  end;
  Box := ActiveBox;
  if Box = nil then
  begin
    Exit;
  end;
  Box.FocusSearch;
  Handled := True;
end;

end.
