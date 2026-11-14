unit Atlas.Common.Lsp.ValueEdit;

// Befehl atlas.server.valueEdit (#868): Typ eines Werts, den das Plugin beim
// Debuggen ändern will, und daraus die Art der Eingabe.
// Argumente: [uri, line, expression] (Zeile ab 0). Atlas sucht den Ausdruck in
// der Zeile (als ganzes Wort), bestimmt seinen Typ wie
// atlas.server.expressionType und daraus die Art:
//   integer (mit low/high der Breite), float (auch Currency), boolean, char,
//   string, enum und set (mit den Werten in Deklarationsreihenfolge, prefix
//   „TModus.“ bei {$SCOPEDENUMS ON}), color (TColor, TAlphaColor), other.
// Endet der Ausdruck mit einer Eigenschaft, nennt setter die Schreibmethode
// (write SetBetrag); readOnly, wenn sie kein write hat. Ein Feld als Ziel von
// write (F + Großbuchstabe) gilt nicht als Setter.
// Antwort: {"expression": "Betrag", "type": "Currency", "kind": "float",
//   "values": [], "prefix": "", "low": "", "high": "", "setter": "",
//   "readOnly": false}; ohne Fund im Text kind "other" und type "".

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Values;

type
  TLspValueEditInfo = record
    Expression: string;
    TypeName: string;
    /// <summary>integer, float, boolean, char, string, enum, set, color oder other.</summary>
    Kind: string;
    Values: TArray<string>;
    Prefix: string;
    /// <summary>Grenzen bei integer als Text; '' sonst.</summary>
    Low: string;
    High: string;
    Setter: string;
    ReadOnly: Boolean;
  end;

  TLspValueEdit = class
  public const
    cCommand = 'atlas.server.valueEdit';
  public
    /// <summary>Zeichen (ab 0) von AExpression in ALine als ganzes Wort; -1 ohne.</summary>
    class function FindExpression(const ALine, AExpression: string): Integer; static;
    /// <summary>Grenzen einer Ganzzahl mit AWidth Bytes; False ohne bekannte Breite.</summary>
    class function IntegerRange(AWidth: Integer; ASigned: Boolean; out ALow, AHigh: string): Boolean; static;
    /// <summary>Ziel von write in der Deklaration einer Eigenschaft; '' ohne write.</summary>
    class function WriterOf(const ADeclaration: string): string; static;
    /// <summary>Art und Werte für den Ausdruck in Zeile ALine (ab 0) von ALookup.</summary>
    class function Describe(const ALookup: TEnumLookup; ALine: Integer; const AExpression: string): TLspValueEditInfo;
      static;
    class function Json(const AInfo: TLspValueEditInfo): TJSONObject; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReadText: TCompletionReadText;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.ExpressionTypes.Contract,
  Atlas.Common.Semantics.ExpressionTypes.Operators,
  Atlas.Common.Lsp.ExpressionType,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TValueEditText = (ArgumentsExpected, DocumentIsNotOpen);

const
  cTexts: array[TValueEditText] of TAtlasText = (
    (De: 'Erwartet werden URI, Zeile und Ausdruck'; En: 'URI, line and expression expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '));

{$SCOPEDENUMS OFF}

const
  cIdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  /// <summary>Farbtypen mit Farbauswahl.</summary>
  cColorTypes: array[0..1] of string = ('TColor', 'TAlphaColor');
  cByteBits = 8;
  /// <summary>Breite von Int64 und UInt64 in Bytes.</summary>
  cWidth64 = 8;

class function TLspValueEdit.FindExpression(const ALine, AExpression: string): Integer;
var
  mFrom, mAt, mAfter: Integer;
begin
  Result := -1;
  if AExpression = '' then
  begin
    Exit;
  end;
  mFrom := 1;
  repeat
    mAt := Pos(AExpression, ALine, mFrom);
    if mAt = 0 then
    begin
      Exit;
    end;
    mAfter := mAt + Length(AExpression);
    if ((mAt = 1) or not CharInSet(ALine[mAt - 1], cIdentChars + ['.'])) and
      ((mAfter > Length(ALine)) or not CharInSet(ALine[mAfter], cIdentChars)) then
    begin
      Exit(mAt - 1);
    end;
    mFrom := mAt + 1;
  until False;
end;

class function TLspValueEdit.IntegerRange(AWidth: Integer; ASigned: Boolean; out ALow, AHigh: string): Boolean;
var
  mBits: Integer;
begin
  ALow := '';
  AHigh := '';
  Result := AWidth in [1, 2, 4, cWidth64];
  if not Result then
  begin
    Exit;
  end;
  mBits := AWidth * cByteBits;
  if AWidth = cWidth64 then
  begin
    if ASigned then
    begin
      ALow := IntToStr(Low(Int64));
      AHigh := IntToStr(High(Int64));
    end
    else
    begin
      ALow := '0';
      AHigh := UIntToStr(High(UInt64));
    end;
  end
  else if ASigned then
  begin
    ALow := IntToStr(-(Int64(1) shl (mBits - 1)));
    AHigh := IntToStr((Int64(1) shl (mBits - 1)) - 1);
  end
  else
  begin
    ALow := '0';
    AHigh := IntToStr((Int64(1) shl mBits) - 1);
  end;
end;

class function TLspValueEdit.WriterOf(const ADeclaration: string): string;
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(ADeclaration, '\bwrite\s+([A-Za-z_][A-Za-z0-9_.]*)', [roIgnoreCase]);
  Result := '';
  if mMatch.Success then
  begin
    Result := mMatch.Groups[1].Value;
  end;
end;

function IsColorType(const ATypeName: string): Boolean;
var
  mName, mColor: string;
begin
  mName := ATypeName;
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  for mColor in cColorTypes do
  begin
    if SameText(mName, mColor) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Art aus der Kategorie eines eingebauten Typs; '' ohne.</summary>
function KindOfBuiltin(const ATypeName: string; var AInfo: TLspValueEditInfo): string;
var
  mWidth: Integer;
  mSigned: Boolean;
begin
  case TExpressionOperators.CategoryOf(ATypeName, mWidth, mSigned) of
    TExpressionCategory.Integer_:
      begin
        TLspValueEdit.IntegerRange(mWidth, mSigned, AInfo.Low, AInfo.High);
        Result := 'integer';
      end;
    TExpressionCategory.Float, TExpressionCategory.Currency_:
      Result := 'float';
    TExpressionCategory.Boolean_:
      Result := 'boolean';
    TExpressionCategory.Char_:
      Result := 'char';
    TExpressionCategory.String_:
      Result := 'string';
  else
    Result := '';
  end;
end;

/// <summary>Setter bzw. readOnly, wenn an ALine/ACharacter (letztes Zeichen des Ausdrucks) eine Eigenschaft steht.
/// </summary>
procedure ReadSetter(const ALookup: TEnumLookup; ALine, ACharacter: Integer; var AInfo: TLspValueEditInfo);
var
  mSymbol: TResolvedSymbol;
  mWriter: string;
begin
  mSymbol := ALookup.Resolver.Resolve(ALookup.Tree, ALookup.FileName, TTextPosition.Create(ALine, ACharacter));
  if not mSymbol.Found or (mSymbol.SymbolKind <> TIndexSymbolKind.Property_) then
  begin
    Exit;
  end;
  mWriter := TLspValueEdit.WriterOf(TCompletionValues.DeclarationOf(ALookup, mSymbol));
  AInfo.ReadOnly := mWriter = '';
  // write FBetrag schreibt das Feld direkt: kein Aufruf.
  if not TRegEx.IsMatch(mWriter, '^F[A-Z]') then
  begin
    AInfo.Setter := mWriter;
  end;
end;

class function TLspValueEdit.Describe(const ALookup: TEnumLookup; ALine: Integer;
  const AExpression: string): TLspValueEditInfo;
var
  mLines: TArray<string>;
  mStart: Integer;
  mRange: TTextRange;
  mType: TExpressionTypeInfo;
  mTable: TLineTable;
  mIsSet: Boolean;
begin
  Result := Default(TLspValueEditInfo);
  Result.Expression := AExpression;
  Result.Kind := 'other';
  mLines := TextLines(ALookup.Text);
  if (ALine < 0) or (ALine > System.High(mLines)) then
  begin
    Exit;
  end;
  mStart := FindExpression(mLines[ALine], AExpression);
  if mStart < 0 then
  begin
    Exit;
  end;
  mRange := TTextRange.Create(TTextPosition.Create(ALine, mStart),
    TTextPosition.Create(ALine, mStart + Length(AExpression)));
  mType := TLspExpressionType.Describe(ALookup.Resolver, ALookup.Tree, ALookup.FileName, ALookup.Text, ALookup.Index,
    TExpressionTypeQuery.Create(mRange, False));
  Result.TypeName := mType.TypeName;
  ReadSetter(ALookup, ALine, mStart + Length(AExpression) - 1, Result);
  if IsColorType(mType.TypeName) then
  begin
    Result.Kind := 'color';
    Exit;
  end;
  Result.Kind := KindOfBuiltin(mType.BaseName, Result);
  if Result.Kind = '' then
  begin
    Result.Kind := KindOfBuiltin(mType.TypeName, Result);
  end;
  if Result.Kind <> '' then
  begin
    Exit;
  end;
  Result.Kind := 'other';
  mTable := TLineTable.Build(ALookup.Text);
  if TCompletionValues.EnumOfType(ALookup, mTable.OffsetAt(mRange.StartPos), mType.TypeName, Result.Values, mIsSet,
    Result.Prefix) then
  begin
    Result.Kind := 'enum';
    if mIsSet then
    begin
      Result.Kind := 'set';
    end;
  end;
end;

class function TLspValueEdit.Json(const AInfo: TLspValueEditInfo): TJSONObject;
var
  mValues: TJSONArray;
  mValue: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('expression', AInfo.Expression);
  Result.AddPair('type', AInfo.TypeName);
  Result.AddPair('kind', AInfo.Kind);
  mValues := TJSONArray.Create;
  Result.AddPair('values', mValues);
  for mValue in AInfo.Values do
  begin
    mValues.Add(mValue);
  end;
  Result.AddPair('prefix', AInfo.Prefix);
  Result.AddPair('low', AInfo.Low);
  Result.AddPair('high', AInfo.High);
  Result.AddPair('setter', AInfo.Setter);
  Result.AddPair('readOnly', TJSONBool.Create(AInfo.ReadOnly));
end;

class function TLspValueEdit.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReadText: TCompletionReadText;
  const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mLookup: TEnumLookup;
begin
  if (AArguments = nil) or (AArguments.Count < 3) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONNumber) or not (AArguments.Items[2] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TValueEditText.ArgumentsExpected].Text);
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TValueEditText.DocumentIsNotOpen].Text + mUri);
  end;
  mShared := TSyntaxTreeCache.Get(mDocument);
  mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    mResolver.Namespaces := ANamespaces;
    mLookup := Default(TEnumLookup);
    mLookup.Resolver := mResolver;
    mLookup.Index := AIndex;
    mLookup.Tree := mShared.Tree;
    mLookup.Text := mDocument.Text;
    mLookup.FileName := TDocumentUris.ToPath(mUri);
    mLookup.ReadText := AReadText;
    Result := Json(Describe(mLookup, TJSONNumber(AArguments.Items[1]).AsInt, Trim(AArguments.Items[2].Value)));
  finally
    mResolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ValueEdit', cTexts);

end.
