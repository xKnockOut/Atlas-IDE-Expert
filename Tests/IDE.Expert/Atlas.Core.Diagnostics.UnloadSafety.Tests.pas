unit Atlas.Core.Diagnostics.UnloadSafety.Tests;

// Kennzeichen „Entladen ohne Neustart nicht sicher“: Gründe sammeln, jedes
// Package nur einmal festhalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUnloadSafetyTests = class
  private const
    /// <summary>Erfundenes Package: Der Test hält nichts im Speicher fest.</summary>
    cModule = $5B5B0000;
  private
    FPinned: TArray<HMODULE>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UnknownModuleIsSafe;
    [Test]
    procedure MarkUnsafeKeepsReasonsAndPinsOnce;
  end;

implementation

uses
  Atlas.Core.Diagnostics.UnloadSafety;

procedure TAtlasUnloadSafetyTests.Setup;
begin
  FPinned := nil;
  TAtlasUnloadSafety.ResetForTests(
    procedure(AModule: HMODULE)
    begin
      FPinned := FPinned + [AModule];
    end);
end;

procedure TAtlasUnloadSafetyTests.TearDown;
begin
  TAtlasUnloadSafety.ResetForTests(nil);
  FPinned := nil;
end;

procedure TAtlasUnloadSafetyTests.UnknownModuleIsSafe;
begin
  Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule));
  Assert.AreEqual(0, Length(TAtlasUnloadSafety.Reasons));
end;

procedure TAtlasUnloadSafetyTests.MarkUnsafeKeepsReasonsAndPinsOnce;
begin
  TAtlasUnloadSafety.MarkUnsafe(cModule, 'erster Grund');
  TAtlasUnloadSafety.MarkUnsafe(cModule, 'zweiter Grund');
  TAtlasUnloadSafety.MarkUnsafe(0, 'ohne Package');
  Assert.IsFalse(TAtlasUnloadSafety.IsSafe(cModule));
  Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule + 1));
  Assert.AreEqual(2, Length(TAtlasUnloadSafety.Reasons));
  Assert.AreEqual('zweiter Grund', TAtlasUnloadSafety.Reasons[1]);
  Assert.AreEqual(1, Length(FPinned));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnloadSafetyTests);

end.
