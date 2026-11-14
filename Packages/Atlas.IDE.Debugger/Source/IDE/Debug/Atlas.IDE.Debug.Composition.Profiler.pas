unit Atlas.IDE.Debug.Composition.Profiler;

// Modul Debugger, Teil der Komposition: Stichproben-Profiler (#2057). Liefert
// das Teil der Feature-Tabelle (nur mit debug.profiler), die Befehle
// „Profil“ (Fenster), „Mit Profil ausführen“ und „Profil starten/beenden“,
// ihre Einträge im Atlas-Menü und das Weiterreichen von Einstellungen und
// Thema; Atlas.IDE.Debug.Composition stellt sie über den Scope des Moduls
// bereit.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

/// <summary>AScopeOf liefert den Scope des Moduls für Antworten des Servers.</summary>
function ProfilerParts(const AScopeOf: TFunc<IAtlasModuleScope>): TArray<IAtlasFeaturePart>;
function ProfilerCommands: TArray<TAtlasModuleCommand>;
function ProfilerMenuEntries: TArray<TAtlasMenuEntry>;
procedure ApplyProfilerSettings;
procedure ProfilerThemeChanged;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Profiler,
  Atlas.UI.Debug.Profile.Strings;

const
  cWindowCommand = 'Atlas.DebugProfile';
  cRunCommand = 'Atlas.DebugProfileRun';
  cToggleCommand = 'Atlas.DebugProfileToggle';

function ProfilerVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugProfiler;
end;

function ProfilerParts(const AScopeOf: TFunc<IAtlasModuleScope>): TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Nur Zeitgeber und Fenster; gemessen wird im Server.
    TAtlasFeaturePart.When('DebugProfiler',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and ProfilerVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugProfiler.Started;
      end,
      procedure
      begin
        TAtlasIdeDebugProfiler.Start(AScopeOf,
          procedure(AText: string)
          begin
            TAtlasIdeHost.Message(AText);
          end);
      end, TAtlasIdeDebugProfiler.Release)];
end;

/// <summary>Befehl abgesichert ausführen (#493), sichtbar nur mit debug.profiler.</summary>
function ProfilerCommand(const AId: string; ATextId: TAtlasProfileTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasProfileStrings.Text(ATextId);
  Result.Run :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, ARun);
    end;
  Result.Visible := AVisible;
end;

function ProfilerCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    ProfilerCommand(cWindowCommand, TAtlasProfileTextId.ProfileWindowCommand, TAtlasIdeDebugProfiler.ShowWindow,
      ProfilerVisible),
    ProfilerCommand(cRunCommand, TAtlasProfileTextId.ProfileRunCommand, TAtlasIdeDebugProfiler.RunWithProfile,
      ProfilerVisible),
    ProfilerCommand(cToggleCommand, TAtlasProfileTextId.ProfileToggleCommand, TAtlasIdeDebugProfiler.Toggle,
      ProfilerVisible)];
end;

function AtlasMenuEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := TAtlasMenuPlace.AtlasMenu;
end;

function ProfilerMenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [AtlasMenuEntry(cWindowCommand), AtlasMenuEntry(cRunCommand), AtlasMenuEntry(cToggleCommand)];
end;

procedure ApplyProfilerSettings;
begin
  TAtlasIdeDebugProfiler.ApplySettings;
end;

procedure ProfilerThemeChanged;
begin
  TAtlasIdeDebugProfiler.ThemeChanged;
end;

end.
