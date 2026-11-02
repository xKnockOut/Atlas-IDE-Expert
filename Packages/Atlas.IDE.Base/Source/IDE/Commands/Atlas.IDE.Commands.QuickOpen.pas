unit Atlas.IDE.Commands.QuickOpen;

// Datei und Symbol schnell öffnen (#503) in der IDE: das Fenster der
// Befehlspalette (TAtlasPaletteWindow) mit eigener Reihenfolge (Presorted) und
// ohne Wartezeit, nur bei "#" mit Tipppause wie die Symbolsuche (#400).
// - Quellen: Projekte der Gruppe (sonst das aktive) mit Projektdatei, .dpr bzw.
//   .dpk, eingetragenen Units samt Formular; Ordner der Projektdateien und die
//   Suchpfade ($(…) aufgelöst wie bei „Suchpfade prüfen“, #759); mit
//   quickOpen.librarySources auch $(BDS)\source.
// - Die Liste baut TAtlasQuickOpenList im Hintergrund auf: beim Anmelden, wenn
//   ein Projekt geöffnet oder geschlossen wird bzw. das aktive wechselt, und vor
//   jedem Öffnen des Fensters (nur neu, wenn sich die Quellen geändert haben).
// - Zuletzt geöffnete Dateien zählt ein IDE-Beobachter (alle Wege, nicht nur
//   dieses Fenster) in %LOCALAPPDATA%\Atlas\quickopen.json.
// - "@" fragt die Gliederung der obersten Datei einmal je Fenster ab, "#" bei
//   jeder Eingabe workspace/symbol, ":123" springt in der obersten Datei.
// Fehler nur ins Diagnoseprotokoll, nie als Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session;

type
  TAtlasIdeQuickOpen = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FState: TObject;
  private
    class function Session: TLspSession; static;
    class function RecentFile: string; static;
  public
    /// <summary>Beobachter anmelden und die Dateiliste im Hintergrund aufbauen.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>); static;
    /// <summary>Beobachter abmelden, Verlauf speichern, auf den Aufbau warten.</summary>
    class procedure Uninstall; static;
    /// <summary>Quellen neu bestimmen und die Liste bei Änderung neu aufbauen (Hauptthread).</summary>
    class procedure Refresh; static;
    /// <summary>Fenster zeigen; aus, solange quickOpen.enabled aus ist.</summary>
    class procedure Show; static;
  end;

implementation

uses
  System.Types,
  System.Math,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Results.Model,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.QuickOpen,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Context;

const
  SymbolTimeoutMs = 1500;
  ProjectSymbolDelayMs = 150;

type
  TQuickOpenState = class;

  TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
  private
    FOwner: TQuickOpenState;
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

  TQuickOpenState = class
  public
    List: TAtlasQuickOpenList;
    Recent: TAtlasCommandHistory;
    Notifier: TIdeNotifier;
    NotifierIndex: Integer;
    RefreshQueued: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

function State: TQuickOpenState;
begin
  Result := TQuickOpenState(TAtlasIdeQuickOpen.FState);
end;

function IsProjectFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.dproj') or (Extension = '.groupproj') or (Extension = '.dpr') or (Extension = '.dpk');
end;

{ TIdeNotifier }

procedure TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Owner: TQuickOpenState;
  Name: string;
begin
  Owner := FOwner;
  if Owner = nil then
    Exit;
  Name := FileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      if (NotifyCode = ofnFileOpened) and TAtlasQuickOpen.IsListed(Name) then
        Owner.Recent.Executed(TAtlasQuickOpen.RecentKey(Name));
      // Projektwechsel: nach dem Laden neu aufbauen (die IDE meldet vor dem Einlesen der Units).
      if ((NotifyCode = ofnActiveProjectChanged) or (((NotifyCode = ofnFileOpened) or
        (NotifyCode = ofnFileClosing)) and IsProjectFile(Name))) and not Owner.RefreshQueued then
      begin
        Owner.RefreshQueued := True;
        TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
          procedure
          begin
            if State = nil then
              Exit;
            State.RefreshQueued := False;
            TAtlasIdeQuickOpen.Refresh;
          end);
      end;
    end);
end;

procedure TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TQuickOpenState }

constructor TQuickOpenState.Create;
begin
  inherited Create;
  NotifierIndex := -1;
  Recent := TAtlasCommandHistory.Create;
  List := TAtlasQuickOpenList.Create(
    function(const AFolder: string; ARecursive: Boolean): TArray<string>
    begin
      Result := TAtlasQuickOpen.ListFolder(AFolder, ARecursive);
    end);
end;

destructor TQuickOpenState.Destroy;
begin
  List.Free;
  Recent.Free;
  inherited;
end;

{ Quellen }

function TopFile: string;
var
  Editors: IOTAEditorServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) and (Editors.TopBuffer <> nil) then
    Result := Editors.TopBuffer.FileName;
end;

function OpenFiles: TArray<string>;
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
  Index, FileIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
      Result := Result + [Module.ModuleFileEditors[FileIndex].FileName];
  end;
end;

procedure AddProject(const AProject: IOTAProject; var ASources: TAtlasQuickOpenSources; ALibrary: Boolean);
var
  Index: Integer;
  Info: IOTAModuleInfo;
  Main, Folder: string;
  Mains: array[0..1] of string;
  Context: TAtlasProjectContext;
  Variable: TAtlasPathVariable;
  Skipped: TArray<string>;
  Macros: TAtlasPathMacros;
begin
  if AProject = nil then
    Exit;
  Folder := ExtractFileDir(AProject.FileName);
  ASources.ProjectFiles := ASources.ProjectFiles + [AProject.FileName];
  Mains[0] := ChangeFileExt(AProject.FileName, '.dpr');
  Mains[1] := ChangeFileExt(AProject.FileName, '.dpk');
  for Main in Mains do
    if FileExists(Main) then
      ASources.ProjectFiles := ASources.ProjectFiles + [Main];
  for Index := 0 to AProject.GetModuleCount - 1 do
  begin
    Info := AProject.GetModule(Index);
    if (Info = nil) or (Info.FileName = '') then
      Continue;
    ASources.ProjectFiles := ASources.ProjectFiles + [Info.FileName];
    if Info.FormName <> '' then
      ASources.ProjectFiles := ASources.ProjectFiles + [ChangeFileExt(Info.FileName, '.dfm')];
    ASources.Folders := ASources.Folders + [ExtractFileDir(Info.FileName)];
  end;
  ASources.Folders := ASources.Folders + [Folder];
  Context := TAtlasIdeProjectContext.Read(AProject);
  if Context.Project = '' then
    Exit;
  Macros := TAtlasIdeProjectContext.Macros(Context);
  // Mit (): Variable liefert eine Funktion; ohne Klammern wäre es die Methode selbst.
  Variable := Macros.Variable();
  Skipped := nil;
  ASources.Folders := ASources.Folders + TAtlasPathCheck.ExpandPaths(Context.SearchPaths, Folder, Variable, Skipped);
  if ALibrary and (Macros.Value('BDS') <> '') and (Length(ASources.LibraryFolders) = 0) then
    ASources.LibraryFolders := [TPath.Combine(Macros.Value('BDS'), 'source')];
end;

function CurrentSources: TAtlasQuickOpenSources;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
  Library_: Boolean;
begin
  Result := Default(TAtlasQuickOpenSources);
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Library_ := TAtlasIdeSettings.Current.QuickOpenLibrary;
  Group := Services.MainProjectGroup;
  if (Group <> nil) and (Group.ProjectCount > 0) then
  begin
    Result.Root := ExtractFileDir(Group.FileName);
    if Result.Root = '' then
      Result.Root := ExtractFileDir(Group.Projects[0].FileName);
    for Index := 0 to Group.ProjectCount - 1 do
      AddProject(Group.Projects[Index], Result, Library_);
  end
  else if Services.GetActiveProject <> nil then
  begin
    Result.Root := ExtractFileDir(Services.GetActiveProject.FileName);
    AddProject(Services.GetActiveProject, Result, Library_);
  end;
end;

{ Einträge }

function Command(const AId, ACaption, APath, AShortCut: string): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Path := APath;
  Result.ShortCut := AShortCut;
end;

/// <summary>Eintrag mit Ziel: Datei in Description, "Zeile:Zeichen" (0-basiert, Zeile -1 = nur öffnen) in Id.
/// So braucht OnExecute keinen Zustand des Fensters, das sich beim Ausführen schon freigibt.</summary>
function Target(const AFileName: string; ALine, ACharacter: Integer; const ACaption, APath,
  AShortCut: string): TAtlasCommand;
begin
  Result := Command(Format('%d:%d', [ALine, ACharacter]), ACaption, APath, AShortCut);
  Result.Description := AFileName;
end;

function OriginText(AOrigin: TAtlasQuickOpenOrigin): string;
begin
  case AOrigin of
    TAtlasQuickOpenOrigin.Project:
      Result := TAtlasStrings.Text(TAtlasTextId.QuickOpenOriginProject);
    TAtlasQuickOpenOrigin.SearchPath:
      Result := TAtlasStrings.Text(TAtlasTextId.QuickOpenOriginSearchPath);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.QuickOpenOriginLibrary);
  end;
end;

type
  /// <summary>Zustand eines offenen Fensters; gehört dem Fenster und geht mit ihm.</summary>
  TWindowState = class(TComponent)
  public
    Window: TAtlasPaletteWindow;
    FileSymbols: TArray<TAtlasSymbol>;
    FileSymbolsRead: Boolean;
    Top: string;
    Open: TArray<string>;
  end;

function Query(AWindow: TWindowState; const APattern: string): TArray<TAtlasCommand>;
var
  Parsed: TAtlasQuickOpenQuery;
  Files: TAtlasQuickOpenFiles;
  Symbols: TArray<TAtlasSymbol>;
  Names: TArray<string>;
  Index: Integer;
  Current: TLspSession;
  Line: Integer;
begin
  Result := nil;
  Parsed := TAtlasQuickOpenQuery.Parse(APattern);
  // Nur "#" fragt bei jedem Zeichen den Server; dort mit Tipppause.
  if Parsed.Mode = TAtlasQuickOpenMode.ProjectSymbols then
    AWindow.Window.QueryDelay := ProjectSymbolDelayMs
  else
    AWindow.Window.QueryDelay := 0;
  case Parsed.Mode of
    TAtlasQuickOpenMode.Files:
      begin
        Files := State.List.Files;
        if (Length(Files) = 0) and State.List.Building then
        begin
          Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenBuilding), '', '')];
          Exit;
        end;
        Line := -1;
        if Parsed.Line > 0 then
          Line := Parsed.Line - 1;
        for Index in TAtlasQuickOpen.Order(Files, Parsed.Text, AWindow.Open, State.Recent) do
          Result := Result + [Target(Files[Index].FileName, Line, 0, Files[Index].Name,
            ExtractFileDir(Files[Index].RelativePath), OriginText(Files[Index].Origin))];
      end;
    TAtlasQuickOpenMode.Line:
      begin
        if AWindow.Top = '' then
        begin
          Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenNoEditor), '', '')];
          Exit;
        end;
        if Parsed.Line = 0 then
        begin
          Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenLineHint), ExtractFileName(AWindow.Top), '')];
          Exit;
        end;
        Result := [Target(AWindow.Top, Parsed.Line - 1, 0,
          TAtlasStrings.Fmt(TAtlasTextId.QuickOpenLine, [Parsed.Line]), ExtractFileName(AWindow.Top), '')];
      end;
    TAtlasQuickOpenMode.FileSymbols:
      begin
        if AWindow.Top = '' then
        begin
          Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenNoEditor), '', '')];
          Exit;
        end;
        if not AWindow.FileSymbolsRead then
        begin
          AWindow.FileSymbolsRead := True;
          Current := TAtlasIdeQuickOpen.Session;
          if Current <> nil then
            try
              AWindow.FileSymbols := Current.DocumentSymbols(AWindow.Top, SymbolTimeoutMs);
            except
              on ELspClientError do
                AWindow.FileSymbols := nil;
            end;
        end;
        Symbols := AWindow.FileSymbols;
        SetLength(Names, Length(Symbols));
        for Index := 0 to High(Symbols) do
          Names[Index] := Symbols[Index].Name;
        for Index in TAtlasQuickOpen.OrderSymbols(Names, Parsed.Text) do
          Result := Result + [Target(Symbols[Index].FileName, Symbols[Index].Line,
            Symbols[Index].Character, Symbols[Index].Name, Symbols[Index].Container,
            TAtlasResults.SymbolBadge(Symbols[Index].Kind))];
      end;
    TAtlasQuickOpenMode.ProjectSymbols:
      begin
        Current := TAtlasIdeQuickOpen.Session;
        if (Current = nil) or (Parsed.Text = '') then
          Exit;
        try
          Symbols := Current.WorkspaceSymbols(Parsed.Text, SymbolTimeoutMs);
        except
          on ELspClientError do
            Symbols := nil;
        end;
        for Index := 0 to Min(High(Symbols), TAtlasQuickOpen.MaxResults - 1) do
        begin
          Line := Symbols[Index].Line;
          if Symbols[Index].Container <> '' then
            Result := Result + [Target(Symbols[Index].FileName, Line, Symbols[Index].Character,
              Symbols[Index].Name, Symbols[Index].Container + ' · ' + ExtractFileName(Symbols[Index].FileName),
              TAtlasResults.SymbolBadge(Symbols[Index].Kind))]
          else
            Result := Result + [Target(Symbols[Index].FileName, Line, Symbols[Index].Character,
              Symbols[Index].Name, ExtractFileName(Symbols[Index].FileName),
              TAtlasResults.SymbolBadge(Symbols[Index].Kind))];
        end;
      end;
  end;
end;

procedure OpenTarget(const ACommand: TAtlasCommand);
var
  Parts: TArray<string>;
  Line, Character: Integer;
begin
  Parts := ACommand.Id.Split([':']);
  if (ACommand.Description = '') or (Length(Parts) <> 2) then
    Exit;
  Line := StrToIntDef(Parts[0], -1);
  Character := StrToIntDef(Parts[1], 0);
  if State <> nil then
    State.Recent.Executed(TAtlasQuickOpen.RecentKey(ACommand.Description));
  if Line >= 0 then
    TAtlasIdeNavigation.GoToLocation(ACommand.Description, Line, Character)
  else
    TAtlasIdeNavigation.ShowFile(ACommand.Description);
end;

{ TAtlasIdeQuickOpen }

class function TAtlasIdeQuickOpen.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
    Result := FSessionOf();
end;

class function TAtlasIdeQuickOpen.RecentFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'quickopen.json');
end;

class procedure TAtlasIdeQuickOpen.Install(const ASessionOf: TFunc<TLspSession>);
var
  Owner: TQuickOpenState;
  Services: IOTAServices;
begin
  FSessionOf := ASessionOf;
  Owner := TQuickOpenState.Create;
  FState := Owner;
  // Fehlt, unbrauchbar oder gesperrt: leer weiter; TAtlasDataFile legt Unbrauchbares als quickopen.json.defekt
  // beiseite und protokolliert, eine gesperrte Datei schreibt SaveToFile nicht (Bericht N3).
  Owner.Recent.Kind := 'Verlauf von Schnell öffnen';
  Owner.Recent.LoadFromFile(RecentFile);
  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Owner.Notifier := TIdeNotifier.Create;
    Owner.Notifier.FOwner := Owner;
    Owner.NotifierIndex := Services.AddNotifier(Owner.Notifier);
  end;
  if TAtlasIdeSettings.Current.QuickOpen then
    Refresh;
end;

class procedure TAtlasIdeQuickOpen.Uninstall;
var
  Owner: TQuickOpenState;
  Services: IOTAServices;
begin
  Owner := State;
  FState := nil;
  FSessionOf := nil;
  if Owner = nil then
    Exit;
  if Owner.Notifier <> nil then
    Owner.Notifier.FOwner := nil;
  // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
  if (Owner.NotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(Owner.NotifierIndex);
  try
    Owner.Recent.SaveToFile(RecentFile);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(Owner.Recent.Kind, E);
  end;
  Owner.Free;
end;

class procedure TAtlasIdeQuickOpen.Refresh;
begin
  if State = nil then
    Exit;
  State.List.Refresh(CurrentSources);
end;

class procedure TAtlasIdeQuickOpen.Show;
var
  Palette: TAtlasPaletteWindow;
  Window: TWindowState;
  Area: TRect;
begin
  if (State = nil) or not TAtlasIdeSettings.Current.QuickOpen then
    Exit;
  Refresh;
  Palette := TAtlasPaletteWindow.CreatePalette(Application, nil, nil, TAtlasIdeStyle.Colors);
  Window := TWindowState.Create(Palette);
  Window.Window := Palette;
  Window.Top := TopFile;
  Window.Open := OpenFiles;
  Palette.Prompt := TAtlasStrings.Text(TAtlasTextId.QuickOpenPrompt);
  Palette.Presorted := True;
  Palette.QueryDelay := 0;
  Palette.OnHighlight :=
    function(APattern: string): string
    begin
      Result := TAtlasQuickOpenQuery.Parse(APattern).Text;
    end;
  Palette.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := nil;
      if State <> nil then
        Result := Query(Window, APattern);
    end;
  Palette.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    begin
      OpenTarget(ACommand);
    end;
  Palette.SetCommands(Query(Window, ''));
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Palette.ShowOver(Area);
end;

end.
