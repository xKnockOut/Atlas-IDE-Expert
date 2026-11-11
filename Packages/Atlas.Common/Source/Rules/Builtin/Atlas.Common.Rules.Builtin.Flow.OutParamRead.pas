unit Atlas.Common.Rules.Builtin.Flow.OutParamRead;

// Regel out-param-read aus Atlas.Common.Rules.Builtin.Flow (#924): Ein out-Parameter wird gelesen, bevor die
// Routine ihn setzt; bei verwalteten Typen hat ihn der Aufrufer schon geleert. Korrektur: out -&gt; var in der
// Implementierung und in jeder Deklaration mit gleicher Parameterliste.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TOutParamReadRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cOutParamReadRuleId = 'out-param-read';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowOutParamReadText = (OutToVar, AlwaysEmpty, Undefined, ReadBeforeSet, Title);

const
  cTexts: array[TFlowOutParamReadText] of TAtlasText = (
    (De: 'out durch var ersetzen'; En: 'Replace out with var'),
    (De: 'bei %s ist er hier immer leer.'; En: 'with %s it is always empty here.'),
    (De: 'sein Wert ist hier undefiniert.'; En: 'its value is undefined here.'),
    (De: 'out-Parameter %s wird gelesen, bevor er gesetzt ist; %s';
     En: 'out parameter %s is read before it is set; %s'),
    (De: 'out-Parameter gelesen, bevor er gesetzt ist'; En: 'out parameter read before it is set'));

{$SCOPEDENUMS OFF}

/// <summary>Verwaltete Typen leert der Aufrufer vor dem Aufruf mit out.</summary>
function IsManagedParamType(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, cManagedTypes) or MatchText(ATypeName, ['IInterface', 'IUnknown', 'TBytes']) or
    StartsText('TArray<', ATypeName) or StartsText('array of', ATypeName);
  // Interfaces: I gefolgt von einem Großbuchstaben.
  Result := Result or ((Length(ATypeName) > 1) and (ATypeName[1] = 'I') and CharInSet(ATypeName[2], ['A'..'Z']));
end;

/// <summary>Übergibt der Aufruf ACall einen Teil von AName (AName.Feld, AName[I])?</summary>
function PassesPartArgument(ACall: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or ((ACall[mIndex].Kind <> TSyntaxKind.Identifier) and SameText(RootName(ACall[mIndex]), AName));
  end;
end;

/// <summary>Wird ein Teil von AName (AName.Feld, AName[I]) als Argument übergeben? Ein out-Argument setzt ihn
/// dann, ohne dass der Graph es sieht.</summary>
function PassesPart(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(AVisited) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (AVisited.Kind = TSyntaxKind.Call) and PassesPartArgument(AVisited, mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Klasse, in deren Deklaration ANode steht ('' außerhalb).</summary>
function OwnerOf(ANode: TSyntaxNode): string;
begin
  Result := '';
  while (ANode <> nil) and (Result = '') do
  begin
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      Result := ANode.Name;
    end;
    ANode := ANode.Parent;
  end;
end;

/// <summary>Ziel einer Zuweisung (AName := …)?</summary>
function IsAssignTarget(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
    (ANode.Parent.ChildCount > 0) and (ANode.Parent[0] = ANode);
end;

function IsOutParam(AParam: TSyntaxNode; const ANames: string): Boolean;
begin
  Result := (AParam.Kind = TSyntaxKind.Parameter) and SameText(AParam.Name, ANames) and
    (AParam.Modifier = TParameterModifier.OutParam);
end;

type
  /// <summary>Prüfung einer Unit für out-param-read; hält die Routine, ihren Graphen und den geprüften Parameter.
  /// </summary>
  TOutParamCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FRoutine: TSyntaxNode;
    FHeader: TSyntaxNode;
    FParams: TSyntaxNode;
    FGraph: TControlFlowGraph;
    FNames: string;
    FName: string;
    FTypeName: string;
    function FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
    function Collapsed(ANode: TSyntaxNode): string;
    function ParamOutToken(AParam: TSyntaxNode; out AToken: TPascalToken): Boolean;
    function OutToken(AParams: TSyntaxNode; out AToken: TPascalToken): Boolean;
    function OutEdit(const AToken: TPascalToken): TRuleEdit;
    function IsSameDeclaration(ANode: TSyntaxNode; const AShort, AClassPart: string): Boolean;
    function DeclarationEdits(const AShort, AClassPart, AKey: string): TArray<TRuleEdit>;
    function Fix: TArray<TRuleFix>;
    function ReadsUndefined(ANode: TSyntaxNode): Boolean;
    procedure ReportRead(ANode: TSyntaxNode);
    procedure CheckName(ABlock: TSyntaxNode);
    function GraphComplete: Boolean;
    procedure CheckParam(AParam, ABlock: TSyntaxNode);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TOutParamCheck }

constructor TOutParamCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TOutParamCheck.FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
begin
  Result := nil;
  while (ANode <> nil) and (Result = nil) do
  begin
    Result := FGraph.NodeOf(ANode);
    ANode := ANode.Parent;
  end;
end;

/// <summary>Quelltext von ANode ohne Leerzeichen und Zeilenumbrüche, klein geschrieben.</summary>
function TOutParamCheck.Collapsed(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode <> nil then
  begin
    Result := SourceText(FContext.Text, ANode).Replace(' ', '').Replace(#13, '').Replace(#10, '');
    Result := LowerCase(Result);
  end;
end;

/// <summary>Das Token "out" im Parameter AParam.</summary>
function TOutParamCheck.ParamOutToken(AParam: TSyntaxNode; out AToken: TPascalToken): Boolean;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  Result := False;
  for mIndex := FContext.Tree.FirstTokenFrom(AParam.StartOffset) to High(FContext.Tree.Tokens) do
  begin
    mToken := FContext.Tree.Tokens[mIndex];
    if Result or (mToken.Offset >= AParam.EndOffset) then
    begin
      Break;
    end;
    if (mToken.Offset >= AParam.StartOffset) and SameText(mToken.Text, 'out') then
    begin
      AToken := mToken;
      Result := True;
    end;
  end;
end;

/// <summary>Das Token "out" vor dem Parameter mit den Namen FNames in AParams.</summary>
function TOutParamCheck.OutToken(AParams: TSyntaxNode; out AToken: TPascalToken): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    if not Result and IsOutParam(AParams[mIndex], FNames) then
    begin
      Result := ParamOutToken(AParams[mIndex], AToken);
    end;
  end;
end;

function TOutParamCheck.OutEdit(const AToken: TPascalToken): TRuleEdit;
begin
  Result := TRuleEdit.Create(TTextRange.Create(AToken.StartPos, AToken.EndPos), 'var');
end;

/// <summary>Deklaration derselben Routine (gleicher Name, gleiche Klasse), nicht der Kopf der Implementierung.
/// </summary>
function TOutParamCheck.IsSameDeclaration(ANode: TSyntaxNode; const AShort, AClassPart: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode <> FHeader) and
    SameText(ShortName(ANode.Name), AShort) and SameText(OwnerOf(ANode), AClassPart);
end;

/// <summary>out -&gt; var in jeder Deklaration mit gleicher Parameterliste AKey; in Textreihenfolge.</summary>
function TOutParamCheck.DeclarationEdits(const AShort, AClassPart, AKey: string): TArray<TRuleEdit>;
var
  mEdits: TArray<TRuleEdit>;
begin
  mEdits := nil;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  FContext.Tree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Other: TSyntaxNode;
      Found: TPascalToken;
    begin
      Result := TSyntaxSearchStep.Descend;
      // Rümpfe anderer Routinen enthalten keine Deklarationen dieser Routine.
      if ANode.Kind = TSyntaxKind.Block then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if IsSameDeclaration(ANode, AShort, AClassPart) then
      begin
        Other := ANode.FindChild(TSyntaxKind.Parameters);
        if (Other <> nil) and (Collapsed(Other) = AKey) and OutToken(Other, Found) then
        begin
          mEdits := mEdits + [OutEdit(Found)];
        end;
      end;
    end);
  Result := mEdits;
end;

/// <summary>out -&gt; var in der Implementierung und in jeder Deklaration mit gleicher Parameterliste.</summary>
function TOutParamCheck.Fix: TArray<TRuleFix>;
var
  mEdits: TArray<TRuleEdit>;
  mToken: TPascalToken;
  mShort: string;
begin
  Result := nil;
  mShort := ShortName(FRoutine.Name);
  // Deklarationen stehen vor der Implementierung; die Änderungen bleiben nach Stelle sortiert.
  mEdits := DeclarationEdits(mShort, DeclaredClassName(Copy(FRoutine.Name, 1, Length(FRoutine.Name) -
    Length(mShort) - 1)), Collapsed(FParams));
  if OutToken(FParams, mToken) then
  begin
    mEdits := mEdits + [OutEdit(mToken)];
  end;
  if mEdits <> nil then
  begin
    Result := [TRuleFix.Create(cTexts[TFlowOutParamReadText.OutToVar].Text, mEdits)];
  end;
end;

/// <summary>Liest ANode den Parameter auf einem erreichbaren Weg, auf dem nur der Eintritt ihn gesetzt hat?
/// </summary>
function TOutParamCheck.ReadsUndefined(ANode: TSyntaxNode): Boolean;
var
  mFlow: TFlowNode;
begin
  Result := IsName(ANode, FName) and not IsAssignTarget(ANode);
  if Result then
  begin
    mFlow := FlowNodeOf(ANode);
    Result := (mFlow <> nil) and (FGraph.IsReachable(mFlow) = TFlowAnswer.Yes) and
      FGraph.ReachingDefinitions(mFlow, FName).FromEntry;
  end;
end;

procedure TOutParamCheck.ReportRead(ANode: TSyntaxNode);
var
  mDetail: string;
begin
  if IsManagedParamType(FTypeName) then
  begin
    mDetail := cTexts[TFlowOutParamReadText.AlwaysEmpty].Fmt([FTypeName]);
  end
  else
  begin
    mDetail := cTexts[TFlowOutParamReadText.Undefined].Text;
  end;
  FReport.Add(NodeRange(ANode), cTexts[TFlowOutParamReadText.ReadBeforeSet].Fmt(
    [FName, mDetail]), TRuleConfidence.High, Fix);
end;

/// <summary>Meldet den ersten Lesezugriff auf FName in ABlock, der vor dem Setzen liegt.</summary>
procedure TOutParamCheck.CheckName(ABlock: TSyntaxNode);
var
  mRead: TSyntaxNode;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mRead := ABlock.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ReadsUndefined(ANode) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  if mRead <> nil then
  begin
    ReportRead(mRead);
  end;
end;

/// <summary>Legt den Graphen beim ersten Bedarf an; False, wenn er unvollständig ist.</summary>
function TOutParamCheck.GraphComplete: Boolean;
begin
  if FGraph = nil then
  begin
    FGraph := TRuleDerived.Graph(FCache, FContext, FRoutine);
  end;
  Result := FGraph.Complete;
end;

procedure TOutParamCheck.CheckParam(AParam, ABlock: TSyntaxNode);
var
  mName: string;
begin
  if (AParam.Kind <> TSyntaxKind.Parameter) or (AParam.Modifier <> TParameterModifier.OutParam) then
  begin
    Exit;
  end;
  FTypeName := '';
  if AParam.FindChild(TSyntaxKind.TypeReference) <> nil then
  begin
    FTypeName := AParam.FindChild(TSyntaxKind.TypeReference).Name;
  end;
  FNames := AParam.Name;
  for mName in AParam.Name.Split([',']) do
  begin
    FName := mName.Trim;
    if not HasOpaqueUse(ABlock, FName) and not PassesPart(ABlock, FName) and GraphComplete then
    begin
      CheckName(ABlock);
    end;
  end;
end;

procedure TOutParamCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  mBlock: TSyntaxNode;
  mIndex: Integer;
begin
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  FHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (mBlock = nil) or (FHeader = nil) then
  begin
    Exit;
  end;
  FParams := FHeader.FindChild(TSyntaxKind.Parameters);
  if FParams = nil then
  begin
    Exit;
  end;
  FRoutine := ARoutine;
  FGraph := nil;
  for mIndex := 0 to FParams.ChildCount - 1 do
  begin
    CheckParam(FParams[mIndex], mBlock);
  end;
end;

procedure TOutParamCheck.Run;
var
  mRoutine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  FCache := TRuleDerived.Open(FContext);
  for mRoutine in TRuleDerived.Routines(FCache, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ TOutParamReadRule }

function TOutParamReadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cOutParamReadRuleId, TRuleSeverity.Warning,
    cTexts[TFlowOutParamReadText.Title].Text);
end;

procedure TOutParamReadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TOutParamCheck;
begin
  mCheck := TOutParamCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.OutParamRead', cTexts);

end.
