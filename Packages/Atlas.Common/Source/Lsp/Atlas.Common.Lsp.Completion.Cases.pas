unit Atlas.Common.Lsp.Completion.Cases;

// Die Fälle von textDocument/completion in fester Reihenfolge (Code-Review S-01): ohne Syntaxbaum
// (Schnellbefehle, Direktiven, Feldnamen in Strings, Wertdarstellungen) und mit Baum und Resolver (Angebote
// oben in der Liste, exklusive Listen, die allgemeine Liste, Code-Vorlagen, Deklarieren). Aus
// Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Forms,
  Atlas.Common.Lsp.Completion.Postfix,
  Atlas.Common.Lsp.Completion.Hooks;

type
  /// <summary>Ergebnis eines Falls der Vervollständigung (Code-Review S-01): weiter mit dem nächsten Fall oder
  /// fertig mit TCompletionAnswer.Exclusive.</summary>
  TCompletionOutcome = (Next, Answered);

  /// <summary>Antwort im Aufbau (Code-Review S-01, 4.2 Schritt 5): Hinweise oben, vorab bestimmte Einträge
  /// (Aufzählungswerte, Komponenten; bei Staffelung schon gesendet), die allgemeine Liste und der Schluss
  /// (Code-Vorlagen, Deklarieren). Ein exklusiver Fall antwortet mit Exclusive allein.</summary>
  TCompletionAnswer = class
  public
    Hints: TArray<TCompletionItem>;
    Prefetched: TArray<TCompletionItem>;
    Body: TArray<TCompletionItem>;
    Tail: TArray<TCompletionItem>;
    Incomplete: Boolean;
    Exclusive: TCompletionItems;
    /// <summary>Postfix-Vorlagen des Dokuments (#188), gesetzt vor der allgemeinen Liste.</summary>
    Postfix: TPostfixOptions;
    /// <summary>partialResultToken (#616); '' ohne Staffelung.</summary>
    Token: string;
    /// <summary>Schon als $/progress gesendete Einträge; die Antwort setzt sortText dahinter fort.</summary>
    SentCount: Integer;
    Partial: TCompletionPartialProc;
    Cancellation: IJsonRpcCancellationToken;
    Forms: TCompletionFormFunc;
    /// <summary>Rückrufe und Schalter der Vervollständigung; gehört der TLspCompletion.</summary>
    Hooks: TCompletionHooks;
  end;

  /// <summary>Ein Fall von textDocument/completion; die Reihenfolge legen TextCases und TreeCases fest.
  /// </summary>
  TCompletionCase = reference to function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;

  TCompletionCases = class
  public
    /// <summary>Fälle ohne Syntaxbaum, in dieser Reihenfolge: Schnellbefehle (#293), Direktiven (#102), Feld- und
    /// Parameternamen im String-Literal (#461), Platzhalter in Wertdarstellungen (#854).</summary>
    class function TextCases: TArray<TCompletionCase>; static;
    /// <summary>Fälle mit Baum und Resolver, in der Reihenfolge der Auswertung.</summary>
    class function TreeCases: TArray<TCompletionCase>; static;
    /// <summary>Läuft ACases der Reihe nach, bis einer antwortet; True dann.</summary>
    class function Run(const ACases: TArray<TCompletionCase>; ARequest: TCompletionRequest;
      AAnswer: TCompletionAnswer): Boolean; static;
    /// <summary>"Sender." in einem Ereignisbehandler mit "Sender: TObject" (#480): Ist die Methode im Formular
    /// Komponenten zugewiesen, die Mitglieder des nächsten gemeinsamen Vorfahren ihrer Typen. Jeder Eintrag
    /// ersetzt "Sender.Na" (TextEdit) durch die Umwandlung nach Settings.SenderCast und den Namen. False ohne
    /// Zuweisung im Formular (über AForms), bei bereits umgewandeltem Sender oder wenn der gemeinsame Typ TObject
    /// ist.</summary>
    class function SenderItems(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
      out AItems: TCompletionItems): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CreateMethod,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.DocComments,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Lsp.CompletionDebugDisplay,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Completion.Values,
  Atlas.Common.Lsp.Completion.Declarations,
  Atlas.Common.Lsp.Completion.Names,
  Atlas.Common.Lsp.Completion.Methods,
  Atlas.Common.Lsp.Completion.Guard,
  Atlas.Common.Lsp.Completion.Slash,
  Atlas.Common.Lsp.Completion.Lists;

type
  /// <summary>Texte der Fälle in beiden Sprachen (#1458).</summary>
  TCasesText = (ResolveWith);

const
  cTexts: array[TCasesText] of TAtlasText = (
    (De: 'with auflösen'; En: 'Resolve with'));

/// <summary>Answered, wenn AFound; sonst Next.</summary>
function AnsweredIf(AFound: Boolean): TCompletionOutcome;
begin
  Result := TCompletionOutcome.Next;
  if AFound then
  begin
    Result := TCompletionOutcome.Answered;
  end;
end;

/// <summary>AAnswer antwortet mit AItem allein.</summary>
function AnswerWith(AAnswer: TCompletionAnswer; const AItem: TCompletionItem): TCompletionOutcome;
begin
  AAnswer.Exclusive := Default(TCompletionItems);
  AAnswer.Exclusive.Items := [AItem];
  Result := TCompletionOutcome.Answered;
end;

/// <summary>AItems ohne die Schlüsselwörter aus AddKeywords (#31).</summary>
function WithoutKeywords(const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  mItem: TCompletionItem;
  mCount: Integer;
begin
  // Einmal anlegen statt je Eintrag anhängen (Code-Review P-08), wie WithoutNames.
  Result := nil;
  SetLength(Result, Length(AItems));
  mCount := 0;
  for mItem in AItems do
  begin
    if mItem.Kind <> KindKeyword then
    begin
      Result[mCount] := mItem;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

/// <summary>AItems ohne die Namen aus ANames (#448: vorab bestimmte Einträge).</summary>
function WithoutNames(const AItems, ANames: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  mNames: TDictionary<string, Boolean>;
  mItem: TCompletionItem;
  mCount: Integer;
begin
  if Length(ANames) = 0 then
  begin
    Exit(AItems);
  end;
  mNames := TDictionary<string, Boolean>.Create;
  try
    for mItem in ANames do
    begin
      mNames.AddOrSetValue(LowerCase(mItem.Name), True);
    end;
    Result := nil;
    SetLength(Result, Length(AItems));
    mCount := 0;
    for mItem in AItems do
    begin
      if not mNames.ContainsKey(LowerCase(mItem.Name)) then
      begin
        Result[mCount] := mItem;
        Inc(mCount);
      end;
    end;
    SetLength(Result, mCount);
  finally
    mNames.Free;
  end;
end;

/// <summary>Index des Tokens, auf dem APosition steht; Length(ATokens) dahinter.</summary>
function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and (ComparePositions(ATokens[Result].EndPos, APosition) < 0) do
  begin
    Inc(Result);
  end;
end;

/// <summary>„with auflösen“ (#50) als Eintrag, wenn der Cursor auf dem Wort with steht: die Hauptänderung
/// entfernt das Wort (eine Zeile, mit dem Cursor), der Rest der Anweisung kommt als Zusatzänderung.</summary>
function WithItem(ARequest: TCompletionRequest; const AWithFor: TCompletionWithFunc;
  out AItem: TCompletionItem): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
begin
  AItem := Default(TCompletionItem);
  Result := False;
  mIndex := TokenAt(ARequest.Tree.Tokens, ARequest.Position);
  if mIndex > High(ARequest.Tree.Tokens) then
  begin
    Exit;
  end;
  mToken := ARequest.Tree.Tokens[mIndex];
  if not mToken.IsKeyword('with') or (ComparePositions(mToken.StartPos, ARequest.Position) > 0) or
    not AWithFor(ARequest, mEdits) then
  begin
    Exit;
  end;
  AItem.Name := cTexts[TCasesText.ResolveWith].Text;
  AItem.Kind := KindSnippet;
  AItem.Detail := 'Atlas';
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'with';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(mToken.StartPos, mToken.EndPos), '');
  for mEdit in mEdits do
  begin
    if (mEdit.Range.StartPos.Line = mToken.StartPos.Line) and
      (mEdit.Range.StartPos.Character = mToken.StartPos.Character) then
    begin
      AItem.AdditionalEdits := AItem.AdditionalEdits + [TRuleEdit.Create(TTextRange.Create(mToken.EndPos,
        mEdit.Range.EndPos), mEdit.NewText)];
      Result := True;
    end
    else
    begin
      AItem.AdditionalEdits := AItem.AdditionalEdits + [mEdit];
    end;
  end;
end;

/// <summary>„Parameter abgleichen“ (#88) als Eintrag, wenn der Cursor in einem ///-Block über einer Routine
/// steht, deren Signatur nicht mehr zum Block passt: An der Cursorstelle ändert sich nichts, fehlende
/// &lt;param&gt; und markierte überzählige kommen als Zusatzänderungen.</summary>
function DocParamsItem(ARequest: TCompletionRequest; out AItem: TCompletionItem): Boolean;
var
  mAction: TCodeAction;
begin
  AItem := Default(TCompletionItem);
  Result := TDocComments.AdjustBlock(ARequest.Text, ARequest.Tree, ARequest.Position.Line, mAction);
  if not Result then
  begin
    Exit;
  end;
  AItem.Name := mAction.Title;
  AItem.Kind := KindSnippet;
  AItem.Detail := 'Atlas';
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'docParams';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position, ARequest.Position), '');
  AItem.AdditionalEdits := mAction.Edits;
end;

/// <summary>„Methode aus Aufruf anlegen“ (#472) als Eintrag: Nach dem Auslöser "(" bleibt der Text an der
/// Aufrufstelle, mit Strg+Leer auf dem Namen ersetzt der Eintrag ihn durch sich selbst. Deklaration und Rumpf
/// kommen als Zusatzänderungen; "$0" darin setzt den Cursor in den Rumpf.</summary>
function CreateItem(ARequest: TCompletionRequest; const ACreateFor: TCompletionCreateFunc;
  out AItem: TCompletionItem): Boolean;
var
  mSite: TCreateCallSite;
  mTitle, mDetail: string;
  mEdits: TArray<TTextEdit>;
begin
  AItem := Default(TCompletionItem);
  Result := (ARequest.Tree <> nil) and TCreateMethod.Site(ARequest.Tree.Tokens, ARequest.Position, mSite) and
    ACreateFor(ARequest, mTitle, mDetail, mEdits);
  if not Result then
  begin
    Exit;
  end;
  AItem.Name := mTitle;
  AItem.Kind := KindMethod;
  AItem.Detail := mDetail;
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'create';
  AItem.Unknown := mSite.Name;
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(mSite.NameRange, mSite.Name);
  if ARequest.Trigger = '(' then
  begin
    AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position, ARequest.Position), '');
  end;
  AItem.AdditionalEdits := mEdits;
end;

/// <summary>Sendet AItems als $/progress und zählt sie zu den gesendeten.</summary>
procedure SendProgress(AAnswer: TCompletionAnswer; const AItems: TArray<TCompletionItem>);
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('token', AAnswer.Token);
  mParams.AddPair('value', CompletionItemsToJson(AItems, AAnswer.SentCount));
  Inc(AAnswer.SentCount, Length(AItems));
  AAnswer.Hooks.Notify('$/progress', mParams);
end;

/// <summary>Teilergebnisse als $/progress (#616); zwischen den Stufen bricht eine veraltete Anfrage ab.</summary>
function PartialSender(AAnswer: TCompletionAnswer): TCompletionPartialProc;
begin
  Result :=
    procedure(const AItems: TArray<TCompletionItem>)
    var
      mItems: TArray<TCompletionItem>;
    begin
      AAnswer.Cancellation.ThrowIfCancellationRequested;
      // Die vorab bestimmten Einträge kamen schon (#448).
      mItems := WithoutNames(AItems, AAnswer.Prefetched);
      if Length(mItems) > 0 then
      begin
        SendProgress(AAnswer, mItems);
      end;
    end;
end;

{ Fälle ohne Syntaxbaum }

function SlashCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mDisabled: TArray<string>;
begin
  mDisabled := nil;
  Result := AnsweredIf((not Assigned(AAnswer.Hooks.SlashCommandsFor) or
    AAnswer.Hooks.SlashCommandsFor(ARequest.Uri, mDisabled)) and
    TCompletionSlash.SlashItems(ARequest, mDisabled, AAnswer.Hooks.RuleIdsFor, AAnswer.Exclusive));
end;

function DirectiveCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mContext: TConditionalContext;
begin
  mContext := TConditionalContext.Default;
  if Assigned(AAnswer.Hooks.SymbolsFor) then
  begin
    mContext := AAnswer.Hooks.SymbolsFor(ARequest.Uri);
  end;
  Result := AnsweredIf(TCompletionSlash.SymbolItems(ARequest, mContext, AAnswer.Exclusive) or
    TCompletionSlash.DirectiveItems(ARequest, AAnswer.Exclusive));
  // Abgeschaltet (directives.completion): in der Direktive gar nichts, auch nicht die übrige Liste.
  if (Result = TCompletionOutcome.Answered) and not mContext.CompletionEnabled then
  begin
    AAnswer.Exclusive := Default(TCompletionItems);
  end;
end;

function DataNameCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionForms.DataNameItems(ARequest, AAnswer.Exclusive));
end;

/// <summary>Platzhalter in Wertdarstellungen (#854): in // atlas-debug: bzw. [AtlasDebugDisplay] nur die
/// Mitglieder des Typs.</summary>
function DebugDisplayCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionDebugDisplay.Items(ARequest, AAnswer.Exclusive));
end;

{ Fälle mit Baum und Resolver }

/// <summary>„Parameter abgleichen“ (#88): Strg+Leer in einem ///-Block, dessen Routine andere Parameter hat; dann
/// nur dieses Angebot (die Tags liefert das Plugin selbst).</summary>
function DocParamsCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItem: TCompletionItem;
begin
  Result := TCompletionOutcome.Next;
  if (not Assigned(AAnswer.Hooks.DocCommentsFor) or AAnswer.Hooks.DocCommentsFor(ARequest.Uri)) and
    DocParamsItem(ARequest, mItem) then
  begin
    Result := AnswerWith(AAnswer, mItem);
  end;
end;

/// <summary>String als resourcestring auslagern (#473): Strg+Leer im String-Literal; sonst bietet die Liste dort
/// nichts.</summary>
function ResourceStringCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionDeclarations.ResourceStringItems(ARequest, AAnswer.Hooks.SnippetSupport,
    AAnswer.Exclusive));
end;

/// <summary>Freigabe absichern (#489): Das Plugin fragt nach dem ";" bzw. dem Zeilenende (#10) hinter einem
/// übernommenen Konstruktor mit diesem Auslöser; dann gibt es nur dieses Angebot oder nichts.</summary>
function GuardCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := TCompletionOutcome.Next;
  if (ARequest.Trigger <> ';') and (ARequest.Trigger <> #10) then
  begin
    Exit;
  end;
  if not (ARequest.Settings.OfferTryFinally and TCompletionGuard.GuardItems(ARequest, ARequest.Trigger = #10,
    AAnswer.Exclusive)) then
  begin
    AAnswer.Exclusive := Default(TCompletionItems);
  end;
  Result := TCompletionOutcome.Answered;
end;

/// <summary>Anonyme Methoden (#468): Erwartet das Argument einen Methodenreferenztyp, nach "(" nur das Gerüst
/// (dort gibt es keine unbekannte Methode anzulegen), mit Strg+Leer ganz oben in der Liste.</summary>
function AnonymousCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItem: TCompletionItem;
begin
  Result := TCompletionOutcome.Next;
  if not TCompletionMethods.AnonymousItem(ARequest, AAnswer.Hooks.SnippetSupport, AAnswer.Hooks.NamingFor,
    mItem) then
  begin
    Exit;
  end;
  if ARequest.Trigger = '(' then
  begin
    Exit(AnswerWith(AAnswer, mItem));
  end;
  AAnswer.Hints := AAnswer.Hints + [mItem];
end;

/// <summary>Methode aus Aufruf anlegen (#472): Nach "(" (Auslöser des Plugins) gibt es nur dieses Angebot oder
/// nichts, mit Strg+Leer auf dem Namen eines Aufrufs steht es oben in der Liste.</summary>
function CreateCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItem: TCompletionItem;
  mFound: Boolean;
begin
  Result := TCompletionOutcome.Next;
  mFound := Assigned(AAnswer.Hooks.CreateFor) and CreateItem(ARequest, AAnswer.Hooks.CreateFor, mItem);
  if ARequest.Trigger = '(' then
  begin
    AAnswer.Exclusive := Default(TCompletionItems);
    if mFound then
    begin
      AAnswer.Exclusive.Items := [mItem];
    end;
    Result := TCompletionOutcome.Answered;
  end
  else if mFound then
  begin
    AAnswer.Hints := AAnswer.Hints + [mItem];
  end;
end;

/// <summary>with auflösen (#50): auf dem Wort with oben in der Liste, die übrige Liste bleibt.</summary>
function WithCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItem: TCompletionItem;
begin
  Result := TCompletionOutcome.Next;
  if Assigned(AAnswer.Hooks.WithFor) and WithItem(ARequest, AAnswer.Hooks.WithFor, mItem) then
  begin
    AAnswer.Hints := AAnswer.Hints + [mItem];
  end;
end;

/// <summary>Alle Felder zuweisen (#491): hinter "Ausdruck." am Anweisungsanfang ganz oben, die übrige Liste
/// bleibt.</summary>
function AssignAllCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItem: TCompletionItem;
begin
  Result := TCompletionOutcome.Next;
  if TCompletionValues.AssignAllItem(ARequest, AAnswer.Hooks.SnippetSupport, mItem) then
  begin
    AAnswer.Hints := AAnswer.Hints + [mItem];
  end;
end;

/// <summary>Namensvorschläge (#452): an der Namensposition einer Deklaration mit bekanntem Typ nur die Namen.
/// </summary>
function NameCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionNames.NameItems(ARequest, AAnswer.Hooks.NamingFor, AAnswer.Exclusive));
end;

/// <summary>Methoden überschreiben (#443) vor der allgemeinen Vervollständigung.</summary>
function OverrideCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionDeclarations.OverrideItems(ARequest, AAnswer.Exclusive));
end;

/// <summary>Property-Zugriffe (#31): nach read bzw. write nur passende Felder und Methoden.</summary>
function PropertyCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionDeclarations.PropertyItems(ARequest, AAnswer.Exclusive));
end;

/// <summary>Ereignis-Zuweisung (#444).</summary>
function EventCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionMethods.EventItems(ARequest, AAnswer.Exclusive));
end;

/// <summary>Interface implementieren (#466): auf leerer Zeile der Klasse nur die fehlenden Methoden mit
/// Kontrollkästchen; bei angefangenem Wort ein Hinweis oben in der normalen Liste.</summary>
function InterfaceCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItems: TArray<TCompletionItem>;
  mBatch: Boolean;
begin
  Result := TCompletionOutcome.Next;
  if not TCompletionDeclarations.InterfaceItems(ARequest, mItems, mBatch) then
  begin
    Exit;
  end;
  if mBatch then
  begin
    AAnswer.Exclusive := Default(TCompletionItems);
    AAnswer.Exclusive.Items := mItems;
    Exit(TCompletionOutcome.Answered);
  end;
  AAnswer.Hints := mItems;
end;

/// <summary>Aufzählungen und Mengen (#448): im Mengenkonstruktor nur dessen Werte; sonst die Werte des erwarteten
/// Aufzählungstyps vorab und vor der übrigen Liste. Atlas fragt bei "[" mit triggerCharacter: ohne Menge nichts.
/// </summary>
function EnumCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
begin
  Result := TCompletionOutcome.Next;
  if TCompletionValues.EnumItems(ARequest, mItems, mSetMode) then
  begin
    AAnswer.Prefetched := mItems;
  end;
  if mSetMode or (ARequest.Trigger = '[') then
  begin
    AAnswer.Exclusive := Default(TCompletionItems);
    if mSetMode then
    begin
      AAnswer.Exclusive.Items := AAnswer.Prefetched;
    end;
    Result := TCompletionOutcome.Answered;
  end;
end;

/// <summary>Komponenten aus dem Formular (#455) wie die Aufzählungswerte vorab und vor der übrigen Liste.
/// </summary>
function ComponentCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mItems: TArray<TCompletionItem>;
begin
  Result := TCompletionOutcome.Next;
  if TCompletionForms.ComponentItems(ARequest, AAnswer.Forms, mItems) then
  begin
    AAnswer.Prefetched := AAnswer.Prefetched + mItems;
  end;
end;

/// <summary>Postfix-Vorlagen je Dokument; gestaffelt (#616), wenn der Client einen partialResultToken
/// mitschickt: Teilergebnisse als $/progress mit CompletionItem[], die vorab bestimmten Einträge zuerst, der
/// Rest in der Antwort.</summary>
function PostfixCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := TCompletionOutcome.Next;
  AAnswer.Postfix := AAnswer.Hooks.PostfixOf(ARequest.Uri);
  if AAnswer.Token = '' then
  begin
    Exit;
  end;
  AAnswer.Partial := PartialSender(AAnswer);
  if Length(AAnswer.Prefetched) > 0 then
  begin
    SendProgress(AAnswer, AAnswer.Prefetched);
  end;
end;

/// <summary>Sender mit Typumwandlung (#480): statt der Mitglieder von TObject die des zugewiesenen
/// Komponententyps.</summary>
function SenderCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := AnsweredIf(TCompletionCases.SenderItems(ARequest, AAnswer.Forms, AAnswer.Exclusive));
end;

/// <summary>Die allgemeine Liste ohne die vorab bestimmten Namen; Schlüsselwörter abschaltbar (#31,
/// completion.keywords).</summary>
function ListCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mCollected: TCompletionItems;
begin
  Result := TCompletionOutcome.Next;
  mCollected := TCompletionLists.Collect(ARequest, AAnswer.Postfix, AAnswer.Partial);
  AAnswer.Body := WithoutNames(mCollected.Items, AAnswer.Prefetched);
  if not ARequest.Settings.Keywords then
  begin
    AAnswer.Body := WithoutKeywords(AAnswer.Body);
  end;
  AAnswer.Incomplete := mCollected.Incomplete;
end;

/// <summary>Kontextabhängige Code-Vorlagen (#51) am Ende der Liste.</summary>
function ContextCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
begin
  Result := TCompletionOutcome.Next;
  AAnswer.Tail := AAnswer.Tail + TCompletionLists.ContextItems(ARequest, AAnswer.Hooks.Namespaces,
    AAnswer.Hooks.SnippetSupport);
end;

/// <summary>Unbekannter Name (#471): Deklarieren am Ende. Die Einträge hängen am getippten Namen, deshalb neu
/// fragen.</summary>
function DeclareCase(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mDeclares: TArray<TCompletionItem>;
begin
  Result := TCompletionOutcome.Next;
  if TCompletionValues.DeclareItems(ARequest, AAnswer.Postfix.InlineVar, AAnswer.Prefetched + AAnswer.Body +
    AAnswer.Tail, mDeclares) then
  begin
    AAnswer.Tail := AAnswer.Tail + mDeclares;
    AAnswer.Incomplete := True;
  end;
end;

/// <summary>Hängt ACase an ACases an.</summary>
procedure AddCase(var ACases: TArray<TCompletionCase>; const ACase: TCompletionCase);
begin
  SetLength(ACases, Length(ACases) + 1);
  ACases[High(ACases)] := ACase;
end;

{ TCompletionCases }

class function TCompletionCases.TextCases: TArray<TCompletionCase>;
begin
  Result := nil;
  AddCase(Result, SlashCase);
  AddCase(Result, DirectiveCase);
  AddCase(Result, DataNameCase);
  AddCase(Result, DebugDisplayCase);
end;

class function TCompletionCases.TreeCases: TArray<TCompletionCase>;
begin
  Result := nil;
  AddCase(Result, DocParamsCase);
  AddCase(Result, ResourceStringCase);
  AddCase(Result, GuardCase);
  AddCase(Result, AnonymousCase);
  AddCase(Result, CreateCase);
  AddCase(Result, WithCase);
  AddCase(Result, AssignAllCase);
  AddCase(Result, NameCase);
  AddCase(Result, OverrideCase);
  AddCase(Result, PropertyCase);
  AddCase(Result, EventCase);
  AddCase(Result, InterfaceCase);
  AddCase(Result, EnumCase);
  AddCase(Result, ComponentCase);
  AddCase(Result, PostfixCase);
  AddCase(Result, SenderCase);
  AddCase(Result, ListCase);
  AddCase(Result, ContextCase);
  AddCase(Result, DeclareCase);
end;

class function TCompletionCases.Run(const ACases: TArray<TCompletionCase>; ARequest: TCompletionRequest;
  AAnswer: TCompletionAnswer): Boolean;
var
  mStep: TCompletionCase;
begin
  for mStep in ACases do
  begin
    if mStep(ARequest, AAnswer) = TCompletionOutcome.Answered then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCompletionCases.SenderItems(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TSenderSite;
  mRequest: TCompletionRequest;
  mPostfix: TPostfixOptions;
begin
  AItems := Default(TCompletionItems);
  Result := TCompletionForms.SenderSite(ARequest, AForms, mSite);
  if not Result then
  begin
    Exit;
  end;
  // Mitglieder wie bei "Sender: <Typ>": den umgeschriebenen Text neu zerlegen; die Position bleibt gleich.
  mRequest := TCompletionRequest.Create(mSite.PatchedText, ARequest.FileName, ARequest.Position);
  try
    mRequest.Tree := TSyntaxTreeCache.Parse(mSite.PatchedText);
    try
      mRequest.Resolver := ARequest.Resolver;
      mRequest.Index := ARequest.Index;
      mRequest.Matching := ARequest.Matching;
      mPostfix := TPostfixOptions.Default;
      mPostfix.Enabled := False;
      AItems := TCompletionLists.Collect(mRequest, mPostfix, nil);
    finally
      mRequest.Tree.Free;
    end;
  finally
    mRequest.Free;
  end;
  TCompletionForms.ApplySender(mSite, ARequest.Position, AItems);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion.Cases', cTexts);

end.
