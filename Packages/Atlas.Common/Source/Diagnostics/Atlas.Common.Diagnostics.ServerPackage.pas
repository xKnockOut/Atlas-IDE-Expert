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
//   Anführungszeichen zu <wert>; gekennzeichnete Namen, Pfade und fremder
//   Text (Atlas.Text.LogMarks, #1478) werden ersetzt. Die erste Zeile sagt,
//   ob das Protokoll anonymisiert ist oder Klarnamen enthält.
// - Trace: Jede Zeile wird als JSON gelesen; Schlüssel, Zahlen und die Werte
//   von "jsonrpc" und "method" bleiben, jeder andere Text wird <wert>. Zeilen,
//   die kein JSON tragen, entfallen (gezählt). So bleibt sichtbar, welche
//   Anfrage wann wie lange lief, ohne Quelltext und Bezeichner.
// - Aufrufstatistik der MCP-Prozesse am selben Ordner (#2611, Abschnitt mcp ihrer Statusdateien): Argumente
//   fehlgeschlagener Aufrufe sind gekennzeichnet (Atlas.Text.LogMarks) und werden wie im Protokoll ersetzt,
//   Pfade wie im Status.
// Zugangsdaten nie, auch nicht ohne Anonymisierung: Werte unter Schlüsseln
// wie token, password, secret, apiKey, credential werden immer <geheim>.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.StatusFile;

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
    /// <summary>Abschnitte mcp der MCP-Prozesse an den Arbeitsbereichen als JSON-Text (McpSections).</summary>
    McpStatistics: TArray<string>;
  end;

  TServerPackage = class
  public const
    /// <summary>Befehl des Servers; Argument optional {"anonymize": true, "traceMinutes": 5}.</summary>
    cCommand = 'atlas.server.diagnosticPackage';
    cStatusName = 'server/status.json';
    cLogName = 'server/protokoll.txt';
    cTraceName = 'server/trace.txt';
    /// <summary>Aufrufstatistik eines MCP-Prozesses; %d zählt ab 1.</summary>
    cMcpName = 'server/mcp-%d.json';
    cSecretLabel = '<geheim>';
    cDefaultTraceMinutes = 5;
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
    /// <summary>Abschnitte mcp der MCP-Prozesse in AEntries, deren Ordner zu einem von AWorkspaces gehört.</summary>
    class function McpSections(const AEntries: TArray<TServerStatusEntry>; const AWorkspaces: TArray<string>):
      TArray<string>; static;
    /// <summary>Wie McpSections über die Statusdateien in AStatusRoot.</summary>
    class function McpSectionsIn(const AStatusRoot: string; const AWorkspaces: TArray<string>; ANow: TDateTime):
      TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Anonymize,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TServerPackageText = (SessionLogAnonymized, SessionLogWithRealNames, TraceOfTheLastMinutes,
    AnonymizedKeysNumbersAndMethods, LinesWithoutJSONLeftOut);

const
  cTexts: array[TServerPackageText] of TAtlasText = (
    (De: '# Protokoll der Sitzung, anonymisiert'; En: '# Session log, anonymized'),
    (De: '# Protokoll der Sitzung mit Klarnamen (ausdrücklich gewählt)';
     En: '# Session log with real names (explicitly chosen)'),
    (De: '# Trace der letzten %d Minuten'; En: '# Trace of the last %d minutes'),
    (De: ', anonymisiert (Schlüssel, Zahlen und Methoden bleiben)';
     En: ', anonymized (keys, numbers and methods remain)'),
    (De: '# %d Zeilen ohne JSON ausgelassen'; En: '# %d lines without JSON left out'));

{$SCOPEDENUMS OFF}

{ TServerPackage }

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
  begin
    if AAll and IsText(mItem) and (mItem.Value <> '') then
    begin
      Result.Add(TTextAnonymizer.cValueLabel);
    end
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
end;

/// <summary>Ersetzt einen Textwert im Paar APair durch eine Marke, wenn AAll gilt und der Schlüssel kein
/// Protokollfeld (jsonrpc, method) ist.</summary>
procedure ScrubText(APair: TJSONPair; AAll: Boolean);
var
  mKey: string;
begin
  mKey := APair.JsonString.Value;
  if AAll and not SameText(mKey, 'jsonrpc') and not SameText(mKey, 'method') and (APair.JsonValue.Value <> '') then
  begin
    ReplaceValue(APair, TTextAnonymizer.cValueLabel);
  end;
end;

/// <summary>Bereinigt den Wert eines Paars: Geheimnisse immer, mit AAll auch alle Texte.</summary>
procedure ScrubPair(APair: TJSONPair; AAll: Boolean);
begin
  if TServerPackage.IsSecretKey(APair.JsonString.Value) and not (APair.JsonValue is TJSONNull) then
  begin
    ReplaceValue(APair, TServerPackage.cSecretLabel);
  end
  else if IsText(APair.JsonValue) then
  begin
    ScrubText(APair, AAll);
  end
  else if AAll and (APair.JsonValue is TJSONArray) then
  begin
    // Texte in Arrays lassen sich nicht an Ort und Stelle ersetzen: bereinigte Kopie einsetzen.
    APair.JsonValue := ScrubbedArray(TJSONArray(APair.JsonValue), AAll);
  end
  else
  begin
    TServerPackage.Scrub(APair.JsonValue, AAll);
  end;
end;

class procedure TServerPackage.Scrub(AValue: TJSONValue; AAll: Boolean);
var
  mPair: TJSONPair;
  mItem: TJSONValue;
begin
  if AValue is TJSONObject then
  begin
    for mPair in TJSONObject(AValue) do
    begin
      ScrubPair(mPair, AAll);
    end;
  end
  else if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      Scrub(mItem, AAll);
    end;
  end;
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
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(Copy(ALine, mStart, MaxInt));
  if mValue = nil then
  begin
    Exit;
  end;
  try
    if mValue is TJSONArray then
    begin
      mScrubbed := ScrubbedArray(TJSONArray(mValue), AAll);
    end
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
    begin
      Result := Copy(ALine, 1, mStart - 1) + mValue.ToJSON([]);
    end;
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
  begin
    Result := ALine;
  end;
end;

/// <summary>Status-JSON mit Zugangsdaten entfernt und, mit AAnonymize, Pfaden und Benutzernamen ersetzt.</summary>
function StatusText(const AInput: TServerPackageInput): string;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AInput.StatusJson);
  if mValue = nil then
  begin
    Exit('{}');
  end;
  try
    TServerPackage.Scrub(mValue, False);
    Result := mValue.Format(2);
  finally
    mValue.Free;
  end;
  if AInput.Anonymize then
  begin
    Result := TTextAnonymizer.AnonymizePaths(Result, AInput.Workspaces, AInput.Identity);
  end;
end;

/// <summary>Protokollzeilen, mit AAnonymize ohne Pfade und Namen.</summary>
function LogText(const AInput: TServerPackageInput): string;
var
  mBuilder: TStringBuilder;
  mLine, mText: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    if AInput.Anonymize then
    begin
      mBuilder.Append(cTexts[TServerPackageText.SessionLogAnonymized].Text).Append(sLineBreak);
    end
    else
    begin
      mBuilder.Append(cTexts[TServerPackageText.SessionLogWithRealNames].Text).Append(sLineBreak);
    end;
    for mLine in AInput.LogLines do
    begin
      if AInput.Anonymize then
      begin
        mText := TTextAnonymizer.AnonymizeLogLine(mLine, AInput.Workspaces, AInput.Identity);
      end
      else
      begin
        mText := TLogMarks.Plain(mLine);
      end;
      mBuilder.Append(mText).Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Trace-Zeilen ohne Geheimnisse, mit AAnonymize auch ohne Texte; Zeilen ohne JSON fallen weg.</summary>
function TraceText(const AInput: TServerPackageInput): string;
var
  mBuilder: TStringBuilder;
  mLine, mText: string;
  mDropped: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mDropped := 0;
    mBuilder.Append(cTexts[TServerPackageText.TraceOfTheLastMinutes].Fmt([AInput.TraceMinutes]));
    if AInput.Anonymize then
    begin
      mBuilder.Append(cTexts[TServerPackageText.AnonymizedKeysNumbersAndMethods].Text);
    end;
    mBuilder.Append(sLineBreak);
    for mLine in AInput.TraceLines do
    begin
      mText := ScrubbedTraceLine(mLine, AInput.Anonymize);
      if (mText = '') and not AInput.Anonymize then
      begin
        mText := mLine;
      end;
      if mText = '' then
      begin
        Inc(mDropped);
      end
      else
      begin
        mBuilder.Append(mText).Append(sLineBreak);
      end;
    end;
    if mDropped > 0 then
    begin
      mBuilder.Append(cTexts[TServerPackageText.LinesWithoutJSONLeftOut].Fmt([mDropped])).Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function PackageFile(const AName, AContent: string): TServerPackageFile;
begin
  Result.Name := AName;
  Result.Content := AContent;
end;

/// <summary>Ein Text der Aufrufstatistik: mit AAnonymize gekennzeichnete Werte, Pfade und Benutzernamen ersetzt,
/// sonst die Werte im Klartext.</summary>
function McpValue(const AText: string; const AInput: TServerPackageInput): string;
begin
  if AInput.Anonymize then
  begin
    Exit(TTextAnonymizer.AnonymizePaths(AText, AInput.Workspaces, AInput.Identity));
  end;
  Result := TLogMarks.Plain(AText);
end;

/// <summary>Ersetzt jeden Text in AValue (Objekte, auch verschachtelt) durch McpValue. Vor dem Formatieren, damit
/// die Kennzeichen nicht als \u-Folgen im JSON-Text stehen.</summary>
procedure MapMcpTexts(AValue: TJSONValue; const AInput: TServerPackageInput);
var
  mPair: TJSONPair;
  mItem: TJSONValue;
begin
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      MapMcpTexts(mItem, AInput);
    end;
    Exit;
  end;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(AValue) do
  begin
    if IsText(mPair.JsonValue) then
    begin
      ReplaceValue(mPair, McpValue(mPair.JsonValue.Value, AInput));
    end
    else
    begin
      MapMcpTexts(mPair.JsonValue, AInput);
    end;
  end;
end;

/// <summary>Aufrufstatistik eines MCP-Prozesses ohne Zugangsdaten, Texte nach McpValue.</summary>
function McpText(const AInput: TServerPackageInput; const AJson: string): string;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue = nil then
  begin
    Exit('{}');
  end;
  try
    TServerPackage.Scrub(mValue, False);
    MapMcpTexts(mValue, AInput);
    Result := mValue.Format(2);
  finally
    mValue.Free;
  end;
end;

class function TServerPackage.Build(const AInput: TServerPackageInput): TArray<TServerPackageFile>;
var
  mIndex: Integer;
begin
  Result := [PackageFile(cStatusName, StatusText(AInput)), PackageFile(cLogName, LogText(AInput))];
  if AInput.Tracing then
  begin
    Result := Result + [PackageFile(cTraceName, TraceText(AInput))];
  end;
  for mIndex := 0 to High(AInput.McpStatistics) do
  begin
    Result := Result + [PackageFile(Format(cMcpName, [mIndex + 1]), McpText(AInput, AInput.McpStatistics[mIndex]))];
  end;
end;

class function TServerPackage.McpSections(const AEntries: TArray<TServerStatusEntry>;
  const AWorkspaces: TArray<string>): TArray<string>;
var
  mEntry: TServerStatusEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if (mEntry.KindOrLsp = TServerStatusEntry.cKindMcp) and (mEntry.Mcp <> '') and
      TServerStatusFile.Matches(AWorkspaces, mEntry.Target) then
    begin
      Result := Result + [mEntry.Mcp];
    end;
  end;
end;

class function TServerPackage.McpSectionsIn(const AStatusRoot: string; const AWorkspaces: TArray<string>;
  ANow: TDateTime): TArray<string>;
begin
  Result := McpSections(TServerStatusFile.List(AStatusRoot, ANow, nil), AWorkspaces);
end;

class function TServerPackage.IsSecretKey(const AKey: string): Boolean;
var
  mKey: string;
begin
  mKey := LowerCase(AKey);
  Result := mKey.Contains('token') or mKey.Contains('password') or mKey.Contains('passwort') or
    mKey.Contains('secret') or mKey.Contains('apikey') or mKey.Contains('api_key') or
    mKey.Contains('credential') or mKey.Contains('authorization');
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Diagnostics.ServerPackage', cTexts);

end.
