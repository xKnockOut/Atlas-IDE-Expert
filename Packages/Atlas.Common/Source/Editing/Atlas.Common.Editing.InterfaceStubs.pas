unit Atlas.Common.Editing.InterfaceStubs;

// Fehlende Interface-Methoden einer Klasse anlegen (#466), ohne Namensauflösung. Gemeinsamer Erzeuger für die
// Vervollständigung (#466), die Code-Aktion „Interface-Methoden implementieren“ (#42) und den Schnellbefehl
// /intf (#295):
//   - Split: Kopf und Direktiven einer Methodendeklaration ("procedure Name(...): T; stdcall;").
//   - Make: Deklaration für die Klasse (mit overload und Aufrufkonvention) und Rumpf wie bei #443, aber ohne
//     inherited; Funktionen setzen Result auf Default(<Typ>).
//   - LastSection: letzter Sichtbarkeitsabschnitt der Klasse; ist er der gewünschte, braucht es keinen neuen.
//   - ClassEdits: Abschnitt, Kommentar "{ IExporter }" und Deklaration vor dem "end" der Klasse. Alle Einfügungen
//     eines Interfaces stehen an derselben Stelle; Merge fasst sie zu einer Änderung zusammen und lässt
//     doppelte Abschnitte und Kommentare weg.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TInterfaceStub = record
    /// <summary>Deklarierendes Interface, z. B. "IExporter".</summary>
    InterfaceName: string;
    /// <summary>Name der Methode.</summary>
    Name: string;
    /// <summary>"procedure Export(const AFileName: string);" ohne Einrückung.</summary>
    Declaration: string;
    /// <summary>Rumpf "procedure TJsonExporter.Export(...);" bis "end;" mit ALineBreak, ohne Einrückung.</summary>
    Body: string;
  end;

  TInterfaceStubs = class
  public
    /// <summary>Kopf "Name(...): T" und Direktiven (klein, mit Leerzeichen umgeben, z. B. " virtual overload ")
    /// aus einer Methodendeklaration; AIsClass bei "class procedure". False ohne procedure bzw. function.</summary>
    class function Split(const ADeclaration: string; out AIsClass: Boolean; out AKind, AHead,
      ADirectives: string): Boolean; static;
    /// <summary>Ergebnistyp aus "Name(A: T): R" bzw. "Name: R"; '' bei Prozeduren.</summary>
    class function ReturnType(const AHead: string): string; static;
    /// <summary>Stub für eine Interface-Methode mit der Deklaration ADeclaration; False, wenn sie keine Methode ist.</summary>
    class function Make(const AInterfaceName, ATypeName, ADeclaration, ALineBreak: string;
      out AStub: TInterfaceStub): Boolean; static;
    /// <summary>Letzter Sichtbarkeitsabschnitt in einer Klassendeklaration zwischen den Zeilen AFirstLine und
    /// ALastLine (beide ausgeschlossen): "private", "strict protected", "public" ...; '' ohne.</summary>
    class function LastSection(const ATokens: TArray<TPascalToken>; AFirstLine, ALastLine: Integer): string; static;
    /// <summary>Einfügungen vor Zeile AEndLine (dem "end" der Klasse, eingerückt mit AIndent): mit AHeader der
    /// Abschnitt ASection, dann der Kommentar zum Interface und die Deklaration, eine Ebene tiefer.</summary>
    class function ClassEdits(const AStub: TInterfaceStub; AEndLine: Integer; const AIndent, ASection: string;
      AHeader: Boolean; const ALineBreak: string): TArray<TTextEdit>; static;
    /// <summary>Fasst Änderungen mit gleichem Bereich zusammen: Texte in der Reihenfolge des ersten Auftretens,
    /// gleiche Texte nur einmal. Bereiche bleiben in der Reihenfolge ihres ersten Auftretens.</summary>
    class function Merge(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions;

class function TInterfaceStubs.Split(const ADeclaration: string; out AIsClass: Boolean; out AKind, AHead,
  ADirectives: string): Boolean;
var
  Text: string;
  Index, Depth: Integer;
begin
  AKind := '';
  AHead := '';
  ADirectives := '';
  Text := Trim(ADeclaration);
  AIsClass := StartsText('class ', Text);
  if AIsClass then
    Text := TrimLeft(Copy(Text, 7, MaxInt));
  if StartsText('procedure ', Text) then
    AKind := 'procedure'
  else if StartsText('function ', Text) then
    AKind := 'function'
  else
    Exit(False);
  Text := TrimLeft(Copy(Text, Length(AKind) + 1, MaxInt));
  // Ende des Kopfs: erstes ";" außerhalb von Klammern.
  Depth := 0;
  for Index := 1 to Length(Text) do
    case Text[Index] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          AHead := Trim(Copy(Text, 1, Index - 1));
          ADirectives := ' ' + LowerCase(Copy(Text, Index + 1, MaxInt)).Replace(';', ' ') + ' ';
          Exit(AHead <> '');
        end;
    end;
  Result := False;
end;

class function TInterfaceStubs.ReturnType(const AHead: string): string;
var
  Index, Depth: Integer;
begin
  // Erster ":" außerhalb von Parameter- und Typparameterklammern.
  Depth := 0;
  for Index := 1 to Length(AHead) do
    case AHead[Index] of
      '(', '<': Inc(Depth);
      ')', '>': Dec(Depth);
      ':':
        if Depth = 0 then
          Exit(Trim(Copy(AHead, Index + 1, MaxInt)));
    end;
  Result := '';
end;

class function TInterfaceStubs.Make(const AInterfaceName, ATypeName, ADeclaration, ALineBreak: string;
  out AStub: TInterfaceStub): Boolean;
const
  // Bleiben in der Deklaration der Klasse; die Aufrufkonvention muss zu der des Interfaces passen.
  Kept: array[0..5] of string = ('overload', 'stdcall', 'safecall', 'cdecl', 'register', 'pascal');
var
  IsClass: Boolean;
  Kind, Head, Directives, Directive, ResultType, Name: string;
begin
  AStub := Default(TInterfaceStub);
  Result := Split(ADeclaration, IsClass, Kind, Head, Directives) and not IsClass;
  if not Result then
    Exit;
  // "Name(…): T", "Name: T", "Name<T>(…)": bis zum ersten Trennzeichen.
  Name := Head;
  if Pos('(', Name) > 0 then
    Name := Copy(Name, 1, Pos('(', Name) - 1);
  if Pos(':', Name) > 0 then
    Name := Copy(Name, 1, Pos(':', Name) - 1);
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  AStub.InterfaceName := AInterfaceName;
  AStub.Name := Trim(Name);
  AStub.Declaration := Kind + ' ' + Head + ';';
  for Directive in Kept do
    if Directives.Contains(' ' + Directive + ' ') then
      AStub.Declaration := AStub.Declaration + ' ' + Directive + ';';
  // Rumpf: Standardwerte stehen nur in der Deklaration.
  AStub.Body := Kind + ' ' + ATypeName + '.' + TRegEx.Replace(Head, '\s*=\s*[^;)]+', '') + ';' + ALineBreak +
    'begin' + ALineBreak;
  ResultType := ReturnType(Head);
  if (Kind = 'function') and (ResultType <> '') then
    AStub.Body := AStub.Body + '  Result := Default(' + ResultType + ');' + ALineBreak
  else
    AStub.Body := AStub.Body + ALineBreak;
  AStub.Body := AStub.Body + 'end;';
end;

class function TInterfaceStubs.LastSection(const ATokens: TArray<TPascalToken>; AFirstLine,
  ALastLine: Integer): string;
var
  Index, Previous: Integer;
  Word: string;
begin
  Result := '';
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].StartPos.Line <= AFirstLine then
      Continue;
    if ATokens[Index].StartPos.Line >= ALastLine then
      Break;
    if not (ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
      Continue;
    Word := LowerCase(ATokens[Index].Text);
    if not MatchStr(Word, ['private', 'protected', 'public', 'published']) then
      Continue;
    Previous := Index - 1;
    while (Previous >= 0) and (ATokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Previous);
    if (Previous >= 0) and SameText(ATokens[Previous].Text, 'strict') then
      Word := 'strict ' + Word;
    Result := Word;
  end;
end;

class function TInterfaceStubs.ClassEdits(const AStub: TInterfaceStub; AEndLine: Integer; const AIndent,
  ASection: string; AHeader: Boolean; const ALineBreak: string): TArray<TTextEdit>;
var
  Range: TTextRange;
begin
  Result := nil;
  Range := TTextRange.Create(AEndLine, 0, AEndLine, 0);
  if AHeader then
    Result := Result + [TTextEdit.Create(Range, AIndent + ASection + ALineBreak)];
  Result := Result + [TTextEdit.Create(Range, AIndent + '  { ' + AStub.InterfaceName + ' }' + ALineBreak),
    TTextEdit.Create(Range, AIndent + '  ' + AStub.Declaration + ALineBreak)];
end;

function SameRange(const A, B: TTextRange): Boolean;
begin
  Result := (A.StartPos.Line = B.StartPos.Line) and (A.StartPos.Character = B.StartPos.Character) and
    (A.EndPos.Line = B.EndPos.Line) and (A.EndPos.Character = B.EndPos.Character);
end;

class function TInterfaceStubs.Merge(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  Edit: TTextEdit;
  Index, Found: Integer;
  // Je Bereich die schon übernommenen Texte, mit #0 umschlossen.
  Seen: TArray<string>;
begin
  Result := nil;
  Seen := nil;
  for Edit in AEdits do
  begin
    Found := -1;
    for Index := 0 to High(Result) do
      if SameRange(Result[Index].Range, Edit.Range) then
      begin
        Found := Index;
        Break;
      end;
    if Found < 0 then
    begin
      Result := Result + [Edit];
      Seen := Seen + [#0 + Edit.NewText + #0];
      Continue;
    end;
    if Pos(#0 + Edit.NewText + #0, Seen[Found]) > 0 then
      Continue;
    Seen[Found] := Seen[Found] + Edit.NewText + #0;
    Result[Found].NewText := Result[Found].NewText + Edit.NewText;
  end;
end;

end.
