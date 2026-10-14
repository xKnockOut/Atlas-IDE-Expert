unit Atlas.IDE.Settings.Options;

// Meldet die Seite „Atlas“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Daneben die Seite „Atlas.Tastenkonflikte“ (#494): Wer welche Taste belegt,
// fragt sie über TAtlasIdeKeys.Owner ab; nach dem Speichern belegt die
// Komposition die Tasten über Settings.OnChanged neu.
// Abschnitt Symbolindex (#492): Kennzahlen aus atlas.server.status, „Index neu
// aufbauen“ und „Index löschen“ über die Befehle des Servers.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Befehl an den Server; Ergebnis gehört dem Aufrufer, nil ohne Server.</summary>
  TAtlasServerCommand = reference to function(ACommand: string): TJSONValue;

  TAtlasOptionsRegistration = class
  public
    class procedure Register(const AResetHistory: TProc; const ACommand: TAtlasServerCommand); static;
    class procedure Unregister; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Progress,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Keys,
  Atlas.UI.Strings,
  Atlas.IDE.Commands.Keys,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.CodeInsight.Manager,
  Atlas.IDE.Settings.Store;

type
  TAtlasAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsPage;
    FResetHistory: TProc;
    FCommand: TAtlasServerCommand;
    function Run(const ACommand: string; out AAnswer: TJSONValue): Boolean;
  public
    constructor Create(const AResetHistory: TProc; const ACommand: TAtlasServerCommand);
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

var
  Options: INTAAddInOptions;
  KeysOptions: INTAAddInOptions;

{ TAtlasAddInOptions }

constructor TAtlasAddInOptions.Create(const AResetHistory: TProc; const ACommand: TAtlasServerCommand);
begin
  inherited Create;
  FResetHistory := AResetHistory;
  FCommand := ACommand;
end;

function TAtlasAddInOptions.Run(const ACommand: string; out AAnswer: TJSONValue): Boolean;
begin
  AAnswer := nil;
  if Assigned(FCommand) then
    AAnswer := FCommand(ACommand);
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
  FPage.DefaultServerPath := TAtlasCodeInsightManager.DefaultServerPath;
  FPage.OnResetHistory := FResetHistory;
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

{ TAtlasOptionsRegistration }

class procedure TAtlasOptionsRegistration.Register(const AResetHistory: TProc; const ACommand: TAtlasServerCommand);
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    Options := TAtlasAddInOptions.Create(AResetHistory, ACommand);
    Services.RegisterAddInOptions(Options);
    KeysOptions := TAtlasKeysOptions.Create;
    Services.RegisterAddInOptions(KeysOptions);
  end;
end;

class procedure TAtlasOptionsRegistration.Unregister;
var
  Services: INTAEnvironmentOptionsServices;
begin
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    if KeysOptions <> nil then
      Services.UnregisterAddInOptions(KeysOptions);
    if Options <> nil then
      Services.UnregisterAddInOptions(Options);
  end;
  KeysOptions := nil;
  Options := nil;
end;

end.
