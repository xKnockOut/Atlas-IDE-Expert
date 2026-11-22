unit Atlas.Common.Editing.Providers.CompilerFixes;

// IEditingCompilerFixes über TCompilerFixes.Fixes.

interface

uses
  Atlas.Common.Editing.Contract.CompilerFixes;

type
  TEditingCompilerFixesProvider = class(TInterfacedObject, IEditingCompilerFixes)
  public
    function Fixes(const AText: string; const AMessage: TFixMessage): TArray<TCompilerFix>;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CompilerFixes;

{ TEditingCompilerFixesProvider }

function TEditingCompilerFixesProvider.Fixes(const AText: string; const AMessage: TFixMessage): TArray<TCompilerFix>;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TCompilerFixes.Fixes(AText, mTree, AMessage, Default(TCompilerFixContext));
  finally
    mTree.Free;
  end;
end;

end.
