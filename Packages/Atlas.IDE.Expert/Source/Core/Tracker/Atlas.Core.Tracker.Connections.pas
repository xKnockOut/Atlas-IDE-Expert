unit Atlas.Core.Tracker.Connections;

// Tracker-Verbindungen (#1260), ohne VCL und Open Tools API.
// - TAtlasTrackerConnection: Name, Anbieter und Adresse eines Trackers.
//   Persönliche Verbindungen stehen in %APPDATA%\Atlas\settings.json unter
//   issues.connections (TAtlasPluginSettings.IssuesConnections, JSON-Text);
//   eine Verbindung aus dem Abschnitt tracker der .atlas (#486) kommt
//   schreibgeschützt dazu („aus .atlas“).
// - TAtlasTrackerConnections: Liste lesen und schreiben (Read, ToJson),
//   Adresse prüfen (nur https, ohne Benutzer, wie TAtlasTrackerTarget),
//   eindeutige Namen.
// - Token: liegt nur im Anmeldespeicher von Windows unter
//   TAtlasTrackerTarget.CredentialTarget ("Atlas:tracker:<Server>"), nie in
//   der Liste. Zustand je Server: fehlt, gespeichert, geprüft, abgelehnt,
//   nicht erreichbar oder unerwartete Antwort.
// - Check: „Verbindung prüfen“ fragt den Tracker einmal (ProbeUrl des
//   Anbieters, Zeitgrenze CheckTimeoutMs) und ordnet die Antwort einem
//   Zustand zu. Ohne Klick kein Netz; das Netz kommt über IAtlasCiTransport.
//   Bei geprüftem Token erkennt sie auch die Sprache der Oberfläche
//   (YouTrack, #1263); die Seite merkt sie an der Verbindung ("language"),
//   damit die Vorgabe „Mir zugewiesen“ in dieser Sprache gilt.
// - IAtlasTrackerAccess: Anbieter, Token und Transport für Optionsseite und
//   „Meine Issues“; setzt die Komposition um (Anmeldespeicher, Dialog).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Herkunft einer Verbindung.</summary>
  TAtlasTrackerConnectionSource = (Personal, TeamFile);
  /// <summary>Ergebnis der Prüfung einer Adresse.</summary>
  TAtlasTrackerUrlCheck = (Valid, Empty, NotHttps, WithUser, Invalid);
  /// <summary>Zustand des Tokens einer Verbindung.</summary>
  TAtlasTrackerTokenState = (Missing, Saved, Verified, Rejected, Unreachable, Unexpected);
{$SCOPEDENUMS OFF}

  TAtlasTrackerConnection = record
    /// <summary>Eindeutiger, frei wählbarer Name, z. B. "Firma".</summary>
    Name: string;
    /// <summary>Anbieter klein: "youtrack", "github".</summary>
    Provider: string;
    /// <summary>Adresse ohne „/“ am Ende, z. B. "https://youtrack.firma.local".</summary>
    Url: string;
    /// <summary>Sprache der Oberfläche ("de", "en"), erkannt beim Prüfen (#1263); '' = unbekannt.</summary>
    Language: string;
    Source: TAtlasTrackerConnectionSource;
    class function Create(const AName, AProvider, AUrl: string): TAtlasTrackerConnection; static;
    /// <summary>Verbindung aus dem Abschnitt tracker der .atlas (schreibgeschützt); Name = AName.</summary>
    class function FromTeamFile(const AName: string; const ATarget: TAtlasTrackerTarget): TAtlasTrackerConnection;
      static;
    /// <summary>Ziel ohne Projekt und Abfrage: genug für Server, Token und Prüfung.</summary>
    function Target: TAtlasTrackerTarget;
    function ReadOnly: Boolean;
  end;

  /// <summary>Zustand des Tokens zu einem Server.</summary>
  TAtlasTrackerTokenStatus = record
    State: TAtlasTrackerTokenState;
    /// <summary>Zeit der Prüfung (lokal); 0 = nie geprüft.</summary>
    CheckedAt: TDateTime;
    /// <summary>HTTP-Status der Prüfung; 0 ohne Antwort.</summary>
    HttpStatus: Integer;
    /// <summary>Bei der Prüfung erkannte Sprache der Oberfläche (#1263); '' unbekannt.</summary>
    Language: string;
    class function Create(AState: TAtlasTrackerTokenState; ACheckedAt: TDateTime;
      AHttpStatus: Integer): TAtlasTrackerTokenStatus; static;
    /// <summary>Ohne Prüfung: gespeichert oder fehlt.</summary>
    class function Stored(AHasToken: Boolean): TAtlasTrackerTokenStatus; static;
  end;

  /// <summary>Anbieter, Token und Transport; setzt die Komposition um. Token nie im Protokoll.</summary>
  IAtlasTrackerAccess = interface
    ['{4C7E2A91-8B3D-4F06-9E15-A2D6C8B04F73}']
    /// <summary>Alle Anbieter in fester Reihenfolge (Auswahl der Optionsseite).</summary>
    function Providers: TArray<IAtlasTrackerProvider>;
    /// <summary>Anbieter zum Namen; nil, wenn es ihn nicht gibt.</summary>
    function Provider(const AName: string): IAtlasTrackerProvider;
    /// <summary>Im Anmeldespeicher steht ein Token für den Server von ATarget.</summary>
    function HasToken(const ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Token abfragen (verdeckter Dialog) und speichern, leer entfernt es; nur über https. True, wenn
    /// sich etwas geändert hat.</summary>
    function EnterToken(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Token des Servers entfernen; True auch, wenn es keins gab.</summary>
    function RemoveToken(const ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Transport mit dem Token, das nur an AProvider.ApiServer geht; nil ohne Token. Im Hintergrund
    /// erlaubt.</summary>
    function Transport(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  end;

  TAtlasTrackerConnections = class
  public const
    /// <summary>Pfad in settings.json.</summary>
    Path = 'issues.connections';
    /// <summary>Zeitgrenze von „Verbindung prüfen“.</summary>
    CheckTimeoutMs = 5000;
  public
    /// <summary>Persönliche Verbindungen aus dem JSON-Text der Liste; Einträge ohne Name, Anbieter oder Adresse und
    /// doppelte Namen entfallen (der Server meldet sie in settings.json).</summary>
    class function Read(const AJson: string): TArray<TAtlasTrackerConnection>; static;
    /// <summary>Persönliche Verbindungen als JSON-Liste; Verbindungen aus der .atlas entfallen.</summary>
    class function ToJson(const AItems: TArray<TAtlasTrackerConnection>): string; static;
    class function CheckUrl(const AUrl: string): TAtlasTrackerUrlCheck; static;
    /// <summary>Index des Namens (ohne Groß-/Kleinschreibung, ohne Leerraum außen); -1 ohne.</summary>
    class function IndexOfName(const AItems: TArray<TAtlasTrackerConnection>; const AName: string): Integer; static;
    /// <summary>Name leer oder schon bei einer anderen Verbindung als AExcept vergeben.</summary>
    class function NameTaken(const AItems: TArray<TAtlasTrackerConnection>; const AName: string;
      AExcept: Integer): Boolean; static;
    /// <summary>Erster freier Name: ABase, sonst "ABase 2", "ABase 3" …</summary>
    class function FreeName(const AItems: TArray<TAtlasTrackerConnection>; const ABase: string): string; static;
    /// <summary>Zustand zur Antwort der Prüfung: AAnswered = eine Antwort kam (AStatus, AText).
    /// 200 mit "login" = geprüft, 401/403 = abgelehnt, ohne Antwort = nicht erreichbar, sonst unerwartet.</summary>
    class function StateOf(AAnswered: Boolean; AStatus: Integer; const AText: string): TAtlasTrackerTokenState;
      static;
    /// <summary>Erkannte Sprache (#1263) für ATarget: die erste Verbindung mit gleichem Anbieter und Server, die
    /// eine nennt; so gilt sie auch für den Tracker aus der .atlas. '' ohne.</summary>
    class function LanguageOf(const AItems: TArray<TAtlasTrackerConnection>;
      const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Verbindung prüfen: ohne Transport (kein Token) „fehlt“, sonst ein GET auf ProbeUrl. Im
    /// Hintergrund.</summary>
    class function Check(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const ATransport: IAtlasCiTransport; ANow: TDateTime): TAtlasTrackerTokenStatus; static;
  end;

implementation

uses
  System.JSON,
  System.Diagnostics,
  Atlas.Core.Tracker.Templates,
  Atlas.Core.Tracker.QueryTest;

{ TAtlasTrackerConnection }

class function TAtlasTrackerConnection.Create(const AName, AProvider, AUrl: string): TAtlasTrackerConnection;
begin
  Result.Name := Trim(AName);
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while (Result.Url <> '') and (Result.Url[Length(Result.Url)] = '/') do
    Delete(Result.Url, Length(Result.Url), 1);
  Result.Language := '';
  Result.Source := TAtlasTrackerConnectionSource.Personal;
end;

class function TAtlasTrackerConnection.FromTeamFile(const AName: string;
  const ATarget: TAtlasTrackerTarget): TAtlasTrackerConnection;
begin
  Result := Create(AName, ATarget.Provider, ATarget.Url);
  Result.Source := TAtlasTrackerConnectionSource.TeamFile;
end;

function TAtlasTrackerConnection.Target: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create(Provider, Url, '', '');
  Result.Language := Language;
end;

function TAtlasTrackerConnection.ReadOnly: Boolean;
begin
  Result := Source = TAtlasTrackerConnectionSource.TeamFile;
end;

{ TAtlasTrackerTokenStatus }

class function TAtlasTrackerTokenStatus.Create(AState: TAtlasTrackerTokenState; ACheckedAt: TDateTime;
  AHttpStatus: Integer): TAtlasTrackerTokenStatus;
begin
  Result.State := AState;
  Result.CheckedAt := ACheckedAt;
  Result.HttpStatus := AHttpStatus;
  Result.Language := '';
end;

class function TAtlasTrackerTokenStatus.Stored(AHasToken: Boolean): TAtlasTrackerTokenStatus;
begin
  if AHasToken then
    Result := Create(TAtlasTrackerTokenState.Saved, 0, 0)
  else
    Result := Create(TAtlasTrackerTokenState.Missing, 0, 0);
end;

{ TAtlasTrackerConnections }

function Quoted(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

class function TAtlasTrackerConnections.Read(const AJson: string): TArray<TAtlasTrackerConnection>;
var
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mConnection: TAtlasTrackerConnection;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
      Exit;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mConnection := TAtlasTrackerConnection.Create(TextOf(TJSONObject(mItem), 'name'),
        TextOf(TJSONObject(mItem), 'provider'), TextOf(TJSONObject(mItem), 'url'));
      if (mConnection.Name = '') or (mConnection.Provider = '') or (mConnection.Url = '') or
        (IndexOfName(Result, mConnection.Name) >= 0) then
        Continue;
      mConnection.Language := TAtlasTrackerTemplates.NormalLanguage(TextOf(TJSONObject(mItem), 'language'));
      Result := Result + [mConnection];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerConnections.ToJson(const AItems: TArray<TAtlasTrackerConnection>): string;
var
  mItem: TAtlasTrackerConnection;
  mParts: TArray<string>;
  mPart: string;
begin
  mParts := nil;
  for mItem in AItems do
    if not mItem.ReadOnly then
    begin
      mPart := '{"name": ' + Quoted(mItem.Name) + ', "provider": ' + Quoted(mItem.Provider) + ', "url": ' +
        Quoted(mItem.Url);
      if mItem.Language <> '' then
        mPart := mPart + ', "language": ' + Quoted(mItem.Language);
      mParts := mParts + [mPart + '}'];
    end;
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasTrackerConnections.CheckUrl(const AUrl: string): TAtlasTrackerUrlCheck;
var
  mUrl, mHost: string;
  mSlash: Integer;
begin
  mUrl := Trim(AUrl);
  if mUrl = '' then
    Exit(TAtlasTrackerUrlCheck.Empty);
  if not SameText(Copy(mUrl, 1, 8), 'https://') then
    Exit(TAtlasTrackerUrlCheck.NotHttps);
  mHost := Copy(mUrl, 9, MaxInt);
  mSlash := Pos('/', mHost);
  if mSlash > 0 then
    mHost := Copy(mHost, 1, mSlash - 1);
  // Benutzer oder Token in der Adresse („user:token@host“) nie: das Token gehört in den Anmeldespeicher.
  if Pos('@', mHost) > 0 then
    Exit(TAtlasTrackerUrlCheck.WithUser);
  if (mHost = '') or (Pos(' ', mUrl) > 0) or (TAtlasTrackerTarget.Create('', mUrl, '', '').Server = '') then
    Exit(TAtlasTrackerUrlCheck.Invalid);
  Result := TAtlasTrackerUrlCheck.Valid;
end;

class function TAtlasTrackerConnections.IndexOfName(const AItems: TArray<TAtlasTrackerConnection>;
  const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
    if SameText(AItems[mIndex].Name, Trim(AName)) then
      Exit(mIndex);
  Result := -1;
end;

class function TAtlasTrackerConnections.NameTaken(const AItems: TArray<TAtlasTrackerConnection>;
  const AName: string; AExcept: Integer): Boolean;
var
  mIndex: Integer;
begin
  if Trim(AName) = '' then
    Exit(True);
  for mIndex := 0 to High(AItems) do
    if (mIndex <> AExcept) and SameText(AItems[mIndex].Name, Trim(AName)) then
      Exit(True);
  Result := False;
end;

class function TAtlasTrackerConnections.FreeName(const AItems: TArray<TAtlasTrackerConnection>;
  const ABase: string): string;
var
  mNumber: Integer;
begin
  Result := ABase;
  mNumber := 1;
  while IndexOfName(AItems, Result) >= 0 do
  begin
    Inc(mNumber);
    Result := ABase + ' ' + IntToStr(mNumber);
  end;
end;

"class function TAtlasTrackerConnections.LanguageOf(const AItems: TArray<TAtlasTrackerConnection>;
  const ATarget: TAtlasTrackerTarget): string;
var
  mItem: TAtlasTrackerConnection;
begin
  Result := '';
  if ATarget.Server = '' then
    Exit;
  for mItem in AItems do
    if (mItem.Language <> '') and SameText(mItem.Provider, ATarget.Provider) and
      (mItem.Target.Server = ATarget.Server) then
      Exit(mItem.Language);
end;

/// <summary>Antwort ist ein JSON-Objekt mit einem nicht leeren "login" (YouTrack und GitHub).</summary>
function HasLogin(const AText: string): Boolean;
var
  mRoot: TJSONValue;
begin
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if mRoot is TJSONObject then
      Result := TextOf(TJSONObject(mRoot), 'login') <> '';
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerConnections.StateOf(AAnswered: Boolean; AStatus: Integer;
  const AText: string): TAtlasTrackerTokenState;
begin
  if not AAnswered then
    Exit(TAtlasTrackerTokenState.Unreachable);
  case AStatus of
    200:
      // Eine Anmeldeseite oder ein Proxy antwortet auch mit 200; geprüft ist nur, wer den Benutzer nennt.
      if HasLogin(AText) then
        Result := TAtlasTrackerTokenState.Verified
      else
        Result := TAtlasTrackerTokenState.Unexpected;
    401, 403:
      Result := TAtlasTrackerTokenState.Rejected;
  else
    Result := TAtlasTrackerTokenState.Unexpected;
  end;
end;

class function TAtlasTrackerConnections.Check(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ANow: TDateTime): TAtlasTrackerTokenStatus;
var
  mUrl, mText: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mAnswered: Boolean;
  mWatch: TStopwatch;
  mRest: Int64;
begin
  if ATransport = nil then
    Exit(TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Missing, ANow, 0));
  mUrl := '';
  if AProvider <> nil then
    mUrl := AProvider.ProbeUrl(ATarget);
  if mUrl = '' then
    Exit(TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Unexpected, ANow, 0));
  mWatch := TStopwatch.StartNew;
  mAnswered := ATransport.Get(mUrl, CheckTimeoutMs, mStatus, mText, mError);
  if not mAnswered then
    mStatus := 0;
  Result := TAtlasTrackerTokenStatus.Create(StateOf(mAnswered, mStatus, mText), ANow, mStatus);
  if Result.State <> TAtlasTrackerTokenState.Verified then
    Exit;
  // In der restlichen Zeit: Sprache der Oberfläche für die Vorgabe der Abfrage (#1263).
  mRest := CheckTimeoutMs - mWatch.ElapsedMilliseconds;
  if mRest > 0 then
    Result.Language := TAtlasTrackerQueryTest.DetectLanguage(AProvider, ATarget, ATransport, Integer(mRest));
end;

end.
