unit Atlas.Core.Tracker.TimePlan;

// Entscheidungen der Zeiterfassung (#1267) ohne IDE prüfbar (#1967); die IDE (Atlas.IDE.Tracker.TimeTracking)
// ruft nur noch Takt, Statusfeld, Dialoge und die Datei time.json:
// - Welche Eingabe zählt (nur neue Eingaben, nur bei IDE vorn) und wann sie war.
// - Summe des aktuellen Issues aus Datei, ungeschriebener Uhr und Spannen, die noch nicht in der Datei sind.
// - Wann gespeichert, beim Wechsel angeboten und nach dem Beenden angeboten wird; wie viel Zeit mindestens.
// - Von Hand korrigierte Dauer („0“ ist erlaubt) und der Kommentar für GitHub.

interface

uses
  Atlas.Core.Tracker.TimeLog;

type
{$SCOPEDENUMS ON}
  /// <summary>Letzte Eingabe: unverändert (nichts tun), außerhalb der IDE (nur merken), in der IDE (merken und als
  /// aktiv zählen).</summary>
  TAtlasTimeInput = (Same, Elsewhere, Ide);
  /// <summary>Nach dem Beenden: nichts (nicht erfasst oder ohne Angebot), schon im Beenden-Dialog gebucht (Merker
  /// löschen), Buchen anbieten.</summary>
  TAtlasTimeEndStep = (Skip, BookedOnEnd, Offer);
{$SCOPEDENUMS OFF}

  TAtlasTimePlan = class
  public const
    /// <summary>Alle so viele Takte in die Datei (eine Minute bei 5 s).</summary>
    cSaveTicks = 12;
    /// <summary>Weniger Zeit bietet Atlas nicht zum Buchen an.</summary>
    cMinOfferSeconds = 60;
  public
    /// <summary>AHasInput: Zeitpunkt der letzten Eingabe bekannt (AInput); ALast: zuletzt gesehener Wert;
    /// AIdeActive: die IDE ist vorn.</summary>
    class function InputOf(AHasInput: Boolean; AInput, ALast: Cardinal; AIdeActive: Boolean): TAtlasTimeInput;
      static;
    /// <summary>Zeitpunkt einer Eingabe vor AAgeMs Millisekunden.</summary>
    class function InputAt(ANow: TDateTime; AAgeMs: Cardinal): TDateTime; static;
    /// <summary>Beim Takt ATicks (ab 1) in die Datei schreiben?</summary>
    class function SavesOnTick(ATicks: Integer): Boolean; static;
    /// <summary>Summe von AIssue: geschrieben (ASaved), ungeschrieben in der Uhr (AUnsaved) und Spannen von AIssue in
    /// APending.</summary>
    class function Total(ASaved, AUnsaved: Int64; const APending: TArray<TAtlasTimeSpan>;
      const AIssue: TAtlasTimeIssue): Int64; static;
    /// <summary>Wechsel von AOld auf ANew: AOld zum Buchen anbieten (nur zwischen zwei Issues).</summary>
    class function OffersOnSwitch(const AOld, ANew: TAtlasTimeIssue): Boolean; static;
    /// <summary>Genug Zeit, um das Buchen anzubieten?</summary>
    class function Offers(ATotal: Int64): Boolean; static;
    /// <summary>Beschreibung aus den Commits holen (Ordner und Zweig bekannt)?</summary>
    class function ReadsCommits(const AFolder, ABranch: string): Boolean; static;
    /// <summary>Nach dem Beenden von AKey: ABookedOnEnd ist die Kennung, deren Zeit der Beenden-Dialog gebucht hat;
    /// AOffer: Buchen anbieten (nicht bei „nicht geplant“, „Duplikat“).</summary>
    class function EndStep(const AKey, ABookedOnEnd: string; AOffer: Boolean): TAtlasTimeEndStep; static;
    /// <summary>Ist AKey das aktuelle Issue ACurrent?</summary>
    class function IsCurrent(const ACurrent: TAtlasTimeIssue; const AKey: string): Boolean; static;
    /// <summary>Von Hand eingegebene Dauer in Minuten; „0“ und „0:00“ sind erlaubt (wie Zurücksetzen); False bei
    /// unlesbarer Eingabe.</summary>
    class function CorrectedMinutes(const AText: string; out AMinutes: Integer): Boolean; static;
    /// <summary>GitHub: Kommentar aus Aufwandszeile AHeader und Beschreibung AText darunter.</summary>
    class function BookComment(const AHeader, AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasTimePlan.InputOf(AHasInput: Boolean; AInput, ALast: Cardinal;
  AIdeActive: Boolean): TAtlasTimeInput;
begin
  if not AHasInput or (AInput = ALast) then
  begin
    Result := TAtlasTimeInput.Same;
  end
  else if not AIdeActive then
  begin
    Result := TAtlasTimeInput.Elsewhere;
  end
  else
  begin
    Result := TAtlasTimeInput.Ide;
  end;
end;

class function TAtlasTimePlan.InputAt(ANow: TDateTime; AAgeMs: Cardinal): TDateTime;
begin
  Result := ANow - AAgeMs / MSecsPerDay;
end;

class function TAtlasTimePlan.SavesOnTick(ATicks: Integer): Boolean;
begin
  Result := ATicks mod cSaveTicks = 0;
end;

class function TAtlasTimePlan.Total(ASaved, AUnsaved: Int64; const APending: TArray<TAtlasTimeSpan>;
  const AIssue: TAtlasTimeIssue): Int64;
var
  mSpan: TAtlasTimeSpan;
begin
  Result := ASaved + AUnsaved;
  for mSpan in APending do
  begin
    if mSpan.Issue.Same(AIssue) then
    begin
      Inc(Result, mSpan.Seconds);
    end;
  end;
end;

class function TAtlasTimePlan.OffersOnSwitch(const AOld, ANew: TAtlasTimeIssue): Boolean;
begin
  Result := not AOld.IsEmpty and not ANew.IsEmpty and not AOld.Same(ANew);
end;

class function TAtlasTimePlan.Offers(ATotal: Int64): Boolean;
begin
  Result := ATotal >= cMinOfferSeconds;
end;

class function TAtlasTimePlan.ReadsCommits(const AFolder, ABranch: string): Boolean;
begin
  Result := (AFolder <> '') and (ABranch <> '');
end;

class function TAtlasTimePlan.EndStep(const AKey, ABookedOnEnd: string; AOffer: Boolean): TAtlasTimeEndStep;
begin
  if (ABookedOnEnd <> '') and SameText(ABookedOnEnd, AKey) then
  begin
    Result := TAtlasTimeEndStep.BookedOnEnd;
  end
  else if AOffer then
  begin
    Result := TAtlasTimeEndStep.Offer;
  end
  else
  begin
    Result := TAtlasTimeEndStep.Skip;
  end;
end;

class function TAtlasTimePlan.IsCurrent(const ACurrent: TAtlasTimeIssue; const AKey: string): Boolean;
begin
  Result := not ACurrent.IsEmpty and SameText(ACurrent.Key, AKey);
end;

class function TAtlasTimePlan.CorrectedMinutes(const AText: string; out AMinutes: Integer): Boolean;
begin
  AMinutes := 0;
  Result := (Trim(AText) = '0') or (Trim(AText) = '0:00');
  if not Result then
  begin
    Result := TAtlasTimeRounding.ParseDuration(AText, AMinutes);
  end;
end;

class function TAtlasTimePlan.BookComment(const AHeader, AText: string): string;
begin
  Result := AHeader;
  if AText <> '' then
  begin
    Result := Result + #10#10 + AText;
  end;
end;

end.
