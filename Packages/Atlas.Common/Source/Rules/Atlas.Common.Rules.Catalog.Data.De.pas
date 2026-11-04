unit Atlas.Common.Rules.Catalog.Data.De;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern. Die Regeln stehen je Gruppe in den Teil-Units Atlas.Common.Rules.Catalog.Data.De.<Gruppe>.

interface

/// <summary>Der Katalog aus regelkatalog.de.json als JSON, Regeln nach Gruppen geordnet.</summary>
function RuleCatalogDeJson: string;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Catalog.Data.De.FindBugs,
  Atlas.Common.Rules.Catalog.Data.De.Exceptions,
  Atlas.Common.Rules.Catalog.Data.De.Threads,
  Atlas.Common.Rules.Catalog.Data.De.Database,
  Atlas.Common.Rules.Catalog.Data.De.CompilerSyntax,
  Atlas.Common.Rules.Catalog.Data.De.CompilerNames,
  Atlas.Common.Rules.Catalog.Data.De.CompilerTypes,
  Atlas.Common.Rules.Catalog.Data.De.Robustness,
  Atlas.Common.Rules.Catalog.Data.De.Performance,
  Atlas.Common.Rules.Catalog.Data.De.Security,
  Atlas.Common.Rules.Catalog.Data.De.Components,
  Atlas.Common.Rules.Catalog.Data.De.Forms,
  Atlas.Common.Rules.Catalog.Data.De.Architecture,
  Atlas.Common.Rules.Catalog.Data.De.Style,
  Atlas.Common.Rules.Catalog.Data.De.Packages,
  Atlas.Common.Rules.Catalog.Data.De.Internal;

/// <summary>Zeilen mit #10 verbunden, auch nach der letzten.</summary>
function Joined(const ALines: array of string): string;
begin
  Result := string.Join(#10, ALines) + #10;
end;

function RuleCatalogDeJson: string;
begin
  Result := '{' + #10 + '  "rules": [' + #10 +
    Joined(CatalogLinesDeFindBugs) + ',' + #10 +
    Joined(CatalogLinesDeExceptions) + ',' + #10 +
    Joined(CatalogLinesDeThreads) + ',' + #10 +
    Joined(CatalogLinesDeDatabase) + ',' + #10 +
    Joined(CatalogLinesDeCompilerSyntax) + ',' + #10 +
    Joined(CatalogLinesDeCompilerNames) + ',' + #10 +
    Joined(CatalogLinesDeCompilerTypes) + ',' + #10 +
    Joined(CatalogLinesDeRobustness) + ',' + #10 +
    Joined(CatalogLinesDePerformance) + ',' + #10 +
    Joined(CatalogLinesDeSecurity) + ',' + #10 +
    Joined(CatalogLinesDeComponents) + ',' + #10 +
    Joined(CatalogLinesDeForms) + ',' + #10 +
    Joined(CatalogLinesDeArchitecture) + ',' + #10 +
    Joined(CatalogLinesDeStyle) + ',' + #10 +
    Joined(CatalogLinesDePackages) + ',' + #10 +
    Joined(CatalogLinesDeInternal) +
    '  ]' + #10 + '}' + #10;
end;

end.
