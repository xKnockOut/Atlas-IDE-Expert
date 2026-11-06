unit Atlas.Core.Ci.Adapters.Credentials;

// Zugang zum Build-Server (#763) im Anmeldespeicher von Windows
// (Anmeldeinformationsverwaltung, „Windows-Anmeldeinformationen“), nie in
// einer Datei, der Registry oder dem Protokoll. Ein Eintrag je Server:
// Ziel "Atlas:ci:https://ci.firma.de" (TAtlasCiJob.CredentialTarget), Art
// CRED_TYPE_GENERIC, Benutzer als Benutzername, API-Token als Inhalt
// (UTF-16), gespeichert für diesen Benutzer auf diesem Rechner
// (CRED_PERSIST_LOCAL_MACHINE, wandert nicht mit dem Profil).
// Leser im Hintergrund-Thread erlaubt; Schreiben aus dem Befehl
// „Zugang zum Build-Server hinterlegen …“.
// Der Issue-Tracker (#765) legt seinen Zugang ebenso ab: Ziel
// "Atlas:tracker:https://github.com" (TAtlasTrackerTarget.CredentialTarget),
// Benutzer = Name des Trackers, Inhalt = Token, Kommentar „Atlas: Issue-Tracker“.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract;

type
  TAtlasCiCredentials = class
  public const
    /// <summary>Höchstlänge des Tokens (CRED_MAX_CREDENTIAL_BLOB_SIZE = 2560 Byte, UTF-16).</summary>
    MaxTokenLength = 1280;
  public
    /// <summary>Eintrag zu ATarget lesen; False ohne Eintrag.</summary>
    class function Read(const ATarget: string; out AUser, AToken: string): Boolean; static;
    /// <summary>Eintrag anlegen oder ersetzen; False bei Fehler oder zu langem Token.</summary>
    class function Write(const ATarget, AUser, AToken: string): Boolean; overload; static;
    /// <summary>Wie Write, mit eigenem Kommentar für die Anmeldeinformationsverwaltung (#765).</summary>
    class function Write(const ATarget, AUser, AToken, AComment: string): Boolean; overload; static;
    /// <summary>Eintrag entfernen; True auch, wenn es keinen gab.</summary>
    class function Delete(const ATarget: string): Boolean; static;
    class function Exists(const ATarget: string): Boolean; static;
  end;

  /// <summary>IAtlasCiCredentialStore über den Anmeldespeicher von Windows (#1455); erzeugt nur die Komposition
  /// des Moduls Tracker.</summary>
  TAtlasCiCredentialStore = class(TInterfacedObject, IAtlasCiCredentialStore)
  public const
    cDefaultComment = 'Atlas: Build-Server';
  public
    function Read(const ATarget: string; out AUser, AToken: string): Boolean;
    /// <summary>AComment '' = cDefaultComment.</summary>
    function Write(const ATarget, AUser, AToken, AComment: string): Boolean;
    function Delete(const ATarget: string): Boolean;
  end;

implementation

uses
  Winapi.Windows;

const
  // Fehlt in Delphis Winapi.Windows.
  ERROR_NOT_FOUND = 1168;
  CRED_TYPE_GENERIC = 1;
  CRED_PERSIST_LOCAL_MACHINE = 2;

type
  // CREDENTIALW aus wincred.h (Ausrichtung wie in C).
  TCredential = record
    Flags: DWORD;
    CredType: DWORD;
    TargetName: PWideChar;
    Comment: PWideChar;
    LastWritten: TFileTime;
    CredentialBlobSize: DWORD;
    CredentialBlob: PByte;
    Persist: DWORD;
    AttributeCount: DWORD;
    Attributes: Pointer;
    TargetAlias: PWideChar;
    UserName: PWideChar;
  end;
  PCredential = ^TCredential;

function CredReadW(TargetName: PWideChar; CredType, Flags: DWORD; out Credential: PCredential): BOOL; stdcall;
  external advapi32 name 'CredReadW';
function CredWriteW(const Credential: TCredential; Flags: DWORD): BOOL; stdcall;
  external advapi32 name 'CredWriteW';
function CredDeleteW(TargetName: PWideChar; CredType, Flags: DWORD): BOOL; stdcall;
  external advapi32 name 'CredDeleteW';
procedure CredFree(Buffer: Pointer); stdcall;
  external advapi32 name 'CredFree';

{ TAtlasCiCredentials }

class function TAtlasCiCredentials.Read(const ATarget: string; out AUser, AToken: string): Boolean;
var
  Credential: PCredential;
begin
  AUser := '';
  AToken := '';
  Result := False;
  if ATarget = '' then
  begin
    Exit;
  end;
  Credential := nil;
  if not CredReadW(PWideChar(ATarget), CRED_TYPE_GENERIC, 0, Credential) then
  begin
    Exit;
  end;
  try
    if Credential.UserName <> nil then
    begin
      AUser := Credential.UserName;
    end;
    if (Credential.CredentialBlob <> nil) and (Credential.CredentialBlobSize >= SizeOf(WideChar)) then
    begin
      SetString(AToken, PWideChar(Credential.CredentialBlob), Integer(Credential.CredentialBlobSize) div
        SizeOf(WideChar));
    end;
    Result := (AUser <> '') and (AToken <> '');
  finally
    CredFree(Credential);
  end;
end;

class function TAtlasCiCredentials.Write(const ATarget, AUser, AToken: string): Boolean;
begin
  Result := TAtlasCiCredentials.Write(ATarget, AUser, AToken, 'Atlas: Build-Server');
end;

class function TAtlasCiCredentials.Write(const ATarget, AUser, AToken, AComment: string): Boolean;
var
  Credential: TCredential;
  Blob: string;
begin
  Result := False;
  if (ATarget = '') or (AUser = '') or (AToken = '') or (Length(AToken) > MaxTokenLength) then
  begin
    Exit;
  end;
  Blob := AToken;
  UniqueString(Blob);
  try
    Credential := Default(TCredential);
    Credential.CredType := CRED_TYPE_GENERIC;
    Credential.TargetName := PWideChar(ATarget);
    Credential.Comment := PWideChar(AComment);
    Credential.CredentialBlobSize := Length(Blob) * SizeOf(WideChar);
    Credential.CredentialBlob := PByte(PWideChar(Blob));
    Credential.Persist := CRED_PERSIST_LOCAL_MACHINE;
    Credential.UserName := PWideChar(AUser);
    Result := CredWriteW(Credential, 0);
  finally
    // Die Kopie des Tokens nicht im Speicher liegen lassen.
    FillChar(PWideChar(Blob)^, Length(Blob) * SizeOf(WideChar), 0);
  end;
end;

class function TAtlasCiCredentials.Delete(const ATarget: string): Boolean;
begin
  if ATarget = '' then
  begin
    Exit(False);
  end;
  Result := CredDeleteW(PWideChar(ATarget), CRED_TYPE_GENERIC, 0) or (GetLastError = ERROR_NOT_FOUND);
end;

class function TAtlasCiCredentials.Exists(const ATarget: string): Boolean;
var
  User, Token: string;
begin
  Result := Read(ATarget, User, Token);
end;

{ TAtlasCiCredentialStore }

function TAtlasCiCredentialStore.Read(const ATarget: string; out AUser, AToken: string): Boolean;
begin
  Result := TAtlasCiCredentials.Read(ATarget, AUser, AToken);
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
  Result := TAtlasCiCredentials.Write(ATarget, AUser, AToken, mComment);
end;

function TAtlasCiCredentialStore.Delete(const ATarget: string): Boolean;
begin
  Result := TAtlasCiCredentials.Delete(ATarget);
end;

end.
