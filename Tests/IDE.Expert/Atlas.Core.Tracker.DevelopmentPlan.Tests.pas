unit Atlas.Core.Tracker.DevelopmentPlan.Tests;

// Entscheidungen des Reiters „Entwicklung“ (#1269, #1967) ohne IDE: gleiches Issue, Basis-Branches, Tracker ohne
// Anbieter oder Token, Zeile zum Tracker, kurze Revision, Rückfrage vor dem Wechseln und Diff eines Commits.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueDevelopmentPlanTests = class
  public
    [Test]
    procedure SameIssueNeedsCurrentAndBothKeys;
    [Test]
    procedure BasesFromSettingOrMainMaster;
    [Test]
    procedure UnreachableWithoutProviderOrToken;
    [Test]
    procedure NoteOnlyWhenTrackerFailed;
    [Test]
    procedure ShortRevisionOnlyForHashes;
    [Test]
    procedure AsksSwitchOnlyWithChanges;
    [Test]
    procedure CommitDiffCaptionsAndLimit;
    /// <summary>Beim ersten Lesefehler Schluss: bisherige Dateien bleiben, das Ergebnis ist der Fehler.</summary>
    [Test]
    procedure CommitDiffStopsAtFirstError;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Tracker.DevelopmentPlan,
  Atlas.Core.VersionControl.Contract;

function LogFile(const APath, ARepositoryPath: string): TAtlasVcsLogFile;
begin
  Result := Default(TAtlasVcsLogFile);
  Result.Path := APath;
  Result.RepositoryPath := ARepositoryPath;
end;

function Entry(ACount: Integer): TAtlasVcsLogEntry;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasVcsLogEntry);
  Result.Revision := 'abc';
  SetLength(Result.Files, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result.Files[mIndex] := LogFile('C:\Projekt\U' + IntToStr(mIndex) + '.pas', 'src/U' + IntToStr(mIndex) + '.pas');
  end;
end;

/// <summary>Liefert „vorher:Pfad“ bzw. „nachher:Pfad“; AFailAt: Datei, deren Inhalt danach nicht lesbar ist.
/// </summary>
function Content(const AFailAt: string): TAtlasIssueDevContent;
var
  mFailAt: string;
begin
  mFailAt := AFailAt;
  Result :=
    function(const AFile: TAtlasVcsLogFile; ABefore: Boolean; out AText: string): TAtlasVcsOutcome
    begin
      AText := '';
      Result := TAtlasVcsOutcome.Ok;
      if (mFailAt <> '') and (AFile.RepositoryPath = mFailAt) and not ABefore then
      begin
        Exit(TAtlasVcsOutcome.Failed);
      end;
      if ABefore then
      begin
        AText := 'vorher:' + AFile.RepositoryPath;
      end
      else
      begin
        AText := 'nachher:' + AFile.RepositoryPath;
      end;
    end;
end;

function Development(ALoaded: Boolean; AError: TAtlasCiFetchError): TAtlasIssueDevelopment;
begin
  Result := TAtlasIssueDevelopment.Empty;
  Result.TrackerLoaded := ALoaded;
  Result.TrackerError := AError;
end;

function NoteOf(ALoaded: Boolean; AError: TAtlasCiFetchError): Integer;
begin
  Result := Ord(TAtlasIssueDevelopmentPlan.NoteOf(Development(ALoaded, AError)));
end;

{ TAtlasIssueDevelopmentPlanTests }

procedure TAtlasIssueDevelopmentPlanTests.SameIssueNeedsCurrentAndBothKeys;
var
  mTarget, mOther: TAtlasTrackerTarget;
begin
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', 'owner/repo', '');
  mOther := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', 'owner/anders', '');
  Assert.IsTrue(TAtlasIssueDevelopmentPlan.SameIssue(True, mTarget, '#12', mTarget, '#12'));
  Assert.IsFalse(TAtlasIssueDevelopmentPlan.SameIssue(False, mTarget, '#12', mTarget, '#12'), 'noch keins');
  Assert.IsFalse(TAtlasIssueDevelopmentPlan.SameIssue(True, mTarget, '#12', mTarget, '#13'));
  Assert.IsFalse(TAtlasIssueDevelopmentPlan.SameIssue(True, mTarget, '#12', mOther, '#12'), 'anderer Tracker');
end;

procedure TAtlasIssueDevelopmentPlanTests.BasesFromSettingOrMainMaster;
begin
  Assert.AreEqual('develop', string.Join(',', TAtlasIssueDevelopmentPlan.Bases(' develop ')));
  Assert.AreEqual('main,master', string.Join(',', TAtlasIssueDevelopmentPlan.Bases('  ')));
end;

procedure TAtlasIssueDevelopmentPlanTests.UnreachableWithoutProviderOrToken;
begin
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.None)), Integer(Ord(TAtlasIssueDevelopmentPlan.Unreachable(True,
    True))));
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.NotConfigured)),
    Integer(Ord(TAtlasIssueDevelopmentPlan.Unreachable(False, False))));
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.Unauthorized)),
    Integer(Ord(TAtlasIssueDevelopmentPlan.Unreachable(True, False))));
end;

procedure TAtlasIssueDevelopmentPlanTests.NoteOnlyWhenTrackerFailed;
begin
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.None)), NoteOf(True, TAtlasCiFetchError.Network), 'geladen');
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.None)), NoteOf(False, TAtlasCiFetchError.None));
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.None)), NoteOf(False, TAtlasCiFetchError.Cancelled));
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.Token)), NoteOf(False, TAtlasCiFetchError.Unauthorized));
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.Timeout)), NoteOf(False, TAtlasCiFetchError.Timeout));
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.Config)), NoteOf(False, TAtlasCiFetchError.UnknownProvider));
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.Invalid)), NoteOf(False, TAtlasCiFetchError.NotFound));
  Assert.AreEqual(Integer(Ord(TAtlasIssueDevNote.Network)), NoteOf(False, TAtlasCiFetchError.Network));
end;

procedure TAtlasIssueDevelopmentPlanTests.ShortRevisionOnlyForHashes;
begin
  Assert.AreEqual('0123456', TAtlasIssueDevelopmentPlan.ShortRevision('0123456789abcdef0123'));
  Assert.AreEqual('48230', TAtlasIssueDevelopmentPlan.ShortRevision('48230'), 'SVN');
end;

procedure TAtlasIssueDevelopmentPlanTests.AsksSwitchOnlyWithChanges;
begin
  Assert.IsTrue(TAtlasIssueDevelopmentPlan.AsksSwitch(1));
  Assert.IsFalse(TAtlasIssueDevelopmentPlan.AsksSwitch(0));
end;

procedure TAtlasIssueDevelopmentPlanTests.CommitDiffCaptionsAndLimit;
var
  mEntry: TAtlasVcsLogEntry;
  mFiles: TArray<TAtlasIssueFileDiff>;
begin
  mEntry := Entry(2);
  mEntry.Files[1].RepositoryPath := '';
  Assert.AreEqual(Integer(Ord(TAtlasVcsOutcome.Ok)), Integer(Ord(TAtlasIssueDevelopmentPlan.CommitDiff(mEntry,
    Content(''), mFiles))));
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('src/U0.pas', mFiles[0].Caption);
  Assert.AreEqual('vorher:src/U0.pas', mFiles[0].Before);
  Assert.AreEqual('nachher:src/U0.pas', mFiles[0].After);
  Assert.AreEqual('C:\Projekt\U1.pas', mFiles[1].Caption, 'ohne Pfad im Repository');
  TAtlasIssueDevelopmentPlan.CommitDiff(Entry(TAtlasIssueDevelopmentPlan.cMaxDiffFiles + 5), Content(''), mFiles);
  Assert.AreEqual(Integer(TAtlasIssueDevelopmentPlan.cMaxDiffFiles), Integer(Length(mFiles)));
end;

procedure TAtlasIssueDevelopmentPlanTests.CommitDiffStopsAtFirstError;
var
  mFiles: TArray<TAtlasIssueFileDiff>;
begin
  Assert.AreEqual(Integer(Ord(TAtlasVcsOutcome.Failed)), Integer(Ord(TAtlasIssueDevelopmentPlan.CommitDiff(Entry(4),
    Content('src/U2.pas'), mFiles))));
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('src/U1.pas', mFiles[1].Caption);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueDevelopmentPlanTests);

end.
