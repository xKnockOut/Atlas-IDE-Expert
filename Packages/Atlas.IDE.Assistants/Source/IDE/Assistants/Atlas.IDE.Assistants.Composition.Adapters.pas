unit Atlas.IDE.Assistants.Composition.Adapters;

// Teil der Komposition des Moduls KI-Assistenten, der Adapter erzeugt: HTTP für
// die KI-Anbieter und den Anmeldespeicher von Windows für ihre Schlüssel (#1922),
// die Anbieter der IDE über ToolsAPI.AI als Quelle für einfache Aufgaben (#2744) und
// den Eintrag „Atlas (…)“ bei Smart CodeInsight der IDE (#2745).
// Nur Atlas.IDE.Assistants.Composition bindet diese Unit ein.

interface

uses
  Atlas.IDE.Contracts.AiText,
  Atlas.UI.Assistants.SettingsSection;

/// <summary>Haken der Einstellungsseite für die Schlüssel der KI-Anbieter.</summary>
function AiKeyHooks: TAtlasAssistantsKeyHooks;
/// <summary>„Verbindung testen“ und „Modelle abrufen“ der Einstellungsseite (#2056); ab der Anmeldung.</summary>
procedure StartAiProbe;
/// <summary>Bricht laufende Proben ab und wartet ihre Threads ab (Regel 3).</summary>
procedure StopAiProbe;
/// <summary>Teil „AiGhostText“ (#1922): Schattentext-Anbieter anlegen und bei Base anmelden.</summary>
procedure StartAiGhost;
/// <summary>Bricht die laufende Anfrage ab und meldet den Anbieter bei Base ab (Regel 3).</summary>
procedure StopAiGhost;
/// <summary>Teil „AiGhostText“ läuft.</summary>
function AiGhostStarted: Boolean;
/// <summary>Text vom KI-Anbieter für andere Module (#2462); ab der Anmeldung, die Komposition stellt ihn bereit.
/// </summary>
function StartAiText: IAtlasAiText;
/// <summary>Bricht offene Anfragen ab, wartet die Threads ab und meldet den Fragenden Cancelled (Regel 3).</summary>
procedure StopAiText;
/// <summary>Teil „AiIdePlugin“ (#2745) soll laufen: Schalter an und eigener Anbieter eingerichtet.</summary>
function AiIdePluginWanted: Boolean;
/// <summary>Eigenen Anbieter als „Atlas (…)“ bei der IDE anmelden; ASwitch: Modulschalter für „In Atlas einrichten“.
/// </summary>
procedure StartAiIdePlugin(const ASwitch: string);
/// <summary>Bei der IDE abmelden, laufende Anfragen abbrechen (Regel 3).</summary>
procedure StopAiIdePlugin;
function AiIdePluginStarted: Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.AiProviders.Providers.Http,
  Atlas.Core.Credentials.Contract,
  Atlas.Core.Credentials.Providers.Windows,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Assistants.Adapters.AiGhost,
  Atlas.IDE.Assistants.AiProbe,
  Atlas.IDE.Assistants.Adapters.AiText,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Plugin.Assistants,
  Atlas.Core.Assistants.Contract.IdeAi,
  Atlas.IDE.Assistants.Adapters.TextRequests,
  Atlas.IDE.Assistants.Adapters.TextSource,
  Atlas.IDE.Assistants.IdeBridge,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.OptionsDialog,
  Atlas.IDE.Settings.ModuleNodes,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Assistants.Strings,
  Atlas.UI.Assistants.IdePluginFrame,
  Atlas.IDE.Assistants.DailyCount,
  Atlas.IDE.Assistants.Adapters.IdeProviders,
  Atlas.IDE.Assistants.Adapters.IdePlugin;

var
  GAiGhost: TAtlasIdeAiGhost;
  GAiProbe: TAtlasIdeAiProbe;
  /// <summary>GAiTextRef hält den Dienst, GAiText stoppt ihn.</summary>
  GAiText: TAtlasIdeAiText;
  GAiTextRef: IAtlasAiText;
  /// <summary>Anbieter der IDE (#2744) und die Quelle, die andere Module bekommen; jeweils Objekt und Referenz.
  /// </summary>
  GIdeEngine: TAtlasIdeAiEngine;
  GIdeEngineRef: IAtlasIdeAiEngine;
  GIdeText: TAtlasIdeAiTextRequests;
  GIdeTextRef: IAtlasAiText;
  GSource: TAtlasAiTextSource;
  GSourceRef: IAtlasAiText;
  /// <summary>Eintrag „Atlas (…)“ bei Smart CodeInsight (#2745).</summary>
  GIdePlugin: TAtlasIdeAiPluginHost;

/// <summary>Schlüssel des KI-Anbieters AProviderId aus dem Anmeldespeicher; '' ohne Eintrag. Auch im
/// Hintergrund-Thread.</summary>
function ReadAiKey(const AProviderId: string): string;
var
  mStore: IAtlasCredentialStore;
  mUser: string;
begin
  mStore := TAtlasWindowsCredentials.Create;
  if not mStore.Read(TAtlasAiKeys.Target(AProviderId), mUser, Result) then
  begin
    Result := '';
  end;
end;

function HasAiKey(AProviderId: string): Boolean;
begin
  Result := ReadAiKey(AProviderId) <> '';
end;

function StoreAiKey(AProviderId, AKey: string): Boolean;
var
  mStore: IAtlasCredentialStore;
begin
  mStore := TAtlasWindowsCredentials.Create;
  Result := mStore.Write(TAtlasAiKeys.Target(AProviderId), cAiKeyUser, AKey, cAiKeyComment);
end;

procedure DeleteAiKey(AProviderId: string);
var
  mStore: IAtlasCredentialStore;
begin
  mStore := TAtlasWindowsCredentials.Create;
  mStore.Delete(TAtlasAiKeys.Target(AProviderId));
end;

procedure ProbeAi(const AInput: TAtlasAssistantsProbeInput; const ADone: TAtlasAssistantsProbeDone);
begin
  if GAiProbe <> nil then
  begin
    GAiProbe.Probe(AInput, ADone);
  end;
end;

procedure ListAiModels(const AInput: TAtlasAssistantsProbeInput; const ADone: TAtlasAssistantsModelsDone);
begin
  if GAiProbe <> nil then
  begin
    GAiProbe.Models(AInput, ADone);
  end;
end;

function AiKeyHooks: TAtlasAssistantsKeyHooks;
begin
  Result := Default(TAtlasAssistantsKeyHooks);
  Result.Has := HasAiKey;
  Result.Store := StoreAiKey;
  Result.Delete := DeleteAiKey;
  Result.Probe := ProbeAi;
  Result.Models := ListAiModels;
  Result.IdeProviders := TAtlasIdeAiEngine.List;
  Result.OpenIdeOptions := TAtlasIdeAiEngine.OpenOptions;
end;

procedure StartAiProbe;
begin
  GAiProbe := TAtlasIdeAiProbe.Create(TAtlasAiHttpClient.Create, ReadAiKey);
end;

procedure StopAiProbe;
begin
  FreeAndNil(GAiProbe);
end;

procedure StartAiGhost;
begin
  GAiGhost := TAtlasIdeAiGhost.Create(
    function: TLspSession
    begin
      Result := TAtlasIdeHost.RunningSession;
    end, TAtlasAiHttpClient.Create, ReadAiKey,
    TAtlasIdeHost.Warnings());
end;

procedure StopAiGhost;
begin
  FreeAndNil(GAiGhost);
end;

function AiGhostStarted: Boolean;
begin
  Result := GAiGhost <> nil;
end;

/// <summary>Eigener Transport je Anfrage: Cancel trifft nur sie.</summary>
function NewAiHttp: IAtlasAiHttp;
begin
  Result := TAtlasAiHttpClient.Create;
end;

/// <summary>Antwort der IDE an die offenen Anfragen (Hauptthread).</summary>
procedure IdeReplied(const AId, AText: string; AIsError: Boolean);
begin
  if GIdeText = nil then
  begin
    Exit;
  end;
  if AIsError then
  begin
    GIdeText.Failed(AId, AText);
  end
  else
  begin
    GIdeText.Answered(AId, AText);
  end;
end;

function IdeTextOptions: TAtlasIdeAiTextOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := Default(TAtlasIdeAiTextOptions);
  Result.Enabled := mSettings.AssistantsIdeProvider;
  Result.Wanted := mSettings.AssistantsIdeProviderName;
end;

function SourceOptions: TAtlasAiTextSourceOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := Default(TAtlasAiTextSourceOptions);
  Result.Source := mSettings.AssistantsTextSource;
  Result.Exclude := mSettings.AssistantsExclude;
end;

function StartAiText: IAtlasAiText;
begin
  GAiText := TAtlasIdeAiText.Create(NewAiHttp, ReadAiKey, HasAiKey);
  GAiTextRef := GAiText;
  GIdeEngine := TAtlasIdeAiEngine.Create(IdeReplied);
  GIdeEngineRef := GIdeEngine;
  GIdeText := TAtlasIdeAiTextRequests.Create(GIdeEngineRef, IdeTextOptions,
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.IdeRefused));
  GIdeTextRef := GIdeText;
  GSource := TAtlasAiTextSource.Create(GAiTextRef, GIdeTextRef, SourceOptions,
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.TextExcluded));
  GSourceRef := GSource;
  Result := GSourceRef;
end;

procedure StopAiText;
begin
  // Rückwärts zum Aufbau: Quelle, Anfragen an die IDE samt Notifiern, eigener Anbieter.
  if GSource <> nil then
  begin
    GSource.Stop;
  end;
  if GIdeText <> nil then
  begin
    GIdeText.Stop;
  end;
  if GIdeEngine <> nil then
  begin
    GIdeEngine.Stop;
  end;
  if GAiText <> nil then
  begin
    GAiText.Stop;
  end;
  GSource := nil;
  GSourceRef := nil;
  GIdeText := nil;
  GIdeTextRef := nil;
  GIdeEngine := nil;
  GIdeEngineRef := nil;
  GAiText := nil;
  GAiTextRef := nil;
end;

{ Eintrag „Atlas (…)“ bei Smart CodeInsight (#2745) }

function AiIdePluginWanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.AssistantsRegisterInIde and (GAiText <> nil) and GAiText.Ready;
end;

/// <summary>Anfrage der IDE zur Tagesgrenze zählen; '' wenn sie zählt.</summary>
function TakeIdeRequest: string;
var
  mLimit: Integer;
begin
  Result := '';
  mLimit := TAtlasIdeSettings.Current.AssistantsDailyLimit;
  if not TAtlasIdeAiDailyCount.TryTake(mLimit) then
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BridgeLimit, [mLimit]);
  end;
end;

/// <summary>Modelle des OpenAI-kompatiblen Anbieters nach den gespeicherten Einstellungen.</summary>
procedure ListOwnModels(const ADone: TAtlasIdeAiModelsDone);
var
  mSettings: TAtlasPluginSettings;
  mInput: TAtlasAssistantsProbeInput;
begin
  mSettings := TAtlasIdeSettings.Current;
  mInput := Default(TAtlasAssistantsProbeInput);
  mInput.ProviderId := cAssistantsProviderNames[2];
  mInput.Model := mSettings.AssistantsOpenAiModel;
  mInput.Url := mSettings.AssistantsOpenAiUrl;
  mInput.TimeoutMs := mSettings.AssistantsOpenAiTimeoutMs;
  ListAiModels(mInput,
    procedure(const AModels: TArray<string>; const AText: string)
    begin
      if Length(AModels) = 0 then
      begin
        ADone(AModels, AText);
      end
      else
      begin
        ADone(AModels, '');
      end;
    end);
end;

/// <summary>Modellliste nur beim OpenAI-kompatiblen Anbieter (/models).</summary>
function ModelLister: TAtlasIdeAiModelLister;
begin
  Result := nil;
  if SameText(TAtlasIdeSettings.Current.AssistantsProvider, cAssistantsProviderNames[2]) then
  begin
    Result := ListOwnModels;
  end;
end;

procedure PostToMainThread(const AWork: TThreadProcedure);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Settings, AWork);
end;

function PluginView: TAtlasIdePluginFrameView;
begin
  Result := Default(TAtlasIdePluginFrameView);
  if (GAiText <> nil) and GAiText.Ready then
  begin
    Result.Provider := GAiText.ProviderName;
  end;
  Result.Today := TAtlasIdeAiDailyCount.Today;
  Result.Limit := TAtlasIdeSettings.Current.AssistantsDailyLimit;
end;

/// <summary>Im offenen Optionsdialog zum Knoten des Moduls springen.</summary>
function OpenAtlasPage(const ASwitch: string): TProc;
begin
  Result :=
    procedure
    begin
      if not TAtlasIdeOptionsDialog.SelectNode([TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesNode),
        TAtlasModuleNodes.NameOfSwitch(ASwitch)]) then
      begin
        TAtlasGuard.Log('Smart CodeInsight: Seite des Moduls KI-Assistenten nicht gefunden'); // german-ok Protokoll
      end;
    end;
end;

procedure StartAiIdePlugin(const ASwitch: string);
var
  mTexts: TAtlasIdeAiBridgeTexts;
  mHooks: TAtlasIdeAiPluginHooks;
begin
  mTexts := Default(TAtlasIdeAiBridgeTexts);
  mTexts.NotReady := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.BridgeNotReady);
  mTexts.NoModels := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.BridgeNoModels);
  mHooks := Default(TAtlasIdeAiPluginHooks);
  mHooks.View := PluginView;
  mHooks.OpenAtlas := OpenAtlasPage(ASwitch);
  GIdePlugin := TAtlasIdeAiPluginHost.Create(TAtlasIdeAiBridge.Create(GAiTextRef, TakeIdeRequest, ModelLister(),
    PostToMainThread, mTexts, nil), mHooks);
end;

procedure StopAiIdePlugin;
begin
  FreeAndNil(GIdePlugin);
end;

function AiIdePluginStarted: Boolean;
begin
  Result := GIdePlugin <> nil;
end;

end.
