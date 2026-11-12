unit Atlas.Common.Mcp.EditTools;

// Schreibende MCP-Werkzeuge (#61) nach den Regeln aus #99:
//   rename_symbol      Symbol an Datei:Zeile:Spalte umbenennen, samt .dfm/.fmx
//                      und automatisch benannter Ereignis-Handler (#30)
//   apply_code_action  Korrektur eines Regeltreffers in einer Zeile anwenden
//   fix_findings       Sammelkorrektur (#1352): sichere Korrekturen ausgewählter
//                      Regeln in einer Datei oder im ganzen Projekt (TBulkFix);
//                      im Editor ungespeicherte Dateien bleiben unberührt und
//                      werden genannt, in der IDE offene gehen über das Plugin
//                      als ein Rückgängig-Schritt je Datei (#397)
//   format_code        Datei oder geplanten Text nach den Formatregeln des
//                      Projekts formatieren (#1358), ganz oder einen Zeilenbereich
// dryRun (Vorgabe true) liefert nur den Diff und schreibt nichts. Mit
// dryRun=false wird atomar geschrieben: alle neuen Texte werden vorher
// berechnet; hat sich eine Datei seit dem Lesen geändert oder ist sie im Editor
// ungespeichert geändert (Liste des IDE-Plugins), bricht der Aufruf ohne
// Änderung ab; scheitert das Schreiben einer Datei, werden die schon
// geschriebenen zurückgesetzt. Geänderte Dateien gehen ins Protokoll (Audit).
// apply_code_action prüft mit den Symbolen des Projekts (CheckSource, #860) und
// mit Symbolindex und Projektdiensten (CheckProject, #1112) wie der Server.
// rename_symbol ändert nur sichere Stellen (#1119); erschlossene nennt der
// Bericht unter „Nicht geändert, bitte prüfen“.
// format_code schreibt über denselben Weg (offene Dateien über das Plugin als
// ein Rückgängig-Schritt, #397); mit Text statt Datei liefert es nur den
// formatierten Text. Dateien mit Syntaxfehlern formatiert es nicht. Die
// Zeilenenden der Datei bleiben dabei; format.endOfLine setzt --format-write um.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Lsp.References,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Mcp.Contract;

type
  TMcpFileEdit = record
    FileName: string;
    Range: TTextRange;
    NewText: string;
    class function Create(const AFileName: string; const ARange: TTextRange;
      const ANewText: string): TMcpFileEdit; static;
  end;

  /// <summary>Schreibt AText nach AFileName (Kodierung und Zeilenenden erhalten); Fehler als Exception.</summary>
  TMcpWriteText = reference to procedure(const AFileName, AText: string);
  /// <summary>Im Editor ungespeichert geänderte Dateien (IDE-Plugin); leer ohne Editor.</summary>
  TMcpDirtyFiles = reference to function: TArray<string>;
  TMcpAudit = reference to procedure(const AText: string);

  TMcpEditTools = class
  private
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FWriteText: TMcpWriteText;
    FProjectFiles: TFunc<TArray<string>>;
    FEnsureUnit: TEnsureUnitFunc;
    FDirtyFiles: TMcpDirtyFiles;
    FAudit: TMcpAudit;
    FNamespaces: TArray<string>;
    FCheckSource: TCheckSourceFunc;
    FCheckProject: TCheckProjectFunc;
    FSettingsFor: TReferenceSettingsProvider;
    procedure ReadAll(const ANames: TArray<string>; const AGroups: TArray<TArray<TMcpFileEdit>>;
      out AOldTexts, ANewTexts: TArray<string>);
    procedure EnsureWritable(const ANames, AOldTexts: TArray<string>);
    procedure WriteAll(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>);
    function RenameEdits(const AFileName: string; ALine, AColumn: Integer; const ANewName: string;
      out AUnchanged: TArray<TReferenceLocation>): TArray<TMcpFileEdit>;
    function ActionsAt(const AScope: TMcpRuleScope; const AFileName: string; ALine: Integer): TArray<TCodeAction>;
    function RunFixes(const AScope: TMcpRuleScope; const AFiles: TArray<string>; const AOptions: TBulkFixOptions;
      const AFixRules: TArray<IRule>; ADryRun: Boolean; out AUntouched: TArray<string>): TArray<TBulkFixFile>;
    procedure WriteFixes(const AFixRules: TArray<string>; const AResults: TArray<TBulkFixFile>);
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AWriteText: TMcpWriteText; const AProjectFiles: TFunc<TArray<string>>;
      const AEnsureUnit: TEnsureUnitFunc);
    /// <summary>Wendet Edits einer Datei auf AText an (von hinten nach vorn).</summary>
    class function ApplyToText(const AText: string; const AEdits: TArray<TMcpFileEdit>): string; static;
    /// <summary>Zeilen-Diff (- alt, + neu) mit Zeilennummern des alten Texts.</summary>
    class function Diff(const AFileName, AOld, ANew: string): string; static;
    /// <summary>Plant bzw. schreibt AEdits (siehe Unit-Kopf); liefert den Bericht.</summary>
    function Apply(const ATool: string; const AEdits: TArray<TMcpFileEdit>; ADryRun: Boolean): string;
    function RenameSymbol(const AFileName: string; ALine, AColumn: Integer; const ANewName: string;
      ADryRun: Boolean): string;
    /// <summary>Ohne ATitle: verfügbare Korrekturen der Zeile auflisten, nichts ändern.</summary>
    function ApplyCodeAction(const AScope: TMcpRuleScope; const AFileName: string; ALine: Integer;
      const ATitle: string; ADryRun: Boolean): string;
    /// <summary>fix_findings (#1352): sichere Korrekturen von AFixRules ("all" = alle) in AFiles; AMinConfidence ''
    /// = fix.minConfidence, sonst nur höher. Liefert Zusammenfassung und Diff.</summary>
    function FixFindings(const AScope: TMcpRuleScope; const AFiles, AFixRules: TArray<string>;
      const AMinConfidence: string; ADryRun: Boolean): string;
    /// <summary>format_code mit Text (#1358): formatiert AText (geplanter Inhalt von AFileName) nach AStyle und
    /// liefert die Abweichungen und den formatierten Text; schreibt nichts.</summary>
    function FormatCode(const AStyle: TFormatStyle; const AFileName, AText: string;
      const AScope: TFormatScope): string; overload;
    /// <summary>format_code für die Datei (#1358): Vorschau als Diff bzw. mit ADryRun = False schreiben wie
    /// apply_code_action.</summary>
    function FormatCode(const AStyle: TFormatStyle; const AFileName: string; const AScope: TFormatScope;
      ADryRun: Boolean): string; overload;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Liest Dateien wie die Werkzeuge selbst (extract_method, #2054).</summary>
    property ReadText: TReferenceReadText read FReadText;
    property DirtyFiles: TMcpDirtyFiles read FDirtyFiles write FDirtyFiles;
    property Audit: TMcpAudit read FAudit write FAudit;
    /// <summary>Symbole und Include-Dateien für die Regelprüfung (#860); nil = Vordefinitionen (Win32).</summary>
    property CheckSource: TCheckSourceFunc read FCheckSource write FCheckSource;
    /// <summary>Projekt, Symbolindex und Projektdienste für die Regelprüfung (#1112); nil = ohne Index.</summary>
    property CheckProject: TCheckProjectFunc read FCheckProject write FCheckProject;
    /// <summary>Einstellungen references.* (#1119); nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Mcp.Server,
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditToolsText = (IsNotReadableNothingChanged, HasUnsavedChangesInThe, HasBeenChangedInThe, NoChanges,
    PreviewDryRunChangesInFiles, ChangesWrittenInFiles, IsNotReadable, NotChangedPleaseCheckInferred,
    ThereIsNoSymbolThat, NoFixInLineAvailable, FixesInLineApplyWith, NoFixInLine, RepeatWithDryRunFalseTo,
    NotTouchedUnsavedChangesIn, ArgumentRulesMissingRuleIds, DeviationsFromTheFormatRules, AndMore,
    NoteTheFormattingIsNot, SyntaxErrorInLineNot, NoDeviationFromTheFormat, NoDeviationFromTheFormat2,
    OnlyTheLineEndingsDiffer, Line, FormattedTextPascal);

const
  cTexts: array[TEditToolsText] of TAtlasText = (
    (De: '%s ist nicht lesbar; nichts geändert.'; En: '%s is not readable; nothing changed.'),
    (De: '%s hat ungespeicherte Änderungen im Editor; nichts geändert. Erst in der IDE speichern.';
     En: '%s has unsaved changes in the editor; nothing changed. Save in the IDE first.'),
    (De: '%s wurde inzwischen geändert; nichts geändert.';
     En: '%s has been changed in the meantime; nothing changed.'),
    (De: 'Keine Änderungen.'; En: 'No changes.'),
    (De: 'Vorschau (dryRun): %d Änderungen in %d Dateien, nichts geschrieben. Zum Schreiben mit dryRun=false ' +
      'wiederholen.';
     En: 'Preview (dryRun): %d changes in %d files, nothing written. Repeat with dryRun=false to write.'),
    (De: '%d Änderungen in %d Dateien geschrieben.'; En: '%d changes written in %d files.'),
    (De: '%s ist nicht lesbar'; En: '%s is not readable'),
    (De: 'Nicht geändert, bitte prüfen (%d erschlossene Stellen):';
     En: 'Not changed, please check (%d inferred places):'),
    (De: 'An dieser Stelle steht kein umbenennbares Symbol.';
     En: 'There is no symbol that can be renamed at this position.'),
    (De: 'Keine Korrektur "%s" in Zeile %d. Verfügbar:'; En: 'No fix "%s" in line %d. Available:'),
    (De: 'Korrekturen in Zeile %d (mit title anwenden):'; En: 'Fixes in line %d (apply with title):'),
    (De: 'Keine Korrektur in Zeile %d.'; En: 'No fix in line %d.'),
    (De: 'Zum Schreiben mit dryRun=false wiederholen.'; En: 'Repeat with dryRun=false to write.'),
    (De: 'Nicht angefasst (ungespeicherte Änderungen im Editor): %s';
     En: 'Not touched (unsaved changes in the editor): %s'),
    (De: 'Argument "rules" fehlt: Regelkennungen oder "all"'; En: 'Argument "rules" missing: rule ids or "all"'),
    (De: '%s: %d Abweichungen von den Formatregeln'; En: '%s: %d deviations from the format rules'),
    (De: '- … und %d weitere'; En: '- … and %d more'),
    (De: 'Hinweis: Die Formatierung ist nicht stabil, ein zweiter Lauf ändert erneut.';
     En: 'Note: the formatting is not stable, a second run changes it again.'),
    (De: '%s: Syntaxfehler in Zeile %d, nicht formatiert: %s'; En: '%s: syntax error in line %d, not formatted: %s'),
    (De: 'Keine Abweichung von den Formatregeln; der Text bleibt, wie er ist.';
     En: 'No deviation from the format rules; the text stays as it is.'),
    (De: '%s: keine Abweichung von den Formatregeln.'; En: '%s: no deviation from the format rules.'),
    (De: 'Nur die Zeilenenden weichen ab (format.endOfLine); format_code ändert sie nicht, dafür AtlasServer --check ' +
      '<Datei> --format-write verwenden.';
     En: 'Only the line endings differ (format.endOfLine); format_code does not change them, use AtlasServer --check ' +
      '<file> --format-write for that.'),
    (De: '- Zeile %d: %s'; En: '- Line %d: %s'),
    (De: 'Formatierter Text:' + sLineBreak + '```pascal' + sLineBreak + '%s' + sLineBreak + '```';
     En: 'Formatted text:' + sLineBreak + '```pascal' + sLineBreak + '%s' + sLineBreak + '```'));

{$SCOPEDENUMS OFF}

{ TMcpFileEdit }

class function TMcpFileEdit.Create(const AFileName: string; const ARange: TTextRange;
  const ANewText: string): TMcpFileEdit;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.NewText := ANewText;
end;

{ TMcpEditTools }

constructor TMcpEditTools.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
  const AWriteText: TMcpWriteText; const AProjectFiles: TFunc<TArray<string>>;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FWriteText := AWriteText;
  FProjectFiles := AProjectFiles;
  FEnsureUnit := AEnsureUnit;
end;

class function TMcpEditTools.ApplyToText(const AText: string; const AEdits: TArray<TMcpFileEdit>): string;
var
  mSorted: TArray<TMcpFileEdit>;
  mEdit: TMcpFileEdit;
  mStartOffset, mEndOffset: Integer;
  mLines: TLineTable;
begin
  mSorted := Copy(AEdits);
  TArray.Sort<TMcpFileEdit>(mSorted, TComparer<TMcpFileEdit>.Construct(
    function(const A, B: TMcpFileEdit): Integer
    begin
      Result := B.Range.StartPos.Line - A.Range.StartPos.Line;
      if Result = 0 then
      begin
        Result := B.Range.StartPos.Character - A.Range.StartPos.Character;
      end;
    end));
  Result := AText;
  for mEdit in mSorted do
  begin
    // Zeilen wie LSP (CRLF, LF, CR); Zeichen hinter dem Zeilenende zählen als Zeilenende.
    mLines := TLineTable.Build(Result);
    mStartOffset := mLines.OffsetAt(mEdit.Range.StartPos);
    mEndOffset := mLines.OffsetAt(mEdit.Range.EndPos);
    Result := Copy(Result, 1, mStartOffset) + mEdit.NewText + Copy(Result, mEndOffset + 1, MaxInt);
  end;
end;

class function TMcpEditTools.Diff(const AFileName, AOld, ANew: string): string;
var
  mLine: string;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.AppendFormat('--- %s', [AFileName]).AppendLine;
    // Gleiche Zeilenzahl (z. B. Umbenennen): nur die geänderten Zeilen, sonst der geänderte Block.
    for mLine in TTextDiff.ChangedLines(TTextLines.SplitLines(AOld), TTextLines.SplitLines(ANew)) do
    begin
      mBuilder.AppendLine(mLine);
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Edits je Datei in der Reihenfolge des ersten Auftretens; ANames die Dateien dazu.</summary>
function GroupByFile(const AEdits: TArray<TMcpFileEdit>; out ANames: TArray<string>): TArray<TArray<TMcpFileEdit>>;
var
  mPositions: TDictionary<string, Integer>;
  mEdit: TMcpFileEdit;
  mPosition: Integer;
begin
  Result := nil;
  ANames := nil;
  mPositions := TDictionary<string, Integer>.Create;
  try
    for mEdit in AEdits do
    begin
      if not mPositions.TryGetValue(AnsiLowerCase(mEdit.FileName), mPosition) then
      begin
        mPosition := Length(ANames);
        mPositions.Add(AnsiLowerCase(mEdit.FileName), mPosition);
        ANames := ANames + [mEdit.FileName];
        SetLength(Result, mPosition + 1);
      end;
      Result[mPosition] := Result[mPosition] + [mEdit];
    end;
  finally
    mPositions.Free;
  end;
end;

/// <summary>Steht AName (ohne Groß-/Kleinschreibung) in ANames?</summary>
function ContainsName(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>AFileName relativ zu ARoot, wenn sie darunter liegt; sonst unverändert.</summary>
function RelativeTo(const ARoot, AFileName: string): string;
begin
  Result := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
  begin
    Result := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  end;
end;

procedure TMcpEditTools.ReadAll(const ANames: TArray<string>; const AGroups: TArray<TArray<TMcpFileEdit>>;
  out AOldTexts, ANewTexts: TArray<string>);
var
  mIndex: Integer;
begin
  SetLength(AOldTexts, Length(ANames));
  SetLength(ANewTexts, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    if not FReadText(ANames[mIndex], AOldTexts[mIndex]) then
    begin
      raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.IsNotReadableNothingChanged].Text, [ANames[mIndex]]);
    end;
    ANewTexts[mIndex] := ApplyToText(AOldTexts[mIndex], AGroups[mIndex]);
  end;
end;

procedure TMcpEditTools.EnsureWritable(const ANames, AOldTexts: TArray<string>);
var
  mDirty, mCurrent: string;
  mIndex: Integer;
begin
  // Keine Kollision mit ungespeicherten Änderungen im Editor.
  if Assigned(FDirtyFiles) then
  begin
    for mDirty in FDirtyFiles() do
    begin
      if ContainsName(ANames, mDirty) then
      begin
        raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.HasUnsavedChangesInThe].Text, [mDirty]);
      end;
    end;
  end;
  // Seit dem Lesen geändert? Dann nichts schreiben.
  for mIndex := 0 to High(ANames) do
  begin
    if not FReadText(ANames[mIndex], mCurrent) or (mCurrent <> AOldTexts[mIndex]) then
    begin
      raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.HasBeenChangedInThe].Text, [ANames[mIndex]]);
    end;
  end;
end;

procedure TMcpEditTools.WriteAll(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>);
begin
  // Alles oder nichts: Scheitert eine Datei, setzt TBulkFix die schon geschriebenen zurück.
  try
    TBulkFix.WriteAll(ANames, AOldTexts, ANewTexts,
      procedure(const AFileName, AText: string)
      begin
        FWriteText(AFileName, AText);
      end);
  except
    on E: EBulkFixWrite do
      raise EMcpToolError.Create(E.Message);
  end;
  if Assigned(FAudit) then
  begin
    FAudit(Format('MCP %s hat geschrieben: %s', [ATool, TLogMarks.Path(string.Join(', ', ANames))]));
  end;
end;

function TMcpEditTools.Apply(const ATool: string; const AEdits: TArray<TMcpFileEdit>; ADryRun: Boolean): string;
var
  mNames, mOldTexts, mNewTexts: TArray<string>;
  mGroups: TArray<TArray<TMcpFileEdit>>;
  mIndex: Integer;
  mReport: TStringBuilder;
begin
  if Length(AEdits) = 0 then
  begin
    raise EMcpToolError.Create(cTexts[TEditToolsText.NoChanges].Text);
  end;
  mGroups := GroupByFile(AEdits, mNames);
  ReadAll(mNames, mGroups, mOldTexts, mNewTexts);
  mReport := TStringBuilder.Create;
  try
    if ADryRun then
    begin
      mReport.AppendFormat(cTexts[TEditToolsText.PreviewDryRunChangesInFiles].Text, [Length(AEdits),
        Length(mNames)]).AppendLine;
    end
    else
    begin
      EnsureWritable(mNames, mOldTexts);
      WriteAll(ATool, mNames, mOldTexts, mNewTexts);
      mReport.AppendFormat(cTexts[TEditToolsText.ChangesWrittenInFiles].Text, [Length(AEdits),
        Length(mNames)]).AppendLine;
    end;
    for mIndex := 0 to High(mNames) do
    begin
      mReport.AppendLine;
      mReport.AppendLine(Diff(mNames[mIndex], mOldTexts[mIndex], mNewTexts[mIndex]));
    end;
    Result := TrimRight(mReport.ToString);
  finally
    mReport.Free;
  end;
end;

function TMcpEditTools.RenameEdits(const AFileName: string; ALine, AColumn: Integer; const ANewName: string;
  out AUnchanged: TArray<TReferenceLocation>): TArray<TMcpFileEdit>;
var
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mRenames: TArray<TRenameEdit>;
  mRename: TRenameEdit;
  mSettings: TReferenceSettings;
begin
  if not FReadText(AFileName, mText) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.IsNotReadable].Text, [AFileName]);
  end;
  mSettings := TReferenceSettings.Default;
  if Assigned(FSettingsFor) then
  begin
    mSettings := FSettingsFor(TDocumentUris.FromPath(AFileName));
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := FNamespaces;
      try
        mRenames := TLspRename.Edits(mResolver, FIndex, mTree, TReferenceSearch.Create(AFileName,
          TTextPosition.Create(ALine - 1, AColumn - 1), True, FProjectFiles(), FReadText),
          TRenameRequest.Create(ANewName, True, mSettings, nil), AUnchanged);
      except
        on E: EJsonRpcError do
          raise EMcpToolError.Create(E.Message);
      end;
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
  Result := nil;
  for mRename in mRenames do
  begin
    Result := Result + [TMcpFileEdit.Create(mRename.FileName, mRename.Range, mRename.NewText)];
  end;
end;

/// <summary>Erschlossene Stellen, die rename_symbol nicht geändert hat; '' ohne.</summary>
function UnchangedReport(const AUnchanged: TArray<TReferenceLocation>): string;
var
  mLocation: TReferenceLocation;
begin
  Result := '';
  if Length(AUnchanged) = 0 then
  begin
    Exit;
  end;
  Result := sLineBreak + sLineBreak + cTexts[TEditToolsText.NotChangedPleaseCheckInferred].Fmt([Length(AUnchanged)]);
  for mLocation in AUnchanged do
  begin
    Result := Result + sLineBreak + Format('%s:%d:%d – %s: %s', [mLocation.FileName,
      mLocation.Range.StartPos.Line + 1, mLocation.Range.StartPos.Character + 1, mLocation.Confidence.ReasonName,
      mLocation.Confidence.Detail]);
  end;
end;

function TMcpEditTools.RenameSymbol(const AFileName: string; ALine, AColumn: Integer; const ANewName: string;
  ADryRun: Boolean): string;
var
  mEdits: TArray<TMcpFileEdit>;
  mUnchanged: TArray<TReferenceLocation>;
begin
  mEdits := RenameEdits(AFileName, ALine, AColumn, ANewName, mUnchanged);
  if Length(mEdits) = 0 then
  begin
    raise EMcpToolError.Create(cTexts[TEditToolsText.ThereIsNoSymbolThat].Text);
  end;
  Result := Apply('rename_symbol', mEdits, ADryRun) + UnchangedReport(mUnchanged);
end;

function TMcpEditTools.ActionsAt(const AScope: TMcpRuleScope; const AFileName: string;
  ALine: Integer): TArray<TCodeAction>;
var
  mText: string;
  mAction: TCodeAction;
  mScopes: TFindingScopes;
begin
  if not FReadText(AFileName, mText) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.IsNotReadable].Text, [AFileName]);
  end;
  Result := nil;
  for mAction in TRuleCodeActions.ForRange(TFileChecker.CheckText(AScope.Rules, AScope.Settings,
    RelativeTo(AScope.Root, AFileName), mText, TCheckOrigin.ForFile(FCheckProject, FCheckSource, AFileName),
    mScopes), mText,
    TTextRange.Create(ALine - 1, 0, ALine - 1, MaxInt div 2)) do
  begin
    if (Length(mAction.Edits) > 0) and (mAction.Command = '') then
    begin
      Result := Result + [mAction];
    end;
  end;
end;

/// <summary>Korrektur mit Titel oder Regelkennung ATitle; -1 ohne.</summary>
function ChosenAction(const AActions: TArray<TCodeAction>; const ATitle: string): Integer;
var
  mIndex: Integer;
begin
  // Über die Regelkennung nur echte Korrekturen: Unterdrücken behebt nichts und braucht seinen Titel (#1109).
  for mIndex := 0 to High(AActions) do
  begin
    if SameText(AActions[mIndex].Title, ATitle) or (SameText(AActions[mIndex].RuleId, ATitle) and
      not MatchStr(AActions[mIndex].Tag, [cRuleSuppressLineTag, cRuleSuppressFileTag])) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Liste der Korrekturen der Zeile; mit ATitle als Hinweis, dass es diese nicht gibt.</summary>
function ActionList(const AActions: TArray<TCodeAction>; const ATitle: string; ALine: Integer): string;
var
  mAction: TCodeAction;
begin
  if ATitle <> '' then
  begin
    Result := cTexts[TEditToolsText.NoFixInLineAvailable].Fmt([ATitle, ALine]);
  end
  else
  begin
    Result := cTexts[TEditToolsText.FixesInLineApplyWith].Fmt([ALine]);
  end;
  for mAction in AActions do
  begin
    Result := Result + sLineBreak + Format('- %s [%s]', [mAction.Title, mAction.RuleId]);
  end;
end;

function TMcpEditTools.ApplyCodeAction(const AScope: TMcpRuleScope; const AFileName: string; ALine: Integer;
  const ATitle: string; ADryRun: Boolean): string;
var
  mActions: TArray<TCodeAction>;
  mChosen: Integer;
  mEdit: TRuleEdit;
  mEdits: TArray<TMcpFileEdit>;
begin
  mActions := ActionsAt(AScope, AFileName, ALine);
  if Length(mActions) = 0 then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.NoFixInLine].Text, [ALine]);
  end;
  mChosen := -1;
  if ATitle <> '' then
  begin
    mChosen := ChosenAction(mActions, ATitle);
    if mChosen < 0 then
    begin
      raise EMcpToolError.Create(ActionList(mActions, ATitle, ALine));
    end;
  end;
  if mChosen < 0 then
  begin
    Exit(ActionList(mActions, '', ALine));
  end;
  mEdits := nil;
  for mEdit in mActions[mChosen].Edits do
  begin
    mEdits := mEdits + [TMcpFileEdit.Create(AFileName, mEdit.Range, mEdit.NewText)];
  end;
  Result := Format('Korrektur: %s', [mActions[mChosen].Title]) + sLineBreak +
    Apply('apply_code_action', mEdits, ADryRun);
end;

function TMcpEditTools.RunFixes(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
  const AOptions: TBulkFixOptions; const AFixRules: TArray<IRule>; ADryRun: Boolean;
  out AUntouched: TArray<string>): TArray<TBulkFixFile>;
var
  mDirtyFiles: TArray<string>;
  mFileName, mText: string;
  mSource: TCheckSource;
begin
  // Ungespeicherte Dateien der IDE nicht anfassen; die übrigen laufen weiter.
  mDirtyFiles := nil;
  if not ADryRun and Assigned(FDirtyFiles) then
  begin
    mDirtyFiles := FDirtyFiles();
  end;
  Result := nil;
  AUntouched := nil;
  for mFileName in AFiles do
  begin
    if ContainsName(mDirtyFiles, mFileName) then
    begin
      AUntouched := AUntouched + [mFileName];
    end
    else if FReadText(mFileName, mText) then
    begin
      mSource := TFileChecker.SourceOf(FCheckSource, mFileName);
      Result := Result + [TBulkFix.Run(mFileName, mText, AOptions, TBulkFix.CheckWith(AFixRules, AScope.Settings,
        RelativeTo(AScope.Root, mFileName), TFileChecker.ProjectOf(FCheckProject, mFileName), mSource),
        TBulkFix.SyntaxErrorsWith(mSource))];
    end;
  end;
end;

procedure TMcpEditTools.WriteFixes(const AFixRules: TArray<string>; const AResults: TArray<TBulkFixFile>);
var
  mResult: TBulkFixFile;
  mCurrent: string;
  mNames: TArray<string>;
begin
  // Seit dem Lesen geändert? Dann nichts schreiben.
  mNames := nil;
  for mResult in AResults do
  begin
    if mResult.Changed and (not FReadText(mResult.FileName, mCurrent) or (mCurrent <> mResult.OldText)) then
    begin
      raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.HasBeenChangedInThe].Text, [mResult.FileName]);
    end;
    if mResult.Changed then
    begin
      mNames := mNames + [mResult.FileName];
    end;
  end;
  try
    TBulkFix.WriteAll(AResults,
      procedure(const AFileName, AText: string)
      begin
        FWriteText(AFileName, AText);
      end);
  except
    on E: EBulkFixWrite do
      raise EMcpToolError.Create(E.Message);
  end;
  if Assigned(FAudit) and (mNames <> nil) then
  begin
    FAudit(Format('MCP fix_findings (%s) hat geschrieben: %s', [string.Join(', ', AFixRules),
      TLogMarks.Path(string.Join(', ', mNames))]));
  end;
end;

/// <summary>Bericht von fix_findings: Zusammenfassung, nicht angefasste Dateien und Diff je geänderter Datei.
/// </summary>
function FixReport(const ARoot: string; const AResults: TArray<TBulkFixFile>; const AUntouched: TArray<string>;
  ADryRun: Boolean): string;
var
  mReport: TStringBuilder;
  mFileName: string;
  mResult: TBulkFixFile;
begin
  mReport := TStringBuilder.Create;
  try
    mReport.AppendLine(TBulkFix.Summary(AResults, ADryRun, sLineBreak));
    if ADryRun then
    begin
      mReport.AppendLine(cTexts[TEditToolsText.RepeatWithDryRunFalseTo].Text);
    end;
    for mFileName in AUntouched do
    begin
      mReport.AppendFormat(cTexts[TEditToolsText.NotTouchedUnsavedChangesIn].Text, [mFileName]).AppendLine;
    end;
    for mResult in AResults do
    begin
      if mResult.Changed then
      begin
        mReport.AppendLine.Append(TBulkFix.Diff(StringReplace(RelativeTo(ARoot, mResult.FileName), '\', '/',
          [rfReplaceAll]), mResult));
      end;
    end;
    Result := TrimRight(mReport.ToString);
  finally
    mReport.Free;
  end;
end;

function TMcpEditTools.FixFindings(const AScope: TMcpRuleScope; const AFiles, AFixRules: TArray<string>;
  const AMinConfidence: string; ADryRun: Boolean): string;
var
  mConfidence: TRuleConfidence;
  mError: string;
  mUntouched: TArray<string>;
  mResults: TArray<TBulkFixFile>;
begin
  if AFixRules = nil then
  begin
    raise EMcpToolError.Create(cTexts[TEditToolsText.ArgumentRulesMissingRuleIds].Text);
  end;
  if not TBulkFix.MinConfidenceOf(AScope.Settings.FixMinConfidence, AMinConfidence, mConfidence, mError) then
  begin
    raise EMcpToolError.Create(mError);
  end;
  mResults := RunFixes(AScope, AFiles, TBulkFixOptions.Create(AFixRules, mConfidence, TRuleCatalog.Shared.Entries),
    TBulkFix.RulesFor(AScope.Rules, AFixRules), ADryRun, mUntouched);
  if not ADryRun then
  begin
    WriteFixes(AFixRules, mResults);
  end;
  Result := FixReport(AScope.Root, mResults, mUntouched, ADryRun);
end;

/// <summary>Ergebnis von format_code ohne Syntaxfehler: Zahl und erste Abweichungen; '' ohne Abweichung.</summary>
function DeviationReport(const AFileName: string; const AOutcome: TFormatOutcome): string;
const
  cShown = 20;
var
  mLines: TArray<string>;
  mShown: Integer;
  mIndex: Integer;
begin
  mShown := Length(AOutcome.Deviations);
  if mShown > cShown then
  begin
    mShown := cShown;
  end;
  SetLength(mLines, mShown + 1);
  mLines[0] := cTexts[TEditToolsText.DeviationsFromTheFormatRules].Fmt([ExtractFileName(AFileName),
    Length(AOutcome.Deviations)]);
  for mIndex := 0 to mShown - 1 do
  begin
    mLines[mIndex + 1] := cTexts[TEditToolsText.Line].Fmt([AOutcome.Deviations[mIndex].Line + 1,
      AOutcome.Deviations[mIndex].Message]);
  end;
  if Length(AOutcome.Deviations) > cShown then
  begin
    mLines := mLines + [cTexts[TEditToolsText.AndMore].Fmt([Length(AOutcome.Deviations) - cShown])];
  end;
  if not AOutcome.Stable then
  begin
    mLines := mLines + [cTexts[TEditToolsText.NoteTheFormattingIsNot].Text];
  end;
  Result := string.Join(sLineBreak, mLines);
end;

/// <summary>Formatiert AText; EMcpToolError bei Syntaxfehlern.</summary>
function FormatOrFail(const AStyle: TFormatStyle; const AFileName, AText: string; const AScope: TFormatScope;
  const ASource: TCheckSource): TFormatOutcome;
begin
  Result := TFormatCheck.Run(AText, AStyle, AScope, ASource.Options);
  if Result.HasSyntaxError then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.SyntaxErrorInLineNot].Text,
      [ExtractFileName(AFileName), Result.SyntaxError.StartPos.Line + 1, Result.SyntaxError.Message]);
  end;
end;

function TMcpEditTools.FormatCode(const AStyle: TFormatStyle; const AFileName, AText: string;
  const AScope: TFormatScope): string;
var
  mOutcome: TFormatOutcome;
begin
  mOutcome := FormatOrFail(AStyle, AFileName, AText, AScope, TFileChecker.SourceOf(FCheckSource, AFileName));
  if not mOutcome.Changed then
  begin
    Exit(cTexts[TEditToolsText.NoDeviationFromTheFormat].Text);
  end;
  Result := DeviationReport(AFileName, mOutcome) + sLineBreak + sLineBreak +
    cTexts[TEditToolsText.FormattedTextPascal].Fmt([mOutcome.Formatted]);
end;

function TMcpEditTools.FormatCode(const AStyle: TFormatStyle; const AFileName: string;
  const AScope: TFormatScope; ADryRun: Boolean): string;
var
  mText: string;
  mOutcome: TFormatOutcome;
  mEdit: TTextEdit;
  mEdits: TArray<TMcpFileEdit>;
begin
  if not FReadText(AFileName, mText) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TEditToolsText.IsNotReadable].Text, [AFileName]);
  end;
  mOutcome := FormatOrFail(AStyle, AFileName, mText, AScope, TFileChecker.SourceOf(FCheckSource, AFileName));
  if not mOutcome.Changed then
  begin
    Exit(cTexts[TEditToolsText.NoDeviationFromTheFormat2].Fmt([ExtractFileName(AFileName)]));
  end;
  mEdits := nil;
  for mEdit in TTextChanges.Diff(mText, mOutcome.Formatted) do
  begin
    mEdits := mEdits + [TMcpFileEdit.Create(AFileName, mEdit.Range, mEdit.NewText)];
  end;
  // Die Datei behält ihre Zeilenenden (TFileEncoding beim Schreiben); andere setzt --format-write um.
  if Length(mEdits) = 0 then
  begin
    Exit(DeviationReport(AFileName, mOutcome) + sLineBreak + cTexts[TEditToolsText.OnlyTheLineEndingsDiffer].Text);
  end;
  Result := DeviationReport(AFileName, mOutcome) + sLineBreak + sLineBreak + Apply('format_code', mEdits, ADryRun);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.EditTools', cTexts);

end.
