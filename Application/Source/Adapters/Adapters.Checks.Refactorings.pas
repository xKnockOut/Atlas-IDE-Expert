unit Adapters.Checks.Refactorings;

// Host-Adapter zwischen Rules und Editing: Prüfregeln bieten Korrekturen aus Refactorings über
// TCheckRefactorings an (SPI im Rules-Contract), Editing bietet die Refactorings über seinen Contract an (API).
// Erzeugt nur in Shell.Composition.*; kennt nur die Contracts.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.ClassActions.Contract,
  Atlas.Common.Checks.Contract.Refactorings,
  Atlas.Common.Editing.Contract.ClassActions,
  Atlas.Common.Editing.Contract.ClassCompletion,
  Atlas.Common.Editing.Contract.Extract,
  Atlas.Common.Editing.Contract.MethodOrder,
  Atlas.Common.Editing.Contract.MethodWithoutSelf,
  Atlas.Common.Editing.Contract.SlashCommands;

type
  /// <summary>ICheckClassRefactorings über die Klassen-Aktionen von Editing.</summary>
  TCheckClassRefactoringsAdapter = class(TInterfacedObject, ICheckClassRefactorings)
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

  /// <summary>ICheckExtractRefactorings über „Extrahieren“ von Editing.</summary>
  TCheckExtractRefactoringsAdapter = class(TInterfacedObject, ICheckExtractRefactorings)
  private
    FExtract: IEditingExtractFixes;
  public
    constructor Create(const AExtract: IEditingExtractFixes);
    function ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
    function ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
      const ANames: TPascalNamePrefixes): ICheckConstantExtraction;
  end;

  /// <summary>ICheckMethodRefactorings über die Methoden ohne Self von Editing.</summary>
  TCheckMethodRefactoringsAdapter = class(TInterfacedObject, ICheckMethodRefactorings)
  private
    FMethods: IEditingMethodsWithoutSelf;
  public
    constructor Create(const AMethods: IEditingMethodsWithoutSelf);
    function WithoutSelf(const AScan: TCheckMethodScan): TArray<TCheckMethodWithoutSelf>;
  end;

  /// <summary>ICheckMethodOrderRefactorings über die Prüfung der Methodenordnung von Editing.</summary>
  TCheckMethodOrderRefactoringsAdapter = class(TInterfacedObject, ICheckMethodOrderRefactorings)
  private
    FOrder: IEditingMethodOrderReview;
  public
    constructor Create(const AOrder: IEditingMethodOrderReview);
    function Review(const AText: string; const ATree: IPascalSyntaxTree;
      const ARequest: TCheckMethodOrderRequest): TCheckMethodOrderReview;
  end;

  /// <summary>ICheckClassCompletionRefactorings über die Klassenvervollständigung von Editing.</summary>
  TCheckClassCompletionRefactoringsAdapter = class(TInterfacedObject, ICheckClassCompletionRefactorings)
  private
    FCompletion: IEditingClassCompletion;
  public
    constructor Create(const ACompletion: IEditingClassCompletion);
    function Scan(const AText: string; const ATree: IPascalSyntaxTree; const AUnit: TUnitIndex;
      const ASettings: TClassCompletionSettings; const AStyle: TFormatStyle): ICheckClassCompletionScan;
  end;

  /// <summary>ICheckSlashCommands über die Prüfung der Schnellbefehle von Editing.</summary>
  TCheckSlashCommandsAdapter = class(TInterfacedObject, ICheckSlashCommands)
  private
    FChecks: IEditingSlashChecks;
  public
    constructor Create(const AChecks: IEditingSlashChecks);
    function Problems(const AText: string; const AIndex: ISymbolIndex;
      const ADelphiVersion: string): TArray<TCheckSlashProblem>;
    function IgnoreWithoutHit(const ARuleId: string): string;
  end;

  /// <summary>Die APIs von Editing, aus denen die Korrekturen der Prüfregeln entstehen; nil = nicht anbieten.
  /// </summary>
  TCheckRefactoringSources = record
    Classes: IEditingClassActions;
    Extract: IEditingExtractFixes;
    Methods: IEditingMethodsWithoutSelf;
    Order: IEditingMethodOrderReview;
    Completion: IEditingClassCompletion;
    Commands: IEditingSlashChecks;
  end;

  /// <summary>Die Refactorings für die Prüfregeln aus den APIs von Editing.</summary>
  TCheckRefactoringsAdapters = record
    /// <summary>Ein nil-Eintrag in ASources: diese Korrekturen nicht anbieten.</summary>
    class function Create(const ASources: TCheckRefactoringSources): TCheckRefactorings; static;
  end;

implementation

uses
  Atlas.Common.Editing.Contract,
  Atlas.Common.Semantics.Contract;

{ TCheckClassRefactoringsAdapter }

constructor TCheckClassRefactoringsAdapter.Create(const AActions: IEditingClassActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TCheckClassRefactoringsAdapter.OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.OverrideMethod(ARequest, AName, AAction);
end;

function TCheckClassRefactoringsAdapter.ImplementInterface(const ARequest: TClassEditRequest;
  const AInterface: string; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.ImplementInterface(ARequest, AInterface, AAction);
end;

function TCheckClassRefactoringsAdapter.CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.CreateAccessor(ARequest, APlan, AAction);
end;

type
  /// <summary>ICheckConstantExtraction über die von Editing.</summary>
  TCheckConstantExtractionAdapter = class(TInterfacedObject, ICheckConstantExtraction)
  private
    FExtraction: IEditingConstantExtraction;
  public
    constructor Create(const AExtraction: IEditingConstantExtraction);
    function Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
  end;

{ TCheckConstantExtractionAdapter }

constructor TCheckConstantExtractionAdapter.Create(const AExtraction: IEditingConstantExtraction);
begin
  inherited Create;
  FExtraction := AExtraction;
end;

function TCheckConstantExtractionAdapter.Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
begin
  Result := FExtraction.Run(ARange, AAction);
end;

{ TCheckExtractRefactoringsAdapter }

constructor TCheckExtractRefactoringsAdapter.Create(const AExtract: IEditingExtractFixes);
begin
  inherited Create;
  FExtract := AExtract;
end;

function TCheckExtractRefactoringsAdapter.ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree;
  const ARange: TTextRange; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
begin
  Result := FExtract.ExtractCondition(AText, ATree, ARange, AStyle, AAction);
end;

function TCheckExtractRefactoringsAdapter.ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
  const ANames: TPascalNamePrefixes): ICheckConstantExtraction;
var
  mExtraction: IEditingConstantExtraction;
begin
  Result := nil;
  mExtraction := FExtract.ConstantExtraction(AText, ATree, ANames);
  if mExtraction <> nil then
  begin
    Result := TCheckConstantExtractionAdapter.Create(mExtraction);
  end;
end;

{ TCheckMethodRefactoringsAdapter }

constructor TCheckMethodRefactoringsAdapter.Create(const AMethods: IEditingMethodsWithoutSelf);
begin
  inherited Create;
  FMethods := AMethods;
end;

function TCheckMethodRefactoringsAdapter.WithoutSelf(const AScan: TCheckMethodScan): TArray<TCheckMethodWithoutSelf>;
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

{ TCheckMethodOrderRefactoringsAdapter }

constructor TCheckMethodOrderRefactoringsAdapter.Create(const AOrder: IEditingMethodOrderReview);
begin
  inherited Create;
  FOrder := AOrder;
end;

function TCheckMethodOrderRefactoringsAdapter.Review(const AText: string; const ATree: IPascalSyntaxTree;
  const ARequest: TCheckMethodOrderRequest): TCheckMethodOrderReview;
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
  Result := Default(TCheckMethodOrderReview);
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

type
  /// <summary>ICheckClassCompletionScan über die Zuordnung von Editing.</summary>
  TCheckClassCompletionScanAdapter = class(TInterfacedObject, ICheckClassCompletionScan)
  private
    FScan: IEditingClassCompletionScan;
  public
    constructor Create(const AScan: IEditingClassCompletionScan);
    function Unmatched: TArray<TUnmatchedMethod>;
    function Pairs: TArray<TSignaturePair>;
    function InPair(const AMethod: TUnmatchedMethod): Boolean;
    function Shape(const ASymbol: TIndexSymbol; out AShape: TSignatureShape): Boolean;
    function MissingBodies(const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
    function AddDeclaration(const AMethod: TUnmatchedMethod; out AEdit: TTextEdit): Boolean;
    function PairFixes(const APair: TSignaturePair; out AFixes: TArray<TCodeAction>): Boolean;
  end;

{ TCheckClassCompletionScanAdapter }

constructor TCheckClassCompletionScanAdapter.Create(const AScan: IEditingClassCompletionScan);
begin
  inherited Create;
  FScan := AScan;
end;

function TCheckClassCompletionScanAdapter.Unmatched: TArray<TUnmatchedMethod>;
begin
  Result := FScan.Unmatched;
end;

function TCheckClassCompletionScanAdapter.Pairs: TArray<TSignaturePair>;
begin
  Result := FScan.Pairs;
end;

function TCheckClassCompletionScanAdapter.InPair(const AMethod: TUnmatchedMethod): Boolean;
begin
  Result := FScan.InPair(AMethod);
end;

function TCheckClassCompletionScanAdapter.Shape(const ASymbol: TIndexSymbol; out AShape: TSignatureShape): Boolean;
begin
  Result := FScan.Shape(ASymbol, AShape);
end;

function TCheckClassCompletionScanAdapter.MissingBodies(const APosition: TTextPosition;
  out AAction: TCodeAction): Boolean;
begin
  Result := FScan.MissingBodies(APosition, AAction);
end;

function TCheckClassCompletionScanAdapter.AddDeclaration(const AMethod: TUnmatchedMethod;
  out AEdit: TTextEdit): Boolean;
begin
  Result := FScan.AddDeclaration(AMethod, AEdit);
end;

function TCheckClassCompletionScanAdapter.PairFixes(const APair: TSignaturePair;
  out AFixes: TArray<TCodeAction>): Boolean;
begin
  Result := FScan.PairFixes(APair, AFixes);
end;

{ TCheckClassCompletionRefactoringsAdapter }

constructor TCheckClassCompletionRefactoringsAdapter.Create(const ACompletion: IEditingClassCompletion);
begin
  inherited Create;
  FCompletion := ACompletion;
end;

function TCheckClassCompletionRefactoringsAdapter.Scan(const AText: string; const ATree: IPascalSyntaxTree;
  const AUnit: TUnitIndex; const ASettings: TClassCompletionSettings;
  const AStyle: TFormatStyle): ICheckClassCompletionScan;
var
  mScan: IEditingClassCompletionScan;
begin
  Result := nil;
  mScan := FCompletion.Scan(AText, ATree, AUnit, ASettings, AStyle);
  if mScan <> nil then
  begin
    Result := TCheckClassCompletionScanAdapter.Create(mScan);
  end;
end;

{ TCheckSlashCommandsAdapter }

constructor TCheckSlashCommandsAdapter.Create(const AChecks: IEditingSlashChecks);
begin
  inherited Create;
  FChecks := AChecks;
end;

function TCheckSlashCommandsAdapter.Problems(const AText: string; const AIndex: ISymbolIndex;
  const ADelphiVersion: string): TArray<TCheckSlashProblem>;
var
  mFound: TArray<TSlashProblem>;
  mIndex: Integer;
begin
  mFound := FChecks.Problems(AText, AIndex, ADelphiVersion);
  SetLength(Result, Length(mFound));
  for mIndex := 0 to High(mFound) do
  begin
    Result[mIndex].Range := mFound[mIndex].Range;
    Result[mIndex].Message := mFound[mIndex].Message;
  end;
end;

function TCheckSlashCommandsAdapter.IgnoreWithoutHit(const ARuleId: string): string;
begin
  Result := FChecks.IgnoreWithoutHit(ARuleId);
end;

{ TCheckRefactoringsAdapters }

class function TCheckRefactoringsAdapters.Create(const ASources: TCheckRefactoringSources): TCheckRefactorings;
begin
  Result := Default(TCheckRefactorings);
  if ASources.Classes <> nil then
  begin
    Result.Classes := TCheckClassRefactoringsAdapter.Create(ASources.Classes);
  end;
  if ASources.Extract <> nil then
  begin
    Result.Extract := TCheckExtractRefactoringsAdapter.Create(ASources.Extract);
  end;
  if ASources.Methods <> nil then
  begin
    Result.Methods := TCheckMethodRefactoringsAdapter.Create(ASources.Methods);
  end;
  if ASources.Order <> nil then
  begin
    Result.Order := TCheckMethodOrderRefactoringsAdapter.Create(ASources.Order);
  end;
  if ASources.Completion <> nil then
  begin
    Result.Completion := TCheckClassCompletionRefactoringsAdapter.Create(ASources.Completion);
  end;
  if ASources.Commands <> nil then
  begin
    Result.Commands := TCheckSlashCommandsAdapter.Create(ASources.Commands);
  end;
end;

end.
