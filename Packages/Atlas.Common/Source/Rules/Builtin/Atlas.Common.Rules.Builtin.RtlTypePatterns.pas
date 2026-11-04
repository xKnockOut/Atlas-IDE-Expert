unit Atlas.Common.Rules.Builtin.RtlTypePatterns;

// Regeln für fehleranfällige RTL-Muster, Stufe 2 aus #153 (mit deklarierten
// Typen aus der Datei, Atlas.Common.Pascal.DeclaredTypes):
//   int32-mul-overflow       Int64 := Int32 * Int32 läuft vor der Zuweisung über
//   sizeof-pointer           Move/FillChar mit SizeOf eines Zeigers, Strings oder dynamischen Arrays
//   char-to-pchar            Cast eines Char nach PChar
//   float-equality           Gleitkommavergleich mit = oder <> (nicht mit 0, nicht in Equals-Vergleichern)
//   constructor-on-instance  Konstruktor auf einer Variablen statt auf der Klasse
//   writeln-in-gui-app       Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem
//                            Programm ohne Konsole (#926): E/A-Fehler 104 bzw. 105 zur Laufzeit
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

  TWritelnInGuiAppRule = class(TInterfacedObject, IRule)
  public const
    DefaultReplacement = 'OutputDebugString';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Anwendungsart aus DCC_ConsoleTarget der .dproj und dem Text der .dpr: Console bei
    /// "true" oder {$APPTYPE CONSOLE}, Service bei einem program mit Vcl.SvcMgr und ohne Vcl.Forms,
    /// sonst Gui bei einem program; Library_ bei einer library ohne Formulare und ohne Vcl.Forms,
    /// Package bei einem package, sonst Unknown (DLL mit Formularen, kein Text).</summary>
    class function ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind; static;
    /// <summary>Option "replacement" aus den Regeloptionen; ohne Angabe OutputDebugString.</summary>
    class function Replacement(const AOptions: string): string; static;
  end;

/// <summary>Registriert die typbasierten Regeln für RTL-Muster.</summary>
procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Memory,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Collections,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Conversions;

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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      // V := A * B; mit V: Int64 und A, B höchstens 32 Bit.
      if not Tokens[Index].IsSymbol(':=') then
      begin
        Continue;
      end;
      Target := PreviousCode(Tokens, Index);
      Left := NextCode(Tokens, Index + 1);
      Times := NextCode(Tokens, Left + 1);
      Right := NextCode(Tokens, Times + 1);
      Stop := NextCode(Tokens, Right + 1);
      if (Stop > High(Tokens)) or not Tokens[Times].IsSymbol('*') or not IsPlainIdentifier(Tokens, Target) or
        not IsPlainIdentifier(Tokens, Left) or not (IsPlainIdentifier(Tokens, Right) or
        (Tokens[Right].Kind = TPascalTokenKind.Number)) or
        not (Tokens[Stop].IsSymbol(';') or Tokens[Stop].IsKeyword('end') or Tokens[Stop].IsKeyword('else')) then
      begin
        Continue;
      end;
      if not TDeclaredTypes.IsInt64(Types.DeclaredType(Tokens[Target].Text, Tokens[Target].StartPos)) or
        not TDeclaredTypes.IsInt32(Types.DeclaredType(Tokens[Left].Text, Tokens[Left].StartPos)) or
        not ((Tokens[Right].Kind = TPascalTokenKind.Number) or
        TDeclaredTypes.IsInt32(Types.DeclaredType(Tokens[Right].Text, Tokens[Right].StartPos))) then
      begin
        Continue;
      end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(Tokens[Index].Text, ['Move', 'FillChar', 'ZeroMemory', 'CopyMemory', 'FillMemory'])) then
      begin
        Continue;
      end;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      begin
        Continue;
      end;
      Close := Closing(Tokens, Open);
      for Inner := Open + 1 to Close - 1 do
      begin
        if not SameText(Tokens[Inner].Text, 'SizeOf') then
        begin
          Continue;
        end;
        SizeOpen := NextCode(Tokens, Inner + 1);
        Name := NextCode(Tokens, SizeOpen + 1);
        SizeClose := NextCode(Tokens, Name + 1);
        if (SizeClose >= Close) or not Tokens[SizeOpen].IsSymbol('(') or not Tokens[SizeClose].IsSymbol(')') or
          (Tokens[Name].Kind <> TPascalTokenKind.Identifier) then
        begin
          Continue;
        end;
        TypeName := Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos);
        if (TypeName <> '') and TDeclaredTypes.IsReference(TypeName) then
        begin
          AReport.Add(RangeOf(Tokens, Inner, SizeClose), Format('SizeOf(%s) ist die Größe des Zeigers (%s), ' +
            'nicht die der Daten; Length(…) * SizeOf(Element) verwenden', [Tokens[Name].Text, TypeName]),
            TRuleConfidence.High);
        end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(Tokens[Index].Text, ['PChar', 'PWideChar', 'PAnsiChar'])) then
      begin
        Continue;
      end;
      Open := NextCode(Tokens, Index + 1);
      Name := NextCode(Tokens, Open + 1);
      Close := NextCode(Tokens, Name + 1);
      if (Close > High(Tokens)) or not Tokens[Open].IsSymbol('(') or not Tokens[Close].IsSymbol(')') or
        (Tokens[Name].Kind <> TPascalTokenKind.Identifier) then
      begin
        Continue;
      end;
      if TDeclaredTypes.IsChar(Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos)) then
      begin
        AReport.Add(RangeOf(Tokens, Index, Close), Format('%s(%s) macht aus dem Zeichen eine Adresse; ' +
          'gemeint ist meist ein String: %s(string(%s))', [Tokens[Index].Text, Tokens[Name].Text,
          Tokens[Index].Text, Tokens[Name].Text]), TRuleConfidence.High);
      end;
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

/// <summary>
/// Steht vor ATokens[AIndex] in derselben Routine "AName := Max(…)" bzw. Min(…) mit AOther unter den Argumenten?
/// Dann ist AName genau einer der Werte, und = AOther ist ein exakter Vergleich (MaxValue = R, #1109).
/// </summary>
function SelectedFrom(const ATokens: TTokens; AIndex: Integer; const AName, AOther: string): Boolean;
var
  Index, Call, Close, Inner: Integer;
begin
  Result := False;
  Index := AIndex - 1;
  while (Index >= 0) and not (ATokens[Index].IsKeyword('procedure') or ATokens[Index].IsKeyword('function') or
    ATokens[Index].IsKeyword('constructor') or ATokens[Index].IsKeyword('destructor')) do
  begin
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AName) then
    begin
      Call := NextCode(ATokens, NextCode(ATokens, Index + 1) + 1);
      if (Call <= High(ATokens)) and ATokens[NextCode(ATokens, Index + 1)].IsSymbol(':=') and
        MatchText(ATokens[Call].Text, ['Max', 'Min']) then
      begin
        Close := NextCode(ATokens, Call + 1);
        if (Close <= High(ATokens)) and ATokens[Close].IsSymbol('(') then
        begin
          for Inner := Close + 1 to High(ATokens) do
          begin
            if ATokens[Inner].IsSymbol(';') then
            begin
              Break;
            end;
            if (ATokens[Inner].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Inner].Text, AOther) then
            begin
              Exit(True);
            end;
          end;
        end;
        // Die letzte Zuweisung zählt.
        Exit;
      end;
    end;
    Dec(Index);
  end;
end;

/// <summary>Steht AOffset im Rumpf eines Gleichheitsvergleichers (Equals, Equals_Double, class operator Equal,
/// NotEqual, IsEqual)? Dort ist der exakte Vergleich Vertrag: Equals muss zu GetHashCode passen
/// (System.Generics.Defaults), eine Toleranz wäre nicht transitiv.</summary>
function InEqualityRoutine(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  mRoutine: TSyntaxNode;
  mName: string;
begin
  mRoutine := TRoutineBody.RoutineAt(ATree, AOffset);
  if mRoutine = nil then
  begin
    Exit(False);
  end;
  mName := mRoutine.Name;
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := StartsText('Equal', mName) or MatchText(mName, ['NotEqual', 'IsEqual']);
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not (Tokens[Index].IsSymbol('=') or Tokens[Index].IsSymbol('<>')) then
      begin
        Continue;
      end;
      Left := PreviousCode(Tokens, Index);
      Right := NextCode(Tokens, Index + 1);
      if (Left < 0) or (Right > High(Tokens)) or not InStatements(AContext.Tree, Tokens[Index].StartPos) then
      begin
        Continue;
      end;
      // Nur einfache Operanden: A = B, A <> 1.5; nicht Teil eines größeren Ausdrucks davor oder danach.
      Prev := PreviousCode(Tokens, Left);
      Next := NextCode(Tokens, Right + 1);
      if not ((Tokens[Left].Kind = TPascalTokenKind.Number) or IsPlainIdentifier(Tokens, Left)) or
        not ((Tokens[Right].Kind = TPascalTokenKind.Number) or IsPlainIdentifier(Tokens, Right)) or
        ((Prev >= 0) and (Tokens[Prev].Kind = TPascalTokenKind.Symbol) and
        MatchStr(Tokens[Prev].Text, ['+', '-', '*', '/'])) or
        ((Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Symbol) and
        MatchStr(Tokens[Next].Text, ['+', '-', '*', '/'])) or IsZero(Tokens[Left]) or IsZero(Tokens[Right]) then
      begin
        Continue;
      end;
      IsFloat := ((Tokens[Left].Kind = TPascalTokenKind.Identifier) and
        IsInexact(Types.DeclaredType(Tokens[Left].Text, Tokens[Left].StartPos))) or
        ((Tokens[Right].Kind = TPascalTokenKind.Identifier) and
        IsInexact(Types.DeclaredType(Tokens[Right].Text, Tokens[Right].StartPos)));
      if not IsFloat or SelectedFrom(Tokens, Index, Tokens[Left].Text, Tokens[Right].Text) or
        SelectedFrom(Tokens, Index, Tokens[Right].Text, Tokens[Left].Text) or
        InEqualityRoutine(AContext.Tree, Tokens[Index].Offset) then
      begin
        Continue;
      end;
      Call := 'SameValue(' + Tokens[Left].Text + ', ' + Tokens[Right].Text + ')';
      if Tokens[Index].IsSymbol('<>') then
      begin
        Call := 'not ' + Call;
      end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      Prev := PreviousCode(Tokens, Index);
      Dot := NextCode(Tokens, Index + 1);
      Ctor := NextCode(Tokens, Dot + 1);
      if (Ctor > High(Tokens)) or not Tokens[Dot].IsSymbol('.') or not SameText(Tokens[Ctor].Text, 'Create') or
        ((Prev >= 0) and (Tokens[Prev].IsSymbol('.') or Tokens[Prev].IsKeyword('inherited'))) then
      begin
        Continue;
      end;
      TypeName := Types.DeclaredType(Tokens[Index].Text, Tokens[Index].StartPos);
      // Klassenreferenzen (TComponentClass, class of …) dürfen Create aufrufen.
      if (TypeName = '') or not StartsStr('T', TypeName) or EndsText('Class', TypeName) or
        StartsText('class', TypeName) or (Pos('<', TypeName) > 0) or not InStatements(AContext.Tree,
        Tokens[Index].StartPos) then
      begin
        Continue;
      end;
      AReport.Add(RangeOf(Tokens, Index, Ctor), Format('Create auf der Variablen %s statt auf der Klasse %s; ' +
        'das legt kein neues Objekt an', [Tokens[Index].Text, TypeName]), TRuleConfidence.High,
        [TRuleFix.Create(TypeName + '.Create verwenden', [TRuleEdit.Create(RangeOf(Tokens, Index, Index),
        TypeName)])]);
    end;
  finally
    Types.Free;
  end;
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
  First, ServiceManager, Forms, FormMarker, AfterFileName: Boolean;
  Directive: string;
begin
  if SameText(Trim(AConsoleTarget), 'true') then
  begin
    Exit(TRuleApplicationKind.Console);
  end;
  Result := TRuleApplicationKind.Unknown;
  Tokens := TPascalLexer.Tokenize(AMainSource);
  First := True;
  ServiceManager := False;
  Forms := False;
  FormMarker := False;
  AfterFileName := False;
  for Token in Tokens do
    case Token.Kind of
      TPascalTokenKind.Directive:
        begin
          // {$APPTYPE CONSOLE} oder (*$APPTYPE CONSOLE*), auch in {$IFDEF}: dann gilt Konsole.
          Directive := UpperCase(Token.Text);
          Directive := StringReplace(StringReplace(Directive, '(*$', '', []), '{$', '', []);
          if StartsText('APPTYPE', Trim(Directive)) and ContainsText(Directive, 'CONSOLE') then
          begin
            Exit(TRuleApplicationKind.Console);
          end;
        end;
      TPascalTokenKind.Comment:
        // Unit1 in 'Unit1.pas' {Form1}: die IDE markiert Formulare ohne Doppelpunkt, andere Designer
        // als {Name: TDataModule} (#1060).
        if AfterFileName and StartsStr('{', Token.Text) and
          ((Pos(':', Token.Text) = 0) or ContainsText(Token.Text, ': TForm')) then
        begin
          FormMarker := True;
        end;
    else
      AfterFileName := Token.Kind = TPascalTokenKind.StringLiteral;
      if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'SvcMgr') then
      begin
        ServiceManager := True;
      end;
      if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Forms') then
      begin
        Forms := True;
      end;
      if First then
      begin
        First := False;
        if Token.IsKeyword('program') then
        begin
          Result := TRuleApplicationKind.Gui;
        end
        else if Token.IsKeyword('library') then
        begin
          Result := TRuleApplicationKind.Library_;
        end
        // package ist kein reserviertes Wort (#943).
        else if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'package') then
        begin
          Exit(TRuleApplicationKind.Package);
        end
        else
        begin
          Exit(TRuleApplicationKind.Unknown);
        end;
      end;
    end;
  // Ein Dienst bindet Vcl.SvcMgr ein; mit Vcl.Forms daneben startet dasselbe Programm auch mit Oberfläche.
  if (Result = TRuleApplicationKind.Gui) and ServiceManager and not Forms then
  begin
    Result := TRuleApplicationKind.Service;
  end;
  if (Result = TRuleApplicationKind.Library_) and (Forms or FormMarker) then
  begin
    Result := TRuleApplicationKind.Unknown;
  end;
end;

class function TWritelnInGuiAppRule.Replacement(const AOptions: string): string;
var
  Value: TJSONValue;
begin
  Result := DefaultReplacement;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if (Value is TJSONObject) and TJSONObject(Value).TryGetValue<string>('replacement', Result) and
      (Trim(Result) = '') then
    begin
      Result := DefaultReplacement;
    end;
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
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
        begin
          Name := Node.Name;
          if Pos('.', Name) > 0 then
          begin
            Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
          end;
          Declared := Declared + [Name];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function DeclaredTypeOf(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode.Kind = TSyntaxKind.Identifier then
    begin
      Result := Types.DeclaredType(ANode.Name, ANode.StartPos);
    end;
  end;

  // Die Prüfung "if IsConsole then" zeigt, dass der Aufruf gewollt ist.
  function MentionsIsConsole(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, 'IsConsole') then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
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
      begin
        Exit(True);
      end;
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
      begin
        Exit(True);
      end;
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  // AsString für Knoten ohne Unterausdrücke (Literal, Bezeichner, Aufruf); '' für alle anderen.
  function LeafAsString(ANode: TSyntaxNode): string;
  var
    TypeName: string;
  begin
    Result := '';
    case ANode.Kind of
      TSyntaxKind.Literal:
        if (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']) then
        begin
          Result := Text(ANode);
        end
        else
        begin
          Result := QuotedStr(Text(ANode));
        end;
      TSyntaxKind.Identifier:
        begin
          TypeName := DeclaredTypeOf(ANode);
          if MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'Char',
            'WideChar', 'AnsiChar', 'TFileName']) then
          begin
            Result := ANode.Name;
          end
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
        begin
          Result := Text(ANode);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // Argument als String-Ausdruck für die Korrektur; '' wenn der Typ nicht sicher ist.
  function AsString(ANode: TSyntaxNode): string;
  var
    Pending: TStack<TSyntaxNode>;
    Steps: TStack<Integer>;
    Values: TStack<string>;
    Node: TSyntaxNode;
    Step: Integer;
    Value: string;
  begin
    // Iterativ (Bericht M1): Verkettungen sind so tief wie lang. Steps zählt die schon ausgewerteten Kinder;
    // Values hält die Ergebnisse. Wie zuvor wertet + die rechte Seite nur aus, wenn die linke passt.
    Pending := TStack<TSyntaxNode>.Create;
    Steps := TStack<Integer>.Create;
    Values := TStack<string>.Create;
    try
      Pending.Push(ANode);
      Steps.Push(0);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Step := Steps.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and (Node.Name = '+') and (Node.ChildCount = 2) then
          case Step of
            0:
              begin
                Pending.Push(Node);
                Steps.Push(1);
                Pending.Push(Node[0]);
                Steps.Push(0);
              end;
            1:
              if Values.Pop = Text(Node[0]) then
              begin
                Pending.Push(Node);
                Steps.Push(2);
                Pending.Push(Node[1]);
                Steps.Push(0);
              end
              else
              begin
                Values.Push('');
              end;
          else
            if Values.Pop = Text(Node[1]) then
            begin
              Values.Push(Text(Node));
            end
            else
            begin
              Values.Push('');
            end;
          end
        else if (Node.Kind = TSyntaxKind.ParenExpr) and (Node.ChildCount = 1) then
        begin
          if Step = 0 then
          begin
            Pending.Push(Node);
            Steps.Push(1);
            Pending.Push(Node[0]);
            Steps.Push(0);
          end
          else
          begin
            Value := Values.Pop;
            if Value <> '' then
            begin
              Values.Push('(' + Value + ')');
            end
            else
            begin
              Values.Push('');
            end;
          end;
        end
        else
        begin
          Values.Push(LeafAsString(Node));
        end;
      end;
      Result := Values.Pop;
    finally
      Values.Free;
      Steps.Free;
      Pending.Free;
    end;
  end;

  // Breitenangaben wie X:5:2 lassen sich nicht in einen String übertragen.
  function HasWidth(ACall: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    // Binär zum ersten Token des Aufrufs statt ab Dateianfang (#1323).
    mIndex := TRoutineBody.TokenAt(Tokens, ACall.StartOffset);
    while (mIndex <= High(Tokens)) and (Tokens[mIndex].Offset < ACall.EndOffset) do
    begin
      if Tokens[mIndex].IsSymbol(':') then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
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
    begin
      Exit;
    end;
    NeedsSysUtils := False;
    Expression := '';
    for Index := AFirst to ACall.ChildCount - 1 do
    begin
      Part := AsString(ACall[Index]);
      if Part = '' then
      begin
        Exit;
      end;
      if Expression <> '' then
      begin
        Expression := Expression + ' + ';
      end;
      Expression := Expression + Part;
    end;
    if Pos('%s', ReplacementText) > 0 then
    begin
      NewText := StringReplace(ReplacementText, '%s', Expression, []);
    end
    else if SameText(ReplacementText, TWritelnInGuiAppRule.DefaultReplacement) then
    begin
      NewText := ReplacementText + '(PChar(' + Expression + '))';
    end
    else
    begin
      NewText := ReplacementText + '(' + Expression + ')';
    end;
    Edits := [TRuleEdit.Create(TTextRange.Create(ACall.StartPos, ACall.EndPos), NewText)];
    Used := TUsesClauses.UsedUnits(Tokens);
    if SameText(ReplacementText, TWritelnInGuiAppRule.DefaultReplacement) and
      not TUsesClauses.IsUsed(Used, 'Winapi.Windows', AContext.Namespaces) and
      TUsesClauses.AddUnit(Tokens, ACall.StartOffset, 'Winapi.Windows', TTextLines.LineBreakOf(AContext.Text),
      UsesEdit) then
    begin
      Edits := Edits + [UsesEdit];
    end;
    if NeedsSysUtils and not TUsesClauses.IsUsed(Used, 'System.SysUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(Tokens, ACall.StartOffset, 'System.SysUtils', TTextLines.LineBreakOf(AContext.Text),
      UsesEdit) then
    begin
      Edits := Edits + [UsesEdit];
    end;
    Name := ReplacementText;
    if Pos('(', Name) > 0 then
    begin
      Name := Trim(Copy(Name, 1, Pos('(', Name) - 1));
    end;
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
    begin
      Exit;
    end;
    if (SameText(Name, 'Write') or SameText(Name, 'Read')) and InMethod(ANode) then
    begin
      Exit;
    end;
    First := 1;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) then
    begin
      // Erstes Argument eine Datei: kein Konsolenzugriff.
      if (ANode[1].Kind = TSyntaxKind.Identifier) and MatchText(ANode[1].Name, StandardFiles) then
      begin
        First := 2;
      end
      else
      begin
        TypeName := DeclaredTypeOf(ANode[1]);
        if MatchText(TypeName, FileTypes) or StartsText('file ', TypeName) then
        begin
          Exit;
        end;
        if (ANode[1].Kind = TSyntaxKind.Identifier) and (TypeName = '') and (ANode.ChildCount > 2) then
        begin
          Exit;
        end;
      end;
    end;
    if Guarded(ANode) then
    begin
      Exit;
    end;
    Reading := SameText(Name, 'Read') or SameText(Name, 'Readln');
    if Reading then
    begin
      Found := nil;
      AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), Format('Das Projekt hat keine Konsole; ' +
        '%s löst zur Laufzeit E/A-Fehler 104 aus.', [Text(ACallee)]), TRuleConfidence.High, Found);
    end
    else
    begin
      AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), Format('Das Projekt hat keine Konsole; ' +
        '%s löst zur Laufzeit E/A-Fehler 105 aus.', [Text(ACallee)]), TRuleConfidence.High, Fixes(ANode, First));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and (Node[0].Kind = TSyntaxKind.Identifier) then
        begin
          CheckCall(Node, Node[0]);
        end
        else if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount = 1) and
          (Node[0].Kind = TSyntaxKind.Identifier) then
        begin
          CheckCall(Node[0], Node[0]);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Kind: TRuleApplicationKind;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Kind := AContext.Application;
  // Ohne Projekt nur die .dpr selbst: program ohne {$APPTYPE CONSOLE}.
  if Kind = TRuleApplicationKind.Unknown then
  begin
    Kind := ApplicationKind('', AContext.Text);
  end;
  // Auch ein Windows-Dienst hat keine Konsole (#1060).
  if (Kind <> TRuleApplicationKind.Gui) and (Kind <> TRuleApplicationKind.Service) then
  begin
    Exit;
  end;
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

procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInt32MulOverflowRule.Create);
  ARegistry.Register(TDelimitedTextWithoutStrictRule.Create);
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
  ARegistry.Register(TDictionaryGetWithoutCheckRule.Create);
  ARegistry.Register(TUncheckedEnumCastRule.Create);
  ARegistry.Register(TCreateProcessReadonlyCommandLineRule.Create);
  ARegistry.Register(TGlobalFormatSettingsModifiedRule.Create);
end;

end.
