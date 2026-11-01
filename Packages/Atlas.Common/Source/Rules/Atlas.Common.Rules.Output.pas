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
  System.Generics.Collections;

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
        Builder.Append(Format('%s(%d,%d): %s %s [Konfidenz %s]: %s', [CheckedFile.Path,
          Finding.Range.StartPos.Line + 1, Finding.Range.StartPos.Character + 1,
          TFindingsOutput.SeverityName(Finding.Severity), Finding.RuleId, ConfidenceText(Finding.Confidence),
          Finding.Message]));
        Builder.Append(sLineBreak);
      end;
    end;
    Builder.Append(Format('%d Treffer in %d von %d Dateien', [Count, FilesWithFindings, Length(AFiles)]));
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

/// <summary>Ein Ergebnis mit Fingerabdrücken und Zustand gegenüber der Baseline.</summary>
procedure AppendSarifMark(ABuilder: TStringBuilder; ACatalog: TRuleCatalog; const ARules: TArray<TRuleDescriptor>;
  const ACheckedFile: TCheckedFile; const ASourceRoot: string; const AMark: TBaselineMark;
  ALineCounts, AContextCounts: TDictionary<string, Integer>);
var
  Finding: TRuleFinding;
  Severity: TRuleSeverity;
begin
  Finding := AMark.Finding;
  // Nicht mehr gefunden: Schweregrad aus dem Aufrufer, sonst der Standard der Regel.
  if (AMark.State = TBaselineState.Absent) and (Finding.Severity in [TRuleSeverity.Default, TRuleSeverity.Off]) then
  begin
    Severity := DefaultSeverityOf(ARules, Finding.RuleId);
  end
  else
  begin
    Severity := Finding.Severity;
  end;
  ABuilder.Append('{"ruleId":').Append(TFindingsOutput.JsonString(Finding.RuleId));
  ABuilder.Append(',"level":').Append(TFindingsOutput.JsonString(SarifLevel(Severity)));
  ABuilder.Append(',"message":{"text":').Append(TFindingsOutput.JsonString(SarifMessage(ACatalog, Finding)));
  ABuilder.Append('},"locations":[{"physicalLocation":{"artifactLocation":');
  ABuilder.Append(SarifLocation(ACheckedFile, ASourceRoot)).Append('}');
  // Nicht mehr gefunden: keine Stelle im aktuellen Text.
  if AMark.State <> TBaselineState.Absent then
  begin
    ABuilder.Append(Format(',"region":{"startLine":%d,"startColumn":%d,"endLine":%d,"endColumn":%d}',
      [Finding.Range.StartPos.Line + 1, Finding.Range.StartPos.Character + 1,
      Finding.Range.EndPos.Line + 1, Finding.Range.EndPos.Character + 1]));
  end;
  ABuilder.Append('}}]');
  ABuilder.Append(',"partialFingerprints":{"atlasBaseline/v1":');
  ABuilder.Append(TFindingsOutput.JsonString(Occurrence(ALineCounts, TRuleBaseline.SarifFingerprint(AMark))));
  ABuilder.Append(',"atlasContext/v1":').Append(TFindingsOutput.JsonString(Occurrence(AContextCounts,
    AMark.Context))).Append('}');
  if AMark.State <> TBaselineState.None then
  begin
    ABuilder.Append(',"baselineState":').Append(TFindingsOutput.JsonString(BaselineStateName(AMark.State)));
  end;
  if AMark.State = TBaselineState.Unchanged then
  begin
    ABuilder.Append(',"suppressions":[{"kind":"external","justification":').Append(
      TFindingsOutput.JsonString(BaselineFileName)).Append('}]');
  end;
  ABuilder.Append(',"properties":{"confidence":').Append(TFindingsOutput.JsonString(ConfidenceName(Finding.Confidence)));
  ABuilder.Append(',"detail":').Append(TFindingsOutput.JsonString(Finding.Message));
  if AMark.Routine <> '' then
  begin
    ABuilder.Append(',"routine":').Append(TFindingsOutput.JsonString(AMark.Routine));
  end;
  ABuilder.Append('}}');
end;

function RenderSarif(const AFiles: TArray<TCheckedFile>; const ARules: TArray<TRuleDescriptor>;
  const ASourceRoot: string): string;
var
  Mark: TBaselineMark;
  LineCounts, ContextCounts: TDictionary<string, Integer>;
  Builder: TStringBuilder;
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
  Rule: TRuleDescriptor;
  Entry: TRuleCatalogEntry;
  Catalog: TRuleCatalog;
  First: Boolean;
  RootUri: string;
begin
  // Immer der englische Katalog: stabile Texte für GitHub Code Scanning.
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":[{');
    Builder.Append('"tool":{"driver":{"name":').Append(TFindingsOutput.JsonString(TProductVersion.Name));
    Builder.Append(',"version":').Append(TFindingsOutput.JsonString(TProductVersion.Version));
    Builder.Append(',"informationUri":"https://github.com/xKnockOut/Atlas-IDE-Expert","rules":[');
    First := True;
    for Rule in ARules do
    begin
      if not First then
      begin
        Builder.Append(',');
      end;
      First := False;
      Builder.Append('{"id":').Append(TFindingsOutput.JsonString(Rule.Id));
      if Catalog.TryFind(Rule.Id, Entry) then
      begin
        Builder.Append(',"name":').Append(TFindingsOutput.JsonString(Entry.Name));
        Builder.Append(',"shortDescription":{"text":').Append(TFindingsOutput.JsonString(Entry.Name));
        Builder.Append('},"fullDescription":{"text":').Append(TFindingsOutput.JsonString(Entry.Description));
        Builder.Append('},"properties":{"tags":[').Append(TFindingsOutput.JsonString(TRuleCatalog.CategoryName(Entry.Category)));
        Builder.Append(']}');
      end
      else
      begin
        Builder.Append(',"shortDescription":{"text":').Append(TFindingsOutput.JsonString(Rule.Description)).Append('}');
      end;
      Builder.Append(',"helpUri":').Append(TFindingsOutput.JsonString(TRuleCatalog.HelpUri(Rule.Id)));
      Builder.Append(',"defaultConfiguration":{"level":').Append(TFindingsOutput.JsonString(SarifLevel(Rule.DefaultSeverity)));
      Builder.Append('}}');
    end;
    Builder.Append(']}}');
    if ASourceRoot <> '' then
    begin
      RootUri := TFindingsOutput.FileUri(ASourceRoot);
      if RootUri[Length(RootUri)] <> '/' then
      begin
        RootUri := RootUri + '/';
      end;
      Builder.Append(',"originalUriBaseIds":{').Append(TFindingsOutput.JsonString(TFindingsOutput.SourceRootId));
      Builder.Append(':{"uri":').Append(TFindingsOutput.JsonString(RootUri)).Append('}}');
    end;
    Builder.Append(',"results":[');
    First := True;
    for CheckedFile in AFiles do
    begin
      if Length(CheckedFile.Marks) > 0 then
      begin
        // Zähler je Datei: gleiche Treffer derselben Datei unterscheidet ":n".
        LineCounts := TDictionary<string, Integer>.Create;
        ContextCounts := TDictionary<string, Integer>.Create;
        try
          for Mark in CheckedFile.Marks do
          begin
            if not First then
            begin
              Builder.Append(',');
            end;
            First := False;
            AppendSarifMark(Builder, Catalog, ARules, CheckedFile, ASourceRoot, Mark, LineCounts, ContextCounts);
          end;
        finally
          ContextCounts.Free;
          LineCounts.Free;
        end;
        Continue;
      end;
      for Finding in CheckedFile.Findings do
      begin
        if not First then
        begin
          Builder.Append(',');
        end;
        First := False;
        Builder.Append('{"ruleId":').Append(TFindingsOutput.JsonString(Finding.RuleId));
        Builder.Append(',"level":').Append(TFindingsOutput.JsonString(SarifLevel(Finding.Severity)));
        Builder.Append(',"message":{"text":').Append(TFindingsOutput.JsonString(SarifMessage(Catalog, Finding)));
        Builder.Append('},"locations":[{"physicalLocation":{"artifactLocation":');
        Builder.Append(SarifLocation(CheckedFile, ASourceRoot));
        Builder.Append(Format('},"region":{"startLine":%d,"startColumn":%d,"endLine":%d,"endColumn":%d}}}]',
          [Finding.Range.StartPos.Line + 1, Finding.Range.StartPos.Character + 1,
          Finding.Range.EndPos.Line + 1, Finding.Range.EndPos.Character + 1]));
        Builder.Append(',"properties":{"confidence":').Append(TFindingsOutput.JsonString(ConfidenceName(Finding.Confidence)));
        Builder.Append(',"detail":').Append(TFindingsOutput.JsonString(Finding.Message));
        Builder.Append('}}');
      end;
    end;
    Builder.Append(']}]}');
    Result := Builder.ToString;
  finally
    Builder.Free;
    Catalog.Free;
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

end.
