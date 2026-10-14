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
      const ACatalog: TRuleCatalog; AContext: Integer = DefaultContext): string; static;
    /// <summary>Deutscher Katalog (Basis mit deutschem Overlay); der Aufrufer gibt ihn frei.</summary>
    class function GermanCatalog: TRuleCatalog; static;
    /// <summary>Gemeinsamer deutscher Katalog, einmal geladen; nicht freigeben.</summary>
    class function SharedCatalog: TRuleCatalog; static;
  end;

implementation

uses
  System.Math,
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
      Shared := GermanCatalog;
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
  const ACatalog: TRuleCatalog; AContext: Integer): string;
var
  Builder: TStringBuilder;
  Lines: TArray<string>;
  Entry: TRuleCatalogEntry;
  Known: Boolean;
  Index, First, Last, Line: Integer;
  Marker: string;
begin
  Known := (ACatalog <> nil) and ACatalog.TryFind(AFinding.RuleId, Entry);
  Line := AFinding.Range.StartPos.Line;
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  Builder := TStringBuilder.Create;
  try
    if Known and (Entry.Name <> '') then
      Builder.AppendFormat('## Befund %s: %s', [AFinding.RuleId, Entry.Name]).AppendLine
    else
      Builder.AppendFormat('## Befund %s', [AFinding.RuleId]).AppendLine;
    Builder.AppendLine;
    Builder.AppendFormat('- Datei: `%s`, Zeile %d, Spalte %d', [AFileName, Line + 1,
      AFinding.Range.StartPos.Character + 1]).AppendLine;
    Builder.AppendFormat('- Schweregrad: %s', [TFindingsOutput.SeverityName(AFinding.Severity)]).AppendLine;
    Builder.AppendFormat('- Meldung: %s', [AFinding.Message]).AppendLine;
    Builder.AppendFormat('- Konfidenz: %s', [ConfidenceText(AFinding.Confidence)]).AppendLine;
    if Known and (Entry.Description <> '') then
    begin
      Builder.AppendLine;
      Builder.AppendLine('### Regel');
      Builder.AppendLine;
      Builder.AppendLine(Entry.Description);
    end;
    if Length(Lines) > 0 then
    begin
      First := Max(0, Line - AContext);
      Last := Min(High(Lines), Line + AContext);
      Builder.AppendLine;
      Builder.AppendLine('### Code');
      Builder.AppendLine;
      Builder.AppendLine('```pascal');
      for Index := First to Last do
      begin
        if Index = Line then
          Marker := '>'
        else
          Marker := ' ';
        Builder.AppendFormat('%s %4d | %s', [Marker, Index + 1, Lines[Index]]).AppendLine;
      end;
      Builder.AppendLine('```');
    end;
    if Known and ((Entry.Bad <> '') or (Entry.Good <> '')) then
    begin
      Builder.AppendLine;
      Builder.AppendLine('### Vorher/Nachher');
      if Entry.Bad <> '' then
      begin
        Builder.AppendLine;
        Builder.AppendLine('Vorher:');
        Builder.AppendLine;
        Builder.AppendLine('```pascal');
        Builder.AppendLine(TrimRight(Entry.Bad));
        Builder.AppendLine('```');
      end;
      if Entry.Good <> '' then
      begin
        Builder.AppendLine;
        Builder.AppendLine('Nachher:');
        Builder.AppendLine;
        Builder.AppendLine('```pascal');
        Builder.AppendLine(TrimRight(Entry.Good));
        Builder.AppendLine('```');
      end;
    end;
    Result := TrimRight(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

initialization
  SharedLock := TObject.Create;

finalization
  FreeAndNil(Shared);
  FreeAndNil(SharedLock);

end.
