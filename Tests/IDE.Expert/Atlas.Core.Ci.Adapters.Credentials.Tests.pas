unit Atlas.Core.Ci.Adapters.Credentials.Tests;

// Tests für den Zugang zum Build-Server und zum Issue-Tracker (#763, #765) über einen Anmeldespeicher (#1922: der
// Speicher von Windows liegt jetzt in Base und wird übergeben): Lesen, Schreiben mit Vorgabekommentar, Löschen. Der
// Speicher ist eine Fälschung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasCiCredentialStoreTests = class
  public
    [Test]
    procedure WriteUsesDefaultComment;
    [Test]
    procedure WriteKeepsOwnComment;
    [Test]
    procedure ReadAndDeletePassThrough;
  end;

implementation

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Credentials.Contract,
  Atlas.Core.Ci.Adapters.Credentials;

type
  TFakeStore = class(TInterfacedObject, IAtlasCredentialStore)
  public
    Target: string;
    User: string;
    Secret: string;
    Comment: string;
    Deleted: string;
    function Read(const ATarget: string; out AUser, ASecret: string): Boolean;
    function Write(const ATarget, AUser, ASecret, AComment: string): Boolean;
    function Delete(const ATarget: string): Boolean;
  end;

{ TFakeStore }

function TFakeStore.Read(const ATarget: string; out AUser, ASecret: string): Boolean;
begin
  Result := ATarget = Target;
  AUser := '';
  ASecret := '';
  if Result then
  begin
    AUser := User;
    ASecret := Secret;
  end;
end;

function TFakeStore.Write(const ATarget, AUser, ASecret, AComment: string): Boolean;
begin
  Target := ATarget;
  User := AUser;
  Secret := ASecret;
  Comment := AComment;
  Result := True;
end;

function TFakeStore.Delete(const ATarget: string): Boolean;
begin
  Deleted := ATarget;
  Result := True;
end;

{ TAtlasCiCredentialStoreTests }

procedure TAtlasCiCredentialStoreTests.WriteUsesDefaultComment;
var
  mFake: TFakeStore;
  mStore: IAtlasCredentialStore;
  mCredentials: IAtlasCiCredentialStore;
begin
  mFake := TFakeStore.Create;
  mStore := mFake;
  mCredentials := TAtlasCiCredentialStore.Create(mStore);
  Assert.IsTrue(mCredentials.Write('Atlas:ci:https://ci', 'anna', 't1', ''));
  Assert.AreEqual(TAtlasCiCredentialStore.cDefaultComment, mFake.Comment);
  Assert.AreEqual('anna', mFake.User);
  Assert.AreEqual('t1', mFake.Secret);
end;

procedure TAtlasCiCredentialStoreTests.WriteKeepsOwnComment;
var
  mFake: TFakeStore;
  mStore: IAtlasCredentialStore;
  mCredentials: IAtlasCiCredentialStore;
begin
  mFake := TFakeStore.Create;
  mStore := mFake;
  mCredentials := TAtlasCiCredentialStore.Create(mStore);
  mCredentials.Write('Atlas:tracker:https://github.com', 'GitHub', 't2', 'Atlas: Issue-Tracker');
  Assert.AreEqual('Atlas: Issue-Tracker', mFake.Comment);
end;

procedure TAtlasCiCredentialStoreTests.ReadAndDeletePassThrough;
var
  mFake: TFakeStore;
  mStore: IAtlasCredentialStore;
  mCredentials: IAtlasCiCredentialStore;
  mUser, mToken: string;
begin
  mFake := TFakeStore.Create;
  mStore := mFake;
  mCredentials := TAtlasCiCredentialStore.Create(mStore);
  mCredentials.Write('ziel', 'bert', 't3', '');
  Assert.IsTrue(mCredentials.Read('ziel', mUser, mToken), 'gelesen');
  Assert.AreEqual('bert', mUser);
  Assert.AreEqual('t3', mToken);
  Assert.IsFalse(mCredentials.Read('anders', mUser, mToken), 'fremdes Ziel');
  Assert.IsTrue(mCredentials.Delete('ziel'));
  Assert.AreEqual('ziel', mFake.Deleted);
end;

end.
