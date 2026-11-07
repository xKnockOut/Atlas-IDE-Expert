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

  /// <summary>Wie die Ersetzung geschrieben wird.</summary>
  TPostfixLayout = record
    /// <summary>Einrückung der Zeile.</summary>
    Indent: string;
    LineBreak: string;
    /// <summary>Inline-Variablen erlaubt (Sprachversion und Einstellung).</summary>
    InlineVar: Boolean;
    /// <summary>LSP-Snippet mit Platzhaltern statt Klartext.</summary>
    Snippet: Boolean;
    class function Create(const AIndent, ALineBreak: string; AInlineVar, ASnippet: Boolean): TPostfixLayout;
      static;
  end;

  TPostfixTemplates = class
  public const
    cItemName = 'Item';
    cExprToken = '$expr';
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
    /// <summary>Ersatztext und Deklaration für AExpr.Kürzel, geschrieben nach ALayout.</summary>
    class function Expand(const ATemplate: TPostfixTemplate; const AExpr: string; const ATraits: TPostfixTraits;
      const ALayout: TPostfixLayout): TPostfixExpansion; overload; static;
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
  cConditions: array[0..7] of string = ('any', 'reference', 'class', 'string', 'boolean', 'enumerable',
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
  Result := (Trim(ACondition) <> '') and not MatchText(Trim(ACondition), cConditions);
end;

class function TPostfixTemplates.Applies(const ATemplate: TPostfixTemplate; const ATraits: TPostfixTraits;
  AInlineVar: Boolean; const ADescends: TFunc<string, Boolean>): Boolean;
var
  mCondition: string;
begin
  if not ATemplate.IsCustom then
  begin
    Exit(Applies(ATemplate.Key, ATraits, AInlineVar));
  end;
  mCondition := LowerCase(Trim(ATemplate.Condition));
  if (mCondition = '') or (mCondition = 'any') then
  begin
    Result := True;
  end
  else if mCondition = 'reference' then
  begin
    Result := ATraits.IsReference;
  end
  else if mCondition = 'class' then
  begin
    Result := ATraits.IsClass;
  end
  else if mCondition = 'string' then
  begin
    Result := ATraits.IsString;
  end
  else if mCondition = 'boolean' then
  begin
    Result := ATraits.IsBoolean;
  end
  else if mCondition = 'enumerable' then
  begin
    Result := ATraits.Enumerable;
  end
  else if mCondition = 'constructor' then
  begin
    Result := ATraits.IsConstructorCall;
  end
  else if mCondition = 'function' then
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
  mTemplate: TPostfixTemplate;
  mTraits: TPostfixTraits;
begin
  mTemplate := Default(TPostfixTemplate);
  mTemplate.Key := AKey;
  mTraits := Default(TPostfixTraits);
  Result := Expand(mTemplate, AExpr, mTraits, TPostfixLayout.Create(AIndent, ALineBreak, AInlineVar, False)).Text;
end;

{ TPostfixLayout }

class function TPostfixLayout.Create(const AIndent, ALineBreak: string; AInlineVar, ASnippet: Boolean):
  TPostfixLayout;
begin
  Result.Indent := AIndent;
  Result.LineBreak := ALineBreak;
  Result.InlineVar := AInlineVar;
  Result.Snippet := ASnippet;
end;

type
  /// <summary>Ersetzung einer eingebauten Vorlage.</summary>
  TPostfixExpander = record
    Layout: TPostfixLayout;
    Traits: TPostfixTraits;
    /// <summary>Ausdruck, im Snippet maskiert.</summary>
    Expr: string;
    /// <summary>Platzhalter ANumber mit Vorgabe ADefault; im Klartext nur die Vorgabe.</summary>
    function Field(ANumber: Integer; const ADefault: string): string;
    /// <summary>Endposition des Cursors.</summary>
    function Caret: string;
    /// <summary>Eingerückte Folgezeile nach einem Kopf wie "if … then".</summary>
    function Next: string;
    function TryFinally(const AFree: string): string;
    /// <summary>Vorlagen, die nur den Ausdruck einsetzen; False bei unbekanntem Kürzel.</summary>
    function Simple(const AKey: string; out AText: string): Boolean;
    function ForIn: TPostfixExpansion;
    function TryCreate: TPostfixExpansion;
    function NewVar: TPostfixExpansion;
  end;

function TPostfixExpander.Field(ANumber: Integer; const ADefault: string): string;
begin
  Result := ADefault;
  if Layout.Snippet then
  begin
    Result := Format('${%d:%s}', [ANumber, TPostfixTemplates.Escape(ADefault)]);
  end;
end;

function TPostfixExpander.Caret: string;
begin
  Result := '';
  if Layout.Snippet then
  begin
    Result := '$0';
  end;
end;

function TPostfixExpander.Next: string;
begin
  Result := Layout.LineBreak + Layout.Indent + '  ' + Caret;
end;

function TPostfixExpander.TryFinally(const AFree: string): string;
begin
  Result := 'try' + Layout.LineBreak + Layout.Indent + '  ' + Caret + Layout.LineBreak + Layout.Indent + 'finally' +
    Layout.LineBreak + Layout.Indent + '  ' + AFree + '.Free;' + Layout.LineBreak + Layout.Indent + 'end;';
end;

function TPostfixExpander.Simple(const AKey: string; out AText: string): Boolean;
begin
  Result := True;
  case IndexStr(AKey, ['tryf', 'ifa', 'notnil', 'nil', 'not', 'if', 'fmt', 'free', 'exit']) of
    0:
      AText := TryFinally(Expr);
    1, 2:
      AText := 'if Assigned(' + Expr + ') then' + Next;
    3:
      AText := 'if not Assigned(' + Expr + ') then' + Next;
    4:
      AText := 'not ' + Expr;
    5:
      AText := 'if ' + Expr + ' then' + Next;
    6:
      AText := 'Format(' + Expr + ', [' + Caret + '])';
    7:
      AText := 'FreeAndNil(' + Expr + ');';
    8:
      AText := 'Exit(' + Expr + ');';
  else
    AText := '';
    Result := False;
  end;
end;

function TPostfixExpander.ForIn: TPostfixExpansion;
begin
  Result := Default(TPostfixExpansion);
  if Layout.InlineVar then
  begin
    Result.Text := 'for var ' + Field(1, TPostfixTemplates.cItemName) + ' in ' + Expr + ' do' + Next;
  end
  else
  begin
    // Der Name steht auch in der Deklaration; kein Platzhalter, der nur eine Stelle ändern würde.
    Result.Text := 'for ' + TPostfixTemplates.cItemName + ' in ' + Expr + ' do' + Next;
    Result.Declaration := TPostfixTemplates.ClassicDeclaration(Traits);
  end;
end;

function TPostfixExpander.TryCreate: TPostfixExpansion;
var
  mName, mBody: string;
begin
  Result := Default(TPostfixExpansion);
  mName := TPostfixTemplates.SuggestName(Traits.TypeName);
  if Layout.InlineVar then
  begin
    mBody := 'var ' + Field(1, mName) + ' := ' + Expr + ';';
    if Layout.Snippet then
    begin
      mName := '$1';
    end;
  end
  else
  begin
    mBody := mName + ' := ' + Expr + ';';
    Result.Declaration := mName + ': ' + Traits.TypeName + ';';
  end;
  Result.Text := mBody + Layout.LineBreak + Layout.Indent + TryFinally(mName);
end;

function TPostfixExpander.NewVar: TPostfixExpansion;
var
  mName: string;
begin
  Result := Default(TPostfixExpansion);
  mName := TPostfixTemplates.SuggestName(Traits.TypeName);
  if Layout.InlineVar then
  begin
    Result.Text := 'var ' + Field(1, mName) + ' := ' + Expr + ';' + Caret;
  end
  else
  begin
    Result.Text := mName + ' := ' + Expr + ';';
    Result.Declaration := mName + ': ' + Traits.TypeName + ';';
  end;
end;

class function TPostfixTemplates.Expand(const ATemplate: TPostfixTemplate; const AExpr: string;
  const ATraits: TPostfixTraits; const ALayout: TPostfixLayout): TPostfixExpansion;
var
  mKey: string;
  mExpander: TPostfixExpander;
begin
  Result := Default(TPostfixExpansion);
  if ATemplate.IsCustom then
  begin
    Result.Text := CustomText(ATemplate.Body, AExpr, ALayout.Indent, ALayout.LineBreak, ALayout.Snippet);
    Exit;
  end;
  mKey := LowerCase(ATemplate.Key);
  mExpander := Default(TPostfixExpander);
  mExpander.Layout := ALayout;
  mExpander.Traits := ATraits;
  mExpander.Expr := AExpr;
  if ALayout.Snippet then
  begin
    mExpander.Expr := Escape(AExpr);
  end;
  if (mKey = 'for') or (mKey = 'forin') then
  begin
    Result := mExpander.ForIn;
  end
  else if mKey = 'try' then
  begin
    Result := mExpander.TryCreate;
  end
  else if mKey = 'var' then
  begin
    Result := mExpander.NewVar;
  end
  else if not mExpander.Simple(mKey, Result.Text) then
  begin
    Result.Text := AExpr;
  end;
end;

/// <summary>Platzhalter $1 bzw. $0 ab AIndex; im Snippet unverändert, im Klartext leer.</summary>
function NumberedPlaceholder(const ABody: string; var AIndex: Integer; ASnippet: Boolean): string;
var
  mClose: Integer;
begin
  mClose := AIndex + 1;
  while (mClose <= Length(ABody)) and CharInSet(ABody[mClose], ['0'..'9']) do
  begin
    Inc(mClose);
  end;
  Result := '';
  if ASnippet then
  begin
    Result := Copy(ABody, AIndex, mClose - AIndex);
  end;
  AIndex := mClose;
end;

/// <summary>${1:Vorgabe} bzw. ${2} ab AIndex: im Snippet unverändert, im Klartext die Vorgabe.</summary>
function BracedPlaceholder(const ABody: string; var AIndex: Integer; ASnippet: Boolean): string;
var
  mClose, mColon: Integer;
begin
  mClose := PosEx('}', ABody, AIndex);
  if mClose = 0 then
  begin
    mClose := Length(ABody) + 1;
  end;
  Result := '';
  mColon := PosEx(':', ABody, AIndex);
  if ASnippet then
  begin
    Result := Copy(ABody, AIndex, mClose - AIndex + 1);
  end
  else if (mColon > 0) and (mColon < mClose) then
  begin
    Result := Copy(ABody, mColon + 1, mClose - mColon - 1);
  end;
  AIndex := mClose + 1;
end;

/// <summary>Teil ab dem "$" an AIndex: $expr, $$, $1 oder ${1:…}; False, wenn dort kein Platzhalter steht.
/// </summary>
function DollarPart(const ABody, AExpr: string; var AIndex: Integer; ASnippet: Boolean; out APart: string):
  Boolean;
begin
  Result := True;
  if StartsText(TPostfixTemplates.cExprToken, Copy(ABody, AIndex, Length(TPostfixTemplates.cExprToken))) then
  begin
    APart := AExpr;
    if ASnippet then
    begin
      APart := TPostfixTemplates.Escape(AExpr);
    end;
    Inc(AIndex, Length(TPostfixTemplates.cExprToken));
  end
  else if (AIndex < Length(ABody)) and (ABody[AIndex + 1] = '$') then
  begin
    // "$$" steht für ein "$".
    APart := '$';
    if ASnippet then
    begin
      APart := '\$';
    end;
    Inc(AIndex, 2);
  end
  else if (AIndex < Length(ABody)) and CharInSet(ABody[AIndex + 1], ['0'..'9']) then
  begin
    APart := NumberedPlaceholder(ABody, AIndex, ASnippet);
  end
  else if (AIndex + 2 <= Length(ABody)) and (ABody[AIndex + 1] = '{') and CharInSet(ABody[AIndex + 2], ['0'..'9']) then
  begin
    APart := BracedPlaceholder(ABody, AIndex, ASnippet);
  end
  else
  begin
    APart := '';
    Result := False;
  end;
end;

class function TPostfixTemplates.CustomText(const ABody, AExpr, AIndent, ALineBreak: string;
  ASnippet: Boolean): string;
var
  mIndex: Integer;
  mBody, mPart: string;
  mChar: Char;
begin
  // Text der Vorlage: Zeilen mit #10, Folgezeilen mit der Einrückung der Cursorzeile.
  mBody := ABody.Replace(#13#10, #10).Replace(#13, #10);
  Result := '';
  mIndex := 1;
  while mIndex <= Length(mBody) do
  begin
    mChar := mBody[mIndex];
    if mChar = #10 then
    begin
      Result := Result + ALineBreak + AIndent;
    end
    else if (mChar = '$') and DollarPart(mBody, AExpr, mIndex, ASnippet, mPart) then
    begin
      Result := Result + mPart;
      Continue;
    end
    else if ASnippet and CharInSet(mChar, ['\', '$', '}']) then
    begin
      Result := Result + '\' + mChar;
    end
    else
    begin
      Result := Result + mChar;
    end;
    Inc(mIndex);
  end;
end;

class function TPostfixTemplates.ClassicDeclaration(const ATraits: TPostfixTraits): string;
begin
  Result := Format('%s: %s;', [cItemName, ATraits.ElementType]);
end;

class function TPostfixTemplates.SuggestName(const ATypeName: string): string;
var
  mText: string;
  mAngle: Integer;
begin
  mText := Trim(ATypeName);
  mAngle := Pos('<', mText);
  if StartsText('TArray<', mText) or StartsText('array ', mText) or StartsText('array[', mText) then
  begin
    Exit('Values');
  end;
  if mAngle > 0 then
  begin
    mText := Copy(mText, 1, mAngle - 1);
  end;
  if LastDelimiter('.', mText) > 0 then
  begin
    mText := Copy(mText, LastDelimiter('.', mText) + 1, MaxInt);
  end;
  // TStringList → StringList. Ohne T- oder I-Vorsatz (Integer, Tabelle) hieße die Variable wie ihr Typ.
  if (Length(mText) > 1) and CharInSet(mText[1], ['T', 'I']) and CharInSet(mText[2], ['A'..'Z']) then
  begin
    mText := Copy(mText, 2, MaxInt);
  end
  else
  begin
    mText := 'Value';
  end;
  Result := mText;
end;

class function TPostfixTemplates.ElementOf(const ATypeText: string): string;
var
  mText: string;
  mOfPos: Integer;
begin
  Result := '';
  mText := Trim(ATypeText);
  if StartsText('TArray<', mText) and EndsStr('>', mText) then
  begin
    Exit(Trim(Copy(mText, Length('TArray<') + 1, Length(mText) - Length('TArray<') - 1)));
  end;
  if StartsText('array', mText) or StartsText('set ', mText) then
  begin
    mOfPos := Pos(' OF ', UpperCase(mText));
    if mOfPos > 0 then
    begin
      Result := Trim(Copy(mText, mOfPos + Length(' of '), MaxInt));
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
  mText: string;
begin
  mText := Trim(ATypeText);
  Result := MatchText(mText, ['Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte']) or StartsStr('^', mText);
end;

end.
