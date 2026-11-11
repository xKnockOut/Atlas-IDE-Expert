unit Atlas.Common.Lsp.Completion.Forms;

// Vervollständigung aus der Formulardatei: Komponenten des Formulars (#455), "Sender." in Ereignisbehandlern
// (#480) und Feld- bzw. Parameternamen in FieldByName und Verwandten (#461). Dazu der Zugriff auf die
// Formulare mit und ohne Zwischenspeicher. Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Internals.FormCache,
  Atlas.Common.Lsp.CompletionRequest;

type
  /// <summary>Auszug des Formulars zur Unit ASourceFile mit dem Text ASourceText (#455, #480); False ohne
  /// Formular.</summary>
  TCompletionFormFunc = reference to function(const ASourceFile, ASourceText: string;
    out ASnapshot: TFormSnapshot): Boolean;

  /// <summary>"Sender." in einem Ereignisbehandler (#480): gemeinsamer Typ der Komponenten, deren Ereignis auf
  /// die Methode zeigt, und der Text mit "Sender: &lt;Typ&gt;" im Kopf der Methode.</summary>
  TSenderSite = record
    CommonType: string;
    /// <summary>Namen der Komponenten, je Objekt die erste Zuweisung.</summary>
    Names: TArray<string>;
    /// <summary>Dokumenttext mit umgeschriebenem Parameter; die Zeile des Cursors bleibt gleich.</summary>
    PatchedText: string;
    /// <summary>Umwandlung von Sender, etwa "(Sender as TButton)".</summary>
    Cast: string;
    /// <summary>Anfang von "Sender." in der Zeile des Cursors.</summary>
    ChainStart: TTextPosition;
  end;

  TCompletionForms = class
  public
    /// <summary>Formular zur Unit über AReadText, ohne Zwischenspeicher (für Aufrufer ohne Instanz, z. B. Tests);
    /// nil ohne AReadText.</summary>
    class function Uncached(const AReadText: TCompletionReadText): TCompletionFormFunc; static;
    /// <summary>Formular zur Unit über AReadText, zwischengespeichert in ACache je Stand der Formulardatei:
    /// offene Formulare (AStore) nach ihrem Text, Dateien nach der Dateizeit. False ohne AReadText.</summary>
    class function Cached(const AStore: IDocumentStore; const AReadText: TCompletionReadText;
      ACache: TFormSnapshotCache): TCompletionFormFunc; static;
    /// <summary>Komponenten des Formulars zur Unit (#455), wenn der Cursor ohne Punkt in einer Methode der
    /// Formularklasse steht. Quelle ist das Formular über AForms, also der Stand im Designer, solange es offen
    /// ist. Je Komponente ein Feld mit ihrem Typ als Detail und Form = Formularname. Passt der Name nicht zum
    /// Getippten, aber der Typ (eigene Klasse beginnt damit ohne "T", oder ein Vorfahr heißt genau so), kommt
    /// sie mit ByType. False ohne Formular oder außerhalb seiner Methoden; außerhalb von Routinen wird AForms
    /// nicht gerufen.</summary>
    class function ComponentItems(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
      out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>"Sender." in einem Ereignisbehandler mit "Sender: TObject" (#480), dessen Methode im Formular
    /// Komponenten zugewiesen ist: der nächste gemeinsame Vorfahr ihrer Typen. False ohne Zuweisung im
    /// Formular, bei bereits umgewandeltem Sender oder wenn der gemeinsame Typ TObject ist.</summary>
    class function SenderSite(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
      out ASite: TSenderSite): Boolean; static;
    /// <summary>Setzt in AItems den gemeinsamen Typ und die Komponenten aus ASite; Einträge ohne eigenes TextEdit
    /// ersetzen "Sender.Na" bis APosition durch die Umwandlung und den Namen.</summary>
    class procedure ApplySender(const ASite: TSenderSite; const APosition: TTextPosition;
      var AItems: TCompletionItems); static;
    /// <summary>Cursor im ersten Argument von FieldByName, FindField oder ParamByName an einer Datenmenge der
    /// Unit (#461): die Namen aus der Formulardatei (persistente Felder, Spalten der SQL-Anweisung,
    /// Platzhalter, Params). Jeder Eintrag ersetzt den ganzen String-Inhalt. True auch ohne Namen, denn im
    /// String gibt es sonst nichts vorzuschlagen.</summary>
    class function DataNameItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Editing.DataFieldNames,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Internals.CompletionSource;

const
  /// <summary>Höchstens so viele Komponenten prüfen, ob sie von hier aus als Feld sichtbar sind.</summary>
  cMaxProbes = 3;
  /// <summary>So viele Vorfahren einer Komponente höchstens verfolgen.</summary>
  cMaxAncestors = 32;
  /// <summary>So weit sucht Atlas nach oben nach dem Kopf der Methode.</summary>
  cMaxHeaderDistance = 2000;
  /// <summary>So viele Zeilen ab dem Kopf nach dem Parameter Sender.</summary>
  cMaxHeaderLines = 6;

type
  /// <summary>Woher Cached das Formular liest und wohin es den Auszug legt.</summary>
  TFormSource = record
    Store: IDocumentStore;
    ReadText: TCompletionReadText;
    Cache: TFormSnapshotCache;
  end;

/// <summary>Liegt APosition in ARange (Grenzen eingeschlossen)?</summary>
function RangeHas(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) <= 0);
end;

/// <summary>Innerste Routine aus AUnit (aus dem Baum), deren Bereich APosition enthält; lokale Prozeduren
/// stehen nicht im Index, daher ist das die umgebende Methode bzw. Routine.</summary>
function RoutineAt(const AUnit: TUnitIndex; const APosition: TTextPosition; out ARoutine: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  ARoutine := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) and
      RangeHas(mSymbol.Range, APosition) and
      (not Result or (mSymbol.Range.StartPos.Line >= ARoutine.Range.StartPos.Line)) then
    begin
      ARoutine := mSymbol;
      Result := True;
    end;
  end;
end;

/// <summary>Zerlegt AFormText; False, wenn die Datei kein Wurzelobjekt hat.</summary>
function ParseForm(const AFormFile, AFormText: string; out ASnapshot: TFormSnapshot): Boolean;
var
  mDocument: TDfmDocument;
begin
  ASnapshot := Default(TFormSnapshot);
  mDocument := TDfmParser.Parse(AFormText);
  try
    Result := mDocument.Root <> nil;
    if Result then
    begin
      ASnapshot := TFormSnapshotCache.FromDocument(AFormFile, mDocument);
    end;
  finally
    mDocument.Free;
  end;
end;

/// <summary>Stand der Formulardatei: Offene Formulare (Designer) über ihren Text – die
/// Versionsnummer beginnt nach Schließen und erneutem Öffnen wieder vorn –, Dateien auf der Platte über die
/// Dateizeit; '' ohne Stand. False, wenn sich ein offenes Formular nicht lesen lässt.</summary>
function FormStamp(const ASource: TFormSource; const AFormFile: string; out AFormText, AStamp: string): Boolean;
var
  mDocument: ITextDocument;
  mAge: TDateTime;
begin
  AFormText := '';
  AStamp := '';
  Result := True;
  if (ASource.Store <> nil) and ASource.Store.TryGet(TDocumentUris.FromPath(AFormFile), mDocument) then
  begin
    Result := ASource.ReadText(AFormFile, AFormText);
    if Result then
    begin
      AStamp := 'd' + AFormText;
    end;
  end
  else if FileAge(AFormFile, mAge) then
  begin
    AStamp := 't' + FloatToStr(mAge, TFormatSettings.Invariant);
  end;
end;

/// <summary>Auszug von AFormFile aus dem Zwischenspeicher oder neu gelesen; ohne Stand nicht gespeichert.
/// </summary>
function FormFileSnapshot(const ASource: TFormSource; const AFormFile: string;
  out ASnapshot: TFormSnapshot): Boolean;
var
  mFormText, mStamp: string;
begin
  ASnapshot := Default(TFormSnapshot);
  Result := False;
  if not FormStamp(ASource, AFormFile, mFormText, mStamp) then
  begin
    Exit;
  end;
  if (mStamp <> '') and ASource.Cache.TryGet(AFormFile, mStamp, ASnapshot) then
  begin
    Exit(True);
  end;
  if (mFormText = '') and not ASource.ReadText(AFormFile, mFormText) then
  begin
    Exit;
  end;
  Result := ParseForm(AFormFile, mFormText, ASnapshot);
  if Result and (mStamp <> '') then
  begin
    ASource.Cache.Put(AFormFile, mStamp, ASnapshot);
  end;
end;

/// <summary>Erstes lesbares Formular zur Unit, zwischengespeichert.</summary>
function CachedSnapshot(const ASource: TFormSource; const ASourceFile, ASourceText: string;
  out ASnapshot: TFormSnapshot): Boolean;
var
  mFormFile: string;
begin
  ASnapshot := Default(TFormSnapshot);
  Result := False;
  if not Assigned(ASource.ReadText) then
  begin
    Exit;
  end;
  for mFormFile in TFormFiles.FormFiles(ASourceFile, ASourceText) do
  begin
    if FormFileSnapshot(ASource, mFormFile, ASnapshot) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Erstes lesbares Formular zur Unit, ohne Zwischenspeicher.</summary>
function UncachedSnapshot(const AReadText: TCompletionReadText; const ASourceFile, ASourceText: string;
  out ASnapshot: TFormSnapshot): Boolean;
var
  mFormFile, mFormText: string;
begin
  ASnapshot := Default(TFormSnapshot);
  for mFormFile in TFormFiles.FormFiles(ASourceFile, ASourceText) do
  begin
    if AReadText(mFormFile, mFormText) and ParseForm(mFormFile, mFormText, ASnapshot) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Klassenname ohne führendes T.</summary>
function TypeWord(const ATypeName: string): string;
begin
  Result := ATypeName;
  if (Length(ATypeName) > 1) and CharInSet(ATypeName[1], ['T', 't']) then
  begin
    Result := Copy(ATypeName, 2, MaxInt);
  end;
end;

/// <summary>Ein Typ aus AChain heißt ohne "T" genau AWord.</summary>
function ChainHas(const AChain: TArray<string>; const AWord: string): Boolean;
var
  mName: string;
begin
  for mName in AChain do
  begin
    if SameText(TypeWord(mName), AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kontext am Cursor und Formular, wenn der Cursor ohne Punkt in einer Routine steht.</summary>
function FormAtRoutine(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
  out AContext: TCompletionContext; out AForm: TFormSnapshot): Boolean;
var
  mRoutine: TIndexSymbol;
begin
  AForm := Default(TFormSnapshot);
  AContext := Default(TCompletionContext);
  Result := False;
  if not Assigned(AForms) then
  begin
    Exit;
  end;
  AContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  // Komponenten gibt es nur in Routinen (Methoden der Formularklasse): außerhalb das Formular gar nicht
  // erst lesen.
  Result := (AContext.Kind = TCompletionContextKind.Scope) and
    RoutineAt(ARequest.UnitIndex, ARequest.Position, mRoutine) and AForms(ARequest.FileName, ARequest.Text, AForm);
end;

/// <summary>Sichtbar nur in Methoden der Formularklasse: eine der ersten Komponenten muss als deren Feld
/// auflösen.</summary>
function FormVisible(ARequest: TCompletionRequest; const AForm: TFormSnapshot; AOffset: Integer): Boolean;
var
  mIndex: Integer;
  mResolved: TResolvedSymbol;
begin
  for mIndex := 0 to Min(cMaxProbes, Length(AForm.Components)) - 1 do
  begin
    mResolved := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, [AForm.Components[mIndex].Name],
      AOffset);
    if mResolved.Found and (mResolved.SymbolKind = TIndexSymbolKind.Field) and
      SameText(mResolved.Container, AForm.RootType) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Namen der Vorfahren von ATypeName, je Typ einmal aufgelöst.</summary>
function AncestorChain(ARequest: TCompletionRequest; AAncestors: TDictionary<string, TArray<string>>;
  const ATypeName: string): TArray<string>;
var
  mType, mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  if AAncestors.TryGetValue(LowerCase(ATypeName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if ARequest.Resolver.ResolveTypeFrom(ARequest.UnitIndex, ATypeName, mType) then
  begin
    for mDepth := 1 to cMaxAncestors do
    begin
      if not ARequest.Resolver.AncestorOf(mType, mAncestor) then
      begin
        Break;
      end;
      Result := Result + [mAncestor.Name];
      mType := mAncestor;
    end;
  end;
  AAncestors.Add(LowerCase(ATypeName), Result);
end;

/// <summary>Suche über den Typ ab zwei Zeichen: eigene Klasse beginnt mit APrefix, oder ein Vorfahr heißt genau
/// so ("button" findet TButton und TBitBtn, aber nicht TCheckBox über TButtonControl).</summary>
function MatchesByType(ARequest: TCompletionRequest; AAncestors: TDictionary<string, TArray<string>>;
  const ATypeName, APrefix: string): Boolean;
begin
  Result := (Length(APrefix) >= 2) and (StartsText(APrefix, TypeWord(ATypeName)) or
    ChainHas(AncestorChain(ARequest, AAncestors, ATypeName), APrefix));
end;

/// <summary>Eintrag für AComponent des Formulars AForm.</summary>
function ComponentItem(ARequest: TCompletionRequest; const AForm: TFormSnapshot;
  const AComponent: TFormSnapshotComponent; const APrefix: string; AByType: Boolean): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := AComponent.Name;
  Result.Detail := AComponent.TypeName;
  Result.Kind := cKindField;
  Result.Container := AForm.RootType;
  Result.Scope := 3;
  Result.Form := AForm.RootName;
  Result.ByType := AByType;
  // Wie im Sammler (#882): Unscharfe Treffer und Treffer über den Typ bekommen das getippte Wort als
  // filterText, sonst verwirft ein Editor mit eigenem Präfixfilter (VS Code) alles ohne passenden Anfang.
  if (ARequest.Matching = TCompletionMatching.Fuzzy) and (APrefix <> '') and
    not AComponent.Name.StartsWith(APrefix, True) then
  begin
    Result.FilterText := APrefix;
  end;
end;

/// <summary>Kopf der umgebenden Methode "procedure TForm1.btnAnyClick(Sender: TObject);" oberhalb des Cursors:
/// aus dem Index; nur ohne passende Methode dort Zeile für Zeile nach oben.</summary>
function SenderHeader(ARequest: TCompletionRequest; const ALines: TArray<string>; out AHeaderLine: Integer;
  out AMethodName: string): Boolean;
var
  mRoutine: TIndexSymbol;
  mHeader: TRegEx;
  mMatch: TMatch;
  mLine: Integer;
begin
  AHeaderLine := -1;
  AMethodName := '';
  if RoutineAt(ARequest.UnitIndex, ARequest.Position, mRoutine) and (mRoutine.Container <> '') and
    (mRoutine.Range.StartPos.Line < ARequest.Position.Line) and (mRoutine.Range.StartPos.Line <= High(ALines)) then
  begin
    AHeaderLine := mRoutine.Range.StartPos.Line;
    AMethodName := mRoutine.Name;
    Exit(True);
  end;
  mHeader := TRegEx.Create('^\s*(class\s+)?(procedure|function)\s+[\w.]+\.(\w+)\s*[(;:]', [roIgnoreCase]);
  for mLine := Min(ARequest.Position.Line - 1, High(ALines)) downto
    Max(0, ARequest.Position.Line - cMaxHeaderDistance) do
  begin
    mMatch := mHeader.Match(ALines[mLine]);
    if mMatch.Success then
    begin
      AHeaderLine := mLine;
      AMethodName := mMatch.Groups[3].Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zeile mit "Sender: TObject" ab AHeaderLine vor ACursorLine; -1 ohne.</summary>
function SenderParamLine(const ALines: TArray<string>; AHeaderLine, ACursorLine: Integer;
  const ASenderParam: TRegEx): Integer;
var
  mLine: Integer;
begin
  for mLine := AHeaderLine to Min(AHeaderLine + cMaxHeaderLines - 1, ACursorLine - 1) do
  begin
    if ASenderParam.IsMatch(ALines[mLine]) then
    begin
      Exit(mLine);
    end;
  end;
  Result := -1;
end;

/// <summary>Komponenten, deren Ereignis im Formular auf AMethodName zeigt; je Objekt die erste Zuweisung.
/// </summary>
function HandlerTargets(const AForm: TFormSnapshot; const AMethodName: string; out ATypes,
  ANames: TArray<string>): Boolean;
var
  mHandler: TFormSnapshotHandler;
  mLastObject: Integer;
begin
  ATypes := nil;
  ANames := nil;
  mLastObject := -1;
  for mHandler in AForm.Handlers do
  begin
    if (mHandler.ObjectIndex <> mLastObject) and SameText(mHandler.MethodName, AMethodName) and
      (mHandler.TypeName <> '') then
    begin
      mLastObject := mHandler.ObjectIndex;
      ANames := ANames + [mHandler.ObjectName];
      if IndexText(mHandler.TypeName, ATypes) < 0 then
      begin
        ATypes := ATypes + [mHandler.TypeName];
      end;
    end;
  end;
  Result := Length(ATypes) > 0;
end;

/// <summary>Steht ACandidate in den Typketten aller ATypes ab dem zweiten?</summary>
function SharedByAll(ARequest: TCompletionRequest; const ATypes: TArray<string>; const ACandidate: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 1 to High(ATypes) do
  begin
    if IndexText(ACandidate, TypeChain(ARequest.Resolver, ARequest.UnitIndex, ATypes[mIndex])) < 0 then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Nächster gemeinsamer Vorfahr: der erste Typ in der Kette des ersten, den alle Ketten enthalten;
/// '' ohne.</summary>
function CommonAncestor(ARequest: TCompletionRequest; const ATypes: TArray<string>): string;
var
  mCandidate: string;
begin
  for mCandidate in TypeChain(ARequest.Resolver, ARequest.UnitIndex, ATypes[0]) do
  begin
    if SharedByAll(ARequest, ATypes, mCandidate) then
    begin
      Exit(mCandidate);
    end;
  end;
  Result := '';
end;

/// <summary>Umwandlung von ASender nach AType je nach completion.senderCast.</summary>
function SenderCast(ACast: TCompletionSenderCast; const AType, ASender: string): string;
begin
  if ACast = TCompletionSenderCast.HardCast then
  begin
    Result := AType + '(' + ASender + ')';
  end
  else
  begin
    Result := '(' + ASender + ' as ' + AType + ')';
  end;
end;

/// <summary>"Sender." mit genau diesem einen Namen vor dem Punkt?</summary>
function IsSenderContext(const AContext: TCompletionContext): Boolean;
begin
  Result := (AContext.Kind = TCompletionContextKind.Member) and (Length(AContext.Names) = 1) and
    SameText(AContext.Names[0], 'Sender');
end;

/// <summary>"Sender.Cap" → "(Sender as TButton).Caption".</summary>
procedure CastItem(const ASite: TSenderSite; const APosition: TTextPosition; var AItem: TCompletionItem);
var
  mName: string;
begin
  mName := AItem.InsertText;
  if mName = '' then
  begin
    mName := AItem.Name;
  end;
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(ASite.ChainStart, APosition), ASite.Cast + '.' + mName);
end;

{ TCompletionForms }

class function TCompletionForms.Uncached(const AReadText: TCompletionReadText): TCompletionFormFunc;
begin
  Result := nil;
  if not Assigned(AReadText) then
  begin
    Exit;
  end;
  Result :=
    function(const ASourceFile, ASourceText: string; out ASnapshot: TFormSnapshot): Boolean
    begin
      Result := UncachedSnapshot(AReadText, ASourceFile, ASourceText, ASnapshot);
    end;
end;

class function TCompletionForms.Cached(const AStore: IDocumentStore; const AReadText: TCompletionReadText;
  ACache: TFormSnapshotCache): TCompletionFormFunc;
var
  mSource: TFormSource;
begin
  mSource.Store := AStore;
  mSource.ReadText := AReadText;
  mSource.Cache := ACache;
  Result :=
    function(const ASourceFile, ASourceText: string; out ASnapshot: TFormSnapshot): Boolean
    begin
      Result := CachedSnapshot(mSource, ASourceFile, ASourceText, ASnapshot);
    end;
end;

class function TCompletionForms.ComponentItems(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
  out AItems: TArray<TCompletionItem>): Boolean;
var
  mContext: TCompletionContext;
  mForm: TFormSnapshot;
  mComponent: TFormSnapshotComponent;
  mAncestors: TDictionary<string, TArray<string>>;
  mItems: TList<TCompletionItem>;
  mByType: Boolean;
begin
  AItems := nil;
  if not FormAtRoutine(ARequest, AForms, mContext, mForm) or not FormVisible(ARequest, mForm, mContext.Offset) then
  begin
    Exit(False);
  end;
  mAncestors := TDictionary<string, TArray<string>>.Create;
  mItems := TList<TCompletionItem>.Create;
  try
    for mComponent in mForm.Components do
    begin
      mByType := MatchScore(mComponent.Name, mContext.Prefix, ARequest.Matching) = TFuzzyMatch.cNoMatch;
      if not mByType or MatchesByType(ARequest, mAncestors, mComponent.TypeName, mContext.Prefix) then
      begin
        // Liste statt AItems := AItems + [...].
        mItems.Add(ComponentItem(ARequest, mForm, mComponent, mContext.Prefix, mByType));
      end;
    end;
    AItems := mItems.ToArray;
  finally
    mItems.Free;
    mAncestors.Free;
  end;
  Result := Length(AItems) > 0;
end;

class function TCompletionForms.SenderSite(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
  out ASite: TSenderSite): Boolean;
var
  mContext: TCompletionContext;
  mLines, mTypes: TArray<string>;
  mHeaderLine, mParamLine: Integer;
  mMethodName: string;
  mForm: TFormSnapshot;
  mSenderParam: TRegEx;
begin
  ASite := Default(TSenderSite);
  Result := False;
  mContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  // Kopie: Die Zeile mit dem Parameter wird unten umgeschrieben.
  mLines := Copy(ARequest.Lines);
  if not IsSenderContext(mContext) or not Assigned(AForms) or
    not SenderHeader(ARequest, mLines, mHeaderLine, mMethodName) then
  begin
    Exit;
  end;
  // Muster je Aufruf übersetzen; lokal, weil die Vervollständigung nebenläufig läuft.
  mSenderParam := TRegEx.Create('\b(Sender\s*:\s*)TObject\b', [roIgnoreCase]);
  mParamLine := SenderParamLine(mLines, mHeaderLine, ARequest.Position.Line, mSenderParam);
  if (mParamLine < 0) or not AForms(ARequest.FileName, ARequest.Text, mForm) or
    not HandlerTargets(mForm, mMethodName, mTypes, ASite.Names) then
  begin
    Exit;
  end;
  ASite.CommonType := CommonAncestor(ARequest, mTypes);
  if (ASite.CommonType = '') or SameText(ASite.CommonType, 'TObject') then
  begin
    Exit;
  end;
  // Mitglieder wie bei "Sender: <Typ>": Parameter im Kopf umschreiben; die Zeile des Cursors bleibt gleich.
  mLines[mParamLine] := mSenderParam.Replace(mLines[mParamLine], '$1' + ASite.CommonType);
  ASite.PatchedText := string.Join(ARequest.LineBreak, mLines);
  ASite.Cast := SenderCast(ARequest.Settings.SenderCast, ASite.CommonType, mContext.Names[0]);
  ASite.ChainStart := mContext.ChainStart;
  Result := True;
end;

class procedure TCompletionForms.ApplySender(const ASite: TSenderSite; const APosition: TTextPosition;
  var AItems: TCompletionItems);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems.Items) do
  begin
    AItems.Items[mIndex].Sender := ASite.CommonType;
    AItems.Items[mIndex].SenderOf := string.Join(', ', ASite.Names);
    if not AItems.Items[mIndex].HasTextEdit then
    begin
      CastItem(ASite, APosition, AItems.Items[mIndex]);
    end;
  end;
end;

/// <summary>Eintrag für den Namen AName aus der Formulardatei.</summary>
function DataNameItem(const ACall: TDataNameCall; const AName: TDataName; const ARange: TTextRange;
  const ASource: string): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := AName.Name;
  Result.Detail := AName.TypeName;
  Result.Kind := cKindField;
  if ACall.Kind = TDataNameKind.Param then
  begin
    Result.Kind := cKindVariable;
  end;
  // Schreibweise wie in der Quelle; ersetzt den ganzen Inhalt zwischen den Anführungszeichen.
  Result.HasTextEdit := True;
  Result.TextEdit := TRuleEdit.Create(ARange, StringReplace(AName.Name, '''', '''''', [rfReplaceAll]));
  Result.DataSet := ACall.DisplayName;
  Result.DataSource := ASource;
end;

class function TCompletionForms.DataNameItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  mLines: TArray<string>;
  mCall: TDataNameCall;
  mSql, mSource: string;
  mNames: TArray<TDataName>;
  mName: TDataName;
  mFound: Boolean;
  mRange: TTextRange;
begin
  AItems := Default(TCompletionItems);
  mLines := ARequest.Lines;
  if (ARequest.Position.Line < 0) or (ARequest.Position.Line > High(mLines)) or
    not TDataFieldNames.CallAt(mLines[ARequest.Position.Line], ARequest.Position.Character, mCall) then
  begin
    Exit(False);
  end;
  Result := True;
  if not Assigned(ARequest.ReadText) then
  begin
    Exit;
  end;
  // Nur aus der Formulardatei: Ohne Designer-Informationen kein geratener Vorschlag.
  mNames := TDataFieldNames.Lookup(TDataLookupSource.Create(ARequest.Text, ARequest.FileName, ARequest.Index,
    function(const AName: string; out AContent: string): Boolean
    begin
      Result := ARequest.ReadText(AName, AContent);
    end), mCall, mSql, mFound);
  mSource := TDataFieldNames.ShortSql(mSql);
  mRange := TTextRange.Create(ARequest.Position.Line, mCall.ContentStart, ARequest.Position.Line, mCall.ContentEnd);
  for mName in mNames do
  begin
    AItems.Items := AItems.Items + [DataNameItem(mCall, mName, mRange, mSource)];
  end;
end;

end.
