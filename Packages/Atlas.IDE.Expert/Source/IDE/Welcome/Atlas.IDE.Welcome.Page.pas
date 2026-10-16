unit Atlas.IDE.Welcome.Page;

// Atlas-Bereiche auf der Willkommensseite der IDE (#753) über
// ToolsAPI.WelcomePage (RAD Studio 12 und 13, ADR 0011): Jeder Bereich ist ein
// Inhalts-Plugin (INTAWelcomePagePlugin + INTAWelcomePageContentPluginCreator).
// Die IDE bekommt einen Rahmen mit Titelzeile
// (WelcomePagePluginService.CreateCaptionFrame), in den der Atlas-Frame als
// Client gesetzt wird (INTAWelcomePageCaptionFrame.SetClientFrame). So lassen
// sich die Atlas-Bereiche wie die eingebauten verschieben, ein- und
// ausblenden. Der Client folgt dem IDE-Thema (IOTAIDEThemingServices).
// Register ersetzt ein Plugin mit derselben Kennung; RemoveAll meldet beim
// Entladen alle ab.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Welcome.Frame;

type
  TAtlasWelcomeClientFactory = reference to function(AOwner: TComponent): TAtlasWelcomeFrame;

  TAtlasIdeWelcomePage = class
  public
    /// <summary>Bietet die IDE die Schnittstelle der Willkommensseite an?</summary>
    class function Available: Boolean; static;
    /// <summary>Plugin APluginId mit Titel ACaption anmelden; AFactory erzeugt den Inhalt, wenn die IDE ihn
    /// zeigt.</summary>
    class procedure Register(const APluginId, ACaption: string; const AFactory: TAtlasWelcomeClientFactory); static;
    class procedure Unregister(const APluginId: string); static;
    class procedure RemoveAll; static;
    /// <summary>Angemeldete Kennungen.</summary>
    class function Registered: TArray<string>; static;
    /// <summary>Inhalt des Plugins, solange die IDE ihn zeigt; sonst nil.</summary>
    class function Client(const APluginId: string): TAtlasWelcomeFrame; static;
    /// <summary>IDE-Thema auf alle gezeigten Inhalte anwenden.</summary>
    class procedure ApplyTheme; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.WelcomePage,
  Atlas.Core.Diagnostics.Guard;

type
  TPlugin = class(TInterfacedObject, INTAWelcomePagePlugin, INTAWelcomePageContentPluginCreator)
  private
    FId: string;
    FCaption: string;
    FFactory: TAtlasWelcomeClientFactory;
    FView: TFrame;
    FClient: TAtlasWelcomeFrame;
    FIconIndex: Integer;
    { INTAWelcomePageContentPluginCreator }
    function GetView: TFrame;
    function GetIconIndex: Integer;
    procedure SetIconIndex(const Value: Integer);
  public
    constructor Create(const AId, ACaption: string; const AFactory: TAtlasWelcomeClientFactory);
    destructor Destroy; override;
    { INTAWelcomePagePlugin }
    function GetPluginID: string;
    function GetPluginName: string;
    function GetPluginVisible: Boolean;
    { INTAWelcomePageContentPluginCreator }
    function CreateView: TFrame;
    procedure DestroyView;
    function GetIcon: TGraphicArray;
  end;

var
  // Kennung → Plugin; die IDE hält eigene Referenzen, wir nur zum Abmelden und für Client.
  Plugins: TDictionary<string, TPlugin>;

procedure Theme(AFrame: TFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

{ TPlugin }

constructor TPlugin.Create(const AId, ACaption: string; const AFactory: TAtlasWelcomeClientFactory);
begin
  inherited Create;
  FId := AId;
  FCaption := ACaption;
  FFactory := AFactory;
  FIconIndex := -1;
end;

destructor TPlugin.Destroy;
begin
  DestroyView;
  inherited;
end;

function TPlugin.GetPluginID: string;
begin
  Result := FId;
end;

function TPlugin.GetPluginName: string;
begin
  Result := FCaption;
end;

function TPlugin.GetPluginVisible: Boolean;
begin
  Result := True;
end;

function TPlugin.CreateView: TFrame;
var
  Caption: INTAWelcomePageCaptionFrame;
begin
  if FView = nil then
  begin
    FView := WelcomePagePluginService.CreateCaptionFrame(FId, FCaption, nil);
    if Supports(FView, INTAWelcomePageCaptionFrame, Caption) then
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          // Der Rahmen besitzt den Inhalt und gibt ihn mit sich frei.
          FClient := FFactory(FView);
          if FClient <> nil then
          begin
            Caption.SetClientFrame(FClient);
            Theme(FClient);
            FClient.UpdateContent;
          end;
        end);
  end;
  Result := FView;
end;

procedure TPlugin.DestroyView;
begin
  FClient := nil;
  FreeAndNil(FView);
end;

function TPlugin.GetIcon: TGraphicArray;
begin
  Result := [];
end;

function TPlugin.GetIconIndex: Integer;
begin
  Result := FIconIndex;
end;

procedure TPlugin.SetIconIndex(const Value: Integer);
begin
  FIconIndex := Value;
end;

function TPlugin.GetView: TFrame;
begin
  Result := FView;
end;

{ TAtlasIdeWelcomePage }

class function TAtlasIdeWelcomePage.Available: Boolean;
begin
  Result := Assigned(WelcomePagePluginService);
end;

class procedure TAtlasIdeWelcomePage.Register(const APluginId, ACaption: string;
  const AFactory: TAtlasWelcomeClientFactory);
var
  Plugin: TPlugin;
begin
  if not Available then
    Exit;
  Unregister(APluginId);
  if Plugins = nil then
    Plugins := TDictionary<string, TPlugin>.Create;
  Plugin := TPlugin.Create(APluginId, ACaption, AFactory);
  Plugins.Add(LowerCase(APluginId), Plugin);
  WelcomePagePluginService.RegisterPluginCreator(Plugin);
end;

class procedure TAtlasIdeWelcomePage.Unregister(const APluginId: string);
begin
  if (Plugins = nil) or not Plugins.ContainsKey(LowerCase(APluginId)) then
    Exit;
  Plugins.Remove(LowerCase(APluginId));
  if Available then
    WelcomePagePluginService.UnRegisterPlugin(APluginId);
end;

class procedure TAtlasIdeWelcomePage.RemoveAll;
var
  Id: string;
begin
  for Id in Registered do
    Unregister(Id);
  FreeAndNil(Plugins);
end;

class function TAtlasIdeWelcomePage.Registered: TArray<string>;
var
  Plugin: TPlugin;
begin
  Result := nil;
  if Plugins <> nil then
    for Plugin in Plugins.Values do
      Result := Result + [Plugin.FId];
end;

class function TAtlasIdeWelcomePage.Client(const APluginId: string): TAtlasWelcomeFrame;
var
  Plugin: TPlugin;
begin
  Result := nil;
  if (Plugins <> nil) and Plugins.TryGetValue(LowerCase(APluginId), Plugin) then
    Result := Plugin.FClient;
end;

class procedure TAtlasIdeWelcomePage.ApplyTheme;
var
  Plugin: TPlugin;
begin
  if Plugins = nil then
    Exit;
  for Plugin in Plugins.Values do
    if Plugin.FClient <> nil then
    begin
      Theme(Plugin.FClient);
      Plugin.FClient.UpdateContent;
      // Auch Panels und Überschriften, nicht nur die Zeichenflächen: sonst bleibt der alte Hintergrund stehen.
      if Plugin.FClient.HandleAllocated then
        RedrawWindow(Plugin.FClient.Handle, nil, 0, RDW_ERASE or RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_FRAME);
    end;
end;

end.
