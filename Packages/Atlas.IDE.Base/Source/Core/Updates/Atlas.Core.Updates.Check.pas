unit Atlas.Core.Updates.Check;

// Prüfung auf neue Versionen (#495), ohne Netzwerk und ohne IDE:
// - Nur mit updates.check (Vorgabe aus, Zustimmung beim ersten Start) und
//   höchstens einmal täglich; auch eine gescheiterte Abfrage zählt.
// - Abgefragt wird die Versionsdatei des Kanals (updates.channel, #1519:
//   atlas-version.json bzw. atlas-version-beta.json, {"version": "1.2.0",
//   "changes": "https://…", …}); übertragen werden nur Atlas-Version und
//   IDE-Version als Parameter der Adresse, keine Projektdaten.
// - Versionen nach SemVer 2.0 (TUpdateVersions, dieselben Regeln wie
//   AtlasUpdate.exe). Neuer ist eine Version nur, wenn sie größer ist als
//   die installierte.
// - Der Zustand (gefragt, letzte Prüfung, zuletzt gefundene neuere Version)
//   liegt in einer eigenen Datei, nicht in den Einstellungen, damit die
//   tägliche Prüfung keine Einstellungsstände (#722) erzeugt. Die gefundene
//   Version hält die Zeile „Version“ des Statusfelds und der Zustandskachel
//   (#754) bis zur nächsten Prüfung bzw. bis sie installiert ist.
// - Eine gescheiterte Abfrage merkt sich ihre Fehlerart (lastError), bis eine
//   Abfrage gelingt. So zeigt die Zeile „Version“ „Prüfung fehlgeschlagen“
//   statt „aktuell“: Ohne Antwort ist unbekannt, ob es eine neuere Version gibt.
//   Nach einem Fehlschlag (etwa HTTP 504 oder eine Zeitüberschreitung, oft nur
//   vorübergehend) ist die nächste Abfrage schon nach einer Stunde fällig statt
//   nach einem Tag, also in der Regel beim nächsten Start der IDE.
// Heruntergeladen und installiert wird hier nichts; das macht AtlasUpdate.exe
// (#1519, Atlas.Core.Updates.Install).

interface

uses
  System.SysUtils,
  Atlas.Text.Updates,
  Atlas.Core.Updates.Contract;

type
  TAtlasRelease = record
    Version: string;
    /// <summary>https-Adresse der Änderungen dieser Version.</summary>
    ChangesUrl: string;
  end;

  TAtlasUpdateState = record
    /// <summary>Beim ersten Start gefragt (Ja oder Nein).</summary>
    Asked: Boolean;
    /// <summary>Letzte Abfrage (Ortszeit); 0 = nie.</summary>
    LastCheck: TDateTime;
    /// <summary>Zuletzt gefundene neuere Version und Adresse ihrer Änderungen (#754); '' = keine.</summary>
    Available: string;
    ChangesUrl: string;
    /// <summary>Fehlerart der letzten Abfrage, z. B. „HTTP 407“; '' = sie ist gelungen oder es gab noch keine.
    /// </summary>
    LastError: string;
    function ToJson: string;
    class function FromJson(const AJson: string): TAtlasUpdateState; static;
  end;

{$SCOPEDENUMS ON}
  TAtlasUpdateOutcome = (Disabled, NotDue, Failed, Current, NewVersion);
{$SCOPEDENUMS OFF}

  /// <summary>Was eine Prüfung abfragt (#1519): Versionsdatei des Kanals, installierte Atlas- und IDE-Version.
  /// </summary>
  TAtlasUpdateQuery = record
    Url: string;
    Installed: string;
    IdeVersion: string;
  end;

  TAtlasUpdateResult = record
    Outcome: TAtlasUpdateOutcome;
    Release: TAtlasRelease;
    /// <summary>Bei Failed: warum, ohne Adresse.</summary>
    Error: string;
  end;

  TAtlasUpdates = class
  public const
    cVersionUrl = TUpdateChannels.cStableUrl;
    cReleasesUrl = TUpdateChannels.cReleasesUrl;
    cTimeoutMs = 10000;
    cMaxErrorLength = 80;
    /// <summary>Nach einer gescheiterten Abfrage so viele Stunden bis zur nächsten.</summary>
    cRetryHours = 1;
  public
    /// <summary>SemVer-Vergleich: negativ, 0 oder positiv; ungültige Versionen sind kleiner als gültige.</summary>
    class function Compare(const A, B: string): Integer; static;
    class function IsValidVersion(const AVersion: string): Boolean; static;
    /// <summary>Versionsdatei lesen; False ohne gültige Version. Fehlt "changes" oder ist es keine
    /// https-Adresse, gilt die Release-Seite der Version.</summary>
    class function TryParse(const AJson: string; out ARelease: TAtlasRelease): Boolean; static;
    /// <summary>Fällig, wenn noch nie, seit mindestens einem Tag nicht geprüft oder die Uhr
    /// zurückgestellt wurde.</summary>
    class function IsDue(ALastCheck, ANow: TDateTime): Boolean; static;
    /// <summary>Wie IsDue, nach einer gescheiterten Abfrage (LastError) aber schon nach cRetryHours.</summary>
    class function IsStateDue(const AState: TAtlasUpdateState; ANow: TDateTime): Boolean; static;
    /// <summary>Adresse mit genau zwei Parametern: atlas und ide.</summary>
    class function RequestUrl(const ABase, AAtlasVersion, AIdeVersion: string): string; static;
    /// <summary>Ergebnis einer Prüfung im Zustand merken (#754): neue Version setzt Available und ChangesUrl,
    /// „aktuell“ löscht sie; beide löschen LastError. Ein Fehlschlag setzt nur LastError (eine gemerkte Version
    /// bleibt), keine Abfrage ändert nichts.</summary>
    class procedure Remember(var AState: TAtlasUpdateState; const AResult: TAtlasUpdateResult); static;
    /// <summary>Gemerkte Version, die neuer ist als AInstalled; False ohne (dann ist ARelease leer). Nach der
    /// Installation des Updates gilt sie nicht mehr.</summary>
    class function Pending(const AState: TAtlasUpdateState; const AInstalled: string;
      out ARelease: TAtlasRelease): Boolean; static;
    /// <summary>Fehlerart für Zustand und Anzeige: eine Zeile ohne Steuerzeichen, höchstens cMaxErrorLength
    /// Zeichen; leer wird „?“.</summary>
    class function ErrorText(const AError: string): string; static;
    /// <summary>Eine Prüfung der Versionsdatei unter AQuery.Url (Kanal, #1519); setzt AState.LastCheck, wenn
    /// abgefragt wurde.</summary>
    class function Run(const ASource: IAtlasVersionSource; const AQuery: TAtlasUpdateQuery;
      var AState: TAtlasUpdateState; AEnabled: Boolean; ANow: TDateTime): TAtlasUpdateResult; static;
    /// <summary>%LOCALAPPDATA%\Atlas\updates.json.</summary>
    class function StateFile: string; static;
    /// <summary>Compiler-Version der IDE, für die das Plugin gebaut ist, z. B. „37.0“ (Delphi 13).</summary>
    class function IdeVersion: string; static;
  end;

implementation

uses
  System.JSON,
  System.DateUtils,
  System.NetEncoding,
  System.IOUtils;

{ TAtlasUpdateState }

function TAtlasUpdateState.ToJson: string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('asked', TJSONBool.Create(Asked));
    if LastCheck > 0 then
    begin
      mRoot.AddPair('lastCheck', TJSONString.Create(DateToISO8601(LastCheck, False)));
    end;
    if Available <> '' then
    begin
      mRoot.AddPair('available', TJSONString.Create(Available));
      mRoot.AddPair('changes', TJSONString.Create(ChangesUrl));
    end;
    if LastError <> '' then
    begin
      mRoot.AddPair('lastError', TJSONString.Create(LastError));
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasUpdateState.FromJson(const AJson: string): TAtlasUpdateState;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mText: string;
  mFound: Boolean;
begin
  Result := Default(TAtlasUpdateState);
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    mRoot.TryGetValue<Boolean>('asked', Result.Asked);
    // Ergebnis der Abfragen erst in eine Variable: so lesen es auch andere Compiler (Tests unter FPC).
    mFound := mRoot.TryGetValue<string>('lastCheck', mText);
    if mFound and not TryISO8601ToDate(mText, Result.LastCheck, False) then
    begin
      Result.LastCheck := 0;
    end;
    // Nur eine gültige Version (#754); ohne https-Adresse gilt die Release-Seite der Version.
    mFound := mRoot.TryGetValue<string>('available', mText);
    if mFound and TAtlasUpdates.IsValidVersion(mText) then
    begin
      Result.Available := mText;
      mFound := mRoot.TryGetValue<string>('changes', Result.ChangesUrl);
      if not mFound or not Result.ChangesUrl.StartsWith('https://', True) or
        (Result.ChangesUrl.IndexOfAny([' ', #9, #10, #13]) >= 0) then
      begin
        Result.ChangesUrl := TAtlasUpdates.cReleasesUrl + '/tag/v' + mText;
      end;
    end;
    mFound := mRoot.TryGetValue<string>('lastError', mText);
    if mFound then
    begin
      Result.LastError := TAtlasUpdates.ErrorText(mText);
    end;
  finally
    mValue.Free;
  end;
end;

{ TAtlasUpdates }

class function TAtlasUpdates.IsValidVersion(const AVersion: string): Boolean;
begin
  Result := TUpdateVersions.IsValidVersion(AVersion);
end;

class function TAtlasUpdates.Compare(const A, B: string): Integer;
begin
  Result := TUpdateVersions.Compare(A, B);
end;

class function TAtlasUpdates.TryParse(const AJson: string; out ARelease: TAtlasRelease): Boolean;
var
  mValue: TJSONValue;
  mFound: Boolean;
begin
  ARelease := Default(TAtlasRelease);
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    // Ergebnis der Abfragen erst in eine Variable: so lesen es auch andere Compiler (Tests unter FPC).
    Result := mValue is TJSONObject;
    if Result then
    begin
      mFound := TJSONObject(mValue).TryGetValue<string>('version', ARelease.Version);
      Result := mFound and IsValidVersion(ARelease.Version);
    end;
    if not Result then
    begin
      ARelease := Default(TAtlasRelease);
      Exit;
    end;
    // Nur https-Adressen landen in der Meldungsansicht.
    mFound := TJSONObject(mValue).TryGetValue<string>('changes', ARelease.ChangesUrl);
    if not mFound or
      not ARelease.ChangesUrl.StartsWith('https://', True) or (ARelease.ChangesUrl.IndexOfAny([' ', #9, #10, #13]) >= 0)
    then
    begin
      ARelease.ChangesUrl := cReleasesUrl + '/tag/v' + ARelease.Version;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasUpdates.IsDue(ALastCheck, ANow: TDateTime): Boolean;
begin
  Result := (ALastCheck <= 0) or (ANow - ALastCheck >= 1) or (ALastCheck > ANow);
end;

class function TAtlasUpdates.IsStateDue(const AState: TAtlasUpdateState; ANow: TDateTime): Boolean;
begin
  Result := IsDue(AState.LastCheck, ANow) or
    ((AState.LastError <> '') and (ANow >= IncHour(AState.LastCheck, cRetryHours)));
end;

class function TAtlasUpdates.RequestUrl(const ABase, AAtlasVersion, AIdeVersion: string): string;
begin
  Result := ABase + '?atlas=' + TNetEncoding.URL.Encode(AAtlasVersion) + '&ide=' +
    TNetEncoding.URL.Encode(AIdeVersion);
end;

class function TAtlasUpdates.ErrorText(const AError: string): string;
var
  mIndex: Integer;
begin
  // Steht in einer Zeile des Statusfelds und in der Zustandsdatei; Adressen enthält AError nicht.
  Result := Copy(Trim(AError), 1, cMaxErrorLength);
  for mIndex := 1 to Length(Result) do
  begin
    if Ord(Result[mIndex]) < 32 then
    begin
      Result[mIndex] := ' ';
    end;
  end;
  if Result = '' then
  begin
    Result := '?';
  end;
end;

class procedure TAtlasUpdates.Remember(var AState: TAtlasUpdateState; const AResult: TAtlasUpdateResult);
begin
  case AResult.Outcome of
    TAtlasUpdateOutcome.NewVersion:
      begin
        AState.Available := AResult.Release.Version;
        AState.ChangesUrl := AResult.Release.ChangesUrl;
        AState.LastError := '';
      end;
    TAtlasUpdateOutcome.Current:
      begin
        AState.Available := '';
        AState.ChangesUrl := '';
        AState.LastError := '';
      end;
    TAtlasUpdateOutcome.Failed:
      AState.LastError := ErrorText(AResult.Error);
    TAtlasUpdateOutcome.Disabled: ;
    TAtlasUpdateOutcome.NotDue: ;
  end;
end;

class function TAtlasUpdates.Pending(const AState: TAtlasUpdateState; const AInstalled: string;
  out ARelease: TAtlasRelease): Boolean;
begin
  ARelease := Default(TAtlasRelease);
  Result := (AState.Available <> '') and (Compare(AState.Available, AInstalled) > 0);
  if not Result then
  begin
    Exit;
  end;
  ARelease.Version := AState.Available;
  ARelease.ChangesUrl := AState.ChangesUrl;
  if not ARelease.ChangesUrl.StartsWith('https://', True) or (ARelease.ChangesUrl.IndexOfAny([' ', #9, #10, #13]) >= 0)
  then
  begin
    ARelease.ChangesUrl := cReleasesUrl + '/tag/v' + AState.Available;
  end;
end;

class function TAtlasUpdates.Run(const ASource: IAtlasVersionSource; const AQuery: TAtlasUpdateQuery;
  var AState: TAtlasUpdateState; AEnabled: Boolean; ANow: TDateTime): TAtlasUpdateResult;
var
  mText: string;
begin
  Result := Default(TAtlasUpdateResult);
  if not AEnabled then
  begin
    Result.Outcome := TAtlasUpdateOutcome.Disabled;
    Exit;
  end;
  if not IsStateDue(AState, ANow) then
  begin
    Result.Outcome := TAtlasUpdateOutcome.NotDue;
    Exit;
  end;
  // Auch ein Fehlschlag zählt: höchstens eine Abfrage am Tag.
  AState.LastCheck := ANow;
  if not ASource.Fetch(RequestUrl(AQuery.Url, AQuery.Installed, AQuery.IdeVersion), cTimeoutMs, mText,
    Result.Error) then
  begin
    Result.Outcome := TAtlasUpdateOutcome.Failed;
    Exit;
  end;
  if not TryParse(mText, Result.Release) then
  begin
    Result.Outcome := TAtlasUpdateOutcome.Failed;
    Result.Error := 'Versionsdatei ungültig';
    Exit;
  end;
  if Compare(Result.Release.Version, AQuery.Installed) > 0 then
  begin
    Result.Outcome := TAtlasUpdateOutcome.NewVersion;
  end
  else
  begin
    Result.Outcome := TAtlasUpdateOutcome.Current;
  end;
end;

class function TAtlasUpdates.IdeVersion: string;
begin
  Result := FormatFloat('0.0', CompilerVersion, TFormatSettings.Invariant);
end;

class function TAtlasUpdates.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'updates.json');
end;

end.
