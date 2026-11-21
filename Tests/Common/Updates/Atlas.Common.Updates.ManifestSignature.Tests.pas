unit Atlas.Common.Updates.ManifestSignature.Tests;

// Tests der Echtheitsprüfung der Versionsdatei (#1519): Hexziffern lesen,
// Adresse der Signaturdatei, Urteil über fehlende, unlesbare, falsche und
// echte Signaturen und die eingebetteten öffentlichen Schlüssel.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Updates.Contract,
  Atlas.Tests.UpdateFakes;

type
  [TestFixture]
  TCommonUpdatesManifestSignatureTests = class
  private
    FFake: TFakeUpdateSystem;
    function Trust: IUpdateTrust;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsHexDigits;
    [Test]
    procedure RejectsBrokenHex;
    [Test]
    procedure SignatureLiesNextToManifest;
    [Test]
    procedure MissingWithoutSignatureFile;
    [Test]
    procedure GenuineWithAnyKey;
    [Test]
    procedure ForgedOnOtherContent;
    [Test]
    procedure ForgedOnWrongLength;
    [Test]
    procedure EmbedsTwoDistinctKeys;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Updates.ManifestSignature;

const
  cManifest = '{"version": "2.3.0"}';

function Keys: TArray<string>;
begin
  Result := TArray<string>.Create('a', 'b');
end;

{ TCommonUpdatesManifestSignatureTests }

function TCommonUpdatesManifestSignatureTests.Trust: IUpdateTrust;
begin
  Result := FFake.System.Trust;
end;

procedure TCommonUpdatesManifestSignatureTests.Setup;
begin
  FFake := TFakeUpdateSystem.Create;
end;

procedure TCommonUpdatesManifestSignatureTests.TearDown;
begin
  FreeAndNil(FFake);
end;

procedure TCommonUpdatesManifestSignatureTests.ReadsHexDigits;
var
  mBytes: TBytes;
begin
  Assert.IsTrue(TUpdateManifestSignature.TryHexBytes(' 00fF7a'#13#10, mBytes));
  Assert.AreEqual(3, Integer(Length(mBytes)));
  Assert.AreEqual(0, Integer(mBytes[0]));
  Assert.AreEqual(255, Integer(mBytes[1]));
  Assert.AreEqual(122, Integer(mBytes[2]));
  Assert.IsTrue(TUpdateManifestSignature.TryHexBytes('', mBytes));
  Assert.AreEqual(0, Integer(Length(mBytes)));
end;

procedure TCommonUpdatesManifestSignatureTests.RejectsBrokenHex;
var
  mBytes: TBytes;
begin
  Assert.IsFalse(TUpdateManifestSignature.TryHexBytes('abc', mBytes));
  Assert.IsFalse(TUpdateManifestSignature.TryHexBytes('0g', mBytes));
  Assert.IsFalse(TUpdateManifestSignature.TryHexBytes('00 11', mBytes));
  Assert.AreEqual(0, Integer(Length(mBytes)));
end;

procedure TCommonUpdatesManifestSignatureTests.SignatureLiesNextToManifest;
begin
  Assert.AreEqual('https://github.com/o/r/releases/latest/download/atlas-version.json.sig',
    TUpdateManifestSignature.SignatureUrl('https://github.com/o/r/releases/latest/download/atlas-version.json'));
end;

procedure TCommonUpdatesManifestSignatureTests.MissingWithoutSignatureFile;
begin
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Missing,
    TUpdateManifestSignature.Verdict(Trust, cManifest, False, TFakeTrust.SignManifest(cManifest, 'a'), Keys));
end;

procedure TCommonUpdatesManifestSignatureTests.GenuineWithAnyKey;
begin
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Genuine,
    TUpdateManifestSignature.Verdict(Trust, cManifest, True, TFakeTrust.SignManifest(cManifest, 'a'), Keys));
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Genuine,
    TUpdateManifestSignature.Verdict(Trust, cManifest, True, TFakeTrust.SignManifest(cManifest, 'b') + #10,
    Keys));
end;

procedure TCommonUpdatesManifestSignatureTests.ForgedOnOtherContent;
begin
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Forged,
    TUpdateManifestSignature.Verdict(Trust, cManifest + ' ', True, TFakeTrust.SignManifest(cManifest, 'a'),
    Keys));
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Forged,
    TUpdateManifestSignature.Verdict(Trust, cManifest, True, TFakeTrust.SignManifest(cManifest, 'c'), Keys));
end;

procedure TCommonUpdatesManifestSignatureTests.ForgedOnWrongLength;
var
  mSignature: string;
begin
  mSignature := TFakeTrust.SignManifest(cManifest, 'a');
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Forged,
    TUpdateManifestSignature.Verdict(Trust, cManifest, True, Copy(mSignature, 1, 126), Keys));
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Forged,
    TUpdateManifestSignature.Verdict(Trust, cManifest, True, mSignature + '00', Keys));
  Assert.AreEqual<TUpdateManifestVerdict>(TUpdateManifestVerdict.Forged,
    TUpdateManifestSignature.Verdict(Trust, cManifest, True, '', Keys));
end;

procedure TCommonUpdatesManifestSignatureTests.EmbedsTwoDistinctKeys;
var
  mKeys: TArray<string>;
  mKey: string;
  mBytes: TBytes;
begin
  mKeys := TUpdateManifestSignature.Keys;
  Assert.AreEqual(2, Integer(Length(mKeys)));
  for mKey in mKeys do
  begin
    Assert.IsTrue(TUpdateManifestSignature.TryHexBytes(mKey, mBytes), mKey);
    Assert.AreEqual(TUpdateManifestSignature.cKeyBytes, Integer(Length(mBytes)), mKey);
  end;
  Assert.AreNotEqual(mKeys[0], mKeys[1]);
end;

end.
