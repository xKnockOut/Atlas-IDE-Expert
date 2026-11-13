unit Atlas.IDE.Debug.Composition.Leaks;

// Modul Debugger, Teil der Komposition: Leckbericht am Ende einer Debug-Sitzung
// und Fenster „Atlas-Lecks“ (#1875). Teil „DebugLeakReport“ (debug.leakReport),
// Befehl Atlas.DebugLeaks und das Thema des Fensters. Atlas.IDE.Debug.Composition
// stellt den Teil über den Scope des Moduls bereit; Antworten des Servers
// laufen über denselben Scope.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Teil „DebugLeakReport“; Serverantworten über AScope.</summary>
function DebugLeakParts(const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
/// <summary>Befehl Atlas.DebugLeaks: Fenster „Atlas-Lecks“ mit dem letzten Bericht.</summary>
procedure ShowDebugLeaks;
/// <summary>Befehl „Atlas-Lecks“ zeigen? (debug.leakReport)</summary>
function DebugLeaksVisible: Boolean;
/// <summary>Nach einem Wechsel des IDE-Themas.</summary>
procedure DebugLeaksThemeChanged;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Leaks;

/// <summary>Start mit dem Scope; eigene Routine, damit die Methodenreferenz nur AScope festhält.</summary>
function Starter(const AScope: IAtlasModuleScope): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeDebugLeaks.Start(AScope,
        procedure(AText: string)
        begin
          TAtlasIdeHost.Message(AText);
        end);
    end;
end;

function DebugLeakParts(const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Leckbericht am Programmende (#1875): Zuhörer der Debug-Sitzung, Zeitgeber und Fenster; aus = nichts.
    TAtlasFeaturePart.When('DebugLeakReport',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugLeakReport;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugLeaks.Started;
      end, Starter(AScope), TAtlasIdeDebugLeaks.Release)];
end;

procedure ShowDebugLeaks;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugLeaks.ShowWindow);
end;

function DebugLeaksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugLeakReport;
end;

procedure DebugLeaksThemeChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugLeaks.ThemeChanged);
end;

end.
