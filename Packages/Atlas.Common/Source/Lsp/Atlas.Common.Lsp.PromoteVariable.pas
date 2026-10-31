unit Atlas.Common.Lsp.PromoteVariable;

// „Lokale Variable und Feld umwandeln“ über das Protokoll (#668):
//   - Code-Aktion „In Feld umwandeln (X → FX)“ bzw. „In lokale Variable
//     umwandeln (FX → LX)“ an der Stelle, nur mit refactoring.promoteVariable.
//     Sie trägt den Client-Befehl atlas.promoteVariable mit [uri, position,
//     vorgeschlagener Name]; das Plugin fragt den Namen nach.
//   - Befehl atlas.server.promoteVariable [uri, position, Name]:
//     {"edit": WorkspaceEdit, "warnings": [...], "places": n, "files": 1};
//     ein vergebener oder ungültiger Name ist ein Fehler mit Grund.
// Namensauflösung: Typ von Inline-Variablen ohne Angabe über die Ableitung der
// Inlay Hints (#453), geerbte Mitglieder über TNameResolver.ResolveChain,
// Formulardatei (.dfm, .fmx neben der Unit) über AReadText.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Lsp.References;

type
  TLspPromoteVariable = class
  public const
    ClientCommand = 'atlas.promoteVariable';
    ApplyCommand = 'atlas.server.promoteVariable';
    Kind = 'refactor.rewrite';
  public
    /// <summary>Typen, Vorfahren und Formular über AResolver für ATree der Datei AFileName.</summary>
    class function Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const AReadText: TReferenceReadText): TPromoteLookup; static;
    /// <summary>Die Code-Aktion an APosition oder nil. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
      const ALookup: TPromoteLookup): TArray<TJSONObject>; static;
    /// <summary>Antwort auf atlas.server.promoteVariable; EJsonRpcError mit dem Grund, wenn es nicht geht. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    class function Execute(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
      const AName: string; const ALookup: TPromoteLookup; const AStyle: TFormatStyle): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.FormMentions,
  Atlas.Common.Lsp.InlayHints;

class function TLspPromoteVariable.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AReadText: TReferenceReadText): TPromoteLookup;
var
  FileName: string;
begin
  Result := TPromoteLookup.FromTree(ATree);
  FileName := AFileName;
  Result.InlineType :=
    function(const ALocal: TRoutineLocal): string
    var
      Found: TInferredType;
    begin
      Result := '';
      for Found in TLspInlayHints.Inferred(AResolver, ATree, FileName, TTextRange.Create(ALocal.Decl.StartPos,
        ALocal.Decl.EndPos)) do
        if SameText(Found.Name, ALocal.Name) and not Found.ForIn then
          Exit(Found.TypeName);
    end;
  Result.MemberExists :=
    function(const AClassName, AName: string; AOffset: Integer): Boolean
    begin
      Result := AResolver.ResolveChain(ATree, FileName, (AClassName + '.' + AName).Split(['.']), AOffset).Found;
    end;
  Result.InForm := TLspFormMentions.Lookup(AFileName, AReadText);
end;

class function TLspPromoteVariable.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const ALookup: TPromoteLookup): TArray<TJSONObject>;
var
  Target: TPromoteTarget;
  Reason: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not TPromoteVariable.Target(AText, ATree, APosition, ALookup, Target, Reason) then
    Exit;
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
  Result := [Action];
end;

class function TLspPromoteVariable.Execute(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const AName: string; const ALookup: TPromoteLookup;
  const AStyle: TFormatStyle): TJSONObject;
var
  Promoted: TPromoteResult;
  Reason, Warning: string;
  Warnings: TJSONArray;
begin
  if not TPromoteVariable.Execute(AText, ATree, APosition, ALookup, AStyle, AName, Promoted, Reason) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Umwandeln geht nicht: ' + Reason);
  Warnings := TJSONArray.Create;
  for Warning in Promoted.Warnings do
    Warnings.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', TLspCodeActions.WorkspaceEditJson(AUri, Promoted.Edits));
  Result.AddPair('warnings', Warnings);
  Result.AddPair('places', TJSONNumber.Create(Promoted.Places));
  Result.AddPair('files', TJSONNumber.Create(1));
end;

end.
