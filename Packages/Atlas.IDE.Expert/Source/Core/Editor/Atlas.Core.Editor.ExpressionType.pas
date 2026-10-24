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
    Command = 'atlas.server.expressionType';
    /// <summary>Strg+Umschalt+T.</summary>
    DefaultKey = $6054;
    ErrorNoExpression = 'noExpression';
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

function ReadPosition(const AValue: TJSONValue; out APosition: TLspTextPosition): Boolean;
var
  Line, Character: Integer;
begin
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>('line', Line) and
    TJSONObject(AValue).TryGetValue<Integer>('character', Character);
  if Result then
    APosition := TLspTextPosition.Create(Line, Character);
end;

function ReadRange(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and ReadPosition(TJSONObject(AValue).GetValue('start'), ARange.StartPos) and
    ReadPosition(TJSONObject(AValue).GetValue('end'), ARange.EndPos);
end;

function StringOf(const AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
    Result := AObject.GetValue(AName).Value;
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
  Parts: TArray<string>;
begin
  Parts := ADetail.Split(['|']);
  if (Length(Parts) = 3) and (Parts[1] = '') then
    Result := Format(ATexts.OperatorUnary, [Parts[0], Parts[2]])
  else if Length(Parts) = 3 then
    Result := Format(ATexts.OperatorMismatch, [Parts[0], Parts[1], Parts[2]])
  else
    Result := Format(ATexts.Unknown, [ADetail]);
end;

function Row(AKind: TAtlasExpressionTypeRowKind; const AText: string; ALink: Boolean): TAtlasExpressionTypeRow;
begin
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Link := ALink;
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
  List: TJSONArray;
  Range, Options: TJSONObject;
begin
  List := TJSONArray.Create;
  try
    List.Add(AUri);
    Range := TJSONObject.Create;
    Range.AddPair('start', PositionJson(ARange.StartPos));
    Range.AddPair('end', PositionJson(ARange.EndPos));
    List.AddElement(Range);
    Options := TJSONObject.Create;
    Options.AddPair('expand', TJSONBool.Create(AExpand));
    Options.AddPair('conversions', TJSONBool.Create(AConversions));
    Options.AddPair('constValue', TJSONBool.Create(AConstValue));
    List.AddElement(Options);
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

class function TAtlasExpressionType.Read(const AAnswer: TJSONValue; out AInfo: TAtlasExpressionTypeInfo): Boolean;
var
  Answer, Location, Error, Item: TJSONObject;
  Element: TJSONValue;
  Conversion: TAtlasExpressionConversion;
  Number: Integer;
  Value: Int64;
begin
  AInfo := Default(TAtlasExpressionTypeInfo);
  Result := AAnswer is TJSONObject;
  if not Result then
    Exit;
  Answer := TJSONObject(AAnswer);
  ReadRange(Answer.GetValue('range'), AInfo.Range);
  AInfo.Expression := StringOf(Answer, 'expression');
  AInfo.TypeName := StringOf(Answer, 'type');
  AInfo.BaseName := StringOf(Answer, 'base');
  AInfo.Overload := StringOf(Answer, 'overload');
  if Answer.GetValue('location') is TJSONObject then
  begin
    Location := TJSONObject(Answer.GetValue('location'));
    AInfo.FileName := StringOf(Location, 'file');
    if Location.TryGetValue<Integer>('line', Number) then
      AInfo.Line := Number;
    if Location.TryGetValue<Integer>('character', Number) then
      AInfo.Character := Number;
  end;
  if Answer.GetValue('conversions') is TJSONArray then
    for Element in TJSONArray(Answer.GetValue('conversions')) do
      if Element is TJSONObject then
      begin
        Item := TJSONObject(Element);
        Conversion := Default(TAtlasExpressionConversion);
        Conversion.Expression := StringOf(Item, 'expression');
        Conversion.FromType := StringOf(Item, 'from');
        Conversion.ToType := StringOf(Item, 'to');
        Conversion.Convert := StringOf(Item, 'kind') = 'convert';
        AInfo.Conversions := AInfo.Conversions + [Conversion];
      end;
  if (Answer.GetValue('value') is TJSONNumber) and Answer.TryGetValue<Int64>('value', Value) then
  begin
    AInfo.HasValue := True;
    AInfo.Value := Value;
  end;
  if Answer.GetValue('error') is TJSONObject then
  begin
    Error := TJSONObject(Answer.GetValue('error'));
    AInfo.Error := StringOf(Error, 'kind');
    AInfo.ErrorDetail := StringOf(Error, 'detail');
  end;
  // Weder Typ noch Fehler: keine verwertbare Antwort.
  Result := AInfo.Usable;
end;

class function TAtlasExpressionType.Rows(const AInfo: TAtlasExpressionTypeInfo;
  const ATexts: TAtlasExpressionTypeTexts): TArray<TAtlasExpressionTypeRow>;
var
  Conversion: TAtlasExpressionConversion;
  Text, Detail: string;
begin
  Result := nil;
  if AInfo.Expression <> '' then
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Expression, AInfo.Expression, False)];
  if AInfo.Error <> '' then
  begin
    Detail := AInfo.ErrorDetail;
    if Detail = '' then
      Detail := AInfo.Expression;
    if AInfo.Error = ErrorNoExpression then
      Text := ATexts.NoExpression
    else if AInfo.Error = 'unknownName' then
      Text := Format(ATexts.UnknownName, [Detail])
    else if AInfo.Error = 'operator' then
      Text := OperatorText(Detail, ATexts)
    else if AInfo.Error = 'noResult' then
      Text := Format(ATexts.NoResult, [Detail])
    else
      Text := Format(ATexts.Unknown, [Detail]);
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Error, Text, False)];
  end
  else
  begin
    Text := AInfo.TypeName;
    if (AInfo.BaseName <> '') and not SameText(AInfo.BaseName, AInfo.TypeName) then
      Text := Text + ' = ' + AInfo.BaseName;
    Result := Result + [Row(TAtlasExpressionTypeRowKind.TypeName, Text, AInfo.HasLocation)];
    if AInfo.HasValue then
      Result := Result + [Row(TAtlasExpressionTypeRowKind.Value, Format(ATexts.Value, [IntToStr(AInfo.Value)]),
        False)];
    for Conversion in AInfo.Conversions do
    begin
      if Conversion.Convert then
        Text := Format(ATexts.Convert, [Conversion.Expression, Conversion.FromType, Conversion.ToType])
      else
        Text := Format(ATexts.Widen, [Conversion.Expression, Conversion.FromType, Conversion.ToType]);
      Result := Result + [Row(TAtlasExpressionTypeRowKind.Conversion, Text, False)];
    end;
    if AInfo.Overload <> '' then
      Result := Result + [Row(TAtlasExpressionTypeRowKind.Overload, Format(ATexts.Overload, [AInfo.Overload]),
        False)];
  end;
  // Erweitern nur, wo es einen Ausdruck gibt.
  if (ATexts.Expand <> '') and (AInfo.Error <> ErrorNoExpression) then
    Result := Result + [Row(TAtlasExpressionTypeRowKind.Hint, ATexts.Expand, False)];
end;

class procedure TAtlasExpressionType.NextRequest(const AShown: TAtlasExpressionTypeShown; const AFileName,
  AText: string; const ASelection: TLspRange; out ARange: TLspRange; out AExpand: Boolean);
begin
  AExpand := AShown.Active and SameText(AShown.FileName, AFileName) and (AShown.Text = AText) and
    AShown.Selection.Same(ASelection);
  if AExpand then
    ARange := AShown.Range
  else
    ARange := ASelection;
end;

class function TAtlasExpressionType.KeepShown(AExpand: Boolean; const AInfo: TAtlasExpressionTypeInfo): Boolean;
begin
  Result := AExpand and (AInfo.Error = ErrorNoExpression);
end;

class function TAtlasExpressionType.SpanOnLine(const ARange: TLspRange; ALine, ALength: Integer;
  out ASpan: TAtlasExpressionTypeSpan): Boolean;
begin
  ASpan := Default(TAtlasExpressionTypeSpan);
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line) and not ARange.IsEmpty;
  if not Result then
    Exit;
  ASpan.Start := 0;
  if ALine = ARange.StartPos.Line then
    ASpan.Start := ARange.StartPos.Character;
  ASpan.Stop := ALength;
  if ALine = ARange.EndPos.Line then
    ASpan.Stop := ARange.EndPos.Character;
  if ASpan.Stop > ALength then
    ASpan.Stop := ALength;
  Result := ASpan.Stop > ASpan.Start;
end;

end.
