unit Atlas.IDE.Tracker.PaletteSearch;

// Issues in der Befehlspalette suchen (#1270, issues.paletteSearch): Quelle
// der Palette (IAtlasPaletteSource) für den Tracker des aktiven Projekts.
// - Auslöser und Anfrage aus Atlas.Core.Tracker.PaletteSearch: "#Text",
//   "#42", bei YouTrack "ATL-12" und "ATL-Text"; andere Eingaben bleiben
//   bei den Befehlen, ohne Netz.
// - Die Abfrage beim Tracker (entprellt, eine Anfrage zur Zeit, Zeitgrenze
//   5 s, letzte Antwort) steht in Atlas.IDE.Tracker.PaletteSearchFetch. Bis
//   zur Antwort steht „Suche im Tracker …“ in der Gruppe „Issues“ unter den
//   Befehlen; die Befehle erscheinen sofort.
// - Leeres "#": die zuletzt in „Atlas-Issue“ geöffneten Issues (höchstens
//   10, aus der Vorschau) ohne Netzabfrage.
// - Enter öffnet die Vorschau (#1264; mit issues.preview aus den Browser),
//   Strg+Enter beginnt das Issue wie in „Meine Issues“, Umschalt+Enter öffnet
//   den Browser, Strg+C kopiert die Kennung.
// - Andere Eingaben zeigen die Übergänge des aktuellen Issues (#2124, Hook
//   States, issues.statusState) als Gruppe „Aktuelles Issue“; Enter führt
//   den Übergang aus (Hook StateRun). Ohne Netz, auch mit issues.paletteSearch
//   aus.
// - Mit issues.paletteSearch aus gibt es keine Suche und keinen Netzzugriff.
// Ziel, Transport, Vorschau, „Beginnen“ und die zuletzt geöffneten Issues
// kommen über Hooks („Meine Issues“).

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.PaletteSearchPlan,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.IDE.Tracker.PaletteSearchFetch,
  Atlas.Core.Notifications.MessageSink;

type
  /// <summary>Tracker des aktiven Projekts; nil ohne Anbieter bzw. Server.</summary>
  TAtlasIssueSearchTargetHook = reference to function(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
  TAtlasIssueSearchRecentHook = reference to function(const ATarget: TAtlasTrackerTarget):
    TArray<TAtlasTrackerIssue>;
  TAtlasIssueSearchShowHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string);
  /// <summary>Übergänge des aktuellen Issues, die zur Eingabe passen (#2124); nil ohne.</summary>
  TAtlasIssueSearchStatesHook = reference to function(const APattern: string): TArray<TAtlasCommand>;

  TAtlasIssueSearchHooks = record
    Target: TAtlasIssueSearchTargetHook;
    /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Ohne Dialog.</summary>
    Transport: TAtlasIssuePreviewTransportHook;
    /// <summary>Issue in „Atlas-Issue“ zeigen.</summary>
    Show: TAtlasIssueSearchShowHook;
    /// <summary>issues.preview an (sonst öffnet Enter den Browser).</summary>
    PreviewActive: TFunc<Boolean>;
    Recent: TAtlasIssueSearchRecentHook;
    /// <summary>„Beginnen“ wie in „Meine Issues“.</summary>
    Start: TProc<TAtlasTrackerIssue>;
    CanStart: TFunc<Boolean>;
    /// <summary>Zeile in der Meldungsansicht.</summary>
    Report: TProc<string>;
    States: TAtlasIssueSearchStatesHook;
    /// <summary>Zeile aus States ausführen; False, wenn sie nicht von dort stammt.</summary>
    StateRun: TFunc<string, Boolean>;
  end;

  TAtlasIdeIssueSearch = class(TInterfacedObject, IAtlasPaletteSource)
  private
    FHooks: TAtlasIssueSearchHooks;
    FMessage: TAtlasMessageSink;
    FStarted: Boolean;
    FShow: TProc<TAtlasPaletteGroup>;
    FFetch: TAtlasIdeIssueSearchFetch;
    FFetchRef: IInterface;
    FIssues: TArray<TAtlasTrackerIssue>;
    procedure Answered(const AQuery: TAtlasIssueSearchQuery; AAnswer: TAtlasIssueSearchAnswer;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
    procedure ShowIssues(const ATitle: string; const AQuery: TAtlasIssueSearchQuery;
      const AIssues: TArray<TAtlasTrackerIssue>);
    procedure ShowStatus(const AStatus: string);
    procedure ShowGroup(const AGroup: TAtlasPaletteGroup);
    /// <summary>Übergänge des aktuellen Issues zur Eingabe (#2124); ohne passende keine Gruppe.</summary>
    procedure ShowStates(const APattern: string);
    /// <summary>Ohne Tracker gehört "#…" trotzdem nicht zu den Befehlen: Hinweis statt stiller Leere.</summary>
    procedure ShowNoTracker(const APattern: string);
    /// <summary>Zuletzt gesehene Issues ("#" allein).</summary>
    procedure ShowRecent(const AQuery: TAtlasIssueSearchQuery);
    /// <summary>Kennung oder Text: dieselbe Eingabe wie zuletzt aus der letzten Antwort, sonst nach der Wartezeit
    /// fragen.</summary>
    procedure ShowOrSearch(const AQuery: TAtlasIssueSearchQuery);
    /// <summary>Übergang des aktuellen Issues (#2124): Enter und Strg+Enter führen ihn aus, die übrigen Tasten
    /// nichts. True, wenn AItem von dort stammt.</summary>
    function RanState(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction): Boolean;
    function ErrorText(AError: TAtlasCiFetchError; const AQuery: TAtlasIssueSearchQuery): string;
    procedure Browse(const AKey: string);
  public
    constructor Create(const AHooks: TAtlasIssueSearchHooks);
    destructor Destroy; override;
    /// <summary>Abbrechen, kurz auf Anfragen warten, Hooks lösen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>issues.paletteSearch an?</summary>
    class function Active: Boolean; static;
    { IAtlasPaletteSource }
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    procedure Changed(const APattern: string);
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure Closed;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeIssueSearch }

constructor TAtlasIdeIssueSearch.Create(const AHooks: TAtlasIssueSearchHooks);
var
  mOwner: TAtlasIdeIssueSearch;
begin
  inherited Create;
  FHooks := AHooks;
  FMessage := TAtlasMessageSink.Create(FHooks.Report);
  FStarted := True;
  // Die Abfrage lebt, solange eine Anfrage läuft; Stop löst ihren Rückruf.
  mOwner := Self;
  FFetch := TAtlasIdeIssueSearchFetch.Create(FHooks.Transport,
    procedure(const AQuery: TAtlasIssueSearchQuery; AAnswer: TAtlasIssueSearchAnswer;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError)
    begin
      mOwner.Answered(AQuery, AAnswer, AIssues, AError);
    end);
  FFetchRef := FFetch;
end;

destructor TAtlasIdeIssueSearch.Destroy;
begin
  Stop;
  FFetch := nil;
  FFetchRef := nil;
  inherited;
end;

procedure TAtlasIdeIssueSearch.Answered(const AQuery: TAtlasIssueSearchQuery; AAnswer: TAtlasIssueSearchAnswer;
  const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
begin
  if not FStarted or not Assigned(FShow) then
  begin
    Exit;
  end;
  case AAnswer of
    TAtlasIssueSearchAnswer.Show:
      ShowIssues(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesGroup), AQuery, AIssues);
    TAtlasIssueSearchAnswer.Ignore:
      ; // Abgebrochen: Eine neuere Eingabe zeigt ihr eigenes Ergebnis.
    TAtlasIssueSearchAnswer.Error:
      ShowStatus(ErrorText(AError, AQuery));
  end;
end;

procedure TAtlasIdeIssueSearch.ShowIssues(const ATitle: string; const AQuery: TAtlasIssueSearchQuery;
  const AIssues: TArray<TAtlasTrackerIssue>);
var
  mStatus: string;
begin
  FIssues := AIssues;
  if Length(AIssues) = 0 then
  begin
    mStatus := TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesNone);
  end
  else
  begin
    mStatus := TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesKeys);
  end;
  ShowGroup(TAtlasPaletteGroup.Create(ATitle, mStatus, AQuery.Highlight, TAtlasIssuePaletteSearch.Rows(AIssues)));
end;

procedure TAtlasIdeIssueSearch.ShowStatus(const AStatus: string);
begin
  FIssues := nil;
  ShowGroup(TAtlasPaletteGroup.Create(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesGroup), AStatus, '',
    nil));
end;

procedure TAtlasIdeIssueSearch.ShowGroup(const AGroup: TAtlasPaletteGroup);
begin
  if Assigned(FShow) then
  begin
    FShow(AGroup);
  end;
end;

function TAtlasIdeIssueSearch.ErrorText(AError: TAtlasCiFetchError; const AQuery: TAtlasIssueSearchQuery): string;
begin
  Result := '';
  case TAtlasIssuePaletteSearchPlan.ErrorOf(AError, AQuery.Kind) of
    TAtlasIssueSearchError.Config:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorConfig);
    TAtlasIssueSearchError.Token:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken);
    TAtlasIssueSearchError.KeyNotFound:
      Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewErrorNotFound, [AQuery.Key]);
    TAtlasIssueSearchError.NoneFound:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesNone);
    TAtlasIssueSearchError.Timeout:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesTimeout);
    TAtlasIssueSearchError.Network:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorNetwork);
    TAtlasIssueSearchError.Invalid:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorInvalid);
  end;
end;

procedure TAtlasIdeIssueSearch.ShowStates(const APattern: string);
var
  mRows: TArray<TAtlasCommand>;
begin
  mRows := nil;
  if Assigned(FHooks.States) then
  begin
    mRows := FHooks.States(APattern);
  end;
  FIssues := nil;
  if Length(mRows) = 0 then
  begin
    ShowGroup(TAtlasPaletteGroup.None);
    Exit;
  end;
  ShowGroup(TAtlasPaletteGroup.Create(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.PaletteStateGroup),
    TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.PaletteStateStatus), Trim(APattern), mRows));
end;

procedure TAtlasIdeIssueSearch.ShowNoTracker(const APattern: string);
begin
  if Active and TAtlasIssuePaletteSearchPlan.IsIssueInput(APattern) then
  begin
    ShowStatus(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesNoTracker));
  end
  else
  begin
    ShowStates(APattern);
  end;
end;

procedure TAtlasIdeIssueSearch.ShowRecent(const AQuery: TAtlasIssueSearchQuery);
var
  mRecent: TArray<TAtlasTrackerIssue>;
begin
  mRecent := nil;
  if Assigned(FHooks.Recent) then
  begin
    mRecent := FHooks.Recent(FFetch.Target);
  end;
  if Length(mRecent) = 0 then
  begin
    ShowStatus(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesNoRecent));
  end
  else
  begin
    ShowIssues(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesRecent), AQuery, mRecent);
  end;
end;

procedure TAtlasIdeIssueSearch.ShowOrSearch(const AQuery: TAtlasIssueSearchQuery);
var
  mLast: TArray<TAtlasTrackerIssue>;
begin
  if FFetch.Last(AQuery, mLast) then
  begin
    ShowIssues(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesGroup), AQuery, mLast);
  end
  else
  begin
    ShowStatus(TAtlasIssueStrings.Text(TAtlasIssueTextId.PaletteIssuesSearching));
    FFetch.Search(AQuery);
  end;
end;

procedure TAtlasIdeIssueSearch.Browse(const AKey: string);
var
  mUrl: string;
begin
  if FFetch.Provider = nil then
  begin
    Exit;
  end;
  // Nur die Seite aus der eingetragenen Adresse; nie eine Adresse aus der Antwort.
  mUrl := FFetch.Provider.IssuePage(FFetch.Target, AKey);
  TAtlasIssuePreview.Browse(mUrl);
end;

procedure TAtlasIdeIssueSearch.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  FFetch.Stop;
  FShow := nil;
  FHooks := Default(TAtlasIssueSearchHooks);
  FMessage.Clear;
end;

class function TAtlasIdeIssueSearch.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPaletteSearch;
end;

procedure TAtlasIdeIssueSearch.Opened(const AShow: TProc<TAtlasPaletteGroup>);
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
begin
  FShow := nil;
  FIssues := nil;
  mProvider := nil;
  mTarget := Default(TAtlasTrackerTarget);
  if FStarted then
  begin
    // Die Übergänge des aktuellen Issues (#2124) gibt es auch ohne Suche im Tracker.
    FShow := AShow;
    if Active and Assigned(FHooks.Target) then
    begin
      // Einmal je Öffnen: Tracker des aktiven Projekts (liest die .atlas, kein Netz).
      mProvider := FHooks.Target(mTarget);
    end;
  end;
  FFetch.Open(mProvider, mTarget);
end;

procedure TAtlasIdeIssueSearch.Changed(const APattern: string);
var
  mQuery: TAtlasIssueSearchQuery;
begin
  if not Assigned(FShow) then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      // Jede Eingabe ersetzt die laufende Anfrage.
      FFetch.Cancel;
      if FFetch.Provider = nil then
      begin
        ShowNoTracker(APattern);
        Exit;
      end;
      mQuery := TAtlasIssuePaletteSearch.Parse(FFetch.Target, APattern);
      case mQuery.Kind of
        TAtlasIssueSearchKind.None:
          ShowStates(APattern);
        TAtlasIssueSearchKind.Recent:
          ShowRecent(mQuery);
      else
        ShowOrSearch(mQuery);
      end;
    end);
end;

procedure TAtlasIdeIssueSearch.Closed;
begin
  FShow := nil;
  FFetch.Close;
  FIssues := nil;
end;

function TAtlasIdeIssueSearch.RanState(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction): Boolean;
begin
  Result := FStarted and TAtlasIssuePaletteSearchPlan.RunsState(AAction) and Assigned(FHooks.StateRun) and
    FHooks.StateRun(AItem.Id);
end;

procedure TAtlasIdeIssueSearch.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
var
  mIssue: TAtlasTrackerIssue;
begin
  if RanState(AItem, AAction) or not FStarted or
    not TAtlasIssuePaletteSearchPlan.IssueOf(FIssues, AItem, mIssue) then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      case AAction of
        TAtlasPaletteAction.Open:
          if Assigned(FHooks.Show) and Assigned(FHooks.PreviewActive) and FHooks.PreviewActive() then
          begin
            FHooks.Show(FFetch.Target, mIssue.Key);
          end
          else
          begin
            Browse(mIssue.Key);
          end;
        TAtlasPaletteAction.Start:
          if Assigned(FHooks.Start) and Assigned(FHooks.CanStart) and FHooks.CanStart() then
          begin
            FHooks.Start(mIssue);
          end
          else
          begin
            FMessage.Say(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.PaletteIssuesCannotStart, [mIssue.Key]));
          end;
        TAtlasPaletteAction.Browse:
          Browse(mIssue.Key);
        TAtlasPaletteAction.Copy:
          Clipboard.AsText := mIssue.Key;
        TAtlasPaletteAction.Toggle:
          begin
            // Schalten gibt es nur für Einstellungen (#1884); Alt+Enter auf einem Issue tut nichts.
          end;
      end;
    end);
end;

end.
