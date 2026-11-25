unit Atlas.UI.Signature.FormatText;

// Zeile der Platzhalter im Parameter-Hint (#451) in der Sprache der Oberfläche: „Platzhalter 2 von 2 erwartet
// ganzzahlig“ und die Probleme eines Formataufrufs. Die Texte stehen in der gemeinsamen Tabelle (TAtlasStrings).

interface

uses
  Atlas.Core.Signature.Format;

type
  TAtlasSignatureFormatText = class
  private
    /// <summary>Art eines Literals, wie der Server sie nennt (string, char, integer, float, boolean).</summary>
    class function LiteralKind(const AKind: string): string; static;
  public
    /// <summary>Text zu ALine; '' ohne.</summary>
    class function Line(const ALine: TAtlasFormatLine): string; static;
    /// <summary>Art eines Typbuchstabens (d → ganzzahlig, s → String …).</summary>
    class function Kind(AType: Char): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Core.Signature.Contract,
  Atlas.Plugin.Localization.Strings;

const
  /// <summary>Arten von Literalen, wie der Server sie nennt, und ihre Beschriftung.</summary>
  cLiteralKinds: array[0..4] of string = ('string', 'char', 'integer', 'float', 'boolean');
  cLiteralKindTexts: array[0..4] of TAtlasTextId = (TAtlasTextId.FormatLiteralString,
    TAtlasTextId.FormatLiteralChar, TAtlasTextId.FormatLiteralInteger, TAtlasTextId.FormatLiteralFloat,
    TAtlasTextId.FormatLiteralBoolean);

{ TAtlasSignatureFormatText }

class function TAtlasSignatureFormatText.LiteralKind(const AKind: string): string;
var
  mIndex: Integer;
begin
  mIndex := IndexStr(AKind, cLiteralKinds);
  if mIndex < 0 then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.FormatLiteralOther));
  end;
  Result := TAtlasStrings.Text(cLiteralKindTexts[mIndex]);
end;

class function TAtlasSignatureFormatText.Line(const ALine: TAtlasFormatLine): string;
begin
  case ALine.Kind of
    TAtlasFormatLineKind.Placeholder:
      Result := TAtlasStrings.Fmt(TAtlasTextId.FormatPlaceholder,
        [ALine.Placeholder + 1, ALine.Count, Kind(ALine.TypeChar)]);
    TAtlasFormatLineKind.Width:
      Result := TAtlasStrings.Fmt(TAtlasTextId.FormatWidth,
        [ALine.Placeholder + 1, ALine.Count, ALine.PlaceholderText]);
    TAtlasFormatLineKind.Precision:
      Result := TAtlasStrings.Fmt(TAtlasTextId.FormatPrecision,
        [ALine.Placeholder + 1, ALine.Count, ALine.PlaceholderText]);
    TAtlasFormatLineKind.Unused:
      Result := TAtlasStrings.Fmt(TAtlasTextId.FormatUnused, [ALine.Argument + 1, ALine.Count]);
    TAtlasFormatLineKind.Problem:
      case ALine.Problem of
        TAtlasFormatProblem.Invalid:
          Result := TAtlasStrings.Fmt(TAtlasTextId.FormatInvalid, [ALine.PlaceholderText]);
        TAtlasFormatProblem.TooManyArguments:
          Result := TAtlasStrings.Fmt(TAtlasTextId.FormatTooMany, [ALine.Argument + 1]);
        TAtlasFormatProblem.TypeConflict:
          Result := TAtlasStrings.Fmt(TAtlasTextId.FormatConflict, [ALine.Placeholder + 1, ALine.PlaceholderText,
            Kind(ALine.TypeChar), ALine.Argument + 1, LiteralKind(ALine.ProblemKind)]);
      else
        Result := '';
      end;
  else
    Result := '';
  end;
end;

class function TAtlasSignatureFormatText.Kind(AType: Char): string;
begin
  case AType of
    'u':
      Result := TAtlasStrings.Text(TAtlasTextId.FormatKindUnsigned);
    'x':
      Result := TAtlasStrings.Text(TAtlasTextId.FormatKindHex);
    'e', 'f', 'g', 'n':
      Result := TAtlasStrings.Text(TAtlasTextId.FormatKindFloat);
    'm':
      Result := TAtlasStrings.Text(TAtlasTextId.FormatKindMoney);
    's':
      Result := TAtlasStrings.Text(TAtlasTextId.FormatKindString);
    'p':
      Result := TAtlasStrings.Text(TAtlasTextId.FormatKindPointer);
  else
    // d und Unbekanntes: ganzzahlig
    Result := TAtlasStrings.Text(TAtlasTextId.FormatKindInteger);
  end;
end;

end.
