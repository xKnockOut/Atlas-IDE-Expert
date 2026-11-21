unit Atlas.Windows.Updates.Adapters.Trust.Tests;

// Tests der Signaturprüfung der Versionsdatei über CNG (#1519): echte
// ECDSA-P-256-Signaturen zweier Testschlüssel, die nur hier stehen, erzeugt
// mit einer unabhängigen Umsetzung (OpenSSL über Python, r und s je 32 Byte)
// über genau die Zeile cManifest.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWindowsUpdateTrustTests = class
  public
    [Test]
    procedure AcceptsFirstKey;
    [Test]
    procedure AcceptsSecondKey;
    [Test]
    procedure RejectsChangedManifest;
    [Test]
    procedure RejectsUnknownKey;
    [Test]
    procedure SkipsBrokenKeys;
    [Test]
    procedure RejectsShortSignature;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract,
  Atlas.Common.Updates.ManifestSignature,
  Atlas.Windows.Updates.Adapters.Trust;

const
  cManifest = '{"version":"2.3.0"}'#10;
  cKeyA = '1152ad843407d6ec4f62bf82e16c830187de3f728328b007fe3394397257c67f' +
    '2009cd051560b3704976bd9bbf1ae5ec5e18496ca68327774a1cef7bba9beffd';
  cSignatureA = '2392f38dc6a886e8a654c346261339f0afef7e908bb557abdbee42567f45cc3f' +
    '029f56f966f354def405248de5491abeabddb6e24dfff3a88b58fe97138d0fa3';
  cKeyB = 'a766693b702cfbae1b6a91e091bfc1eabc1191a4e9304616d0df1b9ab38700b9' +
    '2bb36d4ae4ebb252d0f8c621278774a84459ad3cb07853ae82172399bd766d82';
  cSignatureB = '5f561078918e001313e2814f4b3d41b6972ffd8b299f6345a603dedb45328659' +
    'c5c2912338aa0a19b551d7696402f9d5764d45aec1c50350e1df30535148cf47';

function Genuine(const AManifest, ASignature: string; const AKeys: TArray<string>): Boolean;
var
  mTrust: IUpdateTrust;
  mSignature: TBytes;
begin
  mTrust := TUpdateWindowsTrust.Create;
  Assert.IsTrue(TUpdateManifestSignature.TryHexBytes(ASignature, mSignature));
  Result := mTrust.ManifestIsGenuine(TEncoding.UTF8.GetBytes(AManifest), mSignature, AKeys);
end;

{ TWindowsUpdateTrustTests }

procedure TWindowsUpdateTrustTests.AcceptsFirstKey;
begin
  Assert.IsTrue(Genuine(cManifest, cSignatureA, TArray<string>.Create(cKeyA, cKeyB)));
end;

procedure TWindowsUpdateTrustTests.AcceptsSecondKey;
begin
  Assert.IsTrue(Genuine(cManifest, cSignatureB, TArray<string>.Create(cKeyA, cKeyB)));
end;

procedure TWindowsUpdateTrustTests.RejectsChangedManifest;
begin
  Assert.IsFalse(Genuine('{"version":"2.3.1"}'#10, cSignatureA, TArray<string>.Create(cKeyA, cKeyB)));
  // Auch ein anderes Zeilenende ist eine andere Datei.
  Assert.IsFalse(Genuine('{"version":"2.3.0"}'#13#10, cSignatureA, TArray<string>.Create(cKeyA, cKeyB)));
end;

procedure TWindowsUpdateTrustTests.RejectsUnknownKey;
begin
  Assert.IsFalse(Genuine(cManifest, cSignatureA, TArray<string>.Create(cKeyB)));
end;

procedure TWindowsUpdateTrustTests.SkipsBrokenKeys;
begin
  Assert.IsTrue(Genuine(cManifest, cSignatureA, TArray<string>.Create('', 'zz', Copy(cKeyB, 1, 64), cKeyA)));
  Assert.IsFalse(Genuine(cManifest, cSignatureA, TArray<string>.Create('', '')));
end;

procedure TWindowsUpdateTrustTests.RejectsShortSignature;
begin
  Assert.IsFalse(Genuine(cManifest, Copy(cSignatureA, 1, 126), TArray<string>.Create(cKeyA)));
end;

end.
