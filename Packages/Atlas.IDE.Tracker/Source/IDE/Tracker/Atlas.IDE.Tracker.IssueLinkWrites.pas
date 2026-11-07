unit Atlas.IDE.Tracker.IssueLinkWrites;

// Verknüpfungen im Fenster „Atlas-Issue“ (#1279, issues.preview.links): kann
// der Anbieter schreiben (IAtlasTrackerLinkWriter), legen „Unteraufgabe
// anlegen …“ und „Verknüpfen …“ nach dem Dialog im Hintergrund an
// (Zeitgrenze WriteTimeoutMs), danach lädt das Fenster neu und meldet das
// Ergebnis über dem Inhalt. CheckBlocked liest für „Beginnen“
// (issues.warnBlocked) die Verknüpfungen frisch (BlockedTimeoutMs, ohne
// Kommentare), ohne Netz aus dem Zwischenspeicher.

interface

uses
  Atlas.Core.CiBuild.Contract,
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Tracker.IssueContext;

type
  /// <summary>Schreibender Auftrag im Hintergrund (#1279); AKey: Kennung des angelegten bzw. verknüpften Issues.
  /// </summary>
  TAtlasIssueWriteWork = reference to function(const AWriter: IAtlasTrackerLinkWriter;
    const ATransport: IAtlasCiTransport; out AKey: string; out AError: TAtlasCiFetchError): Boolean;
  /// <summary>Ende eines schreibenden Auftrags, im Hauptthread.</summary>
  TAtlasIssueWriteDone = reference to procedure(ASucceeded: Boolean; const AKey: string;
    AError: TAtlasCiFetchError);
  /// <summary>Ergebnis von CheckBlocked im Hauptthread: AKnown = frisch geladen oder aus dem Zwischenspeicher.
  /// </summary>
  TAtlasIssueBlockedDone = reference to procedure(AKnown: Boolean; const ADetails: TAtlasTrackerDetails);

  TAtlasIdeIssueLinkWrites = class
  public const
    /// <summary>Zeitgrenze für Anlegen und Verknüpfen (#1279).</summary>
    cWriteTimeoutMs = 15000;
    /// <summary>Zeitgrenze der Prüfung vor „Beginnen“ (#1279).</summary>
    cBlockedTimeoutMs = 5000;
  private
    FContext: TAtlasIdeIssueContext;
    /// <summary>Das gezeigte Issue neu laden.</summary>
    FRefresh: TProc;
    /// <summary>Meldung nach Anlegen bzw. Verknüpfen, gezeigt mit dem frisch geladenen Stand.</summary>
    FNotice: string;
  public
    constructor Create(AContext: TAtlasIdeIssueContext; const ARefresh: TProc);
    destructor Destroy; override;
    /// <summary>„Unteraufgabe anlegen …“ für das gezeigte Issue.</summary>
    procedure CreateSubtask;
    /// <summary>„Verknüpfen …“ für das gezeigte Issue.</summary>
    procedure AddLink;
    /// <summary>Meldung für den frisch geladenen Stand ('' ohne); danach leer.</summary>
    function TakeNotice: string;
    /// <summary>Verknüpfungen von AKey für die Warnung beim Beginnen (#1279): frisch im Hintergrund, ohne Antwort
    /// der letzte Stand; ADone im Hauptthread (sofort, wenn kein Transport da ist).</summary>
    procedure CheckBlocked(const ATarget: TAtlasTrackerTarget; const AKey: string;
      const ADone: TAtlasIssueBlockedDone);
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.LinkDialogs;

/// <summary>Projekt einer YouTrack-Kennung ("ATL-12" → "ATL"); '' ohne Bindestrich.</summary>
function ProjectOfKey(const AKey: string): string;
var
  mAt: Integer;
begin
  Result := '';
  mAt := LastDelimiter('-', AKey);
  if mAt > 1 then
  begin
    Result := Copy(AKey, 1, mAt - 1);
  end;
end;

/// <summary>Gezeigtes Issue mit Inhalt; sonst False.</summary>
function ShownKey(AOwner: TAtlasIdeIssueLinkWrites; out AKey: string): Boolean;
var
  mFrame: TAtlasIssueFrame;
begin
  AKey := '';
  mFrame := AOwner.FContext.Frame;
  Result := AOwner.FContext.Started and AOwner.FContext.HasCurrent and (mFrame <> nil);
  Result := Result and mFrame.State.HasDetails;
  if Result then
  begin
    AKey := mFrame.State.Details.Key;
  end;
end;

procedure Written(AOwner: TAtlasIdeIssueLinkWrites; const AText: string);
begin
  if not AOwner.FContext.Started then
  begin
    Exit;
  end;
  TAtlasGuard.Log('Issue-Vorschau: Verknüpfung geschrieben');
  // Neu laden: Der Baum zeigt die neue Unteraufgabe bzw. Verknüpfung, die Meldung steht darüber.
  AOwner.FNotice := AText;
  AOwner.FRefresh();
end;

procedure WriteFailed(AOwner: TAtlasIdeIssueLinkWrites; const AText: string; AError: TAtlasCiFetchError);
var
  mFrame: TAtlasIssueFrame;
begin
  if not AOwner.FContext.Started then
  begin
    Exit;
  end;
  TAtlasGuard.Log('Issue-Vorschau: Schreiben nicht möglich (' + TAtlasCiBuild.ErrorKey(AError) + ')');
  mFrame := AOwner.FContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.ShowError(AText, TAtlasIssuePreview.FixOf(AError));
  end;
end;

/// <summary>AWork im Hintergrund; ADone im Hauptthread.</summary>
procedure StartWrite(AOwner: TAtlasIdeIssueLinkWrites; const AWriter: IAtlasTrackerLinkWriter;
  const ATransport: IAtlasCiTransport; const AWork: TAtlasIssueWriteWork; const ADone: TAtlasIssueWriteDone);
var
  mWriter: IAtlasTrackerLinkWriter;
  mTransport: IAtlasCiTransport;
begin
  mWriter := AWriter;
  mTransport := ATransport;
  AOwner.FContext.Run(TThread.CreateAnonymousThread(
    procedure
    var
      mKey: string;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mKey := '';
      mError := TAtlasCiFetchError.Network;
      mOk := False;
      try
        mOk := AWork(mWriter, mTransport, mKey, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Vorschau: Schreiben mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      mWriter := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          ADone(mOk, mKey, mError);
        end);
    end));
end;

procedure RunWrite(AOwner: TAtlasIdeIssueLinkWrites; const ATarget: TAtlasTrackerTarget;
  const AWork: TAtlasIssueWriteWork; const ADone: TAtlasIssueWriteDone);
var
  mProvider: IAtlasTrackerProvider;
  mWriter: IAtlasTrackerLinkWriter;
  mTransport: IAtlasCiTransport;
  mFrame: TAtlasIssueFrame;
begin
  mProvider := AOwner.FContext.ProviderOf(ATarget);
  if not Supports(mProvider, IAtlasTrackerLinkWriter, mWriter) or not AOwner.FContext.CanTransport then
  begin
    ADone(False, '', TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  // Liest das Token ohne Dialog; ohne Token wie eine abgelehnte Anmeldung (Knopf „Token hinterlegen …“).
  mTransport := AOwner.FContext.TransportOf(mProvider, ATarget);
  if mTransport = nil then
  begin
    ADone(False, '', TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  mFrame := AOwner.FContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.ShowError(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinkWorking), TAtlasIssueFix.None);
  end;
  AOwner.FContext.ReleaseThreads(False);
  StartWrite(AOwner, mWriter, mTransport, AWork, ADone);
end;

/// <summary>Meldung nach dem Anlegen einer Unteraufgabe unter AParent.</summary>
procedure SubtaskDone(AOwner: TAtlasIdeIssueLinkWrites; ASucceeded: Boolean; const AKey, AParent: string;
  AError: TAtlasCiFetchError);
begin
  if ASucceeded then
  begin
    Written(AOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueSubtaskCreated, [AKey]));
  end
  else if AKey <> '' then
  begin
    WriteFailed(AOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueSubtaskNotLinked, [AKey,
      TAtlasIssueTip.ErrorText(AError, AParent)]), AError);
  end
  else
  begin
    WriteFailed(AOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueSubtaskFailed,
      [TAtlasIssueTip.ErrorText(AError, AParent)]), AError);
  end;
end;

type
  /// <summary>Prüfung vor „Beginnen“: was abgefragt wird und was ohne Antwort gilt.</summary>
  TBlockedJob = record
    Target: TAtlasTrackerTarget;
    Key: string;
    Provider: IAtlasTrackerProvider;
    Transport: IAtlasCiTransport;
    /// <summary>Ohne Antwort: Stand aus dem Zwischenspeicher (Known = vorhanden).</summary>
    Known: Boolean;
    Cached: TAtlasTrackerDetails;
  end;

/// <summary>Frischer Stand im Hintergrund; ohne Antwort AJob.Known/AJob.Cached.</summary>
procedure StartBlocked(AOwner: TAtlasIdeIssueLinkWrites; const AJob: TBlockedJob; const ADone: TAtlasIssueBlockedDone);
var
  mJob: TBlockedJob;
begin
  mJob := AJob;
  AOwner.FContext.Run(TThread.CreateAnonymousThread(
    procedure
    var
      mDetails: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mDetails := TAtlasTrackerDetails.Empty;
      mOk := False;
      try
        mOk := mJob.Provider.Details(TAtlasTrackerCall.Create(mJob.Target, mJob.Transport,
          TAtlasIdeIssueLinkWrites.cBlockedTimeoutMs), mJob.Key, False, mDetails, mError);
      except
        on E: Exception do
        begin
          mOk := False;
          TAtlasGuard.Log('Issue-Vorschau: Prüfung vor „Beginnen“ mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          // Ohne Antwort der letzte Stand aus dem Zwischenspeicher.
          if mOk then
          begin
            ADone(True, mDetails);
          end
          else
          begin
            ADone(mJob.Known, mJob.Cached);
          end;
        end);
    end));
end;

{ TAtlasIdeIssueLinkWrites }

constructor TAtlasIdeIssueLinkWrites.Create(AContext: TAtlasIdeIssueContext; const ARefresh: TProc);
begin
  inherited Create;
  FContext := AContext;
  FRefresh := ARefresh;
end;

destructor TAtlasIdeIssueLinkWrites.Destroy;
begin
  FRefresh := nil;
  inherited;
end;

function TAtlasIdeIssueLinkWrites.TakeNotice: string;
begin
  Result := FNotice;
  FNotice := '';
end;

procedure TAtlasIdeIssueLinkWrites.CreateSubtask;
var
  mTarget: TAtlasTrackerTarget;
  mParent, mProject, mTitle, mDescription: string;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueLinkWrites;
begin
  if not ShownKey(Self, mParent) then
  begin
    Exit;
  end;
  mTarget := FContext.Current.Target;
  // Vorbelegt: das Projekt des übergeordneten Issues (GitHub owner/repo, YouTrack Kürzel).
  mProject := mTarget.Project;
  if mProject = '' then
  begin
    mProject := ProjectOfKey(mParent);
  end;
  if not TAtlasSubtaskDialog.Execute(mParent, mProject, mTitle, mDescription) then
  begin
    Exit;
  end;
  mKeep := FContext.Keep;
  mOwner := Self;
  RunWrite(Self, mTarget,
    function(const AWriter: IAtlasTrackerLinkWriter; const ATransport: IAtlasCiTransport; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean
    begin
      Result := AWriter.CreateSubtask(TAtlasTrackerCall.Create(mTarget, ATransport, cWriteTimeoutMs), mParent, mTitle,
        mDescription, AKey, AError);
    end,
    procedure(ASucceeded: Boolean; const AKey: string; AError: TAtlasCiFetchError)
    begin
      if mKeep <> nil then
      begin
        SubtaskDone(mOwner, ASucceeded, AKey, mParent, AError);
      end;
    end);
end;

procedure TAtlasIdeIssueLinkWrites.AddLink;
var
  mTarget: TAtlasTrackerTarget;
  mKey, mOther: string;
  mKind: TAtlasTrackerLinkKind;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueLinkWrites;
begin
  if not ShownKey(Self, mKey) then
  begin
    Exit;
  end;
  mTarget := FContext.Current.Target;
  if not TAtlasIssueLinkDialog.Execute(mKey, mTarget.Provider, mKind, mOther) then
  begin
    Exit;
  end;
  mKeep := FContext.Keep;
  mOwner := Self;
  RunWrite(Self, mTarget,
    function(const AWriter: IAtlasTrackerLinkWriter; const ATransport: IAtlasCiTransport; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean
    begin
      AKey := mOther;
      Result := AWriter.AddLink(TAtlasTrackerCall.Create(mTarget, ATransport, cWriteTimeoutMs), mKey, mKind, mOther,
        AError);
    end,
    procedure(ASucceeded: Boolean; const AKey: string; AError: TAtlasCiFetchError)
    begin
      if mKeep = nil then
      begin
        Exit;
      end;
      if ASucceeded then
      begin
        Written(mOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueLinkAdded, [mKey, mOther]));
      end
      else
      begin
        WriteFailed(mOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueLinkFailed,
          [TAtlasIssueTip.ErrorText(AError, mOther)]), AError);
      end;
    end);
end;

procedure TAtlasIdeIssueLinkWrites.CheckBlocked(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const ADone: TAtlasIssueBlockedDone);
var
  mJob: TBlockedJob;
begin
  mJob := Default(TBlockedJob);
  mJob.Target := ATarget;
  mJob.Key := AKey;
  mJob.Cached := TAtlasTrackerDetails.Empty;
  mJob.Known := FContext.Started and FContext.Cache.Get(ATarget, AKey, TAtlasIdeIssueContext.NowUtc, mJob.Cached);
  if FContext.Started then
  begin
    mJob.Provider := FContext.ProviderOf(ATarget);
  end;
  mJob.Transport := FContext.TransportOf(mJob.Provider, ATarget);
  if mJob.Transport = nil then
  begin
    ADone(mJob.Known, mJob.Cached);
    Exit;
  end;
  FContext.ReleaseThreads(False);
  StartBlocked(Self, mJob, ADone);
end;

end.
