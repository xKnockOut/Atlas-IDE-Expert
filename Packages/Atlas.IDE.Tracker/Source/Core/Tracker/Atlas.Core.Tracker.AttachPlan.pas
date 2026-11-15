unit Atlas.Core.Tracker.AttachPlan;

// Entscheidungen von „An Issue anhängen …“ (#1276) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.Attach)
// ruft nur noch Dialog, Hintergrund-Thread, Zwischenablage und Browser:
// - ob es etwas zu senden gibt;
// - welche Meldung nach dem Senden erscheint (abgebrochen still, Fehler mit bzw. ohne hochgeladene Dateien,
//   GitHub über die Zwischenablage, hochgeladen mit bzw. ohne Kommentar, nur Kommentar);
// - das anonyme Protokoll (Anbieter, Anzahl, Ergebnis, Fehlerart; nie Kennung, Adresse oder Inhalt).

interface

uses
  Atlas.Core.CiBuild.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Meldung nach dem Senden.</summary>
  TAtlasAttachReport = (Silent, CommentFailed, Failed, Fallback, DoneComment, Done, Commented, Nothing);
{$SCOPEDENUMS OFF}

  TAtlasAttachPlan = class
  public
    /// <summary>Gibt es etwas zu senden: Kennung AKey und Dateien (AFileCount) oder Kommentar AComment?</summary>
    class function HasWork(const AKey: string; AFileCount: Integer; const AComment: string): Boolean; static;
    /// <summary>Meldung zum Ergebnis: ASucceeded/AError, AUploaded hochgeladene Dateien, ACommented Kommentar
    /// geschrieben, AFallback GitHub ohne Hochladen.</summary>
    class function ReportOf(ASucceeded: Boolean; AError: TAtlasCiFetchError; AUploaded: Integer; ACommented,
      AFallback: Boolean): TAtlasAttachReport; static;
    /// <summary>Protokollzeile, anonym: Anbieter AProvider, Zahl der Dateien AFiles, Ergebnis oder Fehlerart.
    /// </summary>
    class function SentLog(const AProvider: string; AFiles: Integer; ASucceeded: Boolean;
      AError: TAtlasCiFetchError): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cLogSent = 'Anhängen: %s, %d Dateien, %s'; // german-ok: Protokollzeile, unverändert übernommen
  cLogDone = 'gesendet';
  cLogFailed = 'nicht gesendet (%s)'; // german-ok: Protokollzeile, unverändert übernommen

class function TAtlasAttachPlan.HasWork(const AKey: string; AFileCount: Integer; const AComment: string): Boolean;
begin
  Result := (AKey <> '') and ((AFileCount > 0) or (AComment <> ''));
end;

class function TAtlasAttachPlan.ReportOf(ASucceeded: Boolean; AError: TAtlasCiFetchError; AUploaded: Integer;
  ACommented, AFallback: Boolean): TAtlasAttachReport;
begin
  if AError = TAtlasCiFetchError.Cancelled then
  begin
    Result := TAtlasAttachReport.Silent;
  end
  else if not ASucceeded and (AUploaded > 0) then
  begin
    Result := TAtlasAttachReport.CommentFailed;
  end
  else if not ASucceeded then
  begin
    Result := TAtlasAttachReport.Failed;
  end
  else if AFallback then
  begin
    Result := TAtlasAttachReport.Fallback;
  end
  else if (AUploaded > 0) and ACommented then
  begin
    Result := TAtlasAttachReport.DoneComment;
  end
  else if AUploaded > 0 then
  begin
    Result := TAtlasAttachReport.Done;
  end
  else if ACommented then
  begin
    Result := TAtlasAttachReport.Commented;
  end
  else
  begin
    Result := TAtlasAttachReport.Nothing;
  end;
end;

class function TAtlasAttachPlan.SentLog(const AProvider: string; AFiles: Integer; ASucceeded: Boolean;
  AError: TAtlasCiFetchError): string;
var
  mState: string;
begin
  mState := cLogDone;
  if not ASucceeded then
  begin
    mState := Format(cLogFailed, [TAtlasCiBuild.ErrorKey(AError)]);
  end;
  Result := Format(cLogSent, [AProvider, AFiles, mState]);
end;

end.
