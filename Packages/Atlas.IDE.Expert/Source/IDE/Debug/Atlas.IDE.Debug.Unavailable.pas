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
//     mit Bestätigung:
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
    /// <summary>Konfiguration, die „Mit Debug neu starten“ zuerst wählt.</summary>
    DebugConfiguration = 'Debug';
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
    procedure ApplyEdit(AFix: TAtlasUnavailableFix);
    procedure RestartWithDebug;
    procedure UseDebugDcus;
    procedure ShowDirective;
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
    class function ExecuteAction(const AName: string; AShortCut: TShortCut): Boolean; static;
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
  System.Actions,
  System.UITypes,
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Dialogs,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Debug.Sources,
  Atlas.UI.Strings;

const
  ResetAction = 'RunProgramResetCommand';
  RunAction = 'RunRunCommand';
  DebugDcusOption = 'DCC_DebugDCUs';
  DebugInfoOption = 'DCC_DebugInformation';

function FixText(AFix: TAtlasUnavailableFix): string;
const
  Ids: array[TAtlasUnavailableFix] of TAtlasTextId = (TAtlasTextId.DebugUnavailableFixRestart,
    TAtlasTextId.DebugUnavailableFixRoutine, TAtlasTextId.DebugUnavailableFixUnit,
    TAtlasTextId.DebugUnavailableFixDcus, TAtlasTextId.DebugUnavailableFixDirective);
begin
  Result := TAtlasStrings.Text(Ids[AFix]);
end;

function CheckText(ACheck: TAtlasUnavailableCheck): string;
const
  Ids: array[TAtlasUnavailableCheck] of TAtlasTextId = (TAtlasTextId.DebugUnavailableCheckConfiguration,
    TAtlasTextId.DebugUnavailableCheckSymbols, TAtlasTextId.DebugUnavailableCheckOptimization,
    TAtlasTextId.DebugUnavailableCheckLifetime, TAtlasTextId.DebugUnavailableCheckInline,
    TAtlasTextId.DebugUnavailableCheckLibrary);
begin
  Result := TAtlasStrings.Text(Ids[ACheck]);
end;

/// <summary>Zusatz zur Lebensdauer (1-basierte Zeilen); '' ohne.</summary>
function LifetimeText(ALifetime: TAtlasValueLifetime; const AFacts: TAtlasUnavailableFacts): string;
begin
  case ALifetime of
    TAtlasValueLifetime.Unused:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableUnused);
    TAtlasValueLifetime.Before:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableNotYet, [AFacts.FirstUse + 1]);
    TAtlasValueLifetime.After:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableNoLonger, [AFacts.LastUse + 1]);
  else
    Result := '';
  end;
end;

function Joined(const AFirst, ASecond: string): string;
begin
  Result := AFirst;
  if ASecond <> '' then
    Result := Result + ' ' + ASecond;
end;

{ TAtlasIdeDebugUnavailable.TListener }

procedure TAtlasIdeDebugUnavailable.TListener.DebugEnded;
begin
  if (FInstance = nil) or not FInstance.FRestartPending then
    Exit;
  FInstance.FRestartPending := False;
  if not ExecuteAction(RunAction, ShortCut(VK_F9, [])) then
    FInstance.Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesNoRunAction));
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
    TAtlasIdeDebugSession.RemoveListener(FListener);
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
    FInstance := TAtlasIdeDebugUnavailable.Create(ASession, AMessage);
end;

class procedure TAtlasIdeDebugUnavailable.Release;
var
  Instance: TAtlasIdeDebugUnavailable;
begin
  if FInstance = nil then
    Exit;
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
    Result := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableCaption);
end;

class function TAtlasIdeDebugUnavailable.Explain(const AValue: TAtlasDebugValue;
  const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
begin
  Result := AValue;
  if (FInstance = nil) or not Enabled or (AValue.State <> TAtlasDebugValueState.Failed) or
    not TAtlasDebugUnavailable.IsUnavailable(AValue.Text, Patterns) then
    Exit;
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
    Exit;
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
  Session: TLspSession;
  Buffer: IOTAEditBuffer;
  FileName, Name: string;
  Line, Request: Integer;
  Facts: TAtlasUnavailableFacts;
  Located: Boolean;
  Worker: TThread;
begin
  Result := AValue;
  Result.Note.Caption := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableCaption);
  Result.Note.Pending := True;
  Located := StopLocation(FileName, Line);
  Facts := TAtlasUnavailableFacts.Create(LaunchFacts, Located and
    not TAtlasIdeDebugSources.OwnCode.IsOwnFile(FileName));
  Name := TAtlasDebugUnavailable.RootName(AValue.Expression);
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  Buffer := nil;
  if Located then
    Buffer := TAtlasIdeFiles.BufferOf(FileName);
  Inc(FRequest);
  Request := FRequest;
  if (Session = nil) or (Buffer = nil) or (Name = '') then
  begin
    // Ohne Server oder Quelltext: nur die Tatsachen des Plugins.
    FLastExpression := AValue.Expression;
    FLastFacts := Facts;
    FLastExplanation := TAtlasDebugUnavailable.Explain(Facts);
    Result := Describe(AValue, FLastExplanation, Facts);
    Exit;
  end;
  FileName := Buffer.FileName;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Session.Sync(FileName, TAtlasEditorBuffer.Text(Buffer));
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TAtlasUnavailableFacts;
    begin
      Answer := Facts;
      Fetch(Session, FileName, Line, Name, Answer);
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.Debugger,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, AValue, Answer, ADone);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  ReapWorkers(False);
  FWorkers.Add(Worker);
  Worker.Start;
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
    Exit;
  Explanation := TAtlasDebugUnavailable.Explain(AFacts);
  FLastExpression := AValue.Expression;
  FLastFacts := AFacts;
  FLastExplanation := Explanation;
  if Assigned(ADone) then
    ADone(Describe(AValue, Explanation, AFacts));
end;

class function TAtlasIdeDebugUnavailable.OriginText(const ASwitch: TAtlasUnavailableSwitch;
  const AOption, AConfiguration: string): string;
begin
  Result := '';
  if not ASwitch.Known then
    Exit;
  case ASwitch.Source of
    TAtlasSwitchSource.Directive, TAtlasSwitchSource.Include:
      if ASwitch.FileName <> '' then
        Result := TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableOriginDirective, [ASwitch.OriginText,
          ExtractFileName(ASwitch.FileName), ASwitch.Line + 1]);
    TAtlasSwitchSource.Project:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableOriginProject, [AOption, AConfiguration]);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableOriginDefault);
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
  Note.Caption := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableCaption);
  case AExplanation.Cause of
    TAtlasUnavailableCause.ReleaseBuild:
      Note.Reason := TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableRelease, [AExplanation.Configuration]);
    TAtlasUnavailableCause.NoDebugInfo:
      begin
        Note.Reason := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableNoDebugInfo);
        Note.Origin := OriginText(AExplanation.Switch, DebugInfoOption, AExplanation.Configuration);
      end;
    TAtlasUnavailableCause.NoLocalSymbols:
      begin
        Note.Reason := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableNoLocalSymbols);
        Note.Origin := OriginText(AExplanation.Switch, 'DCC_LocalDebugSymbols', AExplanation.Configuration);
      end;
    TAtlasUnavailableCause.Optimization:
      begin
        Note.Reason := Joined(TAtlasStrings.Text(TAtlasTextId.DebugUnavailableOptimization),
          LifetimeText(AExplanation.Lifetime, AFacts));
        Note.Origin := OriginText(AExplanation.Switch, 'DCC_Optimize', AExplanation.Configuration);
      end;
    TAtlasUnavailableCause.Lifetime:
      Note.Reason := Joined(TAtlasStrings.Text(TAtlasTextId.DebugUnavailableLifetime),
        LifetimeText(AExplanation.Lifetime, AFacts));
    TAtlasUnavailableCause.InlineRoutine:
      Note.Reason := TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableInline, [AExplanation.RoutineName]);
    TAtlasUnavailableCause.LibraryFrame:
      Note.Reason := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableLibrary);
  else
    begin
      Note.Reason := TAtlasStrings.Text(TAtlasTextId.DebugUnavailableUnknown);
      for Check in AExplanation.Checked do
        Note.Checked := Note.Checked + [CheckText(Check)];
    end;
  end;
  for Fix in AExplanation.Fixes do
    Note.Fixes := Note.Fixes + [TAtlasDebugValueFix.Create(Ord(Fix), FixText(Fix))];
  Result.Note := Note;
end;

class procedure TAtlasIdeDebugUnavailable.Fix(const AValue: TAtlasDebugValue; AIndex: Integer);
begin
  if (FInstance = nil) or not Enabled or (AIndex < 0) or (AIndex > High(AValue.Note.Fixes)) then
    Exit;
  if (AValue.Note.Fixes[AIndex].Id < Ord(Low(TAtlasUnavailableFix))) or
    (AValue.Note.Fixes[AIndex].Id > Ord(High(TAtlasUnavailableFix))) then
    Exit;
  FInstance.RunFix(AValue, TAtlasUnavailableFix(AValue.Note.Fixes[AIndex].Id));
end;

procedure TAtlasIdeDebugUnavailable.RunFix(const AValue: TAtlasDebugValue; AFix: TAtlasUnavailableFix);
begin
  // Die Tatsachen gehören zur letzten Erklärung; für einen anderen Ausdruck fehlen sie.
  if (AValue.Expression <> FLastExpression) or not FLastExplanation.HasFix(AFix) then
    Exit;
  case AFix of
    TAtlasUnavailableFix.RestartWithDebug:
      RestartWithDebug;
    TAtlasUnavailableFix.RoutineOptimization, TAtlasUnavailableFix.UnitOptimization:
      ApplyEdit(AFix);
    TAtlasUnavailableFix.DebugDcus:
      UseDebugDcus;
    TAtlasUnavailableFix.ShowDirective:
      ShowDirective;
  end;
end;

procedure TAtlasIdeDebugUnavailable.ApplyEdit(AFix: TAtlasUnavailableFix);
var
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Target: string;
begin
  if AFix = TAtlasUnavailableFix.RoutineOptimization then
    Edit := FLastFacts.RoutineEdit
  else
    Edit := FLastFacts.UnitEdit;
  if Edit.IsEmpty then
    Exit;
  Target := ExtractFileName(Edit.Files[0].FileName);
  // Vorschau: die eingefügten Zeilen; erst nach Bestätigung ändern.
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableConfirmEdit, [Target, sLineBreak + sLineBreak,
    string.Join(sLineBreak, TAtlasDebugUnavailable.PreviewLines(Edit)), sLineBreak + sLineBreak]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel], 0) <> mrOk then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), FixText(AFix));
  if Outcome.Error <> '' then
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]))
  else
    Say(TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableEditDone, [FixText(AFix), Target]));
end;

procedure TAtlasIdeDebugUnavailable.RestartWithDebug;
var
  Project: IOTAProject;
  Name, Chosen, Previous: string;
  Configurations: TArray<string>;
begin
  Project := GetActiveProject;
  if Project = nil then
    Exit;
  // Konfiguration mit Debug-Informationen: „Debug“, sonst die erste mit (ohne die Grundkonfiguration).
  Chosen := '';
  Configurations := TAtlasIdeProjectContext.Configurations(Project);
  for Name in Configurations do
    if SameText(Name, DebugConfiguration) and TAtlasDebugUnavailable.OptionOn(
      TAtlasIdeProjectContext.ConfigurationValue(Project, Name, '', DebugInfoOption), True) then
      Chosen := Name;
  if Chosen = '' then
    for Name in Configurations do
      if (Chosen = '') and not SameText(Name, 'Base') and TAtlasDebugUnavailable.OptionOn(
        TAtlasIdeProjectContext.ConfigurationValue(Project, Name, '', DebugInfoOption), True) then
        Chosen := Name;
  if Chosen = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.DebugUnavailableNoDebugConfiguration));
    Exit;
  end;
  Previous := Project.CurrentConfiguration;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableConfirmRestart, [Chosen, Previous,
    sLineBreak + sLineBreak]), TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel], 0) <> mrOk then
    Exit;
  if not SameText(Previous, Chosen) then
    Project.CurrentConfiguration := Chosen;
  if not TAtlasIdeDebugSession.Active then
  begin
    if not ExecuteAction(RunAction, ShortCut(VK_F9, [])) then
      Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesNoRunAction));
    Exit;
  end;
  // Start erst, wenn der letzte Prozess weg ist (TListener.DebugEnded).
  FRestartPending := True;
  if not ExecuteAction(ResetAction, ShortCut(VK_F2, [ssCtrl])) then
  begin
    FRestartPending := False;
    Say(TAtlasStrings.Text(TAtlasTextId.DebugUnavailableNoResetAction));
  end;
end;

procedure TAtlasIdeDebugUnavailable.UseDebugDcus;
var
  Project: IOTAProject;
  Build: IOTABuildConfiguration;
  Configuration, Previous: string;
begin
  Project := GetActiveProject;
  if Project = nil then
    Exit;
  Configuration := FLastFacts.Launch.Configuration;
  if Configuration = '' then
    Configuration := Project.CurrentConfiguration;
  Build := TAtlasIdeProjectContext.BuildConfiguration(Project, Configuration);
  if Build = nil then
    Exit;
  Previous := Trim(Build.GetValue(DebugDcusOption, True));
  if Previous = '' then
    Previous := 'false';
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableConfirmDcus, [Configuration,
    ExtractFileName(Project.FileName), Previous, sLineBreak + sLineBreak]), TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel], 0) <> mrOk then
    Exit;
  Build.SetValue(DebugDcusOption, 'true');
  Say(TAtlasStrings.Fmt(TAtlasTextId.DebugUnavailableDcusDone, [Configuration, Previous]));
end;

procedure TAtlasIdeDebugUnavailable.ShowDirective;
var
  Switch: TAtlasUnavailableSwitch;
begin
  Switch := FLastExplanation.Switch;
  if Switch.IsDirective then
    TAtlasIdeNavigation.GoToLocation(Switch.FileName, Switch.Line, 0);
end;

class function TAtlasIdeDebugUnavailable.ExecuteAction(const AName: string; AShortCut: TShortCut): Boolean;
var
  Services: INTAServices;
  Index: Integer;
  Action: TContainedAction;
  Found: TContainedAction;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  Found := nil;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
    if SameText(Services.ActionList.Actions[Index].Name, AName) then
      Found := Services.ActionList.Actions[Index];
  // Ersatz: die Aktion mit dem Tastenkürzel der IDE.
  if Found = nil then
    for Index := 0 to Services.ActionList.ActionCount - 1 do
    begin
      Action := Services.ActionList.Actions[Index];
      if (Found = nil) and (Action is TCustomAction) and (TCustomAction(Action).ShortCut = AShortCut) then
        Found := Action;
    end;
  if Found = nil then
    Exit;
  Found.Update;
  if (Found is TCustomAction) and not TCustomAction(Found).Enabled then
    Exit;
  Found.Execute;
  Result := True;
end;

procedure TAtlasIdeDebugUnavailable.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

procedure TAtlasIdeDebugUnavailable.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

end.
