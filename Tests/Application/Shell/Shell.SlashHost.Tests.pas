unit Shell.SlashHost.Tests;

// Schnellbefehle laden nur in der Nachrichtenschleife neu (Code-Review A-03).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellSlashHostTests = class
  public
    [Test]
    procedure SelectBuildRunsThroughLoopRunner;
    [Test]
    procedure WithoutLoopRunnerRunsImmediately;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Editing.SlashCommands,
  Shell.Workspace,
  Shell.SlashHost;

/// <summary>Host ohne Ordner; ACalls zählt die Aufrufe von WorkspaceOf.</summary>
function CreateHost(const ACalls: PInteger): TShellSlashHost;
var
  Calls: PInteger;
begin
  Calls := ACalls;
  Result := TShellSlashHost.Create(
    function(const AUri: string): TShellWorkspace
    begin
      Inc(Calls^);
      Result := nil;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end,
    function(const AUri: string): string
    begin
      Result := '';
    end,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create);
end;

{ TShellSlashHostTests }

procedure TShellSlashHostTests.SelectBuildRunsThroughLoopRunner;
var
  Host: TShellSlashHost;
  Ref: ISlashHost;
  Calls: Integer;
  Queued: TList<TProc>;
begin
  Calls := 0;
  Queued := TList<TProc>.Create;
  try
    Host := CreateHost(@Calls);
    Ref := Host;
    Host.RunInLoop :=
      procedure(const AWork: TProc)
      begin
        Queued.Add(AWork);
      end;
    Host.SelectBuild('file:///C:/P/A.pas', 'Release', 'Win64');
    // Noch nichts im Worker: Erst die Schleife sucht den Ordner und lädt neu.
    Assert.AreEqual(0, Calls);
    Assert.AreEqual(1, Integer(Queued.Count));
    Queued[0]();
    Assert.AreEqual(1, Calls);
  finally
    Ref := nil;
    Queued.Free;
  end;
end;

procedure TShellSlashHostTests.WithoutLoopRunnerRunsImmediately;
var
  Host: TShellSlashHost;
  Ref: ISlashHost;
  Calls: Integer;
begin
  Calls := 0;
  Host := CreateHost(@Calls);
  Ref := Host;
  Host.SelectBuild('file:///C:/P/A.pas', 'Release', 'Win64');
  Assert.AreEqual(1, Calls);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSlashHostTests);

end.
