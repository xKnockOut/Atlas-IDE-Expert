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
  System.Classes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Mcp.Contract;

{$SCOPEDENUMS ON}

type
  TMcpCallDirection = (Incoming, Outgoing, Both);

  TMcpCodeTools = class
  public const
    cMaxReferences = 200;
    cMaxFindings = 200;
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
    function FindReferences(const ALocation: TSymbolLocation; const AText: string): TArray<TReferenceLocation>;
    procedure AddReferences(ALines: TStrings; const AFound: TArray<TReferenceLocation>; ASure: Boolean;
      var ACount: Integer);
    function CheckedText(const AFileName, AText: string; AStartLine, AEndLine: Integer): string;
    function UnresolvedOf(const AFileName, AText: string; const ASource: TCheckSource): TArray<TUnresolvedName>;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
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
    class function ParseDirection(const AText: string): TMcpCallDirection; static;
    /// <summary>
    /// check_code (#178): prüft AText als neuen Inhalt von AFileName, ohne zu schreiben.
    /// Mit AStartLine > 0 ersetzt AText nur die Zeilen AStartLine..AEndLine (ab 1, einschließlich;
    /// AEndLine = AStartLine - 1 fügt vor AStartLine ein). Liefert Syntaxfehler, Regeltreffer und
    /// nicht auflösbare Bezeichner; Positionen beziehen sich auf den neuen Text.
    /// </summary>
    function CheckCode(const AScope: TMcpRuleScope; const AFileName, AText: string; AStartLine,
      AEndLine: Integer): string;
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
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.CheckTools,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCodeToolsText = (NoteSymbolsOfThisName, ViaInterface, LineAndColumnCountFrom, FileNotReadable, NoSymbolInTheIndex,
    FileNotReadable2, InferredCheckBeforeRenaming, None, IsNotARoutineOr, ThereIsNoDeclarationFor, NoAffectedTests,
    DepthReachedPlacesNotFollowed, MaximumOfPlacesReachedResult, TimeLimitOfMsReached, NothingUsesTheSymbol,
    InvalidRangeTheFileHas, IsNotReadableGiveThe, WarningUnresolvedIdentifierCannotBe,
    WarningUnresolvedIdentifierCannotBe2, NoFindingsIn, NoteUnitSystemIsNot, NoteTheNameCheckKnows,
    UsesOfCertainInferred, CalledBy, Calls, UnitLevel, ImpactOfDepthPlacesDirect, FindingsInPositionsInThe, Virtual,
    ImplementationText, Implementations, Inferred, More, CertainInferred, Form, Form2, AffectedTests, Level,
    MoreFindings);

const
  cTexts: array[TCodeToolsText] of TAtlasText = (
    (De: 'Hinweis: %d Symbole dieses Namens, ausgewertet wird %s in %s. Mit TTyp.Name genauer fassen.';
     En: 'Note: %d symbols of this name, %s in %s is evaluated. Narrow it down with TType.Name.'),
    (De: 'über Interface'; En: 'via interface'),
    (De: 'line und column zählen ab 1'; En: 'line and column count from 1'),
    (De: 'Datei %s nicht lesbar'; En: 'File %s not readable'),
    (De: 'Kein Symbol "%s" im Index.'; En: 'No symbol "%s" in the index.'),
    (De: 'Datei %s nicht lesbar.'; En: 'File %s not readable.'),
    (De: 'Erschlossen, vor dem Umbenennen prüfen:'; En: 'Inferred, check before renaming:'),
    (De: '  (keine)'; En: '  (none)'),
    (De: '%s ist keine Routine oder Methode.'; En: '%s is not a routine or method.'),
    (De: 'Zu %s gibt es keine Deklaration.'; En: 'There is no declaration for %s.'),
    (De: 'Keine betroffenen Tests.'; En: 'No affected tests.'),
    (De: 'Tiefe %d erreicht: %d Stellen nicht weiter verfolgt (größere "depth" geht weiter).';
     En: 'Depth %d reached: %d places not followed further (a greater "depth" goes on).'),
    (De: 'Höchstzahl von %d Stellen erreicht, Ergebnis unvollständig.';
     En: 'Maximum of %d places reached, result incomplete.'),
    (De: 'Zeitlimit von %d ms erreicht, Ergebnis unvollständig.';
     En: 'Time limit of %d ms reached, result incomplete.'),
    (De: 'Nichts verwendet das Symbol.'; En: 'Nothing uses the symbol.'),
    (De: 'Ungültiger Bereich %d-%d; die Datei hat %d Zeilen'; En: 'Invalid range %d-%d; the file has %d lines'),
    (De: '%s ist nicht lesbar; ohne Bereich den ganzen Text angeben';
     En: '%s is not readable; give the whole text without a range'),
    (De: '%d:%d: warning [unresolved-identifier] "%s" ist nicht auflösbar; gemeint ist %s? ({$SCOPEDENUMS ON})';
     En: '%d:%d: warning [unresolved-identifier] "%s" cannot be resolved; did you mean %s? ({$SCOPEDENUMS ON})'),
    (De: '%d:%d: warning [unresolved-identifier] "%s" ist nicht auflösbar';
     En: '%d:%d: warning [unresolved-identifier] "%s" cannot be resolved'),
    (De: 'Keine Befunde in %s.'; En: 'No findings in %s.'),
    (De: 'Hinweis: Unit System ist nicht im Index, Bezeichner wurden nicht geprüft.';
     En: 'Note: unit System is not in the index, identifiers were not checked.'),
    (De: 'Hinweis: Die Namensprüfung kennt keine Überladungen, Generics, Class Helper und with; einzelne Meldungen ' +
      'können Fehlalarme sein.';
     En: 'Note: the name check knows no overloads, generics, class helpers and with; single messages can be false ' +
      'alarms.'),
    (De: '%d Verwendungen von %s (%s:%d), %d sicher, %d erschlossen:';
     En: '%d uses of %s (%s:%d), %d certain, %d inferred:'),
    (De: 'Aufgerufen von:'; En: 'Called by:'),
    (De: 'Ruft auf:'; En: 'Calls:'),
    (De: ', Unit-Ebene'; En: ', unit level'),
    (De: 'Auswirkungen von %s, Tiefe %d: %d Stellen, %d direkt, %d indirekt, %d Tests.';
     En: 'Impact of %s, depth %d: %d places, %d direct, %d indirect, %d tests.'),
    (De: '%d Befunde in %s (Positionen im neuen Text, Zeile:Spalte):';
     En: '%d findings in %s (positions in the new text, line:column):'),
    (De: 'virtuell'; En: 'virtual'),
    (De: ' [%s, 1 Umsetzung]'; En: ' [%s, 1 implementation]'),
    (De: ' [%s, %d Umsetzungen]'; En: ' [%s, %d implementations]'),
    (De: ' – erschlossen (%s): %s'; En: ' – inferred (%s): %s'),
    (De: '… %d weitere'; En: '… %d more'),
    (De: '  %d sicher, %d erschlossen'; En: '  %d certain, %d inferred'),
    (De: '%s    Formular: %s (%s:%d)'; En: '%s    Form: %s (%s:%d)'),
    (De: '  Formular: %s (%s:%d)'; En: '  Form: %s (%s:%d)'),
    (De: 'Betroffene Tests:'; En: 'Affected tests:'),
    (De: '  %s (%s:%d, Ebene %d)'; En: '  %s (%s:%d, level %d)'),
    (De: '… %d weitere Befunde'; En: '… %d more findings'));

{ TMcpCodeTools }

constructor TMcpCodeTools.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
  const AFiles: TReferenceFilesProvider);
begin
  Create(AIndex, AReadText, AFiles, nil);
end;

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
  mLookup: TMcpIndexTools;
  mFound: TArray<TSymbolLocation>;
begin
  AHint := '';
  mLookup := TMcpIndexTools.Create(FIndex, nil);
  try
    mFound := mLookup.Matches(AName);
  finally
    mLookup.Free;
  end;
  Result := Length(mFound) > 0;
  if Result then
  begin
    ALocation := mFound[0];
    if Length(mFound) > 1 then
    begin
      AHint := cTexts[TCodeToolsText.NoteSymbolsOfThisName].Fmt([Length(mFound), ALocation.Symbol.QualifiedName,
        ALocation.UnitName]);
    end;
  end;
end;

function TMcpCodeTools.LineText(const AFileName: string; ALine: Integer): string;
var
  mText: string;
  mLines: TStringList;
begin
  Result := '';
  if not FReadText(AFileName, mText) then
  begin
    Exit;
  end;
  mLines := TStringList.Create;
  try
    mLines.Text := mText;
    if (ALine >= 0) and (ALine < mLines.Count) then
    begin
      Result := Trim(mLines[ALine]);
    end;
  finally
    mLines.Free;
  end;
end;

function TMcpCodeTools.SettingsOf(const AFileName: string): TReferenceSettings;
begin
  if Assigned(FSettingsFor) then
  begin
    Result := FSettingsFor(TDocumentUris.FromPath(AFileName));
  end
  else
  begin
    Result := TReferenceSettings.Default;
  end;
end;

/// <summary>Aufruf über Interface bzw. virtuelle Methode (#1122): " [über Interface, 3 Umsetzungen]".</summary>
function DispatchSuffix(const ACall: THierarchyCall): string;
begin
  Result := '';
  if ACall.Dispatch = TReferenceReason.Interface_ then
  begin
    Result := cTexts[TCodeToolsText.ViaInterface].Text;
  end
  else if ACall.Dispatch = TReferenceReason.Virtual then
  begin
    Result := cTexts[TCodeToolsText.Virtual].Text;
  end
  else
  begin
    Exit;
  end;
  if ACall.Implementations <= 0 then
  begin
    Result := ' [' + Result + ']';
  end
  else if ACall.Implementations = 1 then
  begin
    Result := cTexts[TCodeToolsText.ImplementationText].Fmt([Result]);
  end
  else
  begin
    Result := cTexts[TCodeToolsText.Implementations].Fmt([Result, ACall.Implementations]);
  end;
end;

/// <summary>" – erschlossen (interface): Aufruf über …" für erschlossene Treffer, sonst ''.</summary>
function ConfidenceSuffix(const AConfidence: TReferenceConfidence): string;
begin
  if AConfidence.IsSure then
  begin
    Result := '';
  end
  else
  begin
    Result := cTexts[TCodeToolsText.Inferred].Fmt([AConfidence.ReasonName, AConfidence.Detail]);
  end;
end;

function TMcpCodeTools.QualifiedName(const AFileName: string; ALine, AColumn: Integer;
  AWithParameters: Boolean): string;
var
  mText, mError: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  if (ALine < 1) or (AColumn < 1) then
  begin
    raise EMcpToolError.Create(cTexts[TCodeToolsText.LineAndColumnCountFrom].Text);
  end;
  if not FReadText(AFileName, mText) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TCodeToolsText.FileNotReadable].Text, [AFileName]);
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := FNamespaces;
      if not TQualifiedNames.At(mResolver, FIndex, mTree, TQualifiedNameRequest.Create(AFileName,
        TTextPosition.Create(ALine - 1, AColumn - 1), AWithParameters), Result, mError) then
      begin
        raise EMcpToolError.Create(mError);
      end;
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

function TMcpCodeTools.FindReferences(const ALocation: TSymbolLocation;
  const AText: string): TArray<TReferenceLocation>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mFiles: TArray<string>;
begin
  mFiles := nil;
  if Assigned(FFiles) then
  begin
    mFiles := FFiles();
  end;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := FNamespaces;
      Result := TLspReferences.Find(mResolver, FIndex, mTree, TReferenceSearch.Create(ALocation.FileName,
        ALocation.Symbol.SelectionRange.StartPos, False, mFiles, FReadText), SettingsOf(ALocation.FileName), nil);
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Zahl der sicheren Verwendungen in AFound.</summary>
function SureCount(const AFound: TArray<TReferenceLocation>): Integer;
var
  mReference: TReferenceLocation;
begin
  Result := 0;
  for mReference in AFound do
  begin
    if mReference.Confidence.IsSure then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TMcpCodeTools.AddReferences(ALines: TStrings; const AFound: TArray<TReferenceLocation>; ASure: Boolean;
  var ACount: Integer);
var
  mReference: TReferenceLocation;
begin
  for mReference in AFound do
  begin
    if mReference.Confidence.IsSure <> ASure then
    begin
      Continue;
    end;
    if ACount >= cMaxReferences then
    begin
      Break;
    end;
    Inc(ACount);
    ALines.Add(Format('%s:%d: %s%s', [mReference.FileName, mReference.Range.StartPos.Line + 1,
      LineText(mReference.FileName, mReference.Range.StartPos.Line), ConfidenceSuffix(mReference.Confidence)]));
  end;
end;

function TMcpCodeTools.References(const AName: string): string;
var
  mLocation: TSymbolLocation;
  mHint, mText: string;
  mFound: TArray<TReferenceLocation>;
  mLines: TStringList;
  mCount, mSure: Integer;
begin
  if not Locate(AName, mLocation, mHint) then
  begin
    Exit(cTexts[TCodeToolsText.NoSymbolInTheIndex].Fmt([AName]));
  end;
  if not FReadText(mLocation.FileName, mText) then
  begin
    Exit(cTexts[TCodeToolsText.FileNotReadable2].Fmt([mLocation.FileName]));
  end;
  mFound := FindReferences(mLocation, mText);
  mSure := SureCount(mFound);
  mLines := TStringList.Create;
  try
    mLines.Add(cTexts[TCodeToolsText.UsesOfCertainInferred].Fmt([Length(mFound),
      mLocation.Symbol.QualifiedName, mLocation.FileName, mLocation.Symbol.SelectionRange.StartPos.Line + 1, mSure,
      Length(mFound) - mSure]));
    // Erst die sicheren, dann die erschlossenen: Nur die sicheren ändert ein Umbenennen ohne Prüfung.
    mCount := 0;
    AddReferences(mLines, mFound, True, mCount);
    if (mSure < Length(mFound)) and (mCount < cMaxReferences) then
    begin
      mLines.Add(cTexts[TCodeToolsText.InferredCheckBeforeRenaming].Text);
    end;
    AddReferences(mLines, mFound, False, mCount);
    if mCount < Length(mFound) then
    begin
      mLines.Add(cTexts[TCodeToolsText.More].Fmt([Length(mFound) - mCount]));
    end;
    if mHint <> '' then
    begin
      mLines.Add(mHint);
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

function DescribeItem(const AItem: THierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Container <> '' then
  begin
    Result := AItem.Container + '.' + Result;
  end;
  Result := Format('%s – Unit %s, %s:%d', [Result, AItem.UnitName, AItem.FileName,
    AItem.SelectionRange.StartPos.Line + 1]);
end;

procedure AddCalls(ALines: TStrings; const ATitle, AArrow: string; const ACalls: TArray<THierarchyCall>);
var
  mCall: THierarchyCall;
  mSure, mRound: Integer;
begin
  ALines.Add(ATitle);
  if Length(ACalls) = 0 then
  begin
    ALines.Add(cTexts[TCodeToolsText.None].Text);
  end;
  mSure := 0;
  for mCall in ACalls do
  begin
    if mCall.Confidence.IsSure then
    begin
      Inc(mSure);
    end;
  end;
  // Sichere Aufrufer zuerst, erschlossene mit Grund danach (#1119).
  for mRound := 0 to 1 do
  begin
    for mCall in ACalls do
    begin
      if mCall.Confidence.IsSure = (mRound = 0) then
      begin
        ALines.Add(Format('  %s %s (%d×)%s%s', [AArrow, DescribeItem(mCall.Item), Length(mCall.Ranges),
          DispatchSuffix(mCall), ConfidenceSuffix(mCall.Confidence)]));
      end;
    end;
  end;
  if mSure < Length(ACalls) then
  begin
    ALines.Add(cTexts[TCodeToolsText.CertainInferred].Fmt([mSure, Length(ACalls) - mSure]));
  end;
end;

/// <summary>Dateien des Arbeitsbereichs aus AFiles; leer ohne Provider.</summary>
function ProvidedFiles(const AFiles: TReferenceFilesProvider): TArray<string>;
begin
  Result := nil;
  if Assigned(AFiles) then
  begin
    Result := AFiles();
  end;
end;

function TMcpCodeTools.CallHierarchy(const AName: string; ADirection: TMcpCallDirection): string;
var
  mLocation: TSymbolLocation;
  mHint, mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItem: THierarchyItem;
  mFiles: TArray<string>;
  mLines: TStringList;
begin
  if not Locate(AName, mLocation, mHint) then
  begin
    Exit(cTexts[TCodeToolsText.NoSymbolInTheIndex].Fmt([AName]));
  end;
  if not FReadText(mLocation.FileName, mText) then
  begin
    Exit(cTexts[TCodeToolsText.FileNotReadable2].Fmt([mLocation.FileName]));
  end;
  mFiles := ProvidedFiles(FFiles);
  mLines := TStringList.Create;
  try
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
      try
        mResolver.Namespaces := FNamespaces;
        if not TLspHierarchies.CallItemAt(mResolver, mTree, mLocation.FileName,
          mLocation.Symbol.SelectionRange.StartPos, mItem) then
        begin
          Exit(cTexts[TCodeToolsText.IsNotARoutineOr].Fmt([mLocation.Symbol.QualifiedName]));
        end;
        mLines.Add(DescribeItem(mItem));
        if ADirection in [TMcpCallDirection.Incoming, TMcpCallDirection.Both] then
        begin
          AddCalls(mLines, cTexts[TCodeToolsText.CalledBy].Text, '←',
            TLspHierarchies.IncomingCalls(THierarchyCallSource.Create(mResolver, FIndex, FReadText, nil), mItem, mFiles,
            SettingsOf(mItem.FileName)));
        end;
        if ADirection in [TMcpCallDirection.Outgoing, TMcpCallDirection.Both] then
        begin
          AddCalls(mLines, cTexts[TCodeToolsText.Calls].Text, '→',
            TLspHierarchies.OutgoingCalls(mResolver, FIndex, mItem,
            FReadText, nil));
        end;
      finally
        mResolver.Free;
      end;
    finally
      mTree.Free;
    end;
    if mHint <> '' then
    begin
      mLines.Add(mHint);
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

function ImpactOptionsOf(const ATools: TMcpCodeTools; const AProvider: TImpactOptionsProvider;
  const AFileName: string): TImpactOptions;
begin
  if Assigned(AProvider) then
  begin
    Result := AProvider(TDocumentUris.FromPath(AFileName));
  end
  else
  begin
    Result := TImpactOptions.Default;
    Result.References := ATools.SettingsOf(AFileName);
  end;
end;

function TMcpCodeTools.Impact(const AName: string; AJson: Boolean): string;
var
  mLocation: TSymbolLocation;
  mHint: string;
begin
  if not Locate(AName, mLocation, mHint) then
  begin
    Exit(cTexts[TCodeToolsText.NoSymbolInTheIndex].Fmt([AName]));
  end;
  Result := Impact(AName, ImpactOptionsOf(Self, FImpactOptionsFor, mLocation.FileName).Depth, AJson);
end;

function TMcpCodeTools.Impact(const AName: string; ADepth: Integer; AJson: Boolean): string;
var
  mLocation: TSymbolLocation;
  mHint, mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mStart: THierarchyItem;
  mOptions: TImpactOptions;
  mFound: TImpactResult;
  mJson: TJSONObject;
begin
  if not Locate(AName, mLocation, mHint) then
  begin
    Exit(cTexts[TCodeToolsText.NoSymbolInTheIndex].Fmt([AName]));
  end;
  if not FReadText(mLocation.FileName, mText) then
  begin
    Exit(cTexts[TCodeToolsText.FileNotReadable2].Fmt([mLocation.FileName]));
  end;
  mOptions := ImpactOptionsOf(Self, FImpactOptionsFor, mLocation.FileName);
  mOptions.Depth := TImpactAnalysis.ClampDepth(ADepth);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := FNamespaces;
      if not TLspHierarchies.SymbolItemAt(mResolver, mTree, mLocation.FileName,
        mLocation.Symbol.SelectionRange.StartPos, mStart) then
      begin
        Exit(cTexts[TCodeToolsText.ThereIsNoDeclarationFor].Fmt([mLocation.Symbol.QualifiedName]));
      end;
      if Assigned(FFiles) then
      begin
        mFound := TImpactAnalysis.Analyze(mResolver, FIndex, mStart, TImpactSources.Create(FFiles(), FReadText),
          mOptions,
          nil);
      end
      else
      begin
        mFound := TImpactAnalysis.Analyze(mResolver, FIndex, mStart, TImpactSources.Create(nil, FReadText), mOptions,
          nil);
      end;
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
  if not AJson then
  begin
    Exit(ImpactReport(mFound, mHint));
  end;
  mJson := TImpactAnalysis.ToJson(mFound);
  try
    Result := mJson.ToJSON;
  finally
    mJson.Free;
  end;
end;

function ImpactEdgeText(AEdge: TImpactEdge): string;
const
  cTexts: array[TImpactEdge] of TAtlasText = (
    (De: 'Aufruf'; En: 'call'),
    (De: 'Verweis'; En: 'reference'),
    (De: 'Override'; En: 'override'),
    (De: 'überschriebene Basismethode'; En: 'overridden base method'),
    (De: 'Interface-Methode'; En: 'interface method'),
    (De: 'Umsetzung'; En: 'implementation'));
begin
  Result := cTexts[AEdge].Text;
end;

procedure AddImpactPlace(ALines: TStrings; const AResult: TImpactResult; AIndex: Integer; const AIndent: string);
var
  mPlace: TImpactPlace;
  mBinding: TImpactFormBinding;
  mChild: Integer;
  mExtra: string;
begin
  mPlace := AResult.Places[AIndex];
  mExtra := ImpactEdgeText(mPlace.Edge);
  if Length(mPlace.Ranges) > 0 then
  begin
    mExtra := Format('%s, %d×', [mExtra, Length(mPlace.Ranges)]);
  end;
  if mPlace.Terminal then
  begin
    mExtra := mExtra + cTexts[TCodeToolsText.UnitLevel].Text;
  end;
  if mPlace.Test >= 0 then
  begin
    mExtra := mExtra + ', Test';
  end;
  ALines.Add(Format('%s← %s (%s)%s', [AIndent, DescribeItem(mPlace.Item), mExtra, ConfidenceSuffix(mPlace.Confidence)]));
  for mBinding in mPlace.Forms do
  begin
    ALines.Add(cTexts[TCodeToolsText.Form].Fmt([AIndent, mBinding.Text, mBinding.FileName,
      mBinding.Range.StartPos.Line + 1]));
  end;
  // Jede Stelle hat genau eine Ursache: Der Baum endet.
  for mChild := AIndex + 1 to High(AResult.Places) do
  begin
    if AResult.Places[mChild].Cause = AIndex then
    begin
      AddImpactPlace(ALines, AResult, mChild, AIndent + '  ');
    end;
  end;
end;

/// <summary>Kopf von get_impact: Zahlen und Formularbindungen des Symbols selbst.</summary>
procedure AddImpactHead(ALines: TStrings; const AResult: TImpactResult);
var
  mBinding: TImpactFormBinding;
begin
  ALines.Add(cTexts[TCodeToolsText.ImpactOfDepthPlacesDirect].Fmt([DescribeItem(AResult.Symbol), AResult.Depth,
    Length(AResult.Places), AResult.LevelCount(1),
    Length(AResult.Places) - AResult.LevelCount(1), Length(AResult.Tests)]));
  for mBinding in AResult.SymbolForms do
  begin
    ALines.Add(cTexts[TCodeToolsText.Form2].Fmt([mBinding.Text, mBinding.FileName, mBinding.Range.StartPos.Line + 1]));
  end;
end;

procedure AddImpactTests(ALines: TStrings; const AResult: TImpactResult);
var
  mTest: TImpactTest;
begin
  if Length(AResult.Tests) = 0 then
  begin
    ALines.Add(cTexts[TCodeToolsText.NoAffectedTests].Text);
    Exit;
  end;
  ALines.Add(cTexts[TCodeToolsText.AffectedTests].Text);
  for mTest in AResult.Tests do
  begin
    ALines.Add(cTexts[TCodeToolsText.Level].Fmt([mTest.Name, mTest.FileName, mTest.Line + 1, mTest.Level]));
  end;
  ALines.Add('run_tests tests: ' + string.Join(', ', AResult.RunNames));
end;

procedure AddImpactLimits(ALines: TStrings; const AResult: TImpactResult);
begin
  if TImpactLimit.Depth in AResult.Limits then
  begin
    ALines.Add(cTexts[TCodeToolsText.DepthReachedPlacesNotFollowed].Fmt([AResult.Depth, AResult.Unexpanded]));
  end;
  if TImpactLimit.Count in AResult.Limits then
  begin
    ALines.Add(cTexts[TCodeToolsText.MaximumOfPlacesReachedResult].Fmt([AResult.MaxPlaces]));
  end;
  if TImpactLimit.Time in AResult.Limits then
  begin
    ALines.Add(cTexts[TCodeToolsText.TimeLimitOfMsReached].Fmt([AResult.TimeoutMs]));
  end;
end;

class function TMcpCodeTools.ImpactReport(const AResult: TImpactResult; const AHint: string): string;
var
  mLines: TStringList;
  mIndex: Integer;
begin
  mLines := TStringList.Create;
  try
    AddImpactHead(mLines, AResult);
    if Length(AResult.Places) = 0 then
    begin
      mLines.Add(cTexts[TCodeToolsText.NothingUsesTheSymbol].Text);
    end;
    for mIndex := 0 to High(AResult.Places) do
    begin
      if AResult.Places[mIndex].Cause < 0 then
      begin
        AddImpactPlace(mLines, AResult, mIndex, '  ');
      end;
    end;
    AddImpactTests(mLines, AResult);
    AddImpactLimits(mLines, AResult);
    if AHint <> '' then
    begin
      mLines.Add(AHint);
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

function SplitKeepingBreaks(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  // Jede Zeile behält ihren Zeilenwechsel, damit CRLF/LF erhalten bleiben.
  Result := nil;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = #10 then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart + 1)];
      mStart := mIndex + 1;
    end;
  end;
  if mStart <= Length(AText) then
  begin
    Result := Result + [Copy(AText, mStart, MaxInt)];
  end;
end;

class function TMcpCodeTools.ReplaceLines(const AOriginal, AText: string; AStartLine, AEndLine: Integer): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mInserted: string;
begin
  mLines := SplitKeepingBreaks(AOriginal);
  if (AStartLine < 1) or (AStartLine > Length(mLines) + 1) or (AEndLine < AStartLine - 1) or
    (AEndLine > Length(mLines)) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TCodeToolsText.InvalidRangeTheFileHas].Text,
      [AStartLine, AEndLine, Length(mLines)]);
  end;
  mInserted := AText;
  // Der ersetzte Bereich endet mit einem Zeilenwechsel, wenn danach noch etwas kommt.
  if (mInserted <> '') and (AEndLine < Length(mLines)) and not EndsStr(#10, mInserted) then
  begin
    mInserted := mInserted + TTextLines.LineBreakOf(AOriginal);
  end;
  Result := '';
  for mIndex := 0 to AStartLine - 2 do
  begin
    Result := Result + mLines[mIndex];
  end;
  Result := Result + mInserted;
  for mIndex := AEndLine to High(mLines) do
  begin
    Result := Result + mLines[mIndex];
  end;
end;

function TMcpCodeTools.CheckedText(const AFileName, AText: string; AStartLine, AEndLine: Integer): string;
var
  mOriginal: string;
begin
  if AStartLine <= 0 then
  begin
    Exit(AText);
  end;
  if not (Assigned(FReadText) and FReadText(AFileName, mOriginal)) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TCodeToolsText.IsNotReadableGiveThe].Text, [AFileName]);
  end;
  Result := ReplaceLines(mOriginal, AText, AStartLine, AEndLine);
end;

/// <summary>Meldung zu einem nicht auflösbaren Namen, mit Vorschlag, wenn es einen gibt.</summary>
function UnresolvedLine(const AName: TUnresolvedName): string;
begin
  if AName.Code <> '' then
  begin
    Result := Format('%d:%d: warning [unresolved-identifier] %s', [AName.Range.StartPos.Line + 1,
      AName.Range.StartPos.Character + 1, TUnresolvedNames.Describe(AName)]);
  end
  else if AName.Suggestion <> '' then
  begin
    Result := cTexts[TCodeToolsText.WarningUnresolvedIdentifierCannotBe].Fmt([AName.Range.StartPos.Line + 1,
      AName.Range.StartPos.Character + 1, AName.Name,
      AName.Suggestion]);
  end
  else
  begin
    Result := cTexts[TCodeToolsText.WarningUnresolvedIdentifierCannotBe2].Fmt([AName.Range.StartPos.Line + 1,
      AName.Range.StartPos.Character + 1, AName.Name]);
  end;
end;

function TMcpCodeTools.UnresolvedOf(const AFileName, AText: string;
  const ASource: TCheckSource): TArray<TUnresolvedName>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mProcessed: TPreprocessorResult;
begin
  // Nur die aktiven Zweige (#860): Namen eines anderen Zielsystems sind dort nicht auflösbar.
  mTree := TSyntaxTreeCache.ParseActive(AText, ASource.Options, nil, mProcessed);
  try
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := FNamespaces;
      Result := TUnresolvedNames.Find(mResolver, mTree, AFileName);
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Kopf und Hinweise von check_code um die Zeilen ALines.</summary>
procedure FinishCheckReport(ALines: TStrings; ACount: Integer; const AFileName: string; ACheckNames: Boolean);
begin
  if ACount > TMcpCodeTools.cMaxFindings then
  begin
    ALines.Add(cTexts[TCodeToolsText.MoreFindings].Fmt([ACount - TMcpCodeTools.cMaxFindings]));
  end;
  if ACount = 0 then
  begin
    ALines.Insert(0, cTexts[TCodeToolsText.NoFindingsIn].Fmt([ExtractFileName(AFileName)]));
  end
  else
  begin
    ALines.Insert(0, cTexts[TCodeToolsText.FindingsInPositionsInThe].Fmt([ACount,
      ExtractFileName(AFileName)]));
  end;
  if not ACheckNames then
  begin
    ALines.Add(cTexts[TCodeToolsText.NoteUnitSystemIsNot].Text);
  end
  else
  begin
    ALines.Add(cTexts[TCodeToolsText.NoteTheNameCheckKnows].Text);
  end;
end;

function TMcpCodeTools.CheckCode(const AScope: TMcpRuleScope; const AFileName, AText: string; AStartLine,
  AEndLine: Integer): string;
var
  mLines: TStringList;
  mNewText: string;
  mFinding: TRuleFinding;
  mName: TUnresolvedName;
  mCount: Integer;
  mCheckNames: Boolean;
  mSource: TCheckSource;
  mScopes: TFindingScopes;
begin
  mNewText := CheckedText(AFileName, AText, AStartLine, AEndLine);
  mSource := TFileChecker.SourceOf(FCheckSource, AFileName);
  mCheckNames := TUnresolvedNames.Available(FIndex);
  mLines := TStringList.Create;
  try
    mCount := 0;
    for mFinding in TFileChecker.CheckText(AScope.Rules, AScope.Settings, TMcpCheckTools.RelativeTo(AScope.Root,
      AFileName), mNewText,
      TCheckOrigin.Make(TFileChecker.ProjectOf(FCheckProject, AFileName), mSource), mScopes) do
    begin
      Inc(mCount);
      if mCount <= cMaxFindings then
      begin
        mLines.Add(TMcpCheckTools.FindingLine(mFinding));
      end;
    end;
    if mCheckNames then
    begin
      for mName in UnresolvedOf(AFileName, mNewText, mSource) do
      begin
        Inc(mCount);
        if mCount <= cMaxFindings then
        begin
          mLines.Add(UnresolvedLine(mName));
        end;
      end;
    end;
    FinishCheckReport(mLines, mCount, AFileName, mCheckNames);
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

class function TMcpCodeTools.ParseDirection(const AText: string): TMcpCallDirection;
begin
  if SameText(AText, 'incoming') then
  begin
    Result := TMcpCallDirection.Incoming;
  end
  else if SameText(AText, 'outgoing') then
  begin
    Result := TMcpCallDirection.Outgoing;
  end
  else
  begin
    Result := TMcpCallDirection.Both;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.CodeTools', cTexts);

end.
