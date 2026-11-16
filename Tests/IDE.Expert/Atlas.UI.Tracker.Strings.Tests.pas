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

/// <summary>Texttabellen der Issue-Ansichten (Issue bis Anhänge).</summary>
function IssueTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 7);
  Result[0] := TextTable('Issue', Ord(High(TAtlasIssueTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId(AIndex));
    end);
  Result[1] := TextTable('Development', Ord(High(TAtlasIssueDevTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId(AIndex));
    end);
  Result[2] := TextTable('Board', Ord(High(TAtlasBoardTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId(AIndex));
    end);
  Result[3] := TextTable('Flow', Ord(High(TAtlasFlowTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasFlowStrings.Text(TAtlasFlowTextId(AIndex));
    end);
  Result[4] := TextTable('Workflow', Ord(High(TAtlasWorkflowTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId(AIndex));
    end);
  Result[5] := TextTable('Time', Ord(High(TAtlasTimeTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasTimeStrings.Text(TAtlasTimeTextId(AIndex));
    end);
  Result[6] := TextTable('Attach', Ord(High(TAtlasAttachTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasAttachStrings.Text(TAtlasAttachTextId(AIndex));
    end);
end;

/// <summary>Übrige Texttabellen des Trackers (Neues Issue bis Befehle).</summary>
function MoreTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 6);
  Result[0] := TextTable('NewIssue', Ord(High(TAtlasNewIssueTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId(AIndex));
    end);
  Result[1] := TextTable('Settings', Ord(High(TAtlasOptionsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasOptionsStrings.Text(TAtlasOptionsTextId(AIndex));
    end);
  Result[2] := TextTable('MyIssues', Ord(High(TAtlasMyIssuesTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId(AIndex));
    end);
  Result[3] := TextTable('Sprint', Ord(High(TAtlasSprintTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId(AIndex));
    end);
  Result[4] := TextTable('TestResults', Ord(High(TAtlasTestResultsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId(AIndex));
    end);
  Result[5] := TextTable('Commands', Ord(High(TAtlasCommandsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId(AIndex));
    end);
end;

/// <summary>Die Texttabellen aller Features des Moduls.</summary>
function Tables: TArray<TAtlasTextTable>;
begin
  Result := IssueTables + MoreTables;
end;

{ TAtlasTrackerStringsTests }

procedure TAtlasTrackerStringsTests.EveryTextExistsInBothLanguages;
begin
  AssertTablesInBothLanguages(Tables);
end;

procedure TAtlasTrackerStringsTests.FollowsLanguageOfBase;
begin
  AssertTablesFollowLanguage(Tables);
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
