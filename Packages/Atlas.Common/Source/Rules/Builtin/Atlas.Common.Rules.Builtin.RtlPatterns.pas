unit Atlas.Common.Rules.Builtin.RtlPatterns;

// Regeln für fehleranfällige RTL-Muster, Stufe 1 aus #153 (syntaktisch, ohne Typen):
//   self-assignment           X := X
//   for-high-to-low           for I := High(A) to Low(A) bzw. Count - 1 to 0 ohne downto; konstante
//                             Grenzen, die nie laufen (10 to 1, wie H2135, #1023)
//   exception-not-raised      Exception erzeugt, aber nicht ausgelöst
//   assert-side-effect        Assert mit Seiteneffekt im Argument; fällt mit {$C-} weg
//   ifthen-side-effect        IfThen wertet beide Zweige aus: Nil-Zugriff oder Funktionsaufruf darin
//   random-without-randomize  Random ohne Randomize in der Unit (Standard aus, niedrige Konfidenz)

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TSelfAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForHighToLowRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionNotRaisedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAssertSideEffectRule = class(TInterfacedObject, IRule)
  public const
    DefaultMutatingMethods: array[0..5] of string = ('Add', 'Delete', 'Remove', 'Extract', 'Clear', 'Insert');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Option "mutatingMethods" aus den Regeloptionen; ohne Angabe die Vorgabe.</summary>
    class function MutatingMethods(const AOptions: string): TArray<string>; static;
  end;

  TIfThenSideEffectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRandomWithoutRandomizeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Regeln für RTL-Muster.</summary>
procedure RegisterRtlPatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TTokens = TArray<TPascalToken>;
  /// <summary>Token eines Arguments, erstes und letztes.</summary>
  TSpan = record
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Nächstes Code-Token ab AIndex; Length(ATokens) ohne.</summary>
function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Vorheriges Code-Token vor AIndex; -1 ohne.</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Beginnt hinter ATokens[AIndex] eine Anweisung?</summary>
function EndsStatement(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  if AIndex < 0 then
    Exit(False);
  Result := ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsKeyword('begin') or
    ATokens[AIndex].IsKeyword('then') or ATokens[AIndex].IsKeyword('else') or ATokens[AIndex].IsKeyword('do') or
    ATokens[AIndex].IsKeyword('try') or ATokens[AIndex].IsKeyword('finally') or
    ATokens[AIndex].IsKeyword('except') or ATokens[AIndex].IsKeyword('repeat');
end;

/// <summary>Endet vor ATokens[AIndex] eine Anweisung (;, end, else, until, except, finally)?</summary>
function IsStatementEnd(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  if AIndex > High(ATokens) then
    Exit(True);
  Result := ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsKeyword('end') or
    ATokens[AIndex].IsKeyword('else') or ATokens[AIndex].IsKeyword('until') or
    ATokens[AIndex].IsKeyword('except') or ATokens[AIndex].IsKeyword('finally');
end;

/// <summary>Index der zur öffnenden Klammer bei AOpen passenden schließenden; -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(ATokens) do
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
  Result := -1;
end;

/// <summary>Code der Token AFirst..ALast ohne Kommentare, Wörter klein, mit Leerzeichen getrennt.</summary>
function Normalized(const ATokens: TTokens; AFirst, ALast: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
    if not IsTrivia(ATokens[Index]) then
      Result := Result + ' ' + LowerCase(ATokens[Index].Text);
end;

/// <summary>Bezeichnerkette aus Bezeichnern, Punkten, Indizes und ^?</summary>
function IsDesignator(const ATokens: TTokens; AFirst, ALast: Integer): Boolean;
var
  Index, Depth: Integer;
begin
  if (AFirst > ALast) or (ATokens[AFirst].Kind <> TPascalTokenKind.Identifier) then
    Exit(False);
  Depth := 0;
  for Index := AFirst to ALast do
  begin
    if IsTrivia(ATokens[Index]) then
      Continue;
    if ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and not ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or
      ATokens[Index].IsSymbol('.') or ATokens[Index].IsSymbol('^')) then
      Exit(False);
  end;
  Result := Depth = 0;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Grenzen der Argumente zwischen AOpen und AClose (Klammern) auf oberster Ebene.</summary>
function Arguments(const ATokens: TTokens; AOpen, AClose: Integer): TArray<TSpan>;
var
  Index, Depth, Start: Integer;
  Span: TSpan;
begin
  Result := nil;
  Depth := 0;
  Start := AOpen + 1;
  for Index := AOpen + 1 to AClose do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if (ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']')) and (Index < AClose) then
      Dec(Depth)
    else if (Depth = 0) and (ATokens[Index].IsSymbol(',') or (Index = AClose)) then
    begin
      Span.First := Start;
      Span.Last := Index - 1;
      Result := Result + [Span];
      Start := Index + 1;
    end;
  end;
end;

{ TSelfAssignmentRule }

function TSelfAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('self-assignment', TRuleSeverity.Warning, 'Zuweisung an sich selbst');
end;

/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Trim(Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset));
end;

procedure TSelfAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Start, Stop, Before: Integer;
  Removal, Insert: TTextRange;
  Resolver: TNameResolver;
  Local, Member: TResolvedSymbol;
  Name: string;
  Fixes: TArray<TRuleFix>;
  Message: string;
begin
  if AContext.Tree = nil then
    Exit;
  Resolver := nil;
  try
    Tokens := AContext.Tree.Tokens;
    for Index := 0 to High(Tokens) do
    begin
      if not Tokens[Index].IsSymbol(':=') then
        Continue;
      // Linke Seite bis zum Anweisungsbeginn zurück.
      Start := PreviousCode(Tokens, Index);
      Before := PreviousCode(Tokens, Start);
      while (Before >= 0) and not EndsStatement(Tokens, Before) and not Tokens[Before].IsKeyword('var') and
        not Tokens[Before].IsSymbol(':') and not Tokens[Before].IsSymbol(':=') do
      begin
        Start := Before;
        Before := PreviousCode(Tokens, Start);
      end;
      if (Before < 0) or not EndsStatement(Tokens, Before) then
        Continue;
      Stop := NextCode(Tokens, Index + 1);
      while not IsStatementEnd(Tokens, Stop) do
        Stop := NextCode(Tokens, Stop + 1);
      if (Stop > High(Tokens)) or not IsDesignator(Tokens, Start, PreviousCode(Tokens, Index)) or
        (Normalized(Tokens, Start, Index - 1) <> Normalized(Tokens, Index + 1, Stop - 1)) then
        Continue;
      if Tokens[Stop].IsSymbol(';') then
        Removal := RangeOf(Tokens, Start, Stop)
      else
        Removal := RangeOf(Tokens, Start, PreviousCode(Tokens, Stop));
      Name := SourceText(AContext.Text, Tokens, Start, PreviousCode(Tokens, Index));
      Message := Format('%s wird sich selbst zugewiesen; gemeint ist vermutlich ein anderer Wert', [Name]);
      Fixes := [TRuleFix.Create('Anweisung entfernen', [TRuleEdit.Create(Removal, '')])];
      // Name := Name, wenn ein Parameter oder eine lokale Variable das gleichnamige Feld verdeckt:
      // gemeint ist fast immer Self.Name := Name.
      if (Start = PreviousCode(Tokens, Index)) and (Tokens[Start].Kind = TPascalTokenKind.Identifier) and
        (AContext.Index <> nil) then
      begin
        if Resolver = nil then
        begin
          Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
          Resolver.Namespaces := AContext.Namespaces;
        end;
        Local := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, [Name], Tokens[Start].Offset, False);
        if Local.Kind = TResolvedKind.Local then
        begin
          Member := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, ['Self', Name], Tokens[Start].Offset,
            False);
          if (Member.Kind = TResolvedKind.Symbol) and
            (Member.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
          begin
            Message := Format('%s wird sich selbst zugewiesen: %s verdeckt %s; gemeint ist vermutlich Self.%s := %s',
              [Name, TNameResolver.ShadowText(Local), TNameResolver.ShadowText(Member), Name, Name]);
            Insert := TTextRange.Create(Tokens[Start].StartPos, Tokens[Start].StartPos);
            Fixes := [TRuleFix.Create('Self. ergänzen', [TRuleEdit.Create(Insert, 'Self.')])] + Fixes;
          end;
        end;
      end;
      AReport.Add(RangeOf(Tokens, Start, PreviousCode(Tokens, Stop)), Message, TRuleConfidence.High, Fixes);
    end;
  finally
    Resolver.Free;
  end;
end;

{ TForHighToLowRule }

function TForHighToLowRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('for-high-to-low', TRuleSeverity.Warning,
    'for-Schleife zählt mit to vom oberen zum unteren Wert');
end;

/// <summary>Beginnt der Ausdruck bei AIndex mit dem Aufruf AName( und endet er vor AStop?</summary>
function IsCallUntil(const ATokens: TTokens; AIndex, AStop: Integer; const AName: string): Boolean;
var
  Open: Integer;
begin
  Result := False;
  if (AIndex > High(ATokens)) or not SameText(ATokens[AIndex].Text, AName) then
    Exit;
  Open := NextCode(ATokens, AIndex + 1);
  if (Open > High(ATokens)) or not ATokens[Open].IsSymbol('(') then
    Exit;
  Result := NextCode(ATokens, Closing(ATokens, Open) + 1) = AStop;
end;

/// <summary>Ist der Ausdruck von AFirst bis vor AStop ein ganzzahliges Literal (mit Vorzeichen) bzw. ein
/// einzelnes Zeichen? AIsChar unterscheidet beides; andere Ausdrücke liefern False.</summary>
function LiteralBound(const ATokens: TTokens; AFirst, AStop: Integer; out AValue: Int64;
  out AIsChar: Boolean): Boolean;
var
  Sign: Int64;
  Text: string;
begin
  Result := False;
  AValue := 0;
  AIsChar := False;
  Sign := 1;
  if (AFirst <= High(ATokens)) and (ATokens[AFirst].IsSymbol('-') or ATokens[AFirst].IsSymbol('+')) then
  begin
    if ATokens[AFirst].IsSymbol('-') then
      Sign := -1;
    AFirst := NextCode(ATokens, AFirst + 1);
  end;
  if (AFirst > High(ATokens)) or (NextCode(ATokens, AFirst + 1) <> AStop) then
    Exit;
  Text := ATokens[AFirst].Text;
  case ATokens[AFirst].Kind of
    TPascalTokenKind.Number:
      begin
        // $-Hex versteht TryStrToInt64; %-Binär und Gleitkommazahlen bleiben still.
        if not TryStrToInt64(Text, AValue) then
          Exit;
        AValue := Sign * AValue;
        Result := True;
      end;
    TPascalTokenKind.CharLiteral:
      if (Sign = 1) and (Length(Text) > 1) and TryStrToInt64(Copy(Text, 2, MaxInt), AValue) then
      begin
        AIsChar := True;
        Result := True;
      end;
    TPascalTokenKind.StringLiteral:
      if (Sign = 1) and (Length(Text) = 3) and (Text[1] = '''') and (Text[3] = '''') and (Text[2] <> '''') then
      begin
        AValue := Ord(Text[2]);
        AIsChar := True;
        Result := True;
      end;
  end;
end;

procedure TForHighToLowRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Assign, StartExpr, ToToken, EndExpr, DoToken, Last: Integer;
  Suspicious: Boolean;
  StartValue, EndValue: Int64;
  StartIsChar, EndIsChar: Boolean;
  Fix: TRuleFix;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not Tokens[Index].IsKeyword('for') then
      Continue;
    // for I := …, for var I := … und for var I: Integer := ….
    Assign := NextCode(Tokens, Index + 1);
    if (Assign <= High(Tokens)) and Tokens[Assign].IsKeyword('var') then
      Assign := NextCode(Tokens, Assign + 1);
    Assign := NextCode(Tokens, Assign + 1);
    if (Assign <= High(Tokens)) and Tokens[Assign].IsSymbol(':') then
      while (Assign <= High(Tokens)) and not Tokens[Assign].IsSymbol(':=') and
        not Tokens[Assign].IsKeyword('do') do
        Assign := NextCode(Tokens, Assign + 1);
    if (Assign > High(Tokens)) or not Tokens[Assign].IsSymbol(':=') then
      Continue;
    StartExpr := NextCode(Tokens, Assign + 1);
    ToToken := StartExpr;
    while (ToToken <= High(Tokens)) and not Tokens[ToToken].IsKeyword('to') and
      not Tokens[ToToken].IsKeyword('downto') and not Tokens[ToToken].IsKeyword('do') do
      Inc(ToToken);
    if (ToToken > High(Tokens)) or not Tokens[ToToken].IsKeyword('to') then
      Continue;
    EndExpr := NextCode(Tokens, ToToken + 1);
    DoToken := EndExpr;
    while (DoToken <= High(Tokens)) and not Tokens[DoToken].IsKeyword('do') do
      Inc(DoToken);
    if DoToken > High(Tokens) then
      Continue;
    // High(A) to Low(A) bzw. … Count - 1 to 0.
    Suspicious := IsCallUntil(Tokens, StartExpr, ToToken, 'High') and IsCallUntil(Tokens, EndExpr, DoToken, 'Low');
    if not Suspicious then
    begin
      Last := PreviousCode(Tokens, ToToken);
      Suspicious := (Last > StartExpr + 1) and (Tokens[Last].Text = '1') and
        Tokens[PreviousCode(Tokens, Last)].IsSymbol('-') and
        SameText(Tokens[PreviousCode(Tokens, PreviousCode(Tokens, Last))].Text, 'Count') and
        (Tokens[EndExpr].Text = '0') and (NextCode(Tokens, EndExpr + 1) = DoToken);
    end;
    Fix := TRuleFix.Create('to durch downto ersetzen', [TRuleEdit.Create(RangeOf(Tokens, ToToken, ToToken),
      'downto')], True);
    if Suspicious then
      AReport.Add(RangeOf(Tokens, Index, DoToken), 'Die Schleife läuft vom oberen zum unteren Wert mit to und ' +
        'wird daher nie ausgeführt; downto verwenden', TRuleConfidence.High, [Fix])
    // Konstante Grenzen: 10 to 1, -1 to -5, 'z' to 'a', #13 to #10 (#1023, wie H2135).
    else if LiteralBound(Tokens, StartExpr, ToToken, StartValue, StartIsChar) and
      LiteralBound(Tokens, EndExpr, DoToken, EndValue, EndIsChar) and (StartIsChar = EndIsChar) and
      (StartValue > EndValue) then
      AReport.Add(RangeOf(Tokens, Index, DoToken), Format('Die Schleife läuft nie (%s to %s); gemeint war downto ' +
        '(wie H2135).', [Trim(Copy(AContext.Text, Tokens[StartExpr].Offset + 1,
        Tokens[ToToken].Offset - Tokens[StartExpr].Offset)), Trim(Copy(AContext.Text, Tokens[EndExpr].Offset + 1,
        Tokens[DoToken].Offset - Tokens[EndExpr].Offset))]), TRuleConfidence.High, [Fix]);
  end;
end;

{ TExceptionNotRaisedRule }

function TExceptionNotRaisedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-not-raised', TRuleSeverity.Warning,
    'Exception erzeugt, aber nicht ausgelöst');
end;

function IsExceptionClass(const AName: string): Boolean;
begin
  Result := SameText(AName, 'Exception') or ((Length(AName) > 1) and (AName[1] = 'E') and
    CharInSet(AName[2], ['A'..'Z']));
end;

procedure TExceptionNotRaisedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Dot, Ctor, Stop, Before: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not IsExceptionClass(Tokens[Index].Text) then
      Continue;
    Before := PreviousCode(Tokens, Index);
    if not EndsStatement(Tokens, Before) then
      Continue;
    Dot := NextCode(Tokens, Index + 1);
    Ctor := NextCode(Tokens, Dot + 1);
    if (Ctor > High(Tokens)) or not Tokens[Dot].IsSymbol('.') or not StartsText('Create', Tokens[Ctor].Text) then
      Continue;
    Stop := NextCode(Tokens, Ctor + 1);
    if (Stop <= High(Tokens)) and Tokens[Stop].IsSymbol('(') then
      Stop := NextCode(Tokens, Closing(Tokens, Stop) + 1);
    if not IsStatementEnd(Tokens, Stop) then
      Continue;
    AReport.Add(RangeOf(Tokens, Index, PreviousCode(Tokens, Stop)),
      Format('%s wird erzeugt, aber nicht ausgelöst; raise fehlt', [Tokens[Index].Text]), TRuleConfidence.High,
      [TRuleFix.Create('raise voranstellen', [TRuleEdit.Create(TTextRange.Create(Tokens[Index].StartPos,
      Tokens[Index].StartPos), 'raise ')], True)]);
  end;
end;

{ TAssertSideEffectRule }

function TAssertSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('assert-side-effect', TRuleSeverity.Warning, 'Assert mit Seiteneffekt');
end;

class function TAssertSideEffectRule.MutatingMethods(const AOptions: string): TArray<string>;
var
  Value: TJSONValue;
  Items: TJSONArray;
  Item: TJSONValue;
  Index: Integer;
begin
  SetLength(Result, Length(DefaultMutatingMethods));
  for Index := 0 to High(DefaultMutatingMethods) do
    Result[Index] := DefaultMutatingMethods[Index];
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if (Value is TJSONObject) and TJSONObject(Value).TryGetValue<TJSONArray>('mutatingMethods', Items) then
    begin
      Result := nil;
      for Item in Items do
        if Item is TJSONString then
          Result := Result + [Item.Value];
    end;
  finally
    Value.Free;
  end;
end;

procedure TAssertSideEffectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Methods: TArray<string>;
  Index, Open, Close, Inner, Next: Integer;
  Effect: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Methods := MutatingMethods(AContext.Options);
  for Index := 0 to High(Tokens) do
  begin
    if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, 'Assert')) then
      Continue;
    Open := NextCode(Tokens, Index + 1);
    if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      Continue;
    Close := Closing(Tokens, Open);
    if Close < 0 then
      Continue;
    Effect := '';
    for Inner := Open + 1 to Close - 1 do
    begin
      if Tokens[Inner].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Next := NextCode(Tokens, Inner + 1);
      if MatchText(Tokens[Inner].Text, ['Inc', 'Dec']) and (Next < Close) and Tokens[Next].IsSymbol('(') then
        Effect := Tokens[Inner].Text
      // Try…-Funktionen geben ihr Ergebnis über einen out-Parameter zurück.
      else if StartsText('Try', Tokens[Inner].Text) and (Length(Tokens[Inner].Text) > 3) and
        CharInSet(Tokens[Inner].Text[4], ['A'..'Z']) and (Next < Close) and Tokens[Next].IsSymbol('(') then
        Effect := Tokens[Inner].Text
      else if MatchText(Tokens[Inner].Text, Methods) and (Inner > Open + 1) and
        Tokens[PreviousCode(Tokens, Inner)].IsSymbol('.') then
        Effect := Tokens[Inner].Text;
      if Effect <> '' then
        Break;
    end;
    if Effect <> '' then
      AReport.Add(RangeOf(Tokens, Index, Close), Format('%s im Assert verändert Daten; mit {$C-} entfällt der ' +
        'ganze Aufruf samt Seiteneffekt. Vorher ausführen und nur das Ergebnis prüfen', [Effect]),
        TRuleConfidence.High);
  end;
end;

{ TIfThenSideEffectRule }

function TIfThenSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('ifthen-side-effect', TRuleSeverity.Warning,
    'IfThen wertet beide Zweige aus');
end;

/// <summary>Namen, die die Bedingung auf nil prüft: Assigned(X), X <> nil.</summary>
function CheckedNames(const ATokens: TTokens; AFirst, ALast: Integer): TArray<string>;
var
  Index, Next, Name: Integer;
begin
  Result := nil;
  for Index := AFirst to ALast do
  begin
    Next := NextCode(ATokens, Index + 1);
    if SameText(ATokens[Index].Text, 'Assigned') and (Next <= ALast) and ATokens[Next].IsSymbol('(') then
    begin
      Name := NextCode(ATokens, Next + 1);
      if Name <= ALast then
        Result := Result + [LowerCase(ATokens[Name].Text)];
    end
    else if ATokens[Index].IsKeyword('nil') then
    begin
      Name := PreviousCode(ATokens, PreviousCode(ATokens, Index));
      if (Name >= AFirst) and (ATokens[Name].Kind = TPascalTokenKind.Identifier) then
        Result := Result + [LowerCase(ATokens[Name].Text)];
    end;
  end;
end;

procedure TIfThenSideEffectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Args: TArray<TSpan>;
  Checked: TArray<string>;
  Index, Open, Close, Arg, Inner, Next, Assign, Target, Stop: Integer;
  Confidence: TRuleConfidence;
  Found: Boolean;
  Fixes: TArray<TRuleFix>;
  Text: string;

  function Slice(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Tokens[AFirst].Offset + 1, Tokens[ALast].Offset + Length(Tokens[ALast].Text) -
      Tokens[AFirst].Offset);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, 'IfThen')) then
      Continue;
    Open := NextCode(Tokens, Index + 1);
    if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      Continue;
    Close := Closing(Tokens, Open);
    if Close < 0 then
      Continue;
    Args := Arguments(Tokens, Open, Close);
    if Length(Args) <> 3 then
      Continue;
    Checked := CheckedNames(Tokens, Args[0].First, Args[0].Last);
    Found := False;
    Confidence := TRuleConfidence.Medium;
    for Arg := 1 to 2 do
      for Inner := Args[Arg].First to Args[Arg].Last do
      begin
        Next := NextCode(Tokens, Inner + 1);
        if Tokens[Inner].Kind <> TPascalTokenKind.Identifier then
          Continue;
        // Zugriff auf einen in der Bedingung geprüften Bezeichner: X.Name oder X^.
        if MatchText(Tokens[Inner].Text, Checked) and (Next <= Args[Arg].Last) and
          (Tokens[Next].IsSymbol('.') or Tokens[Next].IsSymbol('^')) and
          ((Inner = Args[Arg].First) or not Tokens[PreviousCode(Tokens, Inner)].IsSymbol('.')) then
        begin
          Found := True;
          Confidence := TRuleConfidence.High;
        end
        else if (Next <= Args[Arg].Last) and Tokens[Next].IsSymbol('(') then
          Found := True;
      end;
    if not Found then
      Continue;
    // V := IfThen(B, X, Y); → if B then V := X else V := Y;
    Fixes := nil;
    Assign := PreviousCode(Tokens, Index);
    Stop := NextCode(Tokens, Close + 1);
    if (Assign >= 0) and Tokens[Assign].IsSymbol(':=') and (Stop <= High(Tokens)) and Tokens[Stop].IsSymbol(';') then
    begin
      Target := PreviousCode(Tokens, Assign);
      while (Target > 0) and not EndsStatement(Tokens, PreviousCode(Tokens, Target)) do
        Target := PreviousCode(Tokens, Target);
      if (Target >= 0) and IsDesignator(Tokens, Target, PreviousCode(Tokens, Assign)) then
      begin
        Text := Slice(Target, PreviousCode(Tokens, Assign));
        Fixes := [TRuleFix.Create('In if-Anweisung umwandeln', [TRuleEdit.Create(RangeOf(Tokens, Target, Stop),
          'if ' + Slice(Args[0].First, Args[0].Last) + ' then ' + Text + ' := ' + Slice(Args[1].First, Args[1].Last) +
          ' else ' + Text + ' := ' + Slice(Args[2].First, Args[2].Last) + ';')])];
      end;
    end;
    AReport.Add(RangeOf(Tokens, Index, Close), 'IfThen wertet beide Zweige aus, auch den nicht gewählten; ' +
      'Seiteneffekte und Nil-Zugriffe darin treten immer auf. if-Anweisung verwenden', Confidence, Fixes);
  end;
end;

{ TRandomWithoutRandomizeRule }

function TRandomWithoutRandomizeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('random-without-randomize', TRuleSeverity.Hint, 'Random ohne Randomize',
    True);
end;

procedure TRandomWithoutRandomizeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, First: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  First := -1;
  for Index := 0 to High(Tokens) do
    if Tokens[Index].Kind = TPascalTokenKind.Identifier then
      if SameText(Tokens[Index].Text, 'Randomize') then
        Exit
      else if (First < 0) and SameText(Tokens[Index].Text, 'Random') and
        ((Index = 0) or not Tokens[PreviousCode(Tokens, Index)].IsSymbol('.')) then
        First := Index;
  if First >= 0 then
    AReport.Add(RangeOf(Tokens, First, First), 'Random ohne Randomize in dieser Unit liefert bei jedem Start ' +
      'dieselbe Folge; Randomize einmal beim Programmstart aufrufen', TRuleConfidence.Low);
end;

procedure RegisterRtlPatternRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSelfAssignmentRule.Create);
  ARegistry.Register(TForHighToLowRule.Create);
  ARegistry.Register(TExceptionNotRaisedRule.Create);
  ARegistry.Register(TAssertSideEffectRule.Create);
  ARegistry.Register(TIfThenSideEffectRule.Create);
  ARegistry.Register(TRandomWithoutRandomizeRule.Create);
end;

end.
