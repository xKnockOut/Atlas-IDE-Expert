unit Atlas.Common.Editing.Providers.ClassCompletion;

// IEditingClassCompletion über TClassCompletionScan und TClassCompletion.PairFixes: arbeitet auf dem Baum des
// Aufrufers und hält die Zuordnung je Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Contract.ClassCompletion;

type
  TEditingClassCompletionProvider = class(TInterfacedObject, IEditingClassCompletion)
  public
    function Scan(const AText: string; const ATree: IPascalSyntaxTree; const AUnit: TUnitIndex;
      const ASettings: TClassCompletionSettings; const AStyle: TFormatStyle): IEditingClassCompletionScan;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Editing.ClassBodies,
  Atlas.Common.Editing.ClassCompletion;

type
  /// <summary>Zuordnung einer Unit samt Optionen für neue Rümpfe.</summary>
  TEditingClassCompletionScan = class(TInterfacedObject, IEditingClassCompletionScan)
  private
    FTree: TSyntaxTree;
    FText: string;
    FScan: TClassCompletionScan;
    FOptions: TClassBodyOptions;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AUnit: TUnitIndex;
      const AOptions: TClassBodyOptions);
    destructor Destroy; override;
    function Unmatched: TArray<TEditingUnmatchedMethod>;
    function Pairs: TArray<TEditingSignaturePair>;
    function InPair(const AMethod: TEditingUnmatchedMethod): Boolean;
    function Shape(const ASymbol: TIndexSymbol; out AShape: TEditingSignatureShape): Boolean;
    function MissingBodies(const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
    function AddDeclaration(const AMethod: TEditingUnmatchedMethod; out AEdit: TTextEdit): Boolean;
    function PairFixes(const APair: TEditingSignaturePair; out AFixes: TArray<TCodeAction>): Boolean;
  end;

{ TEditingClassCompletionScan }

constructor TEditingClassCompletionScan.Create(ATree: TSyntaxTree; const AText: string; const AUnit: TUnitIndex;
  const AOptions: TClassBodyOptions);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FOptions := AOptions;
  FScan := TClassCompletionScan.Create(ATree, AText, AUnit);
end;

destructor TEditingClassCompletionScan.Destroy;
begin
  FScan.Free;
  inherited Destroy;
end;

function TEditingClassCompletionScan.Unmatched: TArray<TEditingUnmatchedMethod>;
begin
  Result := FScan.Unmatched;
end;

function TEditingClassCompletionScan.Pairs: TArray<TEditingSignaturePair>;
begin
  Result := FScan.Pairs;
end;

function TEditingClassCompletionScan.InPair(const AMethod: TEditingUnmatchedMethod): Boolean;
begin
  Result := FScan.InPair(AMethod);
end;

function TEditingClassCompletionScan.Shape(const ASymbol: TIndexSymbol; out AShape: TEditingSignatureShape): Boolean;
begin
  Result := FScan.Shape(ASymbol, AShape);
end;

function TEditingClassCompletionScan.MissingBodies(const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
begin
  Result := FScan.MissingBodies(APosition, FOptions, AAction);
end;

function TEditingClassCompletionScan.AddDeclaration(const AMethod: TEditingUnmatchedMethod;
  out AEdit: TTextEdit): Boolean;
begin
  Result := FScan.AddDeclaration(AMethod, AEdit);
end;

function TEditingClassCompletionScan.PairFixes(const APair: TEditingSignaturePair;
  out AFixes: TArray<TCodeAction>): Boolean;
begin
  Result := TClassCompletion.PairFixes(FTree, FText, APair, AFixes);
end;

{ TEditingClassCompletionProvider }

function TEditingClassCompletionProvider.Scan(const AText: string; const ATree: IPascalSyntaxTree;
  const AUnit: TUnitIndex; const ASettings: TClassCompletionSettings;
  const AStyle: TFormatStyle): IEditingClassCompletionScan;
var
  mTree: TSyntaxTree;
begin
  Result := nil;
  mTree := TSyntaxTreeHandles.TreeOf(ATree);
  if mTree <> nil then
  begin
    Result := TEditingClassCompletionScan.Create(mTree, AText, AUnit, TClassBodyOptions.FromSettings(ASettings,
      AStyle));
  end;
end;

end.
