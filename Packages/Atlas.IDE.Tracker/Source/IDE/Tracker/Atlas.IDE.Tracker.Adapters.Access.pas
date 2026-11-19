unit Atlas.IDE.Tracker.Adapters.Access;

// Zugang des Moduls Tracker zum Issue-Tracker (#765, #1260), Rolle Adapters:
// TAtlasTrackerAccess erfüllt IAtlasTrackerAccess aus
// Atlas.Core.Tracker.Contract mit Anbietern, Token und Transport für „Meine
// Issues“ und den Abschnitt Issue-Tracker. Token im Anmeldespeicher (Ziel
// "Atlas:tracker:<Server>", Benutzer = Anbieter), verdeckter Dialog,
// „Authorization: Bearer“ nur über https an die API des Trackers. Meldungen
// anonym, ohne Server und Token. Anlegen nur in Atlas.IDE.Tracker.Composition.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Tracker.Access;

type
  TAtlasTrackerAccess = class(TInterfacedObject, IAtlasTrackerAccess)
  public const
    cComment = 'Atlas: Issue-Tracker';
  private
    FProviders: TAtlasTrackerProvidersFactory;
    FParts: TAtlasAccessParts;
    procedure SavedOrFailed(AOk: Boolean);
  public
    constructor Create(const AProviders: TAtlasTrackerProvidersFactory; const AParts: TAtlasAccessParts);
    function Providers: TArray<IAtlasTrackerProvider>;
    function Provider(const AName: string): IAtlasTrackerProvider;
    function HasToken(const ATarget: TAtlasTrackerTarget): Boolean;
    function EnterToken(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    function RemoveToken(const ATarget: TAtlasTrackerTarget): Boolean;
    function Transport(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Tracker.MyIssues.Strings,
  Atlas.UI.Tracker.CiLogin;

{ TAtlasTrackerAccess }

constructor TAtlasTrackerAccess.Create(const AProviders: TAtlasTrackerProvidersFactory;
  const AParts: TAtlasAccessParts);
begin
  inherited Create;
  FProviders := AProviders;
  FParts := AParts;
end;

procedure TAtlasTrackerAccess.SavedOrFailed(AOk: Boolean);
begin
  if AOk then
  begin
    FParts.Say(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginSaved));
  end
  else
  begin
    FParts.Say(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginFailed));
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
  WipeToken(mToken);
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
    FParts.Say(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginInsecure));
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
  WipeToken(mToken);
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
    FParts.Say(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginRemoved));
  end
  else
  begin
    FParts.Say(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.TrackerLoginFailed));
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
  WipeToken(mToken);
end;

end.
