unit Atlas.Common.Mcp.CodeTools;

// MCP-Werkzeuge, die Quelltext auswerten (#48): Verwendungen, Aufrufhierarchie
// und Befunde der Prüfregeln. Das Symbol wird per Name über den Index gefunden
// und dann wie im LSP an seiner Deklaration aufgelöst.
// Befunde und check_code lesen die Dateien mit den Symbolen des Projekts und
// dessen Include-Dateien (CheckSource, #860), wie der Editor, und geben den
// Regeln den Symbolindex und die Projektdienste mit (CheckProject, #1112).
// Verwendungen und Aufrufer sind nach Treffersicherheit getrennt (#1119):
// erst die sicheren, dann die erschlossenen mit Grund.
// get_impact (#1120): Auswirkungen einer Änderung nach Ebenen samt betroffenen
// Tests, als Text oder als JSON wie atlas/impact.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Todos.Contract;

{$SCOPEDENUMS ON}

type
  TMcpCallDirection = (Incoming, Outgoing, Both);

  TMcpCodeTools = class
  public const
    MaxReferences = 200;
    MaxFindings = 200;
  private
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FCheckSource: TCheckSourceFunc;
    FCheckProject: TCheckProjectFunc;
    FSettingsFor: TReferenceSettingsProvider;
    FImpactOptionsFor: TImpactOptionsProvider;
    function Locate(const AName: string; out ALocation: TSymbolLocation; out AHint: string): Boolean;
    function LineText(const AFileName: string; ALine: Integer): string;
    function SettingsOf(const AFileName: string): TReferenceSettings;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    /// <summary>Alle Verwendungen des Symbols im Projekt, mit Zeile und Quelltext.</summary>
    function References(const AName: string): string;
    /// <summary>Aufrufer und/oder aufgerufene Routinen einer Methode oder Routine.</summary>
    function CallHierarchy(const AName: string; ADirection: TMcpCallDirection): string;
    /// <summary>get_impact (#1120) mit der Tiefe aus navigation.impactDepth.</summary>
    function Impact(const AName: string; AJson: Boolean): string; overload;
    /// <summary>Wie oben mit der Tiefe ADepth (1–5, außerhalb begrenzt).</summary>
    function Impact(const AName: string; ADepth: Integer; AJson: Boolean): string; overload;
    /// <summary>Text von get_impact: Symbol, direkte und indirekte Stellen als Baum, Tests, Grenzen.</summary>
    class function ImpactReport(const AResult: TImpactResult; const AHint: string): string; static;
    /// <summary>qualified_name (#128): voll qualifizierter Name des Symbols an ALine/AColumn (ab 1);
    /// EMcpToolError, wenn dort keins steht.</summary>
    function QualifiedName(const AFileName: string; ALine, AColumn: Integer; AWithParameters: Boolean): string;
    /// <summary>Befunde der Prüfregeln und Syntaxfehler je Datei; ARoot für relative Pfade.</summary>
    class function Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText): string; overload;
      static;
    /// <summary>Wie oben mit Symbolen und Include-Dateien je Datei aus ASource (#860).</summary>
    class function Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ASource: TCheckSourceFunc): string; overload; static;
    /// <summary>Wie oben mit Projekt, Symbolindex und Projektdiensten je Datei aus AProject (#1112), wie im
    /// Server.</summary>
    class function Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ASource: TCheckSourceFunc; const AProject: TCheckProjectFunc): string; overload; static;
    /// <summary>hook_check: Befunde ab ASeverity (Warning: Warnungen und Fehler) einer gerade bearbeiteten
    /// Datei als Ausgabe eines PostToolUse-Hooks von Claude Code: JSON mit
    /// hookSpecificOutput.additionalContext, damit Claude die Befunde sofort sieht. Leer, wenn die Datei
    /// kein Pascal-Quelltext ist (.pas, .dpr, .dpk, .inc), sich nicht lesen lässt oder keine Befunde hat;
    /// leere Hook-Ausgabe ändert nichts. Projekt und Symbolindex aus AProject wie bei get_diagnostics (#1112).</summary>
    class function HookDiagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot, AFileName: string; const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc;
      const AProject: TCheckProjectFunc; ASeverity: TRuleSeverity): string; static;
    /// <summary>Schwelle für hook_check aus "error", "warning" (Vorgabe bei leerem Text), "information" oder
    /// "hint"; EMcpToolError bei anderem Text.</summary>
    class function ParseHookSeverity(const AText: string): TRuleSeverity; static;
    class function ParseDirection(const AText: string): TMcpCallDirection; static;
    /// <summary>get_metrics (#66): Kennzahlen je Methode mit den Grenzwerten aus ASettings; Markdown-Bericht
    /// oder mit AJson die Metrikdaten. Pfade relativ zu ARoot.</summary>
    class function Metrics(const ASettings: TServerSettings; const ARoot: string; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; AJson: Boolean): string; static;
    /// <summary>get_todos (#68): TODO-Einträge der Dateien AFiles mit den Marken aus ASettings (Option keywords
    /// der Regel todo-comment), gefiltert nach AFilter; Markdown-Übersicht oder mit AJson die Daten. Pfade relativ
    /// zu ARoot.</summary>
    class function Todos(const ASettings: TServerSettings; const ARoot: string; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const AFilter: TTodoFilter; AJson: Boolean): string; static;
    /// <summary>
    /// check_code (#178): prüft AText als neuen Inhalt von AFileName, ohne zu schreiben.
    /// Mit AStartLine > 0 ersetzt AText nur die Zeilen AStartLine..AEndLine (ab 1, einschließlich;
    /// AEndLine = AStartLine - 1 fügt vor AStartLine ein). Liefert Syntaxfehler, Regeltreffer und
    /// nicht auflösbare Bezeichner; Positionen beziehen sich auf den neuen Text.
    /// </summary>
    function CheckCode(const ARules: TArray<IRule>; const ASettings: TServerSettings; const ARoot, AFileName,
      AText: string; AStartLine, AEndLine: Integer): string;
    /// <summary>Ersetzt die Zeilen AStartLine..AEndLine (ab 1) von AOriginal durch AText; EMcpToolError bei
    /// ungültigem Bereich.</summary>
    class function ReplaceLines(const AOriginal, AText: string; AStartLine, AEndLine: Integer): string; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Symbole und Include-Dateien für check_code (#860); nil = Vordefinitionen (Win32).</summary>
    property CheckSource: TCheckSourceFunc read FCheckSource write FCheckSource;
    /// <summary>Projekt, Symbolindex und Projektdienste für check_code (#1112); nil = ohne Index.</summary>
    property CheckProject: TCheckProjectFunc read FCheckProject write FCheckProject;
    /// <summary>Einstellungen references.* (#1119); nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
    /// <summary>Optionen der Auswirkungsanalyse (#1120); nicht gesetzt: Vorgaben mit SettingsFor.</summary>
    property ImpactOptionsFor: TImpactOptionsProvider read FImpactOptionsFor write FImpactOptionsFor;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Output,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Text.Lines;

{ TMcpCodeTools }

constructor TMcpCodeTools.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
  const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

function TMcpCodeTools.Locate(const AName: string; out ALocation: TSymbolLocation; out AHint: string): Boolean;
var
  Lookup: TMcpIndexTools;
  Found: TArray<TSymbolLocation>;
begin
  AHint := '';
  Lookup := TMcpIndexTools.Create(FIndex, nil);
  try
    Found := Lookup.Matches(AName);
  finally
    Lookup.Free;
  end;
  Result := Length(Found) > 0;
  if Result then
  begin
    ALocation := Found[0];
    if Length(Found) > 1 then
      AHint := Format('Hinweis: %d Symbole dieses Namens, ausgewertet wird %s in %s. ' +
        'Mit TTyp.Name genauer fassen.', [Length(Found), ALocation.Symbol.QualifiedName, ALocation.UnitName]);
  end;
end;

function TMcpCodeTools.LineText(const AFileName: string; ALine: Integer): string;
var
  Text: string;
  Lines: TStringList;
begin
  Result := '';
  if not FReadText(AFileName, Text) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    if (ALine >= 0) and (ALine < Lines.Count) then
      Result := Trim(Lines[ALine]);
  finally
    Lines.Free;
  end;
end;

function TMcpCodeTools.SettingsOf(const AFileName: string): TReferenceSettings;
begin
  if Assigned(FSettingsFor) then
    Result := FSettingsFor(TDocumentUris.FromPath(AFileName))
  else
    Result := TReferenceSettings.Default;
end;

/// <summary>Aufruf über Interface bzw. virtuelle Methode (#1122): " [über Interface, 3 Umsetzungen]".</summary>
function DispatchSuffix(const ACall: THierarchyCall): string;
begin
  Result := '';
  if ACall.Dispatch = TReferenceReason.Interface_ then
    Result := 'über Interface'
  else if ACall.Dispatch = TReferenceReason.Virtual then
    Result := 'virtuell'
  else
    Exit;
  if ACall.Implementations <= 0 then
    Result := ' [' + Result + ']'
  else if ACall.Implementations = 1 then
    Result := ' [' + Result + ', 1 Umsetzung]'
  else
    Result := Format(' [%s, %d Umsetzungen]', [Result, ACall.Implementations]);
end;

/// <summary>" – erschlossen (interface): Aufruf über …" für erschlossene Treffer, sonst ''.</summary>
function ConfidenceSuffix(const AConfidence: TReferenceConfidence): string;
begin
  if AConfidence.IsSure then
    Result := ''
  else
    Result := Format(' – erschlossen (%s): %s', [AConfidence.ReasonName, AConfidence.Detail]);
end;

function TMcpCodeTools.QualifiedName(const AFileName: string; ALine, AColumn: Integer;
  AWithParameters: Boolean): string;
var
  Text, Error: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  if (ALine < 1) or (AColumn < 1) then
    raise EMcpToolError.Create('line und column zählen ab 1');
  if not FReadText(AFileName, Text) then
    raise EMcpToolError.CreateFmt('Datei %s nicht lesbar', [AFileName]);
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      if not TQualifiedNames.At(Resolver, FIndex, Tree, AFileName, TTextPosition.Create(ALine - 1, AColumn - 1),
        AWithParameters, Result, Error) then
        raise EMcpToolError.Create(Error);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function TMcpCodeTools.References(const AName: string): string;
var
  Location: TSymbolLocation;
  Hint, Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Files: TArray<string>;
  Found: TArray<TReferenceLocation>;
  Reference: TReferenceLocation;
  Lines: TStringList;
  Count, Sure, Round: Integer;
  Pass: Boolean;
begin
  if not Locate(AName, Location, Hint) then
    Exit(Format('Kein Symbol "%s" im Index.', [AName]));
  if not FReadText(Location.FileName, Text) then
    Exit(Format('Datei %s nicht lesbar.', [Location.FileName]));
  Files := nil;
  if Assigned(FFiles) then
    Files := FFiles();
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      Found := TLspReferences.Find(Resolver, FIndex, Tree, Location.FileName,
        Location.Symbol.SelectionRange.StartPos, False, Files, FReadText, SettingsOf(Location.FileName), nil);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  Lines := TStringList.Create;
  try
    Sure := 0;
    for Reference in Found do
      if Reference.Confidence.IsSure then
        Inc(Sure);
    Lines.Add(Format('%d Verwendungen von %s (%s:%d), %d sicher, %d erschlossen:', [Length(Found),
      Location.Symbol.QualifiedName, Location.FileName, Location.Symbol.SelectionRange.StartPos.Line + 1, Sure,
      Length(Found) - Sure]));
    // Erst die sicheren, dann die erschlossenen: Nur die sicheren ändert ein Umbenennen ohne Prüfung.
    Count := 0;
    for Round := 0 to 1 do
    begin
      Pass := Round = 0;
      if not Pass and (Sure < Length(Found)) and (Count < MaxReferences) then
        Lines.Add('Erschlossen, vor dem Umbenennen prüfen:');
      for Reference in Found do
      begin
        if Reference.Confidence.IsSure <> Pass then
          Continue;
        if Count >= MaxReferences then
          Break;
        Inc(Count);
        Lines.Add(Format('%s:%d: %s%s', [Reference.FileName, Reference.Range.StartPos.Line + 1,
          LineText(Reference.FileName, Reference.Range.StartPos.Line), ConfidenceSuffix(Reference.Confidence)]));
      end;
    end;
    if Count < Length(Found) then
      Lines.Add(Format('… %d weitere', [Length(Found) - Count]));
    if Hint <> '' then
      Lines.Add(Hint);
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function DescribeItem(const AItem: THierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Container <> '' then
    Result := AItem.Container + '.' + Result;
  Result := Format('%s – Unit %s, %s:%d', [Result, AItem.UnitName, AItem.FileName,
    AItem.SelectionRange.StartPos.Line + 1]);
end;

procedure AddCalls(ALines: TStrings; const ATitle, AArrow: string; const ACalls: TArray<THierarchyCall>);
var
  Call: THierarchyCall;
  Sure, Round: Integer;
begin
  ALines.Add(ATitle);
  if Length(ACalls) = 0 then
    ALines.Add('  (keine)');
  Sure := 0;
  for Call in ACalls do
    if Call.Confidence.IsSure then
      Inc(Sure);
  // Sichere Aufrufer zuerst, erschlossene mit Grund danach (#1119).
  for Round := 0 to 1 do
    for Call in ACalls do
      if Call.Confidence.IsSure = (Round = 0) then
        ALines.Add(Format('  %s %s (%d×)%s%s', [AArrow, DescribeItem(Call.Item), Length(Call.Ranges),
          DispatchSuffix(Call), ConfidenceSuffix(Call.Confidence)]));
  if Sure < Length(ACalls) then
    ALines.Add(Format('  %d sicher, %d erschlossen', [Sure, Length(ACalls) - Sure]));
end;

function TMcpCodeTools.CallHierarchy(const AName: string; ADirection: TMcpCallDirection): string;
var
  Location: TSymbolLocation;
  Hint, Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Item: THierarchyItem;
  Files: TArray<string>;
  Lines: TStringList;
begin
  if not Locate(AName, Location, Hint) then
    Exit(Format('Kein Symbol "%s" im Index.', [AName]));
  if not FReadText(Location.FileName, Text) then
    Exit(Format('Datei %s nicht lesbar.', [Location.FileName]));
  Files := nil;
  if Assigned(FFiles) then
    Files := FFiles();
  Lines := TStringList.Create;
  try
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
      try
        Resolver.Namespaces := FNamespaces;
        if not TLspHierarchies.CallItemAt(Resolver, Tree, Location.FileName,
          Location.Symbol.SelectionRange.StartPos, Item) then
          Exit(Format('%s ist keine Routine oder Methode.', [Location.Symbol.QualifiedName]));
        Lines.Add(DescribeItem(Item));
        if ADirection in [TMcpCallDirection.Incoming, TMcpCallDirection.Both] then
          AddCalls(Lines, 'Aufgerufen von:', '←',
            TLspHierarchies.IncomingCalls(Resolver, FIndex, Item, Files, FReadText, SettingsOf(Item.FileName), nil));
        if ADirection in [TMcpCallDirection.Outgoing, TMcpCallDirection.Both] then
          AddCalls(Lines, 'Ruft auf:', '→', TLspHierarchies.OutgoingCalls(Resolver, FIndex, Item, FReadText, nil));
      finally
        Resolver.Free;
      end;
    finally
      Tree.Free;
    end;
    if Hint <> '' then
      Lines.Add(Hint);
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function ImpactOptionsOf(const ATools: TMcpCodeTools; const AProvider: TImpactOptionsProvider;
  const AFileName: string): TImpactOptions;
begin
  if Assigned(AProvider) then
    Result := AProvider(TDocumentUris.FromPath(AFileName))
  else
  begin
    Result := TImpactOptions.Default;
    Result.References := ATools.SettingsOf(AFileName);
  end;
end;

function TMcpCodeTools.Impact(const AName: string; AJson: Boolean): string;
var
  Location: TSymbolLocation;
  Hint: string;
begin
  if not Locate(AName, Location, Hint) then
    Exit(Format('Kein Symbol "%s" im Index.', [AName]));
  Result := Impact(AName, ImpactOptionsOf(Self, FImpactOptionsFor, Location.FileName).Depth, AJson);
end;

function TMcpCodeTools.Impact(const AName: string; ADepth: Integer; AJson: Boolean): string;
var
  Location: TSymbolLocation;
  Hint, Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Start: THierarchyItem;
  Options: TImpactOptions;
  Found: TImpactResult;
  Json: TJSONObject;
begin
  if not Locate(AName, Location, Hint) then
    Exit(Format('Kein Symbol "%s" im Index.', [AName]));
  if not FReadText(Location.FileName, Text) then
    Exit(Format('Datei %s nicht lesbar.', [Location.FileName]));
  Options := ImpactOptionsOf(Self, FImpactOptionsFor, Location.FileName);
  Options.Depth := TImpactAnalysis.ClampDepth(ADepth);
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      if not TLspHierarchies.SymbolItemAt(Resolver, Tree, Location.FileName,
        Location.Symbol.SelectionRange.StartPos, Start) then
        Exit(Format('Zu %s gibt es keine Deklaration.', [Location.Symbol.QualifiedName]));
      if Assigned(FFiles) then
        Found := TImpactAnalysis.Analyze(Resolver, FIndex, Start, FFiles(), FReadText, Options, nil)
      else
        Found := TImpactAnalysis.Analyze(Resolver, FIndex, Start, nil, FReadText, Options, nil);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  if not AJson then
    Exit(ImpactReport(Found, Hint));
  Json := TImpactAnalysis.ToJson(Found);
  try
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

function ImpactEdgeText(AEdge: TImpactEdge): string;
const
  Texts: array[TImpactEdge] of string = ('Aufruf', 'Verweis', 'Override', 'überschriebene Basismethode',
    'Interface-Methode', 'Umsetzung');
begin
  Result := Texts[AEdge];
end;

procedure AddImpactPlace(ALines: TStrings; const AResult: TImpactResult; AIndex: Integer; const AIndent: string);
var
  Place: TImpactPlace;
  Binding: TImpactFormBinding;
  Child: Integer;
  Extra: string;
begin
  Place := AResult.Places[AIndex];
  Extra := ImpactEdgeText(Place.Edge);
  if Length(Place.Ranges) > 0 then
    Extra := Format('%s, %d×', [Extra, Length(Place.Ranges)]);
  if Place.Terminal then
    Extra := Extra + ', Unit-Ebene';
  if Place.Test >= 0 then
    Extra := Extra + ', Test';
  ALines.Add(Format('%s← %s (%s)%s', [AIndent, DescribeItem(Place.Item), Extra, ConfidenceSuffix(Place.Confidence)]));
  for Binding in Place.Forms do
    ALines.Add(Format('%s    Formular: %s (%s:%d)', [AIndent, Binding.Text, Binding.FileName,
      Binding.Range.StartPos.Line + 1]));
  // Jede Stelle hat genau eine Ursache: Der Baum endet.
  for Child := AIndex + 1 to High(AResult.Places) do
    if AResult.Places[Child].Cause = AIndex then
      AddImpactPlace(ALines, AResult, Child, AIndent + '  ');
end;

class function TMcpCodeTools.ImpactReport(const AResult: TImpactResult; const AHint: string): string;
var
  Lines: TStringList;
  Binding: TImpactFormBinding;
  Test: TImpactTest;
  Index: Integer;
  Names: TArray<string>;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(Format('Auswirkungen von %s, Tiefe %d: %d Stellen, %d direkt, %d indirekt, %d Tests.',
      [DescribeItem(AResult.Symbol), AResult.Depth, Length(AResult.Places), AResult.LevelCount(1),
      Length(AResult.Places) - AResult.LevelCount(1), Length(AResult.Tests)]));
    for Binding in AResult.SymbolForms do
      Lines.Add(Format('  Formular: %s (%s:%d)', [Binding.Text, Binding.FileName, Binding.Range.StartPos.Line + 1]));
    if Length(AResult.Places) = 0 then
      Lines.Add('Nichts verwendet das Symbol.');
    for Index := 0 to High(AResult.Places) do
      if AResult.Places[Index].Cause < 0 then
        AddImpactPlace(Lines, AResult, Index, '  ');
    if Length(AResult.Tests) > 0 then
    begin
      Lines.Add('Betroffene Tests:');
      for Test in AResult.Tests do
        Lines.Add(Format('  %s (%s:%d, Ebene %d)', [Test.Name, Test.FileName, Test.Line + 1, Test.Level]));
      Names := AResult.RunNames;
      Lines.Add('run_tests tests: ' + string.Join(', ', Names));
    end
    else
      Lines.Add('Keine betroffenen Tests.');
    if TImpactLimit.Depth in AResult.Limits then
      Lines.Add(Format('Tiefe %d erreicht: %d Stellen nicht weiter verfolgt (größere "depth" geht weiter).',
        [AResult.Depth, AResult.Unexpanded]));
    if TImpactLimit.Count in AResult.Limits then
      Lines.Add(Format('Höchstzahl von %d Stellen erreicht, Ergebnis unvollständig.', [AResult.MaxPlaces]));
    if TImpactLimit.Time in AResult.Limits then
      Lines.Add(Format('Zeitlimit von %d ms erreicht, Ergebnis unvollständig.', [AResult.TimeoutMs]));
    if AHint <> '' then
      Lines.Add(AHint);
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TMcpCodeTools.Metrics(const ASettings: TServerSettings; const ARoot: string;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; AJson: Boolean): string;
var
  Collector: TMetricsCollector;
  Files: TArray<TFileMetrics>;
  Limits: TMetricLimits;
begin
  Limits := TMetricRules.Limits(ASettings);
  Collector := TMetricsCollector.Create;
  try
    Files := Collector.Collect(AFiles, ARoot,
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := Assigned(AReadText) and AReadText(AFileName, AText);
      end);
  finally
    Collector.Free;
  end;
  if AJson then
    Result := TMetricsReport.Json(Files, Limits)
  else
    Result := TMetricsReport.Markdown(Files, Limits, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)));
end;

class function TMcpCodeTools.Todos(const ASettings: TServerSettings; const ARoot: string;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; const AFilter: TTodoFilter;
  AJson: Boolean): string;
var
  Files: TArray<TFileTodos>;
begin
  Files := TTodoScanner.Filter(TTodoScanner.Collect(AFiles, ARoot,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Assigned(AReadText) and AReadText(AFileName, AText);
    end, TTodoRules.Keywords(ASettings)), AFilter);
  if AJson then
    Result := TTodoReport.Json(Files)
  else
    Result := TTodoReport.Markdown(Files, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)));
end;

class function TMcpCodeTools.Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText): string;
begin
  Result := Diagnostics(ARules, ASettings, ARoot, AFiles, AReadText, nil);
end;

class function TMcpCodeTools.Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ASource: TCheckSourceFunc): string;
begin
  Result := Diagnostics(ARules, ASettings, ARoot, AFiles, AReadText, ASource, nil);
end;

class function TMcpCodeTools.Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ASource: TCheckSourceFunc; const AProject: TCheckProjectFunc): string;
var
  Lines: TStringList;
  FileName, RelativePath, Text: string;
  Finding: TRuleFinding;
  Count, Checked: Integer;
  Scopes: TFindingScopes;
begin
  Lines := TStringList.Create;
  try
    Count := 0;
    Checked := 0;
    for FileName in AFiles do
    begin
      if not AReadText(FileName, Text) then
      begin
        Lines.Add(Format('%s: nicht lesbar', [FileName]));
        Continue;
      end;
      Inc(Checked);
      RelativePath := FileName;
      if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), FileName) then
        RelativePath := Copy(FileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
      for Finding in TFileChecker.CheckText(ARules, ASettings, RelativePath, Text,
        TFileChecker.ProjectOf(AProject, FileName), TFileChecker.SourceOf(ASource, FileName), Scopes) do
      begin
        Inc(Count);
        if Count <= MaxFindings then
          Lines.Add(Format('%s:%d:%d: %s [%s] [Konfidenz %s] %s', [FileName, Finding.Range.StartPos.Line + 1,
            Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity),
            Finding.RuleId, ConfidenceText(Finding.Confidence), Finding.Message]));
      end;
    end;
    if Count > MaxFindings then
      Lines.Add(Format('… %d weitere Befunde', [Count - MaxFindings]));
    Lines.Insert(0, Format('%d Befunde in %d Dateien.', [Count, Checked]));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TMcpCodeTools.HookDiagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot, AFileName: string; const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc;
  const AProject: TCheckProjectFunc; ASeverity: TRuleSeverity): string;
const
  PascalExtensions: array[0..3] of string = ('.pas', '.dpr', '.dpk', '.inc');
var
  Text, Extension, Context, RelativePath: string;
  Finding: TRuleFinding;
  Lines: TStringList;
  Count: Integer;
  Scopes: TFindingScopes;
begin
  Result := '';
  Extension := ExtractFileExt(AFileName);
  if not MatchText(Extension, PascalExtensions) then
    Exit;
  if not (Assigned(AReadText) and AReadText(AFileName, Text)) then
    Exit;
  // Wie get_diagnostics: Regeln und overrides aus atlas.json gelten für den Pfad relativ zum Projekt.
  RelativePath := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
    RelativePath := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  Lines := TStringList.Create;
  try
    Count := 0;
    for Finding in TFileChecker.CheckText(ARules, ASettings, RelativePath, Text,
      TFileChecker.ProjectOf(AProject, AFileName), TFileChecker.SourceOf(ASource, AFileName), Scopes) do
    begin
      if Finding.Severity < ASeverity then
        Continue;
      Inc(Count);
      if Count <= MaxFindings then
        Lines.Add(Format('%d:%d: %s [%s] %s', [Finding.Range.StartPos.Line + 1,
          Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity), Finding.RuleId,
          Finding.Message]));
    end;
    if Count = 0 then
      Exit;
    if Count > MaxFindings then
      Lines.Add(Format('… %d weitere Befunde', [Count - MaxFindings]));
    Context := Format('Atlas hat in %s nach der Änderung %d Befunde gefunden (Zeile:Spalte):', [AFileName, Count]) +
      #10 + TrimRight(Lines.Text) + #10 +
      'Ursache im Code beheben; Erklärung mit explain_finding, Korrektur mit apply_code_action.';
  finally
    Lines.Free;
  end;
  Result := '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":' +
    TFindingsOutput.JsonString(Context) + '}}';
end;

class function TMcpCodeTools.ParseHookSeverity(const AText: string): TRuleSeverity;
begin
  if (AText = '') or SameText(AText, 'warning') then
    Result := TRuleSeverity.Warning
  else if SameText(AText, 'error') then
    Result := TRuleSeverity.Error
  else if SameText(AText, 'information') then
    Result := TRuleSeverity.Information
  else if SameText(AText, 'hint') then
    Result := TRuleSeverity.Hint
  else
    raise EMcpToolError.Create('"severity" ist error, warning, information oder hint');
end;

function SplitKeepingBreaks(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  // Jede Zeile behält ihren Zeilenwechsel, damit CRLF/LF erhalten bleiben.
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) do
    if AText[Index] = #10 then
    begin
      Result := Result + [Copy(AText, Start, Index - Start + 1)];
      Start := Index + 1;
    end;
  if Start <= Length(AText) then
    Result := Result + [Copy(AText, Start, MaxInt)];
end;

class function TMcpCodeTools.ReplaceLines(const AOriginal, AText: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  Index: Integer;
  Inserted: string;
begin
  Lines := SplitKeepingBreaks(AOriginal);
  if (AStartLine < 1) or (AStartLine > Length(Lines) + 1) or (AEndLine < AStartLine - 1) or
    (AEndLine > Length(Lines)) then
    raise EMcpToolError.CreateFmt('Ungültiger Bereich %d-%d; die Datei hat %d Zeilen',
      [AStartLine, AEndLine, Length(Lines)]);
  Inserted := AText;
  // Der ersetzte Bereich endet mit einem Zeilenwechsel, wenn danach noch etwas kommt.
  if (Inserted <> '') and (AEndLine < Length(Lines)) and not EndsStr(#10, Inserted) then
    Inserted := Inserted + TTextLines.LineBreakOf(AOriginal);
  Result := '';
  for Index := 0 to AStartLine - 2 do
    Result := Result + Lines[Index];
  Result := Result + Inserted;
  for Index := AEndLine to High(Lines) do
    Result := Result + Lines[Index];
end;

function TMcpCodeTools.CheckCode(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot, AFileName, AText: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TStringList;
  Original, NewText, RelativePath: string;
  Finding: TRuleFinding;
  Count: Integer;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Name: TUnresolvedName;
  Unresolved: TArray<TUnresolvedName>;
  CheckNames: Boolean;
  Source: TCheckSource;
  Processed: TPreprocessorResult;
  Scopes: TFindingScopes;
begin
  if AStartLine > 0 then
  begin
    if not (Assigned(FReadText) and FReadText(AFileName, Original)) then
      raise EMcpToolError.CreateFmt('%s ist nicht lesbar; ohne Bereich den ganzen Text angeben', [AFileName]);
    NewText := ReplaceLines(Original, AText, AStartLine, AEndLine);
  end
  else
    NewText := AText;
  RelativePath := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
    RelativePath := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  Lines := TStringList.Create;
  try
    Count := 0;
    Source := TFileChecker.SourceOf(FCheckSource, AFileName);
    for Finding in TFileChecker.CheckText(ARules, ASettings, RelativePath, NewText,
      TFileChecker.ProjectOf(FCheckProject, AFileName), Source, Scopes) do
    begin
      Inc(Count);
      if Count <= MaxFindings then
        Lines.Add(Format('%d:%d: %s [%s] [Konfidenz %s] %s', [Finding.Range.StartPos.Line + 1,
          Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity), Finding.RuleId,
          ConfidenceText(Finding.Confidence), Finding.Message]));
    end;
    CheckNames := TUnresolvedNames.Available(FIndex);
    if CheckNames then
    begin
      // Nur die aktiven Zweige (#860): Namen eines anderen Zielsystems sind dort nicht auflösbar.
      Tree := TSyntaxTreeCache.ParseActive(NewText, Source.Options, nil, Processed);
      try
        Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
        try
          Resolver.Namespaces := FNamespaces;
          Unresolved := TUnresolvedNames.Find(Resolver, Tree, AFileName);
        finally
          Resolver.Free;
        end;
      finally
        Tree.Free;
      end;
      for Name in Unresolved do
      begin
        Inc(Count);
        if (Count <= MaxFindings) and (Name.Code <> '') then
          Lines.Add(Format('%d:%d: warning [unresolved-identifier] %s', [Name.Range.StartPos.Line + 1,
            Name.Range.StartPos.Character + 1, TUnresolvedNames.Describe(Name)]))
        else if (Count <= MaxFindings) and (Name.Suggestion <> '') then
          Lines.Add(Format('%d:%d: warning [unresolved-identifier] "%s" ist nicht auflösbar; gemeint ist %s? ' +
            '({$SCOPEDENUMS ON})', [Name.Range.StartPos.Line + 1, Name.Range.StartPos.Character + 1, Name.Name,
            Name.Suggestion]))
        else if Count <= MaxFindings then
          Lines.Add(Format('%d:%d: warning [unresolved-identifier] "%s" ist nicht auflösbar', [Name.Range.StartPos.Line + 1,
            Name.Range.StartPos.Character + 1, Name.Name]));
      end;
    end;
    if Count > MaxFindings then
      Lines.Add(Format('… %d weitere Befunde', [Count - MaxFindings]));
    if Count = 0 then
      Lines.Insert(0, Format('Keine Befunde in %s.', [ExtractFileName(AFileName)]))
    else
      Lines.Insert(0, Format('%d Befunde in %s (Positionen im neuen Text, Zeile:Spalte):', [Count, ExtractFileName(AFileName)]));
    if not CheckNames then
      Lines.Add('Hinweis: Unit System ist nicht im Index, Bezeichner wurden nicht geprüft.')
    else
      Lines.Add('Hinweis: Die Namensprüfung kennt keine Überladungen, Generics, Class Helper und with; ' +
        'einzelne Meldungen können Fehlalarme sein.');
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TMcpCodeTools.ParseDirection(const AText: string): TMcpCallDirection;
begin
  if SameText(AText, 'incoming') then
    Result := TMcpCallDirection.Incoming
  else if SameText(AText, 'outgoing') then
    Result := TMcpCallDirection.Outgoing
  else
    Result := TMcpCallDirection.Both;
end;

end.
