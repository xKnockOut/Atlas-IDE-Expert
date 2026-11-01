unit Atlas.IDE.Welcome.Listener;

// Ereignisse anderer Module für die Willkommensseite (#1455): Ende einer
// Projektaufgabe (#900, Modul Build-Werkzeuge) und eines Testlaufs (#69,
// Modul Tests) an die Schnellaktionen (#764), zurückgesetzte Befehlsnutzung
// an „Atlas entdecken“ (#757); entsperrte Tipps meldet der eigene Abschnitt
// der Einstellungen direkt (Atlas.IDE.Welcome.Settings). Das Modul stellt den
// Hörer über seinen Scope bereit; er fragt die laufende Seite bei jedem
// Aufruf neu und tut ohne sie nichts.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Usage,
  Atlas.IDE.Contracts.BuildTools,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Welcome.Commands;

type
  TAtlasWelcomeListener = class(TInterfacedObject, IAtlasTaskListener, IAtlasTestsListener,
    IAtlasCommandUsageListener)
  private
    FCurrent: TFunc<TAtlasIdeWelcome>;
  public
    /// <summary>ACurrent: die laufende Seite, nil ohne.</summary>
    constructor Create(const ACurrent: TFunc<TAtlasIdeWelcome>);
    procedure TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
    procedure TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
    procedure UsageReset;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.Discover;

constructor TAtlasWelcomeListener.Create(const ACurrent: TFunc<TAtlasIdeWelcome>);
begin
  inherited Create;
  FCurrent := ACurrent;
end;

procedure TAtlasWelcomeListener.TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
var
  mWelcome: TAtlasIdeWelcome;
  mProject: string;
  mResult: TAtlasTaskResult;
begin
  mWelcome := FCurrent();
  mProject := AProject;
  mResult := AResult;
  if (mWelcome <> nil) and (mWelcome.QuickActions <> nil) then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mWelcome.QuickActions.TaskFinished(mProject, mResult);
      end);
  end;
end;

procedure TAtlasWelcomeListener.TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
var
  mWelcome: TAtlasIdeWelcome;
  mProject: string;
begin
  // Ergebnis in der Zeile des Projekts; die Karte Tests (#763) liest die Projekt-Zusammenfassung.
  mWelcome := FCurrent();
  mProject := ATestProject;
  if (mWelcome <> nil) and (mWelcome.QuickActions <> nil) then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mWelcome.QuickActions.TestsFinished(mProject, APassed, AFailed);
      end);
  end;
end;

procedure TAtlasWelcomeListener.UsageReset;
var
  mWelcome: TAtlasIdeWelcome;
begin
  mWelcome := FCurrent();
  if (mWelcome <> nil) and (mWelcome.Discover <> nil) then
  begin
    mWelcome.Discover.Refresh;
  end;
end;

end.
