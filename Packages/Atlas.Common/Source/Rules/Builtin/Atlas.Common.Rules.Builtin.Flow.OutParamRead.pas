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
  OutParamReadRuleId = 'out-param-read';

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
  Result := MatchText(ATypeName, ManagedTypes) or MatchText(ATypeName, ['IInterface', 'IUnknown', 'TBytes']) or
    StartsText('TArray<', ATypeName) or StartsText('array of', ATypeName);
  // Interfaces: I gefolgt von einem Großbuchstaben.
  Result := Result or ((Length(ATypeName) > 1) and (ATypeName[1] = 'I') and CharInSet(ATypeName[2], ['A'..'Z']));
end;

/// <summary>Übergibt der Aufruf ACall einen Teil von AName (AName.Feld, AName[I])?</summary>
function PassesPartArgument(ACall: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or ((ACall[Index].Kind <> TSyntaxKind.Identifier) and SameText(RootName(ACall[Index]), AName));
  end;
end;

/// <summary>Wird ein Teil von AName (AName.Feld, AName[I]) als Argument übergeben? Ein out-Argument setzt ihn
/// dann, ohne dass der Graph es sieht.</summary>
function PassesPart(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(AVisited) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (AVisited.Kind = TSyntaxKind.Call) and PassesPartArgument(AVisited, Name) then
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
  Index: Integer;
  Token: TPascalToken;
begin
  Result := False;
  for Index := FContext.Tree.FirstTokenFrom(AParam.StartOffset) to High(FContext.Tree.Tokens) do
  begin
    Token := FContext.Tree.Tokens[Index];
    if Result or (Token.Offset >= AParam.EndOffset) then
    begin
      Break;
    end;
    if (Token.Offset >= AParam.StartOffset) and SameText(Token.Text, 'out') then
    begin
      AToken := Token;
      Result := True;
    end;
  end;
end;

/// <summary>Das Token "out" vor dem Parameter mit den Namen FNames in AParams.</summary>
function TOutParamCheck.OutToken(AParams: TSyntaxNode; out AToken: TPascalToken): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to AParams.ChildCount - 1 do
  begin
    if not Result and IsOutParam(AParams[Index], FNames) then
    begin
      Result := ParamOutToken(AParams[Index], AToken);
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
  Edits: TArray<TRuleEdit>;
begin
  Edits := nil;
  // Iterativ (Bericht M1).
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
          Edits := Edits + [OutEdit(Found)];
        end;
      end;
    end);
  Result := Edits;
end;

/// <summary>out -&gt; var in der Implementierung und in jeder Deklaration mit gleicher Parameterliste.</summary>
function TOutParamCheck.Fix: TArray<TRuleFix>;
var
  Edits: TArray<TRuleEdit>;
  Token: TPascalToken;
  Short: string;
begin
  Result := nil;
  Short := ShortName(FRoutine.Name);
  // Deklarationen stehen vor der Implementierung; die Änderungen bleiben nach Stelle sortiert.
  Edits := DeclarationEdits(Short, DeclaredClassName(Copy(FRoutine.Name, 1, Length(FRoutine.Name) -
    Length(Short) - 1)), Collapsed(FParams));
  if OutToken(FParams, Token) then
  begin
    Edits := Edits + [OutEdit(Token)];
  end;
  if Edits <> nil then
  begin
    Result := [TRuleFix.Create(cTexts[TFlowOutParamReadText.OutToVar].Text, Edits)];
  end;
end;

/// <summary>Liest ANode den Parameter auf einem erreichbaren Weg, auf dem nur der Eintritt ihn gesetzt hat?
/// </summary>
function TOutParamCheck.ReadsUndefined(ANode: TSyntaxNode): Boolean;
var
  Flow: TFlowNode;
begin
  Result := IsName(ANode, FName) and not IsAssignTarget(ANode);
  if Result then
  begin
    Flow := FlowNodeOf(ANode);
    Result := (Flow <> nil) and (FGraph.IsReachable(Flow) = TFlowAnswer.Yes) and
      FGraph.ReachingDefinitions(Flow, FName).FromEntry;
  end;
end;

procedure TOutParamCheck.ReportRead(ANode: TSyntaxNode);
var
  Detail: string;
begin
  if IsManagedParamType(FTypeName) then
  begin
    Detail := cTexts[TFlowOutParamReadText.AlwaysEmpty].Fmt([FTypeName]);
  end
  else
  begin
    Detail := cTexts[TFlowOutParamReadText.Undefined].Text;
  end;
  FReport.Add(NodeRange(ANode), cTexts[TFlowOutParamReadText.ReadBeforeSet].Fmt(
    [FName, Detail]), TRuleConfidence.High, Fix);
end;

/// <summary>Meldet den ersten Lesezugriff auf FName in ABlock, der vor dem Setzen liegt.</summary>
procedure TOutParamCheck.CheckName(ABlock: TSyntaxNode);
var
  Read: TSyntaxNode;
begin
  // Iterativ (Bericht M1).
  Read := ABlock.Search(
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
  if Read <> nil then
  begin
    ReportRead(Read);
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
  Name: string;
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
  for Name in AParam.Name.Split([',']) do
  begin
    FName := Name.Trim;
    if not HasOpaqueUse(ABlock, FName) and not PassesPart(ABlock, FName) and GraphComplete then
    begin
      CheckName(ABlock);
    end;
  end;
end;

procedure TOutParamCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  Block: TSyntaxNode;
  Index: Integer;
begin
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  FHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (Block = nil) or (FHeader = nil) then
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
  for Index := 0 to FParams.ChildCount - 1 do
  begin
    CheckParam(FParams[Index], Block);
  end;
end;

procedure TOutParamCheck.Run;
var
  Routine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  FCache := TRuleDerived.Open(FContext);
  for Routine in TRuleDerived.Routines(FCache, FContext) do
  begin
    CheckRoutine(Routine);
  end;
end;

{ TOutParamReadRule }

function TOutParamReadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OutParamReadRuleId, TRuleSeverity.Warning,
    cTexts[TFlowOutParamReadText.Title].Text);
end;

procedure TOutParamReadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TOutParamCheck;
begin
  Check := TOutParamCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.OutParamRead', cTexts);

end.
