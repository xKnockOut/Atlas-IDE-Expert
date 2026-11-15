unit Atlas.Core.Tracker.CommentPlan;

// Entscheidungen des Kommentar-Editors in der IDE (#1278) ohne IDE prüfbar (#1967); die IDE
// (Atlas.IDE.Tracker.CommentAssist) ruft nur noch Anbieter, Hintergrundarbeiter, Versionsverwaltung und Entwürfe:
// - Ob ein Feld Hilfe bekommt (issues.commentEditor, nur mit Kennung).
// - Merker der Benutzerliste je Tracker und Suchtext (ohne Groß-/Kleinschreibung) und wie lange er gilt.
// - Zuletzt geöffnete Issues ohne Netz, höchstens so viele wie Vorschläge.
// - Welche Fehler ins Protokoll kommen (abgebrochen nie, bei der Issue-Suche auch „nicht gefunden“ nicht).

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasCommentPlan = class
  public const
    /// <summary>So lange gilt eine gelesene Benutzerliste.</summary>
    cCacheMs = 5 * 60 * 1000;
  public
    /// <summary>Hilfe für das Feld: Dienst läuft, issues.commentEditor an und ein Issue (AKey) bekannt.</summary>
    class function Assists(AStarted, AActive: Boolean; const AKey: string): Boolean; static;
    /// <summary>Merker der Benutzerliste für den Tracker ATrackerKey und den Suchtext AText.</summary>
    class function UsersKey(const ATrackerKey, AText: string): string; static;
    /// <summary>Gilt eine Liste von ATick (ms) bei ANow noch?</summary>
    class function UsersFresh(ATick, ANow: UInt64): Boolean; static;
    /// <summary>Zuletzt geöffnete Issues als Vorschläge: höchstens AMax.</summary>
    class function Recent(const AIssues: TArray<TAtlasTrackerIssue>; AMax: Integer): TArray<TAtlasTrackerIssue>;
      static;
    /// <summary>Fehler der Benutzersuche ins Protokoll?</summary>
    class function LogsUsersError(AError: TAtlasCiFetchError): Boolean; static;
    /// <summary>Fehler der Issue-Suche ins Protokoll? „Nicht gefunden“ ist bei der Suche nach einer Kennung normal.
    /// </summary>
    class function LogsIssuesError(AError: TAtlasCiFetchError): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasCommentPlan.Assists(AStarted, AActive: Boolean; const AKey: string): Boolean;
begin
  Result := AStarted and AActive and (AKey <> '');
end;

class function TAtlasCommentPlan.UsersKey(const ATrackerKey, AText: string): string;
begin
  Result := ATrackerKey + '|' + AnsiLowerCase(AText);
end;

class function TAtlasCommentPlan.UsersFresh(ATick, ANow: UInt64): Boolean;
begin
  Result := ANow - ATick < cCacheMs;
end;

class function TAtlasCommentPlan.Recent(const AIssues: TArray<TAtlasTrackerIssue>;
  AMax: Integer): TArray<TAtlasTrackerIssue>;
begin
  Result := Copy(AIssues, 0, AMax);
end;

class function TAtlasCommentPlan.LogsUsersError(AError: TAtlasCiFetchError): Boolean;
begin
  Result := AError <> TAtlasCiFetchError.Cancelled;
end;

class function TAtlasCommentPlan.LogsIssuesError(AError: TAtlasCiFetchError): Boolean;
begin
  Result := LogsUsersError(AError) and (AError <> TAtlasCiFetchError.NotFound);
end;

end.
