unit Shell.SymbolHistory.Tests;

// Symbolgeschichte mit echtem git (#2641): Ein temporäres Repository mit vier Commits (Routine eingeführt, geändert,
// in eine neue Unit verschoben und dabei umbenannt, wieder geändert; Dateien mit BOM). Geprüft werden Zeilen,
// Text je Stand, geänderte Dateien eines Commits und die ganze Geschichte über die Verschiebung. Fehlt git, endet
// der Test ohne Prüfung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellSymbolHistoryTests = class
  public
    [Test]
    procedure DetectWithoutWorkingCopyGivesReason;
    [Test]
    procedure GitHistoryFollowsMoveAndRename;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Contract,
  Atlas.Common.History.Service,
  Shell.Platform,
  Shell.VersionControlChanges,
  Shell.SymbolHistory;

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

function NewFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasSymbolHistory-' + TGUID.NewGuid.ToString.Substring(1, 8));
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
  // git legt schreibgeschützte Dateien an.
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

/// <summary>Routine AName mit einer Schleife; ATag ändert die erste Zeile des Rumpfs.</summary>
function Routine(const AName, ATag: string): string;
begin
  Result := 'procedure ' + AName + '(AWert: Integer);'#10'var'#10'  mSumme: Integer;'#10'begin'#10 +
    '  mSumme := ' + ATag + ';'#10'  while AWert > 0 do'#10'  begin'#10'    mSumme := mSumme + AWert;'#10 +
    '    Dec(AWert);'#10'  end;'#10'  Ausgabe(mSumme);'#10'end;'#10;
end;

/// <summary>Unit AName mit den Routinen ARoutines (Text), gespeichert mit BOM.</summary>
procedure PutUnit(const AFolder, AName, ARoutines: string);
var
  mFileName: string;
begin
  mFileName := TPath.Combine(TPath.Combine(AFolder, 'Src'), AName + '.pas');
  TDirectory.CreateDirectory(ExtractFileDir(mFileName));
  TFile.WriteAllText(mFileName, 'unit ' + AName + ';'#10#10'interface'#10#10'implementation'#10#10 + ARoutines +
    #10'end.'#10, TEncoding.UTF8);
end;

procedure Commit(const ARunner: IAtlasVcsRunner; const AGit, AFolder, AMessage: string);
begin
  Exec(ARunner, AGit, ['add', '-A'], AFolder);
  Exec(ARunner, AGit, ['commit', '-q', '-m', AMessage], AFolder);
end;

/// <summary>Vier Commits: Rechne eingeführt (#1), geändert (#2), als Summiere nach Neu.pas verschoben (ABC-3),
/// geändert (#4). Alt.pas behält eine andere Routine.</summary>
procedure CommitSteps(const ARunner: IAtlasVcsRunner; const AGit, AFolder: string);
const
  cOther = 'procedure Bleibt;'#10'begin'#10'end;'#10;
begin
  Exec(ARunner, AGit, ['init', '-q'], AFolder);
  Exec(ARunner, AGit, ['config', 'user.name', 'Atlas Test'], AFolder);
  Exec(ARunner, AGit, ['config', 'user.email', 'test@example.org'], AFolder);
  Exec(ARunner, AGit, ['config', 'core.autocrlf', 'false'], AFolder);
  Exec(ARunner, AGit, ['config', 'commit.gpgsign', 'false'], AFolder);
  PutUnit(AFolder, 'Alt', cOther + #10 + Routine('TFoo.Rechne', '0'));
  Commit(ARunner, AGit, AFolder, 'Rechne eingeführt (#1)');
  PutUnit(AFolder, 'Alt', cOther + #10 + Routine('TFoo.Rechne', '1'));
  Commit(ARunner, AGit, AFolder, 'Start bei 1 (#2)');
  PutUnit(AFolder, 'Alt', cOther);
  PutUnit(AFolder, 'Neu', Routine('TFoo.Summiere', '1'));
  Commit(ARunner, AGit, AFolder, 'ABC-3 Summe in eigene Unit');
  PutUnit(AFolder, 'Neu', Routine('TFoo.Summiere', '2'));
  Commit(ARunner, AGit, AFolder, 'Start bei 2 (#4)');
end;

{ TShellSymbolHistoryTests }

procedure TShellSymbolHistoryTests.DetectWithoutWorkingCopyGivesReason;
var
  mFolder, mError: string;
  mVcs: ISymbolHistoryVcs;
begin
  mFolder := NewFolder;
  try
    Assert.IsFalse(TShellSymbolHistoryVcs.DetectHistory(mFolder, TServerSettings.Default, mVcs, mError));
    Assert.IsNull(mVcs);
    Assert.AreNotEqual('', mError);
  finally
    RemoveFolder(mFolder);
  end;
end;

/// <summary>Bausteine der Versionsverwaltung: Text mit BOM, Dateien eines Commits, Zeilen eines Bereichs.</summary>
procedure AssertParts(const AVcs: ISymbolHistoryVcs; const AFirst, ALast: Integer);
var
  mText: string;
  mFiles: TArray<THotspotFileChange>;
  mCommits: TArray<TSymbolLineCommit>;
begin
  Assert.AreEqual<THotspotTextState>(THotspotTextState.Found, AVcs.TextAt('Src/Neu.pas', '', False, mText));
  Assert.IsTrue(mText.StartsWith('unit Neu;'), 'BOM entfernt');
  Assert.AreEqual<THotspotTextState>(THotspotTextState.Missing, AVcs.TextAt('Src/Neu.pas', 'HEAD~1', True, mText));
  Assert.IsTrue(AVcs.CommitFiles('HEAD~1', mFiles));
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.IsTrue(AVcs.LineLog('Src/Neu.pas', '', AFirst, ALast, 20, mCommits));
  Assert.AreEqual(2, Integer(Length(mCommits)), 'git log -L endet an der neuen Datei');
  Assert.IsTrue(mCommits[0].Message.StartsWith('Start bei 2'));
end;

procedure TShellSymbolHistoryTests.GitHistoryFollowsMoveAndRename;
var
  mGit, mFolder, mError, mText: string;
  mRunner: IAtlasVcsRunner;
  mVcs: ISymbolHistoryVcs;
  mService: ISymbolHistoryService;
  mRequest: TSymbolHistoryRequest;
  mResult: TSymbolHistoryResult;
begin
  mGit := TVcsChanges.ToolFor(TAtlasVcsKind.Git, '');
  // Ohne git keine Prüfung. Exit statt Assert.Pass: Der Leckmonitor zählte die Meldung als Leck.
  if mGit = '' then
  begin
    Exit;
  end;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mFolder := NewFolder;
  try
    CommitSteps(mRunner, mGit, mFolder);
    Assert.IsTrue(TShellSymbolHistoryVcs.DetectHistory(mFolder, TServerSettings.Default, mVcs, mError), mError);
    mRequest := Default(TSymbolHistoryRequest);
    mRequest.Symbol := 'TFoo.Summiere';
    mRequest.Path := 'Src/Neu.pas';
    mRequest.IsRoutine := True;
    mRequest.Limit := 20;
    mRequest.FollowMoves := True;
    Assert.AreEqual<THotspotTextState>(THotspotTextState.Found, mVcs.TextAt(mRequest.Path, '', False, mText));
    Assert.IsTrue(TSymbolHistoryService.FindRoutine(mText, mRequest.Symbol, mRequest.FirstLine, mRequest.LastLine));
    AssertParts(mVcs, mRequest.FirstLine, mRequest.LastLine);
    mService := TSymbolHistoryService.Create;
    mResult := mService.Run(mVcs, mRequest);
    Assert.AreEqual(4, Integer(Length(mResult.Events)));
    Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Moved, mResult.Events[1].Kind, 'verschoben');
    Assert.AreEqual('Src/Alt.pas', mResult.Events[1].FromPath);
    Assert.AreEqual('TFoo.Rechne', mResult.Events[1].FromSymbol);
    Assert.AreEqual('ABC-3', string.Join(',', mResult.Events[1].Issues));
    Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[3].Kind, 'eingeführt');
    Assert.AreEqual('#1', string.Join(',', mResult.Events[3].Issues));
    Assert.AreEqual<TSymbolHistoryStop>(TSymbolHistoryStop.None, mResult.Stop);
  finally
    mVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSymbolHistoryTests);

end.
