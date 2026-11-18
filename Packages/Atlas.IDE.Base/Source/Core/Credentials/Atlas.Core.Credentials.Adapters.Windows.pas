unit Atlas.Core.Credentials.Adapters.Windows;

// Anmeldespeicher von Windows (Anmeldeinformationsverwaltung, „Windows-
// Anmeldeinformationen“) für Atlas.Core.Credentials.Contract: ein Eintrag je
// Ziel ("Atlas:ci:https://ci.firma.de", "Atlas:tracker:https://github.com",
// "Atlas:ai:anthropic"), Art CRED_TYPE_GENERIC, Benutzer als Benutzername,
// Geheimnis als Inhalt (UTF-16), gespeichert für diesen Benutzer auf diesem
// Rechner (CRED_PERSIST_LOCAL_MACHINE, wandert nicht mit dem Profil). Die
// Kopie des Geheimnisses wird nach dem Schreiben überschrieben.
// Lesen im Hintergrund-Thread erlaubt. Die Module Tracker und KI-Assistenten
// erzeugen die Umsetzung in ihrer Komposition.

interface

uses
  Atlas.Core.Credentials.Contract;

type
  TAtlasWindowsCredentials = class(TInterfacedObject, IAtlasCredentialStore)
  public const
    /// <summary>Höchstlänge des Geheimnisses (CRED_MAX_CREDENTIAL_BLOB_SIZE = 2560 Byte, UTF-16).</summary>
    cMaxSecretLength = 1280;
  public
    function Read(const ATarget: string; out AUser, ASecret: string): Boolean;
    function Write(const ATarget, AUser, ASecret, AComment: string): Boolean;
    function Delete(const ATarget: string): Boolean;
  end;

implementation

uses
  Winapi.Windows;

const
  // Fehlt in Delphis Winapi.Windows.
  cERROR_NOT_FOUND = 1168;
  cCRED_TYPE_GENERIC = 1;
  cCRED_PERSIST_LOCAL_MACHINE = 2;

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

function CredReadW(ATargetName: PWideChar; ACredType, AFlags: DWORD; out ACredential: PCredential): BOOL; stdcall;
  external advapi32 name 'CredReadW';
function CredWriteW(const ACredential: TCredential; AFlags: DWORD): BOOL; stdcall;
  external advapi32 name 'CredWriteW';
function CredDeleteW(ATargetName: PWideChar; ACredType, AFlags: DWORD): BOOL; stdcall;
  external advapi32 name 'CredDeleteW';
procedure CredFree(ABuffer: Pointer); stdcall;
  external advapi32 name 'CredFree';

{ TAtlasWindowsCredentials }

function TAtlasWindowsCredentials.Read(const ATarget: string; out AUser, ASecret: string): Boolean;
var
  mCredential: PCredential;
begin
  AUser := '';
  ASecret := '';
  Result := False;
  if ATarget = '' then
  begin
    Exit;
  end;
  mCredential := nil;
  if not CredReadW(PWideChar(ATarget), cCRED_TYPE_GENERIC, 0, mCredential) then
  begin
    Exit;
  end;
  try
    if mCredential.UserName <> nil then
    begin
      AUser := mCredential.UserName;
    end;
    if (mCredential.CredentialBlob <> nil) and (mCredential.CredentialBlobSize >= SizeOf(WideChar)) then
    begin
      SetString(ASecret, PWideChar(mCredential.CredentialBlob), Integer(mCredential.CredentialBlobSize) div
        SizeOf(WideChar));
    end;
    Result := (AUser <> '') and (ASecret <> '');
  finally
    CredFree(mCredential);
  end;
end;

function TAtlasWindowsCredentials.Write(const ATarget, AUser, ASecret, AComment: string): Boolean;
var
  mCredential: TCredential;
  mBlob: string;
begin
  Result := False;
  if (ATarget = '') or (AUser = '') or (ASecret = '') or (Length(ASecret) > cMaxSecretLength) then
  begin
    Exit;
  end;
  mBlob := ASecret;
  UniqueString(mBlob);
  try
    mCredential := Default(TCredential);
    mCredential.CredType := cCRED_TYPE_GENERIC;
    mCredential.TargetName := PWideChar(ATarget);
    mCredential.Comment := PWideChar(AComment);
    mCredential.CredentialBlobSize := Length(mBlob) * SizeOf(WideChar);
    mCredential.CredentialBlob := PByte(PWideChar(mBlob));
    mCredential.Persist := cCRED_PERSIST_LOCAL_MACHINE;
    mCredential.UserName := PWideChar(AUser);
    Result := CredWriteW(mCredential, 0);
  finally
    // Die Kopie des Geheimnisses nicht im Speicher liegen lassen.
    FillChar(PWideChar(mBlob)^, Length(mBlob) * SizeOf(WideChar), 0);
  end;
end;

function TAtlasWindowsCredentials.Delete(const ATarget: string): Boolean;
begin
  if ATarget = '' then
  begin
    Exit(False);
  end;
  Result := CredDeleteW(PWideChar(ATarget), cCRED_TYPE_GENERIC, 0) or (GetLastError = cERROR_NOT_FOUND);
end;

end.
