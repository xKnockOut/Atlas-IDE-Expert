unit Atlas.Core.Diagnostics.Edition.Tests;

// Kommandozeilen-Compiler der IDE (#1822): Suche unter bin und bin64, unbekannter Ordner, Programme, die einen
// Compiler brauchen, und wann der einmalige Hinweis kommt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditionTests = class
  public
    [Test]
    procedure FindsBothCompilers;
    [Test]
    procedure FindsDcc64InBin64;
    [Test]
    procedure StarterHasNone;
    [Test]
    procedure UnknownFolderCountsAsPresent;
    [Test]
    procedure RecognizesCompilerPrograms;
    [Test]
    procedure OtherProgramsNeedNoCompiler;
    [Test]
    procedure NotifiesOnceWhenMissing;
    [Test]
    procedure SwitchedOffNeverMissing;
    [Test]
    procedure LogTextNamesResult;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Edition;

const
  cRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

function Files(const ANames: array of string): TAtlasFileExistsFunc;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mNames, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    mNames[mIndex] := ANames[mIndex];
  end;
  Result :=
    function(const AFileName: string): Boolean
    var
      mName: string;
    begin
      for mName in mNames do
      begin
        if SameText(mName, AFileName) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

procedure TAtlasEditionTests.FindsBothCompilers;
var
  mTools: TAtlasCompilerTools;
begin
  mTools := TAtlasEdition.Detect(cRoot, Files([cRoot + '\bin\dcc32.exe', cRoot + '\bin\dcc64.exe']));
  Assert.IsTrue(mTools.Checked);
  Assert.IsTrue(mTools.Dcc32);
  Assert.IsTrue(mTools.Dcc64);
  Assert.IsTrue(mTools.CommandLine);
end;

procedure TAtlasEditionTests.FindsDcc64InBin64;
var
  mTools: TAtlasCompilerTools;
begin
  mTools := TAtlasEdition.Detect(cRoot + '\', Files([cRoot + '\bin64\dcc64.exe']));
  Assert.IsFalse(mTools.Dcc32);
  Assert.IsTrue(mTools.Dcc64, 'abschließender Trenner und bin64');
  Assert.IsTrue(mTools.CommandLine);
end;

procedure TAtlasEditionTests.StarterHasNone;
var
  mTools: TAtlasCompilerTools;
begin
  mTools := TAtlasEdition.Detect(cRoot, Files([cRoot + '\bin\bds.exe']));
  Assert.IsTrue(mTools.Checked);
  Assert.IsFalse(mTools.CommandLine);
  Assert.IsTrue(TAtlasEdition.Missing(mTools, True));
end;

procedure TAtlasEditionTests.UnknownFolderCountsAsPresent;
var
  mTools: TAtlasCompilerTools;
begin
  mTools := TAtlasEdition.Detect('', Files([]));
  Assert.IsFalse(mTools.Checked);
  Assert.IsTrue(mTools.CommandLine, 'ohne Ordner kein Fehlalarm');
  Assert.IsFalse(TAtlasEdition.Missing(mTools, True));
  mTools := TAtlasEdition.Detect(cRoot, nil);
  Assert.IsFalse(mTools.Checked);
end;

procedure TAtlasEditionTests.RecognizesCompilerPrograms;
begin
  Assert.IsTrue(TAtlasEdition.NeedsCommandLine('dcc32'));
  Assert.IsTrue(TAtlasEdition.NeedsCommandLine('DCC64.EXE'));
  Assert.IsTrue(TAtlasEdition.NeedsCommandLine('${bds}\bin\dcc32.exe'));
  Assert.IsTrue(TAtlasEdition.NeedsCommandLine('"C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"'));
  Assert.IsTrue(TAtlasEdition.NeedsCommandLine('msbuild'));
  Assert.IsTrue(TAtlasEdition.NeedsCommandLine('/usr/bin/dcclinux64'));
end;

procedure TAtlasEditionTests.OtherProgramsNeedNoCompiler;
begin
  Assert.IsFalse(TAtlasEdition.NeedsCommandLine('pwsh'));
  Assert.IsFalse(TAtlasEdition.NeedsCommandLine('AtlasServer.exe'));
  Assert.IsFalse(TAtlasEdition.NeedsCommandLine('mydcc32wrapper.cmd'));
  Assert.IsFalse(TAtlasEdition.NeedsCommandLine(''));
end;

procedure TAtlasEditionTests.NotifiesOnceWhenMissing;
var
  mTools: TAtlasCompilerTools;
begin
  mTools := TAtlasEdition.Detect(cRoot, Files([]));
  Assert.IsTrue(TAtlasEdition.ShouldNotify(mTools, True, False));
  Assert.IsFalse(TAtlasEdition.ShouldNotify(mTools, True, True), 'schon gezeigt');
  mTools := TAtlasEdition.Detect(cRoot, Files([cRoot + '\bin\dcc32.exe']));
  Assert.IsFalse(TAtlasEdition.ShouldNotify(mTools, True, False), 'Professional');
end;

procedure TAtlasEditionTests.SwitchedOffNeverMissing;
var
  mTools: TAtlasCompilerTools;
begin
  mTools := TAtlasEdition.Detect(cRoot, Files([]));
  Assert.IsFalse(TAtlasEdition.Missing(mTools, False));
  Assert.IsFalse(TAtlasEdition.ShouldNotify(mTools, False, False));
end;

procedure TAtlasEditionTests.LogTextNamesResult;
begin
  Assert.AreEqual('command-line compiler: dcc32, dcc64',
    TAtlasEdition.Detect(cRoot, Files([cRoot + '\bin\dcc32.exe', cRoot + '\bin\dcc64.exe'])).LogText);
  Assert.Contains(TAtlasEdition.Detect(cRoot, Files([])).LogText, 'none');
  Assert.AreEqual('command-line compiler: not checked', TAtlasEdition.Detect('', Files([])).LogText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditionTests);

end.
