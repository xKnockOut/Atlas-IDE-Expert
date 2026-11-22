unit Atlas.Common.Editing.Providers.Extract;

// IEditingExtract über TExtractRefactoring: parst den Text einmal und versucht mit Duplicates zuerst die
// Extraktion samt gleicher Stellen, sonst nur die Auswahl.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract.Extract;

type
  TEditingExtractProvider = class(TInterfacedObject, IEditingExtract)
  public
    function ExtractMethod(const AText: string; const ARange: TTextRange;
      const AWish: TEditingExtractWish): TEditingExtractResult;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.Extract.Shared,
  Atlas.Common.Editing.Extract;

function OptionsOf(const AWish: TEditingExtractWish): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := AWish.InlineVar;
  Result.Style := AWish.Style;
  Result.Duplicates := AWish.Duplicates;
  Result.MethodName := AWish.MethodName;
end;

{ TEditingExtractProvider }

function TEditingExtractProvider.ExtractMethod(const AText: string; const ARange: TTextRange;
  const AWish: TEditingExtractWish): TEditingExtractResult;
var
  mTree: TSyntaxTree;
  mOptions: TExtractOptions;
begin
  Result := Default(TEditingExtractResult);
  mOptions := OptionsOf(AWish);
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    if AWish.Duplicates then
    begin
      Result.Extracted := TExtractRefactoring.ExtractMethodWithDuplicates(AText, mTree, ARange, mOptions,
        Result.Action, Result.DuplicatesReason);
      if Result.Extracted then
      begin
        Result.DuplicatesReason := '';
        Exit;
      end;
    end;
    Result.Extracted := TExtractRefactoring.ExtractMethod(AText, mTree, ARange, mOptions, Result.Action,
      Result.Reason);
  finally
    mTree.Free;
  end;
end;

end.
