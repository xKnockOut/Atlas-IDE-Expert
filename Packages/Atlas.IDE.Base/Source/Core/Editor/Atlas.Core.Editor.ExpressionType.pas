unit Atlas.Core.Editor.ExpressionType;

// Typ des markierten Ausdrucks (#689), Kern im Plugin ohne VCL und ToolsAPI:
// Argumente für atlas.server.expressionType, die Antwort als Datensatz, die
// Zeilen des Tooltips und die Entscheidung, ob ein erneutes Drücken des
// Kürzels auf den umschließenden Ausdruck erweitert.
// - Erweitern: Steht der Tooltip noch, ist die Datei dieselbe, ihr Text
//   unverändert und die Markierung bzw. Schreibmarke dieselbe wie beim
//   Zeigen, fragt das Plugin mit dem Bereich der letzten Antwort und
//   expand = true. Sonst gilt die aktuelle Markierung.
// - Gibt es beim Erweitern keinen größeren Ausdruck (noExpression), bleibt der
//   Tooltip, wie er ist.
// Tooltip-Zeilen:
//   Price * Count + Shipping          (Ausdruck)
//   TPreis = Currency                 (Typ; Klick springt zur Deklaration)
//   = 48                              (Wert konstanter Ausdrücke)
//   Count: Integer wird zu Currency erweitert
//   Überladung: function Max(A, B: Double): Double;
//   Kein Typ: unbekannter Name Nichts (statt Typ)
//   Strg+Umschalt+T erneut: umschließender Ausdruck

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.TextChanges;

type
  /// <summary>Implizite Umwandlung eines Teilausdrucks.</summary>
  TAtlasExpressionConversion = record
    Expression: string;
    FromType: string;
    ToType: string;
    /// <summary>True: umgewandelt (etwa Variant zu string); False: erweitert (Integer zu Int64).</summary>
    Convert: Boolean;
  end;

  TAtlasExpressionTypeInfo = record
    /// <summary>Bereich des beschriebenen Ausdrucks (Zeilen und Zeichen ab 0).</summary>
    Range: TLspRange;
    Expression: string;
    TypeName: string;
    /// <summary>Grundtyp eines Alias; '' ohne Alias.</summary>
    BaseName: string;
    /// <summary>Deklaration des Typs; FileName '' ohne Fundort.</summary>
    FileName: string;
    Line: Integer;
    Character: Integer;
    Conversions: TArray<TAtlasExpressionConversion>;
    /// <summary>Signatur der gewählten Überladung; '' ohne.</summary>
    Overload: string;
    HasValue: Boolean;
    Value: Int64;
    /// <summary>noExpression, unknownName, operator, noResult, unknown; '' ohne Fehler.</summary>
    Error: string;
    ErrorDetail: string;
    function HasLocation: Boolean;
    /// <summary>Typ oder Fehler vorhanden: verwertbare Antwort.</summary>
    function Usable: Boolean;
  end;

  {$SCOPEDENUMS ON}
  TAtlasExpressionTypeRowKind = (Expression, TypeName, Value, Conversion, Overload, Error, Hint);
  {$SCOPEDENUMS OFF}

  TAtlasExpressionTypeRow = record
    Kind: TAtlasExpressionTypeRowKind;
    Text: string;
    /// <summary>Anklickbar (Sprung zur Deklaration des Typs).</summary>
    Link: Boolean;
  end;

  /// <summary>Texte des Tooltips; die UI füllt sie aus Atlas.UI.Strings. Format-Texte mit %s.</summary>
  TAtlasExpressionTypeTexts = record
    /// <summary>„= %s“.</summary>
    Value: string;
    /// <summary>„%s: %s wird zu %s erweitert“ (Ausdruck, von, nach).</summary>
    Widen: string;
    /// <summary>„%s: %s wird zu %s umgewandelt“.</summary>
    Convert: string;
    /// <summary>„Überladung: %s“.</summary>
    Overload: string;
    NoExpression: string;
    /// <summary>„Kein Typ: unbekannter Name %s“.</summary>
    UnknownName: string;
    /// <summary>„Kein Typ: %s passt nicht zu %s und %s“ (Operator, linker und rechter Typ).</summary>
    OperatorMismatch: string;
    /// <summary>„Kein Typ: %s passt nicht zu %s“ (Operator, Typ des Operanden).</summary>
    OperatorUnary: string;
    /// <summary>„Kein Typ: %s liefert keinen Wert“.</summary>
    NoResult: string;
    /// <summary>„Kein Typ: %s nicht auflösbar“.</summary>
    Unknown: string;
    /// <summary>„%s erneut: umschließender Ausdruck“ (Tastenkürzel); '' = keine Zeile.</summary>
    Expand: string;
  end;

  /// <summary>Was der Tooltip gerade zeigt; für die Entscheidung über das Erweitern.</summary>
  TAtlasExpressionTypeShown = record
    Active: Boolean;
    FileName: string;
    Text: string;
    /// <summary>Markierung bzw. Schreibmarke beim Zeigen.</summary>
    Selection: TLspRange;
    /// <summary>Bereich des gezeigten Ausdrucks.</summary>
    Range: TLspRange;
  end;

  /// <summary>Teil einer Zeile, den die Hervorhebung des Ausdrucks deckt; Zeichen ab 0, Ende ausschließlich.
  /// </summary>
  TAtlasExpressionTypeSpan = record
    Start: Integer;
    Stop: Integer;
  end;

  TAtlasExpressionType = class
  public const
    cCommand = 'atlas.server.expressionType';
    cErrorNoExpression = 'noExpression';
  public
    /// <summary>[uri, {start, end}, {expand, conversions, constValue}].</summary>
    class function Arguments(const AUri: string; const ARange: TLspRange; AExpand, AConversions,
      AConstValue: Boolean): string; static;
    /// <summary>Antwort lesen; False bei leerer oder fremder Antwort (dann ist AInfo.Usable False).</summary>
    class function Read(const AAnswer: TJSONValue; out AInfo: TAtlasExpressionTypeInfo): Boolean; static;
    /// <summary>Zeilen des Tooltips in der Reihenfolge der Anzeige.</summary>
    class function Rows(const AInfo: TAtlasExpressionTypeInfo;
      const ATexts: TAtlasExpressionTypeTexts): TArray<TAtlasExpressionTypeRow>; static;
    /// <summary>Bereich und expand für das nächste Drücken: erweitert nur, wenn AShown noch für dieselbe Datei,
    /// denselben Text und dieselbe Markierung gilt.</summary>
    class procedure NextRequest(const AShown: TAtlasExpressionTypeShown; const AFileName, AText: string;
      const ASelection: TLspRange; out ARange: TLspRange; out AExpand: Boolean); static;
    /// <summary>Beim Erweitern ohne größeren Ausdruck bleibt der Tooltip stehen.</summary>
    class function KeepShown(AExpand: Boolean; const AInfo: TAtlasExpressionTypeInfo): Boolean; static;
    /// <summary>Teil von Zeile ALine (ab 0, Länge ALength), den ARange deckt; False ohne.</summary>
    class function SpanOnLine(const ARange: TLspRange; ALine, ALength: Integer;
      out ASpan: TAtlasExpressionTypeSpan): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Json;

function ReadPosition(const AValue: TJSONValue; out APosition: TLspTextPosition): Boolean;
var
  mLine, mCharacter: Integer;
begin
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>('line', mLine) and
    TJSONObject(AValue).TryGetValue<Integer>('character', mCharacter);
  if Result then
  begin
    APosition := TLspTextPosition.Create(mLine, mCharacter);
  end;
end;

function ReadRange(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and ReadPosition(TJSONObject(AValue).GetValue('start'), ARange.StartPos) and
    ReadPosition(TJSONObject(AValue).GetValue('end'), ARange.EndPos);
end;

function PositionJson(const APosition: TLspTextPosition): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(APosition.Line));
  Result.AddPair('character', TJSONNumber.Create(APosition.Character));
end;

/// <summary>Detail des Servers "Operator|links|rechts" bzw. "Operator||Operand"; sonst der Text, wie er ist.
/// </summary>
function OperatorText(const ADetail: string; const ATexts: TAtlasExpressionTypeTexts): string;
var
  mParts: TArray<string>;
begin
  mParts := ADetail.Split(['|']);
  if (Length(mParts) = 3) and (mParts[1] = '') then
  begin
    Result := Format(ATexts.OperatorUnary, [mParts[0], mParts[2]]);
  end
  else if Length(mParts) = 3 then
  begin
    Result := Format(ATexts.OperatorMismatch, [mParts[0], mParts[1], mParts[2]]);
  end
  else
  begin
    Result := Format(ATexts.Unknown, [ADetail]);
  end;
end;

function Row(AKind: TAtlasExpressionTypeRowKind; const AText: string; ALink: Boolean): TAtlasExpressionTypeRow;
begin
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Link := ALink;
end;

procedure ReadLocation(const AAnswer: TJSONObject; var AInfo: TAtlasExpressionTypeInfo);
var
  mLocation: TJSONObject;
  mNumber: Integer;
begin
  if AAnswer.GetValue('location') is TJSONObject then
  begin
    mLocation := TJSONObject(AAnswer.GetValue('location'));
    AInfo.FileName := TJsonRead.Text(mLocation, 'file');
    if mLocation.TryGetValue<Integer>('line', mNumber) then
    begin
      AInfo.Line := mNumber;
    end;
    if mLocation.TryGetValue<Integer>('character', mNumber) then
    begin
      AInfo.Character := mNumber;
    end;
  end;
end;

function ReadConversion(const AItem: TJSONObject): TAtlasExpressionConversion;
begin
  Result := Default(TAtlasExpressionConversion);
  Result.Expression := TJsonRead.Text(AItem, 'expression');
  Result.FromType := TJsonRead.Text(AItem, 'from');
  Result.ToType := TJsonRead.Text(AItem, 'to');
  Result.Convert := TJsonRead.Text(AItem, 'kind') = 'convert';
end;

function ReadConversions(const AValue: TJSONValue): TArray<TAtlasExpressionConversion>;
var
  mElement: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mElement in TJSONArray(AValue) do
    begin
      if mElement is TJSONObject then
      begin
        Result := Result + [ReadConversion(TJSONObject(mElement))];
      end;
    end;
  end;
end;

procedure ReadValueAndError(const AAnswer: TJSONObject; var AInfo: TAtlasExpressionTypeInfo);
var
  mError: TJSONObject;
  mValue: Int64;
begin
  if (AAnswer.GetValue('value') is TJSONNumber) and AAnswer.TryGetValue<Int64>('value', mValue) then
  begin
    AInfo.HasValue := True;
    AInfo.Value := mValue;
  end;
  if AAnswer.GetValue('error') is TJSONObject then
  begin
    mError := TJSONObject(AAnswer.GetValue('error'));
    AInfo.Error := TJsonRead.Text(mError, 'kind');
    AInfo.ErrorDetail := TJsonRead.Text(mError, 'detail');
  end;
end;

/// <summary>Text der Fehlerzeile nach der Art des Fehlers.</summary>
function ErrorText(const AInfo: TAtlasExpressionTypeInfo; const ATexts: TAtlasExpressionTypeTexts): string;
var
  mDetail: string;
begin
  mDetail := AInfo.ErrorDetail;
  if mDetail = '' then
  begin
    mDetail := AInfo.Expression;
  end;
  if AInfo.Error = TAtlasExpressionType.cErrorNoExpression then
  begin
    Result := ATexts.NoExpression;
  end
  else if AInfo.Error = 'unknownName' then
  begin
    Result := Format(ATexts.UnknownName, [mDetail]);
  end
  else if AInfo.Error = 'operator' then
  begin
    Result := OperatorText(mDetail, ATexts);
  end
  else if AInfo.Error = 'noResult' then
  begin
    Result := Format(ATexts.NoResult, [mDetail]);
  end
  else
  begin
    Result := Format(ATexts.Unknown, [mDetail]);
  end;
end;

function ConversionText(const AConversion: TAtlasExpressionConversion; const ATexts: TAtlasExpressionTypeTexts):
  string;
begin
  if AConversion.Convert then
  begin
    Result := Format(ATexts.Convert, [AConversion.Expression, AConversion.FromType, AConversion.ToType]);
  end
  else
  begin
    Result := Format(ATexts.Widen, [AConversion.Expression, AConversion.FromType, AConversion.ToType]);
  end;
end;

/// <summary>Zeilen ohne Fehler: Typ (mit Basistyp), Wert, Umwandlungen, Überladung.</summary>
function TypeRows(const AInfo: TAtlasExpressionTypeInfo; const ATexts: TAtlasExpressionTypeTexts):
  TArray<TAtlasExpressionTypeRow>;
var
  mConversion: TAtlasExpressionConversion;
  mText: string;
begin
  mText := AInfo.TypeName;
  if (AInfo.BaseName <> '') and not SameText(AInfo.BaseName, AInfo.TypeName) then
  begin
    mText := mText + ' = ' + AInfo.BaseName;
  end;
  Result := TArray<TAtlasExpressionTypeRow>.Create(Row(TAtlasExpressionTypeRowKind.TypeName, mText,
    AInfo.HasLocation));
  if AInfo.HasValue then
  begin
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Value, Format(ATexts.Value, [IntToStr(AInfo.Value)]),
      False)];
  end;
  for mConversion in AInfo.Conversions do
  begin
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Conversion, ConversionText(mConversion, ATexts), False)];
  end;
  if AInfo.Overload <> '' then
  begin
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Overload, Format(ATexts.Overload, [AInfo.Overload]),
      False)];
  end;
end;

{ TAtlasExpressionTypeInfo }

function TAtlasExpressionTypeInfo.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

function TAtlasExpressionTypeInfo.Usable: Boolean;
begin
  Result := (TypeName <> '') or (Error <> '');
end;

{ TAtlasExpressionType }

class function TAtlasExpressionType.Arguments(const AUri: string; const ARange: TLspRange; AExpand, AConversions,
  AConstValue: Boolean): string;
var
  mList: TJSONArray;
  mRange, mOptions: TJSONObject;
begin
  mList := TJSONArray.Create;
  try
    mList.Add(AUri);
    mRange := TJSONObject.Create;
    mRange.AddPair('start', PositionJson(ARange.StartPos));
    mRange.AddPair('end', PositionJson(ARange.EndPos));
    mList.AddElement(mRange);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('expand', TJSONBool.Create(AExpand));
    mOptions.AddPair('conversions', TJSONBool.Create(AConversions));
    mOptions.AddPair('constValue', TJSONBool.Create(AConstValue));
    mList.AddElement(mOptions);
    Result := mList.ToJSON;
  finally
    mList.Free;
  end;
end;

class function TAtlasExpressionType.Read(const AAnswer: TJSONValue; out AInfo: TAtlasExpressionTypeInfo): Boolean;
var
  mAnswer: TJSONObject;
begin
  AInfo := Default(TAtlasExpressionTypeInfo);
  Result := AAnswer is TJSONObject;
  if Result then
  begin
    mAnswer := TJSONObject(AAnswer);
    ReadRange(mAnswer.GetValue('range'), AInfo.Range);
    AInfo.Expression := TJsonRead.Text(mAnswer, 'expression');
    AInfo.TypeName := TJsonRead.Text(mAnswer, 'type');
    AInfo.BaseName := TJsonRead.Text(mAnswer, 'base');
    AInfo.Overload := TJsonRead.Text(mAnswer, 'overload');
    ReadLocation(mAnswer, AInfo);
    AInfo.Conversions := ReadConversions(mAnswer.GetValue('conversions'));
    ReadValueAndError(mAnswer, AInfo);
    // Weder Typ noch Fehler: keine verwertbare Antwort.
    Result := AInfo.Usable;
  end;
end;

class function TAtlasExpressionType.Rows(const AInfo: TAtlasExpressionTypeInfo;
  const ATexts: TAtlasExpressionTypeTexts): TArray<TAtlasExpressionTypeRow>;
begin
  Result := nil;
  if AInfo.Expression <> '' then
  begin
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Expression, AInfo.Expression, False)];
  end;
  if AInfo.Error <> '' then
  begin
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Error, ErrorText(AInfo, ATexts), False)];
  end
  else
  begin
    Result := Result + TypeRows(AInfo, ATexts);
  end;
  // Erweitern nur, wo es einen Ausdruck gibt.
  if (ATexts.Expand <> '') and (AInfo.Error <> cErrorNoExpression) then
  begin
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Hint, ATexts.Expand, False)];
  end;
end;

class procedure TAtlasExpressionType.NextRequest(const AShown: TAtlasExpressionTypeShown; const AFileName,
  AText: string; const ASelection: TLspRange; out ARange: TLspRange; out AExpand: Boolean);
begin
  AExpand := AShown.Active and SameText(AShown.FileName, AFileName) and (AShown.Text = AText) and
    AShown.Selection.Same(ASelection);
  if AExpand then
  begin
    ARange := AShown.Range;
  end
  else
  begin
    ARange := ASelection;
  end;
end;

class function TAtlasExpressionType.KeepShown(AExpand: Boolean; const AInfo: TAtlasExpressionTypeInfo): Boolean;
begin
  Result := AExpand and (AInfo.Error = cErrorNoExpression);
end;

class function TAtlasExpressionType.SpanOnLine(const ARange: TLspRange; ALine, ALength: Integer;
  out ASpan: TAtlasExpressionTypeSpan): Boolean;
begin
  ASpan := Default(TAtlasExpressionTypeSpan);
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line) and not ARange.IsEmpty;
  if not Result then
  begin
    Exit;
  end;
  ASpan.Start := 0;
  if ALine = ARange.StartPos.Line then
  begin
    ASpan.Start := ARange.StartPos.Character;
  end;
  ASpan.Stop := ALength;
  if ALine = ARange.EndPos.Line then
  begin
    ASpan.Stop := ARange.EndPos.Character;
  end;
  if ASpan.Stop > ALength then
  begin
    ASpan.Stop := ALength;
  end;
  Result := ASpan.Stop > ASpan.Start;
end;

end.
