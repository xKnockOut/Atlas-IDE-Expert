unit Atlas.Core.StartProfiles.Flow.Tests;

// Tests für den Ablauf der Startprofile (#575) ohne IDE: Profil setzen und
// merken, zurücksetzen auf die Startoptionen von vorher, gemerktes Profil
// erneut setzen, Fehler beim Schreiben und beim Speichern, aktuelle
// Startoptionen als persönliches Profil speichern, Statusfeld.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.StartProfiles.Store,
  Atlas.Core.StartProfiles.Flow;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasStartProfileFlowTests = class
  private
    FFolder: string;
    FTeamText: string;
    FOpen: Boolean;
    FFailWrite: Boolean;
    FOptions: TAtlasStartOptions;
    FWrites: Integer;
    function NewFlow: TAtlasStartProfileFlow;
    procedure RemoveFolder;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActivateWritesOptionsAndRemembersBefore;
    [Test]
    procedure NoProfileRestoresOptionsFromBefore;
    [Test]
    procedure UnknownProfileWritesNothing;
    [Test]
    procedure ClosedProjectIsReported;
    [Test]
    procedure FailedWriteKeepsLocalFile;
    [Test]
    procedure ReapplyWritesRememberedProfile;
    [Test]
    procedure SaveCurrentAddsPersonalProfile;
    [Test]
    procedure StatusNamesActiveAndMissingProfile;
    [Test]
    procedure PersonalFileIsCreated;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Plugin.Settings.TeamFile,
  Atlas.Core.StartProfiles.Picker;

const
  cProject = 'C:\Repo\App\App.dproj';
  cTeam = '{"version": 1, "startProfiles": [{"name": "Demo", "parameters": "-demo"}]}';

{ TAtlasStartProfileFlowTests }

procedure TAtlasStartProfileFlowTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasStartProfileFlow' + IntToStr(Random(1000000)));
  FTeamText := cTeam;
  FOpen := True;
  FFailWrite := False;
  FOptions := Default(TAtlasStartOptions);
  FOptions.Parameters := '-vorher';
  FWrites := 0;
end;

procedure TAtlasStartProfileFlowTests.TearDown;
begin
  RemoveFolder;
  FFolder := '';
  FTeamText := '';
  FOptions := Default(TAtlasStartOptions);
end;

procedure TAtlasStartProfileFlowTests.RemoveFolder;
var
  mFile: string;
begin
  if not DirectoryExists(FFolder) then
  begin
    Exit;
  end;
  for mFile in TDirectory.GetFiles(FFolder) do
  begin
    System.SysUtils.DeleteFile(mFile);
  end;
  RemoveDir(FFolder);
end;

function TAtlasStartProfileFlowTests.NewFlow: TAtlasStartProfileFlow;
var
  mAccess: TAtlasStartProfileAccess;
begin
  mAccess := Default(TAtlasStartProfileAccess);
  mAccess.Folder := FFolder;
  mAccess.TeamOf :=
    function(const AProject: string): TAtlasTeamSettings
    begin
      Result := TAtlasTeamFile.Parse(FTeamText, 'C:\Repo\App\.atlas', 'C:\Repo');
    end;
  mAccess.ReadOptions :=
    function(const AProject: string; out AOptions: TAtlasStartOptions): Boolean
    begin
      AOptions := FOptions;
      Result := FOpen;
    end;
  mAccess.WriteOptions :=
    function(const AProject: string; const AOptions: TAtlasStartOptions; out AReason: string): Boolean
    begin
      AReason := '';
      Result := not FFailWrite;
      if Result then
      begin
        FOptions := AOptions;
        Inc(FWrites);
      end
      else
      begin
        AReason := 'gesperrt';
      end;
    end;
  Result := TAtlasStartProfileFlow.Create(mAccess);
end;

procedure TAtlasStartProfileFlowTests.ActivateWritesOptionsAndRemembersBefore;
var
  mFlow: TAtlasStartProfileFlow;
  mResult: TAtlasStartProfileResult;
  mState: TAtlasStartProfileState;
begin
  mFlow := NewFlow;
  try
    mResult := mFlow.Activate(cProject, 'demo');
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Applied, mResult.Outcome);
    Assert.IsTrue(mResult.Succeeded);
    Assert.AreEqual('Demo', mResult.Name, 'Name wie im Profil');
    Assert.AreEqual('-demo', mResult.Options.Parameters);
    Assert.AreEqual('-demo', FOptions.Parameters, 'geschrieben');
    Assert.AreEqual('Demo', mFlow.ActiveName(cProject), 'gemerkt');
    mState := TAtlasStartProfiles.Load(FFolder, cProject);
    Assert.IsTrue(mState.HasOriginal);
    Assert.AreEqual('-vorher', mState.Original.Parameters, 'Startoptionen von vorher gemerkt');
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.NoProfileRestoresOptionsFromBefore;
var
  mFlow: TAtlasStartProfileFlow;
  mResult: TAtlasStartProfileResult;
begin
  mFlow := NewFlow;
  try
    mFlow.Activate(cProject, 'Demo');
    mResult := mFlow.Activate(cProject, '  ');
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Restored, mResult.Outcome);
    Assert.AreEqual('-vorher', FOptions.Parameters, 'zurückgesetzt');
    Assert.AreEqual('', mFlow.ActiveName(cProject));
    FWrites := 0;
    mResult := mFlow.Activate(cProject, '');
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Restored,
      mResult.Outcome, 'ohne gemerkte bleiben die jetzigen');
    Assert.AreEqual(0, FWrites, 'nichts geschrieben');
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.UnknownProfileWritesNothing;
var
  mFlow: TAtlasStartProfileFlow;
  mResult: TAtlasStartProfileResult;
begin
  mFlow := NewFlow;
  try
    mResult := mFlow.Activate(cProject, 'Fehlt');
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Unknown, mResult.Outcome);
    Assert.IsFalse(mResult.Succeeded);
    Assert.AreEqual('Fehlt', mResult.Name);
    Assert.AreEqual(0, FWrites);
    Assert.AreEqual('', mFlow.ActiveName(cProject));
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.ClosedProjectIsReported;
var
  mFlow: TAtlasStartProfileFlow;
begin
  FOpen := False;
  mFlow := NewFlow;
  try
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.NotOpen,
      mFlow.Activate(cProject, 'Demo').Outcome);
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.NotOpen,
      mFlow.SaveCurrent(cProject, 'Neu').Outcome);
    Assert.AreEqual(0, FWrites);
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.FailedWriteKeepsLocalFile;
var
  mFlow: TAtlasStartProfileFlow;
  mResult: TAtlasStartProfileResult;
begin
  FFailWrite := True;
  mFlow := NewFlow;
  try
    mResult := mFlow.Activate(cProject, 'Demo');
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.WriteFailed, mResult.Outcome);
    Assert.AreEqual('gesperrt', mResult.Reason);
    Assert.AreEqual('', mFlow.ActiveName(cProject), 'nichts gemerkt');
    Assert.IsFalse(FileExists(TAtlasStartProfiles.FileFor(FFolder, cProject)));
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.ReapplyWritesRememberedProfile;
var
  mFlow: TAtlasStartProfileFlow;
  mResult: TAtlasStartProfileResult;
begin
  mFlow := NewFlow;
  try
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Done,
      mFlow.Reapply(cProject).Outcome, 'ohne aktives nichts');
    Assert.AreEqual(0, FWrites);
    mFlow.Activate(cProject, 'Demo');
    FOptions := Default(TAtlasStartOptions);
    mResult := mFlow.Reapply(cProject);
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Done, mResult.Outcome);
    Assert.AreEqual('-demo', FOptions.Parameters, 'erneut gesetzt');
    FFailWrite := True;
    mResult := mFlow.Reapply(cProject);
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.WriteFailed, mResult.Outcome);
    Assert.AreEqual('gesperrt', mResult.Reason);
    FTeamText := '{"version": 1}';
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Done,
      mFlow.Reapply(cProject).Outcome, 'Profil fehlt: nichts');
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.SaveCurrentAddsPersonalProfile;
var
  mFlow: TAtlasStartProfileFlow;
  mResult: TAtlasStartProfileResult;
  mEntries: TArray<TAtlasStartProfileEntry>;
begin
  mFlow := NewFlow;
  try
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.InvalidName,
      mFlow.SaveCurrent(cProject, '   ').Outcome);
    mResult := mFlow.SaveCurrent(cProject, ' Lokal ');
    Assert.AreEqual<TAtlasStartProfileOutcome>(TAtlasStartProfileOutcome.Saved, mResult.Outcome);
    Assert.AreEqual('Lokal', mResult.Name);
    mEntries := mFlow.Profiles(cProject);
    Assert.AreEqual(2, Integer(Length(mEntries)), 'gemeinsam und persönlich');
    Assert.AreEqual('Lokal', mEntries[1].Profile.Name);
    Assert.AreEqual('-vorher', mEntries[1].Profile.Parameters);
    Assert.AreEqual('', mFlow.ActiveName(cProject), 'erst Activate macht es aktiv');
    Assert.AreEqual(0, Integer(Length(mFlow.Profiles(''))), 'ohne Projekt');
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.StatusNamesActiveAndMissingProfile;
var
  mFlow: TAtlasStartProfileFlow;
  mStatus: TAtlasStartProfileStatus;
begin
  mFlow := NewFlow;
  try
    Assert.AreEqual<TAtlasStartProfileStatusKind>(TAtlasStartProfileStatusKind.Hidden, mFlow.Status('').Kind);
    Assert.AreEqual<TAtlasStartProfileStatusKind>(TAtlasStartProfileStatusKind.NoneActive, mFlow.Status(cProject).Kind);
    mFlow.Activate(cProject, 'Demo');
    mStatus := mFlow.Status(cProject);
    Assert.AreEqual<TAtlasStartProfileStatusKind>(TAtlasStartProfileStatusKind.Active, mStatus.Kind);
    Assert.AreEqual('Demo', mStatus.Entry.Profile.Name);
    FTeamText := '{"version": 1}';
    mStatus := mFlow.Status(cProject);
    Assert.AreEqual<TAtlasStartProfileStatusKind>(TAtlasStartProfileStatusKind.Missing, mStatus.Kind);
    Assert.AreEqual('Demo', mStatus.Active);
  finally
    mFlow.Free;
  end;
end;

procedure TAtlasStartProfileFlowTests.PersonalFileIsCreated;
var
  mFlow: TAtlasStartProfileFlow;
  mFileName: string;
begin
  mFlow := NewFlow;
  try
    Assert.IsTrue(mFlow.PersonalFile(cProject, mFileName));
    Assert.IsTrue(FileExists(mFileName));
    Assert.AreEqual(TAtlasStartProfiles.FileFor(FFolder, cProject), mFileName);
    Assert.IsTrue(mFlow.PersonalFile(cProject, mFileName), 'vorhandene Datei bleibt');
  finally
    mFlow.Free;
  end;
end;

end.
