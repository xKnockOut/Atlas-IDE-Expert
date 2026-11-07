unit Atlas.IDE.CodeInsight.Manager;

// Code Insight-Manager für Delphi in RAD Studio (ADR 0006). Die IDE ruft ihn direkt auf; er fragt Atlas über eine
// eigene LSP-Sitzung. Umgesetzt: Symbolhinweis (Hover, GetHintText), Browse (Strg+Klick, GotoDefinition), Help
// Insight (leer, solange der Atlas-Tooltip an ist) und Vervollständigung im eigenen Popup (#410): Strg+Leer und "."
// lösen sie aus, InvokeCodeCompletion öffnet das Popup und meldet der IDE False, damit sie keine eigene Liste zeigt
// (#407). Parameterhilfe ebenso im eigenen Hint (#436): "(", "," und Strg+Umschalt+Leer, InvokeParameterCodeInsight
// meldet False.
// Oberste Stufe der Klassenkette State (Zustand, Protokoll) → Session (Start, Stopp, Projekte) → Commands (Befehle
// im Hintergrund) → Crashes (Abstürze, Bericht H5, #1355) → Manager (Open Tools API). Serverprozess,
// Ordnerbeobachter und die Quellen von Vervollständigung und Parameter-Hint aus dem Kern setzt die
// Kompositionswurzel ein (TAtlasCodeInsightAdapters, A-09).

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.CodeInsight.Manager.State,
  Atlas.IDE.CodeInsight.Manager.Editors,
  Atlas.IDE.CodeInsight.Manager.Crashes;

type
  TAtlasCodeInsightManager = class(TAtlasCodeInsightCrashes, IOTACodeInsightManager, IOTACodeInsightManager90,
    IOTACodeInsightSelection)
  private
    /// <summary>Haken der Editor-Anbindungen an diesen Manager.</summary>
    function EditorHooks: TAtlasCodeInsightEditorHooks;
    /// <summary>Zeigt Atlas den Tooltip selbst (Hauptschalter und Tooltip an)?</summary>
    class function OwnTooltip: Boolean; static;
  public
    constructor Create(const AAdapters: TAtlasCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Alles abbauen, was im Code des Plugins weiterliefe: Editor-Anbindungen, Sitzung, Server und
    /// Hintergrund-Threads (#886). Mehrfach aufrufbar, nur im Hauptthread. Danach meldet der Manager sich als
    /// ausgeschaltet. Die Kompositionswurzel ruft es beim Abmelden, weil die IDE den Manager nach
    /// RemoveCodeInsightManager noch halten kann (etwa mitten im Gruppen-Build); Destroy liefe dann
    /// erst später.</summary>
    procedure Shutdown;
    /// <summary>Vervollständigung der Sitzung (Schnipsel, Neue Datei); beim ersten Aufruf angelegt.</summary>
    function Completion: TAtlasEditorCompletion;
    /// <summary>Ist die Liste der Vervollständigung offen (#671)?</summary>
    function CompletionVisible: Boolean;
    /// <summary>Läuft der Platzhalter-Modus einer Vorlage (#589: dann keine Mehrfachmarken)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Vervollständigung bzw. Parameter-Hint über eine eigene Taste von Atlas öffnen (#494).</summary>
    procedure OpenCompletion;
    procedure OpenSignature;
    /// <summary>Bietet IOTACodeInsightManager90 (Help Insight) nur an, solange der Atlas-Tooltip an ist.</summary>
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    { IOTACodeInsightManager100 }
    function GetName: string;
    function GetIDString: string;
    function GetEnabled: Boolean;
    procedure SetEnabled(Value: Boolean);
    function EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
    procedure AllowCodeInsight(var Allow: Boolean; const Key: Char);
    function PreValidateCodeInsight(const Str: string): Boolean;
    function IsViewerBrowsable(Index: Integer): Boolean;
    function GetMultiSelect: Boolean;
    procedure GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
    procedure OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
    function HandlesFile(const AFileName: string): Boolean;
    function GetLongestItem: string;
    procedure GetParameterList(out ParameterList: IOTACodeInsightParameterList);
    procedure GetCodeInsightType(AChar: Char; AElement: Integer; out CodeInsightType: TOTACodeInsightType;
      out InvokeType: TOTAInvokeType);
    function InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
    function InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; var SelectedIndex: Integer): Boolean;
    procedure ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
    function ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
    function GetHintText(HintLine, HintCol: Integer): string;
    function GotoDefinition(out AFileName: string; out ALineNum: Integer; Index: Integer): Boolean; overload;
    function GotoDefinition(out AFileName: string; out ALineNum: Integer): Boolean; overload;
    procedure Done(Accepted: Boolean; out DisplayParams: Boolean);
    { IOTACodeInsightManager }
    function GetOptionSetName: string;
    { IOTACodeInsightManager90 }
    function GetHelpInsightHtml: WideString;
    { IOTACodeInsightSelection }
    function GetDisplayName: string;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.CodeInsight.Manager.Queries,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TManagerText = (Completion);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TManagerText] of string = (
    ('Vervollständigung: '),
    ('Completion: '));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TManagerText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  // Unterscheidet sich vom gleichnamigen benutzerdefinierten LSP-Eintrag.
  cManagerName = 'Atlas IDE Expert';
  cManagerId = 'Atlas.CodeInsight';

/// <summary>Fehler eines Einstiegspunkts an die Sicherung (#493, Code-Review S-05); ein beendeter Server oder sein
/// Zeitlimit (ELspClientError) ist erwartbar und zählt nicht.</summary>
procedure ReportFailure(AFeature: TAtlasFeature; AE: Exception);
begin
  if not (AE is ELspClientError) then
  begin
    TAtlasGuard.Report(AFeature, AE);
  end;
end;

{ TAtlasCodeInsightManager }

constructor TAtlasCodeInsightManager.Create(const AAdapters: TAtlasCodeInsightAdapters);
begin
  inherited Create(AAdapters);
  // Gemeinsamer Pufferstand für Probleme und Inlay-Hints (P-04).
  TAtlasEditorSnapshots.Install;
  FEditors := TAtlasCodeInsightEditors.Create(EditorHooks);
end;

destructor TAtlasCodeInsightManager.Destroy;
begin
  Shutdown;
  FreeAndNil(FEditors);
  inherited;
end;

function TAtlasCodeInsightManager.EditorHooks: TAtlasCodeInsightEditorHooks;
begin
  Result := Default(TAtlasCodeInsightEditorHooks);
  Result.EnsureSession :=
    function: Boolean
    begin
      Result := EnsureSession;
    end;
  Result.RunningSession :=
    function: TLspSession
    begin
      Result := RunningSession;
    end;
  Result.ReadySession :=
    function: TLspSession
    begin
      Result := ReadySession;
    end;
  Result.RunCommandAsync :=
    procedure(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<TJSONValue>)
    begin
      RunServerCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
    end;
  Result.Diagnose :=
    procedure(AMessage: string)
    begin
      Diagnose(AMessage);
    end;
  Result.Handles :=
    function(AFileName: string): Boolean
    begin
      Result := Handles(AFileName);
    end;
  Result.EditView :=
    function: IOTAEditView
    begin
      Result := TAtlasCodeInsightQueries.CurrentEditView;
    end;
  Result.NewCompletionSources := FAdapters.NewCompletionSources;
  Result.NewSignatureSource := FAdapters.NewSignatureSource;
  Result.OpenCodeActions := FAdapters.OpenCodeActions;
end;

procedure TAtlasCodeInsightManager.Shutdown;
begin
  if FShutDown then
  begin
    Exit;
  end;
  FShutDown := True;
  FEnabled := False;
  RetireManager(Self);
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg.
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Vor der Sitzung: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.
  if FEditors <> nil then
  begin
    FEditors.ReleaseViews;
  end;
  FOnServerChanged := nil;
  StopSession;
  // Nach StopSession: Die Threads sind dort schon angehalten.
  if FEditors <> nil then
  begin
    FEditors.ReleaseProblems;
  end;
  // Nach beiden Verbrauchern.
  TAtlasEditorSnapshots.Uninstall;
  // Die Threads geben sich nicht selbst frei: Erst wenn sie beendet sind, läuft nichts mehr im Code des Plugins,
  // auch nicht das Freigeben ihrer anonymen Methode (#886). Sie nutzen bis zuletzt die Ereignisse aus Destroy.
  if not FThreads.StopAll(TAtlasShutdown.cStopMs) then
  begin
    Diagnose('Manager abgebaut, während ein Hintergrund-Thread noch lief');
  end;
end;

function TAtlasCodeInsightManager.Completion: TAtlasEditorCompletion;
begin
  Result := FEditors.Completion;
end;

function TAtlasCodeInsightManager.CompletionVisible: Boolean;
begin
  Result := FEditors.CompletionVisible;
end;

function TAtlasCodeInsightManager.PlaceholdersActive: Boolean;
begin
  Result := FEditors.PlaceholdersActive;
end;

function TAtlasCodeInsightManager.GetHintText(HintLine, HintCol: Integer): string;
var
  mView: IOTAEditView;
  mActivity: IInterface;
begin
  mActivity := TAtlasActivity.Scope('Symbolhinweis');
  Result := '';
  // Durch die Sicherung abgeschaltet (#493, Code-Review S-05); eigener Tooltip (#442): die IDE zeigt keinen
  // zweiten.
  if TAtlasGuard.Disabled(TAtlasFeature.Hover) then
  begin
    Exit;
  end;
  Diagnose(Format('GetHintText(%d, %d) aufgerufen', [HintLine, HintCol]));
  if TAtlasIdeSettings.Current.HoverTooltip then
  begin
    Exit;
  end;
  try
    mView := TAtlasCodeInsightQueries.CurrentEditView;
    if (mView <> nil) and (mView.Buffer <> nil) and EnsureSession then
    begin
      Result := TAtlasCodeInsightQueries.HintAt(FSession, mView, HintLine, HintCol,
        procedure(AMessage: string)
        begin
          Diagnose(AMessage);
        end);
    end;
  except
    on E: Exception do
    begin
      ReportError('Hover: ' + E.Message);
      ReportFailure(TAtlasFeature.Hover, E);
      Result := '';
    end;
  end;
end;

function TAtlasCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer): Boolean;
begin
  Result := GotoDefinition(AFileName, ALineNum, -1);
end;

function TAtlasCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer;
  Index: Integer): Boolean;
var
  mView: IOTAEditView;
  mActivity: IInterface;
begin
  mActivity := TAtlasActivity.Scope('Gehe zu Definition');
  // Laut ToolsAPI: AFileName = '' und ALineNum = 0 bricht ohne Meldung ab. Mit False meldet die IDE „Datei ""
  // nicht gefunden“; deshalb True.
  AFileName := '';
  ALineNum := 0;
  Result := True;
  // Durch die Sicherung abgeschaltet (#493, Code-Review S-05); AFileName = '' bricht still ab.
  if TAtlasGuard.Disabled(TAtlasFeature.GoToDefinition) then
  begin
    Exit;
  end;
  Diagnose(Format('GotoDefinition(Index %d) aufgerufen', [Index]));
  try
    mView := TAtlasCodeInsightQueries.CurrentEditView;
    if (mView = nil) or (mView.Buffer = nil) then
    begin
      Diagnose('Gehe zu Definition: keine Editoransicht');
    end
    else if EnsureSession then
    begin
      TAtlasCodeInsightQueries.DefinitionAt(FSession, mView, Index,
        procedure(AMessage: string)
        begin
          Diagnose(AMessage);
        end, AFileName, ALineNum);
    end;
  except
    on E: Exception do
    begin
      ReportError('Gehe zu Definition: ' + E.Message);
      ReportFailure(TAtlasFeature.GoToDefinition, E);
      AFileName := '';
      ALineNum := 0;
    end;
  end;
end;

function TAtlasCodeInsightManager.GetName: string;
begin
  Result := cManagerName;
end;

function TAtlasCodeInsightManager.GetIDString: string;
begin
  Result := cManagerId;
end;

function TAtlasCodeInsightManager.GetDisplayName: string;
begin
  Result := cManagerName;
end;

function TAtlasCodeInsightManager.GetOptionSetName: string;
begin
  // Dieselben Editoreinstellungen wie der eingebaute Delphi-Manager.
  Result := 'Borland.EditOptions.Pascal';
end;

class function TAtlasCodeInsightManager.OwnTooltip: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.HoverTooltip;
end;

function TAtlasCodeInsightManager.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  // Ohne IOTACodeInsightManager90 holt sich die IDE Help Insight anderswo (DelphiLSP) und zeigt es neben dem
  // Atlas-Tooltip. Mit dem Atlas-Tooltip aus bleibt es beim Verhalten der IDE.
  if IsEqualGUID(IID, IOTACodeInsightManager90) and not OwnTooltip then
  begin
    Pointer(Obj) := nil;
    Exit(E_NOINTERFACE);
  end;
  Result := inherited QueryInterface(IID, Obj);
end;

function TAtlasCodeInsightManager.GetHelpInsightHtml: WideString;
begin
  // Der Atlas-Tooltip zeigt alles; die IDE soll keinen zweiten Tooltip öffnen.
  Result := '';
  Diagnose('GetHelpInsightHtml aufgerufen');
end;

function TAtlasCodeInsightManager.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TAtlasCodeInsightManager.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
  Diagnose('SetEnabled(' + BoolToStr(Value, True) + ')');
  if not Value then
  begin
    StopSession;
  end;
end;

function TAtlasCodeInsightManager.EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
begin
  Result := ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'];
  if PreValidating then
  begin
    Include(Result, '.');
  end;
end;

procedure TAtlasCodeInsightManager.AllowCodeInsight(var Allow: Boolean; const Key: Char);
begin
  Allow := False;
  try
    // #0 Vervollständigung (Strg+Leer), "." Vervollständigung nach Punkt, #2 Browse
    // (Strg+Klick), #3 Symbolhinweis; #1 Parameterhilfe (Strg+Umschalt+Leer), "(" und ",".
    // "<" nur für XMLDoc-Tags in ///-Kommentaren (#435), siehe GetCodeInsightType. "[" für Mengen (#448): Der
    // Server liefert nur in einem Mengenkonstruktor etwas, sonst bleibt das Popup zu.
    Allow := CharInSet(Key, [#0, '.', #1, '(', ',', #2, #3, '<', '[']);
    Diagnose(Format('AllowCodeInsight(#%d) = %s', [Ord(Key), BoolToStr(Allow, True)]));
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

function TAtlasCodeInsightManager.PreValidateCodeInsight(const Str: string): Boolean;
begin
  Result := True;
end;

function TAtlasCodeInsightManager.IsViewerBrowsable(Index: Integer): Boolean;
begin
  Result := False;
end;

function TAtlasCodeInsightManager.GetMultiSelect: Boolean;
begin
  Result := False;
end;

procedure TAtlasCodeInsightManager.GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
begin
  SymbolList := nil;
end;

procedure TAtlasCodeInsightManager.OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
begin
  try
    CloseViewer := True;
    Accept := False;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

function TAtlasCodeInsightManager.HandlesFile(const AFileName: string): Boolean;
begin
  Result := False;
  try
    Result := Handles(AFileName);
    Diagnose(Format('HandlesFile(%s) = %s', [ExtractFileExt(AFileName), BoolToStr(Result, True)]));
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

function TAtlasCodeInsightManager.GetLongestItem: string;
begin
  Result := 'constructor';
end;

procedure TAtlasCodeInsightManager.GetParameterList(out ParameterList: IOTACodeInsightParameterList);
begin
  ParameterList := nil;
end;

procedure TAtlasCodeInsightManager.GetCodeInsightType(AChar: Char; AElement: Integer;
  out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
begin
  CodeInsightType := citNone;
  InvokeType := itManual;
  try
    CodeInsightType := TAtlasCodeInsightQueries.InsightType(AChar, AElement,
      function: Boolean
      begin
        // Nach dem ";" hinter einem übernommenen Konstruktor „Mit try…finally absichern“ (#489).
        Result := Completion.GuardPending(TAtlasCodeInsightQueries.CurrentEditView);
      end, InvokeType);
    Diagnose(Format('GetCodeInsightType(#%d, Element %d) = %d', [Ord(AChar), AElement, Ord(CodeInsightType)]));
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

function TAtlasCodeInsightManager.InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
var
  mActivity: IInterface;
begin
  mActivity := TAtlasActivity.Scope('Vervollständigung öffnen');
  // False: Die IDE zeigt keine eigene Liste; unser Popup übernimmt (#407, #410).
  Result := False;
  Diagnose(Format('InvokeCodeCompletion(%d, %d Zeichen)', [Ord(HowInvoked), Length(Str)]));
  try
    // Start nur hier im Hauptthread (A-01); die Quellen bekommen danach die laufende Sitzung.
    // Ohne Server liefern die übrigen Quellen trotzdem.
    EnsureSession;
    Completion.Invoke(TAtlasCodeInsightQueries.CurrentEditView, HowInvoked <> itManual);
  except
    on E: Exception do
    begin
      ReportError(UiText(TManagerText.Completion) + E.Message);
      ReportFailure(TAtlasFeature.Completion, E);
    end;
  end;
end;

function TAtlasCodeInsightManager.InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType;
  var SelectedIndex: Integer): Boolean;
var
  mActivity: IInterface;
begin
  // False: Die IDE zeigt keine eigene Parameterhilfe; unser Hint übernimmt (#436).
  Result := False;
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Signature) then
  begin
    Exit;
  end;
  mActivity := TAtlasActivity.Scope('Parameterhilfe');
  Diagnose(Format('InvokeParameterCodeInsight(%d)', [Ord(HowInvoked)]));
  try
    // Start nur hier im Hauptthread (A-01).
    EnsureSession;
    FEditors.Signature.Invoke(TAtlasCodeInsightQueries.CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TAtlasFeature.Signature, E);
    end;
  end;
end;

procedure TAtlasCodeInsightManager.OpenCompletion;
begin
  if not FEnabled or TAtlasGuard.Disabled(TAtlasFeature.Completion) or not ServerAvailable then
  begin
    Exit;
  end;
  Diagnose('Vervollständigung über eigene Taste');
  try
    // Start nur hier im Hauptthread (A-01).
    EnsureSession;
    Completion.Invoke(TAtlasCodeInsightQueries.CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError(UiText(TManagerText.Completion) + E.Message);
      ReportFailure(TAtlasFeature.Completion, E);
    end;
  end;
end;

procedure TAtlasCodeInsightManager.OpenSignature;
begin
  if not FEnabled or TAtlasGuard.Disabled(TAtlasFeature.Signature) or not ServerAvailable then
  begin
    Exit;
  end;
  Diagnose('Parameterhilfe über eigene Taste');
  try
    // Start nur hier im Hauptthread (A-01).
    EnsureSession;
    FEditors.Signature.Invoke(TAtlasCodeInsightQueries.CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TAtlasFeature.Signature, E);
    end;
  end;
end;

procedure TAtlasCodeInsightManager.ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
begin
end;

function TAtlasCodeInsightManager.ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
begin
  Result := -1;
end;

procedure TAtlasCodeInsightManager.Done(Accepted: Boolean; out DisplayParams: Boolean);
begin
  DisplayParams := False;
  try
    DisplayParams := False;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
    end;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.CodeInsight.Manager', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
