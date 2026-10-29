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
// - Mit issues.paletteSearch aus gibt es weder Gruppe noch Netzzugriff.
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
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.IDE.Tracker.IssuePreview;

type
  /// <summary>Tracker des aktiven Projekts; nil ohne Anbieter bzw. Server.</summary>
  TAtlasIssueSearchTargetHook = reference to function(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
  TAtlasIssueSearchRecentHook = reference to function(const ATarget: TAtlasTrackerTarget):
    TArray<TAtlasTrackerIssue>;
  TAtlasIssueSearchShowHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string);

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
    FWorkers: TList;
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
    procedure ReleaseThreads(AWait: Boolean);
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
  Winapi.ShellAPI,
  System.StrUtils,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeIssueSearch }

constructor TAtlasIdeIssueSearch.Create(const AHooks: TAtlasIssueSearchHooks);
begin
  inherited Create;
  FHooks := AHooks;
  FStarted := True;
  FDebounce := TAtlasIssueSearchDebounce.Create(TAtlasIssuePaletteSearch.DelayMs);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
  FWorkers := TList.Create;
  FQuery := TAtlasIssueSearchQuery.None;
  FLastQuery := TAtlasIssueSearchQuery.None;
end;

destructor TAtlasIdeIssueSearch.Destroy;
begin
  Stop;
  ReleaseThreads(True);
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
    Exit;
  FStarted := False;
  Inc(FGeneration);
  // Der Zeitgeber gehört dem Hauptthread; die letzte Referenz kann ein Hintergrund-Thread lösen.
  FreeAndNil(FTimer);
  FDebounce.Clear;
  CancelRequest;
  ReleaseThreads(True);
  FShow := nil;
  FProvider := nil;
  FHooks := Default(TAtlasIssueSearchHooks);
end;

procedure TAtlasIdeIssueSearch.ReleaseThreads(AWait: Boolean);
var
  mIndex: Integer;
  mThread: TThread;
  mWait: TArray<TThread>;
begin
  if AWait then
  begin
    mWait := nil;
    for mIndex := 0 to FWorkers.Count - 1 do
      mWait := mWait + [TThread(FWorkers[mIndex])];
    if Length(mWait) > 0 then
      TAtlasShutdown.WaitForThreads(mWait);
  end;
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    mThread := TThread(FWorkers[mIndex]);
    if mThread.Finished then
    begin
      mThread.Free;
      FWorkers.Delete(mIndex);
    end
    else if AWait then
    begin
      // Läuft noch (Zeitgrenze): räumt sich selbst auf.
      mThread.FreeOnTerminate := True;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasIdeIssueSearch.CancelRequest;
begin
  // Die Antwort einer abgebrochenen Anfrage zählt nicht mehr (Generation).
  Inc(FGeneration);
  if FCancel <> nil then
    FCancel.Cancel;
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
  if not FStarted or not Active or not Assigned(FHooks.Target) then
    Exit;
  FShow := AShow;
  // Einmal je Öffnen: Tracker des aktiven Projekts (liest die .atlas, kein Netz).
  FProvider := FHooks.Target(FTarget);
end;

procedure TAtlasIdeIssueSearch.Closed;
begin
  FShow := nil;
  if FTimer <> nil then
    FTimer.Enabled := False;
  FDebounce.Clear;
  CancelRequest;
  ReleaseThreads(False);
  FIssues := nil;
end;

procedure TAtlasIdeIssueSearch.ShowGroup(const AGroup: TAtlasPaletteGroup);
begin
  if Assigned(FShow) then
    FShow(AGroup);
end;

procedure TAtlasIdeIssueSearch.ShowStatus(const AStatus: string);
begin
  FIssues := nil;
  ShowGroup(TAtlasPaletteGroup.Create(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesGroup), AStatus, '', nil));
end;

procedure TAtlasIdeIssueSearch.ShowIssues(const ATitle: string; const AQuery: TAtlasIssueSearchQuery;
  const AIssues: TArray<TAtlasTrackerIssue>);
var
  mStatus: string;
begin
  FIssues := AIssues;
  if Length(AIssues) = 0 then
    mStatus := TAtlasStrings.Text(TAtlasTextId.PaletteIssuesNone)
  else
    mStatus := TAtlasStrings.Text(TAtlasTextId.PaletteIssuesKeys);
  ShowGroup(TAtlasPaletteGroup.Create(ATitle, mStatus, AQuery.Highlight, TAtlasIssuePaletteSearch.Rows(AIssues)));
end;

procedure TAtlasIdeIssueSearch.Changed(const APattern: string);
var
  mQuery: TAtlasIssueSearchQuery;
  mRecent: TArray<TAtlasTrackerIssue>;
begin
  if not Assigned(FShow) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      // Jede Eingabe ersetzt die laufende Anfrage.
      if FTimer <> nil then
        FTimer.Enabled := False;
      FDebounce.Clear;
      CancelRequest;
      if FProvider = nil then
      begin
        // Ohne Tracker gehört "#…" trotzdem nicht zu den Befehlen: Hinweis statt stiller Leere.
        if StartsStr('#', TrimLeft(APattern)) then
          ShowStatus(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesNoTracker))
        else
          ShowGroup(TAtlasPaletteGroup.None);
        Exit;
      end;
      mQuery := TAtlasIssuePaletteSearch.Parse(FTarget, APattern);
      FQuery := mQuery;
      case mQuery.Kind of
        TAtlasIssueSearchKind.None:
          begin
            FIssues := nil;
            ShowGroup(TAtlasPaletteGroup.None);
          end;
        TAtlasIssueSearchKind.Recent:
          begin
            mRecent := nil;
            if Assigned(FHooks.Recent) then
              mRecent := FHooks.Recent(FTarget);
            if Length(mRecent) = 0 then
              ShowStatus(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesNoRecent))
            else
              ShowIssues(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesRecent), mQuery, mRecent);
          end;
      else
        if FHasLast and mQuery.SameAs(FLastQuery) then
          ShowIssues(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesGroup), mQuery, FLastIssues)
        else
        begin
          ShowStatus(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesSearching));
          FDebounce.Input(mQuery.Key + '|' + mQuery.Text, NowMs);
          Schedule;
        end;
      end;
    end);
end;

procedure TAtlasIdeIssueSearch.Schedule;
var
  mWait: Integer;
begin
  if FTimer = nil then
    Exit;
  mWait := FDebounce.WaitMs(NowMs);
  FTimer.Enabled := False;
  if mWait < 0 then
    Exit;
  if mWait < 1 then
    mWait := 1;
  FTimer.Interval := Cardinal(mWait);
  FTimer.Enabled := True;
end;

procedure TAtlasIdeIssueSearch.TimerTick(Sender: TObject);
var
  mText: string;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  if not FStarted or not Assigned(FShow) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      if FDebounce.Take(NowMs, mText) then
        Request(FQuery)
      else
        Schedule;
    end);
end;

procedure TAtlasIdeIssueSearch.Request(const AQuery: TAtlasIssueSearchQuery);
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mTransport: IAtlasCiTransport;
  mGeneration: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueSearch;
  mThread: TThread;
begin
  ReleaseThreads(False);
  CancelRequest;
  mGeneration := FGeneration;
  mProvider := FProvider;
  mTarget := FTarget;
  if (mProvider = nil) or not Assigned(FHooks.Transport) then
  begin
    Answered(mGeneration, AQuery, False, nil, TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  // Der Transport entsteht hier, damit eine neue Eingabe ihn abbrechen kann; er liest das Token ohne Dialog.
  mTransport := FHooks.Transport(mProvider, mTarget);
  if mTransport = nil then
  begin
    Answered(mGeneration, AQuery, False, nil, TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
    FCancel := nil;
  mKeep := Self;
  mOwner := Self;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mIssues: TArray<TAtlasTrackerIssue>;
      mIssue: TAtlasTrackerIssue;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mIssues := nil;
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        if AQuery.Kind = TAtlasIssueSearchKind.Key then
        begin
          mOk := mProvider.Lookup(mTarget, mTransport, AQuery.Key, TAtlasIssuePaletteSearch.TimeoutMs, mIssue,
            mError);
          if mOk then
            mIssues := [mIssue];
        end
        else
          mOk := mProvider.Search(mTarget, mTransport, AQuery.Text, TAtlasIssuePaletteSearch.TimeoutMs,
            TAtlasIssuePaletteSearch.MaxResults, mIssues, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Palettensuche: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.Palette,
        procedure
        begin
          if mKeep <> nil then
            mOwner.Answered(mGeneration, AQuery, mOk, mIssues, mError);
        end);
    end);
  mThread.FreeOnTerminate := False;
  FWorkers.Add(mThread);
  mThread.Start;
end;

procedure TAtlasIdeIssueSearch.Answered(AGeneration: Integer; const AQuery: TAtlasIssueSearchQuery;
  ASucceeded: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  mName: string;
begin
  ReleaseThreads(False);
  // Neuere Eingabe, abgebrochen oder Palette zu: diese Antwort zählt nicht.
  if not FStarted or (AGeneration <> FGeneration) or not Assigned(FShow) then
    Exit;
  FCancel := nil;
  mName := '';
  if FProvider <> nil then
    mName := FProvider.Name;
  TAtlasGuard.Log(Format('Palettensuche: %s, %s', [mName, IfThen(ASucceeded, IntToStr(Length(AIssues)) +
    ' Treffer', 'keine Antwort (' + TAtlasCiBuild.ErrorKey(AError) + ')')]));
  if ASucceeded then
  begin
    FLastQuery := AQuery;
    FLastIssues := AIssues;
    FHasLast := True;
    ShowIssues(TAtlasStrings.Text(TAtlasTextId.PaletteIssuesGroup), AQuery, AIssues);
    Exit;
  end;
  if AError = TAtlasCiFetchError.Cancelled then
    Exit;
  ShowStatus(ErrorText(AError, AQuery));
end;

function TAtlasIdeIssueSearch.ErrorText(AError: TAtlasCiFetchError; const AQuery: TAtlasIssueSearchQuery): string;
begin
  case AError of
    TAtlasCiFetchError.NotConfigured:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorConfig);
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      if AQuery.Kind = TAtlasIssueSearchKind.Key then
        Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewErrorNotFound, [AQuery.Key])
      else
        Result := TAtlasStrings.Text(TAtlasTextId.PaletteIssuesNone);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.PaletteIssuesTimeout);
    TAtlasCiFetchError.Network:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorInvalid);
  end;
end;

function TAtlasIdeIssueSearch.IssueOf(const AItem: TAtlasCommand; out AIssue: TAtlasTrackerIssue): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  for mIssue in FIssues do
    if SameText(mIssue.Key, AItem.Id) then
    begin
      AIssue := mIssue;
      Exit(True);
    end;
  AIssue := TAtlasTrackerIssue.Empty;
  AIssue.Key := AItem.Id;
  AIssue.Title := AItem.Description;
  Result := AItem.Id <> '';
end;

procedure TAtlasIdeIssueSearch.Report(const AText: string);
begin
  if Assigned(FHooks.Report) then
    FHooks.Report(AText);
end;

procedure TAtlasIdeIssueSearch.Browse(const AKey: string);
var
  mUrl: string;
begin
  if FProvider = nil then
    Exit;
  // Nur die Seite aus der eingetragenen Adresse; nie eine Adresse aus der Antwort.
  mUrl := FProvider.IssuePage(FTarget, AKey);
  if TAtlasIssuePreview.MayBrowse(mUrl) then
    ShellExecute(0, 'open', PChar(mUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasIdeIssueSearch.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
var
  mIssue: TAtlasTrackerIssue;
begin
  if not FStarted or not IssueOf(AItem, mIssue) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Palette,
    procedure
    begin
      case AAction of
        TAtlasPaletteAction.Open:
          if Assigned(FHooks.Show) and Assigned(FHooks.PreviewActive) and FHooks.PreviewActive() then
            FHooks.Show(FTarget, mIssue.Key)
          else
            Browse(mIssue.Key);
        TAtlasPaletteAction.Start:
          if Assigned(FHooks.Start) and Assigned(FHooks.CanStart) and FHooks.CanStart() then
            FHooks.Start(mIssue)
          else
            Report(TAtlasStrings.Fmt(TAtlasTextId.PaletteIssuesCannotStart, [mIssue.Key]));
        TAtlasPaletteAction.Browse:
          Browse(mIssue.Key);
        TAtlasPaletteAction.Copy:
          Clipboard.AsText := mIssue.Key;
      end;
    end);
end;

end.
