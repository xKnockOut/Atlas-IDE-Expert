unit Atlas.UI.Tracker.GitHubStrings;

// Oberflächentexte des GitHub-Anbieters im Tracker auf Deutsch und Englisch:
// Abschnitt „Abschluss“ im Beenden-Dialog mit Schließgrund (#2135), Status
// im Projekt und seine Einstellungen (#2134), verknüpfter Branch beim
// Beginnen und im Reiter „Entwicklung“ (#2138), Pull Request beim Beenden
// und seine Einstellungen (#2136). Wie die übrigen Texttabellen
// des Trackers (Atlas.UI.Tracker.<Feature>.Strings) bestimmt Base die Sprache
// (`TAtlasStrings.Language`).

interface

uses
  Atlas.Core.Localization.Language,
  Atlas.Core.Tracker.Contract;

{$SCOPEDENUMS ON}

type
  TAtlasGitHubTextId = (
    EndClose, EndCloseCompleted, EndCloseNotPlanned, EndCloseDuplicate, EndCloseKeepOpen, EndDuplicateHint,
    EndDuplicateMissing, EndDuplicateUnknown, EndDuplicateComment, EndSendDuplicate, EndSendNotPlanned, PartClosed,
    PartClosedNotPlanned, PartClosedDuplicate, PartDuplicateFallback, ProjectStatus, ProjectStatusNew,
    ProjectStatusSame, ProjectAdded, ProjectSeveral, ProjectDenied, ProjectMissingOption, SettingsStateTarget,
    SettingsStateTargetProject, SettingsStateTargetLabel, SettingsProject, SettingsAddToProject, SettingsLinkBranch,
    LinkCreated, LinkFound, LinkExists, LinkForeign, LinkDenied, LinkFailed, LinkFetchFailed, DevelopmentLinked,
    EndPull, EndPullRoute, EndPullDefaultBase, EndPullTitle, EndPullBody, EndPullCopyIssue, EndPullReviewer,
    EndPullDraft, EndPullExisting, EndPullStep, EndPullDirty, EndPullForeign, EndPullPushFailed, EndSendPull,
    EndCloseByMerge, PullCreated, PullExisting, PullDecorateFailed, PullReviewersFailed, PullDraftYes, PullDraftNo,
    PartPull, SettingsCreatePr, SettingsPrBase, SettingsPrBody, SettingsPrDraft);

{$SCOPEDENUMS OFF}

  TAtlasGitHubStrings = class
  public
    class function Text(AId: TAtlasGitHubTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasGitHubTextId; const AArgs: array of const): string; static;
    /// <summary>Zeilen der Meldung zum Status im Projekt (#2134) für AKey; leer, wenn kein Projekt berührt wurde.
    /// </summary>
    class function ProjectLines(const AKey: string; const AStatus: TAtlasTrackerProjectStatus): TArray<string>;
      static;
    /// <summary>Zeile der Meldung zum verknüpften Branch (#2138) für AKey; '' bei None. ARepository: "owner/repo"
    /// (Foreign), AReason: Grund bei Failed bzw. wenn Abruf oder Auschecken scheiterten (AFetched False).
    /// </summary>
    class function LinkLine(const AKey, ARepository, AReason: string; const ALink: TAtlasTrackerBranchLink;
      AFetched: Boolean): string; static;
    /// <summary>Zeilen der Meldung zum Pull Request beim Beenden (#2136) für AKey; leer, wenn keiner steht.
    /// </summary>
    class function PullLines(const AKey: string; const APull: TAtlasTrackerPullResult): TArray<string>;
      static;
    /// <summary>Grund, warum kein Pull Request angelegt wurde (Dirty, Foreign, PushFailed); '' sonst. AHead:
    /// Branch, ARepository: "owner/repo".</summary>
    class function PullProblem(const APull: TAtlasTrackerPullResult; const AHead, ARepository: string): string;
      static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasGitHubTextId] of string = (
    ('Abschluss:',
     'Erledigt',
     'Nicht geplant',
     'Duplikat von',
     'Offen lassen',
     'Original, z. B. #123',
     'Bitte das Original angeben (z. B. #123), nicht das Issue selbst.',
     'Das Original %s gibt es im Repository nicht.',
     'Duplikat von %s.',
     'Als Duplikat schließen',
     'Als nicht geplant schließen',
     'geschlossen',
     'als nicht geplant geschlossen',
     'als Duplikat von %s geschlossen',
     'GitHub nahm den Duplikat-Verweis nicht an: als nicht geplant geschlossen, Verweis als Kommentar',
     '%s: Status im Projekt „%s“ %s → %s',
     '%s: Status im Projekt „%s“ auf %s gesetzt',
     '%s: Status im Projekt „%s“ ist schon %s',
     '%s: in das Projekt „%s“ aufgenommen',
     '%s liegt in mehreren Projekten; gesetzt in „%s“ (anderes über issues.github.project)',
     '%s: Projekte nicht lesbar (Token ohne Berechtigung „project“), Zustand als Label gesetzt',
     '%s: Das Statusfeld im Projekt „%s“ hat keine Option „%s“; nichts geändert.',
     'Zustand bei GitHub führen in:',
     'Projektfeld „Status“, sonst Label',
     'Label',
     'Projekt (GitHub):',
     'Issues ohne Projekt beim Beginnen in das Projekt aufnehmen',
     'Branch beim Beginnen auf GitHub anlegen und mit dem Issue verknüpfen',
     '%s: Branch %s auf GitHub angelegt und mit dem Issue verknüpft',
     '%s: mit dem Issue verknüpften Branch %s von GitHub ausgecheckt',
     '%s: Branch %s gibt es schon; nicht mit dem Issue verknüpft',
     '%s: origin ist nicht das Repository %s; Branch nur lokal angelegt',
     '%s: Das Token darf keine Branches anlegen (Recht „Contents: write“); Branch nur lokal angelegt',
     '%s: Branch nicht auf GitHub angelegt (%s); Branch nur lokal angelegt',
     '%s: Branch %s liegt auf GitHub, Abruf oder Auschecken scheiterte (%s); Branch nur lokal angelegt',
     'mit dem Issue verknüpft (GitHub)',
     'Pull Request anlegen',
     'Von → nach:',
     'Standard-Branch',
     'Titel:',
     'Text:',
     'Labels und Meilenstein des Issues übernehmen',
     'Prüfer:',
     'als Entwurf',
     'Offener Pull Request: %s',
     'Pull Request',
     'Die Arbeitskopie hat ungesicherte Änderungen: erst committen, dann erneut senden.',
     'origin zeigt nicht auf %s (Fork?); den Pull Request bitte im Browser anlegen.',
     'Push von %s gescheitert (%s); nichts angelegt.',
     'Pushen und PR anlegen',
     'Schließt der Merge',
     '%s: Pull Request #%d angelegt → %s (Entwurf: %s) %s',
     '%s: Branch gepusht; Pull Request #%d ist schon offen %s',
     '%s: Labels und Meilenstein nicht in den Pull Request übernommen',
     '%s: Prüfer nicht angefragt (Benutzer ohne Zugriff auf das Repository?)',
     'ja',
     'nein',
     'Pull Request #%d',
     'Beim Beenden einen Pull Request anlegen (vorab angehakt)',
     'Ziel-Branch des Pull Requests:',
     'Text des Pull Requests:',
     'Pull Request als Entwurf vorbelegen'),
    ('Close as:',
     'Completed',
     'Not planned',
     'Duplicate of',
     'Keep open',
     'Original, e.g. #123',
     'Enter the original (e.g. #123), not this issue itself.',
     'The original %s does not exist in the repository.',
     'Duplicate of %s.',
     'Close as duplicate',
     'Close as not planned',
     'closed',
     'closed as not planned',
     'closed as duplicate of %s',
     'GitHub did not accept the duplicate link: closed as not planned, link added as a comment',
     '%s: status in project "%s" %s → %s',
     '%s: status in project "%s" set to %s',
     '%s: status in project "%s" already is %s',
     '%s: added to project "%s"',
     '%s is in several projects; set in "%s" (choose another with issues.github.project)',
     '%s: projects not readable (token without "project" scope), state set as a label',
     '%s: The status field in project "%s" has no option "%s"; nothing changed.',
     'Keep GitHub state in:',
     'Project field "Status", else label',
     'Label',
     'Project (GitHub):',
     'Add issues without a project to the project when starting',
     'Create the branch on GitHub when starting and link it to the issue',
     '%s: branch %s created on GitHub and linked to the issue',
     '%s: checked out branch %s linked to the issue from GitHub',
     '%s: branch %s already exists; not linked to the issue',
     '%s: origin is not the repository %s; branch created locally only',
     '%s: the token may not create branches ("Contents: write" permission); branch created locally only',
     '%s: branch not created on GitHub (%s); branch created locally only',
     '%s: branch %s is on GitHub, fetch or checkout failed (%s); branch created locally only',
     'linked to the issue (GitHub)',
     'Create pull request',
     'From → to:',
     'default branch',
     'Title:',
     'Text:',
     'Copy labels and milestone of the issue',
     'Reviewer:',
     'as draft',
     'Open pull request: %s',
     'Pull request',
     'The working copy has uncommitted changes: commit first, then send again.',
     'origin does not point to %s (fork?); please create the pull request in the browser.',
     'Push of %s failed (%s); nothing created.',
     'Push and create PR',
     'Closed by the merge',
     '%s: pull request #%d created → %s (draft: %s) %s',
     '%s: branch pushed; pull request #%d is already open %s',
     '%s: labels and milestone not copied to the pull request',
     '%s: reviewer not requested (user without access to the repository?)',
     'yes',
     'no',
     'pull request #%d',
     'Create a pull request when finishing (checked in advance)',
     'Target branch of the pull request:',
     'Text of the pull request:',
     'Mark the pull request as draft in advance'));

{ TAtlasGitHubStrings }

class function TAtlasGitHubStrings.Text(AId: TAtlasGitHubTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasGitHubStrings.Fmt(AId: TAtlasGitHubTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

class function TAtlasGitHubStrings.ProjectLines(const AKey: string;
  const AStatus: TAtlasTrackerProjectStatus): TArray<string>;
begin
  Result := nil;
  if AStatus.Denied then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.ProjectDenied, [AKey])];
  end;
  if (AStatus.Project = '') or (AStatus.MissingOption <> '') then
  begin
    Exit;
  end;
  if AStatus.Added then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.ProjectAdded, [AKey, AStatus.Project])];
  end;
  if AStatus.Several then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.ProjectSeveral, [AKey, AStatus.Project])];
  end;
  if AStatus.After = '' then
  begin
    Exit;
  end;
  if AStatus.Before = '' then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.ProjectStatusNew, [AKey, AStatus.Project, AStatus.After])];
  end
  else if SameText(AStatus.Before, AStatus.After) then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.ProjectStatusSame, [AKey, AStatus.Project, AStatus.After])];
  end
  else
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.ProjectStatus, [AKey, AStatus.Project, AStatus.Before,
      AStatus.After])];
  end;
end;

class function TAtlasGitHubStrings.PullLines(const AKey: string;
  const APull: TAtlasTrackerPullResult): TArray<string>;
const
  cDraft: array[Boolean] of TAtlasGitHubTextId = (TAtlasGitHubTextId.PullDraftNo, TAtlasGitHubTextId.PullDraftYes);
begin
  Result := nil;
  case APull.Outcome of
    TAtlasTrackerPullOutcome.Created:
      Result := Result + [Fmt(TAtlasGitHubTextId.PullCreated, [AKey, APull.Number, APull.Base,
        Text(cDraft[APull.Draft]), APull.Url])];
    TAtlasTrackerPullOutcome.Existing:
      Result := Result + [Fmt(TAtlasGitHubTextId.PullExisting, [AKey, APull.Number, APull.Url])];
  else
    Exit;
  end;
  if APull.DecorateFailed then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.PullDecorateFailed, [AKey])];
  end;
  if APull.ReviewersFailed then
  begin
    Result := Result + [Fmt(TAtlasGitHubTextId.PullReviewersFailed, [AKey])];
  end;
end;

class function TAtlasGitHubStrings.PullProblem(const APull: TAtlasTrackerPullResult; const AHead,
  ARepository: string): string;
begin
  case APull.Outcome of
    TAtlasTrackerPullOutcome.Dirty:
      Result := Text(TAtlasGitHubTextId.EndPullDirty);
    TAtlasTrackerPullOutcome.Foreign:
      Result := Fmt(TAtlasGitHubTextId.EndPullForeign, [ARepository]);
    TAtlasTrackerPullOutcome.PushFailed:
      Result := Fmt(TAtlasGitHubTextId.EndPullPushFailed, [AHead, APull.Message]);
  else
    Result := '';
  end;
end;

class function TAtlasGitHubStrings.LinkLine(const AKey, ARepository, AReason: string;
  const ALink: TAtlasTrackerBranchLink; AFetched: Boolean): string;
begin
  case ALink.Outcome of
    TAtlasTrackerBranchLinkOutcome.Created, TAtlasTrackerBranchLinkOutcome.Found:
      if not AFetched then
      begin
        Result := Fmt(TAtlasGitHubTextId.LinkFetchFailed, [AKey, ALink.Branch, AReason]);
      end
      else if ALink.Outcome = TAtlasTrackerBranchLinkOutcome.Created then
      begin
        Result := Fmt(TAtlasGitHubTextId.LinkCreated, [AKey, ALink.Branch]);
      end
      else
      begin
        Result := Fmt(TAtlasGitHubTextId.LinkFound, [AKey, ALink.Branch]);
      end;
    TAtlasTrackerBranchLinkOutcome.Exists:
      Result := Fmt(TAtlasGitHubTextId.LinkExists, [AKey, ALink.Branch]);
    TAtlasTrackerBranchLinkOutcome.Foreign:
      Result := Fmt(TAtlasGitHubTextId.LinkForeign, [AKey, ARepository]);
    TAtlasTrackerBranchLinkOutcome.Denied:
      Result := Fmt(TAtlasGitHubTextId.LinkDenied, [AKey]);
    TAtlasTrackerBranchLinkOutcome.Failed:
      Result := Fmt(TAtlasGitHubTextId.LinkFailed, [AKey, AReason]);
  else
    Result := '';
  end;
end;

end.
