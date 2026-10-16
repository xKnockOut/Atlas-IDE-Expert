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

interface

uses
  System.SysUtils;

type
  TAtlasCiCredentials = class
  public const
    /// <summary>Höchstlänge des Tokens (CRED_MAX_CREDENTIAL_BLOB_SIZE = 2560 Byte, UTF-16).</summary>
    MaxTokenLength = 1280;
  public
    /// <summary>Eintrag zu ATarget lesen; False ohne Eintrag.</summary>
    class function Read(const ATarget: string; out AUser, AToken: string): Boolean; static;
    /// <summary>Eintrag anlegen oder ersetzen; False bei Fehler oder zu langem Token.</summary>
    class function Write(const ATarget, AUser, AToken: string): Boolean; static;
    /// <summary>Eintrag entfernen; True auch, wenn es keinen gab.</summary>
    class function Delete(const ATarget: string): Boolean; static;
    class function Exists(const ATarget: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows;

const
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
    Exit;
  Credential := nil;
  if not CredReadW(PWideChar(ATarget), CRED_TYPE_GENERIC, 0, Credential) then
    Exit;
  try
    if Credential.UserName <> nil then
      AUser := Credential.UserName;
    if (Credential.CredentialBlob <> nil) and (Credential.CredentialBlobSize >= SizeOf(WideChar)) then
      SetString(AToken, PWideChar(Credential.CredentialBlob), Integer(Credential.CredentialBlobSize) div
        SizeOf(WideChar));
    Result := (AUser <> '') and (AToken <> '');
  finally
    CredFree(Credential);
  end;
end;

class function TAtlasCiCredentials.Write(const ATarget, AUser, AToken: string): Boolean;
var
  Credential: TCredential;
  Blob: string;
begin
  Result := False;
  if (ATarget = '') or (AUser = '') or (AToken = '') or (Length(AToken) > MaxTokenLength) then
    Exit;
  Blob := AToken;
  UniqueString(Blob);
  try
    Credential := Default(TCredential);
    Credential.CredType := CRED_TYPE_GENERIC;
    Credential.TargetName := PWideChar(ATarget);
    Credential.Comment := PWideChar('Atlas: Build-Server');
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
    Exit(False);
  Result := CredDeleteW(PWideChar(ATarget), CRED_TYPE_GENERIC, 0) or (GetLastError = ERROR_NOT_FOUND);
end;

class function TAtlasCiCredentials.Exists(const ATarget: string): Boolean;
var
  User, Token: string;
begin
  Result := Read(ATarget, User, Token);
end;

end.
