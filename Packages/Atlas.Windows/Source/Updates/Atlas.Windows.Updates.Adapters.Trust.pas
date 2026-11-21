unit Atlas.Windows.Updates.Adapters.Trust;

// Platform-Feature "Updates" (#1519), Adapter: Prüfsummen und Signaturen.
// - SHA-256 über System.Hash.
// - Authenticode über WinVerifyTrust (WINTRUST_ACTION_GENERIC_VERIFY_V2,
//   Widerruf über die ganze Kette, ohne Oberfläche); der Herausgeber ist der
//   Anzeigename des Zertifikats des ersten Unterzeichners. Die Typen von
//   wintrust.dll und crypt32.dll stehen hier selbst, weil Delphi sie nicht in
//   allen Versionen gleich deklariert; gelesen werden nur die ersten Felder.
// - Signatur der Versionsdatei über CNG (bcrypt.dll): ECDSA P-256,
//   BCryptVerifySignature mit dem SHA-256 der Bytes; der öffentliche Schlüssel
//   kommt als BCRYPT_ECCPUBLIC_BLOB (Kennung, Länge, X, Y) hinein, die
//   Signatur als r und s (IEEE P1363, wie .NET ECDsa.SignData sie liefert).

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsTrust = class(TInterfacedObject, IUpdateTrust)
  public
    function Sha256(const AFileName: string): string;
    function Signature(const AFileName: string): TUpdateSignature;
    function ManifestIsGenuine(const AManifest, ASignature: TBytes; const APublicKeys: TArray<string>): Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.Hash,
  Atlas.Common.Updates.ManifestSignature;

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

  TCryptProviderCert = record
    cbStruct: DWORD;
    pCert: Pointer;
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
  cEcdsaP256 = 'ECDSA_P256';
  cEccPublicBlob = 'ECCPUBLICBLOB';
  /// <summary>BCRYPT_ECDSA_PUBLIC_P256_MAGIC („ECS1“).</summary>
  cEcdsaPublicP256Magic = $31534345;
  cCoordinateBytes = 32;

function WinVerifyTrust(AWindow: HWND; AAction: PGUID; AData: Pointer): Longint; stdcall;
  external 'wintrust.dll' name 'WinVerifyTrust';
function WTHelperProvDataFromStateData(AStateData: THandle): Pointer; stdcall;
  external 'wintrust.dll' name 'WTHelperProvDataFromStateData';
function WTHelperGetProvSignerFromChain(AProvData: Pointer; ASigner: DWORD; ACounterSigner: BOOL;
  ACounterIndex: DWORD): PCryptProviderSigner; stdcall; external 'wintrust.dll' name 'WTHelperGetProvSignerFromChain';
function BCryptOpenAlgorithmProvider(out AAlgorithm: THandle; AAlgId, AImplementation: PWideChar;
  AFlags: ULONG): Longint; stdcall; external 'bcrypt.dll' name 'BCryptOpenAlgorithmProvider';
function BCryptCloseAlgorithmProvider(AAlgorithm: THandle; AFlags: ULONG): Longint; stdcall;
  external 'bcrypt.dll' name 'BCryptCloseAlgorithmProvider';
function BCryptImportKeyPair(AAlgorithm, AImportKey: THandle; ABlobType: PWideChar; out AKey: THandle;
  AInput: PByte; AInputBytes, AFlags: ULONG): Longint; stdcall; external 'bcrypt.dll' name 'BCryptImportKeyPair';
function BCryptDestroyKey(AKey: THandle): Longint; stdcall; external 'bcrypt.dll' name 'BCryptDestroyKey';
function BCryptVerifySignature(AKey: THandle; APaddingInfo: Pointer; AHash: PByte; AHashBytes: ULONG;
  ASignature: PByte; ASignatureBytes, AFlags: ULONG): Longint; stdcall;
  external 'bcrypt.dll' name 'BCryptVerifySignature';
function CertGetNameStringW(ACertContext: Pointer; AType, AFlags: DWORD; ATypePara: Pointer; AName: PWideChar;
  ACount: DWORD): DWORD; stdcall; external 'crypt32.dll' name 'CertGetNameStringW';

function SubjectOf(AStateData: THandle): string;
var
  mSigner: PCryptProviderSigner;
  mBuffer: array[0..511] of WideChar;
begin
  Result := '';
  mSigner := WTHelperGetProvSignerFromChain(WTHelperProvDataFromStateData(AStateData), 0, False, 0);
  if (mSigner = nil) or (mSigner.csCertChain = 0) or (mSigner.pasCertChain = nil) then
  begin
    Exit;
  end;
  if CertGetNameStringW(mSigner.pasCertChain.pCert, cSimpleDisplayName, 0, nil, @mBuffer[0], Length(mBuffer)) > 1 then
  begin
    Result := mBuffer;
  end;
end;

/// <summary>BCRYPT_ECCPUBLIC_BLOB aus 128 Hexziffern (X und Y); leer, wenn der Text kein Schlüssel ist.</summary>
function PublicKeyBlob(const AKey: string): TBytes;
var
  mPoint: TBytes;
  mMagic, mLength: ULONG;
begin
  Result := nil;
  if not TUpdateManifestSignature.TryHexBytes(AKey, mPoint) or
    (Length(mPoint) <> TUpdateManifestSignature.cKeyBytes) then
  begin
    Exit;
  end;
  mMagic := cEcdsaPublicP256Magic;
  mLength := cCoordinateBytes;
  SetLength(Result, 2 * SizeOf(ULONG) + Length(mPoint));
  Move(mMagic, Result[0], SizeOf(ULONG));
  Move(mLength, Result[SizeOf(ULONG)], SizeOf(ULONG));
  Move(mPoint[0], Result[2 * SizeOf(ULONG)], Length(mPoint));
end;

function VerifiesWith(AAlgorithm: THandle; const ABlob, AHash, ASignature: TBytes): Boolean;
var
  mKey: THandle;
begin
  Result := False;
  if BCryptImportKeyPair(AAlgorithm, 0, cEccPublicBlob, mKey, @ABlob[0], Length(ABlob), 0) <> 0 then
  begin
    Exit;
  end;
  try
    Result := BCryptVerifySignature(mKey, nil, @AHash[0], Length(AHash), @ASignature[0], Length(ASignature),
      0) = 0;
  finally
    BCryptDestroyKey(mKey);
  end;
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
    if Result.Valid then
    begin
      Result.Subject := SubjectOf(mData.hWVTStateData);
    end;
  finally
    mData.dwStateAction := cStateClose;
    WinVerifyTrust(INVALID_HANDLE_VALUE, @mAction, @mData);
  end;
end;

function TUpdateWindowsTrust.ManifestIsGenuine(const AManifest, ASignature: TBytes;
  const APublicKeys: TArray<string>): Boolean;
var
  mAlgorithm: THandle;
  mHash: THashSHA2;
  mDigest, mBlob: TBytes;
  mKey: string;
begin
  Result := False;
  if Length(ASignature) <> TUpdateManifestSignature.cSignatureBytes then
  begin
    Exit;
  end;
  mHash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  mHash.Update(AManifest);
  mDigest := mHash.HashAsBytes;
  if BCryptOpenAlgorithmProvider(mAlgorithm, cEcdsaP256, nil, 0) <> 0 then
  begin
    Exit;
  end;
  try
    for mKey in APublicKeys do
    begin
      mBlob := PublicKeyBlob(mKey);
      if (mBlob <> nil) and VerifiesWith(mAlgorithm, mBlob, mDigest, ASignature) then
      begin
        Exit(True);
      end;
    end;
  finally
    BCryptCloseAlgorithmProvider(mAlgorithm, 0);
  end;
end;

end.
