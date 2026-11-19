unit Atlas.IDE.Debug.KnownErrors;

// Bekannte Fehler beim Exception-Halt (#2460), Seite des Debuggers in der IDE:
//   - Bei jedem aufgenommenen Halt fragt Atlas den Vertrag IAtlasKnownErrors
//     (Tracker-Modul) mit Klasse, Meldung und eigenen Rahmen. Die Antwort
//     kommt aus dem Zwischenspeicher des Trackers oder später: Der Tracker
//     sucht im Hintergrund und meldet das Ende über IAtlasKnownErrorsView
//     (TAtlasIdeDebugKnownErrorsView, über den Scope des Debuggers
//     bereitgestellt); dann fragt Atlas für den gezeigten Halt erneut.
//   - Die Treffer gehen über TAtlasIdeDebugExceptionBar.Known in die
//     Exception-Leiste, ihre Knöpfe kommen über SetKnownHandler zurück und
//     gehen an IAtlasKnownErrors.Run.
//   - Ohne Tracker-Modul (kein Anbieter) bleibt die Leiste, wie sie ist.
// Läuft mit der Exception-Leiste. Nur im Hauptthread.

interface

uses
  Atlas.Core.KnownErrors.Contract,
  Atlas.IDE.Contracts.KnownErrors,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.IDE.Debug.Exceptions;

type
  TAtlasIdeDebugKnownErrors = class
  private class var
    FHandler: Integer;
    FStop: Integer;
    FReport: TAtlasDebugExceptionReport;
    FKnown: TAtlasDebugBannerKnown;
    class procedure ExceptionTaken(const AStop: TAtlasDebugExceptionStop); static;
    /// <summary>Tracker für den gemerkten Halt fragen und das Ergebnis an die Leiste geben.</summary>
    class procedure Ask; static;
    class procedure RunAction(AAction: TAtlasDebugBarAction); static;
  public
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Der Tracker hat eine Suche beendet: für den gezeigten Halt erneut fragen.</summary>
    class procedure Changed; static;
  end;

  /// <summary>Empfänger der Meldung des Trackers (IAtlasKnownErrorsView).</summary>
  TAtlasIdeDebugKnownErrorsView = class(TInterfacedObject, IAtlasKnownErrorsView)
  public
    procedure KnownErrorsChanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Debug.KnownErrors,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ExceptionBar;

/// <summary>Erster Anbieter von IAtlasKnownErrors (Tracker-Modul); nil ohne.</summary>
function KnownErrorsProvider: IAtlasKnownErrors;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasKnownErrors) do
  begin
    if Supports(mItem, IAtlasKnownErrors, Result) then
    begin
      Exit;
    end;
  end;
end;

{ TAtlasIdeDebugKnownErrors }

class procedure TAtlasIdeDebugKnownErrors.ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
begin
  if AStop.Continued then
  begin
    Exit;
  end;
  FStop := AStop.Stop;
  FReport := TAtlasDebugKnownErrors.ReportOf(AStop.Exception, TAtlasIdeDebugSession.LaunchProject);
  Ask;
end;

class procedure TAtlasIdeDebugKnownErrors.Ask;
var
  mProvider: IAtlasKnownErrors;
begin
  FKnown := Default(TAtlasDebugBannerKnown);
  mProvider := KnownErrorsProvider;
  if mProvider <> nil then
  begin
    FKnown := TAtlasDebugBannerKnown.FromResult(mProvider.Lookup(FReport));
  end;
  TAtlasIdeDebugExceptionBar.Known(FStop, FKnown);
end;

class procedure TAtlasIdeDebugKnownErrors.RunAction(AAction: TAtlasDebugBarAction);
var
  mAction: TAtlasKnownErrorAction;
  mProvider: IAtlasKnownErrors;
begin
  mProvider := KnownErrorsProvider;
  if (mProvider <> nil) and TAtlasDebugKnownErrors.ActionOf(AAction, mAction) then
  begin
    mProvider.Run(mAction, FReport, TAtlasDebugKnownErrors.KeyOf(AAction, FKnown));
  end;
end;

class procedure TAtlasIdeDebugKnownErrors.Start;
begin
  if FHandler <> 0 then
  begin
    Exit;
  end;
  FHandler := TAtlasIdeDebugExceptions.AddExceptionHandler(ExceptionTaken);
  TAtlasIdeDebugExceptionBar.SetKnownHandler(
    procedure(AAction: TAtlasDebugBarAction)
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          RunAction(AAction);
        end);
    end);
end;

class procedure TAtlasIdeDebugKnownErrors.Release;
begin
  if FHandler = 0 then
  begin
    Exit;
  end;
  TAtlasIdeDebugExceptions.RemoveExceptionHandler(FHandler);
  FHandler := 0;
  TAtlasIdeDebugExceptionBar.SetKnownHandler(nil);
  TAtlasIdeDebugExceptionBar.Known(FStop, Default(TAtlasDebugBannerKnown));
  FStop := 0;
  FReport := Default(TAtlasDebugExceptionReport);
  FKnown := Default(TAtlasDebugBannerKnown);
end;

class function TAtlasIdeDebugKnownErrors.Started: Boolean;
begin
  Result := FHandler <> 0;
end;

class procedure TAtlasIdeDebugKnownErrors.Changed;
begin
  if Started and (FStop <> 0) and TAtlasIdeDebugExceptionBar.Covers(FStop) then
  begin
    Ask;
  end;
end;

{ TAtlasIdeDebugKnownErrorsView }

procedure TAtlasIdeDebugKnownErrorsView.KnownErrorsChanged;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugKnownErrors.Changed);
end;

end.
