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

/// <summary>Registriert die typbasierten Regeln für RTL-Muster.</summary>
procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract;

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
end;

end.
