unit Atlas.Common.Rules.Builtin.Exceptions;

// Exception-Regeln (#277, abgetrennt aus #57):
//   generic-exception-raised    raise Exception.Create(…) statt einer eigenen Klasse
//   catch-all-without-raise     on E: Exception do ohne raise; nur für Bibliothekscode,
//                               deshalb Standard aus und über Profile/Pfadregeln einzuschalten (#146)
//   exception-freed             Exception-Objekt nach raise bzw. im Handler zusätzlich freigegeben
// Der leere except-Block bleibt bei empty-except (#56).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TGenericExceptionRaisedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCatchAllWithoutRaiseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Exception-Regeln.</summary>
procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TTokens = TArray<TPascalToken>;

  /// <summary>Exception-Handler "on [Name:] Typ do Anweisung".</summary>
  THandler = record
    OnToken: Integer;
    DoToken: Integer;
    /// <summary>Name der Handler-Variablen; '' bei "on Typ do".</summary>
    Name: string;
    TypeName: string;
    /// <summary>Erstes und letztes Token der Anweisung hinter do.</summary>
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('asm');
end;

/// <summary>Letztes Token der Anweisung ab AFirst: bis zum passenden end bzw. vor ; oder end.</summary>
function StatementEnd(const ATokens: TTokens; AFirst: Integer): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  Index := AFirst;
  Result := AFirst;
  while Index <= High(ATokens) do
  begin
    if OpensBlock(ATokens[Index]) then
      Inc(Depth)
    else if ATokens[Index].IsKeyword('end') then
    begin
      if Depth = 0 then
        Exit;
      Dec(Depth);
      if Depth = 0 then
        Exit(Index);
    end
    else if (Depth = 0) and (ATokens[Index].IsSymbol(';') or ATokens[Index].IsKeyword('else')) then
      Exit;
    if not IsTrivia(ATokens[Index]) then
      Result := Index;
    Inc(Index);
  end;
end;

function Handlers(const ATokens: TTokens): TArray<THandler>;
var
  Index, Next, Colon: Integer;
  Handler: THandler;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    // "on" ist kein reserviertes Wort; im except-Teil folgt Name : Typ do oder Typ do.
    if not ((ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, 'on')) then
      Continue;
    Handler := Default(THandler);
    Handler.OnToken := Index;
    Next := NextCode(ATokens, Index + 1);
    Colon := NextCode(ATokens, Next + 1);
    if Colon > High(ATokens) then
      Continue;
    if ATokens[Colon].IsSymbol(':') then
    begin
      Handler.Name := ATokens[Next].Text;
      Next := NextCode(ATokens, Colon + 1);
    end;
    if (Next > High(ATokens)) or (ATokens[Next].Kind <> TPascalTokenKind.Identifier) then
      Continue;
    Handler.TypeName := ATokens[Next].Text;
    // Qualifizierter Typ: System.SysUtils.Exception.
    Handler.DoToken := NextCode(ATokens, Next + 1);
    while (Handler.DoToken < High(ATokens)) and ATokens[Handler.DoToken].IsSymbol('.') do
    begin
      Handler.TypeName := ATokens[NextCode(ATokens, Handler.DoToken + 1)].Text;
      Handler.DoToken := NextCode(ATokens, NextCode(ATokens, Handler.DoToken + 1) + 1);
    end;
    if (Handler.DoToken > High(ATokens)) or not ATokens[Handler.DoToken].IsKeyword('do') then
      Continue;
    Handler.First := NextCode(ATokens, Handler.DoToken + 1);
    if Handler.First > High(ATokens) then
      Continue;
    Handler.Last := StatementEnd(ATokens, Handler.First);
    Result := Result + [Handler];
  end;
end;

/// <summary>Gibt Token AIndex den Namen AName frei: AName.Free, AName.Destroy, FreeAndNil(AName)?</summary>
function IsFreeOf(const ATokens: TTokens; AIndex: Integer; const AName: string): Boolean;
var
  Dot, Method, Open, Arg: Integer;
begin
  Result := False;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
    Exit;
  if SameText(ATokens[AIndex].Text, AName) then
  begin
    Dot := NextCode(ATokens, AIndex + 1);
    Method := NextCode(ATokens, Dot + 1);
    Result := (Method <= High(ATokens)) and ATokens[Dot].IsSymbol('.') and
      MatchText(ATokens[Method].Text, ['Free', 'Destroy', 'DisposeOf']) and
      ((AIndex = 0) or not ATokens[PreviousCode(ATokens, AIndex)].IsSymbol('.'));
  end
  else if SameText(ATokens[AIndex].Text, 'FreeAndNil') then
  begin
    Open := NextCode(ATokens, AIndex + 1);
    Arg := NextCode(ATokens, Open + 1);
    Result := (Arg < High(ATokens)) and ATokens[Open].IsSymbol('(') and SameText(ATokens[Arg].Text, AName) and
      ATokens[NextCode(ATokens, Arg + 1)].IsSymbol(')');
  end;
end;

{ TGenericExceptionRaisedRule }

function TGenericExceptionRaisedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('generic-exception-raised', TRuleSeverity.Hint,
    'raise Exception statt einer eigenen Exception-Klasse');
end;

procedure TGenericExceptionRaisedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Name, Dot, Ctor: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not Tokens[Index].IsKeyword('raise') then
      Continue;
    Name := NextCode(Tokens, Index + 1);
    // raise SysUtils.Exception.Create bzw. System.SysUtils.Exception.Create
    while (Name + 2 <= High(Tokens)) and MatchText(Tokens[Name].Text, ['System', 'SysUtils']) and
      Tokens[NextCode(Tokens, Name + 1)].IsSymbol('.') do
      Name := NextCode(Tokens, NextCode(Tokens, Name + 1) + 1);
    Dot := NextCode(Tokens, Name + 1);
    Ctor := NextCode(Tokens, Dot + 1);
    if (Ctor > High(Tokens)) or not SameText(Tokens[Name].Text, 'Exception') or not Tokens[Dot].IsSymbol('.') or
      not StartsText('Create', Tokens[Ctor].Text) then
      Continue;
    AReport.Add(RangeOf(Tokens, Index, Ctor), 'raise Exception lässt sich nicht gezielt abfangen; eine eigene ' +
      'Klasse (z. B. EKundeNichtGefunden = class(Exception)) oder eine passende der RTL verwenden',
      TRuleConfidence.High);
  end;
end;

{ TCatchAllWithoutRaiseRule }

function TCatchAllWithoutRaiseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('catch-all-without-raise', TRuleSeverity.Warning,
    'on E: Exception do ohne raise', True);
end;

procedure TCatchAllWithoutRaiseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Handler: THandler;
  Index: Integer;
  Raises: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Handler in Handlers(Tokens) do
  begin
    if not MatchText(Handler.TypeName, ['Exception', 'TObject']) then
      Continue;
    Raises := False;
    for Index := Handler.First to Handler.Last do
      if Tokens[Index].IsKeyword('raise') then
        Raises := True;
    if not Raises then
      AReport.Add(RangeOf(Tokens, Handler.OnToken, Handler.DoToken), 'Bibliothekscode fängt jede Exception ab, ' +
        'ohne sie weiterzuwerfen; der Aufrufer erfährt nichts vom Fehler. Gezielt abfangen oder mit raise ' +
        'weiterwerfen', TRuleConfidence.Medium);
  end;
end;

{ TExceptionFreedRule }

function TExceptionFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-freed', TRuleSeverity.Error,
    'Exception-Objekt nach raise zusätzlich freigegeben');
end;

/// <summary>Erstes und letztes Token der Routine, in der Token AIndex liegt; False ohne.</summary>
function RoutineSpan(ATree: TSyntaxTree; const ATokens: TTokens; AIndex: Integer;
  out AFirst, ALast: Integer): Boolean;
var
  Best: TSyntaxNode;

  procedure Search(ANode: TSyntaxNode);
  var
    Child: Integer;
  begin
    for Child := 0 to ANode.ChildCount - 1 do
    begin
      if (ANode[Child].Kind = TSyntaxKind.RoutineDecl) and (ANode[Child].StartOffset <= ATokens[AIndex].Offset) and
        (ANode[Child].EndOffset > ATokens[AIndex].Offset) then
        Best := ANode[Child];
      Search(ANode[Child]);
    end;
  end;

var
  Index: Integer;
begin
  Best := nil;
  if ATree.Root <> nil then
    Search(ATree.Root);
  Result := Best <> nil;
  if not Result then
    Exit;
  AFirst := AIndex;
  ALast := AIndex;
  for Index := 0 to High(ATokens) do
    if (ATokens[Index].Offset >= Best.StartOffset) and (ATokens[Index].Offset < Best.EndOffset) then
    begin
      if Index < AFirst then
        AFirst := Index;
      if Index > ALast then
        ALast := Index;
    end;
end;

procedure TExceptionFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Handler: THandler;
  Index, Inner, Name, Stop, First, Last: Integer;
  Done: TArray<Integer>;

  function Reported(AToken: Integer): Boolean;
  var
    Item: Integer;
  begin
    for Item in Done do
      if Item = AToken then
        Exit(True);
    Result := False;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Done := nil;
  // Im Handler: on E: Exception do … E.Free; die RTL gibt E nach dem Handler selbst frei.
  for Handler in Handlers(Tokens) do
    if Handler.Name <> '' then
      for Index := Handler.First to Handler.Last do
        if IsFreeOf(Tokens, Index, Handler.Name) then
        begin
          Done := Done + [Index];
          AReport.Add(RangeOf(Tokens, Index, Index), Format('%s gehört nach dem Handler der RTL und wird dort ' +
            'freigegeben; eigenes Freigeben führt zur doppelten Freigabe', [Handler.Name]), TRuleConfidence.High);
        end;
  // raise X; … X.Free in derselben Routine: Nach raise gehört das Objekt der RTL.
  for Index := 0 to High(Tokens) do
  begin
    if not Tokens[Index].IsKeyword('raise') then
      Continue;
    Name := NextCode(Tokens, Index + 1);
    Stop := NextCode(Tokens, Name + 1);
    if (Stop > High(Tokens)) or (Tokens[Name].Kind <> TPascalTokenKind.Identifier) or
      not (Tokens[Stop].IsSymbol(';') or Tokens[Stop].IsKeyword('end')) then
      Continue;
    if not RoutineSpan(AContext.Tree, Tokens, Index, First, Last) then
      Continue;
    for Inner := First to Last do
      if IsFreeOf(Tokens, Inner, Tokens[Name].Text) and not Reported(Inner) then
      begin
        Done := Done + [Inner];
        AReport.Add(RangeOf(Tokens, Inner, Inner), Format('%s wird mit raise ausgelöst und gehört dann der ' +
          'RTL; zusätzliches Freigeben führt zur doppelten Freigabe', [Tokens[Name].Text]), TRuleConfidence.High);
        Break;
      end;
  end;
end;

procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TGenericExceptionRaisedRule.Create);
  ARegistry.Register(TCatchAllWithoutRaiseRule.Create);
  ARegistry.Register(TExceptionFreedRule.Create);
end;

end.
