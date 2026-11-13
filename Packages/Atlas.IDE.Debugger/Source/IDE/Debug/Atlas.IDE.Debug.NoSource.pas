unit Atlas.IDE.Debug.NoSource;

// Fenster „Kein Quelltext“ (#869) in der IDE: Hält der Debugger und hat der
// oberste Rahmen keinen Quelltext (die IDE zeigt das CPU-Fenster), zeigt
// Atlas oben rechts im aktiven Fenster der IDE ein kleines Fenster ohne
// Fokus mit Routine, Modul, Adresse, Grund und Auswegen
// (TAtlasNoSourcePopup). Das CPU-Fenster bleibt unverändert.
// - Ist „Nur eigener Code“ (#578) an, gilt nur ein Halt durch Exception;
//   Schritte in Code ohne Quelltext übernimmt dort #578.
// - Debug-DCUs einschalten und neu bauen: DCC_DebugDCUs in „Debug“ (mit
//   Rückfrage, TAtlasIdeDebugUnavailableFixes), Sitzung beenden, nach ihrem
//   Ende bauen und starten.
// - Zurück zum eigenen Code: „Bis zur Rückkehr“, bis der oberste Rahmen
//   eigener Code ist (höchstens cMaxReturns-mal).
// - Quelltext suchen …: Ordner wählen; liegt die Unit darin, merkt Atlas ihn
//   für das Projekt und öffnet die Datei.
// - Für diese Unit nicht mehr zeigen: debug.noSourcePage.ignoredUnits.
// Weiterlaufen und Ende der Sitzung schließen das Fenster.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.NoSource,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.NoSourcePopup;

type
  TAtlasIdeDebugNoSource = class
  public const
    cIntervalMs = 150;
    cStackRetries = 10;
    cMaxReturns = 20;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FPopup: TAtlasNoSourcePopup;
    FMessage: TProc<string>;
    FStop: Integer;
    FRetries: Integer;
    FReturning: Boolean;
    FReturns: Integer;
    FRebuild: Boolean;
    FFacts: TAtlasNoSourceFacts;
    class procedure Say(const AText: string); static;
    class procedure Schedule; static;
    class procedure Check; static;
    class procedure Judge(const AFrames: TAtlasDebugFrames); static;
    /// <summary>Ein Schritt von „Zurück zum eigenen Code“ ist angekommen: fertig oder weiter.</summary>
    class procedure Returned(const AFrames: TAtlasDebugFrames); static;
    class procedure Show(const AFacts: TAtlasNoSourceFacts; AHasOwnFrame: Boolean); static;
    class procedure Hide; static;
    class procedure Choose(AWay: TAtlasNoSourceWay); static;
    class procedure ReturnToOwnCode; static;
    class procedure EnableDebugDcus; static;
    class procedure FindSource; static;
    class procedure Ignore; static;
    class procedure RebuildAndRun; static;
  public
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  System.Types,
  System.IOUtils,
  Vcl.Forms,
  Vcl.FileCtrl,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Debug.Unavailable,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.NoSourceFacts,
  Atlas.IDE.Debug.UnavailableFixes,
  Atlas.UI.Debug.Strings;

const
  cDebugConfiguration = 'Debug';
  /// <summary>Abstand des Fensters vom rechten bzw. oberen Rand des aktiven Fensters (in cPad).</summary>
  cCornerRight = 3;
  cCornerTop = 8;

{ TAtlasIdeDebugNoSource.TTicker }

procedure TAtlasIdeDebugNoSource.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugNoSource.Check);
end;

{ TAtlasIdeDebugNoSource.TListener }

procedure TAtlasIdeDebugNoSource.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if not TAtlasIdeSettings.Current.DebugNoSourcePage then
  begin
    Exit;
  end;
  // Mit „Nur eigener Code“ übernimmt #578 die Schritte; dann nur Exceptions.
  if not FReturning and (AStop = TAtlasDebugStop.Paused) and TAtlasIdeSettings.Current.DebugJustMyCode then
  begin
    Exit;
  end;
  TAtlasIdeDebugNoSource.Schedule;
end;

procedure TAtlasIdeDebugNoSource.TListener.DebugResumed;
begin
  TAtlasIdeDebugNoSource.Hide;
end;

procedure TAtlasIdeDebugNoSource.TListener.DebugEnded;
begin
  FReturning := False;
  TAtlasIdeDebugNoSource.Hide;
  if FRebuild then
  begin
    FRebuild := False;
    TAtlasIdeDebugNoSource.RebuildAndRun;
  end;
end;

{ TAtlasIdeDebugNoSource }

class procedure TAtlasIdeDebugNoSource.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cIntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugNoSource.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(FPopup);
  TAtlasIdeNoSourceFacts.Release;
  FMessage := nil;
  FReturning := False;
  FRebuild := False;
end;

class function TAtlasIdeDebugNoSource.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugNoSource.ThemeChanged;
begin
  if (FPopup <> nil) and FPopup.IsShown then
  begin
    FPopup.Colors := TAtlasIdeStyle.Colors;
    FPopup.Invalidate;
  end;
end;

class procedure TAtlasIdeDebugNoSource.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class procedure TAtlasIdeDebugNoSource.Schedule;
begin
  FStop := TAtlasIdeDebugSession.StopCount;
  FRetries := 0;
  FTimer.Enabled := True;
end;

class procedure TAtlasIdeDebugNoSource.Check;
var
  mThread: IOTAThread;
  mFrames: TAtlasDebugFrames;
begin
  FTimer.Enabled := False;
  // Weitergelaufen oder neuer Halt: dieser Halt gilt nicht mehr.
  if FStop <> TAtlasIdeDebugSession.StopCount then
  begin
    Exit;
  end;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if mThread = nil then
  begin
    FReturning := False;
    Exit;
  end;
  case TAtlasIdeDebugSession.ReadStack(mThread, TAtlasDebugCallStack.cMaxFrames, mFrames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FRetries);
        FTimer.Enabled := FRetries <= cStackRetries;
      end;
    TAtlasDebugStackRead.Ready:
      begin
        TAtlasIdeDebugSources.MarkFrames(mFrames);
        Judge(mFrames);
      end;
  else
    FReturning := False;
  end;
end;

/// <summary>Steht weiter unten im Stapel eigener Code?</summary>
function HasOwnFrame(const AFrames: TAtlasDebugFrames): Boolean;
var
  mFrame: TAtlasDebugFrame;
begin
  for mFrame in AFrames do
  begin
    if mFrame.Own then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TAtlasIdeDebugNoSource.Judge(const AFrames: TAtlasDebugFrames);
var
  mFacts: TAtlasNoSourceFacts;
begin
  if (Length(AFrames) = 0) or FReturning then
  begin
    Returned(AFrames);
    Exit;
  end;
  if AFrames[0].HasSource then
  begin
    Hide;
    Exit;
  end;
  mFacts := TAtlasIdeNoSourceFacts.Collect(AFrames[0].Header);
  if TAtlasNoSource.IsIgnored(mFacts.UnitName, TAtlasIdeSettings.Current.DebugNoSourceIgnoredUnits) or
    TAtlasNoSource.IsIgnored(mFacts.Place.Module, TAtlasIdeSettings.Current.DebugNoSourceIgnoredUnits) then
  begin
    Exit;
  end;
  Show(mFacts, HasOwnFrame(AFrames));
end;

class procedure TAtlasIdeDebugNoSource.Returned(const AFrames: TAtlasDebugFrames);
begin
  // „Zurück zum eigenen Code“: weiter, bis der oberste Rahmen eigener Code ist.
  if (Length(AFrames) = 0) or AFrames[0].Own or (FReturns >= cMaxReturns) or not HasOwnFrame(AFrames) then
  begin
    FReturning := False;
    Exit;
  end;
  Inc(FReturns);
  if not TAtlasIdeDebugSession.RunMode(ormRunUntilReturn) then
  begin
    FReturning := False;
  end;
end;

/// <summary>Rechte obere Ecke im aktiven Fenster der IDE (Bildschirm).</summary>
function Corner: TPoint;
var
  mForm: TCustomForm;
  mRect: TRect;
begin
  mForm := Screen.ActiveCustomForm;
  if mForm = nil then
  begin
    mForm := Application.MainForm;
  end;
  if mForm = nil then
  begin
    Exit(Mouse.CursorPos);
  end;
  mRect := mForm.BoundsRect;
  Result := TPoint.Create(mRect.Right - mForm.ScaleValue(TAtlasNoSourcePopup.cPad * cCornerRight),
    mRect.Top + mForm.ScaleValue(TAtlasNoSourcePopup.cPad * cCornerTop));
end;

/// <summary>„Modul … · Adresse … · Unit …“; Unbekanntes als „unbekannt“.</summary>
function PlaceText(const AFacts: TAtlasNoSourceFacts): string;
var
  mModule, mAddress: string;
begin
  mModule := AFacts.Place.Module;
  if mModule = '' then
  begin
    mModule := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceUnknown);
  end;
  mAddress := AFacts.Place.Address;
  if mAddress = '' then
  begin
    mAddress := TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceUnknown);
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourcePlace, [mModule, mAddress]);
  if AFacts.UnitName <> '' then
  begin
    Result := Result + ' · ' + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceUnit, [AFacts.UnitName]);
  end;
end;

class procedure TAtlasIdeDebugNoSource.Show(const AFacts: TAtlasNoSourceFacts; AHasOwnFrame: Boolean);
var
  mReason: TAtlasNoSourceReason;
  mPoint: TPoint;
begin
  FFacts := AFacts;
  mReason := TAtlasNoSource.Decide(AFacts);
  if FPopup = nil then
  begin
    FPopup := TAtlasNoSourcePopup.Create(nil);
    FPopup.OnWay :=
      procedure(AWay: TAtlasNoSourceWay)
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            TAtlasIdeDebugNoSource.Choose(AWay);
          end);
      end;
    FPopup.OnIgnore :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugNoSource.Ignore);
      end;
  end;
  mPoint := Corner;
  FPopup.Colors := TAtlasIdeStyle.Colors;
  FPopup.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FPopup.ShowFor(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceTitle, [AFacts.Place.Routine]), PlaceText(AFacts),
    TAtlasNoSourcePopup.ReasonText(mReason), TAtlasNoSource.Ways(mReason, AHasOwnFrame,
    SameText(TAtlasIdeDebugSession.LaunchConfiguration, cDebugConfiguration)),
    (AFacts.UnitName <> '') or (AFacts.Place.Module <> ''), mPoint);
end;

class procedure TAtlasIdeDebugNoSource.Hide;
begin
  if FPopup <> nil then
  begin
    FPopup.Dismiss;
  end;
end;

class procedure TAtlasIdeDebugNoSource.Choose(AWay: TAtlasNoSourceWay);
begin
  case AWay of
    TAtlasNoSourceWay.EnableDebugDcus:
      EnableDebugDcus;
    TAtlasNoSourceWay.ReturnToOwnCode:
      ReturnToOwnCode;
    TAtlasNoSourceWay.FindSource:
      FindSource;
    TAtlasNoSourceWay.KeepCpu:
      ;
  end;
end;

class procedure TAtlasIdeDebugNoSource.ReturnToOwnCode;
begin
  FReturning := True;
  FReturns := 1;
  Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.NoSourceReturning));
  if not TAtlasIdeDebugSession.RunMode(ormRunUntilReturn) then
  begin
    FReturning := False;
  end;
end;

class procedure TAtlasIdeDebugNoSource.EnableDebugDcus;
var
  mProject: IOTAProject;
begin
  TAtlasIdeDebugUnavailableFixes.UseDebugDcus(cDebugConfiguration, FMessage);
  mProject := GetActiveProject;
  // Abgelehnt oder nicht gesetzt: Sitzung läuft weiter.
  if (mProject = nil) or not TAtlasDebugUnavailable.OptionOn(TAtlasIdeProjectContext.ConfigurationValue(mProject,
    cDebugConfiguration, '', TAtlasIdeDebugUnavailableFixes.cDebugDcusOption), False) then
  begin
    Exit;
  end;
  FRebuild := TAtlasIdeDebugUnavailableFixes.Reset(FMessage);
end;

class procedure TAtlasIdeDebugNoSource.RebuildAndRun;
var
  mProject: IOTAProject;
begin
  mProject := GetActiveProject;
  if (mProject = nil) or (mProject.ProjectBuilder = nil) then
  begin
    Exit;
  end;
  if mProject.ProjectBuilder.BuildProject(cmOTABuild, True, True) then
  begin
    TAtlasIdeDebugUnavailableFixes.Run(FMessage);
  end;
end;

class procedure TAtlasIdeDebugNoSource.FindSource;
var
  mFolder, mName, mFile: string;
begin
  mName := FFacts.UnitName + '.pas';
  if FFacts.UnitName = '' then
  begin
    mName := FFacts.Place.Routine;
  end;
  mFolder := ExtractFileDir(FFacts.PasPath);
  if not SelectDirectory(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceFindTitle, [mName]), '', mFolder) then
  begin
    Exit;
  end;
  mFile := TPath.Combine(mFolder, mName);
  if (FFacts.UnitName = '') or not FileExists(mFile) then
  begin
    Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceNotFound, [mName, mFolder]));
    Exit;
  end;
  TAtlasIdeNoSourceFacts.RememberFolder(mFolder);
  Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceFound, [mFolder]));
  TAtlasIdeNavigation.ShowFile(mFile);
end;

class procedure TAtlasIdeDebugNoSource.Ignore;
var
  mNext: TAtlasPluginSettings;
  mUnit: string;
begin
  mUnit := FFacts.UnitName;
  if mUnit = '' then
  begin
    mUnit := FFacts.Place.Module;
  end;
  if mUnit = '' then
  begin
    Exit;
  end;
  mNext := TAtlasIdeSettings.Stored;
  mNext.DebugNoSourceIgnoredUnits := TAtlasNoSource.AddIgnored(mNext.DebugNoSourceIgnoredUnits, mUnit);
  TAtlasIdeSettings.Update(mNext);
  Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.NoSourceIgnored, [mUnit]));
end;

end.
