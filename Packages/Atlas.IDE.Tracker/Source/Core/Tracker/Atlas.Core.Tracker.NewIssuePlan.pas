unit Atlas.Core.Tracker.NewIssuePlan;

// Entscheidungen von „Issue anlegen …“ (#1268) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.NewIssue)
// ruft nur noch Editor, Dialog, Hintergrund und Benachrichtigung:
// - Auswahl der Tracker: der des aktiven Projekts zuerst, dahinter die übrigen persönlichen Verbindungen, und ihre
//   Beschriftung („Firma (GitHub · github.com)“);
// - ob GitHub-Vorlagen der Arbeitskopie gelten (#2137) und ob eine Seite im Browser öffnen darf.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections;

type
  /// <summary>Eintrag der Tracker-Auswahl im Dialog.</summary>
  TAtlasNewIssueChoice = record
    Caption: string;
    Target: TAtlasTrackerTarget;
  end;

  TAtlasNewIssuePlan = class
  public
    /// <summary>„Anbieter · Server“, mit Verbindungsnamen AConnection davor.</summary>
    class function CaptionOf(const AConnection: string; const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Tracker des Projekts AResolved (Verbindung AConnection, ohne Anbieter keiner; Sprache aus
    /// AConnections) zuerst, dahinter die übrigen AConnections; AIndex der vorgewählte (der erste), -1 ohne
    /// Einträge.</summary>
    class function Choices(const AResolved: TAtlasTrackerTarget; const AConnection: string;
      const AConnections: TArray<TAtlasTrackerConnection>; out AIndex: Integer): TArray<TAtlasNewIssueChoice>;
      static;
    /// <summary>Wie Choices mit den Verbindungen aus issues.connections (AConnectionsJson).</summary>
    class function ChoicesFor(const AResolved: TAtlasTrackerTarget; const AConnection, AConnectionsJson: string;
      out AIndex: Integer): TArray<TAtlasNewIssueChoice>; static;
    /// <summary>Gleicher Tracker: Anbieter, Server und Projekt ohne Groß-/Kleinschreibung.</summary>
    class function SameTracker(const A, B: TAtlasTrackerTarget): Boolean; static;
    /// <summary>Kommen Vorlagen aus der Arbeitskopie in Frage: mit Projekt (AHasProject), GitHub und
    /// issues.create.templates (AEnabled)? Ob ATarget der Tracker des Projekts ist, prüft der Aufrufer.</summary>
    class function TemplatesPossible(AHasProject, AEnabled: Boolean; const ATarget: TAtlasTrackerTarget): Boolean;
      static;
    /// <summary>Darf die Seite APage im Browser öffnen (nur https)?</summary>
    class function Opens(const APage: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  cGitHubName = 'GitHub';
  cYouTrackName = 'YouTrack';
  cHttps = 'https://';

function Choice(const ACaption: string; const ATarget: TAtlasTrackerTarget): TAtlasNewIssueChoice;
begin
  Result.Caption := ACaption;
  Result.Target := ATarget;
end;

class function TAtlasNewIssuePlan.CaptionOf(const AConnection: string; const ATarget: TAtlasTrackerTarget): string;
var
  mProvider: string;
begin
  if SameText(ATarget.Provider, TAtlasTrackerTarget.cGitHub) then
  begin
    mProvider := cGitHubName;
  end
  else
  begin
    mProvider := cYouTrackName;
  end;
  Result := mProvider + ' · ' + ATarget.Server;
  if AConnection <> '' then
  begin
    Result := AConnection + ' (' + Result + ')';
  end;
end;

class function TAtlasNewIssuePlan.Choices(const AResolved: TAtlasTrackerTarget; const AConnection: string;
  const AConnections: TArray<TAtlasTrackerConnection>; out AIndex: Integer): TArray<TAtlasNewIssueChoice>;
var
  mResolved, mTarget: TAtlasTrackerTarget;
  mItem: TAtlasTrackerConnection;
  mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AConnections) + 1);
  mCount := 0;
  mResolved := AResolved;
  mResolved.Language := TAtlasTrackerConnections.LanguageOf(AConnections, mResolved);
  if mResolved.Provider <> '' then
  begin
    Result[0] := Choice(CaptionOf(AConnection, mResolved), mResolved);
    mCount := 1;
  end;
  for mItem in AConnections do
  begin
    if (AConnection <> '') and SameText(mItem.Name, AConnection) then
    begin
      Continue;
    end;
    mTarget := TAtlasTrackerTarget.Create(mItem.Provider, mItem.Url, '', '');
    mTarget.Language := mItem.Language;
    Result[mCount] := Choice(CaptionOf(mItem.Name, mTarget), mTarget);
    Inc(mCount);
  end;
  SetLength(Result, mCount);
  AIndex := -1;
  if mCount > 0 then
  begin
    AIndex := 0;
  end;
end;

class function TAtlasNewIssuePlan.ChoicesFor(const AResolved: TAtlasTrackerTarget; const AConnection,
  AConnectionsJson: string; out AIndex: Integer): TArray<TAtlasNewIssueChoice>;
begin
  Result := Choices(AResolved, AConnection, TAtlasTrackerConnections.Read(AConnectionsJson), AIndex);
end;

class function TAtlasNewIssuePlan.SameTracker(const A, B: TAtlasTrackerTarget): Boolean;
begin
  Result := SameText(A.Provider, B.Provider) and SameText(A.Server, B.Server) and SameText(A.Project, B.Project);
end;

class function TAtlasNewIssuePlan.TemplatesPossible(AHasProject, AEnabled: Boolean;
  const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := AHasProject and SameText(ATarget.Provider, TAtlasTrackerTarget.cGitHub) and AEnabled;
end;

class function TAtlasNewIssuePlan.Opens(const APage: string): Boolean;
begin
  Result := APage.StartsWith(cHttps, True);
end;

end.
