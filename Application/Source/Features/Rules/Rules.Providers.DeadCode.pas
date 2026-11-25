unit Rules.Providers.DeadCode;

// Anbieter von IRuleDeadCode (Rules.Contract.Api) für find_unused_code (#64): die Regeln für
// ungenutzten Code (unused-private-member, unused-public-member, unused-declaration, unused-unit) aus den Regeln des
// Hosts, mit Index, Projekten und Namensräumen wie im Editor; die Formulardatei neben einer .pas sehen die Regeln
// mit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Rules.Contract,
  Atlas.Common.Findings.Contract,
  Rules.Contract.Api,
  Atlas.Common.Projects.Contract.Group;

type
  TRuleDeadCodeProvider = class(TInterfacedObject, IRuleDeadCode)
  private
    FRules: TArray<IRule>;
    FIndex: ISymbolIndex;
    FProjectFiles: IProjectGroupFiles;
    FNamespaces: TArray<string>;
  public
    /// <summary>ARules: alle Regeln, davon gelten die für ungenutzten Code; AProjectFiles nil = keine Datei lesbar,
    /// gilt als vollständig.</summary>
    constructor Create(const ARules: TArray<IRule>; const AIndex: ISymbolIndex;
      const AProjectFiles: IProjectGroupFiles; const ANamespaces: TArray<string>);
    function RuleIds: TArray<string>;
    function Available: Boolean;
    function Complete(out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Rules.Engine,
  Rules.Builtin.Visibility,
  Rules.Builtin.PublicMembers,
  Rules.Builtin.DeadCode;

const
  cDeadCodeIds: array[0..3] of string = (cUnusedPrivateMemberRuleId, cUnusedPublicMemberRuleId,
    cUnusedDeclarationRuleId, cUnusedUnitRuleId);

{ TRuleDeadCodeProvider }

constructor TRuleDeadCodeProvider.Create(const ARules: TArray<IRule>; const AIndex: ISymbolIndex;
  const AProjectFiles: IProjectGroupFiles; const ANamespaces: TArray<string>);
var
  mRule: IRule;
begin
  inherited Create;
  FRules := nil;
  for mRule in ARules do
  begin
    if IndexText(mRule.Descriptor.Id, cDeadCodeIds) >= 0 then
    begin
      FRules := FRules + [mRule];
    end;
  end;
  FIndex := AIndex;
  FProjectFiles := AProjectFiles;
  FNamespaces := ANamespaces;
end;

function TRuleDeadCodeProvider.RuleIds: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(cDeadCodeIds));
  for mIndex := 0 to High(cDeadCodeIds) do
  begin
    Result[mIndex] := cDeadCodeIds[mIndex];
  end;
end;

function TRuleDeadCodeProvider.Available: Boolean;
begin
  Result := FRules <> nil;
end;

function TRuleDeadCodeProvider.Complete(out AReason: string): Boolean;
begin
  AReason := '';
  Result := (FProjectFiles = nil) or FProjectFiles.Complete(AReason);
end;

function TRuleDeadCodeProvider.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := (FProjectFiles <> nil) and FProjectFiles.ReadText(AFileName, AText);
end;

function TRuleDeadCodeProvider.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mContext := Default(TRuleContext);
    mContext.FileName := AFileName;
    mContext.RelativePath := StringReplace(ARelativePath, '\', '/', [rfReplaceAll]);
    mContext.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
    mContext.Text := AText;
    mContext.Tree := mTree;
    mContext.Index := FIndex;
    mContext.Namespaces := FNamespaces;
    mContext.ProjectFiles := FProjectFiles;
    if (FProjectFiles <> nil) and SameText(ExtractFileExt(AFileName), '.pas') and
      not FProjectFiles.ReadText(ChangeFileExt(AFileName, '.dfm'), mContext.FormText) then
    begin
      FProjectFiles.ReadText(ChangeFileExt(AFileName, '.fmx'), mContext.FormText);
    end;
    Result := TRuleEngine.Run(FRules, ASettings, mContext);
  finally
    mTree.Free;
  end;
end;

end.
