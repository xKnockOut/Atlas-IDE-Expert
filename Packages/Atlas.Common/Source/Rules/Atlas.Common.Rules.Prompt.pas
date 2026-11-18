unit Atlas.Common.Rules.Prompt;

// Befund an einen KI-Assistenten übergeben (#158, #2570): Markdown mit Regel, Beschreibung, Codeausschnitt (±N
// Zeilen, die betroffene Zeile markiert), Vorher/Nachher aus dem Regelkatalog (#145), weiteren Stellen (#896) und
// einer Schlusszeile, mit welchem MCP-Werkzeug der Assistent sein Ergebnis prüft bzw. korrigiert. Dieselbe Ausgabe
// liefern das MCP-Werkzeug explain_finding, die Code-Aktion „Befund als Auftrag kopieren“ und das Fenster
// „Atlas-Prüfung“ (Befehl atlas.server.findingsPrompt).
// Mehrere Befunde (Many): ein Auftrag „n Befunde in m Dateien beheben“, je Datei gruppiert, überlappende
// Ausschnitte einmal, Erklärung jeder Regel einmal am Ende; über der Obergrenze ein Hinweis auf check_code.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog;

type
  /// <summary>Ein Befund für einen Auftrag: Datei, wie sie im Text erscheint, Quelltext und Befund.</summary>
  TFindingPromptItem = record
    FileName: string;
    Text: string;
    Finding: TRuleFinding;
    /// <summary>Compilermeldung ohne Atlas-Regel: ohne Konfidenz und ohne Korrekturwerkzeug.</summary>
    Compiler: Boolean;
    class function Create(const AFinding: TRuleFinding; const AFileName, AText: string): TFindingPromptItem; static;
  end;

  TFindingPrompt = class
  public const
    /// <summary>Zeilen vor und nach dem Befund im Ausschnitt.</summary>
    cDefaultContext = 8;
    /// <summary>Höchstzahl Befunde eines Auftrags; der Rest steht als Hinweis auf check_code da.</summary>
    cDefaultLimit = 20;
  public
    /// <summary>Markdown zu AFinding in AText (Datei AFileName); ACatalog darf nil sein.</summary>
    class function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
      const ACatalog: TRuleCatalog; AContext: Integer): string; overload; static;
    /// <summary>Wie oben mit AContext = cDefaultContext.</summary>
    class function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
      const ACatalog: TRuleCatalog): string; overload; static;
    /// <summary>Auftrag zu einem Befund; ACatalog darf nil sein.</summary>
    class function OneFinding(const AItem: TFindingPromptItem; const ACatalog: TRuleCatalog;
      AContext: Integer): string; static;
    /// <summary>Auftrag zu AItems (ein Befund wie OneFinding); höchstens ALimit Befunde; ACatalog darf nil
    /// sein.</summary>
    class function Many(const AItems: TArray<TFindingPromptItem>; const ACatalog: TRuleCatalog;
      AContext, ALimit: Integer): string; static;
    /// <summary>Deutscher Katalog (Basis mit deutschem Overlay); der Aufrufer gibt ihn frei.</summary>
    class function GermanCatalog: TRuleCatalog; static;
    /// <summary>Gemeinsamer Katalog in der Sprache der Texte (TRuleCatalog.Localized); nicht freigeben.</summary>
    class function SharedCatalog: TRuleCatalog; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Rules.Output,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPromptText = (Rule, BeforeAfter, Before, After, FindingNamed, Finding, Location, Severity, Message, Confidence,
    CompilerMessage, LineColumn, Related, RelatedItem, CheckWith, FixWith, ManyHeading, FileHeading, Rules, Omitted);

const
  cTexts: array[TPromptText] of TAtlasText = (
    (De: 'Regel'; En: 'Rule'),
    (De: 'Vorher/Nachher'; En: 'Before/after'),
    (De: 'Vorher:'; En: 'Before:'),
    (De: 'Nachher:'; En: 'After:'),
    (De: 'Befund %s: %s'; En: 'Finding %s: %s'),
    (De: 'Befund %s'; En: 'Finding %s'),
    (De: '- Datei: `%s`, Zeile %d, Spalte %d'; En: '- File: `%s`, line %d, column %d'),
    (De: '- Schweregrad: %s'; En: '- Severity: %s'),
    (De: '- Meldung: %s'; En: '- Message: %s'),
    (De: '- Konfidenz: %s'; En: '- Confidence: %s'),
    (De: 'Compilermeldung %s'; En: 'Compiler message %s'),
    (De: '- Zeile %d, Spalte %d'; En: '- Line %d, column %d'),
    (De: '- Weitere Stellen:'; En: '- Further locations:'),
    (De: '  - `%s`, Zeile %d: %s'; En: '  - `%s`, line %d: %s'),
    (De: 'Prüfen mit: `check_code` (file: `%s`)'; En: 'Check with: `check_code` (file: `%s`)'),
    (De: 'Korrigieren mit: `fix_findings` (rules: [%s], file: `%s`)';
     En: 'Fix with: `fix_findings` (rules: [%s], file: `%s`)'),
    (De: '%d Befunde in %d Dateien beheben'; En: 'Fix %d findings in %d files'),
    (De: 'Datei `%s`'; En: 'File `%s`'),
    (De: 'Regeln'; En: 'Rules'),
    (De: 'Weitere %d Befunde sind hier nicht aufgeführt; nach den Korrekturen mit `check_code` holen.';
     En: '%d more findings are not listed here; fetch them with `check_code` after the fixes.'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Zusammenhängender Ausschnitt (Zeilen ab 0, beide einschließlich).</summary>
  TPromptBlock = record
    First: Integer;
    Last: Integer;
  end;

  /// <summary>Befunde einer Datei im Auftrag, in Zeilenreihenfolge.</summary>
  TPromptFile = record
    FileName: string;
    Text: string;
    Items: TArray<TFindingPromptItem>;
  end;

{ TFindingPromptItem }

class function TFindingPromptItem.Create(const AFinding: TRuleFinding;
  const AFileName, AText: string): TFindingPromptItem;
begin
  Result := Default(TFindingPromptItem);
  Result.Finding := AFinding;
  Result.FileName := AFileName;
  Result.Text := AText;
end;

{ Bausteine }

procedure AppendHeading(ABuilder: TStringBuilder; ALevel: Integer; const AText: string);
begin
  ABuilder.AppendLine;
  ABuilder.Append(StringOfChar('#', ALevel)).Append(' ').AppendLine(AText);
end;

function LinesOf(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Split([#10]);
end;

/// <summary>Katalogeintrag der Regel; False, wenn ACatalog nil ist oder die Regel nicht kennt.</summary>
function TryEntry(const ACatalog: TRuleCatalog; const ARuleId: string; out AEntry: TRuleCatalogEntry): Boolean;
begin
  AEntry := Default(TRuleCatalogEntry);
  Result := (ACatalog <> nil) and (ARuleId <> '') and ACatalog.TryFind(ARuleId, AEntry);
end;

/// <summary>Überschrift des Befunds: Regel mit Name aus dem Katalog bzw. Compilermeldung.</summary>
function TitleOf(const AItem: TFindingPromptItem; const ACatalog: TRuleCatalog): string;
var
  mEntry: TRuleCatalogEntry;
begin
  if AItem.Compiler then
  begin
    Result := cTexts[TPromptText.CompilerMessage].Fmt([AItem.Finding.RuleId]);
  end
  else if TryEntry(ACatalog, AItem.Finding.RuleId, mEntry) and (mEntry.Name <> '') then
  begin
    Result := cTexts[TPromptText.FindingNamed].Fmt([AItem.Finding.RuleId, mEntry.Name]);
  end
  else
  begin
    Result := cTexts[TPromptText.Finding].Fmt([AItem.Finding.RuleId]);
  end;
end;

/// <summary>Weitere Stellen des Befunds (#896) als eingerückte Liste.</summary>
procedure AppendRelated(ABuilder: TStringBuilder; const AFinding: TRuleFinding);
var
  mRelated: TRuleRelated;
begin
  if AFinding.Related = nil then
  begin
    Exit;
  end;
  ABuilder.AppendLine(cTexts[TPromptText.Related].Text);
  for mRelated in AFinding.Related do
  begin
    ABuilder.AppendLine(cTexts[TPromptText.RelatedItem].Fmt([mRelated.FileName, mRelated.Range.StartPos.Line + 1,
      mRelated.Message]));
  end;
end;

/// <summary>Liste mit Ort (mit Datei nur für einen einzelnen Befund), Schwere, Meldung, Konfidenz und weiteren
/// Stellen.</summary>
procedure AppendFacts(ABuilder: TStringBuilder; const AItem: TFindingPromptItem; AWithFile: Boolean);
var
  mStart: TTextPosition;
begin
  mStart := AItem.Finding.Range.StartPos;
  if AWithFile then
  begin
    ABuilder.AppendLine(cTexts[TPromptText.Location].Fmt([AItem.FileName, mStart.Line + 1, mStart.Character + 1]));
  end
  else
  begin
    ABuilder.AppendLine(cTexts[TPromptText.LineColumn].Fmt([mStart.Line + 1, mStart.Character + 1]));
  end;
  ABuilder.AppendLine(cTexts[TPromptText.Severity].Fmt([TFindingsOutput.SeverityName(AItem.Finding.Severity)]));
  ABuilder.AppendLine(cTexts[TPromptText.Message].Fmt([AItem.Finding.Message]));
  if not AItem.Compiler then
  begin
    ABuilder.AppendLine(cTexts[TPromptText.Confidence].Fmt([ConfidenceText(AItem.Finding.Confidence)]));
  end;
  AppendRelated(ABuilder, AItem.Finding);
end;

/// <summary>Beschreibung der Regel unter einer Überschrift der Stufe ALevel; nichts ohne Beschreibung.</summary>
procedure AppendDescription(ABuilder: TStringBuilder; ALevel: Integer; const ATitle: string;
  const AEntry: TRuleCatalogEntry);
begin
  if AEntry.Description <> '' then
  begin
    AppendHeading(ABuilder, ALevel, ATitle);
    ABuilder.AppendLine;
    ABuilder.AppendLine(AEntry.Description);
  end;
end;

/// <summary>Ein Beispiel unter ATitle ("Vorher:"/"Nachher:"); nichts ohne Code.</summary>
procedure AppendExample(ABuilder: TStringBuilder; const ATitle, ACode: string);
begin
  if ACode = '' then
  begin
    Exit;
  end;
  ABuilder.AppendLine;
  ABuilder.AppendLine(ATitle);
  ABuilder.AppendLine;
  ABuilder.AppendLine('```pascal');
  ABuilder.AppendLine(TrimRight(ACode));
  ABuilder.AppendLine('```');
end;

/// <summary>Abschnitt „Vorher/Nachher“ aus dem Katalogeintrag.</summary>
procedure AppendExamples(ABuilder: TStringBuilder; ALevel: Integer; const AEntry: TRuleCatalogEntry);
begin
  if (AEntry.Bad <> '') or (AEntry.Good <> '') then
  begin
    AppendHeading(ABuilder, ALevel, cTexts[TPromptText.BeforeAfter].Text);
    AppendExample(ABuilder, cTexts[TPromptText.Before].Text, AEntry.Bad);
    AppendExample(ABuilder, cTexts[TPromptText.After].Text, AEntry.Good);
  end;
end;

/// <summary>Ausschnitte um die Zeilen AMarked (je ±AContext), überlappende und angrenzende zusammengelegt.</summary>
function BlocksOf(const AMarked: TArray<Integer>; ALineCount, AContext: Integer): TArray<TPromptBlock>;
var
  mLines: TArray<Integer>;
  mLine: Integer;
  mBlock: TPromptBlock;
begin
  Result := nil;
  mLines := Copy(AMarked);
  TArray.Sort<Integer>(mLines);
  for mLine in mLines do
  begin
    mBlock.First := Max(0, mLine - AContext);
    mBlock.Last := Min(ALineCount - 1, mLine + AContext);
    if mBlock.First > mBlock.Last then
    begin
      Continue;
    end;
    if (Length(Result) > 0) and (mBlock.First <= Result[High(Result)].Last + 1) then
    begin
      Result[High(Result)].Last := Max(Result[High(Result)].Last, mBlock.Last);
    end
    else
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := mBlock;
    end;
  end;
end;

function IsMarked(const AMarked: TArray<Integer>; ALine: Integer): Boolean;
var
  mLine: Integer;
begin
  Result := False;
  for mLine in AMarked do
  begin
    if mLine = ALine then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Abschnitt „Code“: Ausschnitte um AMarked (Zeilen ab 0), Fundzeilen mit ">", zwischen getrennten
/// Ausschnitten eine Zeile „…“.</summary>
procedure AppendCode(ABuilder: TStringBuilder; ALevel: Integer; const AText: string;
  const AMarked: TArray<Integer>; AContext: Integer);
var
  mLines: TArray<string>;
  mBlocks: TArray<TPromptBlock>;
  mBlock: TPromptBlock;
  mIndex: Integer;
begin
  mLines := LinesOf(AText);
  mBlocks := BlocksOf(AMarked, Length(mLines), AContext);
  if mBlocks = nil then
  begin
    Exit;
  end;
  AppendHeading(ABuilder, ALevel, 'Code');
  ABuilder.AppendLine;
  ABuilder.AppendLine('```pascal');
  for mBlock in mBlocks do
  begin
    if mBlock.First <> mBlocks[0].First then
    begin
      ABuilder.AppendLine('       …');
    end;
    for mIndex := mBlock.First to mBlock.Last do
    begin
      ABuilder.AppendFormat('%s %4d | %s', [IfThen(IsMarked(AMarked, mIndex), '>', ' '), mIndex + 1,
        mLines[mIndex]]).AppendLine;
    end;
  end;
  ABuilder.AppendLine('```');
end;

/// <summary>Regeln mit sicherer Korrektur (Katalogfeld safeFix) unter AItems, ohne Doppelte.</summary>
function SafeRules(const AItems: TArray<TFindingPromptItem>; const ACatalog: TRuleCatalog): TArray<string>;
var
  mItem: TFindingPromptItem;
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if not mItem.Compiler and TryEntry(ACatalog, mItem.Finding.RuleId, mEntry) and mEntry.SafeFix and
      not MatchText(mItem.Finding.RuleId, Result) then
    begin
      Result := Result + [mItem.Finding.RuleId];
    end;
  end;
end;

/// <summary>Schlusszeilen: Prüfen mit check_code, bei sicheren Korrekturen auch fix_findings.</summary>
procedure AppendTools(ABuilder: TStringBuilder; const AFileName: string; const ASafeRules: TArray<string>);
var
  mRules: string;
  mRule: string;
begin
  ABuilder.AppendLine;
  ABuilder.AppendLine(cTexts[TPromptText.CheckWith].Fmt([AFileName]));
  if ASafeRules = nil then
  begin
    Exit;
  end;
  mRules := '';
  for mRule in ASafeRules do
  begin
    if mRules <> '' then
    begin
      mRules := mRules + ', ';
    end;
    mRules := mRules + '"' + mRule + '"';
  end;
  ABuilder.AppendLine(cTexts[TPromptText.FixWith].Fmt([mRules, AFileName]));
end;

/// <summary>Befunde nach Datei in der Reihenfolge des ersten Auftretens, je Datei nach Zeile.</summary>
function GroupByFile(const AItems: TArray<TFindingPromptItem>): TArray<TPromptFile>;
var
  mItem: TFindingPromptItem;
  mIndex, mFound: Integer;
begin
  Result := nil;
  for mItem in AItems do
  begin
    mFound := -1;
    for mIndex := 0 to High(Result) do
    begin
      if SameFileName(Result[mIndex].FileName, mItem.FileName) then
      begin
        mFound := mIndex;
        Break;
      end;
    end;
    if mFound < 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      mFound := High(Result);
      Result[mFound].FileName := mItem.FileName;
      Result[mFound].Text := mItem.Text;
    end;
    Result[mFound].Items := Result[mFound].Items + [mItem];
  end;
end;

/// <summary>Befunde einer Datei nach Zeile und Spalte; bei Gleichstand nach Regel, damit die Reihenfolge feststeht.
/// </summary>
procedure SortByLine(var AItems: TArray<TFindingPromptItem>);
begin
  TArray.Sort<TFindingPromptItem>(AItems, TComparer<TFindingPromptItem>.Construct(
    function(const A, B: TFindingPromptItem): Integer
    begin
      Result := CompareValue(A.Finding.Range.StartPos.Line, B.Finding.Range.StartPos.Line);
      if Result = 0 then
      begin
        Result := CompareValue(A.Finding.Range.StartPos.Character, B.Finding.Range.StartPos.Character);
      end;
      if Result = 0 then
      begin
        Result := CompareText(A.Finding.RuleId, B.Finding.RuleId);
      end;
    end));
end;

/// <summary>Zeilen (ab 0) der Befunde in AItems.</summary>
function MarkedLines(const AItems: TArray<TFindingPromptItem>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := AItems[mIndex].Finding.Range.StartPos.Line;
  end;
end;

/// <summary>Abschnitt einer Datei im Auftrag zu mehreren Befunden.</summary>
procedure AppendFile(ABuilder: TStringBuilder; var AFile: TPromptFile; const ACatalog: TRuleCatalog;
  AContext: Integer);
var
  mItem: TFindingPromptItem;
begin
  SortByLine(AFile.Items);
  AppendHeading(ABuilder, 2, cTexts[TPromptText.FileHeading].Fmt([AFile.FileName]));
  for mItem in AFile.Items do
  begin
    AppendHeading(ABuilder, 3, TitleOf(mItem, ACatalog));
    ABuilder.AppendLine;
    AppendFacts(ABuilder, mItem, False);
  end;
  AppendCode(ABuilder, 3, AFile.Text, MarkedLines(AFile.Items), AContext);
  AppendTools(ABuilder, AFile.FileName, SafeRules(AFile.Items, ACatalog));
end;

/// <summary>Abschnitt „Regeln“: Beschreibung und Vorher/Nachher jeder Regel aus AItems einmal.</summary>
procedure AppendRules(ABuilder: TStringBuilder; const AItems: TArray<TFindingPromptItem>;
  const ACatalog: TRuleCatalog);
var
  mItem: TFindingPromptItem;
  mEntry: TRuleCatalogEntry;
  mDone: TArray<string>;
  mStart: Integer;
begin
  mStart := ABuilder.Length;
  AppendHeading(ABuilder, 2, cTexts[TPromptText.Rules].Text);
  mDone := nil;
  for mItem in AItems do
  begin
    if not MatchText(mItem.Finding.RuleId, mDone) and TryEntry(ACatalog, mItem.Finding.RuleId, mEntry) and
      ((mEntry.Description <> '') or (mEntry.Bad <> '') or (mEntry.Good <> '')) then
    begin
      mDone := mDone + [mItem.Finding.RuleId];
      AppendDescription(ABuilder, 3, TitleOf(mItem, ACatalog), mEntry);
      AppendExamples(ABuilder, 4, mEntry);
    end;
  end;
  if mDone = nil then
  begin
    ABuilder.Length := mStart;
  end;
end;

{ TFindingPrompt }

class function TFindingPrompt.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
  const ACatalog: TRuleCatalog): string;
begin
  Result := Markdown(AFinding, AFileName, AText, ACatalog, cDefaultContext);
end;

class function TFindingPrompt.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
  const ACatalog: TRuleCatalog; AContext: Integer): string;
begin
  Result := OneFinding(TFindingPromptItem.Create(AFinding, AFileName, AText), ACatalog, AContext);
end;

class function TFindingPrompt.GermanCatalog: TRuleCatalog;
begin
  Result := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
end;

class function TFindingPrompt.SharedCatalog: TRuleCatalog;
begin
  // Kein eigener Katalog: Ein zweiter deutscher neben TRuleCatalog.Localized hielt rund 850 KB doppelt.
  Result := TRuleCatalog.Localized;
end;

class function TFindingPrompt.OneFinding(const AItem: TFindingPromptItem; const ACatalog: TRuleCatalog;
  AContext: Integer): string;
var
  mBuilder: TStringBuilder;
  mEntry: TRuleCatalogEntry;
  mKnown: Boolean;
begin
  mKnown := TryEntry(ACatalog, AItem.Finding.RuleId, mEntry);
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('## ').AppendLine(TitleOf(AItem, ACatalog));
    mBuilder.AppendLine;
    AppendFacts(mBuilder, AItem, True);
    AppendDescription(mBuilder, 3, cTexts[TPromptText.Rule].Text, mEntry);
    AppendCode(mBuilder, 3, AItem.Text, TArray<Integer>.Create(AItem.Finding.Range.StartPos.Line), AContext);
    if mKnown then
    begin
      AppendExamples(mBuilder, 3, mEntry);
    end;
    AppendTools(mBuilder, AItem.FileName, SafeRules(TArray<TFindingPromptItem>.Create(AItem), ACatalog));
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

class function TFindingPrompt.Many(const AItems: TArray<TFindingPromptItem>; const ACatalog: TRuleCatalog;
  AContext, ALimit: Integer): string;
var
  mBuilder: TStringBuilder;
  mListed: TArray<TFindingPromptItem>;
  mFiles: TArray<TPromptFile>;
  mIndex: Integer;
begin
  if Length(AItems) = 1 then
  begin
    Result := OneFinding(AItems[0], ACatalog, AContext);
    Exit;
  end;
  Result := '';
  if AItems = nil then
  begin
    Exit;
  end;
  mListed := Copy(AItems, 0, Max(1, ALimit));
  mFiles := GroupByFile(mListed);
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('# ').AppendLine(cTexts[TPromptText.ManyHeading].Fmt([Length(AItems),
      Length(GroupByFile(AItems))]));
    if Length(mListed) < Length(AItems) then
    begin
      mBuilder.AppendLine;
      mBuilder.AppendLine(cTexts[TPromptText.Omitted].Fmt([Length(AItems) - Length(mListed)]));
    end;
    for mIndex := 0 to High(mFiles) do
    begin
      AppendFile(mBuilder, mFiles[mIndex], ACatalog, AContext);
    end;
    AppendRules(mBuilder, mListed, ACatalog);
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Prompt', cTexts);

end.
