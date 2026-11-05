unit Atlas.IDE.CodeInsight.Manager.Editors;

// Anbindungen des Code Insight-Managers an den Editor: Vervollständigung im eigenen Popup (#410), Parameter-Hint
// (#436), eigener Hover-Tooltip (#442), Probleme (#398), Inlay-Hints (#401) und Code Lens zur Testunit (#189) und
// mit Code-Metriken (#66). Sie fragen die Sitzung über die Haken des Managers; abgebaut wird in der Reihenfolge,
// die StopSession und Shutdown brauchen.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Signature.Contract,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.Signature.Editor,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.InlayHints.Editor,
  Atlas.IDE.Editor.Lens,
  Atlas.IDE.Editor.TestUnitLens,
  Atlas.IDE.Editor.MetricsSource,
  Atlas.IDE.Problems.Controller;

type
  /// <summary>Was die Anbindungen vom Manager brauchen.</summary>
  TAtlasCodeInsightEditorHooks = record
    /// <summary>Laufende Sitzung oder Start im Hauptthread; außerhalb des Hauptthreads nur, was schon läuft (A-01).
    /// </summary>
    EnsureSession: TFunc<Boolean>;
    /// <summary>Laufende Sitzung oder nil, nie während StopSession; startet keinen Server.</summary>
    RunningSession: TFunc<TLspSession>;
    /// <summary>Server läuft und Sitzung initialisiert; startet keinen Server.</summary>
    ReadySession: TFunc<TLspSession>;
    /// <summary>Befehl im Hintergrund an den laufenden Server (Code Lens); die Antwort im Hauptthread.</summary>
    RunCommandAsync: TAtlasLensCommandProc;
    Diagnose: TProc<string>;
    /// <summary>Bedient Atlas diese Datei?</summary>
    Handles: TFunc<string, Boolean>;
    /// <summary>Editoransicht, in der Code Insight gerade läuft.</summary>
    EditView: TFunc<IOTAEditView>;
    NewCompletionSources: TAtlasCompletionSourcesFactory;
    NewSignatureSource: TFunc<TAtlasSessionFunc, IAtlasSignatureSource>;
  end;

  /// <summary>Editor-Anbindungen des Managers.</summary>
  TAtlasCodeInsightEditors = class
  private
    FHooks: TAtlasCodeInsightEditorHooks;
    FCompletion: TAtlasEditorCompletion;
    FSignature: TAtlasEditorSignature;
    FHover: TAtlasEditorHover;
    FProblems: TAtlasProblemsController;
    FInlayHints: TAtlasEditorInlayHints;
    FTestUnitLens: TAtlasEditorTestUnitLens;
    FMetricsSource: TAtlasEditorMetricsSource;
    procedure CreateProblems;
    procedure CreateHover;
    procedure CreateLenses;
  public
    /// <summary>Probleme, Hover, Inlay-Hints und Code Lens anlegen; Vervollständigung und Parameter-Hint erst beim
    /// ersten Gebrauch.</summary>
    constructor Create(const AHooks: TAtlasCodeInsightEditorHooks);
    destructor Destroy; override;
    /// <summary>Vervollständigung der Sitzung (Schnipsel, Neue Datei), beim ersten Aufruf angelegt.</summary>
    function Completion: TAtlasEditorCompletion;
    /// <summary>Parameter-Hint, beim ersten Aufruf angelegt.</summary>
    function Signature: TAtlasEditorSignature;
    /// <summary>Ist die Liste der Vervollständigung offen (#671)?</summary>
    function CompletionVisible: Boolean;
    /// <summary>Läuft der Platzhalter-Modus einer Vorlage (#589)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Vor dem Schließen der Verbindung: laufende Anfragen von Vervollständigung und Parameter-Hint
    /// beenden, Threads der Probleme anhalten.</summary>
    procedure BeginStop;
    /// <summary>Nach dem Schließen der Verbindung: Hover-Anfragen kehren sofort zurück (Code-Review A-07), auf die
    /// Probleme warten.</summary>
    procedure EndStop;
    /// <summary>Vor der Sitzung freigeben: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.</summary>
    procedure ReleaseViews;
    /// <summary>Nach dem Ende der Sitzung: Probleme freigeben.</summary>
    procedure ReleaseProblems;
  end;

implementation

uses
  Atlas.Core.Problems.Contract;

constructor TAtlasCodeInsightEditors.Create(const AHooks: TAtlasCodeInsightEditorHooks);
begin
  inherited Create;
  FHooks := AHooks;
  CreateProblems;
  CreateHover;
  CreateLenses;
end;

destructor TAtlasCodeInsightEditors.Destroy;
begin
  ReleaseViews;
  ReleaseProblems;
  inherited;
end;

procedure TAtlasCodeInsightEditors.CreateProblems;
var
  mEnsure: TFunc<Boolean>;
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
begin
  mEnsure := FHooks.EnsureSession;
  mRunning := FHooks.RunningSession;
  mDiagnose := FHooks.Diagnose;
  FProblems := TAtlasProblemsController.Create(
    function(AStart: Boolean): TLspSession
    begin
      // Start nur im Hauptthread (Probleme-Takt); EnsureSession kehrt sonst sofort zurück (A-01).
      if AStart then
      begin
        mEnsure();
      end;
      Result := mRunning();
    end,
    procedure(const AMessage: string)
    begin
      mDiagnose(AMessage);
    end);
end;

procedure TAtlasCodeInsightEditors.CreateHover;
var
  mEnsure: TFunc<Boolean>;
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
  mHandles: TFunc<string, Boolean>;
begin
  mEnsure := FHooks.EnsureSession;
  mRunning := FHooks.RunningSession;
  mDiagnose := FHooks.Diagnose;
  mHandles := FHooks.Handles;
  FHover := TAtlasEditorHover.Create(
    function: TLspSession
    begin
      Result := nil;
      if mEnsure() then
      begin
        Result := mRunning();
      end;
    end,
    procedure(const AMessage: string)
    begin
      mDiagnose(AMessage);
    end,
    function(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>
    begin
      Result := nil;
      if FProblems <> nil then
      begin
        Result := FProblems.ProblemsAt(AFileName, ALine, ACharacter);
      end;
    end,
    function(const AFileName: string): Boolean
    begin
      Result := mHandles(AFileName);
    end);
end;

procedure TAtlasCodeInsightEditors.CreateLenses;
var
  mReady: TFunc<TLspSession>;
begin
  mReady := FHooks.ReadySession;
  // Code Lens und Metriken fragen den Server im Hintergrund; der Hauptthread gibt nur den Textstand weiter.
  // Startet keinen Server: Inlay-Hints kommen erst, wenn er ohnehin läuft.
  FInlayHints := TAtlasEditorInlayHints.Create(
    function: TLspSession
    begin
      Result := mReady();
    end);
  // Code Lens zur Testunit (#189); startet ebenfalls keinen Server.
  FTestUnitLens := TAtlasEditorTestUnitLens.Create(
    function: TLspSession
    begin
      Result := mReady();
    end, FHooks.RunCommandAsync);
  // Code-Metriken für Statusleiste und die Lens im Modul Analyse (#66, #1756); startet ebenfalls keinen Server.
  FMetricsSource := TAtlasEditorMetricsSource.Create(
    function: TLspSession
    begin
      Result := mReady();
    end, FHooks.RunCommandAsync);
end;

function TAtlasCodeInsightEditors.Signature: TAtlasEditorSignature;
var
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
begin
  if FSignature = nil then
  begin
    mRunning := FHooks.RunningSession;
    mDiagnose := FHooks.Diagnose;
    FSignature := TAtlasEditorSignature.Create(
      FHooks.NewSignatureSource(
        function: TLspSession
        begin
          // Im Hauptthread beim Öffnen des Hints: nur eine laufende Sitzung, nie ein Start (A-01).
          Result := mRunning();
        end),
      function: Boolean
      begin
        Result := CompletionVisible;
      end,
      procedure(const AMessage: string)
      begin
        mDiagnose(AMessage);
      end);
  end;
  Result := FSignature;
end;

function TAtlasCodeInsightEditors.Completion: TAtlasEditorCompletion;
var
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
  mEditView: TFunc<IOTAEditView>;
begin
  if FCompletion = nil then
  begin
    mRunning := FHooks.RunningSession;
    mDiagnose := FHooks.Diagnose;
    mEditView := FHooks.EditView;
    FCompletion := TAtlasEditorCompletion.Create(
      function: TLspSession
      begin
        // Aufgerufen im Zeitlimit-Arbeiter (#493): nur eine laufende Sitzung, nie ein Start (A-01).
        Result := mRunning();
      end,
      procedure(const AMessage: string)
      begin
        mDiagnose(AMessage);
      end,
      FHooks.NewCompletionSources);
    // Nach "Add(|)" den Parameter-Hint öffnen (#430).
    FCompletion.OnOpenSignature :=
      procedure
      begin
        Signature.Invoke(mEditView());
      end;
  end;
  Result := FCompletion;
end;

function TAtlasCodeInsightEditors.CompletionVisible: Boolean;
begin
  Result := (FCompletion <> nil) and FCompletion.Visible;
end;

function TAtlasCodeInsightEditors.PlaceholdersActive: Boolean;
begin
  Result := (FCompletion <> nil) and FCompletion.PlaceholdersActive;
end;

procedure TAtlasCodeInsightEditors.BeginStop;
begin
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch.
  if FCompletion <> nil then
  begin
    FCompletion.Shutdown;
  end;
  if FSignature <> nil then
  begin
    FSignature.Shutdown;
  end;
  // Probleme: Threads anhalten, Verbindung schließen (laufende Anfragen kehren sofort zurück), warten.
  if FProblems <> nil then
  begin
    FProblems.BeginShutdown;
  end;
end;

procedure TAtlasCodeInsightEditors.EndStop;
begin
  // Hover-Anfragen halten die Sitzung als rohen Zeiger; nach Close kehren sie sofort zurück (Code-Review A-07).
  if FHover <> nil then
  begin
    FHover.Shutdown;
  end;
  if FProblems <> nil then
  begin
    FProblems.WaitShutdown;
  end;
end;

procedure TAtlasCodeInsightEditors.ReleaseViews;
begin
  FreeAndNil(FInlayHints);
  FreeAndNil(FTestUnitLens);
  FreeAndNil(FMetricsSource);
  FreeAndNil(FHover);
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
end;

procedure TAtlasCodeInsightEditors.ReleaseProblems;
begin
  FreeAndNil(FProblems);
end;

end.
