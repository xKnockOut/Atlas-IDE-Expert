unit Atlas.Common.Rules.Builtin.Exceptions;

// Exception-Regeln (#277, abgetrennt aus #57):
//   generic-exception-raised    raise Exception.Create(…) statt einer eigenen Klasse
//   catch-all-without-raise     on E: Exception do ohne raise; nur für Bibliothekscode,
//                               deshalb Standard aus und über Profile/Pfadregeln einzuschalten (#146)
//   exception-freed             Exception-Objekt nach raise bzw. im Handler zusätzlich freigegeben
//   exception-in-destructor     raise in einem Destruktor, das kein except im Destruktor abfängt (#927)
//   except-handler-order        on-Handler, der nie erreicht wird, weil ein früherer die Klasse schon fängt (#957)
//   reraise-exception-object    raise E im Handler statt raise; (#958)
//   inherited-constructor-after-try  try im Konstruktor vor dem geerbten Konstruktor, Self noch nicht
//                               initialisiert (wie H2505, #1027); ergänzt missing-inherited. Zweige von
//                               {$IFDEF}, die sich ausschließen, zählen nicht gegeneinander
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

  TExceptionInDestructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptHandlerOrderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorfahr einer bekannten RTL-, VCL- oder FireDAC-Exception; leer, wenn unbekannt.</summary>
    class function KnownParent(const AName: string): string; static;
  end;

  TReraiseExceptionObjectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedConstructorAfterTryRule = class(TInterfacedObject, IRule)
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
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance;

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

{ TExceptionInDestructorRule }

function TExceptionInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-in-destructor', TRuleSeverity.Warning, 'raise im Destruktor');
end;

procedure TExceptionInDestructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  RoutineName: string;
  // Offset des ersten inherited im Destruktor; MaxInt ohne.
  InheritedOffset: Integer;

  function RoutineText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function IsDestructor(ARoutine: TSyntaxNode): Boolean;
  var
    Head: string;
  begin
    Head := RoutineText(ARoutine);
    if StartsText('class', Head) then
      Head := TrimLeft(Copy(Head, Length('class') + 1, MaxInt));
    Result := StartsText('destructor', Head) and ((Length(Head) = Length('destructor')) or
      CharInSet(Head[Length('destructor') + 1], [' ', #9, #10, #13]));
  end;

  // Erstes inherited im Destruktor, ohne eingebettete Routinen und anonyme Methoden.
  procedure FindInherited(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
      Exit;
    if (ANode.Kind = TSyntaxKind.InheritedExpr) and (ANode.StartOffset < InheritedOffset) then
      InheritedOffset := ANode.StartOffset;
    for Index := 0 to ANode.ChildCount - 1 do
      FindInherited(ANode[Index]);
  end;

  // AActive: eine Ausnahme an dieser Stelle verlässt den Destruktor.
  procedure Visit(ANode: TSyntaxNode; AActive: Boolean);
  var
    Index: Integer;
    Child: TSyntaxNode;
    HasExcept: Boolean;
    Message: string;
  begin
    if ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
      Exit;
    if ANode.Kind = TSyntaxKind.RaiseStatement then
    begin
      if not AActive then
        Exit;
      if ANode.StartOffset < InheritedOffset then
        Message := Format('raise im Destruktor: inherited %s läuft nicht mehr, Felder bleiben liegen.',
          [RoutineName])
      else
        Message := Format('raise im Destruktor: die Ausnahme verlässt %s, der Aufrufer erwartet eine ' +
          'Freigabe ohne Ausnahme.', [RoutineName]);
      AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
        ANode.StartPos.Character + Length('raise'))), Message, TRuleConfidence.High);
      Exit;
    end;
    if ANode.Kind = TSyntaxKind.TryStatement then
    begin
      HasExcept := False;
      for Index := 0 to ANode.ChildCount - 1 do
        if ANode[Index].Kind = TSyntaxKind.ExceptBlock then
          HasExcept := True;
      for Index := 0 to ANode.ChildCount - 1 do
      begin
        Child := ANode[Index];
        // Im try-Teil fängt ein eigenes except die Ausnahme ab; except- und finally-Teil nicht.
        if Child.Kind in [TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock] then
          Visit(Child, AActive)
        else
          Visit(Child, AActive and not HasExcept);
      end;
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], AActive);
  end;

  procedure Search(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.RoutineDecl) and IsDestructor(ANode) then
    begin
      RoutineName := ANode.Name;
      if LastDelimiter('.', RoutineName) > 0 then
        RoutineName := Copy(RoutineName, LastDelimiter('.', RoutineName) + 1, MaxInt);
      Body := ANode.FindChild(TSyntaxKind.Block);
      if Body <> nil then
      begin
        InheritedOffset := MaxInt;
        FindInherited(Body);
        Visit(Body, True);
      end;
    end;
    // Auch eingebettete Routinen und Klassen in Routinen.
    for Index := 0 to ANode.ChildCount - 1 do
      Search(ANode[Index]);
  end;

begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
    Search(AContext.Tree.Root);
end;

{ TExceptHandlerOrderRule }

const
  // Vorfahren bekannter RTL-, VCL- und FireDAC-Exceptions (Klasse=Vorfahr), wenn der Index sie nicht kennt.
  KnownExceptionParents: array[0..39] of string = (
    'EAbort=Exception', 'EConvertError=Exception', 'EInOutError=Exception', 'EOSError=Exception',
    'EInvalidCast=Exception', 'EInvalidPointer=EHeapException', 'EOutOfMemory=EHeapException',
    'EHeapException=Exception', 'EExternal=Exception', 'EAccessViolation=EExternal', 'EIntError=EExternal',
    'EDivByZero=EIntError', 'ERangeError=EIntError', 'EIntOverflow=EIntError', 'EMathError=EExternal',
    'EInvalidOp=EMathError', 'EZeroDivide=EMathError', 'EOverflow=EMathError', 'EUnderflow=EMathError',
    'EArgumentException=Exception', 'EArgumentOutOfRangeException=EArgumentException',
    'EArgumentNilException=EArgumentException', 'ENotImplemented=Exception', 'ENotSupportedException=Exception',
    'EListError=Exception', 'EStringListError=EListError', 'EStreamError=Exception',
    'EFileStreamError=EStreamError', 'EFOpenError=EFileStreamError', 'EFCreateError=EFileStreamError',
    'EFilerError=EStreamError', 'EReadError=EFilerError', 'EWriteError=EFilerError',
    'EVariantError=Exception', 'EDatabaseError=Exception', 'EFDException=EDatabaseError',
    'EFDDBEngineException=EFDException', 'EEncodingError=Exception', 'EJSONException=Exception',
    'EComponentError=Exception');

function TExceptHandlerOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('except-handler-order', TRuleSeverity.Warning,
    'Allgemeiner Exception-Handler vor speziellem');
end;

class function TExceptHandlerOrderRule.KnownParent(const AName: string): string;
var
  Entry: string;
begin
  for Entry in KnownExceptionParents do
    if SameText(Copy(Entry, 1, Pos('=', Entry) - 1), AName) then
      Exit(Copy(Entry, Pos('=', Entry) + 1, MaxInt));
  Result := '';
end;

procedure TExceptHandlerOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Lines: TArray<string>;
  LineBreak: string;

  function TypeOf(AHandler: TSyntaxNode): string;
  var
    Reference: TSyntaxNode;
  begin
    Result := '';
    Reference := AHandler.FindChild(TSyntaxKind.TypeReference);
    if Reference <> nil then
      Result := Copy(Reference.Name, LastDelimiter('.', Reference.Name) + 1, MaxInt);
  end;

  // Fängt ein Handler für AGeneral auch ASpecial? Über die Datei, den Index und die Tabelle bekannter Klassen.
  function Covers(const AGeneral, ASpecial: string): Boolean;
  var
    Current, Parent: string;
    Steps: Integer;
  begin
    if SameText(AGeneral, 'TObject') then
      Exit(True);
    // Alles, was als Exception ausgelöst wird, erbt in der Praxis von Exception.
    if SameText(AGeneral, 'Exception') and not SameText(ASpecial, 'TObject') then
      Exit(True);
    Current := ASpecial;
    for Steps := 1 to 16 do
    begin
      Parent := Ancestry.ParentOf(Current);
      if (Parent = '') or SameText(Parent, 'TObject') then
        Parent := KnownParent(Current);
      if Parent = '' then
        Exit(False);
      if SameText(Parent, AGeneral) then
        Exit(True);
      Current := Parent;
    end;
    Result := False;
  end;

  // Steht der Handler allein auf seinen Zeilen (davor Einrückung, danach höchstens ";")?
  function OwnLines(AHandler: TSyntaxNode): Boolean;
  var
    Rest: string;
  begin
    Rest := Trim(Copy(Lines[AHandler.EndPos.Line], AHandler.EndPos.Character + 1, MaxInt));
    Result := (Trim(Copy(Lines[AHandler.StartPos.Line], 1, AHandler.StartPos.Character)) = '') and
      ((Rest = '') or (Rest = ';')) and (AHandler.EndPos.Line < High(Lines));
  end;

  // Korrektur: den speziellen Handler vor den allgemeinen verschieben.
  function MoveFix(AGeneral, ASpecial: TSyntaxNode): TArray<TRuleFix>;
  var
    Line: Integer;
    Text: string;
  begin
    Result := nil;
    if not OwnLines(AGeneral) or not OwnLines(ASpecial) or (AGeneral.EndPos.Line >= ASpecial.StartPos.Line) then
      Exit;
    Text := '';
    for Line := ASpecial.StartPos.Line to ASpecial.EndPos.Line do
      Text := Text + Lines[Line] + LineBreak;
    // Der letzte Handler darf ohne Semikolon stehen; vor einem anderen braucht er eines.
    if Trim(Copy(Lines[ASpecial.EndPos.Line], ASpecial.EndPos.Character + 1, MaxInt)) = '' then
      Text := Copy(Text, 1, Length(Text) - Length(LineBreak)) + ';' + LineBreak;
    Result := [TRuleFix.Create(Format('on %s vor on %s verschieben', [TypeOf(ASpecial), TypeOf(AGeneral)]), [
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(AGeneral.StartPos.Line, 0),
        TTextPosition.Create(AGeneral.StartPos.Line, 0)), Text),
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ASpecial.StartPos.Line, 0),
        TTextPosition.Create(ASpecial.EndPos.Line + 1, 0)), '')])];
  end;

  procedure CheckBlock(ABlock: TSyntaxNode);
  var
    Handlers: TArray<TSyntaxNode>;
    Index, Earlier: Integer;
    General, Special: string;
    Range: TTextRange;
    Reference: TSyntaxNode;
  begin
    Handlers := nil;
    for Index := 0 to ABlock.ChildCount - 1 do
      if ABlock[Index].Kind = TSyntaxKind.ExceptionHandler then
        Handlers := Handlers + [ABlock[Index]];
    for Index := 1 to High(Handlers) do
    begin
      Special := TypeOf(Handlers[Index]);
      if Special = '' then
        Continue;
      for Earlier := 0 to Index - 1 do
      begin
        General := TypeOf(Handlers[Earlier]);
        if General = '' then
          Continue;
        Reference := Handlers[Index].FindChild(TSyntaxKind.TypeReference);
        Range := TTextRange.Create(Reference.StartPos, Reference.EndPos);
        if SameText(General, Special) then
        begin
          AReport.Add(Range, Format('Nie erreicht: %s wird schon in Zeile %d behandelt.',
            [Special, Handlers[Earlier].StartPos.Line + 1]));
          Break;
        end;
        if Covers(General, Special) then
        begin
          AReport.Add(Range, Format('Nie erreicht: %s ist ein Nachfahr von %s, das schon in Zeile %d behandelt wird.',
            [Special, General, Handlers[Earlier].StartPos.Line + 1]), MoveFix(Handlers[Earlier], Handlers[Index]));
          Break;
        end;
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.ExceptBlock then
      CheckBlock(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'except') then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

{ TReraiseExceptionObjectRule }

function TReraiseExceptionObjectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('reraise-exception-object', TRuleSeverity.Warning,
    'raise E statt raise im Handler');
end;

procedure TReraiseExceptionObjectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Handler: THandler;
  Index, Name, Stop: Integer;
  Done: TArray<Integer>;

  // Übernimmt der Handler das Objekt selbst (AcquireExceptionObject) oder weist er der Variablen neu zu?
  function OwnsObject(const AHandler: THandler): Boolean;
  var
    Position: Integer;
  begin
    for Position := AHandler.First to AHandler.Last do
      if SameText(Tokens[Position].Text, 'AcquireExceptionObject') or
        (SameText(Tokens[Position].Text, AHandler.Name) and
        Tokens[NextCode(Tokens, Position + 1)].IsSymbol(':=')) then
        Exit(True);
    Result := False;
  end;

  // Liegt das raise in einer anonymen Methode innerhalb des Handlers?
  function InAnonymousMethod(const AHandler: THandler; ARaise: Integer): Boolean;
  var
    Position: Integer;
  begin
    for Position := AHandler.First to ARaise do
      if Tokens[Position].IsKeyword('procedure') or Tokens[Position].IsKeyword('function') then
        Exit(True);
    Result := False;
  end;

  function Reported(AToken: Integer): Boolean;
  var
    Item: Integer;
  begin
    for Item in Done do
      if Item = AToken then
        Exit(True);
    Result := False;
  end;

var
  Fixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'raise') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Done := nil;
  for Handler in Handlers(Tokens) do
  begin
    if (Handler.Name = '') or OwnsObject(Handler) then
      Continue;
    for Index := Handler.First to Handler.Last do
    begin
      if not Tokens[Index].IsKeyword('raise') or Reported(Index) then
        Continue;
      Name := NextCode(Tokens, Index + 1);
      Stop := NextCode(Tokens, Name + 1);
      if (Stop > High(Tokens)) or not SameText(Tokens[Name].Text, Handler.Name) or
        InAnonymousMethod(Handler, Index) then
        Continue;
      // raise E; raise E end; raise E else; raise E at Adresse (ohne Korrektur).
      Fixes := nil;
      if Tokens[Stop].IsSymbol(';') or Tokens[Stop].IsKeyword('end') or Tokens[Stop].IsKeyword('else') then
        Fixes := [TRuleFix.Create(Format('raise %s; durch raise; ersetzen', [Handler.Name]),
          [TRuleEdit.Create(RangeOf(Tokens, Index, Name), 'raise')])]
      else if not SameText(Tokens[Stop].Text, 'at') then
        Continue;
      Done := Done + [Index];
      AReport.Add(RangeOf(Tokens, Index, Name), Format('raise %s löst das Objekt neu aus: Absprungstelle ' +
        '(ExceptAddr) und Aufrufliste zeigen danach auf diesen Handler statt auf den ursprünglichen Fehler; ' +
        'raise; wirft die Exception unverändert weiter.', [Handler.Name]), TRuleConfidence.High, Fixes);
    end;
  end;
end;

{ TInheritedConstructorAfterTryRule }

function TInheritedConstructorAfterTryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-constructor-after-try', TRuleSeverity.Hint,
    'Geerbter Konstruktor erst nach try');
end;

/// <summary>Erstes Token ab AOffset (die Tokens sind nach Offset sortiert).</summary>
function TokenAtOffset(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Upper, Middle: Integer;
begin
  Result := 0;
  Upper := Length(ATokens);
  while Result < Upper do
  begin
    Middle := (Result + Upper) div 2;
    if ATokens[Middle].Offset < AOffset then
      Result := Middle + 1
    else
      Upper := Middle;
  end;
end;

/// <summary>Knoten unter ARoot in Quelltextreihenfolge, ohne Rekursion (#1094). Mit ASkipRoutines ohne
/// eingebettete Routinen und anonyme Methoden.</summary>
function NodesBelow(ARoot: TSyntaxNode; ASkipRoutines: Boolean): TArray<TSyntaxNode>;
var
  Stack: TArray<TSyntaxNode>;
  Count, Index, Found: Integer;
  Node: TSyntaxNode;
begin
  SetLength(Result, 64);
  Found := 0;
  SetLength(Stack, 64);
  Stack[0] := ARoot;
  Count := 1;
  while Count > 0 do
  begin
    Dec(Count);
    Node := Stack[Count];
    if Found = Length(Result) then
      SetLength(Result, 2 * Found);
    Result[Found] := Node;
    Inc(Found);
    if Count + Node.ChildCount > Length(Stack) then
      SetLength(Stack, 2 * (Count + Node.ChildCount));
    for Index := Node.ChildCount - 1 downto 0 do
      if not ASkipRoutines or not (Node[Index].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Stack[Count] := Node[Index];
        Inc(Count);
      end;
  end;
  SetLength(Result, Found);
end;

procedure TInheritedConstructorAfterTryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'try vor dem Aufruf des geerbten Konstruktors; Self ist noch nicht initialisiert (wie H2505).';
var
  Tokens: TTokens;
  Paths, Lines: TArray<string>;
  LineBreak: string;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAtOffset(Tokens, ANode.StartOffset));
  end;

  function IsConstructor(ARoutine: TSyntaxNode): Boolean;
  var
    Head: string;
  begin
    // class constructor ruft kein inherited auf; dort gibt es kein Self.
    Head := TrimLeft(Copy(AContext.Text, ARoutine.StartOffset + 1, Length('constructor') + 1));
    Result := StartsText('constructor', Head) and (Length(Head) > Length('constructor')) and
      CharInSet(Head[Length('constructor') + 1], [' ', #9, #10, #13]);
  end;

  // inherited ohne Namen, mit dem eigenen Namen oder Create…: der geerbte Konstruktor.
  function IsConstructorCall(ANode: TSyntaxNode; const AOwn: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.InheritedExpr) and ((ANode.Name = '') or SameText(ANode.Name, AOwn) or
      StartsText('Create', ANode.Name));
  end;

  // Korrektur, wenn der Aufruf die erste Anweisung des try-Teils ist: vor try ziehen.
  function MoveBeforeTry(ATry, ACall: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    TryToken, Last, Semicolon: Integer;
    Text, Before: string;
    Removal: TTextRange;
  begin
    Result := nil;
    Statement := ACall;
    while (Statement <> nil) and (Statement.Parent <> ATry) do
      Statement := Statement.Parent;
    if (Statement = nil) or (ATry.ChildCount = 0) or (ATry[0] <> Statement) or
      (Statement.Kind <> TSyntaxKind.CallStatement) then
      Exit;
    TryToken := TokenAtOffset(Tokens, ATry.StartOffset);
    // Kommentare zwischen try und Aufruf gingen mit dem Verschieben verloren.
    if (TryToken + 1 > High(Tokens)) or (Tokens[TryToken + 1].Offset <> Statement.StartOffset) then
      Exit;
    Last := PreviousCode(Tokens, TokenAtOffset(Tokens, Statement.EndOffset));
    Semicolon := NextCode(Tokens, Last + 1);
    Removal := TTextRange.Create(Tokens[TryToken].EndPos, Tokens[Last].EndPos);
    if (Semicolon <= High(Tokens)) and Tokens[Semicolon].IsSymbol(';') then
      Removal.EndPos := Tokens[Semicolon].EndPos;
    Text := Copy(AContext.Text, Statement.StartOffset + 1, Statement.EndOffset - Statement.StartOffset);
    Before := Trim(Copy(Lines[Tokens[TryToken].StartPos.Line], 1, Tokens[TryToken].StartPos.Character));
    if Before = '' then
      Text := Text + ';' + LineBreak + TTextLines.IndentOf(Lines[Tokens[TryToken].StartPos.Line])
    else
      Text := Text + '; ';
    Result := [TRuleFix.Create(Format('%s vor try ziehen', [Trim(Copy(AContext.Text, ACall.StartOffset + 1,
      ACall.EndOffset - ACall.StartOffset))]), [TRuleEdit.Create(TTextRange.Create(Tokens[TryToken].StartPos,
      Tokens[TryToken].StartPos), Text), TRuleEdit.Create(Removal, '')], True)];
  end;

  procedure CheckConstructor(ARoutine: TSyntaxNode);
  var
    Body, Node, Call, After: TSyntaxNode;
    Own, TryPath: string;
    Calls, Trys, Reported: TArray<TSyntaxNode>;
    Earlier, Shadowed: Boolean;
  begin
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    if Body = nil then
      Exit;
    Own := ARoutine.Name;
    if LastDelimiter('.', Own) > 0 then
      Own := Copy(Own, LastDelimiter('.', Own) + 1, MaxInt);
    Calls := nil;
    Trys := nil;
    for Node in NodesBelow(Body, True) do
      if IsConstructorCall(Node, Own) then
        Calls := Calls + [Node]
      else if Node.Kind = TSyntaxKind.TryStatement then
        Trys := Trys + [Node];
    if (Calls = nil) or (Trys = nil) then
      Exit;
    Reported := nil;
    for Node in Trys do
    begin
      // Zweige von {$IFDEF}, die sich ausschließen, zählen nicht gegeneinander.
      TryPath := PathOf(Node);
      Earlier := False;
      After := nil;
      for Call in Calls do
      begin
        if TConditionalBranches.Exclusive(TryPath, PathOf(Call)) then
          Continue;
        if Call.StartOffset < Node.StartOffset then
          Earlier := True
        else if After = nil then
          After := Call;
      end;
      if Earlier or (After = nil) then
        Continue;
      // Gemeldet wird das erste try; ein späteres nur in einem anderen Zweig.
      Shadowed := False;
      for Call in Reported do
        if not TConditionalBranches.Exclusive(TryPath, PathOf(Call)) then
          Shadowed := True;
      if Shadowed then
        Continue;
      Reported := Reported + [Node];
      AReport.Add(TTextRange.Create(Node.StartPos, TTextPosition.Create(Node.StartPos.Line,
        Node.StartPos.Character + Length('try'))), Message, TRuleConfidence.High, MoveBeforeTry(Node, After));
    end;
  end;

var
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  for Node in NodesBelow(AContext.Tree.Root, False) do
    if (Node.Kind = TSyntaxKind.RoutineDecl) and IsConstructor(Node) then
      CheckConstructor(Node);
end;

procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TGenericExceptionRaisedRule.Create);
  ARegistry.Register(TCatchAllWithoutRaiseRule.Create);
  ARegistry.Register(TExceptionFreedRule.Create);
  ARegistry.Register(TExceptionInDestructorRule.Create);
  ARegistry.Register(TExceptHandlerOrderRule.Create);
  ARegistry.Register(TReraiseExceptionObjectRule.Create);
  ARegistry.Register(TInheritedConstructorAfterTryRule.Create);
end;

end.
