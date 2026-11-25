unit Atlas.IDE.Tracker.Composition.HostAdapters;

// Adapter der Teile des Moduls Tracker (#1443): legt die Adapter
// (Atlas.IDE.Tracker.Adapters.*) zu den Klassen der Wurzel an und meldet sie
// über den Scope des Moduls an, damit Atlas.IDE.Tracker.Composition.Parts
// nur die Teile startet und stoppt (Regel 4: alles über den Scope).
// Hauptthread.

interface

uses
  Atlas.Core.Commands.Contract,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Tracker.CommentAssist,
  Atlas.IDE.Tracker.MyIssues,
  Atlas.IDE.Tracker.Review,
  Atlas.IDE.Tracker.TestResults;

type
  TAtlasTrackerAdapters = class
  public
    /// <summary>Kacheln „Meine Issues“ und „Sprint“ (#765, #1277) und „Issue anlegen“ für Base (#1355) über
    /// AScope; die Registrierungen gibt der Aufrufer rückwärts frei.</summary>
    class function ProvideIssues(const AScope: IAtlasModuleScope;
      AIssues: TAtlasIdeIssues): TArray<IAtlasRegistration>; static;
    /// <summary>„Prüfen“ (#2126) hört als IAtlasTestsListener auf das Ende der betroffenen Tests.</summary>
    class function ProvideReview(const AScope: IAtlasModuleScope;
      AReview: TAtlasIdeIssueReview): IAtlasRegistration; static;
    /// <summary>Kachel „Testergebnisse“ (#763) und Zuhörer der Zusammenfassungen von Base.</summary>
    class function ProvideTests(const AScope: IAtlasModuleScope;
      ATests: TAtlasIdeTestResults): TArray<IAtlasRegistration>; static;
    /// <summary>Issues in der Befehlspalette (#1270); nil ohne Suche.</summary>
    class function PaletteSource(AIssues: TAtlasIdeIssues): IAtlasPaletteSource; static;
    /// <summary>Hook für TAtlasIdeIssuesHooks.CommentAssist (#1278).</summary>
    class function CommentAssist: TAtlasCommentAssistAdapt; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract.CommentAssist,
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.IDE.Base.Foundation.WelcomeTiles,
  Atlas.IDE.Projects.Summaries,
  Atlas.UI.Tracker.Contract.MyIssues,
  Atlas.UI.Tracker.Contract.Sprint,
  Atlas.IDE.Tracker.Adapters.CommentAssist,
  Atlas.IDE.Tracker.Adapters.MyIssues,
  Atlas.IDE.Tracker.Adapters.NewIssue,
  Atlas.IDE.Tracker.Adapters.PaletteSearch,
  Atlas.IDE.Tracker.Adapters.Review,
  Atlas.IDE.Tracker.Adapters.Sprint,
  Atlas.IDE.Tracker.Adapters.TestResults,
  Atlas.IDE.Tracker.Adapters.Tiles,
  Atlas.UI.Tracker.Contract.TestResults;

/// <summary>Quelle der Sprint-Kachel, solange die Sprint-Steuerung von AIssues läuft; sonst nil. Eigene Routine:
/// Die anonyme Methode hält nur AIssues.</summary>
function SprintSourceOf(AIssues: TAtlasIdeIssues): TFunc<IAtlasSprintSource>;
begin
  Result :=
    function: IAtlasSprintSource
    begin
      Result := nil;
      if AIssues.Services.Sprint <> nil then
      begin
        Result := TAtlasSprintSourceAdapter.Create(AIssues.Services.Sprint);
      end;
    end;
end;

function AdaptCommentAssist(AAssist: TAtlasIdeCommentAssist): IAtlasCommentAssist;
begin
  Result := TAtlasCommentAssistAdapter.Create(AAssist);
end;

{ TAtlasTrackerAdapters }

class function TAtlasTrackerAdapters.ProvideIssues(const AScope: IAtlasModuleScope;
  AIssues: TAtlasIdeIssues): TArray<IAtlasRegistration>;
var
  mSource: IAtlasIssuesSource;
begin
  mSource := TAtlasIssuesSourceAdapter.Create(AIssues);
  Result := [AScope.Provide(IAtlasWelcomeTile, TAtlasTrackerIssuesTile.Create(AIssues, mSource) as IAtlasWelcomeTile),
    AScope.Provide(IAtlasWelcomeTile, TAtlasTrackerSprintTile.Create(AIssues, SprintSourceOf(AIssues)) as
    IAtlasWelcomeTile),
    AScope.Provide(IAtlasIssueCreation, TAtlasIdeIssueCreation.Create as IAtlasIssueCreation)];
end;

class function TAtlasTrackerAdapters.ProvideReview(const AScope: IAtlasModuleScope;
  AReview: TAtlasIdeIssueReview): IAtlasRegistration;
begin
  Result := AScope.Provide(IAtlasTestsListener, TAtlasReviewTestsListener.Create(AReview) as IAtlasTestsListener);
end;

class function TAtlasTrackerAdapters.ProvideTests(const AScope: IAtlasModuleScope;
  ATests: TAtlasIdeTestResults): TArray<IAtlasRegistration>;
var
  mSource: IAtlasTestResultsSource;
begin
  mSource := TAtlasTestResultsSourceAdapter.Create(ATests);
  Result := [AScope.Provide(IAtlasWelcomeTile, TAtlasTrackerTestsTile.Create(mSource) as IAtlasWelcomeTile),
    AScope.Provide(IAtlasProjectSummaryListener,
    TAtlasTestsSummaryListener.Create(ATests) as IAtlasProjectSummaryListener)];
end;

class function TAtlasTrackerAdapters.PaletteSource(AIssues: TAtlasIdeIssues): IAtlasPaletteSource;
begin
  Result := nil;
  if (AIssues <> nil) and (AIssues.Services.PaletteSearch <> nil) then
  begin
    Result := TAtlasIssuePaletteSourceAdapter.Create(AIssues.Services.PaletteSearch);
  end;
end;

class function TAtlasTrackerAdapters.CommentAssist: TAtlasCommentAssistAdapt;
begin
  Result := AdaptCommentAssist;
end;

end.
