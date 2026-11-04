unit Atlas.Common.Rules.Catalog.Data.En;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern. Die Regeln stehen je Gruppe in den Teil-Units Atlas.Common.Rules.Catalog.Data.En.<Gruppe>.

interface

/// <summary>Der Katalog aus regelkatalog.json als JSON, Regeln nach Gruppen geordnet.</summary>
function RuleCatalogEnJson: string;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Catalog.Data.En.FindBugs,
  Atlas.Common.Rules.Catalog.Data.En.Exceptions,
  Atlas.Common.Rules.Catalog.Data.En.Threads,
  Atlas.Common.Rules.Catalog.Data.En.Database,
  Atlas.Common.Rules.Catalog.Data.En.CompilerSyntax,
  Atlas.Common.Rules.Catalog.Data.En.CompilerNames,
  Atlas.Common.Rules.Catalog.Data.En.CompilerTypes,
  Atlas.Common.Rules.Catalog.Data.En.Robustness,
  Atlas.Common.Rules.Catalog.Data.En.Performance,
  Atlas.Common.Rules.Catalog.Data.En.Security,
  Atlas.Common.Rules.Catalog.Data.En.Components,
  Atlas.Common.Rules.Catalog.Data.En.Forms,
  Atlas.Common.Rules.Catalog.Data.En.Architecture,
  Atlas.Common.Rules.Catalog.Data.En.Style,
  Atlas.Common.Rules.Catalog.Data.En.Packages,
  Atlas.Common.Rules.Catalog.Data.En.Internal;

/// <summary>Zeilen mit #10 verbunden, auch nach der letzten.</summary>
function Joined(const ALines: array of string): string;
begin
  Result := string.Join(#10, ALines) + #10;
end;

function RuleCatalogEnJson: string;
begin
  Result := '{' + #10 + '  "rules": [' + #10 +
    Joined(CatalogLinesEnFindBugs) + ',' + #10 +
    Joined(CatalogLinesEnExceptions) + ',' + #10 +
    Joined(CatalogLinesEnThreads) + ',' + #10 +
    Joined(CatalogLinesEnDatabase) + ',' + #10 +
    Joined(CatalogLinesEnCompilerSyntax) + ',' + #10 +
    Joined(CatalogLinesEnCompilerNames) + ',' + #10 +
    Joined(CatalogLinesEnCompilerTypes) + ',' + #10 +
    Joined(CatalogLinesEnRobustness) + ',' + #10 +
    Joined(CatalogLinesEnPerformance) + ',' + #10 +
    Joined(CatalogLinesEnSecurity) + ',' + #10 +
    Joined(CatalogLinesEnComponents) + ',' + #10 +
    Joined(CatalogLinesEnForms) + ',' + #10 +
    Joined(CatalogLinesEnArchitecture) + ',' + #10 +
    Joined(CatalogLinesEnStyle) + ',' + #10 +
    Joined(CatalogLinesEnPackages) + ',' + #10 +
    Joined(CatalogLinesEnInternal) +
    '  ]' + #10 + '}' + #10;
end;

end.
