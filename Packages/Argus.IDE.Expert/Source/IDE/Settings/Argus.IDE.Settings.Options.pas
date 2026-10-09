unit Argus.IDE.Settings.Options;

// Meldet die Seite „Argus“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).

interface

uses
  System.SysUtils;

type
  TArgusOptionsRegistration = class
  public
    class procedure Register(const AResetHistory: TProc); static;
    class procedure Unregister; static;
  end;

implementation

uses
  Vcl.Forms,
  ToolsAPI,
  Argus.Core.Settings.Plugin,
  Argus.UI.Settings.Page,
  Argus.IDE.Settings.Store;

type
  TArgusAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TArgusSettingsPage;
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

var
  Options: INTAAddInOptions;

{ TArgusAddInOptions }

constructor TArgusAddInOptions.Create(const AResetHistory: TProc);
begin
  inherited Create;
  FResetHistory := AResetHistory;
end;

function TArgusAddInOptions.GetArea: string;
begin
  // Leer: unter „Drittanbieter“, wie die Open Tools API empfiehlt.
  Result := '';
end;

function TArgusAddInOptions.GetCaption: string;
begin
  Result := 'Argus';
end;

function TArgusAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TArgusSettingsPage;
end;

procedure TArgusAddInOptions.FrameCreated(AFrame: TCustomFrame);
begin
  FPage := AFrame as TArgusSettingsPage;
  FPage.LoadFrom(TArgusIdeSettings.Current);
  FPage.OnResetHistory := FResetHistory;
end;

procedure TArgusAddInOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TArgusPluginSettings;
begin
  if Accepted and (FPage <> nil) then
  begin
    Settings := TArgusIdeSettings.Current;
    FPage.SaveTo(Settings);
    TArgusIdeSettings.Update(Settings);
  end;
  FPage := nil;
end;

function TArgusAddInOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TArgusAddInOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TArgusAddInOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TArgusOptionsRegistration }

class procedure TArgusOptionsRegistration.Register(const AResetHistory: TProc);
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    Options := TArgusAddInOptions.Create(AResetHistory);
    Services.RegisterAddInOptions(Options);
  end;
end;

class procedure TArgusOptionsRegistration.Unregister;
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options <> nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
    Services.UnregisterAddInOptions(Options);
  Options := nil;
end;

end.
