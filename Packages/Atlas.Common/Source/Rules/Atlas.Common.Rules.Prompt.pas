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
    DefaultContext = 3;
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
  Atlas.Common.Rules.Output;

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
  Result := Markdown(AFinding, AFileName, AText, ACatalog, DefaultContext);
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
    ABuilder.AppendLine('### Regel');
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
    ABuilder.AppendLine('### Vorher/Nachher');
    AppendExample(ABuilder, 'Vorher:', AEntry.Bad);
    AppendExample(ABuilder, 'Nachher:', AEntry.Good);
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
      mBuilder.AppendFormat('## Befund %s: %s', [AFinding.RuleId, mEntry.Name]).AppendLine;
    end
    else
    begin
      mBuilder.AppendFormat('## Befund %s', [AFinding.RuleId]).AppendLine;
    end;
    mBuilder.AppendLine;
    mBuilder.AppendFormat('- Datei: `%s`, Zeile %d, Spalte %d', [AFileName, AFinding.Range.StartPos.Line + 1,
      AFinding.Range.StartPos.Character + 1]).AppendLine;
    mBuilder.AppendFormat('- Schweregrad: %s', [TFindingsOutput.SeverityName(AFinding.Severity)]).AppendLine;
    mBuilder.AppendFormat('- Meldung: %s', [AFinding.Message]).AppendLine;
    mBuilder.AppendFormat('- Konfidenz: %s', [ConfidenceText(AFinding.Confidence)]).AppendLine;
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
  SharedLock := TObject.Create;

finalization
  FreeAndNil(Shared);
  FreeAndNil(SharedLock);

end.
