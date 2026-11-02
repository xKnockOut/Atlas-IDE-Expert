unit Atlas.Common.Editing.PostfixTemplates;

// Postfix-Vorlagen (#188, ARG-053): Ein Kürzel hinter einem Ausdruck formt ihn um.
//   Liste.for, Liste.forin   for var Item in Liste do        aufzählbar
//   Obj.tryf                 try … finally Obj.Free; end;    Klasse
//   X.ifa, X.notnil          if Assigned(X) then             Klasse, Interface, Zeiger
//   X.nil                    if not Assigned(X) then         Klasse, Interface, Zeiger
//   B.not                    not B                           Boolean
//   B.if                     if B then                       Boolean
//   S.fmt                    Format(S, [])                   String
//   Obj.free                 FreeAndNil(Obj);                Klasse
//   TFoo.Create.try          var Foo := TFoo.Create; try … finally Foo.Free; end;   Konstruktoraufruf
//   X.var                    var Name := X;                  bekannter Typ
//   X.exit                   Exit(X);                        in einer Funktion
// Anweisungen (for, if, try …) gibt es nur, wenn der Ausdruck die Zeile beginnt. Nach einem Kopf wie
// "if … then" steht der Cursor eingerückt in der Folgezeile.
//
// Eigene Vorlagen (#51-Format mit Kopfzeile "postfix: true"): $expr steht für den Ausdruck, Platzhalter wie in
// #51 (${1:Name}, $0, "$$" für ein "$"). Die Bedingung "type:" ist ein Merkmal (any, reference, class, string,
// boolean, enumerable, constructor, function) oder ein Typname; dann passt der Typ selbst und jeder Nachfahr.
//
// Mit ASnippet entsteht ein LSP-Snippet (${1:Item}, $0; "\", "$" und "}" maskiert), sonst Klartext.
// Angeboten wird nur, was zum Typ passt; den Typ ermittelt die Vervollständigung über die Namensauflösung (#17)
// und übergibt ihn als TPostfixTraits. Diese Unit erzeugt nur Text.

interface

uses
  System.SysUtils;

type
  /// <summary>Was über den Typ des Ausdrucks bekannt ist.</summary>
  TPostfixTraits = record
    /// <summary>Array, Menge oder Typ mit GetEnumerator.</summary>
    Enumerable: Boolean;
    /// <summary>Klasse: Free ist sinnvoll.</summary>
    IsClass: Boolean;
    /// <summary>Klasse, Interface oder Zeiger: Assigned ist sinnvoll.</summary>
    IsReference: Boolean;
    IsString: Boolean;
    IsBoolean: Boolean;
    /// <summary>Der Ausdruck ruft einen Konstruktor auf (TFoo.Create).</summary>
    IsConstructorCall: Boolean;
    /// <summary>Der Cursor steht in einer Funktion (Exit mit Wert ist erlaubt).</summary>
    InFunction: Boolean;
    /// <summary>Elementtyp für die klassische for-in-Schleife; '' wenn unbekannt.</summary>
    ElementType: string;
    /// <summary>Typ des Ausdrucks, wie er im var-Abschnitt stehen kann; '' wenn unbekannt.</summary>
    TypeName: string;
  end;

  TPostfixTemplate = record
    Key: string;
    Description: string;
    /// <summary>Erzeugt eine Anweisung: nur, wenn der Ausdruck die Zeile beginnt.</summary>
    Statement: Boolean;
    /// <summary>Eigene Vorlage: Text im Format von #51 mit $expr; '' bei mitgelieferten.</summary>
    Body: string;
    /// <summary>Eigene Vorlage: Merkmal oder Typname; '' = any.</summary>
    Condition: string;
    class function Custom(const AKey, ADescription, ABody, ACondition: string): TPostfixTemplate; static;
    function IsCustom: Boolean;
  end;

  TPostfixExpansion = record
    /// <summary>Ersatz für "Ausdruck.Kürzel"; LSP-Snippet oder Klartext.</summary>
    Text: string;
    /// <summary>Deklaration für den var-Abschnitt ohne Inline-Variable, z. B. "Item: Integer;"; '' ohne.</summary>
    Declaration: string;
  end;

  TPostfixTemplates = class
  public const
    ItemName = 'Item';
    ExprToken = '$expr';
  public
    /// <summary>Mitgelieferte Vorlagen in der Reihenfolge der Liste.</summary>
    class function Templates: TArray<TPostfixTemplate>; static;
    /// <summary>Passt AKey zum Typ? .for klassisch braucht zusätzlich den Elementtyp.</summary>
    class function Applies(const AKey: string; const ATraits: TPostfixTraits; AInlineVar: Boolean): Boolean;
      overload; static;
    /// <summary>Wie oben für eine Vorlage; bei einer eigenen mit Typname als Bedingung entscheidet
    /// ADescends (Typ oder Nachfahr), nil = nur gleicher Name.</summary>
    class function Applies(const ATemplate: TPostfixTemplate; const ATraits: TPostfixTraits; AInlineVar: Boolean;
      const ADescends: TFunc<string, Boolean>): Boolean; overload; static;
    /// <summary>Ist ACondition ein Typname statt eines Merkmals?</summary>
    class function IsTypeCondition(const ACondition: string): Boolean; static;
    /// <summary>Ersatztext für AExpr.AKey als Klartext; AIndent ist die Einrückung der Zeile.</summary>
    class function Expand(const AKey, AExpr, AIndent, ALineBreak: string; AInlineVar: Boolean): string;
      overload; static;
    /// <summary>Ersatztext und Deklaration für AExpr.Kürzel; ASnippet: LSP-Snippet mit Platzhaltern.</summary>
    class function Expand(const ATemplate: TPostfixTemplate; const AExpr, AIndent, ALineBreak: string;
      const ATraits: TPostfixTraits; AInlineVar, ASnippet: Boolean): TPostfixExpansion; overload; static;
    /// <summary>Deklaration für den var-Abschnitt bei .for ohne Inline-Variable, z. B. "Item: Integer;".</summary>
    class function ClassicDeclaration(const ATraits: TPostfixTraits): string; static;
    /// <summary>Variablenname zum Typ: TStringList → StringList, TArray&lt;T&gt; → Values, ohne T-Vorsatz Value.
    /// </summary>
    class function SuggestName(const ATypeName: string): string; static;
    /// <summary>Elementtyp aus 'TArray&lt;T&gt;', 'array of T', 'array[..] of T', 'set of T'; '' sonst.</summary>
    class function ElementOf(const ATypeText: string): string; static;
    /// <summary>String-Typen.</summary>
    class function IsStringType(const ATypeText: string): Boolean; static;
    /// <summary>Boolesche Typen.</summary>
    class function IsBooleanType(const ATypeText: string): Boolean; static;
    /// <summary>Zeigertypen: Pointer, ^T, PChar, PByte …</summary>
    class function IsPointerType(const ATypeText: string): Boolean; static;
    /// <summary>Maskiert "\", "$" und "}" für ein LSP-Snippet.</summary>
    class function Escape(const AText: string): string; static;
    /// <summary>Text einer eigenen Vorlage (#51-Format) als LSP-Snippet bzw. Klartext; $expr wird zu AExpr,
    /// Folgezeilen bekommen AIndent.</summary>
    class function CustomText(const ABody, AExpr, AIndent, ALineBreak: string; ASnippet: Boolean): string; static;
  end;

implementation

uses
  System.StrUtils;

const
  Conditions: array[0..7] of string = ('any', 'reference', 'class', 'string', 'boolean', 'enumerable',
    'constructor', 'function');

{ TPostfixTemplate }

class function TPostfixTemplate.Custom(const AKey, ADescription, ABody, ACondition: string): TPostfixTemplate;
begin
  Result.Key := AKey;
  Result.Description := ADescription;
  Result.Statement := False;
  Result.Body := ABody;
  Result.Condition := Trim(ACondition);
end;

function TPostfixTemplate.IsCustom: Boolean;
begin
  Result := Body <> '';
end;

{ TPostfixTemplates }

class function TPostfixTemplates.Templates: TArray<TPostfixTemplate>;

  function Template(const AKey, ADescription: string; AStatement: Boolean): TPostfixTemplate;
  begin
    Result := Default(TPostfixTemplate);
    Result.Key := AKey;
    Result.Description := ADescription;
    Result.Statement := AStatement;
  end;

begin
  Result := [Template('for', 'for … in … do', True), Template('forin', 'for var Item in … do', True),
    Template('tryf', 'try … finally Free end', True), Template('ifa', 'if Assigned(…) then', True),
    Template('notnil', 'if Assigned(…) then', True), Template('nil', 'if not Assigned(…) then', True),
    Template('not', 'not …', False), Template('if', 'if … then', True), Template('fmt', 'Format(…, [])', False),
    Template('free', 'FreeAndNil(…);', True), Template('try', 'Variable := …; try … finally Free end', True),
    Template('var', 'var Name := …;', True), Template('exit', 'Exit(…);', True)];
end;

class function TPostfixTemplates.Applies(const AKey: string; const ATraits: TPostfixTraits;
  AInlineVar: Boolean): Boolean;
begin
  if MatchText(AKey, ['for', 'forin']) then
  begin
    Result := ATraits.Enumerable and (AInlineVar or (ATraits.ElementType <> ''));
  end
  else if MatchText(AKey, ['tryf', 'free']) then
  begin
    Result := ATraits.IsClass;
  end
  else if MatchText(AKey, ['ifa', 'notnil', 'nil']) then
  begin
    Result := ATraits.IsReference;
  end
  else if MatchText(AKey, ['not', 'if']) then
  begin
    Result := ATraits.IsBoolean;
  end
  else if SameText(AKey, 'fmt') then
  begin
    Result := ATraits.IsString;
  end
  else if SameText(AKey, 'try') then
  begin
    Result := ATraits.IsConstructorCall and (AInlineVar or (ATraits.TypeName <> ''));
  end
  else if SameText(AKey, 'var') then
  begin
    Result := AInlineVar or (ATraits.TypeName <> '');
  end
  else if SameText(AKey, 'exit') then
  begin
    Result := ATraits.InFunction;
  end
  else
  begin
    Result := False;
  end;
end;

class function TPostfixTemplates.IsTypeCondition(const ACondition: string): Boolean;
begin
  Result := (Trim(ACondition) <> '') and not MatchText(Trim(ACondition), Conditions);
end;

class function TPostfixTemplates.Applies(const ATemplate: TPostfixTemplate; const ATraits: TPostfixTraits;
  AInlineVar: Boolean; const ADescends: TFunc<string, Boolean>): Boolean;
var
  Condition: string;
begin
  if not ATemplate.IsCustom then
  begin
    Exit(Applies(ATemplate.Key, ATraits, AInlineVar));
  end;
  Condition := LowerCase(Trim(ATemplate.Condition));
  if (Condition = '') or (Condition = 'any') then
  begin
    Result := True;
  end
  else if Condition = 'reference' then
  begin
    Result := ATraits.IsReference;
  end
  else if Condition = 'class' then
  begin
    Result := ATraits.IsClass;
  end
  else if Condition = 'string' then
  begin
    Result := ATraits.IsString;
  end
  else if Condition = 'boolean' then
  begin
    Result := ATraits.IsBoolean;
  end
  else if Condition = 'enumerable' then
  begin
    Result := ATraits.Enumerable;
  end
  else if Condition = 'constructor' then
  begin
    Result := ATraits.IsConstructorCall;
  end
  else if Condition = 'function' then
  begin
    Result := ATraits.InFunction;
  end
  else if ATraits.TypeName = '' then
  begin
    Result := False;
  end
  else if SameText(ATraits.TypeName, Trim(ATemplate.Condition)) then
  begin
    Result := True;
  end
  else
  begin
    Result := Assigned(ADescends) and ADescends(Trim(ATemplate.Condition));
  end;
end;

class function TPostfixTemplates.Escape(const AText: string): string;
begin
  Result := AText.Replace('\', '\\').Replace('$', '\$').Replace('}', '\}');
end;

class function TPostfixTemplates.Expand(const AKey, AExpr, AIndent, ALineBreak: string; AInlineVar: Boolean): string;
var
  Template: TPostfixTemplate;
  Traits: TPostfixTraits;
begin
  Template := Default(TPostfixTemplate);
  Template.Key := AKey;
  Traits := Default(TPostfixTraits);
  Result := Expand(Template, AExpr, AIndent, ALineBreak, Traits, AInlineVar, False).Text;
end;

class function TPostfixTemplates.Expand(const ATemplate: TPostfixTemplate; const AExpr, AIndent, ALineBreak: string;
  const ATraits: TPostfixTraits; AInlineVar, ASnippet: Boolean): TPostfixExpansion;
var
  Key, Expr, Body, Name: string;

  // Platzhalter ANumber mit Vorgabe ADefault; im Klartext nur die Vorgabe.
  function Field(ANumber: Integer; const ADefault: string): string;
  begin
    if ASnippet then
    begin
      Result := Format('${%d:%s}', [ANumber, Escape(ADefault)]);
    end
    else
    begin
      Result := ADefault;
    end;
  end;

  // Endposition des Cursors.
  function Caret: string;
  begin
    if ASnippet then
    begin
      Result := '$0';
    end
    else
    begin
      Result := '';
    end;
  end;

  // Eingerückte Folgezeile nach einem Kopf wie "if … then".
  function Next: string;
  begin
    Result := ALineBreak + AIndent + '  ' + Caret;
  end;

  function TryFinally(const AFree: string): string;
  begin
    Result := 'try' + ALineBreak + AIndent + '  ' + Caret + ALineBreak + AIndent + 'finally' + ALineBreak + AIndent +
      '  ' + AFree + '.Free;' + ALineBreak + AIndent + 'end;';
  end;

begin
  Result := Default(TPostfixExpansion);
  if ATemplate.IsCustom then
  begin
    Result.Text := CustomText(ATemplate.Body, AExpr, AIndent, ALineBreak, ASnippet);
    Exit;
  end;
  Key := LowerCase(ATemplate.Key);
  if ASnippet then
  begin
    Expr := Escape(AExpr);
  end
  else
  begin
    Expr := AExpr;
  end;
  if (Key = 'for') or (Key = 'forin') then
  begin
    if AInlineVar then
    begin
      Body := 'for var ' + Field(1, ItemName) + ' in ' + Expr + ' do';
    end
    else
    begin
      // Der Name steht auch in der Deklaration; kein Platzhalter, der nur eine Stelle ändern würde.
      Body := 'for ' + ItemName + ' in ' + Expr + ' do';
      Result.Declaration := ClassicDeclaration(ATraits);
    end;
    Result.Text := Body + Next;
  end
  else if Key = 'tryf' then
  begin
    Result.Text := TryFinally(Expr);
  end
  else if (Key = 'ifa') or (Key = 'notnil') then
  begin
    Result.Text := 'if Assigned(' + Expr + ') then' + Next;
  end
  else if Key = 'nil' then
  begin
    Result.Text := 'if not Assigned(' + Expr + ') then' + Next;
  end
  else if Key = 'not' then
  begin
    Result.Text := 'not ' + Expr;
  end
  else if Key = 'if' then
  begin
    Result.Text := 'if ' + Expr + ' then' + Next;
  end
  else if Key = 'fmt' then
  begin
    Result.Text := 'Format(' + Expr + ', [' + Caret + '])';
  end
  else if Key = 'free' then
  begin
    Result.Text := 'FreeAndNil(' + Expr + ');';
  end
  else if Key = 'try' then
  begin
    Name := SuggestName(ATraits.TypeName);
    if AInlineVar then
    begin
      Body := 'var ' + Field(1, Name) + ' := ' + Expr + ';';
      if ASnippet then
      begin
        Name := '$1';
      end;
    end
    else
    begin
      Body := Name + ' := ' + Expr + ';';
      Result.Declaration := Name + ': ' + ATraits.TypeName + ';';
    end;
    Result.Text := Body + ALineBreak + AIndent + TryFinally(Name);
  end
  else if Key = 'var' then
  begin
    Name := SuggestName(ATraits.TypeName);
    if AInlineVar then
    begin
      Result.Text := 'var ' + Field(1, Name) + ' := ' + Expr + ';' + Caret;
    end
    else
    begin
      Result.Text := Name + ' := ' + Expr + ';';
      Result.Declaration := Name + ': ' + ATraits.TypeName + ';';
    end;
  end
  else if Key = 'exit' then
  begin
    Result.Text := 'Exit(' + Expr + ');';
  end
  else
  begin
    Result.Text := AExpr;
  end;
end;

class function TPostfixTemplates.CustomText(const ABody, AExpr, AIndent, ALineBreak: string;
  ASnippet: Boolean): string;
var
  Index, Close: Integer;
  Body: string;
  Ch: Char;
begin
  // Text der Vorlage: Zeilen mit #10, Folgezeilen mit der Einrückung der Cursorzeile.
  Body := ABody.Replace(#13#10, #10).Replace(#13, #10);
  Result := '';
  Index := 1;
  while Index <= Length(Body) do
  begin
    Ch := Body[Index];
    if Ch = #10 then
    begin
      Result := Result + ALineBreak + AIndent;
      Inc(Index);
    end
    else if (Ch = '$') and StartsText(ExprToken, Copy(Body, Index, Length(ExprToken))) then
    begin
      if ASnippet then
      begin
        Result := Result + Escape(AExpr);
      end
      else
      begin
        Result := Result + AExpr;
      end;
      Inc(Index, Length(ExprToken));
    end
    else if (Ch = '$') and (Index < Length(Body)) and (Body[Index + 1] = '$') then
    begin
      // "$$" steht für ein "$".
      if ASnippet then
      begin
        Result := Result + '\$';
      end
      else
      begin
        Result := Result + '$';
      end;
      Inc(Index, 2);
    end
    else if (Ch = '$') and (Index < Length(Body)) and CharInSet(Body[Index + 1], ['0'..'9']) then
    begin
      // $1 bzw. $0
      Close := Index + 1;
      while (Close <= Length(Body)) and CharInSet(Body[Close], ['0'..'9']) do
      begin
        Inc(Close);
      end;
      if ASnippet then
      begin
        Result := Result + Copy(Body, Index, Close - Index);
      end;
      Index := Close;
    end
    else if (Ch = '$') and (Index + 2 <= Length(Body)) and (Body[Index + 1] = '{') and
      CharInSet(Body[Index + 2], ['0'..'9']) then
    begin
      // ${1:Vorgabe} bzw. ${2}: Vorgabe bis zur schließenden Klammer.
      Close := PosEx('}', Body, Index);
      if Close = 0 then
      begin
        Close := Length(Body) + 1;
      end;
      if ASnippet then
      begin
        Result := Result + Copy(Body, Index, Close - Index + 1);
      end
      else if Pos(':', Copy(Body, Index, Close - Index)) > 0 then
      begin
        Result := Result + Copy(Body, PosEx(':', Body, Index) + 1, Close - PosEx(':', Body, Index) - 1);
      end;
      Index := Close + 1;
    end
    else
    begin
      if ASnippet and CharInSet(Ch, ['\', '$', '}']) then
      begin
        Result := Result + '\' + Ch;
      end
      else
      begin
        Result := Result + Ch;
      end;
      Inc(Index);
    end;
  end;
end;

class function TPostfixTemplates.ClassicDeclaration(const ATraits: TPostfixTraits): string;
begin
  Result := Format('%s: %s;', [ItemName, ATraits.ElementType]);
end;

class function TPostfixTemplates.SuggestName(const ATypeName: string): string;
var
  Text: string;
  Angle: Integer;
begin
  Text := Trim(ATypeName);
  Angle := Pos('<', Text);
  if StartsText('TArray<', Text) or StartsText('array ', Text) or StartsText('array[', Text) then
  begin
    Exit('Values');
  end;
  if Angle > 0 then
  begin
    Text := Copy(Text, 1, Angle - 1);
  end;
  if LastDelimiter('.', Text) > 0 then
  begin
    Text := Copy(Text, LastDelimiter('.', Text) + 1, MaxInt);
  end;
  // TStringList → StringList. Ohne T- oder I-Vorsatz (Integer, Tabelle) hieße die Variable wie ihr Typ.
  if (Length(Text) > 1) and CharInSet(Text[1], ['T', 'I']) and CharInSet(Text[2], ['A'..'Z']) then
  begin
    Text := Copy(Text, 2, MaxInt);
  end
  else
  begin
    Text := 'Value';
  end;
  Result := Text;
end;

class function TPostfixTemplates.ElementOf(const ATypeText: string): string;
var
  Text: string;
  OfPos: Integer;
begin
  Result := '';
  Text := Trim(ATypeText);
  if StartsText('TArray<', Text) and EndsStr('>', Text) then
  begin
    Exit(Trim(Copy(Text, Length('TArray<') + 1, Length(Text) - Length('TArray<') - 1)));
  end;
  if StartsText('array', Text) or StartsText('set ', Text) then
  begin
    OfPos := Pos(' OF ', UpperCase(Text));
    if OfPos > 0 then
    begin
      Result := Trim(Copy(Text, OfPos + Length(' of '), MaxInt));
    end;
    // array of const hat keinen Elementtyp, über den sich schreiben ließe.
    if SameText(Result, 'const') then
    begin
      Result := '';
    end;
  end;
end;

class function TPostfixTemplates.IsStringType(const ATypeText: string): Boolean;
begin
  Result := MatchText(Trim(ATypeText), ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'UTF8String', 'RawByteString', 'System.string', 'System.UnicodeString']);
end;

class function TPostfixTemplates.IsBooleanType(const ATypeText: string): Boolean;
begin
  Result := MatchText(Trim(ATypeText), ['Boolean', 'ByteBool', 'WordBool', 'LongBool', 'System.Boolean']);
end;

class function TPostfixTemplates.IsPointerType(const ATypeText: string): Boolean;
var
  Text: string;
begin
  Text := Trim(ATypeText);
  Result := MatchText(Text, ['Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte']) or StartsStr('^', Text);
end;

end.
