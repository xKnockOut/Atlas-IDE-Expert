unit Atlas.IDE.Tasks.Launcher;

// Starter der Projektaufgaben (#900) für die Aufgaben der IDE
// (Atlas.IDE.Tasks.Runner): Ende eines Laufs und die Fabrik des Starters. Den
// Starter selbst (ein Thread je Lauf, Atlas.IDE.BuildTools.Adapters.TaskLauncher) und
// den Prozess (Atlas.Core.Tasks.Providers.Process) setzt die Komposition des
// Moduls zusammen.

interface

uses
  System.SysUtils,
  Atlas.Core.Tasks.Contract,
  Atlas.Core.Tasks.Runs,
  Atlas.IDE.Tasks.Output;

type
  /// <summary>Lauf AId ist mit ARun zu Ende (im Hauptthread).</summary>
  TAtlasTaskRunEnded = reference to procedure(AId: Integer; const ARun: TAtlasTaskRun);

  /// <summary>Starter für AOutput (gehört dem Aufrufer und lebt länger); AOnEnded bekommt das Ende, solange AAlive
  /// True liefert.</summary>
  TAtlasIdeTaskLauncherFactory = reference to function(AOutput: TAtlasIdeTaskOutput;
    const AOnEnded: TAtlasTaskRunEnded; const AAlive: TFunc<Boolean>): IAtlasTaskLauncher;

implementation

end.
