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
  cBuiltinTypeNames: array[0..33] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'ShortInt', 'SmallInt', 'LongInt', 'Byte', 'Word', 'LongWord', 'Int8', 'Int16', 'Int32', 'UInt8', 'UInt16',
    'UInt32', 'string', 'AnsiString', 'UnicodeString', 'WideString', 'ShortString', 'Char', 'AnsiChar', 'WideChar',
    'Single', 'Double', 'Extended', 'Currency', 'Real', 'Variant', 'Pointer', 'TDateTime');
  cBooleanTypeNames: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');

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
  Atlas.Common.Editing.RoutineBody;

function BareTypeName(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(AName);
  mIndex := Pos('<', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, 1, mIndex - 1);
  end;
  mIndex := LastDelimiter('.', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, mIndex + 1, MaxInt);
  end;
  Result := Trim(Result);
end;

/// <summary>Kinder vom Typ Parameter unter AParameters in Reihenfolge.</summary>
function ParameterNodes(AParameters: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParameters.ChildCount - 1 do
  begin
    if AParameters[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      Result := Result + [AParameters[mIndex]];
    end;
  end;
end;

{ TRoutineHead }

class function TRoutineHead.Read(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TRoutineHead;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := Default(TRoutineHead);
  Result.Header := AHeader;
  mIndex := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (mIndex < Length(ATokens)) and (ATokens[mIndex].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(mIndex);
  end;
  if (mIndex < Length(ATokens)) and SameText(ATokens[mIndex].Text, 'class') then
  begin
    Result.IsClass := True;
    mIndex := TRoutineBody.NextToken(ATokens, mIndex);
  end;
  if (mIndex >= 0) and (mIndex < Length(ATokens)) then
  begin
    Result.Keyword := LowerCase(ATokens[mIndex].Text);
  end;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    mChild := AHeader[mIndex];
    case mChild.Kind of
      TSyntaxKind.Parameters:
        Result.Parameters := Result.Parameters + ParameterNodes(mChild);
      TSyntaxKind.TypeReference:
        Result.ResultType := mChild;
      TSyntaxKind.GenericParams:
        if Result.GenericParams = nil then
        begin
          Result.GenericParams := mChild;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

function TRoutineHead.ParameterCount: Integer;
var
  mParameter: TSyntaxNode;
begin
  Result := 0;
  for mParameter in Parameters do
  begin
    Inc(Result, Length(SplitString(mParameter.Name, ',')));
  end;
end;

function TRoutineHead.Directive(const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Header.ChildCount - 1 do
  begin
    if (Header[mIndex].Kind = TSyntaxKind.Directive) and SameText(Header[mIndex].Name, AName) then
    begin
      Exit(Header[mIndex]);
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
  mTypes: TFileTypes;
begin
  mTypes := Default(TFileTypes);
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
          mTypes.Names := mTypes.Names + [ANode.Name];
          mTypes.Types := mTypes.Types + [ANode[Index]];
          mTypes.AliasOf := mTypes.AliasOf + [Target];
          Break;
        end;
      end;
    end);
  Result := mTypes;
end;

function TFileTypes.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Names) do
  begin
    if SameText(Names[mIndex], AName) then
    begin
      if Types[mIndex].Kind <> TSyntaxKind.ForwardType then
      begin
        Exit(mIndex);
      end;
      if Result < 0 then
      begin
        Result := mIndex;
      end;
    end;
  end;
end;

function TFileTypes.DeclaredKind(const AName: string): TSyntaxKind;
var
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := TSyntaxKind.Error;
  mFound := False;
  for mIndex := 0 to High(Names) do
  begin
    if SameText(Names[mIndex], AName) and (Types[mIndex].Kind <> TSyntaxKind.ForwardType) then
    begin
      if (AliasOf[mIndex] <> '') or (mFound and (Types[mIndex].Kind <> Result)) then
      begin
        Exit(TSyntaxKind.Error);
      end;
      Result := Types[mIndex].Kind;
      mFound := True;
    end;
  end;
end;

function TFileTypes.SameNames(const AName: string): TArray<string>;
var
  mIndex: Integer;
  mChanged: Boolean;
begin
  Result := [BareTypeName(AName)];
  repeat
    mChanged := False;
    for mIndex := 0 to High(Names) do
    begin
      if (AliasOf[mIndex] <> '') and MatchText(BareTypeName(AliasOf[mIndex]), Result) and
        not MatchText(Names[mIndex], Result) then
      begin
        Result := Result + [Names[mIndex]];
        mChanged := True;
      end;
    end;
  until not mChanged;
end;

function TFileTypes.CertainlyOther(const AName: string; const AOwn: array of string): Boolean;
var
  mBare: string;
  mIndex: Integer;
begin
  mBare := BareTypeName(AName);
  if (mBare = '') or MatchText(mBare, AOwn) then
  begin
    Exit(False);
  end;
  mIndex := IndexOf(mBare);
  if mIndex >= 0 then
  begin
    Exit(AliasOf[mIndex] = '');
  end;
  Result := MatchText(mBare, cBuiltinTypeNames) or MatchText(mBare, cBooleanTypeNames);
end;

function TFileTypes.ParentOf(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := IndexOf(AName);
  if (mIndex >= 0) and (Types[mIndex].Kind = TSyntaxKind.ClassType) and (Types[mIndex].ChildCount > 0) and
    (Types[mIndex][0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := BareTypeName(Types[mIndex][0].Name);
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
  mIndex, mLast: Integer;
  mName: string;
begin
  mName := AHeader.Name;
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  mLast := -1;
  mIndex := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (mIndex < Length(ATokens)) and (ATokens[mIndex].Offset < AHeader.EndOffset) do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol(':') or ATokens[mIndex].IsSymbol(';') or
      ATokens[mIndex].IsSymbol('<') then
    begin
      Break;
    end;
    if SameText(ATokens[mIndex].Text, mName) then
    begin
      mLast := mIndex;
    end;
    Inc(mIndex);
  end;
  Result := mLast;
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
  mText: string;
begin
  if ANode = nil then
  begin
    Exit('');
  end;
  mText := TRoutineBody.TextOf(AText, ANode);
  mText := StringReplace(StringReplace(mText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  while Pos('  ', mText) > 0 do
  begin
    mText := StringReplace(mText, '  ', ' ', [rfReplaceAll]);
  end;
  Result := Trim(mText);
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
  mFound: TArray<TRoutineHead>;
  mParams, mResultText: string;
begin
  mFound := nil;
  mParams := Squeezed(AText, AHead.Header.FindChild(TSyntaxKind.Parameters));
  mResultText := Squeezed(AText, AHead.ResultType);
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
        if (Squeezed(AText, ANode.FindChild(TSyntaxKind.Parameters)) = mParams) and
          (Squeezed(AText, Head.ResultType) = mResultText) then
        begin
          mFound := mFound + [Head];
        end;
      end;
    end);
  Result := mFound;
end;

end.
