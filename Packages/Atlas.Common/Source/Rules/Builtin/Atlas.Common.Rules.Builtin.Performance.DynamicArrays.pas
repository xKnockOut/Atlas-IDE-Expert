unit Atlas.Common.Rules.Builtin.Performance.DynamicArrays;

// Erkennt dynamische Arrays für setlength-in-loop und managed-param-without-const: array of X, TArray<X>, bekannte
// Array-Typen der RTL und Typen der Datei, die so deklariert sind.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  TDynamicArrayTypes = class
  public const
    /// <summary>Dynamische Arrays der RTL, die nicht in der Datei deklariert sind.</summary>
    cRtlDynamicArrays: array[0..13] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray',
      'TInt64DynArray', 'TCardinalDynArray', 'TDoubleDynArray', 'TSingleDynArray', 'TByteDynArray',
      'TWordDynArray', 'TBooleanDynArray', 'TShortIntDynArray', 'TSmallIntDynArray', 'TLongWordDynArray',
      'TExtendedDynArray');
  public
    /// <summary>Ist ATypeText ein dynamisches Array? ADeclared: Namen der Array-Typen der Datei.</summary>
    class function IsDynamic(const ATypeText: string; const ADeclared: TArray<string>): Boolean; static;
    /// <summary>Namen der Typen der Datei, die als dynamisches Array deklariert sind (T = array of X bzw.
    /// TArray&lt;X&gt;).</summary>
    class function DeclaredIn(const AText: string; ARoot: TSyntaxNode): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

/// <summary>Ist der Typknoten ANode mit dem Text AText ein dynamisches Array?</summary>
function IsDynamicNode(ANode: TSyntaxNode; const AText: string): Boolean;
begin
  Result := ((ANode.Kind = TSyntaxKind.ArrayType) and StartsText('array of ', AText)) or
    ((ANode.Kind = TSyntaxKind.TypeReference) and StartsText('TArray<', AText));
end;

{ TDynamicArrayTypes }

class function TDynamicArrayTypes.IsDynamic(const ATypeText: string; const ADeclared: TArray<string>): Boolean;
var
  mText: string;
begin
  mText := Trim(ATypeText);
  Result := StartsText('array of ', mText) or StartsText('TArray<', mText) or MatchText(mText, cRtlDynamicArrays) or
    MatchText(mText, ADeclared);
end;

class function TDynamicArrayTypes.DeclaredIn(const AText: string; ARoot: TSyntaxNode): TArray<string>;
var
  mFound: TArray<string>;
  mText: string;
begin
  mFound := nil;
  mText := AText;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mChild: TSyntaxNode;
    begin
      Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.ClassType, TSyntaxKind.RecordType]);
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.ChildCount > 0) then
      begin
        mChild := ANode[ANode.ChildCount - 1];
        if IsDynamicNode(mChild, Trim(Copy(mText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset))) then
        begin
          mFound := mFound + [ANode.Name];
        end;
      end;
    end);
  Result := mFound;
end;

end.
