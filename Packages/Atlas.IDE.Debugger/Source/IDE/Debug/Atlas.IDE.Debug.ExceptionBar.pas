unit Atlas.IDE.Debug.ExceptionBar;

// Exception-Leiste beim Debuggen (#783) in der IDE. Baut auf dem
// Exception-Verlauf auf (#517: Klasse und Meldung aus dem Dialog der IDE,
// Aufrufstapel, Ignorier-Liste) und meldet sich dort als Empfänger jedes
// aufgenommenen Halts an.
//   - Ersetzen: In Delphi 12 und 13 (TAtlasDebugBannerRules.KnownIdeVersion)
//     schließt Atlas den erkannten Exception-Dialog über seinen Knopf
//     „Anhalten“; der Prozess bleibt stehen, und statt des Dialogs steht die
//     Leiste oben im Editor. Einen Code-Hook in die IDE (wie GExperts) setzt
//     Atlas nicht: Der Dialog erscheint kurz (bis zu
//     TAtlasIdeExceptionDialog.cIntervalMs), dann schließt Atlas ihn.
//   - Rückfall: unbekannte IDE-Version, Dialog nicht erkannt oder ohne beide
//     Knöpfe, Befehl Atlas.DebugExceptionIdeDialog für die laufende Sitzung:
//     Der Dialog bleibt unverändert; schließt der Benutzer ihn mit
//     „Anhalten“, kommt die Leiste dazu. Bei unbekannter Version steht ein
//     gelber Hinweis im Atlas-Statusfeld.
//   - Leiste: erst wenn kein modales Fenster mehr offen ist und der Prozess
//     noch am selben Halt steht. Atlas springt zur gezeigten Zeile (erste
//     eigene, #578) und markiert sie; die Leiste kommt in das oberste
//     Editorfenster über Brotkrumen und Editorleiste.
//   - Knöpfe: Anhalten (Leiste zu, Prozess bleibt stehen), Fortsetzen,
//     Klasse ignorieren bzw. Nur an dieser Stelle ignorieren (merken, dann
//     fortsetzen), Meldung kopieren. Solange die Leiste im aktiven Fenster
//     steht, gehören F9 (Fortsetzen), F8 und Esc (Anhalten) ihr
//     (TAtlasKeyHook); sonst berührt Atlas keine Taste.
//   - Fortsetzen von anderer Stelle, neuer Halt, Ende der Sitzung schließen
//     die Leiste.
//   - Erklärung (#865): Atlas.IDE.Debug.AccessViolation reicht über Explain
//     die Erklärung einer Zugriffsverletzung je Halt herein; sie erscheint
//     unter der Meldung, sobald die Leiste für diesen Halt steht. Die Knöpfe
//     der Erklärung meldet die Leiste an SetExplanationHandler.
// Ohne debug.exceptionBanner ist nichts angemeldet, der Dialog der IDE bleibt
// unverändert. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Exceptions,
  Atlas.UI.Debug.ExceptionBar;

type
  TAtlasIdeDebugExceptionBar = class
  public const
    cStatusId = 'atlas.debug.exceptionBanner';
    cStatusOrder = 85;
    /// <summary>So lange wartet Atlas höchstens, bis der Dialog zu ist.</summary>
    cShowWaitMs = 120000;
    cIntervalMs = 100;
    cKeyPriority = 30;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TKeys = class(TAtlasKeyClient)
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    end;
    /// <summary>Zeitgeber und Freigabe-Meldung der Leiste (das Editorfenster kann vorher gehen).</summary>
    TWatcher = class(TComponent)
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FHandler: Integer;
    FKeys: TKeys;
    FWatcher: TWatcher;
    FTimer: TTimer;
    FBar: TAtlasDebugExceptionBar;
    FMessage: TProc<string>;
    FRegistry: IAtlasStatusRegistry;
    FStatusRef: IAtlasStatusItem;
    /// <summary>Befehl Atlas.DebugExceptionIdeDialog: in dieser Sitzung den Dialog der IDE lassen.</summary>
    FIdeDialog: Boolean;
    FPending: TAtlasDebugExceptionStop;
    FHasPending: Boolean;
    FPendingSince: UInt64;
    FQuiet: Integer;
    FShown: TAtlasDebugException;
    FShownInfo: TAtlasDebugBannerInfo;
    FShownStop: Integer;
    FExplanation: TAtlasDebugBannerExplanation;
    FExplanationStop: Integer;
    FExplanationHandler: TProc<TAtlasDebugBarAction>;
    class procedure ExceptionTaken(const AStop: TAtlasDebugExceptionStop); static;
    class procedure CheckShow; static;
    class procedure ShowBar; static;
    /// <summary>Leiste in AHost anlegen bzw. aus einem anderen Editorfenster herüberholen.</summary>
    class procedure EnsureBar(AHost: TWinControl); static;
    class procedure RunAction(AAction: TAtlasDebugBarAction); static;
    class procedure ResumeProcess; static;
    class function HostOfTopEditor: TWinControl; static;
    class procedure UpdateStatus; static;
  public
    class procedure Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Leiste schließen; der Prozess bleibt, wie er ist.</summary>
    class procedure Hide; static;
    /// <summary>Befehl Atlas.DebugExceptionIdeDialog: bis zum Ende der Sitzung den Dialog der IDE zeigen bzw.
    /// wieder ersetzen.</summary>
    class procedure ToggleIdeDialog; static;
    /// <summary>Kennt Atlas die IDE-Version, für die es übersetzt ist?</summary>
    class function KnownVersion: Boolean; static;
    class function Visible: Boolean; static;
    /// <summary>Erklärung für den Halt AStop (#865); erscheint, sobald die Leiste für ihn steht.</summary>
    class procedure Explain(AStop: Integer; const AExplanation: TAtlasDebugBannerExplanation); static;
    /// <summary>Steht die Leiste für AStop oder kommt sie gleich (Dialog noch offen)?</summary>
    class function Covers(AStop: Integer): Boolean; static;
    /// <summary>Empfänger der Knöpfe der Erklärung (Wo zugewiesen, Auswerten, Erklärung kopieren); nil = keiner.
    /// </summary>
    class procedure SetExplanationHandler(const AHandler: TProc<TAtlasDebugBarAction>); static;
  end;

implementation

uses
  Atlas.Core.Status.Registry,
  Atlas.Core.Debug.ExceptionDialog,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeDebugExceptionBar.TListener }

procedure TAtlasIdeDebugExceptionBar.TListener.DebugStarted;
begin
  // Neue Sitzung: wieder ersetzen (der Befehl gilt nur für eine Sitzung).
  FIdeDialog := False;
  FHasPending := False;
  Hide;
end;

procedure TAtlasIdeDebugExceptionBar.TListener.DebugResumed;
begin
  FHasPending := False;
  Hide;
end;

procedure TAtlasIdeDebugExceptionBar.TListener.DebugEnded;
begin
  FHasPending := False;
  Hide;
end;

{ TAtlasIdeDebugExceptionBar.TKeys }

function TAtlasIdeDebugExceptionBar.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (FBar <> nil) and FBar.Visible and (AShift = []) and
    ((AKey = VK_ESCAPE) or (AKey = VK_F8) or (AKey = VK_F9)) and
    (Screen.ActiveCustomForm <> nil) and (Screen.ActiveCustomForm = GetParentForm(FBar));
end;

procedure TAtlasIdeDebugExceptionBar.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  if FBar = nil then
  begin
    Exit;
  end;
  if AKey = VK_F9 then
  begin
    FBar.Trigger(TAtlasDebugBarAction.Continue);
  end
  else
  begin
    FBar.Trigger(TAtlasDebugBarAction.BreakHere);
  end;
end;

{ TAtlasIdeDebugExceptionBar.TWatcher }

procedure TAtlasIdeDebugExceptionBar.TWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FBar) then
  begin
    FBar := nil;
    if (FKeys <> nil) and TAtlasKeyHook.Contains(FKeys) then
    begin
      TAtlasKeyHook.Remove(FKeys);
    end;
  end;
end;

procedure TAtlasIdeDebugExceptionBar.TWatcher.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugExceptionBar.CheckShow);
end;

{ TAtlasIdeDebugExceptionBar }

class function TAtlasIdeDebugExceptionBar.KnownVersion: Boolean;
begin
  Result := TAtlasDebugBannerRules.KnownIdeVersion(CompilerVersion);
end;

class procedure TAtlasIdeDebugExceptionBar.Start(const AMessage: TProc<string>;
  const ARegistry: IAtlasStatusRegistry);
begin
  FMessage := AMessage;
  FRegistry := ARegistry;
  if FWatcher = nil then
  begin
    FWatcher := TWatcher.Create(nil);
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cIntervalMs;
    FTimer.OnTimer := FWatcher.Tick;
  end;
  if FKeys = nil then
  begin
    FKeys := TKeys.Create(cKeyPriority);
  end;
  if FHandler = 0 then
  begin
    FHandler := TAtlasIdeDebugExceptions.AddExceptionHandler(ExceptionTaken);
  end;
  // Ersetzt die Leiste den Dialog, darf er gar nicht erst sichtbar werden (kein Aufblitzen).
  TAtlasIdeDebugExceptions.SetDialogMayHide(
    function(const AScan: TAtlasDebugDialogScan): Boolean
    begin
      Result := TAtlasIdeSettings.Current.DebugExceptionBanner and
        (TAtlasDebugBannerRules.Mode(True, KnownVersion, FIdeDialog, AScan) = TAtlasDebugBannerMode.Replace);
    end);
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
  if not KnownVersion then
  begin
    TAtlasGuard.Log(Format('Exception-Leiste: IDE-Version %.1f nicht geprüft; der Dialog der IDE bleibt',
      [CompilerVersion], TFormatSettings.Invariant));
  end;
  UpdateStatus;
end;

class procedure TAtlasIdeDebugExceptionBar.Release;
begin
  Hide;
  FreeAndNil(FBar);
  FHasPending := False;
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  if FHandler <> 0 then
  begin
    TAtlasIdeDebugExceptions.RemoveExceptionHandler(FHandler);
  end;
  FHandler := 0;
  TAtlasIdeDebugExceptions.SetDialogMayHide(nil);
  if (FRegistry <> nil) and (FStatusRef <> nil) then
  begin
    FRegistry.Remove(cStatusId);
  end;
  FStatusRef := nil;
  FRegistry := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FKeys);
  FreeAndNil(FWatcher);
  FShown := Default(TAtlasDebugException);
  FShownInfo := Default(TAtlasDebugBannerInfo);
  FPending := Default(TAtlasDebugExceptionStop);
  FExplanation := Default(TAtlasDebugBannerExplanation);
  FExplanationStop := 0;
  FShownStop := 0;
  FMessage := nil;
end;

class function TAtlasIdeDebugExceptionBar.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeDebugExceptionBar.Visible: Boolean;
begin
  Result := (FBar <> nil) and FBar.Visible;
end;

class procedure TAtlasIdeDebugExceptionBar.Explain(AStop: Integer; const AExplanation: TAtlasDebugBannerExplanation);
begin
  FExplanation := AExplanation;
  FExplanationStop := AStop;
  if (FBar <> nil) and FBar.Visible and (FShownStop = AStop) then
  begin
    FBar.SetExplanation(AExplanation);
  end;
end;

class function TAtlasIdeDebugExceptionBar.Covers(AStop: Integer): Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.DebugExceptionBanner and
    ((Visible and (FShownStop = AStop)) or (FHasPending and (FPending.Stop = AStop)));
end;

class procedure TAtlasIdeDebugExceptionBar.SetExplanationHandler(const AHandler: TProc<TAtlasDebugBarAction>);
begin
  FExplanationHandler := AHandler;
end;

class procedure TAtlasIdeDebugExceptionBar.ApplySettings;
begin
  if not TAtlasIdeSettings.Current.DebugExceptionBanner then
  begin
    Hide;
  end
  else if FBar <> nil then
  begin
    // debug.exceptionBanner.ignoreAtLocation: Knopf an oder aus.
    FShownInfo.CanIgnoreLocation := TAtlasIdeSettings.Current.DebugExceptionBannerIgnoreAtLocation and
      (TAtlasIdeDebugSession.LaunchProject <> '') and FShownInfo.HasLocation;
    FBar.SetInfo(FShownInfo);
  end;
  UpdateStatus;
end;

class procedure TAtlasIdeDebugExceptionBar.ThemeChanged;
begin
  if FBar <> nil then
  begin
    FBar.SetColors(TAtlasIdeStyle.Colors);
  end;
end;

class procedure TAtlasIdeDebugExceptionBar.UpdateStatus;
var
  mLine: TAtlasStatusLine;
begin
  if FRegistry = nil then
  begin
    Exit;
  end;
  if KnownVersion or not TAtlasIdeSettings.Current.DebugExceptionBanner then
  begin
    if FStatusRef <> nil then
    begin
      FRegistry.Remove(cStatusId);
    end;
    FStatusRef := nil;
    Exit;
  end;
  if FStatusRef <> nil then
  begin
    Exit;
  end;
  mLine := TAtlasStatusLine.Create(FRegistry, cStatusId, cStatusOrder);
  FStatusRef := mLine;
  // Gelb: Die Einstellung ist an, wirkt aber nur als Rückfall.
  mLine.Update(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerUnknownVersion), TAtlasStatusState.Yellow,
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerUnknownVersionSummary));
  FRegistry.Add(FStatusRef);
end;

class procedure TAtlasIdeDebugExceptionBar.ToggleIdeDialog;
begin
  FIdeDialog := not FIdeDialog;
  if Assigned(FMessage) then
  begin
    if FIdeDialog then
    begin
      FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerIdeDialogOn));
    end
    else
    begin
      FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerIdeDialogOff));
    end;
  end;
end;

class procedure TAtlasIdeDebugExceptionBar.ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
var
  mMode: TAtlasDebugBannerMode;
begin
  Hide;
  FHasPending := False;
  if AStop.Continued or not TAtlasIdeSettings.Current.DebugExceptionBanner then
  begin
    Exit;
  end;
  mMode := TAtlasDebugBannerRules.Mode(True, KnownVersion, FIdeDialog, AStop.Dialog);
  if mMode = TAtlasDebugBannerMode.Off then
  begin
    Exit;
  end;
  // Ersetzen: Dialog mit „Anhalten“ schließen; geht das nicht mehr (schon zu), wie im Rückfall.
  if (mMode = TAtlasDebugBannerMode.Replace) and not TAtlasIdeDebugExceptions.BreakDialog then
  begin
    TAtlasGuard.Log('Exception-Leiste: Dialog der IDE ließ sich nicht schließen; Leiste danach');
  end;
  FPending := AStop;
  FHasPending := True;
  FPendingSince := TThread.GetTickCount64;
  FQuiet := 0;
  FTimer.Enabled := True;
end;

class procedure TAtlasIdeDebugExceptionBar.CheckShow;
begin
  // Weitergelaufen, neuer Halt, Sitzung zu oder zu lange gewartet: keine Leiste.
  if not FHasPending or (TAtlasIdeDebugSession.StopCount <> FPending.Stop) or
    (TAtlasIdeDebugSession.StoppedThread = nil) or (TThread.GetTickCount64 - FPendingSince > cShowWaitMs) then
  begin
    FTimer.Enabled := False;
    FHasPending := False;
    Exit;
  end;
  // Erst wenn kein Dialog mehr offen ist und die IDE ihren Ort gezeigt hat (zwei ruhige Takte).
  if Application.ModalLevel > 0 then
  begin
    FQuiet := 0;
    Exit;
  end;
  Inc(FQuiet);
  if FQuiet < 2 then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  FHasPending := False;
  ShowBar;
end;

class function TAtlasIdeDebugExceptionBar.HostOfTopEditor: TWinControl;
var
  mEditor: TWinControl;
begin
  Result := nil;
  mEditor := TAtlasEditorBarHost.TopEditor;
  if (mEditor <> nil) and (mEditor.Parent <> nil) then
  begin
    Result := mEditor.Parent;
  end;
end;

class procedure TAtlasIdeDebugExceptionBar.EnsureBar(AHost: TWinControl);
begin
  if (FBar <> nil) and (FBar.Parent <> AHost) then
  begin
    FreeAndNil(FBar);
  end;
  if FBar <> nil then
  begin
    Exit;
  end;
  FBar := TAtlasDebugExceptionBar.Create(nil);
  FBar.FreeNotification(FWatcher);
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          RunAction(AAction);
        end);
    end;
  // Ganz oben, über Brotkrumen und Editorleiste (alTop ordnet nach Top).
  FBar.Align := alNone;
  FBar.Top := 0;
  FBar.Align := alTop;
  FBar.Parent := AHost;
end;

class procedure TAtlasIdeDebugExceptionBar.ShowBar;
var
  mFound: TAtlasDebugException;
  mHost: TWinControl;
begin
  FShown := FPending.Exception;
  // Zähler aus dem Verlauf (gleiche Klasse an gleicher Stelle in dieser Sitzung).
  if (TAtlasIdeDebugExceptions.History <> nil) and
    TAtlasIdeDebugExceptions.History.TryFind(FShown.Key, mFound) then
  begin
    FShown.Count := mFound.Count;
  end;
  FShownInfo := TAtlasDebugBannerRules.Info(FShown, TAtlasIdeSettings.Current.DebugJustMyCode,
    TAtlasIdeDebugSession.LaunchProject, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsThread),
    TAtlasIdeSettings.Current.DebugExceptionBannerIgnoreAtLocation);
  // Zur gezeigten Zeile und markieren; öffnet die Unit im obersten Editorfenster.
  if FShownInfo.HasLocation then
  begin
    TAtlasIdeNavigation.MarkLine(FShownInfo.FileName, FShownInfo.Line - 1);
  end;
  mHost := HostOfTopEditor;
  if mHost = nil then
  begin
    TAtlasGuard.Log('Exception-Leiste: kein Editorfenster; nur der Verlauf zeigt die Exception');
    Exit;
  end;
  EnsureBar(mHost);
  FBar.SetColors(TAtlasIdeStyle.Colors);
  FBar.SetInfo(FShownInfo);
  FShownStop := FPending.Stop;
  // Erklärung einer Zugriffsverletzung nur für diesen Halt (#865).
  if FExplanationStop = FShownStop then
  begin
    FBar.SetExplanation(FExplanation);
  end
  else
  begin
    FBar.SetExplanation(Default(TAtlasDebugBannerExplanation));
  end;
  FBar.Top := 0;
  FBar.Visible := True;
  if not TAtlasKeyHook.Contains(FKeys) then
  begin
    TAtlasKeyHook.Add(FKeys);
  end;
end;

class procedure TAtlasIdeDebugExceptionBar.Hide;
begin
  if (FKeys <> nil) and TAtlasKeyHook.Contains(FKeys) then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  if FBar <> nil then
  begin
    FBar.Visible := False;
  end;
end;

class procedure TAtlasIdeDebugExceptionBar.ResumeProcess;
begin
  Hide;
  if not TAtlasIdeDebugSession.Resume then
  begin
    TAtlasGuard.Log('Exception-Leiste: Fortsetzen ging nicht, der Prozess steht nicht mehr');
  end;
end;

class procedure TAtlasIdeDebugExceptionBar.RunAction(AAction: TAtlasDebugBarAction);
begin
  case AAction of
    TAtlasDebugBarAction.BreakHere:
      Hide;
    TAtlasDebugBarAction.Continue:
      ResumeProcess;
    TAtlasDebugBarAction.IgnoreClass:
      begin
        TAtlasIdeDebugExceptions.IgnoreClass(FShownInfo.ExceptionClass);
        ResumeProcess;
      end;
    TAtlasDebugBarAction.IgnoreLocation:
      begin
        TAtlasIdeDebugExceptions.IgnoreLocation(TAtlasIdeDebugSession.LaunchProject, FShownInfo.ExceptionClass,
          FShownInfo.FileName, FShownInfo.Line);
        ResumeProcess;
      end;
    TAtlasDebugBarAction.Copy:
      Clipboard.AsText := FShown.CopyText;
    TAtlasDebugBarAction.Open:
      if FShownInfo.HasLocation then
      begin
        TAtlasIdeNavigation.MarkLine(FShownInfo.FileName, FShownInfo.Line - 1);
      end;
    TAtlasDebugBarAction.WhereAssigned, TAtlasDebugBarAction.Evaluate, TAtlasDebugBarAction.CopyExplanation:
      if Assigned(FExplanationHandler) then
      begin
        FExplanationHandler(AAction);
      end;
    TAtlasDebugBarAction.None: ;
  end;
end;

end.
