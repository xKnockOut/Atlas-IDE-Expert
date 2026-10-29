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
    MaxCases = 20;
    RequestName = 'anfrage.json';
    StackName = 'stapel.txt';
    ReplayName = 'wiederholen.cmd';
    /// <summary>Ersatzname des Schnappschusses, wenn die Uri keinen Dateinamen hat.</summary>
    BufferName = 'puffer.pas';
    /// <summary>Version von anfrage.json.</summary>
    FormatVersion = 1;
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
    /// <summary>JSON aus AText; nil, wenn es nicht lesbar ist. Mit Ausnahme statt nil im Parser: Der Parser von
    /// FPC liefert bei Fehlern sonst einen unbestimmten Wert.</summary>
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
  Atlas.Text.Jsonc;

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
    Exit;
  Result := ExtractFileName(FileName);
  // Kein Name, der mit den festen Dateien des Falls zusammenfällt.
  if (Result = '') or SameText(Result, TCrashCases.RequestName) or SameText(Result, TCrashCases.StackName) or
    SameText(Result, TCrashCases.ReplayName) or SameText(Result, 'atlas.json') or
    SameText(Result, 'settings.json') then
    Result := TCrashCases.BufferName;
end;

function TCrashCase.Summary: string;
var
  mWhere, mWhat: string;
begin
  mWhere := '';
  if FileName <> '' then
    mWhere := ExtractFileName(FileName)
  else if Uri <> '' then
    mWhere := Uri;
  if (mWhere <> '') and (Line >= 0) then
    mWhere := mWhere + ':' + IntToStr(Line + 1);
  if Kind = TCrashCaseKind.Timeout then
    mWhat := Format('überschritt das Zeitlimit von %d ms', [TimeoutMs])
  else
    mWhat := 'löste ' + ExceptionClass + ' aus';
  if mWhere <> '' then
    Result := Format('%s in %s %s', [Method, mWhere, mWhat])
  else
    Result := Method + ' ' + mWhat;
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
    if Pos(mPart, mName) > 0 then
      Exit(True);
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
      if CharInSet(Result[mIndex], ['/', '?', '#', ' ', #9, #10, #13, '"']) then
      begin
        mEnd := mIndex;
        Break;
      end;
    mAt := 0;
    for mIndex := mScheme + 3 to mEnd - 1 do
      if Result[mIndex] = '@' then
        mAt := mIndex;
    if mAt > 0 then
      Delete(Result, mScheme + 3, mAt - mScheme - 2);
    mScheme := Pos('://', Result, mScheme + 3);
  end;
end;

class function TCrashCases.ParseOrNil(const AText: string): TJSONValue;
begin
  try
    Result := TJSONValue.ParseJSONValue(AText, False, True);
  except
    on Exception do
      Result := nil;
  end;
end;

class procedure TCrashCases.RedactValue(const AValue: TJSONValue);
var
  mIndex: Integer;
  mObject: TJSONObject;
  mArray: TJSONArray;
  mPair: TJSONPair;
  mName, mText: string;
begin
  if AValue is TJSONObject then
  begin
    mObject := TJSONObject(AValue);
    for mIndex := mObject.Count - 1 downto 0 do
    begin
      mPair := mObject.Pairs[mIndex];
      mName := mPair.JsonString.Value;
      if IsSecretKey(mName) then
        mObject.RemovePair(mName).Free
      // TJSONNumber erbt von TJSONString; Zahlen tragen keine Adressen.
      else if (mPair.JsonValue is TJSONString) and not (mPair.JsonValue is TJSONNumber) then
      begin
        mText := TJSONString(mPair.JsonValue).Value;
        // Neu anhängen statt den Wert zu tauschen: Das Paar hinten ist schon durchlaufen (Schleife rückwärts).
        if (Pos('@', mText) > 0) and (WithoutUserInfo(mText) <> mText) then
        begin
          mObject.RemovePair(mName).Free;
          mObject.AddPair(mName, WithoutUserInfo(mText));
        end;
      end
      else
        RedactValue(mPair.JsonValue);
    end;
  end
  else if AValue is TJSONArray then
  begin
    mArray := TJSONArray(AValue);
    for mIndex := 0 to mArray.Count - 1 do
      RedactValue(mArray.Items[mIndex]);
  end;
end;

class function TCrashCases.Redact(const AJsonText: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if Trim(AJsonText) = '' then
    Exit;
  mValue := ParseOrNil(TJsoncScanner.StripComments(AJsonText));
  if mValue = nil then
    Exit;
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
    Exit;
  mDocument := TJSONObject(AParams).GetValue('textDocument');
  if mDocument is TJSONObject then
  begin
    mDocument := TJSONObject(mDocument).GetValue('uri');
    if mDocument is TJSONString then
      AUri := mDocument.Value;
  end;
  mPosition := TJSONObject(AParams).GetValue('position');
  mLine := nil;
  if mPosition is TJSONObject then
    mLine := TJSONObject(mPosition).GetValue('line')
  else
  begin
    mRange := TJSONObject(AParams).GetValue('range');
    if mRange is TJSONObject then
    begin
      mRange := TJSONObject(mRange).GetValue('start');
      if mRange is TJSONObject then
        mLine := TJSONObject(mRange).GetValue('line');
    end;
  end;
  if mLine is TJSONNumber then
    ALine := TJSONNumber(mLine).AsInt;
  Result := AUri <> '';
end;

class function TCrashCases.RequestJson(const ACase: TCrashCase): string;
var
  mRoot, mException, mFiles: TJSONObject;
  mRecent, mSettings: TJSONArray;
  mValue: TJSONValue;
  mText: string;
  mSetting: TCrashCaseSetting;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(FormatVersion));
    mRoot.AddPair('kind', cKindNames[ACase.Kind]);
    mRoot.AddPair('time', DateToISO8601(ACase.Time, False));
    mRoot.AddPair('processId', TJSONNumber.Create(ACase.ProcessId));
    mRoot.AddPair('method', ACase.Method);
    if ACase.Id <> '' then
    begin
      mValue := ParseOrNil(ACase.Id);
      if mValue <> nil then
        mRoot.AddPair('id', mValue);
    end;
    mValue := nil;
    if ACase.Params <> '' then
      mValue := ParseOrNil(Redact(ACase.Params));
    if mValue <> nil then
      mRoot.AddPair('params', mValue)
    else
      mRoot.AddPair('params', TJSONNull.Create);
    if ACase.Uri <> '' then
      mRoot.AddPair('uri', ACase.Uri);
    if ACase.FileName <> '' then
      mRoot.AddPair('file', ACase.FileName);
    if ACase.Line >= 0 then
      mRoot.AddPair('line', TJSONNumber.Create(ACase.Line));
    if ACase.Kind = TCrashCaseKind.Timeout then
      mRoot.AddPair('timeoutMs', TJSONNumber.Create(ACase.TimeoutMs));
    mException := TJSONObject.Create;
    mRoot.AddPair('exception', mException);
    mException.AddPair('class', ACase.ExceptionClass);
    mException.AddPair('message', WithoutUserInfo(ACase.ExceptionMessage));
    mRoot.AddPair('atlasVersion', ACase.AtlasVersion);
    mRoot.AddPair('buildCompiler', ACase.BuildCompiler);
    if ACase.Client <> '' then
      mRoot.AddPair('client', ACase.Client);
    mFiles := TJSONObject.Create;
    mRoot.AddPair('files', mFiles);
    if ACase.HasText then
      mFiles.AddPair('snapshot', ACase.SnapshotName);
    mFiles.AddPair('stack', StackName);
    mSettings := TJSONArray.Create;
    mFiles.AddPair('settings', mSettings);
    for mSetting in ACase.Settings do
      mSettings.Add(mSetting.Name);
    mValue := nil;
    if ACase.Initialize <> '' then
      mValue := ParseOrNil(Redact(ACase.Initialize));
    if mValue <> nil then
      mRoot.AddPair('initialize', mValue);
    mRecent := TJSONArray.Create;
    mRoot.AddPair('recent', mRecent);
    for mText in ACase.Recent do
    begin
      // TJsonRpcRecentMessages kürzt zu gültigem JSON; anderes (etwa von Hand bearbeitet) als Text, ohne Adressdaten.
      mValue := ParseOrNil(mText);
      if mValue <> nil then
      begin
        RedactValue(mValue);
        mRecent.AddElement(mValue);
      end
      else
        mRecent.Add(WithoutUserInfo(mText));
    end;
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
    mLines.Append('Atlas-Absturzfall ').Append(FolderName(ACase.Time, ACase.ProcessId)).Append(sLineBreak);
    mLines.Append(ACase.Summary).Append(sLineBreak).Append(sLineBreak);
    if ACase.Kind = TCrashCaseKind.Timeout then
      mLines.Append('Art: Abbruch durch den Watchdog').Append(sLineBreak)
    else
      mLines.Append('Art: unbehandelte Ausnahme').Append(sLineBreak);
    mLines.Append('Ausnahme: ').Append(ACase.ExceptionClass).Append(sLineBreak);
    mLines.Append('Meldung: ').Append(WithoutUserInfo(ACase.ExceptionMessage)).Append(sLineBreak);
    mLines.Append('Methode: ').Append(ACase.Method).Append(sLineBreak);
    if ACase.FileName <> '' then
      mLines.Append('Datei: ').Append(ACase.FileName).Append(sLineBreak);
    if ACase.Line >= 0 then
      mLines.Append('Zeile: ').Append(IntToStr(ACase.Line + 1)).Append(sLineBreak);
    mLines.Append('Atlas: ').Append(ACase.AtlasVersion).Append(sLineBreak);
    mLines.Append('Gebaut mit: ').Append(ACase.BuildCompiler).Append(sLineBreak);
    if ACase.Client <> '' then
      mLines.Append('Client: ').Append(ACase.Client).Append(sLineBreak);
    mLines.Append(sLineBreak).Append('Aufrufstapel:').Append(sLineBreak);
    if Trim(ACase.Stack) <> '' then
      mLines.Append(ACase.Stack).Append(sLineBreak)
    else
      mLines.Append('(keiner: ohne Debug-Informationen oder beim Abbruch durch den Watchdog)').Append(sLineBreak);
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
    mServer := 'AtlasServer';
  Result := '@echo off' + sLineBreak +
    'rem Atlas-Absturzfall nachstellen (#1355): Exit-Code 1 = reproduziert, 0 = nicht reproduziert.' + sLineBreak +
    'cd /d "%~dp0"' + sLineBreak +
    '"' + mServer + '" --replay ' + RequestName + sLineBreak +
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
    Exit;
  mList := TList<string>.Create;
  try
    for mFolder in TDirectory.GetDirectories(ARoot) do
      if TFile.Exists(TPath.Combine(mFolder, RequestName)) then
        mList.Add(mFolder);
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
    TFile.WriteAllText(TPath.Combine(Result, ACase.SnapshotName), ACase.Text, TEncoding.UTF8);
  for mSetting in ACase.Settings do
  begin
    // Nicht lesbar: lieber ohne die Datei als mit möglichen Zugangsdaten.
    mText := Redact(mSetting.Text);
    if mText <> '' then
      TFile.WriteAllText(TPath.Combine(Result, mSetting.Name), mText, TEncoding.UTF8);
  end;
  TFile.WriteAllText(TPath.Combine(Result, StackName), StackText(ACase), TEncoding.UTF8);
  // Ohne BOM: cmd.exe liest sonst „ï»¿@echo“ als Befehl.
  TFile.WriteAllBytes(TPath.Combine(Result, ReplayName), TEncoding.ANSI.GetBytes(ReplayScript(ACase)));
  // Zuletzt: Ein Ordner gilt erst mit anfrage.json als Fall (Folders).
  TFile.WriteAllText(TPath.Combine(Result, RequestName), RequestJson(ACase), TEncoding.UTF8);
  Prune(ARoot, MaxCases);
end;

function StringOf(const AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
    Result := mValue.Value;
end;

class function TCrashCases.Load(const AFileName: string; out ACase: TCrashCase; out AError: string): Boolean;
var
  mFolder, mName: string;
  mRoot: TJSONValue;
  mObject, mFiles: TJSONObject;
  mValue: TJSONValue;
  mSettings: TJSONArray;
  mIndex: Integer;
  mTime: TDateTime;
begin
  ACase := TCrashCase.Empty;
  AError := '';
  Result := False;
  if not TFile.Exists(AFileName) then
  begin
    AError := 'Datei nicht gefunden: ' + AFileName;
    Exit;
  end;
  mFolder := ExtractFileDir(TPath.GetFullPath(AFileName));
  mRoot := ParseOrNil(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  if not (mRoot is TJSONObject) then
  begin
    mRoot.Free;
    AError := 'Kein Absturzfall (JSON-Objekt erwartet): ' + AFileName;
    Exit;
  end;
  try
    mObject := TJSONObject(mRoot);
    ACase.Method := StringOf(mObject, 'method');
    if ACase.Method = '' then
    begin
      AError := 'Im Absturzfall fehlt "method"';
      Exit;
    end;
    if StringOf(mObject, 'kind') = cKindNames[TCrashCaseKind.Timeout] then
      ACase.Kind := TCrashCaseKind.Timeout;
    if TryISO8601ToDate(StringOf(mObject, 'time'), mTime, False) then
      ACase.Time := mTime;
    mValue := mObject.GetValue('processId');
    if mValue is TJSONNumber then
      ACase.ProcessId := Cardinal(TJSONNumber(mValue).AsInt64);
    mValue := mObject.GetValue('id');
    if mValue <> nil then
      ACase.Id := mValue.ToJSON;
    mValue := mObject.GetValue('params');
    if (mValue <> nil) and not (mValue is TJSONNull) then
      ACase.Params := mValue.ToJSON;
    ACase.Uri := StringOf(mObject, 'uri');
    ACase.FileName := StringOf(mObject, 'file');
    mValue := mObject.GetValue('line');
    if mValue is TJSONNumber then
      ACase.Line := TJSONNumber(mValue).AsInt;
    mValue := mObject.GetValue('timeoutMs');
    if mValue is TJSONNumber then
      ACase.TimeoutMs := Cardinal(TJSONNumber(mValue).AsInt64);
    mValue := mObject.GetValue('exception');
    if mValue is TJSONObject then
    begin
      ACase.ExceptionClass := StringOf(TJSONObject(mValue), 'class');
      ACase.ExceptionMessage := StringOf(TJSONObject(mValue), 'message');
    end;
    ACase.AtlasVersion := StringOf(mObject, 'atlasVersion');
    ACase.BuildCompiler := StringOf(mObject, 'buildCompiler');
    ACase.Client := StringOf(mObject, 'client');
    mValue := mObject.GetValue('initialize');
    if mValue <> nil then
      ACase.Initialize := mValue.ToJSON;
    mValue := mObject.GetValue('files');
    if mValue is TJSONObject then
    begin
      mFiles := TJSONObject(mValue);
      mName := StringOf(mFiles, 'snapshot');
      if (mName <> '') and TFile.Exists(TPath.Combine(mFolder, ExtractFileName(mName))) then
      begin
        ACase.Text := TFile.ReadAllText(TPath.Combine(mFolder, ExtractFileName(mName)), TEncoding.UTF8);
        ACase.HasText := True;
        // SnapshotName nimmt den Namen aus FileName; ohne Pfad im Fall den gespeicherten Namen.
        if ACase.FileName = '' then
          ACase.FileName := mName;
      end;
      mValue := mFiles.GetValue('settings');
      if mValue is TJSONArray then
      begin
        mSettings := TJSONArray(mValue);
        for mIndex := 0 to mSettings.Count - 1 do
        begin
          mName := ExtractFileName(mSettings.Items[mIndex].Value);
          if (mName <> '') and TFile.Exists(TPath.Combine(mFolder, mName)) then
            ACase.Settings := ACase.Settings + [TCrashCaseSetting.Create(mName,
              TFile.ReadAllText(TPath.Combine(mFolder, mName), TEncoding.UTF8))];
        end;
      end;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

end.
