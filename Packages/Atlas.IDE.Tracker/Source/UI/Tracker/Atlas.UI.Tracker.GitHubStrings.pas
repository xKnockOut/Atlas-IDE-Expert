unit Atlas.UI.Tracker.GitHubStrings;

// Oberflächentexte des GitHub-Anbieters im Tracker auf Deutsch und Englisch:
// Abschnitt „Abschluss“ im Beenden-Dialog mit Schließgrund (#2135), Status
// im Projekt und seine Einstellungen (#2134), verknüpfter Branch beim
// Beginnen und im Reiter „Entwicklung“ (#2138). Wie die übrigen Texttabellen
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
    LinkCreated, LinkFound, LinkExists, LinkForeign, LinkDenied, LinkFailed, LinkFetchFailed, DevelopmentLinked);

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
     'mit dem Issue verknüpft (GitHub)'),
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
     'linked to the issue (GitHub)'));

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
