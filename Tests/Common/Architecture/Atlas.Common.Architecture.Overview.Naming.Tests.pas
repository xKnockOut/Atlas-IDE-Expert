unit Atlas.Common.Architecture.Overview.Naming.Tests;

// Tests der Namen der Teilsysteme (#1118, #1364): Zählung je Unit,
// unterscheidender Abschnitt, Schreibweise, doppelte Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSubsystemNamingTests = class
  private
    FParts: TArray<TArray<string>>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PartCountsCountOncePerUnit;
    [Test]
    procedure BestPartPrefersDistinguishingPart;
    [Test]
    procedure BestPartEmptyWithoutGain;
    [Test]
    procedure PartCaptionKeepsSpelling;
    [Test]
    procedure MakeUniqueNumbersDuplicates;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Architecture.Overview.Naming;

/// <summary>Zahl zu AKey; -1, wenn der Schlüssel fehlt.</summary>
function CountOf(const ACounts: TDictionary<string, Integer>; const AKey: string): Integer;
begin
  if not ACounts.TryGetValue(AKey, Result) then
  begin
    Result := -1;
  end;
end;

procedure TSubsystemNamingTests.Setup;
begin
  // App.Index.Reader, App.Index.Writer, app.Ui.Main, App.Ui.Index
  FParts := [TArray<string>.Create('App', 'Index'), TArray<string>.Create('App', 'Index'),
    TArray<string>.Create('app', 'Ui'), TArray<string>.Create('App', 'Ui', 'ui')];
end;

procedure TSubsystemNamingTests.TearDown;
begin
  FParts := nil;
end;

procedure TSubsystemNamingTests.PartCountsCountOncePerUnit;
var
  mCounts: TDictionary<string, Integer>;
begin
  mCounts := TSubsystemNaming.PartCounts(FParts, TArray<Integer>.Create(0, 1, 2, 3));
  try
    Assert.AreEqual(4, CountOf(mCounts, 'app'));
    Assert.AreEqual(2, CountOf(mCounts, 'index'));
    Assert.AreEqual(2, CountOf(mCounts, 'ui'));
    Assert.AreEqual(3, mCounts.Count);
  finally
    mCounts.Free;
  end;
end;

procedure TSubsystemNamingTests.BestPartPrefersDistinguishingPart;
var
  mGlobal: TDictionary<string, Integer>;
  mScore: Double;
begin
  mGlobal := TSubsystemNaming.PartCounts(FParts, TArray<Integer>.Create(0, 1, 2, 3));
  try
    Assert.AreEqual('ui', TSubsystemNaming.BestPart(FParts, TArray<Integer>.Create(2, 3), mGlobal, 4, mScore));
    Assert.IsTrue(mScore > 0);
  finally
    mGlobal.Free;
  end;
end;

procedure TSubsystemNamingTests.BestPartEmptyWithoutGain;
var
  mGlobal: TDictionary<string, Integer>;
  mScore: Double;
begin
  mGlobal := TSubsystemNaming.PartCounts(FParts, TArray<Integer>.Create(0, 1));
  try
    // Alle Abschnitte der Gruppe kommen in allen Units des Vergleichsumfangs vor: kein Gewinn.
    Assert.AreEqual('', TSubsystemNaming.BestPart(FParts, TArray<Integer>.Create(0, 1), mGlobal, 2, mScore));
    Assert.AreEqual(Double(0), mScore);
  finally
    mGlobal.Free;
  end;
end;

procedure TSubsystemNamingTests.PartCaptionKeepsSpelling;
begin
  Assert.AreEqual('app', TSubsystemNaming.PartCaption(FParts, TArray<Integer>.Create(2, 0), 'APP'));
  Assert.AreEqual('Ui', TSubsystemNaming.PartCaption(FParts, TArray<Integer>.Create(3), 'ui'));
  Assert.AreEqual('fehlt', TSubsystemNaming.PartCaption(FParts, TArray<Integer>.Create(0), 'fehlt'));
end;

procedure TSubsystemNamingTests.MakeUniqueNumbersDuplicates;
var
  mNames: TArray<string>;
begin
  mNames := TArray<string>.Create('Index', 'index', 'Ui', 'Index 2', 'Index');
  TSubsystemNaming.MakeUnique(mNames);
  Assert.AreEqual('Index', mNames[0]);
  Assert.AreEqual('index 2', mNames[1]);
  Assert.AreEqual('Ui', mNames[2]);
  Assert.AreEqual('Index 2 2', mNames[3]);
  Assert.AreEqual('Index 3', mNames[4]);
end;

end.
