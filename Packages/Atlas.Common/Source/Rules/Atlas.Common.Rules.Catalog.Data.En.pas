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
    Joined(cCatalogLinesEnFindBugs) + ',' + #10 +
    Joined(cCatalogLinesEnExceptions) + ',' + #10 +
    Joined(cCatalogLinesEnThreads) + ',' + #10 +
    Joined(cCatalogLinesEnDatabase) + ',' + #10 +
    Joined(cCatalogLinesEnCompilerSyntax) + ',' + #10 +
    Joined(cCatalogLinesEnCompilerNames) + ',' + #10 +
    Joined(cCatalogLinesEnCompilerTypes) + ',' + #10 +
    Joined(cCatalogLinesEnRobustness) + ',' + #10 +
    Joined(cCatalogLinesEnPerformance) + ',' + #10 +
    Joined(cCatalogLinesEnSecurity) + ',' + #10 +
    Joined(cCatalogLinesEnComponents) + ',' + #10 +
    Joined(cCatalogLinesEnForms) + ',' + #10 +
    Joined(cCatalogLinesEnArchitecture) + ',' + #10 +
    Joined(cCatalogLinesEnStyle) + ',' + #10 +
    Joined(cCatalogLinesEnPackages) + ',' + #10 +
    Joined(cCatalogLinesEnInternal) +
    '  ]' + #10 + '}' + #10;
end;

end.
