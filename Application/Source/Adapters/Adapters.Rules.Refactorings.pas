unit Adapters.Rules.Refactorings;

// Host-Adapter zwischen Rules und Editing: Prüfregeln bieten Korrekturen aus Refactorings über
// TRuleRefactorings an (SPI im Rules-Contract), Editing bietet die Refactorings über seinen Contract an (API).
// Erzeugt nur in Shell.Composition.*; kennt nur die Contracts.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.CodeActions.Contract.Classes,
  Atlas.Common.Rules.Contract.Refactorings,
  Atlas.Common.Editing.Contract.ClassActions,
  Atlas.Common.Editing.Contract.Extract,
  Atlas.Common.Editing.Contract.MethodOrder,
  Atlas.Common.Editing.Contract.MethodWithoutSelf;

type
  /// <summary>IRuleClassRefactorings über die Klassen-Aktionen von Editing.</summary>
  TRuleClassRefactoringsAdapter = class(TInterfacedObject, IRuleClassRefactorings)
  private
    FActions: IEditingClassActions;
  public
    constructor Create(const AActions: IEditingClassActions);
    function OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
      out AAction: TCodeAction): Boolean;
    function ImplementInterface(const ARequest: TClassEditRequest; const AInterface: string;
      out AAction: TCodeAction): Boolean;
    function CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
      out AAction: TCodeAction): Boolean;
  end;

  /// <summary>IRuleExtractRefactorings über „Extrahieren“ von Editing.</summary>
  TRuleExtractRefactoringsAdapter = class(TInterfacedObject, IRuleExtractRefactorings)
  private
    FExtract: IEditingExtractFixes;
  public
    constructor Create(const AExtract: IEditingExtractFixes);
    function ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
    function ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
      const ANames: TPascalNamePrefixes): IRuleConstantExtraction;
  end;

  /// <summary>IRuleMethodRefactorings über die Methoden ohne Self von Editing.</summary>
  TRuleMethodRefactoringsAdapter = class(TInterfacedObject, IRuleMethodRefactorings)
  private
    FMethods: IEditingMethodsWithoutSelf;
  public
    constructor Create(const AMethods: IEditingMethodsWithoutSelf);
    function WithoutSelf(const AScan: TRuleMethodScan): TArray<TRuleMethodWithoutSelf>;
  end;

  /// <summary>IRuleMethodOrderRefactorings über die Prüfung der Methodenordnung von Editing.</summary>
  TRuleMethodOrderRefactoringsAdapter = class(TInterfacedObject, IRuleMethodOrderRefactorings)
  private
    FOrder: IEditingMethodOrderReview;
  public
    constructor Create(const AOrder: IEditingMethodOrderReview);
    function Review(const AText: string; const ATree: IPascalSyntaxTree;
      const ARequest: TRuleMethodOrderRequest): TRuleMethodOrderReview;
  end;

  /// <summary>Die APIs von Editing, aus denen die Korrekturen der Prüfregeln entstehen; nil = nicht anbieten.
  /// </summary>
  TRuleRefactoringSources = record
    Classes: IEditingClassActions;
    Extract: IEditingExtractFixes;
    Methods: IEditingMethodsWithoutSelf;
    Order: IEditingMethodOrderReview;
  end;

  /// <summary>Die Refactorings für die Prüfregeln aus den APIs von Editing.</summary>
  TRuleRefactoringsAdapters = record
    /// <summary>Ein nil-Eintrag in ASources: diese Korrekturen nicht anbieten.</summary>
    class function Create(const ASources: TRuleRefactoringSources): TRuleRefactorings; static;
  end;

implementation

{ TRuleClassRefactoringsAdapter }

constructor TRuleClassRefactoringsAdapter.Create(const AActions: IEditingClassActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TRuleClassRefactoringsAdapter.OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.OverrideMethod(ARequest, AName, AAction);
end;

function TRuleClassRefactoringsAdapter.ImplementInterface(const ARequest: TClassEditRequest;
  const AInterface: string; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.ImplementInterface(ARequest, AInterface, AAction);
end;

function TRuleClassRefactoringsAdapter.CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.CreateAccessor(ARequest, APlan, AAction);
end;

type
  /// <summary>IRuleConstantExtraction über die von Editing.</summary>
  TRuleConstantExtractionAdapter = class(TInterfacedObject, IRuleConstantExtraction)
  private
    FExtraction: IEditingConstantExtraction;
  public
    constructor Create(const AExtraction: IEditingConstantExtraction);
    function Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
  end;

{ TRuleConstantExtractionAdapter }

constructor TRuleConstantExtractionAdapter.Create(const AExtraction: IEditingConstantExtraction);
begin
  inherited Create;
  FExtraction := AExtraction;
end;

function TRuleConstantExtractionAdapter.Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
begin
  Result := FExtraction.Run(ARange, AAction);
end;

{ TRuleExtractRefactoringsAdapter }

constructor TRuleExtractRefactoringsAdapter.Create(const AExtract: IEditingExtractFixes);
begin
  inherited Create;
  FExtract := AExtract;
end;

function TRuleExtractRefactoringsAdapter.ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree;
  const ARange: TTextRange; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
begin
  Result := FExtract.ExtractCondition(AText, ATree, ARange, AStyle, AAction);
end;

function TRuleExtractRefactoringsAdapter.ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
  const ANames: TPascalNamePrefixes): IRuleConstantExtraction;
var
  mExtraction: IEditingConstantExtraction;
begin
  Result := nil;
  mExtraction := FExtract.ConstantExtraction(AText, ATree, ANames);
  if mExtraction <> nil then
  begin
    Result := TRuleConstantExtractionAdapter.Create(mExtraction);
  end;
end;

{ TRuleMethodRefactoringsAdapter }

constructor TRuleMethodRefactoringsAdapter.Create(const AMethods: IEditingMethodsWithoutSelf);
begin
  inherited Create;
  FMethods := AMethods;
end;

function TRuleMethodRefactoringsAdapter.WithoutSelf(const AScan: TRuleMethodScan): TArray<TRuleMethodWithoutSelf>;
var
  mScan: TEditingMethodScan;
  mFound: TArray<TEditingMethodWithoutSelf>;
  mIndex: Integer;
begin
  mScan := Default(TEditingMethodScan);
  mScan.FileName := AScan.FileName;
  mScan.Text := AScan.Text;
  mScan.Tree := AScan.Tree;
  mScan.FormText := AScan.FormText;
  mScan.Index := AScan.Index;
  mScan.EnsureUnit := AScan.EnsureUnit;
  mScan.Namespaces := AScan.Namespaces;
  mScan.WithStatic := AScan.WithStatic;
  mScan.Style := AScan.Style;
  mFound := FMethods.Scan(mScan);
  Result := nil;
  SetLength(Result, Length(mFound));
  for mIndex := 0 to High(mFound) do
  begin
    Result[mIndex].ClassName := mFound[mIndex].ClassName;
    Result[mIndex].Name := mFound[mIndex].Name;
    Result[mIndex].NamePosition := mFound[mIndex].NamePosition;
    Result[mIndex].HasFix := mFound[mIndex].HasFix;
    Result[mIndex].Fix := mFound[mIndex].Fix;
  end;
end;

{ TRuleMethodOrderRefactoringsAdapter }

constructor TRuleMethodOrderRefactoringsAdapter.Create(const AOrder: IEditingMethodOrderReview);
begin
  inherited Create;
  FOrder := AOrder;
end;

function TRuleMethodOrderRefactoringsAdapter.Review(const AText: string; const ATree: IPascalSyntaxTree;
  const ARequest: TRuleMethodOrderRequest): TRuleMethodOrderReview;
var
  mRequest: TEditingMethodOrderRequest;
  mFound: TEditingMethodOrderReview;
  mIndex: Integer;
begin
  mRequest := Default(TEditingMethodOrderRequest);
  mRequest.Placement := ARequest.Placement;
  mRequest.LifecycleFirst := ARequest.LifecycleFirst;
  mRequest.BlankLines := ARequest.BlankLines;
  mRequest.TypeComment := ARequest.TypeComment;
  mRequest.LineLength := ARequest.LineLength;
  mFound := FOrder.Review(AText, ATree, mRequest);
  Result := Default(TRuleMethodOrderReview);
  Result.Placement := mFound.Placement;
  SetLength(Result.Types, Length(mFound.Types));
  for mIndex := 0 to High(mFound.Types) do
  begin
    Result.Types[mIndex].TypeName := mFound.Types[mIndex].TypeName;
    Result.Types[mIndex].NameRange := mFound.Types[mIndex].NameRange;
    Result.Types[mIndex].OrderEdits := mFound.Types[mIndex].OrderEdits;
    Result.Types[mIndex].CommentEdits := mFound.Types[mIndex].CommentEdits;
    Result.Types[mIndex].CommentText := mFound.Types[mIndex].CommentText;
  end;
end;

{ TRuleRefactoringsAdapters }

class function TRuleRefactoringsAdapters.Create(const ASources: TRuleRefactoringSources): TRuleRefactorings;
begin
  Result := Default(TRuleRefactorings);
  if ASources.Classes <> nil then
  begin
    Result.Classes := TRuleClassRefactoringsAdapter.Create(ASources.Classes);
  end;
  if ASources.Extract <> nil then
  begin
    Result.Extract := TRuleExtractRefactoringsAdapter.Create(ASources.Extract);
  end;
  if ASources.Methods <> nil then
  begin
    Result.Methods := TRuleMethodRefactoringsAdapter.Create(ASources.Methods);
  end;
  if ASources.Order <> nil then
  begin
    Result.Order := TRuleMethodOrderRefactoringsAdapter.Create(ASources.Order);
  end;
end;

end.
