unit Atlas.IDE.Tracker.PaletteSearch;

// Issues in der Befehlspalette suchen (#1270, issues.paletteSearch): Quelle
// der Palette (IAtlasPaletteSource) für den Tracker des aktiven Projekts.
// - Auslöser und Anfrage aus Atlas.Core.Tracker.PaletteSearch: "#Text",
//   "#42", bei YouTrack "ATL-12" und "ATL-Text"; andere Eingaben bleiben
//   bei den Befehlen, ohne Netz.
// - Entprellt um 300 ms (TAtlasIssueSearchDebounce, Zeitgeber der IDE); eine
//   neue Eingabe bricht die laufende Anfrage ab (IAtlasCiCancel), Zeitgrenze
//   5 s. Bis zur Antwort steht „Suche im Tracker …“ in der Gruppe „Issues“
//   unter den Befehlen; die Befehle erscheinen sofort.
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
// - Protokoll anonym: Anbieter, Anzahl und Fehlerart, nie Suchtext, Kennung
//   oder Adresse.
// Ziel, Transport, Vorschau, „Beginnen“ und die zuletzt geöffneten Issues
// kommen über Hooks („Meine Issues“).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.Core.Diagnostics.WorkerSlot;

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
    FStarted: Boolean;
    FShow: TProc<TAtlasPaletteGroup>;
    FDebounce: TAtlasIssueSearchDebounce;
    FTimer: TTimer;
    FTarget: TAtlasTrackerTarget;
    FProvider: IAtlasTrackerProvider;
    FQuery: TAtlasIssueSearchQuery;
    // Letzte Antwort: dieselbe Eingabe noch einmal (Rücktaste und neu getippt) braucht kein Netz.
    FLastQuery: TAtlasIssueSearchQuery;
    FLastIssues: TArray<TAtlasTrackerIssue>;
    FHasLast: Boolean;
    FIssues: TArray<TAtlasTrackerIssue>;
    FCancel: IAtlasCiCancel;
    FGeneration: Integer;
    FWorkers: TAtlasWorkerSlot;
    procedure TimerTick(Sender: TObject);
    procedure Schedule;
    procedure Request(const AQuery: TAtlasIssueSearchQuery);
    procedure Answered(AGeneration: Integer; const AQuery: TAtlasIssueSearchQuery; ASucceeded: Boolean;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
    procedure ShowIssues(const ATitle: string; const AQuery: TAtlasIssueSearchQuery;
      const AIssues: TArray<TAtlasTrackerIssue>);
    procedure ShowStatus(const AStatus: string);
    procedure ShowGroup(const AGroup: TAtlasPaletteGroup);
    procedure CancelRequest;
    function IssueOf(const AItem: TAtlasCommand; out AIssue: TAtlasTrackerIssue): Boolean;
    function ErrorText(AError: TAtlasCiFetchError; const AQuery: TAtlasIssueSearchQuery): string;
    procedure Browse(const AKey: string);
    procedure Report(const AText: string);
    class function NowMs: UInt64; static;
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
  Winapi.Windows,
  System.StrUtils,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.Strings,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeIssueSearch }

constructor TAtlasIdeIssueSearch.Create(const AHooks: TAtlasIssueSearchHooks);
begin
  inherited Create;
  FHooks := AHooks;
  FStarted := True;
  FDebounce := TAtlasIssueSearchDebounce.Create(TAtlasIssuePaletteSearch.cDelayMs);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
  FQuery := TAtlasIssueSearchQuery.None;
  FLastQuery := TAtlasIssueSearchQuery.None;
end;

destructor TAtlasIdeIssueSearch.Destroy;
begin
  Stop;
  FWorkers.Free;
  FTimer.Free;
  FDebounce.Free;
  inherited;
end;

class function TAtlasIdeIssueSearch.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPaletteSearch;
end;

class function TAtlasIdeIssueSearch.NowMs: UInt64;
begin
  Result := GetTickCount64;
end;

procedure TAtlasIdeIssueSearch.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  Inc(FGeneration);
  // Der Zeitgeber gehört dem Hauptthread; die letzte Referenz kann ein Hintergrund-Thread lösen.
  FreeAndNil(FTimer);
  FDebounce.Clear;
  CancelRequest;
  FWorkers.Release(True);
  FShow := nil;
  FProvider := nil;
  FHooks := Default(TAtlasIssueSearchHooks);
end;

procedure TAtlasIdeIssueSearch.CancelRequest;
begin
  // Die Antwort einer abgebrochenen Anfrage zählt nicht mehr (Generation).
  Inc(FGeneration);
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
  FCancel := nil;
end;

procedure TAtlasIdeIssueSearch.Opened(const AShow: TProc<TAtlasPaletteGroup>);
begin
  FShow := nil;
  FProvider := nil;
  FQuery := TAtlasIssueSearchQuery.None;
  FHasLast := False;
  FLastIssues := nil;
  FIssues := nil;
  if not FStarted then
  begin
    Exit;
  end;
  // Die Übergänge des aktuellen Issues (#2124) gibt es auch ohne Suche im Tracker.
  FShow := AShow;
  if Active and Assigned(FHooks.Target) then
  begin
    // Einmal je Öffnen: Tracker des aktiven Projekts (liest die .atlas, kein Netz).
    FProvider := FHooks.Target(FTarget);
  end;
end;

procedure TAtlasIdeIssueSearch.Closed;
begin
  FShow := nil;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FDebounce.Clear;
  CancelRequest;
  FWorkers.Release(False);
  FIssues := nil;
end;

procedure TAtlasIdeIssueSearch.ShowGroup(const AGroup: TAtlasPaletteGroup);
begin
  if Assigned(FShow) then
  begin
    FShow(AGroup);
  end;
end;

procedure TAtlasIdeIssueSearch.ShowStatus(const AStatus: string);
begin
  FIssues := nil;
  ShowGroup(TAtlasPaletteGroup.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesGroup), AStatus, '',
    nil));
end;

procedure TAtlasIdeIssueSearch.ShowIssues(const ATitle: string; const AQuery: TAtlasIssueSearchQuery;
  const AIssues: TArray<TAtlasTrackerIssue>);
var
  mStatus: string;
begin
  FIssues := AIssues;
  if Length(AIssues) = 0 then
  begin
    mStatus := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesNone);
  end
  else
  begin
    mStatus := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesKeys);
  end;
  ShowGroup(TAtlasPaletteGroup.Create(ATitle, mStatus, AQuery.Highlight, TAtlasIssuePaletteSearch.Rows(AIssues)));
end;

/// <summary>Übergänge des aktuellen Issues zur Eingabe (#2124); ohne passende keine Gruppe.</summary>
procedure ShowStates(AOwner: TAtlasIdeIssueSearch; const APattern: string);
var
  mRows: TArray<TAtlasCommand>;
begin
  mRows := nil;
  if Assigned(AOwner.FHooks.States) then
  begin
    mRows := AOwner.FHooks.States(APattern);
  end;
  AOwner.FIssues := nil;
  if Length(mRows) = 0 then
  begin
    AOwner.ShowGroup(TAtlasPaletteGroup.None);
    Exit;
  end;
  AOwner.ShowGroup(TAtlasPaletteGroup.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteStateGroup),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteStateStatus), Trim(APattern), mRows));
end;

/// <summary>Ohne Tracker gehört "#…" trotzdem nicht zu den Befehlen: Hinweis statt stiller Leere.</summary>
procedure ShowNoTracker(AOwner: TAtlasIdeIssueSearch; const APattern: string);
begin
  if TAtlasIdeIssueSearch.Active and StartsStr('#', TrimLeft(APattern)) then
  begin
    AOwner.ShowStatus(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesNoTracker));
  end
  else
  begin
    ShowStates(AOwner, APattern);
  end;
end;

/// <summary>Zuletzt gesehene Issues ("#" allein).</summary>
procedure ShowRecent(AOwner: TAtlasIdeIssueSearch; const AQuery: TAtlasIssueSearchQuery);
var
  mRecent: TArray<TAtlasTrackerIssue>;
begin
  mRecent := nil;
  if Assigned(AOwner.FHooks.Recent) then
  begin
    mRecent := AOwner.FHooks.Recent(AOwner.FTarget);
  end;
  if Length(mRecent) = 0 then
  begin
    AOwner.ShowStatus(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesNoRecent));
  end
  else
  begin
    AOwner.ShowIssues(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesRecent), AQuery, mRecent);
  end;
end;

/// <summary>Kennung oder Text: dieselbe Eingabe wie zuletzt aus der letzten Antwort, sonst nach der Wartezeit
/// fragen.</summary>
procedure ShowOrSearch(AOwner: TAtlasIdeIssueSearch; const AQuery: TAtlasIssueSearchQuery);
begin
  if AOwner.FHasLast and AQuery.SameAs(AOwner.FLastQuery) then
  begin
    AOwner.ShowIssues(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesGroup), AQuery,
      AOwner.FLastIssues);
  end
  else
  begin
    AOwner.ShowStatus(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesSearching));
    AOwner.FDebounce.Input(AQuery.Key + '|' + AQuery.Text, TAtlasIdeIssueSearch.NowMs);
    AOwner.Schedule;
  end;
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
      if FTimer <> nil then
      begin
        FTimer.Enabled := False;
      end;
      FDebounce.Clear;
      CancelRequest;
      if FProvider = nil then
      begin
        ShowNoTracker(Self, APattern);
        Exit;
      end;
      mQuery := TAtlasIssuePaletteSearch.Parse(FTarget, APattern);
      FQuery := mQuery;
      case mQuery.Kind of
        TAtlasIssueSearchKind.None:
          ShowStates(Self, APattern);
        TAtlasIssueSearchKind.Recent:
          ShowRecent(Self, mQuery);
      else
        ShowOrSearch(Self, mQuery);
      end;
    end);
end;

procedure TAtlasIdeIssueSearch.Schedule;
var
  mWait: Integer;
begin
  if FTimer = nil then
  begin
    Exit;
  end;
  mWait := FDebounce.WaitMs(NowMs);
  FTimer.Enabled := False;
  if mWait < 0 then
  begin
    Exit;
  end;
  if mWait < 1 then
  begin
    mWait := 1;
  end;
  FTimer.Interval := Cardinal(mWait);
  FTimer.Enabled := True;
end;

procedure TAtlasIdeIssueSearch.TimerTick(Sender: TObject);
var
  mText: string;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  if not FStarted or not Assigned(FShow) then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      if FDebounce.Take(NowMs, mText) then
      begin
        Request(FQuery);
      end
      else
      begin
        Schedule;
      end;
    end);
end;

type
  /// <summary>Eine Anfrage der Suche, wie sie in den Hintergrund geht.</summary>
  TSearchJob = record
    Generation: Integer;
    Query: TAtlasIssueSearchQuery;
    Provider: IAtlasTrackerProvider;
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
  end;

/// <summary>Issue zur Kennung bzw. Suche nach Text; False mit AError.</summary>
function FetchIssues(const AJob: TSearchJob; out AIssues: TArray<TAtlasTrackerIssue>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  AIssues := nil;
  if AJob.Query.Kind <> TAtlasIssueSearchKind.Key then
  begin
    Exit(AJob.Provider.Search(TAtlasTrackerCall.Create(AJob.Target, AJob.Transport,
      TAtlasIssuePaletteSearch.cTimeoutMs), AJob.Query.Text, TAtlasIssuePaletteSearch.cMaxResults, AIssues, AError));
  end;
  Result := AJob.Provider.Lookup(AJob.Target, AJob.Transport, AJob.Query.Key, TAtlasIssuePaletteSearch.cTimeoutMs,
    mIssue, AError);
  if Result then
  begin
    AIssues := [mIssue];
  end;
end;

/// <summary>Arbeit des Hintergrundthreads; die Antwort geht über den Hauptthread an AOwner, solange AKeep ihn
/// hält. Eigene Routine: Die anonyme Methode hält nur ihre Parameter.</summary>
function SearchWorker(AOwner: TAtlasIdeIssueSearch; const AKeep: IInterface; const AJob: TSearchJob): TProc;
var
  mJob: TSearchJob;
  mKeep: IInterface;
begin
  mJob := AJob;
  mKeep := AKeep;
  Result :=
    procedure
    var
      mIssues: TArray<TAtlasTrackerIssue>;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := FetchIssues(mJob, mIssues, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mIssues := nil;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Palettensuche: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Palette,
        procedure
        begin
          if mKeep <> nil then
          begin
            AOwner.Answered(mJob.Generation, mJob.Query, mOk, mIssues, mError);
          end;
        end);
    end;
end;

procedure TAtlasIdeIssueSearch.Request(const AQuery: TAtlasIssueSearchQuery);
var
  mJob: TSearchJob;
begin
  FWorkers.Release(False);
  CancelRequest;
  mJob := Default(TSearchJob);
  mJob.Generation := FGeneration;
  mJob.Query := AQuery;
  mJob.Provider := FProvider;
  mJob.Target := FTarget;
  if (mJob.Provider = nil) or not Assigned(FHooks.Transport) then
  begin
    Answered(mJob.Generation, AQuery, False, nil, TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  // Der Transport entsteht hier, damit eine neue Eingabe ihn abbrechen kann; er liest das Token ohne Dialog.
  mJob.Transport := FHooks.Transport(mJob.Provider, mJob.Target);
  if mJob.Transport = nil then
  begin
    Answered(mJob.Generation, AQuery, False, nil, TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  if not Supports(mJob.Transport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  FWorkers.Start(TThread.CreateAnonymousThread(SearchWorker(Self, Self, mJob)));
end;

procedure TAtlasIdeIssueSearch.Answered(AGeneration: Integer; const AQuery: TAtlasIssueSearchQuery;
  ASucceeded: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  mName, mState: string;
begin
  FWorkers.Release(False);
  // Neuere Eingabe, abgebrochen oder Palette zu: diese Antwort zählt nicht.
  if not FStarted or (AGeneration <> FGeneration) or not Assigned(FShow) then
  begin
    Exit;
  end;
  FCancel := nil;
  mName := '';
  if FProvider <> nil then
  begin
    mName := FProvider.Name;
  end;
  if ASucceeded then
  begin
    mState := IntToStr(Length(AIssues)) + ' Treffer';
  end
  else
  begin
    mState := 'keine Antwort (' + TAtlasCiBuild.ErrorKey(AError) + ')';
  end;
  TAtlasGuard.Log(Format('Palettensuche: %s, %s', [mName, mState]));
  if ASucceeded then
  begin
    FLastQuery := AQuery;
    FLastIssues := AIssues;
    FHasLast := True;
    ShowIssues(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesGroup), AQuery, AIssues);
    Exit;
  end;
  if AError = TAtlasCiFetchError.Cancelled then
  begin
    Exit;
  end;
  ShowStatus(ErrorText(AError, AQuery));
end;

function TAtlasIdeIssueSearch.ErrorText(AError: TAtlasCiFetchError; const AQuery: TAtlasIssueSearchQuery): string;
begin
  case AError of
    TAtlasCiFetchError.NotConfigured:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewErrorConfig);
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      if AQuery.Kind = TAtlasIssueSearchKind.Key then
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewErrorNotFound, [AQuery.Key]);
      end
      else
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesNone);
      end;
    TAtlasCiFetchError.Timeout:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.PaletteIssuesTimeout);
    TAtlasCiFetchError.Network:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewErrorNetwork);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewErrorInvalid);
  end;
end;

function TAtlasIdeIssueSearch.IssueOf(const AItem: TAtlasCommand; out AIssue: TAtlasTrackerIssue): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  for mIssue in FIssues do
  begin
    if SameText(mIssue.Key, AItem.Id) then
    begin
      AIssue := mIssue;
      Exit(True);
    end;
  end;
  AIssue := TAtlasTrackerIssue.Empty;
  AIssue.Key := AItem.Id;
  AIssue.Title := AItem.Description;
  Result := AItem.Id <> '';
end;

procedure TAtlasIdeIssueSearch.Report(const AText: string);
begin
  if Assigned(FHooks.Report) then
  begin
    FHooks.Report(AText);
  end;
end;

procedure TAtlasIdeIssueSearch.Browse(const AKey: string);
var
  mUrl: string;
begin
  if FProvider = nil then
  begin
    Exit;
  end;
  // Nur die Seite aus der eingetragenen Adresse; nie eine Adresse aus der Antwort.
  mUrl := FProvider.IssuePage(FTarget, AKey);
  TAtlasIssuePreview.Browse(mUrl);
end;

/// <summary>Übergang des aktuellen Issues (#2124): Enter und Strg+Enter führen ihn aus, die übrigen Tasten nichts.
/// True, wenn AItem von dort stammt.</summary>
function RanState(AOwner: TAtlasIdeIssueSearch; const AItem: TAtlasCommand; AAction: TAtlasPaletteAction): Boolean;
begin
  Result := AOwner.FStarted and (AAction in [TAtlasPaletteAction.Open, TAtlasPaletteAction.Start]) and
    Assigned(AOwner.FHooks.StateRun) and AOwner.FHooks.StateRun(AItem.Id);
end;

procedure TAtlasIdeIssueSearch.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
var
  mIssue: TAtlasTrackerIssue;
begin
  if RanState(Self, AItem, AAction) or not FStarted or not IssueOf(AItem, mIssue) then
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
            FHooks.Show(FTarget, mIssue.Key);
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
            Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.PaletteIssuesCannotStart, [mIssue.Key]));
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
