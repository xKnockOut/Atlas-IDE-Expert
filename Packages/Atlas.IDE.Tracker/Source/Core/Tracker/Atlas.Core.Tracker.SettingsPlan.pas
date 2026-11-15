unit Atlas.Core.Tracker.SettingsPlan;

// Entscheidungen des Abschnitts „Issue-Tracker“ im Optionsdialog ohne IDE prüfbar (#1967); die IDE
// (Atlas.IDE.Tracker.Settings) ruft nur noch Hintergrund, Anmeldespeicher, .atlas und den Abschnitt:
// - Schlüssel und Stand einer geprüften Verbindung (ohne Token „fehlt“, geprüft gilt bis zum Entladen);
// - Ziel für „Werte vom Tracker laden“ (mit dem Projekt aus der .atlas bei gleichem Server) und Name der Verbindung
//   aus der .atlas;
// - das anonyme Protokoll (Anbieter, Zustand und Anzahl; nie Adresse, Abfrage oder Token).

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.QueryTest;

type
  TAtlasTrackerSettingsPlan = class
  public
    /// <summary>Schlüssel des Prüfergebnisses einer Verbindung zu ATarget (Anmeldeziel klein).</summary>
    class function StateKey(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Stand für die Liste: ohne Token (AHasToken False) „fehlt“, sonst das gemerkte Ergebnis (AKnown,
    /// AKnownStatus) oder „gespeichert“.</summary>
    class function StateOf(AHasToken, AKnown: Boolean; const AKnownStatus: TAtlasTrackerTokenStatus):
      TAtlasTrackerTokenStatus; static;
    /// <summary>Ziel für „Werte vom Tracker laden“: ATeam (Tracker der .atlas, ATeamConfigured), wenn er derselbe
    /// Anbieter und Server wie ATarget ist (GitHub braucht owner/repo); sonst ATarget.</summary>
    class function ValuesTarget(const ATarget: TAtlasTrackerTarget; ATeamConfigured: Boolean;
      const ATeam: TAtlasTrackerTarget): TAtlasTrackerTarget; static;
    /// <summary>Name der Verbindung aus der .atlas: Dateiname des Projekts AProject ohne Endung.</summary>
    class function TeamName(const AProject: string): string; static;
    class function TokenStateKey(AState: TAtlasTrackerTokenState): string; static;
    class function OutcomeKey(AOutcome: TAtlasTrackerQueryOutcome): string; static;
    /// <summary>Protokollzeilen: Verbindung geprüft, Werte geladen, Abfrage getestet.</summary>
    class function CheckedLog(AState: TAtlasTrackerTokenState): string; static;
    class function ValuesLog(AError: TAtlasCiFetchError; AStates: Integer): string; static;
    class function QueryLog(const AProvider: string; AOutcome: TAtlasTrackerQueryOutcome): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  // Protokoll: anonym, nur Anbieter, Zustand und Anzahl.
  cLogValuesLoaded = 'Issue-Tracker: Werte geladen (%s, %d Zustände)'; // german-ok: Protokollzeile, unverändert
  cLogChecked = 'Issue-Tracker: Verbindung geprüft (%s)'; // german-ok: Protokollzeile, unverändert
  cLogQueryTested = 'Issue-Tracker: Abfrage getestet (%s, %s)'; // german-ok: Protokollzeile, unverändert
  cTrackerStateKeys: array[TAtlasTrackerTokenState] of string = ('missing', 'saved', 'verified', 'rejected',
    'unreachable', 'unexpected');
  cOutcomeKeys: array[TAtlasTrackerQueryOutcome] of string = ('found', 'empty', 'noToken', 'notConfigured',
    'rejected', 'projectUnknown', 'queryRejected', 'unreadable', 'serverError', 'unreachable');

class function TAtlasTrackerSettingsPlan.StateKey(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := LowerCase(ATarget.CredentialTarget);
end;

class function TAtlasTrackerSettingsPlan.StateOf(AHasToken, AKnown: Boolean;
  const AKnownStatus: TAtlasTrackerTokenStatus): TAtlasTrackerTokenStatus;
begin
  if not AHasToken then
  begin
    Result := TAtlasTrackerTokenStatus.Stored(False);
  end
  else if AKnown then
  begin
    Result := AKnownStatus;
  end
  else
  begin
    Result := TAtlasTrackerTokenStatus.Stored(True);
  end;
end;

class function TAtlasTrackerSettingsPlan.ValuesTarget(const ATarget: TAtlasTrackerTarget; ATeamConfigured: Boolean;
  const ATeam: TAtlasTrackerTarget): TAtlasTrackerTarget;
begin
  Result := ATarget;
  if ATeamConfigured and SameText(ATeam.Provider, ATarget.Provider) and SameText(ATeam.Server, ATarget.Server) then
  begin
    Result := ATeam;
  end;
end;

class function TAtlasTrackerSettingsPlan.TeamName(const AProject: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AProject), '');
end;

class function TAtlasTrackerSettingsPlan.TokenStateKey(AState: TAtlasTrackerTokenState): string;
begin
  Result := cTrackerStateKeys[AState];
end;

class function TAtlasTrackerSettingsPlan.OutcomeKey(AOutcome: TAtlasTrackerQueryOutcome): string;
begin
  Result := cOutcomeKeys[AOutcome];
end;

class function TAtlasTrackerSettingsPlan.CheckedLog(AState: TAtlasTrackerTokenState): string;
begin
  Result := Format(cLogChecked, [TokenStateKey(AState)], TFormatSettings.Invariant);
end;

class function TAtlasTrackerSettingsPlan.ValuesLog(AError: TAtlasCiFetchError; AStates: Integer): string;
begin
  Result := Format(cLogValuesLoaded, [TAtlasCiBuild.ErrorKey(AError), AStates], TFormatSettings.Invariant);
end;

class function TAtlasTrackerSettingsPlan.QueryLog(const AProvider: string; AOutcome: TAtlasTrackerQueryOutcome):
  string;
begin
  Result := Format(cLogQueryTested, [AProvider, OutcomeKey(AOutcome)], TFormatSettings.Invariant);
end;

end.
