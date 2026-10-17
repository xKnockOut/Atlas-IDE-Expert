unit Atlas.Common.Editing.AssignFields;

// Alle Felder eines Records bzw. einer Klasse zuweisen (#491), ohne Namensauflösung:
//   - Merge, Writable: Aus den Mitgliedern des Typs (Vorfahren zuerst, in Deklarationsreihenfolge) die
//     öffentlich beschreibbaren Felder und Properties. Eine Property ohne Typ ("property Caption;") hebt nur
//     die Sichtbarkeit einer geerbten an und übernimmt deren Typ und Zugriff.
//   - KindOfText, DefaultValue: Vorgabe für den Platzhalter aus dem Typtext: 0, '', #0, False, nil, [] oder
//     der erste Aufzählungswert; sonst Default(T).
//   - AssignedAfter, Without: Felder, die die unmittelbar folgenden Zeilen schon zuweisen, fallen weg.
//   - Snippet, Plain, Line: der Text der Zuweisungen, als LSP-Snippet mit Platzhaltern oder als Klartext.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  /// <summary>Art des Werts für die Vorgabe im Platzhalter.</summary>
  TAssignValueKind = (Number, Text, Character, Boolean_, Reference, SetOf, Enum, Other);

  /// <summary>Mitglied des Typs, wie es die Namensauflösung liefert.</summary>
  TAssignMember = record
    Name: string;
    Kind: TIndexSymbolKind;
    /// <summary>Kopf der Deklaration wie im Index ("property Name: string read FName write SetName").</summary>
    Signature: string;
    /// <summary>Typ als Text, bei generischen Typen samt Argumenten.</summary>
    TypeName: string;
    Visibility: TIndexVisibility;
    /// <summary>Parameterzahl bei indizierten Properties.</summary>
    MaxArgs: Integer;
  end;

  /// <summary>Zuzuweisendes Feld mit der Vorgabe für den Platzhalter.</summary>
  TAssignField = record
    Name: string;
    TypeName: string;
    Value: string;
  end;

  TAssignFields = class
  public const
    /// <summary>Mehr Felder als so viele: zuerst die Liste mit Kontrollkästchen.</summary>
    ListThreshold = 15;
  public
    /// <summary>Mitglieder in Reihenfolge; eine Property ohne Typ ersetzt Sichtbarkeit und Signaturkopf der
    /// gleichnamigen geerbten an deren Stelle, gleichnamige spätere Einträge ersetzen frühere.</summary>
    class function Merge(const AMembers: TArray<TAssignMember>): TArray<TAssignMember>; static;
    /// <summary>Öffentliches Feld oder öffentliche, nicht indizierte Property mit write und Typ.</summary>
    class function Writable(const AMember: TAssignMember): Boolean; static;
    /// <summary>Art aus dem Typtext allein (eingebaute Typen, set of, Arrays, Zeiger, Methodenzeiger); False,
    /// wenn erst die Namensauflösung es klären kann.</summary>
    class function KindOfText(const ATypeName: string; out AKind: TAssignValueKind): Boolean; static;
    /// <summary>Vorgabe für AKind; AFirstValue ist bei Aufzählungen der erste Wert ('' = Default(T)).</summary>
    class function DefaultValue(AKind: TAssignValueKind; const ATypeName, AFirstValue: string): string; static;
    /// <summary>Namen, die die Zeilen direkt nach ALine (0-basiert) mit "AExpression.Name :=" zuweisen; leere
    /// Zeilen zählen mit, die erste andere Zeile beendet die Suche.</summary>
    class function AssignedAfter(const ALines: TArray<string>; ALine: Integer;
      const AExpression: string): TArray<string>; static;
    /// <summary>AFields ohne die Namen aus ANames (ohne Groß-/Kleinschreibung).</summary>
    class function Without(const AFields: TArray<TAssignField>;
      const ANames: TArray<string>): TArray<TAssignField>; static;
    /// <summary>"AExpression.Name := Wert;".</summary>
    class function Line(const AExpression: string; const AField: TAssignField): string; static;
    /// <summary>LSP-Snippet: Zeilen mit #10 ohne Einrückung, je Wert ein Platzhalter ${n:Wert}.</summary>
    class function Snippet(const AExpression: string; const AFields: TArray<TAssignField>): string; static;
    /// <summary>Klartext: Zeilen mit ALineBreak und AIndent davor (ab der zweiten).</summary>
    class function Plain(const AExpression, AIndent, ALineBreak: string;
      const AFields: TArray<TAssignField>): string; static;
    /// <summary>„Alle Felder zuweisen (n)“.</summary>
    class function Title(ACount: Integer): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions;

const
  NumberTypes: array[0..27] of string = ('integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'longint',
    'longword', 'shortint', 'smallint', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16',
    'uint32', 'fixedint', 'fixeduint', 'single', 'double', 'extended', 'real', 'currency', 'comp', 'tdatetime',
    'tdate');
  TextTypes: array[0..6] of string = ('string', 'unicodestring', 'ansistring', 'widestring', 'shortstring',
    'rawbytestring', 'utf8string');
  CharTypes: array[0..2] of string = ('char', 'ansichar', 'widechar');
  BooleanTypes: array[0..3] of string = ('boolean', 'bytebool', 'wordbool', 'longbool');
  ReferenceTypes: array[0..11] of string = ('pointer', 'pchar', 'pansichar', 'pwidechar', 'tobject', 'iinterface',
    'iunknown', 'tclass', 'tarray', 'tproc', 'tfunc', 'tpredicate');

/// <summary>Typtext ohne Unit-Präfix und Typargumente, klein.</summary>
function BareName(const ATypeName: string): string;
var
  Index: Integer;
begin
  Result := LowerCase(Trim(ATypeName));
  Index := Pos('<', Result);
  if Index > 0 then
    Result := Trim(Copy(Result, 1, Index - 1));
  Index := LastDelimiter('.', Result);
  if Index > 0 then
    Result := Copy(Result, Index + 1, MaxInt);
end;

/// <summary>Beginnt ein Typtext mit dem Wort AWord (nicht mit einem längeren Namen)?</summary>
function StartsWithWord(const AText, AWord: string): Boolean;
begin
  Result := StartsText(AWord, AText) and ((Length(AText) = Length(AWord)) or
    not CharInSet(AText[Length(AWord) + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

/// <summary>Teil der Signatur nach dem Namen: ab dem ersten ":" außerhalb von Klammern; '' ohne Typ.</summary>
function AfterName(const ASignature: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(ASignature) do
    case ASignature[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ':':
        if Depth = 0 then
          Exit(Copy(ASignature, Index + 1, MaxInt));
    end;
end;

class function TAssignFields.Merge(const AMembers: TArray<TAssignMember>): TArray<TAssignMember>;
var
  Member: TAssignMember;
  Index, Found: Integer;
begin
  Result := nil;
  for Member in AMembers do
  begin
    Found := -1;
    for Index := 0 to High(Result) do
      if SameText(Result[Index].Name, Member.Name) then
      begin
        Found := Index;
        Break;
      end;
    if Found < 0 then
      Result := Result + [Member]
    else if (Member.Kind = TIndexSymbolKind.Property_) and (Member.TypeName = '') and
      (Result[Found].Kind = TIndexSymbolKind.Property_) then
      // "property Caption;" im published-Abschnitt: Typ und Zugriff bleiben die geerbten.
      Result[Found].Visibility := Member.Visibility
    else
      Result[Found] := Member;
  end;
end;

class function TAssignFields.Writable(const AMember: TAssignMember): Boolean;
begin
  Result := (AMember.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and
    (AMember.TypeName <> '');
  if not Result then
    Exit;
  case AMember.Kind of
    TIndexSymbolKind.Field:
      Result := True;
    TIndexSymbolKind.Property_:
      Result := (AMember.MaxArgs = 0) and TRegEx.IsMatch(AfterName(AMember.Signature), '\bwrite\b',
        [roIgnoreCase]);
  else
    Result := False;
  end;
end;

class function TAssignFields.KindOfText(const ATypeName: string; out AKind: TAssignValueKind): Boolean;
var
  Text, Bare: string;
begin
  AKind := TAssignValueKind.Other;
  Result := True;
  Text := Trim(ATypeName);
  if Text.StartsWith('type ', True) then
    Text := Trim(Copy(Text, 6, MaxInt));
  Bare := BareName(Text);
  if StartsWithWord(Text, 'set') then
    AKind := TAssignValueKind.SetOf
  else if Text.StartsWith('^') or StartsWithWord(Text, 'array') or StartsWithWord(Text, 'procedure') or
    StartsWithWord(Text, 'function') or StartsWithWord(Text, 'reference') or StartsWithWord(Text, 'class') then
    AKind := TAssignValueKind.Reference
  else if StartsWithWord(Text, 'string') or (IndexText(Bare, TextTypes) >= 0) then
    AKind := TAssignValueKind.Text
  else if (IndexText(Bare, NumberTypes) >= 0) or SameText(Bare, 'ttime') then
    AKind := TAssignValueKind.Number
  else if IndexText(Bare, CharTypes) >= 0 then
    AKind := TAssignValueKind.Character
  else if IndexText(Bare, BooleanTypes) >= 0 then
    AKind := TAssignValueKind.Boolean_
  else if IndexText(Bare, ReferenceTypes) >= 0 then
    AKind := TAssignValueKind.Reference
  else
    Result := False;
end;

class function TAssignFields.DefaultValue(AKind: TAssignValueKind; const ATypeName, AFirstValue: string): string;
begin
  case AKind of
    TAssignValueKind.Number:
      Result := '0';
    TAssignValueKind.Text:
      Result := '''''';
    TAssignValueKind.Character:
      Result := '#0';
    TAssignValueKind.Boolean_:
      Result := 'False';
    TAssignValueKind.Reference:
      Result := 'nil';
    TAssignValueKind.SetOf:
      Result := '[]';
    TAssignValueKind.Enum:
      begin
        Result := AFirstValue;
        if Result = '' then
          Result := 'Default(' + Trim(ATypeName) + ')';
      end;
  else
    Result := 'Default(' + Trim(ATypeName) + ')';
  end;
end;

class function TAssignFields.AssignedAfter(const ALines: TArray<string>; ALine: Integer;
  const AExpression: string): TArray<string>;
var
  Pattern: string;
  Parts: TArray<string>;
  Index: Integer;
  Found: TMatch;
begin
  Result := nil;
  // "Opts . Inner" steht auch mit Leerzeichen um den Punkt da.
  Parts := AExpression.Split(['.']);
  for Index := 0 to High(Parts) do
    Parts[Index] := TRegEx.Escape(Trim(Parts[Index]));
  Pattern := '^\s*' + string.Join('\s*\.\s*', Parts) + '\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=';
  for Index := ALine + 1 to High(ALines) do
  begin
    if Trim(ALines[Index]) = '' then
      Continue;
    Found := TRegEx.Match(ALines[Index], Pattern, [roIgnoreCase]);
    if not Found.Success then
      Break;
    Result := Result + [Found.Groups[1].Value];
  end;
end;

class function TAssignFields.Without(const AFields: TArray<TAssignField>;
  const ANames: TArray<string>): TArray<TAssignField>;
var
  Field: TAssignField;
begin
  Result := nil;
  for Field in AFields do
    if IndexText(Field.Name, ANames) < 0 then
      Result := Result + [Field];
end;

class function TAssignFields.Line(const AExpression: string; const AField: TAssignField): string;
begin
  Result := AExpression + '.' + AField.Name + ' := ' + AField.Value + ';';
end;

/// <summary>Text für einen Platzhalter: "$", "}" und "\" mit "\" davor.</summary>
function Escaped(const AText: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 1 to Length(AText) do
  begin
    if CharInSet(AText[Index], ['$', '}', '\']) then
      Result := Result + '\';
    Result := Result + AText[Index];
  end;
end;

class function TAssignFields.Snippet(const AExpression: string; const AFields: TArray<TAssignField>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AFields) do
  begin
    if Index > 0 then
      Result := Result + #10;
    Result := Result + Escaped(AExpression) + '.' + Escaped(AFields[Index].Name) + ' := ${' +
      IntToStr(Index + 1) + ':' + Escaped(AFields[Index].Value) + '};';
  end;
end;

class function TAssignFields.Plain(const AExpression, AIndent, ALineBreak: string;
  const AFields: TArray<TAssignField>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AFields) do
  begin
    if Index > 0 then
      Result := Result + ALineBreak + AIndent;
    Result := Result + Line(AExpression, AFields[Index]);
  end;
end;

class function TAssignFields.Title(ACount: Integer): string;
begin
  Result := Format('Alle Felder zuweisen (%d)', [ACount]);
end;

end.
