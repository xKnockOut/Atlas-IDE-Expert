unit Argus.IDE.CodeInsight.Manager;

// Code Insight-Manager für Delphi in RAD Studio (ADR 0006). Die IDE ruft ihn
// direkt auf; er fragt Argus über eine eigene LSP-Sitzung.
// Umgesetzt: Symbolhinweis (Hover, GetHintText), Browse (Strg+Klick,
// GotoDefinition) und Vervollständigung im eigenen Popup (#410): Strg+Leer und
// "." lösen sie aus, InvokeCodeCompletion öffnet das Popup und meldet der IDE
// False, damit sie keine eigene Liste zeigt (#407). Parameterhilfe ebenso im eigenen
// Hint (#436): "(", "," und Strg+Umschalt+Leer, InvokeParameterCodeInsight meldet False.
//
// Server: Pfad und Argumente aus HKCU\Software\Argus\IdePlugin
// (ServerPath, ServerArguments), ersatzweise aus dem früheren Schlüssel
// HKCU\Software\BetterDelphiLSP\IdePlugin (#403). Ohne Eintrag: ArgusServer.exe neben dem
// Plugin, sonst ..\..\..\Win64\Debug\Bin\ (Ausgabeordner des Repos).
// Diagnose = 1 (DWORD) im selben Schlüssel protokolliert die Aufrufe der IDE
// in Argus.IDE.Expert.log neben dem Plugin.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Argus.Core.Lsp.Adapters.ServerProcess,
  Argus.Core.Lsp.Session,
  Argus.IDE.Completion.Editor,
  Argus.IDE.Signature.Editor;

type
  TArgusCodeInsightManager = class(TInterfacedObject, IOTACodeInsightManager, IOTACodeInsightSelection)
  private
    FEnabled: Boolean;
    FServer: TLspServerProcess;
    FSession: TLspSession;
    FLastError: string;
    FDiagnose: Boolean;
    FCompletion: TArgusEditorCompletion;
    FSignature: TArgusEditorSignature;
    function EnsureSession: Boolean;
    procedure StopSession;
    procedure ReportError(const AMessage: string);
    procedure Diagnose(const AMessage: string);
    function CurrentEditView: IOTAEditView;
    /// <summary>Cursorzeile ist ein ///-Kommentar (XMLDoc, #435).</summary>
    function InXmlDocLine: Boolean;
    function Completion: TArgusEditorCompletion;
    function Signature: TArgusEditorSignature;
    function SessionOrNil: TLspSession;
    class function ServerPath(out AArguments: string): string; static;
    class function DiagnoseEnabled: Boolean; static;
    class function DiagnoseLog: string; static;
  public
    constructor Create;
    destructor Destroy; override;
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
    function GotoDefinition(out AFileName: string; out ALineNum: Integer; Index: Integer = -1): Boolean;
    procedure Done(Accepted: Boolean; out DisplayParams: Boolean);
    { IOTACodeInsightManager }
    function GetOptionSetName: string;
    { IOTACodeInsightSelection }
    function GetDisplayName: string;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Win.Registry,
  Argus.IDE.Settings.Store,
  Winapi.Windows,
  Argus.IDE.Editor.Buffer;

const
  RegistryKey = 'Software\Argus\IdePlugin';
  // Schlüssel vor der Umbenennung in Argus (#403), wird nur noch gelesen.
  LegacyRegistryKey = 'Software\BetterDelphiLSP\IdePlugin';
  // Unterscheidet sich vom gleichnamigen benutzerdefinierten LSP-Eintrag.
  ManagerName = 'Argus IDE Expert';
  ManagerId = 'Argus.CodeInsight';

/// <summary>Öffnet den Schlüssel der Einstellungen, ersatzweise den früheren; liefert den
/// geöffneten Schlüssel oder ''.</summary>
function OpenSettingsKey(ARegistry: TRegistry): string;
begin
  ARegistry.RootKey := HKEY_CURRENT_USER;
  if ARegistry.OpenKeyReadOnly(RegistryKey) then
    Result := RegistryKey
  else if ARegistry.OpenKeyReadOnly(LegacyRegistryKey) then
    Result := LegacyRegistryKey
  else
    Result := '';
end;

{ TArgusCodeInsightManager }

constructor TArgusCodeInsightManager.Create;
begin
  inherited Create;
  FEnabled := True;
  FDiagnose := DiagnoseEnabled;
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
end;

destructor TArgusCodeInsightManager.Destroy;
begin
  // Vor der Sitzung: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
  StopSession;
  inherited;
end;

class function TArgusCodeInsightManager.DiagnoseEnabled: Boolean;
var
  Registry: TRegistry;
begin
  // Diagnose = 1 (DWORD): Aufrufe der IDE und Ergebnisse in DiagnoseLog.
  Result := False;
  Registry := TRegistry.Create(KEY_READ);
  try
    if (OpenSettingsKey(Registry) <> '') and Registry.ValueExists('Diagnose') and
      (Registry.GetDataType('Diagnose') = rdInteger) then
      Result := Registry.ReadInteger('Diagnose') <> 0;
  finally
    Registry.Free;
  end;
end;

class function TArgusCodeInsightManager.DiagnoseLog: string;
begin
  // Neben dem Plugin, nicht im Temp-Ordner: Den hat die IDE nicht in jedem Fall gemeinsam mit uns.
  Result := ChangeFileExt(GetModuleName(HInstance), '.log');
end;

class function TArgusCodeInsightManager.ServerPath(out AArguments: string): string;
var
  Registry: TRegistry;
  PluginDir: string;
  Key: string;
begin
  Result := '';
  AArguments := '';
  Registry := TRegistry.Create(KEY_READ);
  try
    Key := OpenSettingsKey(Registry);
    if Key <> '' then
    begin
      if Registry.ValueExists('ServerPath') then
        Result := Registry.ReadString('ServerPath');
      if Registry.ValueExists('ServerArguments') then
        AArguments := Registry.ReadString('ServerArguments');
    end;
  finally
    Registry.Free;
  end;
  // Der alte Schlüssel zeigt meist noch auf BetterDelphiLSP.exe; fehlt sie, gelten die Vorgaben.
  if (Key = LegacyRegistryKey) and (Result <> '') and not FileExists(Result) then
    Result := '';
  if Result <> '' then
    Exit;
  PluginDir := ExtractFilePath(GetModuleName(HInstance));
  Result := PluginDir + 'ArgusServer.exe';
  if not FileExists(Result) then
    Result := ExpandFileName(PluginDir + '..\..\..\Win64\Debug\Bin\ArgusServer.exe');
end;

procedure TArgusCodeInsightManager.ReportError(const AMessage: string);
var
  Messages: IOTAMessageServices;
begin
  Diagnose('Fehler: ' + AMessage);
  // Jede Meldung nur einmal, sonst flutet ein fehlender Server das Meldungsfenster.
  if AMessage = FLastError then
    Exit;
  FLastError := AMessage;
  if Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.AddTitleMessage('Argus: ' + AMessage);
end;

procedure TArgusCodeInsightManager.Diagnose(const AMessage: string);
begin
  if not FDiagnose then
    Exit;
  try
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AMessage + sLineBreak,
      TEncoding.UTF8);
  except
    // Diagnose darf die IDE nie stören.
  end;
end;

procedure TArgusCodeInsightManager.StopSession;
begin
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch.
  if FCompletion <> nil then
    FCompletion.Shutdown;
  if FSignature <> nil then
    FSignature.Shutdown;
  FreeAndNil(FSession);
  FreeAndNil(FServer);
end;

function TArgusCodeInsightManager.EnsureSession: Boolean;
var
  Path, Arguments: string;
begin
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
    Exit(True);
  StopSession;
  Path := ServerPath(Arguments);
  Diagnose('Starte Server: ' + Path);
  if not FileExists(Path) then
  begin
    ReportError('Server nicht gefunden: ' + Path);
    Exit(False);
  end;
  try
    FServer := TLspServerProcess.Create(Path, Arguments);
    FSession := TLspSession.Create(FServer.Client);
    FSession.Initialize;
    FLastError := '';
    Result := True;
  except
    on E: Exception do
    begin
      ReportError('Start fehlgeschlagen: ' + E.Message);
      StopSession;
      Result := False;
    end;
  end;
end;

function TArgusCodeInsightManager.CurrentEditView: IOTAEditView;
var
  Services: IOTACodeInsightServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.GetEditView(Result);
  if Result = nil then
    Result := (BorlandIDEServices as IOTAEditorServices).TopView;
end;

function TArgusCodeInsightManager.SessionOrNil: TLspSession;
begin
  if EnsureSession then
    Result := FSession
  else
    Result := nil;
end;

function TArgusCodeInsightManager.Signature: TArgusEditorSignature;
begin
  if FSignature = nil then
    FSignature := TArgusEditorSignature.Create(
      function: TLspSession
      begin
        Result := SessionOrNil;
      end,
      function: Boolean
      begin
        Result := (FCompletion <> nil) and FCompletion.Visible;
      end,
      procedure(const AMessage: string)
      begin
        Diagnose(AMessage);
      end);
  Result := FSignature;
end;

function TArgusCodeInsightManager.Completion: TArgusEditorCompletion;
begin
  if FCompletion = nil then
  begin
    FCompletion := TArgusEditorCompletion.Create(
      function: TLspSession
      begin
        Result := SessionOrNil;
      end,
      procedure(const AMessage: string)
      begin
        Diagnose(AMessage);
      end);
    // Nach "Add(|)" den Parameter-Hint öffnen (#430).
    FCompletion.OnOpenSignature :=
      procedure
      begin
        Signature.Invoke(CurrentEditView);
      end;
  end;
  Result := FCompletion;
end;

function TArgusCodeInsightManager.GetHintText(HintLine, HintCol: Integer): string;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
begin
  Result := '';
  Diagnose(Format('GetHintText(%d, %d) aufgerufen', [HintLine, HintCol]));
  try
    View := CurrentEditView;
    if (View = nil) or (View.Buffer = nil) or not EnsureSession then
      Exit;
    Text := TArgusEditorBuffer.Text(View.Buffer);
    Lines := Text.Split([#13#10, #10]);
    if (HintLine < 1) or (HintLine > Length(Lines)) then
      Exit;
    Result := FSession.Hover(View.Buffer.FileName, Text, HintLine - 1,
      TLspSession.ColumnToIndex(Lines[HintLine - 1], HintCol, TArgusEditorBuffer.TabWidth(View.Buffer)));
    Diagnose(Format('Hover in %s, Zeile %d, Spalte %d (Cursor %d/%d): %s', [ExtractFileName(View.Buffer.FileName),
      HintLine, HintCol, View.CursorPos.Line, View.CursorPos.Col, IfThen(Result = '', 'leer', Result)]));
  except
    on E: Exception do
    begin
      ReportError('Hover: ' + E.Message);
      Result := '';
    end;
  end;
end;

function TArgusCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer;
  Index: Integer): Boolean;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  Character: Integer;
  Location: TLspLocation;
begin
  // Laut ToolsAPI: AFileName = '' und ALineNum = 0 bricht ohne Meldung ab.
  // Mit False meldet die IDE „Datei "" nicht gefunden“; deshalb True.
  AFileName := '';
  ALineNum := 0;
  Result := True;
  Diagnose(Format('GotoDefinition(Index %d) aufgerufen', [Index]));
  try
    View := CurrentEditView;
    if (View = nil) or (View.Buffer = nil) then
    begin
      Diagnose('Gehe zu Definition: keine Editoransicht');
      Exit;
    end;
    if not EnsureSession then
      Exit;
    Text := TArgusEditorBuffer.Text(View.Buffer);
    Lines := Text.Split([#13#10, #10]);
    // Die synchrone Schnittstelle übergibt keine Klickposition; maßgeblich ist der Cursor.
    Cursor := View.CursorPos;
    if (Cursor.Line < 1) or (Cursor.Line > Length(Lines)) then
    begin
      Diagnose(Format('Gehe zu Definition: Cursorzeile %d außerhalb des Puffers (%d Zeilen)',
        [Cursor.Line, Length(Lines)]));
      Exit;
    end;
    Character := TLspSession.ColumnToIndex(Lines[Cursor.Line - 1], Cursor.Col, TArgusEditorBuffer.TabWidth(View.Buffer));
    if FSession.Definition(View.Buffer.FileName, Text, Cursor.Line - 1, Character, Location) then
    begin
      AFileName := Location.FileName;
      ALineNum := Location.Line + 1;
    end;
    Diagnose(Format('Gehe zu Definition (Index %d) in %s, Zeile %d, Spalte %d (Zeichen %d): %s',
      [Index, ExtractFileName(View.Buffer.FileName), Cursor.Line, Cursor.Col, Character,
       IfThen(AFileName <> '', Format('%s, Zeile %d', [AFileName, ALineNum]), 'keine Definition')]));
  except
    on E: Exception do
    begin
      ReportError('Gehe zu Definition: ' + E.Message);
      AFileName := '';
      ALineNum := 0;
    end;
  end;
end;

function TArgusCodeInsightManager.GetName: string;
begin
  Result := ManagerName;
end;

function TArgusCodeInsightManager.GetIDString: string;
begin
  Result := ManagerId;
end;

function TArgusCodeInsightManager.GetDisplayName: string;
begin
  Result := ManagerName;
end;

function TArgusCodeInsightManager.GetOptionSetName: string;
begin
  // Dieselben Editoreinstellungen wie der eingebaute Delphi-Manager.
  Result := 'Borland.EditOptions.Pascal';
end;

function TArgusCodeInsightManager.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TArgusCodeInsightManager.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
  Diagnose('SetEnabled(' + BoolToStr(Value, True) + ')');
  if not Value then
    StopSession;
end;

function TArgusCodeInsightManager.EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
begin
  Result := ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'];
  if PreValidating then
    Include(Result, '.');
end;

procedure TArgusCodeInsightManager.AllowCodeInsight(var Allow: Boolean; const Key: Char);
begin
  // #0 Vervollständigung (Strg+Leer), "." Vervollständigung nach Punkt, #2 Browse
  // (Strg+Klick), #3 Symbolhinweis; #1 Parameterhilfe (Strg+Umschalt+Leer), "(" und ",".
  // "<" nur für XMLDoc-Tags in ///-Kommentaren (#435), siehe GetCodeInsightType.
  Allow := CharInSet(Key, [#0, '.', #1, '(', ',', #2, #3, '<']);
  Diagnose(Format('AllowCodeInsight(#%d) = %s', [Ord(Key), BoolToStr(Allow, True)]));
end;

function TArgusCodeInsightManager.PreValidateCodeInsight(const Str: string): Boolean;
begin
  Result := True;
end;

function TArgusCodeInsightManager.IsViewerBrowsable(Index: Integer): Boolean;
begin
  Result := False;
end;

function TArgusCodeInsightManager.GetMultiSelect: Boolean;
begin
  Result := False;
end;

procedure TArgusCodeInsightManager.GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
begin
  SymbolList := nil;
end;

procedure TArgusCodeInsightManager.OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
begin
  CloseViewer := True;
  Accept := False;
end;

function TArgusCodeInsightManager.HandlesFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  // Hauptschalter (#407): ausgeschaltet übernimmt die eingebaute Code Insight.
  Result := TArgusIdeSettings.Current.Enabled and ((Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc'));
  Diagnose(Format('HandlesFile(%s) = %s', [AFileName, BoolToStr(Result, True)]));
end;

function TArgusCodeInsightManager.GetLongestItem: string;
begin
  Result := 'constructor';
end;

procedure TArgusCodeInsightManager.GetParameterList(out ParameterList: IOTACodeInsightParameterList);
begin
  ParameterList := nil;
end;

function TArgusCodeInsightManager.InXmlDocLine: Boolean;
var
  View: IOTAEditView;
begin
  View := CurrentEditView;
  Result := (View <> nil) and (View.Buffer <> nil) and
    TrimLeft(TArgusEditorBuffer.LineText(View, View.CursorPos.Line)).StartsWith('///');
end;

procedure TArgusCodeInsightManager.GetCodeInsightType(AChar: Char; AElement: Integer;
  out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
begin
  InvokeType := itManual;
  case AChar of
    #0: CodeInsightType := citCodeInsight;
    '.':
      begin
        // Nach der in den Editoroptionen eingestellten Verzögerung.
        CodeInsightType := citCodeInsight;
        InvokeType := itTimer;
      end;
    #1: CodeInsightType := citParameterCodeInsight;
    '(', ',':
      begin
        CodeInsightType := citParameterCodeInsight;
        InvokeType := itTimer;
      end;
    '<':
      begin
        CodeInsightType := citCodeInsight;
        InvokeType := itTimer;
      end;
    #2: CodeInsightType := citBrowseCodeInsight;
    #3: CodeInsightType := citHintCodeInsight;
  else
    CodeInsightType := citNone;
  end;
  // In Kommentaren und Strings keine Vervollständigung (#435); Ausnahme: XMLDoc-Tags in ///-Zeilen.
  // "<" außerhalb davon ist ein Vergleich, keine Auslösung.
  if (CodeInsightType = citCodeInsight) and ((AChar = '<') or (AElement = atComment)) and InXmlDocLine then
    // Vervollständigung bleibt; die XMLDoc-Quelle liefert die Tags.
  else if (AChar = '<') or ((CodeInsightType in [citCodeInsight, citParameterCodeInsight]) and
    ((AElement = atComment) or (AElement = atString))) then
    CodeInsightType := citNone;
  Diagnose(Format('GetCodeInsightType(#%d, Element %d) = %d', [Ord(AChar), AElement, Ord(CodeInsightType)]));
end;

function TArgusCodeInsightManager.InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
begin
  // False: Die IDE zeigt keine eigene Liste; unser Popup übernimmt (#407, #410).
  Result := False;
  Diagnose(Format('InvokeCodeCompletion(%d, "%s")', [Ord(HowInvoked), Str]));
  try
    Completion.Invoke(CurrentEditView);
  except
    on E: Exception do
      ReportError('Vervollständigung: ' + E.Message);
  end;
end;

function TArgusCodeInsightManager.InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType;
  var SelectedIndex: Integer): Boolean;
begin
  // False: Die IDE zeigt keine eigene Parameterhilfe; unser Hint übernimmt (#436).
  Result := False;
  Diagnose(Format('InvokeParameterCodeInsight(%d)', [Ord(HowInvoked)]));
  try
    Signature.Invoke(CurrentEditView);
  except
    on E: Exception do
      ReportError('Parameterhilfe: ' + E.Message);
  end;
end;

procedure TArgusCodeInsightManager.ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
begin
end;

function TArgusCodeInsightManager.ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
begin
  Result := -1;
end;

procedure TArgusCodeInsightManager.Done(Accepted: Boolean; out DisplayParams: Boolean);
begin
  DisplayParams := False;
end;

end.
