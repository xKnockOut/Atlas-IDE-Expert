unit Atlas.Common.Rules.Catalog.Data;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.
// Nicht von Hand ändern. Je Sprache eine Unit Atlas.Common.Rules.Catalog.Data.<Sprache>, die Regeln je Gruppe in deren Teil-Units.

interface

/// <summary>Englischer Grundkatalog als JSON.</summary>
function RuleCatalogBaseJson: string;
/// <summary>Übersetzung als JSON, '' für unbekannte Sprachen.</summary>
function RuleCatalogOverlayJson(const ALanguage: string): string;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Catalog.Data.En,
  Atlas.Common.Rules.Catalog.Data.De;

function RuleCatalogBaseJson: string;
begin
  Result := RuleCatalogEnJson;
end;

function RuleCatalogOverlayJson(const ALanguage: string): string;
begin
  if SameText(ALanguage, 'de') then
  begin
    Exit(RuleCatalogDeJson);
  end;
  Result := '';
end;

end.
