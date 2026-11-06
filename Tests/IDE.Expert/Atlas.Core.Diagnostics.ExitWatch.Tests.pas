unit Atlas.Core.Diagnostics.ExitWatch.Tests;

// Wache auf das Zerstören einer Komponente: Grundlage des Abbaus beim Beenden der IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExitWatchTests = class
  public
    [Test]
    procedure RunsWhenTargetIsDestroyed;
    [Test]
    procedure RunsOnlyOnce;
    [Test]
    procedure FreedWatchStaysSilent;
    [Test]
    procedure OtherComponentsDoNotCount;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Diagnostics.ExitWatch;

type
  TOpenWatch = class(TAtlasExitWatch);

procedure TExitWatchTests.RunsWhenTargetIsDestroyed;
var
  mTarget: TComponent;
  mWatch: TAtlasExitWatch;
  mCalls: Integer;
begin
  mCalls := 0;
  mTarget := TComponent.Create(nil);
  mWatch := TAtlasExitWatch.Create(mTarget,
    procedure
    begin
      Inc(mCalls);
    end);
  try
    Assert.AreEqual(0, mCalls);
    mTarget.Free;
    Assert.AreEqual(1, mCalls);
  finally
    mWatch.Free;
  end;
end;

procedure TExitWatchTests.RunsOnlyOnce;
var
  mTarget: TComponent;
  mWatch: TAtlasExitWatch;
  mCalls: Integer;
begin
  mCalls := 0;
  mTarget := TComponent.Create(nil);
  mWatch := TAtlasExitWatch.Create(mTarget,
    procedure
    begin
      Inc(mCalls);
    end);
  try
    mTarget.Free;
    TOpenWatch(mWatch).Notification(nil, opRemove);
    Assert.AreEqual(1, mCalls);
  finally
    mWatch.Free;
  end;
end;

procedure TExitWatchTests.FreedWatchStaysSilent;
var
  mTarget: TComponent;
  mWatch: TAtlasExitWatch;
  mCalls: Integer;
begin
  mCalls := 0;
  mTarget := TComponent.Create(nil);
  try
    mWatch := TAtlasExitWatch.Create(mTarget,
      procedure
      begin
        Inc(mCalls);
      end);
    mWatch.Free;
  finally
    mTarget.Free;
  end;
  Assert.AreEqual(0, mCalls);
end;

procedure TExitWatchTests.OtherComponentsDoNotCount;
var
  mTarget, mOther: TComponent;
  mWatch: TAtlasExitWatch;
  mCalls: Integer;
begin
  mCalls := 0;
  mTarget := TComponent.Create(nil);
  mOther := TComponent.Create(nil);
  mWatch := TAtlasExitWatch.Create(mTarget,
    procedure
    begin
      Inc(mCalls);
    end);
  try
    mOther.FreeNotification(mWatch);
    mOther.Free;
    Assert.AreEqual(0, mCalls);
  finally
    mWatch.Free;
    mTarget.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExitWatchTests);

end.
