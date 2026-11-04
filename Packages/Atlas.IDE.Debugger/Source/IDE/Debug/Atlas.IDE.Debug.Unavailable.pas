unit Atlas.IDE.Debug.Unavailable;

// „kein Zugriff auf Wert“ beim Debuggen erklären (#840) in der IDE:
//   - Explain (Hover, über TAtlasEditorHover.OnExplain der Komposition):
//     Erkennt TAtlasDebugUnavailable den Fehlertext des Debuggers (bekannte
//     Texte und Ergänzungen aus %LOCALAPPDATA%\Atlas\debug-unavailable.txt),
//     steht sofort „‹kein Zugriff›“ mit „Ursache wird ermittelt …“ im Tooltip.
//     Atlas liest den Ausführungspunkt (oberster Rahmen), gleicht dessen Datei
//     im Hauptthread ab und fragt im Hintergrund atlas/debugUnavailable für
//     den ersten Bezeichner des Ausdrucks. Ohne laufenden Server, ohne Quelltext
//     am Halt oder ohne Antwort erklärt Atlas nur mit den Tatsachen des
//     Plugins (startet keinen Server).
//   - Tatsachen des Plugins: Konfiguration und Optionen beim Start
//     (TAtlasIdeDebugSession.LaunchValue) und ob der Halt außerhalb des
//     eigenen Codes liegt (TAtlasIdeDebugSources.OwnCode, #578).
//   - Texte der Ursache, der Herkunft des Schalters, der geprüften Punkte und
//     der Korrekturen kommen aus Atlas.UI.Strings.
//   - Fix (Klick auf eine Korrektur im Tooltip), jede erst nach einer Vorschau
//     mit Bestätigung (ausgeführt von TAtlasIdeDebugUnavailableFixes):
//       RestartWithDebug: Programm zurücksetzen (Aktion der IDE wie Strg+F2),
//         Konfiguration mit Debug-Informationen wählen („Debug“ zuerst) und
//         nach dem Ende der Sitzung „Start“ auslösen. Zurück: die frühere
//         Konfiguration in der Projektverwaltung wieder wählen.
//       RoutineOptimization, UnitOptimization: Einfügungen des Servers über
//         TAtlasIdeWorkspaceEdit; Strg+Z bzw. „Letzte Atlas-Änderung
//         zurücknehmen“ nimmt sie zurück.
//       DebugDcus: DCC_DebugDCUs in der Konfiguration des Starts auf true. Die
//         Projektoptionen kennen kein Strg+Z; die Vorschau nennt den alten
//         Wert, die Meldungsansicht wiederholt ihn mit dem Weg zurück.
//       ShowDirective: springt zur Direktive des Schalters.
// Ohne debug.explainUnavailable bleibt der Wert unverändert (Fehler wie bisher
// ausgeblendet). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Unavailable,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasUnavailableSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugUnavailable = class
  public const
    RequestTimeoutMs = 3000;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugEnded; override;
    end;
  private class var
    FInstance: TAtlasIdeDebugUnavailable;
    FPatterns: TArray<string>;
    FPatternsLoaded: Boolean;
  private
    FSession: TAtlasUnavailableSessionFunc;
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FWorkers: TList<TThread>;
    FRequest: Integer;
    // Letzte Erklärung: die Korrekturen brauchen ihre Tatsachen (Einfügungen, Schalter).
    FLastExpression: string;
    FLastFacts: TAtlasUnavailableFacts;
    FLastExplanation: TAtlasUnavailableExplanation;
    // Nach dem Zurücksetzen „Start“ auslösen (RestartWithDebug).
    FRestartPending: Boolean;
    constructor Create(const ASession: TAtlasUnavailableSessionFunc; const AMessage: TProc<string>);
    function ExplainValue(const AValue: TAtlasDebugValue; const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
    procedure Accept(ARequest: Integer; const AValue: TAtlasDebugValue; const AFacts: TAtlasUnavailableFacts;
      const ADone: TAtlasDebugValueEvent);
    procedure RunFix(const AValue: TAtlasDebugValue; AFix: TAtlasUnavailableFix);
    /// <summary>Ohne Server oder Quelltext: nur die Tatsachen des Plugins.</summary>
    function ExplainLocally(const AValue: TAtlasDebugValue; const AFacts: TAtlasUnavailableFacts): TAtlasDebugValue;
    /// <summary>Im Hintergrund nach dem ersten Bezeichner von AValue.Expression fragen; die Antwort geht über
    /// Accept an ADone.</summary>
    procedure StartFetch(ASession: TLspSession; const AFileName: string; ALine: Integer;
      const AValue: TAtlasDebugValue; const AFacts: TAtlasUnavailableFacts; const ADone: TAtlasDebugValueEvent);
    procedure RestartWithDebug;
    procedure Say(const AText: string);
    procedure ReapWorkers(AWait: Boolean);
    /// <summary>Datei (vollständig) und Zeile (0-basiert) des Ausführungspunkts; False ohne Quelltext.</summary>
    class function StopLocation(out AFileName: string; out ALine: Integer): Boolean; static;
    class function LaunchFacts: TAtlasUnavailableLaunch; static;
    /// <summary>Im Hintergrund-Thread: fragen und lesen.</summary>
    class procedure Fetch(ASession: TLspSession; const AFileName: string; ALine: Integer; const AName: string;
      var AFacts: TAtlasUnavailableFacts); static;
    /// <summary>Texte der Erklärung in AValue.Note.</summary>
    class function Describe(const AValue: TAtlasDebugValue; const AExplanation: TAtlasUnavailableExplanation;
      const AFacts: TAtlasUnavailableFacts): TAtlasDebugValue; static;
    class function OriginText(const ASwitch: TAtlasUnavailableSwitch; const AOption, AConfiguration: string): string;
      static;
  public
    destructor Destroy; override;
    /// <summary>AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Start(const ASession: TAtlasUnavailableSessionFunc; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.explainUnavailable an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Ergänzungen neu lesen (nach Änderung der Einstellungen).</summary>
    class procedure ApplySettings; static;
    /// <summary>Muster aus %LOCALAPPDATA%\Atlas\debug-unavailable.txt (einmal gelesen).</summary>
    class function Patterns: TArray<string>; static;
    /// <summary>„‹kein Zugriff›“ für die Werte im Editor; '' wenn abgeschaltet.</summary>
    class function InlineCaption: string; static;
    /// <summary>Für den Hover: AValue mit vorläufiger Erklärung; die fertige an ADone. Unverändert, wenn
    /// abgeschaltet, nicht gestartet oder kein bekannter Text.</summary>
    class function Explain(const AValue: TAtlasDebugValue; const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
      static;
    /// <summary>Korrektur AIndex aus AValue.Note.Fixes ausführen (nach Vorschau).</summary>
    class procedure Fix(const AValue: TAtlasDebugValue; AIndex: Integer); static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.UnavailableFixes,
  Atlas.UI.Debug.Strings;

const
  DebugDcusOption = TAtlasIdeDebugUnavailableFixes.DebugDcusOption;
  DebugInfoOption = TAtlasIdeDebugUnavailableFixes.DebugInfoOption;

function CheckText(ACheck: TAtlasUnavailableCheck): string;
const
  Ids: array[TAtlasUnavailableCheck] of TAtlasDebugTextId = (TAtlasDebugTextId.DebugUnavailableCheckConfiguration,
    TAtlasDebugTextId.DebugUnavailableCheckSymbols, TAtlasDebugTextId.DebugUnavailableCheckOptimization,
    TAtlasDebugTextId.DebugUnavailableCheckLifetime, TAtlasDebugTextId.DebugUnavailableCheckInline,
    TAtlasDebugTextId.DebugUnavailableCheckLibrary);
begin
  Result := TAtlasDebugStrings.Text(Ids[ACheck]);
end;

/// <summary>Zusatz zur Lebensdauer (1-basierte Zeilen); '' ohne.</summary>
function LifetimeText(ALifetime: TAtlasValueLifetime; const AFacts: TAtlasUnavailableFacts): string;
begin
  case ALifetime of
    TAtlasValueLifetime.Unused:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableUnused);
    TAtlasValueLifetime.Before:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableNotYet, [AFacts.FirstUse + 1]);
    TAtlasValueLifetime.After:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableNoLonger, [AFacts.LastUse + 1]);
  else
    Result := '';
  end;
end;

function Joined(const AFirst, ASecond: string): string;
begin
  Result := AFirst;
  if ASecond <> '' then
  begin
    Result := Result + ' ' + ASecond;
  end;
end;

{ TAtlasIdeDebugUnavailable.TListener }

procedure TAtlasIdeDebugUnavailable.TListener.DebugEnded;
begin
  if (FInstance = nil) or not FInstance.FRestartPending then
  begin
    Exit;
  end;
  FInstance.FRestartPending := False;
  TAtlasIdeDebugUnavailableFixes.Run(FInstance.Say);
end;

{ TAtlasIdeDebugUnavailable }

constructor TAtlasIdeDebugUnavailable.Create(const ASession: TAtlasUnavailableSessionFunc;
  const AMessage: TProc<string>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FWorkers := TList<TThread>.Create;
  FListener := TListener.Create;
  TAtlasIdeDebugSession.AddListener(FListener);
end;

destructor TAtlasIdeDebugUnavailable.Destroy;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FLastFacts := Default(TAtlasUnavailableFacts);
  FLastExplanation := Default(TAtlasUnavailableExplanation);
  inherited Destroy;
end;

class procedure TAtlasIdeDebugUnavailable.Start(const ASession: TAtlasUnavailableSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugUnavailable.Create(ASession, AMessage);
  end;
end;

class procedure TAtlasIdeDebugUnavailable.Release;
var
  Instance: TAtlasIdeDebugUnavailable;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  Instance := FInstance;
  FInstance := nil;
  Instance.Free;
  FPatterns := nil;
  FPatternsLoaded := False;
end;

class function TAtlasIdeDebugUnavailable.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugUnavailable.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugExplainUnavailable;
end;

class procedure TAtlasIdeDebugUnavailable.ApplySettings;
begin
  FPatternsLoaded := False;
  FPatterns := nil;
end;

class function TAtlasIdeDebugUnavailable.Patterns: TArray<string>;
var
  FileName, Text: string;
begin
  if not FPatternsLoaded then
  begin
    FPatternsLoaded := True;
    FPatterns := nil;
    try
      FileName := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
        TAtlasDebugUnavailable.UserFileName);
      if TFile.Exists(FileName) then
      begin
        Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
        FPatterns := TAtlasDebugUnavailable.ParsePatterns(Text);
      end;
    except
      // Unlesbare Ergänzungen: es gelten die bekannten Texte.
      FPatterns := nil;
    end;
  end;
  Result := FPatterns;
end;

class function TAtlasIdeDebugUnavailable.InlineCaption: string;
begin
  Result := '';
  if (FInstance <> nil) and Enabled then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableCaption);
  end;
end;

class function TAtlasIdeDebugUnavailable.Explain(const AValue: TAtlasDebugValue;
  const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
begin
  Result := AValue;
  if (FInstance = nil) or not Enabled or (AValue.State <> TAtlasDebugValueState.Failed) or
    not TAtlasDebugUnavailable.IsUnavailable(AValue.Text, Patterns) then
  begin
    Exit;
  end;
  Result := FInstance.ExplainValue(AValue, ADone);
end;

class function TAtlasIdeDebugUnavailable.StopLocation(out AFileName: string; out ALine: Integer): Boolean;
var
  Frames: TAtlasDebugFrames;
begin
  AFileName := '';
  ALine := -1;
  Result := (TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, Frames) =
    TAtlasDebugStackRead.Ready) and (Length(Frames) > 0) and Frames[0].HasSource;
  if not Result then
  begin
    Exit;
  end;
  TAtlasIdeDebugSources.MarkFrames(Frames);
  AFileName := Frames[0].FileName;
  ALine := Frames[0].Line - 1;
end;

class function TAtlasIdeDebugUnavailable.LaunchFacts: TAtlasUnavailableLaunch;
begin
  Result := Default(TAtlasUnavailableLaunch);
  Result.Configuration := TAtlasIdeDebugSession.LaunchConfiguration;
  Result.Known := Result.Configuration <> '';
  Result.DebugInfo := TAtlasIdeDebugSession.LaunchValue(DebugInfoOption);
  Result.LocalSymbols := TAtlasIdeDebugSession.LaunchValue('DCC_LocalDebugSymbols');
  Result.Optimization := TAtlasIdeDebugSession.LaunchValue('DCC_Optimize');
  Result.DebugDcus := TAtlasIdeDebugSession.LaunchValue(DebugDcusOption);
end;

function TAtlasIdeDebugUnavailable.ExplainValue(const AValue: TAtlasDebugValue;
  const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
var
  mSession: TLspSession;
  mBuffer: IOTAEditBuffer;
  mFileName, mName: string;
  mLine: Integer;
  mFacts: TAtlasUnavailableFacts;
  mLocated: Boolean;
begin
  Result := AValue;
  Result.Note.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableCaption);
  Result.Note.Pending := True;
  mLocated := StopLocation(mFileName, mLine);
  mFacts := TAtlasUnavailableFacts.Create(LaunchFacts, mLocated and
    not TAtlasIdeDebugSources.OwnCode.IsOwnFile(mFileName));
  mName := TAtlasDebugUnavailable.RootName(AValue.Expression);
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  mBuffer := nil;
  if mLocated then
  begin
    mBuffer := TAtlasIdeFiles.BufferOf(mFileName);
  end;
  Inc(FRequest);
  if (mSession = nil) or (mBuffer = nil) or (mName = '') then
  begin
    Result := ExplainLocally(AValue, mFacts);
    Exit;
  end;
  mFileName := mBuffer.FileName;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(mFileName, TAtlasEditorBuffer.Text(mBuffer));
  StartFetch(mSession, mFileName, mLine, AValue, mFacts, ADone);
end;

function TAtlasIdeDebugUnavailable.ExplainLocally(const AValue: TAtlasDebugValue;
  const AFacts: TAtlasUnavailableFacts): TAtlasDebugValue;
begin
  FLastExpression := AValue.Expression;
  FLastFacts := AFacts;
  FLastExplanation := TAtlasDebugUnavailable.Explain(AFacts);
  Result := Describe(AValue, FLastExplanation, AFacts);
end;

procedure TAtlasIdeDebugUnavailable.StartFetch(ASession: TLspSession; const AFileName: string; ALine: Integer;
  const AValue: TAtlasDebugValue; const AFacts: TAtlasUnavailableFacts; const ADone: TAtlasDebugValueEvent);
var
  mName: string;
  mRequest: Integer;
  mFacts: TAtlasUnavailableFacts;
  mValue: TAtlasDebugValue;
  mWorker: TThread;
begin
  mName := TAtlasDebugUnavailable.RootName(AValue.Expression);
  mRequest := FRequest;
  mFacts := AFacts;
  mValue := AValue;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mAnswer: TAtlasUnavailableFacts;
    begin
      mAnswer := mFacts;
      Fetch(ASession, AFileName, ALine, mName, mAnswer);
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.Debugger,
              procedure
              begin
                if FInstance <> nil then
                begin
                  FInstance.Accept(mRequest, mValue, mAnswer, ADone);
                end;
              end);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  ReapWorkers(False);
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

class procedure TAtlasIdeDebugUnavailable.Fetch(ASession: TLspSession; const AFileName: string; ALine: Integer;
  const AName: string; var AFacts: TAtlasUnavailableFacts);
var
  Response: TJSONValue;
begin
  Response := nil;
  try
    try
      Response := ASession.DebugUnavailable(AFileName, ALine, AName, RequestTimeoutMs);
      AFacts.ReadServer(Response);
    except
      // Server langsam oder weg: nur die Tatsachen des Plugins.
      AFacts.Server := False;
    end;
  finally
    Response.Free;
  end;
end;

procedure TAtlasIdeDebugUnavailable.Accept(ARequest: Integer; const AValue: TAtlasDebugValue;
  const AFacts: TAtlasUnavailableFacts; const ADone: TAtlasDebugValueEvent);
var
  Explanation: TAtlasUnavailableExplanation;
begin
  ReapWorkers(False);
  // Nur die jüngste Anfrage; ein Halt danach macht die Erklärung wertlos (der Hover fragt neu).
  if (ARequest <> FRequest) or not Enabled or (TAtlasIdeDebugSession.StoppedThread = nil) then
  begin
    Exit;
  end;
  Explanation := TAtlasDebugUnavailable.Explain(AFacts);
  FLastExpression := AValue.Expression;
  FLastFacts := AFacts;
  FLastExplanation := Explanation;
  if Assigned(ADone) then
  begin
    ADone(Describe(AValue, Explanation, AFacts));
  end;
end;

class function TAtlasIdeDebugUnavailable.OriginText(const ASwitch: TAtlasUnavailableSwitch;
  const AOption, AConfiguration: string): string;
begin
  Result := '';
  if not ASwitch.Known then
  begin
    Exit;
  end;
  case ASwitch.Source of
    TAtlasSwitchSource.Directive, TAtlasSwitchSource.Include:
      if ASwitch.FileName <> '' then
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableOriginDirective, [ASwitch.OriginText,
          ExtractFileName(ASwitch.FileName), ASwitch.Line + 1]);
      end;
    TAtlasSwitchSource.Project:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableOriginProject, [AOption, AConfiguration]);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableOriginDefault);
  end;
end;

class function TAtlasIdeDebugUnavailable.Describe(const AValue: TAtlasDebugValue;
  const AExplanation: TAtlasUnavailableExplanation; const AFacts: TAtlasUnavailableFacts): TAtlasDebugValue;
var
  Note: TAtlasDebugValueNote;
  Check: TAtlasUnavailableCheck;
  Fix: TAtlasUnavailableFix;
begin
  Result := AValue;
  Note := Default(TAtlasDebugValueNote);
  Note.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableCaption);
  case AExplanation.Cause of
    TAtlasUnavailableCause.ReleaseBuild:
      Note.Reason := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableRelease, [AExplanation.Configuration]);
    TAtlasUnavailableCause.NoDebugInfo:
      begin
        Note.Reason := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableNoDebugInfo);
        Note.Origin := OriginText(AExplanation.Switch, DebugInfoOption, AExplanation.Configuration);
      end;
    TAtlasUnavailableCause.NoLocalSymbols:
      begin
        Note.Reason := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableNoLocalSymbols);
        Note.Origin := OriginText(AExplanation.Switch, 'DCC_LocalDebugSymbols', AExplanation.Configuration);
      end;
    TAtlasUnavailableCause.Optimization:
      begin
        Note.Reason := Joined(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableOptimization),
          LifetimeText(AExplanation.Lifetime, AFacts));
        Note.Origin := OriginText(AExplanation.Switch, 'DCC_Optimize', AExplanation.Configuration);
      end;
    TAtlasUnavailableCause.Lifetime:
      Note.Reason := Joined(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableLifetime),
        LifetimeText(AExplanation.Lifetime, AFacts));
    TAtlasUnavailableCause.InlineRoutine:
      Note.Reason := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugUnavailableInline, [AExplanation.RoutineName]);
    TAtlasUnavailableCause.LibraryFrame:
      Note.Reason := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableLibrary);
  else
    begin
      Note.Reason := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugUnavailableUnknown);
      for Check in AExplanation.Checked do
      begin
        Note.Checked := Note.Checked + [CheckText(Check)];
      end;
    end;
  end;
  for Fix in AExplanation.Fixes do
  begin
    Note.Fixes := Note.Fixes + [TAtlasDebugValueFix.Create(Ord(Fix),
      TAtlasIdeDebugUnavailableFixes.FixText(Fix))];
  end;
  Result.Note := Note;
end;

class procedure TAtlasIdeDebugUnavailable.Fix(const AValue: TAtlasDebugValue; AIndex: Integer);
begin
  if (FInstance = nil) or not Enabled or (AIndex < 0) or (AIndex > High(AValue.Note.Fixes)) then
  begin
    Exit;
  end;
  if (AValue.Note.Fixes[AIndex].Id < Ord(Low(TAtlasUnavailableFix))) or
    (AValue.Note.Fixes[AIndex].Id > Ord(High(TAtlasUnavailableFix))) then
  begin
    Exit;
  end;
  FInstance.RunFix(AValue, TAtlasUnavailableFix(AValue.Note.Fixes[AIndex].Id));
end;

procedure TAtlasIdeDebugUnavailable.RunFix(const AValue: TAtlasDebugValue; AFix: TAtlasUnavailableFix);
begin
  // Die Tatsachen gehören zur letzten Erklärung; für einen anderen Ausdruck fehlen sie.
  if (AValue.Expression <> FLastExpression) or not FLastExplanation.HasFix(AFix) then
  begin
    Exit;
  end;
  case AFix of
    TAtlasUnavailableFix.RestartWithDebug:
      RestartWithDebug;
    TAtlasUnavailableFix.RoutineOptimization, TAtlasUnavailableFix.UnitOptimization:
      TAtlasIdeDebugUnavailableFixes.ApplyEdit(AFix, FLastFacts, Say);
    TAtlasUnavailableFix.DebugDcus:
      TAtlasIdeDebugUnavailableFixes.UseDebugDcus(FLastFacts.Launch.Configuration, Say);
    TAtlasUnavailableFix.ShowDirective:
      TAtlasIdeDebugUnavailableFixes.ShowDirective(FLastExplanation.Switch);
  end;
end;

procedure TAtlasIdeDebugUnavailable.RestartWithDebug;
begin
  if not TAtlasIdeDebugUnavailableFixes.PrepareRestart(Say) then
  begin
    Exit;
  end;
  if not TAtlasIdeDebugSession.Active then
  begin
    TAtlasIdeDebugUnavailableFixes.Run(Say);
    Exit;
  end;
  // Start erst, wenn der letzte Prozess weg ist (TListener.DebugEnded).
  FRestartPending := True;
  if not TAtlasIdeDebugUnavailableFixes.Reset(Say) then
  begin
    FRestartPending := False;
  end;
end;

procedure TAtlasIdeDebugUnavailable.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

procedure TAtlasIdeDebugUnavailable.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
  begin
    Exit;
  end;
  for Index := FWorkers.Count - 1 downto 0 do
  begin
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
  end;
end;

end.
