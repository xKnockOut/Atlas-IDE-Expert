unit Atlas.Common.Editing.Providers.Extract;

// IEditingExtract über TExtractRefactoring: parst den Text einmal und versucht mit Duplicates zuerst die
// Extraktion samt gleicher Stellen, sonst nur die Auswahl. Die Korrekturen der Prüfregeln
// (IEditingExtractFixes) arbeiten auf dem Baum der Regel.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract.Extract;

type
  TEditingExtractProvider = class(TInterfacedObject, IEditingExtract, IEditingExtractFixes)
  public
    function ExtractMethod(const AText: string; const ARange: TTextRange;
      const AWish: TEditingExtractWish): TEditingExtractResult;
    function ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
    function ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
      const ANames: TPascalNamePrefixes): IEditingConstantExtraction;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Editing.Extract.Shared,
  Atlas.Common.Editing.Extract;

type
  /// <summary>Hält den Extraktor für alle Literale auf dem Baum des Aufrufers.</summary>
  TEditingConstantExtraction = class(TInterfacedObject, IEditingConstantExtraction)
  private
    FExtractor: TConstantExtractor;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const ANames: TPascalNamePrefixes);
    destructor Destroy; override;
    function Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
  end;

{ TEditingConstantExtraction }

constructor TEditingConstantExtraction.Create(const AText: string; ATree: TSyntaxTree;
  const ANames: TPascalNamePrefixes);
var
  mOptions: TExtractOptions;
begin
  inherited Create;
  mOptions := TExtractOptions.Default;
  mOptions.Names := ANames;
  FExtractor := TConstantExtractor.Create(AText, ATree, mOptions);
end;

destructor TEditingConstantExtraction.Destroy;
begin
  FExtractor.Free;
  inherited Destroy;
end;

function TEditingConstantExtraction.Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
begin
  Result := FExtractor.Run(ARange, False, AAction);
end;

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

function TEditingExtractProvider.ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree;
  const ARange: TTextRange; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
var
  mTree: TSyntaxTree;
  mOptions: TExtractOptions;
begin
  mTree := TSyntaxTreeHandles.TreeOf(ATree);
  if mTree = nil then
  begin
    Exit(False);
  end;
  mOptions := TExtractOptions.Default;
  mOptions.Style := AStyle;
  Result := TExtractRefactoring.ExtractCondition(AText, mTree, ARange, mOptions, AAction);
end;

function TEditingExtractProvider.ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
  const ANames: TPascalNamePrefixes): IEditingConstantExtraction;
var
  mTree: TSyntaxTree;
begin
  Result := nil;
  mTree := TSyntaxTreeHandles.TreeOf(ATree);
  if mTree <> nil then
  begin
    Result := TEditingConstantExtraction.Create(AText, mTree, ANames);
  end;
end;

end.
