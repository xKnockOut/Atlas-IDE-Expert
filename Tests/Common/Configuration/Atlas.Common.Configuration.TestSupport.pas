unit Atlas.Common.Configuration.TestSupport;

// Gemeinsame Hilfen der Tests des Konfigurationsparsers (Atlas.Common.Configuration.*.Tests).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser;

/// <summary>Liest AText mit dem Konfigurationsparser; AIssues erhält die Meldungen.</summary>
function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;
/// <summary>Einstellungen aus AJson ('' = Vorgaben); prüft, dass der Parser nichts zu beanstanden hat.</summary>
function SettingsOf(const AJson: string): TServerSettings;

implementation

uses
  DUnitX.TestFramework;

function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;
begin
  Result := TConfigurationParser.Parse(AText, AIssues);
end;

function SettingsOf(const AJson: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  if AJson = '' then
  begin
    Exit(TServerSettings.Default);
  end;
  Result := TConfigurationParser.Parse(AJson, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), AJson);
end;

end.
