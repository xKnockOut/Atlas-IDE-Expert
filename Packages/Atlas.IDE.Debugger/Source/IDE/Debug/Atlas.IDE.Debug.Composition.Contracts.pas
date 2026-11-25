unit Atlas.IDE.Debug.Composition.Contracts;

// Verträge des Moduls Debugger für andere Module (Modulregel 6), eigene Unit
// neben Atlas.IDE.Debug.Composition: der Bericht über die Debug-Sitzung
// (IAtlasDebugReportSource, #1276), der Halt für „Test daraus anlegen …“
// (IAtlasDebugStopSource, #1873), die Steuerung für KI-Assistenten
// (IAtlasDebugControl, #1874) und der Empfänger für bekannte Fehler aus dem Tracker
// (IAtlasKnownErrorsView, #2460). Alle gehen über den Scope des Moduls und
// werden beim Abmelden mit ihm gelöst (Regel 4).
// Dazu die Adapter, die Teile des Moduls über eine Fabrik bekommen (Rollenmatrix:
// nur die Komposition erzeugt Adapters): Ziel der Debug-Sitzung, Auswertung im
// Thread und der Speicher des Programms für die Objektzählung.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Verträge des Debuggers über AScope bereitstellen.</summary>
procedure ProvideDebugContracts(const AScope: IAtlasModuleScope);
/// <summary>Adapter für die Teile des Moduls setzen (Ziel der Debug-Sitzung, Auswertung im Thread, Speicher für
/// die Objektzählung); vor dem ersten Teil.</summary>
procedure UseDebugAdapters;
/// <summary>Beim Abmelden: Auswertung und Speicherzugang lösen.</summary>
procedure ReleaseDebugAdapters;

implementation

uses
  Atlas.Core.Debug.Contract,
  Atlas.IDE.Debug.Adapters.AssistantControl,
  Atlas.IDE.Debug.Adapters.Report,
  Atlas.IDE.Debug.Adapters.StopSource,
  Atlas.IDE.Debug.Adapters.KnownErrorsView,
  Atlas.IDE.Debug.Adapters.SessionTarget,
  Atlas.IDE.Debug.Adapters.ThreadEvaluator,
  Atlas.IDE.Debug.Adapters.ProcessMemory,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ObjectCount,
  Atlas.IDE.Base.Foundation.DebugControl,
  Atlas.IDE.Base.Foundation.KnownErrors,
  Atlas.IDE.Base.Foundation.DebugReport,
  Atlas.IDE.Base.Foundation.DebugStop;

procedure ProvideDebugContracts(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasDebugReportSource, TAtlasIdeDebugReportSource.Create as IAtlasDebugReportSource);
  AScope.Provide(IAtlasDebugStopSource, TAtlasIdeDebugStopSource.Create as IAtlasDebugStopSource);
  AScope.Provide(IAtlasDebugControl, TAtlasIdeDebugAssistantControl.Create as IAtlasDebugControl);
  AScope.Provide(IAtlasKnownErrorsView, TAtlasIdeDebugKnownErrorsView.Create as IAtlasKnownErrorsView);
end;

/// <summary>Neue Auswertung im angehaltenen Thread.</summary>
function NewEvaluator: IAtlasDebugEvaluator;
begin
  Result := TAtlasIdeDebugThreadEvaluator.Create;
end;

/// <summary>Speicher des Programms APid zum Lesen öffnen.</summary>
function OpenMemory(APid: Cardinal; out AMemory: IAtlasProcessMemory; out AError: string): Boolean;
begin
  Result := TAtlasIdeProcessMemory.Open(APid, AMemory, AError);
end;

procedure UseDebugAdapters;
begin
  TAtlasIdeDebugSession.UseAdapters(TAtlasIdeDebugTarget.Create, NewEvaluator);
  TAtlasIdeDebugObjectCount.OpenMemory := OpenMemory;
end;

procedure ReleaseDebugAdapters;
begin
  TAtlasIdeDebugObjectCount.OpenMemory := nil;
  TAtlasIdeDebugSession.UseAdapters(nil, nil);
end;

end.
