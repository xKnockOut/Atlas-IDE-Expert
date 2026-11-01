unit Atlas.IDE.Results.Impact;

// Befehl „Auswirkungen anzeigen“ (#1120): Was ist betroffen, wenn sich das
// Symbol am Cursor ändert? Der Server (atlas/impact) sammelt Aufrufer und
// Verweise, Overrides, Interface-Umsetzungen, Formularbindungen und Tests über
// mehrere Ebenen; das Ergebnisfenster zeigt sie als Baum.
// Die Anfrage kann über viele Units laufen. Sie geht deshalb in einen eigenen
// Thread; die IDE bleibt bedienbar, das Fenster zeigt bis dahin „Ermittle …“.
// Nur die jüngste Anfrage kommt an. Eine andere Tiefe im Fenster fragt mit
// derselben Stelle neu, „Betroffene Tests ausführen“ übergibt die Testnamen an
// den Testläufer (#69). Mit navigation.impact = false gibt es den Befehl nicht.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Lsp.Contract;

type
  /// <summary>Testlauf: Datei aus dem Testprojekt und Namen für --run.</summary>
  TAtlasImpactTestRun = reference to procedure(const AFileName: string; const ATests: TArray<string>);

  TAtlasIdeImpact = class
  private class var
    FWorkers: TArray<TThread>;
    FRequest: Integer;
    FFileName: string;
    FName: string;
    FLine: Integer;
    FCharacter: Integer;
    FRunTests: TAtlasImpactTestRun;
  private
    class procedure Start(ADepth: Integer); static;
    class procedure Reap(AWait: Boolean); static;
    class procedure Show(ARequest: Integer; const AImpact: TAtlasImpact; const AError: string); static;
  public
    /// <summary>Verdrahtet das Ergebnisfenster; ARunTests startet den Testläufer.</summary>
    class procedure Install(const ARunTests: TAtlasImpactTestRun); static;
    /// <summary>Beim Entladen: wartet auf laufende Anfragen und löst die Verdrahtung.</summary>
    class procedure Uninstall; static;
    /// <summary>Ist der Befehl eingeschaltet (navigation.impact)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Auswirkungen des Symbols am Cursor mit der Vorgabe der Tiefe.</summary>
    class procedure ShowAtCursor; static;
    /// <summary>Gleiche Stelle mit anderer Tiefe (Auswahl im Fenster).</summary>
    class procedure Recalculate(ADepth: Integer); static;
    /// <summary>Betroffene Tests über den Testläufer ausführen.</summary>
    class procedure RunTests(const AImpact: TAtlasImpact); static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Results.Commands;

{ TAtlasIdeImpact }

class procedure TAtlasIdeImpact.Install(const ARunTests: TAtlasImpactTestRun);
begin
  FRunTests := ARunTests;
  TAtlasIdeResultsWindow.OnImpactDepth :=
    procedure(ADepth: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Results,
        procedure
        begin
          Recalculate(ADepth);
        end);
    end;
  TAtlasIdeResultsWindow.OnImpactRunTests :=
    procedure(const AImpact: TAtlasImpact)
    var
      Impact: TAtlasImpact;
    begin
      Impact := AImpact;
      TAtlasGuard.Run(TAtlasFeature.Results,
        procedure
        begin
          RunTests(Impact);
        end);
    end;
end;

class procedure TAtlasIdeImpact.Uninstall;
begin
  // Spätere Antworten verwerfen; TAtlasMainThread.Stop räumt schon eingereihte weg. Beim Entladen auf die
  // Arbeiter warten: TAtlasShutdown bricht ihre Anfrage sofort ab. Wird nur der Befehl abgeschaltet (Sicherheits-
  // stufe), bleibt das Package geladen; ein laufender Arbeiter endet dann von selbst und wird später freigegeben.
  Inc(FRequest);
  Reap(TAtlasShutdown.Signalled);
  FRunTests := nil;
  FFileName := '';
  FName := '';
end;

class function TAtlasIdeImpact.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Impact;
end;

class procedure TAtlasIdeImpact.Reap(AWait: Boolean);
var
  Index: Integer;
  Remaining: TArray<TThread>;
begin
  // Fertige Arbeiter freigeben; ein laufender liefert nur noch eine verworfene Antwort und hält den
  // Hauptthread nicht auf. Beim Entladen (AWait) auf alle warten.
  Remaining := nil;
  for Index := 0 to High(FWorkers) do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
    end
    else
      Remaining := Remaining + [FWorkers[Index]];
  FWorkers := Remaining;
end;

class procedure TAtlasIdeImpact.ShowAtCursor;
var
  FileName, Name: string;
  Line, Character: Integer;
begin
  if not Enabled then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.ImpactOff));
    Exit;
  end;
  if not TAtlasIdeResults.AtCursor(FileName, Line, Character, Name) then
    Exit;
  FFileName := FileName;
  FLine := Line;
  FCharacter := Character;
  FName := Name;
  Start(EnsureRange(TAtlasIdeSettings.Current.ImpactDepth, TAtlasPluginSettings.MinImpactDepth,
    TAtlasPluginSettings.MaxImpactDepth));
end;

class procedure TAtlasIdeImpact.Recalculate(ADepth: Integer);
var
  Session: TLspSession;
begin
  if not Enabled or (FFileName = '') then
    Exit;
  Session := TAtlasIdeResults.Session;
  if Session = nil then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Seit der ersten Anfrage kann sich der Text geändert haben.
  TAtlasIdeRename.SyncOpenBuffers(Session);
  Start(EnsureRange(ADepth, TAtlasPluginSettings.MinImpactDepth, TAtlasPluginSettings.MaxImpactDepth));
end;

class procedure TAtlasIdeImpact.Start(ADepth: Integer);
var
  Session: TLspSession;
  Request, Line, Character: Integer;
  FileName: string;
  Worker: TThread;
begin
  Session := TAtlasIdeResults.Session;
  if Session = nil then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Inc(FRequest);
  Request := FRequest;
  FileName := FFileName;
  Line := FLine;
  Character := FCharacter;
  TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.ImpactRunning, [FName, ADepth]), nil);
  Reap(False);
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Impact: TAtlasImpact;
      Error: string;
    begin
      Impact := Default(TAtlasImpact);
      Error := '';
      try
        Impact := Session.Impact(FileName, Line, Character, ADepth);
      except
        on E: Exception do
          Error := E.Message;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Results,
        procedure
        begin
          Show(Request, Impact, Error);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers := FWorkers + [Worker];
  Worker.Start;
end;

class procedure TAtlasIdeImpact.Show(ARequest: Integer; const AImpact: TAtlasImpact; const AError: string);
begin
  // Eine neuere Anfrage läuft schon oder das Package wird entladen.
  if ARequest <> FRequest then
    Exit;
  if AError <> '' then
  begin
    TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [AError]), nil);
    TAtlasIdeResults.Say(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [AError]));
    Exit;
  end;
  if not AImpact.Found then
  begin
    TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Text(TAtlasTextId.ImpactNothing), nil);
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.ImpactNothing));
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowImpact(TAtlasStrings.Fmt(TAtlasTextId.ImpactTitle,
    [AImpact.Symbol.Name, AImpact.Depth, Length(AImpact.Places)]), AImpact);
end;

class procedure TAtlasIdeImpact.RunTests(const AImpact: TAtlasImpact);
begin
  if (Length(AImpact.Tests) = 0) or not Assigned(FRunTests) then
    Exit;
  // Der Server meldet nur Tests aus dem Testprogramm des Projekts: Eine Datei genügt, um es zu finden.
  FRunTests(AImpact.Tests[0].FileName, AImpact.RunNames);
end;

end.
