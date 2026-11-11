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
// Die Plugins sind abschaltbar mit welcomePage.ideWelcomePage (#761). RemoveAll gibt vor dem Abmelden
// die Atlas-Inhalte in den Rahmen der IDE frei: Kein Objekt einer Atlas-Klasse
// soll in einem Fenster der IDE stehen bleiben, das die IDE erst nach dem
// Entladen von Atlas abbaut (vgl. #1233, Spalten der Zeilenleiste).

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
  mTheming: IOTAIDEThemingServices;
begin
  if (AFrame <> nil) and Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) and
    mTheming.IDEThemingEnabled then
  begin
    mTheming.ApplyTheme(AFrame);
  end;
end;

{ TViewWatch }

procedure TViewWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation <> opRemove) or (FPlugin = nil) then
  begin
    Exit;
  end;
  if AComponent = FPlugin.FClient then
  begin
    FPlugin.FClient := nil;
  end;
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
  mCaption: INTAWelcomePageCaptionFrame;
begin
  if FView = nil then
  begin
    FView := WelcomePagePluginService.CreateCaptionFrame(FId, FCaption, nil);
    if FView <> nil then
    begin
      FView.FreeNotification(FWatch);
    end;
    if Supports(FView, INTAWelcomePageCaptionFrame, mCaption) then
    begin
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          // Der Rahmen besitzt den Inhalt und gibt ihn mit sich frei.
          FClient := FFactory(FView);
          if FClient <> nil then
          begin
            FClient.FreeNotification(FWatch);
            mCaption.SetClientFrame(FClient);
            Theme(FClient);
            FClient.UpdateContent;
          end;
        end);
    end;
  end;
  Result := FView;
end;

procedure TPlugin.DestroyView;
var
  mView: TFrame;
begin
  if FClient <> nil then
  begin
    FClient.RemoveFreeNotification(FWatch);
  end;
  FClient := nil;
  // Nur einen Rahmen freigeben, der noch lebt; hat die IDE ihn schon freigegeben, ist FView nil (TViewWatch).
  mView := FView;
  FView := nil;
  if mView <> nil then
  begin
    mView.RemoveFreeNotification(FWatch);
    mView.Free;
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
  mPlugin: TPlugin;
begin
  if not Available then
  begin
    Exit;
  end;
  Unregister(APluginId);
  if Plugins = nil then
  begin
    Plugins := TDictionary<string, TPlugin>.Create;
  end;
  mPlugin := TPlugin.Create(APluginId, ACaption, AFactory);
  Plugins.Add(LowerCase(APluginId), mPlugin);
  ServiceGone := False;
  WelcomePagePluginService.RegisterPluginCreator(mPlugin);
end;

class procedure TAtlasIdeWelcomePage.Unregister(const APluginId: string);
begin
  if (Plugins = nil) or not Plugins.ContainsKey(LowerCase(APluginId)) then
  begin
    Exit;
  end;
  Plugins.Remove(LowerCase(APluginId));
  if Available and not ServiceGone then
  begin
    WelcomePagePluginService.UnRegisterPlugin(APluginId);
  end;
end;

class procedure TAtlasIdeWelcomePage.RemoveAll;
var
  mId: string;
  mPlugin: TPlugin;
  mClient: TAtlasWelcomeFrame;
begin
  // Nur den Inhalt (Atlas-Klasse) freigeben, nicht den Rahmen: Der gehört der IDE und kann noch in ihrer Seite
  // stehen. Der Inhalt nimmt sich beim Freigeben selbst aus dem Rahmen.
  if Plugins <> nil then
  begin
    for mPlugin in Plugins.Values do
    begin
      mClient := mPlugin.FClient;
      mPlugin.FClient := nil;
      if mClient <> nil then
      begin
        mClient.RemoveFreeNotification(mPlugin.FWatch);
        mClient.Free;
      end;
    end;
  end;
  for mId in Registered do
  begin
    Unregister(mId);
  end;
  FreeAndNil(Plugins);
end;

class function TAtlasIdeWelcomePage.Registered: TArray<string>;
var
  mPlugin: TPlugin;
begin
  Result := nil;
  if Plugins <> nil then
  begin
    for mPlugin in Plugins.Values do
    begin
      Result := Result + [mPlugin.FId];
    end;
  end;
end;

class function TAtlasIdeWelcomePage.Client(const APluginId: string): TAtlasWelcomeFrame;
var
  mPlugin: TPlugin;
begin
  Result := nil;
  if (Plugins <> nil) and Plugins.TryGetValue(LowerCase(APluginId), mPlugin) then
  begin
    Result := mPlugin.FClient;
  end;
end;

class procedure TAtlasIdeWelcomePage.ApplyTheme;
var
  mPlugin: TPlugin;
begin
  if Plugins = nil then
  begin
    Exit;
  end;
  for mPlugin in Plugins.Values do
  begin
    if mPlugin.FClient <> nil then
    begin
      Theme(mPlugin.FClient);
      mPlugin.FClient.UpdateContent;
      // Auch Panels und Überschriften, nicht nur die Zeichenflächen: sonst bleibt der alte Hintergrund stehen.
      if mPlugin.FClient.HandleAllocated then
      begin
        RedrawWindow(mPlugin.FClient.Handle, nil, 0, RDW_ERASE or RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_FRAME);
      end;
    end;
  end;
end;

end.
