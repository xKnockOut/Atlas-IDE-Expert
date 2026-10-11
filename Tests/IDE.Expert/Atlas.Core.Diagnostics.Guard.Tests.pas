unit Atlas.Core.Diagnostics.Guard.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Absturzsicherheit (#493): Schutz, Sicherung, Protokoll.</summary>
  [TestFixture]
  TAtlasGuardTests = class
  private
    FFolder: string;
    FOldFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RunSwallowsExceptions;
    [Test]
    procedure FuseTripsAfterThreeFailuresWithinFiveMinutes;
    [Test]
    procedure OldFailuresDoNotCount;
    [Test]
    procedure TrippedFeatureIsSkippedOthersRun;
    [Test]
    procedure LogRotatesAtLimit;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard;

procedure TAtlasGuardTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasGuardTests' + TGUID.NewGuid.ToString);
  FOldFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FFolder;
  TAtlasGuard.Fuse.ResetAll;
end;

procedure TAtlasGuardTests.TearDown;
begin
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasGuardTests.RunSwallowsExceptions;
var
  Ran: Boolean;
begin
  Assert.IsFalse(TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end));
  Ran := False;
  Assert.IsTrue(TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      Ran := True;
    end));
  Assert.IsTrue(Ran);
  Assert.Contains(TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8), 'EInvalidOpException: kaputt');
end;

procedure TAtlasGuardTests.FuseTripsAfterThreeFailuresWithinFiveMinutes;
var
  Fuse: TAtlasFuse;
  Clock: TDateTime;
begin
  Clock := EncodeDateTime(2026, 10, 11, 12, 0, 0, 0);
  Fuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := Clock;
    end);
  try
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Completion));
    Clock := IncMinute(Clock, 2);
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Completion));
    Clock := IncMinute(Clock, 2);
    Assert.IsTrue(Fuse.Failed(TAtlasFeature.Completion), 'dritter Fehler in 4 Minuten löst aus');
    Assert.IsTrue(Fuse.Tripped(TAtlasFeature.Completion));
    Assert.IsFalse(Fuse.Tripped(TAtlasFeature.Hover), 'nur das betroffene Feature');
    Fuse.Reset(TAtlasFeature.Completion);
    Assert.IsFalse(Fuse.Tripped(TAtlasFeature.Completion));
  finally
    Fuse.Free;
  end;
end;

procedure TAtlasGuardTests.OldFailuresDoNotCount;
var
  Fuse: TAtlasFuse;
  Clock: TDateTime;
begin
  Clock := EncodeDateTime(2026, 10, 11, 12, 0, 0, 0);
  Fuse := TAtlasFuse.Create(
    function: TDateTime
    begin
      Result := Clock;
    end);
  try
    Fuse.Failed(TAtlasFeature.Pairs);
    Fuse.Failed(TAtlasFeature.Pairs);
    Clock := IncMinute(Clock, 6);
    Assert.IsFalse(Fuse.Failed(TAtlasFeature.Pairs), 'ältere Fehler liegen außerhalb der 5 Minuten');
  finally
    Fuse.Free;
  end;
end;

procedure TAtlasGuardTests.TrippedFeatureIsSkippedOthersRun;
var
  Index, Calls: Integer;
  Warning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      Warning := AText;
    end;
  for Index := 1 to 3 do
    TAtlasGuard.Run(TAtlasFeature.Problems,
      procedure
      begin
        raise Exception.Create('Fehler');
      end);
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Problems));
  Assert.Contains(Warning, 'Probleme');
  Calls := 0;
  TAtlasGuard.Run(TAtlasFeature.Problems,
    procedure
    begin
      Inc(Calls);
    end);
  Assert.AreEqual(0, Calls, 'abgeschaltet: läuft nicht mehr');
  TAtlasGuard.Run(TAtlasFeature.Hover,
    procedure
    begin
      Inc(Calls);
    end);
  Assert.AreEqual(1, Calls, 'andere Features laufen weiter');
  TAtlasGuard.Enable(TAtlasFeature.Problems);
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Problems));
end;

procedure TAtlasGuardTests.LogRotatesAtLimit;
var
  Log: TAtlasRotatingLog;
  Index: Integer;
begin
  Log := TAtlasRotatingLog.Create(FFolder, 200, 3);
  try
    for Index := 1 to 40 do
      Log.Add(StringOfChar('x', 40));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'atlas.1.log')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'atlas.2.log')));
    Assert.IsFalse(TFile.Exists(TPath.Combine(FFolder, 'atlas.3.log')), 'höchstens 3 Dateien');
  finally
    Log.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGuardTests);

end.
