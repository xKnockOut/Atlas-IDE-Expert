unit Atlas.Common.Lsp.Completion.Details;

// Details zu einer Deklaration für completionItem/resolve und das Detailpanel von Atlas (#405, #424, #654):
// Deklaration, Unit, Container, Sichtbarkeit, Direktiven und XMLDoc. Dazu die Doku im Format, das der Client
// wünscht (#31). Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionDetails = class
  public
    /// <summary>Details zur Deklaration an APosition (Namensposition) in AText für das Detailpanel
    /// von Atlas (#405, #424): declaration, unit, container, visibility, directives, deprecated,
    /// summary, params, returns, exceptions, remarks als Klartext, dazu documentation strukturiert
    /// samt Fundorten der Verweise und documentationText (#654). AReadText liest andere Dateien
    /// für &lt;inheritdoc/&gt;. Der Aufrufer übernimmt das Objekt.</summary>
    class function Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText): TJSONObject; overload; static;
    /// <summary>Wie oben mit AReadText = nil.</summary>
    class function Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
      const APosition: TTextPosition): TJSONObject; overload; static;
    /// <summary>Gebundene Typparameter (#450): setzt "T=TKunde" wortweise in die declaration von ADetails ein.
    /// </summary>
    class procedure Bind(ADetails: TJSONObject; const ABindings: TArray<string>); static;
    /// <summary>completionItem.documentationFormat aus initialize (#31): True, wenn der Client Markdown zuerst
    /// nennt; RAD Studio meldet nur plaintext.</summary>
    class function ClientPrefersMarkdown(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>documentation für completionItem/resolve aus Details: Markdown als MarkupContent, sonst Klartext
    /// (ganzer XMLDoc-Text, ersatzweise der Kurztext); nil ohne Doku.</summary>
    class function ResolveDocumentation(const ADetails: TJSONObject; AMarkdown: Boolean): TJSONValue; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Files,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.Completion.Context;

const
  cDirectives: array[0..13] of string = ('class', 'static', 'virtual', 'dynamic', 'override', 'abstract', 'final',
    'reintroduce', 'overload', 'inline', 'message', 'deprecated', 'platform', 'experimental');
  cClassMembers: array[0..6] of string = ('function', 'procedure', 'property', 'operator', 'constructor',
    'destructor', 'var');
  cVisibilities: array[TIndexVisibility] of string = ('public', 'published', 'protected', 'strict protected',
    'private', 'strict private');
  cDocumentationPath: array[0..4] of string = ('capabilities', 'textDocument', 'completion', 'completionItem',
    'documentationFormat');

type
  /// <summary>Die Deklaration, zu der Details gefragt sind.</summary>
  TDetailsSite = record
    Index: ISymbolIndex;
    FileName: string;
    Text: string;
    ReadText: TCompletionReadText;
    Lines: TArray<string>;
    HasUnit: Boolean;
    UnitInfo: TUnitIndex;
    /// <summary>Im Index gefunden; sonst (lokale Variable, Parameter) nur die Zeile ab dem Namen.</summary>
    Found: Boolean;
    Symbol: TIndexSymbol;
    Range: TTextRange;
  end;

/// <summary>Text ohne String-Inhalte (Leerzeichen dafür), damit Wörter darin nicht zählen; ADeprecated: Text
/// des Strings hinter deprecated.</summary>
function MaskStrings(const ADeclaration: string; out ADeprecated: string): string;
var
  mIndex, mQuote: Integer;
begin
  Result := '';
  ADeprecated := '';
  mIndex := 1;
  while mIndex <= Length(ADeclaration) do
  begin
    if ADeclaration[mIndex] <> '''' then
    begin
      Result := Result + ADeclaration[mIndex];
      Inc(mIndex);
      Continue;
    end;
    mQuote := PosEx('''', ADeclaration, mIndex + 1);
    if mQuote = 0 then
    begin
      mQuote := Length(ADeclaration);
    end;
    if EndsText('deprecated', TrimRight(Result)) then
    begin
      ADeprecated := Copy(ADeclaration, mIndex + 1, mQuote - mIndex - 1);
    end;
    Result := Result + ' ';
    mIndex := mQuote + 1;
  end;
end;

/// <summary>Wörter aus Buchstaben, Ziffern und _ in AText, klein geschrieben.</summary>
function WordsOf(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mStart := 0;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      if mIndex - 1 > mStart then
      begin
        Result := Result + [LowerCase(Copy(AText, mStart + 1, mIndex - 1 - mStart))];
      end;
      mStart := mIndex;
    end;
  end;
end;

/// <summary>Ist AWords[AIndex] eine Direktive? "class" nur am Anfang vor einer Methode o. Ä. (class function),
/// sonst wäre jeder Klassentyp eine Klassenmethode.</summary>
function IsDirective(const AWords: TArray<string>; AIndex: Integer): Boolean;
begin
  Result := MatchStr(AWords[AIndex], cDirectives);
  if Result and (AWords[AIndex] = 'class') then
  begin
    Result := (AIndex = 0) and (High(AWords) >= 1) and MatchStr(AWords[1], cClassMembers);
  end;
end;

/// <summary>Direktiven einer Deklaration (virtual, override, deprecated ...); ADeprecated: Text
/// hinter deprecated, '' ohne Text; AIsDeprecated: deprecated kommt vor.</summary>
function DirectivesOf(const ADeclaration: string; out ADeprecated: string; out AIsDeprecated: Boolean): TArray<string>;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mWords := WordsOf(MaskStrings(ADeclaration, ADeprecated));
  for mIndex := 0 to High(mWords) do
  begin
    if IsDirective(mWords, mIndex) and (IndexStr(mWords[mIndex], Result) < 0) then
    begin
      Result := Result + [mWords[mIndex]];
    end;
  end;
  AIsDeprecated := IndexStr('deprecated', Result) >= 0;
end;

/// <summary>Sucht die Deklaration an APosition. Auch für Include-Dateien (#500): Unit, die sie einbindet;
/// Symbole nur aus dieser Datei.</summary>
procedure FindSymbol(var ASite: TDetailsSite; const APosition: TTextPosition);
var
  mCandidate: TIndexSymbol;
begin
  ASite.HasUnit := TIndexFiles.UnitOf(ASite.Index, ASite.FileName, ASite.UnitInfo);
  ASite.Range := TTextRange.Create(APosition, APosition);
  if not ASite.HasUnit then
  begin
    Exit;
  end;
  for mCandidate in ASite.UnitInfo.Symbols do
  begin
    if (ComparePositions(mCandidate.SelectionRange.StartPos, APosition) = 0) and
      SameText(ASite.UnitInfo.SymbolFile(mCandidate), ASite.FileName) then
    begin
      ASite.Symbol := mCandidate;
      ASite.Found := True;
      ASite.Range := mCandidate.Range;
      Exit;
    end;
  end;
end;

/// <summary>container, visibility und helper (#456: Das Panel zeigt dann „Helper · Unit“).</summary>
procedure AddContainer(AResult: TJSONObject; const ASite: TDetailsSite);
var
  mCandidate: TIndexSymbol;
begin
  if not ASite.Found or (ASite.Symbol.Container = '') then
  begin
    Exit;
  end;
  AResult.AddPair('container', ASite.Symbol.Container);
  AResult.AddPair('visibility', cVisibilities[ASite.Symbol.Visibility]);
  for mCandidate in ASite.UnitInfo.Symbols do
  begin
    if (mCandidate.Kind = TIndexSymbolKind.HelperType) and
      SameText(mCandidate.QualifiedName, ASite.Symbol.Container) then
    begin
      AResult.AddPair('helper', TJSONBool.Create(True));
      Exit;
    end;
  end;
end;

/// <summary>directives und deprecated aus ADeclaration.</summary>
procedure AddDirectives(AResult: TJSONObject; const ADeclaration: string);
var
  mDirectives: TArray<string>;
  mDirective, mDeprecated: string;
  mIsDeprecated: Boolean;
  mList: TJSONArray;
begin
  mDirectives := DirectivesOf(ADeclaration, mDeprecated, mIsDeprecated);
  if Length(mDirectives) > 0 then
  begin
    mList := TJSONArray.Create;
    for mDirective in mDirectives do
    begin
      mList.Add(mDirective);
    end;
    AResult.AddPair('directives', mList);
  end;
  if mIsDeprecated then
  begin
    AResult.AddPair('deprecated', mDeprecated);
  end;
end;

/// <summary>XMLDoc wie im Hover (#654): mit &lt;inheritdoc/&gt; und den Fundorten der cref-Verweise;
/// documentation, documentationText und documentationMarkdown in AResult.</summary>
function AddDocumentation(AResult: TJSONObject; const ASite: TDetailsSite): TXmlDoc;
var
  mResolver: TNameResolver;
  mContainer: string;
  mTargets: TArray<TDocTarget>;
begin
  mResolver := TNameResolver.Create(ASite.Index);
  try
    mTargets := nil;
    if ASite.Found then
    begin
      Result := TLspDocumentation.Load(mResolver, TResolvedSymbol.FromIndex(ASite.UnitInfo, ASite.Symbol),
        ASite.Lines, ASite.Range.StartPos.Line, TLspDocumentation.Reader(ASite.FileName, ASite.Text,
        ASite.ReadText));
      mContainer := ASite.Symbol.Container;
      if mContainer = '' then
      begin
        mContainer := ASite.Symbol.Name;
      end;
      if not Result.IsEmpty then
      begin
        mTargets := TLspDocumentation.Targets(mResolver, ASite.UnitInfo, mContainer, Result);
      end;
    end
    else
    begin
      Result := TXmlDoc.Parse(TXmlDoc.CommentAbove(ASite.Lines, ASite.Range.StartPos.Line));
    end;
  finally
    mResolver.Free;
  end;
  if Result.IsEmpty then
  begin
    Exit;
  end;
  AResult.AddPair('documentation', TLspDocumentation.ToJson(Result, mTargets));
  AResult.AddPair('documentationText', Result.ToPlainText);
  // Nur für documentation in completionItem/resolve; HandleResolve nimmt es wieder heraus.
  AResult.AddPair('documentationMarkdown', Result.ToMarkdown);
end;

/// <summary>[{"name", "text"}] aus AEntries.</summary>
function EntriesJson(const AEntries: TArray<TXmlDocEntry>): TJSONArray;
var
  mEntry: TXmlDocEntry;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mEntry in AEntries do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mEntry.Name);
    mItem.AddPair('text', mEntry.Text);
    Result.AddElement(mItem);
  end;
end;

/// <summary>Setzt AValue unter AName, wenn es nicht leer ist.</summary>
procedure AddText(AResult: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AResult.AddPair(AName, AValue);
  end;
end;

/// <summary>summary, returns, remarks, params und exceptions als Klartext.</summary>
procedure AddDocFields(AResult: TJSONObject; const ADoc: TXmlDoc);
begin
  AddText(AResult, 'summary', ADoc.Summary);
  AddText(AResult, 'returns', ADoc.Returns);
  AddText(AResult, 'remarks', ADoc.Remarks);
  if Length(ADoc.Params) > 0 then
  begin
    AResult.AddPair('params', EntriesJson(ADoc.Params));
  end;
  if Length(ADoc.Exceptions) > 0 then
  begin
    AResult.AddPair('exceptions', EntriesJson(ADoc.Exceptions));
  end;
end;

{ TCompletionDetails }

class function TCompletionDetails.Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
  const APosition: TTextPosition): TJSONObject;
begin
  Result := Details(AIndex, AFileName, AText, APosition, nil);
end;

class function TCompletionDetails.Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText): TJSONObject;
var
  mSite: TDetailsSite;
  mDeclaration: string;
begin
  mSite := Default(TDetailsSite);
  mSite.Index := AIndex;
  mSite.FileName := AFileName;
  mSite.Text := AText;
  mSite.ReadText := AReadText;
  mSite.Lines := TextLines(AText);
  FindSymbol(mSite, APosition);
  Result := TJSONObject.Create;
  if mSite.HasUnit then
  begin
    Result.AddPair('unit', mSite.UnitInfo.UnitName);
  end;
  mDeclaration := TInterfaceStubs.DeclarationOf(mSite.Lines, mSite.Range);
  AddText(Result, 'declaration', mDeclaration);
  AddContainer(Result, mSite);
  AddDirectives(Result, mDeclaration);
  AddDocFields(Result, AddDocumentation(Result, mSite));
end;

class procedure TCompletionDetails.Bind(ADetails: TJSONObject; const ABindings: TArray<string>);
var
  mText: string;
begin
  if (Length(ABindings) > 0) and ADetails.TryGetValue<string>('declaration', mText) then
  begin
    ADetails.RemovePair('declaration').Free;
    ADetails.AddPair('declaration', TInterfaceStubs.SubstituteWords(mText, ABindings));
  end;
end;

class function TCompletionDetails.ClientPrefersMarkdown(const AInitializeParams: TJSONObject): Boolean;
var
  mNode: TJSONValue;
  mKey: string;
begin
  Result := False;
  mNode := AInitializeParams;
  for mKey in cDocumentationPath do
  begin
    if not (mNode is TJSONObject) then
    begin
      Exit;
    end;
    mNode := TJSONObject(mNode).GetValue(mKey);
  end;
  Result := (mNode is TJSONArray) and (TJSONArray(mNode).Count > 0) and
    (TJSONArray(mNode).Items[0] is TJSONString) and SameText(TJSONString(TJSONArray(mNode).Items[0]).Value, 'markdown');
end;

class function TCompletionDetails.ResolveDocumentation(const ADetails: TJSONObject; AMarkdown: Boolean): TJSONValue;
var
  mText: string;
  mMarkup: TJSONObject;
begin
  Result := nil;
  if ADetails = nil then
  begin
    Exit;
  end;
  if AMarkdown and ADetails.TryGetValue<string>('documentationMarkdown', mText) and (mText <> '') then
  begin
    mMarkup := TJSONObject.Create;
    mMarkup.AddPair('kind', 'markdown');
    mMarkup.AddPair('value', mText);
    Exit(mMarkup);
  end;
  // Klartext (RAD Studio: documentationFormat ["plaintext"]): ganzer Text, sonst der Kurztext.
  if (ADetails.TryGetValue<string>('documentationText', mText) and (mText <> '')) or
    (ADetails.TryGetValue<string>('summary', mText) and (mText <> '')) then
  begin
    Result := TJSONString.Create(mText);
  end;
end;

end.
