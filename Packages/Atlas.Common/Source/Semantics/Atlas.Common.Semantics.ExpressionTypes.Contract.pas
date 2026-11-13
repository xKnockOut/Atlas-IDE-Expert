unit Atlas.Common.Semantics.ExpressionTypes.Contract;

// Typen der Ausdruckstypen (#689): Kategorie eines Typs, Umwandlung, Fehlerart, Ergebnis und Optionen.
// Die Operatorregeln (Atlas.Common.Semantics.ExpressionTypes.Operators) und der Durchlauf
// (Atlas.Common.Semantics.ExpressionTypes) nutzen sie.

interface

uses
  Atlas.Common.Documents.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Erweitern (Ganzzahl → Gleitkomma, schmale → breite Zahl) bzw. umwandeln (Variant, Char).</summary>
  TExpressionConversionKind = (Widen, Convert);
  TExpressionErrorKind = (None, NoExpression, UnknownName, OperatorMismatch, NoResult, Unknown);
  /// <summary>Grobe Art eines Typs für die Operatorregeln.</summary>
  TExpressionCategory = (Unknown, Integer_, Float, Currency_, Boolean_, Char_, String_, Variant_, Set_, Pointer_,
    Nil_, Other);
{$SCOPEDENUMS OFF}

  TExpressionConversion = record
    /// <summary>Teilausdruck wie im Quelltext (gekürzt).</summary>
    Expression: string;
    FromType: string;
    ToType: string;
    Kind: TExpressionConversionKind;
  end;

  TExpressionTypeInfo = record
    /// <summary>Bereich und Text des Ausdrucks, dessen Typ gilt.</summary>
    Range: TTextRange;
    Expression: string;
    /// <summary>Typ wie im Quelltext ('' bei Fehler).</summary>
    TypeName: string;
    /// <summary>Grundtyp eines Alias; '' sonst.</summary>
    BaseName: string;
    /// <summary>Fundort der Typdeklaration; TypeFile '' ohne (eingebaute Typen).</summary>
    TypeFile: string;
    TypeLine: Integer;
    TypeCharacter: Integer;
    Conversions: TArray<TExpressionConversion>;
    /// <summary>Kopf der gewählten Überladung, wenn es mehrere gibt; '' sonst.</summary>
    Overload: string;
    HasValue: Boolean;
    Value: Int64;
    Error: TExpressionErrorKind;
    /// <summary>Name bzw. Operator und Operandentypen zum Fehler.</summary>
    ErrorDetail: string;
    function Found: Boolean;
  end;

  TExpressionTypeOptions = record
    Conversions: Boolean;
    ConstValue: Boolean;
    class function Default: TExpressionTypeOptions; static;
  end;

implementation

function TExpressionTypeInfo.Found: Boolean;
begin
  Result := TypeName <> '';
end;

class function TExpressionTypeOptions.Default: TExpressionTypeOptions;
begin
  Result.Conversions := True;
  Result.ConstValue := True;
end;

end.
