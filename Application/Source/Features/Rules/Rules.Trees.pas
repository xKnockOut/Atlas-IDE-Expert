unit Rules.Trees;

// Syntaxbaum einer Prüfung: Rules.Contract reicht den Baum nur als Handle (TRuleContext.TreeHandle,
// IPascalSyntaxTree aus dem Pascal-Contract), damit der Contract den Syntaxbaum nicht einbindet. Regeln und wer
// einen Kontext baut, lesen und setzen ihn über diesen Helfer als TSyntaxTree (AContext.Tree).

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Rules.Contract;

type
  /// <summary>Baum hinter TRuleContext.TreeHandle.</summary>
  TRuleContextTree = record helper for TRuleContext
  private
    function GetTree: TSyntaxTree;
    procedure SetTree(ATree: TSyntaxTree);
  public
    /// <summary>Syntaxbaum des Textes; gehört dem Aufrufer. nil ohne Baum.</summary>
    property Tree: TSyntaxTree read GetTree write SetTree;
  end;

implementation

{ TRuleContextTree }

function TRuleContextTree.GetTree: TSyntaxTree;
begin
  Result := TSyntaxTree.FromHandle(TreeHandle);
end;

procedure TRuleContextTree.SetTree(ATree: TSyntaxTree);
begin
  TreeHandle := TSyntaxTree.HandleOf(ATree);
end;

end.
