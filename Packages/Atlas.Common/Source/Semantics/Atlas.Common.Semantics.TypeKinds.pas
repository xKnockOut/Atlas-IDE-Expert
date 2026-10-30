unit Atlas.Common.Semantics.TypeKinds;

// Art eines aufgelösten Typs (#1370): Ganzzahl, Gleitkomma, Currency,
// Boolean, Zeichen, String, Variant, Zeiger, Aufzählung, Menge, Array, Record,
// object, Klasse, Klassenreferenz, Interface, Helfer, prozeduraler Typ und
// Datei. Grundlage für Regeln, die eine bestimmte Typart verlangen
// (type-kind-required: Index nur auf Arrays, ^ nur auf Zeigern, Punkt nur auf
// Records, Klassen und object-Typen …) und für Typvergleiche.
//   - Eingebaute Typen über TExpressionTypes.CategoryOf (Integer, Double …).
//   - Typen aus Datei und Index über ihre Symbolart; "class of" im Kopf ist
//     eine Klassenreferenz, auch wenn der Index sie als Klasse führt.
//   - Aliase über den Typtext hinter "=": ^T, class of, set of, array,
//     procedure/function/reference to, file, string[n]; ein Alias auf einen
//     eingebauten Namen bekommt dessen Art.
// Unknown, wenn die Art nicht sicher feststeht (Teilbereiche, unbekannte
// Namen, Aliase ohne Text).

interface

uses
  Atlas.Common.Semantics.NameResolver;

type
{$SCOPEDENUMS ON}
  TResolvedTypeKind = (Unknown, Integer_, Float, Currency_, Boolean_, Char_, String_, Variant_, Pointer_, Enumeration,
    Set_, Array_, Record_, Object_, Class_, ClassReference, Interface_, Helper, Procedure_, File_);
{$SCOPEDENUMS OFF}

  TResolvedTypeKinds = record
  public
    /// <summary>Art des eingebauten Typnamens AName (mit oder ohne "System."); Unknown, wenn er keiner ist.
    /// </summary>
    class function OfBuiltin(const AName: string): TResolvedTypeKind; static;
    /// <summary>Art eines Typtexts, wie er hinter "=" bzw. ":" steht ("^Integer", "class of TObject",
    /// "array of Byte", "Integer"); Unknown bei Typnamen, die kein eingebauter Typ sind.</summary>
    class function OfText(const ATypeText: string): TResolvedTypeKind; static;
    /// <summary>Art des aufgelösten Typs AType; bei Aliasen aus dem Kopf der Deklaration (Signature).</summary>
    class function OfType(const AType: TResolvedSymbol): TResolvedTypeKind; overload; static;
    /// <summary>Wie oben; ADeclaredText ist der Typtext hinter "=" für Aliase, deren Kopf fehlt (lokale Typen).
    /// </summary>
    class function OfType(const AType: TResolvedSymbol; const ADeclaredText: string): TResolvedTypeKind; overload; static;
    /// <summary>Einfacher Wert ohne Mitglieder, Index und Dereferenzierung: Ganzzahl, Gleitkomma, Currency,
    /// Boolean, Zeichen oder Aufzählung.</summary>
    class function IsSimpleValue(AKind: TResolvedTypeKind): Boolean; static;
    /// <summary>Art mit unbestimmtem Artikel für Meldungen ("eine Zahl", "ein Record", "eine Klasse").</summary>
    class function Describe(AKind: TResolvedTypeKind): string; static;
    /// <summary>Typtext hinter dem ersten "=" bzw. ":" auf oberster Ebene des Kopfs ASignature bis zum
    /// Semikolon; '' ohne.</summary>
    class function DeclaredText(const ASignature: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.ExpressionTypes;

const
  cKindTexts: array[TResolvedTypeKind] of string = ('ein Typ unbekannter Art', 'eine Ganzzahl', 'eine Gleitkommazahl',
    'eine Zahl vom Typ Currency', 'ein Boolean', 'ein Zeichen', 'ein String', 'ein Variant', 'ein Zeiger',
    'eine Aufzählung', 'eine Menge', 'ein Array', 'ein Record', 'ein object-Typ', 'eine Klasse',
    'eine Klassenreferenz', 'ein Interface', 'ein Helfer', 'ein prozeduraler Typ', 'eine Datei');

{ TResolvedTypeKinds }

class function TResolvedTypeKinds.OfBuiltin(const AName: string): TResolvedTypeKind;
var
  mWidth: Integer;
  mSigned: Boolean;
begin
  case TExpressionTypes.CategoryOf(Trim(AName), mWidth, mSigned) of
    TExpressionCategory.Integer_:
      Result := TResolvedTypeKind.Integer_;
    TExpressionCategory.Float:
      Result := TResolvedTypeKind.Float;
    TExpressionCategory.Currency_:
      Result := TResolvedTypeKind.Currency_;
    TExpressionCategory.Boolean_:
      Result := TResolvedTypeKind.Boolean_;
    TExpressionCategory.Char_:
      Result := TResolvedTypeKind.Char_;
    TExpressionCategory.String_:
      Result := TResolvedTypeKind.String_;
    TExpressionCategory.Variant_:
      Result := TResolvedTypeKind.Variant_;
    TExpressionCategory.Pointer_:
      Result := TResolvedTypeKind.Pointer_;
    TExpressionCategory.Set_:
      Result := TResolvedTypeKind.Set_;
  else
    Result := TResolvedTypeKind.Unknown;
  end;
end;

class function TResolvedTypeKinds.OfText(const ATypeText: string): TResolvedTypeKind;
var
  mText: string;
begin
  mText := Trim(ATypeText);
  // "type Integer" ist ein eigener Typ derselben Art.
  if StartsText('type ', mText) then
    mText := Trim(Copy(mText, 6, MaxInt));
  if mText = '' then
    Exit(TResolvedTypeKind.Unknown);
  if StartsStr('^', mText) then
    Exit(TResolvedTypeKind.Pointer_);
  if StartsText('class of ', mText) then
    Exit(TResolvedTypeKind.ClassReference);
  if StartsText('set of ', mText) then
    Exit(TResolvedTypeKind.Set_);
  if StartsText('array', mText) or StartsText('packed array', mText) then
    Exit(TResolvedTypeKind.Array_);
  if StartsText('procedure', mText) or StartsText('function', mText) or StartsText('reference to ', mText) then
    Exit(TResolvedTypeKind.Procedure_);
  if SameText(mText, 'file') or StartsText('file of ', mText) or SameText(mText, 'Text') or
    SameText(mText, 'TextFile') then
    Exit(TResolvedTypeKind.File_);
  if StartsText('string[', mText) then
    Exit(TResolvedTypeKind.String_);
  if StartsStr('(', mText) then
    Exit(TResolvedTypeKind.Enumeration);
  Result := OfBuiltin(mText);
end;

class function TResolvedTypeKinds.OfType(const AType: TResolvedSymbol): TResolvedTypeKind;
begin
  Result := OfType(AType, '');
end;

class function TResolvedTypeKinds.OfType(const AType: TResolvedSymbol; const ADeclaredText: string): TResolvedTypeKind;
var
  mText: string;
begin
  // Eingebaute Typen tragen in der Namensauflösung die Symbolart RecordType; maßgeblich ist ihr Name.
  if AType.Builtin then
    Exit(OfBuiltin(AType.Name));
  if not AType.Found or not AType.IsType then
    Exit(TResolvedTypeKind.Unknown);
  // "TClass = class of TObject" steht im Index als Klasse.
  mText := ADeclaredText;
  if mText = '' then
    mText := DeclaredText(AType.Signature);
  if StartsText('class of ', mText) then
    Exit(TResolvedTypeKind.ClassReference);
  case AType.SymbolKind of
    TIndexSymbolKind.ClassType:
      Result := TResolvedTypeKind.Class_;
    TIndexSymbolKind.ObjectType:
      Result := TResolvedTypeKind.Object_;
    TIndexSymbolKind.RecordType:
      Result := TResolvedTypeKind.Record_;
    TIndexSymbolKind.InterfaceType:
      Result := TResolvedTypeKind.Interface_;
    TIndexSymbolKind.HelperType:
      Result := TResolvedTypeKind.Helper;
    TIndexSymbolKind.EnumType:
      Result := TResolvedTypeKind.Enumeration;
    TIndexSymbolKind.TypeAlias:
      Result := OfText(mText);
  else
    Result := TResolvedTypeKind.Unknown;
  end;
end;

class function TResolvedTypeKinds.IsSimpleValue(AKind: TResolvedTypeKind): Boolean;
begin
  Result := AKind in [TResolvedTypeKind.Integer_, TResolvedTypeKind.Float, TResolvedTypeKind.Currency_, TResolvedTypeKind.Boolean_, TResolvedTypeKind.Char_,
    TResolvedTypeKind.Enumeration];
end;

class function TResolvedTypeKinds.Describe(AKind: TResolvedTypeKind): string;
begin
  Result := cKindTexts[AKind];
end;

class function TResolvedTypeKinds.DeclaredText(const ASignature: string): string;
var
  mIndex, mDepth, mEnd: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(ASignature) do
    case ASignature[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
      ':', '=':
        if mDepth = 0 then
        begin
          Result := Copy(ASignature, mIndex + 1, MaxInt);
          mEnd := Pos(';', Result);
          if mEnd > 0 then
            Result := Copy(Result, 1, mEnd - 1);
          Exit(Trim(Result));
        end;
    end;
end;

end.
