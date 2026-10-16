unit Shell.SlashHost.Tests;

// Schnellbefehle laden nur in der Nachrichtenschleife neu (Code-Review A-03); WriteFiles ohne Editor
// schreibt auf die Platte (#297).

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
    [Test]
    procedure WriteFilesOnDisk;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
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

procedure TShellSlashHostTests.WriteFilesOnDisk;
var
  Host: TShellSlashHost;
  Ref: ISlashHost;
  Calls: Integer;
  Folder, NewFile, OldFile, Text: string;
  FileFormat: TFileFormat;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasSlashHost' + IntToStr(Random(1000000)));
  NewFile := TPath.Combine(TPath.Combine(Folder, 'Sub'), 'Neu.pas');
  OldFile := TPath.Combine(Folder, 'App.dpr');
  ForceDirectories(Folder);
  try
    TFileEncoding.SaveToFile(OldFile, 'program App;'#10'end.'#10, TFileFormat.Create(TFileEncodingKind.Utf8,
      TLineBreakStyle.LF));
    Calls := 0;
    Host := CreateHost(@Calls);
    Ref := Host;
    Host.WriteFiles('file:///x', [TSlashFile.Create(NewFile, 'unit Neu;'#13#10'end.'#13#10, True),
      TSlashFile.Create(OldFile, 'program App;'#10'uses Neu;'#10'end.'#10, False)], '');
    // Neue Datei: Ordner angelegt, UTF-8 mit BOM und CRLF; vorhandene behält ihr Format.
    Text := TFileEncoding.LoadFromFile(NewFile, FileFormat);
    Assert.AreEqual('unit Neu;'#13#10'end.'#13#10, Text);
    Assert.IsTrue(FileFormat.Encoding = TFileEncodingKind.Utf8Bom);
    Text := TFileEncoding.LoadFromFile(OldFile, FileFormat);
    Assert.AreEqual('program App;'#10'uses Neu;'#10'end.'#10, Text);
    Assert.IsTrue(FileFormat.Encoding = TFileEncodingKind.Utf8);
    // Danach neu geladen (ohne Schleife sofort).
    Assert.AreEqual(1, Calls);
  finally
    Ref := nil;
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSlashHostTests);

end.
