unit Atlas.Core.Debug.KnownErrors;

// Bekannte Fehler beim Exception-Halt (#2460), Seite des Debuggers ohne VCL
// und Open Tools API:
//   - ReportOf: der Halt für den Vertrag IAtlasKnownErrors: Klasse, Meldung,
//     die Rahmen in eigenem Code (oberste zuerst, höchstens cMaxFrames) und
//     der Ort. Ohne eigene Rahmen zählt die Routine der Exception.
//   - ActionOf und KeyOf: Knopf der Leiste als Knopf des Vertrags; die Knöpfe
//     zum Treffer gelten dem besten (ersten).

interface

uses
  Atlas.Core.KnownErrors.Contract,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionBanner;

type
  TAtlasDebugKnownErrors = record
  public const
    /// <summary>Höchstens so viele eigene Rahmen gehen an den Tracker.</summary>
    cMaxFrames = 10;
  public
    /// <summary>Halt AException im Projekt AProject als Anfrage an den Tracker.</summary>
    class function ReportOf(const AException: TAtlasDebugException;
      const AProject: string): TAtlasDebugExceptionReport; static;
    /// <summary>Knopf des Vertrags zum Knopf AAction der Leiste; False bei anderen Knöpfen.</summary>
    class function ActionOf(AAction: TAtlasDebugBarAction; out AKnownAction: TAtlasKnownErrorAction): Boolean;
      static;
    /// <summary>Kennung des Treffers, dem AAction gilt; '' bei „Neues Issue …“ bzw. ohne Treffer.</summary>
    class function KeyOf(AAction: TAtlasDebugBarAction; const AKnown: TAtlasDebugBannerKnown): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack;

function FrameText(const ARoutine, AFileName: string; ALine: Integer): string;
var
  mPlace: string;
begin
  mPlace := ExtractFileName(AFileName);
  if (mPlace <> '') and (ALine > 0) then
  begin
    mPlace := mPlace + ':' + IntToStr(ALine);
  end;
  Result := ARoutine;
  if mPlace = '' then
  begin
    Exit;
  end;
  if Result = '' then
  begin
    Exit(mPlace);
  end;
  Result := Result + ' (' + mPlace + ')';
end;

{ TAtlasDebugKnownErrors }

class function TAtlasDebugKnownErrors.ReportOf(const AException: TAtlasDebugException;
  const AProject: string): TAtlasDebugExceptionReport;
var
  mFrame: TAtlasDebugFrame;
begin
  Result := Default(TAtlasDebugExceptionReport);
  Result.Project := AProject;
  Result.ExceptionClass := AException.ExceptionClass;
  Result.ExceptionMessage := AException.Message;
  for mFrame in AException.Frames do
  begin
    if Length(Result.OwnMethods) >= cMaxFrames then
    begin
      Break;
    end;
    if not mFrame.Own or (mFrame.Routine = '') then
    begin
      Continue;
    end;
    if Result.OwnMethods = nil then
    begin
      Result.FileName := mFrame.FileName;
      Result.Line := mFrame.Line;
    end;
    Result.OwnMethods := Result.OwnMethods + [mFrame.Routine];
    Result.OwnFrames := Result.OwnFrames + [FrameText(mFrame.Routine, mFrame.FileName, mFrame.Line)];
  end;
  // Ohne eigene Rahmen (Stapel fehlt, debug.ownCodeFolders leer): die Routine der Exception.
  if (Result.OwnMethods = nil) and (AException.Routine <> '') then
  begin
    Result.FileName := AException.FileName;
    Result.Line := AException.Line;
    Result.OwnMethods := [AException.Routine];
    Result.OwnFrames := [FrameText(AException.Routine, AException.FileName, AException.Line)];
  end;
end;

class function TAtlasDebugKnownErrors.ActionOf(AAction: TAtlasDebugBarAction;
  out AKnownAction: TAtlasKnownErrorAction): Boolean;
begin
  Result := True;
  AKnownAction := TAtlasKnownErrorAction.Open;
  case AAction of
    TAtlasDebugBarAction.KnownOpen:
      AKnownAction := TAtlasKnownErrorAction.Open;
    TAtlasDebugBarAction.KnownComment:
      AKnownAction := TAtlasKnownErrorAction.Comment;
    TAtlasDebugBarAction.KnownReopen:
      AKnownAction := TAtlasKnownErrorAction.Reopen;
    TAtlasDebugBarAction.KnownNew:
      AKnownAction := TAtlasKnownErrorAction.NewIssue;
  else
    Result := False;
  end;
end;

class function TAtlasDebugKnownErrors.KeyOf(AAction: TAtlasDebugBarAction;
  const AKnown: TAtlasDebugBannerKnown): string;
begin
  Result := '';
  if (AAction <> TAtlasDebugBarAction.KnownNew) and AKnown.HasErrors then
  begin
    Result := AKnown.Errors[0].Key;
  end;
end;

end.
