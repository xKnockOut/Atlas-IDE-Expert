unit Atlas.Core.Build.Events.Tests;

// Tests für die Compile-Ereignisse (#527) mit gefälschten Ereignissen, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCompileEventsTests = class
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
    /// <summary>#261: Builds auf Auftrag (Claude Code) tragen requestedBy, Builds des Benutzers nicht.</summary>
    [Test]
    procedure RequestedByMarksOwnBuilds;
    /// <summary>#533: Teilnehmer sehen vor dem Compile schon Background und RequestedBy; nach einem Abbruch
    /// erfahren alle den Grund (Läufer #261, Schnellaktion #764).</summary>
    [Test]
    procedure CancelSeesRunAndIsAnnounced;
    /// <summary>#1455: Ein abgemeldeter Teilnehmer bekommt nichts mehr; Abmelden während einer Verteilung gibt ihn
    /// erst danach frei und lässt die übrigen weiterlaufen.</summary>
    [Test]
    procedure RemovedParticipantHearsNothing;
    [Test]
    procedure RemoveDuringDispatch;
    /// <summary>#1775: Compiling zählt laufende Projekte außer Atlas' eigener Hintergrundprüfung.</summary>
    [Test]
    procedure CompilingIgnoresBackgroundChecks;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Build.Events;

type
  TRecorder = class(TAtlasCompileParticipant)
  public
    Trace: string;
    Cancel: Boolean;
    Fail: Boolean;
    procedure GroupStarted(AKind: TAtlasCompileKind); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    function CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean; override;
    procedure CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string); override;
    procedure ProjectStarted(const AProject: TAtlasCompileProject); override;
    procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

procedure TRecorder.GroupStarted(AKind: TAtlasCompileKind);
begin
  Trace := Trace + 'G+' + TAtlasCompileEvents.KindText(AKind) + ' ';
end;

procedure TRecorder.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  Trace := Trace + Format('G-%s/%d ', [BoolToStr(ASucceeded, True), ADurationMs]);
end;

procedure TRecorder.CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string);
begin
  Trace := Trace + 'X(' + AReason + ') ';
end;

function TRecorder.CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
begin
  Trace := Trace + 'C';
  if AProject.Background then
  begin
    Trace := Trace + 'b';
  end;
  if AProject.RequestedBy <> '' then
  begin
    Trace := Trace + '[' + AProject.RequestedBy + ']';
  end;
  Trace := Trace + ' ';
  if Fail then
  begin
    raise Exception.Create('kaputt');
  end;
  Result := Cancel;
  AReason := 'Hinweise vorhanden';
end;

procedure TRecorder.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  Trace := Trace + 'P+' + ExtractFileName(AProject.FileName) + ' ';
  if Fail then
  begin
    raise Exception.Create('kaputt');
  end;
end;

procedure TRecorder.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
begin
  Trace := Trace + Format('P-%s/%s/%d ', [ExtractFileName(AProject.FileName), BoolToStr(ASucceeded, True), ADurationMs]);
end;

var
  Clock: Int64;
  Sent: string;

function MakeEvents: TAtlasCompileEvents;
begin
  Clock := 1000;
  Sent := '';
  Result := TAtlasCompileEvents.Create(
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

function Project(const AFileName: string): TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := AFileName;
  Result.Kind := TAtlasCompileKind.Build;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
end;

procedure TAtlasCompileEventsTests.ProjectOnceWithDurationAndNotifications;
var
  mEvents: TAtlasCompileEvents;
  mRecorder: TRecorder;
begin
  mEvents := MakeEvents;
  try
    mRecorder := TRecorder.Create;
    mEvents.Add(mRecorder);
    // Zwei Notifier der IDE melden denselben Beginn.
    mEvents.ProjectStarted(Project('C:\P\App.dproj'));
    mEvents.ProjectStarted(Project('C:\P\App.dproj'));
    Clock := 1250;
    mEvents.ProjectFinished('C:\P\App.dproj', True);
    mEvents.ProjectFinished('C:\P\App.dproj', True);
    Assert.AreEqual('P+App.dproj P-App.dproj/True/250 ', mRecorder.Trace);
    Assert.AreEqual(
      'atlas/compileStarted{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64"}'#10 +
      'atlas/compileFinished{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64",' +
      '"success":true,"durationMs":250}'#10, Sent);
  finally
    mEvents.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.GroupRunAroundProjects;
var
  mEvents: TAtlasCompileEvents;
  mRecorder: TRecorder;
begin
  mEvents := MakeEvents;
  try
    mRecorder := TRecorder.Create;
    mEvents.Add(mRecorder);
    mEvents.GroupStarted(TAtlasCompileKind.Build);
    mEvents.ProjectStarted(Project('C:\P\A.dproj'));
    mEvents.ProjectFinished('C:\P\A.dproj', True);
    mEvents.ProjectStarted(Project('C:\P\B.dproj'));
    Clock := 1100;
    mEvents.ProjectFinished('C:\P\B.dproj', False);
    mEvents.GroupFinished(False);
    Assert.AreEqual('G+build P+A.dproj P-A.dproj/True/0 P+B.dproj P-B.dproj/False/100 G-False/100 ', mRecorder.Trace);
  finally
    mEvents.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.CompilingIgnoresBackgroundChecks;
var
  mEvents: TAtlasCompileEvents;
begin
  mEvents := MakeEvents;
  try
    Assert.IsFalse(mEvents.Compiling, 'vor dem Lauf');
    mEvents.Background := True;
    mEvents.ProjectStarted(Project('C:\P\A.dproj'));
    Assert.IsFalse(mEvents.Compiling, 'Hintergrundprüfung zählt nicht');
    mEvents.ProjectFinished('C:\P\A.dproj', True);
    mEvents.Background := False;
    mEvents.ProjectStarted(Project('C:\P\B.dproj'));
    Assert.IsTrue(mEvents.Compiling, 'Build des Benutzers');
    mEvents.ProjectFinished('C:\P\B.dproj', True);
    Assert.IsFalse(mEvents.Compiling, 'nach dem Lauf');
  finally
    mEvents.Free;
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.CodeInsightOnlyCounted;
var
  mEvents: TAtlasCompileEvents;
  mRecorder: TRecorder;
  mReason: string;
begin
  mEvents := MakeEvents;
  try
    mRecorder := TRecorder.Create;
    mRecorder.Cancel := True;
    mEvents.Add(mRecorder);
    Assert.IsFalse(mEvents.BeforeCompile(Project('C:\P\App.dproj'), True, mReason));
    Clock := 1040;
    mEvents.CodeInsightFinished;
    Assert.AreEqual('', mRecorder.Trace);
    Assert.AreEqual('', Sent);
    Assert.AreEqual(1, mEvents.CodeInsightCount);
    Assert.AreEqual(Int64(40), mEvents.CodeInsightMs);
  finally
    mEvents.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.ParticipantCancelsWithReason;
var
  mEvents: TAtlasCompileEvents;
  mRecorder: TRecorder;
  mReason: string;
begin
  mEvents := MakeEvents;
  try
    mRecorder := TRecorder.Create;
    mEvents.Add(mRecorder);
    Assert.IsFalse(mEvents.BeforeCompile(Project('C:\P\App.dproj'), False, mReason));
    mRecorder.Cancel := True;
    Assert.IsTrue(mEvents.BeforeCompile(Project('C:\P\App.dproj'), False, mReason));
    Assert.AreEqual('App.dproj: Hinweise vorhanden', mReason);
  finally
    mEvents.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.ExceptionIsLoggedAndOthersRun;
var
  mEvents: TAtlasCompileEvents;
  mFailing, mSecond: TRecorder;
  mLogged, mReason: string;
begin
  mEvents := MakeEvents;
  try
    mLogged := '';
    mEvents.OnLog :=
      procedure(const AText: string)
      begin
        mLogged := mLogged + AText;
      end;
    mFailing := TRecorder.Create;
    mFailing.Fail := True;
    mSecond := TRecorder.Create;
    mEvents.Add(mFailing);
    mEvents.Add(mSecond);
    mEvents.ProjectStarted(Project('C:\P\App.dproj'));
    Assert.IsFalse(mEvents.BeforeCompile(Project('C:\P\App.dproj'), False, mReason));
    Assert.AreEqual('P+App.dproj C ', mSecond.Trace);
    Assert.Contains(mLogged, 'kaputt');
  finally
    mEvents.Free;
    // Globaler Text darf den Leck-Monitor nicht über Testgrenzen täuschen.
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.RequestedByMarksOwnBuilds;
var
  mEvents: TAtlasCompileEvents;
begin
  mEvents := MakeEvents;
  try
    mEvents.RequestedBy := 'mcp';
    mEvents.ProjectStarted(Project('C:\P\App.dproj'));
    mEvents.RequestedBy := '';
    mEvents.ProjectFinished('C:\P\App.dproj', False);
    mEvents.ProjectStarted(Project('C:\P\App.dproj'));
    mEvents.ProjectFinished('C:\P\App.dproj', True);
    Assert.AreEqual(
      'atlas/compileStarted{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64",' +
      '"requestedBy":"mcp"}'#10 +
      'atlas/compileFinished{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64",' +
      '"requestedBy":"mcp","success":false,"durationMs":0}'#10 +
      'atlas/compileStarted{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64"}'#10 +
      'atlas/compileFinished{"project":"C:\\P\\App.dproj","kind":"build","configuration":"Debug","platform":"Win64",' +
      '"success":true,"durationMs":0}'#10, Sent);
  finally
    mEvents.Free;
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.CancelSeesRunAndIsAnnounced;
var
  mEvents: TAtlasCompileEvents;
  mFirst, mSecond: TRecorder;
  mReason: string;
begin
  mEvents := MakeEvents;
  try
    mFirst := TRecorder.Create;
    mSecond := TRecorder.Create;
    mEvents.Add(mFirst);
    mEvents.Add(mSecond);
    mEvents.RequestedBy := 'welcome';
    Assert.IsFalse(mEvents.BeforeCompile(Project('C:\P\App.dproj'), False, mReason));
    mEvents.RequestedBy := '';
    mEvents.Background := True;
    Assert.IsFalse(mEvents.BeforeCompile(Project('C:\P\App.dproj'), False, mReason));
    mEvents.Background := False;
    Assert.AreEqual('C[welcome] Cb ', mFirst.Trace);
    mFirst.Trace := '';
    mSecond.Trace := '';
    mFirst.Cancel := True;
    Assert.IsTrue(mEvents.BeforeCompile(Project('C:\P\App.dproj'), False, mReason));
    // Der zweite wird nach dem Abbruch nicht mehr gefragt, erfährt ihn aber.
    Assert.AreEqual('C X(App.dproj: Hinweise vorhanden) ', mFirst.Trace);
    Assert.AreEqual('X(App.dproj: Hinweise vorhanden) ', mSecond.Trace);
  finally
    mEvents.Free;
    Sent := '';
  end;
end;

type
  /// <summary>Meldet beim Gruppenstart AVictim ab.</summary>
  TRemover = class(TAtlasCompileParticipant)
  public
    Events: TAtlasCompileEvents;
    Victim: TAtlasCompileParticipant;
    procedure GroupStarted(AKind: TAtlasCompileKind); override;
  end;

  /// <summary>Meldet seine Freigabe.</summary>
  TFreeRecorder = class(TRecorder)
  public
    Freed: PBoolean;
    destructor Destroy; override;
  end;

procedure TRemover.GroupStarted(AKind: TAtlasCompileKind);
begin
  Events.Remove(Victim);
end;

destructor TFreeRecorder.Destroy;
begin
  if Freed <> nil then
  begin
    Freed^ := True;
  end;
  inherited;
end;

procedure TAtlasCompileEventsTests.RemovedParticipantHearsNothing;
var
  mEvents: TAtlasCompileEvents;
  mKept: TRecorder;
  mGone: TFreeRecorder;
  mWasFreed: Boolean;
begin
  mEvents := MakeEvents;
  try
    mKept := TRecorder.Create;
    mGone := TFreeRecorder.Create;
    mWasFreed := False;
    mGone.Freed := @mWasFreed;
    mEvents.Add(mKept);
    mEvents.Add(mGone);
    mEvents.Remove(mGone);
    Assert.IsTrue(mWasFreed, 'sofort frei');
    mEvents.Remove(mGone);
    mEvents.GroupStarted(TAtlasCompileKind.Make);
    Assert.AreEqual('G+make ', mKept.Trace);
  finally
    mEvents.Free;
    Sent := '';
  end;
end;

procedure TAtlasCompileEventsTests.RemoveDuringDispatch;
var
  mEvents: TAtlasCompileEvents;
  mRemover: TRemover;
  mVictim: TFreeRecorder;
  mLast: TRecorder;
  mWasFreed: Boolean;
begin
  mEvents := MakeEvents;
  try
    mRemover := TRemover.Create;
    mVictim := TFreeRecorder.Create;
    mLast := TRecorder.Create;
    mWasFreed := False;
    mVictim.Freed := @mWasFreed;
    mRemover.Events := mEvents;
    mRemover.Victim := mVictim;
    mEvents.Add(mRemover);
    mEvents.Add(mVictim);
    mEvents.Add(mLast);
    mEvents.GroupStarted(TAtlasCompileKind.Build);
    Assert.IsTrue(mWasFreed, 'nach der Verteilung frei');
    Assert.AreEqual('G+build ', mLast.Trace, 'die übrigen laufen weiter');
    mRemover.Victim := nil;
    mEvents.GroupStarted(TAtlasCompileKind.Make);
    Assert.AreEqual('G+build G+make ', mLast.Trace);
  finally
    mEvents.Free;
    Sent := '';
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompileEventsTests);

end.