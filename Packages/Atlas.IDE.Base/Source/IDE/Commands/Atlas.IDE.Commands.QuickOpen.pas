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
  cSymbolTimeoutMs = 1500;
  cProjectSymbolDelayMs = 150;

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
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.dproj') or (mExtension = '.groupproj') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

{ TIdeNotifier }

procedure TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  mOwner: TQuickOpenState;
  mName: string;
begin
  mOwner := FOwner;
  if mOwner = nil then
  begin
    Exit;
  end;
  mName := FileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      if (NotifyCode = ofnFileOpened) and TAtlasQuickOpen.IsListed(mName) then
      begin
        mOwner.Recent.Executed(TAtlasQuickOpen.RecentKey(mName));
      end;
      // Projektwechsel: nach dem Laden neu aufbauen (die IDE meldet vor dem Einlesen der Units).
      if ((NotifyCode = ofnActiveProjectChanged) or (((NotifyCode = ofnFileOpened) or
        (NotifyCode = ofnFileClosing)) and IsProjectFile(mName))) and not mOwner.RefreshQueued then
      begin
        mOwner.RefreshQueued := True;
        TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
          procedure
          begin
            if State = nil then
            begin
              Exit;
            end;
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
  mEditors: IOTAEditorServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and (mEditors.TopBuffer <> nil) then
  begin
    Result := mEditors.TopBuffer.FileName;
  end;
end;

function OpenFiles: TArray<string>;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex, mFileIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      Result := Result + [mModule.ModuleFileEditors[mFileIndex].FileName];
    end;
  end;
end;

procedure AddProject(const AProject: IOTAProject; var ASources: TAtlasQuickOpenSources; ALibrary: Boolean);
var
  mIndex: Integer;
  mInfo: IOTAModuleInfo;
  mMain, mFolder: string;
  mMains: array[0..1] of string;
  mContext: TAtlasProjectContext;
  mVariable: TAtlasPathVariable;
  mSkipped: TArray<string>;
  mMacros: TAtlasPathMacros;
begin
  if AProject = nil then
  begin
    Exit;
  end;
  mFolder := ExtractFileDir(AProject.FileName);
  ASources.ProjectFiles := ASources.ProjectFiles + [AProject.FileName];
  mMains[0] := ChangeFileExt(AProject.FileName, '.dpr');
  mMains[1] := ChangeFileExt(AProject.FileName, '.dpk');
  for mMain in mMains do
  begin
    if FileExists(mMain) then
    begin
      ASources.ProjectFiles := ASources.ProjectFiles + [mMain];
    end;
  end;
  for mIndex := 0 to AProject.GetModuleCount - 1 do
  begin
    mInfo := AProject.GetModule(mIndex);
    if (mInfo = nil) or (mInfo.FileName = '') then
    begin
      Continue;
    end;
    ASources.ProjectFiles := ASources.ProjectFiles + [mInfo.FileName];
    if mInfo.FormName <> '' then
    begin
      ASources.ProjectFiles := ASources.ProjectFiles + [ChangeFileExt(mInfo.FileName, '.dfm')];
    end;
    ASources.Folders := ASources.Folders + [ExtractFileDir(mInfo.FileName)];
  end;
  ASources.Folders := ASources.Folders + [mFolder];
  mContext := TAtlasIdeProjectContext.Read(AProject);
  if mContext.Project = '' then
  begin
    Exit;
  end;
  mMacros := TAtlasIdeProjectContext.Macros(mContext);
  // Mit (): Variable liefert eine Funktion; ohne Klammern wäre es die Methode selbst.
  mVariable := mMacros.Variable();
  mSkipped := nil;
  ASources.Folders := ASources.Folders + TAtlasPathCheck.ExpandPaths(mContext.SearchPaths, mFolder, mVariable, mSkipped);
  if ALibrary and (mMacros.Value('BDS') <> '') and (Length(ASources.LibraryFolders) = 0) then
  begin
    ASources.LibraryFolders := [TPath.Combine(mMacros.Value('BDS'), 'source')];
  end;
end;

function CurrentSources: TAtlasQuickOpenSources;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
  mLibrary_: Boolean;
begin
  Result := Default(TAtlasQuickOpenSources);
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mLibrary_ := TAtlasIdeSettings.Current.QuickOpenLibrary;
  mGroup := mServices.MainProjectGroup;
  if (mGroup <> nil) and (mGroup.ProjectCount > 0) then
  begin
    Result.Root := ExtractFileDir(mGroup.FileName);
    if Result.Root = '' then
    begin
      Result.Root := ExtractFileDir(mGroup.Projects[0].FileName);
    end;
    for mIndex := 0 to mGroup.ProjectCount - 1 do
    begin
      AddProject(mGroup.Projects[mIndex], Result, mLibrary_);
    end;
  end
  else if mServices.GetActiveProject <> nil then
  begin
    Result.Root := ExtractFileDir(mServices.GetActiveProject.FileName);
    AddProject(mServices.GetActiveProject, Result, mLibrary_);
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

/// <summary>Treffer unter den Dateien; solange die Liste entsteht und leer ist, ein Hinweis.</summary>
function FileResults(AWindow: TWindowState; const AParsed: TAtlasQuickOpenQuery): TArray<TAtlasCommand>;
var
  mFiles: TAtlasQuickOpenFiles;
  mIndex: Integer;
  mLine: Integer;
begin
  Result := nil;
  mFiles := State.List.Files;
  if (Length(mFiles) = 0) and State.List.Building then
  begin
    Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenBuilding), '', '')];
    Exit;
  end;
  mLine := -1;
  if AParsed.Line > 0 then
  begin
    mLine := AParsed.Line - 1;
  end;
  for mIndex in TAtlasQuickOpen.Order(mFiles, AParsed.Text, AWindow.Open, State.Recent) do
  begin
    Result := Result + [Target(mFiles[mIndex].FileName, mLine, 0, mFiles[mIndex].Name,
      ExtractFileDir(mFiles[mIndex].RelativePath), OriginText(mFiles[mIndex].Origin))];
  end;
end;

/// <summary>Sprung zu einer Zeile der obersten Datei; ohne Editor oder Zeile ein Hinweis.</summary>
function LineResults(AWindow: TWindowState; const AParsed: TAtlasQuickOpenQuery): TArray<TAtlasCommand>;
begin
  if AWindow.Top = '' then
  begin
    Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenNoEditor), '', '')];
  end
  else if AParsed.Line = 0 then
  begin
    Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenLineHint), ExtractFileName(AWindow.Top), '')];
  end
  else
  begin
    Result := [Target(AWindow.Top, AParsed.Line - 1, 0,
      TAtlasStrings.Fmt(TAtlasTextId.QuickOpenLine, [AParsed.Line]), ExtractFileName(AWindow.Top), '')];
  end;
end;

/// <summary>Symbole der obersten Datei, beim ersten Mal vom Server gelesen und dann im Fenster gemerkt.</summary>
procedure ReadFileSymbols(AWindow: TWindowState);
var
  mCurrent: TLspSession;
begin
  if AWindow.FileSymbolsRead then
  begin
    Exit;
  end;
  AWindow.FileSymbolsRead := True;
  mCurrent := TAtlasIdeQuickOpen.Session;
  if mCurrent = nil then
  begin
    Exit;
  end;
  try
    AWindow.FileSymbols := mCurrent.DocumentSymbols(AWindow.Top, cSymbolTimeoutMs);
  except
    on ELspClientError do
      AWindow.FileSymbols := nil;
  end;
end;

/// <summary>Treffer unter den Symbolen der obersten Datei; ohne Editor ein Hinweis.</summary>
function FileSymbolResults(AWindow: TWindowState; const AParsed: TAtlasQuickOpenQuery): TArray<TAtlasCommand>;
var
  mSymbols: TArray<TAtlasSymbol>;
  mNames: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  if AWindow.Top = '' then
  begin
    Result := [Command('', TAtlasStrings.Text(TAtlasTextId.QuickOpenNoEditor), '', '')];
    Exit;
  end;
  ReadFileSymbols(AWindow);
  mSymbols := AWindow.FileSymbols;
  SetLength(mNames, Length(mSymbols));
  for mIndex := 0 to High(mSymbols) do
  begin
    mNames[mIndex] := mSymbols[mIndex].Name;
  end;
  for mIndex in TAtlasQuickOpen.OrderSymbols(mNames, AParsed.Text) do
  begin
    Result := Result + [Target(mSymbols[mIndex].FileName, mSymbols[mIndex].Line,
      mSymbols[mIndex].Character, mSymbols[mIndex].Name, mSymbols[mIndex].Container,
      TAtlasResults.SymbolBadge(mSymbols[mIndex].Kind))];
  end;
end;

/// <summary>Zweite Zeile eines Projektsymbols: Container und Datei, ohne Container nur die Datei.</summary>
function SymbolPlace(const ASymbol: TAtlasSymbol): string;
begin
  Result := ExtractFileName(ASymbol.FileName);
  if ASymbol.Container <> '' then
  begin
    Result := ASymbol.Container + ' · ' + Result;
  end;
end;

/// <summary>Symbole des ganzen Projekts vom Server; leer ohne Sitzung oder Suchtext.</summary>
function ProjectSymbolResults(const AParsed: TAtlasQuickOpenQuery): TArray<TAtlasCommand>;
var
  mCurrent: TLspSession;
  mSymbols: TArray<TAtlasSymbol>;
  mIndex: Integer;
begin
  Result := nil;
  mCurrent := TAtlasIdeQuickOpen.Session;
  if (mCurrent = nil) or (AParsed.Text = '') then
  begin
    Exit;
  end;
  try
    mSymbols := mCurrent.WorkspaceSymbols(AParsed.Text, cSymbolTimeoutMs);
  except
    on ELspClientError do
      mSymbols := nil;
  end;
  for mIndex := 0 to Min(High(mSymbols), TAtlasQuickOpen.MaxResults - 1) do
  begin
    Result := Result + [Target(mSymbols[mIndex].FileName, mSymbols[mIndex].Line, mSymbols[mIndex].Character,
      mSymbols[mIndex].Name, SymbolPlace(mSymbols[mIndex]), TAtlasResults.SymbolBadge(mSymbols[mIndex].Kind))];
  end;
end;

function Query(AWindow: TWindowState; const APattern: string): TArray<TAtlasCommand>;
var
  mParsed: TAtlasQuickOpenQuery;
begin
  Result := nil;
  mParsed := TAtlasQuickOpenQuery.Parse(APattern);
  // Nur "#" fragt bei jedem Zeichen den Server; dort mit Tipppause.
  if mParsed.Mode = TAtlasQuickOpenMode.ProjectSymbols then
  begin
    AWindow.Window.QueryDelay := cProjectSymbolDelayMs;
  end
  else
  begin
    AWindow.Window.QueryDelay := 0;
  end;
  case mParsed.Mode of
    TAtlasQuickOpenMode.Files:
      Result := FileResults(AWindow, mParsed);
    TAtlasQuickOpenMode.Line:
      Result := LineResults(AWindow, mParsed);
    TAtlasQuickOpenMode.FileSymbols:
      Result := FileSymbolResults(AWindow, mParsed);
    TAtlasQuickOpenMode.ProjectSymbols:
      Result := ProjectSymbolResults(mParsed);
  end;
end;

procedure OpenTarget(const ACommand: TAtlasCommand);
var
  mParts: TArray<string>;
  mLine, mCharacter: Integer;
begin
  mParts := ACommand.Id.Split([':']);
  if (ACommand.Description = '') or (Length(mParts) <> 2) then
  begin
    Exit;
  end;
  mLine := StrToIntDef(mParts[0], -1);
  mCharacter := StrToIntDef(mParts[1], 0);
  if State <> nil then
  begin
    State.Recent.Executed(TAtlasQuickOpen.RecentKey(ACommand.Description));
  end;
  if mLine >= 0 then
  begin
    TAtlasIdeNavigation.GoToLocation(ACommand.Description, mLine, mCharacter);
  end
  else
  begin
    TAtlasIdeNavigation.ShowFile(ACommand.Description);
  end;
end;

{ TAtlasIdeQuickOpen }

class function TAtlasIdeQuickOpen.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class function TAtlasIdeQuickOpen.RecentFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'quickopen.json');
end;

class procedure TAtlasIdeQuickOpen.Install(const ASessionOf: TFunc<TLspSession>);
var
  mOwner: TQuickOpenState;
  mServices: IOTAServices;
begin
  FSessionOf := ASessionOf;
  mOwner := TQuickOpenState.Create;
  FState := mOwner;
  // Fehlt, unbrauchbar oder gesperrt: leer weiter; TAtlasDataFile legt Unbrauchbares als quickopen.json.defekt
  // beiseite und protokolliert, eine gesperrte Datei schreibt SaveToFile nicht (Bericht N3).
  mOwner.Recent.Kind := 'Verlauf von Schnell öffnen';
  mOwner.Recent.LoadFromFile(RecentFile);
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mOwner.Notifier := TIdeNotifier.Create;
    mOwner.Notifier.FOwner := mOwner;
    mOwner.NotifierIndex := mServices.AddNotifier(mOwner.Notifier);
  end;
  if TAtlasIdeSettings.Current.QuickOpen then
  begin
    Refresh;
  end;
end;

class procedure TAtlasIdeQuickOpen.Uninstall;
var
  mOwner: TQuickOpenState;
  mServices: IOTAServices;
begin
  mOwner := State;
  FState := nil;
  FSessionOf := nil;
  if mOwner = nil then
  begin
    Exit;
  end;
  if mOwner.Notifier <> nil then
  begin
    mOwner.Notifier.FOwner := nil;
  end;
  // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
  if (mOwner.NotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(mOwner.NotifierIndex);
  end;
  try
    mOwner.Recent.SaveToFile(RecentFile);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(mOwner.Recent.Kind, E);
  end;
  mOwner.Free;
end;

class procedure TAtlasIdeQuickOpen.Refresh;
begin
  if State = nil then
  begin
    Exit;
  end;
  State.List.Refresh(CurrentSources);
end;

class procedure TAtlasIdeQuickOpen.Show;
var
  mPalette: TAtlasPaletteWindow;
  mWindow: TWindowState;
  mArea: TRect;
begin
  if (State = nil) or not TAtlasIdeSettings.Current.QuickOpen then
  begin
    Exit;
  end;
  Refresh;
  mPalette := TAtlasPaletteWindow.CreatePalette(Application, nil, nil, TAtlasIdeStyle.Colors);
  mWindow := TWindowState.Create(mPalette);
  mWindow.Window := mPalette;
  mWindow.Top := TopFile;
  mWindow.Open := OpenFiles;
  mPalette.Prompt := TAtlasStrings.Text(TAtlasTextId.QuickOpenPrompt);
  mPalette.Presorted := True;
  mPalette.QueryDelay := 0;
  mPalette.OnHighlight :=
    function(APattern: string): string
    begin
      Result := TAtlasQuickOpenQuery.Parse(APattern).Text;
    end;
  mPalette.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := nil;
      if State <> nil then
      begin
        Result := Query(mWindow, APattern);
      end;
    end;
  mPalette.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    begin
      OpenTarget(ACommand);
    end;
  mPalette.SetCommands(Query(mWindow, ''));
  if Screen.ActiveForm <> nil then
  begin
    mArea := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end
  else
  begin
    mArea := Screen.WorkAreaRect;
  end;
  mPalette.ShowOver(mArea);
end;

end.
