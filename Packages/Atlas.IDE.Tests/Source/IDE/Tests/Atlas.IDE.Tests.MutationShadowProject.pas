unit Atlas.IDE.Tests.MutationShadowProject;

// Was das Schattenprojekt des Mutationslaufs (#1460) vom Lauf braucht
// (TAtlasIdeMutationShadowSetup), und die Fabrik, über die der Lauf
// (Atlas.IDE.Tests.Mutation) es bekommt. Das Schattenprojekt selbst steht in
// Atlas.IDE.Tests.Adapters.MutationShadowProject; die Komposition des Moduls
// gibt die Fabrik an den Lauf. Nur im Hauptthread verwenden.

interface

uses
  ToolsAPI,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Contract,
  Atlas.IDE.Tests.Runner;

type
  /// <summary>Baut ATarget.Project vollständig mit Konfiguration und Plattform aus ATarget; False mit Grund, wenn
  /// nicht gebaut wird, sonst kommt ADone nach dem Build.</summary>
  TAtlasMutationBuildFunc = reference to function(const ATarget: TAtlasTestTarget;
    const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;

  /// <summary>Lebt, solange der Lauf lebt; Cancelled liest auch der Thread der Test-EXE.</summary>
  TAtlasMutationAlive = class(TInterfacedObject)
  private
    FAlive: Boolean;
    FCancelled: Boolean;
  public
    property Alive: Boolean read FAlive write FAlive;
    property Cancelled: Boolean read FCancelled write FCancelled;
  end;

  /// <summary>Was das Schattenprojekt vom Lauf braucht.</summary>
  TAtlasIdeMutationShadowSetup = record
    /// <summary>Testprojekt des Benutzers und sein Ziel.</summary>
    Original: IOTAProject;
    Target: TAtlasTestTarget;
    /// <summary>Die mutierte Unit.</summary>
    UnitFile: string;
    Build: TAtlasMutationBuildFunc;
    NewRunner: TAtlasTestsRunnerFactory;
    /// <summary>Gehört dem Lauf und lebt länger.</summary>
    Threads: TAtlasWorkerSlot;
    Alive: TAtlasMutationAlive;
  end;

  /// <summary>Schattenprojekt für den Lauf mit ASetup.</summary>
  TAtlasIdeMutationShadowFactory = reference to function(const ASetup: TAtlasIdeMutationShadowSetup):
    IAtlasMutationShadowProject;

implementation

end.
