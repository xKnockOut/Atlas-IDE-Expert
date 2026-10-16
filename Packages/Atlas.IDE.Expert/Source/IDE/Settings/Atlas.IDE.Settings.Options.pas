unit Atlas.IDE.Settings.Options;

// Meldet die Seite „Atlas“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Die Liste der angehefteten Favoriten (#458) kommt aus TAtlasIdeFavorites; „Entfernen“ wirkt sofort.
// Darunter die Seite „Snippets“ (#51): Code-Vorlagen ansehen, eigene anlegen,
// bearbeiten und löschen; gespeichert wird beim Schließen mit OK. Der Punkt
// in der Überschrift „Atlas.Snippets“ hängt die Seite unter „Atlas“.
// Daneben die Seite „Atlas.Tastenkonflikte“ (#494): Wer welche Taste belegt,
// fragt sie über TAtlasIdeKeys.Owner ab; nach dem Speichern belegt die
// Komposition die Tasten über Settings.OnChanged neu.
// Abschnitt Symbolindex (#492): Kennzahlen aus atlas.server.status, „Index neu
// aufbauen“ und „Index löschen“ über die Befehle des Servers.
// Seite „Atlas.Server“ (#227): globale und Projekt-Einstellungen des Servers im
// Dialog, Baseline neu erzeugen oder löschen, Unterdrückungen je Regel und
// Index-Cache löschen über AtlasServer.exe als Prozess (TAtlasServerTool).

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Befehl an den Server; Ergebnis gehört dem Aufrufer, nil ohne Server.</summary>
  TAtlasServerCommand = reference to function(ACommand: string): TJSONValue;

  /// <summary>Was die Optionsseiten von anderen Features brauchen; setzt die Composition (A-09: die Seiten
  /// importieren Befehlszählung, Tipps, Code Insight-Manager und Vervollständigung nicht). Nicht gesetzte Haken
  /// bleiben ohne Wirkung bzw. liefern ''.</summary>
  TAtlasOptionsHooks = record
    /// <summary>Lernende Gewichtung zurücksetzen (#418).</summary>
    ResetHistory: TProc;
    /// <summary>Befehl an den Server (#492).</summary>
    Command: TAtlasServerCommand;
    /// <summary>Zählung der Befehle zurücksetzen (#757).</summary>
    ResetUsage: TProc;
    /// <summary>Gesperrte Tipps wieder zeigen (#757).</summary>
    UnblockTips: TProc;
    /// <summary>Pfad der AtlasServer.exe nach den Einstellungen.</summary>
    ServerPath: TFunc<string>;
    /// <summary>Pfad der mitgelieferten AtlasServer.exe.</summary>
    DefaultServerPath: TFunc<string>;
    /// <summary>Ordner der Live Templates der IDE (#487).</summary>
    IdeTemplateFolder: TFunc<string>;
    /// <summary>Ordner der eigenen Code-Vorlagen (#51).</summary>
    SnippetFolder: TFunc<string>;
  end;

  TAtlasOptionsRegistration = class
  public
    class procedure Register(const AHooks: TAtlasOptionsHooks); static;
    class procedure Unregister; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  System.Classes,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.UI.Settings.SnippetsPage,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Progress,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Keys,
  Atlas.UI.Settings.ServerPage,
  Atlas.Core.Settings.Baseline,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerTool,
  Atlas.UI.Strings,
  Atlas.IDE.Commands.Keys,
  Atlas.Core.Completion.Favorites,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.Settings.Store;

type
  TAtlasAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsPage;
    function Run(const ACommand: string; out AAnswer: TJSONValue): Boolean;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Seite „Tastenkonflikte“ (#494).</summary>
  TAtlasKeysOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasKeysPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  TAtlasSnippetOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSnippetsPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Seite „Server“ (#227).</summary>
  TAtlasServerOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasServerPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

var
  Options: INTAAddInOptions;
  ServerOptions: INTAAddInOptions;
  SnippetOptions: INTAAddInOptions;
  KeysOptions: INTAAddInOptions;
  /// <summary>Gesetzt von Register, geleert von Unregister.</summary>
  Hooks: TAtlasOptionsHooks;

/// <summary>Ergebnis eines Hakens; '' ohne Haken.</summary>
function HookText(const AHook: TFunc<string>): string;
begin
  Result := '';
  if Assigned(AHook) then
    Result := AHook();
end;

{ TAtlasAddInOptions }

function TAtlasAddInOptions.Run(const ACommand: string; out AAnswer: TJSONValue): Boolean;
begin
  AAnswer := nil;
  if Assigned(Hooks.Command) then
    AAnswer := Hooks.Command(ACommand);
  Result := AAnswer <> nil;
end;

function TAtlasAddInOptions.GetArea: string;
begin
  // Leer: unter „Drittanbieter“, wie die Open Tools API empfiehlt.
  Result := '';
end;

function TAtlasAddInOptions.GetCaption: string;
begin
  Result := 'Atlas';
end;

function TAtlasAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSettingsPage;
end;

procedure TAtlasAddInOptions.FrameCreated(AFrame: TCustomFrame);
begin
  FPage := AFrame as TAtlasSettingsPage;
  FPage.DefaultServerPath := HookText(Hooks.DefaultServerPath);
  // Version der gewählten AtlasServer.exe (#227).
  FPage.OnServerVersion :=
    function(APath: string): string
    begin
      Result := TAtlasServerTool.FileVersion(APath);
    end;
  FPage.OnResetHistory := Hooks.ResetHistory;
  // Angeheftete Favoriten (#458): Liste und Entfernen.
  FPage.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeFavorites.Remove(AKeys);
        end);
    end;
  FPage.OnFavorites :=
    function: TArray<TAtlasFavorite>
    begin
      Result := TAtlasIdeFavorites.Items;
    end;
  // Karte „Atlas entdecken“ (#757): Zählung zurücksetzen, gesperrte Tipps wieder zeigen.
  FPage.OnResetUsage :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if Assigned(Hooks.ResetUsage) then
            Hooks.ResetUsage();
        end);
    end;
  FPage.OnUnblockTips :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if Assigned(Hooks.UnblockTips) then
            Hooks.UnblockTips();
        end);
    end;
  // Symbolindex (#492): vor LoadFrom, das die Kennzahlen gleich anzeigt.
  FPage.OnIndexMetrics :=
    function: string
    var
      Answer: TJSONValue;
    begin
      Run('atlas.server.status', Answer);
      try
        Result := TLspIndexStatus.Metrics(Answer).Text;
      finally
        Answer.Free;
      end;
    end;
  FPage.OnIndexRebuild :=
    function: string
    var
      Answer: TJSONValue;
    begin
      if Run('atlas.server.rebuildIndex', Answer) then
        Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
      Answer.Free;
    end;
  FPage.OnIndexClear :=
    function: string
    var
      Answer: TJSONValue;
    begin
      if Run('atlas.server.clearIndex', Answer) then
        Result := TLspIndexStatus.ClearedText(Answer)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
      Answer.Free;
    end;
  FPage.LoadFrom(TAtlasIdeSettings.Stored);
end;

procedure TAtlasAddInOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  try
    if Accepted and (FPage <> nil) then
    begin
      Settings := TAtlasIdeSettings.Stored;
      FPage.SaveTo(Settings);
      TAtlasIdeSettings.Update(Settings);
    end;
    // Strukturhervorhebung und Help Insight der IDE erst nach dem Dialog abgleichen: Mit OK
    // schreibt die IDE danach ihre Editoroptionen aus dem Speicher zurück, auch die Schalter,
    // die Atlas abgeschaltet hatte. Sonst zeigt sie ab dem nächsten Start wieder beide Tooltips.
    if Accepted then
      TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Settings,
            procedure
            begin
              TAtlasIdeStructureSwitch.Sync;
            end);
        end);
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasAddInOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasAddInOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasAddInOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasSnippetOptions }

function TAtlasSnippetOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasSnippetOptions.GetCaption: string;
begin
  Result := 'Atlas.Snippets';
end;

function TAtlasSnippetOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSnippetsPage;
end;

procedure TAtlasSnippetOptions.FrameCreated(AFrame: TCustomFrame);
var
  Ide, Own: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
  Errors: TArray<string>;
begin
  try
    FPage := AFrame as TAtlasSnippetsPage;
    Ide := nil;
    if TAtlasIdeSettings.Current.ImportIdeTemplates then
      Ide := TAtlasLiveTemplates.LoadFolder(HookText(Hooks.IdeTemplateFolder), Stats);
    Own := TAtlasSnippets.LoadFolder(HookText(Hooks.SnippetFolder), Errors);
    FPage.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, Ide, Own));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasSnippetOptions.DialogClosed(Accepted: Boolean);
begin
  try
    if Accepted and (FPage <> nil) and (FPage.Catalog <> nil) and FPage.Catalog.Modified then
      FPage.Catalog.Save(HookText(Hooks.SnippetFolder));
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasSnippetOptions.ValidateContents: Boolean;
var
  Message: string;
begin
  Result := True;
  if FPage = nil then
    Exit;
  Message := FPage.Validate;
  if Message <> '' then
  begin
    ShowMessage(Message);
    Result := False;
  end;
end;

function TAtlasSnippetOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasSnippetOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasKeysOptions }

function TAtlasKeysOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasKeysOptions.GetCaption: string;
begin
  // Punkt: Unterseite von „Atlas“.
  Result := 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle);
end;

function TAtlasKeysOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasKeysPage;
end;

procedure TAtlasKeysOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    FPage := AFrame as TAtlasKeysPage;
    FPage.LoadFrom(TAtlasIdeSettings.Stored);
    FPage.OwnerOf :=
      function(AShortCut: Word): string
      begin
        Result := TAtlasIdeKeys.Owner(AShortCut);
      end;
    FPage.ShowForeignCompletions(TAtlasIdeKeys.ForeignCompletions);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasKeysOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  try
    if Accepted and (FPage <> nil) then
    begin
      Settings := TAtlasIdeSettings.Stored;
      FPage.SaveTo(Settings);
      TAtlasIdeSettings.Update(Settings);
    end;
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasKeysOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasKeysOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasKeysOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasServerOptions }

function ServerExe: string;
begin
  Result := HookText(Hooks.ServerPath);
end;

/// <summary>atlas-baseline.json des aktiven Projekts (oder der alte Name, wenn nur er existiert); '' ohne Projekt.
/// </summary>
function BaselineFile: string;
var
  Folder: string;
begin
  Result := '';
  if TAtlasProjectSettings.SettingsFile = '' then
    Exit;
  Folder := ExtractFileDir(TAtlasProjectSettings.SettingsFile);
  Result := IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.FileName;
  if not FileExists(Result) and FileExists(IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.LegacyFileName)
  then
    Result := IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.LegacyFileName;
end;

function BaselineText: string;
var
  FileName: string;
  Count, Entries: Integer;
begin
  FileName := BaselineFile;
  if FileName = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
  if not FileExists(FileName) then
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  Count := TAtlasBaselineInfo.Count(TFile.ReadAllText(FileName, TEncoding.UTF8), Entries);
  if Count < 0 then
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageBaselineCount, [Count, Entries]);
end;

/// <summary>AtlasServer.exe mit AArguments im Projektordner; '' bei Erfolg, sonst die Meldung.</summary>
function RunTool(const AArguments: string; ATimeoutMs: Cardinal; out AOutput: string): string;
var
  Code: Cardinal;
  Error, Folder: string;
begin
  Result := '';
  Folder := ExtractFileDir(TAtlasProjectSettings.ActiveProject);
  if not TAtlasServerTool.Run(ServerExe, AArguments, Folder, ATimeoutMs, AOutput, Code, Error) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, [Error])
  else if Code = 3 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, ['Exit-Code 3']);
end;

function TAtlasServerOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasServerOptions.GetCaption: string;
begin
  // Punkt: Unterseite von „Atlas“.
  Result := 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.ServerPageTitle);
end;

function TAtlasServerOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasServerPage;
end;

procedure TAtlasServerOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    FPage := AFrame as TAtlasServerPage;
    FPage.OnEditGlobal :=
      procedure
      begin
        TAtlasProjectSettings.ExecuteGlobal;
      end;
    FPage.OnEditProject :=
      procedure
      begin
        TAtlasProjectSettings.Execute;
      end;
    FPage.OnBaselineInfo :=
      function: string
      begin
        Result := BaselineText;
      end;
    FPage.OnBaselineUpdate :=
      function: string
      var
        Output: string;
      begin
        if TAtlasProjectSettings.ActiveProject = '' then
          Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
        Result := RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
          TAtlasServerTool.CheckTimeoutMs, Output);
        if Result = '' then
          Result := BaselineText;
      end;
    FPage.OnBaselineDelete :=
      function: string
      begin
        if (BaselineFile <> '') and FileExists(BaselineFile) then
          TFile.Delete(BaselineFile);
        Result := BaselineText;
      end;
    FPage.OnSuppressions :=
      function: TArray<string>
      var
        OutputFile, Output, Error: string;
        Row: TAtlasSuppressionRow;
      begin
        Result := nil;
        if TAtlasProjectSettings.ActiveProject = '' then
        begin
          Result := [TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject)];
          Exit;
        end;
        OutputFile := TPath.GetTempFileName;
        try
          Error := RunTool('--check "' + TAtlasProjectSettings.ActiveProject +
            '" --suppression-stats --format json --output "' + OutputFile + '"', TAtlasServerTool.CheckTimeoutMs,
            Output);
          if Error <> '' then
          begin
            Result := [Error];
            Exit;
          end;
          for Row in TAtlasBaselineInfo.Suppressions(TFile.ReadAllText(OutputFile, TEncoding.UTF8)) do
            Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.ServerPageSuppressionRow,
              [Row.Rule, Row.Total, Row.Unused, Row.Files])];
          if Length(Result) = 0 then
            Result := [TAtlasStrings.Text(TAtlasTextId.ServerPageSuppressionsNone)];
        finally
          if FileExists(OutputFile) then
            TFile.Delete(OutputFile);
        end;
      end;
    FPage.OnClearCache :=
      function: string
      var
        Output: string;
      begin
        Result := RunTool('--clear-cache', TAtlasServerTool.ShortTimeoutMs, Output);
        if Result = '' then
          Result := Trim(Output);
        if Result = '' then
          Result := TAtlasStrings.Text(TAtlasTextId.ServerPageToolDone);
      end;
    FPage.Refresh;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasServerOptions.DialogClosed(Accepted: Boolean);
begin
  FPage := nil;
end;

function TAtlasServerOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasServerOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasServerOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasOptionsRegistration }

class procedure TAtlasOptionsRegistration.Register(const AHooks: TAtlasOptionsHooks);
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    Hooks := AHooks;
    Options := TAtlasAddInOptions.Create;
    Services.RegisterAddInOptions(Options);
    SnippetOptions := TAtlasSnippetOptions.Create;
    Services.RegisterAddInOptions(SnippetOptions);
    KeysOptions := TAtlasKeysOptions.Create;
    Services.RegisterAddInOptions(KeysOptions);
    ServerOptions := TAtlasServerOptions.Create;
    Services.RegisterAddInOptions(ServerOptions);
  end;
end;

class procedure TAtlasOptionsRegistration.Unregister;
var
  Services: INTAEnvironmentOptionsServices;
begin
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    if SnippetOptions <> nil then
      Services.UnregisterAddInOptions(SnippetOptions);
    if KeysOptions <> nil then
      Services.UnregisterAddInOptions(KeysOptions);
    if ServerOptions <> nil then
      Services.UnregisterAddInOptions(ServerOptions);
    if Options <> nil then
      Services.UnregisterAddInOptions(Options);
  end;
  SnippetOptions := nil;
  KeysOptions := nil;
  ServerOptions := nil;
  Options := nil;
  Hooks := Default(TAtlasOptionsHooks);
end;

end.
