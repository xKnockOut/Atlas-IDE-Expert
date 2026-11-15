unit Atlas.Core.Tracker.MyIssuesPlan;

// Entscheidungen von „Meine Issues“ (#765) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.MyIssues) ruft
// nur noch Kontext, Dienste und Fenster:
// - „Alle Tracker-Projekte“ (#1928): Gruppen aus den Ansichten je Tracker-Projekt, nur gemeinsame Abfragen, die
//   gewählte Abfrage nach Namen;
// - was nur für ein Projekt gilt (laufende Abfrage, Filter der Sprint-Kachel);
// - was eine Aktion an einer Zeile auslöst („Prüfen“, „Weiterarbeiten“, wieder geöffnete Issues).

interface

uses
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.MyIssues;

type
{$SCOPEDENUMS ON}
  /// <summary>Aktion an einer Zeile (wie TAtlasIssueAction der Oberfläche).</summary>
  TAtlasIssueRowAction = (Continue, Dismiss, Reason, Review);
  /// <summary>Was die Aktion auslöst: prüfen, weiterarbeiten, Marke ausblenden, Grund zeigen, nichts (ohne Dienst
  /// der wieder geöffneten Issues).</summary>
  TAtlasIssueRowStep = (Review, Resume, Dismiss, Reason, Skip);
{$SCOPEDENUMS OFF}

  /// <summary>Ansicht eines Tracker-Projekts für „Alle“: Kopf (Caption, Project) und Ansicht.</summary>
  TAtlasIssuesGroupView = record
    Caption: string;
    Project: string;
    View: TAtlasIssuesView;
  end;

  TAtlasMyIssuesPlan = class
  public
    /// <summary>Abfragen aus AQueries, die es (nach Name) auch in AOther gibt.</summary>
    class function CommonQueries(const AQueries, AOther: TArray<TAtlasTrackerQuery>): TArray<TAtlasTrackerQuery>;
      static;
    /// <summary>„Alle Tracker-Projekte“: Gruppen AGroups (je höchstens APerGroup Zeilen) auf der Ansicht ABase des
    /// gezeigten Projekts; ohne Filter der Sprint-Kachel; die gewählte Abfrage bleibt nach Namen, wenn alle sie
    /// kennen.</summary>
    class function AllView(const ABase: TAtlasIssuesView; const AGroups: TArray<TAtlasIssuesGroupView>;
      APerGroup: Integer): TAtlasIssuesView; static;
    /// <summary>Gilt ein Stand für AOwner (gesetzt) im Projekt AProject (ohne Groß-/Kleinschreibung)?</summary>
    class function SameProject(const AOwner, AProject: string): Boolean; static;
    /// <summary>Filter der Sprint-Kachel (ACaption, gesetzt in AFilterProject) für AProject?</summary>
    class function FilterApplies(const ACaption, AFilterProject, AProject: string): Boolean; static;
    /// <summary>Was AAction auslöst; AHasReopened: Dienst der wieder geöffneten Issues läuft.</summary>
    class function StepOf(AAction: TAtlasIssueRowAction; AHasReopened: Boolean): TAtlasIssueRowStep; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasMyIssuesPlan.CommonQueries(const AQueries,
  AOther: TArray<TAtlasTrackerQuery>): TArray<TAtlasTrackerQuery>;
var
  mQuery, mOther: TAtlasTrackerQuery;
begin
  Result := nil;
  for mQuery in AQueries do
  begin
    for mOther in AOther do
    begin
      if SameText(mQuery.Name, mOther.Name) then
      begin
        Result := Result + [mQuery];
        Break;
      end;
    end;
  end;
end;

class function TAtlasMyIssuesPlan.AllView(const ABase: TAtlasIssuesView; const AGroups: TArray<TAtlasIssuesGroupView>;
  APerGroup: Integer): TAtlasIssuesView;
var
  mGroup: TAtlasIssuesGroupView;
  mIndex: Integer;
  mSelected: string;
begin
  Result := ABase;
  Result.Items := nil;
  Result.Unseen := nil;
  Result.Groups := nil;
  // Der Filter der Sprint-Kachel gilt nur für ein Board.
  Result.Filter := '';
  Result.Querying := False;
  Result.Status := TAtlasIssuesStatus.NotConfigured;
  mSelected := '';
  if (ABase.QueryIndex >= 0) and (ABase.QueryIndex <= High(ABase.Queries)) then
  begin
    mSelected := ABase.Queries[ABase.QueryIndex].Name;
  end;
  for mGroup in AGroups do
  begin
    TAtlasMyIssues.AddGroup(Result, mGroup.Caption, mGroup.Project, mGroup.View, APerGroup);
    Result.Querying := Result.Querying or mGroup.View.Querying;
    Result.Status := TAtlasIssuesStatus.Ready;
    // Eine Abfrage für alle: nur Abfragen, die jedes Tracker-Projekt kennt.
    Result.Queries := CommonQueries(Result.Queries, mGroup.View.Queries);
  end;
  Result.QueryCounts := nil;
  Result.QueryIndex := -1;
  for mIndex := 0 to High(Result.Queries) do
  begin
    if SameText(Result.Queries[mIndex].Name, mSelected) then
    begin
      Result.QueryIndex := mIndex;
    end;
  end;
end;

class function TAtlasMyIssuesPlan.SameProject(const AOwner, AProject: string): Boolean;
begin
  Result := (AOwner <> '') and SameText(AOwner, AProject);
end;

class function TAtlasMyIssuesPlan.FilterApplies(const ACaption, AFilterProject, AProject: string): Boolean;
begin
  Result := (ACaption <> '') and SameText(AFilterProject, AProject);
end;

class function TAtlasMyIssuesPlan.StepOf(AAction: TAtlasIssueRowAction; AHasReopened: Boolean): TAtlasIssueRowStep;
begin
  case AAction of
    TAtlasIssueRowAction.Review:
      Result := TAtlasIssueRowStep.Review;
    TAtlasIssueRowAction.Continue:
      Result := TAtlasIssueRowStep.Resume;
    TAtlasIssueRowAction.Dismiss:
      if AHasReopened then
      begin
        Result := TAtlasIssueRowStep.Dismiss;
      end
      else
      begin
        Result := TAtlasIssueRowStep.Skip;
      end;
  else
    if AHasReopened then
    begin
      Result := TAtlasIssueRowStep.Reason;
    end
    else
    begin
      Result := TAtlasIssueRowStep.Skip;
    end;
  end;
end;

end.
