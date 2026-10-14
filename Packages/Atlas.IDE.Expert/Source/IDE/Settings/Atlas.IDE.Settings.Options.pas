unit Atlas.IDE.Settings.Options;

// Meldet die Seite „Atlas“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Darunter die Seite „Snippets“ (#51): Code-Vorlagen ansehen, eigene anlegen,
// bearbeiten und löschen; gespeichert wird beim Schließen mit OK. Der Punkt
// in der Überschrift „Atlas.Snippets“ hängt die Seite unter „Atlas“.

interface

uses
  System.SysUtils;

type
  TAtlasOptionsRegistration = class
  public
    class procedure Register(const AResetHistory: TProc); static;
    class procedure Unregister; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.UI.Settings.SnippetsPage,
  Atlas.IDE.Completion.Editor,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.CodeInsight.Manager,
  Atlas.IDE.Settings.Store;

type
  TAtlasAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsPage;
    FResetHistory: TProc;
  public
    constructor Create(const AResetHistory: TProc);
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

var
  Options: INTAAddInOptions;
  SnippetOptions: INTAAddInOptions;

{ TAtlasAddInOptions }

constructor TAtlasAddInOptions.Create(const AResetHistory: TProc);
begin
  inherited Create;
  FResetHistory := AResetHistory;
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
  FPage.DefaultServerPath := TAtlasCodeInsightManager.DefaultServerPath;
  FPage.LoadFrom(TAtlasIdeSettings.Current);
  FPage.OnResetHistory := FResetHistory;
end;

procedure TAtlasAddInOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  try
    if Accepted and (FPage <> nil) then
    begin
      Settings := TAtlasIdeSettings.Current;
      FPage.SaveTo(Settings);
      TAtlasIdeSettings.Update(Settings);
      TAtlasIdeStructureSwitch.Sync;
    end;
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
      Ide := TAtlasLiveTemplates.LoadFolder(TAtlasEditorCompletion.IdeTemplateFolder, Stats);
    Own := TAtlasSnippets.LoadFolder(TAtlasEditorCompletion.SnippetFolder, Errors);
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
      FPage.Catalog.Save(TAtlasEditorCompletion.SnippetFolder);
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

{ TAtlasOptionsRegistration }

class procedure TAtlasOptionsRegistration.Register(const AResetHistory: TProc);
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    Options := TAtlasAddInOptions.Create(AResetHistory);
    Services.RegisterAddInOptions(Options);
    SnippetOptions := TAtlasSnippetOptions.Create;
    Services.RegisterAddInOptions(SnippetOptions);
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
    if Options <> nil then
      Services.UnregisterAddInOptions(Options);
  end;
  SnippetOptions := nil;
  Options := nil;
end;

end.
