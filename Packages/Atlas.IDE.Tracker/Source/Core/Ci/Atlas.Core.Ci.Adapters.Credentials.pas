unit Atlas.Core.Ci.Adapters.Credentials;

// Zugang zum Build-Server (#763) im Anmeldespeicher von Windows (den die
// Komposition aus Base übergibt, IAtlasCredentialStore), nie in einer Datei, der
// Registry oder dem Protokoll. Ein Eintrag je Server: Ziel
// "Atlas:ci:https://ci.firma.de" (TAtlasCiJob.CredentialTarget), Benutzer als
// Benutzername, API-Token als Inhalt.
// Leser im Hintergrund-Thread erlaubt; Schreiben aus dem Befehl
// „Zugang zum Build-Server hinterlegen …“.
// Der Issue-Tracker (#765) legt seinen Zugang ebenso ab: Ziel
// "Atlas:tracker:https://github.com" (TAtlasTrackerTarget.CredentialTarget),
// Benutzer = Name des Trackers, Inhalt = Token, Kommentar „Atlas: Issue-Tracker“.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Credentials.Contract;

type
  /// <summary>IAtlasCiCredentialStore über einen Anmeldespeicher (#1455); erzeugt nur die Komposition des Moduls
  /// Tracker mit dem von Windows.</summary>
  TAtlasCiCredentialStore = class(TInterfacedObject, IAtlasCiCredentialStore)
  public const
    cDefaultComment = 'Atlas: Build-Server';
  private
    FStore: IAtlasCredentialStore;
  public
    constructor Create(const AStore: IAtlasCredentialStore);
    function Read(const ATarget: string; out AUser, AToken: string): Boolean;
    /// <summary>AComment '' = cDefaultComment.</summary>
    function Write(const ATarget, AUser, AToken, AComment: string): Boolean;
    function Delete(const ATarget: string): Boolean;
  end;

implementation

{ TAtlasCiCredentialStore }

constructor TAtlasCiCredentialStore.Create(const AStore: IAtlasCredentialStore);
begin
  inherited Create;
  FStore := AStore;
end;

function TAtlasCiCredentialStore.Read(const ATarget: string; out AUser, AToken: string): Boolean;
begin
  Result := FStore.Read(ATarget, AUser, AToken);
end;

function TAtlasCiCredentialStore.Write(const ATarget, AUser, AToken, AComment: string): Boolean;
var
  mComment: string;
begin
  mComment := AComment;
  if mComment = '' then
  begin
    mComment := cDefaultComment;
  end;
  Result := FStore.Write(ATarget, AUser, AToken, mComment);
end;

function TAtlasCiCredentialStore.Delete(const ATarget: string): Boolean;
begin
  Result := FStore.Delete(ATarget);
end;

end.
