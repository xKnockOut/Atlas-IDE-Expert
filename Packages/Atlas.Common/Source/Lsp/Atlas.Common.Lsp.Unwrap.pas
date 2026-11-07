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
    cCommand = 'atlas.server.unwrap';
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
  mRange: TTextRange;
begin
  Result := TJSONArray.Create;
  for mRange in ARanges do
  begin
    Result.AddElement(TLspPositions.RangeToJson(mRange));
  end;
end;

function EditsToJson(const AEdits: TArray<TTextEdit>): TJSONArray;
var
  mEdit: TTextEdit;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    Result.AddElement(mItem);
  end;
end;

class function TLspUnwrap.ToJson(const ACandidates: TArray<TUnwrapCandidate>): TJSONObject;
var
  mCandidates, mVariants: TJSONArray;
  mCandidate: TUnwrapCandidate;
  mChoice: TUnwrapVariant;
  mItem, mVariantItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  mCandidates := TJSONArray.Create;
  Result.AddPair('candidates', mCandidates);
  for mCandidate in ACandidates do
  begin
    mItem := TJSONObject.Create;
    mCandidates.AddElement(mItem);
    mItem.AddPair('kind', TUnwrap.KindName(mCandidate.Kind));
    mItem.AddPair('range', TLspPositions.RangeToJson(mCandidate.Range));
    mItem.AddPair('note', TUnwrap.NoteName(mCandidate.Note));
    mItem.AddPair('noteText', mCandidate.NoteText);
    mVariants := TJSONArray.Create;
    mItem.AddPair('variants', mVariants);
    for mChoice in mCandidate.Variants do
    begin
      mVariantItem := TJSONObject.Create;
      mVariants.AddElement(mVariantItem);
      mVariantItem.AddPair('kind', TUnwrap.VariantName(mChoice.Kind));
      mVariantItem.AddPair('branch', TJSONNumber.Create(mChoice.Branch));
      mVariantItem.AddPair('edits', EditsToJson(mChoice.Edits));
      mVariantItem.AddPair('keep', RangesToJson(mChoice.Keep));
      mVariantItem.AddPair('remove', RangesToJson(mChoice.Remove));
    end;
  end;
end;

class function TLspUnwrap.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; AIndentWidth: Integer): TJSONObject;
var
  mOptions: TUnwrapOptions;
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mContext: TRefactoringContext;
begin
  mOptions := TUnwrapOptions.Default;
  mOptions.IndentWidth := AIndentWidth;
  if mOptions.IndentWidth <= 0 then
  begin
    mOptions.IndentWidth := AContext.Style.IndentSize;
  end;
  mText := AText;
  mTree := ATree;
  mResolver := AResolver;
  mContext := AContext;
  if mResolver <> nil then
  begin
    mOptions.ResolveWith :=
      function(AWith: TSyntaxNode; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
      var
        Resolved: TWithResolved;
      begin
        Result := TWithResolution.Resolve(mText, mTree, AWith, TLspRefactorings.WithLookup(mResolver, mTree,
          mContext.FileName), TLspRefactorings.ExtractOptions(mContext), Resolved);
        AEdits := Resolved.Action.Edits;
        AReason := Resolved.Reason;
      end;
  end;
  Result := ToJson(TUnwrap.Candidates(AText, ATree, APosition, mOptions));
end;

end.
