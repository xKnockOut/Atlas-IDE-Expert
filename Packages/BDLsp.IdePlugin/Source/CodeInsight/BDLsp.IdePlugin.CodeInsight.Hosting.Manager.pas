unit BDLsp.IdePlugin.CodeInsight.Hosting.Manager;

// Code Insight-Manager für Delphi in RAD Studio (ADR 0006). Die IDE ruft ihn
// direkt auf; er fragt BetterDelphiLSP über eine eigene LSP-Sitzung.
// Umgesetzt: Symbolhinweis (Hover, GetHintText) und Browse (Strg+Klick,
// GotoDefinition). Vervollständigung und Parameterhilfe folgen.
//
// Server: Pfad und Argumente aus HKCU\Software\BetterDelphiLSP\IdePlugin
// (ServerPath, ServerArguments). Ohne Eintrag: BetterDelphiLSP.exe neben dem
// Plugin, sonst ..\..\..\Win64\Debug\Bin\ (Ausgabeordner des Repos).
// Diagnose = 1 (DWORD) im selben Schlüssel protokolliert die Aufrufe der IDE
// in BDLsp.IdePlugin.log neben dem Plugin.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  BDLsp.IdePlugin.Lsp.Adapters.ServerProcess,
  BDLsp.IdePlugin.Lsp.Session;

type
  TBDLspCodeInsightManager = class(TInterfacedObject, IOTACodeInsightManager, IOTACodeInsightSelection)
  private
    FEnabled: Boolean;
    FServer: TLspServerProcess;
    FSession: TLspSession;
    FLastError: string;
    FDiagnose: Boolean;
    function EnsureSession: Boolean;
    procedure StopSession;
    procedure ReportError(const AMessage: string);
    procedure Diagnose(const AMessage: string);
    function CurrentEditView: IOTAEditView;
    class function BufferText(const ABuffer: IOTAEditBuffer): string; static;
    class function TabWidth(const ABuffer: IOTAEditBuffer): Integer; static;
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
  Winapi.Windows;

const
  RegistryKey = 'Software\BetterDelphiLSP\IdePlugin';
  // Unterscheidet sich vom gleichnamigen benutzerdefinierten LSP-Eintrag.
  ManagerName = 'BetterDelphiLSP (Plugin)';
  ManagerId = 'BetterDelphiLSP.CodeInsight';

{ TBDLspCodeInsightManager }

constructor TBDLspCodeInsightManager.Create;
begin
  inherited Create;
  FEnabled := True;
  FDiagnose := DiagnoseEnabled;
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
end;

destructor TBDLspCodeInsightManager.Destroy;
begin
  StopSession;
  inherited;
end;

class function TBDLspCodeInsightManager.DiagnoseEnabled: Boolean;
var
  Registry: TRegistry;
begin
  // Diagnose = 1 (DWORD): Aufrufe der IDE und Ergebnisse in DiagnoseLog.
  Result := False;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly(RegistryKey) and Registry.ValueExists('Diagnose') and
      (Registry.GetDataType('Diagnose') = rdInteger) then
      Result := Registry.ReadInteger('Diagnose') <> 0;
  finally
    Registry.Free;
  end;
end;

class function TBDLspCodeInsightManager.DiagnoseLog: string;
begin
  // Neben dem Plugin, nicht im Temp-Ordner: Den hat die IDE nicht in jedem Fall gemeinsam mit uns.
  Result := ChangeFileExt(GetModuleName(HInstance), '.log');
end;

class function TBDLspCodeInsightManager.ServerPath(out AArguments: string): string;
var
  Registry: TRegistry;
  PluginDir: string;
begin
  Result := '';
  AArguments := '';
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly(RegistryKey) then
    begin
      if Registry.ValueExists('ServerPath') then
        Result := Registry.ReadString('ServerPath');
      if Registry.ValueExists('ServerArguments') then
        AArguments := Registry.ReadString('ServerArguments');
    end;
  finally
    Registry.Free;
  end;
  if Result <> '' then
    Exit;
  PluginDir := ExtractFilePath(GetModuleName(HInstance));
  Result := PluginDir + 'BetterDelphiLSP.exe';
  if not FileExists(Result) then
    Result := ExpandFileName(PluginDir + '..\..\..\Win64\Debug\Bin\BetterDelphiLSP.exe');
end;

procedure TBDLspCodeInsightManager.ReportError(const AMessage: string);
var
  Messages: IOTAMessageServices;
begin
  Diagnose('Fehler: ' + AMessage);
  // Jede Meldung nur einmal, sonst flutet ein fehlender Server das Meldungsfenster.
  if AMessage = FLastError then
    Exit;
  FLastError := AMessage;
  if Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.AddTitleMessage('BetterDelphiLSP: ' + AMessage);
end;

procedure TBDLspCodeInsightManager.Diagnose(const AMessage: string);
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

procedure TBDLspCodeInsightManager.StopSession;
begin
  FreeAndNil(FSession);
  FreeAndNil(FServer);
end;

function TBDLspCodeInsightManager.EnsureSession: Boolean;
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

function TBDLspCodeInsightManager.CurrentEditView: IOTAEditView;
var
  Services: IOTACodeInsightServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.GetEditView(Result);
  if Result = nil then
    Result := (BorlandIDEServices as IOTAEditorServices).TopView;
end;

class function TBDLspCodeInsightManager.BufferText(const ABuffer: IOTAEditBuffer): string;
const
  ChunkSize = 65536;
var
  Reader: IOTAEditReader;
  Chunk: AnsiString;
  Bytes: TBytes;
  Position, Count: Integer;
begin
  Reader := ABuffer.CreateReader;
  Position := 0;
  repeat
    SetLength(Chunk, ChunkSize);
    Count := Reader.GetText(Position, PAnsiChar(Chunk), ChunkSize);
    if Count > 0 then
    begin
      SetLength(Bytes, Length(Bytes) + Count);
      Move(Chunk[1], Bytes[Length(Bytes) - Count], Count);
      Inc(Position, Count);
    end;
  until Count < ChunkSize;
  // Der Editorpuffer ist UTF-8.
  Result := TEncoding.UTF8.GetString(Bytes);
end;

class function TBDLspCodeInsightManager.TabWidth(const ABuffer: IOTAEditBuffer): Integer;
var
  Stops: string;
begin
  Result := 8;
  if ABuffer.BufferOptions <> nil then
  begin
    Stops := Trim(ABuffer.BufferOptions.TabStops);
    if Stops <> '' then
      Result := StrToIntDef(Stops.Split([' '])[0], 8);
    if Result < 1 then
      Result := 8;
  end;
end;

function TBDLspCodeInsightManager.GetHintText(HintLine, HintCol: Integer): string;
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
    Text := BufferText(View.Buffer);
    Lines := Text.Split([#13#10, #10]);
    if (HintLine < 1) or (HintLine > Length(Lines)) then
      Exit;
    Result := FSession.Hover(View.Buffer.FileName, Text, HintLine - 1,
      TLspSession.ColumnToIndex(Lines[HintLine - 1], HintCol, TabWidth(View.Buffer)));
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

function TBDLspCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer;
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
    Text := BufferText(View.Buffer);
    Lines := Text.Split([#13#10, #10]);
    // Die synchrone Schnittstelle übergibt keine Klickposition; maßgeblich ist der Cursor.
    Cursor := View.CursorPos;
    if (Cursor.Line < 1) or (Cursor.Line > Length(Lines)) then
    begin
      Diagnose(Format('Gehe zu Definition: Cursorzeile %d außerhalb des Puffers (%d Zeilen)',
        [Cursor.Line, Length(Lines)]));
      Exit;
    end;
    Character := TLspSession.ColumnToIndex(Lines[Cursor.Line - 1], Cursor.Col, TabWidth(View.Buffer));
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

function TBDLspCodeInsightManager.GetName: string;
begin
  Result := ManagerName;
end;

function TBDLspCodeInsightManager.GetIDString: string;
begin
  Result := ManagerId;
end;

function TBDLspCodeInsightManager.GetDisplayName: string;
begin
  Result := ManagerName;
end;

function TBDLspCodeInsightManager.GetOptionSetName: string;
begin
  // Dieselben Editoreinstellungen wie der eingebaute Delphi-Manager.
  Result := 'Borland.EditOptions.Pascal';
end;

function TBDLspCodeInsightManager.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TBDLspCodeInsightManager.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
  Diagnose('SetEnabled(' + BoolToStr(Value, True) + ')');
  if not Value then
    StopSession;
end;

function TBDLspCodeInsightManager.EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
begin
  Result := ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'];
  if PreValidating then
    Include(Result, '.');
end;

procedure TBDLspCodeInsightManager.AllowCodeInsight(var Allow: Boolean; const Key: Char);
begin
  // #2 Browse (Strg+Klick), #3 Symbolhinweis; Vervollständigung (#0) und
  // Parameterhilfe (#1) folgen.
  Allow := CharInSet(Key, [#2, #3]);
  Diagnose(Format('AllowCodeInsight(#%d) = %s', [Ord(Key), BoolToStr(Allow, True)]));
end;

function TBDLspCodeInsightManager.PreValidateCodeInsight(const Str: string): Boolean;
begin
  Result := True;
end;

function TBDLspCodeInsightManager.IsViewerBrowsable(Index: Integer): Boolean;
begin
  Result := False;
end;

function TBDLspCodeInsightManager.GetMultiSelect: Boolean;
begin
  Result := False;
end;

procedure TBDLspCodeInsightManager.GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
begin
  SymbolList := nil;
end;

procedure TBDLspCodeInsightManager.OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
begin
  CloseViewer := True;
  Accept := False;
end;

function TBDLspCodeInsightManager.HandlesFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc');
  Diagnose(Format('HandlesFile(%s) = %s', [AFileName, BoolToStr(Result, True)]));
end;

function TBDLspCodeInsightManager.GetLongestItem: string;
begin
  Result := 'constructor';
end;

procedure TBDLspCodeInsightManager.GetParameterList(out ParameterList: IOTACodeInsightParameterList);
begin
  ParameterList := nil;
end;

procedure TBDLspCodeInsightManager.GetCodeInsightType(AChar: Char; AElement: Integer;
  out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
begin
  InvokeType := itManual;
  case AChar of
    #2: CodeInsightType := citBrowseCodeInsight;
    #3: CodeInsightType := citHintCodeInsight;
  else
    CodeInsightType := citNone;
  end;
  Diagnose(Format('GetCodeInsightType(#%d, Element %d) = %d', [Ord(AChar), AElement, Ord(CodeInsightType)]));
end;

function TBDLspCodeInsightManager.InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
begin
  Result := False;
end;

function TBDLspCodeInsightManager.InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType;
  var SelectedIndex: Integer): Boolean;
begin
  Result := False;
end;

procedure TBDLspCodeInsightManager.ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
begin
end;

function TBDLspCodeInsightManager.ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
begin
  Result := -1;
end;

procedure TBDLspCodeInsightManager.Done(Accepted: Boolean; out DisplayParams: Boolean);
begin
  DisplayParams := False;
end;

end.
