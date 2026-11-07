unit Atlas.IDE.Tracker.IssueChecklists;

// Checklisten im Fenster „Atlas-Issue“ (#1273, issues.preview.checklists):
// Klick auf ein Kästchen bzw. „Punkt hinzufügen …“ lädt im Hintergrund die
// aktuelle Beschreibung (IAtlasTrackerDescriptions), prüft die Zeile
// (TAtlasTrackerChecklist), schreibt zurück und zeigt den neuen Text; ein
// Schreiben zur Zeit. Wurde die Beschreibung inzwischen geändert, schreibt
// Atlas nichts, lädt neu und meldet es. Lehnt der Tracker ab (401/403) oder
// kann der Anbieter nicht schreiben, bleibt die Liste für dieses Issue in der
// Sitzung nur lesbar.
// Statusfeld (issues.checklistStatus): Progress liest den Fortschritt aus dem
// Zwischenspeicher, Prefetch frischt ihn höchstens alle PrefetchMinutes im
// Hintergrund auf.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.IDE.Tracker.IssueContext;

type
  TAtlasIdeIssueChecklists = class
  public const
    /// <summary>So lange gilt der Fortschritt einer Checkliste im Zwischenspeicher fürs Statusfeld (#1273).</summary>
    cPrefetchMinutes = 10;
  private
    FContext: TAtlasIdeIssueContext;
    /// <summary>Das Issue neu laden (Beschreibung wurde inzwischen geändert).</summary>
    FReload: TProc<TAtlasIssueHistoryEntry>;
    // Ein Schreiben zur Zeit, Hinweis nach dem Neuladen, nur lesbare Issues der Sitzung.
    FWriting: Boolean;
    FPendingNotice: string;
    FReadOnly: TStringList;
    // Statusfeld: zuletzt angestoßene Auffrischung (Kennung und Zeit, UTC).
    FPrefetchKey: string;
    FPrefetchAt: TDateTime;
    FPrefetching: Boolean;
  public
    constructor Create(AContext: TAtlasIdeIssueContext; const AReload: TProc<TAtlasIssueHistoryEntry>);
    destructor Destroy; override;
    /// <summary>Schalter der Checkliste für AEntry am Frame setzen.</summary>
    procedure Prepare(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry);
    /// <summary>Kästchen AIndex der gezeigten Beschreibung umschalten.</summary>
    procedure Toggle(AIndex: Integer);
    /// <summary>„Punkt hinzufügen …“: Text erfragen und anhängen.</summary>
    procedure AddTask;
    /// <summary>Hinweis für den nächsten frisch geladenen Stand ('' ohne); danach leer.</summary>
    function TakeNotice: string;
    /// <summary>Fortschritt der Checkliste von AKey aus dem Zwischenspeicher (ohne Netz); False ohne Stand.</summary>
    function Progress(const ATarget: TAtlasTrackerTarget; const AKey: string;
      out AProgress: TAtlasChecklistProgress): Boolean;
    /// <summary>Stand von AKey im Hintergrund auffrischen, wenn er fehlt oder älter als PrefetchMinutes ist; je
    /// Kennung höchstens einmal in PrefetchMinutes (auch nach einem Fehler). Ohne Fenster.</summary>
    procedure Prefetch(const ATarget: TAtlasTrackerTarget; const AKey: string);
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.IssueCache,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.IssueTip;

type
  {$SCOPEDENUMS ON}
  TChecklistChange = (Toggle, Append);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Schreibauftrag an die Beschreibung.</summary>
  TChecklistJob = record
    Entry: TAtlasIssueHistoryEntry;
    Editor: IAtlasTrackerDescriptions;
    Transport: IAtlasCiTransport;
    Change: TChecklistChange;
    Item: TAtlasChecklistItem;
    Text: string;
  end;

  /// <summary>Ergebnis eines Schreibauftrags.</summary>
  TChecklistResult = record
    Applied: Boolean;
    Changed: Boolean;
    /// <summary>Der Tracker hat das Schreiben abgelehnt: keine Schreibrechte.</summary>
    Denied: Boolean;
    Error: TAtlasCiFetchError;
    /// <summary>Der geschriebene Text.</summary>
    Text: string;
  end;

function ReadOnlyKey(const AEntry: TAtlasIssueHistoryEntry): string;
begin
  Result := TAtlasTrackerIssueCache.TrackerId(AEntry.Target) + '#' + LowerCase(AEntry.Key);
end;

/// <summary>Checkliste des gezeigten Issues lässt sich gerade ändern.</summary>
function Writable(AOwner: TAtlasIdeIssueChecklists; AFrame: TAtlasIssueFrame): Boolean;
begin
  Result := AOwner.FContext.Started and AOwner.FContext.HasCurrent and not AOwner.FWriting and (AFrame <> nil);
  if Result then
  begin
    Result := AFrame.State.HasDetails and not (TAtlasIssueFlag.ChecklistReadOnly in AFrame.Flags);
  end;
end;

/// <summary>Im Hintergrund: aktuellen Stand lesen und nur schreiben, wenn der Punkt dort unverändert steht.</summary>
function WriteChecklist(const AJob: TChecklistJob): TChecklistResult;
var
  mCurrent: string;
  mOk: Boolean;
begin
  Result := Default(TChecklistResult);
  Result.Error := TAtlasCiFetchError.Network;
  if not AJob.Editor.Description(AJob.Entry.Target, AJob.Transport, AJob.Entry.Key, TAtlasIssuePreview.cTimeoutMs,
    mCurrent, Result.Error) then
  begin
    Exit;
  end;
  if AJob.Change = TChecklistChange.Toggle then
  begin
    mOk := TAtlasTrackerChecklist.Toggle(mCurrent, AJob.Item, Result.Text);
  end
  else
  begin
    mOk := TAtlasTrackerChecklist.Append(mCurrent, AJob.Text, Result.Text);
  end;
  if not mOk then
  begin
    Result.Changed := True;
    Result.Error := TAtlasCiFetchError.None;
  end
  else
  begin
    Result.Applied := AJob.Editor.UpdateDescription(AJob.Entry.Target, AJob.Transport, AJob.Entry.Key, Result.Text,
      TAtlasIssuePreview.cTimeoutMs, Result.Error);
    // Nur eine Ablehnung beim Schreiben heißt „keine Schreibrechte“; Lesefehler nicht.
    Result.Denied := not Result.Applied and (Result.Error = TAtlasCiFetchError.Unauthorized);
  end;
end;

/// <summary>Ergebnis fürs Protokoll, anonym.</summary>
procedure LogWritten(const AProvider: IAtlasTrackerProvider; const AResult: TChecklistResult);
var
  mText: string;
begin
  if AProvider = nil then
  begin
    Exit;
  end;
  mText := 'nicht geschrieben (' + TAtlasCiBuild.ErrorKey(AResult.Error) + ')';
  if AResult.Applied then
  begin
    mText := 'geschrieben';
  end
  else if AResult.Changed then
  begin
    mText := 'Beschreibung geändert';
  end;
  TAtlasGuard.Log(Format('Issue-Vorschau: Checkliste bei %s %s', [AProvider.Name, mText]));
end;

/// <summary>Ergebnis im Fenster zeigen; AEntry ist das gezeigte Issue.</summary>
procedure ShowWritten(AOwner: TAtlasIdeIssueChecklists; AFrame: TAtlasIssueFrame;
  const AEntry: TAtlasIssueHistoryEntry; const AResult: TChecklistResult);
begin
  if AResult.Applied then
  begin
    AFrame.ReplaceDescription(AResult.Text);
  end
  else if AResult.Changed then
  begin
    // Nichts angewendet: neu laden, danach der Hinweis.
    AOwner.FPendingNotice := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistChanged);
    AOwner.FReload(AEntry);
  end
  else if AResult.Denied then
  begin
    AFrame.SetFlag(TAtlasIssueFlag.ChecklistReadOnly, True);
    AFrame.ShowNotice(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistDenied));
  end
  else if AResult.Error <> TAtlasCiFetchError.Cancelled then
  begin
    AFrame.ShowNotice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueChecklistFailed,
      [TAtlasIssueTip.ErrorText(AResult.Error, AEntry.Key)]));
  end;
end;

/// <summary>Im Hauptthread: Zwischenspeicher, nur lesbare Issues und Fenster nachführen.</summary>
procedure Written(AOwner: TAtlasIdeIssueChecklists; const AEntry: TAtlasIssueHistoryEntry;
  const AResult: TChecklistResult);
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
  mContext: TAtlasIdeIssueContext;
begin
  mContext := AOwner.FContext;
  AOwner.FWriting := False;
  mContext.ReleaseThreads(False);
  if not mContext.Started then
  begin
    Exit;
  end;
  LogWritten(mContext.ProviderOf(AEntry.Target), AResult);
  if AResult.Applied and mContext.Cache.Get(AEntry.Target, AEntry.Key, TAtlasIdeIssueContext.NowUtc, mDetails) then
  begin
    // Der geschriebene Text ist der neue Stand, auch fürs Statusfeld.
    mDetails.Description := AResult.Text;
    mDetails.Fetched := TAtlasIdeIssueContext.NowUtc;
    mContext.Cache.Put(AEntry.Target, mDetails);
  end;
  if AResult.Denied then
  begin
    AOwner.FReadOnly.Add(ReadOnlyKey(AEntry));
  end;
  mFrame := mContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.SetFlag(TAtlasIssueFlag.ChecklistBusy, False);
  end;
  if (mFrame <> nil) and mContext.HasCurrent and mContext.Current.SameAs(AEntry) then
  begin
    ShowWritten(AOwner, mFrame, AEntry, AResult);
  end;
end;

/// <summary>Schreibauftrag im Hintergrund; das Ergebnis über Written im Hauptthread.</summary>
procedure StartWrite(AOwner: TAtlasIdeIssueChecklists; const AJob: TChecklistJob);
var
  mKeep: IInterface;
  mJob: TChecklistJob;
begin
  mKeep := AOwner.FContext.Keep;
  mJob := AJob;
  AOwner.FContext.Run(TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TChecklistResult;
    begin
      try
        mResult := WriteChecklist(mJob);
      except
        on E: Exception do
        begin
          mResult := Default(TChecklistResult);
          mResult.Error := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Vorschau: Checkliste mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
      mJob.Editor := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if mKeep <> nil then
          begin
            Written(AOwner, mJob.Entry, mResult);
          end;
        end);
    end));
end;

/// <summary>Ohne Schreibfähigkeit oder ohne Token wie eine Ablehnung des Trackers.</summary>
function Denied: TChecklistResult;
begin
  Result := Default(TChecklistResult);
  Result.Denied := True;
  Result.Error := TAtlasCiFetchError.Unauthorized;
end;

procedure ChangeChecklist(AOwner: TAtlasIdeIssueChecklists; AChange: TChecklistChange;
  const AItem: TAtlasChecklistItem; const AText: string);
var
  mJob: TChecklistJob;
  mProvider: IAtlasTrackerProvider;
  mFrame: TAtlasIssueFrame;
begin
  mJob := Default(TChecklistJob);
  mJob.Entry := AOwner.FContext.Current;
  mJob.Change := AChange;
  mJob.Item := AItem;
  mJob.Text := AText;
  mProvider := AOwner.FContext.ProviderOf(mJob.Entry.Target);
  if Supports(mProvider, IAtlasTrackerDescriptions, mJob.Editor) then
  begin
    mJob.Transport := AOwner.FContext.TransportOf(mProvider, mJob.Entry.Target);
  end;
  // Ohne Token darf Atlas nicht schreiben.
  if mJob.Transport = nil then
  begin
    Written(AOwner, mJob.Entry, Denied);
    Exit;
  end;
  AOwner.FWriting := True;
  mFrame := AOwner.FContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.SetFlag(TAtlasIssueFlag.ChecklistBusy, True);
  end;
  AOwner.FContext.ReleaseThreads(False);
  StartWrite(AOwner, mJob);
end;

/// <summary>Frischer Stand im Zwischenspeicher, oder diese Kennung wurde eben erst versucht.</summary>
function PrefetchFresh(AOwner: TAtlasIdeIssueChecklists; const AEntry: TAtlasIssueHistoryEntry): Boolean;
var
  mDetails: TAtlasTrackerDetails;
  mNow: TDateTime;
begin
  mNow := TAtlasIdeIssueContext.NowUtc;
  Result := AOwner.FContext.Cache.Get(AEntry.Target, AEntry.Key, mNow, mDetails) and
    (mNow - mDetails.Fetched < TAtlasIdeIssueChecklists.cPrefetchMinutes / MinsPerDay);
  if not Result then
  begin
    Result := SameText(AOwner.FPrefetchKey, ReadOnlyKey(AEntry)) and
      (mNow - AOwner.FPrefetchAt < TAtlasIdeIssueChecklists.cPrefetchMinutes / MinsPerDay);
  end;
end;

procedure Prefetched(AOwner: TAtlasIdeIssueChecklists; const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
  const ADetails: TAtlasTrackerDetails);
var
  mDetails: TAtlasTrackerDetails;
begin
  AOwner.FPrefetching := False;
  AOwner.FContext.ReleaseThreads(False);
  if not AOwner.FContext.Started or not ASucceeded then
  begin
    Exit;
  end;
  mDetails := ADetails;
  mDetails.Fetched := TAtlasIdeIssueContext.NowUtc;
  AOwner.FContext.Cache.Put(AEntry.Target, mDetails);
end;

/// <summary>Auffrischen im Hintergrund; das Ergebnis über Prefetched im Hauptthread.</summary>
procedure StartPrefetch(AOwner: TAtlasIdeIssueChecklists; const AEntry: TAtlasIssueHistoryEntry;
  const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport);
var
  mKeep: IInterface;
  mEntry: TAtlasIssueHistoryEntry;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mComments: Boolean;
begin
  mKeep := AOwner.FContext.Keep;
  mEntry := AEntry;
  mProvider := AProvider;
  mTransport := ATransport;
  mComments := TAtlasIdeSettings.Current.IssuesPreviewComments;
  AOwner.FContext.Run(TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mResult := TAtlasTrackerDetails.Empty;
      mOk := False;
      try
        mOk := mProvider.Details(TAtlasTrackerCall.Create(mEntry.Target, mTransport, TAtlasIssuePreview.cTimeoutMs),
          mEntry.Key, mComments, mResult, mError);
      except
        on Exception do
          mOk := False;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if mKeep <> nil then
          begin
            Prefetched(AOwner, mEntry, mOk, mResult);
          end;
        end);
    end));
end;

{ TAtlasIdeIssueChecklists }

constructor TAtlasIdeIssueChecklists.Create(AContext: TAtlasIdeIssueContext;
  const AReload: TProc<TAtlasIssueHistoryEntry>);
begin
  inherited Create;
  FContext := AContext;
  FReload := AReload;
  FReadOnly := TStringList.Create;
  FReadOnly.Sorted := True;
  FReadOnly.Duplicates := dupIgnore;
end;

destructor TAtlasIdeIssueChecklists.Destroy;
begin
  FReload := nil;
  FReadOnly.Free;
  inherited;
end;

procedure TAtlasIdeIssueChecklists.Prepare(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry);
var
  mProvider: IAtlasTrackerProvider;
begin
  AFrame.SetFlag(TAtlasIssueFlag.Checklists, TAtlasIdeSettings.Current.IssuesPreviewChecklists);
  // Nur lesbar: Anbieter kann nicht schreiben, oder der Tracker hat in dieser Sitzung abgelehnt.
  mProvider := FContext.ProviderOf(AEntry.Target);
  AFrame.SetFlag(TAtlasIssueFlag.ChecklistReadOnly, (mProvider = nil) or
    not Supports(mProvider, IAtlasTrackerDescriptions) or (FReadOnly.IndexOf(ReadOnlyKey(AEntry)) >= 0));
end;

procedure TAtlasIdeIssueChecklists.Toggle(AIndex: Integer);
var
  mFrame: TAtlasIssueFrame;
  mItem: TAtlasChecklistItem;
begin
  mFrame := FContext.Frame;
  // Der Punkt, wie er angezeigt wurde; ChangeChecklist vergleicht ihn mit dem aktuellen Text.
  if Writable(Self, mFrame) and TAtlasTrackerChecklist.Find(mFrame.State.Details.Description, AIndex, mItem) then
  begin
    ChangeChecklist(Self, TChecklistChange.Toggle, mItem, '');
  end;
end;

procedure TAtlasIdeIssueChecklists.AddTask;
var
  mText: string;
begin
  if not Writable(Self, FContext.Frame) then
  begin
    Exit;
  end;
  mText := '';
  if not InputQuery(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistAdd),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistAddPrompt), mText) or (Trim(mText) = '') then
  begin
    Exit;
  end;
  // Während des Dialogs kann das Fenster gewechselt haben.
  if FContext.Started and FContext.HasCurrent and not FWriting then
  begin
    ChangeChecklist(Self, TChecklistChange.Append, Default(TAtlasChecklistItem), mText);
  end;
end;

function TAtlasIdeIssueChecklists.TakeNotice: string;
begin
  Result := FPendingNotice;
  FPendingNotice := '';
end;

function TAtlasIdeIssueChecklists.Progress(const ATarget: TAtlasTrackerTarget; const AKey: string;
  out AProgress: TAtlasChecklistProgress): Boolean;
var
  mDetails: TAtlasTrackerDetails;
begin
  AProgress := TAtlasChecklistProgress.Create(0, 0);
  Result := (Trim(AKey) <> '') and FContext.Cache.Get(ATarget, AKey, TAtlasIdeIssueContext.NowUtc, mDetails);
  if Result then
  begin
    AProgress := TAtlasTrackerChecklist.Progress(mDetails.Description);
  end;
end;

procedure TAtlasIdeIssueChecklists.Prefetch(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mEntry: TAtlasIssueHistoryEntry;
begin
  if not FContext.Started or FPrefetching or (Trim(AKey) = '') or not FContext.CanTransport then
  begin
    Exit;
  end;
  mEntry := TAtlasIssueHistoryEntry.Create(ATarget, AKey);
  if PrefetchFresh(Self, mEntry) then
  begin
    Exit;
  end;
  FPrefetchKey := ReadOnlyKey(mEntry);
  FPrefetchAt := TAtlasIdeIssueContext.NowUtc;
  mProvider := FContext.ProviderOf(ATarget);
  mTransport := FContext.TransportOf(mProvider, ATarget);
  if mTransport <> nil then
  begin
    FPrefetching := True;
    FContext.ReleaseThreads(False);
    StartPrefetch(Self, mEntry, mProvider, mTransport);
  end;
end;

end.
