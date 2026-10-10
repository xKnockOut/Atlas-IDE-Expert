unit Argus.Core.Build.Events.Tests;

// Tests für die Compile-Ereignisse (#527) mit gefälschten Ereignissen, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusCompileEventsTests = class
  public
    [Test]
    procedure ProjectOnceWithDurationAndNotifications;
    [Test]
    procedure GroupRunAroundProjects;
    [Test]
    procedure CodeInsightOnlyCounted;
    [Test]
    procedure ParticipantCancelsWithReason;
    [Test]
    procedure ExceptionIsLoggedAndOthersRun;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Core.Build.Events;

type
  TRecorder = class(TArgusCompileParticipant)
  public
    Trace: string;
    Cancel: Boolean;
    Fail: Boolean;
    procedure GroupStarted(AKind: TArgusCompileKind); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    function CancelCompile(const AProject: TArgusCompileProject; out AReason: string): Boolean; override;
    procedure ProjectStarted(const AProject: TArgusCompileProject); override;
    procedure ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

procedure TRecorder.GroupStarted(AKind: TArgusCompileKind);
begin
  Trace := Trace + 'G+' + TArgusCompileEvents.KindText(AKind) + ' ';
end;

procedure TRecorder.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  Trace := Trace + Format('G-%s/%d ', [BoolToStr(ASucceeded, True), ADurationMs]);
end;

function TRecorder.CancelCompile(const AProject: TArgusCompileProject; out AReason: string): Boolean;
begin
  Trace := Trace + 'C ';
  if Fail then
    raise Exception.Create('kaputt');
  Result := Cancel;
  AReason := 'Hinweise vorhanden';
end;

procedure TRecorder.ProjectStarted(const AProject: TArgusCompileProject);
begin
  Trace := Trace + 'P+' + ExtractFileName(AProject.FileName) + ' ';
  if Fail then
    raise Exception.Create('kaputt');
end;

procedure TRecorder.ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
begin
  Trace := Trace + Format('P-%s/%s/%d ', [ExtractFileName(AProject.FileName), BoolToStr(ASucceeded, True), ADurationMs]);
end;

var
  Clock: Int64;
  Sent: string;

function MakeEvents: TArgusCompileEvents;
begin
  Clock := 1000;
  Sent := '';
  Result := TArgusCompileEvents.Create(
    function: Int64
    begin
      Result := Clock;
    end);
  Result.OnNotify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      Sent := Sent + AMethod + AParams.ToJSON + #10;
      AParams.Free;
    end;
end;

function Project(const AFileName: string): TArgusCompileProject;
begin
  Result := Default(TArgusCompileProject);
  Result.FileName := AFileName;
  Result.Kind := TArgusCompileKind.Build;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
end;

procedure TArgusCompileEventsTests.ProjectOnceWithDurationAndNotifications;
var
  Events: TArgusCompileEvents;
  Recorder: TRecorder;
begin
  Events := MakeEvents;
  try
    Recorder := TRecorder.Create;
    Events.Add(Recorder);
    // Zwei Notifier der IDE melden denselben Beginn.
    Events.ProjectStarted(Project('C:\P\App.dproj'));
    Events.ProjectStarted(Project('C:\P\App.dproj'));
    Clock := 1250;
    Events.ProjectFinished('C:\P\App.dproj', True);
    Events.ProjectFinished('C:\P\App.dproj', True);
    Assert.AreEqual('P+App.dproj P-App.dproj/True/250 ', Recorder.Trace);
    Assert.AreEqual(
      'argus/compileStarted{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64"}'#10 +
      'argus/compileFinished{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64",' +
      '"success":true,"durationMs":250}'#10, Sent);
  finally
    Events.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TArgusCompileEventsTests.GroupRunAroundProjects;
var
  Events: TArgusCompileEvents;
  Recorder: TRecorder;
begin
  Events := MakeEvents;
  try
    Recorder := TRecorder.Create;
    Events.Add(Recorder);
    Events.GroupStarted(TArgusCompileKind.Build);
    Events.ProjectStarted(Project('C:\P\A.dproj'));
    Events.ProjectFinished('C:\P\A.dproj', True);
    Events.ProjectStarted(Project('C:\P\B.dproj'));
    Clock := 1100;
    Events.ProjectFinished('C:\P\B.dproj', False);
    Events.GroupFinished(False);
    Assert.AreEqual('G+build P+A.dproj P-A.dproj/True/0 P+B.dproj P-B.dproj/False/100 G-False/100 ', Recorder.Trace);
  finally
    Events.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TArgusCompileEventsTests.CodeInsightOnlyCounted;
var
  Events: TArgusCompileEvents;
  Recorder: TRecorder;
  Reason: string;
begin
  Events := MakeEvents;
  try
    Recorder := TRecorder.Create;
    Recorder.Cancel := True;
    Events.Add(Recorder);
    Assert.IsFalse(Events.BeforeCompile(Project('C:\P\App.dproj'), True, Reason));
    Clock := 1040;
    Events.CodeInsightFinished;
    Assert.AreEqual('', Recorder.Trace);
    Assert.AreEqual('', Sent);
    Assert.AreEqual(1, Events.CodeInsightCount);
    Assert.AreEqual(Int64(40), Events.CodeInsightMs);
  finally
    Events.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TArgusCompileEventsTests.ParticipantCancelsWithReason;
var
  Events: TArgusCompileEvents;
  Recorder: TRecorder;
  Reason: string;
begin
  Events := MakeEvents;
  try
    Recorder := TRecorder.Create;
    Events.Add(Recorder);
    Assert.IsFalse(Events.BeforeCompile(Project('C:\P\App.dproj'), False, Reason));
    Recorder.Cancel := True;
    Assert.IsTrue(Events.BeforeCompile(Project('C:\P\App.dproj'), False, Reason));
    Assert.AreEqual('App.dproj: Hinweise vorhanden', Reason);
  finally
    Events.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TArgusCompileEventsTests.ExceptionIsLoggedAndOthersRun;
var
  Events: TArgusCompileEvents;
  Failing, Second: TRecorder;
  Logged, Reason: string;
begin
  Events := MakeEvents;
  try
    Logged := '';
    Events.OnLog :=
      procedure(const AText: string)
      begin
        Logged := Logged + AText;
      end;
    Failing := TRecorder.Create;
    Failing.Fail := True;
    Second := TRecorder.Create;
    Events.Add(Failing);
    Events.Add(Second);
    Events.ProjectStarted(Project('C:\P\App.dproj'));
    Assert.IsFalse(Events.BeforeCompile(Project('C:\P\App.dproj'), False, Reason));
    Assert.AreEqual('P+App.dproj C ', Second.Trace);
    Assert.Contains(Logged, 'kaputt');
  finally
    Events.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusCompileEventsTests);

end.