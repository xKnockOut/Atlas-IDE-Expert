unit Atlas.Common.Rules.Builtin.RtlTypePatterns;

// Regeln für fehleranfällige RTL-Muster, Stufe 2 aus #153 (mit deklarierten
// Typen aus der Datei, Atlas.Common.Pascal.DeclaredTypes):
//   int32-mul-overflow       Int64 := Int32 * Int32 läuft vor der Zuweisung über
//   sizeof-pointer           Move/FillChar mit SizeOf eines Zeigers, Strings oder dynamischen Arrays
//   char-to-pchar            Cast eines Char nach PChar
//   float-equality           Gleitkommavergleich mit = oder <> (nicht mit 0)
//   constructor-on-instance  Konstruktor auf einer Variablen statt auf der Klasse
//   format-without-settings  Format mit %f/%n/%m/%g/%e, FloatToStr, StrToDate … ohne TFormatSettings
//   managed-type-raw-memory  FillChar, ZeroMemory, Move, CopyMemory, GetMem oder FreeMem auf Variablen,
//                            deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält
//                            (#921). Records und Aliasse werden in der Datei und im Index aufgelöst.
//   threadvar-managed        threadvar mit verwaltetem Typ: Delphi finalisiert ihn am Thread-Ende
//                            nicht (#922)
//   pchar-of-temporary       PChar(S + '.bak'), PChar(IntToStr(N)) … in einer Variablen, einem Feld oder
//                            Result gemerkt bzw. an PostMessage übergeben (#923): der temporäre String
//                            ist nach der Anweisung weg
//   stringlist-unsorted      Find oder Duplicates := dupIgnore/dupError auf einer TStringList, die in der
//                            Datei erzeugt, aber nie sortiert wird (#925)
//   writeln-in-gui-app       Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem
//                            Programm ohne Konsole (#926): E/A-Fehler 104 bzw. 105 zur Laufzeit
//   unchecked-conversion     StrToInt, StrToFloat, StrToDate … direkt auf Edit.Text, Cells[…] oder Lines[…]
//                            ohne umgebendes try/except (#932); Korrektur: TryStrToInt … mit raise im
//                            Fehlerzweig, wenn das Ziel eine Variable des passenden Typs ist
// Bezeichner, deren Typ in der Datei nicht deklariert ist, lösen keinen Treffer aus.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TInt32MulOverflowRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSizeOfPointerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCharToPCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFloatEqualityRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConstructorOnInstanceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormatWithoutSettingsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Enthält AFormat einen vom Gebietsschema abhängigen Platzhalter (%f, %n, %m, %g, %e)?</summary>
    class function HasLocaleSpecifier(const AFormat: string): Boolean; static;
  end;

  TManagedTypeRawMemoryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TThreadvarManagedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPCharOfTemporaryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TStringListUnsortedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TWritelnInGuiAppRule = class(TInterfacedObject, IRule)
  public const
    DefaultReplacement = 'OutputDebugString';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Anwendungsart aus DCC_ConsoleTarget der .dproj und dem Text der .dpr: Console bei
    /// "true" oder {$APPTYPE CONSOLE}, Gui bei einem program ohne Konsole, sonst Unknown
    /// (library, package, kein Text).</summary>
    class function ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind; static;
    /// <summary>Option "replacement" aus den Regeloptionen; ohne Angabe OutputDebugString.</summary>
    class function Replacement(const AOptions: string): string; static;
  end;

  TUncheckedConversionRule = class(TInterfacedObject, IRule)
  public const
    DefaultFunctions: array[0..5] of string = ('StrToInt', 'StrToInt64', 'StrToFloat', 'StrToDate', 'StrToDateTime',
      'StrToCurr');
    DefaultSources: array[0..2] of string = ('Text', 'Cells', 'Lines');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die typbasierten Regeln für RTL-Muster.</summary>
procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines;

type
  TTokens = TArray<TPascalToken>;

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

/// <summary>Zahl der Argumente auf oberster Ebene zwischen AOpen und AClose.</summary>
function ArgumentCount(const ATokens: TTokens; AOpen, AClose: Integer): Integer;
var
  Index, Depth: Integer;
begin
  if NextCode(ATokens, AOpen + 1) = AClose then
    Exit(0);
  Result := 1;
  Depth := 0;
  for Index := AOpen + 1 to AClose - 1 do
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and ATokens[Index].IsSymbol(',') then
      Inc(Result);
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  Prev, Next: Integer;
begin
  if (AIndex < 0) or (AIndex > High(ATokens)) or (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) then
    Exit(False);
  Prev := PreviousCode(ATokens, AIndex);
  Next := NextCode(ATokens, AIndex + 1);
  Result := not ((Prev >= 0) and (ATokens[Prev].IsSymbol('.') or ATokens[Prev].IsSymbol('@'))) and
    not ((Next <= High(ATokens)) and (ATokens[Next].IsSymbol('.') or ATokens[Next].IsSymbol('(') or
    ATokens[Next].IsSymbol('[') or ATokens[Next].IsSymbol('^')));
end;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;

  function Search(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.Kind = TSyntaxKind.Block) and
        ((Child.StartPos.Line < APosition.Line) or ((Child.StartPos.Line = APosition.Line) and
        (Child.StartPos.Character <= APosition.Character))) and
        ((Child.EndPos.Line > APosition.Line) or ((Child.EndPos.Line = APosition.Line) and
        (Child.EndPos.Character > APosition.Character))) then
        Exit(True);
      if Search(Child) then
        Exit(True);
    end;
    Result := False;
  end;

begin
  Result := (ATree.Root <> nil) and Search(ATree.Root);
end;

{ TInt32MulOverflowRule }

function TInt32MulOverflowRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('int32-mul-overflow', TRuleSeverity.Warning,
    'Int32-Multiplikation läuft vor der Zuweisung an Int64 über');
end;

procedure TInt32MulOverflowRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Target, Left, Times, Right, Stop: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      // V := A * B; mit V: Int64 und A, B höchstens 32 Bit.
      if not Tokens[Index].IsSymbol(':=') then
        Continue;
      Target := PreviousCode(Tokens, Index);
      Left := NextCode(Tokens, Index + 1);
      Times := NextCode(Tokens, Left + 1);
      Right := NextCode(Tokens, Times + 1);
      Stop := NextCode(Tokens, Right + 1);
      if (Stop > High(Tokens)) or not Tokens[Times].IsSymbol('*') or not IsPlainIdentifier(Tokens, Target) or
        not IsPlainIdentifier(Tokens, Left) or not (IsPlainIdentifier(Tokens, Right) or
        (Tokens[Right].Kind = TPascalTokenKind.Number)) or
        not (Tokens[Stop].IsSymbol(';') or Tokens[Stop].IsKeyword('end') or Tokens[Stop].IsKeyword('else')) then
        Continue;
      if not TDeclaredTypes.IsInt64(Types.DeclaredType(Tokens[Target].Text, Tokens[Target].StartPos)) or
        not TDeclaredTypes.IsInt32(Types.DeclaredType(Tokens[Left].Text, Tokens[Left].StartPos)) or
        not ((Tokens[Right].Kind = TPascalTokenKind.Number) or
        TDeclaredTypes.IsInt32(Types.DeclaredType(Tokens[Right].Text, Tokens[Right].StartPos))) then
        Continue;
      AReport.Add(RangeOf(Tokens, Left, Right), Format('%s * %s wird in 32 Bit gerechnet und läuft über, bevor ' +
        'das Ergebnis in %s (Int64) landet', [Tokens[Left].Text, Tokens[Right].Text, Tokens[Target].Text]),
        TRuleConfidence.High, [TRuleFix.Create('Operand nach Int64 umwandeln',
        [TRuleEdit.Create(RangeOf(Tokens, Left, Left), 'Int64(' + Tokens[Left].Text + ')')], True)]);
    end;
  finally
    Types.Free;
  end;
end;

{ TSizeOfPointerRule }

function TSizeOfPointerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('sizeof-pointer', TRuleSeverity.Error,
    'Move/FillChar mit SizeOf eines Zeigers statt der Daten');
end;

procedure TSizeOfPointerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Open, Close, Inner, SizeOpen, Name, SizeClose: Integer;
  TypeName: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(Tokens[Index].Text, ['Move', 'FillChar', 'ZeroMemory', 'CopyMemory', 'FillMemory'])) then
        Continue;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
        Continue;
      Close := Closing(Tokens, Open);
      for Inner := Open + 1 to Close - 1 do
      begin
        if not SameText(Tokens[Inner].Text, 'SizeOf') then
          Continue;
        SizeOpen := NextCode(Tokens, Inner + 1);
        Name := NextCode(Tokens, SizeOpen + 1);
        SizeClose := NextCode(Tokens, Name + 1);
        if (SizeClose >= Close) or not Tokens[SizeOpen].IsSymbol('(') or not Tokens[SizeClose].IsSymbol(')') or
          (Tokens[Name].Kind <> TPascalTokenKind.Identifier) then
          Continue;
        TypeName := Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos);
        if (TypeName <> '') and TDeclaredTypes.IsReference(TypeName) then
          AReport.Add(RangeOf(Tokens, Inner, SizeClose), Format('SizeOf(%s) ist die Größe des Zeigers (%s), ' +
            'nicht die der Daten; Length(…) * SizeOf(Element) verwenden', [Tokens[Name].Text, TypeName]),
            TRuleConfidence.High);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TCharToPCharRule }

function TCharToPCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('char-to-pchar', TRuleSeverity.Error, 'Char wird nach PChar umgewandelt');
end;

procedure TCharToPCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Open, Name, Close: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(Tokens[Index].Text, ['PChar', 'PWideChar', 'PAnsiChar'])) then
        Continue;
      Open := NextCode(Tokens, Index + 1);
      Name := NextCode(Tokens, Open + 1);
      Close := NextCode(Tokens, Name + 1);
      if (Close > High(Tokens)) or not Tokens[Open].IsSymbol('(') or not Tokens[Close].IsSymbol(')') or
        (Tokens[Name].Kind <> TPascalTokenKind.Identifier) then
        Continue;
      if TDeclaredTypes.IsChar(Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos)) then
        AReport.Add(RangeOf(Tokens, Index, Close), Format('%s(%s) macht aus dem Zeichen eine Adresse; ' +
          'gemeint ist meist ein String: %s(string(%s))', [Tokens[Index].Text, Tokens[Name].Text,
          Tokens[Index].Text, Tokens[Name].Text]), TRuleConfidence.High);
    end;
  finally
    Types.Free;
  end;
end;

{ TFloatEqualityRule }

function TFloatEqualityRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('float-equality', TRuleSeverity.Hint, 'Gleitkommavergleich mit = oder <>');
end;

function IsZero(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Number) and MatchStr(AToken.Text, ['0', '0.0', '0.00']);
end;

/// <summary>Gleitkommatyp, für den ein exakter Vergleich verdächtig ist. Datum und Uhrzeit nicht: Zeitstempel
/// (z. B. Dateizeiten) werden absichtlich exakt verglichen (#647).</summary>
function IsInexact(const AType: string): Boolean;
begin
  Result := TDeclaredTypes.IsFloat(AType) and not MatchText(AType, ['TDateTime', 'TDate', 'TTime']);
end;

procedure TFloatEqualityRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Left, Right, Prev, Next: Integer;
  IsFloat: Boolean;
  Call: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not (Tokens[Index].IsSymbol('=') or Tokens[Index].IsSymbol('<>')) then
        Continue;
      Left := PreviousCode(Tokens, Index);
      Right := NextCode(Tokens, Index + 1);
      if (Left < 0) or (Right > High(Tokens)) or not InStatements(AContext.Tree, Tokens[Index].StartPos) then
        Continue;
      // Nur einfache Operanden: A = B, A <> 1.5; nicht Teil eines größeren Ausdrucks davor oder danach.
      Prev := PreviousCode(Tokens, Left);
      Next := NextCode(Tokens, Right + 1);
      if not ((Tokens[Left].Kind = TPascalTokenKind.Number) or IsPlainIdentifier(Tokens, Left)) or
        not ((Tokens[Right].Kind = TPascalTokenKind.Number) or IsPlainIdentifier(Tokens, Right)) or
        ((Prev >= 0) and (Tokens[Prev].Kind = TPascalTokenKind.Symbol) and
        MatchStr(Tokens[Prev].Text, ['+', '-', '*', '/'])) or
        ((Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Symbol) and
        MatchStr(Tokens[Next].Text, ['+', '-', '*', '/'])) or IsZero(Tokens[Left]) or IsZero(Tokens[Right]) then
        Continue;
      IsFloat := ((Tokens[Left].Kind = TPascalTokenKind.Identifier) and
        IsInexact(Types.DeclaredType(Tokens[Left].Text, Tokens[Left].StartPos))) or
        ((Tokens[Right].Kind = TPascalTokenKind.Identifier) and
        IsInexact(Types.DeclaredType(Tokens[Right].Text, Tokens[Right].StartPos)));
      if not IsFloat then
        Continue;
      Call := 'SameValue(' + Tokens[Left].Text + ', ' + Tokens[Right].Text + ')';
      if Tokens[Index].IsSymbol('<>') then
        Call := 'not ' + Call;
      AReport.Add(RangeOf(Tokens, Left, Right), 'Gleitkommawerte sind selten exakt gleich; SameValue aus ' +
        'System.Math mit Toleranz verwenden', TRuleConfidence.Medium,
        [TRuleFix.Create('SameValue verwenden', [TRuleEdit.Create(RangeOf(Tokens, Left, Right), Call)])]);
    end;
  finally
    Types.Free;
  end;
end;

{ TConstructorOnInstanceRule }

function TConstructorOnInstanceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('constructor-on-instance', TRuleSeverity.Warning,
    'Konstruktor auf einer Instanz statt auf der Klasse');
end;

procedure TConstructorOnInstanceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Dot, Ctor, Prev: Integer;
  TypeName: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Prev := PreviousCode(Tokens, Index);
      Dot := NextCode(Tokens, Index + 1);
      Ctor := NextCode(Tokens, Dot + 1);
      if (Ctor > High(Tokens)) or not Tokens[Dot].IsSymbol('.') or not SameText(Tokens[Ctor].Text, 'Create') or
        ((Prev >= 0) and (Tokens[Prev].IsSymbol('.') or Tokens[Prev].IsKeyword('inherited'))) then
        Continue;
      TypeName := Types.DeclaredType(Tokens[Index].Text, Tokens[Index].StartPos);
      // Klassenreferenzen (TComponentClass, class of …) dürfen Create aufrufen.
      if (TypeName = '') or not StartsStr('T', TypeName) or EndsText('Class', TypeName) or
        StartsText('class', TypeName) or (Pos('<', TypeName) > 0) or not InStatements(AContext.Tree,
        Tokens[Index].StartPos) then
        Continue;
      AReport.Add(RangeOf(Tokens, Index, Ctor), Format('Create auf der Variablen %s statt auf der Klasse %s; ' +
        'das legt kein neues Objekt an', [Tokens[Index].Text, TypeName]), TRuleConfidence.High,
        [TRuleFix.Create(TypeName + '.Create verwenden', [TRuleEdit.Create(RangeOf(Tokens, Index, Index),
        TypeName)])]);
    end;
  finally
    Types.Free;
  end;
end;

{ TFormatWithoutSettingsRule }

function TFormatWithoutSettingsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('format-without-settings', TRuleSeverity.Hint,
    'Formatierung abhängig vom Gebietsschema');
end;

class function TFormatWithoutSettingsRule.HasLocaleSpecifier(const AFormat: string): Boolean;
var
  Index: Integer;
begin
  Index := 1;
  while Index <= Length(AFormat) do
  begin
    if AFormat[Index] = '%' then
    begin
      Inc(Index);
      if (Index <= Length(AFormat)) and (AFormat[Index] = '%') then
      begin
        Inc(Index);
        Continue;
      end;
      // Index, Ausrichtung, Breite, Genauigkeit: %0:-10.2f
      while (Index <= Length(AFormat)) and CharInSet(AFormat[Index], ['0'..'9', ':', '-', '.', '*']) do
        Inc(Index);
      if (Index <= Length(AFormat)) and CharInSet(AFormat[Index], ['f', 'F', 'n', 'N', 'm', 'M', 'g', 'G',
        'e', 'E']) then
        Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

/// <summary>Zahl der Argumente ohne TFormatSettings; 0, wenn AName keine solche Funktion ist.</summary>
function PlainArgumentCount(const AName: string): Integer;
const
  One: array[0..10] of string = ('FloatToStr', 'StrToFloat', 'DateToStr', 'StrToDate', 'DateTimeToStr',
    'StrToDateTime', 'TimeToStr', 'StrToTime', 'CurrToStr', 'StrToCurr', 'TextToFloat');
  Two: array[0..8] of string = ('FormatFloat', 'FormatDateTime', 'TryStrToFloat', 'StrToFloatDef',
    'TryStrToDate', 'StrToDateDef', 'TryStrToDateTime', 'StrToDateTimeDef', 'FormatCurr');
begin
  if MatchText(AName, One) then
    Result := 1
  else if MatchText(AName, Two) then
    Result := 2
  else if SameText(AName, 'FloatToStrF') then
    Result := 4
  else
    Result := 0;
end;

procedure TFormatWithoutSettingsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Open, Close, First, Prev, Expected: Integer;
  Reported: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
      Continue;
    Prev := PreviousCode(Tokens, Index);
    Open := NextCode(Tokens, Index + 1);
    // Methoden wie Writer.Format bleiben außen vor; SysUtils.Format zählt.
    if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') or ((Prev >= 0) and Tokens[Prev].IsSymbol('.') and
      not ((PreviousCode(Tokens, Prev) >= 0) and MatchText(Tokens[PreviousCode(Tokens, Prev)].Text,
      ['SysUtils', 'System.SysUtils']))) then
      Continue;
    Close := Closing(Tokens, Open);
    if Close < 0 then
      Continue;
    if SameText(Tokens[Index].Text, 'Format') then
    begin
      First := NextCode(Tokens, Open + 1);
      Reported := (ArgumentCount(Tokens, Open, Close) = 2) and
        (Tokens[First].Kind = TPascalTokenKind.StringLiteral) and HasLocaleSpecifier(Tokens[First].Text);
    end
    else
    begin
      Expected := PlainArgumentCount(Tokens[Index].Text);
      Reported := (Expected > 0) and (ArgumentCount(Tokens, Open, Close) = Expected);
    end;
    if Reported then
      AReport.Add(RangeOf(Tokens, Index, Close), Format('%s ohne TFormatSettings hängt vom Gebietsschema ab ' +
        '(Dezimaltrenner, Datumsformat); für Dateien und Protokolle eine feste TFormatSettings übergeben',
        [Tokens[Index].Text]), TRuleConfidence.Medium, [TRuleFix.Create('FormatSettings übergeben',
        [TRuleEdit.Create(TTextRange.Create(Tokens[Close].StartPos, Tokens[Close].StartPos),
        ', FormatSettings')])]);
  end;
end;

{ TManagedTypeRawMemoryRule }

const
  // RTL-Records mit verwalteten Feldern, auch ohne Index.
  ManagedStringRecords: array[0..2] of string = ('TFormatSettings', 'TSearchRec', 'TWin32FindData');
  ManagedInterfaceRecords: array[0..1] of string = ('TValue', 'TRttiContext');
  DynamicArrayNames: array[0..5] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
    'TArray', 'TObjectDynArray');

type
  /// <summary>Löst Typnamen der Datei und des Index auf und sagt, ob sie verwaltete Teile enthalten.</summary>
  TManagedTypes = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FIndex: ISymbolIndex;
    function TypeDecl(const AName: string): TSyntaxNode;
    function NodeTypeText(ANode: TSyntaxNode): string;
    function FieldsManaged(ARecord: TSyntaxNode; ADepth: Integer): string;
    function IndexManaged(const AName: string; ADepth: Integer): string;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
    /// <summary>'Strings', 'Interfaces', 'dynamische Arrays' oder 'Variants', wenn ATypeName solche Teile
    /// hat; '' sonst oder wenn der Typ unbekannt ist.</summary>
    function Managed(const ATypeName: string; ADepth: Integer): string;
    /// <summary>Zieltyp eines Zeigertyps (^TRec oder PRec = ^TRec in der Datei); '' sonst.</summary>
    function Pointee(const ATypeName: string): string;
    /// <summary>Ist ATypeName selbst ein String, Interface, dynamisches Array oder Variant?</summary>
    function IsPrimitive(const ATypeName: string): Boolean;
  end;

constructor TManagedTypes.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FIndex := AIndex;
end;

function TManagedTypes.TypeDecl(const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
  Name: string;
begin
  Found := nil;
  Name := AName;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Found = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, Name) then
        Found := ANode;
    end);
  Result := Found;
end;

function TManagedTypes.NodeTypeText(ANode: TSyntaxNode): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType] then
      Exit(Trim(Copy(FText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset)));
  end;
end;

function TManagedTypes.FieldsManaged(ARecord: TSyntaxNode; ADepth: Integer): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  for Index := 0 to ARecord.ChildCount - 1 do
  begin
    Child := ARecord[Index];
    // Verschachtelte Typdeklarationen sind keine Felder.
    if Child.Kind = TSyntaxKind.TypeDecl then
      Continue;
    if Child.Kind = TSyntaxKind.Field then
      Result := Managed(NodeTypeText(Child), ADepth + 1)
    else if not (Child.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) then
      Result := FieldsManaged(Child, ADepth);
    if Result <> '' then
      Exit;
  end;
end;

function TManagedTypes.IndexManaged(const AName: string; ADepth: Integer): string;
var
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Result := '';
  if FIndex = nil then
    Exit;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if Location.Symbol.Container <> '' then
      Continue;
    case Location.Symbol.Kind of
      TIndexSymbolKind.InterfaceType:
        Exit('Interfaces');
      TIndexSymbolKind.TypeAlias:
        Exit(Managed(Location.Symbol.TypeName, ADepth + 1));
      TIndexSymbolKind.RecordType:
        begin
          if not FIndex.FindFile(Location.FileName, UnitIndex) then
            Exit;
          for Symbol in UnitIndex.Symbols do
            if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AName) then
            begin
              Result := Managed(Symbol.TypeName, ADepth + 1);
              if Result <> '' then
                Exit;
            end;
          Exit;
        end;
    else
      Exit;
    end;
  end;
end;

function TManagedTypes.IsPrimitive(const ATypeName: string): Boolean;
var
  Name: string;
begin
  Name := Trim(ATypeName);
  Result := MatchText(Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String',
    'Variant', 'OleVariant', 'IInterface', 'IUnknown', 'IDispatch']) or MatchText(Name, DynamicArrayNames) or
    StartsText('array of', Name) or StartsText('TArray<', Name);
end;

function TManagedTypes.Managed(const ATypeName: string; ADepth: Integer): string;
var
  Name, Element: string;
  Decl, Body: TSyntaxNode;
  Index: Integer;
begin
  Result := '';
  Name := Trim(ATypeName);
  if (Name = '') or (ADepth > 16) then
    Exit;
  if MatchText(Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) then
    Exit('Strings');
  if MatchText(Name, ['Variant', 'OleVariant']) then
    Exit('Variants');
  if MatchText(Name, ['IInterface', 'IUnknown', 'IDispatch']) then
    Exit('Interfaces');
  if StartsText('array of', Name) or StartsText('TArray<', Name) or MatchText(Name, DynamicArrayNames) then
    Exit('dynamische Arrays');
  // Statisches Array: verwaltet, wenn die Elemente es sind.
  if StartsText('array', Name) then
  begin
    Index := Pos(' of ', LowerCase(Name));
    if Index = 0 then
      Exit;
    Element := Copy(Name, Index + 4, MaxInt);
    Exit(Managed(Element, ADepth + 1));
  end;
  if MatchText(Name, ManagedStringRecords) then
    Exit('Strings');
  if MatchText(Name, ManagedInterfaceRecords) then
    Exit('Interfaces');
  if Pos('<', Name) > 0 then
    Exit;
  Decl := TypeDecl(Name);
  if Decl = nil then
    Exit(IndexManaged(Name, ADepth));
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  if Body <> nil then
    Exit(FieldsManaged(Body, ADepth));
  if Decl.FindChild(TSyntaxKind.InterfaceType) <> nil then
    Exit('Interfaces');
  if (Decl.FindChild(TSyntaxKind.TypeReference) <> nil) or (Decl.FindChild(TSyntaxKind.ArrayType) <> nil) then
    Result := Managed(NodeTypeText(Decl), ADepth + 1);
end;

function TManagedTypes.Pointee(const ATypeName: string): string;
var
  Name: string;
  Decl: TSyntaxNode;
begin
  Result := '';
  Name := Trim(ATypeName);
  if StartsText('^', Name) then
    Exit(Trim(Copy(Name, 2, MaxInt)));
  if (Name = '') or (Pos('<', Name) > 0) then
    Exit;
  Decl := TypeDecl(Name);
  if (Decl <> nil) and (Decl.FindChild(TSyntaxKind.PointerType) <> nil) then
  begin
    Result := NodeTypeText(Decl);
    if StartsText('^', Result) then
      Result := Trim(Copy(Result, 2, MaxInt))
    else
      Result := '';
  end;
end;

function TManagedTypeRawMemoryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('managed-type-raw-memory', TRuleSeverity.Error,
    'FillChar, Move oder GetMem auf verwaltete Typen');
end;

procedure TManagedTypeRawMemoryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Managed: TManagedTypes;
  Index, Call, Open, Close: Integer;
  Starts, Stops: TArray<Integer>;
  Routine: string;

  // Argumente auf oberster Ebene: Start- und Endtoken.
  procedure SplitArguments;
  var
    Inner, Depth, First: Integer;
  begin
    Starts := nil;
    Stops := nil;
    Depth := 0;
    First := NextCode(Tokens, Open + 1);
    for Inner := Open + 1 to Close do
      if (Inner = Close) or ((Depth = 0) and Tokens[Inner].IsSymbol(',')) then
      begin
        if First < Inner then
        begin
          Starts := Starts + [First];
          Stops := Stops + [PreviousCode(Tokens, Inner)];
        end;
        First := NextCode(Tokens, Inner + 1);
      end
      else if Tokens[Inner].IsSymbol('(') or Tokens[Inner].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Inner].IsSymbol(')') or Tokens[Inner].IsSymbol(']') then
        Dec(Depth);
  end;

  // Argument AIndex als X, @X oder X^: Name (Tokenindex) und ob dereferenziert; -1 sonst.
  function Target(AArgument: Integer; out ADeref: Boolean): Integer;
  var
    First, Last: Integer;
  begin
    Result := -1;
    ADeref := False;
    if AArgument > High(Starts) then
      Exit;
    First := Starts[AArgument];
    Last := Stops[AArgument];
    if Tokens[First].IsSymbol('@') then
      First := NextCode(Tokens, First + 1);
    if (Last > First) and Tokens[Last].IsSymbol('^') and (NextCode(Tokens, First + 1) = Last) then
    begin
      ADeref := True;
      Last := First;
    end;
    if (First = Last) and (Tokens[First].Kind = TPascalTokenKind.Identifier) then
      Result := First;
  end;

  // Typ der Daten hinter dem Argument; bei AAsPointer (GetMem, FreeMem, X^) der Zieltyp des Zeigers.
  function DataType(AName: Integer; AAsPointer: Boolean): string;
  begin
    Result := Types.DeclaredType(Tokens[AName].Text, Tokens[AName].StartPos);
    if AAsPointer then
      Result := Managed.Pointee(Result);
  end;

  function Subject(const ATypeName, AKind: string): string;
  begin
    if Managed.IsPrimitive(ATypeName) then
      Result := Format('%s ist ein verwalteter Typ', [ATypeName])
    else
      Result := Format('%s enthält %s', [ATypeName, AKind]);
  end;

  // Anweisung: davor ;, begin, then, else, do, try, finally, except oder repeat; danach ;, end oder else.
  function IsStatement: Boolean;
  var
    Before, After: Integer;
  begin
    Before := PreviousCode(Tokens, Call);
    After := NextCode(Tokens, Close + 1);
    Result := (Before >= 0) and (Tokens[Before].IsSymbol(';') or Tokens[Before].IsKeyword('begin') or
      Tokens[Before].IsKeyword('then') or Tokens[Before].IsKeyword('else') or Tokens[Before].IsKeyword('do') or
      Tokens[Before].IsKeyword('try') or Tokens[Before].IsKeyword('finally') or Tokens[Before].IsKeyword('except') or
      Tokens[Before].IsKeyword('repeat')) and (After <= High(Tokens)) and (Tokens[After].IsSymbol(';') or
      Tokens[After].IsKeyword('end') or Tokens[After].IsKeyword('else'));
  end;

  // Argument ist SizeOf(X) oder SizeOf(T) mit X bzw. T wie angegeben.
  function IsSizeOf(AArgument: Integer; const AName, ATypeName: string): Boolean;
  var
    First, Inner, Last: Integer;
  begin
    Result := False;
    if AArgument > High(Starts) then
      Exit;
    First := Starts[AArgument];
    Inner := NextCode(Tokens, NextCode(Tokens, First + 1) + 1);
    Last := Stops[AArgument];
    Result := SameText(Tokens[First].Text, 'SizeOf') and (NextCode(Tokens, Inner + 1) = Last) and
      Tokens[Last].IsSymbol(')') and (SameText(Tokens[Inner].Text, AName) or SameText(Tokens[Inner].Text, ATypeName));
  end;

  function IsZero(AArgument: Integer): Boolean;
  begin
    Result := (AArgument <= High(Starts)) and (Starts[AArgument] = Stops[AArgument]) and
      MatchText(Tokens[Starts[AArgument]].Text, ['0', '#0', '$0', '$00']);
  end;

  procedure Report(const ATypeName, AKind, AText: string; const AFixes: TArray<TRuleFix>);
  begin
    AReport.Add(RangeOf(Tokens, Call, Close), Format('%s; %s %s', [Subject(ATypeName, AKind), Routine, AText]),
      TRuleConfidence.High, AFixes);
  end;

  procedure CheckOverwrite;
  var
    Name: Integer;
    Deref: Boolean;
    TypeName, Kind: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := Target(0, Deref);
    if Name < 0 then
      Exit;
    TypeName := DataType(Name, Deref);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
      Exit;
    Fixes := nil;
    // FillChar(X, SizeOf(X), 0) bzw. ZeroMemory(@X, SizeOf(X)): X := Default(T).
    if IsStatement and not Deref and IsSizeOf(1, Tokens[Name].Text, TypeName) and
      (SameText(Routine, 'ZeroMemory') or IsZero(2)) then
      Fixes := [TRuleFix.Create(Format('%s := Default(%s)', [Tokens[Name].Text, TypeName]),
        [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Format('%s := Default(%s)', [Tokens[Name].Text,
        TypeName]))], True)];
    Report(TypeName, Kind, 'überschreibt die Referenzen ohne Freigabe (Leck, ggf. Zugriffsverletzung).',
      Fixes);
  end;

  procedure CheckCopy(ASource, ADestination: Integer);
  var
    Source, Destination: Integer;
    SourceDeref, DestinationDeref: Boolean;
    SourceType, DestinationType, Kind, TypeName: string;
    Fixes: TArray<TRuleFix>;
  begin
    Source := Target(ASource, SourceDeref);
    Destination := Target(ADestination, DestinationDeref);
    SourceType := '';
    DestinationType := '';
    if Source >= 0 then
      SourceType := DataType(Source, SourceDeref);
    if Destination >= 0 then
      DestinationType := DataType(Destination, DestinationDeref);
    TypeName := DestinationType;
    Kind := Managed.Managed(DestinationType, 0);
    if Kind = '' then
    begin
      TypeName := SourceType;
      Kind := Managed.Managed(SourceType, 0);
    end;
    if Kind = '' then
      Exit;
    Fixes := nil;
    // Move(A, B, SizeOf(T)) mit gleichem Typ: B := A.
    if IsStatement and (Source >= 0) and (Destination >= 0) and not SourceDeref and not DestinationDeref and
      SameText(SourceType, DestinationType) and IsSizeOf(2, Tokens[Source].Text, SourceType) then
      Fixes := [TRuleFix.Create(Format('%s := %s', [Tokens[Destination].Text, Tokens[Source].Text]),
        [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Format('%s := %s', [Tokens[Destination].Text,
        Tokens[Source].Text]))], True)];
    Report(TypeName, Kind, 'kopiert die Referenzen ohne Referenzzählung (doppelte Freigabe, ' +
      'ggf. Zugriffsverletzung).', Fixes);
  end;

  procedure CheckMemory(AAllocate: Boolean);
  var
    Name: Integer;
    Deref: Boolean;
    TypeName, Kind, Replacement: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := Target(0, Deref);
    if (Name < 0) or Deref then
      Exit;
    TypeName := DataType(Name, True);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
      Exit;
    Fixes := nil;
    if AAllocate then
      Replacement := Format('New(%s)', [Tokens[Name].Text])
    else
      Replacement := Format('Dispose(%s)', [Tokens[Name].Text]);
    // GetMem(P, SizeOf(T)) bzw. FreeMem(P) oder FreeMem(P, SizeOf(T)): New bzw. Dispose.
    if IsStatement and ((Length(Starts) = 1) and not AAllocate or IsSizeOf(1, '', TypeName)) then
      Fixes := [TRuleFix.Create(Replacement, [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Replacement)], True)];
    if AAllocate then
      Report(TypeName, Kind, 'lässt die Referenzen uninitialisiert (Zugriffsverletzung beim ersten ' +
        'Zuweisen); New oder Initialize verwenden.', Fixes)
    else
      Report(TypeName, Kind, 'gibt die Referenzen nicht frei (Leck); Dispose oder Finalize verwenden.', Fixes);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  Managed := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    for Index := 0 to High(Tokens) do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not MatchText(Tokens[Index].Text, ['FillChar',
        'ZeroMemory', 'FillMemory', 'Move', 'CopyMemory', 'GetMem', 'FreeMem']) then
        Continue;
      // Methoden anderer Objekte (Stream.Move) sind nicht gemeint.
      if (PreviousCode(Tokens, Index) >= 0) and Tokens[PreviousCode(Tokens, Index)].IsSymbol('.') then
        Continue;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
        Continue;
      Close := Closing(Tokens, Open);
      if Close < 0 then
        Continue;
      Call := Index;
      SplitArguments;
      Routine := Tokens[Index].Text;
      if MatchText(Routine, ['FillChar', 'ZeroMemory', 'FillMemory']) then
        CheckOverwrite
      else if SameText(Routine, 'Move') then
        CheckCopy(0, 1)
      else if SameText(Routine, 'CopyMemory') then
        CheckCopy(1, 0)
      else
        CheckMemory(SameText(Routine, 'GetMem'));
    end;
  finally
    Managed.Free;
    Types.Free;
  end;
end;

{ TThreadvarManagedRule }

function TThreadvarManagedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('threadvar-managed', TRuleSeverity.Warning, 'threadvar mit verwaltetem Typ');
end;

procedure TThreadvarManagedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Managed: TManagedTypes;

  procedure CheckDecl(ADecl: TSyntaxNode);
  var
    TypeName, Kind, Name, Shown: string;
    Index: Integer;
  begin
    TypeName := Managed.NodeTypeText(ADecl);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
      Exit;
    Shown := TypeName;
    if not Managed.IsPrimitive(TypeName) then
      Shown := Format('%s (enthält %s)', [TypeName, Kind]);
    for Name in SplitString(ADecl.Name, ',') do
      for Index := 0 to High(Tokens) do
      begin
        if Tokens[Index].Offset >= ADecl.EndOffset then
          Break;
        if (Tokens[Index].Offset >= ADecl.StartOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
          SameText(Tokens[Index].Text, Trim(Name)) then
        begin
          AReport.Add(RangeOf(Tokens, Index, Index), Format('threadvar mit %s wird beim Thread-Ende nicht ' +
            'finalisiert (Leck je Thread).', [Shown]), TRuleConfidence.High);
          Break;
        end;
      end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.VarSection) and SameText(ANode.Name, 'threadvar') then
    begin
      for Index := 0 to ANode.ChildCount - 1 do
        if ANode[Index].Kind = TSyntaxKind.VarDecl then
          CheckDecl(ANode[Index]);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Managed := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    Visit(AContext.Tree.Root);
  finally
    Managed.Free;
  end;
end;

{ TPCharOfTemporaryRule }

const
  PCharCasts: array[0..2] of string = ('PChar', 'PWideChar', 'PAnsiChar');
  // Umwandlungen, durch die die Regel hindurchsieht: LPARAM(PChar(…)).
  PassThroughCasts: array[0..9] of string = ('LPARAM', 'WPARAM', 'NativeInt', 'NativeUInt', 'Pointer', 'Integer',
    'Cardinal', 'Int64', 'UInt64', 'IntPtr');
  StringCasts: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString');
  // Asynchrone Nachrichten: der Empfänger liest den Zeiger erst nach der Anweisung.
  AsyncMessages: array[0..3] of string = ('PostMessage', 'PostThreadMessage', 'SendNotifyMessage',
    'SendMessageCallback');

function TPCharOfTemporaryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('pchar-of-temporary', TRuleSeverity.Warning,
    'PChar auf einen temporären String');
end;

procedure TPCharOfTemporaryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  Tokens: TTokens;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function IsStringValue(ANode: TSyntaxNode): Boolean;
  var
    TypeName: string;
  begin
    case ANode.Kind of
      TSyntaxKind.Literal:
        Result := (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']);
      TSyntaxKind.Identifier:
        begin
          TypeName := Types.DeclaredType(ANode.Name, ANode.StartPos);
          Result := MatchText(TypeName, StringCasts);
        end;
      TSyntaxKind.Call:
        Result := not MatchText(ANode.Name, PCharCasts) and not MatchText(ANode.Name, PassThroughCasts);
      TSyntaxKind.ParenExpr:
        Result := (ANode.ChildCount = 1) and IsStringValue(ANode[0]);
      TSyntaxKind.BinaryExpr:
        Result := (ANode.Name = '+') and (ANode.ChildCount = 2) and
          (IsStringValue(ANode[0]) or IsStringValue(ANode[1]));
    else
      Result := False;
    end;
  end;

  // Nur Literale: der Compiler legt den String als Konstante ab.
  function IsConstant(ANode: TSyntaxNode): Boolean;
  begin
    case ANode.Kind of
      TSyntaxKind.Literal:
        Result := True;
      TSyntaxKind.ParenExpr:
        Result := (ANode.ChildCount = 1) and IsConstant(ANode[0]);
      TSyntaxKind.BinaryExpr:
        Result := (ANode.ChildCount = 2) and IsConstant(ANode[0]) and IsConstant(ANode[1]);
    else
      Result := False;
    end;
  end;

  // Temporärer String: Verkettung mit einem String oder Ergebnis eines Funktionsaufrufs.
  function IsTemporary(ANode: TSyntaxNode): Boolean;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and MatchText(ANode.Name, StringCasts) and (ANode.ChildCount = 2) then
      Exit(IsTemporary(ANode[1]));
    if ANode.Kind = TSyntaxKind.ParenExpr then
      Exit((ANode.ChildCount = 1) and IsTemporary(ANode[0]));
    Result := not IsConstant(ANode) and (((ANode.Kind = TSyntaxKind.BinaryExpr) and IsStringValue(ANode)) or
      ((ANode.Kind = TSyntaxKind.Call) and IsStringValue(ANode)));
  end;

  // PChar(temporär) in AValue, auch hinter LPARAM(…) und ähnlichen Umwandlungen; sonst nil.
  function TemporaryPChar(AValue: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (AValue = nil) or (AValue.Kind <> TSyntaxKind.Call) or (AValue.ChildCount <> 2) then
      Exit;
    if MatchText(AValue.Name, PCharCasts) and IsTemporary(AValue[1]) then
      Exit(AValue[1]);
    if MatchText(AValue.Name, PassThroughCasts) then
      Result := TemporaryPChar(AValue[1]);
  end;

  function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Index, Inner: Integer;
    Section: TSyntaxNode;
    Name: string;
  begin
    Result := False;
    if ARoutine = nil then
      Exit;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Section := ARoutine[Index];
      if (Section.Kind <> TSyntaxKind.VarSection) or not SameText(Section.Name, 'var') then
        Continue;
      for Inner := 0 to Section.ChildCount - 1 do
        if Section[Inner].Kind = TSyntaxKind.VarDecl then
          for Name in SplitString(Section[Inner].Name, ',') do
            if SameText(Trim(Name), AName) then
              Exit(True);
    end;
  end;

  // Neuer Name AName + 'Text', der in der Routine noch nicht vorkommt.
  function FreshName(ARoutine: TSyntaxNode; const ABase: string): string;
  var
    Number: Integer;

    function Used(const AName: string): Boolean;
    var
      Token: TPascalToken;
    begin
      for Token in Tokens do
        if (Token.Offset >= ARoutine.StartOffset) and (Token.Offset < ARoutine.EndOffset) and
          (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, AName) then
          Exit(True);
      Result := False;
    end;

  begin
    Result := ABase + 'Text';
    Number := 2;
    while Used(Result) do
    begin
      Result := ABase + 'Text' + IntToStr(Number);
      Inc(Number);
    end;
  end;

  procedure CheckAssign(AStatement, ARoutine, AParent: TSyntaxNode);
  var
    Expression: TSyntaxNode;
    Target, Name, Indent: string;
    Fixes: TArray<TRuleFix>;
  begin
    Expression := TemporaryPChar(AStatement[1]);
    if Expression = nil then
      Exit;
    Target := Trim(Text(AStatement[0]));
    Fixes := nil;
    // Lokale Variable direkt in einem Block: das Zwischenergebnis in eine Inline-Variable legen.
    if (AStatement[0].Kind = TSyntaxKind.Identifier) and (AParent <> nil) and (AParent.Kind = TSyntaxKind.Block) and
      IsLocal(ARoutine, Target) then
    begin
      Name := FreshName(ARoutine, Target);
      Indent := StringOfChar(' ', AStatement.StartPos.Character);
      Fixes := [TRuleFix.Create(Format('Zwischenergebnis in %s ablegen', [Name]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
        Format('var %s: string := %s;', [Name, Trim(Text(Expression))]) + LineBreak + Indent),
        TRuleEdit.Create(TTextRange.Create(Expression.StartPos, Expression.EndPos), Name)])];
    end;
    AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos), Format('Der Ausdruck %s ist temporär; ' +
      '%s zeigt nach dieser Zeile auf freigegebenen Speicher.', [Trim(Text(Expression)), Target]),
      TRuleConfidence.High, Fixes);
  end;

  procedure CheckAsync(ACall: TSyntaxNode);
  var
    Index: Integer;
    Expression: TSyntaxNode;
  begin
    for Index := 1 to ACall.ChildCount - 1 do
    begin
      Expression := TemporaryPChar(ACall[Index]);
      if Expression <> nil then
        AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos), Format('Der Ausdruck %s ist ' +
          'temporär; %s liest den Zeiger erst später aus freigegebenem Speicher.', [Trim(Text(Expression)),
          ACall.Name]), TRuleConfidence.High);
    end;
  end;

  procedure Visit(ANode, ARoutine, AParent: TSyntaxNode);
  var
    Index: Integer;
    Routine: TSyntaxNode;
  begin
    Routine := ARoutine;
    if ANode.Kind = TSyntaxKind.RoutineDecl then
      Routine := ANode;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) then
      CheckAssign(ANode, Routine, AParent)
    else if (ANode.Kind = TSyntaxKind.Call) and MatchText(ANode.Name, AsyncMessages) then
      CheckAsync(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], Routine, ANode);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    Types.Free;
  end;
end;

{ TStringListUnsortedRule }

const
  StringListClasses: array[0..1] of string = ('TStringList', 'THashedStringList');
  // Aufrufe, die eine Liste nicht weitergeben: sie bleibt in der Hand der Routine.
  NonEscapingCalls: array[0..2] of string = ('FreeAndNil', 'Assigned', 'Free');
  // Methoden, die mit Sorted := True eine Ausnahme auslösen: dann keine Korrektur mit Sorted.
  UnsortedOnlyMethods: array[0..2] of string = ('Insert', 'Move', 'Exchange');

type
  // Was die Regel über eine Liste (lokal je Routine, sonst Feld) gesammelt hat.
  TStringListFacts = record
    Creation: TSyntaxNode;
    Sorted: Boolean;
    UnsortedOnly: Boolean;
    Hits: TArray<TSyntaxNode>;
  end;

function TStringListUnsortedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('stringlist-unsorted', TRuleSeverity.Warning,
    'Find oder Duplicates auf einer unsortierten TStringList');
end;

procedure TStringListUnsortedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Keys: TArray<string>;
  Facts: TArray<TStringListFacts>;
  Routines: TArray<TSyntaxNode>;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Name der Liste: X oder Self.X; sonst leer.
  function BaseName(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode = nil then
      Exit;
    if ANode.Kind = TSyntaxKind.Identifier then
      Result := ANode.Name
    else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
      Result := ANode.Name;
  end;

  // Deklariert die Routine AName als Variable (var-Abschnitt oder Inline-Variable)?
  function DeclaresLocal(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
    Child: TSyntaxNode;
    Name: string;
  begin
    Result := False;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      // Eingebettete Routinen haben eigene Variablen.
      if Child.Kind = TSyntaxKind.RoutineDecl then
        Continue;
      if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
        for Name in SplitString(Child.Name, ',') do
          if SameText(Trim(Name), AName) then
            Exit(True);
      if DeclaresLocal(Child, AName) then
        Exit(True);
    end;
  end;

  // Schlüssel der Liste an ANode: Routine und Name für lokale Variablen, sonst der Feldname.
  function KeyOf(ANode: TSyntaxNode; const AName: string): string;
  var
    Index: Integer;
    Routine: TSyntaxNode;
  begin
    // Routines ist nach Start sortiert; die innerste umgebende Routine liegt hinten.
    for Index := High(Routines) downto 0 do
    begin
      Routine := Routines[Index];
      if (Routine.StartOffset <= ANode.StartOffset) and (Routine.EndOffset >= ANode.EndOffset) and
        DeclaresLocal(Routine, AName) then
        Exit(IntToStr(Routine.StartOffset) + ':' + LowerCase(AName));
    end;
    Result := 'F:' + LowerCase(AName);
  end;

  function FactIndex(const AKey: string): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to High(Keys) do
      if Keys[Index] = AKey then
        Exit(Index);
    Result := Length(Keys);
    SetLength(Keys, Result + 1);
    SetLength(Facts, Result + 1);
    Keys[Result] := AKey;
    Facts[Result].Creation := nil;
    Facts[Result].Sorted := False;
    Facts[Result].UnsortedOnly := False;
    Facts[Result].Hits := nil;
  end;

  // Index der Liste, auf die ANode (X oder Self.X) zeigt; -1 ohne Namen.
  function ListOf(ANode: TSyntaxNode): Integer;
  var
    Name: string;
  begin
    Name := BaseName(ANode);
    if Name = '' then
      Exit(-1);
    Result := FactIndex(KeyOf(ANode, Name));
  end;

  function IsFalse(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'False');
  end;

  // TStringList.Create(...); ASorted, wenn Create(Duplicates, Sorted, CaseSensitive) sortiert.
  function IsCreation(AValue: TSyntaxNode; out ASorted: Boolean): Boolean;
  var
    Callee: TSyntaxNode;
  begin
    ASorted := False;
    Callee := AValue;
    if (AValue <> nil) and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount > 0) then
      Callee := AValue[0];
    Result := (Callee <> nil) and (Callee.Kind = TSyntaxKind.MemberAccess) and SameText(Callee.Name, 'Create') and
      (Callee.ChildCount = 1) and (Callee[0].Kind = TSyntaxKind.Identifier) and
      MatchText(Callee[0].Name, StringListClasses);
    if Result and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount = 4) then
      ASorted := not IsFalse(AValue[2]);
  end;

  procedure NoteCreation(AStatement: TSyntaxNode; AList: Integer; AValue: TSyntaxNode);
  var
    ConstructorSorted: Boolean;
  begin
    if (AList < 0) or not IsCreation(AValue, ConstructorSorted) then
      Exit;
    if Facts[AList].Creation = nil then
      Facts[AList].Creation := AStatement;
    if ConstructorSorted then
      Facts[AList].Sorted := True;
  end;

  // Die Liste wird weitergegeben: was der Empfänger damit macht, ist unbekannt.
  procedure NoteEscape(ANode: TSyntaxNode);
  var
    List: Integer;
  begin
    List := ListOf(ANode);
    if List >= 0 then
      Facts[List].Sorted := True;
  end;

  procedure VisitAssign(AStatement: TSyntaxNode);
  var
    Target, Value: TSyntaxNode;
    List: Integer;
  begin
    Target := AStatement[0];
    Value := AStatement[1];
    NoteCreation(AStatement, ListOf(Target), Value);
    NoteEscape(Value);
    if (Target.Kind <> TSyntaxKind.MemberAccess) or (Target.ChildCount <> 1) then
      Exit;
    List := ListOf(Target[0]);
    if List < 0 then
      Exit;
    if SameText(Target.Name, 'Sorted') and not IsFalse(Value) then
      Facts[List].Sorted := True
    else if SameText(Target.Name, 'Duplicates') and (Value.Kind = TSyntaxKind.Identifier) and
      MatchText(Value.Name, ['dupIgnore', 'dupError']) then
      Facts[List].Hits := Facts[List].Hits + [AStatement];
  end;

  // X.Methode oder X.Methode(...): Sortieren, Find und Methoden, die nur unsortiert gehen.
  procedure VisitMember(AMember, ACall: TSyntaxNode);
  var
    List: Integer;
  begin
    if AMember.ChildCount <> 1 then
      Exit;
    List := ListOf(AMember[0]);
    if List < 0 then
      Exit;
    if SameText(AMember.Name, 'Sort') or SameText(AMember.Name, 'CustomSort') then
      Facts[List].Sorted := True;
    if MatchText(AMember.Name, UnsortedOnlyMethods) then
      Facts[List].UnsortedOnly := True;
    if SameText(AMember.Name, 'Find') and (ACall <> nil) and (ACall.ChildCount = 3) then
      Facts[List].Hits := Facts[List].Hits + [ACall];
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Value: TSyntaxNode;
  begin
    case ANode.Kind of
      TSyntaxKind.AssignStatement:
        if ANode.ChildCount = 2 then
          VisitAssign(ANode);
      TSyntaxKind.InlineVar:
        if (ANode.ChildCount > 0) and (Pos(',', ANode.Name) = 0) then
        begin
          Value := ANode[ANode.ChildCount - 1];
          NoteEscape(Value);
          NoteCreation(ANode, FactIndex(KeyOf(ANode, Trim(ANode.Name))), Value);
        end;
      TSyntaxKind.Call:
        begin
          if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
            VisitMember(ANode[0], ANode);
          // Als Argument übergeben: der Aufgerufene kann sortieren.
          if not MatchText(ANode.Name, NonEscapingCalls) then
            for Index := 1 to ANode.ChildCount - 1 do
              NoteEscape(ANode[Index]);
        end;
      TSyntaxKind.CallStatement:
        if (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
          VisitMember(ANode[0], nil);
      TSyntaxKind.WithStatement:
        // with X do Sorted := True ist nicht nachvollziehbar: als sortiert betrachten.
        for Index := 0 to ANode.ChildCount - 2 do
          NoteEscape(ANode[Index]);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

  procedure CollectRoutines(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
      Routines := Routines + [ANode];
    for Index := 0 to ANode.ChildCount - 1 do
      CollectRoutines(ANode[Index]);
  end;

  function Indent(ANode: TSyntaxNode): string;
  begin
    Result := StringOfChar(' ', ANode.StartPos.Character);
  end;

  function ListName(const AFacts: TStringListFacts): string;
  begin
    if AFacts.Creation.Kind = TSyntaxKind.InlineVar then
      Result := Trim(AFacts.Creation.Name)
    else
      Result := Text(AFacts.Creation[0]);
  end;

  // Sorted := True direkt nach dem Erzeugen; nur in einem Anweisungsblock.
  function SortedFix(const AFacts: TStringListFacts): TArray<TRuleFix>;
  var
    Creation: TSyntaxNode;
  begin
    Result := nil;
    Creation := AFacts.Creation;
    if AFacts.UnsortedOnly or (Creation.Parent = nil) or (Creation.Parent.Kind <> TSyntaxKind.Block) then
      Exit;
    Result := [TRuleFix.Create('Sorted := True nach dem Erzeugen ergänzen',
      [TRuleEdit.Create(TTextRange.Create(Creation.EndPos, Creation.EndPos),
      ';' + LineBreak + Indent(Creation) + ListName(AFacts) + '.Sorted := True')])];
  end;

  // if X.Find(S, I) then: vorher I := X.IndexOf(S), im if I >= 0.
  function IndexOfFix(AFind: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    IndexText: string;
  begin
    Result := nil;
    Statement := AFind.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.IfStatement) or (Statement.ChildCount = 0) or
      (Statement[0] <> AFind) or (Statement.Parent = nil) or (Statement.Parent.Kind <> TSyntaxKind.Block) then
      Exit;
    IndexText := Text(AFind[2]);
    Result := [TRuleFix.Create('IndexOf statt Find verwenden',
      [TRuleEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
      Format('%s := %s.IndexOf(%s);', [IndexText, Text(AFind[0][0]), Text(AFind[1])]) + LineBreak +
      Indent(Statement)),
      TRuleEdit.Create(TTextRange.Create(AFind.StartPos, AFind.EndPos), IndexText + ' >= 0')])];
  end;

  procedure ReportUses(const AFacts: TStringListFacts);
  var
    Use: TSyntaxNode;
    Name: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := ListName(AFacts);
    for Use in AFacts.Hits do
      if Use.Kind = TSyntaxKind.Call then
      begin
        Fixes := SortedFix(AFacts);
        Fixes := Fixes + IndexOfFix(Use);
        AReport.Add(TTextRange.Create(Use.StartPos, Use.EndPos), Format('Find setzt eine sortierte Liste voraus; ' +
          '%s ist nicht sortiert.', [Name]), TRuleConfidence.Medium, Fixes);
      end
      else
        AReport.Add(TTextRange.Create(Use.StartPos, Use.EndPos), Format('Duplicates wirkt nur bei sortierten ' +
          'Listen; %s ist nicht sortiert.', [Name]), TRuleConfidence.Medium, SortedFix(AFacts));
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Keys := nil;
  Facts := nil;
  Routines := nil;
  CollectRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
  for Index := 0 to High(Facts) do
    if (Facts[Index].Creation <> nil) and not Facts[Index].Sorted then
      ReportUses(Facts[Index]);
end;

{ TWritelnInGuiAppRule }

const
  ConsoleRoutines: array[0..3] of string = ('Write', 'Writeln', 'Read', 'Readln');
  StandardFiles: array[0..2] of string = ('Output', 'ErrOutput', 'Input');
  FileTypes: array[0..2] of string = ('Text', 'TextFile', 'File');
  IntegerTypes: array[0..13] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int32', 'UInt32');
  FloatTypes: array[0..5] of string = ('Double', 'Single', 'Extended', 'Real', 'Currency', 'TDateTime');
  // Funktionen, die einen String liefern; dazu alle *ToStr und *ToHex.
  StringFunctions: array[0..14] of string = ('Format', 'Trim', 'TrimLeft', 'TrimRight', 'UpperCase', 'LowerCase',
    'QuotedStr', 'Copy', 'StringOfChar', 'StringReplace', 'ExtractFileName', 'ExtractFilePath', 'Concat',
    'ParamStr', 'GetCurrentDir');

function TWritelnInGuiAppRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('writeln-in-gui-app', TRuleSeverity.Warning, 'Writeln in einem Programm ohne Konsole');
end;

class function TWritelnInGuiAppRule.ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind;
var
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  First: Boolean;
  Directive: string;
begin
  if SameText(Trim(AConsoleTarget), 'true') then
    Exit(TRuleApplicationKind.Console);
  Result := TRuleApplicationKind.Unknown;
  Tokens := TPascalLexer.Tokenize(AMainSource);
  First := True;
  for Token in Tokens do
    case Token.Kind of
      TPascalTokenKind.Directive:
        begin
          // {$APPTYPE CONSOLE} oder (*$APPTYPE CONSOLE*), auch in {$IFDEF}: dann gilt Konsole.
          Directive := UpperCase(Token.Text);
          Directive := StringReplace(StringReplace(Directive, '(*$', '', []), '{$', '', []);
          if StartsText('APPTYPE', Trim(Directive)) and ContainsText(Directive, 'CONSOLE') then
            Exit(TRuleApplicationKind.Console);
        end;
      TPascalTokenKind.Comment:
        ;
    else
      if First then
      begin
        First := False;
        if Token.IsKeyword('program') then
          Result := TRuleApplicationKind.Gui
        else
          Exit(TRuleApplicationKind.Unknown);
      end;
    end;
end;

class function TWritelnInGuiAppRule.Replacement(const AOptions: string): string;
var
  Value: TJSONValue;
begin
  Result := DefaultReplacement;
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if (Value is TJSONObject) and TJSONObject(Value).TryGetValue<string>('replacement', Result) and
      (Trim(Result) = '') then
      Result := DefaultReplacement;
  finally
    Value.Free;
  end;
  Result := Trim(Result);
end;

procedure TWritelnInGuiAppRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  Tokens: TTokens;
  Declared: TArray<string>;
  ReplacementText: string;
  NeedsSysUtils: Boolean;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Namen der Routinen, die die Unit selbst deklariert (letzter Teil von TKlasse.Write).
  procedure CollectDeclared(ANode: TSyntaxNode);
  var
    Index: Integer;
    Name: string;
  begin
    if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
    begin
      Name := ANode.Name;
      if Pos('.', Name) > 0 then
        Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
      Declared := Declared + [Name];
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CollectDeclared(ANode[Index]);
  end;

  function DeclaredTypeOf(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode.Kind = TSyntaxKind.Identifier then
      Result := Types.DeclaredType(ANode.Name, ANode.StartPos);
  end;

  // Die Prüfung "if IsConsole then" zeigt, dass der Aufruf gewollt ist.
  function MentionsIsConsole(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'IsConsole') then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if MentionsIsConsole(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

  function Guarded(ANode: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
  begin
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if (Parent.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement]) and (Parent.ChildCount > 0) and
        MentionsIsConsole(Parent[0]) then
        Exit(True);
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  // Innerhalb einer Methode: Read und Write können Methoden der Klasse sein (TStream.Read).
  function InMethod(ANode: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
  begin
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if (Parent.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Parent.Name) > 0) then
        Exit(True);
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  // Argument als String-Ausdruck für die Korrektur; '' wenn der Typ nicht sicher ist.
  function AsString(ANode: TSyntaxNode): string;
  var
    TypeName: string;
  begin
    Result := '';
    case ANode.Kind of
      TSyntaxKind.Literal:
        if (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']) then
          Result := Text(ANode)
        else
          Result := QuotedStr(Text(ANode));
      TSyntaxKind.Identifier:
        begin
          TypeName := DeclaredTypeOf(ANode);
          if MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'Char',
            'WideChar', 'AnsiChar', 'TFileName']) then
            Result := ANode.Name
          else if MatchText(TypeName, IntegerTypes) then
          begin
            Result := 'IntToStr(' + ANode.Name + ')';
            NeedsSysUtils := True;
          end
          else if MatchText(TypeName, FloatTypes) then
          begin
            Result := 'FloatToStr(' + ANode.Name + ')';
            NeedsSysUtils := True;
          end
          else if SameText(TypeName, 'Boolean') then
          begin
            Result := 'BoolToStr(' + ANode.Name + ', True)';
            NeedsSysUtils := True;
          end;
        end;
      TSyntaxKind.Call:
        if EndsText('ToStr', ANode.Name) or EndsText('ToHex', ANode.Name) or MatchText(ANode.Name, StringFunctions) then
          Result := Text(ANode);
      TSyntaxKind.BinaryExpr:
        if (ANode.Name = '+') and (ANode.ChildCount = 2) and (AsString(ANode[0]) = Text(ANode[0])) and
          (AsString(ANode[1]) = Text(ANode[1])) then
          Result := Text(ANode);
      TSyntaxKind.ParenExpr:
        if (ANode.ChildCount = 1) and (AsString(ANode[0]) <> '') then
          Result := '(' + AsString(ANode[0]) + ')';
    end;
  end;

  // Breitenangaben wie X:5:2 lassen sich nicht in einen String übertragen.
  function HasWidth(ACall: TSyntaxNode): Boolean;
  var
    Token: TPascalToken;
  begin
    for Token in Tokens do
      if (Token.Offset >= ACall.StartOffset) and (Token.Offset < ACall.EndOffset) and Token.IsSymbol(':') then
        Exit(True);
    Result := False;
  end;

  function Fixes(ACall: TSyntaxNode; AFirst: Integer): TArray<TRuleFix>;
  var
    Index: Integer;
    Part, Expression, NewText, Name: string;
    Edits: TArray<TRuleEdit>;
    UsesEdit: TTextEdit;
    Used: TArray<string>;
  begin
    Result := nil;
    if (ACall.Kind <> TSyntaxKind.Call) or (AFirst >= ACall.ChildCount) or HasWidth(ACall) then
      Exit;
    NeedsSysUtils := False;
    Expression := '';
    for Index := AFirst to ACall.ChildCount - 1 do
    begin
      Part := AsString(ACall[Index]);
      if Part = '' then
        Exit;
      if Expression <> '' then
        Expression := Expression + ' + ';
      Expression := Expression + Part;
    end;
    if Pos('%s', ReplacementText) > 0 then
      NewText := StringReplace(ReplacementText, '%s', Expression, [])
    else if SameText(ReplacementText, TWritelnInGuiAppRule.DefaultReplacement) then
      NewText := ReplacementText + '(PChar(' + Expression + '))'
    else
      NewText := ReplacementText + '(' + Expression + ')';
    Edits := [TRuleEdit.Create(TTextRange.Create(ACall.StartPos, ACall.EndPos), NewText)];
    Used := TUsesClauses.UsedUnits(Tokens);
    if SameText(ReplacementText, TWritelnInGuiAppRule.DefaultReplacement) and
      not TUsesClauses.IsUsed(Used, 'Winapi.Windows', AContext.Namespaces) and
      TUsesClauses.AddUnit(Tokens, ACall.StartOffset, 'Winapi.Windows', TTextLines.LineBreakOf(AContext.Text),
      UsesEdit) then
      Edits := Edits + [UsesEdit];
    if NeedsSysUtils and not TUsesClauses.IsUsed(Used, 'System.SysUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(Tokens, ACall.StartOffset, 'System.SysUtils', TTextLines.LineBreakOf(AContext.Text),
      UsesEdit) then
      Edits := Edits + [UsesEdit];
    Name := ReplacementText;
    if Pos('(', Name) > 0 then
      Name := Trim(Copy(Name, 1, Pos('(', Name) - 1));
    Result := [TRuleFix.Create(Format('Durch %s ersetzen', [Name]), Edits)];
  end;

  procedure CheckCall(ANode, ACallee: TSyntaxNode);
  var
    Name, TypeName: string;
    First: Integer;
    Reading: Boolean;
    Found: TArray<TRuleFix>;
  begin
    Name := ACallee.Name;
    if not MatchText(Name, ConsoleRoutines) or MatchText(Name, Declared) then
      Exit;
    if (SameText(Name, 'Write') or SameText(Name, 'Read')) and InMethod(ANode) then
      Exit;
    First := 1;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) then
    begin
      // Erstes Argument eine Datei: kein Konsolenzugriff.
      if (ANode[1].Kind = TSyntaxKind.Identifier) and MatchText(ANode[1].Name, StandardFiles) then
        First := 2
      else
      begin
        TypeName := DeclaredTypeOf(ANode[1]);
        if MatchText(TypeName, FileTypes) or StartsText('file ', TypeName) then
          Exit;
        if (ANode[1].Kind = TSyntaxKind.Identifier) and (TypeName = '') and (ANode.ChildCount > 2) then
          Exit;
      end;
    end;
    if Guarded(ANode) then
      Exit;
    Reading := SameText(Name, 'Read') or SameText(Name, 'Readln');
    if Reading then
    begin
      Found := nil;
      AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), Format('Das Projekt hat keine Konsole; ' +
        '%s löst zur Laufzeit E/A-Fehler 104 aus.', [Text(ACallee)]), TRuleConfidence.High, Found);
    end
    else
      AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), Format('Das Projekt hat keine Konsole; ' +
        '%s löst zur Laufzeit E/A-Fehler 105 aus.', [Text(ACallee)]), TRuleConfidence.High, Fixes(ANode, First));
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Identifier) then
      CheckCall(ANode, ANode[0])
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) then
      CheckCall(ANode[0], ANode[0]);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Kind: TRuleApplicationKind;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Kind := AContext.Application;
  // Ohne Projekt nur die .dpr selbst: program ohne {$APPTYPE CONSOLE}.
  if Kind = TRuleApplicationKind.Unknown then
    Kind := ApplicationKind('', AContext.Text);
  if Kind <> TRuleApplicationKind.Gui then
    Exit;
  Tokens := AContext.Tree.Tokens;
  ReplacementText := Replacement(AContext.Options);
  Declared := nil;
  CollectDeclared(AContext.Tree.Root);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TUncheckedConversionRule }

type
  /// <summary>Umwandlung mit Try-Gegenstück: Zieltypen, die als out-Parameter passen, und Meldungstext.</summary>
  TCheckedConversion = record
    Name: string;
    Types: string;
    Problem: string;
  end;

const
  CheckedConversions: array[0..8] of TCheckedConversion = (
    (Name: 'StrToInt'; Types: ',integer,longint,'; Problem: 'ist keine Zahl'),
    (Name: 'StrToInt64'; Types: ',int64,'; Problem: 'ist keine Zahl'),
    (Name: 'StrToFloat'; Types: ',double,extended,single,'; Problem: 'ist keine Zahl'),
    (Name: 'StrToCurr'; Types: ',currency,'; Problem: 'ist kein Betrag'),
    (Name: 'StrToDate'; Types: ',tdatetime,'; Problem: 'ist kein Datum'),
    (Name: 'StrToDateTime'; Types: ',tdatetime,'; Problem: 'ist kein Zeitpunkt'),
    (Name: 'StrToTime'; Types: ',tdatetime,'; Problem: 'ist keine Uhrzeit'),
    (Name: 'StrToBool'; Types: ',boolean,'; Problem: 'ist kein Wahrheitswert'),
    (Name: 'StrToUInt'; Types: ',cardinal,longword,'; Problem: 'ist keine Zahl'));
  // Hüllen, durch die die Eingabe unverändert geprüft wird: StrToInt(Trim(Edit.Text)).
  TransparentCalls: array[0..3] of string = ('Trim', 'TrimLeft', 'TrimRight', 'Copy');

function TUncheckedConversionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unchecked-conversion', TRuleSeverity.Hint,
    'Umwandlung einer Benutzereingabe ohne Prüfung');
end;

procedure TUncheckedConversionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Functions, Sources: TArray<string>;
  Types: TDeclaredTypes;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Edit.Text, Grid.Cells[C, R], Memo.Lines[I], auch in Trim(…); nil, wenn das Argument keine Eingabe ist.
  function InputSource(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    while (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) do
      ANode := ANode[0];
    case ANode.Kind of
      TSyntaxKind.MemberAccess:
        if MatchText(ANode.Name, Sources) then
          Result := ANode;
      TSyntaxKind.IndexAccess:
        if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.MemberAccess) and MatchText(ANode.Name, Sources) then
          Result := ANode;
      TSyntaxKind.Call:
        if (ANode.ChildCount > 1) and MatchText(ANode.Name, TransparentCalls) then
          Result := InputSource(ANode[1]);
    end;
  end;

  // Im try-Teil eines try/except: die Fehleingabe wird abgefangen.
  function Caught(ANode: TSyntaxNode): Boolean;
  var
    Child, Parent: TSyntaxNode;
  begin
    Child := ANode;
    Parent := ANode.Parent;
    while (Parent <> nil) and not (Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    begin
      if (Parent.Kind = TSyntaxKind.TryStatement) and not (Child.Kind in [TSyntaxKind.ExceptBlock,
        TSyntaxKind.FinallyBlock]) and (Parent.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
        Exit(True);
      Child := Parent;
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  function ConversionOf(const AName: string; out AConversion: TCheckedConversion): Boolean;
  var
    Conversion: TCheckedConversion;
  begin
    for Conversion in CheckedConversions do
      if SameText(Conversion.Name, AName) then
      begin
        AConversion := Conversion;
        Exit(True);
      end;
    Result := False;
  end;

  // X := StrToInt(Edit.Text); als eigene Anweisung in einer Anweisungsliste, X eine Variable des
  // passenden Typs: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create('X ist keine Zahl').
  function Fixes(ACall, AArgument: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement, Target: TSyntaxNode;
    Conversion: TCheckedConversion;
    TypeName, Indent: string;
  begin
    Result := nil;
    Statement := ACall.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.AssignStatement) or (Statement.ChildCount <> 2) or
      (Statement[1] <> ACall) or (Statement.Parent = nil) or not (Statement.Parent.Kind in [TSyntaxKind.Block,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement,
      TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]) then
      Exit;
    Target := Statement[0];
    if (Target.Kind <> TSyntaxKind.Identifier) or not ConversionOf(ACall.Name, Conversion) then
      Exit;
    TypeName := LowerCase(Types.DeclaredType(Target.Name, Target.StartPos));
    if (TypeName = '') or (Pos(',' + TypeName + ',', Conversion.Types) = 0) then
      Exit;
    Indent := StringOfChar(' ', Statement.StartPos.Character);
    Result := [TRuleFix.Create('In Try' + Conversion.Name + ' mit Fehlerzweig umschreiben',
      [TRuleEdit.Create(TTextRange.Create(Statement.StartPos, Statement.EndPos), 'if not Try' + Conversion.Name +
      '(' + Text(AArgument) + ', ' + Target.Name + ') then' + LineBreak + Indent + '  raise EConvertError.Create(''' +
      Target.Name + ' ' + Conversion.Problem + ''')')])];
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Source: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and MatchText(ANode.Name, Functions) then
    begin
      Source := InputSource(ANode[1]);
      if (Source <> nil) and not Caught(ANode) then
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Eingabe aus %s ohne Prüfung ' +
          'umgewandelt; eine Fehleingabe löst EConvertError aus.', [Text(Source)]), TRuleConfidence.Medium,
          Fixes(ANode, ANode[1]));
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Defaults: TArray<string>;
  Name: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Defaults := nil;
  for Name in DefaultFunctions do
    Defaults := Defaults + [Name];
  Functions := TRuleOptions.Strings(AContext.Options, 'functions', Defaults);
  Defaults := nil;
  for Name in DefaultSources do
    Defaults := Defaults + [Name];
  Sources := TRuleOptions.Strings(AContext.Options, 'sources', Defaults);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInt32MulOverflowRule.Create);
  ARegistry.Register(TSizeOfPointerRule.Create);
  ARegistry.Register(TCharToPCharRule.Create);
  ARegistry.Register(TFloatEqualityRule.Create);
  ARegistry.Register(TConstructorOnInstanceRule.Create);
  ARegistry.Register(TFormatWithoutSettingsRule.Create);
  ARegistry.Register(TManagedTypeRawMemoryRule.Create);
  ARegistry.Register(TThreadvarManagedRule.Create);
  ARegistry.Register(TPCharOfTemporaryRule.Create);
  ARegistry.Register(TStringListUnsortedRule.Create);
  ARegistry.Register(TWritelnInGuiAppRule.Create);
  ARegistry.Register(TUncheckedConversionRule.Create);
end;

end.
