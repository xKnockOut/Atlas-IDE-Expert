unit Atlas.UI.Tracker.Strings.Tests;

// Texte des Moduls Tracker (#1455), je Feature eine Tabelle: jede Id in beiden Sprachen, gleiche Platzhalter,
// und jede Tabelle folgt der Sprache von Base.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FollowsLanguageOfBase;
    [Test]
    procedure EnglishFollowsLanguageOfBase;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Strings.Tests,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Development.Strings,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.UI.Tracker.Commands.Strings,
  Atlas.UI.Tracker.Flow.Strings,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.Time.Strings,
  Atlas.UI.Tracker.Attach.Strings,
  Atlas.UI.Tracker.NewIssue.Strings,
  Atlas.UI.Tracker.Settings.Strings,
  Atlas.UI.Tracker.MyIssues.Strings,
  Atlas.UI.Tracker.Sprint.Strings,
  Atlas.UI.Tracker.TestResults.Strings;

type
  /// <summary>Text zur Id mit der Ordnungszahl AIndex in der aktuellen Sprache.</summary>
  TTableText = reference to function(AIndex: Integer): string;

  TTable = record
    Name: string;
    Count: Integer;
    Text: TTableText;
  end;

function Table(const AName: string; ACount: Integer; const AText: TTableText): TTable;
begin
  Result.Name := AName;
  Result.Count := ACount;
  Result.Text := AText;
end;

/// <summary>Die Texttabellen aller Features des Moduls.</summary>
function Tables: TArray<TTable>;
begin
  SetLength(Result, 13);
  Result[0] := Table('Issue', Ord(High(TAtlasIssueTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId(AIndex));
    end);
  Result[1] := Table('Development', Ord(High(TAtlasIssueDevTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId(AIndex));
    end);
  Result[2] := Table('Board', Ord(High(TAtlasBoardTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId(AIndex));
    end);
  Result[3] := Table('Flow', Ord(High(TAtlasFlowTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasFlowStrings.Text(TAtlasFlowTextId(AIndex));
    end);
  Result[4] := Table('Workflow', Ord(High(TAtlasWorkflowTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId(AIndex));
    end);
  Result[5] := Table('Time', Ord(High(TAtlasTimeTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasTimeStrings.Text(TAtlasTimeTextId(AIndex));
    end);
  Result[6] := Table('Attach', Ord(High(TAtlasAttachTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasAttachStrings.Text(TAtlasAttachTextId(AIndex));
    end);
  Result[7] := Table('NewIssue', Ord(High(TAtlasNewIssueTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId(AIndex));
    end);
  Result[8] := Table('Settings', Ord(High(TAtlasOptionsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasOptionsStrings.Text(TAtlasOptionsTextId(AIndex));
    end);
  Result[9] := Table('MyIssues', Ord(High(TAtlasMyIssuesTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId(AIndex));
    end);
  Result[10] := Table('Sprint', Ord(High(TAtlasSprintTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId(AIndex));
    end);
  Result[11] := Table('TestResults', Ord(High(TAtlasTestResultsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId(AIndex));
    end);
  Result[12] := Table('Commands', Ord(High(TAtlasCommandsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId(AIndex));
    end);
end;

procedure TAtlasTrackerStringsTests.EveryTextExistsInBothLanguages;
var
  mTable: TTable;
  mIndex: Integer;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mTable in Tables do
    begin
      Assert.IsTrue(mTable.Count > 0, mTable.Name);
      for mIndex := 0 to mTable.Count - 1 do
      begin
        TAtlasStrings.Language := TAtlasLanguage.German;
        mGerman := mTable.Text(mIndex);
        TAtlasStrings.Language := TAtlasLanguage.English;
        AssertTextPair(mGerman, mTable.Text(mIndex), mIndex);
      end;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerStringsTests.FollowsLanguageOfBase;
var
  mTable: TTable;
  mIndex: Integer;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für jede Tabelle des Moduls.
  mSaved := TAtlasStrings.Language;
  try
    for mTable in Tables do
    begin
      mDiffers := 0;
      for mIndex := 0 to mTable.Count - 1 do
      begin
        TAtlasStrings.Language := TAtlasLanguage.German;
        mGerman := mTable.Text(mIndex);
        TAtlasStrings.Language := TAtlasLanguage.English;
        if mGerman <> mTable.Text(mIndex) then
        begin
          Inc(mDiffers);
        end;
      end;
      Assert.IsTrue(mDiffers > 0, mTable.Name + ': kein Text folgt der Sprache von Base');
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerStringsTests.EnglishFollowsLanguageOfBase;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.IsFalse(TAtlasWorkflowStrings.English);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.IsTrue(TAtlasWorkflowStrings.English);
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerStringsTests);

end.
