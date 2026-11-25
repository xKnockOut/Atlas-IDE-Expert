unit Atlas.IDE.Welcome.Adapters.Listener;

// Ereignisse anderer Module für die Willkommensseite (#1455): Ende einer
// Projektaufgabe (#900, Modul Build-Werkzeuge) und eines Testlaufs (#69,
// Modul Tests) an die Schnellaktionen (#764), zurückgesetzte Befehlsnutzung
// an „Atlas entdecken“ (#757); entsperrte Tipps meldet der eigene Abschnitt
// der Einstellungen direkt (Atlas.IDE.Welcome.Adapters.Settings). Das Modul stellt den
// Hörer über seinen Scope bereit. Wohin die Ereignisse gehen, gibt die Composition mit; sie fragt die laufende
// Seite bei jedem Aufruf neu und tut ohne sie nichts.

interface

uses
  System.SysUtils,
  Atlas.IDE.Contracts.BuildTools,
  Atlas.IDE.Contracts.Tests,
  Atlas.Core.Commands.Contract;

type
  /// <summary>Ziele der Ereignisse; ein nicht gesetzter Haken lässt das Ereignis fallen.</summary>
  TAtlasWelcomeListenerHooks = record
    /// <summary>Projektaufgabe von AProject fertig (Schnellaktionen).</summary>
    TaskFinished: TProc<string, TAtlasTaskResult>;
    /// <summary>Testlauf von ATestProject fertig: bestanden, fehlgeschlagen (Schnellaktionen).</summary>
    TestsFinished: TProc<string, Integer, Integer>;
    /// <summary>Befehlsnutzung zurückgesetzt („Atlas entdecken“).</summary>
    UsageReset: TProc;
  end;

  TAtlasWelcomeListener = class(TInterfacedObject, IAtlasTaskListener, IAtlasTestsListener,
    IAtlasCommandUsageListener)
  private
    FHooks: TAtlasWelcomeListenerHooks;
  public
    constructor Create(const AHooks: TAtlasWelcomeListenerHooks);
    procedure TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
    procedure TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
    procedure UsageReset;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard;

{ TAtlasWelcomeListener }

constructor TAtlasWelcomeListener.Create(const AHooks: TAtlasWelcomeListenerHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

procedure TAtlasWelcomeListener.TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
var
  mProject: string;
  mResult: TAtlasTaskResult;
  mHook: TProc<string, TAtlasTaskResult>;
begin
  mHook := FHooks.TaskFinished;
  mProject := AProject;
  mResult := AResult;
  if Assigned(mHook) then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mHook(mProject, mResult);
      end);
  end;
end;

procedure TAtlasWelcomeListener.TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
var
  mProject: string;
  mHook: TProc<string, Integer, Integer>;
begin
  // Ergebnis in der Zeile des Projekts; die Karte Tests (#763) liest die Projekt-Zusammenfassung.
  mHook := FHooks.TestsFinished;
  mProject := ATestProject;
  if Assigned(mHook) then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mHook(mProject, APassed, AFailed);
      end);
  end;
end;

procedure TAtlasWelcomeListener.UsageReset;
begin
  if Assigned(FHooks.UsageReset) then
  begin
    FHooks.UsageReset();
  end;
end;

end.
