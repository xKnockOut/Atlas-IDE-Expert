unit Atlas.IDE.Contracts.GhostSuggestions.Tests;

// Vertrag der Schattentext-Anbieter (#1890): Reihenfolge der Anmeldung, Abmelden, eingeschaltete Anbieter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGhostProvidersTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsOrderAndRemoves;
    [Test]
    procedure AnyEnabledAsksProviders;
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Contracts.GhostSuggestions;

type
  TFakeProvider = class(TInterfacedObject, IAtlasGhostProvider)
  private
    FEnabled: Boolean;
  public
    constructor Create(AEnabled: Boolean);
    function Enabled: Boolean;
    function Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
    procedure Accepted(const AProposal: TAtlasGhostProposal);
    procedure Rejected(const AProposal: TAtlasGhostProposal);
  end;

constructor TFakeProvider.Create(AEnabled: Boolean);
begin
  inherited Create;
  FEnabled := AEnabled;
end;

function TFakeProvider.Enabled: Boolean;
begin
  Result := FEnabled;
end;

function TFakeProvider.Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
begin
  Result := nil;
end;

procedure TFakeProvider.Accepted(const AProposal: TAtlasGhostProposal);
begin
end;

procedure TFakeProvider.Rejected(const AProposal: TAtlasGhostProposal);
begin
end;

procedure TAtlasGhostProvidersTests.TearDown;
var
  mProvider: IAtlasGhostProvider;
begin
  for mProvider in TAtlasGhostProviders.List do
  begin
    TAtlasGhostProviders.Remove(mProvider);
  end;
end;

procedure TAtlasGhostProvidersTests.KeepsOrderAndRemoves;
var
  mFirst, mSecond: IAtlasGhostProvider;
begin
  mFirst := TFakeProvider.Create(True);
  mSecond := TFakeProvider.Create(True);
  TAtlasGhostProviders.Add(mFirst);
  TAtlasGhostProviders.Add(mSecond);
  TAtlasGhostProviders.Add(mFirst);
  Assert.AreEqual(2, Integer(Length(TAtlasGhostProviders.List)), 'zweimal angemeldet zählt einmal');
  Assert.IsTrue(TAtlasGhostProviders.List[0] = mSecond, 'erneutes Anmelden stellt hinten an');
  TAtlasGhostProviders.Remove(mSecond);
  Assert.AreEqual(1, Integer(Length(TAtlasGhostProviders.List)));
  Assert.IsTrue(TAtlasGhostProviders.List[0] = mFirst);
end;

procedure TAtlasGhostProvidersTests.AnyEnabledAsksProviders;
var
  mOff, mOn: IAtlasGhostProvider;
begin
  Assert.IsFalse(TAtlasGhostProviders.AnyEnabled, 'ohne Anbieter');
  mOff := TFakeProvider.Create(False);
  TAtlasGhostProviders.Add(mOff);
  Assert.IsFalse(TAtlasGhostProviders.AnyEnabled);
  mOn := TFakeProvider.Create(True);
  TAtlasGhostProviders.Add(mOn);
  Assert.IsTrue(TAtlasGhostProviders.AnyEnabled);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGhostProvidersTests);

end.
