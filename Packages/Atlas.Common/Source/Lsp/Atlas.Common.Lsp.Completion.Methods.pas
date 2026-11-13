unit Atlas.Common.Lsp.Completion.Methods;

// Vervollständigung für Methodenzeiger und Methodenreferenzen: passende Methoden und „Neue Methode …“ nach
// "Objekt.Ereignis := " (#444) und das Gerüst einer anonymen Methode, wo ein Methodenreferenztyp erwartet
// wird (#468). Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionAnonymous,
  Atlas.Common.Lsp.Completion.Names;

type
  TCompletionMethods = class
  public
    /// <summary>Nach "Objekt.Ereignis := " (#444): Methoden der umgebenden Klasse, deren Parameter zum
    /// Methodenzeigertyp des Ereignisses passen, zuletzt "Neue Methode …" mit Deklaration im private-Abschnitt
    /// und leerem Rumpf. False außerhalb dieses Kontexts.</summary>
    class function EventItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Methodenreferenztyp ATypeText, so aufgelöst, wie er in AFromUnit stünde (#468): Deklaration aus
    /// dem Index, Aliase bis TCompletionAnonymous.cMaxAliasDepth verfolgt, Typparameter durch die Typargumente
    /// ersetzt; ohne Deklaration im Index die von System.SysUtils (TProc, TFunc, TPredicate). False, wenn
    /// ATypeText kein "reference to procedure/function" ist.</summary>
    class function MethodRefOf(AResolver: TNameResolver; const AFromUnit: TUnitIndex; const ATypeText: string;
      out AMethodRef: TMethodRef): Boolean; static;
    /// <summary>Gerüst einer anonymen Methode (#468), wenn das Argument bzw. die Zuweisung am Cursor einen
    /// Methodenreferenztyp erwartet und completion.anonymousMethods gilt; der Cursor steht ohne Wort oder hinter
    /// einem Anfang von procedure bzw. function. Mit ASnippets im Platzhalter-Modus. Das Präfix der Parameter
    /// kommt aus ANamingFor bzw. TCompletionNames.NamingPrefix.</summary>
    class function AnonymousItem(ARequest: TCompletionRequest; ASnippets: Boolean;
      const ANamingFor: TCompletionNamingFunc; out AItem: TCompletionItem): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.TypeConversions,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Lines;

type
  /// <summary>Texte der Methoden-Vervollständigung in beiden Sprachen (#1458).</summary>
  TMethodsText = (NewMethod, AnonymousMethod);

const
  cTexts: array[TMethodsText] of TAtlasText = (
    (De: 'Neue Methode %s …'; En: 'New method %s …'),
    (De: 'anonyme Methode'; En: 'anonymous method'));

type
  /// <summary>Zuweisung "Objekt.Ereignis := Anfang" am Cursor.</summary>
  TEventTarget = record
    /// <summary>Namenskette bis zum Ereignis, etwa ["btnSave", "OnClick"].</summary>
    Names: TArray<string>;
    EventName: string;
    Prefix: string;
    Offset: Integer;
  end;

  /// <summary>Signatur des Methodenzeigertyps eines Ereignisses.</summary>
  TEventSignature = record
    TypeName: string;
    Kind: string;
    Params: string;
    ResultType: string;
    ParamTypes: TArray<string>;
  end;

/// <summary>Typen der Parameter aus "const A, B: T; var C: U; D" in Reihenfolge; untypisiert ''.</summary>
function EventParamTypes(const AParams: string): TArray<string>;
var
  mGroup, mNames, mTypeText: string;
  mIndex: Integer;
begin
  Result := nil;
  for mGroup in AParams.Split([';']) do
  begin
    if Trim(mGroup) = '' then
    begin
      Continue;
    end;
    mNames := mGroup;
    mTypeText := '';
    if Pos(':', mGroup) > 0 then
    begin
      mNames := Copy(mGroup, 1, Pos(':', mGroup) - 1);
      mTypeText := Copy(mGroup, Pos(':', mGroup) + 1, MaxInt);
      if Pos('=', mTypeText) > 0 then
      begin
        mTypeText := Copy(mTypeText, 1, Pos('=', mTypeText) - 1);
      end;
    end;
    for mIndex := 1 to Length(mNames.Split([','])) do
    begin
      Result := Result + [Trim(mTypeText)];
    end;
  end;
end;

/// <summary>"btnSave.OnClick := btn|", "OnClick := |"; nicht "A.B := " in Ausdrücken mit "=" davor.</summary>
function EventTargetAt(ARequest: TCompletionRequest; out ATarget: TEventTarget): Boolean;
var
  mMatch: TMatch;
  mName: string;
begin
  ATarget := Default(TEventTarget);
  mMatch := TRegEx.Match(ARequest.LineBefore, '(?:^|[^\w.&])((?:&?\w+\.)*)&?(\w+)\s*:=\s*(\w*)$');
  Result := mMatch.Success;
  if not Result then
  begin
    Exit;
  end;
  ATarget.Prefix := mMatch.Groups[3].Value;
  ATarget.EventName := mMatch.Groups[2].Value;
  for mName in mMatch.Groups[1].Value.Split(['.']) do
  begin
    if mName <> '' then
    begin
      ATarget.Names := ATarget.Names + [CleanName(mName)];
    end;
  end;
  ATarget.Names := ATarget.Names + [ATarget.EventName];
  ATarget.Offset := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position).Offset;
end;

/// <summary>Methodenzeigertyp des Ereignisses auflösen: wie im Quelltext, sonst über die Unit der Eigenschaft.
/// </summary>
function EventTypeOf(ARequest: TCompletionRequest; const ATarget: TEventTarget;
  out AEventType: TResolvedSymbol): Boolean;
var
  mEvent: TResolvedSymbol;
  mTypeNames: TArray<string>;
begin
  AEventType := Default(TResolvedSymbol);
  mEvent := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, ATarget.Names, ATarget.Offset);
  if not mEvent.Found or not (mEvent.SymbolKind in [TIndexSymbolKind.Property_, TIndexSymbolKind.Field,
    TIndexSymbolKind.Variable]) or (mEvent.TypeName = '') then
  begin
    Exit(False);
  end;
  mTypeNames := mEvent.TypeName.Split(['.']);
  AEventType := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, mTypeNames, ATarget.Offset);
  if not AEventType.Found and (mEvent.UnitName <> '') then
  begin
    AEventType := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName,
      mEvent.UnitName.Split(['.']) + mTypeNames, ATarget.Offset);
  end;
  Result := AEventType.Found and (AEventType.FileName <> '');
end;

/// <summary>Text der Datei, in der AEventType steht.</summary>
function SourceOf(ARequest: TCompletionRequest; const AEventType: TResolvedSymbol; out ASource: string): Boolean;
begin
  ASource := '';
  Result := True;
  if SameText(AEventType.FileName, ARequest.FileName) then
  begin
    ASource := ARequest.Text;
  end
  else
  begin
    Result := Assigned(ARequest.ReadText) and ARequest.ReadText(AEventType.FileName, ASource);
  end;
end;

/// <summary>Signatur aus der Deklaration "TNotifyEvent = procedure(Sender: TObject) of object;"; nur
/// Methodenzeiger und Methodenreferenzen.</summary>
function SignatureOf(const ADeclaration: string; out ASignature: TEventSignature): Boolean;
var
  mMatch: TMatch;
begin
  ASignature := Default(TEventSignature);
  mMatch := TRegEx.Match(ADeclaration,
    '=\s*(reference\s+to\s+)?(procedure|function)\s*(?:\((.*)\))?\s*(?::\s*([\w.<>, ]+?))?\s*(of\s+object)?\s*;',
    [roIgnoreCase]);
  Result := mMatch.Success and ((mMatch.Groups[1].Length > 0) or (mMatch.Groups[5].Length > 0));
  if not Result then
  begin
    Exit;
  end;
  ASignature.Kind := LowerCase(mMatch.Groups[2].Value);
  ASignature.Params := Trim(mMatch.Groups[3].Value);
  ASignature.ResultType := Trim(mMatch.Groups[4].Value);
  ASignature.ParamTypes := EventParamTypes(ASignature.Params);
end;

/// <summary>Signatur des Ereignisses an ATarget.</summary>
function EventSignatureOf(ARequest: TCompletionRequest; const ATarget: TEventTarget;
  out ASignature: TEventSignature): Boolean;
var
  mEventType: TResolvedSymbol;
  mSource: string;
begin
  ASignature := Default(TEventSignature);
  Result := EventTypeOf(ARequest, ATarget, mEventType) and SourceOf(ARequest, mEventType, mSource) and
    SignatureOf(TInterfaceStubs.DeclarationOf(TextLines(mSource), mEventType.Range), ASignature);
  ASignature.TypeName := mEventType.Name;
end;

/// <summary>Umgebende Klasse: Methodenrumpf, in dem der Cursor steht; '' ohne.</summary>
function EnclosingClassOf(ARequest: TCompletionRequest): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in ARequest.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and (mSymbol.Container <> '') and
      (mSymbol.Range.StartPos.Line < ARequest.Position.Line) and
      (mSymbol.Range.EndPos.Line >= ARequest.Position.Line) then
    begin
      Result := mSymbol.Container;
    end;
  end;
end;

/// <summary>Passen Art, Ergebnis und Parametertypen von ACandidate zu ASignature?</summary>
function MethodFits(const ACandidate: TResolvedSymbol; const ASignature: TEventSignature): Boolean;
var
  mIsFunction: Boolean;
  mIndex: Integer;
begin
  mIsFunction := ASignature.Kind = 'function';
  Result := (ACandidate.SymbolKind = TIndexSymbolKind.Method) and
    (Length(ACandidate.ParamTypes) = Length(ASignature.ParamTypes)) and (mIsFunction = (ACandidate.TypeName <> ''));
  if Result and mIsFunction then
  begin
    Result := PlainType(ACandidate.TypeName) = PlainType(ASignature.ResultType);
  end;
  for mIndex := 0 to High(ASignature.ParamTypes) do
  begin
    Result := Result and (PlainType(ACandidate.ParamTypes[mIndex]) = PlainType(ASignature.ParamTypes[mIndex]));
  end;
end;

/// <summary>Eintrag für die passende Methode ACandidate.</summary>
function FittingItem(const ACandidate: TResolvedSymbol; const AExpected: string): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACandidate.Name;
  Result.Kind := cKindMethod;
  Result.Detail := ACandidate.Container;
  Result.Container := ACandidate.Container;
  Result.Depth := ACandidate.Depth;
  Result.SourceFile := ACandidate.FileName;
  Result.SourcePosition := ACandidate.SelectionRange.StartPos;
  Result.Expected := AExpected;
  Result.Fits := True;
end;

/// <summary>Passende Methoden der Klasse samt geerbter; merkt alle Mitglieder in ATaken.</summary>
function FittingItems(ARequest: TCompletionRequest; const ATarget: TEventTarget; const ASignature: TEventSignature;
  ATaken: TDictionary<string, Boolean>): TArray<TCompletionItem>;
var
  mCandidate: TResolvedSymbol;
begin
  Result := nil;
  for mCandidate in ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName, ['Self'],
    ATarget.Offset) do
  begin
    ATaken.AddOrSetValue(LowerCase(mCandidate.Name), True);
    if MethodFits(mCandidate, ASignature) then
    begin
      Result := Result + [FittingItem(mCandidate, ASignature.TypeName)];
    end;
  end;
end;

/// <summary>Name der neuen Methode: Objekt + Ereignis ohne "On" (btnSave.OnClick → btnSaveClick).</summary>
function NewMethodBase(const ATarget: TEventTarget; const ATypeName: string): string;
begin
  if (Length(ATarget.Names) > 1) and not SameText(ATarget.Names[High(ATarget.Names) - 1], 'Self') then
  begin
    Result := ATarget.Names[High(ATarget.Names) - 1];
  end
  else if StartsText('T', ATypeName) and (Pos('.', ATypeName) = 0) then
  begin
    Result := Copy(ATypeName, 2, MaxInt);
  end
  else
  begin
    Result := ATypeName.Substring(ATypeName.LastIndexOf('.') + 1);
  end;
  if StartsText('On', ATarget.EventName) then
  begin
    Result := Result + Copy(ATarget.EventName, 3, MaxInt);
  end
  else
  begin
    Result := Result + ATarget.EventName;
  end;
end;

/// <summary>ABase, mit Ziffer eindeutig gemacht gegenüber ATaken.</summary>
function UniqueName(const ABase: string; ATaken: TDictionary<string, Boolean>): string;
var
  mNumber: Integer;
begin
  Result := ABase;
  mNumber := 1;
  while ATaken.ContainsKey(LowerCase(Result)) do
  begin
    Inc(mNumber);
    Result := ABase + IntToStr(mNumber);
  end;
end;

/// <summary>Kopf der neuen Methode "procedure TForm1.btnSaveClick(Sender: TObject)".</summary>
function NewMethodHeader(const ASignature: TEventSignature; const ATypeName, AName: string): string;
begin
  Result := ASignature.Kind + ' ' + ATypeName + '.' + AName;
  if ASignature.Params <> '' then
  begin
    Result := Result + '(' + ASignature.Params + ')';
  end;
  if ASignature.Kind = 'function' then
  begin
    Result := Result + ': ' + ASignature.ResultType;
  end;
end;

/// <summary>„Neue Methode …“ mit Deklaration im private-Abschnitt und leerem Rumpf.</summary>
function NewMethodItem(ARequest: TCompletionRequest; const ASignature: TEventSignature;
  const ATarget: TEventTarget; const ATypeName, AName: string): TCompletionItem;
var
  mHeader: string;
  mMethod: TUnmatchedMethod;
  mEdit: TRuleEdit;
begin
  mHeader := NewMethodHeader(ASignature, ATypeName, AName);
  Result := Default(TCompletionItem);
  Result.Name := cTexts[TMethodsText.NewMethod].Fmt([AName]);
  Result.Kind := cKindMethod;
  Result.Detail := Copy(mHeader, Length(ASignature.Kind) + 2, MaxInt);
  Result.InsertText := AName;
  // Immer sichtbar, auch wenn das Getippte nicht zum Namen passt.
  Result.FilterText := ATarget.Prefix;
  Result.Action := 'create';
  mMethod := Default(TUnmatchedMethod);
  mMethod.TypeName := ATypeName;
  mMethod.Header := mHeader;
  mMethod.Symbol.Name := AName;
  mMethod.Declared := False;
  if TClassCompletion.AddDeclaration(ARequest.Tree, ARequest.Text, mMethod, mEdit) then
  begin
    Result.AdditionalEdits := Result.AdditionalEdits + [mEdit];
  end;
  if TClassCompletion.BodyEdit(ARequest.Tree, ARequest.Text, ATypeName, mHeader + ';' + ARequest.LineBreak + 'begin' +
    ARequest.LineBreak + ARequest.LineBreak + 'end;', mEdit) then
  begin
    Result.AdditionalEdits := Result.AdditionalEdits + [mEdit];
  end;
end;

class function TCompletionMethods.EventItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  mTarget: TEventTarget;
  mSignature: TEventSignature;
  mTypeName, mName: string;
  mSymbol: TIndexSymbol;
  mTaken: TDictionary<string, Boolean>;
begin
  AItems := Default(TCompletionItems);
  mTypeName := '';
  if EventTargetAt(ARequest, mTarget) and EventSignatureOf(ARequest, mTarget, mSignature) then
  begin
    mTypeName := EnclosingClassOf(ARequest);
  end;
  Result := mTypeName <> '';
  if not Result then
  begin
    Exit;
  end;
  mTaken := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in ARequest.UnitIndex.Symbols do
    begin
      if SameText(mSymbol.Container, mTypeName) then
      begin
        mTaken.AddOrSetValue(LowerCase(mSymbol.Name), True);
      end;
    end;
    AItems.Items := FittingItems(ARequest, mTarget, mSignature, mTaken);
    mName := UniqueName(NewMethodBase(mTarget, mTypeName), mTaken);
  finally
    mTaken.Free;
  end;
  AItems.Items := AItems.Items + [NewMethodItem(ARequest, mSignature, mTarget, mTypeName, mName)];
end;

/// <summary>Signatur des Typs ATypeText aus dem Index, ohne Quellen der RTL die von System.SysUtils; '' ohne.
/// </summary>
function RefSignature(AResolver: TNameResolver; const AFromUnit: TUnitIndex; const ATypeText: string;
  out AResolved: TResolvedSymbol; out AArgs: TArray<string>): string;
var
  mBase: string;
begin
  AArgs := TCompletionAnonymous.TypeArgs(ATypeText, mBase);
  Result := '';
  AResolved := Default(TResolvedSymbol);
  if (AResolver <> nil) and AResolver.ResolveTypeTextFrom(AFromUnit, ATypeText, AResolved) and
    not AResolved.Builtin then
  begin
    Result := AResolved.Signature;
  end;
  if Result = '' then
  begin
    Result := TCompletionAnonymous.RtlDeclaration(mBase, Length(AArgs));
  end;
end;

/// <summary>Ersetzt in AMethodRef die Typparameter ATypeParams durch AArgs.</summary>
procedure SubstituteRef(var AMethodRef: TMethodRef; const ATypeParams, AArgs: TArray<string>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AMethodRef.Params) do
  begin
    AMethodRef.Params[mIndex].TypeText := TCompletionAnonymous.Substitute(AMethodRef.Params[mIndex].TypeText,
      ATypeParams, AArgs);
  end;
  AMethodRef.ResultType := TCompletionAnonymous.Substitute(AMethodRef.ResultType, ATypeParams, AArgs);
end;

class function TCompletionMethods.MethodRefOf(AResolver: TNameResolver; const AFromUnit: TUnitIndex;
  const ATypeText: string; out AMethodRef: TMethodRef): Boolean;
var
  mTypeText, mSignature, mTarget: string;
  mArgs, mTypeParams: TArray<string>;
  mFromUnit: TUnitIndex;
  mResolved: TResolvedSymbol;
  mDepth: Integer;
begin
  AMethodRef := Default(TMethodRef);
  Result := False;
  mTypeText := ATypeText;
  mFromUnit := AFromUnit;
  for mDepth := 0 to TCompletionAnonymous.cMaxAliasDepth do
  begin
    mSignature := RefSignature(AResolver, mFromUnit, mTypeText, mResolved, mArgs);
    if mSignature = '' then
    begin
      Exit;
    end;
    if TCompletionAnonymous.Parse(mSignature, mTypeParams, AMethodRef, mTarget) then
    begin
      SubstituteRef(AMethodRef, mTypeParams, mArgs);
      Exit(True);
    end;
    // Alias ("TKundenFilter = TPredicate<TKunde>"): weiter mit dem Ziel, gelesen in der Unit des Alias.
    if (mTarget = '') or not AResolver.DeclaringUnit(mResolved, mFromUnit) then
    begin
      Exit;
    end;
    mTypeText := TCompletionAnonymous.Substitute(mTarget, mTypeParams, mArgs);
  end;
end;

/// <summary>Steht der Cursor ohne Wort oder hinter einem Anfang von procedure bzw. function, wo ein Name erwartet
/// wird?</summary>
function AnonymousContext(ARequest: TCompletionRequest; out AContext: TCompletionContext): Boolean;
begin
  AContext := Default(TCompletionContext);
  if not ARequest.Settings.AnonymousMethods or (ARequest.Tree = nil) or (ARequest.Resolver = nil) then
  begin
    Exit(False);
  end;
  AContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  Result := (AContext.Kind = TCompletionContextKind.Scope) and (AContext.Filter = TCompletionFilter.Any) and
    not AContext.Attribute and not AContext.Generic;
  if Result and (AContext.Prefix <> '') then
  begin
    Result := StartsText(AContext.Prefix, 'procedure') or StartsText(AContext.Prefix, 'function');
  end;
end;

/// <summary>Bindungen generischer Instanzen sind qualifiziert ("Kunden.TKunde"); im Gerüst wie im Quelltext
/// üblich.</summary>
procedure UnqualifyRef(ARequest: TCompletionRequest; var AMethodRef: TMethodRef);
var
  mIndex: Integer;
  mUnitName: string;
begin
  mUnitName := ARequest.UnitIndex.UnitName;
  for mIndex := 0 to High(AMethodRef.Params) do
  begin
    AMethodRef.Params[mIndex].TypeText := ARequest.Resolver.Queries.UnqualifyType(AMethodRef.Params[mIndex].TypeText,
      mUnitName);
  end;
  AMethodRef.ResultType := ARequest.Resolver.Queries.UnqualifyType(AMethodRef.ResultType, mUnitName);
end;

/// <summary>Text des Gerüsts: als Snippet (Zeilen mit #10, die Einrückung setzt der Editor davor) oder als
/// Klartext mit der Einrückung der Zeile.</summary>
procedure SetAnonymousText(ARequest: TCompletionRequest; const AMethodRef: TMethodRef; ASnippets: Boolean;
  var AItem: TCompletionItem);
begin
  AItem.Snippet := ASnippets;
  if ASnippets then
  begin
    AItem.TextEdit.NewText := TCompletionAnonymous.Snippet(AMethodRef);
  end
  else
  begin
    AItem.TextEdit.NewText := TCompletionAnonymous.Plain(AMethodRef,
      TTextLines.IndentOf(ARequest.LineText(ARequest.Position.Line)), ARequest.LineBreak);
  end;
end;

class function TCompletionMethods.AnonymousItem(ARequest: TCompletionRequest; ASnippets: Boolean;
  const ANamingFor: TCompletionNamingFunc; out AItem: TCompletionItem): Boolean;
var
  mContext: TCompletionContext;
  mExpected: string;
  mMethodRef: TMethodRef;
  mStart: TTextPosition;
begin
  AItem := Default(TCompletionItem);
  Result := False;
  if not AnonymousContext(ARequest, mContext) then
  begin
    Exit;
  end;
  mExpected := TCompletionContexts.ExpectedFullType(ARequest.Resolver, ARequest.Tree, ARequest.FileName,
    ARequest.Position);
  if (mExpected = '') or not MethodRefOf(ARequest.Resolver, ARequest.UnitIndex, mExpected, mMethodRef) then
  begin
    Exit;
  end;
  mExpected := ARequest.Resolver.Queries.UnqualifyType(mExpected, ARequest.UnitIndex.UnitName);
  UnqualifyRef(ARequest, mMethodRef);
  mMethodRef := TCompletionAnonymous.Named(mMethodRef, TCompletionNames.PrefixFor(ARequest, ANamingFor,
    TNamingKind.Parameter));
  AItem.Name := TCompletionAnonymous.Header(mMethodRef);
  AItem.FilterText := 'procedure';
  if mMethodRef.IsFunction then
  begin
    AItem.FilterText := 'function';
  end;
  AItem.Kind := cKindSnippet;
  // Den Typ zeigt Atlas als Tag (MethodRef); rechts steht, was der Eintrag ist.
  AItem.Detail := cTexts[TMethodsText.AnonymousMethod].Text;
  AItem.MethodRef := mExpected;
  AItem.Expected := mExpected;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: keine uses-Ergänzung.
  AItem.Action := 'anonymous';
  AItem.HasTextEdit := True;
  mStart := ARequest.Position;
  mStart.Character := Max(0, mStart.Character - Length(mContext.Prefix));
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(mStart, ARequest.Position), '');
  SetAnonymousText(ARequest, mMethodRef, ASnippets, AItem);
  Result := True;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion.Methods', cTexts);

end.
