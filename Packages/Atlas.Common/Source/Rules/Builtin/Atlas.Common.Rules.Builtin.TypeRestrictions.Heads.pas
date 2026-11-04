unit Atlas.Common.Rules.Builtin.TypeRestrictions.Heads;

// Gemeinsame Hilfen der Regeln aus TypeRestrictions (Operators, Generics, Records, Attributes, TypeInfo): Kopf einer
// Routine (TRoutineHead), Typdeklarationen der Datei (TFileTypes), Bereiche und Text von Knoten und Token.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract;

const
  // Eingebaute Typen, die sicher für sich stehen (kein Alias eines Typs der Datei).
  BuiltinTypeNames: array[0..33] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'ShortInt', 'SmallInt', 'LongInt', 'Byte', 'Word', 'LongWord', 'Int8', 'Int16', 'Int32', 'UInt8', 'UInt16',
    'UInt32', 'string', 'AnsiString', 'UnicodeString', 'WideString', 'ShortString', 'Char', 'AnsiChar', 'WideChar',
    'Single', 'Double', 'Extended', 'Currency', 'Real', 'Variant', 'Pointer', 'TDateTime');
  BooleanTypeNames: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');

type
  /// <summary>Kopf einer Routine aus Syntaxbaum und Token: Schlüsselwort, class, Parameter, Ergebnis.</summary>
  TRoutineHead = record
    Header: TSyntaxNode;
    /// <summary>procedure, function, constructor, destructor oder operator in Kleinbuchstaben.</summary>
    Keyword: string;
    /// <summary>Steht class davor (class procedure, class operator, class constructor)?</summary>
    IsClass: Boolean;
    /// <summary>Parameter-Knoten in Reihenfolge (ein Knoten kann mehrere Namen tragen).</summary>
    Parameters: TArray<TSyntaxNode>;
    /// <summary>Ergebnistyp oder nil.</summary>
    ResultType: TSyntaxNode;
    /// <summary>Typparameter der Routine oder nil.</summary>
    GenericParams: TSyntaxNode;
    /// <summary>Kopf aus dem Knoten AHeader (RoutineHeader) mit den Token der Datei.</summary>
    class function Read(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TRoutineHead; static;
    /// <summary>Zahl der Parameternamen ("A, B: T" zählt zwei).</summary>
    function ParameterCount: Integer;
    /// <summary>Trägt der Kopf die Direktive (virtual, static, inline …)?</summary>
    function HasDirective(const AName: string): Boolean;
    /// <summary>Knoten der Direktive oder nil.</summary>
    function Directive(const AName: string): TSyntaxNode;
  end;

  /// <summary>Typdeklarationen der Datei: Name, Knoten des Typs und Alias-Ziel.</summary>
  TFileTypes = record
    Names: TArray<string>;
    Types: TArray<TSyntaxNode>;
    /// <summary>Ziel bei type A = B (ohne type), sonst ''.</summary>
    AliasOf: TArray<string>;
    class function Collect(ARoot: TSyntaxNode): TFileTypes; static;
    /// <summary>Eintrag zu AName; eine vollständige Deklaration vor einer Vorwärtsdeklaration, -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Art der Deklaration AName in der Datei (ClassType, RecordType …); Error, wenn AName fehlt, ein
    /// Alias ist oder mehrdeutig deklariert ist.</summary>
    function DeclaredKind(const AName: string): TSyntaxKind;
    /// <summary>Namen, die denselben Typ meinen wie AName: AName und seine Aliase in der Datei.</summary>
    function SameNames(const AName: string): TArray<string>;
    /// <summary>Steht AName sicher für einen anderen Typ als die Namen in AOwn? Eingebaut oder in der Datei als
    /// eigener Typ (kein Alias) deklariert.</summary>
    function CertainlyOther(const AName: string; const AOwn: array of string): Boolean;
    /// <summary>Direkter Vorfahr der Klasse AName aus der Datei, '' ohne.</summary>
    function ParentOf(const AName: string): string;
  end;

/// <summary>Name ohne Unit-Präfix und ohne Typargumente: "System.TList&lt;T&gt;" ergibt "TList".</summary>
function BareTypeName(const AName: string): string;
/// <summary>Name des Typs, zu dem der Mitglieds-Kopf AHeader gehört ('' ohne).</summary>
function ContainerName(AHeader: TSyntaxNode): string;
/// <summary>Token des Namens im Kopf (bei TFoo.Bar das von Bar); -1 ohne.</summary>
function NameToken(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Integer;
function TokenRange(const AToken: TPascalToken): TTextRange;
function NodeRange(ANode: TSyntaxNode): TTextRange;
/// <summary>Text eines Knotens in einer Zeile, ohne doppelte Leerzeichen, für Meldungen.</summary>
function OneLine(const AText: string; ANode: TSyntaxNode): string;
/// <summary>Text eines Knotens ohne Zeilenumbrüche und doppelte Leerzeichen, für Vergleiche.</summary>
function Squeezed(const AText: string; ANode: TSyntaxNode): string;
/// <summary>Rümpfe AQualified (TFoo.Bar, auch TAussen.TFoo.Bar) mit gleicher Parameterliste und gleichem
/// Ergebnis wie AHead.</summary>
function ImplementationHeads(const AText: string; const ATokens: TArray<TPascalToken>; ARoot: TSyntaxNode;
  const AQualified: string; const AHead: TRoutineHead): TArray<TRoutineHead>;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Semantics.NameResolver;

function BareTypeName(const AName: string): string;
var
  Index: Integer;
begin
  Result := Trim(AName);
  Index := Pos('<', Result);
  if Index > 0 then
  begin
    Result := Copy(Result, 1, Index - 1);
  end;
  Index := LastDelimiter('.', Result);
  if Index > 0 then
  begin
    Result := Copy(Result, Index + 1, MaxInt);
  end;
  Result := Trim(Result);
end;

/// <summary>Kinder vom Typ Parameter unter AParameters in Reihenfolge.</summary>
function ParameterNodes(AParameters: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AParameters.ChildCount - 1 do
  begin
    if AParameters[Index].Kind = TSyntaxKind.Parameter then
    begin
      Result := Result + [AParameters[Index]];
    end;
  end;
end;

{ TRoutineHead }

class function TRoutineHead.Read(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TRoutineHead;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := Default(TRoutineHead);
  Result.Header := AHeader;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index < Length(ATokens)) and (ATokens[Index].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Index);
  end;
  if (Index < Length(ATokens)) and SameText(ATokens[Index].Text, 'class') then
  begin
    Result.IsClass := True;
    Index := TRoutineBody.NextToken(ATokens, Index);
  end;
  if (Index >= 0) and (Index < Length(ATokens)) then
  begin
    Result.Keyword := LowerCase(ATokens[Index].Text);
  end;
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    Child := AHeader[Index];
    case Child.Kind of
      TSyntaxKind.Parameters:
        Result.Parameters := Result.Parameters + ParameterNodes(Child);
      TSyntaxKind.TypeReference:
        Result.ResultType := Child;
      TSyntaxKind.GenericParams:
        if Result.GenericParams = nil then
        begin
          Result.GenericParams := Child;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

function TRoutineHead.ParameterCount: Integer;
var
  Parameter: TSyntaxNode;
begin
  Result := 0;
  for Parameter in Parameters do
  begin
    Inc(Result, Length(SplitString(Parameter.Name, ',')));
  end;
end;

function TRoutineHead.Directive(const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to Header.ChildCount - 1 do
  begin
    if (Header[Index].Kind = TSyntaxKind.Directive) and SameText(Header[Index].Name, AName) then
    begin
      Exit(Header[Index]);
    end;
  end;
  Result := nil;
end;

function TRoutineHead.HasDirective(const AName: string): Boolean;
begin
  Result := Directive(AName) <> nil;
end;

{ TFileTypes }

class function TFileTypes.Collect(ARoot: TSyntaxNode): TFileTypes;
var
  Types: TFileTypes;
begin
  Types := Default(TFileTypes);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Index: Integer;
      Target: string;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.TypeDecl) or (ANode.Name = '') then
      begin
        Exit;
      end;
      Target := '';
      for Index := 0 to ANode.ChildCount - 1 do
      begin
        if ANode[Index].Kind <> TSyntaxKind.GenericParams then
        begin
          if ANode[Index].Kind = TSyntaxKind.TypeReference then
          begin
            Target := ANode[Index].Name;
          end;
          Types.Names := Types.Names + [ANode.Name];
          Types.Types := Types.Types + [ANode[Index]];
          Types.AliasOf := Types.AliasOf + [Target];
          Break;
        end;
      end;
    end);
  Result := Types;
end;

function TFileTypes.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(Names) do
  begin
    if SameText(Names[Index], AName) then
    begin
      if Types[Index].Kind <> TSyntaxKind.ForwardType then
      begin
        Exit(Index);
      end;
      if Result < 0 then
      begin
        Result := Index;
      end;
    end;
  end;
end;

function TFileTypes.DeclaredKind(const AName: string): TSyntaxKind;
var
  Index: Integer;
  Found: Boolean;
begin
  Result := TSyntaxKind.Error;
  Found := False;
  for Index := 0 to High(Names) do
  begin
    if SameText(Names[Index], AName) and (Types[Index].Kind <> TSyntaxKind.ForwardType) then
    begin
      if (AliasOf[Index] <> '') or (Found and (Types[Index].Kind <> Result)) then
      begin
        Exit(TSyntaxKind.Error);
      end;
      Result := Types[Index].Kind;
      Found := True;
    end;
  end;
end;

function TFileTypes.SameNames(const AName: string): TArray<string>;
var
  Index: Integer;
  Changed: Boolean;
begin
  Result := [BareTypeName(AName)];
  repeat
    Changed := False;
    for Index := 0 to High(Names) do
    begin
      if (AliasOf[Index] <> '') and MatchText(BareTypeName(AliasOf[Index]), Result) and
        not MatchText(Names[Index], Result) then
      begin
        Result := Result + [Names[Index]];
        Changed := True;
      end;
    end;
  until not Changed;
end;

function TFileTypes.CertainlyOther(const AName: string; const AOwn: array of string): Boolean;
var
  Bare: string;
  Index: Integer;
begin
  Bare := BareTypeName(AName);
  if (Bare = '') or MatchText(Bare, AOwn) then
  begin
    Exit(False);
  end;
  Index := IndexOf(Bare);
  if Index >= 0 then
  begin
    Exit(AliasOf[Index] = '');
  end;
  Result := MatchText(Bare, BuiltinTypeNames) or MatchText(Bare, BooleanTypeNames);
end;

function TFileTypes.ParentOf(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := IndexOf(AName);
  if (Index >= 0) and (Types[Index].Kind = TSyntaxKind.ClassType) and (Types[Index].ChildCount > 0) and
    (Types[Index][0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := BareTypeName(Types[Index][0].Name);
  end;
end;

/// <summary>Name des Typs, zu dem der Mitglieds-Kopf AHeader gehört ('' ohne).</summary>
function ContainerName(AHeader: TSyntaxNode): string;
begin
  Result := '';
  if (AHeader.Parent <> nil) and (AHeader.Parent.Parent <> nil) and
    (AHeader.Parent.Parent.Kind = TSyntaxKind.TypeDecl) then
  begin
    Result := AHeader.Parent.Parent.Name;
  end;
end;

/// <summary>Token des Namens im Kopf (bei TFoo.Bar das von Bar); -1 ohne.</summary>
function NameToken(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Integer;
var
  Index, Last: Integer;
  Name: string;
begin
  Name := AHeader.Name;
  if LastDelimiter('.', Name) > 0 then
  begin
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  Last := -1;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index < Length(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol(':') or ATokens[Index].IsSymbol(';') or
      ATokens[Index].IsSymbol('<') then
    begin
      Break;
    end;
    if SameText(ATokens[Index].Text, Name) then
    begin
      Last := Index;
    end;
    Inc(Index);
  end;
  Result := Last;
end;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Text eines Knotens in einer Zeile, ohne doppelte Leerzeichen, für Meldungen.</summary>
function OneLine(const AText: string; ANode: TSyntaxNode): string;
var
  Text: string;
begin
  if ANode = nil then
  begin
    Exit('');
  end;
  Text := TRoutineBody.TextOf(AText, ANode);
  Text := StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  while Pos('  ', Text) > 0 do
  begin
    Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);
  end;
  Result := Trim(Text);
end;

/// <summary>Text eines Knotens ohne Zeilenumbrüche und doppelte Leerzeichen, für Vergleiche.</summary>
function Squeezed(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := LowerCase(OneLine(AText, ANode));
end;

/// <summary>Rümpfe AQualified (TFoo.Bar, auch TAussen.TFoo.Bar) mit gleicher Parameterliste und gleichem
/// Ergebnis wie AHead.</summary>
function ImplementationHeads(const AText: string; const ATokens: TArray<TPascalToken>; ARoot: TSyntaxNode;
  const AQualified: string; const AHead: TRoutineHead): TArray<TRoutineHead>;
var
  Found: TArray<TRoutineHead>;
  Params, ResultText: string;
begin
  Found := nil;
  Params := Squeezed(AText, AHead.Header.FindChild(TSyntaxKind.Parameters));
  ResultText := Squeezed(AText, AHead.ResultType);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Head: TRoutineHead;
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineHeader;
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and (SameText(ANode.Name, AQualified) or
        EndsText('.' + AQualified, ANode.Name)) then
      begin
        Head := TRoutineHead.Read(ATokens, ANode);
        if (Squeezed(AText, ANode.FindChild(TSyntaxKind.Parameters)) = Params) and
          (Squeezed(AText, Head.ResultType) = ResultText) then
        begin
          Found := Found + [Head];
        end;
      end;
    end);
  Result := Found;
end;

end.
