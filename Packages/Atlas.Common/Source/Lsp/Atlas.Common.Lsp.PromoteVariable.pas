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
  /// <summary>Was atlas.server.promoteVariable braucht außer Baum, Text und Stelle.</summary>
  TPromoteVariableContext = record
    Lookup: TPromoteLookup;
    Style: TFormatStyle;
    /// <summary>Name des neuen Felds bzw. der Variablen.</summary>
    NewName: string;
  end;

  TLspPromoteVariable = class
  public const
    cClientCommand = 'atlas.promoteVariable';
    cApplyCommand = 'atlas.server.promoteVariable';
    cKind = 'refactor.rewrite';
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
      const AContext: TPromoteVariableContext): TJSONObject; static;
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
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspPromoteVariableText = (ConversionNotPossible);

const
  cTexts: array[TLspPromoteVariableText] of TAtlasText = (
    (De: 'Umwandeln geht nicht: '; En: 'Conversion not possible: '));

{$SCOPEDENUMS OFF}

class function TLspPromoteVariable.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AReadText: TReferenceReadText): TPromoteLookup;
var
  mFileName: string;
begin
  Result := TPromoteLookup.FromTree(ATree);
  mFileName := AFileName;
  Result.InlineType :=
    function(const ALocal: TRoutineLocal): string
    var
      Found: TInferredType;
    begin
      Result := '';
      for Found in TLspInlayHints.Inferred(AResolver, ATree, mFileName, TTextRange.Create(ALocal.Decl.StartPos,
        ALocal.Decl.EndPos)) do
      begin
        if SameText(Found.Name, ALocal.Name) and not Found.ForIn then
        begin
          Exit(Found.TypeName);
        end;
      end;
    end;
  Result.MemberExists :=
    function(const AClassName, AName: string; AOffset: Integer): Boolean
    begin
      Result := AResolver.ResolveChain(ATree, mFileName, (AClassName + '.' + AName).Split(['.']), AOffset).Found;
    end;
  Result.InForm := TLspFormMentions.Lookup(AFileName, AReadText);
end;

class function TLspPromoteVariable.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const ALookup: TPromoteLookup): TArray<TJSONObject>;
var
  mTarget: TPromoteTarget;
  mReason: string;
  mArguments: TJSONArray;
  mCommand, mAction: TJSONObject;
begin
  Result := nil;
  if not TPromoteVariable.Target(AText, ATree, APosition, ALookup, mTarget, mReason) then
  begin
    Exit;
  end;
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(APosition));
  mArguments.Add(mTarget.Suggested);
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', mTarget.Title);
  mCommand.AddPair('command', cClientCommand);
  mCommand.AddPair('arguments', mArguments);
  mAction := TJSONObject.Create;
  mAction.AddPair('title', mTarget.Title);
  mAction.AddPair('kind', cKind);
  mAction.AddPair('command', mCommand);
  Result := [mAction];
end;

class function TLspPromoteVariable.Execute(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const AContext: TPromoteVariableContext): TJSONObject;
var
  mPromoted: TPromoteResult;
  mReason, mWarning: string;
  mWarnings: TJSONArray;
begin
  if not TPromoteVariable.Execute(AText, ATree, TPromoteRequest.Create(APosition, AContext.Lookup, AContext.Style,
    AContext.NewName), mPromoted, mReason) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed,
      cTexts[TLspPromoteVariableText.ConversionNotPossible].Text + mReason);
  end;
  mWarnings := TJSONArray.Create;
  for mWarning in mPromoted.Warnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', TLspCodeActions.WorkspaceEditJson(AUri, mPromoted.Edits));
  Result.AddPair('warnings', mWarnings);
  Result.AddPair('places', TJSONNumber.Create(mPromoted.Places));
  Result.AddPair('files', TJSONNumber.Create(1));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.PromoteVariable', cTexts);

end.
