unit Atlas.Core.Completion.Providers.Server;

// Standardquelle der Vervollständigung (#408): der Atlas-Server über die
// LSP-Sitzung des Plugins (ADR 0006). Prepare gleicht im aufrufenden Thread
// (Zeitlimit-Arbeiter, #493) den Editortext ab (Sync ist threadsicher), Fetch
// fragt textDocument/completion im Hintergrund an
// und übersetzt die LSP-Einträge. Details für das Detailpanel (#405, #424)
// fragt Resolve über completionItem/resolve nach; der Server liefert sie
// strukturiert in data.atlas.
//
// Gestaffelt (#616): Fetch fragt mit partialResultToken; der Server schickt zuerst den eigenen
// Gültigkeitsbereich, dann die Units aus uses, die Antwort bringt den Rest (Importe). Jedes Teilergebnis
// geht sofort ans Popup. Rank zählt über alle Teile fort.
//
// Lebensdauer: Die Sitzung gehört dem Aufrufer. Bevor er sie freigibt (Neustart
// des Servers, Entladen), muss er Shutdown aufrufen; das wartet auf laufende Anfragen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Internals.Async,
  Atlas.Core.Lsp.Session;

type
  /// <summary>Alias für Bestandsnutzer; die Deklaration steht in Atlas.Core.Lsp.Session.</summary>
  TAtlasSessionFunc = Atlas.Core.Lsp.Session.TAtlasSessionFunc;
  /// <summary>Zeile fürs Diagnoselog des Plugins; ohne Namen aus dem Quelltext. Auch aus Hintergrund-Threads.</summary>
  TAtlasProviderLog = reference to procedure(const AMessage: string);

  TAtlasServerCompletionProvider = class(TAtlasAsyncCompletionProvider, IAtlasCompletionResolver)
  public const
    cDefaultTimeoutMs = 2000;
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
  private
    FSession: TAtlasSessionFunc;
    FTimeoutMs: Cardinal;
    FResolveGeneration: Integer;
    FOnLog: TAtlasProviderLog;
    FSnippets: Boolean;
    procedure Log(const AMessage: string);
  protected
    /// <summary>Server weg oder Zeitlimit des Servers zählt nicht als Fehler der Quelle (#393 startet neu).</summary>
    function IsFailure(E: Exception): Boolean; override;
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  public
    constructor Create(const ASession: TAtlasSessionFunc; ATimeoutMs: Cardinal); overload;
    /// <summary>Wie oben mit ATimeoutMs = DefaultTimeoutMs.</summary>
    constructor Create(const ASession: TAtlasSessionFunc); overload;
    /// <summary>LSP-CompletionItemKind → Art des Eintrags.</summary>
    class function KindOf(ALspKind: Integer): TAtlasItemKind; static;
    /// <summary>Ein CompletionItem des LSP; ARank ist seine Stelle in der Antwort.</summary>
    class function ItemFromLsp(AItem: TJSONObject; ARank: Integer): TAtlasCompletionItem; static;
    /// <summary>Antwort auf textDocument/completion: CompletionList, CompletionItem[] oder null.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue; AFirstRank: Integer): TAtlasCompletionItems; overload; static;
    /// <summary>Wie oben mit AFirstRank = 0.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue): TAtlasCompletionItems; overload; static;
    /// <summary>AItems ohne Code-Vorlagen des Servers (Einträge mit Snippet, #51); Postfix-Vorlagen bleiben.</summary>
    class function WithoutSnippets(const AItems: TAtlasCompletionItems): TAtlasCompletionItems; static;
    /// <summary>Hinweis bei unvollständigem Code (#457) aus "syntaxNotice" der CompletionList; Sure ohne.</summary>
    class function SyntaxNoticeOf(AResponse: TJSONValue): TAtlasSyntaxNotice; static;
    /// <summary>AItem ohne Platzhalter: Vorgabetexte eingesetzt, auch in verknüpften Zusatzänderungen.</summary>
    class function Plain(const AItem: TAtlasCompletionItem): TAtlasCompletionItem; static;
    /// <summary>Details aus der Antwort auf completionItem/resolve (data.atlas, sonst detail/documentation).</summary>
    class function DetailsFromLsp(AResponse: TJSONValue): TAtlasItemDetails; static;
    { IAtlasCompletionResolver }
    function Resolve(const AItem: TAtlasCompletionItem; const ACallback: TAtlasDetailsCallback): Boolean;
    /// <summary>Warum die Liste leer bleibt (kein Server, keine Antwort) und wie lange der Server brauchte.</summary>
    property OnLog: TAtlasProviderLog read FOnLog write FOnLog;
    /// <summary>Kontextabhängige Code-Vorlagen des Servers anbieten (#51, completion.snippets); Vorgabe an.</summary>
    property Snippets: Boolean read FSnippets write FSnippets;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Localization.Language,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TServerText = (CompletionServer);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TServerText] of string = (
    ('Vervollständigung (Server)'),
    ('Completion (server)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TServerText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasServerCompletionProvider }

class function TAtlasServerCompletionProvider.ProviderTitle: string;
begin
  Result := UiText(TServerText.CompletionServer);
end;

constructor TAtlasServerCompletionProvider.Create(const ASession: TAtlasSessionFunc);
begin
  Create(ASession, cDefaultTimeoutMs);
end;

constructor TAtlasServerCompletionProvider.Create(const ASession: TAtlasSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  Name := ProviderTitle;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
  FSnippets := True;
end;

function TAtlasServerCompletionProvider.IsFailure(E: Exception): Boolean;
begin
  Result := inherited IsFailure(E) and not (E is ELspClientError);
end;

class function TAtlasServerCompletionProvider.KindOf(ALspKind: Integer): TAtlasItemKind;
const
  // Index: CompletionItemKind des LSP; nicht abgebildete Arten bleiben Unknown.
  cLspKinds: array[0..25] of TAtlasItemKind = (
    TAtlasItemKind.Unknown, // 0
    TAtlasItemKind.Unknown, // 1
    TAtlasItemKind.Method, // 2
    TAtlasItemKind.Function_, // 3
    TAtlasItemKind.Constructor_, // 4
    TAtlasItemKind.Field, // 5
    TAtlasItemKind.Variable, // 6
    TAtlasItemKind.Class_, // 7
    TAtlasItemKind.Interface_, // 8
    TAtlasItemKind.Unit_, // 9
    TAtlasItemKind.Property_, // 10
    TAtlasItemKind.Unknown, // 11
    TAtlasItemKind.Unknown, // 12
    TAtlasItemKind.Enum, // 13
    TAtlasItemKind.Keyword, // 14
    TAtlasItemKind.Snippet, // 15
    TAtlasItemKind.Unknown, // 16
    TAtlasItemKind.Unknown, // 17
    TAtlasItemKind.Unknown, // 18
    TAtlasItemKind.Unknown, // 19
    TAtlasItemKind.EnumMember, // 20
    TAtlasItemKind.Constant, // 21
    TAtlasItemKind.Record_, // 22
    TAtlasItemKind.Event, // 23
    TAtlasItemKind.Unknown, // 24
    TAtlasItemKind.Type_); // 25
begin
  if (ALspKind < Low(cLspKinds)) or (ALspKind > High(cLspKinds)) then
  begin
    Exit(TAtlasItemKind.Unknown);
  end;
  Result := cLspKinds[ALspKind];
end;

function EditFromLsp(AEdit: TJSONObject; out AResult: TAtlasTextEdit): Boolean;
begin
  AResult := Default(TAtlasTextEdit);
  Result := AEdit.TryGetValue<Integer>('range.start.line', AResult.StartLine) and
    AEdit.TryGetValue<Integer>('range.start.character', AResult.StartCharacter) and
    AEdit.TryGetValue<Integer>('range.end.line', AResult.EndLine) and
    AEdit.TryGetValue<Integer>('range.end.character', AResult.EndCharacter) and
    AEdit.TryGetValue<string>('newText', AResult.NewText);
end;

/// <summary>LSP-Range ohne Text (#448).</summary>
function RangeFromLsp(ARange: TJSONObject; out AResult: TAtlasTextEdit): Boolean;
begin
  AResult := Default(TAtlasTextEdit);
  Result := ARange.TryGetValue<Integer>('start.line', AResult.StartLine) and
    ARange.TryGetValue<Integer>('start.character', AResult.StartCharacter) and
    ARange.TryGetValue<Integer>('end.line', AResult.EndLine) and
    ARange.TryGetValue<Integer>('end.character', AResult.EndCharacter);
end;

/// <summary>Die Strings eines JSON-Arrays; leer, wenn AValue kein Array ist.</summary>
function StringsOf(AValue: TJSONValue): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mValue in TJSONArray(AValue) do
    begin
      if mValue is TJSONString then
      begin
        Result := Result + [TJSONString(mValue).Value];
      end;
    end;
  end;
end;

/// <summary>documentation (string oder MarkupContent) und data unverändert für completionItem/resolve.</summary>
procedure ReadDocumentation(AItem: TJSONObject; var AResult: TAtlasCompletionItem);
var
  mDocumentation: TJSONValue;
begin
  mDocumentation := AItem.GetValue('documentation');
  if mDocumentation is TJSONString then
  begin
    AResult.Documentation := TJSONString(mDocumentation).Value;
  end
  else if mDocumentation is TJSONObject then
  begin
    AResult.Documentation := TJSONObject(mDocumentation).GetValue<string>('value', '');
  end;
  if AItem.GetValue('data') <> nil then
  begin
    AResult.ResolveData := AItem.GetValue('data').ToJSON;
  end;
end;

/// <summary>Herkunft, Vererbungstiefe, Helper (#419, #425, #456), andere Unit und verdeckte Deklarationen (#488),
/// Mitglied eines with-Objekts (#481).</summary>
procedure ReadOrigin(AData: TJSONObject; var AResult: TAtlasCompletionItem);
begin
  AResult.DeclaringClass := AData.GetValue<string>('container', '');
  AResult.Depth := AData.GetValue<Integer>('depth', 0);
  AResult.IsHelper := AData.GetValue('helper') is TJSONTrue;
  AResult.Condition := AData.GetValue<string>('condition', '');
  AResult.VariantBranch := AData.GetValue<string>('variant', '');
  AResult.Unavailable := AData.GetValue('unavailable') is TJSONTrue;
  AResult.Scope := AData.GetValue<Integer>('scope', 0);
  AResult.DeclaringUnit := AData.GetValue<string>('unit', '');
  AResult.Hides := StringsOf(AData.GetValue('hides'));
  AResult.WithOrigin := AData.GetValue<string>('withOrigin', '');
  AResult.WithShadows := StringsOf(AData.GetValue('withShadows'));
  AResult.HasParameters := AData.GetValue('parameters') is TJSONTrue;
  AResult.ExpectedType := AData.GetValue<string>('expected', '');
  AResult.Fits := AData.GetValue('fits') is TJSONTrue;
end;

/// <summary>Einträge, die Code erzeugen: Aktionen, Postfix-Vorlagen, Aufzählungen und Mengen, case, Interface,
/// Formular, Sender und Typkonvertierung.</summary>
procedure ReadActions(AItem, AData: TJSONObject; var AResult: TAtlasCompletionItem);
begin
  // Neue Methode (#444), Deklarationen unbekannter Namen (#471) und „Parameter abgleichen“ (#88) erzeugen
  // Code und stehen am Ende; ihre Zusatzänderungen gelten auch ohne automatische uses-Einträge.
  AResult.IsAction := MatchText(AData.GetValue<string>('action', ''), ['create', 'declare', 'docParams']);
  // Postfix-Vorlagen (#188): Der Server filtert über "Ausdruck.Kürzel"; getippt ist hier nur das Wort hinter
  // dem Punkt, also gilt der Teil nach dem letzten Punkt.
  AResult.Postfix := AData.GetValue<string>('action', '') = 'postfix';
  if AResult.Postfix then
  begin
    AResult.FilterText := AItem.GetValue<string>('filterText', AResult.Name);
    AResult.FilterText := Copy(AResult.FilterText, LastDelimiter('.', AResult.FilterText) + 1, MaxInt);
  end;
  AResult.Unknown := AData.GetValue<string>('unknown', '');
  // Aufzählungen und Mengen (#448).
  AResult.Ordinal := AData.GetValue<Integer>('ordinal', 0);
  AResult.SetOf := AData.GetValue<string>('setOf', '');
  AResult.Checked := AData.GetValue('checked') is TJSONTrue;
  if (AResult.SetOf <> '') and not ((AData.GetValue('setRange') is TJSONObject) and
    RangeFromLsp(TJSONObject(AData.GetValue('setRange')), AResult.SetRange)) then
  begin
    AResult.SetOf := '';
  end;
  // case vervollständigen (#449).
  AResult.Pinned := AData.GetValue('pinned') is TJSONTrue;
  AResult.Count := AData.GetValue<Integer>('count', 0);
  // Interface implementieren (#466).
  AResult.Batch := AData.GetValue('batch') is TJSONTrue;
  AResult.Hint := AData.GetValue('hint') is TJSONTrue;
  // Komponenten aus dem Formular (#455).
  AResult.Form := AData.GetValue<string>('form', '');
  AResult.ByType := AData.GetValue('byType') is TJSONTrue;
  // Sender mit Typumwandlung (#480).
  AResult.Sender := AData.GetValue<string>('sender', '');
  AResult.SenderOf := AData.GetValue<string>('senderOf', '');
  // Typkonvertierung (#490): filtert nach dem Namen des Originals, nicht nach dem Ausdruck.
  AResult.Conversion := AData.GetValue<string>('conversion', '');
  AResult.ConvertFrom := AData.GetValue<string>('convertFrom', '');
  if AResult.Conversion <> '' then
  begin
    AResult.FilterText := AResult.ConvertFrom;
  end;
  AResult.Lossy := AData.GetValue<string>('lossy', '');
end;

/// <summary>Alle Felder zuweisen (#491): Zeilen für die Liste mit Kontrollkästchen.</summary>
function AssignmentsOf(AValue: TJSONValue): TArray<TAtlasAssignment>;
var
  mValue: TJSONValue;
  mAssignment: TAtlasAssignment;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AValue) do
  begin
    if mValue is TJSONObject then
    begin
      mAssignment.Name := TJSONObject(mValue).GetValue<string>('name', '');
      mAssignment.Detail := TJSONObject(mValue).GetValue<string>('detail', '');
      mAssignment.Text := TJSONObject(mValue).GetValue<string>('text', '');
      if mAssignment.Name <> '' then
      begin
        Result := Result + [mAssignment];
      end;
    end;
  end;
end;

/// <summary>Feld- und Parameternamen (#461), Freigabe (#489), Typargumente (#450), Attribute (#465), anonyme
/// Methoden (#468), Exception-Klassen (#483).</summary>
procedure ReadNames(AData: TJSONObject; var AResult: TAtlasCompletionItem);
begin
  AResult.DataSet := AData.GetValue<string>('dataSet', '');
  AResult.DataSource := AData.GetValue<string>('dataSource', '');
  AResult.Guard := AData.GetValue<string>('guard', '') <> '';
  AResult.TypeParam := AData.GetValue<string>('typeParam', '');
  AResult.Constraint := AData.GetValue<string>('constraint', '');
  AResult.ConstraintHint := AData.GetValue<string>('constraintHint', '');
  AResult.HiddenKinds := AData.GetValue<string>('hiddenKinds', '');
  AResult.Attribute := AData.GetValue('attribute') is TJSONTrue;
  AResult.MethodRef := AData.GetValue<string>('methodRef', '');
  AResult.ExceptionGroup := AData.GetValue<string>('exceptionGroup', '');
  AResult.Unreachable := AData.GetValue<string>('unreachable', '');
end;

/// <summary>uses-Abschnitt (#469), vollständiger inherited-Aufruf (#482), gleichnamige Bezeichner aus
/// verschiedenen Units (#475) und Platzhalter in weiteren Änderungen (#473).</summary>
procedure ReadUses(AData: TJSONObject; var AResult: TAtlasCompletionItem);
begin
  // Gefiltert wird nach dem Namensteil ab dem Getippten ("Classes" für System.Classes).
  AResult.UsesGroup := AData.GetValue<string>('usesGroup', '');
  if AData.GetValue<string>('usesFilter', '') <> '' then
  begin
    AResult.FilterText := AData.GetValue<string>('usesFilter', '');
  end;
  AResult.UsesElsewhere := AData.GetValue<string>('usesElsewhere', '');
  AResult.UsesCycle := AData.GetValue<string>('usesCycle', '');
  AResult.UsesTypes := StringsOf(AData.GetValue('usesTypes'));
  AResult.UsesTypeCount := AData.GetValue<Integer>('usesTypeCount', 0);
  AResult.UsesHidden := StringsOf(AData.GetValue('usesHidden'));
  AResult.InheritedMatch := AData.GetValue<string>('inheritedMatch', '');
  AResult.InheritedAbstract := StringsOf(AData.GetValue('inheritedAbstract'));
  AResult.SameNameActive := AData.GetValue<Boolean>('sameNameActive', False);
  AResult.SameNameOf := AData.GetValue<string>('sameNameOf', '');
  AResult.SameNameInsert := AData.GetValue<string>('sameNameInsert', '');
  AResult.SameNameUnits := StringsOf(AData.GetValue('sameNameUnits'));
  AResult.SameNameHidden := StringsOf(AData.GetValue('sameNameHidden'));
  AResult.LinkedEdits := AData.GetValue<Boolean>('linkedEdits', False);
end;

/// <summary>Überladungen (#456): gleiche Datei, andere Position; ein data je Überladung für
/// completionItem/resolve.</summary>
function OverloadDataOf(AData: TJSONObject): TArray<string>;
var
  mValue: TJSONValue;
  mTwin: TJSONObject;
begin
  Result := nil;
  if not (AData.GetValue('overloads') is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AData.GetValue('overloads')) do
  begin
    if mValue is TJSONObject then
    begin
      mTwin := AData.Clone as TJSONObject;
      try
        mTwin.RemovePair('overloads').Free;
        mTwin.RemovePair('line').Free;
        mTwin.RemovePair('character').Free;
        mTwin.AddPair('line', TJSONNumber.Create(TJSONObject(mValue).GetValue<Integer>('line', 0)));
        mTwin.AddPair('character', TJSONNumber.Create(TJSONObject(mValue).GetValue<Integer>('character', 0)));
        Result := Result + [mTwin.ToJSON];
      finally
        mTwin.Free;
      end;
    end;
  end;
end;

/// <summary>textEdit (#188) und additionalTextEdits; danach, ob die Unit schon eingebunden ist.</summary>
procedure ReadEdits(AItem: TJSONObject; var AResult: TAtlasCompletionItem);
var
  mValue: TJSONValue;
  mEdit: TAtlasTextEdit;
begin
  // textEdit ersetzt mehr als das getippte Wort, etwa den Ausdruck vor dem Punkt.
  // Ein textEdit ohne Text ersetzt nichts sinnvoll; ignorieren statt den Bereich zu löschen. Ausnahme: Der Hinweis
  // „Methoden fehlen“ (#466) entfernt das getippte Wort, der Code kommt über die weiteren Änderungen.
  if (AItem.GetValue('textEdit') is TJSONObject) and EditFromLsp(TJSONObject(AItem.GetValue('textEdit')), mEdit) and
    ((mEdit.NewText <> '') or AResult.Hint) then
  begin
    AResult.HasTextEdit := True;
    AResult.TextEdit := mEdit;
  end;
  if AItem.GetValue('additionalTextEdits') is TJSONArray then
  begin
    for mValue in TJSONArray(AItem.GetValue('additionalTextEdits')) do
    begin
      if (mValue is TJSONObject) and EditFromLsp(TJSONObject(mValue), mEdit) then
      begin
        AResult.AdditionalEdits := AResult.AdditionalEdits + [mEdit];
      end;
    end;
  end;
  // Bis #405 "Unit eingebunden" liefert: Ein Eintrag mit uses-Ergänzung (#180) kommt aus
  // einer noch nicht eingebundenen Unit. Einträge mit data.action (override, neue Methode;
  // #443, #444) ergänzen Code statt uses.
  AResult.UnitUsed := (Length(AResult.AdditionalEdits) = 0) or
    ((AItem.GetValue('data') is TJSONObject) and (TJSONObject(AItem.GetValue('data')).GetValue('action') <> nil));
end;

/// <summary>Kontextabhängige Code-Vorlage des Servers (#51): Platzhalter-Modus wie bei den eigenen Vorlagen.
/// </summary>
procedure ReadSnippet(AItem: TJSONObject; var AResult: TAtlasCompletionItem);
var
  mIndex: Integer;
begin
  if (AItem.GetValue('insertTextFormat') is TJSONNumber) and
    (TJSONNumber(AItem.GetValue('insertTextFormat')).AsInt = 2) then
  begin
    if AResult.HasTextEdit then
    begin
      AResult.Snippet := TAtlasSnippets.FromLsp(AResult.TextEdit.NewText);
    end
    else if AResult.InsertText <> '' then
    begin
      AResult.Snippet := TAtlasSnippets.FromLsp(AResult.InsertText);
    end
    else
    begin
      AResult.Snippet := TAtlasSnippets.FromLsp(AResult.Name);
    end;
  end;
  if AResult.Snippet = '' then
  begin
    AResult.LinkedEdits := False;
  end;
  if AResult.LinkedEdits then
  begin
    for mIndex := 0 to High(AResult.AdditionalEdits) do
    begin
      AResult.AdditionalEdits[mIndex].NewText := TAtlasSnippets.FromLsp(AResult.AdditionalEdits[mIndex].NewText);
    end;
  end;
end;

/// <summary>Befehl nach dem Übernehmen (#473), etwa den resourcestring in eine andere Unit schreiben.</summary>
procedure ReadCommand(AItem: TJSONObject; var AResult: TAtlasCompletionItem);
begin
  if AItem.GetValue('command') is TJSONObject then
  begin
    AResult.Command := TJSONObject(AItem.GetValue('command')).GetValue<string>('command', '');
    AResult.CommandArguments := '[]';
    if TJSONObject(AItem.GetValue('command')).GetValue('arguments') is TJSONArray then
    begin
      AResult.CommandArguments := TJSONObject(AItem.GetValue('command')).GetValue('arguments').ToJSON;
    end;
  end;
end;

class function TAtlasServerCompletionProvider.ItemFromLsp(AItem: TJSONObject; ARank: Integer): TAtlasCompletionItem;
var
  mData: TJSONObject;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AItem.GetValue<string>('label', '');
  Result.Kind := KindOf(AItem.GetValue<Integer>('kind', 0));
  Result.Signature := AItem.GetValue<string>('detail', '');
  Result.InsertText := AItem.GetValue<string>('insertText', '');
  // filterText nicht übernehmen: Der Server setzt dort bei unscharfen Treffern das getippte
  // Wort, damit VS Code sie nicht verwirft. Atlas filtert selbst gegen den Namen (#409);
  // sonst passt jeder Eintrag genau (in der IDE: "mylist" zeigte ERROR_TOO_MANY_LINKS).
  Result.Rank := ARank;
  ReadDocumentation(AItem, Result);
  if AItem.GetValue('data') is TJSONObject then
  begin
    mData := TJSONObject(AItem.GetValue('data'));
    ReadOrigin(mData, Result);
    ReadActions(AItem, mData, Result);
    Result.Assignments := AssignmentsOf(mData.GetValue('assign'));
    ReadNames(mData, Result);
    ReadUses(mData, Result);
    Result.OverloadData := OverloadDataOf(mData);
  end;
  ReadEdits(AItem, Result);
  ReadSnippet(AItem, Result);
  ReadCommand(AItem, Result);
end;

class function TAtlasServerCompletionProvider.Plain(const AItem: TAtlasCompletionItem): TAtlasCompletionItem;

  function Expanded(const AText: string): string;
  begin
    // Zeilenumbrüche wie geliefert: Der Server schreibt die des Dokuments.
    if Pos(#13#10, AText) > 0 then
    begin
      Result := TAtlasSnippets.Expand(AText, '', #13#10).Text;
    end
    else
    begin
      Result := TAtlasSnippets.Expand(AText, '', #10).Text;
    end;
  end;

var
  mIndex: Integer;
begin
  Result := AItem;
  if Result.HasTextEdit then
  begin
    Result.TextEdit.NewText := Expanded(Result.Snippet);
  end
  else
  begin
    Result.InsertText := Expanded(Result.Snippet);
  end;
  if Result.LinkedEdits then
  begin
    for mIndex := 0 to High(Result.AdditionalEdits) do
    begin
      Result.AdditionalEdits[mIndex].NewText := Expanded(Result.AdditionalEdits[mIndex].NewText);
    end;
  end;
  Result.Snippet := '';
  Result.LinkedEdits := False;
end;

class function TAtlasServerCompletionProvider.SyntaxNoticeOf(AResponse: TJSONValue): TAtlasSyntaxNotice;
var
  mNotice: TJSONValue;
  mTrust: string;
begin
  Result := Default(TAtlasSyntaxNotice);
  Result.Line := -1;
  Result.Character := -1;
  if not (AResponse is TJSONObject) then
  begin
    Exit;
  end;
  mNotice := TJSONObject(AResponse).GetValue('syntaxNotice');
  if not (mNotice is TJSONObject) then
  begin
    Exit;
  end;
  mTrust := TJSONObject(mNotice).GetValue<string>('trust', '');
  if mTrust = 'limited' then
  begin
    Result.Trust := TAtlasSyntaxTrust.Limited;
  end
  else if mTrust = 'unknown' then
  begin
    Result.Trust := TAtlasSyntaxTrust.Unknown;
  end
  else
  begin
    Exit;
  end;
  Result.Line := TJSONObject(mNotice).GetValue<Integer>('line', -1);
  Result.Character := TJSONObject(mNotice).GetValue<Integer>('character', -1);
  Result.Message := TJSONObject(mNotice).GetValue<string>('message', '');
end;

class function TAtlasServerCompletionProvider.WithoutSnippets(
  const AItems: TAtlasCompletionItems): TAtlasCompletionItems;
var
  mItem: TAtlasCompletionItem;
begin
  Result := nil;
  // Postfix-Vorlagen (#188) haben ihren eigenen Schalter completion.postfixTemplates. Einträge, die Code erzeugen
  // (resourcestring auslagern, #473), Gerüste anonymer Methoden (#468, eigener Schalter
  // completion.anonymousMethods) und "EFoo.Create('')" nach raise (#483, completion.exceptionClasses) bleiben ohne
  // Platzhalter.
  for mItem in AItems do
  begin
    if (mItem.Snippet = '') or mItem.Postfix then
    begin
      Result := Result + [mItem];
    end
    else if mItem.IsAction or (mItem.MethodRef <> '') or (mItem.ExceptionGroup <> '') then
    begin
      Result := Result + [Plain(mItem)];
    end;
  end;
end;

class function TAtlasServerCompletionProvider.ItemsFromLsp(AResponse: TJSONValue): TAtlasCompletionItems;
begin
  Result := ItemsFromLsp(AResponse, 0);
end;

class function TAtlasServerCompletionProvider.ItemsFromLsp(AResponse: TJSONValue;
  AFirstRank: Integer): TAtlasCompletionItems;
var
  mItems: TJSONValue;
  mIndex, mCount: Integer;
begin
  Result := nil;
  if AResponse is TJSONObject then
  begin
    mItems := TJSONObject(AResponse).GetValue('items');
  end
  else
  begin
    mItems := AResponse;
  end;
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  // Einmal anlegen statt je Eintrag anzuhängen: Das kopierte bei 1000 Einträgen die ganze Liste jedes Mal (#616).
  SetLength(Result, TJSONArray(mItems).Count);
  mCount := 0;
  for mIndex := 0 to TJSONArray(mItems).Count - 1 do
  begin
    if TJSONArray(mItems).Items[mIndex] is TJSONObject then
    begin
      Result[mCount] := ItemFromLsp(TJSONObject(TJSONArray(mItems).Items[mIndex]), AFirstRank + mIndex);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

procedure TAtlasServerCompletionProvider.Log(const AMessage: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(AMessage);
  end;
end;

function TAtlasServerCompletionProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
var
  mSession: TLspSession;
begin
  AData := nil;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  Result := (mSession <> nil) and (AContext.FileName <> '');
  if not Result then
  begin
    if mSession = nil then
    begin
      Log('Vervollständigung: kein Server verbunden');
    end;
    Exit;
  end;
  // Sync ist threadsicher (FDocLock in TLspSession); hier im Zeitlimit-Arbeiter.
  mSession.Sync(AContext.FileName, AContext.Text);
  AData := mSession;
end;

function TAtlasServerCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc;
    out AState: TAtlasFetchState): TAtlasCompletionItems;
var
  mResponse: TJSONValue;
  mNextRank: Integer;
  mEmit: TAtlasEmitProc;
  mWatch: TStopwatch;
  mSnippets: Boolean;
begin
  AState := Default(TAtlasFetchState);
  mNextRank := 0;
  mEmit := AEmit;
  mSnippets := FSnippets;
  mWatch := TStopwatch.StartNew;
  // Teilergebnisse kommen im Lese-Thread nacheinander und alle vor der Antwort.
  mResponse := TLspSession(AData).Completion(AContext.FileName, AContext.Line, AContext.Character, FTimeoutMs,
    AContext.Trigger,
    procedure(const AValue: TJSONValue)
    var
      Items: TAtlasCompletionItems;
    begin
      if not (AValue is TJSONArray) then
      begin
        Exit;
      end;
      Items := ItemsFromLsp(AValue, mNextRank);
      Inc(mNextRank, TJSONArray(AValue).Count);
      // completion.snippets aus (#51): wie ohne die Funktion.
      if not mSnippets then
      begin
        Items := WithoutSnippets(Items);
      end;
      mEmit(Items);
    end);
  try
    // Ohne Antwort bleibt die Liste leer; das Zeitlimit ist FTimeoutMs.
    if mResponse = nil then
    begin
      Log(Format('Vervollständigung: keine Antwort nach %d ms (%d Teilergebnisse)',
        [mWatch.ElapsedMilliseconds, mNextRank]));
    end
    else
    begin
      Log(Format('Vervollständigung: Antwort nach %d ms', [mWatch.ElapsedMilliseconds]));
    end;
    if ACancelled() then
    begin
      Exit(nil);
    end;
    // CompletionList mit isIncomplete: Der Server hat gekürzt und will beim Weitertippen neu gefragt werden.
    // Ohne GetValue<Boolean>: das lässt über TValue Speicher liegen (Leck-Monitor).
    AState.Incomplete := (mResponse is TJSONObject) and (TJSONObject(mResponse).GetValue('isIncomplete') is TJSONBool) and
      TJSONBool(TJSONObject(mResponse).GetValue('isIncomplete')).AsBoolean;
    AState.Syntax := SyntaxNoticeOf(mResponse);
    Result := ItemsFromLsp(mResponse, mNextRank);
    if not mSnippets then
    begin
      Result := WithoutSnippets(Result);
    end;
  finally
    mResponse.Free;
  end;
end;

function EntriesOf(AObject: TJSONObject; const AName: string): TArray<TAtlasDocEntry>;
var
  mValue, mItem: TJSONValue;
  mEntry: TAtlasDocEntry;
begin
  Result := nil;
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if mItem is TJSONObject then
    begin
      mEntry.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
      mEntry.Text := TJsonRead.Text(TJSONObject(mItem), 'text');
      Result := Result + [mEntry];
    end;
  end;
end;

class function TAtlasServerCompletionProvider.DetailsFromLsp(AResponse: TJSONValue): TAtlasItemDetails;
var
  mData, mAtlas, mDirectives, mItem: TJSONValue;
  mDocumentation: TJSONValue;
begin
  Result := Default(TAtlasItemDetails);
  if not (AResponse is TJSONObject) then
  begin
    Exit;
  end;
  mData := TJSONObject(AResponse).GetValue('data');
  mAtlas := nil;
  if mData is TJSONObject then
  begin
    mAtlas := TJSONObject(mData).GetValue('atlas');
  end;
  if mAtlas is TJSONObject then
  begin
    Result.Declaration := TJsonRead.Text(TJSONObject(mAtlas), 'declaration');
    Result.UnitName := TJsonRead.Text(TJSONObject(mAtlas), 'unit');
    Result.Container := TJsonRead.Text(TJSONObject(mAtlas), 'container');
    Result.IsHelper := TJSONObject(mAtlas).GetValue('helper') is TJSONTrue;
    Result.Visibility := TJsonRead.Text(TJSONObject(mAtlas), 'visibility');
    Result.IsDeprecated := TJSONObject(mAtlas).GetValue('deprecated') <> nil;
    Result.DeprecatedText := TJsonRead.Text(TJSONObject(mAtlas), 'deprecated');
    Result.Summary := TJsonRead.Text(TJSONObject(mAtlas), 'summary');
    Result.Returns := TJsonRead.Text(TJSONObject(mAtlas), 'returns');
    Result.Remarks := TJsonRead.Text(TJSONObject(mAtlas), 'remarks');
    Result.Params := EntriesOf(TJSONObject(mAtlas), 'params');
    Result.Exceptions := EntriesOf(TJSONObject(mAtlas), 'exceptions');
    Result.Doc := TAtlasDoc.FromJson(TJSONObject(mAtlas).GetValue('documentation'));
    Result.Display := TAtlasDocDisplay.FromJson(TJSONObject(mAtlas).GetValue('xmlDoc'),
      TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 0));
    mDirectives := TJSONObject(mAtlas).GetValue('directives');
    if mDirectives is TJSONArray then
    begin
      for mItem in TJSONArray(mDirectives) do
      begin
        if mItem is TJSONString then
        begin
          Result.Directives := Result.Directives + [TJSONString(mItem).Value];
        end;
      end;
    end;
    Exit;
  end;
  // Andere Server: detail als Deklaration, documentation als Beschreibung.
  Result.Declaration := TJsonRead.Text(TJSONObject(AResponse), 'detail');
  mDocumentation := TJSONObject(AResponse).GetValue('documentation');
  if mDocumentation is TJSONString then
  begin
    Result.Summary := TJSONString(mDocumentation).Value;
  end
  else if mDocumentation is TJSONObject then
  begin
    Result.Summary := TJsonRead.Text(TJSONObject(mDocumentation), 'value');
  end;
end;

/// <summary>Anfrage für completionItem/resolve: nur label und data, mehr braucht der Server nicht.</summary>
function ResolveRequest(const AItem: TAtlasCompletionItem): string;
var
  mItem: TJSONObject;
begin
  mItem := TJSONObject.Create;
  try
    mItem.AddPair('label', AItem.Name);
    mItem.AddPair('data', TJSONObject.ParseJSONValue(AItem.ResolveData));
    Result := mItem.ToJSON;
  finally
    mItem.Free;
  end;
end;

/// <summary>ADetails mit dem, was der Eintrag selbst schon weiß: verdeckte Deklarationen, with-Objekt und
/// verlustbehaftete Konvertierung.</summary>
function WithItemFacts(const ADetails: TAtlasItemDetails; const AItem: TAtlasCompletionItem): TAtlasItemDetails;
begin
  Result := ADetails;
  Result.Hides := AItem.Hides;
  Result.WithOrigin := AItem.WithOrigin;
  Result.LossyFrom := AItem.Lossy;
  Result.LossyTo := '';
  if AItem.Lossy <> '' then
  begin
    Result.LossyTo := AItem.ExpectedType;
  end;
end;

function TAtlasServerCompletionProvider.Resolve(const AItem: TAtlasCompletionItem;
  const ACallback: TAtlasDetailsCallback): Boolean;
var
  mSession: TLspSession;
  mRequest: string;
  mGeneration: Integer;
  mAliveToken: TAtlasAliveToken;
  mAliveRef: IInterface;
  mProvider: TAtlasServerCompletionProvider;
  mCallback: TAtlasDetailsCallback;
  mItem: TAtlasCompletionItem;
begin
  Result := False;
  if AItem.ResolveData = '' then
  begin
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Exit;
  end;
  mRequest := ResolveRequest(AItem);
  mItem := AItem;
  mGeneration := TInterlocked.Increment(FResolveGeneration);
  mAliveToken := Token;
  mAliveRef := TokenRef;
  mProvider := Self;
  mCallback := ACallback;
  RunInBackground(
    procedure
    var
      Response: TJSONValue;
      Details: TAtlasItemDetails;
    begin
      Response := mSession.ResolveCompletion(TJSONObject.ParseJSONValue(mRequest) as TJSONObject, FTimeoutMs);
      try
        Details := WithItemFacts(DetailsFromLsp(Response), mItem);
      finally
        Response.Free;
      end;
      // Der Rückruf zeigt das Detailpanel; die Hülle zählt seine Fehler für die Vervollständigung (S-05, A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Completion,
        procedure
        begin
          if mAliveToken.Alive and (mAliveRef <> nil) and
            (TInterlocked.CompareExchange(mProvider.FResolveGeneration, 0, 0) = mGeneration) then
          begin
            mCallback(Details);
          end;
        end);
    end);
  Result := True;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Completion.Providers.Server', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.