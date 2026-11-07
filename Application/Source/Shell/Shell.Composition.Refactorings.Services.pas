unit Shell.Composition.Refactorings.Services;

// Internals-Rolle Shell: Was die Refactorings des Servers von der Komposition brauchen, und die gemeinsame Basis
// ihrer Teile. Jeder Teil meldet seine Befehle selbst an und liefert seine Code-Aktionen; die Prüfung der
// Argumente, der Einstellung und des geöffneten Dokuments steht hier einmal.

interface

uses
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Refactorings;

type
  /// <summary>Liste von Namen, z. B. Dateien des Projekts oder Namensräume.</summary>
  TShellNamesFunc = reference to function: TArray<string>;
  TShellRefactoringSettingsFunc = reference to function(const AUri: string): TRefactoringSettings;
  TShellFormatStyleFunc = reference to function(const AUri: string): TFormatStyle;
  /// <summary>Text zu einer Datei, z. B. Sprachversion oder Delphi-Version.</summary>
  TShellUriTextFunc = reference to function(const AUri: string): string;
  TShellCompilerMessagesFunc = reference to function(const AFileName: string): TArray<TCompilerMessage>;
  TShellProjectFunc = reference to function(const AFileName: string; out AProject: TProjectInfo): Boolean;
  TShellNewNamesFunc = reference to function(const AUri: string): TPascalNamePrefixes;
  TShellMissingUnitSetupFunc = reference to function(const AFileName, AUnitName: string;
    out ASetup: TMissingUnitSetup): Boolean;

  /// <summary>Was die Refactorings vom Server brauchen; die Arbeitsbereiche bleiben in der Komposition.</summary>
  TShellRefactoringServices = record
    Logger: ILogger;
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TShellNamesFunc;
    ProjectFiles: TShellNamesFunc;
    ReadText: TReferenceReadText;
    SettingsFor: TShellRefactoringSettingsFunc;
    FormatStyleFor: TShellFormatStyleFunc;
    LanguageLevelFor: TShellUriTextFunc;
    DelphiVersionFor: TShellUriTextFunc;
    /// <summary>uses-Umfeld einer Datei; False ohne Projekt.</summary>
    UsesContextFor: TUsesContextProvider;
    /// <summary>Meldungen des letzten Compilerlaufs zu einer Datei.</summary>
    MessagesFor: TShellCompilerMessagesFunc;
    /// <summary>Projekt des Arbeitsbereichs einer Datei.</summary>
    ProjectFor: TShellProjectFunc;
    NewNamesFor: TShellNewNamesFunc;
    MissingUnitSetupFor: TShellMissingUnitSetupFunc;
    /// <summary>classCompletion.typeComment der Datei (#1838).</summary>
    TypeCommentFor: TShellUriTextFunc;
  end;

  /// <summary>Basis der Teile: Zugriff auf die Dienste und die Prüfungen, die jeder Befehl braucht.</summary>
  TShellRefactoringPart = class
  private
    FServices: TShellRefactoringServices;
  protected
    function Settings(const AUri: string): TRefactoringSettings;
    /// <summary>Typkommentare mitnehmen (#1838): classCompletion.typeComment nicht off.</summary>
    function TypeComments(const AUri: string): Boolean;
    /// <summary>Code-Aktion: eingeschaltet, Datei geöffnet und eine .pas-Datei.</summary>
    function TryOpen(const AUri: string; AEnabled: Boolean; out ADocument: ITextDocument): Boolean; overload;
    /// <summary>Wie TryOpen für die Endungen AExtensions.</summary>
    function TryOpen(const AUri: string; AEnabled: Boolean; const AExtensions: array of string;
      out ADocument: ITextDocument): Boolean; overload;
    /// <summary>Befehl: das geöffnete Dokument, sonst EJsonRpcError.</summary>
    function Open(const AUri: string): ITextDocument; overload;
    /// <summary>Befehl: eingeschaltet (sonst EJsonRpcError mit ADisabled) und das geöffnete Dokument.</summary>
    function Open(const AUri: string; AEnabled: Boolean; const ADisabled: string): ITextDocument; overload;
    /// <summary>Namensauflösung mit den Namensräumen des Projekts; der Aufrufer gibt sie frei.</summary>
    function NewResolver: TNameResolver;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Die Datei liegt auf der Platte oder ist im Editor geöffnet.</summary>
    function SourceExists(const AFileName: string): Boolean;
    function ProjectFiles: TArray<string>;
    function FormatStyle(const AUri: string): TFormatStyle;
    function LanguageLevel(const AUri: string): string;
    function DelphiVersion(const AUri: string): string;
    function UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
    function Messages(const AFileName: string): TArray<TCompilerMessage>;
    function Project(const AFileName: string; out AProject: TProjectInfo): Boolean;
    /// <summary>Nur Zahlen ins Log, keine Namen und Pfade (#647).</summary>
    procedure Log(const AText: string);
    /// <summary>EJsonRpcError (RequestFailed) mit ADisabled, wenn AEnabled nicht gilt.</summary>
    class procedure Allow(AEnabled: Boolean; const ADisabled: string); static;
    /// <summary>EJsonRpcError (InvalidParams) mit AMissing, wenn weniger als ACount Argumente da sind.</summary>
    class procedure Require(const AArguments: TJSONArray; ACount: Integer; const AMissing: string); overload; static;
    /// <summary>Wie oben für die Argumente ANames (je eins); die Meldung nennt sie in der Sprache der Texte.</summary>
    class procedure Require(const AArguments: TJSONArray; const ANames: array of string); overload; static;
    /// <summary>Meldung für Allow und Open: Befehl AName ist über die Einstellung ASetting abgeschaltet.</summary>
    class function Disabled(const AName, ASetting: string): string; static;
    /// <summary>Zahl im Feld AName der Antwort.</summary>
    class function Number(const AAnswer: TJSONObject; const AName: string): Integer; static;
    /// <summary>Länge der Liste im Feld AName der Antwort.</summary>
    class function Count(const AAnswer: TJSONObject; const AName: string): Integer; static;
    /// <summary>Zeilenumbruch des Textes: CRLF, wenn er eins enthält, sonst LF.</summary>
    class function LineBreakOf(const AText: string): string; static;
    /// <summary>Lesen einer Datei (offenes Dokument vor der Platte) für die Kontexte der Refactorings.</summary>
    property Reader: TReferenceReadText read FServices.ReadText;
    /// <summary>uses-Umfeld einer Datei; als Wert für Kontexte (geerbte Methoden als Methodenreferenz bringen Free
    /// Pascal zum Absturz).</summary>
    property UsesProvider: TUsesContextProvider read FServices.UsesContextFor;
    property SetupProvider: TShellMissingUnitSetupFunc read FServices.MissingUnitSetupFor;
    property Index: ISymbolIndex read FServices.Index;
    property Documents: IDocumentStore read FServices.Documents;
  public
    constructor Create(const AServices: TShellRefactoringServices);
    /// <summary>Meldet die Befehle des Teils an.</summary>
    procedure Register(ACommands: TLspCommands); virtual; abstract;
    /// <summary>Code-Aktionen des Teils für den Bereich.</summary>
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; virtual; abstract;
    /// <summary>Umfeld der Refactorings aus Atlas.Common.Lsp.Refactorings für eine Datei.</summary>
    function ContextFor(const AUri: string): TRefactoringContext;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.LanguageFeatures,
  System.Generics.Collections,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TRefactoringServiceText = (NotOpen, Disabled);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TRefactoringServiceText] of TAtlasText = (
    (De: 'Die Datei ist nicht geöffnet.'; En: 'The file is not open.'),
    (De: '"%s" ist abgeschaltet (%s).'; En: '"%s" is turned off (%s).'));

constructor TShellRefactoringPart.Create(const AServices: TShellRefactoringServices);
begin
  inherited Create;
  FServices := AServices;
end;

function TShellRefactoringPart.Settings(const AUri: string): TRefactoringSettings;
begin
  Result := FServices.SettingsFor(AUri);
end;

function TShellRefactoringPart.TypeComments(const AUri: string): Boolean;
begin
  Result := not Assigned(FServices.TypeCommentFor) or not SameText(FServices.TypeCommentFor(AUri), 'off');
end;

function TShellRefactoringPart.TryOpen(const AUri: string; AEnabled: Boolean; out ADocument: ITextDocument): Boolean;
begin
  Result := TryOpen(AUri, AEnabled, ['.pas'], ADocument);
end;

function TShellRefactoringPart.TryOpen(const AUri: string; AEnabled: Boolean; const AExtensions: array of string;
  out ADocument: ITextDocument): Boolean;
begin
  ADocument := nil;
  Result := AEnabled and MatchText(ExtractFileExt(TDocumentUris.ToPath(AUri)), AExtensions) and
    FServices.Documents.TryGet(AUri, ADocument);
end;

function TShellRefactoringPart.Open(const AUri: string): ITextDocument;
begin
  if not FServices.Documents.TryGet(AUri, Result) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed, cTexts[TRefactoringServiceText.NotOpen].Text);
  end;
end;

function TShellRefactoringPart.Open(const AUri: string; AEnabled: Boolean; const ADisabled: string): ITextDocument;
begin
  Allow(AEnabled, ADisabled);
  Result := Open(AUri);
end;

function TShellRefactoringPart.NewResolver: TNameResolver;
begin
  Result := TNameResolver.Create(FServices.Index, FServices.EnsureUnit);
  Result.Namespaces := FServices.Namespaces();
end;

function TShellRefactoringPart.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

function TShellRefactoringPart.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FServices.EnsureUnit(AUnitName);
end;

function TShellRefactoringPart.SourceExists(const AFileName: string): Boolean;
var
  mOpen: ITextDocument;
begin
  Result := FileExists(AFileName) or FServices.Documents.TryGet(TDocumentUris.FromPath(AFileName), mOpen);
end;

function TShellRefactoringPart.ProjectFiles: TArray<string>;
begin
  Result := FServices.ProjectFiles();
end;

function TShellRefactoringPart.FormatStyle(const AUri: string): TFormatStyle;
begin
  Result := FServices.FormatStyleFor(AUri);
end;

function TShellRefactoringPart.LanguageLevel(const AUri: string): string;
begin
  Result := FServices.LanguageLevelFor(AUri);
end;

function TShellRefactoringPart.DelphiVersion(const AUri: string): string;
begin
  Result := FServices.DelphiVersionFor(AUri);
end;

function TShellRefactoringPart.UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  Result := FServices.UsesContextFor(AUri, AContext);
  if not Result then
  begin
    AContext := Default(TUsesContext);
  end;
end;

function TShellRefactoringPart.Messages(const AFileName: string): TArray<TCompilerMessage>;
begin
  Result := FServices.MessagesFor(AFileName);
end;

function TShellRefactoringPart.Project(const AFileName: string; out AProject: TProjectInfo): Boolean;
begin
  Result := FServices.ProjectFor(AFileName, AProject);
end;

procedure TShellRefactoringPart.Log(const AText: string);
begin
  FServices.Logger.Info(AText);
end;

class procedure TShellRefactoringPart.Allow(AEnabled: Boolean; const ADisabled: string);
begin
  if not AEnabled then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed, ADisabled);
  end;
end;

class procedure TShellRefactoringPart.Require(const AArguments: TJSONArray; ACount: Integer; const AMissing: string);
begin
  if (AArguments = nil) or (AArguments.Count < ACount) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, AMissing);
  end;
end;

class procedure TShellRefactoringPart.Require(const AArguments: TJSONArray; const ANames: array of string);
begin
  if (AArguments = nil) or (AArguments.Count < Length(ANames)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, TShellTexts.Missing(ANames));
  end;
end;

class function TShellRefactoringPart.Disabled(const AName, ASetting: string): string;
begin
  Result := cTexts[TRefactoringServiceText.Disabled].Fmt([AName, ASetting]);
end;

class function TShellRefactoringPart.Number(const AAnswer: TJSONObject; const AName: string): Integer;
begin
  Result := (AAnswer.GetValue(AName) as TJSONNumber).AsInt;
end;

class function TShellRefactoringPart.Count(const AAnswer: TJSONObject; const AName: string): Integer;
begin
  Result := (AAnswer.GetValue(AName) as TJSONArray).Count;
end;

class function TShellRefactoringPart.LineBreakOf(const AText: string): string;
begin
  Result := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    Result := #13#10;
  end;
end;

function TShellRefactoringPart.ContextFor(const AUri: string): TRefactoringContext;
var
  mLevel: string;
begin
  mLevel := LanguageLevel(AUri);
  Result := Default(TRefactoringContext);
  Result.Settings := Settings(AUri);
  Result.Index := FServices.Index;
  Result.EnsureUnit := EnsureUnit;
  Result.Namespaces := FServices.Namespaces();
  Result.FileName := TDocumentUris.ToPath(AUri);
  Result.ReadText := ReadText;
  Result.InlineVar := Result.Settings.InlineVar and
    TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, mLevel);
  Result.IfExpression := TLanguageFeatures.IsAvailable(TLanguageFeature.IfExpression, mLevel);
  Result.Style := FormatStyle(AUri);
  Result.NewNames := FServices.NewNamesFor(AUri);
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Refactorings.Services', cTexts);

end.
