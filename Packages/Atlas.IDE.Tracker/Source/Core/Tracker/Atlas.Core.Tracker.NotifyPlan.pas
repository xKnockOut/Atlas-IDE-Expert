unit Atlas.Core.Tracker.NotifyPlan;

// Entscheidungen der Meldungen zu meinen Issues (#1271) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.Notify)
// ruft nur noch Takt, Hintergrundarbeiter, Benachrichtigungszentrale und Einblendung:
// - Fälligkeit einer Verbindung (Takt bzw. beim Öffnen von „Meine Issues“), Anmeldename einmal je Verbindung, ob ein
//   Fehler gemeldet wird.
// - Ein- und Ausschalten: Was vorher geschah, ist nicht neu; Punkte verschwinden.
// - Tracker und Sprungstelle einer Meldung (GitHub: Repository der Meldung; wieder geöffnet, #2127: der Kommentar).
// - Punkte und Sprungstelle je Tracker.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Notify,
  Atlas.Core.Tracker.Reopened;

type
  TAtlasNotifyPlan = class
  public
    /// <summary>Verbindung mit ASchedule fällig? AOnDemand: beim Öffnen von „Meine Issues“; AActive: Benutzer aktiv;
    /// AIntervalMinutes: issues.notify.intervalMinutes.</summary>
    class function IsDue(var ASchedule: TAtlasTrackerNotifySchedule; AOnDemand, AActive: Boolean; ANowMs: UInt64;
      AIntervalMinutes: Integer): Boolean; static;
    /// <summary>Anmeldenamen vor der Abfrage holen: noch unbekannt (AMe '') und der Anbieter nennt eine Adresse dafür.
    /// </summary>
    class function AsksLogin(const AMe, AProbeUrl: string): Boolean; static;
    /// <summary>Fehler melden? AFirst: erster Fehlschlag seit dem letzten Erfolg; abgebrochen meldet nie.</summary>
    class function ReportsError(AFirst: Boolean; AError: TAtlasCiFetchError): Boolean; static;
    /// <summary>issues.notify AEnabled gegenüber dem Stand in AFile geändert? Dann gilt für jede Verbindung „ab
    /// ANow“, ohne Last-Modified und Punkte, und AFile merkt den neuen Schalter.</summary>
    class function Switch(var AFile: TAtlasTrackerNotifyFile; AEnabled: Boolean; ANow: TDateTime): Boolean; static;
    /// <summary>Tracker der Meldung: GitHub das Repository der Meldung, nicht das des Projekts.</summary>
    class function NoticeTarget(const ATarget: TAtlasTrackerTarget; const ANotice: TAtlasTrackerNotice):
      TAtlasTrackerTarget; static;
    /// <summary>Sprungstelle beim Öffnen: wieder geöffnet (AReopened) mit Kommentar dessen Zeitpunkt, sonst der erste
    /// neue Kommentar.</summary>
    class function NoticeAnchor(const ANotice: TAtlasTrackerNotice; AReopened: Boolean;
      const AReopen: TAtlasTrackerReopen): TDateTime; static;
    /// <summary>Kennungen mit Punkt in AConnection für ATarget (GitHub: nur dieses Repository).</summary>
    class function UnseenKeys(const AConnection: TAtlasTrackerNotifyConnection;
      const ATarget: TAtlasTrackerTarget): TArray<string>; static;
    /// <summary>Erster neuer Kommentar von AKey mit Punkt (UTC); 0 ohne.</summary>
    class function UnseenAnchor(const AConnection: TAtlasTrackerNotifyConnection; const ATarget: TAtlasTrackerTarget;
      const AKey: string): TDateTime; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasNotifyPlan.IsDue(var ASchedule: TAtlasTrackerNotifySchedule; AOnDemand, AActive: Boolean;
  ANowMs: UInt64; AIntervalMinutes: Integer): Boolean;
begin
  if AOnDemand then
  begin
    Result := ASchedule.DueOnDemand(ANowMs);
  end
  else
  begin
    Result := ASchedule.Due(ANowMs, AActive, AIntervalMinutes);
  end;
end;

class function TAtlasNotifyPlan.AsksLogin(const AMe, AProbeUrl: string): Boolean;
begin
  Result := (AMe = '') and (AProbeUrl <> '');
end;

class function TAtlasNotifyPlan.ReportsError(AFirst: Boolean; AError: TAtlasCiFetchError): Boolean;
begin
  Result := AFirst and (AError <> TAtlasCiFetchError.Cancelled);
end;

class function TAtlasNotifyPlan.Switch(var AFile: TAtlasTrackerNotifyFile; AEnabled: Boolean;
  ANow: TDateTime): Boolean;
var
  mIndex: Integer;
begin
  Result := AEnabled <> AFile.Enabled;
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AFile.Connections) do
  begin
    AFile.Connections[mIndex].Since := ANow;
    AFile.Connections[mIndex].LastModified := '';
    AFile.Connections[mIndex].Unseen := nil;
  end;
  AFile.Enabled := AEnabled;
end;

class function TAtlasNotifyPlan.NoticeTarget(const ATarget: TAtlasTrackerTarget;
  const ANotice: TAtlasTrackerNotice): TAtlasTrackerTarget;
begin
  Result := ATarget;
  if ANotice.Project <> '' then
  begin
    Result.Project := ANotice.Project;
  end;
end;

class function TAtlasNotifyPlan.NoticeAnchor(const ANotice: TAtlasTrackerNotice; AReopened: Boolean;
  const AReopen: TAtlasTrackerReopen): TDateTime;
begin
  Result := ANotice.Anchor;
  if AReopened and (AReopen.CommentAt > 0) then
  begin
    Result := AReopen.CommentAt;
  end;
end;

class function TAtlasNotifyPlan.UnseenKeys(const AConnection: TAtlasTrackerNotifyConnection;
  const ATarget: TAtlasTrackerTarget): TArray<string>;
var
  mItem: TAtlasTrackerUnseen;
  mProject: string;
  mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AConnection.Unseen));
  mCount := 0;
  mProject := TAtlasTrackerNotify.UnseenProject(ATarget);
  for mItem in AConnection.Unseen do
  begin
    if SameText(mItem.Project, mProject) then
    begin
      Result[mCount] := mItem.Key;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TAtlasNotifyPlan.UnseenAnchor(const AConnection: TAtlasTrackerNotifyConnection;
  const ATarget: TAtlasTrackerTarget; const AKey: string): TDateTime;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := AConnection.IndexOfUnseen(AKey, TAtlasTrackerNotify.UnseenProject(ATarget));
  if mIndex >= 0 then
  begin
    Result := AConnection.Unseen[mIndex].Anchor;
  end;
end;

end.
