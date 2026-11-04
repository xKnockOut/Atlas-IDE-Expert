unit Atlas.Common.Configuration.TestSupport;

// Gemeinsame Hilfen der Tests des Konfigurationsparsers (Atlas.Common.Configuration.*.Tests).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser;

/// <summary>Liest AText mit dem Konfigurationsparser; AIssues erhält die Meldungen.</summary>
function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;

implementation

function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;
begin
  Result := TConfigurationParser.Parse(AText, AIssues);
end;

end.
