unit Atlas.Windows.Updates.Adapters.Trust;

// Platform-Feature "Updates" (#1519), Adapter: Prüfsummen und Signaturen.
// - SHA-256 über System.Hash.
// - Authenticode über WinVerifyTrust (WINTRUST_ACTION_GENERIC_VERIFY_V2,
//   Widerruf über die ganze Kette, ohne Oberfläche). Herausgeber ist das
//   Zertifikat des ersten Unterzeichners: Anzeigename (nur zur Anzeige) und
//   Fingerabdruck = SHA-256 der Bits seines öffentlichen Schlüssels. Der
//   Schlüssel statt des ganzen Zertifikats, damit ein erneuertes Zertifikat
//   mit demselben Schlüssel derselbe Herausgeber bleibt. Die Typen von
//   wintrust.dll und crypt32.dll stehen hier selbst, weil Delphi sie nicht in
//   allen Versionen gleich deklariert; gelesen werden nur die ersten Felder
//   (CERT_INFO bis zum öffentlichen Schlüssel).

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsTrust = class(TInterfacedObject, IUpdateTrust)
  public
    function Sha256(const AFileName: string): string;
    function Signature(const AFileName: string): TUpdateSignature;
  end;

implementation

uses
  Winapi.Windows,
  System.Hash;

type
  TWinTrustFileInfo = record
    cbStruct: DWORD;
    pcwszFilePath: PWideChar;
    hFile: THandle;
    pgKnownSubject: PGUID;
  end;

  TWinTrustData = record
    cbStruct: DWORD;
    pPolicyCallbackData: Pointer;
    pSIPClientData: Pointer;
    dwUIChoice: DWORD;
    fdwRevocationChecks: DWORD;
    dwUnionChoice: DWORD;
    pFile: Pointer;
    dwStateAction: DWORD;
    hWVTStateData: THandle;
    pwszURLReference: PWideChar;
    dwProvFlags: DWORD;
    dwUIContext: DWORD;
    pSignatureSettings: Pointer;
  end;

  TCryptBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;

  TCryptAlgorithmIdentifier = record
    pszObjId: PAnsiChar;
    Parameters: TCryptBlob;
  end;

  TCryptBitBlob = record
    cbData: DWORD;
    pbData: PByte;
    cUnusedBits: DWORD;
  end;

  TCertPublicKeyInfo = record
    Algorithm: TCryptAlgorithmIdentifier;
    PublicKey: TCryptBitBlob;
  end;

  TCertInfo = record
    dwVersion: DWORD;
    SerialNumber: TCryptBlob;
    SignatureAlgorithm: TCryptAlgorithmIdentifier;
    Issuer: TCryptBlob;
    NotBefore: TFileTime;
    NotAfter: TFileTime;
    Subject: TCryptBlob;
    SubjectPublicKeyInfo: TCertPublicKeyInfo;
  end;
  PCertInfo = ^TCertInfo;

  TCertContext = record
    dwCertEncodingType: DWORD;
    pbCertEncoded: PByte;
    cbCertEncoded: DWORD;
    pCertInfo: PCertInfo;
  end;
  PCertContext = ^TCertContext;

  TCryptProviderCert = record
    cbStruct: DWORD;
    pCert: PCertContext;
  end;
  PCryptProviderCert = ^TCryptProviderCert;

  TCryptProviderSigner = record
    cbStruct: DWORD;
    sftVerifyAsOf: TFileTime;
    csCertChain: DWORD;
    pasCertChain: PCryptProviderCert;
  end;
  PCryptProviderSigner = ^TCryptProviderSigner;

const
  cGenericVerifyV2: TGUID = '{00AAC56B-CD44-11D0-8CC2-00C04FC295EE}';
  cUiNone = 2;
  cRevokeWholeChain = 1;
  cChoiceFile = 1;
  cStateVerify = 1;
  cStateClose = 2;
  cSimpleDisplayName = 4;

function WinVerifyTrust(AWindow: HWND; AAction: PGUID; AData: Pointer): Longint; stdcall;
  external 'wintrust.dll' name 'WinVerifyTrust';
function WTHelperProvDataFromStateData(AStateData: THandle): Pointer; stdcall;
  external 'wintrust.dll' name 'WTHelperProvDataFromStateData';
function WTHelperGetProvSignerFromChain(AProvData: Pointer; ASigner: DWORD; ACounterSigner: BOOL;
  ACounterIndex: DWORD): PCryptProviderSigner; stdcall; external 'wintrust.dll' name 'WTHelperGetProvSignerFromChain';
function CertGetNameStringW(ACertContext: Pointer; AType, AFlags: DWORD; ATypePara: Pointer; AName: PWideChar;
  ACount: DWORD): DWORD; stdcall; external 'crypt32.dll' name 'CertGetNameStringW';

/// <summary>Zertifikat des ersten Unterzeichners; nil ohne.</summary>
function SignerCertificate(AStateData: THandle): PCertContext;
var
  mSigner: PCryptProviderSigner;
begin
  Result := nil;
  mSigner := WTHelperGetProvSignerFromChain(WTHelperProvDataFromStateData(AStateData), 0, False, 0);
  if (mSigner <> nil) and (mSigner.csCertChain > 0) and (mSigner.pasCertChain <> nil) then
  begin
    Result := mSigner.pasCertChain.pCert;
  end;
end;

function SubjectOf(ACertificate: PCertContext): string;
var
  mBuffer: array[0..511] of WideChar;
begin
  Result := '';
  if CertGetNameStringW(ACertificate, cSimpleDisplayName, 0, nil, @mBuffer[0], Length(mBuffer)) > 1 then
  begin
    Result := mBuffer;
  end;
end;

/// <summary>SHA-256 des öffentlichen Schlüssels als 64 kleine Hexziffern; '' ohne Schlüssel.</summary>
function ThumbprintOf(ACertificate: PCertContext): string;
var
  mKey: TCryptBitBlob;
  mHash: THashSHA2;
begin
  Result := '';
  if ACertificate.pCertInfo = nil then
  begin
    Exit;
  end;
  mKey := ACertificate.pCertInfo.SubjectPublicKeyInfo.PublicKey;
  if (mKey.cbData = 0) or (mKey.pbData = nil) then
  begin
    Exit;
  end;
  mHash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  mHash.Update(mKey.pbData^, mKey.cbData);
  Result := LowerCase(mHash.HashAsString);
end;

{ TUpdateWindowsTrust }

function TUpdateWindowsTrust.Sha256(const AFileName: string): string;
begin
  Result := LowerCase(THashSHA2.GetHashStringFromFile(AFileName, THashSHA2.TSHA2Version.SHA256));
end;

function TUpdateWindowsTrust.Signature(const AFileName: string): TUpdateSignature;
var
  mFile: TWinTrustFileInfo;
  mData: TWinTrustData;
  mAction: TGUID;
  mCertificate: PCertContext;
begin
  Result := Default(TUpdateSignature);
  mFile := Default(TWinTrustFileInfo);
  mFile.cbStruct := SizeOf(mFile);
  mFile.pcwszFilePath := PWideChar(AFileName);
  mData := Default(TWinTrustData);
  mData.cbStruct := SizeOf(mData);
  mData.dwUIChoice := cUiNone;
  mData.fdwRevocationChecks := cRevokeWholeChain;
  mData.dwUnionChoice := cChoiceFile;
  mData.pFile := @mFile;
  mData.dwStateAction := cStateVerify;
  mAction := cGenericVerifyV2;
  Result.Valid := WinVerifyTrust(INVALID_HANDLE_VALUE, @mAction, @mData) = 0;
  try
    mCertificate := nil;
    if Result.Valid then
    begin
      mCertificate := SignerCertificate(mData.hWVTStateData);
    end;
    // Ohne lesbares Zertifikat bleiben Name und Fingerabdruck leer; die Vorbereitung wertet das als unsigniert.
    if mCertificate <> nil then
    begin
      Result.Subject := SubjectOf(mCertificate);
      Result.Thumbprint := ThumbprintOf(mCertificate);
    end;
  finally
    mData.dwStateAction := cStateClose;
    WinVerifyTrust(INVALID_HANDLE_VALUE, @mAction, @mData);
  end;
end;

end.
