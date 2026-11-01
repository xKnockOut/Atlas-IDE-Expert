unit Atlas.IDE.Tracker.IssueCommands;

// Befehle von „Meine Issues“ (aus Atlas.IDE.Tracker.MyIssues gelöst, #1455):
// Issue anzeigen (Vorschau „Atlas-Issue“ bzw. Browser, #1264), Issue-Kennungen
// im Editor (#1265: CodeTarget, ShowIssue, BrowseIssue, StartIssue), Links
// "#312" in Begründungen (#1123, IssueUrl), „An Issue anhängen“ (#1276),
// Browser und Pull-Request aus der Liste und der Filter der Sprint-Kachel.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Attach,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices;

type
  TAtlasIdeIssueCommands = class
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
    /// <summary>Issue-Links "#312" in Begründungen (#1123) anmelden.</summary>
    procedure Start;
    /// <summary>Issue-Links abmelden; ohne Tracker sind sie nicht anklickbar.</summary>
    class procedure Stop; static;
    /// <summary>Adresse des Issues AKey im Tracker des aktuellen Projekts (#1123); '' ohne Tracker. Ohne Netz.
    /// </summary>
    function IssueUrl(const AKey: string): string;
    /// <summary>Befehl Atlas.IssueShow (#1264): Kennung abfragen und das Issue aus dem Tracker des aktiven
    /// Projekts in „Atlas-Issue“ zeigen.</summary>
    procedure ShowPreviewPrompt;
    /// <summary>Tracker für Issue-Kennungen im Editor (#1265): das aktive Projekt der IDE, sonst das des Bereichs;
    /// zwischengespeichert, ohne Netz. False vor Start und ohne Tracker.</summary>
    function CodeTarget(out ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Issue AKey zeigen: Vorschau „Atlas-Issue“ mit issues.preview, sonst im Browser.</summary>
    procedure ShowIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>Seite des Issues AKey im Browser (nur aus der eingetragenen Adresse).</summary>
    procedure BrowseIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>„Beginnen“ für AKey wie in „Meine Issues“; der Titel aus dem Zwischenspeicher bzw. einer
    /// Kurzabfrage.</summary>
    procedure StartIssue(const ATarget: TAtlasTrackerTarget; const AKey: string); overload;
    /// <summary>„gleich beginnen“ nach „Issue anlegen …“ (#1268): wie „Beginnen“ mit issues.start.</summary>
    procedure StartIssue(const AIssue: TAtlasTrackerIssue); overload;
    /// <summary>Befehl Atlas.IssueAttach (#1276): Dialog „An Issue anhängen“ für den Tracker des aktiven Projekts,
    /// das aktuelle Issue vorgewählt.</summary>
    procedure AttachPrompt;
    /// <summary>Dialog „An Issue anhängen“ für AKey bei ATarget mit AFiles vorgewählt (Absturzfall nach „Issue
    /// anlegen“, #1355).</summary>
    procedure AttachFiles(const ATarget: TAtlasTrackerTarget; const AKey: string;
      const AFiles: TArray<TAtlasAttachFile>);
    /// <summary>Seite von AIssue im Browser; die Meldung dazu gilt als gesehen (#1271).</summary>
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    /// <summary>AIssue in „Atlas-Issue“, mit Punkt am ersten neuen Kommentar (#1271).</summary>
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    /// <summary>Liste auf AIssues beschränken (Sprint-Kachel); ohne den Bereich öffnet es das Board.</summary>
    procedure SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
    procedure ClearFilter;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.Attach;

{ TAtlasIdeIssueCommands }

constructor TAtlasIdeIssueCommands.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
end;

procedure TAtlasIdeIssueCommands.Start;
begin
  // Eigene Routine: Die anonyme Methode hält nur Self, keinen Rahmen des Aufrufers.
  TAtlasDocIssueLinks.SetResolver(
    function(const AKey: string): string
    begin
      Result := IssueUrl(AKey);
    end);
end;

class procedure TAtlasIdeIssueCommands.Stop;
begin
  TAtlasDocIssueLinks.Clear;
end;

function TAtlasIdeIssueCommands.IssueUrl(const AKey: string): string;
var
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
begin
  Result := '';
  if not FContext.Started or (AKey = '') then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(FContext.CurrentProject);
  mProvider := FContext.ProviderOf(mTarget.Provider);
  if mProvider <> nil then
  begin
    Result := mProvider.IssuePage(mTarget, AKey);
  end;
end;

procedure TAtlasIdeIssueCommands.ShowPreviewPrompt;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
      mInput, mKey: string;
    begin
      if not FContext.Started or (FServices.Preview = nil) or not TAtlasIdeIssuePreview.Active then
      begin
        Exit;
      end;
      mProvider := FContext.ActiveTarget(mTarget);
      if mProvider = nil then
      begin
        FContext.Report(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoTracker));
        Exit;
      end;
      mInput := '';
      if not InputQuery(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCaption),
        TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewPrompt, [TAtlasIssuePreview.KeyExample(mTarget.Provider)]),
        mInput) then
      begin
        Exit;
      end;
      mKey := TAtlasIssuePreview.KeyOf(mTarget.Provider, mInput);
      if mKey = '' then
      begin
        FContext.Report(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewInvalidKey, [Trim(mInput)]));
        Exit;
      end;
      FServices.Preview.Show(mTarget, mKey);
    end);
end;

function TAtlasIdeIssueCommands.CodeTarget(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mProject: string;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  Result := False;
  if not FContext.Started then
  begin
    Exit;
  end;
  // Wie „Issue anzeigen …“: das aktive Projekt der IDE, sonst das des Bereichs.
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
  begin
    mProject := FContext.CurrentProject;
  end;
  ATarget := FContext.CachedTargetOf(mProject).Target;
  Result := FContext.ProviderOf(ATarget.Provider) <> nil;
end;

procedure TAtlasIdeIssueCommands.ShowIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if not FContext.Started or (AKey = '') then
  begin
    Exit;
  end;
  if FServices.Options.Preview then
  begin
    FServices.Preview.Show(ATarget, AKey);
  end
  else
  begin
    BrowseIssue(ATarget, AKey);
  end;
end;

procedure TAtlasIdeIssueCommands.BrowseIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mProvider: IAtlasTrackerProvider;
  mUrl: string;
begin
  if not FContext.Started or (AKey = '') then
  begin
    Exit;
  end;
  mProvider := FContext.ProviderOf(ATarget.Provider);
  if mProvider = nil then
  begin
    Exit;
  end;
  // Nur die Seite aus der eingetragenen Adresse, nie etwas aus der Antwort des Trackers.
  mUrl := mProvider.IssuePage(ATarget, AKey);
  if TAtlasIssuePreview.MayBrowse(mUrl) then
  begin
    TAtlasIdeIssuesTargets.OpenPage(mUrl);
  end;
end;

/// <summary>Nach der Kurzabfrage von AKey beginnen (eigene Routine: hält nur diese Werte).</summary>
function StartAfterLookup(const AKeep: IAtlasIdeIssuesActions; AContext: TAtlasIdeIssuesContext;
  AServices: TAtlasIdeIssuesServices; const AKey: string): TAtlasIssueLookupDone;
var
  mKeep: IAtlasIdeIssuesActions;
  mKey: string;
begin
  mKeep := AKeep;
  mKey := AKey;
  Result :=
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if (mKeep = nil) or not AContext.CanStart then
      begin
        Exit;
      end;
      if ASucceeded then
      begin
        mKeep.Start(ADetails.Issue, AServices.Options.Start);
      end
      else
      begin
        AContext.Report(TAtlasIssueTip.ErrorText(AError, mKey));
      end;
    end;
end;

procedure TAtlasIdeIssueCommands.StartIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mDetails: TAtlasTrackerDetails;
begin
  if not FContext.CanStart or (AKey = '') or (FServices.Preview = nil) or (FContext.Actions = nil) then
  begin
    Exit;
  end;
  // Der Titel gehört in Branch-Namen und Präfix: aus dem Zwischenspeicher, sonst erst fragen.
  if FServices.Preview.Peek(ATarget, AKey, mDetails) then
  begin
    FContext.Actions.Start(mDetails.Issue, FServices.Options.Start);
  end
  else
  begin
    FServices.Preview.Lookup(ATarget, AKey, StartAfterLookup(FContext.Actions, FContext, FServices, AKey));
  end;
end;

procedure TAtlasIdeIssueCommands.StartIssue(const AIssue: TAtlasTrackerIssue);
begin
  if FContext.CanStart and (FContext.Actions <> nil) then
  begin
    FContext.Actions.Start(AIssue, FServices.Options.Start);
  end;
end;

procedure TAtlasIdeIssueCommands.AttachPrompt;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
      mData: TAtlasIssuesView;
      mKey: string;
    begin
      if not FContext.Started or (FServices.Attach = nil) or not TAtlasIdeIssueAttach.Active or
        (FContext.Actions = nil) then
      begin
        Exit;
      end;
      mProvider := FContext.ActiveTarget(mTarget);
      if mProvider = nil then
      begin
        FContext.Report(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoTracker));
        Exit;
      end;
      // Das aktuelle Issue vorwählen, wenn es zum selben Tracker gehört.
      mKey := '';
      mData := FContext.Actions.ViewOf(FContext.CurrentProject);
      if mData.Active.Active and SameText(FContext.TargetOf(FContext.CurrentProject).Provider, mTarget.Provider) then
      begin
        mKey := mData.Active.Key;
      end;
      FServices.Attach.Execute(mTarget, mKey);
    end);
end;

procedure TAtlasIdeIssueCommands.AttachFiles(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const AFiles: TArray<TAtlasAttachFile>);
begin
  if FContext.Started and (FServices.Attach <> nil) and TAtlasIdeIssueAttach.Active then
  begin
    FServices.Attach.Execute(ATarget, AKey, AFiles);
  end;
end;

procedure TAtlasIdeIssueCommands.Browse(const AIssue: TAtlasTrackerIssue);
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
    begin
      mTarget := FContext.TargetOf(FContext.CurrentProject);
      mProvider := FContext.ProviderOf(mTarget.Provider);
      if mProvider = nil then
      begin
        Exit;
      end;
      if FServices.Notify <> nil then
      begin
        FServices.Notify.Seen(mTarget, mIssue.Key);
      end;
      TAtlasIdeIssuesTargets.OpenPage(mProvider.IssuePage(mTarget, mIssue.Key));
    end);
end;

procedure TAtlasIdeIssueCommands.Preview(const AIssue: TAtlasTrackerIssue);
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mAnchor: TDateTime;
    begin
      if not FContext.Started or (FServices.Preview = nil) or not TAtlasIdeIssuePreview.Active then
      begin
        Exit;
      end;
      mTarget := FContext.TargetOf(FContext.CurrentProject);
      // Mit Punkt (#1271): am ersten neuen Kommentar öffnen, der Punkt verschwindet.
      mAnchor := 0;
      if FServices.Notify <> nil then
      begin
        mAnchor := FServices.Notify.AnchorOf(mTarget, mIssue.Key);
        FServices.Notify.Seen(mTarget, mIssue.Key);
      end;
      FServices.Preview.Show(mTarget, mIssue.Key, mAnchor);
    end);
end;

procedure TAtlasIdeIssueCommands.BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
    begin
      mTarget := FContext.TargetOf(FContext.CurrentProject);
      mProvider := FContext.ProviderOf(mTarget.Provider);
      if (mProvider <> nil) and (mIssue.PullRequest.Number > 0) then
      begin
        TAtlasIdeIssuesTargets.OpenPage(mProvider.PullRequestPage(mTarget, mIssue.PullRequest.Number));
      end;
    end);
end;

procedure TAtlasIdeIssueCommands.SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
var
  mFilter: TAtlasIssuesFilter;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  // Ohne den Bereich „Meine Issues“ zeigt das Board die Karten.
  if not TAtlasIdeIssuesTargets.Active then
  begin
    if FServices.Board <> nil then
    begin
      FServices.Board.Show;
    end;
    Exit;
  end;
  mFilter.Caption := ACaption;
  mFilter.Issues := AIssues;
  mFilter.Project := FContext.CurrentProject;
  FContext.Filter := mFilter;
  FContext.Changed;
end;

procedure TAtlasIdeIssueCommands.ClearFilter;
begin
  FContext.Filter := Default(TAtlasIssuesFilter);
  FContext.Changed;
end;

end.
