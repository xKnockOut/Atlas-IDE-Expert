unit Atlas.IDE.Tracker.IssueLookups;

// Kurzabfrage für den Hover über Kennungen im Editor (#1265): Peek liest nur
// den Zwischenspeicher (kein Netz), Lookup fragt im Hintergrund ohne
// Kommentare; gleiche Wünsche laufen einmal, nicht gefundene Kennungen fragt
// Atlas MissingMs lang nicht erneut. Vorhandene Kommentare im
// Zwischenspeicher bleiben erhalten. Protokoll anonym (nie Kennung oder Titel).

interface

uses
  Atlas.Core.CiBuild.Contract,
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Tracker.IssueContext;

type
  /// <summary>Ende einer Kurzabfrage (#1265); im Hauptthread.</summary>
  TAtlasIssueLookupDone = reference to procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
    AError: TAtlasCiFetchError);

  TAtlasIdeIssueLookups = class
  public const
    /// <summary>So lange gilt ein Stand im Zwischenspeicher für den Hover als frisch (keine neue Abfrage).</summary>
    FreshMs = 10 * 60 * 1000;
    /// <summary>So lange fragt der Hover eine nicht gefundene Kennung nicht erneut.</summary>
    MissingMs = 10 * 60 * 1000;
  private
    FContext: TAtlasIdeIssueContext;
    // Laufende Kurzabfragen (Tracker|Kennung → Rückrufe) und nicht gefundene Kennungen (→ Zeitpunkt).
    FLookups: TDictionary<string, TArray<TAtlasIssueLookupDone>>;
    FMissing: TDictionary<string, UInt64>;
    procedure LookedUp(const AId: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
  public
    constructor Create(AContext: TAtlasIdeIssueContext);
    destructor Destroy; override;
    /// <summary>Letzter Stand von AKey aus dem Zwischenspeicher (#1265); ohne Netz.</summary>
    function Peek(const ATarget: TAtlasTrackerTarget; const AKey: string; out ADetails: TAtlasTrackerDetails): Boolean;
    /// <summary>Stand jünger als FreshMs?</summary>
    class function Fresh(const ADetails: TAtlasTrackerDetails): Boolean; static;
    /// <summary>AKey im Hintergrund ohne Kommentare abfragen und in den Zwischenspeicher legen (#1265); ADone im
    /// Hauptthread, auch sofort (kein Anbieter, kein Token, kürzlich nicht gefunden). Nach Stop wirkungslos.
    /// </summary>
    procedure Lookup(const ATarget: TAtlasTrackerTarget; const AKey: string; const ADone: TAtlasIssueLookupDone);
    /// <summary>Rückrufe des Editors nicht mehr aufrufen (Anhalten).</summary>
    procedure Clear;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.IssueCache,
  Atlas.Core.Tracker.Preview;

function LookupId(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := TAtlasTrackerIssueCache.TrackerId(ATarget) + '|' + UpperCase(Trim(AKey));
end;

procedure Deliver(const ADone: TAtlasIssueLookupDone; ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
  AError: TAtlasCiFetchError);
begin
  // Eigene Routine: Die anonyme Methode fängt nur ihre Argumente, nicht die Schleife von LookedUp.
  TAtlasGuard.Run(TAtlasFeature.IssueLinks,
    procedure
    begin
      ADone(ASucceeded, ADetails, AError);
    end);
end;

/// <summary>Kürzlich nicht gefunden (sofort melden) oder läuft schon (anhängen): True = erledigt.</summary>
function Waiting(AOwner: TAtlasIdeIssueLookups; const AId: string; const ADone: TAtlasIssueLookupDone): Boolean;
var
  mAt: UInt64;
  mWaiting: TArray<TAtlasIssueLookupDone>;
  mCount: Integer;
begin
  if AOwner.FMissing.TryGetValue(AId, mAt) then
  begin
    Result := TThread.GetTickCount64 - mAt < TAtlasIdeIssueLookups.MissingMs;
    if Result then
    begin
      ADone(False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.NotFound);
      Exit;
    end;
    AOwner.FMissing.Remove(AId);
  end;
  Result := AOwner.FLookups.TryGetValue(AId, mWaiting);
  if Result then
  begin
    mCount := Length(mWaiting);
    SetLength(mWaiting, mCount + 1);
    mWaiting[mCount] := ADone;
    AOwner.FLookups[AId] := mWaiting;
  end;
end;

function OneWaiting(const ADone: TAtlasIssueLookupDone): TArray<TAtlasIssueLookupDone>;
begin
  SetLength(Result, 1);
  Result[0] := ADone;
end;

/// <summary>Abfrage im Hintergrund; das Ergebnis über LookedUp im Hauptthread.</summary>
procedure StartLookup(AOwner: TAtlasIdeIssueLookups; const AId: string; const ATarget: TAtlasTrackerTarget;
  const AKey: string; const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport);
var
  mKeep: IInterface;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
begin
  mKeep := AOwner.FContext.Keep;
  mProvider := AProvider;
  mTransport := ATransport;
  AOwner.FContext.Run(TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mResult := TAtlasTrackerDetails.Empty;
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := mProvider.Details(TAtlasTrackerCall.Create(ATarget, mTransport, TAtlasIssuePreview.TimeoutMs), AKey,
          False, mResult, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Kennung: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.IssueLinks,
        procedure
        begin
          if mKeep <> nil then
          begin
            AOwner.LookedUp(AId, ATarget, mOk, mResult, mError);
          end;
        end);
    end));
end;

{ TAtlasIdeIssueLookups }

constructor TAtlasIdeIssueLookups.Create(AContext: TAtlasIdeIssueContext);
begin
  inherited Create;
  FContext := AContext;
  FLookups := TDictionary<string, TArray<TAtlasIssueLookupDone>>.Create;
  FMissing := TDictionary<string, UInt64>.Create;
end;

destructor TAtlasIdeIssueLookups.Destroy;
begin
  FLookups.Free;
  FMissing.Free;
  inherited;
end;

procedure TAtlasIdeIssueLookups.Clear;
begin
  FLookups.Clear;
end;

function TAtlasIdeIssueLookups.Peek(const ATarget: TAtlasTrackerTarget; const AKey: string;
  out ADetails: TAtlasTrackerDetails): Boolean;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  Result := (Trim(AKey) <> '') and FContext.Cache.Get(ATarget, AKey, TAtlasIdeIssueContext.NowUtc, ADetails);
end;

class function TAtlasIdeIssueLookups.Fresh(const ADetails: TAtlasTrackerDetails): Boolean;
begin
  Result := (ADetails.Fetched > 0) and (MilliSecondsBetween(TAtlasIdeIssueContext.NowUtc, ADetails.Fetched) < FreshMs);
end;

procedure TAtlasIdeIssueLookups.Lookup(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const ADone: TAtlasIssueLookupDone);
var
  mId: string;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mError: TAtlasCiFetchError;
begin
  if not FContext.Started or (Trim(AKey) = '') or not Assigned(ADone) then
  begin
    Exit;
  end;
  mId := LookupId(ATarget, AKey);
  if Waiting(Self, mId, ADone) then
  begin
    Exit;
  end;
  mProvider := FContext.ProviderOf(ATarget);
  // Ohne Token kein Netz (wie die Vorschau, ohne Dialog).
  mTransport := FContext.TransportOf(mProvider, ATarget);
  if mTransport = nil then
  begin
    mError := TAtlasCiFetchError.Unauthorized;
    if (mProvider = nil) or not FContext.CanTransport then
    begin
      mError := TAtlasCiFetchError.NotConfigured;
    end;
    ADone(False, TAtlasTrackerDetails.Empty, mError);
    Exit;
  end;
  FLookups.Add(mId, OneWaiting(ADone));
  FContext.ReleaseThreads(False);
  StartLookup(Self, mId, ATarget, AKey, mProvider, mTransport);
end;

procedure TAtlasIdeIssueLookups.LookedUp(const AId: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mWaiting: TArray<TAtlasIssueLookupDone>;
  mDone: TAtlasIssueLookupDone;
  mDetails, mCached: TAtlasTrackerDetails;
begin
  FContext.ReleaseThreads(False);
  if not FContext.Started or not FLookups.TryGetValue(AId, mWaiting) then
  begin
    Exit;
  end;
  FLookups.Remove(AId);
  mDetails := ADetails;
  if ASucceeded then
  begin
    mDetails.Fetched := TAtlasIdeIssueContext.NowUtc;
    // Ohne Kommentare gefragt: die der Vorschau nicht verlieren.
    if not mDetails.CommentsLoaded and FContext.Cache.Get(ATarget, mDetails.Key, TAtlasIdeIssueContext.NowUtc,
      mCached) and mCached.CommentsLoaded then
    begin
      mDetails.CommentsLoaded := True;
      mDetails.Comments := mCached.Comments;
    end;
    FContext.Cache.Put(ATarget, mDetails);
  end
  else if AError = TAtlasCiFetchError.NotFound then
  begin
    FMissing.AddOrSetValue(AId, TThread.GetTickCount64);
  end;
  // Anonym: nie Kennung oder Titel.
  TAtlasGuard.Log('Issue-Kennung: ' + TAtlasIdeIssueContext.LoadState(ASucceeded, AError));
  for mDone in mWaiting do
  begin
    Deliver(mDone, ASucceeded, mDetails, AError);
  end;
end;

end.
