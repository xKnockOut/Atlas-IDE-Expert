unit Atlas.Common.Semantics.Attributes;

// Attribute im Quelltext (#119): [TestFixture], [DUnitX.Attributes.TestFixture],
// [TestCase('A', '1,2')]. Liefert zur Position den geschriebenen Namen und die
// Zahl der Argumente; die Namensauflösung sucht damit zuerst NameAttribute,
// dann Name. Names liefert die Namen eines Attribut-Knotens ohne Endung
// Attribute und ohne Unit, z. B. für die DUnitX-Regeln (#945).
// Opens und InBracket (#465) arbeiten nur auf Tokens, auch bei unfertigem Code
// ("[Te" vor einer Methode): Eine "[" eröffnet ein Attribut, wenn davor eine
// Deklaration enden oder beginnen kann (";", type, var, const, class, record,
// ")" hinter class(...) bzw. einer Parameterliste, "(" einer Parameterliste) oder
// sie am Zeilenanfang hinter einer Sichtbarkeit bzw. einem anderen Attribut
// steht. Mengen ("in [", "= ["), Array-Indizes ("A[") und die GUID eines
// Interfaces ("interface [") zählen nicht.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TAttributeUse = record
    /// <summary>Name wie geschrieben, ggf. qualifiziert (DUnitX.Attributes.TestFixture).</summary>
    Name: string;
    /// <summary>Bereich des Namens (alle Teile).</summary>
    NameRange: TTextRange;
    /// <summary>Zahl der Argumente, 0 ohne Klammern.</summary>
    ArgCount: Integer;
  end;

  TAttributes = class
  public
    /// <summary>Steht APosition auf dem Namen eines Attributs?</summary>
    class function At(ATree: TSyntaxTree; const APosition: TTextPosition; out AUse: TAttributeUse): Boolean; static;
    /// <summary>Klassennamen in Suchreihenfolge: NameAttribute, dann Name.</summary>
    class function ClassNames(const AName: string): TArray<string>; static;
    /// <summary>Namen der Attribute im Knoten AAttribute ([Test, TestCase('a', '1')] → Test, TestCase): letzter
    /// Teil eines qualifizierten Namens, ohne Endung Attribute.</summary>
    class function Names(AAttribute: TSyntaxNode): TArray<string>; static;
    /// <summary>Eröffnet die "[" an AOpen ein Attribut (siehe oben)?</summary>
    class function Opens(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean; static;
    /// <summary>Steht ein Name hinter dem Token ALast ("[" bzw. "," einer Attributklammer) auf der Stelle
    /// eines Attributnamens? Nicht in den Argumenten eines Attributs.</summary>
    class function InBracket(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean; static;
    /// <summary>Name ohne Endung Attribute ("TestCaseAttribute" → "TestCase"); "Attribute" selbst bleibt.</summary>
    class function ShortName(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

function Contains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := Before(ANode.StartPos, APosition) and Before(APosition, ANode.EndPos);
end;

/// <summary>Name einer Bezeichner- bzw. Punktkette; '' bei anderen Ausdrücken.</summary>
function DottedName(ANode: TSyntaxNode): string;
var
  mSuffix: string;
begin
  // Iterativ (Bericht M1): von rechts nach links an der Kette entlang.
  mSuffix := '';
  while (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) do
  begin
    mSuffix := '.' + ANode.Name + mSuffix;
    ANode := ANode[0];
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name + mSuffix;
  end
  else
  begin
    Result := '';
  end;
end;

function FindAttribute(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ mit eigenem Stapel (Bericht M1), Reihenfolge wie die frühere Rekursion.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Attribute then
      begin
        Exit(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if Contains(mNode[mIndex], APosition) then
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
  Result := nil;
end;

class function TAttributes.At(ATree: TSyntaxTree; const APosition: TTextPosition; out AUse: TAttributeUse): Boolean;
var
  mAttribute, mItem, mNameNode: TSyntaxNode;
  mIndex: Integer;
begin
  AUse := Default(TAttributeUse);
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(False);
  end;
  mAttribute := FindAttribute(ATree.Root, APosition);
  if mAttribute = nil then
  begin
    Exit(False);
  end;
  for mIndex := 0 to mAttribute.ChildCount - 1 do
  begin
    mItem := mAttribute[mIndex];
    mNameNode := mItem;
    if (mItem.Kind = TSyntaxKind.Call) and (mItem.ChildCount > 0) then
    begin
      mNameNode := mItem[0];
    end;
    if not Contains(mNameNode, APosition) then
    begin
      Continue;
    end;
    AUse.Name := DottedName(mNameNode);
    if AUse.Name = '' then
    begin
      Exit(False);
    end;
    AUse.NameRange := TTextRange.Create(mNameNode.StartPos, mNameNode.EndPos);
    if mItem <> mNameNode then
    begin
      AUse.ArgCount := mItem.ChildCount - 1;
    end;
    Exit(True);
  end;
  Result := False;
end;

class function TAttributes.Names(AAttribute: TSyntaxNode): TArray<string>;
var
  mIndex, mDot: Integer;
  mItem: TSyntaxNode;
  mName: string;
begin
  Result := nil;
  if (AAttribute = nil) or (AAttribute.Kind <> TSyntaxKind.Attribute) then
  begin
    Exit;
  end;
  for mIndex := 0 to AAttribute.ChildCount - 1 do
  begin
    mItem := AAttribute[mIndex];
    if (mItem.Kind = TSyntaxKind.Call) and (mItem.ChildCount > 0) then
    begin
      mItem := mItem[0];
    end;
    mName := DottedName(mItem);
    if mName = '' then
    begin
      Continue;
    end;
    mDot := LastDelimiter('.', mName);
    mName := Copy(mName, mDot + 1, MaxInt);
    if EndsText('Attribute', mName) and (Length(mName) > Length('Attribute')) then
    begin
      mName := Copy(mName, 1, Length(mName) - Length('Attribute'));
    end;
    Result := Result + [mName];
  end;
end;

const
  /// <summary>Tiefe für Ketten wie [A] [B] [C] am Zeilenanfang.</summary>
  cMaxChainedBrackets = 16;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Öffnende Klammer zu der schließenden an AClose ("(" zu ")", "[" zu "]"); -1 ohne.</summary>
function OpeningOf(const ATokens: TArray<TPascalToken>; AClose: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AClose;
  while Result >= 0 do
  begin
    if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Dec(Result);
  end;
end;

/// <summary>Steht vor der "(" an AOpen der Kopf einer Routine ("procedure Foo(", "function TFoo.Bar(",
/// "reference to procedure(")?</summary>
function OpensParameters(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := PreviousIndex(ATokens, AOpen);
  while (mIndex >= 0) and ((ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or ATokens[mIndex].IsSymbol('.')) do
  begin
    mIndex := PreviousIndex(ATokens, mIndex);
  end;
  Result := (mIndex >= 0) and (ATokens[mIndex].IsKeyword('procedure') or ATokens[mIndex].IsKeyword('function') or
    ATokens[mIndex].IsKeyword('constructor') or ATokens[mIndex].IsKeyword('destructor') or
    ATokens[mIndex].IsKeyword('property'));
end;

/// <summary>Steht vor der "(" an AOpen class, record oder object (Vorfahrenliste)?</summary>
function OpensAncestors(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := PreviousIndex(ATokens, AOpen);
  Result := (mIndex >= 0) and (ATokens[mIndex].IsKeyword('class') or ATokens[mIndex].IsKeyword('object'));
end;

function IsVisibility(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and (SameText(AToken.Text, 'private') or
    SameText(AToken.Text, 'protected') or SameText(AToken.Text, 'public') or SameText(AToken.Text, 'published') or
    SameText(AToken.Text, 'automated'));
end;

const
  // Schlüsselwörter, hinter denen ein Attribut beginnen kann.
  cAttributeKeywords: array[0..7] of string = ('type', 'var', 'const', 'threadvar', 'class', 'record', 'object',
    'implementation');

function OpensAt(const ATokens: TArray<TPascalToken>; AOpen, ADepth: Integer): Boolean; forward;

/// <summary>Beginnt hinter dem Schlüsselwort ATokens[APrev] ein Attribut?</summary>
function OpensAfterKeyword(const ATokens: TArray<TPascalToken>; APrev: Integer): Boolean;
var
  mBefore: Integer;
  mKeyword: string;
begin
  // "IFoo = interface [" ist die GUID; "interface" als Abschnitt steht hinter "unit X;".
  if ATokens[APrev].IsKeyword('interface') or ATokens[APrev].IsKeyword('dispinterface') then
  begin
    mBefore := PreviousIndex(ATokens, APrev);
    Exit((mBefore < 0) or not ATokens[mBefore].IsSymbol('='));
  end;
  for mKeyword in cAttributeKeywords do
  begin
    if ATokens[APrev].IsKeyword(mKeyword) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>"TFoo = class(TBasis)" und darunter das Attribut eines Felds: ATokens[APrev] ist die ")".</summary>
function OpensAfterClose(const ATokens: TArray<TPascalToken>; APrev: Integer; ALineStart: Boolean): Boolean;
var
  mBefore: Integer;
begin
  mBefore := OpeningOf(ATokens, APrev);
  Result := ALineStart and (mBefore >= 0) and (OpensAncestors(ATokens, mBefore) or OpensParameters(ATokens, mBefore));
end;

/// <summary>Beginnt an AOpen ein Attribut, wenn davor das Nicht-Schlüsselwort ATokens[APrev] steht?</summary>
function OpensAfterToken(const ATokens: TArray<TPascalToken>; AOpen, APrev, ADepth: Integer): Boolean;
var
  mLineStart: Boolean;
begin
  mLineStart := ATokens[APrev].EndPos.Line < ATokens[AOpen].StartPos.Line;
  if ATokens[APrev].IsSymbol(';') then
  begin
    Result := True;
  end
  // Parameter: "procedure Foo([Ref] const A".
  else if ATokens[APrev].IsSymbol('(') then
  begin
    Result := OpensParameters(ATokens, APrev);
  end
  else if ATokens[APrev].IsSymbol(')') then
  begin
    Result := OpensAfterClose(ATokens, APrev, mLineStart);
  end
  // Sichtbarkeit und weitere Attribute nur am Zeilenanfang: "Private[0]" und "A[1][2]" sind Indizes.
  else if not mLineStart then
  begin
    Result := False;
  end
  else if ATokens[APrev].IsSymbol(']') then
  begin
    Result := OpensAt(ATokens, OpeningOf(ATokens, APrev), ADepth + 1);
  end
  else
  begin
    Result := IsVisibility(ATokens[APrev]);
  end;
end;

function OpensAt(const ATokens: TArray<TPascalToken>; AOpen, ADepth: Integer): Boolean;
var
  mPrev: Integer;
begin
  Result := False;
  if (AOpen < 0) or (AOpen > High(ATokens)) or not ATokens[AOpen].IsSymbol('[') or (ADepth > cMaxChainedBrackets) then
  begin
    Exit;
  end;
  mPrev := PreviousIndex(ATokens, AOpen);
  if mPrev < 0 then
  begin
    Result := True;
  end
  else if ATokens[mPrev].Kind = TPascalTokenKind.Keyword then
  begin
    Result := OpensAfterKeyword(ATokens, mPrev);
  end
  else
  begin
    Result := OpensAfterToken(ATokens, AOpen, mPrev, ADepth);
  end;
end;

class function TAttributes.Opens(const ATokens: TArray<TPascalToken>; AOpen: Integer): Boolean;
begin
  Result := OpensAt(ATokens, AOpen, 0);
end;

/// <summary>Ein Schritt der Suche nach der offenen "[": True beendet die Suche, AOpen sagt, ob AToken sie
/// ist.</summary>
function BracketScanStops(const AToken: TPascalToken; var ADepth: Integer; out AOpen: Boolean): Boolean;
begin
  AOpen := False;
  Result := False;
  if AToken.IsSymbol(')') or AToken.IsSymbol(']') then
  begin
    Inc(ADepth);
  end
  else if AToken.IsSymbol('(') or AToken.IsSymbol('[') then
  begin
    Result := ADepth = 0;
    AOpen := Result and AToken.IsSymbol('[');
    Dec(ADepth);
  end
  else
  begin
    Result := (ADepth = 0) and (AToken.IsSymbol(';') or (AToken.Kind = TPascalTokenKind.Keyword));
  end;
end;

/// <summary>Offene "[" vor ALast; -1, wenn vorher eine offene "(" (in den Argumenten) oder ein Satzende
/// steht.</summary>
function OpenBracketBefore(const ATokens: TArray<TPascalToken>; ALast: Integer): Integer;
var
  mDepth: Integer;
  mOpen: Boolean;
begin
  mDepth := 0;
  Result := PreviousIndex(ATokens, ALast);
  while Result >= 0 do
  begin
    if BracketScanStops(ATokens[Result], mDepth, mOpen) then
    begin
      if not mOpen then
      begin
        Result := -1;
      end;
      Exit;
    end;
    Result := PreviousIndex(ATokens, Result);
  end;
end;

class function TAttributes.InBracket(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean;
var
  mOpen: Integer;
begin
  if (ALast < 0) or (ALast > High(ATokens)) then
  begin
    Result := False;
  end
  else if ATokens[ALast].IsSymbol('[') then
  begin
    Result := Opens(ATokens, ALast);
  end
  else if ATokens[ALast].IsSymbol(',') then
  begin
    // Zur offenen "[" zurück; eine offene "(" davor heißt: in den Argumenten.
    mOpen := OpenBracketBefore(ATokens, ALast);
    Result := (mOpen >= 0) and Opens(ATokens, mOpen);
  end
  else
  begin
    Result := False;
  end;
end;

class function TAttributes.ShortName(const AName: string): string;
begin
  Result := AName;
  if EndsText('Attribute', Result) and (Length(Result) > Length('Attribute')) then
  begin
    Result := Copy(Result, 1, Length(Result) - Length('Attribute'));
  end;
end;

class function TAttributes.ClassNames(const AName: string): TArray<string>;
begin
  if EndsText('Attribute', AName) then
  begin
    Result := [AName];
  end
  else
  begin
    Result := [AName + 'Attribute', AName];
  end;
end;

end.
