unit Atlas.Core.Tests.AffectedHook.Tests;

// Tests für den pre-commit-Hook der betroffenen Tests (#1353): Skript, Angaben, fremder Hook bleibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasAffectedHookTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ScriptAsksServerAndOnlyBlocksOnRequest;
    [Test]
    procedure ConfigUsesForwardSlashes;
    [Test]
    procedure InstallWritesConfigAndKeepsForeignHook;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Tests.AffectedHook;

function Config: TAtlasAffectedHookConfig;
begin
  Result := Default(TAtlasAffectedHookConfig);
  Result.ServerPath := 'C:\Atlas\AtlasServer.exe';
  Result.Project := 'C:\Repo\Tests\Tests.dproj';
  Result.Executable := 'C:\Repo\Tests\Win64\Debug\Tests.exe';
end;

procedure TAtlasAffectedHookTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'atlas-affected-' + IntToStr(Random(1000000)));
  ForceDirectories(FDir);
end;

procedure TAtlasAffectedHookTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
  FDir := '';
end;

procedure TAtlasAffectedHookTests.ScriptAsksServerAndOnlyBlocksOnRequest;
var
  mScript: string;
begin
  mScript := TAtlasAffectedHook.Script;
  Assert.IsTrue(mScript.StartsWith('#!/bin/sh' + #10 + TAtlasAffectedHook.Marker + #10));
  Assert.AreEqual(0, Pos(#13, mScript), 'sh verträgt kein CR');
  Assert.IsTrue(Pos('--affected-tests HEAD --include-uncommitted --format dunitx', mScript) > 0);
  // Ohne Terminal nur die Liste; der Commit scheitert nur nach Fehlschlag und „nein“.
  Assert.IsTrue(Pos('( : < /dev/tty ) 2>/dev/null || exit 0', mScript) > 0);
  Assert.IsTrue(Pos('exit 1', mScript) > 0);
  Assert.AreEqual(Pos('exit 1', mScript), mScript.LastIndexOf('exit 1') + 1, 'nur ein Abbruch');
  Assert.IsTrue(TAtlasAffectedHook.IsOwn(mScript));
  Assert.IsFalse(TAtlasAffectedHook.IsOwn('#!/bin/sh' + #10 + 'npx lint-staged'));
end;

procedure TAtlasAffectedHookTests.ConfigUsesForwardSlashes;
begin
  Assert.AreEqual('C:/Atlas/AtlasServer.exe'#10'C:/Repo/Tests/Tests.dproj'#10'C:/Repo/Tests/Win64/Debug/Tests.exe'#10,
    TAtlasAffectedHook.ConfigText(Config));
end;

procedure TAtlasAffectedHookTests.InstallWritesConfigAndKeepsForeignHook;
var
  mHooks: string;
begin
  mHooks := TPath.Combine(FDir, 'hooks');
  Assert.IsTrue(TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Missing);
  Assert.IsTrue(TAtlasAffectedHook.Install(mHooks, FDir, Config), 'legt Ordner, Hook und Angaben an');
  Assert.IsTrue(TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Own);
  Assert.AreEqual(TAtlasAffectedHook.ConfigText(Config), TFile.ReadAllText(TAtlasAffectedHook.ConfigFileOf(FDir), TEncoding.UTF8));
  Assert.IsTrue(TAtlasAffectedHook.Install(mHooks, FDir, Config), 'eigener wird ersetzt');
  Assert.IsTrue(TAtlasAffectedHook.Uninstall(mHooks, FDir));
  Assert.IsTrue(TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Missing);
  Assert.IsFalse(FileExists(TAtlasAffectedHook.ConfigFileOf(FDir)), 'Angaben mit entfernt');
  TFile.WriteAllText(TAtlasAffectedHook.HookFile(mHooks), '#!/bin/sh' + #10 + 'echo fremd' + #10);
  Assert.IsTrue(TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Foreign);
  Assert.IsFalse(TAtlasAffectedHook.Install(mHooks, FDir, Config), 'fremder Hook bleibt');
  Assert.IsFalse(FileExists(TAtlasAffectedHook.ConfigFileOf(FDir)), 'ohne eigenen Hook keine Angaben');
  Assert.IsTrue(TAtlasAffectedHook.Uninstall(mHooks, FDir));
  Assert.IsTrue(Pos('echo fremd', TFile.ReadAllText(TAtlasAffectedHook.HookFile(mHooks), TEncoding.UTF8)) > 0);
  Assert.IsFalse(TAtlasAffectedHook.Install('', FDir, Config));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAffectedHookTests);

end.
