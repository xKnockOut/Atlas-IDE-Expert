unit Atlas.Common.Rules.Builtin.Unused.Shared;

// Gemeinsame Hilfen der Regeln aus Atlas.Common.Rules.Builtin.Unused und ihrer Teil-Units Unused.Duplicates
// (duplicate-assignment) und Unused.EmptyRoutines (empty-routine): Namenslisten und Muster, Bereiche von
// Namen und ganzen Zeilen, Inline-Variablen und die Frage, ob die Signatur einer Methode von außen vorgegeben
// ist.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

/// <summary>Passt AName auf das Muster? * steht für beliebig viele, ? für genau ein Zeichen;
/// ohne Groß-/Kleinschreibung.</summary>
function MatchesWildcard(const AName, APattern: string): Boolean;

/// <summary>Muster aus {"ignore": [...]}.</summary>
function IgnorePatterns(const AOptions: string): TArray<string>;

/// <summary>Passt AName auf eines der Muster APatterns?</summary>
function IsIgnored(const AName: string; const APatterns: TArray<string>): Boolean;

/// <summary>Namen einer Liste "A, B, C" ohne Leerraum; leere Teile entfallen.</summary>
function SplitNames(const ANames: string): TArray<string>;

/// <summary>Letzter Teil eines Namens mit Punkten (TFoo.Bar → Bar).</summary>
function ShortName(const AName: string): string;

/// <summary>Kommt der Bezeichner AName in ANode oder darunter vor?</summary>
function MentionsName(ANode: TSyntaxNode; const AName: string): Boolean;

/// <summary>Erweitert [AStart, AEnd) auf ganze Zeilen; False, wenn davor oder dahinter noch etwas steht.</summary>
function WholeLines(const AText: string; AStart, AEnd: Integer; out ALineStart, ALineEnd: Integer): Boolean;

/// <summary>Bezeichner-Token im Bereich [AStart, AEnd) mit diesem Text.</summary>
function FindToken(const AContext: TRuleContext; AStart, AEnd: Integer; const AName: string;
  out AToken: TPascalToken): Boolean;

/// <summary>Bereich des Namens AName in ANode; ohne Fund der ganze Knoten.</summary>
function NameRange(const AContext: TRuleContext; ANode: TSyntaxNode; const AName: string): TTextRange;

/// <summary>Inline-Variablen eines Rumpfs, ohne lokale Routinen und anonyme Methoden.</summary>
procedure CollectInlineVars(ANode: TSyntaxNode; var AVars: TArray<TSyntaxNode>);

/// <summary>Rumpf (Klasse, Record, Objekt, Helfer) des Typs ATypeName unter ANode; nil ohne.</summary>
function FindTypeBody(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;

/// <summary>Typname der Methode AQualifiedName ohne Typparameter und äußere Typen (TFoo&lt;T&gt;.Bar → TFoo,
/// TAussen.TInnen.Bar → TInnen).</summary>
function MethodTypeName(const AQualifiedName: string): string;

/// <summary>Nennt der Typ Interfaces (class(TBasis, IFoo) bzw. class(IFoo))? nil zählt nicht.</summary>
function ListsInterfaces(ATypeBody: TSyntaxNode): Boolean;

/// <summary>Trägt der Kopf AHeader eine der Direktiven ANames? nil zählt nicht.</summary>
function HasDirectiveIn(AHeader: TSyntaxNode; const ANames: array of string): Boolean;

/// <summary>Ist die Signatur der Methode von außen vorgegeben (override, Interface, DFM …) oder unbekannt?</summary>
function MethodSignatureFixed(ARoot: TSyntaxNode; const AQualifiedName: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON;

function MatchesWildcard(const AName, APattern: string): Boolean;
var
  Name, Pattern: string;

  function Match(ANameIndex, APatternIndex: Integer): Boolean;
  begin
    while APatternIndex <= Length(Pattern) do
    begin
      if Pattern[APatternIndex] = '*' then
      begin
        while ANameIndex <= Length(Name) + 1 do
        begin
          if Match(ANameIndex, APatternIndex + 1) then
          begin
            Exit(True);
          end;
          Inc(ANameIndex);
        end;
        Exit(False);
      end;
      if (ANameIndex > Length(Name)) or ((Pattern[APatternIndex] <> '?') and
        (Pattern[APatternIndex] <> Name[ANameIndex])) then
      begin
        Exit(False);
      end;
      Inc(ANameIndex);
      Inc(APatternIndex);
    end;
    Result := ANameIndex > Length(Name);
  end;

begin
  Name := LowerCase(AName);
  Pattern := LowerCase(APattern);
  Result := Match(1, 1);
end;

function IgnorePatterns(const AOptions: string): TArray<string>;
var
  Value, Items, Item: TJSONValue;
begin
  Result := nil;
  if AOptions = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Items := TJSONObject(Value).GetValue('ignore');
    if Items is TJSONArray then
    begin
      for Item in TJSONArray(Items) do
      begin
        if Item is TJSONString then
        begin
          Result := Result + [Item.Value];
        end;
      end;
    end;
  finally
    Value.Free;
  end;
end;

function IsIgnored(const AName: string; const APatterns: TArray<string>): Boolean;
var
  Pattern: string;
begin
  for Pattern in APatterns do
  begin
    if MatchesWildcard(AName, Pattern) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function SplitNames(const ANames: string): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in SplitString(ANames, ',') do
  begin
    if Trim(Name) <> '' then
    begin
      Result := Result + [Trim(Name)];
    end;
  end;
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function MentionsName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.Identifier) and SameText(AVisited.Name, Name) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function WholeLines(const AText: string; AStart, AEnd: Integer; out ALineStart, ALineEnd: Integer): Boolean;
begin
  ALineStart := AStart;
  while (ALineStart > 0) and CharInSet(AText[ALineStart], [' ', #9]) do
  begin
    Dec(ALineStart);
  end;
  if (ALineStart > 0) and (AText[ALineStart] <> #10) then
  begin
    Exit(False);
  end;
  ALineEnd := AEnd;
  while (ALineEnd < Length(AText)) and CharInSet(AText[ALineEnd + 1], [' ', #9, #13]) do
  begin
    Inc(ALineEnd);
  end;
  if ALineEnd < Length(AText) then
  begin
    if AText[ALineEnd + 1] <> #10 then
    begin
      Exit(False);
    end;
    Inc(ALineEnd);
  end;
  Result := True;
end;

function FindToken(const AContext: TRuleContext; AStart, AEnd: Integer; const AName: string;
  out AToken: TPascalToken): Boolean;
var
  mIndex: Integer;
begin
  // Ab AStart statt ab Dateianfang und ohne Kopie je Token (#1323): je Deklaration und Routine aufgerufen.
  for mIndex := AContext.Tree.FirstTokenFrom(AStart) to High(AContext.Tree.Tokens) do
  begin
    if AContext.Tree.Tokens[mIndex].Offset >= AEnd then
    begin
      Break;
    end;
    if (AContext.Tree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      SameText(AContext.Tree.Tokens[mIndex].Text, AName) then
    begin
      AToken := AContext.Tree.Tokens[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

function NameRange(const AContext: TRuleContext; ANode: TSyntaxNode; const AName: string): TTextRange;
var
  Token: TPascalToken;
begin
  if FindToken(AContext, ANode.StartOffset, ANode.EndOffset, AName, Token) then
  begin
    Result := TTextRange.Create(Token.StartPos, Token.EndPos);
  end
  else
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;
end;

procedure CollectInlineVars(ANode: TSyntaxNode; var AVars: TArray<TSyntaxNode>);
var
  Vars: TArray<TSyntaxNode>;
begin
  // Iterativ (Bericht M1); var-Parameter lassen sich nicht in der anonymen Methode verwenden.
  Vars := AVars;
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := not (AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
      if Result and (AVisited.Kind = TSyntaxKind.InlineVar) then
      begin
        Vars := Vars + [AVisited];
      end;
    end);
  AVars := Vars;
end;

/// <summary>Rumpf (Klasse, Record, Objekt, Helfer) einer Typdeklaration, sonst nil.</summary>
function TypeBodyOf(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
      TSyntaxKind.HelperType] then
    begin
      Exit(ADecl[Index]);
    end;
  end;
  Result := nil;
end;

function FindTypeBody(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  TypeName: string;
  Decl: TSyntaxNode;
begin
  TypeName := ATypeName;
  // Iterativ (Bericht M1).
  Decl := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.TypeDecl) and SameText(AVisited.Name, TypeName) and
        (TypeBodyOf(AVisited) <> nil) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
  if Decl = nil then
  begin
    Result := nil;
  end
  else
  begin
    Result := TypeBodyOf(Decl);
  end;
end;

function MethodTypeName(const AQualifiedName: string): string;
begin
  Result := Copy(AQualifiedName, 1, LastDelimiter('.', AQualifiedName) - 1);
  // TFoo<T>.Bar und verschachtelte Typen: nur der letzte Typname zählt.
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := ShortName(Result);
end;

function ListsInterfaces(ATypeBody: TSyntaxNode): Boolean;
var
  mIndex, mCount: Integer;
  mName: string;
begin
  Result := False;
  if ATypeBody = nil then
  begin
    Exit;
  end;
  mCount := 0;
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    if ATypeBody[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Inc(mCount);
      mName := ATypeBody[mIndex].Name;
      Result := Result or (mCount > 1) or ((Length(mName) > 1) and (mName[1] = 'I') and
        CharInSet(mName[2], ['A'..'Z']));
    end;
  end;
end;

function HasDirectiveIn(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  Index: Integer;
begin
  if AHeader <> nil then
  begin
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ANames) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Ist ein Kopf namens AName im Typ published oder trägt override, virtual, dynamic, abstract oder
/// message?</summary>
function FixedMember(ATypeBody: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mMember: TSyntaxNode;
  mVisibility: string;
begin
  mVisibility := '';
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    mMember := ATypeBody[mIndex];
    if mMember.Kind = TSyntaxKind.Visibility then
    begin
      mVisibility := LowerCase(mMember.Name);
    end
    else if (mMember.Kind = TSyntaxKind.RoutineHeader) and SameText(mMember.Name, AName) and
      ((mVisibility = 'published') or HasDirectiveIn(mMember, ['override', 'virtual', 'dynamic', 'abstract',
      'message'])) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function MethodSignatureFixed(ARoot: TSyntaxNode; const AQualifiedName: string): Boolean;
var
  mBody: TSyntaxNode;
begin
  mBody := FindTypeBody(ARoot, MethodTypeName(AQualifiedName));
  // class(TBasis, IFoo) oder class(TInterfacedObject, IFoo): Methoden können ein Interface erfüllen.
  Result := (mBody = nil) or ListsInterfaces(mBody) or FixedMember(mBody, ShortName(AQualifiedName));
end;

end.
