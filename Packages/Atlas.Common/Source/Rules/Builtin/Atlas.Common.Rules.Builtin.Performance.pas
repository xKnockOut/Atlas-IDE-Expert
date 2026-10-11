unit Atlas.Common.Rules.Builtin.Performance;

// Performance-Regeln (#278, abgetrennt aus #57). Alle standardmäßig aus:
//   string-concat-in-loop     S := S + … in einer Schleife; in Delphi meist harmlos
//                             (In-place-Vergrößerung), deshalb nur niedrige Konfidenz
//   loop-invariant-call       teurer Aufruf in der Bedingung von while bzw. until, die bei
//                             jedem Durchlauf neu ausgewertet wird (die Grenzen von for nicht)
//   missing-begin-update      Items/Lines/Strings.Add in einer Schleife ohne BeginUpdate
// ParamByName in Schleifen und DisableControls gehören zu #70.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TStringConcatInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopInvariantCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMissingBeginUpdateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Performance-Regeln.</summary>
procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.DeclaredTypes;

type
  TTokens = TArray<TPascalToken>;

  /// <summary>Schleife mit Rumpf und (bei while/repeat) Bedingung als Tokenbereiche.</summary>
  TLoop = record
    Keyword: Integer;
    BodyFirst: Integer;
    BodyLast: Integer;
    /// <summary>Bedingung von while bzw. until; CondFirst > CondLast bei for.</summary>
    CondFirst: Integer;
    CondLast: Integer;
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
    AToken.IsKeyword('asm') or AToken.IsKeyword('repeat');
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
    else if ATokens[Index].IsKeyword('until') then
      Dec(Depth)
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

/// <summary>Index von do bzw. until ab AFirst auf gleicher Klammerebene; -1 ohne.</summary>
function FindKeyword(const ATokens: TTokens; AFirst: Integer; const AKeyword: string): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFirst to High(ATokens) do
    if (Depth = 0) and ATokens[Index].IsKeyword(AKeyword) then
      Exit(Index)
    else if (AKeyword = 'until') and ATokens[Index].IsKeyword('repeat') then
      Inc(Depth)
    else if (AKeyword = 'until') and ATokens[Index].IsKeyword('until') then
      Dec(Depth)
    else if (AKeyword = 'do') and ATokens[Index].IsSymbol(';') then
      Exit(-1);
  Result := -1;
end;

function Loops(const ATokens: TTokens): TArray<TLoop>;
var
  Index, Mark: Integer;
  Loop: TLoop;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    Loop := Default(TLoop);
    Loop.Keyword := Index;
    if ATokens[Index].IsKeyword('for') or ATokens[Index].IsKeyword('while') then
    begin
      Mark := FindKeyword(ATokens, Index + 1, 'do');
      if Mark < 0 then
        Continue;
      Loop.BodyFirst := NextCode(ATokens, Mark + 1);
      if Loop.BodyFirst > High(ATokens) then
        Continue;
      Loop.BodyLast := StatementEnd(ATokens, Loop.BodyFirst);
      if ATokens[Index].IsKeyword('while') then
      begin
        Loop.CondFirst := NextCode(ATokens, Index + 1);
        Loop.CondLast := PreviousCode(ATokens, Mark);
      end
      else
      begin
        Loop.CondFirst := 1;
        Loop.CondLast := 0;
      end;
    end
    else if ATokens[Index].IsKeyword('repeat') then
    begin
      Mark := FindKeyword(ATokens, Index + 1, 'until');
      if Mark < 0 then
        Continue;
      Loop.BodyFirst := Index + 1;
      Loop.BodyLast := PreviousCode(ATokens, Mark);
      Loop.CondFirst := NextCode(ATokens, Mark + 1);
      Loop.CondLast := StatementEnd(ATokens, Loop.CondFirst);
    end
    else
      Continue;
    Result := Result + [Loop];
  end;
end;

/// <summary>Liegt Token AIndex im Rumpf einer der Schleifen?</summary>
function InLoopBody(const ALoops: TArray<TLoop>; AIndex: Integer): Boolean;
var
  Loop: TLoop;
begin
  for Loop in ALoops do
    if (AIndex >= Loop.BodyFirst) and (AIndex <= Loop.BodyLast) then
      Exit(True);
  Result := False;
end;

/// <summary>Beginnt an AIndex ein Bezeichner, dem kein Punkt vorausgeht?</summary>
function StartsDesignator(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    ((AIndex = 0) or not ATokens[PreviousCode(ATokens, AIndex)].IsSymbol('.'));
end;

/// <summary>Punktkette ab AIndex (A.B.C) als Text in Kleinbuchstaben; ALast = letztes Token.</summary>
function Chain(const ATokens: TTokens; AIndex: Integer; out ALast: Integer): string;
var
  Dot: Integer;
begin
  Result := LowerCase(ATokens[AIndex].Text);
  ALast := AIndex;
  Dot := NextCode(ATokens, ALast + 1);
  while (Dot < High(ATokens)) and ATokens[Dot].IsSymbol('.') and
    (ATokens[NextCode(ATokens, Dot + 1)].Kind = TPascalTokenKind.Identifier) do
  begin
    ALast := NextCode(ATokens, Dot + 1);
    Result := Result + '.' + LowerCase(ATokens[ALast].Text);
    Dot := NextCode(ATokens, ALast + 1);
  end;
end;

{ TStringConcatInLoopRule }

function TStringConcatInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('string-concat-in-loop', TRuleSeverity.Hint,
    'String-Verkettung in einer Schleife', True);
end;

procedure TStringConcatInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Found: TArray<TLoop>;
  Types: TDeclaredTypes;
  Index, Assign, Same, Plus, Last: Integer;
  TypeName: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Found := Loops(Tokens);
  if Found = nil then
    Exit;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      // S := S + …
      if not StartsDesignator(Tokens, Index) or not InLoopBody(Found, Index) then
        Continue;
      Assign := NextCode(Tokens, Index + 1);
      Same := NextCode(Tokens, Assign + 1);
      Plus := NextCode(Tokens, Same + 1);
      if (Plus > High(Tokens)) or not Tokens[Assign].IsSymbol(':=') or
        not SameText(Tokens[Same].Text, Tokens[Index].Text) or not Tokens[Plus].IsSymbol('+') then
        Continue;
      TypeName := Types.DeclaredType(Tokens[Index].Text, Tokens[Index].StartPos);
      if not MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'UTF8String',
        'RawByteString']) then
        Continue;
      Last := StatementEnd(Tokens, Index);
      AReport.Add(RangeOf(Tokens, Index, Last), Format('%s wird in der Schleife schrittweise verlängert; bei ' +
        'vielen Durchläufen ist TStringBuilder schneller', [Tokens[Index].Text]), TRuleConfidence.Low);
    end;
  finally
    Types.Free;
  end;
end;

{ TLoopInvariantCallRule }

const
  ExpensiveCalls: array[0..17] of string = ('Trim', 'TrimLeft', 'TrimRight', 'LowerCase', 'UpperCase',
    'AnsiLowerCase', 'AnsiUpperCase', 'Format', 'StrToInt', 'StrToFloat', 'IntToStr', 'FileExists',
    'DirectoryExists', 'ExtractFileName', 'ExtractFilePath', 'StringReplace', 'Copy', 'ComponentCount');
  ExpensiveProperties: array[0..2] of string = ('Text', 'CommaText', 'DelimitedText');

function TLoopInvariantCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('loop-invariant-call', TRuleSeverity.Hint,
    'Teurer Aufruf in der Schleifenbedingung', True);
end;

procedure TLoopInvariantCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Loop: TLoop;
  Index, Previous: Integer;
  Name: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Loop in Loops(Tokens) do
    for Index := Loop.CondFirst to Loop.CondLast do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Name := Tokens[Index].Text;
      Previous := PreviousCode(Tokens, Index);
      if MatchText(Name, ExpensiveProperties) and (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
        AReport.Add(RangeOf(Tokens, Index, Index), Format('.%s baut bei jeder Prüfung der Bedingung einen neuen ' +
          'String auf; vor der Schleife in eine Variable übernehmen', [Name]), TRuleConfidence.Medium)
      else if MatchText(Name, ExpensiveCalls) and StartsDesignator(Tokens, Index) then
        AReport.Add(RangeOf(Tokens, Index, Index), Format('%s wird bei jeder Prüfung der Bedingung erneut ' +
          'ausgeführt; ändert sich das Ergebnis nicht, vor der Schleife berechnen', [Name]), TRuleConfidence.Medium);
    end;
end;

{ TMissingBeginUpdateRule }

function TMissingBeginUpdateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('missing-begin-update', TRuleSeverity.Hint,
    'Hinzufügen in einer Schleife ohne BeginUpdate', True);
end;

procedure TMissingBeginUpdateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Found: TArray<TLoop>;
  Updated, Reported: TArray<string>;
  Index, Last, Dot: Integer;
  Text, Receiver, Method, Collection, ReceiverText: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Found := Loops(Tokens);
  if Found = nil then
    Exit;
  // Empfänger, für die irgendwo in der Datei BeginUpdate aufgerufen wird.
  Updated := nil;
  for Index := 0 to High(Tokens) do
    if StartsDesignator(Tokens, Index) then
    begin
      Text := Chain(Tokens, Index, Last);
      if EndsText('.beginupdate', Text) then
        Updated := Updated + [Copy(Text, 1, Length(Text) - Length('.beginupdate'))];
    end;
  Reported := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not StartsDesignator(Tokens, Index) or not InLoopBody(Found, Index) then
      Continue;
    Text := Chain(Tokens, Index, Last);
    Dot := LastDelimiter('.', Text);
    if Dot = 0 then
      Continue;
    Receiver := Copy(Text, 1, Dot - 1);
    Method := Copy(Text, Dot + 1, MaxInt);
    Collection := Copy(Receiver, LastDelimiter('.', Receiver) + 1, MaxInt);
    // Nur sichtbare Listen: ListBox1.Items, Memo1.Lines, TreeView1.Items; Receiver hat mindestens zwei Glieder.
    if (Pos('.', Receiver) = 0) or not MatchText(Collection, ['items', 'lines', 'strings']) or
      not MatchText(Method, ['add', 'addobject', 'append', 'insert', 'addchild', 'addchildobject', 'addpair']) then
      Continue;
    if MatchText(Receiver, Updated) or MatchText(Copy(Receiver, 1, LastDelimiter('.', Receiver) - 1), Updated) or
      MatchText(Receiver, Reported) then
      Continue;
    Reported := Reported + [Receiver];
    ReceiverText := Copy(AContext.Text, Tokens[Index].Offset + 1,
      Tokens[PreviousCode(Tokens, Last)].Offset - Tokens[Index].Offset);
    AReport.Add(RangeOf(Tokens, Index, Last), Format('Jedes %s in der Schleife zeichnet das Steuerelement neu; ' +
      'die Schleife mit %s.BeginUpdate und try … finally %s.EndUpdate umschließen',
      [Tokens[Last].Text, ReceiverText, ReceiverText]),
      TRuleConfidence.Medium);
  end;
end;

procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringConcatInLoopRule.Create);
  ARegistry.Register(TLoopInvariantCallRule.Create);
  ARegistry.Register(TMissingBeginUpdateRule.Create);
end;

end.
