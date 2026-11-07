unit Atlas.Common.Rules.Prompt;

// Befund an KI übergeben (#158): Markdown mit Regel, Beschreibung,
// Codeausschnitt (±N Zeilen, die betroffene Zeile markiert) und
// Vorher/Nachher-Beispiel aus dem Regelkatalog (#145). Dieselbe Ausgabe
// liefern das MCP-Werkzeug explain_finding und die Code-Aktion
// „Befund als Prompt kopieren“.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog;

type
  TFindingPrompt = class
  public const
    cDefaultContext = 3;
  public
    /// <summary>Markdown zu AFinding in AText (Datei AFileName); ACatalog darf nil sein.</summary>
    class function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
      const ACatalog: TRuleCatalog; AContext: Integer): string; overload; static;
    /// <summary>Wie oben mit AContext = DefaultContext.</summary>
    class function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
      const ACatalog: TRuleCatalog): string; overload; static;
    /// <summary>Deutscher Katalog (Basis mit deutschem Overlay); der Aufrufer gibt ihn frei.</summary>
    class function GermanCatalog: TRuleCatalog; static;
    /// <summary>Gemeinsamer deutscher Katalog, einmal geladen; nicht freigeben.</summary>
    class function SharedCatalog: TRuleCatalog; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Rules.Output,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPromptText = (Rule, BeforeAfter, Before, After, FindingNamed, Finding, Location, Severity, Message, Confidence);

const
  cTexts: array[TPromptText] of TAtlasText = (
    (De: '### Regel'; En: '### Rule'),
    (De: '### Vorher/Nachher'; En: '### Before/after'),
    (De: 'Vorher:'; En: 'Before:'),
    (De: 'Nachher:'; En: 'After:'),
    (De: '## Befund %s: %s'; En: '## Finding %s: %s'),
    (De: '## Befund %s'; En: '## Finding %s'),
    (De: '- Datei: `%s`, Zeile %d, Spalte %d'; En: '- File: `%s`, line %d, column %d'),
    (De: '- Schweregrad: %s'; En: '- Severity: %s'),
    (De: '- Meldung: %s'; En: '- Message: %s'),
    (De: '- Konfidenz: %s'; En: '- Confidence: %s'));

{$SCOPEDENUMS OFF}

var
  Shared: TRuleCatalog;
  SharedLock: TObject;

class function TFindingPrompt.SharedCatalog: TRuleCatalog;
begin
  TMonitor.Enter(SharedLock);
  try
    if Shared = nil then
    begin
      Shared := GermanCatalog;
    end;
    Result := Shared;
  finally
    TMonitor.Exit(SharedLock);
  end;
end;

class function TFindingPrompt.GermanCatalog: TRuleCatalog;
begin
  Result := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
end;

class function TFindingPrompt.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
  const ACatalog: TRuleCatalog): string;
begin
  Result := Markdown(AFinding, AFileName, AText, ACatalog, cDefaultContext);
end;

/// <summary>Abschnitt "### Code": AContext Zeilen um ALine (ab 0), die Fundzeile mit ">" markiert.</summary>
procedure AppendCode(ABuilder: TStringBuilder; const AText: string; ALine, AContext: Integer);
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  mLines := AText.Replace(#13#10, #10).Split([#10]);
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  ABuilder.AppendLine;
  ABuilder.AppendLine('### Code');
  ABuilder.AppendLine;
  ABuilder.AppendLine('```pascal');
  for mIndex := Max(0, ALine - AContext) to Min(High(mLines), ALine + AContext) do
  begin
    ABuilder.AppendFormat('%s %4d | %s', [IfThen(mIndex = ALine, '>', ' '), mIndex + 1, mLines[mIndex]]).AppendLine;
  end;
  ABuilder.AppendLine('```');
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

/// <summary>Abschnitt "### Regel" aus dem Katalogeintrag.</summary>
procedure AppendEntry(ABuilder: TStringBuilder; const AEntry: TRuleCatalogEntry);
begin
  if AEntry.Description <> '' then
  begin
    ABuilder.AppendLine;
    ABuilder.AppendLine(cTexts[TPromptText.Rule].Text);
    ABuilder.AppendLine;
    ABuilder.AppendLine(AEntry.Description);
  end;
end;

/// <summary>Abschnitt "### Vorher/Nachher" aus dem Katalogeintrag.</summary>
procedure AppendExamples(ABuilder: TStringBuilder; const AEntry: TRuleCatalogEntry);
begin
  if (AEntry.Bad <> '') or (AEntry.Good <> '') then
  begin
    ABuilder.AppendLine;
    ABuilder.AppendLine(cTexts[TPromptText.BeforeAfter].Text);
    AppendExample(ABuilder, cTexts[TPromptText.Before].Text, AEntry.Bad);
    AppendExample(ABuilder, cTexts[TPromptText.After].Text, AEntry.Good);
  end;
end;

class function TFindingPrompt.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string;
  const ACatalog: TRuleCatalog; AContext: Integer): string;
var
  mBuilder: TStringBuilder;
  mEntry: TRuleCatalogEntry;
  mKnown: Boolean;
begin
  mKnown := (ACatalog <> nil) and ACatalog.TryFind(AFinding.RuleId, mEntry);
  mBuilder := TStringBuilder.Create;
  try
    if mKnown and (mEntry.Name <> '') then
    begin
      mBuilder.AppendFormat(cTexts[TPromptText.FindingNamed].Text, [AFinding.RuleId, mEntry.Name]).AppendLine;
    end
    else
    begin
      mBuilder.AppendFormat(cTexts[TPromptText.Finding].Text, [AFinding.RuleId]).AppendLine;
    end;
    mBuilder.AppendLine;
    mBuilder.AppendFormat(cTexts[TPromptText.Location].Text, [AFileName, AFinding.Range.StartPos.Line + 1,
      AFinding.Range.StartPos.Character + 1]).AppendLine;
    mBuilder.AppendFormat(cTexts[TPromptText.Severity].Text,
      [TFindingsOutput.SeverityName(AFinding.Severity)]).AppendLine;
    mBuilder.AppendFormat(cTexts[TPromptText.Message].Text, [AFinding.Message]).AppendLine;
    mBuilder.AppendFormat(cTexts[TPromptText.Confidence].Text, [ConfidenceText(AFinding.Confidence)]).AppendLine;
    if mKnown then
    begin
      AppendEntry(mBuilder, mEntry);
    end;
    AppendCode(mBuilder, AText, AFinding.Range.StartPos.Line, AContext);
    if mKnown then
    begin
      AppendExamples(mBuilder, mEntry);
    end;
    Result := TrimRight(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Prompt', cTexts);
  SharedLock := TObject.Create;

finalization
  FreeAndNil(Shared);
  FreeAndNil(SharedLock);

end.
