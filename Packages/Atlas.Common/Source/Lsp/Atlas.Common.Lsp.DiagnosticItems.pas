unit Atlas.Common.Lsp.DiagnosticItems;

// Einzelne LSP-Diagnosen für textDocument/publishDiagnostics und die
// Projektprüfung: Regeltreffer, Compilermeldungen, inaktive Bereiche,
// Präprozessor-Befunde und auffällige uses-Einträge, dazu die Meldungen
// von Formulardateien. TLspSyntaxDiagnostics setzt sie zu den Parametern
// eines Dokuments zusammen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Suppressions,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract;

type
  TLspDiagnosticItems = class
  public const
    cSource = 'Atlas';
    cCompilerSource = 'dcc';
    /// <summary>DiagnosticTag.Unnecessary: Der Editor blendet ab.</summary>
    cTagUnnecessary = 1;
    /// <summary>DiagnosticTag.Deprecated: Der Editor streicht durch.</summary>
    cTagDeprecated = 2;
  public
    class function InactiveMessage: string; static;
    class function InactiveConditionMessage: string; static;
    class function InactiveTargetSuffix: string; static;
    /// <summary>Meldungen zu uses-Einträgen (#621).</summary>
    class function UsesUnusedMessage: string; static;
    class function UsesInitializationMessage: string; static;
    class function UsesAllowlistMessage: string; static;
    class function UsesImplementationMessage: string; static;
    /// <summary>Ein Regeltreffer als LSP-Diagnostic (code = Regelkennung). Der Aufrufer übernimmt das Objekt.</summary>
    class function FindingToJson(const AFinding: TRuleFinding): TJSONObject; static;
    /// <summary>Compilermeldung als LSP-Diagnostic; ALineText (falls bekannt) begrenzt den Bereich.
    /// Der Aufrufer übernimmt das Objekt.</summary>
    class function CompilerMessageToJson(const AMessage: TCompilerMessage; const ALineText: string;
      AHasLineText: Boolean): TJSONObject; static;
    /// <summary>Meldung zu einem inaktiven Bereich: mit Bedingung „Inaktiv: Bedingung X nicht erfüllt“,
    /// mit Plattform oder Konfiguration dahinter „(Zielplattform Win32 · Debug)“.</summary>
    class function InactiveMessageOf(const ACondition, APlatform, AConfig: string): string; static;
    /// <summary>Inaktiver Bereich als Hinweis mit dem Tag Unnecessary; Bedingung, Plattform und Konfiguration
    /// einzeln in data.inactive (#615).</summary>
    class function InactiveToJson(const ARegion: TLspInactiveRegion; const APlatform, AConfig: string)
      : TJSONObject; static;
    /// <summary>Befund des Präprozessors: Include-Zyklus als Warnung, sonst Hinweis.</summary>
    class function IssueToJson(const AIssue: TPreprocessorIssue): TJSONObject; static;
    /// <summary>Auffällige uses-Einträge von AText als Diagnosen in AItems (#621); AInactive zählt nicht.
    /// Ungenutzte Einträge, die ein lsp-ignore für unused-uses aus ASuppressions abdeckt, fehlen (#1135), ebenso
    /// nur in der implementation gebrauchte unter lsp-ignore für uses-only-in-implementation (#1136);
    /// ASuppressions nil = keine. Nur Einträge mit einem Zustand aus AShown.</summary>
    class procedure AddUses(AItems: TJSONArray; const AText: string; const AInactive: TArray<TTextRange>;
      const AContext: TUsesContext; ASuppressions: TSuppressions; const AShown: TUsesEntryStates); static;
    /// <summary>Regel, deren lsp-ignore einen Eintrag im Zustand AState verbirgt: unused-uses für ungenutzte,
    /// uses-only-in-implementation für OnlyImplementation, sonst leer.</summary>
    class function UsesRuleOf(AState: TUsesEntryState): string; static;
    /// <summary>Name des Zustands in data.uses.state: unused, initialization, allowlist, implementation.</summary>
    class function UsesStateName(AState: TUsesEntryState): string; static;
    /// <summary>Parameter für publishDiagnostics einer Formulardatei (#44): nur Lesefehler der DFM, bei binär
    /// gespeicherten ein Hinweis (#122). False, wenn AUri keine Formulardatei ist.</summary>
    class function TryFormParams(const AUri, AText: string; out AParams: TJSONObject): Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Builtin.Deprecated,
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDiagnosticItemsText = (InactiveRegionConditionalCompilation, InactiveConditionNotMet, TargetPlatform,
    NothingFromIsUsed, IsNotShownAsUnused, IsInUsesKeepAndIs, IsOnlyNeededInThe);

const
  cTexts: array[TDiagnosticItemsText] of TAtlasText = (
    (De: 'Inaktiver Bereich (bedingte Kompilierung)'; En: 'Inactive region (conditional compilation)'),
    (De: 'Inaktiv: Bedingung %s nicht erfüllt'; En: 'Inactive: condition %s not met'),
    (De: ' (Zielplattform %s · %s)'; En: ' (target platform %s · %s)'),
    (De: 'Aus %s wird nichts verwendet'; En: 'Nothing from %s is used'),
    (De: '%s wird wegen initialization nicht als ungenutzt gezeigt';
     En: '%s is not shown as unused because of initialization'),
    (De: '%s steht in usesKeep und wird nicht als ungenutzt gezeigt';
     En: '%s is in usesKeep and is not shown as unused'),
    (De: '%s wird nur in der implementation gebraucht'; En: '%s is only needed in the implementation'));

{$SCOPEDENUMS OFF}

class function TLspDiagnosticItems.InactiveMessage: string;
begin
  Result := cTexts[TDiagnosticItemsText.InactiveRegionConditionalCompilation].Text;
end;

class function TLspDiagnosticItems.InactiveConditionMessage: string;
begin
  Result := cTexts[TDiagnosticItemsText.InactiveConditionNotMet].Text;
end;

class function TLspDiagnosticItems.InactiveTargetSuffix: string;
begin
  Result := cTexts[TDiagnosticItemsText.TargetPlatform].Text;
end;

class function TLspDiagnosticItems.UsesUnusedMessage: string;
begin
  Result := cTexts[TDiagnosticItemsText.NothingFromIsUsed].Text;
end;

class function TLspDiagnosticItems.UsesInitializationMessage: string;
begin
  Result := cTexts[TDiagnosticItemsText.IsNotShownAsUnused].Text;
end;

class function TLspDiagnosticItems.UsesAllowlistMessage: string;
begin
  Result := cTexts[TDiagnosticItemsText.IsInUsesKeepAndIs].Text;
end;

class function TLspDiagnosticItems.UsesImplementationMessage: string;
begin
  Result := cTexts[TDiagnosticItemsText.IsOnlyNeededInThe].Text;
end;

function SeverityOf(ASeverity: TRuleSeverity): Integer;
begin
  case ASeverity of
    TRuleSeverity.Error:
      Result := TLspDiagnosticSeverity.cError;
    TRuleSeverity.Warning:
      Result := TLspDiagnosticSeverity.cWarning;
    TRuleSeverity.Information:
      Result := TLspDiagnosticSeverity.cInformation;
  else
    Result := TLspDiagnosticSeverity.cHint;
  end;
end;

function TagsOf(ATag: Integer): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(ATag);
end;

/// <summary>Fenster „Atlas-Prüfung“ und Befund-Hover (#909): Kategorie und Gruppe aus dem Katalog; Gruppe
/// „Compiler vorab“ (#1024) mit den Codes für den Abgleich mit dcc und die Spalte „Compiler“ im Plugin.</summary>
procedure AddCatalogData(AData: TJSONObject; const ARuleId: string);
var
  mEntry: TRuleCatalogEntry;
  mCodes: TJSONArray;
  mCode: string;
begin
  if not TRuleCatalog.Shared.TryFind(ARuleId, mEntry) then
  begin
    Exit;
  end;
  AData.AddPair('category', TRuleCatalog.CategoryName(mEntry.Category));
  AData.AddPair('group', TRuleCatalog.GroupName(mEntry.Group));
  if Length(mEntry.CompilerCodes) > 0 then
  begin
    mCodes := TJSONArray.Create;
    for mCode in mEntry.CompilerCodes do
    begin
      mCodes.Add(mCode);
    end;
    AData.AddPair('compilerCodes', mCodes);
  end;
end;

function FindingData(const AFinding: TRuleFinding): TJSONObject;
begin
  Result := TJSONObject.Create(TJSONPair.Create('confidence', ConfidenceName(AFinding.Confidence)));
  AddCatalogData(Result, AFinding.RuleId);
  // Wie Rules.CodeActions: bevorzugt ist nur die erste Korrektur, wenn sie keine Alternative ist.
  if (Length(AFinding.Fixes) > 0) and not AFinding.Fixes[0].Alternative then
  begin
    Result.AddPair('fix', AFinding.Fixes[0].Title);
  end;
  // Zusatz für den Befund-Hover, z. B. der durchsuchte Bereich projektweiter Regeln (#1102).
  if AFinding.Details <> '' then
  begin
    Result.AddPair('details', AFinding.Details);
  end;
end;

/// <summary>Weitere Stellen (#896), z. B. die uses-Einträge eines Zyklus: anklickbar im Befund-Hover.</summary>
function RelatedJson(const ARelated: TArray<TRuleRelated>): TJSONArray;
var
  mRelated: TRuleRelated;
  mLocation, mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mRelated in ARelated do
  begin
    mLocation := TJSONObject.Create;
    mLocation.AddPair('uri', TDocumentUris.FromPath(mRelated.FileName));
    mLocation.AddPair('range', TLspPositions.RangeToJson(mRelated.Range));
    mItem := TJSONObject.Create;
    mItem.AddPair('location', mLocation);
    mItem.AddPair('message', mRelated.Message);
    Result.AddElement(mItem);
  end;
end;

/// <summary>Bereich einer Compilermeldung mit bekanntem Zeilentext: ab der Spalte bis zum Ende des
/// Bezeichners (mindestens ein Zeichen), ohne Spalte die ganze Zeile ohne Einrückung.</summary>
function LineRange(ALine, AColumn: Integer; const ALineText: string): TTextRange;
var
  mFirst, mLast: Integer;
begin
  if AColumn >= 0 then
  begin
    mFirst := Min(AColumn, Length(ALineText));
    mLast := mFirst + 1;
    while (mLast < Length(ALineText)) and CharInSet(ALineText[mLast + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    begin
      Inc(mLast);
    end;
  end
  else
  begin
    mFirst := 0;
    while (mFirst < Length(ALineText)) and CharInSet(ALineText[mFirst + 1], [' ', #9]) do
    begin
      Inc(mFirst);
    end;
    mLast := Length(ALineText);
  end;
  Result.StartPos := TTextPosition.Create(ALine, mFirst);
  Result.EndPos := TTextPosition.Create(ALine, Max(mLast, mFirst));
end;

function CompilerRange(const AMessage: TCompilerMessage; const ALineText: string; AHasLineText: Boolean)
  : TTextRange;
var
  mLine: Integer;
begin
  mLine := Max(AMessage.Line, 0);
  if AHasLineText then
  begin
    Result := LineRange(mLine, AMessage.Column, ALineText);
  end
  else if AMessage.Column >= 0 then
  begin
    Result.StartPos := TTextPosition.Create(mLine, AMessage.Column);
    Result.EndPos := TTextPosition.Create(mLine, AMessage.Column + 1);
  end
  else
  begin
    Result.StartPos := TTextPosition.Create(mLine, 0);
    Result.EndPos := TTextPosition.Create(mLine + 1, 0);
  end;
end;

function CompilerSeverityOf(ASeverity: TCompilerSeverity): Integer;
begin
  case ASeverity of
    TCompilerSeverity.Hint:
      Result := TLspDiagnosticSeverity.cHint;
    TCompilerSeverity.Warning:
      Result := TLspDiagnosticSeverity.cWarning;
  else
    Result := TLspDiagnosticSeverity.cError;
  end;
end;

function UsesMessage(AState: TUsesEntryState): string;
begin
  case AState of
    TUsesEntryState.KeptForInitialization:
      Result := TLspDiagnosticItems.UsesInitializationMessage;
    TUsesEntryState.KeptByAllowlist:
      Result := TLspDiagnosticItems.UsesAllowlistMessage;
    TUsesEntryState.OnlyImplementation:
      Result := TLspDiagnosticItems.UsesImplementationMessage;
  else
    Result := TLspDiagnosticItems.UsesUnusedMessage;
  end;
end;

{ TLspDiagnosticItems }

class function TLspDiagnosticItems.FindingToJson(const AFinding: TRuleFinding): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AFinding.Range));
  Result.AddPair('severity', TJSONNumber.Create(SeverityOf(AFinding.Severity)));
  Result.AddPair('code', AFinding.RuleId);
  Result.AddPair('codeDescription', TJSONObject.Create(
    TJSONPair.Create('href', TRuleCatalog.HelpUri(AFinding.RuleId))));
  Result.AddPair('source', cSource);
  // Konfidenz als eigenes Feld, der Meldungstext bleibt unverändert (#144).
  Result.AddPair('message', AFinding.Message);
  Result.AddPair('data', FindingData(AFinding));
  if AFinding.Related <> nil then
  begin
    Result.AddPair('relatedInformation', RelatedJson(AFinding.Related));
  end;
  // Veraltete Symbole durchgestrichen (#38), aber nicht platform, library oder experimental (#1018).
  if (AFinding.RuleId = cDeprecatedSymbolRuleId) and TDeprecatedSymbolRule.IsDeprecation(AFinding.Message) then
  begin
    Result.AddPair('tags', TagsOf(cTagDeprecated));
  end;
end;

class function TLspDiagnosticItems.CompilerMessageToJson(const AMessage: TCompilerMessage;
  const ALineText: string; AHasLineText: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(CompilerRange(AMessage, ALineText, AHasLineText)));
  Result.AddPair('severity', TJSONNumber.Create(CompilerSeverityOf(AMessage.Severity)));
  if AMessage.Code <> '' then
  begin
    Result.AddPair('code', AMessage.Code);
  end;
  Result.AddPair('source', cCompilerSource);
  Result.AddPair('message', AMessage.Text);
end;

class function TLspDiagnosticItems.InactiveMessageOf(const ACondition, APlatform, AConfig: string): string;
var
  mPlatform, mConfig: string;
begin
  if ACondition = '' then
  begin
    Exit(InactiveMessage);
  end;
  Result := Format(InactiveConditionMessage, [ACondition]);
  if (APlatform = '') and (AConfig = '') then
  begin
    Exit;
  end;
  mPlatform := APlatform;
  mConfig := AConfig;
  if mPlatform = '' then
  begin
    mPlatform := '?';
  end;
  if mConfig = '' then
  begin
    mConfig := '?';
  end;
  Result := Result + Format(InactiveTargetSuffix, [mPlatform, mConfig]);
end;

class function TLspDiagnosticItems.InactiveToJson(const ARegion: TLspInactiveRegion;
  const APlatform, AConfig: string): TJSONObject;
var
  mData: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(ARegion.Range));
  Result.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cHint));
  Result.AddPair('source', cSource);
  Result.AddPair('message', InactiveMessageOf(ARegion.Condition, APlatform, AConfig));
  Result.AddPair('tags', TagsOf(cTagUnnecessary));
  // Einzeln für Clients, die den Hinweis selbst setzen (Plugin, übersetzt).
  mData := TJSONObject.Create;
  mData.AddPair('condition', ARegion.Condition);
  mData.AddPair('platform', APlatform);
  mData.AddPair('config', AConfig);
  Result.AddPair('data', TJSONObject.Create(TJSONPair.Create('inactive', mData)));
end;

class function TLspDiagnosticItems.IssueToJson(const AIssue: TPreprocessorIssue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AIssue.Range));
  if AIssue.Kind = TPreprocessorIssueKind.IncludeCycle then
  begin
    Result.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cWarning));
  end
  else
  begin
    Result.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cHint));
  end;
  Result.AddPair('source', cSource);
  Result.AddPair('message', AIssue.Message);
end;

class function TLspDiagnosticItems.UsesStateName(AState: TUsesEntryState): string;
begin
  case AState of
    TUsesEntryState.KeptForInitialization:
      Result := 'initialization';
    TUsesEntryState.KeptByAllowlist:
      Result := 'allowlist';
    TUsesEntryState.OnlyImplementation:
      Result := 'implementation';
  else
    Result := 'unused';
  end;
end;

class function TLspDiagnosticItems.UsesRuleOf(AState: TUsesEntryState): string;
begin
  case AState of
    TUsesEntryState.Unused:
      Result := cUnusedUsesRuleId;
    TUsesEntryState.OnlyImplementation:
      Result := cUsesOnlyInImplementationRuleId;
  else
    Result := '';
  end;
end;

class procedure TLspDiagnosticItems.AddUses(AItems: TJSONArray; const AText: string;
  const AInactive: TArray<TTextRange>; const AContext: TUsesContext; ASuppressions: TSuppressions;
  const AShown: TUsesEntryStates);
var
  mEntry: TUsesEntry;
  mItem, mData: TJSONObject;
  mRuleId: string;
begin
  if AShown = [] then
  begin
    Exit;
  end;
  for mEntry in TUsesActions.Entries(TPascalLexer.Tokenize(AText), AInactive, AContext.Info, AContext.Keep,
    AContext.Resolution(AText, AInactive)) do
  begin
    mRuleId := UsesRuleOf(mEntry.State);
    if not (mEntry.State in AShown) or ((mRuleId <> '') and (ASuppressions <> nil) and
      ASuppressions.IsSuppressed(mRuleId, mEntry.Range.StartPos.Line)) then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEntry.Range));
    mItem.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cHint));
    mItem.AddPair('source', cSource);
    mItem.AddPair('message', Format(UsesMessage(mEntry.State), [mEntry.Name]));
    // Nur ungenutzte blendet der Editor ab.
    if mEntry.State = TUsesEntryState.Unused then
    begin
      mItem.AddPair('tags', TagsOf(cTagUnnecessary));
    end;
    mData := TJSONObject.Create;
    mData.AddPair('unit', mEntry.Name);
    mData.AddPair('state', UsesStateName(mEntry.State));
    mItem.AddPair('data', TJSONObject.Create(TJSONPair.Create('uses', mData)));
    AItems.AddElement(mItem);
  end;
end;

class function TLspDiagnosticItems.TryFormParams(const AUri, AText: string; out AParams: TJSONObject): Boolean;
var
  mForm: TDfmDocument;
begin
  AParams := nil;
  Result := TDfmParser.IsFormFile(AUri);
  if not Result then
  begin
    Exit;
  end;
  AParams := TJSONObject.Create;
  AParams.AddPair('uri', AUri);
  if TFormModel.IsBinary(AText) then
  begin
    AParams.AddPair('diagnostics', TLspFormFiles.BinaryDiagnostics);
    Exit;
  end;
  mForm := TDfmParser.Parse(AText);
  try
    AParams.AddPair('diagnostics', TLspFormFiles.BuildDiagnostics(mForm));
  finally
    mForm.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DiagnosticItems', cTexts);

end.
