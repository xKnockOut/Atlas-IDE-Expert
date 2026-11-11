unit Atlas.IDE.Hotspots.Service;

// Fenster „Atlas-Hotspots“ (#1354) in der IDE:
// - ShowWindow zeigt das Fenster (Ansicht › Atlas › Hotspots, Befehlspalette
//   Atlas.Hotspots) und rechnet beim ersten Öffnen.
// - Request fragt den Server mit atlas.hotspots für das aktive Projekt im
//   Hintergrund, immer auf Methodenebene (die Antwort enthält dann Units und
//   Methoden; die Ebene im Fenster schaltet nur die Anzeige um). Der Server
//   liest den Verlauf über vcs.provider und die Werkzeugpfade (#1285) in
//   einem eigenen Thread und behält das Ergebnis bis zum nächsten Commit;
//   solange er rechnet, antwortet er "pending" und der Dienst fragt nach
//   cPollMs wieder (Zeitgeber im Hauptthread). „Neu berechnen“ verlangt eine
//   neue Rechnung ("refresh"). Die Antwort liest TAtlasHotspotModel, gezeigt
//   wird über TAtlasMainThread. Eine ältere Antwort, die nach einer neueren
//   Anfrage kommt, fällt weg.
// - Ohne Versionsverwaltung zeigt das Fenster den Grund statt einer leeren
//   Liste.
// - „Bericht speichern …“ geht an atlas.hotspots.saveReport; der Server
//   schreibt HTML, Markdown oder JSON nach der Endung, auf der Ebene des
//   Fensters.
// - Doppelklick springt zur Methode bzw. Unit; „Auswirkungen anzeigen“ setzt
//   den Cursor auf den Namen der Methode und ruft OnImpact (#1120), das die
//   Zusammensetzung setzt.
// - hotspots.enabled aus schließt das Fenster.
// Den Server erreicht der Dienst über ARun (Install), damit er die
// Zusammensetzung des Plugins nicht kennen muss. Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  /// <summary>Befehl des Servers im Hintergrund (nebenläufig zu anderen Befehlen); ADone bekommt die Antwort
  /// ('' bei Fehler oder Zeitlimit), aus einem beliebigen Thread. False = nicht gestartet (kein Server).</summary>
  TAtlasHotspotsRun = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeHotspots = class
  private class var
    FState: TObject;
  public class var
    /// <summary>„Auswirkungen anzeigen“ für das Symbol am Cursor (#1120); setzt die Zusammensetzung.</summary>
    OnImpact: TProc;
  public
    class procedure Install(const ARun: TAtlasHotspotsRun); static;
    class procedure Uninstall; static;
    /// <summary>Fenster zeigen; nichts, solange hotspots.enabled aus ist.</summary>
    class procedure ShowWindow; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    class function Enabled: Boolean; static;
  end;

implementation

uses
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hotspots.Model,
  Atlas.UI.Analysis.Strings,
  Atlas.UI.Hotspots.Frame,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Hotspots.Window;

const
  /// <summary>Die Antwort kommt sofort (der Server rechnet im Hintergrund); länger nur bei einem Server, der
  /// gerade den Index baut.</summary>
  cTimeoutMs = 60000;
  /// <summary>Abstand der Nachfragen, solange der Server rechnet.</summary>
  cPollMs = 2000;
  /// <summary>Das Fenster fragt immer beide Ebenen ab.</summary>
  cRequestLevel = 'method';

type
  /// <summary>Gelesene Antwort von atlas.hotspots.</summary>
  THotspotsAnswer = record
    Parsed: Boolean;
    Enabled: Boolean;
    HasVcs: Boolean;
    Message: string;
    Model: TAtlasHotspotModel;
  end;

  THotspotsState = class
  private
    FRun: TAtlasHotspotsRun;
    /// <summary>Nummer der letzten Anfrage; ältere Antworten fallen weg.</summary>
    FRequest: Integer;
    /// <summary>Eine Anfrage läuft (Antwort steht aus).</summary>
    FPending: Boolean;
    /// <summary>Zeitraum und Mindestzahl, mit denen zuletzt gefragt wurde.</summary>
    FMonths: Integer;
    FMinCommits: Integer;
    /// <summary>Fragt nach, solange der Server rechnet; nur im Hauptthread.</summary>
    FPoll: TTimer;
    procedure Wire(AFrame: TAtlasHotspotsFrame);
    procedure PollTimer(Sender: TObject);
    /// <summary>atlas.hotspots fragen; ARefresh verlangt eine neue Rechnung.</summary>
    procedure Request(ARefresh: Boolean);
    function AnswerHandler(ARequest: Integer): TProc<string>;
    /// <summary>Antwort auf die Anfrage ARequest im Hauptthread zeigen.</summary>
    procedure ShowAnswer(ARequest: Integer; const AAnswer: THotspotsAnswer);
    function ProjectUri(out AUri: string): Boolean;
    procedure Impact(const AFileName: string; ALine: Integer; const AMethod: string);
  public
    constructor Create(const ARun: TAtlasHotspotsRun);
    destructor Destroy; override;
    /// <summary>„Neu berechnen“.</summary>
    procedure Refresh;
    /// <summary>Rechnen, wenn das Fenster noch nichts zeigt und keine Anfrage läuft.</summary>
    procedure EnsureData;
    procedure Save(const AFileName: string);
    procedure ApplySettings;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.HotspotsEnabled and not TAtlasGuard.Disabled(TAtlasFeature.Hotspots);
end;

{ THotspotsState }

constructor THotspotsState.Create(const ARun: TAtlasHotspotsRun);
begin
  inherited Create;
  FRun := ARun;
  FMonths := TAtlasIdeSettings.Current.HotspotsMonths;
  FMinCommits := TAtlasIdeSettings.Current.HotspotsCouplingMinCommits;
  FPoll := TTimer.Create(nil);
  FPoll.Enabled := False;
  FPoll.Interval := cPollMs;
  FPoll.OnTimer := PollTimer;
  TAtlasIdeHotspotsWindow.OnFrame :=
    procedure(AFrame: TAtlasHotspotsFrame)
    begin
      Wire(AFrame);
    end;
  // Früh anmelden, damit die IDE das Fenster im Desktop speichert und wiederherstellt (#879).
  TAtlasIdeHotspotsWindow.Prepare;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeHotspotsWindow.ExistingFrame <> nil then
  begin
    Wire(TAtlasIdeHotspotsWindow.ExistingFrame);
  end;
end;

destructor THotspotsState.Destroy;
var
  mFrame: TAtlasHotspotsFrame;
begin
  // Antworten, die noch unterwegs sind, finden FState nicht mehr und fallen weg.
  Inc(FRequest);
  FPoll.Free;
  TAtlasIdeHotspotsWindow.OnFrame := nil;
  mFrame := TAtlasIdeHotspotsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnRefresh := nil;
    mFrame.OnSave := nil;
    mFrame.OnLevelChanged := nil;
    mFrame.OnOpen := nil;
    mFrame.OnImpact := nil;
  end;
  inherited Destroy;
end;

procedure THotspotsState.Wire(AFrame: TAtlasHotspotsFrame);
begin
  AFrame.OnRefresh :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Hotspots,
        procedure
        begin
          Refresh;
        end);
    end;
  AFrame.OnSave :=
    procedure(AFileName: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Hotspots,
        procedure
        begin
          Save(AFileName);
        end);
    end;
  AFrame.OnOpen :=
    procedure(AFileName: string; ALine: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine - 1, 0);
    end;
  AFrame.OnImpact :=
    procedure(AFileName: string; ALine: Integer; AMethod: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Hotspots,
        procedure
        begin
          Impact(AFileName, ALine, AMethod);
        end);
    end;
  // Vom Desktop wiederhergestellt: rechnen, sobald der Aufbau durch ist (dann ist meist auch das Projekt da).
  TAtlasMainThread.Queue(TAtlasFeature.Hotspots,
    procedure
    begin
      if (TAtlasIdeHotspots.FState = Self) and Active and TAtlasIdeHotspotsWindow.Visible then
      begin
        EnsureData;
      end;
    end);
end;

procedure THotspotsState.EnsureData;
var
  mFrame: TAtlasHotspotsFrame;
begin
  mFrame := TAtlasIdeHotspotsWindow.ExistingFrame;
  if (mFrame <> nil) and not mFrame.HasModel and not FPending and not FPoll.Enabled then
  begin
    Request(False);
  end;
end;

procedure THotspotsState.PollTimer(Sender: TObject);
begin
  FPoll.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.Hotspots,
    procedure
    begin
      if Active and (TAtlasIdeHotspotsWindow.ExistingFrame <> nil) then
      begin
        Request(False);
      end;
    end);
end;

procedure THotspotsState.Refresh;
begin
  Request(True);
end;

function THotspotsState.ProjectUri(out AUri: string): Boolean;
var
  mProject: IOTAProject;
begin
  AUri := '';
  mProject := GetActiveProject;
  Result := (mProject <> nil) and (mProject.FileName <> '');
  if Result then
  begin
    AUri := TLspSession.PathToUri(mProject.FileName);
  end;
end;

procedure THotspotsState.Impact(const AFileName: string; ALine: Integer; const AMethod: string);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mLines: TArray<string>;
  mColumn: Integer;
begin
  if not Assigned(TAtlasIdeHotspots.OnImpact) then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(AFileName, ALine - 1, 0);
  // Der Befehl wirkt auf das Symbol am Cursor: auf den Namen der Methode (bzw. der Unit) setzen.
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  mLines := TAtlasEditorBuffer.Text(mView.Buffer).Split([#13#10, #10]);
  if (ALine < 1) or (ALine > Length(mLines)) then
  begin
    Exit;
  end;
  mColumn := TAtlasHotspotCommands.NameColumn(mLines[ALine - 1], AMethod);
  if mColumn < 0 then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToPosition(ALine - 1, mColumn);
  TAtlasIdeHotspots.OnImpact();
end;

function THotspotsState.AnswerHandler(ARequest: Integer): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mAnswer: THotspotsAnswer;
    begin
      mAnswer := Default(THotspotsAnswer);
      mAnswer.Parsed := TAtlasHotspotModel.Parse(AAnswer, mAnswer.Model, mAnswer.Enabled, mAnswer.HasVcs,
        mAnswer.Message);
      TAtlasMainThread.Queue(TAtlasFeature.Hotspots,
        procedure
        begin
          ShowAnswer(ARequest, mAnswer);
        end);
    end;
end;

procedure THotspotsState.ShowAnswer(ARequest: Integer; const AAnswer: THotspotsAnswer);
var
  mCurrent: TAtlasHotspotsFrame;
begin
  if (TAtlasIdeHotspots.FState <> Self) or (ARequest <> FRequest) then
  begin
    Exit;
  end;
  FPending := False;
  mCurrent := TAtlasIdeHotspotsWindow.ExistingFrame;
  if mCurrent = nil then
  begin
    Exit;
  end;
  if not AAnswer.Parsed then
  begin
    mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsFailed), False);
  end
  else if not AAnswer.Enabled then
  begin
    mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsDisabled), False);
  end
  else if not AAnswer.HasVcs then
  begin
    mCurrent.SetMessage(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.HotspotsNoVcs, [AAnswer.Message]), False);
  end
  else if AAnswer.Model.Pending then
  begin
    // Der Server rechnet noch: bisherige Daten stehen lassen und später nachfragen.
    mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsLoading), True);
    FPoll.Enabled := True;
  end
  else
  begin
    mCurrent.SetModel(AAnswer.Model);
  end;
end;

procedure THotspotsState.Request(ARefresh: Boolean);
var
  mFrame: TAtlasHotspotsFrame;
  mUri: string;
  mRequest: Integer;
begin
  FPoll.Enabled := False;
  mFrame := TAtlasIdeHotspotsWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if not ProjectUri(mUri) then
  begin
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsNoProject), False);
    Exit;
  end;
  Inc(FRequest);
  mRequest := FRequest;
  FPending := True;
  FMonths := TAtlasIdeSettings.Current.HotspotsMonths;
  FMinCommits := TAtlasIdeSettings.Current.HotspotsCouplingMinCommits;
  mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsLoading), True);
  if not FRun(TAtlasHotspotCommands.cCommand, TAtlasHotspotCommands.Arguments(mUri, cRequestLevel, ARefresh),
    cTimeoutMs, AnswerHandler(mRequest)) then
  begin
    FPending := False;
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsNoServer), True);
  end;
end;

procedure THotspotsState.Save(const AFileName: string);
var
  mFrame: TAtlasHotspotsFrame;
  mUri: string;
begin
  mFrame := TAtlasIdeHotspotsWindow.ExistingFrame;
  if (mFrame = nil) or (AFileName = '') then
  begin
    Exit;
  end;
  if not ProjectUri(mUri) then
  begin
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsNoProject), True);
    Exit;
  end;
  if not FRun(TAtlasHotspotCommands.cSaveCommand,
    TAtlasHotspotCommands.SaveArguments(mUri, AFileName, mFrame.LevelValue), cTimeoutMs,
    procedure(AAnswer: string)
    var
      mSaved: string;
      mPendingSave: Boolean;
    begin
      mSaved := TAtlasHotspotCommands.SavedFile(AAnswer);
      mPendingSave := TAtlasHotspotCommands.IsPending(AAnswer);
      TAtlasMainThread.Queue(TAtlasFeature.Hotspots,
        procedure
        var
          mCurrent: TAtlasHotspotsFrame;
        begin
          if TAtlasIdeHotspots.FState <> Self then
          begin
            Exit;
          end;
          mCurrent := TAtlasIdeHotspotsWindow.ExistingFrame;
          if mCurrent = nil then
          begin
            Exit;
          end;
          if mSaved <> '' then
          begin
            mCurrent.SetMessage(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.HotspotsSaved, [mSaved]), True);
          end
          else if mPendingSave then
          begin
            mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsLoading), True);
          end
          else
          begin
            mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsFailed), True);
          end;
        end);
    end) then
  begin
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.HotspotsNoServer), True);
  end;
end;

procedure THotspotsState.ApplySettings;
var
  mChanged: Boolean;
begin
  mChanged := (FMonths <> TAtlasIdeSettings.Current.HotspotsMonths) or
    (FMinCommits <> TAtlasIdeSettings.Current.HotspotsCouplingMinCommits);
  // Zeitraum oder Kopplung auf der Optionsseite geändert: neu rechnen, solange das Fenster offen ist.
  if mChanged and TAtlasIdeHotspotsWindow.Visible then
  begin
    Request(False);
  end;
end;

{ TAtlasIdeHotspots }

class procedure TAtlasIdeHotspots.Install(const ARun: TAtlasHotspotsRun);
begin
  FreeAndNil(FState);
  FState := THotspotsState.Create(ARun);
end;

class procedure TAtlasIdeHotspots.Uninstall;
begin
  OnImpact := nil;
  FreeAndNil(FState);
  TAtlasIdeHotspotsWindow.Release;
end;

class function TAtlasIdeHotspots.Enabled: Boolean;
begin
  Result := Active;
end;

class procedure TAtlasIdeHotspots.ShowWindow;
var
  mFrame: TAtlasHotspotsFrame;
begin
  if (FState = nil) or not Active then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeHotspotsWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  // Beim ersten Öffnen rechnen; danach nur auf „Neu berechnen“ oder geänderte Einstellungen.
  THotspotsState(FState).EnsureData;
  if mFrame.Filter.CanFocus and mFrame.Filter.Showing then
  begin
    mFrame.Filter.SetFocus;
  end;
end;

class procedure TAtlasIdeHotspots.ApplySettings;
begin
  if FState = nil then
  begin
    Exit;
  end;
  if not Active then
  begin
    TAtlasIdeHotspotsWindow.Hide;
    Exit;
  end;
  THotspotsState(FState).ApplySettings;
end;

class procedure TAtlasIdeHotspots.ThemeChanged;
var
  mFrame: TAtlasHotspotsFrame;
begin
  TAtlasIdeHotspotsWindow.ApplyTheme;
  mFrame := TAtlasIdeHotspotsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.Chart.Invalidate;
  end;
end;

end.
