unit Atlas.Common.Rules.Builtin.Performance;

// Performance-Regeln (#278, abgetrennt aus #57). Alle standardmäßig aus:
//   string-concat-in-loop     S := S + … in einer Schleife; in Delphi meist harmlos
//                             (In-place-Vergrößerung), deshalb nur niedrige Konfidenz
//   loop-invariant-call       teurer Aufruf in der Bedingung von while bzw. until, die bei
//                             jedem Durchlauf neu ausgewertet wird (die Grenzen von for nicht)
//   missing-begin-update      Items/Lines/Strings.Add in einer Schleife ohne BeginUpdate; still bei
//                             Menüs (TMenuItem hat kein BeginUpdate) und bei for-Schleifen mit
//                             höchstens FewIterations Durchläufen (feste Grenzen bzw. statisches
//                             Array der Datei)
// Standardmäßig an (#974):
//   setlength-in-loop         SetLength(A, Length(A) + 1) in einer Schleife kopiert das
//                             dynamische Array bei jedem Durchlauf; gemeldet wird nur, wenn A
//                             sicher ein dynamisches Array ist (Typ in der Datei bzw. bekannter
//                             RTL-Typ, nie Strings). Bei einer for-Schleife ist die Anzahl
//                             bekannt; dann setzt die Korrektur die Länge vor der Schleife,
//                             wenn A eine lokale Variable ist, die vorher nicht benutzt wird,
//                             und A in der Schleife nur über A[High(A)] bzw. A[Length(A) - 1]
//                             beschrieben wird.
// Standardmäßig aus (#975):
//   managed-param-without-const  String-, Interface-, Array- bzw. Record-Parameter (ab
//                             minRecordSize Byte) ohne const, den die Routine sicher nicht
//                             verändert; Übergabe an Aufrufe mit unbekannter Signatur, with,
//                             anonyme Methoden und inherited ohne Namen lassen die Regel
//                             schweigen. Vorgegebene Signaturen (virtual, Interfaces,
//                             published, Ereignisse) bleiben außen vor. Die Korrektur
//                             ergänzt const in Rumpf und Deklaration.
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

  TSetLengthInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TManagedParamWithoutConstRule = class(TInterfacedObject, IRule)
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
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ResolvedSignatures,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived;

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

/// <summary>Letztes Token der Anweisung ab AFirst: bis zum passenden end bzw. vor ; oder end.
/// Ein else gehört zur Anweisung, solange ein if davor noch keinen else-Zweig hat
/// (if … then begin … end else …).</summary>
function StatementEnd(const ATokens: TTokens; AFirst: Integer): Integer;
var
  Index, Depth, OpenIfs: Integer;
begin
  Depth := 0;
  OpenIfs := 0;
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
      // Beginnt die Anweisung selbst mit dem Block, endet sie mit seinem end.
      if (Depth = 0) and OpensBlock(ATokens[AFirst]) then
        Exit(Index);
    end
    else if (Depth = 0) and ATokens[Index].IsKeyword('if') then
      Inc(OpenIfs)
    else if (Depth = 0) and ATokens[Index].IsKeyword('else') then
    begin
      if OpenIfs = 0 then
        Exit;
      Dec(OpenIfs);
    end
    else if (Depth = 0) and ATokens[Index].IsSymbol(';') then
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

const
  /// <summary>Bis zu so vielen Durchläufen lohnt BeginUpdate nicht.</summary>
  FewIterations = 10;
  /// <summary>Menüs: Items ist ein TMenuItem, das kein BeginUpdate kennt.</summary>
  MenuTypes: array[0..3] of string = ('TMenu', 'TMainMenu', 'TPopupMenu', 'TMenuItem');

/// <summary>Ganzzahl ab AIndex (mit Vorzeichen -); ALast = letztes Token.</summary>
function IntegerAt(const ATokens: TTokens; AIndex: Integer; out AValue: Int64; out ALast: Integer): Boolean;
var
  Negative: Boolean;
begin
  Result := False;
  AValue := 0;
  ALast := AIndex;
  if AIndex > High(ATokens) then
    Exit;
  Negative := ATokens[AIndex].IsSymbol('-');
  if Negative then
    ALast := NextCode(ATokens, AIndex + 1);
  if (ALast > High(ATokens)) or (ATokens[ALast].Kind <> TPascalTokenKind.Number) or
    not TryStrToInt64(ATokens[ALast].Text, AValue) then
    Exit;
  if Negative then
    AValue := -AValue;
  Result := True;
end;

/// <summary>Grenzen des statischen Arrays AName, das in der Datei als AName: array[A..B] steht.</summary>
function StaticArrayBounds(const ATokens: TTokens; const AName: string; out ALow, AHigh: Int64): Boolean;
var
  Index, Next, Last: Integer;
begin
  ALow := 0;
  AHigh := -1;
  for Index := 0 to High(ATokens) - 1 do
  begin
    if (ATokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(ATokens[Index].Text, AName) then
      Continue;
    Next := NextCode(ATokens, Index + 1);
    if (Next > High(ATokens)) or not ATokens[Next].IsSymbol(':') then
      Continue;
    Next := NextCode(ATokens, Next + 1);
    if (Next > High(ATokens)) or not ATokens[Next].IsKeyword('array') then
      Continue;
    Next := NextCode(ATokens, Next + 1);
    if (Next > High(ATokens)) or not ATokens[Next].IsSymbol('[') or
      not IntegerAt(ATokens, NextCode(ATokens, Next + 1), ALow, Last) then
      Continue;
    Next := NextCode(ATokens, Last + 1);
    if (Next > High(ATokens)) or not ATokens[Next].IsSymbol('..') or
      not IntegerAt(ATokens, NextCode(ATokens, Next + 1), AHigh, Last) then
      Continue;
    Next := NextCode(ATokens, Last + 1);
    if (Next <= High(ATokens)) and ATokens[Next].IsSymbol(']') then
      Exit(True);
  end;
  Result := False;
end;

/// <summary>Grenze einer for-Schleife ab AIndex bis vor AStop: Zahl, Low(X) oder High(X) mit
/// statischem Array X der Datei.</summary>
function BoundAt(const ATokens: TTokens; AIndex, AStop: Integer; out AValue: Int64): Boolean;
var
  Last, Open, Name, Close: Integer;
  First, Final: Int64;
begin
  if IntegerAt(ATokens, AIndex, AValue, Last) then
    Exit(NextCode(ATokens, Last + 1) = AStop);
  Result := False;
  Open := NextCode(ATokens, AIndex + 1);
  Name := NextCode(ATokens, Open + 1);
  Close := NextCode(ATokens, Name + 1);
  if (Close >= AStop) or (NextCode(ATokens, Close + 1) <> AStop) or not ATokens[Open].IsSymbol('(') or
    (ATokens[Name].Kind <> TPascalTokenKind.Identifier) or not ATokens[Close].IsSymbol(')') or
    not StaticArrayBounds(ATokens, ATokens[Name].Text, First, Final) then
    Exit;
  if SameText(ATokens[AIndex].Text, 'Low') then
    AValue := First
  else if SameText(ATokens[AIndex].Text, 'High') then
    AValue := Final
  else
    Exit;
  Result := True;
end;

/// <summary>Anzahl der Durchläufe einer for-Schleife mit festen Grenzen bzw. über ein statisches
/// Array der Datei; -1 wenn unbekannt (while, repeat, Grenzen erst zur Laufzeit).</summary>
function FixedIterations(const ATokens: TTokens; const ALoop: TLoop): Int64;
var
  Index, Stop, Bound: Integer;
  First, Last: Int64;
begin
  Result := -1;
  if not ATokens[ALoop.Keyword].IsKeyword('for') then
    Exit;
  Stop := FindKeyword(ATokens, ALoop.Keyword + 1, 'do');
  Index := NextCode(ATokens, ALoop.Keyword + 1);
  if (Index <= High(ATokens)) and ATokens[Index].IsKeyword('var') then
    Index := NextCode(ATokens, Index + 1);
  Index := NextCode(ATokens, Index + 1);
  if (Stop < 0) or (Index >= Stop) then
    Exit;
  if ATokens[Index].IsKeyword('in') then
  begin
    // for X in Werte do: Werte ist ein statisches Array der Datei.
    Index := NextCode(ATokens, Index + 1);
    if (NextCode(ATokens, Index + 1) = Stop) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and
      StaticArrayBounds(ATokens, ATokens[Index].Text, First, Last) then
      Result := Last - First + 1;
    Exit;
  end;
  if not ATokens[Index].IsSymbol(':=') then
    Exit;
  Bound := Index + 1;
  while (Bound < Stop) and not ATokens[Bound].IsKeyword('to') and not ATokens[Bound].IsKeyword('downto') do
    Inc(Bound);
  if (Bound >= Stop) or not BoundAt(ATokens, NextCode(ATokens, Index + 1), Bound, First) or
    not BoundAt(ATokens, NextCode(ATokens, Bound + 1), Stop, Last) then
    Exit;
  if ATokens[Bound].IsKeyword('downto') then
    Result := First - Last + 1
  else
    Result := Last - First + 1;
  if Result < 0 then
    Result := 0;
end;

/// <summary>Durchlaufen alle Schleifen um AIndex zusammen höchstens FewIterations Mal?</summary>
function FewInLoops(const ATokens: TTokens; const ALoops: TArray<TLoop>; AIndex: Integer): Boolean;
var
  Loop: TLoop;
  Total, Count: Int64;
begin
  Total := 1;
  for Loop in ALoops do
    if (AIndex >= Loop.BodyFirst) and (AIndex <= Loop.BodyLast) then
    begin
      Count := FixedIterations(ATokens, Loop);
      if Count < 0 then
        Exit(False);
      Total := Total * Count;
      if Total > FewIterations then
        Exit(False);
    end;
  Result := True;
end;

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
  Types: TDeclaredTypes;
  Index, Last, Dot: Integer;
  Text, Receiver, Method, Collection, ReceiverText, Owner: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Found := Loops(Tokens);
  if Found = nil then
    Exit;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
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
      // Menu.Items ist ein TMenuItem ohne BeginUpdate.
      Owner := Copy(Receiver, 1, LastDelimiter('.', Receiver) - 1);
      if StartsText('self.', Owner) then
        Owner := Copy(Owner, Length('self.') + 1, MaxInt);
      if (Pos('.', Owner) = 0) and MatchText(Types.DeclaredType(Owner, Tokens[Index].StartPos), MenuTypes) then
        Continue;
      // Wenige Einträge: Das Neuzeichnen fällt nicht ins Gewicht.
      if FewInLoops(Tokens, Found, Index) then
        Continue;
      Reported := Reported + [Receiver];
      ReceiverText := Copy(AContext.Text, Tokens[Index].Offset + 1,
        Tokens[PreviousCode(Tokens, Last)].Offset - Tokens[Index].Offset);
      AReport.Add(RangeOf(Tokens, Index, Last), Format('Jedes %s in der Schleife zeichnet das Steuerelement neu; ' +
        'die Schleife mit %s.BeginUpdate und try … finally %s.EndUpdate umschließen',
        [Tokens[Last].Text, ReceiverText, ReceiverText]),
        TRuleConfidence.Medium);
    end;
  finally
    Types.Free;
  end;
end;

{ TSetLengthInLoopRule }

const
  /// <summary>Dynamische Arrays der RTL, die nicht in der Datei deklariert sind.</summary>
  RtlDynamicArrays: array[0..13] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray',
    'TInt64DynArray', 'TCardinalDynArray', 'TDoubleDynArray', 'TSingleDynArray', 'TByteDynArray',
    'TWordDynArray', 'TBooleanDynArray', 'TShortIntDynArray', 'TSmallIntDynArray', 'TLongWordDynArray',
    'TExtendedDynArray');

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Ist ANode der Aufruf AName(X) mit genau einem Argument, dessen Text ATarget ist?</summary>
function IsCallOf(const AText: string; ANode: TSyntaxNode; const AName, ATarget: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    SameText(ANode.Name, AName) and SameText(NodeText(AText, ANode[1]), ATarget);
end;

/// <summary>Ganzzahliges Literal ab 1?</summary>
function IsPositiveLiteral(ANode: TSyntaxNode): Boolean;
var
  Value: Integer;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and TryStrToInt(ANode.Name, Value) and (Value >= 1);
end;

/// <summary>Vergrößert ALength die Länge von ATarget um einen festen Schritt: Length(A) + n, n + Length(A),
/// Succ(Length(A)) oder High(A) + n mit n ab 2?</summary>
function IsGrowth(const AText: string; ALength: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := False;
  if (ALength.Kind = TSyntaxKind.Call) and SameText(ALength.Name, 'Succ') and (ALength.ChildCount = 2) then
    Exit(IsCallOf(AText, ALength[1], 'Length', ATarget));
  if (ALength.Kind <> TSyntaxKind.BinaryExpr) or (ALength.Name <> '+') or (ALength.ChildCount <> 2) then
    Exit;
  if IsCallOf(AText, ALength[0], 'Length', ATarget) then
    Result := IsPositiveLiteral(ALength[1])
  else if IsCallOf(AText, ALength[1], 'Length', ATarget) then
    Result := IsPositiveLiteral(ALength[0])
  else if IsCallOf(AText, ALength[0], 'High', ATarget) then
    Result := IsPositiveLiteral(ALength[1]) and (ALength[1].Name <> '1');
end;

/// <summary>Letztes Element von ATarget als Index: High(A) bzw. Length(A) - 1?</summary>
function IsLastIndex(const AText: string; AIndex: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := IsCallOf(AText, AIndex, 'High', ATarget) or
    ((AIndex.Kind = TSyntaxKind.BinaryExpr) and (AIndex.Name = '-') and (AIndex.ChildCount = 2) and
    IsCallOf(AText, AIndex[0], 'Length', ATarget) and (AIndex[1].Kind = TSyntaxKind.Literal) and
    (AIndex[1].Name = '1'));
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

/// <summary>Innerste Schleife um ANode innerhalb derselben Routine; nil ohne.</summary>
function EnclosingLoop(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not IsLoop(Result) do
  begin
    if Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      Exit(nil);
    Result := Result.Parent;
  end;
end;

/// <summary>Rumpf der Schleife; bei repeat nil (mehrere Anweisungen).</summary>
function LoopBody(ALoop: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ALoop.Kind <> TSyntaxKind.RepeatStatement) and (ALoop.ChildCount > 0) then
    Result := ALoop[ALoop.ChildCount - 1];
end;

/// <summary>Steht AStatement direkt im Rumpf von ALoop, wird es also bei jedem Durchlauf ausgeführt?</summary>
function RunsEveryIteration(ALoop, AStatement: TSyntaxNode): Boolean;
var
  Body: TSyntaxNode;
begin
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
    Exit(AStatement.Parent = ALoop);
  Body := LoopBody(ALoop);
  Result := (Body = AStatement) or ((Body <> nil) and (Body.Kind = TSyntaxKind.Block) and (AStatement.Parent = Body));
end;

/// <summary>Ist ATypeText ein dynamisches Array? ADeclared: Namen der Array-Typen der Datei.</summary>
function IsDynamicArrayType(const ATypeText: string; const ADeclared: TArray<string>): Boolean;
var
  Text: string;
begin
  Text := Trim(ATypeText);
  Result := StartsText('array of ', Text) or StartsText('TArray<', Text) or MatchText(Text, RtlDynamicArrays) or
    MatchText(Text, ADeclared);
end;

/// <summary>Namen der Typen der Datei, die als dynamisches Array deklariert sind (T = array of X bzw. TArray&lt;X&gt;).
/// </summary>
function DynamicArrayTypes(const AText: string; ARoot: TSyntaxNode): TArray<string>;
var
  Found: TArray<string>;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Child: TSyntaxNode;
      Text: string;
    begin
      Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.ClassType, TSyntaxKind.RecordType]);
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.ChildCount > 0) then
      begin
        Child := ANode[ANode.ChildCount - 1];
        Text := Trim(NodeText(AText, Child));
        if ((Child.Kind = TSyntaxKind.ArrayType) and StartsText('array of ', Text)) or
          ((Child.Kind = TSyntaxKind.TypeReference) and StartsText('TArray<', Text)) then
          Found := Found + [ANode.Name];
      end;
    end);
  Result := Found;
end;

/// <summary>Ergebnistyp der Funktion um ANode als Quelltext; '' ohne.</summary>
function ResultType(const AText: string; ANode: TSyntaxNode): string;
var
  Routine, Header: TSyntaxNode;
begin
  Result := '';
  Routine := ANode.Parent;
  while (Routine <> nil) and (Routine.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if Routine.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    Routine := Routine.Parent;
  end;
  if Routine = nil then
    Exit;
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if (Header <> nil) and (Header.ChildCount > 0) and (Header[Header.ChildCount - 1].Kind <> TSyntaxKind.Parameters) then
  begin
    Header := Header.FindChild(TSyntaxKind.TypeReference);
    if Header <> nil then
      Result := NodeText(AText, Header);
  end;
end;

/// <summary>Anzahl der Durchläufe einer for-Schleife als Quelltext; '' wenn sie nicht sicher zu bestimmen ist.
/// ALoopIndex: Ausdruck für den Index des I-ten Elements (I bzw. I - Start).</summary>
function ForCount(const AText: string; ALoop: TSyntaxNode; out ALoopIndex: string): string;
var
  First, Last: TSyntaxNode;
  LowText, HighText: string;
begin
  Result := '';
  ALoopIndex := '';
  if (ALoop.Kind <> TSyntaxKind.ForStatement) or (ALoop.ChildCount < 3) then
    Exit;
  First := ALoop[ALoop.ChildCount - 3];
  Last := ALoop[ALoop.ChildCount - 2];
  if ContainsText(Copy(AText, First.EndOffset + 1, Last.StartOffset - First.EndOffset), 'downto') then
    Exit;
  LowText := Trim(NodeText(AText, First));
  HighText := Trim(NodeText(AText, Last));
  if LowText = '0' then
  begin
    ALoopIndex := ALoop.Name;
    if (Last.Kind = TSyntaxKind.BinaryExpr) and (Last.Name = '-') and (Last.ChildCount = 2) and
      (Last[1].Kind = TSyntaxKind.Literal) and (Last[1].Name = '1') then
      Result := Trim(NodeText(AText, Last[0]))
    else
      Result := HighText + ' + 1';
  end
  else if LowText = '1' then
  begin
    Result := HighText;
    ALoopIndex := ALoop.Name + ' - 1';
  end
  else
  begin
    Result := Format('%s - %s + 1', [HighText, LowText]);
    ALoopIndex := Format('%s - %s', [ALoop.Name, LowText]);
  end;
end;

function TSetLengthInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('setlength-in-loop', TRuleSeverity.Hint,
    'Dynamisches Array wächst in einer Schleife um je ein Element');
end;

procedure TSetLengthInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Types: TDeclaredTypes;
  ArrayTypes: TArray<string>;
  Calls: TArray<TSyntaxNode>;
  Call, Statement, Loop: TSyntaxNode;
  Target, Count, LoopIndex, TypeText: string;
  Fixes: TArray<TRuleFix>;

  function Range(AStart, AEnd: Integer): TTextRange;
  begin
    Result := TRuleDerived.OffsetRange(Cache, AContext, AStart, AEnd);
  end;

  function LineStart(AOffset: Integer): Integer;
  begin
    Result := AOffset;
    while (Result > 0) and not CharInSet(AContext.Text[Result], [#10, #13]) do
      Dec(Result);
  end;

  function Indent(AOffset: Integer): string;
  var
    Start, Index: Integer;
  begin
    Start := LineStart(AOffset);
    Index := Start;
    while (Index < AOffset) and CharInSet(AContext.Text[Index + 1], [' ', #9]) do
      Inc(Index);
    Result := Copy(AContext.Text, Start + 1, Index - Start);
  end;

  /// <summary>Bereich der ganzen Zeile(n) von AStatement samt folgendem ; und Zeilenende; False, wenn mehr in der
  /// Zeile steht.</summary>
  function WholeLines(AStatement: TSyntaxNode; out AStart, AEnd: Integer): Boolean;
  begin
    AStart := LineStart(AStatement.StartOffset);
    Result := Trim(Copy(AContext.Text, AStart + 1, AStatement.StartOffset - AStart)) = '';
    AEnd := AStatement.EndOffset;
    while (AEnd < Length(AContext.Text)) and CharInSet(AContext.Text[AEnd + 1], [' ', #9]) do
      Inc(AEnd);
    if (AEnd < Length(AContext.Text)) and (AContext.Text[AEnd + 1] = ';') then
      Inc(AEnd);
    while (AEnd < Length(AContext.Text)) and CharInSet(AContext.Text[AEnd + 1], [' ', #9]) do
      Inc(AEnd);
    if (AEnd < Length(AContext.Text)) and (AContext.Text[AEnd + 1] = #13) then
      Inc(AEnd);
    if (AEnd < Length(AContext.Text)) and (AContext.Text[AEnd + 1] = #10) then
      Inc(AEnd)
    else
      Result := False;
  end;

  /// <summary>Lokale Variable ATarget der Routine um ALoop, die vor der Schleife nicht vorkommt?</summary>
  function FreshLocal(ALoop: TSyntaxNode): Boolean;
  var
    Routine, Section, Body: TSyntaxNode;
    Index, Inner: Integer;
    Declared, Used: Boolean;
    Name, Wanted: string;
  begin
    Wanted := Target;
    Routine := ALoop.Parent;
    while (Routine <> nil) and (Routine.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      if Routine.Kind = TSyntaxKind.AnonymousMethod then
        Exit(False);
      Routine := Routine.Parent;
    end;
    if Routine = nil then
      Exit(False);
    Declared := False;
    for Index := 0 to Routine.ChildCount - 1 do
    begin
      Section := Routine[Index];
      if Section.Kind = TSyntaxKind.VarSection then
        for Inner := 0 to Section.ChildCount - 1 do
          for Name in SplitString(Section[Inner].Name, ',') do
            if SameText(Trim(Name), Target) then
              Declared := True;
    end;
    Body := Routine.FindChild(TSyntaxKind.Block);
    if not Declared or (Body = nil) then
      Exit(False);
    Used := False;
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not Used;
        if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.EndOffset <= ALoop.StartOffset) and
          SameText(ANode.Name, Wanted) then
          Used := True;
      end);
    Result := not Used;
  end;

  /// <summary>Text von AFrom bis ATo mit den Ersetzungen in AEdits (Offsets) darin.</summary>
  function Rewrite(AFrom, ATo: Integer; const AReplaced: TArray<TSyntaxNode>; const ANew: string): string;
  var
    Index: Integer;
  begin
    Result := Copy(AContext.Text, AFrom + 1, ATo - AFrom);
    for Index := High(AReplaced) downto 0 do
      if (AReplaced[Index].StartOffset >= AFrom) and (AReplaced[Index].EndOffset <= ATo) then
        Result := Copy(Result, 1, AReplaced[Index].StartOffset - AFrom) + ANew +
          Copy(Result, AReplaced[Index].EndOffset - AFrom + 1, MaxInt);
  end;

  function OnOwnLine(AOffset: Integer): Boolean;
  begin
    Result := Trim(Copy(AContext.Text, LineStart(AOffset) + 1, AOffset - LineStart(AOffset))) = '';
  end;

  /// <summary>Korrektur: Länge vor der Schleife setzen, SetLength entfernen, A[High(A)] durch A[I] ersetzen.
  /// Bleibt im begin … end nur eine Anweisung, entfällt der Block.</summary>
  function CountFix(ALoop, AStatement: TSyntaxNode): TArray<TRuleFix>;
  var
    Body, Other: TSyntaxNode;
    Edits: TArray<TRuleEdit>;
    Replaced: TArray<TSyntaxNode>;
    Safe: Boolean;
    Start, Stop, Index, Remaining: Integer;
    Wanted, Text: string;
  begin
    Result := nil;
    Wanted := Target;
    Text := AContext.Text;
    Body := LoopBody(ALoop);
    if (LoopIndex = '') or (Body = nil) or not FreshLocal(ALoop) or not WholeLines(AStatement, Start, Stop) then
      Exit;
    // Jede andere Stelle mit A im Rumpf muss A[High(A)] bzw. A[Length(A) - 1] sein; Sprünge verkürzen das Array.
    Safe := True;
    Replaced := nil;
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := Safe and (ANode <> AStatement);
        if not Result then
          Exit;
        if (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount = 2) and
          (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, Wanted) and
          IsLastIndex(Text, ANode[1], Wanted) then
        begin
          Replaced := Replaced + [ANode[1]];
          Exit(False);
        end;
        if ((ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, Wanted)) or
          ((ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.CallStatement]) and
          MatchText(ANode.Name, ['Break', 'Continue', 'Exit'])) or (ANode.Kind = TSyntaxKind.GotoStatement) then
          Safe := False;
      end);
    if not Safe or (Replaced = nil) then
      Exit;
    Edits := [TRuleEdit.Create(Range(LineStart(ALoop.StartOffset), LineStart(ALoop.StartOffset)),
      Indent(ALoop.StartOffset) + Format('SetLength(%s, %s);', [Target, Count]) + TTextLines.LineBreakOf(AContext.Text))];
    Remaining := 0;
    Other := nil;
    if Body.Kind = TSyntaxKind.Block then
      for Index := 0 to Body.ChildCount - 1 do
        if Body[Index] <> AStatement then
        begin
          Inc(Remaining);
          Other := Body[Index];
        end;
    if (Remaining = 1) and OnOwnLine(Body.StartOffset) and OnOwnLine(Body.EndOffset - 3) and
      OnOwnLine(Other.StartOffset) and (Other.StartOffset > AStatement.StartOffset) then
      // Die Anweisung steht schon zwei Zeichen tiefer als begin, also dort, wo sie ohne Block hingehört.
      Edits := Edits + [TRuleEdit.Create(Range(LineStart(Body.StartOffset), Body.EndOffset),
        Rewrite(LineStart(Other.StartOffset), Other.EndOffset, Replaced, LoopIndex))]
    else
    begin
      Edits := Edits + [TRuleEdit.Create(Range(Start, Stop), '')];
      for Index := 0 to High(Replaced) do
        Edits := Edits + [TRuleEdit.Create(Range(Replaced[Index].StartOffset, Replaced[Index].EndOffset), LoopIndex)];
    end;
    Result := [TRuleFix.Create(Format('Länge von %s vor der Schleife setzen', [Target]), Edits)];
  end;

begin
  if AContext.Tree = nil then
    Exit;
  // Vorfilter: ohne SetLength keine Arbeit.
  if not ContainsText(AContext.Text, 'SetLength') then
    Exit;
  Calls := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
        (ANode[0].Kind = TSyntaxKind.Call) and SameText(ANode[0].Name, 'SetLength') and (ANode[0].ChildCount = 3) then
        Calls := Calls + [ANode];
    end);
  if Calls = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  ArrayTypes := DynamicArrayTypes(AContext.Text, AContext.Tree.Root);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Statement in Calls do
    begin
      Call := Statement[0];
      if Call[1].Kind <> TSyntaxKind.Identifier then
        Continue;
      Target := Call[1].Name;
      Loop := EnclosingLoop(Statement);
      if (Loop = nil) or not IsGrowth(AContext.Text, Call[2], Target) then
        Continue;
      TypeText := Types.DeclaredType(Target, Call[1].StartPos);
      if (TypeText = '') and SameText(Target, 'Result') then
        TypeText := ResultType(AContext.Text, Statement);
      if not IsDynamicArrayType(TypeText, ArrayTypes) then
        Continue;
      Count := '';
      LoopIndex := '';
      if RunsEveryIteration(Loop, Statement) then
        Count := ForCount(AContext.Text, Loop, LoopIndex);
      if Count <> '' then
      begin
        Fixes := CountFix(Loop, Statement);
        AReport.Add(Range(Statement.StartOffset, Statement.EndOffset), Format('SetLength in der Schleife kopiert ' +
          '%s bei jedem Durchlauf; die Anzahl %s ist vorher bekannt.', [Target, Count]), Fixes);
      end
      else
        AReport.Add(Range(Statement.StartOffset, Statement.EndOffset), Format('SetLength in der Schleife kopiert ' +
          '%s bei jedem Durchlauf; die Länge vor der Schleife setzen oder die Werte in einer TList<T> sammeln.',
          [Target]));
    end;
  finally
    Types.Free;
  end;
end;

{ TManagedParamWithoutConstRule }

const
  ManagedParamRuleId = 'managed-param-without-const';
  StringTypes: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String', 'ShortString');
  KnownInterfaces: array[0..3] of string = ('IInterface', 'IUnknown', 'IDispatch', 'IInvokable');
  /// <summary>Direktiven, bei denen die Signatur von außen vorgegeben ist (Vorfahr, Nachfahren, Aufrufer).</summary>
  FixedSignatureDirectives: array[0..10] of string = ('virtual', 'dynamic', 'abstract', 'message', 'stdcall',
    'cdecl', 'safecall', 'pascal', 'register', 'external', 'export');

type
  TSyntaxKinds = set of TSyntaxKind;

{$SCOPEDENUMS ON}
  /// <summary>Was eine Wertübergabe kostet.</summary>
  TParamCost = (RefCount, Copy);

  /// <summary>Wie die Routine einen Parameter benutzt.</summary>
  TParamAccess = (Read, Modified, Undecided);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Wertparameter, der für const in Frage kommt.</summary>
  TParamCandidate = record
    Name: string;
    Cost: TParamCost;
    /// <summary>Strings, Records, Arrays: Zuweisungen an Teile ändern den Wert (Interfaces: nur das Objekt).
    /// </summary>
    PartsAreValue: Boolean;
    /// <summary>Feldnamen bei Records der Datei; andere Mitglieder (Methoden, Properties) können ändern.</summary>
    Fields: TArray<string>;
    IsRecord: Boolean;
    /// <summary>Parameterknoten (Gruppe) und Stelle des Namens darin.</summary>
    Group: TSyntaxNode;
    Position: Integer;
  end;

/// <summary>Name ohne Typparameter: TListe&lt;T&gt; wird TListe.</summary>
function WithoutTypeParams(const AName: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(AName) do
    if AName[Index] = '<' then
      Inc(Depth)
    else if AName[Index] = '>' then
      Dec(Depth)
    else if Depth = 0 then
      Result := Result + AName[Index];
end;

/// <summary>Quelltext ohne Leerraum, klein geschrieben; für den Vergleich von Parameterlisten.</summary>
function Squeezed(const AText: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 1 to Length(AText) do
    if AText[Index] > ' ' then
      Result := Result + AText[Index];
  Result := LowerCase(Result);
end;

function ParamsText(const AText: string; AHeader: TSyntaxNode): string;
var
  Params: TSyntaxNode;
begin
  Result := '';
  Params := AHeader.FindChild(TSyntaxKind.Parameters);
  if Params <> nil then
    Result := Squeezed(NodeText(AText, Params));
end;

/// <summary>Knoten der Arten AKinds unter ARoot in Baumreihenfolge; Teilbäume der Arten ASkip werden übergangen.
/// </summary>
function NodesOf(ARoot: TSyntaxNode; const AKinds, ASkip: TSyntaxKinds): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind in AKinds then
        Found := Found + [ANode];
      Result := (ANode = ARoot) or not (ANode.Kind in ASkip);
    end);
  Result := Found;
end;

/// <summary>Kopf der Deklaration zum Rumpf ARoutine: die Methode in ihrer Klasse bzw. die Routine im interface
/// oder als forward, mit gleicher Parameterliste. nil ohne eigene Deklaration. AFound False, wenn eine Methode
/// ihre Klasse nicht findet (dann ist nichts sicher). AVisibility: Abschnitt in der Klasse ('' = ohne Angabe);
/// AClass: Typknoten der Klasse bzw. nil.</summary>
function DeclarationOf(const AText: string; ARoot, ARoutine: TSyntaxNode; out AFound: Boolean;
  out AVisibility: string; out AClass: TSyntaxNode): TSyntaxNode;
var
  Header, Container, Member: TSyntaxNode;
  TypeName, Name, Params, Section: string;
  Candidates: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, Matches: Integer;
begin
  Result := nil;
  AFound := True;
  AVisibility := '';
  AClass := nil;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (Header = nil) or ((ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.RoutineDecl)) then
    Exit;
  Name := Header.Name;
  TypeName := '';
  if Pos('.', Name) > 0 then
  begin
    TypeName := WithoutTypeParams(Copy(Name, 1, LastDelimiter('.', Name) - 1));
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  Params := ParamsText(AText, Header);
  Matches := 0;
  if TypeName <> '' then
  begin
    for Node in NodesOf(ARoot, [TSyntaxKind.TypeDecl], [TSyntaxKind.Block, TSyntaxKind.RoutineDecl]) do
      if SameText(WithoutTypeParams(Node.Name), TypeName) and (Node.ChildCount > 0) then
      begin
        Container := Node[Node.ChildCount - 1];
        Section := '';
        for Index := 0 to Container.ChildCount - 1 do
        begin
          Member := Container[Index];
          if Member.Kind = TSyntaxKind.Visibility then
            Section := LowerCase(Member.Name)
          else if (Member.Kind = TSyntaxKind.RoutineHeader) and SameText(Member.Name, Name) then
          begin
            Inc(Matches);
            if (Params = '') or (ParamsText(AText, Member) = Params) then
            begin
              Result := Member;
              AVisibility := Section;
              AClass := Container;
            end;
          end;
        end;
      end;
    // Ohne Parameterliste im Rumpf ist die Überladung nicht eindeutig.
    AFound := (Result <> nil) and ((Params <> '') or (Matches = 1));
    if not AFound then
      Result := nil;
    Exit;
  end;
  Candidates := NodesOf(ARoot, [TSyntaxKind.RoutineDecl], [TSyntaxKind.Block, TSyntaxKind.RoutineDecl,
    TSyntaxKind.TypeDecl]);
  for Node in Candidates do
    if (Node <> ARoutine) and (Node.FindChild(TSyntaxKind.Block) = nil) and (Node.ChildCount > 0) and
      (Node[0].Kind = TSyntaxKind.RoutineHeader) and SameText(Node[0].Name, Name) and
      (Node[0].StartOffset < Header.StartOffset) then
    begin
      Inc(Matches);
      if (Params = '') or (ParamsText(AText, Node[0]) = Params) then
        Result := Node[0];
    end;
  if (Result <> nil) and (Params = '') and (Matches > 1) then
  begin
    AFound := False;
    Result := nil;
  end;
end;

function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  Index: Integer;
begin
  if AHeader <> nil then
    for Index := 0 to AHeader.ChildCount - 1 do
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ANames) then
        Exit(True);
  Result := False;
end;

function RecordSize(const AText: string; ARecord: TSyntaxNode; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer; forward;

/// <summary>Größe eines Typs in Byte als Untergrenze (Win64, ohne Ausrichtung); -1 = unbekannt. ARecords: Records
/// der Datei nach Namen (klein); ADepth schützt vor Zyklen.</summary>
function TypeSize(const AText, ATypeName: string; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer;
const
  Sizes: array[0..30] of string = ('Byte=1', 'Boolean=1', 'ByteBool=1', 'AnsiChar=1', 'ShortInt=1', 'Int8=1',
    'UInt8=1', 'Word=2', 'SmallInt=2', 'Char=2', 'WideChar=2', 'WordBool=2', 'Int16=2', 'UInt16=2', 'Integer=4',
    'Cardinal=4', 'LongInt=4', 'LongWord=4', 'Single=4', 'LongBool=4', 'Int32=4', 'UInt32=4', 'Int64=8',
    'UInt64=8', 'Double=8', 'Currency=8', 'TDateTime=8', 'Comp=8', 'Extended=8', 'TDate=8', 'TTime=8');
  Pointers: array[0..7] of string = ('Pointer', 'NativeInt', 'NativeUInt', 'string', 'UnicodeString', 'TObject',
    'PChar', 'IInterface');
var
  Item: string;
  Node: TSyntaxNode;
begin
  Result := -1;
  for Item in Sizes do
    if SameText(Copy(Item, 1, Pos('=', Item) - 1), ATypeName) then
      Exit(StrToInt(Copy(Item, Pos('=', Item) + 1, MaxInt)));
  if MatchText(ATypeName, Pointers) or StartsText('TArray<', ATypeName) then
    Exit(8);
  if (ADepth < 4) and ARecords.TryGetValue(LowerCase(ATypeName), Node) then
    Result := RecordSize(AText, Node, ARecords, ADepth + 1);
end;

/// <summary>Summe der Feldgrößen eines Records der Datei; -1, wenn ein Feld unbekannt ist.</summary>
function RecordSize(const AText: string; ARecord: TSyntaxNode; const ARecords: TDictionary<string, TSyntaxNode>;
  ADepth: Integer): Integer;
var
  Index, Size, Count, LowBound, HighBound: Integer;
  Field, TypeNode, Bounds: TSyntaxNode;
begin
  Result := 0;
  for Index := 0 to ARecord.ChildCount - 1 do
  begin
    Field := ARecord[Index];
    if Field.Kind = TSyntaxKind.VariantPart then
      Exit(-1);
    if Field.Kind <> TSyntaxKind.Field then
      Continue;
    if Field.ChildCount = 0 then
      Exit(-1);
    TypeNode := Field[0];
    Count := 1;
    if TypeNode.Kind = TSyntaxKind.ArrayType then
    begin
      // array[A..B] of T mit Zahlen als Grenzen
      Bounds := TypeNode.FindChild(TSyntaxKind.SubrangeType);
      if (Bounds = nil) or (Bounds.ChildCount <> 2) or not TryStrToInt(Bounds[0].Name, LowBound) or
        not TryStrToInt(Bounds[1].Name, HighBound) or
        (TypeNode[TypeNode.ChildCount - 1].Kind <> TSyntaxKind.TypeReference) then
        Exit(-1);
      Count := HighBound - LowBound + 1;
      TypeNode := TypeNode[TypeNode.ChildCount - 1];
    end;
    if TypeNode.Kind <> TSyntaxKind.TypeReference then
      Exit(-1);
    Size := TypeSize(AText, Trim(NodeText(AText, TypeNode)), ARecords, ADepth);
    if Size < 0 then
      Exit(-1);
    Inc(Result, Size * Count * Length(Field.Name.Split([','])));
  end;
end;

/// <summary>Feldnamen eines Records (Gruppen aufgeteilt).</summary>
function RecordFields(ARecord: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ARecord.ChildCount - 1 do
    if ARecord[Index].Kind = TSyntaxKind.Field then
      for Name in ARecord[Index].Name.Split([',']) do
        Result := Result + [Trim(Name)];
end;

/// <summary>Wie ANode (Bezeichner des Parameters) den Parameter benutzt. Undecided mit ACall: Argument eines
/// Aufrufs, dessen Signatur ALookup nicht kennt; AArgument ist die Stelle (ab 0).</summary>
function ParamAccess(ANode: TSyntaxNode; const ACandidate: TParamCandidate; const ALookup: TFlowSignatureLookup;
  out ACall: TSyntaxNode; out AArgument: Integer): TParamAccess;
var
  Node, Top, Parent: TSyntaxNode;
  Index: Integer;
  Mode: TFlowArgumentMode;
begin
  ACall := nil;
  AArgument := -1;
  Node := ANode.Parent;
  while (Node <> nil) and (Node.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    // Anonyme Methoden fangen den Parameter ein; with-Ausdrücke binden ihn für den Rumpf.
    if Node.Kind = TSyntaxKind.AnonymousMethod then
      Exit(TParamAccess.Undecided);
    if (Node.Kind = TSyntaxKind.WithStatement) and (Node.ChildCount > 1) and
      (ANode.StartOffset < Node[Node.ChildCount - 1].StartOffset) then
      Exit(TParamAccess.Undecided);
    Node := Node.Parent;
  end;
  Parent := ANode.Parent;
  if Parent.Kind = TSyntaxKind.AddressOf then
    Exit(TParamAccess.Modified);
  // Bei Records nur Felder; Methoden und Properties können den Wert ändern.
  if ACandidate.IsRecord and (Parent.Kind = TSyntaxKind.MemberAccess) and (Parent[0] = ANode) and
    not MatchText(Parent.Name, ACandidate.Fields) then
    Exit(TParamAccess.Modified);
  Top := ANode;
  while (Top.Parent <> nil) and (Top.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Top.Parent[0] = Top) do
    Top := Top.Parent;
  Parent := Top.Parent;
  Result := TParamAccess.Read;
  if Parent = nil then
    Exit;
  if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Top) then
  begin
    if (Top = ANode) or ACandidate.PartsAreValue then
      Result := TParamAccess.Modified;
    Exit;
  end;
  // Methode eines Feldes: Kunde.Adresse.Leeren
  if ACandidate.IsRecord and (Top <> ANode) and ((Parent.Kind = TSyntaxKind.CallStatement) or
    ((Parent.Kind = TSyntaxKind.Call) and (Parent[0] = Top))) then
    Exit(TParamAccess.Modified);
  if (Parent.Kind = TSyntaxKind.Call) and (Parent[0] <> Top) then
  begin
    Index := 0;
    while (Index < Parent.ChildCount) and (Parent[Index] <> Top) do
      Inc(Index);
    Mode := TFlowArgumentMode.Unknown;
    if Assigned(ALookup) then
      Mode := ALookup(Parent, Index - 1);
    case Mode of
      TFlowArgumentMode.Value:
        Result := TParamAccess.Read;
      TFlowArgumentMode.Reference, TFlowArgumentMode.Output:
        if (Top = ANode) or ACandidate.PartsAreValue then
          Result := TParamAccess.Modified;
    else
      Result := TParamAccess.Undecided;
      ACall := Parent;
      AArgument := Index - 1;
      // Ein Teil (A[I], Intf.Wert) ändert an einem var-Parameter den Wert nicht, wenn Teile keine Werte sind.
      if (Top <> ANode) and not ACandidate.PartsAreValue then
        Result := TParamAccess.Read;
    end;
  end;
end;

function TManagedParamWithoutConstRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ManagedParamRuleId, TRuleSeverity.Hint,
    'String-, Interface-, Array- oder Record-Parameter ohne const wird nicht verändert', True);
end;

procedure TManagedParamWithoutConstRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Lookup: TFlowSignatureLookup;
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  Records: TDictionary<string, TSyntaxNode>;
  Interfaces, DynArrays, Exported: TArray<string>;
  MinRecordSize: Integer;
  IgnoreOverrides: Boolean;
  Root: TSyntaxNode;

  function Range(AStart, AEnd: Integer): TTextRange;
  begin
    Result := TRuleDerived.OffsetRange(Cache, AContext, AStart, AEnd);
  end;

  /// <summary>Übergabeart über die Namensauflösung (Methoden, Routinen anderer Units, Typumwandlungen).</summary>
  function ResolvedMode(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;
  begin
    if (Resolver = nil) and (AContext.Index <> nil) then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      mCache := TRuleDerived.Open(AContext);
      Resolver := TRuleDerived.Resolver(mCache, AContext);
    end;
    Result := TResolvedSignatures.Mode(Resolver, AContext.Tree, AContext.RelativePath, ACall, AArgument);
  end;

  function CandidateOf(AGroup: TSyntaxNode; APosition: Integer; out ACandidate: TParamCandidate): Boolean;
  var
    TypeText: string;
    Node: TSyntaxNode;
    Size: Integer;
  begin
    Result := False;
    ACandidate := Default(TParamCandidate);
    if (AGroup.Modifier <> TParameterModifier.None) or (AGroup.ChildCount = 0) then
      Exit;
    TypeText := Trim(NodeText(AContext.Text, AGroup[0]));
    ACandidate.Name := Trim(AGroup.Name.Split([','])[APosition]);
    ACandidate.Group := AGroup;
    ACandidate.Position := APosition;
    if MatchText(TypeText, StringTypes) then
    begin
      ACandidate.PartsAreValue := True;
      if SameText(TypeText, 'ShortString') then
        ACandidate.Cost := TParamCost.Copy;
      Exit(True);
    end;
    if MatchText(TypeText, Interfaces) or MatchText(TypeText, KnownInterfaces) then
      Exit(True);
    if StartsText('array of ', TypeText) then
    begin
      if SameText(Trim(Copy(TypeText, 10, MaxInt)), 'const') then
        Exit;
      ACandidate.Cost := TParamCost.Copy;
      ACandidate.PartsAreValue := True;
      Exit(True);
    end;
    // Elemente eines const-Arrays lassen sich zwar schreiben, das ändert aber den Wert des Aufrufers.
    if IsDynamicArrayType(TypeText, DynArrays) then
    begin
      ACandidate.PartsAreValue := True;
      Exit(True);
    end;
    if Records.TryGetValue(LowerCase(TypeText), Node) then
    begin
      Size := RecordSize(AContext.Text, Node, Records, 0);
      if (Size >= 0) and (Size >= MinRecordSize) then
      begin
        ACandidate.Cost := TParamCost.Copy;
        ACandidate.PartsAreValue := True;
        ACandidate.IsRecord := True;
        ACandidate.Fields := RecordFields(Node);
        Result := True;
      end;
    end;
  end;

  /// <summary>Routine wird als Wert benutzt (Methodenzeiger, @Routine, Formular, exports).</summary>
  function UsedAsValue(const AName: string): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := MatchText(AName, Exported) or
      ((AContext.FormText <> '') and TRegEx.IsMatch(AContext.FormText, '\b' + AName + '\b', [roIgnoreCase]));
    if Result then
      Exit;
    for Node in NodesOf(Root, [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess], []) do
      if SameText(Node.Name, AName) and (Node.Parent <> nil) and not ((Node.Parent.Kind = TSyntaxKind.Call) and
        (Node.Parent[0] = Node)) and (Node.Parent.Kind <> TSyntaxKind.CallStatement) then
        Exit(True);
  end;

  /// <summary>Text der Gruppe mit const vor den Namen in AConst (Stellen); Gruppen werden bei Bedarf geteilt.
  /// </summary>
  function GroupEdit(AGroup: TSyntaxNode; const AConst: TArray<Boolean>): TRuleEdit;
  var
    Names: TArray<string>;
    Text, TypeText, Part: string;
    Index: Integer;
    All: Boolean;
  begin
    Names := AGroup.Name.Split([',']);
    All := True;
    for Index := 0 to High(AConst) do
      All := All and AConst[Index];
    if All then
      Exit(TRuleEdit.Create(Range(AGroup.StartOffset, AGroup.StartOffset), 'const '));
    Text := NodeText(AContext.Text, AGroup);
    TypeText := Trim(Copy(Text, Pos(':', Text) + 1, MaxInt));
    Text := '';
    for Index := 0 to High(Names) do
    begin
      Part := Trim(Names[Index]) + ': ' + TypeText;
      if AConst[Index] then
        Part := 'const ' + Part;
      if Text <> '' then
        Text := Text + '; ';
      Text := Text + Part;
    end;
    Result := TRuleEdit.Create(Range(AGroup.StartOffset, AGroup.EndOffset), Text);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Header, Declaration, ClassNode, Params, DeclParams, Group, Node, Call: TSyntaxNode;
    Visibility, Name, ShortName, Subject, Costs: string;
    Found, IsOverride, HasRefCount, HasCopy: Boolean;
    Candidates, Unchanged: TArray<TParamCandidate>;
    Candidate: TParamCandidate;
    Usages, Declared: TArray<TSyntaxNode>;
    Index, Position, Argument: Integer;
    Access: TParamAccess;
    Names: TArray<string>;
    Marks: TArray<Boolean>;
    Edits: TArray<TRuleEdit>;
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header = nil) or (NodesOf(ARoutine, [TSyntaxKind.AsmBlock, TSyntaxKind.Error], []) <> nil) or
      ContainsText(NodeText(AContext.Text, Header), '{$') then
      Exit;
    Declaration := DeclarationOf(AContext.Text, Root, ARoutine, Found, Visibility, ClassNode);
    if not Found then
      Exit;
    IsOverride := HasDirective(Header, ['override']) or HasDirective(Declaration, ['override']);
    if HasDirective(Header, FixedSignatureDirectives) or HasDirective(Declaration, FixedSignatureDirectives) or
      (IsOverride and IgnoreOverrides) then
      Exit;
    if ClassNode <> nil then
    begin
      // Interfaces geben die Signatur vor; published (auch ohne Abschnitt bei Vorfahren) heißt Formular-Ereignis.
      if (ClassNode.Kind = TSyntaxKind.ClassType) and ((Length(NodesOf(ClassNode, [TSyntaxKind.TypeReference],
        [TSyntaxKind.RoutineHeader, TSyntaxKind.Field, TSyntaxKind.PropertyDecl])) > 1) or
        (Visibility = 'published') or ((Visibility = '') and (ClassNode.FindChild(TSyntaxKind.TypeReference) <> nil)))
        then
        Exit;
    end;
    Name := Header.Name;
    ShortName := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
    if UsedAsValue(ShortName) then
      Exit;
    // Bare inherited reicht alle Parameter weiter.
    for Node in NodesOf(ARoutine, [TSyntaxKind.InheritedExpr], [TSyntaxKind.RoutineHeader]) do
      if (Node.Name = '') and (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.CallStatement) then
        Exit;
    Params := Header.FindChild(TSyntaxKind.Parameters);
    DeclParams := nil;
    if Declaration <> nil then
      DeclParams := Declaration.FindChild(TSyntaxKind.Parameters);
    if Params = nil then
      Params := DeclParams;
    if Params = nil then
      Exit;
    Candidates := nil;
    for Index := 0 to Params.ChildCount - 1 do
    begin
      Group := Params[Index];
      if Group.Kind <> TSyntaxKind.Parameter then
        Continue;
      for Position := 0 to High(Group.Name.Split([','])) do
        if CandidateOf(Group, Position, Candidate) then
          Candidates := Candidates + [Candidate];
    end;
    if Candidates = nil then
      Exit;
    Usages := nil;
    Declared := nil;
    for Index := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Index] <> Header then
      begin
        Usages := Usages + NodesOf(ARoutine[Index], [TSyntaxKind.Identifier], []);
        Declared := Declared + NodesOf(ARoutine[Index], [TSyntaxKind.Parameter, TSyntaxKind.VarDecl,
          TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.ForStatement,
          TSyntaxKind.ForInStatement], []);
      end;
    Unchanged := nil;
    for Candidate in Candidates do
    begin
      Access := TParamAccess.Read;
      // Gleichnamige Deklarationen darunter verdecken den Parameter; for-Variable heißt verändert.
      for Node in Declared do
        if MatchText(Candidate.Name, Node.Name.Split([',', ' '])) then
          Access := TParamAccess.Modified;
      for Node in Usages do
      begin
        if Access <> TParamAccess.Read then
          Break;
        if not SameText(Node.Name, Candidate.Name) then
          Continue;
        Access := ParamAccess(Node, Candidate, Lookup, Call, Argument);
        if (Access = TParamAccess.Undecided) and (Call <> nil) then
          case ResolvedMode(Call, Argument) of
            TFlowArgumentMode.Value:
              Access := TParamAccess.Read;
            TFlowArgumentMode.Reference, TFlowArgumentMode.Output:
              Access := TParamAccess.Modified;
          end;
      end;
      if Access = TParamAccess.Read then
        Unchanged := Unchanged + [Candidate];
    end;
    if Unchanged = nil then
      Exit;
    Names := nil;
    HasRefCount := False;
    HasCopy := False;
    for Candidate in Unchanged do
    begin
      Names := Names + [Candidate.Name];
      HasRefCount := HasRefCount or (Candidate.Cost = TParamCost.RefCount);
      HasCopy := HasCopy or (Candidate.Cost = TParamCost.Copy);
    end;
    if Length(Names) = 1 then
      Subject := Names[0] + ' wird'
    else
      Subject := string.Join(', ', Copy(Names, 0, Length(Names) - 1)) + ' und ' + Names[High(Names)] + ' werden';
    if HasRefCount and HasCopy then
      Costs := 'entfallen Referenzzählung und Kopie'
    else if HasRefCount then
      Costs := 'entfällt die Referenzzählung'
    else
      Costs := 'entfällt die Kopie';
    Edits := nil;
    if not IsOverride then
      for Index := 0 to Params.ChildCount - 1 do
      begin
        Group := Params[Index];
        Marks := nil;
        SetLength(Marks, Length(Group.Name.Split([','])));
        Found := False;
        for Candidate in Unchanged do
          if Candidate.Group = Group then
          begin
            Marks[Candidate.Position] := True;
            Found := True;
          end;
        if not Found then
          Continue;
        if Params <> DeclParams then
          Edits := Edits + [GroupEdit(Group, Marks)];
        // Gleiche Parameterliste: die Gruppe steht an derselben Stelle.
        if (DeclParams <> nil) and (Index < DeclParams.ChildCount) then
          Edits := Edits + [GroupEdit(DeclParams[Index], Marks)];
      end;
    if Edits <> nil then
      AReport.Add(Range(Params.StartOffset, Params.EndOffset), Format('%s nicht verändert; mit const %s.',
        [Subject, Costs]), [TRuleFix.Create('const ergänzen', Edits)])
    else
      AReport.Add(Range(Params.StartOffset, Params.EndOffset), Format('%s nicht verändert; mit const %s ' +
        '(override: die Signatur des Vorfahren mit ändern).', [Subject, Costs]));
  end;

var
  Node: TSyntaxNode;
  Routine: TSyntaxNode;
  Name: string;
begin
  if AContext.Tree = nil then
    Exit;
  Root := AContext.Tree.Root;
  MinRecordSize := TRuleOptions.Int(AContext.Options, 'minRecordSize', 16);
  IgnoreOverrides := TRuleOptions.Bool(AContext.Options, 'ignoreOverrides', True);
  Cache := TRuleDerived.Open(AContext);
  Lookup := TRuleDerived.FlowSignatures(Cache, AContext);
  DynArrays := DynamicArrayTypes(AContext.Text, Root);
  Interfaces := nil;
  Exported := nil;
  Resolver := nil;
  Records := TDictionary<string, TSyntaxNode>.Create;
  try
    for Node in NodesOf(Root, [TSyntaxKind.TypeDecl, TSyntaxKind.ExportsClause], [TSyntaxKind.Block]) do
      if Node.Kind = TSyntaxKind.ExportsClause then
      begin
        for Name in TRegEx.Split(NodeText(AContext.Text, Node), '[^A-Za-z0-9_]+') do
          if Name <> '' then
            Exported := Exported + [Name];
      end
      else if Node.ChildCount > 0 then
        case Node[Node.ChildCount - 1].Kind of
          TSyntaxKind.InterfaceType:
            Interfaces := Interfaces + [Node.Name];
          TSyntaxKind.RecordType:
            Records.AddOrSetValue(LowerCase(Node.Name), Node[Node.ChildCount - 1]);
        end;
    for Routine in TRuleDerived.Routines(Cache, AContext) do
      CheckRoutine(Routine);
  finally
    Records.Free;
  end;
end;

procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringConcatInLoopRule.Create);
  ARegistry.Register(TLoopInvariantCallRule.Create);
  ARegistry.Register(TMissingBeginUpdateRule.Create);
  ARegistry.Register(TSetLengthInLoopRule.Create);
  ARegistry.Register(TManagedParamWithoutConstRule.Create);
end;

end.
