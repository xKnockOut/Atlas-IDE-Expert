unit Editing.Providers.MethodOrder;

// IEditingMethodOrderReview über TMethodOrder.Review: übersetzt den Wunsch in TMethodOrderOptions und das
// Ergebnis in die Records des Contracts.

interface

uses
  Atlas.Common.Pascal.Contract,
  Editing.Contract.MethodOrder;

type
  TEditingMethodOrderProvider = class(TInterfacedObject, IEditingMethodOrderReview)
  public
    function Review(const AText: string; const ATree: IPascalSyntaxTree;
      const ARequest: TEditingMethodOrderRequest): TEditingMethodOrderReview;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TypeComments,
  Editing.MethodOrder;

/// <summary>Optionen von TMethodOrder aus dem Wunsch.</summary>
function OptionsOf(const ARequest: TEditingMethodOrderRequest): TMethodOrderOptions;
begin
  Result := TMethodOrderOptions.Create(TMethodOrder.PlacementOf(ARequest.Placement));
  Result.LifecycleFirst := ARequest.LifecycleFirst;
  Result.BlankLines := ARequest.BlankLines;
  Result.TypeComment := TTypeComments.StyleOf(ARequest.TypeComment);
  Result.LineLength := ARequest.LineLength;
end;

{ TEditingMethodOrderProvider }

function TEditingMethodOrderProvider.Review(const AText: string; const ATree: IPascalSyntaxTree;
  const ARequest: TEditingMethodOrderRequest): TEditingMethodOrderReview;
var
  mTree: TSyntaxTree;
  mOptions: TMethodOrderOptions;
  mFound: TArray<TMethodTypeReview>;
  mIndex: Integer;
begin
  Result := Default(TEditingMethodOrderReview);
  mOptions := OptionsOf(ARequest);
  Result.Placement := TMethodOrder.PlacementName(mOptions.Placement);
  mTree := TSyntaxTree.FromHandle(ATree);
  if mTree = nil then
  begin
    Exit;
  end;
  mFound := TMethodOrder.Review(mTree, AText, mOptions);
  SetLength(Result.Types, Length(mFound));
  for mIndex := 0 to High(mFound) do
  begin
    Result.Types[mIndex].TypeName := mFound[mIndex].TypeName;
    Result.Types[mIndex].NameRange := mFound[mIndex].NameRange;
    Result.Types[mIndex].OrderEdits := mFound[mIndex].OrderEdits;
    Result.Types[mIndex].CommentEdits := mFound[mIndex].CommentEdits;
    Result.Types[mIndex].CommentText := mFound[mIndex].CommentText;
  end;
end;

end.
