unit Atlas.IDE.Debug.Composition.Contracts;

// Verträge des Moduls Debugger für andere Module (Modulregel 6), aus
// Atlas.IDE.Debug.Composition ausgelagert: der Bericht über die Debug-Sitzung
// (IAtlasDebugReportSource, #1276) und der Halt für „Test daraus anlegen …“
// (IAtlasDebugStopSource, #1873). Beide gehen über den Scope des Moduls und
// werden beim Abmelden mit ihm gelöst (Regel 4).

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Verträge des Debuggers über AScope bereitstellen.</summary>
procedure ProvideDebugContracts(const AScope: IAtlasModuleScope);

implementation

uses
  Atlas.IDE.Debug.Report,
  Atlas.IDE.Debug.StopSource,
  Atlas.IDE.Contracts.DebugReport,
  Atlas.IDE.Contracts.DebugStop;

procedure ProvideDebugContracts(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasDebugReportSource, TAtlasIdeDebugReport.Create as IAtlasDebugReportSource);
  AScope.Provide(IAtlasDebugStopSource, TAtlasIdeDebugStopSource.Create as IAtlasDebugStopSource);
end;

end.
