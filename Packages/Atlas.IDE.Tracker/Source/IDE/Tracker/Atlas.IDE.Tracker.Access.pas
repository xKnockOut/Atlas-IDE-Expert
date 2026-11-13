unit Atlas.IDE.Tracker.Access;

// Zugang des Moduls Tracker zum Issue-Tracker (#765, #1260) und zum
// Build-Server (#763).
// - TAtlasTrackerAccess (IAtlasTrackerAccess): Anbieter, Token und Transport
//   des Issue-Trackers für „Meine Issues“ und den Abschnitt Issue-Tracker.
//   Token im Anmeldespeicher (Ziel "Atlas:tracker:&lt;Server&gt;", Benutzer =
//   Anbieter), verdeckter Dialog, „Authorization: Bearer“ nur über https an die
//   API des Trackers.
// - TAtlasCiAccess (IAtlasCiAccess): Anbieter des Build-Servers nach Namen,
//   Transport mit dem Zugang aus dem Anmeldespeicher und „Zugang zum
//   Build-Server hinterlegen …“ für die Kachel „Testergebnisse“.
// Anmeldespeicher, Transporte und Anbieter kommen als Schnittstellen bzw.
// Fabriken aus Atlas.IDE.Tracker.Composition (Rolle Adapters); diese Unit
// kennt keinen Adapter. Meldungen anonym, ohne Server, Benutzer und Token.
// Transport und Provider laufen auch im Hintergrund-Thread, die Dialoge nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections;

type
  /// <summary>Alle Anbieter des Issue-Trackers, je Aufruf neu (der Hintergrund bekommt eigene).</summary>
  TAtlasTrackerProvidersFactory = reference to function: TArray<IAtlasTrackerProvider>;
  /// <summary>CI-Anbieter zum Namen ("jenkins"), je Aufruf neu; nil, wenn es ihn nicht gibt.</summary>
  TAtlasCiProviderFactory = reference to function(const AName: string): IAtlasCiProvider;

  /// <summary>Was beide Zugänge brauchen: Anmeldespeicher, Transporte und die Meldungsansicht.</summary>
  TAtlasAccessParts = record
    Credentials: IAtlasCiCredentialStore;
    Transports: IAtlasCiTransports;
    /// <summary>Zeile in die Meldungsansicht, sichtbar gemacht (folgt immer auf eine Aktion des Benutzers).</summary>
    Notice: TProc<string>;
  end;

  TAtlasTrackerAccess = class(TInterfacedObject, IAtlasTrackerAccess)
  public const
    cComment = 'Atlas: Issue-Tracker';
  private
    FProviders: TAtlasTrackerProvidersFactory;
    FParts: TAtlasAccessParts;
    procedure Notice(const AText: string);
    procedure SavedOrFailed(AOk: Boolean);
    class procedure Wipe(var AToken: string); static;
  public
    constructor Create(const AProviders: TAtlasTrackerProvidersFactory; const AParts: TAtlasAccessParts);
    function Providers: TArray<IAtlasTrackerProvider>;
    function Provider(const AName: string): IAtlasTrackerProvider;
    function HasToken(const ATarget: TAtlasTrackerTarget): Boolean;
    function EnterToken(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    function RemoveToken(const ATarget: TAtlasTrackerTarget): Boolean;
    function Transport(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  end;

  /// <summary>Zugang zum Build-Server; die Kachel „Testergebnisse“ hält ihn, auch im Hintergrund-Thread.</summary>
  IAtlasCiAccess = interface
    ['{7C1F4E9B-2A6D-4B83-9E50-D84A3C7B1F62}']
    function Provider(const AName: string): IAtlasCiProvider;
    /// <summary>Transport für AJob mit dem Zugang aus dem Anmeldespeicher (ohne Dialog); im Hintergrund.</summary>
    function Transport(const AJob: TAtlasCiJob): IAtlasCiTransport;
    /// <summary>Zugang für AJob abfragen und speichern; beide Felder leer entfernen ihn. True, wenn sich etwas
    /// geändert hat. Hauptthread.</summary>
    function EnterCredentials(const AJob: TAtlasCiJob): Boolean;
  end;

  TAtlasCiAccess = class(TInterfacedObject, IAtlasCiAccess)
  private
    FProviders: TAtlasCiProviderFactory;
    FParts: TAtlasAccessParts;
    procedure Notice(const AText: string);
    function StoredUser(const AJob: TAtlasCiJob): string;
    function Remove(const AJob: TAtlasCiJob): Boolean;
  public
    constructor Create(const AProviders: TAtlasCiProviderFactory; const AParts: TAtlasAccessParts);
    function Provider(const AName: string): IAtlasCiProvider;
    function Transport(const AJob: TAtlasCiJob): IAtlasCiTransport;
    function EnterCredentials(const AJob: TAtlasCiJob): Boolean;
  end;

implementation

uses
  Atlas.UI.Tracker.MyIssues.Strings,
  Atlas.UI.Tracker.TestResults.Strings,
  Atlas.UI.Tracker.CiLogin;

{ TAtlasTrackerAccess }

constructor TAtlasTrackerAccess.Create(const AProviders: TAtlasTrackerProvidersFactory;
  const AParts: TAtlasAccessParts);
begin
  inherited Create;
  FProviders := AProviders;
  FParts := AParts;
end;

class procedure TAtlasTrackerAccess.Wipe(var AToken: string);
begin
  // Die Kopie des Tokens nicht im Speicher liegen lassen.
  if AToken <> '' then
  begin
    UniqueString(AToken);
    FillChar(PChar(AToken)^, Length(AToken) * SizeOf(Char), 0);
  end;
  AToken := '';
end;

procedure TAtlasTrackerAccess.Notice(const AText: string);
begin
  if Assigned(FParts.Notice) then
  begin
    FParts.Notice(AText);
  end;
end;

procedure TAtlasTrackerAccess.SavedOrFailed(AOk: Boolean);
begin
  if AOk then
  begin
    Notice(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginSaved));
  end
  else
  begin
    Notice(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginFailed));
  end;
end;

function TAtlasTrackerAccess.Providers: TArray<IAtlasTrackerProvider>;
begin
  Result := nil;
  if Assigned(FProviders) then
  begin
    Result := FProviders();
  end;
end;

function TAtlasTrackerAccess.Provider(const AName: string): IAtlasTrackerProvider;
var
  mProvider: IAtlasTrackerProvider;
begin
  Result := nil;
  for mProvider in Providers do
  begin
    if SameText(mProvider.Name, Trim(AName)) then
    begin
      Exit(mProvider);
    end;
  end;
end;

function TAtlasTrackerAccess.HasToken(const ATarget: TAtlasTrackerTarget): Boolean;
var
  mUser, mToken: string;
begin
  Result := False;
  if (ATarget.CredentialTarget = '') or (FParts.Credentials = nil) then
  begin
    Exit;
  end;
  Result := FParts.Credentials.Read(ATarget.CredentialTarget, mUser, mToken) and (mToken <> '');
  Wipe(mToken);
end;

function TAtlasTrackerAccess.EnterToken(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): Boolean;
var
  mToken: string;
begin
  Result := False;
  // Das Token geht nur über https an den eingetragenen Server; ohne https gar nicht erst speichern.
  if not ATarget.Secure then
  begin
    Notice(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginInsecure));
    Exit;
  end;
  mToken := '';
  if (FParts.Credentials = nil) or not TAtlasCiLoginPrompt.AskToken(
    TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.TrackerLoginTitle, [AProvider.Caption, ATarget.Server]),
    TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginToken), mToken) then
  begin
    Exit;
  end;
  if mToken = '' then
  begin
    Exit(RemoveToken(ATarget));
  end;
  Result := FParts.Credentials.Write(ATarget.CredentialTarget, AProvider.Name, mToken, cComment);
  Wipe(mToken);
  // Anonym: weder Server noch Projekt.
  SavedOrFailed(Result);
end;

function TAtlasTrackerAccess.RemoveToken(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := True;
  if (ATarget.CredentialTarget = '') or (FParts.Credentials = nil) then
  begin
    Exit;
  end;
  Result := FParts.Credentials.Delete(ATarget.CredentialTarget);
  if Result then
  begin
    Notice(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginRemoved));
  end
  else
  begin
    Notice(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginFailed));
  end;
end;

function TAtlasTrackerAccess.Transport(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
var
  mUser, mToken: string;
begin
  Result := nil;
  if (AProvider = nil) or not ATarget.Secure or (FParts.Credentials = nil) or (FParts.Transports = nil) then
  begin
    Exit;
  end;
  // Ohne Token kein Transport (kein Netz). „Authorization: Bearer“ nur über https an die API des Trackers.
  if FParts.Credentials.Read(ATarget.CredentialTarget, mUser, mToken) and (mToken <> '') then
  begin
    Result := FParts.Transports.Bearer(AProvider.ApiServer(ATarget), mToken);
  end;
  Wipe(mToken);
end;

{ TAtlasCiAccess }

constructor TAtlasCiAccess.Create(const AProviders: TAtlasCiProviderFactory; const AParts: TAtlasAccessParts);
begin
  inherited Create;
  FProviders := AProviders;
  FParts := AParts;
end;

procedure TAtlasCiAccess.Notice(const AText: string);
begin
  if Assigned(FParts.Notice) then
  begin
    FParts.Notice(AText);
  end;
end;

function TAtlasCiAccess.Provider(const AName: string): IAtlasCiProvider;
begin
  Result := nil;
  if Assigned(FProviders) then
  begin
    Result := FProviders(AName);
  end;
end;

function TAtlasCiAccess.Transport(const AJob: TAtlasCiJob): IAtlasCiTransport;
var
  mUser, mToken: string;
begin
  Result := nil;
  if FParts.Transports = nil then
  begin
    Exit;
  end;
  mUser := '';
  mToken := '';
  // Ohne Eintrag fragt Atlas ohne Anmeldung (offene Server).
  if FParts.Credentials <> nil then
  begin
    FParts.Credentials.Read(AJob.CredentialTarget, mUser, mToken);
  end;
  Result := FParts.Transports.Basic(AJob.Server, mUser, mToken);
  TAtlasTrackerAccess.Wipe(mToken);
end;

function TAtlasCiAccess.StoredUser(const AJob: TAtlasCiJob): string;
var
  mToken: string;
begin
  // Nur der Benutzer wird vorbelegt; das gespeicherte Token wird nie angezeigt.
  Result := '';
  FParts.Credentials.Read(AJob.CredentialTarget, Result, mToken);
  TAtlasTrackerAccess.Wipe(mToken);
end;

function TAtlasCiAccess.Remove(const AJob: TAtlasCiJob): Boolean;
begin
  Result := FParts.Credentials.Delete(AJob.CredentialTarget);
  if Result then
  begin
    Notice(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginRemoved));
  end
  else
  begin
    Notice(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginFailed));
  end;
end;

function TAtlasCiAccess.EnterCredentials(const AJob: TAtlasCiJob): Boolean;
var
  mUser, mToken: string;
begin
  Result := False;
  mUser := '';
  mToken := '';
  if FParts.Credentials <> nil then
  begin
    mUser := StoredUser(AJob);
  end;
  if (FParts.Credentials = nil) or not TAtlasCiLoginPrompt.Ask(AJob.Server, mUser, mToken) then
  begin
    Exit;
  end;
  if (mUser = '') and (mToken = '') then
  begin
    Exit(Remove(AJob));
  end;
  if (mUser = '') or (mToken = '') then
  begin
    Notice(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginIncomplete));
    Exit;
  end;
  Result := FParts.Credentials.Write(AJob.CredentialTarget, mUser, mToken, '');
  TAtlasTrackerAccess.Wipe(mToken);
  // Anonym: weder Server noch Benutzer.
  if Result then
  begin
    Notice(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginSaved));
  end
  else
  begin
    Notice(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginFailed));
  end;
end;

end.
