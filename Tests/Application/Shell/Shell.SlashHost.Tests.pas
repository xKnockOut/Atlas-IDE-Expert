unit Shell.SlashHost.Tests;

// Schnellbefehle laden nur in der Nachrichtenschleife neu; WriteFiles ohne Editor
// schreibt auf die Platte (#297).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellSlashHostTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure SelectBuildRunsThroughLoopRunner;
    [Test]
    procedure WithoutLoopRunnerRunsImmediately;
    [Test]
    procedure WriteFilesOnDisk;
    [Test]
    procedure NewFileFollowsCommandFile;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Editing.Contract,
  Shell.Workspace,
  Shell.SlashHost;

/// <summary>Host ohne Ordner; ACalls zählt die Aufrufe von WorkspaceOf.</summary>
function CreateHost(const ACalls: PInteger): TShellSlashHost;
var
  mCalls: PInteger;
begin
  mCalls := ACalls;
  Result := TShellSlashHost.Create(TShellSlashSources.New(
    function(const AUri: string): TShellWorkspace
    begin
      Inc(mCalls^);
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
    end),
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create);
end;

{ TShellSlashHostTests }

procedure TShellSlashHostTests.WarmUpFirstUse;
begin
  WriteFilesOnDisk;
end;

procedure TShellSlashHostTests.SelectBuildRunsThroughLoopRunner;
var
  mHost: TShellSlashHost;
  mRef: ISlashHost;
  mCalls: Integer;
  mQueued: TList<TProc>;
begin
  mCalls := 0;
  mQueued := TList<TProc>.Create;
  try
    mHost := CreateHost(@mCalls);
    mRef := mHost;
    mHost.RunInLoop :=
      procedure(const AWork: TProc)
      begin
        mQueued.Add(AWork);
      end;
    mHost.SelectBuild('file:///C:/P/A.pas', 'Release', 'Win64');
    // Noch nichts im Worker: Erst die Schleife sucht den Ordner und lädt neu.
    Assert.AreEqual(0, mCalls);
    Assert.AreEqual(1, Integer(mQueued.Count));
    mQueued[0]();
    Assert.AreEqual(1, mCalls);
  finally
    mRef := nil;
    mQueued.Free;
  end;
end;

procedure TShellSlashHostTests.WithoutLoopRunnerRunsImmediately;
var
  mHost: TShellSlashHost;
  mRef: ISlashHost;
  mCalls: Integer;
begin
  mCalls := 0;
  mHost := CreateHost(@mCalls);
  mRef := mHost;
  mHost.SelectBuild('file:///C:/P/A.pas', 'Release', 'Win64');
  Assert.AreEqual(1, mCalls);
end;

procedure TShellSlashHostTests.WriteFilesOnDisk;
var
  mHost: TShellSlashHost;
  mRef: ISlashHost;
  mCalls: Integer;
  mFolder, mNewFile, mOldFile, mText: string;
  mFileFormat: TFileFormat;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasSlashHost' + IntToStr(Random(1000000)));
  mNewFile := TPath.Combine(TPath.Combine(mFolder, 'Sub'), 'Neu.pas');
  mOldFile := TPath.Combine(mFolder, 'App.dpr');
  ForceDirectories(mFolder);
  try
    TFileEncoding.SaveToFile(mOldFile, 'program App;'#10'end.'#10, TFileFormat.Create(TFileEncodingKind.Utf8,
      TLineBreakStyle.LF));
    mCalls := 0;
    mHost := CreateHost(@mCalls);
    mRef := mHost;
    mHost.WriteFiles('file:///x', [TSlashFile.Create(mNewFile, 'unit Neu;'#13#10'end.'#13#10, True),
      TSlashFile.Create(mOldFile, 'program App;'#10'uses Neu;'#10'end.'#10, False)], '');
    // Neue Datei: Ordner angelegt, UTF-8 mit BOM und CRLF; vorhandene behält ihr Format.
    mText := TFileEncoding.LoadFromFile(mNewFile, mFileFormat);
    Assert.AreEqual('unit Neu;'#13#10'end.'#13#10, mText);
    Assert.IsTrue(mFileFormat.Encoding = TFileEncodingKind.Utf8Bom);
    mText := TFileEncoding.LoadFromFile(mOldFile, mFileFormat);
    Assert.AreEqual('program App;'#10'uses Neu;'#10'end.'#10, mText);
    Assert.IsTrue(mFileFormat.Encoding = TFileEncodingKind.Utf8);
    // Danach neu geladen (ohne Schleife sofort).
    Assert.AreEqual(1, mCalls);
  finally
    mRef := nil;
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TShellSlashHostTests.NewFileFollowsCommandFile;
var
  mHost: TShellSlashHost;
  mRef: ISlashHost;
  mCalls: Integer;
  mFolder, mNewFile, mMainFile, mText: string;
  mFileFormat: TFileFormat;
begin
  // #299 (#121): Die neue Unit übernimmt die Kodierung der Datei, in der der Befehl stand.
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasSlashHost' + IntToStr(Random(1000000)));
  mNewFile := TPath.Combine(mFolder, 'Zaehler.pas');
  mMainFile := TPath.Combine(mFolder, 'Main.pas');
  ForceDirectories(mFolder);
  try
    TFileEncoding.SaveToFile(mMainFile, 'unit Main;'#10'end.'#10, TFileFormat.Create(TFileEncodingKind.Utf8,
      TLineBreakStyle.LF));
    mCalls := 0;
    mHost := CreateHost(@mCalls);
    mRef := mHost;
    mHost.WriteFiles(TDocumentUris.FromPath(mMainFile), [TSlashFile.Create(mNewFile, 'unit Zaehler;'#10'end.'#10,
      True)], '');
    mText := TFileEncoding.LoadFromFile(mNewFile, mFileFormat);
    Assert.AreEqual('unit Zaehler;'#10'end.'#10, mText);
    Assert.IsTrue(mFileFormat.Encoding = TFileEncodingKind.Utf8);
    Assert.IsTrue(mFileFormat.LineBreak = TLineBreakStyle.LF);
  finally
    mRef := nil;
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSlashHostTests);

end.
