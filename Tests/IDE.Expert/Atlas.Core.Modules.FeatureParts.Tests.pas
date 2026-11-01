unit Atlas.Core.Modules.FeatureParts.Tests;

// Tests zu TAtlasFeaturePart (#1455).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFeaturePartTests = class
  public
    [Test]
    procedure AtLevelFollowsMinLevel;
    [Test]
    procedure WhenCallsTheReferences;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.FeatureParts;

function Inactive: TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := False;
    end;
end;

procedure TFeaturePartTests.AtLevelFollowsMinLevel;
var
  mPart: IAtlasFeaturePart;
begin
  mPart := TAtlasFeaturePart.AtLevel('A', TAtlasSafeLevel.Safe, Inactive, nil, nil);
  Assert.AreEqual('A', mPart.Name);
  Assert.IsTrue(mPart.Wanted(TAtlasSafeLevel.Normal));
  Assert.IsTrue(mPart.Wanted(TAtlasSafeLevel.Safe));
  Assert.IsFalse(mPart.Wanted(TAtlasSafeLevel.Minimal));
  Assert.IsFalse(mPart.IsActive);
  mPart.Start;
  mPart.Stop;
end;

procedure TFeaturePartTests.WhenCallsTheReferences;
var
  mPart: IAtlasFeaturePart;
  mLog: string;
  mOn: Boolean;
begin
  mLog := '';
  mOn := False;
  mPart := TAtlasFeaturePart.When('B',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := mOn and (ALevel = TAtlasSafeLevel.Normal);
    end,
    function: Boolean
    begin
      Result := mLog = 'start';
    end,
    procedure
    begin
      mLog := 'start';
    end,
    procedure
    begin
      mLog := 'stop';
    end);
  Assert.IsFalse(mPart.Wanted(TAtlasSafeLevel.Normal));
  mOn := True;
  Assert.IsTrue(mPart.Wanted(TAtlasSafeLevel.Normal));
  mPart.Start;
  Assert.IsTrue(mPart.IsActive);
  mPart.Stop;
  Assert.AreEqual('stop', mLog);
  mPart := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TFeaturePartTests);

end.
