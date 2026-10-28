unit Atlas.Core.Tracker.QueryTest;

// „Testen“ im Dialog „Abfrage bearbeiten“ (#1263), ohne VCL und Open Tools
// API: die Abfrage samt Projekt einmal an den Tracker schicken (Zeitgrenze
// TimeoutMs) und die Antwort einer Ursache zuordnen.
// - Evaluate: 200 mit Liste = „N Issues gefunden“ mit den ersten MaxKeys
//   Kennungen bzw. leere Liste; 200 ohne Liste (HTML, z. B. Anmeldeseite bei
//   falscher Adresse) = nicht lesbar; 400/422 = Abfrage abgelehnt mit der
//   Meldung des Trackers (YouTrack "error_description", GitHub "message" bzw.
//   "errors[].message"); 401/403 = abgelehnt; 404 = Projekt unbekannt;
//   ohne Antwort = nicht erreichbar; ohne Transport = kein Token.
// - Jedes Ergebnis nennt die tatsächlich gesendete Abfrage
//   (IAtlasTrackerProvider.SentQuery), nie das Token.
// - DetectLanguage: Sprache der Oberfläche (YouTrack); erst über LocaleUrl,
//   ohne Recht darauf über eine Probe mit beiden Vorlagen „Mir zugewiesen“.
//   Bei leerer Liste und deutscher Oberfläche schlägt Run die deutsche
//   Vorlage vor. Dieselbe Erkennung nutzt „Verbindung prüfen“ (#1260) für die
//   Vorgabe einer neuen Verbindung.
// Läuft im Hintergrund; das Netz kommt über IAtlasCiTransport.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasTrackerQueryOutcome = (Found, Empty, NoToken, NotConfigured, Rejected, ProjectUnknown, QueryRejected,
    Unreadable, ServerError, Unreachable);
{$SCOPEDENUMS OFF}

  TAtlasTrackerQueryTestResult = record
    Outcome: TAtlasTrackerQueryOutcome;
    /// <summary>Gelesene Issues (höchstens TAtlasTrackerQueryTest.MaxIssues).</summary>
    Count: Integer;
    /// <summary>Es gibt mehr als Count.</summary>
    More: Boolean;
    /// <summary>Die ersten Kennungen ("ATL-12", "#753").</summary>
    Keys: TArray<string>;
    /// <summary>Meldung des Trackers bei 400/422 (einzeilig, gekürzt); '' ohne.</summary>
    TrackerMessage: string;
    /// <summary>HTTP-Status; 0 ohne Antwort.</summary>
    HttpStatus: Integer;
    ElapsedMs: Int64;
    /// <summary>Abfrage, wie sie an den Tracker ging (ohne Token).</summary>
    SentQuery: string;
    /// <summary>Erkannte Sprache der Oberfläche ("de", "en"); '' unbekannt oder nicht gefragt.</summary>
    Language: string;
    /// <summary>Vorschlag bei leerer Liste: die Vorlage „Mir zugewiesen“ in der Sprache der Oberfläche; '' ohne.
    /// </summary>
    SuggestedQuery: string;
    class function Create(AOutcome: TAtlasTrackerQueryOutcome; const ASentQuery: string): TAtlasTrackerQueryTestResult;
      static;
  end;

  TAtlasTrackerQueryTest = class
  public const
    TimeoutMs = 5000;
    MaxIssues = 50;
    MaxKeys = 3;
    MaxMessage = 300;
  public
    /// <summary>Meldung aus einer Fehlerantwort; ohne JSON der Anfang des Texts, bei HTML ''.</summary>
    class function TrackerMessage(const AText: string): string; static;
    /// <summary>Sprache aus der Antwort von localeSettings ({"locale": {"language": "de"}}); '' ohne.</summary>
    class function LanguageOfLocale(const AText: string): string; static;
    /// <summary>Antwort der Liste einer Ursache zuordnen. AAnswered: eine Antwort kam (AStatus, AText), sonst
    /// AError.</summary>
    class function Evaluate(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      AAnswered: Boolean; AStatus: Integer; const AText: string; AError: TAtlasCiFetchError):
      TAtlasTrackerQueryTestResult; static;
    /// <summary>Sprache der Oberfläche, höchstens ATimeoutMs; '' unbekannt oder ohne LocaleUrl (GitHub).</summary>
    class function DetectLanguage(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const ATransport: IAtlasCiTransport; ATimeoutMs: Integer): string; static;
    /// <summary>„Testen“: ATarget samt Abfrage und Projekt einmal abfragen; ohne ATransport „kein Token“.</summary>
    class function Run(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const ATransport: IAtlasCiTransport): TAtlasTrackerQueryTestResult; static;
  end;

implementation

uses
  System.JSON,
  System.Diagnostics,
  Atlas.Core.Tracker.Templates;

{ TAtlasTrackerQueryTestResult }

class function TAtlasTrackerQueryTestResult.Create(AOutcome: TAtlasTrackerQueryOutcome;
  const ASentQuery: string): TAtlasTrackerQueryTestResult;
begin
  Result := Default(TAtlasTrackerQueryTestResult);
  Result.Keys := nil;
  Result.Outcome := AOutcome;
  Result.SentQuery := ASentQuery;
end;

{ TAtlasTrackerQueryTest }

function OneLine(const AText: string): string;
begin
  Result := Trim(AText.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ').Replace(#9, ' '));
  while Pos('  ', Result) > 0 do
    Result := Result.Replace('  ', ' ');
  if Length(Result) > TAtlasTrackerQueryTest.MaxMessage then
    Result := Copy(Result, 1, TAtlasTrackerQueryTest.MaxMessage - 1) + '…';
end;

function TextOf(AValue: TJSONValue; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if not (AValue is TJSONObject) then
    Exit;
  mValue := TJSONObject(AValue).GetValue(AName);
  if mValue is TJSONString then
    Result := Trim(TJSONString(mValue).Value);
end;

function LooksLikeHtml(const AText: string): Boolean;
begin
  Result := Trim(AText).StartsWith('<');
end;

class function TAtlasTrackerQueryTest.TrackerMessage(const AText: string): string;
var
  mRoot, mErrors, mItem: TJSONValue;
  mParts: TArray<string>;
  mPart: string;
begin
  Result := '';
  if LooksLikeHtml(AText) then
    Exit;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
      Exit(OneLine(AText));
    // YouTrack: {"error": "bad_request", "error_description": "…"}.
    Result := TextOf(mRoot, 'error_description');
    if Result <> '' then
      Exit(OneLine(Result));
    // GitHub: {"message": "Validation Failed", "errors": [{"message": "…"}]}; die Einzelmeldungen sagen mehr.
    mParts := nil;
    mErrors := TJSONObject(mRoot).GetValue('errors');
    if mErrors is TJSONArray then
      for mItem in TJSONArray(mErrors) do
      begin
        mPart := TextOf(mItem, 'message');
        if mPart <> '' then
          mParts := mParts + [mPart];
      end;
    if Length(mParts) > 0 then
      Exit(OneLine(string.Join('; ', mParts)));
    Result := TextOf(mRoot, 'message');
    if Result = '' then
      Result := TextOf(mRoot, 'error');
    Result := OneLine(Result);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerQueryTest.LanguageOfLocale(const AText: string): string;
var
  mRoot, mLocale: TJSONValue;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
      Exit;
    mLocale := TJSONObject(mRoot).GetValue('locale');
    Result := TAtlasTrackerTemplates.NormalLanguage(TextOf(mLocale, 'language'));
    if Result = '' then
      Result := TAtlasTrackerTemplates.NormalLanguage(TextOf(mLocale, 'locale'));
    if Result = '' then
      Result := TAtlasTrackerTemplates.NormalLanguage(TextOf(mLocale, 'id'));
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerQueryTest.Evaluate(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; AAnswered: Boolean; AStatus: Integer; const AText: string;
  AError: TAtlasCiFetchError): TAtlasTrackerQueryTestResult;
var
  mIssues: TArray<TAtlasTrackerIssue>;
  mIndex: Integer;
begin
  Result := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, AProvider.SentQuery(ATarget));
  if not AAnswered then
    Exit;
  Result.HttpStatus := AStatus;
  case AStatus of
    200:
      begin
        // Eine Anmeldeseite (falsche Adresse, Proxy) antwortet auch mit 200.
        if LooksLikeHtml(AText) or not AProvider.ParseList(AText, MaxIssues + 1, mIssues) then
        begin
          Result.Outcome := TAtlasTrackerQueryOutcome.Unreadable;
          Exit;
        end;
        Result.More := Length(mIssues) > MaxIssues;
        if Result.More then
          SetLength(mIssues, MaxIssues);
        Result.Count := Length(mIssues);
        for mIndex := 0 to High(mIssues) do
          if mIndex < MaxKeys then
            Result.Keys := Result.Keys + [mIssues[mIndex].Key];
        if Result.Count > 0 then
          Result.Outcome := TAtlasTrackerQueryOutcome.Found
        else
          Result.Outcome := TAtlasTrackerQueryOutcome.Empty;
      end;
    400, 422:
      begin
        Result.Outcome := TAtlasTrackerQueryOutcome.QueryRejected;
        Result.TrackerMessage := TrackerMessage(AText);
      end;
    401, 403:
      Result.Outcome := TAtlasTrackerQueryOutcome.Rejected;
    404:
      Result.Outcome := TAtlasTrackerQueryOutcome.ProjectUnknown;
  else
    if LooksLikeHtml(AText) then
      Result.Outcome := TAtlasTrackerQueryOutcome.Unreadable
    else
      Result.Outcome := TAtlasTrackerQueryOutcome.ServerError;
  end;
end;

function Remaining(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  mRest: Int64;
begin
  mRest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if mRest > 0 then
    Result := Integer(mRest);
end;

/// <summary>Probe mit „Mir zugewiesen“ in ALanguage: -1 abgelehnt oder ohne Antwort, sonst die Zahl der Treffer.
/// </summary>
function Probe(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const ALanguage: string; ATimeoutMs: Integer): Integer;
var
  mTarget: TAtlasTrackerTarget;
  mStatus: Integer;
  mText: string;
  mError: TAtlasCiFetchError;
  mIssues: TArray<TAtlasTrackerIssue>;
begin
  Result := -1;
  if ATimeoutMs <= 0 then
    Exit;
  mTarget := ATarget;
  mTarget.Query := TAtlasTrackerTemplates.QueryOf(AProvider.Name, ALanguage, TAtlasTrackerTemplateKind.AssignedToMe);
  if ATransport.Get(AProvider.ListUrl(mTarget, 1), ATimeoutMs, mStatus, mText, mError) and (mStatus = 200) and
    AProvider.ParseList(mText, 1, mIssues) then
    Result := Length(mIssues);
end;

class function TAtlasTrackerQueryTest.DetectLanguage(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer): string;
var
  mWatch: TStopwatch;
  mUrl, mText: string;
  mStatus, mGerman, mEnglish: Integer;
  mError: TAtlasCiFetchError;
begin
  Result := '';
  if (AProvider = nil) or (ATransport = nil) then
    Exit;
  mUrl := AProvider.LocaleUrl(ATarget);
  if mUrl = '' then
    Exit;
  mWatch := TStopwatch.StartNew;
  if ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) and (mStatus = 200) then
    Result := LanguageOfLocale(mText);
  if Result <> '' then
    Exit;
  // Ohne Recht auf die globalen Einstellungen: Die Vorlage in der Sprache der Oberfläche findet etwas, die andere
  // nichts (bzw. wird abgelehnt).
  mGerman := Probe(AProvider, ATarget, ATransport, TAtlasTrackerTemplates.German, Remaining(mWatch, ATimeoutMs));
  mEnglish := Probe(AProvider, ATarget, ATransport, TAtlasTrackerTemplates.English, Remaining(mWatch, ATimeoutMs));
  if (mGerman > 0) and (mEnglish <= 0) then
    Result := TAtlasTrackerTemplates.German
  else if (mEnglish > 0) and (mGerman <= 0) then
    Result := TAtlasTrackerTemplates.English
  else if (mGerman = 0) and (mEnglish < 0) then
    Result := TAtlasTrackerTemplates.German
  else if (mEnglish = 0) and (mGerman < 0) then
    Result := TAtlasTrackerTemplates.English;
end;

class function TAtlasTrackerQueryTest.Run(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport): TAtlasTrackerQueryTestResult;
var
  mWatch: TStopwatch;
  mUrl, mText, mSent, mSuggested: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mAnswered: Boolean;
begin
  if AProvider = nil then
    Exit(TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.NotConfigured, ''));
  if ATransport = nil then
    Exit(TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.NoToken, AProvider.SentQuery(ATarget)));
  mUrl := '';
  if ATarget.Configured then
    mUrl := AProvider.ListUrl(ATarget, MaxIssues + 1);
  // GitHub ohne owner/repo: keine Adresse.
  if mUrl = '' then
    Exit(TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.NotConfigured,
      AProvider.SentQuery(ATarget)));
  mWatch := TStopwatch.StartNew;
  mAnswered := ATransport.Get(mUrl, TimeoutMs, mStatus, mText, mError);
  Result := Evaluate(AProvider, ATarget, mAnswered, mStatus, mText, mError);
  Result.ElapsedMs := mWatch.ElapsedMilliseconds;
  if Result.Outcome <> TAtlasTrackerQueryOutcome.Empty then
    Exit;
  // Anmeldung und Verbindung stehen, nur passt kein Issue: liegt es an der Sprache der Suchbegriffe?
  Result.Language := ATarget.Language;
  if Result.Language = '' then
    Result.Language := DetectLanguage(AProvider, ATarget, ATransport, Remaining(mWatch, TimeoutMs));
  // Gesendet wurde ATarget.Query bzw. ohne sie die Vorgabe zur bisher bekannten Sprache.
  mSent := ATarget.Query;
  if mSent = '' then
    mSent := TAtlasTrackerTemplates.DefaultQuery(AProvider.Name, ATarget.Language);
  mSuggested := TAtlasTrackerTemplates.DefaultQuery(AProvider.Name, Result.Language);
  if (Result.Language = TAtlasTrackerTemplates.German) and not SameText(mSuggested, mSent) then
    Result.SuggestedQuery := mSuggested;
end;

end.
