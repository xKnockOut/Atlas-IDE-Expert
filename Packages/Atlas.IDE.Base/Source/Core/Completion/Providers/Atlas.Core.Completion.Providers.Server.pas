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
  Atlas.Core.Localization.Language;

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
begin
  case ALspKind of
    2: Result := TAtlasItemKind.Method;
    3: Result := TAtlasItemKind.Function_;
    4: Result := TAtlasItemKind.Constructor_;
    5: Result := TAtlasItemKind.Field;
    6: Result := TAtlasItemKind.Variable;
    7: Result := TAtlasItemKind.Class_;
    8: Result := TAtlasItemKind.Interface_;
    9: Result := TAtlasItemKind.Unit_;
    10: Result := TAtlasItemKind.Property_;
    13: Result := TAtlasItemKind.Enum;
    14: Result := TAtlasItemKind.Keyword;
    15: Result := TAtlasItemKind.Snippet;
    20: Result := TAtlasItemKind.EnumMember;
    21: Result := TAtlasItemKind.Constant;
    22: Result := TAtlasItemKind.Record_;
    23: Result := TAtlasItemKind.Event;
    25: Result := TAtlasItemKind.Type_;
  else
    Result := TAtlasItemKind.Unknown;
  end;
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

class function TAtlasServerCompletionProvider.ItemFromLsp(AItem: TJSONObject; ARank: Integer): TAtlasCompletionItem;
var
  mDocumentation, mEdits, mValue, mOverloads: TJSONValue;
  mEdit: TAtlasTextEdit;
  mData, mTwin: TJSONObject;
  mIndex: Integer;
  mAssignment: TAtlasAssignment;
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
  // documentation: string oder MarkupContent.
  mDocumentation := AItem.GetValue('documentation');
  if mDocumentation is TJSONString then
  begin
    Result.Documentation := TJSONString(mDocumentation).Value;
  end
  else if mDocumentation is TJSONObject then
  begin
    Result.Documentation := TJSONObject(mDocumentation).GetValue<string>('value', '');
  end;
  // data unverändert für completionItem/resolve aufheben.
  if AItem.GetValue('data') <> nil then
  begin
    Result.ResolveData := AItem.GetValue('data').ToJSON;
  end;
  // Herkunft, Vererbungstiefe, Helper und Überladungen (#419, #425, #456).
  if AItem.GetValue('data') is TJSONObject then
  begin
    mData := TJSONObject(AItem.GetValue('data'));
    Result.DeclaringClass := mData.GetValue<string>('container', '');
    Result.Depth := mData.GetValue<Integer>('depth', 0);
    Result.IsHelper := mData.GetValue('helper') is TJSONTrue;
    Result.Condition := mData.GetValue<string>('condition', '');
    Result.VariantBranch := mData.GetValue<string>('variant', '');
    Result.Unavailable := mData.GetValue('unavailable') is TJSONTrue;
    Result.Scope := mData.GetValue<Integer>('scope', 0);
    // Herkunft aus einer anderen Unit und verdeckte Deklarationen (#488).
    Result.DeclaringUnit := mData.GetValue<string>('unit', '');
    mValue := mData.GetValue('hides');
    if mValue is TJSONArray then
    begin
      for mValue in TJSONArray(mData.GetValue('hides')) do
      begin
        if mValue is TJSONString then
        begin
          Result.Hides := Result.Hides + [TJSONString(mValue).Value];
        end;
      end;
    end;
    // Mitglied eines with-Objekts (#481).
    Result.WithOrigin := mData.GetValue<string>('withOrigin', '');
    mValue := mData.GetValue('withShadows');
    if mValue is TJSONArray then
    begin
      for mValue in TJSONArray(mData.GetValue('withShadows')) do
      begin
        if mValue is TJSONString then
        begin
          Result.WithShadows := Result.WithShadows + [TJSONString(mValue).Value];
        end;
      end;
    end;
    Result.HasParameters := mData.GetValue('parameters') is TJSONTrue;
    Result.ExpectedType := mData.GetValue<string>('expected', '');
    Result.Fits := mData.GetValue('fits') is TJSONTrue;
    // Neue Methode (#444), Deklarationen unbekannter Namen (#471) und „Parameter abgleichen“ (#88) erzeugen
    // Code und stehen am Ende; ihre Zusatzänderungen gelten auch ohne automatische uses-Einträge.
    Result.IsAction := MatchText(mData.GetValue<string>('action', ''), ['create', 'declare', 'docParams']);
    // Postfix-Vorlagen (#188): Der Server filtert über "Ausdruck.Kürzel"; getippt ist hier nur das Wort hinter
    // dem Punkt, also gilt der Teil nach dem letzten Punkt.
    Result.Postfix := mData.GetValue<string>('action', '') = 'postfix';
    if Result.Postfix then
    begin
      Result.FilterText := AItem.GetValue<string>('filterText', Result.Name);
      Result.FilterText := Copy(Result.FilterText, LastDelimiter('.', Result.FilterText) + 1, MaxInt);
    end;
    Result.Unknown := mData.GetValue<string>('unknown', '');
    // Aufzählungen und Mengen (#448).
    Result.Ordinal := mData.GetValue<Integer>('ordinal', 0);
    Result.SetOf := mData.GetValue<string>('setOf', '');
    Result.Checked := mData.GetValue('checked') is TJSONTrue;
    if (Result.SetOf <> '') and not ((mData.GetValue('setRange') is TJSONObject) and
      RangeFromLsp(TJSONObject(mData.GetValue('setRange')), Result.SetRange)) then
    begin
      Result.SetOf := '';
    end;
    // case vervollständigen (#449).
    Result.Pinned := mData.GetValue('pinned') is TJSONTrue;
    Result.Count := mData.GetValue<Integer>('count', 0);
    // Interface implementieren (#466).
    Result.Batch := mData.GetValue('batch') is TJSONTrue;
    Result.Hint := mData.GetValue('hint') is TJSONTrue;
    // Komponenten aus dem Formular (#455).
    Result.Form := mData.GetValue<string>('form', '');
    Result.ByType := mData.GetValue('byType') is TJSONTrue;
    // Sender mit Typumwandlung (#480).
    Result.Sender := mData.GetValue<string>('sender', '');
    Result.SenderOf := mData.GetValue<string>('senderOf', '');
    // Typkonvertierung (#490): filtert nach dem Namen des Originals, nicht nach dem Ausdruck.
    Result.Conversion := mData.GetValue<string>('conversion', '');
    Result.ConvertFrom := mData.GetValue<string>('convertFrom', '');
    if Result.Conversion <> '' then
    begin
      Result.FilterText := Result.ConvertFrom;
    end;
    Result.Lossy := mData.GetValue<string>('lossy', '');
    // Alle Felder zuweisen (#491): Zeilen für die Liste mit Kontrollkästchen.
    if mData.GetValue('assign') is TJSONArray then
    begin
      for mValue in TJSONArray(mData.GetValue('assign')) do
      begin
        if mValue is TJSONObject then
        begin
          mAssignment.Name := TJSONObject(mValue).GetValue<string>('name', '');
          mAssignment.Detail := TJSONObject(mValue).GetValue<string>('detail', '');
          mAssignment.Text := TJSONObject(mValue).GetValue<string>('text', '');
          if mAssignment.Name <> '' then
          begin
            Result.Assignments := Result.Assignments + [mAssignment];
          end;
        end;
      end;
    end;
    // Feld- und Parameternamen (#461).
    Result.DataSet := mData.GetValue<string>('dataSet', '');
    Result.DataSource := mData.GetValue<string>('dataSource', '');
    // Freigabe absichern (#489).
    Result.Guard := mData.GetValue<string>('guard', '') <> '';
    // Typargumente nach den Constraints (#450).
    Result.TypeParam := mData.GetValue<string>('typeParam', '');
    Result.Constraint := mData.GetValue<string>('constraint', '');
    Result.ConstraintHint := mData.GetValue<string>('constraintHint', '');
    Result.HiddenKinds := mData.GetValue<string>('hiddenKinds', '');
    // Attribute nach "[" (#465).
    Result.Attribute := mData.GetValue('attribute') is TJSONTrue;
    // Anonyme Methoden (#468).
    Result.MethodRef := mData.GetValue<string>('methodRef', '');
    // Exception-Klassen (#483).
    Result.ExceptionGroup := mData.GetValue<string>('exceptionGroup', '');
    Result.Unreachable := mData.GetValue<string>('unreachable', '');
    // uses-Abschnitt (#469): gefiltert wird nach dem Namensteil ab dem Getippten ("Classes" für System.Classes).
    Result.UsesGroup := mData.GetValue<string>('usesGroup', '');
    if mData.GetValue<string>('usesFilter', '') <> '' then
    begin
      Result.FilterText := mData.GetValue<string>('usesFilter', '');
    end;
    Result.UsesElsewhere := mData.GetValue<string>('usesElsewhere', '');
    Result.UsesCycle := mData.GetValue<string>('usesCycle', '');
    Result.UsesTypes := StringsOf(mData.GetValue('usesTypes'));
    Result.UsesTypeCount := mData.GetValue<Integer>('usesTypeCount', 0);
    Result.UsesHidden := StringsOf(mData.GetValue('usesHidden'));
    // Vollständiger inherited-Aufruf (#482).
    Result.InheritedMatch := mData.GetValue<string>('inheritedMatch', '');
    Result.InheritedAbstract := StringsOf(mData.GetValue('inheritedAbstract'));
    // Gleichnamige Bezeichner aus verschiedenen Units (#475).
    Result.SameNameActive := mData.GetValue<Boolean>('sameNameActive', False);
    Result.SameNameOf := mData.GetValue<string>('sameNameOf', '');
    Result.SameNameInsert := mData.GetValue<string>('sameNameInsert', '');
    Result.SameNameUnits := StringsOf(mData.GetValue('sameNameUnits'));
    Result.SameNameHidden := StringsOf(mData.GetValue('sameNameHidden'));
    // resourcestring auslagern (#473): Platzhalter auch in den weiteren Änderungen.
    Result.LinkedEdits := mData.GetValue<Boolean>('linkedEdits', False);
    mOverloads := mData.GetValue('overloads');
    if mOverloads is TJSONArray then
    begin
      for mValue in TJSONArray(mOverloads) do
      begin
        if mValue is TJSONObject then
        begin
          // Gleiche Datei, andere Position: ein data je Überladung für completionItem/resolve.
          mTwin := mData.Clone as TJSONObject;
          try
            mTwin.RemovePair('overloads').Free;
            mTwin.RemovePair('line').Free;
            mTwin.RemovePair('character').Free;
            mTwin.AddPair('line', TJSONNumber.Create(TJSONObject(mValue).GetValue<Integer>('line', 0)));
            mTwin.AddPair('character', TJSONNumber.Create(TJSONObject(mValue).GetValue<Integer>('character', 0)));
            Result.OverloadData := Result.OverloadData + [mTwin.ToJSON];
          finally
            mTwin.Free;
          end;
        end;
      end;
    end;
  end;
  // textEdit (#188): ersetzt mehr als das getippte Wort, etwa den Ausdruck vor dem Punkt.
  // Ein textEdit ohne Text ersetzt nichts sinnvoll; ignorieren statt den Bereich zu löschen. Ausnahme: Der Hinweis
  // „Methoden fehlen“ (#466) entfernt das getippte Wort, der Code kommt über die weiteren Änderungen.
  if (AItem.GetValue('textEdit') is TJSONObject) and EditFromLsp(TJSONObject(AItem.GetValue('textEdit')), mEdit) and
    ((mEdit.NewText <> '') or Result.Hint) then
  begin
    Result.HasTextEdit := True;
    Result.TextEdit := mEdit;
  end;
  mEdits := AItem.GetValue('additionalTextEdits');
  if mEdits is TJSONArray then
  begin
    for mValue in TJSONArray(mEdits) do
    begin
      if (mValue is TJSONObject) and EditFromLsp(TJSONObject(mValue), mEdit) then
      begin
        Result.AdditionalEdits := Result.AdditionalEdits + [mEdit];
      end;
    end;
  end;
  // Bis #405 "Unit eingebunden" liefert: Ein Eintrag mit uses-Ergänzung (#180) kommt aus
  // einer noch nicht eingebundenen Unit. Einträge mit data.action (override, neue Methode;
  // #443, #444) ergänzen Code statt uses.
  Result.UnitUsed := (Length(Result.AdditionalEdits) = 0) or
    ((AItem.GetValue('data') is TJSONObject) and (TJSONObject(AItem.GetValue('data')).GetValue('action') <> nil));
  // Kontextabhängige Code-Vorlage des Servers (#51): Platzhalter-Modus wie bei den eigenen Vorlagen.
  if (AItem.GetValue('insertTextFormat') is TJSONNumber) and
    (TJSONNumber(AItem.GetValue('insertTextFormat')).AsInt = 2) then
  begin
    if Result.HasTextEdit then
    begin
      Result.Snippet := TAtlasSnippets.FromLsp(Result.TextEdit.NewText);
    end
    else if Result.InsertText <> '' then
    begin
      Result.Snippet := TAtlasSnippets.FromLsp(Result.InsertText);
    end
    else
    begin
      Result.Snippet := TAtlasSnippets.FromLsp(Result.Name);
    end;
  end;
  if Result.Snippet = '' then
  begin
    Result.LinkedEdits := False;
  end;
  if Result.LinkedEdits then
  begin
    for mIndex := 0 to High(Result.AdditionalEdits) do
    begin
      Result.AdditionalEdits[mIndex].NewText := TAtlasSnippets.FromLsp(Result.AdditionalEdits[mIndex].NewText);
    end;
  end;
  // Befehl nach dem Übernehmen (#473), etwa den resourcestring in eine andere Unit schreiben.
  if AItem.GetValue('command') is TJSONObject then
  begin
    Result.Command := TJSONObject(AItem.GetValue('command')).GetValue<string>('command', '');
    Result.CommandArguments := '[]';
    if TJSONObject(AItem.GetValue('command')).GetValue('arguments') is TJSONArray then
    begin
      Result.CommandArguments := TJSONObject(AItem.GetValue('command')).GetValue('arguments').ToJSON;
    end;
  end;
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

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end
  else
  begin
    Result := '';
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
      mEntry.Name := StringOf(TJSONObject(mItem), 'name');
      mEntry.Text := StringOf(TJSONObject(mItem), 'text');
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
    Result.Declaration := StringOf(TJSONObject(mAtlas), 'declaration');
    Result.UnitName := StringOf(TJSONObject(mAtlas), 'unit');
    Result.Container := StringOf(TJSONObject(mAtlas), 'container');
    Result.IsHelper := TJSONObject(mAtlas).GetValue('helper') is TJSONTrue;
    Result.Visibility := StringOf(TJSONObject(mAtlas), 'visibility');
    Result.IsDeprecated := TJSONObject(mAtlas).GetValue('deprecated') <> nil;
    Result.DeprecatedText := StringOf(TJSONObject(mAtlas), 'deprecated');
    Result.Summary := StringOf(TJSONObject(mAtlas), 'summary');
    Result.Returns := StringOf(TJSONObject(mAtlas), 'returns');
    Result.Remarks := StringOf(TJSONObject(mAtlas), 'remarks');
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
  Result.Declaration := StringOf(TJSONObject(AResponse), 'detail');
  mDocumentation := TJSONObject(AResponse).GetValue('documentation');
  if mDocumentation is TJSONString then
  begin
    Result.Summary := TJSONString(mDocumentation).Value;
  end
  else if mDocumentation is TJSONObject then
  begin
    Result.Summary := StringOf(TJSONObject(mDocumentation), 'value');
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
  mItem: TJSONObject;
  mHides: TArray<string>;
  mWithOrigin, mLossyFrom, mLossyTo: string;
begin
  Result := False;
  if AItem.ResolveData = '' then
  begin
    Exit;
  end;
  mHides := AItem.Hides;
  mWithOrigin := AItem.WithOrigin;
  mLossyFrom := AItem.Lossy;
  mLossyTo := '';
  if mLossyFrom <> '' then
  begin
    mLossyTo := AItem.ExpectedType;
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
  // Nur label und data: mehr braucht der Server nicht.
  mItem := TJSONObject.Create;
  try
    mItem.AddPair('label', AItem.Name);
    mItem.AddPair('data', TJSONObject.ParseJSONValue(AItem.ResolveData));
    mRequest := mItem.ToJSON;
  finally
    mItem.Free;
  end;
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
        Details := DetailsFromLsp(Response);
      finally
        Response.Free;
      end;
      Details.Hides := mHides;
      Details.WithOrigin := mWithOrigin;
      Details.LossyFrom := mLossyFrom;
      Details.LossyTo := mLossyTo;
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