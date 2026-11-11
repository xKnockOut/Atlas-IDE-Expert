unit Atlas.IDE.ElementHelp.Keys;

// F1 zu Atlas-Elementen (#1886) für Base: fragt den laufenden Anbieter von IAtlasHelpProvider
// (Atlas.IDE.Contracts.Help, Modul Hilfe) bei jedem Aufruf neu über die Registry (Regel 3: das Modul kann
// inzwischen fort sein). AddKey hängt an einen Frame (Atlas-Fenster, Optionsseite) eine Aktion mit F1: Sie ist
// nur aktiv, solange ein Anbieter zur Kennung unter dem Fokus eine Seite kennt; sonst geht F1 wie vorher an die
// IDE. Jedes Atlas-Dockfenster bekommt F1 über TAtlasIdeDockWindow.OnFrameCreated: Kennung ist das Fenster
// selbst, SetWindowTopic kann je Fenster eine genauere liefern (Atlas-Prüfung: Regel des gewählten Befunds).
// Nur im Hauptthread verwenden.

interface

uses
  System.Classes,
  Atlas.IDE.Contracts.Help;

type
  /// <summary>Kennung des Elements unter dem Fokus; False ohne.</summary>
  TAtlasHelpTopicFunc = reference to function(out ATopic: TAtlasHelpTopic): Boolean;

  TAtlasIdeHelp = class
  public const
    /// <summary>Kennung der Optionsseite „Atlas“ ohne Einstellung unter dem Fokus.</summary>
    cOptionsWindow = 'AtlasOptions';
  public
    class function Topic(AKind: TAtlasHelpKind; const AId: string): TAtlasHelpTopic; static;
    /// <summary>Kennt ein laufendes Modul eine Seite zu ATopic?</summary>
    class function Available(const ATopic: TAtlasHelpTopic): Boolean; static;
    /// <summary>Seite zu ATopic zeigen; False ohne Anbieter oder ohne Seite.</summary>
    class function Show(const ATopic: TAtlasHelpTopic): Boolean; static;
    /// <summary>F1 in AOwner (Frame eines Atlas-Fensters, Optionsseite): Hilfe zu ATopicOf. Die Aktion gehört
    /// AOwner und geht mit ihm.</summary>
    class procedure AddKey(AOwner: TComponent; const ATopicOf: TAtlasHelpTopicFunc); static;
    /// <summary>Genauere Kennung für F1 im Dockfenster AWindow; ohne bzw. bei False gilt das Fenster.</summary>
    class procedure SetWindowTopic(const AWindow: string; const ATopicOf: TAtlasHelpTopicFunc); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions;

type
  /// <summary>Hält Aktion und Rückruf; gehört dem Frame.</summary>
  THelpKey = class(TComponent)
  private
    FTopicOf: TAtlasHelpTopicFunc;
    procedure ActionUpdate(Sender: TObject);
    procedure ActionExecute(Sender: TObject);
  end;

var
  /// <summary>Genauere Kennungen je Dockfenster (SetWindowTopic).</summary>
  GWindowTopics: TDictionary<string, TAtlasHelpTopicFunc>;

/// <summary>Erster laufender Anbieter; False ohne.</summary>
function Find(out AProvider: IAtlasHelpProvider): Boolean;
var
  mItem: IInterface;
begin
  AProvider := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasHelpProvider) do
  begin
    if Supports(mItem, IAtlasHelpProvider, AProvider) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ THelpKey }

procedure THelpKey.ActionUpdate(Sender: TObject);
var
  mTopic: TAtlasHelpTopic;
begin
  (Sender as TAction).Enabled := Assigned(FTopicOf) and FTopicOf(mTopic) and TAtlasIdeHelp.Available(mTopic);
end;

procedure THelpKey.ActionExecute(Sender: TObject);
var
  mTopic: TAtlasHelpTopic;
begin
  if Assigned(FTopicOf) and FTopicOf(mTopic) then
  begin
    TAtlasIdeHelp.Show(mTopic);
  end;
end;

{ TAtlasIdeHelp }

class function TAtlasIdeHelp.Topic(AKind: TAtlasHelpKind; const AId: string): TAtlasHelpTopic;
begin
  Result.Kind := AKind;
  Result.Id := AId;
end;

class function TAtlasIdeHelp.Available(const ATopic: TAtlasHelpTopic): Boolean;
var
  mProvider: IAtlasHelpProvider;
begin
  Result := (ATopic.Id <> '') and Find(mProvider) and mProvider.HasHelp(ATopic);
end;

class function TAtlasIdeHelp.Show(const ATopic: TAtlasHelpTopic): Boolean;
var
  mProvider: IAtlasHelpProvider;
begin
  Result := False;
  if (ATopic.Id <> '') and Find(mProvider) then
  begin
    try
      Result := mProvider.ShowHelp(ATopic);
    except
      on mError: Exception do
      begin
        TAtlasGuard.Log('F1 ' + ATopic.Id + ': ' + mError.Message);
      end;
    end;
  end;
end;

class procedure TAtlasIdeHelp.AddKey(AOwner: TComponent; const ATopicOf: TAtlasHelpTopicFunc);
var
  mKey: THelpKey;
  mList: TActionList;
  mAction: TAction;
begin
  if AOwner = nil then
  begin
    Exit;
  end;
  mKey := THelpKey.Create(AOwner);
  mKey.FTopicOf := ATopicOf;
  mList := TActionList.Create(AOwner);
  mAction := TAction.Create(mList);
  mAction.ActionList := mList;
  mAction.ShortCut := ShortCut(VK_F1, []);
  mAction.OnUpdate := mKey.ActionUpdate;
  mAction.OnExecute := mKey.ActionExecute;
end;

class procedure TAtlasIdeHelp.SetWindowTopic(const AWindow: string; const ATopicOf: TAtlasHelpTopicFunc);
begin
  GWindowTopics.AddOrSetValue(AWindow, ATopicOf);
end;

/// <summary>F1 für den neuen Frame des Dockfensters AWindow.</summary>
procedure WindowFrameCreated(AWindow: string; AFrame: TCustomFrame);
begin
  TAtlasIdeHelp.AddKey(AFrame,
    function(out ATopic: TAtlasHelpTopic): Boolean
    var
      mTopicOf: TAtlasHelpTopicFunc;
    begin
      Result := GWindowTopics.TryGetValue(AWindow, mTopicOf) and Assigned(mTopicOf) and mTopicOf(ATopic);
      if not Result then
      begin
        ATopic := TAtlasIdeHelp.Topic(TAtlasHelpKind.Window, AWindow);
        Result := True;
      end;
    end);
end;

initialization
  GWindowTopics := TDictionary<string, TAtlasHelpTopicFunc>.Create;
  TAtlasIdeDockWindow.OnFrameCreated := WindowFrameCreated;

finalization
  TAtlasIdeDockWindow.OnFrameCreated := nil;
  FreeAndNil(GWindowTopics);

end.
