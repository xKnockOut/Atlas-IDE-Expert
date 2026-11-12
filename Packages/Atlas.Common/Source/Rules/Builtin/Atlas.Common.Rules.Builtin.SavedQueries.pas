unit Atlas.Common.Rules.Builtin.SavedQueries;

// Gespeicherte Abfragen mit "failIfAny" als Regeln query:<name> (#1351): Jeder
// Treffer in der geprüften Datei wird ein Befund mit dem Schweregrad und der
// Meldung aus atlas.json. Damit erscheinen sie im Editor, bei --check und in
// SARIF, und die Baseline blendet sie wie andere Befunde aus.
//
// Gerechnet wird über ICodeQueries des Arbeitsbereichs: Der Dienst hält das
// Ergebnis je Index-Stand, darum kostet jede weitere Datei nur das Filtern der
// Zeilen. Ohne Dienst (Datei ohne Projekt, find_unused_code) schweigt die Regel.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

type
  TSavedQueryRule = class(TInterfacedObject, IRule)
  public const
    cPrefix = 'query:';
  private
    FQuery: TSavedQuery;
  public
    constructor Create(const AQuery: TSavedQuery);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Kennung der Regel zur Abfrage AName: query:&lt;name&gt;.</summary>
    class function RuleId(const AName: string): string; static;
    /// <summary>Eine Regel je gespeicherter Abfrage mit failIfAny; keine, wenn query.enabled aus ist.</summary>
    class function RulesOf(const ASettings: TServerSettings): TArray<IRule>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Output,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TSavedQueriesText = (Title);

const
  cTexts: array[TSavedQueriesText] of TAtlasText = (
    (De: 'Gespeicherte Abfrage: %s'; En: 'Saved query: %s'));

{$SCOPEDENUMS OFF}

{ TSavedQueryRule }

constructor TSavedQueryRule.Create(const AQuery: TSavedQuery);
begin
  inherited Create;
  FQuery := AQuery;
end;

class function TSavedQueryRule.RuleId(const AName: string): string;
begin
  Result := cPrefix + AName;
end;

class function TSavedQueryRule.RulesOf(const ASettings: TServerSettings): TArray<IRule>;
var
  mQuery: TSavedQuery;
begin
  Result := nil;
  if not ASettings.QueryEnabled then
  begin
    Exit;
  end;
  for mQuery in ASettings.Queries do
  begin
    if mQuery.FailIfAny then
    begin
      Result := Result + [TSavedQueryRule.Create(mQuery) as IRule];
    end;
  end;
end;

function TSavedQueryRule.Descriptor: TRuleDescriptor;
var
  mDescription: string;
begin
  mDescription := FQuery.Description;
  if mDescription = '' then
  begin
    mDescription := cTexts[TSavedQueriesText.Title].Fmt([FQuery.Query]);
  end;
  Result := TRuleDescriptor.Create(RuleId(FQuery.Name), FQuery.Severity, mDescription);
end;

procedure TSavedQueryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRequest: TQueryRequest;
  mResult: TQueryResult;
  mRow: TQueryRow;
begin
  if (AContext.Queries = nil) or (AContext.FileName = '') then
  begin
    Exit;
  end;
  mRequest := TQueryRequest.Create(FQuery.Query, 0);
  // Felder der Meldung als Spalten, damit {methods} auch ohne Bedingung auf methods einen Wert hat.
  mRequest.Fields := TQueryResult.Placeholders(FQuery.Message);
  mResult := AContext.Queries.Execute(mRequest);
  // Eine fehlerhafte Abfrage meldet die Konfiguration (atlas.json) mit Spalte, nicht jede Datei.
  if mResult.Failed then
  begin
    Exit;
  end;
  for mRow in mResult.Rows do
  begin
    if SameText(mRow.FileName, AContext.FileName) then
    begin
      AReport.Add(mRow.Range, mResult.Message(TQueryOutput.MessageTemplate(FQuery.Message), mRow));
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.SavedQueries', cTexts);

end.
