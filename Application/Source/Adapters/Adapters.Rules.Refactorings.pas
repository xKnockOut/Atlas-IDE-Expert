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
  Atlas.Common.ClassActions.Contract,
  Atlas.Common.Rules.Contract.Refactorings,
  Atlas.Common.Editing.Contract.ClassActions,
  Atlas.Common.Editing.Contract.Extract,
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
    function ExtractCondition(const AText: string; const ARange: TTextRange; const AStyle: TFormatStyle;
      out AAction: TCodeAction): Boolean;
    function ConstantExtraction(const AText: string; const ANames: TPascalNamePrefixes): IRuleConstantExtraction;
  end;

  /// <summary>IRuleMethodRefactorings über die Methoden ohne Self von Editing.</summary>
  TRuleMethodRefactoringsAdapter = class(TInterfacedObject, IRuleMethodRefactorings)
  private
    FMethods: IEditingMethodsWithoutSelf;
  public
    constructor Create(const AMethods: IEditingMethodsWithoutSelf);
    function WithoutSelf(const AScan: TRuleMethodScan): TArray<TRuleMethodWithoutSelf>;
  end;

  /// <summary>Die Refactorings für die Prüfregeln aus den APIs von Editing.</summary>
  TRuleRefactoringsAdapters = record
    /// <summary>Ein nil-Argument: diese Korrekturen nicht anbieten.</summary>
    class function Create(const AClasses: IEditingClassActions; const AExtract: IEditingExtractFixes;
      const AMethods: IEditingMethodsWithoutSelf): TRuleRefactorings; static;
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

function TRuleExtractRefactoringsAdapter.ExtractCondition(const AText: string; const ARange: TTextRange;
  const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
begin
  Result := FExtract.ExtractCondition(AText, ARange, AStyle, AAction);
end;

function TRuleExtractRefactoringsAdapter.ConstantExtraction(const AText: string;
  const ANames: TPascalNamePrefixes): IRuleConstantExtraction;
begin
  Result := TRuleConstantExtractionAdapter.Create(FExtract.ConstantExtraction(AText, ANames));
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

{ TRuleRefactoringsAdapters }

class function TRuleRefactoringsAdapters.Create(const AClasses: IEditingClassActions;
  const AExtract: IEditingExtractFixes; const AMethods: IEditingMethodsWithoutSelf): TRuleRefactorings;
begin
  Result := Default(TRuleRefactorings);
  if AClasses <> nil then
  begin
    Result.Classes := TRuleClassRefactoringsAdapter.Create(AClasses);
  end;
  if AExtract <> nil then
  begin
    Result.Extract := TRuleExtractRefactoringsAdapter.Create(AExtract);
  end;
  if AMethods <> nil then
  begin
    Result.Methods := TRuleMethodRefactoringsAdapter.Create(AMethods);
  end;
end;

end.
