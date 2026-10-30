unit Shell.Hotspots.Tests;

// Hotspots mit echtem git und svn (#1354): Die Tests legen eine
// Git-Arbeitskopie bzw. ein SVN-Repository unter file:/// mit demselben
// Verlauf in einem temporären Ordner an (eine Unit wird umbenannt) und prüfen
// Stand, Verlauf samt Umbenennung, Methodenverlauf, Text in einem Stand und
// die Zahlen des Dienstes gegen git log. SVN muss dieselben Werte liefern
// wie Git. Fehlt git bzw. svn (oder svnadmin), endet der Test ohne Prüfung.
// Ohne Arbeitskopie meldet Detect den Grund, mit vcs.provider = off ebenso.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellHotspotsTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure DetectWithoutWorkingCopyGivesReason;
    [Test]
    procedure GitHistoryFollowsRenameAndMatchesGitLog;
    [Test]
    procedure SvnGivesSameValuesAsGit;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.History,
  Atlas.Common.Hotspots.Service,
  Shell.Platform,
  Shell.VcsChanges,
  Shell.Hotspots;

function Exec(const ARunner: IAtlasVcsRunner; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string): string;
var
  mAnswer: TAtlasVcsRunResult;
begin
  mAnswer := ARunner.Run(AExecutable, AArguments, AWorkingDir, 60000);
  if (mAnswer.Outcome <> TAtlasVcsOutcome.Ok) or (mAnswer.ExitCode <> 0) then
    raise Exception.CreateFmt('%s %s: Exit-Code %d', [ExtractFileName(AExecutable), string.Join(' ', AArguments),
      mAnswer.ExitCode]);
  Result := Trim(TEncoding.UTF8.GetString(mAnswer.Output));
end;

function NewFolder(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasHotspots-' + AName + '-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(Result);
end;

procedure RemoveFolder(const AFolder: string);
{$IFDEF MSWINDOWS}
var
  mFileName: string;
{$ENDIF}
begin
  if not TDirectory.Exists(AFolder) then
    Exit;
  {$IFDEF MSWINDOWS}
  // git und svn legen schreibgeschützte Dateien an.
  for mFileName in TDirectory.GetFiles(AFolder, '*', TSearchOption.soAllDirectories) do
  begin
    {$WARN SYMBOL_PLATFORM OFF}
    TFile.SetAttributes(mFileName, [TFileAttribute.faNormal]);
    {$WARN SYMBOL_PLATFORM ON}
  end;
  {$ENDIF}
  try
    TDirectory.Delete(AFolder, True);
  except
    on EInOutError do
      ;
    on EOSError do
      ;
  end;
end;

/// <summary>Unit mit einer Prozedur Rechne aus AIfs if-Anweisungen; ATag ändert eine Zeile darin.</summary>
function Source(const AName: string; AIfs: Integer; const ATag: string): string;
var
  mIndex: Integer;
begin
  Result := 'unit ' + AName + ';'#10#10'interface'#10#10'implementation'#10#10'procedure Rechne(A: Integer);'#10 +
    'begin'#10'  // ' + ATag + #10;
  for mIndex := 1 to AIfs do
    Result := Result + '  if A > ' + IntToStr(mIndex) + ' then'#10'    A := A - 1;'#10;
  Result := Result + 'end;'#10#10'end.'#10;
end;

procedure PutFile(const AFolder, APath, AText: string);
var
  mFileName: string;
begin
  // Pfade wie 'Src/Alt.pas': ExtractFileDir trennt unter Windows nur an '\'.
  mFileName := TPath.Combine(AFolder, APath.Replace('/', PathDelim));
  TDirectory.CreateDirectory(ExtractFileDir(mFileName));
  TFile.WriteAllText(mFileName, AText, TEncoding.ASCII);
end;

/// <summary>Einer der Schritte des gemeinsamen Verlaufs: 1 legt Alt und Andere an, 2 ändert Alt, 3 benennt Alt in
/// Neu um, 4 ändert Neu und Andere, 5 ändert Andere.</summary>
procedure WriteStep(const AFolder: string; AStep: Integer);
begin
  case AStep of
    1:
      begin
        PutFile(AFolder, 'Src/Alt.pas', Source('Alt', 2, 'eins'));
        PutFile(AFolder, 'Src/Andere.pas', Source('Andere', 1, 'eins'));
      end;
    2:
      PutFile(AFolder, 'Src/Alt.pas', Source('Alt', 3, 'zwei'));
    4:
      begin
        PutFile(AFolder, 'Src/Neu.pas', Source('Neu', 5, 'vier'));
        PutFile(AFolder, 'Src/Andere.pas', Source('Andere', 1, 'vier'));
      end;
    5:
      PutFile(AFolder, 'Src/Andere.pas', Source('Andere', 1, 'fünf'));
  end;
end;

function IndexOf(const AFolder: string): ISymbolIndex;
var
  mName: string;
begin
  Result := TSymbolIndex.Create;
  for mName in TArray<string>.Create('Src/Neu.pas', 'Src/Andere.pas') do
    Result.AddUnit(TIndexExtractor.ExtractText(TFile.ReadAllText(TPath.Combine(AFolder, mName)),
      TPath.Combine(AFolder, mName), nil, nil));
end;

function Analyze(const AFolder: string; const AVcs: IHotspotVcs): THotspotResult;
var
  mService: THotspotService;
  mRequest: THotspotRequest;
begin
  mService := THotspotService.Create(IndexOf(AFolder),
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TFile.Exists(AFileName);
      if Result then
        AText := TFile.ReadAllText(AFileName);
    end);
  try
    mRequest := THotspotRequest.FromSettings(TServerSettings.Default);
    mRequest.Root := AFolder;
    mRequest.Level := THotspotLevel.Methods;
    Result := mService.Analyze(mRequest, AVcs);
  finally
    mService.Free;
  end;
end;

function Find(const AEntries: TArray<THotspotEntry>; const AUnit: string): THotspotEntry;
var
  mEntry: THotspotEntry;
begin
  for mEntry in AEntries do
    if SameText(mEntry.UnitName, AUnit) then
      Exit(mEntry);
  Result := Default(THotspotEntry);
end;

{ TShellHotspotsTests }

procedure TShellHotspotsTests.WarmUpFirstUse;
begin
  try
    GitHistoryFollowsRenameAndMatchesGitLog;
  except
    on Exception do
      ;
  end;
end;

procedure TShellHotspotsTests.DetectWithoutWorkingCopyGivesReason;
var
  mFolder, mError: string;
  mVcs: IHotspotVcs;
  mSettings: TServerSettings;
begin
  mFolder := NewFolder('ohne');
  try
    Assert.IsFalse(TShellHotspotVcs.Detect(mFolder, TServerSettings.Default, mVcs, mError));
    Assert.IsNull(mVcs);
    Assert.IsTrue(mError.Contains('weder in einem Git-Repository noch in einer SVN-Arbeitskopie'), mError);
    mSettings := TServerSettings.Default;
    mSettings.VcsProvider := 'off';
    Assert.IsFalse(TShellHotspotVcs.Detect(mFolder, mSettings, mVcs, mError));
    Assert.IsTrue(mError.Contains('vcs.provider = off'), mError);
  finally
    RemoveFolder(mFolder);
  end;
end;

procedure TShellHotspotsTests.GitHistoryFollowsRenameAndMatchesGitLog;
var
  mGit, mFolder, mError, mText, mHead: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IHotspotVcs;
  mCommits: TArray<THotspotCommit>;
  mLines: TArray<THotspotLineCommit>;
  mResult: THotspotResult;
  mEntry: THotspotEntry;
  mStep, mFollowed: Integer;
begin
  mGit := TVcsChanges.ToolFor(TAtlasVcsKind.Git, '');
  // Ohne git keine Prüfung. Exit statt Assert.Pass: Der Leckmonitor zählte die Meldung als Leck.
  if mGit = '' then
    Exit;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mFolder := NewFolder('git');
  try
    Exec(mRunner, mGit, ['init', '-q'], mFolder);
    Exec(mRunner, mGit, ['config', 'user.name', 'Atlas Test'], mFolder);
    Exec(mRunner, mGit, ['config', 'user.email', 'test@example.org'], mFolder);
    Exec(mRunner, mGit, ['config', 'core.autocrlf', 'false'], mFolder);
    Exec(mRunner, mGit, ['config', 'commit.gpgsign', 'false'], mFolder);
    for mStep := 1 to 5 do
    begin
      if mStep = 3 then
        Exec(mRunner, mGit, ['mv', 'Src/Alt.pas', 'Src/Neu.pas'], mFolder)
      else
        WriteStep(mFolder, mStep);
      Exec(mRunner, mGit, ['add', '-A'], mFolder);
      Exec(mRunner, mGit, ['commit', '-q', '-m', 'Schritt ' + IntToStr(mStep)], mFolder);
    end;
    Assert.IsTrue(TShellHotspotVcs.Detect(TPath.Combine(mFolder, 'Src'), TServerSettings.Default, mVcs, mError),
      mError);
    Assert.IsTrue(mVcs.Kind = THotspotVcsKind.Git);
    Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(mFolder), mVcs.Root));
    mHead := mVcs.Head;
    Assert.AreEqual(Exec(mRunner, mGit, ['rev-parse', 'HEAD'], mFolder), mHead);
    Assert.IsTrue(mVcs.Log(IncDay(Now, -1), mCommits, mError), mError);
    Assert.AreEqual(5, Integer(Length(mCommits)));
    Assert.AreEqual('Schritt 5', mCommits[0].Summary, 'neueste zuerst');
    Assert.AreEqual('Atlas Test', mCommits[0].Author);
    Assert.IsTrue(mCommits[2].Files[0].Kind = THotspotChangeKind.Renamed, 'git mv');
    Assert.AreEqual('Src/Alt.pas', mCommits[2].Files[0].OldPath);

    // Wie git log --follow: Neu.pas hat vier Commits (drei davon unter dem alten Namen).
    mFollowed := Length(Exec(mRunner, mGit, ['log', '--follow', '--format=%H', '--', 'Src/Neu.pas'], mFolder)
      .Split([#10]));
    Assert.AreEqual(4, mFollowed);
    mResult := Analyze(mFolder, mVcs);
    mEntry := Find(mResult.Units, 'Neu');
    Assert.AreEqual(mFollowed, mEntry.Changes.Changes, 'Änderungen wie git log');
    Assert.AreEqual(3, Find(mResult.Units, 'Andere').Changes.Changes);
    Assert.AreEqual('Neu', mResult.Units[0].UnitName, 'oft geändert und am komplexesten');
    Assert.AreEqual(5, mEntry.Complexity);

    // Methodenebene über git log -L, auch über die Umbenennung.
    Assert.IsTrue(mVcs.LineLog(TPath.Combine(mFolder, 'Src/Neu.pas'), 7, 20, IncDay(Now, -1), mLines));
    Assert.IsTrue(Length(mLines) >= 3, IntToStr(Length(mLines)));
    Assert.AreEqual('Schritt 4', mLines[0].Summary);
    mEntry := Find(mResult.Methods, 'Neu');
    Assert.AreEqual('Rechne', mEntry.Method);
    Assert.AreEqual(Integer(Length(mLines)), mEntry.Changes.Changes);

    // Stand: heute gibt es Neu.pas, Fehlt.pas gab es nie, vor dem ersten Commit ist nichts bekannt.
    Assert.IsTrue(mVcs.TextAt('Src/Neu.pas', IncDay(Now, 1), mText) = THotspotTextState.Found);
    Assert.IsTrue(mText.Contains('// vier'));
    Assert.IsTrue(mVcs.TextAt('Src/Fehlt.pas', IncDay(Now, 1), mText) = THotspotTextState.Missing);
    Assert.IsTrue(mVcs.TextAt('Src/Neu.pas', IncDay(Now, -2), mText) = THotspotTextState.Unknown);
  finally
    mVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

procedure TShellHotspotsTests.SvnGivesSameValuesAsGit;
var
  mGit, mSvn, mSvnAdmin, mFolder, mGitFolder, mRepository, mUrl, mWorkingCopy, mError: string;
  mRunner: IAtlasVcsRunner;
  mGitVcs, mSvnVcs: IHotspotVcs;
  mStep, mIndex: Integer;
  mGitResult, mSvnResult: THotspotResult;
begin
  mGit := TVcsChanges.ToolFor(TAtlasVcsKind.Git, '');
  mSvn := TVcsChanges.ToolFor(TAtlasVcsKind.Svn, '');
  if (mGit = '') or (mSvn = '') then
    Exit;
  mSvnAdmin := TPath.Combine(ExtractFilePath(mSvn), 'svnadmin' + ExtractFileExt(mSvn));
  if not TFile.Exists(mSvnAdmin) then
    Exit;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mFolder := NewFolder('svn');
  try
    mGitFolder := TPath.Combine(mFolder, 'git');
    mRepository := TPath.Combine(mFolder, 'repo');
    mWorkingCopy := TPath.Combine(mFolder, 'wc');
    TDirectory.CreateDirectory(mGitFolder);
    Exec(mRunner, mGit, ['init', '-q'], mGitFolder);
    Exec(mRunner, mGit, ['config', 'user.name', 'atlas'], mGitFolder);
    Exec(mRunner, mGit, ['config', 'user.email', 'test@example.org'], mGitFolder);
    Exec(mRunner, mGit, ['config', 'core.autocrlf', 'false'], mGitFolder);
    Exec(mRunner, mGit, ['config', 'commit.gpgsign', 'false'], mGitFolder);
    Exec(mRunner, mSvnAdmin, ['create', mRepository], mFolder);
    mUrl := 'file:///' + StringReplace(mRepository, '\', '/', [rfReplaceAll]);
    if mUrl.StartsWith('file:////') then
      mUrl := 'file://' + Copy(mUrl, 9, MaxInt);
    Exec(mRunner, mSvn, ['mkdir', '-q', '-m', 'Ablage', mUrl + '/trunk', '--non-interactive', '--username', 'atlas'],
      mFolder);
    Exec(mRunner, mSvn, ['checkout', '-q', mUrl + '/trunk', mWorkingCopy, '--non-interactive'], mFolder);
    // Gleich aufgebaute Verläufe: dieselben Schritte in beiden.
    for mStep := 1 to 5 do
    begin
      if mStep = 3 then
      begin
        Exec(mRunner, mGit, ['mv', 'Src/Alt.pas', 'Src/Neu.pas'], mGitFolder);
        Exec(mRunner, mSvn, ['move', '-q', 'Src/Alt.pas', 'Src/Neu.pas'], mWorkingCopy);
      end
      else
      begin
        WriteStep(mGitFolder, mStep);
        WriteStep(mWorkingCopy, mStep);
        if mStep = 1 then
          Exec(mRunner, mSvn, ['add', '-q', 'Src'], mWorkingCopy);
      end;
      Exec(mRunner, mGit, ['add', '-A'], mGitFolder);
      Exec(mRunner, mGit, ['commit', '-q', '-m', 'Schritt ' + IntToStr(mStep)], mGitFolder);
      Exec(mRunner, mSvn, ['commit', '-q', '-m', 'Schritt ' + IntToStr(mStep), '--non-interactive', '--username',
        'atlas'], mWorkingCopy);
    end;
    Exec(mRunner, mSvn, ['update', '-q', '--non-interactive'], mWorkingCopy);
    Assert.IsTrue(TShellHotspotVcs.Detect(mGitFolder, TServerSettings.Default, mGitVcs, mError), mError);
    Assert.IsTrue(TShellHotspotVcs.Detect(mWorkingCopy, TServerSettings.Default, mSvnVcs, mError), mError);
    Assert.IsTrue(mSvnVcs.Kind = THotspotVcsKind.Svn);
    Assert.AreEqual('6', mSvnVcs.Head, 'Ablage = r1, fünf Schritte');
    mGitResult := Analyze(mGitFolder, mGitVcs);
    mSvnResult := Analyze(mWorkingCopy, mSvnVcs);
    Assert.AreEqual(5, mSvnResult.Commits);
    Assert.AreEqual(Integer(Length(mGitResult.Units)), Integer(Length(mSvnResult.Units)));
    for mIndex := 0 to High(mGitResult.Units) do
    begin
      Assert.AreEqual(mGitResult.Units[mIndex].UnitName, mSvnResult.Units[mIndex].UnitName);
      Assert.AreEqual(mGitResult.Units[mIndex].Changes.Changes, mSvnResult.Units[mIndex].Changes.Changes,
        mGitResult.Units[mIndex].UnitName);
      Assert.AreEqual(Integer(Length(mGitResult.Units[mIndex].Changes.Authors)),
        Integer(Length(mSvnResult.Units[mIndex].Changes.Authors)));
      Assert.AreEqual(mGitResult.Units[mIndex].Complexity, mSvnResult.Units[mIndex].Complexity);
      Assert.AreEqual(mGitResult.Units[mIndex].Score, mSvnResult.Units[mIndex].Score, 1E-9);
    end;
    Assert.AreEqual(Integer(Length(mGitResult.Methods)), Integer(Length(mSvnResult.Methods)));
    for mIndex := 0 to High(mGitResult.Methods) do
      Assert.AreEqual(mGitResult.Methods[mIndex].Changes.Changes, mSvnResult.Methods[mIndex].Changes.Changes,
        mGitResult.Methods[mIndex].UnitName);
    Assert.AreEqual(Integer(Length(mGitResult.Coupling)), Integer(Length(mSvnResult.Coupling)));
  finally
    mGitVcs := nil;
    mSvnVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellHotspotsTests);

end.
