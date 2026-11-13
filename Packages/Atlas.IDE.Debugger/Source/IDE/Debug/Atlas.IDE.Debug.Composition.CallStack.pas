unit Atlas.IDE.Debug.Composition.CallStack;

// Modul Debugger, Teil der Komposition: das Fenster „Atlas-Aufrufstapel“ (#843). Liefert den Teil der
// Feature-Tabelle (debug.callStackWindow; Serverantworten über den Scope des Moduls), den Befehl samt Sichtbarkeit
// und das Weiterreichen des Themas; Atlas.IDE.Debug.Composition.Session nimmt sie in die Teile und Befehle der
// Threads auf.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Teil „DebugCallStackWindow“; Serverantworten über AScope.</summary>
function CallStackParts(const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
/// <summary>Befehl Atlas.DebugCallStack: Fenster „Atlas-Aufrufstapel“, sichtbar mit debug.callStackWindow.</summary>
function CallStackCommands: TArray<TAtlasModuleCommand>;
/// <summary>Nach einem Wechsel des IDE-Themas.</summary>
procedure CallStackThemeChanged;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.CallStack,
  Atlas.UI.Debug.Strings;

function CallStackCommands: TArray<TAtlasModuleCommand>;
var
  mCommand: TAtlasModuleCommand;
begin
  mCommand := Default(TAtlasModuleCommand);
  mCommand.Id := 'Atlas.DebugCallStack';
  mCommand.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackCommand);
  mCommand.Run :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugCallStack.ShowWindow);
    end;
  mCommand.Visible :=
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.DebugCallStackWindow;
    end;
  SetLength(Result, 1);
  Result[0] := mCommand;
end;

procedure CallStackThemeChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugCallStack.ThemeChanged);
end;

/// <summary>Start mit Serverbefehlen im Hintergrund über Base und den Scope AScope; die Antwort kommt nur, solange
/// das Modul angemeldet ist.</summary>
function CallStackStarter(const AScope: IAtlasModuleScope): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeDebugCallStack.Start(
        function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
        begin
          Result := TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger, ACommand, AArgumentsJson,
            ATimeoutMs, ADone);
        end,
        procedure(AText: string)
        begin
          TAtlasIdeHost.Message(AText);
        end);
    end;
end;

function CallStackParts(const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Fenster „Atlas-Aufrufstapel“: Zuhörer der Debug-Sitzung, Zeitgeber und Fenster; aus = nichts, der
    // Aufrufstack der IDE bleibt, wie er ist.
    TAtlasFeaturePart.When('DebugCallStackWindow',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugCallStackWindow;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugCallStack.Started;
      end, CallStackStarter(AScope), TAtlasIdeDebugCallStack.Release)];
end;

end.
