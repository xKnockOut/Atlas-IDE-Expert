unit Shell.Composition.Completion;

// Internals-Rolle Shell: Vervollständigung im Editor und in den Debug-Dialogen (#538) samt der Rückfragen, die nur
// sie stellt: Abgleich, Postfix-Vorlagen (#188), with auflösen (#50) und Methode aus Aufruf anlegen (#472). Die
// Komposition reicht Dokumente, Index, Quelltext und die Einstellungen der Arbeitsbereiche als Dienste herein.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.Refactorings,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.Completion.Hooks,
  Atlas.Common.Lsp.ExpressionCompletion;

type
  TShellCompletionRefactoringFunc = reference to function(const AUri: string): TRefactoringSettings;
  TShellLanguageLevelFunc = reference to function(const AUri: string): string;
  TShellRefactoringContextFunc = reference to function(const AUri: string): TRefactoringContext;

  /// <summary>Typen aus der IDE (atlas/ideTypes); derselbe Typ wie in den Hooks, nur ohne deren Unit.</summary>
  TShellCompletionIdeTypesFunc = TCompletionIdeTypesFunc;

  /// <summary>Was die Vervollständigung von der Komposition braucht.</summary>
  TShellCompletionServices = record
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    ReadText: TCompletionReadText;
    /// <summary>Abschnitt für Interface-Methoden (#466), Typumwandlung von Sender (#480), Abgleich.</summary>
    CompletionSettingsFor: TCompletionSettingsFunc;
    RefactoringSettingsFor: TShellCompletionRefactoringFunc;
    LanguageLevelFor: TShellLanguageLevelFunc;
    /// <summary>Kontext der Refactorings für with auflösen und Methode anlegen.</summary>
    RefactoringContextFor: TShellRefactoringContextFunc;
    SlashCommandsFor: TSlashCommandsProvider;
    RuleIdsFor: TSlashRuleIdsFunc;
    /// <summary>Präfix der Namensvorschläge (#452).</summary>
    NamingFor: TCompletionNamingFunc;
    /// <summary>Für completionItem/resolve (Detailpanel von Atlas, #405); Anzeige von XMLDoc (#654).</summary>
    HintsFor: TDocHintsProvider;
    /// <summary>„Parameter abgleichen“ in ///-Blöcken (#88) hängt an completeBlocks.docComment.</summary>
    DocCommentsFor: TCompletionEnabledFunc;
    /// <summary>Bedingte Symbole in {$IFDEF } und Co. (#102).</summary>
    SymbolsFor: TConditionalContextFunc;
    /// <summary>Teilergebnisse (#616) als $/progress.</summary>
    Notify: TCompletionNotifyProc;
    /// <summary>Zeiten je Anfrage im Debug-Protokoll.</summary>
    Log: TCompletionLogProc;
    /// <summary>Typen aus den Packages der IDE (atlas/ideTypes).</summary>
    IdeTypesFor: TCompletionIdeTypesFunc;
  end;

  /// <summary>Vervollständigung im Editor und in den Debug-Dialogen.</summary>
  TShellCompletion = class
  private
    FServices: TShellCompletionServices;
    FCompletion: TLspCompletion;
    FExpressionCompletion: TLspExpressionCompletion;
    function MatchingFor(const AUri: string): TCompletionMatching;
    function PostfixOptionsFor(const AUri: string): TPostfixOptions;
    function WithEdits(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean;
    function CreateMethod(ARequest: TCompletionRequest; out ATitle, ADetail: string;
      out AEdits: TArray<TTextEdit>): Boolean;
    procedure WireCallbacks;
  public
    constructor Create(const AServices: TShellCompletionServices);
    destructor Destroy; override;
    /// <summary>Anfragen der Vervollständigung am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Vervollständigung im Editor; das Erzeugen-Menü (#719) und die Fähigkeiten des Clients greifen zu.
    /// </summary>
    property Completion: TLspCompletion read FCompletion;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Pascal.LanguageFeatures;

constructor TShellCompletion.Create(const AServices: TShellCompletionServices);
begin
  inherited Create;
  FServices := AServices;
  FCompletion := TLspCompletion.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
  WireCallbacks;
  // Ausdrücke in den Debug-Dialogen (#538) mit denselben Einträgen wie im Editor.
  FExpressionCompletion := TLspExpressionCompletion.Create(FServices.Documents, FCompletion);
end;

procedure TShellCompletion.WireCallbacks;
begin
  FCompletion.Hooks.MatchingFor := MatchingFor;
  FCompletion.Hooks.SettingsFor := FServices.CompletionSettingsFor;
  FCompletion.Hooks.SlashCommandsFor := FServices.SlashCommandsFor;
  FCompletion.Hooks.RuleIdsFor := FServices.RuleIdsFor;
  FCompletion.Hooks.PostfixFor := PostfixOptionsFor;
  // with auflösen über Strg+Leer auf with (#50), abschaltbar mit refactoring.resolveWith.
  FCompletion.Hooks.WithFor := WithEdits;
  // Methode aus Aufruf anlegen nach "(" bzw. mit Strg+Leer (#472), abschaltbar mit refactoring.createMethod.
  FCompletion.Hooks.CreateFor := CreateMethod;
  FCompletion.Hooks.NamingFor := FServices.NamingFor;
  FCompletion.Hooks.IdeTypesFor := FServices.IdeTypesFor;
  FCompletion.Hooks.HintsFor := FServices.HintsFor;
  FCompletion.Hooks.DocCommentsFor := FServices.DocCommentsFor;
  FCompletion.Hooks.SymbolsFor := FServices.SymbolsFor;
  FCompletion.Hooks.ReadText := FServices.ReadText;
  FCompletion.Hooks.Notify := FServices.Notify;
  FCompletion.Hooks.Log := FServices.Log;
end;

destructor TShellCompletion.Destroy;
begin
  FreeAndNil(FExpressionCompletion);
  FreeAndNil(FCompletion);
  inherited Destroy;
end;

procedure TShellCompletion.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FCompletion.Attach(ADispatcher);
  FExpressionCompletion.Attach(ADispatcher);
end;

function TShellCompletion.MatchingFor(const AUri: string): TCompletionMatching;
begin
  Result := FServices.CompletionSettingsFor(AUri).Matching;
end;

function TShellCompletion.PostfixOptionsFor(const AUri: string): TPostfixOptions;
begin
  // Postfix-Vorlagen (#188): abschaltbar mit completion.postfixTemplates; for var und var Name := nur, wenn die
  // Sprachversion Inline-Variablen kennt und refactoring.inlineVar sie nicht abschaltet.
  Result := TPostfixOptions.Default;
  Result.Enabled := FServices.CompletionSettingsFor(AUri).PostfixTemplates;
  Result.InlineVar := FServices.RefactoringSettingsFor(AUri).InlineVar and
    TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, FServices.LanguageLevelFor(AUri));
end;

function TShellCompletion.WithEdits(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean;
var
  mContext: TRefactoringContext;
  mAction: TCodeAction;
begin
  AEdits := nil;
  mContext := FServices.RefactoringContextFor(ARequest.Uri);
  mContext.CaretMarker := True;
  Result := mContext.Settings.ResolveWith and TLspRefactorings.WithAction(ARequest.Resolver, ARequest.Tree,
    ARequest.Text, ARequest.Position, mContext, mAction);
  if Result then
  begin
    AEdits := mAction.Edits;
  end;
end;

function TShellCompletion.CreateMethod(ARequest: TCompletionRequest; out ATitle, ADetail: string;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mContext: TRefactoringContext;
  mCreated: TCreatedMethod;
begin
  ATitle := '';
  ADetail := '';
  AEdits := nil;
  mContext := FServices.RefactoringContextFor(ARequest.Uri);
  // Nur Änderungen in dieser Datei; die Klasse in einer anderen Unit bekommt die Code-Aktion.
  Result := mContext.Settings.CreateMethod and TLspRefactorings.CreateMethod(ARequest.Resolver, ARequest.Tree,
    ARequest.Text, ARequest.Position, mContext, mCreated) and (mCreated.FileEdits = nil);
  if Result then
  begin
    ATitle := mCreated.Title;
    ADetail := mCreated.Detail;
    AEdits := mCreated.Edits;
  end;
end;

end.
