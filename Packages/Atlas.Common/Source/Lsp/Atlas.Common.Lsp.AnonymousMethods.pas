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
    ClientCommand = 'atlas.anonymousMethod';
    ApplyCommand = 'atlas.server.anonymousMethod';
    Kind = 'refactor.rewrite';
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
  Atlas.Common.Lsp.PromoteVariable;

const
  // Alias auf Alias: so tief wird verfolgt.
  MaxAliasDepth = 4;

/// <summary>Art des Typs ATypeText an AOffset, Aliase über AResolver verfolgt.</summary>
function KindOfType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, ATypeText: string;
  AOffset: Integer): TProcTypeKind;
var
  Name: string;
  Resolved: TResolvedSymbol;
  Depth: Integer;
begin
  Name := Trim(ATypeText);
  for Depth := 0 to MaxAliasDepth do
  begin
    Result := TAnonymousMethods.KindOfTypeText(Name);
    if (Result <> TProcTypeKind.Unknown) or (Name = '') then
    begin
      Exit;
    end;
    if Pos('<', Name) > 0 then
    begin
      Name := Copy(Name, 1, Pos('<', Name) - 1);
    end;
    if (Pos(' ', Trim(Name)) > 0) or (Pos('^', Name) > 0) then
    begin
      Exit;
    end;
    Resolved := AResolver.ResolveChain(ATree, AFileName, Trim(Name).Split(['.']), AOffset);
    if not Resolved.Found or (Resolved.SymbolKind <> TIndexSymbolKind.TypeAlias) or (Pos('=', Resolved.Signature) = 0)
    then
    begin
      Exit;
    end;
    // "TAktion = reference to procedure(…)": der Teil hinter '='.
    Name := Trim(Copy(Resolved.Signature, Pos('=', Resolved.Signature) + 1, MaxInt));
    if EndsStr(';', Name) then
    begin
      Name := Trim(Copy(Name, 1, Length(Name) - 1));
    end;
  end;
  Result := TProcTypeKind.Unknown;
end;

/// <summary>Art des prozeduralen Typs ANode (reference to …, … of object, procedure …) aus den Token.</summary>
function KindOfProcedureType(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): TProcTypeKind;
var
  Index, Next: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  if (Index <= High(ATokens)) and SameText(ATokens[Index].Text, 'reference') then
  begin
    Exit(TProcTypeKind.Reference);
  end;
  Result := TProcTypeKind.Plain;
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ANode.EndOffset) do
  begin
    Next := TRoutineBody.NextToken(ATokens, Index);
    if SameText(ATokens[Index].Text, 'of') and (Next <= High(ATokens)) and SameText(ATokens[Next].Text, 'object') then
    begin
      Exit(TProcTypeKind.MethodPointer);
    end;
    Inc(Index);
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
  Promote: TPromoteLookup;
  Nested: TNestedRoutineLookup;
  FileName: string;
begin
  Result := TAnonymousLookup.FromTree(ATree);
  Promote := TLspPromoteVariable.Lookup(AResolver, ATree, AFileName, AReadText);
  Nested := TNestedRoutineLookup.FromResolver(AResolver, ATree, AFileName);
  Result.InlineType := Promote.InlineType;
  Result.MemberExists := Promote.MemberExists;
  Result.InForm := Promote.InForm;
  Result.ConstType := Nested.ConstType;
  FileName := AFileName;
  Result.TargetType :=
    function(AValue: TSyntaxNode): TProcTypeKind
    begin
      Result := TargetKind(AResolver, ATree, FileName, AValue);
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

class function TLspAnonymousMethods.Actions(const ARequest: TAnonymousMethodRequest): TArray<TJSONObject>;
var
  Target: TAnonymousTarget;
  Reason: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
  Embedded: TCodeAction;
begin
  Result := nil;
  if TAnonymousMethods.Target(ARequest.Text, ARequest.Tree, ARequest.Position, ARequest.Lookup, ARequest.Capture,
    Target, Reason) then
  begin
    Arguments := TJSONArray.Create;
    Arguments.Add(ARequest.Uri);
    Arguments.AddElement(TLspPositions.PositionToJson(ARequest.Position));
    Arguments.Add(Target.Suggested);
    Command := TJSONObject.Create;
    Command.AddPair('title', Target.Title);
    Command.AddPair('command', ClientCommand);
    Command.AddPair('arguments', Arguments);
    Action := TJSONObject.Create;
    Action.AddPair('title', Target.Title);
    Action.AddPair('kind', Kind);
    Action.AddPair('command', Command);
    Result := Result + [Action];
  end;
  if TAnonymousMethods.Embed(ARequest.Text, ARequest.Tree, ARequest.Position, ARequest.Lookup, ARequest.Style,
    Embedded, Reason) then
  begin
    Result := Result + [TLspCodeActions.ActionToJson(ARequest.Uri, Embedded)];
  end;
end;

class function TLspAnonymousMethods.Execute(const ARequest: TAnonymousMethodRequest; const AName: string): TJSONObject;
var
  Converted: TAnonymousResult;
  Reason, Warning: string;
  Warnings: TJSONArray;
begin
  if not TAnonymousMethods.Execute(ARequest.Text, ARequest.Tree, ARequest.Position, ARequest.Lookup, ARequest.Capture,
    ARequest.Style, AName, Converted, Reason) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Umwandeln geht nicht: ' + Reason);
  end;
  Warnings := TJSONArray.Create;
  for Warning in Converted.Warnings do
  begin
    Warnings.Add(Warning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', TLspCodeActions.WorkspaceEditJson(ARequest.Uri, Converted.Edits));
  Result.AddPair('warnings', Warnings);
  Result.AddPair('places', TJSONNumber.Create(Length(Converted.Edits)));
  Result.AddPair('files', TJSONNumber.Create(1));
  Result.AddPair('preview', Converted.Preview);
end;

end.
