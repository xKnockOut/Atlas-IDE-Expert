unit Rules.Catalog.Data.De;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern. Die Regeln stehen je Gruppe in den Teil-Units Rules.Catalog.Data.De.<Gruppe>.

interface

/// <summary>Der Katalog aus regelkatalog.de.json als JSON, Regeln nach Gruppen geordnet.</summary>
function RuleCatalogDeJson: string;

implementation

uses
  System.SysUtils,
  Rules.Catalog.Data.De.FindBugs,
  Rules.Catalog.Data.De.Exceptions,
  Rules.Catalog.Data.De.Threads,
  Rules.Catalog.Data.De.Database,
  Rules.Catalog.Data.De.CompilerSyntax,
  Rules.Catalog.Data.De.CompilerNames,
  Rules.Catalog.Data.De.CompilerTypes,
  Rules.Catalog.Data.De.Robustness,
  Rules.Catalog.Data.De.Migration,
  Rules.Catalog.Data.De.Performance,
  Rules.Catalog.Data.De.Security,
  Rules.Catalog.Data.De.Components,
  Rules.Catalog.Data.De.Forms,
  Rules.Catalog.Data.De.Architecture,
  Rules.Catalog.Data.De.Style,
  Rules.Catalog.Data.De.Packages,
  Rules.Catalog.Data.De.Internal;

/// <summary>Zeilen mit #10 verbunden, auch nach der letzten.</summary>
function Joined(const ALines: array of string): string;
begin
  Result := string.Join(#10, ALines) + #10;
end;

function RuleCatalogDeJson: string;
begin
  Result := '{' + #10 + '  "rules": [' + #10 +
    Joined(cCatalogLinesDeFindBugs) + ',' + #10 +
    Joined(cCatalogLinesDeExceptions) + ',' + #10 +
    Joined(cCatalogLinesDeThreads) + ',' + #10 +
    Joined(cCatalogLinesDeDatabase) + ',' + #10 +
    Joined(cCatalogLinesDeCompilerSyntax) + ',' + #10 +
    Joined(cCatalogLinesDeCompilerNames) + ',' + #10 +
    Joined(cCatalogLinesDeCompilerTypes) + ',' + #10 +
    Joined(cCatalogLinesDeRobustness) + ',' + #10 +
    Joined(cCatalogLinesDeMigration) + ',' + #10 +
    Joined(cCatalogLinesDePerformance) + ',' + #10 +
    Joined(cCatalogLinesDeSecurity) + ',' + #10 +
    Joined(cCatalogLinesDeComponents) + ',' + #10 +
    Joined(cCatalogLinesDeForms) + ',' + #10 +
    Joined(cCatalogLinesDeArchitecture) + ',' + #10 +
    Joined(cCatalogLinesDeStyle) + ',' + #10 +
    Joined(cCatalogLinesDePackages) + ',' + #10 +
    Joined(cCatalogLinesDeInternal) +
    '  ]' + #10 + '}' + #10;
end;

end.
