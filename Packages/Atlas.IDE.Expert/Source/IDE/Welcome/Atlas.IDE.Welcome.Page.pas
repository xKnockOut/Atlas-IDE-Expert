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
// Beim Beenden baut die IDE ihre Willkommensseite vor dem Entladen von Atlas
// ab und gibt dabei die Plugins frei, obwohl sie noch angemeldet sind. Ein
// freigegebenes Plugin trägt sich deshalb selbst aus Plugins aus, und danach
// ruft Atlas den Dienst nicht mehr auf (#1091: „Welcome: EAccessViolation“
// beim Entladen). Den Rahmen gibt die IDE mit ihrer
// Seite frei; ein Wächter (FreeNotification) vergisst ihn dann, damit
// DestroyView ihn nicht ein zweites Mal freigibt.

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
  TPlugin = class;

  /// <summary>Meldet, wenn die IDE Rahmen oder Inhalt freigibt (#1091).</summary>
  TViewWatch = class(TComponent)
  private
    FPlugin: TPlugin;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TPlugin = class(TInterfacedObject, INTAWelcomePagePlugin, INTAWelcomePageContentPluginCreator)
  private
    FWatch: TViewWatch;
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
  // Die IDE hat ein noch angemeldetes Plugin freigegeben: Sie baut ihre
  // Willkommensseite ab (Beenden), der Dienst ist nicht mehr aufrufbar (#1091).
  ServiceGone: Boolean;

procedure Theme(AFrame: TFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and
    Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

{ TViewWatch }

procedure TViewWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation <> opRemove) or (FPlugin = nil) then
    Exit;
  if AComponent = FPlugin.FClient then
    FPlugin.FClient := nil;
  if AComponent = FPlugin.FView then
  begin
    // Der Rahmen besitzt den Inhalt: mit ihm ist auch der Inhalt weg.
    FPlugin.FView := nil;
    FPlugin.FClient := nil;
  end;
end;

{ TPlugin }

constructor TPlugin.Create(const AId, ACaption: string; const AFactory: TAtlasWelcomeClientFactory);
begin
  inherited Create;
  FWatch := TViewWatch.Create(nil);
  FWatch.FPlugin := Self;
  FId := AId;
  FCaption := ACaption;
  FFactory := AFactory;
  FIconIndex := -1;
end;

destructor TPlugin.Destroy;
begin
  // Gibt die IDE uns frei, ohne dass wir abgemeldet haben, darf das Wörterbuch nicht weiter auf uns zeigen.
  if (Plugins <> nil) and Plugins.ContainsKey(LowerCase(FId)) and (Plugins[LowerCase(FId)] = Self) then
  begin
    Plugins.Remove(LowerCase(FId));
    ServiceGone := True;
  end;
  DestroyView;
  FWatch.FPlugin := nil;
  FreeAndNil(FWatch);
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
    if FView <> nil then
      FView.FreeNotification(FWatch);
    if Supports(FView, INTAWelcomePageCaptionFrame, Caption) then
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          // Der Rahmen besitzt den Inhalt und gibt ihn mit sich frei.
          FClient := FFactory(FView);
          if FClient <> nil then
          begin
            FClient.FreeNotification(FWatch);
            Caption.SetClientFrame(FClient);
            Theme(FClient);
            FClient.UpdateContent;
          end;
        end);
  end;
  Result := FView;
end;

procedure TPlugin.DestroyView;
var
  View: TFrame;
begin
  if FClient <> nil then
    FClient.RemoveFreeNotification(FWatch);
  FClient := nil;
  // Nur einen Rahmen freigeben, der noch lebt; hat die IDE ihn schon freigegeben, ist FView nil (TViewWatch).
  View := FView;
  FView := nil;
  if View <> nil then
  begin
    View.RemoveFreeNotification(FWatch);
    View.Free;
  end;
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
  ServiceGone := False;
  WelcomePagePluginService.RegisterPluginCreator(Plugin);
end;

class procedure TAtlasIdeWelcomePage.Unregister(const APluginId: string);
begin
  if (Plugins = nil) or not Plugins.ContainsKey(LowerCase(APluginId)) then
    Exit;
  Plugins.Remove(LowerCase(APluginId));
  if Available and not ServiceGone then
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
