unit Atlas.Common.Lsp.Unwrap;

// „Umschließung entfernen“ über das Protokoll (#657): Befehl
// atlas.server.unwrap [uri, position, Einrückungsbreite?] liefert die
// umschließenden Konstrukte am Cursor mit ihren Varianten:
//   {"candidates": [{"kind": "tryFinally", "range": …, "note": "loopVariable",
//     "noteText": "I", "variants": [{"kind": "keepFinally", "branch": 0,
//     "edits": [{"range": …, "newText": …}], "keep": [range …],
//     "remove": [range …]}]}]}
// Die Edits einer Variante sind ein Rückgängig-Schritt im Plugin. Bei with
// stammen sie aus „with auflösen“ (#50) mit der Namensauflösung des Servers;
// ist das nicht eindeutig, trägt der Eintrag note "withUnresolved" mit dem
// Grund und keine Varianten.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.Unwrap,
  Atlas.Common.Lsp.Refactorings;

type
  TLspUnwrap = class
  public const
    Command = 'atlas.server.unwrap';
  public
    /// <summary>Konstrukte an APosition als JSON; AIndentWidth &lt;= 0 = Breite aus dem Formatierstil. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; AIndentWidth: Integer): TJSONObject;
      static;
    class function ToJson(const ACandidates: TArray<TUnwrapCandidate>): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.WithResolution,
  Atlas.Common.Lsp.Positions;

function RangesToJson(const ARanges: TArray<TTextRange>): TJSONArray;
var
  Range: TTextRange;
begin
  Result := TJSONArray.Create;
  for Range in ARanges do
    Result.AddElement(TLspPositions.RangeToJson(Range));
end;

function EditsToJson(const AEdits: TArray<TTextEdit>): TJSONArray;
var
  Edit: TTextEdit;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Result.AddElement(Item);
  end;
end;

class function TLspUnwrap.ToJson(const ACandidates: TArray<TUnwrapCandidate>): TJSONObject;
var
  Candidates, Variants: TJSONArray;
  Candidate: TUnwrapCandidate;
  Choice: TUnwrapVariant;
  Item, VariantItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Candidates := TJSONArray.Create;
  Result.AddPair('candidates', Candidates);
  for Candidate in ACandidates do
  begin
    Item := TJSONObject.Create;
    Candidates.AddElement(Item);
    Item.AddPair('kind', TUnwrap.KindName(Candidate.Kind));
    Item.AddPair('range', TLspPositions.RangeToJson(Candidate.Range));
    Item.AddPair('note', TUnwrap.NoteName(Candidate.Note));
    Item.AddPair('noteText', Candidate.NoteText);
    Variants := TJSONArray.Create;
    Item.AddPair('variants', Variants);
    for Choice in Candidate.Variants do
    begin
      VariantItem := TJSONObject.Create;
      Variants.AddElement(VariantItem);
      VariantItem.AddPair('kind', TUnwrap.VariantName(Choice.Kind));
      VariantItem.AddPair('branch', TJSONNumber.Create(Choice.Branch));
      VariantItem.AddPair('edits', EditsToJson(Choice.Edits));
      VariantItem.AddPair('keep', RangesToJson(Choice.Keep));
      VariantItem.AddPair('remove', RangesToJson(Choice.Remove));
    end;
  end;
end;

class function TLspUnwrap.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; AIndentWidth: Integer): TJSONObject;
var
  Options: TUnwrapOptions;
  Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Context: TRefactoringContext;
begin
  Options := TUnwrapOptions.Default;
  Options.IndentWidth := AIndentWidth;
  if Options.IndentWidth <= 0 then
    Options.IndentWidth := AContext.Style.IndentSize;
  Text := AText;
  Tree := ATree;
  Resolver := AResolver;
  Context := AContext;
  if Resolver <> nil then
    Options.ResolveWith :=
      function(AWith: TSyntaxNode; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
      var
        Action: TCodeAction;
      begin
        Result := TWithResolution.Resolve(Text, Tree, AWith, TLspRefactorings.WithLookup(Resolver, Tree,
          Context.FileName), TLspRefactorings.ExtractOptions(Context), Action, AReason);
        AEdits := Action.Edits;
      end;
  Result := ToJson(TUnwrap.Candidates(AText, ATree, APosition, Options));
end;

end.
