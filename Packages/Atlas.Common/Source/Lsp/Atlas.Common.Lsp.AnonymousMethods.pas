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
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
      const ALookup: TAnonymousLookup; ACapture: TDeferredCapture; const AStyle: TFormatStyle): TArray<TJSONObject>;
      static;
    /// <summary>Antwort auf atlas.server.anonymousMethod; EJsonRpcError mit dem Grund, wenn es nicht geht. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    class function Execute(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
      const AName: string; const ALookup: TAnonymousLookup; ACapture: TDeferredCapture;
      const AStyle: TFormatStyle): TJSONObject; static;
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
      Exit;
    if Pos('<', Name) > 0 then
      Name := Copy(Name, 1, Pos('<', Name) - 1);
    if (Pos(' ', Trim(Name)) > 0) or (Pos('^', Name) > 0) then
      Exit;
    Resolved := AResolver.ResolveChain(ATree, AFileName, Trim(Name).Split(['.']), AOffset);
    if not Resolved.Found or (Resolved.SymbolKind <> TIndexSymbolKind.TypeAlias) or (Pos('=', Resolved.Signature) = 0)
    then
      Exit;
    // "TAktion = reference to procedure(…)": der Teil hinter '='.
    Name := Trim(Copy(Resolved.Signature, Pos('=', Resolved.Signature) + 1, MaxInt));
    if EndsStr(';', Name) then
      Name := Trim(Copy(Name, 1, Length(Name) - 1));
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
    Exit(TProcTypeKind.Reference);
  Result := TProcTypeKind.Plain;
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ANode.EndOffset) do
  begin
    Next := TRoutineBody.NextToken(ATokens, Index);
    if SameText(ATokens[Index].Text, 'of') and (Next <= High(ATokens)) and SameText(ATokens[Next].Text, 'object') then
      Exit(TProcTypeKind.MethodPointer);
    Inc(Index);
  end;
end;

/// <summary>Art des Typs, an den der Wert AValue geht.</summary>
function TargetKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AValue: TSyntaxNode): TProcTypeKind;
var
  Parent: TSyntaxNode;
  Symbol, TypeSymbol: TResolvedSymbol;
  TypeFound: Boolean;
  Candidates: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Index: Integer;
  Kind: TProcTypeKind;
  TypeText: string;
begin
  Result := TProcTypeKind.Unknown;
  Parent := AValue.Parent;
  if Parent = nil then
    Exit;
  case Parent.Kind of
    TSyntaxKind.AssignStatement:
      begin
        if not AResolver.NodeType(ATree, AFileName, Parent[0], Symbol, TypeSymbol, TypeFound) then
          Exit;
        if TypeFound then
          Result := KindOfType(AResolver, ATree, AFileName, TypeSymbol.Name, AValue.StartOffset);
        if (Result = TProcTypeKind.Unknown) and (Symbol.TypeName <> '') then
        begin
          TypeText := Symbol.TypeName;
          if Symbol.TypeArgs <> '' then
            TypeText := TypeText + '<' + Symbol.TypeArgs + '>';
          Result := KindOfType(AResolver, ATree, AFileName, TypeText, AValue.StartOffset);
        end;
      end;
    TSyntaxKind.InlineVar:
      if (Parent.ChildCount > 1) and (Parent[0].Kind = TSyntaxKind.TypeReference) then
        Result := KindOfType(AResolver, ATree, AFileName, Parent[0].Name, AValue.StartOffset)
      else if (Parent.ChildCount > 1) and (Parent[0].Kind = TSyntaxKind.ProcedureType) then
        Result := KindOfProcedureType(ATree.Tokens, Parent[0]);
    TSyntaxKind.Call:
      begin
        Index := 1;
        while (Index < Parent.ChildCount) and (Parent[Index] <> AValue) do
          Inc(Index);
        if Index >= Parent.ChildCount then
          Exit;
        Candidates := AResolver.CallCandidates(ATree, AFileName, Parent[0]);
        // Alle Überladungen müssen dasselbe sagen.
        for Candidate in Candidates do
        begin
          if Index - 1 > High(Candidate.ParamTypes) then
            Continue;
          Kind := KindOfType(AResolver, ATree, AFileName, Candidate.ParamTypes[Index - 1], AValue.StartOffset);
          if Kind = TProcTypeKind.Unknown then
            Exit(TProcTypeKind.Unknown);
          if (Result <> TProcTypeKind.Unknown) and (Kind <> Result) then
            Exit(TProcTypeKind.Unknown);
          Result := Kind;
        end;
      end;
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
    Result := TDeferredCapture.Fields
  else
    Result := TDeferredCapture.Forward;
end;

class function TLspAnonymousMethods.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const ALookup: TAnonymousLookup; ACapture: TDeferredCapture;
  const AStyle: TFormatStyle): TArray<TJSONObject>;
var
  Target: TAnonymousTarget;
  Reason: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
  Embedded: TCodeAction;
begin
  Result := nil;
  if TAnonymousMethods.Target(AText, ATree, APosition, ALookup, ACapture, Target, Reason) then
  begin
    Arguments := TJSONArray.Create;
    Arguments.Add(AUri);
    Arguments.AddElement(TLspPositions.PositionToJson(APosition));
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
  if TAnonymousMethods.Embed(AText, ATree, APosition, ALookup, AStyle, Embedded, Reason) then
    Result := Result + [TLspCodeActions.ActionToJson(AUri, Embedded)];
end;

class function TLspAnonymousMethods.Execute(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const AName: string; const ALookup: TAnonymousLookup; ACapture: TDeferredCapture;
  const AStyle: TFormatStyle): TJSONObject;
var
  Converted: TAnonymousResult;
  Reason, Warning: string;
  Warnings: TJSONArray;
begin
  if not TAnonymousMethods.Execute(AText, ATree, APosition, ALookup, ACapture, AStyle, AName, Converted, Reason) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Umwandeln geht nicht: ' + Reason);
  Warnings := TJSONArray.Create;
  for Warning in Converted.Warnings do
    Warnings.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', TLspCodeActions.WorkspaceEditJson(AUri, Converted.Edits));
  Result.AddPair('warnings', Warnings);
  Result.AddPair('places', TJSONNumber.Create(Length(Converted.Edits)));
  Result.AddPair('files', TJSONNumber.Create(1));
  Result.AddPair('preview', Converted.Preview);
end;

end.
