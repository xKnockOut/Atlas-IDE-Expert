unit Atlas.IDE.Debug.Composition.Session;

// Modul Debugger (#1455), Teil der Komposition: die Teile der Feature-Tabelle, die der Debug-Sitzung zuhören, in
// zwei Gruppen nach ihrer Stelle in der Startreihenfolge:
//   - DebugExceptionParts: Exception-Verlauf (#517), nur eigener Code (#578) und Exception-Leiste (#783).
//   - DebugThreadParts: Threads beim Halt: „Was wartet worauf?“ (#587), „Parallele Aufrufstapel“ (#837) und
//     „Threads im Quelltext“ (#852) samt Schicht der Rinne (ProvideDebugThreadLayers) und die Herkunft eingereihter
//     Methoden (#859, experimentell).
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
/// <summary>Befehle „Thread markieren“, „einfrieren“, „auftauen“, „Alle auftauen“ (#852).</summary>
function DebugThreadCommands: TArray<TAtlasModuleCommand>;
/// <summary>Schicht der Rinne für die Threads im Quelltext (#852) über den Scope des Moduls.</summary>
procedure ProvideDebugThreadLayers(const AScope: IAtlasModuleScope);

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Status.Registry,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.OwnCode,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.Deadlocks,
  Atlas.IDE.Debug.ParallelStacks,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.ThreadsInSource,
  Atlas.IDE.Debug.ThreadsGutter,
  Atlas.IDE.Debug.AsyncOrigin,
  Atlas.UI.Debug.Strings;

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

procedure StartDebugThreadsInSource;
begin
  TAtlasIdeDebugThreadsInSource.Start(MessageLine, TAtlasStatusRegistry.Default);
end;

procedure StartDebugAsyncOrigin;
begin
  TAtlasIdeDebugAsyncOrigin.Start(MessageLine, TAtlasStatusRegistry.Default);
end;

{ Threads im Quelltext (#852) }

function DebugThreadsInSourceVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugThreadsInSource and TAtlasIdeDebugThreadsInSource.Started;
end;

function DebugThreadFreezeVisible: Boolean;
begin
  Result := DebugThreadsInSourceVisible and TAtlasIdeDebugThreadsInSource.FreezeAvailable;
end;

function DebugThreadsFrozenVisible: Boolean;
begin
  Result := DebugThreadsInSourceVisible and TAtlasIdeDebugThreadsInSource.AnyFrozen;
end;

/// <summary>Befehl, dessen Ausführung über TAtlasFeature.Debugger gesichert ist.</summary>
function ThreadCommand(const AId: string; ACaption: TAtlasDebugTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasDebugStrings.Text(ACaption);
  Result.Run :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, ARun);
    end;
  Result.Visible := AVisible;
end;

function DebugThreadCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    ThreadCommand('Atlas.DebugThreadFlag', TAtlasDebugTextId.ThreadMarksFlagCommand,
      TAtlasIdeDebugThreadsInSource.FlagAtLine, DebugThreadsInSourceVisible),
    // Einfrieren nur mit debug.threadFreeze (experimentell); Auftauen, solange ein Thread eingefroren ist.
    ThreadCommand('Atlas.DebugThreadFreeze', TAtlasDebugTextId.ThreadMarksFreezeCommand,
      TAtlasIdeDebugThreadsInSource.FreezeAtLine, DebugThreadFreezeVisible),
    ThreadCommand('Atlas.DebugThreadThaw', TAtlasDebugTextId.ThreadMarksThawCommand,
      TAtlasIdeDebugThreadsInSource.ThawAtLine, DebugThreadsFrozenVisible),
    ThreadCommand('Atlas.DebugThreadsThawAll', TAtlasDebugTextId.ThreadMarksThawAllCommand,
      TAtlasIdeDebugThreadsInSource.ThawAll, DebugThreadsFrozenVisible)];
end;

procedure ProvideDebugThreadLayers(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasGutterLayer, TAtlasIdeDebugThreadsGutter.Create as IAtlasGutterLayer);
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
      end, TAtlasIdeDebugParallelStacks.Start, TAtlasIdeDebugParallelStacks.Release),
    // Threads im Quelltext (#852): Zuhörer der Debug-Sitzung; Release taut alle eingefrorenen Threads auf.
    TAtlasFeaturePart.When('DebugThreadsInSource',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugThreadsInSource;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugThreadsInSource.Started;
      end, StartDebugThreadsInSource, TAtlasIdeDebugThreadsInSource.Release),
    // Herkunft eingereihter Methoden (#859, experimentell): Haltepunkte an den Aufrufstellen; Release entfernt sie.
    TAtlasFeaturePart.When('DebugAsyncOrigin',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugAsyncOrigin;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugAsyncOrigin.Started;
      end, StartDebugAsyncOrigin, TAtlasIdeDebugAsyncOrigin.Release)];
end;

end.
