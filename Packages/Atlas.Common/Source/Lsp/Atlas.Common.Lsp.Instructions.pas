unit Atlas.Common.Lsp.Instructions;

// Anweisungsdateien für KI-Assistenten (#2615): Stand und Schreiben des Abschnitts aus Atlas.Common.Rules.Instructions
// in jeder Datei aus assistants.instructions.file (relativ zum Ordner der atlas.json). Gemeinsam für die
// Kommandozeile (--write-instructions, --check-instructions) und den Befehl atlas.server.assistantInstructions des
// Plugins. Gelesen und geschrieben wird über Funktionen des Aufrufers; Kodierung, BOM und Zeilenenden einer
// vorhandenen Datei bleiben, eine neue Datei wird UTF-8 ohne BOM mit LF.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Instructions;

type
  /// <summary>Liest eine Datei; False, wenn sie fehlt.</summary>
  TLspInstructionsRead = reference to function(const AFileName: string; out ABytes: TBytes): Boolean;
  /// <summary>Schreibt eine Datei so, dass kein Leser einen halben Stand sieht; False mit Grund in AError.</summary>
  TLspInstructionsWrite = reference to function(const AFileName: string; const ABytes: TBytes;
    out AError: string): Boolean;

  /// <summary>Eine Anweisungsdatei: Stand vor dem Lauf, alter und neuer Abschnitt, ob geschrieben.</summary>
  TInstructionsFile = record
    /// <summary>Wie in atlas.json angegeben.</summary>
    FileName: string;
    State: TInstructionsState;
    /// <summary>Vorhandener Abschnitt ('' ohne), Umbrüche als #10.</summary>
    OldSection: string;
    NewSection: string;
    Written: Boolean;
    /// <summary>Grund, wenn Schreiben scheiterte; sonst ''.</summary>
    Error: string;
  end;

  TLspInstructions = class
  public const
    cCommand = 'atlas.server.assistantInstructions';
  private
    FRead: TLspInstructionsRead;
    FWrite: TLspInstructionsWrite;
    function Inspect(const ARoot, AFileName, ASection: string; AWrite: Boolean): TInstructionsFile;
  public
    constructor Create(const ARead: TLspInstructionsRead; const AWrite: TLspInstructionsWrite);
    /// <summary>Stand jeder Datei aus ASettings.AssistantsInstructionFiles unter ARoot; mit AWrite werden
    /// veraltete und fehlende Abschnitte geschrieben.</summary>
    function Run(const ARoot: string; const ASettings: TServerSettings; const ARules: TArray<IRule>;
      AWrite: Boolean): TArray<TInstructionsFile>;
    /// <summary>Abschnitt in der Sprache aus mcp.promptLanguage mit dem Katalog dieser Sprache.</summary>
    class function SectionFor(const ASettings: TServerSettings; const ARules: TArray<IRule>): string; static;
    /// <summary>Soll der Befehl schreiben? [{"write": true}]; sonst nur der Stand.</summary>
    class function WriteRequested(const AArguments: TJSONArray): Boolean; static;
    /// <summary>URI aus [{"uri": …}]; '' ohne.</summary>
    class function UriOf(const AArguments: TJSONArray): string; static;
    /// <summary>Antwort des Befehls: {"files": [{"file", "state", "old", "new", "written", "error"}], "stale": n}.
    /// "stale" zählt Dateien, deren Abschnitt nach dem Lauf nicht aktuell ist.</summary>
    class function ToJson(const AFiles: TArray<TInstructionsFile>): TJSONObject; static;
    /// <summary>Anzahl der Dateien, deren Abschnitt nach dem Lauf nicht aktuell ist.</summary>
    class function StaleCount(const AFiles: TArray<TInstructionsFile>): Integer; static;
    /// <summary>current, stale oder missing.</summary>
    class function StateName(AState: TInstructionsState): string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data;

const
  cStateNames: array[TInstructionsState] of string = ('current', 'stale', 'missing');
  cLineBreaks: array[TLineBreakStyle] of string = (#13#10, #10, #13);

/// <summary>Pfad der Datei: absolut wie angegeben, sonst unter ARoot.</summary>
function PathOf(const ARoot, AFileName: string): string;
var
  mName: string;
begin
  mName := StringReplace(StringReplace(AFileName, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
  if (ARoot = '') or (ExtractFileDrive(mName) <> '') or ((mName <> '') and (mName[1] = PathDelim)) then
  begin
    Exit(mName);
  end;
  Result := IncludeTrailingPathDelimiter(ARoot) + mName;
end;

{ TLspInstructions }

constructor TLspInstructions.Create(const ARead: TLspInstructionsRead; const AWrite: TLspInstructionsWrite);
begin
  inherited Create;
  FRead := ARead;
  FWrite := AWrite;
end;

function TLspInstructions.Inspect(const ARoot, AFileName, ASection: string; AWrite: Boolean): TInstructionsFile;
var
  mPath, mText: string;
  mBytes: TBytes;
  mFormat: TFileFormat;
begin
  Result := Default(TInstructionsFile);
  Result.FileName := AFileName;
  Result.NewSection := ASection;
  mPath := PathOf(ARoot, AFileName);
  mText := '';
  mFormat := TFileFormat.Create(TFileEncodingKind.Utf8, TLineBreakStyle.LF);
  if FRead(mPath, mBytes) then
  begin
    mText := TFileEncoding.Decode(mBytes, mFormat);
  end;
  Result.OldSection := TRuleInstructions.Extract(mText);
  Result.State := TRuleInstructions.State(mText, ASection);
  if AWrite and (Result.State <> TInstructionsState.Current) then
  begin
    mBytes := TFileEncoding.EncodeKeepingLineBreaks(TRuleInstructions.Apply(mText, ASection,
      cLineBreaks[mFormat.LineBreak]), mFormat);
    Result.Written := FWrite(mPath, mBytes, Result.Error);
  end;
end;

function TLspInstructions.Run(const ARoot: string; const ASettings: TServerSettings; const ARules: TArray<IRule>;
  AWrite: Boolean): TArray<TInstructionsFile>;
var
  mSection, mFileName: string;
begin
  Result := nil;
  mSection := SectionFor(ASettings, ARules);
  for mFileName in ASettings.AssistantsInstructionFiles do
  begin
    Result := Result + [Inspect(ARoot, mFileName, mSection, AWrite)];
  end;
end;

class function TLspInstructions.SectionFor(const ASettings: TServerSettings; const ARules: TArray<IRule>): string;
var
  mLanguage: TTextLanguage;
  mCatalog: TRuleCatalog;
begin
  mLanguage := TRuleInstructions.LanguageOf(ASettings);
  if mLanguage = TTextLanguage.English then
  begin
    Exit(TRuleInstructions.Section(ARules, ASettings, TRuleCatalog.Shared, mLanguage));
  end;
  // Der deutsche Katalog unabhängig von der Sprache der Oberfläche (TRuleCatalog.Localized folgt ihr).
  mCatalog := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
  try
    Result := TRuleInstructions.Section(ARules, ASettings, mCatalog, mLanguage);
  finally
    mCatalog.Free;
  end;
end;

/// <summary>Erstes Argument als Objekt; nil sonst.</summary>
function FirstObject(const AArguments: TJSONArray): TJSONObject;
begin
  Result := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
  begin
    Result := TJSONObject(AArguments.Items[0]);
  end;
end;

class function TLspInstructions.WriteRequested(const AArguments: TJSONArray): Boolean;
var
  mArguments: TJSONObject;
begin
  mArguments := FirstObject(AArguments);
  Result := (mArguments <> nil) and (mArguments.GetValue('write') is TJSONBool) and
    TJSONBool(mArguments.GetValue('write')).AsBoolean;
end;

class function TLspInstructions.UriOf(const AArguments: TJSONArray): string;
var
  mArguments: TJSONObject;
begin
  Result := '';
  mArguments := FirstObject(AArguments);
  if mArguments <> nil then
  begin
    Result := mArguments.GetValue<string>('uri', '');
  end;
end;

class function TLspInstructions.StaleCount(const AFiles: TArray<TInstructionsFile>): Integer;
var
  mFile: TInstructionsFile;
begin
  Result := 0;
  for mFile in AFiles do
  begin
    if (mFile.State <> TInstructionsState.Current) and not mFile.Written then
    begin
      Inc(Result);
    end;
  end;
end;

class function TLspInstructions.StateName(AState: TInstructionsState): string;
begin
  Result := cStateNames[AState];
end;

class function TLspInstructions.ToJson(const AFiles: TArray<TInstructionsFile>): TJSONObject;
var
  mFiles: TJSONArray;
  mFile: TInstructionsFile;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  mFiles := TJSONArray.Create;
  Result.AddPair('files', mFiles);
  for mFile in AFiles do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mFile.FileName);
    mItem.AddPair('state', StateName(mFile.State));
    mItem.AddPair('old', mFile.OldSection);
    mItem.AddPair('new', mFile.NewSection);
    mItem.AddPair('written', TJSONBool.Create(mFile.Written));
    mItem.AddPair('error', mFile.Error);
    mFiles.AddElement(mItem);
  end;
  Result.AddPair('stale', TJSONNumber.Create(StaleCount(AFiles)));
end;

end.
