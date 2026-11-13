unit Atlas.UI.Tracker.MyIssues.Text;

// Texte und Farben des Bereichs „Meine Issues“ ohne Steuerelement (#765): Stand, Filter, Fußzeile, Abfragen,
// Gruppen, Pull Request, Zustandskachel, Hinweise und wieder geöffnete Issues (#2127). Gezeichnet wird in
// Atlas.UI.Tracker.MyIssues; die Zustandskachel und die Tests lesen die Texte hier.

interface

uses
  Vcl.Graphics,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Reopened;

type
{$SCOPEDENUMS ON}
  /// <summary>Was an einer Stelle des Bereichs liegt (Treffer der Maus).</summary>
  TAtlasIssuesHitKind = (None, Row, Key, PullRequest, Start, Assign, Filter, Continue, Dismiss, Reason);
{$SCOPEDENUMS OFF}

  TAtlasIssuesHit = record
    Kind: TAtlasIssuesHitKind;
    /// <summary>Zeile; -1 sonst.</summary>
    Index: Integer;
    class function Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit; static;
  end;

  /// <summary>Texte und Farben des Bereichs, ohne Steuerelement (auch für die Zustandskachel und Tests).</summary>
  TAtlasTrackerIssuesText = class
  private
    class function ActiveFooter(const AView: TAtlasIssuesView; out AText: string): Boolean; static;
    class function NotConfiguredFooter(const AView: TAtlasIssuesView): string; static;
    /// <summary>Was „Beginnen“ tut; '' ohne Issues.</summary>
    class function StartFooter(const AView: TAtlasIssuesView): string; static;
  public const
    /// <summary>Vor dem Titel des Bereichs, solange ein Issue einen Punkt trägt.</summary>
    cUnseenMark = '● ';
    // Dieselben Töne wie „Testergebnisse“ und „Projekte“: lesbar im hellen und im dunklen Thema.
    cGreenColor = TColor($0043A02E);
    cYellowColor = TColor($001A8CC9);
    cRedColor = TColor($002E22CF);
    cGrayColor = TColor($00817666);
  public
    /// <summary>Zeile über der Liste: Stand, Fehler, „Stand vom …“; '' bei frischem Stand.</summary>
    class function StatusText(const AView: TAtlasIssuesView): string; static;
    /// <summary>„Gefiltert: „Sprint 12“, meine offen · alle zeigen“; '' ohne Filter (#1277).</summary>
    class function FilterText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Fußzeile: Hinweis, sonst aktuelles Issue außerhalb der Liste, sonst was „Beginnen“ tut.</summary>
    class function FooterText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Die Fußzeile ist der Link „zuordnen …“ (#1261): Projekt ohne Tracker, Zuordnen möglich.</summary>
    class function FooterIsAssign(const AView: TAtlasIssuesView): Boolean; static;
    /// <summary>Zeile unter der Fußzeile (#1262): „Firma · KASSE · Abfrage: …“; '' ohne Tracker.</summary>
    class function SourceText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Eintrag der Klappliste: „Name (3)“, ab MaxItems „Name (10+)“, ohne Abfrage nur der Name.</summary>
    class function QueryCaption(const AName: string; ACount: Integer): string; static;
    /// <summary>Klappliste sichtbar: eingeschaltet und Tracker mit Abfragen.</summary>
    class function ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean; static;
    class function ErrorText(AError: TAtlasCiFetchError): string; static;
    /// <summary>Kopf einer Gruppe bei „Alle“ (#1928): „YouTrack · KASSE (7)“.</summary>
    class function GroupCaption(const AGroup: TAtlasIssuesGroup): string; static;
    /// <summary>Rechts im Kopf: „+ N weitere“, wird abgefragt, kein Zugang, Fehler bzw. keine Issues; '' sonst.
    /// </summary>
    class function GroupNote(const AGroup: TAtlasIssuesGroup): string; static;
    /// <summary>„PR #760 · CI grün“, „PR #760 (Entwurf)“; '' ohne Pull Request.</summary>
    class function PullRequestText(const APull: TAtlasTrackerPullRequest): string; static;
    class function ChecksColor(AChecks: TAtlasTrackerChecks): TColor; static;
    /// <summary>Kurztext „ATL-123 · 3 offen“ (Zustandskachel und Statusfeld); ohne aktuelles Issue „3 offen“
    /// mit dem Anbieter.</summary>
    class function TileText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Hinweis auf „Beginnen“: Branch nach Muster bzw. „Merkt … als aktuelles Issue“.</summary>
    class function StartHint(const AView: TAtlasIssuesView; const AIssue: TAtlasTrackerIssue): string; static;
    /// <summary>Hinweis an der Stelle AHit; '' ohne.</summary>
    class function HintAt(const AView: TAtlasIssuesView; const AHit: TAtlasIssuesHit): string; static;
    /// <summary>Titel des Bereichs: „Meine Issues · Projekt“; ohne Projekt „Meine Issues“.</summary>
    class function TitleText(const AProjectName: string): string; overload; static;
    /// <summary>Wie oben, mit Punkt davor, wenn AUnseen (#1271: neue Änderungen an einem Issue).</summary>
    class function TitleText(const AProjectName: string; AUnseen: Boolean): string; overload; static;
    /// <summary>Grund unter einem wieder geöffneten Issue (#2127): „Jana, vor 20 min: „…““, ohne Kommentar
    /// „Erledigt → In Bearbeitung, kein neuer Kommentar“.</summary>
    class function ReasonText(const AReopen: TAtlasTrackerReopen; ANowUtc: TDateTime): string; static;
    /// <summary>„Weiterarbeiten auf issue/ATL-2052“; ohne gemerkten Branch „Weiterarbeiten“.</summary>
    class function ContinueText(const AReopen: TAtlasTrackerReopen): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Tracker.Review,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.MyIssues.Strings,
  Atlas.UI.Tracker.TestResults.Strings,
  Atlas.UI.Tracker.TestResults;

const
  cSeparator = ' · ';
  cStaleTimeFormat = 'ddddd t';
  cQueryCaptionMore = '%s (%d+)';
  cQueryCaptionCount = '%s (%d)';
  cPullRequestPrefix = 'PR #';

/// <summary>Teile mit „ · “ verbunden; leere fallen weg.</summary>
function JoinParts(const AParts: TArray<string>): string;
var
  mPart: string;
begin
  Result := '';
  for mPart in AParts do
  begin
    if mPart = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + cSeparator;
    end;
    Result := Result + mPart;
  end;
end;

{ TAtlasIssuesHit }

class function TAtlasIssuesHit.Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TAtlasTrackerIssuesText }

class function TAtlasTrackerIssuesText.TitleText(const AProjectName: string): string;
begin
  if AProjectName = '' then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesTitle);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesTitleProject, [AProjectName]);
  end;
end;

class function TAtlasTrackerIssuesText.TitleText(const AProjectName: string; AUnseen: Boolean): string;
begin
  Result := TitleText(AProjectName);
  if AUnseen then
  begin
    Result := cUnseenMark + Result;
  end;
end;

class function TAtlasTrackerIssuesText.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesUnauthorized);
    TAtlasCiFetchError.NoCredentials:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesNoToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesNotFound);
    TAtlasCiFetchError.Invalid:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesInvalid);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsCiTimeout);
    TAtlasCiFetchError.Server:
      Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsCiServerError);
    TAtlasCiFetchError.UnknownProvider, TAtlasCiFetchError.NotConfigured:
      Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsCiUnknownProvider);
    TAtlasCiFetchError.None:
      Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsCiNotQueried);
  else
    Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsCiUnreachable);
  end;
end;

class function TAtlasTrackerIssuesText.GroupCaption(const AGroup: TAtlasIssuesGroup): string;
begin
  Result := Format(cQueryCaptionCount, [AGroup.Caption, AGroup.Total], TFormatSettings.Invariant);
end;

class function TAtlasTrackerIssuesText.GroupNote(const AGroup: TAtlasIssuesGroup): string;
begin
  Result := '';
  if AGroup.Querying then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssuesGroupQuerying);
  end
  else if (AGroup.Status = TAtlasIssuesStatus.NotConfigured) or ((AGroup.Status in [TAtlasIssuesStatus.Failed,
    TAtlasIssuesStatus.Stale]) and (AGroup.Error in [TAtlasCiFetchError.NoCredentials,
    TAtlasCiFetchError.Unauthorized])) then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssuesGroupNoAccess);
  end
  else if AGroup.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale] then
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssuesGroupFailed, [ErrorText(AGroup.Error)]);
  end
  else if AGroup.Status = TAtlasIssuesStatus.Waiting then
  begin
    Result := ErrorText(TAtlasCiFetchError.None);
  end
  else if AGroup.Total = 0 then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssuesGroupEmpty);
  end
  else if AGroup.More > 0 then
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.IssuesGroupMore, [AGroup.More]);
  end;
end;

class function TAtlasTrackerIssuesText.StatusText(const AView: TAtlasIssuesView): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  case AView.Status of
    TAtlasIssuesStatus.NotConfigured:
      mParts := nil;
    TAtlasIssuesStatus.Waiting:
      if AView.Querying then
      begin
        mParts := [TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesQuerying)];
      end
      else
      begin
        mParts := [AView.Tracker, TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsCiNotQueried)];
      end;
    TAtlasIssuesStatus.Failed:
      mParts := [AView.Tracker, ErrorText(AView.Error)];
    TAtlasIssuesStatus.Stale:
      mParts := [AView.Tracker, ErrorText(AView.Error),
        TAtlasTestResultsStrings.Fmt(TAtlasTestResultsTextId.WelcomeTestsStale,
        [FormatDateTime(cStaleTimeFormat, TTimeZone.Local.ToLocalTime(AView.At), FormatSettings)])];
  else
    if AView.Querying then
    begin
      mParts := [TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesQuerying)];
    end
    else if (Length(AView.Items) = 0) and (Length(AView.Groups) = 0) then
    begin
      mParts := [TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesEmpty)];
    end;
  end;
  if AView.Querying and (AView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale]) then
  begin
    mParts := mParts + [TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesQuerying)];
  end;
  Result := JoinParts(mParts);
end;

class function TAtlasTrackerIssuesText.NotConfiguredFooter(const AView: TAtlasIssuesView): string;
begin
  if AView.Project = '' then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesNoProject);
  end
  else if FooterIsAssign(AView) then
  begin
    // Weder .atlas noch persönliche Zuordnung: gleich zuordnen lassen (#1261).
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesAssign);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesNotConfigured);
  end;
end;

class function TAtlasTrackerIssuesText.ActiveFooter(const AView: TAtlasIssuesView; out AText: string): Boolean;
var
  mItem: TAtlasTrackerIssue;
begin
  // Aktuelles Issue, das die Liste nicht zeigt (z. B. schon geschlossen oder anderer Bearbeiter).
  AText := '';
  Result := AView.Active.Active;
  for mItem in AView.Items do
  begin
    Result := Result and not SameText(mItem.Key, AView.Active.Key);
  end;
  if Result then
  begin
    AText := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesActiveFooter,
      [Trim(AView.Active.Key + ' ' + AView.Active.Title)]);
  end;
end;

class function TAtlasTrackerIssuesText.FooterText(const AView: TAtlasIssuesView): string;
begin
  if AView.Notice <> '' then
  begin
    Result := AView.Notice;
  end
  else if AView.Status = TAtlasIssuesStatus.NotConfigured then
  begin
    Result := NotConfiguredFooter(AView);
  end
  else if not ActiveFooter(AView, Result) then
  begin
    Result := StartFooter(AView);
  end;
end;

class function TAtlasTrackerIssuesText.StartFooter(const AView: TAtlasIssuesView): string;
begin
  if Length(AView.Items) = 0 then
  begin
    Result := '';
  end
  else if (AView.Options.Start = TAtlasIssueStart.Remember) or
    ((AView.VcsKind <> TAtlasVcsKind.Git) and (AView.VcsKind <> TAtlasVcsKind.Svn)) then
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesFooterRemember);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesFooter);
  end;
end;

class function TAtlasTrackerIssuesText.FooterIsAssign(const AView: TAtlasIssuesView): Boolean;
begin
  Result := (AView.Notice = '') and (AView.Status = TAtlasIssuesStatus.NotConfigured) and (AView.Project <> '') and
    AView.CanAssign;
end;

class function TAtlasTrackerIssuesText.SourceText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if (AView.Status <> TAtlasIssuesStatus.NotConfigured) and (AView.QueryText <> '') then
  begin
    Result := JoinParts([AView.Connection, AView.TrackerProject,
      TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesSource, [AView.QueryText])]);
  end;
end;

class function TAtlasTrackerIssuesText.QueryCaption(const AName: string; ACount: Integer): string;
begin
  if ACount < 0 then
  begin
    Result := AName;
  end
  else if ACount >= TAtlasMyIssues.cMaxItems then
  begin
    Result := Format(cQueryCaptionMore, [AName, TAtlasMyIssues.cMaxItems], TFormatSettings.Invariant);
  end
  else
  begin
    Result := Format(cQueryCaptionCount, [AName, ACount], TFormatSettings.Invariant);
  end;
end;

class function TAtlasTrackerIssuesText.ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean;
begin
  Result := AView.Picker and (AView.Status <> TAtlasIssuesStatus.NotConfigured) and (AView.QueryIndex >= 0) and
    (AView.QueryIndex <= High(AView.Queries));
end;

class function TAtlasTrackerIssuesText.PullRequestText(const APull: TAtlasTrackerPullRequest): string;
begin
  Result := '';
  if APull.Number <= 0 then
  begin
    Exit;
  end;
  Result := cPullRequestPrefix + IntToStr(APull.Number);
  if APull.Draft then
  begin
    Result := Result + TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesDraft);
  end;
  case APull.Checks of
    TAtlasTrackerChecks.Success:
      Result := Result + cSeparator + TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesChecksSuccess);
    TAtlasTrackerChecks.Failure:
      Result := Result + cSeparator + TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesChecksFailure);
    TAtlasTrackerChecks.Pending:
      Result := Result + cSeparator + TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesChecksPending);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasTrackerIssuesText.ChecksColor(AChecks: TAtlasTrackerChecks): TColor;
begin
  case AChecks of
    TAtlasTrackerChecks.Success:
      Result := cGreenColor;
    TAtlasTrackerChecks.Failure:
      Result := cRedColor;
    TAtlasTrackerChecks.Pending:
      Result := cYellowColor;
  else
    Result := cGrayColor;
  end;
end;

class function TAtlasTrackerIssuesText.TileText(const AView: TAtlasIssuesView): string;
var
  mHead: string;
begin
  mHead := AView.Active.Key;
  if mHead = '' then
  begin
    mHead := AView.Tracker;
  end;
  if mHead = '' then
  begin
    mHead := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesTitle);
  end;
  Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesStatusTile, [mHead, AView.OpenCount]);
end;

class function TAtlasTrackerIssuesText.StartHint(const AView: TAtlasIssuesView;
  const AIssue: TAtlasTrackerIssue): string;
var
  mPlan: TAtlasIssueStartPlan;
begin
  // Im Prüfzustand (#2126) steht dort „Prüfen …“.
  if TAtlasTrackerReview.Reviews(AView, AIssue) then
  begin
    Exit(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerReviewHint));
  end;
  mPlan := TAtlasMyIssues.PlanStart(AView.VcsKind, AView.Options, AIssue);
  if (mPlan.Mode = TAtlasIssueStart.Branch) and mPlan.Valid then
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesHintStart, [mPlan.Branch]);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesHintRemember, [AIssue.Key]);
  end;
end;

class function TAtlasTrackerIssuesText.HintAt(const AView: TAtlasIssuesView; const AHit: TAtlasIssuesHit): string;
begin
  case AHit.Kind of
    TAtlasIssuesHitKind.Key:
      if AView.Options.Preview then
      begin
        Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHintKeyPreview);
      end
      else
      begin
        Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHintKey);
      end;
    TAtlasIssuesHitKind.PullRequest:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHintPullRequest);
    TAtlasIssuesHitKind.Start:
      Result := StartHint(AView, AView.Items[AHit.Index]);
    TAtlasIssuesHitKind.Row:
      begin
        Result := AView.Items[AHit.Index].Key + ' ' + AView.Items[AHit.Index].Title;
        if AView.IsUnseen(AView.Items[AHit.Index].Key) then
        begin
          Result := Result + sLineBreak + TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.IssueNotifyUnseenHint);
        end;
      end;
    TAtlasIssuesHitKind.Assign:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHintAssign);
    TAtlasIssuesHitKind.Filter:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHintFilter);
    TAtlasIssuesHitKind.Continue:
      Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesContinueHint,
        [AView.Items[AHit.Index].Key]);
    TAtlasIssuesHitKind.Dismiss:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesReopenedReadHint);
    TAtlasIssuesHitKind.Reason:
      Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesReopenedCommentHint);
  else
    Result := '';
  end;
end;

class function TAtlasTrackerIssuesText.ReasonText(const AReopen: TAtlasTrackerReopen; ANowUtc: TDateTime): string;
var
  mWho: string;
begin
  if AReopen.Comment <> '' then
  begin
    mWho := AReopen.CommentBy;
    if mWho = '' then
    begin
      mWho := '?';
    end;
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesReopenedComment, [mWho,
      TAtlasTrackerTestResultsText.AgoText(AReopen.CommentAt, ANowUtc), AReopen.Comment]);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesReopenedState, [AReopen.Previous,
      AReopen.State]);
  end;
end;

class function TAtlasTrackerIssuesText.ContinueText(const AReopen: TAtlasTrackerReopen): string;
begin
  if AReopen.Branch <> '' then
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesContinueOn, [AReopen.Branch]);
  end
  else
  begin
    Result := TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesContinue);
  end;
end;

class function TAtlasTrackerIssuesText.FilterText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if AView.Filter <> '' then
  begin
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesFilter, [AView.Filter]);
  end;
end;

end.
