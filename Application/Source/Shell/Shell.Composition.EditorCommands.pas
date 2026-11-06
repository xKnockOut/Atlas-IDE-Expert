unit Shell.Composition.EditorCommands;

// Internals-Rolle Shell: Befehle des Plugins am Editor. Austrittspunkte (#698), neu zugewiesene Variablen (#712),
// Typ des markierten Ausdrucks (#689), Methodenrümpfe in Deklarationsreihenfolge (#660), Überschreibungen (#768),
// qualifizierte Namen, Aufzählungswerte, resourcestring (#473), Zeichenkettenliterale und die Einrückung beim Tippen
// (#1827). Die Komposition reicht Dokumente, Index, Quelltext, Namensräume und Einstellungen als Dienste herein.

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.DocumentHighlights,
  Atlas.Common.Lsp.ResourceStringCommands,
  Atlas.Common.Lsp.SmartIndent,
  Atlas.Common.Lsp.MethodOrder;

type
  TShellEditorReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  TShellNamespacesFunc = reference to function: TArray<string>;
  TShellStringLiteralFunc = reference to function(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;

  /// <summary>Was die Befehle am Editor von der Komposition brauchen.</summary>
  TShellEditorCommandServices = record
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    ReadText: TShellEditorReadText;
    /// <summary>Namensräume des Projekts, wie die Navigation sie zuletzt bekam.</summary>
    Namespaces: TShellNamespacesFunc;
    HighlightSettingsFor: THighlightSettingsProvider;
    StringLiteralFor: TShellStringLiteralFunc;
    /// <summary>Schreibt einen resourcestring in eine andere Unit (#473); über den Host der Schnellbefehle.</summary>
    ResourceStringWrite: TResourceStringWrite;
    /// <summary>Einrückung beim Tippen (#1827) je Datei.</summary>
    SmartIndentFor: TSmartIndentOptionsFunc;
    /// <summary>Einstellungen zum Ordnen der Methodenrümpfe (#1834) je Datei.</summary>
    MethodOrderFor: TMethodOrderOptionsFunc;
  end;

  /// <summary>Befehle des Plugins am Editor.</summary>
  TShellEditorCommands = class
  private
    FServices: TShellEditorCommandServices;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function RunExitPoints(const AArguments: TJSONArray): TJSONValue;
    function RunReassigned(const AArguments: TJSONArray): TJSONValue;
    function RunExpressionType(const AArguments: TJSONArray): TJSONValue;
    function RunMethodOrder(const AArguments: TJSONArray): TJSONValue;
    function RunOverrideMarks(const AArguments: TJSONArray): TJSONValue;
    function RunQualifiedNames(const AArguments: TJSONArray): TJSONValue;
    function RunEnumValue(const AArguments: TJSONArray): TJSONValue;
    function RunAddResourceString(const AArguments: TJSONArray): TJSONValue;
    function RunPlainText(const AArguments: TJSONArray): TJSONValue;
    function RunToLiteral(const AArguments: TJSONArray): TJSONValue;
    function RunSmartIndent(const AArguments: TJSONArray): TJSONValue;
  public
    constructor Create(const AServices: TShellEditorCommandServices);
    /// <summary>Markierungen im Plugin: Austrittspunkte, neu zugewiesene Variablen, Ausdruckstyp,
    /// Methodenreihenfolge, Überschreibungen.</summary>
    procedure RegisterMarkCommands(ACommands: TLspCommands);
    /// <summary>Textbefehle: qualifizierte Namen, Aufzählungswerte, resourcestring, Zeichenkettenliterale,
    /// Einrückung beim Tippen.</summary>
    procedure RegisterTextCommands(ACommands: TLspCommands);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.ExitPoints,
  Atlas.Common.Lsp.Reassigned,
  Atlas.Common.Lsp.ExpressionType,
  Atlas.Common.Lsp.OverrideMarks,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.EnumValueCommands,
  Atlas.Common.Lsp.StringLiteralCommands;

constructor TShellEditorCommands.Create(const AServices: TShellEditorCommandServices);
begin
  inherited Create;
  FServices := AServices;
end;

function TShellEditorCommands.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

procedure TShellEditorCommands.RegisterMarkCommands(ACommands: TLspCommands);
begin
  // Austrittspunkte am Cursor für die Hervorhebung im Plugin (#698).
  ACommands.Register(TLspExitPoints.Command, RunExitPoints);
  // Neu zugewiesene Variablen für die Unterstreichung im Plugin (#712).
  ACommands.Register(TLspReassigned.Command, RunReassigned);
  // Typ des markierten Ausdrucks für das Tastenkürzel im Plugin (#689).
  ACommands.Register(TLspExpressionType.Command, RunExpressionType);
  // Methodenrümpfe in Deklarationsreihenfolge für Befehl und Einfügen im Plugin (#660).
  ACommands.Register(TLspMethodOrder.Command, RunMethodOrder);
  // Überschreibungen für die Atlas-Spalte der Zeilenleiste (#768).
  ACommands.Register(TLspOverrideMarks.Command, RunOverrideMarks);
end;

procedure TShellEditorCommands.RegisterTextCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TQualifiedNames.Command, RunQualifiedNames);
  ACommands.Register(TEnumValueCommands.Command, RunEnumValue);
  ACommands.Register(TResourceStringCommands.AddCommand, RunAddResourceString);
  ACommands.Register(TStringLiteralCommands.PlainTextCommand, RunPlainText);
  ACommands.Register(TStringLiteralCommands.ToLiteralCommand, RunToLiteral);
  ACommands.Register(TLspSmartIndent.Command, RunSmartIndent);
end;

function TShellEditorCommands.RunExitPoints(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspExitPoints.Execute(FServices.Documents, FServices.Index, FServices.EnsureUnit, FServices.Namespaces(),
    TExitPointsReaders.Create(ReadText, FServices.HighlightSettingsFor), AArguments);
end;

function TShellEditorCommands.RunReassigned(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspReassigned.Execute(FServices.Documents, FServices.Index, FServices.EnsureUnit, FServices.Namespaces(),
    AArguments);
end;

function TShellEditorCommands.RunExpressionType(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspExpressionType.Execute(FServices.Documents, FServices.Index, FServices.EnsureUnit,
    FServices.Namespaces(), AArguments);
end;

function TShellEditorCommands.RunMethodOrder(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspMethodOrder.Execute(FServices.Documents, FServices.MethodOrderFor, AArguments);
end;

function TShellEditorCommands.RunOverrideMarks(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspOverrideMarks.Execute(FServices.Documents, FServices.Index, FServices.EnsureUnit,
    FServices.Namespaces(), AArguments);
end;

function TShellEditorCommands.RunQualifiedNames(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TQualifiedNames.Execute(FServices.Documents, FServices.Index, FServices.EnsureUnit, FServices.Namespaces(),
    AArguments);
end;

function TShellEditorCommands.RunEnumValue(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TEnumValueCommands.Execute(FServices.Documents, FServices.Index, FServices.EnsureUnit,
    FServices.Namespaces(), ReadText, AArguments);
end;

function TShellEditorCommands.RunAddResourceString(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TResourceStringCommands.ExecuteAdd(ReadText, FServices.ResourceStringWrite, AArguments);
end;

function TShellEditorCommands.RunPlainText(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TStringLiteralCommands.ExecutePlainText(FServices.Documents, AArguments);
end;

function TShellEditorCommands.RunToLiteral(const AArguments: TJSONArray): TJSONValue;
var
  mSettings: TStringLiteralSettings;
  mMultiline: Boolean;
begin
  mSettings := TStringLiteralSettings.Default;
  mMultiline := False;
  if (AArguments <> nil) and (AArguments.Count > 0) then
  begin
    mSettings := FServices.StringLiteralFor(AArguments.Items[0].Value, mMultiline);
  end;
  Result := TStringLiteralCommands.ExecuteToLiteral(FServices.Documents, mSettings, mMultiline, AArguments);
end;

function TShellEditorCommands.RunSmartIndent(const AArguments: TJSONArray): TJSONValue;
begin
  try
    Result := TLspSmartIndent.Execute(FServices.Documents, FServices.SmartIndentFor, AArguments);
  except
    on E: EArgumentException do
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, E.Message);
  end;
end;

end.
