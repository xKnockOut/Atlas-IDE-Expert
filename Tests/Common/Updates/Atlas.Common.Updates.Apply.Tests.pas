unit Atlas.Common.Updates.Apply.Tests;

// Tests des Tauschs (#1519, Befehle apply und install): Warten auf die IDE,
// Abbruch, Auswahl der Module, Known Packages, andere Profile und Rückfall
// bei einem Fehler.

interface

uses
  DUnitX.TestFramework,
  Atlas.Text.UpdateRun,
  Atlas.Common.Updates.Apply,
  Atlas.Tests.UpdateFakes;

type
  [TestFixture]
  TCommonUpdatesApplyTests = class
  private
    FFake: TFakeUpdateSystem;
    function Args(const ASelect: TArray<string>): TUpdateArguments;
    function Input: TUpdateApplyInput;
    function Apply(const ASelect: TArray<string>): TUpdateOutcome;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InstallsProposal;
    [Test]
    procedure RemovesDeselectedModule;
    [Test]
    procedure KeepsModuleOfOtherProfile;
    [Test]
    procedure WaitsForIde;
    [Test]
    procedure CancelsWhileWaiting;
    [Test]
    procedure RollsBackOnError;
    [Test]
    procedure UpdatesOtherPlatformInPlace;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Updates.Prepare;

const
  cRoot = 'C:\Local\Atlas\Updates';
  cStaging = cRoot + '\2.0.1';
  cFiles = cStaging + '\files';
  cTarget = 'C:\Atlas';
  cKey = 'Software\Embarcadero\BDS\37.0';
  cKnown = cKey + '\Known Packages';

procedure TCommonUpdatesApplyTests.Setup;
begin
  FFake := TFakeUpdateSystem.Create;
  FFake.Files.WriteText(cFiles + '\AtlasServer.exe', 'server 2.0.1');
  FFake.Files.WriteText(cFiles + '\Win32\Atlas.IDE.Base370.bpl', 'base 2.0.1');
  FFake.Files.WriteText(cFiles + '\Win32\Atlas.IDE.Debugger370.bpl', 'debugger 2.0.1');
  FFake.Files.WriteText(cFiles + '\Win32\Atlas.IDE.Debugger370.map', 'debugger map');
  FFake.Files.WriteText(cFiles + '\Win32\Atlas.IDE.Search370.bpl', 'search 2.0.1');
  FFake.Files.WriteText(cTarget + '\AtlasServer.exe', 'server 2.0.0');
  FFake.Files.WriteText(cTarget + '\Win32\Atlas.IDE.Base370.bpl', 'base 2.0.0');
  FFake.Files.WriteText(cTarget + '\Win32\Atlas.IDE.Debugger370.bpl', 'debugger 2.0.0');
  FFake.Files.WriteText(cTarget + '\Win32\Atlas.IDE.Debugger370.map', 'debugger map 2.0.0');
  FFake.Registry.WriteValue(cKnown, cTarget + '\Win32\Atlas.IDE.Base370.bpl', 'Atlas Base');
  FFake.Registry.WriteValue(cKnown, cTarget + '\Win32\Atlas.IDE.Debugger370.bpl', 'Atlas Debugger');
end;

procedure TCommonUpdatesApplyTests.TearDown;
begin
  FreeAndNil(FFake);
end;

function TCommonUpdatesApplyTests.Args(const ASelect: TArray<string>): TUpdateArguments;
begin
  Result := Default(TUpdateArguments);
  Result.Command := 'apply';
  Result.Ide := '37.0';
  Result.Platform := 'Win32';
  Result.RegistryKey := cKey;
  Result.Target := cTarget;
  Result.Staging := cStaging;
  Result.Select := ASelect;
  Result.WaitPid := 4711;
  Result.NewModules := TUpdateNewModules.Install;
end;

function TCommonUpdatesApplyTests.Input: TUpdateApplyInput;
begin
  Result := Default(TUpdateApplyInput);
  Result.FilesDir := cFiles;
  Result.WorkDir := cStaging;
  Result.RootDir := cRoot;
  Result.Version := '2.0.1';
  Result.Previous := '2.0.0';
  Result.Candidates := TUpdateFolders.Candidates(FFake.System, Args(nil), cFiles);
end;

function TCommonUpdatesApplyTests.Apply(const ASelect: TArray<string>): TUpdateOutcome;
var
  mInstallation: TUpdateInstallation;
begin
  mInstallation := TUpdateInstallation.Create(FFake.System, Args(ASelect), Input);
  try
    mInstallation.Run;
    Result := mInstallation.Outcome;
  finally
    mInstallation.Free;
  end;
end;

procedure TCommonUpdatesApplyTests.InstallsProposal;
var
  mOutcome: TUpdateOutcome;
begin
  mOutcome := Apply(nil);
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Installed,
    mOutcome.Kind, mOutcome.Reason + ' ' + mOutcome.Detail);
  Assert.AreEqual('server 2.0.1', FFake.Files.ReadText(cTarget + '\AtlasServer.exe'));
  Assert.AreEqual('search 2.0.1', FFake.Files.ReadText(cTarget + '\Win32\Atlas.IDE.Search370.bpl'));
  Assert.IsTrue(FFake.Registry.Has(cKnown, cTarget + '\Win32\Atlas.IDE.Search370.bpl'));
  Assert.AreEqual('Atlas.IDE.Search', string.Join(',', mOutcome.Added));
  Assert.AreEqual(0, Integer(Length(mOutcome.Removed)));
  Assert.AreEqual('installed', TUpdateNames.OutcomeName(TUpdateOutcome.FromJson(FFake.Files.ReadText(cRoot +
    '\result.json')).Kind));
end;

procedure TCommonUpdatesApplyTests.RemovesDeselectedModule;
var
  mOutcome: TUpdateOutcome;
begin
  mOutcome := Apply(TArray<string>.Create('Atlas.IDE.Base'));
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Installed,
    mOutcome.Kind, mOutcome.Reason + ' ' + mOutcome.Detail);
  Assert.IsFalse(FFake.Files.FileExists(cTarget + '\Win32\Atlas.IDE.Debugger370.bpl'));
  Assert.IsFalse(FFake.Files.FileExists(cTarget + '\Win32\Atlas.IDE.Debugger370.map'));
  Assert.IsFalse(FFake.Files.FileExists(cTarget + '\Win32\Atlas.IDE.Search370.bpl'));
  Assert.IsFalse(FFake.Registry.Has(cKnown, cTarget + '\Win32\Atlas.IDE.Debugger370.bpl'));
  Assert.AreEqual('Atlas.IDE.Debugger', string.Join(',', mOutcome.Removed));
  // Das abgelehnte neue Modul wird nicht wieder vorgeschlagen.
  Assert.AreEqual('Atlas.IDE.Search'#13#10, FFake.Files.ReadText(cRoot + '\declined.txt'));
end;

procedure TCommonUpdatesApplyTests.KeepsModuleOfOtherProfile;
var
  mOutcome: TUpdateOutcome;
begin
  FFake.Registry.WriteValue('Software\Embarcadero\Test\37.0\Known Packages',
    cTarget + '\Win32\Atlas.IDE.Debugger370.bpl', 'Atlas Debugger');
  mOutcome := Apply(TArray<string>.Create('Atlas.IDE.Base'));
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Installed, mOutcome.Kind);
  Assert.AreEqual('debugger 2.0.0', FFake.Files.ReadText(cTarget + '\Win32\Atlas.IDE.Debugger370.bpl'));
  Assert.IsFalse(FFake.Registry.Has(cKnown, cTarget + '\Win32\Atlas.IDE.Debugger370.bpl'));
  Assert.Contains(FFake.LogText, 'anderes Profil');
end;

procedure TCommonUpdatesApplyTests.WaitsForIde;
var
  mOutcome: TUpdateOutcome;
begin
  FFake.Processes.Run(4711, 'bds.exe', 3);
  mOutcome := Apply(nil);
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Installed, mOutcome.Kind);
  Assert.AreEqual(3, FFake.Processes.Sleeps);
  Assert.Contains(FFake.LogText, 'bds.exe (4711)');
end;

procedure TCommonUpdatesApplyTests.CancelsWhileWaiting;
var
  mOutcome: TUpdateOutcome;
begin
  FFake.Processes.Run(4711, 'bds.exe', 10);
  FFake.Processes.CancelAfter := 2;
  mOutcome := Apply(nil);
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Cancelled, mOutcome.Kind);
  Assert.AreEqual('server 2.0.0', FFake.Files.ReadText(cTarget + '\AtlasServer.exe'));
  Assert.IsFalse(FFake.Files.FileExists(cTarget + '\Win32\Atlas.IDE.Search370.bpl'));
end;

procedure TCommonUpdatesApplyTests.RollsBackOnError;
var
  mOutcome: TUpdateOutcome;
  mBefore: string;
begin
  mBefore := FFake.Registry.Dump(cKnown);
  // Die letzte Datei lässt sich nicht schreiben: alles davor wird zurückgenommen.
  FFake.Files.Damage(cTarget + '\Win32\Atlas.IDE.Search370.bpl');
  mOutcome := Apply(nil);
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.RolledBack, mOutcome.Kind);
  Assert.AreEqual(TUpdateErrors.cCopyFailed, mOutcome.Reason);
  Assert.AreEqual('server 2.0.0', FFake.Files.ReadText(cTarget + '\AtlasServer.exe'));
  Assert.AreEqual('base 2.0.0', FFake.Files.ReadText(cTarget + '\Win32\Atlas.IDE.Base370.bpl'));
  Assert.AreEqual(mBefore, FFake.Registry.Dump(cKnown));
  Assert.IsFalse(FFake.Files.FileExists(cRoot + '\declined.txt'));
end;

procedure TCommonUpdatesApplyTests.UpdatesOtherPlatformInPlace;
var
  mOutcome: TUpdateOutcome;
begin
  FFake.Files.WriteText(cFiles + '\Win64\Atlas.IDE.Base370.bpl', 'base64 2.0.1');
  FFake.Files.WriteText(cFiles + '\Win64\Atlas.IDE.Search370.bpl', 'search64 2.0.1');
  FFake.Files.WriteText(cTarget + '\Win64\Atlas.IDE.Base370.bpl', 'base64 2.0.0');
  mOutcome := Apply(nil);
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Installed, mOutcome.Kind);
  Assert.AreEqual('base64 2.0.1', FFake.Files.ReadText(cTarget + '\Win64\Atlas.IDE.Base370.bpl'));
  // Neue Module der anderen IDE bleiben ihrem eigenen Update überlassen.
  Assert.IsFalse(FFake.Files.FileExists(cTarget + '\Win64\Atlas.IDE.Search370.bpl'));
end;

end.
