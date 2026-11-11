unit Atlas.Common.Diagnostics.CrashCase;

// Absturzfall als nachstellbarer Fall (#1355): Stürzt eine Anfrage mit einer
// unerwarteten Ausnahme ab oder bricht der Watchdog sie ab, legt der Server
// unter <Wurzel>\<JJJJ-MM-TT_hhmmss>_<pid>\ ab:
// - anfrage.json: Art, Methode, id und Parameter der Anfrage, die letzten 20
//   Nachrichten (gekürzt), Parameter von initialize, Ausnahme, Versionen und
//   die Namen der Dateien daneben;
// - den Schnappschuss des Puffers bzw. der Datei, auf die sich die Anfrage
//   bezieht (unter ihrem Dateinamen), und die Einstellungen (atlas.json,
//   settings.json) ohne Zugangsdaten;
// - stapel.txt: Ausnahmeklasse, Meldung, Aufrufstapel, Atlas- und
//   Delphi-Version;
// - wiederholen.cmd: AtlasServer --replay anfrage.json.
// Höchstens MaxCases Fälle; ältere löscht Prune (nach dem Namen, der mit dem
// Zeitpunkt beginnt).
// Zugangsdaten: Redact entfernt aus jedem JSON (Parameter, Nachrichten,
// initialize, Einstellungen) alle Paare, deren Name nach Zugangsdaten
// aussieht (IsSecretKey), und Benutzer und Kennwort aus Adressen
// (https://name:geheim@host). Nicht lesbare Einstellungen fallen ganz weg,
// statt ungefiltert im Fall zu landen.
// Kein Netzzugriff: Fälle bleiben lokal, bis der Benutzer sie weitergibt.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Unbehandelte Ausnahme im Handler bzw. Abbruch durch den Watchdog.</summary>
  TCrashCaseKind = (Exception_, Timeout);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Einstellungsdatei im Fall: Name im Ordner (atlas.json, settings.json) und Text ohne
  /// Zugangsdaten.</summary>
  TCrashCaseSetting = record
    Name: string;
    Text: string;
    class function Create(const AName, AText: string): TCrashCaseSetting; static;
  end;

  TCrashCase = record
    Kind: TCrashCaseKind;
    Time: TDateTime;
    ProcessId: Cardinal;
    Method: string;
    /// <summary>id der Anfrage als JSON-Text; '' unbekannt.</summary>
    Id: string;
    /// <summary>Parameter als JSON-Text; '' ohne.</summary>
    Params: string;
    /// <summary>textDocument.uri der Parameter; '' ohne Dokument.</summary>
    Uri: string;
    /// <summary>Pfad der Datei zu Uri; '' ohne.</summary>
    FileName: string;
    /// <summary>Zeile ab 0 aus position bzw. range.start; -1 ohne.</summary>
    Line: Integer;
    /// <summary>Inhalt des Puffers (bzw. der Datei) beim Absturz; nur mit HasText.</summary>
    Text: string;
    HasText: Boolean;
    /// <summary>Die letzten Nachrichten, gekürzt, älteste zuerst.</summary>
    Recent: TArray<string>;
    /// <summary>Parameter von initialize als JSON-Text; '' unbekannt.</summary>
    Initialize: string;
    Settings: TArray<TCrashCaseSetting>;
    ExceptionClass: string;
    ExceptionMessage: string;
    /// <summary>Aufrufstapel mit Unit und Zeile, soweit Debug-Informationen vorhanden sind.</summary>
    Stack: string;
    /// <summary>Zeitlimit beim Abbruch durch den Watchdog.</summary>
    TimeoutMs: Cardinal;
    AtlasVersion: string;
    /// <summary>Compiler, mit dem der Server gebaut wurde, etwa „Delphi 37.0“.</summary>
    BuildCompiler: string;
    /// <summary>Client aus initialize (clientInfo), etwa „RAD Studio 37.0“; '' unbekannt.</summary>
    Client: string;
    /// <summary>Pfad von AtlasServer für wiederholen.cmd; '' = „AtlasServer“ aus dem Suchpfad.</summary>
    ServerPath: string;
    /// <summary>Leer bis auf Line = -1 und Kind = Exception_.</summary>
    class function Empty: TCrashCase; static;
    /// <summary>Dateiname des Schnappschusses im Ordner ('' ohne): Name der Datei, sonst „puffer.pas“.</summary>
    function SnapshotName: string;
    /// <summary>„textDocument/hover in UI.Auftrag.pas:812 löste EStackOverflow aus“ (Zeile ab 1).</summary>
    function Summary: string;
  end;

  TCrashCases = class
  public const
    cMaxCases = 20;
    cRequestName = 'anfrage.json';
    cStackName = 'stapel.txt';
    cReplayName = 'wiederholen.cmd';
    /// <summary>Ersatzname des Schnappschusses, wenn die Uri keinen Dateinamen hat.</summary>
    cBufferName = 'puffer.pas';
    /// <summary>Version von anfrage.json.</summary>
    cFormatVersion = 1;
  public
    /// <summary>„2026-10-29_211530_4711“.</summary>
    class function FolderName(ATime: TDateTime; AProcessId: Cardinal): string; static;
    /// <summary>Legt den Fall unter ARoot an und liefert seinen Ordner; ältere Fälle über MaxCases werden
    /// gelöscht. Ausnahmen beim Schreiben gehen an den Aufrufer.</summary>
    class function Write(const ARoot: string; const ACase: TCrashCase): string; static;
    /// <summary>Löscht die ältesten Fälle unter ARoot, bis höchstens AKeep bleiben.</summary>
    class procedure Prune(const ARoot: string; AKeep: Integer); static;
    /// <summary>Ordner der Fälle unter ARoot, älteste zuerst.</summary>
    class function Folders(const ARoot: string): TArray<string>; static;
    /// <summary>Liest anfrage.json samt Schnappschuss und Einstellungen daneben; False mit AError.</summary>
    class function Load(const AFileName: string; out ACase: TCrashCase; out AError: string): Boolean; static;
    /// <summary>Inhalt von anfrage.json.</summary>
    class function RequestJson(const ACase: TCrashCase): string; static;
    /// <summary>Inhalt von stapel.txt.</summary>
    class function StackText(const ACase: TCrashCase): string; static;
    /// <summary>Inhalt von wiederholen.cmd.</summary>
    class function ReplayScript(const ACase: TCrashCase): string; static;
    /// <summary>Sieht der Name eines JSON-Paars nach Zugangsdaten aus (token, password, secret, apiKey …)?
    /// </summary>
    class function IsSecretKey(const AName: string): Boolean; static;
    /// <summary>Adresse ohne Benutzer und Kennwort (https://name:geheim@host → https://host).</summary>
    class function WithoutUserInfo(const AText: string): string; static;
    /// <summary>JSON-Text (auch mit Kommentaren) ohne Zugangsdaten, kompakt; '' wenn er nicht lesbar ist.
    /// </summary>
    class function Redact(const AJsonText: string): string; static;
    /// <summary>JSON aus AText; nil, wenn es nicht lesbar ist. Unter FPC leitet Convert-ForFpc den Aufruf auf
    /// AtlasJsonCompat um, das ebenfalls nil liefert (#1356).</summary>
    class function ParseOrNil(const AText: string): TJSONValue; static;
    /// <summary>Entfernt Zugangsdaten in AValue selbst.</summary>
    class procedure RedactValue(const AValue: TJSONValue); static;
    /// <summary>textDocument.uri und Zeile (position.line bzw. range.start.line) der Parameter; False ohne
    /// Dokument.</summary>
    class function DocumentOf(const AParams: TJSONValue; out AUri: string; out ALine: Integer): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Json,
  Atlas.Text.Jsonc,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCrashCaseText = (ExceededTheTimeLimitOf, Raised, KindAbortedByTheWatchdog, FileText, BuiltWith,
    NoneWithoutDebugInformationOr, FileNotFound, NoCrashCaseJSONObject, TheCrashCaseLacksMethod, AtlasCrashCase,
    KindUnhandledException, Exception, Message, Line, CallStack);

const
  cTexts: array[TCrashCaseText] of TAtlasText = (
    (De: 'überschritt das Zeitlimit von %d ms'; En: 'exceeded the time limit of %d ms'),
    (De: 'löste %s aus'; En: 'raised %s'),
    (De: 'Art: Abbruch durch den Watchdog'; En: 'Kind: aborted by the watchdog'),
    (De: 'Datei: '; En: 'File: '),
    (De: 'Gebaut mit: '; En: 'Built with: '),
    (De: '(keiner: ohne Debug-Informationen oder beim Abbruch durch den Watchdog)';
     En: '(none: without debug information or when aborted by the watchdog)'),
    (De: 'Datei nicht gefunden: '; En: 'File not found: '),
    (De: 'Kein Absturzfall (JSON-Objekt erwartet): '; En: 'No crash case (JSON object expected): '),
    (De: 'Im Absturzfall fehlt "method"'; En: 'The crash case lacks "method"'),
    (De: 'Atlas-Absturzfall '; En: 'Atlas crash case '),
    (De: 'Art: unbehandelte Ausnahme'; En: 'Kind: unhandled exception'),
    (De: 'Ausnahme: '; En: 'Exception: '),
    (De: 'Meldung: '; En: 'Message: '),
    (De: 'Zeile: '; En: 'Line: '),
    (De: 'Aufrufstapel:'; En: 'Call stack:'));

{$SCOPEDENUMS OFF}

const
  cKindNames: array[TCrashCaseKind] of string = ('exception', 'timeout');
  cSecretParts: array[0..10] of string = ('token', 'password', 'passwort', 'kennwort', 'secret', 'apikey',
    'api_key', 'credential', 'authorization', 'privatekey', 'cookie');

{ TCrashCaseSetting }

class function TCrashCaseSetting.Create(const AName, AText: string): TCrashCaseSetting;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

/// <summary>AName ist eine der festen Dateien eines Falls (oder eine Einstellungsdatei).</summary>
function IsFixedFileName(const AName: string): Boolean;
begin
  Result := SameText(AName, TCrashCases.cRequestName) or SameText(AName, TCrashCases.cStackName) or
    SameText(AName, TCrashCases.cReplayName) or SameText(AName, 'atlas.json') or SameText(AName, 'settings.json');
end;

{ TCrashCase }

class function TCrashCase.Empty: TCrashCase;
begin
  Result := Default(TCrashCase);
  Result.Kind := TCrashCaseKind.Exception_;
  Result.Line := -1;
end;

function TCrashCase.SnapshotName: string;
begin
  Result := '';
  if not HasText then
  begin
    Exit;
  end;
  Result := ExtractFileName(FileName);
  // Kein Name, der mit den festen Dateien des Falls zusammenfällt.
  if (Result = '') or IsFixedFileName(Result) then
  begin
    Result := TCrashCases.cBufferName;
  end;
end;

function TCrashCase.Summary: string;
var
  mWhere, mWhat: string;
begin
  mWhere := '';
  if FileName <> '' then
  begin
    mWhere := ExtractFileName(FileName);
  end
  else if Uri <> '' then
  begin
    mWhere := Uri;
  end;
  if (mWhere <> '') and (Line >= 0) then
  begin
    mWhere := mWhere + ':' + IntToStr(Line + 1);
  end;
  if Kind = TCrashCaseKind.Timeout then
  begin
    mWhat := cTexts[TCrashCaseText.ExceededTheTimeLimitOf].Fmt([TimeoutMs]);
  end
  else
  begin
    mWhat := cTexts[TCrashCaseText.Raised].Fmt([ExceptionClass]);
  end;
  if mWhere <> '' then
  begin
    Result := Format('%s in %s %s', [Method, mWhere, mWhat]);
  end
  else
  begin
    Result := Method + ' ' + mWhat;
  end;
end;

{ TCrashCases }

class function TCrashCases.FolderName(ATime: TDateTime; AProcessId: Cardinal): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"_"hhnnss', ATime) + '_' + IntToStr(AProcessId);
end;

class function TCrashCases.IsSecretKey(const AName: string): Boolean;
var
  mName, mPart: string;
begin
  mName := LowerCase(AName);
  for mPart in cSecretParts do
  begin
    if Pos(mPart, mName) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCrashCases.WithoutUserInfo(const AText: string): string;
var
  mScheme, mAt, mEnd, mIndex: Integer;
begin
  Result := AText;
  mScheme := Pos('://', Result);
  while mScheme > 0 do
  begin
    // Ende der Autorität: erstes /, ?, # oder Leerraum nach dem Schema.
    mEnd := Length(Result) + 1;
    for mIndex := mScheme + 3 to Length(Result) do
    begin
      if CharInSet(Result[mIndex], ['/', '?', '#', ' ', #9, #10, #13, '"']) then
      begin
        mEnd := mIndex;
        Break;
      end;
    end;
    mAt := 0;
    for mIndex := mScheme + 3 to mEnd - 1 do
    begin
      if Result[mIndex] = '@' then
      begin
        mAt := mIndex;
      end;
    end;
    if mAt > 0 then
    begin
      Delete(Result, mScheme + 3, mAt - mScheme - 2);
    end;
    mScheme := Pos('://', Result, mScheme + 3);
  end;
end;

class function TCrashCases.ParseOrNil(const AText: string): TJSONValue;
begin
  Result := TJSONValue.ParseJSONValue(AText);
end;

/// <summary>Entfernt geheime Schlüssel aus dem Paar AIndex von AObject und Benutzerangaben aus Adressen darin.
/// </summary>
procedure RedactPair(AObject: TJSONObject; AIndex: Integer);
var
  mPair: TJSONPair;
  mName, mText: string;
begin
  mPair := AObject.Pairs[AIndex];
  mName := mPair.JsonString.Value;
  if TCrashCases.IsSecretKey(mName) then
  begin
    AObject.RemovePair(mName).Free;
  end
  // TJSONNumber erbt von TJSONString; Zahlen tragen keine Adressen.
  else if (mPair.JsonValue is TJSONString) and not (mPair.JsonValue is TJSONNumber) then
  begin
    mText := TJSONString(mPair.JsonValue).Value;
    // Neu anhängen statt den Wert zu tauschen: Das Paar hinten ist schon durchlaufen (Schleife rückwärts).
    if (Pos('@', mText) > 0) and (TCrashCases.WithoutUserInfo(mText) <> mText) then
    begin
      AObject.RemovePair(mName).Free;
      AObject.AddPair(mName, TCrashCases.WithoutUserInfo(mText));
    end;
  end
  else
  begin
    TCrashCases.RedactValue(mPair.JsonValue);
  end;
end;

class procedure TCrashCases.RedactValue(const AValue: TJSONValue);
var
  mIndex: Integer;
  mArray: TJSONArray;
begin
  if AValue is TJSONObject then
  begin
    for mIndex := TJSONObject(AValue).Count - 1 downto 0 do
    begin
      RedactPair(TJSONObject(AValue), mIndex);
    end;
  end
  else if AValue is TJSONArray then
  begin
    mArray := TJSONArray(AValue);
    for mIndex := 0 to mArray.Count - 1 do
    begin
      RedactValue(mArray.Items[mIndex]);
    end;
  end;
end;

class function TCrashCases.Redact(const AJsonText: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if Trim(AJsonText) = '' then
  begin
    Exit;
  end;
  mValue := ParseOrNil(TJsoncScanner.StripComments(AJsonText));
  if mValue = nil then
  begin
    Exit;
  end;
  try
    RedactValue(mValue);
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

class function TCrashCases.DocumentOf(const AParams: TJSONValue; out AUri: string; out ALine: Integer): Boolean;
var
  mDocument, mPosition, mRange: TJSONValue;
  mLine: TJSONValue;
begin
  AUri := '';
  ALine := -1;
  Result := False;
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  mDocument := TJSONObject(AParams).GetValue('textDocument');
  if mDocument is TJSONObject then
  begin
    mDocument := TJSONObject(mDocument).GetValue('uri');
    if mDocument is TJSONString then
    begin
      AUri := mDocument.Value;
    end;
  end;
  mPosition := TJSONObject(AParams).GetValue('position');
  mLine := nil;
  if mPosition is TJSONObject then
  begin
    mLine := TJSONObject(mPosition).GetValue('line');
  end
  else
  begin
    mRange := TJSONObject(AParams).GetValue('range');
    if mRange is TJSONObject then
    begin
      mRange := TJSONObject(mRange).GetValue('start');
      if mRange is TJSONObject then
      begin
        mLine := TJSONObject(mRange).GetValue('line');
      end;
    end;
  end;
  if mLine is TJSONNumber then
  begin
    ALine := TJSONNumber(mLine).AsInt;
  end;
  Result := AUri <> '';
end;

/// <summary>JSON-Text AText (ohne geheime Werte) als Wert; nil, wenn leer oder nicht lesbar.</summary>
function RedactedValue(const AText: string): TJSONValue;
begin
  Result := nil;
  if AText <> '' then
  begin
    Result := TCrashCases.ParseOrNil(TCrashCases.Redact(AText));
  end;
end;

/// <summary>Anfrage, Fundstelle und Ausnahme des Falls.</summary>
procedure AddRequest(ARoot: TJSONObject; const ACase: TCrashCase);
var
  mValue: TJSONValue;
  mException: TJSONObject;
begin
  ARoot.AddPair('method', ACase.Method);
  mValue := nil;
  if ACase.Id <> '' then
  begin
    mValue := TCrashCases.ParseOrNil(ACase.Id);
  end;
  if mValue <> nil then
  begin
    ARoot.AddPair('id', mValue);
  end;
  mValue := RedactedValue(ACase.Params);
  if mValue = nil then
  begin
    mValue := TJSONNull.Create;
  end;
  ARoot.AddPair('params', mValue);
  if ACase.Uri <> '' then
  begin
    ARoot.AddPair('uri', ACase.Uri);
  end;
  if ACase.FileName <> '' then
  begin
    ARoot.AddPair('file', ACase.FileName);
  end;
  if ACase.Line >= 0 then
  begin
    ARoot.AddPair('line', TJSONNumber.Create(ACase.Line));
  end;
  if ACase.Kind = TCrashCaseKind.Timeout then
  begin
    ARoot.AddPair('timeoutMs', TJSONNumber.Create(ACase.TimeoutMs));
  end;
  mException := TJSONObject.Create;
  ARoot.AddPair('exception', mException);
  mException.AddPair('class', ACase.ExceptionClass);
  mException.AddPair('message', TCrashCases.WithoutUserInfo(ACase.ExceptionMessage));
end;

/// <summary>Namen der Dateien neben anfrage.json.</summary>
function FilesJson(const ACase: TCrashCase): TJSONObject;
var
  mSettings: TJSONArray;
  mSetting: TCrashCaseSetting;
begin
  Result := TJSONObject.Create;
  if ACase.HasText then
  begin
    Result.AddPair('snapshot', ACase.SnapshotName);
  end;
  Result.AddPair('stack', TCrashCases.cStackName);
  mSettings := TJSONArray.Create;
  Result.AddPair('settings', mSettings);
  for mSetting in ACase.Settings do
  begin
    mSettings.Add(mSetting.Name);
  end;
end;

/// <summary>Letzte Nachrichten ohne geheime Werte.</summary>
function RecentJson(const ACase: TCrashCase): TJSONArray;
var
  mValue: TJSONValue;
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ACase.Recent do
  begin
    // TJsonRpcRecentMessages kürzt zu gültigem JSON; anderes (etwa von Hand bearbeitet) als Text, ohne Adressdaten.
    mValue := TCrashCases.ParseOrNil(mText);
    if mValue <> nil then
    begin
      TCrashCases.RedactValue(mValue);
      Result.AddElement(mValue);
    end
    else
    begin
      Result.Add(TCrashCases.WithoutUserInfo(mText));
    end;
  end;
end;

class function TCrashCases.RequestJson(const ACase: TCrashCase): string;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormatVersion));
    mRoot.AddPair('kind', cKindNames[ACase.Kind]);
    mRoot.AddPair('time', DateToISO8601(ACase.Time, False));
    mRoot.AddPair('processId', TJSONNumber.Create(ACase.ProcessId));
    AddRequest(mRoot, ACase);
    mRoot.AddPair('atlasVersion', ACase.AtlasVersion);
    mRoot.AddPair('buildCompiler', ACase.BuildCompiler);
    if ACase.Client <> '' then
    begin
      mRoot.AddPair('client', ACase.Client);
    end;
    mRoot.AddPair('files', FilesJson(ACase));
    mValue := RedactedValue(ACase.Initialize);
    if mValue <> nil then
    begin
      mRoot.AddPair('initialize', mValue);
    end;
    mRoot.AddPair('recent', RecentJson(ACase));
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

class function TCrashCases.StackText(const ACase: TCrashCase): string;
var
  mLines: TStringBuilder;
begin
  mLines := TStringBuilder.Create;
  try
    mLines.Append(cTexts[TCrashCaseText.AtlasCrashCase].Text).Append(FolderName(ACase.Time,
      ACase.ProcessId)).Append(sLineBreak);
    mLines.Append(ACase.Summary).Append(sLineBreak).Append(sLineBreak);
    if ACase.Kind = TCrashCaseKind.Timeout then
    begin
      mLines.Append(cTexts[TCrashCaseText.KindAbortedByTheWatchdog].Text).Append(sLineBreak);
    end
    else
    begin
      mLines.Append(cTexts[TCrashCaseText.KindUnhandledException].Text).Append(sLineBreak);
    end;
    mLines.Append(cTexts[TCrashCaseText.Exception].Text).Append(ACase.ExceptionClass).Append(sLineBreak);
    mLines.Append(cTexts[TCrashCaseText.Message].Text).Append(WithoutUserInfo(ACase.ExceptionMessage))
      .Append(sLineBreak);
    mLines.Append('Methode: ').Append(ACase.Method).Append(sLineBreak);
    if ACase.FileName <> '' then
    begin
      mLines.Append(cTexts[TCrashCaseText.FileText].Text).Append(ACase.FileName).Append(sLineBreak);
    end;
    if ACase.Line >= 0 then
    begin
      mLines.Append(cTexts[TCrashCaseText.Line].Text).Append(IntToStr(ACase.Line + 1)).Append(sLineBreak);
    end;
    mLines.Append('Atlas: ').Append(ACase.AtlasVersion).Append(sLineBreak);
    mLines.Append(cTexts[TCrashCaseText.BuiltWith].Text).Append(ACase.BuildCompiler).Append(sLineBreak);
    if ACase.Client <> '' then
    begin
      mLines.Append('Client: ').Append(ACase.Client).Append(sLineBreak);
    end;
    mLines.Append(sLineBreak).Append(cTexts[TCrashCaseText.CallStack].Text).Append(sLineBreak);
    if Trim(ACase.Stack) <> '' then
    begin
      mLines.Append(ACase.Stack).Append(sLineBreak);
    end
    else
    begin
      mLines.Append(cTexts[TCrashCaseText.NoneWithoutDebugInformationOr].Text).Append(sLineBreak);
    end;
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

class function TCrashCases.ReplayScript(const ACase: TCrashCase): string;
var
  mServer: string;
begin
  mServer := ACase.ServerPath;
  if mServer = '' then
  begin
    mServer := 'AtlasServer';
  end;
  Result := '@echo off' + sLineBreak +
    'rem Atlas-Absturzfall nachstellen (#1355): Exit-Code 1 = reproduziert, 0 = nicht reproduziert.' + sLineBreak +
    'cd /d "%~dp0"' + sLineBreak +
    '"' + mServer + '" --replay ' + cRequestName + sLineBreak +
    'echo Exit-Code %ERRORLEVEL%' + sLineBreak +
    'pause' + sLineBreak;
end;

class function TCrashCases.Folders(const ARoot: string): TArray<string>;
var
  mList: TList<string>;
  mFolder: string;
begin
  Result := nil;
  if (ARoot = '') or not TDirectory.Exists(ARoot) then
  begin
    Exit;
  end;
  mList := TList<string>.Create;
  try
    for mFolder in TDirectory.GetDirectories(ARoot) do
    begin
      if TFile.Exists(TPath.Combine(mFolder, cRequestName)) then
      begin
        mList.Add(mFolder);
      end;
    end;
    // Der Name beginnt mit dem Zeitpunkt; gleiche Namen gibt es nicht (Write hängt -2, -3 an).
    mList.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareStr(ExtractFileName(ALeft), ExtractFileName(ARight));
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class procedure TCrashCases.Prune(const ARoot: string; AKeep: Integer);
var
  mFolders: TArray<string>;
  mIndex: Integer;
begin
  mFolders := Folders(ARoot);
  for mIndex := 0 to Length(mFolders) - AKeep - 1 do
    try
      TDirectory.Delete(mFolders[mIndex], True);
    except
      // Gesperrt (etwa im Explorer offen) oder schon weg: beim nächsten Fall erneut.
      // lsp-ignore: catch-all-without-raise -- Aufräumen nach Kräften, nächster Fall versucht es erneut
      on Exception do
        ;
    end;
end;

class function TCrashCases.Write(const ARoot: string; const ACase: TCrashCase): string;
var
  mBase: string;
  mNumber: Integer;
  mSetting: TCrashCaseSetting;
  mText: string;
begin
  mBase := TPath.Combine(ARoot, FolderName(ACase.Time, ACase.ProcessId));
  Result := mBase;
  mNumber := 1;
  while TDirectory.Exists(Result) do
  begin
    Inc(mNumber);
    Result := mBase + '-' + IntToStr(mNumber);
  end;
  TDirectory.CreateDirectory(Result);
  if ACase.HasText then
  begin
    TFile.WriteAllText(TPath.Combine(Result, ACase.SnapshotName), ACase.Text, TEncoding.UTF8);
  end;
  for mSetting in ACase.Settings do
  begin
    // Nicht lesbar: lieber ohne die Datei als mit möglichen Zugangsdaten.
    mText := Redact(mSetting.Text);
    if mText <> '' then
    begin
      TFile.WriteAllText(TPath.Combine(Result, mSetting.Name), mText, TEncoding.UTF8);
    end;
  end;
  TFile.WriteAllText(TPath.Combine(Result, cStackName), StackText(ACase), TEncoding.UTF8);
  // Ohne BOM: cmd.exe liest sonst „ï»¿@echo“ als Befehl.
  TFile.WriteAllBytes(TPath.Combine(Result, cReplayName), TEncoding.ANSI.GetBytes(ReplayScript(ACase)));
  // Zuletzt: Ein Ordner gilt erst mit anfrage.json als Fall (Folders).
  TFile.WriteAllText(TPath.Combine(Result, cRequestName), RequestJson(ACase), TEncoding.UTF8);
  Prune(ARoot, cMaxCases);
end;

/// <summary>Wert AName aus AObject als JSON-Text; '' ohne Wert und bei null.</summary>
function JsonOf(const AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if (mValue <> nil) and not (mValue is TJSONNull) then
  begin
    Result := mValue.ToJSON;
  end;
end;

/// <summary>Felder des Falls aus anfrage.json, ohne die Dateien.</summary>
procedure ReadFields(AObject: TJSONObject; var ACase: TCrashCase);
var
  mValue: TJSONValue;
  mTime: TDateTime;
begin
  if TJsonRead.Text(AObject, 'kind') = cKindNames[TCrashCaseKind.Timeout] then
  begin
    ACase.Kind := TCrashCaseKind.Timeout;
  end;
  if TryISO8601ToDate(TJsonRead.Text(AObject, 'time'), mTime, False) then
  begin
    ACase.Time := mTime;
  end;
  ACase.ProcessId := Cardinal(TJsonRead.Int64Or(AObject, 'processId', ACase.ProcessId));
  mValue := AObject.GetValue('id');
  if mValue <> nil then
  begin
    ACase.Id := mValue.ToJSON;
  end;
  ACase.Params := JsonOf(AObject, 'params');
  ACase.Uri := TJsonRead.Text(AObject, 'uri');
  ACase.FileName := TJsonRead.Text(AObject, 'file');
  ACase.Line := Integer(TJsonRead.Int64Or(AObject, 'line', ACase.Line));
  ACase.TimeoutMs := Cardinal(TJsonRead.Int64Or(AObject, 'timeoutMs', ACase.TimeoutMs));
  mValue := AObject.GetValue('exception');
  if mValue is TJSONObject then
  begin
    ACase.ExceptionClass := TJsonRead.Text(TJSONObject(mValue), 'class');
    ACase.ExceptionMessage := TJsonRead.Text(TJSONObject(mValue), 'message');
  end;
  ACase.AtlasVersion := TJsonRead.Text(AObject, 'atlasVersion');
  ACase.BuildCompiler := TJsonRead.Text(AObject, 'buildCompiler');
  ACase.Client := TJsonRead.Text(AObject, 'client');
  mValue := AObject.GetValue('initialize');
  if mValue <> nil then
  begin
    ACase.Initialize := mValue.ToJSON;
  end;
end;

/// <summary>Einstellungsdateien aus ASettings, die in AFolder liegen.</summary>
procedure ReadSettings(ASettings: TJSONArray; const AFolder: string; var ACase: TCrashCase);
var
  mIndex: Integer;
  mName: string;
begin
  for mIndex := 0 to ASettings.Count - 1 do
  begin
    mName := ExtractFileName(ASettings.Items[mIndex].Value);
    if (mName <> '') and TFile.Exists(TPath.Combine(AFolder, mName)) then
    begin
      ACase.Settings := ACase.Settings + [TCrashCaseSetting.Create(mName,
        TFile.ReadAllText(TPath.Combine(AFolder, mName), TEncoding.UTF8))];
    end;
  end;
end;

/// <summary>Stand des Puffers und Einstellungsdateien laut "files" aus AFolder.</summary>
procedure ReadFiles(AFiles: TJSONObject; const AFolder: string; var ACase: TCrashCase);
var
  mName: string;
  mValue: TJSONValue;
begin
  mName := TJsonRead.Text(AFiles, 'snapshot');
  if (mName <> '') and TFile.Exists(TPath.Combine(AFolder, ExtractFileName(mName))) then
  begin
    ACase.Text := TFile.ReadAllText(TPath.Combine(AFolder, ExtractFileName(mName)), TEncoding.UTF8);
    ACase.HasText := True;
    // SnapshotName nimmt den Namen aus FileName; ohne Pfad im Fall den gespeicherten Namen.
    if ACase.FileName = '' then
    begin
      ACase.FileName := mName;
    end;
  end;
  mValue := AFiles.GetValue('settings');
  if mValue is TJSONArray then
  begin
    ReadSettings(TJSONArray(mValue), AFolder, ACase);
  end;
end;

class function TCrashCases.Load(const AFileName: string; out ACase: TCrashCase; out AError: string): Boolean;
var
  mRoot, mFiles: TJSONValue;
  mObject: TJSONObject;
begin
  ACase := TCrashCase.Empty;
  AError := '';
  Result := False;
  if not TFile.Exists(AFileName) then
  begin
    AError := cTexts[TCrashCaseText.FileNotFound].Text + AFileName;
    Exit;
  end;
  mRoot := ParseOrNil(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  try
    if not (mRoot is TJSONObject) then
    begin
      AError := cTexts[TCrashCaseText.NoCrashCaseJSONObject].Text + AFileName;
      Exit;
    end;
    mObject := TJSONObject(mRoot);
    ACase.Method := TJsonRead.Text(mObject, 'method');
    if ACase.Method = '' then
    begin
      AError := cTexts[TCrashCaseText.TheCrashCaseLacksMethod].Text;
      Exit;
    end;
    ReadFields(mObject, ACase);
    mFiles := mObject.GetValue('files');
    if mFiles is TJSONObject then
    begin
      ReadFiles(TJSONObject(mFiles), ExtractFileDir(TPath.GetFullPath(AFileName)), ACase);
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Diagnostics.CrashCase', cTexts);

end.
