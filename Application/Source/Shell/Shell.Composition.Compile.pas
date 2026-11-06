unit Shell.Composition.Compile;

// Internals-Rolle Shell: Compilerläufe des Servers (#40, #261). Wählt den Weg zum Compiler (dcc oder eigene IDE
// über cc.ps1), baut im eigenen Thread, merkt einen Auftrag während eines Laufs vor und veröffentlicht die Meldungen.
// Ohne nutzbaren Compiler stehen Grund und Ausweg einmal je Grund und Sitzung als Meldung im Editor und dauerhaft
// im Status (#28). Beenden (A-05) bricht den Prozess ab, statt auf ihn zu warten.

interface

uses
  System.Classes,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Backend,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Compiler.Results,
  Atlas.Common.Lsp.WorkDoneProgress,
  Atlas.Common.Lsp.Status,
  Shell.Compiler;

type
  /// <summary>Auftrag für AFileName (leer: das gewählte Projekt); False mit Grund in AError.</summary>
  TShellCompileJobFunc = reference to function(const AFileName: string; out AJob: TShellCompileJob;
    out AError: string): Boolean;
  /// <summary>Meldungen eines Laufs sind da; AFiles sind die Dateien, deren Meldungen sich geändert haben.</summary>
  TShellCompilePublish = reference to procedure(const AFiles: TArray<string>);

  /// <summary>Was die Compilerläufe vom Server brauchen.</summary>
  TShellCompileServices = record
    Logger: ILogger;
    /// <summary>Für window/showMessage; nil ohne Editor.</summary>
    Transport: IJsonRpcTransport;
    Process: ICompilerProcess;
    Progress: TLspWorkDoneProgress;
    Editions: TShellCompilerEditions;
    IdeCompiler: TShellIdeCompiler;
    JobFor: TShellCompileJobFunc;
    Publish: TShellCompilePublish;
  end;

  TShellCompileHost = class
  private
    FServices: TShellCompileServices;
    FResults: TCompilerResults;
    FLock: TObject;
    FThread: TThread;
    FCompiling: Boolean;
    FStopping: Boolean;
    FHasPending: Boolean;
    FPending: TShellCompileJob;
    FUnavailable: string;
    FChoice: TCompilerBackendChoice;
    FHasChoice: Boolean;
    FShown: TArray<string>;
    FRestricted: Boolean;
    function Choose(const AFileName: string; out AJob: TShellCompileJob; out AChoice: TCompilerBackendChoice): Boolean;
    function ChoiceFor(const AJob: TShellCompileJob; AEdition: TCompilerEdition): TCompilerBackendChoice;
    procedure Remember(const AChoice: TCompilerBackendChoice);
    procedure Unavailable(const AChoice: TCompilerBackendChoice; AShow: Boolean);
    function MarkUnavailable(const AChoice: TCompilerBackendChoice; AShow: Boolean; out AFirst: Boolean): Boolean;
    procedure ShowMessage(const AText: string);
    function Prepare(const AFileName: string; out AJob: TShellCompileJob;
      out AChoice: TCompilerBackendChoice): Boolean;
    function Enqueue(var AJob: TShellCompileJob): Boolean;
    procedure Launch(const AJob: TShellCompileJob);
    function NextJob(var AJob: TShellCompileJob): Boolean;
    procedure Loop(const AJob: TShellCompileJob);
    procedure CompileOnce(const AJob: TShellCompileJob);
    procedure CompileWithDcc(const AJob: TShellCompileJob);
    procedure Unlicensed(const AJob: TShellCompileJob);
    procedure CompileWithIde(const AJob: TShellCompileJob);
    procedure Publish(const AMessages: TArray<TCompilerMessage>; const AVia: string);
  public
    /// <summary>Übernimmt Progress, Editions und IdeCompiler.</summary>
    constructor Create(const AServices: TShellCompileServices);
    destructor Destroy; override;
    /// <summary>Startet einen Lauf für AFileName (leer: das gewählte Projekt). AManual: auf den Befehl; sonst nach
    /// dem Speichern. False, wenn kein nutzbarer Compiler da ist; AChoice sagt warum.</summary>
    function Start(const AFileName: string; AManual: Boolean; out AChoice: TCompilerBackendChoice): Boolean;
    /// <summary>Beenden (A-05): keinen Lauf mehr starten, den Prozess abbrechen, die eigene IDE beenden.</summary>
    procedure Stop;
    /// <summary>Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40), der Status prüft
    /// den Weg neu (#261).</summary>
    procedure Reset;
    /// <summary>Weg zum Compiler für den Status (#261): zuletzt gewählt, sonst jetzt geprüft.</summary>
    procedure StatusOf(var AStatus: TServerStatus);
    /// <summary>Meldungen des letzten Laufs je Datei.</summary>
    property Results: TCompilerResults read FResults;
    /// <summary>Workspace Trust (#186): Ein Compilerlauf kann Build-Ereignisse des Projekts ausführen.</summary>
    property Restricted: Boolean read FRestricted write FRestricted;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.OutputParser,
  Atlas.Common.JsonRpc.Messages,
  Shell.Platform,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TCompileHostText = (Restricted, TrustHint, NotUsable, NotLicensed, NoMessages, Compiling, CompilingIde, CheckSetup,
    Failed, Summary);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TCompileHostText] of TAtlasText = (
    (De: 'Der Arbeitsbereich ist nicht vertrauenswürdig'; En: 'The workspace is not trusted'),
    (De: 'Dem Ordner im Editor vertrauen; ein Compilerlauf kann Build-Ereignisse des Projekts ausführen.';
    En: 'Trust the folder in the editor; a compiler run can execute build events of the project.'),
    (De: 'Compiler nicht nutzbar'; En: 'Compiler not usable'),
    (De: 'Kommandozeilen-Compiler nicht lizenziert'; En: 'Command-line compiler not licensed'),
    (De: '%s endet mit Exit-Code %d ohne Meldungen:%s'; En: '%s ends with exit code %d without messages:%s'),
    (De: 'Projekt kompilieren'; En: 'Compile project'),
    (De: 'Projekt über eine eigene IDE kompilieren'; En: 'Compile project through an IDE of its own'),
    (De: 'cc.ps1 und die Delphi-Installation prüfen; Einzelheiten stehen im Server-Log.';
    En: 'Check cc.ps1 and the Delphi installation; details are in the server log.'),
    (De: 'Fehlgeschlagen'; En: 'Failed'),
    (De: '%d Fehler, %d Warnungen, %d Hinweise'; En: '%d errors, %d warnings, %d hints'));

constructor TShellCompileHost.Create(const AServices: TShellCompileServices);
begin
  inherited Create;
  FServices := AServices;
  FResults := TCompilerResults.Create;
  FLock := TObject.Create;
end;

destructor TShellCompileHost.Destroy;
begin
  // Stop ruft der Server, solange Diagnoselog und Syntaxprüfung noch leben (A-05).
  FServices.Progress.Free;
  FServices.IdeCompiler.Free;
  FServices.Editions.Free;
  FLock.Free;
  FResults.Free;
  inherited Destroy;
end;

procedure TShellCompileHost.Remember(const AChoice: TCompilerBackendChoice);
begin
  System.TMonitor.Enter(FLock);
  try
    FChoice := AChoice;
    FHasChoice := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellCompileHost.MarkUnavailable(const AChoice: TCompilerBackendChoice; AShow: Boolean;
  out AFirst: Boolean): Boolean;
var
  mShown: string;
begin
  System.TMonitor.Enter(FLock);
  try
    AFirst := FUnavailable <> AChoice.Reason;
    FUnavailable := AChoice.Reason;
    FChoice := AChoice;
    FHasChoice := True;
    Result := AShow;
    for mShown in FShown do
    begin
      Result := Result and (mShown <> AChoice.Reason);
    end;
    if Result then
    begin
      FShown := FShown + [AChoice.Reason];
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellCompileHost.ShowMessage(const AText: string);
var
  mParams, mNotification: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('type', TJSONNumber.Create(2));
  mParams.AddPair('message', AText);
  mNotification := TJsonRpcMessages.Notification('window/showMessage', mParams);
  try
    FServices.Transport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

procedure TShellCompileHost.Unavailable(const AChoice: TCompilerBackendChoice; AShow: Boolean);
var
  mFirst, mShow: Boolean;
begin
  mShow := MarkUnavailable(AChoice, AShow, mFirst);
  if mFirst then
  begin
    FServices.Logger.Warning('Kompilieren nicht möglich: ' + TLogMarks.Text(AChoice.Reason) +
      '. Nach dem Speichern wird bis zum nächsten Laden des Projekts nicht mehr kompiliert; ' +
      'der Befehl "Projekt kompilieren" versucht es erneut.');
  end;
  // Das Log sieht im Editor kaum jemand (#261): Grund und Ausweg einmal je Grund und Sitzung als Meldung;
  // dauerhaft steht es im Status (#28).
  if mShow and (FServices.Transport <> nil) then
  begin
    ShowMessage(AChoice.MessageText);
  end;
end;

function TShellCompileHost.ChoiceFor(const AJob: TShellCompileJob; AEdition: TCompilerEdition): TCompilerBackendChoice;
begin
  Result := TCompilerBackends.Choose(AJob.Settings.Backend, AEdition, AJob.Settings.IdeCommand,
    (Trim(AJob.Settings.IdeCommand) <> '') and FileExists(AJob.Settings.IdeCommand));
end;

function TShellCompileHost.Choose(const AFileName: string; out AJob: TShellCompileJob;
  out AChoice: TCompilerBackendChoice): Boolean;
var
  mError: string;
  mEdition: TCompilerEdition;
begin
  AJob := Default(TShellCompileJob);
  Result := FServices.JobFor(AFileName, AJob, mError);
  if not Result then
  begin
    AChoice := TCompilerBackendChoice.Unavailable(mError, '');
    Exit;
  end;
  // Die Ausgabe der Installation zählt nur für auto und dcc; erkannt wird einmal je Installation (#261).
  mEdition := TCompilerEdition.Unknown;
  if (AJob.Settings.Backend = TCompilerBackendSetting.Auto) or (AJob.Settings.Backend = TCompilerBackendSetting.Dcc)
  then
  begin
    mEdition := FServices.Editions.Resolve(AJob.BdsRoot, AJob.Version, AJob.Request.Executable);
  end;
  AChoice := ChoiceFor(AJob, mEdition);
end;

/// <summary>Grund für Workspace Trust (#186).</summary>
function RestrictedChoice: TCompilerBackendChoice;
begin
  Result := TCompilerBackendChoice.Unavailable(cTexts[TCompileHostText.Restricted].Text,
    cTexts[TCompileHostText.TrustHint].Text);
end;

/// <summary>Kein nutzbarer Weg: bewusst abgeschaltet nur im Status, sonst Grund und Ausweg einmal als Meldung (#261).
/// </summary>
function TShellCompileHost.Prepare(const AFileName: string; out AJob: TShellCompileJob;
  out AChoice: TCompilerBackendChoice): Boolean;
begin
  try
    Result := Choose(AFileName, AJob, AChoice);
  except
    on ECompilerCancelled do
      Exit(False); // Beenden läuft (A-05).
  end;
  if not Result then
  begin
    // Ohne Projekt oder Installation: nur ins Log, wie bisher (#40).
    Unavailable(AChoice, False);
  end
  else if AChoice.Usable or (AJob.Settings.Backend = TCompilerBackendSetting.Off) then
  begin
    Remember(AChoice);
    Result := AChoice.Usable;
  end
  else
  begin
    Unavailable(AChoice, True);
    Result := False;
  end;
end;

function TShellCompileHost.Enqueue(var AJob: TShellCompileJob): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    // Beenden läuft schon (A-05): keinen neuen Thread mehr starten.
    Result := not FStopping and not FCompiling;
    if FCompiling and not FStopping then
    begin
      // Der laufende Lauf startet danach den neuesten Stand; ein vorgemerkter Befehl bleibt ein Befehl.
      AJob.Manual := AJob.Manual or (FHasPending and FPending.Manual);
      FPending := AJob;
      FHasPending := True;
    end;
    FCompiling := FCompiling or Result;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellCompileHost.Launch(const AJob: TShellCompileJob);
var
  mJob: TShellCompileJob;
begin
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  mJob := AJob;
  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.NameThreadForDebugging('Atlas.Compile');
      Loop(mJob);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

function TShellCompileHost.Start(const AFileName: string; AManual: Boolean;
  out AChoice: TCompilerBackendChoice): Boolean;
var
  mJob: TShellCompileJob;
  mUnavailable: Boolean;
begin
  AChoice := Default(TCompilerBackendChoice);
  if FRestricted then
  begin
    AChoice := RestrictedChoice;
    if AManual then
    begin
      FServices.Logger.Warning('Kompilieren ist in einem nicht vertrauenswürdigen Arbeitsbereich abgeschaltet');
    end;
    Exit(False);
  end;
  System.TMonitor.Enter(FLock);
  try
    mUnavailable := FUnavailable <> '';
    if mUnavailable then
    begin
      AChoice := FChoice;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := (AManual or not mUnavailable) and Prepare(AFileName, mJob, AChoice);
  // Die eigene IDE ist langsam: nur auf den Befehl, nie nach dem Speichern (#261).
  if Result and (AManual or TCompilerBackends.RunsOnSave(AChoice.Backend)) then
  begin
    mJob.Backend := AChoice.Backend;
    mJob.Manual := AManual;
    if Enqueue(mJob) then
    begin
      Launch(mJob);
    end;
  end;
end;

function TShellCompileHost.NextJob(var AJob: TShellCompileJob): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := not FStopping and FHasPending;
    if Result then
    begin
      AJob := FPending;
      FHasPending := False;
    end
    else
    begin
      FCompiling := False;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellCompileHost.Loop(const AJob: TShellCompileJob);
var
  mJob: TShellCompileJob;
  mDone: Boolean;
begin
  mJob := AJob;
  mDone := False;
  try
    try
      repeat
        CompileOnce(mJob);
        mDone := not NextJob(mJob);
      until mDone;
    except
      // Sonst läge die Ausnahme ungelesen in FatalException und FCompiling bliebe True (Code-Review S-06).
      on E: Exception do
        FServices.Logger.Error(Format('Compilerlauf abgebrochen: %s: %s', [E.ClassName, TLogMarks.Text(E.Message)]));
    end;
  finally
    if not mDone then
    begin
      System.TMonitor.Enter(FLock);
      try
        FCompiling := False;
        FHasPending := False;
      finally
        System.TMonitor.Exit(FLock);
      end;
    end;
  end;
end;

procedure TShellCompileHost.CompileOnce(const AJob: TShellCompileJob);
begin
  try
    // Im try (S-06): Wirft schon der Start des Fortschritts, endet der Lauf geordnet.
    if AJob.Backend = TCompilerBackend.Ide then
    begin
      CompileWithIde(AJob);
    end
    else
    begin
      CompileWithDcc(AJob);
    end;
  except
    on ECompilerCancelled do
      ; // Beenden (A-05): nichts mehr melden, der Transport ist schon zu.
    on E: Exception do
    begin
      Unavailable(TCompilerBackendChoice.Unavailable(E.Message, ''), False);
      FServices.Progress.Finish(cTexts[TCompileHostText.Failed].Text);
    end;
  end;
end;

/// <summary>Starter bzw. Community Edition (#261): dcc ist da, darf aber nicht von der Kommandozeile bauen. Merken,
/// damit auto künftig gleich richtig wählt; bei einem Befehl gleich über die IDE bauen.</summary>
procedure TShellCompileHost.Unlicensed(const AJob: TShellCompileJob);
var
  mChoice: TCompilerBackendChoice;
  mIdeJob: TShellCompileJob;
begin
  FServices.Editions.Remember(AJob.BdsRoot, AJob.Version, AJob.Request.Executable, TCompilerEdition.NoCommandLine);
  mChoice := ChoiceFor(AJob, TCompilerEdition.NoCommandLine);
  if not mChoice.Usable then
  begin
    Unavailable(mChoice, True);
    FServices.Progress.Finish(cTexts[TCompileHostText.NotUsable].Text);
    Exit;
  end;
  Remember(mChoice);
  FServices.Progress.Finish(cTexts[TCompileHostText.NotLicensed].Text);
  if AJob.Manual then
  begin
    mIdeJob := AJob;
    mIdeJob.Backend := mChoice.Backend;
    CompileWithIde(mIdeJob);
  end;
end;

/// <summary>Die ersten drei nicht leeren Zeilen der Ausgabe, je mit Leerzeichen davor.</summary>
function OutputStart(const ALines: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to Min(Length(ALines), 3) - 1 do
  begin
    if Trim(ALines[mIndex]) <> '' then
    begin
      Result := Result + ' ' + Trim(ALines[mIndex]);
    end;
  end;
end;

/// <summary>Führt AJob aus und sammelt die Ausgabe in ALines; Exit-Code.</summary>
function RunCompiler(const AProcess: ICompilerProcess; const AJob: TShellCompileJob; ALines: TList<string>): Integer;
begin
  ForceDirectories(AJob.OutputDir);
  Result := AProcess.Run(AJob.Request,
    procedure(const ALine: string)
    begin
      ALines.Add(ALine);
    end);
end;

procedure TShellCompileHost.CompileWithDcc(const AJob: TShellCompileJob);
var
  mLines: TList<string>;
  mOutput: TArray<string>;
  mMessages: TArray<TCompilerMessage>;
  mCode: Integer;
begin
  mLines := TList<string>.Create;
  try
    FServices.Progress.Start(cTexts[TCompileHostText.Compiling].Text);
    mCode := RunCompiler(FServices.Process, AJob, mLines);
    mOutput := mLines.ToArray;
  finally
    mLines.Free;
  end;
  mMessages := TCompilerOutputParser.Parse(mOutput, AJob.Request.WorkingDir);
  if (mCode <> 0) and (Length(mMessages) = 0) and TCompilerEditions.HasLicenseText(mOutput) then
  begin
    Unlicensed(AJob);
  end
  else if (mCode <> 0) and (Length(mMessages) = 0) then
  begin
    // Abbruch ohne eine einzige Meldung: Der Compiler selbst ist nicht nutzbar. Bisherige Meldungen bleiben stehen.
    Unavailable(TCompilerBackendChoice.Unavailable(cTexts[TCompileHostText.NoMessages].Fmt([
      ExtractFileName(AJob.Request.Executable), mCode, OutputStart(mOutput)]), ''), False);
    FServices.Progress.Finish(cTexts[TCompileHostText.NotUsable].Text);
  end
  else
  begin
    Publish(mMessages, Format('%s (Exit-Code %d)', [ExtractFileName(AJob.Request.Executable), mCode]));
  end;
end;

procedure TShellCompileHost.CompileWithIde(const AJob: TShellCompileJob);
var
  mMessages: TArray<TCompilerMessage>;
  mSucceeded: Boolean;
  mError: string;
begin
  FServices.Progress.Start(cTexts[TCompileHostText.CompilingIde].Text);
  if not FServices.IdeCompiler.Build(AJob.Settings.IdeCommand, AJob.Project, AJob.Platform, mMessages, mSucceeded, mError) then
  begin
    Unavailable(TCompilerBackendChoice.Unavailable(mError, cTexts[TCompileHostText.CheckSetup].Text), True);
    FServices.Progress.Finish(cTexts[TCompileHostText.Failed].Text);
  end
  else if mSucceeded then
  begin
    Publish(mMessages, 'eigene IDE (erfolgreich)');
  end
  else
  begin
    Publish(mMessages, 'eigene IDE (misslungen)');
  end;
end;

procedure TShellCompileHost.Publish(const AMessages: TArray<TCompilerMessage>; const AVia: string);
var
  mItem: TCompilerMessage;
  mCounts: array[TCompilerSeverity] of Integer;
  mSummary: string;
begin
  System.TMonitor.Enter(FLock);
  try
    FUnavailable := '';
  finally
    System.TMonitor.Exit(FLock);
  end;
  FillChar(mCounts, SizeOf(mCounts), 0);
  for mItem in AMessages do
  begin
    Inc(mCounts[mItem.Severity]);
    if mItem.FileName = '' then
    begin
      FServices.Logger.Warning(Format('Compiler: %s %s', [mItem.Code, TLogMarks.Text(mItem.Text)]));
    end;
  end;
  FServices.Publish(FResults.Replace(AMessages));
  mSummary := cTexts[TCompileHostText.Summary].Fmt([mCounts[TCompilerSeverity.Error] +
    mCounts[TCompilerSeverity.Fatal], mCounts[TCompilerSeverity.Warning], mCounts[TCompilerSeverity.Hint]]);
  FServices.Logger.Info(Format('Kompiliert über %s: %s', [AVia, mSummary]));
  FServices.Progress.Finish(mSummary);
end;

procedure TShellCompileHost.Stop;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopping := True;
    FHasPending := False;
  finally
    System.TMonitor.Exit(FLock);
  end;
  // Statt unbegrenzt auf dcc32 zu warten: Prozess beenden, dann endet der Thread sofort.
  if FServices.Process <> nil then
  begin
    FServices.Process.Cancel;
  end;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  // Eigene IDE (#261) mit dem Server beenden; der alte Läufer ist abgebrochen, deshalb ein neuer.
  if (FServices.IdeCompiler <> nil) and (FServices.IdeCompiler.Pid <> 0) then
  begin
    FServices.IdeCompiler.Quit(TProcessRunner.Create);
  end;
end;

procedure TShellCompileHost.Reset;
begin
  System.TMonitor.Enter(FLock);
  try
    FUnavailable := '';
    FHasChoice := False;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellCompileHost.StatusOf(var AStatus: TServerStatus);
var
  mChoice: TCompilerBackendChoice;
  mJob: TShellCompileJob;
  mKnown: Boolean;
begin
  // Zuletzt gewählt; sonst jetzt prüfen (die Ausgabe der Installation ist meist schon gemerkt). Eine Meldung zeigt
  // erst ein Compilerlauf.
  System.TMonitor.Enter(FLock);
  try
    mKnown := FHasChoice;
    mChoice := FChoice;
  finally
    System.TMonitor.Exit(FLock);
  end;
  if not mKnown and not FRestricted then
    try
      mKnown := Choose('', mJob, mChoice);
      if mKnown then
      begin
        Remember(mChoice);
      end;
    except
      on E: Exception do
        FServices.Logger.Debug('Weg zum Compiler nicht geprüft: ' + E.ClassName);
    end;
  if FRestricted then
  begin
    mChoice := TCompilerBackendChoice.Unavailable(cTexts[TCompileHostText.Restricted].Text, '');
    mKnown := True;
  end;
  if not mKnown then
  begin
    AStatus.Compiler := TCompilerBackends.UncheckedStatus;
    Exit;
  end;
  AStatus.Compiler := mChoice.StatusText;
  AStatus.CompilerBackend := TCompilerBackends.BackendText(mChoice.Backend);
  AStatus.CompilerReason := mChoice.MessageText;
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Compile', cTexts);

end.
