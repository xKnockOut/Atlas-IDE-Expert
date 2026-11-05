unit Atlas.Common.Rules.Output;

// Ausgabe des Kommandozeilen-Linters als Text, JSON oder SARIF 2.1.0 und
// Exit-Code nach --fail-on. Positionen in Text und SARIF beginnen bei 1, im
// JSON wie im LSP bei 0.
//
// SARIF für GitHub Code Scanning: Pfade relativ zur Quellwurzel mit
// uriBaseId "%SRCROOT%" (die Wurzel steht in run.originalUriBaseIds),
// Dateien außerhalb als absoluter file:-URI. message.text ist der englische
// Katalogname der Regel ohne Konfidenz-Zusatz; die Konfidenz steht in
// properties.confidence, die deutsche Meldung des Treffers in properties.detail.
// Im JSON steht die Konfidenz ebenso in properties.confidence und zusätzlich
// als "confidence" neben "severity" (älteres Feld, bleibt erhalten).
//
// Baseline (#97): Trägt TCheckedFile.Marks die Treffer mit Fingerabdrücken,
// bekommt jedes Ergebnis partialFingerprints mit dem Baseline-Fingerabdruck
// ("atlasBaseline/v1": Regel, Routine und Zeile) und dem Kontext
// ("atlasContext/v1"), je mit ":n" für den n-ten gleichen Treffer der Datei.
// So erkennt Code Scanning verschobene Treffer wieder. Mit Baseline steht
// zusätzlich baselineState "new", "unchanged" oder "absent" am Ergebnis;
// unveränderte Treffer tragen eine externe Unterdrückung (suppressions, kind
// "external"), nicht mehr gefundene stehen ohne Region mit der Datei da. Text,
// JSON und der Exit-Code sehen weiter nur die neuen Treffer (Findings).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker;

type
  TFindingsFormat = (Text, Json, Sarif);

  /// <summary>Ab welchem Schweregrad der Linter mit Exit-Code 1 endet (--fail-on).</summary>
  TFailOn = (Error, Warning, Never);

  /// <summary>Prüft, ob es eine Datei oder einen Ordner gibt.</summary>
  TPathExists = reference to function(const APath: string): Boolean;

  TFindingsOutput = class
  public const
    ExitClean = 0;
    /// <summary>Mindestens ein Treffer ab dem Schweregrad aus --fail-on.</summary>
    ExitFindings = 1;
    /// <summary>Aufruf- oder Lesefehler, vergibt der Aufrufer.</summary>
    ExitFailure = 3;
    SourceRootId = '%SRCROOT%';
  public
    class function TryParseFormat(const AText: string; out AFormat: TFindingsFormat): Boolean; static;
    class function TryParseFailOn(const AText: string; out AFailOn: TFailOn): Boolean; static;
    /// <summary>ASourceRoot: Quellwurzel für SARIF; '' = Pfade aus TCheckedFile.Path ohne uriBaseId.</summary>
    class function Render(const AFiles: TArray<TCheckedFile>; AFormat: TFindingsFormat;
      const ARules: TArray<TRuleDescriptor>; const ASourceRoot: string): string; overload; static;
    /// <summary>Wie oben ohne Quellwurzel (ASourceRoot = '').</summary>
    class function Render(const AFiles: TArray<TCheckedFile>; AFormat: TFindingsFormat;
      const ARules: TArray<TRuleDescriptor>): string; overload; static;
    /// <summary>1, wenn ein Treffer AFailOn erreicht (Standard: ein Fehler), sonst 0.</summary>
    class function ExitCode(const AFiles: TArray<TCheckedFile>; AFailOn: TFailOn): Integer; overload; static;
    /// <summary>Wie oben mit AFailOn = Error.</summary>
    class function ExitCode(const AFiles: TArray<TCheckedFile>): Integer; overload; static;
    /// <summary>Nächster Ordner ab AStart aufwärts, der ".git" enthält; '' ohne.</summary>
    class function FindGitRoot(const AStart: string; const AExists: TPathExists): string; static;
    /// <summary>
    ///   URI für SARIF: relativ zu ASourceRoot (ARelative = True) oder, außerhalb
    ///   der Wurzel, absolut als file:-URI. Prozent-kodiert wie RFC 3986.
    /// </summary>
    class function SarifUri(const AFullPath, ASourceRoot: string; out ARelative: Boolean): string; static;
    class function FileUri(const AFullPath: string): string; static;
    class function SeverityName(ASeverity: TRuleSeverity): string; static;
    class function JsonString(const AText: string): string; static;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Product.Version,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Rules.Baseline,
  Atlas.Text.Json,
  System.Generics.Collections,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TOutputText = (FindingLine, Summary);

const
  cTexts: array[TOutputText] of TAtlasText = (
    (De: '%s(%d,%d): %s %s [Konfidenz %s]: %s'; En: '%s(%d,%d): %s %s [confidence %s]: %s'),
    (De: '%d Treffer in %d von %d Dateien'; En: '%d findings in %d of %d files'));

{$SCOPEDENUMS OFF}

class function TFindingsOutput.TryParseFormat(const AText: string; out AFormat: TFindingsFormat): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(AText));
  Result := True;
  if Value = 'text' then
  begin
    AFormat := TFindingsFormat.Text;
  end
  else if Value = 'json' then
  begin
    AFormat := TFindingsFormat.Json;
  end
  else if Value = 'sarif' then
  begin
    AFormat := TFindingsFormat.Sarif;
  end
  else
  begin
    AFormat := TFindingsFormat.Text;
    Result := False;
  end;
end;

class function TFindingsOutput.SeverityName(ASeverity: TRuleSeverity): string;
begin
  case ASeverity of
    TRuleSeverity.Error:
      Result := 'error';
    TRuleSeverity.Warning:
      Result := 'warning';
    TRuleSeverity.Information:
      Result := 'info';
  else
    Result := 'hint';
  end;
end;

function SarifLevel(ASeverity: TRuleSeverity): string;
begin
  case ASeverity of
    TRuleSeverity.Error:
      Result := 'error';
    TRuleSeverity.Warning:
      Result := 'warning';
  else
    Result := 'note';
  end;
end;

class function TFindingsOutput.JsonString(const AText: string): string;
begin
  Result := TJsonText.Quote(AText);
end;

class function TFindingsOutput.TryParseFailOn(const AText: string; out AFailOn: TFailOn): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(AText));
  Result := True;
  if Value = 'error' then
  begin
    AFailOn := TFailOn.Error;
  end
  else if Value = 'warning' then
  begin
    AFailOn := TFailOn.Warning;
  end
  else if Value = 'never' then
  begin
    AFailOn := TFailOn.Never;
  end
  else
  begin
    AFailOn := TFailOn.Error;
    Result := False;
  end;
end;

function UriPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

/// <summary>Prozent-Kodierung nach RFC 3986; "/" und ":" (Laufwerk) bleiben.</summary>
function EncodeUri(const APath: string): string;
var
  Bytes: TBytes;
  B: Byte;
begin
  Result := '';
  Bytes := TEncoding.UTF8.GetBytes(APath);
  for B in Bytes do
  begin
    if (B in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9')]) or
      (B in [Ord('-'), Ord('.'), Ord('_'), Ord('~'), Ord('/'), Ord(':')]) then
    begin
      Result := Result + Chr(B);
    end
    else
    begin
      Result := Result + '%' + IntToHex(B, 2);
    end;
  end;
end;

class function TFindingsOutput.FileUri(const AFullPath: string): string;
var
  Path: string;
begin
  Path := UriPath(AFullPath);
  // UNC-Pfad \\server\freigabe wird zu file://server/freigabe.
  if Copy(Path, 1, 2) = '//' then
  begin
    Exit('file:' + EncodeUri(Path));
  end;
  if Copy(Path, 1, 1) <> '/' then
  begin
    Path := '/' + Path;
  end;
  Result := 'file://' + EncodeUri(Path);
end;

class function TFindingsOutput.SarifUri(const AFullPath, ASourceRoot: string; out ARelative: Boolean): string;
var
  Path, Root: string;
begin
  Path := UriPath(AFullPath);
  Root := UriPath(ASourceRoot);
  if (Root <> '') and (Root[Length(Root)] <> '/') then
  begin
    Root := Root + '/';
  end;
  // Windows-Pfade unterscheiden keine Groß- und Kleinschreibung.
  ARelative := (Root <> '') and (Length(Path) > Length(Root)) and SameText(Copy(Path, 1, Length(Root)), Root);
  if ARelative then
  begin
    Result := EncodeUri(Copy(Path, Length(Root) + 1, MaxInt));
  end
  else
  begin
    Result := FileUri(AFullPath);
  end;
end;

class function TFindingsOutput.FindGitRoot(const AStart: string; const AExists: TPathExists): string;
var
  Dir, Parent: string;
begin
  Dir := ExcludeTrailingPathDelimiter(AStart);
  while Dir <> '' do
  begin
    if AExists(IncludeTrailingPathDelimiter(Dir) + '.git') then
    begin
      Exit(Dir);
    end;
    Parent := ExtractFileDir(Dir);
    if (Parent = Dir) or (Parent = '') then
    begin
      Break;
    end;
    Dir := Parent;
  end;
  Result := '';
end;

function RenderText(const AFiles: TArray<TCheckedFile>): string;
var
  Builder: TStringBuilder;
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
  Count, FilesWithFindings: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Count := 0;
    FilesWithFindings := 0;
    for CheckedFile in AFiles do
    begin
      if Length(CheckedFile.Findings) > 0 then
      begin
        Inc(FilesWithFindings);
      end;
      for Finding in CheckedFile.Findings do
      begin
        Inc(Count);
        // Konfidenz als eigene Spalte vor der Meldung, nicht im Meldungstext (#144).
        Builder.Append(cTexts[TOutputText.FindingLine].Fmt([CheckedFile.Path,
          Finding.Range.StartPos.Line + 1, Finding.Range.StartPos.Character + 1,
          TFindingsOutput.SeverityName(Finding.Severity), Finding.RuleId, ConfidenceText(Finding.Confidence),
          Finding.Message]));
        Builder.Append(sLineBreak);
      end;
    end;
    Builder.Append(cTexts[TOutputText.Summary].Fmt([Count, FilesWithFindings, Length(AFiles)]));
    Builder.Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function JsonPosition(const APos: TTextPosition): string;
begin
  Result := Format('{"line":%d,"character":%d}', [APos.Line, APos.Character]);
end;

function RenderJson(const AFiles: TArray<TCheckedFile>): string;
var
  Builder: TStringBuilder;
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
  FirstFile, FirstFinding: Boolean;
  Counts: array[TRuleSeverity] of Integer;
  Severity: TRuleSeverity;
begin
  for Severity := Low(TRuleSeverity) to High(TRuleSeverity) do
  begin
    Counts[Severity] := 0;
  end;
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"files":[');
    FirstFile := True;
    for CheckedFile in AFiles do
    begin
      if not FirstFile then
      begin
        Builder.Append(',');
      end;
      FirstFile := False;
      Builder.Append('{"path":').Append(TFindingsOutput.JsonString(UriPath(CheckedFile.Path))).Append(',"findings":[');
      FirstFinding := True;
      for Finding in CheckedFile.Findings do
      begin
        Inc(Counts[Finding.Severity]);
        if not FirstFinding then
        begin
          Builder.Append(',');
        end;
        FirstFinding := False;
        Builder.Append('{"rule":').Append(TFindingsOutput.JsonString(Finding.RuleId));
        Builder.Append(',"severity":').Append(TFindingsOutput.JsonString(TFindingsOutput.SeverityName(Finding.Severity)));
        Builder.Append(',"confidence":').Append(TFindingsOutput.JsonString(ConfidenceName(Finding.Confidence)));
        Builder.Append(',"message":').Append(TFindingsOutput.JsonString(Finding.Message));
        Builder.Append(',"range":{"start":').Append(JsonPosition(Finding.Range.StartPos));
        Builder.Append(',"end":').Append(JsonPosition(Finding.Range.EndPos)).Append('}');
        // Wie in SARIF unter properties (#144); "confidence" oben bleibt für bestehende Auswertungen.
        Builder.Append(',"properties":{"confidence":').Append(
          TFindingsOutput.JsonString(ConfidenceName(Finding.Confidence))).Append('}}');
      end;
      Builder.Append(']}');
    end;
    Builder.Append(Format('],"summary":{"files":%d,"errors":%d,"warnings":%d,"information":%d,"hints":%d}}',
      [Length(AFiles), Counts[TRuleSeverity.Error], Counts[TRuleSeverity.Warning],
      Counts[TRuleSeverity.Information], Counts[TRuleSeverity.Hint]]));
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

/// <summary>artifactLocation ohne die schließende Klammer.</summary>
function SarifLocation(const ACheckedFile: TCheckedFile; const ASourceRoot: string): string;
var
  Relative: Boolean;
  Uri: string;
begin
  if (ASourceRoot = '') or (ACheckedFile.FullPath = '') then
  begin
    Uri := EncodeUri(UriPath(ACheckedFile.Path));
    Relative := ASourceRoot <> '';
  end
  else
  begin
    Uri := TFindingsOutput.SarifUri(ACheckedFile.FullPath, ASourceRoot, Relative);
  end;
  Result := '{"uri":' + TFindingsOutput.JsonString(Uri);
  if Relative then
  begin
    Result := Result + ',"uriBaseId":' + TFindingsOutput.JsonString(TFindingsOutput.SourceRootId);
  end;
end;

/// <summary>Englischer Katalogname der Regel; ohne Katalogeintrag die Meldung ohne Konfidenz-Zusatz.</summary>
function SarifMessage(ACatalog: TRuleCatalog; const AFinding: TRuleFinding): string;
var
  Entry: TRuleCatalogEntry;
begin
  if ACatalog.TryFind(AFinding.RuleId, Entry) and (Entry.Name <> '') then
  begin
    Result := Entry.Name;
  end
  else
  begin
    Result := AFinding.Message;
  end;
end;

function BaselineStateName(AState: TBaselineState): string;
begin
  case AState of
    TBaselineState.New:
      Result := 'new';
    TBaselineState.Unchanged:
      Result := 'unchanged';
    TBaselineState.Absent:
      Result := 'absent';
  else
    Result := '';
  end;
end;

/// <summary>AKey mit ":n" für das n-te Vorkommen in ACounts.</summary>
function Occurrence(ACounts: TDictionary<string, Integer>; const AKey: string): string;
var
  Count: Integer;
begin
  if not ACounts.TryGetValue(AKey, Count) then
  begin
    Count := 0;
  end;
  Inc(Count);
  ACounts.AddOrSetValue(AKey, Count);
  Result := AKey + ':' + IntToStr(Count);
end;

/// <summary>Standard-Schweregrad der Regel ARuleId aus ARules; Hinweis, wenn sie fehlt.</summary>
function DefaultSeverityOf(const ARules: TArray<TRuleDescriptor>; const ARuleId: string): TRuleSeverity;
var
  Rule: TRuleDescriptor;
begin
  for Rule in ARules do
  begin
    if SameText(Rule.Id, ARuleId) then
    begin
      Exit(Rule.DefaultSeverity);
    end;
  end;
  Result := TRuleSeverity.Hint;
end;

type
  /// <summary>Schreibt einen SARIF-Lauf: Regeln, Wurzel und Ergebnisse. Immer der englische Katalog: stabile Texte
  /// für GitHub Code Scanning.</summary>
  TSarifWriter = class
  private
    FBuilder: TStringBuilder;
    FCatalog: TRuleCatalog;
    FRules: TArray<TRuleDescriptor>;
    FSourceRoot: string;
    FFirst: Boolean;
    FLineCounts: TDictionary<string, Integer>;
    FContextCounts: TDictionary<string, Integer>;
    procedure Separate;
    procedure AppendRule(const ARule: TRuleDescriptor);
    procedure AppendRegion(const ARange: TTextRange);
    procedure AppendMark(const ACheckedFile: TCheckedFile; const AMark: TBaselineMark);
    procedure AppendFinding(const ACheckedFile: TCheckedFile; const AFinding: TRuleFinding);
    procedure AppendFile(const ACheckedFile: TCheckedFile);
  public
    constructor Create(const ARules: TArray<TRuleDescriptor>; const ASourceRoot: string);
    destructor Destroy; override;
    function Render(const AFiles: TArray<TCheckedFile>): string;
  end;

constructor TSarifWriter.Create(const ARules: TArray<TRuleDescriptor>; const ASourceRoot: string);
begin
  inherited Create;
  FRules := ARules;
  FSourceRoot := ASourceRoot;
  FCatalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  FBuilder := TStringBuilder.Create;
  FLineCounts := TDictionary<string, Integer>.Create;
  FContextCounts := TDictionary<string, Integer>.Create;
end;

destructor TSarifWriter.Destroy;
begin
  FContextCounts.Free;
  FLineCounts.Free;
  FBuilder.Free;
  FCatalog.Free;
  inherited;
end;

/// <summary>Komma vor jedem Element außer dem ersten einer Liste.</summary>
procedure TSarifWriter.Separate;
begin
  if not FFirst then
  begin
    FBuilder.Append(',');
  end;
  FFirst := False;
end;

procedure TSarifWriter.AppendRule(const ARule: TRuleDescriptor);
var
  mEntry: TRuleCatalogEntry;
begin
  Separate;
  FBuilder.Append('{"id":').Append(TFindingsOutput.JsonString(ARule.Id));
  if FCatalog.TryFind(ARule.Id, mEntry) then
  begin
    FBuilder.Append(',"name":').Append(TFindingsOutput.JsonString(mEntry.Name));
    FBuilder.Append(',"shortDescription":{"text":').Append(TFindingsOutput.JsonString(mEntry.Name));
    FBuilder.Append('},"fullDescription":{"text":').Append(TFindingsOutput.JsonString(mEntry.Description));
    FBuilder.Append('},"properties":{"tags":[').Append(TFindingsOutput.JsonString(
      TRuleCatalog.CategoryName(mEntry.Category)));
    FBuilder.Append(']}');
  end
  else
  begin
    FBuilder.Append(',"shortDescription":{"text":').Append(TFindingsOutput.JsonString(ARule.Description)).Append('}');
  end;
  FBuilder.Append(',"helpUri":').Append(TFindingsOutput.JsonString(TRuleCatalog.HelpUri(ARule.Id)));
  FBuilder.Append(',"defaultConfiguration":{"level":').Append(TFindingsOutput.JsonString(
    SarifLevel(ARule.DefaultSeverity)));
  FBuilder.Append('}}');
end;

procedure TSarifWriter.AppendRegion(const ARange: TTextRange);
begin
  FBuilder.Append(Format(',"region":{"startLine":%d,"startColumn":%d,"endLine":%d,"endColumn":%d}',
    [ARange.StartPos.Line + 1, ARange.StartPos.Character + 1, ARange.EndPos.Line + 1, ARange.EndPos.Character + 1]));
end;

/// <summary>Ein Ergebnis mit Fingerabdrücken und Zustand gegenüber der Baseline.</summary>
procedure TSarifWriter.AppendMark(const ACheckedFile: TCheckedFile; const AMark: TBaselineMark);
var
  mFinding: TRuleFinding;
  mSeverity: TRuleSeverity;
begin
  mFinding := AMark.Finding;
  // Nicht mehr gefunden: Schweregrad aus dem Aufrufer, sonst der Standard der Regel.
  mSeverity := mFinding.Severity;
  if (AMark.State = TBaselineState.Absent) and (mFinding.Severity in [TRuleSeverity.Default, TRuleSeverity.Off]) then
  begin
    mSeverity := DefaultSeverityOf(FRules, mFinding.RuleId);
  end;
  FBuilder.Append('{"ruleId":').Append(TFindingsOutput.JsonString(mFinding.RuleId));
  FBuilder.Append(',"level":').Append(TFindingsOutput.JsonString(SarifLevel(mSeverity)));
  FBuilder.Append(',"message":{"text":').Append(TFindingsOutput.JsonString(SarifMessage(FCatalog, mFinding)));
  FBuilder.Append('},"locations":[{"physicalLocation":{"artifactLocation":');
  FBuilder.Append(SarifLocation(ACheckedFile, FSourceRoot)).Append('}');
  // Nicht mehr gefunden: keine Stelle im aktuellen Text.
  if AMark.State <> TBaselineState.Absent then
  begin
    AppendRegion(mFinding.Range);
  end;
  FBuilder.Append('}}]');
  FBuilder.Append(',"partialFingerprints":{"atlasBaseline/v1":');
  FBuilder.Append(TFindingsOutput.JsonString(Occurrence(FLineCounts, TRuleBaseline.SarifFingerprint(AMark))));
  FBuilder.Append(',"atlasContext/v1":').Append(TFindingsOutput.JsonString(Occurrence(FContextCounts,
    AMark.Context))).Append('}');
  if AMark.State <> TBaselineState.None then
  begin
    FBuilder.Append(',"baselineState":').Append(TFindingsOutput.JsonString(BaselineStateName(AMark.State)));
  end;
  if AMark.State = TBaselineState.Unchanged then
  begin
    FBuilder.Append(',"suppressions":[{"kind":"external","justification":').Append(
      TFindingsOutput.JsonString(BaselineFileName)).Append('}]');
  end;
  FBuilder.Append(',"properties":{"confidence":').Append(TFindingsOutput.JsonString(
    ConfidenceName(mFinding.Confidence)));
  FBuilder.Append(',"detail":').Append(TFindingsOutput.JsonString(mFinding.Message));
  if AMark.Routine <> '' then
  begin
    FBuilder.Append(',"routine":').Append(TFindingsOutput.JsonString(AMark.Routine));
  end;
  FBuilder.Append('}}');
end;

procedure TSarifWriter.AppendFinding(const ACheckedFile: TCheckedFile; const AFinding: TRuleFinding);
begin
  FBuilder.Append('{"ruleId":').Append(TFindingsOutput.JsonString(AFinding.RuleId));
  FBuilder.Append(',"level":').Append(TFindingsOutput.JsonString(SarifLevel(AFinding.Severity)));
  FBuilder.Append(',"message":{"text":').Append(TFindingsOutput.JsonString(SarifMessage(FCatalog, AFinding)));
  FBuilder.Append('},"locations":[{"physicalLocation":{"artifactLocation":');
  FBuilder.Append(SarifLocation(ACheckedFile, FSourceRoot)).Append('}');
  AppendRegion(AFinding.Range);
  FBuilder.Append('}}]');
  FBuilder.Append(',"properties":{"confidence":').Append(TFindingsOutput.JsonString(
    ConfidenceName(AFinding.Confidence)));
  FBuilder.Append(',"detail":').Append(TFindingsOutput.JsonString(AFinding.Message));
  FBuilder.Append('}}');
end;

/// <summary>Ergebnisse einer Datei: mit Baseline die Marken, sonst die Treffer.</summary>
procedure TSarifWriter.AppendFile(const ACheckedFile: TCheckedFile);
var
  mMark: TBaselineMark;
  mFinding: TRuleFinding;
begin
  // Zähler je Datei: gleiche Treffer derselben Datei unterscheidet ":n".
  FLineCounts.Clear;
  FContextCounts.Clear;
  for mMark in ACheckedFile.Marks do
  begin
    Separate;
    AppendMark(ACheckedFile, mMark);
  end;
  if Length(ACheckedFile.Marks) > 0 then
  begin
    Exit;
  end;
  for mFinding in ACheckedFile.Findings do
  begin
    Separate;
    AppendFinding(ACheckedFile, mFinding);
  end;
end;

function TSarifWriter.Render(const AFiles: TArray<TCheckedFile>): string;
var
  mRule: TRuleDescriptor;
  mCheckedFile: TCheckedFile;
  mRootUri: string;
begin
  FBuilder.Append('{"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":[{');
  FBuilder.Append('"tool":{"driver":{"name":').Append(TFindingsOutput.JsonString(TProductVersion.Name));
  FBuilder.Append(',"version":').Append(TFindingsOutput.JsonString(TProductVersion.Version));
  FBuilder.Append(',"informationUri":"https://github.com/xKnockOut/Atlas-IDE-Expert","rules":[');
  FFirst := True;
  for mRule in FRules do
  begin
    AppendRule(mRule);
  end;
  FBuilder.Append(']}}');
  if FSourceRoot <> '' then
  begin
    mRootUri := TFindingsOutput.FileUri(FSourceRoot);
    if mRootUri[Length(mRootUri)] <> '/' then
    begin
      mRootUri := mRootUri + '/';
    end;
    FBuilder.Append(',"originalUriBaseIds":{').Append(TFindingsOutput.JsonString(TFindingsOutput.SourceRootId));
    FBuilder.Append(':{"uri":').Append(TFindingsOutput.JsonString(mRootUri)).Append('}}');
  end;
  FBuilder.Append(',"results":[');
  FFirst := True;
  for mCheckedFile in AFiles do
  begin
    AppendFile(mCheckedFile);
  end;
  FBuilder.Append(']}]}');
  Result := FBuilder.ToString;
end;

function RenderSarif(const AFiles: TArray<TCheckedFile>; const ARules: TArray<TRuleDescriptor>;
  const ASourceRoot: string): string;
var
  mWriter: TSarifWriter;
begin
  mWriter := TSarifWriter.Create(ARules, ASourceRoot);
  try
    Result := mWriter.Render(AFiles);
  finally
    mWriter.Free;
  end;
end;

class function TFindingsOutput.Render(const AFiles: TArray<TCheckedFile>; AFormat: TFindingsFormat;
  const ARules: TArray<TRuleDescriptor>): string;
begin
  Result := Render(AFiles, AFormat, ARules, '');
end;

class function TFindingsOutput.Render(const AFiles: TArray<TCheckedFile>; AFormat: TFindingsFormat;
  const ARules: TArray<TRuleDescriptor>; const ASourceRoot: string): string;
begin
  case AFormat of
    TFindingsFormat.Json:
      Result := RenderJson(AFiles);
    TFindingsFormat.Sarif:
      Result := RenderSarif(AFiles, ARules, ASourceRoot);
  else
    Result := RenderText(AFiles);
  end;
end;

class function TFindingsOutput.ExitCode(const AFiles: TArray<TCheckedFile>): Integer;
begin
  Result := ExitCode(AFiles, TFailOn.Error);
end;

class function TFindingsOutput.ExitCode(const AFiles: TArray<TCheckedFile>; AFailOn: TFailOn): Integer;
var
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
begin
  Result := ExitClean;
  if AFailOn = TFailOn.Never then
  begin
    Exit;
  end;
  // Treffer aus der Baseline sind hier schon ausgeblendet und zählen deshalb nie.
  for CheckedFile in AFiles do
  begin
    for Finding in CheckedFile.Findings do
    begin
      if (Finding.Severity = TRuleSeverity.Error) or
        ((AFailOn = TFailOn.Warning) and (Finding.Severity = TRuleSeverity.Warning)) then
      begin
        Exit(ExitFindings);
      end;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Output', cTexts);

end.
