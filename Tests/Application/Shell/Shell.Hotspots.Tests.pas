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
  Atlas.Core.VersionControl.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Service,
  Shell.Platform,
  Shell.VersionControlChanges,
  Shell.Hotspots;

function Exec(const ARunner: IAtlasVcsRunner; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string): string;
var
  mAnswer: TAtlasVcsRunResult;
begin
  mAnswer := ARunner.Run(AExecutable, AArguments, AWorkingDir, 60000);
  if (mAnswer.Outcome <> TAtlasVcsOutcome.Ok) or (mAnswer.ExitCode <> 0) then
  begin
    raise Exception.CreateFmt('%s %s: Exit-Code %d', [ExtractFileName(AExecutable), string.Join(' ', AArguments),
      mAnswer.ExitCode]);
  end;
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
  begin
    Exit;
  end;
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
  begin
    Result := Result + '  if A > ' + IntToStr(mIndex) + ' then'#10'    A := A - 1;'#10;
  end;
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
  begin
    Result.AddUnit(TIndexExtractor.ExtractText(TFile.ReadAllText(TPath.Combine(AFolder, mName), TEncoding.UTF8),
      TPath.Combine(AFolder, mName), nil, nil));
  end;
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
      begin
        AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
      end;
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
  begin
    if SameText(mEntry.UnitName, AUnit) then
    begin
      Exit(mEntry);
    end;
  end;
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

/// <summary>Legt in AFolder ein Git-Repository für den Benutzer AUser an (ohne CRLF-Umwandlung und Signatur).
/// </summary>
procedure InitGit(const ARunner: IAtlasVcsRunner; const AGit, AFolder, AUser: string);
begin
  Exec(ARunner, AGit, ['init', '-q'], AFolder);
  Exec(ARunner, AGit, ['config', 'user.name', AUser], AFolder);
  Exec(ARunner, AGit, ['config', 'user.email', 'test@example.org'], AFolder);
  Exec(ARunner, AGit, ['config', 'core.autocrlf', 'false'], AFolder);
  Exec(ARunner, AGit, ['config', 'commit.gpgsign', 'false'], AFolder);
end;

/// <summary>Fünf Commits in AFolder; im dritten wird Src/Alt.pas zu Src/Neu.pas.</summary>
procedure CommitGitSteps(const ARunner: IAtlasVcsRunner; const AGit, AFolder: string);
var
  mStep: Integer;
begin
  for mStep := 1 to 5 do
  begin
    if mStep = 3 then
    begin
      Exec(ARunner, AGit, ['mv', 'Src/Alt.pas', 'Src/Neu.pas'], AFolder);
    end
    else
    begin
      WriteStep(AFolder, mStep);
    end;
    Exec(ARunner, AGit, ['add', '-A'], AFolder);
    Exec(ARunner, AGit, ['commit', '-q', '-m', 'Schritt ' + IntToStr(mStep)], AFolder);
  end;
end;

/// <summary>Kopf und Verlauf von AVcs wie git rev-parse und git log.</summary>
procedure AssertGitHistory(const AVcs: IHotspotVcs; const ARunner: IAtlasVcsRunner; const AGit, AFolder: string);
var
  mCommits: TArray<THotspotCommit>;
  mError, mHead: string;
begin
  Assert.AreEqual<THotspotVcsKind>(THotspotVcsKind.Git, AVcs.Kind);
  Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(AFolder), AVcs.Root));
  mHead := AVcs.Head;
  Assert.AreEqual(Exec(ARunner, AGit, ['rev-parse', 'HEAD'], AFolder), mHead);
  Assert.IsTrue(AVcs.Log(IncDay(Now, -1), mCommits, mError), mError);
  Assert.AreEqual(5, Integer(Length(mCommits)));
  Assert.AreEqual('Schritt 5', mCommits[0].Summary, 'neueste zuerst');
  Assert.AreEqual('Atlas Test', mCommits[0].Author);
  Assert.AreEqual<THotspotChangeKind>(THotspotChangeKind.Renamed, mCommits[2].Files[0].Kind, 'git mv');
  Assert.AreEqual('Src/Alt.pas', mCommits[2].Files[0].OldPath);
end;

/// <summary>Methodenebene über git log -L, auch über die Umbenennung.</summary>
procedure AssertLineHistory(const AVcs: IHotspotVcs; const AFolder: string; const AResult: THotspotResult);
var
  mLines: TArray<THotspotLineCommit>;
  mEntry: THotspotEntry;
begin
  Assert.IsTrue(AVcs.LineLog(TPath.Combine(AFolder, 'Src/Neu.pas'), 7, 20, IncDay(Now, -1), mLines));
  Assert.IsTrue(Length(mLines) >= 3, IntToStr(Length(mLines)));
  Assert.AreEqual('Schritt 4', mLines[0].Summary);
  mEntry := Find(AResult.Methods, 'Neu');
  Assert.AreEqual('Rechne', mEntry.Method);
  Assert.AreEqual(Integer(Length(mLines)), mEntry.Changes.Changes);
end;

/// <summary>Stand: heute gibt es Neu.pas, Fehlt.pas gab es nie, vor dem ersten Commit ist nichts bekannt.</summary>
procedure AssertTextStates(const AVcs: IHotspotVcs);
var
  mText: string;
begin
  Assert.AreEqual<THotspotTextState>(THotspotTextState.Found, AVcs.TextAt('Src/Neu.pas', IncDay(Now, 1), mText));
  Assert.IsTrue(mText.Contains('// vier'));
  Assert.AreEqual<THotspotTextState>(THotspotTextState.Missing, AVcs.TextAt('Src/Fehlt.pas', IncDay(Now, 1), mText));
  Assert.AreEqual<THotspotTextState>(THotspotTextState.Unknown, AVcs.TextAt('Src/Neu.pas', IncDay(Now, -2), mText));
end;

procedure TShellHotspotsTests.GitHistoryFollowsRenameAndMatchesGitLog;
var
  mGit, mFolder, mError: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IHotspotVcs;
  mResult: THotspotResult;
  mEntry: THotspotEntry;
  mFollowed: Integer;
begin
  mGit := TVcsChanges.ToolFor(TAtlasVcsKind.Git, '');
  // Ohne git keine Prüfung. Exit statt Assert.Pass: Der Leckmonitor zählte die Meldung als Leck.
  if mGit = '' then
  begin
    Exit;
  end;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mFolder := NewFolder('git');
  try
    InitGit(mRunner, mGit, mFolder, 'Atlas Test');
    CommitGitSteps(mRunner, mGit, mFolder);
    Assert.IsTrue(TShellHotspotVcs.Detect(TPath.Combine(mFolder, 'Src'), TServerSettings.Default, mVcs, mError),
      mError);
    AssertGitHistory(mVcs, mRunner, mGit, mFolder);

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
    AssertLineHistory(mVcs, mFolder, mResult);
    AssertTextStates(mVcs);
  finally
    mVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

/// <summary>git, svn und svnadmin; False, wenn eines fehlt.</summary>
function SvnTools(out AGit, ASvn, ASvnAdmin: string): Boolean;
begin
  AGit := TVcsChanges.ToolFor(TAtlasVcsKind.Git, '');
  ASvn := TVcsChanges.ToolFor(TAtlasVcsKind.Svn, '');
  ASvnAdmin := '';
  Result := (AGit <> '') and (ASvn <> '');
  if Result then
  begin
    ASvnAdmin := TPath.Combine(ExtractFilePath(ASvn), 'svnadmin' + ExtractFileExt(ASvn));
    Result := TFile.Exists(ASvnAdmin);
  end;
end;

/// <summary>Legt die SVN-Ablage ARepository mit trunk an und checkt trunk nach AWorkingCopy aus.</summary>
procedure CreateSvnWorkingCopy(const ARunner: IAtlasVcsRunner; const ASvn, ASvnAdmin, AFolder, ARepository,
  AWorkingCopy: string);
var
  mUrl: string;
begin
  Exec(ARunner, ASvnAdmin, ['create', ARepository], AFolder);
  mUrl := 'file:///' + StringReplace(ARepository, '\', '/', [rfReplaceAll]);
  if mUrl.StartsWith('file:////') then
  begin
    mUrl := 'file://' + Copy(mUrl, 9, MaxInt);
  end;
  Exec(ARunner, ASvn, ['mkdir', '-q', '-m', 'Ablage', mUrl + '/trunk', '--non-interactive', '--username', 'atlas'],
    AFolder);
  Exec(ARunner, ASvn, ['checkout', '-q', mUrl + '/trunk', AWorkingCopy, '--non-interactive'], AFolder);
end;

/// <summary>Gleich aufgebaute Verläufe: dieselben fünf Schritte in AGitFolder und AWorkingCopy.</summary>
procedure CommitBothSteps(const ARunner: IAtlasVcsRunner; const AGit, ASvn, AGitFolder, AWorkingCopy: string);
var
  mStep: Integer;
begin
  for mStep := 1 to 5 do
  begin
    if mStep = 3 then
    begin
      Exec(ARunner, AGit, ['mv', 'Src/Alt.pas', 'Src/Neu.pas'], AGitFolder);
      Exec(ARunner, ASvn, ['move', '-q', 'Src/Alt.pas', 'Src/Neu.pas'], AWorkingCopy);
    end
    else
    begin
      WriteStep(AGitFolder, mStep);
      WriteStep(AWorkingCopy, mStep);
      if mStep = 1 then
      begin
        Exec(ARunner, ASvn, ['add', '-q', 'Src'], AWorkingCopy);
      end;
    end;
    Exec(ARunner, AGit, ['add', '-A'], AGitFolder);
    Exec(ARunner, AGit, ['commit', '-q', '-m', 'Schritt ' + IntToStr(mStep)], AGitFolder);
    Exec(ARunner, ASvn, ['commit', '-q', '-m', 'Schritt ' + IntToStr(mStep), '--non-interactive', '--username',
      'atlas'], AWorkingCopy);
  end;
end;

/// <summary>Git und SVN liefern dieselben Werte je Unit und Methode.</summary>
procedure AssertSameResults(const AGitResult, ASvnResult: THotspotResult);
var
  mIndex: Integer;
begin
  Assert.AreEqual(Integer(Length(AGitResult.Units)), Integer(Length(ASvnResult.Units)));
  for mIndex := 0 to High(AGitResult.Units) do
  begin
    Assert.AreEqual(AGitResult.Units[mIndex].UnitName, ASvnResult.Units[mIndex].UnitName);
    Assert.AreEqual(AGitResult.Units[mIndex].Changes.Changes, ASvnResult.Units[mIndex].Changes.Changes,
      AGitResult.Units[mIndex].UnitName);
    Assert.AreEqual(Integer(Length(AGitResult.Units[mIndex].Changes.Authors)),
      Integer(Length(ASvnResult.Units[mIndex].Changes.Authors)));
    Assert.AreEqual(AGitResult.Units[mIndex].Complexity, ASvnResult.Units[mIndex].Complexity);
    Assert.AreEqual(AGitResult.Units[mIndex].Score, ASvnResult.Units[mIndex].Score, 1E-9);
  end;
  Assert.AreEqual(Integer(Length(AGitResult.Methods)), Integer(Length(ASvnResult.Methods)));
  for mIndex := 0 to High(AGitResult.Methods) do
  begin
    Assert.AreEqual(AGitResult.Methods[mIndex].Changes.Changes, ASvnResult.Methods[mIndex].Changes.Changes,
      AGitResult.Methods[mIndex].UnitName);
  end;
  Assert.AreEqual(Integer(Length(AGitResult.Coupling)), Integer(Length(ASvnResult.Coupling)));
end;

procedure TShellHotspotsTests.SvnGivesSameValuesAsGit;
var
  mGit, mSvn, mSvnAdmin, mFolder, mGitFolder, mWorkingCopy, mError: string;
  mRunner: IAtlasVcsRunner;
  mGitVcs, mSvnVcs: IHotspotVcs;
  mGitResult, mSvnResult: THotspotResult;
begin
  if not SvnTools(mGit, mSvn, mSvnAdmin) then
  begin
    Exit;
  end;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mFolder := NewFolder('svn');
  try
    mGitFolder := TPath.Combine(mFolder, 'git');
    mWorkingCopy := TPath.Combine(mFolder, 'wc');
    TDirectory.CreateDirectory(mGitFolder);
    InitGit(mRunner, mGit, mGitFolder, 'atlas');
    CreateSvnWorkingCopy(mRunner, mSvn, mSvnAdmin, mFolder, TPath.Combine(mFolder, 'repo'), mWorkingCopy);
    CommitBothSteps(mRunner, mGit, mSvn, mGitFolder, mWorkingCopy);
    Exec(mRunner, mSvn, ['update', '-q', '--non-interactive'], mWorkingCopy);
    Assert.IsTrue(TShellHotspotVcs.Detect(mGitFolder, TServerSettings.Default, mGitVcs, mError), mError);
    Assert.IsTrue(TShellHotspotVcs.Detect(mWorkingCopy, TServerSettings.Default, mSvnVcs, mError), mError);
    Assert.AreEqual<THotspotVcsKind>(THotspotVcsKind.Svn, mSvnVcs.Kind);
    Assert.AreEqual('6', mSvnVcs.Head, 'Ablage = r1, fünf Schritte');
    mGitResult := Analyze(mGitFolder, mGitVcs);
    mSvnResult := Analyze(mWorkingCopy, mSvnVcs);
    Assert.AreEqual(5, mSvnResult.Commits);
    AssertSameResults(mGitResult, mSvnResult);
  finally
    mGitVcs := nil;
    mSvnVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellHotspotsTests);

end.
