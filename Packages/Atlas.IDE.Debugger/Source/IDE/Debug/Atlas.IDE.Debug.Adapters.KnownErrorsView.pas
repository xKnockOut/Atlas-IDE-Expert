unit Atlas.IDE.Debug.Adapters.KnownErrorsView;

// Empfänger der Meldung des Trackers für bekannte Fehler beim Exception-Halt
// (#2460, IAtlasKnownErrorsView aus Atlas.IDE.Base.Foundation.KnownErrors): Hat der
// Tracker eine Suche beendet, fragt TAtlasIdeDebugKnownErrors für den
// gezeigten Halt erneut. Die Komposition stellt ihn über den Scope des
// Debuggers bereit. Nur im Hauptthread.

interface

uses
  Atlas.IDE.Base.Foundation.KnownErrors;

type
  /// <summary>Empfänger der Meldung des Trackers (IAtlasKnownErrorsView).</summary>
  TAtlasIdeDebugKnownErrorsView = class(TInterfacedObject, IAtlasKnownErrorsView)
  public
    procedure KnownErrorsChanged;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Debug.KnownErrors;

{ TAtlasIdeDebugKnownErrorsView }

procedure TAtlasIdeDebugKnownErrorsView.KnownErrorsChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugKnownErrors.Changed);
end;

end.
