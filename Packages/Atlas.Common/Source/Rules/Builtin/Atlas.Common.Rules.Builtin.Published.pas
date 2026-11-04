unit Atlas.Common.Rules.Builtin.Published;

// Mitglieder im published-Abschnitt einer Klasse (#909, Gruppe Compiler vorab):
//   published-type-invalid  Was das Streaming nicht veröffentlichen kann
//                           (#1004): Property vom Typ statisches Array,
//                           Zeiger oder Prozedurtyp ohne "of object" (E2188;
//                           Records und dynamische Arrays übersetzt dcc,
//                           PU1-PU3 im dcc-Lauf vom 29.10.2026, #1328), Real48
//                           (E2186), Menge über 4 Byte (E2187), Feld, das
//                           keine Klasse und kein Interface ist (E2217), mehr
//                           als eine published-Überladung (E2266),
//                           Klassen-Property (E2545) und Nicht-ASCII-Zeichen
//                           im Namen (E2452).
//
// Die Regel prüft nur Mitglieder hinter einem ausdrücklichen "published". Der
// Abschnitt ohne Angabe ist zwar bei {$M+} bzw. Nachfahren von TPersistent
// ebenfalls published, dort stuft der Compiler unpassende Mitglieder aber
// still zu public herab. Typen löst sie über die Datei und den Index auf
// (Aliase bis zum Ziel, Typparameter der Klasse passen zu allem); was sich
// nicht sicher auflösen lässt, bleibt still, ebenso ein Abschnitt, dessen
// "published" in einem anderen Zweig der bedingten Übersetzung steht als das
// Mitglied. Überladungen in sich ausschließenden Zweigen zählen nicht doppelt.
//
// Korrektur: "In den public-Abschnitt verschieben" setzt die Zeilen des
// Mitglieds vor das "published", unter ein vorhandenes oder neues "public".

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  PublishedTypeInvalidRuleId = 'published-type-invalid';

type
  TPublishedTypeInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPublishedRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Lines;

type
  /// <summary>Was ein Typ für den published-Abschnitt ist.</summary>
  TPublishKind = (
    /// <summary>Nicht sicher aufzulösen: keine Aussage.</summary>
    Unknown,
    /// <summary>Klasse oder Interface: als Feld und Property erlaubt.</summary>
    ClassOrInterface,
    /// <summary>Ordinal, String, Gleitkomma, Variant, Methodenzeiger, kleine Menge: nur als Property.</summary>
    Simple,
    /// <summary>Record: als Property erlaubt, als Feld nicht.</summary>
    RecordKind,
    /// <summary>Dynamisches Array (array of, TArray&lt;T&gt;): als Property erlaubt, als Feld nicht.</summary>
    DynArrayKind,
    /// <summary>Statisches Array.</summary>
    ArrayKind,
    PointerKind,
    ProcedureKind,
    Real48Kind,
    /// <summary>Menge über 4 Byte.</summary>
    LargeSet);

const
  /// <summary>Eingebaute Typen, die als Property veröffentlicht werden können (Kleinbuchstaben).</summary>
  SimpleTypes: array[0..41] of string = ('integer', 'cardinal', 'shortint', 'smallint', 'longint', 'longword',
    'int64', 'uint64', 'byte', 'word', 'nativeint', 'nativeuint', 'fixedint', 'fixeduint', 'boolean', 'bytebool',
    'wordbool', 'longbool', 'char', 'ansichar', 'widechar', 'string', 'ansistring', 'widestring', 'unicodestring',
    'shortstring', 'rawbytestring', 'utf8string', 'single', 'double', 'extended', 'real', 'comp', 'currency',
    'variant', 'olevariant', 'tdatetime', 'tdate', 'ttime', 'uint32', 'int32', 'tcolor');
  PointerTypes: array[0..4] of string = ('pointer', 'pchar', 'pansichar', 'pwidechar', 'pbyte');
  /// <summary>Records aus System.Types bzw. Winapi.Windows, wenn die Unit sie einbindet und der Index sie nicht
  /// kennt.</summary>
  TypesRecords: array[0..6] of string = ('tpoint', 'trect', 'tsize', 'tpointf', 'trectf', 'tsizef', 'tsmallpoint');
  TypesUnits: array[0..3] of string = ('system.types', 'types', 'winapi.windows', 'windows');

function IsAscii(const AText: string): Boolean;
var
  Ch: Char;
begin
  for Ch in AText do
  begin
    if Ord(Ch) > 127 then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Typname ohne Unit und ohne Typargumente ("System.Types.TPointF" wird "TPointF").</summary>
function BareTypeName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Trim(Copy(Result, LastDelimiter('.', Result) + 1, MaxInt));
end;

/// <summary>Text hinter dem ersten "=" einer Typdeklaration ("TZahlen = array of Integer" wird
/// "array of Integer"); ohne führendes "type" und "packed".</summary>
function AliasTarget(const ASignature: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(ASignature) do
  begin
    if ASignature[Index] = '<' then
    begin
      Inc(Depth);
    end
    else if ASignature[Index] = '>' then
    begin
      Dec(Depth);
    end
    else if (ASignature[Index] = '=') and (Depth = 0) then
    begin
      Result := Trim(Copy(ASignature, Index + 1, MaxInt));
      Break;
    end;
  end;
  if StartsText('type ', Result) then
  begin
    Result := Trim(Copy(Result, 6, MaxInt));
  end;
  if StartsText('packed ', Result) then
  begin
    Result := Trim(Copy(Result, 8, MaxInt));
  end;
end;

/// <summary>Nur ein Typname wie "TArray&lt;TVektor&gt;" oder "System.Integer" (der Index trennt Token durch
/// Leerzeichen)?</summary>
function IsTypeName(const AText: string): Boolean;
var
  Ch: Char;
begin
  Result := (AText <> '') and CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']);
  for Ch in AText do
  begin
    if not CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '<', '>', ',', ' ']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Ordinalwert eines Literals (Zahl oder Zeichen 'a'); False, wenn es keins ist.</summary>
function OrdinalLiteral(const AText: string; out AValue: Integer): Boolean;
var
  Text: string;
begin
  Text := Trim(AText);
  if (Length(Text) = 3) and (Text[1] = '''') and (Text[3] = '''') then
  begin
    AValue := Ord(Text[2]);
    Exit(True);
  end;
  Result := TryStrToInt(Text, AValue) and (AValue >= 0);
end;

/// <summary>Beginnt der Aliastext mit dem Wort "array"?</summary>
function IsArrayTarget(const ATarget: string): Boolean;
begin
  Result := StartsText('array', ATarget) and ((Length(ATarget) = 5) or not CharInSet(ATarget[6], ['A'..'Z',
    'a'..'z', '0'..'9', '_']));
end;

/// <summary>"array of …" ist dynamisch, "array[…] of …" statisch.</summary>
function ArrayTargetKind(const ATarget: string): TPublishKind;
begin
  if StartsText('of ', Trim(Copy(ATarget, 6, MaxInt))) then
  begin
    Result := TPublishKind.DynArrayKind;
  end
  else
  begin
    Result := TPublishKind.ArrayKind;
  end;
end;

/// <summary>Prozedurtyp: mit "of object" (Ereignis) zulässig. Das Merkmal aus dem Index gilt auch, wenn die
/// Signatur vor "of object" abgeschnitten ist (#1326).</summary>
function RoutineTargetKind(const ALocation: TSymbolLocation; const ATarget: string): TPublishKind;
begin
  if ALocation.Symbol.HasDirective('of object') or ContainsText(ATarget, ' of object') then
  begin
    Result := TPublishKind.Simple;
  end
  else
  begin
    Result := TPublishKind.ProcedureKind;
  end;
end;

/// <summary>Menge mit Werten, die die Bytes AFirstByte bis ALastByte belegen: bis 4 Byte Simple.</summary>
function ByteSpanKind(AFirstByte, ALastByte: Integer): TPublishKind;
begin
  if ALastByte - AFirstByte + 1 > 4 then
  begin
    Result := TPublishKind.LargeSet;
  end
  else
  begin
    Result := TPublishKind.Simple;
  end;
end;

/// <summary>Menge über eine Aufzählung "(a, b, …)" ohne feste Werte; mit "=" Unknown. Count Werte ab 0 belegen
/// die Bytes 0 bis (Count - 1) div 8.</summary>
function EnumSetKind(const AEnum: string): TPublishKind;
begin
  if (AEnum = '') or (AEnum[1] <> '(') or (Pos('=', AEnum) > 0) then
  begin
    Exit(TPublishKind.Unknown);
  end;
  Result := ByteSpanKind(0, (Length(AEnum.Split([','])) - 1) div 8);
end;

/// <summary>Menge über einen Teilbereich "0..40"; eine Menge belegt die Bytes von Low div 8 bis High div 8.</summary>
function RangeSetKind(const ARange: string): TPublishKind;
var
  mLow, mHigh: Integer;
begin
  if not OrdinalLiteral(Copy(ARange, 1, Pos('..', ARange) - 1), mLow) or
    not OrdinalLiteral(Copy(ARange, Pos('..', ARange) + 2, MaxInt), mHigh) or (mHigh < mLow) then
  begin
    Exit(TPublishKind.Unknown);
  end;
  Result := ByteSpanKind(mLow div 8, mHigh div 8);
end;

function TPublishedTypeInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PublishedTypeInvalidRuleId, TRuleSeverity.Error,
    'Unzulässiges Mitglied im published-Abschnitt');
end;

type
  /// <summary>Ein Lauf der Regel über eine Unit.</summary>
  TPublishedScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FLines: TArray<string>;
    FLineBreak: string;
    FUsesTypes: Boolean;
    function TokenAt(AOffset: Integer): Integer;
    function PathOf(ANode: TSyntaxNode): string;
    function SourceOf(ANode: TSyntaxNode): string;
    function NodeRange(ANode: TSyntaxNode): TTextRange;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function Ambiguous(const AName: string): Boolean;
    function NamedKind(const AName: string; const AWildcards: TArray<string>; ADepth: Integer): TPublishKind;
    function UnresolvedKind(const AName, ALower: string): TPublishKind;
    function SymbolKind(const ALocation: TSymbolLocation; ADepth: Integer): TPublishKind;
    function AliasKind(const ALocation: TSymbolLocation; const ATarget: string; ADepth: Integer): TPublishKind;
    function SetKind(const ABase: string; ADepth: Integer): TPublishKind;
    function NamedSetKind(const ABase: string; ADepth: Integer): TPublishKind;
    function TypeKind(ATypeNode: TSyntaxNode; const AWildcards: TArray<string>): TPublishKind;
    function MoveToPublic(AMember, APublished: TSyntaxNode; APreviousPublic: Boolean): TArray<TRuleFix>;
    function TypeNodeOf(AMember: TSyntaxNode): TSyntaxNode;
    procedure CheckClass(ADecl, ABody: TSyntaxNode);
    function IsPublishedMember(AMember, ASection: TSyntaxNode): Boolean;
    procedure CheckMember(ABody: TSyntaxNode; AIndex: Integer; const AWildcards: TArray<string>;
      const AFixes: TArray<TRuleFix>);
    function IsClassProperty(AMember: TSyntaxNode): Boolean;
    procedure CheckProperty(AMember: TSyntaxNode; const AWildcards: TArray<string>; const AFixes: TArray<TRuleFix>);
    procedure ReportPropertyType(const AName: string; ATypeNode: TSyntaxNode; AKind: TPublishKind;
      const AFixes: TArray<TRuleFix>);
    procedure CheckField(AMember: TSyntaxNode; const AWildcards: TArray<string>; const AFixes: TArray<TRuleFix>);
    procedure CheckOverload(ABody: TSyntaxNode; AIndex: Integer; const AFixes: TArray<TRuleFix>);
    function IsSameRoutine(AOther, AMember: TSyntaxNode): Boolean;
    procedure Visit(ARoot: TSyntaxNode);
    function FindTypesUnit(ANode: TSyntaxNode): Boolean;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TPublishedScan }

constructor TPublishedScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Erstes Token ab AOffset (Index); Length(Tokens) ohne.</summary>
function TPublishedScan.TokenAt(AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(FTokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if FTokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

function TPublishedScan.PathOf(ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(FPaths, TokenAt(ANode.StartOffset));
end;

function TPublishedScan.SourceOf(ANode: TSyntaxNode): string;
begin
  Result := Trim(Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

function TPublishedScan.NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Bereich des Namens AName im Knoten ANode (erstes passendes Token); sonst der ganze Knoten.</summary>
function TPublishedScan.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  Index: Integer;
begin
  Index := TokenAt(ANode.StartOffset);
  while (Index < Length(FTokens)) and (FTokens[Index].Offset < ANode.EndOffset) do
  begin
    if (FTokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[Index].Text, AName) then
    begin
      Exit(TTextRange.Create(FTokens[Index].StartPos, FTokens[Index].EndPos));
    end;
    Inc(Index);
  end;
  Result := NodeRange(ANode);
end;

/// <summary>Gibt es den Namen als Typ, der nicht auf Unit-Ebene steht (verschachtelt) oder mehrfach (Zweige
/// bedingter Übersetzung)? Dann ist die Auflösung über FindAnyType nicht sicher.</summary>
function TPublishedScan.Ambiguous(const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Count: Integer;
begin
  Count := 0;
  for Symbol in FAncestry.Local.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias,
      TIndexSymbolKind.HelperType]) and SameText(Symbol.Name, AName) then
    begin
      if (Symbol.Container <> '') or Symbol.Unavailable then
      begin
        Exit(True);
      end;
      Inc(Count);
    end;
  end;
  Result := Count > 1;
end;

/// <summary>Art des Typs mit Namen AName (Aliase werden bis ADepth = 8 verfolgt).</summary>
/// <summary>Art des Typs mit Namen AName (Aliase werden bis ADepth = 8 verfolgt).</summary>
function TPublishedScan.NamedKind(const AName: string; const AWildcards: TArray<string>; ADepth: Integer): TPublishKind;
var
  mBare: string;
  mLocation: TSymbolLocation;
begin
  Result := TPublishKind.Unknown;
  mBare := BareTypeName(AName);
  if (mBare = '') or (ADepth > 8) or MatchText(mBare, AWildcards) or Ambiguous(mBare) then
  begin
    Exit;
  end;
  if not FAncestry.FindAnyType(mBare, mLocation) then
  begin
    Result := UnresolvedKind(AName, LowerCase(mBare));
  end
  else if not mLocation.Symbol.Unavailable then
  begin
    Result := SymbolKind(mLocation, ADepth);
  end;
end;

/// <summary>Art eines Typs, den der Index nicht kennt (RTL-Grundtypen); ALower ist der kleingeschriebene Name.</summary>
function TPublishedScan.UnresolvedKind(const AName, ALower: string): TPublishKind;
begin
  Result := TPublishKind.Unknown;
  if MatchText(ALower, SimpleTypes) then
  begin
    Result := TPublishKind.Simple;
  end
  else if MatchText(ALower, PointerTypes) then
  begin
    Result := TPublishKind.PointerKind;
  end
  else if ALower = 'real48' then
  begin
    Result := TPublishKind.Real48Kind;
  end
  else if (ALower = 'tguid') or (FUsesTypes and MatchText(ALower, TypesRecords)) then
  begin
    Result := TPublishKind.RecordKind;
  end
  else if (ALower = 'tarray') and (Pos('<', AName) > 0) then
  begin
    Result := TPublishKind.DynArrayKind;
  end;
end;

function TPublishedScan.SymbolKind(const ALocation: TSymbolLocation; ADepth: Integer): TPublishKind;
begin
  case ALocation.Symbol.Kind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
      Result := TPublishKind.ClassOrInterface;
    TIndexSymbolKind.RecordType:
      Result := TPublishKind.RecordKind;
    TIndexSymbolKind.EnumType:
      Result := TPublishKind.Simple;
    TIndexSymbolKind.TypeAlias:
      Result := AliasKind(ALocation, AliasTarget(ALocation.Symbol.Signature), ADepth);
  else
    Result := TPublishKind.Unknown;
  end;
end;

/// <summary>Art des Alias mit dem Ziel ATarget ("^T", "array of …", "set of …", Prozedurtyp, anderer Name).</summary>
function TPublishedScan.AliasKind(const ALocation: TSymbolLocation; const ATarget: string;
  ADepth: Integer): TPublishKind;
begin
  Result := TPublishKind.Unknown;
  if ATarget = '' then
  begin
    Exit;
  end;
  if ATarget[1] = '^' then
  begin
    Result := TPublishKind.PointerKind;
  end
  else if IsArrayTarget(ATarget) then
  begin
    Result := ArrayTargetKind(ATarget);
  end
  else if StartsText('set ', ATarget) and StartsText('of ', Trim(Copy(ATarget, 5, MaxInt))) then
  begin
    Result := SetKind(Trim(Copy(Trim(Copy(ATarget, 5, MaxInt)), 4, MaxInt)), ADepth + 1);
  end
  else if StartsText('reference ', ATarget) or ALocation.Symbol.HasDirective('reference to') then
  begin
    Result := TPublishKind.ProcedureKind;
  end
  else if StartsText('procedure', ATarget) or StartsText('function', ATarget) then
  begin
    Result := RoutineTargetKind(ALocation, ATarget);
  end
  else if StartsText('string[', ATarget) or (Pos('..', ATarget) > 0) then
  begin
    Result := TPublishKind.Simple;
  end
  else if IsTypeName(ATarget) then
  begin
    Result := NamedKind(StringReplace(ATarget, ' ', '', [rfReplaceAll]), nil, ADepth + 1);
  end;
end;

/// <summary>Art einer Menge über ABase ("TFarbe", "(a, b)", "0..40", "Byte"): Simple bis 4 Byte, LargeSet
/// darüber, sonst Unknown.</summary>
/// <summary>Art einer Menge über ABase ("TFarbe", "(a, b)", "0..40", "Byte"): Simple bis 4 Byte, LargeSet
/// darüber, sonst Unknown.</summary>
function TPublishedScan.SetKind(const ABase: string; ADepth: Integer): TPublishKind;
var
  mBase: string;
begin
  Result := TPublishKind.Unknown;
  mBase := Trim(ABase);
  if (mBase = '') or (ADepth > 8) then
  begin
    Exit;
  end;
  if mBase[1] = '(' then
  begin
    Result := EnumSetKind(mBase);
  end
  else if Pos('..', mBase) > 0 then
  begin
    Result := RangeSetKind(mBase);
  end
  else
  begin
    Result := NamedSetKind(mBase, ADepth);
  end;
end;

/// <summary>Menge über einen benannten Typ: Aufzählung aus dem Index, Alias darauf oder Byte, AnsiChar, ShortInt.</summary>
function TPublishedScan.NamedSetKind(const ABase: string; ADepth: Integer): TPublishKind;
var
  mBare, mTarget: string;
  mLocation: TSymbolLocation;
begin
  Result := TPublishKind.Unknown;
  mBare := BareTypeName(ABase);
  if Ambiguous(mBare) then
  begin
    Exit;
  end;
  if not FAncestry.FindAnyType(mBare, mLocation) then
  begin
    if MatchText(LowerCase(mBare), ['byte', 'ansichar', 'shortint']) then
    begin
      Result := TPublishKind.LargeSet;
    end;
    Exit;
  end;
  if mLocation.Symbol.Unavailable then
  begin
    Exit;
  end;
  mTarget := AliasTarget(mLocation.Symbol.Signature);
  if mLocation.Symbol.Kind = TIndexSymbolKind.EnumType then
  begin
    Result := EnumSetKind(mTarget);
  end
  else if (mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias) and (mTarget <> '') and
    ((mTarget[1] = '(') or (Pos('..', mTarget) > 0) or IsTypeName(mTarget)) then
  begin
    Result := SetKind(mTarget, ADepth + 1);
  end;
end;

/// <summary>Art des Typknotens ATypeNode (Typverweis oder Typ im Feld selbst).</summary>
function TPublishedScan.TypeKind(ATypeNode: TSyntaxNode; const AWildcards: TArray<string>): TPublishKind;
begin
  case ATypeNode.Kind of
    TSyntaxKind.TypeReference:
      if ATypeNode.Name = 'string' then
      begin
        Result := TPublishKind.Simple;
      end
      else
      begin
        Result := NamedKind(SourceOf(ATypeNode), AWildcards, 0);
      end;
    TSyntaxKind.ArrayType:
      Result := TPublishKind.ArrayKind;
    TSyntaxKind.RecordType:
      Result := TPublishKind.RecordKind;
    TSyntaxKind.PointerType:
      Result := TPublishKind.PointerKind;
    TSyntaxKind.EnumType, TSyntaxKind.SubrangeType, TSyntaxKind.SetType:
      Result := TPublishKind.Simple;
  else
    Result := TPublishKind.Unknown;
  end;
end;

/// <summary>Korrektur: Zeilen des Mitglieds AMember vor das "published" APublished setzen, unter das
/// "public" davor oder ein neues.</summary>
function TPublishedScan.MoveToPublic(AMember, APublished: TSyntaxNode; APreviousPublic: Boolean): TArray<TRuleFix>;
var
  First, Last, Line: Integer;
  Moved, Insert: string;
begin
  Result := nil;
  First := AMember.StartPos.Line;
  Last := AMember.EndPos.Line;
  if (Last + 1 >= Length(FLines)) or (APublished.StartPos.Line >= First) or
    not SameText(Trim(FLines[APublished.StartPos.Line]), 'published') or
    (Trim(Copy(FLines[First], 1, AMember.StartPos.Character)) <> '') or
    (Trim(Copy(FLines[Last], AMember.EndPos.Character + 1, MaxInt)) <> '') then
  begin
    Exit;
  end;
  // Attribute über dem Mitglied gehören dazu: dann lieber keine Korrektur als eine halbe.
  if StartsStr('[', Trim(FLines[First - 1])) then
  begin
    Exit;
  end;
  Moved := '';
  for Line := First to Last do
  begin
    Moved := Moved + FLines[Line] + FLineBreak;
  end;
  Insert := Moved;
  if not APreviousPublic then
  begin
    Insert := TTextLines.IndentOf(FLines[APublished.StartPos.Line]) + 'public' + FLineBreak + Moved;
  end;
  Result := [TRuleFix.Create('In den public-Abschnitt verschieben', [
    TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(APublished.StartPos.Line, 0),
    TTextPosition.Create(APublished.StartPos.Line, 0)), Insert),
    TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(First, 0), TTextPosition.Create(Last + 1, 0)), '')])];
end;

function TPublishedScan.TypeNodeOf(AMember: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to AMember.ChildCount - 1 do
  begin
    if not (AMember[Index].Kind in [TSyntaxKind.Parameters, TSyntaxKind.Parameter, TSyntaxKind.Attribute,
      TSyntaxKind.Directive, TSyntaxKind.GenericParams]) then
    begin
      Exit(AMember[Index]);
    end;
  end;
  Result := nil;
end;

procedure TPublishedScan.CheckClass(ADecl, ABody: TSyntaxNode);
var
  mWildcards: TArray<string>;
  mIndex: Integer;
  mMember, mSection, mPrevious, mParams: TSyntaxNode;
  mFixes: TArray<TRuleFix>;
begin
  mWildcards := nil;
  mParams := ADecl.FindChild(TSyntaxKind.GenericParams);
  if mParams <> nil then
  begin
    for mIndex := 0 to mParams.ChildCount - 1 do
    begin
      mWildcards := mWildcards + [mParams[mIndex].Name];
    end;
  end;
  mSection := nil;
  mPrevious := nil;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mMember := ABody[mIndex];
    if mMember.Kind = TSyntaxKind.Visibility then
    begin
      mPrevious := mSection;
      mSection := mMember;
    end
    else if IsPublishedMember(mMember, mSection) then
    begin
      mFixes := MoveToPublic(mMember, mSection, (mPrevious <> nil) and (mPrevious.Name = 'public') and
        TConditionalBranches.Implies(PathOf(mSection), PathOf(mPrevious)));
      CheckMember(ABody, mIndex, mWildcards, mFixes);
    end;
  end;
end;

/// <summary>Feld, Property oder Methode in einem published-Abschnitt, der immer mit ihr übersetzt wird.</summary>
function TPublishedScan.IsPublishedMember(AMember, ASection: TSyntaxNode): Boolean;
begin
  Result := (AMember.Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader]) and
    (ASection <> nil) and (ASection.Name = 'published') and
    TConditionalBranches.Implies(PathOf(AMember), PathOf(ASection));
end;

procedure TPublishedScan.CheckMember(ABody: TSyntaxNode; AIndex: Integer; const AWildcards: TArray<string>;
  const AFixes: TArray<TRuleFix>);
var
  mMember: TSyntaxNode;
  mName: string;
begin
  mMember := ABody[AIndex];
  mName := mMember.Name;
  if not IsAscii(mName) then
  begin
    FReport.Add(NameRange(mMember, mName.Split([','])[0]), Format('Der published-Name %s enthält Zeichen ' +
      'außerhalb von ASCII (wie E2452).', [mName]), TRuleConfidence.High, AFixes);
    Exit;
  end;
  case mMember.Kind of
    TSyntaxKind.PropertyDecl:
      CheckProperty(mMember, AWildcards, AFixes);
    TSyntaxKind.Field:
      CheckField(mMember, AWildcards, AFixes);
    TSyntaxKind.RoutineHeader:
      CheckOverload(ABody, AIndex, AFixes);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>"class property": das Token vor "property" (Kommentare übersprungen) ist "class".</summary>
function TPublishedScan.IsClassProperty(AMember: TSyntaxNode): Boolean;
var
  mToken: Integer;
begin
  mToken := TokenAt(AMember.StartOffset) - 1;
  while (mToken >= 0) and (FTokens[mToken].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mToken);
  end;
  Result := (mToken >= 0) and FTokens[mToken].IsKeyword('class');
end;

procedure TPublishedScan.CheckProperty(AMember: TSyntaxNode; const AWildcards: TArray<string>;
  const AFixes: TArray<TRuleFix>);
var
  mTypeNode: TSyntaxNode;
begin
  if IsClassProperty(AMember) then
  begin
    FReport.Add(NameRange(AMember, AMember.Name), Format('Die Klassen-Property %s kann nicht published sein ' +
      '(wie E2545).', [AMember.Name]), TRuleConfidence.High, AFixes);
    Exit;
  end;
  // Array-Properties und Properties ohne Typ (neu veröffentlicht) prüft die Regel nicht.
  mTypeNode := AMember.FindChild(TSyntaxKind.TypeReference);
  if (AMember.FindChild(TSyntaxKind.Parameters) = nil) and (mTypeNode <> nil) then
  begin
    ReportPropertyType(AMember.Name, mTypeNode, TypeKind(mTypeNode, AWildcards), AFixes);
  end;
end;

procedure TPublishedScan.ReportPropertyType(const AName: string; ATypeNode: TSyntaxNode; AKind: TPublishKind;
  const AFixes: TArray<TRuleFix>);
var
  mMessage: string;
begin
  case AKind of
    TPublishKind.ArrayKind:
      mMessage := '%0:s (Array) kann nicht published sein (wie E2188).';
    TPublishKind.PointerKind:
      mMessage := '%0:s (Zeiger) kann nicht published sein (wie E2188).';
    TPublishKind.ProcedureKind:
      mMessage := '%0:s (Prozedurtyp ohne "of object") kann nicht published sein (wie E2188).';
    TPublishKind.Real48Kind:
      mMessage := '%1:s ist vom Typ Real48; Real48 kann nicht published sein (wie E2186).';
    TPublishKind.LargeSet:
      mMessage := 'Die Menge %0:s ist größer als 4 Byte und kann nicht published sein (wie E2187).';
  else
    // Unbekannt, Klassen, einfache Typen, Records und dynamische Arrays (dcc übersetzt sie, PU1-PU3).
    Exit;
  end;
  FReport.Add(NodeRange(ATypeNode), Format(mMessage, [SourceOf(ATypeNode), AName]), TRuleConfidence.High, AFixes);
end;

procedure TPublishedScan.CheckField(AMember: TSyntaxNode; const AWildcards: TArray<string>;
  const AFixes: TArray<TRuleFix>);
var
  mTypeNode: TSyntaxNode;
begin
  mTypeNode := TypeNodeOf(AMember);
  if (mTypeNode = nil) or (TypeKind(mTypeNode, AWildcards) in [TPublishKind.Unknown, TPublishKind.ClassOrInterface]) then
  begin
    Exit;
  end;
  FReport.Add(NameRange(AMember, AMember.Name.Split([','])[0]), Format('Das published-Feld %s ist vom Typ %s; ' +
    'published-Felder müssen Klassen oder Interfaces sein (wie E2217).',
    [StringReplace(AMember.Name, ',', ', ', [rfReplaceAll]), SourceOf(mTypeNode)]), TRuleConfidence.High, AFixes);
end;

/// <summary>Eine frühere published-Methode gleichen Namens, die mit dieser übersetzt wird?</summary>
procedure TPublishedScan.CheckOverload(ABody: TSyntaxNode; AIndex: Integer; const AFixes: TArray<TRuleFix>);
var
  mOther: Integer;
  mMember, mScan: TSyntaxNode;
begin
  mMember := ABody[AIndex];
  mScan := nil;
  for mOther := 0 to AIndex - 1 do
  begin
    if ABody[mOther].Kind = TSyntaxKind.Visibility then
    begin
      mScan := ABody[mOther];
    end
    else if (mScan <> nil) and (mScan.Name = 'published') and IsSameRoutine(ABody[mOther], mMember) then
    begin
      FReport.Add(NameRange(mMember, mMember.Name), Format('Nur eine Überladung von %s darf published sein ' +
        '(wie E2266).', [mMember.Name]), TRuleConfidence.High, AFixes);
      Exit;
    end;
  end;
end;

/// <summary>AOther ist eine Methode gleichen Namens wie AMember in einem nicht ausschließenden Zweig.</summary>
function TPublishedScan.IsSameRoutine(AOther, AMember: TSyntaxNode): Boolean;
begin
  Result := (AOther.Kind = TSyntaxKind.RoutineHeader) and SameText(AOther.Name, AMember.Name) and
    not TConditionalBranches.Exclusive(PathOf(AOther), PathOf(AMember));
end;

// Iterativ (Bericht M1).
procedure TPublishedScan.Visit(ARoot: TSyntaxNode);
var
  Pending: TStack<TSyntaxNode>;
  Node, Body: TSyntaxNode;
  Index: Integer;
begin
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.TypeDecl then
      begin
        Body := Node.FindChild(TSyntaxKind.ClassType);
        if Body <> nil then
        begin
          CheckClass(Node, Body);
          Node := Body;
        end;
      end;
      // Nur Deklarationscontainer: Anweisungen und Ausdrücke enthalten keine Klassen (#1094).
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        if Node[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
          TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl] then
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Bindet die Unit System.Types oder Winapi.Windows ein (TPoint, TRect, TPointF ...)? Die Rekursion
/// geht nur über Abschnitt, uses und Unit (feste Tiefe) und bleibt deshalb (Bericht M1).</summary>
function TPublishedScan.FindTypesUnit(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.UsedUnit) and MatchText(ANode.Name, TypesUnits) then
  begin
    Exit(True);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.UsesClause, TSyntaxKind.UsedUnit]) and FindTypesUnit(ANode[Index]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPublishedScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FCache := TRuleDerived.Open(FContext);
  FTokens := FContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FLines := TTextLines.SplitLines(FContext.Text);
  FLineBreak := TTextLines.LineBreakOf(FContext.Text);
  FUsesTypes := FindTypesUnit(FContext.Tree.Root);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(FCache, FContext));
  try
    Visit(FContext.Tree.Root);
  finally
    FAncestry.Free;
  end;
end;

{ TPublishedTypeInvalidRule }

procedure TPublishedTypeInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mWorker: TPublishedScan;
begin
  mWorker := TPublishedScan.Create(AContext, AReport);
  try
    mWorker.Run;
  finally
    mWorker.Free;
  end;
end;

procedure RegisterPublishedRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPublishedTypeInvalidRule.Create);
end;

end.
