unit Atlas.Common.Lsp.AnonymousMethods;

// „Anonyme Methode und Methode umwandeln“ über das Protokoll (#680):
//   - Code-Aktion „In Methode umwandeln (Name)“ bzw. „In Routine umwandeln
//     (Name)“ auf dem Kopf einer anonymen Methode, nur mit
//     refactoring.anonymousMethod. Sie trägt den Client-Befehl
//     atlas.anonymousMethod mit [uri, position, vorgeschlagener Name]; das
//     Plugin fragt den Namen nach.
//   - Befehl atlas.server.anonymousMethod [uri, position, Name]:
//     {"edit": WorkspaceEdit, "warnings": [...], "places": n, "files": 1,
//     "preview": Text}; ein vergebener oder ungültiger Name ist ein Fehler mit
//     Grund. Die Form für später laufende anonyme Methoden folgt
//     refactoring.anonymousMethodDeferredCapture.
//   - Code-Aktion „Als anonyme Methode einbetten“ mit Vorschau (data.preview).
// Namensauflösung: Typ von Inline-Variablen ohne Angabe und Mitglieder wie bei
// #668, Records und Interfaces für const wie bei #663, Zieltyp einer Übergabe
// (Parameter des Aufgerufenen, Typ links der Zuweisung, Typ der
// Inline-Variablen) samt Aliasen über TNameResolver.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.AnonymousMethods,
  Atlas.Common.Lsp.References;

type
  /// <summary>Stelle im Dokument und wie umgewandelt wird.</summary>
  TAnonymousMethodRequest = record
    Tree: TSyntaxTree;
    Text: string;
    Uri: string;
    Position: TTextPosition;
    Lookup: TAnonymousLookup;
    Capture: TDeferredCapture;
    Style: TFormatStyle;
  end;

  TLspAnonymousMethods = class
  public const
    cClientCommand = 'atlas.anonymousMethod';
    cApplyCommand = 'atlas.server.anonymousMethod';
    cKind = 'refactor.rewrite';
  public
    /// <summary>Typen, Mitglieder, Formular und Zieltypen über AResolver für ATree der Datei AFileName.</summary>
    class function Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const AReadText: TReferenceReadText): TAnonymousLookup; static;
    /// <summary>"fields" bzw. sonst Forward.</summary>
    class function CaptureOf(const ASetting: string): TDeferredCapture; static;
    /// <summary>Die Code-Aktionen an APosition. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(const ARequest: TAnonymousMethodRequest): TArray<TJSONObject>; static;
    /// <summary>Antwort auf atlas.server.anonymousMethod; EJsonRpcError mit dem Grund, wenn es nicht geht. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    class function Execute(const ARequest: TAnonymousMethodRequest; const AName: string): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.PromoteVariable,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspAnonymousMethodsText = (ConversionNotPossible);

const
  cTexts: array[TLspAnonymousMethodsText] of TAtlasText = (
    (De: 'Umwandeln geht nicht: '; En: 'Conversion not possible: '));

{$SCOPEDENUMS OFF}

const
  // Alias auf Alias: so tief wird verfolgt.
  cMaxAliasDepth = 4;

/// <summary>Art des Typs ATypeText an AOffset, Aliase über AResolver verfolgt.</summary>
function KindOfType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, ATypeText: string;
  AOffset: Integer): TProcTypeKind;
var
  mName: string;
  mResolved: TResolvedSymbol;
  mDepth: Integer;
begin
  mName := Trim(ATypeText);
  for mDepth := 0 to cMaxAliasDepth do
  begin
    Result := TAnonymousMethods.KindOfTypeText(mName);
    if (Result <> TProcTypeKind.Unknown) or (mName = '') then
    begin
      Exit;
    end;
    if Pos('<', mName) > 0 then
    begin
      mName := Copy(mName, 1, Pos('<', mName) - 1);
    end;
    if (Pos(' ', Trim(mName)) > 0) or (Pos('^', mName) > 0) then
    begin
      Exit;
    end;
    mResolved := AResolver.ResolveChain(ATree, AFileName, Trim(mName).Split(['.']), AOffset);
    if not mResolved.Found or (mResolved.SymbolKind <> TIndexSymbolKind.TypeAlias) or (Pos('=', mResolved.Signature) = 0)
    then
    begin
      Exit;
    end;
    // "TAktion = reference to procedure(…)": der Teil hinter '='.
    mName := Trim(Copy(mResolved.Signature, Pos('=', mResolved.Signature) + 1, MaxInt));
    if EndsStr(';', mName) then
    begin
      mName := Trim(Copy(mName, 1, Length(mName) - 1));
    end;
  end;
  Result := TProcTypeKind.Unknown;
end;

/// <summary>Art des prozeduralen Typs ANode (reference to …, … of object, procedure …) aus den Token.</summary>
function KindOfProcedureType(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): TProcTypeKind;
var
  mIndex, mNext: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  if (mIndex <= High(ATokens)) and SameText(ATokens[mIndex].Text, 'reference') then
  begin
    Exit(TProcTypeKind.Reference);
  end;
  Result := TProcTypeKind.Plain;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    mNext := TRoutineBody.NextToken(ATokens, mIndex);
    if SameText(ATokens[mIndex].Text, 'of') and (mNext <= High(ATokens)) and SameText(ATokens[mNext].Text, 'object') then
    begin
      Exit(TProcTypeKind.MethodPointer);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Art des Typs links einer Zuweisung, an die der Wert AValue geht.</summary>
function AssignTargetKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AValue: TSyntaxNode): TProcTypeKind;
var
  mSymbol, mTypeSymbol: TResolvedSymbol;
  mTypeFound: Boolean;
  mTypeText: string;
begin
  Result := TProcTypeKind.Unknown;
  if not AResolver.NodeType(ATree, AFileName, AValue.Parent[0], mSymbol, mTypeSymbol, mTypeFound) then
  begin
    Exit;
  end;
  if mTypeFound then
  begin
    Result := KindOfType(AResolver, ATree, AFileName, mTypeSymbol.Name, AValue.StartOffset);
  end;
  if (Result = TProcTypeKind.Unknown) and (mSymbol.TypeName <> '') then
  begin
    mTypeText := mSymbol.TypeName;
    if mSymbol.TypeArgs <> '' then
    begin
      mTypeText := mTypeText + '<' + mSymbol.TypeArgs + '>';
    end;
    Result := KindOfType(AResolver, ATree, AFileName, mTypeText, AValue.StartOffset);
  end;
end;

/// <summary>Art des angegebenen Typs der Inline-Variablen, deren Wert AValue ist.</summary>
function InlineVarTargetKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AValue: TSyntaxNode): TProcTypeKind;
var
  mVar: TSyntaxNode;
begin
  Result := TProcTypeKind.Unknown;
  mVar := AValue.Parent;
  if mVar.ChildCount <= 1 then
  begin
    Exit;
  end;
  if mVar[0].Kind = TSyntaxKind.TypeReference then
  begin
    Result := KindOfType(AResolver, ATree, AFileName, mVar[0].Name, AValue.StartOffset);
  end
  else if mVar[0].Kind = TSyntaxKind.ProcedureType then
  begin
    Result := KindOfProcedureType(ATree.Tokens, mVar[0]);
  end;
end;

/// <summary>Stelle von AValue unter den Argumenten von ACall (1 = erstes Argument); 0 = keines davon.</summary>
function ArgumentIndex(ACall, AValue: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    if ACall[mIndex] = AValue then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Art des Parametertyps, an den das Argument AValue geht. Alle Überladungen müssen dasselbe sagen.
/// </summary>
function CallTargetKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AValue: TSyntaxNode): TProcTypeKind;
var
  mArgument: Integer;
  mCandidate: TResolvedSymbol;
  mKind: TProcTypeKind;
begin
  Result := TProcTypeKind.Unknown;
  mArgument := ArgumentIndex(AValue.Parent, AValue) - 1;
  if mArgument < 0 then
  begin
    Exit;
  end;
  for mCandidate in AResolver.CallCandidates(ATree, AFileName, AValue.Parent[0]) do
  begin
    if mArgument > High(mCandidate.ParamTypes) then
    begin
      Continue;
    end;
    mKind := KindOfType(AResolver, ATree, AFileName, mCandidate.ParamTypes[mArgument], AValue.StartOffset);
    if (mKind = TProcTypeKind.Unknown) or ((Result <> TProcTypeKind.Unknown) and (mKind <> Result)) then
    begin
      Exit(TProcTypeKind.Unknown);
    end;
    Result := mKind;
  end;
end;

/// <summary>Art des Typs, an den der Wert AValue geht.</summary>
function TargetKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AValue: TSyntaxNode): TProcTypeKind;
begin
  Result := TProcTypeKind.Unknown;
  if AValue.Parent = nil then
  begin
    Exit;
  end;
  case AValue.Parent.Kind of
    TSyntaxKind.AssignStatement:
      Result := AssignTargetKind(AResolver, ATree, AFileName, AValue);
    TSyntaxKind.InlineVar:
      Result := InlineVarTargetKind(AResolver, ATree, AFileName, AValue);
    TSyntaxKind.Call:
      Result := CallTargetKind(AResolver, ATree, AFileName, AValue);
  else
    // Übrige Arten: nichts zu tun.
  end;
end;


class function TLspAnonymousMethods.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AReadText: TReferenceReadText): TAnonymousLookup;
var
  mPromote: TPromoteLookup;
  mNested: TNestedRoutineLookup;
  mFileName: string;
begin
  Result := TAnonymousLookup.FromTree(ATree);
  mPromote := TLspPromoteVariable.Lookup(AResolver, ATree, AFileName, AReadText);
  mNested := TNestedRoutineLookup.FromResolver(AResolver, ATree, AFileName);
  Result.InlineType := mPromote.InlineType;
  Result.MemberExists := mPromote.MemberExists;
  Result.InForm := mPromote.InForm;
  Result.ConstType := mNested.ConstType;
  mFileName := AFileName;
  Result.TargetType :=
    function(AValue: TSyntaxNode): TProcTypeKind
    begin
      Result := TargetKind(AResolver, ATree, mFileName, AValue);
    end;
end;

class function TLspAnonymousMethods.CaptureOf(const ASetting: string): TDeferredCapture;
begin
  if SameText(ASetting, 'fields') then
  begin
    Result := TDeferredCapture.Fields;
  end
  else
  begin
    Result := TDeferredCapture.Forward;
  end;
end;

/// <summary>Eingabe der Umwandlung aus ARequest.</summary>
function InputOf(const ARequest: TAnonymousMethodRequest): TAnonymousInput;
begin
  Result := TAnonymousInput.Create(ARequest.Text, ARequest.Tree, ARequest.Position, ARequest.Lookup);
  Result.Capture := ARequest.Capture;
  Result.Style := ARequest.Style;
end;

class function TLspAnonymousMethods.Actions(const ARequest: TAnonymousMethodRequest): TArray<TJSONObject>;
var
  mTarget: TAnonymousTarget;
  mReason: string;
  mArguments: TJSONArray;
  mCommand, mAction: TJSONObject;
  mEmbedded: TCodeAction;
begin
  Result := nil;
  if TAnonymousMethods.Target(InputOf(ARequest), mTarget, mReason) then
  begin
    mArguments := TJSONArray.Create;
    mArguments.Add(ARequest.Uri);
    mArguments.AddElement(TLspPositions.PositionToJson(ARequest.Position));
    mArguments.Add(mTarget.Suggested);
    mCommand := TJSONObject.Create;
    mCommand.AddPair('title', mTarget.Title);
    mCommand.AddPair('command', cClientCommand);
    mCommand.AddPair('arguments', mArguments);
    mAction := TJSONObject.Create;
    mAction.AddPair('title', mTarget.Title);
    mAction.AddPair('kind', cKind);
    mAction.AddPair('command', mCommand);
    Result := Result + [mAction];
  end;
  if TAnonymousMethods.Embed(InputOf(ARequest), mEmbedded, mReason) then
  begin
    Result := Result + [TLspCodeActions.ActionToJson(ARequest.Uri, mEmbedded)];
  end;
end;

class function TLspAnonymousMethods.Execute(const ARequest: TAnonymousMethodRequest; const AName: string): TJSONObject;
var
  mConverted: TAnonymousResult;
  mReason, mWarning: string;
  mWarnings: TJSONArray;
begin
  if not TAnonymousMethods.Execute(InputOf(ARequest), AName, mConverted, mReason) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed,
      cTexts[TLspAnonymousMethodsText.ConversionNotPossible].Text + mReason);
  end;
  mWarnings := TJSONArray.Create;
  for mWarning in mConverted.Warnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', TLspCodeActions.WorkspaceEditJson(ARequest.Uri, mConverted.Edits));
  Result.AddPair('warnings', mWarnings);
  Result.AddPair('places', TJSONNumber.Create(Length(mConverted.Edits)));
  Result.AddPair('files', TJSONNumber.Create(1));
  Result.AddPair('preview', mConverted.Preview);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.AnonymousMethods', cTexts);

end.
