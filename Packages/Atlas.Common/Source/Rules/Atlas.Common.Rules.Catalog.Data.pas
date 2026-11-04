unit Atlas.Common.Rules.Catalog.Data;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.
// Nicht von Hand ändern. Die Zeilen stehen in den Teil-Units Atlas.Common.Rules.Catalog.Data.<Sprache><n>.

interface

/// <summary>Englischer Grundkatalog als JSON.</summary>
function RuleCatalogBaseJson: string;
/// <summary>Übersetzung als JSON, '' für unbekannte Sprachen.</summary>
function RuleCatalogOverlayJson(const ALanguage: string): string;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Catalog.Data.En1,
  Atlas.Common.Rules.Catalog.Data.En2,
  Atlas.Common.Rules.Catalog.Data.En3,
  Atlas.Common.Rules.Catalog.Data.En4,
  Atlas.Common.Rules.Catalog.Data.De1,
  Atlas.Common.Rules.Catalog.Data.De2,
  Atlas.Common.Rules.Catalog.Data.De3;

/// <summary>Zeilen mit #10 verbunden, auch nach der letzten.</summary>
function Joined(const ALines: array of string): string;
begin
  Result := string.Join(#10, ALines) + #10;
end;

function RuleCatalogBaseJson: string;
begin
  Result := Joined(CatalogLinesEn1) +
    Joined(CatalogLinesEn2) +
    Joined(CatalogLinesEn3) +
    Joined(CatalogLinesEn4);
end;

function RuleCatalogOverlayJson(const ALanguage: string): string;
begin
  if SameText(ALanguage, 'de') then
  begin
    Exit(Joined(CatalogLinesDe1) +
      Joined(CatalogLinesDe2) +
      Joined(CatalogLinesDe3));
  end;
  Result := '';
end;

end.
