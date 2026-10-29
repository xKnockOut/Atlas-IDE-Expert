unit Atlas.Common.Diagnostics.ServerPackage;

// Teil des Servers im Diagnosepaket (#1356, Erweiterung von #108): der Status
// als JSON, das Serverprotokoll der Sitzung und, wenn --trace läuft, der
// Trace der letzten Minuten. Das Plugin legt seinen Fehlerbericht dazu und
// schreibt die ZIP-Datei; der Server liefert nur Dateinamen und Inhalt.
//
// Anonymisiert (diagnostics.bugReport.anonymize, wie #108):
// - Status: Unit-Namen des Projekts über den Anonymisierer des Servers
//   (name#N), Pfade unter einem Arbeitsbereich zu <ws>/…, andere zu <pfad>,
//   Benutzer- und Rechnername zu <benutzer> (Atlas.Text.Anonymize).
// - Protokoll: dieselben Regeln wie der Fehlerbericht, dazu Text in
//   Anführungszeichen zu <wert>.
// - Trace: Jede Zeile wird als JSON gelesen; Schlüssel, Zahlen und die Werte
//   von "jsonrpc" und "method" bleiben, jeder andere Text wird <wert>. Zeilen,
//   die kein JSON tragen, entfallen (gezählt). So bleibt sichtbar, welche
//   Anfrage wann wie lange lief, ohne Quelltext und Bezeichner.
// Zugangsdaten nie, auch nicht ohne Anonymisierung: Werte unter Schlüsseln
// wie token, password, secret, apiKey, credential werden immer <geheim>.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TServerPackageFile = record
    /// <summary>Name in der ZIP-Datei mit „/“ (server/status.json).</summary>
    Name: string;
    Content: string;
  end;

  TServerPackageInput = record
    /// <summary>Status als JSON-Text (atlas.server.status, Unit-Namen schon anonymisiert, falls gewünscht).</summary>
    StatusJson: string;
    LogLines: TArray<string>;
    /// <summary>Trace der letzten Minuten; leer, wenn --trace nicht läuft.</summary>
    TraceLines: TArray<string>;
    Tracing: Boolean;
    TraceMinutes: Integer;
    Workspaces: TArray<string>;
    Identity: TArray<string>;
    Anonymize: Boolean;
  end;

  TServerPackage = class
  public const
    /// <summary>Befehl des Servers; Argument optional {"anonymize": true, "traceMinutes": 5}.</summary>
    Command = 'atlas.server.diagnosticPackage';
    StatusName = 'server/status.json';
    LogName = 'server/protokoll.txt';
    TraceName = 'server/trace.txt';
    SecretLabel = '<geheim>';
    DefaultTraceMinutes = 5;
  public
    class function Build(const AInput: TServerPackageInput): TArray<TServerPackageFile>; static;
    /// <summary>{"files": [{"name": …, "content": …}]}; der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AFiles: TArray<TServerPackageFile>): TJSONObject; static;
    /// <summary>Eine Trace-Zeile „Datum Zeit Richtung JSON“ anonymisiert; '' wenn sie kein JSON trägt.</summary>
    class function AnonymizeTraceLine(const ALine: string): string; static;
    /// <summary>Eine Trace-Zeile ohne Zugangsdaten, sonst unverändert; Zeilen ohne JSON bleiben, wie sie sind.
    /// </summary>
    class function SecretFreeTraceLine(const ALine: string): string; static;
    /// <summary>Werte unter Schlüsseln für Zugangsdaten in AValue durch SecretLabel ersetzen; mit AAll auch jeden
    /// anderen Text außer "jsonrpc" und "method" durch &lt;wert&gt;.</summary>
    class procedure Scrub(AValue: TJSONValue; AAll: Boolean); static;
    /// <summary>Ist AKey ein Schlüssel für Zugangsdaten (token, password, secret, apiKey, credential …)?</summary>
    class function IsSecretKey(const AKey: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Anonymize;

{ TServerPackage }

class function TServerPackage.IsSecretKey(const AKey: string): Boolean;
var
  mKey: string;
begin
  mKey := LowerCase(AKey);
  Result := mKey.Contains('token') or mKey.Contains('password') or mKey.Contains('passwort') or
    mKey.Contains('secret') or mKey.Contains('apikey') or mKey.Contains('api_key') or
    mKey.Contains('credential') or mKey.Contains('authorization');
end;

/// <summary>Text, aber keine Zahl: TJSONNumber erbt von TJSONString.</summary>
function IsText(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
end;

/// <summary>Ersetzt den Wert des Paares durch einen Text; der alte wird freigegeben.</summary>
procedure ReplaceValue(APair: TJSONPair; const AText: string);
begin
  APair.JsonValue := TJSONString.Create(AText);
end;

/// <summary>Kopie von AArray mit &lt;wert&gt; statt jedem nichtleeren Text, Objekte und Arrays bereinigt.</summary>
function ScrubbedArray(AArray: TJSONArray; AAll: Boolean): TJSONArray;
var
  mItem, mCopy: TJSONValue;
begin
  Result := TJSONArray.Create;
  for mItem in AArray do
    if AAll and IsText(mItem) and (mItem.Value <> '') then
      Result.Add(TTextAnonymizer.ValueLabel)
    else
    begin
      mCopy := TJSONValue(mItem.Clone);
      if mCopy is TJSONArray then
      begin
        Result.AddElement(ScrubbedArray(TJSONArray(mCopy), AAll));
        mCopy.Free;
      end
      else
      begin
        TServerPackage.Scrub(mCopy, AAll);
        Result.AddElement(mCopy);
      end;
    end;
end;

class procedure TServerPackage.Scrub(AValue: TJSONValue; AAll: Boolean);
var
  mPair: TJSONPair;
  mItem: TJSONValue;
  mKey: string;
begin
  if AValue is TJSONObject then
    for mPair in TJSONObject(AValue) do
    begin
      mKey := mPair.JsonString.Value;
      if IsSecretKey(mKey) and not (mPair.JsonValue is TJSONNull) then
        ReplaceValue(mPair, SecretLabel)
      else if IsText(mPair.JsonValue) then
      begin
        if AAll and not SameText(mKey, 'jsonrpc') and not SameText(mKey, 'method') and
          (mPair.JsonValue.Value <> '') then
          ReplaceValue(mPair, TTextAnonymizer.ValueLabel);
      end
      else if AAll and (mPair.JsonValue is TJSONArray) then
        // Texte in Arrays lassen sich nicht an Ort und Stelle ersetzen: bereinigte Kopie einsetzen.
        mPair.JsonValue := ScrubbedArray(TJSONArray(mPair.JsonValue), AAll)
      else
        Scrub(mPair.JsonValue, AAll);
    end
  else if AValue is TJSONArray then
    for mItem in TJSONArray(AValue) do
      Scrub(mItem, AAll);
end;

/// <summary>Trace-Zeile mit bereinigtem JSON; '' ohne JSON.</summary>
function ScrubbedTraceLine(const ALine: string; AAll: Boolean): string;
var
  mStart: Integer;
  mValue: TJSONValue;
  mScrubbed: TJSONValue;
begin
  Result := '';
  mStart := Pos('{', ALine);
  if mStart = 0 then
    Exit;
  mValue := TJSONObject.ParseJSONValue(Copy(ALine, mStart, MaxInt));
  if mValue = nil then
    Exit;
  try
    if mValue is TJSONArray then
      mScrubbed := ScrubbedArray(TJSONArray(mValue), AAll)
    else
    begin
      mScrubbed := nil;
      TServerPackage.Scrub(mValue, AAll);
    end;
    if mScrubbed <> nil then
      try
        Result := Copy(ALine, 1, mStart - 1) + mScrubbed.ToJSON([]);
      finally
        mScrubbed.Free;
      end
    else
      Result := Copy(ALine, 1, mStart - 1) + mValue.ToJSON([]);
  finally
    mValue.Free;
  end;
end;

class function TServerPackage.AnonymizeTraceLine(const ALine: string): string;
begin
  Result := ScrubbedTraceLine(ALine, True);
end;

class function TServerPackage.SecretFreeTraceLine(const ALine: string): string;
begin
  Result := ScrubbedTraceLine(ALine, False);
  if Result = '' then
    Result := ALine;
end;

/// <summary>Status-JSON mit Zugangsdaten entfernt und, mit AAnonymize, Pfaden und Benutzernamen ersetzt.</summary>
function StatusText(const AInput: TServerPackageInput): string;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AInput.StatusJson);
  if mValue = nil then
    Exit('{}');
  try
    TServerPackage.Scrub(mValue, False);
    Result := mValue.Format(2);
  finally
    mValue.Free;
  end;
  if AInput.Anonymize then
    Result := TTextAnonymizer.AnonymizePaths(Result, AInput.Workspaces, AInput.Identity);
end;

class function TServerPackage.Build(const AInput: TServerPackageInput): TArray<TServerPackageFile>;
var
  mFile: TServerPackageFile;
  mBuilder: TStringBuilder;
  mLine, mText: string;
  mDropped: Integer;
begin
  Result := nil;
  mFile.Name := StatusName;
  mFile.Content := StatusText(AInput);
  Result := Result + [mFile];

  mBuilder := TStringBuilder.Create;
  try
    for mLine in AInput.LogLines do
    begin
      mText := mLine;
      if AInput.Anonymize then
        mText := TTextAnonymizer.AnonymizeLogLine(mText, AInput.Workspaces, AInput.Identity);
      mBuilder.Append(mText).Append(sLineBreak);
    end;
    mFile.Name := LogName;
    mFile.Content := mBuilder.ToString;
    Result := Result + [mFile];
  finally
    mBuilder.Free;
  end;

  if not AInput.Tracing then
    Exit;
  mBuilder := TStringBuilder.Create;
  try
    mDropped := 0;
    mBuilder.Append(Format('# Trace der letzten %d Minuten', [AInput.TraceMinutes]));
    if AInput.Anonymize then
      mBuilder.Append(', anonymisiert (Schlüssel, Zahlen und Methoden bleiben)');
    mBuilder.Append(sLineBreak);
    for mLine in AInput.TraceLines do
    begin
      if AInput.Anonymize then
        mText := AnonymizeTraceLine(mLine)
      else
        mText := SecretFreeTraceLine(mLine);
      if mText = '' then
      begin
        Inc(mDropped);
        Continue;
      end;
      mBuilder.Append(mText).Append(sLineBreak);
    end;
    if mDropped > 0 then
      mBuilder.Append(Format('# %d Zeilen ohne JSON ausgelassen', [mDropped])).Append(sLineBreak);
    mFile.Name := TraceName;
    mFile.Content := mBuilder.ToString;
    Result := Result + [mFile];
  finally
    mBuilder.Free;
  end;
end;

class function TServerPackage.ToJson(const AFiles: TArray<TServerPackageFile>): TJSONObject;
var
  mFiles: TJSONArray;
  mItem: TJSONObject;
  mFile: TServerPackageFile;
begin
  Result := TJSONObject.Create;
  mFiles := TJSONArray.Create;
  for mFile in AFiles do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mFile.Name);
    mItem.AddPair('content', mFile.Content);
    mFiles.AddElement(mItem);
  end;
  Result.AddPair('files', mFiles);
end;

end.
