unit Atlas.IDE.Debug.Composition.Session;

// Modul Debugger (#1455), Teil der Komposition: die Teile der Feature-Tabelle, die der Debug-Sitzung zuhören, in
// zwei Gruppen nach ihrer Stelle in der Startreihenfolge:
//   - DebugExceptionParts: Exception-Verlauf (#517), nur eigener Code (#578) und Exception-Leiste (#783).
//   - DebugThreadParts: Threads beim Halt: „Was wartet worauf?“ (#587) und „Parallele Aufrufstapel“ (#837).
// Dazu die Befehle beider, die Atlas.IDE.Debug.Composition in seine Befehle aufnimmt, und das Thema des Fensters.
// Atlas.IDE.Debug.Composition stellt die Teile über den Scope des Moduls bereit.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Exception-Verlauf, nur eigener Code und Exception-Leiste.</summary>
function DebugExceptionParts: TArray<IAtlasFeaturePart>;
/// <summary>Teile für die Threads eines angehaltenen Programms.</summary>
function DebugThreadParts: TArray<IAtlasFeaturePart>;
/// <summary>Befehl Atlas.DebugDeadlocks: Was wartet worauf? (#587).</summary>
procedure RunDebugDeadlocks;
/// <summary>Befehl „Was wartet worauf?“ zeigen? (debug.deadlocks)</summary>
function DebugDeadlocksVisible: Boolean;
/// <summary>Befehl Atlas.DebugParallelStacks: Fenster „Parallele Aufrufstapel“ (#837).</summary>
procedure ShowDebugParallelStacks;
/// <summary>Befehl „Parallele Aufrufstapel“ zeigen? (debug.parallelStacks)</summary>
function DebugParallelStacksVisible: Boolean;
/// <summary>Nach einem Wechsel des IDE-Themas.</summary>
procedure DebugThreadsThemeChanged;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Status.Registry,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.OwnCode,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.Deadlocks,
  Atlas.IDE.Debug.ParallelStacks;

{ Dienste von Base }

procedure MessageLine(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

function DebugExceptionBarVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory and TAtlasIdeSettings.Current.DebugExceptionBanner;
end;

function DebugDeadlocksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugDeadlocks;
end;

procedure RunDebugDeadlocks;
begin
  TAtlasIdeDebugDeadlocks.Run;
end;

function DebugParallelStacksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugParallelStacks;
end;

procedure ShowDebugParallelStacks;
begin
  TAtlasIdeDebugParallelStacks.ShowWindow;
end;

procedure DebugThreadsThemeChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugParallelStacks.ThemeChanged);
end;

{ Start der Teile }

procedure StartDebugExceptions;
begin
  TAtlasIdeDebugExceptions.Start(MessageLine);
end;

procedure StartDebugOwnCode;
begin
  TAtlasIdeDebugOwnCode.Start(MessageLine);
end;

procedure StartDebugExceptionBar;
begin
  TAtlasIdeDebugExceptionBar.Start(MessageLine, TAtlasStatusRegistry.Default);
end;

procedure StartDebugDeadlocks;
begin
  TAtlasIdeDebugDeadlocks.Start(MessageLine);
end;

{ Teile der Feature-Tabelle }

/// <summary>Exception-Verlauf, nur eigener Code und Exception-Leiste.</summary>
function DebugExceptionParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Exception-Verlauf (#517): Zuhörer der Debug-Sitzung; aus = kein Notifier beim Debugger.
    TAtlasFeaturePart.When('DebugExceptions',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugExceptionHistory;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugExceptions.Started;
      end, StartDebugExceptions, TAtlasIdeDebugExceptions.Release),
    // Nur eigener Code (#578): Zuhörer der Debug-Sitzung und Haken an „Einzelne Anweisung“ (F7).
    TAtlasFeaturePart.When('DebugOwnCode',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugJustMyCode;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugOwnCode.Started;
      end, StartDebugOwnCode, TAtlasIdeDebugOwnCode.Release),
    // Exception-Leiste (#783): baut auf dem Exception-Verlauf auf; aus = Dialog der IDE unverändert.
    TAtlasFeaturePart.When('DebugExceptionBar',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and DebugExceptionBarVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugExceptionBar.Started;
      end, StartDebugExceptionBar, TAtlasIdeDebugExceptionBar.Release)]
end;

function DebugThreadParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Was wartet worauf? (#587): Zeitgeber für nachgelieferte Stapel (LLDB) und die Liste im Ergebnisfenster.
    TAtlasFeaturePart.When('DebugDeadlocks',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugDeadlocks;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugDeadlocks.Started;
      end, StartDebugDeadlocks, TAtlasIdeDebugDeadlocks.Release),
    // Parallele Aufrufstapel (#837): Zuhörer der Debug-Sitzung und Fenster; aus = weder Fenster noch Menüpunkt.
    TAtlasFeaturePart.When('DebugParallelStacks',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugParallelStacks;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugParallelStacks.Started;
      end, TAtlasIdeDebugParallelStacks.Start, TAtlasIdeDebugParallelStacks.Release)];
end;

end.
