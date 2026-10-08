unit BDLsp.Common.Editing.PostfixTemplates;

// Postfix-Vorlagen (#188): Ein Kürzel hinter einem Ausdruck formt ihn um.
//   Liste.for   for var Item in Liste do   (klassisch: for Item in Liste do)
//   Obj.tryf    try … finally Obj.Free; end;
//   X.ifa       if Assigned(X) then
//   S.fmt       Format(S, [])
// Angeboten wird nur, was zum Typ passt; den Typ ermittelt die Vervollständigung
// über die Namensauflösung (#17) und übergibt ihn als TPostfixTraits. Diese Unit
// erzeugt nur Text.

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
    /// <summary>Elementtyp für die klassische for-in-Schleife; '' wenn unbekannt.</summary>
    ElementType: string;
  end;

  TPostfixTemplate = record
    Key: string;
    Description: string;
    /// <summary>Erzeugt eine Anweisung: nur, wenn der Ausdruck die Zeile beginnt.</summary>
    Statement: Boolean;
  end;

  TPostfixTemplates = class
  public const
    ItemName = 'Item';
  public
    class function Templates: TArray<TPostfixTemplate>; static;
    /// <summary>Passt AKey zum Typ? .for klassisch braucht zusätzlich den Elementtyp.</summary>
    class function Applies(const AKey: string; const ATraits: TPostfixTraits; AInlineVar: Boolean): Boolean; static;
    /// <summary>Ersatztext für AExpr.AKey; AIndent ist die Einrückung der Zeile.</summary>
    class function Expand(const AKey, AExpr, AIndent, ALineBreak: string; AInlineVar: Boolean): string; static;
    /// <summary>Deklaration für den var-Abschnitt bei .for ohne Inline-Variable, z. B. "Item: Integer;".</summary>
    class function ClassicDeclaration(const ATraits: TPostfixTraits): string; static;
    /// <summary>Elementtyp aus 'TArray&lt;T&gt;', 'array of T', 'array[..] of T', 'set of T'; '' sonst.</summary>
    class function ElementOf(const ATypeText: string): string; static;
    /// <summary>String-Typen.</summary>
    class function IsStringType(const ATypeText: string): Boolean; static;
    /// <summary>Zeigertypen: Pointer, ^T, PChar, PByte …</summary>
    class function IsPointerType(const ATypeText: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils;

{ TPostfixTemplates }

class function TPostfixTemplates.Templates: TArray<TPostfixTemplate>;

  function Template(const AKey, ADescription: string; AStatement: Boolean): TPostfixTemplate;
  begin
    Result.Key := AKey;
    Result.Description := ADescription;
    Result.Statement := AStatement;
  end;

begin
  Result := [Template('for', 'for … in … do', True), Template('tryf', 'try … finally Free end', True),
    Template('ifa', 'if Assigned(…) then', True), Template('fmt', 'Format(…, [])', False)];
end;

class function TPostfixTemplates.Applies(const AKey: string; const ATraits: TPostfixTraits;
  AInlineVar: Boolean): Boolean;
begin
  if SameText(AKey, 'for') then
    Result := ATraits.Enumerable and (AInlineVar or (ATraits.ElementType <> ''))
  else if SameText(AKey, 'tryf') then
    Result := ATraits.IsClass
  else if SameText(AKey, 'ifa') then
    Result := ATraits.IsReference
  else if SameText(AKey, 'fmt') then
    Result := ATraits.IsString
  else
    Result := False;
end;

class function TPostfixTemplates.Expand(const AKey, AExpr, AIndent, ALineBreak: string; AInlineVar: Boolean): string;
begin
  if SameText(AKey, 'for') then
  begin
    if AInlineVar then
      Result := Format('for var %s in %s do', [ItemName, AExpr])
    else
      Result := Format('for %s in %s do', [ItemName, AExpr]);
  end
  else if SameText(AKey, 'tryf') then
    Result := 'try' + ALineBreak + AIndent + '  ' + ALineBreak + AIndent + 'finally' + ALineBreak + AIndent + '  ' +
      AExpr + '.Free;' + ALineBreak + AIndent + 'end;'
  else if SameText(AKey, 'ifa') then
    Result := Format('if Assigned(%s) then', [AExpr])
  else if SameText(AKey, 'fmt') then
    Result := Format('Format(%s, [])', [AExpr])
  else
    Result := AExpr;
end;

class function TPostfixTemplates.ClassicDeclaration(const ATraits: TPostfixTraits): string;
begin
  Result := Format('%s: %s;', [ItemName, ATraits.ElementType]);
end;

class function TPostfixTemplates.ElementOf(const ATypeText: string): string;
var
  Text: string;
  OfPos: Integer;
begin
  Result := '';
  Text := Trim(ATypeText);
  if StartsText('TArray<', Text) and EndsStr('>', Text) then
    Exit(Trim(Copy(Text, Length('TArray<') + 1, Length(Text) - Length('TArray<') - 1)));
  if StartsText('array', Text) or StartsText('set ', Text) then
  begin
    OfPos := Pos(' OF ', UpperCase(Text));
    if OfPos > 0 then
      Result := Trim(Copy(Text, OfPos + Length(' of '), MaxInt));
    // array of const hat keinen Elementtyp, über den sich schreiben ließe.
    if SameText(Result, 'const') then
      Result := '';
  end;
end;

class function TPostfixTemplates.IsStringType(const ATypeText: string): Boolean;
begin
  Result := MatchText(Trim(ATypeText), ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'UTF8String', 'RawByteString', 'System.string', 'System.UnicodeString']);
end;

class function TPostfixTemplates.IsPointerType(const ATypeText: string): Boolean;
var
  Text: string;
begin
  Text := Trim(ATypeText);
  Result := MatchText(Text, ['Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte']) or StartsStr('^', Text);
end;

end.
