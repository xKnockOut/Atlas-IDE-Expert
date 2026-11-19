unit Atlas.IDE.Assistants.Composition.Adapters;

// Teil der Komposition des Moduls KI-Assistenten, der Adapter erzeugt: HTTP für
// die KI-Anbieter und den Anmeldespeicher von Windows für ihre Schlüssel (#1922).
// Nur Atlas.IDE.Assistants.Composition bindet diese Unit ein.

interface

uses
  Atlas.UI.Assistants.SettingsSection;

/// <summary>Haken der Einstellungsseite für die Schlüssel der KI-Anbieter.</summary>
function AiKeyHooks: TAtlasAssistantsKeyHooks;
/// <summary>Teil „AiGhostText“ (#1922): Schattentext-Anbieter anlegen und bei Base anmelden.</summary>
procedure StartAiGhost;
/// <summary>Bricht die laufende Anfrage ab und meldet den Anbieter bei Base ab (Regel 3).</summary>
procedure StopAiGhost;
/// <summary>Teil „AiGhostText“ läuft.</summary>
function AiGhostStarted: Boolean;

implementation

uses
  System.SysUtils,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.AiProviders.Adapters.Http,
  Atlas.Core.Credentials.Contract,
  Atlas.Core.Credentials.Adapters.Windows,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Assistants.AiGhost;

var
  GAiGhost: TAtlasIdeAiGhost;

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

function AiKeyHooks: TAtlasAssistantsKeyHooks;
begin
  Result := Default(TAtlasAssistantsKeyHooks);
  Result.Has := HasAiKey;
  Result.Store := StoreAiKey;
  Result.Delete := DeleteAiKey;
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

end.
