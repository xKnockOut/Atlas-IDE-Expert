unit Shell.Composition.Compile.Tests;

// Compilerläufe des Servers (#40, #186, #261): Workspace Trust, fehlendes Projekt, Merken des Grunds bis zum
// nächsten Laden und der Status ohne Lauf.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Compile;

type
  [TestFixture]
  TShellCompileHostTests = class
  private
    FCalls: Integer;
    FHost: TShellCompileHost;
    procedure CreateHost(const AError: string);
  public
    [TearDown]
    procedure TearDown;
    /// <summary>Im nicht vertrauenswürdigen Arbeitsbereich startet kein Lauf, auch nicht auf den Befehl.</summary>
    [Test]
    procedure RestrictedNeverCompiles;
    /// <summary>Ohne Projekt nennt der Befehl den Grund; nach dem Speichern wird bis zum nächsten Laden nicht
    /// erneut gesucht.</summary>
    [Test]
    procedure MissingProjectIsRemembered;
    [Test]
    procedure StatusWithoutProjectIsUnchecked;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Compiler.Backend,
  Atlas.Common.Lsp.Status,
  Shell.Compiler;

procedure TShellCompileHostTests.CreateHost(const AError: string);
var
  mServices: TShellCompileServices;
  mError: string;
begin
  mError := AError;
  mServices := Default(TShellCompileServices);
  mServices.Logger := TLogger.Create;
  mServices.JobFor :=
    function(const AFileName: string; out AJob: TShellCompileJob; out AErrorText: string): Boolean
    begin
      Inc(FCalls);
      AJob := Default(TShellCompileJob);
      AErrorText := mError;
      Result := mError = '';
    end;
  mServices.Publish :=
    procedure(const AFiles: TArray<string>)
    begin
    end;
  FHost := TShellCompileHost.Create(mServices);
end;

procedure TShellCompileHostTests.TearDown;
begin
  if FHost <> nil then
  begin
    FHost.Stop;
  end;
  FreeAndNil(FHost);
  FCalls := 0;
end;

procedure TShellCompileHostTests.RestrictedNeverCompiles;
var
  mChoice: TCompilerBackendChoice;
  mStatus: TServerStatus;
begin
  CreateHost('');
  FHost.Restricted := True;
  Assert.IsFalse(FHost.Start('', True, mChoice));
  Assert.IsFalse(mChoice.Usable);
  Assert.AreEqual(0, FCalls, 'kein Projekt gesucht');
  mStatus := Default(TServerStatus);
  FHost.StatusOf(mStatus);
  Assert.AreEqual(0, FCalls);
  Assert.IsTrue(mStatus.Compiler <> TCompilerBackends.UncheckedStatus);
end;

procedure TShellCompileHostTests.MissingProjectIsRemembered;
var
  mChoice: TCompilerBackendChoice;
begin
  CreateHost('Kein Ordner mit Projekt geöffnet');
  Assert.IsFalse(FHost.Start('', True, mChoice));
  Assert.AreEqual('Kein Ordner mit Projekt geöffnet', mChoice.Reason);
  Assert.AreEqual(1, FCalls);
  Assert.IsFalse(FHost.Start('A.pas', False, mChoice), 'nach dem Speichern');
  Assert.AreEqual(1, FCalls, 'bis zum nächsten Laden nicht erneut');
  Assert.AreEqual('Kein Ordner mit Projekt geöffnet', mChoice.Reason);
  FHost.Reset;
  Assert.IsFalse(FHost.Start('A.pas', False, mChoice));
  Assert.AreEqual(2, FCalls, 'nach dem Laden neue Chance');
end;

procedure TShellCompileHostTests.StatusWithoutProjectIsUnchecked;
var
  mStatus: TServerStatus;
begin
  CreateHost('Kein Ordner mit Projekt geöffnet');
  mStatus := Default(TServerStatus);
  FHost.StatusOf(mStatus);
  Assert.AreEqual(TCompilerBackends.UncheckedStatus, mStatus.Compiler);
  Assert.AreEqual(1, FCalls);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCompileHostTests);

end.
